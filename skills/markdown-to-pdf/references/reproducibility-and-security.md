# Reproducibility and Security Reference

## Reproducible Builds Checklist

- Pin versions: pandoc + selected PDF engine.
- Set `SOURCE_DATE_EPOCH` in CI.
- Keep explicit input order for multi-file conversions.
- Use checked-in defaults/templates/CSS and stable resource paths.
- Set metadata deterministically (title/date/identifier strategy).
- Store outputs under deterministic paths.

## Security Checklist for Untrusted Input

- Restrict parser/extension surface where possible.
- Use `pandoc --sandbox` for IO restrictions.
- Treat filters and templates as executable trust boundaries.
- Isolate conversion runtime (container/job sandbox).
- Enforce file size/time/memory limits.
- Log conversion errors without exposing sensitive environment details.

## Safe-by-Default Guidance

- Default to no custom filters for user-submitted Markdown.
- Only allow approved templates and known resource directories.
- For server-side conversion, prefer constrained, ephemeral workers.
