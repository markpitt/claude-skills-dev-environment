---
name: container-image-updates
description: Checks a Docker Compose stack's images for newer releases without pulling them, reads the release notes for breaking changes and one-way migrations, checks version coupling between services, then pins the chosen versions by tag and digest, backs up, deploys, verifies and keeps a rollback ready. Queries Docker Hub, GHCR and other OCI registries over their HTTP APIs with anonymous pull tokens, and resolves the multi-architecture index digest. Use when asked whether a stack has updates, to update or pin an image, to move images off moving tags such as latest or main, or after a deploy that did not pick up a new image. Do NOT use for building or publishing your own images, for automatic updaters such as Watchtower or Renovate, or for Kubernetes rollouts.
license: Apache-2.0
metadata:
  version: "1.0.1"
  tags: "docker, compose, images, registry, oci, digest, pinning, upgrades, ghcr, docker-hub, rollback, release-notes"
---

# Container image updates

An update is three decisions: which version, whether its changes are safe for this data, and how to get
back. This skill answers the first from the registry and the release notes without touching the running
stack, puts the answer to the operator, and only then changes anything. Every image ends pinned by tag
and digest, so the next update is a deliberate edit and the rollback is the previous line.

## Critical boundaries

- **Checking is read-only.** Querying registries and reading release notes changes nothing. Pulling,
  editing the compose and deploying do, and need the operator's go-ahead for this update.
- **One-way migrations need a data backup first.** Many apps migrate their database on start and cannot
  run the old version against the new schema. A compose backup alone does not roll that back. Say which
  volumes hold the data, and get a data backup (or the operator's acceptance that there is none) before
  the deploy.
- **Never pin to a digest you did not resolve.** Copy digests from the registry response, not from memory,
  a changelog or a search result.
- **Patch, minor and major are different asks.** Present each with its risk. Do not fold a major version
  into "updates available".

## Procedure

### 1. Inventory what runs

```bash
docker compose -f <compose> config --images                 # what the compose asks for
docker ps --format '{{.Names}}\t{{.Image}}'                   # what runs
docker inspect --format '{{.Name}} {{.Image}}' $(docker ps -q)     # the image ID each container runs
docker image inspect --format '{{.RepoDigests}}' <image-id>         # the digest that image was pulled by
```

`RepoDigests` is an image field, not a container field, so it is read with `docker image inspect`. Use
`{{.RepoDigests}}` rather than `index ... 0`: a locally built image has none, and `index` then fails.

Record for each service: the reference (`image:tag` or `image@digest`), the running digest, and the
`pull_policy`. A moving tag (`latest`, `main`, `stable`, a bare major) with `pull_policy: missing` never
updates on deploy, so the running version may be months older than the tag suggests.

### 2. Find newer versions without pulling

Get an anonymous pull token, list tags, then read the digest from a HEAD request. Ask for the index
types, so a multi-architecture image returns its index digest rather than one platform's manifest.

```bash
ACCEPT='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

# Docker Hub (official images are library/<name>)
t=$(curl -fsS "https://auth.docker.io/token?service=registry.docker.io&scope=repository:<ns>/<repo>:pull" | jq -r .token)
curl -fsS "https://hub.docker.com/v2/repositories/<ns>/<repo>/tags?page_size=100&ordering=last_updated" \
  | jq -r '.results[] | "\(.name)\t\(.last_updated)"'
curl -fsSI -H "Authorization: Bearer $t" -H "Accept: $ACCEPT" \
  "https://registry-1.docker.io/v2/<ns>/<repo>/manifests/<tag>" | grep -i docker-content-digest

# GHCR
t=$(curl -fsS "https://ghcr.io/token?scope=repository:<owner>/<repo>:pull" | jq -r .token)
curl -fsS -H "Authorization: Bearer $t" "https://ghcr.io/v2/<owner>/<repo>/tags/list?n=1000" | jq -r '.tags[]'
curl -fsSI -H "Authorization: Bearer $t" -H "Accept: $ACCEPT" \
  "https://ghcr.io/v2/<owner>/<repo>/manifests/<tag>" | grep -i docker-content-digest
```

- `docker buildx imagetools inspect <image>:<tag>`, `skopeo inspect` or `crane digest` give the same
  digest where those tools are installed.
- Other registries follow the same `/v2/` API. Read the `WWW-Authenticate` header of an unauthenticated
  request to find the token endpoint.
- Tag lists are not sorted by version. Filter to the project's release pattern and sort with
  `sort -V`, and take the project's **releases page** as the authority on which tag is the latest stable.
  Pre-release, nightly and `-rc` tags are not updates.
- GitHub releases: `curl -fsS https://api.github.com/repos/<owner>/<repo>/releases?per_page=10 | jq -r '.[] | "\(.tag_name)\t\(.published_at)\t\(.prerelease)"'`.

### 3. Read what changed

For each candidate, read every release note between the running version and the target, not only the
target's. Note:

- breaking changes, renamed or removed settings and environment variables;
- database or schema migrations, and whether they are reversible;
- a changed default user, port, entrypoint or data path (these break mounts and wrappers);
- a release only hours old: fine for a fresh install, riskier for one with data.

### 4. Check coupling between services

Some services must move together. Look for a pinned client version in the main app's dependency files or
its own example compose (a browser server that must match a library version, a database major the app
supports, a worker that must match the server). Read the main app's `requirements.txt`,
`pyproject.toml`, `package.json` or example `docker-compose*.yml` at the target tag. "Latest" for a
coupled service is often wrong.

### 5. Propose

Give the operator one line per service: current, proposed, kind (patch, minor, major), the notable
changes, the migration risk, and what rollback needs. Recommend, and wait for the choice.

### 6. Apply

1. Back up the compose definition, and the data volumes where step 3 found a one-way migration.
2. Pin as `image: <repo>:<tag>@sha256:<index-digest>`. The tag is for humans; the digest is what runs.
3. Deploy, and check the container was recreated (`docker ps` shows a new `CreatedAt`, the running
   digest matches the pin).
4. Verify: the container is healthy, the restart count is 0, the logs since start have no new errors,
   and the app answers on its health endpoint or main page. Check the services that depend on it too.
5. Record what changed, the backup paths and the exact rollback.

### 7. Roll back

Restore the previous compose (the old pinned line) and redeploy. If the new version migrated the data,
restore the data backup as well, with the container stopped. Without a data backup a rollback after a
migration may not be possible; that is why step 3 asks.

## Gotchas

- **Index digest, not platform digest.** `docker image inspect` `RepoDigests` gives the index digest the
  image was pulled by. A digest copied from the registry web page may be one platform's manifest, which then
  fails to pull on another architecture.
- **Mount-only changes do not recreate.** A deploy that changes only a mounted config file may leave the
  container running the old config. Recreate explicitly, or bump a harmless environment value.
- **Docker Hub rate limits** count manifest GETs. HEAD requests for digests are not counted, so prefer
  them when checking many images.
- **Wrappers depend on the image.** An entrypoint wrapper (for CA trust, for example) assumes the image's
  shell, user and paths. Recheck it after every update.

## Neighbours

- **internal-ca-trust** for the CA wrapper that an update can break.
- **traefik-lan-routes** when the update is to Traefik itself or changes a service's port.
