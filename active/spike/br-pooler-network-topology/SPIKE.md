# SPIKE — BR Pooler Network Topology

## Investigation question

Where should the Brazil (sa-east-1) PgBouncer connection pooler's network live, and what is the right topology to serve potentially multiple Brazil-side consumers reaching one or more us-east-1 RDS databases?

Context: `app-atento-001` migration (Phase 0 open item #1 in TASKS.md). The atento-001 stack deploys a payroll/runner worker on sa-east-1 Fargate (`app-outbound-atento-br`, 10.12.0.0/26). The us-east-1 pooler being built for the atento-001 app services cannot be reached by this sa-east-1 worker without new networking. The question is whether to build a BR-side pooler and, if so, where to network it.

## Sources consulted

- `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:16-18` — Phase 0 open item #1 verbatim: sa-east-1 payroll worker blocker
- `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/PLAN.md` — shared-001 architecture record: session pooling, static userlist, md5, `4shark.internal` CNAME, PHZ association requirement
- `terraform/networking/transit_gateway.tf:23-66` — TGW spoke_rt design: single route `0.0.0.0/0 → egress`; no intra-spoke routing
- `terraform/networking/peering.tf:490-569` — app-outbound-atento-br ↔ Management peering; cross-region Management ↔ app-atento-001 peering; NO direct peering between the two
- `terraform/networking/vpc_app_outbound_atento_br.tf:5-137` — VPC CIDR 10.12.0.0/26; both route tables have `lifecycle { ignore_changes = [route] }`; private default → TGW
- `terraform/app-atento-001/rds.tf:23-53` — Aurora SG: ingress 5432 only from 10.100.12.0/22 and 10.255.0.0/16
- `terraform/modules/atento_001_task_config/main.tf:85-88` — shared SSM ARN pattern: both us-east-1 and sa-east-1 stacks fetch identical SSM ARNs in us-east-1
- `terraform/networking/vpc_egress_sa_east_1.tf:126-130` — maqnelson CIDR = 10.1.2.0/24; return route in egress pub table confirms TGW attachment
- See auxiliary: `br-pooler-network-topology_excerpt_1.tf` — annotated Terraform excerpts from all 7 source files above, proving the networking facts
- [https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/) — cross-region PrivateLink requirements: NLB-only, Interface endpoint only, traffic on AWS backbone
- [https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/](https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/) — NLB + PrivateLink pattern for cross-VPC RDS access
- [https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-aws-network-infrastructure/centralized-access-to-vpc-private-endpoints.html](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-aws-network-infrastructure/centralized-access-to-vpc-private-endpoints.html) — hub-spoke shared services pattern; PHZ per-VPC association requirement; blast-radius warning
- [https://blog.sagarregmi.info.np/transaction-pooling-the-multi-tenant-nightmare](https://blog.sagarregmi.info.np/transaction-pooling-the-multi-tenant-nightmare) — transaction pooling search_path leakage between tenants
- [https://www.pgbouncer.org/features.html](https://www.pgbouncer.org/features.html) — official pooling mode docs; transaction pooling "breaks session-based features"
- [https://www.revenuecat.com/blog/engineering/pgbouncer-on-aws-ecs/](https://www.revenuecat.com/blog/engineering/pgbouncer-on-aws-ecs/) — canonical ECS PgBouncer pattern (same-VPC pooler + ECS Service Discovery)
- See auxiliary: `br-pooler-network-topology_doc_1.md` — verbatim quotes from all web sources, with fetch confirmation and context notes

## Findings

### Finding 1: The sa-east-1 worker has no private path to the us-east-1 Aurora RDS today

**Evidence:**

From `terraform/app-atento-001/rds.tf:23-53` (see `br-pooler-network-topology_excerpt_1.tf` lines 116-136):

```hcl
ingress {
  description = "PostgreSQL from VPC"
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  cidr_blocks = [module.vpc_data.vpc_cidr]  # = 10.100.12.0/22
}
ingress {
  description = "PostgreSQL from VPN (Management VPC)"
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  cidr_blocks = ["10.255.0.0/16"]
}
# No ingress for 10.12.0.0/26 (app-outbound-atento-br)
```

Confirmed separately:
- RDS `publicly_accessible = false` (`terraform/app-atento-001/rds.tf:55-59`)
- No direct VPC peering between `app-outbound-atento-br` (10.12.0.0/26) and `app-atento-001` (10.100.12.0/22) (`terraform/networking/peering.tf:490-569`)
- TGW spoke_rt has only `0.0.0.0/0 → egress VPC`; no intra-spoke route (`terraform/networking/transit_gateway.tf:62-66`)
- VPN in `app-outbound-atento-br` routes only to `10.155.0.152/32` and `10.189.0.162/32` (Atento corporate); no AWS CIDR (`terraform/app-outbound-atento-br/main.tf`, reproduced in aux file lines 157-158)
- VPC peering is not transitive: `app-outbound-atento-br` can reach Management (10.255.0.0/16) via peering, and Management can reach `app-atento-001` (10.100.12.0/22) via cross-region peering — but packets cannot transit through a peering; Management acts as a connection hub only for VPN (OS-layer routing), not for application traffic

**Source:** `terraform/app-atento-001/rds.tf:23-53`, `terraform/networking/transit_gateway.tf:62-66`, `terraform/networking/peering.tf:490-569`, `terraform/app-outbound-atento-br/main.tf`, `terraform/networking/vpc_app_outbound_atento_br.tf:83-98`

**Significance:** Any solution — Candidate 1 (maqnelson), Candidate 2 (dedicated VPC), Candidate 3 (maqnelson first) — that deploys a new BR-side pooler must ALSO establish a new cross-region private path from the pooler VPC to the us-east-1 RDS. The candidates differ in WHERE the pooler lives, not in whether this cross-region path work is required. Candidate 4 (PrivateLink) is the only option that avoids this new cross-region path entirely.

---

### Finding 2: TGW spoke route table has no intra-spoke routing; integrator VPCs cannot communicate through TGW

**Evidence:**

From `terraform/networking/transit_gateway.tf:62-66` (see `br-pooler-network-topology_excerpt_1.tf` lines 17-21):

```hcl
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke_rt.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.egress_sa_east_1.id
}
```

This is the only route in `spoke_rt`. There are no entries for any spoke CIDR (`10.1.0.0/24`, `10.1.2.0/24`, `10.12.0.0/26`, etc.).

**Source:** `terraform/networking/transit_gateway.tf:62-66`

**Significance:** Placing the BR pooler inside the maqnelson VPC (Candidate 1) does not automatically give other sa-east-1 consumers (integrators, other `app-outbound-*` VPCs) access to it via TGW. Each additional consumer would require either (a) a new TGW intra-spoke route entry in `spoke_rt` pointing the pooler VPC CIDR to the pooler's TGW attachment — changing the existing egress-only spoke design — or (b) a new VPC peering between each consumer and maqnelson. Neither is free. This constraint applies identically to Candidate 2 (dedicated pooler VPC): reaching the pooler from other consumers still requires the same work (new TGW route or new peering). The difference is that Candidate 2's pooler VPC is dedicated and isolated; Candidate 1's is shared with maqnelson workloads.

---

### Finding 3: Both app-outbound-atento-br route tables have lifecycle ignore_changes=[route] — routes exist outside Terraform

**Evidence:**

From `terraform/networking/vpc_app_outbound_atento_br.tf:83-98` (see `br-pooler-network-topology_excerpt_1.tf` lines 38-48):

```hcl
resource "aws_route_table" "app_outbound_atento_br_pub" {
  vpc_id = aws_vpc.app_outbound_atento_br.id
  lifecycle {
    ignore_changes = [route]  # VGW + Pritunl out-of-band routes managed outside Terraform
  }
}
resource "aws_route_table" "app_outbound_atento_br_prv" {
  vpc_id = aws_vpc.app_outbound_atento_br.id
  lifecycle {
    ignore_changes = [route]
  }
}
```

VPN static routes (`terraform/app-outbound-atento-br/main.tf`): `customer_network_cidrs = ["10.155.0.152/32", "10.189.0.162/32"]` — Atento corporate endpoints only.

**Source:** `terraform/networking/vpc_app_outbound_atento_br.tf:83-98`, `terraform/app-outbound-atento-br/main.tf`

**Significance:** The `ignore_changes` confirms that VGW (Site-to-Site VPN) and Pritunl (OpenVPN) routes exist in these route tables outside Terraform. The VPN routes go to Atento's corporate network — not to any AWS us-east-1 CIDR. Therefore VPN cannot serve as the cross-region path to the RDS or to a us-east-1 pooler. The `ignore_changes` also means that any new Terraform route added to these tables (e.g., pointing to a BR pooler CIDR) would be tracked, but the existing out-of-band routes would remain invisible in `terraform plan`. This is operational complexity, not a blocker.

---

### Finding 4: The shared atento_001_task_config module delivers identical SSM ARNs to both the us-east-1 app and the sa-east-1 worker

**Evidence:**

From `terraform/modules/atento_001_task_config/main.tf:85-88` (see `br-pooler-network-topology_excerpt_1.tf` lines 146-149):

```hcl
secrets = [for name in local.secret_names : {
  name      = name
  valueFrom = "arn:aws:ssm:us-east-1:405749097490:parameter/atento-001/${name}"
}]
```

Both the us-east-1 (`app-atento-001`) stack and the sa-east-1 (`app-outbound-atento-br`) stack call this module, resulting in both reading from `/atento-001/DATABASE_URL` and `/atento-001/DATABASE_REPLICA_URL` in us-east-1.

TASKS.md Phase 4 note (`~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:56`):

> "Respect the sa-east-1 worker decision from Phase 0 (don't repoint a param the sa-east-1 worker shares if it can't reach the pooler)."

**Source:** `terraform/modules/atento_001_task_config/main.tf:85-88`, `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:56`

**Significance:** A naive SSM host swap (host → us-east-1 pooler CNAME) propagates simultaneously to the sa-east-1 worker. If the sa-east-1 worker cannot resolve `pgbouncer-atento-001.4shark.internal` (PHZ not associated with its VPC) or route TCP/5432 to the pooler, the worker fails at next task restart. Any BR-side solution that allows the sa-east-1 worker to reach the pooler via the SAME SSM param simplifies the cutover: no SSM split required. Candidate 4 (PrivateLink) is the only option where this is naturally true — the Interface endpoint resolves to a private IP inside the consumer's own VPC, so no PHZ association is needed and the SSM param value stays in us-east-1.

---

### Finding 5: Cross-region PrivateLink (Candidate 4) allows sa-east-1 consumers to reach a us-east-1 NLB-backed service without a new BR VPC or cross-region peering

**Evidence:**

From the AWS PrivateLink cross-region blog ([source 1](https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/)):

> "You can only enable cross-region access for NLB-based services. AWS services and Marketplace services are not supported at this time."

> "All traffic stays on AWS network without going over the public internet."

> "Cross-region connectivity is only supported for Interface type VPC endpoints."

Architecture for this spike's use case: NLB in `app-atento-001` (us-east-1), fronting the existing PgBouncer ECS service on port 6432. Endpoint service attached to that NLB. Interface VPC endpoint in `app-outbound-atento-br` (sa-east-1). Consumer connects via the Interface endpoint's private DNS name or IP. No new VPC, no new TGW attachment, no new cross-region VPC peering, no new RDS SG rule.

**Source:** https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/ (re-fetched and quote substring confirmed)

**Significance:** Candidate 4 does not require any new sa-east-1 network infrastructure. The sa-east-1 worker's DATABASE_URL can point to the Interface endpoint DNS name (or the us-east-1 pooler CNAME if PHZ is associated with the worker VPC — but the endpoint DNS avoids that requirement entirely). The trade-off is a new NLB in the us-east-1 stack and ~130ms RTT for all worker queries crossing regions (same as today's direct RDS access from sa-east-1, if that access exists at all). A TCP NLB can front port 6432.

---

### Finding 6: Session pooling is required for multi-tenant safety; transaction and statement pooling cause search_path leakage

**Evidence:**

From blog.sagarregmi.info.np ([source 5](https://blog.sagarregmi.info.np/transaction-pooling-the-multi-tenant-nightmare)), re-fetched and confirmed:

> "In Transaction Pooling, PgBouncer gives your app a fresh connection for each transaction — but it doesn't clean up session-level settings like `search_path`."

> "Thread B reuses the connection, assumes it's for tenant_b, but still sees tenant_a's context. Result: tenant_b sees tenant_a's data."

From pgbouncer.org ([source 6](https://www.pgbouncer.org/features.html)), fetched and confirmed:

> "Most polite method. When a client connects, a server connection will be assigned to it for the whole duration it stays connected."

(Session pooling description)

> "This mode breaks a few session-based features of PostgreSQL. You can use it only when the application cooperates by not using features that break."

(Transaction pooling warning)

**Source:** https://blog.sagarregmi.info.np/transaction-pooling-the-multi-tenant-nightmare (re-fetched), https://www.pgbouncer.org/features.html (fetched)

**Significance:** If a BR pooler serves multiple consumers (e.g., a payroll worker for Atento AND future integrator workloads), it is a multi-tenant pooler — multiple `[databases]` sections, potentially multiple users, potentially different `search_path` per tenant. Session pooling is the only safe mode. This matches the existing 4Shark pattern confirmed in PLAN.md (`auth_type=md5`, session pooling). Any BR pooler must use the same configuration.

---

### Finding 7: Route53 Private Hosted Zone 4shark.internal requires explicit aws_route53_zone_association per consumer VPC

**Evidence:**

From `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:11`:

> "The atento app VPC must be associated with that zone (aws_route53_zone_association) — it bit us on shared (NXDOMAIN). Verify + add."

PHZ zone ID: `Z3PBW9DU61QULB`

From the AWS whitepaper (Source 3, fetched prior session):

> "Private hosted zones are associated with specific VPCs. Managed private hosted zones only work within the VPC containing the VPC endpoint."

**Source:** `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:11`, AWS whitepaper

**Significance:** Candidates 1, 2, and 3 all require the BR pooler to be reachable via a `4shark.internal` CNAME from each consumer VPC. Every consumer VPC (app-outbound-atento-br and any future BR consumer) must be associated with the `4shark.internal` PHZ — one `aws_route53_zone_association` resource per VPC. This is known operational work, already identified as a pain point from shared-001. Candidate 4 (PrivateLink Interface endpoint) provides its own DNS names inside the consumer VPC without using the PHZ at all, sidestepping this requirement.

---

### Finding 8: Maqnelson VPC (Candidate 1 host) is a shared integrator environment; no confirmation of tenant count

**Evidence:**

From `terraform/networking/vpc_egress_sa_east_1.tf:126-130` (see `br-pooler-network-topology_excerpt_1.tf` lines 162-165):

```hcl
resource "aws_route" "egress_sa_east_1_pub_to_maqnelson" {
  route_table_id         = aws_route_table.egress_sa_east_1_pub.id
  destination_cidr_block = "10.1.2.0/24"
  transit_gateway_id     = aws_ec2_transit_gateway.sa_east_1.id
}
```

Maqnelson CIDR = `10.1.2.0/24`. Listed alongside almaviva (10.1.0.0/24), commcenter (10.1.3.0/24), redebrasil (10.1.1.0/24) — all integrator VPCs with the same TGW + egress pattern.

**Source:** `terraform/networking/vpc_egress_sa_east_1.tf:126-130`

**Significance:** Maqnelson is confirmed as one of the sa-east-1 integrator VPCs. Per the investigation brief, it is described as "a shared integrator env (multiple client tenants that each may need outbound integration to a us-east-1 DB)." Co-locating a BR pooler here mixes database connection pooling infrastructure with integrator ECS workloads. A pooler compromise or misconfiguration (wrong `search_path`, wrong credentials) inside maqnelson has a shared blast radius with integrator functions. Whether maqnelson is 4client (dedicated, one client) or 4shared (multi-tenant) was not confirmed from the Terraform code read — the module structure would need to be checked. Not finding confirms uncertainty.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **C1: Pooler in maqnelson VPC** | No new VPC; uses existing TGW attachment; faster to deploy | Requires new cross-region VPC peering (maqnelson → app-atento-001); new RDS SG ingress rule for maqnelson CIDR; each additional sa-east-1 consumer needs new TGW intra-spoke route or new peering to maqnelson; blast radius shared with integrator workloads; PHZ association per consumer VPC; SSM split still needed for the sa-east-1 worker | `terraform/networking/transit_gateway.tf:62-66`, `terraform/networking/peering.tf:490-569`, `terraform/app-atento-001/rds.tf:23-53` |
| **C2: Dedicated pooler VPC (sa-east-1)** | Clean network isolation; one cross-region peering for the pooler; additional sa-east-1 consumers add only a new TGW route or peering to the pooler VPC (not to each other's VPCs); matches hub-spoke architecture philosophy; clear blast-radius boundary | New VPC, subnets, TGW attachment, route tables (Terraform work ~= C1 minus the blast-radius sharing); cross-region peering to app-atento-001; new RDS SG ingress rule; PHZ association per consumer VPC; SSM split still needed for the sa-east-1 worker | `terraform/networking/transit_gateway.tf`, AWS whitepaper (Source 3) |
| **C3: Start in maqnelson, extract later** | Defers new-VPC Terraform cost; faster initial delivery | All C1 costs now, plus a migration cost when the second consumer appears (VPC move = new ECS service, new DNS, SSM re-swap, downtime window); the extraction is harder than a greenfield build | `~/.claude/plans/active/terraform/pgbouncer-ecs-migration/TASKS.md:16-18` |
| **C4: Cross-region PrivateLink (NLB in us-east-1, Interface endpoint in sa-east-1 consumer VPCs)** | No new sa-east-1 VPC; no new cross-region VPC peering; no new RDS SG rule; sa-east-1 worker can use the same SSM param (endpoint DNS resolves inside its own VPC; no PHZ association needed for the endpoint); traffic stays on AWS backbone; each new sa-east-1 consumer adds only one Interface endpoint (no peering changes, no TGW route changes) | NLB hourly + LCU cost in us-east-1; ~130ms RTT for all sa-east-1 worker queries (same as today if worker reaches RDS directly); NLB health check requires TCP/6432 access to the pooler; requires new Terraform in app-atento-001 (NLB + endpoint service); Interface endpoint per consumer VPC | Source 1 (AWS PrivateLink blog, re-fetched) |

## What remains uncertain

1. **How the sa-east-1 payroll worker connects to the database today.** The RDS is `publicly_accessible = false` and the worker VPC (10.12.0.0/26) has no confirmed Terraform route to us-east-1. If the worker is connecting today, it must be via the Pritunl OpenVPN server in Management VPC acting as an OS-layer router — traffic goes: `app-outbound-atento-br → Management peering → Pritunl VPN server → (VPN client route?) → app-atento-001`. This path is not visible in Terraform (`ignore_changes=[route]` on Management route tables). If the worker is NOT connecting today (desired_count=0, never used), then the sa-east-1 DB path question may be moot for the current state, and it becomes a forward-looking design question only.

2. **Whether Candidate 4 (PrivateLink) supports the existing pooler's TCP connection semantics at port 6432.** AWS NLB supports TCP pass-through (layer 4 load balancing). PgBouncer speaks plain TCP + PostgreSQL protocol on port 6432. A TCP NLB should pass this through without issue, but the TLS behavior of the pooler (`server_tls_sslmode`) and whether the NLB needs to terminate TLS or pass it through is unconfirmed.

3. **Whether the maqnelson integrator VPC is 4client (dedicated, single client) or 4shared (multi-tenant, multiple clients).** If it is 4client, the blast-radius concern of co-locating the pooler is scoped to one client. If it is 4shared, the concern applies to all clients on that VPC. This affects the risk assessment of Candidate 1 but was not confirmed from the Terraform code read.

4. **Cost comparison: dedicated VPC + TGW attachment (C2) vs NLB + LCU (C4).** A sa-east-1 TGW attachment is ~$0.07/hour in sa-east-1 (USD, 2026 pricing); an NLB in us-east-1 is ~$0.008/hour per AZ + $0.006/LCU/hour. For a low-traffic pooler (one or two consumers), C4 may be cheaper than C2 despite adding an NLB. This cost difference is small compared to the operational work involved in either option.

5. **The atento-001 specific `out-of-band` Pritunl routes in app-outbound-atento-br.** Both route tables have `ignore_changes=[route]`. If Pritunl VPN routes were added for the Management VPC direction AND Management has a route to app-atento-001 via cross-region peering, the Pritunl server could act as an OS-level router connecting the two paths. This is speculative — no VPN config was read. If true, the sa-east-1 worker might already have a path to the RDS via Pritunl routing, making the whole BR-pooler question secondary to confirming the existing path.

## Suggested options for main and the engineer

**Option A — Candidate 2: Dedicated BR pooler VPC (sa-east-1)**

New Terraform stack `app-pooler-br` (or similar naming convention), VPC in sa-east-1 with its own CIDR (e.g., 10.1.4.0/24), TGW attachment (spoke_rt), cross-region VPC peering to `app-atento-001` (10.100.12.0/22), new RDS SG ingress rule for the new CIDR on port 5432, ECS Fargate PgBouncer (`pgbouncer:4` image), session pooling, N `[databases]` sections per consuming tenant, `4shark.internal` DNS via Cloud Map, `aws_route53_zone_association` for each consumer VPC. SSM split: sa-east-1 worker DATABASE_URL → BR pooler; us-east-1 app DATABASE_URL → us-east-1 pooler (requires breaking the shared `atento_001_task_config` module SSM dependency or adding a separate param). Trade-off: cleanest topology, highest Terraform work, resolves the Phase 0 open item by providing a BR path.

**Option B — Candidate 4: Cross-region PrivateLink from us-east-1 pooler**

NLB added in `app-atento-001` (us-east-1), targeting the existing PgBouncer ECS service on port 6432. VPC endpoint service enabled on the NLB. Interface VPC endpoint created in `app-outbound-atento-br` (sa-east-1). The sa-east-1 worker's DATABASE_URL is updated to the Interface endpoint DNS name (private IP in 10.12.0.0/26). No new sa-east-1 VPC, no new cross-region peering, no new RDS SG rule. PHZ association not needed for the endpoint DNS. Each new sa-east-1 consumer adds one Interface endpoint, with no architecture changes. Trade-off: all worker queries still transit the AWS backbone with ~130ms RTT; NLB cost in us-east-1; new Terraform in the us-east-1 stack (NLB + endpoint service).

**Option C — No BR pooler: sa-east-1 worker bypasses the pooler entirely**

Resolve Phase 0 open item #1 by deciding the sa-east-1 payroll worker does NOT use a pooler. The worker keeps its current database path (if it has one today) or gets a dedicated SSM param pointing directly at the Aurora RDS writer endpoint, using the existing Management→app-atento-001 cross-region peering as the routing path (requires the sa-east-1 worker to route to the Management VPC; the existing peering puts 10.255.0.0/16 reachable from 10.12.0.0/26 — but the return route in Management goes only to management_pub, not management_prv, which is an asymmetric peering gap). The us-east-1 app services use only the us-east-1 pooler as planned. The BR-pooler question is deferred until a second sa-east-1 consumer appears. Trade-off: simplest cutover for the us-east-1 migration; does not answer the forward-looking multi-consumer question; the Management peering asymmetry may complicate even this option.
