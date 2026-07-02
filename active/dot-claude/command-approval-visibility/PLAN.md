# PLAN — Command Approval Visibility (Mechanical Enforcement)

> Reference: KNOWLEDGE.md, CONTEXT-MAP.md, PROCESS.md, DOMAIN.md — not present (standard workflow, no DDD phase for this feature); derived from `PLAN-SPIKE.md` in this directory, which itself builds on `~/.claude/plans/active/spike/agent-command-approval-visibility/SPIKE.md` (10 findings) and auxiliary `subagent_hook_scope_1.txt`.

## Objective

Close the "opaque command at approval time" gap: a `VAR=$(cmd) ... long-wrapper-path ...` shape (concretely, `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...`) currently reaches the human approver as a hard-to-review string. The fix is mechanical — a new `PreToolUse` `exit 2` block in `validate-bash-command.sh` following the same block-and-redirect pattern the file already uses twice — plus a documentation correction so `CLAUDE.md`'s self-print rule (`Executando o comando completo: <full command>`) is no longer framed as if it were enforcement, when Claude Code's own documentation establishes that permission rules are enforced by Claude Code, not by the model.

## Scope

### In scope

- A new `PreToolUse` `exit 2` block in `~/Projects/4Shark/dot-claude/scripts/validate-bash-command.sh` detecting the opaque `VAR=$(...)`-into-long-version-manager-wrapper-path shape, using the Candidate 3 heuristic: reuse the existing `VAR=`/`env`-stripping normalization loop (Pattern 3, `validate-bash-command.sh:453-490`), then match the normalized command against the wrapper-path regex family already in production in `inject-working-dir-reminder.sh:61` (`/\.rvm/wrappers/|/\.rbenv/shims/|/\.asdf/shims/`).
- The match requiring a **compound condition**: a `VAR=` prefix present AND the wrapper-path match — not either alone.
- Draft 1's corrective stderr message (wrapper-specific, routes to `ruby.sh`) for the new block.
- A header comment on the new block documenting its deliberately narrow scope (Ruby/version-manager-wrapper-specific), so the non-Ruby opaque-wrapper case is a known, recorded gap rather than a silent omission — matching how the file's other blocks self-document.
- Correcting `~/Projects/4Shark/dot-claude/CLAUDE.md` § "Bash Single-Line Policy" using Variant 2 wording: re-label the self-print bullet as "best-effort transparency, not a security boundary," pointing at the actual mechanical control in § Command Safety Policy.
- Aligning `~/Projects/4Shark/dot-claude/scripts/inject-working-dir-reminder.sh`'s existing advisory corrective text with the new block's remediation guidance (both point to `ruby.sh`), without changing its detection logic or its advisory (non-blocking) tier.
- A manual test-case matrix (§5 of `PLAN-SPIKE.md`) validating the new block before merge, following the same validation pattern documented in PRs `#151`, `#239`, `#324` for this file.
- A live test (spawn a real subagent via the `Task` tool, observe whether a `PermissionRequest` hook fires for a subagent-originated `Bash` call) that decides whether Option B (`PermissionRequest` hook) gets built at all, and if so, how it is scoped.
- All edits land in the `~/Projects/4Shark/dot-claude/` working copy via a feature branch + PR, per `CLAUDE.md` § "Configuration Changes Policy" — never a direct edit to `~/.claude/`.

### Out of scope

- Whether A, B, C, D, or E is the right top-level direction — already decided by the engineer (Option E = A + B + C).
- Sandboxing / Auto Mode classifier investment (the source spike's separate trade-off row).
- Carve-out Candidates 1, 2, and 4, and the "1 OR 3" combination — Candidate 3 alone was chosen; the false-positive/false-negative profiles of the other candidates are not part of this plan's committed work.
- Full removal of the CLAUDE.md self-print bullet (Variant 1) — the practice is kept, only its framing is corrected.
- Folding `inject-working-dir-reminder.sh`'s wrapper-path detection into the new block and retiring the advisory duplication — the existing hook stays in place unchanged in function; only its message text is aligned.
- Building Option B (`PermissionRequest` hook) unconditionally — it is built only if the live subagent test in Phase 5 confirms the hook fires for subagent-originated calls.
- Any direct edit to `~/.claude/scripts/` or `~/.claude/CLAUDE.md` — all changes go through the `dot-claude` working copy and PR workflow.

## Chosen approach

**Direction:** Option E = A + B (conditional) + C, as locked by the engineer from the source spike's option space — extending `validate-bash-command.sh` with a new opaque-command block (A), correcting the CLAUDE.md self-print framing (C), and treating the `PermissionRequest` hook (B) as conditional on fresh evidence rather than committed up front.

**Rationale (from engineer):** the whole feature is to mechanically enforce visibility of opaque command shapes at the Bash approval boundary, and to correct the CLAUDE.md self-print rule so it is no longer framed as a control. Option B is not built blind: fresh evidence (GitHub issues `#23983` and `#34692`, `PLAN-SPIKE.md` §2 + `subagent_hook_scope_1.txt`) indicates B is likely main-session dead code (a `PreToolUse` `exit 2` from A pre-empts `PermissionRequest`'s firing condition) and likely does not fire for subagent-originated calls either — so committing to B's implementation without first confirming its actual coverage risks building dead code. A live test, not a documentation conclusion, decides B.

**Source patterns referenced (from `PLAN-SPIKE.md`, all read in full):**

- **Pattern 1 — Infra-compound block**, `validate-bash-command.sh:159-200`: the file's existing "detect an opaque/unreviewable shape at a segment start, block with `exit 2`, redirect to the atomic form" precedent.
- **Pattern 2 — Work-script-pipe block**, `validate-bash-command.sh:202-237`: the file's second existing example of the same block-and-redirect shape, this time for output-truncation piping.
- **Pattern 3 — Ask-bypass normalization loop**, `validate-bash-command.sh:453-490`: strips leading `VAR=value`/`env` tokens before re-matching — directly reused by the new block to isolate "what the command looks like with every leading `VAR=`/`env` token removed."
- **Pattern 4 — `cd && cmd` block's corrective text**, `validate-bash-command.sh:130-138` (specifically line 135): sanctions `VAR=value cmd` verbatim — the shape any new block must NOT contradict for the short, legitimate case.
- **Pattern 5 — `ruby.sh`'s "absorb the substitution internally" fix**, `~/.claude/scripts/ruby.sh` (111 lines): the target remediation for the new block's corrective message.
- **Pattern 6 — `inject-working-dir-reminder.sh`'s existing wrapper-path detection regex**, `inject-working-dir-reminder.sh:61`: `/\.rvm/wrappers/|/\.rbenv/shims/|/\.asdf/shims/` — already battle-tested in production at the advisory tier, directly reused as the new block's wrapper-path match.

## Execution phases

### Phase 1: Extend `validate-bash-command.sh` with the new opaque-command block (Option A)

**Objective:** Add a `PreToolUse` `exit 2` block that detects the `VAR=$(...)`-into-long-version-manager-wrapper-path shape and blocks it before it reaches the human as an unreadable approval prompt.

**Components:**
- New block in `~/Projects/4Shark/dot-claude/scripts/validate-bash-command.sh`, placed following the file's existing block ordering conventions.
- **Detection logic:** reuse the `VAR=`/`env`-stripping normalization loop (Pattern 3) to produce the normalized command, then match the normalized command against the wrapper-path regex (Pattern 6): `/\.rvm/wrappers/|/\.rbenv/shims/|/\.asdf/shims/`.
- **Compound condition:** the block fires only when BOTH a `VAR=` prefix was present in the original command AND the normalized command matches the wrapper-path regex — a bare `~/.rvm/wrappers/ruby-3.2/gem list` with nothing hidden must NOT be swept in.
- **Corrective message:** Draft 1 from `PLAN-SPIKE.md` §3 — states the "Why" (this is exactly the case `ruby.sh` exists for; `$(...)` already forces manual approval regardless of any allow-list rule, so this block intercepts before that already-mandatory prompt reaches the human in opaque form), the "Fix" (`bash ~/.claude/scripts/ruby.sh [--dir <abs-project-dir>] <tool> [args...]`), and "See" (`~/.claude/docs/RUBY-COMMAND-EXECUTION.md`).
- **Header comment:** documents that the block is deliberately scoped to the Ruby/version-manager-wrapper case only — a future non-Ruby opaque-wrapper shape is a known, recorded gap, not a silent omission — matching the self-documentation style of the file's existing blocks.

**Dependencies:** none — Patterns 1, 3, 4, 5, and 6 are all already present in the codebase and require no prior change.

**Success criteria:**
- [ ] The new block fires (`exit 2`) on the exact spike-cited shape: `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...`
- [ ] The block does NOT fire on the sanctioned escape hatch: `AWS_PROFILE=prod aws sts get-caller-identity`, `BUNDLE_GEMFILE=/abs/path/Gemfile bundle exec rspec` (no long-wrapper path)
- [ ] The block does NOT fire on a bare wrapper invocation with no `VAR=` prefix present
- [ ] `bash -n scripts/validate-bash-command.sh` passes (auto-approved per `settings.json:434`)
- [ ] The block's header comment documents its narrower (Ruby-only) scope as a deliberate, known limitation

### Phase 2: Correct CLAUDE.md § "Bash Single-Line Policy" (Option C)

**Objective:** Re-frame the self-print rule so it reads as best-effort transparency, not as if it were a control.

**Components:**
- Edit `~/Projects/4Shark/dot-claude/CLAUDE.md`, the existing bullet at (repo-copy equivalent of) `CLAUDE.md:24`: *"Before executing a long command, print it explicitly so the engineer can read it before approving. Format: `Executando o comando completo: <full command>`. The single line will scroll off-screen — the printed copy preserves visibility into what is about to run"*
- Replace with Variant 2 wording from `PLAN-SPIKE.md` §4:

  > **Best-effort transparency, not a security boundary**: before executing a long command, the agent SHOULD print it explicitly so the engineer can read it before approving (format: `Executando o comando completo: <full command>`). This is advisory only — per Claude Code's own documentation, permission rules are enforced by Claude Code, not by the model, and prompt-level instructions do not change what Claude Code allows. The actual mechanical guarantee against an opaque or unreadable command is the PreToolUse block in `validate-bash-command.sh` — see § Command Safety Policy.

**Dependencies:** none functionally, but should land in the same PR as Phase 1 so the corrected bullet can reference the new block by name.

**Success criteria:**
- [ ] The bullet no longer implies the self-print instruction is itself an enforcement mechanism
- [ ] The bullet explicitly points to § Command Safety Policy / `validate-bash-command.sh` as the actual mechanical guarantee
- [ ] The practice itself (printing the full command) is preserved, not removed

### Phase 3: Align `inject-working-dir-reminder.sh`'s corrective guidance with the new block

**Objective:** Ensure the advisory hook and the new blocking hook do not give the model divergent remediation guidance for the same command shape in the same `PreToolUse` pass.

**Components:**
- Review `~/Projects/4Shark/dot-claude/scripts/inject-working-dir-reminder.sh`'s current advisory message text.
- Update its remediation wording (not its detection regex, not its advisory/non-blocking tier) so it agrees with the new block's Draft 1 corrective message — both route to `ruby.sh`.

**Dependencies:** Phase 1 (the new block's exact corrective wording must exist first, so this phase can align to it).

**Success criteria:**
- [ ] `inject-working-dir-reminder.sh` continues to fire as an advisory-only reminder (no change to its `additionalContext`-only behavior, no change to `permissionDecision`)
- [ ] Its remediation text and the new block's corrective message agree on pointing to `ruby.sh`
- [ ] No detection-logic change to this file — its existing wrapper-path regex and rate-limiting behavior are untouched

### Phase 4: Validate the new block via the manual test-case matrix

**Objective:** Confirm the new block behaves correctly before merge, using the same validation pattern documented in the three most similar prior additions to this file (PRs `#151`, `#239`, `#324`) — since no automated test harness exists for `~/.claude/scripts/` (confirmed: no `.bats` files, no `tests/`/`spec/` directory, no `.github/workflows/` in `dot-claude`).

**Components:**
- Manual validation via `printf JSON | bash scripts/validate-bash-command.sh` for each case in the matrix below (from `PLAN-SPIKE.md` §5), plus `bash -n scripts/validate-bash-command.sh`.
- **Should block:** the exact `RAILS_MASTER_KEY=$(cat config/master.key) BUNDLE_GEMFILE=/abs/Gemfile ~/.rvm/wrappers/ruby@gemset/bundle exec ...` shape from `RUBY-COMMAND-EXECUTION.md:36`.
- **Should pass (regression against the sanctioned escape hatch, `CLAUDE.md:40`):** `AWS_PROFILE=prod aws sts get-caller-identity`; `BUNDLE_GEMFILE=/abs/path/Gemfile bundle exec rspec` (no long-wrapper path).
- **Should still block (regression on the two existing blocks in the same file):** the Pattern 1 (infra-compound) and Pattern 2 (work-script-pipe) example commands — since checks run sequentially and each `exit`s on match, the new block's placement relative to Patterns 1 and 2 must be verified for any overlapping shape.
- **Corrective-message rendering:** confirm the chosen Draft 1 message renders correctly on `stderr` and that the suggested `ruby.sh` invocation is syntactically correct.
- **Placement verification:** confirm which block fires first for any command shape that could match more than one pattern (the sequential-block-placement risk, below).

**Dependencies:** Phase 1 (the block must exist to test), Phase 3 (message alignment should be verified alongside).

**Success criteria:**
- [ ] Every "should block" case blocks with the correct corrective message
- [ ] Every "should pass" regression case passes with no new prompt/block
- [ ] Every "should still block" regression case still fires its original block (Pattern 1 or Pattern 2), not superseded incorrectly by the new block
- [ ] `bash -n` passes
- [ ] Block placement relative to Patterns 1 and 2 is confirmed correct for any overlapping shape

### Phase 5: Live subagent test — decides whether Option B is built (conditional gate)

**Objective:** Determine, empirically, whether a `PermissionRequest` hook fires for a subagent (Task tool) Bash call — the fact the source spike left uncertain and that neither internal citation trail nor external GitHub issue research (`#23983`, `#34692`) fully resolves on its own.

**Components:**
- Spawn a real subagent via the `Task` tool in a live session, with a wired `PermissionRequest` hook configured for a Bash call shape the subagent will trigger.
- Observe directly whether the hook fires for that subagent-originated call.
- **Decision rule (from the engineer, recorded here as settled):**
  - IF the hook fires for the subagent call → build Option B as genuine subagent-layer coverage, with a regex deliberately scoped for that purpose (not simply duplicating Option A's detection logic, since a same-shape B would be dead code in the main session per the ordering analysis in `PLAN-SPIKE.md` §2).
  - IF the hook does NOT fire → drop Option B and document the residual subagent gap explicitly, rather than shipping a hook proven to add no coverage.

**Dependencies:** none blocking — can run independently of Phases 1-4, but the decision determines whether Phase 6 exists at all.

**Success criteria:**
- [ ] A live subagent spawn was observed with a wired `PermissionRequest` hook
- [ ] The fire/no-fire outcome is recorded
- [ ] The decision (build B / drop B) follows the recorded outcome per the decision rule above

### Phase 6 (conditional — only if Phase 5 confirms the hook fires for subagents): Build Option B

**Objective:** Add a `PermissionRequest` hook as genuine second-layer, subagent-scoped coverage for the same opaque-command shape.

**Components:**
- New hook wired to `PermissionRequest` in `settings.json` (a new hook type for this repository — no prior production example to extend, per the source spike's Finding 6).
- Detection logic deliberately distinct from Option A's — targeting the case A cannot reach (subagent-originated calls), not duplicating A's main-session coverage.
- Validated the same way as Phase 4 for the hook script's own matching logic (`printf JSON | bash script`), plus the live-test method from Phase 5 to confirm the platform actually invokes the hook for the call sites it is meant to cover.

**Dependencies:** Phase 5 confirming the fire condition.

**Success criteria:**
- [ ] The hook fires for the subagent shapes it targets (re-confirmed via a live test, not just the script's own logic)
- [ ] The hook's regex is demonstrably distinct from Option A's, closing a gap A does not cover
- [ ] `settings.json` wiring is correct and does not duplicate or conflict with the existing `PreToolUse` wiring

### Phase 7: Changelog and PR

**Objective:** Land the change through the standard `dot-claude` contribution flow.

**Components:**
- Feature branch off `develop` in `~/Projects/4Shark/dot-claude/`.
- `CHANGELOG.md` entry under the appropriate section (per CLAUDE.md § Changelog Policy — user-facing/behavior-facing description, no implementation detail).
- `gh pr create` targeting `develop`, per § Configuration Changes Policy (the engineer pulls `~/.claude/` after merge).

**Dependencies:** Phases 1-4 complete (committed work); Phase 5 resolved (Phase 6 included only if triggered).

**Success criteria:**
- [ ] All committed-work phases (1-4) and the Phase 5 decision are reflected in a single PR (or Phase 6 is a documented follow-on if B is built)
- [ ] `CHANGELOG.md` updated
- [ ] PR opened against `develop`, not merged by the agent

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Carve-out heuristic for Option A | Candidate 3 alone — wrapper-path match (after `VAR=`/`env` stripping) against `/\.rvm/wrappers/\|/\.rbenv/shims/\|/\.asdf/shims/` | Only candidate with zero found false positives against the sanctioned `VAR=value cmd` escape hatch; maps 1:1 to the `ruby.sh` remediation. The narrower (Ruby-specific) scope is a deliberate choice, not an oversight — the non-Ruby opaque-wrapper case is a known, documented gap, flagged in the new block's own header comment (as the file's other blocks do), not silently omitted |
| Match condition for Candidate 3 | Compound: `VAR=` prefix present AND wrapper-path match — not either alone | A bare `~/.rvm/wrappers/ruby-3.2/gem list` with nothing hidden must not be swept in |
| Scope and priority of Option B | Conditional, gated on a live subagent test (spawn a real subagent via the Task tool, observe whether `PermissionRequest` fires) | B is not built blind. Fresh evidence (issues `#23983`, `#34692`, `PLAN-SPIKE.md` §2, `subagent_hook_scope_1.txt`) indicates B is likely main-session dead code (a `PreToolUse` `exit 2` from A pre-empts `PermissionRequest`'s firing condition) and likely does not fire for subagents either — building it blind risks dead code. The two UNVERIFIED issues (`#40580`, `#26923`) are exactly why a live test, not a documentation conclusion, decides B. Decision rule: fires → build B scoped for genuine subagent-layer coverage; does not fire → drop B and document the residual gap |
| Corrective message for Option A | Draft 1 — the wrapper-path-specific message that routes to `ruby.sh` | Draft 2 (generic `$(...)`-in-`VAR=` fallback) is not used, since Candidate 1 was not chosen as the detection heuristic |
| CLAUDE.md wording for Option C | Variant 2 — re-label the self-print bullet as "best-effort transparency, not a security boundary," pointing at the mechanical control in § Command Safety Policy | Full removal (Variant 1) is not chosen — the practice is kept, only its framing is corrected. Variant 2 preserves whatever residual value the practice has (a legible signal on the rare command the new mechanical block doesn't match) while being honest about its trust tier |
| Coordination with `inject-working-dir-reminder.sh` | Align remediation wording only — do not fold detection logic into the new block, do not retire the advisory hook | Keep the existing advisory hook in place (it correctly covers the legible, no-`VAR=`-prefix wrapper-path case at the advisory tier); the only change is making both hooks' remediation guidance agree (both point to `ruby.sh`) so the model does not receive divergent guidance in the same `PreToolUse` pass |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Carve-out too narrow (Candidate 3 alone) | A future non-Ruby opaque-wrapper shape is not covered — the spike's broader framing (not Ruby-specific) is only partially addressed | Document the narrower scope explicitly in the block's own header comment (Phase 1), so a future incident is a known, deliberate gap rather than a surprise |
| Option B, if built, provides no measurable benefit | Engineering effort (a new hook type, new `settings.json` wiring) for a layer that could be main-session dead code and/or not cover subagents | Resolved by gating B on the Phase 5 live test rather than committing to its shape in advance; if built, its regex must be deliberately distinct from Option A's (Phase 6) |
| Sequential-block placement in `validate-bash-command.sh` | The file's checks run top-to-bottom, each ending in `exit 2` on match — if the new block is placed after an existing one that partially overlaps, the existing (possibly less precise) block's message fires instead of the new one's | Placement is an explicit item in the Phase 4 test-case matrix — verify which block fires first for any command matching more than one pattern |
| Internal citation trail (`agent-pipe-chaining` → `llm-agent-command-chaining`) does not currently resolve | Reduces confidence in one input to the subagent-coverage conclusion, though fresh external research reaches a materially similar conclusion independently | Documented plainly in `subagent_hook_scope_1.txt`; this plan does not depend on the unresolved internal citation — and the Phase 5 live test is the actual source of truth regardless |

## Assumptions

- Patterns 1-6 (as cited by `file:line` in `PLAN-SPIKE.md` and reproduced above) remain unchanged in `validate-bash-command.sh`, `ruby.sh`, and `inject-working-dir-reminder.sh` between the drafting of `PLAN-SPIKE.md` and execution — validated by Phase 4's own test pass, which re-confirms the current file state.
- No automated test harness exists for `~/.claude/scripts/` in this repository (confirmed: no `.bats` files, no `tests/`/`spec/` directory, no `.github/workflows/` in `dot-claude`) — manual `printf JSON | bash script` + `bash -n` validation, matching PRs `#151`, `#239`, `#324`, is the correct and sufficient validation method for Phase 4.
- The `$(...)`-in-`VAR=` shape already forces a manual approval prompt in Claude Code today regardless of any allow-list rule (an independent security layer, cited to `anthropics/claude-code#31373` per `RUBY-COMMAND-EXECUTION.md:25-28`) — so the new block in Phase 1 converts an already-mandatory prompt into a block-and-redirect cycle, it does not introduce a new prompt where none existed.
- Issues `#23983` and `#34692` (verified via WebFetch, 2026-07-01) are read as the best-supported external evidence on subagent hook coverage; issues `#40580` and `#26923` remain UNVERIFIED per Citation Discipline and do not sustain any conclusion on their own — the Phase 5 live test is the mechanism that actually resolves the question for this plan, not further reading of these issues.
- The internal citation discrepancy between `agent-pipe-chaining/SPIKE.md:89` and the current `llm-agent-command-chaining/SPIKE.md` (documented in `subagent_hook_scope_1.txt`) is not relied upon by this plan and does not block any phase.
