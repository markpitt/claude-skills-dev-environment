---
name: zellij
description: Configures and operates zellij terminal multiplexer sessions. Use when setting up zellij shell integration, creating or attaching sessions, managing pane and tab workflows, restoring work after disconnects, or optimising terminal workflows for AI agents. Also use for directory-driven auto-enter rules, project-local autostart through mise, a yazi pane that changes the shell directory, mouse scrolling in stacked panes, or unreadable contrast in a ChromeOS terminal. Do NOT use for tmux, including keeping tmux sessions across reboots (use tmux-persist), or for mise tasks in general (use mise).
license: Apache-2.0
metadata:
  version: "2.0.0"
---

# Zellij

The aim is terminal work that survives a disconnect and is quick to pick up again: named sessions,
tabs with a job each, and start-up wiring that can be switched off.

## What this was checked against

The commands here were checked against `zellij 0.44.3` and the official docs on 2 July 2026. The
config keys in `references/config-and-layouts.md` were checked against `zellij 0.46.0` on
20 November 2026 with `zellij setup --dump-config`. Flags move between releases, so check
`zellij --help` and the subcommand's `--help` on the machine before giving exact syntax.

Useful facts that rarely change:

- Config and layouts are KDL.
- Config is looked for in `--config-dir`, then `ZELLIJ_CONFIG_DIR`, then `$HOME/.config/zellij`,
  then the platform default, then the system config.
- `zellij setup --dump-config` prints the current defaults, and `zellij setup --check` validates
  the config paths and syntax.
- `zellij setup --generate-auto-start <shell>` prints a start-up snippet, and
  `--generate-completion <shell>` prints completions.
- `zellij --layout <path-or-name>` starts with a layout. Inside a session the same command adds the
  layout as new tabs. A layout in the config layout folder can be named bare: `zellij --layout coding`.
- `zellij attach --create <name>` attaches or creates. When the first run needs a layout, use
  `zellij --session <name> --new-session-with-layout <layout>` and attach normally afterwards.

## Before changing anything

Look for zellij wiring that is already there, usually under `~/.config/zellij` and the shell's
drop-in folder, before suggesting new start-up code. Then check:

1. `command -v zellij`. If it is missing, give the install command for the OS and stop there.
2. `$ZELLIJ`. If it is set, you are already inside a session: add tabs or panes to it rather than
   nesting another.
3. Ask what you cannot see: the shell, whether this is for one project or all of them, and whether
   sessions are meant to be short-lived or kept for weeks.

Confirm with the person before editing shell start-up files or killing a session.

## Start-up wiring

Prefer the generated snippet from `zellij setup --generate-auto-start <shell>`, and guard it. The
guard should start zellij only in an interactive shell with a terminal, skip when `$ZELLIJ` is
already set, skip in an editor's built-in terminal unless asked, and honour an opt-out such as
`ZELLIJ_AUTO_START=0`. Without the opt-out, a broken layout can lock someone out of a usable shell.

For automatic sessions per directory, a shape that holds up:

- a guarded hook in the shell's drop-in folder, sourced only by interactive shells;
- the decision in a separate script the hook calls, so it can be tested alone, with a dry-run flag
  that prints the choice without launching anything;
- a rules file mapping directory patterns to a session name and layout;
- shared layouts in the config layout folder, named bare.

A sensible default policy: `$HOME` gets a plain layout and a fixed session name, a git root gets a
coding layout, and any other folder stays a plain shell unless the project checks in a layout file.
`references/config-and-layouts.md` has the rules file, the project-local version through a mise
hook, the config keys, the yazi pane that changes the shell's directory, why the mouse wheel does
nothing in a stacked pane, and a contrast profile for the ChromeOS terminal.

Two config behaviours that confuse people:

- **`default_mode "locked"` passes every key to the pane.** A session that seems to ignore its key
  bindings is often just locked. `Ctrl g` unlocks it in the default key map.
- **Pinning `theme` turns off light and dark switching.** Set `theme_dark` and `theme_light`
  instead if the terminal's palette should decide.

## Sessions, tabs and panes

Name a session after the project and what it is for (`<repo>-main`, `<repo>-review`,
`<repo>-ops`). Detach when pausing; do not kill. List with `zellij list-sessions` and remove only a
named session with `zellij kill-session <name>`. Someone who works in one repository at a time does
better with one long-lived session and several tabs than with a new session for each task.

Give each tab one job, such as `editor`, `tests`, `logs` and `ops`, with the main command in the
first pane, a watcher or log beside it, and a floating pane for anything brief. The tab name is what
tells you where you are after a reconnect, so "Tab #3" is a small failure.

For scripts and agents, `zellij action` is quicker and repeatable:

```bash
zellij action list-panes --json
zellij action list-tabs --json
zellij action new-tab --name tests
zellij action go-to-tab-name --create logs
zellij action new-pane -- npm run watch
zellij action dump-layout
zellij action dump-screen --full --path screen.txt
zellij action save-session
zellij action detach
```

## Getting back after a disconnect

1. `zellij list-sessions`, and find the one you expect.
2. `zellij attach <name>`. Try this before anything else.
3. If tabs are missing, recreate them and restart the long-running commands.
4. If a session is genuinely stale, kill that one only, recreate it, then
   `zellij action save-session`.
5. To look at a session without taking control of it, use `zellij watch <name>`.

## What to hand back

Say what is installed and running now, give the commands to run in order with what each should
show, give the undo for any start-up file you changed, and end with the check: open, detach and
reattach a named session. After any config change, run `zellij setup --check` and the auto-start
script's dry run before relying on it.
