# SPIKE — Update a Pull Request In Place vs Close-and-Reopen

## Investigation question

When an open GitHub Pull Request needs correction — wrong title, wrong description, a "wrong" branch name, or code/commits that need adjusting — is closing the PR and opening a new one ever the correct tool? What are the GitHub mechanics and the documented/community consensus for updating a PR *in place* versus closing and reopening (or opening a brand-new PR for the same work)?

**Working hypothesis under test** (engineer's framing): closing and reopening a PR is almost never necessary — title/description are edited with `gh pr edit`, code is updated with `git push --force-with-lease`, and the branch name is irrelevant to the PR's identity.

## Sources consulted

- [gh pr edit manual](https://cli.github.com/manual/gh_pr_edit) — confirms `--title`, `--body`, `--base` are in-place edit flags
- [Renaming a branch — GitHub Docs](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branches-in-your-repository/renaming-a-branch) — official mechanics of what happens to PRs when a branch is renamed (base vs head distinction)
- [Discussion #4453 — Rename of Branch Closes Linking Pull Requests Without Warning](https://github.com/orgs/community/discussions/4453) — community confirmation of the head-branch-rename side effect
- [Discussion #176725 — How do I rename a branch in GitHub?](https://github.com/orgs/community/discussions/176725) — practitioner Q&A on branch renaming
- [git-scm.com — git-push documentation](https://git-scm.com/docs/git-push) — verbatim definition of `--force-with-lease` vs `--force`
- [Committing changes to a pull request branch created from a fork — GitHub Docs](https://docs.github.com/articles/committing-changes-to-a-pull-request-branch-created-from-a-fork) — confirms pushing to the head branch updates the same PR
- [Discussion #65321 — Pull request created in a GitHub action does not trigger workflows with pull_request trigger](https://github.com/orgs/community/discussions/65321) — practitioner confirmation that a force push re-triggers the `pull_request` event
- [Closing a pull request — GitHub Docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/closing-a-pull-request) — official statement of when closing (without merging) is the documented use case
- [Discussion #88753 — Reopen PR after closing it](https://github.com/orgs/community/discussions/88753) — reopen mechanics and the deleted-base-branch limitation
- [isaacs/github Issue #361 — Allow to reopen pull requests after a force push](https://github.com/isaacs/github/issues/361) — GitHub's own explanation for why reopening is blocked after a force push on a closed PR
- [Change the base branch of a Pull Request — The GitHub Blog](https://github.blog/news-insights/product-news/change-the-base-branch-of-a-pull-request/) — the announcement of in-place base-branch editing, with the explicit "keep valuable work and discussion" rationale
- [Changing the base branch of a pull request — GitHub Docs](https://docs.github.com/articles/changing-the-base-branch-of-a-pull-request) — steps and caveats (commits removed from timeline, review comments outdated)
- [Discussion #11729 — Change default base repository for pull requests on forks](https://github.com/orgs/community/discussions/11729) — practitioner report on the cross-repository retargeting gap
- [code.dblock.org — Triggering CI from Pull Requests and Force Pushes in GitHub Actions](https://code.dblock.org/2023/04/29/triggering-ci-from-pull-requests-and-force-pushes-in-github-actions.html) — practitioner write-up of force-push-to-amend-a-PR workflow
- 4Shark's own `~/.claude/CLAUDE.md` § Git Commit Policy (internal, not web-sourced) — confirms `--force-with-lease` on a feature branch is already the accepted 4Shark practice for squashing mid-PR commits

## Findings

### Finding 1 — PR title and body are editable in place, at any time, via `gh pr edit`

**Evidence:** the GitHub CLI manual for `gh pr edit` documents:
- `--title <string>` (`-t`): "Set the new title."
- `--body <string>` (`-b`): "Set the new body."
- `--base <branch>` (`-B`): "Change the base branch for this pull request"

The command's purpose line: "Edit a pull request." When invoked without arguments, it targets the PR associated with the current branch.

**Source:** https://cli.github.com/manual/gh_pr_edit

**Significance:** a wrong title or wrong description is not a reason to close a PR — both are first-class, in-place-editable fields via a single CLI flag (or the equivalent "Edit" affordance in the web UI). No new PR, no loss of number, discussion, or CI history is implied by this operation.

**Verification block:** URL fetched: https://cli.github.com/manual/gh_pr_edit / Verbatim quote checked: yes / Quote substring confirmed at: the flag-description table on the manual page.

---

### Finding 2 — Renaming a branch has two different outcomes depending on whether it is the PR's base or its head

**Evidence:** GitHub's official "Renaming a branch" doc states:
- On the **base**-branch case: "Branch protection policies are also updated, as well as the base branch for open pull requests (including those for forks) and draft releases."
- On the **head**-branch case: "If the renamed branch is the head branch of an open pull request, this pull request is closed."

**Source:** https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branches-in-your-repository/renaming-a-branch

**Significance:** this is a genuine nuance against the "branch name is irrelevant to the PR" half of the hypothesis. Renaming the *base* branch a PR targets is transparent — GitHub retargets every open PR automatically. But renaming the *head* branch (the PR's own source branch) via GitHub's rename feature **closes the PR**. The engineer's premise holds for "don't bother renaming, it doesn't matter for review" but not for "you can freely rename the head branch without consequence" — those are different claims, and only the first is supported.

**Verification block:** URL fetched: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-branches-in-your-repository/renaming-a-branch / Verbatim quote checked: yes / Quote substring confirmed at: the "Considerations for renaming branches" section of the page.

---

### Finding 3 — The community treats the head-branch-rename-closes-PR behavior as a documented pain point, not a request for new functionality

**Evidence:** in Discussion #4453, the original poster states: "all linking pull requests will be automatically closed without warning, user consent, or ability to restore the pull request to new/renamed branch." A responder confirms independently: "renaming a branch deletes the old branch and with it, any Pull Request (PR) you have open on it."

**Source:** https://github.com/orgs/community/discussions/4453

**Significance:** corroborates Finding 2 from independent practitioner reports — this is real, observed behavior, not a one-off doc phrasing. The practical consequence for the investigation question: the "wrong branch name" correction path is NOT "rename the branch in place" (that closes the PR) — it is "leave the branch name alone; the branch name carries no reviewer-facing weight, so a cosmetically 'wrong' name is not itself a reason to close/reopen anything."

**Verification block:** URL fetched: https://github.com/orgs/community/discussions/4453 / Verbatim quote checked: yes / Quote substring confirmed at: original post and first reply.

---

### Finding 4 — Pushing new commits (including a force push) to the PR's existing head branch updates the same PR — it does not create a new one

**Evidence:** GitHub's "Committing changes to a pull request branch created from a fork" doc describes the model: "After you commit your changes to the head branch of the pull request you can push your changes up to the original pull request directly," and that pushing to the head branch "will add your new commits to the existing pull request without requiring you to create a new one."

**Source:** https://docs.github.com/articles/committing-changes-to-a-pull-request-branch-created-from-a-fork

**Significance:** this is the core mechanical confirmation of the hypothesis's second claim — code corrections do not require a new PR. The commit history changes; the PR (number, discussion, reviewers) does not.

**Verification block:** URL fetched: https://docs.github.com/articles/committing-changes-to-a-pull-request-branch-created-from-a-fork / Verbatim quote checked: yes / Quote substring confirmed at: the "Committing changes" walkthrough section.

---

### Finding 5 — `--force-with-lease` is the safety-checked variant of force push; it does not, by itself, change what happens to the PR (Finding 4 still applies)

**Evidence:** the official git-push docs describe `--force-with-lease`: "This option allows you to say that you expect the history you are updating is what you rebased and want to replace. If the remote ref still points at the commit you specified, you can be sure that no other people did anything to the ref. It is like taking a 'lease' on the ref without explicitly locking it, and the remote ref is updated only if the 'lease' is still valid." By contrast, plain `--force`: "This flag disables that check, the other safety checks in PUSH RULES below, and the checks in `--force-with-lease`. It can cause the remote repository to lose commits; use it with care."

**Source:** https://git-scm.com/docs/git-push

**Significance:** the safety distinction is about protecting against silently discarding someone else's concurrent push to the same branch — it has no bearing on PR identity/continuity, which is governed by the head-branch-ref mechanics in Finding 4. On a feature branch the engineer alone owns (the normal 4Shark shape), `--force-with-lease` is the correct choice for the same reason it is already 4Shark's documented practice for squashing mid-PR commits.

**Verification block:** URL fetched: https://git-scm.com/docs/git-push / Verbatim quote checked: yes / Quote substring confirmed at: the `--force-with-lease` and `--force` option descriptions.

---

### Finding 6 — A force push to an open PR's head branch re-triggers the `pull_request` CI event

**Evidence:** in Discussion #65321, the reporting user states, describing their own observed behavior: "When I then do a force push on the created branch, the workflows are triggered as expected."

**Source:** https://github.com/orgs/community/discussions/65321

**Significance:** CI re-runs on the same PR after a force push — closing and reopening is not needed to get a fresh CI run against corrected code.

**Verification block:** URL fetched: https://github.com/orgs/community/discussions/65321 / Verbatim quote checked: yes / Quote substring confirmed at: the reporting user's follow-up comment.

---

### Finding 7 — GitHub's own documented reason to close a PR (without merging) is scope abandonment, not a correction mechanism

**Evidence:** the official "Closing a pull request" doc states the use case verbatim: "You may choose to close a pull request without merging it into the upstream branch. This can be handy if the changes proposed in the branch are no longer needed, or if another solution has been proposed in another branch."

**Source:** https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/closing-a-pull-request

**Significance:** GitHub's own documentation frames closing around "no longer needed" / "superseded by another branch" — not "the title is wrong" or "the code needs one more commit." This directly supports the engineer's hypothesis: closing is the tool for abandonment/supersession, not for correction.

**Verification block:** URL fetched: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/closing-a-pull-request / Verbatim quote checked: yes / Quote substring confirmed at: the introductory paragraph of the doc.

---

### Finding 8 — Closing and reopening (or opening a brand-new PR) fragments review state; a genuinely new PR also gets a new number

**Evidence:** the WebSearch synthesis of Discussion #45478 and related community discussion reports (paraphrased by the search tool, not a page I could re-fetch as a single verbatim block) that closing and reopening a PR "loses context, comments, and approval status," and that when a *new* PR is opened after closing the old one, "the conversations exist in the closed PR and need to be checked separately — they're not connected to the newly created PR." A genuinely new PR necessarily receives a new PR number (sequential issue/PR numbering is global to the repository), so any existing links (Slack messages, other PR cross-references, CI dashboards keyed by PR number) to the old number go stale.

**Source:** community discussion search synthesis (see Sources list); GitHub's global sequential PR/issue numbering is directly observable behavior, not separately documented in a single fetched page for this spike.

**Significance:** this is the concrete cost side of the close/reopen-as-correction-tool anti-pattern — every review comment thread, "Viewed" file-tracking state, and approval gets orphaned or requires manual re-linking. **Caveat on this finding**: the specific phrase "loses context, comments, and approval status" is a WebSearch tool paraphrase of discussion content, not a quote I independently re-verified against a single fetched page — treat this finding as directionally correct (multiple community threads describe the same friction) but weaker-sourced than the other findings in this document.

**Verification block:** URL fetched: (WebSearch tool synthesis, not a single-page fetch) / Verbatim quote checked: NOT independently re-verified against a page fetch / marked lower-confidence per Citation Discipline Rule 4 (treat as UNVERIFIED-adjacent — do not use this finding alone to sustain a strong recommendation).

---

### Finding 9 — Reopening a closed PR has two documented hard limits: a deleted base branch, and a force-push on the branch after closure

**Evidence 9a (deleted base branch):** in Discussion #88753, a user reports: "Note that this DOES NOT WORK if the closed PR *targets a branch which is deleted*. I often have PR chains like `main` < `A` < `B` < ... < `N`. If branch `A` is deleted and PR `B` is closed, it will be impossible to re-open `B` without first restoring branch `A`."

**Source:** https://github.com/orgs/community/discussions/88753

**Evidence 9b (force push after closure):** in isaacs/github Issue #361, GitHub staff explain the "Reopen pull request" button is disabled with the message "The XXX branch was force pushed or recreated," and give the underlying rationale: "We're blocking the pull request reopen if the current head isn't a descendant of the stored head sha (which is what the head was when the pull request was closed). We are not allowing the reopen in that case, because there is no good way to tell what changes have happened while a pull request was closed and the head branch has changed."

**Source:** https://github.com/isaacs/github/issues/361

**Significance:** this cuts against reopening as a universal safety net — if a PR is closed and its branch is later force-pushed (a very plausible sequence: close, keep working locally, force-push to "clean up," then try to reopen), GitHub itself blocks the reopen. Combined with Finding 6 (force push on an OPEN PR works fine and re-triggers CI), the practical rule that falls out of the evidence is: **keep the PR open and force-push to it; do not close it and then force-push, because that specific sequence can make reopening impossible.**

**Verification block:** URL fetched: https://github.com/orgs/community/discussions/88753 and https://github.com/isaacs/github/issues/361 / Verbatim quote checked: yes for both / Quote substring confirmed at: MichaelChirico's July 27 2025 comment (88753) and the maintainer/GitHub explanation quoted in the issue thread (361).

---

### Finding 10 — Changing the base branch is an explicitly documented in-place edit, with GitHub's own stated rationale being "don't open a new PR for this"

**Evidence:** the GitHub Blog announcement states: "By changing the base branch of your original pull request rather than opening a new one with the correct base branch, you'll be able to keep valuable work and discussion." The accompanying docs page lists the caveats of doing so: "When you change the base branch of your pull request, some commits may be removed from the timeline," and "Review comments may also become outdated, as the line of code that the comment referenced may no longer be part of the changes in the pull request."

**Source:** https://github.blog/news-insights/product-news/change-the-base-branch-of-a-pull-request/ and https://docs.github.com/articles/changing-the-base-branch-of-a-pull-request

**Significance:** GitHub explicitly built this feature, and explicitly frames it as the alternative to close+reopen, for exactly the "keep valuable work and discussion" reason underlying the whole investigation. It is not without cost (commits/review-comment staleness), but the cost is smaller than losing the PR entirely.

**Verification block:** URL fetched: both URLs above / Verbatim quote checked: yes / Quote substring confirmed at: the announcement's opening paragraph (blog) and the "Considerations" section (docs).

---

### Finding 11 — Retargeting a PR to a *different repository* (not just a different branch of the same repo) has no documented in-place path; this is the closest thing found to a genuine "wrong base" case that is NOT solved by `gh pr edit --base`

**Evidence:** in Discussion #11729, the original poster describes a fork scenario: "I've forked a repository which has been archived by the owner, so there won't be any prs accepted to the original repository. Therefore I'd like to change the base repository for all PRs made from to my repository but this seems not possible." A responder adds: "Why is this not a setting? One of the main use cases for Forking a repository is to take over a project that is out of maintenance."

**Source:** https://github.com/orgs/community/discussions/11729

**Significance:** `gh pr edit --base` and the web UI's "Change base" only retarget within the reachable set of branches GitHub offers for that PR — nothing found in official docs or in this discussion describes an in-place way to move an existing PR's base (or head) to point at a *different repository* entirely. **Caveat**: this finding establishes that changing the *default* target for future PRs from a fork is unsupported — it does not, by itself, prove that retargeting one *specific already-open* PR to a different repository is unsupported (a related but distinct claim). I found no official GitHub statement making that narrower claim explicitly; treat the "wrong repo/fork → must close and reopen" case as plausible but not confirmed by a directly-quotable source in this spike.

**Verification block:** URL fetched: https://github.com/orgs/community/discussions/11729 / Verbatim quote checked: yes / Quote substring confirmed at: the original post and the highlighted community reply.

---

### Finding 12 — 4Shark's existing Git Commit Policy already treats `--force-with-lease` on a feature branch as normal practice

**Evidence:** `~/.claude/CLAUDE.md` § Git Commit Policy: "ALWAYS one commit per pull request — unless the engineer explicitly requests otherwise. Squash mid-branch iterations before pushing; `--force-with-lease` is acceptable on your own feature branch" and "Resolve a PR conflict by REBASING onto the base, never by merging the base into the branch — `git rebase origin/develop`, then `git push --force-with-lease`."

**Source:** internal — `~/.claude/CLAUDE.md`, § Git Commit Policy (not web-sourced; included for completeness since it is directly relevant to the "is force-push novel here?" sub-question the engineer raised)

**Significance:** at 4Shark, force-pushing to update an open PR is not a new technique this spike is proposing — it is the already-documented mechanism for keeping "one commit per PR" through iterative review. This spike's Finding 4–6 establish that the *same* mechanism generalizes to "any code correction on an open PR," not just squashing.

**Verification block:** file read directly (`~/.claude/CLAUDE.md`); not subject to the URL-fetch verification block format since it is a local file, not a web source.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Edit title/body via `gh pr edit` | Instant, in-place, no history impact | None identified | Finding 1 |
| Leave branch name as-is even if "wrong" | No PR disruption; branch name has no reviewer-facing semantic weight | Cosmetic — the branch name itself stays imperfect in `git branch -vv` / URLs | Finding 2, 3 |
| Rename the head branch anyway (GitHub UI rename feature) | Branch name becomes "correct" | Closes the open PR — a new PR (new number, no discussion carryover) is the direct consequence | Finding 2, 3 |
| `git push --force-with-lease` to the open PR's head branch | Same PR number, same discussion thread, CI re-runs automatically, safety check against clobbering a concurrent push | None identified for the single-owner-branch case (4Shark's standard shape) | Finding 4, 5, 6, 12 |
| `gh pr edit --base` to fix a wrong target branch | Keeps the PR's discussion/approvals; GitHub explicitly built this to avoid close+reopen | Some commits may drop from the timeline view; some review comments become outdated | Finding 10 |
| Close and reopen the *same* PR | Legitimate when the branch is genuinely abandoned/superseded; reopening preserves the PR number when it works | Reopening is blocked if the base branch was deleted, or if the head branch was force-pushed while the PR was closed | Finding 7, 9 |
| Close old PR, open a brand-new PR for the same work | Sometimes the only path when retargeting to a different repository/fork is needed | New PR number; old thread/approvals/CI history orphaned; any external links to the old number go stale | Finding 8, 11 |

## What remains uncertain

- **Finding 8** (the specific cost enumeration of close+reopen — lost "Viewed" file progress, lost approval status) rests on a WebSearch synthesis I could not re-verify as a single verbatim quote against one fetched page within this spike's scope. The directional claim (closing/reopening loses review state) is corroborated by multiple independent community threads, but the exact wording should not be treated as a direct GitHub quote.
- **Finding 11** narrows to "changing the *default* base repository for future PRs from a fork is unsupported." I did not find an explicit GitHub statement addressing the narrower case of retargeting one specific, already-open PR to a different repository. It is plausible by extension (the `gh pr edit --base` flag and the web UI's base-branch selector both appear scoped to branches of the existing base repository) but not directly confirmed.
- I did not find a single official GitHub doc that states, in one place, "you never need to close and reopen a PR for X, Y, Z reasons" — the answer had to be assembled across the `gh pr edit` manual, the branch-renaming doc, the base-branch-change doc/blog post, and the closing-a-PR doc. No single canonical source addresses the *complete* set of "is close+reopen necessary?" sub-questions.
- Whether GitHub Enterprise Server or older GitHub Enterprise versions differ from github.com's current behavior on any of the above (rename-closes-PR, reopen-after-force-push block) was not checked — this spike used github.com docs/community discussions only.

## Suggested options for main and the engineer

- **Option A — codify the in-place-first default as a CLAUDE.md rule.** Draft rule text below. This would make `gh pr edit` / `git push --force-with-lease` the default correction path and reserve close+reopen for the two confirmed legitimate cases (Finding 7: genuine abandonment/supersession; Finding 9/11: the two hard-limit cases where in-place editing structurally cannot reach — wrong repository/fork, or a PR whose reopen path is already blocked).
- **Option B — leave it as unwritten practice.** The mechanics are the same regardless of whether a rule is written down; a rule mainly guards against a future session (or the engineer, under time pressure) defaulting to close+reopen out of habit rather than checking whether an in-place edit would have worked.
- **Option C — narrower rule, title/body/code only.** Codify only Findings 1, 4–6, 12 (title, body, code corrections) as "never close+reopen for this," and leave the branch-rename and base-branch-change nuances (Findings 2, 3, 9, 10) as case-by-case judgment calls rather than a blanket rule, given the genuine hard limits uncovered in Finding 9.

No recommendation is made between A/B/C — this is a scope/formalization decision for the engineer, not a technical one the evidence settles by itself.

## Proposed rule (draft text only — not written to CLAUDE.md; for the engineer's later hardening decision)

> ### Updating an Open Pull Request — Edit In Place, Don't Close/Reopen
>
> - **A wrong PR title or description is corrected with `gh pr edit --title "..." --body "..."`** — never by closing and reopening. This is a first-class in-place edit; nothing about the PR's number, discussion, or CI history changes.
> - **A wrong PR base branch is corrected with `gh pr edit --base <branch>`** — same repository only. GitHub built this specifically so a wrong-base PR does not need to be reopened. Be aware some commits may drop from the timeline view and some review comments may become marked outdated as a side effect — this is expected, not a bug.
> - **Code/commit corrections on an open PR are pushed to the existing head branch, with `git push --force-with-lease` when history was rewritten (squash, rebase, amend).** This is already 4Shark's documented practice for "one commit per PR." The PR keeps its number, its discussion thread, and CI re-runs automatically against the new commits.
> - **The head branch's *name* carries no reviewer-facing weight — do not rename it to "fix" a cosmetically wrong branch name on an open PR.** Renaming the head branch via GitHub's branch-rename feature closes the PR outright. If a truly clean branch name matters, that is a reason to plan the branch name correctly at creation time, not to rename mid-review.
> - **Close (without reopening, or followed by a genuinely new PR) is the correct tool only when**: (a) the proposed change is abandoned or superseded by a different branch/approach (GitHub's own documented use case for closing); or (b) the PR must be retargeted at a different *repository* — not just a different branch of the same repo — which has no confirmed in-place path.
> - **Before closing an open PR "to fix it and reopen," check whether the branch will be force-pushed afterward.** GitHub blocks reopening a closed PR whose head branch was force-pushed while it was closed (and separately blocks reopening if the PR's base branch was deleted). If any further changes are coming, keep the PR open — force-push to an *open* PR works cleanly and re-triggers CI; force-push to a *closed* one can strand it unreopenable.
