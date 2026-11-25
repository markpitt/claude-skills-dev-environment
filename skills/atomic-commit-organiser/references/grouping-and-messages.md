# Grouping, messages and exclusions

## What makes a group

A group is one reason to change: a bug fix, a rename, a formatting-only pass, a dependency bump, or a new module
with its tests.

- Tests travel with the code they test.
- Mechanical changes (renames, formatting, regenerated files) get their own commit, so a reviewer can skip them
  with confidence.
- Order the commits so each one builds. A dependency added before the code that uses it.
- If a group is still large, split it by file. If two files only make sense together, keep them in one group.

## Conventional Commits

Format: `type(scope): summary`

- **Scope** names the component, not the file list: `fix(parser)`, `docs(api)`, `chore(deps)`.
- **Types** in common use: `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `ci`, `style`, `chore`.
- **Summary** in the imperative, lower case, with no full stop, about 72 characters at most.
- **Body** only when the reason is not obvious from the diff. Wrap at 72.

Good: `refactor(auth): move the token refresh into its own module`

Poor: `updates` or `WIP` or `fix stuff in several files`

## Line endings

Before staging a file that other tools may have touched:

```bash
git config --get core.autocrlf
git ls-files --eol -- path/to/file
```

An entry showing `i/crlf` in the index and `w/lf` in the worktree means an editor converted the endings. Restore
the original bytes before committing. A commit that rewrites every line hides the real change.

After staging, `git diff --cached --stat` should show a count close to the real edit. If it shows every line of
the file, stop and fix the endings first.

## Generated and binary files

- Generated output (exports, PDFs built into a source folder, lockfile churn) is excluded only when the user names
  it or the project ignores it.
- Proposing a `.gitignore` entry is a separate commit. Do not slip it into an unrelated group.
- List binary changes by path in the handover. Commit them only when they belong to a group the user asked for.

## Exclusions

- Record each exclusion with its reason in the handover.
- Match an exclusion exactly with `git status --porcelain=v1 -- <path>` before and after staging, so you can show
  it is still unstaged.
