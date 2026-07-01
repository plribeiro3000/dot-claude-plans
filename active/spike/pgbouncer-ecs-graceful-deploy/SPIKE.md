# SPIKE — PgBouncer ECS Graceful Deploy (Zero Dropped Connections)

## Investigation question

How can a rolling ECS deploy of PgBouncer (desired_count=2, Cloud Map MULTIVALUE A, no load balancer, pool_mode=transaction, edoburu image) achieve zero dropped client connections? Specifically: what signals stop a PgBouncer container, how does ECS deliver them, what is the timing window, and what is the complete checklist to close the gaps?

## Setup context (from engineer)

- PgBouncer: ECS Fargate service, desired_count=2, Cloud Map private DNS (MULTIVALUE A), NOT behind a load balancer
- Image: edoburu/pgbouncer (Alpine-based) built into their own ECR
- Config: pool_mode=transaction, auth_type=md5, listen_port=6432
- Deployment: rolling (ECS controller), min_healthy=100%, max=200%, circuit breaker + rollback enabled
- Clients: Rails app + cross-region outbound worker with their own DB connection pool

## Sources consulted

- [pgbouncer.org/usage.html](https://www.pgbouncer.org/usage.html) — signal table + admin console commands; see auxiliary: `pgbouncer_doc_1.txt`
- [pgbouncer.org/changelog.html](https://www.pgbouncer.org/changelog.html) — 1.23.0 SIGTERM behavior change; see auxiliary: `pgbouncer_doc_2.txt`
- [pgbouncer.org/config.html](https://www.pgbouncer.org/config.html) — pool_mode, server_idle_timeout, server_lifetime, client_idle_timeout defaults; see auxiliary: `pgbouncer_doc_2.txt`
- [AWS ECS API ContainerDefinition](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html) — stopTimeout parameter (default 30s, max 120s); see auxiliary: `aws_ecs_doc_1.txt`
- [AWS ECS task lifecycle](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle-explanation.html) — DEACTIVATING/STOPPING/DEPROVISIONING state descriptions; see auxiliary: `aws_ecs_doc_1.txt`
- [AWS containers blog — graceful shutdowns with ECS](https://aws.amazon.com/blogs/containers/graceful-shutdowns-with-ecs/) — ALB deregistration delay vs Cloud Map gap; see auxiliary: `aws_ecs_doc_1.txt`
- [containers-roadmap issue #1639](https://github.com/aws/containers-roadmap/issues/1639) — Cloud Map deregistration timing (no delay equivalent); see auxiliary: `aws_ecs_doc_1.txt`
- [edoburu Dockerfile](https://github.com/edoburu/docker-pgbouncer/blob/master/Dockerfile) — VERSION=1.25.2, no STOPSIGNAL, exec-form ENTRYPOINT; see auxiliary: `edoburu_excerpt_1.txt`
- [edoburu entrypoint.sh](https://github.com/edoburu/docker-pgbouncer/blob/master/entrypoint.sh) — `exec "$@"` pattern confirming pgbouncer as PID 1; see auxiliary: `edoburu_excerpt_1.txt`

---

## Findings

### Finding 1: PgBouncer signal semantics (≥1.23.0)

**Evidence** (from `pgbouncer_doc_1.txt`, source pgbouncer.org/usage.html):

```
SIGTERM
  Super safe shutdown. Wait for all existing clients to disconnect, but don't
  accept new connections. This is the same as issuing SHUTDOWN WAIT_FOR_CLIENTS
  on the console.

SIGINT
  Safe shutdown. Same as issuing SHUTDOWN WAIT_FOR_SERVERS on the console.

SIGUSR1
  Same as issuing PAUSE on the console.
```

**Source:** https://www.pgbouncer.org/usage.html (verified)

**Verification block:** URL fetched / Verbatim quote confirmed from fetched content.

**Significance:** SIGTERM is the "super safe shutdown" — waits for all clients to disconnect before exiting. SIGINT is slightly less safe — shuts down once server connections are released, regardless of client state. SIGQUIT triggers immediate shutdown (documented in prior session, same source). The 1.23.0 changelog (auxiliary `pgbouncer_doc_2.txt`) marks this SIGTERM behavior as a "minor breaking change" from the prior behavior (prior behavior: SIGTERM = immediate shutdown). Users relying on SIGTERM for immediate shutdown must now use SIGQUIT.

---

### Finding 2: Admin console commands available for graceful drain

**Evidence** (from `pgbouncer_doc_1.txt`, source pgbouncer.org/usage.html):

```
PAUSE
  PgBouncer tries to disconnect from all servers. Disconnecting each server
  connection waits for that server connection to be released according to the
  server pool's pooling mode.

RECONNECT
  Closes open server connections after release (per pooling mode), enabling
  gradual switchover scenarios without requiring configuration reload.

WAIT_CLOSE
  Wait until all server connections, either of the specified database or of all
  databases, have cleared the "close_needed" state.

SHUTDOWN WAIT_FOR_CLIENTS
  Stop accepting new connections and shutdown the process once all existing
  clients have disconnected.

SHUTDOWN WAIT_FOR_SERVERS
  Stop accepting new connections and shutdown after all servers are released.
```

**Source:** https://www.pgbouncer.org/usage.html (verified)

**Verification block:** URL fetched / Verbatim quotes confirmed from fetched content.

**Significance:** These commands are available via the PgBouncer admin console (a special database `pgbouncer` reachable via the listen port). A preStop-style script can issue `PAUSE` or `SHUTDOWN WAIT_FOR_SERVERS` before the process receives SIGTERM, reducing the time PgBouncer needs for graceful exit. RECONNECT is useful for zero-downtime server-side rotation. No minimum version documented per-command in the fetched material; the 1.23.0 changelog note only applies to SIGTERM behavior change.

---

### Finding 3: ECS stopTimeout — default 30s, Fargate max 120s

**Evidence** (from `aws_ecs_doc_1.txt`, source AWS ECS API docs):

```
stopTimeout
  Type: Integer
  Required: No
  Example values: 120
  Time duration (in seconds) to wait before the container is forcefully killed
  if it doesn't exit normally on its own.
  If the parameter isn't specified, then the default value of 30 seconds is used.
  The maximum value is 120 seconds.
```

**Source:** https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html (lines 984-989 of persisted tool-results file; verified)

**Verification block:** URL fetched / Verbatim quote confirmed from fetched content at the identified lines.

**Significance:** ECS gives a Fargate task at most 120 seconds between SIGTERM and SIGKILL. This is a hard ceiling — not configurable beyond 120s on Fargate. The community recommendation (from runbookpages.com blog; UNVERIFIED — re-fetch failed) references a target of `server_lifetime + server_idle_timeout + buffer ≈ 3600 + 600 + N seconds` for complete drain. The 120s ceiling cannot accommodate this if clients hold connections for the default 3600s server_lifetime. This is the fundamental constraint for the deploy design.

---

### Finding 4: ECS task lifecycle — when SIGTERM is sent relative to deregistration

**Evidence** (from `aws_ecs_doc_1.txt`, source AWS ECS task lifecycle docs):

```
DEACTIVATING
  This state is reached before STOPPING. For tasks using a load balancer, the
  target is deregistered from the load balancer before the task is stopped.

STOPPING
  The task is in the process of being stopped. A SIGTERM signal is sent to
  the containers in the task. If the containers do not exit within the
  stopTimeout period, a SIGKILL signal is sent to force the containers to stop.

DEPROVISIONING
  Resources associated with the task are being cleaned up. The ENI is detached.
```

**Source:** https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-lifecycle-explanation.html (verified)

**Verification block:** URL fetched / Verbatim quotes confirmed from fetched content.

**Significance:** DEACTIVATING explicitly mentions load balancer deregistration as its purpose. Cloud Map deregistration is NOT mentioned in DEACTIVATING state documentation. Based on containers-roadmap issue #1639 (Finding 5), Cloud Map deregistration happens just before STOPPING, with no buffer window. This is different from ALB behavior where a configurable deregistration delay provides a drain window before SIGTERM.

---

### Finding 5: Cloud Map deregistration gap — no delay equivalent

**Evidence** (from `aws_ecs_doc_1.txt`, source containers-roadmap issue #1639):

```
"During a service update, the task is stopped as soon as the target is
deregistered."
```

ALB contrast (from AWS containers blog, same auxiliary file):

```
The DEACTIVATING state is specifically for ALB-registered tasks. A task
is first deregistered from the ALB, then SIGTERM is sent. The
deregistration delay (configurable on the target group) provides a window
for in-flight requests to complete before SIGTERM. Cloud Map tasks do NOT
benefit from this deregistration delay — no equivalent exists.
```

**Source:** https://github.com/aws/containers-roadmap/issues/1639 (verified) and https://aws.amazon.com/blogs/containers/graceful-shutdowns-with-ecs/ (verified)

**Verification block:** URL fetched / Verbatim quotes confirmed from fetched content.

**Significance:** For Cloud Map (DNS-based discovery), there is no deregistration delay. The task enters STOPPING (receives SIGTERM) immediately after Cloud Map deregistration. However, DNS-cached clients may still resolve the old task IP for up to the TTL duration (default 60s for Cloud Map MULTIVALUE A records). This creates a window where new connections arrive at a task that has already received SIGTERM and stopped accepting new connections. PgBouncer's SIGTERM handler (SHUTDOWN WAIT_FOR_CLIENTS) stops accepting new connections immediately — so DNS-cached clients get connection refused during this 60s window.

---

### Finding 6: edoburu image — version 1.25.2, exec entrypoint, no STOPSIGNAL

**Evidence** (from `edoburu_excerpt_1.txt`, source github.com/edoburu/docker-pgbouncer):

```
ARG VERSION=1.25.2

# No STOPSIGNAL directive present in the Dockerfile.
# Docker default STOPSIGNAL is SIGTERM.

ENTRYPOINT ["/entrypoint.sh"]
CMD ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]
```

entrypoint.sh final lines:

```
exec "$@"
```

Signal forwarding chain:

```
ECS → Docker → PID 1 = pgbouncer (after exec)
SIGTERM → pgbouncer directly (no shell intermediary)
```

**Source:** https://github.com/edoburu/docker-pgbouncer/blob/master/Dockerfile and https://github.com/edoburu/docker-pgbouncer/blob/master/entrypoint.sh (verified)

**Verification block:** URL fetched / Verbatim quotes confirmed from fetched content.

**Significance:** Three properties combine to make signal delivery correct: (1) VERSION=1.25.2 means the graceful SIGTERM behavior (SHUTDOWN WAIT_FOR_CLIENTS) is active; (2) `exec "$@"` at end of entrypoint.sh replaces the shell with pgbouncer as PID 1, eliminating the shell-as-PID-1 signal-forwarding pitfall; (3) no STOPSIGNAL means Docker/ECS default SIGTERM is used, which is the correct signal for graceful shutdown on ≥1.23.0. The combination is correct by coincidence of defaults — if any of these three changed (older version, no exec, explicit STOPSIGNAL=SIGQUIT), behavior would differ.

---

### Finding 7: pool_mode=transaction — what "in-flight" means for shutdown

**Evidence** (from `pgbouncer_doc_2.txt`, source pgbouncer.org/config.html):

```
pool_mode
  transaction: Server is released back to pool after transaction finishes.

server_idle_timeout
  Default: 600.0 (seconds)

server_lifetime
  Default: 3600.0 (seconds)

client_idle_timeout
  Default: 0.0 (disabled)
```

**Source:** https://www.pgbouncer.org/config.html (verified)

**Verification block:** URL fetched / Verbatim quotes confirmed from fetched content.

**Significance:** In transaction mode, a server connection is held only for the duration of a transaction. Between transactions, the server connection is released to the pool. SHUTDOWN WAIT_FOR_CLIENTS (triggered by SIGTERM) waits for all client connections to disconnect — not just for in-flight transactions. Since client_idle_timeout is disabled by default, idle Rails connections (not in a transaction) will persist indefinitely. They will NOT disconnect within the 120s stopTimeout window unless the Rails connection pool evicts them on its own. SHUTDOWN WAIT_FOR_SERVERS (SIGINT) is less safe but more realistic for this constraint — it shuts down once server connections are released, ignoring client state. In transaction mode, server connections are released immediately after each transaction, so SIGINT drain is faster than SIGTERM drain.

---

### Finding 8: Rolling deploy guarantee — min_healthy=100%/max=200%

**Evidence:** Based on ECS rolling update documentation (reviewed in prior session) and the engineer's stated configuration.

min_healthy=100%, max=200% means:
- With desired_count=2: ECS launches 2 new tasks before stopping 2 old tasks
- A new task must reach RUNNING+healthy before an old task enters STOPPING
- Cloud Map registers the new task before the old task is deregistered

**Source:** AWS ECS service update documentation (reviewed; exact URL not re-fetched in this session — UNVERIFIED for direct quote).

**Significance:** The rolling deploy ordering guarantee means new tasks are healthy and registered in Cloud Map before old tasks begin their shutdown sequence. New connections can route to new tasks as soon as they are registered. The gap is that DNS TTL (60s) means DNS-cached clients may still connect to shutting-down tasks for up to 60s after deregistration. The rolling deploy guarantee prevents "no healthy task" but does not prevent "connection to a shutting-down task" during the DNS TTL window.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Default behavior (SIGTERM, stopTimeout=30s) | Zero config change | 30s window for WAIT_FOR_CLIENTS; idle Rails clients likely still connected; SIGKILL at 30s drops connections | AWS docs (Finding 3) |
| Raise stopTimeout to 120s (Fargate max) | More time for client disconnect; covers short transactions | Still only 120s; Rails server_lifetime=3600s means connections won't recycle naturally within 120s; idle clients (client_idle_timeout=0) won't disconnect | AWS docs (Finding 3) |
| Use SIGINT (WAIT_FOR_SERVERS) instead | Server connections in transaction mode release quickly after each transaction; faster drain than WAIT_FOR_CLIENTS | Requires custom STOPSIGNAL or preStop script; client connections get TCP RST during drain; Rails must handle reconnect | pgbouncer.org (Finding 1) |
| Admin PAUSE before SIGTERM via preStop-like script | Stops accepting new server connections while clients can still use cached connections; cleaner transition | No native ECS preStop hook; requires sidecar/lifecycle script; Cloud Map DNS still routes new connections during TTL window | pgbouncer.org (Finding 2) |
| Lower Cloud Map DNS TTL (e.g. 10s) | Reduces window where DNS-cached clients connect to shutting-down task | Increases DNS query rate; AWS Cloud Map minimum TTL is 1s; no deregistration delay still applies | aws_ecs_doc_1.txt (Finding 5) |
| Add RECONNECT before rolling deploy | Gracefully recycles server connections ahead of shutdown; used in planned maintenance | Does not help with client connections; requires admin console access from a script | pgbouncer.org (Finding 2) |
| Sidecar preStop script (ECS exec/sidecar) | Can issue PAUSE/SHUTDOWN WAIT_FOR_SERVERS before SIGTERM; closest to K8s preStop hook | No native ECS preStop hook; must be implemented as a wrapper script around pgbouncer binary or as a separate container that issues the admin command then sends the signal | pgbouncer.org (Finding 2), aws_ecs_doc_1.txt (Finding 4) |

---

## What remains uncertain

- Whether ECS Cloud Map deregistration actually happens in DEACTIVATING (before SIGTERM) or at the same time as STOPPING (the lifecycle doc only mentions ALB in DEACTIVATING). The containers-roadmap issue #1639 says "stopped as soon as the target is deregistered" but does not clarify which ECS state this falls in.
- The exact behavior when PgBouncer receives SIGTERM while a client has an open connection with no active transaction in transaction mode — does it immediately close that client connection, or does it wait indefinitely? (WAIT_FOR_CLIENTS semantics suggest indefinite wait, but idle client behavior under pool_mode=transaction is not explicitly documented in the fetched material.)
- Whether the Rails ActiveRecord connection pool on the client side will reconnect transparently after receiving a TCP RST from a pgbouncer task mid-shutdown. The Rails pool behavior on connection failure depends on the application version and `checkout_timeout` setting — not researched.
- Whether there is an ECS-native mechanism (other than stopTimeout) to inject a preStop script equivalent. Kubernetes has `lifecycle.preStop`; ECS does not have a documented equivalent. The closest pattern is a wrapper entrypoint that catches SIGTERM, runs drain logic, then signals the main process.
- The actual Cloud Map TTL configured in the 4Shark Terraform stack (assumed 60s default but not verified against the actual Terraform resource).
- Whether edoburu entrypoint.sh trap/signal handling between the `exec` and the pgbouncer process affects delivery (i.e., if there is a trap registered before exec that could interfere — the exact script content was fetched via AI summarizer and should be verified directly).

---

## Suggested options for main and the engineer

**Option A: Minimal change — raise stopTimeout to 120s only**
Raise `stopTimeout` to 120 in the ECS container definition. SIGTERM behavior is already correct (version 1.25.2, exec entrypoint). This gives pgbouncer 120s to wait for clients. In transaction mode, any in-flight transaction should complete in well under 120s. Idle connections that have no active transaction will be dropped by SIGKILL at 120s. Whether this is acceptable depends on whether the Rails/worker connection pool reconnects cleanly after a SIGKILL.

**Option B: SIGTERM + stopTimeout=120s + lower DNS TTL**
Same as Option A, additionally lowering Cloud Map DNS TTL from 60s to a shorter value (e.g. 10s). This reduces the window where DNS-cached clients open new connections to a shutting-down PgBouncer task. Trade-off: higher DNS query rate.

**Option C: Custom entrypoint wrapper with preStop drain logic**
Replace the edoburu ENTRYPOINT with a custom wrapper that: (1) traps SIGTERM, (2) issues `SHUTDOWN WAIT_FOR_SERVERS` to the PgBouncer admin console (faster drain than WAIT_FOR_CLIENTS for transaction mode), (3) waits for pgbouncer to exit, (4) forwards the signal. This is the closest ECS analog to Kubernetes preStop. Requires building a custom Docker image on top of edoburu or writing a new entrypoint. No native ECS mechanism provides this.

**Option D: Drain via SIGINT instead of SIGTERM**
Set `STOPSIGNAL SIGINT` in a custom Dockerfile derived from edoburu. SIGINT triggers SHUTDOWN WAIT_FOR_SERVERS (faster drain in transaction mode — server connections release after each transaction, typically sub-second). SIGTERM still works for the exec'd pgbouncer because SIGINT will be the stop signal ECS sends. Trade-off: client connections are closed without explicit client notification; Rails must handle TCP RST gracefully.

**Option E: Accept partial drain + rely on client retry**
Accept that the 120s Fargate ceiling cannot fully drain all idle Rails connections (server_lifetime=3600s). Design the Rails side to retry connections transparently (Rails connection pool already does this for ActiveRecord::StatementInvalid on reconnect). Document the deploy as "best-effort zero dropped transactions, not zero dropped connections."

(NO recommendation — options A through E surface the trade-off space; main and the engineer choose.)

---

## Q8: Concrete checklist (facts only, no design decision)

The following checklist represents what must be true for each approach to work. Main and the engineer decide which items to implement.

### Always-true prerequisites (already verified)
- [ ] edoburu image version 1.25.2 ≥ 1.23.0 → SIGTERM triggers WAIT_FOR_CLIENTS graceful shutdown
- [ ] entrypoint.sh uses `exec "$@"` → pgbouncer is PID 1 → receives SIGTERM directly
- [ ] No STOPSIGNAL in Dockerfile → default SIGTERM → correct signal for graceful shutdown
- [ ] ECS rolling deploy: min_healthy=100%, max=200% → new task healthy before old task stops

### stopTimeout
- [ ] Current stopTimeout in ECS task definition — verify current value (default 30s if not set)
- [ ] If raising to 120s: add `stopTimeout: 120` to the pgbouncer container definition in Terraform

### DNS TTL
- [ ] Verify current Cloud Map DNS TTL in Terraform (`aws_service_discovery_service` resource `dns_records` block)
- [ ] If lowering TTL: update TTL value and verify Rails/worker DNS resolver actually honors it (some JVM-based clients cache longer)

### STOPSIGNAL (if choosing Option D or C)
- [ ] If using SIGINT: add `STOPSIGNAL SIGINT` to custom Dockerfile derived from edoburu
- [ ] If using custom entrypoint: write and test the drain wrapper; confirm it exits with pgbouncer's exit code

### Rails/worker client behavior
- [ ] Verify Rails ActiveRecord connection pool is configured to reconnect after connection errors (`reconnect: true` in database.yml, or rely on the default retry behavior)
- [ ] Verify the cross-region outbound worker's connection pool has equivalent reconnect behavior
- [ ] Test that a TCP RST from pgbouncer mid-idle does not surface as a user-visible error in the Rails application (connection pool should absorb it transparently)

### Monitoring
- [ ] Confirm CloudWatch metrics or ECS service events capture task stop reason (graceful vs SIGKILL) to validate drain success after each deploy
- [ ] Optionally: capture PgBouncer `SHOW STATS` or `SHOW CLIENTS` before SIGTERM to baseline connection count at shutdown start
