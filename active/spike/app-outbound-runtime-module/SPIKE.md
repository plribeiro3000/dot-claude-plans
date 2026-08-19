# SPIKE — app-outbound runtime module

## Question

The two `app-outbound-*` stacks are the outstanding deviation from the Terraform
module boundary rule. What of their per-stack declaration is genuine duplication
that belongs in a module, and what diverges because the clients genuinely differ?

## Findings

### Finding 1 — the existing `modules/app_outbound` is a NETWORK module, not a runtime one

`modules/app_outbound/` holds `dns.tf`, `routing.tf`, `security.tf`, `vpn.tf` —
VPC, VPN, routing, DNS and a default security group. It declares nothing about
the ECS cluster, the tasks, IAM or KMS.

This is why `app-outbound-atento-br/main.tf:18` instantiates it and
`app-outbound-maqnelson` does not: atento-br has a dedicated VPC, maqnelson
reuses the client's integrator VPC. That split is the per-client decision
`~/.claude/docs/OUTBOUND-INTEGRATION-NETWORK.md` governs — dedicated VPC only
when there is no integrator VPC or a client requirement forces isolation.

**The network divergence is legitimate and must not be consolidated.**

### Finding 2 — the KMS replica is 91 of 94 lines identical

`diff app-outbound-atento-br/kms.tf app-outbound-maqnelson/kms.tf` returns three
changed lines: the provider alias (`aws.atento_001` vs `aws.shared_001`), the
alias name read (`alias/app-atento-001` vs `alias/app-shared-001`) and the
description string. Everything else — the `aws_kms_replica_key`, the whole
independent replica policy with its three statements — is byte-identical.

The resource itself is legitimate (a log group is encryptable only by a key in
its own Region, so the replica is how the stack encrypts under its primary
stack's key rather than minting one). What is not legitimate is declaring it
twice.

### Finding 3 — both stacks declare the SAME twelve IAM resources

`app-outbound-maqnelson/iam.tf` holds all twelve. `app-outbound-atento-br`
splits the same twelve across `iam.tf` (eight) and `iam_task_role.tf` (four).
The first eight appear at identical line numbers in both `iam.tf` files
(20, 28, 56, 81, 86, 108, 116, 135), which is what a copy looks like.

The split into two files is organisational, not functional.

### Finding 4 — compute differs only by name and by the network wiring

`diff` of the two `compute.tf` (185 and 179 lines) reduces to:

- the primary stack's name throughout (`atento-001` vs `shared-001`), including
  which task-config module is sourced and which SSM parameters are read;
- the subnets and security groups — atento-br reads
  `module.networking_data.private_ids` and `module.this.default_security_group_id`
  (its own VPC), maqnelson reads subnet ids from SSM and its own
  `aws_security_group.this` (the reused VPC).

The second is Finding 1 surfacing inside compute. Everything else is a name.

## What this implies

A runtime module sitting BESIDE `modules/app_outbound`, owning the KMS replica,
the twelve IAM resources and the compute, taking as inputs:

- the primary stack's identifier and its provider alias (the only real variation);
- `subnet_ids` and `security_group_ids` — so each stack supplies its network the
  way its client requires, which is question 3 of the boundary test.

The network module stays as it is. Naming should not reuse `app_outbound`, which
is taken by the network module; something like `app_outbound_runtime` keeps the
two distinguishable at the call site.

## Cost and risk

Comparable in shape to terraform PR #980 (the compute migration of the four
`app-*-001` stacks): a new module, two stacks rewritten, `moved` blocks for every
relocated address, and a zero-sum plan proving nothing is created or destroyed
before any apply.

Both stacks serve production clients. The plan must read `0 to add, 0 to change,
0 to destroy` with only relocations listed, per stack, before applying — and the
relocations DO require an apply, because a `moved` block declares a relocation
while only the apply writes it into state.

## Open question for the engineer

Whether the two `*_task_config` modules (`atento_001_task_config`,
`shared_001_task_config`) fold into this work or stay separate. They are already
shared between each primary stack and its outbound sibling, so they are not
duplication of the kind above — but they are two modules doing the same job for
different environments, which the same boundary question could reach.
