# DNS & Web Security Improvement

**Based on:** SPIKE-merged.md (2026-01-14, 2026-03-04)
**Status:** In progress — Phases 1, 7, 8, 9, 10, CSP, Pentest done. Phases 2–6, 11 pending (DNS/email)

---

## Overview

Harden DNS and web security across all 4Shark Cloudflare zones (4shark.com, 4shark.com.br, app4shark.com, app4shark.com.br, 4sharkpay.com) based on two audits:
- DNS/email security audit (2026-01-14): SPF, DKIM, DMARC, CAA, TLS-RPT, MTA-STS
- Cloudflare WAF/web security audit (2026-03-04): WAF rules, rate limiting, OWASP, zone settings, port blocking — triggered by pen test on shared-001

---

## Progress

### Phase 1: SPF + DKIM + AI Bots — DONE (2026-01-14)

**4shark.com:**

| Item | Before | After |
|------|--------|-------|
| SPF | `include:_spf.google.com` only | Added: Stripe, Zendesk, RD Station, SendGrid |
| DKIM Google | Missing | Added `google._domainkey.4shark.com` |
| DKIM SendGrid | Missing | Added s1, s2 |
| DKIM Stripe | Already configured | No change |

Current SPF:
```
v=spf1 include:_spf.google.com include:mail.zendesk.com include:_spf.rdstation.com.br include:sendgrid.net include:_spf.stripe.com ~all
```

**4shark.com.br:**

| Item | Before | After |
|------|--------|-------|
| SPF | Missing Stripe | Added `include:_spf.stripe.com` |

Current SPF:
```
v=spf1 include:_spf.google.com include:mail.zendesk.com include:_spf.rdstation.com.br include:sendgrid.net include:_spf.stripe.com ~all
```

**All 4 domains:** AI bots blocked.

---

### CSP & Permissions-Policy Headers — DONE (2026-03-05)

**Implemented in the Rails app project** (not Cloudflare/Terraform).

Decision: CSP headers live in Rails because Sidekiq's UI has hardcoded inline CSS/JS with its own CSP nonce — managing CSP at the Cloudflare level would conflict. Permissions-Policy was also added in Rails for consistency.

See: `~/.claude/plans/active/app/csp-headers/PLAN.md` for full details.

PR: https://github.com/4shark/app/pull/4852 (merged)

---

### Pen Test Findings Remediation Map (shared-001 — 2026-03-04)

All findings from the pen test (ZAP, Nmap, Nuclei) mapped to remediation status:

| # | Finding | Source | Severity | Status | Resolution |
|---|---------|--------|----------|--------|------------|
| 1 | 13 open TCP ports (2052-2096, 8080, 8443, 8880) | Nmap | Medium | **FIXED** | WAF port blocking rule (Phase 7) |
| 2 | CSP Header Not Set (`/sign_in`, `/sitemap.xml`) | ZAP | Medium | **FIXED** | CSP in Rails (PR #4852) |
| 3 | CSP directive fallback (cdn-cgi) | ZAP | Medium | **N/A** | Cloudflare challenge page — not app-controllable |
| 4 | Missing Anti-clickjacking (cdn-cgi) | ZAP | Medium | **N/A** | Cloudflare challenge page — not app-controllable |
| 5 | Cookie SameSite None (`cf_clearance`) | ZAP | Low | **N/A** | Cloudflare Bot Management cookie — not app-controllable |
| 6 | HTTPS Content Available via HTTP (cdn-cgi) | ZAP | Low | **N/A** | Cloudflare challenge page — not app-controllable |
| 7 | HSTS Not Set (5 instances, all cdn-cgi) | ZAP | Low | **N/A** | Cloudflare challenge pages — not app-controllable |
| 8 | X-Content-Type-Options Missing (assets, robots.txt) | ZAP | Low | **FIXED** | Cloudflare zone setting `nosniff = true` (Phase 7, PR #216) |
| 9 | Credentials Disclosure Check | Nuclei | Medium | **N/A** | False positive — Nuclei detected password field patterns on `/sign_in` login form |
| 10–15 | Informational findings (6 items) | ZAP | Info | **N/A** | Not vulnerabilities — authentication detection, cache directives, session management, etc. |

**Summary**: 3 fixed, 6 not applicable (Cloudflare-controlled), 6 informational. All pen test findings resolved.

---

## Pending Phases

### Phase 2: DKIM Stripe for 4shark.com.br

1. Access Stripe Dashboard
2. Go to Settings → Email → Custom email domain
3. Add domain `4shark.com.br`
4. Stripe will generate 6 DKIM records
5. Add records to Cloudflare DNS

Records format (example — actual values from Stripe):
```
CNAME: {selector}._domainkey.4shark.com.br → {selector}.dkim.custom-email-domain.stripe.com
```

### Phase 3: DMARC Hardening (4shark.com)

Current:
```
v=DMARC1; p=none; rua=mailto:45909c5fae804c92987868c16e7d77da@dmarc-reports.cloudflare.net
```

Target:
```
v=DMARC1; p=quarantine; fo=1; rua=mailto:45909c5fae804c92987868c16e7d77da@dmarc-reports.cloudflare.net; ruf=mailto:abuse@4shark.com; pct=100;
```

Prerequisites:
- Monitor DMARC reports for 1-2 weeks after SPF/DKIM changes
- Confirm all email services are passing SPF/DKIM checks

Risk: Medium — If any email service is not properly configured, emails may go to spam.

### Phase 4: CAA Records (All domains)

```
CAA 0 issue "comodoca.com"
CAA 0 issue "digicert.com"
CAA 0 issue "letsencrypt.org"
CAA 0 issue "pki.goog"
CAA 0 issuewild "comodoca.com"
CAA 0 issuewild "digicert.com"
CAA 0 issuewild "letsencrypt.org"
CAA 0 issuewild "pki.goog"
CAA 0 iodef "mailto:security@4shark.com.br"
```

Domains to apply:
- [ ] 4shark.com
- [ ] 4shark.com.br
- [ ] app4shark.com
- [ ] app4shark.com.br

Risk: Low — But verify current CAs before implementing.

### Phase 5: TLS-RPT (Email domains only)

```
TXT _smtp._tls.4shark.com "v=TLSRPTv1; rua=mailto:tls-reports@4shark.com"
TXT _smtp._tls.4shark.com.br "v=TLSRPTv1; rua=mailto:tls-reports@4shark.com.br"
```

Risk: None — Only for receiving reports.

### Phase 6: MTA-STS (Email domains only)

Requires DNS record (`_mta-sts.{domain}` TXT) and HTTPS endpoint (`https://mta-sts.{domain}/.well-known/mta-sts.txt`).

Policy file content:
```
version: STSv1
mode: enforce
mx: aspmx.l.google.com
mx: alt1.aspmx.l.google.com
mx: alt2.aspmx.l.google.com
mx: alt3.aspmx.l.google.com
mx: alt4.aspmx.l.google.com
max_age: 86400
```

Complexity: Medium — Requires hosting a file on a specific subdomain.
Risk: Medium — If misconfigured, may cause email delivery issues.

### Phase 7: Cloudflare Zone Security Terraform Module — DONE

Module `cloudflare_zone_security` created and applied to all 5 zones (PRs #212, #213, #215, #216, #217):
- Block Region rule (standardized with EU across all zones)
- Block IPs rule (shared IP list)
- Block Scanners rule (expanded with advanced patterns for Pro zones)
- Block User Agent rule (without empty UA block — mobile app sends requests without user agent)
- Block non-standard ports rule (pen test fix: `not cf.edge.server_port in {80 443}`)
- Rate limiting rule (`/api`, 1500 req/10s per IP+colo)
- OWASP managed ruleset (paranoia levels 2-4 disabled, score threshold 40)
- Advanced WAF rules (Log4Shell, XSS, path traversal, cookie overflow, TRACE method)
- Response Header Transform Rule (`X-Frame-Options: DENY`)
- Zone settings: HSTS with `nosniff = true` (adds `X-Content-Type-Options: nosniff`)

### Phase 8: Fix Zone Settings — DONE

`4sharkpay.com` fixed via module with `manage_zone_settings = true`:
- `always_use_https`: off → **on**
- `min_tls_version`: 1.0 → **1.2**
- HSTS enabled with preload

### Phase 9: Standardize Block Region Rule — DONE

Block Region rule is now in the shared module — all 5 zones use the same expression including "EU".

### Phase 10: Replace S3 Redirect Buckets with Cloudflare Redirect Rules — DONE

**Part 1 — app4shark.com.br redirects (PR #218, merged 2026-03-05):**
- Replaced 9 S3-pointing CNAMEs in `app4shark.com.br` zone with 2 proxied A records (root + wildcard `*.app4shark.com.br`) pointing to `192.0.2.1`
- Single Cloudflare ruleset (`expression = "true"`, 301) redirects all `app4shark.com.br` traffic → `app4shark.com` preserving path and query string
- All 9 S3 redirect buckets for `.com.br` deleted

**Part 2 — atento-br.app4shark.com redirect (PR #219, merged 2026-03-05):**
- Changed `atento-br.app4shark.com` DNS from CNAME (S3) to A record `192.0.2.1` with `proxied = true`
- Cloudflare ruleset in `dns/redirect_app4shark_com.tf` redirects `atento-br.app4shark.com` → `atentoprime-br.app4shark.com` (301, preserves path and query)
- S3 bucket `atento-br.app4shark.com` deleted

### Phase 11: CAA Records for 4sharkpay.com

Extend Phase 4 CAA records to include 4sharkpay.com:
- [ ] 4sharkpay.com

Risk: Low — Same as Phase 4.
