# Raw external sources — verbatim quotes

Fetched 2026-07-15. Preserved so the SPIKE can be revised (re-weighted, sources added/dropped) without re-fetching. Each entry records the URL, what was asked of it, and the literal substrings the SPIKE relies on.

Per `CITATION-DISCIPLINE.md`: a source that failed to fetch or returned unusable content is marked **UNVERIFIED** and may not sustain any derivation.

> **2026-07-15 correction pass.** S5 originally misstated issue #165's status as "Open" — the `wip` label was conflated with the issue's actual `state`. The `output-verifier` flagged this as a citation-integrity failure; the coordinator independently re-confirmed via `gh api`; this file and the SPIKE were corrected in place, and the investigation was extended (S11–S16, auxiliary `taskdef-drift_v6release_1.md`) to determine what the resolving PR actually did. S5 is corrected below rather than removed, so the nature of the original error stays visible.

> **2026-07-15 follow-up pass (same day, second investigation).** The engineer authorized closing Uncertainty 2 (what does `data.aws_ecs_service.task_definition` actually return) and Uncertainty 7 (is `track_latest` + un-ignored `task_definition` safe against a `CODE_DEPLOY`-controller service). S17–S26 below resolve both, sourced from the provider's own Go implementation (not just its docs) and from `gh api` on the specific issue this SPIKE had previously surfaced-but-not-fetched (#12703). Full raw evidence — Go source excerpts, JSON, AWS doc quotes — preserved in auxiliary `taskdef-drift_followup_1.md`.

---

## S1 — HashiCorp: `check` blocks

**URL:** https://developer.hashicorp.com/terraform/language/checks
**Status:** fetched OK
**Relevant to:** Q2 (can `plan` detect the divergence?)

Verbatim:

> "Use the `check` block to validate your infrastructure outside of the typical resource lifecycle."

> "The `check` block executes as the last step of plan or apply operation, after Terraform has planned or provisioned your infrastructure."

> "When a `check` block's assertion fails, Terraform reports a warning and continues executing the current operation."

The page's own example uses a data source (`data "http" "terraform_io"`) inside the check block, confirming data sources are usable there.

**What this sustains:** a `check` block runs at plan time, may read a data source, and produces a WARNING — it cannot block. That is the precise shape of what is and is not achievable inside `terraform plan`.

---

## S2 — AWS provider docs: `aws_ecs_service` resource

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown
**Status:** fetched OK (the Registry rendering at registry.terraform.io is JS-rendered and returned an empty body — the provider repo's markdown source is the same content, fetched directly)
**Relevant to:** Q1, Q2, Q3

Verbatim on `ignore_changes`:

> "You can utilize the generic Terraform resource lifecycle configuration block with ignore_changes to create an ECS service with an initial count of running instances, then ignore any changes to that count caused externally (e.g., Application Autoscaling)."

The example given is scoped to `desired_count` only:

```terraform
resource "aws_ecs_service" "example" {
  # ... other configurations ...
  desired_count = 2
  lifecycle {
    ignore_changes = [desired_count]
  }
}
```

**Notable negative:** the extraction found **no** guidance anywhere in this resource's documentation for `ignore_changes` on `task_definition`. The only mention of an external controller owning the task definition is:

> "Required unless using the EXTERNAL deployment controller."

Verbatim on `force_new_deployment`:

> "Enable to force a new task deployment of the service. This can be used to update tasks to use a newer Docker image with same image/tag combination (e.g., myimage:latest), roll Fargate tasks onto a newer platform version, or immediately deploy ordered_placement_strategy and placement_constraints updates."

Verbatim on `triggers`:

> "Map of arbitrary keys and values that, when changed, will trigger an in-place update (redeployment)."

> "The key used with `triggers` is arbitrary."

The docs place this under a section titled **"Redeploy Service On Every Apply"** with the example:

```terraform
resource "aws_ecs_service" "example" {
  # ... other configurations ...

  force_new_deployment = true

  triggers = {
    redeployment = plantimestamp()
  }
}
```

**Verbatim on the `task_definition` ARGUMENT description (re-confirmed in the follow-up pass, see S20):**

> "Family and revision (`family:revision`) or full ARN of the task definition that you want to run in your service. Required unless using the `EXTERNAL` deployment controller. If a revision is not specified, the latest `ACTIVE` revision is used."

**What this sustains:** `ignore_changes = [task_definition]` is **not** a vendor-documented pattern — it is community practice. `triggers` + `plantimestamp()` + `force_new_deployment` IS vendor-documented, as "Redeploy Service On Every Apply". **This finding is UNCHANGED by the S5 correction** — `track_latest` (S11–S13) is a distinct argument on `aws_ecs_task_definition`, not on `ignore_changes` or `triggers`; the provider still documents no `ignore_changes` guidance for `task_definition`. The `task_definition` argument description quoted above is the RESOURCE's input-argument text — see S20/S21 for why this matters to the DATA SOURCE question (Uncertainty 2).

---

## S3 — AWS provider docs: `aws_ecs_service` DATA SOURCE

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/d/ecs_service.html.markdown
**Status:** fetched OK
**Relevant to:** Q2

The data source's attribute list, verbatim:

> "arn, availability_zone_rebalancing, capacity_provider_strategy, created_at, created_by, deployment_configuration, deployment_controller, deployments, desired_count, enable_ecs_managed_tags, enable_execute_command, events, health_check_grace_period_seconds, iam_role, launch_type, load_balancer, network_configuration, ordered_placement_strategy, pending_count, placement_constraints, platform_family, platform_version, propagate_tags, running_count, scheduling_strategy, service_registries, status, task_definition, task_sets, tags"

On `task_definition` specifically:

> "Family for the latest ACTIVE revision or full ARN of the task definition"

**What this sustains:** `task_definition` IS exposed by the data source, so a `check` block can read what the service currently points at. **Original caveat, RESOLVED in the follow-up pass (see S17–S21):** this doc string is confirmed — via the provider's own Go source, not speculation — to be a documentation artifact, not a description of runtime behavior. The data source returns exactly what `DescribeServices` reports for the service's `taskDefinition` field, with zero family-resolution logic. See F21 in the SPIKE for the full resolution.

---

## S4 — hashicorp/terraform-provider-aws issue #34129

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/34129
**Status:** fetched OK
**Relevant to:** Q1, Q3

Title, verbatim:

> "[Bug]: aws_ecs_service triggers based on computed values do not result in redeployment #34129"

Status: **Closed as not planned.**

The reporter's stated constraint, verbatim:

> "Terraform must ignore changes to the `task_definition` argument on `aws_ecs_service.main` are ignored to avoid drift detection."

(sic — the grammar is the reporter's.) The context is external CodePipeline deployments creating revisions outside Terraform.

The reproduction, verbatim:

> "Run `terraform apply` and note that the Task Definition 'must be replaced', but no changes are planned against `aws_ecs_service.main`"

— requiring a second apply for the trigger change to be detected.

**Notable gap:** the extraction surfaced **no maintainer response proposing a solution**. The issue carries the problem statement, a config example, and reproduction steps only.

**What this sustains, re-examined after the S5 correction:** this is a **narrower** complaint than #165 — it is specifically about `triggers` computed from other resources not causing redeployment, in a CodePipeline (not GitHub-Actions-plain-service) context, and it was closed **not planned** (the provider team declined to fix the `triggers` computed-value gap), which is a *different* disposition from #165's "closed, completed, fixed by v6.0.0". This finding still stands on its own terms — the provider team declined this specific request — but it no longer needs to (and should not) be read together with the old S5 as joint evidence that "the community has no answer to the core problem". It only shows: (a) `triggers` on computed values is a documented dead end (independently useful — it bears on Trade-off row D in the SPIKE), and (b) the reporter's own words confirm the general shape of the problem exists in the wild beyond 4Shark.

---

## S5 — terraform-aws-modules/terraform-aws-ecs issue #165 — CORRECTED 2026-07-15

> **Correction notice.** This entry originally stated the issue was "Open (marked 'wip')". That was wrong: the `wip` **label** is real and still attached, but the issue's **state** is `closed`, `state_reason: completed`. Caught by the `output-verifier`, independently re-confirmed by the coordinator via `gh api`, and re-verified again here directly via `gh api` (not a WebFetch summary). See auxiliary `taskdef-drift_v6release_1.md` (E1) for the full raw JSON and (E2–E8) for what actually resolved it.

**URL:** https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/165
**Status:** fetched OK, via `gh api repos/terraform-aws-modules/terraform-aws-ecs/issues/165`, 2026-07-15 (direct API call, not a rendered-page fetch)
**Relevant to:** Q1

Title, verbatim (accurate in the original entry, unchanged):

> "The recommended workaround for ignoring task definition changes causes the service's container_definitions to be overwritten on every Terraform apply, even ones that don't touch the service."

**Corrected status — verbatim JSON fields:**

```json
"state": "closed"
"state_reason": "completed"
"closed_at": "2025-07-07T12:24:48Z"
"milestone": { "title": "v6.0.0" }
"closed_by": { "login": "bryantbiggs" }
```

The `wip` label is still attached (`"labels":[{"name":"wip", ...}]`) — the label and the state are different fields; the original fetch conflated them and reported the label as if it were the state.

The module's documented workaround, quoted in the issue body (accurate, unchanged):

> "a scenario where the service, task definition, and container definition are all managed by Terraform, the following configuration could be used to allow an external party to change the image of the container definition without conflicting with Terraform"

The reporter's problem, verbatim (accurate, unchanged):

> "whenever we make any change to our Terraform (even if it doesn't touch the ECS service in any way), the container_definitions of the service are recreated."

**What this sustains, corrected:** this issue is **closed as completed**, resolved by PR #217 (merged 2025-07-07, milestone v6.0.0 — see S11). It does **not**, on its own, sustain "the community has no settled answer" — that derivation in the original SPIKE was built on the wrong status. What replaces it: S11–S14 establish specifically what v6.0.0 did (removed a custom module-level hack, replaced it with the provider-native `track_latest` argument for the *default* service path), and the SPIKE's updated findings state precisely what is and is not resolved by that change (the plain-`ECS`-controller case is addressed; the `CODE_DEPLOY`-controller case, which is 4Shark's web service, is now separately and definitively resolved by S17–S26 below — NOT addressed, and confirmed unsafe at the AWS API level).

---

## S6 — AWS: ECS ResourceInitializationError troubleshooting

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/resource-initialization-error.html
**Status:** fetched OK
**Relevant to:** Q4

Section headings, verbatim (each is an error condition that prevents a task from starting):

> "The task cannot pull secrets from AWS Systems Manager Parameter Store. Check your network connection between the task and AWS Systems Manager."

> "The task can't pull the secret from Secrets Manager. The task can't retrieve the secret with ARN '{{secretARN}}' from Secrets Manager. Check whether the secret exists in the specified Region."

> "The task cannot find the Amazon CloudWatch log group defined in the task definition."

> "failed to initialize logging driver"

On the logging driver error, verbatim:

> "This error occurs when your task fails to find the CloudWatch log group you defined in the task definition."

> "The error indicates that the CloudWatch group in the task definition does not exist."

> "The issue is either that the group specified in the task definition is incorrect, or the log group does not exist."

On the Secrets Manager case, the documented causes table includes, verbatim:

> "The secret ARN doesn't exist"

and

> "The task execution role defined in the task definition doesn't have the permissions for Secrets Manager."

Also documented as its own failure class:

> "failed to invoke EFS utils commands to set up EFS volumes"

**What this sustains:** the Q4 enumeration. A missing secret ARN, a missing log group, and a task-execution-role permission gap each produce a task that **fails to start** — the same failure shape as the incident, arising from different resource classes.

---

## S7 — AWS: `awslogs` log group auto-creation

**URL:** (web search result set; the authoritative statement appears in the AWS re:Post / ECS troubleshooting material surfaced by the search)
**Status:** **UNVERIFIED** — the specific claim below came back through a search-result summary, not a direct fetch of a single authoritative page whose substring was confirmed.
**Relevant to:** Q4

Claim surfaced: the `awslogs` driver does not create the log group automatically unless `awslogs-create-group` is set to `true`, and `AmazonECSTaskExecutionRolePolicy` does not include `logs:CreateLogGroup`.

**Handling:** this is tagged UNVERIFIED and does **not** sustain any derivation on its own. It is not needed: **S6** independently and directly establishes that a missing log group fails the task ("The error indicates that the CloudWatch group in the task definition does not exist."), and the 4Shark module's own code shows `awslogs-create-group` is simply absent from the options map (`modules/ecs_service/main.tf:45-52`) — a code fact, not a claim about AWS behaviour.

---

## S8 — AWS: ECS built-in blue/green deployments (July 2025)

**URL:** https://aws.amazon.com/about-aws/whats-new/2025/07/amazon-ecs-built-in-blue-green-deployments/
**Status:** fetched OK
**Relevant to:** Q1

Verbatim:

> "When you use a blue/green deployment strategy, Amazon ECS provisions the new application version alongside the old, and allows you to validate the new application version before routing production traffic to it."

> "You can use blue/green deployments and deployment lifecycle hooks for new and existing Amazon ECS services in all commercial AWS Regions using the AWS Management Console, SDK, CLI, CloudFormation, CDK, and Terraform."

**Notable negative:** this page does **not** mention CodeDeploy and does **not** state that the built-in feature removes a CodeDeploy dependency. Community articles assert "ECS-native blue/green is now the recommended default" — that phrasing was surfaced only in a search-result summary and is **UNVERIFIED**; it is not used to sustain anything in the SPIKE. **Distinct from `track_latest` (S11–S13)** — this is native ECS blue/green (`deployment_configuration.strategy = "BLUE_GREEN"` with `deployment_controller.type = "ECS"`), a different mechanism from both the legacy `CODE_DEPLOY` controller 4Shark's web service uses and from `track_latest`.

---

## S9 — Martin Fowler: Parallel Change

**URL:** https://martinfowler.com/bliki/ParallelChange.html
**Status:** fetched OK
**Relevant to:** Q3

Verbatim:

> "Parallel change, also known as expand and contract, is a pattern to implement backward-incompatible changes to an interface in a safe manner, by breaking the change into three distinct phases: expand, migrate, and contract."

> "In the _expand_ phase you augment the interface to support both the old and the new versions."

> "During the _migrate_ phase you update all clients using the old version to the new version."

> "Once all usages have been migrated to the new version, you perform the _contract_ phase to remove the old version and change the interface so that it only supports the new version."

**What this sustains:** the named pattern that the incident's correct sequencing maps onto. 4Shark's `DEPLOYMENT-STRATEGY.md` §6 already cites this pattern by name for schema changes.

---

## S10 — browniebroke TIL: Terraform and ECS task revisions

**URL:** https://browniebroke.com/tils/2023-05-05-terraform-and-ecs-task-revisions/
**Status:** fetched OK — but returned a **negative** result for what was asked
**Relevant to:** Q1

This page was fetched specifically to source the `data aws_ecs_task_definition` + `max(latest, current)` idiom named in the investigation brief. The fetch found **no such content**. The extraction states the page instead documents:

```terraform
lifecycle {
  ignore_changes = [task_definition]
}
```

combined with `force_new_deployment = true` — i.e. the same ignore pattern, not a max/latest strategy.

**What this sustains:** nothing affirmative on its own. **Superseded finding:** the original SPIKE concluded from this negative result that "the `max(latest, current)` idiom was NOT found" and treated uncertainty #7 as open. That conclusion was **too narrow a search, not a correct negative** — see S14: the idiom exists, verbatim, in the pre-v6.0.0 source of `terraform-aws-modules/terraform-aws-ecs` (`modules/service/main.tf:593-609` at tag `v5.12.1`), just not in this particular blog post. S10 stays in the record as an example of a genuinely negative single-source result that should have prompted a wider search before the uncertainty was declared, rather than as evidence the idiom does not exist anywhere.

---

## S11 — Corrected via `gh api`: issue #165 and resolving PR #217 (see auxiliary for full detail)

**URLs:**
- https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/165 (re-fetched via `gh api`)
- https://github.com/terraform-aws-modules/terraform-aws-ecs/pull/217

**Status:** fetched OK, directly via `gh api repos/terraform-aws-modules/terraform-aws-ecs/pulls/217`, 2026-07-15
**Relevant to:** Q1

PR #217 title, verbatim:

> "feat!: Upgrade AWS provider and min required Terraform version to `6.0` and `1.5.7` respectively"

Merged: `"merged": true`, `"merged_at": "2025-07-07T12:24:46Z"`.

The PR's own breaking-changes list, verbatim (identical text also found in the shipped `docs/UPGRADE-6.0.md`):

> "The 'hack' put in place to track the task definition version when updating outside of the module has been removed. Instead, users should rely on the `track_latest` variable to ensure that the latest task definition is used when updating the service. Any issues with tracking the task definition version should be reported to the *ECS service team* as it is a limitation of the AWS ECS service/API and not the module itself."

The PR's motivation section lists, verbatim: `"Resolves #165"` (among 28 other issues in the same release).

**What this sustains:** the specific mechanism that resolved #165 — replacing a custom module-level hack with the provider-native `track_latest` argument (S12, S13). It also sustains the module maintainers' own position that residual task-definition-tracking issues are an **AWS ECS API limitation**, not something the module (or, by extension, a hand-rolled Terraform configuration) can fully close — a caveat this spike carries forward rather than treating `track_latest` as a complete fix. Full JSON preserved in auxiliary `taskdef-drift_v6release_1.md` (E1, E2).

---

## S12 — Provider PR #30154: `track_latest` added to `aws_ecs_task_definition`

**URL:** https://github.com/hashicorp/terraform-provider-aws/pull/30154
**Status:** fetched OK, directly via `gh api repos/hashicorp/terraform-provider-aws/pulls/30154`, 2026-07-15
**Relevant to:** Q1

```json
"title": "r/aws_ecs_task_definition: add track_latest attribute"
"merged_at": "2024-02-12T18:13:32Z"
```

Body, verbatim:

> "This PR allows users to make the task definitions track always the latest one if `track_latest` is set to true."

> "The rationale for this Pull Request is that in some projects/environments/teams, Task Definitions can be updated outside Terraform. For example, a CI/CD process could bumps the Docker Tag version by creates a new TaskDefinition using the previous one as a base template, within the process, it might move the previous TaskDefinition to inactive. Because of this, when Terraform is executed again it cannot track the changes and forces a new resource creation."

> "With this Pull Request, we would allow users to track always the changes against the latest TaskDefinition, so, if all the fields are the same, Terraform won't promote any change."

**Notable caveat, verbatim (submission-time, testing section):**

> "Regarding the acceptance tests, I'd need some guidance from someone, please. I'd like to write the tests, but I'm not sure how sould I write them."

**What this sustains:** `track_latest` is a **provider-level** argument (merged into `hashicorp/terraform-provider-aws` on 2024-02-12 — over a year before the community module adopted it), not a community-module-only feature. Any Terraform configuration declaring the raw `aws_ecs_task_definition` resource — including 4Shark's own hand-rolled `modules/ecs_service` — can set it directly, without depending on the community module. The scenario described ("a CI/CD process bumps the Docker Tag version by creating a new TaskDefinition") is structurally the same shape as 4Shark's GitHub Actions worker deploy (`app/.github/workflows/deploy-beta-001.yaml:418`).

---

## S13 — Provider docs: `track_latest` argument (verified twice, two fetch methods)

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_task_definition.html.markdown
**Status:** fetched OK (WebFetch), 2026-07-15; corroborated independently by the raw module source at S14 (`main.tf:1001: track_latest = var.track_latest`) and `variables.tf:731-736`
**Relevant to:** Q1

Verbatim:

> "`track_latest` - (Optional) Whether should track latest `ACTIVE` task definition on AWS or the one created with the resource stored in state. Default is `false`. Useful in the event the task definition is modified outside of this resource."

**What this sustains:** the exact mechanism. `track_latest` makes the resource resolve to whatever the ACTUAL latest ACTIVE revision is — including one registered by an external process — rather than only the revision Terraform's own state remembers creating.

---

## S14 — The `max(latest, current)` idiom, located directly in the community module's pre-v6 source

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/contents/modules/service/main.tf?ref=v5.12.1`
**Status:** fetched OK, directly via `gh api`, 2026-07-15
**Relevant to:** Q1 (this corrects uncertainty #7 of the original SPIKE)

Verbatim, `modules/service/main.tf:593-609` at tag `v5.12.1` (the last v5.x tag before v6.0.0):

```hcl
locals {
  create_task_definition = var.create && var.create_task_definition

  # This allows us to query both the existing as well as Terraform's state and get
  # and get the max version of either source, useful for when external resources
  # update the container definition
  max_task_def_revision = local.create_task_definition ? max(aws_ecs_task_definition.this[0].revision, data.aws_ecs_task_definition.this[0].revision) : 0
  task_definition       = local.create_task_definition ? "${aws_ecs_task_definition.this[0].family}:${local.max_task_def_revision}" : var.task_definition_arn
}

data "aws_ecs_task_definition" "this" {
  count = local.create_task_definition ? 1 : 0

  task_definition = aws_ecs_task_definition.this[0].family
  # ...
}
```

**What this sustains:** the `data aws_ecs_task_definition` + `max(latest, current)` idiom named in the original investigation brief **does exist** — in the community module's own pre-v6.0.0 source. It was not found in the specific blog post fetched to look for it (S10), which was too narrow a search. `docs/UPGRADE-6.0.md:13` (quoted in S11) calls this exact block "the 'hack'" and states it has been removed and replaced by `track_latest`. This corrects the original SPIKE's uncertainty #7 ("not found") to "found — and superseded".

---

## S15 — The v6.0.0 module still ignores `task_definition`, but only for one branch (`EXTERNAL` controller)

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/contents/modules/service/main.tf?ref=master` and `.../variables.tf?ref=master`
**Status:** fetched OK, directly via `gh api`, 2026-07-15
**Relevant to:** Q1 (scope of what v6.0.0 resolved)

The `master` branch declares **two** mutually exclusive `aws_ecs_service` resources. The default (`ignore_task_definition_changes = false`, `main.tf:39-40`) has, verbatim, `main.tf:381-385`:

```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
    ]
  }
```

— **no `task_definition` in this list.** The opt-in branch (`ignore_task_definition_changes = true`, `main.tf:392-393`) has, verbatim, `main.tf:735-741`:

```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
      task_definition,
      load_balancer,
    ]
  }
```

— the same trap shape as 4Shark's own module, unchanged. This branch is gated (`main.tf:25`) by:

```hcl
  is_external_deployment = try(var.deployment_controller.type, null) == "EXTERNAL"
```

`variables.tf:38-43` documents `ignore_task_definition_changes`, verbatim:

> "Whether changes to service `task_definition` changes should be ignored" — `default = false`

`variables.tf:731-736` documents `track_latest`, verbatim (same text as S13):

> "Whether should track latest `ACTIVE` task definition on AWS or the one created with the resource stored in state. Useful in the event the task definition is modified outside of this resource" — `default = true`

**Notable negative:** a `grep` of `main.tf`, `variables.tf`, and `docs/UPGRADE-6.0.md` for `CODE_DEPLOY` / `CodeDeploy` returned **no matches**. The module's branching is keyed on the ECS **`EXTERNAL`** deployment-controller type (used with `aws_ecs_task_set`), not on the legacy **`CODE_DEPLOY`** deployment-controller type that 4Shark's web service uses (confirmed live: `beta-001-web-service`, `deploymentController.type = "CODE_DEPLOY"` — `taskdef-drift_awsdump_1.json`). Whether the module's default (`track_latest`, no ignore on the service) is usable against a `CODE_DEPLOY`-controller service is resolved by S17–S26 below (the follow-up pass) rather than left open — see F22 in the SPIKE.

**What this sustains:** v6.0.0 did not eliminate `ignore_changes = [task_definition]` — it **scoped it** to the `EXTERNAL`-controller path and shipped a genuine alternative (`track_latest`, no ignore) for the plain-`ECS`-controller path, which is the shape #165's reporter actually had (GitHub Actions against a plain service) and the shape of 4Shark's own WORKER services (confirmed `controller: ECS` — see `taskdef-drift_awsdump_1.json`). The `CODE_DEPLOY` case (4Shark's web service) is resolved (in the negative) by S17–S26.

---

## S16 — 4Shark does not consume the community module

**Command:** `grep -rn --include='*.tf' 'terraform-aws-modules/ecs' ~/Projects/4Shark/terraform`
**Result:** no matches
**Relevant to:** Q1 (applicability to 4Shark)

**What this sustains:** `modules/ecs_service` in 4Shark's own repo is a fully hand-written module — every resource is a direct `aws_*` resource, no `source = "terraform-aws-modules/..."` call anywhere in the repo. Adopting the community module wholesale is not on the table and is not what S11–S15 make available. What IS directly available: `track_latest` (S12, S13) is an argument on the raw AWS-provider `aws_ecs_task_definition` resource, addable to 4Shark's own `modules/ecs_service/main.tf:12` task definition resource without taking on the community module as a dependency. The community module's v6.0.0 rewrite is field evidence that the argument is the maintained replacement for the old hack — not itself something 4Shark would import.

---

## S17 — `aws_ecs_service` DATA SOURCE Go source: direct passthrough, no family resolution

**Command:** `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service_data_source.go --jq .content` (base64-decoded)
**Status:** fetched OK, directly, 2026-07-15
**Relevant to:** Uncertainty 2

Verbatim, `internal/service/ecs/service_data_source.go:565`:

> `d.Set("task_definition", service.TaskDefinition)`

**What this sustains:** the data source's `task_definition` attribute is an unconditional, direct assignment from the AWS SDK response's own `TaskDefinition` field — no `max()`, no family lookup, no "latest ACTIVE" computation anywhere in the Go implementation. Full excerpt and the surrounding `Read` function in auxiliary `taskdef-drift_followup_1.md` (E1).

---

## S18 — `findServiceByTwoPartKey` calls `DescribeServices` directly

**Command:** `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service.go --jq .content` (base64-decoded)
**Status:** fetched OK, directly, 2026-07-15
**Relevant to:** Uncertainty 2

Verbatim, `internal/service/ecs/service.go:2002`:

> `output, err := conn.DescribeServices(ctx, input)`

**What this sustains:** the entire call chain from the data source's `Read` function down to the AWS SDK is a straight `DescribeServices` call with no intermediate transformation. Combined with S17, this confirms the data source's `task_definition` output IS, byte-for-byte, `DescribeServices`'s `services[].taskDefinition` response field. Full excerpt in auxiliary `taskdef-drift_followup_1.md` (E2).

---

## S19 — AWS API reference: `Service.taskDefinition` field description

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Service.html
**Status:** fetched OK (WebFetch), 2026-07-15
**Relevant to:** Uncertainty 2

Verbatim:

> "The task definition to use for tasks in the service. This value is specified when the service is created with CreateService, and it can be modified with UpdateService."

**What this sustains:** the field is an explicit, API-writable value describing what the service is CONFIGURED to run — set by `CreateService`, changeable by `UpdateService` — not a computed "latest ACTIVE revision of the family". This is exactly what S17/S18 show the data source echoes back unmodified.

---

## S20 — AWS provider RESOURCE docs: the `task_definition` ARGUMENT description — the source of the data source's garbled doc string

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown
**Status:** fetched OK (WebFetch), 2026-07-15
**Relevant to:** Uncertainty 2

Verbatim:

> "Family and revision (`family:revision`) or full ARN of the task definition that you want to run in your service. Required unless using the `EXTERNAL` deployment controller. If a revision is not specified, the latest `ACTIVE` revision is used."

**What this sustains:** this is the RESOURCE's INPUT-argument description (what value you may pass in when creating/updating a service). The data source's doc string ("Family for the latest ACTIVE revision or full ARN of the task definition", S3) is a garbled, truncated echo of this text, misapplied to describe the OUTPUT attribute. S17–S19 show the actual runtime semantics of the output attribute have nothing to do with this "latest ACTIVE" language — it is a documentation artifact, not a description of behavior.

---

## S21 — AWS API reference: `Deployment.status` and `Deployment.taskDefinition` — configured target, not per-task confirmation; scoped to `ECS` controller only

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Deployment.html
**Status:** fetched OK (WebFetch), 2026-07-15
**Relevant to:** Uncertainty 2 (residual caveat)

Verbatim, the type's scope note:

> "The details of an Amazon ECS service deployment. This is used only when a service uses the `ECS` deployment controller type."

Verbatim, `status`:

> "PRIMARY The most recent deployment of a service. ACTIVE A service deployment that still has running tasks, but are in the process of being replaced with a new `PRIMARY` deployment. INACTIVE A deployment that has been completely replaced."

Verbatim, `taskDefinition`:

> "The most recent task definition that was specified for the tasks in the service to use."

**What this sustains:** `deployments[]` (with PRIMARY/ACTIVE/INACTIVE) applies only to plain-`ECS`-controller services — the worker services (F4), not the `CODE_DEPLOY`-controlled web service (which uses `taskSets` instead). Even the per-deployment field describes a TARGET ("specified... to use"), not a live per-task confirmation. For the #711 incident shape (zero deployment activity, one static deployment entry, no rollout in progress) this caveat is immaterial; for the general "is every running task actually on this revision" question, per-task `describe-tasks` → `taskDefinitionArn` remains the ground truth.

---

## S22 — `hashicorp/terraform-provider-aws` issue #12703 — fetched (previously UNVERIFIED, surfaced-but-not-fetched)

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/12703
**Status:** fetched OK, directly via `gh api repos/hashicorp/terraform-provider-aws/issues/12703` + `/comments` + `/events`, 2026-07-15
**Relevant to:** Uncertainty 7

Title, verbatim: "ECS with CodeDeploy Blue/Green". `state: closed`, `state_reason: not_planned`.

Original report (2020), verbatim:

> "Error: Error applying plan: ... aws_ecs_service.default: Error updating ECS Service (...): InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment."

Independently reconfirmed, provider v5.53.0, comment dated 2024-06-14, verbatim:

> "If I declare task_definition, I get this error: ... InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. If I do not declare task_definition, I get this error: InvalidParameterException: Family should not be null or empty."

**Disposition, verbatim from the events timeline:** labeled `stale` by `github-actions[bot]` on 2026-06-07; closed by `github-actions[bot]` on 2026-07-12 (30 days later — the standard stale-bot window). `closed_by: github-actions[bot]`, `state_reason: not_planned`. **This is an automated staleness closure, not a maintainer decision that evaluated and declined a fix** — no maintainer comment in the 9-comment thread proposes or rejects a code-level solution.

**What this sustains:** this is no longer UNVERIFIED — it is the load-bearing evidence for Uncertainty 7. A `terraform apply` that changes `task_definition` on a `CODE_DEPLOY`-controller service fails at the AWS API level (`InvalidParameterException`), reconfirmed across provider versions from 2020 through 2024, with the issue only closed by inactivity in July 2026 (never fixed). Full JSON, comments, and events in auxiliary `taskdef-drift_followup_1.md` (E6).

---

## S23 — Cross-tool corroboration: `aws/aws-cdk` issue #7040

**URL:** https://github.com/aws/aws-cdk/issues/7040
**Status:** fetched OK, directly via `gh api repos/aws/aws-cdk/issues/7040`, 2026-07-15
**Relevant to:** Uncertainty 7

Verbatim:

> "The FargateService class is trying to update the ECS Service when a new task definition is provided to the service when `DeploymentControllerType.CODE_DEPLOY` is specified. When using Blue/Green deployment strategy powered by CodeDeploy in a Fargate Service, only the desired count, deployment configuration, and health check grace period can be updated using the `update-service`. Otherwise a new CodeDeploy deployment should be created."

Verbatim error log quoted in the issue:

> "Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. (Service: AmazonECS; Status Code: 400; Error Code: InvalidParameterException; Request ID: 83f32eb8-4ed5-4263-b944-9df4d7fa3a62)"

**What this sustains:** the identical AWS API error, same message text, reproduced by a completely different tool (AWS CDK / CloudFormation, not Terraform) calling the same underlying `UpdateService` API. Confirms the restriction is at the AWS ECS API level, not a Terraform-provider-specific bug. Full body in auxiliary `taskdef-drift_followup_1.md` (E7).

---

## S24 — The AWS provider's `aws_ecs_service` resource UPDATE code: no `CODE_DEPLOY` special-casing

**Command:** `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service.go --jq .content` (same fetch as S18)
**Status:** fetched OK, directly, 2026-07-15
**Relevant to:** Uncertainty 7

Verbatim, `internal/service/ecs/service.go:1802-1804`:

```go
if d.HasChange("task_definition") {
	input.TaskDefinition = aws.String(d.Get("task_definition").(string))
}
```

A full-file grep for `CODE_DEPLOY`/`CodeDeploy` in `resourceServiceUpdate` returns no matches.

**What this sustains:** the provider does not skip, warn, or pre-validate a `task_definition` change against `deployment_controller.type` — it sends the `UpdateService` call unconditionally, and AWS's ECS API itself is what rejects it (S22, S23). `track_latest` changes only what `aws_ecs_task_definition`'s own computed attributes resolve to; it does nothing to prevent this rejection once a value differing from AWS's on-record value is sent to `UpdateService` for a `CODE_DEPLOY`-controller service. Full excerpt in auxiliary `taskdef-drift_followup_1.md` (E8).

---

## S25 — `terraform-aws-modules/terraform-aws-ecs` issue #169 does not mention `CODE_DEPLOY`

**URL:** https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/169
**Status:** fetched OK, directly via `gh api`, 2026-07-15
**Relevant to:** Uncertainty 7 (search-completeness)

Full body read; no mention of `CODE_DEPLOY`, `deployment_controller`, or any CodeDeploy interaction anywhere in the issue that proposed adopting `track_latest`.

**What this sustains:** combined with the fully-read #12703 thread (S22) and the fully-read v6.0.0 module source (S15), no source fetched across either investigation pass discusses `track_latest` and `CODE_DEPLOY` jointly — a genuine, confirmed negative (not a shallow one), consistent with F22's conclusion that the two are separately-discussed topics everywhere examined.

---

## S26 — AWS's blue/green tutorial: CodeDeploy tracks state via `taskSetsInfo`, not confirmed against the service's own field — genuinely unresolved sub-question

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-blue-green.html
**Status:** fetched OK (WebFetch), 2026-07-15
**Relevant to:** Uncertainty 7 (the "continuously vs. only at deploy time" sub-question)

Verbatim, the tutorial's own `get-deployment-target` example output:

> `"taskSetsInfo": [{"status": "ACTIVE", "trafficWeight": 0.0, ...}, {"status": "PRIMARY", "trafficWeight": 100.0, ...}]`

**What this sustains, and what it does not:** confirms CodeDeploy tracks blue/green state through its own `taskSetsInfo` (CodeDeploy-side), distinct from the ECS `deployments[]` model (S21). It does **not** state anywhere fetched whether the ECS `Service.taskDefinition` top-level field itself gets rewritten by CodeDeploy during/after a swap. This specific sub-question is recorded as **genuinely unresolved** — not found addressed in any AWS doc fetched — but it does not change the answer to Uncertainty 7: S22/S23/S24 establish the rejection happens on any Terraform-initiated `UpdateService` call regardless of what CodeDeploy itself does to the field between deployments.

---

## Sources deliberately NOT used

- Community blog posts surfaced in search results (oneuptime, cloudthat, dev.to, medium, ewere.tech) — appeared in search-result summaries only, never individually fetched and substring-confirmed. Per rule 4 of `CITATION-DISCIPLINE.md` they are UNVERIFIED and sustain nothing here.
- `registry.terraform.io` rendered pages — JS-rendered, return an empty body to a plain fetch. The provider repo's `website/docs/**.markdown` sources are the same content and were used instead.
- `hashicorp/terraform-provider-aws` issue #20121 ("Keep LATEST aws_ecs_task_definition container_definition image revision") — fetched, confirmed **Open**, no resolution documented. Adjacent to this investigation (cited in PR #30154's own references) but not load-bearing for any SPIKE finding — recorded here for completeness, not cited as a Finding source.
