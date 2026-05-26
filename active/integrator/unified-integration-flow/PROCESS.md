# PROCESS - Unified Integration Flow

> Reference: KNOWLEDGE.md

## Overview

This document models all business processes for the Unified Integration Flow feature. The system
operates under two fundamentally different contracts with clients:

- **Self-Service Integration** — the client normalizes their data into 4Shark's canonical `fsk_*`
  schema. The integrator pulls from that schema. No Source/Stream/Connector configuration in MongoDB.
- **Managed Integration** — 4Shark connects directly to the client's systems (API, database, or
  both), configures extraction and mapping, and runs the pipeline. Full Source/Stream/Connector
  configuration in MongoDB.

Integration mode is persisted as a field in MongoDB (not an environment variable) so the web
management interface can render the appropriate UI per client without redeploy.

**Target state**: After the unified flow is deployed, Process 2 (Self-Service) ceases to exist
as a separate execution path. Self-service clients run through Process 3 (Managed) with a
DatabaseSource configured as `normalized: true`. Process 7 (Seed Task) describes the migration
path. All 44 self-service workers are deleted.

---

## Process 1: Client Onboarding

### Trigger

A new client is being set up on the integrator for the first time. Operations receives a request
to onboard a new client and begins the configuration process.

### Main Flow

    [Operations receives new client request]
                    │
                    ▼
         Assess client capability
                    │
                    ├── Client has IT team and       ──► [Self-Service Onboarding Path]
                    │   can normalize their data
                    │
                    └── Client lacks IT team or      ──► [Managed Onboarding Path]
                        cannot normalize data

### Self-Service Onboarding Path

    [Decision: Self-Service]
            │
            ▼
    Step 1: Provision client infrastructure
    (EC2 instance, ECS services, MongoDB, Redis)
            │
            ▼
    Step 2: Set integration_mode = "self_service"
    in MongoDB client configuration document
            │
            ▼
    Step 3: Share fsk_* schema documentation
    with the client's IT team
            │
            ▼
    Step 4: Client normalizes their data
    into fsk_* tables (client-side work)
            │
            ▼
    Step 5: Operations verifies database
    connectivity (telnet host:port)
            │
            ├── Reachable ──► Step 6
            │
            └── Unreachable ──► Fix networking, retry Step 5
            │
            ▼
    Step 6: Trigger DatabaseIntegrator
    (first integration run)
            │
            ├── Success ──► [Client onboarded — Self-Service]
            │
            └── Failure ──► Review error report, fix schema, retry Step 6

### Managed Onboarding Path

    [Decision: Managed]
            │
            ▼
    Step 1: Provision client infrastructure
    (EC2 instance, ECS services, MongoDB, Redis)
            │
            ▼
    Step 2: Set integration_mode = "managed"
    in MongoDB client configuration document
            │
            ▼
    Step 3: Discovery call (1-2 hours)
    Operations + client identify where data lives:
    - Which systems hold each stream type
    - Whether each system is API or Database
    - Authentication method per system
    - Field names and structure
            │
            ▼
    Step 4: Configure Data Sources in MongoDB
    (via web management interface)
            │
            ├── For each API Source:
            │   - Register ApiSource
            │     (name, identifier, timezone, resource_limit)
            │   - Configure Authentication
            │     (endpoint, grant_type, credentials)
            │   - Configure HealthCheck
            │     (endpoint, expected status code)
            │
            └── For each Database Source:
                - Register DatabaseSource
                  (host, port, credentials, adapter type)
            │
            ▼
    Step 5: Configure Streams in MongoDB
    (which resource types to extract, one per business entity)
            │
            For each enabled Stream (User, Deal, Goal, etc.):
            - Set enabled = true
            - Assign Data Source (API or Database)
            - Configure Connector:
              - API Connector: URI, query template, pagination,
                collection source path, attribute mappings
              - Database Connector: query, table name, primary key,
                attribute mappings
            │
            ▼
    Step 6: Verify connectivity per source
    (see Process 4: Connectivity Verification Per Source Type)
            │
            ├── All sources healthy ──► Step 7
            │
            └── Source(s) unhealthy ──► Fix config, retry Step 6
            │
            ▼
    Step 7: Trigger managed integration
    (first integration run)
            │
            ├── Success ──► [Client onboarded — Managed]
            │
            └── Failure ──► Review report, adjust mappings, retry Step 7

### Detailed Steps

#### Assess Client Capability

- **Actor**: Operations team
- **Input**: Client profile, technical team composition
- **Action**: Determine whether client can normalize data independently
- **Output**: Integration mode decision (self_service or managed)
- **Criteria**: Does the client have an IT/engineering team? Can they run SQL transformations?

#### Provision Infrastructure

- **Actor**: Operations team (via management scripts / Terraform)
- **Input**: Client name, environment configuration
- **Action**: Stand up EC2 instance, ECS services, MongoDB collection, Redis
- **Output**: Running client deployment with accessible MongoDB

#### Set Integration Mode

- **Actor**: Operations team (via web management interface)
- **Input**: Integration mode decision
- **Action**: Write `integration_mode: "self_service"` or `integration_mode: "managed"` to
  the MongoDB client configuration document
- **Output**: Persisted mode in MongoDB; web interface renders appropriate screens on next load
- **Note**: This replaces the `INTEGRATION_MODE` environment variable. No redeploy required.

#### Discovery Call (Managed only)

- **Actor**: Operations team + client stakeholders + (future) AI-assisted data discovery
- **Input**: Client's existing systems and data model
- **Action**: Map each stream type to its source system, identify field structure, authentication
  method, and data volume
- **Output**: Documented mapping of stream → source system → fields
- **Target duration**: 1-2 hours per the business constraint
- **AI vision**: AI connects to the client's database during the call, explores tables and columns,
  suggests attribute mappings, and validates queries — all within the session

#### Configure Data Sources (Managed only)

- **Actor**: Operations team (via web management interface)
- **Input**: Connection credentials, auth config, health check config
- **Action**: Create Source documents in MongoDB (ApiSource for API sources;
  DatabaseSource for database sources)
- **Output**: Source documents persisted in MongoDB

#### Configure Streams and Connectors (Managed only)

- **Actor**: Operations team (via web management interface)
- **Input**: Stream type, assigned Data Source, extraction config, field mappings
- **Action**: Create Stream documents with Connectors and AttributeMappings
- **Output**: Stream/Connector/AttributeMapping documents persisted in MongoDB

#### First Integration Run

- **Actor**: Scheduler (cron) or manual trigger via management interface
- **Input**: Configured MongoDB documents, reachable sources
- **Action**: Trigger the appropriate integrator worker for the client's mode
- **Output**: Integration report delivered by email; resources loaded into 4Shark API

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Onboarded — Self-Service | Client completes fsk_* normalization, connectivity verified | First scheduled run succeeds |
| Onboarded — Managed | All sources configured and connectivity verified | First scheduled run succeeds |
| Partial config | Some streams skipped or disabled | Those streams do not run; others proceed normally |
| Connectivity failure at setup | Source unreachable during Step 6 | Ops adjusts config; no job runs until verified |

---

## Process 2: Self-Service Integration Execution

### Overview

> **NOTE**: This process describes the CURRENT self-service flow which will be absorbed into
> the managed flow. After the unified flow is deployed, self-service clients will run through
> Process 3 with a DatabaseSource configured as `normalized: true`. This process is preserved
> here for reference and migration validation.

The Self-Service integration runs the `fsk_*` database pipeline. This flow is documented as-is,
renamed to Self-Service terminology. It will be replaced by Process 3 when Phase 5 is complete.

### Trigger

Scheduler triggers `DatabaseIntegrator` on the configured cron interval (e.g., nightly).

### Main Flow

    [Cron triggers DatabaseIntegrator]
                    │
                    ▼
    Step 1: Acquire distributed lock
    (Redis, key: "integrator")
                    │
                    ├── Lock already held ──► Exit silently
                    │                        (integration already running)
                    │
                    └── Lock acquired ──► Continue
                    │
                    ▼
    Step 2: Create Job record in MongoDB
    (starts_at, fetch_since, application_version,
     database_version, integration_version)
                    │
                    ▼
    Step 3: Database connectivity check
    (telnet host:port, timeout: 5s)
                    │
                    ├── Unreachable ──► UnreachableHostReport
                    │                  Send email, release lock, end
                    │
                    └── Reachable ──► Step 4
                    │
                    ▼
    Step 4: Throughput calculation
    (count all fsk_* table rows updated since fetch_since)
                    │
                    ├── Throughput > ceiling ──► HighThroughputReport
                    │                            Send email, release lock, end
                    │
                    └── Within normal range ──► Step 5
                    │
                    ▼
    Step 5: Permission check
    (verify SELECT on all required fsk_* tables)
                    │
                    ├── Missing permissions ──► MissingAccessReport
                    │                           Send email, release lock, end
                    │
                    └── Permissions OK ──► Step 6
                    │
                    ▼
    Step 6: Table lock check
    (detect open transactions blocking the schema)
                    │
                    ├── Locks present ──► OpenTransactionsReport
                    │                     Send email, release lock, end
                    │
                    └── No locks ──► Step 7
                    │
                    ▼
    Step 7: Extraction phase
    Stream extractors run sequentially, each triggering the next
    (see Extraction Chain Detail below)
                    │
                    ▼
    Step 8: Transformation phase
    Stream transformer producers/consumers run sequentially
    (see Transformation Chain Detail below)
                    │
                    ▼
    Step 9: Load phase
    Stream loader producers/consumers run sequentially
    (see Loading Chain Detail below)
                    │
                    ▼
    Step 10: Job::Finisher
    Record ends_at, trigger integration report
                    │
                    ▼
    Step 11: IntegrationReport::Producer / Consumer
    Generate workbook, send email to all recipients
                    │
                    ▼
    Step 12: Resource::Producer / Consumer
    Archive old Resource documents to S3, free MongoDB space
                    │
                    ▼
    Step 13: ShutDownWorker
    Stop EC2 instance, scale down ECS (production only)
                    │
                    ▼
    [Integration complete]

### Extraction Chain Detail (Self-Service)

Each stream extractor pages through its `fsk_*` table using cursor-based pagination
(`collection_last_id`). When no more pages remain, it triggers the next stream extractor.

    Stream::DatabaseExtractor (job_id, collection_last_id = nil)
            │
            ├── More rows exist ──► Create Collection document in MongoDB
            │                       Set collection_last_id = last row id
            │                       Re-enqueue self (next page)
            │
            └── No more rows ──► Enqueue NextStream::DatabaseExtractor
            │
            ▼ (when Goal finishes — last stream)
    job.finish_extraction (records fetch_ends_at on Job)

Extraction order (business-dependency-driven, must be preserved):

     1.  Subsidiary       (org units — no upstream dependencies)
     2.  Hierarchy        (org structure — depends on Subsidiary)
     3.  User             (people — depends on Hierarchy)
     4.  UserIdentifier   (user external IDs — depends on User)
     5.  Client           (client accounts — depends on User)
     6.  Product          (product catalog — no hard dependency but ordered here)
     7.  Group            (sales groups — depends on User)
     8.  Groupification   (group memberships — depends on Group + User)
     9.  UserField        (custom user attributes — depends on User)
    10.  UserActivity     (user events — depends on User)
    11.  Deal             (sales deals — depends on User + Client)
    12.  DealExtraField   (deal attributes — depends on Deal)
    13.  Modifier         (deal modifiers — depends on Deal)
    14.  Goal             (sales goals — depends on User + Group)

Retry on transient connection errors: re-enqueue self with same `collection_last_id`.
The extractor resumes from the last successfully stored page.

### Transformation Chain Detail (Self-Service)

Each stream transformer producer reads Collections from MongoDB, sets the queue counter in
Computation (Redis), enqueues transformer consumer jobs in bulk, and waits for the counter to
reach zero before triggering the next stream.

    Stream::DatabaseTransformerProducer (job_id)
            │
            ├── Collections exist ──► Increment Computation queue counter
            │                          Push bulk Stream::DatabaseTransformerConsumer jobs
            │
            └── No collections ──► Enqueue NextStream::DatabaseTransformerProducer
            │
    Stream::DatabaseTransformerConsumer (collection_id, raw_object_id)
            │
            ├── Read raw row from Collection
            ├── Enrich with related data (e.g., user for a deal row)
            ├── Find or create Resource document by external_id
            ├── Write Import embedded in Resource (data = transformed hash)
            └── Increment Computation execution counter
                    │
                    └── When queue == executions (Computation.done?)
                            ──► Enqueue NextStream::DatabaseTransformerProducer

Retry on transient connection errors: re-enqueue consumer with same arguments.
Overwrites the same Import record (idempotent).

### Loading Chain Detail (Self-Service)

The loading phase is shared between Self-Service and Managed (see Process 3).

    Stream::LoaderProducer (job_id, collection_last_id = nil)
            │
            ├── First call ──► Count total Resources with imports for this Job
            │                   Increment Computation queue counter
            │                   Enqueue page of Stream::LoaderConsumer jobs
            │                   Re-enqueue self (next page)
            │
            ├── Subsequent pages ──► Enqueue next page of consumers
            │                         Re-enqueue self
            │
            └── No resources with imports ──► Enqueue NextStream::LoaderProducer
            │
    Stream::LoaderConsumer (job_id, resource_id)
            │
            ├── Read Resource and its Import for this Job
            ├── Evaluate integration_status state machine:
            │   - pending ──► create in 4Shark API
            │   - integrated / disabled ──► update in 4Shark API
            ├── Transition state machine accordingly
            └── Increment Computation execution counter
                    │
                    └── When queue == executions (Computation.done?)
                            ──► Enqueue NextStream::LoaderProducer

Loading order (same resource sequence as extraction, ending at Job::Finisher):

     1.  Subsidiary
     2.  Hierarchy
     3.  User (by role: Admin → President → VicePresident → Director → Superintendent
               → GeneralManager → Manager → Coordinator → Supervisor → SalesRepresentative)
     4.  ParentUpdate (hierarchy corrections)
     5.  UserIdentifier
     6.  Client
     7.  Product
     8.  Group
     9.  Groupification
    10.  UserField
    11.  UserActivity
    12.  Deal
    13.  DealExtraField
    14.  Modifier
    15.  Goal ──► Job::Finisher

### Actors (Self-Service)

| Actor | Role | Responsibilities |
|-------|------|------------------|
| Scheduler (cron) | Trigger | Fires DatabaseIntegrator on schedule |
| DatabaseIntegrator | Orchestrator | Acquires lock, creates Job, runs pre-flight checks, starts extraction |
| DatabaseWarmer | Retry handler | Retries DB connection up to 3 times with 5-minute delays before reporting |
| ThroughputCalculator | Guard | Counts fsk_* rows updated since fetch_since |
| Stream::DatabaseExtractor | Extractor | Pages through one fsk_* table, stores raw Collections |
| Stream::DatabaseTransformerProducer | Transformer coord. | Fans out transformation work per Collection |
| Stream::DatabaseTransformerConsumer | Transformer worker | Transforms one record, writes Import to Resource |
| Stream::LoaderProducer | Loader coord. | Pages Resources with imports, fans out load work |
| Stream::LoaderConsumer | Loader worker | Calls 4Shark API for one resource, transitions state machine |
| Job::Finisher | Finalizer | Records ends_at, triggers integration report |
| IntegrationReport::Producer / Consumer | Reporter | Sends email report to all configured recipients |
| Resource::Producer / Consumer | Archiver | Moves old Resource documents to S3 |
| ShutDownWorker | Cleanup | Stops EC2, scales down ECS |

### Data Flow (Self-Service)

| From | To | Data | Format |
|------|----|------|--------|
| fsk_* tables (SQL Server / PostgreSQL) | Collection (MongoDB) | Raw rows, paged | Array of hashes |
| Collection (MongoDB) | Import embedded in Resource (MongoDB) | Transformed record | Hash |
| Import (MongoDB) | 4Shark API | Normalized request body | JSON via HTTP |
| 4Shark API | Resource state machine | Response status | HTTP status code |
| Job (MongoDB) | Email report | Timing, request counts, error list | Workbook + SMTP |
| Resource (MongoDB) | S3 | Archived document | JSON |

---

## Process 3: Managed Integration Execution

### Overview

A Managed integration runs a single job that may extract from multiple sources per stream — each
stream independently configured to use an API connector, a database connector, or both. The
extraction, transformation, and loading phases are sequential by stream but parallel within each
stream (fan-out via Sidekiq bulk push).

### Trigger

Scheduler triggers the managed integrator worker (analogous to the current `ApiIntegrator` but
extended to handle mixed sources) on the configured cron interval.

### Main Flow

    [Cron triggers ManagedIntegrator]
                    │
                    ▼
    Step 1: Acquire distributed lock
    (Redis, key: "integrator")
                    │
                    ├── Lock held ──► Exit silently
                    │
                    └── Lock acquired ──► Continue
                    │
                    ▼
    Step 2: Create Job record in MongoDB
    (starts_at, fetch_since, application_version,
     total_external_applications, total_enabled_streams)
                    │
                    ▼
    Step 3: Connectivity verification for ALL configured sources
    (see Process 4: Connectivity Verification Per Source Type)
                    │
                    ├── Any source fails ──► Send report for that source type
                    │                        Release lock, end job
                    │
                    └── All sources healthy ──► Step 4
                    │
                    ▼
    Step 4: Begin ordered stream extraction
    (first enabled stream in configured order)
                    │
                    ▼
    Step 5: Per-stream ELT cycle
    (see Per-Stream Execution Detail below)
    Repeats for each stream in order
                    │
                    ▼
    Step 6: Job::Finisher
    Record ends_at, trigger integration report
                    │
                    ▼
    Step 7: IntegrationReport → Resource archiving → ShutDown
    (same as Self-Service Steps 11–13)

### Per-Stream Execution Detail (Managed)

    [Stream N begins]
            │
            ▼
    Read stream's Connector from MongoDB
            │
            ├── Connector type = API ──► API Extraction Path
            │
            └── Connector type = Database ──► Database Extraction Path
            │
    API Extraction Path:
    ┌─────────────────────────────────────────────┐
    │ Resolve ApiSource (auth tokens,              │
    │   base URL, resource_limit, timezone)        │
    │ Resolve Connector (URI template, query       │
    │   template, paginated_query_template,        │
    │   collection_source_keys, sensitive_keys)    │
    │                                              │
    │ Loop: paginated HTTP GET                     │
    │   ├── Build query from template + variables  │
    │   ├── GET uri with authenticated headers     │
    │   ├── Unexpected status ──► Raise exception  │
    │   └── Success ──► Parse JSON                 │
    │                   Strip sensitive keys       │
    │                   Store raw body + headers   │
    │                   Create ApiRequest record   │
    │   Repeat until last_page?(collection_size)   │
    │                                              │
    │ Trigger next stream's extractor              │
    └─────────────────────────────────────────────┘

    Database Extraction Path:
    ┌─────────────────────────────────────────────┐
    │ Resolve DatabaseSource (host, port,          │
    │   credentials, adapter)                      │
    │ Resolve Connector (table/query, primary key, │
    │   fetch_since condition)                     │
    │                                              │
    │ Loop: cursor-based pagination                │
    │   ├── Query with updated_at >= fetch_since   │
    │   │     and id > collection_last_id          │
    │   ├── Connection error ──► Re-enqueue self   │
    │   └── Success ──► Store raw Collection       │
    │                   Advance cursor             │
    │   Repeat until no more rows                  │
    │                                              │
    │ Trigger next stream's extractor              │
    └─────────────────────────────────────────────┘

    [All streams extracted → job.finish_extraction]
            │
            ▼
    Transformation phase (same order as extraction):

    API Transformer:
    ┌─────────────────────────────────────────────┐
    │ For each ApiRequest for this stream + job:   │
    │   Read raw body from stored file             │
    │   Extract collection (via collection_source) │
    │   For each record:                           │
    │     Apply simple AttributeMappings (dynamic, │
    │       fixed) to produce attributes hash      │
    │     Apply compound AttributeMappings         │
    │       (template, formula) using attributes   │
    │     Find/create Resource by external_id      │
    │     Write Import embedded in Resource        │
    └─────────────────────────────────────────────┘

    Database Transformer Producer / Consumer:
    ┌─────────────────────────────────────────────┐
    │ Producer: set Computation queue = batch size │
    │           push bulk Consumer jobs            │
    │ Consumer: read raw row from Collection       │
    │           apply AttributeMappings            │
    │           write Import embedded in Resource  │
    │           increment Computation counter      │
    │           when done → next stream            │
    └─────────────────────────────────────────────┘

    [Transformation complete → Loading phase]
            │
            ▼
    Loading phase (shared — source-agnostic):
    Same LoaderProducer / LoaderConsumer flow as Self-Service.
    Reads Import documents from Resources; calls 4Shark API.

### Stream Execution Order (Managed)

The execution order reflects business dependencies and must be preserved even when different
streams use different source types. The order is the same as in Self-Service:

     1.  Subsidiary
     2.  Hierarchy
     3.  User (with sub-roles for API mode: Admin → President → ... → SalesRepresentative)
     4.  UserIdentifier
     5.  Client
     6.  Product
     7.  Group
     8.  Groupification
     9.  UserField
    10.  UserActivity
    11.  Deal
    12.  DealExtraField
    13.  Modifier
    14.  Goal

Each stream in this order may use a different source type. Example: User from Active Directory
API, Deal from SQL Server, Goal from a REST API.

### Mixed-Source Scenario (Illustrative Example)

Client with User from an AD API and Deal from SQL Server:

    Job starts
        │
        ▼
    Connectivity checks:
        ├── API Source (Active Directory):
        │   HealthCheck HTTP GET ──► OK
        │   ConnectionCheck POST (OAuth) ──► Token stored
        └── Database Source (SQL Server):
            Telnet 1433 ──► Reachable
            Permissions ──► OK
            Locks ──► None
        │
        ▼
    Extraction (in order):
        ├── Subsidiary (Database) ──► Collection stored
        ├── Hierarchy (Database) ──► Collection stored
        ├── User (API — Active Directory) ──► Raw bodies stored
        └── Deal (Database — SQL Server) ──► Collection stored
        │
        ▼
    Transformation (in order):
        ├── Subsidiary (Database path) ──► Imports written
        ├── Hierarchy (Database path) ──► Imports written
        ├── User (API path, AttributeMappings) ──► Imports written
        └── Deal (Database path) ──► Imports written
        │
        ▼
    Loading (shared path, in order):
        ├── Subsidiary::Loader ──► 4Shark API
        ├── Hierarchy::Loader ──► 4Shark API
        ├── User::Loader ──► 4Shark API
        └── Deal::Loader ──► 4Shark API
        │
        ▼
    Job::Finisher ──► IntegrationReport ──► Archive ──► ShutDown

### Actors (Managed)

| Actor | Role | Responsibilities |
|-------|------|------------------|
| Scheduler (cron) | Trigger | Fires ManagedIntegrator on schedule |
| ManagedIntegrator | Orchestrator | Acquires lock, creates Job, dispatches connectivity checks |
| HealthCheck::Processor | Pre-flight | HTTP health check for each API source |
| ConnectionCheck::Processor | Pre-flight | Auth token acquisition for each API source |
| Database connectivity check | Pre-flight | Telnet + permissions + lock check for each database source |
| Stream::Extractor (API path) | Extractor | Paginated HTTP GET, stores raw bodies and ApiRequest records |
| Stream::Extractor (Database path) | Extractor | Cursor pagination on configured query/table, stores Collections |
| Stream::ApiTransformer | Transformer | Reads raw bodies, applies AttributeMappings, writes Imports |
| Stream::DatabaseTransformerProducer | Transformer coord. | Fans out transformation work |
| Stream::DatabaseTransformerConsumer | Transformer worker | Transforms one record, writes Import |
| Stream::LoaderProducer | Loader coord. | Pages Resources with imports, fans out load work |
| Stream::LoaderConsumer | Loader worker | Calls 4Shark API per resource, transitions state machine |
| Job::Finisher | Finalizer | Records ends_at, triggers integration report |

### Data Flow (Managed)

| From | To | Data | Format |
|------|----|------|--------|
| External API (via HTTP) | Raw body file (local / S3) | Paginated HTTP response | JSON |
| External API (via HTTP) | ApiRequest + ApiResponse (MongoDB) | Request URI, response status | MongoDB documents |
| Database source (via Sequel) | Collection (MongoDB) | Raw rows, paged | Array of hashes |
| Raw body file | Import embedded in Resource (MongoDB) | Normalized record via AttributeMapping | Hash |
| Collection (MongoDB) | Import embedded in Resource (MongoDB) | Normalized record via AttributeMapping | Hash |
| Import (MongoDB) | 4Shark API | Normalized request body | JSON via HTTP |
| Job (MongoDB) | Email report | Timing, request counts, errors | Workbook + SMTP |

---

## Process 4: Connectivity Verification Per Source Type

### Overview

Before any extraction begins, the system verifies that every configured source is reachable and
authorized. The behavior differs by source type. For mixed-source clients, both check types run
before the first extractor is triggered.

### Trigger

Connectivity verification is triggered by the integrator worker (both modes) after the Job record
is created, before the first extractor runs. Also callable manually from the web management
interface during onboarding.

### API Source Connectivity Flow

    [API Source connectivity check triggered]
                    │
                    ▼
    Step 1: HealthCheck::Processor
    For each ApiSource:
        HTTP GET to health_check.endpoint
                    │
                    ├── All return expected status ──► Step 2
                    │
                    └── Any return unexpected status ──► Collect unavailable names
                                                         HealthCheckReport::Producer
                                                         Send email report
                                                         Abort job
                    │
                    ▼
    Step 2: ConnectionCheck::Processor
    For each ApiSource:
        HTTP POST to authentication.endpoint
        with client credentials (client_id, client_secret, grant_type, etc.)
                    │
                    ├── All succeed ──► Store auth tokens in AuthenticationResponse (MongoDB)
                    │                  Proceed to extraction
                    │
                    └── Any fail ──► Collect unauthorized names
                                     ConnectionCheckReport::Producer
                                     Send email report
                                     Abort job

### Database Source Connectivity Flow

    [Database Source connectivity check triggered]
                    │
                    ▼
    Step 1: Network reachability
    Net::Telnet to host:port (timeout: 5s)
                    │
                    ├── Reachable ──► Step 2
                    │
                    └── Timeout / SSL error / connection reset ──► UnreachableHostReport::Producer
                                                                    Send email report
                                                                    Abort job
                    │
                    ▼
    Step 2: Throughput check (Self-Service only)
    ThroughputCalculator counts all fsk_* rows updated since fetch_since
                    │
                    ├── Throughput <= ceiling ──► Step 3
                    │
                    └── Throughput > ceiling ──► HighThroughputReport::Producer
                                                  Send email report
                                                  Abort job (anomaly guard)
                    │
                    ▼
    Step 3: Permission check
    Verify SELECT on all required tables
                    │
                    ├── All permissions present ──► Step 4
                    │
                    └── Missing permissions ──► MissingAccessReport::Producer
                                                Send email report
                                                Abort job
                    │
                    ▼
    Step 4: Lock check
    Detect open transactions blocking schema access
                    │
                    ├── No locks ──► Proceed to extraction
                    │
                    └── Locks detected ──► OpenTransactionsReport::Producer
                                           Send email report
                                           Abort job

### Mixed-Source Client: Both Checks Run

For a client with both API and database sources, connectivity checks run for all sources before
extraction begins:

    [ManagedIntegrator starts connectivity phase]
                    │
                    ├── API sources exist ──► Run HealthCheck::Processor
                    │                         then ConnectionCheck::Processor
                    │
                    └── Database sources exist ──► Run database connectivity check
                                                   (telnet → permissions → locks)
                    │
                    ▼
    Both must pass before extraction begins.
    Either failure aborts the entire job.

### Failure Policy for Mixed-Source Partial Failures

NOTE: The exact policy for partial failures in mixed-source jobs is an open question
(see KNOWLEDGE.md Open Questions). The current system always aborts on any connectivity failure.
This documents current behavior.

    [One source fails connectivity]
            │
            ├── Conservative (current behavior):
            │   Abort entire job regardless of which source failed.
            │   Report which source failed and why.
            │
            └── Partial run (future option — requires business decision):
                Skip streams whose source failed.
                Run streams with healthy sources.
                Report partial run with affected streams named.

### Sequence Diagram

    Integrator    HealthCheck    ConnectionCheck    DBCheck
        │               │                │              │
        │── start ─────►│                │              │
        │               │── GET (health)─►API Source    │
        │               │◄── 200 ────────│              │
        │               │── POST (auth) ─►API Source    │
        │               │◄── token ──────│              │
        │               │── store token ─►MongoDB       │
        │               │──────────────────────────────►│
        │               │                │              │── telnet
        │               │                │              │── permissions
        │               │                │              │── locks
        │◄── all OK ───────────────────────────────────│

### Retry Behavior Summary

| Failure Type | Behavior | Limit |
|---|---|---|
| Database connection error during extraction | Re-enqueue extractor with same cursor | Unlimited (transient) |
| API unreachable during extraction (retry_count check) | Raise UnreachableApiException after 2 retries | 3 total |
| Database warm-up failure at startup | DatabaseWarmer retries with 5-minute delay | 3 total |
| Unexpected API response status during extraction | Raise exception, stream fails | No retry |
| 4Shark API parse exception during load | Re-enqueue LoaderConsumer after 5 seconds | Sidekiq default after |

---

## Process 5: Mode Transition (Future Consideration)

### Status

Not a current requirement. Documented as a future consideration to ensure architectural decisions
do not preclude this path.

### Self-Service to Managed

    [Client requests transition to Managed]
                    │
                    ▼
    Step 1: Operations assessment
    - What data exists in 4Shark from prior Self-Service runs?
    - Are there Resources and Import history in MongoDB?
    - Which fsk_* fields came from the client's source vs. were added by 4Shark?
                    │
                    ▼
    Step 2: Discovery call (same as Managed onboarding)
    - Identify source systems for each stream type
    - Map source fields to fsk_* field equivalents
    - Confirm coverage is complete before cutover
                    │
                    ▼
    Step 3: Configure Managed sources in parallel
    (do not remove fsk_* yet — run both in staging)
    - Register Sources (ApiSource / DatabaseSource)
    - Configure Streams, Connectors, AttributeMappings
                    │
                    ▼
    Step 4: Dry-run Managed extraction
    - Run extraction + transformation without loading to 4Shark API
    - Compare Managed output with current Self-Service data
    - Validate field coverage and value accuracy
                    │
                    ├── Data matches ──► Step 5
                    │
                    └── Discrepancies ──► Adjust mappings, retry Step 4
                    │
                    ▼
    Step 5: Cutover
    - Update integration_mode = "managed" in MongoDB
    - Next scheduled run uses Managed path
    - fsk_* tables remain intact but are no longer read
                    │
                    ▼
    Step 6: Monitor first N Managed runs
    - Compare job metrics with Self-Service historical baseline
    - Confirm all resources are loading correctly
                    │
                    ▼
    [Transition complete — client is now Managed]

### Managed to Self-Service

    [Client builds internal IT capacity]
                    │
                    ▼
    Step 1: Provide client with fsk_* schema documentation
                    │
                    ▼
    Step 2: Client normalizes their data into fsk_* tables
    (client-side work, runs in parallel with ongoing Managed jobs)
                    │
                    ▼
    Step 3: Validate fsk_* data completeness
    - Operations verifies all required tables populated
    - Spot-check data quality vs. current Managed output
                    │
                    ▼
    Step 4: Cutover
    - Update integration_mode = "self_service" in MongoDB
    - Next scheduled run uses Self-Service path
                    │
                    ▼
    [Transition complete — client owns their normalization]

### Critical Considerations

- **Import identifier prefix**: `Import#identifier` currently branches on
  `ApplicationConfiguration.api_integration?` to decide whether to prefix with `4sk_`. With
  `integration_mode` in MongoDB, this branch must use the persisted mode. A mid-history transition
  changes the identifier logic — existing Records in 4Shark may appear as new records unless the
  transition is handled at the cutover boundary (not mid-run).

- **Mode transitions are cutover events, not live toggles**: Changing `integration_mode` in MongoDB
  takes effect on the next scheduled run. A transition during an active run would cause inconsistent
  behavior. Operations must coordinate the cutover with the job schedule.

- **Historical Import data is mode-agnostic in structure**: The `Import` document schema does not
  change between modes. What changes is the identifier prefix and the source of the data. This
  means historical Imports from Self-Service runs remain valid after a transition.

---

## Process 6: Web Interface Interaction

### Overview

The web management interface (separate project) reads integration configuration and status from
MongoDB to render the appropriate UI per client. The interface needs to know the integration mode
to decide which screens and datasets to present.

### Trigger

An operations engineer opens a client's management screen in the web interface.

### Main Flow

    [Engineer opens client management screen]
                    │
                    ▼
    Step 1: Read integration_mode from MongoDB
    (client configuration document)
                    │
                    ├── integration_mode = "self_service" ──► Render Self-Service UI
                    │
                    └── integration_mode = "managed" ──► Render Managed UI

### Self-Service UI: Data Requirements

MongoDB reads needed to render the Self-Service UI:

    ├── integration_mode = "self_service"
    ├── Job history:
    │   ├── Total job count
    │   ├── Most recent Job: ends_at, duration, request counts
    │   └── Last N jobs: starts_at, ends_at, duration, failed_requests_quantity
    └── Database connection status:
        ├── Last known connectivity result (reachable / unreachable)
        └── Timestamp of last connectivity check

UI surfaces:
- Job history table (date, duration, records loaded, error count)
- Database status indicator
- Integration version info (application_version, database_version, integration_version)

### Managed UI: Data Requirements

MongoDB reads needed to render the Managed UI:

    ├── integration_mode = "managed"
    ├── Job history (same as Self-Service)
    ├── Sources:
    │   ├── ApiSources:
    │   │   (name, identifier, timezone, resource_limit,
    │   │    health_check status, authentication status)
    │   └── DatabaseSources:
    │       (name, host, port, adapter, last connectivity result)
    ├── Streams:
    │   ├── All stream types (User, Deal, Goal, etc.)
    │   ├── enabled / disabled per stream
    │   └── assigned Data Source per stream
    └── Connectors:
        ├── API Connectors per stream:
        │   (URI, query templates, collection_source, attribute mappings,
        │    sensitive keys, success_response_status_code)
        └── Database Connectors per stream:
            (query/table name, primary key, attribute mappings)

UI surfaces:
- Job history table (same as Self-Service)
- Sources management screen: list, add, edit, delete, test connectivity
- Streams management screen: enable/disable, assign source, reorder
- Connector configuration: attribute mapping editor per stream

### Common Data (Both Modes)

Both UIs always display:

| Data | Source in MongoDB |
|------|------------------|
| Integration mode | Client configuration document |
| Total job count | Job collection count |
| Last job date | Max(ends_at) across Job collection |
| Last N job durations and statuses | Job collection, ordered by starts_at desc |
| Application version | Job.application_version (most recent) |

### Interaction Sequence

    Web UI         MongoDB         Integrator (background)
       │               │                    │
       │── read ──────►│                    │
       │   integration_mode                 │
       │◄── "managed" ─│                    │
       │               │                    │
       │── read ──────►│                    │
       │   Jobs (last N)                    │
       │◄── job list ──│                    │
       │               │                    │
       │── read ──────►│                    │
       │   Sources +                        │
       │   Streams +                        │
       │   Connectors                       │
       │◄── config ────│                    │
       │               │                    │
       │── render Managed UI                │
       │               │                    │
       │── (ops edits) │                    │
       │── write ─────►│                    │
       │   updated Connector doc            │
       │               │                    │
       │               │◄── next scheduled run reads updated config
       │               │                    │── uses new Connector

### Architecture Note on Access Pattern

The web interface currently reads MongoDB directly — there is no REST API layer on the integrator
side. This is an open question (see KNOWLEDGE.md Open Questions): should the integrator expose an
HTTP API, or does the web app continue to read MongoDB directly?

The direct-MongoDB approach means the MongoDB document structure IS the contract between the
integrator and the web interface. Any schema change to Source/Stream/Connector documents requires
coordinated updates to both the integrator and the web interface.

---

## Outcomes Summary

| Outcome | Condition | Result |
|---------|-----------|--------|
| Self-Service run succeeds | All connectivity checks pass, all fsk_* data extracted | Resources loaded into 4Shark API, email report sent, instance stopped |
| Managed run succeeds | All sources healthy, all streams extracted | Resources loaded into 4Shark API, email report sent, instance stopped |
| Database host unreachable | Telnet timeout to host:port | UnreachableHostReport email, job aborted |
| Database connection error at startup | TinyTds / Sequel connection error | DatabaseWarmer retry up to 3 times, then UnreachableHostReport |
| Throughput anomaly | Row count > ceiling threshold | HighThroughputReport email, job aborted |
| Missing permissions | SELECT not granted on required tables | MissingAccessReport email, job aborted |
| Table locks detected | Open transactions block schema | OpenTransactionsReport email, job aborted |
| API health check failure | Unexpected HTTP status from health endpoint | HealthCheckReport email, job aborted |
| API auth failure | Unexpected HTTP status from auth endpoint | ConnectionCheckReport email, job aborted |
| Unexpected API response during extraction | Non-success HTTP status on a data request | Exception raised, stream fails, Sidekiq retries |
| API permanently unreachable during extraction | retry_count > 2 | UnreachableApiException raised |
| Concurrent run attempt | Lock already held in Redis | Silent skip — integrator already running |
| Client onboarded — Self-Service | fsk_* schema populated, connectivity verified | First scheduled run succeeds |
| Client onboarded — Managed | All sources configured and verified | First scheduled run succeeds |
| Mode changed in MongoDB | integration_mode field updated | Web UI renders new mode on next page load; next run uses new mode |

---

## Notes

- **Self-Service extraction order is a business invariant** — subsidiaries before hierarchy before
  users before deals reflects real data dependencies. Downstream resources reference upstream ones.
  This ordering must be preserved even if the mechanism that enforces it changes (from hardcoded
  class calls to configurable position fields in MongoDB).

- **Computation (Redis counters) is the synchronization backbone** — the producer/consumer pattern
  for transformation and loading relies on atomic Redis counters (`queue` and `executions`) to
  know when all workers for a stream have completed. Any restructuring must preserve this
  coordination pattern.

- **The Loader phase is already source-agnostic** — `LoaderProducer` and `LoaderConsumer` read
  from `Import` documents embedded in `Resource` records without knowing whether data came from an
  API or a database. This is the clean convergence point and requires no changes.

- **`Import#identifier` contains mode-branching logic** — currently checks
  `ApplicationConfiguration.api_integration?`. With the mode persisted in MongoDB, this must read
  from the persisted mode. This is also relevant for mode transitions: the identifier prefix
  (`4sk_`) changes when mode changes, which can affect record matching in 4Shark.

- **No production client uses Managed (API) mode yet** — this is the ideal window to rename
  MongoDB models (`ExternalApplication` → Source, `ApplicationProgrammingInterface` → Connector,
  `ExternalResource` → Stream) without a data migration burden on existing documents.

- **The web management interface is a key consumer of the domain model** — the integrator's
  MongoDB schema is effectively the API between the integrator and the web app. The structure of
  the `integration_mode` field, Source/Stream/Connector documents, and Job history must be designed
  with the web interface's read patterns in mind.

- **AI-assisted data discovery is part of the Managed onboarding vision** — during the discovery
  call, AI could connect to the client's database, explore tables and columns, suggest attribute
  mappings, and validate queries. This is a future capability but should not be architecturally
  precluded. The Database Connector configuration step (Step 5 of Managed Onboarding) is the
  natural integration point.

- **Domain model first, worker restructuring later** — this document models business processes
  using existing worker concepts (Extractor, Transformer, Loader). Worker class renaming and
  consolidation (e.g., eliminating the ApiExtractor / DatabaseExtractor duplication per stream)
  is a separate concern that follows from the domain model, not a prerequisite.

---

## Process 7: Self-Service Migration via Seed Task

### Overview

The seed task (`rake integration:seed_normalized`) migrates existing self-service clients to the
unified flow by creating Source/Stream/Connector records from environment variables. This is a
one-time operation per client, run before deploying the unified flow code.

### Trigger

Engineer runs the task on each self-service client deployment as part of the unified flow
rollout.

### Main Flow

    [Engineer runs rake integration:seed_normalized]
                    │
                    ▼
    Step 1: Read environment variables
    (CLIENT_HOST, CLIENT_PORT, CLIENT_DATABASE,
     CLIENT_USERNAME, CLIENT_PASSWORD, DATABASE_ADAPTER,
     CLIENT_AZURE, CLIENT_TIMEOUT, TABLE_PREFIX, SQL_PAGE_SIZE)
                    │
                    ▼
    Step 2: Create DatabaseSource
    (normalized: true, identifier_prefix: "4sk_",
     table_prefix from TABLE_PREFIX)
                    │
                    ▼
    Step 3: Create DatabaseAuthentication
    (username, password — encrypted)
                    │
                    ▼
    Step 4: Create HealthCheck
    (TCP socket check to host:port)
                    │
                    ▼
    Step 5: Create 14 Streams
    (one per resource in chain order,
     each linked to the DatabaseSource)

    | Position | Resource Name  | Table Name       |
    |----------|----------------|------------------|
    | 1        | Subsidiary     | subsidiaries     |
    | 2        | Hierarchy      | hierarchy        |
    | 3        | User           | users            |
    | 4        | UserIdentifier | user_identifiers |
    | 5        | Client         | clients          |
    | 6        | Product        | products         |
    | 7        | Group          | groups           |
    | 8        | Groupification | groupifications  |
    | 9        | UserField      | user_fields      |
    | 10       | UserActivity   | user_activity    |
    | 11       | Deal           | deals            |
    | 12       | DealExtraField | deal_extra_fields|
    | 13       | Modifier       | modifiers        |
    | 14       | Goal           | goals            |

                    │
                    ▼
    Step 6: Create 14 Connectors
    (one per stream, standard query:
     SELECT * FROM {prefix}{table},
     primary_key: id, fetch_since_column: updated_at,
     page_size from SQL_PAGE_SIZE)
                    │
                    ▼
    Step 7: Verify configuration
    (count streams, connectors, run health check)
                    │
                    ├── All OK ──► [Migration complete for this client]
                    │
                    └── Issues found ──► Fix env vars, re-run (idempotent)

### Idempotency

The task checks for existing configuration before creating:
- If a DatabaseSource with `normalized: true` already exists → skip source creation
- If Streams for all 14 resources already exist → skip stream creation
- Re-running the task on an already-migrated client is a no-op

### Deployment Sequence

    [Phase 1: Deploy seed task code]
    (no behavior change — self-service still works as before)
                    │
                    ▼
    [Phase 2: Run seed task on each client]
    (creates MongoDB config — self-service still works as before)
                    │
                    ▼
    [Phase 3: Deploy unified flow code]
    (self-service workers removed — clients use managed flow
     with seeded config)
                    │
                    ▼
    [Phase 4: Verify all clients running correctly]
    (compare job metrics with pre-migration baseline)

### Actors

| Actor | Role | Responsibilities |
|-------|------|------------------|
| Engineer | Executor | Runs seed task on each client, verifies output |
| Seed Task | Generator | Creates Source/Stream/Connector from env vars |
| ManagedIntegrator | Consumer | Uses seeded config for next integration run |

### Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| Migration successful | All 14 streams + connectors created | Client runs through managed flow on next cron |
| Partial migration | Some env vars missing | Task reports missing vars, does not create incomplete config |
| Already migrated | Config already exists | Task is a no-op, reports existing config |
| Post-deploy verification | First managed run completes | Compare with historical self-service job metrics |

---

**Status:** PROCESS MODELING COMPLETE — Implementation in progress
