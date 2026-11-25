---
name: zellij
description: Configure and operate zellij terminal multiplexer sessions. Use when setting up zellij shell integration, creating or attaching sessions, managing pane/tab workflows, restoring work after disconnects, or optimising terminal workflows for AI agents. Also use for directory-driven auto-enter rules, project-local autostart through mise, a yazi pane that changes the shell directory, mouse scrolling in stacked panes, or unreadable contrast in a ChromeOS terminal. Do NOT use for tmux persistence across reboots (use tmux-persist) or for mise tasks in general (use mise).
license: Apache-2.0
metadata:
  version: "1.1.0"
---

# Zellij

Make terminal work persistent, recoverable, and easy to resume.

## Documentation Baseline

- Last checked against local `zellij 0.44.3` and official Zellij docs on 2026-07-02.
- Config keys in `references/config-and-layouts.md` were checked against `zellij 0.46.0` on 2026-11-20 with `zellij setup --dump-config`.
- Zellij configuration and layouts use KDL.
- Current config discovery order is `--config-dir`, `ZELLIJ_CONFIG_DIR`, `$HOME/.config/zellij`, platform default, then system config.
- Generate current config with `zellij setup --dump-config`; validate config paths and syntax with `zellij setup --check`.
- Generate shell snippets with `zellij setup --generate-auto-start <shell>` and completions with `zellij setup --generate-completion <shell>`.
- Layouts can be applied at startup with `zellij --layout <path-or-name>`. Inside an existing session, the same command adds the layout as new tab(s).
- Layouts in the config layout directory can be referenced by bare name, for example `zellij --layout coding`.
- To force a new session with a layout, use `zellij --session <name> --new-session-with-layout <path-or-name>`.
- For a create-or-attach path, use `zellij attach --create <session-name>` when no special first-run layout is required; when a first-run layout is required, test the exact create path against `zellij --help` and `zellij attach --help`.

## Config, Layouts and Autostart

For the config keys that change behaviour (default mode, theme pinning, simplified UI, mouse
options), the auto-enter rules file, project-local autostart through a mise hook, the yazi
working-directory pane, scroll-wheel behaviour in stacked panes and the ChromeOS contrast
profile, read `references/config-and-layouts.md`. Two points to keep in mind:

- `default_mode "locked"` passes every key to the pane. A session that seems to ignore keys is often
  locked; `Ctrl g` unlocks in the operator's key map.
- Pinning `theme` turns off automatic light and dark switching. Set `theme_dark` and `theme_light`
  instead if the terminal's palette should decide.

## What This Skill Produces

- A working zellij setup plan for the current shell and machine.
- A repeatable session model (naming, attach/detach, cleanup).
- A workflow pattern for panes/tabs that reduces context loss.
- Recovery steps for common failures (stale sessions, orphan panes, bad layout state).
- A default setup profile using guarded auto-start for interactive shells.

## Scope

- Workspace-scoped skill at `.claude/skills/zellij`.
- Before recommending new startup wiring, inspect any global Zellij shell integration already present, typically under `~/.config/zellij` and the shell's drop-in directory.

## When To Use

Use this skill when the request includes any of these intents:

- "set up zellij"
- "help me use zellij"
- "manage terminal sessions"
- "recover my terminal workspace"
- "replace tmux/screen workflow"
- "make terminal work persistent"

## Inputs To Clarify

Before changing startup files or killing sessions, confirm:

1. Shell: `bash`, `zsh`, `fish`, or other.
2. Scope: one project only, or all projects.
3. Style: keyboard-first defaults, tmux-like mode, or minimal learning curve.
4. Persistence expectation: temporary session vs long-lived named sessions.

## Workflow

### 1. Establish Baseline

1. Confirm zellij exists on PATH by running `command -v zellij`.
2. If zellij is missing, stop and provide install instructions for the host OS.
3. Check whether already inside zellij via `$ZELLIJ`.
4. If already inside, avoid nesting. Prefer creating tabs/panes in the current session.

Completion check:
- zellij is installed.
- nested-session risk is identified.

### 2. Configure Safe Startup Behaviour

1. Run `zellij setup --help` and prefer the generated shell-specific snippet from `zellij setup --generate-auto-start <shell>` when appropriate.
2. Add startup integration only after user confirmation.
3. Default to guarded auto-start for interactive shells, unless an existing global policy is already present.
4. Keep a documented bypass path (eg env flag or direct shell launch).

Default guard pattern:
- Only auto-start in interactive shells.
- Skip when already inside zellij (`$ZELLIJ` is set).
- Respect explicit opt-out env var (eg `ZELLIJ_AUTO_START=0`).
- Skip cleanly when no controlling terminal is available.
- Avoid auto-starting from editor-hosted terminals unless the user explicitly wants that.

A workable shape, if the user wants auto-start wired globally:
- A guarded hook in the shell's drop-in directory, sourced for interactive shells only
- The decision logic in a separate script the hook calls, so it can be tested on its own
- A rules file mapping directory patterns to session name and layout
- Shared layouts in the config layout directory, referenced by bare name
- A dry-run flag on the decision script, so the choice can be inspected without launching anything

A reasonable default policy: `$HOME` gets a plain terminal layout and a stable
session name, git roots get a coding layout, and ordinary directories do not
auto-enter unless the project opts in with a checked-in layout file.

Completion check:
- shell startup change is explicit and reversible.
- user has a bypass path.

### 3. Standardise Session Lifecycle

Use named sessions for each project or objective.

1. List sessions: `zellij list-sessions`.
2. Start/attach by name: `zellij attach --create <session-name>`.
3. If the first-run session needs a layout, create it with `zellij --session <session-name> --new-session-with-layout <layout>`, then attach normally on later runs.
4. Detach (do not kill) when pausing work.
5. For deliberate cleanup, kill only targeted sessions with `zellij kill-session <session-name>`.

Naming convention:
- `<repo>-main`
- `<repo>-review`
- `<repo>-ops`

Completion check:
- at least one named session exists.
- user can detach and reattach without losing context.

### 4. Apply Pane/Tab Operating Pattern

Use tabs for domains and panes for parallel commands.

Recommended tab structure:
- `editor`: primary coding and file navigation
- `tests`: continuous test/lint loops
- `logs`: runtime output and diagnostics
- `ops`: git, release, maintenance commands

Recommended pane pattern per tab:
- top/left pane: main active command
- secondary pane: watcher or logs
- optional floating pane: short-lived inspection task

Completion check:
- at least 2 tabs with clear purpose.
- no pane left with unknown purpose.

### 5. Drive Sessions Through CLI Actions When Needed

Use targeted automation when interactive control is slow:

- `zellij action list-panes --json`
- `zellij action list-tabs --json`
- `zellij action current-tab-info --json`
- `zellij action new-pane -- <command>`
- `zellij action new-tab --name <name>`
- `zellij action go-to-tab-name --create <name>`
- `zellij action dump-layout`
- `zellij action dump-screen --full --path <file>`
- `zellij action override-layout <layout>`
- `zellij action rename-session <new-name>`
- `zellij action save-session`
- `zellij action detach`

Use actions for repeatability, especially in scripts or agent workflows.

Completion check:
- at least one action command successfully used for session control.

### 6. Recovery Playbook

If a terminal disconnects or state becomes unclear:

1. List sessions and identify expected target.
2. Reattach to the named session first with `zellij attach <session-name>`.
3. If the layout is degraded, recreate missing tabs and re-run long-lived commands.
4. If a session is truly stale, terminate only that session and recreate.
5. Save state after major layout rebuild with `zellij action save-session`.
6. For read-only inspection without taking control, use `zellij watch <session-name>`.

Completion check:
- user can recover to a known-good session in under 2 minutes.

## Decision Points

- If user wants zero startup risk: do not modify shell startup, use manual `zellij` launch.
- Default preference: guarded auto-start in interactive shells with a clear bypass.
- If user wants tmux-like ergonomics: switch mode/profile after confirming preferred keybindings.
- If user runs many repos concurrently: require strict session naming and tab discipline.
- If user mostly runs one repo: keep one stable session and rotate tabs, not sessions.

## Quality Criteria

A zellij setup is complete only if all are true:

1. User can open, detach, and reattach a named session.
2. Session names are predictable.
3. Tabs are role-based (not generic "Tab #n").
4. Recovery path is documented and tested once.
5. Startup behaviour is explicit, minimal, and reversible.

## Agent Response Contract

When invoked, produce:

1. Current state summary (installed, shell, in-session, session inventory).
2. Exact commands to run now (minimal set).
3. Expected outcomes after each command.
4. Quick rollback instructions for any startup-file change.
5. Final verification checklist.

## Maintenance

- Re-check official docs and local `zellij --help` before updating command syntax, especially for startup, layout, session, and action commands.
- After changing global config, run `zellij setup --check`, plus the dry-run flag on any auto-start decision script, before relying on the result.
- Review the skill after Zellij upgrades or at least quarterly if it is actively used.

## Example Prompts

- "Set up zellij safely for zsh with reversible startup config."
- "Create a reliable zellij session model for this repository."
- "I got disconnected, recover my zellij workspace quickly."
- "Convert my ad-hoc terminal usage into a stable zellij workflow."
- "Start a project's zellij session when I enter the directory, through mise."
- "The mouse wheel does nothing in my agent pane. Why?"
- "Half the zellij interface is unreadable in my ChromeOS terminal."
