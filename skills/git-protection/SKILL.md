---
name: git-protection
description: Stop force pushes and history rewrites from a machine with a global git pre-push hook, and set the matching agent rules (commit small and often, ask before pushing, fix forward). Use when asked to protect git history, block force pushes, set up or check a pre-push hook, add commit and push rules for coding agents, or when a push is refused with "non-fast-forward". Do NOT use for resolving merge conflicts, writing commit messages, organising a dirty tree into commits (use atomic-commit-organiser), scrubbing a repository for publication (use public-repo-hygiene) or configuring CI.
license: Apache-2.0
metadata:
  version: "1.1.0"
---

# Git protection

Keep published history complete. Mistakes are fixed forward with a new commit or a `git revert`,
never by rewriting what has been pushed.

## What it protects

| Layer | Stops | Bypass |
|---|---|---|
| Global `pre-push` hook (`scripts/`) | `--force`, `--force-with-lease`, `+refspec`, moved tags, from every repo on the machine | `git push --no-verify` |
| Agent rules in the user-level instructions file (below) | Agents pushing without asking, amending or rebasing pushed commits | Ignoring the instruction |
| Server-side branch protection | Anyone, from any machine, including `--no-verify` | Repo admins |

Use all three. The hook is the only one that works on the machine itself without trusting anybody;
the server-side setting is the only one that cannot be skipped from the client.

## Install the hook

```bash
bash scripts/install.sh                 # for this user: git config --global core.hooksPath ~/.config/git/hooks
bash scripts/install.sh --repo <path>   # one repository only
bash scripts/install.sh --uninstall     # unset core.hooksPath (add --repo <path> for a repo install)
bash scripts/test.sh                    # prove it against a throwaway remote; touches nothing else
```

`install.sh` is re-runnable, and installs the hooks executable, so the copies in `scripts/` do not
need to be. It refuses to replace a `core.hooksPath` that already points somewhere
else (husky, lefthook, a team hooks directory); copy `scripts/pre-push` into that directory instead.

## How the hook behaves

- Refuses any ref update where the remote's current commit is not an ancestor of what is being
  pushed, and says which ref, the two commits and what to do instead.
- Allows creating a ref and deleting one. A normal fast-forward push is untouched.
- `core.hooksPath` replaces each repository's `.git/hooks`, so `pre-push` runs the repository's own
  `pre-push` afterwards, and every other client hook is a symlink to `scripts/_chain`, which runs the
  repository's hook of the same name. Existing per-repo hooks keep working.
- If the remote commit is not in the local object store (someone else pushed), the push is refused
  as non-fast-forward. Fetch, integrate your own local work, and push again.

## Verify it is active

```bash
git config --get core.hooksPath          # the hooks directory
git push --dry-run                        # a normal push still works
```

A refused push looks like:

```text
pre-push: refusing non-fast-forward push of 'main' to 'refs/heads/main'.
  Remote is at 23ec3f658ccf, local is 6a06ae365a55, which does not contain it.
  History is never rewritten here. Fetch and merge/rebase LOCAL work, or fix forward with a new commit or revert.
```

## Agent rules to add to the user-level instructions

Put this in the user-level instructions file your agent reads at the start of every session, so it
applies to every repository on the machine (Claude Code reads one from your `~/.claude` directory):

```markdown
## Git: commit little and often, ask before pushing, never rewrite history

- Commit as you work: one small, self-contained change per commit, as soon as it is done and checked.
  Keep unrelated changes in separate commits; stage by path or hunk.
- Ask before every push. A "yes" covers that push only.
- Never rewrite published history: no force pushes (`--force`, `--force-with-lease`, `+branch`), no
  amend, rebase, `reset --hard` or filter-branch of commits that have been pushed. Fix forward.
- Never use `--no-verify` to get past a hook.
```

Optionally also deny the obvious forms in `settings.json` so they need no judgement
(`permissions.deny`, for example `Bash(git push --force:*)`). Treat this as a convenience; flag
order and `+refspec` make a pattern list incomplete, which is why the hook exists.

The rules above are the default for every agent, every session. The one exception, for a rewrite the operator
explicitly asks for, is in "History rewrites the operator asks for" below. It does not relax the rules for
anything else.

## Commit hygiene

Small, self-contained commits are what make the rules above workable: a commit grouped by intent rarely needs
rewriting, and a revert of one commit is cheap. To turn a dirty tree into those commits, use the
`atomic-commit-organiser` skill (claude-skills-dev-environment group). It stages explicit paths and hunks and never a blanket
add. This skill does not restate its procedure.

## History rewrites the operator asks for

The default does not change: agents do not rewrite pushed history, do not force-push, and do not bypass the
hook. An exception exists only when the operator explicitly asks for a rewrite in the current conversation,
naming the repository and the history to change. Then:

1. Restate the scope in one reply and wait for a yes: the refs, the commits or paths, the reason, and whether a
   push is part of the job.
2. Do the rewriting on a new branch or in a fresh clone, never on the branch other people have, and never on the
   default branch.
3. Do not push it. The push to a published branch is the operator's own command, run outside the agent. The
   pre-push hook still refuses a non-fast-forward push, and that refusal is the point at which the operator
   decides; the agent does not disable, uninstall or reconfigure the hook to get past it, and does not use
   `--no-verify`.
4. Follow `public-repo-hygiene` for the procedure: the history rewrite tooling, the scrub, the fresh-clone check
   and the re-scan. This skill does not restate them.
5. After any push the operator makes, confirm it with `git ls-remote` against the remote, rather than from the
   local reflog.

A rewrite that the operator has not asked for is a stop, whatever the state of the remote.

## Server-side protection (recommended)

The hook only covers pushes made with this machine's git configuration. In GitHub, add a branch
protection rule or ruleset on the default branch with "Block force pushes" and "Restrict deletions".
This needs repository admin rights and cannot be done from the client.

## Gotchas

- `git push --no-verify` skips every hook. Say so in the agent rules and use branch protection.
- If a tool sets its own `core.hooksPath` per repository (husky, lefthook), the repository value
  wins over the global one and this hook does not run there. Add `pre-push` to that tool's hooks.
- The hooks are copied, not linked. After editing `scripts/pre-push`, run `bash scripts/install.sh` again.
- A branch you delete on the remote keeps its history only if something else points at it; deletion
  is allowed on purpose so merged branches can be cleaned up.
