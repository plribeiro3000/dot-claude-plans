# PLAN - Integrator Module Cleanup

## Objective

Remove all EC2-era legacy code from the shared `modules/integrator` module now that all 5 active
integrator stacks (almaviva, maqnelson, redebrasil, atento, commcenter) have completed the
migration to ECS Fargate. The module must reflect the current ECS reality — no EC2 app servers,
no module-managed MongoDB, no public subnet workarounds.

Every Terraform plan produced during this work must show **0 add, 0 change, 0 destroy** for all
5 migrated stacks. This is a code-only cleanup: no infrastructure changes.

## Scope

### In Scope
- Delete `modules/integrator/app.tf` (EC2 app server resources)
- Delete `modules/integrator/mongodb.tf` (module-managed MongoDB EC2 resources)
- Delete `modules/integrator/peering.tf` (empty file)
- Remove 17 legacy variables from `modules/integrator/variables.tf`
- Remove `subnet_map` local and `"pub-b"` entry from `modules/integrator/main.tf`
- Remove `vpn_client_cidrs` dynamic ingress block from `modules/integrator/security.tf`
- Remove 6 legacy outputs from `modules/integrator/outputs.tf`
- Update all 5 migrated stack `main.tf` files to remove legacy arguments and fix `ec2_instance_ids`
- Isolate `integrator-aster-maquinas` from the shared module before any module changes

### Out of Scope
- `integrator-aster-maquinas` decommission (contract cancelled, to be handled separately)
- `modules/integrator_iam` interface changes (variable stays; only callers are updated)
- Any infrastructure changes — no resources are created, changed, or destroyed
- CloudWatch log groups in each stack (MongoDB Lambda still runs on EC2; groups stay)
- `modules/networking_data` variables (`has_public_subnets`, `has_nat_gateway`) — already clean

## Prerequisite: Isolate aster-maquinas

**Problem**: `integrator-aster-maquinas` still uses the full legacy interface:
- `subnet_pub_b_id` with a real public subnet (`module.networking_data.public_ids[0]`)
- `app_servers` with two EC2 instances
- `enable_mongo = true` (default) — module-managed MongoDB
- `vpn_client_cidrs = ["10.149.176.0/27"]`
- `ubuntu_ami`

These are exactly the variables and files being removed from the shared module. The module cannot
be cleaned while aster-maquinas still references them.

**Decision**: Inline all module resources directly into the `integrator-aster-maquinas` stack
before touching the shared module. This is a pure code refactor (no plan diff for aster-maquinas
either) and makes the decommission self-contained when the time comes.

The approach is to copy the module's current state into the stack (security.tf, app.tf,
mongodb.tf, vpn.tf, routing.tf, dns.tf, elasticache.tf, main.tf locals) so aster-maquinas
becomes independent of the shared module entirely.

## Execution Phases

### Phase 0: Inline modules/integrator into integrator-aster-maquinas

**Objective**: Make `integrator-aster-maquinas` independent of the shared module so the shared
module can be cleaned without breaking it.

**Components**:
- Copy the full current module output (security group, app servers, mongodb EC2s, VPN, routing,
  DNS, ElastiCache) as standalone resources inside `integrator-aster-maquinas/`
- Remove the `module "this"` block from `integrator-aster-maquinas/main.tf`
- Keep `module "iam"` using `values(module.this.app_server_ids)` — wait, `module.this` will be
  gone. Fix: pass the app server instance IDs directly from the inlined `aws_instance` resources.
- Terraform plan for `integrator-aster-maquinas` must show **0 add, 0 change, 0 destroy**
  (state addresses change from `module.this.*` to stack-level `*`, so a `terraform state mv`
  pass is required for each resource)

**Dependencies**: None — aster-maquinas is independent of the 5 migrated stacks

**Success Criteria**:
- [ ] `integrator-aster-maquinas` stack has no `source = "../modules/integrator"` reference
- [ ] All resources previously managed by `module.this` are now stack-level resources
- [ ] `terraform plan` for `integrator-aster-maquinas` shows 0 add, 0 change, 0 destroy after state moves
- [ ] `modules/integrator` is no longer referenced by `integrator-aster-maquinas/main.tf`

### Phase 1: Clean modules/integrator

**Objective**: Remove all EC2-era code from the shared module.

**Files to delete**:
- `modules/integrator/app.tf`
- `modules/integrator/mongodb.tf`
- `modules/integrator/peering.tf`

**Variables to remove from `modules/integrator/variables.tf`** (17 total):
- `subnet_pub_b_id`
- `enable_mongo`
- `enable_termination_protection`
- `key_name`
- `ubuntu_ami`
- `vpn_client_cidrs`
- `app_servers`
- `mongo_arbiter_type`, `mongo_arbiter_volume_size`, `mongo_arbiter_ami`
- `mongo_primary_type`, `mongo_primary_volume_size`, `mongo_primary_ami`
- `mongo_secondary_type`, `mongo_secondary_volume_size`, `mongo_secondary_ami`

**Changes to `modules/integrator/main.tf`**:
- Remove `subnet_map` local entirely (was only used by `app.tf`)

**Changes to `modules/integrator/security.tf`**:
- Remove the `dynamic "ingress"` block gated by `length(var.vpn_client_cidrs) > 0`

**Outputs to remove from `modules/integrator/outputs.tf`** (6 total):
- `subnet_pub_b_id`
- `mongo_arbiter_private_ip`
- `mongo_primary_private_ip`
- `mongo_secondary_private_ip`
- `app_server_private_ips`
- `app_server_ids`

**Dependencies**: Phase 0 complete (aster-maquinas no longer uses the shared module)

**Success Criteria**:
- [ ] `modules/integrator/app.tf` deleted
- [ ] `modules/integrator/mongodb.tf` deleted
- [ ] `modules/integrator/peering.tf` deleted
- [ ] `variables.tf` has exactly 15 variables (verify count)
- [ ] `outputs.tf` has exactly 6 outputs (verify count)
- [ ] `main.tf` has no `subnet_map` local
- [ ] `security.tf` has no `vpn_client_cidrs` dynamic block
- [ ] `terraform validate` passes on the module in isolation

### Phase 2: Update all 5 migrated stack main.tf files

**Objective**: Remove legacy arguments passed to `module "this"` and fix `ec2_instance_ids` in
`module "iam"` for each of the 5 migrated stacks.

**Stacks affected**: almaviva, maqnelson, redebrasil, atento, commcenter

**Changes per stack** (where applicable):

| Stack | Remove from module "this" | Fix module "iam" ec2_instance_ids |
|-------|--------------------------|-----------------------------------|
| almaviva | `subnet_pub_b_id`, `ubuntu_ami`, `enable_mongo`, `app_servers` | `values(module.this.app_server_ids)` → `[]` |
| maqnelson | `subnet_pub_b_id`, `ubuntu_ami`, `enable_mongo`, `app_servers` | `values(module.this.app_server_ids)` → `[]` |
| redebrasil | `subnet_pub_b_id`, `ubuntu_ami`, `enable_mongo`, `app_servers` | already `[]` — no change |
| atento | `subnet_pub_b_id`, `ubuntu_ami`, `enable_mongo`, `app_servers` | `values(module.this.app_server_ids)` → `[]` |
| commcenter | `subnet_pub_b_id`, `ubuntu_ami`, `enable_mongo`, `app_servers` | already `[]` — no change |

**Note on `ec2_instance_ids`**: The IAM module uses this to grant Lambda start/stop permissions
on specific EC2 instances. The migrated stacks no longer have EC2 app servers. MongoDB EC2
instances are managed per-stack in `mongodb.tf` (not via the module). Passing `[]` is correct —
it skips the `ManageInstances` IAM statement (already handled by the `length > 0` guard in
`modules/integrator_iam/ec2.tf`). redebrasil and commcenter already pass `[]`.

**Dependencies**: Phase 1 complete

**Success Criteria**:
- [ ] No `subnet_pub_b_id` argument in any of the 5 migrated stacks
- [ ] No `ubuntu_ami` argument in any of the 5 migrated stacks
- [ ] No `enable_mongo` argument in any of the 5 migrated stacks
- [ ] No `app_servers` argument in any of the 5 migrated stacks
- [ ] No `module.this.app_server_ids` reference in any of the 5 migrated stacks
- [ ] `terraform validate` passes on all 5 stacks

### Phase 3: Terraform plan verification

**Objective**: Confirm zero infrastructure changes across all 5 migrated stacks.

**Process**: Run `terraform plan` for each of the 5 stacks individually (not chained). Each plan
is saved to `/tmp/` per the External Results Policy. Review each plan summary before proceeding
to the next.

**Note**: MFA elevation required before any Terraform command (`/aws-elevate`).

**Dependencies**: Phase 2 complete, MFA session active

**Success Criteria**:
- [ ] `integrator-almaviva`: plan shows 0 add, 0 change, 0 destroy
- [ ] `integrator-maqnelson`: plan shows 0 add, 0 change, 0 destroy
- [ ] `integrator-redebrasil`: plan shows 0 add, 0 change, 0 destroy
- [ ] `integrator-atento`: plan shows 0 add, 0 change, 0 destroy
- [ ] `integrator-commcenter`: plan shows 0 add, 0 change, 0 destroy

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| How to handle aster-maquinas | Inline module resources into the stack | Cleanest isolation: decommission becomes self-contained, shared module gets fully cleaned |
| State moves for aster-maquinas | `terraform state mv module.this.<resource> <resource>` per resource | Required to avoid destroy/recreate — addresses change when moving from module to stack level |
| `ec2_instance_ids` for migrated stacks | Pass `[]` | No EC2 app servers remain; MongoDB EC2 IDs are not in scope here; `[]` correctly suppresses the `ManageInstances` IAM statement |
| `modules/integrator_iam` interface | No change | Variable stays; callers updated; IAM module already handles empty list gracefully |
| Plan verification order | One stack at a time, plan saved to `/tmp/` | Follows Command Safety Policy — no chaining, output preserved |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| State address mismatch for aster-maquinas | High — recreates infrastructure | Careful `terraform state list` before and after inlining; verify with plan before applying state moves |
| Missing resource during aster-maquinas inline | High — resource left unmanaged | Cross-reference `terraform state list module.this` against all files being inlined |
| Migrated stack plans showing unexpected changes | Medium — indicates missed argument or output reference | Fix in Phase 2 before proceeding to next stack |
| aster-maquinas MongoDB still using module outputs | Medium — output removed, stack breaks | Audit all `module.this.*` references in aster-maquinas before Phase 0 |

## Assumptions

- All 5 migrated stacks have completed the ECS migration and have no EC2 app servers in state
- MongoDB EC2 instances for migrated stacks are managed by per-stack `mongodb.tf` files, not by `module.this`
- `integrator-aster-maquinas` is not to be decommissioned in this PR — Phase 0 only isolates it
- The Lambda that starts MongoDB EC2 instances is managed by the `lambda` repo; CloudWatch log groups in each stack stay as-is
- redebrasil and commcenter passing `[]` to `ec2_instance_ids` is intentional and correct
