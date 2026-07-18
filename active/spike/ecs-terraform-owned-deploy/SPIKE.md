# SPIKE — ECS deploys where Terraform owns everything, including the task-definition pointer

> **This spike brings options with evidence. It does not rank them and makes no recommendation.** Standing instruction, restated because the engineer's own framing is a request for a stable answer, which is exactly the pressure that produces a manufactured consensus if not resisted.

## Investigation question

How do teams run ECS deploys where Terraform owns EVERYTHING — including moving the service's task-definition pointer — so that no external deployer is in the critical path? What does the community actually do, and what breaks?

The engineer's underlying driver, restated: not content-ownership (Terraform already owns SSM parameters, secrets, and `command` for all 37 4Shark services — established fact, prior spikes) but **removing the dependency on a third-party service being in the deploy path**. "We run Terraform, and that is the whole deploy."

## Established facts treated as ground truth

Per the brief, this spike builds on `../ecs-taskdef-pointer-lag/ANALYSIS.md`, `../ecs-taskdef-pointer-lag/SPIKE.md`, `../ecs-taskdef-ownership-boundary/SPIKE.md`, and `../terraform-ignore-changes-task-definition-drift/SPIKE.md`. All nine numbered facts in the brief and the `ecs-taskdef-ownership-boundary/SPIKE.md` findings (cited as "prior spike Finding N") are taken as given, not re-derived. **What that prior spike's Finding 2 actually concluded — correctly restated here: titled "For the CODE_DEPLOY (blue/green) controller, the community's answer is converged, stable, and NOT Terraform-specific," its Significance states plainly that "the CODE_DEPLOY case is not 'Terraform has a problem here'... The community's answer... is the one 4Shark's web service already runs." That prior Finding 2 was correct, and this spike does not dispute it for the CODE_DEPLOY controller as it existed at the time of that research. The "is not itself a solution" phrase belongs to a different Finding entirely — prior spike Finding 1, about HashiCorp's own general anti-out-of-band-change guidance, which never mentions CODE_DEPLOY. This spike's legitimate basis for revisiting the picture is narrower and different: it is not that prior Finding 2 was wrong, but that a genuinely new AWS mechanism — ECS-native blue/green, announced July 2025, outside that prior spike's research window — may open a path for the web service that did not exist when that spike ran. See Finding 3.**

> **Correction note.** An earlier draft of this paragraph misattributed the "is not itself a solution" quote to prior spike Finding 2 and mischaracterized what that Finding concluded (stating it "treated [CODE_DEPLOY] as a fixed constraint," when Finding 2 in fact found the CODE_DEPLOY answer converged and settled, and never used that phrase at all). The `output-verifier` caught this — the quote is real and verbatim, but lives in prior spike Finding 1 (about HashiCorp's general guidance, not CODE_DEPLOY), while prior spike Finding 2's actual subject and conclusion are the near-opposite of how the earlier draft described them. The paragraph above is the correction. No Finding's evidence or conclusion in this document was changed as a result — Finding 3 below already correctly grounded its claims in AWS's own July 2025 announcement and the provider evidence, not in the mischaracterized prior-spike attribution.

## Sources consulted

All 17 sources are indexed and quoted in full, with verification blocks, in the auxiliary file:

- [`ecs-terraform-owned-deploy_sources_1.md`](./ecs-terraform-owned-deploy_sources_1.md) — S1 through S17, including three fetched directly via `gh api` from the Cloud Posse `atmos-native-ci` repository's actual source files (not summaries of the README), two GitHub provider-issue citations on failure modes, and the negative/UNVERIFIED results recorded honestly rather than omitted.

## Findings

### Finding 1 — The one working full-Terraform-drives-ECS-deploy reference implementation is Cloud Posse's Atmos example, and its own source code shows a CI service is still in the critical path

**Evidence:** The `atmos-native-ci` repository's actual GitHub Actions workflow (fetched directly, not paraphrased) authenticates via `atmos auth login --identity plat-dev/terraform` under `permissions: { id-token: write }`, then runs the single command `atmos terraform deploy app -s dev` with `APP_IMAGE` set as a plain environment variable. This IS "Terraform owns the pointer" in the sense the engineer wants — no `aws ecs update-service` call anywhere in the pipeline, the deploy step is 100% a Terraform apply. But the pipeline that gets there is still GitHub Actions: a runner GitHub operates, triggered by GitHub's own event model (`pull_request`, `merge_group`), authenticating via GitHub's OIDC token exchange.

**Source:** S1 (workflow file), S2 (stack config), S3 (atmos.yaml).

**Significance:** This directly and honestly answers brief question (a): the topology exists and works, but it does not remove a third-party service from the deploy path — it relocates what that service DOES, from "call the AWS API" to "trigger a Terraform apply." GitHub Actions (or whatever CI runs the job) is still the thing that decides when the deploy happens, still holds the credentials, and still is a dependency 4Shark does not operate. The engineer's stated goal — "só depende da gente rodar o Terraform, não depende de um serviço" — is not satisfied by this topology as built by its own reference implementation; a service still runs the deploy trigger, it is just triggering `terraform apply` instead of `aws ecs update-service`.

**Verification:** See auxiliary file S1–S3 — each fetched via `gh api ... --jq '.content'`, base64-decoded, and read directly (not summarized by a search engine or a `WebFetch` paraphrase). Re-confirmed present at time of writing.

---

### Finding 2 — The image tag flows in via an Atmos-specific env-var-to-config binding (`!env`), and the CI identity that applies it is named/scoped for apply, not for a narrow ECS update

**Evidence:** `image: !env APP_IMAGE 068007702576.dkr.ecr.us-east-2.amazonaws.com/.../atmos-native-ci:sha-2ee4206` in `terraform/stacks/defaults/app.yaml` — Atmos's custom YAML tag resolves the `APP_IMAGE` environment variable at render time into the Terraform component's `image` variable. The identity the CI job assumes is named `plat-dev/terraform` (`atmos auth login --identity plat-dev/terraform`) — an identity scoped by its own name to run Terraform, i.e., apply-level AWS permissions, not the narrower `ecs:UpdateService`-only permission a plain deployer would need.

**Source:** S2, S1.

**Significance:** Directly answers brief question (b) for this one reference implementation: the mechanism is a template-language variable substitution feeding a normal Terraform variable — not a Terraform data source resolving a registry tag at plan time (`track_latest`-style), and not a CI call to `update-service`. The identity naming is a real, if indirect, signal that the CI pipeline holds broader AWS credentials under this topology than a narrow-scope deployer would — trading "CI can only nudge the service pointer" for "CI can run any Terraform change to this stack," a real security-shape shift from 4Shark's current split (GHA's IAM role only needs ECS deploy permissions, not whatever the `app`/`integrator` Terraform stacks touch). **Whether this specific identity is narrowly scoped to only the `app` component, or is a broader apply identity reused across components, was not determined from the fetched files** — this is a genuine gap, not a claim either way.

**Verification:** See auxiliary file S1, S2.

---

### Finding 3 — A newer AWS mechanism (ECS-native blue/green, July 2025) may open a path for the CODE_DEPLOY-controlled web service that did not exist when the prior spikes ran

**Evidence:** AWS announced native blue/green deployments built into ECS itself, distinct from the CodeDeploy-controller path, in July 2025: *"using the AWS Management Console, SDK, CLI, CloudFormation, CDK, and Terraform"* (S6). AWS's own DevOps blog states *"ECS-native blue/green deployments is now the recommended option for most teams and new projects"* and frames CODE_DEPLOY as a path you can keep or migrate away from (S7). `terraform-provider-aws` v6.4.0 (released the same month) added a `strategy` argument to `deployment_configuration`, with valid values `ROLLING`, `BLUE_GREEN`, `LINEAR`, `CANARY` (S9), used under `deployment_controller { type = "ECS" }` — **not** `type = "CODE_DEPLOY"`. One named individual (S8) configured a service this way, ran `terraform apply` against it, and reports: *"Deployment worked successfully"* — i.e., a Terraform-driven `task_definition` change on this new controller type triggered a working native blue/green rollout, the exact thing the CODE_DEPLOY controller's AWS API rejects (fact 2 in the brief).

**Source:** S6, S7, S8, S9.

**Significance:** Directly and honestly answers brief question (c): this spike did **not** find that the web service's CODE_DEPLOY restriction is permanently unbreakable — it found a newer, AWS-native alternative (`deployment_controller = "ECS"` + `deployment_configuration.strategy = "BLUE_GREEN"`) that is a *migration*, not a flag flip on the existing controller, and for which the AWS API's task-definition-update restriction (which is specific to the `CODE_DEPLOY` controller) does not appear to apply. **This is weaker evidence than Finding 1 or 2** — it rests on one individual's blog post (not a named organization's production account), and the provider's own documentation does not carry an explicit sentence stating "unlike CODE_DEPLOY, BLUE_GREEN accepts direct Terraform-driven task_definition updates" (S9's caveat). It is a real, dated, first-party-sourced possibility, not a settled community consensus — the "community answer" for THIS specific new mechanism has not had time to converge (the feature is roughly one year old relative to this spike's date).

**Verification:** See auxiliary file S6–S9.

---

### Finding 4 — What breaks: Terraform's own success signal for an ECS deployment has two independently reported failure modes

**Evidence:** `terraform-provider-aws` issue #19519: *"The terraform apply command does not appropriately wait for the state to be steady. It seems to exit after about 6 minutes, when the ECS service attempts to deploy the second time after failing the first time"* — with the ECS deployment circuit breaker enabled, a failed-then-rolled-back deployment can still make `terraform apply` report success (S11). Issue #16012, a separate report: *"the actual behavior is inconsistent given the same Terraform configuration"* — the same config produced completion times ranging from 1–7 minutes to a 10-minute timeout, with no configuration change between runs (S12).

**Source:** S11, S12.

**Significance:** Directly answers brief question (d) for the specific concern of "does a failed deploy leave things in a bad, undetected state." In a topology where "Terraform apply succeeded" IS the deploy's success signal (because there is no separate deployer to report status independently), these two reports show that signal can be wrong or non-deterministic under at least the circuit-breaker + `wait_for_steady_state` combination. This is a genuine risk specific to collapsing "infra provisioned" and "deploy succeeded" into the same tool's single exit code — a risk that does NOT exist in 4Shark's current split (GHA's deploy script and CloudWatch/ECS-service-level monitoring are a separate, independent signal from "did terraform apply exit 0").

**Verification:** See auxiliary file S11, S12.

---

### Finding 5 — State-lock contention under concurrent Terraform runs is a real, documented failure mode, but no source found ties it specifically to "every app deploy is a terraform apply" at deploy frequency

**Evidence:** Simply Business (named organization, directly fetched, not a search summary): *"If one Terraform binary attempts to acquire a lock on a state file that is already locked, an exception is raised and the Terraform run exits"* — caused in their case by `plan` and `apply` running in separate Jenkins stages with a manual review gate between them, so two concurrent branch builds could each be mid-flight on the same state file (S14). Their fix was NOT a Terraform-native mechanism — they built their own synchronization by polling live ECS task status before letting a Terraform action proceed.

**Source:** S14. (A second, generic source on the same topic, `quickinfracloud.com`, returned HTTP 404 on direct fetch and is marked UNVERIFIED in the auxiliary file — it does NOT sustain this Finding; only S14 does.)

**Significance:** Partially answers brief question (d): state-lock contention during Terraform-driven ECS work is real and has forced at least one named organization to build an out-of-band workaround. But this is evidence for "concurrent Terraform provisioning collides with itself," not specifically for "an ECS deploy pipeline that runs a fresh `terraform apply` on every code push hits lock contention at deploy frequency" — that more specific claim was searched for and not found substantiated by any fetchable source in this spike. The generalization from S14 to 4Shark's specific concern (would 4Shark's dozens of daily worker/web deploys across 4 stacks collide on state locks if each were a `terraform apply`?) is the reader's own extrapolation, not something this spike found stated anywhere.

**Verification:** See auxiliary file S14 (verified) and S13 (UNVERIFIED, excluded).

---

### Finding 6 — No source found describing the exact "thin deployer, Terraform authors everything" middle ground (brief topology e); the closest hit is a different, already-known topology

**Evidence:** A targeted search for a deployer whose ONLY action is `aws ecs update-service --task-definition <arn-from-terraform-output>` — never registering its own revision — returned, as its closest hit, a Medium post (Jack Mahoney) describing Jenkins doing the opposite: Jenkins itself calls `register-task-definition` then `update-service`, using Terraform only for cluster/service-level outputs (S15). This is topology 1 from the prior spike (`ecs-taskdef-ownership-boundary/SPIKE.md`), not topology (e).

**Source:** S15.

**Significance:** Directly and honestly answers brief question (e): **this spike did not find a named account of this specific middle-ground topology being run anywhere.** This does not mean it does not exist or would not work — the mechanics are simple (a `data "aws_ecs_task_definition"` or a Terraform output exposing the latest ARN, consumed by a one-line CI step) — but no community discussion, blog post, or module documentation describing it AS a deliberate, named pattern was found within this spike's search budget. This is recorded as a genuine gap, not papered over with a synthesized "yes, people do this."

**Verification:** See auxiliary file S15.

---

### Finding 7 — The honest bottom line on removing a third-party service from the deploy path: every real-world instance found still has a service, including HashiCorp's own recommended pattern

**Evidence:** HashiCorp's own Well-Architected Framework GitOps doc: *"GitOps tools continuously monitor Git repositories and automatically apply changes when new commits are merged"*; describing its own SaaS: *"HCP Terraform detects the merge to the main branch and automatically runs a new plan followed by an apply operation"* (S16). Spacelift's guidance, independently: *"Use local runs for quick iteration, but run authoritative plans and all applies in CI/CD (or a dedicated infrastructure orchestration layer) for consistent execution, access control, and auditability"* (S17).

**Source:** S16, S17.

**Significance:** This is the direct, plain answer to brief question (f). Across every source this spike found — the one working reference implementation (Finding 1), HashiCorp's own recommended pattern, and an independent industry source — **something automated is always what triggers the apply**: GitHub Actions in Cloud Posse's case, HCP Terraform (a HashiCorp-run SaaS) in HashiCorp's own described pattern, or "a dedicated infrastructure orchestration layer" generically in Spacelift's framing. No source in this spike describes a genuinely CI-less production deploy path where a human runs `terraform apply` from their own machine as the standing, sanctioned process — every account treats that as the "quick iteration" case, explicitly distinguished from the authoritative production path. **So the honest answer is: the choice available is what the automation surface DOES (call the AWS API directly, vs. trigger a Terraform apply), not whether an automation surface exists at all.** Every topology found in this spike and the prior one keeps some external trigger in the loop; none eliminates it.

**Verification:** See auxiliary file S16, S17.

---

## Enumerated topologies — cross-referenced against this spike's search

Building on the six topologies already enumerated in `ecs-taskdef-ownership-boundary/SPIKE.md`'s "Enumerated topologies" section (that document's numbering retained for continuity):

- **Topology 2 ("Terraform owns everything; deployer only calls `update-service` against a Terraform-rendered revision")** — still **not found as a distinct, separately-evidenced topology** in this spike either (Finding 6). Two spikes now, same negative result.
- **Topology 4 ("Terraform owns everything including the image tag, fed in as a variable — pipeline triggers Terraform rather than the AWS CLI")** — this spike's Findings 1–2 add direct, primary-source detail (the actual workflow file, the actual `!env` binding, the actual identity name) that the prior spike's survey did not have — but the "is this run anywhere beyond Cloud Posse's own example repo" question from the prior spike's "What remains uncertain" is **still unanswered**: no independent third-party production account of this exact shape was found in this spike either.
- **New topology, not previously enumerated — ECS-native blue/green as a third path for the CODE_DEPLOY case (Finding 3).** This is genuinely new information relative to the prior three spikes, which treated the CODE_DEPLOY restriction as settled and permanent for the controller as it existed at the time (per the corrected paragraph above — that prior conclusion was correct for that controller; this spike's new information is a *different* mechanism). It changes the shape of brief question (c)'s answer from "no" to "possibly, via a controller migration, on thin evidence."

## Trade-offs surfaced

| Topology | Evidence found | What it costs | Source |
|---|---|---|---|
| CI triggers `terraform apply` directly (Atmos/Cloud Posse reference shape) | One working, source-verified reference implementation | A CI service is still fully in the critical path — it just triggers Terraform instead of the AWS API; the CI identity needs apply-level (not narrow ECS-update) AWS credentials; the documented CI recipe (`atmos terraform deploy`) re-plans and auto-approves rather than applying a previously reviewed saved plan | S1–S5 |
| Web service migrated from `CODE_DEPLOY` to ECS-native `BLUE_GREEN` strategy | One individual's confirmed working `terraform apply` against this configuration; AWS's own recommendation to migrate toward it | Migration, not a config flag — a genuinely different `deployment_controller` value; no named organization's production account found; provider docs do not explicitly state the CODE_DEPLOY-vs-BLUE_GREEN task_definition-update distinction in so many words | S6–S9 |
| Terraform's own apply as the deploy-success signal | Two independent provider-issue reports of the signal being wrong or non-deterministic under circuit-breaker + `wait_for_steady_state` | A topology that collapses "infra applied" and "deploy succeeded" into one exit code inherits both failure modes; 4Shark's current split (independent deployer + independent monitoring) does not have this specific risk | S11, S12 |
| State-lock contention under concurrent Terraform activity | One named organization's real, documented incident and workaround | Real but not shown to be deploy-frequency-specific for an ECS app-deploy pipeline; the org's fix was a custom workaround, not a Terraform-native feature | S14 |
| "Thin deployer" middle ground (topology e) | Not found as a named pattern anywhere searched | Unknown cost — no account exists to draw a trade-off from | S15 (negative result) |
| Removing the CI/automation-service dependency entirely | Not found anywhere, including in HashiCorp's own recommended pattern | N/A — every source treats an automation surface as required for the authoritative/production apply | S16, S17 |

## What remains uncertain

- **Whether the CI identity in Cloud Posse's reference implementation is scoped narrowly to the `app` component or is a broader apply-capable identity reused across the whole Terraform estate** — not determined from the fetched files (Finding 2).
- **Whether `terraform-aws-modules/terraform-aws-ecs` (the flagship community module) has updated its own documentation to say `ignore_changes` is unnecessary under the new `BLUE_GREEN` strategy** — the relevant issue (#154) was fetched directly and did not carry this answer; genuinely unknown from this spike (S10).
- **Whether a second, independent, named-organization account exists of running `terraform apply` against the new ECS-native `BLUE_GREEN` strategy in production** — this spike found exactly one individual's blog post (S8) and no corroborating second source within its time-box.
- **Whether Terraform's own `wait_for_steady_state` false-success / non-determinism (Finding 4) has been fixed in a more recent provider release** — the two issues cited (#19519, #16012) were not re-checked against the current provider changelog for a closed/fixed status; this is a gap, not a claim that they remain open today.
- **Whether state-lock contention (Finding 5) is a practical problem specifically at the frequency of 4Shark's own deploy cadence (multiple worker/web deploys per day across 4 stacks)** — no source found ties the generic state-lock failure mode to that specific frequency question; this would require either a fifth spike or an actual trial.
- **The brief's topology (e) — "thin deployer, Terraform authors everything" — has no known real-world instance found in two spikes now.** Whether it is simply undocumented (nobody blogs about the boring, working case) or actually rare/broken in some way not yet surfaced is not distinguishable from this spike's evidence.

## Suggested options for main and the engineer

Per the standing instruction, these are NOT ranked and NO recommendation is made. Each is grounded in a Finding above, and each is presented alongside what it does and does not solve relative to the engineer's stated goal.

- **Option A — Adopt the Cloud Posse Atmos shape: CI triggers `terraform apply` (via Atmos or a bare `terraform apply`) instead of calling the AWS API.** Grounded in: Finding 1, Finding 2. What it solves: Terraform genuinely becomes the sole author of the task-definition pointer move, closing the pointer-lag window at the root for whichever services adopt it. What it does NOT solve: the third-party-service dependency the engineer named as the actual goal — GitHub Actions (or whatever CI is used) is still fully in the critical path, now with broader (apply-level) AWS credentials than today's narrower ECS-deploy role.

- **Option B — Migrate the web service's `deployment_controller` from `CODE_DEPLOY` to ECS-native `BLUE_GREEN`, then apply Option A (or an equivalent) to it.** Grounded in: Finding 3. What it solves: potentially removes the one structural blocker (the CODE_DEPLOY API rejection) that made "Terraform drives the web deploy" previously impossible for that controller — prior spike Finding 2's own conclusion about the CODE_DEPLOY path itself is not disputed by this. What it does NOT solve: this is thin evidence (one blog post) for a one-year-old AWS feature; no 4Shark-specific trial has been run; and Option A's CI-dependency point still applies on top of it.

- **Option C — Keep today's split (Terraform owns content, GHA/CodeDeploy own the pointer move) and treat pointer lag as a documented, accepted risk (options A–D from `ecs-taskdef-pointer-lag/ANALYSIS.md`, unchanged by this spike).** Grounded in: Finding 7 (every alternative topology found still has a service in the loop; none is free of that dependency) and Finding 4/5 (moving the deploy into Terraform's own apply inherits two documented failure modes that today's split does not have). What it solves: avoids taking on Findings 4 and 5's risks and Finding 2's credential-scope widening. What it does NOT solve: pointer lag remains exactly as documented in the prior spikes; the engineer's stated goal of removing a service dependency is not addressed at all.

- **Option D — Investigate the "thin deployer" middle ground (topology e) as a 4Shark-original design, since no community precedent was found either way.** Grounded in: Finding 6 (the gap is real, not a hidden "yes, everyone does this"). What it solves: potentially the least credential-scope-widening path — CI would need only `ecs:UpdateService`-equivalent permissions, not apply-level Terraform credentials, while Terraform still authors 100% of the task-definition content. What it does NOT solve: this has zero community validation found in two spikes; 4Shark would be the first documented account, with all the attendant discovery cost of an untested pattern.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, URL + quote, or `gh api` fetch + quote); an uncitable claim is written as "Not found: <…>" instead. Raw source material — full fetch quotes, verification blocks, and honestly-recorded negative/UNVERIFIED results — is preserved in `ecs-terraform-owned-deploy_sources_1.md` in this same directory. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
