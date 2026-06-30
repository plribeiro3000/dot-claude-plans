# ANALYSIS — Integration-Debug S3 Standardization

## Context & decision

Standardize every integration-debug S3 artifact under a single parent prefix `integration-debug/`, with two subfolders by nature and retention:

- `integration-debug/audits/` — output of the `integration_audit:*` rake tasks (app + integrator). **30-day** lifecycle. PII (names, e-mail, CPF, hierarchy) — bounded retention per LGPD storage-limitation; reconciliation accountability lives in the consolidated report, not the raw dump.
- `integration-debug/scripts/` — high-volume migration staging uploads (the Phase-2 inputs the rake reads from S3). **7-day** lifecycle. Truly transient.

This reverses the prior `SKILL.md` stance that audit CSVs are kept forever ("Never delete"). Rationale: indefinite retention of client PII violates LGPD storage-limitation; the snapshots are regenerable.

Subfolder names (`audits/`, `scripts/`) and "all 43 rakes vs only User-flow" are OPEN — see § Open decisions.

## Current state (survey)

### terraform (`~/Projects/4Shark/terraform`)
- All app/integrator buckets come from `modules/s3_bucket`. No lifecycle existed before; versioning is ON by default.
- 9 stacks source the module; `integrator-atento` instantiates it 7× (per-country/staging), `integrator-commcenter` 2× → 16 bucket instances total.
- **PR #538 (open)** added one rule: filter `integration-debug/migrations/` → 7d. Plans run clean (16 add, 0 change, 0 destroy) but are now STALE — the prefix/structure changed under this decision. Do NOT apply #538 as-is.
- CloudTrail bucket (`audit/cloudtrail.tf`) is created outside the module — out of scope, never expire.

### app (`~/Projects/4Shark/app`)
- **15** rake files under `lib/tasks/integration_audit/*.rake`. Each writes `file_path = "integration-audit/#{company_id}/<resource>/#{timestamp}.csv"` (uniform, ~line 17).
- No `integration-audit/` references outside `lib/tasks` (no consumers hardcode the prefix).

### integrator (`~/Projects/4Shark/integrator`)
- **28** rake files under `lib/tasks/integration_audit/{mongo,normalized}/*.rake`. Each writes `file_path = "integration-audit/{mongo|normalized}/<resource>/#{timestamp}.csv"` (uniform, ~line 15/22). Same count on `origin/master` and `develop`.
- **Deployed code is on `master`; `develop` has not been released and won't be now.** Integrator change MUST go via HOTFIX on master, then master→develop reconciliation (develop diverged significantly).
- No `integration-audit/` references outside `lib/tasks`.

### dot-claude (`~/Projects/4Shark/dot-claude`)
- `skills/integration-debug/SKILL.md` — prefix references at lines 84, 111, 295 (audit "keep forever"), 296 (migration prefix + lifecycle), 383-385 (app audit S3 paths), 421-422 (integrator audit S3 paths).
- `docs/SCRIPT-DISCIPLINE.md:126` — migration prefix in the retention rule.
- `CLAUDE.md` § Output Policy — S3-destination examples use `integration-debug/migrations/`.
- Snapshot scripts (`integration-audit-snapshot-{fargate,ec2}.sh`, `ecs-runner-profile.sh`) parse the `s3://` URI from rake stdout — they do NOT hardcode the prefix, so no path change needed. Their filenames contain "integration-audit" (cosmetic only).

## Impact map / work breakdown

| # | Repo | Change | Branch type | PRs |
|---|---|---|---|---|
| 1 | terraform | ✅ DONE — module has 2 rules (`scripts/` 7d + `audits/` 30d). PR #538 merged; all 9 stacks (16 bucket instances) applied. The `integrator-atento` VPN-destroy was transient drift, self-resolved before its apply. | amend PR #538 (feature) | 1 |
| 2 | app | ✅ DONE — PR #5176 merged (15 rake `file_path` prefixes repointed to `integration-debug/audits/`). | feature | 1 |
| 3 | integrator | ✅ DONE — PR #2253 admin-merged to master (Bundler Audit bypass: 32 pre-existing master CVEs, unrelated); `git hf hotfix finish 8.4.15` tagged 8.4.15 + back-merged to develop. Back-merge conflict resolved: develop's 28 rakes now on `integration-debug/audits/` with develop's own logic (`source.connect!`) preserved; CHANGELOG merged ([Unreleased] kept + [8.4.15] dated). version.rb bumped 8.4.12→8.4.15. | hotfix + reconciliation | 2 |
| 4 | dot-claude | ✅ DONE — PR #286 merged. SKILL.md + SCRIPT-DISCIPLINE.md aligned: `migrations/`→`scripts/`, `integration-audit/`→`integration-debug/audits/`, audit retention "keep forever"→30d lifecycle, SCRIPT-DISCIPLINE rule 2 now describes both tiers (`scripts/` 7d + `audits/` 30d). CLAUDE.md Output Policy needed no change (S3 rule is generic). | feature | 1 |

Migration staging prefix also moves `integration-debug/migrations/` → `integration-debug/scripts/` (terraform filter + SKILL/docs + the upload-command example).

## Sequencing (proposed)

1. **terraform** first (#538 amended) — the lifecycle must exist before the rakes start writing to the new prefixes, so artifacts are covered on arrival. Apply 9 stacks (apply-before-merge), then merge.
2. **app** rakes (feature) — switch to `integration-debug/audits/`.
3. **integrator** rakes — HOTFIX on master, apply/deploy, then reconcile master→develop so the next develop release lands clean (no rework).
4. **dot-claude** — docs/skill updated last (or alongside) to reflect the final prefixes + retention.

## Resolved decisions

1. **Subfolder names** — `integration-debug/audits/` + `integration-debug/scripts/`. (Engineer accepted the "scripts/" naming for the migration staging area.)
2. **Scope of the rake repoint** — ALL 43 audit rakes (15 app + 28 integrator), full standardization.
3. **Retention** — `audits/` 30d, `scripts/` 7d.
4. **Snapshot script rename** — NO. Leave `integration-audit-snapshot-*.sh` as-is (cosmetic; renaming churns SKILL refs + allow-list for no functional gain).
5. **Legacy objects** — ✅ DONE. After app (release 3.43.0, 4 envs) + integrator (8.4.15, 12 deploys) were live on the new prefix, list-before-delete found legacy `integration-audit/` in 6 of 16 buckets (atento-001 ×46, shared-001 ×6, integrator-atento-cl ×25, -atento-co ×5, -atento-mx ×8, -commcenter ×12 = **102 objects**). Deleted all 102 via `aws s3 rm --recursive --profile 4shark-mfa`; re-list confirmed all 6 prefixes empty. The other 10 buckets had none.

## Effort complete

All five steps done. Integration-debug S3 artifacts are standardized under `integration-debug/` (`scripts/` 7d + `audits/` 30d), every producer (terraform lifecycle, 15 app rakes, 28 integrator rakes) points at the new prefixes and is deployed to production, the docs/skill are aligned, and the legacy `integration-audit/` PII is purged. Side-deliverable: HubFlow finish recovery + non-interactive tag lessons documented (PR #285).

## Risks

- **Mixed-prefix window**: until the rakes deploy, old runs still land in `integration-audit/` (no lifecycle → no expiry). Existing `integration-audit/` objects are NOT auto-migrated; decide whether to leave them (no lifecycle) or add a one-off expiry/move for the legacy prefix.
- **Integrator develop reconciliation** — develop diverged; the hotfix prefix change must be re-applied cleanly so the eventual develop release carries it without rework.
- **Apply-before-merge across 9 stacks** — each apply needs MFA + explicit approval.
