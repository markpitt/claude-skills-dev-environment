---
name: tmux-persist
description: Keeps tmux sessions across reboots on any Linux machine. Saves every session, window and pane layout (working directory and foreground command) every five minutes and at shutdown, and rebuilds them at boot through systemd user units. Use when asked to set up tmux persistence on a new server, check or repair it, add a program to the re-run allowlist, or recover tmux sessions after a reboot. Do NOT use for zellij (use zellij), for recovering an agent's interrupted work after a crash (use resume-after-crash), or for general tmux key bindings and configuration.
license: Apache-2.0
metadata:
  version: "1.1.0"
---

# tmux-persist

One script, `scripts/tmux-session.sh`, and the systemd user units in `scripts/systemd/`. It needs
tmux, a systemd user instance and bash. No tmux plugins and no root.

## Install on a machine

1. Get this skill's folder onto the machine: clone the repository, unpack the skill zip, or
   `scp -r` it across.
2. As the normal user, not root, run `bash scripts/tmux-session.sh install`. It copies the script
   to `~/.local/bin/tmux-session`, puts the units in `~/.config/systemd/user/`, saves the current
   layout, and enables two units:
   - `tmux-session.service` runs `restore` at boot and `snapshot` when it stops;
   - `tmux-session-snapshot.timer` runs `snapshot` two minutes after boot, then every five.
3. Turn on linger, or the user units wait for the first login instead of starting at boot. Check
   with `loginctl show-user $USER -p Linger` and fix with `sudo loginctl enable-linger $USER`. The
   installer warns when it is off.
4. To make the skill available to Claude Code as well, link it:
   `ln -s <path>/tmux-persist ~/.claude/skills/tmux-persist`.

## What it saves and what it brings back

The snapshot is `~/.local/state/tmux-session/sessions.tsv`, with the previous one kept as `.prev`.
Each row is one pane: session, window index and name, layout string, active flags, pane index,
working directory and foreground command. `tmux-session show` prints it, which is also the quickest
way to see what a reboot would rebuild.

`restore` only creates sessions that do not already exist. A live session is never touched, so
running it twice does no harm. Layouts, working directories and the active window and pane come
back exactly.

The foreground command is typed back into the pane's shell only when its program is on the
allowlist, which by default is `claude btop htop top less tail watch journalctl`. Anything else is
logged and the pane is left at a prompt. Typing the command, rather than exec'ing it, means the
shell's own PATH applies (mise shims included) and the pane survives the program exiting. A wrapper
run as `bash /path/tool args` is recorded as `/path/tool args`, so the allowlist names the tool, not
`bash`.

Change the allowlist, or pin the tmux binary, in `~/.config/tmux-session/env`:

```bash
TMUX_SESSION_PROGRAMS="claude btop htop top less tail watch journalctl nvim"
TMUX_BIN=/path/to/tmux
```

Things it deliberately does not do:

- **It does not save scrollback, shell history or program state.** An editor's unsaved buffers and
  an SSH hop are gone after a reboot.
- **It does not overwrite a good snapshot with nothing.** No snapshot is written when no tmux
  server is running. The flip side is that a session you kill on purpose stays in the snapshot until
  something else changes it. Delete its rows, or the file, to forget it.
- **It does not add `--continue` to `claude remote-control` panes.** They are typed back as
  recorded. `--continue` would limit a directory to one session, and plain remote-control allows
  many.

Those remote-control panes first run `tmux-session wait-dns`, which waits until `api.anthropic.com`
resolves, for up to ten minutes (`TMUX_SESSION_WAIT_HOST` and `TMUX_SESSION_WAIT_SECONDS` change
both). At boot the restore can run before the resolver is up, typically when `/etc/resolv.conf`
points at a local DNS container such as AdGuard Home or Pi-hole, and without the wait the first
attempt fails with `getaddrinfo ENOTFOUND`.

### Leaving some agents stopped

Set `TMUX_SESSION_NO_AUTOSTART_DIR` to a folder that holds one subfolder per agent, for example
`$HOME/agents`. Restore then skips a pane running `<name>-agent` when `<dir>/<name>/.no-autostart`
exists. It is unset by default, and the marker file is then ignored.

A skipped pane comes back as a plain shell, so the next snapshot records no program for it.
Removing `.no-autostart` later does not bring the agent back at the next reboot. Start it by hand
once and the snapshot picks it up again.

## Checking and debugging

- Status: `systemctl --user status tmux-session.service tmux-session-snapshot.timer`.
- Logs: `journalctl --user -u tmux-session -u tmux-session-snapshot -b`.
- Save or restore by hand: `tmux-session snapshot`, `tmux-session restore`.
- Try a restore without touching the real server:
  `TMUX_SESSION_SOCKET=test TMUX_SESSION_STATE_DIR=/tmp/x tmux-session restore`, which uses
  `tmux -L test`.

Two traps found while building it:

- **systemd's user PATH has neither mise nor `~/.local/bin`.** The script searches for tmux itself.
  If the log says "tmux not found", set `TMUX_BIN`.
- **The tmux server that `restore` starts lives in the unit's cgroup.** `KillMode=process` keeps it
  alive when the unit stops or restarts, but a user manager that stops (logging out without linger)
  still takes it down.

## Why not tmux-resurrect and tmux-continuum

They work. They also need TPM and plugin configuration on every machine, and their restore of
running programs relies on a looser match. This is one file with a snapshot you can read. The usual
alternatives are tmuxinator, hand-written session scripts and resurrect. This is the scripted
approach, except that the script is generated from the live server rather than written by hand.
