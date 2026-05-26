# TASKS — DNS Centralization: Explicit Dependency Between App Projects and `dns/`

> Reference: PLAN.md at `~/.claude/plans/active/dns-centralization/PLAN.md`

---

## Phase 1: Remove Dead Code (`alb_record_name`)

### Task 1.1: Remove `alb_record_name` variable from `app-beta-001/variables.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/variables.tf`

**Action:** Remove the `variable "alb_record_name"` block (line 153).

**Acceptance Criteria:**
- [ ] The variable block is removed
- [ ] `terraform validate` passes

---

### Task 1.2: Remove `record_name` parameter from `app-beta-001/main.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/main.tf`

**Action:** Remove the `record_name = var.alb_record_name` line from the `module "public_alb"` call (line 46).

**Acceptance Criteria:**
- [ ] The line is removed
- [ ] `terraform validate` passes

---

### Task 1.3: Remove `alb_record_name` variable from `app-demo-001/variables.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/variables.tf`

**Action:** Remove the `variable "alb_record_name"` block (line 153).

**Acceptance Criteria:**
- [ ] The variable block is removed
- [ ] `terraform validate` passes

---

### Task 1.4: Remove `record_name` parameter from `app-demo-001/main.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/main.tf`

**Action:** Remove the `record_name = var.alb_record_name` line from the `module "public_alb"` call (line 46).

**Acceptance Criteria:**
- [ ] The line is removed
- [ ] `terraform validate` passes

---

### Task 1.5: Remove `alb_record_name` variable from `setup/variables.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/setup/variables.tf`

**Action:** Remove the `variable "alb_record_name"` block (line 69).

**Acceptance Criteria:**
- [ ] The variable block is removed
- [ ] `terraform validate` passes

---

### Task 1.6: Remove `record_name` parameter from `setup/main.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/setup/main.tf`

**Action:** Remove the `record_name = var.alb_record_name` line from the `module "public_alb"` call (line 103).

**Acceptance Criteria:**
- [ ] The line is removed
- [ ] `terraform validate` passes

---

## Phase 2: Add Terramate Dependency (`after = ["/dns"]`)

### Task 2.1: Add `/dns` to `after` list in `app-beta-001/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/stack.tm.hcl`

**Action:** Update the `after` list to include `"/dns"` alongside existing `"/shared-resources"`.

**Current state:**
```hcl
stack {
  after = ["/shared-resources"]
}
```

**Target state:**
```hcl
stack {
  after = ["/shared-resources", "/dns"]
}
```

**Acceptance Criteria:**
- [ ] `"/dns"` is added to the `after` list

---

### Task 2.2: Add `/dns` to `after` list in `app-demo-001/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/stack.tm.hcl`

**Action:** Update the `after` list to include `"/dns"` alongside existing `"/shared-resources"`.

**Acceptance Criteria:**
- [ ] `"/dns"` is added to the `after` list

---

### Task 2.3: Add `/dns` to `after` list in `app-atento-001/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/stack.tm.hcl`

**Action:** Update the `after` list to include `"/dns"` alongside existing `"/shared-resources"`.

**Acceptance Criteria:**
- [ ] `"/dns"` is added to the `after` list

---

### Task 2.4: Add `/dns` to `after` list in `app-shared-001/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/stack.tm.hcl`

**Action:** Update the `after` list to include `"/dns"` alongside existing `"/shared-resources"`.

**Acceptance Criteria:**
- [ ] `"/dns"` is added to the `after` list

---

### Task 2.5: Add `/dns` to `after` list in `setup/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/setup/stack.tm.hcl`

**Action:** Update the `after` list to include `"/dns"` alongside existing `"/shared-resources"`.

**Acceptance Criteria:**
- [ ] `"/dns"` is added to the `after` list

---

### Task 2.6: Add `after = ["/dns"]` to `auth-001/stack.tm.hcl`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/auth-001/stack.tm.hcl`

**Action:** Add a new `after` attribute with `["/dns"]` (this project has no existing `after`).

**Current state:**
```hcl
stack {
  # no after at all
}
```

**Target state:**
```hcl
stack {
  after = ["/dns"]
}
```

**Acceptance Criteria:**
- [ ] `after = ["/dns"]` is added to the stack block

---

## Phase 3: Add `local.public_domain` Reference

### Task 3.1: Add `public_domain` local to `app-beta-001/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-beta-001/locals.tf`

**Action:** Append the following local to the existing `locals` block:

```hcl
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "beta001.app4shark.com"
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"beta001.app4shark.com"`
- [ ] `terraform validate` passes

---

### Task 3.2: Add `public_domain` local to `app-demo-001/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-demo-001/locals.tf` (or appropriate existing file)

**Action:** Create `locals.tf` or update an existing `locals` block with:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "demo001.app4shark.com"
}
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"demo001.app4shark.com"`
- [ ] `terraform validate` passes

---

### Task 3.3: Add `public_domain` local to `app-atento-001/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-atento-001/locals.tf` (or appropriate existing file)

**Action:** Create `locals.tf` or update an existing `locals` block with:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "atento001.app4shark.com"
}
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"atento001.app4shark.com"`
- [ ] `terraform validate` passes

---

### Task 3.4: Add `public_domain` local to `app-shared-001/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/locals.tf` (or appropriate existing file)

**Action:** Create `locals.tf` or update an existing `locals` block with:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "shared001.app4shark.com"
}
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"shared001.app4shark.com"`
- [ ] `terraform validate` passes

---

### Task 3.5: Add `public_domain` local to `setup/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/setup/locals.tf` (or appropriate existing file)

**Action:** Create `locals.tf` if it doesn't exist, or append to existing `locals` block:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "setup.app4shark.com"
}
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"setup.app4shark.com"`
- [ ] `terraform validate` passes

---

### Task 3.6: Add `public_domain` local to `auth-001/locals.tf`

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/auth-001/locals.tf` (or appropriate existing file)

**Action:** Create `locals.tf` if it doesn't exist with:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "auth-001.app4shark.com"
}
```

**Acceptance Criteria:**
- [ ] `local.public_domain` is defined and equals `"auth-001.app4shark.com"`
- [ ] `terraform validate` passes

---

## Phase 4: Verify `dns/` Stack (No Changes Expected)

### Task 4.1: Review `dns/stack.tm.hcl` and confirm no app environment changes needed

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/dns/stack.tm.hcl`

**Action:** Review the current `after` list in the stack block. Verify that no app environment stacks (`/app-beta-001`, `/app-demo-001`, `/app-atento-001`, `/app-shared-001`, `/setup`, `/auth-001`) are listed.

**Expected state:**
```hcl
stack {
  after = ["/integrator-almaviva", "/integrator-aster-maquinas", ...]
  # No app environments listed
}
```

**Rationale:** The dependency flows in one direction (app projects → dns/). The `dns/` stack does not need to declare a dependency on app environments because the Terramate topological sort respects the `after` declarations in the app stacks.

**Acceptance Criteria:**
- [ ] Confirmed that `dns/stack.tm.hcl` contains no app environment paths in its `after` list
- [ ] Confirmed that no changes are needed to `dns/stack.tm.hcl`

---

## Phase 5: Update Changelog

### Task 5.1: Update `CHANGELOG.md` with DNS centralization changes

**File:** `/Users/plribeiro3000/Projects/4Shark/terraform/CHANGELOG.md`

**Action:** Add a new entry to the `Unreleased` section describing the changes from a user/operator perspective.

**Example entry (adjust version/date as appropriate):**

```markdown
## [Unreleased]

### Changed
- **DNS dependency is now explicit:** All app environments (`app-beta-001`, `app-demo-001`, `app-atento-001`, `app-shared-001`, `setup`, `auth-001`) now explicitly depend on the `dns/` stack, ensuring DNS is configured before ALB routing is activated. This makes the infrastructure execution order clearer and more maintainable.

### Removed
- Removed unused `alb_record_name` variable from `app-beta-001`, `app-demo-001`, and `setup`. These projects never created DNS records (the configuration was dead code); all DNS is centrally managed by the `dns/` stack.
```

**Acceptance Criteria:**
- [ ] Changelog entry added to `Unreleased` section
- [ ] Entry explains the value/impact from a user perspective
- [ ] Entry does not reference file names, variable names, or technical implementation details

---

## Phase 6: Validation

### Task 6.1: Run Terramate topological sort to verify no cycles

**Action:** Execute `terramate run --order=toposort -- echo ok` from the terraform project root to verify the new `after` declarations do not create circular dependencies.

**Command:**
```bash
cd /Users/plribeiro3000/Projects/4Shark/terraform
terramate run --order=toposort -- echo ok
```

**Acceptance Criteria:**
- [ ] Command completes without cycle errors
- [ ] All stacks print "ok" in topological order
- [ ] `dns/` runs before all app environments

---

### Task 6.2: Run `terraform validate` for all 6 app projects

**Action:** Validate all Terraform configurations for the affected projects.

**Commands:**
```bash
cd /Users/plribeiro3000/Projects/4Shark/terraform
terramate run -- terraform validate
```

or individually:
```bash
terraform -chdir=app-beta-001 validate
terraform -chdir=app-demo-001 validate
terraform -chdir=app-atento-001 validate
terraform -chdir=app-shared-001 validate
terraform -chdir=setup validate
terraform -chdir=auth-001 validate
```

**Acceptance Criteria:**
- [ ] All 6 projects pass `terraform validate`
- [ ] No configuration errors reported

---

## Summary

- **Phase 1 (Tasks 1.1–1.6):** Remove dead `alb_record_name` code from 3 projects (6 changes total)
- **Phase 2 (Tasks 2.1–2.6):** Add `after = ["/dns"]` to 6 app stacks (6 changes total)
- **Phase 3 (Tasks 3.1–3.6):** Add `local.public_domain` to 6 app projects (6 changes total)
- **Phase 4 (Task 4.1):** Verify `dns/stack.tm.hcl` needs no changes (1 review task)
- **Phase 5 (Task 5.1):** Update `CHANGELOG.md` (1 documentation task)
- **Phase 6 (Tasks 6.1–6.2):** Validate all changes (2 verification tasks)

**Total granular tasks:** 16

Each task is explicit about the file to change, the exact change to make, and success criteria. Tasks follow a logical order: remove dead code first (Phase 1), then establish dependencies (Phase 2), then document the relationship (Phase 3), then validate (Phase 6).
