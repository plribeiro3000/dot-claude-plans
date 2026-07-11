# PLAN — MongoDB Golden-AMI Pipeline (split-role architecture)

> Rewritten 2026-07-10 after the architecture pivot. The prior version (dedicated
> `mongodb` repo with the role COPIED in) is superseded — see `PLAN-SPIKE.md` for
> the original research. The pivot and all decisions below were driven live by the
> engineer.

## HARD RULE — no `8` in any identifier

The major version does NOT belong in any name. The role tracks MongoDB
generically; the installed series lives ONLY in the `mongodb_version` variable
(default `"8.2"`). So, everywhere:

- repo: `ansible-role-mongodb` (NOT `ansible-role-mongodb8`)
- role: `4shark.mongodb` (NOT `4shark.mongodb8`)
- the `name:` in a consumer's `requirements.yml`, every README/meta/CHANGELOG
  reference, every `roles:` entry — all `4shark.mongodb`, no `8`.

Prose describing the product ("installs MongoDB") stays generic too — do not bake
"MongoDB 8" into identifiers or headings; the version is a variable.

**Consequence flagged, not yet resolved:** `4shark.mongodb` collides with the
legacy `4shark.mongodb` role (MongoDB 4.0) still in the `ansible` monorepo. That
legacy role must be retired/reconciled as part of the ansible modernization step
(below) before the new `4shark.mongodb` name is free. Until then, the new role's
installed name is an open item — see Open questions.

## Architecture (three repos, distinct roles)

- **`mongodb`** (build repo, main-only, exists) — owns the Packer HCL2 build, the
  version pin, the Renovate/min-age auto-update, prune-to-3, publishes the AMI. It
  does NOT contain the role; it pulls it from `ansible-role-mongodb` at a pinned
  tag via `requirements.yml` + `ansible-galaxy` at build time.
- **`ansible-role-mongodb`** (role library, main-only, exists) — the MongoDB
  provisioning role, split out of the `ansible` monorepo so the build can pin and
  auto-update it independently (`ansible-galaxy` cannot install one role from a
  monorepo subdirectory — verified). Versioned by git tags. Single source of truth
  for the role.
- **`ansible`** (monorepo) — keeps its OTHER roles; the mongodb role is REMOVED
  from `roles/` and referenced via `requirements.yml`. Its Packer project is
  modernized so the OS-level provisioning is done/maintained there. The legacy
  `4shark.mongodb` (4.0) role is retired here.

Consumers (integrator stacks, the Pritunl VPN Mongo VM) select the AMI by tag via
a `data "aws_ami"` lookup — never a hardcoded id.

## Current state (2026-07-10)

Done:
- `mongodb` build repo created + scaffolded. The initial scaffold COPIED the role;
  that was later undone and replaced by a `requirements.yml` pull (see Remaining
  step 1 and Execution progress below — both DONE).
- `ansible-role-mongodb` repo created, registered in terraform/identity, renamed
  in-place from the wrong `ansible-role-mongodb8` (terraform #671/#672/#673 all
  merged; the rename used `moved` blocks, 0 destroy).
- `ansible-role-mongodb` **populated + merged to main** — the role (verbatim from
  the ansible monorepo), galaxy meta (`namespace: 4shark`, `role_name: mongodb`),
  README/CHANGELOG, and the fleet supply chain (ansible-lint `profile: min` +
  yamllint, Renovate, min-age). Zero `8` in any identifier. CI green.
- Local clone re-pointed to the canonical `~/Projects/4Shark/ansible-role-mongodb`.

## VALIDATION GATE — no tag before it works end to end

The role is NOT tagged yet, on purpose. A version tag is a release artifact and
must not be cut before a real Packer build consumes the role and produces a
working AMI (mongod installed, THP off, boots). Until then, consumers pin the role
by the `main` branch (or a commit SHA) — NOT a semver tag. The initial tag
(`v1.0.0`) is cut ONLY after that validation passes, and only with the engineer's
explicit OK (Git Tag Policy). After the tag, every pin flips from `main`/SHA to the
tag and Renovate takes over bumping it.

## The ansible monorepo is legacy — NOT on the critical path

Infra provisioning is moving OFF Ansible onto Terraform. The three playbooks that
consume the mongodb roles are all dying:
`provision-4client-mongodb-server.yml` (→ `4shark.mongodb8`, 8.2),
`provision-4client-without-vpn.yml` and `provision-4client.yml` (→ legacy
`4shark.mongodb`, 4.0). So there is NO collision to resolve and NO wire-back: the
go-forward "inside the OS" provisioning lives in `ansible-role-mongodb`, consumed
by the `mongodb` build's Packer. The monorepo's mongodb roles + those playbooks +
its old `packer/*.json` are legacy cleanup, deferred to the Terraform migration
(alongside Phase 3), NOT a prerequisite for anything here. Leave them untouched
for now — they still serve the current fleet until Phase 3 cuts it over.

## Remaining steps (order)

1. ✅ **`mongodb` build repo** — DONE. The copied role was removed; `ansible/requirements.yml`
   pulls `ansible-role-mongodb` (pinned to `main`) and the Packer ansible provisioner
   installs-then-uses it. main is a clean orphan (ivonoide init dropped).
2. ✅ **VALIDATE** — DONE. Real Packer builds produced bootable MongoDB 8.2 AMIs
   (mongod installed, THP disabled via the baked systemd unit, config in place); the
   pipeline runs in production (build on push-to-main). See "Execution progress" below.
3. ⏸ **Cut `v1.0.0`** — **deferred by the engineer** ("deixa a tag de fora"). The role
   stays pinned to `main` for now. When cut (explicit tag OK required), flip the pin
   from `main` → `v1.0.0` and enable Renovate on the tag.
4. **Phase 2 / Phase 3** — Phase 2 (Pritunl Mongo VM adopts the AMI) is in progress
   under the VPN migration plan (`~/Projects/4Shark/dot-claude-plans/active/pritunl-ecs/PLAN.md`,
   its PR 2.3). Phase 3 (integrator fleet cutover) + the ansible-monorepo legacy cleanup
   ride along later.

## Execution progress (2026-07-10)

- **Build infra (terraform/mongodb stack) — applied + merged**: IAM user `mongodb-ami-build`
  (minimum Packer EC2 policy), its access key, a read-only SSH deploy key on the private
  `ansible-role-mongodb`, and the `mongodb` GitHub Environment secrets (AWS keys + the
  deploy-key private half). The role is private, so the build loads the deploy key and
  clones it over SSH.
- **Validation surfaced and fixed four real build gaps** (the gate did its job):
  1. no default VPC in the account → the Packer `amazon-ebs` source now targets the
     management VPC public subnet via `subnet_filter` (by tag) + `associate_public_ip_address`.
  2. private role clone failed anonymously → SSH deploy key + `git@github.com` in
     `requirements.yml` + a workflow step that loads the key.
  3. the build was slow → tuned; see next.
  4. per-task SSH overhead (a `mkdir` took ~35s) was the real cost, not CPU — fixed by
     `use_proxy = false` (Ansible connects directly to the instance's public IP) +
     `ANSIBLE_PIPELINING=True`. Provisioning dropped from ~8.5 min to ~1.5 min.
- **Instance right-sized back to `t3a.micro`** after the diagnosis proved CPU was never
  the bottleneck; `enable_unlimited_credits = true` keeps the short package-install burst
  from throttling. Micro + unlimited + pipelining ≈ the same speed as a larger instance
  (~10 min total, ~7 of which is the AWS-side EBS snapshot). First production AMI:
  `mongodb-8.2-20260710180906`.
- **Supply-chain governance**: `mongodb` and `ansible-role-mongodb` were added to
  `main_branch_repositories_with_min_age_check` in the identity stack (terraform#680), so
  their merges now require the `Verify Minimum Age` check they already produce.

## Phase 2: Pritunl Mongo VM adopts the golden AMI (greenfield, single-node, 20GB)

Unchanged from the prior plan. The Pritunl Mongo VM (`terraform/vpn/`, PR 2.3 of
the Pritunl migration) references the golden AMI via the tag-filtered
`data "aws_ami"` lookup; single-node standalone `mongod`, 20GB root, born at size.
Depends on steps 1–4. Closes the `4shark.pritunl` MongoDB-install duplication.

## Phase 3: Integrator production Mongo fleet rolling cutover — separate high-risk track

Unchanged from the prior plan. 15 VMs (5 clients × 3-node PSA), manual
runbook-driven per replica set: secondaries first, wait for `SECONDARY`, step down
+ replace primary last. Data nodes 60GB → 40GB (new instances only — EBS cannot
shrink in place); arbiters stay 20GB. Backup per set; `ignore_changes = [ami]`
revisited one stack at a time; maintenance window per client. Disk sizing anchored
on measured CloudWatch `disk_used_percent` (data nodes ~5.5–11GB of 60GB; arbiters
~3–5.6GB of 20GB). Depends on Phase 2 burn-in.

## Technical decisions (current)

| Decision | Choice |
|---|---|
| Role location | Split into its own repo `ansible-role-mongodb` (community-standard for versioned sharing across projects; galaxy cannot pull a monorepo subdir role) |
| Build ↔ role coupling | The `mongodb` build pulls the role via `requirements.yml` + `ansible-galaxy` at a pinned tag; Renovate bumps the tag |
| Naming | No major version in ANY identifier; version lives in `mongodb_version` (default 8.2) |
| Repo models | `mongodb` and `ansible-role-mongodb`: main-only, tags. `ansible`: HubFlow (unchanged) |
| AMI reference in Terraform | `data "aws_ami"` by tag, not hardcoded id, not SSM |
| AMI lifecycle | Immutable per build, tagged build-date + git commit; retain 3 most recent |
| Disk sizing | Integrator data nodes 60→40GB (new instances only), arbiters 20GB, Pritunl 20GB — anchored on measured CloudWatch usage |
| Integrator cutover | Manual runbook, per replica set, secondaries-first/primary-last; own high-risk Phase 3 |

## Open questions

- Legacy `4shark.mongodb` (4.0) retirement — must happen before the new role can
  take the `4shark.mongodb` name; whether its two playbook consumers
  (`provision-4client.yml`, `provision-4client-without-vpn.yml`) are still live is
  unresolved. Until resolved, the new role's installed name is provisional.
- Phase 2 burn-in duration before Phase 3.
- Terraform Policy stance on `-replace` for stateful production resources (Phase 3).

## Session lesson (recorded)

Renaming a terraform resource keyed by name in a `for_each` map ALWAYS needs a
`moved` block — otherwise terraform reads the key change as a new resource and
plans destroy+recreate. An interrupted destroy+recreate apply this session removed
the repo's branch protection + team grant and orphaned the state lock; recovered
via force-unlock + `moved`-block in-place rename. Never let the config alone
reinterpret a keyed resource as new.
