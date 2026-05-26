# Terraform Project Cross-References Analysis
**Generated:** 2026-03-03  
**Directory:** /Users/plribeiro3000/Projects/4Shark/terraform

## Executive Summary

This analysis reveals how projects reference each other in the 4Shark Terraform codebase. The architecture uses **AWS SSM Parameters** as the primary cross-project communication mechanism, with **hardcoded DNS values** in the DNS project. **NO terraform_remote_state data sources or Terramate remote state references exist.**

---

## Key Finding: Cross-Project Architecture Pattern

### Pattern 1: SSM Parameters for Infrastructure Data (Primary)

**SSM Parameters** are the standard mechanism for sharing infrastructure data between Terraform projects.

**Flow:**
1. **networking/** project creates VPCs, subnets, route tables
2. **networking/ssm.tf** publishes these to AWS SSM Parameter Store
3. Other projects use **modules/networking_data** module to read them back

**Example SSM Parameter Structure:**
```
/networking/{environment}/vpc_id
/networking/{environment}/private_subnet_ids
/networking/{environment}/public_subnet_ids
/networking/{environment}/route_table_private_id
/networking/{environment}/route_table_public_id
/networking/{environment}/nat_gateway_eips
```

**Implementation in Projects:**

File: `/Users/plribeiro3000/Projects/4Shark/terraform/modules/networking_data/main.tf`
```hcl
data "aws_ssm_parameter" "vpc_id" {
  name = "/networking/${var.networking_environment}/vpc_id"
}

data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/networking/${var.networking_environment}/private_subnet_ids"
}

# ... similar for other parameters
```

File: `/Users/plribeiro3000/Projects/4Shark/terraform/modules/networking_data/outputs.tf`
```hcl
output "vpc_id" {
  value = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
}

output "private_ids" {
  value = split(",", nonsensitive(data.aws_ssm_parameter.private_subnet_ids.value))
}
```

### How Projects Use It

File: `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva/main.tf`
```hcl
module "networking_data" {
  source = "../modules/networking_data"
  networking_environment = "integrator-almaviva"
}

module "this" {
  source = "../modules/integrator"
  
  vpc_id                 = module.networking_data.vpc_id
  subnet_pub_b_id        = module.networking_data.public_ids[0]
  subnet_prv_a_id        = module.networking_data.private_ids[0]
  subnet_prv_b_id        = module.networking_data.private_ids[1]
  route_table_private_id = module.networking_data.route_table_private_id
```

---

## Pattern 2: Local Module Composition (for same environment)

Projects in the same environment use local module references to get ALB DNS names and other outputs. This works because they're in the same Terraform state.

File: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/main.tf` (lines 40-70)
```hcl
module "public_alb" {
  source = "../modules/public_alb"
  
  name_prefix       = local.alb_name_prefix
  vpc_id            = module.vpc_data.vpc_id
  subnet_ids        = module.vpc_data.public_ids
  record_name       = var.alb_record_name
  cloudflare_only   = var.cloudflare_only
  alb_ingress_cidrs = var.alb_ingress_cidrs
  tags              = local.tags
  
  # ... other configs
}
```

File: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/locals.tf`
```hcl
{ ALB_HOSTNAME = module.public_alb.alb_dns_name }
```

---

## Pattern 3: Hardcoded DNS Values (for cross-environment)

The **dns/** project hardcodes ALB DNS names in Cloudflare DNS records. These values are extracted from the deployed infrastructure.

File: `/Users/plribeiro3000/Projects/4Shark/terraform/dns/public_dns_app4shark_com.tf`
```hcl
resource "cloudflare_dns_record" "beta001_cname" {
  content  = "beta-001-pub-lb-32118907.us-east-1.elb.amazonaws.com"
  name     = "beta001.app4shark.com"
  proxied  = true
  ttl      = 1
  type     = "CNAME"
  zone_id  = local.cloudflare_zone_ids["app4shark.com"]
}

resource "cloudflare_dns_record" "setup_cname" {
  content  = "setup-pub-lb-1094379503.us-east-1.elb.amazonaws.com"
  name     = "setup.app4shark.com"
  proxied  = true
  ttl      = 1
  type     = "CNAME"
  zone_id  = local.cloudflare_zone_ids["app4shark.com"]
}
```

### Hardcoded ALB DNS Names (Current)

| Environment | Stack | ALB DNS Name | Domain |
|---|---|---|---|
| app-beta-001 | beta-001-pub-lb-32118907 | beta-001-pub-lb-32118907.us-east-1.elb.amazonaws.com | beta001.app4shark.com |
| app-atento-001 | atento-001-pub-lb-2131878159 | atento-001-pub-lb-2131878159.us-east-1.elb.amazonaws.com | atento001.app4shark.com |
| app-demo-001 | demo-001-pub-lb-367378674 | demo-001-pub-lb-367378674.us-east-1.elb.amazonaws.com | demo001.app4shark.com |
| setup | setup-pub-lb-1094379503 | setup-pub-lb-1094379503.us-east-1.elb.amazonaws.com | setup.app4shark.com |
| shared-001 | shared-001-pub-lb-1711668524 | shared-001-pub-lb-1711668524.us-east-1.elb.amazonaws.com | shared001.app4shark.com |
| auth-001 | auth-001 | auth-001-1499755417.sa-east-1.elb.amazonaws.com | auth-001.app4shark.com |

---

## Terramate Configuration

Terramate is configured but **NOT used for remote state or cross-project data sharing**.

File: `/Users/plribeiro3000/Projects/4Shark/terraform/terramate.tm.hcl`
```hcl
terramate {
  required_version = ">= 0.12.0"
  
  config {
    git {
      default_remote = "origin"
      default_branch = "develop"
    }
  }
}
```

### Stack Dependencies

Each stack defines dependencies using the `after` property:

File: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/stack.tm.hcl`
```hcl
stack {
  name        = "app-beta-001"
  description = "Beta 001 ECS application environment"
  id          = "app-beta-001"
  tags        = ["aws", "us-east-1", "app", "mongodbatlas", "rediscloud"]
  after       = ["/shared-resources"]
}
```

File: `/Users/plribeiro3000/Projects/4Shark/terraform/dns/stack.tm.hcl`
```hcl
stack {
  name        = "dns"
  id          = "dns"
  tags        = ["aws", "sa-east-1", "cloudflare", "infra"]
  after       = [
    "/integrator-almaviva",
    "/integrator-aster-maquinas",
    "/integrator-atento-br",
    "/integrator-commcenter",
    "/integrator-maqnelson",
    "/integrator-redebrasil",
    "/app-atento-br",
    "/vpn",
  ]
}
```

**Note:** These dependencies are for **execution order only**, not for data sharing.

---

## Where ALB DNS Names Are Exported

### 1. From Individual Projects (Local Outputs)

File: `/Users/plribeiro3000/Projects/4Shark/terraform/setup/output.tf`
```hcl
output "alb_dns_name" {
  description = "ALB DNS name (use this to create Cloudflare CNAME)"
  value       = module.public_alb.alb_dns_name
}
```

File: `/Users/plribeiro3000/Projects/4Shark/terraform/auth-001/outputs.tf`
```hcl
output "alb_dns_name" {
  value = aws_lb.auth_001.dns_name
}
```

File: `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/output.tf`
```hcl
output "codedeploy_app_name" {
  description = "Nome da aplicação CodeDeploy"
  value       = module.codedeploy_web.app_name
}

# ... but NO alb_dns_name output!
```

**ISSUE DISCOVERED:** app-beta-001's output.tf does NOT export alb_dns_name. This is why the DNS project must use hardcoded values.

---

## Networking SSM Parameters (Available)

File: `/Users/plribeiro3000/Projects/4Shark/terraform/networking/ssm.tf`

Parameters are organized by environment:

**app-beta-001 VPC Parameters:**
```
/networking/app-beta-001/vpc_id
/networking/app-beta-001/vpc_cidr
/networking/app-beta-001/private_subnet_ids
/networking/app-beta-001/public_subnet_ids
/networking/app-beta-001/route_table_private_id
/networking/app-beta-001/route_table_private_a_id
/networking/app-beta-001/route_table_private_b_id
/networking/app-beta-001/route_table_public_id
/networking/app-beta-001/nat_gateway_eips
```

**Other available environments:**
- `production` (us-east-1)
- `beta` (us-east-1)
- `4app-atento` (us-east-1)
- `management` (sa-east-1)
- `integrator-almaviva` (sa-east-1)
- `integrator-redebrasil` (sa-east-1)
- `integrator-maqnelson` (sa-east-1)
- `integrator-commcenter` (sa-east-1)
- `integrator-aster-maquinas` (sa-east-1)
- `integrator-atento-br` (sa-east-1)
- `out-atento-br` (us-east-1)

---

## Modules/Integrator Outputs

File: `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/outputs.tf`

The integrator module exports:
```hcl
output "vpc_id"
output "subnet_pub_b_id"
output "subnet_prv_a_id"
output "subnet_prv_b_id"
output "default_security_group_id"
output "vpn_gateway_id"
output "elasticache_endpoint"
output "mongo_arbiter_private_ip"
output "mongo_primary_private_ip"
output "mongo_secondary_private_ip"
output "app_server_private_ips"
output "app_server_ids"
```

---

## Search Results Summary

### Search 1: terraform_remote_state
**Result:** NO MATCHES found across the entire codebase.

### Search 2: data "terraform_remote_state"
**Result:** NO MATCHES found across the entire codebase.

### Search 3: alb_dns_name References
**Result:** 12 matches found
- Used internally within each project's ECS service definitions
- Exported from `setup/`, `auth-001/`
- **NOT exported from app-beta-001, app-demo-001, app-atento-001, app-shared-001**

### Search 4: Terramate Files
**Result:** 18 .tm.hcl files found
- Root: `terramate.tm.hcl`
- Each stack: `stack.tm.hcl`
- All use `after` dependencies for execution order

### Search 5: SSM Parameters (Networking)
**Result:** 87 aws_ssm_parameter resources in `networking/ssm.tf`
- Infrastructure metadata stored in parameter store
- Structured by environment
- Consumed via `modules/networking_data` module

### Search 6: Generated Files
**Result:** NO files with `_generated`, `generated`, or `_terramate_generated` found.

---

## Current Architecture Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                     NETWORKING PROJECT (sa-east-1)           │
│  Creates VPCs, Subnets, Route Tables, NAT Gateways          │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ├──→ Publishes to SSM Parameter Store
                         │    /networking/{env}/*
                         │
        ┌────────────────┴───────────────────┐
        │                                    │
        ▼                                    ▼
┌──────────────────────────────┐   ┌──────────────────────────────┐
│  APP ENVIRONMENTS (us-east-1) │   │ INTEGRATOR ENVIRONMENTS      │
│  - app-beta-001              │   │ - integrator-almaviva (sa)   │
│  - app-atento-001            │   │ - integrator-redebrasil (sa) │
│  - app-demo-001              │   │ - integrator-maqnelson (sa)  │
│  - app-shared-001            │   │ - integrator-commcenter (sa) │
│  - setup                     │   │ - integrator-aster-maquinas  │
│  - auth-001                  │   │ - integrator-atento-br       │
│                              │   │                              │
│ Uses: modules/networking_data│   │ Uses: modules/networking_data│
│ Reads: SSM Parameters        │   │ Reads: SSM Parameters        │
│ Deploys: ALB + ECS Services  │   │ Deploys: App Servers + VPN   │
└──────────────┬───────────────┘   └──────────────┬───────────────┘
               │                                  │
               └──────────────┬───────────────────┘
                              │
                              ├──→ Outputs local ALB DNS (if exported)
                              │    or hardcoded values
                              │
                              ▼
                    ┌──────────────────────┐
                    │  DNS PROJECT (sa)    │
                    │ - Cloudflare CNAME   │
                    │ - Route53 Internal   │
                    │                      │
                    │ Uses HARDCODED ALB   │
                    │ DNS values (manual)  │
                    └──────────────────────┘
```

---

## Key Insights

1. **No terraform_remote_state used** - The architecture explicitly avoids direct state file references
2. **SSM Parameters are the contract** - Infrastructure metadata is published to SSM for cross-project consumption
3. **Local module composition** - Services within the same environment use local module references
4. **Hardcoded DNS values** - DNS records are manually maintained from deployed ALB outputs
5. **Terramate for orchestration only** - Dependencies control execution order, not data sharing
6. **Regional separation** - App environments in us-east-1, integrators in sa-east-1, requires regional SSM access

---

## Recommendations for app-beta-001

To enable dynamic DNS updates for app-beta-001:

1. **Add alb_dns_name output** to `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/output.tf`
2. **Create SSM parameter** in networking/ssm.tf for app-beta-001 ALB DNS
3. **Update dns project** to read from SSM instead of hardcoded values
4. **Update Terramate dependencies** so dns runs after app environments complete

