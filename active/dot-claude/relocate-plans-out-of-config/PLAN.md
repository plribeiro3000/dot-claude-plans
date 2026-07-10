# PLAN — Relocate Plans Repository Out of `~/.claude/`

> Reference: derived from `PLAN-SPIKE.md` and its three auxiliary files (`plans-relocation_file-inventory_1.md`, `plans-relocation_mirror-patterns_1.md`, `plans-relocation_autocommit-scripts_1.md`) in this directory.

## Objective

Every write to a plans document (`PLAN.md`, `TASKS.md`, `SPIKE.md`, the DDD docs) currently triggers Claude Code's "editing its own settings" confirmation prompt, because the personal plans repository lives at `~/.claude/plans/` — inside the directory Claude Code's sensitive-file gate protects unconditionally, ahead of hooks and `permissions.allow` rules (confirmed by two open upstream bugs: [#66525](https://github.com/anthropics/claude-code/issues/66525), [#41615](https://github.com/anthropics/claude-code/issues/41615)). This plan relocates the plans repository to `~/Projects/4Shark/dot-claude-plans/` — a path with no `.claude` segment, which escapes the gate entirely — as a global, cross-project personal "planning brain" (deliberately not project-local). The relocation is delivered as a single PR to the dot-claude working copy, repointing every live functional reference and every prose convention reference in the ~33-file inventory, paired with a guided per-machine migration mirroring the existing `migrate-ssh-keys` pattern (`scripts/check-ssh-keys.sh` + `skills/migrate-ssh-keys/SKILL.md`).

## Scope

### In scope

- Repointing every LIVE functional path (scripts, hooks, glob patterns) from `~/.claude/plans` to `~/Projects/4Shark/dot-claude-plans`
- Repointing every PROSE convention reference (agents, commands, skill, CLAUDE.md, README.md) to the new path
- A new SessionStart detection hook, `scripts/check-plans-location.sh`, mirroring `scripts/check-ssh-keys.sh:1-103`
- A new guided migration skill, `skills/migrate-plans-location/SKILL.md`, mirroring `skills/migrate-ssh-keys/SKILL.md:1-65`
- Changing the autocommit scheduler's behavior from "commit only, never push" to "commit + push", and repointing its three scripts to the new location
- Removing the two now-fully-dead mitigation attempts this relocation supersedes (`scripts/auto-approve-claude-dir-writes.sh` and the plans-specific carve-out in `scripts/validate-bash-command.sh`)
- Engineer-facing documentation of the migration: a new runbook, the runbooks INDEX entry, README updates, CHANGELOG entry, and CLAUDE.md prose updates (including the autocommit push-behavior change)
- Post-implementation verification that no live/prose reference to the old path remains

### Out of scope

- Rewriting the 6 historical `CITATION` paths inside ADRs/docs that point at specific already-completed spike/plan folders (`docs/WORKTREE-POLICY.md:92`, `docs/adr/ADR-001-rules-loading-mechanism.md:114-115`, `docs/adr/ADR-003-policy-verifier.md:85-86`, `docs/adr/ADR-004-code-write-policy-enforcement.md:87-88`, `docs/DEPLOYMENT-STRATEGY.md:196`, `docs/runbooks/terraform-operations/AMI-VERSION-UPGRADE.md:158`) — engineer decision: leave as-is, add one explanatory note in the new runbook instead (see Technical Decisions, Decision D)
- The two already-executed migration scripts (`scripts/migrations/20251128200000_create_active_completed_dirs.sh`, `scripts/migrations/20251128200001_rename_project_dirs.sh`) — never edited, per the standing migration-history convention (`plans-relocation_file-inventory_1.md` § Scripts, and `plans-relocation_mirror-patterns_1.md` § 3)
- `CHANGELOG.md:429-431` — historical entry establishing the original `~/.claude/plans/` convention, never rewritten per Changelog Policy
- A compatibility symlink at the old location — engineer decision: none (see Technical Decisions, Decision C)
- A fallback dual-path shim for the transition window — engineer decision: clean cutover instead (see Technical Decisions, Decision A)
- Coordinated, synchronized team-wide cutover — engineer decision: asynchronous auto-update rollout instead (see Technical Decisions, Decision F)
- A pull step in the autocommit scheduler — single-machine backup only; multi-machine sync is a possible future evolution, not in scope now

## Chosen approach

**Direction:** clean cutover to `~/Projects/4Shark/dot-claude-plans/`, delivered as a single PR, with a SessionStart detection hook + guided migration skill mirroring the `migrate-ssh-keys` pattern, and no compatibility symlink.

**Rationale (from engineer):** the new location is deliberately global and cross-project (not project-local) because 4Shark keeps a cross-project "planning brain" distinct from the community's project-local trend; the path has no `.claude` segment, so it escapes the sensitive-file gate structurally rather than through another hook attempt. A clean cutover was chosen because agent `.md` prose files cannot conditionally resolve a path at runtime — they hardcode one path, so partial dual-path support is structurally impossible for that category regardless of what the scripts do (`PLAN-SPIKE.md` § Sub-decision A, Option A1). The migration mechanism mirrors `migrate-ssh-keys` because it is the closest existing 4Shark precedent for a stateful, confirmed, per-step migration, rather than the unattended `scripts/migrate.sh` mechanism, which is built for idempotent, harmless filesystem operations and not for a cross-repo relocation with a possible destination-content collision (`plans-relocation_mirror-patterns_1.md` § 3). No compatibility symlink was chosen because writing through a symlink at `~/.claude/plans/PLAN.md` still presents the tool call with a `file_path` starting `~/.claude/` — the sensitive-file gate matches on the presented path, not the resolved target, so a symlink would silently re-trigger the exact bug this feature exists to remove (`PLAN-SPIKE.md` § Sub-decision C, Option C1).

**Source patterns referenced:**
- `scripts/check-ssh-keys.sh:1-103` — SessionStart detection hook pattern
- `skills/migrate-ssh-keys/SKILL.md:1-65` — guided migration skill pattern
- `settings.json:36` — SessionStart hook wiring precedent
- `scripts/check-plans-autocommit.sh:37-41` — existing silent-degrade-on-bad-remote precedent, reused as evidence for the clean-cutover transition behavior

## Execution phases

### Phase 1: Worktree and branch setup

**Objective:** establish an isolated working environment for the change, per the standing Worktree Policy.

**Components:**
- New worktree under `~/Projects/4Shark/dot-claude/.claude/worktrees/<name>` on a `feature/*` branch cut from `develop`

**Dependencies:** none

**Success criteria:**
- [ ] Worktree created and checked out on a new feature branch

### Phase 2: Repoint LIVE functional paths

**Objective:** update every script, hook, and glob pattern that resolves the plans directory at runtime, so functional behavior follows the new location.

**Components:**
- `scripts/plans-autocommit.sh:32` — `PLANS_DIR="${HOME}/.claude/plans"` → `${HOME}/Projects/4Shark/dot-claude-plans` (single-constant change; every other line in the script derives from `PLANS_DIR`, per `plans-relocation_autocommit-scripts_1.md` § `plans-autocommit.sh`)
- `scripts/check-plans-autocommit.sh:26-27` — same `PLANS_DIR` repoint
- `scripts/setup-plans-autocommit.sh:128` — `plans_dir="${HOME}/.claude/plans"` repoint (the `.gitignore` self-heal block for `.autocommit.log`); `setup-plans-autocommit.sh:23` (`COMMIT_SCRIPT`) does NOT need to change — it points at the script's own location in `~/.claude/scripts/`, which is unaffected (`plans-relocation_autocommit-scripts_1.md` § `setup-plans-autocommit.sh`)
- `docs/LANGUAGE-POLICY.md:176` — the LIVE glob `~/.claude/plans/{active,completed}/**/*.md` that the language-policy verifier evaluates paths against, repointed to the new location; `docs/LANGUAGE-POLICY.md:3` (prose) also repointed. `docs/LANGUAGE-POLICY.md:58` is an illustrative citation-format example, not one of the 6 named historical citations in scope for Decision D — left as-is alongside those, since it demonstrates citation syntax rather than pointing at a live convention (`plans-relocation_file-inventory_1.md` § Docs)
- `scripts/validate-bash-command.sh` — see Phase 6 (dead-code removal); its plans-carve-out is removed, not repointed
- `tests/cases/validate-bash-command.cases.sh:60` — the test fixture asserting the old-path carve-out is auto-approved; removed alongside the carve-out (see Phase 6)

**Dependencies:** Phase 1

**Success criteria:**
- [ ] All 4 LIVE scripts and the 1 LIVE glob repointed to `~/Projects/4Shark/dot-claude-plans`
- [ ] No LIVE functional path still resolves against `~/.claude/plans`

### Phase 3: Repoint PROSE convention references

**Objective:** update every documentation and agent-prompt reference so every future session's mental model, and every agent's write location, follows the new convention.

**Components:**
- 8 agent files: `agents/knowledge-cruncher.md:67-68`, `agents/spike.md:60`, `agents/task-researcher.md:15,17`, `agents/process-modeler.md:18-19`, `agents/orchestrator.md:88,92,106,129,400`, `agents/plan-researcher.md:26,79-80`, `agents/context-mapper.md:16-17`, `agents/pr-review.md:119`
- 2 command files: `commands/execute.md:10,19,22-24,27-29`, `commands/cleanup-memories.md` (extensive — the skill's entire run-folder convention lives under the plans path; largest single-file edit in the set, per `plans-relocation_file-inventory_1.md` § Commands)
- 1 skill file: `skills/post-mortem/SKILL.md:119`
- 2 injected-reminder scripts (prose text, not functional path resolution): `scripts/read-context.sh:171`, `scripts/inject-output-policy-reminder.sh:35`
- `CLAUDE.md` — every plans-path reference (§ Plans Repository Auto-Commit, § Repository Structure, § Plans Storage - Filesystem-Based, § Security, and any other occurrence the inventory flags), repointed
- `README.md` — all prose occurrences and the migration-script code example repointed

**Dependencies:** Phase 1

**Success criteria:**
- [ ] All 20 PROSE files repointed to `~/Projects/4Shark/dot-claude-plans`
- [ ] `CLAUDE.md`'s "Plans Storage - Filesystem-Based" tree and "Repository Structure" tree reflect the new location

### Phase 4: New SessionStart detection hook

**Objective:** detect an un-migrated engineer at every session start and proactively offer the migration skill, mirroring `scripts/check-ssh-keys.sh`.

**Components:**
- `scripts/check-plans-location.sh` (new) — silent when `~/.claude/plans/` no longer exists as a real (un-migrated) directory; when it still exists, prints a warning block plus an `AGENT:` directive to proactively offer the `migrate-plans-location` skill, never migrating or deleting anything without the engineer's explicit OK — same shape as `scripts/check-ssh-keys.sh:97-101` (`plans-relocation_mirror-patterns_1.md` § 1)
- `settings.json` — wire the new hook into SessionStart, `"matcher": "*"`, alongside the existing session-start checks (mirrors `settings.json:36`)

**Dependencies:** Phase 2, Phase 3 (the hook's nag text refers to the new convention those phases establish)

**Success criteria:**
- [ ] `scripts/check-plans-location.sh` exits silently when `~/Projects/4Shark/dot-claude-plans/` is the live plans repo and `~/.claude/plans/` is gone or already-migrated
- [ ] The hook prints the warning + `AGENT:` directive when `~/.claude/plans/` still exists as a real, un-migrated directory
- [ ] Hook wired into `settings.json` SessionStart

### Phase 5: New guided migration skill

**Objective:** perform the one-time, per-machine, merge-safe move from `~/.claude/plans/` to `~/Projects/4Shark/dot-claude-plans/`, mirroring `skills/migrate-ssh-keys/SKILL.md`.

**Components:**
- `skills/migrate-plans-location/SKILL.md` (new) — numbered, per-step-confirmed flow: detect → back up → merge-safe move → verify → reinstall the autocommit scheduler at the new path → retire the old directory only on explicit engineer confirmation (mirrors the "retire the backup" step at `skills/migrate-ssh-keys/SKILL.md:62-64`)
- **Non-destructive merge**: the skill unions the old `~/.claude/plans/` content into `~/Projects/4Shark/dot-claude-plans/`; the migration MUST be merge-safe rather than move-if-empty, because the cutover race (Phase 4's hook is advisory, not blocking) means the engineer may already have written new plans to the new location before running the skill (`PLAN-SPIKE.md` § Sub-decision A, Option A1's central risk; § Risks table)
- On a same-named-file collision during the merge: keep both files (suffix one), report the collision to the engineer explicitly — never clobber, never silently drop
- The moved repo's `.git` directory and history are preserved through the merge
- After the merge, the skill reinstalls the per-OS autocommit scheduler at the new path by re-running `scripts/setup-plans-autocommit.sh` (idempotent reinstall — the existing install logic already overwrites its own prior registration via `bootout`-then-`bootstrap` / `systemctl --user enable --now` / `schtasks.exe .../f`, per `plans-relocation_autocommit-scripts_1.md` § `setup-plans-autocommit.sh`)
- The old `~/.claude/plans/` directory is retired (renamed/retained as an inert backup) only after successful, verified migration, and only with explicit engineer confirmation to remove — never auto-deleted, mirroring the SSH-key precedent (`skills/migrate-ssh-keys/SKILL.md:62-64`)
- No compatibility symlink is left at the old location (Technical Decisions, Decision C)

**Dependencies:** Phase 4 (the skill is what the detection hook offers)

**Success criteria:**
- [ ] `skills/migrate-plans-location/SKILL.md` exists, follows the numbered-flow + non-negotiable-safety-rules shape of `migrate-ssh-keys/SKILL.md`
- [ ] A same-named-file collision during merge is reported to the engineer, never silently resolved
- [ ] The autocommit scheduler is reinstalled at the new path as part of the flow
- [ ] The old directory is retired only on explicit engineer confirmation

### Phase 6: Autocommit push-behavior change

**Objective:** change the autocommit scheduler from "commit only, never push" to "commit + push", for off-machine backup of the relocated, privately-remoted plans repo.

**Components:**
- `scripts/plans-autocommit.sh` — after the nightly commit, push to the remote (`git@github.com:<user>/dot-claude-plans.git`, confirmed private) for off-machine backup; no pull step (single-machine backup — nothing external mutates the repo, so push alone suffices; multi-machine sync is a possible future evolution, out of scope now)
- `scripts/setup-plans-autocommit.sh`, `scripts/check-plans-autocommit.sh` — repointed to the new location per Phase 2; no behavior change beyond the path repoint already covered there
- `CLAUDE.md` § Plans Repository Auto-Commit — updated from "Commit only, never push — history is preserved locally; pushing for off-machine backup stays a manual action" to reflect commit+push; `README.md` updated if it mirrors this prose

**Dependencies:** Phase 2 (path repoint), Phase 3 (prose repoint)

**Success criteria:**
- [ ] `scripts/plans-autocommit.sh` pushes after each successful commit
- [ ] No pull step is present
- [ ] `CLAUDE.md` and README (if applicable) prose reflect commit+push

### Phase 7: Dead-code removal

**Objective:** remove the two mitigation attempts this relocation makes fully dead — both are proven ineffective against the sensitive-file gate (the very prompt this feature removes), and post-relocation their target paths are never written.

**Components:**
- `scripts/auto-approve-claude-dir-writes.sh` — removed in full, along with its `settings.json:249` PreToolUse wiring
- `tests/cases/auto-approve-claude-dir-writes.cases.sh` — removed (exercises the removed hook)
- `scripts/validate-bash-command.sh` — the plans-specific carve-out removed (`plans_prefix="$HOME/.claude/plans/"` at line 95, the `Edit|Write|MultiEdit` case arm at lines 109-116, the Bash-write case arm at lines 580-584, per `plans-relocation_mirror-patterns_1.md` § 2)
- `tests/cases/validate-bash-command.cases.sh:60` (`"write under plans allows"`) — removed alongside the carve-out it exercises

**Dependencies:** Phase 2 (the new path is confirmed live before the old carve-out is removed)

**Success criteria:**
- [ ] `scripts/auto-approve-claude-dir-writes.sh` and its settings.json wiring no longer exist
- [ ] The `validate-bash-command.sh` plans-carve-out no longer exists
- [ ] Both associated test fixtures removed; remaining test suite passes

### Phase 8: Documentation

**Objective:** document the migration for engineers and preserve the historical record accurately.

**Components:**
- New runbook: `docs/runbooks/engineer-access/PLANS-RELOCATION.md`, mirroring `docs/runbooks/engineer-access/SSH-KEY-HYGIENE.md`'s family; includes one explanatory note that pre-relocation `CITATION` paths in ADRs/docs reference the old `~/.claude/plans` location (Technical Decisions, Decision D)
- `docs/runbooks/INDEX.md` — new entry pointing to `PLANS-RELOCATION.md`
- `CHANGELOG.md` — new entry under `## [Unreleased]` (this is a feature branch; no dated version section is created, per Changelog Policy)
- `CLAUDE.md` and `README.md` prose updates from Phase 3 and Phase 6 land here as part of the same documentation pass

**Dependencies:** Phase 2–7 (documentation describes the completed mechanism)

**Success criteria:**
- [ ] `docs/runbooks/engineer-access/PLANS-RELOCATION.md` exists and is indexed
- [ ] `CHANGELOG.md` has an `## [Unreleased]` entry for this change
- [ ] The 6 historical CITATION paths remain untouched, with the explanatory note present in the new runbook

### Phase 9: Verification

**Objective:** confirm no live or prose reference to the old path remains before opening the PR.

**Components:**
- Re-run `grep -rln "claude/plans"` over `~/Projects/4Shark/dot-claude/` — the same deliberately broad pattern used for the original research (matches both `~/.claude/plans` and any `.claude/plans` without a leading tilde)
- Expect zero LIVE/PROSE hits remaining, except the intentionally-preserved historical CITATION rows (the 6 named files) and the historical `CHANGELOG.md:429-431` entry

**Dependencies:** Phase 2–8

**Success criteria:**
- [ ] Verification grep returns only the intentionally-preserved CITATION and historical-changelog hits
- [ ] No 34th, previously-uncaught reference surfaces

### Phase 10: Pull request

**Objective:** deliver the full change as one reviewable unit.

**Components:**
- Single PR containing: the path repoint (LIVE + PROSE), the new detection hook, the new migration skill, the autocommit push-behavior change, the dead-code removal, and the documentation updates — delivered as one reviewable unit (Technical Decisions, Decision E). The plan stops when the PR is open; the merge is the engineer's decision, outside this plan's scope (Git Safety)

**Dependencies:** Phase 1–9

**Success criteria:**
- [ ] PR opened against `develop`, containing the complete change described above
- [ ] PR title = the Angular-format commit message (feature-branch rule, Pull Request Policy); the `CHANGELOG.md` `## [Unreleased]` entry is a separate bare-subject line, not required to match the PR title

## Technical decisions

| Decision | Choice | Rationale (from engineer) |
|----------|--------|----------------------------|
| New location | `~/Projects/4Shark/dot-claude-plans/` — global, cross-project, not project-local | 4Shark deliberately keeps a cross-project "planning brain," distinct from the community's project-local trend; the path has no `.claude` segment, escaping the sensitive-file gate structurally |
| Scope of repoint | Rewrite every LIVE functional reference and every PROSE convention reference across the ~33-file inventory; `~/.claude/plans` ceases to exist and nothing references it after the PR | There is no Claude Code harness coupling to `~/.claude/plans` — it is a pure 4Shark convention (confirmed, `plans-relocation_mirror-patterns_1.md` § 5); agents cannot conditionally resolve a path, so they hardcode the new one |
| Migration mechanism | SessionStart detection hook (`scripts/check-plans-location.sh`) + guided migration skill (`skills/migrate-plans-location/SKILL.md`), mirroring `migrate-ssh-keys` | Closest existing 4Shark precedent for a stateful, per-step-confirmed migration; `scripts/migrate.sh` is built for idempotent, harmless filesystem operations, not a cross-repo relocation with a possible destination-content collision |
| **A — Transition-window safety** | Clean cutover (A1): hardcode the new path everywhere; rely on the detection hook to force migration at first session | Agent `.md` prose files cannot conditionally resolve a path at runtime — partial dual-path support is structurally impossible for that category regardless of what scripts do, so a fallback shim (A2) would only protect a smaller slice of the problem while adding real shim-maintenance cost |
| **B — Merge strategy when target already has content** | Non-destructive merge: union old content into the new location; on a same-named-file collision, keep both (suffix one) and report to the engineer; preserve `.git` and history | The cutover race means the engineer may already have written new plans to the new location before running the migration skill — the skill must be merge-safe, not move-if-empty, and must never clobber or silently drop data |
| **C — Compatibility symlink** | None (C2) | Writing through `~/.claude/plans/PLAN.md` (even as a symlink) still presents a `file_path` starting `~/.claude/` — the sensitive-file gate matches the presented path, not the resolved target, so a symlink would silently re-trigger the exact bug this feature removes |
| **D — Historical citation paths** | Leave the 6 CITATION paths as-is; add one explanatory note in the new runbook | These files describe already-completed research; rewriting them edits historical record for paths whose accuracy is independent of this relocation. One sentence in the runbook prevents future confusion without touching 6 files |
| **E — PR structuring** | Single PR (repoint + hook + skill + autocommit change + dead-code cleanup + docs together) | The change is atomic — no intermediate state exists where the convention prose says one thing and the enforcement mechanism says another; one changelog entry, one review pass, the full picture reviewed together |
| **F — Rollout ordering** | Asynchronous, auto-update-driven (F1) | Each engineer's plans repo is an independent per-machine fork with no shared state requiring coordination; reuses the exact auto-update (`check-claude-version.sh`) + detection-hook machinery already proven for SSH key hygiene |
| **Carve-out cleanup** | Remove `scripts/auto-approve-claude-dir-writes.sh` and the `validate-bash-command.sh` plans-carve-out entirely | Both are proven ineffective against the sensitive-file gate (the reason this feature exists); post-relocation their target paths are never written — removing genuinely dead code is a Kaizen-shaped cleanup the diff itself reveals |
| Naming | Hook: `scripts/check-plans-location.sh`; skill: `migrate-plans-location` | Engineer-confirmed names |
| Runbook home | `docs/runbooks/engineer-access/PLANS-RELOCATION.md`, added to the runbooks INDEX | Mirrors `SSH-KEY-HYGIENE.md`'s engineer-access family — the closest existing precedent |
| Autocommit behavior | Change from commit-only to commit + push, no pull step | Off-machine backup for a single-machine repo with a confirmed-private remote; nothing external mutates the repo, so push alone suffices. Multi-machine sync (which would need a pull step) is a possible future evolution, not in scope now |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Cutover race: an agent writes a new `PLAN-SPIKE.md`/`SPIKE.md`/etc. to the new (empty) path before the engineer runs the migration skill, while prior planning history sits unseen at the old path | Discoverability loss (not data loss) — a session appears to have no history for an in-progress feature until migration runs | The merge-safe migration skill (Decision B) unions content regardless of how much has already landed at the new path; the detection hook nags proactively at every session start until migrated, not just once |
| A missed 34th reference — a variant spelling (`.claude/plans` without the leading `~`) not caught by the inventory grep | A stale reference silently keeps working against the old (or, post-migration, nonexistent) path, producing either the original sensitive-file prompt or a broken-path failure | Phase 9: re-run the same broad `grep -rln "claude/plans"` as a post-implementation verification step before the PR is opened |
| Per-machine, per-fork migration cannot be pushed centrally — an engineer who never sees or acts on the nag stays on the broken path indefinitely | The nag is advisory only; SessionStart hooks in this codebase never block | This mirrors the exact same residual, accepted gap for SSH key hygiene (`check-ssh-keys.sh` also only nags, never forces) — a documented, accepted category of gap in this codebase's hook design, not a new risk class |
| Dead-code removal (Phase 7) touches code outside the pure "add a mechanism" scope | Slightly larger diff | Justified as Kaizen per Scope Discipline — the code is provably dead for its stated purpose the moment the relocation lands, and the diff itself reveals it |

## Assumptions

- `~/Projects/4Shark/dot-claude/` (working copy) exists and is where this change is made — confirmed by directory listing
- `~/.claude/plans` is its own git repo (`git@github.com:plribeiro3000/dot-claude-plans.git`, branch `main`), per-engineer, confirmed by `scripts/plans-autocommit.sh` comments
- `~/Projects/4Shark/dot-claude-plans/` does not exist yet — the target is free (confirmed: no sibling `dot-claude-plans` directory listed at `~/Projects/4Shark/` during research)
- `settings.json:401` already lists `~/Projects` in `additionalDirectories` — no `settings.json` permission change is needed for file-system access to the new location
- No Claude Code harness-level (built-in) coupling to `~/.claude/plans` exists — every reference to the sensitive-file gate in the codebase describes it as a generic `~/.claude/*` protection, never `plans/`-specific; relocation does not fight anything the harness itself expects
- The engineer's remote for the relocated plans repo is confirmed private, making auto-push of `PLAN`/`SPIKE` docs acceptable
- Single-machine backup is the current requirement; multi-machine sync (which would need a pull step) is explicitly deferred, not designed for in this plan

## Validation / acceptance

- [ ] Verification grep (Phase 9) confirms zero unintended LIVE/PROSE hits for `claude/plans` remaining in `~/Projects/4Shark/dot-claude/`
- [ ] `scripts/check-plans-location.sh` and `skills/migrate-plans-location/SKILL.md` exist, are wired correctly, and follow the `migrate-ssh-keys` mirror shape
- [ ] `scripts/plans-autocommit.sh` pushes after commit, with no pull step
- [ ] `scripts/auto-approve-claude-dir-writes.sh`, its settings.json wiring, the `validate-bash-command.sh` plans-carve-out, and both associated test fixtures are removed
- [ ] `docs/runbooks/engineer-access/PLANS-RELOCATION.md` exists, is indexed, and carries the historical-citation note
- [ ] `CHANGELOG.md` has an `## [Unreleased]` entry (bare subject); the PR title is the Angular-format commit message, per the feature-branch Pull Request Policy (the two are not required to match)
- [ ] The 6 historical CITATION paths remain unmodified
- [ ] Full test suite passes after the dead-code removal
- [ ] PR opened against `develop` as a single unit (Decision E)
