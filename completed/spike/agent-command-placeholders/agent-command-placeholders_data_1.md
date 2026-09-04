# Resolver table — placeholder class to concrete read-only command

Auxiliary to `SPIKE.md`, Finding 4. Each row cites the exact source read during
this spike; a row with no confirmed source is marked UNVERIFIED rather than
invented.

| Placeholder class | Resolves from | Command / mechanism | Source |
|---|---|---|---|
| ECS cluster/service name (`app`, `app-outbound`) | AWS tags (`Project=app`/`Project=app-outbound`, `Environment`) | `bash ~/.claude/skills/apps/scripts/apps-services.sh [--project ...] [--environment ...]` | `~/.claude/skills/apps/SKILL.md:42-61` |
| Integrator cluster/service name | AWS tags (`Project=integrator`, `Client`, `Environment`) | `bash ~/.claude/skills/integrators/scripts/*.sh` (skill discovers by tag, per its description) | `~/.claude/skills/integrators/SKILL.md:3` (description) |
| Onboarding / setup cluster/service name | AWS tags, `us-east-1` | `/onboarding`, `/setup` skill discovery scripts | `~/.claude/CLAUDE.md` § Available Commands (`/onboarding`, `/setup`) |
| Authenticator (Keycloak) instance name | AWS tags, per-instance region | `/authenticators` skill discovery script | `~/.claude/CLAUDE.md` § Available Commands (`/authenticators`) |
| Connection pooler cluster/service name | AWS tag `Project=connection-pooler`, `Environment` | `bash ~/.claude/skills/connection-poolers/scripts/connection-pooler-services.sh [--environment ...]` | `~/.claude/skills/connection-poolers/SKILL.md:38-40` |
| Standalone EC2 instance ID/name (MongoDB, pgbouncer, Windows, SQL Server, VPN) | AWS tags `Project`/`Client`/`Role` | `bash ~/.claude/skills/ec2-instances/scripts/ec2-instances.sh [--client ...] [--role ...] [--region ...]` | `~/.claude/skills/ec2-instances/SKILL.md:30-49` |
| Harvester task definition / schedule | AWS tag `Project=harvester`, `Client`, `Environment` | `/harvesters` skill discovery script (read-only) | `~/.claude/CLAUDE.md` § Available Commands (`/harvesters`) |
| Connection-pooler internal DB endpoint | Fixed DNS pattern, no lookup needed | `connection-pooler-{environment}.4shark.internal:6432` | `~/.claude/skills/connection-poolers/SKILL.md:22` |
| VPC ID, subnet ID, security group ID, DB cluster endpoint, KMS key ARN, any Terraform-managed value | Terraform state of the owning stack | `bash ~/.claude/scripts/terraform.sh <stack-dir> output [name]` or `bash ~/.claude/scripts/terraform.sh <stack-dir> state show <resource>` | `~/.claude/scripts/terraform.sh:85` (read-subcommand list includes `output`, `state`) |
| A named output not yet known (e.g. `pooler_admin_user`, `mongo_url_parameter_arn`, `secret_parameter_arns`) | The module's own `outputs.tf` | `grep -n 'output "' <module-path>/outputs.tf`, then `terraform.sh <stack-dir> output <name>` | `~/Projects/4Shark/terraform/modules/app/outputs.tf` (grep of `output "..."` lines) |
| AWS region for a project | Written convention, not a lookup | `app` → `us-east-1`; `app-outbound`, integrator, EC2 standalone (except pgbouncer) → `sa-east-1`; pgbouncer → `us-east-1` | `~/.claude/skills/apps/SKILL.md:8-9`; `~/.claude/skills/ec2-instances/SKILL.md:17` |
| AWS profile (read vs write) | Written convention | Default profile for any `describe-*`/`get-*`/`list-*` (auto-approved via `aws * get-*:*` etc.); `--profile engineer-elevated` only for a write, obtained via `/elevate-engineer-access` on an auth failure | `~/.claude/settings.json:756-766`; `~/.claude/CLAUDE.md` § AWS Policy |
| A 4Shark-managed secret already in SSM SecureString or Secrets Manager | The parameter/secret the owning Terraform module published | `aws ssm get-parameter --name <name> --with-decryption` or `aws secretsmanager get-secret-value --secret-id <arn>` — both match the `aws * get-*:*` wildcard, auto-approved under the default profile | `~/.claude/settings.json:756-758`; `~/Projects/4Shark/terraform/modules/connection_pooler/main.tf:318-342` (secrets published by ARN, never by value) |
| A 4Shark-owned third-party provider bootstrap credential (Datadog, MongoDB Atlas, Redis Cloud, GitHub token in `Terraform ENV`) | The shared "Terraform ENV" 1Password item | `op item get 'Terraform ENV' --vault 'Employee' --account=4shark.1password.com --format json` — **UNVERIFIED for direct agent use**: this exact invocation is only confirmed running inside a stack's own `.envrc` via `direnv`, not as a standalone agent-issued Bash command; `op item get` carries no standalone allow-list entry | `~/Projects/4Shark/terraform/app-demo-001/.envrc:10-18`; `~/.claude/settings.json` (grep for `elevate-engineer-access\|elevate-policy-arbiter` returns only the bundled elevation scripts, no bare `op` entry) |
| A per-engineer AWS MFA item (`AWS_MFA_ITEM`) | The engineer's own `settings.local.json`, never the shared config | Read by `/elevate-engineer-access`'s own script, not something the agent resolves ad hoc | `~/.claude/CLAUDE.md` § `/elevate-policy-arbiter-access` entry (contrasts the org-wide item, pinned in-script, against the per-person item, configured in `settings.local.json`) |
| A customer-supplied credential 4Shark does not hold (e.g. a password the client emailed) | Not resolvable by the agent at all | Ask the engineer to provide it; if it slipped into something already read, acknowledge it by category only, never print the value | `~/.claude/CLAUDE.md` § Layer 0 (`~/.claude/CLAUDE.md:1031`) |

## What this table does NOT cover

- Kubernetes/Docker-image-tag placeholders — out of scope; no repository in the
  catalog runs Kubernetes per `~/.claude/docs/PROJECTS-CATALOG.md` (not read in
  full during this spike; noted from the summary in CLAUDE.md's repository
  structure section, not independently verified here).
- Client-specific business values that have no infrastructure source at all
  (e.g. a client's internal employee ID format) — these are legitimately
  engineer-supplied and are not a placeholder-avoidance failure.
