# PLAN — Atento Mexico Site-to-Site VPN

**Target stack**: `integrator-atento/` (sa-east-1)
**Module peer key**: `mx-equinix`
**Counterparty**: Atento MX, Palo Alto Networks 5220 firewall, Equinix Querétaro data center

> Architectural rationale and discarded alternatives are documented in [`SPIKE.md`](./SPIKE.md). This plan covers execution only.

## Objective

Establish a site-to-site VPN between the `integrator-atento` VPC (AWS sa-east-1, CIDR `10.12.255.0/24`) and Atento Mexico's internal network (behind a Palo Alto firewall in Equinix Querétaro, public IP via Axtel `200.188.12.42`), so ECS tasks running in the `integrator-atento` can reach Atento MX systems (Simplex and VKPI).

The integrator module's multi-VPN base (PR #347) is already in production — this plan uses the `integrator` module and adds the `mx-equinix` peer, with no further changes to shared infra required.

### Relationship with the pre-existing `azure` peer

The `integrator-atento` stack already had an active VPN before this work, with peer key `azure`. That VPN connects AWS to **Atento's central Azure infrastructure** (IP `48.214.37.228`) and is how 4Shark accesses the normalized database shared by all countries (BR/MX/CO/CL).

This new `mx-equinix` VPN is independent and serves a different purpose: reaching Atento MX **local systems** (Simplex, VKPI) running in their Equinix Querétaro data center, not in central Azure. Both VPNs share the same VGW (`vgw-05a609b1a6ea90519`) because AWS allows multiple VPN connections per VGW, but they are fully independent in terms of routing, credentials, and state.

## Current status (2026-04-22)

- ✅ **AWS infra provisioned**: CGW + VPN connection (via PR #347)
- ✅ **Technical handoff delivered** to Atento MX (2026-04-21): tunnel endpoints + PSKs via 1Password + email
- ⏸ **Tunnels DOWN**: waiting on Atento MX to configure their Palo Alto 5220
- ⏸ **AWS routes not added**: blocked on Atento MX internal CIDR
- **Next step**: wait for Atento MX response with (a) remote CIDR and (b) confirmation they configured the Palo Alto

**No committed timeline**: Atento MX has not committed to a response timeframe. Could be days, weeks, or longer. Not active urgency on our side — the wait is on them, to configure the firewall and inform the CIDR.

### Resumption checklist (when Atento MX responds)

Before executing Phase 3, verify:

- [ ] Is the 1Password link still valid? (expires ~2026-05-06; if expired, regenerate via Desktop App restricted to the same emails or to whoever they indicate)
- [ ] Email reply from Atento MX with **remote CIDR** received?
- [ ] Did they confirm the actual Palo Alto config (PFS/DH14 and lifetime unit)?
- [ ] Current AWS tunnel status:
  ```
  aws ec2 describe-vpn-connections --vpn-connection-ids vpn-0c686081cfb9eebf2 --region sa-east-1 --query 'VpnConnections[0].VgwTelemetry'
  ```
  If already `UP` from their side, Phase 3 only adds routes. If `DOWN`, understand what is blocking before apply (likely some IKE/IPsec parameter mismatch).

## Scope

### In scope
- Deliver credentials (PSKs) and technical data to Atento MX
- Receive remote CIDR from them
- Add AWS routes (`aws_vpn_connection_route` + `aws_route`) so traffic flows
- Validate end-to-end connectivity (ECS task → MX host)

### Out of scope
- Specific port/protocol security group rules (separate follow-up if needed)
- Application workloads consuming these hosts (app layer, not infra)
- Other Atento VPNs (existing Brazil/Azure, future Colombia, Chile)

## Phases

### Phase 1 — Provision AWS infra — ✅ DONE (via PR #347, 2026-04-21)

Resources created:
- `aws_customer_gateway.this["mx-equinix"]` = `cgw-095a980c99d64342e` pointing at `200.188.12.42`
- `aws_vpn_connection.this["mx-equinix"]` = `vpn-0c686081cfb9eebf2` sharing VGW `vgw-05a609b1a6ea90519` with the `azure` peer (Atento BR)
- `customer_network_cidrs = []` — no routes yet, intentional

### Phase 2 — Technical handoff — ✅ DONE (2026-04-21)

Delivered to Atento MX via email to Pedro Cardenas (pedro.cardenas@atento.com), Yoneison Carreno (yoneison.carreno@atento.com), with copy to Santiago (4shark) and others:

| Item | Value | Channel |
|---|---|---|
| Tunnel 1 AWS endpoint | `54.94.234.36` | Email |
| Tunnel 2 AWS endpoint | `54.207.148.119` | Email |
| Tunnel 1 PSK | `ALIFCKgV2IxkJflkMTik1ie9_WvIxP65` | 1Password (restricted link, 14 days) |
| Tunnel 2 PSK | `xUOeGF1Xnr7JopbOhZ0hEIwdiWer1ZWI` | 1Password (same link) |
| Our CIDR | `10.12.255.0/24` | Email |

Pending from them (per the return email):
1. **Atento MX internal network CIDR** (the "Domain Encryption" field left blank on the form)
2. Configure Palo Alto 5220 with the AWS tunnels (both or just one — their choice)
3. Confirm whether the actual Palo Alto Phase 2 PFS is `YES` (with DH14) or `NO` (no DH) — their doc was contradictory

### Phase 3 — Add AWS routes — ⏸ PENDING (external input)

**Trigger**: Atento MX provides remote CIDR.

Steps when unblocked:
1. New branch: `feature/atento-mx-vpn-routes`
2. Edit `integrator-atento/main.tf`:
   ```hcl
   "mx-equinix" = {
     customer_gateway_ip    = "200.188.12.42"
     customer_network_cidrs = ["<atento-mx-cidr>"]   # <- fill in
   }
   ```
3. `/aws-elevate` before any terraform
4. Plan: `cd integrator-atento && terraform plan -out=/tmp/terraform_plan_integrator-atento_{ts}.tfplan 2>&1 | tee /tmp/terraform_plan_integrator-atento_{ts}.txt`
5. Validate: **exactly 2 adds**:
   - `aws_vpn_connection_route.this["mx-equinix:<cidr>"]`
   - `aws_route.private_vpn["mx-equinix:<cidr>"]`
   - 0 destroy
6. Apply after approval: `terraform apply /tmp/terraform_plan_integrator-atento_{ts}.tfplan`
7. Update CHANGELOG, commit, PR (Angular pattern), merge, `/merge-cleanup`

### Phase 4 — End-to-end validation — ⏸ PENDING

**Pre-conditions**: Phase 3 applied + Atento MX with Palo Alto configured.

Steps:
1. Check tunnel status:
   ```
   aws ec2 describe-vpn-connections --vpn-connection-ids vpn-0c686081cfb9eebf2 --region sa-east-1 --query 'VpnConnections[0].VgwTelemetry'
   ```
   Expected: both tunnels `UP` (or at least one, if they chose only one)
2. Connectivity test from an ECS task in `integrator-atento`:
   - `nc -zv <ip-on-mx-network> 1433` (typical SQL Server port — Simplex uses)
   - Or `ping <ip>` if they allow ICMP
3. Confirm in the integrator application that connections to Simplex MX start working (logs, dashboards)

## Attention points

### VPN configuration

1. **PFS vs DH14 on Phase 2 — contradiction in their document**
   Atento MX marked `PFS: NO` but also `DH Group 14` on Phase 2. Mutually exclusive.
   AWS is permissive and accepts either side. What matters is the actual Palo Alto config: if it has DH14 on the real P2 → PFS active; if no DH → PFS inactive.
   Confirm via technical call before activating.

2. **Phase 1 lifetime in "minutes" (28800)**
   On the form they entered `28800 minutes` (= 20 days). AWS default is `28800 seconds` (= 8 hours). If their Palo Alto is literally at 28800 minutes, rekey will happen at different times on each side — works initially but may cause strange re-establishment over time. Confirm unit on call.

3. **2 AWS tunnels**
   AWS always provisions 2 tunnels by HA design (not configurable). Atento MX may opt for (a) configuring both on the Palo Alto with auto-failover, or (b) configuring only one (simpler, no redundancy). Our config supports both.

### Operational state

4. **1Password link expires in ~14 days (until ~2026-05-06)**
   If Atento MX delays configuration and the link expires, generate a new one via 1Password Desktop App:
   - Vault: `Technology Administration` (4shark account)
   - Item: `VPN S2S — Atento México (AWS ↔ Palo Alto Equinix QRO)` (ID `gvpynsgj3kpukj5agsknvcbjgm`)
   - Restrict to the same emails (pedro.cardenas@atento.com, yoneison.carreno@atento.com) or to whoever they indicate

5. **If Atento MX requests a specific PSK (not the one AWS generated)**
   Can be set via Terraform with `tunnel1_preshared_key` / `tunnel2_preshared_key` in `modules/integrator/vpn.tf` — currently not set, AWS generates random. Would require module edit + apply.

### Process (repo rules)

6. **Recurring drift on `aws_default_security_group`**
   Every `terraform plan` in `integrator-atento` (and other integrators) shows a cosmetic change in `aws_default_security_group.this` — AWS merges 3 ingress blocks on refresh, Terraform wants to split them again. Noise, doesn't affect functionality. Ignore during Phase 3 plan/apply.

7. **Git push with explicit refspec**
   Always `git push origin <branch>:refs/heads/<branch>`. The repo's default push is `upstream`; without refspec it pushes to develop.

8. **Terraform plan**
   Always `terraform plan -out=/tmp/terraform_plan_{stack}_{YYYYMMDD_HHMMSS}.tfplan 2>&1 | tee /tmp/terraform_plan_{stack}_{YYYYMMDD_HHMMSS}.txt`. Never `-target`. Never chaining.

9. **MFA required**
   Run `/aws-elevate` before any terraform command — the terraform repo's `.envrc` sets `AWS_PROFILE=4shark-mfa`.

## Post-activation troubleshooting

| Symptom | Likely cause | Where to investigate |
|---|---|---|
| Phase 1 tunnel does not establish | IKEv2/SHA256/AES256/DH14 mismatch OR wrong PSK | Palo Alto IKE logs; verify PSK per tunnel in 1Password |
| Phase 2 tunnel does not establish | PFS mismatch (AWS negotiates with DH14 vs Palo Alto without DH, or vice-versa) | Phase 2 config on Palo Alto: is a DH group set? |
| Tunnel UP but no traffic | AWS routes not added or selector mismatch | `aws ec2 describe-vpn-connections` — check `Routes`. Confirm local=`10.12.255.0/24` and remote=`<their-cidr>` |
| Tunnel drops at regular intervals (~8h) | Lifetime unit mismatch (seconds vs minutes) | Confirm actual Palo Alto unit (should be seconds) |
| Asymmetric traffic | Their routing does not include `10.12.255.0/24` | Ask them to verify the Palo Alto route table for our CIDR |

## Relevant resources

### Files in the terraform repo
- `integrator-atento/main.tf` — where to add the remote CIDR (Phase 3)
- `modules/integrator/vpn.tf` — module IKE/IPsec config (if it needs adjustment to conform to Palo Alto)

### AWS resources
- VPN Connection: `vpn-0c686081cfb9eebf2`
- VGW: `vgw-05a609b1a6ea90519` (shared with the `azure` peer)
- mx-equinix CGW: `cgw-095a980c99d64342e`
- Atento VPC (our CIDR): `10.12.255.0/24` in sa-east-1

### External artifacts
- 1Password item: `gvpynsgj3kpukj5agsknvcbjgm` — vault `Technology Administration` (4shark account)
  - Shared with: pedro.cardenas@atento.com, yoneison.carreno@atento.com
  - Expires: ~2026-05-06
- Email sent 2026-04-21: text in `/tmp/atento_mx_vpn_email_20260421_144500.txt`
- Original Atento MX VPN document: `~/Downloads/Formato VPN S2S Atento-Cliente.docx`

### Atento MX contacts
- **Pedro Cardenas** (pedro.cardenas@atento.com) — sent the original doc, network configuration owner
- **Yoneison Carreno** (yoneison.carreno@atento.com) — network, added by Pedro
- **Santiago Velasquez** (santiago.velasquez@4shark.com.br) — 4Shark ↔ Atento MX intermediary
