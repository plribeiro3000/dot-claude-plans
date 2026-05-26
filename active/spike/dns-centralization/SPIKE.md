# SPIKE — DNS Centralization: Explicit Dependency Between App Projects and `dns/`

**Conducted by:** Paulo Ribeiro
**Date:** 2026-03-03 (updated 2026-03-09)
**Status:** Research complete — ready for PLAN.md

---

## Goal

The `dns/` project is the single source of truth for all DNS. App projects should explicitly depend on `dns/`, not the other way around. Today this dependency is implicit and undeclared.

**Questions:**
1. Is DNS already centralized in `dns/`, or are there scattered definitions in other projects?
2. How to make the dependency from app projects → `dns/` explicit in both code and execution order?

---

## Method

- Audited all DNS resource definitions (`aws_route53_record`, `cloudflare_dns_record`) across the codebase
- Reviewed Terramate `stack.tm.hcl` for all app environments and `dns/`
- Checked Cloudflare provider availability in app projects
- Verified real ALB names via AWS API

---

## Evidence

### Finding 1 — `dns/` is already the single source of truth

All Cloudflare records and Route53 internal records are defined in `dns/`. No DNS record resources exist in any app project directory. The centralization is already in place.

### Finding 2 — Dead code in three app projects

`modules/public_alb/main.tf` contains a Route53 CNAME resource gated by `count`:

```hcl
resource "aws_route53_record" "alb_cname" {
  count   = var.public_zone_id == null || var.record_name == null ? 0 : 1
  ...
}
```

Three projects pass `record_name` but never pass `public_zone_id`, so `count = 0` — the record is **never created**:

| Project | `alb_record_name` value | `public_zone_id` |
|---|---|---|
| `app-beta-001` | `beta001.app4shark.com` | not passed (null) |
| `app-demo-001` | `demo001.app4shark.com` | not passed (null) |
| `setup` | `setup.app4shark.com` | not passed (null) |

`app-atento-001` and `app-shared-001` don't pass `record_name` — no dead code there.

### Finding 3 — No declared execution dependency between app projects and `dns/`

Current Terramate state:

```hcl
# app-beta-001/stack.tm.hcl (same for app-demo-001, app-atento-001, app-shared-001, setup)
stack {
  after = ["/shared-resources"]   # no mention of /dns
}

# auth-001/stack.tm.hcl
stack {
  # no after at all
}

# dns/stack.tm.hcl
stack {
  after = ["/integrator-almaviva", "/integrator-aster-maquinas", ...]
  # app environments not listed here either
}
```

Neither side declares the dependency. The order that `dns/` runs after integrators is declared, but the relationship with app environments is entirely undeclared.

### Finding 4 — Cloudflare provider not available in app projects

App projects only configure the AWS provider. Adding `data "cloudflare_dns_record"` to express the dependency would require adding the Cloudflare provider (API token, provider block) to each app project — disproportionate overhead.

### ALB names (stable across recreations)

| Environment | ALB Name | Region |
|---|---|---|
| app-beta-001 | `beta-001-pub-lb` | us-east-1 |
| app-demo-001 | `demo-001-pub-lb` | us-east-1 |
| app-atento-001 | `app-atento-001-lb` | us-east-1 |
| app-shared-001 | `app-shared-001-lb` | us-east-1 |
| setup | `setup-pub-lb` | us-east-1 |
| auth-001 | `auth-001` | sa-east-1 |

---

## Conclusions

1. **`dns/` is already centralized** — no DNS records to migrate from other projects.

2. **The problem is two-fold:**
   - Dead code (`alb_record_name` variable) in `app-beta-001`, `app-demo-001`, `setup` suggests DNS responsibility exists in these projects when it doesn't
   - No declared execution dependency — nothing in the code communicates that app projects depend on `dns/`

3. **Correct approach for expressing the dependency:**
   - **Terramate `after = ["/dns"]`** in each app stack — explicit execution dependency at the orchestration layer. `dns/` runs before app environments in all automated applies.
   - **`local.public_domain`** in each app project — a named local referencing the domain managed by `dns/`, with a comment pointing to the `dns/` project. Useful for CORS, redirect URLs, and makes the relationship visible to any engineer reading the code.

4. **Execution order at initial creation:** ALB must exist before `dns/` apply (for the Cloudflare CNAME to have a value to point to). This is acceptable — it's a one-time setup step. Subsequent applies follow the declared order.

5. **Adding `after = ["/dns"]` to app stacks does NOT create a circular dependency** — `dns/` does not declare `after` any app environment, so the graph remains acyclic.

---

## Next Steps

Generate PLAN.md with scope:

1. Remove `alb_record_name` variable and module param from `app-beta-001`, `app-demo-001`, `setup`
2. Remove `record_name` param from `module.public_alb` call in those three projects
3. Add `after = ["/dns"]` to `stack.tm.hcl` of `app-beta-001`, `app-demo-001`, `app-atento-001`, `app-shared-001`, `setup`, `auth-001`
4. Add `local.public_domain` to each app project pointing to its Cloudflare domain
5. Update `dns/stack.tm.hcl` to also declare `after` app environments (for the initial creation scenario — ensures ALBs exist before `dns/` runs in a full-stack apply)
