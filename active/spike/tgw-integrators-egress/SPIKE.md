# SPIKE: Transit Gateway — Centralized Egress for Integrator VPCs

**Status:** Completed
**Date:** 2026-03-06
**Author:** Engineering
**Motivation:** 7 NAT Gateways in sa-east-1 costing ~$476/month. Investigate replacing them with a single shared NAT Gateway via AWS Transit Gateway.

---

## Questions to Answer

1. Can TGW coexist with existing VPC peerings during migration?
2. Can migration be done incrementally (one integrator at a time)?
3. Does the VPN (Virtual Private Gateway) conflict with TGW?
4. What is the exact routing change needed per integrator?
5. What is the blast radius of each step?

---

## Current Architecture (confirmed from live infrastructure)

### VPCs in sa-east-1

| VPC | CIDR | NAT Gateway | Peering to Management |
|-----|------|-------------|----------------------|
| management | 10.255.0.0/16 | nat-management | hub |
| integrator-almaviva | 10.1.0.0/24 | nat-0c73faca7e745930d | pcx-078cff15e5c534ca3 |
| integrator-redebrasil | 10.1.1.0/24 | nat-05abe4fcc9b9f0d55 | pcx-0d2b3cbed169074e4 |
| integrator-maqnelson | 10.1.2.0/24 | nat-0f4523b88ae80f008 | pcx-0cfc2971e1dedf0cc |
| integrator-commcenter | 10.1.3.0/24 | nat-0ca37d7634939afa3 | pcx-0660dcb38076bd208 |
| integrator-aster-maquinas | 10.1.4.0/24 | nat-01f4651d50c20d462 | pcx-0a31bb4f931e55651 |
| integrator-atento-br | 10.12.255.0/24 | nat-0d943e24969e7bf4f | pcx-080ff142daa2beadd |
| out-atento-br | 10.12.0.0/26 | nat-03b45836d0effc138 | pcx-0dd23f620fcc6cc77 |

### Route tables (each integrator private RT)

Every integrator private route table has exactly these route types:
- `<local CIDR>` → local
- `10.255.0.0/16` → VPC peering connection (to management)
- `<client on-prem CIDR>` → Virtual Private Gateway (VGW, client VPN)
- `0.0.0.0/0` → NAT Gateway (the one in the same VPC)

No TGW exists in the account today.

---

## Research Findings

### Finding 1: TGW and VPC peerings CAN coexist

VPC peering and Transit Gateway are completely independent AWS primitives. Adding a TGW attachment to a VPC does NOT affect its existing peering connections. The two share routing table entries but never conflict because they handle different destination CIDRs during a phased migration.

**Confirmed behavior:**
- Peering continues to handle `10.255.0.0/16` (management internal traffic)
- TGW handles `0.0.0.0/0` (internet egress) once we flip the default route
- Both can be active simultaneously in the same route table

This means migration can be done **without any downtime window** for admin access.

### Finding 2: Incremental migration is fully supported

Because the only change per integrator is swapping the `0.0.0.0/0` route target (from `nat-gateway-id` to `tgw-id`), each integrator can be migrated independently. The steps for a single integrator are atomic and reversible (just flip the route back).

Migration sequence is safe because:
- Before the flip: integrator uses its own NAT GW for internet, peering for management traffic
- After the flip: integrator uses TGW for internet, peering still handles management traffic
- Admin SSH access via Pritunl always goes through peering (10.255.0.0/16), never through NAT

### Finding 3: Virtual Private Gateway (client VPN) is unaffected

Each integrator has a VGW for the site-to-site VPN with the client's on-premise network. VGW and TGW are independent. The client VPN routes (specific client CIDRs via VGW) remain unchanged throughout the migration.

The VGW routes have higher specificity than `0.0.0.0/0`, so AWS longest-prefix-match routing guarantees they are always preferred over any default route change.

### Finding 4: TGW centralized egress is an AWS-supported pattern

Unlike VPC peering (which prohibits transitive NAT), Transit Gateway explicitly supports centralized egress. AWS documentation describes this as "centralized outbound routing" — traffic from spoke VPCs goes to TGW, TGW routes to the egress VPC (management), and the egress VPC's NAT GW handles internet translation.

This works because TGW acts as a router between VPCs, not as a peering extension. The management VPC's NAT GW sees traffic from its own TGW attachment (a management VPC resource), not from the originating integrator VPC.

### Finding 5: One TGW route table design that works without extra complexity

The simplest design uses a single TGW route table with:
- `0.0.0.0/0` → management VPC attachment (for internet egress from all integrators)
- `10.255.0.0/16` → management VPC attachment (for direct management traffic, optional)
- `10.1.0.0/24` → almaviva attachment
- `10.1.1.0/24` → redebrasil attachment
- ... (one per integrator, for return traffic)

Management VPC TGW attachment route table:
- `0.0.0.0/0` → existing management NAT GW (already exists, no change)
- Routes back to integrator CIDRs → TGW (added alongside existing peering routes during migration, then peering routes removed after)

---

## Migration Plan (Phased)

### Phase 0: Baseline validation (before any change)

- Document current NAT Gateway EIPs per integrator (clients may have whitelisted them)
- Check if any client has whitelisted the integrator's NAT GW EIP in their firewall
- Confirm Datadog is sending metrics from all integrators (validate baseline)

**Risk:** If clients have whitelisted the NAT GW EIP, changing to a shared NAT GW will change the outbound IP. Need to communicate new EIP to clients before migration.

### Phase 1: Create TGW and attach management VPC

Terraform changes in `networking/`:
```hcl
resource "aws_ec2_transit_gateway" "main" {
  description                     = "Centralized egress for integrator VPCs"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"

  tags = { Name = "4shark-main" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "management" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.management.id
  subnet_ids         = [aws_subnet.management_pub_2a.id]

  tags = { Name = "management" }
}

resource "aws_ec2_transit_gateway_route_table" "spoke" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = { Name = "spoke-to-egress" }
}

resource "aws_ec2_transit_gateway_route_table" "egress" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  tags = { Name = "egress" }
}

# Default route in spoke RT: all traffic goes to management (internet egress)
resource "aws_ec2_transit_gateway_route" "spoke_default" {
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.spoke.id
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.management.id
}
```

**Impact:** Zero. No routes changed. TGW created, management attached, nothing routes through it yet.

### Phase 2: Pilot migration — one integrator (recommended: almaviva)

Choose the integrator with the least critical traffic or easiest rollback. Almaviva has 2 app servers and a simple client VPN.

Terraform changes:
1. Add TGW attachment for almaviva VPC
2. Add almaviva CIDR to TGW spoke route table
3. Add return route in management VPC RT: `10.1.0.0/24 → TGW` (alongside existing peering route — longest prefix match keeps peering for management↔integrator internal traffic)
4. **Flip**: change almaviva's private RT `0.0.0.0/0` from NAT GW to TGW attachment
5. Validate: Datadog metrics arrive, can reach GitHub, can `apt-get update`
6. If OK: delete almaviva NAT GW and EIP (save $68/month)

**Rollback (if something breaks):** Change `0.0.0.0/0` back to NAT GW. The NAT GW is not deleted until validation passes.

**Observation window:** 24 hours minimum before deleting the NAT GW.

### Phase 3: Migrate remaining integrators (one at a time)

Same steps as Phase 2, one per integrator. Suggested order:
1. almaviva (pilot)
2. maqnelson
3. commcenter
4. aster-maquinas
5. redebrasil
6. out-atento-br
7. atento-br (most complex: has Redis/ElastiCache, more app servers)

Each migration can be done on separate days. No urgency to batch them.

### Phase 4 (optional): Remove VPC peerings

After all integrators migrate to TGW, the peerings to management serve only internal traffic (10.255.0.0/16 from integrators, and integrator CIDRs from management). These can be replaced with TGW routes to consolidate all traffic through TGW.

This step is **optional** — peerings are free for same-region traffic, so there is no cost benefit to removing them. The benefit is operational simplicity.

---

## CIDR Overlap Check

All integrator CIDRs are unique and non-overlapping:

```
10.1.0.0/24    almaviva
10.1.1.0/24    redebrasil
10.1.2.0/24    maqnelson
10.1.3.0/24    commcenter
10.1.4.0/24    aster-maquinas
10.12.0.0/26   out-atento-br
10.12.255.0/24 atento-br
10.255.0.0/16  management
```

No conflicts. TGW route table can accommodate all without ambiguity.

---

## Cost Analysis

### Current (monthly)
- 7 integrator NAT GWs × ~$68/month = **$476/month**
- 1 management NAT GW = **$68/month** (existing, keeps existing)
- **Total: $544/month**

### After migration (monthly)
- 0 integrator NAT GWs = **$0**
- 1 management NAT GW (shared) = **$68/month**
- 8 TGW attachments × $0.05/hr × 730h = **$292/month**
- TGW data processing $0.02/GB (estimated ~$10-20/month based on current NAT bytes)
- **Total: ~$370-380/month**
- **Savings: ~$164-174/month (~$2,000/year)**

### Break-even
No upfront cost. Savings start from month 1 of each migrated integrator.
Almaviva alone saves $68 - $36 (its share of TGW cost) = ~$32/month net from day 1.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Client has whitelisted NAT GW EIP | Medium | High | Survey all clients before migration; coordinate EIP change |
| Asymmetric routing during transition | Low | Medium | Keep peering intact; TGW only changes default route |
| TGW route table misconfiguration | Low | High | Test with pilot integrator 24h before proceeding |
| TGW bandwidth limits | Very Low | Low | TGW bursts to 50Gbps; integrators are t3.small/medium |
| Management NAT GW becomes bottleneck | Very Low | Medium | Can add second NAT GW in management if needed |

### Key risk: Client IP whitelisting

The management NAT GW EIP is already a shared IP (used by management VPC). After migration, all integrators will egress via this same EIP. This is a **client-facing change** — any client that has whitelisted the integrator's current NAT GW EIP in their corporate firewall will lose connectivity.

**Action required before any migration:** Confirm with each client whether they whitelist the NAT GW EIP. If yes, provide the new EIP (management NAT GW) in advance and request firewall update before migration.

---

## Conclusion

**The TGW centralized egress migration is viable, safe, and incremental.**

Key answers to the original questions:
1. **TGW + peerings coexist:** YES. No conflict. Migration preserves admin access throughout.
2. **Incremental migration:** YES. One integrator at a time, each reversible in minutes.
3. **VGW unaffected:** YES. Client VPN routes are more specific than `0.0.0.0/0` and are never touched.
4. **Biggest risk:** Client IP whitelisting. Must be surveyed before starting.

Recommended next step: survey whether any client whitelists the integrator NAT GW EIP, then proceed with Phase 1 (TGW + management attachment) which has zero blast radius.
