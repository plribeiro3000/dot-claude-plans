# SPIKE: DNS Dynamic ALB Approach

## Question

Can `dns/` read ALB DNS names dynamically via `data "aws_lb"` instead of hardcoded values?
What is the impact on the Terramate dependency graph?

## Context

`dns/` currently has hardcoded ALB DNS names (full ELB hostnames with numeric suffix, e.g. `-553633455`).
App stacks have `after = ["/dns"]` — apps depend on dns/ in execution order.
User wants this direction maintained: apps run after dns.

## Findings

### Current State

- `dns/stack.tm.hcl` — `after` only includes integrators and `app-atento-br`. App stacks are NOT listed.
- All app stacks have `after = ["/shared-resources", "/dns"]`.
- 6 CNAME records in dns/ have hardcoded ELB hostnames.
- Backend: all stacks use `4shark-terraform-state` S3, each with own key.
- No app stack exports `alb_dns_name` as output today.
- `dns/providers.tf` uses `region = "sa-east-1"`, but all app ALBs are in `us-east-1` → provider alias required for `data "aws_lb"`.

### Q1: Circular dependency if dns/ adds `after = [app stacks]`?

**Yes.** App stacks already have `after = ["/dns"]`. Adding the reverse would create a cycle. Terramate would refuse to run.
Resolution: remove `after = ["/dns"]` from app stacks OR don't add app stacks to `dns/after`. Not both.

### Q2: Does dns/ need to export anything for remote_state?

No — direction is inverted. App stacks would add `output "alb_dns_name"`, and dns/ reads via `terraform_remote_state`. S3 infrastructure already supports this.

### Q3: Migration path for `data "aws_lb"`?

1. Confirm ALB names in AWS (`aws elbv2 describe-load-balancers`)
2. Add provider alias `us-east-1` in `dns/providers.tf`
3. Replace each hardcoded `content = "..."` with `data.aws_lb.<name>.dns_name`
4. Apply dns/ — DNS names become dynamic

### Q4: Alternative without remote_state?

**Yes — `data "aws_lb"` directly in dns/.** Eliminates hardcoded hostnames (which break when ALB is recreated) without changing app stack outputs or the Terramate graph. ALB names (e.g. `beta-001-pub-lb`) are stable and do not change on recreation.

## Recommendation

**Option A: `data "aws_lb"` in dns/** for the immediate migration.

- Resolves the hardcoded hostname maintenance problem
- Minimal risk — no cross-stack state sharing
- No changes to the Terramate graph required
- `after = ["/dns"]` in app stacks remains valid and correct

**Option B: `terraform_remote_state`** — viable but higher complexity, requires adding outputs to all app stacks, and introduces cross-stack state coupling.

## Decision

Option A is the correct path. Implementation is a separate task from the current dns-centralization feature branch.

## Impact on dns/stack.tm.hcl (Gap 2)

Do NOT add app stacks to `dns/stack.tm.hcl after` — this would create a circular dependency with the existing `after = ["/dns"]` in app stacks.

The existing direction (apps after dns) is already correct for the user's intent. The real fix is replacing hardcoded ALB hostnames with `data "aws_lb"` — making dns/ truly independent from app stack Terraform state.
