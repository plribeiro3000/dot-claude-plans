# PLAN — Import KeyCloak SSO cluster to Terraform

## Current Situation

- **Region:** `sa-east-1` (São Paulo)
- **Created via:** AWS Console + CloudFormation (ECS cluster)
- **Not managed by Terraform** — all resources were provisioned manually
- **Domain:** `auth-001.app4shark.com` (wildcard cert `*.app4shark.com`)

### Existing Infrastructure (Discovery)

**VPC: management** (`vpc-0bdc76f3b391694dd`, `10.255.0.0/16`)
- 3 public subnets: `management-pub-a` (1c, 10.255.0.0/24), `management-pub-c` (1c, 10.255.1.0/24), `management-pub-2a` (1a, 10.255.4.0/24)
- 2 private subnets: `management-prv-a` (1a, 10.255.2.0/24), `management-prv-c` (1c, 10.255.3.0/24)
- IGW: `igw-06f10a0eb3ab77ae1`
- NAT Gateway: `nat-0d7fe84dc6c97f1ca` (subnet pub-2a, EIP: 54.233.103.227)
- Route tables: `management-pub` (public, with peering routes) + `management-prv` (private, via NAT)
- 9 VPC peering connections:
  - `pcx-0d8b42289e7030f61` — production (us-east-1, 10.254.0.0/16)
  - `pcx-078cff15e5c534ca3` — almaviva (10.1.0.0/24)
  - `pcx-0d2b3cbed169074e4` — redebrasil (10.1.1.0/24)
  - `pcx-0cfc2971e1dedf0cc` — maqnelson (10.1.2.0/24)
  - `pcx-0660dcb38076bd208` — commcenter (10.1.3.0/24)
  - `pcx-0a31bb4f931e55651` — aster-maquinas (10.1.4.0/24)
  - `pcx-0e6e37042c51b363e` — unknown (us-east-1, 10.2.1.0/24)
  - `pcx-080ff142daa2beadd` — atento-br (10.12.255.0/24)
  - `pcx-0dd23f620fcc6cc77` — out-atento-br (10.12.0.0/26)

**ECS Cluster: `4shark-keycloak`**
- Fargate-based (capacity providers: FARGATE, FARGATE_SPOT)
- CloudFormation stack: `Infra-ECS-Cluster-4shark-keycloak-700c8106`
- Service Discovery namespace: `4shark-keycloak` (HTTP, `ns-w4rst3xqinbzhdch`)
- Container Insights: disabled

**ECS Service: `auth-001`**
- Desired count: 2, running: 2
- Fargate platform: 1.4.0
- Deploy: ROLLING with circuit breaker + auto-rollback
- Subnets: `management-prv-a`, `management-prv-c`
- Security Group: `sg-09fba8c76ba2c4899` (auth)
- assignPublicIp: ENABLED
- No auto scaling

**Task Definition: `auth-001-task:38`**
- Image: `405749097490.dkr.ecr.sa-east-1.amazonaws.com/4shark-keycloak-clustered:1`
- CPU: 1024 (1 vCPU), Memory: 4096 MB (4 GB)
- Ports: 8080 (app), 9000 (management/health)
- Entry point: `/opt/keycloak/bin/kc.sh`
- Command: `start --http-enabled=true --http-port=8080 --hostname-backchannel-dynamic=false --proxy-headers=xforwarded --hostname=https://auth-001.app4shark.com/auth --http-management-port=9000 --health-enabled=true`
- Environment:
  - `KC_HTTP_RELATIVE_PATH=/auth`
  - `KC_DB=postgres`
  - `KC_HOSTNAME_ADMIN_URL=https://auth-001.app4shark.com/auth`
  - `KC_HOSTNAME_URL=https://auth-001.app4shark.com/auth`
  - `KC_DB_URL=jdbc:postgresql://auth001.c8jdkpg7fpd1.sa-east-1.rds.amazonaws.com:5432/keycloak`
- Secrets (from `auth-001-sm`): KC_DB_PASSWORD, KC_DB_USERNAME, KEYCLOAK_ADMIN, KEYCLOAK_ADMIN_PASSWORD
- Logs: `/ecs/4shark-keycloak-task`
- Task/Execution role: `ecsTaskExecutionRole-keycloak`

**ALB: `auth-001`**
- Internet-facing, in public subnets (pub-2a, pub-a)
- Listener: HTTPS 443 (TLS 1.3 policy: `ELBSecurityPolicy-TLS13-1-2-2021-06`)
- ACM cert: `arn:aws:acm:sa-east-1:405749097490:certificate/fe1946d5-9ad5-4d59-9738-bdcf1d6b70e0`
- Target group: `auth-001` (HTTP:8080, target type: ip)
- Health check: `/auth/health` on port 9000, interval 30s, healthy 5, unhealthy 4
- No deletion protection, no access logs

**RDS: `auth001`**
- PostgreSQL 15.12, `db.t3.small`
- Storage: 200 GB gp3 (3000 IOPS, 125 MB/s)
- MultiAZ: true (1c primary, 1a secondary)
- Encrypted: KMS (`6f7b8e40-e077-4a1f-914d-c15f6e731e35`)
- Backup: 7 days, window 02:00-02:30 UTC
- DB name: `keycloak`, master user: `postgres`
- Subnet group: `default-vpc-0bdc76f3b391694dd`
- Security group: `sg-0ffd57ce587c3f3b8` (auth-rds) — port 5432 from VPC CIDR
- No deletion protection, no Performance Insights, no Enhanced Monitoring
- Parameter group: `default.postgres15`

**ECR Repositories:**
- `4shark-keycloak` (older)
- `4shark-keycloak-clustered` (current, used by task def)

**IAM:**
- Role: `ecsTaskExecutionRole-keycloak`
  - Trust: `ecs-tasks.amazonaws.com`
  - `AmazonECSTaskExecutionRolePolicy` (AWS managed)
  - `keycloak-policy` (custom): Secrets Manager + KMS + S3 access

**Secrets Manager:**
- `auth-001-sm` (KMS key: `5a64fa33-0a93-4352-9c62-e9edad2b87f9`)

**Security Groups:**
- `auth` (`sg-09fba8c76ba2c4899`): HTTPS 443 from 0.0.0.0/0, all from VPC CIDR
- `auth-rds` (`sg-0ffd57ce587c3f3b8`): PostgreSQL 5432 from VPC CIDR
- `auth002-keycloak-sg` (`sg-05dbf8341d809af62`): legacy SG (ports 8080, 9000, 22, 443)

**CloudWatch Log Groups:**
- `/ecs/4shark-keycloak-task` (active, ~343 MB)
- `/ecs/auth-001`, `/ecs/keycloak`, `/ecs/keycloak-task` (legacy)

**S3:** IAM policy references `4shark-keycloak-s3` but bucket does not exist.

## Objective / Target State

- All KeyCloak infrastructure managed by Terraform via `terraform import`
- New environment directory `auth-001/` in the terraform project
- State stored in S3 backend: `4shark-terraform-state` key `auth-001/terraform.tfstate`
- Zero downtime — import only, no resource recreation

## Problem / New Feature

Import the existing KeyCloak SSO cluster (sa-east-1) into Terraform management. The infrastructure was provisioned manually via AWS Console and CloudFormation and needs to be brought under IaC control.

## Challenges and Notes

- **Fargate vs EC2**: All existing modules target EC2. KeyCloak uses Fargate — write raw resources for the Fargate-specific parts (ECS cluster, service, task definition)
- **CloudFormation stack**: The ECS cluster was created via CF stack `Infra-ECS-Cluster-4shark-keycloak-700c8106`. After Terraform import, this stack becomes orphaned. Can be deleted with `retain resources` option or left as-is
- **Region**: `sa-east-1` vs `us-east-1` for all other environments — provider block needs `region = "sa-east-1"`
- **S3 bucket ghost**: IAM policy references `4shark-keycloak-s3` which doesn't exist. Import the policy as-is, clean up later if desired
- **Legacy SG and log groups**: `auth002-keycloak-sg` and old log groups exist but are not actively used. Import them or ignore — decision during execution

## Proposed Steps

1. **Create `auth-001/` directory** with structure:
   - `providers.tf` — AWS provider for sa-east-1, S3 backend
   - `vpc.tf` — VPC, subnets, IGW, NAT Gateway, EIP, route tables, routes
   - `peering.tf` — All 9 VPC peering connections + peering routes
   - `security_groups.tf` — auth, auth-rds security groups + rules
   - `iam.tf` — IAM role, policies, attachments
   - `ecr.tf` — ECR repositories
   - `secrets.tf` — Secrets Manager secret (reference, not values)
   - `logs.tf` — CloudWatch log groups
   - `rds.tf` — RDS instance, subnet group
   - `alb.tf` — ALB, listener, target group
   - `ecs.tf` — ECS cluster, capacity providers, service discovery namespace, task definition, service
   - `variables.tf` — variables
   - `outputs.tf` — outputs (KeyCloak URL, RDS endpoint, etc.)

2. **Write Terraform code** matching the exact current state of each resource

3. **Run `terraform import`** for all resources (listed below)

4. **Run `terraform plan`** — iterate until plan shows zero changes

5. **Handle CloudFormation stack** — delete with retain resources or leave orphaned

### Resources to Import

| # | Resource | Terraform Type | Import ID |
|---|----------|---------------|-----------|
| **VPC** | | | |
| 1 | VPC management | `aws_vpc` | `vpc-0bdc76f3b391694dd` |
| 2 | Subnet management-pub-a | `aws_subnet` | `subnet-05ef68e0a36f73693` |
| 3 | Subnet management-pub-c | `aws_subnet` | `subnet-0a8d6cf0048d42a26` |
| 4 | Subnet management-pub-2a | `aws_subnet` | `subnet-0f3b88bcee6275ac4` |
| 5 | Subnet management-prv-a | `aws_subnet` | `subnet-03320c13f3efc36ce` |
| 6 | Subnet management-prv-c | `aws_subnet` | `subnet-0d7d244e85dcb5afb` |
| 7 | IGW | `aws_internet_gateway` | `igw-06f10a0eb3ab77ae1` |
| 8 | NAT Gateway | `aws_nat_gateway` | `nat-0d7fe84dc6c97f1ca` |
| 9 | EIP (NAT) | `aws_eip` | (lookup during execution) |
| 10 | Route table pub | `aws_route_table` | `rtb-0b0f97ccaea1b4e28` |
| 11 | Route table prv | `aws_route_table` | `rtb-0c582c63aa3248e87` |
| 12 | RT association pub-a | `aws_route_table_association` | `subnet-05ef68e0a36f73693/rtb-0b0f97ccaea1b4e28` |
| 13 | RT association pub-c | `aws_route_table_association` | `subnet-0a8d6cf0048d42a26/rtb-0b0f97ccaea1b4e28` |
| 14 | RT association pub-2a | `aws_route_table_association` | `subnet-0f3b88bcee6275ac4/rtb-0b0f97ccaea1b4e28` |
| 15 | RT association prv-a | `aws_route_table_association` | `subnet-03320c13f3efc36ce/rtb-0c582c63aa3248e87` |
| 16 | RT association prv-c | `aws_route_table_association` | `subnet-0d7d244e85dcb5afb/rtb-0c582c63aa3248e87` |
| 17 | Route pub default (IGW) | `aws_route` | `rtb-0b0f97ccaea1b4e28_0.0.0.0/0` |
| 18 | Route prv default (NAT) | `aws_route` | `rtb-0c582c63aa3248e87_0.0.0.0/0` |
| **Peering** | | | |
| 19 | Peering production | `aws_vpc_peering_connection` | `pcx-0d8b42289e7030f61` |
| 20 | Peering almaviva | `aws_vpc_peering_connection` | `pcx-078cff15e5c534ca3` |
| 21 | Peering redebrasil | `aws_vpc_peering_connection` | `pcx-0d2b3cbed169074e4` |
| 22 | Peering maqnelson | `aws_vpc_peering_connection` | `pcx-0cfc2971e1dedf0cc` |
| 23 | Peering commcenter | `aws_vpc_peering_connection` | `pcx-0660dcb38076bd208` |
| 24 | Peering aster-maquinas | `aws_vpc_peering_connection` | `pcx-0a31bb4f931e55651` |
| 25 | Peering unknown (10.2.1.0/24) | `aws_vpc_peering_connection` | `pcx-0e6e37042c51b363e` |
| 26 | Peering atento-br | `aws_vpc_peering_connection` | `pcx-080ff142daa2beadd` |
| 27 | Peering out-atento-br | `aws_vpc_peering_connection` | `pcx-0dd23f620fcc6cc77` |
| 28-36 | Peering routes (pub RT) | `aws_route` | `rtb-0b0f97ccaea1b4e28_{cidr}` (9 routes) |
| **Security Groups** | | | |
| 37 | SG auth | `aws_security_group` | `sg-09fba8c76ba2c4899` |
| 38 | SG auth-rds | `aws_security_group` | `sg-0ffd57ce587c3f3b8` |
| 39-42 | SG rules | `aws_security_group_rule` | (multiple ingress/egress rules) |
| **IAM** | | | |
| 43 | IAM Role | `aws_iam_role` | `ecsTaskExecutionRole-keycloak` |
| 44 | IAM Policy | `aws_iam_policy` | `arn:aws:iam::405749097490:policy/keycloak-policy` |
| 45 | Attachment (managed) | `aws_iam_role_policy_attachment` | `ecsTaskExecutionRole-keycloak/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` |
| 46 | Attachment (custom) | `aws_iam_role_policy_attachment` | `ecsTaskExecutionRole-keycloak/arn:aws:iam::405749097490:policy/keycloak-policy` |
| **ECR** | | | |
| 47 | ECR 4shark-keycloak | `aws_ecr_repository` | `4shark-keycloak` |
| 48 | ECR 4shark-keycloak-clustered | `aws_ecr_repository` | `4shark-keycloak-clustered` |
| **Secrets** | | | |
| 49 | Secret auth-001-sm | `aws_secretsmanager_secret` | `arn:aws:secretsmanager:sa-east-1:405749097490:secret:auth-001-sm-NRJuS1` |
| **Logs** | | | |
| 50 | Log group | `aws_cloudwatch_log_group` | `/ecs/4shark-keycloak-task` |
| **RDS** | | | |
| 51 | DB Subnet Group | `aws_db_subnet_group` | `default-vpc-0bdc76f3b391694dd` |
| 52 | RDS Instance | `aws_db_instance` | `auth001` |
| **ALB** | | | |
| 53 | ALB | `aws_lb` | `arn:aws:elasticloadbalancing:sa-east-1:405749097490:loadbalancer/app/auth-001/d3d12f09fa1cbeb6` |
| 54 | Target Group | `aws_lb_target_group` | `arn:aws:elasticloadbalancing:sa-east-1:405749097490:targetgroup/auth-001/92c1ddad52d3ad09` |
| 55 | Listener HTTPS | `aws_lb_listener` | `arn:aws:elasticloadbalancing:sa-east-1:405749097490:listener/app/auth-001/d3d12f09fa1cbeb6/f8319e74c8c6a01a` |
| **ECS** | | | |
| 56 | ECS Cluster | `aws_ecs_cluster` | `arn:aws:ecs:sa-east-1:405749097490:cluster/4shark-keycloak` |
| 57 | Cluster Capacity Providers | `aws_ecs_cluster_capacity_providers` | `4shark-keycloak` |
| 58 | Service Discovery Namespace | `aws_service_discovery_http_namespace` | `ns-w4rst3xqinbzhdch` |
| 59 | Task Definition | `aws_ecs_task_definition` | `arn:aws:ecs:sa-east-1:405749097490:task-definition/auth-001-task:38` |
| 60 | ECS Service | `aws_ecs_service` | `arn:aws:ecs:sa-east-1:405749097490:service/4shark-keycloak/auth-001` |

**~60 resources total.**

## Internal References

- Existing Terraform patterns: `app-demo-001/`, `app-shared-001/`
- VPC data module: `modules/vpc_data/`
- ECS modules (EC2 pattern, for reference): `modules/ecs_cluster/`, `modules/ecs_service/`
- ALB module (reference): `modules/public_alb/`

---

**Status:** Completed. Merged via PR #189 on 2026-02-26.
