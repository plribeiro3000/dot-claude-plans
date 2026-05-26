# App API Domain Documentation + Integration Skill

**Created:** 2026-05-04
**Last updated:** 2026-05-07 — Phase 4 (D3 Integrator Domain) closed: PR #2174 merged the cleanup work (originally Phase 4.1, grew into a structural refactor); PR #2176 merged the consolidated `INTEGRATOR_DOMAIN.md`. v3 analysis captured the post-#2174 state and supersedes v2 for any future drafting. Phases 5 (D4 Runbook Connector) and 6 (D5 Skill) remain.

## Context

The previous session (Commcenter client, drift validation between app and integrator) repeatedly stalled because domain knowledge that is not visible in the code lived nowhere: how 4Shark handles client IDs, why two user creation APIs exist, why the integrator uses a prefix, the deployment topology, the 5-year anonymization rule, and so on.

After the Phase 1.2 analysis (`ANALYSIS.md`), the scope was narrowed: the documentation will cover only the **API-affected** subset of the app's domain — the models and behaviors the integrator can actually touch through `/api/v3/`. The original ambition of documenting the full app domain (Plan, Statement, Commission, Payment, Reward, Incentive, etc.) was dropped because none of that surface is exposed through the API and the original goal of the project (drift integrator↔app) does not need it.

The deliverable shape stays the same: domain doc → API-cross-cutting doc → integrator doc → runbook → Claude Code skill with extraction binaries.

## Guiding principle

**Document behavior, business decisions, historical/legal context, and domain. Document the "why" of design decisions, not the "how" of code.**

Test heuristic: "would this paragraph survive a code refactor?". If not, drop it.

Additional rule, learned in Phase 1.2: **never claim a model is exposed via API based on its name; verify against `config/routes.rb` and the controller's strong_params**.

## Scope

### In scope

- **App API-affected domain** — every model that has an endpoint, every model that gets in/out via nested attributes, every model referenced via payload-ref (Variable, Status, State); their relationships; and the per-resource business behavior the API exposes
- **Cross-cutting API behavior** — guardrails (subsidiary mode), patterns (identity translation, idempotency, no-delete via activity), and architectural decisions (multiple endpoints per behavior, singular resources, asymmetry create vs update)
- **Integrator domain** — what the integrator is, why it exists, topology, contract with the real client, ID decisions, console gotchas
- **Runbook connector** — links app and integrator in domain terms, with debugging flows
- **Claude Code skill** — `~/.claude/skills/<name>/` with full context, workflow for analyzing client bases, and extraction binaries

### Out of scope

- Anything not exposed through `/api/v3/`: Plan, Statement, Commission, Payment, Reward, Incentive, Mobile vs Web auth split, PlanAcceptment, PlanParticipation, Holding/Company hierarchy, internal computation/dataset/audit infrastructure, performance analysis
- How the code works (methods, validations, callbacks, schema)
- Infra/deploy configuration except where it is a domain decision
- Upload flow

## Deliverables

Five documents/artifacts, in dependency order:

1. **App API Domain doc** (`app/docs/<name>.md`) — per-resource business behavior + relationship map, anchored on the API surface
2. **App API Cross-Cutting doc** (`app/docs/<name>.md`) — patterns and behaviors that span resources (guardrails, idempotency, error contracts, anonymization rule)
3. **Integrator Domain doc** (`integrator/docs/<name>.md`) — what the integrator is, why, how it consumes the app's API contract
4. **Runbook Connector** (location TBD: `~/.claude/docs/` or `dot-claude` repo) — links the three above
5. **Claude Code Skill** (`~/.claude/skills/<name>/`) — workflow + binaries for client base drift analysis

## Planned content per deliverable

### Deliverable 1 — App API Domain

The chapter list is anchored on the relationship map in `ANALYSIS.md` (which lists 14 directly-managed models, 4 referenced-but-not-managed models, and the relationship table). Each chapter captures domain reasoning, not code.

#### A) Identity translation pattern

The general rule (client sends their own ID, app maps) and the two exceptions (User has many identifiers via `user_identifiers`, Indicator has no `external_id` and uses composite identity).

Concrete materialization in the controllers: `UserIdentifier.get(...).user_id`, `Client.get_id(...)`, `Variable.get_id(...)`. The 4Shark internal ID never appears in payloads. This is a platform differentiator, not a coincidence — document it as such.

The recommended client behavior (prefix per source system, e.g. `intern-`, `a1-`, `a2-` for a call center with multiple CRMs) and why the platform refuses to unify identifiers on its own.

#### B) Activity / no-delete pattern

The `activity` sub-resource exists on Client, Deal, Group, Product, Role, Subsidiary, User. It is **not** backed by an Activity model — it is two columns (`disabled_at`, `disabler_id`) on each parent, toggled via `enable`/`disable` methods.

Why it matters as domain: 4Shark is a financial platform; nothing is ever truly gone. The client's integration must assume that "deactivate then reactivate" is a normal flow.

#### C) Custom fields — two models, one concept

`Field` (User custom fields, payload `{key, value}`, free-form key) vs `DealField` (Deal custom fields, payload `{variable, value}`, must reference a registered Variable). Same conceptual need served by two designs because the use cases differ — User fields hold ad-hoc per-employee metadata; Deal fields hold structured business data that participates in commission rules.

The asymmetry is intentional — document it.

#### D) Goal — single endpoint, two STI types

`POST /api/v3/goals` accepts both UserGoal and GroupGoal discriminated by the `type` field. The constraint stated in the original plan (one goal type per indicator per plan) holds at the database level via two unique indices (`group_goals_unique_index`, `user_goals_unique_index`).

Why one endpoint and not two: a goal is a goal regardless of subject — splitting the endpoint by subject would suggest the resources are different when the resource is the same.

#### E) Singular resources

`/api/v3/goals` and `/api/v3/indicators` are singular — no URL identifier. Identity is composed from payload fields:

- Goal: `variable + (user_id or group_id) + starts_at + ends_at`
- Indicator: `variable + user_id + compiled_at`

Why singular: indicators have no stable client-side ID (they often come from spreadsheets); goals have a composite business identity (variable + subject + period) that does not fit a single URL parameter cleanly.

#### F) Three seat-change endpoints with distinct semantics

`PATCH /users/:user_id/seat` (parent only), `POST /users/:user_id/promotions` (higher role + parent), `POST /users/:user_id/demotions` (lower role + parent). Three endpoints, three form objects, three sets of validation rules.

Why split: each transition has different invariants (a promotion must move up the hierarchy and the new parent must be higher than the new role; a demotion does the reverse). Documenting one "update" endpoint with a "what changed?" body would shift complexity to the client.

#### G) Hierarchy via Seat (not via User)

Seat has `belongs_to :parent, polymorphic: true` — the chain of command is Seat → Seat, never User → User. Each Seat has a `type` (STI: 11 internal types, 10 exposed via API; SuperAdmin is internal only).

Rules: first node (typically Admin) has no parent; all others have a parent at a higher access level; levels can be skipped (a SalesRepresentative reporting directly to Admin is valid).

Why this design (worth explicit statement): it is engineering, not operations. Many clients struggle with the tree concept; the doc has to walk through both why the model exists and how to read it.

#### H) Multi-identifier User + identifier promotion

User has many `UserIdentifier` records (one-to-many). One is `primary`; the others are secondary. The primary is the one used in payloads from outside (Deal `user_id`, Goal `user_id`, etc., all resolve via `UserIdentifier.get(value).user`).

Promotion (`POST /users/:user_id/identifier_promotions`) flips which identifier is primary. The "promote" call exists because identifying which identifier is "the one" matters for downstream lookups, and that decision can change over time (e.g., a contract migration moves a worker from CRM A1 to CRM A2 as primary).

#### I) Groupifications

(Carried over from the original plan, with the API view added.) Groupification = link between User and Group, with entry/exit dates and a history record per cycle. API exposes `update` (start) and `destroy` (finish) — no `create` because the groupification record may already exist (a previous cycle).

Cover: lifecycle (start, finish, restart resets exit and rewrites entry), chronology constraints (next entry must be after previous exit), why the complexity exists (pro-rated calculations, eligibility windows, anonymized users still appearing, 8-year-old groups with long-departed people).

Implementation note worth surfacing: the model exposes `start(attributes)` and `finish(attributes)` methods that handle the "already active" / "never active" / "already inactive" error cases the client could trigger.

#### J) Subsidiary scoping and cross-subsidiary management

The subsidiary mode is a top-level company configuration that swaps the entire API surface. Cover: why the split exists (data isolation per subsidiary, regulatory document types per country), how `external_parent_subsidiary_id` on User supports the real-world case of a manager in one subsidiary managing reports in another.

Connection to the API guardrail: Cross-Cutting deliverable will cover the guardrail mechanism; this chapter covers the domain reason for needing two API surfaces in the first place.

#### K) Variable as referenced-but-not-managed registry

Goal, Indicator, and DealField all reference Variable via payload key (`variable: 'sales_target'`). Variable cannot be created via API — it must exist on the server before any Goal/Indicator/DealField call can succeed.

Why this matters for integration: the integrator cannot bootstrap a fresh client end-to-end via the API alone; Variables are configuration that must be present (set up by the 4Shark team during onboarding). A drift on Variable → cascading rejects on every dependent call.

### Deliverable 2 — App API Cross-Cutting

Patterns and behaviors that span resources, not specific to any one resource.

- **Identity translation** (the cross-resource view) — every endpoint translates client IDs to internal IDs via `*.get_id(...)` and `UserIdentifier.get(...).user_id`. Errors when the client ID is unknown surface as 404 or 422 with the `nil` propagating into the strong_params; document the actual behavior so the integrator can debug it.
- **Subsidiary mode guardrail** — at the architectural level: every controller checks `current_company.subsidiaries_module?` and aborts with HTTP 400 + a message pointing to the correct API. Document the rule, the failure mode, and the message format.
- **Idempotency key** — every state-changing endpoint accepts `X-Idempotency-Key`. Successful responses cache for 1 hour; errors do not cache. Cross-reference the existing spike at `~/.claude/plans/active/idempotency-key/`.
- **Asymmetry create vs update** — User create accepts `identifiers_attributes` and `seat_attributes` nested; User update accepts neither and forces calls to the dedicated endpoints. Deal create AND update both accept `fields_attributes` nested. Document the asymmetry because it is the source of correctness bugs in integrators.
- **Anonymization endpoint context** — Brazilian labor law (5 years + 1 month buffer); reactivation resets the counter; subsequent deactivation restarts the count. (This survives from the original plan.)
- **Error contracts** — every endpoint maps to a documented error type (`CreateUserErrors`, `UpdateDealErrors`, etc.). The doc should explain what each kind of error means at the domain level, not enumerate them.

### Deliverable 3 — Integrator Domain

(Unchanged from the original plan.)

- **What the integrator is** — an integration client maintained by 4Shark itself
- **Topology** — one integrator per client per environment; ECS clusters, separate AWS accounts, separate normalized database; no multi-tenancy
- **Contract with the real client** — a normalized database prepared by the client, not the raw ERP
- **How the integrator is itself a client of the app's mechanism** — owning the integrator, 4Shark chose the `4sk_` prefix for IDs generated by the integration. Concrete application of the recommendation in Deliverable 1.A.
- **ID decision** — the `id` of the source `users` table is the only stable + non-sensitive key in the contract. It flows forward as `4sk_<id>`. The `external_id` on the same row becomes the primary identifier in the app.
- **Architecture (operational)** — Mongoid + adapter for the source DB. `User`, `UserIdentifier`, `Subsidiary`, `Hierarchy` are Mongoid documents. Source DB reached via `Database.connect!` → `PostgresSqlAdapter` or `MicrosoftSqlAdapter`.
- **Console adapter API (operational)** — `conn.fetch(:table)` returns Array of Hashes; `conn[:table]` does NOT work (raw Sequel, adapter does not expose). Document the gotcha.
- **Source DB schema (operational)** — `users`, `subsidiaries`, `user_identifiers`, `hierarchy`. `users` keyed by `(subsidiary_id, id)`; `id` alone can collide across subsidiaries.
- **Models to read first when debugging** — `app/models/user.rb`, `app/models/user_identifier.rb`, `app/models/subsidiary.rb`.

### Deliverable 4 — Runbook Connector

- **Glossary** — client, normalized database, integrator, app, primary/secondary identifier, subsidiary, immediate manager, groupification, plan, group, variable, indicator, etc. Short, 3–4 lines per term.
- **End-to-end flow in domain terms** — one page, no code, no method names. Conceptual path: client updates ERP → normalized database → integrator detects → integrator calls app → app validates and persists.
- **Canonical mapping in domain terms** — which concept from the normalized database becomes which concept in the app.
- **Common drift symptoms and what they mean** in domain terms.
- **How to debug from a domain standpoint** — start from normalized database (client's truth), then app (what is reflected); difference is drift; root cause is almost always a manual operation outside the integration channel.

### Deliverable 5 — Claude Code Skill

- Lives in `~/.claude/skills/<name>/`
- `SKILL.md` describes the workflow: when invoked, what context to load (Deliverables 1–4), what extraction binaries to run, what to compare, how to report
- **Extraction binaries** — scripts that extract data in the right shape from integrator console (one binary) and app console (one binary), producing data ready to compare without manual reformatting

## Phases

### Phase 1 — Survey

1.1. **Done (lost)** — original API survey at `/tmp/users_cmp/api_survey.md`. File no longer exists; macOS cleared `/tmp/`. Decision: defer the per-endpoint detailed re-survey to Phase 3 (Deliverable 2 entry).

1.2. **Done** — domain topic survey, narrowed to API-affected models. Output: `ANALYSIS.md` in this directory. Lists the 14 directly-managed models, 4 referenced-but-not-managed models, the relationship map, and the 8 cross-cutting findings that anchor Deliverables 1 and 2.

### Phase 2 — Deliverable 1 (App API Domain)

2.1. **Done** — 11-chapter outline confirmed implicitly by drafting all chapters; engineer review of the outline now happens against the drafts
2.2. **Done** — all 5 open questions resolved on 2026-05-05. Findings folded into drafts D1-F (Seat form constraints: chronology, lock, no-op, demotion conflict), D1-J (cross-subsidiary identifier registration), D2-subsidiary-mode-guardrail (field-level mode differences), D2-asymmetry-create-update (workers/GraphQL still use seat_attributes). Q3 finding: `accepts_nested_attributes_for :seat, update_only: true` is NOT dead code — used by `app/workers/user_document/processor.rb` and the GraphQL user mutations
2.3. **Done in draft form** — chapters A through K written to `drafts/D1-A-*.md` through `drafts/D1-K-*.md` (11 files). Pending: final assembly into `docs/architecture/API_DOMAIN.md` (see structure decision in Open Decisions § 6)
2.4. Engineer reviews; iterate
2.5. **Done** — PR #5003 merged on 2026-05-05 (https://github.com/4shark/app/pull/5003). Single commit consolidating D1 + D2 + replacing the overlapping `ID_MAPPING.md` and `API_IDEMPOTENCY.md`. Triage round of 10 Copilot threads applied as fixes; one of those (anonymization) included a code change aligning `USER_ANONYMIZING_WINDOW` default with the production value (1560 → 2590)

### Phase 3 — Deliverable 2 (App API Cross-Cutting)

3.1. **Cancelled** — the per-endpoint survey is no longer needed. Reading the controllers and forms in Phase 2.2 produced equivalent coverage; nothing in the lost survey is missing from the drafts
3.2. **Done in draft form, with one caveat** — 6 sections written to `drafts/D2-*.md`. **D2-idempotency-key.md is superseded by the existing `docs/architecture/API_IDEMPOTENCY.md`** (which already covers everything in the draft plus implementation details); it will not be copied into the consolidated doc. The remaining 5 sections (subsidiary mode, identity translation cross-resource, asymmetry, anonymization, error contracts) will be assembled into `docs/architecture/API_PATTERNS.md`
3.3. Engineer reviews; iterate
3.4. **Done** — bundled in PR #5003 (same as Phase 2.5)

### Phase 4 — Deliverable 3 (Integrator Domain) — DONE

4.0. **Done** — Survey v1 captured in `ANALYSIS-integrator.md` on 2026-05-05 against `develop` @ `3d42dad1`. Original PLAN's 9-bullet outline expanded to a 12-chapter proposal. Snapshot taken before PR #2120 merge.
4.0b. **Done** — Survey v2 (post-#2120 refresh) in `ANALYSIS-integrator-v2.md` on 2026-05-06 against `develop` @ `3e0ce458`. Outline expanded to 13 chapters; identified the `managed_integration?` flag as obsolete and surfaced the README's outdated console-query syntax.
4.0c. **Done** — Survey v3 (post-#2174 refresh) in `ANALYSIS-integrator-v3.md` on 2026-05-07 against `develop` @ `d3dbc67d`. Captured the structural changes from PR #2174 (per-source connection pool simplification, deletion of 42 orphan workers, JOIN port from legacy DatabaseTransformerConsumer to live TransformerConsumer, fetch_since_column fix on 4 streams, DatabaseWarmer Producer/Consumer split). v3 supersedes v2 as the source of truth for D3 drafting.
4.1. **Done — PR #2174 merged on 2026-05-06** as `5c0aee45` (squashed). Original cleanup scope grew during code review into a structural refactor: `managed_integration?` flag and siblings deleted; `Integrator.fully_normalized?` introduced in `lib/integrator.rb`; `Database` global wrapper and `DatabaseConnectionMiddleware` removed; per-source adapter caching via `DatabaseSource.adapters` (`Concurrent::Map`); Sequel's internal pool replaces the external `connection_pool` gem layer; 42 orphan workers deleted (14 `*::DatabaseExtractor` + 14 `*::DatabaseTransformerProducer` + 14 `*::DatabaseTransformerConsumer`); the normalized JOIN logic ported into the 8 user-bearing `*::TransformerConsumer` workers; `fetch_since_column: 'created_at'` added to Hierarchy, Groupification, UserField, UserActivity in `NORMALIZED_SCHEMA`; `DatabaseWarmer` split into Producer/Consumer with retry-count tracked through the Sidekiq job payload; symmetric encryption initializer unconditional in production; README §2.5.1 console-query syntax updated; Apple Silicon Docker note added.
4.2. **Done** — 13 chapter drafts written to `drafts/D3-01-*.md` through `drafts/D3-13-*.md` on 2026-05-07. Each chapter is self-contained (~150-300 lines) and reflects the post-#2174 codebase. Chapter 1 was iterated three times to nail the persona framing (large enterprise without internal engineering, MIS-team-as-data-source-feed, Ruby-as-IP) before the rest was drafted in sequence.
4.3. **Done** — engineer review accepted en bloc.
4.4. **Done — PR #2176 merged on 2026-05-07** as `28d8d172`. Single file: `integrator/docs/architecture/INTEGRATOR_DOMAIN.md`, 1559 lines, the 13 chapters consolidated with sequential structure (`# Integrator Domain` → `## <Chapter>` → `### <Section>`).

### Phase 4.5 — Doc patches uncovered while preparing the skill — DONE

Two coordinated PRs landing 2026-05-07 to fill gaps surfaced when reading D1+D2+D3 from the perspective of the upcoming skill:

4.5.1. **Done — integrator PR #2177 merged on 2026-05-07.** Patches to `INTEGRATOR_DOMAIN.md`: Cap 2 CloudWatch log groups catalog (template-based, derivable from customer slug); Cap 4 hierarchy 5↔3 verb mapping; Cap 4 split "Deals and modifiers" → "Deals" + "Modifier" (corrected wrong Modifier-Deal dependency claim); Cap 4 Modifier↔Indicator and DealExtraField↔DealField cross-system naming notes; Cap 8 stale `DealField` → `DealExtraField`; Cap 9 `Resource.get` vs Mongoid finder gotcha; Cap 11 skipped Streams MongoDB diagnostics; Cap 13 verb selection logic (POST vs PUT, no PATCH); Cap 13 manual state transitions (prior-upload reconciliation procedure with exact console commands — the original `atento-cl` migration that motivated this work).
4.5.2. **Done — app PR #5012 merged on 2026-05-07.** Patches to `API_DOMAIN.md` (Identity translation: `4sk_` prefix is reserved for the integrator; app-side readers can tell `4sk_*` values apart from customer-side prefixes) and `API_PATTERNS.md` (new top-level CloudWatch log groups section: `/ecs/{environment}-*` ECS task templates, the seven Sidekiq queue variants, Lambda autoscaling, RDS engine logs).

### Phase 5 — Deliverable 4 (Runbook Connector) — DROPPED

D4 dropped definitively on 2026-05-07. Conclusion after discussion: the cross-domain connector content overlaps with D3 + D1 + D2, the only genuinely-novel piece (canonical normalized→app mapping) fits naturally as input to D5, and the workflow knowledge (drift symptoms, debugging methodology) belongs codified inside the skill, not in prose. No standalone runbook or connector doc will be written.

### Phase 6 — Deliverable 5 (Claude Code Skill) — DONE

6.1. **Done** — `SKILL.md` written at `dot-claude/skills/integration-debug/SKILL.md`. Loads D1+D2+D3 as mandatory pre-flight; asks engineer for integrator slug + backend slug + scenario; runs three-phase flow (Discovery → Execution → Verification); cleanup gated on engineer confirmation.
6.2. **Done — PR #142 merged on 2026-05-07** in `dot-claude`. Three-file delivery: `skills/integration-debug/SKILL.md` (the skill itself), `CLAUDE.md` (Repository Structure + Available Commands entries), `CHANGELOG.md` (Unreleased Added entry). No per-repo binaries — scripts are generated by the skill at session time, not committed.
6.3. **Done** — Test against the `atento-cl` migration scenario (the actual customer that motivated this work — initially mistranscribed as "Tentuxil" through voice-to-text) was deferred from this delivery; the skill is live and the engineer can validate it in the next setup-reconciliation session.

**Skill design (final):**
- Agent never executes anything in this skill — generates scripts, AWS CLI commands, and CloudWatch queries as text; engineer runs everything via `bin/ecs run` or in their terminal and reports back
- Three-phase flow:
  1. Discovery — snapshot scripts pinpoint divergences across the four data sources (customer source, normalized base, integrator MongoDB, app RDS)
  2. Execution — Ruby scripts the engineer runs in `bin/ecs run` (state machine flips on the integrator side, `UserIdentifier` creation on the app side via console — never via the API) plus a surgical instruction list for the customer's MIS team for normalized-base changes
  3. Verification — re-run snapshots focused on records in scope plus CloudWatch query confirming post-fix state; loop back to Phase 2 if anything is still broken
- Always regenerate scripts from scratch (engineer often runs parallel debug sessions for the same customer; reusing variable names contaminates state cross-debug)
- Output destined for Excel paste uses `@` separator, no quotes
- Per-ID iteration following the Data Processing Pattern (`~/.claude/CLAUDE.md`) — never `.all` / `.to_a` / `.where(...).each` over a large materialized result set

## Open decisions

1. **Final names and locations for D1 + D2 (resolved 2026-05-05)** — `app/docs/architecture/API_DOMAIN.md` and `app/docs/architecture/API_PATTERNS.md`.
2. **Final name and location for D3 (resolved 2026-05-07)** — `integrator/docs/architecture/INTEGRATOR_DOMAIN.md`. Mirrors the app's `docs/architecture/` convention.
3. **Order of chapters within Deliverable 1 (resolved during 2.3)** — A→B→C→D→E→F→G→H→I→J→K, dependency-friendly. Same shape applied to D3 (1→13).
4. **D4 — existence (resolved 2026-05-07)** — DROPPED. See Phase 5.
5. **D5 — skill name (resolved 2026-05-07)** — `integration-debug`.
6. **D5 — script language (resolved 2026-05-07)** — Ruby preferred (Rails console of both sides), but not committed to a language formally — the skill carries the column shape, the script is written on the fly.
7. **D5 — placement of scripts (resolved 2026-05-07)** — NO committed binaries in either repo. The skill writes scripts at session time, the engineer pastes into the runner's Rails console, output goes to S3, skill reads and processes.

## Risks

- **Sliding back into documenting code** — mitigation: apply the "would it survive a refactor?" heuristic to every paragraph
- **Speculating about API exposure based on model names** — mitigation: anchor every claim to a route + controller; the `ANALYSIS.md` is the source of truth for what is in scope
- **Mixing layers** (per-resource vs cross-cutting vs integrator) — mitigation: the deliverable separation is the first defense; for each paragraph, ask "which deliverable does this belong to?"
- **Binaries in Deliverable 5 going stale** — mitigation: keep them to the minimum; rely on the skill workflow + the docs for context, so the binary just produces raw input

## Lessons from previous sessions

- Always validate against `master`, not `develop`
- Primary models first, secondary files after
- When in doubt about behavior, ask rather than guess
- The 4Shark/integrator/app boundary blurs in the head when one party owns both sides; explicit layer separation in writing is the defense
- **Never claim a model is exposed via API based on its name** — verify against `config/routes.rb` and the controller's strong_params. (Learned 2026-05-05 in this very project's Phase 1.2.)
