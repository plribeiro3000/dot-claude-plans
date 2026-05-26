# SPIKE — CloudWatch monitoring and alerting for 4Shark infrastructure

**Conducted by:** Paulo Ribeiro
**Date:** 2026-03-27
**Status:** Closed — see conclusions

---

## Goal

What CloudWatch monitoring and alerting should 4Shark implement, what does it cost, and how should it be structured to avoid alert fatigue?

The investigation was needed because the platform has no active monitoring: no alarms, no SNS topics, no notification infrastructure. If any production service goes down, nobody is notified.

### Guiding Principle — Infrastructure gaps only

**Alert only on infrastructure failures that the application layer cannot detect.**

The application already has Rollbar for real-time error monitoring. If Redis runs out of keys, if memory spikes, if a database query fails — the app throws an exception that Rollbar catches. These do NOT need CloudWatch alarms.

What needs CloudWatch alarms are **silent infrastructure failures** — things that break without generating application errors. Real example: autoscaling Lambdas lost Redis connectivity and failed silently for a week. Workers stopped scaling, but no application error was raised because the Lambdas are external to the app. This went undetected until manual investigation.

The rule: **if the app can't know about it, CloudWatch must.**

---

## Method

- Analyzed all existing Terraform modules and environment configurations in the terraform repository
- Audited CloudWatch Log Groups, alarms, SNS topics, and related resources
- Reviewed AWS Chatbot and Slack integration pricing
- Applied SRE/DevOps community best practice: alert only on conditions that require immediate human action
- Benchmarked alarm volume against alert fatigue thresholds to arrive at a sustainable alarm count

---

## Evidence

### Current State — No monitoring infrastructure exists

Audit of the terraform repository revealed:

- **CloudWatch Log Groups**: ~15 exist (ECS services, Lambdas, RDS, CodeDeploy, Keycloak)
- **CloudWatch Metric Alarms**: exactly 1 — in `modules/ecs_cluster/main.tf` for ECS scale-down (operational automation, not monitoring)
- **SNS Topics**: zero — no notification infrastructure at all
- **AWS Chatbot**: not configured
- **Result**: no human is notified if any production service goes down

### Monitoring that already exists outside CloudWatch

| System | Where alerts are configured |
|---|---|
| Redis Cloud | Atlas platform — 80% dataset size, 80% connections |
| MongoDB Atlas | Atlas platform — M10 in all environments |
| Rollbar | Rollbar platform — application errors and exceptions |
| CodeDeploy | Pipeline visibility — deployment failures visible in CI |

These systems do not need CloudWatch alarms.

### App environments in scope (production, cannot go down)

Four environments: `app-atento-001`, `app-shared-001`, `app-demo-001`, `app-beta-001`

Each environment contains:

| Component | Atento / Shared | Demo / Beta |
|---|---|---|
| ECS Services | 8 total (web + workers), 3-4 active | 8 total, 3-4 active |
| ALB | 1 with blue/green CodeDeploy | 1 with blue/green CodeDeploy |
| RDS | Aurora PostgreSQL 2x t4g.large | Demo: 1x t3.medium / Beta: t3.micro PG 17.6 |
| OpenSearch | 2x t3.small each | Not present |
| Redis Cloud | 2 databases (Cache + Sidekiq) | 1 database |
| MongoDB Atlas | M10 | M10 |
| Lambdas | 3-5 autoscaling lambdas | 3-5 autoscaling lambdas |
| Scheduled Tasks | None | 4 cron jobs each |
| Log retention | 30 days | 7 days |

### Known performance issue

OpenSearch in Atento and Shared environments has been observed hitting ~80% CPU at times. This was identified through manual investigation, not through any alarm.

### Notification architecture chosen

```
CloudWatch Alarm → SNS Topic → AWS Chatbot → Slack Channel
```

Alternatives considered and rejected:
- **PagerDuty/OpsGenie**: adds monthly cost per user, unnecessary overhead for team size
- **Email via SNS**: slower response, no threading, not integrated into team workflow
- **Lambda fan-out**: adds complexity with no benefit at this scale

AWS Chatbot is free. SNS is free at this volume. Slack integration has no additional cost.

### Alert fatigue analysis — alarm tier design

Community best practice (SRE): only alert on conditions that require immediate human action. Everything observable but not immediately actionable goes to a dashboard.

**Filtering criterion**: Rollbar covers application-level errors. CloudWatch alarms cover ONLY infrastructure failures invisible to the application.

#### Tier 1 — Alarms (Slack notification, human action required)

All thresholds were reviewed individually against AWS documentation, community best practices, and 4Shark production data (30-day CloudWatch metrics analysis). Each alarm was validated for the specific workload pattern before finalizing.

**Silent infrastructure failures — things the app cannot detect:**

| # | Alarm | Metric | Threshold | Period | Eval Periods | Statistic | Environments | Source |
|---|---|---|---|---|---|---|---|---|
| 1 | **Lambda errors sustained** | `Lambda/Errors` | > 0 (Sum) | 60s | 3 consecutive | Sum | All 4 | Community (adjusted for 1/min invocation rate) |
| 2 | **Lambda not invoked** | `Lambda/Invocations` | < 1 (Sum), `treat_missing_data = "breaching"` | 60s | 10 consecutive | Sum | All 4 | AWS recommended |
| 3 | **ECS unable to place tasks** | Metric math: `DesiredCount - RunningCount` | >= 1 | 60s | 10 consecutive | Average | All 4 (active services only) | Community (adjusted for EC2 provision time ~4 min) |
| 4 | **ECS service down** | `ECS/RunningTaskCount` (Container Insights) | <= 0 | 60s | 5 consecutive | Average | All 4 (services with desired > 0) | AWS recommended. Blue/green deploy does NOT cause RunningTaskCount = 0 (validated) |
| 5 | **OpenSearch cluster RED** | `ES/ClusterStatus.red` | >= 1 | 60s | 1 | Maximum | Atento, Shared | AWS recommended (immediate — RED requires manual recovery) |
| 6 | **OpenSearch cluster YELLOW** | `ES/ClusterStatus.yellow` | >= 1 | 60s | 5 consecutive | Maximum | Atento, Shared | AWS recommended (5 min filters transient yellow during shard redistribution) |
| 7 | **RDS storage critical** | `RDS/FreeLocalStorage` (Aurora) / `RDS/FreeStorageSpace` (Beta) | < 10 GB (Atento/Shared) / < 5 GB (Demo/Beta) | 300s | 2 consecutive | Minimum | All 4 | Community (lorenzoaiello module). Validated against current free storage: Atento 12.1 GB, Shared 12.0 GB, Demo 5.8 GB, Beta 16.9 GB |
| 8 | **RDS replication lag** | `RDS/AuroraReplicaLag` | > 1000ms (1 second) | 300s | 2 consecutive | Average | Atento, Shared | Community (100ms warning, 1000ms critical). Validated: normal operation ~15ms avg, picos up to 200ms. 30-day spikes above 1s all correlated with infrastructure changes (VPC migration) |
| 9 | **Scheduled tasks not running** | `Scheduler/TargetErrorCount` and `Scheduler/InvocationDroppedCount` | > 0 (Sum) | 300s | 2 consecutive | Sum | Demo, Beta | EventBridge Scheduler metrics. Covers scheduler → ECS API call layer. ECS task execution layer covered by alarm #3. Application errors covered by Rollbar |

**Sustained resource pressure — WEB SERVICE ONLY (workers excluded, see analysis below):**

| # | Alarm | Metric | Threshold | Period | Eval Periods | Statistic | Environments | Source |
|---|---|---|---|---|---|---|---|---|
| 10 | **ECS web CPU sustained** | `ECS/CPUUtilization` | > 80% | 60s | 5 consecutive | Average | All 4 (web service only) | AWS recommended |
| 11 | **ECS web Memory sustained** | `ECS/MemoryUtilization` | > 80% | 60s | 5 consecutive | Maximum | All 4 (web service only) | AWS recommended (threshold) + Community (Maximum statistic). PumaWorkerKiller auto-reaping at 70% provides self-healing below this threshold (deployed 2026-03-27, hotfix 3.20.2) |

**Alarm count**: 11 alarm types × 4 environments (some only apply to specific envs) = **~35-40 alarms total**

**Prerequisite**: Container Insights must be enabled on all ECS clusters (required for alarms #3 and #4). All thresholds are configurable via Terraform module variables — each environment can override defaults if needed.

**Workers (Sidekiq) — NO CPU/Memory alarms. Validated by data and literature:**

The decision to exclude CPU/Memory alarms from workers was validated through:

1. **AWS CLI verification (2026-03-27)**: All 18 T3a.medium instances run in `unlimited` mode. CPUSurplusCreditsCharged = 0.0 across all workers for the last 30 days. Average CPU on worker-commission (atento) = 1.37%, with bursts up to 48.73%. Credit balance reaches 0.0 during peaks but recharges during idle periods — no surplus charges incurred.

2. **Brendan Gregg — USE Method**: 100% CPU utilization ≠ saturation. A CPU at 100% that processes all work without growing queues is healthy. Saturation is measured by run queue length, not CPU percentage. Workers processing Sidekiq jobs at 100% CPU with stable queue depth are working as designed.

3. **T3a burstable instances and 4Shark workload pattern**: T3a.medium has a 20% CPU baseline. Above baseline, it consumes credits (24 earned/hour, 120 consumed/hour at 100%). The 4Shark worker pattern (mostly idle with processing bursts) is exactly what burstable instances are designed for — credits accumulate during idle time and are spent during bursts. Data confirms no surplus charges in 30 days.

4. **Sidekiq community (Mike Perham)**: Workers are designed to consume all available CPU when processing jobs. The relevant metric for workers is queue depth (are jobs backing up?), not CPU utilization.

5. **Cloud vs physical hardware**: No thermal throttling risk on cloud VMs. AWS manages cooling and hardware lifecycle. The cloud equivalent of thermal concern is CPU steal time, which is a hypervisor-level issue unrelated to workload CPU utilization.

**Note on T3a burstable instances**: While the current burst pattern works well (idle → burst → idle, no surplus charges), if workload patterns change to sustained high CPU (e.g., processing for 6+ continuous hours), the instances would deplete credits and start accumulating surplus charges in `unlimited` mode. This is not currently happening but worth monitoring on the dashboard. A potential future optimization would be evaluating compute-optimized instances (C5/C6i) if sustained workloads increase — separate investigation, not part of this monitoring feature.

**Removed from Tier 1** (Rollbar already covers these):
- ~~ALB 5xx errors~~ → app exceptions that cause 5xx are caught by Rollbar
- ~~ALB unhealthy targets~~ → if health check fails, the app is erroring, Rollbar catches it
- ~~RDS CPU high~~ → slow queries cause app timeouts, Rollbar catches it
- ~~RDS connections high~~ → connection pool exhaustion causes app errors, Rollbar catches it

#### Tier 2 — Dashboard (observation, no notification)

Metrics to display without alerting:
- ECS CPU and memory utilization (all services)
- OpenSearch CPU (the 80% spikes identified above)
- RDS CPU, connections, freeable memory
- ALB latency and 4xx/5xx counts (for trend analysis, not alerting)
- Lambda invocation duration and success rate
- All 4 environments on a single dashboard with tabs

### Cost projection

| Item | Count | Cost/month |
|---|---|---|
| Tier 1 alarms (11 types × 4 envs, adjusted) | ~35-40 | $3.50-4.00 |
| CloudWatch Dashboard | 1 | $3.00 |
| AWS Chatbot | 1 | Free |
| SNS Topic | 1 | Free |
| **Total** | **~35-40 alarms** | **~$6.50-7.00/month** |

Pricing source: AWS CloudWatch pricing page — $0.10 per alarm per month (standard resolution), $3.00 per dashboard per month.

Note: cost is not a constraint for this feature. Even at 100 alarms the total would be ~$13/month.

### Out of scope for first implementation

These environments have monitoring needs but are lower priority and should be addressed separately:
- VPN (Pritunl)
- Integrators (1 on ECS with CloudWatch, rest on EC2)
- Onboarding app
- Setup app

---

## Conclusions

1. **The platform has zero monitoring coverage for silent infrastructure failures.** No alarms, no SNS, no notifications. An infrastructure component can fail silently for days or weeks (as happened with Lambda autoscaling) with no detection.

2. **Rollbar covers application errors — CloudWatch must cover everything else.** The guiding principle is: if the application can detect it (exceptions, timeouts, HTTP errors), Rollbar handles it. If the failure is invisible to the application (Lambda errors, scheduler failures, capacity provider issues, storage exhaustion), CloudWatch must alert.

3. **The right alarm count is ~35-40 across 11 alarm types.** Each threshold was validated individually against AWS documentation, community best practices (CloudPosse, lorenzoaiello, Brendan Gregg USE Method, Sidekiq community), and 30-day production CloudWatch metrics. No threshold was assumed — all were researched and confirmed against real data.

4. **The notification chain is free.** SNS + AWS Chatbot + Slack costs $0. Only the alarms themselves have a cost (~$4/month).

5. **Total monitoring cost is ~$7/month.** Dashboard ($3.00) + alarms ($4.00). Cost is not a constraint — even at 100 alarms the total stays under $13/month.

6. **Web service CPU/Memory alarms at 80% with PumaWorkerKiller self-healing at 70%.** The PumaWorkerKiller auto-reaping was misconfigured (only rolling restart was active, no memory-based killing). This was fixed in hotfix 3.20.2 (deployed 2026-03-27) — workers are now killed at 70% memory usage. The CloudWatch alarm at 80% acts as a safety net: if the killer doesn't resolve the issue, the alarm notifies the team. CPU uses Average statistic (AWS recommended), Memory uses Maximum (community recommended — catches individual container spikes hidden by averaging).

7. **Worker (Sidekiq) CPU/Memory alarms are excluded — validated by data and literature.** Workers are designed to use all available CPU when processing jobs. AWS CLI verification confirmed: all T3a instances in `unlimited` mode, zero surplus charges in 30 days, average CPU 1.37% with bursts up to 48.73%. Brendan Gregg's USE Method confirms 100% utilization ≠ saturation. The relevant metric for workers is queue depth, not CPU.

8. **T3a burstable instances work for the current workload pattern but have limits.** Credit balance reaches 0.0 during peaks but recharges during idle time, resulting in no surplus charges. Worth monitoring on the dashboard. A separate investigation into compute-optimized instances (C5/C6i) may be warranted if workload patterns change.

9. **Real incident validated the infrastructure-first approach.** Autoscaling Lambdas failed for a week due to Redis connectivity loss. No application error was raised. The issue was discovered manually, long after impact.

10. **Memory bloat was discovered and fixed during this investigation.** Atento web service was hitting 99.9% memory utilization on multiple days. Root cause: PumaWorkerKiller was only configured for rolling restarts (every 6h), not memory-based auto-reaping. Memory bloat (Ruby RSS growth) accumulated between restarts. Fixed in hotfix 3.20.2 by enabling `PumaWorkerKiller.start` with 70% threshold. MALLOC_ARENA_MAX not yet configured — potential future optimization.

11. **RDS replication lag threshold validated with production data.** Normal operation: ~15ms average. All spikes > 1s in 30 days correlated with infrastructure changes (VPC migration on March 6-7). Threshold set at 1000ms (community critical level) — will not trigger during normal operation.

12. **RDS storage thresholds differentiated by environment.** 10 GB for production (Atento/Shared), 5 GB for staging (Demo/Beta). Validated against current free storage values. Aurora FreeLocalStorage is instance local disk (for temp tables/sorts), not volume storage.

13. **ECS cluster instance health alarm removed — redundant.** Service down (#4) and unable to place tasks (#3) already cover all scenarios where missing EC2 instances cause problems. A dedicated instance health alarm would generate false positives when desired=0 is intentional.

14. **OpenSearch alarms follow AWS recommended values.** RED: immediate (1 period). YELLOW: 5 minutes (filters transient redistribution). CPU goes to dashboard only.

15. **Scheduled task monitoring uses EventBridge Scheduler metrics**, not ECS task metrics. `TargetErrorCount` and `InvocationDroppedCount` cover the scheduler → API layer. ECS task placement covered by alarm #3. Application errors covered by Rollbar. Three-layer coverage without custom metrics.

16. **All thresholds configurable via Terraform module variables.** Each environment can override defaults. This was a design requirement to allow threshold tuning without code changes.

17. **A reusable Terraform module** is the right implementation approach. Define the alarm set once, instantiate per environment.

18. **Implementation should start with Atento** (most critical) and validate before rolling out to remaining environments.

---

## Actions Taken During Investigation

- **Hotfix 3.20.2** (app project): Fixed PumaWorkerKiller configuration — enabled memory-based auto-reaping at 70% threshold. PR: https://github.com/4shark/app/pull/4905. Deployed to Demo, Atento, and Shared on 2026-03-27.

## Next Steps

Implementation work is needed. Recommended path:

1. Use `@agent-planner` to create a PLAN.md for the implementation
2. The plan should cover:
   - SNS Topic + AWS Chatbot + Slack channel configuration
   - Reusable Terraform module for the 11 alarm types (all thresholds as variables with defaults)
   - Instantiation for all 4 app environments
   - CloudWatch Dashboard covering all 4 environments
   - Container Insights enablement (prerequisite for alarms #3 and #4)
3. Start with `app-atento-001` to validate alarm thresholds before full rollout
4. A second phase (separate PLAN.md) can cover VPN, integrators, onboarding, and setup

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
