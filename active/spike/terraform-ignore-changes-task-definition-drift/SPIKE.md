# SPIKE — `ignore_changes = [task_definition]`: when a clean `terraform plan` does not describe reality

> **Trigger:** `terraform` #711 destroyed four `/<stack>/DD_API_KEY` SSM parameters after `terraform plan` reported `No changes` on all four stacks. Every new task then failed to launch for ~1h across all four stacks (worker autoscaling dead; web unaffected). The canonical incident record is `~/Projects/4Shark/dot-claude-plans/active/terraform/datadog-key-standard/PLAN.md:14-37` — not restated here, used as ground truth.
>
> **This spike brings options with evidence. It does not rank them and makes no recommendation.** Several findings below contradict what the module's own README says; that divergence is itself a finding.
>
> **2026-07-15 correction record.** The `output-verifier` flagged a confirmed citation-integrity failure in the original F7 (this SPIKE's issue #165 status was misstated as "Open" when it was actually `closed`/`state_reason: completed`, resolved by PR #217, milestone v6.0.0). The coordinator independently re-confirmed via `gh api`. This revision corrects F7 in place, investigates what the resolving PR actually did (new F17–F20 below), re-examines every derivation that leaned on "the community has no settled answer" (F5, F6 re-scoped), adds a new trade-off row and new uncertainties, and preserves the full raw evidence in auxiliary `taskdef-drift_v6release_1.md`. Nothing was silently deleted — corrected text says so inline.
>
> **2026-07-15 follow-up record (same day, second pass).** The engineer authorized closing two specific open uncertainties from the previous revision: Uncertainty 2 (what `data.aws_ecs_service.task_definition` actually returns — Option C depended entirely on it) and Uncertainty 7 (is `track_latest` + an un-ignored `task_definition` safe against a `CODE_DEPLOY`-controller service). Both are now resolved from primary sources — the AWS provider's own Go implementation (not just its docs) for Uncertainty 2, and a previously-surfaced-but-never-fetched issue (`hashicorp/terraform-provider-aws#12703`) plus a cross-tool corroboration (`aws/aws-cdk#7040`) for Uncertainty 7. New findings F21 and F22 below carry the resolutions; F8 and F18 are corrected in place with pointers to them; the trade-off table and uncertainty list are updated accordingly. Full raw evidence (Go source excerpts, `gh api` JSON, AWS doc quotes) is preserved in new auxiliary `taskdef-drift_followup_1.md`.
>
> **2026-07-16 empirical record (third pass) — the class of evidence changes here.** Every prior pass reasoned from documentation and source code. This one records an **experiment against real infrastructure**: the engineer authorized applying `track_latest = true` (the mechanism of Trade-off row I) to three productive stacks — `beta-001`, `demo-001`, `atento-001` — as step 1 of a two-step plan, after which it was reverted. Two things the previous passes could only reason about are now **observed**; one trade-off row is **invalidated as described**; and the experiment surfaced a **pre-existing defect that has nothing to do with `track_latest`** and is the most consequential finding in this document (F24). This pass: adds **F23–F25**; corrects **Trade-off row I** and **Suggested Option 5** in place (original text preserved inline); resolves **Uncertainty 5** in place; and adds one new uncertainty this spike **cannot** close. Raw evidence — plan/apply output, state diffs, the S3 revert mechanics, and every re-verified code citation — is preserved in new auxiliary `taskdef-drift_apply_1.md`.
>
> **The code state today:** `track_latest` is **not** in the repository — `grep -rn "track_latest" ~/Projects/4Shark/terraform --include='*.tf'` returns no matches and `develop` is clean (aux `taskdef-drift_apply_1.md`, E1). F23 and F25 describe an experiment that was run and undone. **F24's defect is still live and predates the experiment entirely** — reverting `track_latest` did not touch it.

## Investigation question

Five questions, refined from the engineer's brief:

1. How does the community resolve **Terraform-as-source-of-truth vs. an external deployer mutating the same field**? What are the real options, as documented — not as theorised?
2. **Can `terraform plan` detect this divergence** — the gap between the revision Terraform registered and the revision the service is actually running?
3. What is the **correct way to destroy a secret/parameter referenced by a live task definition** without arming this bomb?
4. Does the trap apply **only to secrets/params**, or are there other resource classes with the same shape in these stacks?
5. Can this become a **mechanical guard** (a dot-claude hook), or is it a written rule?

## Sources consulted

**Code and state (this repo / live AWS)**

- `modules/ecs_service/main.tf:12-65, 81, 152-163` — the task definition, `force_new_deployment`, and the service lifecycle. The core of F1–F3.
- `modules/ecs_service/README.md:7-9, 159-160` — the claims that contradict the code (F2).
- `modules/connection_pooler/main.tf:352-363` — the second module with the same shape (F11).
- `modules/ecs_scheduled_task/main.tf:83` — the contrast case with no trap (F12).
- `app-demo-001/ssm.tf:35-72` — the managed SSM parameters and the managed IAM role policy (F10).
- `app/.github/workflows/deploy-beta-001.yaml:418` — GitHub Actions registering task definitions out-of-band (F4).
- Read-only AWS (`ecs describe-services`, `describe-task-definition`, `list-task-definitions`) — see auxiliary `taskdef-drift_awsdump_1.json`.
- `git log`/`git show` on `modules/ecs_service` — see auxiliary `taskdef-drift_git_1.txt`.

**4Shark internal docs**

- `~/.claude/docs/DEPLOYMENT-STRATEGY.md:141-149` — the three triggers that force phasing (F13).
- `~/.claude/docs/TERRAFORM-POLICY.md:5, 10` — saved-plan requirement and the plan-summary discipline (F14).
- `~/.claude/docs/adr/ADR-004-code-write-policy-enforcement.md:35-37` — the block-vs-flag criterion (F16).

**External** — all verbatim quotes preserved in auxiliary `taskdef-drift_sources_1.md` (S1–S26), including two **negative** results (one since superseded, see F19), one genuinely-unresolved sub-question (S26), and the S5 correction record.

**AWS provider Go source (new in the follow-up pass, not just docs)**

- `internal/service/ecs/service_data_source.go:444-447, 498-573` — the data source's `Read` function; confirms `task_definition` is a direct passthrough of the API response (F21).
- `internal/service/ecs/service.go:1600-1813, 1992-2051` — the resource's update path and the `DescribeServices` call chain; confirms no `CODE_DEPLOY` special-casing anywhere (F21, F22).

**Auxiliary files**

- [`taskdef-drift_awsdump_1.json`](./taskdef-drift_awsdump_1.json) — raw read-only AWS state: clusters, running revisions + deployment controllers, and a full live task definition. Sustains F4 and F9.
- [`taskdef-drift_git_1.txt`](./taskdef-drift_git_1.txt) — the two commits that added then removed `ignore_changes = [container_definitions]`. Sustains F2.
- [`taskdef-drift_sources_1.md`](./taskdef-drift_sources_1.md) — every external source with the literal substrings relied on, plus what was deliberately NOT used and why. Contains the S5 correction, S11–S16 (v6.0.0 investigation), and S17–S26 (this follow-up pass).
- [`taskdef-drift_excerpt_1.tf`](./taskdef-drift_excerpt_1.tf) — the nine code blocks this spike reasons about, verbatim with line labels, including the full `ignore_changes` inventory.
- [`taskdef-drift_v6release_1.md`](./taskdef-drift_v6release_1.md) — the correction investigation: issue #165's real status, PR #217's body, the pre-v6 `max(latest, current)` idiom source, provider PR #30154 (`track_latest`), the v6.0.0 module's two-branch split, and confirmation 4Shark does not consume the community module. Sustains F17–F20.
- [`taskdef-drift_followup_1.md`](./taskdef-drift_followup_1.md) — the follow-up investigation: the AWS provider's Go source for the `aws_ecs_service` data source and resource update path (E1, E2, E8), the AWS API reference quotes for `Service.taskDefinition` and `Deployment.status`/`taskDefinition` (E3, E5), the `task_definition` resource-argument text that the data source's doc string was garbled from (E4), the full `gh api` fetch of issue #12703 with comments and events (E6), the cross-tool `aws/aws-cdk#7040` corroboration (E7), the confirmed-silent `terraform-aws-modules/terraform-aws-ecs#169` (E9), and the genuinely-unresolved AWS blue/green tutorial sub-question (E10). Sustains F21–F22.
- [`taskdef-drift_apply_1.md`](./taskdef-drift_apply_1.md) — the empirical evidence from the 2026-07-16 `track_latest` apply-and-revert on `beta-001`/`demo-001`/`atento-001`: the enabling apply's plan/apply output (E2), the permanently-dirty next plan (E3), the state before/after diff (E4), why the revert could not go through `terraform apply` (E5), the S3 object-version restore and its pre-flight (E6), the config-vs-GHA `command` divergence traced across all four app stacks (E7–E8), and commit `13d32a0`'s real scope (E9). Sustains F23–F25. Provenance is labeled per item: `[MAIN-TRACE]` (the coordinator's own tool results, not re-derivable now that the change is reverted) vs `[VERIFIED-HERE]` (re-read against the live repo during this pass).

---

## Findings

### F1 — The ignore is on the service (the pointer), not the task definition (the content)

**Evidence:** `modules/ecs_service/main.tf:152-163`:

```hcl
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition, # CodeDeploy gerencia a task definition durante deployments
      load_balancer,   # CodeDeploy gerencia os target groups durante blue/green deployments
    ]

    replace_triggered_by = [terraform_data.lb_config]
  }
```

`task_definition` on `aws_ecs_service` is the **pointer** — which revision this service runs. Ignoring it means Terraform never moves the service onto a different revision, and never reports that the service is on a different one.

**Source:** `~/Projects/4Shark/terraform/modules/ecs_service/main.tf:152-163`.

**Significance:** this is the mechanism the briefing named, confirmed. It is necessary but not sufficient to explain the incident — F2 supplies the other half.

---

### F2 — The README is wrong, and the divergence inverts who owns the task definition content

**Evidence.** The README claims twice that content is ignored — `README.md:7-9`:

> "Container definitions are marked `ignore_changes` so that GitHub Actions can inject full environment variables when registering new task definition revisions without Terraform overwriting them on the next apply."

and `README.md:159-160`:

> "`container_definitions` is ignored in `lifecycle` — changes to environment variables or secrets must go through the CI/CD pipeline (GitHub Actions), not Terraform."

The code says otherwise — `modules/ecs_service/main.tf:64`:

```hcl
  lifecycle {}
```

Git resolves it, confirmed independently via `git log -1 --format=%B` on both commits. `5f0a472` — subject *"fix(ecs): prevent Terraform from overwriting CI/CD task definition revisions"* (2026-02-20) — **added** `ignore_changes = [container_definitions]`. `13d32a0` — subject *"feat(integrator-almaviva): bring environment variables under Terraform management"* (2026-03-20) — **removed** it, and its commit body states the intent verbatim:

> "Removed ignore_changes on container_definitions so Terraform has full ownership of task definition content."

**Source:** `modules/ecs_service/README.md:7-9, 159-160`; `modules/ecs_service/main.tf:64`; auxiliary `taskdef-drift_git_1.txt` (commit subjects and bodies for `5f0a472` and `13d32a0`).

**Significance:** the README has been stale for ~4 months, and this is **not cosmetic** — it inverts the premise of any reasoning about what a plan on this module means. A reader trusting the README concludes "Terraform does not touch task definition content, so a plan showing `No changes` is expected and meaningless here". The truth is the opposite: **Terraform fully owns the content and did register a clean revision** — which is precisely why the plan went quiet while reality did not follow. The incident is only explicable once F2 is known.

---

### F3 — The trap is the split between the two halves, and it is a property of the module

**Evidence:** Terraform owns the content (F2) → on #711 it registered a new revision without `DD_API_KEY`. Terraform does not own the pointer (F1) → the service was never moved onto it. Both resources are in the same module, ~90 lines apart. Terraform's `No changes` was **truthful about its own scope** and silent about the gap.

`force_new_deployment` does not close it — `modules/ecs_service/main.tf:81`:

```hcl
  force_new_deployment = var.deployment_controller_type == "CODE_DEPLOY" ? false : var.force_new_deployment
```

It is `false` for CodeDeploy services, and for the rest it only takes effect **if Terraform updates the service resource at all**. With `task_definition` ignored, a revision-only change produces no service update, so nothing forces a deployment.

**Source:** `modules/ecs_service/main.tf:64, 81, 152-163`.

**Significance:** the failure is structural, not an oversight in #711. Any apply that destroys a resource the live revision references — on any stack using this module — arms the same delayed failure, and `plan` cannot see it. The incident record's own generalisable lesson (`PLAN.md:37`) states this; this spike confirms the mechanism.

---

### F4 — The stated justification for the ignore does not match most of the services it applies to

**Evidence.** The inline comment says *"CodeDeploy gerencia a task definition durante deployments"* (`main.tf:155`). Live AWS says only **web** uses CodeDeploy:

| Service | Controller | Running revision |
|---|---|---|
| `beta-001-web-service` | `CODE_DEPLOY` | `beta-001-web:221` |
| `beta-001-worker-system-service` | `ECS` | `beta-001-worker-system:213` |
| `beta-001-worker-user-service` | `ECS` | `beta-001-worker-user:212` |

`beta-001-cluster` runs 9 services; 8 are workers/runner (plain `ECS` controller), 1 is web.

The real out-of-band mutator for the workers is GitHub Actions — `app/.github/workflows/deploy-beta-001.yaml:418`:

```
          TASK_DEF_ARN=$(aws ecs register-task-definition \
```

**Source:** auxiliary `taskdef-drift_awsdump_1.json` (`running_task_definitions_and_controllers`); `modules/ecs_service/main.tf:155`; `app/.github/workflows/deploy-beta-001.yaml:418`.

**Significance:** the ignore is applied **unconditionally to every service** while its justification names a mechanism that governs one service in nine. This does **not** mean the ignore is unnecessary for workers — GHA registering revisions out-of-band is an independent, real reason. It means the *documented rationale is narrower than the blast radius*, so anyone reasoning from the comment underestimates what the ignore covers. The incident hit workers, whose ignore the comment does not explain. **This is also, exactly, the shape `track_latest` (F18) targets** — a plain-`ECS`-controller service with an external CI/CD process registering revisions.

---

### F5 — `ignore_changes` on `task_definition` is community practice, not a vendor-documented pattern

**Evidence.** The AWS provider's `aws_ecs_service` documentation covers `ignore_changes` **only** for `desired_count`:

> "You can utilize the generic Terraform resource lifecycle configuration block with ignore_changes to create an ECS service with an initial count of running instances, then ignore any changes to that count caused externally (e.g., Application Autoscaling)."

The extraction found **no** guidance for `ignore_changes` on `task_definition` anywhere in that resource's docs. The only acknowledgement of an external owner is:

> "Required unless using the EXTERNAL deployment controller."

**Source:** S2 in `taskdef-drift_sources_1.md` (https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown).

**Significance, re-examined after the F7 correction:** this finding is **unaffected** by the F7 correction — `track_latest` (F17) is a distinct provider argument on `aws_ecs_task_definition`, not an `ignore_changes` argument on `aws_ecs_service`. The provider still documents zero `ignore_changes` guidance for `task_definition`. What changes is what this finding is allowed to imply together with F6/F7: it supports "there is no vendor-blessed `ignore_changes` pattern for `task_definition`" on its own; it no longer supports, combined with the old F7, "therefore the community has no answer at all" — F17–F19 show a provider-native answer exists for one shape of the problem (see F19's scope note).

---

### F6 — The provider team closed an adjacent, narrower bug as "not planned"

**Evidence.** `hashicorp/terraform-provider-aws` issue **#34129**, *"[Bug]: aws_ecs_service triggers based on computed values do not result in redeployment"* — **Closed as not planned**. The reporter states the constraint verbatim:

> "Terraform must ignore changes to the `task_definition` argument on `aws_ecs_service.main` are ignored to avoid drift detection."

and the reproduction:

> "Run `terraform apply` and note that the Task Definition 'must be replaced', but no changes are planned against `aws_ecs_service.main`"

The extraction surfaced **no maintainer response proposing a solution**.

**Source:** S4 in `taskdef-drift_sources_1.md` (https://github.com/hashicorp/terraform-provider-aws/issues/34129).

**Significance, re-examined after the F7 correction:** this issue is genuinely **closed as not planned** (confirmed, unlike the original #165 read) and is genuinely **narrower** than #165 — it is specifically about `triggers` computed from other resources not causing redeployment in a CodePipeline context, not about the general task-definition-ownership question. What it still sustains, standing alone: (a) the reporter's own words independently confirm the general problem shape exists beyond 4Shark ("no changes are planned against the service" while "the Task Definition must be replaced" — #711 in miniature); (b) `triggers` based on computed inter-resource values specifically do not work, which bears on Trade-off row D below. It does **not** need, and should not be read together with, the old F7 as joint evidence of "no community answer" — that framing is retired; see F19.

---

### F7 — CORRECTED: issue #165 is closed, resolved by v6.0.0 — not open and unresolved

> **This finding replaces the original F7, which stated the issue was "Open, marked 'wip'". That was a citation-integrity failure — the `wip` label and the issue's actual `state` are different fields, and the original text conflated them. Caught by the `output-verifier`; independently re-confirmed by the coordinator via `gh api`; re-verified a third time here, directly via `gh api`, not a rendered-page fetch.**

**Evidence.** `terraform-aws-modules/terraform-aws-ecs` issue **#165**, titled (accurate in both versions):

> "The recommended workaround for ignoring task definition changes causes the service's container_definitions to be overwritten on every Terraform apply, even ones that don't touch the service."

Corrected status, verbatim JSON via `gh api repos/terraform-aws-modules/terraform-aws-ecs/issues/165`:

```json
"state": "closed"
"state_reason": "completed"
"closed_at": "2025-07-07T12:24:48Z"
"milestone": { "title": "v6.0.0" }
```

The `wip` label is still attached — it is a label, not the state.

**Source:** S5 in `taskdef-drift_sources_1.md` (corrected entry, https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/165, re-fetched via `gh api`).

**Significance:** the flagship community module's own long-standing issue on this exact problem is **resolved**, not abandoned. This single correction is why F5's and F6's derivations needed re-examining (above) and why F17–F19 exist — the question shifts from "does the community have an answer?" (it does, for one shape) to "what precisely did the answer solve, and does it apply to 4Shark's shape of the problem?" (F17–F19 answer this directly; it is a qualified yes for the plain-`ECS`-controller/worker shape and, per F22 below, a confirmed **no** for the `CODE_DEPLOY`-controller/web shape).

---

### F8 — `terraform plan` CAN surface this, but only as a warning, and only via a `check` block

> **2026-07-15 follow-up correction.** This finding originally flagged the data source's doc string as ambiguous and left it as an open caveat ("not confirmed against a live plan"). It is now resolved — see **F21** below, which traces the data source's actual runtime behavior directly through the AWS provider's Go source. The doc-string ambiguity itself is explained (it is a copy-paste artifact from a different field's description), and the underlying semantic question ("does this attribute return the running revision or a computed 'latest' value?") is answered: it is a direct passthrough of `DescribeServices`, i.e. the service's on-record configured value — exactly the value that stayed on the OLD revision throughout #711. The original text below is preserved; F21 supersedes only the caveat, not the rest of the finding.

**Evidence.** HashiCorp on `check` blocks:

> "The `check` block executes as the last step of plan or apply operation, after Terraform has planned or provisioned your infrastructure."

> "When a `check` block's assertion fails, Terraform reports a warning and continues executing the current operation."

The docs' own example uses a data source inside the check. And the `aws_ecs_service` **data source** exposes `task_definition`:

> "Family for the latest ACTIVE revision or full ARN of the task definition"

**Source:** S1 and S3 in `taskdef-drift_sources_1.md`.

**Significance:** the pieces for a plan-time signal exist — a `check` block reading `data.aws_ecs_service` and asserting the running revision matches the one Terraform manages. What it **cannot** do is stop the apply: a failed check warns and continues. So `plan` can *tell you*, but the guarantee remains human attention — the same thing that failed in #711. **Original caveats, now resolved by F21:** (a) the data source description was ambiguous — F21 shows it is a copy-paste artifact, and the actual attribute is a direct `DescribeServices` passthrough, confirmed workable for detecting the #711 shape specifically; (b) a `check` block runs on every plan, adding an API call per service — this cost remains unchanged. `precondition`/`postcondition` remain unevaluated as the blocking alternative (uncertainty 9).

---

### F9 — ECS resolves the referenced resources at task-launch, before the container exists

**Evidence.** AWS documents each of these as a distinct `ResourceInitializationError` that prevents a task from starting:

> "The task can't pull the secret from Secrets Manager. The task can't retrieve the secret with ARN '{{secretARN}}' from Secrets Manager. Check whether the secret exists in the specified Region."

with the documented cause: *"The secret ARN doesn't exist"*, and separately *"The task execution role defined in the task definition doesn't have the permissions for Secrets Manager."*

> "failed to initialize logging driver"
> "This error occurs when your task fails to find the CloudWatch log group you defined in the task definition."
> "The error indicates that the CloudWatch group in the task definition does not exist."

Also documented: *"failed to invoke EFS utils commands to set up EFS volumes"*.

**Source:** S6 in `taskdef-drift_sources_1.md` (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/resource-initialization-error.html).

**Significance:** this is the general rule the incident is one instance of. The incident's PR reasoned *"nothing reads what is being removed"* — true of the variable, false of the mechanism. **The reference is resolved by ECS to build the task; whether the application ever reads the value is irrelevant.** AWS's own error taxonomy confirms the same failure shape arises from several different resource classes, which is exactly Q4.

---

### F10 — Q4: the trap class, enumerated against the real repo and a real live revision

The shape is: *a resource the LIVE revision references, that Terraform can destroy while reporting `No changes`.* Two conditions must BOTH hold — **ECS resolves it at launch** (F9) **and Terraform owns it**. Reading a live revision (`beta-001-worker-system:213`) against the repo:

| Resource class | Resolved at launch? | Terraform-managed? | Same trap? | Evidence |
|---|---|---|---|---|
| **SSM parameters (secrets)** — 16 on this revision | Yes (F9) | **Yes** — `app-demo-001/ssm.tf:35-45`, `aws_ssm_parameter.secrets` for_each over 15 names | **YES — this is the one that fired** | aux `awsdump_1`, `ssm.tf:35-45` |
| **IAM role *policy*** granting `ssm:GetParameters` + `kms:Decrypt` | Yes (F9 — "execution role doesn't have the permissions") | **Yes** — `app-demo-001/ssm.tf:51-72`, `aws_iam_role_policy.ecs_ssm_read` | **YES — and wider blast radius**: destroying it breaks *every* secret at once, not one | `ssm.tf:51-72` |
| **CloudWatch log group** | Yes (F9 — "the group ... does not exist") | **Yes** — `modules/ecs_service/main.tf:1-10`, no `ignore_changes`; `awslogs-create-group` absent from the options map (`:45-52`) | **YES** | `main.tf:1-10, 45-52` |
| **IAM execution/task role itself** | Yes | **No** — referenced as a hardcoded ARN string; grep found no `aws_iam_role` resource for `ecsTaskExecutionRole` | **No** — Terraform cannot destroy it | grep; `scheduled-tasks.tf:71-72` |
| **KMS key** behind the SecureStrings | Yes | **Not confirmed** — grep for `aws_kms_key` found only `audit/kms.tf` (cloudtrail) and `modules/cross_region_backup`; `mrk-fa0cda…` matches neither | **Probably not** — see uncertainties | `ssm.tf:68`; grep |
| **ECR image / repo** | Yes (pull at launch) | Repo yes; the `:latest` tag is pushed by CI | Partly — destroying the repo would qualify; not exercised | aux `awsdump_1` |
| **EFS volumes** | Yes (F9) | N/A here — `volumes: []` on this revision | Not currently applicable | aux `awsdump_1` |
| **Security groups / subnets** | Yes, for `awsvpc` | Yes | Out of the *task-definition* shape — they live on the **service**'s `network_configuration` (`main.tf:96-103`), not the task definition. A different exposure, not this one. | `main.tf:96-103` |

**Significance:** the SSM parameters are the largest instance (16 per revision per stack), but **the IAM role policy is the more dangerous one** — one resource whose destruction breaks every secret for every service on the stack simultaneously. Two classes commonly assumed dangerous are **not** in scope: the execution role and (probably) the KMS key are outside Terraform's ownership, so Terraform cannot destroy them.

---

### F11 — The `connection_pooler` module carries the same trap, without the CodeDeploy justification

**Evidence:** `modules/connection_pooler/main.tf:352-363`:

```hcl
  deployment_controller {
    type = "ECS"
  }
  # ...
  lifecycle {
    ignore_changes = [task_definition]
  }
```

**Source:** `~/Projects/4Shark/terraform/modules/connection_pooler/main.tf:352-363`.

**Significance:** same shape, and here the deployment controller is plainly `ECS` — so the CodeDeploy rationale of F4 cannot apply at all. Four pooler clusters exist (`beta-001`, `demo-001`, `atento-001`, `shared-001` — aux `awsdump_1`). Relevant to the *live* `datadog-key-standard` Phase 3, which migrates the four pooler secrets and already plans a `force-new-deployment` per stack (`PLAN.md:206`) — that step is what keeps Phase 3 out of this trap.

---

### F12 — `ecs_scheduled_task` does NOT have the trap, and shows one way out

**Evidence:** `modules/ecs_scheduled_task/main.tf:83`:

```hcl
      task_definition_arn = replace(aws_ecs_task_definition.this.arn, "/:\\d+$/", "")
```

The module contains **no** `ignore_changes` at all (confirmed by the repo-wide grep in aux `excerpt_1` block [9]).

**Source:** `~/Projects/4Shark/terraform/modules/ecs_scheduled_task/main.tf:27-94`.

**Significance:** stripping the revision suffix makes the EventBridge target track the **family**, so it resolves to the newest ACTIVE revision at invocation. Terraform registers a new revision and the next run picks it up — **no pinned-old-revision window exists**, so no divergence can accumulate. This is the useful contrast: the trap is not inherent to "Terraform + ECS", it is a consequence of pinning a service to a specific revision *and* then ignoring the pin. Whether family-tracking is transferable to a *service* is a separate question (a service must name a concrete revision; ECS does not offer family-tracking for services in the way EventBridge does) — **not verified**, see uncertainties. **F17 offers a different, provider-native way to the same end for services specifically.**

---

### F13 — `DEPLOYMENT-STRATEGY.md`'s decision framework does not cover this incident class

**Evidence.** `~/.claude/docs/DEPLOYMENT-STRATEGY.md:141-149` lists the triggers that force phasing:

> "1. **The `Computation` key derivation changes.** … 2. **The enqueued job's argument shape changes incompatibly.** … 3. **The change introduces a non-idempotent step.**"
>
> "Other classic forcing conditions: an irreversible data-shape change, or a cross-service API/contract change (the consumer must learn the new shape before the producer emits it)."

All three triggers, and both "other" conditions, are about the **application-level in-flight contract** (Redis counters, job arguments, idempotency, data shape, service APIs). The document's machinery section (`:32-76`) describes only the **GitHub Actions** deploy pipeline. The word "terraform" does not appear in the document's framework at all.

**Source:** `~/.claude/docs/DEPLOYMENT-STRATEGY.md:141-149`, `:32-76`.

**Significance:** **this is a genuine gap, not a fit.** The incident's broken contract is *infrastructural*: between a live task definition revision and the resources it references. It arrived through the **terraform** pipeline, which that document never models. #711 could have been read against all five of its conditions and passed every one. The gap sits between `DEPLOYMENT-STRATEGY.md` (models app deploys, not terraform) and `TERRAFORM-POLICY.md` (models the terraform workflow, but its only reality check is the plan — F14). Neither owns this class today.

---

### F14 — The existing terraform review discipline anchors on the artefact that lied

**Evidence.** `~/.claude/docs/TERRAFORM-POLICY.md:10`:

> "**After every plan, present a structured summary** — resources to add/change/destroy with descriptions, totals, sensitive resources flagged"

and `:5`:

> "**NEVER run `terraform apply` without a saved plan file** — always use `terraform plan -out=<file>` first"

**Source:** `~/.claude/docs/TERRAFORM-POLICY.md:5, 10`.

**Significance:** two things pull in opposite directions. The review discipline is anchored on the plan — the exact artefact that was truthful-but-silent in #711, so following the policy perfectly would not have caught it. But `:5` is load-bearing for Q5: because a **saved plan file always exists before an apply**, the destroy-set is mechanically knowable at apply time via `terraform show -json`. That is what makes F15's option technically possible at all.

---

### F15 — Q5: a mechanical guard is *possible* at the apply boundary, and its cost is the question

**Evidence.** The pieces exist: the saved plan file is mandatory (F14 / `TERRAFORM-POLICY.md:5`), so a `PreToolUse` hook on `terraform apply` could read the destroy-set from `terraform show -json`, then query read-only AWS (`ecs describe-services` → `describe-task-definition`) and cross-reference each destroyed ARN against the live revisions. `inject-terraform-context.sh` is the established precedent for a PreToolUse terraform hook, and it documents its own constraints:

> "Always exits 0. A failing hook must NEVER block a terraform command."

and notes a "10k additionalContext inline limit".

**The governing criterion is ADR-004's**, not detection confidence — `ADR-004-code-write-policy-enforcement.md:35-37`:

> "**Block vs flag is decided by exceptions, not by detection confidence**"
>
> "A rule with documented exceptions … must be a FLAG — a block would refuse legitimate code."

**Source:** `~/.claude/docs/TERRAFORM-POLICY.md:5`; `~/.claude/scripts/inject-terraform-context.sh:29-31, 26-27`; `~/.claude/docs/adr/ADR-004-code-write-policy-enforcement.md:35-37`.

**Significance.** Applying ADR-004's criterion honestly: **this rule has a legitimate exception** — destroying a parameter is correct once the live revision no longer references it (that is the intended end state of any cleanup, and of `datadog-key-standard` Phase 4). So a hard BLOCK would refuse legitimate applies, and by ADR-004's own logic it fails the block test. The false-positive profile is otherwise favourable (if the live revision truly references a destroyed ARN, the failure is real, not stylistic); the false-negative profile is the concern — the hook would need to enumerate the right clusters, and a stack it does not know about is silently unchecked. The cost is several AWS round-trips inside a PreToolUse hook. **This spike does not conclude which tier is right** — it establishes that the block tier is ruled out by an existing ADR's criterion, leaving flag/inject and non-hook paths as the live options.

---

### F16 — `triggers` + `plantimestamp()` is vendor-documented, but its interaction with the ignore is unverified

**Evidence.** The provider documents, under a heading titled **"Redeploy Service On Every Apply"**:

> "Map of arbitrary keys and values that, when changed, will trigger an in-place update (redeployment)."

```terraform
resource "aws_ecs_service" "example" {
  force_new_deployment = true

  triggers = {
    redeployment = plantimestamp()
  }
}
```

**Source:** S2 in `taskdef-drift_sources_1.md`.

**Significance:** this is a vendor-documented mechanism, but a distinct one from `track_latest` (F17) — `triggers` forces a redeployment; it does not change what revision the service resolves to. **There is an unresolved question that decides whether it helps at all:** with `task_definition` in `ignore_changes`, a forced redeployment plausibly redeploys the revision the service *currently* points at — the OLD one — rather than adopting the new one. If so it does not fix the divergence; it merely restarts the failing revision. This was **not verified** and remains one of the open questions below. F6 also shows `triggers` has a documented failure mode with computed values (closed as not planned), though `plantimestamp()` is not a computed inter-resource value.

---

### F17 — `track_latest`: a provider-native argument built specifically for "an external CI/CD process registers revisions outside Terraform"

**Evidence.** The AWS provider's `aws_ecs_task_definition` resource documents, verbatim:

> "`track_latest` - (Optional) Whether should track latest `ACTIVE` task definition on AWS or the one created with the resource stored in state. Default is `false`. Useful in the event the task definition is modified outside of this resource."

It was added directly to the provider (not the community module) by PR #30154, merged `2024-02-12T18:13:32Z`, whose own description states the exact scenario it targets, verbatim:

> "The rationale for this Pull Request is that in some projects/environments/teams, Task Definitions can be updated outside Terraform. For example, a CI/CD process could bumps the Docker Tag version by creates a new TaskDefinition using the previous one as a base template, within the process, it might move the previous TaskDefinition to inactive. Because of this, when Terraform is executed again it cannot track the changes and forces a new resource creation."

> "With this Pull Request, we would allow users to track always the changes against the latest TaskDefinition, so, if all the fields are the same, Terraform won't promote any change."

**Source:** S12, S13 in `taskdef-drift_sources_1.md`; https://github.com/hashicorp/terraform-provider-aws/pull/30154; https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_task_definition.html.markdown.

**Significance:** the PR author's own example — "a CI/CD process could bump the Docker Tag version by creating a new TaskDefinition" — is structurally identical to 4Shark's GitHub Actions worker deploy (F4: `app/.github/workflows/deploy-beta-001.yaml:418`, `aws ecs register-task-definition`). This is a genuine, provider-native, purpose-built mechanism for the shape of the problem the incident actually hit on the worker services. **`track_latest` is an argument on `aws_ecs_task_definition`, distinct from `ignore_changes` on `aws_ecs_service`** — it changes what a `data`/resource *resolves to*, not what the service update ignores. Whether pairing it with an un-ignored `task_definition` on the service (F18) fully replicates the fix, and precisely what happens on the apply that first surfaces a divergence, is addressed under uncertainties.

---

### F18 — The community module's v6.0.0 rewrite: `track_latest` replaces the old `max(latest, current)` hack, but ONLY for the default (non-`EXTERNAL`) service path

> **2026-07-15 follow-up correction.** This finding's original significance closed with "a genuine gap this spike could not resolve either way" regarding the `CODE_DEPLOY` case. That gap is now closed — see **F22** below, which resolves it in the negative from primary sources (the AWS provider's own resource-update code, a previously-surfaced-but-unfetched provider issue, and a cross-tool corroboration). The evidence and scope description below are unchanged; only the closing sentence of the original significance is superseded.

**Evidence.** `docs/UPGRADE-6.0.md:13` (identical text in PR #217's body), verbatim:

> "The 'hack' put in place to track the task definition version when updating outside of the module has been removed. Instead, users should rely on the `track_latest` variable to ensure that the latest task definition is used when updating the service. Any issues with tracking the task definition version should be reported to the *ECS service team* as it is a limitation of the AWS ECS service/API and not the module itself."

The "hack" it replaced, verbatim, from the module's pre-v6.0.0 source (tag `v5.12.1`, `modules/service/main.tf:596-599`):

```hcl
  # This allows us to query both the existing as well as Terraform's state and get
  # and get the max version of either source, useful for when external resources
  # update the container definition
  max_task_def_revision = local.create_task_definition ? max(aws_ecs_task_definition.this[0].revision, data.aws_ecs_task_definition.this[0].revision) : 0
```

**This IS the `max(latest, current)` idiom named in the original investigation brief** — it exists, just not in the specific source (S10, browniebroke) originally fetched to look for it. See F19 for the correction to the original "not found" conclusion.

The v6.0.0 (`master`) module declares two mutually exclusive `aws_ecs_service` resources. The default (`ignore_task_definition_changes = false`) has, verbatim, `main.tf:381-385`:

```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
    ]
  }
```

— no `task_definition` ignored. The opt-in branch (`ignore_task_definition_changes = true`), gated by `is_external_deployment = try(var.deployment_controller.type, null) == "EXTERNAL"` (`main.tf:25`), keeps the trap shape unchanged, verbatim, `main.tf:735-741`:

```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
      task_definition,
      load_balancer,
    ]
  }
```

**Source:** S11, S14, S15 in `taskdef-drift_sources_1.md`; auxiliary `taskdef-drift_v6release_1.md` (E2, E3, E7).

**Significance:** v6.0.0 did not eliminate `ignore_changes = [task_definition]` — it **scoped it** to the `EXTERNAL`-deployment-controller case (AWS `aws_ecs_task_set`) and shipped `track_latest` as the alternative for everything else. **This is precisely the shape #165's original reporter had** (GitHub Actions against a plain-`ECS`-controller service, per S5) **and precisely the shape of 4Shark's own worker services** (F4: `controller: ECS`). A `grep` of the module's `main.tf`, `variables.tf`, and `docs/UPGRADE-6.0.md` for `CODE_DEPLOY`/`CodeDeploy` returned **no matches** — the module never addresses the legacy `CODE_DEPLOY` deployment-controller type (which is what 4Shark's web service uses) as a distinct case anywhere found in this investigation. **Whether `track_latest` + an un-ignored `task_definition` is usable against a `CODE_DEPLOY`-controller service is resolved by F22 below: it is not — confirmed at the AWS API level, independent of this module.**

---

### F19 — Correction: the `max(latest, current)` idiom exists; the original "not found" conclusion was too narrow a search

**Evidence.** The original SPIKE (uncertainty #7, S10) concluded the idiom was "not found" based on a single blog post (browniebroke) that documented plain `ignore_changes` instead. F18 above shows the idiom exists verbatim in the community module's own pre-v6.0.0 source, and that the module's own maintainers name it "the 'hack'" and state it "has been removed" in v6.0.0.

**Source:** S10 (the original negative single-source result) and S14 (the corrected finding) in `taskdef-drift_sources_1.md`; auxiliary `taskdef-drift_v6release_1.md` (E3).

**Significance:** this is a methodological correction, recorded so the pattern is visible: a single negative fetch (S10) was treated as "not found" rather than prompting a wider search (the idiom's own name, or the module that is the community's reference implementation for this exact resource type). The practical consequence for Q1 is that the idiom is now a real, sourced, but **superseded** option — the module's own maintainers moved away from it in favor of `track_latest`, calling it a "hack" precisely because it required an extra `data` source, an extra `max()` computation, and (per the module issue #169 that requested its replacement) added complexity the provider-native argument avoids.

---

### F20 — 4Shark does not consume the community module; `track_latest` is directly portable regardless

**Evidence.** `grep -rn --include='*.tf' 'terraform-aws-modules/ecs' ~/Projects/4Shark/terraform` returned no matches — 4Shark's `modules/ecs_service` is fully hand-written; every resource is a direct `aws_*` resource, no community module `source =` anywhere in the repo.

**Source:** S16 in `taskdef-drift_sources_1.md`; auxiliary `taskdef-drift_v6release_1.md` (E8).

**Significance:** the community module's v6.0.0 rewrite is not itself a dependency 4Shark would take on — it is field evidence for a mechanism (`track_latest`) that is a raw AWS-provider argument on `aws_ecs_task_definition` (F17), addable to 4Shark's own `modules/ecs_service/main.tf:12` task definition resource directly, without adopting the community module. This is why F17–F19 belong in the Q1 options table as a genuine option for 4Shark (Trade-off row I below), not merely as commentary on someone else's module.

---

### F21 — RESOLVED (Uncertainty 2): `data.aws_ecs_service.task_definition` is a direct passthrough of `DescribeServices` — the doc string is a copy-paste artifact from a different field's description, and the attribute genuinely detects the #711 shape

**Evidence.**

1. The data source's `Read` function, verbatim, `internal/service/ecs/service_data_source.go:565` (fetched directly via `gh api`, current `main`):

```go
	d.Set("task_definition", service.TaskDefinition)
```

This is an unconditional assignment — no `max()`, no family lookup, no computation. Every other attribute in the same function follows the identical `d.Set(<attr>, service.<Field>)` shape, confirming this is the data source's general pattern.

2. The `service` value comes from `findServiceByTwoPartKey`, which calls `DescribeServices` directly — verbatim, `internal/service/ecs/service.go:2002`:

```go
	output, err := conn.DescribeServices(ctx, input)
```

3. AWS's own API reference for the `Service` data type describes that field, verbatim:

> "The task definition to use for tasks in the service. This value is specified when the service is created with CreateService, and it can be modified with UpdateService."

This is an explicit, settable field recording what the service IS CONFIGURED to run — not a "latest ACTIVE revision" computation.

4. The provider's data source doc string quoted in the original F8/S3 ("Family for the latest ACTIVE revision or full ARN of the task definition") traces to a different place entirely: the **resource's** `task_definition` **argument** description (what you may pass in), verbatim:

> "Family and revision (`family:revision`) or full ARN of the task definition that you want to run in your service. Required unless using the `EXTERNAL` deployment controller. If a revision is not specified, the latest `ACTIVE` revision is used."

"Family for the latest ACTIVE revision" is a garbled echo of "If a revision is not specified, the latest ACTIVE revision is used" — an INPUT-parsing rule for the resource argument, misapplied as a description of the DATA SOURCE's OUTPUT attribute.

**Source:** items 1–2 fetched directly, `internal/service/ecs/service_data_source.go:444-447, 498-573` and `internal/service/ecs/service.go:1992-2051`; item 3, S19 in `taskdef-drift_sources_1.md`; item 4, S20 in `taskdef-drift_sources_1.md`. Full excerpts in auxiliary `taskdef-drift_followup_1.md` (E1–E4).

**Significance:** this settles what Option C depended on. `data.aws_ecs_service.task_definition` returns exactly what `DescribeServices` reports as the service's on-record task definition — the value last written by `CreateService`/`UpdateService`, or unchanged if nothing has updated the service since creation. This is precisely the field that stayed on the OLD revision throughout #711, because `ignore_changes = [task_definition]` prevented Terraform from ever issuing an `UpdateService` call, and nothing else touched the service either. A `check` block comparing this attribute against Terraform's own newly-registered `aws_ecs_task_definition` value would have caught exactly this divergence. **Option C's data-source dependency is confirmed workable for the #711 shape, not merely "unconfirmed" as the original F8 stated.**

**Residual caveat, distinct from the doc-string question:** the field represents what the service is CONFIGURED to run (the target of the most recent `UpdateService`/`CreateService`), not a live confirmation that every currently-running task executes that revision. AWS's own `Deployment` data type — which populates a service's `deployments[]` array, and is explicitly scoped ("used only when a service uses the `ECS` deployment controller type", i.e. the plain-`ECS` worker services, not `CODE_DEPLOY`) — documents three states, verbatim:

> "PRIMARY The most recent deployment of a service. ACTIVE A service deployment that still has running tasks, but are in the process of being replaced with a new `PRIMARY` deployment. INACTIVE A deployment that has been completely replaced."

During an in-progress rolling deployment a service can have a PRIMARY (new revision, target) and an ACTIVE (old revision, still draining) deployment simultaneously; the top-level `task_definition` field mirrors the PRIMARY deployment's target, not a guarantee every running task matches it. For the #711 incident shape (zero deployment activity, one static deployment, no rollout in progress) this distinction is immaterial. For the general "is every running task actually on this revision" question, per-task `describe-tasks` → `taskDefinitionArn` remains the ground truth — the original F8/S6 caveat on this point stands unchanged.

---

### F22 — RESOLVED (Uncertainty 7): `track_latest` + an un-ignored `task_definition` is NOT safe against a `CODE_DEPLOY`-controller service — confirmed at the AWS API level, reproduced across two independent tools, and never fixed

**Evidence.**

1. `hashicorp/terraform-provider-aws` issue **#12703**, "ECS with CodeDeploy Blue/Green" — surfaced in the original SPIKE's search but never fetched (tagged UNVERIFIED there); fetched directly via `gh api` in this pass. Original report (2020), verbatim:

> "Error: Error applying plan: ... aws_ecs_service.default: Error updating ECS Service (...): InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment."

Reproduction, verbatim: "1. switch to CODE_DEPLOY deployment type with ECS Service 2. change aws_ecs_service.task_definition 3. apply"

2. Independently reconfirmed by a different reporter, provider v5.53.0, comment dated 2024-06-14, verbatim:

> "If I declare task_definition, I get this error: Error: updating ECS Service (...): InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. If I do not declare task_definition, I get this error: InvalidParameterException: Family should not be null or empty."

3. Cross-tool corroboration — `aws/aws-cdk` issue **#7040** (a completely different tool, AWS CDK via CloudFormation, not Terraform), fetched directly via `gh api`, verbatim:

> "Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. (Service: AmazonECS; Status Code: 400; Error Code: InvalidParameterException; Request ID: 83f32eb8-4ed5-4263-b944-9df4d7fa3a62)"

Same issue, verbatim: "only the desired count, deployment configuration, and health check grace period can be updated using the `update-service`. Otherwise a new CodeDeploy deployment should be created."

4. The AWS provider's own resource UPDATE code path — verbatim, `internal/service/ecs/service.go:1802-1804`, fetched directly:

```go
	if d.HasChange("task_definition") {
		input.TaskDefinition = aws.String(d.Get("task_definition").(string))
	}
```

No special-casing anywhere in `resourceServiceUpdate` for `deployment_controller.type == CODE_DEPLOY` (confirmed by a full-file grep of `service.go` for `CODE_DEPLOY`/`CodeDeploy`, which returns matches only in the schema default/validation of the `deployment_controller` argument itself, not in the update path). The provider does not skip, warn, or pre-validate — it sends whatever value Terraform computes to `UpdateService` unconditionally, and it is AWS's ECS API (not the provider) that rejects it.

5. Issue #12703's disposition: `state: closed`, `state_reason: not_planned`, `closed_by: github-actions[bot]`, labels `["bug", "service/ecs", "stale"]` — closed by the repository's stale-bot 30 days after being auto-labeled `stale` (2026-06-07 → 2026-07-12), **not** by a maintainer decision that evaluated and declined a fix. No maintainer comment across the 9-comment thread proposes or rejects a code-level solution.

6. Search for a `track_latest`-specific statement on this interaction: neither `terraform-aws-modules/terraform-aws-ecs#169` (the issue that proposed adopting `track_latest`, fully read) nor #12703's own thread (fully read) mentions `track_latest` at all — the two topics are never jointly discussed in any source fetched across either investigation pass.

**Source:** items 1–2 and 5–6, S22, S25 in `taskdef-drift_sources_1.md`; item 3, S23; item 4, S24. Full JSON, comments, events, and Go source in auxiliary `taskdef-drift_followup_1.md` (E6–E9).

**Significance:** this resolves Uncertainty 7 conclusively, and in the negative — **not** "genuinely unresolvable without an experiment". The constraint operates at the AWS ECS API level (`InvalidParameterException`, HTTP 400), independent of which tool issues the `UpdateService` call — confirmed identically by Terraform users in 2020 and again independently in 2024 on provider v5.53.0, and by AWS CDK users calling the same underlying API via CloudFormation. `track_latest` changes only what `aws_ecs_task_definition`'s own computed attributes resolve to; it does nothing to change what value the SERVICE resource sends to `UpdateService`, nor does it change AWS's rejection of that call for a `CODE_DEPLOY`-controlled service. Pairing `track_latest` with an un-ignored `task_definition` on 4Shark's web service would not be merely untested — it would fail with the exact error 4Shark's own inline comment already names as the ignore's justification (`main.tf:155`, F4), the moment the tracked value differs from what AWS has on record. This directly narrows Trade-off rows E and I below: both are now **confirmed**, not merely suspected, to fail against 4Shark's `CODE_DEPLOY`-controlled web service specifically. The community module's v6.0.0 branch-on-`EXTERNAL`-only design (F18) is consistent with this — `EXTERNAL` accepts an `UpdateService` `task_definition` change; `CODE_DEPLOY` does not, and no source found in either investigation pass (module, provider, AWS docs) offers a workaround other than "let CodeDeploy own it" (i.e., keep the ignore for this controller type).

**One sub-question stays genuinely unresolved, recorded honestly rather than forced:** whether the ECS `Service.taskDefinition` top-level field is itself rewritten by CodeDeploy during/after a blue/green swap ("does an un-ignored pointer fight CodeDeploy continuously, or only at the moment of a Terraform apply?") is **not found addressed** in any AWS doc fetched — AWS's own blue/green tutorial documents CodeDeploy's state tracking through its own `taskSetsInfo` (PRIMARY/ACTIVE at the CodeDeploy-target level), distinct from the ECS `deployments[]` model, but says nothing about the service's own top-level field. This does not change the answer above: items 1–4 establish the rejection fires on any Terraform-initiated `UpdateService` call regardless of what CodeDeploy itself does to that field between deployments — only how often the failure would be provoked is left open, not whether it occurs.

---

### F23 — OBSERVED (Uncertainty 5): `track_latest` alone is inert for the apply that enables it, and NOT inert in steady state — the next plan is permanently dirty

> **This finding is the first in this document sustained by an experiment rather than by documentation.** It resolves Uncertainty 5, which the previous pass explicitly recorded as "reasoned about in F17/row I but **not observed** against a real `terraform apply`". It is now observed, on three productive stacks. The answer is split: the premise's first half holds, its second half does not.

**Evidence — half one: the enabling apply IS a silent no-op (premise confirmed).** With `track_latest = true` added to `aws_ecs_task_definition.this` only, and the service's `ignore_changes` untouched, the plan on each of `beta-001` / `demo-001` / `atento-001`:

```
Plan: 0 to add, 9 to change, 0 to destroy.
```

Every change was of one shape, with no `aws_ecs_service` resource in any change set:

```
  ~ track_latest = false -> true
    # (17 unchanged attributes hidden)
```

Applied to all three:

```
Apply complete! Resources: 0 added, 9 changed, 0 destroyed.
```

Verified after: **no new task definition revision was registered by the apply.** The only new revision on the account, `atento-001-worker-user:33`, was registered hours earlier by `registeredBy: arn:aws:iam::405749097490:user/app-atento-001` — the GitHub Actions deploy user. Every service stayed `desired == running` on its existing pointer.

**Evidence — half two: the NEXT plan reports a permanent replacement of every task definition (premise falsified).** With `track_latest = true` now in **both** config and state, the next plan on `beta-001`:

```
Plan: 7 to add, 0 to change, 7 to destroy.
```

Every task definition shows `must be replaced`. Verbatim:

```
# module.ecs_services["beta-001-runner-service"].aws_ecs_task_definition.this must be replaced
  ~ container_definitions = jsonencode(
      ~ [
          ~ {
              - command          = [
                  - "sleep",
                  - "infinity",
                ]
              - mountPoints      = []
                name             = "beta-001-runner"
              - systemControls   = []
              - volumesFrom      = []
            }
        ] # forces replacement
    )
  ~ revision = 82 -> (known after apply)
```

**Evidence — the mechanism, from state.** Before the apply, state held Terraform's own revision with Terraform's own content; after, it holds GHA's revision and GHA's content. A byte-level diff of the two S3 state object versions (`serial` 128 → 129, `lineage` identical, 14 resources before and after — nothing created or lost) shows the changed fields are exactly `track_latest`, `arn`, `revision`, `container_definitions`. Example: `beta-001-runner` `arn: .../beta-001-runner:80 -> .../beta-001-runner:82`.

**Source:** the coordinator's own tool results from the 2026-07-16 session, preserved verbatim in auxiliary `taskdef-drift_apply_1.md` (E2, E3, E4), labeled `[MAIN-TRACE]`. Not re-derivable — the change has since been reverted (E1).

**Significance.** This **contradicts the premise of the two-step approach** the apply was step 1 of. That premise was: applying `track_latest` alone is inert, and it would make a later un-ignore of `task_definition` a no-op. The first clause is true and now proven. The second is false: `track_latest = true` re-points Terraform's state at the latest ACTIVE revision (GHA's) — which is precisely what F17 documents it to do — and Terraform then compares its own config against **what AWS actually has** instead of against its own stale state entry. The steady-state result is a permanent `N to add / N to destroy` on every task definition, on every plan, forever. **Note carefully what this does and does not indict:** `track_latest` behaved exactly as documented. The permanent diff is not a defect in the argument — it is the argument working correctly and, in doing so, exposing F24. Whether the diff would persist if the two sides actually matched is a different question, and F24 is why they do not.

---

### F24 — `track_latest` did not create a divergence; it REVEALED one that has always been there. Terraform's declared task definition content does not match what runs in production, on every app service, on every app stack

> **This is the finding that matters most in this document, and it is not about `track_latest` at all.** The experiment is what surfaced it; reverting the experiment did not fix it. It is live right now.

**Evidence — Terraform's side declares no `command`, and renders it as `null`.** The module's variable, `modules/ecs_service/variables.tf:132-136`:

```hcl
variable "command" {
  description = "Container command"
  type        = list(string)
  default     = []
}
```

The module's render, `modules/ecs_service/main.tf:30`:

```hcl
      command     = length(var.command) > 0 ? var.command : null
```

An undeclared `command` therefore renders as **`null`** in `container_definitions`. And **no app service declares one.** Scanning the service blocks of all four app stacks (everything before the `scheduled_tasks` map) for a `command =` key returns **zero matches** in `app-beta-001`, `app-demo-001`, `app-atento-001`, and `app-shared-001` (aux `taskdef-drift_apply_1.md`, E7). The only `command =` keys in those files belong to `scheduled_tasks`, which use `modules/ecs_scheduled_task` — the module with no trap (F12). (`enable_execute_command` is a different key and is not a match.)

Representative, `app-atento-001/terraform.tfvars:217-233` — verbatim, including the block's own comment:

```hcl
  # desired_count = 0 permanently — task def exists only to provide image, network
  # config, env vars and secrets for ephemeral debug tasks started via bin/ecs run.
  "atento-001-runner-service" = {
    task_family                  = "atento-001-runner"
    container_name               = "atento-001-runner"
    image                        = "405749097490.dkr.ecr.us-east-1.amazonaws.com/atento-001-app:latest"
    task_cpu                     = 2048
    task_memory                  = 2048
    container_cpu                = 0
    container_memory             = null
    container_memory_reservation = null
    container_port               = null
    desired_count                = 0

    execution_role_arn     = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
    task_role_arn          = "arn:aws:iam::405749097490:role/ecsTaskExecutionRole"
    enable_execute_command = true
```

**Evidence — GHA's side injects the `command` at deploy time.** The action declares it as an input, `app/.github/actions/deploy-ecs/action.yaml:5-6`:

```yaml
  command:
    description: 'Container command as JSON array (e.g., ["bundle", "exec", "puma", "-C", "config/puma.rb"])'
```

and patches it into the task definition before registering the revision, `action.yaml:87-97`:

```yaml
        # Set container command from input
        jq --arg NAME "$CONTAINER_NAME" \
           --argjson CMD '${{ inputs.command }}' \
          '(.containerDefinitions[] | select(.name == $NAME)).command = $CMD' \
          final-task.json > final-task-cmd.json
        mv final-task-cmd.json final-task.json

        TASK_DEF_ARN=$(aws ecs register-task-definition \
          --cli-input-json file://final-task.json \
          --query 'taskDefinition.taskDefinitionArn' \
          --output text)
```

Every caller supplies one. `app/.github/workflows/deploy-beta-001.yaml` — the stack whose plan F23 quotes:

```
:363   command: '["bundle", "exec", "puma", "-C", "config/puma.rb"]'
:527   command: '["sleep", "infinity"]'          # the runner
:817   command: '["bundle", "exec", "sidekiq", "-C", "config/${{ matrix.worker.configuration_file }}"]'
```

Line `:527`'s `["sleep", "infinity"]` is the exact literal the F23 plan proposes to **remove** from `beta-001-runner`. The same shape holds on `deploy-shared-001.yaml` (`:388` puma, `:552` and `:1039` `sleep infinity`, `:842` the sidekiq worker matrix).

**Source:** `modules/ecs_service/variables.tf:132-136`; `modules/ecs_service/main.tf:30`; `app-atento-001/terraform.tfvars:217-233`; `app/.github/actions/deploy-ecs/action.yaml:5-6, 87-97`; `app/.github/workflows/deploy-beta-001.yaml:363, 527, 817`; `app/.github/workflows/deploy-shared-001.yaml:388, 552, 842, 1039`. All re-read directly during this pass — full excerpts and the cross-stack scan in auxiliary `taskdef-drift_apply_1.md` (E7, E8), labeled `[VERIFIED-HERE]`.

**Significance — three consequences, in order of severity.**

1. **Terraform's config and production have ALWAYS differed on `container_definitions`, and Terraform could not see it.** With `track_latest = false` (the default, and the state today), Terraform compares its config against **its own last-registered revision** — not against what the services actually run. The comparison was always self-referential, so it was always clean. `track_latest` did not introduce the gap; it removed the blindfold. This is F2's mechanism one layer deeper: F2 established that Terraform *owns* the content; F24 establishes that **what it owns is not what runs**.

2. **An apply that registered Terraform's own revision today would produce a task definition with no command.** For the runner that means losing `["sleep", "infinity"]` — the container would start on the image's own default, not the command the service depends on. This is not hypothetical drift; it is the concrete content of the plan diff in F23. It is also precisely why the revert did not go through `terraform apply` (F25).

3. **It falsifies the stated rationale of commit `13d32a0`**, which F2 already cites for the removal of `ignore_changes = [container_definitions]`. Verbatim, via `git -C ~/Projects/4Shark/terraform log -1 --format=%B 13d32a0`:

> "Removed ignore_changes on container_definitions so Terraform has full ownership of task definition content."

**Terraform does not have full ownership. It only stopped looking.** But the commit is more defensible than that sentence alone suggests, and the detail is load-bearing — its full body continues:

> "Startup commands for web (puma) and worker (sidekiq) are also declared to match the running task definitions."

and its subject is scoped: `feat(integrator-almaviva): bring environment variables under Terraform management`. Those commands **are** declared in that stack — `integrator-almaviva/compute.tf:130` (`["bundle", "exec", "puma", "-C", "config/puma.rb"]`), `:171` (`["bundle", "exec", "sidekiq"]`). So the "full ownership" claim was **locally true for `integrator-almaviva`** and silently false for the four app stacks: the commit removed `ignore_changes` from the **shared** `modules/ecs_service`, carrying its premise to stacks it never audited and which never declared a command. The failure is not that the author overreached in their own stack — it is that a shared module made a per-stack claim global. (Aux E9.)

---

### F25 — For a state-only change, the safe revert is S3 object-version restore, not `terraform apply` — the revert plan would have armed the #711 bomb

**Evidence — why the plan path was rejected.** With `track_latest` removed from config but state still holding GHA's revision (F23's state diff), the revert plan produces an `N to add / N to destroy` on the task definitions. In AWS API terms those are not abstractions:

- the `N to destroy` is a **`DeregisterTaskDefinition`** against the revisions the services are actually running;
- the `N to add` is a **`RegisterTaskDefinition`** built from Terraform's config — the config that, per F24, carries no `command`.

Combined with F1 and F3 (the service's pointer is ignored, so Terraform would never move the services onto the new revision), that is the #711 shape exactly: a freshly-registered revision nothing runs, and live services pinned to a pointer Terraform cannot see. Reverting via plan would have **deliberately armed the bomb this spike exists to document**.

**Evidence — the path used instead.** Per stack, the pre-apply state object version was restored directly:

```
aws s3api copy-object --copy-source '<bucket>/<key>?versionId=<pre-apply-version-id>' ...
```

with a pre-flight before any write: download both object versions, diff them, and confirm `serial`, `lineage`, resource count, and the changed-field set matched expectations (F23's state diff) — only then copy the old version forward. Result on all three stacks:

```
No changes. Your infrastructure matches the configuration.
```

All services `desired == running`; **zero ECS mutation API calls** across the whole revert — no `RegisterTaskDefinition`, no `DeregisterTaskDefinition`, no `UpdateService`.

**Evidence — why no lock had to be invalidated.** `app-beta-001/providers.tf:46-51`:

```hcl
  backend "s3" {
    bucket       = "4shark-terraform-state"
    key          = "app-beta-001/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
```

`use_lockfile = true` with no `dynamodb_table` argument — locking is S3-native (a lock object beside the state), so there is no DynamoDB digest entry that a hand-restored state object would leave stale and inconsistent.

**Source:** the revert mechanics and verification are the coordinator's own tool results, preserved in auxiliary `taskdef-drift_apply_1.md` (E5, E6) as `[MAIN-TRACE]`; the backend configuration is `app-beta-001/providers.tf:46-51`, re-read during this pass (E6a, `[VERIFIED-HERE]`).

**Significance.** This is a reusable operational finding independent of the `track_latest` question, and it generalizes to a rule with a stated precondition: **when an apply changed only Terraform's state and not the infrastructure, the revert is a state operation — and routing it through `terraform apply` can be strictly more dangerous than the change being reverted.** The asymmetry is the point: the forward apply mutated nothing in AWS (F23, half one), so the "undo" has nothing in AWS to undo — but a plan-driven revert does not know that, and computes a mutation from a config that does not match reality (F24). The preconditions that made the object restore safe are what make it a rule rather than an anecdote: (a) the forward change was verified state-only; (b) both object versions were diffed on `serial`/`lineage`/resource-count/changed-fields **before** the write; (c) the backend uses S3-native locking, so there is no external digest to desynchronize. **Not verified:** whether this holds for a backend using the `dynamodb_table` locking mode — no 4Shark stack was checked for that, and the DynamoDB digest question is not addressed by any evidence here.

---

## Trade-offs surfaced

Options for **Q1** (ownership) and **Q3** (safe destroy). Every row is sustained by the Findings named; "do nothing" is included because it is defensible.

| Approach | Pros | Cons | Sustained by |
|---|---|---|---|
| **A. Do nothing; keep the ignore, rely on review** | Zero change, zero risk of breaking blue/green or GHA deploys. The trap has fired once in the module's lifetime. | The review anchors on the plan, which is exactly what lied (F14). The next occurrence is a coin-flip on someone remembering. #711's author *did* verify — just the wrong thing. | F3, F14 |
| **B. Expand/contract the destroy (Parallel Change)** — remove the reference from the task def → deploy so services adopt it → *then* destroy the resource | The named, canonical pattern (F: Fowler, S9); already cited by `DEPLOYMENT-STRATEGY.md` for schema. Needs no module change. `datadog-key-standard` Phase 3 already does this shape (`PLAN.md:206`). | Three steps and a deploy where the engineer expected one apply. Every deploy on a productive stack hits the engineer-only Sidekiq queue gate (`PLAN.md:210-211`). Discipline, not a guarantee — nothing forces it. | S9, F9, F13 |
| **C. `check` block asserting running == managed revision** | Surfaces the divergence at **plan** time, where the reasoning happens. Data source exposes what is needed (F8), and — confirmed via the provider's own Go source (F21) — the exposed attribute genuinely reflects the service's on-record configured value, workable for detecting the #711 shape specifically. Self-documenting; no ownership change. | **Warns only — cannot block** (F8). One API call per service on every plan. Does not, on its own, confirm every *running task* matches the revision during an in-progress rollout (F21's residual caveat) — a narrower gap than the original "unconfirmed data source" concern. | F8, F21 (S1, S3, S19, S20, S21) |
| **D. `triggers = { redeployment = plantimestamp() }` + `force_new_deployment`** | Vendor-documented mechanism (F16). Structural — no human step. | **May not work at all under `ignore_changes = [task_definition]`** (F16, unverified) — forces a redeployment but may redeploy the OLD ignored revision, not adopt a new one. Redeploys **every** service on **every** apply — colliding head-on with the phased-Sidekiq discipline and the queue gate (`DEPLOYMENT-STRATEGY.md:53-61`). | F16 (S2), F6 (S4) |
| **E. Remove `ignore_changes = [task_definition]` entirely; Terraform owns the pointer with no `track_latest`** | Removes the trap at its root; plan tells the truth again. F2 shows the repo already made the symmetrical move for *content* and it stuck. | Terraform would fight both CodeDeploy (web) and GHA `register-task-definition` (workers, F4) unless paired with `track_latest` (see row I) — the ignore exists for real reasons. Provider **confirmed** to error on task-def updates with a CodeDeploy controller — AWS API `InvalidParameterException`, reproduced across two independent tools and provider versions 2020–2024 (F22, issue #12703 — previously UNVERIFIED, now fetched and load-bearing). High blast radius on the web service specifically. | F1, F4, F5, F22 |
| **F. Split the module — ignore only where an external deployer really owns the pointer** | F4 shows the current ignore is applied far wider than its stated justification. A narrower ignore shrinks the trap's surface. | The workers *also* have an out-of-band deployer (GHA, F4) — so the narrowing may buy little in practice on its own; combines naturally with row I (narrow to web/CodeDeploy only, adopt `track_latest` for the rest). Needs per-service analysis. | F4 |
| **G. Family-tracking, as `ecs_scheduled_task` does** | Proven inside this repo; no divergence window can exist (F12). | ECS services must name a concrete revision; whether the EventBridge family-tracking trick transfers to a *service* is **unverified** and probably not available — `track_latest` (row I) is the provider-native equivalent for services specifically. | F12 |
| **H. Fix the README (F2)** | Cheap, uncontroversial, removes an actively misleading document that inverts ownership. | Changes no behaviour. Does not prevent recurrence on its own. | F2 |
| **I. Add `track_latest = true` to `aws_ecs_task_definition.this`, drop `task_definition` from the service's `ignore_changes` — for plain-`ECS`-controller services only** — **CORRECTED 2026-07-16, see below the table** | Provider-native, purpose-built for exactly this scenario (F17); field-tested by the community module's default path as of v6.0.0 (F18); directly portable to 4Shark's own hand-rolled module without adopting any external module (F20). | **The mechanism was applied to three productive stacks and produces permanent replacement drift on every task definition (F23).** Not because the argument misbehaves — because the two sides it compares do not match (F24). **Confirmed NOT applicable to the `CODE_DEPLOY`-controlled web service** (F22). Module maintainers' own position: residual tracking issues are "a limitation of the AWS ECS service/API," not something this argument fully closes (F18, S11). | F17, F18, F20, F22, **F23, F24** |

> **Row I — correction record (2026-07-16). The row is not withdrawn; its premise and its cons are both wrong as originally written, in opposite directions.**
>
> **Original text, preserved verbatim** (pros): *"Provider-native, purpose-built for exactly this scenario (F17); field-tested by the community module's default path as of v6.0.0 (F18); directly portable to 4Shark's own hand-rolled module without adopting any external module (F20); **matches the worker services' actual shape (F4 — plain `ECS` controller, external GHA registrar)**."* (cons): *"**Untested by this spike against a real apply** — whether the resulting plan/apply behaves as a silent no-op (already-correct) or an immediate, visible redeploy attempt is inferred from the documented argument semantics (F17), not observed. **Confirmed NOT applicable to the `CODE_DEPLOY`-controlled web service** (F22) […]"*
>
> **What the evidence changed:**
>
> 1. **The con "untested by this spike against a real apply" is retired — it is now tested (F23), and neither predicted outcome occurred.** The row offered a binary: "a silent no-op (already-correct)" or "an immediate, visible redeploy attempt". The observed answer is **both, in sequence, and a third thing after**: the enabling apply is a silent no-op (0 added, 9 changed, 0 destroyed, no new revision, no service touched), and the *steady state* is a permanent `7 to add / 7 to destroy` on every plan thereafter. The row's framing assumed the question resolved at the moment of the apply. It resolves one plan later.
> 2. **The pro "matches the worker services' actual shape" is correct about the shape and wrong about the consequence.** The premise holds — the workers *are* plain-`ECS`-controller services with an external GHA registrar, exactly what `track_latest` targets (F4, F17). But the shapes `track_latest` makes Terraform compare are not the ones the row assumed: it compares Terraform's **rendered config** against **AWS's latest ACTIVE revision**, and those diverge on `container_definitions` because the config declares no `command` and GHA injects one (F24). The row implicitly assumed the two would agree once the revision pointer was correct. They do not, and never did.
> 3. **The `CODE_DEPLOY` con stands unchanged** (F22) — it was already confirmed in the previous pass and this experiment did not touch the web service.
>
> **What this does NOT establish:** that row I is unusable. The permanent drift is a symptom of F24, not of `track_latest`. Whether the row becomes viable once F24 is addressed — and what "addressed" means — is exactly the open question in Uncertainty 9, which this spike cannot close. The row is neither ruled in nor ruled out; the evidence relocated the obstacle from the argument to the config.

Options for **Q5** (mechanical guard):

| Approach | Pros | Cons | Sustained by |
|---|---|---|---|
| **P. PreToolUse BLOCK on a dangerous apply** | Hard stop at the real moment. Plan file always exists (F14). | **Ruled out by ADR-004's own criterion** — the rule has a legitimate exception (destroying a truly-unreferenced param), so a block refuses legitimate applies. | F15 (ADR-004:35-37), F14 |
| **Q. PreToolUse FLAG / context injection on `terraform apply`** | Matches ADR-004's flag tier and the existing `inject-terraform-context.sh` precedent. Never blocks. | Several AWS calls per apply. Cluster enumeration is the false-negative surface. Advisory — a warning can be ignored, like the plan was. | F15 |
| **R. No hook — a written rule + a verification step in the terraform review** | Zero machinery. The incident record already names the check (`PLAN.md:24`): list what each service *actually* runs and grep it. | Exactly the discipline that failed in #711. | F14, F3 |
| **S. Post-apply / CI verification rather than pre-apply** | Catches it wherever the apply came from, including a human's terminal. | Detects **after** the bomb is armed — though before it detonates (the failure only surfaces when a task tries to start). | F3, F9 |

---

## What remains uncertain

Highest-value first, among what remains open after this and the previous revision. Each is answerable; none was resolved here.

1. **Does `force_new_deployment` / `triggers` actually adopt the NEW revision when `task_definition` is in `ignore_changes`, or redeploy the OLD one?** This single fact decides whether option D works or is a no-op. Answerable with a `terraform plan` on a scratch service, or by reading the provider's `resource_aws_ecs_service` update path (partially read in this pass for a different purpose — F22's E8 — but the specific behavior for a `triggers`-forced redeployment under an ignored `task_definition` was not traced). **F16 is stated as an open question, not a claim.**
2. **Do any other ACTIVE revisions still reference `/<stack>/DD_API_KEY`?** Only the current running revision of three services on one stack (`beta-001`) was checked. A service scaled to zero, or a rollback to an older revision, could still hit the destroyed parameter. `demo-001`'s workers were at 0 desired at collection time (`PLAN.md:33`) — a stack where nothing tried to start is a stack where the bomb is armed but silent.
3. **Are the other three stacks structurally identical?** Assumed (shared module), verified only on `beta-001`.
4. **Is the KMS key `mrk-fa0cda…` terraform-managed?** Grep says probably not; not positively confirmed (aux `awsdump_1._not_researched`).
5. ~~**What actually happens on the apply that first surfaces a divergence under option I, for the plain-`ECS`-controller worker services?**~~ **RESOLVED 2026-07-16 — observed, not reasoned. See F23.** Both halves of the question are now answered, and they answer differently: the **enabling apply IS a silent no-op** (`0 to add, 9 to change, 0 to destroy`; no new revision registered; no service touched) — but the **steady state is NOT** (`7 to add, 0 to change, 7 to destroy` on the very next plan, every task definition `must be replaced`, permanently). The original question's framing — "does the plan show the service needing an update, or does it silently resolve because `track_latest` already reflects the true latest at plan time?" — contained a false dichotomy: `track_latest` does reflect the true latest, and that is exactly *why* it does not silently resolve, because Terraform's config does not match that latest (F24). Applied to `beta-001`, `demo-001`, and `atento-001`, then reverted (F25).
6. **`precondition` / `postcondition` as a blocking alternative to `check`** was not evaluated.
7. **Whether the ignore is genuinely needed per-service** (option F) — requires per-service analysis of what GHA does to workers vs. what CodeDeploy does to web.
8. **Whether CodeDeploy itself rewrites the ECS service's top-level `taskDefinition` field during/after a blue/green swap, and if so how often** — genuinely unresolved (F22's closing caveat, S26); does not change F22's conclusion (the AWS API rejects a Terraform-initiated change regardless), but would determine the theoretical frequency of the failure if the ignore were ever removed on the web service.
9. **Why does the config-vs-GHA `container_definitions` divergence exist at all (F24) — is the GHA injection the INTENDED design, with Terraform's config deliberately partial, or is the config meant to be complete and has silently rotted?** **This is the question that decides what the real fix is, and this spike cannot close it — no source found states the intent either way.** The two readings lead to opposite remediations and are not distinguishable from the evidence gathered:
   - **If the injection is intended** (Terraform owns the task definition's *skeleton*; the deployer owns the *runtime command*, which legitimately varies per workflow — note `deploy-beta-001.yaml:817` builds the command from a `${{ matrix.worker.configuration_file }}` matrix, i.e. one Terraform-declared family backs N distinct worker commands), then the config is correct as written, `track_latest` is simply incompatible with this design, and the fix (if any) lies elsewhere — possibly a *narrower* `ignore_changes` on `container_definitions[*].command` rather than on the whole field or the whole pointer.
   - **If the config is meant to be complete**, then it has rotted since commit `13d32a0` (F24, consequence 3) — that commit declared commands in `integrator-almaviva` while removing `ignore_changes` from the shared module, and the app stacks were never brought up to the premise. The fix is to declare the commands in the app stacks' tfvars, which would then make row I's mechanism behave as it was assumed to.
   
   **What was NOT done, and would likely settle it:** a targeted archaeology pass — `git log -S 'command' -- app-*/terraform.tfvars` and the history around `13d32a0`'s module change — was not run (aux `taskdef-drift_apply_1.md`, E10). This is answerable; it simply was not in this pass's authorized scope. **Until it is answered, F24 is a confirmed divergence with an unknown intent — and "unknown intent" is precisely why no option here is ranked.** Note also that the matrix-driven worker command above is evidence *bearing on* the first reading but is not a statement of intent; treating it as one would be the inference this spike declines to make.

   ---

   **RESOLVED 2026-07-16 (fourth pass, recorded by main) — the FIRST reading is correct: the GHA injection is the intended design. The config is deliberately partial and did NOT rot.** The archaeology pass this entry named as out of scope was run. Three pieces of evidence, each verified against the live repo:

   - **`command` has NEVER been declared under `ecs_services` in any app stack, in the entire history.** Restricted to the mainline — `git log --oneline origin/develop -S'    command ' -- app-shared-001/terraform.tfvars app-atento-001/terraform.tfvars app-beta-001/terraform.tfvars app-demo-001/terraform.tfvars` — the search returns **exactly one** commit: `618eaa4` (`refactor(app): rename environment directories to follow app- prefix convention`), and `git show 618eaa4 --stat` confirms it is a **pure rename** (`{atento-001 => app-atento-001}/terraform.tfvars | 0` — zero lines changed); it matches only because `-S` counts occurrences and the file moved path. So on `develop`, across the whole history, **no commit has ever added, removed, or altered a `command` declaration in an app stack's tfvars at all.** Not removed at some point — never present. This falsifies the second reading ("config rotted") outright.

     **Correction — the original write-up of this bullet cited the wrong commit, and the `output-verifier` caught it.** It ran the search with `--all` (every ref, including unmerged branches), which returned a second commit, `cc8d586` (`feat(app): add security event archiver scheduled task to shared-001 and atento-001`), and cited its diff — `command             = ["bundle", "exec", "rails", "cron:security_event:archiver"]` inside the `scheduled_tasks = {` block — as the key evidence. **The diff quote is verbatim and the commit is real, but `cc8d586` lives on `origin/feature/security-event-archiver-cron` and is NOT merged** (`git merge-base --is-ancestor cc8d586 origin/develop` → exit 1). A reader checking the live tree finds no `security_event` anywhere — which is exactly what the verifier found, and why it returned REJECT on suspicion of fabricated evidence. Both were right: the citation was real but pointed at an unmerged branch, presented as if it were mainline history. The `develop`-only search above replaces it, and the conclusion is **strengthened** rather than weakened: one pure-rename commit is a stronger negative than two commits needing interpretation.
   - **The split is deliberate and visible within a single file.** `app-shared-001/terraform.tfvars` declares `command` **7 times**, every one under `scheduled_tasks`; **zero** under `ecs_services`. A cron task has a fixed command Terraform declares; a service has a per-deploy command it does not.
   - **The coupling that makes it necessary — and it RETRACTS this entry's own cardinality hypothesis.** `deploy-shared-001.yaml` gives each worker its own `configuration_file` (`sidekiq_commission_tiger_shark.yml`, `sidekiq_deal_indexation.yml`, `sidekiq_commission_without_deal_indexation.yml`, …) and the deploy passes `command: '["bundle", "exec", "sidekiq", "-C", "config/${{ matrix.worker.configuration_file }}"]'`. **Each family maps to exactly ONE command** — so "one Terraform-declared family backs N distinct worker commands" (first reading, above) is **wrong as stated** and is retracted. The real reason is coupling: the referenced file lives in the ***app* repo**, so declaring the command in Terraform would bind the infrastructure repo to the application's internal config layout. The conclusion the hypothesis supported survives; the reasoning behind it does not.

   **What this repositions (the load-bearing consequence).** If GHA is the *legitimate* owner of the service's `container_definitions` content, then `ignore_changes = [container_definitions]` — added by `5f0a472` (`fix(ecs): prevent Terraform from overwriting CI/CD task definition revisions`) — **was correct for the app stacks**. `13d32a0` removed it with a rationale true for `integrator-almaviva` (where the commands *are* declared, `compute.tf:130,171`) and the removal leaked through the **shared module** into the app stacks, where it is not true. It went unnoticed for ~4 months because `track_latest = false` made Terraform compare its config against its own stale revision instead of against reality. **F24 therefore documents a divergence that is BY DESIGN; what is defective is that the guard protecting that contract was removed for the app stacks.** The remediation shape stays the engineer's call and is not decided here.

**Resolved in this revision (were open in the previous revision):**

- ~~Uncertainty 2: what does `data.aws_ecs_service.task_definition` actually return?~~ **Resolved** — see F21. It is a direct passthrough of `DescribeServices`'s `taskDefinition` field (the service's on-record configured value), traced through the provider's own Go source; the ambiguous doc string is a copy-paste artifact from the resource argument's description, not a description of the data source's behavior. Option C is confirmed workable for the #711 shape.
- ~~Uncertainty 7: is `track_latest` + an un-ignored `task_definition` safe against a `CODE_DEPLOY`-controller service?~~ **Resolved — no.** See F22. Confirmed at the AWS ECS API level (`InvalidParameterException`, HTTP 400), reproduced by two independent tools (Terraform, AWS CDK) across provider versions 2020–2024, and never fixed (the load-bearing issue, #12703, was closed by stale-bot inactivity, not a maintainer decision). Trade-off rows E and I are updated accordingly.

**Resolved in the third pass (2026-07-16), by experiment rather than by research:**

- ~~Uncertainty 5: what actually happens on the apply that first surfaces a divergence under option I?~~ **Resolved — see F23.** The enabling apply is a silent no-op; the steady state is a permanent `N to add / N to destroy`. Observed on three productive stacks, then reverted (F25). Trade-off row I and Suggested Option 5 are corrected in place accordingly.
- **New, and not previously suspected: F24.** The experiment revealed that Terraform's declared `container_definitions` has never matched what production runs, on every app service on every app stack — a defect independent of `track_latest`, still live after the revert. Its cause is now **Uncertainty 9** above, which this spike cannot close.

**Resolved in the previous revision (carried forward for continuity):**

- ~~The `max(latest, current)` idiom was NOT found.~~ **Found** — see F18, F19. It exists in the community module's pre-v6.0.0 source and was superseded, not absent.
- ~~Whether the community has a settled answer at all (Q1).~~ **Partially answered** — settled for the plain-`ECS`-controller/external-CI-CD shape (F17, F18); now also settled (in the negative) for the `CODE_DEPLOY`-controller shape (F22).

---

## Suggested options for main and the engineer

These are groupings of the table rows, not a ranking. Several combine; none is presented as preferred.

- **Option 1 — Documentation only.** Take H (fix the README) and R (write the rule + the verification step the incident record already names). Cheapest; changes no infrastructure. Accepts that the next occurrence depends on human attention.
- **Option 2 — Plan-time visibility.** Add C (`check` block) — no longer gated on an unresolved uncertainty; F21 confirms the data source's `task_definition` attribute is workable for detecting the #711 shape. Makes the plan stop being silent. Still advisory (cannot block, F8) and does not, on its own, confirm every running task during an in-progress rollout (F21's residual caveat).
- **Option 3 — Process.** Adopt B (expand/contract for any destroy of a launch-resolved resource) and decide whether it belongs in `DEPLOYMENT-STRATEGY.md` as a fourth trigger, in `TERRAFORM-POLICY.md`, or in a new home — F13 shows it currently has no owner.
- **Option 4 — Mechanical.** Q (flag/inject at the apply boundary) or S (post-apply/CI check). P (block) is ruled out by ADR-004's criterion unless the engineer overrides that criterion deliberately.
- **Option 5 — Structural, worker services only. CORRECTED 2026-07-16 — the option's obstacle moved, and it is no longer where this option assumed.** *Original text, preserved verbatim: "I (`track_latest`, un-ignore `task_definition`) for the plain-`ECS`-controller worker services specifically — the shape it is purpose-built for and the shape that actually fired in the incident (F4, F17, F18). Carries uncertainty 5 above (untested against a real apply — the plain-`ECS` rollout behavior). The `CODE_DEPLOY` interaction question no longer applies to this option's scope (workers are not `CODE_DEPLOY`-controlled) and is resolved regardless by F22."* — **What changed:** uncertainty 5 is resolved (F23), and the answer is that this option, applied as written, leaves every task definition in permanent replacement drift. **The blocker is not `track_latest`; it is F24** — Terraform's config declares no `command` while GHA injects one, so the two sides `track_latest` makes Terraform compare cannot agree. This option is therefore **not viable as written, and not refuted either**: it is *gated on* F24 being resolved first, and F24's resolution depends on Uncertainty 9 (is the GHA injection intended?), which is unanswered. If the config is meant to be complete, declaring the commands would plausibly unblock this option; if the injection is intended by design, this option is incompatible with that design and a narrower ignore (e.g. on `container_definitions[*].command` only) would be the shape to evaluate instead — **neither path is evaluated here, and neither is recommended.**
- **Option 6 — Structural, full scope, INCLUDING the web service.** D, E, F, or G for the `CODE_DEPLOY`-controlled web service specifically. **D carries uncertainty 1 (untested).** **E and I are now confirmed (F22), not merely suspected, to fail against the web service** — any Terraform-initiated `task_definition` change on a `CODE_DEPLOY`-controller service is rejected by the AWS ECS API itself, independent of `track_latest`. F and G remain unevaluated/unverified for this scope respectively.
- **Option 7 — Do nothing (A).** Defensible: the trap fired once, the recovery was understood and took ~1h, and web never went down. The cost of every other option is nonzero.

**Regardless of the option chosen, items independent of the decision and answerable now:** uncertainty 2 above (are other ACTIVE revisions still referencing the destroyed parameter — i.e. is a bomb still armed on a scaled-to-zero stack?) and F2 (the README actively misleads about ownership).

---

> **Authoring note.** Written by `@agent-spike`. Every claim carries a `file:line` + verbatim quote or a URL + confirmed substring; sources that failed to fetch or came only from search summaries are tagged UNVERIFIED in `taskdef-drift_sources_1.md` and sustain nothing. Per the engineer's explicit instruction, no option is ranked and no recommendation is made.
>
> **2026-07-15 revision.** The `output-verifier` flagged a citation-integrity failure in the original F7 (issue #165 status misstated as "Open"; actually `closed`, `state_reason: completed`, milestone v6.0.0). The coordinator independently re-confirmed via `gh api` and directed a full investigation, not just a string fix. This revision: corrected F7 in place with the real status and citation; investigated PR #217 and provider PR #30154 to determine what v6.0.0 actually resolved (F17–F20, new); confirmed the `max(latest, current)` idiom exists (reversing the original "not found" conclusion, F19); re-examined F5 and F6 to state precisely what each still supports on its own, independent of #165's corrected status; added Trade-off row I and re-worded row E's/F's/G's cons to reference it; added uncertainties 7–8 and resolved/reversed the former uncertainty 7; and preserved the full raw evidence (issue/PR JSON, pre-v6 and v6 module source, provider docs) in new auxiliary `taskdef-drift_v6release_1.md`. Nothing from the original findings was silently removed — every correction is marked inline with what changed and why.
>
> **2026-07-15 follow-up revision (same day, second pass).** The engineer authorized closing two specific uncertainties from the previous revision. This pass: added F21 (Uncertainty 2 — `data.aws_ecs_service.task_definition` traced through the AWS provider's own Go source, confirmed a direct `DescribeServices` passthrough, the doc-string ambiguity explained as a copy-paste artifact) and F22 (Uncertainty 7 — `track_latest` + un-ignored `task_definition` confirmed unsafe against a `CODE_DEPLOY`-controller service, via a previously-surfaced-but-unfetched issue, `#12703`, now fetched directly via `gh api`, plus a cross-tool corroboration from `aws/aws-cdk#7040`); corrected F8 and F18 in place with pointers to the resolving findings, preserving their original text; updated Trade-off rows C, E, and I with the new evidence; renumbered and restructured the uncertainties list to move both resolved items into a dedicated "Resolved in this revision" section while keeping the previous revision's resolutions in their own section for continuity; updated Suggested Options 2, 5, and 6 to reflect the resolutions; and added new auxiliary `taskdef-drift_followup_1.md` with the full raw evidence (Go source excerpts, `gh api` JSON for #12703 with comments and events, the cross-tool issue, and the AWS API doc quotes), plus corresponding entries S17–S26 in `taskdef-drift_sources_1.md`. One sub-question was deliberately left unresolved and recorded as such rather than forced (F22's closing caveat, uncertainty 8) — whether CodeDeploy itself rewrites the service's top-level `taskDefinition` field was not found addressed in any AWS doc fetched, and this is stated plainly rather than papered over, per the citation discipline's preference for an honest "not found" over a manufactured answer.
>
> **2026-07-16 empirical revision (third pass).** The engineer authorized applying `track_latest = true` to `aws_ecs_task_definition.this` on three productive stacks (`beta-001`, `demo-001`, `atento-001`) as step 1 of a two-step plan; it was applied and then reverted. This is the first pass in this document whose central evidence is an experiment rather than documentation, and the provenance is labeled accordingly throughout the new auxiliary: `[MAIN-TRACE]` for the coordinator's own tool results (plan/apply output, state diffs — **not re-derivable, the change is reverted**) and `[VERIFIED-HERE]` for every code citation, each re-read against the live repo during this pass. This revision: added **F23** (Uncertainty 5 resolved by observation — the enabling apply IS inert, the steady state is NOT, contradicting the two-step plan's premise), **F24** (the finding that matters most, and the one nobody was looking for — `track_latest` did not create a divergence, it revealed that Terraform's declared `container_definitions` has never matched production on any app service on any app stack, which also falsifies commit `13d32a0`'s "full ownership" claim while showing *why* that commit was locally defensible), and **F25** (the safe revert for a state-only change is S3 object-version restore, because the revert *plan* would have armed the #711 bomb — a reusable operational finding with its preconditions stated); corrected **Trade-off row I** and **Suggested Option 5** in place with their original text preserved verbatim and the correction reasoned rather than asserted; resolved **Uncertainty 5** in place; and added **Uncertainty 9**, which this spike explicitly **cannot** close — whether the GHA `command` injection is the intended design or the config has rotted, the question that decides what F24's real fix is. Per the citation discipline, three errors in the commissioning briefing were caught by re-reading the sources rather than trusted: `deploy-shared-001.yaml:828` is actually **:842**; the uncertainty resolved is **#5**, not #8 (#8 is the unrelated CodeDeploy question and remains open); and the `command` divergence is **not scoped to the runner** — it holds for every service in every app stack, which makes F24 materially larger than briefed. Nothing was rewritten: the document was reconstructed segment-wise from the pre-existing file so every untouched line is byte-identical, and the result was mechanically diffed against a backup to confirm only the intended additions and the three marked corrections changed. Per the engineer's standing instruction, no option is ranked and no recommendation is made — F24's remediation in particular is deliberately left open, because its intent is unknown and guessing it is the failure mode this spike was created to document.
