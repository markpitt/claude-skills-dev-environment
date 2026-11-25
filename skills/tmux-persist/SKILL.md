---
name: tmux-persist
description: Keep tmux sessions across reboots on any Linux machine. Saves every session/window/pane layout (cwd + foreground command) every 5 min and at stop, and rebuilds them at boot via systemd user units. Use when asked to set up tmux persistence on a new server, check or repair it, add a program to the re-run allowlist, or recover tmux sessions after a reboot.
license: Apache-2.0
metadata:
  version: "1.0.3"
---

# tmux-persist

Self-contained: `scripts/tmux-session.sh` plus `scripts/systemd/` units. No tmux plugins, no root. Needs tmux, a systemd user instance and bash.

## Install on a machine
1. Get this skill directory onto the machine (clone this repository, install the skill zip, or `scp -r`).
2. Run `bash scripts/tmux-session.sh install` as the normal user (not root). It copies the script to `~/.local/bin/tmux-session`, the units to `~/.config/systemd/user/`, saves the current layout, and enables (the installed copy is executable, so it runs as `tmux-session`):
   - `tmux-session.service`: at boot runs `restore`; on stop runs `snapshot`.
   - `tmux-session-snapshot.timer`: `snapshot` 2 min after boot, then every 5 min.
3. Linger must be on so user units start at boot, not at first login: `loginctl show-user $USER -p Linger` (fix: `sudo loginctl enable-linger $USER`). The installer warns if it is off.
4. Optionally link the skill: `ln -s <path>/tmux-persist ~/.claude/skills/tmux-persist`.

## How it behaves
- Snapshot file: `~/.local/state/tmux-session/sessions.tsv` (previous copy `.prev`). One row per pane: session, window index/name, layout string, active flags, pane index, cwd, foreground command. `tmux-session show` prints it.
- `restore` recreates only sessions that do not exist; a live session is never touched, so running it twice is safe. Layout, cwd, active window/pane come back exactly.
- The foreground command is re-typed into the pane's shell **only if its program is on the allowlist** (default `claude btop htop top less tail watch journalctl`). Anything else is logged and the pane is left at a shell prompt. Re-typing (not exec) means the shell's own PATH (mise etc.) applies and the pane survives the program exiting.
- Extend the allowlist or pin the tmux binary in `~/.config/tmux-session/env`:
  ```
  TMUX_SESSION_PROGRAMS="claude btop htop top less tail watch journalctl nvim"
  TMUX_BIN=/path/to/tmux
  ```
- Optional: `TMUX_SESSION_NO_AUTOSTART_DIR=$HOME/sandboxes` makes restore skip a pane running `<name>-agent` when `<dir>/<name>/.no-autostart` exists (the sandboxed-agent convention). Unset by default: the file is ignored. A skipped pane comes back as a plain shell, so the next snapshot records no program for it: removing `.no-autostart` later does not bring the agent back at the next reboot, start it by hand.
- No snapshot is written when no tmux server runs, so a reboot never overwrites the saved layout with nothing. A session you kill on purpose stays in the snapshot until another session changes it; delete the row (or the file) to forget it.
- Not saved: scrollback, shell history, program state (an editor's unsaved buffers, an SSH hop). `claude remote-control` panes are re-typed as recorded after waiting for DNS. `--continue` is deliberately not added: it limits a directory to one session, whereas plain remote-control allows many.
- Those panes first run `tmux-session wait-dns`, which blocks until `api.anthropic.com` resolves (10 minute cap; `TMUX_SESSION_WAIT_HOST` and `TMUX_SESSION_WAIT_SECONDS` override). At boot the restore can run before the machine's resolver is up, for example when `/etc/resolv.conf` points at a local DNS container such as AdGuard or Pi-hole, and the first attempt then fails with `getaddrinfo ENOTFOUND`.

## Operate / debug
- Status: `systemctl --user status tmux-session.service tmux-session-snapshot.timer`; logs: `journalctl --user -u tmux-session -u tmux-session-snapshot -b`.
- Dry check of what a reboot would rebuild: `tmux-session show`.
- Test a restore without touching the real server: `TMUX_SESSION_SOCKET=test TMUX_SESSION_STATE_DIR=/tmp/x tmux-session restore` (uses `tmux -L test`).
- Manual save/restore: `tmux-session snapshot`, `tmux-session restore`.
- Pitfall found while building this: systemd's user PATH has no mise/`~/.local/bin`, so the script searches for tmux itself (`TMUX_BIN` overrides). If restore logs "tmux not found", set `TMUX_BIN`.
- The server started by `restore` lives in the unit's cgroup; `KillMode=process` keeps it when the unit is stopped or restarted. A stopped/restarted user manager (logout without linger) still ends it.

## Why not tmux-resurrect/continuum
It also works, but needs TPM and plugin config on every machine, and its restore of running programs is a fuzzy whitelist. This script is one file, readable snapshot, same result for this use case. The superuser.com thread "restore tmux session after reboot" lists tmuxinator, hand-scripted sessions and resurrect; this is the scripted approach, generated from the live server instead of hand-written.

Wrapper scripts run as `bash /path/tool args` are recorded as `/path/tool args`, so the allowlist can name the tool (not `bash`).
