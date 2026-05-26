# SPIKE — Terraform Repository Best Practices Analysis

**Conducted by:** Engineering Team
**Date:** 2026-02-28
**Status:** Research complete — pending decisions

---

## Goal

Answer the following questions to reduce uncertainty before investing in infrastructure improvements:

1. How does the current repository structure compare to community-recommended best practices?
2. Where are the highest-priority gaps that introduce risk, toil, or technical debt?
3. What specific improvements should be prioritized, and in what order?

This investigation is needed to establish a baseline and a roadmap for making the Terraform codebase more maintainable, secure, and team-scalable.

---

## Method

- Full codebase analysis: read all root modules, all 23 internal modules, providers, variables, outputs, locals, lock files, tfvars, Terramate configurations, .gitignore, CHANGELOG
- Web research: queried HashiCorp docs, AWS Prescriptive Guidance, Google Cloud Terraform best practices, Terramate docs, Spacelift blog, and the Terraform Best Practices community guide
- Gap analysis: compared findings against authoritative and community sources

---

## Evidence

### Part 1: Current Repository State

#### 1.1 Repository Structure

The repository is a **flat monorepo** with a directory-per-stack layout at the root. Each directory is an independent Terraform root module (a "stack"). Shared logic is centralized in a `modules/` directory.

**Root stacks (16 total):**

| Stack | Region | Description |
|---|---|---|
| `app-shared-001` | us-east-1 | Main production ECS environment (shared tier) |
| `app-atento-001` | us-east-1 | Atento client ECS environment |
| `app-beta-001` | us-east-1 | Beta ECS environment |
| `app-demo-001` | us-east-1 | Demo ECS environment |
| `auth-001` | sa-east-1 | Keycloak SSO (VPC, ECS, RDS) |
| `dns` | sa-east-1 | All public DNS (Cloudflare) + internal DNS (Route53) |
| `integrator-almaviva` | sa-east-1 | Client integrator environment |
| `integrator-aster-maquinas` | sa-east-1 | Client integrator environment |
| `integrator-atento-br` | sa-east-1 | Client integrator environment |
| `integrator-commcenter` | sa-east-1 | Client integrator environment |
| `integrator-maqnelson` | sa-east-1 | Client integrator environment |
| `integrator-redebrasil` | sa-east-1 | Client integrator environment |
| `setup` | us-east-1 | Setup application ECS environment |
| `shared-resources` | us-east-1 | Shared RDS parameter groups |
| `vpn` | sa-east-1 | Pritunl VPN (EC2) |
| `app-atento-br` | sa-east-1 | Atento BR application (references `app` module) |

**Internal modules (23 total):**

```
modules/
├── app/                    # Client-facing app VPC + networking
├── codedeploy/             # AWS CodeDeploy blue/green
├── ecr/                    # ECR repository
├── ecs_capacity/           # ECS capacity provider + ASG
├── ecs_cluster/            # ECS cluster
├── ecs_scheduled_task/     # ECS scheduled tasks
├── ecs_service/            # ECS service + task definition
├── eventbridge-scheduler/  # EventBridge scheduler
├── iam_deploy/             # IAM user + deploy policies
├── integrator/             # Client integrator VPC + networking
├── internal_alb/           # Internal ALB
├── lambda-ecs-autoscaling/ # Lambda for ECS autoscaling
├── lambda-iam/             # Lambda IAM roles
├── mongodb_atlas/          # MongoDB Atlas cluster + users
├── opensearch/             # OpenSearch domain
├── pritunl/                # Pritunl VPN EC2 instance
├── public_alb/             # Public ALB with Cloudflare support
├── rds_aurora_cluster/     # Aurora PostgreSQL cluster
├── rds_instance/           # RDS single instance
├── redis_cloud/            # Redis Cloud subscription
├── s3_bucket/              # S3 bucket
├── vpc/                    # Generic VPC (older, with examples/)
└── vpc_data/               # Data source for existing VPC
```

#### 1.2 Module Structure and Reusability

**Positive findings:**
- Modules follow the standard three-file convention: `main.tf`, `variables.tf`, `outputs.tf`
- Some modules also use `locals.tf`, `versions.tf` for provider pinning at module level
- Modules are well-decomposed: `app` module handles VPC, subnets, NAT, IGW as separate files (`main.tf`, `app.tf`, `dns.tf`, `peering.tf`, `routing.tf`, `security.tf`, `vpn.tf`)
- Variables have descriptions on all inputs (observed across all modules)
- `optional()` type constraints used in newer modules (e.g., `rds_aurora_cluster`, `mongodb_atlas`)

**Concerns:**
- Modules do not have `README.md` files (only `internal_alb`, `public_alb`, `vpc` have them — 3 out of 23)
- No module versioning — all are sourced via relative local paths (`../modules/X`), not tagged Git refs or a registry
- Some modules (e.g., `ecs_service`) use `type = any` for complex inputs, reducing type safety and IDE support
- The `vpc` module contains an `examples/` subdirectory (3 examples), but no other module has examples — inconsistent
- The `vpc` module is not used by any current root module (superseded by `vpc_data` + direct VPC resources) — it may be stale/dead code
- No `CHANGELOG.md` per module — changes are tracked only at the repository level

#### 1.3 State Management

**Backend:** AWS S3 (`4shark-terraform-state` bucket, `us-east-1`)

**State key pattern:** `<stack-name>/terraform.tfstate` (e.g., `app-shared-001/terraform.tfstate`)

**State isolation:** Each root module has its own state file — good blast-radius isolation.

**State locking:** Not explicitly configured. The S3 backend without a DynamoDB table does not enforce state locking. AWS S3 native state locking was introduced in Terraform 1.10 (using S3 conditional writes), but the current backend config does not include `use_lockfile = true`.

```hcl
# Current pattern (all root modules):
backend "s3" {
  bucket = "4shark-terraform-state"
  key    = "app-shared-001/terraform.tfstate"
  region = "us-east-1"
}
```

**Missing:** DynamoDB locking table or `use_lockfile = true` (Terraform >= 1.10). Without locking, concurrent applies can corrupt state.

**Positive:** `.terraform.lock.hcl` files are committed to version control — correct behavior that ensures reproducible provider versions across team members and CI.

#### 1.4 Environment Separation Strategy

The project does **not** use Terraform workspaces. Each environment is a separate directory with its own state file — this is the recommended approach for strong environment isolation.

**App environments** (`app-shared-001`, `app-beta-001`, `app-demo-001`, `app-atento-001`) are parameterized via `terraform.tfvars` files. The root `main.tf` logic is **identical** across these four environments (same 500+ line file duplicated with different variable values in `terraform.tfvars`). This is the most significant DRY violation in the repository.

**Integrator environments** (`integrator-*`) are minimal: each has a `main.tf` (2–30 lines) that calls the shared `modules/integrator` module and a `providers.tf`. This is a well-applied pattern.

#### 1.5 Provider Usage and Versioning

**Providers used:**

| Provider | Constraint | Lock Version (app-shared-001) |
|---|---|---|
| `hashicorp/aws` | `>= 5.0` | 6.33.0 |
| `mongodb/mongodbatlas` | `~> 2.0` | 2.7.0 |
| `RedisLabs/rediscloud` | `~> 2.0` | 2.11.0 |
| `cloudflare/cloudflare` | `~> 5.0` | 5.17.0 |

**Findings:**
- Terraform version constraint: `>= 1.0` — too permissive. Should be pinned closer to what is actually being used (observed providers reference Terraform >= 1.3 features like `optional()`)
- AWS provider: `>= 5.0` — overly broad. Best practice is to use pessimistic constraint (`~> 5.x`) or pin to a minor version range to avoid breaking changes from major bumps
- Some modules specify stricter constraints in `versions.tf` (`>= 1.3`), while root modules use `>= 1.0` — inconsistent
- All regions hardcoded in `providers.tf` (no variable-driven region) — acceptable for this pattern but worth noting

#### 1.6 Variable and Output Conventions

**Positive findings:**
- All variables have `description` attributes (verified across 6+ modules and root stacks)
- Input validation is used where applicable (e.g., `lambda_scheduler_state` with `contains()` check)
- Sensitive outputs marked with `sensitive = true` (e.g., OpenSearch master password)
- `locals.tf` is used for computed values and naming — good separation

**Concerns:**
- Some output files are named `output.tf` (singular) in root modules, while `outputs.tf` (plural) is used in modules — inconsistent convention
- Comments in some files are in Portuguese (e.g., `app-beta-001/main.tf` line 449: `# Cria recursos via Terraform`, `# Grace period: espera antes de verificar health do ALB`) — violates the English-only documentation policy
- `ecs_service/variables.tf` contains Portuguese comments in descriptions (e.g., `"Força novo deployment"`, `"Deployment controller type (ex.: CODE_DEPLOY). Null mantém padrão ECS."`, `"Habilita deployment circuit breaker"`)
- The `services` variable in root modules uses `type = any` — loses type safety for a complex, critical input

#### 1.7 Backend Configuration

The backend is hardcoded in `providers.tf` per root module. This requires manually specifying the bucket/region in each stack, creating repetition and a potential for typos.

There is no use of Terramate code generation to centralize backend configuration (a key Terramate feature). Each stack defines its own full backend block independently.

#### 1.8 CI/CD Integration

**No CI/CD pipeline found.** There is no `.github/` directory and no evidence of any CI/CD configuration (GitHub Actions, GitLab CI, etc.).

Terraform operations appear to be run locally by engineers. Terramate is installed but there is no evidence of it being used in any automated pipeline.

**Missing entirely:**
- Automated `terraform plan` on pull requests
- Automated `terraform apply` after merge
- Drift detection (scheduled plans)
- Security scanning (tflint, tfsec/Trivy, checkov)
- Pre-commit hooks
- `terraform fmt` enforcement

#### 1.9 Naming Conventions

**Root modules:** `<product>-<client/tier>-<seq>` (e.g., `app-shared-001`, `integrator-almaviva`)
**Resources within modules:** `this` for primary resource, descriptive names for secondary (e.g., `aws_ecs_cluster_capacity_providers.this`)
**Variables:** `snake_case` — consistent
**Locals:** `snake_case` — consistent
**Tags:** `PascalCase` keys (`Environment`, `Automation`, `Cluster`, `Role`, `Service`)

**Concerns:**
- Modules use different naming conventions: `ecs_cluster` (snake_case), `eventbridge-scheduler` (kebab-case), `lambda-ecs-autoscaling` (kebab-case), `public_alb` (snake_case) — inconsistent module directory naming
- Tag key casing is inconsistent: `Automation` and `ManagedBy` are used in the same repository (`ManagedBy` in `ecr` module, `Automation` in most other tags). AWS Cost Explorer treats tag keys as case-sensitive

#### 1.10 Hardcoded Values

Several hardcoded values were found that reduce portability and create maintenance risk:

**Hardcoded AWS account ID** (405749097490) appears in multiple places:
- `app-shared-001/main.tf`: IAM ARNs in `ecr_repository_arns`, `task_execution_role_arns`
- `app-beta-001/main.tf`: same pattern
- `app-shared-001/rds.tf`: KMS key ARN, monitoring role ARN

**Hardcoded certificate ARN:**
```hcl
# Same ARN hardcoded in app-shared-001, app-beta-001, app-demo-001, app-atento-001, setup/main.tf
certificate_arn = "arn:aws:acm:us-east-1:405749097490:certificate/6789893d-2c48-452a-90ea-3f2fc9ca8e35"
```

**Hardcoded MongoDB Atlas org ID:**
```hcl
# Same org_id hardcoded in app-shared-001/mongodb.tf and app-atento-001/mongodb.tf
org_id = "5bca5c89cf09a21bb6f53bc3"
```

**Hardcoded management VPC ID:**
```hcl
# Same VPC ID hardcoded in integrator-almaviva, integrator-atento-br, and vpn/main.tf
vpc_id = "vpc-0bdc76f3b391694dd"
```

**Hardcoded DHCP options ID and Route53 zone ID:**
```hcl
# Repeated across every integrator stack
internal_zone_id = "Z3PBW9DU61QULB"
dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
```

**Hardcoded AMI ID (Pritunl module caller):**
```hcl
ami_id = "ami-032ab7316dbf1ea74"  # No data source for latest AMI
```

**Hardcoded Lambda version:**
```hcl
# Hardcoded in app-shared-001/main.tf and app-beta-001/main.tf (same version both)
lambda_version = "0.7.1_736733c"
```

#### 1.11 Tagging Strategy

**Tags currently applied:**

```hcl
# Base tags (most environments)
tags = {
  Environment = var.environment
  Automation  = "terraform"
  Cluster     = "${var.environment}-cluster"
}

# Some resources add:
Role    = "web"
Service = "worker-system"

# ECR uses different key:
ManagedBy = "terraform"   # instead of Automation = "terraform"
```

**Missing tags:**
- No `Project`, `Team`, `Owner`, or `CostCenter` tags — essential for AWS cost allocation
- No AWS provider `default_tags` block — tags must be manually passed to every module call
- Inconsistent tag key for "managed by terraform": `Automation` vs `ManagedBy`
- The `dns` stack uses `Project = "dns"` and `ManagedBy = "terraform"` — different from all other stacks

#### 1.12 Terramate Usage

Terramate is present (`terramate.tm.hcl` at root, `stack.tm.hcl` per stack) but used only for **metadata definition**. The `after` dependency ordering is used in some stacks (e.g., `app-shared-001` declares `after = ["/shared-resources"]`).

**What Terramate is NOT being used for:**
- Code generation (backend configuration could be generated centrally)
- Global variables (shared values like account ID, management VPC ID could be globals)
- CI/CD change detection (the primary value proposition of Terramate for pipelines)
- Orchestration commands in CI/CD

Terramate is partially adopted but its DRY and orchestration capabilities are not being leveraged.

#### 1.13 IAM Pattern: Users vs Roles

Each application environment creates a long-lived IAM user (`aws_iam_user.deploy`) used for GitHub Actions deployments:

```hcl
resource "aws_iam_user" "deploy" {
  name = "app-shared-001"
}
```

This is an older pattern. Modern GitHub Actions best practice uses OIDC identity federation to assume an IAM role with temporary credentials, eliminating long-lived access keys entirely.

#### 1.14 Secret Management

Secrets referenced in ECS tasks use AWS Secrets Manager via `valueFrom` ARNs passed as variables to the `ecs_service` module. The Secrets Manager resource itself is managed in Terraform for `auth-001` (`aws_secretsmanager_secret.auth_001`).

**Gap:** MongoDB Atlas database user "passwords" (API keys) passed as map keys in `terraform.tfvars` are usernames, not passwords. Passwords appear to be managed outside Terraform (Atlas generates them). This is acceptable, but there is no centralized secret rotation strategy documented.

#### 1.15 .gitignore Analysis

The `.gitignore` is well-configured:
- `.terraform/` directories excluded
- `*.tfstate`, `*.tfstate.*` excluded
- `.terraform.lock.hcl` NOT excluded (correctly committed)
- `terraform.tfvars` NOT excluded (intentionally committed — contains environment-specific values but not secrets)
- `*.tfvars.json` excluded
- `.envrc` excluded (good — direnv files may contain credentials)
- No `*.pem` committed (private keys excluded)

---

### Part 2: Community Best Practices Research

#### 2.1 Project Structure

**Community consensus (HashiCorp, AWS Prescriptive Guidance, terraform-best-practices.com):**
- Directory-per-environment (flat monorepo) is the **recommended approach for large projects** — the team's pattern is aligned
- Modules should live in `modules/` — aligned
- Resource-type splitting (e.g., `rds.tf`, `s3.tf`, `redis.tf`) is encouraged — aligned
- Standard file names: `main.tf`, `variables.tf`, `outputs.tf`, `locals.tf`, `providers.tf` — mostly aligned (minor `output.tf` vs `outputs.tf` inconsistency)

Sources: [HashiCorp Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure), [AWS Prescriptive Guidance — Structure](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html), [terraform-best-practices.com](https://www.terraform-best-practices.com/code-structure)

#### 2.2 Module Design

**Community consensus:**
- Every module must have a `README.md` with usage examples, input/output tables
- Modules should be shallow and focused (one logical resource group per module)
- Avoid `type = any` — prefer explicit types for better documentation and validation
- Module versioning via Git tags or a private registry is strongly recommended over unversioned local paths
- If not using a registry, local paths are acceptable but modules must be co-located in the same repo (which they are)

Sources: [Google Cloud — Reusable Modules](https://docs.cloud.google.com/docs/terraform/best-practices/reusable-modules), [Masterpoint — Versioning Guide](https://masterpoint.io/blog/ultimate-terraform-versioning-guide/)

#### 2.3 State Management

**Community consensus:**
- One state file per environment/stack — aligned
- Remote backend with encryption — S3 is aligned
- **State locking is critical** — the current S3 backend without DynamoDB or `use_lockfile = true` (Terraform 1.10+) is a gap
- State files should never be committed to version control — aligned (`.gitignore` excludes them)

Sources: [AWS Prescriptive Guidance — Backend](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html), [Spacelift — State Management](https://spacelift.io/blog/terraform-state), [Scalr — State Best Practices](https://scalr.com/learning-center/terraform-state-files-best-practices/)

#### 2.4 Environment Management

**Community consensus:**
- Workspaces are discouraged for true environment isolation (they share a single backend config)
- Directory-based separation with separate state files is the correct pattern — aligned
- Terragrunt or Terramate can eliminate DRY violations across environment copies
- For the current DRY gap (identical `main.tf` across 4 app environments), the recommended solution is either:
  a. A higher-level module that the per-environment root calls (additional abstraction layer)
  b. Terramate code generation to produce per-environment files from a single template
  c. Terragrunt with `terragrunt.hcl` per environment

Sources: [Terramate — DRY](https://terramate.io/rethinking-iac/how-to-keep-your-terraform-code-dry-by-using-terramate/), [Terragrunt — Keep DRY](https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/)

#### 2.5 Code Quality

**Community consensus tools:**
- `terraform fmt` — enforced in CI (not currently configured)
- `terraform validate` — enforced in CI (not currently configured)
- `tflint` with AWS plugin — catches AWS-specific mistakes, deprecated resource arguments
- `tfsec` / `trivy` — security misconfiguration scanning
- `checkov` — policy enforcement and compliance
- Pre-commit hooks (via `pre-commit` framework) — run all checks before commit

Sources: [Spacelift — Scanning Tools](https://spacelift.io/blog/terraform-scanning-tools), [ezyinfra — Security Practices](https://ezyinfra.dev/blog/best-terraform-security-practices)

#### 2.6 Testing

**Community consensus:**
- Native `terraform test` framework (available since v1.6, mocks since v1.7) — not currently used
- Unit tests: `command = plan` runs for validating logic without real infrastructure
- Integration tests: `command = apply` creates and destroys real resources
- At minimum: `terraform validate` in CI + `terraform plan` review on PRs

Sources: [HashiCorp — Write Tests](https://developer.hashicorp.com/terraform/tutorials/configuration-language/test), [Google Cloud — Testing Best Practices](https://docs.cloud.google.com/docs/terraform/best-practices/testing)

#### 2.7 Security

**Community consensus:**
- IAM roles with temporary credentials (OIDC federation) preferred over long-lived IAM user access keys — current pattern uses IAM users
- Avoid hardcoding account IDs and ARNs — use `data "aws_caller_identity"` and locals
- Use `sensitive = true` on outputs that expose secrets — partially applied
- AWS provider `default_tags` to enforce consistent tagging without repetition
- Restrict S3 state bucket: enable versioning, MFA delete, and public access block

Sources: [AWS Prescriptive Guidance — Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html), [Sysdig — Terraform Security Best Practices](https://www.sysdig.com/blog/terraform-security-best-practices), [HashiCorp — 5 Foundational Security Practices](https://www.hashicorp.com/en/blog/terraform-security-5-foundational-practices)

#### 2.8 CI/CD

**Community consensus:**
- `terraform plan` should run automatically on every PR and output should be posted as a PR comment
- `terraform apply` should run automatically after merge to protected branch
- Drift detection should run on a schedule (daily/weekly `plan` with alerting)
- Terramate change detection can dramatically reduce CI time by only running changed stacks

Sources: [Terramate — Orchestration](https://terramate.io/docs/cli/orchestration), [Fatih Koc — Production Ready Terraform](https://fatihkoc.net/posts/production-ready-terraform/)

#### 2.9 Naming Conventions

**Community consensus:**
- Consistent `snake_case` for all Terraform identifiers (resources, variables, outputs, locals)
- Module directories: `snake_case` (HashiCorp standard) — the project mixes `snake_case` and `kebab-case`
- Standard file names: `main.tf`, `variables.tf`, `outputs.tf` (plural) — the project has `output.tf` in some root modules
- Resource names: `this` for the single primary resource in a module — aligned

Sources: [HashiCorp Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure), [Google Cloud — General Style](https://docs.cloud.google.com/docs/terraform/best-practices/general-style-structure)

#### 2.10 Version Pinning

**Community consensus:**
- Root modules: use pessimistic constraint (`~> 5.x`) or exact version for production stability
- Child modules: use `>=` constraints to allow callers to control the final version
- All root modules should specify `required_version` at the Terraform binary level
- Lock file (`.terraform.lock.hcl`) must always be committed — aligned

Sources: [HashiCorp — Lock and Upgrade Providers](https://developer.hashicorp.com/terraform/tutorials/configuration-language/provider-versioning), [Masterpoint — Versioning Guide](https://masterpoint.io/blog/ultimate-terraform-versioning-guide/)

#### 2.11 DRY Principles

**Community consensus:**
- Terramate code generation can eliminate backend boilerplate and shared variable repetition
- Shared constants (account IDs, VPC IDs, org IDs) should live in a single place (Terramate globals, a data module, or `shared-resources` state outputs consumed via `terraform_remote_state`)
- The repeated 500-line `main.tf` pattern across 4 environments is the most significant DRY violation; the `modules/app` approach used by `app-atento-br` is closer to the right pattern but not fully adopted

Sources: [Terramate — How to Keep Dry](https://terramate.io/rethinking-iac/how-to-keep-your-terraform-code-dry-by-using-terramate/), [Terragrunt — Keep Dry](https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/)

#### 2.12 Tagging Strategy

**Community consensus:**
- AWS `default_tags` in the provider block applies tags to all resources without repetition
- Mandatory tags for cost allocation: `Environment`, `Project`, `Team`, `ManagedBy`, `Owner`, `CostCenter`
- Tag key casing must be consistent — AWS Cost Explorer is case-sensitive
- Enforce tagging via CI/CD policy checks (Checkov, Sentinel, AWS Config)

Sources: [HashiCorp Well-Architected — Tag Resources](https://developer.hashicorp.com/well-architected-framework/optimize-systems/lifecycle-management/tag-cloud-resources), [CloudZero — AWS Tagging Strategy](https://www.cloudzero.com/blog/aws-tagging-strategy/), [TagOps — Tagging Best Practices 2026](https://tagops.cloud/blog-tagging-best-practices-2026.html)

---

## Conclusions

### Summary of Gaps vs Best Practices

| Area | Current State | Best Practice | Gap Severity |
|---|---|---|---|
| **State locking** | S3 without locking | DynamoDB or `use_lockfile = true` | **HIGH** — corruption risk |
| **CI/CD pipeline** | None — local only | Automated plan/apply/lint | **HIGH** — operational risk |
| **IAM authentication** | Long-lived IAM user keys | OIDC role federation (GitHub Actions) | **HIGH** — security risk |
| **DRY — app environments** | 4x ~500-line duplicate `main.tf` | Single module or Terramate codegen | **HIGH** — maintenance burden |
| **Hardcoded values** | Account IDs, VPC IDs, org IDs, AMI IDs, cert ARNs repeated in multiple files | `data` sources, locals, Terramate globals | **MEDIUM** — portability/maintenance |
| **Tagging strategy** | 2–3 tags, no `default_tags`, inconsistent keys | `default_tags` + 5–6 mandatory tags | **MEDIUM** — cost visibility |
| **Module documentation** | 3 of 23 modules have README | Every module needs README | **MEDIUM** — team onboarding |
| **Code quality tooling** | No linting/scanning | tflint + tfsec/trivy + checkov | **MEDIUM** — security/quality risk |
| **Language policy** | Portuguese comments in English-required files | English only in all code | **MEDIUM** — policy violation |
| **Provider version pinning** | `>= 5.0` (too broad) | `~> 5.x` pessimistic constraint | **LOW** — stability risk |
| **Terraform version constraint** | `>= 1.0` (too broad) | `>= 1.9, < 2.0` or similar | **LOW** — reproducibility |
| **Module naming convention** | Mixed `snake_case`/`kebab-case` | Consistent `snake_case` | **LOW** — cosmetic |
| **Output file naming** | `output.tf` (some) vs `outputs.tf` (others) | Consistent `outputs.tf` | **LOW** — cosmetic |
| **Testing** | None | `terraform validate` + native tests | **LOW** — future investment |
| **Terramate code generation** | Stacks defined but codegen not used | Generate backends + shared globals | **LOW** — nice to have |
| **Module versioning** | Local paths only | Git tags or private registry | **LOW** — future investment |
| **Stale modules** | `modules/vpc` unused | Remove or document | **LOW** — clutter |

### Key Findings

**Finding 1 — State locking is missing.**
The S3 backend for all 16 stacks has no state locking mechanism. Concurrent applies by two engineers — or a local run while a CI job runs — can corrupt state. This is a data integrity risk.

**Finding 2 — No CI/CD pipeline exists.**
All Terraform operations are manual. There are no automated checks on PRs, no automated applies, no drift detection. This creates the risk of untested configuration being applied to production and infrastructure drifting from the defined state without detection.

**Finding 3 — Long-lived IAM user credentials for deployment.**
Four environments use `aws_iam_user.deploy` for GitHub Actions. This is a known security anti-pattern. GitHub Actions supports AWS OIDC federation, which provides temporary credentials without storing long-lived secrets.

**Finding 4 — The four app environment root modules are nearly identical copies.**
`app-shared-001`, `app-atento-001`, `app-beta-001`, and `app-demo-001` each have a `main.tf` of approximately 500 lines that is structurally identical. Only `terraform.tfvars` differs. This means any change to the ECS architecture must be applied four times. The `integrator-*` stacks solve this correctly by calling the `modules/integrator` module — the same pattern should be applied to app environments. The `modules/app` module already exists and appears to solve this for the `app-atento-br` case, but the main app environments have not adopted it.

**Finding 5 — Repeated hardcoded constants create maintenance risk.**
The same AWS account ID (405749097490), ACM certificate ARN, MongoDB Atlas org ID, management VPC ID, DHCP options ID, and Route53 zone ID appear verbatim across multiple files. A change to any of these requires a multi-file search-and-replace. Terramate globals or `data` sources would centralize these.

**Finding 6 — Tagging is insufficient for cost allocation.**
The current tags (`Environment`, `Automation`, `Cluster`) do not allow cost attribution by team, project, or owner. The `ManagedBy` vs `Automation` inconsistency means resources cannot be reliably selected by tag. No AWS `default_tags` provider block is used, so tags are manually threaded through every module call.

**Finding 7 — Code quality and security tooling is absent.**
There is no `terraform fmt` enforcement, no linting (tflint), and no security scanning (tfsec, checkov, Trivy). The codebase is clean by inspection, but there is no automated safety net. Security misconfigurations could be introduced without any automated detection.

**Finding 8 — Portuguese comments violate the English-only documentation policy.**
Multiple files contain comments and variable descriptions in Portuguese. This is a policy violation and reduces accessibility for non-Portuguese speakers on the team.

---

## Next Steps

This investigation has produced sufficient findings to drive a prioritized implementation plan. The recommendations below are ordered by risk reduction impact.

**Recommended priority order:**

### Priority HIGH — Address within next sprint

1. **Enable state locking** — Add DynamoDB locking table (or migrate to Terraform 1.10+ with `use_lockfile = true`) for all 16 stacks. This is a low-effort, high-risk-reduction change.
   - Effort: Low (1 DynamoDB table + update all `providers.tf` backend blocks)

2. **Replace IAM user deploy credentials with OIDC** — Migrate GitHub Actions deployments from long-lived IAM user credentials to AWS OIDC identity federation. Remove `aws_iam_user.deploy` resources from all four app environments.
   - Effort: Medium (GitHub Actions workflow changes + new `aws_iam_openid_connect_provider` + IAM role per environment)

3. **Implement a basic CI/CD pipeline** — At minimum: `terraform fmt -check`, `terraform validate`, and `terraform plan` (with output posted to PR) for any changed stack. Terramate change detection should be used to avoid running all 16 stacks on every PR.
   - Effort: Medium (GitHub Actions workflows, Terramate integration)

### Priority MEDIUM — Address within next quarter

4. **Eliminate the 4x `main.tf` duplication** — Refactor `app-shared-001`, `app-atento-001`, `app-beta-001`, and `app-demo-001` to call a shared internal module (extending `modules/app` or creating a new `modules/ecs_environment` module). Environment-specific values live in `terraform.tfvars` only.
   - Effort: High (significant refactoring, requires careful state management to avoid destroying/recreating resources)
   - Risk: High — must be done with `moved` blocks and/or `import` blocks to preserve state

5. **Standardize tagging** — Add AWS provider `default_tags` block to all root module providers. Standardize on `ManagedBy = "terraform"` (drop `Automation`). Add `Project` and `Team` tags.
   - Effort: Low per stack, requires coordinated update across all 16 stacks

6. **Centralize repeated constants** — Extract hardcoded AWS account ID, ACM certificate ARN, MongoDB Atlas org ID, management VPC ID into Terramate globals (`globals.tm.hcl`) or a shared locals file. Use `data "aws_caller_identity"` for account ID.
   - Effort: Medium

7. **Add code quality tooling** — Set up `tflint` with AWS plugin, `tfsec` or `trivy`, and `terraform fmt -check` as pre-commit hooks and CI checks.
   - Effort: Low (configuration files + CI step addition)

8. **Translate Portuguese comments to English** — Fix all `description` values and inline comments that are in Portuguese. Files affected: `modules/ecs_service/variables.tf`, `app-beta-001/main.tf`, `app-shared-001/main.tf`, `setup/main.tf`.
   - Effort: Low

### Priority LOW — Address when capacity allows

9. **Tighten version constraints** — Update `required_version` from `>= 1.0` to `>= 1.9, < 2.0` (or pin to currently used version). Update AWS provider from `>= 5.0` to `~> 5.x`.
   - Effort: Low (edit `providers.tf` across all stacks)

10. **Write module READMEs** — Add `README.md` to the 20 modules that lack them. Use `terraform-docs` to auto-generate input/output tables.
    - Effort: Medium (tooling + content for 20 modules)

11. **Standardize module directory naming** — Rename `eventbridge-scheduler` and `lambda-ecs-autoscaling` from kebab-case to snake_case. Standardize output file from `output.tf` to `outputs.tf` in root modules.
    - Effort: Low (rename + update source references)

12. **Remove or document the stale `modules/vpc` module** — Either delete it (if truly unused) or add a README explaining why it exists alongside `modules/vpc_data`.
    - Effort: Very low

13. **Implement native Terraform tests** — Write `terraform test` files for key modules (especially `ecs_service`, `mongodb_atlas`, `rds_aurora_cluster`) using `command = plan` for unit-style tests.
    - Effort: High (ongoing investment)

**This investigation is complete.** The findings present a clear set of actionable improvements. The engineer needs to review the priorities and decide which items to move into a PLAN.md for implementation. The highest-impact first step is enabling state locking and implementing a basic CI/CD pipeline.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)

---

## Sources

- [HashiCorp — Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure)
- [HashiCorp — Lock and Upgrade Provider Versions](https://developer.hashicorp.com/terraform/tutorials/configuration-language/provider-versioning)
- [HashiCorp — Write Terraform Tests](https://developer.hashicorp.com/terraform/tutorials/configuration-language/test)
- [HashiCorp — Terraform Security: 5 Foundational Practices](https://www.hashicorp.com/en/blog/terraform-security-5-foundational-practices)
- [HashiCorp Well-Architected — Tag Cloud Resources](https://developer.hashicorp.com/well-architected-framework/optimize-systems/lifecycle-management/tag-cloud-resources)
- [AWS Prescriptive Guidance — Project Structure](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html)
- [AWS Prescriptive Guidance — Backend Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/backend.html)
- [AWS Prescriptive Guidance — Security](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html)
- [Google Cloud — General Style and Structure](https://docs.cloud.google.com/docs/terraform/best-practices/general-style-structure)
- [Google Cloud — Reusable Modules Best Practices](https://docs.cloud.google.com/docs/terraform/best-practices/reusable-modules)
- [Google Cloud — Testing Best Practices](https://docs.cloud.google.com/docs/terraform/best-practices/testing)
- [terraform-best-practices.com — Code Structure](https://www.terraform-best-practices.com/code-structure)
- [Terramate — How to Keep Terraform DRY](https://terramate.io/rethinking-iac/how-to-keep-your-terraform-code-dry-by-using-terramate/)
- [Terramate — Orchestration](https://terramate.io/docs/cli/orchestration)
- [Terramate — How to Structure and Size Stacks](https://terramate.io/rethinking-iac/how-to-structure-and-size-terraform-stacks/)
- [Terragrunt — Keep Your Terraform Code DRY](https://terragrunt.gruntwork.io/docs/features/keep-your-terraform-code-dry/)
- [Spacelift — Terraform State Management](https://spacelift.io/blog/terraform-state)
- [Spacelift — Terraform Scanning Tools](https://spacelift.io/blog/terraform-scanning-tools)
- [Scalr — State Files Best Practices](https://scalr.com/learning-center/terraform-state-files-best-practices/)
- [Masterpoint — Ultimate Terraform Versioning Guide](https://masterpoint.io/blog/ultimate-terraform-versioning-guide/)
- [CloudZero — AWS Tagging Strategy Guide](https://www.cloudzero.com/blog/aws-tagging-strategy/)
- [TagOps — AWS Tagging Best Practices 2026](https://tagops.cloud/blog-tagging-best-practices-2026.html)
- [Sysdig — Terraform Security Best Practices](https://www.sysdig.com/blog/terraform-security-best-practices)
