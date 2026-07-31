# SPIKE — Repointing the connection pooler at a new database with zero downtime

## Question

A key migration replaces an environment's database with an encrypted successor filled by logical replication. Moving the application onto the successor means changing the backend the connection pooler talks to. **How is that done with zero downtime — no failed request, no dropped connection?**

The candidate under examination: update the pooler's environment variables to name the new database and deploy. Old tasks keep the old values and keep serving; new tasks come up on the new values; the ECS deployment handles the transition.

## Answer

The candidate does not work, and the reason is not the one it looks like. **It fails on correctness, not on downtime.**

Any deployment that replaces tasks gradually — rolling or blue/green — has a period where old tasks and new tasks are both serving. Old tasks write to the source; new tasks write to the target. Logical replication runs one way, source to target, which makes that overlap a data-integrity failure and not merely an inconsistency:

- The two databases issue primary keys from **independent sequences**. After the sequence advancement they are aligned, so both hand out the same next value. A row created on the target takes id N; a row created on the source takes id N and then replicates to the target, where it collides. **The subscription halts on the unique violation** — the migration stops mid-cutover with writes on both sides.
- A user's write lands on the target through a new task; their next read arrives at the source through an old task and does not find it.

Atomicity is therefore a requirement, and no deployment strategy provides it: gradual replacement is what a deployment *is*.

**The working design keeps the candidate's shape and moves what changes.** The thing the pooler reads must change without producing a new task definition — a DNS record it resolves rather than an environment variable baked into its task. And the transition must be atomic, which PgBouncer provides by holding clients rather than disconnecting them.

## Findings

### 1. The pooler service is rolling, not blue/green

`modules/connection_pooler/main.tf:351-353` sets `deployment_controller { type = "ECS" }`, and `main.tf:342-344` registers the service through `service_registries` — plain Cloud Map service discovery. There is no load balancer and no Service Connect.

The premise that "the deploy is already zero downtime because it is blue/green" describes a different service. Blue/green via CodeDeploy is the app's **web** service; the pooler is a rolling deployment.

*Verification: read at `~/Projects/4Shark/terraform/modules/connection_pooler/main.tf`, lines quoted above.*

### 2. ECS blue/green cannot manage traffic shifting for this service

Verbatim, from [Required resources for Amazon ECS blue/green deployments](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/blue-green-deployment-implementation.html):

> "When your service uses Elastic Load Balancing or Service Connect, Amazon ECS manages the traffic shift between the blue and green service revisions for you. If your service doesn't use a load balancer or Service Connect (headless service), you can still use blue/green deployments for controlled rollouts, but Amazon ECS doesn't manage the traffic shift automatically."

> "For managed traffic shifting, configure one of the following: Elastic Load Balancing, Service Connect"

Cloud Map service discovery (`service_registries`) is neither. Adopting blue/green here would yield a *headless* blue/green: bake time and rollback controls, with no managed shift. Both revisions register in Cloud Map and clients resolve across both — the overlap is not reduced, it is renamed.

*URL fetched. Verbatim quotes checked. Quote substrings confirmed in the page body under "Required resources for Amazon ECS blue/green deployments".*

### 3. The pooler already drains gracefully — and still disconnects clients at the end

`main.tf:270-284` is deliberate about this: `stopTimeout = 120` (the Fargate maximum), the image's `STOPSIGNAL` is SIGINT, and a `pg_isready` health check gates the rolling deploy so an old task drains only once a new one answers.

SIGINT is, verbatim from the [PgBouncer usage documentation](https://www.pgbouncer.org/usage.html), *"Safe shutdown. Same as issuing SHUTDOWN WAIT_FOR_SERVERS on the console."* And that command is:

> "Stop accepting new connections and shutdown after all servers are released. This is basically the same as issuing PAUSE and SHUTDOWN, except that this also stops accepting new connections while waiting for the PAUSE as well as eagerly disconnecting clients that are waiting to receive a server connection."

It waits for **servers** to be released, not for clients to leave. Clients are disconnected when the process exits. The variant that never drops a client is `SHUTDOWN WAIT_FOR_CLIENTS` — *"shutdown the process once all existing clients have disconnected"* — which a Rails connection pool would keep waiting on indefinitely, so it would reach the 120s ceiling and be killed anyway.

The practical consequence is narrow but real: because the shutdown waits for in-flight transactions, no query is killed mid-statement, and the disconnect lands between transactions where a connection pool can reconnect. **Whether the application's pool reconnects transparently there has not been measured** and should not be assumed.

*URL fetched. Verbatim quotes checked. Quote substrings confirmed in the "Signals" and "SHUTDOWN" sections.*

### 4. PgBouncer holds clients rather than dropping them, and the pool mode is what makes it fast

Verbatim, from the [PgBouncer usage documentation](https://www.pgbouncer.org/usage.html):

> "New client connections to a paused database will wait until RESUME is called."

and, on what `PAUSE` waits for:

> "PgBouncer tries to disconnect from all servers. Disconnecting each server connection waits for that server connection to be released according to the server pool's pooling mode"

`pool_mode` is `transaction` (`modules/connection_pooler/variables.tf:66-70`, not overridden by the app stacks), so a server connection is released at the end of **each transaction**. `PAUSE` therefore completes in milliseconds. Under `session` pooling, release happens when the client goes away — which for a Rails pool is never — so **this design is contingent on the pool mode and is not universal**.

Blocking a client is what separates a pause from an outage: the request waits, it does not fail.

*URL fetched. Verbatim quotes checked. Quote substrings confirmed in the "PAUSE" and "RESUME" entries.*

### 5. A DNS change is a first-class trigger for PgBouncer, not a trick

`SHOW SERVERS` documents a `close_needed` field, verbatim:

> "1 if the connection will be closed as soon as possible, because a configuration file reload or DNS update changed the connection information or RECONNECT was issued."

So pointing the pooler's backend at a name we control, and changing what that name resolves to, is a supported way to move the backend — with no new task definition and therefore no task replacement. `RECONNECT` makes it deterministic rather than waiting out a DNS cache:

> "Close each open server connection for the given database, or all databases, after it is released (according to the pooling mode), even if its lifetime is not up yet."

The resolution path already exists: each app VPC is associated with the shared `4shark.internal` private zone (`app-beta-001/connection_pooler.tf:62-66`).

*URL fetched. Verbatim quotes checked. Quote substrings confirmed under "SHOW SERVERS" and "RECONNECT".*

### 6. Console access for those commands is not configured

Verbatim, from the [PgBouncer configuration documentation](https://www.pgbouncer.org/config.html):

> **admin_users** — "Comma-separated list of database users that are allowed to connect and run all commands on the console."

> **stats_users** — "Comma-separated list of database users that are allowed to connect and run read-only queries on the console. That means all `SHOW` commands except `SHOW FDS`."

The rendered `.ini` (`main.tf:46`) sets `stats_users` only. `PAUSE`, `RESUME` and `RECONNECT` are unreachable until an `admin_users` entry exists.

*URL fetched. Verbatim quotes checked. Quote substrings confirmed under the parameter entries of the same name.*

### 7. Real-world practice converges on pause-and-switch

Fresha's account of upgrading *"20+ PostgreSQL databases from PG12 to PG17"* describes the switch as *"pause/resume to freeze connections during the switchover"*, with the backend changed via the admin console (`SET conffile = '/etc/pgbouncer/pgbouncer_new_rw.ini'; RELOAD;`).

**Marked partially UNVERIFIED**: the article does not publish the elapsed pause duration, the exact command sequence executed in production, or evidence that no connection was dropped. It corroborates the *shape* of the answer and may not be cited for timing or for a zero-dropped-connection claim.

*URL fetched. Quotes above confirmed present. The absent detail is stated as absent rather than inferred.*

## Options considered

| Option | Zero downtime | Atomic (no split brain) | Verdict |
|---|---|---|---|
| A — new env var + rolling deploy | Partly: drains gracefully (F3), but disconnects clients at task exit | **No** — overlap by construction | Rejected on correctness |
| B — ECS blue/green, headless | Same as A | **No** — ECS does not manage the shift (F2); both revisions in Cloud Map | Rejected; adds machinery, removes nothing |
| C — backend behind a CNAME, no pause | Yes — no task replacement at all | **No** — server connections recycle gradually, so both databases take writes during the window | Rejected on correctness |
| D — **CNAME + PAUSE / RECONNECT / RESUME** | Yes — clients are held, never dropped (F4) | **Yes** — no task serves the target until every task has stopped serving the source | **Adopted** |

Option D is derived from findings 4, 5 and 6, each verified against vendor documentation, and corroborated in shape by finding 7.

## What Option D requires

Two changes to `modules/connection_pooler`, neither of which belongs on cutover day:

1. **An `admin_user` variable rendered as `admin_users`** in the `.ini`, with that user added to the userlist secret (finding 6).
2. **The backend `host` moved onto a CNAME** in `4shark.internal` pointing at the current database, with a low TTL (finding 5).

Change 2 is itself a task-replacing deploy, since it edits the rendered `.ini` and therefore the task definition. It lands on an ordinary day, and the cutover afterwards changes only what the record resolves to.

The cutover then runs: `PAUSE` on **every** pooler task → confirm zero replication lag → advance sequences → repoint the CNAME → `RECONNECT` → `RESUME`.

**`PAUSE` is per-process.** Cloud Map round-robins across tasks, so a command sent to the service name reaches one of them; an un-paused task keeps writing to the source for the whole cutover, which is precisely the split-brain this design exists to prevent. Resolve each task's IP and issue the command to each.

## What remains unmeasured

**The duration of the pause.** Steps between `PAUSE` and `RESUME` — lag check, sequence advancement, DNS change, `RECONNECT` — are the entire client-visible cost, and no source establishes what that is on a real dataset. This is the number the non-productive run exists to produce, and it is what decides whether the productive environments need anything beyond this design.

**Whether a Rails connection pool reconnects transparently when a pooler task exits** (finding 3). Option D removes this from the cutover path, since no task is replaced. It still applies to the ordinary deploy that introduces the CNAME, and to every future pooler deploy.
