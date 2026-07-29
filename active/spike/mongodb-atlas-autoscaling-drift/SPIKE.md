# SPIKE — MongoDB Atlas Terraform Provider: `use_effective_fields` / `disk_size_gb` Inconsistency Bug and the Path to Zero Perpetual Drift on Auto-Scaled Clusters

## Investigation question

1. Is there a known issue in `mongodb/terraform-provider-mongodbatlas` matching "Provider produced inconsistent result after apply" with `disk_size_gb` going `null` when `use_effective_fields = true` is combined with disk auto-scaling? Open or fixed, and in which version?
2. What is the latest provider version, what changed between 2.14.0 and it regarding `use_effective_fields` / auto-scaling / `effective_*_specs`, and does upgrading fix the bug?
3. What is the correct adoption path for `use_effective_fields` on an existing, already-scaled cluster that also has disk auto-scaling enabled?
4. Should `disk_size_gb` be declared at all when `disk_gb_enabled = true`? Is this configuration self-contradictory regardless of `use_effective_fields`?
5. What alternatives does the community use for zero drift on an auto-scaled Atlas cluster, and what are the trade-offs?
6. How does the `app-atento-001` stack get out of its current state (flag on, pending `disk_size_gb` diff, apply that previously failed) without landing on perpetual drift?

## Sources consulted

- [github.com/mongodb/terraform-provider-mongodbatlas issue #4238](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/4238) — open bug, same error shape as the 4Shark failure, maintainer-confirmed workaround. See auxiliary: `mongodb-atlas_issue_4238.txt`
- [github.com/mongodb/terraform-provider-mongodbatlas issue #888](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/888) — why `lifecycle.ignore_changes` cannot target `replication_specs` granularly. See auxiliary: `mongodb-atlas_issue_677_888.txt`
- [github.com/mongodb/terraform-provider-mongodbatlas issue #677](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/677) — historical evidence that `disk_gb_enabled = false` has not reliably taken effect at the Atlas API level. See auxiliary: `mongodb-atlas_issue_677_888.txt`
- `gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest` — confirms v2.14.0, published 2026-07-15T11:15:34Z, is the current latest release (4Shark is already on it)
- [raw.githubusercontent.com .../docs/resources/advanced_cluster.md](https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/docs/resources/advanced_cluster.md) — `use_effective_fields` behavior and adoption guidance. See auxiliary: `mongodb-atlas_doc_use-effective-fields.md`
- [raw.githubusercontent.com .../CHANGELOG.md](https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/CHANGELOG.md) — version history for `use_effective_fields` and related fixes. See auxiliary: `mongodb-atlas_changelog_excerpt.md`
- `~/Projects/4Shark/terraform/modules/mongodb_atlas/main.tf` (develop, no `use_effective_fields`) and `~/Projects/4Shark/terraform/.claude/worktrees/atlas-autoscaling/modules/mongodb_atlas/main.tf` (feature branch, with the flag) — current and proposed module code
- `~/Projects/4Shark/terraform/app-shared-001/mongodb.tf`, `~/Projects/4Shark/terraform/app-atento-001/mongodb.tf` — the two stacks' module invocations
- `gh -R 4shark/terraform pr view 862` — the open PR that already carries the `use_effective_fields` adoption for the module and for `app-shared-001`, including the engineer's own decision log

## Findings

### Finding 1: An open upstream bug matches the exact failure shape, maintainer-confirmed

**Evidence:** Issue #4238, filed 2026-02-26 against provider v2.7.0, title "[Bug]: produced an unexpected new value", state `open`, label `not_stale`, 3 comments (verified via `gh api repos/mongodb/terraform-provider-mongodbatlas/issues/4238`: `{"comments":3,"created_at":"2026-02-26T09:41:24Z","labels":["not_stale"],"number":4238,"state":"open","title":"[Bug]: produced an unexpected new value","updated_at":"2026-02-27T11:43:00Z"}`).

The reported error:
> "was cty.NumberIntVal(2048), but now null."

on `.replication_specs[0].region_configs[0].analytics_specs.disk_size_gb`, after enabling `use_effective_fields = true` on a cluster with `analytics_specs.disk_size_gb = 2048` and auto-scaling on.

MongoDB maintainer `AgustinBettati` reproduced it and confirmed, verbatim (comment fetched via `gh api repos/mongodb/terraform-provider-mongodbatlas/issues/4238/comments`):
> "I was able to reproduce the `inconsistent result after apply` error by creating the configuration you shared and then doing a follow-up apply that enables use_effective_fields. I can also confirm that your workaround of removing `analytics_specs.disk_size_gb` successfully allows Terraform to reach an empty plan. We have identified an inconsistent behavior in the upstream API that is causing this. We are looking into it and will get back to you here as soon as we have an update."

**Source:** [github.com/mongodb/terraform-provider-mongodbatlas/issues/4238](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/4238); metadata and comments confirmed via `gh api`; full raw text in `mongodb-atlas_issue_4238.txt`.

**Significance:** The `app-atento-001` failure (`electable_specs.disk_size_gb: was cty.NumberIntVal(79), but now null`) is the same field pattern on a different spec block (`electable_specs` vs. `analytics_specs`) under the same trigger condition — `use_effective_fields = true` plus a declared `disk_size_gb` value on a spec whose disk auto-scaling is on. The maintainer confirmed this as "an inconsistent behavior in the upstream API," not a Terraform-config mistake, and confirmed a specific workaround: removing the `disk_size_gb` attribute from the affected spec, not merely enabling the flag.

**Verification:** URL fetched (`gh api` + WebFetch) / Verbatim quote checked / Quote substring confirmed via `gh api repos/mongodb/terraform-provider-mongodbatlas/issues/4238/comments` direct JSON output.

### Finding 2: v2.14.0 (4Shark's pinned version) is the current latest release — no newer version exists to upgrade to

**Evidence:**
```
$ gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest --jq '{tag_name, published_at}'
{"published_at":"2026-07-15T11:15:34Z","tag_name":"v2.14.0"}
```

**Source:** `gh api repos/mongodb/terraform-provider-mongodbatlas/releases/latest`, run directly against the GitHub API (2026-07-28).

**Significance:** This directly answers Question 2's "does upgrading fix the bug?" — there is no newer provider version available; 4Shark is already running the latest release. Whatever remediation is chosen, it cannot rely on a version bump, because none exists past 2.14.0.

**Verification:** URL fetched (GitHub REST API) / Verbatim quote checked / Quote substring confirmed at the `gh api` command's own JSON output above.

### Finding 3: No changelog entry between 2.3.0 and 2.14.0 closes the `disk_size_gb` inconsistency; a related-but-different `oplog_size_mb` bug WAS fixed in 2.13.0

**Evidence:**
> "resource/mongodbatlas_advanced_cluster: Fixes inconsistent result error when scaling attribute changes cause Atlas to recompute oplog_size_mb" — v2.13.0, 2026-06-30

> "resource/mongodbatlas_advanced_cluster: Adds `use_effective_fields` attribute to improve auto-scaling workflows, eliminating the need for `lifecycle.ignore_changes` blocks" — v2.3.0, 2025-12-09

**Source:** [raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/CHANGELOG.md](https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/CHANGELOG.md); full excerpt in `mongodb-atlas_changelog_excerpt.md`.

**Significance:** The provider has fixed at least one instance of this general bug class (an auto-scaling-recomputed field going inconsistent after `use_effective_fields` is enabled) — for `oplog_size_mb`, in v2.13.0, which 4Shark's pinned v2.14.0 already includes. But no changelog entry was found closing the equivalent bug for `disk_size_gb`. This shows the provider team has fixed this bug *shape* before for a different field, which is evidence the underlying mechanism is understood and fixable, but it does not mean `disk_size_gb` has received the same fix.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed at the raw CHANGELOG.md fetch output quoted above and in the auxiliary file.

### Finding 4: 4Shark's module declares a fixed `disk_size_gb` inside `electable_specs` even where disk auto-scaling is on — the exact shape the upstream bug requires to trigger

**Evidence:**
```
# modules/mongodb_atlas/main.tf:28-34 (develop branch, before the fix)
electable_specs = {
  instance_size   = var.cluster_tier
  node_count      = 3
  disk_size_gb    = var.disk_size_gb
  disk_iops       = 3000
  ebs_volume_type = "STANDARD"
}
```
```
# variables.tf:80-84
variable "auto_scaling_disk_gb_enabled" {
  description = "Enable disk auto-scaling"
  type        = bool
  default     = true
}
```

**Source:** `~/Projects/4Shark/terraform/modules/mongodb_atlas/main.tf:28-34`, `~/Projects/4Shark/terraform/modules/mongodb_atlas/variables.tf:80-84`.

**Significance:** `analytics_specs` (`main.tf:36-41`) and `read_only_specs` (`main.tf:43-48`) do NOT declare `disk_size_gb` at all in this module — only `electable_specs` does. Disk auto-scaling defaults to enabled (`true`) for every cluster this module creates. This is precisely the combination the provider's own documentation says triggers field-ignoring behavior under `use_effective_fields` (Finding 5) and precisely the combination issue #4238 shows crashing on apply (Finding 1) — a concrete `disk_size_gb` value declared on a spec whose disk auto-scaling is on, with the flag enabled.

**Verification:** File read directly / Line numbers and content confirmed against the current repository state (2026-07-28).

### Finding 5: The provider's own documentation says `disk_size_gb` is "ignored" under auto-scaling + the flag — but does not yet instruct removing it, and the two statements are in tension

**Evidence:**
> "When either compute or disk auto-scaling is enabled (or both), all three fields (`instance_size`, `disk_size_gb`, and `disk_iops`) are ignored in the Terraform configuration, as Atlas may adjust any of these resources to maintain optimal cluster performance."

**Source:** [raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/docs/resources/advanced_cluster.md](https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/docs/resources/advanced_cluster.md); full excerpt in `mongodb-atlas_doc_use-effective-fields.md`.

**Significance:** The doc's word "ignored" describes plan-time diffing (Terraform does not compare the declared value against the live one when deciding whether to show a change) — it does not describe what happens during the provider's post-apply consistency check, which is exactly where issue #4238 and the `app-atento-001` failure occur. The documentation was not found to instruct removing `disk_size_gb` from the config when disk auto-scaling is on; the maintainer's confirmed fix on #4238 (Finding 1) is to remove it. The doc text and the issue-tracker-confirmed workaround are not yet aligned.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed in the raw markdown fetch output (auxiliary file).

### Finding 6: `lifecycle.ignore_changes` cannot target individual spec attributes — only the whole `replication_specs` block

**Evidence:**
> "Block type 'replication_specs' is represented by a set of objects, and set elements do not have addressable keys."

**Source:** [github.com/mongodb/terraform-provider-mongodbatlas/issues/888](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/888); full excerpt in `mongodb-atlas_issue_677_888.txt`.

**Significance:** This is a Terraform-core limitation (the issue references `hashicorp/terraform#26359`), not something the provider can work around. A `lifecycle.ignore_changes = [replication_specs]` would have to ignore the ENTIRE `replication_specs` block — instance size, disk size, node counts, region config, everything — or nothing. There is no granular `ignore_changes` path that freezes only `instance_size`/`disk_size_gb` while still tracking node counts or region priority.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed in the fetched issue body (auxiliary file).

### Finding 7: Disabling disk auto-scaling via Terraform has a documented history of not reliably taking effect at the Atlas API level

**Evidence:**
> "As per the repro, this seems to be underlying API issue and not related to Terraform provider. I have filed an internal ticket to address this."
> "Closing as not a Terraform issue."

**Source:** [github.com/mongodb/terraform-provider-mongodbatlas/issues/677](https://github.com/mongodb/terraform-provider-mongodbatlas/issues/677) (2022, closed `completed`); full text in `mongodb-atlas_issue_677_888.txt`.

**Significance:** This issue is old (2022) and was closed as out of scope for the provider (deferred to an internal Atlas API ticket, `HELP-31579`, with no public confirmation the underlying API behavior was ever fixed). It is not proof that disabling `disk_gb_enabled` is broken today, but it is documented precedent that `disk_gb_enabled = false` has, at least once, failed to take effect at the API layer regardless of what Terraform declared — relevant caution for the "disable auto-scaling, manage size in code" alternative in the trade-offs table below.

**Verification:** URL fetched / Verbatim quote checked / Quote substring confirmed via `gh api repos/mongodb/terraform-provider-mongodbatlas/issues/677/comments`.

### Finding 8: 4Shark already has an open PR implementing `use_effective_fields`, and its own decision log confirms the two-step adoption path (align `cluster_tier` first, flag second) for the compute dimension

**Evidence:**
```
# modules/mongodb_atlas/main.tf:21-38 (feature/mongodb-autoscaling-drift, PR #862)
resource "mongodbatlas_advanced_cluster" "this" {
  ...
  use_effective_fields = true
  ...
```
PR #862 decision log (`gh -R 4shark/terraform pr view 862`), verbatim:
> "The declared tier on the one stack whose cluster is currently scaled up was aligned to the size it is actually running. Toggling the flag alone was measured first and was NOT safe: the flag only governs how Terraform reads the value from that point on, so the same apply set the flag *and* reverted the size, both visible in one diff. Aligning the declared value first makes the adoption a no-op on the running nodes."

**Source:** `~/Projects/4Shark/terraform/.claude/worktrees/atlas-autoscaling/modules/mongodb_atlas/main.tf:21-38`; PR #862, https://github.com/4shark/terraform/pull/862 (state: OPEN).

**Significance:** This confirms, from 4Shark's own measured attempt, the same sequencing risk described in the investigation prompt (aligning `cluster_tier` to the live-scaled size before toggling the flag, to avoid a same-diff scale-down). The PR's diff touches only `modules/mongodb_atlas/main.tf` (adds the flag) and `app-shared-001/mongodb.tf` (bumps `cluster_tier` from M10 to M20). It does **not** touch `app-atento-001/mongodb.tf` — the stack B failure is not yet addressed in this PR; `disk_size_gb = 79` remains declared in `app-atento-001/mongodb.tf:8` and in `electable_specs` in the module, unchanged.

**Verification:** File read directly (feature branch) / `gh -R 4shark/terraform pr view 862 --json title,body,url,commits` output confirmed the quoted decision text verbatim.

### Finding 9: The `app-atento-001` post-failure state matches Terraform's documented behavior for a provider-inconsistency error — state is written with the provider's (null) response, not rolled back

**Evidence:** The investigation prompt's own observed facts: after the failed apply, `use_effective_fields` no longer shows as pending in `plan` (i.e., it "stuck"), while the plan now wants to write `disk_size_gb = 79` back into `electable_specs` (i.e., the state currently holds `null` for that field).

**Source:** Engineer-reported plan/apply output in the investigation prompt; not independently re-verified because no terraform command was run per the read-only constraint. No external citation available for this specific behavior beyond the general shape of a "produced inconsistent result after apply" error described in Finding 1's reproduction, where the error surfaces after the underlying API call is confirmed to have already succeeded.

**Significance:** This is consistent with — not proof of — Terraform's general handling of this error class: the update call to Atlas succeeded, the flag change was persisted, but the specific `disk_size_gb` value the provider returned did not match what was planned, and the mismatch was raised as a hard error rather than silently reconciled. Re-running `apply` unchanged is expected to hit the same crash again, because the config still declares the same conflicting `disk_size_gb = 79`, which is exactly the trigger issue #4238's maintainer reproduced and confirmed.

**Verification:** Not found: an authoritative external doc/issue describing Terraform's exact state-write behavior on a "produced inconsistent result after apply" error for this provider specifically. This finding is inference from the reported symptoms plus Finding 1's reproduction, and is flagged as such rather than asserted as sourced fact.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| `use_effective_fields = true`, keep `disk_size_gb` declared in `electable_specs` (current `app-atento-001` state) | Matches the provider's documented "recommended" path; already adopted successfully for compute drift on `app-shared-001` | Hits the open, maintainer-confirmed bug (#4238) whenever disk auto-scaling is on and a concrete `disk_size_gb` is declared on the affected spec; produces the exact apply failure already seen, and a straight re-apply is expected to repeat it | Findings 1, 4, 5 |
| `use_effective_fields = true`, remove `disk_size_gb` from the spec(s) where disk auto-scaling is enabled | This is the maintainer-confirmed, reproduced fix for the identical error shape (comment on #4238); the documented "ignored" language is consistent with the field being genuinely unnecessary at that point | Diverges from the resource doc's example configuration, which does not (yet) instruct this removal; unclear whether `disk_size_gb` can be safely omitted at CLUSTER-CREATION time for a brand-new cluster (not just an existing one) — not verified in this spike | Findings 1, 5, 8 |
| `lifecycle.ignore_changes` on the affected spec fields (no `use_effective_fields`) | Does not depend on the buggy new code path; simple, well-understood Terraform primitive | Cannot target individual attributes inside `replication_specs` (it is a Terraform set block) — the only granularity available is the WHOLE `replication_specs` block, which would also freeze node counts and region config; the provider documents `use_effective_fields` as superseding this approach | Finding 6; provider doc (`mongodb-atlas_doc_use-effective-fields.md`) |
| Disable disk auto-scaling (`disk_gb_enabled = false`), manage `disk_size_gb` entirely in code | Removes the auto-scaling/declared-value conflict at its root — no computed value fighting a declared one | Historical precedent (2022, issue #677) that `disk_gb_enabled = false` has not reliably taken effect at the Atlas API layer even when Terraform's plan shows the change; a manual code-driven resize process replaces an automatic one, shifting operational burden; does not by itself resolve the still-open compute-auto-scaling drift this investigation started from | Finding 7 |
| Do not manage the cluster's spec block via Terraform (import/manage everything else, leave sizing fully external) | Structurally removes any Terraform vs. Atlas-autoscaler conflict | Large deviation from 4Shark's existing all-Terraform infrastructure model; not evaluated in depth in this spike (no source consulted specifically proposes or documents this path for `mongodbatlas_advanced_cluster`) | Not found: a specific community source recommending this for `mongodbatlas_advanced_cluster` |

## What remains uncertain

- Whether `disk_size_gb` can be safely omitted entirely from `electable_specs` on a BRAND-NEW cluster creation (as opposed to an already-existing cluster like `app-atento-001` where the value is already at the desired size in Atlas) — the maintainer's confirmed workaround on #4238 was demonstrated on an existing resource via a follow-up apply, not verified here for initial `create`.
- Whether the "Standard IOPS" warning in the provider doc (`mongodb-atlas_doc_use-effective-fields.md`) — "Using `disk_size_gb` with Standard IOPS could lead to errors and configuration issues" — has any causal relationship to the `use_effective_fields` inconsistency bug, or is an unrelated, separately-documented caution. 4Shark's specs use `ebs_volume_type = "STANDARD"` throughout (`main.tf:33,40,47`). No source tying the two together was found.
- Whether re-running `terraform apply` on `app-atento-001` in its CURRENT state (flag persisted true, `disk_size_gb` state-null, config still declaring 79) would reproduce the exact same crash, versus some other outcome — this spike did not run any terraform command (per the read-only constraint) and no external source documents this exact re-apply scenario.
- Whether MongoDB has since posted an update on issue #4238 beyond the 2026-02-27 comment captured here; the issue was last observed `updated_at: 2026-02-27T11:43:00Z` at fetch time, but `not_stale` activity (bot-driven) could mask silent lack of progress.
- Whether the internal Atlas API ticket referenced in #677 (`HELP-31579`, filed 2022) or the internal ticket referenced in #4238 (`CLOUDP-384558`, filed 2026-02-26) have any linked public resolution — neither ticket ID is browsable outside MongoDB's internal Jira.
- Full CHANGELOG.md coverage between v2.4.0 and v2.12.0 was obtained via a fetch-tool summarization rather than a manual line-by-line read of the raw file end to end; treat the "no entry found" conclusion in Finding 3 as indicative, not exhaustive of every line in that range.

## Suggested options for main and the engineer

- **Option A** — Remove `disk_size_gb` from `electable_specs` in the shared module (at minimum conditionally, when `auto_scaling_disk_gb_enabled` is true), matching the maintainer-confirmed workaround on issue #4238, then re-apply `app-atento-001` from its current stuck state.
- **Option B** — Keep `disk_size_gb` declared as-is, and instead pin the provider to see if a `-replace`/state-surgery recovery avoids re-triggering the crash without a code change — contingent on resolving the "what remains uncertain" item about re-apply behavior in the current state, which this spike could not verify without running terraform.
- **Option C** — Abandon `use_effective_fields` for the disk dimension specifically (keep it for compute, given `app-shared-001`'s working adoption), and instead disable disk auto-scaling on `app-atento-001`, managing `disk_size_gb` as a plain declared value going forward — carrying the Finding 7 caution that `disk_gb_enabled = false` has a documented history of not reliably taking effect at the API layer.
- **Option D** — File/track the issue with MongoDB directly (a `+1` or updated repro on #4238) while choosing an interim workaround from A–C, since no version upgrade path exists (Finding 2) and no committed fix date was found.

(NO recommendation — surface options, let main and the engineer choose)

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`mongodb-atlas-autoscaling-drift_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
