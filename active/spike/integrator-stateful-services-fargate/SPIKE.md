# SPIKE — Viability of running stateful services (Redis + MongoDB) as ECS Fargate containers to eliminate EC2 costs

**Conducted by:** Engineering team
**Date:** 2026-03-19
**Status:** Research complete — pending decisions

---

## Goal

Determine whether it is viable and cost-effective to migrate all stateful services used by the integrator — currently Redis (ElastiCache) and MongoDB (EC2 replica set) — to ECS Fargate containers. The goal is to eliminate EC2 and ElastiCache costs entirely: when the integration job is not running, there are no running instances, no idle clusters, and no idle charges.

The AlmaViva deployment is the reference case. Other clients would follow once the pattern is validated.

Specific questions to answer:

1. Can ElastiCache be stopped or paused to avoid idle charges?
2. What is the community-validated approach for reducing ElastiCache costs in intermittent workloads?
3. Is Redis viable as a standalone Fargate container (no HA, no replica)?
4. Is MongoDB viable as a standalone Fargate container with ephemeral storage (no replica set, no EFS)?
5. What configuration changes would be required in the integrator to support standalone Redis and MongoDB?
6. What is the estimated cost difference between the current state and the Fargate-based approach?

---

## Context

The integrator currently runs on ECS Fargate (web + worker services), with two stateful dependencies still on "always-on" infrastructure:

- **Redis**: ElastiCache `cache.t2.small` — charges per node-hour, 24/7, regardless of usage
- **MongoDB**: 3-node EC2 replica set (`4client-almaviva-mongo003/004/005`) — EC2 charges per instance-hour, 24/7

The MongoDB EC2 shutdown/startup pattern was validated and implemented (see `spike/mongodb-integrator-daily-shutdown`). AlmaViva now shuts down MongoDB EC2 instances after each nightly run. The next step is to evaluate whether EC2 instances can be eliminated entirely in favor of Fargate containers — removing the need for OS management, patching, and instance scheduling.

---

## Method

- Research into ElastiCache stop/pause capabilities (AWS documentation + community forums)
- Research into community approaches for intermittent ElastiCache workloads
- Research into ElastiCache Serverless pricing for intermittent workloads
- Research into Redis on ECS Fargate as an ElastiCache replacement
- Analysis of integrator codebase to evaluate MongoDB standalone feasibility
- Research into MongoDB on ECS Fargate with ephemeral storage

---

## Evidence

### E1 — ElastiCache has no stop/pause feature

ElastiCache does **not** support stop or pause (unlike RDS, which does). A running ElastiCache cluster charges by the hour regardless of usage or idle state. The only ways to avoid idle charges are:
- Scale down to the smallest available node type
- Delete the cluster entirely (no equivalent of RDS stop/start)

Sources:
- [Stop elasticache bill | AWS re:Post](https://repost.aws/questions/QUJQG2cbgHSBaw9HBUpiYHnQ/stop-elasticache-bill)
- [Stopping AWS ElastiCache temporarily — feature request | AWS re:Post](https://repost.aws/questions/QU52IbQ6XnR2aavpxm-DiEGw/stopping-aws-elasticache-temporarily-feature-request)

### E2 — Community approach: snapshot → delete → recreate (not applicable here)

The most widely documented workaround for intermittent ElastiCache usage is:
1. Take a Redis snapshot before shutdown
2. Delete the cluster (billing stops immediately)
3. Recreate from snapshot before next run

An open-source CLI tool (`aws-cost-saver`) automates this pattern. Documented savings: ~70% for non-production environments running only during business hours.

**This pattern is unnecessary for the integrator**, because the integrator has no valuable data in Redis. Redis stores Sidekiq job queues and Sidekiq execution logs — both are ephemeral. When the integration ends, all queues are empty and all jobs are done. Restoring from a snapshot would restore an empty Redis anyway.

Source: [aws-cost-saver — GitHub](https://github.com/aramalipoor/aws-cost-saver)

### E3 — ElastiCache Serverless is more expensive for intermittent workloads

ElastiCache Serverless charges a minimum of **1 GB of storage (~$90/month)** regardless of actual data stored or usage. For small, intermittent workloads like the integrator, this is more expensive than a provisioned `cache.t2.small` (~$12-25/month). The community was critical of this pricing at launch.

Conclusion: ElastiCache Serverless does not solve the problem. It is designed for unpredictable high-volume workloads, not for small intermittent batch jobs.

Source: [ElastiCache Serverless HN discussion](https://news.ycombinator.com/item?id=38443559)

### E4 — Redis on ECS Fargate as ElastiCache replacement

Running Redis as a Fargate container is a documented pattern. A reference implementation exists at [epomatti/aws-ecs-redis-cluster](https://github.com/epomatti/aws-ecs-redis-cluster), created specifically as an alternative to ElastiCache for cost-sensitive workloads.

For the integrator use case:
- Redis (`redis:7-alpine`) runs as an ECS service in the same cluster as the integrator
- Starts when the cluster starts, stops when it stops
- No data to preserve: Sidekiq queues are empty when the integration ends
- No persistence needed: ephemeral container storage is sufficient
- No HA needed: the integrator is a single-consumer batch job; if Redis fails mid-run, the run fails and retries next day
- Cost: Fargate charges only while running (vCPU + memory). A small Redis container (`256 CPU / 512 MB`) costs fractions of an ElastiCache node

**Architecture: standalone Redis, no replica, no HA.**

### E5 — MongoDB on ECS Fargate: data persistence is required

MongoDB **cannot** use ephemeral Fargate storage. Codebase analysis revealed that the integrator stores critical cross-run data in MongoDB across 19 Mongoid models. Three categories must persist between daily runs:

**1. Execution watermark (`Job`, `JobMetric`)**
`DatabaseIntegrator` and `ApiIntegrator` both query `Job.ne(ends_at: nil).order_by(starts_at: :asc).last.try(:ends_at)` to determine `fetch_since` for the next run. Without prior `Job` records, the integrator falls back to `initial_fetch_date` and reprocesses the entire history on every run.

`JobMetric` stores throughput history from past runs to calculate dynamic rate limits. Without this history, anomaly detection breaks.

**2. Integration state (`Resource` and all subclasses)**
`Deal`, `User`, `Goal`, `Client`, `Group`, and ~10 other models store `external_id`, `integration_status`, and embedded `imports` (history of every attempt). The `Resource.get` method looks up existing resources by `external_id`; if not found, it creates a new one. Starting with an empty MongoDB would cause every entity to be created as new, resulting in full re-integration and duplication on every run.

**3. Configuration data**
`ExternalApplication`, `ApplicationProgrammingInterface`, `AttributeMapping`, `Authentication`, `Account`, and related models store the static configuration required for the integrator to function. These are created via admin UI and never recreated by the integration jobs.

**Conclusion: MongoDB requires persistent storage across container restarts.**

The only viable persistent storage option for Fargate is **EFS (Elastic File System)**. However, EFS introduces two problems:
- **Performance**: MongoDB is designed for local SSD. EFS is NFS-based — higher latency, different IOPS characteristics. Acceptable for low-throughput workloads, but not ideal.
- **Cost**: EFS charges per GB stored continuously. The storage cost never drops to zero, unlike ephemeral Fargate storage.

**Comparison with current EC2 stop/start model:**
The current EC2 approach stores data on EBS volumes that persist through stop/start cycles at no additional cost (EBS billing is for provisioned size, not for running vs. stopped state). EC2 + EBS is more cost-effective than Fargate + EFS for MongoDB when data persistence is required.

**Architecture verdict: MongoDB on Fargate + EFS is technically viable but not recommended.** The EC2 stop/start pattern is a better fit for MongoDB's persistence requirements. The cost savings from eliminating EC2 instances are partially or fully offset by EFS storage costs, with worse write performance as an additional trade-off.

### E6 — Self-hosted Redis and MongoDB cost comparison

For a container that runs ~4-6 hours/day, 365 days/year:

| Service | Current | Fargate container |
|---|---|---|
| Redis | ElastiCache `cache.t2.small` ~$25/month (24/7) | ~$3-5/month (usage-based) |
| MongoDB | 3x EC2 `t3.small` ~$45/month each = ~$135/month total | ~$10-15/month (usage-based, single container) |
| **Total** | **~$160/month** | **~$15-20/month** |

Estimates are approximate and depend on actual runtime hours and Fargate pricing in the target region.

### E7 — Lifecycle coupling advantage

The core advantage of Fargate-based stateful services is that their lifecycle becomes **automatically coupled** to the integrator's lifecycle. No separate EventBridge schedulers are needed for MongoDB startup (one less moving part). No EC2 instance management, OS patching, or Ansible role maintenance is needed. The GitHub Actions startup workflow becomes simpler: start ECS services, wait for health checks.

The MongoDB shutdown spike implemented a working solution for the EC2 stop/start cycle. The Fargate approach replaces this with a cleaner model: ECS manages everything, from web/worker services to Redis and MongoDB.

---

## Conclusions

### Q1: Can ElastiCache be stopped or paused?

**No.** ElastiCache has no stop/pause feature. The only way to avoid idle charges is to delete the cluster.

### Q2: What is the community approach for intermittent ElastiCache workloads?

The community uses snapshot → delete → recreate. For the integrator, the snapshot step is unnecessary (no valuable data in Redis), so the pattern simplifies to: **delete at shutdown, recreate at startup**. But this is operationally more complex than a Fargate container approach.

### Q3: Is Redis viable as a standalone Fargate container?

**Yes.** Single-node, no HA, no replica. The integrator's Redis usage (Sidekiq queues, execution logs) requires no persistence across runs. Lifecycle couples to ECS automatically. No application code changes required — only the `REDIS` env var URL changes.

### Q4: Is MongoDB viable as a standalone Fargate container with ephemeral storage?

**No.** Codebase analysis confirmed that MongoDB data must persist between daily runs. Three categories of data cannot be lost:
- `Job.last.ends_at` — used as fetch watermark; losing it causes full re-integration from `initial_fetch_date`
- `Resource` entities — losing integration state causes every entity to be re-created and duplicated
- Configuration data — `ExternalApplication`, `ApplicationProgrammingInterface`, etc. are required for the integrator to function at all

MongoDB on Fargate with **EFS (persistent NFS volume)** is technically viable, but:
- EFS has higher write latency than local SSD (EC2 EBS)
- EFS charges per GB stored continuously — the storage cost never drops to zero
- The cost advantage over EC2 + EBS is minimal or negative when factoring in EFS costs

**MongoDB should remain on EC2 with the stop/start pattern already implemented.**

### Q5: What configuration changes are required (Redis only)?

- **Redis**: Update `REDIS` env var in ECS task definition to point to the new Fargate Redis service endpoint (ECS service discovery or internal VPC DNS). No application code changes.
- **Terraform**: Remove ElastiCache module, add Redis ECS service and task definition.
- **GitHub Actions**: No changes needed — Redis lifecycle is managed by ECS automatically.

### Q6: Estimated cost difference (Redis only)?

| Service | Current | Fargate container |
|---|---|---|
| Redis (ElastiCache `cache.t2.small`) | ~$25/month (24/7) | ~$3-5/month (usage-based) |
| MongoDB (3x EC2) | ~$135/month → ~$0 with stop/start | Already handled by stop/start spike |

The Redis migration alone saves ~$20/month per client deployment.

---

## Recommendation

**Partially viable. Redis can and should be migrated to Fargate. MongoDB should remain on EC2.**

### Redis → Fargate (recommended)

Replace ElastiCache with a `redis:7-alpine` Fargate service in the integrator ECS cluster. No application code changes — only `REDIS` env var update. The Redis service lifecycle is automatically coupled to ECS: starts when the cluster starts, stops when it stops. No idle charges.

### MongoDB → stays on EC2 (recommended)

MongoDB data is not ephemeral. `Job`, `Resource`, and configuration data must persist between daily runs. The EC2 stop/start pattern (already implemented for AlmaViva) is the correct solution:
- EBS volumes persist data across stop/start cycles at no additional cost
- Local SSD performance vs EFS NFS
- No architectural complexity of EFS volumes or service discovery for MongoDB

The vision of "everything on Fargate with no EC2" is compelling but does not apply to MongoDB without an external managed database (e.g., MongoDB Atlas) handling the persistence layer.

### Future path for MongoDB (if EC2 elimination is a hard requirement)

If the goal is to fully eliminate EC2 for MongoDB, the right path is **MongoDB Atlas** (managed service):
- Handles persistence, backups, and HA externally
- Can be connected to Fargate tasks via network peering
- Costs per cluster-hour, but has a serverless tier that bills per operation
- Eliminates all OS/patching concerns

This is a separate, larger decision and is out of scope for the current cost optimization work.

---

## Open Questions

1. **Service discovery**: How will the integrator locate the Redis and MongoDB Fargate tasks at runtime? Options: ECS Service Discovery (AWS Cloud Map), internal ALB, or hardcoded task IP via environment injection. Service discovery is the cleanest approach but adds setup complexity.
2. **Container startup ordering**: ECS does not guarantee that Redis and MongoDB containers are healthy before the web/worker services start. A health check + dependency mechanism is needed (e.g., startup grace period, retry logic in the integrator, or ECS dependency conditions).
3. **MongoDB data initialization**: Does the integrator require any MongoDB initialization (indexes, collections) before the first job runs? If so, this must happen as part of the ECS startup sequence (a Rails migration-equivalent for MongoDB).
4. **Single-node replica set initialization**: Starting a single-node replica set in a container requires running `rs.initiate()` at startup. This can be done via an init script in the Docker entrypoint.
5. **Fargate task sizing**: What CPU/memory configuration is appropriate for Redis and MongoDB under the integrator's typical workload?

---

## Next Steps

- Create PLAN.md for the Fargate migration once open questions 1–4 are resolved
- Validate on AlmaViva before replicating to other clients
- The MongoDB EC2 shutdown/startup pattern (implemented in PR #2048 + Terraform) remains in place for all non-AlmaViva clients until they are migrated

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
