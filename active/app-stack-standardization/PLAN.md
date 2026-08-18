# PLAN — Converging the app stacks onto modules/app

## What this is

The order and the shape for moving what an `app` environment is made of into `modules/app`, so an app stack becomes the thin instantiation layer every other project's stack already is.

**The measurement that scopes the work.** `integrator-almaviva`, `integrator-commcenter`, `setup` and `onboarding` carry three or four files each and zero `resource` blocks. The four `app-*-001` stacks carry twenty-two to twenty-four. That gap is the work.

## What an app environment IS

An environment runs the application, and the application does not run without its datastores. Redis holds the queue Sidekiq processes; MongoDB and PostgreSQL hold the data; OpenSearch answers the searches. Naming them as separate per-stack files states the opposite — that an environment might be assembled without one — and every stack then repeats the same declaration to say the same thing four times.

So each of them is created BY the module, unconditionally, on the environment's own encryption key. That is the first question of the module boundary answered, and it decides most of the inventory below.

## The productive axis

**`productive` is a property of the environment, and the module takes it as one input.** It is already how 4Shark describes its environments — the apps catalog carries it per environment, the deploy gate reads it to decide whether a queue check is required, and the database shape follows it (a productive environment has a read follower and a dedicated readonly role).

What it decides in the module is a coherent SET rather than a list of independent switches:

| Decided by `productive` | Productive | Non-productive |
|---|---|---|
| OpenSearch domain | created | absent |
| Read follower on the database | created | absent |
| Redis | split — cache and queue in separate databases | one database, `noeviction` |

**Restore testing is NOT decided by this axis, and the reason is worth keeping.** A rehearsal proves two different things: that the restore mechanism works, which generalizes across every environment sharing one backup configuration, and that restore time fits the recovery objective, which does not — that time scales with data volume. AWS Well-Architected REL09-BP04 ties the test to the *workload's* objective rather than to each environment, and names "assuming that the time to restore or recover data from a backup falls within the RTO for the workload" as the anti-pattern. So the rehearsal runs on the largest environment and covers the rest as the worst case, and which environment that is cannot be derived from whether an environment is productive. It has its own input, `run_restore_rehearsals`.

The read-only MongoDB credential is off this axis for the same shape of reason: the question is whether an environment's data is safe to copy to a laptop, which is not the same question as whether the environment is productive. It has its own input too.

**One input naming what the environment IS stays inside the boundary rule; four per-resource toggles would not.** The rule forbids a variable through which a caller can omit a mandatory resource. `productive = false` does not omit a resource from an environment that needs it — it selects the shape of an environment that is a different kind of thing, the same way the deploy gate and the database shape already select from it.

The Redis split follows from the same axis and for a concrete reason worth keeping at the declaration: a single database serving both roles must never evict, because discarding a queued job to make room for a cached value loses work. A productive environment separates them so the cache can evict under pressure while the queue cannot.

## Order of work

Most isolated to most coupled. Each is one pull request, applied to all four environments before merging.

| # | Component | Consumers to rewrite | Note |
|---|---|---|---|
| 1 | Redis | none | pure leaf; nothing reads its outputs |
| 2 | S3 bucket | one | the move DELETES `s3_bucket_arn`, a round trip that exists only because the bucket is outside |
| 3 | ECR | one ordering edge | |
| 4 | Backup + deploy key | none | two single-call files |
| 5 | OpenSearch | none | introduces `productive`; beta and demo keep no domain |
| 6 | Restore rehearsals | none | own input, not the `productive` axis |
| 7 | MongoDB Atlas | the URL parameter | |
| 8 | RDS | the internal DNS records, the pooler backend | the data — moved last |
| 9 | Lambda autoscaling + scheduler, monitoring | none | held for the capacity providers — see below |

**The capacity providers and `compute.tf` are outside this order.** The binding names both the cluster the module creates and modules that consume the module's own outputs, so pulling it inside recreates the cycle it was extracted to break. It moves only when the capacity provider modules move with it.

### The shape component 8 takes

The database is the one component whose environments run two different engines: `beta-001` is a single PostgreSQL instance (`modules/rds_instance`), the other three are Aurora clusters (`modules/rds_aurora_cluster`). Both live in the module behind an input naming which engine the environment runs, and the primary endpoint is whichever of the two produced one. The per-instance map — identifiers, classes, Availability Zones, retention — is passed verbatim, so every state key survives the move.

**The move DELETES two round trips, which is the clearest signal it belongs inside.** `source_db_arn` is an input today only because the backup, already in the module, needs the ARN of a database declared outside it. The pooler's backend `host` is the same shape: each backend entry names the DNS record the stack creates. Once the database and its records are inside, both stop being inputs — the module resolves them internally. Each backend entry then declares which endpoint it reaches (the primary or the replica) rather than carrying an FQDN, which is what it meant all along.

The replica record follows `productive`, per the axis above: only an environment with a read follower has a reader endpoint for it to point at. The retired CloudWatch log groups stay in their stacks — a group kept only so its retention window runs out is a lifecycle deliberately outside the component, which is exactly the residue the boundary rule leaves in the stack.

**Lambda autoscaling and monitoring are held for that same move, each for its own reason.** The lambda binds to the capacity providers by ASG name and packages a per-stack `config.yml` through `path.module`, so it cannot cross the boundary while they are outside it. Monitoring would make the module relay nine values, most of them describing the database identifiers — which become derivable the moment RDS moves. Neither is blocked by anything in this plan; both wait on work the plan deliberately excludes.

## Why the database can move now

The database sat outside the module while every environment was moved onto its own encryption key, because that migration replaced each cluster and copied its data across — a component being replaced is not a component to re-address at the same time.

Every environment now runs on its own key and every predecessor is destroyed, so that reason is spent. What remains of it is a caution rather than a blocker: RDS and MongoDB carry the data, so their plans are the ones where anything other than a pure relocation stops the work rather than prompting a second look.

## The invariant every one of these is checked against

**A plan reports no additions, no changes and no destructions — only relocations.** The resource is the same one, addressed differently, so any other number means the move is not equivalent and must not be applied.

That check is what makes the sequence safe to run at this pace, and it carries more weight on two of the components than on the rest. Redis and MongoDB Atlas are external subscriptions rather than resources inside the AWS account, so a plan proposing to create one is proposing to bill for a second.

## What each pull request does

Declare the component in `modules/app` with the values that genuinely differ as inputs; replace the stack's file with `moved` blocks; pass the values from the stack's `main.tf`. What every environment shares stops being repeated — the Redis payment method, persistence, replication, source range and alerts were identical in all four and are now held once.

Where a stack consumed the component's outputs, the module publishes them and the stack reads them from there. Where the stack was passing something back into the module that the module could own, the input disappears.
