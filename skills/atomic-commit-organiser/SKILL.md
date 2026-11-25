---
name: atomic-commit-organiser
description: Turn a dirty working tree, or several repositories at once, into commits grouped by intent, staging explicit paths and hunks only and never a blanket add. Use when asked to commit everything in logical pieces, split one large change into atomic commits, tidy a messy index, sweep several repositories for uncommitted work, or leave named files or repositories out of a commit. Do NOT use for blocking force pushes or setting push rules (use git-protection), for drafting a message for one finished change, or for resolving merge conflicts.
license: Apache-2.0
metadata:
  version: "1.0.0"
  tags: "git, commits, atomic-commits, staging, conventional-commits, multi-repo, workflow"
---

# Atomic commit organiser

**Goal:** every commit holds one intent, passes the cheapest check that covers it, and can be reverted on its
own. When the work is done the tree is clean, or holds only what the user excluded.

This skill commits. It does not push, does not amend a commit it did not just make, and does not rewrite
history. Push rules are in the git-protection skill.

## Critical

- Stage explicit paths only. Never `git add .`, `git add -A`, `git add -u` or `git commit -a`.
- Honour the user's exclusions exactly. A file, folder or repository the user named stays out of every commit.
  Something the user did not name is never excluded silently: list it in the handover.
- Where another session may write the same tree, commit with the index (`git commit -F`) after staging, or with
  `git commit --only -F <msgfile> -- <paths>` for whole files. Stage hunks, not files, where a file mixes two
  concerns or holds a peer's edit (see `references/hunk-staging.md`).
- Run `git status` before the first staging and after the last commit. Put both results in the handover.
- If the index already holds staged work when you start, it belongs to someone. Do not commit it under your
  messages. Report it and stop.

## Situation to reference

| Situation | Load |
|---|---|
| One file mixes two concerns, or holds another session's edit beside yours | `references/hunk-staging.md` |
| Several repositories, or a report per repository | `references/multi-repo-sweep.md` |
| Choosing groups, writing messages, handling CRLF, generated files and exclusions | `references/grouping-and-messages.md` |

## Procedure

1. **Survey.** Run each command and read its output in full:
   ```bash
   git rev-parse --show-toplevel
   git status --porcelain=v1
   git diff --stat
   git diff --cached --stat
   git ls-files --others --exclude-standard
   ```
   Print the toplevel with every reading. A wrong root gives accurate figures for the wrong repository.

2. **Record exclusions.** List what the user named (paths, folders, repositories) and any path that looks
   generated (build output, exports, PDFs written into a source folder). Generated files stay out only if the
   user named them or the project ignores them.

3. **Group by intent.** Write the plan as one line per group: `group | paths | message`. Apply the rules in
   `references/grouping-and-messages.md`.

4. **Optional safety tag** before a large change. Keep it local:
   ```bash
   git tag "pre-atomic-$(date +%Y%m%d-%H%M%S)"
   ```
   Never push it. Remove it with `git tag -d <name>` once the user has accepted the commits.

5. **For each group, in dependency order:**
   1. Stage the group's paths: `git add -- <path> [<path> ...]`. For a mixed file, stage only its hunks by
      following `references/hunk-staging.md`.
   2. Confirm the staged set is the plan, and read the whole cached diff:
      ```bash
      git diff --cached --name-status
      git diff --cached --stat
      git diff --cached
      ```
      Stop if the cached diff holds anything the group does not.
   3. Run the cheapest check covering the component. Where `mise.toml` exists, use `mise run <task>`; otherwise
      the project's documented quick test. A check that cannot see only the staged content is reported as "not
      run against the commit", not as passed.
   4. Write the message to a file outside the tree and commit:
      ```bash
      msg="$(mktemp)"
      cat > "$msg" <<'EOF'
      fix(parser): reject empty tokens before the lexer runs
      EOF
      git commit -F "$msg"
      ```
      In a shared tree where whole files are safe to take, use
      `git commit --only -F "$msg" -- <paths>`. `--only` takes the worktree content of each path, so never use it on
      a file whose other hunks belong to someone else. A path that is new and untracked must first be registered
      with `git add -N -- <path>` (intent-to-add), or git rejects it as unknown.
   5. Check the result: `git show --stat HEAD`.

6. **Close out.** Run `git status --porcelain=v1` and `git log --oneline -n <count>`. Anything still listed must
   be an exclusion or be named in the handover.

7. **Handover.** Give a table of `hash | subject | files`, the final status, each exclusion with its reason, and
   every check that did not run. Give the absolute repository path, not a relative one.

## Gotchas

- `git add -p` and `git rebase -i` need a terminal. Use the patch route in `references/hunk-staging.md`.
- A commit that only passes because an unstaged hunk was present is a broken commit. Re-check the cached tree.
- `git commit --amend` is out of scope here: the rule is to correct forward with a new commit.
