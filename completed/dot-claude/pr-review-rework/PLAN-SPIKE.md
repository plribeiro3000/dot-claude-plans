# PLAN-SPIKE — PR Review Rework

> Reference: `SPIKE.md` in this same directory.

## Objective

Rework the review tooling in the dot-claude configuration repository so that all PR review and triage operations work natively inside GitHub. The three locked decisions are: (1) `@agent-code-reviewer` renamed to `@agent-pr-reviewer` with scope limited to PR-only review including security — the agent consults project pattern context (Mother Rule applied to review) and returns structured findings; (2) `@agent-security-reviewer` deleted entirely — security is absorbed into `@agent-pr-reviewer`; (3) `/triage-pr` renamed to `/pr-triage` with scope reduced to identifying false positives in open review threads and marking them resolved on GitHub. All non-FP thread resolution happens in the GitHub UI. There is no local HTML output from either tool going forward.

## Scope

### In scope
- Create `agents/pr-reviewer.md` — new agent spec (absorbs code-reviewer + security-reviewer, PR-only scope, Mother Rule applied to review, findings returned to main)
- Delete `agents/code-reviewer.md` and `agents/security-reviewer.md`
- Create `commands/pr-triage.md` — renamed and reduced triage spec (FP-only, no HTML, no FIX implementation, no ASK drafting)
- Delete `commands/triage-pr.md`
- Rename or replace `scripts/triage-pr.sh` (the script logic is reusable; only the name and possibly minor flags change)
- Decide what to do with `templates/html/code-review-board.html`
- Update all cross-references in `CLAUDE.md`, `README.md`, `docs/SUBAGENT-CONTRACT.md`, `agents/orchestrator.md`, `commands/test.md`, `CHANGELOG.md` — 17 call sites confirmed by grep

### Out of scope (open question)
- No `/pr-check` skill — engineer's call, not implemented
- No pending-review gate (open question 1 from SPIKE.md) — engineer chose to skip
- Auto-resolve on next push (open question 3 from SPIKE.md) — not in scope
- Dogfooding/validation harness beyond manual testing

---

## Inputs — state of the world

### Files to be modified or deleted

| File | Action | References found |
|------|--------|------------------|
| `agents/code-reviewer.md` | Delete (or git-mv to pr-reviewer.md) | 17 cross-refs across 6 files |
| `agents/security-reviewer.md` | Delete entirely | 12 cross-refs across 6 files |
| `commands/triage-pr.md` | Delete (or git-mv to pr-triage.md) | 8 cross-refs across 5 files |
| `scripts/triage-pr.sh` | Keep logic; rename or symlink | Referenced by `commands/triage-pr.md` only |
| `templates/html/code-review-board.html` | TBD — see Decision Point 3 | Referenced by 4 files (code-reviewer, security-reviewer, triage-pr, CLAUDE.md) |
| `CLAUDE.md` | Update all refs — 9 line-matches | Lines 320, 347, 502, 581, 698–699, 816–821, 922–923, 947–948 |
| `README.md` | Update all refs — 8 line-matches | Lines 130, 142, 192–193, 218–219, 308–309, 334, 343, 571–572 |
| `docs/SUBAGENT-CONTRACT.md` | Update refs — 3 line-matches | Lines 44, 146, and the Exceptions table |
| `agents/orchestrator.md` | Update phase refs — 8 line-matches | Lines 46–47, 68–69, 169–170, 187–188 |
| `commands/test.md` | Update ref — 1 line-match | Line 80 |
| `CHANGELOG.md` | Add entry for the rework | Lines 45, 171, 175 |

### Current flow confirmed from codebase

`agents/code-reviewer.md:84–91`:
```markdown
Run read-only Bash:
- `git diff develop --stat` — overview of changes
- `git diff develop` — detailed changes
- `git diff develop --name-only` — file list
```

`commands/triage-pr.md:14–26` (the triage cycle Phases 1–7):
```markdown
1. Report          (you — runs the script, reads code, classifies threads)
2. Engineer decides (engineer — replies with which to fix / reject / ask back)
3. Implement       (you — apply [FIX] items; draft text for [ASK] items)
4. Push            (you — stage scoped files, commit, push with explicit refspec)
5. Resolve threads (you — for [FP] accepted and [FIX] applied, resolve via API)
6. Post replies    (you — for [ASK], post drafted reply to the thread, mention the author)
7. Hand off        (you — tell engineer cycle is done)
```

The new `/pr-triage` keeps only a single phase: identify FPs, resolve them, optionally post a context comment explaining why. Phases 2–7 of the current flow are removed or moved to GitHub UI.

`commands/triage-pr.md:193–211` (the state-changing mutations that `/pr-triage` will keep):
```markdown
### API calls
Post the comment via `addPullRequestReviewThreadReply`, then resolve via `resolveReviewThread`:

gh api graphql -f query='
  mutation($threadId: ID!, $body: String!) {
    addPullRequestReviewThreadReply(input: {pullRequestReviewThreadId: $threadId, body: $body}) {
      comment { id }
    }
  }' -F threadId="<thread_id>" -F body="<body>"
```

Main executes these mutations per the Subagent Contract — the triage agent returns the thread IDs and reasoning; main posts the GraphQL calls.

`docs/SUBAGENT-CONTRACT.md:143–147`:
```markdown
**Verifier runs on:** writes by `knowledge-cruncher`, `context-mapper`,
`process-modeler`, `domain-modeler`, `spike`, `plan-researcher`, `plan-composer`,
`task-researcher`, `task-composer`. The verifier does NOT run on
`orchestrator`, `code-reviewer`, `security-reviewer` (those agents do not
write files).
```

This list must be updated to reference `pr-reviewer` instead of `code-reviewer` and `security-reviewer`.

### Spike findings directly applicable to HOW (not what)

- **Finding 3** (`SPIKE.md:99–121`): Suggestion syntax works via `body` field of review comment using triple-backtick `suggestion` fence. For Ruby code blocks with embedded backticks, tilde-fence escaping is required (open question 2 from spike — material for the pr-reviewer prompt).
- **Finding 4** (`SPIKE.md:123–150`): `/triage-pr` Phases 5–6 already operate natively via GraphQL — only Phase 1 (HTML classification) is local. The new `/pr-triage` drops Phase 1 HTML entirely and keeps only the FP-identify-and-resolve flow.
- **Finding 7** (`SPIKE.md:199–214`): Rate limits are not a practical constraint for typical PRs. A single `POST .../reviews` with N inline comments is ONE API call. However open question 4 (what GitHub counts as "content-generating" for a review comments array on PRs with 50+ findings) is unresolved.

---

## Decision Points — options and trade-offs

### Decision 1: Migration shape — single PR vs multiple PRs

**Context:** 17+ files need changes. The work can land in a single PR or be broken into sequential PRs.

**Option A: Single PR**

All changes in one commit/PR: new `pr-reviewer.md`, deleted `code-reviewer.md` + `security-reviewer.md`, renamed `triage-pr.md` → `pr-triage.md`, updated `CLAUDE.md`, `README.md`, `SUBAGENT-CONTRACT.md`, `orchestrator.md`, `test.md`.

**Pros:** One PR to review and merge; cross-references are never in a broken intermediate state; the CHANGELOG entry is atomic.

**Cons:** Large diff — 17+ file changes in one shot; if a cross-reference is missed, it only appears at PR review; harder to bisect if a regression is found later.

**Cost / effort:** Medium — all changes in one branch, one review round.

**Risk:** Low. These are documentation/configuration files — no runtime breakage risk. The only "breakage" is a dangling reference that makes the wrong agent name appear in a chat context, which is cosmetic.

**Source patterns referenced:**
- `CLAUDE.md:329` — "ALWAYS one commit per pull request" — supports single PR as the 4Shark convention

**Option B: Multiple PRs in sequence**

Three PRs: (1) `/pr-triage` rename + scope reduction; (2) `@agent-pr-reviewer` creation + deletion of old agents; (3) cross-reference cleanup in `CLAUDE.md`, `README.md`, `SUBAGENT-CONTRACT.md`, `orchestrator.md`.

**Pros:** Each PR is smaller and easier to review; regression isolation is cleaner; the triage rename lands first so it can be dogfooded independently.

**Cons:** Cross-references are broken between PRs — after PR 1, `orchestrator.md` still says `@agent-security-reviewer`; after PR 2, the old triage command reference in `CLAUDE.md` is stale. This intermediate breakage would fire the `output-verifier` on next agent invocations.

**Cost / effort:** High — three feature branches, three review rounds, three merges.

**Risk:** Medium. The intermediate broken-reference state may confuse sessions that run between merges.

**Source patterns referenced:**
- `SPIKE.md:Finding 4` — "The skill is already a hybrid" — the triage rename can stand alone without breaking anything visible to the engineer in practice.

---

### Decision 2: Pattern injection mechanism for `@agent-pr-reviewer` (Mother Rule applied to review)

**Context:** The new `pr-reviewer` must, for each changed file in the PR diff, find 2–3 sibling/similar files, read them, extract the established pattern, and compare the diff's new code against that pattern. This is the Mother Rule from `CODE-PATTERN-DISCIPLINE.md` applied to code review rather than code writing.

Three mechanisms are possible:

**Option A: Agent prompt encodes the procedure inline (no new infrastructure)**

The `pr-reviewer.md` spec includes an explicit step: "For each changed file, list its directory, find 2–3 sibling files, read them, extract the pattern shape, then compare the diff against that pattern."

The agent executes this via its `Read`, `Glob`, `Bash` tools — the same tools it already uses for gathering diff context.

**Pros:** Zero new infrastructure; no new hook or script; the procedure is self-contained in the agent spec and visible to anyone reading it; the agent adapts to whatever the current codebase pattern actually is, not a cached snapshot.

**Cons:** Token-heavy — for a PR touching 10 files, reading 2–3 siblings per file = 20–30 additional file reads before reviewing any diff. On large PRs this adds latency and token cost. The agent could forget to run the siblings step if context gets long; the step is a prompt instruction, not a structural guarantee.

**Cost / effort:** Low (prompt change only).

**Risk:** Low-Medium. Token cost on large PRs is the primary concern. If the agent skips the sibling-read step due to context pressure, pattern comparison is silently degraded.

**Source patterns referenced:**
- `docs/CODE-PATTERN-DISCIPLINE.md:1–15` — the Mother Rule procedure (read 2–3 siblings → identify pattern → check against anti-patterns → present findings)
- `agents/code-reviewer.md:84–91` — current agent already runs Bash for diff; same pattern for sibling reads

**Option B: New supporting script that pre-computes sibling context**

A new script `scripts/pr-sibling-patterns.sh` takes a list of changed file paths (from `git diff --name-only`) and for each file lists the sibling files in the same directory with their line counts. Output is a compact JSON or text block the agent reads once before reviewing the diff.

The script does not read the sibling files — it only enumerates them. The agent then selects which 2–3 to read.

**Pros:** Separates enumeration from reading; the agent always sees the full list of candidates and chooses which to read; no prompt instruction can be forgotten because the script runs before the agent starts reviewing.

**Cons:** New script to maintain; the script must be invoked by main before spawning the agent (or the agent must invoke it as its first Bash call, which keeps the pattern in the agent spec anyway). The enumeration step alone does not guarantee the agent reads the siblings — it only presents the list. Adds one more file to the codebase with its own naming conventions.

**Cost / effort:** Medium (new script + agent spec update + wiring into main session pre-spawn or agent first-step).

**Risk:** Low. The script is read-only and small. If it fails, the agent falls back to running `ls` in the directory.

**Source patterns referenced:**
- `scripts/triage-pr.sh:1–12` — existing script pattern: small bash script, single responsibility, accepts CLI flags, emits JSON. The sibling-patterns script would follow the same shape.

**Option C: Reuse the existing `inject-code-pattern-rule.sh` hook extended to pre-load sibling excerpts**

Extend the `inject-code-pattern-on-write.sh` hook (currently fires for `Edit|Write|MultiEdit`) to also fire for the `Task` event when the task involves `pr-reviewer`. On fire, the hook reads the current git diff, enumerates changed files, and injects 2–3 sibling excerpts (10–15 lines each) as `additionalContext` into the agent's spawn context.

**Pros:** No agent-spec instruction needed; sibling context is structurally guaranteed at spawn time; the agent cannot "forget" the step because the context is already there.

**Cons:** Complex hook logic — the hook must parse the Task payload to detect that it's a `pr-reviewer` invocation, enumerate changed files, read siblings, and inject excerpts. This adds ~50–100 lines to an existing hook that is currently simple. Token cost is paid at spawn regardless of whether all siblings are relevant. The hook runs in bash; reading multiple files and concatenating them into `additionalContext` requires careful escaping. The `inject-subagent-contract.sh` pattern (reads one file, injects it) is the established shape — extending it to read many files is a deviation from that pattern.

**Cost / effort:** High (hook logic, testing, potential for hook failures blocking agent spawns).

**Risk:** Medium-High. Hook failures in `inject-code-pattern-on-write.sh` would surface as agent spawn errors. The hook currently always exits 0, but injecting partial content on a read failure is possible. The added complexity is in the critical path for every `pr-reviewer` invocation.

**Source patterns referenced:**
- `scripts/inject-code-pattern-on-write.sh` — existing hook; single responsibility (injects one doc); should not become a multi-file-reading orchestrator per the Scope Discipline rule
- `scripts/inject-subagent-contract.sh:1–15` — reads one file verbatim; the shape that works reliably

---

### Decision 3: What to do with `templates/html/code-review-board.html`

**Context:** The template is currently referenced by `agents/code-reviewer.md`, `agents/security-reviewer.md`, `commands/triage-pr.md`, and `CLAUDE.md`. After the rework, none of these files will exist or reference it. The question is whether the template has value beyond these three deleted files.

**Option A: Delete the template**

Remove `templates/html/code-review-board.html`.

**Evidence that no other consumer exists:**
`grep -rn "code-review-board"` returned exactly 4 hits — all in files being deleted or updated in this rework. No other template, script, agent, or command references the file.

**Pros:** Clean repository; no orphaned template; the `CLAUDE.md` HTML template catalog row for `code-review-board.html` is also removed, keeping the catalog accurate.

**Cons:** Loses the HTML template structure if a future use case emerges. The template represents non-trivial CSS/JS work (~300 lines per the file start seen at `templates/html/code-review-board.html:1–50`).

**Cost / effort:** Low (delete one file, update one catalog row in `CLAUDE.md`).

**Risk:** Low. The `grep` confirms no other consumer. The HTML template catalog in `CLAUDE.md:502` is the only authoritative catalog — it must be updated regardless.

**Source patterns referenced:**
- `CLAUDE.md:502` — catalog row: `| code-review-board.html | Code review or PR triage ... | @agent-code-reviewer, @agent-security-reviewer, /triage-pr |` — all three "Default for" entries are being deleted

**Option B: Keep the template, remove it from the active catalog, document as deprecated**

Move the catalog row to a "deprecated / no longer default-mapped" section, or add a comment in the file header noting it is orphaned but available.

**Pros:** Preserves the HTML work; reusable if another agent or skill needs a code-finding board in the future.

**Cons:** Dead code in a configuration repo is maintenance overhead; orphaned templates accumulate if not pruned; the `CLAUDE.md` catalog becomes inaccurate or cluttered.

**Cost / effort:** Low (comment + catalog update).

**Risk:** Low. But the "keep it just in case" argument is the canonical anti-DRY move.

**Source patterns referenced:**
- `CLAUDE.md` § "Scope Discipline — Easy wins": "Removing dead code adjacent to the change (unreachable branches, unused variables, unused imports)" — the template is dead code made visible by this change.

---

### Decision 4: File provenance — `git mv` vs delete-and-create for agent files

**Context:** `agents/code-reviewer.md` → `agents/pr-reviewer.md` and `commands/triage-pr.md` → `commands/pr-triage.md` are semantically renames-with-rework. Git can track them as renames (`git mv`) or as delete+create (new file has no history). The scripts file `scripts/triage-pr.sh` has the same question.

**Option A: `git mv` (rename in place)**

Use `git mv agents/code-reviewer.md agents/pr-reviewer.md` before editing the new file. Git's rename detection preserves the authorship history in `git log --follow`.

**Pros:** Future `git log --follow agents/pr-reviewer.md` shows the full history of the file, including pre-rename commits. Attribution is preserved.

**Cons:** For files that are substantially rewritten (the pr-reviewer spec differs significantly from code-reviewer), `git blame` becomes confusing — most lines in the new file have the old commit as origin. The "rename" is misleading when the content is 70%+ changed.

**Cost / effort:** Low.

**Risk:** Low.

**Source patterns referenced:**
- `CLAUDE.md` § "Git Commit Policy — ALWAYS one commit per pull request" — `git mv` is a normal git operation, no HubFlow concern.

**Option B: Delete and create (clean history)**

Delete the old files explicitly, create new files with the new names. Git's rename detection heuristic may or may not link them in `git log` depending on content similarity.

**Pros:** `git blame` on the new file shows only the commits that actually wrote the content. No misleading attribution. Reviewer sees a clean "this is a new thing" signal in the diff.

**Cons:** `git log --follow` does not work reliably without explicit rename tracking. If history is important for attribution (it rarely is for configuration files), this loses it.

**Cost / effort:** Low.

**Risk:** Low. For configuration/documentation files, losing rename-traced history has negligible practical impact.

**Source patterns referenced:**
- `CLAUDE.md` § "Git Safety — NEVER commit directly to develop or master" — both options are fine on a feature branch.

---

### Decision 5: Rate limit handling for large PRs (>50 findings from `@agent-pr-reviewer`)

**Context:** The new `@agent-pr-reviewer` posts its findings as a single `POST /repos/.../pulls/{pr}/reviews` with an array of inline comments. SPIKE Finding 7 confirmed a single POST is one API call regardless of comment count. However the engineer's brief flags open question 4: what GitHub counts as "content-generating" for the reviews endpoint at scale.

**Option A: Single POST — no cap (current SPIKE conclusion)**

Post all findings in one `gh api` call with a `comments` array of arbitrary length.

**Evidence from spike:** "For the code-reviewer posting a new review: a single `POST /repos/.../reviews` call with N inline comments is ONE API call. No rate limit concern for typical PRs." — `SPIKE.md:Finding 7`.

**Pros:** Simplest; one call; all findings appear atomically on the PR; the engineer sees everything at once.

**Cons:** GitHub's documentation on whether N inline comments in one POST counts as 1 request or N requests for the "content-generating" rate limit is ambiguous (open question 4 from SPIKE.md:283). If it counts as N, a PR with 50 findings would consume 50/80 of the per-minute budget in one shot.

**Cost / effort:** Low (already the natural shape).

**Risk:** Low-Medium. If the 80 req/min limit applies per-comment-in-array, 50 findings lands at 62% of the per-minute cap. 100 findings would exceed it. In practice 4Shark PRs rarely exceed 50 findings. Risk is theoretical.

**Source patterns referenced:**
- `SPIKE.md:Finding 7:199–214` — "A single `POST .../reviews` call with N inline comments is ONE API call."

**Option B: Cap findings at top N by severity, discard the rest with a note**

After the agent returns findings, main takes only the top N (e.g., top 20 by severity: Critical first, then High, then Medium) and posts them. A final comment on the PR notes "N additional Low findings were omitted — run `@agent-pr-reviewer` again with `--severity low` to see them."

**Pros:** Deterministic; no rate limit concern regardless of PR size; focuses the PR review on what matters; lower noise for the engineer.

**Cons:** Silent omission of findings; the agent does the work but some findings never appear on the PR; the "omitted findings" note requires a second API call (a standalone review comment, not inline); introduces a `--severity low` invocation model not currently planned.

**Cost / effort:** Medium (main must implement the sort+cap logic before posting).

**Risk:** Low-Medium. The primary risk is that a High finding is omitted due to a cap that's too aggressive. If the sort is by severity, this is mitigated.

**Source patterns referenced:**
- `agents/code-reviewer.md:157–163` — current severity classification: Critical / High / Medium / Low. The sort key already exists in the findings payload.

**Option C: Chunked POST — split findings into batches of N, post sequentially**

If the number of findings exceeds a threshold (e.g., 30), split into batches and post multiple `POST /reviews` calls. Each call creates a separate review thread on the PR.

**Pros:** Stays within any per-request rate limit; all findings appear on the PR.

**Cons:** Multiple review submissions from the same reviewer look odd in GitHub UI — the PR shows "pr-reviewer requested changes" twice. Each batch is a separate review event. Ordering of findings across batches is not guaranteed.

**Cost / effort:** Medium (main must implement batch logic).

**Risk:** Low-Medium. Multiple reviews from the same reviewer on the same PR is unusual but functional. GitHub does support it.

**Source patterns referenced:**
- Not found in this project's codebase. This is a new shape with no existing pattern to reference.

---

### Decision 6: Migration of in-flight PRs — reprocess or skip

**Context:** At the time of migration, there may be open PRs in the team's queue that have unresolved threads. The old `/triage-pr` has Phases 1–7 (full cycle including implement, push, resolve). The new `/pr-triage` has only the FP-resolve phase. If a PR was mid-triage when the migration lands, the in-flight cycle breaks.

**Option A: Skip — in-flight PRs complete with the old tooling before the migration merges**

Before merging the rework PR, the engineer ensures all open triage cycles are complete (no in-flight `/triage-pr` invocations pending Phase 3–6).

**Pros:** No migration complexity; clean cutover; old and new tooling never coexist.

**Cons:** Requires a "freeze" on triage until the migration merges. If the team has many open PRs, this could mean a day or two of no triage.

**Cost / effort:** Low (coordination only, no code).

**Risk:** Low.

**Source patterns referenced:**
- `CLAUDE.md` § "Git Safety" — no special consideration; this is a documentation/config repo change.

**Option B: Keep both commands for a transition period — old `/triage-pr` stays alongside new `/pr-triage`**

Both `commands/triage-pr.md` and `commands/pr-triage.md` exist simultaneously for N weeks. The old command is deprecated but functional.

**Pros:** No freeze required; in-flight PRs can complete with the old tooling.

**Cons:** Both commands are registered in Claude's command set — confusion risk; maintaining two specs that do similar things; the CHANGELOG entry becomes "deprecated old, added new" rather than a clean rename.

**Cost / effort:** Low-Medium (keep old file, add deprecation header, remove after transition).

**Risk:** Low. The old command continues to work.

**Source patterns referenced:**
- No precedent found in this repository for parallel deprecated/active commands.

**Option C: Treat all in-flight cycles as complete — re-run with new tooling on remaining threads**

On migration day, any open triage cycles are abandoned. The engineer re-runs `/pr-triage` after migration to pick up whatever threads remain open. The `/pr-triage` scope (FP-only) means the [FIX] and [ASK] threads are not handled by the new command — those stay on the PR for the engineer to address directly in the GitHub UI.

**Pros:** Cleanest migration; no parallel commands; threads that are genuinely FPs get resolved; non-FP threads are handled in the GitHub UI (which is exactly the new design intent).

**Cons:** If a [FIX] thread was identified but not yet implemented in a previous triage cycle, that information is lost. The engineer must re-evaluate those threads manually.

**Cost / effort:** Low (no code; just process).

**Risk:** Low. The worst case is that a legitimate fix thread is briefly unclassified until the engineer looks at it in GitHub.

---

### Decision 7: Test / validation plan — how to confirm before deleting old code

**Context:** The old code (code-reviewer, security-reviewer, triage-pr) is being replaced, not just renamed. Before deleting, the team needs confidence the new tools work end-to-end.

**Option A: Dogfood on the rework PR itself**

After writing `pr-reviewer.md` and `pr-triage.md`, invoke `@agent-pr-reviewer` on the rework PR (the PR that introduces the new agents). The rework PR touches 17+ files — it is a reasonable real-world test. If the agent correctly identifies patterns and returns useful findings, the tooling works.

**Pros:** Zero overhead; the rework PR is already being reviewed anyway; tests the actual diff shape (many markdown + bash files) that the agent will commonly encounter.

**Cons:** The rework PR is primarily documentation/configuration — not the typical Ruby/Rails code the agent will review most often. The pattern-injection mechanism (Decision 2) is harder to validate on markdown files than on Ruby files.

**Cost / effort:** Low.

**Risk:** Low-Medium. A false pass (the agent works on markdown but fails on Ruby) is possible.

**Source patterns referenced:**
- `agents/code-reviewer.md:84` — current agent reads `git diff develop` which is exactly what the rework PR diff contains.

**Option B: Dogfood on a concurrently open Ruby/Rails PR in another repo**

Find an open PR in `app` or `integrator` (the primary Ruby/Rails repos), run `@agent-pr-reviewer` against it manually before deleting the old agents.

**Pros:** Validates the agent against the primary target use case (Ruby/Rails diffs); tests the pattern-injection step on actual Ruby sibling files; higher confidence before deleting the old agents.

**Cons:** Requires a second open PR to exist at the right time; the engineer must coordinate the timing; the Ruby repo PR may not be representative of the full range of cases.

**Cost / effort:** Medium (timing coordination).

**Risk:** Low.

**Source patterns referenced:**
- `SPIKE.md:Finding 2:80–92` — "Anthropic itself has already answered the question for the PR-stage case: inline comments + check run." The Anthropic model suggests the inline-comment mechanism is well-understood — validation on a real PR is the right confirmation step.

**Option C: No formal validation — delete old agents immediately after writing new ones**

Write the new specs, grep for missed references, update all cross-refs, commit. No pre-merge dogfooding.

**Pros:** Fastest path to a clean repository.

**Cons:** If the new agent spec has a structural flaw (wrong API call shape, missing step), it surfaces only after the PR merges and a real review is attempted.

**Cost / effort:** Low.

**Risk:** Medium. A flawed spec in production means the next code review attempt fails silently or produces malformed GitHub comments.

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Migration shape | Single PR / Multiple PRs | Single: atomic + fewer cross-ref gaps. Multiple: smaller diffs, FP-isolation risk | □ |
| Pattern injection mechanism | Option A: inline prompt / Option B: sibling-enumeration script / Option C: hook extension | A: simplest, token-heavy on large PRs. B: structured enumeration, still needs agent read-step. C: structural guarantee, high hook complexity | □ |
| `code-review-board.html` fate | Delete / Keep deprecated | Delete: cleaner, supported by grep confirming no other consumer. Keep: preserves template work | □ |
| File provenance | `git mv` / delete-and-create | git mv: history preserved. delete-create: cleaner blame for substantially rewritten files | □ |
| Rate limit handling | Single POST no cap / cap top N / chunked POST | Single POST: simplest, risk theoretical. Cap: focused but silently omits. Chunked: complete, odd UX | □ |
| In-flight PRs | Skip (freeze) / Parallel transition period / Abandon and re-run | All low risk; coordination vs maintenance overhead vs information loss | □ |
| Validation plan | Dogfood on rework PR / Dogfood on Ruby PR / No validation | Higher confidence at some coordination cost | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| Missed cross-reference after rename | A session calls `@agent-code-reviewer` or `@agent-security-reviewer` by old name and gets "agent not found" | Run `grep -r "code-reviewer\|security-reviewer\|triage-pr"` after all edits as a final check before committing |
| `suggestion` syntax with nested backticks in Ruby (open question 2 from SPIKE) | Suggestion fences that contain Ruby code blocks with triple backticks may not render correctly on GitHub | Use tilde-fence escaping (`~~~suggestion`) in the pr-reviewer spec; validate on a real PR before launch |
| Rate limit on PRs with 50+ findings (open question 4 from SPIKE) | GitHub may count each inline comment in the array separately against the 80 req/min limit | Start with single POST (Option A for Decision 5); monitor first few large PRs; switch to chunked if limit is hit |
| `@agent-pr-reviewer` skips sibling reads under context pressure | Pattern comparison silently degraded — FPs or missed pattern deviations | If Option A for Decision 2 is chosen, explicitly position the sibling-read step as Step 1 in the agent spec with a hard instruction: "Do not proceed to diff review until you have read 2–3 siblings for each changed file" |
| `scripts/triage-pr.sh` rename breaks the auto-approve list in `settings.json` | The `auto-approve-local-skills.sh` hook auto-approves commands by their slug | Verify whether `settings.json` has a hardcoded reference to `triage-pr.sh`; update accordingly |
| Transition confusion between old and new command names during rollout | An engineer in an active session gets the old behavior because their session has the old `CLAUDE.md` in context | The `scripts/read-context.sh` hook re-reads context at SessionStart; a new session after merge gets the updated names automatically |

---

## Execution phases (high-level)

**Phase 1 — Author new specs (unblocked; can proceed in parallel)**
- Write `agents/pr-reviewer.md` — full spec for the new PR-only agent including: PR diff reading, Mother Rule applied to review (sibling-read procedure), security checks absorbed from security-reviewer, structured findings payload for main to post via `gh api`, no HTML output
- Write `commands/pr-triage.md` — reduced spec: fetch unresolved threads (reuse `triage-pr.sh` or its renamed copy), identify FPs with reasoning, return thread IDs + explanations to main, main posts GraphQL mutations
- Rename `scripts/triage-pr.sh` to `scripts/pr-triage.sh` (or keep name — see Decision 4)

**Phase 2 — Delete old specs (depends on Phase 1)**
- Delete `agents/code-reviewer.md`
- Delete `agents/security-reviewer.md`
- Delete `commands/triage-pr.md`

**Phase 3 — Update cross-references (depends on Phase 2)**
- `CLAUDE.md` — 9 locations: workflow phase numbering, agent definitions list, available commands list, HTML template catalog, verifier paragraph, Output Policy "Where this applies" paragraph
- `README.md` — 8 locations: workflow steps 5–6, usage examples, agent table, repository structure
- `docs/SUBAGENT-CONTRACT.md` — 3 locations: verifier exclusion list, inline example, Exceptions table
- `agents/orchestrator.md` — 8 locations: phase tables for both Standard and DDD workflows
- `commands/test.md` — 1 location: post-test suggestion
- `CHANGELOG.md` — add entry under `## [Unreleased]`

**Phase 4 — Template cleanup (depends on Decision 3)**
- If delete: remove `templates/html/code-review-board.html`, remove catalog row from `CLAUDE.md`
- If keep: add deprecation header, remove from active catalog

**Phase 5 — Validation (depends on Phase 1–4)**
- Run `grep -r "code-reviewer\|security-reviewer\|triage-pr"` to confirm no missed references
- Invoke `@agent-pr-reviewer` on a test PR (per Decision 7)
- Confirm FP resolution flow in `/pr-triage` by running against a PR with at least one known FP thread
- Verify `scripts/pr-triage.sh` (or renamed) produces the same JSON output shape as the old script

**Phase 6 — Commit and PR**
- One commit per the 4Shark convention
- PR title = commit message per Pull Request Policy

---

## Open questions for the engineer

1. **`scripts/settings.json` — does it hardcode `triage-pr.sh` or `triage-pr`?** The `auto-approve-local-skills.sh` hook auto-approves commands by slug. If `settings.json` has `triage-pr` in its allow list as a string match (not a glob), the rename to `pr-triage` must update that list too. This file was not read during this research pass — verify before committing Phase 1.

2. **Model for `@agent-pr-reviewer`** — the current `code-reviewer` uses `sonnet`; the current `security-reviewer` uses `opus` (the more expensive model, justified by security finding accuracy). The merged agent covers both domains. Which model should the new `pr-reviewer` use? If `sonnet`, is security analysis accuracy acceptable? If `opus`, the cost per PR review increases. This is a trade-off the engineer decides.

3. **Does the new `/pr-triage` post a context comment on resolved FP threads, or just silently resolve them?** The current `triage-pr.md` Phase 5 always posts a comment before resolving. The engineer's brief says "optionally posts a context comment." The spec needs a default. Options: (a) always post a comment explaining why (audit trail); (b) resolve silently, post comment only when the FP reasoning is non-obvious; (c) let the engineer decide per-invocation with a flag.

4. **`@agent-pr-reviewer` output: inline comments only, or inline comments + summary comment?** CodeRabbit and Anthropic's product both post a top-level PR summary comment in addition to inline findings. The summary (total findings by severity, overall assessment) gives the engineer a quick overview without scrolling the diff. The brief does not specify this. Options: (a) inline findings only; (b) inline findings + a summary comment on the PR (one additional API call).

5. **`scripts/triage-pr.sh` — rename to `scripts/pr-triage.sh` or keep the old name?** The script is referenced by `commands/triage-pr.md` (which is being deleted). After the rename, `commands/pr-triage.md` will reference it by the new path. If the script is kept at the old path for now, the naming inconsistency is minor but visible. This is a cosmetic question; either works.

---

## Sources

- `~/Projects/4Shark/dot-claude/agents/code-reviewer.md:1–180` — current code-reviewer spec; tools, process, finding payload shape
- `~/Projects/4Shark/dot-claude/agents/security-reviewer.md:1–170` — current security-reviewer spec; checklist, severity classification
- `~/Projects/4Shark/dot-claude/commands/triage-pr.md:1–242` — current triage-pr spec; Phases 1–7, GraphQL mutation shapes
- `~/Projects/4Shark/dot-claude/scripts/triage-pr.sh:1–113` — GraphQL fetch script; JSON output shape
- `~/Projects/4Shark/dot-claude/docs/SUBAGENT-CONTRACT.md:143–147` — verifier exclusion list naming `code-reviewer` and `security-reviewer`
- `~/Projects/4Shark/dot-claude/docs/CODE-PATTERN-DISCIPLINE.md:1–15` — Mother Rule procedure (the mechanism being applied to review in Decision 2)
- `~/Projects/4Shark/dot-claude/agents/orchestrator.md:46–47, 68–69, 169–170, 187–188` — phase references to old agent names
- `~/Projects/4Shark/dot-claude/scripts/inject-code-pattern-rule.sh:1–137` — hook shape; establishes that hooks inject one doc, not multi-file reading (relevant to Decision 2 Option C trade-off)
- `~/Projects/4Shark/dot-claude/scripts/inject-subagent-contract.sh:1–63` — hook shape; reads one file verbatim; establishes the "one source of truth per hook" pattern
- `~/Projects/4Shark/dot-claude/CLAUDE.md:502` — HTML template catalog row; all three "Default for" entries being deleted
- `SPIKE.md` (this directory) — 9 findings; rate limit analysis (Finding 7); triage hybrid architecture (Finding 4); suggestion syntax (Finding 3); open questions 2 and 4 (material for pr-reviewer spec)
