---
name: internal-ca-trust
description: Make containers, language runtimes and headless browsers trust a private certificate authority (step-ca or any internal root) so they can reach internal HTTPS services, without dropping the public roots. Covers fetching and fingerprinting the root, the system store for root and non-root images, Python (requests, certifi, httpx, aiohttp), Node, git and curl variables, Chromium and Playwright, ACME clients such as Traefik's lego, and the checks that prove it worked. Use when a container or tool fails with "certificate verify failed", "unable to get local issuer certificate" or "self-signed certificate in certificate chain" against an internal hostname, or when a stack must start calling internal HTTPS services. Do NOT use to run or configure the CA itself (issuing, provisioners, renewal), for public certificates from Let's Encrypt (use traefik-lan-routes), or to switch TLS verification off.
license: Apache-2.0
metadata:
  version: "1.0.0"
  tags: "tls, ca, step-ca, certificates, docker, compose, python, certifi, node, playwright, chromium, lego, traefik"
---

# Internal CA trust

An internal root is trusted in one place per runtime, and runtimes do not share a place. A container that
trusts the root in its system store can still fail from Python, because `requests` reads `certifi`, not
the system store. This skill adds the root everywhere a given process actually looks, keeps the public
roots beside it, and proves the result from inside the running container.

## Critical boundaries

- **Never turn verification off.** `verify=False`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `curl -k`,
  `GIT_SSL_NO_VERIFY` and `--insecure` are not fixes. If a tool offers only those, say so and stop.
- **Add, never replace.** A bundle that holds only the internal root breaks every public HTTPS call the
  process makes. Each method below appends the root to the existing public roots.
- **Check the root before trusting it.** Compare its SHA-256 fingerprint with the one the CA reports
  (`step certificate fingerprint`, or the value recorded when the CA was set up). A root fetched over an
  unverified connection is only as trustworthy as that connection.
- **The root is public, its key is not.** Mount `root_ca.crt` read-only. Never copy, mount or print the
  CA's private keys or its provisioner passwords.
- **One source file on the host.** Mount the same root file into every container. Copies drift when the
  root is re-issued.
- **Back up the compose before editing it.** A trust change needs a recreate, so keep the previous
  definition to roll back to.

## Procedure

### 1. Get the root and fingerprint it

```bash
step ca root root_ca.crt --ca-url https://<ca-host> --fingerprint <expected-fingerprint>
step certificate fingerprint root_ca.crt      # or:
openssl x509 -in root_ca.crt -noout -fingerprint -sha256 -subject -enddate
```

`step ca root` refuses to save a root whose fingerprint does not match. Without the `step` CLI, fetch
`https://<ca-host>/roots.pem` and compare the `openssl` fingerprint by hand. Record where the host copy
lives; every mount below points at it.

### 2. Find out where the failing process looks

Before changing anything, establish for each container that needs the root:

| Question | How to answer it |
|---|---|
| Which user runs the process? | `docker exec <c> id`, or `docker inspect --format '{{.Config.User}}' <image>` |
| Is `update-ca-certificates` (Debian, Ubuntu, Alpine) or `update-ca-trust` (RHEL, Fedora) there? | `docker exec <c> sh -c 'command -v update-ca-certificates update-ca-trust'` |
| Which runtime makes the call? | Python, Node, Go, Java, curl, git or a browser: the table in step 4 |
| What is the image's original entrypoint and command? | `docker inspect --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}' <image>` |

You need the original entrypoint and command, because wrapping one (step 3b) must still end by running it.

### 3a. Root images: update the system store at start

Mount the root where the store tool picks it up, refresh the store before the real start command, and
point the runtimes at the merged bundle:

```yaml
services:
  app:
    volumes:
      - /srv/ca/root_ca.crt:/usr/local/share/ca-certificates/internal-ca.crt:ro
    command: ["bash", "-c", "update-ca-certificates && exec <original start command>"]
    environment:
      SSL_CERT_FILE: /etc/ssl/certs/ca-certificates.crt
      REQUESTS_CA_BUNDLE: /etc/ssl/certs/ca-certificates.crt
      CURL_CA_BUNDLE: /etc/ssl/certs/ca-certificates.crt
```

- The file name must end in `.crt` for `update-ca-certificates` to pick it up.
- On RHEL-family images mount into `/etc/pki/ca-trust/source/anchors/` and run `update-ca-trust`; the
  bundle is `/etc/pki/tls/certs/ca-bundle.crt`.
- Replace `command`, not `entrypoint`, when the image's entrypoint does real set-up, and keep the
  original command after `exec` so signals still reach the main process.
- A `command:` override is passed as arguments to the image's entrypoint. The form above works only when
  the entrypoint ends in `exec "$@"` (or there is none). Otherwise use the entrypoint wrapper in 3b,
  adding `update-ca-certificates` to it.

### 3b. Non-root images: build a bundle the user can write

A non-root process cannot run `update-ca-certificates`. Concatenate the system bundle and the root into
a file under `/tmp` at start, then point every runtime at that file:

```yaml
services:
  app:
    volumes:
      - /srv/ca/root_ca.crt:/etc/internal-ca/root.crt:ro
    entrypoint:
      - /bin/sh
      - -c
      - cat /etc/ssl/certs/ca-certificates.crt /etc/internal-ca/root.crt > /tmp/ca-bundle.crt && exec "$$@"
      - sh
    command: ["<original entrypoint>", "<original args>"]
    environment:
      SSL_CERT_FILE: /tmp/ca-bundle.crt
      REQUESTS_CA_BUNDLE: /tmp/ca-bundle.crt
      CURL_CA_BUNDLE: /tmp/ca-bundle.crt
      GIT_SSL_CAINFO: /tmp/ca-bundle.crt
      NODE_EXTRA_CA_CERTS: /etc/internal-ca/root.crt
```

- `$$` escapes `$` from compose interpolation. The trailing `sh` becomes `$0`, so `"$@"` is the command.
- When the image has no system bundle (slim Python images rely on `certifi`), start from certifi
  instead: `cat "$$(python -c 'import certifi; print(certifi.where())')" /etc/internal-ca/root.crt > /tmp/ca-bundle.crt`.
- Print one line from the wrapper (`echo 'internal-ca: bundle written'`) so the logs show it ran.

### 4. Per-runtime variables

| Runtime | What it reads | Set |
|---|---|---|
| OpenSSL-based tools, Go, Ruby, aiohttp | `SSL_CERT_FILE` (a bundle), or the system store | the merged bundle |
| Python `requests` | `REQUESTS_CA_BUNDLE`, otherwise certifi, never the system store | the merged bundle |
| Python `httpx` | `SSL_CERT_FILE` in most versions (check the installed one); code may pass `verify=` explicitly | the merged bundle |
| curl | `CURL_CA_BUNDLE`, otherwise its compiled-in bundle | the merged bundle |
| git | `GIT_SSL_CAINFO`, or `http.sslCAInfo` | the merged bundle |
| Node.js | `NODE_EXTRA_CA_CERTS`, added to its own compiled-in roots | the root alone is enough |
| Java | the JDK `cacerts` keystore | `keytool -importcert -cacerts -alias internal-ca -file root.crt -noprompt` in a derived image |
| Chromium, Chrome, Playwright | the NSS database or a managed policy, not `SSL_CERT_FILE` | step 5 |

An application can override all of these with its own setting (`ssl_verify`, `ca_file`, a
`*_TLS_CACERTFILE` variable). Read the application's documentation for a CA option before relying on
the environment. A per-app CA option that names only the internal root rejects public certificates, so
point it at the merged bundle as well.

### 5. Browsers and Playwright

Chromium on Linux reads trust from an NSS database in the user's profile, not from `SSL_CERT_FILE`.

- **Preferred, when `certutil` (package `libnss3-tools`) is in the image:**
  `certutil -d sql:$HOME/.pki/nssdb -A -t "C,," -n internal-ca -i /etc/internal-ca/root.crt`, run at
  start as the browser's user. Create the database with `certutil -d sql:$HOME/.pki/nssdb -N --empty-password` if it does not exist.
- **Without certutil:** a managed policy file in `/etc/chromium/policies/managed/` (Chromium) or
  `/etc/opt/chrome/policies/managed/` (Chrome) that lists the root under the `CACertificates` policy.
  Not every build or headless mode honours it, so treat it as untested until step 6 passes.
- **Playwright from code:** `ignoreHTTPSErrors` is the same as turning verification off; do not use it.

### 6. Recreate and prove it from inside

A file mount change alone does not always recreate a container. Recreate explicitly
(`docker compose up -d --force-recreate <service>`, or the platform's redeploy), then check from inside:

```bash
docker exec <c> sh -c 'grep -c "BEGIN CERTIFICATE" "$SSL_CERT_FILE"'              # more than the system count
docker exec <c> curl -sS -o /dev/null -w '%{http_code}\n' https://<internal-host>/   # internal works
docker exec <c> curl -sS -o /dev/null -w '%{http_code}\n' https://example.com/       # public still works
docker exec <c> python3 -c 'import requests; print(requests.get("https://<internal-host>/").status_code)'
```

Run the check in the runtime that failed, not only with curl: curl passing says nothing about Python's
`requests`. Report each container's internal and public result, and the log line from the wrapper.

## ACME clients behind an internal CA

Traefik's ACME client (lego) can be told to trust an internal root with `LEGO_CA_CERTIFICATES`. On its
own that replaces the system pool, so Let's Encrypt's API then fails TLS. Set
`LEGO_CA_SYSTEM_CERT_POOL=true` as well, so lego keeps the public roots and adds the internal one.
Traefik reads both only at start, so recreate the container after setting them.

## Gotchas

- **Trust is not reachability.** A container that cannot resolve the internal name fails before TLS.
  Check DNS from inside the container (`getent hosts <internal-host>`) before blaming trust.
- **A hostname move breaks pinned CA options.** When a service moves from an internal certificate to a
  public one, every client whose CA option names only the internal root starts failing. Search the
  stacks for those options before the move.
- **Hostname mismatch looks like a trust failure.** `openssl s_client -connect <host>:443 -servername <host> -CAfile root.crt`
  shows whether the chain verifies and which names the certificate carries.
- **Root rotation.** When the CA's root changes, every mount still holds the old file until it is
  replaced and the containers are recreated. The single host copy keeps that to one file change.

## Neighbours

- **traefik-lan-routes** publishes an internal service behind Traefik, with an internal or a
  Let's Encrypt certificate.
- **container-image-updates** covers image upgrades. Recheck the CA wrapper after one, because a new
  image can change its entrypoint, user or bundle path.
