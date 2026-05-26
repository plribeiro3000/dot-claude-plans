# TASKS — Cloudflare Security Rules → Terraform (Phase 1 — Pen Test Fix)

> **Objective of this iteration:** Create a reusable Terraform module for Cloudflare zone security, import all existing WAF rules, add the Block Ports rule (pen test fix), and fix 4sharkpay.com zone settings.
> **Reference:** PLAN.md (section: "Phase 1 — Module + Import + Port Blocking + Zone Settings Fixes").

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved** (option: Reusable module with per-zone overrides)
- [ ] **Base branch:** `develop` • **Working branch:** `feature/cloudflare-security-terraform`
- [ ] User understands git worktree requirement (VPC migration in progress on terraform main branch)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Create git worktree for feature branch
- **Objective:** Isolate feature branch from main terraform branch (VPC migration in progress).
- **Actions (checklist):**
  - [ ] Create new git worktree in `.claude/worktrees/` with branch name `feature/cloudflare-security-terraform`
  - [ ] Verify worktree is on `develop` and clean
- **Affected files/areas:** `.git/`, `.claude/worktrees/`
- **Completion criteria:** Worktree created, branch exists, ready for commits.
- **Observations:** Use `EnterWorktree` to isolate work. VPC migration is active on main terraform branch.

### Task 2 — Create cloudflare_zone_security module structure
- **Objective:** Create reusable module with all security resources (WAF custom rules, rate limiting, OWASP, zone settings).
- **Actions (checklist):**
  - [ ] Create directory: `terraform/modules/cloudflare_zone_security/`
  - [ ] Create `terraform/modules/cloudflare_zone_security/main.tf` with:
    - [ ] Cloudflare custom ruleset resource (`cloudflare_ruleset`) for HTTP request firewall
    - [ ] Individual rules: Block Region, Block IPs, Block Scanners, Block User Agent, Block Ports
    - [ ] Cloudflare rate limiting rule (HTTP request rate limiting)
    - [ ] Cloudflare OWASP managed ruleset
    - [ ] Zone settings resource (`cloudflare_zone_settings`) for HTTPS, TLS, and other settings
  - [ ] Create `terraform/modules/cloudflare_zone_security/variables.tf` with inputs:
    - [ ] `zone_id` (required)
    - [ ] `blocked_ips` (list, optional, default empty)
    - [ ] `enable_https_redirect` (bool, default true)
    - [ ] `min_tls_version` (string, default "1.2")
    - [ ] `manage_zone_settings` (bool, default true)
    - [ ] `blocked_ports` (list, default Cloudflare alternative ports: 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880)
  - [ ] Create `terraform/modules/cloudflare_zone_security/outputs.tf` with:
    - [ ] `custom_ruleset_id`
    - [ ] `rate_limiting_rule_id`
    - [ ] `owasp_ruleset_id`
- **Affected files/areas:** `terraform/modules/cloudflare_zone_security/` (new)
- **Completion criteria:** Module files created, Terraform validates without errors, module structure follows existing patterns in `terraform/modules/`.
- **[HOLD POINT]** Pause here for user validation of:
  - [ ] Cloudflare provider v5.0 ruleset resource structure (confirm nested rule model)
  - [ ] Block Region expression — confirm EU continent included for all zones
  - [ ] Block Ports list — confirm all 11 non-standard ports included
  - [ ] Zone settings to manage: always_use_https, min_tls_version, automatic_https_rewrites

### Task 3 — Create zone security instantiation files
- **Objective:** Instantiate module for all 5 zones in `terraform/dns/`.
- **Actions (checklist):**
  - [ ] Create `terraform/dns/security_4shark_com.tf`:
    - [ ] Call module with zone_id `b2b861d356ace7a78485d440b8f6ab65`
    - [ ] Set variables: `blocked_ips` (from existing rule), `manage_zone_settings=false` (no changes needed)
  - [ ] Create `terraform/dns/security_4shark_com_br.tf`:
    - [ ] Call module with zone_id `436ca10c9bba089b7f1ca63db67277f6`
    - [ ] Set variables: `blocked_ips` (from existing rule), `manage_zone_settings=false` (SSL is flexible intentionally), override `min_tls_version` if needed
  - [ ] Create `terraform/dns/security_app4shark_com.tf`:
    - [ ] Call module with zone_id `51fd2f8ea7646efc2ec849a1e947ed84`
    - [ ] Set variables: `blocked_ips` (from existing rule), `manage_zone_settings=false`
  - [ ] Create `terraform/dns/security_app4shark_com_br.tf`:
    - [ ] Call module with zone_id `d92c63ce0f8f35735dc7f48169a885e4`
    - [ ] Set variables: `blocked_ips` (from existing rule), `manage_zone_settings=false`
  - [ ] Create `terraform/dns/security_4sharkpay_com.tf`:
    - [ ] Call module with zone_id `c97ffdcd1282bf95ff97054d1fc8d60f`
    - [ ] Set variables: `blocked_ips` (from existing rule), `manage_zone_settings=true`
    - [ ] Override: `enable_https_redirect=true`, `min_tls_version="1.2"` (zone settings fixes)
- **Affected files/areas:** `terraform/dns/security_*.tf` (new, 5 files)
- **Completion criteria:** All 5 files created, module calls are valid, Terraform validates without errors.
- **Observations:** Block IPs list is shared across all zones — create as local variable or in module.

### Task 4 — Retrieve missing Block IPs rule ID from API for app4shark.com.br
- **Objective:** Get the rule ID for app4shark.com.br's Block IPs rule (not documented in spike).
- **Actions (checklist):**
  - [ ] Query Cloudflare API for app4shark.com.br ruleset rules
  - [ ] Identify Block IPs rule (same expression as other zones, but different ID)
  - [ ] Document rule ID: `app4shark.com.br | Block IPs | <ID>`
  - [ ] Repeat for Block Scanners and Block User Agent if missing
- **Affected files/areas:** SPIKE.md (update if needed), PLAN.md (reference)
- **Completion criteria:** All 3 missing rule IDs retrieved and documented.
- **[HOLD POINT]** Before proceeding to import, confirm rule IDs from API:
  - [ ] app4shark.com.br Block IPs rule ID
  - [ ] app4shark.com.br Block Scanners rule ID
  - [ ] app4shark.com.br Block User Agent rule ID

### Task 5 — Import existing WAF ruleset rules into Terraform state
- **Objective:** Import all existing custom ruleset rules from 4 zones (avoid resource recreation).
- **Actions (checklist):**
  - [ ] Import Block Region rules for 4shark.com, 4shark.com.br, app4shark.com, app4shark.com.br
    - [ ] `terraform import cloudflare_ruleset.<zone>.rules[<index>] <zone_id>/<ruleset_id>/<rule_id>`
  - [ ] Import Block IPs rules (4 zones)
  - [ ] Import Block Scanners rules (4 zones)
  - [ ] Import Block User Agent rules (4 zones)
  - [ ] Import Rate Limiting rule for app4shark.com (only zone with existing rule)
  - [ ] Run `terraform state list` to verify all imports
- **Affected files/areas:** `.terraform/state`, module instantiation files
- **Completion criteria:** All rules imported, `terraform state list` shows all imported resources, no errors.
- **Observations:** Use rule IDs from SPIKE.md. Ruleset ID may differ — retrieve from API if needed. Order matters — ensure rules are imported in correct sequence.
- **[HOLD POINT]** Before running `terraform plan`, confirm imports:
  - [ ] All 16 rule imports successful
  - [ ] No Terraform errors in state validation

### Task 6 — Run terraform plan and verify zero diff for existing zones
- **Objective:** Confirm that Terraform matches current Cloudflare state (4 existing zones unchanged).
- **Actions (checklist):**
  - [ ] Run `terraform plan` and save output to `/tmp/`
  - [ ] Review output: verify zero adds/changes/deletes for 4shark.com, 4shark.com.br, app4shark.com, app4shark.com.br
  - [ ] Verify 4sharkpay.com shows **new resources only** (custom ruleset, rules, rate limiting, OWASP, zone settings)
  - [ ] Check for any drift or import errors
- **Affected files/areas:** Terraform state
- **Completion criteria:** Plan shows zero diff for 4 existing zones, new resources pending for 4sharkpay.com.
- **Observations:** Save plan output to `/tmp/terraform_plan_phase1_<timestamp>.txt` for review.
- **[HOLD POINT]** Pause and show plan output to user for validation before apply:
  - [ ] 4 existing zones: zero changes
  - [ ] 4sharkpay.com: new resources (ruleset, rules, rate limiting, OWASP, zone settings)
  - [ ] No unintended drift detected

### Task 7 — Add Block Ports rule to module
- **Objective:** Implement the pen test fix — block Cloudflare alternative ports.
- **Actions (checklist):**
  - [ ] Add rule to module's custom ruleset (in `main.tf`):
    - [ ] Rule name: "Block Ports"
    - [ ] Expression: Block ports 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880
    - [ ] Action: block
    - [ ] Order: after "Block User Agent", before "Rate Limiting"
  - [ ] Verify rule is parameterizable (blocked_ports variable)
  - [ ] Test rule expression syntax
- **Affected files/areas:** `terraform/modules/cloudflare_zone_security/main.tf`
- **Completion criteria:** Rule added, expression valid, module validates.
- **Observations:** This is the core pen test fix. Rule must block **all 11 ports**.

### Task 8 — Run terraform apply for 4sharkpay.com zone
- **Objective:** Apply new security rules and zone settings to 4sharkpay.com (the zone with zero existing rules).
- **Actions (checklist):**
  - [ ] Run `terraform apply`
  - [ ] Confirm apply: yes
  - [ ] Verify 4sharkpay.com resources created successfully
  - [ ] Check Cloudflare API to confirm:
    - [ ] Custom ruleset created
    - [ ] All 5 rules present (Block Region, Block IPs, Block Scanners, Block User Agent, Block Ports)
    - [ ] Rate Limiting rule present
    - [ ] OWASP ruleset present
    - [ ] Zone settings updated: always_use_https=on, min_tls_version=1.2
- **Affected files/areas:** `terraform/dns/security_4sharkpay_com.tf`, Cloudflare API state
- **Completion criteria:** Apply successful, Cloudflare API confirms all resources created, zone settings correct.
- **[HOLD POINT]** Before validation, confirm apply was successful:
  - [ ] Terraform state updated
  - [ ] No apply errors

### Task 9 — Validate ports are blocked on 4sharkpay.com
- **Objective:** Confirm pen test fix is working — blocked ports reject connections.
- **Actions (checklist):**
  - [ ] From outside Cloudflare IPs, attempt connections to 4sharkpay.com on each blocked port:
    - [ ] Port 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880
  - [ ] Verify all connections are **rejected** (403 Forbidden or similar WAF block)
  - [ ] Verify port 443 (standard HTTPS) still works
  - [ ] Verify port 80 → 443 redirect still works (always_use_https)
  - [ ] Document validation results
- **Affected files/areas:** N/A (validation only)
- **Completion criteria:** All 11 blocked ports reject connections, standard ports work.
- **Observations:** Can use `curl`, `telnet`, or online port scan tools. Document any blocked port that doesn't reject.
- **[HOLD POINT]** If any port is still open, troubleshoot before proceeding:
  - [ ] Confirm rule is in Cloudflare API
  - [ ] Check rule order
  - [ ] Verify rule expression is correct

### Task 10 — Update CHANGELOG.md
- **Objective:** Document Phase 1 changes for end users.
- **Actions (checklist):**
  - [ ] Open `CHANGELOG.md` in terraform project root
  - [ ] Add entry under "Unreleased" or next version:
    - [ ] Highlight: Cloudflare zone security rules now managed by Terraform
    - [ ] Highlight: Added Block Ports rule to prevent access via alternative Cloudflare ports
    - [ ] Highlight: Fixed 4sharkpay.com zone settings (HTTPS enforcement, TLS 1.2 minimum)
    - [ ] Reference: No user-facing impact for standard traffic
  - [ ] Keep entry user-focused (not technical details)
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** Changelog updated with Phase 1 summary.
- **Observations:** Write from business/user perspective, not technical implementation details.

### Task 11 — Commit and push changes
- **Objective:** Commit Phase 1 work to feature branch.
- **Actions (checklist):**
  - [ ] Stage files: module files, instantiation files, changelog
  - [ ] Run `git status` to verify staging
  - [ ] Commit with message following Angular guidelines:
    - [ ] Format: `feat(cloudflare): manage zone security rules via Terraform`
    - [ ] Include: module creation, WAF rule imports, port blocking, zone settings fix
    - [ ] NO "Co-Authored-By" or AI references
  - [ ] Push to remote: `git push -u origin feature/cloudflare-security-terraform`
- **Affected files/areas:** `.git/`, remote repository
- **Completion criteria:** Changes committed, branch pushed, ready for PR.
- **Observations:** One commit per PR is standard workflow.

### Task 12 — Create pull request
- **Objective:** Create PR for Phase 1 work.
- **Actions (checklist):**
  - [ ] PR title: commit message (`feat(cloudflare): manage zone security rules via Terraform`)
  - [ ] PR body: optional (can reference CHANGELOG entry)
  - [ ] Target branch: `develop`
  - [ ] Review: assign to peer for code review
- **Affected files/areas:** GitHub PR
- **Completion criteria:** PR created, assigned for review.
- **Observations:** Use `@agent-pr-writer` if detailed PR description needed.

---

## 2) Items Requiring User Confirmation

- [ ] **Module structure:** Confirm Cloudflare provider v5.0 nested ruleset resource model matches planned `main.tf` structure
- [ ] **Block Ports list:** Confirm all 11 non-standard Cloudflare ports included: 2052, 2053, 2082, 2083, 2086, 2087, 2095, 2096, 8080, 8443, 8880
- [ ] **4shark.com.br SSL:** Confirm NOT to change `ssl=flexible` (intentional for Wix redirect)
- [ ] **4sharkpay.com zone settings:** Confirm always_use_https=on and min_tls_version=1.2 are the correct fixes
- [ ] **Existing rule IDs:** Missing app4shark.com.br rule IDs (Block IPs, Block Scanners, Block User Agent) — will retrieve from API during Task 4

> **Expected response (example):**
> `APPROVED: all 11 ports blocked; 4shark.com.br SSL unchanged; 4sharkpay.com fixes confirmed; retrieve missing rule IDs from API.`

---

## 3) Pending Items After This Iteration

- [ ] **Phase 2:** Standardize rules across all zones (add rate limiting + OWASP to remaining zones, normalize EU/empty UA)
- [ ] **Phase 3:** Replace S3 redirect buckets with Cloudflare Redirect Rules (verify token permissions first)
- [ ] **Token permissions:** Confirm current token has "Dynamic Redirect" permission for Phase 3
- [ ] **Flag in PLAN.md:** Phase 1 complete, Phase 2/3 will be separate PRs
