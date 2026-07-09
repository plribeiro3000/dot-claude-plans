# Auxiliary — git documentation excerpts (fast-forward, checkout, status porcelain)

Fetched via WebFetch during the `auto-update-dot-claude` spike.

## Source: https://git-scm.com/docs/git-pull (and the version-pinned /2.34.0 mirror)

> With `--ff-only`, resolve the merge as a fast-forward when possible. When not
> possible, refuse to merge and exit with a non-zero status.

> `git pull --ff-only` will only do "fast-forward" updates: it fails if your local
> branch has diverged from the remote branch. This is the default.

## Source: https://git-scm.com/docs/git-checkout

> Replace the specified files and/or directories with the version from the index.
> For example, if you check out a commit, edit `file.txt`, and then decide those
> changes were a mistake, `git checkout file.txt` will discard any unstaged changes
> to `file.txt`.

> This will fail if the file has a merge conflict and you haven't yet run `git add
> file.txt` (or something equivalent) to mark it as resolved. You can use `-f` to
> ignore the unmerged files instead of failing, use `--ours` or `--theirs` to replace
> them with the version from a specific side of the merge, or use `-m` to replace
> them with the original conflicted merge result.

## Source: https://git-scm.com/docs/git-status

> The <xy> is a two-letter status code XY. [...] X shows the status of the index and
> Y shows the status of the working tree [outside of a merge situation].

> [ MTARC]  M = work tree changed since index

Interpretation for this spike's design: a line ` M settings.json` (space in the X
column, `M` in the Y column) means `settings.json` is unmodified relative to what is
staged/HEAD in the index but has unstaged working-tree edits — exactly the shape the
desktop app's reformat produces, since it rewrites the file on disk without staging
anything.
