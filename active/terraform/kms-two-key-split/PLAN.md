# PLAN — KMS two-key split (productive / non-productive)

Derived from `active/spike/kms-key-per-environment/SPIKE.md` and the engineer's decision of
2026-07-16. Supersedes the direction of `active/terraform/kms-migration/PLAN.md` Task 2 — see
§ Relationship to the existing KMS plan.

## Goal

Split the single account-wide KMS key into two, so an identity that can decrypt the non-productive
environment cannot decrypt productive data.

## The decision, and the reasoning behind it

**Two keys, not six.** The boundary a key draws is only worth what the identity boundary behind it
is worth — AWS frames the control as *"keys with policies that limit access to the appropriate
principals"* (SEC08-BP02), never a key on its own. 4Shark has three engineer tiers, but baseline
and elevated differ in what they may *do*, not in *which environments* they reach. Only the third
tier (the diminished one, being designed in `active/spike/aws-engineer-staging-tier/`) is scoped to
an environment: beta. So there are exactly two environment audiences, and therefore two keys. A
third key earns its place the day an audience appears that needs one environment and must not see
another — not before.

**`demo-001` sits on the productive key.** Clients access it, it holds real client data, and no
engineer reaches demo without also reaching the productive environments. Client access is over
HTTP, through the application's own task role — clients are never a KMS audience, so their presence
does not argue for a separate key.

**`setup` and `onboarding` sit on the productive key too.** They were not named in the decision
conversation, but they use `4shark-master` today (`setup/ssm.tf:60`, `setup/rds.tf:54,66,70`,
`onboarding/ssm.tf:64`, `onboarding/rds.tf:54,66,70`) and are productive services. Flagging rather
than assuming: if either is in fact non-productive, it moves to the beta key and this plan changes.

| Key | Environments |
|---|---|
| productive | `app-shared-001`, `app-atento-001`, `app-demo-001`, `setup`, `onboarding` |
| non-productive | `app-beta-001` |

## Current state

`4shark-master` (`mrk-fa0cda243274491784fc7b39bead5a03`) encrypts **six stacks across four
services**. Its own description reads *"4Shark master encryption key - all environments and
services"* — the consolidation was deliberate, not accidental.

| Service | Where | Rekey cost |
|---|---|---|
| SSM SecureString | all six stacks' `ssm.tf` | `put-parameter --overwrite --key-id`; no downtime |
| Secrets Manager (connection pooler userlist) | `app-{beta,demo,shared,atento}-001/connection_pooler.tf` | `UpdateSecret --kms-key-id`; in place, no downtime |
| RDS (storage, master user secret, performance insights) | all six stacks' `rds.tf` | **snapshot + copy + restore; 30+ min downtime per instance** |
| OpenSearch | `app-shared-001/opensearch.tf:46`, `app-atento-001/opensearch.tf:46` | not established — see § Open questions |

The estate already runs one-key-per-stack for backups (six `backup-<stack>-local` aliases, from
`modules/cross_region_backup`). Those are **regional** keys, not multi-region — so the new keys do
not need to copy `4shark-master`'s multi-region shape unless cross-region DR requires it.

## Sequence

Phased so the leak closes first and the expensive migration is separable. Each phase is its own PR.

### Phase 1 — Create the two keys

New `aws_kms_key` + `aws_kms_alias` pairs. Nothing consumes them yet, so this phase carries no
migration risk and can be applied and merged on its own.

Naming follows the estate's existing `backup-<stack>-local` shape rather than `4shark-master`'s:
the alias says what the key protects. Exact names to be fixed at implementation against the sibling
stacks — the convention, not the string, is what this plan pins.

Home: `shared-resources/`, alongside where `kms-migration/PLAN.md` Task 1 places the imported
`4shark-master`.

### Phase 2 — Move beta's SSM parameters to the non-productive key

This is the phase that closes the leak the whole line of work started from, and unblocks the
diminished engineer tier. Smallest possible change that delivers it.

1. Point `app-beta-001/ssm.tf` at the non-productive key.
2. Re-encrypt the existing parameters (`put-parameter --overwrite --key-id`). **Note**: the spike
   flags this as inferred from documented mechanics, not an AWS-stated guarantee — verify on one
   parameter before running the set.
3. Confirm the application still reads its parameters.

### Phase 3 — Move the productive stacks' SSM parameters to the productive key

Same mechanics as Phase 2, five stacks. No downtime, but productive — one stack at a time, verified
between each.

### Phase 4 — Secrets Manager (connection pooler userlist)

`UpdateSecret --kms-key-id`, in place. Four stacks. Beta first.

### Phase 5 — RDS

The expensive one: snapshot + copy under the new key + restore, **30+ min downtime per instance**,
one maintenance window each. Beta first (no downtime cost), then the productive stacks one at a
time.

This phase is separable and may be deferred indefinitely without weakening Phases 2–4 — the SSM
leak is closed regardless. Deferring leaves RDS storage on the shared key, which is a smaller
exposure than SSM (no engineer tier gets raw RDS storage decrypt; the database is reached through
credentials, not KMS).

### Phase 6 — OpenSearch

Only after § Open questions resolves whether OpenSearch can rekey in place.

## Relationship to the existing KMS plan

`active/terraform/kms-migration/PLAN.md`:

- **Task 1 (import `4shark-master` into Terraform) stays, and should go first.** The key was created
  by CLI and no resource manages it. That is true regardless of how many keys the estate ends with,
  and Phase 1 lands next to it.
- **Task 2 (migrate legacy RDS onto `4shark-master`) is superseded.** Moving legacy instances onto
  the shared key, only to move them again onto a per-tier key in Phase 5, is two maintenance windows
  to reach the wrong intermediate state. Those instances should go straight to their tier's key —
  fold them into Phase 5.

That plan should be marked superseded-in-part rather than left to be read as current.

## Open questions

- **OpenSearch rekey**: whether the domain's `kms_key_id` can change in place or forces a
  blue/green domain replacement. Not established in the spike. Blocks Phase 6 only.
- **`setup` / `onboarding` classification**: assumed productive here. Engineer to confirm.
- **Multi-region or regional**: `4shark-master` is multi-region; `cross_region_backup` shows the
  estate achieves cross-region DR with paired regional keys instead. Decide per key at Phase 1 —
  driven by whether anything in these stacks genuinely needs the key present in `sa-east-1`.
- **`alias/4shark-ecs-beta-key`**: live since 2025-10-17, rotation disabled, console-default policy,
  referenced by nothing in any repo. Orphan, and unrelated to this split — separate cleanup
  decision (keep / investigate via CloudTrail / schedule deletion).

## Risks

| Risk | Mitigation |
|---|---|
| A parameter fails to re-encrypt and the application cannot read it | Beta first (Phase 2), verify before touching productive (Phase 3). One stack at a time. |
| The `put-parameter --overwrite --key-id` rekey does not behave as inferred | Verify on a single non-critical parameter before the set — the spike explicitly flags this as unverified. |
| `4shark-master` is left half-used and nobody finishes the migration | Phases 2–4 are complete and coherent on their own; Phase 5 deferring is an accepted outcome, not a loose end. Record it as such if deferred. |
| RDS restore under the new key loses data written during the window | Standard snapshot/restore discipline; productive stacks get a real maintenance window, not an opportunistic one. |

## Out of scope

- The diminished engineer tier itself (`active/spike/aws-engineer-staging-tier/`) — this plan makes
  its environment scoping *possible*; it does not build the tier.
- Retiring `4shark-master`. After all phases it would hold nothing, but deleting a KMS key is
  irreversible and deserves its own decision.
- `alias/4shark-ecs-beta-key` cleanup.
