# mise for agents, non-interactive shells and editors

Covers three things: how to run tools from an agent's shell, why `mise activate` does not reach a
non-interactive command, and how to install language servers and debug tools through mise rather than
through the editor's own installer. Checked against mise 2026.11.8 on 20/11/2026, with the probes noted
inline.

## 1. The two ways mise reaches a command

| Mechanism | What it does | Where it works |
|---|---|---|
| `mise exec -- <command>` | Runs one command with the tools and `[env]` of the current directory's config | Anywhere mise is installed: agent tool calls, scripts, CI, cron, editors |
| `eval "$(mise activate <shell>)"` | Installs hooks so PATH and `[env]` follow the directory as the shell prompts or changes directory | Interactive shells, where the eval sits in an rc file that the shell reads |
| `eval "$(mise activate <shell> --shims)"` | Puts shims on PATH, with no hooks | Contexts that need the tool names but not the directory-dependent `[env]` |

Use `mise exec --` for every command an agent runs. Use `mise run <task>` for a defined task. Neither
needs activation, and neither depends on which rc file a shell happened to read.

## 2. Why activation does nothing in an agent's command

The rule is about where the eval sits, not about whether activation works in principle.

Probes run on 20/11/2026 in a scratch directory with `[env] PROBE = "set-by-mise"` in its `mise.toml` and a
subdirectory with its own value:

- `zsh -c 'eval "$(mise activate zsh)"; echo $PROBE'` printed the value. The eval runs the hook once,
  so an activation written into the same command takes effect.
- The same command with `cd` into the subdirectory printed the subdirectory's value. The hook follows
  directory changes inside a non-interactive shell.
- `bash -c 'eval "$(mise activate bash)"; cd …; echo $PROBE'` behaved the same way.
- `zsh -c 'echo $PROBE'` and `bash -c 'echo $PROBE'` with no activation printed nothing: the variable
  was unset.
- `mise exec -- sh -c 'echo $PROBE'` in the subdirectory printed the subdirectory's value, with no
  activation at all.

So the failure an agent sees is almost always this: the activation was written into `~/.zshrc` or
`~/.bashrc`, which an interactive shell reads and a `zsh -c` or `bash -c` command does not. Each
command the agent starts is a new process, so the earlier interactive session's activation does not
carry over. The symptoms are "command not found" for a tool that works in the terminal, or a variable
that is unset in the agent's run only.

Two further points that follow from zsh's documented startup order (not separately probed here):

- `~/.zshenv` is read by every zsh, including `zsh -c`. A PATH line there reaches agent commands. Keep
  it to PATH and a shims activation, not to anything slow or interactive.
- A `zsh -lc` login shell reads the login files, not `~/.zshrc`. Putting activation in a `~/.zshrc.d/`
  drop-in therefore reaches only interactive shells, unless the login files source it too. One earlier
  agent session found that its non-interactive shell had no mise shims on PATH, and added a drop-in that
  an interactive shell would read. Check the real command rather than assume it: `zsh -lc 'command -v mise'`
  and `bash -c 'command -v mise'`.

Rules for an agent:

1. Prefix tool commands with `mise exec --` (or run a `mise run` task). Do not rely on the shell having
   been activated.
2. Do not add `eval "$(mise activate …)"` to a command just to make a tool work. It does work, but
   `mise exec` says what it means in fewer characters and does not install hooks into a process that
   will exit.
3. If a tool is missing under `mise exec`, check whether mise declares it: `mise which <tool>`, then
   `mise ls --current`. A tool that exists only on the interactive PATH is not a mise tool, and no
   activation will make it reliable for an agent. Declare it in mise, or give its full path.
4. Check the environment rather than the shell: `mise env` shows what mise sets in the current directory,
   and `mise doctor` reports shim and PATH conflicts.

## 3. Shims are for PATH, not for `[env]`

`mise activate <shell> --shims` puts the shims on PATH. A probe with `--shims` in `zsh -c` left the
`[env]` variable unset, so a tool called through a shim sees the PATH but not the directory's `[env]`.
For a project that needs both, use `mise exec --`. The shims mode suits a long-lived process that
starts tools by name (an editor's language client, for example) and does not need per-directory
variables.

## 4. Installing language servers through mise

Many editors install their own language servers (Mason in Neovim is the common case). When mise is
the single installer for a machine, disable the editor's installer and declare the servers in mise, so
one command installs, upgrades and pins every external tool.

The pattern used in one operator's Neovim setup, generalised:

- Turn off the editor's package manager (in Neovim with LazyVim, the `mason.nvim` and
  `mason-lspconfig.nvim` entries, and any extras that pull them in). Keep the client configuration.
- Declare the servers and linters in a global drop-in file. mise reads every `*.toml` under
  `~/.config/mise/conf.d/`, which `mise config ls` lists.
- Choose a backend per tool. In that file: `aqua:` for registry binaries (for example `aqua:LuaLS/lua-language-server`,
  `aqua:astral-sh/ruff`), `npm:` for Node-based servers (`npm:pyright`, `npm:typescript-language-server`,
  `npm:bash-language-server`, `npm:yaml-language-server`), `pypi:` for Python tools (`pypi:debugpy`),
  `dotnet:` for .NET tools (`dotnet:fsautocomplete`), and `github:` with an `asset_pattern` for debug
  adapters that ship as release archives. The `github:` form needs the asset name pinned, because a
  release can carry several archives.
- Use `"latest"` only where the operator accepts it. Pin a version where a server's behaviour matters
  to a workflow.
- The editor must resolve the same binaries. The Neovim setup runs `mise env --json` to import the
  environment, and prepends the output of `mise bin-paths` to PATH at startup. That way the editor finds the
  mise-resolved server even when it is launched from a GUI or a stale shell.

Verify a server resolves to mise, not to a stale copy:

```sh
mise which pyright                 # the path mise resolves
mise config ls                     # confirms conf.d files are loaded
mise ls --global | grep pyright    # the installed version and its source file
mise exec -- pyright --version     # the version an agent or a script will get
```

Notes:

- A `npm:` server needs a Node runtime. Declare Node in mise as well; the server resolves against the
  runtime that mise selects.
- Editor-hosted terminals do not always run the shell's activation. The `bin-paths` step above exists for
  this reason, and the same idea applies to any launcher that starts language servers.
- Debug adapters (netcoredbg, codelldb, js-debug) are archives, not packages. Their `github:` entries need
  the `bin_path` or `format` the archive needs; check `mise ls` after an install for the path it reports.

## 5. Symptoms and the first check

| Symptom | First check |
|---|---|
| A tool works in the terminal but not in an agent's run | `mise exec -- command -v <tool>`; then `mise which <tool>` |
| A variable from `mise.toml` is unset in an agent's run | Is the command prefixed with `mise exec --`? |
| A language server is missing or an old version in the editor | `mise which <server>` and `mise bin-paths`; confirm the editor's installer is off |
| `mise exec --` cannot find a tool that is on PATH in the terminal | The tool is not declared in mise; declare it or call it by its full path |
| Shims give the wrong version | `mise doctor` for shim conflicts, then `mise ls --current` |

## 6. Evidence this rests on

- Probes listed in section 2, run on 20/11/2026.
- Agent transcripts from Codex and omp. A standing instruction, "use `mise run` for tasks and
  `mise exec --` for ad hoc commands; non-interactive shells do not preserve `mise activate` state", appears
  in many Codex transcripts. One Codex session found that a non-interactive shell had no mise shims on PATH,
  and another found that `mise exec --` could not see a tool that was on the interactive PATH. Counts and
  paraphrase only; no transcript content is quoted.
- The Neovim setup's comment that mise is the sole installer for external tools, and its declarations in
  `conf.d`.
