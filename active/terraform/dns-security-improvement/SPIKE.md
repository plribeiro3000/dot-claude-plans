# SPIKE — Cloudflare Security Posture Audit

**Conducted by:** Paulo Ribeiro
**Dates:** 2026-01-14 (DNS/email audit), 2026-03-04 (WAF/web security audit)
**Status:** COMPLETE — Implementation tracked in PLAN.md
**Trigger:** Initial proactive DNS audit (Jan), then pen test on shared-001 revealing 14 open TCP ports expanded scope to full Cloudflare security audit (Mar)

---

## Goal

Assess the complete security posture across all 4Shark Cloudflare zones, covering:
- Email authentication (SPF, DKIM, DMARC)
- Certificate authority authorization (CAA)
- Transport security (TLS-RPT, MTA-STS)
- WAF custom rules and managed rulesets
- Zone settings (SSL, TLS, HTTPS)
- Rate limiting
- Port exposure
- Redirect infrastructure

---

## Method

- Audited DNS records for all domains (4shark.com, 4shark.com.br, app4shark.com, app4shark.com.br, 4sharkpay.com)
- Cross-referenced each domain against email authentication best practices (SPF, DKIM, DMARC)
- Reviewed certificate issuance and firewall rules via Cloudflare dashboard and API
- Catalogued current state vs desired state for each security control
- Audited zone settings, WAF rules, rate limiting, and managed rulesets via Cloudflare API
- Verified AWS-side configuration (ALB SGs, ECS SGs, listeners) against pen test findings

---

## Evidence

### 1. Domains Summary

| Domain | Purpose | Email | Cloudflare Proxy | Status |
|--------|---------|-------|------------------|--------|
| 4shark.com | Institutional + Email | Yes | Yes | Improved (2026-01-14) |
| 4shark.com.br | Institutional + Email | Yes | Partial (Wix redirect) | Improved (2026-01-14) |
| app4shark.com | Application | No (reject all) | Yes | OK |
| app4shark.com.br | Application (redirects) | No (reject all) | Yes | OK |
| 4sharkpay.com | Payment | No | Yes | Needs fixes |

### 2. Email Security (DNS Audit — 2026-01-14)

#### 2.1 SPF Records

**4shark.com** (improved):
```
v=spf1 include:_spf.google.com include:mail.zendesk.com include:_spf.rdstation.com.br include:sendgrid.net include:_spf.stripe.com ~all
```

**4shark.com.br** (improved):
```
v=spf1 include:_spf.google.com include:mail.zendesk.com include:_spf.rdstation.com.br include:sendgrid.net include:_spf.stripe.com ~all
```

#### 2.2 DKIM Status

| Domain | Google | SendGrid (s1, s2) | Stripe | Status |
|--------|--------|-------------------|--------|--------|
| 4shark.com | Added (2026-01-14) | Added (2026-01-14) | Already configured | Complete |
| 4shark.com.br | Already configured | Already configured | **Missing** | Pending Stripe setup |

#### 2.3 DMARC Status

Both email domains have DMARC at `p=none` (monitoring only):
```
v=DMARC1; p=none; rua=mailto:45909c5fae804c92987868c16e7d77da@dmarc-reports.cloudflare.net
```

Needs hardening to `p=quarantine` after monitoring period confirms all services pass SPF/DKIM.

#### 2.4 Other Email Security

- **CAA records**: Not configured on any domain
- **TLS-RPT**: Not configured on any domain
- **MTA-STS**: Not configured on any domain

#### 2.5 Other DNS Findings

- AI bots blocked on all 4 domains (2026-01-14)
- app4shark.com CNAMEs without proxy are expected (Netlify routing requirement)
- Security.txt alerts can be ignored for institutional/app domains

### 3. Pen Test Findings (shared-001 — 2026-03-04)

Open TCP ports detected: 80, 443, 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880

**Root cause**: All ports are Cloudflare default proxy ports. AWS side is correctly configured:
- ALB SG (`sg-07f73f94eda18ae48`): Only ports 80/443 from Cloudflare IPs
- ECS SG (`sg-0cc244d4bc388cb5b`): Only VPC internal traffic (10.254.0.0/16)
- No instances have public IPs
- ALB listeners: Only 80 (forward) and 443 (HTTPS forward)

**Fix needed**: Block non-standard ports at Cloudflare level via WAF custom rule.

### 4. ALB Port 80 Analysis

All 4 ALBs (shared-001, atento-001, beta-001, demo-001) have port 80 doing **forward** (not redirect). The Cloudflare `always_use_https` setting handles the redirect before traffic reaches the ALB, so port 80 on the ALB is used for Cloudflare→ALB communication (Cloudflare terminates SSL and forwards HTTP to origin).

**Decision**: Keep port 80 on ALBs. The always_use_https at Cloudflare handles user-facing redirect.

### 5. Zone Settings Audit

| Setting                    | 4shark.com | 4shark.com.br | app4shark.com | app4shark.com.br | 4sharkpay.com |
|----------------------------|:----------:|:-------------:|:-------------:|:----------------:|:-------------:|
| ssl                        | full       | **flexible** ⚠️ | full        | full             | full          |
| always_use_https           | on         | on            | on            | on               | **off** ⚠️    |
| automatic_https_rewrites   | on         | on            | **off**       | on               | on            |
| min_tls_version            | 1.2        | 1.2           | 1.2           | 1.2              | **1.0** ⚠️    |
| tls_1_3                    | on         | on            | on            | zrt              | on            |
| 0rtt                       | off        | off           | off           | **on**           | off           |
| hotlink_protection         | off        | off           | off           | **on**           | off           |
| http3                      | on         | on            | on            | on               | on            |
| brotli                     | on         | on            | on            | on               | on            |
| browser_check              | on         | on            | on            | on               | on            |
| security_level             | medium     | medium        | medium        | medium           | medium        |
| always_online              | off        | off           | off           | off              | off           |
| websockets                 | on         | on            | on            | on               | on            |
| email_obfuscation          | on         | on            | on            | on               | on            |
| server_side_exclude        | on         | on            | on            | on               | on            |
| ip_geolocation             | on         | on            | on            | on               | on            |
| challenge_ttl              | 1800       | 1800          | 1800          | 1800             | 1800          |

**Decisions**:
- `4shark.com.br` SSL flexible: **DO NOT CHANGE** — site redirects to 4shark.com via Wix, currently functional
- `4sharkpay.com` always_use_https: **CHANGE to on**
- `4sharkpay.com` min_tls_version: **CHANGE to 1.2**

### 6. Custom WAF Rules (http_request_firewall_custom)

4 rules replicated across 4 zones. **4sharkpay.com has ZERO rules**.

#### Rule 1: Block Region

```
(ip.geoip.continent in {"AF" "AN" "AS" "EU" "OC" "T1"})
or
(ip.geoip.country in {"AF" "DZ" "AU" "BD" "BY" "BG" "CN" "DK" "EG" "FR" "GE" "DE" "GR" "HN" "HK" "IN" "ID" "IR" "IQ" "IL" "IT" "JP" "KE" "LB" "NP" "PK" "PH" "RO" "RU" "SA" "SG" "SK" "SI" "TJ" "TH" "UA" "GB" "VN" "T1" "XX" "AL"})
```

Note: UAE (AE) was excluded to allow access from Dubai client.

**Inconsistency**: `app4shark.com` does NOT block continent "EU" — others do.
**Decision**: Add "EU" to app4shark.com to match all others.

#### Rule 2: Block IPs

Same IP list across all 4 zones (~200+ IPs). Identical.

#### Rule 3: Block Scanners

Same expression across all 4 zones. Blocks common attack patterns:
```
(
  (lower(http.request.uri.path) contains ".php")
  or (starts_with(lower(http.request.uri.path), "/wp-"))
  or (ends_with(lower(http.request.uri.path), "/xmlrpc.php"))
  or (lower(http.request.uri.path) contains "/phpmyadmin")
  or (lower(http.request.uri.path) contains "/pma")
  or (lower(http.request.uri.path) contains "/cgi-bin/")
  or (lower(http.request.uri.path) contains "/.git")
  or (lower(http.request.uri.path) contains "/.env")
  or (lower(http.request.uri.path) contains "phpunit")
  or (lower(http.request.uri.path) contains "thinkphp")
  or (ends_with(lower(http.request.uri.path), "/storage/logs/laravel.log"))
  or (starts_with(lower(http.request.uri.path), "/hudson"))
  or (starts_with(lower(http.request.uri.path), "/jenkins"))
  or (starts_with(lower(http.request.uri.path), "/solr"))
  or (starts_with(lower(http.request.uri.path), "/actuator"))
  or (starts_with(lower(http.request.uri.path), "/owa"))
  or (starts_with(lower(http.request.uri.path), "/boaform"))
  or (starts_with(lower(http.request.uri.path), "/hnap1"))
  or (starts_with(lower(http.request.uri.path), "/alfresco"))
  or (lower(http.request.uri) contains "/etc/passwd")
  or (lower(http.request.uri.path) contains "/server-status")
  or (lower(http.request.uri.path) contains "/server-info")
  or (lower(http.request.uri.path) contains "/wp-config.php")
  or (lower(http.request.uri.path) contains "/.aws/credentials")
  or (lower(http.request.uri.query) contains "information_schema")
  or (lower(http.request.uri.query) contains "sleep(")
  or (lower(http.request.uri.query) contains "extractvalue(")
  or (lower(http.request.uri.query) contains "updatexml(")
  or (lower(http.request.uri.query) contains "php://input")
  or (lower(http.request.uri.query) contains "/etc/passwd")
  or (lower(http.request.uri.query) contains "cmd=")
  or (http.request.method eq "POST" and http.request.uri.path eq "/")
)
```

#### Rule 4: Block User Agent

```
(
  (http.user_agent eq "")
  or (lower(http.user_agent) contains "sqlmap")
  or (lower(http.user_agent) contains "nikto")
  or (lower(http.user_agent) contains "acunetix")
  or (lower(http.user_agent) contains "nessus")
  or (lower(http.user_agent) contains "zgrab")
  or (lower(http.user_agent) contains "masscan")
  or (lower(http.user_agent) contains "wpscan")
  or (lower(http.user_agent) contains "nmap")
)
```

**Inconsistency**: `4shark.com` and `4shark.com.br` also block **empty user agents** (`http.user_agent eq ""`). `app4shark.com` and `app4shark.com.br` do NOT.
**Decision**: DO NOT block empty user agents for now — mobile app sends requests without user agent. Will be standardized after mobile app update forces all clients to migrate.

### 7. Rate Limiting

Only `app4shark.com` has rate limiting:
```
expression: starts_with(http.request.uri.path, "/api")
action: block
characteristics: ip.src, cf.colo.id
period: 10s
requests_per_period: 1500
mitigation_timeout: 10s
```

**Decision**: Apply to all zones via module.

### 8. Managed WAF (OWASP)

Only `app4shark.com` has managed WAF deployed:
- Cloudflare OWASP Core Ruleset
- Paranoia levels 2-4 disabled
- Score threshold: 40

**Decision**: Apply to all zones via module.

### 9. Other Cloudflare Resources

- **Legacy Firewall Rules**: Same rules from section 6 viewed through legacy API endpoint. Not duplicated.
- **IP Access Rules**: None across all zones
- **Page Rules**: None across all zones
- **DDoS custom rules**: None (using Cloudflare defaults)
- **Transform Rules**: None
- **Bot Management**: Token lacks permission (403)

### 10. S3 Redirect Buckets

All `app4shark.com.br` subdomains redirect to `app4shark.com` equivalents via S3 website hosting:

| S3 Bucket                    | Redirects To                    |
|------------------------------|---------------------------------|
| app4shark.com.br             | app4shark.com                   |
| www.app4shark.com.br         | www.app4shark.com               |
| demo.app4shark.com.br        | demo.app4shark.com              |
| almaviva.app4shark.com.br    | almaviva.app4shark.com          |
| lavronorte.app4shark.com.br  | lavronorte.app4shark.com        |
| maqnelson.app4shark.com.br   | maqnelson.app4shark.com         |
| operador.app4shark.com.br    | operador.app4shark.com          |
| redebrasil.app4shark.com.br  | redebrasil.app4shark.com        |
| vendedor.app4shark.com.br    | vendedor.app4shark.com          |
| atento-br.app4shark.com      | atentoprime-br.app4shark.com    |

DNS records in `app4shark.com.br` zone all point to `{subdomain}.s3-website-us-east-1.amazonaws.com` (proxied).

**Opportunity**: Replace ALL S3 redirect buckets with Cloudflare Redirect Rules (dynamic redirects). Simpler, faster, eliminates S3 dependency and cost.

### 11. 4shark.com.br Redirect Story

- `4shark.com.br` root A record: `185.230.63.107` (Wix IP, dns-only)
- `www.4shark.com.br` CNAME: `pointing.wixdns.net` (dns-only)
- Redirect is handled by **Wix**, not S3 or Cloudflare

**Note**: This is separate from the app4shark.com.br redirects.

---

## Scope for Terraform Implementation

### Must Do (Security)

1. **Create `cloudflare_zone_security` module** with:
   - Block Region rule (standardized with EU across all zones)
   - Block IPs rule (shared IP list as variable)
   - Block Scanners rule
   - Block User Agent rule (without empty UA block for now)
   - Block non-standard ports rule (NEW — the pen test fix)
   - Rate limiting rule (from app4shark.com config)
   - OWASP managed ruleset (from app4shark.com config)

2. **Apply module to all 5 zones**

3. **Fix zone settings**:
   - `4sharkpay.com`: always_use_https = on, min_tls_version = 1.2

4. **Import existing resources** to Terraform state (avoid recreation)

### Should Do (Infrastructure Simplification)

5. **Replace S3 redirect buckets with Cloudflare Redirect Rules**:
   - Create redirect rules in `app4shark.com.br` zone
   - Pattern: `{subdomain}.app4shark.com.br/*` → `{subdomain}.app4shark.com/$1`
   - After validation, delete S3 buckets and update DNS records

---

## Reference Data

### Cloudflare API Access

Token configured in `.venvrc` (`CLOUDFLARE_API_TOKEN`).

Current permissions:
- Zone: Read
- Zone Settings: Edit
- DNS: Edit
- Firewall Services: Edit
- Zone WAF: Edit
- Cache Purge: Purge

**Missing permission**: Redirect Rules returned 403. May need "Dynamic Redirect" or "URL Rewrite" permission if implementing S3 replacement.

### Cloudflare Zone IDs

| Domain | Zone ID |
|--------|---------|
| 4shark.com | b2b861d356ace7a78485d440b8f6ab65 |
| 4shark.com.br | 436ca10c9bba089b7f1ca63db67277f6 |
| app4shark.com | 51fd2f8ea7646efc2ec849a1e947ed84 |
| app4shark.com.br | d92c63ce0f8f35735dc7f48169a885e4 |
| 4sharkpay.com | c97ffdcd1282bf95ff97054d1fc8d60f |

### Existing WAF Rule IDs (for Terraform import)

#### 4shark.com (Custom WAF Ruleset)
- Block Region: `65c33707f774441eb7bce467e151defe`
- Block IPs: `2311f8b1e5144478a0be60f8912bcbb6`
- Block Scanners: `1fb798d2e3504bca8c8cab029c806fda`
- Block User Agent: `0c3f0700e1cd49a18f3684c4862e549f`

#### 4shark.com.br (Custom WAF Ruleset)
- Block Region: `2cd6162d341c4b5e92c8d6ab3fc03306`
- Block IPs: `769e32ae2d0e4f18a77f5d8dcf7fc445`
- Block Scanners: `4ea4895d147f4a3487edb8744a34969e`
- Block User Agent: `b5b9b035948a485f9403a78c75cb9e44`

#### app4shark.com (Custom WAF Ruleset)
- Block Region: `5eddf54c40d34d3f92c63297ec239191`
- Block IPs: `5cf9f3330fa24bfe8585dfd55cebbb32`
- Block Scanners: `137259439ec547fa90a8cc40ff24c887`
- Block User Agent: `74d6e16224264cc4a03ea283d7d31f3e`
- Rate Limiting: `597358f2de7543f69f82b2a5a84c97b6`

#### app4shark.com.br (Custom WAF Ruleset)
- Block Region: `bb6af9fe6e894181b3f3de425743ffd7`
- Block IPs: (same list, different rule ID)
- Block Scanners: (same list, different rule ID)
- Block User Agent: (same list, different rule ID)

#### 4sharkpay.com
- No existing WAF rules (all new)

### AWS Resources (Reference)

| Environment | ALB Name | ALB SG | ECS SG |
|-------------|----------|--------|--------|
| shared-001 | shared-001-pub-lb | sg-07f73f94eda18ae48 | sg-0cc244d4bc388cb5b |
| atento-001 | atento-001-pub-lb | (same pattern) | (same pattern) |
| beta-001 | beta-001-pub-lb | (same pattern) | (same pattern) |
| demo-001 | demo-001-pub-lb | (same pattern) | (same pattern) |
| setup | setup-pub-lb | (same pattern) | (same pattern) |

### Working Notes

- Work must be done in a **git worktree** (VPC migration in progress on main terraform branch)
- Module should be in `terraform/modules/cloudflare_zone_security/`
- Zone-specific configs in `terraform/dns/` (alongside existing DNS config)
- Cloudflare provider v5.0 already configured in dns/providers.tf

---

## Conclusions

### Email Security (from DNS audit)
- SPF records are now comprehensive for both email domains
- DKIM is partially configured (Google + SendGrid done; Stripe pending for 4shark.com.br)
- DMARC is still at `p=none` — needs hardening to `p=quarantine` after monitoring period
- CAA, TLS-RPT, and MTA-STS are not configured on any domain
- AI bots have been blocked on all 4 domains

### Web Security (from Cloudflare audit)
- Pen test ports are Cloudflare proxy defaults — AWS side is secure, fix at Cloudflare WAF level
- WAF rules are mostly consistent across zones but have minor inconsistencies (EU block, empty UA)
- Rate limiting and OWASP WAF only on app4shark.com — should be on all zones
- 4sharkpay.com has zero WAF rules — completely unprotected
- Zone settings have 3 issues: 4sharkpay.com missing always_use_https and using TLS 1.0
- S3 redirect buckets can be replaced with Cloudflare Redirect Rules

---

## Next Steps

See PLAN.md for implementation phases and progress.
