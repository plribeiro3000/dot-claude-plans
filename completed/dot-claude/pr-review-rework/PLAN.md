# PLAN — PR Review Rework

> Derived from `PLAN-SPIKE.md` and `SPIKE.md` in this same directory.

## Objective

Rework the review tooling in the dot-claude configuration repository so that all PR review and triage operations work natively inside GitHub. The three locked changes are: (1) `@agent-code-reviewer` renamed to `@agent-pr-reviewer` with scope limited to PR-only review absorbing security — the agent applies the Mother Rule to review and returns structured findings; (2) `@agent-security-reviewer` deleted entirely — security is absorbed into `@agent-pr-reviewer`; (3) `/triage-pr` renamed to `/pr-triage` with scope reduced to identifying false positives in open review threads and marking them resolved on GitHub. All non-FP thread resolution moves to the GitHub UI. There is no local HTML output from either tool going forward.

## Scope

### In scope

- Rename `agents/code-reviewer.md` → `agents/pr-reviewer.md` via `git mv`, then edit the renamed file with the new pr-reviewer spec (absorbs security-reviewer responsibilities, adds Mother Rule applied to review, etc.)
- Delete `agents/security-reviewer.md`
- Rename `commands/triage-pr.md` → `commands/pr-triage.md` via `git mv`, then edit the renamed file with the new pr-triage spec (FP-only scope, no HTML, always-post-comment-before-resolve)
- Rename `scripts/triage-pr.sh` → `scripts/pr-triage.sh` via `git mv`; script body may need internal flag/help-text updates after rename; core fetch/JSON-emit logic kept intact
- Delete `templates/html/code-review-board.html` and remove its catalog row from `CLAUDE.md`
- Update all cross-references in `CLAUDE.md`, `README.md`, `docs/SUBAGENT-CONTRACT.md`, `agents/orchestrator.md`, `commands/test.md`, `CHANGELOG.md` — 17+ call sites confirmed by grep
- Update `settings.json:267–268` — two hardcoded `triage-pr.sh` allow-list entries updated to `pr-triage.sh`

### Out of scope

- No `/pr-check` skill
- No pending-review gate
- No auto-resolve on next push
- No dogfooding/validation harness beyond organic post-merge validation
- No transition mechanism for in-flight triage cycles (engineer confirmed: none exist at migration time)

## Chosen approach

**Direction:** Single PR — all 17+ file changes in one commit; atomic cutover; no parallel deprecated commands.

**Rationale (from engineer):** Atomic change avoids the intermediate broken-reference state that would occur between sequential PRs. One commit per PR is the 4Shark convention (`CLAUDE.md:113`). No in-flight triage cycles exist at migration time, so a clean cutover is safe.

**Source patterns referenced:**
- `CLAUDE.md:113` — "ALWAYS one commit per pull request" — the single-PR shape is the 4Shark convention
- `SPIKE.md:Finding 4` — triage Phases 5–6 already operate natively via GraphQL; only Phase 1 (HTML classification) is local — the new `/pr-triage` drops Phase 1 HTML and keeps the FP-identify-and-resolve flow

## Execution phases

### Phase 1: Rename and edit specs

**Objective:** Rename all three files via `git mv` and then edit the renamed files with the new content. The `git mv` step preserves history under the new path; the content edit then changes what each file says.

**Components:**

- `git mv agents/code-reviewer.md agents/pr-reviewer.md` — then edit `agents/pr-reviewer.md` with the full new PR-only review agent spec. Includes: reading `git diff` against the base branch; for each changed file, reading 2–3 sibling files and identifying the established pattern (Mother Rule procedure); security checks absorbed from `agents/security-reviewer.md`; structured findings payload for main to post via `gh api`; no HTML output. Model: `opus`. Output: inline comments posted to the PR + a top-level summary comment (severity counts + overall assessment) via a separate `gh pr comment` call.
- `git mv commands/triage-pr.md commands/pr-triage.md` — then edit `commands/pr-triage.md` with the reduced spec. Fetch unresolved review threads (via `scripts/pr-triage.sh` — the renamed script from below); classify FPs with reasoning; return thread IDs + explanations to main; main executes the two GraphQL mutations per FP: `addPullRequestReviewThreadReply` (reasoning comment) then `resolveReviewThread`. Always post the reasoning comment before resolving — audit trail is complete.
- `git mv scripts/triage-pr.sh scripts/pr-triage.sh` — rename with history preserved; then update any internal flag/help-text references to `triage-pr` within the script; core fetch/JSON-emit logic stays intact.

**Dependencies:** None — Phase 1 is unblocked.

**Success criteria:**
- [ ] `agents/pr-reviewer.md` exists and covers: diff reading, sibling-read step (Mother Rule applied to review), security checklist (absorbed from security-reviewer), structured findings payload shape, no HTML output directive, model set to `opus`
- [ ] `commands/pr-triage.md` exists and covers: FP-only scope, no FIX/ASK/implement phases, always-post-comment-before-resolve behavior, GraphQL mutation shapes carried from `commands/triage-pr.md:193–211`
- [ ] `scripts/pr-triage.sh` exists; `scripts/triage-pr.sh` does not exist
- [ ] `git log --follow agents/pr-reviewer.md` shows pre-rename history
- [ ] `git log --follow commands/pr-triage.md` shows pre-rename history
- [ ] `git log --follow scripts/pr-triage.sh` shows pre-rename history

---

### Phase 2: Delete old spec

**Objective:** Remove `agents/security-reviewer.md` — the one file that has no rename target. The files renamed in Phase 1 (`agents/code-reviewer.md`, `commands/triage-pr.md`, `scripts/triage-pr.sh`) no longer exist after the `git mv` operations; there is nothing further to delete for them.

**Components:**

- `git rm agents/security-reviewer.md` — deletion; no rename (plain `git rm`); content is absorbed into `agents/pr-reviewer.md`

**Dependencies:** Phase 1 complete.

**Success criteria:**
- [ ] `agents/security-reviewer.md` does not exist
- [ ] `agents/code-reviewer.md` does not exist (renamed in Phase 1)
- [ ] `commands/triage-pr.md` does not exist (renamed in Phase 1)

---

### Phase 3: Update cross-references

**Objective:** Update every file that references the old names. Depends on Phase 2 (old files gone) so no reference points to a live file by accident.

**Files and line locations to update (from PLAN-SPIKE.md § Inputs):**

| File | Lines | Change |
|------|-------|--------|
| `CLAUDE.md` | 320, 347, 502, 581, 698–699, 816–821, 922–923, 947–948 | Replace `@agent-code-reviewer`, `@agent-security-reviewer`, `/triage-pr`, `code-review-board.html` catalog row with `@agent-pr-reviewer`, `/pr-triage`; remove deleted catalog row |
| `README.md` | 130, 142, 192–193, 218–219, 308–309, 334, 343, 571–572 | Replace old agent and command names with new names |
| `docs/SUBAGENT-CONTRACT.md` | 44, 146, Exceptions table | Replace `code-reviewer` and `security-reviewer` with `pr-reviewer` in verifier exclusion list and Exceptions table |
| `agents/orchestrator.md` | 46–47, 68–69, 169–170, 187–188 | Update phase tables for Standard and DDD workflows |
| `commands/test.md` | 80 | Update post-test suggestion reference |
| `settings.json` | 267–268 | Update two hardcoded allow-list entries: `triage-pr.sh` → `pr-triage.sh` (both the `$HOME/.claude/scripts/` and `~/.claude/scripts/` variants) |
| `CHANGELOG.md` | Under `## [Unreleased]` | Add entry for the rework |

**Dependencies:** Phase 2 complete.

**Success criteria:**
- [ ] `grep -r "code-reviewer" ~/.claude/` (scoped to the dot-claude working copy) returns zero results outside of git history
- [ ] `grep -r "security-reviewer" ~/.claude/` returns zero results outside of git history
- [ ] `grep -r "triage-pr" ~/.claude/` returns zero results outside of git history (including `settings.json:267–268`)
- [ ] `CHANGELOG.md` has a new entry under `## [Unreleased]`

---

### Phase 4: Delete template

**Objective:** Remove `templates/html/code-review-board.html` and remove its catalog row from `CLAUDE.md`. The grep confirmed no consumer other than the three deleted/updated files (`PLAN-SPIKE.md § Decision 3`).

**Components:**

- `git rm templates/html/code-review-board.html`
- Remove the `code-review-board.html` catalog row from `CLAUDE.md:502` (the HTML template catalog table in the Output Policy section) — this overlaps with the Phase 3 CLAUDE.md edits and should be done in the same edit pass

**Dependencies:** Phase 3 (CLAUDE.md is already being edited; the catalog row removal is part of that edit).

**Note:** Phase 4 is not a separate pass — the catalog row removal is folded into the Phase 3 CLAUDE.md edit. The `git rm` of the template file is the only distinct action in Phase 4.

**Success criteria:**
- [ ] `templates/html/code-review-board.html` does not exist
- [ ] `grep "code-review-board" CLAUDE.md` returns zero results

---

### Phase 5: Validation and commit

**Objective:** Confirm no missed references, then create one commit and open the PR.

**Validation steps (organic — no formal pre-merge harness):**

1. Run `grep -r "code-reviewer\|security-reviewer\|triage-pr"` across the dot-claude working copy — zero results expected
2. Verify `settings.json:267–268` reflects `pr-triage.sh` in both allow-list entries
3. Confirm `agents/pr-reviewer.md`, `commands/pr-triage.md`, `scripts/pr-triage.sh` all exist
4. Confirm `agents/code-reviewer.md`, `agents/security-reviewer.md`, `commands/triage-pr.md`, `scripts/triage-pr.sh`, `templates/html/code-review-board.html` do not exist

**Commit and PR:**

- One commit per the 4Shark convention (`CLAUDE.md:113`)
- PR title = commit message (Angular format: `refactor(agents): rename and rework PR review tooling`)
- PR body = `CHANGELOG.md` entry content

**Dependencies:** Phases 1–4 complete.

**Success criteria:**
- [ ] Grep passes — zero results for all old names
- [ ] One commit on the feature branch
- [ ] PR opened against `develop`

---

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Migration shape | Single PR — all 17+ changes in one commit | Atomic; avoids broken intermediate cross-reference state; aligns with `CLAUDE.md:113` "one commit per PR" convention |
| Pattern injection for `@agent-pr-reviewer` | Option C: extend hook to inject sibling excerpts at spawn | Structural guarantee at spawn time — the agent cannot forget the sibling-read step; context is present regardless of agent-spec instruction |
| `templates/html/code-review-board.html` | Delete | Grep confirmed zero consumers other than files being deleted; dead code made visible by this change; catalog row in `CLAUDE.md:502` removed alongside |
| File provenance | `git mv` for all three renames (`agents/code-reviewer.md` → `agents/pr-reviewer.md`, `commands/triage-pr.md` → `commands/pr-triage.md`, `scripts/triage-pr.sh` → `scripts/pr-triage.sh`); plain `git rm` for `agents/security-reviewer.md` (pure deletion, no rename) | Option A applied uniformly per engineer's communicated choice on Decision 4 |
| Rate limit handling | Single POST — no cap; all findings in one `gh api` call | Risk is theoretical for 4Shark PR volumes; SPIKE.md:Finding 7 confirms one POST with N inline comments is one API call; monitor on first large PRs |
| In-flight PRs | No transition mechanism — clean cutover | Engineer confirmed no in-flight triage cycles exist at migration time |
| Validation plan | Option C: organic — no formal pre-merge validation | Fastest path; grep sweep covers the primary failure mode (missed cross-ref); first real PR after merge is the live test |
| Model for `@agent-pr-reviewer` | `opus` | Matches the old security-reviewer model; the merged agent covers security where errors are more expensive than model cost difference |
| `/pr-triage` FP comment behavior | Always post reasoning comment before resolving | Complete audit trail; 2 GraphQL calls per FP: `addPullRequestReviewThreadReply` then `resolveReviewThread` |
| `@agent-pr-reviewer` output shape | Inline comments + top-level summary comment | Summary (severity counts + overall assessment) via separate `gh pr comment`; two API calls per review |
| Script rename | YES — `scripts/triage-pr.sh` → `scripts/pr-triage.sh` via `git mv` | Naming consistency with the renamed command |
| `settings.json` allow-list | Update lines 267–268 — both `triage-pr.sh` entries updated to `pr-triage.sh` | Engineer confirmed hardcoded at `settings.json:267–268`; failing to update breaks auto-approve for the script |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Missed cross-reference after rename | A session calls `@agent-code-reviewer` or `@agent-security-reviewer` by old name and gets "agent not found" | Run `grep -r "code-reviewer\|security-reviewer\|triage-pr"` across the working copy as the final check in Phase 5 before committing |
| `suggestion` syntax with nested backticks in Ruby (SPIKE.md open question 2) | Suggestion fences containing Ruby code blocks with embedded backticks may not render correctly on GitHub | Use tilde-fence escaping (`~~~suggestion`) in the `pr-reviewer` spec; validated on a real PR organically post-merge |
| Rate limit on PRs with 50+ findings (SPIKE.md open question 4) | GitHub may count each inline comment in the array separately against the 80 req/min limit | Start with single POST (chosen); monitor first few large PRs; switch to chunked POST if limit is hit in practice |
| `@agent-pr-reviewer` skips sibling reads under context pressure | Pattern comparison silently degraded — FPs or missed pattern deviations | Decision 2 chose Option C (hook injects sibling excerpts at spawn); context is structurally present, not a prompt instruction that can be skipped |
| `scripts/triage-pr.sh` rename breaks auto-approve in `settings.json` | The allow-list entries at `settings.json:267–268` reference `triage-pr.sh`; if not updated, the renamed script does not auto-approve | Engineer confirmed hardcoded; Phase 3 explicitly updates both lines as part of the cross-reference sweep |
| Transition confusion between old and new command names | An engineer in an active session gets the old behavior because their session has the old `CLAUDE.md` in context | `scripts/read-context.sh` re-reads context at SessionStart; a new session after merge gets the updated names automatically |

---

## Assumptions

- No in-flight triage cycles exist at migration time — engineer confirmed "não vamos ter, não é problema" (PLAN-SPIKE.md § Decision 6)
- `grep -r "code-review-board"` returned exactly 4 hits — all in files being deleted or updated; no other consumer of the HTML template exists (PLAN-SPIKE.md § Decision 3, Option A evidence)
- `settings.json:267–268` contains two hardcoded `triage-pr.sh` allow-list entries — engineer confirmed (tactical choice 5)
- A single `POST /repos/.../pulls/{pr}/reviews` with N inline comments counts as one API call for rate-limit purposes — confirmed by SPIKE.md:Finding 7; single POST shape is safe for typical 4Shark PR volumes

---

> **Authoring:** written by `@agent-plan-composer` from a validated `PLAN-SPIKE.md` plus the engineer's communicated choice. No new options, no new technical decisions, no new assumptions may be introduced at the composer stage — every claim traces to the draft or the engineer's choice. The `output-verifier` runs scope-containment, citation-integrity, contract-compliance, template-compliance, and reference-resolution checks after the write.
