SOURCE: https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/CHANGELOG.md
FETCHED: 2026-07-28, via WebFetch

Relevant entries found between v2.3.0 (where use_effective_fields was
introduced) and v2.14.0 (current, latest as of fetch date):

## v2.14.0 — 2026-07-15 (latest release, confirmed via `gh api
   repos/mongodb/terraform-provider-mongodbatlas/releases/latest`:
   {"published_at":"2026-07-15T11:15:34Z","tag_name":"v2.14.0"})
   No entry found mentioning disk_size_gb, use_effective_fields, or
   "inconsistent result" for this version.

## v2.13.0 — 2026-06-30

Enhancement:
> "resource/mongodbatlas_advanced_cluster: Adds support for Gen 2 instance sizes"

Bug fix:
> "resource/mongodbatlas_advanced_cluster: Fixes inconsistent result error
> when scaling attribute changes cause Atlas to recompute oplog_size_mb"

Note: this bug fix is about `oplog_size_mb`, not `disk_size_gb`. Same general
class of provider bug ("inconsistent result" from a computed value Atlas
recomputes during auto-scaling) but a different field — not a fix for the
disk_size_gb issue in #4238.

## v2.3.0 — 2025-12-09

Enhancements:
> "data-source/mongodbatlas_advanced_cluster: Adds `use_effective_fields`,
> `effective_electable_specs`, `effective_read_only_specs` and
> `effective_analytics_specs` attributes to expose actual specifications"

> "data-source/mongodbatlas_advanced_clusters: Adds `use_effective_fields`,
> `effective_electable_specs`, `effective_read_only_specs` and
> `effective_analytics_specs` attributes"

> "resource/mongodbatlas_advanced_cluster: Adds `use_effective_fields`
> attribute to improve auto-scaling workflows, eliminating the need for
> `lifecycle.ignore_changes` blocks"

## Versions in between (2.4.0–2.12.0)

No changelog entry was found (via the fetch tool's summarization of the raw
CHANGELOG.md) mentioning disk_size_gb, use_effective_fields,
effective_electable_specs, effective_analytics_specs,
effective_read_only_specs, or "inconsistent result after apply" for any
version strictly between 2.3.0 and 2.13.0. This is a summarization-tool
result, not a line-by-line manual read of the full changelog file — treat as
indicative, not exhaustive.

=== CONCLUSION FOR Q2 ===
use_effective_fields was introduced in v2.3.0 (2025-12-09). Issue #4238 was
filed against v2.7.0 (2026-02-26), i.e. 4 minor versions after introduction.
v2.14.0 (4Shark's pinned version, confirmed the latest release as of
2026-07-15) is 7 minor versions past the issue's filing, and the issue is
still open with no changelog entry closing it. No version upgrade path was
found that resolves this specific disk_size_gb bug.
