# Migration Plan: Ansible → Terraform for 4Client Infrastructure (Integrator)

## Context

The 4Client infrastructure for the Integrator application is provisioned via Ansible playbooks. The goal is to migrate to Terraform within the existing `terraform` project (`~/Projects/4Shark/terraform/`), with one subfolder per client environment, following the same patterns already established (S3 backend, module-based architecture).

All 4Client infrastructure lives in **sa-east-1 (São Paulo)**. The existing Terraform project manages only us-east-1 resources. This will be the first sa-east-1 workload.

---

## Phase Status

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1: Modules | **COMPLETE** | `modules/integrator` + `modules/app` created, `terraform validate` passes |
| Phase 1.5: Cleanup | **COMPLETE** | Orphaned resources removed, ~$40/mês saved |
| Phase 2: Pilot Import (aster-maquinas) | **COMPLETE** | PR #163 merged |
| Phase 3: Remaining Clients | **COMPLETE** | All 7 environments imported and applied |
| Phase 4: Final Validation | **COMPLETE** | All environments show clean `terraform plan` (no changes) |

### Import Summary

| Environment | PR | Import Result | Post-Apply State | Notes |
|---|---|---|---|---|
| aster-maquinas (pilot) | #163 | 37 imports OK | Clean | — |
| commcenter | #164 | 37 imports OK | Clean | — |
| redebrasil | — | 36 imports OK | Clean | — |
| maqnelson | #165 | 37 imports OK | Clean | — |
| almaviva | #166 | 39 imports OK | VPN tunnel perpetual diff | Known provider bug — deferred to future PR |
| integrator-atento-br | #167 | 36 imports OK | VPN tunnel perpetual diff | Same provider bug as almaviva |
| app-atento-br | #168 | 41 imports OK | Clean | Zone association created (was missing from Ansible due to `ignore_errors: true`) |

### Pending Follow-Up (separate PRs)

| Item | Description |
|---|---|
| VPN tunnel perpetual diff | almaviva and integrator-atento-br show perpetual diff on tunnel parameters (known AWS provider bug). Fix: either add explicit tunnel params or `lifecycle { ignore_changes }`. |
| Tags standardization in `modules/app` | Customer Gateway missing `common_tags` (only has `{ Name }`), app `root_block_device` missing tags. Same bugs that were already fixed in `modules/integrator`. |

---

## Modules Created

### `modules/integrator` (standard 4client — VPC + VPN + ElastiCache + MongoDB + App)

**3 subnets** (NOT 4 — Ansible creates pub-a and pub-b with same CIDR, pub-b overwrites pub-a's tags, only pub-b actually exists in AWS):
- `pub-b` in `zone_a` (sa-east-1a) — public subnet where NAT GW sits
- `prv-a` in `zone_a` (sa-east-1a)
- `prv-b` in `zone_b` (defaults to sa-east-1a, overridden to sa-east-1c for commcenter and atento-br)

Files:
```
modules/integrator/
├── main.tf          # VPC, 3 subnets, IGW, NAT, EIP, locals (name_prefix, common_tags, subnet_map)
├── routing.tf       # Route tables (pub/prv), routes, main RT association, subnet associations
├── peering.tf       # VPC peering with management + return route via management_route_table_ids
├── vpn.tf           # VGW, CGW, VPN connection, VPN connection routes (conditional)
├── security.tf      # Default security group (self-ref + management VPN SG)
├── elasticache.tf   # Redis cluster + subnet group (NO tags — matches AWS)
├── mongodb.tf       # 3x EC2 (arbiter prv-a, primary prv-b, secondary prv-a), delete_on_termination=false
├── app.tf           # Dynamic app server EC2 instances
├── dns.tf           # Route53 zone association + A records (mongo, app) + CNAME (redis), TTL=60
├── variables.tf     # All variables with defaults
└── outputs.tf       # VPC, subnet, SG, peering, VPN, ElastiCache, MongoDB, app IPs
```

### `modules/app` (out variant — VPC + VPN + App only, no MongoDB/ElastiCache)

**4 subnets** (correct for this variant):
- `pub-a` in `zone_a` (sa-east-1a) — NAT GW here
- `pub-b` in `zone_b` (sa-east-1c)
- `prv-a` in `zone_a` (sa-east-1a)
- `prv-b` in `zone_b` (sa-east-1c)

Files:
```
modules/app/
├── main.tf          # VPC, 4 subnets, IGW, NAT, EIP
├── routing.tf       # Route tables, main RT association
├── peering.tf       # VPC peering with management + return route
├── vpn.tf           # VGW, CGW, VPN connection (conditional)
├── security.tf      # Default security group
├── app.tf           # Dynamic app server EC2 instances
├── dns.tf           # Route53 zone association + A records for app servers, TTL=60
├── variables.tf
└── outputs.tf
```

### Key Differences Between Modules

| Aspect | `integrator` | `app` |
|--------|-------------|-------|
| Name prefix | `4client-{name}` | `4client-out-{name}` |
| VPC CIDR | /24 | /26 |
| Subnets | 3 (pub-b, prv-a, prv-b) | 4 (pub-a, pub-b, prv-a, prv-b) |
| NAT GW subnet | pub-b | pub-a |
| NAT GW tags | `{ Name = ... }` only (no Client) | `common_tags` (with Client) |
| zone_b default | sa-east-1a | sa-east-1c |
| MongoDB | 3 instances | None |
| ElastiCache | Redis cluster | None |

### Tags Pattern (validated against AWS)

```hcl
locals {
  name_prefix = "4client-${var.client_name}"  # or "4client-out-" for app module
  common_tags = merge(var.tags, { Client = var.client_name })
}
```

| Resource | Tags |
|----------|------|
| VPC, subnets, IGW, EIP, route tables, peering, VPN GW, VPN connection, SG | `common_tags` + Name |
| NAT GW (integrator only) | `{ Name = ... }` only — NO Client tag |
| NAT GW (app) | `common_tags` + Name |
| CGW | `{ Name = ... }` only — NO Client tag |
| ElastiCache | NO tags at all |
| EC2 MongoDB | `common_tags` + Name + `Automation=ansible, Role=database, Type=mongodb` |
| EC2 App | `common_tags` + Name + `Automation=ansible, Role=application, Type=ruby` |
| EIP | Name = `{prefix}-nat-gateway` |
| Route tables | Name = `{prefix}-pub` / `{prefix}-prv` |
| Peering | Name = `{prefix}-management` |
| SG | Name = just `{prefix}` |

### EC2 Lifecycle

```hcl
lifecycle {
  ignore_changes = [ami, user_data, user_data_base64]
}
```

MongoDB EBS: `delete_on_termination = false`
App EBS: `delete_on_termination = true` (default)

---

## Environment Files (all created, all validated)

Each environment has `main.tf` + `providers.tf` (NO `terraform.tfvars` — values inline in `main.tf`).

Module reference: `module "this"` (not `module "client"`).

### integrator-almaviva/main.tf

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "almaviva"
  vpc_cidr          = "10.1.0.0/24"
  subnet_pub_b_cidr = "10.1.0.0/28"
  subnet_prv_a_cidr = "10.1.0.128/26"
  subnet_prv_b_cidr = "10.1.0.192/26"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "177.86.255.29"
  customer_network_cidrs = ["10.0.0.0/24", "172.16.255.9/32"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app002" = { instance_type = "t3.medium", subnet_key = "prv-b" }
    "app003" = { instance_type = "t3.medium", subnet_key = "prv-b" }
  }
}
```

### integrator-redebrasil/main.tf

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "redebrasil"
  vpc_cidr          = "10.1.1.0/24"
  subnet_pub_b_cidr = "10.1.1.0/28"
  subnet_prv_a_cidr = "10.1.1.128/26"
  subnet_prv_b_cidr = "10.1.1.192/26"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "200.182.4.34"
  customer_network_cidrs = ["172.16.16.0/21"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app002" = { instance_type = "t3.medium", subnet_key = "prv-b" }
  }
}
```

### integrator-maqnelson/main.tf

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "maqnelson"
  vpc_cidr          = "10.1.2.0/24"
  subnet_pub_b_cidr = "10.1.2.0/28"
  subnet_prv_a_cidr = "10.1.2.128/26"
  subnet_prv_b_cidr = "10.1.2.192/26"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "186.237.197.117"
  customer_network_cidrs = ["192.168.90.0/26"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app002" = { instance_type = "t3.medium", subnet_key = "prv-b" }
    "app003" = { instance_type = "t3.medium", subnet_key = "prv-b" }
  }
}
```

Note: Old VPN (172.21.35.0/26) was deleted during cleanup. Only current VPN route remains.

### integrator-commcenter/main.tf

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "commcenter"
  vpc_cidr          = "10.1.3.0/24"
  subnet_pub_b_cidr = "10.1.3.0/28"
  subnet_prv_a_cidr = "10.1.3.128/26"
  subnet_prv_b_cidr = "10.1.3.192/26"
  zone_b = "sa-east-1c"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "200.196.250.228"
  customer_network_cidrs = ["10.130.2.0/23"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app002"         = { instance_type = "t3.small", subnet_key = "prv-a" }
    "staging-app001" = { instance_type = "t3.small", subnet_key = "prv-a" }
  }
}
```

### integrator-aster-maquinas/main.tf (PILOT)

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "aster-maquinas"
  vpc_cidr          = "10.1.4.0/24"
  subnet_pub_b_cidr = "10.1.4.0/28"
  subnet_prv_a_cidr = "10.1.4.128/26"
  subnet_prv_b_cidr = "10.1.4.192/26"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "200.106.188.44"
  customer_network_cidrs = ["10.6.11.0/24"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app002"         = { instance_type = "t3.small", subnet_key = "prv-b" }
    "staging-app001" = { instance_type = "t3.small", subnet_key = "prv-b" }
  }
}
```

### integrator-atento-br/main.tf

```hcl
module "this" {
  source            = "../modules/integrator"
  client_name       = "atento-br"
  vpc_cidr          = "10.12.255.0/24"
  subnet_pub_b_cidr = "10.12.255.0/28"
  subnet_prv_a_cidr = "10.12.255.128/26"
  subnet_prv_b_cidr = "10.12.255.192/26"
  zone_b = "sa-east-1c"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "48.214.37.228"
  customer_network_cidrs = ["10.101.30.0/24"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  redis_node_type = "cache.t3.medium"
  app_servers = {
    "app002" = { instance_type = "t3.medium", subnet_key = "prv-a" }
  }
}
```

### app-atento-br/main.tf

```hcl
module "this" {
  source            = "../modules/app"
  client_name       = "atento-br"
  vpc_cidr          = "10.12.0.0/26"
  subnet_pub_a_cidr = "10.12.0.0/28"
  subnet_prv_a_cidr = "10.12.0.16/28"
  subnet_pub_b_cidr = "10.12.0.32/28"
  subnet_prv_b_cidr = "10.12.0.48/28"
  management_vpc_id          = "vpc-0bdc76f3b391694dd"
  management_vpc_cidr        = "10.255.0.0/16"
  management_vpn_sg_id       = "sg-001068a60ca68d4ba"
  management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
  enable_vpn             = true
  customer_gateway_ip    = "177.22.252.45"
  customer_network_cidrs = ["10.155.0.152/32", "10.189.0.162/32"]
  internal_zone_id = "Z3PBW9DU61QULB"
  dhcp_options_id  = "dopt-0e66e2fd3d05731ac"
  ubuntu_ami       = "ami-0bd91caaa9bc42cf3"
  app_servers = {
    "app001" = { instance_type = "t3.small", subnet_key = "prv-a" }
    "app002" = { instance_type = "t3.small", subnet_key = "prv-a" }
    "app003" = { instance_type = "t3.small", subnet_key = "prv-a" }
    "app004" = { instance_type = "t3.small", subnet_key = "prv-a" }
    "app005" = { instance_type = "t3.small", subnet_key = "prv-a" }
  }
}
```

Note: `windows-test` instance in this VPC is NOT managed by Terraform (kept intentionally).

### providers.tf pattern (all environments)

```hcl
provider "aws" {
  region = "sa-east-1"
}

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  backend "s3" {
    bucket = "4shark-terraform-state"
    key    = "{directory-name}/terraform.tfstate"
    region = "us-east-1"
  }
}
```

---

## Shared Constants (all environments)

```
management_vpc_id          = "vpc-0bdc76f3b391694dd"
management_vpc_cidr        = "10.255.0.0/16"
management_vpn_sg_id       = "sg-001068a60ca68d4ba"
management_route_table_ids = ["rtb-0b0f97ccaea1b4e28"]
internal_zone_id           = "Z3PBW9DU61QULB"
dhcp_options_id            = "dopt-0e66e2fd3d05731ac"
ubuntu_ami                 = "ami-0bd91caaa9bc42cf3"
```

---

## Cleanup Completed (Phase 1.5)

Executed on 2026-02-21. All items validated via AWS CLI before deletion.

| Item | ID | Reason | Savings |
|------|-----|--------|---------|
| Blackhole route 10.1.8.0/24 | rtb-0b0f97ccaea1b4e28 | Peering deleted (unimaq?) | $0 |
| Blackhole route 10.2.0.0/24 | rtb-0b0f97ccaea1b4e28 | Peering deleted (valecard?) | $0 |
| Blackhole route 10.0.0.0/16 | rtb-0b0f97ccaea1b4e28 | Peering deleted (old prod?) | $0 |
| CGW atento-br-old | cgw-0c376571a5cb12e14 | Orphan — no VPN attached | $0 |
| CGW maqnelson-old (2nd) | cgw-03d3ec68e2679de48 | Orphan — no VPN attached | $0 |
| CGW almaviva-old | cgw-0d509e4d43d9df082 | Orphan — no VPN attached | $0 |
| VPN maqnelson-old | vpn-02555adaec7268739 | Both tunnels DOWN, obsolete | ~$36/mês |
| CGW maqnelson-old (VPN) | cgw-04ffcf3c7c8e3cfe8 | Was attached to deleted VPN | $0 |
| Route 172.21.35.0/26 | rtb-0d2a44868566b3774 | Orphan from deleted VPN | $0 |
| DNS app002-old | 4client-out-atento-br-app002-old | Pointed to old instance | $0 |
| EC2 app002-old | i-0a9d249a1bb66ed7d | Stopped, replaced by app002 | ~$4.60/mês (EBS) |
| **Total savings** | | | **~$40/mês** |

### NOT deleted (intentional)

- `windows-test` (i-06e361f7b55d3fc47) in atento-br VPC — used for Atento testing with Windows

---

## AWS Resource IDs for Import (validated via AWS CLI)

### aster-maquinas (PILOT)

```bash
cd integrator-aster-maquinas/
terraform init

# VPC
terraform import 'module.this.aws_vpc.this' vpc-01af82a1bea1ba1fc
terraform import 'module.this.aws_vpc_dhcp_options_association.this' vpc-01af82a1bea1ba1fc

# Subnets (3 only — no pub-a)
terraform import 'module.this.aws_subnet.pub_b' subnet-0c67f255035d94fa4
terraform import 'module.this.aws_subnet.prv_a' subnet-05279a9e89be8eba0
terraform import 'module.this.aws_subnet.prv_b' subnet-043b3eefacbb43b29

# Gateways
terraform import 'module.this.aws_internet_gateway.this' igw-0166976d75fbce8ab
terraform import 'module.this.aws_eip.nat' eipalloc-0f196eb7cb1eda07a
terraform import 'module.this.aws_nat_gateway.this' nat-01f4651d50c20d462

# Peering
terraform import 'module.this.aws_vpc_peering_connection.management' pcx-0a31bb4f931e55651

# Route Tables
terraform import 'module.this.aws_route_table.private' rtb-071f3359fdd1d7c01
terraform import 'module.this.aws_route_table.public' rtb-0f8077c4d9467bdb3
terraform import 'module.this.aws_main_route_table_association.this' vpc-01af82a1bea1ba1fc

# Routes (individual aws_route resources)
terraform import 'module.this.aws_route.public_igw' rtb-0f8077c4d9467bdb3_0.0.0.0/0
terraform import 'module.this.aws_route.private_nat' rtb-071f3359fdd1d7c01_0.0.0.0/0
terraform import 'module.this.aws_route.private_peering' rtb-071f3359fdd1d7c01_10.255.0.0/16
terraform import 'module.this.aws_route.private_vpn["10.6.11.0/24"]' rtb-071f3359fdd1d7c01_10.6.11.0/24

# Route Table Associations
terraform import 'module.this.aws_route_table_association.pub_b' <association-id>
terraform import 'module.this.aws_route_table_association.prv_a' <association-id>
terraform import 'module.this.aws_route_table_association.prv_b' <association-id>

# Management return route
terraform import 'module.this.aws_route.management_return[0]' rtb-0b0f97ccaea1b4e28_10.1.4.0/24

# VPN
terraform import 'module.this.aws_vpn_gateway.this[0]' vgw-0b134e750c62a35e2
terraform import 'module.this.aws_customer_gateway.this[0]' cgw-0badd2b90e3e12318
terraform import 'module.this.aws_vpn_connection.this[0]' vpn-021b58e63a443e212
terraform import 'module.this.aws_vpn_connection_route.this["10.6.11.0/24"]' vpn-021b58e63a443e212:10.6.11.0/24

# Security Group
terraform import 'module.this.aws_default_security_group.this' sg-0e687f6170da1063d

# ElastiCache
terraform import 'module.this.aws_elasticache_subnet_group.this' ecsg-aster-maquinas
terraform import 'module.this.aws_elasticache_cluster.redis' ec-aster-maquinas

# MongoDB
terraform import 'module.this.aws_instance.mongo_arbiter' i-08b8e6917297dc717
terraform import 'module.this.aws_instance.mongo_primary' i-0528299f595ee7d42
terraform import 'module.this.aws_instance.mongo_secondary' i-0020df2d68b0a7f13

# App Servers
terraform import 'module.this.aws_instance.app["app002"]' i-0a52915aa95e5ab8b
terraform import 'module.this.aws_instance.app["staging-app001"]' i-0dd7ae980ebc091d4

# Route53
terraform import 'module.this.aws_route53_zone_association.this' Z3PBW9DU61QULB:vpc-01af82a1bea1ba1fc:sa-east-1
terraform import 'module.this.aws_route53_record.mongo_arbiter' Z3PBW9DU61QULB_4client-aster-maquinas-mongo000.4shark.internal_A
terraform import 'module.this.aws_route53_record.mongo_primary' Z3PBW9DU61QULB_4client-aster-maquinas-mongo001.4shark.internal_A
terraform import 'module.this.aws_route53_record.mongo_secondary' Z3PBW9DU61QULB_4client-aster-maquinas-mongo002.4shark.internal_A
terraform import 'module.this.aws_route53_record.redis' Z3PBW9DU61QULB_4client-aster-maquinas-redis001.4shark.internal_CNAME
terraform import 'module.this.aws_route53_record.app["app002"]' Z3PBW9DU61QULB_4client-aster-maquinas-app002.4shark.internal_A
terraform import 'module.this.aws_route53_record.app["staging-app001"]' Z3PBW9DU61QULB_4client-aster-maquinas-staging-app001.4shark.internal_A

# Validate
terraform plan  # Must show 0 changes
```

Note: Some IDs marked `<association-id>` need to be looked up at import time via:
```bash
aws ec2 describe-route-tables --route-table-ids rtb-071f3359fdd1d7c01 rtb-0f8077c4d9467bdb3 --region sa-east-1 --query 'RouteTables[].Associations[]'
```

### Resource IDs per Client (for remaining imports)

#### almaviva

| Resource | ID |
|----------|-----|
| VPC | vpc-0c197605716f3a46a |
| Subnet pub-b | (lookup needed) |
| Subnet prv-a | (lookup needed) |
| Subnet prv-b | (lookup needed) |
| IGW | igw-0908e43632af3a475 |
| NAT GW | nat-0c73faca7e745930d |
| EIP | (lookup needed) |
| Peering | pcx-078cff15e5c534ca3 |
| RT private | (lookup needed) |
| RT public | (lookup needed) |
| VGW | vgw-0b6c3936983384017 |
| CGW | cgw-020706a01c02180d3 |
| VPN | vpn-00e6e13038be30a1b |
| SG | sg-076365a3439dfc00e |
| ElastiCache | ec-almaviva / ecsg-almaviva |
| mongo000 | i-09ce6cb464004b8c9 |
| mongo001 | i-06681cb44aa6ea0c4 |
| mongo002 | i-0d8df097acc4eeb73 |
| app002 | i-052ddc01110fc9d52 |
| app003 | i-0c67b1c74a267710d |

#### redebrasil

| Resource | ID |
|----------|-----|
| VPC | vpc-01e23ad5ed29fbbbf |
| IGW | igw-046603418fc24ed60 |
| NAT GW | nat-05abe4fcc9b9f0d55 |
| Peering | pcx-0d2b3cbed169074e4 |
| VGW | vgw-06aa0a8896f0bd725 |
| CGW | cgw-076d72f0c9da62b0e |
| VPN | vpn-0511a7584441e4e5d |
| SG | sg-021435959f7a6069e |
| ElastiCache | ec-redebrasil / ecsg-redebrasil |
| mongo000 | i-01d8eab30b40371a5 |
| mongo001 | i-0d355cde3a1c2d9af |
| mongo002 | i-0b1a7ecf6918e1951 |
| app002 | i-0c08b720245db0be8 |

#### maqnelson

| Resource | ID |
|----------|-----|
| VPC | vpc-0d8b6d6a5819c0b21 |
| IGW | igw-0d7d61ce768468392 |
| NAT GW | nat-0f4523b88ae80f008 |
| Peering | pcx-0cfc2971e1dedf0cc |
| RT private | rtb-0d2a44868566b3774 |
| RT public | rtb-0c1f1628a99be663a |
| VGW | vgw-0a4e249fccdc268b8 |
| CGW | cgw-0659a71b88da4a041 |
| VPN | vpn-0f139221de4133cfd |
| SG | sg-04dc157a56aec4229 |
| ElastiCache | ec-maqnelson / ecsg-maqnelson |
| mongo000 | i-0b99b40d0cfa42396 |
| mongo001 | i-01550a1516a7510dd |
| mongo002 | i-0fc88b1a185540f75 |
| app002 | i-0c464b4ce847b80f1 |
| app003 | i-08c32432b67f2e7f6 |

#### commcenter

| Resource | ID |
|----------|-----|
| VPC | vpc-02e007218ef28a0d4 |
| IGW | igw-09378e8e15b658df3 |
| NAT GW | nat-0ca37d7634939afa3 |
| Peering | pcx-0660dcb38076bd208 |
| VGW | vgw-0eb7a96194a38413b |
| CGW | cgw-0d08caf834d1445fa |
| VPN | vpn-0ed021a126e025c60 |
| SG | sg-0fb857fc4f711b0a3 |
| ElastiCache | ec-commcenter / ecsg-commcenter |
| mongo000 | i-07ccc91781c7cefba |
| mongo001 | i-0633d3d25edb60d00 |
| mongo002 | i-0435b9a44d7960176 |
| app002 | i-01c93742d1a75bed0 |
| staging-app001 | i-0547c1a014846e678 |

#### atento-br

| Resource | ID |
|----------|-----|
| VPC | vpc-0411756bd6ff08180 |
| IGW | igw-064485b3436fff428 |
| NAT GW | nat-0d943e24969e7bf4f |
| Peering | pcx-080ff142daa2beadd |
| VGW | vgw-05a609b1a6ea90519 |
| CGW | cgw-056833834b4b1ff85 |
| VPN | vpn-01d9209252778ffb4 |
| SG | sg-00129ae340555e83d |
| ElastiCache | ec-atento-br / ecsg-atento-br |
| mongo000 | i-0396ab33cd3c75cc9 |
| mongo001 | i-092723876822d531e |
| mongo002 | i-08c0ead254780ab83 |
| app002 | i-0ff8b18a6232184e3 |

#### app-atento-br (out variant)

| Resource | ID |
|----------|-----|
| VPC | vpc-0985020bde92bca75 |
| IGW | igw-06df8b5b96e977cc1 |
| NAT GW | nat-03b45836d0effc138 |
| Peering | pcx-0dd23f620fcc6cc77 |
| VGW | vgw-00b1a91d8cbac571e |
| CGW | cgw-0809e4a99bb897447 |
| VPN | vpn-09eedd2abc65556c8 |
| SG | sg-0a2190b262ecfac75 |
| app001 | i-0826b98c20fc2adb9 |
| app002 | i-096cbaf1800e9bca5 |
| app003 | i-00ae1e34d461f6b69 |
| app004 | i-0032f41df6ca8aab5 |
| app005 | i-00e9be1276d53bf50 |

Note: Some resource IDs (subnets, EIPs, route tables for some clients) need to be looked up at import time.

---

## Import Order

1. **aster-maquinas** (pilot — all app servers stopped, lowest risk)
2. **commcenter**
3. **redebrasil**
4. **maqnelson**
5. **almaviva**
6. **atento-br** (redis cache.t3.medium)
7. **app-atento-br** (out variant, uses `modules/app`, 5 app servers)

---

## Validated AWS State (post-cleanup, 2026-02-21)

| Type | Count | Status |
|------|-------|--------|
| VPCs | 7 client + 1 management | All clean |
| VPN Gateways | 7 | 1 per VPC, no detached |
| VPN Connections | 7 | 1 per VPC, all tunnels validated |
| Customer Gateways | 7 | 1 per VPN, no orphans |
| NAT Gateways | 7 | 1 per VPC |
| Internet Gateways | 7 | 1 per VPC, no detached |
| Elastic IPs | 7 | 1 per VPC, no unassociated |
| VPC Peering | 7 | 1 per VPC, all active |
| Route Tables | 14 | 2 per VPC (pub + prv) |
| Subnets | 22 | 3 per integrator + 4 for app |
| Security Groups | 7 | 1 default per VPC |
| ElastiCache | 6 | 1 per integrator client |
| DNS Records | All | Every A/CNAME points to valid resource |
| Management RT | Clean | No blackhole routes remaining |

---

## What Terraform Will NOT Manage

- Host-level config (MongoDB install, Ruby, DataDog, JumpCloud, users) — Ansible/Packer/user-data
- MongoDB replica set initialization — post-provision step
- Application deployment — Capistrano
- Management VPC — referenced by ID only
- `windows-test` instance in atento-br VPC

## What Terraform WILL Manage

All AWS resources per client: VPC, subnets, IGW, NAT, EIP, route tables, routes, peering, VPN (VGW/CGW/connection/routes), security groups, ElastiCache, EC2 instances, Route53 records + zone associations, management return routes.

---

## Known Issues & Decisions

| Issue | Decision |
|-------|----------|
| Ansible PR #61 (VPN routes in private RT) | Bug confirmed — Ansible never added VPN routes to private RT. Terraform handles this correctly via `aws_route.private_vpn` |
| Route53 TTL inconsistency | Some records have TTL 300 (older), some 60 (newer). Terraform standardizes to 60. Import may show TTL change on older records |
| VPC Peering DNS resolution | Set to false (matches current state). Ansible never enabled it |
| `integrator_app_server` module | Dropped — not needed, app servers are part of the main module via `app_servers` map |
| `aws_main_route_table_association` cannot be imported | This resource does NOT support `terraform import` (confirmed: no Import section in [official docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/main_route_table_association), tracked in [provider issue #37813](https://github.com/hashicorp/terraform-provider-aws/issues/37813)). During import of existing clients, `terraform plan` will show this as 1 resource "to create". This is expected and safe to apply — the resource uses the AWS `ReplaceRouteTableAssociation` API which sets the main RT to the private RT, which is already the main RT in all existing client VPCs (confirmed via `aws ec2 describe-route-tables`). The resource is kept in the module because new clients created from scratch via Terraform need it to set the main RT correctly at creation time. |
| `aws_vpn_connection_route` cannot be imported | This resource does NOT support `terraform import` (confirmed: no Import section in [official docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection_route)). During import of existing clients, `terraform plan` will show this as 1 resource "to create". Tested on 2026-02-23: the AWS `CreateVpnConnectionRoute` API is **idempotent** — calling it for a route that already exists returns success with no changes (tested with `aws ec2 create-vpn-connection-route` on aster-maquinas VPN, confirmed route stayed identical via `describe-vpn-connections`). The API only touches static routes, not tunnels, pre-shared keys, or IKE/IPsec config. |
| `aws_route_table_association` import format changed | AWS provider >= 5.0 uses `subnet_id/route_table_id` format (not the old `rtbassoc-xxx` association ID). Example: `terraform import 'module.this.aws_route_table_association.pub_b' subnet-xxx/rtb-xxx`. |
