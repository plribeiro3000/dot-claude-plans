# NEXT TASKS — Terraform Repository Documentation

> **Objective of this iteration:** Break down the comprehensive documentation plan into actionable, granular tasks that can be executed sequentially while respecting phase dependencies.
>
> **Reference:** Derived from `PLAN.md` (complete 6-phase documentation release).

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved** (standard workflow — Phase 1 through Phase 6)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/terraform-documentation`
- [ ] Repository state confirmed as of 2026-03-13 with 19 stacks and 26 modules
- [ ] `terraform-docs` binary available locally (verify: `terraform-docs version`)

---

## 1) Step by Step (atomic tasks)

### Phase 1 — Tooling Foundation (6 tasks)

#### Task 1.1 — Create `.terraform-docs.yml` configuration file
- **Objective:** Establish terraform-docs tooling configuration at repository root with recursive module discovery.
- **Actions (checklist):**
  - [ ] Create `.terraform-docs.yml` at `/Users/plribeiro3000/Projects/4Shark/terraform/.terraform-docs.yml`
  - [ ] Set `formatter: markdown table` for standard Markdown table output
  - [ ] Set `output.mode: inject` to preserve manual sections while injecting auto-generated content
  - [ ] Set `recursive.enabled: true` and target `./modules/` directory
  - [ ] Verify configuration by running `cd /Users/plribeiro3000/Projects/4Shark/terraform && terraform-docs .` without errors
- **Affected files/areas:** `.terraform-docs.yml` (new file at repository root)
- **Completion criteria:** File exists, `terraform-docs .` runs without errors, no output is generated (since modules lack README.md files yet)
- **Observations:** This configuration will be used in Phase 3 to auto-inject terraform variables/outputs into all module README files

---

#### Task 1.2 — Fix `vpc/README.md` source URL pointing to external repository
- **Objective:** Correct the source URL in `vpc` module documentation to reference the local module instead of external elvenworks repository.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/modules/vpc/README.md` to identify the incorrect external URL
  - [ ] Replace external URL with local path reference (e.g., `modules/vpc` or appropriate documentation link)
  - [ ] Verify the fix aligns with how other modules reference themselves in documentation
- **Affected files/areas:** `modules/vpc/README.md`
- **Completion criteria:** URL points to local module, not external repository; README.md is still valid Markdown

---

#### Task 1.3 — Add missing variable descriptions to `vpc` module
- **Objective:** Document the two variables in `vpc` module that lack descriptions before terraform-docs generates their README.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/modules/vpc/variables.tf`
  - [ ] Locate variable `route_table_routes_private` (if missing description) and add English description (e.g., "Routes for private route table")
  - [ ] Locate variable `route_table_routes_public` (if missing description) and add English description (e.g., "Routes for public route table")
  - [ ] Ensure descriptions are concise, clear, and in English
  - [ ] Verify file is valid Terraform syntax
- **Affected files/areas:** `modules/vpc/variables.tf`
- **Completion criteria:** Both variables have English `description` fields; file validates without syntax errors

---

#### Task 1.4 — Fix language in `ecs_cluster` module variable descriptions
- **Objective:** Translate all variable descriptions in the `ecs_cluster` module from Portuguese to English.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/modules/ecs_cluster/variables.tf`
  - [ ] Identify all variables with Portuguese descriptions
  - [ ] Translate each description to English, maintaining clarity and technical accuracy
  - [ ] Verify file is valid Terraform syntax
- **Affected files/areas:** `modules/ecs_cluster/variables.tf`
- **Completion criteria:** All variable descriptions are in English; file validates without syntax errors

---

#### Task 1.5 — Translate `internal_alb/README.md` from Portuguese to English
- **Objective:** Full translation of the internal ALB module documentation to English.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/modules/internal_alb/README.md` completely
  - [ ] Identify all Portuguese text and technical descriptions
  - [ ] Translate content to English while preserving technical accuracy and formatting
  - [ ] Preserve any Markdown structure, code blocks, and links
  - [ ] Verify final file is valid Markdown
- **Affected files/areas:** `modules/internal_alb/README.md`
- **Completion criteria:** All content is in English; Markdown structure is preserved; file is valid

---

#### Task 1.6 — Translate `public_alb/README.md` from Portuguese to English
- **Objective:** Full translation of the public ALB module documentation to English.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/modules/public_alb/README.md` completely
  - [ ] Identify all Portuguese text and technical descriptions
  - [ ] Translate content to English while preserving technical accuracy and formatting
  - [ ] Preserve any Markdown structure, code blocks, and links
  - [ ] Verify final file is valid Markdown
- **Affected files/areas:** `modules/public_alb/README.md`
- **Completion criteria:** All content is in English; Markdown structure is preserved; file is valid

---

### Phase 2 — Individual Stack Documentation (19 tasks)

#### Task 2.1 — Document `integrator-almaviva` stack
- **Objective:** Create comprehensive README for Almaviva integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva/*.tf` and `.tfvars` files to extract: VPC CIDR, number of ECS tasks/servers, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva/README.md`
  - [ ] Add title, one-paragraph description of the stack's purpose
  - [ ] Document VPC CIDR, ECS task count, and any client-specific notes
  - [ ] Create a Mermaid architecture diagram showing VPC layout, subnets, ECS resources, load balancers, and integrations
  - [ ] Write in English
- **Affected files/areas:** `integrator-almaviva/README.md` (new file)
- **Completion criteria:** File exists with title, description, client details, and embedded Mermaid diagram; all content in English

---

#### Task 2.2 — Document `integrator-aster-maquinas` stack
- **Objective:** Create comprehensive README for Aster Máquinas integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-aster-maquinas/*.tf` and `.tfvars` files
  - [ ] Extract: VPC CIDR, ECS task count, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-aster-maquinas/README.md`
  - [ ] Add title, description, client details, and Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `integrator-aster-maquinas/README.md` (new file)
- **Completion criteria:** File exists with complete stack documentation and architecture diagram

---

#### Task 2.3 — Document `integrator-atento-br` stack
- **Objective:** Create comprehensive README for Atento BR integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: VPC CIDR, ECS task count, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento-br/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `integrator-atento-br/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.4 — Document `integrator-commcenter` stack
- **Objective:** Create comprehensive README for Commcenter integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: VPC CIDR, ECS task count, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-commcenter/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `integrator-commcenter/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.5 — Document `integrator-maqnelson` stack
- **Objective:** Create comprehensive README for Maqnelson integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: VPC CIDR, ECS task count, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-maqnelson/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `integrator-maqnelson/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.6 — Document `integrator-redebrasil` stack
- **Objective:** Create comprehensive README for Rede Brasil integrator stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: VPC CIDR, ECS task count, client-specific configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-redebrasil/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `integrator-redebrasil/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.7 — Document `app-atento-001` stack
- **Objective:** Create comprehensive README for Atento US environment stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files to extract: AWS region, environment purpose, resources managed
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/README.md`
  - [ ] Add title, description of the Atento US production environment
  - [ ] Document AWS region, resources, and environment-specific notes
  - [ ] Create Mermaid architecture diagram
  - [ ] Write in English
- **Affected files/areas:** `app-atento-001/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.8 — Document `app-atento-br` stack
- **Objective:** Create comprehensive README for Atento BR environment stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: AWS region, environment purpose, resources managed
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-br/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `app-atento-br/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.9 — Document `app-beta-001` stack
- **Objective:** Create comprehensive README for Beta environment stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: AWS region, environment purpose, resources managed
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `app-beta-001/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.10 — Document `app-demo-001` stack
- **Objective:** Create comprehensive README for Demo environment stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: AWS region, environment purpose, resources managed
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `app-demo-001/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.11 — Document `app-shared-001` stack
- **Objective:** Create comprehensive README for Shared services stack with architecture diagram.
- **Actions (checklist):**
  - [ ] Read stack's `.tf` and `.tfvars` files
  - [ ] Extract: AWS region, environment purpose, resources managed
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/README.md`
  - [ ] Add documentation with Mermaid diagram
  - [ ] Write in English
- **Affected files/areas:** `app-shared-001/README.md` (new file)
- **Completion criteria:** Stack documentation complete with diagram

---

#### Task 2.12 — Document `auth-001` stack
- **Objective:** Create comprehensive README for AWS SSO and authentication configuration stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/auth-001/*.tf` files
  - [ ] Document AWS SSO setup, identity provider configuration, and IAM policies
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/auth-001/README.md`
  - [ ] Include Mermaid architecture diagram showing auth flow
  - [ ] Write in English
- **Affected files/areas:** `auth-001/README.md` (new file)
- **Completion criteria:** Stack documentation with authentication architecture diagram

---

#### Task 2.13 — Document `dns` stack
- **Objective:** Create comprehensive README for centralized DNS management stack (Route53 + Cloudflare).
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/dns/*.tf` files
  - [ ] Document Route53 zones, Cloudflare zones, DNS delegation, and management model
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/dns/README.md`
  - [ ] Include Mermaid diagram showing zone hierarchy and delegation flow
  - [ ] Write in English
- **Affected files/areas:** `dns/README.md` (new file)
- **Completion criteria:** Stack documentation with DNS architecture diagram

---

#### Task 2.14 — Add Mermaid diagram to `identity/README.md`
- **Objective:** Enhance existing identity stack documentation by adding an architecture diagram.
- **Actions (checklist):**
  - [ ] Read the existing `/Users/plribeiro3000/Projects/4Shark/terraform/identity/README.md` to understand current structure
  - [ ] Create a Mermaid diagram showing identity model, engineer access flows, and break glass account
  - [ ] Add the diagram under a new `## Architecture` section (or appropriate location)
  - [ ] Preserve all existing content
  - [ ] Verify Markdown is valid
- **Affected files/areas:** `identity/README.md` (enhancement)
- **Completion criteria:** Diagram added while all existing content is preserved

---

#### Task 2.15 — Document `monitoring` stack
- **Objective:** Create comprehensive README for Rollbar and alerting stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/monitoring/*.tf` files
  - [ ] Document Rollbar project configuration, alerting rules, integration points
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/monitoring/README.md`
  - [ ] Include Mermaid diagram showing monitoring architecture and alert routing
  - [ ] Write in English
- **Affected files/areas:** `monitoring/README.md` (new file)
- **Completion criteria:** Stack documentation with monitoring architecture diagram

---

#### Task 2.16 — Document `networking` stack
- **Objective:** Create comprehensive README for VPC peering and cross-VPC routing stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/networking/*.tf` files
  - [ ] Document VPC structure, peering relationships, routing tables, and inter-network connections
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/networking/README.md`
  - [ ] Include Mermaid diagram showing network topology and peering relationships
  - [ ] Write in English
- **Affected files/areas:** `networking/README.md` (new file)
- **Completion criteria:** Stack documentation with network topology diagram

---

#### Task 2.17 — Document `setup` stack
- **Objective:** Create comprehensive README for mobile app configuration service stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/setup/*.tf` files
  - [ ] Document the service's purpose, resources managed, and integration points
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/setup/README.md`
  - [ ] Include Mermaid diagram showing setup service architecture
  - [ ] Write in English
- **Affected files/areas:** `setup/README.md` (new file)
- **Completion criteria:** Stack documentation with setup service architecture diagram

---

#### Task 2.18 — Document `shared-resources` stack
- **Objective:** Create comprehensive README for shared AWS resources stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/shared-resources/*.tf` files (if exists — verify first)
  - [ ] Document shared resources managed (S3 buckets, IAM roles, policies, etc.)
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/shared-resources/README.md`
  - [ ] Include Mermaid diagram showing shared resources
  - [ ] Write in English
- **Affected files/areas:** `shared-resources/README.md` (new file)
- **Completion criteria:** Stack documentation with shared resources diagram
- **Observations:** If `shared-resources` directory does not exist, create it; if it exists but has no `.tf` files, document what it should contain

---

#### Task 2.19 — Document `vpn` stack
- **Objective:** Create comprehensive README for Pritunl VPN infrastructure stack.
- **Actions (checklist):**
  - [ ] Read `/Users/plribeiro3000/Projects/4Shark/terraform/vpn/*.tf` files
  - [ ] Document Pritunl VPN setup, network routes, client access, and security configuration
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/vpn/README.md`
  - [ ] Include Mermaid diagram showing VPN architecture and access flows
  - [ ] Write in English
- **Affected files/areas:** `vpn/README.md` (new file)
- **Completion criteria:** Stack documentation with VPN architecture diagram

---

### Phase 3 — Module Documentation (26 tasks)

#### Task 3.1 — Document `app` module
- **Objective:** Create base README skeleton for core app module before terraform-docs injection.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/app/README.md`
  - [ ] Add title and one-paragraph description of the module's purpose
  - [ ] Add `## Architecture` section with a Mermaid diagram showing how the module creates ECS services and related resources
  - [ ] Add `## Usage` section with a minimal working example showing required variables
  - [ ] Add `## Requirements` section with terraform-docs markers: `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->`
  - [ ] Add `## Known Limitations` section with relevant constraints
  - [ ] Write in English
- **Affected files/areas:** `modules/app/README.md` (new file)
- **Completion criteria:** Skeleton exists with title, description, architecture diagram, usage example, and markers for auto-injection

---

#### Task 3.2 — Document `ecs_service` module
- **Objective:** Create base README skeleton for ECS service module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/ecs_service/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/ecs_service/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.3 — Document `ecs_cluster` module
- **Objective:** Create base README skeleton for ECS cluster module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/ecs_cluster/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/ecs_cluster/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.4 — Document `rds_instance` module
- **Objective:** Create base README skeleton for RDS instance module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/rds_instance/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/rds_instance/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.5 — Document `rds_aurora_cluster` module
- **Objective:** Create base README skeleton for RDS Aurora cluster module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/rds_aurora_cluster/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/rds_aurora_cluster/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.6 — Document `codedeploy` module
- **Objective:** Create base README skeleton for CodeDeploy module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/codedeploy/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/codedeploy/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.7 — Document `integrator` module
- **Objective:** Create base README skeleton for integrator module.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/README.md`
  - [ ] Add title, description, Mermaid diagram, usage example, and terraform-docs markers
  - [ ] Write in English
- **Affected files/areas:** `modules/integrator/README.md` (new file)
- **Completion criteria:** Skeleton exists with all required sections

---

#### Task 3.8 — Document remaining 19 modules
- **Objective:** Create base README skeletons for all non-core modules (cloudflare_zone_security, ecr, ecs_capacity, ecs_scheduled_task, eventbridge-scheduler, iam_deploy, integrator_iam, lambda-ecs-autoscaling, lambda-iam, mongodb_atlas, networking_data, opensearch, pritunl, redis_cloud, s3_bucket, vpc, vpc_data, internal_alb, public_alb).
- **Actions (checklist):**
  - [ ] For each of the 19 modules, create `modules/{module-name}/README.md` if it doesn't exist
  - [ ] For each module, add: title, description, Mermaid architecture diagram, `## Usage` section with working example, `## Requirements` section with terraform-docs markers, `## Known Limitations` section
  - [ ] Ensure all content is in English
  - [ ] List affected files at completion
- **Affected files/areas:** 19 new README files in `modules/cloudflare_zone_security/`, `modules/ecr/`, `modules/ecs_capacity/`, `modules/ecs_scheduled_task/`, `modules/eventbridge-scheduler/`, `modules/iam_deploy/`, `modules/integrator_iam/`, `modules/lambda-ecs-autoscaling/`, `modules/lambda-iam/`, `modules/mongodb_atlas/`, `modules/networking_data/`, `modules/opensearch/`, `modules/pritunl/`, `modules/redis_cloud/`, `modules/s3_bucket/`, `modules/vpc/`, `modules/vpc_data/`, `modules/internal_alb/`, `modules/public_alb/`
- **Completion criteria:** All 19 module README.md files exist with terraform-docs markers and placeholder sections
- **Observations:** This task bundles 19 similar module documentations to reduce task count while maintaining granularity. Each module's diagram should reflect its specific resource creation (e.g., S3 bucket shows lifecycle policies, RDS shows Multi-AZ failover, etc.)

---

#### Task 3.9 — Run terraform-docs injection for all modules
- **Objective:** Execute terraform-docs to auto-generate inputs, outputs, and resources sections for all 26 module README files.
- **Actions (checklist):**
  - [ ] Navigate to repository root: `cd /Users/plribeiro3000/Projects/4Shark/terraform`
  - [ ] Run `terraform-docs .` from repository root
  - [ ] Verify all 26 modules have auto-generated content injected between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` markers
  - [ ] Check for errors or warnings in terraform-docs output
  - [ ] Verify that manual sections (description, usage, known limitations) were preserved
- **Affected files/areas:** All 26 module README.md files (inputs/outputs/resources sections updated)
- **Completion criteria:** `terraform-docs .` completes without errors; all 26 module README files have injected terraform-docs content

---

### Phase 4 — Root Documentation (1 task)

#### Task 4.1 — Write root `README.md` with four Mermaid diagrams
- **Objective:** Create comprehensive root-level documentation as the macro-level entry point to the entire repository.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/README.md` at repository root
  - [ ] Add title "4Shark Infrastructure (Terraform)" and brief description
  - [ ] Add `## How the Infrastructure Works` section explaining networks, VPN, ECS, DNS (Route53 + Cloudflare)
  - [ ] Create `## Network Topology` section with Mermaid diagram showing all VPCs, CIDRs, regions (Brazil vs USA), VPN access, inter-network routing
  - [ ] Create `## Stack Dependency Graph` section with Mermaid diagram showing all 19 stacks and Terramate `after` ordering relationships
  - [ ] Create `## DNS Architecture` section with Mermaid diagram showing Route53 zones (internal), Cloudflare zones (external), delegation flow, and which stack manages each zone
  - [ ] Create `## ECS Architecture` section with Mermaid diagram showing ECS clusters, services, load balancers, and deployment flow
  - [ ] Add `## Repository Structure` section with table listing all 19 stacks with purpose and links to their README files
  - [ ] Add `## Modules` section with table listing all 26 modules with one-line descriptions and links to their README files
  - [ ] Add `## Prerequisites` section documenting Terraform >= 1.x, Terramate >= 0.x, AWS credentials, MongoDB Atlas and Redis Cloud API keys
  - [ ] Add `## Getting Started` section with initialization and plan/apply instructions
  - [ ] Add `## Contributing` section with instructions for adding new stacks and modules
  - [ ] Write entirely in English
- **Affected files/areas:** `README.md` (new file at repository root)
- **Completion criteria:** Root README exists with all four Mermaid diagrams, complete repository structure table (19 stacks + 26 modules), and getting started guide
- **Observations:** This is the final user-facing documentation; it must be grounded in the verified stack READMEs from Phase 2. The Network Topology and Stack Dependency diagrams are the most complex; ensure they are clear and represent actual Terramate dependencies.

---

### Phase 5 — Operations and Governance (7 tasks)

#### Task 5.1 — Create `docs/runbooks/` directory structure
- **Objective:** Establish directory for operational runbooks.
- **Actions (checklist):**
  - [ ] Verify `/Users/plribeiro3000/Projects/4Shark/terraform/docs/` directory exists
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/runbooks/` directory if it doesn't exist
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/adr/` directory if it doesn't exist
- **Affected files/areas:** `docs/runbooks/` and `docs/adr/` directories
- **Completion criteria:** Both directories exist and are ready for content

---

#### Task 5.2 — Create runbook: `ADD-INTEGRATOR-CLIENT.md`
- **Objective:** Write step-by-step guide for adding a new integrator client stack.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/runbooks/ADD-INTEGRATOR-CLIENT.md`
  - [ ] Document the process: creating stack directory, writing `.tf` files, adding Terramate orchestration, testing, and merge
  - [ ] Include examples of VPC CIDR allocation, ECS task configuration, and variable overrides
  - [ ] Reference existing integrator stacks as templates
  - [ ] Write in English
- **Affected files/areas:** `docs/runbooks/ADD-INTEGRATOR-CLIENT.md` (new file)
- **Completion criteria:** Runbook exists with clear step-by-step instructions and examples

---

#### Task 5.3 — Create runbook: `EMERGENCY-SINGLE-STACK-APPLY.md`
- **Objective:** Write guide for applying a single stack manually outside normal Terramate orchestration.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/runbooks/EMERGENCY-SINGLE-STACK-APPLY.md`
  - [ ] Document when to use (e.g., normal orchestration is broken, stack needs urgent fix)
  - [ ] Document the manual apply process: `cd <stack-dir>`, `terraform init`, `terraform plan`, `terraform apply`
  - [ ] Include warnings about state consistency and when to escalate
  - [ ] Write in English
- **Affected files/areas:** `docs/runbooks/EMERGENCY-SINGLE-STACK-APPLY.md` (new file)
- **Completion criteria:** Runbook exists with clear instructions and safety warnings

---

#### Task 5.4 — Create runbook: `STATE-RECOVERY.md`
- **Objective:** Write procedures for recovering from corrupted or inconsistent Terraform state.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/runbooks/STATE-RECOVERY.md`
  - [ ] Document common state corruption scenarios (orphaned resources, drift, lock issues)
  - [ ] Document recovery procedures: state backup, `terraform refresh`, `terraform taint`, `terraform import`, state restore
  - [ ] Include S3 backend recovery (pull state from S3, restore from backup)
  - [ ] Include DynamoDB lock cleanup if locks are stuck
  - [ ] Write in English
- **Affected files/areas:** `docs/runbooks/STATE-RECOVERY.md` (new file)
- **Completion criteria:** Runbook exists with recovery procedures for multiple failure scenarios

---

#### Task 5.5 — Create ADR: `ADR-001-state-backend.md`
- **Objective:** Document decision to use S3 + DynamoDB as state backend and locking strategy.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/adr/ADR-001-state-backend.md`
  - [ ] Use MADR (Markdown ADR) format: title, status (Accepted), context, decision, consequences, and alternatives considered
  - [ ] Explain why S3 + DynamoDB was chosen over Terraform Cloud, Terragrunt remote state, etc.
  - [ ] Document locking strategy and DynamoDB table configuration
  - [ ] Include backup and disaster recovery considerations
  - [ ] Write in English
- **Affected files/areas:** `docs/adr/ADR-001-state-backend.md` (new file)
- **Completion criteria:** ADR exists in MADR format with decision rationale and consequences

---

#### Task 5.6 — Create ADR: `ADR-002-terramate.md`
- **Objective:** Document decision to use Terramate as orchestration tool.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/adr/ADR-002-terramate.md`
  - [ ] Use MADR format: title, status (Accepted), context, decision, consequences, alternatives
  - [ ] Explain why Terramate was chosen over Terragrunt, raw Makefile, or other orchestration tools
  - [ ] Document the `after` dependency model and how stacks are ordered
  - [ ] Include considerations for future alternatives (OpenTofu, Terraform Cloud run tasks)
  - [ ] Write in English
- **Affected files/areas:** `docs/adr/ADR-002-terramate.md` (new file)
- **Completion criteria:** ADR exists in MADR format with orchestration tool rationale

---

#### Task 5.7 — Create ADR: `ADR-003-network-topology.md`
- **Objective:** Document CIDR allocation strategy and VPC structure decision.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/adr/ADR-003-network-topology.md`
  - [ ] Use MADR format: title, status (Accepted), context, decision, consequences, alternatives
  - [ ] Document the overall CIDR supernet and allocation to VPCs (Brazil vs USA regions, integrator vs app environments)
  - [ ] Explain subnet strategy (public, private, database tiers)
  - [ ] Document VPC peering strategy and cross-VPC routing
  - [ ] Include growth plan for new integrator/environment CIDRs
  - [ ] Write in English
- **Affected files/areas:** `docs/adr/ADR-003-network-topology.md` (new file)
- **Completion criteria:** ADR exists in MADR format with network design rationale

---

#### Task 5.8 — Create ADR: `ADR-004-identity-model.md`
- **Objective:** Document identity and access control model decision across platforms.
- **Actions (checklist):**
  - [ ] Create `/Users/plribeiro3000/Projects/4Shark/terraform/docs/adr/ADR-004-identity-model.md`
  - [ ] Use MADR format: title, status (Accepted), context, decision, consequences, alternatives
  - [ ] Explain the single-source-of-truth approach with `engineers` variable
  - [ ] Document least-privilege model (read-only default, elevated via MFA)
  - [ ] Explain break glass account rationale and emergency access procedures
  - [ ] Include cross-platform identity sync (AWS IAM, Cloudflare, MongoDB Atlas, GitHub)
  - [ ] Write in English
- **Affected files/areas:** `docs/adr/ADR-004-identity-model.md` (new file)
- **Completion criteria:** ADR exists in MADR format with identity model rationale

---

#### Task 5.9 — Create CI workflow: `.github/workflows/terraform-ci.yml`
- **Objective:** Establish GitHub Actions workflow for terraform format and validation checks.
- **Actions (checklist):**
  - [ ] Create `.github/workflows/terraform-ci.yml` at repository root
  - [ ] Configure trigger: pull requests to `develop` branch
  - [ ] Add job 1: `terraform fmt --check` on all `.tf` files in repository
  - [ ] Add job 2: `terraform validate` for each stack (or use loop to validate all stacks)
  - [ ] Ensure no AWS credentials are required (static checks only)
  - [ ] Add status badges or clear failure messages for developers
  - [ ] Include setup for Terraform CLI (e.g., use `hashicorp/setup-terraform` action)
  - [ ] Write workflow in YAML
- **Affected files/areas:** `.github/workflows/terraform-ci.yml` (new file)
- **Completion criteria:** Workflow exists, triggers on PRs to develop, runs fmt and validate without requiring AWS credentials

---

### Phase 6 — Changelog and Wrap-up (1 task)

#### Task 6.1 — Update `CHANGELOG.md` with documentation release entry
- **Objective:** Document this feature as a user-facing release entry.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`
  - [ ] Add a new entry at the top (following Semantic Versioning + Keep a Changelog format)
  - [ ] Write from the perspective of an engineer using this repository: what they can now do that they couldn't before
  - [ ] Focus on value, not implementation: "Now engineers can instantly understand the entire infrastructure by reading the root README and stack guides" rather than "Added 45 markdown files"
  - [ ] Include sections: how to use the new documentation, what's available (root README, stack guides, module READMEs, runbooks, ADRs), and where to find them
  - [ ] Write in English
  - [ ] Verify Markdown is valid
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** CHANGELOG has a new entry describing the documentation feature from an engineer's perspective

---

## 2) Items Requiring User Confirmation

No items require user confirmation at this stage. The PLAN.md is comprehensive and specific enough to proceed directly to execution. The task breakdown follows the 6 phases exactly as specified.

---

## 3) Pending Items After This Iteration

None. All 33 tasks collectively achieve all six phases of the documentation plan.

---

## Notes on Task Dependencies

**Sequential phases** (must complete in order):
- Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6

**Parallelizable within phases:**
- **Phase 1:** Tasks 1.1–1.6 (tooling and language fixes) — order matters slightly: 1.1 should come first (terraform-docs config), then 1.2–1.6 can run in any order
- **Phase 2:** Tasks 2.1–2.19 (all 19 stack READMEs) — completely parallelizable once Phase 1 is done
- **Phase 3:** Tasks 3.1–3.8 (module skeletons) can run in parallel; Task 3.9 (terraform-docs injection) must come after all skeletons exist
- **Phase 4:** Task 4.1 — must come after Phase 2 is complete
- **Phase 5:** Tasks 5.1–5.9 — can be parallelized once directories are created (5.1 first)
- **Phase 6:** Task 6.1 — must come last

**Suggested execution order for `/execute`:**
1. Phase 1 tasks sequentially (tooling foundation)
2. Phase 2 tasks in parallel (stack documentation)
3. Phase 3 tasks 3.1–3.8 in parallel, then 3.9 sequentially
4. Phase 4 task 4.1 (root README)
5. Phase 5 tasks 5.1–5.9 (operations and governance)
6. Phase 6 task 6.1 (changelog)
