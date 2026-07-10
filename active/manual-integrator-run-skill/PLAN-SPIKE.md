# PLAN-SPIKE — Manual Integrator Run Skill

> Reference: `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md` (337 lines, read in full) and its auxiliary `manual-integrator-run-skill_terraform-desired-counts_1.md`. Resolved decisions RD1–RD8 in that SPIKE are **locked premises** — they are restated below as given, not re-opened, and no option in this document proposes an alternative to any of them.

## Objective

Collapse the engineer's manual "raise the integrator's Mongo/web/worker, run the numbers-preview, eyeball them, approve, run for real" workflow into a single new action inside the existing `/integrators` skill. The skill must: derive a client's normal web/worker task counts from Terraform, raise a client's Mongo EC2 if one exists, scale web+worker to those counts, wait for readiness, trigger a new non-interactive "numbers preview" rake task via an ephemeral ECS runner task, present the NUMBERS to the engineer and stop for approval, then on approval trigger a non-interactive "start, skip the throughput guard" invocation, and report divergence between a first and second numbers reading.

## Scope

### In scope

- The integrator-side rake task change needed to make the flow driveable by a non-interactive Bash tool (RD4).
- Verifying (not designing from scratch) the trigger mechanism through `bin/ecs run` (RD3) actually works when driven by Claude's non-tty Bash tool — Phase 0.
- Confirming the per-client web/worker count derivation from Terraform requires zero Terraform changes, and enumerating how the skill locates the right `.tf` file(s) per client given the non-uniform layout (RD1).
- The new `/integrators` action itself — control flow, what's reused vs new, script vs prose placement (RD8).
- Cross-repo sequencing and the risks specific to this feature.

### Out of scope (open question)

- Redebrasil's second monthly-window schedule's `DesiredCount` payload (SPIKE "What remains uncertain") — not read in this pass either; flagged again below.
- Atento CL's live/active `DesiredCount` (the schedule's own payload, not the Terraform resting value of 0) — same, not read.
- Whether `commcenter`'s stray `scheduled_task_start_mongodb` module (present despite empty `AWS_INSTANCE_IDS`) targets something real — SPIKE flagged this as unread; unaffected by this plan since commcenter has no raisable Mongo either way.
- Exact final rake task/env-var names (`integration:preview`, `integration:start_skip_throughput`, `AUTO_ACCEPT`) are RD4's *working names* — final naming is Pattern Priming's job at `/execute` time, not this document's.

## Locked premises (RD1–RD8, engineer 2026-07-09)

| # | Premise | Source |
|---|---|---|
| RD1 | Per-client web/worker counts come from Terraform `module "web"`/`module "worker"` `desired_count` — not `aws scheduler get-schedule`, not a curated file | SPIKE.md:343 |
| RD2 | Readiness = poll `aws ecs describe-services` until `runningCount == desiredCount` | SPIKE.md:345 |
| RD3 | Trigger container = the ephemeral `bin/ecs run` runner task, never `bin/ecs connect` | SPIKE.md:347 |
| RD4 | Rake surface: add `integration:preview` (numbers only, no prompt); keep `integration:start` (interactive, guarded); rename `force_start` → `integration:start_skip_throughput` (working name); non-interactive accept via `AUTO_ACCEPT=1` (working name) | SPIKE.md:349-353 |
| RD5 | The skill's accept step always uses the skip-throughput path — the human already judged the previewed numbers | SPIKE.md:355 |
| RD6 | Rely on `Job::Starter`'s existing Redis lock for the cron race; an in-flight-`Job` courtesy pre-check is optional polish, not required | SPIKE.md:357 |
| RD7 | No teardown — `ShutDownWorker` already self-scales to 0 / stops Mongo once the pipeline drains | SPIKE.md:359 |
| RD8 | New action inside the existing `/integrators` skill, not a standalone skill | SPIKE.md:361 |

## Phase 0 — prerequisite technical validation (must run before any implementation)

**What is unproven:** whether `bin/ecs run` — which itself opens the ECS Exec session via `aws ecs execute-command --interactive` (`integrator/bin/ecs:325-331`) — can, driven through Claude's non-tty Bash tool, (a) capture clean stdout from a non-blocking rake invocation, and (b) reliably pass an env-var-prefixed command through to the container. SPIKE.md calls this "the single assumption that, if wrong, invalidates the runner approach (RD3) and the whole trigger mechanism" (SPIKE.md:365).

**Why it's independent of RD4** — `integration:preview` doesn't exist yet, but the mechanism can be validated today against any existing rake entrypoint that already prints to stdout and exits without touching `$stdin`, e.g. `bundle exec rails runner`:

```bash
# integrator/bin/ecs:163-166 — cmd_run's own signature
cmd_run() {
  local INTEGRATOR="$1"
  local COMMAND="${2:-bundle exec rails console}"
  local TIMEOUT="${3:-7200}"
```

**Concrete validation steps:**

1. **Clean non-blocking capture.** Run `bin/ecs run commcenter-staging "bundle exec rails runner \"puts 'PHASE0_PROBE_OK'; puts Rails.env\"" 300` via the Bash tool and confirm: the tool call returns (does not hang until timeout), the literal string `PHASE0_PROBE_OK` appears in the captured stdout without corruption (no partial ANSI/control-sequence noise from the SSM Session Manager plugin that would make programmatic parsing unreliable), and the ephemeral task's `cleanup()` trap (`bin/ecs:193-204`) fires and stops the task afterward.
2. **Env-var passthrough.** Run `bin/ecs run commcenter-staging "PHASE0_FLAG=1 bundle exec rails runner \"puts ENV['PHASE0_FLAG']\"" 300` and confirm `1` is captured cleanly — this is the exact shape `AUTO_ACCEPT=1 bundle exec rake integration:start_skip_throughput` will need (RD4).
3. **Client choice rationale.** `commcenter-staging` is `desired_count = 0` for web/worker/runner with **no scheduler resources at all** (aux file, commcenter section) and its `deploy_policy` is `"Non-productive — runs on-demand ... free to deploy"` (`environments.json:71`) — a probe here cannot collide with a live nightly run or a client-visible service.

**If Phase 0 fails** (capture is dirty, or the Bash tool hangs / cannot complete the interactive session non-interactively): the fallback is NOT to reconsider RD3's *decision* (which container issues the command stays "the runner", per RD3's own rationale that the issuing container only needs Rails+DB connectivity) — the fallback is to reconsider **how** the runner issues the command:

- **Fallback A — raw `run-task` with a container command override, no ECS Exec at all.** `cmd_run` already uses `--overrides` to make the container run `sleep $TIMEOUT` instead of its default command (`integrator/bin/ecs:219`); a parallel invocation could instead override the container command directly to `bundle exec rake integration:preview` (or the accept invocation) and skip `execute-command`/`--interactive` entirely — a genuine batch task, not an interactive shell, sidestepping Finding 1's "ECS only supports interactive sessions" constraint completely. Output would be read from CloudWatch Logs after the task reaches `STOPPED`, using `aws ecs describe-tasks` to poll completion (a shape RD2 already establishes) instead of a live stdout stream.
- **Fallback B — reconsider `connect` vs `run`** (re-opens the third SPIKE trade-off table, `SPIKE.md:302-307`), only if Fallback A also fails for some reason specific to the runner task definition.

## Candidate approaches

### 1. integrator repo — the rake surface change (RD4's shape)

**Current state:** the SOURCES + NUMBERS block is byte-identical between `task start` (`integrator/lib/tasks/integration.rake:18-91`) and `task force_start` (`integrator/lib/tasks/integration.rake:95-168`) — 45 lines duplicated once already (SPIKE Finding 2). Adding `integration:preview` as a third caller of the same block, without any change, would triple the duplication.

**Option A — extract the SOURCES+NUMBERS composition into a shared place**, called from `start`, `start_skip_throughput` (renamed `force_start`), and the new `preview`.

- Pros: three call sites reading the exact same ~30 lines (`integrator/lib/tasks/integration.rake:29-77` shape) is the "Rule of Three" trigger textbook definitions point to.
- Cons: directly tensions with 4Shark's own documented threshold — `~/.claude/docs/NO-PREMATURE-DRY.md:63-68` puts the bar at **10+ repetitions** ("3 repetitions: ⚠️ Minimum - But still prefer waiting", "Only after 10+ repetitions should you consider abstracting", `NO-PREMATURE-DRY.md:59,66`). By that document's own table, 3 occurrences is explicitly *not yet* the accepted trigger at 4Shark, even though it is the generic "Rule of Three" number cited elsewhere in the industry.
- Note: this block is closer to "compose and print a fixed report" than the validation-logic example the doc argues against (`NO-PREMATURE-DRY.md:108-176`, where different callers plausibly need different rules) — all three callers print the identical thing, so the "will all consumers use it the same way?" test (`NO-PREMATURE-DRY.md:207-208`) answers yes today. Whether that distinction is enough to justify extracting below the 10x threshold is exactly the kind of pattern/architecture call `ASK-DONT-DECIDE.md` reserves for the engineer, not this document.

**Option B — keep the block inline a third time**, following `NO-PREMATURE-DRY.md` to the letter.

- Pros: no new abstraction, no indirection, matches the doc's stated preference "when in doubt, repeat" (`NO-PREMATURE-DRY.md:238`).
- Cons: three ~45-line near-identical blocks in one file; any future change to the NUMBERS computation (e.g. resolving the `last_job.ends_at` vs `job.fetch_since` discrepancy noted in SPIKE Finding 4) must be applied in three places by hand.

Neither option is chosen here — this is Pattern Priming territory at `/execute` time (`~/.claude/docs/CODE-PATTERN-DISCIPLINE.md`), surfaced here only because RD4 makes a third occurrence unavoidable.

**Other RD4 mechanics to fold into the same change, regardless of A/B:**

- `preview` prints SOURCES + NUMBERS and exits — must NOT reach the `$stdin.gets` line (`integration.rake:79-80`) at all, since Finding 1 established that line hangs a non-tty session indefinitely.
- The rename `force_start` → `start_skip_throughput` (working name) has near-zero blast radius: SPIKE confirmed `force_start` has no callers besides its own definition, and `integration:start` is not referenced anywhere else in `integrator` or `terraform` — the scheduled task is the separate `integration:cron` (`SPIKE.md:352`).
- `AUTO_ACCEPT` (working name) is read inside the start path to skip `$stdin.gets` and branch straight to `Job::Starter.perform_async(true)` (mirroring `integration.rake:159-162`'s existing `when 'y'` branch) — reusing the existing tasks per RD4, not adding parallel ones.
- `integrator/CHANGELOG.md` needs an entry per project convention (cited by SPIKE as `integrator/CHANGELOG.md:1-25` for the repo's changelog format — not re-read in this pass, no new information to add beyond SPIKE's citation).

### 2. integrator repo — trigger path shape (grounding RD3)

`bin/ecs run <integrator> [command] [timeout]` (`integrator/bin/ecs:163-166`) takes the command as its second positional argument, defaulting to `bundle exec rails console` when omitted. The skill's two invocations would be shaped as:

```bash
bin/ecs run <client> "bundle exec rake integration:preview" 300
bin/ecs run <client> "AUTO_ACCEPT=1 bundle exec rake integration:start_skip_throughput" 300
```

Both pass through the same `cmd_run` path (spin up runner task → wait for `RUNNING` → wait for the `ExecuteCommandAgent` → `aws ecs execute-command --interactive`, `integrator/bin/ecs:206-331`) — no code branch inside `bin/ecs` distinguishes preview from accept; the distinction lives entirely in which rake task string is passed. This confirms RD3 needs zero changes to `bin/ecs` itself, only to what string the skill supplies as `$2`.

`Job::Starter.perform_async` (no arg, `skip_throughput` defaults false, `integrator/app/workers/job/starter.rb:7`) vs `Job::Starter.perform_async(true)` (`integration.rake:161`, the existing `force_start` branch) is the exact mapping RD5 already resolved: the skill's accept step must land on the `perform_async(true)` branch, i.e. whatever rake task becomes `integration:start_skip_throughput` must keep calling `Job::Starter.perform_async(true)`, not the plain form.

### 3. terraform repo — confirm no change, and the per-client file-location problem

RD1 reads existing `desired_count` values — this plan requires **zero Terraform edits**. Confirmed no write path exists or is needed.

What RD1 does not resolve: the skill needs to find the *right* `.tf` file(s) for an arbitrary client, and the layout is not uniform (auxiliary file, `manual-integrator-run-skill_terraform-desired-counts_1.md`):

| Client key (environments.json) | Terraform directory | File(s) holding `module "web"`/`module "worker"` |
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

Neither the directory name (`integrator-atento` serves four client keys) nor the file name follows a single derivable rule from the client key alone — `commcenter-staging`'s directory drops the `-staging` suffix but its filename gains a `_staging` suffix; `atento-br` gains a `_br` filename suffix but its directory drops the country entirely. **`~/.claude/skills/integrators/environments.json` does not currently carry this mapping** — it documents what each client *is* (source model, VPN, deploy policy), not where its Terraform lives (confirmed by reading the full file: no `terraform` or `compute` key anywhere in it).

**Option A — heuristic resolution at read time.** Derive directory as `terraform/integrator-{root}/` where `{root}` strips any `-staging`/`-br`/`-mx`/`-co`/`-cl` suffix recognized from a small country/environment-suffix list, then glob `compute*.tf` inside it and grep each file found for `module "web"`/`module "worker"` blocks, disambiguating by filename suffix when more than one file matches.
- Pros: no new metadata file to maintain; self-updating if Terraform gains a new client following the existing naming convention.
- Cons: the suffix-stripping rule is itself a guess codified in a skill script — a genuinely new client naming pattern (a hypothetical fifth Atento country, or a client whose canonical name itself contains a hyphen) could break the heuristic silently; per Finding 6 the pattern is already inconsistent enough (compare `commcenter-staging` vs `atento-br`) that a single stripping rule needs explicit per-suffix handling, not a generic regex.

**Option B — curated per-client field added to `environments.json` (or a sibling metadata file).** Add e.g. `"terraform_compute_file": "integrator-atento/compute_br.tf"` to each client entry, mirroring the existing pattern of curating non-tag metadata in this exact file (`environments.json:3` already states its purpose is "metadata that does NOT come from AWS tags").
- Pros: zero parsing ambiguity; directly matches the precedent this file already sets for client-specific facts Terraform doesn't expose as a tag; a wrong or stale path fails loudly (file not found) rather than silently matching the wrong file.
- Cons: one more per-client fact to keep in sync by hand if a client's Terraform files are ever reorganized — the same class of drift risk the SPIKE's first trade-off table already named for the *count itself* (`SPIKE.md:292`), but here applied only to the *file path*, which changes far less often than `desired_count` does.

Both options still need, inside whichever file is read, a small grep/awk (or equivalent) step to pull the literal `desired_count = N` value out of the `module "web" { ... }` / `module "worker" { ... }` HCL blocks — reading raw HCL from a skill script, flagged as a con in SPIKE's own first trade-off table (`SPIKE.md:290`), applies to both options here since RD1 already settled on Terraform as the source.

### 4. dot-claude repo — the new `/integrators` action

**Control-flow enumeration**, each step tagged with what's reused vs new:

1. **Resolve client** — exact-match against `environments.json` keys/aliases, per the skill's existing lookup convention (`~/.claude/skills/integrators/SKILL.md:56-69` fallback behavior) and the team-wide "Lookup Resolution — Exact Match Wins" rule. *Reused.*
2. **Check for a raisable Mongo** — `bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh --client <name> --role database` (`~/.claude/skills/ec2-instances/SKILL.md:44-45`); if it returns instances, start them via `bash ~/.claude/scripts/start-instance.sh --region sa-east-1 <instance-id...>` (`ec2-instances/SKILL.md:74-76`); if empty, skip (Finding 6: commcenter and all four Atento countries have no `AWS_INSTANCE_IDS`-mapped Mongo — this is expected, not an error). *Reused wholesale.*
3. **Read web/worker desired counts from Terraform** — new logic per section 3 above (Option A or B). *New.*
4. **Scale web + worker to those counts** — two calls to `bash ~/.claude/scripts/ecs-scale.sh --region sa-east-1 --cluster integrator-{client}-cluster --service integrator-{client}-{web|worker}-service --desired-count {N}` (`SKILL.md:96-101`, the skill's existing scale-up action). *Reused wholesale.*
5. **Wait for readiness** — poll `aws ecs describe-services --cluster ... --services <web-service> <worker-service>` until both reach `runningCount == desiredCount` (RD2). *New* — no existing script performs this wait; see the "readiness-wait implementation" decision below.
6. **Trigger preview** — `bin/ecs run <client> "bundle exec rake integration:preview" 300` (section 2). *New command, existing tool.*
7. **Present NUMBERS, STOP for engineer approval** — no execution continues until the engineer replies. *New, but matches the skill's existing "confirm before bulk scale-down" pause pattern (`SKILL.md:108-111`) structurally.*
8. **On approval, trigger accept** — `bin/ecs run <client> "AUTO_ACCEPT=1 bundle exec rake integration:start_skip_throughput" 300` (section 2). *New command, existing tool.*
9. **Capture a second NUMBERS reading and report divergence** — re-run `integration:preview` via the same runner mechanism and diff the two outputs, reported to the engineer as informational. *New.*

**Fork exposed by Phase 0 — execution model.** Every existing `/integrators` action (scale up/down, logs) is driven by Claude issuing Bash tool calls directly inside the conversation (`SKILL.md:90-117`) — the skill never generates a script for the engineer to run by hand. `/integration-debug` is the opposite precedent: it "never executes anything ... even read-only AWS commands ... are generated as text the engineer runs" (per its skill description). RD8 places this new action inside `/integrators`, whose established pattern is direct execution — but RD8 doesn't by itself confirm that `bin/ecs run`'s interactive ECS Exec session (steps 6 and 8) can be driven that way; that is exactly what Phase 0 tests.

- **If Phase 0 passes** (with or without Fallback A): the action follows `/integrators`' existing direct-execution pattern for every step, including 6 and 8.
- **If Phase 0 requires Fallback A** (raw `run-task` + CloudWatch Logs polling, no live interactive stream): still direct execution, just a different underlying mechanism for steps 6, 8, and 9 (poll `describe-tasks` for `STOPPED`, then read the log group instead of capturing a live session).
- **If Phase 0 fails outright even with Fallback A** (not currently expected, but the SPIKE did not test either path): steps 6, 8, and 9 would have to fall back to `/integration-debug`'s prose-generation model for those three steps only, while steps 1–5 and 7 stay directly executed — a split-execution-model action, which would be a new shape for `/integrators` not seen in the skill today.

**Readiness-wait implementation (step 5).** `Bash Single-Line Policy`/`Command Safety Policy` block "long leading sleep loops" in the main session and steer toward the `Monitor` tool for "wait until done" flows. `bin/ecs run` itself implements exactly this kind of poll loop inline in bash (`integrator/bin/ecs:234-263`, `for` loop with `sleep 5`, 60 attempts) as a structural precedent that such a loop is an accepted shape *inside a script*, distinct from the main session issuing repeated `sleep`-then-check Bash tool calls itself. Two shapes for step 5:
- **Inline in a new script** (bash `for`/`sleep` loop calling `aws ecs describe-services`, mirroring `bin/ecs`'s own pattern) — one Bash tool call, bounded internally.
- **Main session polls via the `Monitor` tool pattern** against a backgrounded describe-services-in-a-loop command — avoids embedding a new bash loop, but is a materially different mechanism than every other step in this action (which are all single synchronous tool calls).

**Script vs prose placement.** Existing `/integrators` actions are prose in `SKILL.md` orchestrating calls to two small standalone scripts (`integrator-services.sh`, and the shared `ecs-scale.sh`). This new action is materially more stateful (a mid-flow human-approval pause, a wait loop, a compare-then-report step) than any existing action. Two shapes:
- **Pure prose extension of `SKILL.md`**, matching the existing style exactly — Claude executes each atomic command per the enumerated steps above, across as many Bash tool calls as needed, pausing naturally at step 7.
- **A new dedicated script** (e.g. `skills/integrators/scripts/integration-run.sh`) bundling the no-decision mechanical steps (2–5, or 2–5 plus 9) into fewer tool calls, with steps 6–8 (the parts requiring human judgment or `bin/ecs run`) left to `SKILL.md` prose. Reduces round-trips but pulls Terraform-file-parsing logic (section 3) into a bash script that itself needs testing, and partially breaks from the existing pattern where scripts here are thin AWS-tag-discovery wrappers, not multi-step orchestration.

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| Rake SOURCES+NUMBERS duplication (3rd occurrence) | Extract shared composition (Option A) / triple the inline block (Option B) | A matches generic Rule-of-Three but undercuts 4Shark's own 10+ threshold; B follows the doc to the letter but triples a 45-line block | ☐ |
| Per-client Terraform file location | Heuristic glob+suffix-strip (Option A) / curated `environments.json` field (Option B) | A is self-maintaining but a guess codified in a script; B is unambiguous but one more hand-maintained fact | ☐ |
| Execution model for steps 6/8/9 (contingent on Phase 0) | Direct interactive capture / Fallback A (`run-task` + log polling) / prose-generation for those steps only | Determined largely by Phase 0's outcome, not a free choice | ☐ |
| Readiness-wait (step 5) implementation | Inline bash loop in a new script / `Monitor`-tool-driven poll in the main session | Script mirrors `bin/ecs`'s own precedent; Monitor avoids a new bash loop but is a different mechanism than the rest of the action | ☐ |
| New action: script vs prose placement | Pure `SKILL.md` prose (existing pattern) / new dedicated orchestration script | Prose matches convention exactly; a script reduces round-trips at the cost of new, more complex, harder-to-test bash | ☐ |
| Timing of the "second NUMBERS reading" (step 9) | Immediately after triggering accept / after the job's async pipeline completes | Immediately-after uses the same `last_job.ends_at` watermark as the first reading (Finding 4) — a real divergence only appears if something else (a race, source-side change) shifted state in between; after-completion would need a different comparison basis entirely | ☐ |

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Phase 0 assumption unproven — `bin/ecs run` driven by a non-tty Bash tool has never been tested for a non-blocking command | HIGH — invalidates RD3's chosen mechanism if wrong | Run Phase 0 (this document, section "Phase 0") before writing any integrator or dot-claude code |
| RD5's throughput-skip choice is "resolved by derivation," engineer flagged wanting to confirm at PLAN review (`SPIKE.md:355`) | MEDIUM — if reversed, RD4's rake shape and the skill's accept-step task name both change | Confirm explicitly before `plan-composer` writes `PLAN.md` |
| Client→count lookup brittleness across non-uniform Terraform layouts | MEDIUM — redebrasil's second monthly schedule's `DesiredCount` and Atento CL's active `DesiredCount` were never read (SPIKE "What remains uncertain"); if either differs from the resting Terraform value the skill would scale to a stale/wrong count for those two clients specifically | Read the two unresolved schedule payloads (`aws scheduler get-schedule`) before onboarding redebrasil or atento-cl into this action, even though RD1 does not use the schedule as the primary source |
| Per-client deploy granularity for the integrator rake change is unconfirmed | MEDIUM — sequencing risk: the skill cannot successfully drive a client whose deployed integrator image predates the `integration:preview`/`start_skip_throughput` rake tasks, and this pass did not confirm whether one deploy trigger updates every client or one client at a time | Read `~/.claude/docs/DEPLOY-REFERENCE.md`'s integrator section before sequencing the rollout across clients (not read in this pass) |
| Readiness-wait loop mechanism constrained by the Bash Single-Line/Command-Safety sleep-loop rules | LOW-MEDIUM | Resolve the technical-decision row above before `/execute` |
| Second-NUMBERS-reading semantics (Finding 4's watermark discrepancy) | LOW — reporting/informational only, does not affect whether the job actually starts | Resolve the timing technical-decision row above; document the interpretation in `SKILL.md` once decided |

## Open questions for the engineer

- Confirm RD5 (the skill's accept step always skips the throughput guard) — SPIKE already flagged this as "resolved by derivation... engineer to confirm on PLAN review" (`SPIKE.md:355`).
- Which per-client Terraform-file-location mechanism (heuristic vs curated field)?
- Does deploying the integrator update all clients at once, or is each client's deploy triggered independently? (Not researched — `DEPLOY-REFERENCE.md` was not read in this pass; needed to sequence the rollout.)
- Should the readiness-wait (step 5) live in a new script or be driven via the `Monitor` tool from the main session?
- Should the new action be pure `SKILL.md` prose (matching every existing `/integrators` action) or get a dedicated orchestration script?
- When should the "second NUMBERS reading" (step 9) actually run — immediately after triggering accept, or after the job's async pipeline finishes?
- Extract the SOURCES+NUMBERS block now that a third caller exists, or keep tripling the inline duplication per `NO-PREMATURE-DRY.md`'s literal 10+ threshold?

## Cross-repo execution sequencing

1. **Phase 0 validation** — no repo change required; can run today against `commcenter-staging`'s existing runner service. Must resolve before any of the following.
2. **integrator repo PR** — add `integration:preview`, rename `force_start` → `start_skip_throughput`, wire `AUTO_ACCEPT`, resolve the duplication technical decision, update `CHANGELOG.md`. Must be merged AND deployed to a given client's stack before the skill's new action can be exercised against that client (deploy granularity itself is an open question above).
3. **terraform repo** — no PR needed for RD1 itself. A dot-claude-side metadata addition (Option B in section 3) would NOT touch this repo at all; Option A (heuristic parsing) also touches no Terraform files, only reads them.
4. **dot-claude repo PR** — new `/integrators` action (prose and/or script per the technical decision), optionally an `environments.json` metadata addition (Option B). Can be developed and merged independently of step 2's deploy timing, but is only end-to-end usable against a given client once that client's integrator image includes step 2's rake changes.

Steps 2 and 4 can be developed in parallel once Phase 0 passes; step 2's deployment to each target client is the actual gate on when the new `/integrators` action becomes usable for that client.

## Sources

- `integrator/bin/ecs:1-417` (read in full) — `cmd_connect` (73-158), `cmd_run` (163-332), `cmd_cleanup` (337-405); specifically `163-166` (signature), `193-204` (cleanup trap), `206-331` (run→wait→exec sequence), `325-331` (the interactive execute-command call)
- `integrator/lib/tasks/integration.rake:1-169` (read in full) — `task start` (18-91), `task force_start` (95-168), `$stdin.gets` at 80/157, `Job::Starter.perform_async` at 84 vs `Job::Starter.perform_async(true)` at 161
- `~/.claude/skills/integrators/SKILL.md:1-133` (read in full) — scale-up action (90-104), scale-down confirmation pattern (106-117), MongoDB-start note (130-132), fallback lookup (58-69)
- `~/.claude/skills/integrators/environments.json:1-166` (read in full) — confirms no `terraform`/`compute` file-path field exists per client
- `~/.claude/skills/ec2-instances/SKILL.md:1-89` (read in full) — filter commands (34-49), start-instance wrapper (70-78)
- `~/.claude/scripts/ecs-scale.sh:1-62` (read in full) — the shared scale wrapper
- `~/.claude/docs/NO-PREMATURE-DRY.md:1-248` (read in full) — the 10+ repetitions threshold (59-68), "duplication > wrong abstraction" (70, 232-238)
- `~/.claude/plans/active/spike/manual-integrator-run-skill/SPIKE.md:1-365` (read in full) — all Findings, Trade-offs, and RD1-RD8
- `~/.claude/plans/active/spike/manual-integrator-run-skill/manual-integrator-run-skill_terraform-desired-counts_1.md:1-70` (read in full) — per-client Terraform layout backing section 3's table
