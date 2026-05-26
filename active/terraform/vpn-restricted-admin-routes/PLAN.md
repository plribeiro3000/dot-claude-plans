# Plan: VPN-Restricted Admin Routes (Sidekiq / PgHero)

## Status
BLOCKED — waiting for `feature/vpc-app-beta-001` to merge before implementation.

## Context

The `app` project exposes admin routes (`/sidekiq`, `/pghero`) currently protected
only by application-level authentication. The goal is to restrict these routes at
the infrastructure level so they only respond to traffic originating from the
internal VPN (Pritunl).

## Architecture Decision

**Approach: Internal ALB + ASG Attachment**

VPN users connect via Pritunl (Management VPC: `10.255.0.0/16`), which has VPC
peering with every app environment. An internal ALB, placed in the private subnets
of each app VPC, accepts traffic only from the Management VPC CIDR. The web ASG
registers its instances in both ALBs simultaneously — the public one (managed by
CodeDeploy) and the internal one (attached directly to the ASG, bypassing the
CodeDeploy limitation).

```
Internet → Cloudflare → Public ALB → ECS (all routes)
VPN      → Pritunl   → VPC Peering → Internal ALB → ECS (/sidekiq, /pghero)
```

Admin routes remain accessible on the public ALB (behind app-level auth), but the
definitive security layer is network-level: only VPN-sourced traffic reaches the
internal ALB.

## Why Wait for the Migration Branch

The branch `feature/vpc-app-beta-001` migrates every app environment to a dedicated
VPC and rewrites how networking data is consumed (SSM-backed `networking_data`
module). Implementing the internal ALB before the merge would target the old shared
VPC and require rework immediately after. Waiting costs nothing.

## What the Migration Branch Delivers (Already Done)

- Dedicated VPC per environment (`10.100.4.0/22` for beta-001, etc.)
- VPC peering with Management VPC maintained with routes in both directions
- SSM parameters: `vpc_id`, `vpc_cidr`, `private_subnet_ids`, `public_subnet_ids`,
  `route_table_private_id`, `route_table_public_id`, `nat_gateway_eips`
- `networking_data` module exposes `vpc_cidr` output

## What Still Needs to Be Done

### 1. Route53 Private Hosted Zone (Decision Required)

The `internal_alb` module creates a Route53 CNAME record and requires
`private_zone_id`. This is not included in the migration branch.

**Option A (recommended):** Add one `aws_route53_zone` (private) per app environment
in the `networking/` module and publish the zone ID to SSM alongside other
networking data. Keeps all network infrastructure centralized.

**Option B:** Make the Route53 record optional in `internal_alb` (add `count` guard)
and access the ALB via its AWS-generated DNS name. Simpler but less ergonomic for
engineers connecting via VPN.

### 2. Instantiate `internal_alb` in each app environment `main.tf`

~15 lines per environment (`app-beta-001`, `app-demo-001`, `app-atento-001`,
`app-shared-001`):

```hcl
module "internal_alb" {
  source            = "../modules/internal_alb"
  name_prefix       = "${var.environment}-int"
  vpc_id            = module.vpc_data.vpc_id
  subnet_ids        = module.vpc_data.private_ids
  alb_ingress_cidrs = ["10.255.0.0/16"]  # Management VPC (Pritunl)
  private_zone_id   = var.private_zone_id # from SSM or Option B: omit
  record_name       = var.internal_alb_record_name
  tags              = local.tags
}
```

### 3. ASG Attachment for Web Service

~8 lines per environment. Attaches the web ASG directly to the internal target
group, bypassing the CodeDeploy restriction on load balancers in ECS service config:

```hcl
resource "aws_autoscaling_attachment" "web_internal" {
  autoscaling_group_name = module.capacity_web.asg_name
  lb_target_group_arn    = module.internal_alb.target_group_arn
}
```

### 4. Security Group Rule

~6 lines per environment. Allow the internal ALB SG to reach the ECS cluster SG
on port 3000.

### 5. New Variables

Add to each environment's `variables.tf`:
- `private_zone_id` (if Option A chosen)
- `internal_alb_record_name`

## Effort Estimate

~40-50 lines of Terraform per environment, all in existing files. Four environments
means ~160-200 lines total plus the Route53 decision (Option A adds ~20 lines in
`networking/`, Option B adds ~5 lines to `internal_alb/main.tf`).

Overall effort: **Low**. No new modules needed — `internal_alb` is already built
and production-ready.

## Open Questions

1. **Route53 option A or B?** Needs a decision before implementation starts.
2. **Scope:** Apply to all four app environments at once, or start with beta-001
   and roll out progressively?
3. **App-level auth:** Keep existing Sidekiq/PgHero authentication as a second
   layer after network restriction, or remove it once network control is in place?

## References

- Internal ALB module: `terraform/modules/internal_alb/`
- VPN: `terraform/vpn/` (Pritunl, Management VPC `10.255.0.0/16`)
- VPC peering: `terraform/networking/peering.tf` (all app VPCs peered with Management)
- Migration branch: `origin/feature/vpc-app-beta-001`
