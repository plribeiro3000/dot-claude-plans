# PLAN-SPIKE — Relocate Plans Repository Out of `~/.claude/`

> Auxiliary files: `plans-relocation_file-inventory_1.md` (full 33-file categorized inventory), `plans-relocation_mirror-patterns_1.md` (ssh-keys mirror pattern, two existing failed mitigation hooks, the `migrate.sh` alternate mechanism, `additionalDirectories` finding), `plans-relocation_autocommit-scripts_1.md` (autocommit scheduler repoint detail).

## Objective

Every write to a plans document (`PLAN.md`, `TASKS.md`, `SPIKE.md`, the DDD docs) currently triggers Claude Code's "editing its own settings" confirmation prompt, because the personal plans repository lives at `~/.claude/plans/` — inside the directory Claude Code's sensitive-file gate protects unconditionally, ahead of hooks and `permissions.allow` rules (confirmed by two open upstream bugs: [#66525](https://github.com/anthropics/claude-code/issues/66525), [#41615](https://github.com/anthropics/claude-code/issues/41615)). The engineer has already decided the fix: relocate the plans repository to `~/Projects/4Shark/dot-claude-plans/` (a path with no `.claude` segment, escaping the gate entirely), using a SessionStart-detection-hook + guided-migration-skill mechanism mirroring the existing `migrate-ssh-keys` pattern, delivered through the normal dot-claude PR workflow. This document surfaces the remaining open sub-decisions (transition-window safety, merge behavior, symlink question, documentation home, PR structuring, rollout ordering) as options with trade-offs for engineer review before `plan-composer` writes the canonical `PLAN.md`.

## Scope

### In scope

- Repointing every LIVE functional path (scripts, hooks, glob patterns) from `~/.claude/plans` to `~/Projects/4Shark/dot-claude-plans`
- Repointing every PROSE convention reference (agents, commands, skill, CLAUDE.md, README.md) to the new path
- A new SessionStart detection hook (`scripts/check-plans-location.sh`) mirroring `scripts/check-ssh-keys.sh`
- A new guided migration skill (`skills/migrate-plans-location/SKILL.md`) mirroring `skills/migrate-ssh-keys/SKILL.md`
- Engineer-facing documentation of the migration (runbook + README + CHANGELOG + CLAUDE.md prose)
- Reinstalling the per-OS autocommit scheduler at the new path (each engineer, per-machine)

### Out of scope (open question)

- Whether to rewrite the 6 historical `CITATION` paths inside ADRs/docs that point at specific already-completed spike/plan folders (`WORKTREE-POLICY.md:92`, `ADR-001:114-115`, `ADR-003:85-86`, `ADR-004:87-88`, `DEPLOYMENT-STRATEGY.md:196`, `AMI-VERSION-UPGRADE.md:158`) — see Technical Decision D
- Whether to remove, repoint, or leave as dead code the `validate-bash-command.sh` plans-specific carve-out (lines 95, 109-116, 580-584) that becomes non-functional-for-its-original-purpose once the new path is outside `~/.claude/` — see Technical Decision (below, "carve-out cleanup")
- The two already-executed migration scripts (`20251128200000_...`, `20251128200001_...`) — never edited, per standing migration-history convention (see `plans-relocation_file-inventory_1.md`)
- `CHANGELOG.md:429-431` — historical entry, never rewritten per Changelog Policy

## Ground truth already established (not re-researched, cited for completeness)

- `~/Projects/4Shark/dot-claude/` (working copy) exists and is where this change will be made — confirmed by directory listing.
- `~/.claude/plans` is its own git repo (`git@github.com:plribeiro3000/dot-claude-plans.git`, branch `main`), per-engineer, confirmed by `scripts/plans-autocommit.sh` comments (`plans-relocation_autocommit-scripts_1.md`).
- `~/Projects/4Shark/dot-claude-plans/` does not exist yet — target is free (confirmed: `ls ~/Projects/4Shark/dot-claude/` output during this research did not list a sibling `dot-claude-plans` directory at `~/Projects/4Shark/`).
- **New finding**: `settings.json:401` already lists `~/Projects` in `additionalDirectories` — no `settings.json` permission change is needed for file-system access to the new location (`plans-relocation_mirror-patterns_1.md` § 4).
- **New finding**: two hooks already attempt this exact fix and are already shipped (`auto-approve-claude-dir-writes.sh`, shipped `[0.8.0] - 2026-07-07`, and `validate-bash-command.sh`'s narrower plans-carve-out). Per the engineer's diagnosis, both are ineffective against the sensitive-file gate specifically — full detail in `plans-relocation_mirror-patterns_1.md` § 2.
- **New finding**: no Claude Code harness-level (built-in) coupling to `~/.claude/plans` was found — every reference to the sensitive-file gate in the codebase describes it as a generic `~/.claude/*` protection, never `plans/`-specific. Relocation does not fight anything the harness itself expects (`plans-relocation_mirror-patterns_1.md` § 5).
- **New finding**: a second, different auto-migration mechanism already exists in this codebase (`scripts/migrate.sh` + `scripts/migrations/*.sh`, unattended, SessionStart-triggered, idempotency-tracked via `.migrations_executed`) — a candidate alternative to the chosen guided-skill pattern, but built for harmless-to-retry filesystem operations, not a cross-repo relocation with a possible content collision at the destination (`plans-relocation_mirror-patterns_1.md` § 3).
- File inventory: 33 files reference `claude/plans`, distributed scripts 9 / agents 8 / docs 7 / tests 3 / root 3 / commands 2 / skills 1 — grep-confirmed, full breakdown in `plans-relocation_file-inventory_1.md`.

## Mirror pattern to follow (Pattern Priming)

**Pattern 1: SessionStart detection hook** — `scripts/check-ssh-keys.sh:1-103`

**What it does:** counts violations of a 4Shark convention (extra SSH private keys on disk) at every session start, stays silent when compliant, and prints a directive block telling the agent to proactively offer the remediation skill when it is not.

```bash
# Zero or one private key on disk is the target state — nothing to flag.
[[ "${key_count}" -le 1 ]] && exit 0
...
echo "This session can fix it: the 'migrate-ssh-keys' skill moves the keys into 1Password ..."
echo ""
echo "AGENT: proactively offer to run the migrate-ssh-keys skill. Do not migrate or delete anything without the engineer's explicit OK."
exit 0
```

**Pattern 2: guided migration skill** — `skills/migrate-ssh-keys/SKILL.md:1-65`

**What it does:** performs a stateful, irreversible-risk migration through an explicit, numbered, per-step-confirmed flow — never a silent blanket action.

```markdown
## Non-negotiable safety rules

1. **Back up first.** Copy every key you will touch into a timestamped backup dir before changing anything. Never proceed without the backup.
2. **Never delete ... until BOTH pass:** (a) ... AND (b) .... If either fails, STOP, restore, and leave the key on disk.
3. **One key at a time.** Migrate, verify, and confirm each key with the engineer before touching the next.
...
```

Full excerpts and the wiring detail (`settings.json:36` SessionStart registration) are in `plans-relocation_mirror-patterns_1.md` § 1.

**Pattern not found for "cross-repo directory relocation with destination-collision handling" in this project** — the closest prior art (`scripts/migrate.sh`) is built for idempotent, harmless filesystem operations, not a git-repo-to-git-repo move where the destination might already hold content. No 4Shark project was found with a pattern for this specific shape (move a git-tracked, remote-backed personal directory to a new parent while merging possible pre-existing content). Possible references in other tooling ecosystems: `git subtree`/`git filter-repo` migration guides, or a plain `rsync -a --ignore-existing` + manual `git` re-point — none of these are 4Shark-established patterns, so any choice here is a genuinely new decision for the engineer, not a codebase-precedent lookup.

## Candidate approaches — PR structuring (Technical Decision E)

### Option A: Single PR (repoint + mechanism + docs together)

**Approach summary:** one feature branch, one PR, containing the full path repoint (all ~25 LIVE + PROSE files), the new detection hook, the new migration skill, and the documentation updates (runbook + README + CHANGELOG + CLAUDE.md prose), reviewed and merged as one unit.

**Pros:** the change is atomic — there is no intermediate state where the convention prose says one thing and the enforcement mechanism says another; one changelog entry; one review pass; the engineer reviews the full picture (path change + safety net + docs) together, which matters because the docs explain WHY the mechanism exists.

**Cons:** larger diff to review in one sitting (~25+ file changes plus 2 new files); if the reviewer wants to approve the path repoint but iterate further on the migration-skill wording, those are coupled in one PR.

**Cost / effort:** single branch lifecycle, single CI/verification pass.

**Risk:** low-to-moderate — a large diff is harder to review carefully in one pass (more surface for a missed repoint to slip through), but every file in scope is mechanically discoverable via the same `grep -rln "claude/plans"` used for this research, so a missed file is self-evident on a second pass.

**Source patterns referenced:**
- `plans-relocation_file-inventory_1.md` — the full 33-file breakdown that would land in one diff

### Option B: Split PRs (mechanism first, then repoint + docs; or repoint first, then mechanism)

**Approach summary:** two (or three) sequential PRs — e.g. PR1 ships the detection hook + migration skill (inert until wired to a path that doesn't yet need migrating), PR2 repoints every LIVE/PROSE reference and updates docs, merged once PR1 is validated.

**Pros:** smaller individual diffs, each independently reviewable; the migration mechanism itself (hook + skill code shape) can be validated/tested in isolation before the path-repoint PR makes it load-bearing; a revert of the repoint PR (if something breaks) does not also revert the mechanism.

**Cons:** an intermediate merged state exists where the mechanism references paths that are not yet the live convention (or vice versa) — care is needed so the sequencing does not itself create a broken window; two changelog entries or one deferred to the second PR; more overall process overhead (two review cycles) for a change that is conceptually one unit of work.

**Cost / effort:** two branch lifecycles, two review passes, coordination on merge order.

**Risk:** low — but the intermediate-state risk is a new risk category Option A does not have; mitigated only by care in what each PR's hook/skill hardcodes (e.g. PR1's skill could take the target path as a documented convention it will read from a not-yet-existing new CLAUDE.md section, deferring load until PR2 lands).

**Source patterns referenced:**
- `plans-relocation_mirror-patterns_1.md` § 1 — the `migrate-ssh-keys` skill and its detection hook were introduced together in the same historical change (per `CHANGELOG.md:21`, "SSH key hygiene rule, runbook, session-start check, and guided migration skill" — one bullet, suggesting they shipped as one unit previously)

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| **A — Transition-window safety** (see full write-up below) | (i) Clean cutover — hardcode new path everywhere, rely on the detection hook to force migration at first session; (ii) fallback shim — scripts tolerate either path existing during a window | (i) is simpler and matches the fact that agents (`.md` prose) cannot call a path resolver at all, so partial support is impossible for that category regardless; (ii) adds real complexity only for the 5-6 LIVE script paths, but those are exactly the paths where a stale reference silently breaks the autocommit scheduler with no error surfaced to the engineer | ☐ |
| **B — Merge strategy when target already has content** | (i) Refuse and ask the engineer to resolve manually if `~/Projects/4Shark/dot-claude-plans/` is non-empty; (ii) merge automatically (e.g. `rsync -a --ignore-existing` or `git`-level merge of two histories) | (i) is safer (never silently drops data) but requires the engineer to intervene in the one scenario most likely to be rare (fresh clone target); (ii) is more convenient but requires deciding a conflict-resolution rule (which side wins on a same-named file) — the migrate-ssh-keys precedent is "never destroy without both-pass verification," which argues for (i) as the closer mirror | ☐ |
| **C — Compatibility symlink** (see full write-up below) | (i) Leave `~/.claude/plans -> ~/Projects/4Shark/dot-claude-plans` symlink after migration; (ii) no symlink, old path simply stops resolving to anything after migration | (i) risks silently re-triggering the exact sensitive-file gate this whole feature exists to escape, for any tool/process that still writes through the old path; (ii) is a clean break but any lingering hardcoded reference (missed in the repoint, or in an engineer's personal muscle memory / shell alias) fails loudly instead of silently — which is arguably the safer failure mode here | ☐ |
| **D — Historical citation paths in docs** | (i) Rewrite the 6 CITATION paths in ADRs/docs to the new location; (ii) leave them as-is with an implicit "this predates the relocation" understanding; (iii) leave them as-is but add one explicit note (e.g. in the runbook) that pre-relocation citations use the old path | These files describe already-completed research (mostly moved to `completed/spike/` already per the Spike Lifecycle in CLAUDE.md), so rewriting them is editing historical record for paths that may not even be accurate post-lifecycle-move regardless of this relocation; (iii) costs one sentence and prevents future confusion without touching 6 files | ☐ |
| **F — Rollout ordering across engineers** (see full write-up below) | (i) Merge the PR and let auto-update + the detection hook handle each engineer's transition independently, asynchronously; (ii) coordinate a synchronized cutover (e.g. announce in a team channel, everyone runs the migration skill within a window) | (i) matches the fact that this is a per-machine, per-fork change with no shared-state coordination needed between engineers (confirmed ground truth: each engineer has their own plans fork) — auto-update (`check-claude-version.sh`) already delivers the same dot-claude version to everyone within ~24h regardless of coordination; (ii) adds process overhead for a change that has zero cross-engineer interaction surface | ☐ |
| **Carve-out cleanup** | (i) Remove the `validate-bash-command.sh` plans-specific carve-out (lines 95, 109-116, 580-584) since the new path is outside `~/.claude/` and the carve-out becomes unreachable for its stated purpose; (ii) repoint the carve-out's `plans_prefix` constant to the new path (harmless — it would just always miss, since new writes are never `~/.claude/plans/*`, but symmetric with every other repoint); (iii) leave untouched as a defensive no-op | (i) is the most honest (removes genuinely dead code — a Kaizen-shaped cleanup the diff itself would reveal per Scope Discipline) but touches code outside the pure "add a mechanism" scope; (ii)/(iii) are lower-effort but leave misleading comments claiming to solve a problem the code can no longer encounter | ☐ |

## Sub-decision A — Transition-window safety, full write-up

### Option A1: Clean cutover

**Approach summary:** every file in scope (LIVE scripts, PROSE agents/commands/docs) is repointed to `~/Projects/4Shark/dot-claude-plans` in the same PR. The new `check-plans-location.sh` SessionStart hook detects "physical directory not yet present at the new path" (or "old path still has un-migrated content") and surfaces the nudge + proactive-offer directive, mirroring `check-ssh-keys.sh:97-101`. Until the engineer runs the migration skill (or manually moves the directory), the autocommit scheduler and any live script pointed at the new `PLANS_DIR` will find nothing there and degrade the way `check-plans-autocommit.sh` already degrades when `git -C "${PLANS_DIR}" remote get-url origin` fails — silently, per `plans-relocation_autocommit-scripts_1.md` (a `case` falls through to `exit 0`).

**Pros:** matches the hard constraint that agent `.md` prose files cannot conditionally resolve a path at runtime — they hardcode one path, so "partial support for both paths" is structurally impossible for the 8 agent files and 2 command files regardless of what the scripts do. A clean cutover keeps every file category (scripts and prose) consistent with a single stated convention, avoiding a state where scripts tolerate the old path but agent prompts already assume the new one exists.

**Cons:** an engineer who has not yet run the migration (ignored the nag, or is mid-session when the dot-claude auto-update lands) will have `plan-researcher`/`spike`/etc. agents write PLAN-SPIKE.md and friends to the new (currently empty) path while their actual prior planning history sits unseen at the old path — the "cutover race" the engineer flagged as the central design concern. This is not a data-loss risk (nothing is deleted), but it IS a discoverability risk: the engineer's Claude session appears to have "no prior plans" for features that actually have history, until they run the migration skill and the two directories are merged.

**Cost / effort:** the repoint itself is mechanical (grep-discoverable, per file inventory); the "degrades silently" property already exists in `check-plans-autocommit.sh` without new code, but the NEW detection hook (`check-plans-location.sh`) and the merge-aware migration skill are net-new work regardless of which sub-option is picked here.

**Risk:** the "write to the new empty location while old plans sit unseen" scenario is exactly why the migration skill (whichever transition option is picked) MUST be merge-safe rather than a plain move-if-empty — see Technical Decision B. This is the load-bearing mitigation for A1's central risk, not an independent design axis.

**Source patterns referenced:**
- `plans-relocation_autocommit-scripts_1.md` — `check-plans-autocommit.sh:37-41` degrades silently on a missing/wrong remote, demonstrating the existing degrade-silently precedent this option leans on
- `plans-relocation_mirror-patterns_1.md` § 1 — `check-ssh-keys.sh:97-101` for the nag/proactive-offer directive shape

### Option A2: Fallback shim / dual-path tolerance

**Approach summary:** the 5-6 LIVE scripts (`plans-autocommit.sh`, `check-plans-autocommit.sh`, `setup-plans-autocommit.sh`, `validate-bash-command.sh`, the `LANGUAGE-POLICY.md` glob) are written to check the new path first, and fall back to the old `~/.claude/plans` path if the new one does not yet exist — so a not-yet-migrated engineer's autocommit scheduler and any script-level convention keep working against the old location until they migrate. Agent `.md` prose files still hardcode the new path only (no shim possible there, per the hard constraint above), so this option is necessarily partial — it only closes the gap for the LIVE script category, not for agent-authored writes.

**Pros:** removes the "autocommit silently stops finding anything" failure mode for the transition window specifically; an engineer who has not migrated yet keeps getting daily snapshots of their WORK AT THE OLD PATH during the window, rather than the scheduler quietly operating on an empty new directory.

**Cons:** because agents cannot participate in the shim (per the stated hard constraint — a `.md` prompt cannot call a resolver), the dual-path logic only protects the autocommit/glob category while the write-time category (agents writing PLAN-SPIKE.md, SPIKE.md, etc.) is STILL a clean cutover regardless — so this option does not actually eliminate the cutover-race scenario the engineer flagged, it only adds shim complexity to a smaller slice of the problem (autocommit staying pointed at stale data) without resolving the larger one (new agent writes landing at an empty new location). Added complexity: every shimmed script needs a documented, tested fallback-resolution order, and the fallback logic itself needs to be removed later (a second future cleanup PR) once migration is assumed universal — otherwise it becomes permanent dead-path-checking code.

**Cost / effort:** higher than A1 — new conditional path-resolution logic in 4+ scripts, each needing test coverage for both branches, plus a planned follow-up removal.

**Risk:** the shim logic itself is a new source of bugs (e.g. a script that resolves the new path as "exists" because `mkdir -p` created an empty directory somewhere upstream, then silently operates on nothing) — and because it does not solve the agent-write side of the race at all, it delivers partial risk reduction for real added complexity.

**Source patterns referenced:**
- `plans-relocation_file-inventory_1.md` — the "LIVE" vs "PROSE" categorization that makes explicit which files even a shim could apply to (only the 5-6 LIVE rows; none of the 20 PROSE rows)

## Sub-decision C — Compatibility symlink, full write-up

### Option C1: Leave a symlink `~/.claude/plans -> ~/Projects/4Shark/dot-claude-plans` after migration

**Approach summary:** after the directory content is moved, create a symlink at the old location pointing to the new one, so any stale reference (a missed repoint, an engineer's shell alias, muscle memory) continues to resolve.

**Pros:** backward-compatible for anything not caught by the repoint; zero-friction for an engineer who types the old path out of habit.

**Cons — and this is the reason the task briefing flags it as a likely footgun**: writing THROUGH a symlink at `~/.claude/plans/PLAN.md` still presents the tool call with a `file_path` that starts with `~/.claude/` — the sensitive-file gate matches on the presented path, not the resolved target (this is consistent with every hook comment cited in `plans-relocation_mirror-patterns_1.md` § 2, which describe the gate as matching on the literal path Claude Code's own permission prompt shows). A symlink at the old location does not just fail to help — it actively reintroduces the exact prompt this whole feature exists to eliminate, for the one narrow case (a missed repoint or muscle-memory reference) it was meant to smooth over. It also risks masking a missed repoint indefinitely: the reintroduced prompt is the ONLY signal that a stale reference exists; without the symlink, a stale reference to a now-nonexistent directory fails loudly (`No such file or directory`) and gets fixed; with the symlink, it fails by re-presenting the exact prompt this task removes, potentially without anyone connecting the prompt's return to the specific stale reference that caused it.

**Cost / effort:** one `ln -s` in the migration skill's final step; trivial to add.

**Risk:** the symlink is not a passive compatibility shim — it is an active re-trigger of the original bug for anything that resolves through it, which is a materially different risk profile than a normal "leave a compat symlink" pattern in other contexts.

**Source patterns referenced:**
- `plans-relocation_mirror-patterns_1.md` § 2 — every cited hook comment describes the sensitive-file gate as matching the presented/display path

### Option C2: No compatibility symlink

**Approach summary:** after migration, the old `~/.claude/plans/` path simply no longer exists (or is removed/renamed, e.g. to `~/.claude/plans.migrated-<date>/`, per the migrate-ssh-keys "retire the backup, only with explicit confirmation" precedent).

**Pros:** any stale reference (missed repoint, engineer habit) fails immediately and loudly with a filesystem error, which is a strictly cheaper failure to diagnose and fix than a silently-reintroduced permission prompt; does not reopen the bug this feature removes for any code path, ever.

**Cons:** an engineer's own muscle memory (`cd ~/.claude/plans`) breaks with no compatibility grace period; any missed repoint in the 33-file inventory surfaces as a broken path reference rather than working-but-wrong.

**Cost / effort:** none beyond the plain migration itself; optionally, retaining the old directory (renamed, not symlinked) as an inert backup for a grace period mirrors the migrate-ssh-keys "retire the backup" step (`SKILL.md:62-64`) — engineer-confirmed removal only, never automatic.

**Risk:** low — the failure mode (broken path) is self-diagnosing, unlike C1's failure mode (a returned prompt with no obvious link back to its cause).

**Source patterns referenced:**
- `plans-relocation_mirror-patterns_1.md` § 1 — `SKILL.md:62-64`, the "retire the backup" step (rename/retain, confirm before delete) as the precedent for what to do with the old directory instead of symlinking it

## Sub-decision F — Rollout ordering, full write-up

### Option F1: Asynchronous, auto-update-driven rollout

**Approach summary:** merge the PR to `develop`/`master`. `scripts/check-claude-version.sh` (SessionStart + UserPromptSubmit hook, per CLAUDE.md § Configuration Changes Policy) auto-pulls the update for each engineer within ~24h (once per day, gated by a marker, `--ff-only`). On each engineer's first session after the pull, the new `check-plans-location.sh` SessionStart hook detects their un-migrated state and proactively offers the `migrate-plans-location` skill, mirroring the `check-ssh-keys.sh` nag pattern exactly.

**Pros:** requires zero cross-engineer coordination — matches the confirmed ground truth that each engineer's plans repo is an independent per-machine fork with no shared state; reuses the EXACT auto-update + detection-hook machinery already proven for SSH key hygiene, which shipped and is presumably already validated in production; each engineer migrates at their own next-session pace, at a moment they are actively present to see and act on the nag (the check is deliberately wired to a moment the engineer is at the keyboard, per `check-ssh-keys.sh`'s SessionStart wiring and `check-plans-autocommit.sh`'s explicit UserPromptSubmit-not-SessionStart rationale for "surfaced on a turn someone is present to see").

**Cons:** the window between "engineer A has migrated" and "engineer B has not yet pulled the update" could, in principle, last up to the ~24h auto-update cadence per engineer — during which engineer B's sessions are running the OLD dot-claude version entirely (old paths, no new hook), which is actually a SAFER intermediate state than a partially-updated one (old version = old behavior, consistently) but does mean the fix is not "instant" for the whole team.

**Cost / effort:** none beyond what A1/A2 already require — this option adds no new engineering work, it is a description of what already happens given the existing auto-update mechanism.

**Risk:** low — the two failure modes are "engineer hasn't updated yet" (safe: fully old behavior) and "engineer has updated but hasn't migrated yet" (the A1/A2 transition-window scenario, handled by whichever of those is chosen).

**Source patterns referenced:**
- `CLAUDE.md:504` (working copy) — the auto-update mechanism description ("pulls automatically... once per day, gated by a marker... `--ff-only`")
- `plans-relocation_mirror-patterns_1.md` § 1 — the SessionStart wiring precedent

### Option F2: Coordinated synchronized cutover

**Approach summary:** announce the change to the team out-of-band (e.g. a message), ask all engineers to pull and run the migration skill within an agreed window, rather than relying on the passive auto-update + nag cycle.

**Pros:** collapses the transition window to a known, short, coordinated period rather than an unbounded per-engineer async drift; useful if there were any cross-engineer dependency on the plans location (there is not, per confirmed ground truth) or if the engineer wanted higher confidence that the fix is fully rolled out by a specific date.

**Cons:** adds process overhead (an announcement, a window, follow-up to confirm everyone migrated) for a change with a genuinely zero cross-engineer interaction surface — no engineer's plans content is read by another engineer's session, no shared infrastructure depends on all engineers being migrated simultaneously; duplicates coordination effort the auto-update mechanism already performs mechanically.

**Cost / effort:** a manual communication step outside the codebase, not automatable, not something this PR's content can enforce.

**Risk:** low, but this option's main cost is process overhead disproportionate to a change with no synchronization requirement.

**Source patterns referenced:**
- Confirmed ground truth (task briefing): "each engineer has their OWN fork, so migration is per-machine and manual (a PR cannot move it)" — supports F1's premise that there is no shared state requiring synchronization

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| Cutover race: agent writes new PLAN-SPIKE.md/SPIKE.md/etc. to the new (empty) path before the engineer runs the migration skill, while prior planning history sits unseen at the old path | Discoverability loss (not data loss) — engineer's session appears to have no history for an in-progress feature until migration runs | Merge-safe migration skill (Technical Decision B) that merges rather than clobbers when invoked, regardless of how many new files already landed at the new path by the time it runs; the detection hook nags proactively at every session start until migrated, not just once |
| Missed repoint in the 33-file inventory (a 34th reference not caught by the `grep -rln "claude/plans"` search, or a variant spelling like `.claude/plans` without the leading `~`) | A stale reference silently keeps working against the old (or nonexistent, post-migration) path, producing either the original sensitive-file prompt (if old path still resolves) or a broken-path failure (if not) | Re-run the same grep as a post-implementation verification step before the PR is opened; the grep pattern `claude/plans` is deliberately broad (matches both `~/.claude/plans` and any `.claude/plans` without tilde) |
| The `validate-bash-command.sh` plans-carve-out becomes dead code that misleadingly still claims (in its own comment) to solve the sensitive-file-gate problem, confusing a future reader | Low functional risk, moderate documentation-accuracy risk — a future engineer debugging a permission prompt might trust the stale comment and waste time on a carve-out that can never fire post-relocation | Technical Decision "Carve-out cleanup" (remove/repoint/leave) — engineer chooses |
| Compatibility symlink (if chosen — Option C1) reintroduces the exact bug this feature removes, for any code path that resolves through it | Silently defeats the purpose of the whole relocation for that one code path, and its failure signature (a returned permission prompt) does not obviously point back to "you have a symlink" as the cause | Do not create the symlink (Option C2), OR if created, document loudly in the runbook that the symlink is a known re-trigger and should be removed once no stale references remain |
| Per-machine, per-fork migration means the fix genuinely cannot be "pushed" centrally — an engineer who never sees/acts on the nag stays on the broken path indefinitely | The nag is advisory only (SessionStart hooks in this codebase never block, per every hook cited in `plans-relocation_mirror-patterns_1.md`) — an engineer could ignore it forever | Mirrors the exact same residual-gap accepted for SSH key hygiene (`check-ssh-keys.sh` also only nags, never forces) — this is a documented, accepted category of gap in this codebase's hook design, not a new risk class |

## Open questions for the engineer

- Technical Decision A: clean cutover (A1) or fallback shim (A2) for the transition window — given that A2 only partially closes the gap (LIVE scripts only, not agent writes) and adds real shim-maintenance cost, is the partial protection worth it?
- Technical Decision B: refuse-and-ask vs. auto-merge when the destination already has content — given the destination is confirmed empty today, is this purely a defensive check for future re-runs of the skill, or a real near-term scenario?
- Technical Decision C: symlink (C1) or no symlink (C2) — given C1's demonstrated risk of reintroducing the original bug, is there a scenario that specifically needs the symlink's backward-compatibility that C2's "fails loudly and gets fixed" does not adequately cover?
- Technical Decision D: rewrite, leave, or footnote the 6 historical citation paths in ADRs/docs?
- Technical Decision E: single PR or split PRs for repoint + mechanism + docs?
- Technical Decision F: async auto-update rollout (F1) or coordinated announcement (F2)?
- Carve-out cleanup: remove, repoint, or leave the `validate-bash-command.sh` plans-specific carve-out?
- Naming confirmation: the task briefing proposes `scripts/check-plans-location.sh` and skill `migrate-plans-location` — confirm these names, or choose alternatives (e.g. `check-plans-relocation.sh` / `migrate-plans-repo`) before `plan-composer` writes the canonical PLAN.md.
- Runbook home: which `docs/runbooks/` family should the new migration runbook live under? The closest existing precedent is `docs/runbooks/engineer-access/SSH-KEY-HYGIENE.md` (engineer-access category) — is `docs/runbooks/engineer-access/PLANS-RELOCATION.md` (or similar) the intended home, or does this warrant a different/new runbook family?

## Sources

- `~/Projects/4Shark/dot-claude/scripts/check-ssh-keys.sh:1-103` — SessionStart detection hook pattern to mirror
- `~/Projects/4Shark/dot-claude/skills/migrate-ssh-keys/SKILL.md:1-65` — guided migration skill pattern to mirror
- `~/Projects/4Shark/dot-claude/scripts/auto-approve-claude-dir-writes.sh:1-59` — existing (per engineer diagnosis, ineffective for the sensitive-file gate) broad mitigation attempt, shipped `CHANGELOG.md:49` ([0.8.0] - 2026-07-07)
- `~/Projects/4Shark/dot-claude/scripts/validate-bash-command.sh:10-14,95,109-116,580-584` — existing (per engineer diagnosis, ineffective) narrow plans-specific mitigation attempt
- `~/Projects/4Shark/dot-claude/scripts/migrate.sh:1-57` — existing unattended, tracked-migration mechanism (alternate pattern, not chosen)
- `~/Projects/4Shark/dot-claude/scripts/plans-autocommit.sh:32-33` — autocommit "what" script, single hardcoded `PLANS_DIR`
- `~/Projects/4Shark/dot-claude/scripts/setup-plans-autocommit.sh:23,128` — per-OS scheduler installer, idempotent reinstall confirmed safe
- `~/Projects/4Shark/dot-claude/scripts/check-plans-autocommit.sh:26-27,37-41` — staleness nudge, degrades silently on bad remote (reusable evidence for A1's silent-degrade claim)
- `~/Projects/4Shark/dot-claude/docs/LANGUAGE-POLICY.md:3,58,176` — the one LIVE glob pattern (`~/.claude/plans/{active,completed}/**/*.md`) requiring repoint
- `~/Projects/4Shark/dot-claude/settings.json:36,61,125,249,317,401` — hook wiring line numbers (check-ssh-keys, migrate.sh, check-plans-autocommit, auto-approve-claude-dir-writes, validate-bash-command, additionalDirectories)
- `~/Projects/4Shark/dot-claude/CHANGELOG.md:21,44-49` — SSH key hygiene shipped as one bullet-grouped unit (precedent for Option B "split PRs" trade-off discussion); auto-approve-claude-dir-writes shipped 2026-07-07
- `~/Projects/4Shark/dot-claude/CHANGELOG.md:429-431` — historical entry establishing the original `~/.claude/plans/` convention (never rewritten, per Changelog Policy)
- https://github.com/anthropics/claude-code/issues/66525 — `permissions.allow` rules have no effect on `.claude/**` (cited by task briefing, already-verified, not re-litigated here)
- https://github.com/anthropics/claude-code/issues/41615 — "permissions.allow AND PreToolUse hooks cannot override .claude/ sensitive-file prompt" (cited by task briefing, already-verified, not re-litigated here)
- See auxiliary: `plans-relocation_file-inventory_1.md` — full 33-file categorized breakdown with line numbers
- See auxiliary: `plans-relocation_mirror-patterns_1.md` — full pattern excerpts, both existing mitigation attempts, migrate.sh mechanism, additionalDirectories finding
- See auxiliary: `plans-relocation_autocommit-scripts_1.md` — full autocommit scheduler repoint detail
