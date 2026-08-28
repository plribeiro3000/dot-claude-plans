# SPIKE — Routing `sidekiq-queue-check.sh` through the 4Shark VPN

## Outcome

The direction taken is **Option C** below — run the queue check from inside the target environment's own VPC, so it egresses from that environment's NAT Elastic IP (already in `source_ips`), rather than routing the laptop's connection through the VPN. The VPN-routing options (A and B) and the peering dead-end (Finding 4) are kept here as the record of what was evaluated and why it was set aside. The chosen mechanism lives in `PLAN.md` Phase 3.

## Investigation question

Can `~/.claude/scripts/sidekiq-queue-check.sh`, run from an engineer's laptop, be made to reach each environment's Redis Cloud database over the 4Shark VPN (Pritunl) so that Redis Cloud sees a 4Shark-controlled source IP instead of the laptop's own public IP — closing the last gap that keeps Phase 4 of `PLAN.md` (narrowing `source_ips`) from running? If viable, what is the exact mechanism and which IP does Phase 4 add to the allowlist?

## Sources consulted

- `~/Projects/4Shark/dot-claude-plans/active/redis-source-ips-lockdown/PLAN.md` — the plan this spike supports; Phases 1–2 done, Phase 3 (this spike) blocking Phase 4.
- `~/.claude/scripts/sidekiq-queue-check.sh` — the script in question; connects to Redis Cloud over TLS using `redis-cli`, reading host/port/password from SSM.
- `~/.claude/docs/runbooks/vpn/PRITUNL-VPN-OPERATIONS.md` — operational notes on the Pritunl VPN, including a DNS-routing note that is the strongest first-party evidence for split-tunnel.
- `~/Projects/4Shark/terraform/modules/vpn/ecs.tf`, `production.tf`, `eip.tf`, `outputs.tf` — the Pritunl VPN's Terraform (ECS-on-EC2 with host networking; the production instance and its Elastic IP).
- `~/Projects/4Shark/terraform/vpn/outputs.tf`, `variables.tf` — the stack wrapping the module.
- `~/Projects/4Shark/terraform/networking/vpc_management.tf` — the VPC the Pritunl instance sits in, its subnets and route tables.
- `~/Projects/4Shark/terraform/modules/redis_cloud/README.md` — 4Shark's own Redis Cloud module docs, stating the Essentials plan's connectivity limit.
- [Redis Cloud — Enable VPC peering](https://redis.io/docs/latest/operate/rc/security/vpc-peering/) — confirms VPC peering is Pro-only.
- [Redis Cloud — Network security](https://redis.io/docs/latest/operate/rc/security/database-security/network-security/) — table of VPC peering / IP-restriction support by cloud provider and plan.
- [Redis Cloud — Configure CIDR allow list](https://redis.io/docs/latest/operate/rc/security/cidr-whitelist/) — confirms the allow list is a plan-gated feature and applies to the public endpoint.
- Pritunl documentation, `docs.pritunl.com/kb/vpn/servers/routing` and the Pritunl community forum (accessed via WebSearch, no single URL fetched directly) — Pritunl's default routing behavior and split-tunnel configuration.
- Redis Cloud endpoint-failover material (WebSearch, Redis Knowledge Base "Diagnosing and Resolving Endpoint Flapping in Redis Software") — general statements about endpoint IP changes on failover; **not database-specific, treated as directional, not authoritative** (see What remains uncertain).

## Findings

### Finding 1: The VPN is split-tunnel, not full-tunnel

**Evidence:**
```
## DNS requirements

Pritunl clients reach internal AWS resources via the VPC resolver (`10.255.0.2`
in our setup, or whatever the second IP of the management VPC's CIDR is). For
the resolver to be reachable through the VPN tunnel, the routing must be correct:

- The VPN tunnel must include a **NAT route** for the VPC resolver IP (typically `10.255.0.2/32`)
- Without this route, internal DNS lookups silently fall back to the client's
  local resolver, which can't see internal hostnames
```
**Source:** `~/.claude/docs/runbooks/vpn/PRITUNL-VPN-OPERATIONS.md:45-52`

**Significance:** if the VPN pushed a default `0.0.0.0/0` route to clients (full tunnel), every destination — including the VPC resolver — would already be reachable through the tunnel, and this runbook note would have nothing to instruct. The note exists specifically because only select routes (the VPC CIDR plus, apparently, a specific NAT'd route for the resolver) are pushed to clients. This is corroborated by Pritunl's own documented split-tunnel procedure, which is to remove the `0.0.0.0/0` route and add specific-network routes instead (Finding 3). No Terraform resource for a Pritunl server/route/organization exists in the repository (`grep` for `pritunl_organization|pritunl_route|pritunl_server|provider "pritunl"` across `~/Projects/4Shark/terraform` returned nothing), so route configuration is done by hand in the Pritunl admin console, not IaC — consistent with routes being deliberately curated rather than a blanket default.

### Finding 2: The Pritunl production instance's egress IP is a dedicated, stable 4Shark Elastic IP — different from the app VPCs' NAT EIPs

**Evidence:**
```hcl
# terraform/vpn/production.tf:17-34
resource "aws_instance" "production" {
  ami           = module.amis.ecs_optimized
  instance_type = "t3a.micro"
  key_name      = "kp-4shark"
  subnet_id     = module.networking_data.public_subnet_id["c1"]
  ...
  associate_public_ip_address = true
```
```hcl
# terraform/modules/vpn/eip.tf:11-28
resource "aws_eip" "vpn" {
  domain = "vpc"
  tags = {
    Name = "4shark-vpn-001-eip"
    ...
  }
}

resource "aws_eip_association" "vpn" {
  instance_id   = aws_instance.production.id
  allocation_id = aws_eip.vpn.id
}
```
```hcl
# terraform/networking/vpc_management.tf:17-26, 153-157
resource "aws_subnet" "management_pub_c1" {
  vpc_id                  = aws_vpc.management.id
  cidr_block              = "10.255.0.0/24"
  ...
  map_public_ip_on_launch = true
}
...
resource "aws_route" "management_pub_default" {
  route_table_id         = aws_route_table.management_pub.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.management.id
}
```

**Significance:** the Pritunl production instance lives in the `management` VPC's **public** subnet (`management_pub_c1`), whose route table sends `0.0.0.0/0` straight to the Internet Gateway — not through `aws_nat_gateway.management` (that NAT gateway, and its own separate EIP `aws_eip.management_nat`, serves only the VPC's *private* subnets, per `terraform/networking/vpc_management.tf:79-96,159-163`). Any traffic that egresses through the Pritunl host's own network interface — whether generated by the instance itself or NAT'd (masqueraded) from a connected VPN client via a Pritunl server route with NAT enabled — leaves through the Internet Gateway carrying the instance's 1:1-mapped Elastic IP, `4shark-vpn-001-eip`. This is a single, already-existing, 4Shark-owned address, independent of any environment's app-VPC NAT EIP. Because there is exactly one Pritunl VPN for the whole team (per `terraform/vpn/outputs.tf` and the module's own header comments), this same IP would be the source seen by Redis Cloud regardless of which of the four stacks (`beta-001`/`demo-001`/`shared-001`/`atento-001`) the engineer is checking — one allowlist entry could in principle cover all four, rather than the per-environment NAT EIP the Lambdas use.

### Finding 3: Making the Redis Cloud connection go through the tunnel requires a Pritunl "server route" naming Redis Cloud's endpoint, with NAT enabled — not a change to the tunnel's default shape

**Evidence (WebSearch summary of Pritunl's own routing docs, `docs.pritunl.com/kb/vpn/servers/routing` and `docs.pritunl.com/docs/routing`):**
> "Server routes configure which networks VPN clients will send traffic to. By default a server will route all internet traffic to the VPN server using the 0.0.0.0/0 route." … "NAT can be enabled for routes to NAT traffic from VPN clients to the network, which is required unless a static route is configured on the router for the VPN network." … "The split tunnel configuration will route the VPN traffic only to the configured network (for example, VPC CIDR 172.31.0.0/16). To set up split tunneling, first remove the 0.0.0.0/0 route from the server … then add a route for the specific private network with its network address."

**Significance:** Pritunl's routing primitive is CIDR-based, not domain-based — there is no "route this hostname through the tunnel" construct. To pull the engineer's Redis Cloud traffic through the tunnel without going full-tunnel, the mechanism is: resolve Redis Cloud's public endpoint to its current IP(s), add a Pritunl server route naming that IP (or its containing CIDR) with **NAT enabled**, and the connected client then routes packets for that destination through the tunnel; the Pritunl production instance NATs them out via its own EIP (Finding 2). This is candidate (a) from the task's list, and it is the one Pritunl's own primitives support directly. Full-tunnel (candidate b) is also mechanically available (it is in fact Pritunl's *default*, per the same source) but sends **all** of the engineer's internet-bound traffic through the VPN gateway while connected — a materially larger behavior change than the task requires, imposed on every engineer merely to run a pre-deploy check. VPC peering (candidate c) is foreclosed outright — see Finding 4.

### Finding 4: VPC peering / PrivateLink to Redis Cloud is not available on the Essentials plan — this repository already knows and states it

**Evidence:**
```
## Known Limitations
...
- Redis Cloud Essentials does not support VPC peering — connectivity is over the public
  internet with TLS encryption enforced.
```
**Source:** `~/Projects/4Shark/terraform/modules/redis_cloud/README.md:92-98`

Corroborated externally:
> "VPC peering is available only with Redis Cloud Pro. It is not supported for Redis Cloud Essentials."
**Source:** https://redis.io/docs/latest/operate/rc/security/vpc-peering/

> "AWS | Redis Cloud Pro | Paid Redis Cloud Essentials and Redis Cloud Pro" (VPC peering column vs IP-restrictions column, by plan)
**Source:** https://redis.io/docs/latest/operate/rc/security/database-security/network-security/

**Significance:** candidate (c) — private connectivity from the Redis Cloud side — is not an option without a plan upgrade to Pro (a cost/commercial decision outside this spike's scope, and outside what `PLAN.md` presumes). The `sidekiq-queue-check.sh` script's own comment already documents the current state consistently with this: `~/.claude/scripts/sidekiq-queue-check.sh:196` — "Redis Cloud Essentials enforces TLS (terraform/modules/redis_cloud/README.md)" — the script author had already read this same limitation. This forecloses (c) and leaves (a) [route Redis Cloud's IP through the tunnel] or (b) [full tunnel] as the two mechanically real options; the task's engineer-chosen direction (route through the VPN) is only reachable via (a) or (b), never (c).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| (a) Pritunl server route naming Redis Cloud's endpoint IP, NAT enabled | Narrow — only Redis Cloud traffic changes path; every other engineer traffic (browsing, other tools) is unaffected; reuses the existing `4shark-vpn-001-eip`, no new infrastructure | Requires knowing Redis Cloud's current resolved IP; Pritunl routes are CIDR-based, not hostname-based, so this is a host route (or a narrow CIDR) rather than something that tracks a changing IP automatically; the route is Pritunl-console config, not Terraform-managed (no `pritunl_*` provider resource in this repo), so it is a manual step outside the IaC audit trail; must be updated if Redis Cloud's endpoint IP ever changes (see What remains uncertain) | Findings 1, 2, 3 |
| (b) Full-tunnel VPN (Pritunl's own default) | No dependency on Redis Cloud's IP being stable — every destination, including Redis Cloud, already routes through the tunnel; needs no per-endpoint route maintenance | Every engineer's entire internet-bound traffic (not just the queue check) routes through the Pritunl gateway while connected — a much larger behavior and performance change than the task calls for, imposed on the whole team to serve one script's occasional use | Finding 3 |
| (c) Redis Cloud VPC peering / PrivateLink from the laptop side | Would remove the public-internet leg entirely | Not available on Redis Cloud Essentials at all — Pro-only, a plan upgrade | Finding 4 |

## What remains uncertain

- **Whether Redis Cloud Essentials' public endpoint resolves to a stable IP, or one that can change (e.g., on failover/maintenance).** Redis Cloud's own documentation on this point was not found; a Redis Knowledge Base article on "endpoint flapping" discusses IP changes in the general Redis Software/failover context, not this specific Essentials-plan public endpoint, so it is **not cited as a Finding** (it did not meet the citation bar for this spike — general/adjacent, not a verified statement about the Essentials public endpoint). This uncertainty is the one fact that decides how much operational risk candidate (a) carries: a route pinned to a `/32` that goes stale after a Redis Cloud–side event would fail silently (the queue check would simply stop reaching Redis, surfacing as a script error rather than a security gap) until someone re-points the Pritunl route.
- **Whether Redis Cloud publishes any broader stable CIDR range** (e.g., the AWS/GCP region its Essentials infrastructure runs in) that could be routed instead of a single host IP, reducing exposure to an IP change. Not found in the documentation consulted.
- **Whether the Pritunl route change itself needs anything beyond the admin-console UI** (e.g., an API call that could be scripted/documented) — not investigated; out of the fast-spike scope named in the task.

## Suggested options for main and the engineer

- **Option A — Narrow route (candidate a):** Resolve each environment's Redis Cloud `REDIS_SIDEKIQ_URL`/`REDIS_URL` hostname to its current IP, add a Pritunl server route for that IP (NAT enabled) on the production VPN server, and have the engineer connect to the VPN before running `sidekiq-queue-check.sh`. Phase 4 then adds `4shark-vpn-001-eip`'s public IP (from `terraform/vpn/outputs.tf` → `pritunl_public_ip`) to each environment's `source_ips`, alongside that environment's NAT Elastic IP from Phase 1. Carries the staleness risk named in "What remains uncertain" and needs a documented recovery step (who re-points the route, and how, if Redis Cloud's IP changes).
- **Option B — Full tunnel while connected (candidate b):** Switch the Pritunl production server to its default `0.0.0.0/0` routing behavior instead of split-tunnel. Removes the IP-staleness risk entirely for this specific use case, at the cost of changing routing behavior for every VPN-connected engineer's entire traffic, not just Redis Cloud.
- **Option C — Reconsider the direction:** `PLAN.md`'s own Phase 3 "Components" (before this spike was commissioned) already named an alternative: serve queue depth/busy count from inside the VPC (the app already holds both), so the laptop script reads that instead of dialing Redis Cloud directly at all. This removes the VPN-routing question altogether but is a different mechanism than the one this spike was asked to investigate, and is named here only because Option A carries a real, not-fully-resolved operational risk.

No recommendation is made among these — Option A most directly matches the engineer's stated direction; Option B removes A's fragility at a broader behavioral cost; Option C sidesteps the question but changes the shape of Phase 3 from what was asked.
