# TASKS — Loading Resilience & Idempotency (integrator)

> **Reference:** `../PLAN.md` and `BLUEPRINT.md`

---

## Phase 1: app - Idempotency Support

**Status:** ✅ DONE (deployed)

- [x] X-Idempotency-Key header support in API

---

## Phase 2: integrator - Foundation

**Status:** ✅ DONE

### Task 2.1 — Request model error fields
- [x] Add `error_type` field (String)
- [x] Add `error_message` field (String)
- [x] Add `error?` helper method
- [x] Add `success?`, `user_error?`, `final?` methods
- **Files:** `app/models/request.rb`

### Task 2.2 — LoadingResult value object
- [x] Create LoadingResult class
- [x] Implement `success?` method
- [x] Implement `retriable?` method
- [x] Implement `failed?` method
- **Files:** `app/models/loading_result.rb`

### Task 2.3 — ApplicationLoader with idempotency
- [x] Add X-Idempotency-Key header to all HTTP calls
- [x] Add RETRIABLE_EXCEPTIONS constant
- [x] Create `post`, `put`, `delete` methods returning LoadingResult
- [x] Handle exceptions and update Request with error info
- **Files:** `app/loaders/application_loader.rb`

### Task 2.4 — Service objects for request/response
- [x] `Request::Creator` - creates pending request before HTTP call
- [x] `Request::Updater` - updates request with error on exception
- [x] `Response::Creator` - creates response with status + body
- [x] `Response::ServerErrorCreator` - creates response with status only (5xx)
- **Files:** `app/services/request/*.rb`, `app/services/response/*.rb`

### Task 2.5 — Update all loaders to use ApplicationLoader
- [x] All 19 loaders use `post`, `put`, `delete` methods
- [x] All loaders return LoadingResult
- **Files:** `app/loaders/*.rb`

### Task 2.6 — Update all workers to use LoadingResult
- [x] All 25 workers check `result.retriable?`
- [x] All workers use `ApplicationConfiguration.api_retry_delay`
- [x] No rescue blocks for HTTP exceptions in workers
- **Files:** `app/workers/*/loader_consumer.rb`

---

## Phase 3: integrator - Retry Level 1 (MAX_ATTEMPTS)

**Status:** ✅ DONE

### Task 3.1 — MAX_ATTEMPTS configuration
- [x] Add `api_request_threshold` to ApplicationConfiguration
- [x] Environment variable configured

### Task 3.2 — Error counting per request
- [x] Add `error_count` parameter to LoadingResult
- [x] LoadingResult tracks attempt count
- [x] `Request::ErrorCounter` service counts errors by URL/method

### Task 3.3 — Stop retrying after MAX_ATTEMPTS
- [x] All loaders check `error_count >= api_request_threshold` before HTTP call
- [x] `retriable?` returns `false` when threshold reached
- [x] `failed?` returns `true` when threshold reached

---

## Phase 4: integrator - Three Outcomes in Report

**Status:** ❌ NOT STARTED

### Task 4.1 — Update StatisticAggregator
- [ ] Count three buckets: success, user_error, system_error
- [ ] System error = requests where `error_type` present OR response status >= 500
- **Files:** `app/models/resource/statistic_aggregator.rb`

### Task 4.2 — Update Job model
- [ ] Add `system_errors_count` field
- [ ] Update after integration completes
- **Files:** `app/models/job.rb`

### Task 4.3 — Add System Errors sheet to report
- [ ] New sheet in ApiReportWorkBook
- [ ] Columns: Resource ID, Error Type, Error Message, Timestamp
- [ ] Show all requests with system errors
- **Files:** `app/work_books/api_report_work_book.rb`

### Task 4.4 — Update email template
- [ ] Show three categories: Success, Validation Errors, System Errors
- [ ] Add message: "Automatic retry scheduled for [time]" when system errors exist
- **Files:** `app/views/integration_report_mailer/create.html.erb`

---

## Phase 5: integrator - Job Types

**Status:** ❌ NOT STARTED

### Task 5.1 — Add type field to Job
- [ ] Add `job_type` field (String): 'integration' or 'retry'
- [ ] Default to 'integration' for existing jobs
- **Files:** `app/models/job.rb`

### Task 5.2 — Filter by job type
- [ ] Update queries to filter by job_type when needed
- [ ] Retry Job only queries records with system errors from last integration

---

## Phase 6: integrator - Automatic Retry Job (2 hours)

**Status:** ❌ NOT STARTED

### Task 6.1 — RETRY_DELAY configuration
- [ ] Add `api_retry_delay_hours` to ApplicationConfiguration (default: 2 hours)
- [ ] Add environment variable

### Task 6.2 — Schedule Retry Job after integration
- [ ] In Job::Finisher: check if system errors exist
- [ ] If yes: schedule RetryJob for `api_retry_delay_hours` later
- **Files:** `app/workers/job/finisher.rb`

### Task 6.3 — Create Retry Job workers
- [ ] `RetryJob::Producer` - finds records with system errors
- [ ] `RetryJob::Consumer` - processes only system error records
- [ ] Single retry attempt (no loop)
- **Files:** `app/workers/retry_job/*.rb` (NEW)

### Task 6.4 — Retry Job email templates
- [ ] Success template: "All system errors were successfully resolved"
- [ ] Partial failure template: "Recovered: X, Still failing: Y"
- [ ] Include "Please contact 4Shark team" when errors persist
- **Files:** `app/mailers/retry_report_mailer.rb` (NEW), `app/views/retry_report_mailer/*.html.erb` (NEW)

---

## Phase 7: Testing & Documentation

**Status:** ❌ NOT STARTED

### Task 7.1 — Tests
- [ ] Test LoadingResult with error_count threshold
- [ ] Test StatisticAggregator three buckets
- [ ] Test ApiReportWorkBook System Errors sheet
- [ ] Test RetryJob scheduling
- [ ] Test email templates

### Task 7.2 — Update CHANGELOG
- [ ] Entry explaining system error visibility
- [ ] Entry explaining automatic retry after 2 hours
- [ ] Entry explaining new report sheet

---

## Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | app - Idempotency header | ✅ DONE |
| 2 | integrator - Foundation | ✅ DONE |
| 3 | integrator - MAX_ATTEMPTS | ✅ DONE |
| 4 | integrator - Report (3 outcomes) | ❌ NOT STARTED |
| 5 | integrator - Job Types | ❌ NOT STARTED |
| 6 | integrator - Automatic Retry (2h) | ❌ NOT STARTED |
| 7 | Testing & Documentation | ❌ NOT STARTED |
