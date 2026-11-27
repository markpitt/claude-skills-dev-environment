---
name: public-repo-hygiene
description: Makes a private working repository safe to publish. Gitignores agent and local-state directories, moves internal documents to a separate private repository, triages gitleaks findings as real or false positive, rewrites history with git filter-repo, then verifies with a fresh clone and a re-scan. Use when a spike or project is about to go public, when agent state or internal notes are found in a repository's history, or when gitleaks reports findings before publication. Do NOT use to rewrite or force-push a repository without the operator's explicit request for that rewrite (git-protection governs that hand-off), to resolve merge conflicts, to write commit messages, or to set up CI scanning (use git-protection for hooks and branch protection).
license: Apache-2.0
metadata:
  version: "1.0.1"
  tags: "git, publishing, secrets, gitleaks, filter-repo, history-rewrite, gitignore, open-source, hygiene"
---

# Public repository hygiene

Publishing a repository publishes its whole history, every branch, tag and pull request ref, and any
file an agent wrote into the tree. This skill finds what must not be published, removes it from the
working tree and the history, and proves the result from a fresh clone.

## Critical boundaries

- **A history rewrite needs the operator's explicit request.** Finding a secret does not authorise
  rewriting history. Report the findings and the proposed rewrite, then wait for an explicit go-ahead
  for that rewrite and for each push it needs.
- **The push is the stop, not an obstacle.** A rewritten history cannot be pushed over the existing one
  without a forced update. The `pre-push` hook from git-protection refuses non-fast-forward pushes by
  design. Do not disable it, do not pass `--no-verify`, and do not push to a different remote to get round
  the refusal. Ask the operator how they want the new history published: a new repository, or a forced
  update they explicitly approve.
- **Rewriting does not unpublish.** Anything already public may be cached: forks, clones, pull request
  refs, GitHub's own caches and any CI logs. Treat every real credential as compromised. Rotate it, then
  rewrite. The rewrite is hygiene, not a fix.
- **Never print a secret.** Scan with `--redact`, keep reports outside the repository, and quote a finding
  only by file, line, rule and fingerprint. Do not echo the matched text into chat, a commit message or a
  note.
- **Work in a fresh clone for any rewrite.** Never rewrite the operator's working copy in place.
- **Do not install global tools.** If the repository declares a toolchain (`mise.toml`), run the tools
  through it. Otherwise say which tool is missing and stop.

## Procedure

### 1. Inventory

Record the state before any change. Each command is read-only.

```bash
git -C <repo> status --short
git -C <repo> branch -a
git -C <repo> tag --list
git -C <repo> stash list
git -C <repo> remote -v
git -C <repo> rev-list --all --count
```

Find agent and local-state paths that appear anywhere in history, not only in the current tree:

```bash
git -C <repo> log --all --name-only --format= | sort -u > <outside-repo>/paths-in-history.txt
grep -E '(^|/)\.(claude|codex|omp|pi|cursor|aider)(/|$)|(^|/)CLAUDE\.local\.md$|(^|/)\.env' <outside-repo>/paths-in-history.txt
```

Check the instrument before trusting an empty result: run the same `grep` against a path you know is
in history, and confirm it prints that path. A grep that finds nothing is only evidence of absence if
the list it searched is the full history.

### 2. Gitignore the local-state directories

Agent session state, memory, worktrees, caches and local settings are not part of the project. Add
patterns for them and remove them from the index, in a commit of their own:

```gitignore
# Local agent state (per machine, never published)
.claude/settings.local.json
.claude/projects/
.claude/worktrees/
.codex/
.omp/
.pi/
CLAUDE.local.md
```

Decide per path, not per directory. A committed project instruction file (for example a shared
`CLAUDE.md` or `AGENTS.md`) may be deliberately public. Keep it if the operator agrees; the rule is to
publish what is meant to be read, not what the agent wrote for itself.

```bash
git -C <repo> check-ignore -v <path>                 # confirms which pattern ignores it
git -C <repo> rm -r --cached -- <path>               # untrack without deleting the file
git -C <repo> add -- .gitignore
git -C <repo> commit --only -F <message-file> -- .gitignore <paths-you-untracked>
```

Stage explicit paths, never `git add .` or `git add -A`. Check `git status` before and after.

### 3. Move internal documents to a private sibling repository

Classify each document as public (stays), or internal (moves). Internal means: operational detail about
people, employers, hosts or networks, legal or medical matters, credentials or runbooks for private
systems, and planning notes that name private work.

Move by copying content, not by history:

1. Create the private repository as a separate repository (not a subdirectory of the public one), with
   visibility set to private on the host. Confirm its visibility before copying anything into it.
2. Copy the internal files into it, commit them there, and push to its private remote.
3. In the public repository, remove those files in one commit that says where they went, without naming
   their contents.
4. The public history still holds them until step 5 rewrites it.

### 4. Triage gitleaks findings

Scan the history and the working tree separately. Write reports outside the repository.

```bash
gitleaks git <repo> --redact --report-format json --report-path <outside-repo>/leaks-history.json
gitleaks dir <repo> --redact --report-format json --report-path <outside-repo>/leaks-tree.json
```

`--redact` keeps the matched value out of stdout and the report. Each finding has a rule, a file, a line,
a commit (for history) and a fingerprint. Triage each one into exactly one class:

| Class | Test | Action |
|---|---|---|
| **Real credential** | The value is live. Check with the issuing service's own tooling, not by pasting it anywhere | Rotate it. Then include it in the rewrite |
| **Real, already rotated** | The credential is revoked or expired, and the operator confirms it | Still rewrite it out; record the rotation date |
| **False positive** | A placeholder, a documented example, a test fixture with no live effect, a hash, a UUID | Add a fingerprint entry to `.gitleaksignore` with a reason comment |
| **Not a secret, but internal** | Private data that is not a key (a name, an address) | Not a gitleaks matter. Handle it under step 3 or the rewrite's path list |

`.gitleaksignore` takes one fingerprint per line. Each entry needs a comment with the reason and the
reviewer's name or role, never the secret:

```text
# Placeholder in the setup docs, not a live key. Reviewed by the operator.
<fingerprint-from-report>
```

Never add a fingerprint for a real credential, even to quiet a re-scan. Rotate it and rewrite instead.

### 5. Rewrite history (only on the operator's explicit request)

Use a fresh clone, so filter-repo's safety check passes naturally:

```bash
git clone --no-local <repo> <outside-repo>/rewrite
cd <outside-repo>/rewrite
git filter-repo --invert-paths --path <internal-path> --path <agent-path> --path-glob '*.env'
```

For literal secret values that must be replaced rather than removed, write the expressions to a file
outside any repository. That file holds the secrets in plain text, so delete it after the rewrite:

```text
literal:<value-from-triage>==>[REDACTED]
regex:<pattern>==>[REDACTED]
```

```bash
git filter-repo --replace-text <outside-repo>/expressions.txt
```

Rules for this step:

- `git filter-repo` removes the `origin` remote on purpose. Re-add it with the target URL the operator
  chose, and do not reuse the old remote name without checking where it points.
- Do not pass `--force` to skip filter-repo's fresh-clone check. The check is the protection. If it
  refuses, re-clone.
- Run `git filter-repo` through the project's toolchain (`mise exec -- git filter-repo ...`) where the
  project declares one. Where it does not, say the tool is missing and stop. Do not install it globally.
- Publishing the result is a separate request. Give the operator the exact push command and the target,
  and wait for the go-ahead. It may be refused by `pre-push`. That refusal is the answer; report it.

Local clean-up after a successful rewrite (`git reflog expire --expire=now --all` and
`git gc --prune=now`) deletes the only copy of the old history. Ask before running them, and do not run
them in the operator's working copy.

### 6. Verify from a fresh clone

Do not verify the rewritten copy with the copy you rewrote. Clone the published result into an empty
directory and check that:

```bash
git clone --no-local <published-url> <outside-repo>/verify
git -C <outside-repo>/verify log --all --name-only --format= | sort -u > <outside-repo>/paths-after.txt
grep -E '<internal-path-pattern>' <outside-repo>/paths-after.txt; echo "grep exit $?"
gitleaks git <outside-repo>/verify --redact --report-format json --report-path <outside-repo>/leaks-after.json
gitleaks dir <outside-repo>/verify --redact --report-format json --report-path <outside-repo>/leaks-after-tree.json
```

Report each result with its exit status. `grep` exits 1 when nothing matches, and that is the wanted
result here, but only if the same pattern found the path in step 1. Compare the reports' counts with
the triage: every remaining finding must be one that was reviewed and ignored with a reason.

Also check the refs the fresh clone received, because history rewrites often miss them:

```bash
git -C <outside-repo>/verify for-each-ref --format='%(refname)'
git -C <outside-repo>/verify stash list
```

Pull request refs (`refs/pull/*`) and forks are not in a fresh clone. Check them on the host and tell the
operator which exist. They may still hold the old objects, and the operator decides whether to close,
recreate or delete them.

### 7. Hand off to the operator

Report, in this order:

1. What was in the history and the tree, by class and count (not by value).
2. What was rotated, and what the operator must still rotate.
3. What was moved to the private repository, and its visibility.
4. The rewrite that was made, the verification result, and the push that is waiting for approval.
5. What cannot be undone: forks, caches, pull request refs and anyone's existing clone.

## Gotchas

- `git log --all` covers every ref; `git log` alone does not. Use `--all` for the inventory and the
  verification.
- Gitignore does not untrack a file already in history. Only a rewrite removes it from history.
- `.gitleaksignore` entries are per fingerprint, so a renamed file or a moved line can produce a new
  fingerprint. Re-triage after any rewrite.
- A clean scan proves the rules you ran found nothing. It does not prove the repository is free of
  secrets. Say which rules and which paths the scan covered.
