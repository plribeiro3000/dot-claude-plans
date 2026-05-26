# PLAN - WAF Scanner Block: Refactor Cloudflare WAF Custom Rules

## Objective

Refactor and expand Cloudflare WAF custom rules in `modules/cloudflare_zone_security` to properly block vulnerability scanners, exploit path crawlers, and SQLi attacks — including the SQL Server time-based blind SQLi that was missed against `app4shark.com`.

The attack vector: POST to `/seeyon/htmlofficeservlet` with `WAITFOR DELAY` payload. Root cause: the path was not in any block list, POST body inspection is unavailable below Enterprise plan, and OWASP managed ruleset did not catch it.

## Scope

### In Scope
- Refactor Rule 3 from monolithic "Block Scanners" into focused "Block File Extensions"
- Expand Rule 4 user-agent list from 8 to ~40+ scanner signatures
- Add IP `139.144.169.16` to `dns/security_locals.tf` blocked IPs (already done in worktree)
- Add 6 new advanced WAF rules (Rules 11-16) to cover exploit paths and SQLi patterns
- Reorganize advanced rules into 4 themed exploit-path rules + 1 SQLi rule
- Keep all expressions within the 4,096-character Cloudflare limit
- Update `CHANGELOG.md`

### Out of Scope
- Upgrading Free zones to Pro plan
- Modifying OWASP managed ruleset threshold
- Rate limiting changes
- Response header changes
- POST body inspection (not available below Enterprise)

## Architecture Constraints

- **Free plan zones** (`4shark.com`, `4shark.com.br`, `4sharkpay.com`): 5 custom rules max — email/Wix/landing pages only
- **Pro plan zones** (`app4shark.com`, `app4shark.com.br`): 20 custom rules max — Rails application
- `enable_advanced_waf = false` on Free zones; `true` on Pro zones
- Expression limit: 4,096 characters per rule

## Final Rule Structure

### Base Rules — All Zones (Rules 1-5)

| # | ref | Description | Change |
|---|-----|-------------|--------|
| 1 | `block_region` | Block Region | No change |
| 2 | `block_ips` | Block IPs | IP `139.144.169.16` already added |
| 3 | `block_file_extensions` | Block File Extensions | Renamed + cleaned (removes paths/SQLi) |
| 4 | `block_user_agent` | Block User Agent | Expanded from 8 to ~40+ scanners |
| 5 | `block_ports` | Block Ports | No change |

### Advanced Rules — Pro Zones Only (Rules 6-16)

| # | ref | Description | Change |
|---|-----|-------------|--------|
| 6 | `block_methods` | Block Methods (TRACE) | No change |
| 7 | `block_log4shell` | Block Log4Shell | No change |
| 8 | `block_path_traversal_headers` | Block Path Traversal Headers | No change |
| 9 | `block_cookie_overflow` | Block Cookie Overflow | No change |
| 10 | `block_xss_query` | Block XSS Query | No change |
| 11 | `block_exploit_paths_enterprise` | Block Exploit Paths — Enterprise Software | NEW |
| 12 | `block_exploit_paths_chinese_oa` | Block Exploit Paths — Chinese Enterprise Software | NEW |
| 13 | `block_exploit_paths_frameworks` | Block Exploit Paths — Frameworks & Debug | NEW |
| 14 | `block_exploit_paths_sensitive` | Block Exploit Paths — Sensitive Files & Directories | NEW |
| 15 | `block_sqli_query` | Block SQLi Patterns | NEW |
| 16 | `block_post_root` | Block POST to Root | Moved from Rule 3 |

## Execution Phases

### Phase 1: Refactor Rule 3 — Block File Extensions

**Objective**: Strip Rule 3 down to file-extension-only matching and rename it appropriately. Remove exploit paths, sensitive paths, and SQLi patterns (those move to advanced rules).

**Changes to `modules/cloudflare_zone_security/main.tf`**:
- Change `ref` from `block_scanners` to `block_file_extensions`
- Change `description` from "Block Scanners" to "Block File Extensions"
- Keep extensions: `.php`, `.phtml`, `.phar`, `.asp`, `.jsp`, `.cgi`, `.cfm`, `.bak`, `.sql`, `.swp`, `.log`
- Add extensions: `.aspx`, `.ini`, `.conf`, `.yaml`, `.yml`
- Remove from Rule 3: all path-based conditions (`/wp-`, `/phpmyadmin`, `/.git`, `/.env`, etc.)
- Remove from Rule 3: all SQLi patterns (`information_schema`, `sleep(`, etc.)
- Remove from Rule 3: POST to `/` (moves to Rule 16)

**Dependencies**: None

**Success Criteria**:
- [ ] Rule 3 expression contains only file extension checks
- [ ] Rule 3 expression is under 4,096 characters
- [ ] No paths, directory names, or query patterns in Rule 3
- [ ] `.aspx`, `.ini`, `.conf`, `.yaml`, `.yml` are included

### Phase 2: Expand Rule 4 — Block User Agent

**Objective**: Expand the user-agent blocklist from 8 to ~40+ known scanner signatures.

**Scanner signatures to add**:
- Vulnerability scanners: `nuclei`, `openvas`, `arachni`, `w3af`, `wapiti`, `commix`, `dalfox`, `jaeles`, `whatweb`, `netsparker`, `invicti`, `appscan`, `webinspect`, `detectify`, `censysinspect`, `tsunamisecurityscanner`
- Directory bruteforcers: `gobuster`, `feroxbuster`, `dirbuster`, `ffuf`, `wfuzz`
- OSINT/recon: `shodan`, `onyphe`, `internetmeasurement`, `havij`
- Web scanners: `vega`, `httpx`, `bbot`, `l9explore`, `webbandit`, `webshag`, `wprecon`, `zmeu`, `jbrofuzz`, `fimap`, `sitelockspider`, `netlab360`
- Known bot typos/variants: `Mozlila`, `masscan-ng`, `Fuzz Faster U Fool`

**Dependencies**: None (parallel with Phase 1)

**Success Criteria**:
- [ ] Rule 4 expression includes all ~40+ scanner signatures
- [ ] Rule 4 expression respects the `block_empty_user_agent` conditional
- [ ] Rule 4 expression is under 4,096 characters
- [ ] Original 8 signatures preserved

### Phase 3: Add Advanced Rules 11-16

**Objective**: Create 6 new advanced WAF rules covering exploit paths for enterprise software, Chinese OA software, frameworks/debug endpoints, sensitive files, SQLi patterns, and POST to root.

**Rule 11 — Block Exploit Paths — Enterprise Software**:
Paths targeting Jenkins, Solr, Confluence, Jira, Tomcat Manager, WebLogic, F5 BIG-IP, Citrix, Pulse Secure, Fortinet, Exchange (OWA/ECP/EWS), VMware vCenter, Telerik.
Key paths: `/jenkins`, `/solr`, `/confluence`, `/wiki/`, `/jira/`, `/manager/html`, `/console/`, `/wls-wsat/`, `/_async/`, `/ws_utc/`, `/tmui/`, `/vpn/`, `/dana-na/`, `/ecp/`, `/EWS/`, `/autodiscover/`, `/OAB/`, `/PowerShell`, `/Telerik.Web.UI`, `/remote/login`, `/vcac/`, `/vsphere-client/`

**Rule 12 — Block Exploit Paths — Chinese Enterprise Software**:
Paths targeting Seeyon OA, Weaver/Panwei E-Cology, Yonyou NC, Landray OA, Tongda OA.
Key paths: `/seeyon/`, `/weaver/`, `/ecology/`, `/NCFindWeb`, `/service/~`, `/servlet/~`, `/sys/ui/extend/`, `/ispirit/`, `/mac/gateway`, `/general/login_code`, `/htmlofficeservlet`

**Rule 13 — Block Exploit Paths — Frameworks & Debug**:
Paths targeting Laravel Ignition, Spring Boot Actuator, GraphQL, Swagger/API docs, WordPress, Drupal, ThinkPHP, PHPUnit.
Key paths: `/_ignition/`, `/graphql`, `/graphiql`, `/swagger`, `/api-docs`, `/wp-login.php`, `/wp-json/`, `/xmlrpc.php`, `/wp-cron.php`, `/?q=node`, `/vendor/phpunit/`, `/eval-stdin.php`, `/debug/`, `/trace.axd`, `/elmah.axd`, `/cgi-bin/`

**Rule 14 — Block Exploit Paths — Sensitive Files & Directories**:
Paths targeting config files, backups, VCS directories, webshells, admin panels.
Key paths: `/.git/`, `/.env`, `/.svn/`, `/.hg/`, `/.htaccess`, `/.htpasswd`, `/.ds_store`, `/.aws/`, `/.docker/`, `/wp-config`, `/web.config`, `/database.yml`, `/Dockerfile`, `/docker-compose`, `/Gemfile`, `/backup`, `/phpmyadmin`, `/pma/`, `/adminer`, `/server-status`, `/server-info`, `/shell.php`, `/cmd.php`, `/c99.php`, `/r57.php`, `/wso.php`, `/b374k.php`, `/alfa.php`, `/storage/logs/`

**Rule 15 — Block SQLi Patterns**:
SQL injection patterns in query string, including the `WAITFOR DELAY` pattern that triggered this work.
Key patterns: `information_schema`, `sleep(`, `waitfor`, `benchmark(`, `pg_sleep(`, `extractvalue(`, `updatexml(`, `php://input`, `/etc/passwd`, `cmd=`, `union select`, `union+select`, `concat(`, `char(`, `0x`, `@@version`, `load_file(`, `into outfile`, `into dumpfile`

**Rule 16 — Block POST to Root**:
Block POST requests to `/` — scanner pattern moved from Rule 3.

**Dependencies**: Phase 1 complete (Rule 3 must be cleaned before adding advanced rules, to avoid logical overlap)

**Success Criteria**:
- [ ] 6 new rules added inside `var.enable_advanced_waf ? [...] : []` block
- [ ] Rule 11 covers all listed enterprise software paths
- [ ] Rule 12 covers `/seeyon/` and `/htmlofficeservlet` specifically
- [ ] Rule 13 covers framework and debug endpoints
- [ ] Rule 14 covers sensitive files and webshell names
- [ ] Rule 15 covers `waitfor` and all other SQLi patterns
- [ ] Rule 16 covers POST to `/`
- [ ] Each rule expression is under 4,096 characters
- [ ] Total advanced rules count does not exceed 15 (Pro plan allows 20 total; 5 base + 11 advanced = 16 < 20)

### Phase 4: Validate and Test

**Objective**: Verify correctness of all expressions and no destructive Terraform changes.

**Steps**:
- Run `terraform plan` against the `dns` workspace
- Verify rule count per zone type (Free: 5, Pro: 16)
- Verify no expression exceeds 4,096 characters (manual count or script)

**Dependencies**: Phases 1, 2, 3 complete

**Success Criteria**:
- [ ] `terraform plan` shows only in-place updates to `cloudflare_ruleset.waf_custom` for all zones
- [ ] No destroy/create cycles in the plan output
- [ ] Each rule expression character count verified under 4,096

### Phase 5: Update CHANGELOG.md

**Objective**: Add a user-focused changelog entry describing the security improvements.

**Dependencies**: Phase 4 complete

**Success Criteria**:
- [ ] `CHANGELOG.md` updated with entry under `[Unreleased]`
- [ ] Entry written from a security/business perspective, no technical implementation details

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Split Rule 3 vs. keep monolithic | Split into themed rules | Monolithic rule mixes concerns, harder to maintain, harder to debug which pattern triggered a block |
| Move SQLi to dedicated rule | Rule 15 — advanced only | SQLi in query is a Pro-zone concern; Free zones only serve Wix/email pages with no query parameters worth protecting |
| POST body inspection | Not in scope | Cloudflare limitation below Enterprise; cannot inspect body without plan upgrade |
| `block_post_root` placement | Advanced rule (16) | Moving it from base to advanced reflects that only the Rails app (Pro zones) needs this protection |
| New variables | None needed | All new rules fit within existing `enable_advanced_waf` conditional; no new module variables required |
| Character budget approach | Manual path selection | Paths chosen to maximize coverage within 4,096-char limit per rule; overly generic paths are preferred over highly specific ones |

## Character Budget

| Rule | Estimated Chars | Limit | Status |
|------|----------------|-------|--------|
| Rule 3 (File Extensions) | ~800 | 4,096 | Safe |
| Rule 4 (User Agents) | ~1,800 | 4,096 | Safe |
| Rule 11 (Enterprise Paths) | ~1,375 | 4,096 | Safe |
| Rule 12 (Chinese OA Paths) | ~800 | 4,096 | Safe |
| Rule 13 (Frameworks) | ~1,250 | 4,096 | Safe |
| Rule 14 (Sensitive Files) | ~1,500 | 4,096 | Safe |
| Rule 15 (SQLi Patterns) | ~1,100 | 4,096 | Safe |
| Rule 16 (POST Root) | ~60 | 4,096 | Safe |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| False positive on legitimate path | Medium | Rules target non-Rails paths; Rails app does not use `/seeyon/`, `/jenkins/`, etc. Review each path group before applying |
| Expression character limit exceeded | High | Budget estimates have comfortable margins; verify actual char count after writing expressions |
| Free zone rule count exceeded | High | Free zone uses only Rules 1-5; advanced rules are gated behind `enable_advanced_waf = false` on Free zones — no risk |
| Pro zone rule count exceeded | Medium | 5 base + 11 advanced = 16 rules total, well within the 20-rule Pro limit |
| Cloudflare applies rules immediately on `terraform apply` | Low | Test with `terraform plan` first; rollback is instant via git revert + re-apply |
| `/actuator` already in old Rule 3 | Low | When Rule 3 is refactored to file-extensions-only, `/actuator` moves to Rule 13 — ensure it is included there |

## Assumptions

- IP `139.144.169.16` is already present in `dns/security_locals.tf` (confirmed in worktree)
- The worktree `waf-scanner-block` is the correct implementation location
- No new Terraform module variables are needed; `enable_advanced_waf` is sufficient to gate advanced rules
- `terraform apply` is run in the `dns` workspace where all zone configurations live
- Character count estimates are conservative; actual expressions will be verified before applying

---

**Status:** COMPLETED (merged via PR #220, with hotfixes #221 and #222)
