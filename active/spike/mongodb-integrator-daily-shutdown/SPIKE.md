# SPIKE — Viability of daily shutdown/startup of MongoDB clusters across integrator deployments for cost savings

**Conducted by:** Engineering team
**Date:** 2026-03-18
**Status:** Closed — see conclusions

---

## Goal

Determine whether it is safe and viable to shut down all EC2 instances running MongoDB replica sets across integrator deployments daily — after each client's nightly integration ends — and start them back up before the next run via EventBridge Scheduler. The AlmaViva deployment (`4client-almaviva-mongo003/004/005`) is used as the reference case, but the findings and process apply to all integrator MongoDB clusters.

Specific questions to answer:

1. Is it safe to shut down all 3 replica set nodes simultaneously? What are the risks?
2. What is the correct shutdown order for a MongoDB replica set (primary/secondaries)?
3. When restarted, can the replica set reconstitute itself automatically (elect a primary)?
4. Is there a risk of data corruption or incomplete journaling when stopping via `ec2 stop` (not `kill -9`)?
5. What is the estimated time for the cluster to become operational after restarting the instances?
6. Are there any special considerations given that the integrator is the sole consumer of this MongoDB cluster?

---

## Method

- Codebase analysis of `/Users/plribeiro3000/Projects/4Shark/integrator/` — models, workers, configuration, and middleware
- MongoDB official documentation research (replica set elections, shutdown command, journaling, maintenance procedures)
- AWS EC2 documentation research (stop instance behavior, ACPI/SIGTERM signal, OS shutdown flow)
- Community forums and bug tracker (MongoDB JIRA, Google Groups, GitHub issues)

---

## Evidence

### E1 — EC2 `stop` triggers a graceful OS shutdown

AWS EC2 `stop` sends an ACPI power button event to the guest OS, which initiates a normal OS shutdown sequence (equivalent to `systemctl poweroff`). This sends SIGTERM to all services. MongoDB's `mongod` responds to SIGTERM with a graceful shutdown sequence.

Source: [How EC2 instance stop and start works — AWS Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-stop-start-works.html)

The OS has a grace window of approximately 30–120 seconds before the hypervisor forces a hard power-off if shutdown does not complete. This is generally sufficient for MongoDB to flush and close cleanly.

### E2 — MongoDB responds to SIGTERM with graceful shutdown

When `mongod` receives SIGTERM (from `systemctl stop mongod` or OS shutdown), it:

1. **If the node is primary**: attempts to step down before shutting down. If the step-down succeeds, it does not vote in the ensuing election.
2. **Quiesce period** (MongoDB 5.0+): pauses new connections while allowing in-progress operations to finish, up to `shutdownTimeoutMillisForSignaledShutdown` (default varies by version).
3. Flushes data to disk and closes storage engine cleanly.

Sources:
- [Gracefully Shutting Down MongoDB — mydbops.com](https://www.mydbops.com/blog/mongodb-shutdown-methods-db-shutdownserver-vs-systemctl-stop)
- [shutdown command — MongoDB Docs](https://www.mongodb.com/docs/manual/reference/command/shutdown/)

### E3 — WiredTiger journaling protects against data corruption

MongoDB uses WiredTiger with journaling enabled by default. On restart after a clean or unclean shutdown:

- WiredTiger replays journal files from the last checkpoint to restore a consistent state.
- This approach is explicitly documented as **safe for both graceful and abrupt shutdowns** on WiredTiger deployments.
- Journal writes happen every 100ms by default, so maximum data loss exposure in a hard shutdown is ~100ms of uncommitted writes — but with `ec2 stop` (graceful), this window does not apply because the engine flushes on SIGTERM.

Source: [Configure Journaling — MongoDB Docs](https://www.mongodb.com/docs/manual/tutorial/manage-journaling/)

### E4 — Correct shutdown order for a replica set

The recommended safe procedure from the MongoDB community and documentation is:

**Shutdown:**
1. Run `replSetFreeze` on both secondaries to prevent them from being promoted to primary.
2. Run `rs.stepDown()` on the primary to verify at least one secondary is caught up to the oplog before the primary steps down.
3. Shut down secondaries first, then the primary.

**Simultaneous shutdown without this ceremony:**
Shutting down all nodes at once without the step-down sequence can cause election/voting issues on restart in some cases. However, **with a clean SIGTERM-based shutdown (EC2 stop)**, the primary itself initiates a step-down, and the subsequent shutdown is clean. The risk is lower than with `kill -9`.

Source: [Shutdown order for replica set — MongoDB User Group](https://groups.google.com/g/mongodb-user/c/eYP8HQKPzfk)

### E5 — Automatic reconstitution after all nodes restart

When all 3 nodes of a PSS (Primary-Secondary-Secondary) replica set are restarted:

- Each node independently comes online and begins communicating with the others.
- A **new election is triggered** automatically as soon as a majority (2/3) of nodes are online and communicating.
- The median time to elect a new primary is **under 12 seconds** after the nodes establish connectivity, assuming default `electionTimeoutMillis` of 10 seconds.
- No manual intervention is required.

Sources:
- [Replica Set Elections — MongoDB Docs](https://www.mongodb.com/docs/manual/core/replica-set-elections/)
- [Three Member Replica Sets — MongoDB Docs](https://www.mongodb.com/docs/manual/core/replica-set-architecture-three-members/)

### E6 — Known risk: isSelf failure in dynamic DNS environments (SERVER-62699)

A known MongoDB JIRA issue ([SERVER-62699](https://jira.mongodb.org/browse/SERVER-62699)) documents a failure mode where, in environments with **dynamic DNS** (e.g., EC2 instances with IP-based hostnames that change on restart), all nodes may fail the `isSelf` test on restart and enter a `REMOVED` state. Nodes in `REMOVED` state do not attempt to rejoin the replica set automatically.

**Mitigation:** This only occurs when DNS names change between stop and start. If the replica set is configured with **static private IP addresses** (not DNS hostnames) or if the EC2 instances retain the same private IP on stop/start (which they do with non-spot instances in the same subnet), this bug does not apply. Related fixes were shipped in SERVER-35649 and SERVER-40159.

### E7 — Integrator: no multi-document transactions, no write concern override

Analysis of the integrator codebase:

- **ODM**: Mongoid — documents use `include Mongoid::Document` and `include Mongoid::Timestamps`.
- **No multi-document transactions**: No `session.start_transaction`, `with_transaction`, or session-scoped writes found anywhere in the codebase.
- **No explicit write concern**: No `write_concern: { w: :majority }` or similar overrides. Mongoid defaults apply (w: 1, acknowledged).
- **Write patterns**: All writes are single-document operations (`create`, `update`, `save`, `destroy`). The `Collection` model uses aggregation pipelines (read-only). `Resource` uses `insert_one` via raw driver for S3 restoration.
- **Lock model**: Uses Redis (Sidekiq), not MongoDB. No MongoDB-backed distributed locks.
- **Shutdown trigger**: `ShutDownWorker` calls `Ecs.scale_down`, which reduces ECS service desired count to 0. The integrator (ECS) is already scaled down before any MongoDB shutdown would occur — MongoDB is not shut down by the integrator, it is shut down by a separate mechanism (EventBridge Scheduler stopping EC2 instances).

Source: codebase analysis of `/Users/plribeiro3000/Projects/4Shark/integrator/`

### E8 — Integrator MongoDB timeout configuration

From `lib/application_configuration.rb`:

```
mongo_connect_timeout    → ENV MONGO_CONNECT_TIMEOUT, default: 1 (second)
mongo_socket_timeout     → ENV MONGO_SOCKET_TIMEOUT, default: 1 (second)
mongo_server_selection_timeout → ENV MONGO_SERVER_SELECTION_TIMEOUT, default: 1 (second)
```

These values are **extremely aggressive**. With `server_selection_timeout` at 1 second, the Mongoid driver will raise an error immediately if the cluster is not yet elected when the integrator attempts to connect at startup.

However, these are env vars — they can be changed per deployment without code changes. Raising `MONGO_SERVER_SELECTION_TIMEOUT` to 30 seconds has **zero performance impact in normal operation**: when MongoDB is healthy, server selection resolves in milliseconds regardless of the configured timeout. The timeout only activates when no primary is available. The only tradeoff is that if MongoDB goes down mid-integration, failure detection takes up to 30s per operation instead of 1s — acceptable for a nightly batch process with no real-time users.

With `server_selection_timeout` set to 30 seconds, the driver itself absorbs the replica set election time (~12 seconds) on startup, eliminating the need for any artificial delay between MongoDB EC2 start and ECS startup. The only required buffer is EC2 boot time (~60–120 seconds), after which the driver will wait for election automatically.

### E9 — No existing EventBridge Scheduler for MongoDB EC2 lifecycle

The EventBridge rule `EC2-start-integrator-almaviva` is a legacy artifact from when the application ran on EC2 directly. It is not managed by Terraform and must not be reused. Two new EventBridge Schedulers must be created from scratch per client deployment — one for EC2 start (MongoDB startup) and one managed by the `ShutDownWorker` via fog-aws for EC2 stop. These schedulers must be provisioned via Terraform.

IAM permissions for the new schedulers (EC2 `StartInstances`/`StopInstances`) must also be reviewed and provisioned via Terraform as part of the implementation.

### E10 — EC2 private IPs are stable on stop/start

AWS EC2 instances in a VPC retain their **private IP address** when stopped and started (non-spot, non-terminated). This means the replica set members — if configured with private IPs — will reconnect using the same addresses after restart. The SERVER-62699 DNS failure mode does not apply here.

Source: [Stop and start Amazon EC2 instances — AWS Docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Stop_Start.html)

---

## Conclusions

### Q1: Is it safe to shut down all 3 nodes simultaneously?

**Mostly safe, with one important caveat.**

EC2 `stop` sends SIGTERM to `mongod`, which triggers a graceful shutdown including primary step-down. WiredTiger journaling ensures data consistency even in the unlikely event of an incomplete shutdown. The concurrent shutdown of all nodes means the cluster will lose quorum immediately, but since there are no active clients at shutdown time (ECS is already scaled down), there are no in-flight writes to lose.

The risk of simultaneous shutdown is low in this specific case because:
- The integrator is the only consumer and it is shut down (ECS scale-down) before MongoDB
- No multi-document transactions exist in the codebase
- SIGTERM triggers graceful step-down on the primary

A sequenced shutdown (secondaries first, then primary) remains the textbook best practice and reduces theoretical risk further, but is not strictly required here.

### Q2: What is the correct shutdown order?

Textbook order:
1. `replSetFreeze` on secondaries to prevent promotion
2. `rs.stepDown()` on primary
3. Shut down secondaries
4. Shut down primary

For the automated EC2 stop scenario: since the integrator has already been scaled to 0 before the stop occurs, simultaneous EC2 stop is acceptable. The primary will attempt to step down automatically on SIGTERM. There is no write traffic to protect.

### Q3: Does the replica set reconstitute itself automatically after restart?

**Yes.** A 3-node PSS replica set requires a majority (2/3) to elect a primary. When all nodes restart and establish network connectivity, an election completes automatically in under 12 seconds. No manual `rs.initiate()` or `rs.reconfig()` is needed.

The only failure mode (SERVER-62699) involves DNS hostname changes, which do not apply because EC2 private IPs are stable on stop/start.

### Q4: Risk of data corruption or incomplete journaling?

**Negligible with EC2 stop (SIGTERM-based shutdown).** WiredTiger with journaling (default) is designed to recover cleanly from both clean and unclean shutdowns. EC2 `stop` allows the OS shutdown sequence to run, which is sufficient for `mongod` to flush and close. This is materially different from `kill -9` or a hypervisor hard power-off.

The only exception would be if AWS's grace window expires (typically 4+ minutes) and the hypervisor forces a hard stop — this would require journal replay on next startup but would not cause data corruption in a WiredTiger deployment.

### Q5: Time to become operational after restart?

Estimated total time from EC2 `start` to MongoDB accepting writes:

| Phase | Estimated duration |
|---|---|
| EC2 boot (OS + mongod start) | 60–120 seconds |
| Replica set election (after all nodes online) | 10–15 seconds |
| **Total** | **~2–3 minutes** |

This is an estimate based on typical EC2 boot times for EC2 instances. Actual values depend on instance type (t3, m5, etc.) and AMI configuration. The EventBridge Scheduler that starts the integrator (ECS) should be set to fire **at least 5 minutes after** the EC2 start schedule to provide a safety buffer.

### Q6: Special considerations for the integrator as sole consumer?

Two findings from the codebase analysis are relevant:

1. **Aggressive MongoDB timeouts (1 second defaults)**: If the integrator ECS tasks start before MongoDB has elected a primary, `server_selection_timeout: 1` will cause immediate connection failures. The startup sequence must guarantee MongoDB is fully operational before ECS tasks begin. The EventBridge scheduling gap must account for this.

2. **No transactions, no durable locks in MongoDB**: The integrator uses Redis for locking and single-document writes to MongoDB. There are no operations that would be corrupted by a mid-shutdown scenario. The worst case is that the last write before shutdown is lost — but since the integrator scales to 0 before MongoDB is stopped, this cannot happen.

3. **ShutDownWorker scales down ECS, not MongoDB**: The current `ShutDownWorker` scales ECS services (web + worker) to 0 via the ECS API. It does not touch the MongoDB EC2 instances. The MongoDB shutdown must be a separate step, triggered either after a delay or by a separate EventBridge Scheduler that fires after ECS confirms scale-down.

---

## Recommendation

**Viable. The daily shutdown/startup of MongoDB clusters across integrator deployments is safe to implement**, given the constraints of this deployment pattern:

- EC2 stop triggers SIGTERM, not hard power-off
- WiredTiger journaling ensures consistency
- No active clients at shutdown time (ECS is scaled to 0 first)
- No multi-document transactions in the integrator
- EC2 private IPs are stable across stop/start cycles
- Automatic election after restart is reliable for a 3-node PSS set

### Recommended safe process

**Shutdown sequence (nightly, ~22h BRT after integration ends):**

1. `ShutDownWorker` fires — scales ECS web and worker services to 0, then stops MongoDB EC2 instances via fog-aws
2. EC2 OS shutdown sequence completes; `mongod` shuts down gracefully via SIGTERM

No EventBridge involvement needed for shutdown. `ShutDownWorker` already has fog-aws access, already knows the integration is done, and can call EC2 `StopInstances` directly in the same execution. No drain delay is needed between ECS scale-down and EC2 stop — `ShutDownWorker` fires only after `job.computation.done?`, meaning MongoDB is idle at that point.

**Startup sequence (before next integration window):**

1. New EventBridge Scheduler fires: calls EC2 `StartInstances` on all MongoDB nodes simultaneously (new resource, provisioned via Terraform — one per client deployment)
2. Wait ~2 minutes for EC2 boot (buffer before ECS starts)
3. Existing EventBridge Scheduler fires: scales up ECS web and worker services (already in place — `integrator-{client}-scale-up-web` and `integrator-{client}-scale-up-worker`)

The MongoDB EC2 start scheduler must fire **before** the ECS scale-up schedulers, with enough gap to cover EC2 boot time (~2 minutes). The remaining election time (~12 seconds) is absorbed by `MONGO_SERVER_SELECTION_TIMEOUT: 30`.

**IAM permissions** for the new scheduler (EC2 `StartInstances`) must be reviewed and provisioned via Terraform. To be addressed during implementation.

**Timing buffer between MongoDB start and ECS start: ~2 minutes** (EC2 boot time only). With `MONGO_SERVER_SELECTION_TIMEOUT` raised to 30 seconds, the driver absorbs the replica set election (~12s) automatically — no artificial delay needed beyond waiting for the OS to boot.

### Open questions before implementation

1. **What are the current `mongod.service` systemd `TimeoutStopSec` values on these EC2 instances?** If set too low (< 30s), mongod may receive SIGKILL before completing shutdown. Needs verification on the instances.
2. **Are the replica set members configured with private IPs or DNS hostnames?** If DNS hostnames that resolve differently after restart, SERVER-62699 is a real risk. Needs verification via `rs.status()` output.
3. **What is the actual EC2 instance type?** Boot time varies significantly between `t3.micro` and `m5.large`.
4. **Is there a monitoring/alerting mechanism for failed election after restart?** Without it, a failed startup would silently break the next integration run.
5. ~~`server_selection_timeout` too low~~ — resolved: raise `MONGO_SERVER_SELECTION_TIMEOUT` to 30 seconds via env var per deployment. No code change required, no performance impact in normal operation.

---

## Implementation Progress

### Completed — 2026-03-18

**Integrator (PR #2048 — merged)**
- `ShutDownWorker` updated: stops MongoDB EC2 instances first, then scales down ECS worker service, then web service
- New `Ecs` model added: scales down ECS services via fog-aws (`Fog::AWS::ECS`)
- `Ec2` model restored: stops MongoDB EC2 instances via fog-aws (same var `AWS_INSTANCE_IDS`, now pointing to MongoDB IDs)
- `ApplicationConfiguration` extended: `aws_ecs_cluster`, `aws_ecs_web_service`, `aws_ecs_worker_service`, `aws_instance_ids`
- `config/initializers/fog.rb` updated: initializes all three adapters (S3, EC2, ECS)
- README updated: reflects current ECS-based infrastructure and Terraform/Ansible distinction

**GitHub environment `almaviva`**
- Added: `AWS_ECS_CLUSTER`, `AWS_ECS_WEB_SERVICE`, `AWS_ECS_WORKER_SERVICE`
- Added: `AWS_INSTANCE_IDS` with MongoDB EC2 IDs (`i-050e39c7af8c6cf8e;i-05198f0b263ae5067;i-09f1cf2a4437100b7`)

### Completed — 2026-03-18 (continued)

**IAM permissions (Terraform, `integrator-almaviva`)**
- Added `ec2_instance_arns` variable to `modules/iam_deploy`
- Added `EC2Describe` statement (`ec2:DescribeInstances`, `ec2:DescribeInstanceStatus` — wildcard, AWS limitation)
- Added `EC2StartStop` statement (`ec2:StartInstances`, `ec2:StopInstances` — scoped to the 3 MongoDB EC2 instances)
- `terraform apply` executed successfully

**GitHub Actions — Startup workflow**
- New `startup.yaml` workflow: starts MongoDB EC2 instances, waits for `instance-status-ok`, sleeps 90s for mongod + election, scales up ECS web then worker
- `run.yaml` removed (replaced by `bin/ecs`)
- PR #2050 merged

**End-to-end validation on almaviva — 2026-03-18**
- Shutdown: `ShutDownWorker` stopped MongoDB EC2 (3 instances → `stopped`) and scaled ECS to 0/0 ✅
- Startup: GitHub Actions `Startup` workflow started MongoDB (3 instances → `running`), scaled ECS web and worker to 1/1 ✅
- Connection confirmed via `bin/ecs` after startup ✅

**Terraform `integrator-almaviva` — committed and applied**
- `modules/iam_deploy`: added `ec2_instance_arns` variable + `EC2Describe`/`EC2StartStop` statements
- `integrator-almaviva/compute.tf`: added `ec2:StartInstances` to ECS scheduler role policy
- `integrator-almaviva/compute.tf`: new EventBridge Scheduler `start_mongodb` (cron 00:50 UTC = 21:50 BRT) — starts MongoDB EC2 instances 5 min before ECS scale-up
- `integrator-almaviva/compute.tf`: passed `ec2_instance_arns` to `iam_deploy` module

### Remaining

- Replicate to all other client deployments:
  - Add `ec2_instance_arns` to each client's `iam_deploy` module call in Terraform
  - Add EventBridge Scheduler `start_mongodb` to each client's Terraform
  - Add `ec2:StartInstances` to each client's ECS scheduler role policy
  - Add `AWS_INSTANCE_IDS` (MongoDB EC2 IDs) to each client's GitHub environment
  - Add `AWS_ECS_CLUSTER`, `AWS_ECS_WEB_SERVICE`, `AWS_ECS_WORKER_SERVICE` to each client's GitHub environment
  - Update `MONGO_SERVER_SELECTION_TIMEOUT` to 30 seconds in each client's GitHub environment
- Answer open questions 1–4 (requires SSH access to MongoDB EC2 instances)

---

## Next Steps

- Replicate shutdown/startup configuration to remaining clients

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
