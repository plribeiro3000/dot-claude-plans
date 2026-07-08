# Content Inventory — `dot-claude` classified for Ops access (Eixo A)

Auxiliary to `SPIKE.md`. Every unit of content in `dot-claude` (as of commit `3d456b9`,
branch `develop`), classified on two independent axes:

- **Ops utility**: `OP` (operational-useful — matches one of the three declared Ops use
  cases), `DEV` (dev-only noise — Rails/Ruby/DDD/planning workflow, irrelevant to Ops),
  `NEU` (neutral/meta — universal agent-behavior rule, useful regardless of role)
- **Sensitivity**: `SENS` (carries client names, infra specifics, compliance/legal
  process, or security-investigation material Ops should not default into) / `NORM`
  (no confidentiality concern)

Method: every file was read in full except the Tier 3 docs marked "title-only" below —
for those, the classification is derived from the file name and the one-line "See"
description that already exists in `CLAUDE.md` (cited by line), not from opening the
file. This is a scope limitation of the spike, stated explicitly per file.

## Part 1 — `CLAUDE.md` sections (source: `~/Projects/4Shark/dot-claude/CLAUDE.md`)

| Line | Section | Ops utility | Sensitivity | Note |
|---|---|---|---|---|
| 7 | Never Emit a Credential Value in the Session | NEU | NORM | Universal output-safety rule |
| 14 | Language Policy | NEU | NORM | Universal — governs how Claude talks to any engineer |
| 27 | Bash Single-Line Policy | NEU | NORM | Applies to any Bash use, not code-specific |
| 35 | Working Directory Behavior | DEV | NORM | Escape hatches are Ruby/Rails/Terraform-specific |
| 58 | Git Safety | DEV | NORM | Ops does not commit/push per the stated use case |
| 74 | Git Push Safety | DEV | NORM | — |
| 92 | Worktree Policy | DEV | NORM | — |
| 104 | Work Through to the Pull Request | DEV | NORM | — |
| 112 | HubFlow Policy | DEV | NORM | — |
| 123 | Instruction Precedence | NEU | NORM | Universal |
| 128 | Disagree and Commit | NEU | NORM | Universal |
| 145 | Documentation Loading Model | DEV | NORM | Describes Tier 1/2/3 hook plumbing for code-write flows |
| 165 | Git Commit Policy | DEV | NORM | — |
| 175 | Git Tag & Version Policy | DEV | NORM | — |
| 189 | Changelog Policy | DEV | NORM | — |
| 220 | Pull Request Policy | DEV | NORM | — |
| 228 | No Client/Infra Data in PR/Commit | DEV | NORM | Scoped to PR/commit text Ops never writes; the underlying confidentiality principle is worth carrying informally but the rule as written is dev-scoped |
| 238 | Production Access | **OP** | NORM | Directly answers "can Claude read prod?" — core to the health-check use case |
| 244 | Searching Account Events | NEU-leaning-SENS | SENS-borderline | CloudTrail/audit investigation is a security capability; useful for "o que aconteceu com X" but is an investigative/security tool, not a client-fact lookup — flagged for the engineer to decide |
| 250 | Local Databases | DEV | NORM | `bin/databases` is a Rails-repo dev workflow |
| 258 | Security (sensitive files) | NEU | NORM | Universal git-hygiene rule |
| 264 | Plans Repository Auto-Commit | DEV | NORM | Planning-doc workflow (PLAN.md/SPIKE.md authoring) |
| 271 | Automated Dependency Updates | DEV | NORM | Renovate/Dependabot — CI/dependency management |
| 286 | Bang Methods in Web Flow | DEV | NORM | Ruby/Rails code convention |
| 294 | Optional belongs_to | DEV | NORM | Rails |
| 299 | No Multiple `raise` | DEV | NORM | Ruby |
| 304 | Bulk Delete | DEV | NORM | Rails/ActiveRecord |
| 310 | Use the Object | DEV | NORM | OO code-style |
| 318 | LGPD Data Erasure | DEV/OP-adjacent | **SENS** | Runbook itself says ownership is "one person" (CTO); contains mailbox names, Google Sheet links, Zendesk process detail. Ops may need to *recognize* an LGPD request and escalate, but running the runbook is not the stated Ops use case |
| 327 | Rails Migrations | DEV | NORM | — |
| 336 | Linting Policy | DEV | NORM | — |
| 344 | Variable Naming | DEV | NORM | — |
| 361 | Code Pattern Discipline | DEV | NORM | Code-write only |
| 369 | Ask, Don't Decide | NEU | NORM | Universal agent-behavior rule |
| 379 | Testing Policy | DEV | NORM | — |
| 390 | Data Processing Pattern | DEV | NORM | ActiveRecord/Mongoid |
| 398 | Script Discipline | DEV | NORM | Rails-console script generation — Ops does not write code per the stated use case |
| 411 | ActiveRecord Query Discipline | DEV | NORM | — |
| 427 | Data Access | DEV | NORM | — |
| 437 | Data Processing — Topologies | DEV | NORM | — |
| 451 | Deployment Strategy | DEV-leaning-NEU | NORM | Ops doesn't trigger deploys, but the "one shared backend serves many tenants" framing overlaps with the health-check use case conceptually |
| 462 | Jurisdiction & Policy | DEV | **SENS** | Contains a live client-name × backend × jurisdiction map |
| 470 | Project Layout | NEU | NORM | Useful if Ops ever needs Eixo B code access (repo layout) |
| 478 | Configuration Changes Policy | NEU | NORM | Universal — applies to anyone touching `dot-claude` |
| 489 | Communication Style | NEU | NORM | Universal |
| 498 | Research-First Policy | **OP** | NORM | Directly matches "investigation, not source of truth" use case |
| 510 | Full-Read Discipline | NEU | NORM | Universal |
| 520 | Questions Are Just Questions | NEU | NORM | Universal |
| 533 | Subagent Contract — Research Only | DEV | NORM | ~90 lines; almost entirely about the plan/task/DDD pipeline Ops won't use |
| 622 | Citation Discipline | NEU | NORM | Universal, but mostly a subagent-internal rule |
| 642 | Memory Save Workflow | NEU | NORM | Universal |
| 656 | Lookup Resolution — Exact Match Wins | **OP** | NORM | Directly governs how `/apps`, `/integrators` etc. resolve names — Ops will hit this constantly |
| 668 | Output Policy | **OP** | NORM | ~190 lines; universal, but the PR/commit/email-credential edge cases inside it are dev-flavored noise within an otherwise essential doc |
| 861 | AWS Policy | **OP** | NORM | Directly matches the health-check use case |
| 871 | Terraform Policy (pointer) | DEV | NORM | — |
| 875 | Identity Stack and Engineer Permissions | DEV | NORM | Terraform-repo specific |
| 879 | Ruby Version Manager in Bash | DEV | NORM | — |
| 899 | Terraform Command Execution | DEV | NORM | — |
| 915 | Command Safety Policy | **OP** | NORM | Applies to any Bash/AWS command Ops runs |
| 926 | Execution Policy | NEU | NORM | Universal |
| 932 | Scope Discipline | DEV | NORM | ~160 lines about code diffs/PRs |
| 1093+ | Three Workflows / Agent tables / repository structure / plans storage / document types | DEV | NORM | Describes the DDD/plan/task pipeline and the code-repo layout end to end — not relevant to Ops's investigation use case |

**Rough size accounting**: the file is 1498 lines. Lines classified `OP` above cover
roughly 240 lines (Production Access, Research-First, Lookup Resolution, Output Policy,
AWS Policy, Command Safety) out of 1498 — **about 16%** of the current `CLAUDE.md` by
line count is squarely Ops-useful; the rest is dev workflow, git/PR mechanics, or
Ruby/Rails code convention.

## Part 2 — `docs/` (Tier 1/2/3), by file

Source: `~/Projects/4Shark/dot-claude/docs/*.md` (file listing, `find` on
2026-07-07). "Read" = full content read for this spike. "Title-only" = classified from
file name + the `CLAUDE.md` "See" line cited above.

| File | Read? | Ops utility | Sensitivity |
|---|---|---|---|
| `JURISDICTION.md` | Read (full) | DEV (front-creation only) | **SENS** — live client×backend×jurisdiction map (`docs/JURISDICTION.md:31-58`) |
| `PROJECTS-CATALOG.md` | Read (full) | NEU/OP | NORM — useful reference for Eixo B (which repo is which) |
| `AUTHENTICATION-ARCHITECTURE.md` | Read (full) | **OP** | NORM — directly useful for "existe API de X" questions about login; contains code `file:line` internals (not client data) |
| `DATA-STORES-ARCHITECTURE.md` | Read (full) | **OP** | NORM — useful conceptual map for health-check reasoning; contains code-level detail |
| `WHITE-LABEL-ARCHITECTURE.md` | Read (full) | **OP** | NORM — directly frames "a deploy to a shared stack touches every tenant", useful before any health-check conclusion |
| `ECS-SERVICE-TOPOLOGY.md` | Read (full) | **OP** | NORM — this is the exact doc that prevents "desiredCount=0 looks down but isn't", core to the health-check use case; already cross-referenced from `skills/apps/SKILL.md:90` |
| `AWS-MFA.md` | Read (full) | **OP** | NORM — Ops needs to know the read-only-by-default model even if Ops never gets elevation |
| `IDENTITY-STACK.md` | Read (full) | DEV | NORM — `terraform` repo specific, `ivo`/break-glass profile |
| `runbooks/security/SEARCHING-ACCOUNT-EVENTS.md` | Read (full) | NEU-leaning-SENS | SENS-borderline — same flag as the CLAUDE.md section above |
| `runbooks/compliance/LGPD-DATA-ERASURE.md` | Read (full) | DEV | **SENS** — internal Google Sheet links, mailbox owner names, single-owner (CTO) process |
| `README.md` (repo root) | Read (full) | NEU | NORM — installation/distribution instructions; directly relevant to *how* to distribute Ops's config, not to what Ops sees |
| `ACTIVE-RECORD-QUERY-DISCIPLINE.md` | Title-only (`CLAUDE.md:425`) | DEV | NORM |
| `ALPHABETICAL-ORDERING.md` | Title-only | DEV | NORM |
| `ASK-DONT-DECIDE.md` | Title-only (`CLAUDE.md:377`) | NEU | NORM |
| `AUTOMATED-DEPENDENCY-UPDATES.md` | Title-only (`CLAUDE.md:284`) | DEV | NORM |
| `BANG-METHOD-WEB-FLOW.md` | Title-only (`CLAUDE.md:292`) | DEV | NORM |
| `BULK-DELETE.md` | Title-only (`CLAUDE.md:308`) | DEV | NORM |
| `CHANGELOG.md` | Title-only (`CLAUDE.md:218`) | DEV | NORM |
| `CITATION-DISCIPLINE.md` | Title-only | DEV/NEU | NORM — subagent-internal, not something Ops invokes directly |
| `CODE-PATTERN-DISCIPLINE.md` | Title-only (`CLAUDE.md:367`) | DEV | NORM |
| `CODE-STYLE-RULES.md` | Title-only (`CLAUDE.md:359`) | DEV | NORM |
| `COMMAND-SAFETY.md` | Title-only (`CLAUDE.md:924`) | **OP** | NORM — same rule Ops relies on for any Bash it runs |
| `DATA-ACCESS.md` | Title-only (`CLAUDE.md:435`) | DEV | NORM |
| `DATA-PROCESSING.md` | Title-only (`CLAUDE.md:396`) | DEV | NORM |
| `DEPLOY-REFERENCE.md` | Title-only (`CLAUDE.md:460`) | DEV | NORM — Ops does not trigger deploys per the use case |
| `DEPLOYMENT-STRATEGY.md` | Title-only | DEV | NORM |
| `DOCKER-IMAGE-TOOL-REPOSITORIES.md` | Title-only (filename) | DEV | NORM |
| `FACTORYBOT-CONVENTIONS.md` | Title-only | DEV | NORM |
| `GROUND-BEFORE-SURFACE.md` | Title-only (`CLAUDE.md:374`) | NEU | NORM |
| `LANGUAGE-POLICY.md` | Title-only (`CLAUDE.md:25`) | NEU | NORM |
| `LINTING.md` | Title-only (`CLAUDE.md:342`) | DEV | NORM |
| `LOCAL-DATABASES.md` | Title-only (`CLAUDE.md:256`) | DEV | NORM |
| `NO-MULTIPLE-RAISE.md` | Title-only (`CLAUDE.md:302`) | DEV | NORM |
| `NO-PREMATURE-DRY.md` | Title-only (filename) | DEV | NORM |
| `NO-SAFE-NAVIGATION.md` | Title-only (filename) | DEV | NORM |
| `NO-UNLESS-CONVENTION.md` | Title-only (filename) | DEV | NORM |
| `OPTIONAL-BELONGS-TO.md` | Title-only (`CLAUDE.md:297`) | DEV | NORM |
| `OUTPUT-EDGE-CASES.md` | Title-only (`CLAUDE.md:859`) | NEU | NORM — companion to Output Policy, which is OP |
| `POST-MORTEM-GUIDE.md` | Title-only (filename + `skills/post-mortem/SKILL.md`) | NEU-leaning-DEV | NORM — Ops could plausibly *file* an incident report someday, but authoring one is not the stated use case |
| `PULL-REQUEST-CONVENTIONS.md` | Title-only (`CLAUDE.md:226`) | DEV | NORM |
| `RAILS-MIGRATIONS.md` | Title-only (`CLAUDE.md:334`) | DEV | NORM |
| `RSPEC-CONVENTIONS.md` | Title-only (filename) | DEV | NORM |
| `RUBY-COMMAND-EXECUTION.md` | Title-only (`CLAUDE.md:897`) | DEV | NORM |
| `SCRIPT-DISCIPLINE.md` | Title-only (`CLAUDE.md:409`) | DEV | NORM — Ops does not write mutation scripts per the stated use case |
| `SUBAGENT-CONTRACT.md` | Title-only | DEV | NORM |
| `TERRAFORM-CONVENTIONS.md` | Title-only (`CLAUDE.md:913`) | DEV | NORM |
| `TERRAFORM-POLICY.md` | Title-only (`CLAUDE.md:871`) | DEV | NORM |
| `TESTING-PHILOSOPHY.md` | Title-only (filename) | DEV | NORM |
| `USE-THE-OBJECT.md` | Title-only (`CLAUDE.md:316`) | DEV | NORM |
| `WORKTREE-POLICY.md` | Title-only (`CLAUDE.md:102`) | DEV | NORM |
| `runbooks/INDEX.md` | Read (full) | Mixed (see Part 4) | Mixed |
| `adr/ADR-001..004` | Not read (out of scope — internal decision records about the `dot-claude` tooling itself) | DEV | NORM |

## Part 3 — `skills/` (every `SKILL.md`, all read in full for this spike)

| Skill | Ops utility | Sensitivity | Note |
|---|---|---|---|
| `apps` | **OP** | NORM | Directly matches "está tudo certo com a aplicação do shared?" |
| `authenticators` | **OP** | NORM | Keycloak/SSO health |
| `connection-poolers` | **OP** | NORM | Postgres pooler health |
| `harvesters` | **OP** | NORM | Read-only, matches health-check use case |
| `integrators` | **OP** | NORM | Read-only listing matches health-check; note `environments.json` (per-skill data file, not audited in this spike) likely carries client names — flag for the engineer |
| `onboarding` | **OP** | NORM | — |
| `setup` | **OP** | NORM | — |
| `ec2-instances` | **OP** | NORM | Read-only listing |
| `elevate-aws-access` | DEV-leaning-NEU | NORM | Only relevant if Ops is ever granted MFA-elevated write access — not needed for the stated read-only use case |
| `integration-debug` | DEV | **SENS-adjacent** | Generates Rails-console *mutation* scripts against production data (`skills/integration-debug/SKILL.md:6-13`); explicitly not a read-only tool; out of scope for "Ops does not write code" |
| `runbook` | Mixed | Mixed | Dispatches to whatever runbook matches — inherits that runbook's own classification (see Part 4) |
| `post-mortem` | NEU-leaning-DEV | NORM | Same note as `POST-MORTEM-GUIDE.md` above |
| `pr-triage` | DEV | NORM | GitHub PR review-thread resolution — code workflow |
| `create-app-webclient` | DEV | **SENS** | Creates a new client front end; touches `JURISDICTION.md`'s client map directly |

Not present in this repo listing but named in `CLAUDE.md`/`README.md`: `create-integrator`
and `meeting-context` are **single-file commands** (`commands/create-integrator.md`,
`commands/meeting-context.md`), not folder skills — see Part 3b.

## Part 3b — `commands/` (single-file slash commands)

| Command | Ops utility | Sensitivity |
|---|---|---|
| `execute.md` | DEV | NORM |
| `test.md` | DEV | NORM |
| `merge-cleanup.md` | DEV | NORM |
| `cleanup-memories.md` | DEV | NORM |
| `create-integrator.md` | DEV | **SENS** — creates client infrastructure |
| `op-signin.md` | DEV-leaning-NEU | NORM — only relevant to MFA elevation |
| `meeting-context.md` | Mixed | **SENS** — reads `~/.meeting-notes/`, client conversation history, commitments (`commands/meeting-context.md:3,21-29`). Not part of the declared Ops use case (code+infra investigation) but plausibly adjacent to "suporte a ticket de cliente" — flagged for the engineer to decide explicitly, do not default it in |

## Part 4 — `docs/runbooks/` (by category, from `docs/runbooks/INDEX.md`, read in full)

| Category | Ops utility | Sensitivity |
|---|---|---|
| `client-onboarding/*` | DEV | **SENS** — SSO client secrets, integrator client creation |
| `compliance/*` | DEV | **SENS** — LGPD, Zendesk client tickets, internal register sheets |
| `databases/*` | DEV | NORM — Mongo Atlas auth, replica-set migration; infra-operational, not Ops's stated use case |
| `development/HUBFLOW.md` | DEV | NORM |
| `engineer-access/*` | DEV | NORM/**SENS**-adjacent — `BREAK-GLASS.md` and `AWS-ENGINEER-SETUP.md` describe IAM/root-account access; not something Ops needs to operate, though the concepts (baseline vs elevated) are useful background |
| `migrations/*` (VPC) | DEV | NORM |
| `security/*` | Mixed | Mixed — `PENTEST-ACTIVATION.md` is dev/security-team only; `SEARCHING-ACCOUNT-EVENTS.md` is the borderline case flagged above |
| `services/*` (Keycloak, Setup) | DEV/OP-adjacent | NORM — operational runbooks for services Ops might ask about (auth-001), but written for the engineer doing the operating, not for read-only investigation |
| `terraform-operations/*` | DEV | NORM |
| `vpn/*` | DEV | NORM |

## Part 5 — `agents/` (all 14, names only — none read in full; classification by role)

Every agent in `agents/` is part of the DDD/plan/task/PR-review/spike pipeline described
in `CLAUDE.md:1093-1195`. None of them matches "Ops does not write code; Ops investigates
by reading". All classified **DEV / NORM**: `orchestrator`, `knowledge-cruncher`,
`context-mapper`, `process-modeler`, `domain-modeler`, `plan-researcher`, `plan-composer`,
`task-researcher`, `task-composer`, `output-verifier`, `policy-verifier`,
`code-policy-verifier`, `pr-review`, `spike` (this very agent — DDD/planning research
tooling, not incompatible with Ops using it for their own investigations, but designed
around the engineer-planning workflow).

## Part 6 — `scripts/` (hooks + wrappers, all 40 files, names only)

Grouped by function rather than listed individually (see
`~/Projects/4Shark/dot-claude/scripts/` for the full listing):

- **Universal safety/output hooks** (OP/NEU, NORM): `validate-bash-command.sh`,
  `auto-approve-aws-readonly.sh`, `inject-output-policy-reminder.sh`,
  `inject-output-preservation-reminder.sh`, `inject-working-dir-reminder.sh`,
  `inject-skill-tip.sh`, `notify.sh`, `cleanup-sessions.sh`, `check-dependencies.sh`,
  `check-claude-version.sh`, `check-projects-folder.sh`, `statusline.sh`
- **AWS/ECS operational wrappers** (OP, NORM): `ecs-scale.sh`, `start-instance.sh`,
  `stop-instance.sh`, `redirect-ecs-scale.sh` — the exact scripts the Ops health-check
  skills call
- **Ruby/Rails/Bundler execution** (DEV, NORM): `ruby.sh` and every `check-*`/`validate-*`
  hook scoped to `.rb`/Rails file writes (`check-abbreviated-variables.sh`,
  `check-bulk-delete.sh`, `check-raw-sql-query.sh`, `check-pluck-ruby-reshape.sh`,
  `validate-bang-method-web-flow.sh`, `validate-worker-topology-naming.sh`,
  `validate-concurrent-index-migration.sh`, `validate-rails-migration-creation.sh`)
- **Terraform execution** (DEV, NORM): `terraform.sh`, `redirect-terraform.sh`,
  `inject-terraform-context.sh`
- **Git/PR/commit workflow** (DEV, NORM): `inject-pr-commit-data-policy.sh`,
  `inject-commit-policy-reminder.sh`, `inject-pr-review-context.sh`,
  `setup-worktree.sh`
- **DDD/plan/policy pipeline** (DEV, NORM): `inject-code-pattern-on-write.sh`,
  `inject-code-pattern-rule.sh`, `inject-policy-verifier-docs.sh`,
  `inject-code-policy-verifier-docs.sh`, `inject-full-read-reminder.sh`,
  `inject-integration-debug-docs.sh`, `inject-deployment-strategy.sh`,
  `inject-query-discipline.sh`, `auto-approve-claude-dir-writes.sh`,
  `auto-approve-local-skills.sh`, `auto-approve-safe-mv.sh`
- **Plans auto-commit** (DEV, NORM): `plans-autocommit.sh`, `setup-plans-autocommit.sh`,
  `check-plans-autocommit.sh`
- **Migration runner** (NEU, NORM): `migrate.sh` + `migrations/*.sh`

Nearly every hook in the DDD/git/Rails/Terraform groups is registered against a
`matcher` (`Edit|Write|MultiEdit`, code file extensions, `git commit`, `terraform *`)
that never fires for an Ops session that only reads and runs `/apps`-style skills — they
are inert rather than actively confusing, **except** that `read-context.sh` inlines every
Tier 1 + Tier 2 doc (including the DEV-only ones) into every session and subagent start
regardless of who is running it (`scripts/read-context.sh`, wired at
`settings.json:22,64`) — this is the mechanical reason a naive "give Ops the whole repo"
approach floods their context with Rails/RSpec/DDD rules from the first prompt, matching
the engineer's "vai mais confundir que ajudar" concern.
