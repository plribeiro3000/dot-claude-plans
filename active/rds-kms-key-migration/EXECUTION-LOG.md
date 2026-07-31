# EXECUTION LOG — first manual run of the database key migration

The engineer's instruction was to execute the procedure by hand, record the commands and the problems as they happen, and build the skill and binary from that record afterwards. This is that record. It is written as it happens, so a wrong turn stays in it — the wrong turns are the point.

Environment: `app-beta-001` (non-productive, plain RDS PostgreSQL 18.4, 20 GB). Source `app-beta-001`, target `app-beta-001-2`, application database `app_beta_001`.

## Findings so far — each one changes the script's design

### 1. The client version must be checked against the server before anything

The machine had PostgreSQL 17.5 client tools; both databases are 18.4. `psql` is version-tolerant and works fine, but `pg_dump` and `pg_dumpall` **refuse** a server newer than themselves, which would have failed mid-procedure at the schema step rather than up front.

Installing the 18 client is blocked for the agent by the local-databases hook (*"one-time machine setup is not Claude's call"*), so the engineer ran `brew install postgresql@18`. Homebrew does not link a versioned formula onto the `PATH`, so the binaries are called by absolute path: `/opt/homebrew/opt/postgresql@18/bin/`.

**For the script**: check `pg_dump --version` against the server's `SELECT version()` as a pre-flight, fail with a clear message naming the install command, and never attempt the install itself.

### 2. Secrets Manager and the database were never reachable at the same time — and it was not the VPN

With the VPN connected, `aws secretsmanager list-secrets` and `get-secret-value` hung indefinitely — no error, no refusal — while `aws rds describe-db-instances` and `aws cloudwatch get-metric-statistics` answered normally. A request that eventually escaped returned `InvalidSignatureException: Signature expired`, which is the symptom of having sat unsent for six minutes, not the cause.

The diagnosis went wrong three times before it went right. It was called a permission prompt, then an expired signature, then a permission prompt again. What settled it was a discriminating test — swapping `get-secret-value` for `list-secrets`, which returns no secret value and hung identically, ruling out anything specific to reading a credential. The attribution to the VPN was then also wrong: the real cause was **the engineer's router advertising a broken IPv6 route**, which the engineer found and fixed. After the fix, `get-secret-value` returned immediately.

**For the script**: a hang with no output on an AWS API call is not a permission prompt and not a credentials problem — bound every AWS call with a timeout and report which endpoint stopped answering, so the next person does not spend three diagnoses on it.

### 3. The RDS secret ARN breaks interactive zsh

The ARN contains `!` (`rds!db-...`), which zsh expands as history. A command carrying it unquoted dies with `zsh: event not found: db` before running at all.

**For the script**: single-quote every secret ARN it emits or embeds.

### 4. `.pgpass` cannot hold an RDS-generated password reliably — use `PGPASSWORD`

`.pgpass` uses `:` as its field separator, and RDS's managed master password is 28 characters including punctuation, so it can contain a colon. It did here.

The failure is quiet and misleading: `libpq` finds the line and reports `password retrieved from file`, then fails authentication, so it reads as a wrong password rather than a malformed file. It was diagnosed structurally without reading any credential — `awk -F: '{print NF}'` showed **6 fields on the target line and 5 on the source line**, which is the whole story.

Escaping the colon as `\:` per the libpq format did **not** fix it, and the reason was not established — the attempt is recorded as failed rather than explained. What worked was abandoning the file entirely and passing `PGPASSWORD` from the secret at invocation time.

**For the script**: never write a `.pgpass`. Take the password into the environment for the single command that needs it. This also happens to be better hygiene — nothing durable on disk.

### 5. The two masters are independent

Source and target each manage their own secret with their own password. Anything that dumps from one into the other needs both, retrieved separately. The target's secret is encrypted under the environment's own key, which was set at creation because it is immutable afterwards.

## Verified state at this point

Both databases reachable over the VPN from the engineer's machine, `psql` 18.4 against servers 18.4. Source is `app_beta_001` with the application schema; target is an empty instance whose `postgres` database answers but which has no application database yet.

Connection shape that works, and the one the script should use:

```
PGPASSWORD=<from secret> psql --host <endpoint> --username postgres --dbname <db> --command "<sql>"
```

## Still to do

Phase 1 from `PLAN.md` continues at the roles: extract with `pg_dumpall --roles-only`, triage out the RDS-internal roles, load ours into the target. Then the database, the schema, the publication, the subscription, the lag watch, and the sequence advancement.
