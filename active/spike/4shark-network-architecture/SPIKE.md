# SPIKE — Ideal Network Architecture for 4Shark Multi-Region AWS Infrastructure

**Conducted by:** Engineering Team
**Date:** 2026-03-03
**Status:** Research complete — pending decisions

---

## Goal

This spike investigates the ideal network architecture for 4Shark's AWS infrastructure across two regions (us-east-1 and sa-east-1). The investigation is needed because the current us-east-1 layout has organically grown into an inconsistent state: multiple environments share a single VPC, Beta lives in its own isolated VPC, and the Atento customer has yet another separate VPC — with no consistent design principle guiding any of it.

### Questions to answer

1. Should us-east-1 replicate the hub-and-spoke model that works well in sa-east-1?
2. Should each environment (beta, demo, shared, atento, setup) have its own VPC?
3. What are AWS best practices for multi-environment networking at this scale?
4. What CIDR allocation strategy should be adopted going forward?
5. Should Transit Gateway replace VPC Peering, or is VPC Peering sufficient?
6. What would it take to migrate from the current state to an ideal state?
7. Is it worth the migration effort, or is consolidating beta into the Production VPC a simpler path?
8. Does AWS Organizations / Control Tower make sense for a 3-engineer team?

---

## Method

- Reviewed current Terraform code in `/Users/plribeiro3000/Projects/4Shark/terraform/networking/` for all VPCs, subnets, NAT gateways, and peering connections
- Researched AWS official documentation: Well-Architected Framework (REL02-BP04), multi-VPC network infrastructure whitepaper, Transit Gateway documentation
- Researched pricing for Transit Gateway, NAT Gateway, and cross-region VPC peering data transfer
- Searched community experience on VPC Peering vs Transit Gateway decision points for small teams
- Searched AWS recommendations for dedicated vs shared VPC per environment
- Searched for AWS Organizations / Control Tower suitability for small teams

---

## Evidence

### E1 — Current Architecture Analysis

#### E1.1 — Complete VPC Inventory

| VPC | Region | CIDR | Purpose | Peered To |
|-----|--------|------|---------|-----------|
| Management | sa-east-1 | 10.255.0.0/16 | Hub: VPN (Pritunl) + auth-001 (Keycloak) | All spokes |
| almaviva | sa-east-1 | 10.1.0.0/24 | Integrator + site-to-site VPN to customer | Management |
| redebrasil | sa-east-1 | 10.1.1.0/24 | Integrator + site-to-site VPN to customer | Management |
| maqnelson | sa-east-1 | 10.1.2.0/24 | Integrator + site-to-site VPN to customer | Management |
| commcenter | sa-east-1 | 10.1.3.0/24 | Integrator + site-to-site VPN to customer | Management |
| aster-maquinas | sa-east-1 | 10.1.4.0/24 | Integrator + site-to-site VPN to customer | Management |
| atento-br | sa-east-1 | 10.12.255.0/24 | Integrator + site-to-site VPN to customer | Management |
| out-atento-br | sa-east-1 | 10.12.0.0/26 | App server for atento-br | Management |
| Production | us-east-1 | 10.254.0.0/16 | Shared: demo-001, shared-001, atento-001, setup | Management |
| Beta | us-east-1 | 10.154.0.0/16 | Dedicated: beta-001 only | Management |
| 4app-atento | us-east-1 | 10.2.1.0/24 | Atento customer app (origin unclear) | Management |

**Total VPCs: 11**
**Total cross-region peerings: 3** (Production↔Management, Beta↔Management, 4app-atento↔Management)
**Total same-region peerings: 7** (6 integrators + out-atento-br, all ↔ Management)

#### E1.2 — Current NAT Gateway Count

| VPC | Region | NAT GWs | Monthly Base Cost (USD) |
|-----|--------|---------|------------------------|
| Management | sa-east-1 | 1 | ~$67.00 |
| Production | us-east-1 | 2 | ~$65.70 |
| Beta | us-east-1 | 1 | ~$32.85 |
| 4app-atento | us-east-1 | 1 | ~$32.85 |
| almaviva | sa-east-1 | (none confirmed in TF) | — |
| redebrasil | sa-east-1 | (none confirmed in TF) | — |
| maqnelson | sa-east-1 | (none confirmed in TF) | — |
| commcenter | sa-east-1 | (none confirmed in TF) | — |
| aster-maquinas | sa-east-1 | (none confirmed in TF) | — |
| atento-br | sa-east-1 | (none confirmed in TF) | — |
| out-atento-br | sa-east-1 | 1 | ~$67.00 |

Estimated NAT Gateway base cost (hourly charges only, no data processing): ~$265/month for the confirmed gateways above.

Note: Both NAT gateways in the Production VPC use the same subnet (`production_pub_a`), which is a bug in the current configuration (line 109 of `vpc_production.tf`). True AZ redundancy is not achieved.

#### E1.3 — Strengths of the Current Architecture

- **sa-east-1 is well-designed**: true hub-and-spoke, all spokes isolated from each other, Management is the single gateway to all integrators
- **VPN traffic is correctly NAT'd**: source IP appears as 10.255.x.x regardless of which spoke the user reaches, simplifying security group rules
- **SSM parameters provide a clean contract**: networking outputs are published via SSM, decoupling the networking state from application stacks
- **Terraform fully manages the network**: no manual state drift, centralized in `networking/`

#### E1.4 — Weaknesses and Risks

**W1 — No environment isolation in Production VPC (us-east-1)**
Four environments (demo-001, shared-001, atento-001, setup) share 4 subnets. Any misconfigured security group in one environment could reach resources in another. There is no network-level blast radius containment.

**W2 — Beta VPC is isolated without a good reason**
Beta has its own VPC (10.154.0.0/16) with its own NAT Gateway and its own peering to Management. This means the team manages extra infrastructure just to access beta via VPN. It's not clear what isolation benefit beta gets from this separation since there is no customer data in beta.

**W3 — 4app-atento VPC origin is unclear**
`vpc_4app_atento.tf` comments say "needs verification." It has a tiny CIDR (10.2.1.0/24), its own NAT gateway (~$32.85/month base), and its own cross-region peering. This appears to be an abandoned or transitional VPC from before atento-001 moved into the Production VPC. If unused, it is wasting money.

**W4 — Production VPC CIDR over-provisioned**
10.254.0.0/16 is a massive /16 allocated to what is effectively a shared environment. The subnets (/22 each = 1022 hosts per subnet) are generously sized but provide no isolation between the 4 environments using them.

**W5 — No us-east-1 hub VPC**
Cross-region peering goes directly from Management (sa-east-1) to each app VPC in us-east-1. If a new environment needs to be added, it requires a new cross-region peering to Management. With VPC peering, each app VPC must know Management's CIDR and vice versa — this is manageable now but grows linearly with each addition.

**W6 — VPC peering does not support transitive routing**
VPC peering is not transitive. If Production VPC needs to talk to another spoke, it cannot go through Management as a router — it would need a direct peering. Currently this is not a stated requirement, but it limits future architectural flexibility.

**W7 — NAT Gateway bug in Production VPC**
Both `production_az_a` and `production_az_b` NAT Gateways are placed in `production_pub_a`, not one each in pub_a and pub_b. Traffic from AZ B going outbound uses a NAT GW in AZ A, incurring unnecessary cross-AZ data transfer charges ($0.01/GB).

---

### E2 — AWS Best Practices for Multi-Environment Networking at This Scale

#### E2.1 — AWS Well-Architected Framework (REL02-BP04)

Source: [AWS Well-Architected Reliability Pillar — REL02-BP04](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_planning_network_topology_prefer_hub_and_spoke.html)

AWS explicitly recommends hub-and-spoke topologies over many-to-many mesh. Key guidance:
- Use AWS Transit Gateway as the hub
- Route only between networks that need to communicate (deny by default)
- Place Transit Gateway in a dedicated Network Services account
- Use /28 subnets for Transit Gateway attachments to preserve address space
- Avoid providing routes between networks that have no interdependencies

This is already applied correctly in sa-east-1. It is not applied in us-east-1.

#### E2.2 — Dedicated VPC per Environment

Source: [AWS Networking & Content Delivery Blog — VPC Sharing](https://aws.amazon.com/blogs/networking-and-content-delivery/vpc-sharing-key-considerations-and-best-practices/)
Source: [AWS Whitepaper — Building Scalable and Secure Multi-VPC Networks](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/amazon-vpc-sharing.html)

AWS best practice is to create **one VPC per application environment**. The reasons:
- Network-level blast radius containment: a misconfigured SG in demo cannot reach shared or production resources
- Independent lifecycle: environments can be torn down and rebuilt without affecting others
- Security audit clarity: each VPC has its own flow logs, making incident investigation straightforward
- Route table isolation: environments cannot route to each other unless explicitly configured

The alternative (VPC sharing with subnets) only makes sense in a strict multi-account setup and is not applicable here since 4Shark uses a single account.

#### E2.3 — AWS Organizations and Control Tower for Small Teams

Source: [AWS Control Tower Documentation](https://docs.aws.amazon.com/controltower/latest/userguide/what-is-control-tower.html)

AWS Organizations + Control Tower is free at the service level (you pay for underlying resources). However, for a 3-engineer team using Terraform for all infrastructure:
- Control Tower is console-driven by default and conflicts with a pure Terraform workflow
- Multi-account brings significant overhead: separate billing, IAM cross-account roles, RAM sharing for VPCs/Transit Gateway
- The team does not have compliance or regulatory requirements stated that would require account-level isolation
- Control Tower adds value at 5+ accounts or when compliance guardrails (SOC2, PCI) are needed

**Conclusion for 4Shark**: AWS Organizations / Control Tower is not warranted at this scale and team size. Single-account with VPC-level isolation is appropriate.

---

### E3 — Transit Gateway vs VPC Peering

#### E3.1 — Pricing Comparison

Source: [AWS Transit Gateway Pricing](https://aws.amazon.com/transit-gateway/pricing/)
Source: [AWS VPC Pricing](https://aws.amazon.com/vpc/pricing/)

**Transit Gateway costs (us-east-1):**
- Attachment fee: $0.05/hour per VPC attached = $36.50/month per VPC
- Data processing: $0.02/GB per GB sent through the gateway
- Cross-region peering attachment: $0.05/hour per side = $36.50/month per TGW peering

**VPC Peering costs:**
- The peering connection itself: free
- Data transfer (intra-region, same AZ): free
- Data transfer (intra-region, cross-AZ): $0.01/GB per side (new 2025 billing clarification)
- Data transfer (cross-region): standard inter-region rates apply

**Cross-region data transfer (us-east-1 ↔ sa-east-1):**
- Outbound from us-east-1: ~$0.02/GB
- Outbound from sa-east-1 (São Paulo): ~$0.138/GB (São Paulo has higher egress rates)
- This cost applies equally to both Transit Gateway peering and VPC Peering for cross-region traffic

#### E3.2 — Cost Scenario for 4Shark

**Current state (VPC Peering, 3 cross-region peerings):**
- Peering cost: $0/month
- Total peerings to manage: 10 (3 cross-region + 7 same-region)

**Scenario A: Add Transit Gateway in us-east-1 only (hub for app VPCs)**
- 1 TGW in us-east-1
- Attachments needed: 1 per app VPC. If 5 dedicated VPCs (beta, demo, shared, atento, setup): 5 × $36.50 = $182.50/month
- Plus 1 cross-region TGW peering to Management: $36.50/month (us-east-1 side) + $36.50/month (sa-east-1 side) = $73/month
- **Additional cost vs current: ~$255.50/month**

**Scenario B: Add Transit Gateway in both regions**
- 1 TGW in us-east-1 + 1 TGW in sa-east-1
- us-east-1 attachments (5 app VPCs): $182.50/month
- sa-east-1 attachments (7 integrator VPCs + Management): 8 × $36.50 = $292/month
- Cross-region TGW peering: $73/month
- **Additional cost vs current: ~$547.50/month**

**Scenario C: Keep VPC Peering, add 4 dedicated VPCs in us-east-1**
- No TGW cost
- 4 additional cross-region peerings (one per new app VPC)
- Peering management grows: 14 total peerings
- No additional monthly fixed cost beyond NAT Gateways for new VPCs
- New NAT Gateways: 4 × $32.85 = $131.40/month (if one per VPC, no redundancy)

#### E3.3 — Operational Complexity Comparison

| Dimension | VPC Peering | Transit Gateway |
|-----------|------------|----------------|
| Max connections per VPC | 125 | 5,000 per TGW |
| Transitive routing | Not supported | Supported |
| Route management | Manual per RT | Centralized in TGW RTs |
| Cross-region | Supported | Supported (TGW peering) |
| Terraform complexity | Moderate (routes per RT) | Lower (attach + TGW RT) |
| Cost at 5-15 VPCs | Lower | Significantly higher |
| Break-even (TGW vs Peering) | — | ~10+ VPCs where mesh becomes unmanageable |

At 11 current VPCs with 3 cross-region peerings and 7 same-region peerings, 4Shark is below the threshold where Transit Gateway provides operational savings that offset its cost. The management overhead is real but manageable with Terraform.

Source: [AWS Medium — Difference Between VPC Peering and Transit Gateway](https://medium.com/awesome-cloud/aws-difference-between-vpc-peering-and-transit-gateway-comparison-aws-vpc-peering-vs-aws-transit-gateway-3640a464be2d)
Source: [Ably Engineering Blog — VPC Peering vs Transit Gateway and Beyond](https://ably.com/blog/aws-vpc-peering-vs-transit-gateway-and-beyond)

---

### E4 — Hub-and-Spoke Pattern Applied to us-east-1

The sa-east-1 design has Management VPC as the hub. Traffic flows:
```
[VPN Client] → [Pritunl/Management] → [peering] → [integrator VPC]
                                     → [peering] → [Production VPC]
                                     → [peering] → [Beta VPC]
```

To replicate this in us-east-1 with a dedicated hub, one option is:

**Option 1: Mirror sa-east-1 — add a us-east-1 Hub VPC**
- Create a new "hub-us-east-1" VPC (e.g., 10.253.0.0/16)
- Peer it to Management (sa-east-1) — single cross-region peering
- Peer each app VPC in us-east-1 to this hub
- VPN routes would then reach us-east-1 apps via: Management → hub-us-east-1 → app VPC

Problem: VPC peering is **not transitive**. The hub VPC cannot forward traffic between Management and app VPCs unless the hub itself has routes for both and you use a NAT instance or similar routing appliance. A plain VPC peering hub does not work as a router.

This means a true hub-and-spoke with a single cross-region entry point requires either:
- **Transit Gateway** (supports transitive routing)
- **An EC2-based router/NAT instance** in the hub (complex, operational risk)

**Option 2: Keep direct peering from Management to each app VPC (current model)**
- Each app VPC in us-east-1 has its own peering to Management
- VPN pushes routes for all app VPC CIDRs
- Works today, scales linearly with more app VPCs
- No transitive routing needed since the VPN client receives routes from Management directly

This is the current design and it works correctly for the access pattern (VPN → Management → app). The only downside is that each new environment needs a new cross-region peering.

**Option 3: Transit Gateway in us-east-1 only**
- Single TGW in us-east-1 with all app VPCs attached
- One cross-region peering: TGW (us-east-1) ↔ Management VPC (sa-east-1)
- Management VPC routes all us-east-1 traffic to the TGW peering
- TGW routes to individual app VPCs
- Adding a new environment = new TGW attachment (no new cross-region peering)
- Cost: ~$255.50/month additional (see E3.2, Scenario A)
- Provides transitive routing between app VPCs if ever needed

---

### E5 — Dedicated VPC per Environment: Analysis

#### E5.1 — Current state

Production VPC (10.254.0.0/16) hosts 4 environments sharing 4 subnets:
- demo-001
- shared-001 (production)
- atento-001
- setup

All 4 share the same route tables, the same NAT gateways, and the same security posture at the VPC level. Isolation is only via Security Groups.

#### E5.2 — Impact of Zero VPC Isolation

- **Security**: A misconfigured security group that allows `10.254.0.0/16` as a source would expose resources across all 4 environments. This is a real risk.
- **Blast radius**: If the Production VPC route table is misconfigured (e.g., a bad peering route), all 4 environments are affected simultaneously.
- **Audit**: VPC Flow Logs cannot differentiate environment-level traffic without filtering by subnet or instance tag.
- **Compliance**: Not a current concern, but shared VPCs make compliance audits harder.

#### E5.3 — Cost of Dedicated VPCs (No TGW)

If each of the 5 app environments (beta, demo, shared, atento, setup) gets its own VPC with 1 NAT Gateway and 1 cross-region peering:

- 5 NAT Gateways in us-east-1: 5 × $32.85 = $164.25/month (base, no data processing)
- Current state has 2 NAT GWs in Production + 1 in Beta + 1 in 4app-atento = 4 NAT GWs = $131.40/month
- Net increase: ~$32.85/month (one additional NAT GW)
- Cross-region peerings: from 3 to 5 (two new) — no fixed monthly cost
- Terraform routes to add: 4 additional peerings × ~4 routes each = ~16 new route resources

This is a modest cost increase for a meaningful security improvement.

---

### E6 — CIDR Allocation Strategy Recommendation

#### E6.1 — Current CIDR usage

```
10.1.0.0/24  — almaviva (integrator, sa-east-1)
10.1.1.0/24  — redebrasil (integrator, sa-east-1)
10.1.2.0/24  — maqnelson (integrator, sa-east-1)
10.1.3.0/24  — commcenter (integrator, sa-east-1)
10.1.4.0/24  — aster-maquinas (integrator, sa-east-1)
10.2.1.0/24  — 4app-atento (app, us-east-1) — likely legacy/unused
10.12.0.0/26 — out-atento-br (app, sa-east-1)
10.12.255.0/24 — atento-br (integrator, sa-east-1)
10.154.0.0/16 — Beta (app, us-east-1)
10.254.0.0/16 — Production (app, us-east-1)
10.255.0.0/16 — Management (hub, sa-east-1)
```

#### E6.2 — Problems with current CIDRs

- Beta and Production are both /16 but only use a tiny fraction of the space
- 10.1.x.x range is used for integrators but not sequentially (10.12.x.x breaks the pattern)
- 10.2.1.0/24 is a fragment with no apparent pattern
- No reserved range for future environments

#### E6.3 — Recommended CIDR Scheme

Use an RFC 1918 block with a structured hierarchy:

```
10.0.0.0/8 — Total RFC 1918 pool (all 4Shark)

  sa-east-1 (Brazil):
    10.255.0.0/16  — Management VPC (keep as-is, hub)
    10.1.0.0/8 sub-range reserved for integrators:
      10.1.0.0/24  — almaviva (keep)
      10.1.1.0/24  — redebrasil (keep)
      10.1.2.0/24  — maqnelson (keep)
      10.1.3.0/24  — commcenter (keep)
      10.1.4.0/24  — aster-maquinas (keep)
      10.1.5.0/24  — (reserved for next integrator)
      10.1.6.0/24  — (reserved)
    10.12.0.0/24   — atento-br integrator (keep 10.12.255.0/24 + consolidate out-atento-br)

  us-east-1 (USA) — new dedicated VPC scheme:
    10.100.0.0/16  — shared-001 (production)  [replaces 10.254.x.x share]
    10.101.0.0/16  — beta-001
    10.102.0.0/16  — demo-001
    10.103.0.0/16  — atento-001
    10.104.0.0/16  — setup
    10.105.0.0/16  — (reserved for next environment)
```

**Note on CIDR size for app VPCs:**
A /16 per environment is generous but a /20 (4096 IPs) is likely sufficient for any single app environment. Using /20 per environment allows up to 16 non-overlapping environments in the 10.100.0.0/16 supernet. However, using separate /16 blocks is simpler to reason about and there is no shortage of RFC 1918 space at this scale.

**Key principle**: Do not overlap with integrator ranges (10.1.x.x, 10.12.x.x) or Management (10.255.x.x). Keep all VPN-reachable CIDRs documented in a single place.

---

### E7 — Recommended Target Architecture

#### E7.1 — ASCII Diagram

```
                          ┌─────────────────────────────────────────────────┐
                          │                   sa-east-1                      │
                          │                                                   │
  [VPN Clients]           │  ┌──────────────────────────────────────────┐    │
       │                  │  │  Management VPC (10.255.0.0/16) [HUB]    │    │
       └──── OpenVPN ────►│  │  - Pritunl (VPN server)                  │    │
                          │  │  - auth-001 (Keycloak)                    │    │
                          │  │  NAT: 10.255.x.x (MASQUERADE)            │    │
                          │  └───┬──────┬──────┬──────┬──────┬──────┬───┘    │
                          │      │      │      │      │      │      │         │
                          │  peering  peering  ...                  │         │
                          │      │      │                          │peering   │
                          │  ┌───┘  ┌───┘                          │         │
                          │  │      │                              │         │
                          │ ┌┴──┐ ┌─┴──┐ ┌────┐ ┌────┐ ┌────┐ ┌──┴──┐     │
                          │ │alm│ │rede│ │maqn│ │comm│ │aste│ │aten │     │
                          │ │ava│ │bras│ │elso│ │cent│ │r-mq│ │to-br│     │
                          │ │ /24│ │/24 │ │/24 │ │/24 │ │/24 │ │/24  │     │
                          │ │ VGW│ │VGW │ │VGW │ │VGW │ │VGW │ │VGW  │     │
                          │ └─┬─┘ └─┬──┘ └─┬──┘ └──┬─┘ └─┬──┘ └──┬──┘     │
                          │   │     │      │       │     │      │          │
                          └───┼─────┼──────┼───────┼─────┼──────┼──────────┘
                              │     │      │ S2S VPN│     │      │
                          [Customer networks: Almaviva, Rede Brasil, Maqnelson,
                           CommCenter, Aster-Maquinas, Atento-BR]


                          ┌─────────────────────────────────────────────────────────┐
                          │                     us-east-1                            │
                          │                                                           │
                          │  ┌──────────────────────────────────────────────────┐    │
                          │  │   [Recommended] One VPC per environment          │    │
                          │  │                                                   │    │
                          │  │  shared-001 (10.100.0.0/16)                      │    │
                          │  │    - ECS services, RDS, ElastiCache               │    │
                          │  │    - NAT GW, IGW                                  │    │
                          │  │    - Peered to Management ──────────────────────► │    │
                          │  │                                                   │    │
                          │  │  beta-001 (10.101.0.0/16)                        │    │
                          │  │    - ECS services, RDS, ElastiCache               │    │
                          │  │    - NAT GW, IGW                                  │    │
                          │  │    - Peered to Management ──────────────────────► │    │
                          │  │                                                   │    │
                          │  │  demo-001 (10.102.0.0/16)                        │    │
                          │  │    - ECS services                                 │    │
                          │  │    - NAT GW, IGW                                  │    │
                          │  │    - Peered to Management ──────────────────────► │    │
                          │  │                                                   │    │
                          │  │  atento-001 (10.103.0.0/16)                      │    │
                          │  │    - ECS services, RDS                            │    │
                          │  │    - NAT GW, IGW                                  │    │
                          │  │    - Peered to Management ──────────────────────► │    │
                          │  │                                                   │    │
                          │  │  setup (10.104.0.0/16)                           │    │
                          │  │    - Mobile config services                       │    │
                          │  │    - NAT GW, IGW                                  │    │
                          │  │    - Peered to Management ──────────────────────► │    │
                          │  │                                                   │    │
                          │  │  [optional] future-env (10.105.0.0/16)           │    │
                          │  └──────────────────────────────────────────────────┘    │
                          │                                                           │
                          └─────────────────────────────────────────────────────────┘

Cross-region peerings (all → Management VPC sa-east-1):
  shared-001  ─── cross-region peering ──► Management
  beta-001    ─── cross-region peering ──► Management
  demo-001    ─── cross-region peering ──► Management
  atento-001  ─── cross-region peering ──► Management
  setup       ─── cross-region peering ──► Management

VPN routes pushed to clients:
  10.100.0.0/16, 10.101.0.0/16, 10.102.0.0/16,
  10.103.0.0/16, 10.104.0.0/16,
  10.255.0.0/16, 10.1.0.0/22, 10.12.0.0/24, 10.12.255.0/24
```

#### E7.2 — Why Not Transit Gateway

Transit Gateway would add ~$255/month for 5 app VPC attachments plus one cross-region TGW peering. For a cost-conscious team, this is not justified when:
- The current VPC peering model already works
- Traffic between app VPCs is not a stated requirement
- The number of peering connections (5 cross-region) remains manageable in Terraform
- The team already manages 10 peering connections today

Transit Gateway would become the right choice if:
- The number of us-east-1 VPCs grows beyond ~10
- Traffic between app VPCs is required (e.g., shared-001 calling into beta-001)
- Direct Connect is added (TGW integrates cleanly, VPC peering does not)

---

### E8 — Migration Effort Assessment

#### E8.1 — Option A: Minimum viable cleanup (3-5 days)

**What**: Consolidate beta into Production VPC, retire 4app-atento, fix the NAT GW bug.

**Steps:**
1. Confirm whether 4app-atento VPC is truly unused; if yes, destroy it (save ~$32.85/month)
2. Migrate beta-001 workloads into new subnets within the Production VPC
3. Remove Beta VPC peering and Beta VPC (save ~$32.85/month base)
4. Fix Production VPC NAT GW bug (move `production_az_b` to `production_pub_b`)
5. Update SSM parameters and environment Terraform stacks

**Cost impact**: Save ~$65/month (two fewer NAT GWs), eliminate one cross-region peering
**Risk**: Medium — beta migration requires workload downtime or blue/green cutover
**Isolation improvement**: None — all environments still share one VPC
**Effort**: ~3-5 engineer-days

#### E8.2 — Option B: Dedicated VPC per environment (3-4 weeks)

**What**: Give each environment its own VPC, CIDR, NAT GW, and peering to Management.

**Steps:**
1. Design and document new CIDR scheme (E6.3 above)
2. Create 5 new VPCs via Terraform (shared, beta, demo, atento, setup)
3. Establish 5 cross-region peerings to Management VPC
4. Create new SSM parameters per environment
5. Update each environment's Terraform stack to reference new VPC/subnet IDs
6. Migrate workloads one environment at a time (demo → atento → setup → beta → shared last)
7. Retire old Production VPC and Beta VPC (after all workloads migrated)
8. Update VPN route push list in Pritunl configuration
9. Update security groups across all environments

**Cost impact**: Net ~+$32.85/month (one extra NAT GW vs current 4 gateways)
**Risk**: High during migration (each environment needs workload migration)
**Isolation improvement**: Full network-level isolation between environments
**Effort**: ~3-4 engineer-weeks

#### E8.3 — Option C: New environments get dedicated VPCs, old ones stay (immediate + gradual)

**What**: Stop adding environments to Production VPC. Migrate existing ones only when there is another reason to touch them (e.g., scaling event, major refactor).

**Steps:**
1. Immediately: create dedicated VPC for any new environment
2. Immediately: retire 4app-atento if unused
3. Next opportunity (natural): migrate setup (smallest service)
4. Next quarter: migrate beta into its new dedicated VPC (maintain peering, no collapse into Production)
5. Long-term: migrate demo, atento, shared as capacity allows
6. Fix NAT GW bug in Production VPC now

**Cost impact**: No additional cost until new VPCs are created
**Risk**: Low (incremental)
**Isolation improvement**: Gradual improvement over time
**Effort**: 1-2 days now, then ~1 week per environment as they are migrated

---

### E9 — Cost Impact Summary

| Scenario | Additional Monthly Cost | One-time Effort | Isolation |
|----------|------------------------|-----------------|-----------|
| Do nothing | $0 | 0 | None (current) |
| Option A: Consolidate beta into Production | -$65/month savings | 3-5 days | Worse (more shared) |
| Option B: Dedicated VPC per env (VPC peering) | +$33/month | 3-4 weeks | Full |
| Option B + Transit Gateway (us-east-1) | +$290/month | 5-6 weeks | Full + transitive |
| Option C: Incremental (new envs get own VPC) | $0 now, +$33/month when complete | Days now + weeks later | Gradual |

Transit Gateway for sa-east-1 integrators only would cost +$292/month and is not recommended — the current same-region peering works fine at this scale.

---

## Conclusions

### Finding 1: The sa-east-1 architecture is sound — do not change it

The hub-and-spoke design with Management VPC as the hub and integrators as spokes is correct. The peering topology handles all current requirements. There is no case for Transit Gateway in sa-east-1 at the current integrator count (6 VPCs).

### Finding 2: The us-east-1 architecture has a structural problem worth fixing

Sharing 4 environments in one VPC is an anti-pattern that creates security risk and limits blast radius containment. AWS best practice recommends dedicated VPC per environment. The fix cost is modest (~$33/month net).

### Finding 3: Transit Gateway is not justified at the current scale

At 11 VPCs and no requirement for transitive routing between app VPCs, Transit Gateway adds $255-$547/month in fixed costs with no material operational benefit for a 3-engineer team. The break-even point is approximately 10+ VPCs needing mesh connectivity. If the company grows to 15+ environments, Transit Gateway should be re-evaluated.

### Finding 4: Beta should get its own dedicated VPC, not be merged into Production

Merging beta into Production VPC would worsen the isolation problem, not fix it. Beta already has its own VPC — the issue is that it has inconsistent sizing (/16 vs the pattern of other future dedicated VPCs). The right path is to migrate beta to the new CIDR scheme (10.101.0.0/16) or keep it as-is since it already has isolation.

### Finding 5: 4app-atento VPC is likely legacy and should be confirmed + removed

The VPC costs ~$32.85/month in NAT Gateway base fees. If app-atento-001 runs in the Production VPC (as suggested by the Production VPC comment), then 4app-atento is an orphan VPC. Confirm and destroy.

### Finding 6: AWS Organizations / Control Tower is not appropriate for this team

A single AWS account with VPC-level isolation is the right model for a 3-engineer, cost-conscious team using Terraform. Multi-account would add overhead without meaningful benefit until compliance requirements emerge.

### Recommendation

**Adopt Option C (incremental) with immediate quick wins:**

1. **Immediate (1-2 days):**
   - Confirm 4app-atento is unused and destroy it → save $32.85/month
   - Fix the NAT GW bug in Production VPC → save cross-AZ data transfer charges
   - Document the future CIDR scheme (E6.3) in the Terraform repo

2. **Short-term (1-2 weeks):**
   - Create dedicated VPC for setup (smallest, lowest risk migration)
   - Establish the pattern and Terraform module structure for environment VPCs
   - Update SSM parameter naming convention for consistency

3. **Medium-term (1 quarter):**
   - Migrate demo-001 to its own VPC
   - Migrate atento-001 to its own VPC

4. **Long-term:**
   - Migrate shared-001 (production) — highest risk, requires most care
   - Keep beta as-is (already isolated) or align its CIDR to the new scheme
   - Re-evaluate Transit Gateway if VPC count exceeds 15

**What to avoid:**
- Do not merge beta into Production VPC
- Do not implement Transit Gateway now
- Do not implement AWS Organizations / Control Tower now

---

## Next Steps

1. **Confirm 4app-atento status** — Is app-atento-001 in Production VPC or 4app-atento VPC? Ask the team, check ECS cluster definitions. This is a quick investigation (1 hour) that could yield an immediate $33/month saving.

2. **Decision needed**: Which option does the team want to pursue (A, B, or C)? The recommendation is C, but B is the correct long-term architecture. The engineer must decide the timeline.

3. **If Option B or C is chosen**: Use `@agent-planner` to create a PLAN.md for the networking migration — starting with the dedicated VPC for `setup` as the first environment.

4. **Fix the NAT GW bug now** — it is a standalone change with no dependencies and can be done as a separate PR on the current branch or a new one.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Sources consulted:**
> - [AWS Well-Architected — REL02-BP04: Prefer hub-and-spoke topologies](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_planning_network_topology_prefer_hub_and_spoke.html)
> - [AWS Whitepaper — Building Scalable and Secure Multi-VPC AWS Network Infrastructure (Transit Gateway)](https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/transit-gateway.html)
> - [AWS Transit Gateway Pricing](https://aws.amazon.com/transit-gateway/pricing/)
> - [Amazon VPC Pricing](https://aws.amazon.com/vpc/pricing/)
> - [AWS Blog — VPC Sharing: Key Considerations and Best Practices](https://aws.amazon.com/blogs/networking-and-content-delivery/vpc-sharing-key-considerations-and-best-practices/)
> - [AWS Prescriptive Guidance — Peer VPCs in different AWS Regions using Transit Gateway](https://docs.aws.amazon.com/prescriptive-guidance/latest/patterns/peer-vpcs-different-regions-transit-gateway.html)
> - [AWS re:Post — Transit Gateway Pricing for various environments](https://repost.aws/questions/QUaAhq7NuBQEqIis3Uz573Zg/transit-gateway-pricing-for-various-environments-that-i-have)
> - [Ably Engineering — VPC Peering vs Transit Gateway and Beyond](https://ably.com/blog/aws-vpc-peering-vs-transit-gateway-and-beyond)
> - [Awesome Cloud on Medium — Difference between VPC Peering and Transit Gateway](https://medium.com/awesome-cloud/aws-difference-between-vpc-peering-and-transit-gateway-comparison-aws-vpc-peering-vs-aws-transit-gateway-3640a464be2d)
> - [ClusterCost — AWS NAT Gateway Pricing 2025](https://clustercost.com/blog/aws-nat-gateway-pricing-2025/)
> - [AWS about-aws — Amazon VPC Peering billing update (April 2025)](https://aws.amazon.com/about-aws/whats-new/2025/04/amazon-vpc-peering-billing/)
