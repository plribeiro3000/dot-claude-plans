# PLAN - Integrator Module: Multi-VPN Support

**Status**: ✅ **COMPLETED** — merged to `develop` via PR #347 on 2026-04-21
**Branch**: `feature/integrator-multi-vpn` (deleted post-merge)
**Target stack**: `integrator-atento/`
**Module**: `modules/integrator/`

## Completion Summary

**What shipped:**
- Phase 1 applied to all 5 stacks: module refactor + state migration from index-based to key-based addressing (zero destroy)
- Phase 2 applied to all 5 stacks: key rename to final semantic schema (`main` for single-peer stacks; `azure` + `mx-equinix` for atento) + provisioning of the Atento Mexico VPN peer (CGW + VPN connection)
- CHANGELOG updated and single-commit PR merged

**What changed from this original plan during execution:**
- Key schema evolved from the initial `br`-based naming to the final scheme: `main` for single-peer stacks, `production`/`staging` for 2-env stacks (none today), `<country>-<provider>` for multi-peer stacks (`azure`, `mx-equinix`).
- Object attribute names inside the `vpns` map were set to the full AWS-consistent `customer_gateway_ip` and `customer_network_cidrs` (initial version used abbreviated `cgw_ip`/`cidrs`, corrected during review).
- Name tag on CGW and VPN connection resources was updated to include the peer key suffix (`4client-<client>-<peer>`), so multi-peer stacks don't duplicate tags.
- Discovered recurring cosmetic drift on `aws_default_security_group` across all 5 integrator stacks — not caused by this refactor.

**Still pending (external dependency, not part of this feature):**
- Phase 3 — add routes for the `mx-equinix` peer. Blocked waiting for Atento MX to provide their internal network CIDR. Tunnel endpoints and PSKs were delivered to Atento MX on 2026-04-21.

---

## Objective

Refactor `modules/integrator` to support multiple site-to-site VPN peers per client via a `vpns` map variable with `for_each`, replacing the current single-peer scalar variables (`enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`). The first consumer of the new interface is `integrator-atento`, which gains a second VPN peer for Atento Mexico alongside the existing Atento Brazil peer.

## Scope

### In Scope

- Replace scalar VPN variables with `vpns = map(object({ cgw_ip = string, cidrs = list(string) }))` in `modules/integrator`
- Rewrite `modules/integrator/vpn.tf` and `modules/integrator/routing.tf` to use `for_each` over the `vpns` map
- Add `moved` blocks in `modules/integrator` to migrate the existing Brazil VPN state addresses without destroying resources
- Update `integrator-atento/main.tf` to use the new variable shape, adding the Mexico peer
- Update all other consumers (`integrator-almaviva`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil`) to use the new variable shape
- Phase 1 Mexico deployment: CGW + VPN connection only, no routes (`cidrs = []`)
- Phase 2 Mexico deployment: add routes once Atento MX provides their network CIDR

### Out of Scope

- `integrator-aster-maquinas`: this stack manages its VPN directly (not via the module). No changes needed.
- Security group changes for Mexico (deferred to Phase 2 or a future task)
- IKE parameter per-peer customization (not needed now; current permissive defaults cover IKEv2+SHA256+AES256+DH14)
- Colombia (Simplex, VKPI) VPN peers: future consumers of the same interface, not provisioned here

## Execution Phases

### Phase 1: Module Refactor + State Migration (no infra change)

**Objective**: Change the module interface and migrate state addresses so that a `terraform plan` on every existing consumer shows **zero changes**.

**Components**:

- `modules/integrator/variables.tf`: remove `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`; add `vpns = map(object({ cgw_ip = string, cidrs = list(string) }))` with `default = {}`
- `modules/integrator/vpn.tf`: rewrite all three resources (`aws_vpn_gateway`, `aws_customer_gateway`, `aws_vpn_connection`) to `for_each = var.vpns`; rewrite `aws_vpn_connection_route` to iterate over the flattened set of `{ vpn_key, cidr }` pairs
- `modules/integrator/routing.tf`: rewrite `aws_route.private_vpn` to iterate over the same flattened set
- `modules/integrator/moved.tf` (new file): `moved` blocks mapping old index-based addresses to new key-based addresses for `integrator-atento`

  The required `moved` blocks (key `"br"` for the existing BR peer):

  ```hcl
  moved {
    from = aws_vpn_gateway.this[0]
    to   = aws_vpn_gateway.this["br"]
  }

  moved {
    from = aws_customer_gateway.this[0]
    to   = aws_customer_gateway.this["br"]
  }

  moved {
    from = aws_vpn_connection.this[0]
    to   = aws_vpn_connection.this["br"]
  }

  moved {
    from = aws_vpn_connection_route.this["10.101.30.0/24"]
    to   = aws_vpn_connection_route.this["br:10.101.30.0/24"]
  }

  moved {
    from = aws_route.private_vpn["10.101.30.0/24"]
    to   = aws_route.private_vpn["br:10.101.30.0/24"]
  }
  ```

  Note: the exact `to` address for `aws_vpn_connection_route` and `aws_route` depends on the flatten key scheme chosen during implementation. The key format `"vpn_key:cidr"` is the proposed scheme.

- `integrator-atento/main.tf`: replace scalar variables with:

  ```hcl
  vpns = {
    br = {
      cgw_ip = "48.214.37.228"
      cidrs  = ["10.101.30.0/24"]
    }
  }
  ```

- `integrator-almaviva/main.tf`, `integrator-commcenter/main.tf`, `integrator-maqnelson/main.tf`, `integrator-redebrasil/main.tf`: replace scalar variables with the `vpns` map (single entry each)

  Each consumer needs its own `moved` block scope. Since `moved` blocks inside a module apply to the module's state path, the blocks in `modules/integrator/moved.tf` cover all callers simultaneously — provided they all had a single `[0]` resource. This is correct for all five module-based stacks.

**Dependencies**: none (pure refactor)

**Validation criteria**:
- [ ] `terraform plan` on `integrator-atento` shows `No changes`
- [ ] `terraform plan` on `integrator-almaviva` shows `No changes`
- [ ] `terraform plan` on `integrator-commcenter` shows `No changes`
- [ ] `terraform plan` on `integrator-maqnelson` shows `No changes`
- [ ] `terraform plan` on `integrator-redebrasil` shows `No changes`
- [ ] No resource appears in any plan with action `destroy` or `create` (only `move` annotations are acceptable)

### Phase 2: Mexico VPN — Provision CGW + VPN Connection (no routes)

**Objective**: Add Atento Mexico as a second VPN peer in `integrator-atento`. Provide AWS tunnel IPs and PSK to Atento MX team so they can configure their Palo Alto firewall.

**Components**:

- `integrator-atento/main.tf`: add `mx` entry to the `vpns` map with `cidrs = []`:

  ```hcl
  vpns = {
    br = {
      cgw_ip = "48.214.37.228"
      cidrs  = ["10.101.30.0/24"]
    }
    mx = {
      cgw_ip = "200.188.12.42"
      cidrs  = []
    }
  }
  ```

- No new security group rules needed at this stage (no traffic will flow without routes)
- After apply, retrieve from AWS console or `terraform output` (if output added): Tunnel 1 IP, Tunnel 2 IP, PSK — share with Atento MX

**Dependencies**: Phase 1 applied and validated

**Pre-apply checklist**:
- [ ] Plan shows exactly 2 resources to add: `aws_customer_gateway.this["mx"]` and `aws_vpn_connection.this["mx"]`
- [ ] Plan shows 0 resources to destroy
- [ ] `aws_vpn_gateway.this["br"]` does NOT appear in the plan (VGW is shared; no new VGW is created for MX)

**Validation criteria**:
- [ ] `aws_customer_gateway` for MX (`200.188.12.42`) appears in AWS console as active
- [ ] `aws_vpn_connection` for MX appears with status `pending` (expected before peer is configured)
- [ ] BR VPN connection status remains `available` (no disruption)
- [ ] Tunnel endpoint IPs and PSK extracted and delivered to Atento MX team

**Open item**: PFS discrepancy in Atento MX document — they marked "PFS: NO" but also specified DH Group 14 for Phase 2. Current module defaults include DH Group 14 for Phase 2 (`tunnel1_phase2_dh_group_numbers`). No change needed now; confirm in the pre-activation technical call.

### Phase 3: Mexico VPN — Add Routes (external dependency)

**Objective**: Complete the Mexico VPN by adding the remote network CIDR once Atento MX provides it.

**Trigger**: Atento MX team provides the "Domain Encryption" CIDR (currently blank in the VPN document).

**Components**:

- `integrator-atento/main.tf`: populate `cidrs` for `mx`:

  ```hcl
  mx = {
    cgw_ip = "200.188.12.42"
    cidrs  = ["<atento-mx-cidr>"]   # replace with actual CIDR
  }
  ```

- This automatically creates `aws_vpn_connection_route.this["mx:<cidr>"]` and `aws_route.private_vpn["mx:<cidr>"]`

**Dependencies**: Phase 2 applied; CIDR received from Atento MX

**Validation criteria**:
- [ ] Plan shows exactly 2 resources to add: `aws_vpn_connection_route` and `aws_route` for MX
- [ ] VPN connection status transitions to `available` after Atento MX activates their side
- [ ] Connectivity test from ECS task to a MX host over VPN succeeds

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Variable shape | `vpns = map(object({ cgw_ip = string, cidrs = list(string) }))` | Supports N peers; keys are human-readable (`br`, `mx`, `co-simplex`); backward-incompatible but all consumers are in this repo |
| VGW cardinality | 1 VGW per client (shared across all peers) | AWS VGW is a VPC-level attachment; one is sufficient for multiple VPN connections |
| Route flatten key | `"${vpn_key}:${cidr}"` e.g. `"br:10.101.30.0/24"` | Deterministic, unique, human-readable; avoids index collisions across peers |
| `moved` block location | Inside `modules/integrator/moved.tf` | Module-level `moved` blocks apply to all callers simultaneously; no per-stack moved files needed |
| IKE parameters | Keep current permissive defaults for all peers | BR works today; MX requires IKEv2+SHA256+AES256+DH14 which is a subset of current allowed set. Per-peer customization deferred. |
| Phase split (no routes in Phase 2) | Deploy CGW+VPN first, routes later | Atento MX CIDR is unknown; routes without a valid CIDR cannot be created. Split avoids blocking the module refactor. |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **BR VPN destruction** — `moved` blocks incorrect or missing causes Terraform to destroy existing VGW/CGW/VPN | HIGH — production outage for Atento Brazil | Validate Phase 1 plan shows `No changes` on ALL consumers before applying. Never apply if any destroy appears. |
| Route flatten key mismatch — `moved` block `to` address doesn't match actual `for_each` key | HIGH — same destruction risk as above | Dry-run with `terraform plan` first; verify state addresses with `terraform state list` before applying |
| `moved` blocks applying to stacks with different key names — other consumers used `[0]` and will be mapped to `"br"` key | MEDIUM — could affect almaviva/commcenter/maqnelson/redebrasil | All single-peer stacks will use `"br"` as the canonical key in their updated `main.tf`; `moved` blocks in the module cover `[0]` → `["br"]` uniformly |
| MX CGW/VPN apply while BR plan is dirty | MEDIUM — engineer confusion if Phase 1 not fully closed | Enforce sequential phases: Phase 1 fully applied and validated before Phase 2 starts |
| PFS disagreement with Atento MX | LOW — tunnel may not establish | Confirm in technical call before Phase 3; AWS defaults are flexible enough to negotiate |

## Assumptions

- The VGW is shared across all VPN connections within a client stack (one VGW per VPC). This is validated by the current `vpn.tf` structure.
- The key `"br"` will be used for the existing Atento Brazil peer in `integrator-atento/main.tf`, and also as the canonical single-peer key in all other stacks. This determines the `moved` block targets.
- `integrator-aster-maquinas` is explicitly excluded: it manages VPN resources directly (not via the module) and is not touched.
- Terraform `moved` blocks inside a module apply to every caller's state, which is the desired behavior here since all callers have a structurally identical single-peer setup.
- The `cidrs = []` approach for the routeless Mexico peer is valid: `for_each` over an empty set simply creates no `aws_vpn_connection_route` or `aws_route` resources — no special handling needed.

## Files to Change

| File | Action | Phase |
|------|--------|-------|
| `modules/integrator/variables.tf` | Remove 3 old VPN vars, add `vpns` map | 1 |
| `modules/integrator/vpn.tf` | Rewrite all 4 resources with `for_each` | 1 |
| `modules/integrator/routing.tf` | Rewrite `aws_route` with `for_each` | 1 |
| `modules/integrator/moved.tf` | New file: state migration blocks | 1 |
| `integrator-atento/main.tf` | Replace scalar vars with `vpns` map (BR only) | 1 |
| `integrator-almaviva/main.tf` | Replace scalar vars with `vpns` map | 1 |
| `integrator-commcenter/main.tf` | Replace scalar vars with `vpns` map | 1 |
| `integrator-maqnelson/main.tf` | Replace scalar vars with `vpns` map | 1 |
| `integrator-redebrasil/main.tf` | Replace scalar vars with `vpns` map | 1 |
| `integrator-atento/main.tf` | Add `mx` entry with `cidrs = []` | 2 |
| `integrator-atento/main.tf` | Populate `cidrs` for `mx` | 3 |
| `CHANGELOG.md` | Add entry | before PR |
