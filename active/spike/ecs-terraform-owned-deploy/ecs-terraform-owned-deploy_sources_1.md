# Sources — ECS deploy where Terraform owns everything, no external deployer in the critical path

Raw source material for `SPIKE.md`. Each entry: URL/reference, exact prompt used, verbatim quote(s) returned, and verification status.

---

## S1 — Cloud Posse `atmos-native-ci` — CI workflow file (feature-branch.yml)

**Source:** `gh api repos/cloudposse-examples/atmos-native-ci/contents/.github/workflows/feature-branch.yml` (fetched via `gh api`, base64-decoded, read directly — not a `WebFetch` summary)

**Full content relevant to this spike** (`/tmp` copy no longer exists after session; content reproduced verbatim from the tool result):

```yaml
permissions:
  id-token: write
  contents: read
  statuses: write

env:
  ATMOS_PROFILE: github

jobs:
  build:
    runs-on: ["ubuntu-latest"]
    container:
      image: ghcr.io/cloudposse/atmos:${{ vars.ATMOS_VERSION }}
    steps:
      - name: AWS Auth
        run: |
          atmos auth env --identity plat-dev/terraform --format=github
          atmos auth login --identity plat-dev/terraform
      - name: Build
        id: build
        uses: cloudposse/github-action-docker-build-push@v3
        with:
          organization: cloudposse-examples
          repository: atmos-native-ci
          registry: ${{ vars.ECR_REGISTRY }}
          workdir: app
    outputs:
      image: ${{ steps.build.outputs.image }}
      tag: ${{ steps.build.outputs.tag }}

  deploy-preview:
    needs: [ test, build ]
    steps:
      - name: Deploy ECS Service
        id: deploy
        env:
          ATMOS_PROFILE: github
          APP_IMAGE: "${{ needs.build.outputs.image }}:${{ needs.build.outputs.tag }}"
          PR_NUMBER: ${{ github.event.pull_request.number }}
        run: |
          atmos terraform deploy app -s preview

  deploy-dev:
    needs: [ test, build ]
    if: github.event_name == 'merge_group'
    steps:
      - name: Deploy ECS Service
        id: deploy
        env:
          ATMOS_PROFILE: github
          APP_IMAGE: "${{ needs.build.outputs.image }}:${{ needs.build.outputs.tag }}"
        run: |
          atmos terraform deploy app -s dev
```

**Significance:** This is the whole pipeline, unedited. Three facts, directly readable from the file:

1. **The CI service IS GitHub Actions** — a third-party service, running on `ubuntu-latest` runners GitHub operates. There is no CI-less path in this reference implementation.
2. **Authentication is `atmos auth login --identity plat-dev/terraform`** via `id-token: write` (OIDC) — the CI job assumes an identity literally named `terraform`, which by naming convention is apply-level, not a narrow `ecs:UpdateService`-only role.
3. **The deploy step is `atmos terraform deploy app -s <stage>`** — a single command, not "call the AWS API directly." `APP_IMAGE` is passed as a plain environment variable into that command.

**Verification:** Fetched via `gh api repos/cloudposse-examples/atmos-native-ci/contents/.github/workflows/feature-branch.yml --jq '.content'`, base64-decoded locally, read via the `Read` tool. Re-confirmed present in the decoded file at the time of writing. [VERIFIED-HERE]

---

## S2 — Cloud Posse `atmos-native-ci` — stack config (`terraform/stacks/defaults/app.yaml`)

**Source:** `gh api repos/cloudposse-examples/atmos-native-ci/contents/terraform/stacks/defaults/app.yaml`

**Verbatim (relevant excerpt):**

```yaml
components:
  terraform:
    app:
      metadata:
        component: ecs-task
      vars:
        containers:
          app:
            image: !env APP_IMAGE 068007702576.dkr.ecr.us-east-2.amazonaws.com/cloudposse-examples/atmos-native-ci:sha-2ee4206
```

**Significance:** `!env APP_IMAGE <default>` is a custom Atmos YAML tag that resolves to the value of the `APP_IMAGE` environment variable at stack-config-render time (falling back to the literal default shown if unset), and that resolved value becomes the `image` argument fed into the `ecs-task` Terraform component. This is the exact mechanism answering brief question (b): the image tag flows in through the CI environment variable → Atmos template resolution → Terraform variable — not through a Terraform data source resolving a registry tag, and not through a separate `update-service` call.

**Verification:** Fetched via `gh api`, base64-decoded, read directly. [VERIFIED-HERE]

---

## S3 — Cloud Posse `atmos-native-ci` — `atmos.yaml` root config

**Source:** `gh api repos/cloudposse-examples/atmos-native-ci/contents/atmos.yaml`

**Verbatim (relevant excerpt):**

```yaml
components:
  terraform:
    command: "tofu"
    apply_auto_approve: false
    deploy_run_init: true
```

**Significance:** `apply_auto_approve: false` is the tool's *global default*; the CI workflow (S1) invokes `atmos terraform deploy`, which per Atmos's own docs (S4) hard-codes `-auto-approve` regardless of this setting for that specific subcommand. So the config-level default is not what governs the CI path — the `deploy` subcommand's own behavior is.

**Verification:** Fetched via `gh api`, base64-decoded, read directly. [VERIFIED-HERE]

---

## S4 — Atmos official docs — `atmos terraform deploy` command reference

**URL:** https://atmos.tools/cli/commands/terraform/deploy

**Quote:** *"Use this command to deploy Terraform changes for an Atmos component in a stack with auto-approval. This combines plan and apply operations in a single command."* Also: *"atmos terraform deploy command automatically sets `-auto-approve` flag when running `terraform apply`."* And the caution: *"Multi-component deploy operations will auto-approve all changes. Use `--dry-run` first to verify which components will be affected."*

**Significance:** Confirms `atmos terraform deploy` = plan + apply in one auto-approved step. Planfile support exists (`--from-plan`/`--planfile`) but is optional, not the default shown in S1's workflow. This directly bears on brief question (b) — 4Shark's `TERRAFORM-POLICY.md` requires apply from a saved, reviewed plan; the reference implementation's CI path does not use that shape by default.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S5 — Atmos official docs — CI integration guide

**URL:** https://atmos.tools/ci

**Quote:** *"Plan on Pull Request"* shows `atmos terraform plan vpc -s prod` running on pull request events; *"Apply on Merge"* shows `atmos terraform deploy vpc -s prod` on push to main. And: *"atmos terraform deploy runs a fresh plan and applies it with `-auto-approve`."*

**Significance:** Confirms the recommended two-stage flow (plan on PR, apply on merge) — but the "apply on merge" stage **re-plans fresh and applies immediately**, rather than applying a previously-reviewed, saved plan artifact from the PR stage. This is a materially different shape from 4Shark's `terraform.sh` wrapper convention (saved plan reviewed, then applied from that exact plan file).

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S6 — AWS official announcement — ECS built-in blue/green deployments

**URL:** https://aws.amazon.com/about-aws/whats-new/2025/07/amazon-ecs-built-in-blue-green-deployments/

**Quote:** *"using the AWS Management Console, SDK, CLI, CloudFormation, CDK, and Terraform"* — listing Terraform explicitly among the supported ways to use the new native blue/green capability.

**Significance:** This is AWS's own July 2025 announcement of ECS-native blue/green deployments (a feature that post-dates the "established facts" in this spike's brief, which cited the CODE_DEPLOY-only constraint as apparently permanent). Its existence is the first-order answer to brief question (c): a newer AWS mechanism exists that is not the CODE_DEPLOY controller, and Terraform is explicitly named as a supported control plane.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S7 — AWS DevOps Blog — "Choosing between Amazon ECS Blue/Green Native or AWS CodeDeploy"

**URL:** https://aws.amazon.com/blogs/devops/choosing-between-amazon-ecs-blue-green-native-or-aws-codedeploy-in-aws-cdk/

**Quote:** *"ECS-native blue/green deployments is now the recommended option for most teams and new projects."* Also: *"If your stack already uses the Deployment Controller Type. CODE_DEPLOY path, you can continue to do so; migration options exist."*

**Significance:** This is AWS's own first-party guidance recommending the native path over CodeDeploy going forward, and it explicitly frames CODE_DEPLOY → ECS-native as a *migration*, meaning the two are different `deployment_controller` configurations, not a flag on the same one. The article's discussion is CDK-centric (it doesn't detail the IaC-direct-update mechanics for Terraform specifically); that gap is closed by S8/S9 below.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S8 — note.com (しょうご/shogo452) — "Setting up and verifying Amazon ECS built-in Blue/Green deployments with Terraform"

**URL:** https://note.com/shogo452/n/n8f7ae3dc5b22?hl=en-US

**Quote:** *"Deployment controller: `deployment_controller { type = "ECS" }`"*; *"Deployment strategy: `strategy = "BLUE_GREEN"` with `bake_time_in_minutes = "1"`"*; the author performed an actual deployment and states *"Deployment worked successfully"*; and names the provider version: *"it has already been included in v6.4.0, which was released on July 18th"* (of `terraform-provider-aws`).

**Significance:** This is a single, first-hand, named-author account of running an actual `terraform apply` against a service configured with `deployment_controller = "ECS"` + `deployment_configuration.strategy = "BLUE_GREEN"`, and having it trigger a working native blue/green rollout — i.e., **not** the CODE_DEPLOY-controller path that rejects Terraform-driven `task_definition` updates. This is the closest direct evidence found in this spike that Terraform CAN drive the blue/green rollout itself, for a service reconfigured onto the new controller type. **Caveat, stated plainly**: this is one individual's blog post, not a named organization's production account, and the fetch could not confirm the exact terraform diff that changed the task definition (a follow-up fetch on the same URL, asked specifically about the terraform code triggering the change, returned that the article does not show it explicitly — see below).

**Verification:** URL fetched via `WebFetch`, twice (once for the general summary, once re-probing for the exact triggering diff) / Verbatim quote checked: yes, both times / Quote substring confirmed at: this entry. Second fetch's negative result (article does not show the literal triggering terraform diff) is recorded honestly rather than papered over.

---

## S9 — terraform-provider-aws source docs — `aws_ecs_service` resource reference (raw GitHub)

**URL:** https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/ecs_service.html.markdown

**Quote:** *"`strategy` - (Optional) Type of deployment strategy. Valid values: `ROLLING`, `BLUE_GREEN`, `LINEAR`, `CANARY`. Default: `ROLLING`."* And: *"`task_definition` - (Optional) Family and revision (`family:revision`) or full ARN of the task definition that you want to run in your service. Required unless using the `EXTERNAL` deployment controller."*

**Significance:** Confirms the `strategy` argument exists as documented provider surface (not just a blog claim) and that `task_definition` remains a normal, settable Terraform argument for this configuration — it is not carved out the way it is for `CODE_DEPLOY` (which the prior spike established rejects direct API updates). The doc text fetched does **not** contain an explicit sentence stating "unlike CODE_DEPLOY, BLUE_GREEN accepts direct task_definition updates" — that specific comparison was not found verbatim anywhere in this spike's fetches. The inference is drawn from the resource schema (no controller-specific carve-out documented for `BLUE_GREEN`) plus S8's practical account, not from an explicit stated comparison.

**Verification:** URL fetched via `WebFetch` (raw GitHub) / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S10 — GitHub search summary — terraform-aws-modules/terraform-aws-ecs & related ignore_changes discussion

**URLs referenced in search result summaries (not independently fetched beyond the summary):** `github.com/terraform-aws-modules/terraform-aws-ecs/issues/154`, `github.com/terraform-aws-modules/terraform-aws-ecs/issues/165`

**Quote (from a direct fetch of issue #154):** the fetch of issue #154 returned no comment text discussing the BLUE_GREEN-vs-ignore_changes distinction — the issue is a documentation-expansion *request*, and its content did not carry the technical answer sought.

**Significance:** Recorded as a genuine gap, not papered over: **whether the community's own flagship module (`terraform-aws-modules/terraform-aws-ecs`) has updated its documentation to describe `ignore_changes` as UNNECESSARY under the new `BLUE_GREEN` strategy is NOT confirmed by this spike.** This is a "what remains uncertain" item, not a Finding.

**Verification:** URL fetched via `WebFetch` / Result: no usable quote found / marked as a gap, not used to sustain any claim.

---

## S11 — GitHub issue — terraform-provider-aws #19519 (ECS circuit breaker rollback false-positive success)

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/19519

**Quote:** *"The terraform apply command does not appropriately wait for the state to be steady. It seems to exit after about 6 minutes, when the ECS service attempts to deploy the second time after failing the first time."*

**Significance:** Direct evidence for brief question (d) — "what breaks." When Terraform itself drives an ECS deployment with the deployment circuit breaker + `wait_for_steady_state` enabled, and the deployment fails and the circuit breaker auto-rolls-back, Terraform can report `apply` as **successful** while the service actually failed its first rollout attempt and is on its second (rolled-back) one. A team relying on `terraform apply`'s own exit code as the deploy-succeeded signal — which is exactly what "Terraform owns the whole deploy" implies — inherits this false-positive risk.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S12 — GitHub issue — terraform-provider-aws #16012 (inconsistent ECS deployment outcomes)

**URL:** https://github.com/hashicorp/terraform-provider-aws/issues/16012

**Quote:** *"For case 3., the actual behavior is inconsistent given the same Terraform configuration"* — the reporter's testing showed the same configuration produced timing outcomes ranging from 1–7 minutes to a 10-minute timeout, with no configuration change between runs.

**Significance:** Second, independent piece of evidence for brief question (d): Terraform's `wait_for_steady_state` behavior against an ECS service is reported as non-deterministic under at least one failure condition (a task that persistently fails health checks). For a topology where Terraform's own apply IS the deploy, this directly threatens the "did the deploy actually succeed" signal the whole topology depends on.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S13 — quickinfracloud.com / oneuptime.com — Terraform state lock contention under frequent applies (general, not ECS-specific)

**URLs:** search-summary only for `quickinfracloud.com/bottleneck-with-terraform-lock/` (direct fetch returned HTTP 404 — marked UNVERIFIED, not used to sustain any claim on its own)

**What is actually usable:** the search-result summary (not a fetched, quotable page) describes the generic mechanism: *"Terraform's lock mechanism is necessary to ensure consistency of state ... only one deployment can happen concurrently for a given state file"* and *"Long-running Terraform operations ... can block all other deployments during this time."* This is NOT a verbatim fetched quote — it is a search-engine-generated summary, and per citation discipline it is NOT used to sustain a Finding on its own. It is corroborated independently by S14 below, which WAS fetched directly.

**Verification:** `quickinfracloud.com` URL returned HTTP 404 on direct fetch — **UNVERIFIED, excluded from sustaining any claim**.

---

## S14 — Simply Business tech blog — state-lock contention during CI/CD Terraform runs (independently fetched, named organization)

**URL:** https://www.simplybusiness.co.uk/about-us/tech/2020/08/terraform-state-file-locking/

**Quote:** *"If one Terraform binary attempts to acquire a lock on a state file that is already locked, an exception is raised and the Terraform run exits."* The cause: *"Terraform `plan` and `apply` operations run in separate Jenkins stages—deliberately, to allow code review between stages—making traditional stage-level locking ineffective,"* leading to two concurrent branch builds colliding on the same state file's lock.

**Significance:** A named-organization (Simply Business), first-hand account of state-lock contention breaking a CI/CD Terraform pipeline in practice — corroborating S13's generic claim with an actual fetched, quotable source. Important caveat, stated plainly: **this is about Terraform *provisioning infrastructure* colliding with itself across concurrent builds, not specifically about "every application deploy is a terraform apply."** It generalizes only partially to this spike's question — it shows the state-lock failure mode is real and documented, not that it has been specifically reported against a "Terraform owns every ECS deploy" topology. The workaround the author built (checking live ECS task status before acquiring the Terraform action) is itself evidence that the tooling's native lock semantics were judged insufficient for their case.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S15 — Medium (Jack Mahoney) — "Continuous deployments with AWS ECS, Terraform and Jenkins (task definition revisions)"

**URL:** https://medium.com/@jackmahoneynz/continuous-deployments-with-aws-ecs-terraform-and-jenkins-task-definition-revisions-143d2aa4208e

**Quote:** *"we need to create a new task revision for the ECS service and tell it to run. You could simply use `latest` as the image tag in your ECS task definition but I prefer explicit versioning. To do so we first use the `register-task-definition` command and then `update-service`"*

**Significance:** This is topology 1 from the prior spike (`ecs-taskdef-ownership-boundary/SPIKE.md`) — Jenkins (the deployer) registers its own task-definition revision and calls `update-service` directly; Terraform is used only to read outputs (repo URL, etc.), not to author the task definition content that Jenkins deploys. This is **not** brief topology (e) ("Terraform owns everything; deployer only calls `update-service` against a Terraform-rendered revision") — it is closer to 4Shark's current shape. Recorded here because the search that was meant to find topology (e) surfaced this instead, and the negative result matters: **no source found in this spike describes a deployer that registers NOTHING and calls `update-service` purely against an ARN Terraform itself produced.** This gap is carried into "What remains uncertain."

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S16 — HashiCorp Well-Architected Framework — GitOps workflow doc

**URL:** https://developer.hashicorp.com/well-architected-framework/define-and-automate-processes/process-automation/gitops

**Quote:** *"GitOps tools continuously monitor Git repositories and automatically apply changes when new commits are merged."* And, describing the HCP Terraform-specific flow: *"HCP Terraform detects the merge to the main branch and automatically runs a new plan followed by an apply operation."*

**Significance:** This is HashiCorp's own first-party guidance, and it is directly relevant to brief question (f). Even in HashiCorp's own recommended pattern, **something** — HCP Terraform itself, in this description — is the automation surface that watches the repository and triggers the apply. HCP Terraform is a HashiCorp-run SaaS: a "third-party service in the critical path" by the engineer's own framing, just a different one than GitHub Actions. No workflow is described in this document where a human runs `terraform apply` by hand as the sanctioned production path, and no CI-less / service-less path is described at all.

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## S17 — Spacelift blog — "How to Deploy your Infrastructure in CI/CD using Terraform"

**URL:** https://spacelift.io/blog/terraform-in-ci-cd

**Quote:** *"Use local runs for quick iteration, but run authoritative plans and all applies in CI/CD (or a dedicated infrastructure orchestration layer) for consistent execution, access control, and auditability."*

**Significance:** A second, independent industry source converging on the same shape as S16: some automation surface — "CI/CD (or a dedicated infrastructure orchestration layer)" — is the recommended location for the authoritative apply, explicitly as an alternative framing to "just run it locally." The phrase "or a dedicated infrastructure orchestration layer" is itself an acknowledgment that the *specific* service can vary (GitHub Actions, Atlantis, Spacelift, HCP Terraform), but some automation layer is the consistent recommendation — never "no service at all, an engineer's own machine, as the standing production process."

**Verification:** URL fetched via `WebFetch` / Verbatim quote checked: yes / Quote substring confirmed at: this entry.

---

## Search-only leads that did not produce a fetchable, citable primary source (recorded, not used to sustain claims)

- `quickinfracloud.com/bottleneck-with-terraform-lock/` — HTTP 404 on direct fetch. UNVERIFIED.
- A targeted search for a second, independent, named-organization account (beyond S8) of running `terraform apply` against the new `BLUE_GREEN` ECS strategy did not surface one within this spike's time-box. This is recorded under "What remains uncertain" in `SPIKE.md`, not treated as settled.
- A targeted search for "Terraform declares the task definition fully; CI's only job is `update-service` against a Terraform-output ARN" (brief topology e) did not surface a named account matching that exact shape. S15 was the closest hit and does not match it (Jenkins registers its own revision).
