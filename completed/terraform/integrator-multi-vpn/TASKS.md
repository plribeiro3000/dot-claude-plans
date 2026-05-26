# NEXT TASKS — Integrator Multi-VPN Support

> **Objective of this iteration:** Refactor `modules/integrator` to support multiple site-to-site VPN peers via `vpns` map with `for_each`, validate zero-change state migration on all 5 existing consumers (Phase 1), provision Atento Mexico peer with empty routes (Phase 2), and prepare for route activation once CIDR is provided (Phase 3).
>
> **Reference:** derived from `PLAN.md` (phases: Module Refactor + State Migration → Mexico VPN CGW+Connection → Mexico VPN Routes).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** — 3-phase approach confirmed
- **Base branch:** `develop` • **Working branch:** `feature/integrator-multi-vpn`
- **AWS profile for apply**: `4shark-mfa` (requires `/aws-elevate` before terraform commands)
- **Terraform structure**: Each stack (`integrator-atento/`, `integrator-almaviva/`, etc.) is an independent Terramate stack with its own `stack.tm.hcl`, `providers.tf`, and state file. No root module with `module.integrator_*` — execution happens per stack directory.

---

## 1) Step by Step (atomic tasks)

### Task 1 — Audit VPN configuration across all 5 stacks (pre-refactor validation)

- **Objective:** Before refactoring the module and creating `moved` blocks, audit the current VPN state in all 5 consumers to verify assumptions about CGW IPs, CIDRs, and canonical key names.
- **Actions (checklist):**
  - [ ] For each stack (`integrator-atento`, `integrator-almaviva`, `integrator-commcenter`, `integrator-maqnelson`, `integrator-redebrasil`):
    - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-<stack>/main.tf`
    - [ ] Locate the module call and extract:
      - [ ] Does it have `enable_vpn = true` or `enable_vpn = false` (or absent)?
      - [ ] Is `customer_gateway_ip` populated? If yes, extract the IP address.
      - [ ] Is `customer_network_cidrs` populated? If yes, extract the list of CIDRs.
    - [ ] Record findings in `/tmp/integrator_vpn_audit_$(date +%Y%m%d_%H%M%S).md`
  - [ ] Also check Terraform state (if needed) to confirm resources exist:
    - [ ] Run: `cd /Users/plribeiro3000/Projects/4Shark/terraform && terraform state list | grep integrator_<stack>` to see current state paths
    - [ ] If VPN resources are present, note the state address path (e.g., `aws_customer_gateway.this[0]`)
  - [ ] Document canonical key decision: All single-peer stacks will migrate to key `"br"` (Brazil). Confirm this is semantically acceptable for each stack (almaviva, commcenter, maqnelson, redebrasil — all have single peer; propose `"br"` as default unless stack-specific semantics require a different key).
  - [ ] Save audit file with structure:
    ```
    # Integrator VPN Audit — 2026-04-21

    ## integrator-atento
    - enable_vpn: true
    - cgw_ip: 48.214.37.228
    - cidrs: ["10.101.30.0/24"]
    - Canonical key: "br"
    - State resources: aws_vpn_gateway.this[0], aws_customer_gateway.this[0], aws_vpn_connection.this[0], aws_vpn_connection_route.this["10.101.30.0/24"]

    ## integrator-almaviva
    - enable_vpn: <true|false>
    - cgw_ip: <IP or "absent">
    - cidrs: [<list or "absent">]
    - Canonical key: "br"
    - State resources: <paths or "none">

    ...
    ```

- **Affected files:** `/tmp/integrator_vpn_audit_{YYYYMMDD_HHMMSS}.md`
- **Completion criteria:** Audit file created with all 5 stacks documented; CGW IPs, CIDRs, and canonical key names confirmed
- **Observations:** This audit is the insumo for Task 3 (moved blocks generation). Do not proceed to Task 3 without this audit.

---

### Task 2 — Refactor `modules/integrator/variables.tf` (Phase 1)

- **Objective:** Remove legacy single-peer VPN scalar variables and introduce the new `vpns` map structure.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/variables.tf`
  - [ ] Remove variables: `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`
  - [ ] Add new variable:
    ```hcl
    variable "vpns" {
      description = "Map of VPN peers, keyed by peer name (e.g., 'br', 'mx'). Each peer specifies customer gateway IP and remote network CIDRs."
      type        = map(object({
        cgw_ip = string
        cidrs  = list(string)
      }))
      default = {}
    }
    ```
  - [ ] Verify indentation and syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/variables.tf`
- **Completion criteria:** File parses without syntax errors; variable `vpns` is defined with correct type and default
- **Observations:** This is a backward-incompatible change; all 5 consumers will be updated in Tasks 5–9

---

### Task 3 — Rewrite `modules/integrator/vpn.tf` with `for_each` (Phase 1)

- **Objective:** Replace index-based `aws_vpn_gateway`, `aws_customer_gateway`, `aws_vpn_connection` with key-based `for_each = var.vpns`. VGW remains a singleton, guarded by `count = length(var.vpns) > 0 ? 1 : 0`.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/vpn.tf`
  - [ ] **Rewrite `aws_vpn_gateway`** to use `count` (not `for_each`):
    ```hcl
    resource "aws_vpn_gateway" "this" {
      count            = length(var.vpns) > 0 ? 1 : 0
      vpc_id           = aws_vpc.this.id
      amazon_side_asn  = 64512
      tags = {
        Name = "${local.name}-vpn-gw"
      }
    }
    ```
  - [ ] **Rewrite `aws_customer_gateway`** to use `for_each = var.vpns`:
    ```hcl
    resource "aws_customer_gateway" "this" {
      for_each       = var.vpns
      type           = "ipsec.1"
      bgp_asn        = 65000
      ip_address     = each.value.cgw_ip
      tags = {
        Name = "${local.name}-cgw-${each.key}"
      }
    }
    ```
  - [ ] **Rewrite `aws_vpn_connection`** to use `for_each = var.vpns`:
    ```hcl
    resource "aws_vpn_connection" "this" {
      for_each                   = var.vpns
      type                       = "ipsec.1"
      customer_gateway_id        = aws_customer_gateway.this[each.key].id
      vpn_gateway_id             = aws_vpn_gateway.this[0].id
      static_routes_only         = true
      tunnel1_phase1_encryption_algorithms  = ["AES256"]
      tunnel1_phase1_integrity_algorithms   = ["SHA2-256"]
      tunnel1_phase1_dh_group_numbers       = [14]
      tunnel1_phase2_encryption_algorithms  = ["AES256"]
      tunnel1_phase2_integrity_algorithms   = ["SHA2-256"]
      tunnel1_phase2_dh_group_numbers       = [14]
      tunnel2_phase1_encryption_algorithms  = ["AES256"]
      tunnel2_phase1_integrity_algorithms   = ["SHA2-256"]
      tunnel2_phase1_dh_group_numbers       = [14]
      tunnel2_phase2_encryption_algorithms  = ["AES256"]
      tunnel2_phase2_integrity_algorithms   = ["SHA2-256"]
      tunnel2_phase2_dh_group_numbers       = [14]
      tags = {
        Name = "${local.name}-vpn-conn-${each.key}"
      }
    }
    ```
  - [ ] **Add flattened routes local** (before resources):
    ```hcl
    locals {
      vpn_routes = flatten([
        for vpn_key, vpn_data in var.vpns : [
          for cidr in vpn_data.cidrs : {
            key     = "${vpn_key}:${cidr}"
            vpn_key = vpn_key
            cidr    = cidr
          }
        ]
      ])
    }
    ```
  - [ ] **Rewrite `aws_vpn_connection_route`** to use `for_each = { for r in local.vpn_routes : r.key => r }`:
    ```hcl
    resource "aws_vpn_connection_route" "this" {
      for_each               = { for r in local.vpn_routes : r.key => r }
      destination_cidr_block = each.value.cidr
      vpn_connection_id      = aws_vpn_connection.this[each.value.vpn_key].id
    }
    ```
  - [ ] Verify all references use correct key syntax (e.g., `aws_vpn_connection.this["br"]`, `aws_vpn_gateway.this[0]`)

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/vpn.tf`
- **Completion criteria:** File parses without syntax errors; resources use `for_each = var.vpns` for CGW/VPN, `count` for VGW, and flattened `for_each` for routes
- **Observations:** VGW is a singleton (one per VPC); it does not iterate. All other resources iterate over `var.vpns`.

---

### Task 4 — Rewrite `modules/integrator/routing.tf` with `for_each` (Phase 1)

- **Objective:** Update private route resource to iterate over the same flattened vpn_routes set used in Task 3.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/routing.tf`
  - [ ] Rewrite `aws_route.private_vpn` to use the flattened routes (same `local.vpn_routes` from Task 3):
    ```hcl
    resource "aws_route" "private_vpn" {
      for_each               = { for r in local.vpn_routes : r.key => r }
      route_table_id         = aws_route_table.private.id
      destination_cidr_block = each.value.cidr
      gateway_id             = aws_vpn_gateway.this[0].id
    }
    ```
  - [ ] Remove any old `count` or `depends_on` references to `aws_vpn_connection.this[0]` (if present)
  - [ ] Verify that `aws_vpn_gateway.this[0]` reference is correct (VGW is still [0] because it uses `count`)

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/routing.tf`
- **Completion criteria:** File parses without syntax errors; `aws_route.private_vpn` iterates over `local.vpn_routes`
- **Observations:** Private route table and transit gateway attachment remain unchanged; only dynamic routes change

---

### Task 5 — Create `modules/integrator/moved.tf` with state migration blocks (Phase 1)

- **Objective:** Define `moved` blocks to migrate old index-based state addresses to new key-based addresses for all 5 consumers.
- **Input:** Use the audit file from Task 1 to determine which CIDRs need `moved` blocks for each stack.
- **Actions (checklist):**
  - [ ] Create new file `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/moved.tf`
  - [ ] Add `moved` blocks for the most common case: **all 5 stacks use canonical key `"br"` as the single-peer key**. Generate blocks as follows:
    ```hcl
    moved {
      from = aws_vpn_gateway.this[0]
      to   = aws_vpn_gateway.this[0]
    }
    # Note: VGW does not change address because it uses count with index [0] before and after

    moved {
      from = aws_customer_gateway.this[0]
      to   = aws_customer_gateway.this["br"]
    }

    moved {
      from = aws_vpn_connection.this[0]
      to   = aws_vpn_connection.this["br"]
    }
    ```
  - [ ] **For each (cidr_key, cidr_value) pair discovered in the audit**, add route migration blocks. Example for atento (`br:10.101.30.0/24`):
    ```hcl
    moved {
      from = aws_vpn_connection_route.this["10.101.30.0/24"]
      to   = aws_vpn_connection_route.this["br:10.101.30.0/24"]
    }

    moved {
      from = aws_route.private_vpn["10.101.30.0/24"]
      to   = aws_route.private_vpn["br:10.101.30.0/24"]
    }
    ```
  - [ ] **If any stack has multiple CIDRs or different keys**, adjust the `to` address accordingly. The module-level `moved` blocks apply to all callers simultaneously.
  - [ ] Verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/moved.tf` (new file)
- **Completion criteria:** File exists and contains all required `moved` blocks; syntax is valid. Total blocks: 2 (CGW, VPN) + N (routes, where N = total unique CIDR count across all 5 stacks)
- **Observations:** VGW moved block is **not necessary** because the address `[0]` remains the same before and after refactoring (count-based cardinality unchanged). Route blocks must account for all discovered CIDRs.

---

### Task 6 — Update `integrator-atento/main.tf` to use `vpns` map (Phase 1, Brazil peer only)

- **Objective:** Replace scalar VPN variables with the new `vpns` map structure, defining only the Brazil peer for now.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
  - [ ] Locate the `module "integrator"` block and the VPN-related variables
  - [ ] Remove: `enable_vpn = true`, `customer_gateway_ip = "48.214.37.228"`, `customer_network_cidrs = ["10.101.30.0/24"]`
  - [ ] Add:
    ```hcl
    vpns = {
      br = {
        cgw_ip = "48.214.37.228"
        cidrs  = ["10.101.30.0/24"]
      }
    }
    ```
  - [ ] Verify indentation and syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
- **Completion criteria:** Module call updated; Brazil peer correctly defined with matching CGW IP and CIDR
- **Observations:** This stack will later have the Mexico peer added (Phase 2)

---

### Task 7 — Update `integrator-almaviva/main.tf` to use `vpns` map (Phase 1)

- **Objective:** Replace scalar VPN variables with the `vpns` map for almaviva's single peer.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva/main.tf`
  - [ ] Locate the `module "integrator"` block
  - [ ] Remove: `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`
  - [ ] Extract actual CGW IP and CIDRs from the audit file (Task 1) and add:
    ```hcl
    vpns = { br = { cgw_ip = "<cgw-ip-from-audit>", cidrs = [<cidrs-from-audit>] } }
    ```
  - [ ] Verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva/main.tf`
- **Completion criteria:** Module call updated with correct almaviva VPN values from audit

---

### Task 8 — Update `integrator-commcenter/main.tf` to use `vpns` map (Phase 1)

- **Objective:** Replace scalar VPN variables with the `vpns` map for commcenter's single peer.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-commcenter/main.tf`
  - [ ] Locate the `module "integrator"` block
  - [ ] Remove: `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`
  - [ ] Extract actual CGW IP and CIDRs from the audit file and add:
    ```hcl
    vpns = { br = { cgw_ip = "<cgw-ip-from-audit>", cidrs = [<cidrs-from-audit>] } }
    ```
  - [ ] Verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-commcenter/main.tf`
- **Completion criteria:** Module call updated with correct commcenter VPN values from audit

---

### Task 9 — Update `integrator-maqnelson/main.tf` to use `vpns` map (Phase 1)

- **Objective:** Replace scalar VPN variables with the `vpns` map for maqnelson's single peer.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-maqnelson/main.tf`
  - [ ] Locate the `module "integrator"` block
  - [ ] Remove: `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`
  - [ ] Extract actual CGW IP and CIDRs from the audit file and add:
    ```hcl
    vpns = { br = { cgw_ip = "<cgw-ip-from-audit>", cidrs = [<cidrs-from-audit>] } }
    ```
  - [ ] Verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-maqnelson/main.tf`
- **Completion criteria:** Module call updated with correct maqnelson VPN values from audit

---

### Task 10 — Update `integrator-redebrasil/main.tf` to use `vpns` map (Phase 1)

- **Objective:** Replace scalar VPN variables with the `vpns` map for redebrasil's single peer.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-redebrasil/main.tf`
  - [ ] Locate the `module "integrator"` block
  - [ ] Remove: `enable_vpn`, `customer_gateway_ip`, `customer_network_cidrs`
  - [ ] Extract actual CGW IP and CIDRs from the audit file and add:
    ```hcl
    vpns = { br = { cgw_ip = "<cgw-ip-from-audit>", cidrs = [<cidrs-from-audit>] } }
    ```
  - [ ] Verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-redebrasil/main.tf`
- **Completion criteria:** Module call updated with correct redebrasil VPN values from audit

---

### Task 11 — Validate Phase 1: Plan `integrator-atento`

- **Objective:** Run `terraform plan` on `integrator-atento` stack to confirm state migration is correct and no infrastructure changes are pending.
- **Actions (checklist):**
  - [ ] Run `/aws-elevate` to activate MFA session
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform init`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-atento_phase1_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-atento_phase1_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Save the `.tfplan` and `.txt` file names for reference (you will use the `.tfplan` file in Task 17 for apply)
  - [ ] Read the `.txt` output and verify:
    - [ ] **Only `move` operations are shown in the resource list**; no `create`, `destroy`, or `modify` actions
    - [ ] Plan output contains statement: `No changes. Your infrastructure matches the configuration.`
    - [ ] No `destroy` action appears for any VPN resource

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows `No changes` with only `move` annotations; output file saved to `/tmp/`
- **[HOLD POINT]** If any `destroy` action appears, **do not proceed**. Investigate `moved` blocks (Task 5) and correct before continuing.

---

### Task 12 — Validate Phase 1: Plan `integrator-almaviva`

- **Objective:** Confirm `integrator-almaviva` stack also shows zero infrastructure changes after state migration.
- **Actions (checklist):**
  - [ ] AWS MFA session should still be active from Task 11
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva`
  - [ ] Run: `terraform init`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-almaviva_phase1_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-almaviva_phase1_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Verify: `No changes` and no destroy actions
  - [ ] Save file names

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows `No changes`
- **[HOLD POINT]** If destroy appears, halt and investigate

---

### Task 13 — Validate Phase 1: Plan `integrator-commcenter`

- **Objective:** Confirm `integrator-commcenter` shows zero infrastructure changes.
- **Actions (checklist):**
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-commcenter`
  - [ ] Run: `terraform init`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-commcenter_phase1_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-commcenter_phase1_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Verify: `No changes` and no destroy actions
  - [ ] Save file names

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows `No changes`
- **[HOLD POINT]** If destroy appears, halt

---

### Task 14 — Validate Phase 1: Plan `integrator-maqnelson`

- **Objective:** Confirm `integrator-maqnelson` shows zero infrastructure changes.
- **Actions (checklist):**
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-maqnelson`
  - [ ] Run: `terraform init`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-maqnelson_phase1_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-maqnelson_phase1_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Verify: `No changes` and no destroy actions
  - [ ] Save file names

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows `No changes`
- **[HOLD POINT]** If destroy appears, halt

---

### Task 15 — Validate Phase 1: Plan `integrator-redebrasil`

- **Objective:** Confirm `integrator-redebrasil` shows zero infrastructure changes.
- **Actions (checklist):**
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-redebrasil`
  - [ ] Run: `terraform init`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-redebrasil_phase1_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-redebrasil_phase1_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Verify: `No changes` and no destroy actions
  - [ ] Save file names

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows `No changes`
- **[HOLD POINT]** If destroy appears, halt

---

### Task 16 — Phase 1: Apply to first low-risk stack (`integrator-almaviva`)

- **Objective:** Apply the refactored module to the lowest-risk existing consumer first, preserving state without infrastructure changes.
- **Actions (checklist):**
  - [ ] AWS MFA session should still be active
  - [ ] **Ask user for approval** before applying: "Ready to apply Phase 1 to integrator-almaviva? This refactors the module interface and migrates state with zero infrastructure changes."
  - [ ] Once approved, navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-almaviva`
  - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-almaviva_phase1_*.tfplan` (use the saved plan file from Task 12)
  - [ ] Wait for apply to complete
  - [ ] Verify output: "Apply complete! Resources: 0 added, 0 changed, 0 destroyed."

- **Affected files:** State file for `integrator-almaviva` (managed by Terraform)
- **Completion criteria:** Apply succeeds with zero changes; state is migrated from `[0]` to `["br"]` key
- **Observations:** Applying to almaviva first (rather than atento) reduces production risk

---

### Task 17 — Phase 1: Apply to remaining 4 stacks sequentially

- **Objective:** Apply Phase 1 refactoring to the remaining 4 consumers (atento, commcenter, maqnelson, redebrasil) with user approval for each.
- **Actions (checklist):**
  - [ ] For **atento** (production stack):
    - [ ] Ask user: "Ready to apply Phase 1 to integrator-atento?"
    - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
    - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-atento_phase1_*.tfplan`
    - [ ] Wait for completion; verify "0 added, 0 changed, 0 destroyed"
  - [ ] For **commcenter**:
    - [ ] Ask user: "Ready to apply Phase 1 to integrator-commcenter?"
    - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-commcenter`
    - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-commcenter_phase1_*.tfplan`
    - [ ] Wait and verify
  - [ ] For **maqnelson**:
    - [ ] Ask user: "Ready to apply Phase 1 to integrator-maqnelson?"
    - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-maqnelson`
    - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-maqnelson_phase1_*.tfplan`
    - [ ] Wait and verify
  - [ ] For **redebrasil**:
    - [ ] Ask user: "Ready to apply Phase 1 to integrator-redebrasil?"
    - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-redebrasil`
    - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-redebrasil_phase1_*.tfplan`
    - [ ] Wait and verify
  - [ ] After all 4 are applied, run a final validation across all stacks:
    - [ ] For each stack directory (atento, almaviva, commcenter, maqnelson, redebrasil), run:
      ```
      cd /Users/plribeiro3000/Projects/4Shark/terraform/integrator-<stack>
      terraform plan
      ```
    - [ ] Verify each shows `No changes. Your infrastructure matches the configuration.`

- **Affected files:** State files for all 4 stacks
- **Completion criteria:** All 5 stacks applied successfully; final validation across all shows zero pending changes
- **Observations:** This completes Phase 1. All 5 consumers now use the new `vpns` map interface, and state has been migrated without infrastructure disruption.

---

### Task 18 — Phase 2: Add Mexico peer to `integrator-atento/main.tf`

- **Objective:** Extend `integrator-atento` with the Mexico VPN peer (CGW + VPN connection, no routes yet).
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
  - [ ] Locate the `vpns` map in the `module "integrator"` block
  - [ ] Add the `mx` entry:
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
  - [ ] Save file and verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
- **Completion criteria:** Mexico peer added with correct CGW IP and empty `cidrs` list
- **Observations:** The `cidrs = []` ensures no routes are created yet

---

### Task 19 — Phase 2: Plan `integrator-atento` with Mexico peer

- **Objective:** Run `terraform plan` to confirm exactly 2 resources will be added (CGW + VPN for MX) and nothing destroyed.
- **Actions (checklist):**
  - [ ] Ensure AWS MFA session is active (run `/aws-elevate` if needed)
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-atento_phase2_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-atento_phase2_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Read the output and verify:
    - [ ] Exactly 2 resources to add: `aws_customer_gateway.this["mx"]` and `aws_vpn_connection.this["mx"]`
    - [ ] 0 resources to destroy
    - [ ] `aws_vpn_gateway.this[0]` does **NOT** appear in the plan (it already exists and is shared)
    - [ ] No route resources appear (because `cidrs = []` produces no flattened route entries)
  - [ ] Save plan file

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows exactly 2 additions; no destroy; no route additions
- **[HOLD POINT]** If plan shows anything other than expected 2 additions, do not apply. Review Task 18 before proceeding.

---

### Task 20 — Phase 2: Apply Mexico peer to `integrator-atento`

- **Objective:** Provision the Atento Mexico customer gateway and VPN connection in AWS.
- **Actions (checklist):**
  - [ ] **Ask user for approval**: "Ready to apply Phase 2 (add Mexico peer) to integrator-atento? This creates the CGW and VPN connection (no routes yet). Expected changes: 2 resources added."
  - [ ] Once approved, navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-atento_phase2_*.tfplan`
  - [ ] Wait for completion
  - [ ] Verify: "Apply complete! Resources: 2 added, 0 changed, 0 destroyed."

- **Affected files:** State for `integrator-atento`
- **Completion criteria:** Apply succeeds with 2 resources added; Mexico VPN connection appears in AWS console
- **Observations:** After this step, the Mexico VPN connection will be in `pending` state until Atento MX configures their side

---

### Task 21 — Phase 2: Extract and document tunnel IPs and PSK for Atento MX

- **Objective:** Retrieve AWS tunnel configuration (IPs and PSK) and prepare for sharing with Atento MX team.
- **Actions (checklist):**
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform state show 'module.integrator.aws_vpn_connection.this["mx"]' > /tmp/vpn_mx_state_output_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Extract Tunnel 1 IP, Tunnel 2 IP, and PSK from the output
  - [ ] Alternatively, retrieve via AWS CLI: `aws ec2 describe-vpn-connections --vpn-connection-ids <vpn-id> --region us-east-1 --query 'VpnConnections[0].{Tunnel1IP: VpnConnectionOptions.TunnelOptions[0].TunnelInsideIpv4Cidr, Tunnel2IP: VpnConnectionOptions.TunnelOptions[1].TunnelInsideIpv4Cidr}'`
  - [ ] Document in `/tmp/atento_mx_vpn_config_$(date +%Y%m%d_%H%M%S).txt` with format:
    ```
    Atento Mexico VPN Configuration
    ================================
    Customer Gateway IP: 200.188.12.42
    AWS Tunnel 1 IP: <tunnel-1-ip>
    AWS Tunnel 2 IP: <tunnel-2-ip>
    PSK: <preshared-key>
    IKE Version: IKEv2
    Encryption: AES256
    Hash: SHA256
    DH Group: 14
    ```
  - [ ] Inform user that config is ready for Atento MX team

- **Affected files:** `/tmp/atento_mx_vpn_config_*.txt`, `/tmp/vpn_mx_state_output_*.txt`
- **Completion criteria:** Tunnel IPs and PSK extracted and documented; ready to share with Atento MX
- **Observations:** This is a manual handoff point. Atento MX team will configure these values on their Palo Alto firewall

---

### Task 22 — Phase 3: Await CIDR from Atento MX (blocker task — external dependency)

- **Objective:** Wait for Atento Mexico to provide their network CIDR (Domain Encryption CIDR from the VPN document).
- **Actions (checklist):**
  - [ ] Record the date Phase 2 was completed
  - [ ] Create a reminder or ticket in the project to follow up with Atento MX for CIDR
  - [ ] Once CIDR is received, proceed to Task 23

- **Affected files:** None
- **Completion criteria:** CIDR received from Atento MX team
- **[HOLD POINT]** This task **blocks Phase 3 indefinitely** until external input is received. Do not proceed to Task 23 until user confirms CIDR is available.

---

### Task 23 — Phase 3: Populate Mexico CIDR in `integrator-atento/main.tf`

- **Objective:** Add the Mexico network CIDR to the `vpns` map once Atento MX provides it.
- **Trigger:** Task 22 complete (CIDR received from Atento MX)
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
  - [ ] Locate the `mx` entry in the `vpns` map
  - [ ] Replace `cidrs = []` with `cidrs = ["<atento-mx-cidr>"]` (user provides actual CIDR)
  - [ ] Save and verify syntax

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento/main.tf`
- **Completion criteria:** Mexico CIDR added to the `cidrs` list
- **Observations:** Once CIDR is added, `for_each` over `local.vpn_routes` will generate route resources

---

### Task 24 — Phase 3: Plan Mexico routes

- **Objective:** Validate that exactly 2 route resources will be created (VPN connection route + private route).
- **Actions (checklist):**
  - [ ] Ensure AWS MFA session is active
  - [ ] Navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform plan -out=/tmp/terraform_plan_integrator-atento_phase3_$(date +%Y%m%d_%H%M%S).tfplan 2>&1 | tee /tmp/terraform_plan_integrator-atento_phase3_$(date +%Y%m%d_%H%M%S).txt`
  - [ ] Verify:
    - [ ] Exactly 2 resources to add: `aws_vpn_connection_route.this["mx:<cidr>"]` and `aws_route.private_vpn["mx:<cidr>"]`
    - [ ] 0 resources to destroy or modify
  - [ ] Save plan file

- **Affected files:** None (read-only validation)
- **Completion criteria:** Plan shows exactly 2 route additions; no destroy actions
- **[HOLD POINT]** If plan is incorrect, do not apply. Review Task 23 and correct

---

### Task 25 — Phase 3: Apply Mexico routes

- **Objective:** Create routing entries for the Mexico VPN.
- **Actions (checklist):**
  - [ ] **Ask user for approval**: "Ready to apply Phase 3 (add Mexico routes) to integrator-atento? Expected: 2 route resources added."
  - [ ] Once approved, navigate to `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-atento`
  - [ ] Run: `terraform apply /tmp/terraform_plan_integrator-atento_phase3_*.tfplan`
  - [ ] Wait for completion
  - [ ] Verify: "Apply complete! Resources: 2 added, 0 changed, 0 destroyed."

- **Affected files:** State for `integrator-atento`
- **Completion criteria:** Apply succeeds; routes for Mexico network are created in AWS
- **Observations:** After this step, traffic to the Mexico network will be routed through the VPN

---

### Task 26 — Update `CHANGELOG.md` (before PR)

- **Objective:** Document the feature in the project changelog following 4Shark conventions.
- **Actions (checklist):**
  - [ ] Open `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`
  - [ ] Locate the `## [Unreleased]` section (or create one if missing)
  - [ ] Add entry under `### Changed`:
    ```markdown
    ### Changed
    - Integrator module: multi-VPN support per client
    ```
  - [ ] Verify format matches existing entries (concise, past-tense, no technical details)
  - [ ] Save file

- **Affected files:** `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`
- **Completion criteria:** Changelog entry added under `### Changed` section
- **Observations:** This is required before opening the PR

---

### Task 27 — Commit all changes to feature branch

- **Objective:** Create a single commit with all Phase 1–3 code changes and changelog update.
- **Actions (checklist):**
  - [ ] Ensure all modified files are saved
  - [ ] Run: `git status` to verify tracked changes
  - [ ] Run: `git add -A` (all changes)
  - [ ] Run: `git commit -m "feat(integrator): multi-VPN support per client"` (Angular format, no AI references)
  - [ ] Verify commit appears in `git log`

- **Affected files:** All modified files from Tasks 1–26
- **Completion criteria:** Commit created with clear message; branch is ahead of `develop`
- **Observations:** One commit per PR is the standard workflow

---

### Task 28 — Create PR via `@agent-pr-writer`

- **Objective:** Generate and push the PR to GitHub using the PR writer agent.
- **Actions (checklist):**
  - [ ] Invoke: `@agent-pr-writer`
  - [ ] Agent will ask for target branch (confirm `develop`)
  - [ ] Agent will extract commit message and generate PR title + body
  - [ ] PR is created on GitHub
  - [ ] Verify PR appears on GitHub with correct title and description

- **Affected files:** None (external tool)
- **Completion criteria:** PR created and visible on GitHub
- **Observations:** `@agent-pr-writer` handles the entire PR creation flow

---

## 2) Items Requiring User Confirmation

- [ ] **Audit findings (Task 1)**: Confirm the audit file is complete and CGW IPs / CIDRs / canonical keys are correct for all 5 stacks
- [ ] **Phase 1 approval**: After all 5 `terraform plan` validations show `No changes` (Tasks 11–15), proceed with sequential applies? (default: yes, almaviva first, then others with approval for each)
- [ ] **Phase 2 approval**: After plan validation shows exactly 2 additions (CGW + VPN for MX), proceed with apply? (default: yes, after user approves)
- [ ] **Mexico CIDR for Phase 3**: When Atento MX provides the CIDR, confirm the exact CIDR string (e.g., `192.168.0.0/16`) before updating Task 23
- [ ] **Changelog entry format**: Confirm the changelog entry is acceptable, or provide preferred wording

> **Expected response (example):**
> `APPROVED: Audit findings confirmed; Phase 1 proceeds with almaviva-first apply order; Phase 2 approved subject to plan validation; Phase 3 awaiting CIDR from Atento MX (expected by 2026-05-15). Changelog entry approved as written.`

---

## 3) Pending Items After This Iteration

- [ ] **Phase 3 execution**: Deferred pending CIDR from Atento MX (no timeline committed in PLAN)
- [ ] **Security group rules for Mexico traffic**: Deferred to a follow-up task once Mexico VPN routes are active and traffic patterns are understood
- [ ] **Per-peer IKE customization**: Not needed for current Mexico deployment; future enhancement if needed
- [ ] **Colombia VPN peers (Simplex, VKPI)**: Future consumers of the refactored module; not provisioned here

---

**File paths (absolute) relevant to execution:**

- Module: `/Users/plribeiro3000/Projects/4Shark/terraform/modules/integrator/` (variables.tf, vpn.tf, routing.tf, moved.tf)
- Consumers: `/Users/plribeiro3000/Projects/4Shark/terraform/integrator-{atento,almaviva,commcenter,maqnelson,redebrasil}/main.tf`
- Changelog: `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`
- External results: `/tmp/terraform_plan_*.tfplan`, `/tmp/terraform_plan_*.txt`, `/tmp/integrator_vpn_audit_*.md`, `/tmp/atento_mx_vpn_config_*.txt`, `/tmp/vpn_mx_state_output_*.txt`
