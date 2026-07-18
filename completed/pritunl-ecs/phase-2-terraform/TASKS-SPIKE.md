# TASKS-SPIKE — Pritunl VPN Migration Phase 2: Terraform Infrastructure

> Reference: `~/.claude/plans/active/pritunl-ecs/PLAN.md` (engineer-approved), Phase 2 specification
> 
> **Purpose:** Research and surface decomposition options for Phase 2 (Terraform infrastructure), each PR option with its dependencies, open decisions, and implementation patterns.

## Phase 2 scope (from PLAN.md)

Provision the new infrastructure alongside (not replacing) the running combined VM:

- Production Pritunl ECS instance (privileged + host networking) and associated task definition
- Dedicated MongoDB VM (separate from Pritunl container)
- `-staging` Pritunl ECS instance (normally at zero capacity)
- Security groups (MongoDB isolation, Pritunl ports)
- IAM roles (carry forward route-advertisement permissions)
- Two per-target ECR repositories (`vpn` and `vpn-staging`)
- Identity-stack governance updates (add `pritunl` to `local.hubflow_repositories`)
- **Do NOT yet touch** the existing `aws_eip`/`aws_eip_association` (will reassociate in Phase 3)

## Blocking spikes (must resolve before Phase 2 PRs proceed)

### SPIKE-2: MongoDB VM Ansible role placement

**Decision needed:** Extract Mongo-only tasks into a new independent role, or keep in existing role with inventory-group conditional?

**Two options:**

#### Option 2A: New independent role (recommended by PLAN.md)
- Create `ansible/roles/4shark.mongodb-pritunl/` (or equivalent name)
- Copy/extract MongoDB tasks from `ansible/roles/4shark.pritunl/tasks/main.yml:32-79`
- Reduce existing role to only Pritunl/dnsmasq/fail2ban tasks (or retire it entirely after Phase 4)
- Add Mongo VM to `ansible/inventory/` as a new group (e.g., `[pritunl_mongodb]`)
- Create/extend playbook (e.g., `ansible/playbooks/provision-pritunl-mongo.yml`)

**Pros:** Clear separation, reusable for other Mongo uses, easier to decouple Pritunl version bumps from Mongo patching
**Cons:** More files, new playbook maintenance

#### Option 2B: Conditional in existing role
- Keep `ansible/roles/4shark.pritunl/` intact
- Wrap Mongo tasks with `when: inventory_hostname in groups['pritunl_mongodb']`
- Single playbook targets both Pritunl host and Mongo VM
- Existing role grows slightly but stays cohesive

**Pros:** Fewer new files, existing role structure unchanged
**Cons:** Role becomes multi-purpose, harder to deprecate Mongo tasks after Phase 4

**Open question for engineer:** Which approach aligns with 4Shark's Ansible practices?

**Pattern reference:**
- `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — MongoDB tasks to extract (apt-repo, install, config, systemd enable, handlers)
- `ansible/playbooks/provision-pritunl.yml` — current single-playbook shape

---

### SPIKE-3: Dedicated MongoDB security group mechanism

**Decision needed:** How to restrict Mongo VM's ingress to ONLY the Pritunl instance?

**Two options:**

#### Option 3A: Security-group-to-security-group scoping (new pattern)
```hcl
# Pritunl instance has its own security group
resource "aws_security_group" "pritunl_ecs" {
  # ... ports 14720, 14721, web UI ports
}

# Mongo VM security group permits ONLY from Pritunl's SG
resource "aws_vpc_security_group_ingress_rule" "mongodb_from_pritunl" {
  security_group_id              = aws_security_group.mongodb.id
  from_port                      = 27017
  to_port                        = 27017
  ip_protocol                    = "tcp"
  referenced_security_group_id   = aws_security_group.pritunl_ecs.id
}
```

**Pros:** Dynamic, survives Pritunl instance replacement without IP updates, clearest intent, per `aws_vpc_security_group_ingress_rule` Terraform docs
**Cons:** New pattern (no existing 4Shark precedent), requires `referenced_security_group_id` verification, adds SG-level coupling

#### Option 3B: Narrowed CIDR to Pritunl instance's private IP (existing convention)
```hcl
# Pritunl ECS instance gets a fixed private IP from subnet CIDR
# Mongo VM security group permits from that IP
resource "aws_vpc_security_group_ingress_rule" "mongodb_from_pritunl" {
  security_group_id  = aws_security_group.mongodb.id
  from_port          = 27017
  to_port            = 27017
  ip_protocol        = "tcp"
  cidr_ipv4          = "10.255.X.Y/32"  # Pritunl instance's private IP
}
```

**Pros:** Matches existing convention (`terraform/auth-001/security_groups.tf:11-23,41-47`), no new Terraform pattern
**Cons:** Brittle across instance replacement (requires manual IP tracking or a data source), requires private IP allocation strategy (fixed vs dynamic)

**Open question for engineer:** Prefer new SG-to-SG pattern, or stick with CIDR convention?

**If SG-to-SG:** Must verify `referenced_security_group_id` exists in current AWS provider version and draft PoC rule.
**If CIDR:** Must document Pritunl instance's private IP allocation (fixed subnet allocation, or dynamic tracking via Terraform data source).

**Pattern reference:**
- `terraform/auth-001/security_groups.tf:11-23,41-47` — existing CIDR-scoped convention (RDS example)
- [registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) — `referenced_security_group_id` argument

---

### SPIKE-4: Staging Mongo database strategy

**Decision needed:** Where does the `-staging` Pritunl instance get its MongoDB?

**Three options:**

#### Option 4A: Separate staging Mongo VM (full isolation)
- Provision a second `aws_instance` for MongoDB (staging-only)
- Identical to production Mongo VM, separate host
- Ansible provisioning via same role (Option 2A or 2B)

**Pros:** Complete isolation, staging Mongo can be torn down after test window, no production data risk
**Cons:** Doubles Mongo VM footprint, adds second instance to manage/patch, two Mongo VMs to monitor

#### Option 4B: Separate database on production Mongo VM (shared host)
- Production Mongo VM runs BOTH `pritunl` database and `pritunl-staging` database
- Staging Pritunl instance connects to production Mongo VM with `mongodb_uri: "mongodb://mongo-vm-private-ip:27017/pritunl-staging"`
- Same security group (both services from same SG)

**Pros:** Single Mongo VM (smaller infra footprint), staging seeding from prod Mongo is straightforward
**Cons:** Shared host means staging Mongo failover impacts production, easier to accidentally pollute prod data, requires database-level isolation discipline

#### Option 4C: Ephemeral seeding strategy (staging-only temp)
- Staging Mongo runs only during bring-up window (manual `docker-compose`, or an ECS task started on-demand)
- Seeded with a fixed test dataset (empty, or a clone of prod state, or synthetic test users)
- Stopped when staging Pritunl scales to zero

**Pros:** Zero persistent cost for staging Mongo, freshest test data on each bring-up
**Cons:** Requires seed-data strategy (who generates it, how often updated), Mongo VM gone between test windows (re-provisioning time), more infrastructure-as-code complexity

**Open question for engineer:** Which strategy balances cost, isolation, and operational simplicity?

**Pattern reference:**
- `terraform/auth-001/auth_001_staging.tf:1-194` — Fargate staging pattern (separate RDS database within same RDS instance, desired_count=0 for service)

---

### SPIKE-5: Staging instance's public entry point during test window

**Decision needed:** How does `-staging` Pritunl instance reach the public for client validation?

**Three options:**

#### Option 5A: Dedicated (possibly ephemeral) Elastic IP for staging
```hcl
resource "aws_eip" "pritunl_staging" {
  instance = aws_instance.pritunl_staging.id
  domain   = "vpc"
  tags     = { Name = "pritunl-staging-eip" }
  # Released when instance shuts down
}
```

**Pros:** Stable IP for staging window, familiar pattern (mirrors production EIP), can be shared across test cycles
**Cons:** EIP carries an idle cost when staging is at zero, requires managed release/allocation lifecycle

#### Option 5B: Default (non-elastic) public IP on instance ENI
- Staging instance gets a transient public IP from the account pool (free, but changes on stop/start)
- Notify team of the changing IP via Slack/email when staging comes up

**Pros:** Zero cost during idle, minimal infrastructure
**Cons:** Changing IP is annoying for testers, requires manual communication on each bring-up

#### Option 5C: Private-only validation (no public entry)
- Staging Pritunl validates via Systems Manager Session Manager (SSM) shell or private VPN management interface
- No public IP needed
- Test clients connect over an existing VPN profile (pointing at prod IP), then test against staging Pritunl over private addressing

**Pros:** Zero public exposure, no EIP cost, leverages existing infra
**Cons:** Validation workflow is non-standard (requires SSM access / VPN tunnel), testers must know the private path, complex for ad-hoc validation

**Open question for engineer:** Which path for staging public entry? Cost vs convenience trade-off?

**Pattern reference:**
- `terraform/modules/pritunl/main.tf:32-39` — production EIP pattern (for production only)

---

### SPIKE-6: EC2 host bring-up mechanism for `-staging` confirmation

**Decision needed:** Confirm the mechanism to bring staging EC2 host up/down is direct stop/start, not ASG managed scaling.

**PLAN.md finding:** ASG-backed capacity provider with `min_size=0` is **ruled out** because AWS docs state: *"When Amazon ECS scales out from 0 instances, it automatically launches 2 instances."* For a single-instance staging Pritunl (decision 2 of PLAN.md: one dedicated instance per environment, no HA within an environment), launching 2 instances on scale-from-zero violates the framing and wastes cost.

**Chosen approach:** Direct stop/start of the EC2 instance itself (separate from ECS service `desired_count=0`).

**Open question for engineer:** Confirm this mechanism is acceptable, or surface an alternative?

**Two-step procedure if confirmed:**
1. Scale ECS service to `desired_count=0`: `aws ecs update-service --desired-count 0` (via `~/.claude/scripts/ecs-scale.sh`)
2. Stop EC2 instance: `~/.claude/scripts/stop-instance.sh`

To bring back up:
1. Start EC2 instance: `~/.claude/scripts/start-instance.sh`
2. Scale ECS service to `desired_count=1`: `aws ecs update-service --desired-count 1`

**Pattern reference:**
- `~/.claude/scripts/ecs-scale.sh:1-63` — existing ECS service scaling wrapper
- `~/.claude/scripts/start-instance.sh`, `stop-instance.sh` — existing EC2 control scripts
- `~/.claude/skills/authenticators/SKILL.md:17,70-90` — existing staging instance bring-up/down workflow for authenticators (Fargate model, but the skill's language is the precedent the engineer references)

---

### SPIKE-7: `ecs_service` module extension vs. bespoke task definition

**Decision needed:** How to provide privileged + host-networking task definition for Pritunl ECS instances?

**Current module limitation:** `terraform/modules/ecs_service/main.tf:14` — EC2 launch type only gets `network_mode = "bridge"`, and no `privileged` variable is exposed in the container definitions block.

**Two options:**

#### Option 7A: Extend `terraform/modules/ecs_service` with new variables
```hcl
# modules/ecs_service/variables.tf (new)
variable "privileged" {
  type    = bool
  default = false
}

variable "network_mode_override" {
  type    = string
  default = null  # null means use the standard bridge/awsvpc logic
}

# modules/ecs_service/main.tf (modified)
network_mode = var.network_mode_override != null ? var.network_mode_override : (var.launch_type == "FARGATE" ? "awsvpc" : "bridge")

# container_definitions (modified) — add privileged key
privileged = var.privileged
```

**Pros:** Reusable for future privileged workloads, keeps Pritunl task definition in the module, consistent with 4Shark's module-based approach
**Cons:** Module extension carries risk of breaking downstream consumers (requires careful backward-compatibility testing), adds complexity to a generic module for a single use case

#### Option 7B: Bespoke `aws_ecs_task_definition` for Pritunl (mirroring old `terraform/modules/pritunl` as bespoke)
- Write Pritunl-specific task definition directly in `terraform/vpn/` (or `terraform/pritunl/` if created)
- No module reuse, full control over Pritunl's container_definitions

**Pros:** No risk to other ECS workloads, clear and simple, precedent in the codebase (current `terraform/modules/pritunl` is bespoke, not generic)
**Cons:** Task definition logic not reused, less standardized

**Open question for engineer:** Prefer module extension (generic, reusable) or bespoke definition (simple, isolated)?

**If extending module:** Must verify no downstream consumers are impacted (search for `ecs_service` calls and test backward compatibility).
**If bespoke:** Draft both production and staging task definitions with all required keys (privileged, network_mode, stopTimeout, environment variables, log configuration, etc.).

**Pattern reference:**
- `terraform/modules/ecs_service/main.tf:1-165` — current module (lines 14, 21-54 are the key areas needing change)
- `terraform/modules/connection_pooler/main.tf:250-290` — example of an ECS task definition within a module (Fargate, not EC2 privileged, but shows the shape)

---

## Decomposition options for Phase 2 PRs

With spikes resolved, Phase 2 can be decomposed into PRs in multiple ways. Engineer chooses the trade-off.

### Option A: Grouped by component type + dependency order (recommended if spikes resolve cleanly)

**Pros:** Clear logical grouping, each PR has a single responsibility, easier to review per-component
**Cons:** More PRs (6-7), requires careful sequencing, external ordering complexity

**PR breakdown:**

1. **PR 2.1 — ECR repositories** (`vpn`, `vpn-staging`)
   - Dependencies: Phase 1 complete (images must exist in ECR to validate)
   - Files: `terraform/vpn/ecr.tf` (new or added to existing stack)
   - Open decision: None (straightforward, copies `terraform/auth-001/ecr.tf:1-29` pattern exactly)
   - Acceptance: Both ECR repositories exist, images can be pushed

2. **PR 2.2 — Identity governance** (add `pritunl` to hubflow lists)
   - Dependencies: None (can merge anytime)
   - Files: `terraform/identity/github_repositories.tf` — add `pritunl` to `local.hubflow_repositories` + (once CI ships check) `local.hubflow_repositories_with_min_age_check`
   - Open decision: None (straightforward governance)
   - Acceptance: terraform plan clean, `pritunl` listed correctly in both locals

3. **PR 2.3 — MongoDB infrastructure** (Mongo VM + security group)
   - Dependencies: Resolves SPIKE-2 (Ansible role placement), SPIKE-3 (SG mechanism)
   - Files: `terraform/vpn/mongodb.tf` (new; `aws_instance` for Mongo VM, security group, IAM if needed), `ansible/...` (Mongo role — depends on SPIKE-2 decision)
   - Open decisions: SPIKE-2, SPIKE-3 (placement, SG mechanism)
   - Acceptance: Mongo VM instance runs, MongoDB listening on 27017, ingress restricted per SPIKE-3 decision

4. **PR 2.4 — Production Pritunl ECS** (task def, launch template, instance, service, security group)
   - Dependencies: ECR repos (PR 2.1), resolves SPIKE-7 (task def approach)
   - Files: `terraform/vpn/ecs.tf` or `terraform/vpn/pritunl_ecs.tf` (task definition, service, launch template modification, security group), possibly `terraform/modules/ecs_service/` if SPIKE-7 chooses extension
   - Open decision: SPIKE-7 (module vs bespoke task def)
   - Acceptance: Production ECS service running, container reaches Mongo VM, ports 14720/14721 open, logs flowing to CloudWatch

5. **PR 2.5 — Staging Pritunl ECS** (task def, launch template, instance, service, desired_count=0)
   - Dependencies: Production Pritunl (PR 2.4), resolves SPIKE-4 (Mongo strategy), SPIKE-5 (public entry), SPIKE-6 (host bring-up)
   - Files: `terraform/vpn/ecs_staging.tf` (or appended to `ecs.tf`), Mongo VM updates if SPIKE-4 chooses separate staging Mongo (PR 2.3 extended)
   - Open decisions: SPIKE-4 (Mongo strategy), SPIKE-5 (public entry), SPIKE-6 (host mechanism)
   - Acceptance: Staging ECS service provisions at desired_count=0, scales up/down cleanly, connects to appropriate Mongo database

---

### Option B: Grouped by environment (production layer, then staging layer)

**Pros:** Clearer separation of concerns, production stabilizes before staging is added, less parallel work
**Cons:** More sequential (longer wall-clock time), staging must wait for production

**PR breakdown:**

1. **PR 2.1 — Foundation** (ECR + governance + production Mongo VM)
   - Dependencies: Phase 1 complete
   - Files: ECR repos, governance updates, Mongo VM, Mongo SG
   - Open decisions: SPIKE-2, SPIKE-3
   - Acceptance: ECR available, governance updated, Mongo VM running

2. **PR 2.2 — Production Pritunl ECS** (task def, launch template, instance, service)
   - Dependencies: Foundation (PR 2.1)
   - Files: Production ECS resources, Pritunl security group
   - Open decisions: SPIKE-7
   - Acceptance: Production container running, connected to Mongo

3. **PR 2.3 — Staging Pritunl ECS** (staging Mongo if separate, task def, launch template, instance, service)
   - Dependencies: Production (PR 2.2)
   - Files: Staging ECS resources, staging Mongo VM if SPIKE-4 chooses separate
   - Open decisions: SPIKE-4, SPIKE-5, SPIKE-6
   - Acceptance: Staging container scales up/down, isolated from production

---

### Option C: Single large PR (all Phase 2 at once)

**Pros:** Single review/merge, enforces all dependencies at once, simplest tracking
**Cons:** Large diff, harder to review, riskier rollback, all-or-nothing merge

**PR breakdown:** One PR with all Terraform files from Option A.

---

## Dependency graph (all phase 2 work)

```
Phase 1 (pritunl repo)
    ↓
SPIKE-1, SPIKE-7, SPIKE-8 (resolved in Phase 1 research)
    ↓
SPIKE-2 (Mongo Ansible role) ─── SPIKE-3 (Mongo SG) ─→ PR 2.3 (Mongo VM)
                                                         ↓
    PR 2.1 (ECR) ────→ PR 2.4 (Prod ECS) ────→ PR 2.5 (Staging ECS)
                           ↑
    PR 2.2 (Governance) ───┘

SPIKE-4 (Staging Mongo) ───→ PR 2.3 or PR 2.5 (depending on strategy)
SPIKE-5 (Staging public entry) ───→ PR 2.5
SPIKE-6 (Staging host mechanism) ───→ PR 2.5
```

**Critical path (fastest):**
1. Resolve SPIKE-2, SPIKE-3, SPIKE-7
2. PR 2.1 (ECR) — can be parallel with Mongo decision
3. PR 2.2 (Governance) — can be parallel with anything
4. PR 2.3 (Mongo) — waits for SPIKE-2, SPIKE-3
5. PR 2.4 (Prod ECS) — waits for PR 2.1 + SPIKE-7
6. Resolve SPIKE-4, SPIKE-5, SPIKE-6
7. PR 2.5 (Staging) — waits for PR 2.4 + staging spikes

---

## Open implementation questions for each PR

### PR 2.1 — ECR repositories

No open decisions. Straightforward copy of `terraform/auth-001/ecr.tf:1-29` pattern.

**Pattern reference:**
- `terraform/auth-001/ecr.tf:1-29` — two-ECR-repository shape

```hcl
resource "aws_ecr_repository" "vpn" {
  name                 = "vpn"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  tags = local.tags
}

resource "aws_ecr_repository" "vpn_staging" {
  name = "vpn-staging"
  # ... identical config
}
```

---

### PR 2.2 — Identity governance

No open decisions. Straightforward list addition.

**Pattern reference:**
- `terraform/identity/github_repositories.tf:60-75` — `local.hubflow_repositories` where `pritunl` is added (after `keycloak`)
- `terraform/identity/github_repositories.tf:81-91` — `local.hubflow_repositories_with_min_age_check` where `pritunl` is added (once CI check ships)

---

### PR 2.3 — MongoDB VM infrastructure

**Open decisions:** SPIKE-2 (Ansible role placement), SPIKE-3 (SG mechanism)

**Terraform files:**
- `terraform/vpn/mongodb.tf` (new) — Mongo VM instance, security group, IAM role (if needed)
- Optionally extends `terraform/vpn/iam.tf` if Mongo VM needs its own instance role for cloudwatch logs

**Mongo VM structure:**

```hcl
# Launch template / user_data for Mongo VM
# Identical to Pritunl's in structure, but runs Ansible provisioning instead of ECS

resource "aws_instance" "mongodb" {
  ami           = data.aws_ami.ubuntu_24.id
  instance_type = "t3a.small"  # sizing TBD
  subnet_id     = var.private_subnet_id
  security_groups = [aws_security_group.mongodb.id]
  iam_instance_profile = aws_iam_instance_profile.mongodb.name

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # Install Ansible + bootstrap for role execution
    # Run ansible-playbook targeting this host's group
    EOF
  )

  tags = {
    Name = "pritunl-mongodb"
  }
}

# MongoDB security group
resource "aws_security_group" "mongodb" {
  name   = "pritunl-mongodb"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# Ingress from Pritunl (mechanism per SPIKE-3 decision)
# Option 3A: SG-to-SG (referenced_security_group_id)
# Option 3B: CIDR to Pritunl instance private IP
```

**Ansible provisioning (decision per SPIKE-2):**
- Option 2A: New `ansible/roles/4shark.mongodb-pritunl/` role
- Option 2B: Conditional in existing `4shark.pritunl` role
- Creates `mongod.conf` from template, enables/starts `mongod` systemd unit

**Acceptance criteria:**
- [ ] Mongo VM instance running (check via `aws ec2 describe-instances`)
- [ ] `mongod` process listening on 27017
- [ ] Ingress from Pritunl security group ONLY (test with `mongo-cli` from Pritunl host; test denial from outside)
- [ ] CloudWatch logs flowing

**Pattern reference:**
- `terraform/modules/pritunl/main.tf:1-44` — bare EC2 instance shape (Pritunl uses this, Mongo follows similarly)
- `terraform/modules/ecs_capacity/main.tf:1-51` — launch template / user_data pattern
- `ansible/roles/4shark.pritunl/tasks/main.yml:32-79` — Mongo tasks to be extracted/retargeted
- `terraform/auth-001/security_groups.tf:11-23,41-47` — security group ingress pattern (CIDR-based)

---

### PR 2.4 — Production Pritunl ECS infrastructure

**Open decisions:** SPIKE-7 (module extension vs bespoke task def)

**Terraform files:**
- `terraform/vpn/ecs.tf` or `terraform/vpn/pritunl_ecs.tf` (new) — production task definition, launch template, ECS service, Pritunl security group
- Optionally `terraform/modules/ecs_service/` if SPIKE-7 chooses module extension

**Pritunl security group:**

```hcl
resource "aws_security_group" "pritunl_ecs" {
  name   = "pritunl-ecs"
  vpc_id = var.vpc_id

  # Inbound
  ingress {
    from_port   = 14720
    to_port     = 14720
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 14721
    to_port     = 14721
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Web UI ports (443 typical, exact port TBD)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Egress (all for now)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}
```

**ECS task definition (structure, exact container_definitions per SPIKE-7 decision):**

```hcl
resource "aws_ecs_task_definition" "pritunl" {
  family       = "pritunl"
  network_mode = "host"  # ← required for host networking
  requires_compatibilities = ["EC2"]

  container_definitions = jsonencode([
    {
      name              = "pritunl"
      image             = aws_ecr_repository.vpn.repository_url + ":latest"
      essential         = true
      privileged        = true  # ← required
      stopTimeout       = 20    # ← 20-second grace for SIGTERM
      
      environment = [
        {
          name  = "MONGODB_URI"
          value = "mongodb://${aws_instance.mongodb.private_ip}:27017/pritunl"
        }
        # ... other env vars (DNS resolver, rate limiting, etc.)
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pritunl.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}
```

**ECS launch template (extended with WireGuard + /dev/net/tun bootstrap):**

```hcl
resource "aws_launch_template" "pritunl" {
  name_prefix = "pritunl-"
  image_id    = data.aws_ami.ecs_optimized.id
  instance_type = "t3a.small"  # sizing TBD; current VM is t3a.micro, may need larger

  network_interfaces {
    associate_public_ip_address = false  # public IP via secondary ENI or EIP
    security_groups             = [aws_security_group.pritunl_ecs.id]
  }

  iam_instance_profile {
    name = aws_iam_instance_profile.pritunl.name
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    # Register with ECS cluster
    echo ECS_CLUSTER=${aws_ecs_cluster.pritunl.name} >> /etc/ecs/ecs.config

    # Install WireGuard kernel module
    apt-get update
    apt-get install -y wireguard

    # Ensure /dev/net/tun exists
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200

    # Base OS hardening (as per PLAN.md's "host-only prep")
    # ... TBD by implementation

    systemctl restart ecs
    EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = { Name = "pritunl-ecs-instance" }
  }
}
```

**ECS service:**

```hcl
resource "aws_ecs_service" "pritunl" {
  name            = "pritunl"
  cluster         = aws_ecs_cluster.pritunl.id
  task_definition = aws_ecs_task_definition.pritunl.arn
  desired_count   = 1
  launch_type     = "EC2"

  tags = local.tags
}
```

**Acceptance criteria:**
- [ ] ECS service running with desired_count=1
- [ ] Container image pulled from ECR and started
- [ ] Container reaches "RUNNING" state, not crashing
- [ ] VPN ports 14720/14721 listening (test with `nc -u -l -p PORT`)
- [ ] Pritunl connects to Mongo VM (check logs in CloudWatch)
- [ ] IAM role permits route advertisement (if needed for OpenVPN client routes)
- [ ] CloudWatch logs streaming

**Pattern reference:**
- `terraform/modules/ecs_capacity/main.tf:1-51` — launch template with user_data, ECS cluster registration
- `terraform/auth-001/ecs.tf:1-100+` — ECS task definition, service, cluster, security group shape
- `terraform/modules/pritunl/main.tf:32-39` — IAM role for route advertisement (carry forward)
- `terraform/modules/ecs_service/main.tf:14-54` — container_definitions shape (to extend or replace per SPIKE-7)

---

### PR 2.5 — Staging Pritunl ECS infrastructure

**Open decisions:** SPIKE-4 (Mongo strategy), SPIKE-5 (public entry), SPIKE-6 (host mechanism)

**Terraform files:**
- `terraform/vpn/ecs_staging.tf` or appended to `ecs.tf` (new) — staging task definition, launch template, ECS service, staging Mongo VM (if SPIKE-4 chooses separate), staging public IP/EIP
- Potentially extends `terraform/vpn/mongodb.tf` if SPIKE-4 chooses shared prod Mongo or separate staging Mongo

**ECS task definition for staging:**
- Identical to production (PR 2.4), except `network_mode`, `environment` may differ
- If SPIKE-4 chooses separate Mongo: `MONGODB_URI` points to staging Mongo VM's private IP
- If SPIKE-4 chooses shared prod: `MONGODB_URI` points to production Mongo VM + staging database name (e.g., `pritunl-staging`)

**ECS service for staging:**

```hcl
resource "aws_ecs_service" "pritunl_staging" {
  name            = "pritunl-staging"
  cluster         = aws_ecs_cluster.pritunl.id  # shared cluster with production
  task_definition = aws_ecs_task_definition.pritunl_staging.arn
  desired_count   = 0  # normally at zero

  tags = local.tags
}
```

**Launch template for staging:**
- Identical to production (PR 2.4), just different name/tags
- Same WireGuard + /dev/net/tun bootstrap

**Staging Mongo VM (if SPIKE-4 chooses separate):**
- Identical to production Mongo VM (PR 2.3), just different name/database
- OR: ephemeral task (TBD if SPIKE-4 chooses this path)

**Public entry for staging (per SPIKE-5 decision):**

Option 5A (dedicated EIP):
```hcl
resource "aws_eip" "pritunl_staging" {
  instance = aws_instance.pritunl_staging.id
  domain   = "vpc"
  tags     = { Name = "pritunl-staging-eip" }
}
```

Option 5B (default public IP):
- No additional Terraform; instance gets default public IP from subnet (if public subnet)

Option 5C (private-only):
- No public IP resource; validation happens over private addressing

**Acceptance criteria:**
- [ ] Staging ECS service provisions at desired_count=0 (no running tasks)
- [ ] Staging EC2 instance STOPPED (not running)
- [ ] Manually scale up via `ecs-scale.sh` + `start-instance.sh` (TBD per SPIKE-6 mechanism)
- [ ] Container reaches RUNNING state, connects to appropriate Mongo database
- [ ] Public entry works (IP accessible, ports 14720/14721 reachable) per SPIKE-5 decision
- [ ] Manually scale down via service update + `stop-instance.sh`
- [ ] Instance stopped, no running tasks, minimal cost

**Pattern reference:**
- `terraform/auth-001/auth_001_staging.tf:1-194` — Fargate staging service at desired_count=0, shared cluster with prod, separate database
- PR 2.4 (production ECS) — base pattern to mirror/adapt
- `~/.claude/scripts/start-instance.sh`, `stop-instance.sh` — host control wrappers (referenced in scaling flow, not terraform)
- `~/.claude/scripts/ecs-scale.sh:1-63` — service scaling wrapper

---

## Cross-PR concerns

### Network connectivity validation

Each PR should validate the network path it introduces:
- **PR 2.3:** Mongo VM listening, SG permits correct source
- **PR 2.4:** Pritunl ↔ Mongo VM connectivity (logs should show successful MongoDB connection)
- **PR 2.5:** Staging Pritunl ↔ Staging or Production Mongo (depends on SPIKE-4)

### Rollback strategy

- **PR 2.1 (ECR):** Can be destroyed anytime (images regenerated on next Phase 1 PR)
- **PR 2.2 (Governance):** Can be reverted, but affects Renovate/CI (low risk)
- **PR 2.3 (Mongo):** Destroying leaves production Pritunl with no database (high risk) — keep until Phase 4
- **PR 2.4 (Prod ECS):** Once active, must not be destroyed (production VPN) — keep until Phase 3 EIP flip confirmed
- **PR 2.5 (Staging):** Low risk, can be destroyed anytime (staging-only)

### IAM and logging

- All tasks need IAM roles with CloudWatch Logs permissions
- Pritunl task needs potential route-advertisement permissions (carry from current VM)
- Mongo VM needs CloudWatch Logs agent (if systemd-based; TBD by Ansible role)

---

## Summary: Recommended approach

**Decomposition:** Option A (component-based, 5-6 PRs) with spikes resolved upfront

**Spike resolution order (parallel where possible):**
1. SPIKE-1 (Renovate regex) — blocks Phase 1 finalization
2. SPIKE-2, SPIKE-3 in parallel — block PR 2.3
3. SPIKE-4, SPIKE-5, SPIKE-6, SPIKE-7 in parallel — block PR 2.4, 2.5
4. SPIKE-8 — blocks cutover (Phase 3), not Phase 2

**PR sequence after spikes resolve:**
1. PR 2.1 (ECR) — quick, unblocks 2.4
2. PR 2.2 (Governance) — quick, can be anytime
3. PR 2.3 (Mongo) — medium, requires Ansible coordination
4. PR 2.4 (Prod ECS) — complex, most critical
5. PR 2.5 (Staging) — depends on 2.4

**Risk mitigation:**
- Each PR includes `terraform plan` validation
- Mongo connectivity validated before Pritunl ECS starts
- Staging fully isolated from production (separate instance, DB per SPIKE-4)
- Old VM untouched until Phase 3 (rollback path preserved)

---

## Sources

- `~/.claude/plans/active/pritunl-ecs/PLAN.md` — Phase 2 specification, decisions, residual items
- `terraform/auth-001/ecr.tf:1-29` — two-ECR-repository pattern
- `terraform/auth-001/ecs.tf:1-100+` — ECS task definition, service, security group
- `terraform/auth-001/auth_001_staging.tf:1-194` — Fargate staging-instance pattern (desired_count=0, shared cluster)
- `terraform/auth-001/security_groups.tf:1-53` — security group convention (CIDR-scoped)
- `terraform/modules/ecs_capacity/main.tf:1-102` — launch template, user_data, ASG (host-prep vehicle)
- `terraform/modules/ecs_service/main.tf:1-165` — generic ECS service module (network_mode, container_definitions shape)
- `terraform/modules/pritunl/main.tf:1-44` — current bare EC2 instance + EIP shape
- `terraform/modules/pritunl/iam.tf:29-49` — route-advertisement IAM permissions (carry forward)
- `terraform/identity/github_repositories.tf:60-91` — governance lists where `pritunl` is added
- `ansible/roles/4shark.pritunl/tasks/main.yml:1-264` — full current provisioning (Mongo tasks: 32-79)
- `~/.claude/scripts/ecs-scale.sh:1-63` — ECS service scaling wrapper
- `~/.claude/scripts/start-instance.sh`, `stop-instance.sh` — EC2 host control wrappers
- `~/.claude/skills/authenticators/SKILL.md:1-90` — existing staging instance bring-up/down workflow
- [docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/cluster-auto-scaling.html) — "When Amazon ECS scales out from 0 instances, it automatically launches 2 instances"
- [registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) — `referenced_security_group_id` (UNVERIFIED per Citation Discipline — needs confirmation at impl time)
