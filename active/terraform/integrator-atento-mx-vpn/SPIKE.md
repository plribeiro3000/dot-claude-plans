# SPIKE — Atento Simplex VPN: where to place the new site-to-site VPN

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-14
**Status:** Completed

---

## Goal

Atento requested a new site-to-site VPN so 4Shark can reach the Simplex system (non-normalized database) during development of the integrator for Atento Mexico. The Simplex appears to be used at least in Mexico and Colombia (one instance per country? shared? unknown).

The spike answers:

1. Where should the new VPN terminate on the 4Shark side?
   - Inside `vpc-integrator-atento`?
   - Inside `vpc-management`?
   - In a dedicated VPC (`vpc-partner-simplex` or equivalent)?
   - Through a Transit Gateway hub?
2. Can the existing Atento VPN be reused, or is a new tunnel required?
3. What is the scaling strategy for future partner systems (Simplex CO, other Atento systems, other clients)?
4. What information does 4Shark need to fill the VPN form Atento provided?

---

## Method

- Reviewed the current Terraform stacks related to Atento (`integrator-atento`, `app-atento-001`, `app-atento-br`) and shared VPN module (`modules/integrator/vpn.tf`).
- Analyzed the VPN S2S form sent by Atento (`Formato VPN S2S Atento-Cliente.docx`) — extracted parameters, peer IP, and data center.
- Worked through architectural options (peering mesh, Transit Gateway hub-and-spoke, dedicated partner VPC, direct VPN in integrator VPC) and tradeoffs.
- Interpreted the email thread from Moises Lindo (Atento Peru) and Jessica Mathias (Atento Brazil) to understand who owns the information we are still waiting on.

---

## Evidence

### Context — current state

- **Scaling patterns already in use across integrator clients**:
  - Simple integrators (Almaviva, Rede Brasil, Maqnelson): one cluster per client, normalized base only.
  - Commcenter: two clusters per client (production + homologation).
  - Atento: multiple accounts inside one client network (one per country — BR, CL, CO, MX — see `integrator-atento/compute_*.tf`).
- **New requirement for Atento**: beyond the normalized base, integrator will also read from a non-normalized database (Simplex). Data access must go through a site-to-site VPN into Atento's infrastructure.
- **Consumers of the new VPN** (as scoped by the engineer):
  - Today: engineer laptop (via Pritunl / `vpc-management`) to develop and test.
  - Possibly later: a 4Shark-hosted app that talks to Simplex — if Atento ever decides the C# Simplex extractor should run on 4Shark's side. Currently it runs on Atento's infra.
  - The `vpc-integrator-atento` itself and any other client's VPC are **not** consumers. This VPN is dedicated to Atento only.

### Current Atento VPN (already in place)

From `integrator-atento/main.tf:38-40`:

```hcl
enable_vpn             = true
customer_gateway_ip    = "48.214.37.228"
customer_network_cidrs = ["10.101.30.0/24"]
```

From `modules/integrator/vpn.tf`:

- Creates `aws_vpn_gateway` attached to the integrator VPC, `aws_customer_gateway` with the customer IP, and one `aws_vpn_connection` with `static_routes_only = true`.
- Phase 1 / Phase 2 algorithm lists include AES256, SHA2-256, DH Group 14 — matching what the new Atento form requires.
- **Limitation**: the module supports exactly one VPN per stack. `customer_gateway_ip` is a string; `aws_vpn_connection.this` is a single resource.

### Atento VPN S2S form — parameters provided

Data center: **Equinix Querétaro (Mexico)**.

| Field | Atento value |
|---|---|
| Firewall | Palo Alto Networks 5220 |
| IKE Peer (Atento) | `200.188.12.42` |
| Authentication method | Pre-shared Key (exchanged by call) |
| IKE version | IKEv2 only |
| Negotiation mode | Auto |
| P1 Authentication Algorithm | SHA 256 |
| P1 Encryption Algorithm | AES256 |
| P1 DH Group | Group 14 |
| P1 Lifetime | 28800 minutes |
| P1 Passive Mode | No |
| P1 NAT Traversal | No |
| P2 Authentication method | ESP |
| P2 Encryption Algorithm | AES256 |
| P2 Authentication Algorithm | SHA 256 |
| P2 DH Group | Group 14 |
| P2 Encapsulation | Tunnel |
| P2 Perfect Forward Secrecy | No |
| P2 Lifetime | 3600 seconds |
| Domain Encryption (Productivo) | *blank — Atento to fill* |
| Domain Encryption (Pruebas) | *blank — Atento to fill* |

Yellow fields (4Shark to fill):
- VPN Device Description → AWS Virtual Private Gateway
- Trademark product → Amazon Web Services
- IKE Peer (4Shark side) → 2 public IPs (AWS generates 2 tunnels). Only known after `terraform apply`.
- Pre-shared key → coordinated by call.
- Domain Encryption (our side) → 4Shark CIDRs that need to reach Simplex (TBD — likely private subnets of `vpc-integrator-atento`).

### Email thread interpretation

- **Jessica Mathias (Atento BR)** forwarded the form and mentioned a GitHub user access ticket that was rejected; a new one was opened. Not the technical owner.
- **Moises Lindo (Atento PE)** replied escalating to the Mexico team (Miguel Angel Delgadillo, Alejandro Blanquel): *"Quisiera la intervención de nuestros amigos de México [...] para que nos brinde esta información. Lo que queremos es que se tengan acceso a las BBDD de Simplex: 10.214.0.123 (QA), 10.214.0.122 (PROD)"*.
- **Important distinction**: the IPs Moises listed are the **goal** (the database hosts 4Shark needs to reach), not the network configuration response. The Domain Encryption CIDRs for the form must still be provided by the Mexico team. Do not confuse the goal with the config answer.

### Architectural options considered and discarded

**Option 1 — Transit Gateway as a backbone hub, with `vpc-partner-<system>` per partner.**
Discarded. The engineer clarified the scope is one client only: the Simplex VPN will be consumed exclusively by `vpc-integrator-atento` and `vpc-management`. No shared partner-network concept across clients. TGW's value (hub-and-spoke routing with fine-grained route tables) does not pay off for two consumers.

**Option 2 — VPN inside `vpc-management`.**
Discarded. Works today (engineer-only access), but if a 4Shark-hosted workload ever needs to reach Simplex, management is not the correct home — it would force app-to-partner traffic through management, which is not its role. Costly to migrate later.

**Option 3 — Dedicated `vpc-partner-simplex` VPC with peering to both `vpc-management` and `vpc-integrator-atento`.**
Discarded. Initially attractive because it decouples VPN lifecycle from integrator VPC and absorbs future CIDR collisions between countries. But IPsec S2S VPNs natively support multiple CIDRs in the same tunnel (policy-based traffic selectors or route-based with BGP). Adding a second system from Atento = adding CIDRs to the existing tunnel, not a new VPC. Creating a dedicated VPC now is anticipation of a problem that standard IPsec already handles.

**Option 4 — VPN inside `vpc-integrator-atento` (chosen).**
Chosen. The VPN terminates in the same VPC where the integrator lives. Management access is handled via the existing management ↔ integrator peering. Future systems behind the same Atento VPN endpoint are added as extra CIDRs in the tunnel, not new infrastructure. Only revisited if a real CIDR collision between countries appears — at which point the decision is tactical (split into a second VPN), not a topology change.

### Can the existing VPN be reused?

No. The existing VPN points at peer `48.214.37.228`; the new form points at `200.188.12.42` (Equinix Querétaro). Different peer IP = different gateway = different tunnel required. The existing tunnel cannot be extended to reach Querétaro because the current Atento gateway does not route there.

### CIDR collision check (so far)

- Existing Atento VPN customer CIDR: `10.101.30.0/24`.
- Simplex target hosts mentioned by Moises: `10.214.0.122`, `10.214.0.123`.
- No collision between `10.101.30.0/24` and `10.214.0.x`. But this is not the final answer — the Mexico team still needs to provide the formal Domain Encryption CIDRs, which may be broader than the two host IPs.

---

## Conclusions

1. **The new VPN lives inside `vpc-integrator-atento`.** Same VPC as the existing Atento VPN and the integrator workloads.
2. **A new tunnel is required** — the existing one cannot be extended to reach Querétaro.
3. **Implementation approach**: add the second VPN as loose resources (`aws_customer_gateway` + `aws_vpn_connection` + routes) directly in `integrator-atento/`, reusing the existing `aws_vpn_gateway`. Do **not** extend `modules/integrator/vpn.tf` to support a list — that would force a multi-VPN abstraction onto clients that do not need it. Atento is the exception; keep the exception contained in the Atento stack.
4. **Future partner systems at Atento** (e.g., another non-normalized source) are absorbed by adding their CIDRs to the same tunnel's traffic selectors. No new infrastructure.
5. **Multi-country Simplex (MX vs CO) remains an open topology question**, deferred:
   - If CIDRs do not collide between countries → same tunnel, add CIDRs.
   - If CIDRs collide → at that moment, create a second VPN (still inside `vpc-integrator-atento`). Only if something else forces it — e.g., Atento requires a separate gateway per country — will the dedicated VPC discussion reopen.
6. **TGW is not justified at the current scope**. Existing usage of TGW elsewhere (integrator egress) is a separate concern and does not change this decision.

---

## Next Steps

1. **Wait for the Mexico team (Miguel Angel Delgadillo, Alejandro Blanquel)** to provide the Domain Encryption CIDRs (Productivo + Pruebas) that Atento will route through the tunnel. Email reply sent in Spanish requesting a meeting to unblock.
2. **Decide on the 4Shark-side Domain Encryption CIDRs** — which subnets/hosts from `vpc-integrator-atento` are exposed to Simplex. Likely the two private subnets already used by the integrator.
3. **Implementation (deferred until CIDRs are known)**:
   - Add `aws_customer_gateway` for peer `200.188.12.42` in `integrator-atento/`.
   - Add `aws_vpn_connection` reusing the existing VGW, with algorithm constraints matching the Atento form.
   - Add `aws_vpn_connection_route` entries for each Simplex CIDR.
   - Align pre-shared key with Atento by call.
   - After `terraform apply`, send back the two AWS tunnel public IPs so Atento can configure the Palo Alto side.
4. **This spike should graduate to a PLAN.md** once Atento provides the missing CIDRs. Implementation is straightforward; no further open architectural questions at this point.
