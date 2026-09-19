# Cost baseline per project — pre-tag-activation estimate

Measurement window: 2026-08-18 → 2026-09-18 (daily), AWS account 405749097490. All figures USD.

This is the cost picture **before** the cost allocation tags are active. The `Entity`/`Project`/`Client` tags are applied on resources but not yet activated in Billing (activation is a separate step, scheduled after the first tagged stack was live), so Cost Explorer cannot filter by project — every cost lands in an untagged bucket. The per-service and per-region numbers here are real (Cost Explorer `get-cost-and-usage`, `UnblendedCost`); the per-project and per-stack split is an estimate built by cross-referencing that real spend with the resource inventory and reconciling to the real total. Once the tags populate (~2 days after activation), the exact per-stack numbers replace this estimate.

The companion `COST-BASELINE-2026-09-18.html` renders the same data for reading.

## Daily total — median is the typical day

| Metric (daily cost, 30 days) | USD/day |
|---|---|
| Median (typical day) | 137.9 |
| Mean | 153.7 |
| Minimum | 130.9 |
| Maximum (1 day) | 464.4 |

The mean sits ~16 above the median because a single day hit 464.4 — on that day `EC2 - Compute` jumped from its typical ~22 to ~336 (a hard ASG scale-up or a heavy processing night; the specific day is worth identifying). Outside that spike the real day is stable at 131–140. The median (137.9) is the number to use per day; monthly run-rate ≈ 4,140.

Two non-daily charges are excluded from the typical day: Amazon Registrar 16 (one-time domain renewal) and a one-off S3 spike (~25 on a single day).

## Per project — estimate

| Project | USD/day | USD/month | Share |
|---|---|---|---|
| app (4 environments + outbound + poolers) | ~82 | ~2,460 | ~60% |
| integrator (4 clients) | ~38 | ~1,140 | ~27% |
| setup + onboarding | ~6 | ~180 | ~4% |
| vpn | ~4 | ~120 | ~3% |
| authenticator (auth-001) | ~3 | ~90 | ~2% |
| other (us-west-2, global, KMS/S3 residual) | ~3 | ~90 | ~2% |

Per-project uncertainty ~±20% (the EC2-Other / NAT / CloudWatch allocation is approximate). The robust conclusion: **app is ~3/5 of the account, integrator is the second at ~1/4, everything else is small.**

## Per stack — estimate

| app stack | USD/day |
|---|---|
| atento-001 | ~33 |
| shared-001 | ~31 |
| demo-001 | ~8 |
| beta-001 | ~6 |
| connection-poolers (4) | ~3 |
| outbound (maqnelson + atento-br) | ~1 |

atento-001 and shared-001 are the twin heavyweights: each has 2× Aurora `db.t4g.large`, one OpenSearch domain and ~8–10 ASG instances. The outbound stacks are at `desired_count = 0`.

| integrator stack | USD/day |
|---|---|
| atento (br/co/cl/mx) | ~24 |
| commcenter | ~6 |
| almaviva | ~3.5 |
| maqnelson | ~3 |

atento concentrates the integrator spend: 3 Mongo nodes + a windows-machine + the largest Redis (`cache.t3.medium`) + 4 country clusters. almaviva and maqnelson have their Mongo **stopped** most of the day (started nightly by cron), so they cost less on an idle day and more on a processing night.

## Real data — by service (median daily, 30 days)

| Service | USD/day (median) | Note |
|---|---|---|
| EC2 - Other (EBS, NAT data, transfer, IPv4) | 30.36 | spread |
| RDS (Aurora) | 26.79 | app |
| EC2 - Compute | 22.23 | app + integrator; one day spiked to 335.78 |
| VPC (NAT/VPN/endpoints) | 13.09 | spread |
| ECS (Fargate) | 10.57 | integrator / poolers / auth |
| ElastiCache | 8.11 | integrator |
| OpenSearch | 7.17 | app |
| Load Balancing | 6.85 | app / integrator / auth |
| CloudWatch | 6.65 | app-heavy |
| Backup | 1.50 | app-heavy (RDS/Aurora) |
| KMS · S3 · ECR · Secrets | ~3.6 | spread |

## Real data — by region (14-day daily average)

| Region | USD/day | What lives there |
|---|---|---|
| us-east-1 | 74.3 | apps, onboarding, setup, connection-poolers |
| sa-east-1 | 58.8 | integrators, vpn, outbound, auth-001, Mongo |
| us-west-2 | 2.0 | residual (to investigate) |
| global | 0.1 | Route 53 |

## Attribution method and the inventory it rests on

- **app** — all RDS Aurora (app-atento-001 and app-shared-001 at 2× `db.t4g.large` each, app-demo-001 at `db.t3.medium`, app-beta-001 at `db.t3.micro`), both OpenSearch domains (app-atento-001, app-shared-001), the EC2 ASG fleet (~20× `t3a.medium` in us-east-1 running web/worker), the 4 Fargate connection-poolers, and the environment ALBs.
- **integrator** — all ElastiCache (4 Redis in sa-east-1; apps use external Redis Cloud, not ElastiCache — this is the correction that moved ElastiCache off app), the Mongo nodes on EC2, the nightly Fargate windows, and the customers' site-to-site VPNs.
- **vpn** — the 2 EC2 hosts behind the `management` VPC (Pritunl + its Mongo) plus that VPC's NAT and VPN.
- **authenticator** — the `auth-001` cluster (2 Fargate tasks 24/7, sa-east-1) plus its ALB.
- EC2-Other, NAT/VPC, CloudWatch and KMS/S3/ECR are prorated by resource footprint — the largest source of uncertainty.

## Open items

- The 464.4 spike day (EC2-Compute ~336) is unexplained — identify the day and the cause.
- The us-west-2 ~2/day residual has no obviously mapped stack — identify what runs there.
- After tag activation populates, replace the estimate columns with the real per-`Client`/`Entity` Cost Explorer numbers and record the delta against this baseline.
