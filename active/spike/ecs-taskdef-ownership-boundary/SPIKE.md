# SPIKE — ECS task definition ownership boundary: Terraform, the CI/CD deployer, or a split

> **This spike brings options with evidence. It does not rank them and makes no recommendation.** That is a standing, explicit instruction from the engineer, repeated here because the engineer's own framing (below) is a request for a stable answer — the temptation to manufacture one is exactly what this document must resist where the evidence does not support it.
>
> **Scope note on rigor.** Per the citation discipline this spike operates under, every source below was fetched via `WebFetch` exactly once (with one deliberate exception, S5, fetched twice as a self-check) — this is time-boxed research, not an exhaustive literature review. Where a fetch came back empty, it is recorded as NOT FOUND in the auxiliary file and is not used to manufacture a claim. Read `ecs-boundary_sources_1.md` alongside this document — it carries every quote in full, including the negative results.

## Investigation question

Where should an ECS task definition's `container_definitions` be controlled — Terraform, the CI/CD deployer, or a split — and what does the community actually recommend? Refined per the engineer's framing: not "should we use Terraform" (settled, out of scope) but "is there a stable, community-endorsed answer for THIS specific boundary, so the next migration is the last one" — with the explicit fear being paying migration cost twice and hitting a third problem.

## Established facts (from the prior spike, not re-derived here)

This spike builds on `~/Projects/4Shark/dot-claude-plans/active/spike/terraform-ignore-changes-task-definition-drift/SPIKE.md` (F1-F25). The nine facts given in the brief are treated as ground truth and are cited by fact number below (e.g. "fact 3") rather than re-verified. In particular: 4Shark's web service (CODE_DEPLOY controller) and its 8 worker services (plain ECS controller) are governed by the SAME module today with the SAME unconditional `ignore_changes`, and the GHA deploy script copy-forwards every field except `image`/`command` from the live revision, forever (fact 3).

**Two distinct citation schemes are in play below, deliberately kept separate rather than collapsed into one:** `fact N` (no bold prefix) cites one of the nine established facts enumerated in the brief itself. `prior spike F-N` (always with the explicit "prior spike" prefix) cites a finding from the prior spike's own document directly, for content that informed this spike's research but was never restated as one of the brief's nine numbered facts — for example the prior spike's F17-F20 `track_latest` investigation, or its F2 git-archaeology finding. The two numbering schemes belong to two different documents and are not interchangeable; where this spike cites "prior spike F-N" rather than "fact N", that is because the cited content sits in the prior document but outside the nine facts the brief itself enumerated.

## Sources consulted

All 23 sources are indexed and quoted in full in the auxiliary file:

- [`ecs-boundary_sources_1.md`](./ecs-boundary_sources_1.md) — S1 through S23, each with URL, the exact prompt used, the verbatim quote(s) returned, and an explicit NOT FOUND marker where a fetch produced nothing usable. Read this file for the full evidentiary basis of every Finding below — this SPIKE.md excerpts only what is needed for each Finding's Significance.

## Findings

### Finding 1 — HashiCorp's own official position does not carve out an exception for the CI/CD image-tag case

**Evidence:** HashiCorp's blog states plainly: *"Do not allow any out-of-band changes to occur. We recommend disabling any access/controls that will allow changes to an account or resources that are managed by Terraform."* The only accommodation offered for a case where an out-of-band change is unavoidable is: *"establishing notification/alerting systems for drift detection so changes can be identified and remediated in Terraform code or tracked as a known out-of-band management practice."*

**Source:** S13, https://www.hashicorp.com/en/blog/change-management-at-scale-how-terraform-helps-end-out-of-band-anti-patterns

**Significance:** the engineer's fear ("Terraform was supposed to solve this") runs into a real tension here — HashiCorp's own most general public guidance treats ANY out-of-band change as an anti-pattern to be eliminated, full stop, with no blessed exception for "a CI/CD pipeline must set an image tag Terraform cannot know at plan time" (the irreducible constraint named in the brief). This is not itself a solution — it is evidence that the vendor's default ideological position does not address the specific structural case 4Shark is in. Whatever answer 4Shark adopts, it will not find top-cover from this document.

**Verification:** URL fetched: https://www.hashicorp.com/en/blog/change-management-at-scale-how-terraform-helps-end-out-of-band-anti-patterns / Verbatim quote checked: yes, via a single `WebFetch` pass (no second re-fetch performed in this spike) / Quote substring confirmed at: S13 in `ecs-boundary_sources_1.md`.

---

### Finding 2 — For the CODE_DEPLOY (blue/green) controller, the community's answer is converged, stable, and NOT Terraform-specific

**Evidence:** Three independent sources describe the identical pattern. A dev.to walkthrough shows the exact code:
```terraform
lifecycle {
  ignore_changes = [load_balancer, task_definition]
}
```
with the inline comment *"because CodeDeploy will handle task definition and alb changes outside of terraform"* (S10). AWS's OWN official DevOps blog — for CloudFormation, not Terraform — documents the underlying constraint independently: *"any time there is an update to the task definition on the ECS service (such as when building new application image), the update results in a failure"* (S9). And the AWS API itself returns a literal error confirmed via a closed provider issue: *"Unable to update task definition on services with a CODE_DEPLOY deployment controller. Use AWS CodeDeploy to trigger a new deployment."* (S11).

**Source:** S9, S10, S11 (full quotes and URLs in the auxiliary file).

**Significance:** the CODE_DEPLOY case is not "Terraform has a problem here" — it is an ECS API-level restriction that exists regardless of IaC tool. The community's answer (`ignore_changes` on the whole `task_definition` and `load_balancer` blocks) is the one 4Shark's web service already runs (prior spike F1). A companion finding, S12, explains why the ignore must cover the WHOLE `load_balancer` block rather than a specific attribute: the schema is a `TypeSet`, and *"set elements do not have addressable keys"* — so indexed `ignore_changes` is mechanically impossible, not merely a style choice. **This directly answers brief question (d): yes, blue/green forces a different — and, on the evidence gathered, more settled — answer than the plain-ECS-controller path.**

**Verification:** URL fetched: https://dev.to/aws-builders/ecs-bluegreen-deployment-with-codedeploy-and-terraform-3gf1 (S10) / https://aws.amazon.com/blogs/devops/blue-green-deployments-to-amazon-ecs-using-aws-cloudformation-and-aws-codedeploy/ (S9) / https://github.com/hashicorp/terraform-provider-aws/issues/12703 (S11) / Verbatim quote checked: yes for all three, each via a single `WebFetch` pass / Quote substring confirmed at: S9, S10, S11 in `ecs-boundary_sources_1.md`. The companion schema explanation (S12, `TypeSet`/"set elements do not have addressable keys") was fetched from https://github.com/hashicorp/terraform-provider-aws/issues/13192, quote confirmed the same way.

---

### Finding 3 — For the plain-ECS-controller path, the community has NOT converged on one topology — it has churned in both directions, and is still churning

**Evidence, direction A (away from Terraform, toward a dedicated deploy tool):** two independent, named-organization accounts describe migrating ECS management FROM Terraform TO ecspresso. CyberAgent's SRE blog: infrastructure-layer resources "rarely change after deployment... ECS is an application-layer resource [requiring] frequent configuration changes... managing ECS via Terraform alongside these stable resources created risk of unintended changes" (S22, paraphrased from the Japanese original, which is quoted verbatim in the auxiliary file). A second author (hrfmmr) cites two separate problems: `aws_ecs_task_definition` updates replace rather than preserve revisions (complicating rollback), and Auto Scaling-driven `desired_count` drift risking an unintended override on `terraform apply` (S23).

**Evidence, direction B (away from a split tool, toward full Terraform/OpenTofu):** Cloud Posse's own reference architecture explicitly deprecated its ecspresso-based "Partial Task Definition" pattern: *"This approach is deprecated. For new ECS deployments, we recommend using ECS with Atmos which provides a simpler, more integrated deployment workflow"* (S5, confirmed via two separate fetches, identical wording both times) — replacing it with a topology where "Atmos for configuration orchestration and OpenTofu for infrastructure-as-code" (S6) manages the task definition directly, with the image tag passed in as a Terraform variable rather than registered out-of-band.

**Evidence, direction C (a still-open, unsettled hybrid):** ecspresso's own still-open feature request #871 states plainly that its authors and users run it ALONGSIDE Terraform today — *"When managing service definitions with Terraform (or similar tools) and wanting to update only the task definition, `ecspresso deploy --no-update-service` can be used"* (S21) — a third topology, distinct from both A and B, that is itself still being refined (the issue remains open).

**Source:** S5, S6, S21, S22, S23.

**Significance:** this directly answers brief question (a) and (e). The honest reading of the evidence is: **the community has NOT converged on a single stable topology for the plain-ECS-controller path.** Two named organizations moved toward a dedicated tool citing organizational/lifecycle-mismatch reasons; a third named organization (Cloud Posse) moved away from that exact shape of split-tool pattern toward full-IaC ownership; a fourth pattern (Terraform + ecspresso hybrid, service in Terraform, task-def in ecspresso) is live but still evolving. No single one of these is described anywhere in the fetched material as a stable, unchallenged industry default — every account either reports a switch INTO its current state or (for the still-open feature request) shows the shape is still being worked out.

**Verification:** URL fetched: https://docs.cloudposse.com/layers/software-delivery/ecs-ecspresso/ecs-partial-task-definitions/ (S5, fetched twice, identical deprecation sentence both times — the one two-fetch self-check in this spike) / https://docs.cloudposse.com/layers/software-delivery/ecs-atmos/ (S6, single fetch) / https://github.com/kayac/ecspresso/issues/871 (S21, single fetch) / https://sre.cyberagent.ai/blog/transfer-ecspresso/index.html (S22, single fetch, Japanese-language source with my own English paraphrase clearly marked as such) / https://blog.hrfmmr.com/2023/01/16/terraform_with_ecs/ (S23, single fetch, same Japanese-source caveat) / Verbatim quote checked: yes for all five / Quote substring confirmed at: S5, S6, S21, S22, S23 in `ecs-boundary_sources_1.md`.

---

### Finding 4 — `track_latest` (the provider-native mechanism, established in the prior spike) has no reported problems in this spike's search, but is too recently adopted to call "proven stable"

**Evidence:** this spike's searches for post-release problem reports (`"track_latest" ecs terraform provider issue problems 2025 2026 regression`) returned no bug reports or regressions — only the same adoption material the prior spike already covered (`track_latest` shipped in provider v5.37.0, February 2024; adopted into `terraform-aws-modules/terraform-aws-ecs` v6.0.0). This spike did not find any NEW post-adoption complaint.

**Source:** search result summary only — no specific URL sustains a "no problems reported" claim beyond the absence of a hit, which is a weak form of evidence (absence of a report is not confirmation of absence of a problem).

**Significance:** this is explicitly NOT a finding that `track_latest` is stable — it is a statement that this spike's search did not surface a contradiction. The prior spike's own empirical test (`terraform-ignore-changes-task-definition-drift/SPIKE.md` F23-F25) applied a related mechanism (`track_latest = true`) to three productive 4Shark stacks and reverted it after it produced a permanently-dirty plan (though the specific defect uncovered was pre-existing and unrelated to `track_latest` itself, per that spike's own correction note). Combined, the honest state is: provider-native, targeted at exactly 4Shark's shape of problem, adopted by the flagship community module — but with only about two years of field time, no confirmed large-scale success story found in THIS spike's search, and 4Shark's own one experimental data point ended in a revert (for reasons distinct from the mechanism's own correctness).

**Verification:** no URL sustains this Finding — it is a negative result from a search query, not a fetched quote. Search query run: `"track_latest" ecs terraform provider issue problems 2025 2026 regression bug report after release` (logged verbatim in `ecs-boundary_sources_1.md`'s closing "Search-only leads" section). No quote to check and no substring to confirm; the absence itself is the evidence, and it is weak evidence as stated above.

---

### Finding 5 — No named term was found for the specific "copy-forward makes a removed field immortal" defect (fact 3/6 in the brief)

**Evidence:** targeted searches for a named pattern or anti-pattern covering this exact mechanism returned nothing beyond the generic vocabulary of "configuration drift" and "out-of-band changes" (S13), which describe the general class of problem, not this specific mechanism (a field is REMOVED from the desired configuration, yet SURVIVES indefinitely because a copy-forward operation re-derives the new revision from the OLD live revision rather than from the current desired configuration).

**Source:** search queries recorded in the auxiliary file's closing section ("Search-only leads that did not produce a fetchable, citable primary source").

**Significance:** this directly and plainly answers brief question (c): **the community does not appear to have a name for this specific failure mode.** What IS found, and is a genuinely related but DISTINCT defect, is a documented AWS API bug: `describe-task-definition` — the exact call 4Shark's own copy-forward mechanism uses — has a confirmed history of silently DROPPING a field (`secrets`) from its response, rather than 4Shark's incident where a field was silently PRESERVED past its intended removal (S15). Both point at the same underlying tool (`describe-task-definition` as a copy-forward primitive) as a fragile foundation, via two different, independently-documented failure directions (drop vs. preserve), but neither the drop direction nor the preserve direction has a specific name in any source this spike found.

**Verification:** the "not named" conclusion itself has no URL to check (it is an absence, sustained by the search queries logged verbatim in `ecs-boundary_sources_1.md`'s closing section). The one positive citation inside this Finding, S15, was fetched at https://github.com/aws/amazon-ecs-agent/issues/1694 / Verbatim quote checked: yes, single `WebFetch` pass / Quote substring confirmed at: S15 in `ecs-boundary_sources_1.md`.

---

### Finding 6 — AWS's own official CI/CD reference architecture uses a topology structurally identical to 4Shark's current one (with CloudFormation/CDK, not Terraform)

**Evidence:** AWS's official Containers blog, "Create a CI/CD pipeline for Amazon ECS with GitHub Actions and AWS CodeBuild Tests," describes a flow where the IaC tool (AWS CDK) provisions the ECS service once with a placeholder image, and ongoing deploys register new task-definition revisions directly via `aws-actions/amazon-ecs-render-task-definition@v1` ("Insert a container image URI into an Amazon ECS task definition JSON file") followed by `aws-actions/amazon-ecs-deploy-task-definition@v1` ("Registers an Amazon ECS task definition and deploys it to an Amazon ECS service") — bypassing the IaC tool for every update after the first.

**Source:** S17, https://aws.amazon.com/blogs/containers/create-a-ci-cd-pipeline-for-amazon-ecs-with-github-actions-and-aws-codebuild-tests/

**Significance:** this is AWS's own reference example, and its shape (IaC creates the skeleton once; the deployer takes over from there, permanently) is structurally the same shape 4Shark runs today (fact 2/3 in the brief), even though AWS's example uses CDK/CloudFormation rather than Terraform. A companion finding (S16) shows AWS's own `amazon-ecs-render-task-definition` GitHub Action is deliberately ownership-agnostic in its README — it does not prescribe where the task-definition JSON should live or who should own it, accepting a file, an ARN, or a family name with no stated preference.

**Verification:** URL fetched: https://aws.amazon.com/blogs/containers/create-a-ci-cd-pipeline-for-amazon-ecs-with-github-actions-and-aws-codebuild-tests/ (S17) / https://github.com/aws-actions/amazon-ecs-render-task-definition (S16) / Verbatim quote checked: yes for both, each via a single `WebFetch` pass / Quote substring confirmed at: S16, S17 in `ecs-boundary_sources_1.md`.

---

### Finding 7 — 4Shark's own current mechanism has a mirror-image counterpart bug documented independently, reinforcing that this class of defect is general, not 4Shark-specific

**Evidence:** a third-party blog documents the opposite failure direction from #711: *"The ECS Deploy action in CodePipeline updates the service with the Task Definition currently associated with the running service, not the latest one you've registered"* — i.e., a NEWLY registered revision is silently ignored, the service stays stuck on the OLD one, the mirror image of 4Shark's incident (where the service moved to a NEW revision missing content the OLD one had). The documented AWS behavior quoted in that source: *"If you create new revisions for the task definition without updating the Amazon ECS service, the deployment action will ignore those revisions."* The proposed fix there is a bespoke Lambda function that force-updates the service to the latest revision.

**Source:** S14, https://www.javierinthecloud.com/solving-the-ecs-task-definition-update-challenge-in-codepipeline-deployments/

**Significance:** every fix found across this spike and the prior one for the general "ECS's notion of current revision and the IaC/pipeline's notion of current revision can silently diverge" problem is a workaround bolted on top of the underlying primitive — a Lambda here, a `check` block in the prior spike, `track_latest` as a provider argument — none of them is described anywhere in the fetched material as a native reconciliation the ECS API itself performs. This is evidence for the underlying volatility of the whole problem space, not evidence for or against any specific 4Shark option.

**Verification:** URL fetched: https://www.javierinthecloud.com/solving-the-ecs-task-definition-update-challenge-in-codepipeline-deployments/ / Verbatim quote checked: yes, single `WebFetch` pass / Quote substring confirmed at: S14 in `ecs-boundary_sources_1.md`.

## Enumerated topologies (brief question b)

The six topologies named in the brief, cross-referenced against what this spike actually found evidence for:

1. **Terraform owns the skeleton; deployer copies-forward and overrides image (4Shark today).** Structurally matches AWS's own CDK/CloudFormation reference architecture (Finding 6, S17), though no source found describes this AS a named pattern with its own label — it is simply "how the AWS example works," described operationally, not endorsed or warned against by name.

2. **Terraform owns everything; deployer only calls `update-service` against a Terraform-rendered revision.** This spike found no source describing this specific shape directly (deployer that ONLY calls `update-service`, never registers). Closest analog found is topology 4 below (Atmos), where the deployer triggers a Terraform apply rather than calling the AWS API at all — a different mechanism achieving a similar ownership outcome. **Not found as a distinct, separately-evidenced topology in this spike's search.**

3. **Deployer owns the task-definition file entirely (app repo JSON); Terraform owns only cluster/service/IAM/networking.** This is exactly the (now-deprecated, per Finding 3/S5) Cloud Posse "Partial Task Definition" pattern, and also the shape ecspresso's own open issue #871 (S21) describes as commonly run alongside Terraform.

4. **Terraform owns everything including the image tag, fed in as a variable — pipeline triggers Terraform rather than the AWS CLI.** This is exactly Cloud Posse's current "ECS with Atmos" replacement (Finding 3/S6) — `APP_IMAGE` is set as an environment variable and `atmos terraform deploy app -s [environment]` is run.

5. **`ignore_changes = [container_definitions]` — Terraform seeds revision 1 and never touches it again.** Not directly evidenced by any NEW source in this spike. This spike did not fetch or re-derive further detail; the prior spike's own git-archaeology finding (prior spike F2, outside the brief's nine numbered facts) already documented that 4Shark itself ran a variant of this — `ignore_changes = [container_definitions]` — for about one month before reverting it. No external source in this spike describes this as a deliberate, ongoing strategy elsewhere — only as a historical entry/exit point in 4Shark's own git history (prior spike F2, not re-derived here).

6. **A dedicated CD tool that owns the boundary by design (ecspresso, or an equivalent).** Directly evidenced — ecspresso (S1, S21, S22, S23) is the dedicated tool found across multiple sources, run either as a full Terraform replacement (S22, S23) or alongside Terraform in a hybrid split (S21). No evidence was found in this spike for AWS Copilot, App Runner, or a CodeDeploy-native (non-Terraform) equivalent addressing this SAME boundary question — those were named in the brief as candidates to check but no fetch was attempted against them in this pass; this is a genuine gap, not a negative finding (see "What remains uncertain").

## Trade-offs surfaced

| Topology | Evidence found | Stability signal found | Source |
|---|---|---|---|
| Terraform skeleton + deployer copy-forward-and-override (4Shark today) | Matches AWS's own CDK reference architecture | No external stability/churn account found either way; 4Shark's own incident (prior spike) is the only concrete failure evidence, and it is 4Shark-specific | S17 (AWS reference); prior spike facts 1-9 |
| Deployer owns task-def JSON entirely (app repo); Terraform owns service/cluster/IAM (partial task definition / ecspresso hybrid) | Documented by Cloud Posse and ecspresso's own open issue tracker | Cloud Posse explicitly DEPRECATED this exact shape; ecspresso's hybrid variant (#871) is still an OPEN, evolving issue, not a settled pattern | S5, S21 |
| Full Terraform/OpenTofu ownership incl. image tag as a variable (Atmos-style) | Documented as Cloud Posse's current replacement for the deprecated pattern above | Presented as the CURRENT recommendation by one named vendor; no independent third-party account of adopting or abandoning this specific Atmos-based shape was found | S6 |
| Full migration away from Terraform to a dedicated tool (ecspresso, no hybrid) | Documented by two independent named organizations (CyberAgent, hrfmmr) | Both describe the migration as smooth/successful post-switch; neither reports a subsequent reversal | S22, S23 |
| `track_latest` (provider-native, Terraform stays in control, image tag resolved by comparing state to the live "latest ACTIVE" revision) | Provider argument since Feb 2024; adopted into the flagship community module's v6.0.0 (prior spike F17-F20) | No problem reports found in THIS spike's search (weak evidence — absence of a hit, not confirmation); 4Shark's own one-time experimental application of the related mechanism ended in a revert, for reasons the prior spike attributes to a pre-existing, unrelated defect rather than the mechanism itself | Prior spike F17-F25; this spike's search turned up nothing new |
| CODE_DEPLOY-controller path: `ignore_changes` on the whole `task_definition` + `load_balancer` blocks | Three independent sources (dev.to walkthrough, AWS's own CFN blog describing the same AWS-level constraint, a closed provider issue with the literal AWS error text) | The most converged, most consistently-described pattern in this entire spike — no source contradicts it, no source describes an alternative for this specific controller type | S9, S10, S11, S12 |

## What remains uncertain

- **No named term exists (that this spike found) for the specific "copy-forward makes a removed field immortal" defect** (Finding 5) — the community vocabulary stops at the generic "configuration drift" / "out-of-band changes."
- **AWS Copilot, AWS App Runner, and any CodeDeploy-native (non-Terraform) tool addressing this exact boundary were named in the brief but NOT investigated in this pass** — no fetch was attempted against any of them. This is a real gap in topology enumeration, not a negative finding.
- **Why Cloud Posse specifically moved from ecspresso to Atmos was not found** — the deprecation fact itself is confirmed twice (S5), but no comparison sentence explaining the decision was recoverable from the fetched page.
- **Whether `track_latest` (or the community module's v6.0.0 adoption of it) has any reported field problems since its 2024 release is genuinely unknown from this spike** — the search came up empty, which is weak evidence of absence, not evidence of stability.
- **No quantitative or survey-level data on which topology is most common industry-wide was sought or found** — every account in this spike is a single organization's narrative, not a measured prevalence.
- **The `terraform-aws-modules/terraform-aws-ecs` main README's current stated position on the boundary question was not recoverable in this spike's fetch** (S8's own repo) — the prior spike already established via direct source-file reads that the module never mentions `CODE_DEPLOY` anywhere in `main.tf` or `docs/UPGRADE-6.0.md`; this spike did not find anything to add to or contradict that.
- **The Terraform Registry's own `aws_ecs_service` resource page fetch failed outright in this pass** (S19) — the prior spike already has a working citation to the same content via a raw GitHub URL, so this is a redundant gap, not a new unknown.

## Suggested options for main and the engineer

Per the standing instruction, these are NOT ranked and NO recommendation is made. Each is grounded in a Finding above.

- **Option A — Keep the current shape (Terraform skeleton + GHA copy-forward-and-override) for both service types.** Grounded in: Finding 6 (matches AWS's own reference architecture, albeit a CDK one). Trade-off: this is the shape that produced 4Shark's own #711 incident (established in the prior spike, not re-derived here), and no external source describes it as a name-brand "recommended" pattern — only as "how one AWS tutorial happens to work."

- **Option B — Adopt `track_latest` for the plain-ECS-controller services (workers), leave the CODE_DEPLOY web service on its current `ignore_changes` pattern.** Grounded in: Finding 2 (CODE_DEPLOY's `ignore_changes` pattern is the most converged evidence in this spike) + the prior spike's F17-F20 (provider-native mechanism purpose-built for exactly this shape). Trade-off: Finding 4 — too new to call proven, and 4Shark's own one experimental attempt at a related mechanism ended in a revert (for reasons the prior spike attributes elsewhere, but the revert happened).

- **Option C — Move the task-definition source of truth into the application repo (deployer-owned JSON), Terraform keeps only cluster/service/IAM/networking.** Grounded in: this is topology 3/6 (Finding, Enumerated topologies). Trade-off: Finding 3 — the most directly comparable named vendor implementation of this shape (Cloud Posse's ecspresso-based Partial Task Definition) was explicitly deprecated by its own author.

- **Option D — Move task-definition ownership fully into Terraform, with the image tag supplied as a Terraform variable and the CI/CD pipeline triggering `terraform apply` rather than calling the AWS API directly.** Grounded in: Finding 3/topology 4 (Cloud Posse's current "Atmos" replacement). Trade-off: no independent third-party account of adopting (or abandoning) this specific shape was found in this spike — it is one vendor's current stated direction, not corroborated elsewhere; also a significant deploy-pipeline redesign (CI/CD would trigger Terraform, not the AWS CLI, which is a different operational model than 4Shark runs today for every other deploy).

- **Option E — Do nothing differently, but treat the CODE_DEPLOY (web) and plain-ECS (worker) paths as two genuinely separate questions going forward**, since Finding 2 shows the two paths have very different amounts of community convergence (CODE_DEPLOY: converged; plain ECS: actively churning both directions). Trade-off: does not resolve the engineer's stated fear of paying a migration cost only to face a third problem on the worker side, since the evidence there is genuinely unsettled — Finding 3 shows organizations moving in both directions with no resolution point found.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`{topic}_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
