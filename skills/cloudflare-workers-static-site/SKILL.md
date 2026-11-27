---
name: cloudflare-workers-static-site
description: Deploys a static site (Astro, Vite, Hugo, Eleventy, plain HTML) from a GitHub repo to Cloudflare Workers static assets, with GitHub Actions doing build, check and deploy on push to main. Use when a repo or monorepo subfolder holds a static or mostly static site that should go live on Cloudflare, or when moving a site off Cloudflare Pages or GitHub Pages. Do NOT use for Cloudflare Pages (`wrangler pages deploy`) or for server-rendered apps that need a framework adapter.
license: Apache-2.0
metadata:
  version: "1.0.1"
---

# Deploy a static site to Cloudflare Workers from GitHub

Use this when a repo holds a static site (or a mostly static one) and it should go live on Cloudflare. Workers static assets replaces Cloudflare Pages for new projects. Static requests are free and unlimited on the Workers Free plan; only requests that run Worker code count towards the 100,000 a day.

The end state:

- A `wrangler.jsonc` next to the site that points at the build output.
- `.github/workflows/<site>.yml`: every pull request builds and dry-run deploys; every push to `main` deploys.
- Two GitHub repository secrets, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
- The site live at `<worker-name>.<account-subdomain>.workers.dev`, then on a custom domain if wanted.

Templates are in `templates/`. Copy them, then fill in the `<...>` placeholders.

## 1. Work out the site's facts

Read the repo before writing anything. Record:

| Fact | Where to find it |
| --- | --- |
| Site folder | Repo root, or a subfolder such as `site/` or `web/` in a monorepo |
| Package manager | `package-lock.json` (npm), `pnpm-lock.yaml`, `yarn.lock`, `bun.lock`, or none |
| Node version | `.nvmrc`, `engines.node` in `package.json`, or the framework's minimum |
| Build command | `scripts.build` in `package.json` |
| Output folder | See the table below |
| Routing | Multi-page (one HTML file per route) or single-page app (one `index.html`, client routing) |
| Server code needed? | Forms, APIs, auth. If none, it is assets only and needs no Worker script |

Common output folders:

| Framework | Build | Output |
| --- | --- | --- |
| Astro (`output: "static"`) | `astro build` | `dist` |
| Vite, React, Vue, Svelte (SPA) | `vite build` | `dist` |
| SvelteKit with `adapter-static` | `vite build` | `build` |
| Next.js with `output: "export"` | `next build` | `out` |
| Angular | `ng build` | `dist/<project>/browser` |
| Hugo | `hugo --minify` | `public` |
| Eleventy | `npx @11ty/eleventy` | `_site` |
| Plain HTML | none | the folder itself (add `.assetsignore`, see gotchas) |

If the framework has a server or SSR mode switched on, either switch it to static output or use the framework's Cloudflare adapter. This skill covers static output.

## 2. Add Wrangler and the config

1. Add Wrangler as a pinned dev dependency so CI and local runs use the same version: `npm i -D -E wrangler@latest` (Wrangler 4.34 or later is needed for the higher file limit on paid plans).
2. Copy `templates/wrangler.assets-only.jsonc` to `<site>/wrangler.jsonc`. If the site needs server code for some paths (a form post, an API), copy `templates/wrangler.with-worker.jsonc` and `templates/worker.ts` instead.
3. Fill in:
   - `name`: lower case, hyphens. It becomes the `workers.dev` hostname, so pick it with care.
   - `compatibility_date`: today's date.
   - `assets.directory`: the output folder, relative to the config file.
   - `assets.not_found_handling`: `"404-page"` for multi-page sites (serves the nearest `404.html`), `"single-page-application"` for SPAs (serves `index.html` for unknown paths).
4. Add scripts to `package.json`:

```json
"deploy": "wrangler deploy",
"deploy:check": "wrangler deploy --dry-run --outdir .wrangler/dry-run",
"preview": "wrangler dev --port 8787"
```

5. Add `.wrangler/` to `.gitignore`.
6. Optional: copy `templates/_headers` into the folder the build copies verbatim (`public/` for Astro and Vite, `static/` for Hugo and SvelteKit). It sets security headers and long caching for hashed assets. Adjust the Content Security Policy to whatever the site loads.

Run `npm run build && npm run deploy:check` locally. It needs no Cloudflare login and catches a wrong `assets.directory` or a bad config.

## 3. Add the GitHub Actions workflow

Copy `templates/deploy.yml` to `.github/workflows/<site>.yml` and fill in:

- `<SITE_DIR>`: the site folder (use `.` for repo root, and delete the `paths:` filters).
- The Node version file path, or replace `node-version-file` with `node-version: 22`.
- The install, check, test and build commands for the package manager in use. Remove steps that have no script behind them rather than leaving them failing.

What the workflow does:

- Pull requests: install, check, test, build, dry-run deploy. No secrets are used, so forks are safe.
- Push to `main` (or a manual run): the same build, then `wrangler deploy` with the commit SHA as the deploy message.
- The deploy job runs in a GitHub `production` environment, so protection rules and a deployment link show up on the repo.
- A guard step fails with a clear message when the secrets are missing, instead of Wrangler's less obvious auth error.

## 4. One-off setup the person does

Claude cannot do these. Give the person these exact steps and wait for them.

1. **API token.** Cloudflare dashboard, **Manage account > Account API tokens > Create token**. Start from the **Edit Cloudflare Workers** template. Add more permissions only for bindings in use (for example **Account > D1 > Edit**, **Workers KV Storage > Edit**, **Workers R2 Storage > Edit**). Scope it to the one account, and to the zone if a custom domain will be attached through config.
2. **Account ID.** Dashboard, **Account home**, the account's menu, **Copy account ID**.
3. **GitHub secrets.** Repo **Settings > Secrets and variables > Actions > New repository secret**: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.
4. Optional: a repository variable `SITE_URL` (for example `https://example.com`) if the build uses it for canonical and Open Graph links.

The first push to `main` creates the Worker. Resources declared without IDs (such as a D1 database with only `database_name`) are created by Wrangler on first deploy and stay linked.

## 5. Check it is live

1. Open the workflow run and check the deploy step printed a `https://<name>.<subdomain>.workers.dev` URL.
2. Fetch it: `curl -sI https://<name>.<subdomain>.workers.dev/` should return `200` and your headers.
3. Fetch a missing path and check it returns the 404 page (or `index.html` for an SPA).
4. If it redirects to a Cloudflare Access login, see the first gotcha.

## 6. Custom domain (optional)

The domain's DNS must be on Cloudflare (Free plan is fine). Either:

- Dashboard: the Worker, **Settings > Domains & Routes > Add > Custom domain**. Simplest, and survives deploys.
- Config: add `"routes": [{ "pattern": "example.com", "custom_domain": true }]` to `wrangler.jsonc`. The API token then needs zone access.

To stop the `workers.dev` address serving once the custom domain works, set `"workers_dev": false` and `"preview_urls": false`.

## Gotchas

- **Site asks for a Cloudflare login.** The account has Cloudflare Access protecting `workers.dev` (some accounts turn on "protect all Workers"). The deploy worked; the site is just private. To make it public: the Worker, **Settings > Domains & Routes**, `workers.dev`, **Disable Cloudflare Access**, or remove the app under **Zero Trust > Access > Applications**. Leave it on while the site is not ready for the public; it is a free way to keep a staging site private. Tell the person which state it is in.
- **Wrong output folder.** A deploy that uploads 0 or a handful of files, or serves the repo's README, means `assets.directory` is wrong. `deploy:check` shows the file count.
- **Assets at the repo root.** If `assets.directory` is `.` or contains source files, add an `.assetsignore` (gitignore syntax) listing `node_modules`, `.git`, `.wrangler`, `wrangler.jsonc` and anything private. Without it they get uploaded and served.
- **Limits.** Free plan: 20,000 files per version, 25 MiB per file. Paid: 100,000 files. Put large media in R2.
- **`_headers` and `_redirects`** go in the output folder (so in `public/` before the build). Up to 100 header rules and 2,100 redirects.
- **Trailing slashes.** The default `html_handling` (`auto-trailing-slash`) suits most generators. Match the framework's own setting (Astro `trailingSlash`, Hugo `uglyURLs`) or links will 307 redirect.
- **Run Worker code only where needed.** With a Worker script, use `"run_worker_first": ["/api/*"]` so every other request stays a free static hit.
- **Do not use `cloudflare/pages-action`** or `wrangler pages deploy`. That is Cloudflare Pages, a different product.
- **Secrets on forks.** Fork pull requests get no secrets, which is why pull requests only dry-run.
- **PR previews (optional).** Wrangler 4.135+ has `wrangler preview` for branch Previews with their own URLs. Check the current Cloudflare docs (`/workers/previews/`) before adding it; it needs the token on pull request runs, so limit it to branches in the same repo.

## Migrating from Cloudflare Pages

1. Create `wrangler.jsonc` as above, with `assets.directory` set to the old Pages build output folder.
2. `_headers` and `_redirects` keep working. Pages Functions (`functions/`) do not; move that code into a Worker script.
3. Deploy, attach the custom domain to the Worker, then delete the Pages project.

## When done

Report: the Worker name, the live URL, whether Access is on, what the person still has to do (secrets, domain), and the workflow file path. Put the setup steps from section 4 in the site's README so the next person finds them.
