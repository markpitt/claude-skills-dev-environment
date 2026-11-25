# Zellij config, layouts and autostart in practice

Checked on 20/11/2026 against zellij 0.46.0: every key below appears in `zellij setup --dump-config` for that
version. The main SKILL.md's baseline names 0.44.3, so re-check keys after an upgrade before relying on them.

## 1. Keys that matter, and their defaults

Verify with `zellij setup --dump-config` (the commented defaults) and `zellij setup --check` (the live file).

| Key | Default | What it changes |
|---|---|---|
| `default_mode` | `normal` | Base input mode. `"locked"` passes every keystroke to the pane until the unlock key is pressed. A new user can read this as "keys do nothing" |
| `default_layout` | `default` | Layout for a new session when none is named |
| `theme` | `default` | Pins a theme. Setting it turns off automatic light and dark switching |
| `theme_dark` / `theme_light` | unset | Pair two themes; zellij picks one from the host terminal's reported palette. Both must be set |
| `simplified_ui` | `false` | Plain text in place of arrow glyphs in the bars. The first fix for a terminal that draws those glyphs badly |
| `pane_frames` | `true` | Frames around panes. Turning them off saves a row or column but makes boundaries harder to see |
| `styled_underlines` | `true` | Coloured and curly underlines. Turn off where the terminal renders them wrongly |
| `mouse_mode` | `true` | Mouse events go to zellij. Turning it off restores the terminal's own selection, at the cost of wheel scrolling |
| `focus_follows_mouse` | `false` | Hover focuses a pane |
| `mouse_click_through` | `false` | A click that focuses a pane is also sent into it |
| `mouse_hover_effects` | `true` | Frame highlight and help text on hover |
| `scroll_buffer_size` | `10000` | Lines kept per pane |
| `copy_on_select` | `false` | Copy when a mouse selection is released |
| `copy_command` | unset | Command the copy is piped to, for example a Wayland or X clipboard tool |
| `auto_layout` | `true` | Lay panes out by the predefined layouts whenever possible |

Keys set in `config.kdl` live at the top level or inside `keybinds`. Keep `keybinds clear-defaults=true` only
if the whole key map is redefined; otherwise the defaults disappear.

## 2. Scrolling with the mouse, and the stacked-pane trap

In the operator's key map, `s` in normal mode enters scroll mode; `j`, `k`, the arrows and the page keys scroll;
`Ctrl c` scrolls to the bottom and returns to locked mode. Wheel scrolling depends on mouse mode, and it also
depends on the pane having room to scroll.

Observed fault: wheel scrolling did nothing in the agent panes of a coding layout. The agent pane sat in a
stacked group, and the collapsed panes showed only a one-row header, so there was no scrollable area. The fix
that worked was to keep the agent pane expanded (`expanded=true` on the pane that should show its content) and
to stop stacking the pane that needed scrolling. The current coding layout in the operator's setup does exactly
that:

```kdl
pane split_direction="vertical" {
    pane command="nvim" name="editor" size="57%" focus=true
    pane size="42%" stacked=true {
        pane command="codex" args="--cd" args="." name="codex" expanded=true
        pane name="terminal"
    }
}
```

Focus and click options can be applied to a running session with `zellij --session <name> options`, for example
`--focus-follows-mouse true --mouse-click-through true`. Not every option takes effect at once, so restart or
start a new session to confirm.

## 3. Contrast on a ChromeOS terminal

Reported on 28/06/2026: a Solarized theme in the ChromeOS terminal left half the interface unreadable. The
profile applied that day, and kept by the operator's setup, reads in this order:

1. `simplified_ui true`: removes glyphs that the ChromeOS terminal draws badly.
2. A Solarized theme pinned with `theme`, with `theme_dark` and `theme_light` set only if automatic switching is
   wanted. Pinning `theme` disables switching; that is the choice to make consciously.
3. `default_layout "compact"`: less status-bar chrome.
4. `pane_frames true` so the pane boundaries stay visible.
5. `styled_underlines false`.
6. Start-up tips, release notes and hover effects turned off, to reduce what the terminal has to draw.

If a theme still reads poorly, change only the theme name, one step at a time, and restart zellij after each
change. Use `zellij setup --check` after each edit.

## 4. Auto-enter: a layout chosen by directory

A guarded script in the shell's drop-in directory can decide, for each interactive shell, whether to attach to or
create a zellij session, and which layout to use. Keep the decision in a separate script so it can be tested with a
dry-run flag. The pattern below is generic; the names are examples.

Rules file, first match wins:

```toml
[[rule]]
name = "home uses terminal layout"
when = "home"
layout = "terminal"

[[rule]]
name = "git root uses coding layout"
when = "git_root"
layout = "coding"
```

Other `when` values the operator's script understands: `default`, and `path_prefix:<dir>`. A project can override
all rules with its own `.zellij/layout.kdl`, which is checked first.

Skip conditions, in the order the script applies them. Each skip exits quietly, so the shell carries on:

1. Already inside zellij (`ZELLIJ` is set).
2. A disable variable is set (`ZELLIJ_AUTO_ENTER_DISABLE=1` or `MISE_ZELLIJ_DISABLE=1`).
3. `zellij` is not on PATH.
4. There is no controlling terminal (`/dev/tty` is not readable and writable).
5. The shell sits inside an editor-hosted terminal, detected from editor environment variables or from a parent
   process named after an editor. Auto-start there is usually unwanted.
6. No rule matched, or the layout file is missing (this one prints a message).

Session names: the home directory gets a fixed name (`default`), `~/src` gets `src`, a directory under `~/src`
gets its relative path with separators replaced by underscores (`<group>/<project>` becomes `<group>_<project>`),
and anything else gets a sanitised absolute path. Names are lower-cased and non-alphanumeric runs become `_`.

Create or attach:

```bash
if zellij list-sessions -s 2>/dev/null | grep -Fx -- "$session_name" >/dev/null; then
  exec zellij attach "$session_name"
fi
exec zellij --session "$session_name" --new-session-with-layout "$layout_file"
```

Check the decision without launching anything: run the script with its dry-run flag from the directory you want to
test. It prints the session name, the matched rule and the layout path.

## 5. Project-local autostart through mise

A project can start or reattach to its own zellij session when the directory is entered, without touching global shell
configuration. The pattern keeps everything in the repository:

- `mise.toml` declares a hook and a task:

  ```toml
  [hooks]
  enter = "mise run zellij"

  [tasks.zellij]
  raw = true
  run = "$MISE_PROJECT_ROOT/.zellij/enter.sh"
  ```

- `.zellij/enter.sh` holds the logic and `.zellij/layout.kdl` the layout.
- If the repository already has an `enter` hook, merge with it rather than replacing it.

Guards the script needs: skip when already inside zellij; skip when `MISE_ZELLIJ_DISABLE=1`; skip when `zellij` is not on
PATH; skip when the layout file is missing; skip cleanly when there is no controlling terminal.

Do not gate on `[[ $- == *i* ]]`. A mise hook can run in a non-interactive child shell even when the user entered the
directory from an interactive terminal. A hook whose stdio is detached must bind `zellij` to the controlling terminal
before it attaches or creates, which is what the auto-enter script does by opening `/dev/tty`.

Use `MISE_PROJECT_ROOT`, not hard-coded paths. Session names follow section 4: one stable session per project.

Create-or-attach: use `zellij --session "$name" --new-session-with-layout "$layout"` when a first-run layout is wanted,
and `zellij attach --create "$name"` when it is not. Check the flags against the local `zellij --help` first.

Failure modes, in the order to check them:

1. The hook calls bare `zellij` instead of `mise run zellij`.
2. The script exits early because it assumes an interactive shell from `$-`.
3. The hook has no usable controlling terminal.
4. The session command does not apply the requested layout (the layout is only used when a session is created).
5. The session name derivation does not match what was expected.
6. The layout names a command that is not on PATH.

Validation, using a disposable session name so no real session is touched:

- `mise config get hooks.enter` and `mise tasks ls --local`.
- `bash -n .zellij/enter.sh`.
- The create path and the existing-session path, each with a disposable name.
- `MISE_ZELLIJ_DISABLE=1 mise run zellij`, which should do nothing and exit cleanly.

Do not kill or reuse a real session name during validation unless the operator asks for that.

## 6. Yazi as a working-directory pane

A layout can hold a file browser beside the shell, so that choosing a directory in the browser changes the shell's
directory:

```kdl
pane split_direction="vertical" {
    pane command="~/.config/zellij/yazi-tree.sh" name="treeview" size="22%"
    pane command="/usr/bin/zsh" name="terminal" size="43%" focus=true
    // agent panes continue to the right
}
```

- `yazi-tree.sh` starts yazi with its own `XDG_CONFIG_HOME`, so the browser's configuration is separate from the
  operator's main yazi setup.
- A yazi keymap entry, and a `zellij-cd` action in yazi's `yazi.toml`, run a helper with the selected directory.
- The helper finds the live pane named `terminal` in the same tab (via `zellij action list-panes --json --all` and `jq`),
  then pastes `cd -- <dir>` into that pane and sends Enter. Its environment variables `ZELLIJ_TARGET_PANE_ID`,
  `ZELLIJ_YAZI_SOURCE_PANE_ID` and `ZELLIJ_PANE_ID` select the pane. `ZELLIJ_YAZI_CD_DRY_RUN=1` prints the session, pane
  and command instead of sending them.

Caveat: the helper types into whatever is running in the terminal pane. If a long-running command, an editor or a
prompt has focus there, the `cd` text goes to that program. Use the dry-run flag to test the target first, and keep the
pane idle when the browser is used.

## 7. Evidence and scope

- Keys in sections 1 and 3 were checked against `zellij setup --dump-config` for 0.46.0.
- The scrolling fault in section 2 and the contrast profile in section 3 come from one session each, reported by the
  operator and worked through with the agent. They describe one terminal (ChromeOS) and one layout; test on your own.
- The auto-enter and yazi patterns in sections 4 and 6 are taken from the operator's working setup, with names and
  paths generalised.
