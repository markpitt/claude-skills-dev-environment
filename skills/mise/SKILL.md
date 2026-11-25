---
name: mise
description: Provides expert guidance on mise (mise-en-place), a polyglot dev tool and environment orchestrator that manages runtimes, environment variables, and project tasks. This skill should be used when users ask about mise configuration (mise.toml), installing or switching tool versions (Node, Python, Go, .NET, etc.), the mise task runner, environment variable management, secrets with SOPS/fnox, backends (github, ubi, cargo, npm, aqua, conda, pipx), Lua plugins, shell hooks, migrating from asdf/nvm/direnv, or debugging with mise doctor. Also use when running tools from an agent's shell or other non-interactive commands (mise exec versus mise activate), or when installing language servers and debug adapters through mise instead of an editor's installer such as Mason. Do NOT use for general Docker, container or CI questions that do not involve mise, or for editor settings beyond the tools they run.
license: Apache-2.0
metadata:
  version: 1.3.0
  tags: [mise, devtools, runtimes, environment, tasks, asdf, direnv, nvm, agents, non-interactive-shell, lsp, mason]
---

# Mise Skill

Expert guidance on [mise](https://mise.jdx.dev), the single tool that replaces asdf, nvm, pyenv, direnv, and make. Covers installation, mise.toml configuration, runtime management, task runner, environment variables, secrets, backends, Lua plugins, and team workflows.

## Quick Reference Table

| Task | Load Resource | Key Concepts |
|------|--------------|--------------|
| Install mise or activate in shell | references/core-concepts.md | curl install, shell activation, mise doctor |
| Configure tools and env vars in mise.toml | references/core-concepts.md | [tools], [env], config hierarchy, mise.local.toml |
| Trust a config (env vars not loading) | references/core-concepts.md | mise trust, security model, untrusted configs |
| List, install, upgrade, or pin tool versions | references/commands-reference.md | mise use, mise install, mise upgrade, mise prune |
| Scaffold CI/devcontainer/git hooks | references/commands-reference.md | mise generate github-action, devcontainer, git-pre-commit |
| Understand backends (github, ubi, cargo, npm, aqua, conda) | references/backends.md | Core, GitHub, UBI, Cargo, npm, Pipx, Aqua, Lua plugins |
| Define and run project tasks | references/task-runner.md | [tasks], mise run, depends, wait_for, MISE_PROJECT_ROOT |
| Watch files and rerun tasks automatically | references/commands-reference.md | mise watch, watchexec, --restart, --filter |
| Manage environment variables and secrets | references/environment-secrets.md | `_.path`, `_.file`, templating, SOPS, fnox |
| Advanced: caching, hooks, Pitchfork daemons | references/advanced-features.md | msgpack cache, Lua hooks, Pitchfork, Usage completions |
| Migrate from asdf, nvm, or direnv | references/core-concepts.md | .tool-versions, .nvmrc, compatibility |
| Run tools from an agent or non-interactive shell | references/agents-and-editors.md | mise exec, mise activate, --shims, why rc files do not reach agent commands |
| Install language servers and debug adapters through mise | references/agents-and-editors.md | conf.d, aqua, npm, pypi, dotnet and github backends; disabling Mason |
| Team workflows, CI/CD, lockfiles | references/advanced-features.md | mise.lock, monorepo tasks, CI integration |

## Orchestration Protocol

### Phase 1: Classify the Task

Identify which category the user's request falls into:

- **Setup**: installing mise, activating in shell, configuring global tools
- **Configuration**: writing or editing mise.toml, pinning versions, managing hierarchy
- **Tool management**: installing, listing, upgrading, or switching runtime versions
- **Backends**: choosing the right backend for a tool (ubi, aqua, cargo, npm)
- **Tasks**: defining and running tasks, task dependencies, monorepo tasks
- **Environment**: setting env vars, PATH modifications, .env file loading
- **Secrets**: SOPS encryption, fnox remote secrets
- **Advanced**: caching internals, Lua plugins, Pitchfork daemons, shell hooks
- **Migration**: moving from asdf, nvm, pyenv, or direnv

### Phase 2: Load the Right Resource

Load the resource indicated in the Quick Reference Table. For tasks spanning multiple areas (e.g. "set up a new project with tools, tasks, and secrets"), load all relevant files. The files are lean enough to load together.

### Phase 3: Execute

Apply guidance from the loaded resource. Produce complete, commented mise.toml snippets where configuration is involved. Always suggest `mise doctor` as the first debugging step for any environment issue.

## Common Task Workflows

### Workflow 1: Bootstrap a New Project

1. Load references/core-concepts.md for config hierarchy
2. Create mise.toml in the project root with [tools] for required runtimes
3. Add [env] section for project-specific environment variables
4. Run `mise install` to install all declared tools
5. Commit mise.toml; add mise.local.toml to .gitignore for personal overrides

```toml
[tools]
node = "22"
python = "3.12"

[env]
NODE_ENV = "development"
_.path = ["./node_modules/.bin"]
```

### Workflow 2: Replace nvm / asdf

1. Load references/core-concepts.md
2. Mise auto-reads .nvmrc and .tool-versions, no conversion needed immediately
3. Activate mise in shell profile: `eval "$(mise activate zsh)"`
4. Uninstall nvm/asdf once comfortable; run `mise doctor` to verify
5. Migrate to mise.toml to unlock env vars and tasks

### Workflow 3: Define Project Tasks

1. Load references/task-runner.md
2. Add [tasks.name] blocks to mise.toml
3. Set depends for prerequisite tasks
4. Run: `mise run <task>` or `mise run --list` to see all tasks

### Workflow 4: Manage Secrets with SOPS

1. Load references/environment-secrets.md
2. Install sops: `mise use --global sops`
3. Encrypt secrets file with age key
4. Reference in mise.toml: `_.file = { path = "secrets.enc.json", decrypt = true }`

### Workflow 5: Troubleshoot Environment Issues

1. Run `mise doctor`, surfaces shell integration problems, PATH issues, shim conflicts
2. Run `mise env`, shows exactly which env vars mise will set in the current directory
3. Run `mise ls`, lists active tool versions in the current directory
4. Load references/core-concepts.md for config hierarchy to diagnose overrides

### Workflow 6: Run Tools from an Agent or Non-Interactive Shell

1. Load references/agents-and-editors.md
2. Prefix each command with `mise exec --` (or call `mise run <task>`); do not rely on `mise activate`, which lives in an interactive rc file
3. If a tool is missing there, run `mise which <tool>` and `mise ls --current`; declare the tool in mise if it is missing
4. Check a PATH-only consumer with `zsh -lc 'command -v <tool>'` or `bash -c 'command -v <tool>'`, not the terminal

### Workflow 7: Install Language Servers Through mise

1. Load references/agents-and-editors.md
2. Declare servers in a global conf.d file, one backend per tool (aqua, npm, pypi, dotnet, github)
3. Turn off the editor's installer if mise is the sole manager
4. Verify with `mise which <server>` and `mise exec -- <server> --version`

## Resource Summaries

| File | Contents | Lines |
|------|----------|-------|
| references/core-concepts.md | Installation, shell activation, mise.toml format, config hierarchy, migration from asdf/nvm | ~280 |
| references/commands-reference.md | Full command reference: use, install, upgrade, exec, ls, prune, doctor, env | ~240 |
| references/backends.md | Core, UBI, Cargo, npm, Pipx, Aqua backends; Lua plugin architecture; writing custom plugins | ~260 |
| references/task-runner.md | Task definitions, depends, parallel execution, file tasks, monorepo tasks, Usage completions | ~250 |
| references/environment-secrets.md | [env] reference, PATH management, Tera templating, SOPS integration, fnox remote secrets | ~240 |
| references/advanced-features.md | Caching architecture, Lua lifecycle hooks, Pitchfork daemon manager, shell hooks, team CI/CD | ~260 |
| references/agents-and-editors.md | mise exec versus activate in agent and non-interactive shells, shims, language servers and debug adapters through mise, symptoms | ~190 |

## Best Practices

- **Use `mise exec --` in agent commands**: `mise activate` lives in an interactive rc file, which a non-interactive command never reads; `mise exec --` needs no activation
- **Commit mise.toml**: treat it as the project's source of truth for the toolchain; everyone on the team gets the same runtimes
- **Use mise.local.toml for personal overrides**: add it to .gitignore; never commit personal paths or secrets
- **Prefer `mise use` over hand-editing**: `mise use node@22` writes the correct version and installs the tool atomically
- **Global tools = CLI utilities only**: use `mise use --global` for ripgrep, bat, gh; enforce local versions for runtimes to ensure reproducibility
- **Always run `mise doctor` first**: it diagnoses 90% of "tool not found" / "wrong version" issues instantly
- **Use lockfiles for CI strictness**: enable mise.lock (experimental) to pin exact patch versions
- **Don't mix mise + asdf shims**: they conflict on PATH; remove asdf entirely when migrating
- **For dynamic task targets, use `usage` args**: prefer one stable task name (for example `skill:test:skill <skill>`) over many duplicated static names; dynamic task names are not automatic unless explicitly defined

## External References

- [mise documentation](https://mise.jdx.dev), official docs
- [mise GitHub](https://github.com/jdx/mise), source and releases
- [mise backends list](https://mise.jdx.dev/dev-tools/backends/), all available backends
- [mise plugins registry](https://github.com/mise-plugins/registry), community plugins
- [SOPS documentation](https://github.com/mozilla/sops), secrets encryption
- [Pitchfork](https://github.com/jdx/pitchfork), daemon manager companion tool
- [fnox](https://github.com/jdx/fnox), remote secrets companion tool
