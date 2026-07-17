# SPIKE — ECS task-definition pointer lag: testing "Terraform owns content, GHA only replicates"

## Investigation question

The engineer's model, verbatim (translated): *Terraform should own the task definition's content — env vars, secrets, everything except the image tag and the command — and GitHub Actions should only copy the previous revision forward and overlay image+command. If Terraform's apply reliably produces a new revision reflecting the config, GitHub Actions needs no change.*

This document treats that model as a hypothesis to test, not a premise to confirm. Four things were asked: (1) reconstruct `terraform` PR #711's actual sequence from CloudTrail — did the same apply that deleted `/<stack>/DD_API_KEY` also register a clean revision, and what did the service's pointer reference at that moment; (2) where does the engineer's model NOT hold in the current code, specifically around the `command` asymmetry and any path where a service's pointer could land on a Terraform-registered revision; (3) how long the window stays open and what closes it; (4) the fix space, holding "Terraform stays the owner, GHA does not change" as a fixed constraint.

## Sources consulted

- `aws cloudtrail lookup-events` (five separate queries: `DeleteParameter`, `RegisterTaskDefinition` ×2 pages, `UpdateService`, `RunTask`) — see auxiliary `pointer-lag_cloudtrail_1.md` §§1–4. Reconstructs the incident's exact sequence.
- `aws ecs describe-task-definition` on `beta-001-worker-user:210` and `:211` — see auxiliary `pointer-lag_cloudtrail_1.md` §6. Confirms the content difference between the last GHA revision and Terraform's clean revision.
- `~/Projects/4Shark/terraform/modules/ecs_service/main.tf` and `variables.tf`, `~/Projects/4Shark/terraform/app-beta-001/main.tf` and `terraform.tfvars` — see auxiliary `pointer-lag_cloudtrail_1.md` §7. Confirms the `command = null` behavior is permanent module/config state, not incident-specific, and traces the one code path where a service's initial pointer is set directly to a Terraform revision.
- `gh pr view 711 --json ...` and `git show` on the merge commit — timestamp anchor for the CloudTrail queries (`pointer-lag_cloudtrail_1.md` header).
- `~/Projects/4Shark/dot-claude-plans/active/terraform/datadog-key-standard/PLAN.md:33-58` — the incident's own narrative record, used as a comparison point against the raw CloudTrail timestamps (§5 of the auxiliary), not as ground truth for timing.
- Two prior spikes, read in full and not re-derived: `~/Projects/4Shark/dot-claude-plans/active/spike/terraform-ignore-changes-task-definition-drift/SPIKE.md` (F1–F25) and `~/Projects/4Shark/dot-claude-plans/active/spike/ecs-taskdef-ownership-boundary/SPIKE.md` (Findings 1–7). Cited as "prior spike F-N" / "prior spike Finding N" below.
- Two `WebSearch` queries (expand/contract naming for this specific case; `track_latest`/`command` interaction) — both negative results, no fetchable primary source with a quote, recorded in auxiliary `pointer-lag_sources_1.md`.

## Findings

### Finding 1 — [VERIFIED-HERE] The same terraform apply that destroyed each stack's parameter also registered a clean revision for every task-definition family in that stack

**Evidence:** For all four stacks, the entire batch of `RegisterTaskDefinition` calls by `paulo@4shark.com.br` (the Terraform identity, `terraform-provider-aws/6.53.0` user agent) lands within 1–2 seconds of that same stack's `DeleteParameter` call:

| Stack | `RegisterTaskDefinition` batch (BRT) | `DeleteParameter` (BRT) | Gap |
|---|---|---|---|
| beta-001 | `15:43:45` (14 families) | `15:43:45` | same second |
| demo-001 | `15:46:05` (13 families) | `15:46:04` | 1s |
| atento-001 | `15:46:30`–`:31` (14 families) | `15:46:30` | same second |
| shared-001 | `15:56:21` (18 families) | `15:56:23` | 2s |

**Source:** `pointer-lag_cloudtrail_1.md` §§1–2 (full per-family family-name lists and raw JSON).

**Significance:** this directly answers the first half of question (1): yes, one `terraform apply` per stack did both — registered a new task-definition revision reflecting the config (parameter reference removed) AND destroyed the parameter, in the same run. Terraform's default parallel graph execution (independent resources scheduled concurrently) is the mechanical reason the two unrelated actions land within a 1–2 second window rather than in a strict sequence. This is the engineer's model behaving exactly as described — Terraform DID reliably produce a new revision reflecting the config on this apply.

### Finding 2 — [VERIFIED-HERE] No `UpdateService` call moved any service's task-definition pointer during the destroy window — the ONLY service-touching call was an autoscaling `desiredCount` change with no `taskDefinition` argument

**Evidence:** the single `UpdateService` event in the entire 18:40–19:00Z window is `Lambda-shared-001-worker-system-autoscaling` calling `{"cluster":"shared-001-cluster","service":"shared-001-worker-system-service","desiredCount":1,"forceNewDeployment":false,"dryrun":false}` — no `taskDefinition` key present at all.

**Source:** `pointer-lag_cloudtrail_1.md` §3.

**Significance:** this is the direct, positive confirmation of `ignore_changes = [task_definition]`'s effect in this incident: not merely "Terraform is configured to ignore it" (already established by the prior spike's F1), but "in this specific apply, across four stacks, nothing actually moved any service's pointer." Every worker service on every stack kept pointing at whatever revision it held immediately before the apply.

### Finding 3 — [VERIFIED-HERE] The revision each service actually held through the incident (the last GHA revision) still referenced the parameter; Terraform's own revision, registered in the same apply, did not

**Evidence:** `beta-001-worker-user:210` (registered by `app-beta-001`, i.e. GHA, at `2026-07-15T07:18:30.241000-03:00`, hours before the incident) carries `DD_API_KEY` in its `secrets` list, sourced from `arn:aws:ssm:...:parameter/beta-001/DD_API_KEY`, alongside 15 other secrets. `beta-001-worker-user:211` (registered by `paulo@4shark.com.br`, i.e. Terraform, at the exact moment of the destroy) carries the identical 15-secret list **minus** `DD_API_KEY`.

**Source:** `pointer-lag_cloudtrail_1.md` §6 (both `describe-task-definition` outputs, verbatim).

**Significance:** this is the mechanism, confirmed at the content level, not just inferred from architecture. `:210` — the revision the service was actually pinned to throughout (Finding 2 established nothing moved the pointer) — still had a live dependency on the now-destroyed parameter. `:211` — the clean revision Terraform registered in the very same apply — existed in AWS as an `ACTIVE` task definition the whole time, completely unused by the running service. The engineer's model's second half ("if Terraform's apply reliably produces a new revision ... GHA needs no change") is contradicted by this specific incident: Terraform's apply DID reliably produce the clean revision, and it made no difference, because nothing ever adopts a Terraform-registered revision for a plain-`ECS`-controller worker service under the current architecture — adoption happens only on the next GHA deploy, an event with no fixed relationship to the apply that changed the config.

### Finding 4 — [VERIFIED-HERE, negative result] CloudTrail's Event History does not surface the actual task-placement failures as distinct events

**Evidence:** three `RunTask` events fall inside the destroy-to-recovery window, none carrying an `errorCode` or `errorMessage`.

**Source:** `pointer-lag_cloudtrail_1.md` §4.

**Significance:** the `ResourceInitializationError: unable to place a task ... Fetching secret data from SSM Parameter Store` failures the incident record describes are not visible via `aws cloudtrail lookup-events` in this window — they appear to occur inside the ECS agent's task-startup sequence, downstream of an already-accepted scheduling call, which is a data-plane failure rather than a distinct failed management-event API call. **This is an honest gap, not a reconstruction**: the actual placement-failure evidence for this incident lives in the incident record's own text (`datadog-key-standard/PLAN.md:35`), not in CloudTrail, and this spike did not find a CloudTrail-native way to pull it.

### Finding 5 — [VERIFIED-HERE] The incident record's stated destroy time does not match the raw CloudTrail timestamps

**Evidence:** `datadog-key-standard/PLAN.md` states *"Duration ≈ 1h05 (parameters destroyed 16:40, last stack recovered 17:45 BRT)"*. The CloudTrail `DeleteParameter` events place the four destroys between `15:43:45` and `15:56:23` BRT — 44 to 57 minutes earlier than "16:40".

**Source:** `pointer-lag_cloudtrail_1.md` §5.

**Significance:** flagged as a factual discrepancy between the incident's own narrative record and the primary CloudTrail log; this spike does not resolve which value is correct or why they diverge, only surfaces that they do. Anything downstream that leaned on "16:40" as the destroy time (e.g., recovery-duration arithmetic) should be re-checked against the CloudTrail timestamps above if precision matters.

### Finding 6 — [VERIFIED-HERE] `command = null` on a Terraform-registered worker/web revision is permanent, current-state module behavior — not something specific to the #711 incident

**Evidence:** `modules/ecs_service/main.tf:30` renders `command = length(var.command) > 0 ? var.command : null`; `variables.tf:132-136` defaults `var.command` to `[]`; `app-beta-001/main.tf:450` wires `command = lookup(each.value, "command", [])`. A grep of `app-beta-001/terraform.tfvars` for `command` shows the key present **only** on the four `cron-*` scheduled-task blocks — no worker or web service block sets it.

**Source:** `pointer-lag_cloudtrail_1.md` §7.

**Significance:** the sidekiq/puma/rails startup command for every worker and web service exists **nowhere in Terraform's configuration** — only inside the GHA deploy workflow. This is not a bug introduced by #711; it is the permanent shape of every stack's config today. The consequence: any task launched directly from a Terraform-registered revision for a worker or web service runs the container image's bare default `CMD`, not the application's actual entrypoint, on every stack, today, independent of the #711 incident.

### Finding 7 — [VERIFIED-HERE] A service's INITIAL pointer, at creation, IS set to the Terraform-registered revision — the command-null risk is not purely latent, it has one confirmed live path

**Evidence:** `modules/ecs_service/main.tf:79`: `task_definition = aws_ecs_task_definition.this.arn` — this is the argument Terraform passes when the `aws_ecs_service` resource is first created. The `ignore_changes = [task_definition]` lifecycle block only suppresses Terraform from touching this argument on an **already-existing** resource; it has no effect on what value gets set at creation.

**Source:** `pointer-lag_cloudtrail_1.md` §7 (`main.tf:71-79`, `152-163`).

**Significance:** the brief asked whether ANY path lets a service's pointer come to hold a Terraform-registered revision. This finding confirms one, directly from the code: **first-ever creation of a service.** Combined with Finding 6, a brand-new worker service, on its very first `terraform apply`, would launch tasks against a revision with `command = null` — running the bare image default — until the first GHA deploy overwrites it. Whether this is currently exercised by any live stack was not tested (would require either creating a service or finding one in `terraform apply` output history), so this is a **confirmed code path**, not an observed incident.

### Finding 8 — [VERIFIED-HERE] `replace_triggered_by = [terraform_data.lb_config]` has no live trigger surface for worker services — it is a load-balanced-service-only mechanism

**Evidence:** `terraform_data.lb_config`'s `input` is `length(var.load_balancers) > 0 ? jsonencode(...) : null` — `null` whenever a service has no load balancer, which is true of every worker service. A `null` input to `terraform_data` never changes value across applies (there is nothing to diff), so `replace_triggered_by` referencing it has nothing to fire on for a service with no load balancer.

**Source:** `pointer-lag_cloudtrail_1.md` §7 (`main.tf:71-74`, inline comment: *"Track load balancer target group ARNs to force service replacement when target groups are recreated (e.g., VPC migration)."*).

**Significance:** the brief's second named candidate path (service recreated by `replace_triggered_by`) does **not** apply to worker services under current configuration — only to load-balanced (web) services, and only when target-group ARNs actually change (e.g. a VPC migration). Whether a forced replacement of a `CODE_DEPLOY`-controller web service can even set `task_definition` directly at re-creation (given prior spike Finding 2's confirmed AWS API rejection of `task_definition` updates on `CODE_DEPLOY` services) is **not resolved here** — see uncertainties below; this spike did not test a live replacement.

### Finding 9 — [UNVERIFIED / negative result] No community-named pattern was found for "expand/contract applied to a launch-time-resolved resource referenced by a live task definition"

**Evidence:** a targeted `WebSearch` for this exact shape returned generic Terraform lifecycle material (the `lifecycle` meta-argument reference, the `removed` block) with no page found naming a pattern specific to this case.

**Source:** `pointer-lag_sources_1.md` §1.

**Significance:** consistent with, not contradicting, the prior spike's own Finding 5 (`ecs-taskdef-ownership-boundary/SPIKE.md`), which reached the same "not named" conclusion via a different search. Two independent searches across two spikes, neither turning up a name, is weak-but-consistent evidence that the practice — if done at all — is not documented under a settled term.

### Finding 10 — [UNVERIFIED / negative result] `track_latest` was not found to interact with, or resolve, the `command`-null risk

**Evidence:** a targeted `WebSearch` for `track_latest` + `command` interaction returned no issue, blog, or provider doc addressing the intersection.

**Source:** `pointer-lag_sources_1.md` §2.

**Significance:** `track_latest` (prior spike F17) changes which revision a `data`/resource treats as "latest ACTIVE" — a pointer-resolution mechanism. It has no bearing on what CONTENT a Terraform-authored revision carries; that is downstream of `var.command` (Finding 6), a variable `track_latest` was never designed to touch. The two problems — "which revision does Terraform consider current" and "what does the Terraform-authored revision actually contain" — are independent, and closing one does not close the other.

### Finding 11 — [MAIN-TRACE] The window is closed today, but only as an observed fact, not a structural guarantee

**Evidence:** per the briefing, main swept all 4 stacks' 37 services this session and found no ACTIVE revision referencing the destroyed parameter.

**Source:** stated in the spawning briefing; not re-derived in this spike.

**Significance:** today's absence of a live bomb is a snapshot, not a guarantee against recurrence — Findings 1–3 show the mechanism that created the window in the first place (a Terraform apply that changes config while `ignore_changes = [task_definition]` prevents adoption) is still live in the module today, unchanged. Nothing found in this spike closes that mechanism structurally; see "what remains uncertain" and the fix-space options below.

## Trade-offs surfaced

| Aspect | What was confirmed | What was NOT confirmed / left open |
|---|---|---|
| "Terraform's apply reliably produces a new revision reflecting config" (engineer's premise, part 1) | **Confirmed true** in this incident — Finding 1 | Whether this holds on EVERY apply where `container_definitions` changes (e.g. removing only a `secrets` entry) was not independently tested against the provider's diff logic this session — inherited as an open question, see prior spike F2/F3 for the architectural claim that Terraform owns content |
| "GHA needs no change if Terraform reliably updates content" (engineer's premise, part 2) | **Contradicted by this incident** — Finding 3: Terraform's clean revision existed the whole time and made no difference, because nothing adopts it without a GHA deploy | What WOULD make Terraform's apply sufficient on its own is exactly the fix-space question below (moving the pointer, or closing the window some other way) |
| `command = null` risk | **Confirmed as permanent, current-state, code-verified fact** (Finding 6), not incident-specific | Whether any stack has ever actually launched a worker task from a command-null revision (this spike found the code path, Finding 7, but did not find or test an observed occurrence) |
| Paths to a service pointer holding a Terraform revision | First-ever creation: **confirmed live** (Finding 7). `replace_triggered_by`: **confirmed inert for workers** (Finding 8) | Rollback (`-replace`) and whether a `CODE_DEPLOY` service replacement can even set `task_definition` at re-creation — neither tested |

## What remains uncertain

- Whether a `terraform apply -replace=aws_ecs_service.this` (a manual rollback/force-recreate) on a worker service would reproduce the same "Terraform-set pointer with `command=null`" state as first-creation (Finding 7) — the code path (`main.tf:79`, no special-casing for replace vs create) suggests yes, but this was not exercised live.
- Whether a `CODE_DEPLOY`-controller service (web) that gets recreated via `replace_triggered_by` can even set an initial `task_definition` from Terraform at all, given the AWS API's confirmed rejection of `task_definition` UPDATES on `CODE_DEPLOY` services (prior spike Finding 2) — creation and update may be governed by different API rules; not tested here.
- How long a worker service can sit un-deployed (e.g. `desired_count = 0` for months) while carrying an increasingly stale GHA-registered pointer whose referenced secrets Terraform has since destroyed — the mechanism (Findings 1–3) says the window's length is bounded only by "time until the next GHA deploy for that service", which could be arbitrarily long for a rarely-scaled worker; no specific stack's history was checked for this.
- Whether CloudTrail's Event History (or `s3://4shark-cloudtrail`) has ANY event type that would have surfaced the `ResourceInitializationError` placement failures directly — Finding 4 checked `RunTask` only; other event names (e.g. an ECS-internal task state-change event, if CloudTrail logs one) were not searched.

## Suggested options for main and the engineer

Per the standing instruction, no ranking and no recommendation — options only, each grounded in a Finding above.

- **Option A — Leave the architecture as-is, treat #711 as resolved by the existing incident response (a GHA deploy per stack), and rely on the sweep discipline (Finding 11) to catch future occurrences.** Grounded in: Finding 11 (today's window is closed) and the fact that the only observed failure mode (Finding 1–3) requires BOTH a Terraform config change to a live-referenced resource AND no GHA deploy happening soon after — a narrower condition than "any Terraform apply on these stacks."

- **Option B — Close the `command`-null gap directly, independent of the pointer-lag question, by populating `var.command` in Terraform for every worker/web service** (Finding 6/7). This would not fix pointer lag itself, but it would remove the specific "launches with no command" consequence if a service ever DOES end up pointed at a Terraform revision (first creation, Finding 7; a future replace path, Finding 8's open question).

- **Option C — Adopt an expand/contract discipline specifically for "destroy a launch-time-resolved resource referenced by a live task definition"**: remove the reference from application code/config → deploy (adopt the clean revision) → THEN destroy the resource, as two ordered changes rather than one apply. Grounded in: Finding 1–3 (the mechanism is exactly "config changed and destroy happened in the same apply, with no intervening deploy to adopt the change"); Finding 9 notes no source names this exact pattern, so this option has no vendor/community endorsement found, only the mechanism's own shape as justification.

- **Option D — Build a mechanical guard at the `terraform apply` boundary** that cross-references the destroy-set (from the saved plan, per `TERRAFORM-POLICY.md`) against each affected stack's LIVE task-definition secrets (via `describe-services` → `describe-task-definition`), and flags — not blocks — when a destroyed resource is still referenced by the actually-running revision. This is the prior spike's own Finding 15/`ADR-004` analysis (block is ruled out because there is a legitimate exception — destroying a no-longer-referenced parameter is correct); this spike adds nothing new to that analysis but confirms (Finding 2/3) that the check's data would need to come from the SERVICE's actual current `taskDefinition` field, not from Terraform's state, since Terraform's own revision (Finding 1) can be clean while the service runs something else entirely.

- **Option E — Investigate giving Terraform the ability to move the service pointer for plain-`ECS`-controller services specifically (not `CODE_DEPLOY`), while leaving `CODE_DEPLOY` services untouched.** This is explicitly named in the brief as a question to explore under the "GHA does not change" constraint, but this spike did not investigate it further than the prior spike already did (`track_latest`, Finding 17–22) — no new evidence was gathered here on whether an un-ignored `task_definition` for plain-`ECS` services is safe, and Finding 6/7 suggest that even if the pointer moved, the `command=null` problem (a SEPARATE gap) would still need Option B to avoid launching workers with the wrong command.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim is labeled `[MAIN-TRACE]` (from the spawning briefing, not re-derived), `[VERIFIED-HERE]` (confirmed directly in this session via CloudTrail, AWS read-only, or the repository), or `[UNVERIFIED]` (a searched-for negative result — no primary source found). Large or structured evidence lives in auxiliary files (`pointer-lag_cloudtrail_1.md`, `pointer-lag_sources_1.md`), each referenced above by relative link. The `output-verifier` runs the seven structural checks after the write, including citation integrity and auxiliary-file integrity; the `policy-verifier` checks convention conformance.
