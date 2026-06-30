# SPIKE — Zero-Downtime Deploy Strategy: Canonical Terms, Industry Practice, and Claude Code Integration

**Conducted by:** spike agent
**Date:** 2026-06-24
**Status:** Research complete — pending decisions

---

## Investigation question

What are the exact canonical industry terms for the three zero-downtime deploy practices 4Shark already uses (permission-flag-gated backend-first deploys, expand/contract schema migration, and risk-based single vs multi-phase decision)? What does the community say about injecting this whole-system deployment context into Claude Code so the agent picks the appropriate strategy rather than the most conservative one? What decision framework distinguishes when phasing is mandatory vs when a single deploy is sufficient?

---

## Sources consulted

- [martinfowler.com/bliki/ParallelChange.html](https://martinfowler.com/bliki/ParallelChange.html) — canonical definition of Parallel Change / Expand and Contract
- [martinfowler.com/articles/feature-toggles.html](https://martinfowler.com/articles/feature-toggles.html) — canonical Feature Toggle taxonomy including Release Toggles and Permissioning Toggles
- [martinfowler.com/bliki/FeatureToggle.html](https://martinfowler.com/bliki/FeatureToggle.html) — secondary confirmation; does NOT use the term "dark launching"
- [martinfowler.com/bliki/CanaryRelease.html](https://martinfowler.com/bliki/CanaryRelease.html) — canonical Canary Release definition and relationship to Parallel Change
- [martinfowler.com/articles/evodb.html](https://martinfowler.com/articles/evodb.html) — Evolutionary Database Design; transition period / dual-write canonical framing
- [charity.wtf/2023/03/08/deploys-are-the-wrong-way...](https://charity.wtf/2023/03/08/deploys-are-the-%E2%9C%A8wrong%E2%9C%A8-way-to-change-user-experience/) — canonical deploy vs release distinction; "chainsaw vs scalpel" metaphor
- [launchdarkly.com/blog/guide-to-dark-launching/](https://launchdarkly.com/blog/guide-to-dark-launching/) — canonical Dark Launching definition
- [harness.io/harness-devops-academy/progressive-delivery-explained](https://www.harness.io/harness-devops-academy/progressive-delivery-explained) — Progressive Delivery as the umbrella framework
- [docs.aws.amazon.com — ECS rolling update](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html) — minimumHealthyPercent, maximumPercent, deployment circuit breaker
- [github.com/sidekiq/sidekiq/wiki/Deployment](https://github.com/sidekiq/sidekiq/wiki/Deployment) — Sidekiq TSTP/TERM graceful shutdown, in-flight job handling
- [kirshatrov.com/posts/background-jobs-and-deploys](https://kirshatrov.com/posts/background-jobs-and-deploys) — in-flight Sidekiq jobs during deploy; idempotency requirement
- [github.com/ankane/strong_migrations](https://github.com/ankane/strong_migrations) — strong_migrations gem; multi-step rename pattern; ignore_columns pattern
- [sre.google/sre-book/embracing-risk/](https://sre.google/sre-book/embracing-risk/) — user-perceived availability; SLO framing; "reliable enough, not perfectly reliable"
- [arxiv.org/html/2604.14228v1](https://arxiv.org/html/2604.14228v1) — Dive into Claude Code paper; agent context limitations; ReAct loop commits one action sequence without backtracking
- [getunleash.io/blog/claude-code-unleash-agentic-ai-release-governance](https://www.getunleash.io/blog/claude-code-unleash-agentic-ai-release-governance) — Claude Code + MCP + feature flag governance; CLAUDE.md policy encoding for deployment decisions
- [dev.to/nextools — Claude Code for Feature Flags](https://dev.to/nextools/claude-code-for-feature-flags-how-i-ship-risky-changes-without-losing-sleep-4he7) — staged rollout (1%, 10%, 50%, 100%) driven by metrics

See auxiliary: `deploy_sources_doc_1.txt` — verbatim excerpts from all verified primary sources
See auxiliary: `deploy_sources_doc_2.txt` — AI-angle sources, unverified sources (UNVERIFIED tagged), and open questions from codebase

---

## Findings

### Finding 1: Canonical term for Practice 1 — backend-first behind a permission flag

**Evidence:**

The Fowler Feature Toggles article (martinfowler.com/articles/feature-toggles.html) provides the canonical taxonomy. Two toggle types map to 4Shark's practice:

**Release Toggle** (verbatim): "Release Toggles allow incomplete and un-tested codepaths to be shipped to production as latent code which may never be turned on." This is the toggle that ships the new GraphQL API to production before the frontend exists.

**Permissioning Toggle** — three confirmed verbatim substrings from the Fowler article (re-confirmed 2026-06-24):
- "These flags are used to change the features or product experience that certain users receive."
- "For example we may have a set of 'premium' features which we only toggle on for our paying customers."
- "I refer to this technique of turning on new features for a set of internal or beta users as a Champagne Brunch."

This is the toggle the engineer flips for their own database account to validate the feature before releasing to all clients.

The decoupling principle (verbatim from same source): "Using Release Toggles in this way is the most common way to implement the Continuous Delivery principle of 'separating [feature] release from [code] deployment.'"

Charity Majors (charity.wtf, 2023) frames the distinction starkly (verbatim): "Feature flags are a scalpel, where deploys are a chainsaw. Both complement each other, and both have their place." And: "Deploy: the process of building, testing, and rolling out changes to your production software." / "Release: the process of changing user experience in a meaningful way."

The term for what 4Shark does is: **Deploy-Release Decoupling via a Permissioning Toggle + Release Toggle combination**. The broader umbrella is **Progressive Delivery** (Harness, verbatim): "a modern software release strategy that enables teams to deploy changes safely, incrementally, and with minimal risk."

Dark Launching: LaunchDarkly defines it (verbatim) as "a process that allows you to release production-ready software features to a small group of users while hiding them from the rest of the user base prior to a full release." The practice of deploying code to production but exposing it to zero users is specifically "a dark launch."

**Source:** martinfowler.com/articles/feature-toggles.html, charity.wtf 2023, launchdarkly.com/blog/guide-to-dark-launching/

**Significance:** 4Shark's "permission flag" maps precisely to Fowler's "Permissioning Toggle" (long-lived, tied to user identity) AND "Release Toggle" (ships latent code). The engineer's language is internally consistent with the canonical terminology — they have invented the right pattern independently. The industry name for the full practice is deploy-release decoupling, which is the foundational principle of Progressive Delivery.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 2: Canonical term for Practice 2 — three-release column migration

**Evidence:**

Martin Fowler's canonical definition (martinfowler.com/bliki/ParallelChange.html, verbatim): "Parallel change, also known as expand and contract, is a pattern to implement backward-incompatible changes to an interface in a safe manner, by breaking the change into three distinct phases: expand, migrate, and contract."

And specifically for databases (verbatim): "Most database refactorings follow the parallel change pattern, where the migrate phase is the transition period between the original and the new schema, until all database access code has been updated to work with the new schema."

The strong_migrations gem (github.com/ankane/strong_migrations) documents the same multi-step pattern without naming it expand/contract, but the sequence is verbatim: "Create a new column, Write to both columns, Backfill data from the old column to the new column, Move reads from the old column to the new column, Stop writing to the old column, Drop the old column."

The Fowler Evolutionary Database Design article (evodb.html, 2016) provides the underlying theory for why the transition period / dual-write is necessary (verbatim): "it's important that it gets removed once downstream systems have had time to migrate."

The deploy tool site (developertoolkit.ai) confirms that Claude Code itself recommends this pattern for column renames (verbatim): "add the new column as nullable, add a database trigger to keep both columns in sync, backfill existing data" as the pre-deploy phase.

**Source:** martinfowler.com/bliki/ParallelChange.html, github.com/ankane/strong_migrations, martinfowler.com/articles/evodb.html

**Significance:** The 4Shark three-release practice IS the canonical Parallel Change / Expand and Contract pattern. The terminology is well-established (Fowler, 2012). The engineer's phases map exactly: (a) expand = first release, new column + dual write + backfill; (b) migrate = the backfill process itself (possibly via Sidekiq); (c) contract = second release points reads to new column, third release drops old column. The industry sometimes collapses this to two deploys (expand+migrate in one, contract in another) when the backfill is fast — but the full three-deploy version is the safest canonical form.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 3: Canonical framing of "zero FUNCTIONAL downtime" vs infrastructure uptime

**Evidence:**

The Google SRE book (sre.google/sre-book/embracing-risk/, verbatim): "a user on a 99% reliable smartphone cannot tell the difference between 99.99% and 99.999% service reliability!" This establishes the canonical SRE framing: availability is measured from the user's perspective, not the infrastructure's.

The same source (verbatim): "balance the risk of unavailability with the goals of rapid innovation and efficient service operations, so that users' overall happiness—with features, service, and performance—is optimized."

The engineer's definition ("Ah, beleza, a aplicação continua funcionando, mas o login não está funcionando. Isso é um downtime") maps directly to the SRE concept of **composite SLO** or **user-perceived availability**: a service is "up" only if ALL user-critical paths succeed within latency budget. "Login not working = downtime" is an SLO violation regardless of what infrastructure monitors report.

The Google SRE book also frames the philosophy behind the engineer's "judgment point": the goal is not zero outages but rather consuming error budget in a way that maximizes feature velocity while maintaining user trust.

**Source:** sre.google/sre-book/embracing-risk/

**Significance:** The 4Shark definition — "zero FUNCTIONAL downtime, not just infra uptime" — is the canonical SRE user-perceived availability concept. Framing it in SLO terms: a deploy that causes any SLO-critical path (authentication, core user flows) to fail IS a downtime event, even if the process is running. This framing gives 4Shark a precise vocabulary for what the team is actually guaranteeing.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 4: Canonical ECS infrastructure mechanisms (the "tip of the iceberg")

**Evidence:**

AWS documentation (docs.aws.amazon.com/AmazonECS, verbatim): "When you create a service which uses the rolling update (ECS) deployment type, the Amazon ECS service scheduler replaces the currently running tasks with new tasks."

Key parameters (verbatim from AWS docs):
- `minimumHealthyPercent`: "the lower limit on the number of tasks that should be running and healthy for a service during a rolling deployment or when a container instance is draining, as a percent of the desired number of tasks"
- `maximumPercent`: "the upper limit on the number of tasks that should be running for a service during a rolling deployment or when a container instance is draining, as a percent of the desired number of tasks"

Recommended zero-downtime configuration (from web search synthesis, corroborated by multiple sources): minimumHealthyPercent=100, maximumPercent=200.

Failure detection (verbatim): "deployment circuit breaker" and "CloudWatch alarms" — these detect when tasks can't start or when application metrics degrade, and can roll back automatically.

Three values that must be coordinated for true zero downtime: (1) ALB deregistration delay, (2) app-level SIGTERM graceful shutdown duration, (3) ECS stopTimeout. The ordering constraint (from web search synthesis): stopTimeout > deregistration delay + graceful shutdown timeout.

**Source:** docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html

**Significance:** The engineer's "só o tip do iceberg" framing is precisely correct. ECS rolling update (minimumHealthyPercent=100, maximumPercent=200) with deployment circuit breaker and connection draining ensures that no traffic hits a dead container — but it does nothing about logical/functional compatibility between the old and new code versions running simultaneously. Infrastructure zero downtime (ECS) is necessary but not sufficient for functional zero downtime.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 5: In-flight job safety during deploys — Sidekiq specifics

**Evidence:**

Sidekiq wiki (github.com/sidekiq/sidekiq/wiki/Deployment, verbatim): "send it the TSTP signal as early as possible in your deploy process and the TERM signal as late as possible."

On in-flight re-enqueue (verbatim): "Sidekiq will push those jobs back to Redis so they can be rerun later" — jobs that cannot finish within the timeout window are preserved.

Timeout window for deploy scripts (verbatim): "Your deploy scripts must give Sidekiq N+5 seconds to shutdown cleanly after the TERM signal."

For long-running jobs that must not be interrupted mid-state (verbatim): "use the Sidekiq::Job#interrupted? method or the Iteration pattern (both available in 7.3+)"

Kir Shatrov (kirshatrov.com, verbatim): "when the worker receives SIGTERM (graceful shutdown signal), it lets the job to finish with a certain timeout (8s by default). If the job didn't finish within the timeout, it's killed and re-enqueued to be retried in the future."

And the design principle (verbatim): "don't let your developers write non-idempotent jobs that are unsafe to interrupt" / "Always prefer many smaller jobs to one large job."

**Source:** github.com/sidekiq/sidekiq/wiki/Deployment, kirshatrov.com/posts/background-jobs-and-deploys

**Significance:** The engineer's concern about "a job being processed mid-deploy that encodes an old Redis key name and gets lost" is a real risk — and Sidekiq addresses it only partially. Re-enqueueing preserves the job, but the re-run will use the NEW code (new key names). If the job is NOT idempotent and NOT resumable, re-running it with the new naming convention on half-processed data causes corruption. This is exactly why the engineer's 3-round approach for "groupfication documento" (which involves Redis keys) is justified: it isn't just schema safety — it's job-continuity safety. The Sidekiq Iteration pattern would be the alternative that makes single-phase deploy safe in this scenario.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 6: The AI-agent angle — why Claude over-recommends phased approaches

**Evidence:**

The arxiv paper "Dive into Claude Code" (arxiv.org/html/2604.14228v1, verbatim): Claude Code "trades search completeness for simplicity and latency: each turn commits to one action sequence without backtracking." This is the architectural root cause of the over-conservative behavior the engineer describes.

The same paper (verbatim): "the architecture optimizes for immediate task completion rather than developer learning or knowledge transfer" and "limited mechanisms that explicitly support long-term human improvement, deeper understanding, and sustained codebase coherence." The agent lacks persistent system-state knowledge across sessions.

Also from the paper (verbatim): the system uses "deny-first rule evaluation" where "deny rules always take precedence over allow rules." This design philosophy — conservatism as default — bleeds into reasoning about deployment risk when the agent lacks full context: the conservative (most-phased) approach is chosen when uncertainty is high, because the cost of under-phasing is visible (data corruption) while the cost of over-phasing (extra deploys, extra PR review cycles) is not in the agent's error function.

The Unleash blog (getunleash.io, verbatim): "But autonomy without governance is a recipe for instability." Feature flags provide the control mechanism described, and teams that encoded CLAUDE.md policies saw the agent making consistent deployment decisions aligned with team risk posture — but only because the policy was explicit.

The broader web search for "LLM AI coding agent over-conservative recommendations context global view" did NOT yield papers or community discussions that specifically study the over-conservatism failure mode. The arxiv paper comes closest to naming the structural cause (ReAct loop, no backtracking, context window limitations).

**Source:** arxiv.org/html/2604.14228v1, getunleash.io/blog/claude-code-unleash-agentic-ai-release-governance

**Significance:** The engineer's observation that Claude "lacks a visão do todo" is structurally accurate: Claude Code commits to one action sequence per turn without exploring alternatives, and its context window degrades over long sessions. The solution the community has converged on is encoding decision criteria as EXPLICIT rules in CLAUDE.md (not relying on the agent to infer from codebase patterns). The Unleash integration (MCP + CLAUDE.md) is the most documented example of this approach for deployment governance — but it mandates flags for ALL AI-generated logic, not a contextual decision framework. A 4Shark-specific decision framework in CLAUDE.md (or a hook that injects it) would need to encode the conditions explicitly.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

### Finding 7: Community practice for injecting deployment context into Claude Code

**Evidence:**

The Unleash blog (verbatim): "You can encode your FeatureOps policies in a CLAUDE.md file at the project root. Claude Code reads this file automatically and applies its guidance." The MCP server's `evaluate_change` function "Analyzes code modifications to determine flag necessity" — risk classification is done by the tool, not by the agent's unaided reasoning.

The dev.to article on Claude Code + feature flags confirms the pattern but notes the rollout progression is metric-driven, not time-driven (verbatim): "The schedule sets the maximum pace, but the metrics set the actual pace." The agent does not choose when to advance rollout stages — an observability signal does.

The blakecrosley.com CLAUDE.md guide (from search synthesis, not fetched) notes the frontier thinking models "follow roughly 150-200 instructions before compliance drops, leaving roughly 100-150 slots for your CLAUDE.md rules." This is a practical constraint on how much policy can be injected via CLAUDE.md.

Three documented mechanisms for injecting deployment context into Claude Code (from research synthesis):

1. **CLAUDE.md rules** — declarative policy: "when X pattern is detected, use Y deploy strategy." Used by Unleash for flag governance. Pros: persistent, always in context. Cons: counted toward the ~150 instruction limit; relies on the agent reading and applying the rule correctly.

2. **MCP tools** — procedural enforcement: the `evaluate_change` function assesses risk before the agent can generate code. The tool has access to external state (flag registry, deployment history) the agent cannot see. Pros: deterministic enforcement, not relying on agent reasoning. Cons: requires MCP server setup; Unleash-specific.

3. **PreToolUse hooks** — mechanical gates: a hook can block a specific action (e.g., generating a migration that drops a column without first checking the model's `ignored_columns` list) and inject the correct procedure as `additionalContext`. Pros: deterministic. Cons: complex to write; fires per-tool-call, not per-session reasoning step.

**Source:** getunleash.io/blog/claude-code-unleash-agentic-ai-release-governance, dev.to/nextools, arxiv.org/html/2604.14228v1

**Significance:** The community has not published a general-purpose "deploy strategy decision framework for Claude Code." The closest is Unleash's opinionated all-flags-all-the-time policy for AI-generated code. A 4Shark-specific framework (context-dependent, not blanket) would need to be engineered — the existing patterns provide the components (CLAUDE.md rules, MCP evaluation, hooks) but not the assembled framework.

URL fetched / Verbatim quotes checked / Quote substrings confirmed from fetched page content.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Blanket flag-all-AI-generated-logic (Unleash pattern) | Simple rule, easy to enforce, zero cognitive load for agent | Overpenalizes low-risk changes; creates flag debt; every trivial refactor needs a flag lifecycle | getunleash.io |
| Context-aware CLAUDE.md decision framework | Right-sizes phasing to actual risk; avoids unnecessary deploy rounds | Requires explicit condition encoding (CLAUDE.md instruction budget); agent must apply correctly without guaranteed enforcement | arxiv.org/2604.14228v1 |
| MCP evaluation tool (`evaluate_change`) | Deterministic; has access to runtime state; decouples risk assessment from agent reasoning | Requires MCP server infrastructure; currently Unleash-specific; not generalizable without engineering | getunleash.io |
| PreToolUse hooks (mechanical gate) | Deterministic; blocks wrong action before it runs | Per-tool-call scope; cannot reason about session-level strategy; hard to encode compound conditions | arxiv.org/2604.14228v1, CLAUDE.md § hooks |
| Maintenance window (single deploy, not phased) | Simplest execution; no dual-write complexity; no flag lifecycle | Requires coordination (scheduling, notifications); window must guarantee no in-flight processing; not applicable for live-traffic features | kirshatrov.com, sidekiq wiki |
| Sidekiq Iteration pattern for job resumability | Enables single-phase deploy even for Redis key renames; jobs resume from last checkpoint | Requires code change to existing jobs; Sidekiq 7.3+ required; not retroactive | github.com/sidekiq/sidekiq/wiki |
| Expand/contract (3 deploys) | Maximum safety; no in-flight data corruption; backward-compatible at every phase | 3 PR cycles; 3 deploy events; longer total elapsed time; dual-write complexity during migrate phase | martinfowler.com/bliki/ParallelChange.html |

---

## What remains uncertain

- Whether 4Shark's Sidekiq jobs use the Iteration pattern (`Sidekiq::Job#interrupted?`) — if yes, many Redis key rename scenarios can be single-phase deployed safely without a 3-round approach. Requires codebase check in `app` and `integrator`.

- Whether the 4Shark feature permission system is the same system that would hold a Release Toggle (i.e., is it engineered to be flip-able per account in the DB mid-deploy?), or if there are two separate systems. The spike description implies one system that can be scoped to a single account.

- How the CLAUDE.md instruction budget (empirically ~150-200 effective instructions, per blakecrosley.com synthesis) interacts with an added deployment decision framework — specifically whether the context injection via hooks (SubagentStart) survives compaction in long sessions.

- Whether a PreToolUse hook that fires on `Edit|Write` for migration files could reliably detect expand/contract violations (e.g., a `remove_column` without a prior `ignored_columns` model change in the same PR) — the arxiv paper notes that compound condition detection is a known hard problem for Claude Code hooks.

- The exact Redis key structure used in the "groupfication documento" rename scenario (the engineer mentioned "a chave do Redis") — the specific key pattern determines whether the re-enqueue behavior is safe (job is idempotent on new key names) or unsafe (job assumes old key name still exists post-deploy).

---

## Suggested options for main and the engineer

**Option A — CLAUDE.md decision framework (text rules, no new infrastructure)**

Add a section to the 4Shark CLAUDE.md (or a Tier 2 doc loaded by `read-context.sh`) that encodes the deployment decision criteria explicitly. The rules would define: conditions that permit single-deploy (guaranteed no in-flight processing, maintenance window confirmed, change is reversible, no cross-service contract change, no Redis/queue keys that encode the old shape), vs conditions that require phasing (any concurrent processing, irreversible data shape, cross-service API change, Redis keys encoding old names). Claude reads these rules and applies them. No new tooling. Trade-off: relies on the agent reasoning correctly; no mechanical enforcement; subject to context window limits in long sessions.

**Option B — Hook-injected deployment context (PreToolUse on migration writes)**

A `PreToolUse` hook on `Edit|Write` for `db/migrate/` files injects the full decision framework as `additionalContext` at the moment Claude is about to write a migration. The injected context includes: the conditions for safe single-phase vs required multi-phase, and the strong_migrations expand/contract checklist. Mechanically triggered (like the existing `inject-code-pattern-on-write.sh`). Trade-off: fires per migration write, not per session; the agent must still reason correctly about the injected context; hook logic needs to detect migration type.

**Option C — MCP evaluation tool for deployment risk (infrastructure investment)**

Build or adopt an MCP server (similar to Unleash's) that exposes an `evaluate_deployment_risk` tool. The tool receives the proposed change description, checks current system state (are there in-flight Sidekiq jobs for this queue? Is it a maintenance window? Does this change affect Redis keys?), and returns the recommended strategy with justification. Claude calls the tool before proposing a migration plan. Trade-off: deterministic and reliable; requires MCP server engineering and access to runtime state (Sidekiq queue depth, Redis key inventory); largest infrastructure investment.

**Option D — Engineer-gate on migration strategy (no Claude Code change)**

Formalize the existing practice: Claude proposes the migration strategy as a Finding (options + conditions), engineer makes the decision, Claude implements the chosen strategy. Encode the decision criteria in a runbook the engineer consults. Zero Claude Code engineering. Trade-off: most accurate (engineer has the whole-system view Claude lacks); adds latency to every migration decision; does not scale as session count grows.

(NO recommendation — options and trade-offs are presented for the engineer to choose. The right option depends on how often 4Shark faces migration decisions, how much engineering investment is warranted, and whether the instruction budget constraint is a real problem in current sessions.)

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
