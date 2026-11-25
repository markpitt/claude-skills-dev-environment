<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/banner-dark.svg">
    <img src="docs/assets/banner-light.svg" alt="Developer environment" width="100%">
  </picture>
</h1>

Tooling around the code: mise, devcontainers, terminal multiplexers, git protection, hosting and markdown.

Tooling around the code rather than the code itself. `tmux-persist` is Linux only, because it relies on systemd user units. `git-protection` installs a global pre-push hook that refuses force pushes. The two markdown skills are too small for a repository of their own, so they ride here.

This is one of seven skill groups. [claude-skills](https://github.com/markpitt/claude-skills) lists them all and
holds the shared tooling: validation, packaging, the evaluation harness and the TUI.

## Skills

<!-- BEGIN GENERATED SKILL INDEX -->
| Skill | Bundled files | What it does |
|---|---|---|
| [atomic-commit-organiser](skills/atomic-commit-organiser/SKILL.md) | 3 files | Turn a dirty working tree, or several repositories at once, into commits grouped by intent, staging explicit… |
| [cloudflare-workers-static-site](skills/cloudflare-workers-static-site/SKILL.md) | none | Deploy a static site (Astro, Vite, Hugo, Eleventy, plain HTML) from a GitHub repo to Cloudflare Workers… |
| [container-image-updates](skills/container-image-updates/SKILL.md) | none | Check a Docker Compose stack's images for newer releases without pulling them, read the release notes for… |
| [devcontainers](skills/devcontainers/SKILL.md) | 5 files | Provides expert guidance on Development Containers (devcontainers), creating, configuring, and optimising… |
| [git-protection](skills/git-protection/SKILL.md) | none | Stop force pushes and history rewrites from a machine with a global git pre-push hook, and set the matching… |
| [internal-ca-trust](skills/internal-ca-trust/SKILL.md) | none | Make containers, language runtimes and headless browsers trust a private certificate authority (step-ca or… |
| [markdown-formatter](skills/markdown-formatter/SKILL.md) | 8 files | Formats markdown files according to best practices and common style guidelines. |
| [markdown-to-pdf](skills/markdown-to-pdf/SKILL.md) | 3 files | Produces high-quality PDF documents from Markdown using reproducible, automation-friendly workflows. |
| [mise](skills/mise/SKILL.md) | 7 files | Provides expert guidance on mise (mise-en-place), a polyglot dev tool and environment orchestrator that… |
| [public-repo-hygiene](skills/public-repo-hygiene/SKILL.md) | none | Make a private working repository safe to publish. |
| [tmux-persist](skills/tmux-persist/SKILL.md) | none | Keep tmux sessions across reboots on any Linux machine. |
| [traefik-lan-routes](skills/traefik-lan-routes/SKILL.md) | none | Publish a self-hosted service on the local network through Traefik v3, reachable only from LAN addresses… |
| [wsl-host-ops](skills/wsl-host-ops/SKILL.md) | none | Operate a WSL2 distribution from both sides of the boundary. |
| [zellij](skills/zellij/SKILL.md) | 1 file | Configure and operate zellij terminal multiplexer sessions. |

14 skills.
<!-- END GENERATED SKILL INDEX -->

## Install

Copy a skill directory into either skills location, then start a new session:

```bash
cp -r skills/<skill-name> ~/.claude/skills/    # personal, all projects
cp -r skills/<skill-name> .claude/skills/      # this project only
```

For Claude Desktop, zip the skill directory's contents and upload the zip under Settings,
Capabilities, Skills:

```bash
cd skills/<skill-name> && zip -r ../../<skill-name>.zip .
```

## Licence

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). Each skill directory carries its
own copy of the licence, so a skill copied out on its own stays covered.
