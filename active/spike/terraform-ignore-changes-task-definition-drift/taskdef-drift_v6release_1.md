# Raw evidence — terraform-aws-modules/terraform-aws-ecs v6.0.0 and `track_latest`

Collected 2026-07-15, in response to a citation-integrity correction (F7/S5 originally misstated issue #165's status as "Open"). Preserved so the corrected findings can be re-checked without re-fetching. All fetches below used `gh api` directly (not WebFetch summaries) except where noted, per the coordinator's instruction to re-verify independently.

---

## E1 — Corrected status of issue #165

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/issues/165`
**Fetched:** 2026-07-15, directly via `gh api` (JSON, not a search summary)

Verbatim fields:

```json
"state": "closed"
"state_reason": "completed"
"closed_at": "2025-07-07T12:24:48Z"
"milestone": { "title": "v6.0.0", ... }
"closed_by": { "login": "bryantbiggs", ... }
```

Title (verbatim, unchanged from the original SPIKE — this part was already accurate):

> "The recommended workaround for ignoring task definition changes causes the service's container_definitions to be overwritten on every Terraform apply, even ones that don't touch the service."

Reporter's problem, verbatim (unchanged from original SPIKE — also accurate):

> "whenever we make any change to our Terraform (even if it doesn't touch the ECS service in any way), the container_definitions of the service are recreated."

**What was wrong:** the original SPIKE stated "Open (marked 'wip')" — the `wip` **label** is real and still attached, but the issue's **state** is `closed`, `state_reason: completed`, closed against milestone `v6.0.0`. The label and the state are different fields; the original fetch reported the label as if it were the state.

---

## E2 — PR #217: the resolving PR

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/pulls/217`
**Fetched:** 2026-07-15, directly via `gh api`

```json
"title": "feat!: Upgrade AWS provider and min required Terraform version to `6.0` and `1.5.7` respectively"
"merged": true
"merged_at": "2025-07-07T12:24:46Z"
"merge_commit_sha": "29b257a92ea0da04ffe6fd21790ae6d3aa691cde"
```

The PR body's own itemized breaking-change list, verbatim, includes:

> "The 'hack' put in place to track the task definition version when updating outside of the module has been removed. Instead, users should rely on the `track_latest` variable to ensure that the latest task definition is used when updating the service. Any issues with tracking the task definition version should be reported to the *ECS service team* as it is a limitation of the AWS ECS service/API and not the module itself."

The PR's motivation section lists, verbatim: `"Resolves #165"` among 28 other issues resolved in the same release.

**Same text also fetched from `docs/UPGRADE-6.0.md` at `master`** (`gh api repos/terraform-aws-modules/terraform-aws-ecs/contents/docs/UPGRADE-6.0.md?ref=master`), confirming the PR body and the shipped upgrade doc carry the identical sentence — this is not a draft-only claim, it is the documented migration guidance.

---

## E3 — The pre-v6 `max(latest, current)` idiom, located and confirmed

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/contents/modules/service/main.tf?ref=v5.12.1`
**Fetched:** 2026-07-15, directly via `gh api` (raw file content, tag `v5.12.1` — the last v5.x tag before v6.0.0)

Verbatim, `modules/service/main.tf:593-614` (v5.12.1):

```hcl
locals {
  create_task_definition = var.create && var.create_task_definition

  # This allows us to query both the existing as well as Terraform's state and get
  # and get the max version of either source, useful for when external resources
  # update the container definition
  max_task_def_revision = local.create_task_definition ? max(aws_ecs_task_definition.this[0].revision, data.aws_ecs_task_definition.this[0].revision) : 0
  task_definition       = local.create_task_definition ? "${aws_ecs_task_definition.this[0].family}:${local.max_task_def_revision}" : var.task_definition_arn
}

# This allows us to query both the existing as well as Terraform's state and get
# and get the max version of either source, useful for when external resources
# update the container definition
data "aws_ecs_task_definition" "this" {
  count = local.create_task_definition ? 1 : 0

  task_definition = aws_ecs_task_definition.this[0].family

  depends_on = [
    # Needs to exist first on first deployment
    aws_ecs_task_definition.this
  ]
```

**This is the idiom the original investigation brief asked about, and the original SPIKE's S10 (browniebroke) reported it as NOT found.** It exists — in the community module's own pre-v6 source, not in the source originally fetched to look for it. `docs/UPGRADE-6.0.md:13` (E2 above) calls this exact mechanism "the 'hack'" and states it "has been removed."

---

## E4 — Module issue #169: the request to adopt `track_latest`

**URL:** https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/169
**Fetched:** 2026-07-15 (WebFetch)

Title, verbatim:

> "Use `track_latest` attribute for the `aws_ecs_task_definition` resource at `service` module #169"

Status: **Closed** (superseded by v6.0.0 / PR #217, per the module's own release notes — E2 lists `#165`, not `#169`, as the specific "Resolves" entry, but the mechanism requested in #169 is exactly what #217 shipped).

The issue quotes the same "max version of either source" rationale as E3's inline comment — confirming the reporter of #169 is asking to replace this exact block with the provider-native `track_latest`.

---

## E5 — Provider PR #30154: `track_latest` added to `aws_ecs_task_definition`

**Command:** `gh api repos/hashicorp/terraform-provider-aws/pulls/30154`
**Fetched:** 2026-07-15, directly via `gh api`

```json
"title": "r/aws_ecs_task_definition: add track_latest attribute"
"state": "closed"
"merged_at": "2024-02-12T18:13:32Z"
```

Body, verbatim:

> "This PR allows users to make the task definitions track always the latest one if `track_latest` is set to true."

> "The rationale for this Pull Request is that in some projects/environments/teams, Task Definitions can be updated outside Terraform. For example, a CI/CD process could bumps the Docker Tag version by creates a new TaskDefinition using the previous one as a base template, within the process, it might move the previous TaskDefinition to inactive. Because of this, when Terraform is executed again it cannot track the changes and forces a new resource creation."

> "With this Pull Request, we would allow users to track always the changes against the latest TaskDefinition, so, if all the fields are the same, Terraform won't promote any change."

**Significance:** `track_latest` is a **provider-level** argument on `aws_ecs_task_definition` itself (merged into `hashicorp/terraform-provider-aws` on 2024-02-12, over a year before the module adopted it in v6.0.0). It is not a community-module-only feature — any Terraform configuration using the raw `aws_ecs_task_definition` resource can set it directly, with no dependency on the community module. The PR description's own example scenario — "a CI/CD process could bump the Docker Tag version by creating a new TaskDefinition" — is structurally identical to 4Shark's GitHub Actions worker deploy (`app/.github/workflows/deploy-beta-001.yaml:418`, `aws ecs register-task-definition`).

**Caveat found:** the PR's own testing section, verbatim: *"Regarding the acceptance tests, I'd need some guidance from someone, please. I'd like to write the tests, but I'm not sure how sould I write them."* — the original author was uncertain about test coverage at submission. Whatever tests exist today were added later (not examined in this spike).

---

## E6 — Provider docs: `track_latest` argument (re-confirmed)

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_task_definition.html.markdown
**Fetched:** 2026-07-15 (WebFetch), same source class as S2 in `taskdef-drift_sources_1.md`

Verbatim:

> "`track_latest` - (Optional) Whether should track latest `ACTIVE` task definition on AWS or the one created with the resource stored in state. Default is `false`. Useful in the event the task definition is modified outside of this resource."

---

## E7 — The v6.0.0 module: two service resources, gated by `ignore_task_definition_changes`

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/contents/modules/service/main.tf?ref=master` (and `variables.tf`, same ref)
**Fetched:** 2026-07-15, directly via `gh api`

The `master` branch (v6.0.0 and later) declares **two mutually exclusive** `aws_ecs_service` resources, verbatim:

`modules/service/main.tf:39-40`:
```hcl
resource "aws_ecs_service" "this" {
  count = local.create_service && !var.ignore_task_definition_changes ? 1 : 0
```

with lifecycle (`main.tf:381-385`):
```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
    ]
  }
```
— **`task_definition` is NOT in this list.**

versus:

`modules/service/main.tf:392-393`:
```hcl
resource "aws_ecs_service" "ignore_task_definition" {
  count = local.create_service && var.ignore_task_definition_changes ? 1 : 0
```

with lifecycle (`main.tf:735-741`):
```hcl
  lifecycle {
    ignore_changes = [
      desired_count, # Always ignored
      task_definition,
      load_balancer,
    ]
  }
```
— **the same trap shape as 4Shark's `modules/ecs_service`, unchanged.**

The task definition resource itself, `main.tf:1001`:
```hcl
  track_latest  = var.track_latest
```

`variables.tf:38-43`:
```hcl
variable "ignore_task_definition_changes" {
  description = "Whether changes to service `task_definition` changes should be ignored"
  type        = bool
  default     = false
  nullable    = false
}
```

`variables.tf:731-736`:
```hcl
variable "track_latest" {
  description = "Whether should track latest `ACTIVE` task definition on AWS or the one created with the resource stored in state. Useful in the event the task definition is modified outside of this resource"
  type        = bool
  default     = true
  nullable    = false
}
```

**Significance:** v6.0.0 did not eliminate `ignore_changes = [task_definition]` from the module — it **scoped it to one branch** (`ignore_task_definition_changes = true`), gated by `local.is_external_deployment` for the companion `aws_ecs_task_set` resources (`main.tf:1456-1533`), where:

```hcl
main.tf:25:  is_external_deployment = try(var.deployment_controller.type, null) == "EXTERNAL"
```

**The module's branching is keyed on `deployment_controller.type == "EXTERNAL"`, not `"CODE_DEPLOY"`.** A `grep` of `main.tf`, `variables.tf`, and `docs/UPGRADE-6.0.md` for `CODE_DEPLOY` / `CodeDeploy` returned **no matches** — the module's documentation and code do not address the legacy AWS-CodeDeploy-application deployment controller (`deployment_controller.type = "CODE_DEPLOY"`) as a distinct case anywhere found in this investigation. 4Shark's web service uses exactly that controller type (`beta-001-web-service`, controller `CODE_DEPLOY` — see `taskdef-drift_awsdump_1.json`). Whether the module's default (`ignore_task_definition_changes = false`, `track_latest = true`, no `ignore_changes` on the service's `task_definition`) is even usable against a `CODE_DEPLOY`-controller service was **not found addressed** in the module's docs, issues, or code — this is a genuine gap in what this spike could confirm, not a claim either way.

---

## E8 — 4Shark does not consume this community module

**Command:** `grep -rn --include='*.tf' 'terraform-aws-modules/ecs' ~/Projects/4Shark/terraform`
**Result:** no matches (exit code 1 — grep found nothing)

**Significance:** `modules/ecs_service` in 4Shark's own repo is a fully hand-written module (confirmed in the original investigation — every resource is a direct `aws_*` resource, no `source = "terraform-aws-modules/..."` call anywhere). Adopting the community module wholesale is not what E1–E7 make available to 4Shark. What IS directly available: `track_latest` (E5, E6) is an argument on the raw AWS-provider `aws_ecs_task_definition` resource — it can be added to 4Shark's own `modules/ecs_service/main.tf:12` task definition resource without adopting the community module at all. The community module's v6.0.0 rewrite (E7) is the clearest *evidence this argument is the field-tested replacement for the old hack*, not itself a dependency 4Shark would take on.
