SOURCE: https://raw.githubusercontent.com/mongodb/terraform-provider-mongodbatlas/master/docs/resources/advanced_cluster.md
FETCHED: 2026-07-28, via WebFetch (raw markdown)

Excerpts quoted verbatim, grouped by topic, as returned by the fetch.

## What use_effective_fields changes

> "the non-effective specs (`electable_specs`, `read_only_specs`, `analytics_specs`)
> fields return the hardware specifications that the client provided. When set
> to false (default), the non-effective specs fields show the **current**
> hardware specifications."

> "When auto-scaling is enabled, there are two approaches to manage your
> cluster configuration with Terraform: Option 1 (Recommended): Use
> `use_effective_fields = true` to enable the new effective fields behavior.
> With this option, Atlas-managed auto-scaling changes won't cause plan
> drift..."

> "When either compute or disk auto-scaling is enabled (or both), all three
> fields (`instance_size`, `disk_size_gb`, and `disk_iops`) are ignored in the
> Terraform configuration, as Atlas may adjust any of these resources to
> maintain optimal cluster performance."

The provider then makes actual values accessible through "the
`effective_electable_specs` and `effective_read_only_specs` attributes in the
`mongodbatlas_advanced_cluster` data source."

## Adoption on an existing cluster with lifecycle.ignore_changes

> "Important: Toggle this flag and remove any existing `lifecycle.ignore_changes`
> blocks for spec fields in the same apply, without combining other changes."

> "The recommendation is to toggle the flag and remove any existing
> `lifecycle.ignore_changes` blocks in the same apply, without combining other
> changes."

## Previously-removed read_only_specs / analytics_specs

> "If you previously removed `read_only_specs` or `analytics_specs` attributes
> from your configuration, you'll get a validation error for safety reasons to
> prevent accidental node loss. To resolve: add the blocks back (to keep
> nodes) or with `node_count = 0` (to delete nodes)..."

Explicit statement found in the fetch: "There is no statement requiring
disk_size_gb removal when disk_gb_enabled=true" — i.e. as of this fetch, the
resource doc text itself does NOT instruct the reader to remove disk_size_gb
from the specs when disk auto-scaling is on. (Contrast with the maintainer's
issue-tracker comment on #4238, which DOES confirm removal as the working
fix — see mongodb-atlas_issue_4238.txt. The doc and the confirmed workaround
are not yet in sync.)

## Migration/adoption recommendation

> "**Migration recommendation:** Adopt `use_effective_fields = true` in v2.x
> to prepare for the v3.x transition and benefit from improved auto-scaling
> workflows immediately. The recommendation is to toggle the flag and remove
> any existing `lifecycle.ignore_changes` blocks in the same apply, without
> combining other changes."

## Standard IOPS warning (separately fetched, same document)

> "Using `disk_size_gb` with Standard IOPS could lead to errors and
> configuration issues. Therefore, it should be used only with the
> Provisioned IOPS volume type."

This appears in the disk_size_gb parameter description for electable_specs /
analytics_specs / read_only_specs. It is a general warning about combining a
declared disk_size_gb with STANDARD (gp3) volumes on AWS, rather than a
statement specific to the use_effective_fields bug. 4Shark's module declares
`ebs_volume_type = "STANDARD"` on all three specs blocks
(modules/mongodb_atlas/main.tf:33,40,47 on develop /
modules/mongodb_atlas/main.tf:52,59,66 on feature/mongodb-autoscaling-drift).
No direct evidence was found tying this warning to the specific
"inconsistent result after apply" crash — it is recorded here as a
tangential, separately-documented caution on the same attribute.
