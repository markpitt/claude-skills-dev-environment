# Multi-repository sweep

Use this when asked to commit across several repositories, or to report which of them have uncommitted work.

## Steps

1. **Build the list explicitly.** Do not use a glob, which picks up nested or vendored repositories:
   ```bash
   repos=(
     "$HOME/src/project-a"
     "$HOME/src/project-b"
     "$HOME/src/project-c"
   )
   ```

2. **Survey every repository before committing anything.** Print the toplevel with each reading, so a wrong root
   shows on the page:
   ```bash
   for repo in "${repos[@]}"; do
     printf '== %s\n' "$repo"
     git -C "$repo" rev-parse --show-toplevel
     git -C "$repo" branch --show-current
     git -C "$repo" status --porcelain=v1
   done
   ```
   This loop uses an array and quoted expansions, so it behaves the same under zsh and bash.

3. **Check the branch.** Commit only to the branch the user named. If a repository is on its default branch
   (`main` or `master`) and the user did not say to commit there, stop for that repository and ask. Do not switch
   branches to get round it.

4. **Apply the single-repository procedure in `SKILL.md` to each repository in turn.** Each repository gets its own
   survey, groups, checks and `git status` at the end. Exclusions named for one repository do not carry over to
   another.

5. **Exclude whole repositories when asked.** "Everything except one repo" means that repository is skipped
   entirely. Do not commit part of it. Name it in the report with the reason it was skipped.

6. **Report per repository:**
   - the absolute path and branch,
   - each commit as `hash subject`,
   - what was left uncommitted, and why,
   - which checks ran and which did not.

   A failure in one repository does not stop the others unless the user asked for all-or-nothing. Say which
   mode you used.
