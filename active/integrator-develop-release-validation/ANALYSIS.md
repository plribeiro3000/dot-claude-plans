# ANALYSIS — Integrator `develop` release readiness, validated on Atento MX staging

> Scope: everything `origin/develop` of the `integrator` repository carries beyond `origin/master` (8.4.25), the Terraform stack that runs the Atento MX staging integrator, and the live AWS state of that environment. Written 2026-09-04 so the validation described in `PLAN.md` can start the same day.

## 1. The question

Before the Atento México indicator work (`../atento-mexico-vkpi-integration/PLAN.md`, Phase 1) can start in the week of 2026-09-14, everything on `develop` must be released to every productive integrator. The change on `develop` moves the customer database configuration out of environment variables and into MongoDB documents (`Source`, `DatabaseAuthentication`, `Stream`), populated by a rake task. This document establishes what that change is, what state the staging environment is in, and which defects stand between the current `develop` and a release.

## 2. Current state

### 2.1 The stack — `terraform/integrator-atento`

One stack, four deployments (`br`, `mx`, `co`, `cl`), three of them mirrored into staging (`mx`, `co`, `cl`), plus two harvesters (`mx`, `co`) each with an on-demand staging copy. Everything shares one VPC (`10.12.255.0/24`), one MongoDB replica set, one Redis (separate database index per deployment), and three site-to-site VPNs (`azure`, `mx-equinix`, `co-cirion`).

| Fact | Value | Source |
|---|---|---|
| MX staging host | `integrator-atento-mx-staging.4shark.internal` (ALB priority 50) | `integrator-atento/main.tf:205-206` |
| MX staging Redis database | `5` | `main.tf:207` |
| MX staging customer database | `ME_4Shark_DB` on `glazrdbvp051.database.windows.net` (Azure SQL, "Homologación") | `main.tf:295-298` |
| MX production customer database | `ME_4Shark_DB` on `sql4shark.database.windows.net` | `main.tf:212-213` |
| MX staging report recipient | `MAILER_TO = informe-integracion-atento-mx@4shark.com.br` — the same client-facing mailbox production uses | `main.tf:311` vs `main.tf:227` |
| MX staging validations | `SKIP_DATABASE_VALIDATIONS = "false"` (production: `"true"`) — staging runs the permission and lock probes production skips | `main.tf:323` vs `main.tf:238` |
| MX staging services | web / worker / runner all declared at `desired_count = 0`; no scale-up schedule, no cron | `main.tf:328-349`; `README.md:32` |
| MX staging secrets | 12 SSM SecureString parameters under `/integrator-atento-mx-staging/` | `modules/integrator/variables.tf:96-100` |
| MongoDB nodes declared | `004` (a), `005` (b), `006` (b, arbiter) | `main.tf:40-44` — the stack `README.md:22` still names 003/004/005 and is stale |
| Staging harvester | `mx` with `staging = true`, on-demand only (`create_schedule = false`) | `main.tf:76-78`; `modules/integrator/harvesters.tf:212-240` |
| Staging harvester QA source | Simplex QA `10.214.0.123/32` over the `mx-equinix` VPN | `main.tf:22` |

### 2.2 Live AWS state (read 2026-09-04, default read-only profile)

| Check | Result |
|---|---|
| ECS `integrator-atento-mx-staging-cluster` | web 0/0, worker 0/0, runner 0/0, all `ACTIVE` |
| Staging task definitions in use | `integrator-atento-mx-staging-web:37` and `-worker:37`, deployed 2026-08-26 16:37 BRT; runner `:1` (2026-05-05) |
| ECR `integrator-atento-mx-staging:latest` | `8.4.25-c164475`, pushed 2026-09-03 08:10 BRT — `c164475c` is `origin/develop` HEAD, so `:latest` is already the develop image (the develop-triggered build is in place since `9cfdde55`) |
| SSM parameters `/integrator-atento-mx-staging/*` | all 12 present, version ≥ 3, last written 2026-07-20 (MONGODB v7, 2026-08-19) — none is at the Terraform `PLACEHOLDER` version 1 |
| SSM parameters `/integrator-atento-harvester-mx-staging/*` | all 4 present, version ≥ 3, written 2026-07-20 |
| MongoDB `integrator-atento-mongo004/005/006` | all `running` |
| VPN `integrator-atento-azure`, `-mx-equinix`, `-co-cirion` | `available`, tunnel 1 `UP`, tunnel 2 `DOWN` on each (normal single-tunnel operation) |
| EventBridge schedules `integrator-atento-*` | 8 scale-up schedules, all production; none for staging |
| Log group `/ecs/integrator-atento-mx-staging-worker` | **no log streams at all** — the staging integrator has never processed a job |
| Log group `/ecs/integrator-atento-harvester-mx-staging-cron-integration` | last run 2026-07-22 — the staging normalized base is six weeks stale |
| Log group `/ecs/integrator-atento-mx-worker` (production) | last event 2026-09-02 |
| GitHub `INTEGRATORS` variable | 11 slugs: `almaviva`, `atento-{br,cl,co,mx}`, `atento-{cl,co,mx}-staging`, `commcenter`, `commcenter-staging`, `maqnelson` (updated 2026-08-26) |
| Last `deploy.yaml` runs | 2026-08-26: 6 from `master` (productive) + 4 from `develop` (staging), all successful |
| `ecs:DescribeTaskDefinition` | denied to the default profile — reading the live task-definition environment needs `engineer-elevated` |

### 2.3 What `develop` carries beyond `master`

`origin/master..origin/develop`: 696 files changed, 16,608 insertions, 17,463 deletions; the `[Unreleased]` section of `CHANGELOG.md` on develop holds 6 Added, 10 Changed, 54 Fixed and 7 Removed entries. The functional core is the unified integration flow (`../integrator/unified-integration-flow/PLAN.md`, PRs #2087 → #2188) plus the CI hardening that followed the 2026-07-28 incident (`../integrator/develop-image-incident/`).

**Configuration moved from environment to MongoDB.** On `master`, `lib/application_configuration.rb` derives the customer connection from `CLIENT_HOST`, `CLIENT_PORT`, `CLIENT_DATABASE`, `CLIENT_USERNAME`, `CLIENT_PASSWORD`, `DATABASE_ADAPTER`, `CLIENT_AZURE`, `CLIENT_TIMEOUT` (`connection_params`, lines 255-280) and branches the whole pipeline on `INTEGRATION_MODE` (lines 231-253). On `develop` those methods are gone; the connection lives on a `DatabaseSource` document (`app/models/database_source.rb:24-46`), credentials on a `DatabaseAuthentication`, and every stream's query on a `Stream` document (`app/models/stream.rb`). `rake integration:normalized:bootstrap` (`lib/tasks/integration/normalized/bootstrap.rake`) reads the old environment variables once and writes those documents; it is idempotent (`find_or_initialize_by` + `||=`).

Environment variables by fate on `develop`:

| Fate | Variables |
|---|---|
| Read only by the bootstrap task, then unused | `CLIENT_HOST`, `CLIENT_PORT`, `CLIENT_DATABASE`, `CLIENT_USERNAME`, `CLIENT_PASSWORD`, `DATABASE_ADAPTER`, `CLIENT_AZURE`, `CLIENT_TIMEOUT`, `CLIENT_TIMEZONE`, `CLIENT_NAME` (also the user agent), `TABLE_PREFIX`, `SQL_PAGE_SIZE`, `DATABASE_MAX_CONNECTIONS` |
| Read by nothing any more | `INTEGRATION_MODE`, `CLIENT_WARM_UP` (`CHANGELOG.md` develop, Removed: "Integration mode flag", "Unused warm-up environment flag") |
| Still read at runtime | `MAILER_*`, `INTERNAL_MAILER_TO` (new; default `relatorio-integracao@4shark.com.br`, `lib/application_configuration.rb:129-131`), `HOT_DATA_WINDOW`, `MINIMUM_THROUGHPUT`, `JOB_METRIC_QUANTITY`, `SIDEKIQ_THREADS`, `SKIP_DATABASE_VALIDATIONS`, `SUBSIDIARIES_MODULE`, `LOCALE`, `INITIAL_FETCH_DATE`, `FETCH_DAYS`, `AUTO_ACCEPT`, `SKIP_THROUGHPUT`, `AWS_*`, `REDIS`, `MONGODB`, `SYMMETRIC_ENCRYPTION_*`, `SECRET_KEY_BASE`, `NEW_RELIC_*`, `ROLLBAR_*`, `DATA_DOG_*` |

**Entry point.** `integration:cron` on develop dispatches `DatabaseWarmer::Producer` when any source has `warm_up: true`, otherwise `Job::Starter` (`lib/tasks/integration.rake:8-14`). `Job::Starter` acquires the `integrator` lock, refuses to run when no `Stream` exists (`MissingStreamsReport`) or none is enabled (`InactiveStreamsReport`), creates the `Job`, materializes `SourceCheck`/`StreamCheck` rows and hands off to `HealthCheck::Producer` (`app/workers/job/starter.rb`). The reports for those two refusals go to `INTERNAL_MAILER_TO`; the integration report, the source/stream check reports and the high-throughput report go to `MAILER_TO`.

**Build and deploy.** `build.yaml` on develop builds the staging slugs on every push to `develop` and the productive slugs on every push to `master`; a dispatch naming a slug of the other class fails in `setup` (`9cfdde55`, `.github/workflows/build.yaml:102-108`). `deploy.yaml` is unchanged in shape: preflight (MongoDB running) → TSTP → migrate (`db:migrate` + `db:mongoid:remove_undefined_indexes` + `db:mongoid:create_indexes` on an ephemeral runner task) → web and worker rolling → cron/runner task definitions re-registered. The image is always `:latest`.

**Normalized schema.** The MSSQL and PGSQL setup scripts on develop carry `UNRELEASED` artifacts: eleven new foreign-key indexes and a fix to the `DEBUG` branch of `create_user_identifier` / `remove_user_identifier` (`docs/mssql/migrations/MSSQL-UNRELEASED-Migration.sql`, `docs/pgsql-prefixed/migrations/PGSQL-Prefixo-UNRELEASED-Migration.sql`). The integrator code does not depend on them at runtime (the columns the code reads already exist in 3.0-p1; the procedures are customer-side writers), but `README.md` §2.2 requires them to be versioned on the release branch and the migration handed to each customer's DBA.

## 3. Findings

### F1 — BLOCKER: `Job::Starter` still crashes on `Stream.none?`

`app/workers/job/starter.rb:11` on `origin/develop`:

```ruby
if Lock.acquire(LOCK_KEY)
  if Stream.none?
    MissingStreamsReport::Producer.perform_async
    return
  end
```

Mongoid 9.1.0 defines `none` only on `Criteria` (`mongoid-9.1.0/lib/mongoid/criteria.rb:384`) and never a `none?` on the model class, so this line raises `NoMethodError` on every run before a `Job` document exists. This is the exact defect that stopped a productive integrator on 2026-07-28 when develop images were built by mistake (`../integrator/develop-image-incident/ANALYSIS.md` § Root cause). The validated fix (PR #2285) was closed and its branch deleted; nothing on develop today carries it. Every staging run and, after release, every productive run fails at this line until it is fixed. `Source.normalized.none?` in `app/workers/throughput_processor.rb:14` is a `Criteria` call and is fine.

The fix on record — a local variable, because `Style/CollectionQuerying` autocorrects an inline `Stream.count.zero?` back into the broken `none?`:

```ruby
streams_count = Stream.count

if streams_count.zero?
  MissingStreamsReport::Producer.perform_async
  return
end
```

### F2 — BLOCKER: the bootstrap task calls a method that no longer exists

`lib/tasks/integration/normalized/bootstrap.rake:32` on `origin/develop`:

```ruby
source.warm_up = ApplicationConfiguration.warm_up? if source.warm_up.nil?
```

`ApplicationConfiguration.warm_up?` was removed by PR #2188 ("Dropped operational dead code: `ApplicationConfiguration.warm_up?` — superseded by `DatabaseSource.where(warm_up: true)`", `../integrator/unified-integration-flow/PLAN.md:419-420`); `lib/application_configuration.rb` on develop has no such method and `git grep 'warm_up'` finds only this caller. A fresh `DatabaseSource` has `warm_up` nil, so the guard is true and the line raises `NoMethodError` — the bootstrap aborts after writing the ResourceTypes and before saving the Source. No spec covers the task (`spec/` mentions `warm_up` only as a field expectation, `spec/models/database_source_spec.rb:25`). The fix is to seed `false` (no Atento deployment warms up; `CLIENT_WARM_UP = "false"` everywhere in the stack) and leave a deliberate `true` to be set on the document:

```ruby
source.warm_up = false if source.warm_up.nil?
```

### F3 — Decided: the source timezone is `UTC`, set before the bootstrap

This is the pending release gate 6.6 of the unified-flow plan (`../integrator/unified-integration-flow/PLAN.md:278-294`). On `master` the normalized extractor renders the fetch boundary as `job.fetch_since.strftime('%Y-%m-%d %H:%M:%S')` — a UTC string (`app/workers/user/database_extractor.rb:9`). On `develop` every stream renders through `Variables`, which converts to the source's zone first (`app/models/variables.rb:53`: `@job.fetch_since.in_time_zone(@source.timezone)`), and the bootstrap seeds that zone from `CLIENT_TIMEZONE`, defaulting to `America/Sao_Paulo` (`lib/application_configuration.rb:97-99`; `bootstrap.rake:31`). No integrator stack sets `CLIENT_TIMEZONE`, so every bootstrapped source would query with a boundary three hours earlier than master's.

The data settles which zone is right: the harvester stamps `DateTime.UtcNow` (`simplex-harvester/Services/SimplexHarvesterService.cs:1519,1598`) and the normalized-schema procedures write `GETUTCDATE()` (`docs/mssql/migrations/MSSQL-UNRELEASED-Migration.sql:18,35`). The timestamps are UTC, so `source.timezone = 'UTC'` reproduces master's boundary exactly, for every client. Setting `CLIENT_TIMEZONE = "UTC"` in each deployment's environment before its bootstrap is the zero-behavior-change choice; a wrong zone only widens the re-fetch window (harmless but wasteful for `America/Sao_Paulo`, six hours for `America/Mexico_City`).

### F4 — Nothing automated tests the worker chain

`git ls-tree origin/develop spec/workers/` returns nothing: there is no worker spec on develop, and the rake tasks have none either. F1 and F2 both passed CI. The staging run in `PLAN.md` is therefore the only test of the pipeline as a whole, and the parity checklist there has to be executed by hand.

### F5 — Staging already runs develop code the moment it scales up; a deploy is still required

`:latest` in the staging ECR is `8.4.25-c164475` (develop HEAD). The task definitions pin `:latest`, so scaling the staging services up today launches develop code with no deploy. What a deploy adds is the migrate step, which the new code needs: `db:mongoid:create_indexes` creates the partial unique index on `sources.normalized` (`app/models/source.rb:31`) and the new `collections` index on `(job_id, stream_id)` (`app/models/collection.rb:28`). Both `VERSION` strings read `8.4.25` on both branches; only the SHA in the tag distinguishes master from develop (`../integrator/develop-image-incident/ANALYSIS.md:21`).

### F6 — The staging MongoDB configuration state is unknown

The staging worker has never logged a job, so whether `sources`, `streams`, `resource_types` or an `Account` (the 4Shark API endpoint and token, `app/models/account.rb`) exist in the `atento-mx-staging` database is not readable from here (no MongoDB access from the workstation). The bootstrap is idempotent, but an `Account` is not created by it — `Job::Starter` runs without one and every loader then fails with `NoMethodError` on `account.api_headers`. The first console session on staging must read this state before anything is bootstrapped.

### F7 — The staging normalized base is stale, and the first run is a full load

The staging harvester last wrote on 2026-07-22. With no `Job` in the staging MongoDB, `Job::Starter` computes `fetch_since` from `INITIAL_FETCH_DATE` (1964, `lib/application_configuration.rb:247-258`), so the first run extracts every row of the staging base and pushes all of it to the staging API. Two consequences: the throughput guard fires — with no history `JobMetric#ceiling` is `MINIMUM_THROUGHPUT` (5000, `app/models/job_metric.rb:46-50`) and a full base exceeds it, sending `HighThroughputReport` and stopping the job — so the first run must pass `SKIP_THROUGHPUT=true`; and the run is the "first onboarding" shape, not the "nightly incremental" shape, so a second run after a fresh harvester load is what validates the incremental boundary (F3).

### F8 — The schema artifacts must be versioned at release

`README.md` §2.2 on develop: a schema release is cut only when the integrator cuts a release; every `UNRELEASED` artifact is renamed to the next version on the release branch and a `[MSSQL] version X.Y` / `[PGSQL] version X.Y` entry goes in the CHANGELOG. The migration then reaches each customer's DBA (Atento's Azure SQL databases, Almaviva, Commcenter, Maqnelson). The code runs without it, so this gates the release cut, not the staging test.

### F9 — Terraform residue after the release

`INTEGRATION_MODE` and `CLIENT_WARM_UP` are read by nothing on develop; the `CLIENT_*` connection variables are read only by the bootstrap. All of them stay in the stacks until every deployment has been bootstrapped — the bootstrap needs them — and become a cleanup PR afterwards, one per stack. Not part of this validation.

### F10 — Shutdown on staging is safe, and its failure mode is silent

`ShutDownWorker` runs only under `RAILS_ENV=production` (which staging sets), skips the EC2 stop when `AWS_INSTANCE_IDS` is empty (staging: `""`, `modules/integrator/deployments.tf:74`; `app/models/ec2.rb:9`) and scales `integrator-atento-mx-staging-cluster` web and worker to 0 (`AWS_ECS_ENVIRONMENT = atento-mx-staging`, `deployments.tf:73`). `Ecs.scale_down` on develop still swallows `Fog::AWS::ECS::Error` into a warning (`app/models/ecs.rb:20-22`), so a permission failure leaves the services running with only a log line — the end of every staging run has to be checked with `describe-services`, not assumed.

### F11 — Release shape

The `[Unreleased]` section has Added entries, so the version is a minor: **8.5.0**. HubFlow through `scripts/hubflow.sh`; the release commit bumps `config/version.rb`, dates the CHANGELOG section and renames the schema artifacts (F8). Merging to master builds the seven productive images at once (`build.yaml` on push); nothing runs them until each integrator is deployed. Every productive deployment must be bootstrapped right after its deploy and before its next cron, or that night's run sends a `MissingStreamsReport` and skips. `bin/ecs run <slug>` and the deploy's own runner task are the two paths to the bootstrap.

### F12 — Terraform `release/3.0.0` is in flight

`terraform` PR #1148 (`[3.0.0] - 2026-09-04`) is open and the main working tree is on `release/3.0.0`. The staging change this plan needs is a feature branch off `origin/develop`, applied on its own; it does not depend on the release.

### F13 — The three `UserIdentifier` streams share one query

`config/normalized_schema.rb:416-418` declares `UserIdentifierCreate`, `UserIdentifierPrimary` and `UserIdentifierDelete` over the same table with no `condition`, so the bootstrap gives all three the identical `SELECT * FROM fsk_user_identifiers WHERE updated_at >= ...`. Each stream's transformer writes `resource.imports.find_or_initialize_by(job_id)` on the same resource (`app/workers/user_identifier/transformer_consumer.rb:23-27`), so the result is one import per identifier, extracted three times. Correct, three times the extraction cost; the parity check should confirm identifier counts match master's single pass.

### F14 — Reading the applied environment needs elevation

`aws ecs describe-task-definition` is denied to the default profile. Confirming that the Terraform change reached the running task definition (the `MAILER_TO` and `CLIENT_TIMEZONE` values) is an `engineer-elevated` read.

## 4. What the staging environment is for in this validation

Staging is the one place where the develop code, the customer-shaped data (the QA Simplex source through the staging harvester) and the customer-shaped database (`glazrdbvp051`) meet without touching production. The validation is the release gate 6.6 the unified-flow plan left pending, plus the two blockers above, plus the operational checks the engineer named: the report recipient, the schedules (staging has none, by design; production keeps its eight), and database reachability.

## 5. Sources

- `~/Projects/4Shark/terraform/integrator-atento/main.tf`, `README.md`; `modules/integrator/{deployments,harvesters,variables}.tf`
- `~/Projects/4Shark/integrator` at `origin/develop` (`c164475c`) and `origin/master` (`v8.4.25`): `lib/application_configuration.rb`, `lib/tasks/integration.rake`, `lib/tasks/integration/normalized/bootstrap.rake`, `app/workers/job/starter.rb`, `app/workers/shut_down_worker.rb`, `app/models/{source,database_source,stream,account,job_metric,ecs,ec2,variables}.rb`, `config/normalized_schema.rb`, `.github/workflows/{build,deploy}.yaml`, `docs/architecture/INTEGRATOR_DOMAIN.md`, `docs/architecture/EMAIL_DELIVERY.md`, `README.md`, `CHANGELOG.md`
- `~/Projects/4Shark/simplex-harvester/Services/SimplexHarvesterService.cs`
- `~/.rvm/gems/ruby-4.0.6@integrator/gems/mongoid-9.1.0/lib/mongoid/{criteria,findable}.rb`
- AWS (`sa-east-1`, default profile): `integrator-services.sh`, `ec2-instances.sh`, `harvester-services.sh`, `ssm describe-parameters`, `ecs describe-services`, `ecr describe-images`, `scheduler list-schedules`, `ec2 describe-vpn-connections`, `logs describe-log-streams`
- GitHub: `INTEGRATORS` variable, `build.yaml` / `deploy.yaml` run history, open PRs on `integrator` and `terraform`
- `../integrator/unified-integration-flow/PLAN.md`, `../integrator/develop-image-incident/{ANALYSIS,SPIKE}.md`, `../integrator/shutdown-worker-fix/PLAN.md`, `../atento-mexico-vkpi-integration/PLAN.md`
