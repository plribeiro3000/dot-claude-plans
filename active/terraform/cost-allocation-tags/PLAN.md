# Cost allocation tags — per-entity cost visibility

## Goal

Answer "how much does each entity cost" in Cost Explorer — an environment's full
infra (its VPN, databases, instances, domain) grouped under one identifier, plus
the cost a single client drives even when their workload rides on another
environment, plus the standalone shared services costed on their own (the
engineer-access VPN, the authenticator).

Today this is impossible: the `Project` / `Client` tags exist on resources for
AWS management but were never **activated as cost allocation tags** in Billing,
so `aws ce get-cost-and-usage --filter Project=integrator` returns `$0`. And no
`default_tags` exists on any provider, so any resource whose module forgot to
tag it carries nothing.

## Cost of doing this

Zero on the AWS bill. Applying and activating cost allocation tags is free, and
the Cost Allocation Tags API is free. The only paid pieces are optional and
avoided here: Cost Explorer **API/CLI** queries ($0.01/request — the console is
free) and hourly/resource-level granularity ($0.01/1000 records — daily is
free). Sources: AWS Billing docs (cost-alloc-tags), costgoat CE pricing.

**Not retroactive.** A cost allocation tag accrues data only from activation
forward (~24h to populate). Historical months stay unattributed.

## The three tags

- **`Project`** — the system: `integrator`, `app`, `authenticator`, `vpn`. An
  outbound integration is part of `app`, so it carries `Project = app` (not a
  separate `app-outbound`).
- **`Entity`** — the environment the resources live in, carrying the full
  environment identifier including the `-NNN` sequence (`shared-001`, `beta-001`,
  `demo-001`, `atento-001`, `auth-001`). The sequence is part of the value so a
  second sibling environment (`shared-002`) never collides with the first.
- **`Client`** — the owning client, on every stack dedicated to a single client
  (the dedicated integrators, `app-atento-001`, and the outbound stacks). It sums
  a client's whole footprint across stacks: `Client=maqnelson` covers
  `integrator-maqnelson` plus `app-outbound-maqnelson`; `Client=atento` covers
  `integrator-atento`, `app-atento-001`, and `app-outbound-atento-br`. The
  multi-client environments (`shared-001`, `beta-001`, `demo-001`) and the shared
  infra (`vpn`, `auth-001`) have no single owner, so they carry no `Client`.

## Scope — which stacks get tagged

Only the stacks where per-entity cost is meaningful: integrators, apps, the VPN,
the authenticator. The shared/platform stacks are **excluded** by the engineer's
decision (`dns`, `networking`, `monitoring`, `identity`, `audit`,
`shared-resources`, `analytics-access`, `workspace-access`, `onboarding`,
`setup`, `mongodb`). `integrator-redebrasil` is **not on `develop`** yet, so it
is out of this change and gets its `default_tags` when it lands.

| Stack | `Entity` | `Project` | `Client` |
|---|---|---|---|
| `integrator-almaviva` | `almaviva` | `integrator` | `almaviva` |
| `integrator-atento` | `atento` | `integrator` | `atento` |
| `integrator-commcenter` | `commcenter` | `integrator` | `commcenter` |
| `integrator-maqnelson` | `maqnelson` | `integrator` | `maqnelson` |
| `app-beta-001` | `beta-001` | `app` | — |
| `app-demo-001` | `demo-001` | `app` | — |
| `app-shared-001` | `shared-001` | `app` | — |
| `app-atento-001` | `atento-001` | `app` | `atento` |
| `app-outbound-maqnelson` | `shared-001` | `app` | `maqnelson` |
| `app-outbound-atento-br` | `atento-001` | `app` | `atento` |
| `vpn` | `vpn` | `vpn` | — |
| `auth-001` | `auth-001` | `authenticator` | — |

## Why the SERVICE dimension covers VPN vs DB vs instance — no `Role` tag

The finer split within an entity — VPN vs database vs instance — comes for free
from Cost Explorer's built-in `SERVICE` dimension. Filter `Entity=atento-001` and
group by `SERVICE`: `Amazon Virtual Private Cloud` is the VPN,
`Amazon ElastiCache` / `Amazon RDS` are the databases, `Amazon EC2` is the
instances. So the schema stays `Entity` + `Project` + `Client`; `Environment` and
`Role` are optional refinements deferred unless the SERVICE breakdown proves
insufficient.

## Mechanism — `default_tags` on the AWS provider, per in-scope stack

`default_tags` makes every resource the provider creates inherit the tags
automatically — it catches what a per-resource `tags =` misses. It is a
**provider** setting, so it lives in each stack's `providers.tf` (modules receive
providers, never declare them — TERRAFORM-MODULE-BOUNDARY), and every AWS
provider block in the stack (including regional aliases) carries the same block.

```hcl
# terraform/integrator-atento/providers.tf
provider "aws" {
  region = "sa-east-1"

  default_tags {
    tags = {
      Entity  = "atento"
      Project = "integrator"
    }
  }
}
```

Per-stack `default_tags` is chosen over a Terramate `generate_hcl` template
because the in-scope set is a specific subset and the excluded shared stacks must
not receive the block; a scoped codegen would be more machinery than the small,
identical edits are worth. (Terramate `generate_hcl` gated on a `cost-tagged`
stack tag remains an option if the set grows.)

**Tag-churn watch.** `default_tags` merges with per-resource tags and shows a
diff on every resource that currently sets a conflicting or absent tag inline —
expected, in-place, no replacement. Each stack's plan is reviewed for exactly
this before apply; anything showing a *replace* is a real finding, not tag churn.

## KMS keys — exempt via an un-tagged provider alias

`default_tags` reaches every resource, and a KMS key whose key policy grants no
`Tag` action refuses the tag: applying a cost tag to it calls `kms:TagResource`,
which the policy denies, and the stack's apply fails on that key. The `app` and
`vpn` modules write such least-privilege key policies (their administration
statement carries no `Tag` action), so their keys must be excluded from
`default_tags`.

The exclusion is a second AWS provider, aliased `no_default_tags`, declared in
the stack in the key's own region with no `default_tags` block. The module takes
it through `configuration_aliases` and the KMS key resources set
`provider = aws.no_default_tags`; every other resource keeps the default,
tagged provider. A KMS key carries no meaningful cost anyway, so its absence from
the entity rollup is immaterial.

The `integrator` and `auth` key policies grant `kms:*` to the account root, so
IAM delegation lets `default_tags` tag their keys normally — those modules need
no alias. The outbound stacks create no KMS key of their own.

## Activation

One `aws_ce_cost_allocation_tag` resource per key (`Entity`, `Project`,
`Client`), account-level, in `shared-resources` (account-global config already
lives there — not a per-stack resource, and not `identity`, which is
policy-arbiter restricted).

```hcl
resource "aws_ce_cost_allocation_tag" "entity" {
  tag_key = "Entity"
  status  = "Active"
}
```

The activation is a **separate PR from the tagging**, opened only once the keys
have surfaced in AWS Billing (~24h after the first tagged stack is live). AWS
lists a tag key for activation only after it has appeared on a billed resource,
so the `aws_ce_cost_allocation_tag` apply fails before that window. Keeping it out
of the tagging PR is also what lets the tagging PR merge without drift: a merged
`aws_ce_cost_allocation_tag` that cannot yet apply would be code on `develop` with
no live counterpart.

## Rollout order

Apply-before-merge, one stack at a time, each apply engineer-gated. Follow the
learning ladder — non-productive first:

1. `app-beta-001`, `app-demo-001`, then the staging-bearing integrators — cheap
   to get wrong, and they surface the tag-churn diff shape.
2. The productive app envs (`app-shared-001`, `app-atento-001`) and the
   production integrators.
3. `vpn`, `auth-001`, the outbound stacks.
4. The `aws_ce_cost_allocation_tag` activations (once any tagged stack is
   applied, so the keys exist to activate).

## Verification

After activation + ~24h, `aws ce get-cost-and-usage --filter Entity=atento-001
--group-by SERVICE` returns non-zero, split by service. Before that window the
tag reads $0 — that is the not-retroactive property, not a failure.
