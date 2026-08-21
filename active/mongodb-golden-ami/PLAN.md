# PLAN — MongoDB Golden-AMI Pipeline (split-role architecture)

> Rewritten 2026-07-10 after the architecture pivot. The prior version (dedicated
> `mongodb` repo with the role COPIED in) is superseded — see `PLAN-SPIKE.md` for
> the original research. The pivot and all decisions below were driven live by the
> engineer.
>
> Revised 2026-07-16: the series is `8.0`, not `8.2` (see "Version and OS are both
> pinned by upstream constraints" below); Phase 3 is DONE for every active client.

## Version and OS are both pinned by upstream constraints — neither is a free choice

**Series `8.0`, not `8.2`.** MongoDB's rapid/minor releases (8.1, 8.2, 8.3) are not
for self-managed deployments — only the X.0 LTS line is. `mongodb_version` therefore
tracks the LTS line and nothing else, enforced mechanically: `renovate.json`'s
`allowedVersions` constrains the `endoflife-date` datasource to X.0, and majors sit
behind dependency-dashboard approval. Verbatim from `mongodb/packer/mongodb.pkr.hcl:45-54`:
*"it offers rapid/minor releases (8.1, 8.2, 8.3), which MongoDB directs self-managed
deployments away from ... `allowedVersions` in renovate.json constrains this to the X.0
LTS line"*. The current value is `default = "8.0"` (`mongodb.pkr.hcl:51-54`).

**Ubuntu `noble` / 24.04, and 24.04 is a ceiling — not a waypoint.** MongoDB publishes
an apt repo for `noble` and returns 404 for `resolute` (26.04), so a node built on 26.04
would have no MongoDB to install at all. Verbatim from `mongodb/packer/mongodb.pkr.hcl:71-75`:
*"24.04 is the ceiling, not a waypoint: MongoDB publishes an apt repo for `noble` and
returns 404 for `resolute` (26.04) ... Do not advance these past `noble` until that repo
exists."* Unlike `mongodb_version`, the codename is NOT a build input — every node runs
the same image, so there is nothing to choose between.

**Consequence:** the fleet is at the newest series and OS it can be at. The next move is
gated on upstream, not on us — a new X.0 LTS line, or MongoDB publishing an apt repo for
a newer Ubuntu LTS. Neither is a decision to schedule; both are events to react to.

## HARD RULE — no `8` in any identifier

The major version does NOT belong in any name. The role tracks MongoDB
generically; the installed series lives ONLY in the `mongodb_version` variable
(default `"8.0"`). So, everywhere:

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

## Current state (2026-07-16)

Done:
- **Phase 3 (integrator fleet cutover) — COMPLETE for every active client.** All 12 nodes
  of `almaviva`, `atento`, `commcenter` and `maqnelson` run the golden AMI
  `ami-0244451ea895c4e3c` (`mongodb-8.0-20260715103934`, Ubuntu 24.04 + MongoDB 8.0),
  verified against both the stacks' `mongodb.tf` and the live `describe-instances` state.
  `redebrasil` is deliberately excluded — see "Phase 3" below.
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
2. ✅ **VALIDATE** — DONE. Real Packer builds produced bootable MongoDB 8.0 AMIs
   (mongod installed, THP disabled via the baked systemd unit, config in place); the
   pipeline runs in production (build on push-to-main). See "Execution progress" below.
3. ⏸ **Cut `v1.0.0`** — **deferred by the engineer** ("deixa a tag de fora"). The role
   stays pinned to `main` for now. When cut (explicit tag OK required), flip the pin
   from `main` → `v1.0.0` and enable Renovate on the tag.
4. **Phase 2** — Pritunl Mongo VM adopts the AMI. In progress under the VPN migration plan
   (`~/Projects/4Shark/dot-claude-plans/active/pritunl-ecs/PLAN.md`, its PR 2.3).
5. ✅ **Phase 3** — integrator fleet cutover. DONE for every active client (see Phase 3
   below). The ansible-monorepo legacy cleanup is the remaining tail.
6. **Phase 4** — the AMI snapshot moves onto a key of its own (see Phase 4 below). The
   nodes' own volumes are already on their consumer keys; this closes the image itself.

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
  (~10 min total, ~7 of which is the AWS-side EBS snapshot).
- **AMI retention is working as designed** — prune-to-3 leaves exactly the three most recent
  (`mongodb-8.0-20260715103934`, `-20260714205131`, `-20260714204001` as of 2026-07-16);
  every earlier build, including the first, has already aged out.
- **Supply-chain governance**: `mongodb` and `ansible-role-mongodb` were added to
  `main_branch_repositories_with_min_age_check` in the identity stack (terraform#680), so
  their merges now require the `Verify Minimum Age` check they already produce.

## Phase 2: Pritunl Mongo VM adopts the golden AMI (greenfield, single-node, 20GB)

Unchanged from the prior plan. The Pritunl Mongo VM (`terraform/vpn/`, PR 2.3 of
the Pritunl migration) references the golden AMI via the tag-filtered
`data "aws_ami"` lookup; single-node standalone `mongod`, 20GB root, born at size.
Depends on steps 1–4. Closes the `4shark.pritunl` MongoDB-install duplication.

## Phase 3: Integrator production Mongo fleet rolling cutover — ✅ COMPLETE (active clients)

**Executed 2026-07-14/15**, ahead of Phase 2 rather than after it (the ordering the
prior plan assumed — "depends on Phase 2 burn-in" — did not hold; the fleet cutover ran
first and IS the burn-in the Pritunl Mongo VM now inherits).

**Scope delivered: 12 nodes, 4 clients × 3-node PSA** — `almaviva`, `atento`,
`commcenter`, `maqnelson` — all on `ami-0244451ea895c4e3c` (`mongodb-8.0-20260715103934`),
Ubuntu 24.04 + MongoDB 8.0. Method was the planned one: node replacement per replica set,
secondaries first, primary last (the `/mongodb-reprovision` skill owns the replica-set
dance). Data nodes `t3.small`, arbiters `t3.micro`.

**`redebrasil` is out of scope by decision, not by omission** — the client cancelled. Its
three nodes (`4client-redebrasil-mongo003/004/005`, still on the pre-migration Ubuntu 18.04
AMI `ami-0bd91caaa9bc42cf3`, all `stopped`) are awaiting the client's written deletion
request, at which point the data and the stack are removed. Migrating them would be effort
spent on infrastructure scheduled for deletion. Its `terraform/integrator-redebrasil/mongodb.tf`
still references the 18.04 AMI — correct, since those nodes are frozen pending erasure, not
pending migration. The erasure itself follows `~/.claude/docs/runbooks/compliance/LGPD-DATA-ERASURE.md`.

**Open discrepancy against this plan's own decision (flagged, not resolved):** the decision
table below says *"AMI reference in Terraform | `data "aws_ami"` by tag, not hardcoded id"*,
but all four migrated stacks pin the literal id (`ami = "ami-0244451ea895c4e3c"` —
`terraform/integrator-almaviva/mongodb.tf:34,77,120` and the same shape in the other three).
With `ignore_changes = [ami]` still in place the hardcoded id is inert (Terraform will not act
on it either way), so this is not drift that threatens the fleet — but the next AMI adoption
has no automatic path, and the stated decision is not what is deployed. Reconcile or retract
the decision; do not leave the plan claiming a mechanism the code does not use.

## Phase 4: the AMI snapshot gets a key of its own

The image's snapshot and the running node's disk are two different objects, and only the
second one is on a dedicated key today. Every consumer already re-encrypts at launch —
`modules/integrator/mongodb.tf:86,131,176,221,266,311` declares `kms_key_id =
aws_kms_key.integrator.arn` on all six node slots, and `modules/vpn/mongodb.tf:88-89`
declares the VPN's own key — so the nodes serving production are correctly keyed. What is
not is the snapshot each AMI is built from.

**The build opines about nothing, which is why the images are inconsistent.**
`packer/mongodb.pkr.hcl` carries no `encrypt_boot`, no `kms_key_id`, no
`region_kms_key_ids`; its `launch_block_device_mappings` block sets size and type only.
The three live images show the consequence: `mongodb-8.0-20260715103934` is not encrypted
at all, while `mongodb-8.0-20260803203023` and `mongodb-8.0-20260819141804` are encrypted
under `alias/aws/ebs`. Nothing in the repository changed between those builds, so the
encryption arrived from outside it — account-level EBS default encryption is the only
mechanism that encrypts a snapshot no one asked to encrypt, and it uses exactly that key.
Confirm that setting and its effective date before writing the fix; the fix is the same
either way, but the explanation in the commit should be true.

**The key belongs to the `mongodb` stack, which already owns the build.** That stack holds
`deploy_key.tf`, `github.tf` and `iam.tf` — the credentials the image pipeline runs under —
and no `kms.tf`. A key minted there is owned by the thing that produces the artifact, which
is the same reasoning that puts each environment's key inside the module that produces its
resources. One key serves every image because the images are one artifact line, not
per-client data: the blast radius of the AMI snapshot is the image, and the blast radius of
the client's data is the node's own volume, which already has its own key.

**Two key policies have to be right, and they are right for different callers.** At launch
the EC2 service decrypts the AMI's snapshot under the golden-AMI key and encrypts the new
root volume under the consumer's key, so the golden-AMI key needs the same
`ec2.<region>.amazonaws.com` pair every consumer key already carries — cryptographic use
plus `kms:CreateGrant`, since AWS states the principal calling the launch "must have
kms:CreateGrant permissions to create a grant for Amazon EC2". The consumer keys need no
change: `modules/integrator/kms.tf:178,197` and the VPN's equivalent already declare that
pair. A missing grant on the new key fails at the next launch, not at apply — the same
delayed failure mode the ECS capacity groups had, so the key policy lands and is proven
before any image is built against it.

**The key is named in the block device mapping, not in the source.** The builder's own
guidance is that for a single-region build with a custom key it is *"more efficient to
leave this and `encrypt_boot` empty and to instead set the key id in the
launch_block_device_mappings"*, because the source-level pair *"saves potentially many
minutes at the end of the build by preventing Packer from having to copy and re-encrypt
the image at the end of the build"* only when it is avoided. This build is exactly that
case — one region, one key — so `encrypted = true` + `kms_key_id = "alias/..."` go inside
the existing `launch_block_device_mappings` block, which is also the shape the ECS capacity
groups use. An alias is a valid value there provided the `alias/` prefix is kept; the build
user's IAM policy names the key's ARN, which authorizes a call that identifies the key by
alias, since only the policy's own `Resource` element may not be an alias.

Steps, in order:

1. ✅ **DONE** — the account's EBS-default-encryption setting confirmed on
   (`EbsEncryptionByDefault: true`), which is what has been encrypting the snapshots
   under `alias/aws/ebs`.
2. ✅ **DONE (applied + merged, terraform#1052)** — `kms.tf` in the `mongodb` stack:
   `alias/mongodb-golden-ami` with the EC2 use + `kms:CreateGrant` pair, plus a matching
   grant on the Packer build user's IAM policy scoped to that key alone.
3. ✅ **DONE (merged, mongodb#31)** — the key named in `launch_block_device_mappings`.
4. ✅ **DONE** — `mongodb-8.0-20260820163516`, the first image built after the merge, has
   its snapshot (`snap-03183eb94eb0614b0`) encrypted under key
   `98113283-78a1-4d5e-9bd5-63fe7dfd9de2`, which is what `alias/mongodb-golden-ami`
   resolves to. The two images preceding it are on the account's `aws/ebs` default
   (`414c7ff5-6258-47f7-a96d-d502d12fd4e3`) and age out under the 3-image retention.
5. ✅ **DONE** — a throwaway instance launched from `ami-06318272b35159665` outside
   Terraform, with `alias/vpn` named on the root volume, produced a volume encrypted under
   `0f4e9ae3-59a1-4d66-a4ae-14936a615f1c` — the VPN key, not the golden-AMI key. The launch
   succeeding is itself half the proof, since EC2 had to decrypt the golden-AMI snapshot to
   create that volume, and a missing grant fails at a LAUNCH rather than at an apply. The
   instance was terminated and its volume deleted with it.

Phase 4 is complete. What remains is attrition: the two images still on the account's
`aws/ebs` default age out under the 3-image retention as new builds land.

The existing images stay until the retention rule (3 most recent) retires them — deleting
one deregisters the AMI that depends on it.

## Technical decisions (current)

| Decision | Choice |
|---|---|
| AMI snapshot encryption | `alias/mongodb-golden-ami`, one key for the whole image line, minted in the `mongodb` stack; the running node re-encrypts onto its own consumer key at launch |
| Role location | Split into its own repo `ansible-role-mongodb` (community-standard for versioned sharing across projects; galaxy cannot pull a monorepo subdir role) |
| Build ↔ role coupling | The `mongodb` build pulls the role via `requirements.yml` + `ansible-galaxy` at a pinned tag; Renovate bumps the tag |
| Naming | No major version in ANY identifier; version lives in `mongodb_version` (default 8.0) |
| Series tracked | `8.0` — the X.0 LTS line only; rapid releases (8.1/8.2/8.3) are not for self-managed deployments, enforced by `allowedVersions` in `renovate.json` |
| Ubuntu | `noble` / 24.04 — a ceiling, not a waypoint: MongoDB's apt repo 404s for `resolute` (26.04). Not a build input; every node runs the same image |
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
- ~~Phase 2 burn-in duration before Phase 3.~~ Moot — Phase 3 ran first; the fleet IS the burn-in.
- ~~Terraform Policy stance on `-replace` for stateful production resources (Phase 3).~~ Moot — Phase 3 replaced nodes via the reprovision runbook, not via `-replace`.
- The `data "aws_ami"` vs hardcoded-id discrepancy surfaced by Phase 3 (see Phase 3 above) — reconcile or retract.
- When the tag pin flips from `main` to `v1.0.0` (step 3), whether Renovate's role-tag bump and the AMI rebuild it triggers should be gated behind the same 7-day min-age the rest of the fleet uses.

## Session lesson (recorded)

Renaming a terraform resource keyed by name in a `for_each` map ALWAYS needs a
`moved` block — otherwise terraform reads the key change as a new resource and
plans destroy+recreate. An interrupted destroy+recreate apply this session removed
the repo's branch protection + team grant and orphaned the state lock; recovered
via force-unlock + `moved`-block in-place rename. Never let the config alone
reinterpret a keyed resource as new.
