# PLAN — Deploy Mem0 Shared AI Memory on AWS (Distributed Architecture)

## Context

After a comprehensive spike analyzing 40+ AI memory database solutions (see `SPIKE.md` in this directory), the team approved **Mem0** as the shared AI memory platform for the 4Shark engineering team. The goal is to deploy Mem0 on AWS so that all engineers share a centralized knowledge base via Claude Code, while each engineer also has a private workspace for individual context. This eliminates the problem of losing knowledge between sessions and across engineers.

## Current Situation

- Engineers lose context between Claude Code sessions
- Knowledge learned by one engineer is not accessible to others
- The existing `~/.claude/` Git repo handles rules/config but not semantic memory
- The Terraform repo at `~/Projects/4Shark/terraform/` manages all AWS infrastructure
- Egress VPC (`10.254.0.0/27`) with NAT Gateway provides shared outbound internet for all São Paulo VPCs via Transit Gateway
- Transit Gateway (`aws_ec2_transit_gateway.sa_east_1`) connects all São Paulo VPCs with spoke/egress route tables
- VPN access is already configured via `sg-001068a60ca68d4ba`
- S3 backend: `4shark-terraform-state` (no DynamoDB lock — single operator)

## Objective / Target State

- Mem0 API running on ECS Fargate, accessible only via VPN
- PostgreSQL + pgvector on RDS (managed)
- Neo4j on Aura Professional (managed, sa-east-1)
- Each engineer's Claude Code connects via local OpenMemory MCP server → remote Mem0 API
- Shared team knowledge space (`agent_id=4shark-team`) + per-engineer private spaces (`user_id=<engineer>`)
- DNS record at `mem0.4shark.internal`
- Zero OS management — all components are managed services or containers

## Problem / New Feature

New infrastructure project: deploy Mem0 as a distributed architecture with managed services — ECS Fargate (API), RDS PostgreSQL/pgvector (vector store), Neo4j Aura Professional (knowledge graph) — in a new VPC in São Paulo, connected to the existing egress via Transit Gateway, with VPN-only access.

## Challenges, Difficulties and Risks

- **Technical:** Mem0 API needs persistent connections to both RDS and Neo4j Aura. ECS Fargate handles this naturally (long-running containers)
- **Technical:** Neo4j Aura Professional does not support Private Endpoints (only Business Critical does). Access is authenticated via credentials + IP allowlist if needed
- **Technical:** Embeddings require an LLM provider. OpenAI API key (~$5/month for team usage) is the simplest option
- **Security:** Mem0 API has no built-in authentication. VPN-only access via Security Group is the primary security layer
- **Networking:** New VPC must attach to existing Transit Gateway for egress. Follow the same pattern as integrator VPCs
- **Neo4j Aura Terraform:** The provider (`neo4j-labs/terraform-provider-neo4jaura`) is beta (v0.0.2) and Labs status — not officially supported. May need manual provisioning with Terraform importing, or use the API directly

## Proposed Solution

### Architecture (Distributed — approved)

```
Engineer's machine (VPN)         AWS sa-east-1 — New VPC (claude-shared-memory)
┌──────────────────────┐
│ Claude Code           │         ┌─────────────────────────────────┐
│  └─ OpenMemory MCP   │─HTTP──▶│ ALB internal (:8080)             │
│     (local process)   │  VPN   │  └─▶ ECS Fargate                │
└──────────────────────┘         │       └─ Mem0 API (:8080)       │
                                  │                                  │
                                  │ DNS: mem0.4shark.internal → ALB  │
                                  └───────┬──────────┬───────────────┘
                                          │          │
                               ┌──────────┘          └──────────┐
                               ▼                                 ▼
                     ┌──────────────────┐          ┌──────────────────┐
                     │ RDS PostgreSQL   │          │ Neo4j Aura       │
                     │ + pgvector       │          │ Professional     │
                     │ (db.t4g.micro)   │          │ (1GB, sa-east-1) │
                     │ Private subnet   │          │ Cloud-managed    │
                     └──────────────────┘          └──────────────────┘

Outbound internet (OpenAI API, Docker pulls):
  New VPC → Transit Gateway → Egress VPC (10.254.0.0/27) → NAT Gateway → Internet
```

### Terraform Project Structure

```
~/Projects/4Shark/terraform/claude-shared-memory/
├── providers.tf        # AWS provider + S3 backend
├── variables.tf        # Input variables
├── terraform.tfvars    # Variable values
├── locals.tf           # Local values, tags
├── data.tf             # Data sources (TGW, VPN SG, Route53 zone)
├── vpc.tf              # New VPC, subnets, route tables, TGW attachment
├── security.tf         # Security groups (ALB, Fargate, RDS)
├── rds.tf              # RDS PostgreSQL + pgvector
├── alb.tf              # Internal ALB + target group + listener
├── ecs.tf              # ECS cluster, task definition, service
├── dns.tf              # Route53 alias record → ALB
├── outputs.tf          # DNS name, ALB endpoint, RDS endpoint
└── neo4j.tf            # Neo4j Aura resource (if TF provider works) or documentation
```

### Cost Estimate

| Component | Detail | Monthly Cost |
|-----------|--------|-------------|
| ECS Fargate | 0.25 vCPU, 0.5GB RAM, 24/7 | ~$9 |
| ALB internal | Hourly + LCU (low traffic) | ~$16 |
| RDS PostgreSQL | db.t4g.micro, 20GB gp3 | ~$15 |
| Neo4j Aura Professional | 1GB RAM, sa-east-1 | ~$65 |
| OpenAI embeddings | Team usage (~5 engineers) | ~$5 |
| Egress (NAT Gateway) | Shared — already exists, no additional cost | $0 |
| **Total** | | **~$110/month** |

### Proposed Steps

#### Step 1 — Project scaffold

Create `claude-shared-memory/` folder with:

- **`providers.tf`**: AWS provider `sa-east-1`, S3 backend key `claude-shared-memory/terraform.tfstate`
- **`variables.tf`**: vpc_cidr, rds_instance_class, openai_api_key (sensitive), neo4j_uri, neo4j_user, neo4j_password (sensitive), management_vpn_sg_id, internal_zone_id
- **`terraform.tfvars`**: concrete values
- **`locals.tf`**: name_prefix = `claude-shared-memory`, common tags (Environment, Automation, Service)

#### Step 2 — Networking (new VPC + Transit Gateway attachment)

- **`vpc.tf`**: Create a new VPC for the Mem0 stack:
  - VPC CIDR: TBD (must not overlap with existing — suggest `10.2.0.0/26` or next available in the `10.x.x.x` range). A `/26` (64 IPs) accommodates 2 private subnets + 1 TGW subnet
  - Private subnet A: `<cidr>/28` in `sa-east-1a` (16 IPs — ECS Fargate, RDS, ALB)
  - Private subnet B: `<cidr>/28` in `sa-east-1b` (16 IPs — ALB requires 2 AZs, RDS subnet group)
  - TGW subnet: `<cidr>/28` in `sa-east-1a` (for Transit Gateway attachment)
  - Transit Gateway attachment → associate with `spoke-rt` (same as integrator VPCs)
  - Route table: default route `0.0.0.0/0` → Transit Gateway (egress via shared NAT)
  - Reference TGW ID via SSM parameter: `/networking/tgw-sa-east-1/id`
  - Reference spoke RT ID via SSM parameter: `/networking/tgw-sa-east-1/spoke_rt_id`

- **Networking stack update** (`terraform/networking/`): Add return routes in the egress VPC for the new CIDR via TGW, and propagation in the TGW route tables. Follow the same pattern as `vpc_almaviva.tf` and other integrator VPCs.

> **Note:** The engineer must confirm the VPC CIDR allocation to avoid conflicts with existing networks.

#### Step 3 — Security

- **`security.tf`**: Three security groups:
  1. **ALB SG** — Internal Load Balancer:
     - Ingress: TCP 8080 from VPN SG `sg-001068a60ca68d4ba`
     - Egress: TCP 8080 to Fargate SG
  2. **Fargate SG** — Mem0 API:
     - Ingress: TCP 8080 from ALB SG
     - Egress: TCP 5432 to RDS SG (PostgreSQL)
     - Egress: TCP 7687 to `0.0.0.0/0` (Neo4j Aura Bolt — cloud endpoint)
     - Egress: TCP 443 to `0.0.0.0/0` (OpenAI API, ECR image pulls)
  3. **RDS SG** — PostgreSQL:
     - Ingress: TCP 5432 from Fargate SG only

#### Step 4 — RDS PostgreSQL + pgvector

- **`rds.tf`**: RDS instance:
  - Engine: `postgres` 16.x (pgvector 0.8.0 supported)
  - Instance class: `db.t4g.micro` (2 vCPU, 1GB RAM)
  - Storage: 20GB gp3, autoscaling up to 100GB
  - Subnet group: private subnet
  - Security group: RDS SG
  - Database name: `mem0`
  - Automated backups: 7-day retention
  - Enable pgvector extension via parameter group or post-provisioning SQL
  - Multi-AZ: no (cost optimization, non-critical workload)
  - Encryption at rest: enabled (default KMS key)

#### Step 5 — Neo4j Aura Professional

- **`neo4j.tf`**: Provision Neo4j Aura Professional instance:
  - Region: `sa-east-1`
  - RAM: 1GB (smallest tier)
  - If the `neo4j-labs/terraform-provider-neo4jaura` works: provision via Terraform
  - If the provider is too unstable: provision manually via Neo4j Aura Console, document credentials, and pass URI/credentials as Terraform variables
  - Store credentials in AWS Secrets Manager or pass as sensitive variables

> **Note:** The Neo4j Aura Terraform provider is beta (v0.0.2, Labs status). Test it first. If unreliable, manual provisioning is acceptable — the instance is long-lived and rarely changes.

#### Step 6 — ECS Fargate (Mem0 API)

- **`ecs.tf`**: ECS resources:
  - ECS Cluster: `claude-shared-memory`
  - Task Definition:
    - Container: `mem0ai/mem0:latest` (or pinned version)
    - CPU: 256 (0.25 vCPU), Memory: 512 (0.5GB)
    - Port: 8080
    - Environment variables:
      - `DATABASE_URL`: RDS PostgreSQL endpoint
      - `NEO4J_URI`: Neo4j Aura bolt endpoint
      - `NEO4J_USER`: Neo4j credentials
      - `NEO4J_PASSWORD`: Neo4j credentials (from Secrets Manager)
      - `OPENAI_API_KEY`: OpenAI key (from Secrets Manager)
    - Log driver: awslogs (CloudWatch)
  - Service:
    - Desired count: 1
    - Subnet: private subnet
    - Security group: Fargate SG
    - Load balancer: internal ALB target group (port 8080)

- **`alb.tf`**: Internal Application Load Balancer:
  - Scheme: `internal`
  - Subnets: private subnet(s)
  - Security group: ALB SG
  - Target group: ECS service (port 8080, health check on `/`)
  - Listener: HTTP :8080 → forward to target group
  - ECS service auto-registers/deregisters tasks in the target group

#### Step 7 — DNS

- **`dns.tf`**: Route53 alias record `mem0.4shark.internal` → ALB DNS name
  - Zone: `Z3PBW9DU61QULB` (`4shark.internal`) — already exists, no additional cost
  - Alias record (not CNAME) — no extra Route53 query charges, resolves directly to ALB IPs
  - ALB handles the dynamic IP problem: tasks register/deregister in target group automatically

#### Step 8 — MCP Configuration (documentation only)

Document how each engineer configures their local Claude Code:

1. Install OpenMemory MCP: `pip install openmemory-mcp` (or use Docker)
2. Add to `~/.claude/settings.local.json`:
   ```json
   {
     "mcpServers": {
       "mem0": {
         "command": "openmemory-mcp",
         "args": ["--host", "mem0.4shark.internal", "--port", "8080", "--user-id", "<engineer-name>"]
       }
     }
   }
   ```
3. For shared team memories, use `agent_id=4shark-team`
4. For private memories, the `user_id` parameter scopes automatically

### Memory Scoping Strategy

| Scope | Mem0 Parameter | Use Case |
|-------|---------------|----------|
| Private | `user_id=pedro` | Pedro's personal project context |
| Team shared | `agent_id=4shark-team` | Architecture decisions, patterns, conventions |
| Project-specific | `metadata={"project": "app"}` | Knowledge specific to a project |

## Internal References

- Spike: `SPIKE.md` (same directory)
- Terraform repo: `~/Projects/4Shark/terraform/`
- Networking stack: `terraform/networking/`
- Egress VPC: `terraform/networking/vpc_egress_sa_east_1.tf` (10.254.0.0/27, NAT Gateway)
- Transit Gateway: `terraform/networking/transit_gateway.tf` (spoke-rt, egress-rt)
- SSM parameters: `/networking/tgw-sa-east-1/id`, `/networking/tgw-sa-east-1/spoke_rt_id`, `/networking/tgw-sa-east-1/egress_rt_id`
- Integrator VPC pattern: `terraform/networking/vpc_almaviva.tf` (reference for TGW attachment)
- Management VPN SG: `sg-001068a60ca68d4ba`
- Route53 zone: `Z3PBW9DU61QULB` / `4shark.internal`
- S3 backend: `4shark-terraform-state`
- Neo4j Aura Terraform provider: `neo4j-labs/terraform-provider-neo4jaura` (beta v0.0.2)

## Verification

1. `terraform init` — verify S3 backend connects
2. `terraform plan` — review all resources to be created
3. `terraform apply` — deploy infrastructure (VPC, RDS, ECS)
4. Verify ECS task is running: `aws ecs describe-services --cluster claude-shared-memory`
5. Verify RDS is available: `aws rds describe-db-instances --db-instance-identifier claude-shared-memory`
6. Verify Neo4j Aura connectivity from ECS task (check CloudWatch logs)
7. From VPN, test Mem0 API: `curl http://mem0.4shark.internal:8080/v1/memories/`
8. Configure local MCP and verify Claude Code can store/retrieve memories
9. Test workspace isolation: store a memory as `user_id=test1`, confirm it's not visible to `user_id=test2`
10. Verify DNS resolution: `dig mem0.4shark.internal`
