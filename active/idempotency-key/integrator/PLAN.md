# DEPLOY PLAN — Loading Resilience & Idempotency

**Version:** 1.0
**Branch:** idempotency
**Target:** develop → staging → production

---

## Pre-Deploy Checklist

- [ ] All tests passing
- [ ] Rubocop clean
- [ ] PR approved
- [ ] CHANGELOG.md updated

---

## What's Included in This Deploy

### Features Implemented

| Commit | Description |
|--------|-------------|
| `6f17f6e2` | API request idempotency support (X-Idempotency-Key header) |
| `c69eb547` | LoadingResult pattern with retry logic |
| `1953d747` | Three outcome buckets (success, invalid, pending) |
| `1cef859c` | Job STI (IntegrationJob, RecoveryJob) |
| `e9d4b4b9` | Fix job_id type (String → BSON::ObjectId) |

### Database Migrations

| Migration | Purpose | Reversible |
|-----------|---------|------------|
| `20251203164827_add_invalid_requests_quantity_to_jobs.rb` | Add invalid_requests_quantity field | Yes |
| `20251203164828_add_pending_requests_quantity_to_jobs.rb` | Add pending_requests_quantity field | Yes |
| `20251203164829_add_type_to_jobs.rb` | Set _type = IntegrationJob for all existing jobs | Yes |
| `20251203164830_add_status_to_jobs.rb` | Set status based on timestamps for existing jobs | Yes |

### New Workers

| Worker | Purpose | When to Run |
|--------|---------|-------------|
| `Request::Migration::Producer` | Starts job_id migration from String to BSON::ObjectId | **After deploy - manual** |
| `Request::Migration::JobConsumer` | Processes each job | Called by Producer |
| `Request::Migration::ResourceConsumer` | Updates each resource | Called by JobConsumer |

---

## Deploy Steps

### Step 1: Deploy Code

```bash
# Standard deploy process
cap staging deploy
# or
cap production deploy
```

### Step 2: Run Migrations

Migrations run automatically via Capistrano, but verify:

```bash
# SSH to server
RAILS_ENV=production bundle exec rake db:migrate:status
```

Expected output:
```
   up     20251203164827  Add invalid requests quantity to jobs
   up     20251203164828  Add pending requests quantity to jobs
   up     20251203164829  Add type to jobs
   up     20251203164830  Add status to jobs
```

### Step 3: Verify Migrations Ran Correctly

```javascript
// MongoDB shell - check jobs have _type and status
db.jobs.findOne({}, { _type: 1, status: 1 })

// Should return something like:
// { _id: ObjectId(...), _type: "IntegrationJob", status: 4 }

// Count jobs by type
db.jobs.aggregate([
  { $group: { _id: "$_type", count: { $sum: 1 } } }
])

// Count jobs by status
db.jobs.aggregate([
  { $group: { _id: "$status", count: { $sum: 1 } } }
])
```

### Step 4: Run job_id Migration (MANUAL)

**Important:** This migrates job_id from String to BSON::ObjectId for requests created after 2025-10-03.

```ruby
# Rails console
Request::Migration::Producer.perform_async
```

**Monitoring:**

```ruby
# Check progress
computation = Computation.new('request_migration')
puts "Queue: #{computation.queue}"
puts "Executions: #{computation.executions}"
puts "Done: #{computation.done?}"
```

**Duration:** Depends on number of jobs since 2025-10-03. Each job is processed sequentially.

---

## Post-Deploy Verification

### 1. Check Jobs Are Working

Run a test integration and verify:

- [ ] Job is created with `_type: "IntegrationJob"`
- [ ] Job status transitions correctly (initial → extracting → ... → final)
- [ ] Report shows three buckets (success, invalid, pending)

### 2. Check Idempotency Headers

```ruby
# Verify idempotency keys are being sent
# Check request logs for X-Idempotency-Key header
```

### 3. Check job_id Migration Progress

```javascript
// Count resources with String job_id (should decrease to 0)
db.resources.aggregate([
  { $unwind: "$imports" },
  { $unwind: "$imports.requests" },
  { $match: { "imports.requests.job_id": { $type: "string" } } },
  { $count: "string_job_ids" }
])

// Count resources with ObjectId job_id (should be all)
db.resources.aggregate([
  { $unwind: "$imports" },
  { $unwind: "$imports.requests" },
  { $match: { "imports.requests.job_id": { $type: "objectId" } } },
  { $count: "objectid_job_ids" }
])
```

---

## Rollback Plan

### If Issues After Deploy

1. **Code rollback:**
   ```bash
   cap production deploy:rollback
   ```

2. **Migration rollback (if needed):**
   ```bash
   RAILS_ENV=production bundle exec rake db:rollback STEP=4
   ```

3. **job_id migration:** Cannot be easily rolled back. If needed, run inverse update:
   ```javascript
   // This is destructive - only if absolutely needed
   db.resources.updateMany(
     {},
     [{ $set: {
       "imports.$[].requests.$[].job_id": {
         $toString: "$imports.$[].requests.$[].job_id"
       }
     }}]
   )
   ```

---

## Environment Variables (No Changes)

No new environment variables required for this deploy.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| job_id migration takes too long | Low | Runs in background, doesn't block operations |
| Old jobs don't have status | Medium | Migration sets status based on timestamps |
| STI breaks existing code | High | All existing code works with IntegrationJob |

---

## Notes

- The job_id migration only affects requests created after 2025-10-03 (commit f19c7b1a)
- New jobs will automatically use BSON::ObjectId for job_id
- StatisticAggregator already handles BSON::ObjectId correctly

---

**Status:** DRAFT
**Last Updated:** 2025-12-05
