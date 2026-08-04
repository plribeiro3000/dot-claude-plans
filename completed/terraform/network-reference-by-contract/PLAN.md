# Network References by Contract, Not by Tag or Position

## Problem

Infrastructure in this account resolves networking by two fragile mechanisms, and both are silent when they break.

**Resolution by tag.** A `data` source filters on `tag:Name` to find a VPC or a subnet. The tag is a mutable label with no contract behind it — anyone renaming it for clarity breaks every consumer, and the break surfaces at a later apply in a different stack, or in another repository entirely. This was discovered while correcting three management subnets whose zone suffix did not match the zone they are in: the rename was blocked because the VPN hosts and the MongoDB image build resolve that subnet by its tag.

**Resolution by position.** A consumer reads `public_ids[2]` or `private_ids[0]` from an ordered list. The index carries no meaning — nothing guarantees element 2 is the same subnet next month, and a reordering in the producing stack silently repoints a load balancer or a database to a different Availability Zone.

Neither failure produces an error at the moment the mistake is made. Both produce a wrong resource, later, somewhere else.

## Scope — measured, not estimated

The `tag:Name` sweep returns 24 hits across 5 files, but they are not one problem. They separate into three categories with different verdicts.

### Category 1 — Network resolved by tag (the problem)

| Location | Resolves | Consumer |
|---|---|---|
| `modules/vpn/production.tf:21` | subnet | production VPN host |
| `modules/vpn/staging.tf:26` | subnet | staging VPN host |
| `modules/vpn/mongodb.tf:27` | subnet | VPN MongoDB host |
| `modules/vpc_data/main.tf:9` | VPC | `setup`, `connection_pooler` |
| `modules/vpc_data/main.tf:21` | private subnets | `setup`, `connection_pooler` |
| `modules/vpc_data/main.tf:33` | public subnets | `setup`, `connection_pooler` |

Six lookups. Three are in the VPN module; three constitute `modules/vpc_data` entirely.

### Category 2 — EC2 instances resolved by tag (different problem, out of this scope)

`dns/internal_dns_integrator.tf` carries 15 `data "aws_instance"` lookups by tag, one per MongoDB node per client, plus one in `dns/internal_dns_vpn.tf`. These resolve compute, not network, and the producing stack does not publish instance addresses to SSM today. Fixing them means deciding what the integrator module should export and is a separate piece of work — recorded here so it is not lost, deliberately not planned in this document.

### Category 3 — AMI resolved by tag (correct, leave alone)

`modules/vpn/mongodb.tf:41` resolves the MongoDB golden image with `most_recent = true` on a tag. Its own comment states the intent: *"resolved by tag rather than pinned to an id, so a rebuilt image is adopted by replacing this instance instead of by editing a literal"*. This is the right pattern for an image — the consumer wants whatever is newest, and pinning an id would defeat that. No change.

### The structural duplication

Two modules answer the same question by different means:

| Module | Mechanism | Consumers |
|---|---|---|
| `modules/networking_data` | SSM parameters published by `networking` | `auth`, `integrator`, `app_outbound` |
| `modules/vpc_data` | `tag:Name` filters | `setup`, `connection_pooler` |

`networking_data` is the correct shape and already carries the whole surface: `vpc_id`, `vpc_cidr`, `private_ids`, `public_ids`, `route_table_private_id`, `route_table_public_id`, `nat_gateway_eips`. `vpc_data` exists in parallel doing less, by tag.

### Positional access

The `integrator` and `app_outbound` READMEs document positional access as the pattern for their callers, so the convention is established, not accidental. `modules/auth` was the first stack migrated off it (phase 3) and reads by name.

## The dependency that makes ordering matter

`modules/vpn/production.tf` and `staging.tf` resolve their subnet by tag, and the subnet id feeds `aws_instance.subnet_id` — an attribute that forces instance replacement. The production instance is the gateway the team reaches all private infrastructure through; its own module comment states that replacing it *"means every engineer loses access to the infrastructure they would need to diagnose it"*.

Any change that alters what those lookups resolve to replaces the VPN. A change that makes the lookup fail is safe by comparison — it errors instead of destroying.

Outside this repository, `mongodb/packer/mongodb.pkr.hcl:112` selects its build subnet with `"tag:Name" = "management-pub-a"`. It is not covered by any terraform plan and will not warn.

## Strategy

The end state is that no stack resolves network by tag or by position. Every consumer reads a named value from SSM, published by `networking`, which owns the resources.

Ordering is dictated by one rule: **the producer publishes before any consumer reads.** Adding a parameter is additive and breaks nothing, so every phase that only publishes is independently safe to apply.

### Phase 1 — Publish subnets by name — DONE (PR #884, applied)

`networking/ssm.tf` publishes public and private subnets as ordered `StringList` parameters. Per-subnet `String` parameters sit alongside them, at `/networking/{environment}/{public,private}_subnet_id/{name}`, without removing the lists.

The key is the **subnet name, not the zone** — `sa-east-1c` holds two public subnets in the management VPC, so a zone is not a unique key there.

Additive change. No consumer is affected. The lists keep working while consumers migrate one at a time.

### Phase 2 — `networking_data` exposes the per-name outputs — DONE (PR #884)

`modules/networking_data` reads the new parameters through a `for_each` over `public_subnet_names` / `private_subnet_names` — set by the caller, so a stack only reads the parameters it consumes — and exposes them as `public_subnet_id` / `private_subnet_id` maps keyed by name. Existing outputs stay.

Additive. Every current consumer keeps compiling unchanged.

### Phase 3 — Migrate `auth` off positional access — DONE (PR #885, plan `No changes`)

`modules/auth` reads `public_subnet_id["a1"]` / `private_subnet_id["a"]` instead of `public_ids[2]` / `private_ids[0]`. Five files: `vpc.tf` declares the names, `alb.tf`, `ecs.tf`, `rds.tf`, `auth_001_staging.tf` consume them.

The subnet ids resolved had to be identical to today's, or the ALB and the RDS subnet group change — and for RDS a subnet-group change means replacement. Plan on `auth-001` returned `No changes`.

### Phase 4 — Migrate `vpn` off tag lookups — DONE (PR #886, plan and apply `0 added, 0 changed, 0 destroyed`)

`modules/vpn` reads `public_subnet_id["c1"]` and `private_subnet_id["a"]` from `networking_data`; the three `data "aws_subnet"` tag lookups and the six `vpc_id = "vpc-..."` literals are gone. `data "aws_ami"` keeps its tag filter — resolving the newest golden image by tag is the intended behavior (category 3).

The highest-risk phase. The resolved subnet id had to be byte-identical to what the tag resolved to, or the VPN hosts are replaced. The tag `management-pub-a` resolves to a subnet in `sa-east-1c`, published as `c1` — reading the zone off the tag name would have picked a different subnet and replaced the production gateway.

### Phase 5 — Retire `modules/vpc_data` — DONE (PR #888, nothing to apply)

There was no migration to do: every consumer already sourced `networking_data`. What made the duplication look alive is that the module BLOCKS are named `vpc_data` while sourcing `../modules/networking_data` — a leftover name. `modules/vpc_data/` had zero callers and was deleted.

Nothing to apply, and that is verified rather than assumed: every `module.vpc_data.*` address in state is a `data.aws_ssm_parameter.*` (so, `networking_data`); no `aws_vpc.selected` / `aws_subnets.*` address from the deleted module exists in any state.

The block names are left alone. Renaming them to match what they source would change the state address of every data source inside them across six environments — including addresses `docs/runbooks/STATE-SURGERY-MIGRATION.md` names explicitly — for readability alone.

### Phase 6 — Packer — DONE (terraform PR #889 applied; mongodb PR #21 open)

The subnet id is passed in from the workflow, which reads the published parameter. Leaving the tag as a "documented external consumer" was rejected on the effort's own terms: that build is covered by no `terraform plan`, so a renamed subnet breaks it silently — exactly the failure this work exists to remove, and the one place where nothing would catch it.

Two halves, producer first:

- **terraform PR #889** (merged, applied — `0 added, 1 changed, 0 destroyed`) grants the build identity `ssm:GetParameter` on `/networking/management/public_subnet_id/*`. Verified live with `simulate-principal-policy`, which returned `allowed` for the exact ARN the build reads — a policy can be syntactically right and still not cover the intended ARN.
- **mongodb PR #21** replaces the `subnet_filter` tag lookup with a required `subnet_id` variable, and the `Build` workflow resolves it from the parameter. The variable has no default on purpose: a default would let a bake land somewhere unintended in silence. Because it is required, `ci.yaml`'s `packer validate` passes a placeholder — validation checks the configuration, not the account, and that workflow holds no credentials.

### Phase 7 — Correct the subnet tags — DONE (PR #890, applied — `0 added, 3 changed, 0 destroyed`)

Every management subnet name now states the zone it is in: `management-pub-c1` and `management-pub-c2` in `sa-east-1c`, `management-pub-a1` in `sa-east-1a`, with the private pair already correct at `management-prv-a` and `management-prv-c`.

The subnet ids are unchanged and the production VPN gateway kept its instance id and July launch time — a name is metadata on an existing subnet, so the update is in place. A replacement here would have destroyed everything attached: the VPN gateway, the Keycloak load balancer, the Mongo host.

The precondition was verified before touching anything, not assumed: a sweep of every repository under `~/Projects/4Shark/` plus the installed tooling under `~/.claude/` found the old names only in this file's own definitions and in planning documents. Nothing resolved by them.

## Delivered outside the phase sequence

**terraform PR #883** (merged) — renamed the three management public subnet *resources* (`management_pub_a` → `management_pub_c1`, `management_pub_c` → `management_pub_c2`, `management_pub_2a` → `management_pub_a1`) using `moved` blocks, leaving the `Name` tags untouched.

It is the code-readability half of phase 7, delivered early because it touches nothing in AWS. The tag half waits for phases 5 and 6.

**terraform PR #887** (merged, applied on five stacks with zero resource changes) — pinned the MongoDB golden AMI in `modules/ami_versions` and pointed `modules/integrator` and `modules/vpn` at it. Not part of this effort, but it removed the last `most_recent = true` + `tag:Name` AMI lookup inside terraform, which narrows what phase 6 has to decide: the Packer build's `subnet_filter` is now the only `tag:Name` network lookup left anywhere.

## Risks

**Replacing the production VPN.** Every phase that touches `modules/vpn` carries it. Mitigation: gate each apply on a plan showing zero replacements, and never let a lookup silently resolve to a different subnet — prefer a lookup that fails.

**Cross-repository break.** The Packer template is invisible to terraform. Until phase 6, any tag rename breaks the MongoDB image build with no warning at plan time.

**Positional migration changing a subnet.** Phases 3 and 4 must resolve to the same ids currently in use. A wrong mapping moves a load balancer or a database to a different zone, which for RDS means a replacement.

## Decisions

- Category 3 (`aws_ami` by tag) is deliberately excluded — resolving an image by tag with `most_recent` is the correct pattern, documented in the code itself.
- Category 2 (EC2 instances by tag in the `dns` stack) is recorded but not planned here — it requires deciding what the integrator module exports, which is a different design question from network references.
- Per-zone SSM parameters were chosen over reordering the existing lists, because a list consumed by index cannot be made safe by reordering — only by not being consumed by index.
- Phases are ordered producer-first so that every publishing phase is independently applicable and no consumer is ever ahead of its data.
