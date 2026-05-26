# PLAN — Cloudflare Security Rules → Terraform

> Reference: SPIKE.md (spike/cloudflare-security-terraform/SPIKE.md)

## Current Situation

- **Architecture**: Cloudflare sits in front of all 5 zones, proxying traffic to AWS ALBs. AWS side is correctly locked down (ALB SG accepts only Cloudflare IPs on 80/443; ECS SG accepts only VPC-internal traffic).
- **Impacted components**: All 5 Cloudflare zones — `4shark.com`, `4shark.com.br`, `app4shark.com`, `app4shark.com.br`, `4sharkpay.com`
- **Terraform**: `terraform/dns/` manages DNS records via Cloudflare provider v5.0. No WAF/security resources are currently managed by Terraform.
- **Working constraint**: A VPC migration is in progress on the terraform main branch. All work MUST be done in a **git worktree** to avoid conflicts.

## Objective / Target State

- All Cloudflare security rules (WAF custom rules, rate limiting, managed OWASP ruleset, zone settings) managed as Terraform code.
- A reusable module `cloudflare_zone_security` applied to all 5 zones — no manual drift possible.
- Non-standard Cloudflare ports blocked at WAF level (pen test fix).
- `4sharkpay.com` zone settings corrected (always_use_https, min_tls_version).
- All 4 existing zones' rules imported into Terraform state — zero resource recreation.
- S3 redirect buckets replaced with Cloudflare Redirect Rules (separate phase, separate PR).

**Success criteria**:
- [ ] `terraform plan` shows zero diff after import and apply
- [ ] `4sharkpay.com` rejects connections on ports 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880
- [ ] `4sharkpay.com` redirects HTTP → HTTPS and rejects TLS < 1.2
- [ ] All 5 zones have identical WAF rules (Block Region, Block IPs, Block Scanners, Block User Agent, Block Ports, Rate Limiting, OWASP)
- [ ] No existing traffic is disrupted (mobile app with empty UA still works)

## Problem / New Feature

Pen test on `shared-001` revealed 14 open TCP ports. Investigation confirmed that ports 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880 are Cloudflare alternative proxy ports — legitimate from AWS's perspective, but should be blocked at the Cloudflare WAF level since the application does not use them.

Full audit also revealed:
- Security rules exist only in Cloudflare UI (no Terraform), creating drift risk
- Rules are inconsistent across zones (missing EU block on `app4shark.com`, rate limiting only on `app4shark.com`, OWASP only on `app4shark.com`)
- `4sharkpay.com` has zero WAF rules and insecure zone settings (always_use_https off, min_tls_version 1.0)
- S3 redirect buckets for `app4shark.com.br` are unnecessary overhead (opportunity)

## Challenges, Difficulties and Risks

- **Import complexity**: Existing WAF ruleset rules use a nested resource model in Cloudflare provider v5.0 (`cloudflare_ruleset`). The ruleset ID and individual rule IDs must be obtained from the API before importing. Rule IDs are documented in the spike.
- **Rule ordering**: Cloudflare applies WAF custom rules in order. The module must preserve the same order as the current UI configuration.
- **4shark.com.br SSL**: SSL mode is `flexible` (not `full`). This is intentional — site redirects via Wix and changing it would break connectivity. The module must NOT touch SSL settings for this zone.
- **Empty user agent**: Mobile app sends requests without a User-Agent header. Block User Agent rule must NOT include `http.user_agent eq ""` — current state on `4shark.com` and `4shark.com.br` blocks empty UA; this will be normalized to NOT block.
- **Worktree requirement**: All git work must happen in a worktree, not on the main terraform branch.
- **Token permissions**: Current token may lack "Dynamic Redirect" / "URL Rewrite" permission for Phase 3 (S3 replacement). Needs verification before Phase 3 starts.

## Solution Options (comparative)

- **Option 1 — Reusable module with per-zone overrides (SELECTED)**
  - **How it works:** Create `terraform/modules/cloudflare_zone_security/` with all security resources. Each zone instantiates the module with its own `zone_id`. A small number of variables allow per-zone customization (e.g., `blocked_ips`, `enable_https_redirect`). Zone-specific `.tf` files live in `terraform/dns/` alongside existing DNS config.
  - **Pros:** Single source of truth for all rules. Adding a new rule = change the module = applied everywhere. Easy diff review. Consistent with existing modules pattern in `terraform/modules/`.
  - **Cons:** Less flexibility for zone-specific rules (acceptable given zones are nearly identical).
  - **When NOT to use:** If zones needed radically different rule sets (they don't).

- **Option 2 — Inline resources per zone (no module)**
  - **How it works:** Duplicate all WAF/rate limiting/OWASP resources for each zone directly in `terraform/dns/public_dns_*.tf` files.
  - **Pros:** Maximum per-zone flexibility, no module abstraction overhead.
  - **Cons:** ~5x code duplication, high drift risk, harder to apply cross-zone changes.
  - **When NOT to use:** When rules are nearly identical across zones — as they are here.

## Proposed Steps (high level, don't execute yet)

### Phase 1 — Module + Import + Port Blocking + Zone Settings Fixes (PR #1)

1. Create git worktree for this feature branch
2. Create `terraform/modules/cloudflare_zone_security/` with:
   - `main.tf` — WAF custom ruleset resource (Block Region, Block IPs, Block Scanners, Block User Agent, Block Ports)
   - `variables.tf` — inputs: `zone_id`, `blocked_ips` (list, updateable), `enable_https_redirect` (bool, default true), `min_tls_version` (string, default "1.2"), `manage_zone_settings` (bool, default true)
   - `outputs.tf` — ruleset ID, rate limiting rule ID
3. Create zone security instantiation files in `terraform/dns/`:
   - `security_4shark_com.tf`
   - `security_4shark_com_br.tf`
   - `security_app4shark_com.tf`
   - `security_app4shark_com_br.tf`
   - `security_4sharkpay_com.tf`
4. Run `terraform import` for all existing WAF ruleset rules across 4 zones using known rule IDs from spike
5. Run `terraform plan` — verify zero diff for existing zones
6. Run `terraform apply` for `4sharkpay.com` (new rules + zone settings fix)
7. Verify pen test ports are blocked on all zones

### Phase 2 — Standardize Rules Across All Zones (PR #2)

8. Add rate limiting rule to the module (already exists on `app4shark.com`, import it; new for others)
9. Add OWASP managed ruleset to the module (already on `app4shark.com`, import it; new for others)
10. Add EU continent to Block Region rule for `app4shark.com` (currently missing)
11. Normalize Block User Agent rule: remove empty UA block from `4shark.com` and `4shark.com.br`
12. Import existing rate limiting and OWASP resources for `app4shark.com`
13. Run `terraform plan` — verify only net-new resources show as additions
14. Run `terraform apply` — apply OWASP + rate limiting to remaining 4 zones

### Phase 3 — Replace S3 Redirects with Cloudflare Redirect Rules (PR #3, optional)

15. Verify Cloudflare API token has "Dynamic Redirect" / "URL Rewrite" permission
16. Add redirect rules resource to module or separate resource in `app4shark.com.br` zone config
17. Create Cloudflare Redirect Rules for all 10 subdomains currently handled by S3
18. Validate redirects work correctly (each subdomain → correct destination)
19. Update DNS records in `public_dns_app4shark_com_br.tf` to point directly (remove S3 website endpoint CNAMEs)
20. Delete S3 redirect buckets via Terraform (or manually if not in state)

## Internal References

- Spike: `~/.claude/plans/active/spike/cloudflare-security-terraform/SPIKE.md`
- Existing DNS config: `terraform/dns/public_dns_*.tf`
- Existing modules: `terraform/modules/` (reference for module structure conventions)
- Cloudflare provider config: `terraform/dns/providers.tf`

### Zone IDs (from spike)

| Zone | ID |
|------|----|
| 4shark.com | `b2b861d356ace7a78485d440b8f6ab65` |
| 4shark.com.br | `436ca10c9bba089b7f1ca63db67277f6` |
| app4shark.com | `51fd2f8ea7646efc2ec849a1e947ed84` |
| app4shark.com.br | `d92c63ce0f8f35735dc7f48169a885e4` |
| 4sharkpay.com | `c97ffdcd1282bf95ff97054d1fc8d60f` |

### Existing WAF Rule IDs (for `terraform import` in Phase 1)

| Zone | Rule | ID |
|------|------|----|
| 4shark.com | Block Region | `65c33707f774441eb7bce467e151defe` |
| 4shark.com | Block IPs | `2311f8b1e5144478a0be60f8912bcbb6` |
| 4shark.com | Block Scanners | `1fb798d2e3504bca8c8cab029c806fda` |
| 4shark.com | Block User Agent | `0c3f0700e1cd49a18f3684c4862e549f` |
| 4shark.com.br | Block Region | `2cd6162d341c4b5e92c8d6ab3fc03306` |
| 4shark.com.br | Block IPs | `769e32ae2d0e4f18a77f5d8dcf7fc445` |
| 4shark.com.br | Block Scanners | `4ea4895d147f4a3487edb8744a34969e` |
| 4shark.com.br | Block User Agent | `b5b9b035948a485f9403a78c75cb9e44` |
| app4shark.com | Block Region | `5eddf54c40d34d3f92c63297ec239191` |
| app4shark.com | Block IPs | `5cf9f3330fa24bfe8585dfd55cebbb32` |
| app4shark.com | Block Scanners | `137259439ec547fa90a8cc40ff24c887` |
| app4shark.com | Block User Agent | `74d6e16224264cc4a03ea283d7d31f3e` |
| app4shark.com | Rate Limiting | `597358f2de7543f69f82b2a5a84c97b6` |
| app4shark.com.br | Block Region | `bb6af9fe6e894181b3f3de425743ffd7` |
| app4shark.com.br | Block IPs | (retrieve from API — not in spike) |
| app4shark.com.br | Block Scanners | (retrieve from API — not in spike) |
| app4shark.com.br | Block User Agent | (retrieve from API — not in spike) |

---

**Status:** PHASES 1-5 COMPLETED — Phase 6 pending (app project)

All 5 Cloudflare phases delivered:
- **Phase 1 (PR #212):** Module + Import + Port Blocking + Zone Settings — merged
- **Phase 2 (PR #213):** Rate Limiting + OWASP (conditional for Pro+ plans) — merged
- **Phase 3 (PR #214):** Redirect rule app4shark.com.br → app4shark.com — merged
- **Phase 4 (PR #215):** Advanced WAF Rules for scanner attack mitigation (Pro zones only) — merged
- **Phase 5 (PR #216):** Security response headers (HSTS, X-Content-Type-Options, X-Frame-Options) — merged

### Phase 4 — Advanced WAF Rules (PR #215)

Triggered by production backtraces showing bot scanners bypassing existing WAF rules through uninspected vectors (HTTP headers, non-standard methods, oversized cookies, XSS in query strings).

5 new rules added to the module, conditional on `enable_advanced_waf` (Pro plan required — Free plan limited to 5 custom rules):

| Rule | Ref | Expression | Mitigates |
|------|-----|-----------|-----------|
| 6 | `block_methods` | `http.request.method in {"DELETE" "PUT" "PATCH" "OPTIONS" "TRACE"}` | Unauthorized HTTP methods |
| 7 | `block_log4shell` | `any(http.request.headers.values[*] contains "${jndi:")` + URI path/query | Log4Shell / JNDI injection |
| 8 | `block_path_traversal_headers` | `any(http.request.headers.values[*] contains "../")` | Path traversal via headers |
| 9 | `block_cookie_overflow` | `len(http.request.headers["cookie"][0]) > 8192` | Cookie stuffing DoS |
| 10 | `block_xss_query` | XSS patterns in query string (`<script`, `javascript:`, `onerror=`, etc.) | Reflected XSS |

Applied to Pro zones only: `app4shark.com`, `app4shark.com.br` (via `enable_advanced_waf = true`).

### Phase 5 — Security Response Headers (PR #216)

Triggered by HostedScan pentest reports (ZAP, Nmap, Nuclei) showing missing security headers on `shared001.app4shark.com`.

Changes applied to all 5 zones:

| Setting | Implementation | Value |
|---------|---------------|-------|
| HSTS | Zone Setting `security_header` | `max-age=31536000; includeSubDomains; preload` |
| X-Content-Type-Options | Zone Setting `security_header` (nosniff) | `nosniff` |
| X-Frame-Options | Transform Rule (`http_response_headers_transform`) | `DENY` |
| Always Use HTTPS | Zone Setting `always_use_https` | `on` |
| Min TLS Version | Zone Setting `min_tls_version` | `1.2` |

Required adding `Zone > Transform Rules > Edit` permission to the Cloudflare API token.
Enabled `manage_zone_settings = true` on 4 zones that didn't have it (only `4sharkpay.com` had it before).

### Phase 6 — Content Security Policy (CSP) — PENDING

**Status:** Needs investigation — implementation will be in the Rails application (`app` project), not Cloudflare.

**Context:** The pentest flagged 2 Medium findings for missing CSP headers. CSP was initially considered for Cloudflare Transform Rules, but deferred to the application level because:

1. Sidekiq Web (`/sidekiq`) requires `script-src 'unsafe-inline'` and `style-src 'unsafe-inline'` — a blanket CSP via Cloudflare would either break Sidekiq or be too permissive
2. The Rails app can differentiate paths and apply a strict CSP for API responses and a permissive one for Sidekiq Web
3. The Angular webclient (`app-webclient`) already has CSP configured via `netlify.toml` — it doesn't go through Cloudflare proxy
4. The existing Rails CSP initializer (`config/initializers/content_security_policy.rb`) is fully commented out

**Investigation needed:**
- How to apply path-specific CSP in Rails (middleware vs controller-level override)
- What CSP directives Sidekiq Web actually requires (inline scripts, inline styles, same-origin resources)
- Whether PgHero and RailsPgExtras Web (also mounted at `/pg_hero` and `/pg_extras`) have similar CSP requirements
- Whether to use `Content-Security-Policy` (enforce) or `Content-Security-Policy-Report-Only` (monitor) initially

### Pentest Findings Resolution Summary

| Finding | Severity | Status | Resolution |
|---------|----------|--------|------------|
| Open ports 2052-8880 | Medium (x11) | Resolved | Phase 1 — Rule 5 `block_ports` |
| CSP Header Not Set | Medium | Pending | Phase 6 — Rails application |
| CSP Directive Failures | Medium | Pending | Phase 6 — Rails application |
| X-Frame-Options Missing | Medium | Resolved | Phase 5 — Transform Rule |
| Credentials Disclosure (x2 Nuclei) | Medium | False positive | Session cookie `_four_shark_app` — standard Rails behavior |
| HSTS Not Set | Low | Resolved | Phase 5 — Zone Setting |
| X-Content-Type-Options Missing | Low | Resolved | Phase 5 — Zone Setting |
| HTTPS Content via HTTP | Low | Resolved | Phase 5 — `always_use_https` |
| Cookie SameSite None | Low | False positive | `cf_clearance` cookie from Cloudflare challenge — not controllable |

Pending follow-up (separate feature):
- Remove S3 redirect buckets and CNAME records after confirming redirects work via Cloudflare (wait a few days)
