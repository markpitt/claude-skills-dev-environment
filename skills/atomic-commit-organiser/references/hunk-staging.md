# Staging hunks

Use this when one file mixes two concerns, or a file holds another session's edit beside yours. `git add -p`
needs a terminal, so the agent builds the patch by hand and applies it to the index only.

## Steps

1. Write the full diff for the file to a directory outside the repository:
   ```bash
   tmp="$(mktemp -d)"
   git diff -U3 -- path/to/file > "$tmp/full.patch"
   ```

2. List the hunks with their line numbers:
   ```bash
   grep -n '^@@' "$tmp/full.patch"
   ```

3. Copy the header (every line before the first `@@`) and the hunks that belong to this group into
   `"$tmp/group.patch"`. Leave the other hunks out. Edit the patch with a plain text editor or `Write`, not a tool
   that converts line endings.

4. Check, then apply to the index only:
   ```bash
   git apply --cached --recount --check "$tmp/group.patch"
   git apply --cached --recount "$tmp/group.patch"
   ```
   `--recount` corrects the hunk line counts left after removing hunks.

5. Confirm the index holds only this group's hunks, and that the remainder is the other session's work:
   ```bash
   git diff --cached -- path/to/file
   git diff -- path/to/file
   ```
   The second command must show only hunks that belong to someone else. Leave them unstaged.

6. Commit with `git commit -F "$msg"`, without `--only`. The index is then what lands, not the worktree.

## Notes

- If two hunks touch adjacent lines, git may merge them into one. Use `git diff -U0` to get finer hunks, and apply
  with `git apply --cached --unidiff-zero`. Zero-context patches cannot be checked with `--recount` alone; run the
  `--check` form first.
- When every hunk in the file belongs to the group, stage the whole file with `git add -- path/to/file` instead.
- A patch that carries CRLF content must keep its carriage returns. Check with `git ls-files --eol -- <path>`
  before and after (see `grouping-and-messages.md`).
- Verify the counts with `git diff --cached --stat`. A number far larger than the intended change means the wrong
  hunks went in: `git reset -q -- <path>` clears the index entry for that file, and nothing in the worktree changes.
