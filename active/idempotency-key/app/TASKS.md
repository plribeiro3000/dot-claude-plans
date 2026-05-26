# NEXT TASKS — app Idempotency Key — Reconstruct Response Pattern

> **Objective of this iteration:** Implement X-Idempotency-Key header support returning same response on retry (Stripe pattern).
> **Reference:** derived from `../PLAN.md`.

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved** (Reconstruct Response Pattern)
- [x] **Base branch:** `develop` • **Working branch:** `feature/idempotency-key` (PR #4597 open)

---

## 1) Step by Step (atomic tasks)

### Task 1 — Update cache_key to include controller and action
- **Objective:** Prevent collision when same idempotency key is used on different endpoints
- **Actions (checklist):**
  - [ ] Update `cache_key` method to include `controller_name` and `action_name`
  - [ ] Format: `api:#{MD5(company_id:controller_name:action_name:idempotency_key)}`
- **Affected files/areas:** `app/controllers/api_controller.rb`
- **Completion criteria:** Same key on different endpoints generates different cache keys
- **Status:** PENDING

### Task 2 — Add cached_resource_id method
- **Objective:** Allow controllers to retrieve the cached resource ID
- **Actions (checklist):**
  - [ ] Add `cached_resource_id` method that reads from cache
  - [ ] Update `cached?` to use `cached_resource_id.present?`
- **Affected files/areas:** `app/controllers/api_controller.rb`
- **Completion criteria:** Method returns ID (for CREATE) or true (for UPDATE/DELETE)
- **Status:** PENDING

### Task 3 — Update cache! to accept resource or boolean
- **Objective:** Store resource ID for CREATE, boolean for UPDATE/DELETE
- **Actions (checklist):**
  - [ ] Update `cache!` to accept resource object or `true`
  - [ ] Store `resource.id` when resource passed, `true` when boolean passed
- **Affected files/areas:** `app/controllers/api_controller.rb`
- **Completion criteria:** Cache stores appropriate value based on input
- **Status:** PENDING

### Task 4 — Update CREATE controllers
- **Objective:** Reconstruct response on retry for CREATE actions
- **Actions (checklist):**
  - [ ] On retry: fetch resource by `cached_resource_id`, render with :created
  - [ ] On success: call `cache!(resource)` after render
  - [ ] Update all 36 controllers with CREATE actions
- **Affected files/areas:** `app/controllers/api/v3/*.rb`
- **Completion criteria:** CREATE retry returns 201 + serialized resource
- **Status:** PENDING

### Task 5 — Update UPDATE/DELETE controllers
- **Objective:** Return 204 on retry for UPDATE/DELETE actions
- **Actions (checklist):**
  - [ ] On retry: `head :no_content` and return
  - [ ] On success: call `cache!(true)` after head
  - [ ] Update all 36 controllers with UPDATE/DELETE actions
- **Affected files/areas:** `app/controllers/api/v3/*.rb`
- **Completion criteria:** UPDATE/DELETE retry returns 204
- **Status:** PENDING

### Task 6 — Update Swagger documentation
- **Objective:** Document X-Idempotency-Key header behavior
- **Actions (checklist):**
  - [x] Add header parameter to all create/update/delete operations
  - [x] Document that successful responses are cached for 1 hour
  - [ ] Update documentation to reflect same-response-on-retry behavior
- **Affected files/areas:** `app/controllers/api/v3/*.rb` (swagger blocks)
- **Completion criteria:** All endpoints document the header correctly
- **Status:** MOSTLY COMPLETE

### Task 7 — Update request specs
- **Objective:** Test idempotency behavior returns same response
- **Actions (checklist):**
  - [ ] CREATE specs: verify retry returns 201 + same body
  - [ ] UPDATE/DELETE specs: verify retry returns 204
  - [ ] Update all 36 spec files
- **Affected files/areas:** `spec/requests/api/v3/*.rb`
- **Completion criteria:** All specs pass with correct expectations
- **Status:** PENDING (current specs expect :no_content for all)

### Task 8 — Update CHANGELOG
- **Objective:** Document the feature for end users
- **Actions (checklist):**
  - [x] Add entry under version 2.216.2
  - [ ] Update description to reflect final behavior
- **Affected files/areas:** `CHANGELOG.md`
- **Completion criteria:** Entry explains value to API consumers
- **Status:** NEEDS UPDATE

### Task 9 — Run validations
- **Objective:** Ensure all tests pass and code is clean
- **Actions (checklist):**
  - [ ] Run full RSpec test suite
  - [ ] Run Rubocop
  - [ ] Run Brakeman
- **Affected files/areas:** N/A
- **Completion criteria:** All validations pass
- **Status:** PENDING

---

## 2) Items Requiring User Confirmation

- [x] **Response on retry:** Same as original (201 + body for CREATE, 204 for UPDATE/DELETE)
- [x] **Cache storage:** Resource ID for CREATE, boolean for UPDATE/DELETE
- [x] **Cache key format:** `api:#{MD5(company_id:controller:action:idempotency_key)}`
- [x] **Cache TTL:** 1 hour

---

## 3) Pending Items After This Iteration

- [ ] Update PR #4597 with all changes
- [ ] Request code review
- [ ] Deploy to staging for testing
