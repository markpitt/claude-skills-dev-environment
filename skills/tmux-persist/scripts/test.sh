#!/usr/bin/env bash
# Tests for tmux-session against a private tmux server (-L). Needs tmux; touches nothing of yours.
#   bash scripts/test.sh
set -u
S=$(cd "$(dirname "$0")" && pwd)/tmux-session.sh
D=$(mktemp -d); SOCK=tmux-persist-test-$$
trap 'tmux -L "$SOCK" kill-server 2>/dev/null; rm -rf "$D"' EXIT
export SHELL=/bin/bash   # a fast, predictable shell for the panes
export XDG_CONFIG_HOME=$D/cfg   # keep your own ~/.config/tmux-session/env out of the test
export TMUX_SESSION_SOCKET=$SOCK TMUX_SESSION_STATE_DIR=$D/state TMUX_SESSION_WAIT_HOST=localhost
pass=0 fail=0
ok() { echo "ok    $1"; pass=$((pass+1)); }
no() { echo "FAIL  $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else no "$1"; fi; }
T() { tmux -L "$SOCK" "$@"; }

# A stand-in for `claude` (prints its arguments) and a wrapper script that execs nothing, like a launcher alias.
mkdir -p "$D/bin"
printf '#!/usr/bin/env bash\necho "ARGS:$*"; sleep 300\n' >"$D/bin/claude"
printf '#!/usr/bin/env bash\n%s/claude remote-control --name wrapped "$@"\n' "$D/bin" >"$D/bin/my-agent"
chmod +x "$D/bin/claude" "$D/bin/my-agent"

# 1. snapshot a pane running claude remote-control, restore after the server is gone
export TMUX_SESSION_PROGRAMS="claude my-agent"
T new-session -d -s one -x 300 -y 30 -c "$D" "$D/bin/claude remote-control --name one; sleep 300"
T new-window -d -t one: -n w2 -c "$D" "$D/bin/my-agent; sleep 300"
sleep 1
bash "$S" snapshot 2>/dev/null
check "snapshot records both panes"            '[ "$(wc -l <"$D/state/sessions.tsv")" = 2 ]'
check "wrapper script recorded by path"        'cut -f9 "$D/state/sessions.tsv" | grep -q "^$D/bin/my-agent"'
check "no bash/env interpreter recorded"       '! cut -f9 "$D/state/sessions.tsv" | grep -Eq "^(bash|sh|/usr/bin/env)( |$)"'
T kill-server; sleep 0.5
bash "$S" restore 2>/dev/null
sleep 3
out=$(T capture-pane -p -t one:0; T capture-pane -p -t one:1)
check "restore recreates the session"          'T has-session -t =one'
check "restored command waits for DNS first"   'grep -q "wait-dns" <<<"$out"'
check "restored command has no --continue"     '! grep -q -- "--continue" <<<"$out"'
check "claude gets the recorded arguments"     'grep -q "ARGS:remote-control --name one" <<<"$out"'
check "wrapper pane is re-run"                 'grep -q "ARGS:remote-control --name wrapped" <<<"$out"'

# 2. a program that is not allowlisted is not re-run
T kill-server; sleep 0.5
export TMUX_SESSION_PROGRAMS="claude"
bash "$S" restore 2>"$D/err" >/dev/null; sleep 1
check "non-allowlisted wrapper is not re-run"  '! T capture-pane -p -t one:1 | grep -q "ARGS:"'
check "log says why"                           'grep -q "not re-running" "$D/err"'

# 3. an agent with a .no-autostart file is not re-run; one without is
mkdir -p "$D/sb/off" "$D/sb/on"; touch "$D/sb/off/.no-autostart"
for n in off on; do printf '#!/usr/bin/env bash\necho "STARTED:%s"; sleep 300\n' "$n" >"$D/bin/$n-agent"; chmod +x "$D/bin/$n-agent"; done
T kill-server 2>/dev/null; sleep 0.5
export TMUX_SESSION_PROGRAMS="on-agent off-agent"
T new-session -d -s ag -x 300 -y 30 -c "$D" "$D/bin/on-agent; sleep 300"
T new-window -d -t ag: -n w2 -c "$D" "$D/bin/off-agent; sleep 300"
sleep 1; bash "$S" snapshot 2>/dev/null; T kill-server; sleep 0.5
export TMUX_SESSION_NO_AUTOSTART_DIR=$D/sb
bash "$S" restore 2>"$D/err" >/dev/null; sleep 2
check "agent without .no-autostart is re-run"   'T capture-pane -p -t ag:0 | grep -q "STARTED:on"'
check "agent with .no-autostart is not re-run"  'T list-windows -t ag -F "#{window_index}" | grep -qx 1 && ! T capture-pane -p -t ag:1 | grep -q "STARTED:off"'
check "log names the .no-autostart"             'grep -q "no-autostart" "$D/err"'
T kill-server; sleep 0.5; unset TMUX_SESSION_NO_AUTOSTART_DIR
bash "$S" restore 2>/dev/null >/dev/null; sleep 2
check "without the variable the file is ignored" 'T capture-pane -p -t ag:1 | grep -q "STARTED:off"'

# 4. both window layout formats restore at their recorded size: classic "csum,WxH,X,Y,..." and tmux 3.8's JSON
T kill-server 2>/dev/null; sleep 0.5
export TMUX_SESSION_PROGRAMS="claude"
TAB=$'\t'
{
  printf 'classic%s0%sw%sb25d,123x31,0,0,0%s1%s0%s1%s%s%s\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$D" "$TAB"
  printf 'json%s0%sw%s{"V":2,"L":{"t":"h","w":157,"h":41,"x":0,"y":0,"c":[{"t":"p","w":78,"h":41,"x":0,"y":0,"i":0},{"t":"p","w":78,"h":41,"x":79,"y":0,"i":1}]}}%s1%s0%s1%s%s%s\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$D" "$TAB"
} >"$D/state/sessions.tsv"
bash "$S" restore 2>"$D/err" >/dev/null; rc=$?; sleep 1
check "restore succeeds on both layout formats"  '[ "$rc" = 0 ]'
check "no width error"                           '! grep -q "width invalid" "$D/err"'
check "classic layout session restored"          'T has-session -t =classic'
check "JSON layout session restored"             'T has-session -t =json'
check "JSON layout restored at its width"        '[ "$(T display-message -p -t json:0 "#{window_width}")" = 157 ]'
T kill-server 2>/dev/null
printf 'bad%s0%sw%s{"V":2}%s1%s0%s1%s%s%s\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$D" "$TAB" >"$D/state/sessions.tsv"
bash "$S" restore 2>/dev/null >/dev/null; sleep 1
check "unparseable layout falls back, still restores" 'T has-session -t =bad'

# 5. a later window with more panes than halving the newest pane can fit in the session's 80x24 still restores whole
T kill-server 2>/dev/null; sleep 0.5
{
  printf 'many%s0%ssmall%sb25d,80x24,0,0,0%s0%s0%s1%s%s%s\n' "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$TAB" "$D" "$TAB"
  for i in 0 1 2 3 4 5; do
    printf 'many%s1%sbig%s{"V":2,"L":{"t":"p","w":211,"h":49,"x":0,"y":0}}%s1%s%s%s%s%s%s\n' "$TAB" "$TAB" "$TAB" "$TAB" "$i" "$TAB" "$([ $i = 0 ] && echo 1 || echo 0)" "$TAB" "$D" "$TAB"
  done
} >"$D/state/sessions.tsv"
bash "$S" restore 2>"$D/err" >/dev/null; rc=$?; sleep 1
check "restore succeeds with six panes in a later window" '[ "$rc" = 0 ]'
check "all six panes restored"                     '[ "$(T list-panes -t many:1 | wc -l)" = 6 ]'
check "no 'no space for a new pane'"               '! grep -q "no space" "$D/err"'

echo "---"; echo "$pass passed, $fail failed"; [ "$fail" = 0 ]
