# NEXT TASKS — WAF Scanner Block: Refactor & Expand Cloudflare Custom Rules

> **Objective of this iteration (1–2 lines):** Refactor monolithic Rule 3, expand Rule 4 scanner signatures, add 6 new advanced WAF rules (Rules 11–16) to block exploit paths and SQLi attacks, ensure all expressions stay within the 4,096-character limit per rule.
> **Reference:** `PLAN.md` — Phases 1–5, "Execution Phases" section.

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved** (WAF Scanner Block implementation plan)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/vpc-app-beta-001`
- [ ] Current worktree: `~/.claude/worktrees/waf-scanner-block`
- [ ] IP `139.144.169.16` already added to `dns/security_locals.tf` (confirmed in worktree)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Refactor Rule 3: From "Block Scanners" to "Block File Extensions"

- **Objective:** Strip Rule 3 down to file-extension-only matching. Remove all exploit paths, sensitive directory patterns, and SQLi patterns (those move to advanced rules). Rename rule reference and description appropriately.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Locate the rule with `description = "Block Scanners"` (current Rule 3)
  - [ ] Change `ref` from `block_scanners` to `block_file_extensions`
  - [ ] Change `description` from `"Block Scanners"` to `"Block File Extensions"`
  - [ ] Keep existing extensions: `.php`, `.phtml`, `.phar`, `.asp`, `.jsp`, `.cgi`, `.cfm`, `.bak`, `.sql`, `.swp`, `.log`
  - [ ] Add new extensions: `.aspx`, `.ini`, `.conf`, `.yaml`, `.yml`
  - [ ] Remove all path-based conditions (e.g., `/wp-`, `/phpmyadmin`, `/.git/`, `/.env`, `/actuator`, etc.)
  - [ ] Remove all SQLi patterns (e.g., `information_schema`, `sleep(`, `concat(`, etc.)
  - [ ] Remove POST to `/` condition (moves to Rule 16 in Phase 3)
  - [ ] Verify resulting expression is under 4,096 characters (expected ~800)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (Rule 3 expression and metadata)

- **Completion criteria:**
  - [ ] Rule 3 expression contains only file extension checks (no paths, no SQLi patterns)
  - [ ] All 15 extensions listed (existing 11 + new 4) are in the expression
  - [ ] Expression respects existing conditionals (e.g., `block_empty_user_agent`)
  - [ ] Character count verified ≤ 4,096
  - [ ] No syntax errors when file is saved

- **Observations:**
  - This is a pure refactor—no new rule added, just cleanup of existing Rule 3
  - This task must complete before Phase 3 (advanced rules) to avoid logical overlap

---

### Task 2 — Expand Rule 4: Extend User-Agent Blocklist from 8 to ~40+ Signatures

- **Objective:** Expand the scanner user-agent blocklist from the current 8 signatures to approximately 40+ known vulnerability scanner, directory brute-forcer, OSINT, and web scanner signatures.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Locate Rule 4 (current user-agent rule with `description = "Block User Agent"`)
  - [ ] Add the following scanner categories to the expression:
    - [ ] **Vulnerability scanners:** `nuclei`, `openvas`, `arachni`, `w3af`, `wapiti`, `commix`, `dalfox`, `jaeles`, `whatweb`, `netsparker`, `invicti`, `appscan`, `webinspect`, `detectify`, `censysinspect`, `tsunamisecurityscanner`
    - [ ] **Directory bruteforcers:** `gobuster`, `feroxbuster`, `dirbuster`, `ffuf`, `wfuzz`
    - [ ] **OSINT/recon tools:** `shodan`, `onyphe`, `internetmeasurement`, `havij`
    - [ ] **Web scanners:** `vega`, `httpx`, `bbot`, `l9explore`, `webbandit`, `webshag`, `wprecon`, `zmeu`, `jbrofuzz`, `fimap`, `sitelockspider`, `netlab360`
    - [ ] **Bot typos/variants:** `Mozlila`, `masscan-ng`, `Fuzz Faster U Fool`
  - [ ] Preserve the original 8 signatures
  - [ ] Ensure the expression respects the `block_empty_user_agent` conditional
  - [ ] Verify resulting expression is under 4,096 characters (expected ~1,800)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (Rule 4 expression)

- **Completion criteria:**
  - [ ] All ~40+ scanner signatures added to Rule 4 expression
  - [ ] Original 8 signatures are still present
  - [ ] Expression respects existing conditional logic
  - [ ] Character count verified ≤ 4,096
  - [ ] No syntax errors when file is saved

- **Observations:**
  - This task is independent of Task 1 and can be done in parallel
  - Case sensitivity and substring matching must follow Cloudflare WAF expression syntax

---

### Task 3 — Add Rule 11: Block Exploit Paths — Enterprise Software

- **Objective:** Create a new advanced WAF rule (Rule 11) targeting exploit paths for enterprise software: Jenkins, Solr, Confluence, Jira, Tomcat Manager, WebLogic, F5 BIG-IP, Citrix, Pulse Secure, Fortinet, Exchange, VMware vCenter, Telerik.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Locate the `var.enable_advanced_waf ? [...] : []` block (where advanced rules 6–10 are defined)
  - [ ] Add Rule 11 as a new entry in that array with:
    - `ref = "block_exploit_paths_enterprise"`
    - `description = "Block Exploit Paths — Enterprise Software"`
    - `priority = 11`
  - [ ] Build expression to match paths for: Jenkins, Solr, Confluence, Jira, Tomcat Manager, WebLogic, F5 BIG-IP, Citrix, Pulse Secure, Fortinet, Exchange (OWA/ECP/EWS), VMware vCenter, Telerik
  - [ ] Key paths to include: `/jenkins`, `/solr`, `/confluence`, `/wiki/`, `/jira/`, `/manager/html`, `/console/`, `/wls-wsat/`, `/_async/`, `/ws_utc/`, `/tmui/`, `/vpn/`, `/dana-na/`, `/ecp/`, `/EWS/`, `/autodiscover/`, `/OAB/`, `/PowerShell`, `/Telerik.Web.UI`, `/remote/login`, `/vcac/`, `/vsphere-client/`
  - [ ] Verify expression is under 4,096 characters (expected ~1,375)
  - [ ] Ensure rule is only applied when `enable_advanced_waf = true` (inherited from enclosing conditional)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 11 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 11 expression covers all listed enterprise software paths
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 11 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 4 — Add Rule 12: Block Exploit Paths — Chinese Enterprise Software

- **Objective:** Create a new advanced WAF rule (Rule 12) targeting exploit paths specific to Chinese enterprise software: Seeyon OA, Weaver/Panwei E-Cology, Yonyou NC, Landray OA, Tongda OA. This rule specifically targets the `/seeyon/htmlofficeservlet` endpoint where the `WAITFOR DELAY` SQLi attack occurred.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Add Rule 12 as the next entry after Rule 11 in the advanced rules array with:
    - `ref = "block_exploit_paths_chinese_oa"`
    - `description = "Block Exploit Paths — Chinese Enterprise Software"`
    - `priority = 12`
  - [ ] Build expression to match paths for: Seeyon, Weaver/E-Cology, Yonyou NC, Landray OA, Tongda OA
  - [ ] Ensure `/seeyon/htmlofficeservlet` is explicitly included (this is the attack vector from the incident)
  - [ ] Key paths to include: `/seeyon/`, `/weaver/`, `/ecology/`, `/NCFindWeb`, `/service/~`, `/servlet/~`, `/sys/ui/extend/`, `/ispirit/`, `/mac/gateway`, `/general/login_code`, `/htmlofficeservlet`
  - [ ] Verify expression is under 4,096 characters (expected ~800)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 12 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 12 expression covers all listed Chinese OA software paths
  - [ ] `/seeyon/htmlofficeservlet` is explicitly covered
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 12 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 5 — Add Rule 13: Block Exploit Paths — Frameworks & Debug

- **Objective:** Create a new advanced WAF rule (Rule 13) targeting exploit paths for frameworks and debug endpoints: Laravel Ignition, Spring Boot Actuator, GraphQL, Swagger/API docs, WordPress, Drupal, ThinkPHP, PHPUnit.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Add Rule 13 as the next entry after Rule 12 in the advanced rules array with:
    - `ref = "block_exploit_paths_frameworks"`
    - `description = "Block Exploit Paths — Frameworks & Debug"`
    - `priority = 13`
  - [ ] Build expression to match paths for framework and debug endpoints
  - [ ] Key paths to include: `/_ignition/`, `/graphql`, `/graphiql`, `/swagger`, `/api-docs`, `/wp-login.php`, `/wp-json/`, `/xmlrpc.php`, `/wp-cron.php`, `/?q=node`, `/vendor/phpunit/`, `/eval-stdin.php`, `/debug/`, `/trace.axd`, `/elmah.axd`, `/cgi-bin/`, `/actuator` (moved from old Rule 3)
  - [ ] Verify expression is under 4,096 characters (expected ~1,250)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 13 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 13 expression covers all listed framework and debug paths
  - [ ] `/actuator` is included (moved from Rule 3 cleanup)
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 13 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 6 — Add Rule 14: Block Exploit Paths — Sensitive Files & Directories

- **Objective:** Create a new advanced WAF rule (Rule 14) targeting sensitive files, directories, configuration files, backups, VCS directories, webshells, and admin panels.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Add Rule 14 as the next entry after Rule 13 in the advanced rules array with:
    - `ref = "block_exploit_paths_sensitive"`
    - `description = "Block Exploit Paths — Sensitive Files & Directories"`
    - `priority = 14`
  - [ ] Build expression to match sensitive file paths and directories
  - [ ] Key paths to include: `/.git/`, `/.env`, `/.svn/`, `/.hg/`, `/.htaccess`, `/.htpasswd`, `/.ds_store`, `/.aws/`, `/.docker/`, `/wp-config`, `/web.config`, `/database.yml`, `/Dockerfile`, `/docker-compose`, `/Gemfile`, `/backup`, `/phpmyadmin`, `/pma/`, `/adminer`, `/server-status`, `/server-info`, `/shell.php`, `/cmd.php`, `/c99.php`, `/r57.php`, `/wso.php`, `/b374k.php`, `/alfa.php`, `/storage/logs/`
  - [ ] Verify expression is under 4,096 characters (expected ~1,500)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 14 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 14 expression covers all listed sensitive files and directories
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 14 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 7 — Add Rule 15: Block SQLi Patterns

- **Objective:** Create a new advanced WAF rule (Rule 15) targeting SQL injection patterns in query strings and request bodies, including the `WAITFOR DELAY` blind SQLi pattern that triggered this work.

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Add Rule 15 as the next entry after Rule 14 in the advanced rules array with:
    - `ref = "block_sqli_query"`
    - `description = "Block SQLi Patterns"`
    - `priority = 15`
  - [ ] Build expression to match SQLi attack patterns in query string
  - [ ] Key patterns to include: `information_schema`, `sleep(`, `waitfor`, `benchmark(`, `pg_sleep(`, `extractvalue(`, `updatexml(`, `php://input`, `/etc/passwd`, `cmd=`, `union select`, `union+select`, `concat(`, `char(`, `0x`, `@@version`, `load_file(`, `into outfile`, `into dumpfile`
  - [ ] Ensure `waitfor` pattern is explicitly included (the blind SQLi attack vector)
  - [ ] Verify expression is under 4,096 characters (expected ~1,100)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 15 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 15 expression covers all listed SQLi patterns
  - [ ] `waitfor` pattern is explicitly covered (case-insensitive)
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 15 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 8 — Add Rule 16: Block POST to Root

- **Objective:** Create a new advanced WAF rule (Rule 16) to block POST requests to the root path `/`. This pattern was removed from Rule 3 during the refactor and is a common scanner pattern that only affects the Rails application (Pro zones).

- **Actions (checklist):**
  - [ ] Open `modules/cloudflare_zone_security/main.tf`
  - [ ] Add Rule 16 as the final entry after Rule 15 in the advanced rules array with:
    - `ref = "block_post_root"`
    - `description = "Block POST to Root"`
    - `priority = 16`
  - [ ] Build expression to match POST requests to `/` (root path)
  - [ ] Verify expression is under 4,096 characters (expected ~60)

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (new Rule 16 in advanced rules block)

- **Completion criteria:**
  - [ ] Rule 16 expression matches POST to `/`
  - [ ] Character count verified ≤ 4,096
  - [ ] Priority number is 16 (unique within the ruleset)
  - [ ] No syntax errors when file is saved

---

### Task 9 — Validate All Rules and Character Counts

- **Objective:** Verify that all refactored and new rules are syntactically correct, that character counts are within limits, and that the final rule structure matches the plan.

- **Actions (checklist):**
  - [ ] Run `terraform plan` in the `dns` workspace: `terraform plan -var-file="env/dns.tfvars"`
  - [ ] Review the plan output for Rule 1–5 (base rules) on Free zones—should be unchanged or minimal updates
  - [ ] Review the plan output for Rule 1–16 (base + advanced) on Pro zones—should show updates to all modified/new rules
  - [ ] Verify no destroy/create cycles in the plan output (only in-place updates expected)
  - [ ] Manually verify character count for each rule:
    - [ ] Rule 3: ≤ 4,096 (expected ~800)
    - [ ] Rule 4: ≤ 4,096 (expected ~1,800)
    - [ ] Rule 11: ≤ 4,096 (expected ~1,375)
    - [ ] Rule 12: ≤ 4,096 (expected ~800)
    - [ ] Rule 13: ≤ 4,096 (expected ~1,250)
    - [ ] Rule 14: ≤ 4,096 (expected ~1,500)
    - [ ] Rule 15: ≤ 4,096 (expected ~1,100)
    - [ ] Rule 16: ≤ 4,096 (expected ~60)
  - [ ] Verify rule count on Free zones: 5 total (Rules 1–5)
  - [ ] Verify rule count on Pro zones: 16 total (Rules 1–16, all advanced gated by `enable_advanced_waf = true`)
  - [ ] Save plan output to `/tmp/terraform_plan_dns_waf-scanner-block_$(date +%Y%m%d_%H%M%S).txt` for reference
  - [ ] Create a character count verification document or script to confirm each rule is within limits

- **Affected files/areas:** `modules/cloudflare_zone_security/main.tf` (all rules), `dns/` workspace

- **Completion criteria:**
  - [ ] `terraform plan` shows only in-place updates (no destroy/create)
  - [ ] All character counts verified ≤ 4,096 per rule
  - [ ] Rule count matches expected structure (5 base on Free, 16 total on Pro)
  - [ ] Plan output saved to `/tmp/` for reference

---

### Task 10 — Update CHANGELOG.md

- **Objective:** Add a user-focused changelog entry describing the WAF security improvements. Entry must be written from a business/security perspective, not technical implementation details.

- **Actions (checklist):**
  - [ ] Open `CHANGELOG.md` in the terraform project root
  - [ ] Locate the `[Unreleased]` section (create if missing)
  - [ ] Add a bullet point entry describing the improvement, e.g.:
    - "Enhanced WAF rule coverage to block vulnerability scanners, exploit path crawlers, and SQL injection attacks targeting enterprise software and framework endpoints"
    - OR similar user-focused language that explains the VALUE of the change
  - [ ] Ensure the entry does NOT mention:
    - Technical details (class names, file paths, variable names)
    - Implementation specifics (rule numbers, character limits, Terraform syntax)
    - Specific product names that users don't care about
  - [ ] Follow existing changelog formatting (Semantic Versioning + Keep a Changelog style)

- **Affected files/areas:** `CHANGELOG.md` (root of terraform project)

- **Completion criteria:**
  - [ ] `CHANGELOG.md` updated with entry under `[Unreleased]`
  - [ ] Entry written from a business/user perspective (VALUE focus, not implementation)
  - [ ] Entry is concise (1–2 sentences)
  - [ ] Formatting matches existing entries in the changelog

---

## 2) Items Requiring User Confirmation

- [ ] **Character count validation method:** Manual review of expressions in `main.tf` or automated script to count characters? (Manual recommended for first run)
- [ ] **Cloudflare expression syntax:** Confirm that the WAF expression format in existing Rules 1–5 is the reference for new rules (e.g., case sensitivity, logical operators, path matching)
- [ ] **Priority numbering:** Confirm that Rule priorities should be sequential (6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16) as shown in PLAN.md
- [ ] **Character count estimates in PLAN.md:** Are the provided estimates (Rule 3 ~800, Rule 4 ~1,800, etc.) acceptable as targets, or should actual counts be measured during implementation?
- [ ] **Free vs. Pro zone rule gating:** Confirm that `enable_advanced_waf = false` on Free zones will completely prevent Rules 11–16 from being created (no partial rule creation)

> **Expected response (example):**
> `APPROVED: Use manual character validation; follow existing Rule 1–5 syntax as reference; priorities are sequential 6–16; use estimates as targets, verify final counts before apply; confirm enable_advanced_waf gates all advanced rules.`

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **After terraform plan validation:** If character limits are exceeded on any rule, reassess path/pattern selection or split rule into multiple rules
- [ ] **After terraform apply:** Monitor Cloudflare rule creation logs for any warnings or errors (e.g., expression compilation failures)
- [ ] **Post-deployment testing:** Request security team to verify that known scanners (nuclei, openvas, etc.) are now blocked when tested against the deployed environment
- [ ] **If Free zones exceed 5 rules:** Investigate whether `enable_advanced_waf` is correctly set to `false` on Free zone configs

---

**Status:** COMPLETED (merged via PR #220, with hotfixes #221 and #222)
