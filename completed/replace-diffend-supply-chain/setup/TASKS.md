# NEXT TASKS — Remove Diffend, Add Supply Chain Security Stack — Phase 4: setup

> **Objective of this iteration:** Remove Diffend bundler plugin from the setup repository, replace with bundler-audit and license_finder, add new CI jobs, enable Bundler checksums, update Dockerfile, and complete Rails 8.1.2.1 bump.
> **Reference:** derived from `PLAN.md` (section: Phase 4: setup — Remove Diffend, Add New Stack, Rails Bump).

---

## 0) Pre-conditions

- [ ] `PLAN.md` **approved**
- [ ] **Base branch:** `develop` • **Working branch:** `feature/bump-rails-8.1.2.1`
- [ ] Feature branch already exists with Rails version constraint updated in Gemfile
- [ ] Bundle update may need to be run (setup repo specifics)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Remove Diffend plugin from Gemfile
- **Objective:** Remove the Diffend plugin line from Gemfile.
- **Actions (checklist):**
  - [ ] Edit file: `Gemfile`
  - [ ] Find and remove line: `plugin 'diffend'`
  - [ ] Note: Diffend-monitor gem does NOT appear in setup's Gemfile (no removal needed)
  - [ ] Verify Rails version constraint is in place
- **Affected files/areas:** `Gemfile`
- **Completion criteria:** Diffend plugin line is removed; no Diffend references remain

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

### Task 4 — Update Dockerfile COPY instruction
- **Objective:** Remove `.diffend.yml` from the Docker build context.
- **Actions (checklist):**
  - [ ] Edit file: `.github/docker/web/Dockerfile` (note: location is different from other repos)
  - [ ] Find line: `COPY Gemfile Gemfile.lock .diffend.yml ./`
  - [ ] Change to: `COPY Gemfile Gemfile.lock ./`
- **Affected files/areas:** `.github/docker/web/Dockerfile`
- **Completion criteria:** Dockerfile COPY instruction no longer references `.diffend.yml`

### Task 5 — Remove DIFFEND env vars from ci.yml
- **Objective:** Clean up Diffend environment variables from the CI workflow.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yml`
  - [ ] Remove env var: `DIFFEND_ENV`
  - [ ] Remove env var: `DIFFEND_PROJECT_ID`
  - [ ] Remove env var: `DIFFEND_SHAREABLE_ID`
  - [ ] Remove env var: `DIFFEND_SHAREABLE_KEY`
- **Affected files/areas:** `.github/workflows/ci.yml`
- **Completion criteria:** No DIFFEND_* env vars remain in ci.yml

### Task 6 — Add bundler-audit job to ci.yml
- **Objective:** Add CVE scanning CI job to the CI workflow.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yml`
  - [ ] Add new job:
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
- **Affected files/areas:** `.github/workflows/ci.yml`
- **Completion criteria:** bundler-audit job appears in ci.yml with correct structure

### Task 7 — Add license-finder job to ci.yml
- **Objective:** Add license compliance checking CI job to the CI workflow.
- **Actions (checklist):**
  - [ ] Edit file: `.github/workflows/ci.yml`
  - [ ] Add new job:
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
- **Affected files/areas:** `.github/workflows/ci.yml`
- **Completion criteria:** license-finder job appears in ci.yml with correct structure

### Task 8 — Run bundle update (if needed)
- **Objective:** Ensure Gemfile.lock is up to date with new gems and Rails 8.1.2.1.
- **Actions (checklist):**
  - [ ] Run: `bundle update rails railties actionpack actionview activerecord activesupport actionmailer actioncable activejob activemodel activestorage actionmailbox actiontext railties bundler-audit license_finder`
  - [ ] Verify command completes without errors
  - [ ] Stage Gemfile.lock: `git add Gemfile.lock`
- **Affected files/areas:** `Gemfile.lock`
- **Completion criteria:** Bundle update completes; Gemfile.lock is updated

### Task 9 — Run bundle lock --add-checksums
- **Objective:** Enable Bundler checksums for tampering verification.
- **Actions (checklist):**
  - [ ] Run: `bundle lock --add-checksums`
  - [ ] Verify Gemfile.lock now contains checksum entries (look for `checksum:` lines)
  - [ ] Verify Gemfile.lock is still staged after checksums are added
- **Affected files/areas:** `Gemfile.lock`
- **Completion criteria:** Gemfile.lock contains checksums; command completes without errors

### Task 10 — Update CHANGELOG.md
- **Objective:** Document the changes in the changelog following 4Shark guidelines.
- **Actions (checklist):**
  - [ ] Open `CHANGELOG.md`
  - [ ] Add new version section with today's date if not present
  - [ ] Under `### Removed` section, add: `- Diffend bundler plugin`
  - [ ] Under `### Added` section, add: `- Bundler Audit for CVE scanning`
  - [ ] Under `### Added` section, add: `- License Finder for license compliance`
  - [ ] Under `### Changed` section, add: `- Enabled Bundler checksums for dependency tampering verification`
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** CHANGELOG.md updated with concise entries describing removals and additions

### Task 11 — Verify all changes and prepare commit
- **Objective:** Final verification before committing.
- **Actions (checklist):**
  - [ ] Run: `git status` to review all staged changes
  - [ ] Verify no sensitive files are staged (check `.gitignore`)
  - [ ] Run: `bundle audit check --update` locally to verify bundler-audit gem is installed
  - [ ] Run: `bundle exec license_finder` locally to check for license issues (may show warnings — expected on first run)
  - [ ] Create commit with Angular guidelines: `feat(setup): replace diffend with supply chain security stack` followed by description of changes
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
