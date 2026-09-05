# PLAN — Validate integrator `develop` on Atento MX staging and release it to every productive integrator

> Reference: `ANALYSIS.md` in this directory (current state and findings F1–F14); `../integrator/unified-integration-flow/PLAN.md` (the change under test; its release gate 6.6 is what this plan executes); `../integrator/develop-image-incident/ANALYSIS.md` (the F1 defect and its validated fix); `../atento-mexico-vkpi-integration/PLAN.md` (the work this release unblocks).

## Objective

Prove on the Atento MX staging integrator that the `develop` code — customer database configuration read from MongoDB instead of environment variables, populated by `rake integration:normalized:bootstrap` — integrates a normalized base end to end with the same behavior `master` (8.4.25) has, then cut release 8.5.0 and roll it out to every productive integrator, so that in the week of 2026-09-14 the Atento México indicator work starts on a fleet already running the unified flow.

## Scope

### In scope

- The two defects that stop `develop` from running at all (F1 `Stream.none?`, F2 `warm_up?`), fixed on `develop` before anything is tested
- The staging environment change: report recipient moved to the internal mailbox. The source time zone (F3) is settled in code, not in the environment: the bootstrap seeds every normalized source in `UTC`
- Deploy of the develop image to `atento-mx-staging`, bootstrap, a full first run and an incremental second run, with a written parity checklist against `master`'s behavior
- Release 8.5.0 (HubFlow), the normalized-schema version cut, and the per-integrator rollout runbook (deploy + bootstrap per environment)
- No Terraform change for the productive bootstraps: the time zone is seeded by the bootstrap itself, so no deployment carries a time zone variable

### Out of scope

- The VKPI indicator source and Modifier stream for Mexico (`../atento-mexico-vkpi-integration/PLAN.md` Phase 1) — starts after this plan closes
- Removing the dead environment variables from the Terraform stacks (F9) — a cleanup PR per stack after every deployment is bootstrapped
- The `Ecs.scale_down` silent rescue (F10, `../integrator/shutdown-worker-fix/PLAN.md`) — observed, not fixed here
- Worker and rake-task spec coverage (F4) — a follow-up; this plan relies on the staging run as the test

## Chosen approach

**Direction:** validate on `atento-mx-staging` with real QA-shaped data (the staging harvester loading the Simplex QA source into `glazrdbvp051`), then release once, then roll out one productive integrator at a time — deploy immediately followed by bootstrap, outside that integrator's processing window.

**Rationale:** the engineer's ask (2026-09-04) — test `develop` on the Atento México homologation environment first, release everything on `develop` to production before the indicator work begins. Staging is the only environment where develop code, QA data and the customer-shaped Azure SQL database meet without touching production, and it is the environment the unified-flow plan already named for its pending gate.

**Source patterns referenced:** `deploy.yaml` (preflight → migrate → rolling), `integrator-preview.sh` (`integration:start` with `AUTO_ECCEPT=false` reads the NUMBERS without enqueuing), the `/integrators` "roda o integrador" flow (Mongo up → scale → preview → go), `HUBFLOW.md` (release start/finish through `hubflow.sh`), `README.md` §2.2 on develop (schema versioning at release).

## Execution phases

### Phase 0 — Unblock `develop` and prepare staging (target: 2026-09-04)

**Objective:** `develop` can start a job, the bootstrap can run, and the staging environment reports to 4Shark instead of the client.

**Components:**

- `integrator` PR 1 — [#2363](https://github.com/4shark/integrator/pull/2363) `fix(job): count streams before starting an integration` on `app/workers/job/starter.rb:11`, the validated shape from `../integrator/develop-image-incident/ANALYSIS.md:45-52` (local `streams_count = Stream.count`, no `none?`). CHANGELOG `[Unreleased]` → Fixed: "Integration start on an empty stream set".
- `integrator` PR 2 — [#2364](https://github.com/4shark/integrator/pull/2364) `fix(rake): seed warm-up on a fresh normalized source` on `lib/tasks/integration/normalized/bootstrap.rake:32` → `source.warm_up = false if source.warm_up.nil?`. `ApplicationConfiguration.warm_up?` was removed by the engineer's own cleanup commit `ed648011` while the rake kept calling it; every integrator stack sets `CLIENT_WARM_UP = "false"`, so seeding `false` loses nothing (the env var is now dead in Terraform — a follow-up, not this PR). CHANGELOG → Fixed: "Normalized bootstrap on a fresh source".
- `integrator` PR 3 — [#2365](https://github.com/4shark/integrator/pull/2365) `fix(rake): seed the normalized source in utc`: `bootstrap.rake:31` seeds `source.timezone ||= 'UTC'` and `ApplicationConfiguration.timezone` (the `CLIENT_TIMEZONE` reader, default `America/Sao_Paulo`) is removed. `master` renders the fetch boundary in UTC (`user/database_extractor.rb:9`, Mongoid `use_utc: true`, no Rails `time_zone`), so `UTC` is the only value with no behavior change; the environment-variable path was a `develop`-only detour introduced in `06b5721a`. CHANGELOG → Fixed: "Normalized source time zone".
- `terraform` PR — [#1149](https://github.com/4shark/terraform/pull/1149) in `integrator-atento/main.tf`, `deployments.mx.staging_env_vars`: `MAILER_TO = "relatorio-integracao@4shark.com.br"` (the mailbox `INTERNAL_MAILER_TO` already defaults to, `lib/application_configuration.rb:130`). Apply-before-merge: PR open → plan saved at `/tmp/terraform_plan_integrator_atento_staging_mailer_20260904_105500.tfplan` (3 task definitions replaced, only `MAILER_TO` differs, no service change) → engineer approves → apply → confirmation plan → merge.
- Merge of the two integrator PRs pushes `develop`, and `build.yaml` rebuilds the four staging images (`integrator-atento-mx-staging:latest` among them).
- Deploy of the staging image so the Mongoid indexes exist (F5):

```bash
gh workflow run deploy.yaml -R 4shark/integrator --ref develop -f integrator=atento-mx-staging
```

- Staging base reset, so the first `develop` run starts from zero instead of on top of the 119,897 `Resource` documents left by the `master`-era runs. Three console scripts on `bin/ecs run atento-mx-staging`, in order (pre-flight → mutation → verification, `SCRIPT-DISCIPLINE.md`). What is wiped: every Mongo collection except `accounts` (the primary `Account` created by migration `20240717170533` carries the API endpoint and token) and `data_migrations` (the Mongoid migration ledger); the deployment's own Redis database (`redis://…redis001…/5`, exclusive to `mx-staging` — `br`=1, `mx`=2, `cl`=3, `co`=4, `cl-staging`=6, `co-staging`=7), which holds the Sidekiq queues, the `lock:integrator` starter lock and the `Computation` counters. `delete_all` is the justified exception of `BULK-DELETE.md`: none of the wiped documents carries a destroy callback the wipe needs, and `Collection.delete_all_collections` is the codebase's own shape. The S3 bucket `4shark-integrator-atento-mx-staging` is empty (no `storage/` cold archive, no `jobs/` raw bodies — checked 2026-09-04), so `Resource.get` cannot restore anything from S3 after the wipe and the bucket needs no cleanup.
- The SQL access test from the same console: `MicrosoftSqlAdapter.connect!` with the `ApplicationConfiguration` readers reached the Azure SQL base (`3.0-p1`). Row counts on 2026-09-04: `users` 10,114 / `hierarchy` 3,949 / `user_fields` 88,918 / `user_activity` 1,765 / `subsidiaries` 1, newest timestamps 2026-07-22 21:58 UTC (the last harvester run); `groups`, `groupifications`, `clients`, `deals`, `goals`, `products`, `modifiers`, `user_identifiers`, `deal_extra_fields` at 0. The first job after the reset has no finished `Job`, so `Job::Starter` uses `ApplicationConfiguration.initial_fetch_date` = 1964-01-01 (`INITIAL_FETCH_DATE` unset on staging, `FETCH_DAYS` unset → 0) and reads every row.

**Dependencies:** the Terraform apply must land before the deploy (the deploy re-registers the task definition from the live, Terraform-managed one, so the environment it inherits is whatever Terraform last applied). The MongoDB nodes are running today, so the deploy preflight passes. The base reset runs with web, worker and runner services at 0/0 (no Sidekiq process consuming) and before Phase 2's bootstrap, which recreates `ResourceType`, `DatabaseSource`, `DatabaseAuthentication`, `HealthCheck` and the 28 `Stream`s from the environment variables.

**Success criteria:**

- [x] The three integrator PRs merged to `develop` (#2364 → `7f91bd94`, #2363 → `fb7e8dcf`, #2365 → `7437dc25`); `build.yaml` run for `develop` green after the last merge (run `33870101314`)
- [x] Terraform applied (`3 added, 0 changed, 3 destroyed`); confirmation plan reports `No changes`; PR #1149 merged (`655845a`)
- [x] `deploy.yaml` for `atento-mx-staging` green (run `33870462294`: preflight, quiet, migrate 1m47s, cron tasks, web, worker)
- [x] `aws ecs describe-task-definition --task-definition integrator-atento-mx-staging-worker --region sa-east-1 --profile engineer-elevated` shows `MAILER_TO` = internal mailbox (revision 39, image `integrator-atento-mx-staging:latest`)
- [x] SQL access from the `develop` image confirmed (`database_version` = Azure SQL 12.0.2000.8, `integration_version` = `3.0-p1`, per-table counts recorded above)
- [x] Reset pre-flight printed `PREFLIGHT: OK` (no Sidekiq process, no busy job, primary `Account` present, Redis path `/5`; the only Redis key was Sidekiq's stat heartbeat)
- [x] Reset mutation printed `deleted=` per step with no `FAILED` (119,897 resources, 1,803 collections, 12 job metrics, 1 job; sources/streams/resource types were already at 0) and `redis flushdb: OK`
- [x] Reset verification printed `VERIFICATION: OK` (`accounts` 1 with primary present, `data_migrations` 5, every other collection at 0, Redis `dbsize` 0)

### Phase 1 — Fresh QA data in the staging normalized base (target: 2026-09-04, after Phase 0)

**Objective:** the staging base carries rows newer than 2026-07-22, so the run has something to integrate and the numbers can be checked against the harvester's own summary.

**Components:**

- One-off run of the staging harvester (reads Simplex QA `10.214.0.123` over `mx-equinix`, writes `ME_4Shark_DB` on `glazrdbvp051`). The task definition exists with no schedule; `run-task` is the documented one-off path (`~/.claude/skills/harvesters/SKILL.md`). It is a write to the staging base and stays on the always-ask path:

```bash
aws ecs run-task --cluster integrator-atento-harvester-cluster --task-definition integrator-atento-harvester-mx-staging-cron-integration --launch-type FARGATE --count 1 --network-configuration '{"awsvpcConfiguration":{"subnets":["subnet-0443ebeb86c659777","subnet-0d4b037da95341023"],"securityGroups":["sg-09237c5690fc7293e"],"assignPublicIp":"DISABLED"}}' --region sa-east-1 --profile engineer-elevated > /tmp/aws_ecs_run_task_harvester_mx_staging_20260904.json 2>&1
```

- Its log, read after the task stops (`---------------Inicio---------------` … `---------------Fin---------------`, `[ERR]` lines, the `LoadNuevos` / `LoadCesados` / `LoadUpdates` summaries):

```bash
aws logs tail /ecs/integrator-atento-harvester-mx-staging-cron-integration --region sa-east-1 --since 1h --format short > /tmp/aws_logs_harvester_mx_staging_20260904.txt 2>&1
```

**Dependencies:** VPN `integrator-atento-mx-equinix` tunnel up (it is); the four `/integrator-atento-harvester-mx-staging/*` parameters populated (they are, version ≥ 3).

**Success criteria:**

- [x] Harvester task `4da113e423d442339c8bec4640c2c84c` stopped with exit code 0 (14:32:27 → 15:21:28 UTC, 49 min); `Fin` reached; 8 `[ERR]` lines, all data-level and of the same two classes as the 2026-07-22 run (2 RFCs colliding with `idx_users_unique_register_id`, 6 Simplex rows with no source `external_id`), none infrastructure. Full log: `/tmp/aws_logs_harvester_mx_staging_20260904_full.txt`
- [x] Counts recorded (the expected NUMBERS of Phase 2): Simplex hierarchy 8,941 rows; 4Shark users in memory before the run 10,114; classification 171 mandos / 272 supers / 6,051 racs / 2,448 analistas; 4 admins; `LoadNuevos` 558 to process, 554 `Add created`; `ProcessTerminations` 2,158 returned, 667 disabled; `LoadUpdates` promotion=24, demotion=12, update_parent=1350, no_change=6987, error=0, skipped=4

### Phase 2 — Bootstrap and configuration verification (target: 2026-09-05)

**Objective:** the staging MongoDB carries exactly the configuration `master` expressed as environment variables, and nothing else is missing (F6).

**Components:**

- Discovery first, read-only, from a runner console (`bin/ecs run atento-mx-staging` in the integrator repo opens `bundle exec rails console` on an ephemeral task):

```ruby
puts "Sources: #{Source.count} (normalized: #{Source.normalized.count})"
Source.each { |source| puts "  #{source._type} #{source.name} normalized=#{source.normalized} timezone=#{source.timezone} host=#{source.try(:host)} database=#{source.try(:database_name)} table_prefix=#{source.try(:table_prefix)} warm_up=#{source.try(:warm_up)}" }
puts "ResourceTypes: #{ResourceType.count}"
puts "Streams: #{Stream.count} (enabled: #{Stream.enabled.count})"
puts "Accounts: #{Account.count} (primary present: #{Account.primary.present?})"
Account.each { |account| puts "  endpoint=#{account.api_endpoint} primary=#{account.primary}" }
puts "Jobs: #{Job.count}"
puts "Resources: #{Resource.count}"
```

- The bootstrap, on the same kind of task:

```bash
bin/ecs run atento-mx-staging "bundle exec rake integration:normalized:bootstrap"
```

- Verification after the bootstrap (expected: 1 normalized `DatabaseSource`, timezone `UTC`, host `glazrdbvp051.database.windows.net`, database `ME_4Shark_DB`, table prefix `fsk_`, adapter `microsoft_sql_server`, azure `true`, `warm_up` `false`; 28 ResourceTypes; 28 enabled Streams whose query templates carry `fsk_` and `{{ fetch_since }}`; one `DatabaseAuthentication`; one `HealthCheck`):

```ruby
source = DatabaseSource.find_by(normalized: true)
puts "adapter=#{source.adapter} azure=#{source.azure} host=#{source.host} database=#{source.database_name} port=#{source.port} timeout=#{source.timeout} table_prefix=#{source.table_prefix} timezone=#{source.timezone} warm_up=#{source.warm_up} max_connections=#{source.max_connections}"
puts "resources=#{source.resources.sort.join(',')}"
puts "authentication present=#{source.authentication.present?} username present=#{source.authentication.username.present?}"
puts "health_check present=#{source.health_check.present?}"
puts "resource_types=#{ResourceType.count} expected=#{Integrator::NORMALIZED_SCHEMA.size}"
puts "streams=#{Stream.where(source: source).count} enabled=#{Stream.where(source: source).enabled.count}"
Stream.where(source: source).order_by(name: :asc).each { |stream| puts "  #{stream.name}: page_size=#{stream.page_size} since=#{stream.fetch_since_column} probe=#{stream.availability_probe}" }
puts "connect: #{source.connect!.database_version}"
puts "integration_version: #{source.connect!.integration_version}"
```

- If discovery found no `Account`, one is created by hand in the console with the staging API endpoint and token of the Atento MX staging company (the engineer supplies both; the token is a credential and is typed in the console, never pasted into a chat).
- The bootstrap is the first code path that ENCRYPTS on an Atento deployment: `DatabaseAuthentication#password=` goes through `symmetric-encryption` (`app/models/authentication.rb:16`, `encrypted: true`), whose `production` config takes the key and the IV raw from `SYMMETRIC_ENCRYPTION_KEY` / `SYMMETRIC_ENCRYPTION_IV` (`config/symmetric-encryption.yml`, `cipher_name: aes-256-cbc` → 32-byte key, 16-byte IV; the development values are 32 and 16 plain characters). The SSM parameters Terraform creates as `PLACEHOLDER` with `ignore_changes = [value]` (`modules/integrator/deployments.tf:80-102`) were populated by hand as 64 and 32 hexadecimal characters — twice the length — so the first encryption raises `ArgumentError: key must be 32 bytes` at `bootstrap.rake:43`. `master` never encrypted anything on these deployments (the normalized password lived in `CLIENT_PASSWORD`), which is why the mismatch stayed invisible until this bootstrap and why no stored ciphertext depends on the old values. The productive `mx` parameters carry the same 64/32 shape. Fix: rewrite both parameters as 32 and 16 characters, keeping the KMS key the task role can decrypt (`alias/integrator-atento`), the value generated inside the command and never printed:

```bash
aws ssm put-parameter --name /integrator-atento-mx-staging/SYMMETRIC_ENCRYPTION_KEY --type SecureString --key-id alias/integrator-atento --overwrite --value "$(openssl rand -hex 16)" --region sa-east-1 --profile engineer-elevated > /tmp/aws_ssm_put_symmetric_key_mx_staging_20260904.json 2>&1
```

```bash
aws ssm put-parameter --name /integrator-atento-mx-staging/SYMMETRIC_ENCRYPTION_IV --type SecureString --key-id alias/integrator-atento --overwrite --value "$(openssl rand -hex 8)" --region sa-east-1 --profile engineer-elevated > /tmp/aws_ssm_put_symmetric_iv_mx_staging_20260904.json 2>&1
```

  Applied on staging 2026-09-04 (both parameters at version 4, lengths verified 32/16). Each `bin/ecs run` starts a fresh task, so the next bootstrap reads the new values; the bootstrap is idempotent (`find_or_initialize_by`), so the `ResourceType`s and the `Source` the failed run created are reused.

**Dependencies:** Phase 0 deploy (the bootstrap task exists only in the develop image, and the runner task definition was re-registered by the deploy); the encryption key and IV parameters of the deployment carry 32 and 16 characters.

**Success criteria:**

- [x] Bootstrap printed `BOOTSTRAP COMPLETE` with `ResourceTypes: 28` and `Streams: 28/28` (task `1b35aaac09064a6a987fc2d944fdbf8b`, after the encryption parameters were rewritten). `bin/ecs run <slug> "<command>"` ends with `bin/ecs: line 196: TASK_ARN: unbound variable` on success and on failure alike, and the ephemeral runner task is left running its `sleep 7200` — stop it by id with `aws ecs stop-task` after each run (follow-up on `bin/ecs`: the EXIT trap reads a variable that is local to the `run` function)
- [x] `fetch_since_column` verified after the #2368 fix landed and the base was re-bootstrapped on the corrected image (revision 40): `mismatches=0`, the six `created_at` streams correct (Groupification, Hierarchy, ParentUpdate, UserActivity, UserFieldCreate, UserFieldDelete), the other 22 on `updated_at`. The earlier run had seeded all 28 as `updated_at` because the `Stream` model defaults the field (`app/models/stream.rb:18`) and the bootstrap's `||=` never assigned; the fix assigns on `new_record?`, so it corrects only on creation, which is why the reset + re-bootstrap was required
- [x] `source.connect!.database_version` returned the Azure SQL version string; `integration_version` returned `3.0-p1`
- [x] `Account.primary` present — endpoint `demo001.app4shark.com`, token present (36 chars), created 2026-03-02, one account total. So the staging integrator pushes to the **demo-001** app backend (us-east-1, web 1/1 ACTIVE), a shared multi-jurisdiction demo environment (BR+CL+MX+CO), NOT an isolated test backend. Whether a full Atento MX load (~10k users) should land in demo-001 during the first job is the engineer's decision before Phase 3

### Phase 3 — First full run (target: 2026-09-05)

**Objective:** the whole pipeline — pre-flight, extract, transform, load, report, shutdown — runs on develop against the staging base.

**Components:**

- Preview of the pending numbers, read-only (the wrapper launches `integration:start` with `AUTO_ACCEPT=false` and tails the runner log):

```bash
bash ~/.claude/skills/integrators/scripts/integrator-preview.sh --client atento-mx-staging
```

- Scale-up of web and worker to 1 (the Terraform counts are 0; a manual run needs 1 of each):

```bash
bash ~/.claude/scripts/ecs-scale.sh --region sa-east-1 --cluster integrator-atento-mx-staging-cluster --service integrator-atento-mx-staging-web-service --desired-count 1
```

```bash
bash ~/.claude/scripts/ecs-scale.sh --region sa-east-1 --cluster integrator-atento-mx-staging-cluster --service integrator-atento-mx-staging-worker-service --desired-count 1
```

- The run. The first job's `fetch_since` is 1964 (no prior job), so the load is the whole base and the throughput guard would stop it at `MINIMUM_THROUGHPUT = 5000` (F7); `SKIP_THROUGHPUT=true` bypasses the guard for this run only. Always-ask path, engineer's go:

```bash
aws ecs run-task --cluster integrator-atento-mx-staging-cluster --task-definition integrator-atento-mx-staging-runner --launch-type FARGATE --count 1 --region sa-east-1 --profile engineer-elevated --network-configuration '{"awsvpcConfiguration":{"subnets":["subnet-0443ebeb86c659777","subnet-0d4b037da95341023"],"securityGroups":["sg-09237c5690fc7293e"],"assignPublicIp":"DISABLED"}}' --overrides '{"containerOverrides":[{"name":"integrator-atento-mx-staging-runner","command":["bin/rails","integration:start"],"environment":[{"name":"AUTO_ACCEPT","value":"true"},{"name":"SKIP_THROUGHPUT","value":"true"}]}]}' > /tmp/aws_ecs_run_task_integration_start_atento_mx_staging_20260905.json 2>&1
```

- Observation while it runs:

```bash
aws logs tail /ecs/integrator-atento-mx-staging-worker --region sa-east-1 --follow --format short
```

- State after the run, from the console:

```ruby
job = Job.order_by(starts_at: :desc).first
puts "starts_at=#{job.starts_at} fetch_ends_at=#{job.fetch_ends_at} transformation_ends_at=#{job.transformation_ends_at} ends_at=#{job.ends_at}"
puts "fetch_since=#{job.fetch_since} application_version=#{job.application_version} database_version=#{job.database_version} integration_version=#{job.integration_version}"
puts "sources=#{job.total_sources} streams=#{job.total_streams} requests total=#{job.total_requests_quantity} ok=#{job.successful_requests_quantity} failed=#{job.failed_requests_quantity}"
puts "source checks: #{SourceCheck.where(job_id: job.id).map { |check| [check.source.name, check.reachability, check.authentication, check.failure, check.detail] }}"
puts "stream checks unsuccessful: #{StreamCheck.where(job_id: job.id).unsuccessful.map { |check| [check.stream.name, check.accessibility] }}"
Resource::TYPES.each { |type| puts "  #{type}: imports=#{Resource.where(_type: type, 'imports.job_id': job.id).count}" }
puts "requests by status: #{Resource.collection.aggregate([{ '$unwind' => '$imports' }, { '$match' => { 'imports.job_id' => job.id.to_s } }, { '$unwind' => '$imports.requests' }, { '$group' => { '_id' => '$imports.requests.response.status', 'count' => { '$sum' => 1 } } }]).to_a}"
```

**Dependencies:** Phase 2; MongoDB running; `Account.primary` present.

**Success criteria:**

- [ ] Preview prints the SOURCES block with `Database (normalized)` and a NUMBERS block whose counts match Phase 1's harvester summary
- [ ] `Job` reaches `ends_at`; `SourceCheck` for the normalized source is `passed`/`passed`; no `StreamCheck` failed
- [ ] The integration report arrives at `relatorio-integracao@4shark.com.br` (not at the client mailbox), mobile-card layout, totals matching the console counts
- [ ] Every `4xx` response, if any, is explainable as data (an unknown user type, a missing parent) and not as a shape error; `5xx` count is zero
- [ ] `ShutDownWorker` scaled web and worker back to 0 (`integrator-services.sh --client atento-mx-staging` shows 0/0) — checked, not assumed (F10)
- [ ] The staging 4Shark company shows the loaded users, hierarchy and deals

### Phase 4 — Parity with `master` and the incremental run (target: 2026-09-08 → 2026-09-09)

**Objective:** nothing `master` did is lost, and the incremental boundary behaves as it did on `master` (release gate 6.6).

**Components:**

- The parity checklist, executed against the Phase 3 job and, for the production reference, the last `master` job of `atento-mx` (production MongoDB, read-only console via `bin/ecs run atento-mx`):

| Behavior on `master` | Where it lives on `develop` | Check |
|---|---|---|
| 25-step resource order, `Hierarchy` before users, `ParentUpdate` after | Worker chain (`CLAUDE.md` § Stream Order) | Worker log shows the producers firing in the documented order |
| `4sk_` prefix on every user identifier sent to the API | `Source#user_id_from` (`app/models/source.rb:41-47`) | Request bodies in `imports.requests` carry `4sk_<id>`; no unprefixed user id |
| Users of unknown `type` surface as API rejections, not silent drops | `User::Unknown` stream (`config/normalized_schema.rb:408-414`) | Unknown-type rows appear as `4xx` imports in the report's XLSX |
| Permission and lock probes before extraction (`SKIP_DATABASE_VALIDATIONS=false` on staging) | `Authorization::DatabaseConsumer` | `SourceCheck.authentication = passed`, `affected_resources` empty |
| Throughput guard (`MINIMUM_THROUGHPUT`) | `ThroughputProcessor` (`app/workers/throughput_processor.rb`) | On the second run (no `SKIP_THROUGHPUT`), the job proceeds when the pending volume is under the ceiling |
| Parent lookup for users and hierarchy | Transformer JOIN on `users` | `imports.data.parent` populated where `parent_id` is set |
| Subsidiary module off for MX (`SUBSIDIARIES_MODULE=false`) | `Hierarchy#request_body_for` (`app/models/hierarchy.rb`) | No `external_parent_subsidiary_id` in hierarchy bodies |
| Report email to the configured recipient | `IntegrationReport::Producer` → `MAILER_TO` | Received at the internal mailbox |
| Self-shutdown at the end | `ShutDownWorker` | Services at 0/0 after the run |
| One import per user identifier | Three `UserIdentifier*` streams over one table (F13) | `UserIdentifier` import count equals the distinct identifier count in the base |

- The incremental run: Phase 1 again (fresh harvester load), then Phase 3's run **without** `SKIP_THROUGHPUT`. The boundary check is the point of gate 6.6:

```ruby
previous_job, current_job = Job.order_by(starts_at: :desc).limit(2).to_a.reverse
puts "previous ends_at (UTC)=#{previous_job.ends_at.utc} current fetch_since (UTC)=#{current_job.fetch_since.utc} fetch_days=#{ApplicationConfiguration.fetch_days.inspect}"
source = DatabaseSource.find_by(normalized: true)
variables = Variables.new(current_job, source).to_h
puts "rendered fetch_since=#{variables['fetch_since']} source.timezone=#{source.timezone}"
puts "collections this job: #{Collection.where(job_id: current_job.id).count}"
```

  Expected: `rendered fetch_since` equals `previous ends_at (UTC)` minus `FETCH_DAYS` formatted as `%Y-%m-%d %H:%M:%S` — the same string `master` would have rendered — and every row the harvester wrote after the previous job appears exactly once in the new imports (no duplicates, no gaps at the boundary).

- Optional widening, same procedure, cheap because the staging images are already built from develop: `atento-co-staging`, `atento-cl-staging`, `commcenter-staging`. Commcenter is the one self-populated (customer-written) normalized base with a staging mirror, so it is the closest rehearsal for Almaviva, Commcenter and Maqnelson production.

**Dependencies:** Phase 3 complete; a second harvester load.

**Success criteria:**

- [ ] Every row of the parity table checked and recorded in this directory (a `PARITY.md` or a section appended here)
- [ ] Incremental run: boundary string equals master's semantics; zero duplicated, zero skipped rows at the boundary
- [ ] Gate 6.6 of the unified-flow plan marked done with the decision recorded: `source.timezone = 'UTC'`, seeded by the bootstrap (#2365)

### Phase 5 — Release 8.5.0 (target: 2026-09-10)

**Objective:** `develop` reaches `master` as one release, with the schema artifacts versioned.

**Components:**

- `bash ~/.claude/scripts/hubflow.sh --dir /Users/plribeiro3000/Projects/4Shark/integrator release start 8.5.0` (main working tree, `develop` synced first)
- On the release branch, one commit `chore(release): 8.5.0`: `config/version.rb` → `8.5.0`; `CHANGELOG.md` `[Unreleased]` → `## [8.5.0] - 2026-09-10`; schema artifacts renamed from `UNRELEASED` to their next versions (F8, `README.md` §2.2 — the engineer decides `3.1` vs `3.0-p2` per SGBD) with the matching `[MSSQL] version …` / `[MSSQL Prefixed] version …` / `[PGSQL Prefixed] version …` changelog entries
- Push with explicit refspec, PR against `master` titled `[8.5.0] - 2026-09-10` with the changelog section as body; `pr-review` runs on it
- After the merge: `hubflow.sh --dir … release finish 8.5.0` (tag `v8.5.0`, back-merge into `develop`); `build.yaml` on the push to `master` builds the seven productive images

**Dependencies:** Phase 4 signed off by the engineer.

**Success criteria:**

- [ ] `v8.5.0` tag on the `chore(release)` commit; `master == origin/master`, `develop == origin/develop`
- [ ] Seven productive ECR repositories carry `:latest = 8.5.0-<master sha>`
- [ ] The versioned schema migration files are ready to send to each customer's DBA

### Phase 6 — Productive rollout, one integrator at a time (target: 2026-09-10 → 2026-09-12)

**Objective:** every productive integrator runs 8.5.0 with its configuration bootstrapped before its next processing window.

**Components:**

- No Terraform change for the time zone: the bootstrap seeds every normalized source in `UTC` (#2365), so the productive deployments need no variable. Parity holds for the self-populated bases too: `master` rendered the boundary in UTC regardless of what zone the customer writes, and `UTC` reproduces that exactly (F3).
- Per integrator, outside its window, in this order:

| Step | Command | Note |
|---|---|---|
| 1. MongoDB up | `gh workflow run startup.yaml -R 4shark/integrator -f integrator=<slug>` | Only where the nodes sleep between windows (the deploy preflight refuses otherwise) |
| 2. Deploy | `gh workflow run deploy.yaml -R 4shark/integrator --ref master -f integrator=<slug>` | Migrate step creates the Mongoid indexes; runner task definition re-registered with 8.5.0 |
| 3. Encryption key shape | `aws ssm get-parameter --name /integrator-<slug>/SYMMETRIC_ENCRYPTION_KEY --with-decryption --query Parameter.Value --output text --region sa-east-1 --profile engineer-elevated > /tmp/aws_ssm_symmetric_key_<slug>.txt 2>&1` then `wc -c` (33 = correct; 65 = the hexadecimal shape that breaks the bootstrap) | Every deployment whose key measures 64 characters (IV 32) gets the two `put-parameter` rewrites of Phase 2 with its own name and its stack's KMS alias BEFORE step 4; delete the local file afterwards. Verified on `atento-mx` 2026-09-04: 64/32, so the rewrite is needed there |
| 4. Bootstrap | `bin/ecs run <slug> "bundle exec rake integration:normalized:bootstrap"` | Reads the stack's `CLIENT_*` variables once; idempotent |
| 5. Verify | The Phase 2 verification script on `bin/ecs run <slug>` | Source, 28 streams, `Account.primary`, `connect!` |
| 6. MongoDB down | `gh workflow run shutdown.yaml -R 4shark/integrator -f integrator=<slug>` | Only where step 1 ran |
| 7. Next window | Report email received; `Job` finished; services back at 0/0 | The learning step before the next integrator |

- Order: the ladder is a learning progression (`ZERO-DOWNTIME-POLICY.md` § 2). Proposed: `atento-cl` (the Atento shape already validated on MX staging, smallest window impact) → `atento-co` → `atento-mx` → `atento-br` → `maqnelson` → `almaviva` → `commcenter`. The engineer settles the order by each client's volume and contract.
- The `<slug>` values are the productive keys of the `INTEGRATORS` variable: `almaviva`, `atento-br`, `atento-cl`, `atento-co`, `atento-mx`, `commcenter`, `maqnelson`.

**Dependencies:** Phase 5.

**Success criteria:**

- [ ] Seven deploys green, seven bootstraps `28/28`, seven next-window reports received
- [ ] No `MissingStreamsReport` / `InactiveStreamsReport` email on any integrator (a bootstrap that did not run before the window sends one)
- [ ] Schema migrations delivered to the four customers' DBAs (asynchronous; not a gate)

### Phase 7 — Close (target: 2026-09-12)

- Move `../integrator/unified-integration-flow/` to `completed/` with gate 6.6 recorded
- Open the cleanup PRs for the dead environment variables (F9) as follow-ups, one per stack, not before every deployment is bootstrapped
- Update `terraform/integrator-atento/README.md` MongoDB node names (`004/005/006`) — Kaizen, folds into the F9 PR for that stack
- The week of 2026-09-14 starts on `../atento-mexico-vkpi-integration/PLAN.md` Phase 1

## Technical decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Source timezone for every bootstrapped deployment | `UTC`, seeded by the bootstrap itself (#2365); no environment variable | `master` rendered the fetch boundary as a UTC string; the harvester and the schema procedures write UTC; `UTC` is the only value with zero behavior change (`ANALYSIS.md` F3) |
| Staging report recipient | `relatorio-integracao@4shark.com.br` | The mailbox the code already uses for internal notifications (`INTERNAL_MAILER_TO` default); one internal address for every report during the test |
| First staging run | `SKIP_THROUGHPUT=true` | No job history → ceiling is `MINIMUM_THROUGHPUT`; a full first load exceeds it and would stop at `HighThroughputReport` (F7). The second run proves the guard |
| Release version | `8.5.0` | `[Unreleased]` carries Added entries → minor |
| Rollout unit | Deploy + bootstrap per integrator, outside its window | A deploy without the bootstrap makes the next cron send `MissingStreamsReport` and skip the night |
| Fix shape for `Stream.none?` | Local `streams_count = Stream.count` | `Style/CollectionQuerying` rewrites an inline `.count.zero?` into the `none?` that does not exist on a Mongoid model class (`../integrator/develop-image-incident/ANALYSIS.md:54`) |
| Fix shape for the bootstrap warm-up seed | `source.warm_up = false if source.warm_up.nil?` | The flag lives on the document; a deliberate `true` is set by hand and survives re-runs |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| A third crash-class defect surfaces in the staging run (F4: nothing automated covers the workers) | High — blocks the release | The staging run is scheduled first; fixes go to `develop` and rebuild the staging image automatically; a worker-spec follow-up is opened |
| The staging Azure SQL host refuses the NAT egress or the credentials expired | Medium — Phase 2 fails at `connect!` | `SourceCheck.detail` carries the exact error; the parameters are the ones production used until July 2026 |
| No `Account` in the staging MongoDB | Medium — loaders fail after extraction | Discovery script before the bootstrap; create it by hand |
| A productive deploy happens without its bootstrap before the window | High — one night skipped for that client | Deploy + bootstrap are one motion in the rollout table; the `MissingStreamsReport` email is the alarm |
| `ShutDownWorker` swallows an ECS error and leaves staging running (F10) | Low — cost only | Checked with `integrator-services.sh` after each run |
| The self-populated bases (Almaviva, Commcenter, Maqnelson) behave differently from the harvester-fed ones | Medium | Parity in the boundary string is exact for any zone the customer writes (F3); `commcenter-staging` is the optional rehearsal in Phase 4 |
| `terraform release/3.0.0` still open when the staging change is applied | Low | The change is a feature branch off `develop`, applied on its own; the release back-merge picks it up |
| A productive deployment's `SYMMETRIC_ENCRYPTION_KEY` / `IV` still carry the 64/32-character hexadecimal shape when its bootstrap runs | High — the bootstrap aborts at the authentication step and the next window sends `MissingStreamsReport` | Phase 6 step 3 measures the length before every bootstrap and rewrites the pair when it is wrong; nothing encrypted depends on the old values, because encryption never succeeded with them |

## Assumptions

- The Atento MX staging 4Shark company (the API endpoint behind `Account.primary`) exists and accepts the staging integrator's token; the engineer supplies both if the discovery finds no `Account`
- Simplex QA is reachable and populated (the harvester ran successfully on 2026-07-22 against it)
- The Azure allowlist on `glazrdbvp051` still admits `54.207.204.47`
- The engineer runs the always-ask steps (harvester `run-task`, the integration `run-task`, `terraform apply`, the release finish, the productive deploys); the session prepares every command complete

---

> **Authoring:** written in the main session on 2026-09-04 from `ANALYSIS.md` in this directory and the engineer's instruction; no `plan-researcher` draft preceded it. Every command carries resolved values (cluster, task family, subnets, security group, log groups) read from AWS and the Terraform stack the same day.
