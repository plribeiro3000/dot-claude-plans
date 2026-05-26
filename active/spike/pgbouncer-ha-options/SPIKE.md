# SPIKE — PgBouncer HA Options for app-atento-001

## Investigation question

What options exist to make the PgBouncer on app Atento 001 more resilient to host failures and easier to operate (observability, persistent logs), comparing cost, RTO, operational complexity, and compatibility with Rails 8 + Aurora PostgreSQL 15?

---

## Sources consulted

- [AWS EC2 Automatic Instance Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html) — comparative table simplified vs CloudWatch action-based recovery; text on relative RTO
- [AWS CloudWatch Action Based Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/cloudwatch-recovery.html) — `StatusCheckFailed_System` metric, alarm configuration, limitation with Auto Scaling groups
- [AWS Simplified Automatic Recovery](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html) — enabled by default, limitations with Auto Scaling groups
- [AWS Auto Scaling Health Checks](https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html) — instance replacement behavior, wait logic
- [AWS ECS Fargate Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html) — valid CPU/memory combos table, required awsvpc networking, supported log drivers
- [AWS Fargate Pricing](https://aws.amazon.com/fargate/pricing/) — per vCPU-second and per GB-second rate for Linux/X86 in us-east-1
- [AWS NLB Pricing](https://aws.amazon.com/elasticloadbalancing/pricing/) — NLB hourly rate $0.0225/hr and TCP LCU $0.006 per NLCU
- [AWS RDS Proxy for Aurora](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.html) — PostgreSQL limitations, port 5432, CancelRequest, pinning
- [AWS RDS Proxy Pinning](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html) — pinning conditions for Aurora PostgreSQL
- [AWS RDS Proxy Planning](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-planning.md) — text on Aurora failover; reduction of DNS propagation delays
- [AWS RDS Proxy Concepts](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.howitworks.html) — multiplexing, pinning, multi-AZ proxy infrastructure
- [economize.cloud — t3a.micro pricing](https://www.economize.cloud/resources/aws/pricing/ec2/t3a.micro/) — t3a.micro on-demand price in us-east-1
- [AWS ELB Features Comparison](https://aws.amazon.com/elasticloadbalancing/features/) — comparative table of supported protocols by load balancer type
- [AWS NLB Listeners](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html) — protocols and ports supported by NLB listeners
- [AWS How ELB Works](https://docs.aws.amazon.com/elasticloadbalancing/latest/userguide/how-elastic-load-balancing-works.html) — 60s TTL of the ELB DNS entry; NLB flow hash
- [AWS Cloud Map Service Creation](https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html) — TTL configurable on create-service; example showing TTL=60 as the CLI default
- AWS API — snapshot of the environment (instance, Aurora cluster, ECS cluster, ASGs, existing task definition)

---

## Findings

### Finding 1: Current state — simplified automatic recovery is enabled, but no CloudWatch recovery alarm exists

**Evidence:**

AWS API query returned:

```json
{
  "InstanceId": "i-0b6f70bc905727770",
  "Type": "t3a.micro",
  "AZ": "us-east-1a",
  "State": "running",
  "AutoRecovery": "disabled"
}
```

And:

```json
{
  "AutoRecovery": "default",
  "RebootMigration": "default"
}
```

The property `MaintenanceOptions.AutoRecovery = "default"` means simplified automatic recovery is active (the `"default"` value enables the standard behavior, which includes recovery on supported instances). The `Monitoring.State = "disabled"` field reflects only that CloudWatch detailed monitoring is off — not recovery.

There is no CloudWatch alarm configured for `i-0b6f70bc905727770`:

```
aws cloudwatch describe-alarms --alarm-name-prefix "pgbouncer-atento"
→ MetricAlarms: [], CompositeAlarms: []
```

The reported incident (10 min of unavailability, `StatusCheckFailed_System=1`, auto-recovery with reboot) is the expected behavior of simplified automatic recovery: AWS detects the hardware failure, attempts to migrate the host, and the process appears as an unplanned reboot to the instance.

**Source:** `aws ec2 describe-instances` + `aws cloudwatch describe-alarms` (direct API reads)

**Significance:** Current protection is simplified automatic recovery without a CloudWatch alarm. The incident was contained by that mechanism, but it took ~10 minutes of downtime. There is no SNS visibility for the recovery event, and PgBouncer logs only live in the instance journald — when the host is lost, diagnostic context is lost.

**Verification:**
- URL fetched: N/A (direct AWS API)
- Verbatim quote checked: N/A (API response JSON)
- Quote substring confirmed at: direct output of `describe-instances` and `describe-alarms`

---

### Finding 2: RTO difference between simplified automatic recovery and CloudWatch action-based recovery

**Evidence:**

AWS documentation presents a comparison table with the following verbatim line:

> | Recovery time | Standard recovery attempt | Faster recovery attempts than simplified automatic recovery |

(table row in `https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html`, section "Differences between simplified automatic recovery and CloudWatch action based recovery")

Additionally, on CloudWatch action-based recovery:

> "CloudWatch action based recovery provides to-the-minute recovery response time granularity and Amazon Simple Notification Service (Amazon SNS) notifications of recovery actions and outcomes."

And on simplified automatic recovery:

> "Simplified automatic recovery is enabled by default on all supported instances during instance launch."

Both simplified and CloudWatch action-based recovery share the same critical limitation:

> "Limitations: Auto Scaling: Instances that are part of an Auto Scaling group"

(both pages explicitly list this limitation — it means **neither can be used** on instances managed by an ASG).

**Source:** https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html (table "Differences"); https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/cloudwatch-recovery.html (cites CloudWatch action-based recovery + Limitations); https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html (cites "Simplified automatic recovery is enabled by default...")

**Significance:** CloudWatch action-based recovery offers a lower RTO than simplified (the docs do not give absolute numbers, only "faster") and adds SNS notification. Both options are mutually exclusive with ASG — an instance in an ASG cannot use either direct recovery mechanism.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-recover.html
- Verbatim quote checked: yes
- Quote substring confirmed at: table "Differences between simplified automatic recovery and CloudWatch action based recovery", row "Recovery time"

---

### Finding 3: Task definition pgbouncer:1 already exists in ECS — proprietary ECR image, awslogs configured

**Evidence:**

```json
{
  "family": "pgbouncer",
  "image": "405749097490.dkr.ecr.us-east-1.amazonaws.com/pgbouncer-puma:latest",
  "networkMode": "bridge",
  "requiresCompatibilities": ["EC2"],
  "cpu": "1024",
  "memory": "1024",
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/pgbouncer",
      "awslogs-create-group": "true",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  },
  "registeredAt": "2025-11-16T21:48:34.160000-03:00",
  "registeredBy": "arn:aws:iam::405749097490:user/ivan.domingues"
}
```

The task definition uses `networkMode: bridge` (EC2 mode) and is not Fargate-compatible (Fargate requires `awsvpc`). The image `pgbouncer-puma:latest` is already in the account's ECR. The log group `/ecs/pgbouncer` is already configured with `awslogs-create-group: true`.

**Source:** `aws ecs describe-task-definition --task-definition pgbouncer:1` (direct API read)

**Significance:** A route to ECS (option 5) exists via partial reuse: the ECR image and the log group already exist. A new task definition revision would be required to migrate from `bridge`/EC2 to `awsvpc`/Fargate, or to continue in EC2-mode under an ASG. This artifact represents earlier work (Nov/2025) that was never completed or was abandoned.

**Verification:**
- URL fetched: N/A (direct AWS API)
- Verbatim quote checked: N/A (API response JSON)
- Quote substring confirmed at: direct output of `describe-task-definition`

---

### Finding 4: ASG min=max=1 is incompatible with simplified/CloudWatch recovery — but the instance is replaced automatically

**Evidence:**

The Auto Scaling health checks documentation describes:

> "Amazon EC2 Auto Scaling lets the status checks fail occasionally, without taking any action. When a status check fails, Amazon EC2 Auto Scaling waits a few minutes for AWS to fix the issue. It does not immediately mark an instance `Unhealthy` when its status for the status checks becomes `impaired`."

And for full failure:

> "However, if Amazon EC2 Auto Scaling detects that an instance is no longer in the `running` state, this situation is treated as an immediate failure. In this case, it immediately marks the instance as `Unhealthy` and replaces it."

The simplified automatic recovery documentation explicitly lists:

> "Limitations: Auto Scaling: Instances that are part of an Auto Scaling group"

The same applies to CloudWatch action-based recovery. Therefore, an ASG min=max=1 **replaces** the instance with a new one (new launch), unlike recovery which **migrates** the existing instance. The ASG RTO includes the boot time of the new instance + the PgBouncer systemd start.

**Source:** https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html and https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instance-configuration-recovery.html

**Significance:** ASG min=max=1 does not reduce RTO compared to simplified recovery — it may increase it (booting a new instance vs migrating the existing one). The main gain is log persistence (via CloudWatch agent) and operability (versioned launch template, automated replacement without manual intervention). An instance in an ASG loses simplified/CloudWatch recovery, but gains automatic health-check + replace.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/autoscaling/ec2/userguide/health-checks-overview.html
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Amazon EC2 health checks", paragraph "Important"

---

### Finding 5: RDS Proxy — extensive pinning for Aurora PostgreSQL reduces pooling effectiveness

**Evidence:**

The documentation lists the conditions that cause pinning for Aurora PostgreSQL:

> "For PostgreSQL, the following interactions also cause pinning:
> + Using `SET` commands.
> + Using `PREPARE`, `DISCARD`, `DEALLOCATE`, or `EXECUTE` commands to manage prepared statements.
> + Creating temporary sequences, tables, or views.
> + Declaring cursors.
> + Discarding the session state.
> + Listening on a notification channel.
> + Loading a library module such as `auto_explain`.
> + Manipulating sequences using functions such as `nextval` and `setval`.
> + Interacting with locks using functions such as `pg_advisory_lock` and `pg_try_advisory_lock`."

Additionally:

> "However, for PostgreSQL setting a variable leads to session pinning."

There is also a specific functional limitation for PostgreSQL:

> "For PostgreSQL, RDS Proxy doesn't currently support canceling a query from a client by issuing a `CancelRequest`. This is the case, for example, when you cancel a long-running query in an interactive psql session by using Ctrl\+C."

And about failover:

> "RDS Proxy bypasses Domain Name System (DNS) caches to reduce failover times by up to 66% for Aurora Multi-AZ databases."

**Source:** https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html and https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy.html

**Significance:** Rails (ActiveRecord + PG adapter) issues `SET` and `PREPARE` on every connection. That means virtually every Rails connection through RDS Proxy will be pinned, making multiplexing ineffective — the behavior approaches pass-through, not a real pool. RDS Proxy solves the Aurora failover problem (−66% time), but not the PgBouncer resilience problem itself; they are orthogonal problems.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/rds-proxy-pinning.html
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Conditions that cause pinning for Aurora PostgreSQL"

---

### Finding 6: ECS Fargate — task definition requires awsvpc and natively supports awslogs

**Evidence:**

AWS documentation lists the valid CPU/memory combinations for Fargate:

> "| 256 (.25 vCPU) | 512 MiB, 1 GB, 2 GB | Linux |"
> "| 1024 (1 vCPU) | 2 GB, 3 GB, 4 GB, 5 GB, 6 GB, 7 GB, 8 GB | Linux, Windows |"

And about the log driver:

> "The `awslogs` log driver configures your Fargate tasks to send log information to Amazon CloudWatch Logs."

About the network mode:

> "`networkConfiguration` - Fargate tasks always use the `awsvpc` network mode."

About pricing (Linux/X86, us-east-1):

> "Using the Linux/X86 pricing for US East (N. Virginia) Region where CPU cost: $0.000011244 per vCPU second, memory cost: $0.000001235 per GB per second, and ephemeral storage cost: $0.0000000308 per GB per second"

The existing task definition `pgbouncer:1` uses `networkMode: bridge` and `requiresCompatibilities: ["EC2"]` — it is not Fargate-compatible as-is. A new revision with `networkMode: awsvpc` and `requiresCompatibilities: ["FARGATE"]` would be required.

**Source:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html and https://aws.amazon.com/fargate/pricing/

**Significance:** Migrating to Fargate solves the log problem (native awslogs, persistent on CloudWatch) and eliminates the dependency on a fixed EC2 host. Two tasks across two AZs with an NLB eliminate the AZ SPOF. The existing task definition needs to be recreated with a different network mode — not a direct reuse. The cost of 1 Fargate task (0.25 vCPU / 512 MiB) running ~730h/month is roughly $2.95 in CPU + $0.27 in memory = ~$3.22/month per task.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Task CPU and memory", table of valid combinations

---

### Finding 7: NLB — Layer 4, native health check, TCP support for PgBouncer

**Evidence:**

> "A Network Load Balancer functions at the fourth layer of the Open Systems Interconnection (OSI) model. It can handle millions of requests per second."

> "For TCP traffic, the load balancer selects a target using a flow hash algorithm based on the protocol, source IP address, source port, destination IP address, destination port, and TCP sequence number. The TCP connections from a client have different source ports and sequence numbers, and can be routed to different targets. Each individual TCP connection is routed to a single target for the life of the connection."

About pricing:

> "Adding the hourly charge of $0.0225, the total Network Load Balancer costs are:"

**Source:** https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html and https://aws.amazon.com/elasticloadbalancing/pricing/

**Significance:** NLB operates at Layer 4 (TCP), which is the correct protocol for PgBouncer (port 6432). Each TCP connection is routed to a single target for the lifetime of the connection — that preserves PgBouncer's session-mode and transaction-mode behavior. The base cost is ~$16.43/month for the NLB, independent of the number of targets. An NLB with 2 targets (Fargate tasks in 2 AZs or 2 EC2 instances in 2 AZs) would provide AZ-failure tolerance.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/introduction.html and https://aws.amazon.com/elasticloadbalancing/pricing/
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Network Load Balancer overview" (TCP routing) and pricing examples (hourly charge $0.0225)

---

### Finding 8: Environment snapshot — current app-atento-001 infrastructure

**Evidence (AWS API, read-only):**

| Resource | Value |
|---|---|
| pgbouncer instance | `i-0b6f70bc905727770`, `t3a.micro`, `us-east-1a`, `running` |
| Private IP | `10.100.13.59` |
| VPC | `vpc-030497c296befc066` |
| Private subnets | `subnet-02da8b32b1466bd0e` (us-east-1a, 10.100.13.0/24) and `subnet-0aae9fb5fd47320c0` (us-east-1b, 10.100.14.0/24) |
| Aurora cluster | `app-atento-001-cluster`, PostgreSQL 15.15, MultiAZ: true |
| Aurora writer | `app-atento-001-db-2`, IP `10.100.14.220` (us-east-1b) |
| Aurora reader | `app-atento-001-db-1`, IP `10.100.13.15` (us-east-1a) |
| ECS cluster | `app-atento-001-cluster`, 9 capacity providers (all EC2), 9 services running |
| RDS Proxy | None |
| NLB | None (an internet-facing ALB `app-atento-001-lb` exists) |
| CloudWatch alarms | None for `i-0b6f70bc905727770` |
| Auto Recovery | `default` (simplified active) |
| Existing task def | `pgbouncer:1`, EC2/bridge, 1 vCPU/1 GiB, image `pgbouncer-puma:latest` in ECR |
| App ASGs | 9 existing ASGs (all EC2 mode, none for pgbouncer) |

**Source:** AWS API direct (`describe-instances`, `describe-db-clusters`, `describe-clusters`, `describe-db-proxies`, `describe-load-balancers`, `describe-alarms`, `describe-task-definition`, `describe-auto-scaling-groups`)

**Significance:** The dual-AZ infrastructure already exists (private subnets in 1a and 1b). The ECS cluster uses only EC2 capacity providers — Fargate can be enabled without modifying the existing services. The `pgbouncer:1` task definition represents earlier work that signals familiarity with PgBouncer containerization in this environment.

**Verification:**
- URL fetched: N/A (direct AWS API)
- Verbatim quote checked: N/A
- Quote substring confirmed at: outputs of multiple `aws describe-*` commands

---

### Finding 9: Real topology — 4 pgbouncers across 2 environments × 2 types (Puma and Sidekiq)

**Evidence:**

Direct clarification from the engineer (in-session): there are **4 pgbouncers in total**, distributed along two axes:

- **Environment axis**: Atento 001 + another production environment
- **Type axis per environment**: Puma (web) and Sidekiq (worker)

The Puma/Sidekiq separation per environment exists because:

- Puma and Sidekiq have different `pool_size`, timeouts, and scaling strategy
- Web (Puma) does not outscale; Worker (Sidekiq) outscales aggressively
- It is not possible to keep conflicting configurations in a single pgbouncer

**Source:** Engineer clarification (in-session)

**Significance:** Every earlier cost estimate based on "1 pgbouncer" needs to be multiplied. For an HA solution with 2 tasks/instances per pgbouncer: 4 pgbouncers × 2 units = 8 tasks/instances total. If the NLB is shared across the 4 pgbouncers with listeners on distinct ports, the NLB's fixed cost ($16.43/month) does not multiply — 1 NLB for all. Compute cost (Fargate tasks or EC2) does multiply by 4 or 8.

---

### Finding 10: ALB supports only HTTP/HTTPS/gRPC — not suitable for PgBouncer (TCP)

**Evidence:**

The AWS comparison table for load balancer types documents protocols supported per type:

> "Protocol listeners: HTTP, HTTPS, gRPC" (Application Load Balancer)

> "Protocol listeners: TCP, UDP, TLS" (Network Load Balancer)

The documentation explicitly describes the ALB as operating at the application layer:

> "An Application Load Balancer functions at the application layer, the seventh layer of the Open Systems Interconnection (OSI) model."

While the NLB:

> "A Network Load Balancer functions at the fourth layer of the Open Systems Interconnection (OSI) model."

**Source:** https://aws.amazon.com/elasticloadbalancing/features/ (table "Product Comparisons", row "Protocol listeners"); https://docs.aws.amazon.com/elasticloadbalancing/latest/application/introduction.html (section "Application Load Balancer overview")

**Significance:** PgBouncer exposes a TCP port (6432 by default) and speaks the PostgreSQL wire protocol — not HTTP. The existing ALB in the environment (`app-atento-001-lb`) is internet-facing and serves the application's web traffic; it cannot be reused for PgBouncer. Any load balancer option for PgBouncer must use NLB (Layer 4 TCP), not ALB.

**Verification:**
- URL fetched: https://aws.amazon.com/elasticloadbalancing/features/
- Verbatim quote checked: yes
- Quote substring confirmed at: table "Product Comparisons", row "Protocol listeners" — "HTTP, HTTPS, gRPC" (ALB) and "TCP, UDP, TLS" (NLB)

---

### Finding 11: NLB supports multiple listeners on distinct ports (TCP 1–65535)

**Evidence:**

The NLB listener documentation specifies:

> "Listeners support the following protocols and ports:
> + **Protocols**: TCP, TLS, UDP, TCP\_UDP, QUIC, TCP\_QUIC
> + **Ports**: 1-65535"

About per-listener routing:

> "A *listener* is a process that checks for connection requests, using the protocol and port that you configure. Before you start using your Network Load Balancer, you must add at least one listener."

**Source:** https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html (section "Listener configuration")

**Significance:** A single NLB can host multiple TCP listeners on distinct ports, each listener pointing at a different target group. For 4 pgbouncers (Puma-atento, Sidekiq-atento, Puma-other-env, Sidekiq-other-env), it would be possible to use 4 listeners on 4 distinct ports (e.g., 6432, 6433, 6434, 6435) on a single NLB. Each target group would have its own independent health checks. The NLB fixed cost does not multiply — 1 NLB covers all 4 pgbouncers.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/elasticloadbalancing/latest/network/load-balancer-listeners.html
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Listener configuration", bullet "Ports: 1-65535"

---

### Finding 12: NLB pricing — fixed hourly cost $0.0225/hr + TCP LCU $0.006 per NLCU

**Evidence:**

About the hourly cost:

> "Adding the hourly charge of $0.0225, the total Network Load Balancer costs are:"

About the LCU for TCP traffic:

> "In this example for TCP traffic, the processed bytes (0.36 NLCUs) is greater than both the new connections (0.125 NLCUs) and active connections (0.18 NLCUs). Assuming this usage is consistent over 60 minutes, this results in a total charge of $0.00216 per hour for TCP traffic (0.36 NLCUs \* $0.006) or $1.55 per month for TCP Traffic ($0.00216 \* 24 hours \* 30 days)."

The NLCU dimension for TCP is defined as: 800 new TCP connections/second, 100,000 active TCP connections (sampled per minute), or 1 GB/hour processed.

**Source:** https://aws.amazon.com/elasticloadbalancing/pricing/ (section "Network Load Balancer", TCP cost examples)

**Significance:** NLB cost is $0.0225/hr × 730h = **$16.43/month of fixed cost** + variable per NLCU. For typical PgBouncer traffic in production (low new-connection volume, a few persistent active connections), the LCU component is small. Sharing 1 NLB across 4 pgbouncers via 4 listeners keeps the fixed cost at $16.43/month — vs $65.72/month if they were 4 separate NLBs.

**Verification:**
- URL fetched: https://aws.amazon.com/elasticloadbalancing/pricing/
- Verbatim quote checked: yes
- Quote substring confirmed at: section "Network Load Balancer", TCP calculation example — "0.36 NLCUs \* $0.006" and "hourly charge of $0.0225"

---

### Finding 13: Cloud Map / ECS Service Discovery — configurable TTL, defaults to 60s in the doc examples

**Evidence:**

The Cloud Map service-creation documentation describes the TTL field:

> "For **TTL**, specify a numerical value to define the time to live (TTL) value, in seconds, at the service level. The value of TTL determines how long DNS resolvers cache information for this record before the resolvers forward another DNS query to Amazon Route 53 to get updated settings."

The CLI example in the official doc uses:

```
--dns-config "NamespaceId={{ns-xxxxxxxxxxx}},RoutingPolicy=MULTIVALUE,DnsRecords=[{Type={{A}},TTL={{60}}}]"
```

With a response showing `"TTL": 60` as the default value in the examples.

The ECS Service Discovery documentation says the following about record health:

> "Amazon ECS performs periodic container-level health checks. If an endpoint does not pass the health check, it is removed from DNS routing and marked as unhealthy."

And about the behavior with all records:

> "When all records are unhealthy, Route 53 responds to DNS queries with up to eight unhealthy records."

**Source:** https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html (section "If you choose API and DNS", TTL item; CLI example); https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html (section "Service discovery considerations")

**Significance:** With TTL=60s (the value used in the AWS doc example), clients that resolved DNS before the removal of a dead task's endpoint will keep trying to connect to that IP for up to 60 seconds after deregistration. TCP connections that hit the IP of a terminated task receive `connection refused` or timeout during that window. The NLB avoids the issue because the NLB IP address does not change — only the target group health check detects the dead task and stops routing traffic to it in ~10-30s.

**Verification:**
- URL fetched: https://docs.aws.amazon.com/cloud-map/latest/dg/creating-services.html
- Verbatim quote checked: yes
- Quote substring confirmed at: DNS service configuration section, TTL field description + CLI example with `TTL={{60}}`

---

## Trade-offs surfaced

### Comparative table by criterion (real topology: 4 pgbouncers)

Context: 4 pgbouncers total (2 environments × 2 types: Puma and Sidekiq). Cost calculated for the 4 pgbouncers combined.

| Option | Estimated monthly cost (USD) — 4 pgbouncers | Expected RTO (1 host/task failure) | Persistent logs | Failover error window | Migration effort |
|---|---|---|---|---|---|
| 1. Status quo + Simplified Auto Recovery (current) | ~$27.44 (4× t3a.micro) | ~5–15 min (Finding 1, 2) | No | N/A (in-place recovery) | — |
| 2. CloudWatch alarm recovery | ~$27.44 + ~$0.40 (4 alarms) | Lower than option 1 (Finding 2) | No | N/A (in-place recovery) | Low |
| 3. ASG min=max=1 × 4 + CloudWatch agent | ~$27.44 + CW Logs | ~5–15 min + boot (Finding 4) | Yes | N/A (no LB) | Low–Medium |
| 4. ASG 2 nodes × 4 pgbouncers + 1 shared NLB | ~$54.88 (8× t3a.micro) + $16.43 NLB + CW | ~10–30s (NLB health check) | Yes | ~10–30s (health check detects) | Medium–High |
| 5a. ECS Fargate 1 task × 4 pgbouncers + 1 shared NLB | ~$12.88 (4 tasks × ~$3.22) + $16.43 NLB | ~30–60s (ECS replace + NLB) | Yes (native awslogs) | ~30–60s (task restart) | Medium |
| 5b. ECS Fargate 2 tasks × 4 pgbouncers + 1 shared NLB | ~$25.76 (8 tasks × ~$3.22) + $16.43 NLB | ~0s (other healthy task absorbs) | Yes (native awslogs) | ~0s (LB redirects immediately) | Medium |
| 5c. ECS Fargate 2 tasks × 4 pgbouncers + Cloud Map (no NLB) | ~$25.76 (8 tasks) + Route53/Cloud Map | ~30–60s + TTL DNS cache | Yes (native awslogs) | Up to 60s of TCP errors (Finding 13) | Medium |
| 6. RDS Proxy | ~$21.90 minimum (UNVERIFIED) | N/A for pgbouncer failure (Finding 5) | N/A | N/A | Medium |

**Cost notes:**
- t3a.micro us-east-1: $0.0094/hr × 730h = $6.86/month per instance (Finding 8 + economize.cloud source); 4 instances = $27.44; 8 instances = $54.88
- Fargate 0.25 vCPU / 512 MiB: ~$3.22/month per task (Finding 6); 4 tasks = $12.88; 8 tasks = $25.76
- Shared NLB (1 NLB, 4 listeners): $0.0225/hr × 730h = $16.43/month + LCU (Finding 12) — fixed cost does not multiply with listener count
- RDS Proxy: $0.015/vCPU-hr × at least 2 vCPUs × 730h = $21.90/month (minimum; UNVERIFIED — not confirmed with a verbatim substring from the AWS pricing page directly)

### Prose pros and cons

**Option 1 (Status quo + simplified recovery)**

The current mechanism works for the 4 standalone pgbouncers, but the ~10 min RTO is not controllable. There is no notification, logs disappear with the instance, and the mechanism is an AWS-managed black box. No additional effort, no extra cost.

**Option 2 (CloudWatch alarm recovery)**

Adds an alarm on the `StatusCheckFailed_System` metric with a recovery action (Finding 2) on each of the 4 instances. RTO drops ("faster recovery attempts") and SNS can notify the team. Incremental cost is minimal (~$0.10/alarm × 4 = $0.40/month). Does not solve logs. Cannot be combined with ASG (Finding 4). Effort: configure 4 alarms — Low.

**Option 3 (ASG min=max=1 × 4 + CloudWatch agent)**

Turns each of the 4 standalone instances into an ASG. The CloudWatch agent collects journald/syslog and ships it to CloudWatch Logs — logs become persistent. RTO can be higher than option 1 (boot a new instance vs migrate the existing host — Finding 4). It does not eliminate the AZ SPOF. The instance loses simplified/CloudWatch recovery (ASG limitation — Finding 2 and 4). Effort: create 4 launch templates, 4 ASGs, configure CloudWatch agent on each — Low–Medium.

**Option 4 (ASG 2 nodes × 4 pgbouncers + 1 shared NLB with 4 listeners)**

8 EC2 nodes (2 per pgbouncer across 2 different AZs) behind 1 NLB with 4 TCP listeners on distinct ports. A host or AZ failure leaves the other node healthy absorbing traffic. The real RTO is the time for the NLB health check to detect the target as unhealthy + connection draining. Logs live on CloudWatch. High operational complexity: 4 pairs of pgbouncers need consistent configuration, 8 EC2 instances to manage, 4 NLB target groups. Effort: 4 launch templates, 4 ASGs, 1 NLB with 4 listeners + 4 target groups, security groups — Medium–High.

**Option 5a/5b (ECS Fargate + 1 shared NLB)**

A new task definition with `awsvpc`/Fargate is required (Finding 3 and 6). Fargate natively uses `awslogs` — logs go straight to CloudWatch Logs. With 2 tasks per pgbouncer across 2 AZs (option 5b), the RTO is ~0s for a single-task failure. PgBouncer as a Fargate container requires configuration (pgbouncer.ini, credentials) to be injected via Secrets Manager or SSM — there is no editable local file. The Puma/Sidekiq separation (Finding 9) means 4 distinct ECS services with distinct configurations. 1 NLB with 4 listeners covers all 4 pgbouncers. Effort: 4 task definitions (awsvpc), 4 ECS services, 1 NLB with 4 listeners + 4 target groups, Secrets Manager for configs — Medium.

**Option 5c (ECS Fargate + Cloud Map without NLB)**

Eliminates the NLB fixed cost ($16.43/month). Service discovery uses DNS with TTL=60s (Finding 13). When a task is replaced, the new IP registers in DNS, but clients with the cached record will try to connect to the old IP for up to 60s — during that window, TCP connections fail with `connection refused`. For database connection pools (PgBouncer itself connecting to Aurora, or the application connecting to PgBouncer), that window can cause visible application errors. The error window is deterministic and bounded by TTL, but it exists. Effort similar to 5b, minus the NLB.

**Option 6 (RDS Proxy)**

RDS Proxy does not replace PgBouncer in the current architecture — they are analogous layers. The EC2 host resilience problem is not solved. RDS Proxy is better at Aurora failover (−66% DNS propagation — Finding 5), but Rails + PG adapter issues `SET` and `PREPARE` on every connection, causing extensive pinning (Finding 5). The minimum cost (~$21.90/month, UNVERIFIED) is similar to Fargate 2 tasks + NLB. Effort: create the proxy, Secrets Manager for credentials, adjust connection strings on every service — Medium.

---

## What remains uncertain

1. **Current `pool_mode` and `default_pool_size` of pgbouncer.ini** — could not be read without SSH access to the instance. Relevant to determine whether `transaction` mode is active (which affects which replacement option is viable) and the configured pool size.

2. **Master/follower configuration in pgbouncer.ini** — the Aurora cluster has the writer in us-east-1b and reader in us-east-1a. Which endpoint is pgbouncer pointing at? The writer endpoint? The reader endpoint? The cluster endpoint? That affects how an eventual NLB + 2 pgbouncers would behave: each instance would need the same Aurora endpoint configuration, or is there differentiated read/write routing?

3. **Exact RDS Proxy price for Aurora PostgreSQL in us-east-1** — the AWS pricing page did not return the table value in a fetchable format. The $0.015/vCPU-hr figure was quoted by third-party sources (cloudchipr.com, pump.co) but not confirmed via verbatim substring on the AWS page. Marking as UNVERIFIED for the RDS Proxy cost row.

4. **Measured simplified auto recovery RTO in the incident** — the incident logs disappeared with the instance (Finding 1). The ~10 min value is based on the incident description, not CloudWatch metrics. Without a CloudWatch agent running, there is no precise timestamp for when `StatusCheckFailed_System` went to 1 and when it returned to `ok`.

5. **PgBouncer throughput benchmarks on Fargate 0.25 vCPU vs EC2 t3a.micro** — no benchmarks specific to Aurora PostgreSQL 15 + PgBouncer on Fargate were found. The current instance uses 1 vCPU/1 GiB; the smallest Fargate with 1 vCPU/2 GiB costs ~$9.02/month, marginally more than t3a.micro.

6. **Rails 8 connection-pool compatibility with 2 pgbouncers without a shared pool** — in the 2-PgBouncer-instances mode (option 4 or 5b), each instance keeps its own pool. Rails has no visibility into which pgbouncer receives the connection. In pgbouncer's `transaction` mode that is generally transparent; in `session` mode, sticky connections to the same pgbouncer via NLB flow hash would be required — but the NLB distributes per TCP connection, not per database session. No concrete evidence about that specific behavior with Rails 8 was found.

7. **How different the 4 pgbouncers' configurations are today** — could not read each instance's `pgbouncer.ini` without SSH access. Relevant for sizing migration effort: if the 4 pgbouncers have similar configurations, the migration is simpler; if they have drifted, each one may need individual handling.

8. **NLB compatibility with multiple listeners and independent health checks per target group** — the documentation describes per-target-group health checks (Finding 11), which suggests each listener/target group has independent health checks. Still, no verbatim confirmation was found for the explicit behavior of independent health checks when multiple listeners point at distinct target groups on the same NLB.

9. **Precise failover error window for Cloud Map vs NLB** — Finding 13 establishes that the Cloud Map default TTL in the examples is 60s, and that during that period clients may try to connect to IPs of terminated tasks. No AWS documentation was found with concrete measurements of the actual error window (between task termination and DNS update + TTL expiration on clients). The NLB avoids the issue by design (Finding 7), but the exact magnitude of impact of Cloud Map without an NLB for database connection pools was not found with a citable source.

---

## Suggested options

The options below are ordered by objective criterion, with the real topology of 4 pgbouncers. The engineer picks based on project priority.

### Ranked by estimated monthly cost (ascending) — 4 pgbouncers

1. Option 2 — CloudWatch alarm recovery (~$27.44 + ~$0.40 alarms) — minimum additional
2. Option 3 — ASG min=max=1 × 4 + CloudWatch agent (~$27.44 + CW Logs ingestion)
3. Option 5a — Fargate 1 task × 4 + 1 shared NLB (~$29.31)
4. Option 5b — Fargate 2 tasks × 4 + 1 shared NLB (~$42.19)
5. Option 5c — Fargate 2 tasks × 4 + Cloud Map without NLB (~$25.76 + Route53/Cloud Map, no NLB cost)
6. Option 4 — ASG 2 nodes × 4 + 1 shared NLB (~$71.31)

### Ranked by expected RTO (ascending)

1. Option 5b — Fargate 2 tasks × 4 + NLB (~0s for 1-task failure, Finding 6 and 7)
2. Option 4 — ASG 2 nodes × 4 + NLB (~10–30s health check, Finding 7)
3. Option 5a — Fargate 1 task × 4 + NLB (~30–60s ECS replace + NLB, Finding 6 and 7)
4. Option 5c — Fargate 2 tasks × 4 + Cloud Map (~30–60s + up to 60s of TTL DNS, Finding 13)
5. Option 2 — CloudWatch alarm recovery (less than simplified, no absolute number, Finding 2)
6. Option 3 — ASG min=max=1 × 4 (new-instance boot, possibly higher than option 2, Finding 4)

### Ranked by migration effort (ascending)

1. Option 2 — Low (4 CloudWatch alarms, Finding 2)
2. Option 3 — Low–Medium (4 launch templates + 4 ASGs + CloudWatch agent × 4, Finding 4)
3. Option 5a/5b/5c — Medium (4 task defs awsvpc + 4 ECS services + NLB or Cloud Map + Secrets Manager, Finding 3 and 6)
4. Option 4 — Medium–High (8 launch templates + 4 ASGs + NLB + config sync × 4, Finding 4 and 7)

### Ranked by persistent logs

- Option 2 — does not solve logs (standalone instance without CloudWatch agent)
- Option 3, 4 — yes, via CloudWatch agent on each EC2 instance
- Option 5a/5b/5c — yes, via native ECS awslogs (Finding 6, zero additional configuration)
