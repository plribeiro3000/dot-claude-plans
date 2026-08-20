# Integrator MongoDB fleet re-provision — Ubuntu 24.04 wave

Move all four integrator MongoDB replica sets onto the `mongodb-8.0-20260819141804` golden image, in one wave, then repair the migration skill and the policies that describe it.

## Why this is a single wave and not four independent migrations

The four references that Phase C.3 of `mongodb-reprovision` repoints — `AWS_INSTANCE_IDS`, the `ec2:StartInstances` resource list, the scheduler's `InstanceIds`, and `ec2_instance_arns` — live in `modules/integrator/`, shared by every integrator stack. The skill still describes them as living in `integrator-<client>/compute.tf`; that layout was moved into the module by `cbb75fc` (2026-07-24) and the skill was never updated. A grep of any client stack for `integrator_mongo00` returns nothing.

Because the references are shared, the repoint is one commit for the whole fleet. The previous wave did exactly that: `71de5e4` added the replacement block to all four stacks, `09a8dd7` swapped the module reference once, `5959f43` retired the old block from all four — all on 2026-07-27.

Attempting the repoint while any stack that uses the scheduler still declares only the old block fails at plan time:

```
Error: Invalid index
  on ../modules/integrator/deployments_alb.tf line 269:
 269:           aws_instance.integrator_mongo005[0].arn,
    │ aws_instance.integrator_mongo005 is empty tuple
```

## Which stacks the repoint actually affects

`deployments.tf` uses splat indexing (`[*]`), which yields an empty list on a stack without the block. Only `deployments_alb.tf` uses `[0]`, and that block is generated only when `mongo_start_cron != ""`.

| Stack | Node block declared | `mongo_start_cron` | `inject_mongo_instance_ids` | Repoint affects it |
|---|---|---|---|---|
| almaviva | 001–006 (both) | set | true | yes — plan error risk and functional |
| maqnelson | 001–003 | set | true | yes — plan error risk and functional |
| atento | 001–003 | unset | absent | no effect |
| commcenter | 001–003 | unset | absent | no effect |

So the repoint PR is unblocked once **almaviva and maqnelson** both carry the new block. `atento` and `commcenter` can migrate at any point in the wave without gating it. The wave still covers all four because the old block is retired fleet-wide in one teardown PR.

## Current state

**almaviva** — replacement nodes `004/005/006` created and DNS-registered; both data nodes joined non-voting, synced to `SECONDARY`; cutover completed (`Healthy: true`, `Problems: []`); old trio `001/002/003` stopped and out of the set; SSM connection string rotated to version 7 pointing at the new hosts. Remaining: C.3 (the shared repoint, PR #1023), C.4 deploy, C.5 engineer gate, then Phase D teardown.

**All four clients are through the replica-set dance and the connection-string rotation.** Every cutover ended `Healthy: true` with an empty `Problems` list, priorities `1 / 0.5 / 0`, MongoDB 8.0.29 on FCV 8.0. Every old trio is stopped and out of its set, holding its data as the warm fallback.

The rotated parameters, by client: `maqnelson` one (`/integrator-maqnelson/MONGODB`, version 7); `atento` seven, one per country including the three staging variants (all version 7); `commcenter` two, prod and staging (both version 6). Each byte-count dropped by exactly 1, the clean-value delta the skill predicts.

**The shared repoint is applied on every stack.** `almaviva` and `maqnelson` carry the full change (`4 / 3 / 4` on apply, the figure the skill documents); `atento` moved only its deploy-user policy; `commcenter` planned no differences at all, since it declares neither the scheduler cron nor the instance-id injection. The stacks that run the daily start/stop cycle now name the nodes that actually serve.

Applying it needed one permission the account did not have. The engineer's policies granted `iam:CreateRolePolicy`, which is not an IAM action — the CLI rejects the equivalent operation as an invalid choice — so writing an inline policy onto a role had never been authorised anywhere. The real action is `iam:PutRolePolicy`, and correcting the name in both policy files was enough; no `Resource` or condition changed, because the statement carrying it already scoped every neighbouring role-writing action the same way.

**The deploy unit is the DEPLOYMENT, not the client, and the two do not match one-to-one.** `vars.INTEGRATORS` in the integrator repository is the authoritative list of valid `-f integrator=` values: `almaviva`, `maqnelson`, `commcenter`, `commcenter-staging`, and seven atento entries (`atento-br`, `atento-cl`, `atento-cl-staging`, `atento-co`, `atento-co-staging`, `atento-mx`, `atento-mx-staging`). A bare `atento` resolves to nothing, so the job runs with no GitHub environment, receives no AWS secrets, and dies at *Configure AWS* with `Could not load credentials from any providers` — a failure that reads like a runner problem and is really an invalid input. `redebrasil` appears in the list but its stack is decommissioned (contract cancelled, only the VPN tunnel remains), so it has no MongoDB and no service to deploy.

**The deploy ref follows the deployment's tier: a staging deployment ships from `develop`, everything else from `master`.** `gh workflow run` defaults to the repository's default branch when `--ref` is omitted, so leaving it off silently produces the wrong ref for every deployment. Pass it explicitly, every time.

A deploy was triggered for every valid deployment, which is what makes the application read the rotated connection string — it does not re-resolve the parameter store on its own.

**The almaviva, maqnelson and commcenter gates passed.** In each, the console reported `ApplicationConfiguration.mongodb` pointing at that client's `mongo004/005/006` and a user count consistent with the last recorded job — 16671 for almaviva, 386 for maqnelson, 1992 for commcenter.

**The wave is complete.** Every client passed its gate, the retired block is destroyed across both stacks and the internal zone, the twelve orphaned volumes are deleted, and `verify` reports `Healthy: true` with an empty `Problems` list on all four sets — each on MongoDB 8.0.29 / FCV 8.0 with the idempotent `1 / 0.5 / 0` priority shape, so the next OS migration elects on its first try.

The cold rollback that survives is the snapshot set recorded below. The warm one is gone with the volumes, which is the point of Phase D.

Two permissions the account never had were discovered by real failures during this wave and granted reactively: writing an inline policy onto a role, and deleting a volume. A third — passing each integrator's own task execution role — was what blocked the validation gate on every client, not just the first.

**Golden image** — `ami-09df7812354486404`, built from `ansible-role-mongodb` v0.3.0, which exempts `mongod` from the needrestart automatic service restart. `modules/mongodb_ami/main.tf` already pins `mongodb-8.0-20260819141804`, so no pin move is owed for the remaining three.

**Known drift carried by this wave** — the role pins the MongoDB series, not the patch version, so almaviva moved 8.0.26 → 8.0.29 during the re-provision. The remaining three will do the same. Authorized.

**Open PR** — [#1023](https://github.com/4shark/terraform/pull/1023), branch `feature/integrator-mongo-node-block-refs`, worktree `.claude/worktrees/mongo-node-block-refs`. It is the C.3 repoint: a straight swap `001/002/003` → `004/005/006` in the four module files, mirroring `09a8dd7`. Rebased on current `develop`. The almaviva plan on this branch reads `4 to add, 4 to change, 4 to destroy`, which is what the skill documents as the expected C.3 plan; the four destroys are ECS task-definition revisions, no service and no instance is touched. **Not merged, not applied** — it waits for maqnelson to carry the new block.

## Retired node and volume record

The root volumes are configured not to delete with the instance, so they survive the terminate as `available` and keep costing. After the terminate there is no way to discover which they were, which is why they are written down here before Phase D runs.

| Client | Node | Instance | Root volume |
|---|---|---|---|
| almaviva | mongo001 | `i-0fe07e2a1ba15dee2` | `vol-01db0adb00597dc68` |
| almaviva | mongo002 | `i-0e8f92187a92c4de0` | `vol-0981e990dbe5f94be` |
| almaviva | mongo003 | `i-0e875904a80ee8a13` | `vol-011ab17a81569a839` |
| maqnelson | mongo001 | `i-0c385d70acaf8563c` | `vol-00bc0753e66689baf` |
| maqnelson | mongo002 | `i-0a0793c598ff4039e` | `vol-01fd17bf69e744dc4` |
| maqnelson | mongo003 | `i-0ef3a38e24dbdef7e` | `vol-08580807a51c9e6a7` |
| atento | mongo001 | `i-08682026d10f6463f` | `vol-094f723cd88c77fa1` |
| atento | mongo002 | `i-0f502821a9b08ca12` | `vol-0e36c24ee03210778` |
| atento | mongo003 | `i-07baa89f9026caeb2` | `vol-065e85df8a0705686` |
| commcenter | mongo001 | `i-02acbb2ea732f5193` | `vol-062f93a37e0f251d0` |
| commcenter | mongo002 | `i-09bff8ae559759494` | `vol-0e376189595e3a4c3` |
| commcenter | mongo003 | `i-070f0a7f0fab41fde` | `vol-035dcab51db604af4` |

## Snapshot record

Phase D.6 verifies these before deleting the orphaned volumes, and they are the only rollback once the volumes are gone.

**maqnelson** — `mongo001` `snap-0764cd82f214c2e36`, `mongo002` `snap-02b6a121c97085b4e`, `mongo003` `snap-0d92ea9416b27d803`, `mongo004` `snap-00007bb0086f4d183`, `mongo005` `snap-064b7bbdeabbd2c60`, `mongo006` `snap-07a69dc51495ee627`. Only the data nodes' snapshots carry anything — `mongo003` and `mongo006` are arbiters.

**atento** — `mongo001` `snap-0725bf1243e1db7e5`, `mongo002` `snap-0a8a34b12da0e4f5c`. Only the two data nodes were snapshotted: the set was reachable, so the arbiter was identified from `rs.conf()` and skipped. Its replica set is named `atento-br`, not after the client.

**almaviva** — `mongo001` `snap-02f3b0840b146aa3e`, `mongo002` `snap-0f0fdb3fd846cc8bd`, `mongo003` `snap-0b2d04e3f8ee68f30`. All three complete.

## Execution order

1. **One PR adding the replacement block to the three remaining stacks** — [#1024](https://github.com/4shark/terraform/pull/1024), branch `feature/integrator-mongo-replacement-nodes-fleet`, worktree `.claude/worktrees/mongo-fleet-block`. Three entries each in `mongo_instances` for `atento`, `commcenter` and `maqnelson`, plus the matching `data` + `aws_route53_record` triples in `dns/internal_dns_integrator.tf`. The module already declares `integrator_mongo004/005/006`; nothing there changes. All three integrator plans read `3 to add, 0 to change, 0 to destroy`, the purely-additive shape the skill requires. Apply the integrator stacks first, then the dns stack.
2. **Per client, in any order: the replica-set dance** — `preflight`, `join` on each data node, then `cutover`. Each is the installed script, invoked bare. Record the snapshot ids from every preflight in this file as they come.
3. **Per client: C.1 stop the old trio, C.2 rotate the connection string.** `atento` carries seven parameters (one per country); `commcenter` carries two (prod plus staging).
4. **Apply and merge #1023** once almaviva and maqnelson both carry the new block. This is the whole fleet's repoint in one apply per stack.
5. **C.4 deploy each integrator**, then the engineer's `bin/ecs run` gate per client.
6. **Phase D teardown, one PR for the fleet** — remove the old `data` + records from the dns stack and the old `aws_instance` blocks from the module, apply dns first, clear termination protection, apply the integrator stacks, delete the orphaned volumes after verifying the snapshots, then `verify` per client.

## Follow-up debt — the skill and the policies

To be done after the wave, not during it.

**`~/.claude/skills/mongodb-reprovision/SKILL.md` Phase C.3 is stale.** It names `integrator-<client>/compute.tf` and prescribes a grep scoped to the client stack, both of which stopped matching the code when the references moved into the shared module. Its expected-plan numbers (`4 to add, 4 to change, 4 to destroy`) are still correct. The correction has to say where the references live now and, more importantly, that C.3 is fleet-wide rather than per-client — which changes the shape of the whole procedure, since the skill is written as four independent client migrations.

**The wave constraint itself is undocumented.** Nothing in the skill says a client cannot be migrated alone. The evidence that it cannot is the July commit trio plus the plan error above.

**The stale text cost a full review cycle in this session** — the repoint was written in the module, questioned as wrong against the skill, and only the grep returning empty settled it. That is the concrete reason the correction is owed rather than optional.
