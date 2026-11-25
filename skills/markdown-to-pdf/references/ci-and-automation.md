# CI and Automation Reference

## Deterministic CI Pattern

1. Install/pin toolchain.
2. Run conversion with checked-in defaults.
3. Write to deterministic output path.
4. Publish artifacts from that exact path.

Example pattern:

```bash
export SOURCE_DATE_EPOCH=1700000000
pandoc --defaults pdf.defaults.yaml docs/intro.md docs/architecture.md docs/usage.md
```

## Hook Behavior Policy

For optional PDF artifacts:

- If converter exists: generate PDF.
- If converter missing: warn and skip.
- Include remediation command.

For mandatory PDF artifacts:

- fail with actionable installation guidance.

## Tool Bootstrap Guidance

- Prefer project runtime manager (`mise`) when available.
- Alternative: containerized `pandoc` for consistent automation environments.

## Operational Notes

- Keep log output concise and actionable.
- Separate content-validation failures from toolchain failures.
- Avoid silent fallbacks that hide missing output artifacts.
