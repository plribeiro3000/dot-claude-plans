# SPIKE — Pre-Deploy Sidekiq Queue-Check Binary: Feasibility and Mechanics

## Investigation question

The design is settled and is not re-opened here. This spike answers only the feasibility
and mechanics questions the design leaves open.

**The settled design** (given, per the engineer's explicit instruction):

- A script in `~/Projects/4Shark/dot-claude/scripts/`, auto-approved by one
  `permissions.allow` entry, invoked by the agent before an `app` deploy on a named
  stack (`beta-001`, `demo-001`, `shared-001`, `atento-001`).
- It measures two things: queue depth (how much is waiting) and whether anything is
  currently executing.
- `Computation` counters are rejected as a signal — there is one `Computation` per
  commission, so checking thousands of keys at deploy-check time is infeasible. This
  spike does not propose it, include it in any option, or revisit it.
- Sampling: 10 reads, 10 seconds apart (~100s window).
- Verdict rule: variation across the series, not a threshold constant. A breathing
  queue (`1 → 0 → 1 → 0`) is GO; a ramp (`0 → 1 → 1000 → 8000`) is HOLD. Nothing
  executing across the whole series AND no upward ramp in depth ⇒ safe to deploy. This
  rule is the engineer's; this spike does not redesign it.
- Network: direct to the Redis Cloud public endpoint over TLS, no VPN — `source_ips`
  is `0.0.0.0/0` on every stack today.

**What this spike answers** (open because unresolved, not because they are choices):

1. The credential path — can a local script read `REDIS_SIDEKIQ_URL` (or its
   per-stack equivalent) from SSM using the default read-only AWS profile?
2. The concrete read mechanics — the exact Redis commands for queue depth and
   busy/executing, verified against the pinned Sidekiq source.
3. Whether `redis-cli` alone can do the read, or a real language is needed.
4. The script-shape convention that earns a single allow-list entry.

## Sources consulted

- Live AWS command: `aws sts get-caller-identity` — confirms which identity the
  default profile resolves to.
- Live AWS commands: `aws ssm get-parameter --with-decryption` against all four
  stacks' `REDIS_SIDEKIQ_URL`/`REDIS_URL` parameters. See auxiliary:
  `sidekiq-queue-check-binary_log_1.txt` — full metadata-only output (no credential
  values), and the interpretation.
- `~/Projects/4Shark/terraform/app-{shared,atento,beta,demo}-001/ssm.tf` — per-stack
  SSM secret name lists, read in full this revision.
- `~/Projects/4Shark/terraform/app-{shared,atento,beta,demo}-001/redis.tf` — per-stack
  `source_ips` and module topology, re-confirmed by direct grep this revision.
- `~/Projects/4Shark/terraform/modules/redis_cloud/README.md` — TLS/no-VPC-peering
  limitation, re-read this revision.
- `~/Projects/4Shark/terraform/app-{shared,atento,beta,demo}-001/.envrc` — confirms
  the `REDISCLOUD_ACCESS_KEY`/`REDISCLOUD_SECRET_KEY` pair is a different credential
  (the Redis Cloud provider's own API key), not usable for this binary.
- `~/Projects/4Shark/app/lib/application_configuration.rb` — the `redis_sidekiq_url`
  fallback chain and the Sidekiq client/server TLS config, re-read this revision.
- `~/Projects/4Shark/app/Gemfile.lock:665` — pins the Sidekiq gem version
  (`sidekiq (8.0.10)`) that fixes which tag to cite for `lib/sidekiq/api.rb`.
- [raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb](https://raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb) —
  downloaded fresh to `/tmp/sidekiq_api_v8010.rb` (1348 lines, confirmed with `wc -l`)
  and read locally with `grep -n` / ranged `Read` for every line number cited. See
  auxiliary: `sidekiq-queue-check-binary_excerpt_1.rb`.
- [github.com/sidekiq/sidekiq/wiki/API](https://github.com/sidekiq/sidekiq/wiki/API) —
  fetched fresh this revision, two passes (survey + self-check re-fetch). See
  auxiliary: `sidekiq-queue-check-binary_doc_1.md`.
- [diogoribeiro7.github.io — Mann-Kendall Test](https://diogoribeiro7.github.io/time-series%20analysis/detecting_trends_timeseries_data/) —
  optional prior-art finding on ramp detection, per the engineer's invitation. See
  auxiliary: `sidekiq-queue-check-binary_doc_1.md`.
- `~/.claude/scripts/ruby.sh`, `~/.claude/scripts/terraform.sh` — read in full this
  revision for the script-shape convention. See auxiliary:
  `sidekiq-queue-check-binary_excerpt_4.sh`.
- `~/.claude/settings.json:79,90,97` — allow-list entry shape for existing wrapper
  scripts, re-confirmed by grep this revision.
- Local machine probes (`redis-cli --version`, `python3 -c "import redis"`) — tool
  availability on this machine only, not a documented team baseline.

## Findings

### Finding 1: The default read-only AWS profile CAN decrypt the SSM SecureString on every stack where the relevant parameter name exists

**Evidence:**
```
/shared-001/REDIS_SIDEKIQ_URL  → SUCCESS, Type: SecureString, Version: 2,
                                  ValueLength: 112, ValueIsPlaceholder: false
/atento-001/REDIS_SIDEKIQ_URL  → SUCCESS (valid JSON, non-placeholder Value)
/beta-001/REDIS_URL            → SUCCESS, Type: SecureString, ValueLength: 113
/demo-001/REDIS_URL            → SUCCESS, Type: SecureString, ValueLength: 113
```
**Source:** live `aws ssm get-parameter --name "<name>" --with-decryption --region
us-east-1 --output json`, run against the default (read-only) AWS profile during this
spike, 2026-07-17. Full metadata preserved in `sidekiq-queue-check-binary_log_1.txt`.
Identity resolved for that profile: `arn:aws:iam::405749097490:user/paulo@4shark.com.br`
(`aws sts get-caller-identity`, same log file).

**Significance:** This resolves the biggest open question from the prior revision of
this spike. No `AccessDenied`, no KMS decrypt failure. The script can read the live
Redis connection credential using the SAME default profile the agent already uses for
every other read-only AWS operation — no MFA elevation, no additional IAM grant, no
separate profile. The credential value itself was never printed at any point during
this test (only JSON metadata fields were parsed and reported, per the Never-Emit-a-
Credential-Value rule).

### Finding 2: The parameter NAME differs by stack — `REDIS_SIDEKIQ_URL` on two stacks, `REDIS_URL` on the other two, and the app's own fallback chain explains why

**Evidence:**
```
/beta-001/REDIS_SIDEKIQ_URL   → FAILURE: "An error occurred (ParameterNotFound)
                                  when calling the GetParameter operation:"
/demo-001/REDIS_SIDEKIQ_URL   → FAILURE: same ParameterNotFound
```
```
315     def redis_sidekiq_url
316       ENV.fetch('REDIS_SIDEKIQ_URL', redis_url)
317     end
```
**Source:** live SSM test (as above) plus `~/Projects/4Shark/app/lib/application_configuration.rb:315-317`.
Cross-checked against each stack's `ssm.tf`: `app-shared-001/ssm.tf:17` and
`app-atento-001/ssm.tf:21` both list `"REDIS_SIDEKIQ_URL"` in `ssm_secret_names`;
`app-beta-001/ssm.tf` and `app-demo-001/ssm.tf` list only `"REDIS_URL"` — no
`REDIS_SIDEKIQ_URL` entry exists in either file (confirmed by reading both files in
full). Full excerpts in `sidekiq-queue-check-binary_excerpt_2.tf` and
`sidekiq-queue-check-binary_excerpt_3.rb`.

**Significance:** A script that must work across all four stacks CANNOT read a single
hardcoded parameter name. `redis_sidekiq_url` falls back to `redis_url` (`REDIS_URL`)
when `REDIS_SIDEKIQ_URL` is not set — this is exactly why beta-001/demo-001 have no
dedicated Sidekiq Redis parameter (per the earlier finding that these two stacks
provision one combined Redis Cloud database for both cache and Sidekiq, while
shared-001/atento-001 provision two separate databases). The script needs to try
`/<stack>/REDIS_SIDEKIQ_URL` first and fall back to `/<stack>/REDIS_URL` on
`ParameterNotFound`, mirroring the app's own Ruby fallback chain exactly.

### Finding 3: A different Redis credential exists in each stack's `.envrc` and is NOT usable for this purpose

**Evidence:**
```
export REDISCLOUD_ACCESS_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_ACCESS_KEY").value')"
export REDISCLOUD_SECRET_KEY="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "REDISCLOUD_SECRET_KEY").value')"
```
**Source:** `~/Projects/4Shark/terraform/app-shared-001/.envrc:16-17` (identical shape
in `app-atento-001`, `app-beta-001`, `app-demo-001`, confirmed by grep across all four
this revision).

**Significance:** This is the Redis Cloud PROVIDER's own API key — what Terraform uses
to manage the `rediscloud_essentials_*` resources (create/modify the subscription and
database) — not the database connection credential the app's Sidekiq client
authenticates with. It cannot be used to connect to the Sidekiq Redis as a client. The
only correct credential path is the SSM parameter from Findings 1-2.

### Finding 4: `Sidekiq::Stats#fetch_stats_slow!` is the exact, Sidekiq-maintained implementation of both aggregates the binary needs, in ONE pipelined round trip per read

**Evidence:**
```
134     def fetch_stats_slow!
135       processes = Sidekiq.redis { |conn|
136         conn.sscan("processes").to_a
137       }
138
139       queues = Sidekiq.redis { |conn|
140         conn.sscan("queues").to_a
141       }
142
143       pipe2_res = Sidekiq.redis { |conn|
144         conn.pipelined do |pipeline|
145           processes.each { |key| pipeline.hget(key, "busy") }
146           queues.each { |queue| pipeline.llen("queue:#{queue}") }
147         end
148       }
149
150       s = processes.size
151       workers_size = pipe2_res[0...s].sum(&:to_i)
152       enqueued = pipe2_res[s..].sum(&:to_i)
153
154       @stats[:workers_size] = workers_size
155       @stats[:enqueued] = enqueued
156       @stats
157     end
```
**Source:** [raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb](https://raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb):134-157.
Downloaded to `/tmp/sidekiq_api_v8010.rb` this revision; every line number above
confirmed by `grep -n "def fetch_stats_slow!\|workers_size = pipe2_res\|enqueued =
pipe2_res"` against that local file, and independently by a ranged `Read` at
offset 100-170. Full excerpt with surrounding context in
`sidekiq-queue-check-binary_excerpt_1.rb`.

**Significance:** This IS the concrete read mechanics for both signals in the settled
design, expressed exactly as Sidekiq itself implements them:

- **Queue depth** ("enqueued"): `SSCAN queues` → the set of currently-known queue
  names; for each name, `LLEN queue:<name>`; sum every length. `queues` is confirmed a
  Redis SET (not a Hash or Sorted Set) because it is read with `SSCAN`, a Set-scan
  command (`Sidekiq::Queue.all`, lines 243-245, same file).
- **Currently executing** ("workers_size" / busy): `SSCAN processes` → the set of
  currently-registered process identity keys; for each key, `HGET <identity> busy`
  (the pipelined form shown above) or `HMGET <identity> busy` (the equivalent form
  used by `ProcessSet.[]` and `ProcessSet#each`, lines 934-938 and 986-999 of the same
  file); sum every busy count. Each process's own Redis key is a HASH keyed by its
  identity string, registered as a member of the `processes` SET.
- Nothing executing across the whole series ⇒ `workers_size == 0` on every one of the
  10 reads. No upward ramp in depth ⇒ the `enqueued` series across the 10 reads shows
  no sustained increase (the verdict rule itself is the engineer's, not redesigned
  here).

The `ProcessSet` doc comment (`lib/sidekiq/api.rb:924-927`) states each process "sends
a heartbeat to Redis every 5 seconds" — the Sidekiq wiki independently states
`Sidekiq::ProcessSet` data is "near real-time (updated every 5 sec)"
([github.com/sidekiq/sidekiq/wiki/API](https://github.com/sidekiq/sidekiq/wiki/API),
confirmed present on two separate fetches this revision). This means the underlying
busy/process data itself only refreshes every 5 seconds regardless of how often the
script polls — the settled 10-second sampling interval already polls at roughly twice
the underlying refresh cadence, not faster.

### Finding 5: `redis-cli` alone cannot do the depth/busy sum in a single simple invocation without either a Lua script file or multiple round trips; no dedicated client library is installed on this machine for either candidate language

**Evidence:**
```
--eval <file>      Send an EVAL command using the Lua script at <file>.
-u <uri>           Server URI on format redis://user:password@host:port/dbnum
                   ... For TLS, use the scheme 'rediss'.
--tls              Establish a secure TLS connection.
-a <password>      Password to use when connecting to the server.
                   You can also use the REDISCLI_AUTH environment
                   variable to pass this password more safely
```
**Source:** `redis-cli --help` output, captured live this revision (`redis-cli 8.0.3`
installed on this machine via Homebrew). Full relevant excerpt in
`sidekiq-queue-check-binary_excerpt_4.sh`; full raw dump referenced in
`sidekiq-queue-check-binary_log_1.txt`.

```
python3 -c "import redis; print(redis.__version__)"
  ModuleNotFoundError: No module named 'redis'
```
**Source:** live command run on this machine this revision.

**Significance:** `redis-cli` supports exactly one command per invocation (or a
Lua script via `--eval <file>`, or the raw `--pipe` protocol mode); it has no built-in
facility to enumerate `SSCAN queues`, loop `LLEN` over each member, and sum the results
in one call. That leaves three paths, stated as a constraint rather than a choice:

1. **Multiple sequential `redis-cli` invocations** — one process (and, since the
   connection is not kept open between invocations, one fresh TCP+TLS handshake) per
   `SSCAN`/`LLEN`/`HGET` command, then sum in the surrounding shell — fragile output
   parsing, and for 10 sample rounds this multiplies quickly (10 rounds × (2 SSCAN + N
   queues + M processes) round trips).
2. **A single Lua script via `--eval`** — mirrors Sidekiq's own pipelining semantics in
   one round trip, but requires shipping and maintaining a separate `.lua` file
   alongside the shell script, and this spike found no confirmation either way of
   whether Redis Cloud Essentials permits arbitrary `EVAL` (not tested — see "What
   remains uncertain").
3. **A real language with a Redis client library** — pipelines naturally, reuses one
   connection across all 10 sample rounds, but neither candidate is pre-installed on
   this machine: the Ruby `redis` gem is not installed for the system Ruby (confirmed
   in the prior spike revision and unchanged), and the Python `redis` library is not
   installed either (confirmed this revision, `ModuleNotFoundError: No module named
   'redis'`). Either would need an explicit `gem install`/`pip install` step that is
   not a documented team baseline today.

This is the constraint the engineer asked to have reported plainly, not resolved —
which of the three paths a script takes decides its implementation language, and that
decision is left to whoever builds it.

### Finding 6: `terraform.sh`'s "read-only by construction" pattern is the safer template to copy; `ruby.sh`'s "exec the caller's argument" shape is flagged by its own sibling's comment as a risk

**Evidence:**
```
# READ-ONLY BY CONSTRUCTION — the safety property that makes a single broad
# `Bash(bash ~/.claude/scripts/terraform.sh:*)` allow entry safe: this wrapper
# REFUSES every write subcommand (apply/destroy/import/taint/untaint/refresh,
# `state` other than list/show, and any unrecognized subcommand). It cannot run
# a write, so the allow entry can only ever approve a read. ...
#
# The `terraform` binary is HARDCODED here (never taken from an argument and
# exec'd, unlike ruby.sh) — closing the "environment runner execs its arguments"
# risk that the Claude Code permission docs warn about.
```
**Source:** `~/.claude/scripts/terraform.sh:21-33`, read in full this revision.

```
if [[ -x "$WRAPPER_DIR/$TOOL" ]]; then
  exec "$WRAPPER_DIR/$TOOL" "$@"
fi
```
**Source:** `~/.claude/scripts/ruby.sh:88-90` (and the equivalent `exec "$SHIMS_DIR/$TOOL" "$@"` shapes at lines 97 and 105 for rbenv/asdf) — `$TOOL` is a caller-supplied
positional argument, `exec`'d directly.

**Significance:** For a NEW single-purpose script, `terraform.sh`'s pattern is the one
to copy: hardcode the small set of allowed operations (here: the specific read-only
Redis commands the binary needs — `SSCAN`, `LLEN`, `HGET`/`HMGET` against `queues` and
`processes` — nothing else), refuse anything else explicitly, and never `exec` a
caller-supplied binary/command string. `ruby.sh`'s `exec "$TOOL"` shape is appropriate
for a general-purpose Ruby-command wrapper (its whole job is running an arbitrary
Ruby tool) but is exactly the shape `terraform.sh`'s own header comment names as a risk
it deliberately avoids — not a pattern to copy for a narrow, single-purpose binary.

Both scripts share: `set -euo pipefail` at the top (`ruby.sh:35`, `terraform.sh:43`);
the secret/credential read happens INSIDE the script body (`ruby.sh:64` —
`export RAILS_MASTER_KEY="$(< config/master.key)"`) so it never appears in the
invocation line the permission matcher (or the agent's own visible Bash tool call)
evaluates; and a first positional argument that identifies the TARGET
(`terraform.sh <stack-dir> ...`) rather than relying on cwd, which does not carry over
to subagents or cross-repo one-offs anyway. Full excerpts in
`sidekiq-queue-check-binary_excerpt_4.sh`.

### Finding 7: The allow-list entry shape for a new script is a single line, matching the existing wrappers

**Evidence:**
```
79:      "Bash(bash ~/.claude/scripts/ecs-scale.sh:*)",
90:      "Bash(bash ~/.claude/scripts/ruby.sh:*)",
97:      "Bash(bash ~/.claude/scripts/terraform.sh:*)",
```
**Source:** `~/.claude/settings.json:79,90,97`, confirmed by grep this revision.

**Significance:** A new script earns the same one-line entry:
`"Bash(bash ~/.claude/scripts/<new-script-name>.sh:*)"`. This is a configuration change
to the tracked `settings.json` (via a dot-claude PR, per CLAUDE.md § Configuration
Changes Policy) — not something this spike does or recommends timing for; it is the
mechanical shape the existing precedent already establishes.

## What remains uncertain

- Whether Redis Cloud Essentials permits arbitrary `EVAL` (Lua scripting) against the
  Sidekiq database — not tested. Testing this would require connecting directly to the
  production Sidekiq Redis with the live credential, which this spike deliberately did
  not do: constructing a `redis-cli -u "<url>"` command puts the credential value into
  the Bash tool's own visible invocation (not merely into a printed result), which this
  spike treated as the same class of exposure the Never-Emit-a-Credential-Value rule
  guards against. A live connectivity test needs a script that reads the credential
  internally (mirroring `ruby.sh`'s pattern) — i.e., building at least a minimal reader
  first, which is outside this spike's remit ("do not write the script").
- Whether the local machine's default TLS trust store validates the Redis Cloud
  endpoint's certificate without `redis-cli --insecure`, or whether `--insecure` is
  required to match the app's own `ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }`
  stance (`~/Projects/4Shark/app/lib/application_configuration.rb:141,162`) — untested,
  for the same credential-exposure reason above.
- Whether any additional per-process or per-queue Redis Cloud Essentials rate limit
  or connection-count constraint applies to 10 short-lived connections over ~100
  seconds — not found in `~/Projects/4Shark/terraform/modules/redis_cloud/README.md`
  or elsewhere in the repository; would need Redis Cloud's own documentation, not
  fetched in this revision (out of the scope the engineer defined).
- The exact IAM grant that lets the default read-only profile (the personal IAM user
  `paulo@4shark.com.br`) decrypt these specific SSM SecureStrings — the
  `ecsTaskExecutionRole` policies visible in each stack's `ssm.tf` are a DIFFERENT
  principal and do not explain this profile's access (see the note in
  `sidekiq-queue-check-binary_excerpt_2.tf`). The live test confirms the access WORKS;
  it does not identify which IAM policy/permission-set grants it. Investigating that
  further was judged out of scope for a feasibility spike once the live test itself
  succeeded.
- Whether a minimum-sample-size threshold applies to the Mann-Kendall test (or any
  similar trend statistic) at 10 observations — the one fetched source
  (`sidekiq-queue-check-binary_doc_1.md`) did not discuss this, and no other source was
  fetched to check it; the sample count is fixed by the engineer regardless.

Everything else the settled design depends on — the credential path, the exact Redis
read commands, and the script-shape convention — is answered above with a live test or
a source-code citation, not left open.
