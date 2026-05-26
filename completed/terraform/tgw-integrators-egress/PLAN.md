# PLAN — Centralized Egress for Integrator VPCs via Transit Gateway

**Reference spike:** `~/.claude/plans/active/spike/tgw-integrators-egress/SPIKE.md`
**Status:** APPROVED

---

## Current Situation

- 7 integrator VPCs in sa-east-1, each with its own NAT Gateway
- Each NAT Gateway costs ~$68/month → total ~$476/month just for integrator egress
- All integrators are connected to the management VPC via VPC peering (one peering each)
- Management VPC (10.255.0.0/16) serves as the hub: hosts Pritunl VPN and Keycloak
- No Transit Gateway exists in the account today

**Integrator VPCs (sa-east-1):**

| VPC | CIDR | NAT Gateway |
|-----|------|-------------|
| integrator-almaviva | 10.1.0.0/24 | nat-0c73faca7e745930d |
| integrator-redebrasil | 10.1.1.0/24 | nat-05abe4fcc9b9f0d55 |
| integrator-maqnelson | 10.1.2.0/24 | nat-0f4523b88ae80f008 |
| integrator-commcenter | 10.1.3.0/24 | nat-0ca37d7634939afa3 |
| integrator-aster-maquinas | 10.1.4.0/24 | nat-01f4651d50c20d462 |
| integrator-atento-br | 10.12.255.0/24 | nat-0d943e24969e7bf4f |
| out-atento-br | 10.12.0.0/26 | nat-03b45836d0effc138 |

## Objective / Target State

- Replace 7 individual NAT Gateways with a single shared NAT Gateway in a dedicated egress VPC
- Keep each integrator able to reach the internet (outbound only) via the shared egress path
- Keep all client S2S VPNs (VGW) completely unaffected
- Keep admin access (Pritunl → peering → integrators) completely unaffected
- Support future egress VPCs in other regions under the same naming convention

**Success criteria:**
- All integrators can reach the internet (apt-get, GitHub, external APIs) after migration
- Datadog metrics continue to arrive from all integrators
- No change in S2S VPN connectivity to any client
- Each migrated integrator's NAT Gateway deleted (cost confirmed reduced)

## Architecture Decisions (approved)

### Decision 1: Dedicated egress VPC, not subnets within management

A separate egress VPC is required because:
- Mixing TGW attachment subnets with Pritunl/VPN infrastructure is architecturally wrong
- The egress VPC has a single responsibility: provide internet egress via NAT Gateway
- It needs to be independently manageable and replicable in other regions

### Decision 2: VPC peering from egress VPC to management

The egress VPC must be reachable via VPN for operational access (debugging, maintenance).
- One VPC peering: `egress-sa-east-1` ↔ `management`
- Management adds a return route to the egress VPC CIDR
- Pritunl pushes the egress VPC CIDR to VPN clients

### Decision 3: Naming convention `egress-{aws-region}`

Format: `egress-sa-east-1`, `egress-us-east-1`, `egress-us-west-2`, etc.

Rationale: numbers (001, 002) lose geographic context; country codes (br, us) are ambiguous
when multiple AWS regions exist in the same country (e.g., us-east-1 vs us-west-2).
Full region name is unambiguous and scales without limit.

### Decision 4: Client IP whitelisting is not a concern

All integrator-to-client communication is via S2S VPN (internal IPs).
The NAT Gateway EIP is used only for outbound internet from integrator servers —
not for any communication with client networks. No client coordination needed.

### Decision 5: Single AZ, single NAT Gateway — scale via secondary IPs if needed

Single AZ (sa-east-1a) is sufficient. No AZ redundancy needed — this matches the current
state where each integrator already has a single-AZ NAT Gateway.

If port exhaustion ever occurs, the solution is adding secondary IPv4 addresses to the
existing NAT Gateway (up to 8 IPs = 440k concurrent connections per destination), not
creating a new NAT Gateway. This requires no changes to VPC, subnets, or routing.

## CIDR for egress-sa-east-1

**Approved:** `10.254.0.0/27`

Rationale: placed at the top of the 10.x.x.x space, just below management (10.255.0.0/16).
Future egress VPCs follow the same pattern downward:

```
10.252.0.0/27  — egress-us-west-2  (future)
10.253.0.0/27  — egress-us-east-1  (future)
10.254.0.0/27  — egress-sa-east-1  ← first to create
10.255.0.0/16  — management        (hub, unchanged)
```

AWS minimum subnet size is /28 (16 IPs) — cannot go smaller.

**Subnets:**

| Subnet | CIDR | AZ | Purpose |
|--------|------|----|---------|
| egress-sa-east-1-tgw-a | 10.254.0.0/28 | sa-east-1a | TGW attachment ENI |
| egress-sa-east-1-pub-a | 10.254.0.16/28 | sa-east-1a | NAT Gateway (public subnet) |

## Traffic Flow (after migration)

```
Integrator server
  → default route → TGW
  → TGW spoke-rt (0.0.0.0/0 → egress attachment)
  → egress VPC route table → NAT Gateway
  → NAT Gateway → Internet Gateway → Internet

Admin (VPN)
  → Pritunl (management VPC)
  → peering → egress-sa-east-1  (for maintenance access)
  → peering → integrator VPC    (unchanged)

Client S2S VPN
  → VGW (per integrator) — unchanged, not affected by NAT change
```

## Implementation Phases

### Phase 0 — Confirm CIDR safety
- Verify 10.254.0.0/27 does not conflict with any client on-premise CIDR
- Check static routes configured in each integrator VGW

### Phase 1 — Create egress-sa-east-1 VPC (zero blast radius)
- New file `networking/vpc_egress_sa_east_1.tf`
- VPC `egress-sa-east-1` with CIDR 10.254.0.0/27
- 2 subnets: tgw-a (/28) and pub-a (/28)
- Internet Gateway
- EIP + NAT Gateway in pub-a
- Route table for tgw subnet: `0.0.0.0/0` → NAT Gateway
- VPC peering: egress-sa-east-1 ↔ management (in `networking/peering.tf`)
- Routes in both directions for the peering
- SSM parameters for new VPC/subnet IDs
- No integrator changes — zero impact

### Phase 2 — Create Transit Gateway (zero blast radius)
- New file `networking/transit_gateway.tf`
- `aws_ec2_transit_gateway` with custom route tables (disable default association/propagation)
- TGW route table `spoke-rt`: `0.0.0.0/0` → egress-sa-east-1 attachment
- TGW route table `egress-rt`: return routes added per integrator during Phase 3+
- TGW attachment to egress-sa-east-1 (tgw-a subnet)
- No integrator routes changed yet — still zero impact

### Phase 3 — Pilot migration: almaviva
- TGW attachment for integrator-almaviva VPC
- Add 10.1.0.0/24 to TGW egress-rt → almaviva attachment
- Add route in egress VPC tgw subnet RT: 10.1.0.0/24 → TGW
- Flip almaviva private RT: `0.0.0.0/0` from nat-almaviva → TGW
- Validate 24h: internet reachability, Datadog metrics, S2S VPN unaffected
- If OK: delete almaviva NAT Gateway and EIP

### Phase 4 — Migrate remaining integrators (one at a time)

Same steps as Phase 3. Order:
1. maqnelson
2. commcenter
3. aster-maquinas
4. redebrasil
5. out-atento-br
6. atento-br (last — most complex, has Redis/ElastiCache)

Each migration is independently reversible (flip `0.0.0.0/0` back to old NAT GW before deleting it).

### Phase 5 — Cleanup
- Update CHANGELOG.md
- Verify all 7 integrator NAT Gateways deleted
- Confirm cost reduction in AWS Cost Explorer

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| 10.254.0.0/27 conflicts with client on-premise CIDR | Low | High | Verify in Phase 0 before creating anything |
| TGW route table misconfiguration | Low | High | Pilot with almaviva, 24h observation before proceeding |
| Asymmetric routing during transition | Very Low | Medium | Peering stays intact; only `0.0.0.0/0` route changes |
| atento-br complexity (Redis/ElastiCache) | Medium | Medium | Left last; same procedure, verify all services post-flip |

## Cost Impact

| Item | Before | After |
|------|--------|-------|
| 7 integrator NAT GWs | ~$476/month | $0 |
| Shared NAT GW in egress VPC | $0 | ~$68/month |
| TGW (8 attachments × $0.05/h × 730h) | $0 | ~$292/month |
| TGW data processing (~$0.02/GB) | $0 | ~$10–20/month |
| **Total egress cost** | **~$476/month** | **~$370–380/month** |
| **Net savings** | | **~$96–106/month (~$1,200/year)** |

## Internal References

- Spike: `~/.claude/plans/active/spike/tgw-integrators-egress/SPIKE.md`
- Network architecture spike: `~/.claude/plans/active/spike/4shark-network-architecture/SPIKE.md`
- Terraform: `networking/vpc_management.tf`, `networking/vpc_*.tf`, `networking/peering.tf`
