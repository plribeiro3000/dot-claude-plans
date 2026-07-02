# SPIKE — Ops Self-Service Access to Claude Code Skills

> **Status: CLOSED — 2026-07-01. Decision: do none of the surfaced options.**

## Decision (2026-07-01)

**Do not build any of Options A–D. No further action.**

The spike did its job — it reduced the uncertainty and the answer is that the problem does not justify a solution. Every option surfaced either adds friction or fails to remove the engineer from the path, and the current manual path is already cheap:

- **The task itself is not laborious.** When a request lands in the `Operations` Slack channel, the engineer opens Claude Code, tells it what to run, and it runs. There is no meaningful work to automate away — this was never an automation problem born of complexity, only a wish to simplify an already-light process further.
- **Option B (GitHub Actions), the least-bad of the four, is redundant.** "Ops writes a request → the engineer reads it → the engineer triggers a GitHub Action" is functionally identical to "the engineer reads it → opens Claude Code and runs the skill" — except an interactive Claude Code session is far more flexible than a fixed Action. It would add cost and rigidity to reproduce something that already works better ad-hoc.
- **The only remaining pain is latency (the engineer may not see the Slack message for hours), and none of the options remove it.** Latency would only be solved by something *fully automatic and instant*, which is precisely what was ruled out (reading every Slack message with AI is expensive and fragile). The half-measures that leave a human in the loop keep the latency while adding build/run cost — they simplify nothing that justifies their cost.
- **A cheaper trigger would only be worth it if it were near-zero-effort to build AND removed real work.** Neither holds. So the standing answer is: keep the current manual flow; revisit only if request volume grows enough that the latency becomes a real cost, or if the "scale MongoDB + web + worker(s) then run the integration" procedure is first turned into a skill (it was not found in the repo — see § What remains uncertain).

The evidence and the four options below are retained as the record of *why* this was rejected, so a future session does not re-run the same investigation.

## Investigation question

At 4Shark (a 3-engineer team), a growing set of operational procedures is encoded as Claude Code
skills/commands (`/integrators`, `/apps`, `/connection-poolers`, `/harvesters`,
`integration-debug`, and a candidate not-yet-built "scale up an integrator client's stack"
skill). Requests for these actions arrive via Zendesk/email/WhatsApp, get triaged by the
**Operations team** into a Slack channel called `Operations`, but today only one engineer can
execute them — because Claude Code runs on his machine, under his AWS/GitHub credentials.

The question: how can 4Shark let the **Operations team (non-engineers)** trigger and run these
already-documented skills themselves, with **minimal friction** (ideally: the engineer clicks
OK / two clicks, or the ops person triggers directly), **without impersonating the engineer's
identity**, and **without building a heavy, fully-automated NLP pipeline** reading every Slack
message — given the engineer explicitly does not want full automation, just a "minimal process."

Five sub-questions were researched: (1) documented patterns for exposing Claude Code to
non-technical operators, (2) where Claude Code would need to run if not on the laptop, (3) how to
avoid impersonating the engineer's identity (AWS, GitHub, Slack), (4) concrete low-friction
trigger-surface options compared, (5) a permission/blast-radius model constraining which skills
an operator can run.

## Sources consulted

- [code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless) — `-p`/`--print`
  headless mode, `--allowedTools`, `--permission-mode`, `--bare`, skill invocation in non-interactive
  mode
- [code.claude.com/docs/en/agent-sdk/overview](https://code.claude.com/docs/en/agent-sdk/overview) —
  Agent SDK vs Client SDK vs Managed Agents; runs-in-your-own-process model
- [code.claude.com/docs/en/github-actions](https://code.claude.com/docs/en/github-actions) —
  `@claude` GitHub Action, custom GitHub App for branded bot identity, `claude_args` CLI passthrough,
  skill invocation from a workflow, scheduled/custom-trigger workflows, OIDC cloud auth
- [code.claude.com/docs/en/slack](https://code.claude.com/docs/en/slack) — Claude Code in Slack
  (per-user identity model, being retired)
- [claude.com/docs/claude-tag/overview](https://claude.com/docs/claude-tag/overview) — Claude Tag,
  the org-shared-identity Slack successor
- [code.claude.com/docs/en/claude-code-on-the-web](https://code.claude.com/docs/en/claude-code-on-the-web) —
  cloud sandbox execution model (UNVERIFIED — see auxiliary file, corroborating claim only)
- [platform.claude.com/docs/en/managed-agents/overview](https://platform.claude.com/docs/en/managed-agents/overview) —
  Managed Agents, including the self-hosted-sandbox environment option
- [docs.github.com — GitHub Actions environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment) —
  required-reviewer manual approval gate
- [aws.amazon.com/chatbot](https://aws.amazon.com/chatbot/) — AWS Chatbot / ChatOps precedent
  (non-Claude baseline, UNVERIFIED per auxiliary)
- [Slack Workflow Builder webhooks help article](https://slack.com/help/articles/360041352714-Create-more-advanced-workflows-using-webhooks) —
  incoming webhook trigger; native outgoing-webhook step does not exist (confirmed absent by a
  follow-up search)
- See auxiliary: `ops-self-service_doc_1.md` — full verbatim quote set for every external source
  above, with verification notes per Citation Discipline
- See auxiliary: `ops-self-service_local-grounding_1.md` — excerpts from
  `~/.claude/settings.json`, `~/.claude/docs/AWS-MFA.md`, `~/.claude/skills/integrators/SKILL.md`,
  `~/.claude/scripts/ecs-scale.sh`, and `~/.claude/skills/integration-debug/SKILL.md` that ground
  every claim about 4Shark's current tooling made below

## Findings

### Finding 1: Claude Code headless mode already runs skills non-interactively, using the exact same `~/.claude` config

**Evidence**: `claude -p "/integrators scale down almaviva to 0" --allowedTools "Bash"` runs the
skill to completion and exits, printing the result. Per the docs: "Add the `-p` (or `--print`)
flag to any `claude` command to run it non-interactively... Without [`--bare`], `claude -p` loads
the same context an interactive session would, including anything configured in the working
directory or `~/.claude`." And: "User-invoked skills and custom commands work in `-p` mode:
include `/skill-name` in the prompt string and Claude Code expands it before running."

**Source**: [code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless); full
quotes in `ops-self-service_doc_1.md` § 1.

**Significance**: the four ECS-management skills and any future "scale up integrator X" skill do
not need to be rewritten to be triggered non-interactively — the exact same `SKILL.md` +
`scripts/*.sh` files 4Shark already has work unmodified under `-p`. The gap is not "can Claude
Code run a skill without a human typing in the REPL" (yes, today) — the gap is entirely **who/
what invokes `claude -p`, on what machine, under which credentials**, which is sub-questions 2
and 3.

### Finding 2: `--allowedTools` / `--permission-mode` give a pre-approval mechanism that maps directly onto 4Shark's existing allow-list

**Evidence**: "`dontAsk` denies anything not in your `permissions.allow` rules or the read-only
command set, which is useful for locked-down CI runs. `acceptEdits` lets Claude write files
without prompting and also auto-approves common filesystem commands... Other shell commands and
network requests still need an `--allowedTools` entry or a `permissions.allow` rule, otherwise the
run aborts when one is attempted."

**Source**: [code.claude.com/docs/en/headless](https://code.claude.com/docs/en/headless), § Auto-approve
tools; `ops-self-service_doc_1.md` § 1.

**Significance**: 4Shark's `~/.claude/settings.json` `permissions.allow` list (grounded in
`ops-self-service_local-grounding_1.md` § 1 — e.g.
`Bash(bash $HOME/.claude/scripts/ecs-scale.sh:*)`) already IS an `--allowedTools`-shaped
allow-list. Running headless with `dontAsk` mode against that same settings file gives an
unattended run the identical blast radius as an interactive session: it can run any
already-allow-listed skill script and any read-only AWS command, and will hard-stop (not silently
proceed) on anything in `permissions.ask` (`terraform apply`, `ssh`, `curl`, etc.) or not
allow-listed at all. This is a mechanical enforcement point already built and already tuned by
4Shark — it does not need to be re-invented for a self-service model, only re-pointed at a
different identity (Finding 3).

### Finding 3: the current safety model is command-shape-based, not operator-identity-based — and the AWS write path is welded to one named engineer

**Evidence (local)**: `~/.claude/settings.json`'s hooks and allow/ask/deny lists gate *what kind
of command* may run without confirmation; nothing in that file scopes a rule to *who* is running
Claude Code. Separately, `~/.claude/docs/AWS-MFA.md` states: "The `/elevate-aws-access` skill
automates the MFA elevation flow using 1Password and Windows Hello... 1Password item with your AWS
MFA TOTP, named `"Amazon AWS - <Your Name>"`... MFA device registered on your IAM user."

**Source**: `ops-self-service_local-grounding_1.md` § 1–2 (direct quotes from
`~/.claude/settings.json` and `~/.claude/docs/AWS-MFA.md`, both read in full on 2026-07-01).

**Significance**: two separable facts. (a) 4Shark's default AWS profile is read-only — the
majority of the named skills (`/harvesters` listing, `/integrators` status/logs, most of
`integration-debug` Phase 1/3) need no elevation at all and could run under a shared,
non-personal, read-only service credential today with zero identity risk. (b) The **write** path
(scale up/down, `terraform apply`, any `AccessDenied` retry) is currently anchored to one
engineer's personal 1Password vault item and his own registered MFA device and his own Windows
Hello prompt — this is a personal-identity mechanism by construction and cannot be handed to a
second person without either sharing his own second factor (which defeats "not impersonating
him" and is itself an MFA anti-pattern) or standing up an equivalent elevation path scoped to a
distinct principal (a service/ops IAM role or a second named ops-bot IAM user with its own MFA
device/vault item). Whichever design is chosen, this is the concrete engineering item that makes
"not impersonating the engineer" true and auditable in CloudTrail (a distinct `aws:userid` /
assumed-role ARN for ops-triggered writes, visible in `s3://4shark-cloudtrail` per the existing
searching-account-events runbook) instead of aspirational.

### Finding 4: GitHub Actions already gives 4Shark a documented, distinct bot identity + a one-click human-approval gate, and 4Shark already runs GitHub Actions for every backend deploy

**Evidence**: "The Claude GitHub app requires the following repository permissions: Contents,
Issues, Pull requests" (the default shared Anthropic app) — or, for a branded identity: "For best
control and security... we recommend creating your own GitHub App... This app will be used with
the `actions/create-github-app-token` action to generate authentication tokens in your
workflows." Separately, GitHub Actions environments give: "specify people or teams that must
approve workflow jobs that use this environment," and "a job that references an environment must
follow any protection rules for the environment before running" — i.e. the run pauses until a
named reviewer clicks Approve.

**Source**: [code.claude.com/docs/en/github-actions](https://code.claude.com/docs/en/github-actions)
and [docs.github.com — environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment);
full quotes in `ops-self-service_doc_1.md` § 3 and § 8.

**Significance**: this is the most "already fits 4Shark's existing muscle memory" option. 4Shark
already triggers GitHub Actions workflows for every backend deploy
(`~/.claude/docs/DEPLOY-REFERENCE.md`) and already uses HubFlow/PR conventions on GitHub. A
workflow that (a) is triggered by `repository_dispatch` or `workflow_dispatch` (fireable from a
Slack shortcut, a Zendesk webhook, or a form), (b) targets a GitHub Actions **environment** with
the engineer listed as required reviewer, and (c) on approval runs `claude-code-action@v1` with
`prompt: "/integrators scale down almaviva"` — reuses GitHub's own audit log (who dispatched, who
approved, when) instead of building a new one, and reuses a distinct GitHub App bot identity for
any resulting commits/PRs. **The friction cost**: the four 4Shark ECS-skills use bash scripts
that call `aws` directly against AWS — a GitHub Actions runner has no AWS credentials by default,
so this path requires provisioning a **separate, scoped AWS OIDC role** (GitHub's own
recommended pattern: "OIDC is more secure than using static AWS access keys because credentials
are temporary and automatically rotated") restricted to exactly the ECS actions the skills need
(`ecs:UpdateService` on tagged clusters, `ecs:Describe*`/`List*`), which is new Terraform work,
not zero-cost. It also requires the skill files to be reachable in the GitHub Actions runner
(today they live only in the engineer's personal `~/.claude/`, git-ignored — see open questions).

### Finding 5: 4Shark already has a working design precedent for splitting an ops workflow into an automatable phase and a human-gated phase

**Evidence**: `~/.claude/skills/integration-debug/SKILL.md`: "Phase 1 (Discovery) and Phase 3
(Verification) — fully automated by you... Phase 2 (Execution) — manual, non-negotiable...
Human review is the only gate against a wrong filter mass-mutating production data — never
automate Phase 2."

**Source**: `ops-self-service_local-grounding_1.md` § 5 (partial structural read of
`integration-debug/SKILL.md`, first 80 of a larger file — used only to cite the documented
division-of-labor shape, not to execute that skill's workflow).

**Significance**: 4Shark does not need to invent a permission philosophy from scratch. The same
split — "read/list/status is automatable, write/scale/mutate needs a human gate" — already
exists for `integration-debug` and can be applied mechanically to the ECS-management skills:
`/harvesters` (read-only by SKILL.md's own description), `/integrators` status/logs, and
`/apps`/`/connection-poolers` status checks are candidates for direct ops self-service with no
approval step at all; `/integrators scale up/down`, MongoDB EC2 start/stop, and any future
"stand up an integrator client's full stack" skill are candidates for the human-gated tier.

### Finding 6: the Anthropic-native Slack/cloud paths (Claude Tag, Claude Code on the web) are built for coding-task delegation (produce a PR from a connected GitHub repo), not for triggering local bash-script ops skills against AWS

**Evidence**: "Each session runs under your own Claude account, using your connected repositories
and your plan limits" (per-user Claude Code in Slack) — or, for the successor: "@Claude as your
organization's shared identity with admin-configured access... What it can reach depends on the
channel you're in, not on who you are... You extend what Claude can reach, like your
repositories, ticketing systems, data warehouses, and custom tools, through connections, plugins,
and skills." Cloud sessions execute in "an isolated, Anthropic-managed VM" (UNVERIFIED per
auxiliary — corroborating source only).

**Source**: [code.claude.com/docs/en/slack](https://code.claude.com/docs/en/slack),
[claude.com/docs/claude-tag/overview](https://claude.com/docs/claude-tag/overview); full quotes
in `ops-self-service_doc_1.md` § 4–6.

**Significance**: Claude Tag's admin-configured, channel-scoped, shared-identity model is
*exactly* the non-impersonation shape 4Shark wants ("what it can reach depends on the channel,
not on who you are") — but it is designed around GitHub-repo-connected coding sessions producing
PRs, run in an Anthropic-managed cloud sandbox. That sandbox does not have 4Shark's local
`~/.aws/credentials`, the 1Password/Windows Hello MFA flow, or the engineer's GitHub CLI session
— the ECS-scaling and MongoDB-start skills as currently written (bash scripts calling `aws`
directly with ambient local credentials) would not run there unmodified. **Claude Managed
Agents' self-hosted-sandbox environment** ("Sandboxes on infrastructure you control for
compliance or data-residency requirements") is the one Anthropic-native primitive that *could*
point at 4Shark-controlled infrastructure carrying the right AWS role — but it is currently in
beta, billed directly via API tokens rather than the engineer's existing Claude plan, and is a
materially bigger integration project than the GitHub Actions or dedicated-host options below.

### Finding 7: a native "Slack button → runs something else" step does not exist out of the box — it requires either a small custom Slack App or a third-party connector

**Evidence**: Slack's own Workflow Builder documentation covers only the inbound direction:
"When you choose to start a workflow with a webhook, you'll configure the webhook to kick off
your workflow when a third-party app or service sends a web request to your URL." A follow-up
search found no native Workflow Builder step for sending an outbound HTTP request; that
capability exists only via a third-party connector app or a first-party custom Slack App using
Slack's documented interactivity payloads (slash commands / buttons).

**Source**: [Slack Workflow Builder webhooks help article](https://slack.com/help/articles/360041352714-Create-more-advanced-workflows-using-webhooks);
full note in `ops-self-service_doc_1.md` § 10.

**Significance**: "just add a button in the `Operations` Slack channel that triggers the skill"
is not a zero-build Slack feature. The lowest-code version is a Slack incoming-webhook-triggered
Workflow Builder form (input: which skill, which client, which action) whose *output* still needs
something to consume it — either a small custom Slack App (slash command/button, well-documented
first-party API) or a third-party connector — wired to whichever backend (GitHub Actions
`repository_dispatch`, or a dedicated host's own webhook receiver) actually runs `claude -p`.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A. Slack-queue + engineer's own machine polls/approves** (no new infra) | Zero new infrastructure; zero new identity to manage; engineer stays the sole executor so impersonation risk is moot; can ship in a day | Does not let the ops person "trigger it directly" — only reduces the engineer's per-request cost to ~2 clicks; engineer's machine must be on/reachable when the request lands (the "must be running when they ask" constraint the engineer raised) | Local grounding (Findings 1–3); no vendor doc needed, this is pure 4Shark process design |
| **B. GitHub Actions (`repository_dispatch`/`workflow_dispatch`) + environment required-reviewer + `claude-code-action`** | Reuses 4Shark's existing GitHub Actions muscle memory and audit log; distinct GitHub bot identity (custom GitHub App) for any resulting commits; one-click engineer approval via environment reviewer; runners are ephemeral (no always-on host to patch/own); skills run headless exactly as documented (Finding 1) | Needs a new, scoped AWS OIDC role provisioned in Terraform (new write-capable IAM surface, reviewed carefully) since GitHub runners have no AWS credentials by default; the `~/.claude/skills/` directory is currently personal and git-ignored — needs to be checked into a repo (or a plugin) the runner can read; still needs *something* to fire the `repository_dispatch` from Slack (Finding 7) | Findings 4, 7; `ops-self-service_doc_1.md` §3, §8 |
| **C. Dedicated always-on "ops relay" host (small EC2/container) running headless Claude Code under a service IAM role, fronted by a Slack Bolt app or AWS Chatbot custom action** | Reuses the exact existing bash-script skills unmodified, including the local `~/.claude` config as-is (Finding 1); most flexible for skills that assume a specific local shape; Slack-native approval button already proven at industry scale (AWS Chatbot) | An always-on host is new infra someone has to own (patching, cost, uptime — directly the "must be running when they ask" trade-off, inverted: now it always IS running); needs a custom Slack App (Finding 7) or AWS Chatbot custom actions to receive the trigger; the service IAM role and its own elevation-equivalent (if any write ops need MFA-grade gating) is new design surface, not reused from Finding 3 | Findings 3, 6, 7; `ops-self-service_doc_1.md` §7, §9 |
| **D. Anthropic-native (Claude Tag / Claude Code on the web / Managed Agents self-hosted sandbox)** | Claude Tag's channel-scoped shared identity is conceptually the exact non-impersonation model wanted; least custom "routing" code if the workflow were pure coding/PR tasks | Built for GitHub-repo-connected coding sessions producing PRs — the ECS-scaling/MongoDB bash-script skills do not run in the Anthropic-managed cloud sandbox unmodified (no local AWS profile, no 1Password/Windows Hello); Managed Agents' self-hosted-sandbox variant could close this gap but is in beta, billed via direct API tokens (separate from the engineer's Claude plan), and the biggest integration lift of the four options | Finding 6; `ops-self-service_doc_1.md` §4–7 |

## What remains uncertain

- Whether `~/.claude/skills/` — currently personal and git-ignored per 4Shark's Configuration
  Changes Policy and Security section — would need to become a checked-in, shared repository
  artifact for Option B or C to read it from a non-personal execution context, and if so, which
  repository and under what review process. Not researched in this spike.
- Whether AWS IAM already has (or would need) a distinct principal for "ops-triggered writes"
  that is narrower than the existing `4shark-mfa` role — i.e. can `ecs:UpdateService` be scoped
  to only the tagged clusters the named skills touch, denying everything else, as a single
  Terraform-managed role. Not researched in depth; flagged as a concrete follow-up in Finding 3.
- Whether the "candidate to become a skill" workflow named in the investigation ("scale up 3
  MongoDB instances + 1 web + 1–2 workers, then run integration") has been written as a `SKILL.md`
  yet, or is still purely manual — this spike did not find such a skill under
  `~/.claude/skills/`, only the four already-existing ECS-management skills and
  `integration-debug`. If it does not exist yet, building it is a prerequisite to any self-service
  option, independent of which trigger surface is chosen.
- Cost/volume: how many ops requests per day/week actually flow through the `Operations` Slack
  channel today, and how many of them are read-only status checks vs. writes. This directly
  affects which tier (Finding 5's split) matters most and whether GitHub Actions minutes / API
  token spend (Finding 4, Finding 6) are material or negligible at 4Shark's scale.
- Whether the engineer's intended "he just clicks OK" step is meant to happen *every time* (a
  standing approval gate, as in Options A–C) or only as a *one-time* provisioning decision (grant
  the ops team a scoped self-service path once, then they trigger unsupervised within the
  allow-listed skill set). The investigation prompt is compatible with either reading and the
  two produce different designs (Finding 5's split matters much more under the second reading).

## Options surfaced — ALL REJECTED (see § Decision at the top)

The four options below were the candidates. The engineer reviewed them and rejected all four on 2026-07-01: each adds friction or cost without solving the actual problem (latency), and the current manual flow is already cheap. Kept for the record of why.


- **Option A — Slack-queue, engineer's own machine, near-zero build.** Ops posts the request in
  the existing `Operations` channel in a fixed lightweight format (or a Slack Workflow Builder
  form, per Finding 7, triggering an incoming webhook); a small script polling that queue on the
  engineer's own machine surfaces it to him as a single approve/deny prompt; on approve, the
  existing skill runs exactly as today. Cheapest, but the ops person still does not trigger
  directly and the engineer's machine must be reachable.
- **Option B — GitHub Actions dispatch + required-reviewer environment + `claude-code-action`.**
  Reuses 4Shark's existing CI/CD muscle memory and audit trail; needs a new scoped AWS OIDC role
  and a decision on where `~/.claude/skills/` lives so the runner can read it. Best fit if the
  team wants an auditable, GitHub-native approval trail and is comfortable investing in the OIDC
  role now.
- **Option C — Dedicated always-on ops-relay host + custom Slack App/AWS Chatbot.** Reuses the
  skills completely unmodified including local script assumptions; most flexible, but is new
  infrastructure someone must own, and needs its own elevation-equivalent design for write
  operations (Finding 3).
- **Option D — Anthropic-native (Claude Tag / Managed Agents self-hosted sandbox).** Conceptually
  the closest match to "channel-scoped shared identity, not personal," but the current 4Shark
  skills (local bash + AWS profile + 1Password MFA) do not fit the Anthropic-managed cloud
  sandbox without a self-hosted-sandbox integration project — the largest lift of the four, and
  built on a beta product.

No recommendation is made between these — the engineer decides based on how much new
infrastructure/IAM surface he is willing to stand up now versus defer, and how the open questions
above (skill-repo location, IAM scoping, request volume, one-time-vs-standing approval) resolve.
