# Raw sources — ECS task definition ownership boundary

Every source below was fetched once via the `WebFetch` tool during this spike (2026-07-16). Each entry: URL, the prompt used to extract it, the returned quote(s), and a verification note. Where a fetch returned no usable quote for the question asked, it is recorded as **NOT FOUND** — that is itself evidence (an absence), not a gap to paper over.

**Verification method note (honesty about what "verified" means here):** each quote below was extracted by a single `WebFetch` call against the live URL — the tool fetches the page and an extraction pass pulls the literal substring. This spike did NOT perform a second, independent re-fetch pass for every source (time-boxed research); the one exception is S5 (Cloud Posse deprecation notice), which was fetched twice with different prompts and returned the identical sentence both times — that one carries a true self-check. All others carry single-fetch confidence. This distinction is preserved so the engineer can weight accordingly.

---

## S1 — kayac/ecspresso README

**URL:** https://github.com/kayac/ecspresso

**Asked for:** why ecspresso exists relative to Terraform, ownership split, "Partial Task Definition" language.

**Result: NOT FOUND.** The fetch returned: *"I cannot find any text that explicitly addresses ... Why ecspresso exists relative to Terraform ... Problem it solves vs. Terraform ... Ownership splitting between Terraform and ecspresso ... 'Partial Task Definition' — This phrase does not appear anywhere in the content."* The tool's own summary: *"allows you to manage ECS services and task definitions as code in JSON, YAML, or Jsonnet files, enabling version control and infrastructure as code practices"* is the only description found, and it does not compare to Terraform.

**Significance:** ecspresso's own documentation does not position itself against Terraform or state an ownership philosophy. Any positioning comes from third-party users (see S6, S12, S17), not the tool's own voice.

---

## S2 — hashicorp/terraform-provider-aws#632

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/632

**Title:** "aws_ecs_task_definition and continuous delivery to ecs"

**Quote (original post):** *"We rebuild the docker image with a unique tag at every deployment. This means that after the CI service redeploys a service, the corresponding task definition's revision is incremented and the image field in a container definition changes."*

**Status:** Closed. No maintainer response text was returned by the fetch; the specific resolution mechanism is not recoverable from this single fetch.

---

## S3 — hashicorp/terraform-provider-aws#20121

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/20121

**Title:** "Keep LATEST aws_ecs_task_definition container_definition image revision"

**Quote (original post):** *"I did not find any ways to get the current image revision and keep it on 'container_definitions -> image' field, and just apply the change on other fields."*

**Status at fetch time:** Open. Labels: `enhancement`, `service/ecs`. No maintainer response found in the fetch.

**Significance:** independent confirmation that the "Terraform changes one field, an external process changes another" tension has been an open, unaddressed enhancement request on the provider itself.

---

## S4 — Scale Factory blog, CodeDeploy + Terraform + GitHub Actions

**URL:** https://scalefactory.com/blog/2023/03/07/using-codedeploy-with-terraform-and-github-actions/

**Quote (paraphrase flagged by the fetch tool, not a verbatim page quote — treat as UNVERIFIED for the exact wording):** the tool reported the article specifies *"ignore changes in image ID outside Terraform, i.e. in GitHub actions"* and shows:
```
lifecycle {
  ignore_changes = [task_definition]
}
deployment_controller {
  type = "CODE_DEPLOY"
}
```

**Verification note:** the fetch tool paraphrased rather than quoting the exact prose sentence, so the English wording above is UNVERIFIED as a literal substring; the code block shape (`ignore_changes = [task_definition]` paired with `deployment_controller { type = "CODE_DEPLOY" }`) is corroborated independently and more strongly by S9 below, which returned an exact literal code block plus inline comment.

**Significance (only the corroborated part):** this is a second, independent source describing the same `ignore_changes` + `CODE_DEPLOY` pairing 4Shark already runs (prior spike F1, F4).

---

## S5 — Cloud Posse: "ECS Partial Task Definitions" (deprecation notice)

**URL:** https://docs.cloudposse.com/layers/software-delivery/ecs-ecspresso/ecs-partial-task-definitions/

**Fetched twice**, with two different prompts; both returns included the identical sentence — this is the one source in this spike with a genuine two-fetch self-check.

**Quote (definition):** *"ECS Partial task definitions is the idea of breaking the task definition into smaller parts. This allows for easier management of the task definition and makes it easier to update the task definition."*

**Quote (deprecation — confirmed twice, identical both times):** *"This approach is deprecated. For new ECS deployments, we recommend using ECS with Atmos which provides a simpler, more integrated deployment workflow."*

**Ownership split described:** Terraform owns "secrets, volumes, ARNs, filesystem IDs"; the application repository's CI/CD (ecspresso) owns "container definitions and environment variables during the deployment lifecycle" (per the fetch tool's paraphrase of the split — the ownership-split sentence itself was not returned as an exact quote, only the deprecation sentence was confirmed as literal).

**Significance:** a named vendor (Cloud Posse, a widely-used Terraform module/reference-architecture shop) built, shipped, and then explicitly retired a split-ownership topology (Terraform + ecspresso partial task definitions) in favor of a full-IaC topology (Atmos + OpenTofu). This is direct, dated evidence of churn AWAY from a split-tool topology.

---

## S6 — Cloud Posse: "ECS with Atmos"

**URL:** https://docs.cloudposse.com/layers/software-delivery/ecs-atmos/

**Quote:** *"Atmos for configuration orchestration and OpenTofu for infrastructure-as-code."*

**Quote (image tag mechanism, per fetch tool, not a literal single sentence — paraphrase):** the CI/CD workflow sets an `APP_IMAGE` environment variable and runs `atmos terraform deploy app -s [environment]` — i.e., the image tag is passed into a Terraform/OpenTofu apply, not registered out-of-band via the AWS CLI.

**Navigation label observed:** "ECS with ecspresso (Deprecated)" alongside "ECS with Atmos" as the current path.

**Significance:** this is the topology "Terraform owns everything including the image tag, fed in as a variable — the pipeline triggers Terraform rather than the AWS CLI" (one of the topologies the brief asked to enumerate), and it is Cloud Posse's current recommended replacement for the split-tool topology in S5.

**Not found:** an explicit sentence comparing Atmos to ecspresso or stating WHY the switch happened (the fetch found no such comparison on this page) — the deprecation fact (S5) is confirmed; the stated rationale for it is NOT.

---

## S7 — dev.to, ryo_ariyama, "How We Manage ECS with Terraform and GitHub Repos"

**URL:** https://dev.to/ryo_ariyama_b521d7133c493/amazon-ecs-4j7k

**Quote:** *"Especially with the first point, changing the container image tag typically results from updates to backend source code rather than infrastructure changes."*

**Quote:** *"Doing this every time you deploy creates a lot of communication overhead. Ideally, both teams should be able to deploy independently."*

**Not found:** the fetch explicitly reported *"The article does not discuss any stability issues, problems encountered, or drawbacks with this split approach."*

**Significance:** a stated rationale (organizational — deploy independence between infra and app teams) for why the ECS task definition/service is created in the infra repo but updated from the backend repo — the same general shape as 4Shark's own split, described here as a deliberate choice rather than a defect.

---

## S8 — terraform-aws-modules/terraform-aws-ecs#169

**URL:** https://github.com/terraform-aws-modules/terraform-aws-ecs/issues/169

**Title:** "Use `track_latest` attribute for the `aws_ecs_task_definition` resource at `service` module"

**Quote (OP):** *"This allows us to query both the existing as well as Terraform's state and get the max version of either source."* (describing the old custom-logic hack the issue proposes replacing)

**Status:** the fetch found no maintainer comment or closing resolution text. Prior spike (`terraform-ignore-changes-task-definition-drift/SPIKE.md` F17-F20) already independently confirmed, via the module's `docs/UPGRADE-6.0.md` and PR #217, that `track_latest` shipped in v6.0.0 and replaced this exact hack — that finding is not re-derived here, only cross-referenced.

---

## S9 — AWS DevOps blog: Blue/Green ECS via CloudFormation + CodeDeploy

**URL:** https://aws.amazon.com/blogs/devops/blue-green-deployments-to-amazon-ecs-using-aws-cloudformation-and-aws-codedeploy/

**Quote:** *"With this configuration, any time there is an update to the task definition on the ECS service (such as when building new application image), the update results in a failure."*

**Quote:** *"To avoid this, you can implement a CloudFormation based custom resource that obtains the previous version of task definition."*

**Significance:** this is AWS's OWN official blog, independent of Terraform entirely (it is CloudFormation), documenting the identical constraint the prior spike found at the Terraform-provider level (S11 below): once CodeDeploy owns the ECS service, the IaC tool cannot register task-definition updates against that service directly — a custom side-channel (there, a CFN custom resource; in Terraform, `ignore_changes`) is required regardless of which IaC tool is in use. This generalizes the constraint beyond Terraform — it is an ECS API property, not a Terraform limitation.

---

## S10 — dev.to, aws-builders, "ECS Blue/Green deployment with CodeDeploy and Terraform"

**URL:** https://dev.to/aws-builders/ecs-bluegreen-deployment-with-codedeploy-and-terraform-3gf1

**Quote (exact code block, per fetch tool):**
```terraform
resource "aws_ecs_service" "example"{
...
 task_definition = aws_ecs_task_definition.example.arn

 load_balancer {
  container_name = "example"
  container_port = 8080
  target_group_arn = aws_lb_target_group.example.arn
 }
# because CodeDeploy will handle task definition and alb changes outside of terraform
 lifecycle {
   ignore_changes = [load_balancer, task_definition]
 }
}
```

**Significance:** independent, literal confirmation (inline code comment, not paraphrase) of the exact pattern 4Shark already runs for its web/CODE_DEPLOY service (prior spike F1): `ignore_changes = [task_definition, load_balancer]` as whole-block ignores, justified explicitly by "CodeDeploy will handle task definition and alb changes outside of terraform."

---

## S11 — hashicorp/terraform-provider-aws#12703

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/12703

**Title:** "ECS with CodeDeploy Blue/Green"

**Quote (AWS API error, as reported in the issue, per fetch):** *"Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment."*

**Status:** Closed as not planned.

**Significance:** this issue was already surfaced in the prior spike (`terraform-ignore-changes-task-definition-drift/SPIKE.md`, F22/E6) but is re-fetched here and independently corroborated by S9 (a different IaC tool, same AWS-level constraint) — the CODE_DEPLOY restriction is at the AWS ECS API layer, not specific to any one IaC tool.

---

## S12 — hashicorp/terraform-provider-aws#13192

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/13192

**Title:** "Can't ignore changes for aws_ecs_service load_balancer.0.target_group_arn (for CodeDeploy blue-green deploys)"

**Quote:** *"Block type 'load_balancer' is represented by a set of objects, and set elements do not have addressable keys."*

**Status:** Closed as not planned.

**Significance:** explains WHY the community pattern (S10, prior spike F1) ignores the entire `load_balancer` block rather than a specific attribute inside it — the schema (a `TypeSet`, not `TypeList`) makes indexed `ignore_changes` impossible, so whole-block ignore is not a stylistic choice but the only mechanically available option.

---

## S13 — HashiCorp blog: "Change Management At Scale: How Terraform Helps End Out-of-Band Anti-Patterns"

**URL:** https://www.hashicorp.com/en/blog/change-management-at-scale-how-terraform-helps-end-out-of-band-anti-patterns

**Quote:** *"Do not allow any out-of-band changes to occur. We recommend disabling any access/controls that will allow changes to an account or resources that are managed by Terraform."*

**Quote (the only carve-out found):** *"If out-of-band changes are absolutely required due to current operating practices, then we recommend establishing notification/alerting systems for drift detection so changes can be identified and remediated in Terraform code or tracked as a known out-of-band management practice."*

**Significance:** this is HashiCorp's own official ideological position, and it does NOT carve out an exception for a CI/CD pipeline updating an image tag — the only accommodation offered is detection/alerting after the fact, not a blessed pattern for the split. This creates real tension with the fact (established in the prior spike, not re-derived here) that the image field CANNOT be known by Terraform at plan time — HashiCorp's most general public guidance does not address this specific, structurally unavoidable case.

---

## S14 — javierinthecloud.com: "Solving the ECS Task Definition Update Challenge in CodePipeline Deployments"

**URL:** https://www.javierinthecloud.com/solving-the-ecs-task-definition-update-challenge-in-codepipeline-deployments/

**Quote:** *"The ECS Deploy action in CodePipeline updates the service with the Task Definition currently associated with the running service, not the latest one you've registered."*

**Quote (documented AWS behavior, per fetch, presented in the article as an AWS quote):** *"If you create new revisions for the task definition without updating the Amazon ECS service, the deployment action will ignore those revisions."*

**Quote (proposed fix):** *"a CloudFormation template that ensures the ECS service always uses the latest Task Definition. The key is to create a Lambda function that updates the ECS service with the most recent Task Definition."*

**Significance:** this is the MIRROR-IMAGE problem to 4Shark's #711 incident — here a NEWLY-registered revision is silently ignored (stuck on old), whereas 4Shark's incident was the service silently keeping the OLD revision's stale fields (also stuck on old, different mechanism). Both point to the same root cause named across sources in this spike: ECS's "current running revision" and "what Terraform/CFN thinks is current" are two different pieces of state that do not automatically reconcile, and every fix found (Lambda here, `check` block in the prior spike, `track_latest`) is a workaround bolted on top, not a native reconciliation.

---

## S15 — github.com/aws/amazon-ecs-agent#1694

**URL:** https://github.com/aws/amazon-ecs-agent/issues/1694

**Title:** "describe-task-definition call drops secrets key from containerDefinitions entries"

**Quote:** *"Calling `describe-task-definition` returns a JSON body with `taskDefinition.containerDefinitions` array objects missing their `secrets` key, if they have one."*

**Status:** Closed.

**Significance:** a DIFFERENT, historical (agent v1.22-era) AWS API defect in the same family as 4Shark's own incident mechanism — `describe-task-definition` (the exact call 4Shark's GHA deploy script uses to copy-forward, per the brief's fact 3) has a documented history of silently dropping fields from its response. This is not the same bug as 4Shark's #711 (which was about Terraform destroying a resource, not the API dropping a field), but it is evidence that `describe-task-definition`-based copy-forward has, independently and more than once, been a source of silently-lost task-definition content in the ECS ecosystem.

---

## S16 — aws-actions/amazon-ecs-render-task-definition README

**URL:** https://github.com/aws-actions/amazon-ecs-render-task-definition

**Quote:** *"If task definition file is provided that has precedence over any other option to fetch task definition."*

**Not found:** any statement prescribing where the task-definition JSON file should live (app repo vs. infra repo) or who should maintain it.

**Significance:** AWS's own official GitHub Action for this exact operation is deliberately ownership-agnostic — it accepts a file, an ARN, or a family name with no stated preference, and does not take a position on the Terraform-vs-app-repo question at all.

---

## S17 — AWS Containers blog: "Create a CI/CD pipeline for Amazon ECS with GitHub Actions and AWS CodeBuild Tests"

**URL:** https://aws.amazon.com/blogs/containers/create-a-ci-cd-pipeline-for-amazon-ecs-with-github-actions-and-aws-codebuild-tests/

**Quote:** *"Insert a container image URI into an Amazon ECS task definition JSON file"* (describing `aws-actions/amazon-ecs-render-task-definition@v1`)

**Quote:** *"Registers an Amazon ECS task definition and deploys it to an Amazon ECS service"* (describing `aws-actions/amazon-ecs-deploy-task-definition@v1`)

**Described mechanism (per fetch, paraphrased, not a single verbatim sentence):** the CDK-provisioned infrastructure creates the ECS service with a placeholder image; ongoing deploys register new task-definition revisions directly via the two GitHub Actions above, not through a CDK/CloudFormation re-deploy.

**Significance:** this is AWS's own official reference architecture for "IaC + GitHub Actions CI/CD on ECS", and its shape (IaC creates the skeleton once; CI/CD registers revisions directly thereafter, bypassing the IaC tool for ongoing updates) is structurally the same shape as 4Shark's current topology (prior spike facts 2-3), even though the IaC tool in the AWS example is CDK/CloudFormation, not Terraform.

---

## S18 — AWS Containers blog: "Scaling IaC and CI/CD pipelines with Terraform, GitHub Actions, and AWS Proton"

**URL:** https://aws.amazon.com/blogs/containers/scaling-iac-and-ci-cd-pipelines-with-terraform-github-actions-and-aws-proton/

**Result: NOT FOUND.** The fetch reported: *"This architectural detail regarding task definition lifecycle management is not addressed in the content provided."* Only a general statement that the pipeline "updates the AWS Proton service to deploy the newly built image" was returned, with no mechanism detail.

---

## S19 — Terraform Registry: `aws_ecs_service` resource docs

**URL:** https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecs_service

**Result: FETCH FAILED.** The tool returned no page content (*"I don't have access to the actual web page content ... The content section in your message only shows '---Terraform Registry---' without the substantive documentation"*). UNVERIFIED — sustains nothing. (The prior spike already fetched and quoted this exact resource's raw markdown source successfully via a different URL form — `raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown` — see its S2; this spike did not repeat that successful path.)

---

## S20 — Spacelift self-hosted docs: "Deploying to ECS"

**URL:** https://docs.spacelift.io/self-hosted/latest/installing-spacelift/reference-architecture/guides/deploying-to-ecs

**Result: NOT FOUND.** The fetch reported the guide references a Terraform module for the initial deploy but *"does not detail whether Terraform manages ongoing task definition revisions [or] a separate deployment tool ... registers new revisions outside Terraform."*

---

## S21 — kayac/ecspresso#871

**URL:** https://github.com/kayac/ecspresso/issues/871

**Title:** "Feature request: task definition only deployment for ECS service"

**Quote:** *"When managing service definitions with Terraform (or similar tools) and wanting to update only the task definition, `ecspresso deploy --no-update-service` can be used, but even in this case, ecs-service-def.json is required."*

**Significance:** direct, first-party confirmation that ecspresso is commonly run ALONGSIDE Terraform in a hybrid split — Terraform owns the `aws_ecs_service` resource, ecspresso owns only the task-definition registration — rather than ecspresso fully replacing Terraform for ECS. This is a distinct topology from both S5 (deprecated partial-task-def) and S6 (full Atmos/Terraform) — a live, still-open feature request as of this fetch, meaning the hybrid pattern is still actively used and still evolving, not settled.

---

## S22 — CyberAgent SRE blog: ECS management migrated Terraform → ecspresso

**URL:** https://sre.cyberagent.ai/blog/transfer-ecspresso/index.html

**Quote (Japanese, verbatim as returned by the fetch):** *"VPCやELB等のインフラレイヤーのリソースは1度デプロイすると頻繁に構成変更を行わないのが一般的です。ただしECSはアプリケーションレイヤーのリソースのため頻繁に構成変更する必要があります。そのためTerraformでECSを管理し頻繁に構成変更すると、意図しないECS関連リソースの変更が発生してしまう恐れがあります。"*

**English paraphrase (mine, not a translation attributed to the source as a literal quote):** infrastructure-layer resources (VPC, ELB) rarely change after initial deploy; ECS is an application-layer resource that changes frequently; managing ECS via Terraform alongside stable infrastructure risked unintended changes to ECS-related resources during frequent updates.

**Quote (post-migration, Japanese, verbatim):** *"比較的スムーズに移行ができたと実感しております"*

**English paraphrase (mine):** the author reports the migration went "relatively smoothly."

**Caveat noted in the source (per fetch):** ECS definition files still directly reference AWS resource IDs/ARNs from Terraform state, which the team planned to address in a follow-up article — i.e., the migration is not described as fully decoupled from Terraform even after the switch.

**Significance:** a named, dated (this is a corporate engineering blog, not an anonymous forum post) account of migrating ECS resource management FROM Terraform TO ecspresso — the OPPOSITE direction from S5/S6 (Cloud Posse moving toward full-Terraform/Atmos). Both directions of migration are attested by named organizations.

---

## S23 — hrfmmr blog: "TerraformのECS定義をecspressoに移行する" (Migrating ECS definitions from Terraform to ecspresso)

**URL:** https://blog.hrfmmr.com/2023/01/16/terraform_with_ecs/

**Quote (Japanese, verbatim):** *"タスク定義の登録や実行が個別で行える"*

**English paraphrase (mine):** ecspresso allows task-definition registration and execution to be handled separately (from the service).

**Quote (Japanese, verbatim, on the specific Terraform problem cited):** *"Auto Scaling によってdesired_count の変更が起き得る"* and *"Terraform 定義と稼働しているECS サービスとの間に差分が生まれる"*

**English paraphrase (mine):** Auto Scaling can change `desired_count` outside Terraform, producing drift between the Terraform definition and the running ECS service — risking that a plain `terraform apply` unintentionally cancels an in-progress scaling action.

**Significance:** a second, independent account (different author, different year) of migrating ECS away from Terraform, citing TWO distinct problems: (1) `aws_ecs_task_definition` updates create replacements rather than preserving revision history, complicating rollback; (2) `desired_count` drift from Auto Scaling risking an unintended override on `terraform apply`. Note: (2) is the same general class of problem 4Shark's own module already addresses via `ignore_changes = [desired_count, ...]` (prior spike F1) — this source is evidence the underlying tension is common across organizations, not evidence that 4Shark's specific mitigation is insufficient.

---

## Search-only leads that did not produce a fetchable, citable primary source

These are recorded so the engineer knows what was tried and came up empty, per the "quality over quantity" / "no manufactured consensus" instruction — none of the following sustains any Finding in SPIKE.md beyond the explicit "absence is the evidence" framing each one carries:

- A specific named term (e.g. a coined phrase) for "copy-forward makes a removed field immortal on the next external registration" — searched directly (`ECS task definition "stale" copy-forward named anti-pattern "configuration drift" secret removed still referenced`) and via HashiCorp's own out-of-band-changes terminology search. No named term found beyond the generic "configuration drift" / "out-of-band changes" (S13), which describes the general class, not this specific mechanism. Sustains Finding 5 (a "not found" conclusion).
- Post-release problem reports for `track_latest` — searched directly (`"track_latest" ecs terraform provider issue problems 2025 2026 regression bug report after release`). Returned no bug reports, no regressions, and no post-2024 complaints beyond the same adoption material the prior spike already covered (provider v5.37.0, `terraform-aws-modules/terraform-aws-ecs` v6.0.0). Sustains Finding 4, explicitly as weak/negative evidence (absence of a hit is not confirmation of stability).
- A quantitative industry survey of which topology is most common — not attempted beyond the search engine's own result ranking, which is not evidence of prevalence.
- `terraform-aws-modules/terraform-aws-ecs` main README's own current stated position on `CODE_DEPLOY` support — fetched, returned no relevant passage (the fetch could only surface the `ignore_task_definition_changes` variable name, not surrounding prose); the prior spike's F18 already established via direct source-file reads that this module's `main.tf` and `docs/UPGRADE-6.0.md` never mention `CODE_DEPLOY`/`CodeDeploy` anywhere — that finding is not re-derived here, only not contradicted.
