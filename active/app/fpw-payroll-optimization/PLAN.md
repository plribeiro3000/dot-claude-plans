# FPW Payroll Integration - Optimization with Redis Cache + S3 Buffer

## Metadata
- **Project**: app
- **Status**: 🟡 In Progress
- **Start Date**: 2025-11-18
- **Last Updated**: 2025-11-21
- **Current Phase**: 1 of 6

---

## Problem Context

The application runs in São Paulo (close to the client), but the PostgreSQL database is in North Virginia. This causes ~100-150ms latency per query.

### Solution

Use **Redis as read cache** and **S3 as write buffer**, syncing with PostgreSQL only at the end.

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Client API    │ ←── │  Workers (SP)    │ ──→ │   S3 Bucket     │
│   (São Paulo)   │     │        ↓↑        │     │   (São Paulo)   │
└─────────────────┘     │   Redis Cache    │     └────────┬────────┘
       ~1ms             │   (São Paulo)    │              │
                        └──────────────────┘              │ Sync (Finalizer)
                               ~1-5ms                     ↓
                                                ┌─────────────────┐
                                                │  PostgreSQL     │
                                                │  (N. Virginia)  │
                                                └─────────────────┘
```

### Benefits

1. **Fast reads** - Local Redis eliminates queries to PostgreSQL
2. **Persistent writes** - S3 is durable (99.999999999%)
3. **Idempotency** - S3 check ensures API isn't called twice
4. **Client configurable** - bucket comes from PayrollIntegration
5. **Safe fallback** - if Redis has no data, fetches from PostgreSQL
6. **Efficient sync** - bulk insert/update at the end

---

## Time Analysis - 50K Records

### Reference Latencies

| Component | Location | Latency |
|-----------|----------|---------|
| Redis | São Paulo | ~1ms |
| S3 | São Paulo | ~7ms |
| PostgreSQL | North Virginia | ~125ms |
| FPW API (Check) | Client | ~2,500ms |
| FPW API (Execute) | Client | ~3,000ms |

### Overhead per Consumer

#### Current System
- 9 PostgreSQL queries: ~1,125ms

#### With Redis + S3 + Parameters
- 2 Redis reads + 1 increment + 1 S3 write: ~10ms
- **Zero PostgreSQL queries**

### Our Side Time (150K consumers)

| System | Overhead per consumer | 10 workers | 25 workers | 50 workers |
|--------|----------------------|------------|------------|------------|
| **Current** | 1,125ms | 4h41min | 1h52min | 56min |
| **Optimized** | 10ms | 2.5min | 1min | 30sec |

### Total Time (including API)

| Workers | API Time | Our Overhead | Total |
|---------|----------|--------------|-------|
| 10 | 11.1h | 2.5min | ~11.1h |
| 25 | 4.4h | 1min | ~4.4h |
| 50 | 2.2h | 30sec | ~2.2h |

---

## Implementation Phases

### Phase 1: Create DataCache for Redis

**Status**: [ ] Not started

**Objective**: Create class for structured data caching using `Rails.cache`, following the ApplicationRecord pattern.

**Class**:
```ruby
# app/models/fpw_integration/data_cache.rb
class FpwIntegration::DataCache
  CACHE_TTL = 12.hours

  def initialize(payment_id)
    @payment_id = payment_id
  end

  # Main cache with all shared data
  def store_shared_data(data)
    Rails.cache.write(
      shared_cache_key,
      data.to_json,
      expires_in: CACHE_TTL
    )
  end

  def get_shared_data
    data = Rails.cache.read(shared_cache_key)
    return nil unless data

    JSON.parse(data, symbolize_names: true)
  end

  # Individual cache per user_payment (for specific data)
  def store_user_payment_data(user_payment_id, data)
    Rails.cache.write(
      user_payment_cache_key(user_payment_id),
      data.to_json,
      expires_in: CACHE_TTL
    )
  end

  def get_user_payment_data(user_payment_id)
    data = Rails.cache.read(user_payment_cache_key(user_payment_id))
    return nil unless data

    JSON.parse(data, symbolize_names: true)
  end

  def exists?
    Rails.cache.exist?(shared_cache_key)
  end

  def delete
    # Delete shared cache
    Rails.cache.delete(shared_cache_key)

    # Delete individual caches using pattern matching
    Rails.cache.delete_matched("fpw_cache:#{@payment_id}:up:*")
  end

  private

  def shared_cache_key
    "fpw_cache:#{@payment_id}:shared"
  end

  def user_payment_cache_key(user_payment_id)
    "fpw_cache:#{@payment_id}:up:#{user_payment_id}"
  end
end
```

**Shared cache structure**:
```ruby
{
  payroll_integration: {
    id: 1,
    hostname: '...',
    user_name: '...',
    user_password: '...',
    # ... other fields
  },
  payment: {
    id: 123,
    reference_month: '2025-01-01'
  },
  company_id: 456
}
```

**Per user_payment cache structure**:
```ruby
{
  id: 789,
  user_id: 111,
  payment_type_external_id: 'EVT001',
  billable_money: 1500.00,
  user_numeric_identifier: 12345
}
```

**Tasks**:
- [ ] Create FpwIntegration::DataCache
- [ ] Implement store/get for shared data
- [ ] Implement store/get for per user_payment data
- [ ] Use Rails.cache (consistent with ApplicationRecord)
- [ ] Add 12-hour TTL
- [ ] Test with real data

---

### Phase 2: Modify Producers to Populate Cache and Pass Parameters

**Status**: [ ] Not started

**Affected files**:
- `app/workers/fpw_integration/check_producer.rb`
- `app/workers/fpw_integration/execute_producer.rb`
- `app/workers/fpw_integration/validate_producer.rb`

**Objective**:
- CheckProducer: Load all data and populate cache
- All: Pass [user_payment_id, payment_id, pending] as arguments

**Tasks**:
- [ ] Modify CheckProducer to populate cache
- [ ] Modify all Producers to pass extra parameters
- [ ] Load updated status in Execute/Validate Producers

---

### Phase 3: Add S3 Configuration to PayrollIntegration

**Status**: [ ] Not started

**Objective**: Add fields for S3 bucket configuration per client.

**Migration**:
```ruby
class AddS3ConfigToPayrollIntegrations < ActiveRecord::Migration[7.0]
  def change
    add_column :payroll_integrations, :s3_buffer_enabled, :boolean, default: false
    add_column :payroll_integrations, :s3_buffer_bucket, :string
    add_column :payroll_integrations, :s3_buffer_region, :string
    add_column :payroll_integrations, :s3_buffer_access_key_id, :string
    add_column :payroll_integrations, :s3_buffer_secret_access_key, :string
  end
end
```

**Tasks**:
- [ ] Create migration to add fields
- [ ] Add validations to PayrollIntegration model
- [ ] Encrypt S3 credentials (secret_access_key)

---

### Phase 4: Create Service for S3 Operations

**Status**: [ ] Not started

**Objective**: Create service to abstract S3 read/write operations.

**S3 file structure**:
```
bucket/
  └── payments/
      └── {payment_id}/
          └── payroll_requests/
              ├── {user_payment_id}_check.json
              ├── {user_payment_id}_execution.json
              └── {user_payment_id}_validation.json
```

**Tasks**:
- [ ] Create FpwIntegration::S3BufferService
- [ ] Implement save_payroll_request
- [ ] Implement object_exists? for idempotency
- [ ] Implement load_all_payroll_requests
- [ ] Implement delete_payment_data
- [ ] Add error handling and retries

---

### Phase 5: Modify Consumers to Use Redis + S3

**Status**: [ ] Not started

**Affected files**:
- `app/workers/fpw_integration/check_consumer.rb`
- `app/workers/fpw_integration/execute_consumer.rb`
- `app/workers/fpw_integration/validate_consumer.rb`

**Objective**:
- Receive parameters [user_payment_id, payment_id, pending]
- Read data from Redis cache
- Save results to S3
- Use Computation directly without query

**Tasks**:
- [ ] Modify perform signature to receive extra parameters
- [ ] Read from cache instead of PostgreSQL queries
- [ ] Save to S3 instead of PostgreSQL
- [ ] Use Computation.new("payment:#{payment_id}") directly
- [ ] Implement idempotency check
- [ ] Keep fallback to PostgreSQL when cache doesn't exist

---

### Phase 6: Modify Finalizer for S3 → PostgreSQL Sync

**Status**: [ ] Not started

**Affected file**:
- `app/workers/fpw_integration/finalizer.rb`

**Objective**: Load data from S3, bulk insert to PostgreSQL, cleanup S3 and Redis.

**Tasks**:
- [ ] Implement S3 to PostgreSQL sync (upsert_all)
- [ ] Implement UserPayment status update (update_all)
- [ ] Delete Redis cache after sync
- [ ] Delete S3 data after sync
- [ ] Add error handling

---

## Data Structures

### Redis Cache

**Shared key**: `fpw_cache:{payment_id}:shared`
**Individual key**: `fpw_cache:{payment_id}:up:{user_payment_id}`

### S3 PayrollRequest JSON

```json
{
  "user_payment_id": 12345,
  "action": "check",
  "status": "success",
  "request_body": "<xml>...</xml>",
  "request_headers": {"Content-Type": "..."},
  "response_body": "<xml>...</xml>",
  "duration": 2.5,
  "balance": 1500.00,
  "timeout_quantity": 0
}
```

---

## Technical Patterns

### Sidekiq Parameter Passing

```ruby
arguments = user_payments.map { |up| [up.id, payment_id, up.pending?] }
Consumer.dynamic_push_bulk('args' => arguments)
```

### Computation Without Query

```ruby
Computation.new("payment:#{payment_id}").increment_executions
```

### Idempotency via S3

```ruby
if s3_service.object_exists?(payment_id, user_payment_id, :check)
  return # Already processed
end
```

---

## Test Checklist

- [ ] Test Redis cache populated correctly
- [ ] Test fallback to PostgreSQL when cache doesn't exist
- [ ] Test idempotency (object_exists? on S3)
- [ ] Test with s3_buffer_enabled = true
- [ ] Test with s3_buffer_enabled = false (full fallback)
- [ ] Test sync with many records (50K)
- [ ] Test Redis and S3 cleanup after sync
- [ ] Test failure scenario mid-processing
- [ ] Verify Redis TTL (12 hours)

---

## Security Considerations

1. **S3 Credentials**: Use encryption at rest in database for secret_access_key
2. **Redis**: Sensitive data (user_password) in cache - ensure Redis is not externally accessible
3. **Bucket policy**: Restrict access to configured credentials only
4. **TTL**: Redis expires in 12h, S3 deleted after sync

---

## S3 Costs (estimate)

- PUT requests: $0.005 per 1,000
- Storage: $0.023 per GB/month
- 50K requests × 3 phases = 150K PUTs = $0.75
- Temporary data, deleted after sync

---

## Change History

| Date | Phase | Status | Notes |
|------|-------|--------|-------|
| 2025-11-18 | Planning | Completed | Initial document - S3 approach |
| 2025-11-19 | Planning | Updated | Added Redis Cache + Sidekiq parameters |
| 2026-01-06 | Documentation | Updated | Translated to English |
