# Engine and Standards Reference

## Evidence Baseline

Ground recommendations in official documentation:

- Pandoc user guide (`--pdf-engine`, defaults files, sandbox, reproducibility notes)
- Typst docs (document metadata and deterministic date handling)
- Engine docs for WeasyPrint/Prince when HTML-driven PDF is requested

## Engine Selection Matrix

- `lualatex`
  - Best for broad Pandoc compatibility and mature print-quality control.
  - Use when TeX-level typographic control is needed.
- `tectonic`
  - Best for CI-friendly LaTeX workflows with simpler setup.
  - Good when deterministic automation is more important than TeX customisation depth.
- `weasyprint`
  - Best when CSS Paged Media/web-print parity is required.
  - Validate feature support per pinned version.
- `typst`
  - Best for modern template ergonomics and fast iteration.
  - Use explicit options and pinned versions in CI.
- `prince`
  - Best for enterprise HTML/CSS-to-PDF and advanced commercial features.
  - Requires license and explicit runtime assumptions.

## Standards Guidance

For accessibility/archival requests:

- Prefer explicit standards settings instead of vague claims.
- Typical targets: PDF/UA and/or PDF/A.
- Treat standards support as engine+version+input dependent.
- Always require external validation tooling before declaring compliance.

## Practical Advice

- Start with one engine and a fixed profile per document family.
- Avoid engine switching in the same pipeline unless required.
- Keep templates/styles versioned and reviewed as production assets.
