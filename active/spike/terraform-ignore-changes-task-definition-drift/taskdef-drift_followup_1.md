# Follow-up investigation — raw evidence for Uncertainty 2 and Uncertainty 7

Fetched 2026-07-15 (second pass, after the engineer authorized closing these two specific uncertainties). Preserved per the same rule as `taskdef-drift_v6release_1.md` — so the SPIKE can be revised without re-fetching. Every JSON/Go-source excerpt below was fetched directly via `gh api` (not a rendered-page summary), per the engineer's explicit instruction after the earlier `state`-field misread.

---

## E1 — `aws_ecs_service` DATA SOURCE Go source: the `task_definition` attribute is a direct passthrough

**Command:** `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service_data_source.go --jq .content` (base64-decoded)
**Fetched:** 2026-07-15, current `main` branch
**Relevant to:** Uncertainty 2

Schema declaration, verbatim, `internal/service/ecs/service_data_source.go:444-447`:

```go
				"task_definition": {
					Type:     schema.TypeString,
					Computed: true,
				},
```

The `Read` function, verbatim, `internal/service/ecs/service_data_source.go:498-509, 563-565`:

```go
func dataSourceServiceRead(ctx context.Context, d *schema.ResourceData, meta any) diag.Diagnostics {
	var diags diag.Diagnostics
	conn := meta.(*conns.AWSClient).ECSClient(ctx)

	service, err := findServiceByTwoPartKey(ctx, conn, d.Get(names.AttrServiceName).(string), d.Get("cluster_arn").(string))

	if err != nil {
		return sdkdiag.AppendFromErr(diags, tfresource.SingularDataSourceFindError("ECS Service", err))
	}

	arn := aws.ToString(service.ServiceArn)
	d.SetId(arn)
	d.Set(names.AttrARN, arn)
	...
	d.Set(names.AttrStatus, service.Status)
	d.Set(names.AttrServiceName, service.ServiceName)
	d.Set("task_definition", service.TaskDefinition)
```

**What this shows:** `d.Set("task_definition", service.TaskDefinition)` is an unconditional, direct assignment from the `service` struct's own `TaskDefinition` field — no `max()`, no family lookup, no "latest ACTIVE" resolution logic anywhere in this function. Every other data-source attribute in the same function follows the identical shape (`d.Set(<attr>, service.<Field>)`), confirming this is the data source's general pattern, not a special case for `task_definition`.

---

## E2 — `findServiceByTwoPartKey` calls `DescribeServices` directly — no family resolution upstream either

**Command:** `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service.go --jq .content` (base64-decoded)
**Fetched:** 2026-07-15, current `main` branch
**Relevant to:** Uncertainty 2

Verbatim, `internal/service/ecs/service.go:2001-2051`:

```go
func findServices(ctx context.Context, conn *ecs.Client, input *ecs.DescribeServicesInput) ([]awstypes.Service, error) {
	output, err := conn.DescribeServices(ctx, input)

	if errs.IsA[*awstypes.ClusterNotFoundException](err) || errs.IsA[*awstypes.ServiceNotFoundException](err) {
		return nil, &retry.NotFoundError{
			LastError: err,
		}
	}

	if err != nil {
		return nil, err
	}

	if output == nil {
		return nil, tfresource.NewEmptyResultError()
	}

	// When an ECS Service is not found by DescribeServices(), it will return a Failure struct with Reason = "MISSING"
	for _, v := range output.Failures {
		if aws.ToString(v.Reason) == failureReasonMissing {
			return nil, &retry.NotFoundError{
				LastError: failureError(&v),
			}
		}
	}

	return output.Services, nil
}

func findServiceByTwoPartKey(ctx context.Context, conn *ecs.Client, serviceName, clusterNameOrARN string) (*awstypes.Service, error) {
	input := &ecs.DescribeServicesInput{
		Cluster:  aws.String(clusterNameOrARN),
		Include:  []awstypes.ServiceField{awstypes.ServiceFieldTags},
		Services: []string{serviceName},
	}

	output, err := findService(ctx, conn, input)

	// Some partitions (i.e., ISO) may not support tagging, giving error.
	if errs.IsUnsupportedOperationInPartitionError(partitionFromConn(conn), err) {
		input.Include = nil

		output, err = findService(ctx, conn, input)
	}

	if err != nil {
		return nil, err
	}

	return output, nil
}
```

**What this shows:** the entire call chain — data source `Read` → `findServiceByTwoPartKey` → `findService` → `findServices` → `conn.DescribeServices(ctx, input)` — is a straight AWS SDK `DescribeServices` call with zero intermediate transformation. The data source's `task_definition` attribute IS, byte-for-byte, `DescribeServices`'s `services[].taskDefinition` response field.

---

## E3 — AWS API reference: `Service.taskDefinition` field description

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Service.html
**Fetched:** 2026-07-15 (WebFetch)
**Relevant to:** Uncertainty 2 (adjacent question — configured vs. running)

Verbatim:

> "**taskDefinition** — The task definition to use for tasks in the service. This value is specified when the service is created with CreateService, and it can be modified with UpdateService. Type: String Required: No"

**What this shows:** this is an explicit, API-writable field — set by `CreateService`, changeable by `UpdateService` — describing what the service IS CONFIGURED to run. It is not a computed "latest ACTIVE revision of the family" value. This corroborates E1/E2: the data source returns exactly this field, unmodified.

---

## E4 — AWS provider RESOURCE docs: the `task_definition` ARGUMENT description (the likely source of the data source's garbled doc string)

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown
**Fetched:** 2026-07-15 (WebFetch)
**Relevant to:** Uncertainty 2

Verbatim:

> "Family and revision (`family:revision`) or full ARN of the task definition that you want to run in your service. Required unless using the `EXTERNAL` deployment controller. If a revision is not specified, the latest `ACTIVE` revision is used."

**What this shows:** this is the RESOURCE's argument description — what value you may PASS IN when creating/updating a service (a bare family name resolves to the latest ACTIVE revision AT CREATE/UPDATE TIME, per "If a revision is not specified..."). The DATA SOURCE's doc string quoted in the original SPIKE's F8/S3 — "Family for the latest ACTIVE revision or full ARN of the task definition" — is a garbled, truncated echo of this INPUT-argument description, misapplied to the OUTPUT attribute. E1–E3 show the actual runtime behavior of the output attribute is unrelated to this text: it is a direct readback of whatever `DescribeServices` currently reports, not a "latest ACTIVE" resolution.

---

## E5 — AWS API reference: `Deployment.status` and `Deployment.taskDefinition` — the PRIMARY/ACTIVE/INACTIVE model

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_Deployment.html
**Fetched:** 2026-07-15 (WebFetch)
**Relevant to:** Uncertainty 2 (the residual "configured vs. every task actually running it" caveat)

Verbatim, the type's own scope note:

> "The details of an Amazon ECS service deployment. This is used only when a service uses the `ECS` deployment controller type."

Verbatim, `status`:

> "The status of the deployment. The following describes each state. PRIMARY The most recent deployment of a service. ACTIVE A service deployment that still has running tasks, but are in the process of being replaced with a new `PRIMARY` deployment. INACTIVE A deployment that has been completely replaced."

Verbatim, `taskDefinition`:

> "The most recent task definition that was specified for the tasks in the service to use."

**What this shows:** two things. (1) `deployments[]` (and its PRIMARY/ACTIVE/INACTIVE model) applies **only to plain-`ECS`-controller services** — i.e., exactly the worker services that fired in the incident (F4), not the `CODE_DEPLOY`-controlled web service (which instead uses `taskSets`, per the top-level `Service` type's own description: "Information about a set of Amazon ECS tasks in either an AWS CodeDeploy or an `EXTERNAL` deployment"). (2) Even the per-deployment `taskDefinition` field is described as "the most recent task definition **specified** for the tasks... to use" — i.e., the TARGET, not a live per-task confirmation. During an in-progress rolling deployment a service can have one PRIMARY deployment (new revision, target) and one ACTIVE deployment (old revision, tasks still draining) simultaneously; the top-level `Service.taskDefinition` field mirrors the PRIMARY deployment's target. For the #711 incident shape (a service with zero deployment activity, silently pinned to the old revision — no rollout in progress, `deployments` has exactly one entry) this residual ambiguity does not apply. For confirming that literally every currently-running task executes a given revision in the general case, per-task `describe-tasks` → `taskDefinitionArn` remains the ground truth (as the original SPIKE's F8 already noted).

---

## E6 — `hashicorp/terraform-provider-aws` issue #12703, "ECS with CodeDeploy Blue/Green" — full JSON + comments

**Command:** `gh api repos/hashicorp/terraform-provider-aws/issues/12703` and `gh api repos/hashicorp/terraform-provider-aws/issues/12703/comments` and `gh api repos/hashicorp/terraform-provider-aws/issues/12703/events`
**Fetched:** 2026-07-15, directly via `gh api` (this issue was surfaced but never fetched in the original SPIKE pass — tagged UNVERIFIED there)
**Relevant to:** Uncertainty 7

Header fields, verbatim JSON:

```json
"title": "ECS with CodeDeploy Blue/Green"
"state": "closed"
"state_reason": "not_planned"
"created_at": "2020-04-07T07:24:53Z"
"closed_at": "2026-07-12T18:00:03Z"
```

Original report body, verbatim:

> "When CODE_DEPLOY deployment controller type is utilized with ECS Service, Terraform fails to perform necessary changes."
>
> "Error: Error applying plan: 1 error occurred: * module.service_task.aws_ecs_service.default: 1 error occurred: * aws_ecs_service.default: Error updating ECS Service (arn:aws:ecs:eu-west-1:123456789:service/service-dev-cluster/service-reference-v2-dev-123456abc): InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment."
>
> "Steps to Reproduce: 1. switch to CODE_DEPLOY deployment type with ECS Service 2. change aws_ecs_service.task_definition 3. apply"

Independently reconfirmed by a different reporter, provider v5.53.0, comment dated 2024-06-14T02:15:21Z, verbatim:

> "This is still an issue with version 5.53.0. I have this is my aws_ecs_service: deployment_controller { type = \"CODE_DEPLOY\" } If I declare task_definition, I get this error: Error: updating ECS Service (arn:aws:ecs:eu-central-1:REDACTED:service/stage-api/main-api): InvalidParameterException: Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. If I do not declare task_definition, I get this error: InvalidParameterException: Family should not be null or empty."

**Disposition (events timeline, verbatim):**

```json
{"actor":"github-actions[bot]","created_at":"2026-06-07T18:00:46Z","event":"labeled"}
{"actor":"github-actions[bot]","created_at":"2026-07-12T18:00:03Z","event":"closed"}
```

Labels at close: `["bug", "service/ecs", "stale"]`. `closed_by: github-actions[bot]`.

**What this shows:** the issue was auto-closed by the repository's stale-bot 30 days after being auto-labeled `stale` (2026-06-07 → 2026-07-12) — it is NOT a maintainer decision that evaluated and declined a code fix. No maintainer comment anywhere in the 9-comment thread proposes or rejects a solution; two maintainer comments (`justinretzolk`) only ask reporters to reconfirm reproduction. The problem itself is reconfirmed as still current as of the last technical comment (2024-06-14, provider v5.53.0) — a `terraform apply` that changes `task_definition` on a `CODE_DEPLOY`-controller service fails with `InvalidParameterException` at the AWS API level, independent of provider version across at least 2020–2024.

---

## E7 — Cross-tool corroboration: `aws/aws-cdk` issue #7040 (same AWS API, different tool)

**Command:** `gh api repos/aws/aws-cdk/issues/7040`
**Fetched:** 2026-07-15, directly via `gh api`
**Relevant to:** Uncertainty 7

Verbatim body:

> "The FargateService class is trying to update the ECS Service when a new task definition is provided to the service when `DeploymentControllerType.CODE_DEPLOY` is specified. When using Blue/Green deployment strategy powered by CodeDeploy in a Fargate Service, only the desired count, deployment configuration, and health check grace period can be updated using the `update-service`. Otherwise a new CodeDeploy deployment should be created."

Verbatim error log quoted in the issue:

> "Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment. (Service: AmazonECS; Status Code: 400; Error Code: InvalidParameterException; Request ID: 83f32eb8-4ed5-4263-b944-9df4d7fa3a62)"

**What this shows:** the identical AWS API error (`InvalidParameterException`, HTTP 400), same exact message text, reproduced by a completely different tool (AWS CDK, which synthesizes CloudFormation, not Terraform) calling the same underlying ECS `UpdateService` API. This confirms the restriction is an AWS ECS API-level behavior — not a Terraform-provider bug, not something specific to any one IaC tool. Any tool that issues `UpdateService` with a changed `taskDefinition` against a `CODE_DEPLOY`-controller service hits this error.

---

## E8 — The AWS provider's `aws_ecs_service` resource UPDATE code path: no special-casing for `CODE_DEPLOY`

**Command:** (same fetch as E1/E2) `gh api repos/hashicorp/terraform-provider-aws/contents/internal/service/ecs/service.go`
**Fetched:** 2026-07-15, current `main` branch
**Relevant to:** Uncertainty 7

Verbatim, `internal/service/ecs/service.go:1600-1610, 1802-1804`:

```go
func resourceServiceUpdate(ctx context.Context, d *schema.ResourceData, meta any) diag.Diagnostics {
	var diags diag.Diagnostics
	conn := meta.(*conns.AWSClient).ECSClient(ctx)

	if d.HasChangesExcept(names.AttrForceDelete, names.AttrTags, names.AttrTagsAll) {
		cluster := d.Get("cluster").(string)
		input := ecs.UpdateServiceInput{
			Cluster:            aws.String(cluster),
			ForceNewDeployment: d.Get("force_new_deployment").(bool),
			Service:            aws.String(d.Id()),
		}
	...
		if d.HasChange("task_definition") {
			input.TaskDefinition = aws.String(d.Get("task_definition").(string))
		}
```

A full-file `grep -n "CODE_DEPLOY\|CodeDeploy"` on `service.go` returns matches only for the schema default/validation of the `deployment_controller` argument itself (lines 141, 742-743) and two unrelated data-flattening lines (2174, 2556, 2564) — none inside `resourceServiceUpdate`.

**What this shows:** the provider's update path builds `input.TaskDefinition` unconditionally whenever `task_definition` has changed in Terraform's diff, with **no branch, no guard, no pre-check** for `deployment_controller.type == CODE_DEPLOY` anywhere in the function. The provider does not skip the field, does not warn, does not pre-validate against the controller type — it sends the `UpdateService` call exactly as constructed, and it is AWS's ECS API (not the Terraform provider) that returns `InvalidParameterException` (confirmed at E6/E7). This means `track_latest` (which only changes what `aws_ecs_task_definition`'s own computed attributes resolve to) does nothing to avoid this: whatever value ends up in the service's `task_definition` argument, if it differs from what AWS has on record for a `CODE_DEPLOY`-controller service, the same unconditional code path sends it and the same AWS-side rejection follows.

---

## E9 — `terraform-aws-modules/terraform-aws-ecs` issue #169 (the `track_latest`-adoption issue) does not mention `CODE_DEPLOY`

**Command:** `gh api repos/terraform-aws-modules/terraform-aws-ecs/issues/169`
**Fetched:** 2026-07-15, directly via `gh api`
**Relevant to:** Uncertainty 7 (search-completeness)

Full body, verbatim:

> "The `track_latest` attribute for the `aws_ecs_task_definition` resource released in in v5.37.0 of the Terraform AWS Provider... Simplify the `service` module source code and pass sorting of ECS Taks Definition revisions to the Terraform provider. Use the `track_latest = true` argument at the `aws_ecs_task_definition` instead of a custom implementation."

**What this shows:** no mention of `CODE_DEPLOY`, `deployment_controller`, or any interaction with a CodeDeploy-managed service anywhere in the issue that proposed adopting `track_latest` in the first place. Combined with the fully-read #12703 thread (E6, 9 comments) and the fully-read v6.0.0 module source (auxiliary `taskdef-drift_v6release_1.md`), no source fetched across either investigation pass discusses `track_latest` and `CODE_DEPLOY` jointly.

---

## E10 — AWS's own blue/green tutorial: CodeDeploy tracks revisions through its own AppSpec + task sets, not through the service's `deployments[]`

**URL:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/create-blue-green.html
**Fetched:** 2026-07-15 (WebFetch)
**Relevant to:** Uncertainty 7 (the "continuously vs. only at deploy time" sub-question — genuinely unresolved, recorded honestly below)

The tutorial's AppSpec file specifies the task definition ARN directly, verbatim:

> "TaskDefinition: \"arn:aws:ecs:{{region}}:{{aws_account_id}}:task-definition/{{first-run-task-definition:7}}\""

and the deployment's target status is tracked via CodeDeploy's own `taskSetsInfo` (not the ECS service's `deployments[]`), verbatim from the tutorial's own `get-deployment-target` example output:

> `"taskSetsInfo": [{"status": "ACTIVE", "trafficWeight": 0.0, ...}, {"status": "PRIMARY", "trafficWeight": 100.0, ...}]`

**What this shows, and what it does NOT show:** the tutorial confirms CodeDeploy drives the blue/green transition through its own `taskSetsInfo` (PRIMARY/ACTIVE at the CodeDeploy-target level), corroborating that `CODE_DEPLOY`-controller services are tracked through task sets, distinct from the plain-`ECS` `deployments[]` model (E5). **It does NOT state, anywhere fetched, whether the ECS `Service.taskDefinition` top-level field itself gets rewritten by CodeDeploy during or after a blue/green swap.** This specific sub-question — "does an un-ignored pointer fight CodeDeploy continuously, or only at the moment of a Terraform apply?" — is **not found addressed** in any AWS doc fetched in this investigation and is recorded here as genuinely unresolved. It does not change the answer to Uncertainty 7: regardless of what CodeDeploy itself does to that field, E6/E7/E8 establish that a Terraform-initiated `UpdateService` call carrying a different `task_definition` value is rejected by the AWS API unconditionally, so the "continuously vs. once" distinction does not change the outcome — only how often the failure would be provoked.
