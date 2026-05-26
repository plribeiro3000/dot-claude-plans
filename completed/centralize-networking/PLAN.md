# Centralize Networking in Terraform

## Context

All AWS networking (VPCs, subnets, peering, VPN) is scattered across multiple Terraform states and some resources are unmanaged entirely. This creates:
- **No single source of truth** for the network topology
- **Duplicate state ownership** of peering connections (auth-001 AND integrator-* both manage the same AWS resources)
- **Implicit dependencies** via tag-based lookups (`vpc_data` module)
- **Risk of accidental destruction** when two states own the same resource

The `dns/` project already demonstrates the centralized pattern: one folder with its own state managing all DNS resources. We replicate this for networking, adding SSM Parameter Store for explicit cross-state contracts.

## Decision Log

| Decision | Choice | Rationale |
|---|---|---|
| Cross-state communication | SSM Parameter Store | Explicit contracts, HashiCorp recommended, cross-tool compatible |
| Multi-region strategy | Single `networking/` folder with provider aliases | Cross-region peering needs references to both regions; follows dns/ pattern; manageable resource count (~150) |
| Default provider region | sa-east-1 | Hub VPC (Management) is there; 8 of 12 VPCs are there; all peering involves Management |
| Route management | Separate `aws_route` resources + `lifecycle { ignore_changes = [route] }` on route tables | Allows other states (integrator VPN routes) to add routes without conflict |
| VPN connections | Stay in integrator-\* states | Customer-specific, tightly coupled to customer configs; high blast radius if centralized |
| Peering connections | Centralized in networking/ | Resolves duplicate ownership between auth-001 and integrator-\*; natural part of network topology |
| Integrator module refactoring | Required — modules accept VPC/subnet IDs instead of creating them | Eliminates duplicate resource creation; follows dependency inversion |
| Beta S3 VPC Endpoint | Managed by networking/ | Part of the VPC networking layer |
| Blackhole routes (Production) | Cleaned up during import | Reference deleted peering pcx-07ce30a23d5c62aaf |

## Complete Network Inventory

### us-east-1 (Virginia)

| VPC Name | CIDR | VPC ID | Used By |
|---|---|---|---|
| **Production** | 10.254.0.0/16 | vpc-0204a1f8b5de51941 | app-demo-001, app-shared-001, app-atento-001, setup |
| **Beta** | 10.154.0.0/16 | vpc-0968cc73edd5596b0 | app-beta-001 |
| **4app-atento** | 10.2.1.0/24 | vpc-0331320cef3e08143 | app-atento-001 (needs verification) |
| Default VPC | 172.30.0.0/16 | vpc-0b51d809d6bd9961e | Not managed — excluded from scope |

### sa-east-1 (São Paulo)

| VPC Name | CIDR | VPC ID | Used By |
|---|---|---|---|
| **Management** | 10.255.0.0/16 | vpc-0bdc76f3b391694dd | auth-001, vpn |
| **4client-almaviva** | 10.1.0.0/24 | vpc-0c197605716f3a46a | integrator-almaviva |
| **4client-redebrasil** | 10.1.1.0/24 | vpc-01e23ad5ed29fbbbf | integrator-redebrasil |
| **4client-maqnelson** | 10.1.2.0/24 | vpc-0d8b6d6a5819c0b21 | integrator-maqnelson |
| **4client-commcenter** | 10.1.3.0/24 | vpc-02e007218ef28a0d4 | integrator-commcenter |
| **4client-aster-maquinas** | 10.1.4.0/24 | vpc-01af82a1bea1ba1fc | integrator-aster-maquinas |
| **4client-atento-br** | 10.12.255.0/24 | vpc-0411756bd6ff08180 | integrator-atento-br |
| **4client-out-atento-br** | 10.12.0.0/26 | vpc-0985020bde92bca75 | app-atento-br |

### VPC Peering Connections (10 active, hub-and-spoke via Management)

| Peering ID | Requester | Accepter | Type | Name |
|---|---|---|---|---|
| pcx-0d8b42289e7030f61 | Production (us-east-1) | Management (sa-east-1) | cross-region | production-management |
| pcx-0ac1851979c0a8730 | Management (sa-east-1) | Beta (us-east-1) | cross-region | (unnamed) |
| pcx-0e6e37042c51b363e | 4app-atento (us-east-1) | Management (sa-east-1) | cross-region | (unnamed) |
| pcx-078cff15e5c534ca3 | 4client-almaviva | Management | same-region | 4client-almaviva-management |
| pcx-0d2b3cbed169074e4 | 4client-redebrasil | Management | same-region | 4client-redebrasil-management |
| pcx-0cfc2971e1dedf0cc | 4client-maqnelson | Management | same-region | 4client-maqnelson-management |
| pcx-0660dcb38076bd208 | 4client-commcenter | Management | same-region | 4client-commcenter-management |
| pcx-0a31bb4f931e55651 | 4client-aster-maquinas | Management | same-region | 4client-aster-maquinas-management |
| pcx-080ff142daa2beadd | 4client-atento-br | Management | same-region | 4client-atento-br-management |
| pcx-0dd23f620fcc6cc77 | 4client-out-atento-br | Management | same-region | 4client-out-atento-br-management |

### Site-to-Site VPN Connections (7 — all in sa-east-1)

| Client | Customer Gateway IP | Customer Network CIDRs | VPC |
|---|---|---|---|
| almaviva | 177.86.255.29 | 10.0.0.0/24, 172.16.255.9/32 | 4client-almaviva |
| redebrasil | 200.182.4.34 | 172.16.16.0/21 | 4client-redebrasil |
| maqnelson | 186.237.197.117 | 192.168.90.0/26 | 4client-maqnelson |
| commcenter | 200.196.250.228 | 10.130.2.0/23 | 4client-commcenter |
| aster-maquinas | 200.106.188.44 | 10.6.11.0/24 | 4client-aster-maquinas |
| atento-br | 48.214.37.228 | 10.101.30.0/24 | 4client-atento-br |
| out-atento-br | 177.22.252.45 | 10.155.0.152/32, 10.189.0.162/32 | 4client-out-atento-br |

## Current Terraform State Ownership

| Resource | Current State | Target State |
|---|---|---|
| Production VPC + networking | **UNMANAGED** | networking/ |
| Beta VPC + networking | **UNMANAGED** | networking/ |
| 4app-atento VPC + networking | **UNMANAGED** (needs verification) | networking/ |
| Management VPC + networking | auth-001/ | networking/ |
| 6x Integrator VPCs + networking | integrator-\*/ (inside module) | networking/ |
| 1x App VPC (out-atento-br) + networking | app-atento-br/ (inside module) | networking/ |
| 9x Peering connections (auth-001 side) | auth-001/ | networking/ |
| 7x Peering connections (integrator side) | integrator-\*/ (DUPLICATE) | networking/ |
| 1x Peering connection (app-atento-br side) | app-atento-br/ (DUPLICATE) | networking/ |
| 1x Peering connection (Beta↔Management) | **UNKNOWN** — not in auth-001 | networking/ |
| Peering routes in Management pub RT | auth-001/ + integrator-\*/ (DUPLICATE) | networking/ |
| 7x VPN connections (VGW, CGW, VPN, routes) | integrator-\*/ | integrator-\*/ (stays) |
| 1x VPN connection (out-atento-br) | app-atento-br/ | app-atento-br/ (stays) |
| OpenVPN routes in Management (100.80/100.96) | auth-001/ | auth-001/ (stays — tied to Pritunl ENI) |

### Critical Issue: Duplicate Peering Ownership

**auth-001/peering.tf** creates 9 peering connections + 9 routes in Management's public route table.

**integrator-\*/modules/integrator/peering.tf** creates the SAME peering connection + a "return route" in the Management route table (passed via `management_route_table_ids`).

**app-atento-br/modules/app/peering.tf** does the same for out-atento-br.

This means each integrator/app peering connection and its Management route exist in TWO Terraform states simultaneously. If either state runs `terraform destroy` or drifts, it will destroy the real AWS resource and break the other state.

**Resolution**: During migration, remove from BOTH states first, then import into networking/ as the single owner.

## Architecture

### networking/ folder structure (actual — flat layout)

```
terraform/networking/
├── providers.tf                    # sa-east-1 (default) + us-east-1 (alias)
├── locals.tf                       # Common tags, naming conventions
├── stack.tm.hcl                    # Terramate stack config
├── import.sh                       # Import script (~206 resources)
│
├── vpc_production.tf               # Production VPC (us-east-1) + subnets + IGW + NAT + EIP + RTs + routes
├── vpc_beta.tf                     # Beta VPC (us-east-1) + subnets + IGW + NAT + EIP + RTs + routes + S3 VPC endpoint
├── vpc_4app_atento.tf              # 4app-atento VPC (us-east-1) + subnets + IGW + RT + routes
├── vpc_management.tf               # Management VPC (sa-east-1) + subnets + IGW + NAT + EIP + RTs + routes
├── vpc_almaviva.tf                 # 4client-almaviva VPC + subnets + IGW + NAT + EIP + RTs
├── vpc_redebrasil.tf               # 4client-redebrasil ...
├── vpc_maqnelson.tf                # 4client-maqnelson ...
├── vpc_commcenter.tf               # 4client-commcenter ...
├── vpc_aster_maquinas.tf           # 4client-aster-maquinas ...
├── vpc_atento_br.tf                # 4client-atento-br ...
├── vpc_out_atento_br.tf            # 4client-out-atento-br ...
│
├── peering.tf                      # All 10 peering connections + routes in all directions
├── ssm.tf                          # SSM parameters (both regions)
└── outputs.tf                      # Terraform outputs
```

### providers.tf

```hcl
provider "aws" {
  region = "sa-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
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
    key    = "networking/terraform.tfstate"
    region = "us-east-1"
  }
}
```

### SSM parameter naming convention

```
/networking/{environment}/vpc_id
/networking/{environment}/vpc_cidr
/networking/{environment}/private_subnet_ids       (comma-separated)
/networking/{environment}/public_subnet_ids        (comma-separated)
/networking/{environment}/route_table_private_id   (for integrators that add VPN routes)
/networking/{environment}/route_table_public_id
/networking/{environment}/peering_connection_id    (to Management)
```

Environments: `production`, `beta`, `4app-atento`, `management`, `integrator-almaviva`, `integrator-redebrasil`, `integrator-maqnelson`, `integrator-commcenter`, `integrator-aster-maquinas`, `integrator-atento-br`, `out-atento-br`

SSM parameters are published **in the same region as the VPC** so that consumers (which use the same region provider) can read them:
- us-east-1 SSM: production, beta, 4app-atento
- sa-east-1 SSM: management, all integrators, out-atento-br

### networking_data module

```
terraform/modules/networking_data/
├── main.tf         # SSM data sources
├── variables.tf    # Input: environment
└── outputs.tf      # vpc_id, vpc_cidr, private_ids, public_ids, route_table_private_id (same interface as vpc_data + extras)
```

Consumer projects switch from:
```hcl
module "vpc_data" {
  source             = "../modules/vpc_data"
  vpc_name           = var.vpc_name
  subnet_name_prefix = var.subnet_name_prefix
}
```

To:
```hcl
module "vpc_data" {                          # Keep module name to avoid touching downstream refs
  source                  = "../modules/networking_data"
  networking_environment  = var.networking_environment
}
```

Outputs remain compatible: `module.vpc_data.vpc_id`, `module.vpc_data.private_ids`, `module.vpc_data.public_ids`.

## Phases

### Phase 1: Create networking/ — Write all code + import everything ✅ COMPLETE

**Completed:** 2026-03-01 — PR #203 merged into develop.

**What was done:**
- Created all 17 files in `networking/` (flat layout, no region subdirectories)
- Imported ~206 resources via `import.sh` script
- Fixed all drift to achieve exact match with AWS state (zero changes on `terraform plan`)
- SSM parameters created for all 11 environments (66 parameters across both regions)
- All route tables use `lifecycle { ignore_changes = [route] }` to allow other states to add routes
- All us-east-1 resources use `provider = aws.us_east_1`

**Key findings during implementation:**
- Both Production NAT gateways are in the same subnet (`production_pub_a`), not one per AZ as expected
- Beta VPC has legacy names (IGW: "Staging-igw", VPC endpoint: "Staging-vpce-s3")
- 4app-atento public subnets have `map_public_ip_on_launch = false` (not true as initially assumed)
- Several Name tags in AWS differ from what was expected (production EIPs have no Name, beta EIP has no Name, app_atento NAT has no Name)
- All integrator resources have `Client` tags that must be included on every resource
- Cross-region peering connections (beta, app_atento) have no Name tags in AWS

**Final state:** `terraform plan` → "No changes. Your infrastructure matches the configuration."

### Phase 2: Remove from old states + migrate consumers ✅ COMPLETE

**Completed:** 2026-03-01 — PR #204 merged into develop.

**What was done:**
- Created `modules/networking_data/` module with SSM-based lookups (vpc_id, vpc_cidr, private_ids, public_ids, route_table_private_id, route_table_public_id)
- All outputs wrapped with `nonsensitive()` to prevent sensitive value propagation from SSM data sources
- Removed 171 networking resources from 8 project states via `terraform state rm`:
  - auth-001: 36 resources (Management VPC + 9 peering connections + 9 peering routes)
  - 6 integrators: 19 resources each (114 total)
  - app-atento-br: 21 resources
- Updated all 13 consumer projects to use `networking_data` module
- Refactored integrator/app modules to accept VPC/subnet IDs as inputs instead of creating them
- Gate passed: `terraform plan` on all 13 projects showed zero infrastructure changes

### Phase 3: Networking standardization ✅ COMPLETE

**Completed:** 2026-03-01 — PR #205 merged into develop.

**What was done:**
- Removed dead `locals.tf` (unused `locals.tags` block)
- Fixed Management VPC EIP tag from `"production-nat-gateway"` to `"management-nat-gateway"` (copy-paste error)
- Standardized 6 integrator `public_subnet_ids` SSM parameters from plain string to `join(",", [...])` format for consistency with multi-subnet environments

**Deferred items (require destroy/recreate):**
- Management VPC subnet AZ redistribution (pub_a in sa-east-1c instead of sa-east-1a)
- Integrator subnet naming (pub_b instead of pub_a)
- These carry downtime risk and are not worth pursuing at this time

## Resource Count Summary (actual after Phase 1)

| Category | Count |
|---|---|
| Imported resources | ~206 |
| SSM Parameters (created) | 66 |
| **Total managed resources** | **~272** |

Breakdown: 11 VPCs, ~40 subnets, 11 IGWs, ~12 NAT GWs, ~12 EIPs, ~25 route tables, ~40 route table associations, ~25 default routes, 10 peering connections, ~30 peering routes, 1 VPC endpoint (Beta S3), 66 SSM parameters.

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|---|---|---|---|
| Import writes wrong attributes | TF tries to modify existing resources | Medium | Gate: plan must show zero infra changes before apply |
| Integrator module refactoring breaks VPN | Site-to-site VPN drops | Medium | VPN resources don't move — only the VPC reference changes. Gate check per integrator |
| Cross-region provider misconfiguration | Resources created in wrong region | Low | Explicit `provider = aws.us_east_1` on all us-east-1 resources |
| SSM parameter values incorrect | Consumer gets wrong VPC/subnet IDs | Low | Values reference imported resources directly, not hardcoded |
| Management VPC migration breaks auth-001 | Keycloak, Pritunl disruption | Medium | Auth-001 retains OpenVPN routes; VPC references switch to SSM |

## Rollback Plan

- **Phase 1** ✅ Merged (PR #203) — currently active, no rollback needed. If ever needed: `terraform state rm` all resources from networking/ state + delete SSM parameters. VPCs continue in AWS unchanged, old states still own them.
- **Phase 2** ✅ Merged (PR #204) — no rollback needed. If ever needed: re-import resources into old states, revert module source to `../modules/vpc_data`, revert integrator/app module refactoring.
- **Phase 3** ✅ Merged (PR #205) — tag/SSM format fixes only, trivially revertible.
