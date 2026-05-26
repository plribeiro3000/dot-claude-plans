# PLAN — Loading Resilience & Idempotency

**Version:** 3.0 (Major - Breaking Changes)

## Problems Identified

1. **Two outcomes instead of three** - Loading stage only distinguishes success/failure, but there are actually three: success (2xx), user error (4xx), system error (5xx/timeout)

2. **No automatic retry for system errors** - When API is down or times out, records are marked as failed and user must manually re-run

3. **No separation between Operations and Requests** - Business intent (create user, activate deal) is mixed with HTTP call details

4. **Wrong integration logic for User** - User with external ID has 3 HTTP calls; marked "integrated" only if ALL 3 succeed, but user IS in 4Shark after first succeeds

5. **Retry retries everything** - When a resource needs retry, all operations are re-executed instead of just the pending ones

6. **No idempotency protection** - Retrying the same request could create duplicate data

7. **job_id saved as String** - Service objects were saving job_id as string instead of BSON::ObjectId

## Solutions Summary

| Problem | Solution | Status |
|---------|----------|--------|
| Two outcomes | Three buckets in report (success, invalid, pending) | ✅ Done |
| No retry | Two-level retry (immediate + RecoveryJob) | ✅ Level 1 / 🔄 Level 2 |
| No separation | Operation model between Import and Request | 🔄 In Progress |
| Wrong integration | PRIMARY operation determines integration | 📋 Planned |
| Retry everything | RecoveryJob retries only pending Operations | 📋 Planned |
| No idempotency | X-Idempotency-Key header | ✅ Done |
| job_id as String | Fix service objects + migration workers | ✅ Done |

## Pending Items (to address with Operation)

- [ ] Retry only pending Operations (not all)
- [ ] User LoaderConsumers: restore retriable logic per Operation
- [ ] Each Operation marks itself as executed independently
- [x] Fix job_id type (String → BSON::ObjectId) ✅ Commit e9d4b4b9

## To Revisit at End

- [ ] Race condition in Import find_or_create_by (no unique index)

## Versioning: model_version

Resources use `model_version` to determine data format:

| Version | Structure | Status |
|---------|-----------|--------|
| `1.0` | Import → Request (direct) | Legacy (don't migrate) |
| `2.0` | Import → Operation → Request | New standard |

### Strategy

1. **No migration** - 18M+ resources = not feasible
2. **Two aggregations** - V1 counts by Request, V2 counts by Operation, merge at the end
3. **Workers check version** - V1 doesn't create Operation, V2 does
4. **Gradual deprecation** - V1 resources eventually archived to S3

### S3 Archive

| Operation | V1 | V2 |
|-----------|----|----|
| Store (save) | ✅ Works | ✅ Works (to_json serializes everything) |
| Fetch (restore) | ✅ Works | ⚠️ Need to update `restore_from_s3` to process operations |

## Breaking Changes (v3.0)

1. **Data structure**: Request now embedded in Operation, not Import
2. **Service objects**: May be removed/simplified with Operation
3. **Integration logic**: Based on PRIMARY operation, not all requests
4. **Job types**: IntegrationJob/RecoveryJob instead of plain Job

---

## Current Situation

- **app:** Rails API with idempotency support via X-Idempotency-Key header
- **integrator:** ETL client that consumes the API and generates reports
- **Problem:** Loading stage has only two outcomes (success/error), but there are actually three
- **Problem:** No clear separation between Operations (business) and Requests (HTTP)
- **Problem:** User integration depends on ALL requests succeeding, but should depend on PRIMARY operation only

## Objective / Target State

Build a resilient Loading process that:

1. Handles three distinct outcomes (success, user error, system error)
2. Retries system errors automatically at two levels
3. Shows clear reports to users
4. Uses idempotency keys to prevent duplicate data
5. Separates Operations (business logic) from Requests (HTTP calls)
6. Correctly determines resource integration based on PRIMARY operation, not all requests

## The Three Outcomes

| Outcome | HTTP Status | Meaning | User Action |
|---------|-------------|---------|-------------|
| **Success** | 2xx | Record accepted | None |
| **User Error** | 4xx | Invalid data | Fix source data |
| **System Error** | 5xx / timeout | Technical issue | Wait for automatic retry |

## Data Model

### Hierarchy

```
Job
 └─ Resource
     └─ Import
         └─ Operation (NEW)
             └─ Request
                 └─ Response
```

### Operation vs Request

| Concept | Purpose | Status | Example |
|---------|---------|--------|---------|
| **Operation** | Business intent | pending / executed | "Create user", "Add identifier" |
| **Request** | HTTP call log | (none - just log) | POST /api/v3/users |

**Key insight:**
- An Operation is "pending" until executed, then "executed". Period.
- An Operation doesn't fail - it's either executed or not yet executed.
- A Request is just a log entry of an HTTP call attempt.
- Multiple Requests can exist for one Operation (retries).

### User Example

When creating a user with external ID, there are 3 Operations:

| Operation | Type | Importance |
|-----------|------|------------|
| Create user | PRIMARY | Determines if user is "integrated" |
| Create identifier | SECONDARY | Best effort, doesn't block integration |
| Select primary identifier | SECONDARY | Best effort, doesn't block integration |

**Current problem:** User is marked "integrated" only if ALL 3 succeed.

**Correct behavior:** User should be marked "integrated" after PRIMARY operation succeeds.
If secondary operations fail, they'll be retried, but the user IS already in 4Shark.

## Two Levels of Retry

### Level 1: Immediate Retry

When system error occurs during Loading:
- Retry after 5 seconds
- Up to MAX_ATTEMPTS times (configurable)
- If still failing after MAX_ATTEMPTS: mark Operation as still pending, continue pipeline

### Level 2: Automatic Recovery Job

When integration job finishes with pending Operations:
- Schedule a Recovery Job after configurable delay (e.g., 2 hours)
- Recovery Job finds Operations with status = pending
- Single retry attempt (no loop)
- If still pending: report to user, requires manual investigation

## Jobs

Two types of jobs:

| Type | Purpose | Extract | Transform | Load |
|------|---------|---------|-----------|------|
| **Integration** | Normal ETL | Yes | Yes | Yes |
| **Retry** | Recover system errors | No | No | Yes |

Both generate reports. Import can have Requests from different jobs (history preserved).

## User Notifications

### Integration Email

```
Integration completed

Success: 950 (95%)
Validation errors: 30 (3%)
System errors: 20 (2%)

Automatic retry scheduled for [time].
```

### Retry Email (success)

```
Retry completed

All system errors were successfully resolved.
```

### Retry Email (partial failure)

```
Retry completed

Recovered: 15
Validation errors: 3
System errors: 2 (persist)

Please contact the 4Shark team for assistance.
```

## User Report (Excel)

| Sheet | Content | Purpose |
|-------|---------|---------|
| Per resource type | ID, field, error message | User errors to fix |
| System Errors | ID, error type | Records pending retry |

## Implementation Phases

### Phase 1: app (DONE)

Idempotency support in API via X-Idempotency-Key header.

### Phase 2: integrator - Foundation

1. Add X-Idempotency-Key header to all HTTP calls
2. Log all outcomes (success, user error, system error)
3. Request model: success?, user_error?, system_error?, final? methods
4. Response model: error_type, error_message fields

### Phase 3: integrator - Retry Level 1

1. Add MAX_ATTEMPTS configuration (environment variable)
2. Count retry attempts per request
3. Stop retrying after MAX_ATTEMPTS
4. Mark final system errors for report

### Phase 4: integrator - Three Outcomes in Report

1. Update StatisticAggregator to count three buckets
2. Update Job model with three quantity fields
3. Update ApiReportWorkBook with System Errors sheet
4. Update email template with three categories

### Phase 5: integrator - Job State Machine & Inheritance (REVISED)

Add proper state machine to Job model and implement STI for job types.

#### Class Hierarchy

```ruby
class Job
  # Abstract base class
  TYPES = %w[IntegrationJob RecoveryJob].freeze
  validates :_type, inclusion: { in: TYPES }
  # Common fields, associations, and behaviors
end

class IntegrationJob < Job
  # Full ETL process
  # States: initial → extracting → transforming → loading → final
end

class RecoveryJob < Job
  belongs_to :integration_job, class_name: 'IntegrationJob'
  # Load-only process for pending records
  # States: initial → loading → final
end
```

#### State Machine - IntegrationJob

```
initial → extracting → transforming → loading → final
```

| State | Meaning | Timestamp Set |
|-------|---------|---------------|
| `initial` | Job created, waiting to start | `starts_at` |
| `extracting` | Fetching data from source | - |
| `transforming` | Processing/normalizing data | `fetch_ends_at` |
| `loading` | Sending to API | `transformation_ends_at` |
| `final` | Completed | `ends_at` |

#### State Machine - RecoveryJob

```
initial → loading → final
```

| State | Meaning | Timestamp Set |
|-------|---------|---------------|
| `initial` | Job created | `starts_at` |
| `loading` | Reprocessing pending records | - |
| `final` | Completed | `ends_at` |

#### Migration Strategy

Based on production data analysis (2214 jobs):

```ruby
# All existing jobs become IntegrationJob
Mongoid.default_client[:jobs].update_many(
  {},
  { '$set' => { '_type' => 'IntegrationJob' } }
)

# Set status based on timestamps
# Has ends_at → final
Mongoid.default_client[:jobs].update_many(
  { ends_at: { '$ne' => nil } },
  { '$set' => { 'status' => 4 } }  # final
)

# Has transformation_ends_at, no ends_at → loading
Mongoid.default_client[:jobs].update_many(
  { transformation_ends_at: { '$ne' => nil }, ends_at: nil },
  { '$set' => { 'status' => 3 } }  # loading
)

# Has fetch_ends_at, no transformation_ends_at → transforming
Mongoid.default_client[:jobs].update_many(
  { fetch_ends_at: { '$ne' => nil }, transformation_ends_at: nil },
  { '$set' => { 'status' => 2 } }  # transforming
)

# Has starts_at, no fetch_ends_at → extracting
Mongoid.default_client[:jobs].update_many(
  { starts_at: { '$ne' => nil }, fetch_ends_at: nil },
  { '$set' => { 'status' => 1 } }  # extracting
)
```

#### Implementation Tasks

1. Create `IntegrationJob` class inheriting from `Job`
2. Create `RecoveryJob` class inheriting from `Job`
3. Add `TYPES` constant and validation to `Job`
4. Add `status` field with enumerize to both classes
5. Implement state machines with `state_machines-mongoid`
6. Add `parent_job_id` field to `RecoveryJob` (references IntegrationJob)
7. Add index on `{ _type: 1, status: 1 }`
8. Create migration to set `_type` and `status` for existing jobs
9. Update `DatabaseIntegrator` and `ApiIntegrator` to use `IntegrationJob`
10. Update workers to use state machine events instead of direct timestamp updates
11. Update `bin/draw_state_machines` to accept class parameter
12. Generate state machine diagrams for documentation

### Phase 6: integrator - Operation Model

Add Operation model between Import and Request to track business operations separately from HTTP calls.

#### Operation Model

```ruby
class Operation
  embedded_in :import
  embeds_many :requests

  field :name, type: String        # "create", "update", "activate", etc.
  field :status, type: Integer     # 0 = pending, 1 = executed
  field :primary, type: Boolean    # true = determines resource integration

  enumerize :status, in: { pending: 0, executed: 1 }, default: :pending
end
```

#### Operation Status

| Status | Meaning |
|--------|---------|
| `pending` | Not executed yet (will be retried by RecoveryJob) |
| `executed` | Executed (regardless of HTTP response) |

**Key insight:**
- Operation status is about execution, not success/failure.
- An Operation is "executed" when it received ANY HTTP response (2xx, 4xx, 5xx).
- An Operation stays "pending" if it never got a response (timeout, connection refused).
- RecoveryJob looks for Operations with status = pending.

#### Request Model (simplified)

Request becomes a pure log entry:
- Remove status tracking from Request
- Request just records: url, method, body, timestamp, response (if any), error (if any)
- Multiple Requests can exist per Operation (retry history)

#### Primary vs Secondary Operations

| Resource | Operations | Primary |
|----------|------------|---------|
| User (with external ID) | create, create_identifier, select_primary | create |
| User (without external ID) | create | create |
| Deal | create/update, activate/deactivate | create/update |
| Client | create/update, activate/deactivate | create/update |
| ... | ... | ... |

**Rule:** Resource is marked "integrated" after PRIMARY operation is executed with success response.
Secondary operations are best-effort and don't block integration.

#### Migration Strategy

For existing data:
1. Create Operation for each Request with `name` derived from http_method + url pattern
2. Set `status: executed` if Request has response with 2xx/4xx status
3. Set `status: pending` if Request has no response or has 5xx/error_type
4. Set `primary: true` for create/update operations

#### Implementation Tasks

1. Create Operation model with status enumerize
2. Update Import to embed Operations instead of Requests directly
3. Update Request to be embedded in Operation
4. Update ApplicationLoader to create Operation before Request
5. Update LoaderConsumers to mark Operation as executed on success
6. Update StatisticAggregator to count by Operation status
7. Create migration for existing data
8. Analyze each resource to identify primary vs secondary operations
9. Update integration logic: mark resource integrated after PRIMARY operation succeeds

### Phase 7: integrator - Recovery Job Pipeline

RecoveryJob reprocesses Operations that remained pending after IntegrationJob.

#### The Approach

Unlike IntegrationJob (which creates new Imports), RecoveryJob reuses existing Imports and Operations:
- Find all Operations with `status: pending` from the IntegrationJob
- Execute them again (creating new Requests in each Operation)
- Mark as executed when successful

#### Recovery Flow

```
IntegrationJob finishes with pending Operations
    ↓
Job::Finisher
    - Counts pending Operations
    - If any pending: schedules RecoveryJob
    ↓
RecoveryJob::Starter
    - Creates RecoveryJob linked to IntegrationJob
    - Calls recovery_job.start_loading!
    - Queries Operations with status: pending from IntegrationJob
    - Enqueues LoaderConsumers for each
    ↓
LoaderConsumers (existing - reused)
    - Same logic as IntegrationJob
    - Creates new Request in the pending Operation
    - Marks Operation as executed on success
    ↓
RecoveryJob::Finisher
    - Counts results
    - Sends recovery report email
    - Does NOT schedule another RecoveryJob (prevents loop)
```

#### Implementation Tasks

1. Create `RecoveryJob::Starter` worker
2. Create `RecoveryJob::Finisher` worker
3. Query: Operations with `status: pending` from IntegrationJob
4. Reuse existing LoaderConsumers (they already handle Operations)
5. Create recovery report email template

### Phase 8: integrator - Automatic Recovery Trigger

1. Job::Finisher checks for pending Operations after IntegrationJob completes
2. If pending Operations exist: schedule RecoveryJob::Starter after `recovery_job_delay`
3. RecoveryJob::Finisher does NOT schedule another recovery (prevents loop)
4. Different email template for recovery results

## Files to Modify

### Models

| File | Changes |
|------|---------|
| `app/models/operation.rb` (NEW) | Business operation with status (pending/executed) |
| `app/models/import.rb` | Embed Operations instead of Requests directly |
| `app/models/request.rb` | Embedded in Operation, pure log (remove status logic) |
| `app/models/response.rb` | Keep as is (embedded in Request) |
| `app/models/job.rb` | Add type field, quantity fields |
| `app/models/resource/statistic_aggregator.rb` | Count by Operation status |

### Loaders

| File | Changes |
|------|---------|
| `app/loaders/application_loader.rb` | Create Operation before Request, return LoadingResult |
| `app/loaders/*.rb` (19 files) | Use idempotency headers, work with Operations |

### Workers

| File | Changes |
|------|---------|
| `app/workers/*/loader_consumer.rb` (25 files) | Mark Operation as executed, handle primary vs secondary |
| `app/workers/job/finisher.rb` | Check for pending Operations, schedule RecoveryJob |
| `app/workers/recovery_job/starter.rb` (NEW) | Start RecoveryJob, find pending Operations |
| `app/workers/recovery_job/finisher.rb` (NEW) | Finish RecoveryJob, send report |

### Reports

| File | Changes |
|------|---------|
| `app/work_books/api_report_work_book.rb` | Add System Errors sheet |
| `app/views/integration_report_mailer/create.html.erb` | Three categories, retry notice |
| `app/mailers/retry_report_mailer.rb` (NEW) | Retry results email |

### Configuration

| File | Changes |
|------|---------|
| Environment variables | MAX_ATTEMPTS, RETRY_DELAY |

## Success Criteria

1. System errors are retried immediately (up to MAX_ATTEMPTS)
2. If still pending, automatic Recovery Job runs after delay
3. User receives clear notification about retry
4. Report separates user errors from system errors (pending Operations)
5. Idempotency keys prevent duplicate data on retry
6. Complete history preserved (multiple Requests per Operation)
7. Operations clearly separated from Requests (business vs HTTP)
8. Resource integration determined by PRIMARY operation, not all operations
9. Secondary operations are best-effort (don't block integration)

## Documentation

- `docs/architecture/LOADING.md` - Process documentation
- `docs/architecture/ETL.md` - Overall ETL architecture

---

**Status:** IN PROGRESS

**Completed Phases:**
- Phase 1: app - Idempotency support ✅
- Phase 2: integrator - Foundation (LoadingResult, ApplicationLoader) ✅
- Phase 3: integrator - Retry Level 1 (MAX_ATTEMPTS) ✅
- Phase 4: integrator - Three Outcomes in Report ✅
- Phase 5: integrator - Job State Machine & STI ✅

**Current Phase:**
- Phase 6: integrator - Operation Model (in progress)
