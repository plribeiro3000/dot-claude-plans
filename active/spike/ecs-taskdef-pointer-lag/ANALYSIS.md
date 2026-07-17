# ANALYSIS — ECS task-definition ownership: where the arc stands

> **Purpose.** Three spikes and four merged PRs came out of one incident. This document is the single "where are we" so a future session does not have to reconstruct it from three SPIKE.md files and a chat log. It records what is CLOSED, what is OPEN, and — most importantly — the two wrong models that were believed along the way, so nobody re-derives them.
>
> **Written by main** (not an exception-tier subagent), 2026-07-16. Every claim below traces to a spike Finding or a live verification recorded in this session.

## The incident that started it

Terraform PR #711 destroyed `/<stack>/DD_API_KEY` on four app stacks — dead Heroku-buildpack residue. Pre-apply verification was `terraform plan` → `No changes` on all four, and running tasks stayed healthy. The conclusion drawn was "zero downtime, nothing reads what is being removed". That was wrong: every NEW task failed to place (`unable to place a task. Reason: Fetching secret data from SSM Parameter Store ... invalid parameters: /<stack>/DD_API_KEY`). Worker autoscaling died on all four stacks for ~1h. Detected by a human watching the Sidekiq queue — no alarm fired.

## The mechanism — CONFIRMED, reconstructed from CloudTrail

Established in `ecs-taskdef-pointer-lag/SPIKE.md` Findings 1–3, from raw CloudTrail events (`pointer-lag_cloudtrail_1.md`), verified by `output-verifier` (citation integrity PASS) and `policy-verifier` (ACCEPT_WITH_WARNINGS, zero hard violations).

**It is pointer lag.** In one apply, per stack, within 1–2 seconds (parallel graph execution):

1. Terraform **destroyed** the SSM parameter.
2. The **same apply registered a clean task-definition revision** without it — Terraform did its half correctly.
3. **No `UpdateService` moved any service's pointer.** The only `UpdateService` in the window was an autoscaling `desiredCount` change carrying no `taskDefinition` field. This is a proven absence, not an assumption: the query and its full result set are recorded in the auxiliary file.
4. Each service therefore kept running its last GHA-registered revision, which **still referenced the destroyed parameter** — confirmed by diffing `beta-001-worker-user:210` (what the service held) against Terraform's `:211`.
5. It self-healed only when the next GHA deploy moved the pointer.

**The cause is one line, and it is deliberate:**

```hcl
# terraform/modules/ecs_service/main.tf:152-163
lifecycle {
  ignore_changes = [
    desired_count,
    task_definition, # ← Terraform is forbidden from touching the pointer
    load_balancer,
  ]
}
```

It exists because the deployer (GitHub Actions; CodeDeploy for web) owns the pointer. The side effect is that Terraform also cannot tell a service that it just registered a better revision.

**So the window is:** removal is instantaneous; adoption waits for the next deploy. There is no timing relationship between the two. Its length is bounded only by "time until the next deploy of that service" — which for a worker parked at `desired_count = 0` is unbounded.

**Why `plan` lied and the reviewer could not have caught it:** `plan` compares config against **Terraform's own revision**, which was clean. It never looks at what the service actually runs. #711's author *did* verify — they verified the artefact that lied.

## Two models that were believed and are WRONG — do not re-derive

1. **"Copy-forward makes a removed field immortal."** The first spike's framing: because `deploy-ecs` copies the live revision and overrides only `image`/`command`, Terraform's config supposedly never reaches production. **False, and disproved by live data.** `beta-001-worker-user:211` was registered by a Terraform apply with `command: null`; `:212` was registered by the GHA user one hour later carrying the real command — GHA copied *Terraform's* revision as its base. `describe-task-definition --task-definition <family>` (no revision) returns the latest ACTIVE, so whoever registered last becomes the next copy's base. Terraform's content **does** reach production, one deploy later.

2. **"Restoring `ignore_changes = [container_definitions]` fixes #711."** It does the opposite — it would sever Terraform's path to content entirely and make stale fields genuinely immortal. It was also mis-scoped: `modules/ecs_service` is shared by ~15 stacks (app, integrator ×5, auth-001, onboarding, setup, vpn, app-outbound ×2), and nearly all of them **do** declare `command` — for those, Terraform legitimately owns the content and the ignore would break them. `lifecycle` accepts no variable, so scoping it would require a two-resource `count` split plus a `moved` block per stack.

## What is CLOSED

| Item | State |
|---|---|
| The DD_API_KEY bomb | **Gone.** Swept all 37 services across the 4 stacks (including every `desired=0` service, which were the real suspects): no ACTIVE revision pointed at by any service references the destroyed parameter. Query validated against a known-present term (`API_KEY` → 2 hits) so "empty" could not be a bad search. |
| `command = null` on Terraform revisions | **Fixed and applied.** terraform#733 declares `command` for all 37 services across the 4 stacks. Applied to all four: beta 9/0/9, demo 9/0/9, atento 9/0/9, shared 10/0/10 — all task-definition replacements, **zero `aws_ecs_service` changes**, verified. New revision confirmed live: `shared-001-worker-user:106` now carries `["bundle","exec","sidekiq","-C","config/sidekiq_user.yml"]`. |
| 4 orphaned commission workers (beta ×2, demo ×2) | **Fixed.** app#5242 adds `commission-tiger-shark` and `commission-white-shark` to the beta and demo deploy matrices. They pointed at Terraform revisions with `command: null`, registered by engineer applies, never deployed. They leave the armed state at the next release — only a deploy moves the pointer. |
| `track_latest = true` | **Dead, empirically.** Applied to 3 productive stacks, produced permanent `7 to add / 7 to destroy`; reverted via S3 state version restore. PR #721 closed, branch deleted. Not a bug in the argument: it makes Terraform compare its partial config against the complete live revision. It is also **orthogonal** to pointer lag — it changes which revision Terraform considers current, not who moves the pointer. |
| `platform_version = "LATEST"` drift | **Fixed.** terraform#727, merged. Declaring the default defeats the `Computed` mechanism. |
| Community answer for the CODE_DEPLOY (web) path | **Settled, and it is what we already run.** `ignore_changes` on the whole `task_definition` + `load_balancer` blocks. Three independent sources, including AWS's own CloudFormation blog documenting the identical constraint **outside Terraform entirely** — so this is an ECS API restriction, not a Terraform limitation. The whole `load_balancer` block (not an indexed attribute) because the schema is a `TypeSet` and set elements have no addressable keys. |

## What is OPEN — the only real decision

**Pointer lag itself.** The mechanism is unchanged in the module. Nothing is armed today, but that is a snapshot, not a structural guarantee.

The trigger is narrow — it needs BOTH an apply touching a resource the live task definition references AND no deploy soon after. That is why it fired once in the module's lifetime, not weekly.

Four options, from `ecs-taskdef-pointer-lag/SPIKE.md` § Suggested options. **None is ranked; the engineer decides.**

- **A — Nothing structural.** Narrow trigger, one occurrence, ~1h of stopped autoscaling, self-healed. Every other option costs something.
- **B — Expand/contract as procedure.** Remove the reference → deploy (service adopts the clean revision) → *then* destroy. Two ordered changes, no module change. Cost: discipline — exactly what failed in #711.
- **C — Mechanical guard at apply.** Read the saved plan's destroy-set, cross-reference against the secrets of the revision **the service actually holds** (`describe-services` → `describe-task-definition`) — never against Terraform state, which is precisely what lies. Flags, never blocks: ADR-004's own criterion rules out blocking, because destroying a genuinely-unreferenced parameter is legitimate.
- **D — Let Terraform move the pointer, plain-`ECS` workers only.** Leaves the CODE_DEPLOY web untouched, where the AWS API forbids it anyway. Would close the window at the root for workers. Cost: **not investigated** — no spike tested whether an un-ignored `task_definition` is safe against the GHA deploy in practice.

## What the community does — the honest answer

- **This exact shape has no name.** Two independent searches, across two spikes, for a named pattern covering "expand/contract applied to a launch-time-resolved resource referenced by a live task definition" came back empty. Weak evidence (absence of a hit is not absence of a practice) but consistent across two different search framings.
- **The general shape is canonical: Parallel Change / expand-and-contract** (Fowler). 4Shark's own `DEPLOYMENT-STRATEGY.md` already names it — applied to schema changes and job-argument contracts, not to this resource type. So the convention is ours already; what is missing is anyone having written about applying it here.
- **The plain-ECS-controller ownership boundary is contested and actively churning in both directions.** CyberAgent and a second named author moved ECS management from Terraform to ecspresso and called it smooth; Cloud Posse moved the opposite way, explicitly deprecating its own ecspresso-based split in favour of full-Terraform ownership via Atmos; a third hybrid (Terraform + ecspresso side by side) is a still-open issue. No settled industry default exists for this path. **This is an argument for not migrating, not for picking a different destination.**
- **4Shark's current shape matches AWS's own CI/CD reference architecture** (IaC provisions once with a placeholder image; the deployer registers revisions thereafter) — with CDK/CloudFormation rather than Terraform, but structurally the same. We are not somewhere exotic.

## Open questions nobody has answered

- Would `terraform apply -replace=aws_ecs_service.this` on a worker reproduce the "Terraform-set pointer" state? The code path (`main.tf:79`, no create-vs-replace special-casing) suggests yes; untested.
- Can a CODE_DEPLOY service recreated via `replace_triggered_by` set an initial `task_definition` at all, given the API rejects *updates*? Creation and update may follow different rules; untested.
- Does Terraform register a new revision on EVERY apply where `container_definitions` changes — including one that only REMOVES a `secrets` entry? Assumed from #711's behaviour, not independently tested against the provider's diff logic.
- **The incident record's timestamp is wrong.** `datadog-key-standard/PLAN.md:54` says parameters were destroyed at 16:40; CloudTrail says 15:43–15:56 BRT. Unresolved — neither value was proven correct.
- CloudTrail surfaces no data-plane placement failures (`RunTask` carries no `errorCode` for them). The reconstruction of the *cause* is complete; the picture of the *failure itself* came from the incident record, not CloudTrail.

## Related, not part of this decision

- **`modules/ecs_service/README.md` is wrong** and inverts who owns the task definition. Cheap to fix, changes no behaviour, actively misleads today.
- **`modules/connection_pooler/main.tf:361-363` carries the same `ignore_changes = [task_definition]` trap** — without even the CodeDeploy justification the web has.
- **The three spikes are still in `active/`** and can move to `completed/` once the decision above lands.

## Artifacts

| Path | What |
|---|---|
| `../terraform-ignore-changes-task-definition-drift/SPIKE.md` | First pass — F1–F25. **Carries the discredited copy-forward framing; read with the correction above in hand.** Also holds the CODE_DEPLOY evidence and the track_latest experiment record. |
| `../ecs-taskdef-ownership-boundary/SPIKE.md` | The community survey — 7 findings, 23 sources, the churn evidence. |
| `./SPIKE.md` | The CloudTrail reconstruction — 11 findings, the confirmed mechanism. **This is the canonical one.** |
| `./pointer-lag_cloudtrail_1.md` | Raw CloudTrail events, including the absence-proving query. |
| `/tmp/knowledge_pointer_lag_*.html` | Engineer-facing explainer of the window (ephemeral). |

Merged: [terraform#727](https://github.com/4shark/terraform/pull/727), [terraform#733](https://github.com/4shark/terraform/pull/733), [app#5237](https://github.com/4shark/app/pull/5237), [app#5242](https://github.com/4shark/app/pull/5242). Closed without merging: [terraform#721](https://github.com/4shark/terraform/pull/721).
