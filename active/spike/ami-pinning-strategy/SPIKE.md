# SPIKE — AMI Pinning Strategy for 4Shark Terraform

**Status:** Draft — research phase
**Author context:** triggered after recurring AMI drift across `app-*` stacks (capacity providers) and `integrator-atento` (SQL Server EC2 forced replacement). Engineer constraint: small team, no dedicated ops, weekly AWS AMI releases are unacceptable as auto-apply triggers.

---

## 1. Question

> How does 4Shark pin AMI versions in Terraform so that `terraform plan` stops reporting drift every time AWS publishes a new AMI, while keeping a controlled, periodic upgrade process?

Two concrete scenarios to solve:

- **(A) Capacity providers in `app-*` stacks** — 9 launch templates per stack, `image_id` from `data.aws_ami.ecs_optimized` with `most_recent = true`. Every AWS ECS-optimized AL2023 release (every few days) → 18-resource in-place plan in each of the 5 app stacks.
- **(B) `integrator-atento` SQL Server EC2** — `aws_instance.sqlserver_simplex` with `ami = data.aws_ami.ubuntu_2204.id`, `most_recent = true`. New Ubuntu jammy publish → `# forces replacement` on the instance (destroy + create). Cannot apply without downtime.

---

## 2. Current state — code evidence

All AMI selection across the repo follows the same pattern: `data "aws_ami" "<name>"` with `most_recent = true`, owner restricted, name filter with wildcard, no version anchor.

### 2.1 Capacity providers — `app-shared-001/main.tf:25-33`

```hcl
data "aws_ami" "ecs_optimized" {
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }

  most_recent = true
  owners      = ["amazon"]
}
```

Same shape in `app-atento-001`, `app-beta-001`, `app-demo-001`. The `image_id` flows into `aws_launch_template` via `modules/ecs_capacity/main.tf:3` (`image_id = var.ami_id`), and each `module.capacity_*` instantiation feeds it from the data source.

Every wildcard match resolves to AWS's latest published image. AWS publishes `al2023-ami-ecs-hvm-*` on its own cadence (multi-times-per-week based on `aws/amazon-ecs-ami` GitHub releases — version `20260514` followed `20260511`, three days apart). Every refresh after a publish surfaces drift.

### 2.2 SQL Server destination — `integrator-atento/sqlserver_simplex_destination.tf:24-37, 124-125`

```hcl
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# (...)

resource "aws_instance" "sqlserver_simplex" {
  ami                  = data.aws_ami.ubuntu_2204.id
  # (...)
}
```

`aws_instance.ami` is **replace-on-change** semantics in the AWS provider. Unlike `aws_launch_template`, there's no `image_id` indirection — bumping the data source destroys the instance. This is why `integrator-atento` shows `forces replacement` and the EC2 with SQL Server data would be lost without a maintenance window.

### 2.3 Windows machine — same anti-pattern in `windows_machine.tf:14`

Not yet exhibiting drift in the current plan, but vulnerable to the same future surprise.

---

## 3. Industry options surveyed

Four mainstream approaches. Tradeoffs evaluated against the engineer's stated constraints: small team, no dedicated ops, weekly drift unacceptable, controlled periodic upgrades wanted.

### 3.1 Option A — Hardcoded `ami_id` string

```hcl
resource "aws_launch_template" "this" {
  image_id = "ami-0c4cd4debdeb146ad"
}
```

**Pros:** absolutely deterministic. Zero drift. Git blame shows when bumped.
**Cons:** region-specific (the same AMI has different IDs in `us-east-1` vs `sa-east-1`). Magic string with no semantic meaning — reviewer cannot tell what version it is without an external lookup. Doesn't scale across multi-region stacks (the repo has both).
**Verdict:** rejected. Multi-region nature of 4Shark (app in `us-east-1`, app-outbound + integrators in `sa-east-1`) makes raw IDs unmaintainable.

### 3.2 Option B — `data.aws_ami` with version-anchored filter

```hcl
data "aws_ami" "ecs_optimized" {
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-2023.7.20260514-kernel-6.1-x86_64"]
  }

  owners = ["amazon"]
  # most_recent removed — filter resolves to exactly one image per region
}
```

The filter anchors the version explicitly. Same code resolves to the equivalent image ID in any region because Amazon publishes AMI names consistently.

**Pros:**
- Explicit version in code — readable, reviewable, git-blame friendly
- Cross-region: works in `us-east-1` and `sa-east-1` from the same filter string
- No `lifecycle` overhead, no state-of-truth split
- Upgrade is a one-line PR: change the filter string
- The PR is the audit trail (author, date, release notes link in commit message)
**Cons:**
- Requires monitoring AWS release notes to know when to bump
- A single-match filter that AWS deprecates returns zero results and breaks the plan — but AWS keeps deprecated AMIs available for 2 years, so this is theoretical at our cadence
- "Manual upgrade" is a feature here, not a bug — it's exactly what the engineer asked for
**Verdict:** **strong candidate.** Matches the constraint: explicit pin, periodic manual upgrade via PR.

### 3.3 Option C — SSM Parameter Store reference

```hcl
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}
```

AWS publishes recommended AMI IDs in SSM Parameters and keeps them updated. The data source resolves at plan time.

**Pros:**
- AWS-managed indirection — name stays stable, value updates upstream
- Standard AWS pattern, well-documented
**Cons:**
- **Does NOT solve the drift problem** — the parameter resolves to the latest, so every plan still shows drift (same as `most_recent = true` today)
- Only useful if combined with `ignore_changes` (becomes Option D)
**Verdict:** rejected for the drift problem. Useful only as part of Option D.

### 3.4 Option D — `data.aws_ami most_recent` + `lifecycle { ignore_changes = [ami / image_id] }`

```hcl
resource "aws_instance" "sqlserver_simplex" {
  ami = data.aws_ami.ubuntu_2204.id
  # (...)

  lifecycle {
    ignore_changes = [ami]
  }
}
```

The data source keeps resolving to latest, but Terraform stops reconciling the attribute on the resource.

**Pros:**
- Minimal code change
- Works for `aws_instance` (replace-on-change) — explicitly opts out of replacement
- Common community pattern
**Cons:**
- State and config drift becomes invisible — the "ignored" deriva is silently accepted forever
- Upgrade requires temporarily removing the `ignore_changes` and reverting after apply, OR adding a `replace_triggered_by` — both fragile
- Diff between "what's deployed" and "what Terraform thinks" becomes a permanent semantic gap
- Hard to reason about: the data source value is meaningful only sometimes
**Verdict:** acceptable as a transitional pattern but not preferred. The HashiCorp docs themselves warn against routine use ([lifecycle docs](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)) — *"makes the resource almost unmanageable by Terraform."*

### 3.5 Comparison summary

| Aspect | A (Hardcoded) | **B (Version filter)** | C (SSM) | D (ignore_changes) |
|---|---|---|---|---|
| Eliminates drift | Yes | **Yes** | No | Yes (silenced) |
| Explicit version in code | Magic string | **Semantic name** | Hidden in SSM | Hidden in data source |
| Multi-region compatible | No | **Yes** | Yes | Yes |
| Upgrade is a reviewable PR | Yes (ugly) | **Yes (clean)** | No (out-of-band) | No (silent state drift) |
| State integrity | High | **High** | Medium | Low (perma-deriva) |
| Effort to migrate | Medium | **Low** | Low | Low |

---

## 4. Recommendation for 4Shark

**Adopt Option B — `data.aws_ami` with version-anchored filter — as the standard across all 4Shark Terraform stacks.**

Two reasons:

1. **The "drift" of the engineer is a workflow drift, not a state drift.** What hurts is the *plan noise every few days*, not the eventual AMI bump. Option B kills the noise without sacrificing reconciliation integrity. Option D hides the noise but lets state and config diverge forever.
2. **The 4Shark team has two engineers and a strong "apply-before-merge + PR audit" culture.** A periodic PR that bumps the AMI version string fits the team's existing rhythm. There's no need for an external pipeline or automation.

### 4.1 What to change per scenario

**Scenario (A) — Capacity providers in app stacks (5 stacks × shared `data.aws_ami.ecs_optimized`):**

Current:
```hcl
filter {
  name   = "name"
  values = ["al2023-ami-ecs-hvm-*-x86_64"]
}
most_recent = true
```

Target (pin to the AMI **currently deployed** post the apply we just did — i.e. `ami-0c4cd4debdeb146ad`, version `20260514` family):
```hcl
filter {
  name   = "name"
  values = ["al2023-ami-ecs-hvm-2023.7.20260514-kernel-6.1-x86_64"]
}
# most_recent removed — single-match resolution
```

Result on first apply post-change: **no changes**, because the filter resolves to the same image we just deployed.

**Scenario (B) — `integrator-atento` SQL Server EC2:**

Current:
```hcl
filter {
  name   = "name"
  values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
}
most_recent = true
```

Target (pin to the AMI **currently running on the live instance**, NOT the latest — to avoid replacement):
```hcl
filter {
  name   = "name"
  values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20260413"]
  # exact date suffix from the current instance's AMI
}
```

The exact value comes from inspecting the running instance:
```bash
aws ec2 describe-instances --region sa-east-1 \
  --instance-ids i-08b28ace85761d7e4 \
  --query 'Reservations[].Instances[].ImageId' --output text
# then describe-images with that ID and read the Name field
```

Result on first apply post-change: **no changes** for the SQL Server. The `forces replacement` disappears.

### 4.2 The upgrade process

Document a runbook in `terraform/docs/runbooks/ami-version-upgrade.md` (separate PR). Cadence and triggers:

- **Capacity providers (ECS-optimized AL2023):** quarterly bump aligned with AL2023 official quarterly minor releases ([release cadence](https://docs.aws.amazon.com/linux/al2023/ug/release-cadence.html)). Also: any CVE flagged in [aws/amazon-ecs-ami releases](https://github.com/aws/amazon-ecs-ami/releases) with a `security` label triggers an ad-hoc bump.
- **Ubuntu (SQL Server, future EC2 workloads):** annually OR when a CVE affects the kernel/glibc/openssl. Ubuntu kernel patches are delivered live via `unattended-upgrades`; AMI bump is for the base image, not the kernel.
- **The upgrade is a PR.** Plan, review, apply on the feature branch (per existing 4Shark workflow), merge. The PR body links to the upstream release notes.

### 4.3 Migration plan (this PR or a follow-up)

1. **Inspect current deployed AMI IDs** in `terraform state` for each affected resource. Capture name + region.
2. **Update HCL** to use anchored filters that resolve to the same IDs.
3. **Plan in each stack** — expect `No changes`. If there ARE changes, the pin is wrong; investigate before continuing.
4. **Apply** — no-op apply, just to confirm state.
5. **Update CHANGELOG** with `Changed: AMI selection pinned to specific versions to eliminate recurring drift`.

Suggested split:
- This current PR (#431): already has the SG fix + AMI drift apply. **Keep its scope.**
- **Follow-up PR(s):** one per affected stack family — capacity in app-*, SQL Server in integrator-atento, Windows machine (preventive). Or one big PR if you prefer.

---

## 5. Risks and edge cases

- **Single-match filter returns zero rows** — if Amazon ever removes a specific dated AMI from the catalog (within the 2-year deprecation window, this is rare), plan fails until the filter is updated. **Mitigation:** alarms aren't needed; a failing plan is loud enough, and the upgrade PR pattern means we'd see it the next bump cycle anyway.
- **Multi-region drift** — pinning the name solves it. The Amazon-published AMI names are identical across regions.
- **AMI deprecation** — AWS sets `DeprecationTime` 2 years after publish. Our manual cadence (quarterly for ECS, yearly for Ubuntu) is well inside that window.
- **Engineer forgets to bump** — accepted risk. Out-of-date AMIs are a security concern only if there's an unpatched CVE; the 7-day quarantine pattern 4Shark already uses for dependency updates can be extended to AMIs (Renovate has a custom manager mode for this — out of scope of this spike but a possible follow-up).

---

## 6. Centralization decision (engineer-confirmed)

Approved direction: introduce a **local module `modules/ami_versions`** that holds the `data.aws_ami` definitions and exposes them via outputs. Each stack consumes via `module "amis" { source = "../modules/ami_versions" }` and references `module.amis.ecs_optimized.id` / `.ubuntu_2204.id` / `.windows_server_2022.id`. Bumps become 1-line PRs in the module; all stacks pick up the new value on next apply.

Scope: **follow-up PR after #431 merges.** PR #431 lands the per-stack inline pin (Option B in § 4). The follow-up creates the shared module and migrates the 6 stacks (4 app + setup + integrator-atento) to consume it.

Rejected alternatives (recorded for posterity):
- **Status quo + runbook only** — N edits per bump scale poorly and risks drift between stacks.
- **Custom SSM Parameter** — adds AWS resource + cross-stack dependency without real benefit over the module pattern (out-of-band SSM updates reintroduce the same surprise drift the spike set out to eliminate).

## 7. Open questions for the next PR

1. **Runbook location:** `docs/runbooks/ami-version-upgrade.md` is the proposed home. Confirm at PR open time.
2. **Renovate integration:** quarterly bump can stay as a calendar invite OR Renovate custom manager that opens a PR when a new ECS-AMI release ships. Start with calendar; evaluate Renovate later (adjacent work, not blocking).
3. **Module API shape:** flat outputs (`ecs_optimized`, `ubuntu_2204`, `windows_server_2022`) vs nested `amis` object. Decide at module creation time.

---

## 7. Sources

- [HashiCorp Terraform AWS provider — `aws_ami` data source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami)
- [HashiCorp lifecycle meta-argument reference](https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle)
- [aws_ami data source non-determinism issue #44833](https://github.com/hashicorp/terraform-provider-aws/issues/44833)
- [Amazon ECS-optimized AMI documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html)
- [`aws/amazon-ecs-ami` releases (release cadence evidence)](https://github.com/aws/amazon-ecs-ami/releases)
- [Amazon Linux 2023 release cadence — quarterly](https://docs.aws.amazon.com/linux/al2023/ug/release-cadence.html)
- [OneUptime — Terraform dynamic AMI lookup (May 2026)](https://oneuptime.com/blog/post/2026-02-23-terraform-dynamic-ami-lookup/view)
- [Scalr — Terraform ignore_changes gotchas](https://scalr.com/learning-center/understanding-the-terraform-ignore_changes-lifecycle-block)
