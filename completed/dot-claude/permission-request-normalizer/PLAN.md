# PLAN — Permission Request Normalizer

> **NOT IMPLEMENTED — superseded by measurement, archived 2026-07-16.** This plan solves a problem the data does not show. It was built on an unverified premise: that sessions stall because the agent uses a wrong FORM of an allow-listed command (env-prefixed, `env`-wrapped, absolute-pathed). Measuring the actual transcripts refuted that.
>
> **What the measurement found** (176 transcripts, 10,906 paired Bash calls, wall-clock between `tool_use` and its result): the wrong-form problem has ~18 real occurrences, all one shape — `bash /Users/<user>/.claude/scripts/terraform.sh` (absolute path) against an allow entry written with `~`. That shape was already fixed by `redirect-home-path.sh` (dot-claude PR #425, merged the same day this plan was written). The env-prefix cases that this plan's normalizer targets are `ssh` / `curl` / `terraform apply` — all on `permissions.ask` **on purpose**; the prompt there is the gate working, not a bug.
>
> **What actually stalls sessions**: chaining. A simple read-only command stalled >60s in 0.16% of 1,263 calls; the same commands CHAINED stalled in 0.90% of 2,568 — 5.7×, and 23 of the 25 stalls on instant-by-nature commands carried `;`, `|` or `&&`. Shipped as dot-claude PR #428 (`auto-approve-readonly-compound.sh` + the complementary block in `validate-bash-command.sh`).
>
> **Why this is archived rather than deleted**: the mechanism research holds up and is reusable. §A1 documents the `PermissionRequest` schema; §A3 reasons carefully about whether a `PreToolUse` block can reach the event; §A7 establishes that a broken hook fails safe. The §A2 re-validation question it could not close was later answered empirically by `redirect-home-path.sh`'s author — `updatedInput` IS re-evaluated against the allow list. Two defects the verifiers caught in the draft (a mechanically-blocked `settings.local.json` test step presented as an option; two quotes attributed to the wrong source file) are corrected in place, so the document is safe to read as-is.
>
> Reference: derived from `PLAN-SPIKE.md` (this directory) + the engineer's communicated choice, recorded below. `PLAN-SPIKE.md` in turn references `~/Projects/4Shark/dot-claude-plans/active/spike/command-form-redirect-hook/SPIKE.md` (prior research) and its two auxiliary files (`permission-request-normalizer_doc_1.md`, `permission-request-normalizer_doc_2.md`), read in full for this composition.

## Objective

A permission prompt freezes a Claude Code session until the engineer returns — sometimes hours — and the engineer runs 10–20 parallel sessions at a time. A 15-minute task becomes a multi-hour one. That is the entire cost driver this plan addresses — not "wrong commands," not a safety gap. The reason a written rule cannot fix it on its own: the agent has no way to know in advance whether a given command form will trigger a prompt, because no first-party pre-flight or dry-run mechanism exists for hooks (`PLAN-SPIKE.md` §D3: *"No dedicated 'dry-run' or 'would this be allowed' test command was found for hooks specifically"*, re-confirmed in `permission-request-normalizer_doc_1.md` § "Debugging / testing surface").

This plan builds a new `PermissionRequest` hook, `~/.claude/scripts/auto-approve-normalized-command.sh`, that normalizes a Bash command the same way `validate-bash-command.sh`'s existing "Ask-bypass detection" block already does (strip leading env-var assignments, the `env` wrapper, and the absolute path of the binary) and auto-approves the pending permission dialog when the normalized form is equivalent to something already on `permissions.allow` — so a session never stalls on a prompt for a command that is, in substance, already sanctioned.

## Governing Safety Invariant

**The hook only ever emits `allow` for a command whose normalized form affirmatively matches an entry already on `permissions.allow`. On everything else — any ambiguity, any shape it is not certain about, any parse it cannot do confidently — it emits nothing and lets the normal permission flow proceed.**

The hook's two possible failure modes are asymmetric, and the whole design leans on that asymmetry:

- **Under-approve** (the hook misses something it could have approved) → a permission prompt happens → that is the status quo today. Costs nothing new.
- **Over-approve** (the hook approves something not actually allow-listed) → a security hole.

Because of this asymmetry, the matcher does **not** need to reproduce Claude Code's own permission matcher faithfully — it needs to be a deliberately conservative **strict subset** of it. This is the load-bearing safety property, and it is a property of this hook's own code, not of undocumented harness behavior:

- **Fail-open is safe by construction** (`PLAN-SPIKE.md` §A7): exit code 2 on a `PermissionRequest` hook → *"Denies the permission"*; any other non-zero exit or malformed output → non-blocking error, *"Execution continues"* (falls through to the dialog the hook was supposed to intercept). A broken, crashing, or malformed hook script degrades to "still prompts" or "denies" — never to a silent allow.
- **The invariant dissolves both open uncertainties `PLAN-SPIKE.md` could not fully close on its own:**
  - §A2's re-validation caveat (*"When `behavior` is `'allow'` and you provide `updatedInput`, Claude Code re-validates the updated input against your project's permission rules"*) only binds if the hook uses `updatedInput`. Decision 3 below means it never does — the caveat does not apply to this design. (Main independently re-fetched `code.claude.com/docs/en/hooks` and could not reproduce that exact sentence — the third failed re-fetch across this work, consistent with the fetch tool serving a summarized slice per query. Designing so the claim is never depended on is the response, not further fetching.)
  - §A3's inference that a `PreToolUse` `emit_ask` decision reaches `PermissionRequest` (reasoned from two independently-quoted facts, not empirically confirmed) only matters if the hook might approve an `ask`-routed command. Under the invariant it cannot: a command on the `ask` list was never on `permissions.allow`, so the matcher never matches it — regardless of whether the dialog is actually reachable. **The safety therefore does not rest on undocumented harness ordering ("does exit 2 fire before the dialog?") — it rests on a property of our own code.** That is the point, and it is what turns the empirical test in Phase 6 into a verification step rather than a gate.

Every decision below follows from this invariant.

## Scope

### In scope

- The `PermissionRequest` hook's documented input/output schema — a nested `hookSpecificOutput.decision.{behavior,updatedInput,addPermissionRules,message}` object, structurally different from `PreToolUse`'s flat `permissionDecision` string (`PLAN-SPIKE.md` §A1, `permission-request-normalizer_doc_1.md`)
- Confirming that `validate-bash-command.sh`'s existing `PreToolUse` `exit 2` blocks cannot be silently bypassed by the new hook (`PLAN-SPIKE.md` §A3)
- The matcher: live parse of `permissions.allow` from `settings.json` at hook-run time, as a conservative strict subset of Claude Code's own matcher (Decision 1)
- `$(...)`/backtick refusal handling (Decision 2)
- Never rewriting the command via `updatedInput` — approve-as-typed only (Decision 3)
- The shared-logic question against `validate-bash-command.sh`'s existing normalizer (Decision 4)
- Hook script name and `settings.json` wiring shape (Decisions 5, 6)
- Execution shape: worktree/PR mechanics, CLAUDE.md summary placement per the Documentation Loading Model, CHANGELOG entry
- A pre-merge verification step (not a composition/implementation gate) confirming registration and, optionally, the `emit_ask` reachability question (Decision 7, Decision 8)

### Out of scope

- Re-litigating auto mode / `dontAsk` / `bypassPermissions` / sandbox — evaluated and rejected in the prior spike/decision-matrix research
- Any change to `validate-bash-command.sh`'s existing `exit 2` blocks
- Using `addPermissionRules` as a secondary, session-scoped self-healing mechanism — decided out of scope for this PR (Decision 5)
- Using `updatedInput` to canonicalize/rewrite the command — decided out of scope; the hook only ever approves the command as typed (Decision 3)
- The Bash Single-Line Policy citation error surfaced by the community sweep (`anthropics/claude-code#11932` fix-status correction) — real, but a separate `dot-claude` PR and a separate decision, not planned here

## Chosen approach

**Direction:** A new `PermissionRequest` hook, `~/.claude/scripts/auto-approve-normalized-command.sh`, that normalizes a Bash command exactly as `validate-bash-command.sh`'s existing "Ask-bypass detection" block does (strip leading env-var assignments, the `env` wrapper, and the absolute path of the binary), parses `permissions.allow` from `settings.json` live at hook-run time, and auto-approves — `behavior: "allow"`, never `updatedInput` — only when the normalized form affirmatively matches an existing allow entry under the conservative strict-subset matcher described in the Governing Safety Invariant above.

**Rationale (from engineer):**

1. **Matcher strategy — live parse of `settings.json`'s `permissions.allow`, not a hand-maintained mirror list** (`PLAN-SPIKE.md` §B2, Option 1 chosen over Option 2). The draft's objection to Option 1 was that reimplementing the vendor matcher risks reproducing it incorrectly (`anthropics/claude-code#29616` shows even Anthropic's own matcher has had bugs). Under the Governing Safety Invariant that objection dissolves: the goal is not to match the vendor matcher bug-for-bug, it is to never exceed it — a strict subset is safe even if imperfect. Option 2 (mirror list) is rejected because the draft's own risk table names the fatal direction: *"a REMOVAL from `permissions.allow` doesn't get mirrored, meaning the new hook keeps auto-approving something that was deliberately un-allow-listed."* A single source of truth removes that failure entirely.
2. **`$(...)` handling — refuse to auto-approve when `$(` or a backtick appears ANYWHERE in the command**, not just in the stripped segments (`PLAN-SPIKE.md` §B1). Three reasons: (a) `~/.claude/CLAUDE.md` § Ruby Version Manager in Bash already states command substitution is "an independent security layer" — this is 4Shark's own standing position, not a new one; (b) upstream `anthropics/claude-code#31373` means the built-in matcher never auto-approves a `$(...)`-bearing command, so approving one here would make this hook *more* permissive than the matcher, violating the strict-subset invariant; (c) the draft's alternative option relied on unverified upstream behavior, and a security boundary is never built on unverified behavior.
3. **`updatedInput` — never used. Approve-as-typed only** (`PLAN-SPIKE.md` §B3). The hook's entire job is to approve, not to rewrite — rewriting is what `redirect-terraform.sh` does at `PreToolUse`, and that stays there. The re-validation sentence in §A2 could not be reproduced across three fetches, so not depending on it is correct; the general argument against silent rewriting (a transparent rewrite makes an imperfect correction invisible to the agent) is the same shape `~/.claude/docs/NO-SAFE-NAVIGATION.md` names for silent no-ops.
4. **Shared normalization logic — duplicate the loop in the new hook** (`PLAN-SPIKE.md` §C, Option 1 chosen over Option 2/extraction). `~/.claude/docs/NO-PREMATURE-DRY.md` decides this: 2 call sites is below the stated floor (the Rule of Three is the *minimum*, not the trigger), and the two call sites ask genuinely different questions — does this match the ask-list, vs. does this match the allow-list — so no shared contract has revealed itself yet.
5. **`addPermissionRules` — not used. Out of scope for this PR** (`PLAN-SPIKE.md` §A4). It is session-scoped, does not persist, and does not cross the engineer's 10–20 parallel sessions (each has its own rule set); the first occurrence of a given command in each session would still prompt. It adds session-mutable state to reason about and buys nothing the per-call normalizer does not already do.
6. **Hook script name — `~/.claude/scripts/auto-approve-normalized-command.sh`**. The repo's naming convention is already established by bucket — `validate-*` blocks, `redirect-*` rewrites, `inject-*` adds context, `check-*` flags, `auto-approve-*` emits allow (four precedents already exist: `auto-approve-aws-readonly.sh`, `auto-approve-gmail-read.sh`, `auto-approve-local-skills.sh`, `auto-approve-safe-mv.sh`). This hook emits allow, so it belongs in that bucket.
7. **The empirical test proposed in `PLAN-SPIKE.md` §D3 does not gate composition or implementation** — it becomes a verification step during implementation instead, per the Governing Safety Invariant: the safety no longer depends on the `emit_ask`-reachability inference it would have tested.
8. **Minimum version — resolved.** Installed Claude Code is 2.1.211 (`claude --version`, run by main). Main's own re-fetch of `code.claude.com/docs/en/hooks` independently confirms `PermissionRequest` is a current, documented event with `hookSpecificOutput` → `decision.behavior` (allow/deny) and exit-2 → "Denies the permission." Registration is still confirmed via `/hooks` after wiring, per the draft's own recommendation (Phase 6 below), but the UNVERIFIED tag on §A6 is dropped.

**Source patterns referenced:**
- `~/.claude/scripts/validate-bash-command.sh:502-539` — existing "Ask-bypass detection" normalizer, the mirror-image mechanism this hook's normalization loop is duplicated from
- `~/.claude/scripts/redirect-terraform.sh` — existing `updatedInput`-based redirect precedent; its rewrite pattern is explicitly NOT adopted here (Decision 3)
- The existing `auto-approve-*.sh` naming bucket: `auto-approve-aws-readonly.sh`, `auto-approve-gmail-read.sh`, `auto-approve-local-skills.sh`, `auto-approve-safe-mv.sh`
- The documented process-wrapper stripping (`timeout`, `time`, `nice`, `nohup`, `stdbuf`) per `code.claude.com/docs/en/permissions` § "Bash — process wrappers" — Claude Code's own behavior, applied automatically before any rule match, independent of what this hook does

## Execution phases

### Phase 1: Worktree setup

**Objective:** Prepare an isolated worktree for the change, per § Configuration Changes Policy / § Worktree Policy — never edit the installed `~/.claude/` directly.

**Components:**
- Worktree at `.claude/worktrees/<name>` inside `~/Projects/4Shark/dot-claude/`, created on branch `feature/permission-request-normalizer` from `origin/develop` via `git worktree add`
- `bash ~/.claude/scripts/setup-worktree.sh <worktree-path>` run for consistency (a no-op for the `dot-claude` repo per its curated allowlist, but run anyway per standing convention)

**Dependencies:** None

**Success criteria:**
- [ ] Worktree created on a feature branch off `origin/develop`
- [ ] No edit made to the installed `~/.claude/settings.json` or `~/.claude/settings.local.json` at any point in this work — all edits happen on the tracked copy inside the worktree

### Phase 2: Hook script

**Objective:** Implement `auto-approve-normalized-command.sh` so it obeys the Governing Safety Invariant by construction.

**Components:**
- `PermissionRequest`-shaped hook, scoped to Bash tool calls only (`"matcher": "Bash"`, per `PLAN-SPIKE.md` §B4)
- Normalization loop duplicated from `validate-bash-command.sh:502-539`: strip a leading env-var-assignment token repeatedly, strip a leading `env` wrapper, strip the leading absolute path of the binary — per Decision 4, this loop is NOT extracted into a shared helper
- Refusal check, evaluated on the ORIGINAL command string (before any stripping): if `$(` or a backtick appears ANYWHERE, the hook emits nothing and lets the dialog proceed (Decision 2)
- Matcher: live-parse `permissions.allow` from `settings.json` at hook-run time and apply the documented match rules (prefix matching, `:*` suffix) as a conservative strict subset — on any ambiguity or any shape the matcher is not certain about, emit nothing (Decision 1, Governing Safety Invariant)
- On a confirmed match: emit `hookSpecificOutput.hookEventName: "PermissionRequest"` with `decision.behavior: "allow"` on the command exactly as typed — `updatedInput` is never populated (Decision 3)
- On no match, or any parse the hook is not confident about: exit 0 with no output, so the normal permission dialog proceeds unchanged

**Dependencies:** Phase 1

**Success criteria:**
- [ ] The script never emits `allow` unless the normalized form affirmatively matches an entry already on `permissions.allow`
- [ ] The script never populates `updatedInput`
- [ ] The script refuses (emits nothing) on any command containing `$(` or a backtick, anywhere in the original string
- [ ] The script's registration scopes it to Bash tool calls only

### Phase 3: settings.json wiring

**Objective:** Register the hook under a new top-level `hooks.PermissionRequest` key in the tracked `settings.json`.

**Components:**
- New top-level `hooks.PermissionRequest` entry — confirmed absent today (`grep -n "PermissionRequest" settings.json` returns zero matches, per `PLAN-SPIKE.md` §D2), so this is a first-of-its-kind wiring point, not a modification of an existing block
- Matcher: `"Bash"`

**Dependencies:** Phase 2

**Success criteria:**
- [ ] The tracked `settings.json` carries the new `hooks.PermissionRequest` registration
- [ ] No existing hook block is modified

### Phase 4: CLAUDE.md summary

**Objective:** Add the loader summary so the hook is discoverable by future sessions, per § Documentation Loading Model.

**Components:**
- A new summary section in `~/.claude/CLAUDE.md`, following the existing pattern used for the other `auto-approve-*.sh` hooks, naming what the hook does and the Governing Safety Invariant it operates under

**Dependencies:** Phase 3

**Success criteria:**
- [ ] A CLAUDE.md summary exists for the new hook — *"a hook with no summary here does not reach the session"* (§ Documentation Loading Model)

### Phase 5: CHANGELOG entry

**Objective:** Record the change per § Changelog Policy.

**Components:**
- Entry under `## [Unreleased]` → `### Added` (this repo is on a feature branch, not `release/*`/`hotfix/*` — per § Git Tag & Version Policy, new entries go under Unreleased, no dated section)

**Dependencies:** Phase 4

**Success criteria:**
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`

### Phase 6: Pre-merge verification (not a gate)

**Objective:** Confirm the mechanism behaves as designed before merge. Per Decision 7, this is a verification step, not a blocking gate on composition or implementation — the Governing Safety Invariant already makes the hook safe independent of this step's outcome.

**Components:**
- Confirm registration via `/hooks` (the read-only browser) — confirms the hook is recognized under the `PermissionRequest` event and shows which settings file it came from
- Re-confirm the installed Claude Code version supports the event (already confirmed as 2.1.211 per Decision 8; re-verify via `/hooks` after wiring, since that is the cheapest available confirmation)
- Optional confirmatory check of the `emit_ask` reachability question (`PLAN-SPIKE.md` §A3): register the hook with a mode that logs every `PermissionRequest` payload it receives, trigger a known `emit_ask` case (e.g. `git tag`, confirmed on the ask-list by the sibling spike's catalog), and confirm the payload arrives. This is confirmatory only — per the Governing Safety Invariant, the hook's safety does not depend on this test passing, since it never approves an `ask`-routed command regardless of whether the dialog is reachable

**Dependencies:** Phase 3 (registration must exist to test)

**Success criteria:**
- [ ] `/hooks` confirms the `PermissionRequest` hook is registered and recognized

### Phase 7: PR to develop

**Objective:** Open the PR for engineer review.

**Components:**
- Single commit, Angular Commit Guidelines format (`<type>(<scope>): <subject>`, scope mandatory), no AI references, no AI co-authorship
- PR targets `develop`

**Dependencies:** Phases 2–6 complete

**Success criteria:**
- [ ] PR open against `develop`, carrying the hook script, the `settings.json` wiring, the CLAUDE.md summary, and the CHANGELOG entry
- [ ] PR left open for the engineer to review and merge — merging is never automatic

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Matcher strategy (`PLAN-SPIKE.md` §B2) | Live parse of `settings.json`'s `permissions.allow` at hook-run time | Single source of truth; the strict-subset invariant means reimplementation risk (`#29616`) is no longer disqualifying, while a mirror list's removal-drift risk (Finding A5's own liability) is |
| `$(...)`/backtick handling (§B1) | Refuse to auto-approve whenever `$(` or a backtick appears ANYWHERE in the original command | Matches 4Shark's own standing position (command substitution is an independent security layer, § Ruby Version Manager in Bash); the upstream matcher never auto-approves such a command either (`#31373`), so approving it here would exceed the strict-subset bound |
| `updatedInput` usage (§B3) | Never used — approve-as-typed only | The hook's job is to approve, not rewrite; the re-validation sentence could not be independently reconfirmed, so the design never depends on it; matches the documented "avoid re-validation" path in `permission-request-normalizer_doc_1.md` |
| Shared normalization logic (§C) | Duplicate the ~20-line loop in the new hook, do not extract a shared helper | `NO-PREMATURE-DRY.md`: 2 call sites is below the stated floor; the two sites ask genuinely different questions (ask-list match vs. allow-list match), so no shared contract has revealed itself |
| `addPermissionRules` usage (§A4) | Not used — out of scope for this PR | Session-scoped only; does not persist or cross the engineer's 10–20 parallel sessions; adds session-mutable state for no gain over the per-call normalizer |
| Hook script name and location (§D2) | `~/.claude/scripts/auto-approve-normalized-command.sh` | Matches the established `auto-approve-*.sh` naming bucket (emits allow); consistent with `validate-*`/`redirect-*`/`inject-*`/`check-*` conventions already in the repo |
| Testing approach before merge (§D3) | `/hooks` registration confirmation, plus an optional confirmatory `emit_ask` reachability test — neither is a gate | No true dry-run exists for hooks; under the Governing Safety Invariant the mechanism's safety does not depend on the reachability test's outcome, so it is verification, not a blocker |
| Minimum version (§A6) | Confirmed — installed version 2.1.211 supports `PermissionRequest` | `claude --version` run by main; independently re-confirmed via re-fetch of `code.claude.com/docs/en/hooks`; `/hooks` re-verification kept as the cheapest post-wiring confirmation |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Re-validation confidence caveat (§A2) was based on a single fetch that could not be reproduced on self-check | DISSOLVED as a design risk | The hook never uses `updatedInput` (Decision 3), so the re-validation path this caveat concerns is never exercised — the uncertainty no longer applies to this design |
| `$(...)` surviving normalization in the command that actually executes (§B1) | A malicious or accidental substitution could execute if the normalized (substitution-stripped) form happened to match an allow entry | CLOSED by Decision 2 — the hook refuses to auto-approve whenever `$(` or a backtick appears anywhere in the original command |
| Two-list drift, had a hand-maintained mirror list been chosen (§B2 Option 2) | A future `permissions.allow` addition would not auto-extend to its wrong-shape form, or a removal would leave a stale auto-approval in place | CLOSED by Decision 1 — a live parse of `permissions.allow` is the single source of truth; no second hand-edited list exists |
| Minimum version unverified (§A6) | If the installed version predates `PermissionRequest`, the hook would silently never fire (fail-open, not a security risk, but the stall problem would persist undiagnosed) | RESOLVED — installed version is 2.1.211, independently re-confirmed as supporting the event; `/hooks` re-verification kept in Phase 6 as the cheapest post-wiring confirmation |
| §A3's `emit_ask` reachability was inferred, not empirically confirmed | DISSOLVED as a safety risk (was: the mechanism could either never see `ask`-routed commands, or something unmodeled could happen) | Under the Governing Safety Invariant, the hook never approves an `ask`-routed command regardless of whether `PermissionRequest` fires for it — a command on the ask list was never on `permissions.allow`, so the matcher never matches it. The optional empirical test in Phase 6 remains as a confirmatory step, not a gate |

**Follow-up, not planned here:** the Bash Single-Line Policy's citation of `anthropics/claude-code#11932` needs a fix-status correction (the wildcard-matching bug it describes was fixed in early March 2026, per maintainer bcherny) — a separate `dot-claude` PR and a separate decision.

## Assumptions

- The documented `PermissionRequest` schema — a nested `hookSpecificOutput.decision.{behavior,updatedInput,addPermissionRules,message}` object — is correct, corroborated independently by `anthropics/claude-code#19298`'s bug report, which shows the flat `PreToolUse` shape failing silently on this event (`PLAN-SPIKE.md` §A1–A2)
- `validate-bash-command.sh`'s existing `exit 2` blocks (`gh pr merge`, `git reset --hard`, EC2 start/stop, etc.) cannot be silently bypassed by this hook, because a call stopped before permission-rule evaluation never reaches a dialog and therefore never reaches `PermissionRequest` (`PLAN-SPIKE.md` §A3, from two independently-quoted facts)
- A broken or malformed hook fails safe — deny or still-prompts, never silent-allow (`PLAN-SPIKE.md` §A7)
- The documented process-wrapper stripping (`timeout`, `time`, `nice`, `nohup`, `stdbuf`) is Claude Code's own behavior, applied automatically before any rule match, independent of this hook's own logic

---

> **Authoring:** written by `@agent-plan-composer` from the engineer-validated `PLAN-SPIKE.md` plus the engineer's communicated choices, recorded above as Decisions 1–8. No new options, no new technical decisions, no new assumptions were introduced at the composer stage — every claim traces to the draft or to the engineer's choice. The `output-verifier` runs scope-containment, citation-integrity, contract-compliance, template-compliance, and reference-resolution checks after this write.
