# PLAN — Manual Integrator Run Skill

> Reference: `KNOWLEDGE.md`, `CONTEXT-MAP.md`, `PROCESS.md`, `DOMAIN.md` — none present for this feature (standard workflow, no DDD phase). Derived from `PLAN-SPIKE.md` (`~/.claude/plans/active/manual-integrator-run-skill/PLAN-SPIKE.md`) and the updated `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md` (RD4 revised 2026-07-09; Phase 0 executed 2026-07-09), which in turn derives its locked premises from the SPIKE's own Findings and its auxiliary `manual-integrator-run-skill_terraform-desired-counts_1.md`. RD1–RD8 are locked premises — restated below as given, not re-opened. This document supersedes the prior `PLAN.md` (RD4's earlier working shape — `integration:preview` + renamed `force_start` — and the Phase 0/execution-model contingency are both superseded by the sections below).

## Objective

Collapse the engineer's manual "raise the integrator's Mongo/web/worker, run the numbers-preview, eyeball them, approve, run for real" workflow into a single new action inside the existing `/integrators` skill. The skill must: derive a client's normal web/worker task counts from Terraform, raise a client's Mongo EC2 if one exists, scale web+worker to those counts, wait for readiness, trigger the integrator's (revised) `integration:start` rake task via a raw ECS run-task with a container command override to capture a NUMBERS-only preview, present the NUMBERS to the engineer and stop for approval, then on approval trigger the same task with `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1` to start the job non-interactively, and report divergence between a first and second numbers reading.

## Scope

### In scope

- The integrator-side rake task change (RD4, FINAL) needed to make `integration:start` driveable by a non-interactive Bash tool — EOF-aware `$stdin.gets` handling plus two env vars (`AUTO_ACCEPT`, `SKIP_THROUGHPUT`), `force_start` removed — delivered as a **hotfix**.
- Confirming the trigger mechanism actually works when driven by Claude's non-tty Bash tool — Phase 0 (executed 2026-07-09); its outcome determined the execution model (**Fallback A**: raw `aws ecs run-task` with a container command override, not `bin/ecs run`'s interactive ECS Exec session).
- Confirming the per-client web/worker count derivation from Terraform requires zero Terraform changes, and locating the right `.tf` file(s) per client given the non-uniform layout (RD1) via a curated `environments.json` field.
- The new `/integrators` action itself — control flow, what's reused vs new, prose placement in `SKILL.md` (RD8).
- Cross-repo sequencing (including hotfix delivery for the integrator change) and the risks specific to this feature.

### Out of scope

- Redebrasil's second monthly-window schedule's `DesiredCount` payload (SPIKE "What remains uncertain") — not read in this pass; carried as a flagged pre-rollout task below.
- Atento CL's live/active `DesiredCount` (the schedule's own payload, not the Terraform resting value of 0) — same, not read; carried as a flagged pre-rollout task below.
- Whether `commcenter`'s stray `scheduled_task_start_mongodb` module (present despite empty `AWS_INSTANCE_IDS`) targets something real — unread; unaffected by this plan since commcenter has no raisable Mongo either way.

## Locked premises (RD1–RD8, engineer 2026-07-09)

| # | Premise | Source |
|---|---|---|
| RD1 | Per-client web/worker counts come from Terraform `module "web"`/`module "worker"` `desired_count` — not `aws scheduler get-schedule`, not a curated file | SPIKE.md:343 |
| RD2 | Readiness = poll `aws ecs describe-services` until `runningCount == desiredCount` | SPIKE.md:345 |
| RD3 | Trigger container = the ephemeral runner task, never `bin/ecs connect` — the runner issues the command; only the mechanism it uses to do so is superseded by Fallback A (see RD4/Phase 0) | SPIKE.md:347 |
| RD4 | Rake surface (**FINAL, revised 2026-07-09**): single `integration:start`, made EOF-aware so a non-tty run with no `AUTO_ACCEPT` prints SOURCES+NUMBERS and aborts cleanly instead of crashing on `nil.strip`; `force_start` **REMOVED** (no callers, folded into a flag, not renamed); two env vars — `AUTO_ACCEPT` (skip the `Y/n` prompt, start non-interactively) and `SKIP_THROUGHPUT` (bypass the throughput guard — what `force_start` did via `Job::Starter.perform_async(true)`); shipped as a **hotfix** | SPIKE.md:349-355 |
| RD5 | The skill's accept step always uses the skip-throughput path — the human already judged the previewed numbers, now realized as `SKIP_THROUGHPUT=1` | SPIKE.md:357 |
| RD6 | Rely on `Job::Starter`'s existing Redis lock for the cron race; an in-flight-`Job` courtesy pre-check is optional polish, not required | SPIKE.md:359 |
| RD7 | No teardown — `ShutDownWorker` already self-scales to 0 / stops Mongo once the pipeline drains | SPIKE.md:361 |
| RD8 | New action inside the existing `/integrators` skill, not a standalone skill | SPIKE.md:363 |

## Phase 0 result (executed 2026-07-09 — DONE)

Phase 0 ran against `commcenter-staging` (non-productive, `desired_count=0`, no schedules — safe target). Full capture preserved at `/tmp/phase0_probe_capture_20260709.txt`.

**Outcome — the core premise holds, but `bin/ecs run` is not usable as-is for automation:**

- Clean stdout capture works through the non-tty Bash tool — the probe's output came back uncorrupted.
- No MFA needed — the default (read-only) AWS profile successfully ran `run-task` and `stop-task` on this stack; the skill's trigger will not need `/elevate-aws-access`.
- `bin/ecs run` is unclean non-interactively: the `execute-command --interactive` session ends with `Cannot perform start session: EOF` (no tty to hold the session), the script exits 1 even though the command succeeded (the exit code cannot distinguish real failure from the EOF artifact), and `cleanup()` crashes on `set -u` (`TASK_ARN: unbound variable`, `integrator/bin/ecs:194`) so the ephemeral task is not stopped by the trap (it self-dies when its `sleep TIMEOUT` expires).

**Decision — execution model = Fallback A.** The skill does NOT drive `bin/ecs run`. It uses raw `aws ecs run-task` with a container command override — the runner container runs `bundle exec rake integration:start` (numbers pass) or `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start` (accept pass) directly as a batch task, no ECS Exec / no interactive session — then polls `aws ecs describe-tasks` until `STOPPED` and reads the NUMBERS output from CloudWatch Logs. This sidesteps the "ECS only supports interactive sessions" constraint (SPIKE Finding 1) entirely and is deterministic. It still honors RD3 ("the runner issues the command") — only the HOW changed, not WHO. This closes the prior contingent decision on the execution model for skill steps 6/8/9 — it is no longer deferred.

## Chosen approach

**Direction:** Extend `/integrators` with a new prose-driven action, wired to the revised `integration:start` rake task (single task, EOF-aware, two env vars, `force_start` removed) shipped as a hotfix in the integrator repo, sourcing per-client counts from a curated `environments.json` field, and triggering the rake task via raw `aws ecs run-task` command overrides (Fallback A) rather than `bin/ecs run`'s interactive ECS Exec session.

**Rationale (from engineer):**

- RD5 was already "resolved by derivation" in the SPIKE, flagged for confirmation at PLAN review (`SPIKE.md:357`); the engineer confirmed on 2026-07-09 — the skill's accept step always skips the throughput guard, realized as `SKIP_THROUGHPUT=1`.
- RD4 was collapsed further by the engineer than the earlier "add `preview` + rename `force_start`" working shape: no `integration:preview` task — "the numbers-only first pass IS `integration:start`" (it already prints SOURCES+NUMBERS before the prompt); the `integration:start` name stays unchanged ("the name is perfect" — no external callers, no churn); `force_start` is removed rather than renamed, since it has no callers; this moots the SOURCES+NUMBERS duplication concern entirely — one task, no third copy of the block (SPIKE.md:349-354).
- The engineer instructed this integrator-side rake change to ship as a hotfix (SPIKE.md:355) — HubFlow off `master`, run in the main working tree (not a worktree), version bump + dated CHANGELOG section, `git hf hotfix finish` back-merging to master and develop. The dot-claude skill change stays a normal feature PR.
- Phase 0 (executed 2026-07-09) confirmed clean non-tty stdout capture and no MFA requirement, but found `bin/ecs run` unclean non-interactively (EOF artifact on the exit code, `cleanup()` crash under `set -u`) — so the skill's trigger mechanism is Fallback A: raw `aws ecs run-task` with a container command override, polling `describe-tasks` until `STOPPED` and reading NUMBERS from CloudWatch Logs (SPIKE.md:369-379).
- Per-client Terraform file location: the engineer chose the curated `environments.json` field (PLAN-SPIKE Option B) over the heuristic glob+suffix-strip (Option A). The non-uniform layout (`commcenter-staging` drops the `-staging` suffix in its directory but gains a `_staging` filename suffix; `atento-br` gains a `_br` filename suffix but drops the country from its directory — PLAN-SPIKE.md:121-129) makes a single stripping rule brittle; a curated field matches the file's existing purpose ("metadata that does NOT come from AWS tags", `environments.json:3`) and a wrong/stale path fails loudly (file not found) rather than silently matching the wrong file.
- Skill placement: the engineer chose pure prose in `SKILL.md`, matching every existing `/integrators` action, with at most a minimal helper for reading the `desired_count` value — no dedicated multi-step orchestration script.
- Second NUMBERS reading timing: the engineer chose immediately after triggering the accept (before the async pipeline completes). This detects source-side inserts in the window between reading 1 and reading 2 — the `last_job.ends_at` watermark only moves on job COMPLETION (SPIKE Finding 4), so identical numbers mean "running against the same state" and divergence means something else (a race, a source-side change) shifted state in between.

**Source patterns referenced:**

- `integrator/lib/tasks/integration.rake:31-70` (SOURCES + NUMBERS composition, already printed before the prompt), `:79-90` (task `start`'s `$stdin.gets`/prompt block), `:156-167` (task `force_start`, byte-identical prompt block, `Job::Starter.perform_async(true)` at line 161)
- `integrator/bin/ecs:163-166` (`cmd_run` signature), `193-204` (cleanup trap — the `set -u` crash Phase 0 hit), `206-331` (run→wait→exec sequence), `219` (`--overrides` mechanism — the precedent Fallback A's container command override follows), `325-331` (interactive execute-command call — the step Fallback A bypasses)
- `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md:349-355` (RD4 final), `:369-379` (Phase 0 outcome and Fallback A decision)
- `~/.claude/skills/integrators/SKILL.md:90-104` (scale-up action), `106-117` (scale-down confirmation pattern), `130-132` (MongoDB-start note), `58-69` (fallback lookup)
- `~/.claude/skills/integrators/environments.json:3` (file's stated purpose — curated metadata not derivable from AWS tags)
- `~/.claude/skills/ec2-instances/SKILL.md:34-49` (filter commands), `70-78` (start-instance wrapper)
- `~/.claude/scripts/ecs-scale.sh:1-62` (shared scale wrapper)

## Execution phases

### Phase 0: prerequisite technical validation — DONE (executed 2026-07-09)

**Objective:** prove or refute the single assumption the whole trigger mechanism (RD3) rested on — whether the runner task, driven through Claude's non-tty Bash tool, can capture clean stdout from a non-blocking rake invocation and reliably pass an env-var-prefixed command through to the container.

**Result:** see § "Phase 0 result" above. Clean non-tty capture and no-MFA both confirmed; `bin/ecs run` itself is unusable non-interactively (EOF exit-code artifact, `cleanup()` crash). Execution model decided = **Fallback A** (raw `aws ecs run-task` with a container command override, no ECS Exec).

**Success criteria (all met):**

- [x] The clean non-blocking capture probe returned without hanging and its output was captured without corruption.
- [x] No MFA was required for `run-task`/`stop-task` on the probed stack.
- [x] `bin/ecs run`'s non-interactive limitation was identified precisely enough to select a fallback (Fallback A) with no further open technical question on the trigger mechanism itself.

### Phase 1: integrator repo — rake surface change (RD4 FINAL) — shipped as a hotfix

**Objective:** modify `integration:start` in place — make its `$stdin.gets` EOF-aware, remove `force_start`, add the `AUTO_ACCEPT` and `SKIP_THROUGHPUT` env vars — and ship the change as a hotfix.

**Components:**

- **EOF-aware prompt.** `integration:start` already prints SOURCES + NUMBERS (`integrator/lib/tasks/integration.rake:31-70`) before reaching the `Y/n` prompt (`:79-80`). Today, a non-tty run with no answer on stdin crashes at `nil.strip` when `$stdin.gets` returns `nil` on EOF. The change makes this graceful: no tty and no `AUTO_ACCEPT` → print the numbers and abort cleanly, without starting the job.
- **`integration:start` name unchanged** — the engineer's call; no external callers, no churn.
- **`force_start` REMOVED**, folded into a flag rather than renamed — it has no callers, so removal is safe.
- **`AUTO_ACCEPT` env var** — when set, skips `$stdin.gets` and starts non-interactively (branches straight into the existing "accept" path).
- **`SKIP_THROUGHPUT` env var** — when set, bypasses the throughput guard, i.e. calls `Job::Starter.perform_async(true)` (mirroring what `force_start` did at `integration.rake:161`) instead of the guarded `Job::Starter.perform_async`.
- **Skill's accept invocation:** `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start`.
- **SOURCES+NUMBERS duplication is moot.** One task, no third (or even second) copy of the ~45-line SOURCES+NUMBERS block — RD4's earlier working shape (`preview` + renamed `force_start`) would have created a third occurrence; the final shape removes `force_start` entirely instead, so the duplication concern raised in SPIKE Finding 2 no longer applies to this change.
- `integrator/CHANGELOG.md` entry — as part of the hotfix branch, a dated `## [X.Y.Z] - YYYY-MM-DD` section (not `[Unreleased]`), per the tag-adjacent CHANGELOG convention for release/hotfix branches.

**Delivery mechanics (hotfix, engineer's instruction):**

- HubFlow off `master`: `git hf hotfix start X.Y.Z`.
- Run in the **main working tree**, NOT a worktree — hotfix `finish` checks out `master` then `develop` in the tree where it runs, which a worktree cannot do (those branches are pinned to the main tree).
- Version bump + the dated `CHANGELOG.md` section, committed on the hotfix branch.
- `git hf hotfix finish X.Y.Z` — back-merges to both `master` and `develop`, tags the release.
- The dot-claude skill change (Phase 3 + Phase 4) stays a normal feature branch PR, developed in a worktree.

**Dependencies:** none for the code change itself. Phase 0's outcome informs how the skill will invoke this task (Fallback A, Phase 2) but does not gate writing this change.

**Success criteria:**

- [ ] `integration:start`'s `$stdin.gets` is EOF-aware: a non-tty run with no `AUTO_ACCEPT` prints SOURCES + NUMBERS and aborts cleanly, no crash.
- [ ] `force_start` is removed with no broken callers.
- [ ] `AUTO_ACCEPT=1` skips the prompt and starts the job non-interactively.
- [ ] `SKIP_THROUGHPUT=1` bypasses the throughput guard (calls `Job::Starter.perform_async(true)`).
- [ ] `integrator/CHANGELOG.md` has a dated `## [X.Y.Z] - YYYY-MM-DD` entry for this change.
- [ ] The change ships via `git hf hotfix start` → version bump + CHANGELOG → commit → `git hf hotfix finish`, run entirely in the main working tree.

### Phase 2: trigger mechanism — Fallback A (raw `run-task` with a container command override)

**Objective:** define how the skill actually issues `integration:start` against a client's runner infrastructure, given Phase 0's outcome ruled out `bin/ecs run`.

**Components:**

- Raw `aws ecs run-task` targeting the client's `integrator-{name}-runner-service` network config (the same pre-existing runner infrastructure `bin/ecs run` uses, per `integrator/bin/ecs:163-166` and its `desired_count = 0`-always shape), with a container command override — mirroring the override mechanism `bin/ecs run` itself already uses (`integrator/bin/ecs:219`, currently `sleep $TIMEOUT`) but pointing directly at the rake command instead:
  - Numbers pass: override to `bundle exec rake integration:start`.
  - Accept pass: override to `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start`.
- No `execute-command` / `--interactive` step at all — a genuine batch task, sidestepping the "ECS only supports interactive sessions" constraint (SPIKE Finding 1) entirely.
- Poll `aws ecs describe-tasks` until the task reaches `STOPPED` (the same "poll until a target state" shape RD2 already establishes for readiness).
- Read the NUMBERS output from CloudWatch Logs once the task is `STOPPED`.
- Zero changes to `bin/ecs` itself — Fallback A is a separate, parallel invocation path; `bin/ecs run`/`bin/ecs connect` remain untouched for their existing manual (human) use.

**Dependencies:** Phase 0 (established the need for and shape of Fallback A); Phase 1 (the `integration:start` env-var surface must exist for these invocations to target).

**Success criteria:**

- [ ] The skill's numbers-pass and accept-pass invocations are both raw `aws ecs run-task` calls with a container command override — no `execute-command`/`--interactive` step.
- [ ] The skill polls `aws ecs describe-tasks` until `STOPPED` before reading output.
- [ ] The skill reads NUMBERS from CloudWatch Logs.
- [ ] `bin/ecs` itself is unmodified.

### Phase 3: terraform repo — no edits; `environments.json` metadata addition

**Objective:** confirm RD1 requires zero Terraform edits, and add the per-client Terraform-file-location metadata to `environments.json` (the engineer's chosen Option B).

**Components:**

- RD1 reads existing `desired_count` values — zero Terraform edits required or possible; confirmed no write path exists or is needed.
- Add a curated field per client entry to `~/.claude/skills/integrators/environments.json`, e.g. `"terraform_compute_file": "integrator-atento/compute_br.tf"`, mirroring the existing pattern of curating non-tag metadata in this file (`environments.json:3`: "metadata that does NOT come from AWS tags"). The per-client mapping to populate:

  | Client key (`environments.json`) | Terraform directory | File holding `module "web"`/`module "worker"` |
  |---|---|---|
  | `almaviva` | `terraform/integrator-almaviva/` | `compute.tf` |
  | `redebrasil` | `terraform/integrator-redebrasil/` | `compute.tf` |
  | `maqnelson` | `terraform/integrator-maqnelson/` | `compute.tf` |
  | `commcenter` | `terraform/integrator-commcenter/` | `compute.tf` |
  | `commcenter-staging` | `terraform/integrator-commcenter/` | `compute_staging.tf` |
  | `atento-br` | `terraform/integrator-atento/` | `compute_br.tf` |
  | `atento-mx` | `terraform/integrator-atento/` | `compute_mx.tf` |
  | `atento-co` | `terraform/integrator-atento/` | `compute_co.tf` |
  | `atento-cl` | `terraform/integrator-atento/` | `compute_cl.tf` |

- Reading the literal `desired_count = N` value out of the `module "web" { ... }` / `module "worker" { ... }` HCL block still needs a small grep/awk (or equivalent) step inside whichever file the curated field points to — this applies regardless of the file-location mechanism, since RD1 already settled on Terraform as the source of the count itself.

**Dependencies:** none — this phase can be developed and merged independently of Phase 1's deploy timing.

**Success criteria:**

- [ ] Confirmed: no Terraform PR is needed for RD1.
- [ ] `environments.json` carries a `terraform_compute_file` (or equivalently named) field for every client in the table above.
- [ ] The grep/awk step to extract `desired_count` from the pointed-to file is defined.

### Phase 4: dot-claude repo — the new `/integrators` action

**Objective:** implement the new action as prose in `SKILL.md`, per RD8 and the engineer's placement choice, using Fallback A for the trigger steps.

**Components (control-flow enumeration, each tagged reused vs new):**

1. **Resolve client** — exact-match against `environments.json` keys/aliases, per the skill's existing lookup convention (`~/.claude/skills/integrators/SKILL.md:56-69` fallback behavior) and the team-wide "Lookup Resolution — Exact Match Wins" rule. *Reused.*
2. **Check for a raisable Mongo** — `bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh --client <name> --role database` (`~/.claude/skills/ec2-instances/SKILL.md:44-45`); if it returns instances, start them via `bash ~/.claude/scripts/start-instance.sh --region sa-east-1 <instance-id...>` (`ec2-instances/SKILL.md:74-76`); if empty, skip (commcenter and all four Atento countries have no `AWS_INSTANCE_IDS`-mapped Mongo — expected, not an error, per SPIKE Finding 6). *Reused wholesale.*
3. **Read web/worker desired counts from Terraform** — via the `terraform_compute_file` field added in Phase 3, plus a small grep/awk step to pull the `desired_count` value. *New.*
4. **Scale web + worker to those counts** — two calls to `bash ~/.claude/scripts/ecs-scale.sh --region sa-east-1 --cluster integrator-{client}-cluster --service integrator-{client}-{web|worker}-service --desired-count {N}` (`SKILL.md:96-101`, the skill's existing scale-up action). *Reused wholesale.*
5. **Wait for readiness** — poll `aws ecs describe-services --cluster ... --services <web-service> <worker-service>` until both reach `runningCount == desiredCount` (RD2). *New — implementation deferred, see § Deferred items.*
6. **Trigger preview (numbers pass)** — raw `aws ecs run-task` with a container command override to `bundle exec rake integration:start` (Phase 2, Fallback A); poll `aws ecs describe-tasks` until `STOPPED`; read NUMBERS from CloudWatch Logs. *New command, new mechanism.*
7. **Present NUMBERS, STOP for engineer approval** — no execution continues until the engineer replies. *New, but structurally matches the skill's existing "confirm before bulk scale-down" pause pattern (`SKILL.md:108-111`).*
8. **On approval, trigger accept** — raw `aws ecs run-task` with a container command override to `AUTO_ACCEPT=1 SKIP_THROUGHPUT=1 bundle exec rake integration:start` (Phase 2, Fallback A); same poll + CloudWatch Logs read as step 6. *New command, new mechanism.*
9. **Capture a second NUMBERS reading and report divergence** — re-run step 6's mechanism, immediately after triggering step 8 (the engineer's chosen timing), and diff the two outputs, reported to the engineer as informational. *New.*

**Execution model for steps 6, 8, and 9 — RESOLVED, no longer contingent.** Fallback A (Phase 0/Phase 2) applies to all three: each is a raw `aws ecs run-task` call, polled to `STOPPED`, output read from CloudWatch Logs. This is still direct execution by Claude issuing Bash tool calls inside the conversation, matching every existing `/integrators` action (`SKILL.md:90-117`) — RD8's established pattern holds without a split-execution-model fallback to `/integration-debug`'s prose-generation model.

**Script vs prose placement** — the engineer's choice: pure prose extension of `SKILL.md`, matching the existing style exactly. Claude executes each atomic command per the enumerated steps above, across as many Bash tool calls as needed, pausing naturally at step 7. At most a minimal helper for reading the `desired_count` value (step 3) — no dedicated multi-step orchestration script bundling steps 2–5 or 2–9.

**Dependencies:** Phase 2 (Fallback A mechanism for steps 6/8/9); Phase 1 (the rake env vars steps 6/8 invoke must exist and be deployed to the target client — see § Open research items on deploy granularity); Phase 3 (`terraform_compute_file` field for step 3).

**Success criteria:**

- [ ] The new action is documented as prose in `~/.claude/skills/integrators/SKILL.md`, following the existing action structure.
- [ ] Steps 1, 2, 4 reuse existing scripts/tools wholesale with no new code.
- [ ] Step 3 reads the client's `terraform_compute_file` field and extracts `desired_count` for web and worker.
- [ ] Steps 6 and 8 issue raw `aws ecs run-task` calls with the correct command override, poll to `STOPPED`, and read CloudWatch Logs.
- [ ] Step 7 hard-stops execution until the engineer explicitly approves.
- [ ] Step 9's second reading runs immediately after triggering step 8, and the diff between the two NUMBERS readings is reported to the engineer.

## Technical decisions

| Decision | Choice | Rationale (from engineer / from draft) |
|----------|--------|----------------------------------------|
| Rake surface shape (RD4) | FINAL: single `integration:start`, EOF-aware; `force_start` removed (not renamed); two env vars `AUTO_ACCEPT`/`SKIP_THROUGHPUT` | Engineer collapsed the surface beyond the earlier "add `preview` + rename `force_start`" shape on 2026-07-09 review; "the numbers-only first pass IS `integration:start`", "the name is perfect", `force_start` has no callers so removal is safe (SPIKE.md:349-354) |
| Delivery mechanism for the integrator rake change | Hotfix — HubFlow off `master`, main working tree, dated CHANGELOG section, `git hf hotfix finish` | Engineer's explicit instruction (SPIKE.md:355) |
| Execution model for the skill's trigger (steps 6/8/9) | Fallback A — raw `aws ecs run-task` with a container command override, no ECS Exec | Determined by Phase 0's outcome: `bin/ecs run` is unclean non-interactively (EOF exit-code artifact, `cleanup()` crash under `set -u`); Fallback A sidesteps the interactive-session constraint entirely and is deterministic (SPIKE.md:369-379) |
| RD5 — throughput-guard skip on accept | Confirmed: the skill's accept step always uses `SKIP_THROUGHPUT=1` | SPIKE.md:357 already resolved this "by derivation" (the human already judged the previewed numbers); engineer confirmed explicitly on PLAN review, 2026-07-09 |
| Per-client Terraform file location | Curated field in `environments.json` (`terraform_compute_file` or equivalent), per client, per the table in Phase 3 | Engineer's choice (PLAN-SPIKE section 3, Option B). Non-uniform layout makes a heuristic stripping rule brittle; a wrong/stale curated path fails loudly instead of silently matching the wrong file; matches `environments.json`'s existing purpose of holding non-tag per-client metadata (`environments.json:3`) |
| New action: script vs prose placement | Pure `SKILL.md` prose, matching every existing `/integrators` action; at most a minimal helper for reading `desired_count` | Engineer's choice. Matches convention exactly — no dedicated multi-step orchestration script |
| Timing of the second NUMBERS reading (step 9) | Immediately after triggering the accept (step 8), before the async pipeline completes | Engineer's choice. Uses the same `last_job.ends_at` watermark as the first reading (SPIKE Finding 4) — a real divergence only appears if something else (a race, a source-side change) shifted state in the window between the two readings |

## Deferred items (not decided in this document)

- **Readiness-wait (step 5) implementation (Phase 4).** Deferred to `/execute`. Leaning toward an inline poll loop in a helper mirroring `bin/ecs`'s own `describe`-poll pattern (`integrator/bin/ecs:234-263`, a `for`/`sleep` loop, 60 attempts) as a structural precedent that such a loop is an accepted shape inside a script — as opposed to the main session issuing repeated `sleep`-then-check Bash tool calls itself, which the Bash Single-Line/Command Safety policies steer away from.

## Open research items — flagged as pre-rollout tasks

These items were not resolved during research and are carried forward as gates on rollout, not resolved here.

- **Deploy granularity for the integrator rake change is unconfirmed.** It is not known whether one integrator deploy trigger updates every client at once or each client independently (`~/.claude/docs/DEPLOY-REFERENCE.md` not yet read). This gates the sequencing of Phase 1's rollout across clients — read `DEPLOY-REFERENCE.md`'s integrator section before sequencing.
- **Redebrasil's second monthly-window schedule's `DesiredCount`, and Atento CL's active schedule `DesiredCount`, were never read.** RD1 uses the resting Terraform `desired_count` as the source of truth, which may be stale relative to either of these two clients' actual schedule payload. Read `aws scheduler get-schedule` for both before onboarding redebrasil or atento-cl into this action.

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Phase 0's premise (non-tty capture of a runner-issued command) — RESOLVED | Was HIGH before validation; now closed. `bin/ecs run` itself proved unusable non-interactively, which is why Fallback A was selected | Phase 0 executed 2026-07-09; Fallback A (Phase 2) adopted as the execution model — no longer an open risk to the trigger mechanism's existence, only to its implementation detail (covered by the Phase 2/4 success criteria) |
| Client→count lookup brittleness across non-uniform Terraform layouts | MEDIUM — redebrasil's second monthly schedule's `DesiredCount` and Atento CL's active `DesiredCount` were never read; if either differs from the resting Terraform value the skill would scale to a stale/wrong count for those two clients specifically | Read the two unresolved schedule payloads (`aws scheduler get-schedule`) before onboarding redebrasil or atento-cl into this action, even though RD1 does not use the schedule as the primary source |
| Per-client deploy granularity for the integrator rake change is unconfirmed | MEDIUM — sequencing risk: the skill cannot successfully drive a client whose deployed integrator image predates the revised `integration:start` env vars, and this pass did not confirm whether one deploy trigger updates every client or one client at a time | Read `~/.claude/docs/DEPLOY-REFERENCE.md`'s integrator section before sequencing the rollout across clients |
| Readiness-wait loop mechanism constrained by the Bash Single-Line/Command-Safety sleep-loop rules | LOW-MEDIUM | Resolve the readiness-wait implementation at `/execute` time |
| Second-NUMBERS-reading semantics (Finding 4's watermark discrepancy) | LOW — reporting/informational only, does not affect whether the job actually starts | Document the interpretation in `SKILL.md` once the action is written (timing already decided above) |

## Assumptions

- RD1–RD8 hold as stated in `SPIKE.md` (RD4 in its 2026-07-09 revised form) and are not re-opened by this plan.
- Phase 0 was run before any integrator or dot-claude code was written (2026-07-09), confirming clean non-tty capture and no MFA requirement; per its outcome, the skill uses Fallback A rather than driving `bin/ecs run` directly.
- The curated `environments.json` field added in Phase 3 will be kept in sync by hand if a client's Terraform files are ever reorganized — the same class of drift risk the SPIKE's first trade-off table already named for the count itself (`SPIKE.md:292`), applied here only to the file path, which changes far less often than `desired_count` does.
- `commcenter-staging`'s `desired_count = 0` for web/worker/runner and its "non-productive, free to deploy" policy (`environments.json:71`) made it a safe Phase 0 probe target with no collision risk against a live nightly run or a client-visible service — already exercised in Phase 0.

## Cross-repo execution sequencing

1. **Phase 0 validation — DONE (2026-07-09).** Ran against `commcenter-staging`'s existing runner service; no repo change was required. Resolved the execution model (Fallback A) for every step that follows.
2. **integrator repo — HOTFIX (Phase 1).** `git hf hotfix start X.Y.Z` off `master`, run in the main working tree. Add the `integration:start` EOF-aware handling, remove `force_start`, wire `AUTO_ACCEPT`/`SKIP_THROUGHPUT`, add the dated `CHANGELOG.md` section. `git hf hotfix finish X.Y.Z` back-merges to `master` and `develop`. Must be merged AND deployed to a given client's stack before the skill's new action can be exercised against that client (deploy granularity itself is an open research item above).
3. **terraform repo** — no PR needed for RD1 itself. The `environments.json` metadata addition (Phase 3) does NOT touch the terraform repo at all — it only reads Terraform files, never writes them.
4. **dot-claude repo — normal feature PR (Phase 2 grounding + Phase 3 + Phase 4).** Developed in a worktree on a `feature/*` branch: the `environments.json` metadata addition, and the new `/integrators` action (prose in `SKILL.md`) using the Fallback A trigger mechanism. Can be developed and merged independently of Phase 1's deploy timing, but is only end-to-end usable against a given client once that client's integrator image includes Phase 1's rake changes.

Phase 1 (hotfix) and Phases 3+4 (dot-claude feature) can be developed in parallel — Phase 0 already cleared the way for both. Phase 1's deployment to each target client is the actual gate on when the new `/integrators` action becomes usable for that client.

## Changelog reminders

- `integrator/CHANGELOG.md` needs a dated `## [X.Y.Z] - YYYY-MM-DD` entry for the rake surface change (Phase 1), created directly on the hotfix branch — not under `[Unreleased]`.
- `dot-claude`'s own changelog convention applies to the new `/integrators` action (Phase 3 + Phase 4) once merged via its normal feature-branch flow, per the standing 4Shark rule that every feature branch updates a changelog before completion.

## Sources

- `integrator/lib/tasks/integration.rake:1-169` (read in full) — `task start` (18-91, including SOURCES+NUMBERS at 31-70 and the prompt at 79-90), `task force_start` (95-168, `Job::Starter.perform_async(true)` at 161)
- `integrator/bin/ecs:1-417` (read in full) — `cmd_connect` (73-158), `cmd_run` (163-332), `cmd_cleanup` (337-405); specifically `163-166` (signature), `193-204` (cleanup trap — the `set -u` crash Phase 0 hit), `206-331` (run→wait→exec sequence), `219` (`--overrides` mechanism), `325-331` (interactive execute-command call)
- `~/.claude/skills/integrators/SKILL.md:1-133` (read in full) — scale-up action (90-104), scale-down confirmation pattern (106-117), MongoDB-start note (130-132), fallback lookup (58-69)
- `~/.claude/skills/integrators/environments.json:1-166` (read in full) — confirms no `terraform`/`compute` file-path field exists per client, prior to Phase 3's addition
- `~/.claude/skills/ec2-instances/SKILL.md:1-89` (read in full) — filter commands (34-49), start-instance wrapper (70-78)
- `~/.claude/scripts/ecs-scale.sh:1-62` (read in full) — the shared scale wrapper
- `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md:1-379` (read in full) — all Findings, Trade-offs, RD1-RD8 (RD4 revised at 349-355), and the Phase 0 outcome (369-379)
- `~/.claude/plans/active/spike/manual-integrator-run-skill/manual-integrator-run-skill_terraform-desired-counts_1.md:1-70` (read in full) — per-client Terraform layout backing the Phase 3 table
- `~/.claude/plans/active/manual-integrator-run-skill/PLAN-SPIKE.md:1-213` (read in full) — the validated draft this plan composes from (RD1/RD2/RD3/RD5/RD6/RD7/RD8, the terraform file-location table, and the control-flow enumeration carried forward as-is)
- `/tmp/phase0_probe_capture_20260709.txt` — full Phase 0 probe capture (referenced by the SPIKE's Phase 0 outcome section, not re-read in this pass)
