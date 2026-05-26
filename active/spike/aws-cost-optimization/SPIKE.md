# SPIKE — AWS Infrastructure Cost Optimization

**Conducted by:** Paulo
**Date:** 2026-03-28
**Status:** Research complete — pending decisions

---

## Goal

Identify the top cost drivers in 4Shark's AWS infrastructure and evaluate concrete optimization opportunities. The monthly bill is ~$4,200 (forecasted $4,688) and rising 7% — this spike dissects every major service to find actionable savings.

---

## Method

- Queried AWS Cost Explorer API for March 2026 (01-28) with breakdowns by service, usage type, and daily granularity
- Inventoried all running resources (EC2, RDS, ElastiCache, ALBs, NAT Gateways, VPN, Transit Gateway, OpenSearch, EIPs)
- Cross-referenced Reserved Instances with actual running instances to detect waste
- Analyzed the egress VPC pattern (sa-east-1) by comparing daily costs before and after deployment

---

## Evidence

### Cost Overview — March 2026 (28 days)

| Service | Cost | % of Total |
|---------|------|------------|
| EC2 - Other (NAT GW, EBS, data transfer) | $1,212 | 28.7% |
| EC2 - Compute | $913 | 21.6% |
| RDS (Aurora + Postgres) | $789 | 18.7% |
| VPC (VPN, TGW, IPv4) | $583 | 13.8% |
| ElastiCache | $314 | 7.4% |
| ECS Fargate | $151 | 3.6% |
| ELB | $112 | 2.7% |
| OpenSearch | $101 | 2.4% |
| Other (S3, CloudWatch, KMS, ECR, etc.) | $46 | 1.1% |
| **Total** | **$4,221** | |

### EC2 - Other ($1,212) — Breakdown

| Item | Cost | % |
|------|------|---|
| NAT Gateway Hours (sa-east-1) — 2 gateways | $330 | 27.2% |
| EBS gp2 Volumes (sa-east-1) | $256 | 21.1% |
| NAT Gateway Data Transfer (us-east-1) | $226 | 18.6% |
| NAT Gateway Hours (us-east-1) — 6 gateways | $158 | 13.0% |
| Data Transfer Regional | $101 | 8.4% |
| NAT Gateway Data Transfer (sa-east-1) | $78 | 6.4% |
| EBS gp3 Volumes (us-east-1) | $52 | 4.3% |
| Other (snapshots, CPU credits) | $12 | 1.0% |

**NAT Gateway subtotal: $791 (65% of EC2-Other)**

### EC2 Compute ($913) — Breakdown

**us-east-1 — 27 running instances:**

| Usage Type | Cost | Notes |
|------------|------|-------|
| t3a.medium on-demand (15 instances) | $479 | App web/workers — NO RI coverage |
| t3a.small on-demand (4 instances) | $62 | PgBouncers + setup |
| t3a.micro on-demand (4 instances) | $27 | PgBouncers |
| t2.medium RI charge (unused) | $60 | No t2 instances running |
| t2.small RI charge (unused) | $7 | No t2 instances running |
| t2.micro RI charge (unused) | $4 | No t2 instances running |
| Data transfer | $7 | |

**sa-east-1 — 18 running, 17 stopped:**

| Usage Type | Cost | Notes |
|------------|------|-------|
| t3.small RI (15 reserved, 11 running) | $162 | MongoDB nodes + integrator apps |
| t3.micro RI (9 reserved, 5 running) | $49 | MongoDB primary nodes |
| t3.medium RI (2 reserved, 1 running) | $43 | Integrator apps |
| t3a.micro on-demand (1 instance) | $11 | VPN server |

**Wasted Reserved Instances (us-east-1):**
- 4× t2.medium + 1× t2.small + 1× t2.micro = **$71/month wasted**
- All instances are t3a family — t2 RIs don't apply
- Expire January 2027 — ~$710 total loss remaining

### Egress VPC Analysis (sa-east-1)

Created March 16. Daily cost comparison:

| Period | NAT/day | TGW/day | Total/day | Monthly |
|--------|---------|---------|-----------|---------|
| Mar 1-15 (before egress) | $18.07 | $0.00 | $18.07 | $560 |
| Mar 18-27 (after egress) | $5.07 | $17.36 | $22.43 | $695 |
| **Difference** | -$13.00 | +$17.36 | **+$4.36** | **+$135** |

**Conclusion: Egress pattern costs ~$135/month MORE than individual NATs in sa-east-1.**

The TGW attachment cost in sa-east-1 ($0.09/hr per attachment × 8) outweighs the NAT savings. Data transfer volume through the integrators is too low (~$0.50/day) for the per-GB savings to compensate.

**For us-east-1, the math is also unfavorable:**
- Current (6 NATs): ~$201/month
- With egress (1 NAT + 7 TGW attachments): ~$294/month
- Would cost $93/month MORE

### RDS ($789) — Breakdown

| Instance | Type | Engine | Cost/month | Notes |
|----------|------|--------|------------|-------|
| app-atento-001-db-1 | db.t4g.large | Aurora PostgreSQL | ~$99 | Writer |
| app-atento-001-db-2 | db.t4g.large | Aurora PostgreSQL | ~$99 | Reader replica |
| app-shared-001-db-1 | db.t4g.large | Aurora PostgreSQL | ~$99 | Writer |
| app-shared-001-db-2 | db.t4g.large | Aurora PostgreSQL | ~$99 | Reader replica |
| Aurora Storage I/O | — | — | $118 | IOPS charges |
| auth-001 | db.t3.small | PostgreSQL Multi-AZ | $99 | sa-east-1 |
| app-demo-001-db-1 | db.t3.medium | Aurora PostgreSQL | $54 | |
| app-beta-001 | db.t3.micro | PostgreSQL | ~$10 | |
| onboarding | db.t3.micro | PostgreSQL | ~$10 | |
| setup | db.t3.micro | PostgreSQL | ~$10 | |
| Storage + backups | — | — | $70 | |
| Performance Insights | — | — | $14 | |

**Reader replicas (atento + shared) cost ~$198/month.** If read distribution is not actively used, these can be removed.

### ElastiCache ($314) — Breakdown

| Cluster | Type | Cost/month |
|---------|------|------------|
| ec-almaviva | cache.t2.small | ~$46 |
| ec-aster-maquinas | cache.t2.small | ~$46 |
| ec-commcenter | cache.t2.small | ~$46 |
| ec-maqnelson | cache.t2.small | ~$46 |
| ec-redebrasil | cache.t2.small | ~$46 |
| ec-atento-br | cache.t3.medium | ~$84 |

5 clusters still on old-generation t2. t3 equivalents offer better performance at lower cost.

### VPC ($583) — Breakdown

| Item | Cost |
|------|------|
| VPN Site-to-Site (7 connections) | $229 |
| Transit Gateway (8 attachments, sa-east-1) | $205 |
| Public IPv4 in-use (sa-east-1, ~22 IPs) | $74 |
| Public IPv4 in-use (us-east-1, ~17 IPs) | $56 |
| Transit Gateway data | $16 |
| Public IPv4 idle (1 EIP: vpn-management) | $3 |

### Other Services

| Service | Cost | Details |
|---------|------|---------|
| ECS Fargate | $151 | sa-east-1 integrators ($145) + us-east-1 ($5) |
| ELB | $112 | 6 ALBs us-east-1 ($80) + 2 ALBs sa-east-1 ($32) |
| OpenSearch | $101 | 2× t3.small.search (app-atento-001) |
| S3 | $15 | |
| CloudWatch | $14 | |

### EIP Inventory

**us-east-1 (18 IPs, all associated):**
- 6 named (NAT Gateways: beta, demo, atento, shared, setup, onboarding)
- 12 unnamed (ALBs, other resources)

**sa-east-1 (6 IPs, 1 idle):**
- egress-sa-east-1-nat-gateway, management-nat-gateway, 4shark-vpn-001-eip
- vpn-management — **IDLE, not associated** ($3.65/month waste)
- 2 unnamed

---

## Conclusions

### Top Cost Drivers

1. **NAT Gateways ($791/month)** — Largest single cost category. Egress pattern in sa-east-1 actually increased costs by ~$135/month vs individual NATs.
2. **EC2 Compute on-demand ($479/month)** — 15 t3a.medium instances with zero Savings Plan coverage.
3. **RDS Aurora ($789/month)** — Reader replicas on atento and shared may be unnecessary ($198/month).
4. **VPN + Transit Gateway ($434/month)** — VPN is fixed cost per integrator. TGW can be eliminated by reverting egress.
5. **ElastiCache old-gen ($230/month)** — 5 clusters on t2.small, should be migrated to t3.
6. **Wasted t2 RIs ($71/month)** — No t2 instances exist. Non-recoverable until Jan 2027.

### Actionable vs Non-Actionable

**Can optimize (total ~$520-580/month):**

| Action | Savings/month | Effort | Risk |
|--------|--------------|--------|------|
| Revert egress → individual NATs (sa-east-1) | ~$135 | Medium | Low — original state |
| Compute Savings Plan 1yr (t3a.medium) | ~$150-180 | Low | Low — commitment |
| Remove Aurora reader replicas (if unused) | ~$198 | Low | Validate read patterns first |
| Migrate ElastiCache t2→t3 | ~$50-80 | Medium | Brief downtime per cluster |
| Release idle EIP vpn-management | ~$4 | Trivial | None |

**Cannot optimize (fixed costs):**

| Item | Cost/month | Reason |
|------|-----------|--------|
| VPN connections | $229 | 1 per integrator, required |
| ALBs | $112 | 1 per environment, required |
| OpenSearch | $101 | Required for atento |
| Wasted t2 RIs | $71 | Locked until Jan 2027 |

---

## Next Steps

- Validate whether Aurora reader replicas (atento, shared) are actively used for read distribution
- Evaluate ElastiCache t2→t3 migration path and downtime window per integrator
- Decide on reverting egress pattern in sa-east-1
- Evaluate Compute Savings Plan commitment level for t3a.medium fleet
- Release idle EIP vpn-management
- When ready to implement, create PLAN.md from selected items

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
