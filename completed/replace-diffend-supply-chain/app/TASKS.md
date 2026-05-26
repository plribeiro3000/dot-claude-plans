# NEXT TASKS — Remove Diffend, Add Supply Chain Security Stack — Phase 2: app

> **Objective of this iteration:** Remove Diffend bundler plugin and gems from the app repository, replace with bundler-audit and license_finder, add new CI jobs, enable Bundler checksums, and complete Rails 8.1.2.1 bump.
> **Reference:** derived from `PLAN.md` (section: Phase 2: app — Remove Diffend, Add New Stack, Rails Bump).

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] **Base branch:** `develop` • **Working branch:** `feature/bump-rails-8.1.2.1`
- [ ] Feature branch already exists with Rails version constraint updated in Gemfile
- [ ] Bundle update already completed (Gemfile.lock has Rails changes)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Remove Diffend from Gemfile
- **Objective:** Remove Diffend plugin and gem dependencies from the main Gemfile.
- **Actions (checklist):**
  - [ ] Remove line: `plugin 'diffend'`
  - [ ] Remove line: `gem 'diffend-monitor', require: false`
  - [ ] Verify Rails constraint `~> 8.1.2.1` is in place (no change needed)
- **Affected files/areas:** `Gemfile`
- **Completion criteria:** Gemfile has no Diffend references; Rails version remains `~> 8.1.2.1`

### Task 2 — Add bundler-audit and license_finder to Gemfile
- **Objective:** Add the replacement security gems to the Gemfile.
- **Actions (checklist):**
  - [ ] Add to main section: `gem 'bundler-audit', require: false`
  - [ ] Add to main section: `gem 'license_finder', require: false`
  - [ ] Verify placement is consistent with existing gems
- **Affected files/areas:** `Gemfile`
- **Completion criteria:** Both gems appear in Gemfile with `require: false`

### Task 3 — Delete .diffend.yml
- **Objective:** Remove the Diffend configuration file from the repository.
- **Actions (checklist):**
  - [ ] Delete file: `.diffend.yml`
  - [ ] Verify deletion via `git status`
- **Affected files/areas:** `.diffend.yml`
- **Completion criteria:** File is deleted and staged in git

### Task 4 — Clean up .bundle/plugin/ directory locally
- **Objective:** Remove local Diffend plugin directory (untracked).
- **Actions (checklist):**
  - [ ] Run: `rm -rf .bundle/plugin/`
  - [ ] Verify it's gone: `ls -la .bundle/ 2>/dev/null || echo "No .bundle dir"`
- **Affected files/areas:** `.bundle/plugin/` (local, untracked)
- **Completion criteria:** Directory no longer exists locally

### Task 5 — Update Dockerfile COPY instruction
- **Objective:** Remove `.diffend.yml` from the Docker build context.
- **Actions (checklist):**
  - [ ] Edit file: `.github/docker/Dockerfile`
  - [ ] Find line: `COPY Gemfile Gemfile.lock .diffend.yml ./`
  - [ ] Change to: `COPY Gemfile Gemfile.lock ./`
- **Affected files/areas:** `.github/docker/Dockerfile`
- **Completion criteria:** Dockerfile COPY instruction no longer references `.diffend.yml`

### Task 6 — Remove DIFFEND env vars from ci.yaml
- **Objective:** Clean up Diffend environment variables from the main CI workflow.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yaml`
  - [ ] Remove env var: `DIFFEND_ENV`
  - [ ] Remove env var: `DIFFEND_PROJECT_ID`
  - [ ] Remove env var: `DIFFEND_SHAREABLE_ID`
  - [ ] Remove env var: `DIFFEND_SHAREABLE_KEY`
- **Affected files/areas:** `.github/workflows/ci.yaml`
- **Completion criteria:** No DIFFEND_* env vars remain in ci.yaml

### Task 7 — Add bundler-audit job to ci.yaml
- **Objective:** Add CVE scanning CI job after brakeman.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yaml`
  - [ ] Locate the `brakeman` job
  - [ ] Add new job after `brakeman`:
    ```yaml
    bundler-audit:
      name: Bundler Audit (CVE Scan)
      runs-on: ubuntu-latest
      environment: Test
      timeout-minutes: 5
      steps:
        - uses: actions/checkout@v4
        - uses: ruby/setup-ruby@v1
          with:
            ruby-version: "4.0.2"
            bundler-cache: true
        - run: bundle exec bundler-audit check --update
          timeout-minutes: 5
    ```
- **Affected files/areas:** `.github/workflows/ci.yaml`
- **Completion criteria:** Job appears in ci.yaml with correct structure and runs after brakeman

### Task 8 — Add license-finder job to ci.yaml
- **Objective:** Add license compliance checking CI job after bundler-audit.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yaml`
  - [ ] Add new job after `bundler-audit`:
    ```yaml
    license-finder:
      name: License Finder (License Compliance)
      runs-on: ubuntu-latest
      environment: Test
      timeout-minutes: 5
      steps:
        - uses: actions/checkout@v4
        - uses: ruby/setup-ruby@v1
          with:
            ruby-version: "4.0.2"
            bundler-cache: true
        - run: bundle exec license_finder
          timeout-minutes: 5
    ```
- **Affected files/areas:** `.github/workflows/ci.yaml`
- **Completion criteria:** Job appears in ci.yaml with correct structure and runs after bundler-audit

### Task 9 — Remove DIFFEND references from build-image.yaml
- **Objective:** Clean up Diffend environment variables and build arguments from the build workflow.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/build-image.yaml`
  - [ ] Find all `Setup environment` jq filters and remove `DIFFEND_` from the regex (keep AWS pattern only)
  - [ ] Find all `build-args` blocks (appears 4 times, one per environment)
  - [ ] Remove from each: `DIFFEND_PROJECT_ID`, `DIFFEND_SHAREABLE_ID`, `DIFFEND_SHAREABLE_KEY`
- **Affected files/areas:** `.github/workflows/build-image.yaml`
- **Completion criteria:** No DIFFEND_* references remain in any jq filter or build-args block

### Task 10 — Run bundle lock --add-checksums
- **Objective:** Enable Bundler checksums for tampering verification.
- **Actions (checklist):**
  - [ ] Run: `bundle lock --add-checksums`
  - [ ] Verify Gemfile.lock now contains checksum entries (look for `checksum:` lines)
  - [ ] Stage Gemfile.lock changes: `git add Gemfile.lock`
- **Affected files/areas:** `Gemfile.lock`
- **Completion criteria:** Gemfile.lock contains checksums; command completes without errors

### Task 11 — Update CHANGELOG.md
- **Objective:** Document the changes in the changelog following 4Shark guidelines.
- **Actions (checklist):**
  - [ ] Open `CHANGELOG.md`
  - [ ] Add new version section with today's date if not present
  - [ ] Under `### Removed` section, add: `- Diffend bundler plugin and gem`
  - [ ] Under `### Added` section, add: `- Bundler Audit for CVE scanning`
  - [ ] Under `### Added` section, add: `- License Finder for license compliance`
  - [ ] Under `### Changed` section, add: `- Enabled Bundler checksums for dependency tampering verification`
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** CHANGELOG.md updated with concise entries describing removals and additions

### Task 12 — Verify all changes and prepare commit
- **Objective:** Final verification before committing.
- **Actions (checklist):**
  - [ ] Run: `git status` to review all staged changes
  - [ ] Verify no sensitive files are staged (check `.gitignore`)
  - [ ] Run: `bundle audit check --update` locally to verify bundler-audit gem is installed
  - [ ] Run: `bundle exec license_finder` locally to check for license issues (may show warnings — expected on first run)
  - [ ] Create commit with Angular guidelines: `feat(app): replace diffend with supply chain security stack` followed by description of changes
- **Affected files/areas:** Multiple (see previous tasks)
- **Completion criteria:** All changes staged; local verification passes; ready to create PR

---

## 2) Items Requiring User Confirmation

- [ ] **License warnings from license_finder:** The first run may flag existing gems as unapproved. Should we approve these locally with `license_finder whitelist add` before pushing, or handle post-merge?
- [ ] **Changelog format:** Confirm the changelog entries follow 4Shark guidelines (simple, direct, no technical details).

> **Expected response (example):**
> `APPROVED: handle license warnings locally before pushing; changelog format is correct.`

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] If `license_finder` identifies unapproved licenses, add them to a license whitelist (`.license_finder.yml`) and commit.
- [ ] If `bundler-audit` finds advisories, document them and decide whether to update gems or document exceptions.
- [ ] Verify CI passes on the PR before merge.
