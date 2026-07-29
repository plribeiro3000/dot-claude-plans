# SPIKE — ECR Image Lifecycle Policies

## Investigation question

4Shark's ECS migration pushes a new Docker image to ECR on every deploy, and no repository has an expiration policy — images accumulate indefinitely. This spike answers seven questions for the engineer, ahead of any decision to adopt lifecycle policies:

1. What do AWS and the community recommend as a concrete ECR retention policy?
2. How do ECR lifecycle policy rules actually evaluate (`tagStatus`, `countType`, priority order, known pitfalls)?
3. Does a lifecycle policy risk deleting an image a running ECS task or task definition still needs?
4. Should one policy apply to every repository, or should it vary by environment/application?
5. What does ECR storage actually cost 4Shark today, in `us-east-1` and `sa-east-1`?
6. What is the canonical Terraform shape for `aws_ecr_lifecycle_policy`, and can it be applied centrally across 4Shark's `ecr` module?
7. What concrete policy options exist, with tagged/untagged treated separately?

## Sources consulted

- [AWS: Automate the cleanup of images by using lifecycle policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html) — the evaluation mechanics: rule priority, `tagStatus`, `countType`, the one-`any`-rule-per-storage-class limit, manifest-list protection.
- [AWS: Examples of lifecycle policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_examples.html) — canonical rule JSON for every `countType`/`tagStatus` combination, and the multi-rule priority-freeze walkthrough. Full content preserved as `ecr-lifecycle_doc_1_aws_lifecycle_examples.md`.
- [AWS: Amazon ECR Pricing](https://aws.amazon.com/ecr/pricing/) — the official `$0.10/GB`-month storage rate and the one-year 500 MB free tier for new accounts.
- [moby/buildkit#3499](https://github.com/moby/buildkit/issues/3499) — BuildKit v0.11's default provenance attestation and the extra untagged manifests it leaves in a registry.
- [docs.docker.com: Add SBOM and provenance attestations with GitHub Actions](https://docs.docker.com/build/ci/github-actions/attestations/) — confirms provenance attestations are added automatically for a private repository at `mode=min` unless overridden.
- [oneuptime.com: How to Configure ECR Lifecycle Policies for Image Cleanup](https://oneuptime.com/blog/post/2026-02-12-ecr-lifecycle-policies-image-cleanup/view) — states plainly that lifecycle policies do not check ECS task definitions before expiring an image.
- [aws/containers-roadmap#1078 — "make image lifecycle policies ecs task aware"](https://github.com/aws/containers-roadmap/issues/1078) — the open (unimplemented) AWS feature request confirming there is no in-use/task-aware protection today.
- [aws/containers-roadmap#1036 — "Lifecycle cleanup to check if image is active for a Service"](https://github.com/aws/containers-roadmap/issues/1036) — a second, independent open request for the same missing capability.
- [HashiCorp Terraform provider docs: `aws_ecr_lifecycle_policy`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) — the resource shape (a policy JSON string attached by `repository`) and that it is a separate resource from `aws_ecr_repository`.
- [terraform-aws-modules/terraform-aws-ecr README](https://github.com/terraform-aws-modules/terraform-aws-ecr) — the community module's `repository_lifecycle_policy` / `create_lifecycle_policy` variables, and its documented `for_each` pattern for provisioning many repositories from one module block.
- `/Users/plribeiro3000/Projects/4Shark/terraform/modules/ecr/main.tf`, `variables.tf`, `README.md` — 4Shark's own shared ECR module: what it creates today, and its own documented gap.
- `/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/ecr.tf`, `app-outbound-atento-br/ecr.tf`, `integrator-redebrasil/ecr.tf` — how stacks invoke the shared module (single repo, or `for_each` over a name set).
- `/Users/plribeiro3000/Projects/4Shark/app/.github/workflows/build-image.yaml`, `integrator/.github/workflows/build.yaml`, `onboarding/.github/workflows/build.yml`, `pgbouncer/.github/workflows/build.yaml`, `simplex-harvester/.github/workflows/build.yaml`, `setup/.github/workflows/deploy.yaml` — the actual image-tagging scheme pushed by every 4Shark pipeline.
- `aws ecr describe-repositories` (both regions), `aws ecr describe-images` (7 repositories), `aws ecr get-lifecycle-policy` — read-only AWS CLI, executed 2026-07-28, default profile. Raw/derived output preserved in `ecr-lifecycle_data_1_repos_inventory.json`, `ecr-lifecycle_data_2_orphaned_repos.json`, `ecr-lifecycle_data_3_active_repo_image_stats.json`.
- AWS Cost Explorer data (`UnblendedCost` + `UsageQuantity`, monthly), supplied by the coordinating session, queried 2026-07-28 — preserved in `ecr-lifecycle_data_4_cost_explorer.md`.

## Findings

### Finding 1: No repository in the 4Shark account has a lifecycle policy today, and the shared module says so explicitly

**Evidence:**

```
# terraform/modules/ecr/README.md:69-73
## Known Limitations

- Image lifecycle policies are not managed by this module — old images must be cleaned up
  manually or via an additional `aws_ecr_lifecycle_policy` resource in the calling stack.
- Repository names must be globally unique per AWS account and region.
```

```
# terraform/modules/ecr/main.tf:1-17
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = var.force_delete

  encryption_configuration {
    encryption_type = var.kms_key_arn == null ? "AES256" : "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = var.tags
}
```

Confirmed empirically for a currently-active repository:

```
$ aws ecr get-lifecycle-policy --repository-name app --region us-east-1
An error occurred (LifecyclePolicyNotFoundException) when calling the
GetLifecyclePolicy operation: Lifecycle policy does not exist for the
repository with name 'app' in the registry with id '405749097490'
```

**Source:** `terraform/modules/ecr/README.md:69-73`, `terraform/modules/ecr/main.tf:1-17`, `aws ecr get-lifecycle-policy` output above.

**Significance:** the module that creates every 4Shark ECR repository (`app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`, `app-outbound-atento-br`, `app-outbound-maqnelson`, `integrator-redebrasil`, plus the standalone `auth`/`vpn` module invocations) has no `lifecycle_policy` resource anywhere in its definition — the gap is structural, not a per-repository oversight. The module's own README already names the fix path (`an additional aws_ecr_lifecycle_policy resource in the calling stack`), which answers part of question 6 directly.

### Finding 2: Every 4Shark pipeline tags images the same way — a version+SHA tag plus a moving `:latest`, never a bare unversioned push

**Evidence:**

```yaml
# app/.github/workflows/build-image.yaml:61-67
- name: Determine version
  run: |
    VERSION=$(grep "VERSION = " config/version.rb | cut -d"'" -f2)
    SHORT_SHA=$(git rev-parse --short=7 HEAD)
    IMAGE_TAG="${VERSION}-${SHORT_SHA}"
...
IMAGE_TAGS+="${registry}/${IMAGE_NAME}:latest"$'\n'
IMAGE_TAGS+="${registry}/${IMAGE_NAME}:${IMAGE_TAG}"$'\n'
```

The same `VERSION-SHORT_SHA` + `:latest` pair repeats verbatim in `integrator/.github/workflows/build.yaml:73-92`, `onboarding/.github/workflows/build.yml:42-61`, and `pgbouncer/.github/workflows/build.yaml` (`SHORT_SHA` only, no semantic version — pgbouncer has none). `simplex-harvester/.github/workflows/build.yaml:71-78` uses `docker/metadata-action` with `type=raw,value=latest` + `type=sha,prefix=` — the same two-tags-per-push shape by a different mechanism.

**Source:** the six workflow files listed above, read in full.

**Significance:** this answers the tagging-scheme discovery the engineer flagged as critical. Two consequences follow directly:

1. **No repository is starved of a historical tag.** Every push leaves a permanent `VERSION-SHORT_SHA` tag pointing at that image even after `:latest` moves on — a `tagStatus: tagged` rule keyed on `imageCountMoreThan` or `sinceImagePushed` has a real, non-`latest` tag to count against on every repository observed.
2. **The old digest that used to hold `:latest` does not become "untagged" through this flow** — the version+SHA tag it already carries survives the retag. Untagged images in this account come from elsewhere (Finding 3).

### Finding 3: Untagged images dominate storage, and the majority are not old releases — they are BuildKit/attestation manifest artifacts orphaned by the pipeline shape itself, not something a "keep N releases" retention policy alone would catch

**Evidence:** measured across three currently-active repositories (`aws ecr describe-images`, 2026-07-28):

| Repository | Total images | Tagged | Untagged | Untagged % |
|---|---|---|---|---|
| `shared-001-app` (us-east-1) | 364 | 82 | 282 | 77% |
| `onboarding-web` (us-east-1) | 35 | 11 | 24 | 69% |
| `integrator-atento-mx` (sa-east-1) | 88 | 23 | 65 | 74% |

Of `shared-001-app`'s 282 untagged images, 90 carry `artifactMediaType: application/vnd.buildkit.cacheconfig.v0` — the registry build-cache blobs the workflow itself pushes:

```yaml
# app/.github/workflows/build-image.yaml:99-100
cache-from: type=registry,ref=${{ env.CACHE_REGISTRY }}/${{ env.IMAGE_NAME }}:buildcache
cache-to: type=registry,ref=${{ env.CACHE_REGISTRY }}/${{ env.IMAGE_NAME }}:buildcache,mode=max
```

Every build overwrites the single mutable `:buildcache` tag with a new digest; the digest that tag pointed to previously loses its only tag and becomes untagged permanently. The remaining 192 non-buildcache untagged images track with `docker/build-push-action`'s default behavior:

> "If the GitHub repository is private, provenance attestations with `mode=min` are automatically added to the image."
> — [docs.docker.com, Add SBOM and provenance attestations with GitHub Actions](https://docs.docker.com/build/ci/github-actions/attestations/)

and the community-reported consequence of that default combined with a `docker/build-push-action`-produced OCI image index (91 of `shared-001-app`'s images carry `imageManifestMediaType: application/vnd.oci.image.index.v1+json` — an index wraps a tagged parent manifest plus one or more untagged child manifests: the platform image and, when provenance is on, an attestation manifest):

> "With the release of Buildkit v0.11, by default, a minimal provenance attestation is created and pushed alongside the image, using the attestation storage."
> — [moby/buildkit#3499](https://github.com/moby/buildkit/issues/3499)

**Source:** `aws ecr describe-images` output for `shared-001-app`/`onboarding-web`/`integrator-atento-mx` (`ecr-lifecycle_data_3_active_repo_image_stats.json`); `app/.github/workflows/build-image.yaml:99-100`; the two external sources quoted above.

**Verification:** both URLs re-fetched during this spike; the quoted substrings ("mode=min are automatically added to the image", "a minimal provenance attestation is created and pushed alongside the image") are present verbatim at the fetched pages.

**Significance:** the untagged-image problem in this account is not primarily "we forgot to prune old versions" — it is a byproduct of two things the build pipeline already does deliberately (registry-backed BuildKit cache, and BuildKit's default provenance attestation). A lifecycle rule that targets `tagStatus: untagged` on a short age window (the AWS-documented pattern — see Finding 5) clears this class specifically; a rule that only limits *tagged* image count would leave the untagged pile untouched.

### Finding 4: ECR lifecycle policy evaluation mechanics — rule priority, `tagStatus`, `countType`, and the documented pitfalls

**Evidence** (verbatim from AWS's own reference, full text preserved in `ecr-lifecycle_doc_1_aws_lifecycle_examples.md`):

> "All rules are evaluated at the same time, regardless of rule priority. After all rules are evaluated, they are then applied based on rule priority."
> "An image that matches the tagging requirements of a rule cannot be expired or archived by a rule with a lower priority."
> "Rules can never mark images that are marked by higher priority rules, but can still identify them as if they haven't been expired or archived."
> "Only one rule selecting a specific storage class is allowed to select untagged images."
> "If an image is referenced by a manifest list, it cannot be expired or archived without the manifest list being deleted or archived first."
> "A lifecycle policy rule may specify either `tagPatternList` or `tagPrefixList`, but not both."
> "The `tagPatternList` or `tagPrefixList` parameters may only [be] used if the `tagStatus` is `tagged`."
> — [AWS: Automate the cleanup of images by using lifecycle policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html)

`countType` options and what each measures, same source:

- `imageCountMoreThan` — sorts images youngest to oldest by `pushed_at_time`; everything past the count is expired/archived.
- `sinceImagePushed` — age-based, measured from `pushed_at_time`.
- `sinceImagePulled` — age since `last_recorded_pulltime` (falls back to `pushed_at_time` if never pulled); **usable only with the `transition` action, not `expire`** (confirmed in the worked example in `ecr-lifecycle_doc_1_aws_lifecycle_examples.md`, "Filtering on last pulled time").
- `sinceImageTransitioned` — age since an image entered archive storage; usable only with `expire` + `storageClass: archive`.

The documented multi-rule pitfall the engineer asked about (a rule "swallowing" a later one): AWS's own worked example shows a `beta*` rule at priority 1 consuming images that a `prod*` rule at priority 2 would otherwise have protected, purely because of ordering — swapping the two rules' priorities changes which images survive, with the same repository contents (`ecr-lifecycle_doc_1_aws_lifecycle_examples.md`, "Example A" vs "Example B").

**Source:** as quoted above; `ecr-lifecycle_doc_1_aws_lifecycle_examples.md` (full).

**Verification:** URL fetched 2026-07-28; every quoted sentence confirmed present verbatim in the fetched page content.

**Significance:** answers question 2 in full. The two operationally sharpest pitfalls for 4Shark's shape are (a) the one-`any`-tagStatus-rule-per-policy limit — a policy needs separate rules for `tagged` and `untagged`, they cannot be combined into a single `any` rule if different retention windows are wanted for each — and (b) rule-priority ordering silently changing outcomes when multiple `tagPrefixList`/`tagPatternList` rules exist, which matters if per-application prefixes are ever introduced (Finding 6).

### Finding 5: There is no AWS-native mechanism that protects an image referenced by a running ECS task or task definition — this is a known, still-open gap, not an edge case

**Evidence:**

> "ECR lifecycle policies don't check ECS task definitions before expiring images. A running task that already pulled the image can keep running, but a new task or rollback can fail to pull the image if the tag or digest was deleted."
> "If you need to roll back to an old version, make sure your retention policy keeps enough images."
> — [oneuptime.com, How to Configure ECR Lifecycle Policies for Image Cleanup](https://oneuptime.com/blog/post/2026-02-12-ecr-lifecycle-policies-image-cleanup/view)

Confirmed independently by two separate, still-open AWS feature requests asking for exactly this capability:

> Issue title: "[Ecr] [request]: make image lifecycle policies ecs task aware"
> "lifecycle policies do not take into account active ecs task definitions which may refer to tags" — "lifecycle policy today can delete tags which a production ecs services uses."
> — [aws/containers-roadmap#1078](https://github.com/aws/containers-roadmap/issues/1078)

A second, independently filed request asks for the same thing under a different title — "Lifecycle cleanup to check if image is active for a Service" ([aws/containers-roadmap#1036](https://github.com/aws/containers-roadmap/issues/1036)) — which corroborates that this is a recognized, unaddressed gap rather than one blog's opinion.

**Source:** as quoted above.

**Verification:** all three URLs fetched 2026-07-28; quoted substrings confirmed present at each.

**Significance:** answers question 3 directly. The practical failure mode for 4Shark is: an ECS task already running keeps running even after its image is deleted from ECR (the node already pulled it), but the **next** task launch that needs that same image — a scale-out event, a service restart, or a manual rollback to an older tag — fails to pull if a lifecycle policy already expired it. Because 4Shark's task definitions pin `image = ".../shared-001-app:latest"` (`app-shared-001/terraform.tfvars:44` and 10 other lines) rather than a digest, day-to-day scaling of the *current* release is not at risk — `:latest` always resolves to whatever the policy is also protecting as the newest tagged image. The risk is specific to **rollback**: if the engineer needs to redeploy an older `VERSION-SHORT_SHA` tag that a "keep last N" rule has since expired, ECS will fail to pull it, and nothing in ECR or ECS will have warned before that point.

### Finding 6: Terraform shape — `aws_ecr_lifecycle_policy` is a separate resource, attaches by `repository`, and the module can add it centrally via `for_each` without changing every calling stack

**Evidence:**

```hcl
# terraform/app-shared-001/ecr.tf:5-20 (verbatim)
locals {
  ecr_repositories = toset(["${var.environment}-app", "${var.environment}-connection-pooler"])
}

module "ecr" {
  source = "../modules/ecr"

  for_each = local.ecr_repositories

  name = each.value

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
```

The community module confirms the same `for_each`-over-one-module-block pattern is the standard way to provision many repositories with shared configuration:

> "Users of this Terraform module can create multiple similar resources by using `for_each` meta-argument within `module` block which became available in Terraform 0.13."
> — [terraform-aws-modules/terraform-aws-ecr README](https://github.com/terraform-aws-modules/terraform-aws-ecr)

and exposes lifecycle rules as a first-class variable rather than a bolt-on:

> `repository_lifecycle_policy` — "The policy document. This is a JSON formatted string."
> `create_lifecycle_policy` — "Determines whether a lifecycle policy will be created" (default `true`).
> — [terraform-aws-modules/terraform-aws-ecr README](https://github.com/terraform-aws-modules/terraform-aws-ecr)

**Source:** `terraform/app-shared-001/ecr.tf:5-20`; `terraform/app-outbound-atento-br/ecr.tf:5-14`; `terraform/integrator-redebrasil/ecr.tf`; the community module README as quoted.

**Significance:** answers question 6. Because 4Shark's `modules/ecr` already receives every repository through a single `module "ecr" { for_each = ... }` block per stack, adding an `aws_ecr_lifecycle_policy` resource **inside** `modules/ecr/main.tf` (attached to `aws_ecr_repository.this.name`) applies to every repository the module creates — `app-shared-001`, `app-atento-001`, `app-beta-001`, `app-demo-001`, `app-outbound-atento-br`, `app-outbound-maqnelson`, `integrator-redebrasil` — with zero changes to any calling stack. Repositories created **outside** the shared module (`modules/auth/ecr.tf`, `modules/vpn/ecr.tf`, which declare `aws_ecr_repository` directly rather than invoking `modules/ecr`) would need the same resource added to those two files separately, or a migration onto the shared module.

### Finding 7: The account's own current storage cost and its trajectory

**Evidence:** AWS Cost Explorer, `UnblendedCost` + `UsageQuantity`, monthly, supplied by the coordinating session and preserved in full in `ecr-lifecycle_data_4_cost_explorer.md`:

| Month | Storage total (GB-month) | Total ECR USD (incl. DataTransfer) |
|---|---|---|
| 2026-01 | 57.50 | 5.75 |
| 2026-04 | 60.37 | 9.95 |
| 2026-07 | 90.82 | 12.24 |

The official rate confirming these dollar figures:

> "$0.10 per GB" per month for private repository storage; "500 MB per month of storage for your private repositories for one year" free tier for new accounts.
> — [AWS: Amazon ECR Pricing](https://aws.amazon.com/ecr/pricing/)

**Source:** `ecr-lifecycle_data_4_cost_explorer.md`; AWS ECR pricing page as quoted.

**Significance:** the absolute dollar amount is small — roughly USD 9/month in pure storage today (~USD 108/year at the July run rate), which does not by itself make a dramatic cost-savings case. The more relevant signal is the trajectory: storage grew from 57.5 to 90.8 GB-month over six months (+58%), and `sa-east-1` — where new integrator clients land — grew from 4.1 to 18.9 GB-month (~4.6x) over the same window, tracking new-integrator onboarding rather than organic growth on existing repositories. Left unmanaged, the curve compounds with every future client. A second, separate cost is not retention-shaped at all: `DataTransfer-Out-Bytes` (image pulls) is the single largest ECR line item in several months (USD 3-6/month) and is **not** reduced by a lifecycle policy — pruning old images does not reduce how much data ECS pulls to run the current one. This must not be counted as savings from adopting a lifecycle policy.

### Finding 8: Eleven ECR repositories are fully orphaned — no pipeline pushes to them and no current Terraform stack declares them — and this is a materially different problem from image retention

**Evidence:** cross-referenced against every `.github/workflows/*.y*ml` in `app`, `integrator`, `onboarding`, `setup`, `pgbouncer` (Finding 2's tagging-scheme survey covered the full push surface — none of these push to a bare `app`, `beta-app`, `beta-web`, `demo-app001`, or any `worker_*` repository name) and against the full terraform tree (`grep -rl <name> ~/Projects/4Shark/terraform --include="*.tf" --include="*.tfvars"` returns zero matches for every name below, and the one apparent match for the literal repo name `app` resolved to `dbname = "app_demo_001"` — a substring collision, not a reference):

| Repository | Region | Last push | Image count | Reported size (GB)* |
|---|---|---|---|---|
| `app` | us-east-1 | 2026-01-09 | 10 | 4.92 |
| `beta-app` | us-east-1 | 2026-01-06 | 50 | 23.90 |
| `beta-web` | us-east-1 | 2025-12-17 | — | 9.06 |
| `demo-app001` | us-east-1 | 2025-11-14 | — | 9.57 |
| `worker_migration` | us-east-1 | 2025-12-19 | — | 1.92 |
| `worker_system` | us-east-1 | 2026-01-09 | — | 18.16 |
| `worker_user` | us-east-1 | 2026-01-09 | — | 16.72 |
| `worker_cleansing` | us-east-1 | 2025-12-19 | — | 1.92 |
| `worker_commission_white_shark` | us-east-1 | 2026-01-09 | — | 16.72 |
| `worker_commission_tiger_shark` | us-east-1 | 2026-01-09 | — | 21.87 |
| `worker-commission` | us-east-1 | 2026-01-09 | — | 19.58 |

\* Sum of `imageDetails[].imageSizeInBytes` per repository — **not deduplicated** across shared layers (ECR stores a shared layer's bytes once even when several images in a repository reference it, but each image's reported size counts that layer in full). This overstates real billed bytes and must be read as "this repo is non-trivially large and untouched", not as a literal storage bill.

Every repository's last push predates 2026-02-19, the date `app-shared-001`, `app-atento-001`, `app-beta-001`, and `app-demo-001` were created (per `ecr-lifecycle_data_1_repos_inventory.json`) — consistent with these being the pre-migration repository names, superseded by the current `<environment>-app` / `<environment>-connection-pooler` naming the build workflows push to today (Finding 2).

**Source:** `ecr-lifecycle_data_2_orphaned_repos.json`; `terraform/app-demo-001/main.tf:98` (the `app` substring collision, `dbname = "app_demo_001"`, confirmed to be the only hit and unrelated to the ECR repository).

**Significance:** this is a distinct problem from image retention. A lifecycle policy prunes old images *within* a repository that is still actively used; it does nothing for a repository nobody pushes to anymore — every image in it is permanently "old" and a recurring rule would eventually empty it, but the empty repository itself, and the roughly 144 GB (reported, undeduplicated) of dead data sitting in it today, remain until someone deletes the repository outright. The engineer separated these two axes explicitly, and the evidence supports that separation: retention is a recurring policy decision; an orphaned repository is a one-time deletion decision requiring only confirmation that nothing references it (this spike's grep against every workflow and every terraform stack is that confirmation for the eleven repositories above, not a substitute for the engineer's own judgment call before deleting).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Single account-wide lifecycle policy (same JSON on every repository) | One thing to reason about; trivial to apply via the shared `modules/ecr` module with no per-stack changes (Finding 6) | Cannot distinguish a productive environment's rollback needs from a non-productive one's; a count-based rule tuned for `shared-001-app`'s release cadence may be wrong for a low-traffic repository like `onboarding-web` | Community pattern search (Finding 1 web results) recommends splitting dev/staging/prod even though it does not force a single global policy |
| Per-environment or per-repository policy (productive vs. `beta`/`demo`) | Matches 4Shark's own existing productive/non-productive split (`shared-001`, `atento-001` vs. `beta`, `demo`) already used elsewhere (Deployment Strategy doc) | More Terraform surface to maintain — either a `for_each` over a map keyed by environment, or a `count`/conditional inside the shared module | `terraform/app-shared-001/ecr.tf` vs `terraform/app-demo-001/ecr.tf` (same module, different `for_each` set) — no obstacle to varying the lifecycle rule the same way |
| `tagStatus: untagged` short-window rule only (leave tagged images alone entirely) | Directly removes the dominant waste class measured in Finding 3 (buildcache + attestation orphans, 69-77% of image count in the three repos sampled); lowest risk — never touches a version tag a rollback might need | Does not bound the unlimited growth of *tagged* history — every release ever shipped stays forever, so storage still grows without limit over a longer horizon | `ecr-lifecycle_data_3_active_repo_image_stats.json`; AWS untagged-count-1 example (`ecr-lifecycle_doc_1_aws_lifecycle_examples.md`, "Filtering on image count") |
| `tagStatus: tagged` count-based rule (e.g. "keep last N releases") in addition to the untagged rule | Bounds both classes of growth; matches the community pattern search's "50 most recent" / "180 days" recommendation | Directly creates the rollback risk in Finding 5 if N is set too low relative to how far back the engineer might need to roll back; needs a considered N, not a copy-pasted default | Finding 5; web search result summarized in Sources |
| Age-based (`sinceImagePushed`) instead of count-based (`imageCountMoreThan`) for tagged images | Naturally expresses "a release older than the useful rollback window is gone" — matches the engineer's own framing (schema has moved on after N migrations) | A quiet repository could lose its only recent image if nothing shipped in the window; a very active repository could still balloon in count within the window | `ecr-lifecycle_doc_1_aws_lifecycle_examples.md` (`sinceImagePushed` semantics, Finding 4) |
| Delete the eleven orphaned repositories outright | Removes ~144 GB (reported, undeduplicated) of dead data in one action; no recurring policy needed for repositories nothing writes to | One-time, deliberate action outside version control (repository deletion is not reversible by a lifecycle policy) — needs the engineer's explicit go, not an automated rule; `force_delete` must be considered since these repos still hold images (`terraform/modules/ecr/variables.tf:18-22`) | Finding 8; `terraform/modules/ecr/variables.tf:18-22` |

## What remains uncertain

- **Archive storage-class pricing was not found.** The AWS pricing page confirms the `$0.10/GB` standard rate and the archive *mechanism* is documented in the lifecycle-policy reference (`storageClass: archive`, 90-day minimum retention before deletion), but the fetched pricing page did not show a distinct GB-month rate for archived images. Whether `transition` to archive is cheaper than `expire`-and-lose-the-image-entirely was not confirmed and should not be assumed.
- **`beta-app`'s 1 untagged image and `app`'s 9-of-10 untagged images** (both orphaned repositories, Finding 8) were not further decomposed the way `shared-001-app` was — whether they follow the same buildcache/attestation pattern or something else (these repos predate the current `cache-to: type=registry` shape in some workflows) is not established, and is moot given Finding 8's recommendation path (delete, not tune a lifecycle rule).
- **Whether any currently-running ECS task or scheduled task actually points at an older `VERSION-SHORT_SHA` tag** (as opposed to `:latest`) was not checked against live task definitions in this spike — Finding 5's rollback-risk framing is based on the tagging scheme and the documented AWS gap, not a live audit of every running task definition's `image` field.
- **The `modules/auth/ecr.tf` and `modules/vpn/ecr.tf` repositories** (`auth-001`, `auth-001-staging`, `vpn`, `vpn-staging`) declare `aws_ecr_repository` directly rather than through the shared `modules/ecr`, so a lifecycle policy added inside `modules/ecr/main.tf` would not reach them automatically — this was identified (Finding 6) but not sized (how many images/how much storage these four repositories hold was not measured).

## Suggested options for main and the engineer

- **Option A — untagged-only, account-wide, via the shared module.** Add a single `tagStatus: untagged` / `sinceImagePushed` / short-window `expire` rule inside `modules/ecr/main.tf`, reaching every repository the module creates with no per-stack changes. Lowest risk (never touches a tagged release), addresses the largest measured waste class (Finding 3), leaves the "how many releases to keep" question for a later, separate decision.
- **Option B — untagged + tagged, differentiated by environment.** Same untagged rule as Option A, plus a `tagStatus: tagged` count- or age-based rule whose `countNumber` differs for productive (`shared-001`, `atento-001`) vs. non-productive (`beta`, `demo`) environments — requires the lifecycle policy to be parameterized per `for_each` key rather than hardcoded once inside the module.
- **Option C — untagged + tagged, single account-wide number.** Simplest to reason about and to apply; does not distinguish productive rollback needs from non-productive ones, so the single `countNumber`/age window has to be conservative enough to cover the environment with the longest realistic rollback horizon.
- **Option D — orphaned-repository cleanup, decided and executed separately from A/B/C.** Confirm (beyond this spike's grep) that the eleven repositories in Finding 8 are safe to delete, then delete them as a one-time action — independent of whichever lifecycle-policy option is chosen, since it addresses dead repositories rather than image retention within a live one.

(No recommendation — the trade-offs above and the rollback-risk framing in Finding 5 are the inputs; main and the engineer choose.)

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`ecr-lifecycle_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
