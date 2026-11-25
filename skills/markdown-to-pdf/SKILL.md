---
name: markdown-to-pdf
description: Produces high-quality PDF documents from Markdown using reproducible, automation-friendly workflows. Use when the user asks to convert Markdown to PDF, choose a PDF engine, apply branding/styles/templates, enforce accessibility or archival standards, harden untrusted conversion pipelines, or integrate PDF generation into hooks and CI artifact publishing. Do NOT use for non-documentation tasks or generic Markdown editing without PDF output goals.
license: Apache-2.0
metadata:
  version: "1.0.0"
---

# Markdown to PDF

Generate reliable, modern Markdown-to-PDF workflows with explicit engine selection,
versioned configuration, and deterministic outputs.

## Critical

- Prefer `pandoc` as the baseline converter and show concrete commands.
- Explicitly set formats (`--from`, `--to`) and output (`--output`).
- Prefer checked-in defaults files (`--defaults`) over long ad-hoc CLI strings.
- Choose engine deliberately with `--pdf-engine` and explain trade-offs.
- For multi-file inputs, enforce explicit file order.
- For untrusted input, include security guardrails (sandboxing + strict parsing choices).
- For reproducibility, include `SOURCE_DATE_EPOCH` and deterministic metadata guidance.
- For PDF/UA or PDF/A requests, include standards-specific guidance and external validation caveat.

## Mandatory Intent Rules

For in-scope requests, never answer with generic prose only. Include the required
signals for the detected intent:

- Multi-file merge request:
  - Must mention explicit input ordering.
  - Must mention deterministic output path.
  - Must mention `--resource-path` or file-scope/resource discipline.
- Shared local + CI config request:
  - Must recommend a checked-in defaults file and mention `--defaults`.
- Engine comparison request:
  - Must compare at least 3 engines.
  - Must mention `--pdf-engine` explicitly.
- Accessibility/archival request:
  - Must mention PDF/UA or PDF/A path.
  - Must include explicit external validation caveat.
- Reproducibility request:
  - Must mention `SOURCE_DATE_EPOCH`.
  - Must mention deterministic input order and metadata/path controls.
- Missing-tool automation request:
  - Must provide graceful fallback behaviour (warn/skip or policy-driven fail).
  - Must include remediation command, including `mise` when relevant.

## When to Use

- Convert one or more Markdown files to PDF.
- Build a reusable local + CI conversion workflow.
- Compare engines like `lualatex`, `tectonic`, `weasyprint`, `typst`, or `prince`.
- Add stable branding via templates/CSS/variables.
- Improve safety for untrusted uploaded Markdown.
- Make outputs reproducible across machines/runs.
- Publish PDFs as CI artifacts.

## When NOT to Use

- User asks only for Markdown editing with no PDF output goal.
- User asks unrelated questions (math, geography, general coding).
- Task is non-document automation unrelated to document conversion.

## Response Contract

When the request is in scope, structure the answer so it is immediately actionable:

1. Provide at least one concrete command.
2. State selected engine and why.
3. Include deterministic path/config guidance.
4. Include security/reproducibility/standards guidance when relevant.
5. Keep optional alternatives short and clearly labeled.

Use this compact output structure for in-scope prompts:

- `Recommended command` (or `Recommended defaults file`)
- `Why this engine`
- `Determinism and CI`
- `Security/standards caveats` (only when relevant)

When relevant, include these literal tokens in the answer text:

- `--defaults`
- `--pdf-engine`
- `SOURCE_DATE_EPOCH`
- `--resource-path`
- `PDF/UA` or `PDF/A`
- `external validation`
- `mise`

## Core Workflow

1. Discover capabilities:
   - `pandoc --version`
   - `pandoc --list-output-formats`
   - `pandoc --list-input-formats`
2. Start with a deterministic baseline command.
3. Move repeated options to a checked-in defaults file.
4. Layer style and branding incrementally.
5. Add CI/hook automation with graceful tool-missing behaviour.
6. Add reproducibility controls for stable artifacts.

## Baseline Commands

Single file with TOC and section numbering:

```bash
pandoc --from=markdown --to=pdf README.md \
  --output docs/out/README.pdf \
  --toc --number-sections
```

Multiple files with explicit order:

```bash
pandoc --from=markdown --to=pdf \
  docs/intro.md docs/architecture.md docs/usage.md \
  --output docs/out/guide.pdf \
  --toc --number-sections
```

## Defaults-File First

Prefer a versioned defaults file in the repo.

Example `pdf.defaults.yaml`:

```yaml
from: markdown
to: pdf
pdf-engine: lualatex
table-of-contents: true
number-sections: true
output-file: docs/out/guide.pdf
resource-path:
  - .
  - docs/assets
```

Run:

```bash
pandoc --defaults pdf.defaults.yaml docs/intro.md docs/architecture.md docs/usage.md
```

## Engine Selection Guidance

Always use `--pdf-engine` explicitly when giving recommendations.

- `lualatex`: strongest general default for high-quality typography and broad Pandoc support.
- `tectonic`: strong CI ergonomics and simplified TeX dependency management.
- `weasyprint`: best when CSS-driven layout/web-print parity is required.
- `typst`: fast modern typesetting workflows and strong template ergonomics.
- `prince`: premium HTML/CSS-to-PDF engine with strong standards features.

## Styling and Branding Strategy

Apply styling in this order to reduce brittleness:

1. Metadata/variables (title, lang, margins, fonts)
2. Defaults file
3. Engine-level template/CSS/reference assets
4. Minimal custom filters only when strictly necessary

Keep style artifacts versioned and path-stable. Avoid hidden user-local dependencies.

## Accessibility and Archival Standards

For PDF/UA or PDF/A requirements:

- LaTeX path: use `lualatex` and `pdfstandard` metadata/variables where supported.
- Typst path: use Typst PDF standard options when requested.
- HTML engines (`weasyprint`, `prince`) can support standards/tagging modes, but capabilities vary by version/config.
- State clearly that external conformance validation is mandatory.

Never claim compliance from conversion alone.

## Security for Untrusted Markdown

When users upload Markdown:

- Prefer strict parse surface (for example `--from=commonmark` or constrained extensions).
- Use `--sandbox` for pandoc IO restrictions.
- Treat filters/templates as code: allow-list and review before execution.
- Run conversion in isolated runtime/container for defence in depth.
- Set resource and time limits for conversion jobs.

## Reproducibility Controls

Use all of the following when deterministic outputs matter:

- Pin converter + engine versions in CI.
- Set `SOURCE_DATE_EPOCH`.
- Use fixed input ordering.
- Use stable output paths and checked-in defaults/template assets.
- Set explicit metadata fields (`title`, `date`, identifiers when needed).

## Automation Patterns

### Git hooks (optional artifact)

If PDF generation is optional and tool is missing:

- warn clearly,
- skip artifact generation,
- continue primary workflow.

Include remediation (install command or `mise` bootstrap command).

### CI artifacts

- Generate to deterministic output path (for example `docs/out/*.pdf`).
- Upload artifact from that exact path.
- Fail only when PDF is required by policy.

## Tool-Missing Fallbacks

When `pandoc` is unavailable:

1. Recommend bootstrap via project toolchain (for this repo, `mise`).
2. Offer containerised fallback if local installation is undesirable.
3. Keep behaviour explicit (skip/warn/fail policy).

## References

Load these references for deeper, source-grounded detail:

- `references/engine-and-standards.md`
- `references/reproducibility-and-security.md`
- `references/ci-and-automation.md`
