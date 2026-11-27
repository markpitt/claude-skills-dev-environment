---
name: devcontainers
description: Writes, fixes and speeds up development containers under the Dev Container Specification. Covers devcontainer.json, Dev Container Features and Templates, lifecycle commands, pre-built images, multi-container setups with Docker Compose, Docker-in-Docker and Docker-outside-of-Docker, non-root users and secrets, and GitHub Codespaces and DevPod. Use when creating or editing a .devcontainer folder, adding a tool to a dev container, when a container is slow to build or start, when files created inside it have the wrong owner, when SSH or Git credentials do not work inside it, or when asked to set up a dev container for a repository. Do NOT use for production Dockerfiles or image publishing with no dev container involved, for Kubernetes deployments, or for installing tool versions on the host with mise (use mise).
license: Apache-2.0
metadata:
  version: "2.0.0"
  tags: [docker, containers, devcontainers, vscode, codespaces, devpod]
---

# Dev containers

A dev container is a `devcontainer.json`, usually in `.devcontainer/`, that tells VS Code, the
`devcontainer` CLI, Codespaces or DevPod how to build a container and attach to it. The
[specification](https://containers.dev) is shared by all of them, so a file that works in one
should work in the others.

Produce a complete, commented `devcontainer.json` (and the Dockerfile or Compose file it needs)
rather than describing one.

## Three ways to define the container

| Use | When |
|---|---|
| `image` | A published image plus Features covers it. The simplest, and the right start for most repos |
| `build.dockerfile` | You need system packages or steps no Feature provides |
| `dockerComposeFile` | The app needs other services (a database, a cache) running beside it |

A minimal file:

```jsonc
{
  "name": "my-project",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/devcontainers/features/node:1": { "version": "24" },
    "ghcr.io/devcontainers/features/git:1": {}
  },
  "customizations": {
    "vscode": { "extensions": ["dbaeumer.vscode-eslint"] }
  },
  // Runs once, after the container is created, so the workspace is ready to use.
  "postCreateCommand": "npm ci",
  "forwardPorts": [3000],
  // The Microsoft base images ship a non-root user called vscode.
  "remoteUser": "vscode"
}
```

## Decisions that matter

- **Pin versions.** Features by major version (`node:1`), base images by tag, and the tool versions
  inside Features. An unpinned container builds differently next month.
- **Run as a non-root user.** Set `remoteUser`, and leave `updateRemoteUserUID` at its default of
  `true` on Linux so files you create in the workspace are owned by you on the host.
- **Put setup in lifecycle commands.** `postCreateCommand` for dependency installs, and
  `postStartCommand` for anything that must run on every start. Someone opening the repo should not
  have to read a README first.
- **Keep production Compose files untouched.** Add a `docker-compose.dev.yml` with the source mount
  and debug ports, list both in `dockerComposeFile`, set `service` to the container to attach to,
  and set `shutdownAction: "none"` if the services should outlive the editor.
- **Keep secrets out of the image.** Use SSH agent forwarding (the VS Code extension forwards a
  running local agent), BuildKit secret mounts, or a git-ignored `.env`. Never copy a private key in.
- **Pre-build when start-up is slow.** Build the image in CI with the `devcontainer` CLI, push it,
  and point `image` at it. Start-up goes from minutes to seconds, and the metadata travels in the
  image labels.
- **Use named volumes for heavy folders on macOS and Windows.** Bind mounts there are slow, so put
  `node_modules` and similar in a named volume.

## When it goes wrong

| Symptom | Usual cause | Reference |
|---|---|---|
| Files owned by root or the wrong UID on the host | `remoteUser` unset, or `updateRemoteUserUID` turned off | `references/troubleshooting.md` |
| `git push` fails inside the container | No SSH agent running on the host, or a key copied in instead of forwarded | `references/troubleshooting.md` |
| Builds take minutes every time | Dockerfile order invalidates the cache, or no pre-built image | `references/performance-security.md` |
| Slow file access on macOS or Windows | Heavy folders on a bind mount | `references/performance-security.md` |
| `postCreateCommand` fails silently | The command needs a Feature that installs after it, or a service not yet up | `references/troubleshooting.md` |

## References

| File | Covers |
|---|---|
| `references/core-concepts.md` | Every `devcontainer.json` property, lifecycle hooks, file location precedence |
| `references/features-templates.md` | Using and writing Features, install order, Templates |
| `references/advanced-config.md` | Compose setups, Docker-in-Docker and Docker-outside-of-Docker, Kubernetes, Codespaces, DevPod |
| `references/performance-security.md` | Layer caching, named volumes, pre-built images, non-root users, secrets |
| `references/troubleshooting.md` | Permission errors, slow I/O, SSH and GPG credentials, lifecycle failures |

External: the [devcontainer.json reference](https://containers.dev/implementors/json_reference/),
the [Features](https://containers.dev/features) and [Templates](https://containers.dev/templates)
registries, the [VS Code docs](https://code.visualstudio.com/docs/devcontainers/containers),
[Codespaces](https://docs.github.com/en/codespaces), [DevPod](https://devpod.sh/docs) and the
[devcontainer CLI](https://github.com/devcontainers/cli).
