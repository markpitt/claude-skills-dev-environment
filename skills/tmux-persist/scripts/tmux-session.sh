#!/usr/bin/env bash
# tmux-session: save the layout of the running tmux server and rebuild it after a reboot.
#
#   tmux-session snapshot   save every session/window/pane (cwd, layout, foreground command)
#   tmux-session restore    recreate sessions from the snapshot; live sessions are never touched
#   tmux-session show       print the snapshot
#   tmux-session wait-dns [host]   block until a name resolves (used by restored network programs)
#   tmux-session install    copy this script + systemd user units, enable timer and boot restore
#
# What is saved: layout and working directories, plus the foreground command of each pane,
# which is re-run only when its program is on the allowlist (TMUX_SESSION_PROGRAMS).
# `claude remote-control ...` is re-run as recorded, after waiting for DNS (no --continue: it limits the
# directory to one session, and remote-control allows many).
# Not saved: scrollback, shell history, unsaved state inside programs.
set -euo pipefail

[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-session/env" ] && . "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-session/env"

STATE_DIR=${TMUX_SESSION_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session}
FILE=$STATE_DIR/sessions.tsv
PROGRAMS=${TMUX_SESSION_PROGRAMS:-"claude btop htop top less tail watch journalctl"}
NO_AUTOSTART_DIR=${TMUX_SESSION_NO_AUTOSTART_DIR:-}   # optional: <dir>/<name>/.no-autostart stops a pane running `<name>-agent` from being re-run
SOCKET=${TMUX_SESSION_SOCKET:-}   # tests only: use `tmux -L <name>`
TAB=$'\t'

# systemd's user PATH is minimal (no mise/asdf/~/.local/bin), so find tmux explicitly.
TMUX_BIN=${TMUX_BIN:-$(command -v tmux || true)}
if [ -z "$TMUX_BIN" ]; then
  for c in "$HOME/.local/share/mise/shims/tmux" "$HOME/.local/bin/tmux" /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux; do
    [ -x "$c" ] && { TMUX_BIN=$c; break; }
  done
fi
[ -n "$TMUX_BIN" ] || { echo "tmux-session: tmux not found (set TMUX_BIN in ~/.config/tmux-session/env)" >&2; exit 1; }

t() { if [ -n "$SOCKET" ]; then "$TMUX_BIN" -L "$SOCKET" "$@"; else "$TMUX_BIN" "$@"; fi; }
log() { echo "tmux-session: $*" >&2; }

# Foreground command of a pane, other than its shell: "<shell pid> <tty>" -> command line.
fg_command() {
  ps -t "${2#/dev/}" -o pid=,stat=,args= 2>/dev/null |
    awk -v shell="$1" '$1 != shell && $2 ~ /\+/ { $1 = ""; $2 = ""; sub(/^ +/, ""); print; exit }' |
    tr -d '\t' | unwrap_interpreter
}

# A wrapper script run as `bash /path/to/tool args` (or sh/python3 ...) is recorded as `/path/to/tool args`,
# so the allowlist can name the tool rather than the interpreter.
unwrap_interpreter() {
  local line; IFS= read -r line || return 0
  case "${line%% *}" in
    bash|sh|dash|zsh|/bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh|/usr/bin/env)
      local rest=${line#* }
      [ "$rest" != "$line" ] && case "$rest" in
        /*|./*|~/*) [ -x "${rest%% *}" ] && line=$rest ;;
      esac ;;
  esac
  printf '%s\n' "$line"
}

# layout_size LAYOUT: set cols and rows from a window layout, either the classic "csum,WxH,X,Y..." string or the
# JSON form tmux 3.8 writes ({"V":2,"L":{"t":"p","w":W,"h":H,...}}); 80x24 when neither parses.
layout_size() {
  local l=$1 w h
  if [[ $l == "{"* ]]; then
    [[ $l =~ \"L\":\{[^{}]*\"w\":([0-9]+) ]] && w=${BASH_REMATCH[1]}
    [[ $l =~ \"L\":\{[^{}]*\"h\":([0-9]+) ]] && h=${BASH_REMATCH[1]}
  else
    local size=${l#*,}; size=${size%%,*}; w=${size%x*}; h=${size#*x}
  fi
  [[ ${w:-} =~ ^[0-9]+$ && ${h:-} =~ ^[0-9]+$ ]] || { w=80; h=24; }
  cols=$w rows=$h
}

snapshot() {
  t list-sessions >/dev/null 2>&1 || { log "no tmux server running; snapshot unchanged"; return 0; }
  mkdir -p "$STATE_DIR"
  local tmp; tmp=$(mktemp "$STATE_DIR/.snap.XXXXXX")
  # tmux 3.4 prints a tab inside -F output as "_", so ask for a printable separator and turn it into tabs.
  local S='|~tmux-session~|'
  local fmt="#{session_name}$S#{window_index}$S#{window_name}$S#{window_layout}$S#{window_active}$S#{pane_index}$S#{pane_active}$S#{pane_current_path}$S#{pane_pid}$S#{pane_tty}"
  local sess widx wname layout wact pidx pact cwd pid tty
  while IFS=$'\t' read -r sess widx wname layout wact pidx pact cwd pid tty; do
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sess" "$widx" "$wname" "$layout" "$wact" "$pidx" "$pact" "$cwd" "$(fg_command "$pid" "$tty")" >>"$tmp"
  done < <(t list-panes -a -F "$fmt" | sed "s/|~tmux-session~|/\t/g")
  if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 0; fi
  if [ -f "$FILE" ] && cmp -s "$tmp" "$FILE"; then rm -f "$tmp"; return 0; fi
  [ -f "$FILE" ] && cp -f "$FILE" "$FILE.prev"
  mv -f "$tmp" "$FILE"
  log "saved $(wc -l <"$FILE") panes to $FILE"
}

allowed() {  # allowed "<command line>": first word's basename is on the allowlist
  local first=${1%% *} p
  first=${first##*/}
  for p in $PROGRAMS; do [ "$p" = "$first" ] && return 0; done
  return 1
}

# At boot the only resolver is the local AdGuard container (/etc/resolv.conf: 127.0.0.1), which comes
# up several seconds AFTER this restore runs. A program that needs the network would fail with
# "getaddrinfo ENOTFOUND", so the typed command waits for a name to resolve first.
wait_dns() {  # wait_dns [host]: return 0 once the name resolves, 1 after the timeout
  local host=${1:-${TMUX_SESSION_WAIT_HOST:-api.anthropic.com}}
  local max=${TMUX_SESSION_WAIT_SECONDS:-600} waited=0
  while ! getent hosts "$host" >/dev/null 2>&1; do
    [ "$waited" -eq 0 ] && echo "tmux-session: waiting for DNS ($host)..." >&2
    [ "$waited" -ge "$max" ] && { echo "tmux-session: DNS ($host) still not resolving after ${max}s; carrying on" >&2; return 1; }
    sleep 3; waited=$((waited + 3))
  done
  [ "$waited" -gt 0 ] && echo "tmux-session: DNS up after ${waited}s" >&2
  return 0
}

# `claude remote-control` needs DNS, which is not up yet right after boot, so wait for it first.
# Never add --continue: it allows only one session per directory, while plain remote-control allows many.
resume_variant() {  # resume_variant "<command line>" -> command line to type
  local cmd=$1 first rest self
  first=${cmd%% *}; first=${first##*/}
  rest=${cmd#* }
  if [ "$first" = claude ] && [ "${rest%% *}" = remote-control ]; then
    self=$(readlink -f "$0")
    cmd="bash '$self' wait-dns; $cmd"
  fi
  printf '%s' "$cmd"
}

# no_autostart CMD: true when TMUX_SESSION_NO_AUTOSTART_DIR is set, the command's program is `<name>-agent` and
# <dir>/<name>/.no-autostart exists (a per-agent marker: that agent is not started automatically).
no_autostart() {
  [ -n "$NO_AUTOSTART_DIR" ] || return 1
  local first=${1%% *}; first=${first##*/}
  local name=${first%-agent}
  case $first in *-agent) [ -n "$name" ] && [ -e "$NO_AUTOSTART_DIR/$name/.no-autostart" ] ;; *) return 1 ;; esac
}

# Per-window state while reading the snapshot.
W_ID="" W_LAYOUT="" W_ACTIVE=0 W_ACTIVE_PANE=""
W_PANES=() W_CMDS=()

flush_window() {
  [ -n "$W_ID" ] || return 0
  t select-layout -t "$W_ID" "$W_LAYOUT" >/dev/null 2>&1 || log "could not apply layout to $W_ID"
  t set-option -w -u -t "$W_ID" window-size >/dev/null 2>&1 || true   # undo resize-window's manual size so the window follows its client
  local i cmd
  for i in "${!W_PANES[@]}"; do
    cmd=${W_CMDS[$i]}
    if [ -n "$cmd" ]; then
      if no_autostart "$cmd"; then
        log "not re-running '$cmd' (.no-autostart in $NO_AUTOSTART_DIR)"
      elif allowed "$cmd"; then
        cmd=$(resume_variant "$cmd")
        t send-keys -t "${W_PANES[$i]}" -l -- "$cmd"
        t send-keys -t "${W_PANES[$i]}" Enter
      else
        log "not re-running '$cmd' (add its program to TMUX_SESSION_PROGRAMS to allow)"
      fi
    fi
  done
  [ -n "$W_ACTIVE_PANE" ] && t select-pane -t "$W_ACTIVE_PANE"
  [ "$W_ACTIVE" = 1 ] && t select-window -t "$W_ID"
  W_ID="" W_LAYOUT="" W_ACTIVE=0 W_ACTIVE_PANE="" W_PANES=() W_CMDS=()
}

restore() {
  [ -s "$FILE" ] || { log "no snapshot at $FILE; nothing to restore"; return 0; }
  local -A skip=() started=()
  local sess widx wname layout wact pidx pact cwd cmd
  local cur_sess="" cur_win="" size cols rows paneid actual created=0
  while IFS=$'\t' read -r sess widx wname layout wact pidx pact cwd cmd; do
    [ -n "${skip[$sess]:-}" ] && continue
    if [ "$sess" != "$cur_sess" ]; then
      flush_window
      cur_sess=$sess cur_win=""
      if [ -z "${started[$sess]:-}" ] && t has-session -t "=$sess" 2>/dev/null; then
        skip[$sess]=1; log "session '$sess' already running; left alone"; continue
      fi
    fi
    [ -d "$cwd" ] || cwd=$HOME
    if [ "$widx" != "$cur_win" ]; then
      flush_window
      cur_win=$widx
      layout_size "$layout"
      if [ -z "${started[$sess]:-}" ]; then
        W_ID=$(t new-session -d -s "$sess" -n "$wname" -c "$cwd" -x "$cols" -y "$rows" -P -F '#{window_id}')
        started[$sess]=1; created=$((created + 1))
      else
        W_ID=$(t new-window -d -t "$sess:" -n "$wname" -c "$cwd" -P -F '#{window_id}')
        t resize-window -t "$W_ID" -x "$cols" -y "$rows" >/dev/null 2>&1 || true   # a new window takes the session's size, not its own
      fi
      actual=$(t display-message -p -t "$W_ID" '#{window_index}')
      [ "$actual" = "$widx" ] || t move-window -d -s "$W_ID" -t "$sess:$widx" 2>/dev/null || true
      W_LAYOUT=$layout W_ACTIVE=$wact
      paneid=$(t display-message -p -t "$W_ID" '#{pane_id}')
    else
      # Split the newest pane so pane order matches the snapshot (select-layout assigns by order).
      if ! paneid=$(t split-window -d -t "${W_PANES[-1]}" -c "$cwd" -P -F '#{pane_id}' 2>/dev/null); then
        t select-layout -t "$W_ID" tiled >/dev/null 2>&1   # halving the newest pane ran out of room: spread the panes, try again
        if ! paneid=$(t split-window -d -t "${W_PANES[-1]}" -c "$cwd" -P -F '#{pane_id}' 2>/dev/null); then
          log "no room for pane $pidx of $sess:$widx; skipped"
          continue
        fi
      fi
    fi
    W_PANES+=("$paneid") W_CMDS+=("$cmd")
    [ "$pact" = 1 ] && W_ACTIVE_PANE=$paneid
  done <"$FILE"
  flush_window
  log "restored $created session(s) from $FILE"
}

install_units() {
  local src; src=$(dirname "$(readlink -f "$0")")
  local unit_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
  mkdir -p "$HOME/.local/bin" "$unit_dir"
  install -m 755 "$src/tmux-session.sh" "$HOME/.local/bin/tmux-session"
  install -m 644 "$src"/systemd/*.service "$src"/systemd/*.timer "$unit_dir/"
  systemctl --user daemon-reload
  # Save the current layout before anything else can touch it.
  "$HOME/.local/bin/tmux-session" snapshot
  systemctl --user enable --now tmux-session-snapshot.timer
  systemctl --user enable --now tmux-session.service
  if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]; then
    log "WARNING: linger is off, so the restore will only run at your first login."
    log "         Fix: sudo loginctl enable-linger $USER"
  fi
  systemctl --user list-timers tmux-session-snapshot.timer --no-pager
}

case "${1:-}" in
  snapshot) snapshot ;;
  restore) restore ;;
  wait-dns) shift; wait_dns "${1:-}" ;;
  show) column -t -s "$TAB" "$FILE" 2>/dev/null || cat "$FILE" ;;
  install) install_units ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
