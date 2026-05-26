# PLAN - DNS Centralization: Explicit Dependency Between App Projects and `dns/`

> Reference: SPIKE.md at `~/.claude/plans/active/spike/dns-centralization/SPIKE.md`

## Objective

Make the dependency between app projects and `dns/` explicit at both the code level
(`local.public_domain`) and the execution-order level (`after = ["/dns"]` in Terramate).
Remove dead code (`alb_record_name`) from three projects that falsely suggests those
projects have DNS responsibility.

## Scope

### In Scope

- Add `after = ["/dns"]` to `stack.tm.hcl` of 6 app projects
- Add `local.public_domain` to each of the 6 app projects
- Remove `alb_record_name` variable and `record_name` module param from 3 projects
- Verify `dns/stack.tm.hcl` does not need changes for app environment ordering

### Out of Scope

- No DNS records to migrate — `dns/` is already the single source of truth
- No SSM, remote_state, or data source lookups in app projects
- No changes to `modules/public_alb/main.tf` — the dead resource stays; only the callers change
- No changes to `terramate.tm.hcl` or provider configurations

## Domain Mapping (confirmed from `dns/public_dns_app4shark_com.tf`)

| Project | Domain | Cloudflare resource |
|---|---|---|
| `app-beta-001` | `beta001.app4shark.com` | `cloudflare_dns_record.beta001_cname` |
| `app-demo-001` | `demo001.app4shark.com` | `cloudflare_dns_record.demo001_cname` |
| `app-atento-001` | `atento001.app4shark.com` | `cloudflare_dns_record.atento001_cname` |
| `app-shared-001` | `shared001.app4shark.com` | `cloudflare_dns_record.shared001_cname` |
| `setup` | `setup.app4shark.com` | `cloudflare_dns_record.setup_cname` |
| `auth-001` | `auth-001.app4shark.com` | `cloudflare_dns_record.auth_001_cname` |

Note: `auth-001` domain is `auth-001.app4shark.com`, not `auth.app4shark.com`.

## Execution Steps

### Step 1: Remove dead code from `app-beta-001`, `app-demo-001`, `setup`

For each of the three projects, two files change:

**`variables.tf`** — remove the `alb_record_name` variable block (line 153 in beta/demo, line 69 in setup).

**`main.tf`** — remove the `record_name = var.alb_record_name` line from the `module "public_alb"` call.

Files:
- `app-beta-001/variables.tf` — remove `variable "alb_record_name"` block
- `app-beta-001/main.tf` — remove `record_name = var.alb_record_name` (line 46)
- `app-demo-001/variables.tf` — remove `variable "alb_record_name"` block
- `app-demo-001/main.tf` — remove `record_name = var.alb_record_name` (line 46)
- `setup/variables.tf` — remove `variable "alb_record_name"` block
- `setup/main.tf` — remove `record_name = var.alb_record_name` (line 103)

**Success criteria:**
- [ ] No `alb_record_name` variable in any of the 3 projects
- [ ] No `record_name` argument in `module "public_alb"` calls in any of the 3 projects
- [ ] `terramate run -- terraform validate` passes for all 3 projects

### Step 2: Add `after = ["/dns"]` to the 6 app stacks

**Current state:** 5 of the 6 stacks already have `after = ["/shared-resources"]`; `auth-001` has no `after` at all.

For `app-beta-001`, `app-demo-001`, `app-atento-001`, `app-shared-001`, `setup`:
- Add `"/dns"` to the existing `after` list.

For `auth-001`:
- Add `after = ["/dns"]` (new attribute — no existing `after`).

Files:
- `app-beta-001/stack.tm.hcl`
- `app-demo-001/stack.tm.hcl`
- `app-atento-001/stack.tm.hcl`
- `app-shared-001/stack.tm.hcl`
- `setup/stack.tm.hcl`
- `auth-001/stack.tm.hcl`

**Success criteria:**
- [ ] All 6 stacks declare `"/dns"` in their `after` list
- [ ] `terramate run --order=toposort -- echo ok` completes without cycle errors

### Step 3: Add `local.public_domain` to each of the 6 app projects

Each project gets a new `locals.tf` (or the domain is appended to an existing `locals` block) with:

```hcl
locals {
  # Public domain managed by dns/ (dns/public_dns_app4shark_com.tf)
  public_domain = "<domain>"
}
```

If the project already has a `locals.tf` or a `locals` block in another file, append to it rather than create a new file.

Files (create or update):
- `app-beta-001/` — `public_domain = "beta001.app4shark.com"`
- `app-demo-001/` — `public_domain = "demo001.app4shark.com"`
- `app-atento-001/` — `public_domain = "atento001.app4shark.com"`
- `app-shared-001/` — `public_domain = "shared001.app4shark.com"`
- `setup/` — `public_domain = "setup.app4shark.com"`
- `auth-001/` — `public_domain = "auth-001.app4shark.com"`

**Success criteria:**
- [ ] All 6 projects expose `local.public_domain`
- [ ] `terramate run -- terraform validate` passes for all 6 projects

### Step 4: Verify `dns/stack.tm.hcl` (no change expected)

The spike confirmed that `dns/` does not need to declare `after` for app environments.
The dependency flows in one direction: app projects depend on `dns/`, not the reverse.
`dns/` already has an `after` list for integrators and `app-atento-br`.

**Action:** Review `dns/stack.tm.hcl` to confirm no app environment stacks should be added.

**Success criteria:**
- [ ] Confirmed `dns/stack.tm.hcl` needs no modification
- [ ] Documented the rationale in a code comment if any ambiguity exists

## Technical Decisions

| Decision | Choice | Rationale |
|---|---|---|
| How to express dependency | `after = ["/dns"]` + `local.public_domain` | Terramate handles execution order; local makes the relationship visible in code without adding providers |
| DNS lookup approach | Static string in `local.public_domain` | Cloudflare provider not available in app projects; remote state / SSM would add unnecessary coupling |
| Where to place `local.public_domain` | Dedicated `locals.tf` or existing `locals` block | Keep it findable; avoid creating new files if a locals block already exists |
| Dead code removal scope | Variables + module param only | The dead resource in `modules/public_alb/main.tf` is not removed — it stays for projects that may use it |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Terramate cycle from `after` additions | High | Verify with `terramate run --order=toposort` before merging |
| `auth-001` has no existing `after` | Low | Adding a new `after` attribute is safe — just needs correct syntax |
| `alb_record_name` referenced in `.tfvars` or env vars | Medium | Check `*.tfvars` files in all 3 projects before removing the variable |

## Assumptions

- The `dns/` stack does not need to declare `after` for any app environment — ALB creation is a one-time setup step, and subsequent applies follow the declared order (app projects wait for dns/).
- `local.public_domain` is informational at this stage. If any project needs it at runtime (CORS config, redirect URLs), it can reference it from this local.
- No `.tfvars` files override `alb_record_name` with environment-specific values (to be confirmed before Step 1).
