---
name: traefik-lan-routes
description: Publish a self-hosted service on the local network through Traefik v3, reachable only from LAN addresses, with a certificate from an internal ACME CA (step-ca) or from Let's Encrypt over the DNS-01 challenge, which works for a name that is never exposed to the internet. Covers routers, services and middlewares as Docker labels or a dynamic file, the HTTP to HTTPS redirect, the ipAllowList middleware, local DNS rewrites, the Cloudflare token scope for DNS-01, resolver start-up order and the checks that prove the route. Use when asked to add a LAN-only hostname for a container, move a service from an internal certificate to Let's Encrypt, or debug a Traefik route that returns 404, 403, a default certificate or a certificate error. Do NOT use for exposing a service to the internet through a tunnel, for making containers trust an internal CA as clients (use internal-ca-trust), or for nginx, Caddy or HAProxy.
license: Apache-2.0
metadata:
  version: "1.0.0"
  tags: "traefik, reverse-proxy, tls, lets-encrypt, acme, dns-01, cloudflare, step-ca, lan, ipallowlist, docker, homelab"
---

# Traefik LAN routes

A LAN-only route has four parts, and each fails in its own way: local DNS sends the name to Traefik, a
router matches the host on the right entry point, a middleware refuses addresses outside the LAN, and a
certificate resolver gives the router a certificate. This skill sets them up in that order and checks
each one, so a failure points at one part rather than at "Traefik".

## Critical boundaries

- **Back up before editing.** Copy the dynamic file, or the compose that carries the labels, before the
  change, and say where the copy is. Static configuration (`traefik.yml`) changes need a Traefik restart,
  which drops every route for a moment. Ask before restarting a shared Traefik.
- **The DNS token is a credential.** Never print it, commit it, or pass it on a command line. It goes in
  Traefik's environment from a file or the platform's secret store. Scope it to the one zone.
- **LAN-only means two locks.** The name resolves only on the LAN, and the router carries an
  `ipAllowList` middleware. DNS alone is not access control: anyone who sends the right `Host` header to
  an exposed Traefik reaches the service.
- **One change at a time.** Add the route, prove it, then change the certificate. Two simultaneous
  changes make a failure ambiguous.

## Choose the certificate

| Situation | Resolver | Why |
|---|---|---|
| Internal name (`*.home.arpa`, or a private zone you control) and an internal ACME CA | ACME pointed at the internal CA (`caServer`) | The clients must trust the internal root (internal-ca-trust) |
| A real domain you control, LAN only | Let's Encrypt with `dnsChallenge` | Publicly trusted, so no client needs an extra root, and no inbound port is opened |
| A real domain, reachable from the internet on port 80 | Let's Encrypt with `httpChallenge` | Only when the name is genuinely public |

HTTP-01 cannot work for a LAN-only name, because Let's Encrypt must reach it from the internet. DNS-01
proves control of the domain through a TXT record and needs no public A record at all.

## Procedure

### 1. Local DNS

Point the name at the Traefik host in the LAN resolver (AdGuard Home or Pi-hole rewrite, router DNS, or
a split-horizon zone). Check before touching Traefik:

```bash
dig +short <name> @<lan-resolver>          # the Traefik host's LAN address
dig +short <name> @1.1.1.1                 # empty for a LAN-only name, or NOT the LAN address
```

### 2. The route

The examples use a `redirect-to-https@file` middleware for the HTTP router. Many set-ups define it
already (check the file provider's directory). If yours does not, define it once in a dynamic file, or
the HTTP router is not loaded at all and the name returns 404:

```yaml
http:
  middlewares:
    redirect-to-https:
      redirectScheme:
        scheme: https
        permanent: true
```

As Docker labels on the service (Traefik's Docker or Swarm provider):

```yaml
labels:
  - traefik.enable=true
  - traefik.docker.network=<shared-proxy-network>
  - traefik.http.middlewares.<app>-lan.ipallowlist.sourcerange=192.168.1.0/24,10.0.0.0/8
  - traefik.http.routers.<app>-web.rule=Host(`<name>`)
  - traefik.http.routers.<app>-web.entrypoints=web
  - traefik.http.routers.<app>-web.middlewares=redirect-to-https@file,<app>-lan
  - traefik.http.routers.<app>-websecure.rule=Host(`<name>`)
  - traefik.http.routers.<app>-websecure.entrypoints=websecure
  - traefik.http.routers.<app>-websecure.middlewares=<app>-lan
  - traefik.http.routers.<app>-websecure.tls.certresolver=<resolver>
  - traefik.http.services.<app>.loadbalancer.server.port=<container-port>
```

Or as a dynamic file in the file provider's directory, for a target that is not a labelled container
(a host service, a container on a macvlan, another machine):

```yaml
http:
  routers:
    <app>:
      rule: Host(`<name>`)
      entryPoints: [websecure]
      middlewares: [<app>-lan]
      service: <app>
      tls:
        certResolver: <resolver>
    <app>-http:
      rule: Host(`<name>`)
      entryPoints: [web]
      middlewares: [redirect-to-https@file]
      service: <app>
  middlewares:
    <app>-lan:
      ipAllowList:
        sourceRange: ["192.168.1.0/24"]
  services:
    <app>:
      loadBalancer:
        servers:
          - url: http://<container-or-host>:<port>
```

- Traefik v3 calls it `ipAllowList`. `ipWhiteList` is the v2 name and is not loaded by v3.
- `traefik.docker.network` matters when the container is on several networks: Traefik otherwise picks
  one and may get an address it cannot reach.
- No host port is needed on the container. Remove a `ports:` mapping that only existed for testing, so
  the service is not reachable round the allowlist.
- An app behind a proxy often needs to be told to trust it (`trusted_proxies`, `X-Forwarded-*`, a
  public URL setting) or it builds wrong redirect URLs and rejects logins.

### 3. A DNS-01 resolver (Let's Encrypt)

The resolver is static configuration in `traefik.yml`:

```yaml
certificatesResolvers:
  letsencrypt-dns:
    acme:
      email: <contact address>
      storage: /etc/traefik/acme-dns.json
      dnsChallenge:
        provider: cloudflare
        resolvers: ["1.1.1.1:53", "1.0.0.1:53"]
```

- **Token scope (Cloudflare):** an API token with *Zone, DNS, Edit* and *Zone, Zone, Read*, limited to the
  one zone. A read-only DNS token fails at the point where lego writes the `_acme-challenge` TXT record;
  the Traefik log says it could not create the record.
- **Environment:** `CF_DNS_API_TOKEN` (and, if the zone lookup needs it, `CF_ZONE_API_TOKEN`) on the
  Traefik container. Other DNS providers use their own lego variable names; check the lego provider page.
- **Explicit resolvers** stop the propagation check from asking a LAN resolver that rewrites the name.
- **Start-up order:** Traefik reads resolvers only at start. A router that names a resolver Traefik does
  not have logs `nonexistent certificate resolver` and is served the default certificate. Add the
  resolver, then recreate Traefik, then deploy the route.
- **Traefik that also trusts an internal ACME CA:** if `LEGO_CA_CERTIFICATES` names the internal root, set
  `LEGO_CA_SYSTEM_CERT_POOL=true` too, or lego drops the public roots and cannot reach Let's Encrypt.
- **Testing:** point `caServer` at Let's Encrypt staging while iterating, to stay clear of the production
  rate limits, then remove it and delete the staging entries from the storage file.
- Keep the storage file mode 600. It holds the account key and every private key.

### 4. Prove it

```bash
curl -sS -o /dev/null -w '%{http_code}\n' https://<name>/                       # 200 or the app's code, from the LAN
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' http://<name>/         # 301/308 to https
openssl s_client -connect <name>:443 -servername <name> </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -subject -enddate                                 # the expected issuer
```

Prove the refusal as well as the success: from a client outside the range (a phone off Wi-Fi with
`--resolve <name>:443:<public-ip>`, if Traefik is reachable from outside at all), or by narrowing the
range to one address that is not yours, seeing the 403, and putting the range back. Read Traefik's log or
access log for the router name and the client address it recorded.

## Diagnosing

| Symptom | Usual cause |
|---|---|
| `404 page not found` from Traefik | No router matched: wrong `Host`, wrong entry point, the container not on the proxy network, `traefik.enable` missing, a label typo, or a middleware the router names does not exist (Traefik then does not load the router, and logs it) |
| `403 Forbidden` from the LAN | The allowlist sees another address: Docker's userland proxy, a NAT hop or an upstream proxy. Check the client address in the access log; use `ipStrategy` only when a trusted proxy sits in front |
| `TRAEFIK DEFAULT CERT` | The resolver failed or is unknown. Check the log for the resolver name and the ACME error |
| `502 Bad Gateway` | Traefik matched but cannot reach the backend: the port, the network, or the service listens on 127.0.0.1 only |
| Redirect loop | The app also redirects to HTTPS, or it is not told it sits behind a TLS-terminating proxy |
| Works by IP, not by name | Local DNS: step 1 |

## Neighbours

- **internal-ca-trust** makes clients and containers trust an internal root, needed when the route
  uses an internal CA, and for Traefik's own ACME client against one.
- **container-image-updates** covers upgrading the Traefik image itself. Read its release notes for
  label or middleware renames before a major version.
