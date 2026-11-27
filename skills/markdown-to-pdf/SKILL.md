---
name: markdown-to-pdf
description: Converts Markdown to PDF with Pandoc in a way that can be repeated locally and in CI - explicit formats, a checked-in defaults file, a deliberately chosen PDF engine (lualatex, tectonic, weasyprint, typst or prince), stable styling, reproducible output, PDF/UA or PDF/A where needed, and guardrails for untrusted input. Use when asked to turn Markdown into a PDF, merge several Markdown files into one PDF, choose or compare PDF engines, brand or template PDF output, make PDF builds reproducible, convert user-uploaded Markdown safely, or generate PDFs from a git hook or as CI artifacts. Do NOT use for Markdown editing or tidying with no PDF output (use markdown-formatter), or for producing other formats such as DOCX or HTML on their own.
license: Apache-2.0
metadata:
  version: "2.0.0"
---

# Markdown to PDF

Pandoc is the converter. Most PDF trouble comes from things left implicit: which engine ran, which
order the files went in, where images were looked up, what date was stamped in. Make each of them
explicit and the same build gives the same PDF on every machine.

Answer with a command or a defaults file that works, the engine chosen and why, and whatever the
request needs on determinism, security or standards. Keep alternatives short.

## Start here

Check what is installed: `pandoc --version`, and `pandoc --list-output-formats` if in doubt. Then:

```bash
pandoc --from=markdown --to=pdf README.md \
  --pdf-engine=lualatex \
  --output docs/out/README.pdf \
  --toc --number-sections
```

For several files, list them in the order they should appear. A shell glob sorts by name in the
current locale, which is rarely the reading order and can differ between machines:

```bash
pandoc --from=markdown --to=pdf --pdf-engine=lualatex \
  docs/intro.md docs/architecture.md docs/usage.md \
  --resource-path=.:docs/assets \
  --output docs/out/guide.pdf --toc --number-sections
```

`--resource-path` says where images are found. Without it, Pandoc looks relative to the working
directory, so a build that works from the repository root breaks from anywhere else.

## Put the options in a defaults file

Once a command is used by more than one person or by CI, move its options into a checked-in file,
so local and CI builds cannot drift apart:

```yaml
# pdf.defaults.yaml
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

```bash
pandoc --defaults pdf.defaults.yaml docs/intro.md docs/architecture.md docs/usage.md
```

## Choosing an engine

Always name it with `--pdf-engine`. The default depends on what is installed, so leaving it out
gives different PDFs on different machines.

| Engine | Choose it when | Trade-off |
|---|---|---|
| `lualatex` | You want the best general typography and the widest Pandoc support | A large TeX install, and slower |
| `tectonic` | You want LaTeX output in CI without managing a TeX distribution | Downloads packages on first run, so cache them |
| `weasyprint` | The layout is driven by CSS, or must match a web page | Weaker on maths and some LaTeX-only features |
| `typst` | You want fast builds and simple templates | A younger ecosystem, and templates are Typst, not LaTeX |
| `prince` | You need the most complete CSS paged-media support, or tagged PDFs from HTML | Commercial: it needs a licence for commercial use |

`pdflatex` still works but has no system fonts and limited Unicode. Prefer `lualatex`.

## Styling without brittleness

Apply style in this order, and stop at the first level that does the job: metadata and variables
(title, language, margins, fonts), then the defaults file, then a template, CSS or reference
document for the engine, and only then a Lua filter. Keep every style file in the repository at a
fixed path. A template that lives in someone's home folder is a build that only works for them.

## Accessible and archival PDFs

For PDF/UA (accessible) or PDF/A (archival), use `lualatex` with the `pdfstandard` variable, or
Typst's PDF standard option. weasyprint and prince have their own modes, and what they support
varies by version.

Conversion alone never proves conformance. Say so, and have the output checked by an external
validator such as veraPDF before anyone relies on it.

## Untrusted Markdown

Markdown from users can read local files through image paths and includes, and filters and
templates are code.

- Run Pandoc with `--sandbox`, which stops it reading or writing files beyond its inputs and output.
- Narrow the parser: `--from=commonmark`, or Markdown with only the extensions you need.
- Allow only reviewed filters and templates, never ones named in the input.
- Convert inside a container or other isolated runtime, with time and memory limits.

## Reproducible output

Two builds of the same source differ when the date, the file order, the tool versions or the paths
differ. To pin them:

- set `SOURCE_DATE_EPOCH`, for example to the last commit's timestamp, so embedded dates do not
  change;
- list the input files in a fixed order;
- pin Pandoc and the engine versions in CI;
- keep output paths, defaults and templates fixed and in the repository;
- set `title`, `date` and any identifiers in metadata rather than letting them default.

## Hooks and CI

A git hook that makes an optional PDF should warn and skip when Pandoc is missing, not block the
commit, and print the command that installs it (for example `mise use pandoc` where the project
uses mise, or the system package). Fail only where policy says the PDF is required.

In CI, write to a fixed path such as `docs/out/` and upload the artifact from exactly that path. If
installing Pandoc locally is unwelcome, the `pandoc/latex` container image is a fallback.

## References

| File | Covers |
|---|---|
| `references/engine-and-standards.md` | Engines in depth, PDF/UA and PDF/A options |
| `references/reproducibility-and-security.md` | Determinism controls, sandboxing, untrusted input |
| `references/ci-and-automation.md` | Hooks, CI jobs, artifacts and missing-tool handling |
