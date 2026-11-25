// Runs only for paths listed in assets.run_worker_first (for example /api/*).
// Everything else is served straight from the static assets.

interface Env {
  ASSETS: Fetcher;
  // DB: D1Database;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/api/health") {
      return Response.json({ ok: true });
    }

    // Unknown /api/* path: fall back to the static site (its 404 page).
    return env.ASSETS.fetch(request);
  },
} satisfies ExportedHandler<Env>;
