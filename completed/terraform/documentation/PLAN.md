# PLAN — Terraform Repository Documentation

> Reference: SPIKE.md (research completed 2026-03-13)

## Objective

Document the 4Shark Terraform monorepo so that any engineer can open the root README and immediately understand how the entire infrastructure works — without reading code. Documentation covers three levels: repository root (macro view), individual stacks (operational detail), and modules (API reference).

## Scope

### In Scope

- Root `README.md` with infrastructure overview and four embedded Mermaid diagrams
- `README.md` for all 19 stacks (18 new + 1 diagram addition to `identity`)
- `README.md` for all 26 modules (23 new + fix 2 existing + generate via terraform-docs)
- `.terraform-docs.yml` configuration file at repository root
- Language fixes in existing files (`internal_alb/README.md`, `public_alb/README.md`, `ecs_cluster` variable descriptions)
- Fix `vpc/README.md` source URL pointing to external repository
- Fill in missing descriptions for `vpc` module variables (`route_table_routes_private`, `route_table_routes_public`)
- 3 new runbooks: "Adding a new integrator client", "Emergency single-stack apply", "State recovery"
- 4 ADRs (MADR format): Terramate, network topology, S3 state backend, identity model
- CI enforcement via GitHub Actions: `terraform fmt --check` + `terraform validate`
- Update `CHANGELOG.md` with the documentation release entry

### Out of Scope

- No pre-commit hooks (rejected in spike research)
- No auto-generated diagrams (Terramaid, Rover, Blast Radius — all rejected)
- No `terraform plan` or `terraform apply` in CI (no AWS credentials in CI)
- No changes to any `.tf` source files beyond fixing variable `description` fields
- No GUI diagram tools (draw.io, Excalidraw)

## Execution Phases

### Phase 1 — Tooling Foundation

**Objective**: Establish the tooling and fix existing documentation before generating new content.

**Components**:
- `.terraform-docs.yml`: Add configuration file at repository root with `formatter: markdown table`, `output.mode: inject`, and `recursive.enabled: true` targeting `modules/`
- `vpc/README.md` fix: Correct the source URL pointing to external elvenworks repository to reference the local module path
- `vpc` variable descriptions: Add `description` to `route_table_routes_private` and `route_table_routes_public` in `modules/vpc/variables.tf`
- `ecs_cluster` language fix: Translate all variable descriptions from Portuguese to English in `modules/ecs_cluster/variables.tf`
- `internal_alb/README.md`: Translate full content from Portuguese to English
- `public_alb/README.md`: Translate full content from Portuguese to English

**Dependencies**: None — this phase has no prerequisites.

**Success Criteria**:
- [ ] `.terraform-docs.yml` exists at repository root and `terraform-docs .` runs without errors
- [ ] `vpc/README.md` source URL references the local module
- [ ] All `vpc` variables have English `description` fields
- [ ] All `ecs_cluster` variables have English `description` fields
- [ ] `internal_alb/README.md` is fully in English
- [ ] `public_alb/README.md` is fully in English

---

### Phase 2 — Individual Stack Documentation

**Objective**: Document all 19 stacks with a `README.md` and embedded Mermaid architecture diagram.

**Components**:

**Integrator stacks (6)** — each README must include: client name, VPC CIDR, number of servers/ECS tasks, client-specific notes, and a Mermaid architecture diagram. Read the stack's `.tf` and `.tfvars` files before writing each README.

| Stack | Client |
|-------|--------|
| `integrator-almaviva` | Almaviva |
| `integrator-aster-maquinas` | Aster Máquinas |
| `integrator-atento-br` | Atento BR |
| `integrator-commcenter` | Commcenter |
| `integrator-maqnelson` | Maqnelson |
| `integrator-redebrasil` | Rede Brasil |

**App environment stacks (5)** — each README must include: environment purpose, AWS region, resources managed, and a Mermaid architecture diagram.

| Stack | Purpose |
|-------|---------|
| `app-atento-001` | Atento (US) |
| `app-atento-br` | Atento (BR) |
| `app-beta-001` | Beta environment |
| `app-demo-001` | Demo environment |
| `app-shared-001` | Shared services |

**Infrastructure stacks (8)** — `identity` already has a README and needs only a Mermaid diagram added; the remaining 7 need a full README with diagram.

| Stack | What it manages | Action |
|-------|-----------------|--------|
| `auth-001` | AWS SSO, auth config | Create README + diagram |
| `dns` | Centralized DNS (Route53 + Cloudflare) | Create README + diagram |
| `identity` | Engineer access across all platforms | Add Mermaid diagram only |
| `monitoring` | Rollbar, alerting | Create README + diagram |
| `networking` | VPC peering, routing | Create README + diagram |
| `setup` | Mobile app configuration service | Create README + diagram |
| `shared-resources` | Shared AWS resources | Create README + diagram |
| `vpn` | Pritunl VPN | Create README + diagram |

**Dependencies**: Phase 1 must be complete (language fixes done before content is written).

**Success Criteria**:
- [ ] All 19 stacks have a `README.md`
- [ ] All 19 stack READMEs contain a `## Architecture` section with a Mermaid diagram
- [ ] All 6 integrator READMEs contain VPC CIDR, server count, and client-specific notes sourced from the stack's `.tf`/`.tfvars` files
- [ ] All 5 app environment READMEs contain environment purpose and AWS region
- [ ] `identity/README.md` retains all existing content and gains a Mermaid diagram
- [ ] All READMEs are written in English

---

### Phase 3 — Module Documentation

**Objective**: Generate and write READMEs for all 26 modules using terraform-docs for the inputs/outputs/resources sections.

**Module README structure** (all 26 modules follow this template):

```
# Module Name

One-paragraph description of what this module creates and its primary use case.

## Architecture

```mermaid
graph TD
  [module resources and relationships]
```

## Usage

[Minimal working example with all required inputs]

## Requirements
<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

## Known Limitations

[List any important constraints or gotchas]
```

**Priority order**:
1. Core modules (most referenced across the codebase — write first): `integrator`, `app`, `ecs_service`, `ecs_cluster`, `rds_instance`, `rds_aurora_cluster`, `codedeploy`
2. Remaining 16 modules: `cloudflare_zone_security`, `ecr`, `ecs_capacity`, `ecs_scheduled_task`, `eventbridge-scheduler`, `iam_deploy`, `integrator_iam`, `lambda-ecs-autoscaling`, `lambda-iam`, `mongodb_atlas`, `networking_data`, `opensearch`, `pritunl`, `redis_cloud`, `s3_bucket`, `vpc_data`

After all module README skeletons are written, run `terraform-docs .` from the repository root to inject the auto-generated sections into every module README.

**Dependencies**: Phase 1 must be complete (`.terraform-docs.yml` must exist; `ecs_cluster` and `vpc` variable descriptions must be fixed before terraform-docs generates their READMEs).

**Success Criteria**:
- [ ] All 26 modules have a `README.md`
- [ ] All module READMEs contain `<!-- BEGIN_TF_DOCS -->` / `<!-- END_TF_DOCS -->` markers
- [ ] `terraform-docs .` runs without errors and injects content into all 26 module READMEs
- [ ] All module READMEs contain an `## Architecture` section with a Mermaid diagram
- [ ] All module READMEs contain a `## Usage` section with a working example
- [ ] All module READMEs are written in English

---

### Phase 4 — Root Documentation

**Objective**: Write the root `README.md` as the macro-level entry point for the entire repository. This phase is written last so it is grounded in the verified stack documentation from Phase 2.

**Root `README.md` structure**:

```
# 4Shark Infrastructure (Terraform)

[Brief description of what this repository manages]

## How the Infrastructure Works

[Comprehensive explanation: networks, VPN, ECS applications,
DNS — Route53 internal + Cloudflare external + Cloudflare rules]

## Network Topology

```mermaid
[All VPCs, CIDRs, regions (Brazil vs USA), VPN access paths, inter-network routing]
```

## Stack Dependency Graph

```mermaid
[All 19 stacks and their Terramate dependency relationships]
```

## DNS Architecture

```mermaid
[Route53 zones internal, Cloudflare zones external, delegation flow, which stack manages each]
```

## ECS Architecture

```mermaid
[ECS clusters, services, load balancers, deployment flow]
```

## Repository Structure

[Table of all 19 stacks with purpose and links to their READMEs]

## Modules

[Table of all 26 modules with one-line description and link to README]

## Prerequisites

- Terraform >= 1.x
- Terramate >= 0.x
- AWS credentials configured
- MongoDB Atlas, Redis Cloud API keys

## Getting Started

[How to initialize and plan/apply a stack]

## Contributing

[How to add a new stack, module, or make changes]
```

**Four embedded Mermaid diagrams**:

| Diagram | Contents |
|---------|----------|
| Network Topology | All VPCs, CIDRs, regions (Brazil vs USA), VPN access paths, inter-network routing |
| Stack Dependency Graph | All 19 stacks and Terramate `after` ordering relationships |
| DNS Architecture | Route53 zones (internal), Cloudflare zones (external), delegation flow, which stack manages each |
| ECS Architecture | ECS clusters, services, load balancers, deployment flow |

**Note on stack dependency diagram**: The diagram reflects Terramate orchestration order (the `after` blocks in `stack.tm.hcl`) — not data flow. There are no `terraform_remote_state` data sources in this repository; stacks are independent at configuration time.

**Dependencies**: Phase 2 must be complete — root diagrams and repository structure table depend on verified stack content.

**Success Criteria**:
- [ ] `README.md` exists at repository root
- [ ] Root README contains all 4 Mermaid diagrams
- [ ] Repository Structure table lists all 19 stacks with links to their READMEs
- [ ] Modules table lists all 26 modules with links to their READMEs
- [ ] Prerequisites and Getting Started sections are complete
- [ ] README is written in English

---

### Phase 5 — Operations and Governance

**Objective**: Add runbooks for common operational tasks, ADRs for key architectural decisions, and CI enforcement to prevent documentation drift.

**Runbooks** (stored in `docs/runbooks/`):

| File | Content |
|------|---------|
| `ADD-INTEGRATOR-CLIENT.md` | Step-by-step guide for adding a new integrator client stack |
| `EMERGENCY-SINGLE-STACK-APPLY.md` | How to apply a single stack manually outside normal orchestration |
| `STATE-RECOVERY.md` | Procedures for recovering from corrupted or inconsistent Terraform state |

**ADRs** (stored in `docs/adr/`, MADR format):

| File | Decision captured |
|------|-------------------|
| `ADR-001-state-backend.md` | S3 + DynamoDB as state backend and locking strategy |
| `ADR-002-terramate.md` | Terramate as orchestration tool (over Terragrunt and raw Makefile) |
| `ADR-003-network-topology.md` | Network CIDR allocation strategy and VPC structure |
| `ADR-004-identity-model.md` | Identity and access model across platforms |

**CI enforcement** (`.github/workflows/terraform-ci.yml`):

- Trigger: pull requests to `develop`
- Jobs: `terraform fmt --check` (all `.tf` files) and `terraform validate` (per stack)
- No AWS credentials required — all checks are static
- No `plan` or `apply` in CI

**Dependencies**: Phases 1–4 must be complete. CI enforcement is the last piece — it validates the state left by all previous phases.

**Success Criteria**:
- [ ] 3 runbooks exist under `docs/runbooks/`
- [ ] 4 ADRs exist under `docs/adr/` using MADR format
- [ ] `.github/workflows/terraform-ci.yml` exists and triggers on PRs to `develop`
- [ ] CI workflow runs `terraform fmt --check` and `terraform validate` without errors
- [ ] No AWS credentials are required by the CI workflow

---

### Phase 6 — Changelog and Wrap-up

**Objective**: Update `CHANGELOG.md` to document this documentation release for end users.

**Components**:
- Add an entry to `CHANGELOG.md` describing the documentation work from the perspective of an engineer who uses this repository (what they can now do that they could not before)

**Dependencies**: All previous phases must be complete.

**Success Criteria**:
- [ ] `CHANGELOG.md` has a new entry for this release
- [ ] The entry describes value from the engineer's perspective, not implementation details

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Diagram format | Mermaid embedded in README | GitHub renders natively; no tooling, no binary files, text-diffable in PRs |
| Module README generation | terraform-docs with `inject` mode | Keeps inputs/outputs/resources in sync with code; manual sections preserved |
| ADR format | MADR (Markdown ADR) | Lightweight, Markdown-native, no tooling required |
| Pre-commit hooks | Rejected | Breaks commit flow; tried and abandoned in previous projects |
| CI checks scope | `fmt --check` + `validate` only | Static checks only; no AWS credentials needed |
| Auto-generated diagrams | Rejected | Terramaid output is unreadable with complex stacks; manual diagrams control detail level |
| Documentation order | Bottom-up (stacks first, root last) | Root README is grounded in verified stack content |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Integrator stack data not obvious from code | Medium | Read `.tf` and `.tfvars` files before writing each README; if CIDR or server count is unclear, check `MEMORY.md` infrastructure IDs |
| terraform-docs generates wrong output if variable descriptions are missing | High | Phase 1 explicitly fixes `vpc` and `ecs_cluster` before terraform-docs runs |
| Stack count grows during implementation | Low | SPIKE confirmed 19 stacks as of 2026-03-13; any new stack added during the branch gets a README as part of the same PR |
| Mermaid diagrams become stale after stack changes | Medium | CI does not enforce diagram freshness; accepted trade-off over auto-generation complexity |

## Assumptions

- The 19 stacks and 26 modules listed in this plan reflect the repository state as of 2026-03-13
- All integrator stack data (VPC CIDRs, server counts) is readable from committed `.tf` and `.tfvars` files
- `terraform-docs` is available locally; if not, it must be installed before Phase 3
- GitHub Actions is the CI platform in use
- The `develop` branch is the PR target for all changes in this feature
