---
name: mise
description: Configures and debugs mise (mise-en-place), which manages tool versions, environment variables and project tasks from a mise.toml. Covers installing and pinning runtimes (Node, Python, Go, .NET and others), the task runner, env vars and PATH, secrets with SOPS or fnox, backends (github, ubi, cargo, npm, aqua, conda, pipx), Lua plugins, lockfiles, shell activation, migrating from asdf, nvm or direnv, and mise doctor. Also covers running tools from an agent's shell or any non-interactive command (mise exec versus mise activate), and installing language servers and debug adapters through mise instead of an editor's installer such as Mason. Use when writing or fixing a mise.toml, when a tool is not found or the wrong version runs, when adding mise tasks, or when an agent's commands cannot see tools mise installed. Do NOT use for general Docker, container or CI questions that do not involve mise, or for editor settings beyond the tools they run.
license: Apache-2.0
metadata:
  version: "2.0.0"
  tags: [mise, devtools, runtimes, environment, tasks, asdf, direnv, nvm, agents, non-interactive-shell, lsp, mason]
---

# mise

[mise](https://mise.jdx.dev) reads `mise.toml` in a project and its parents, installs the tool
versions it names, sets the environment variables it declares, and runs its tasks. It covers the
ground of asdf, nvm and pyenv for versions, direnv for environment, and make for simple tasks.

Install it with `curl https://mise.run | sh` (or a package manager), then add
`eval "$(mise activate zsh)"`, or the bash or fish equivalent, to the interactive shell's rc file.

Give complete, commented `mise.toml` snippets for configuration questions. For anything that
behaves oddly, start with `mise doctor`.

## A project file

```toml
[tools]
node = "24"
python = "3.13"

[env]
NODE_ENV = "development"
_.path = ["./node_modules/.bin"]

[tasks.test]
run = "npm test"
depends = ["build"]

[tasks.build]
run = "npm run build"
```

Commit `mise.toml`, run `mise install`, and anyone who clones the repository gets the same tools.
Personal overrides go in `mise.local.toml`, which belongs in `.gitignore`. Commit `mise.lock` as
well (stable since 2026.2.0; `mise lock` creates it) so CI gets the exact versions, not just the
same major.

## Things that catch people out

- **Agents and scripts do not get `mise activate`.** Activation lives in an interactive shell's rc
  file, which a non-interactive command never reads. Prefix commands with `mise exec --`, or wrap
  them as tasks and call `mise run <task>`. Check what a non-interactive shell sees with
  `bash -c 'command -v <tool>'`, not from your terminal.
- **Env vars not loading usually means an untrusted config.** mise ignores the `[env]` of a file it
  has not been told to trust. `mise trust` fixes it, and is a decision to make on purpose for a
  repository you did not write.
- **Global is for utilities, not runtimes.** `mise use --global` suits ripgrep, gh and bat.
  Runtimes belong in the project file, or two projects end up silently sharing one Node.
- **Use `mise use`, not hand edits,** where you can: `mise use node@24` writes the entry and
  installs the tool in one step.
- **Do not run asdf shims alongside mise.** They fight over PATH. Remove asdf once the migration is
  done. mise reads `.tool-versions` and `.nvmrc` already, so the migration can be gradual.
- **One task with an argument beats many near-identical tasks.** Use `usage` arguments for a
  dynamic target (`mise run test:one <name>`). mise does not invent task names that are not defined.

## When a tool is missing or the version is wrong

1. `mise doctor`: shell integration, PATH order, shim conflicts.
2. `mise ls --current`: which versions are active here, and which file set each.
3. `mise which <tool>`: the binary mise would run.
4. `mise env`: the variables mise sets in this directory.
5. If the answer depends on directory, read the config hierarchy in `references/core-concepts.md`:
   a parent's or the global file may be winning.

## Language servers and debug adapters

mise can be the one installer for editor tools too. Declare them in a global `conf.d` file, one
backend per tool (aqua, npm, pypi, dotnet or github), turn off the editor's own installer (Mason
in Neovim, for example) if mise is to be the only manager, and check each with
`mise exec -- <server> --version`. `references/agents-and-editors.md` has the detail.

## References

| File | Covers |
|---|---|
| `references/core-concepts.md` | Install, shell activation, `mise.toml` format, config hierarchy, trust, migrating from asdf and nvm |
| `references/commands-reference.md` | `use`, `install`, `upgrade`, `exec`, `ls`, `prune`, `doctor`, `env`, `watch`, and `generate` for CI, devcontainers and git hooks |
| `references/backends.md` | Core, github, ubi, cargo, npm, pipx and aqua backends, and writing Lua plugins |
| `references/task-runner.md` | Task definitions, dependencies, parallel runs, file tasks, monorepo tasks, `usage` arguments |
| `references/environment-secrets.md` | `[env]`, PATH, templating, SOPS and fnox |
| `references/advanced-features.md` | Caching, hooks, Pitchfork daemons, lockfiles, team and CI set-up |
| `references/agents-and-editors.md` | `mise exec` versus `activate` in agent shells, shims, language servers and debug adapters |

External: [mise docs](https://mise.jdx.dev), [backends](https://mise.jdx.dev/dev-tools/backends/),
[source and releases](https://github.com/jdx/mise), [SOPS](https://github.com/getsops/sops),
[fnox](https://github.com/jdx/fnox) and [Pitchfork](https://github.com/jdx/pitchfork).
