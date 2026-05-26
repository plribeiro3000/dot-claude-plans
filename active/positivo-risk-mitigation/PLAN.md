# PLAN - Positivo Risk Mitigation

> Reference: `~/.claude/plans/active/content/vendor-assessment-positivo/DISPOSITION-v2.md`

## Objective

Implement all 7 mitigations required by Positivo Tecnologia's vendor security assessment within agreed deadlines. The bulk of development work is Item 1 (Security Events API). Items 3+5+6 are Terraform activations. Items 2, 4 (partial), and 7 are documentation or configuration.

## Deadlines

| Item | Description | Risk | Deadline from assessment date (2026-04-08) |
|------|-------------|------|--------------------------------------------|
| 2 | User Identifier + HR Integration | ALTO | 60 days → 2026-06-07 |
| 3 | Hardening (CIS via Security Hub) | MÉDIO | 90 days → 2026-07-07 |
| 4 | DLP (Macie + Google Workspace) | MÉDIO | 90 days → 2026-07-07 |
| 5 | SIEM / Event Correlation (GuardDuty) | MÉDIO | 90 days → 2026-07-07 |
| 6 | SOC Procedures | MÉDIO | 90 days → 2026-07-07 |
| 1 | Security Events API | BAIXO | 120 days → 2026-08-06 |
| 7 | Internal Audit | BAIXO | 120 days → 2026-08-06 |

## Scope

### In Scope

- Security Events API (REST endpoint, authenticated via CompanyToken, per-company opt-in)
- Event capture at all 3 authentication entry points: `SessionsController`, `Authentication::SessionsController`, Devise web
- Event capture for user lifecycle actions: disable, reactivate
- Event capture for API token actions: created, revoked
- Async event persistence via Sidekiq worker
- Feature flag `security_events_enabled` on the `companies` table
- AWS GuardDuty activation in us-east-1 and sa-east-1 (Terraform)
- AWS Security Hub activation with CIS AWS Foundations Benchmark (Terraform)
- AWS Macie activation for S3 sensitive data detection (Terraform)
- Onboarding/offboarding identity procedure documentation (Item 2)
- SOC alert triage and response procedure documentation (Item 6)
- Internal Audit Procedure document + first audit execution (Item 7)

### Out of Scope

- Access log screen in the web client (future: same table, JWT-authenticated consumer — not in this delivery)
- Google Workspace DLP rules (Item 4 partial — separate configuration, no code)
- VPC Flow Logs (not required for GuardDuty activation, can be added later)
- SIEM consumer implementation on the client side (Positivo configures their own SIEM to poll the API)
- Any changes to `app-webclient` or `app-mobileclient`

## Execution Phases

### Phase 1 — Documentation (Items 2 + 6 + 7) | Priority: Item 2 first (60-day deadline)

**Objective**: Deliver the three documentation-only items. No code changes. Item 2 has the shortest deadline (60 days) and must be prioritized.

**Deliverables**:

- **Item 2 — Identity Lifecycle Procedure**: Document onboarding/offboarding checklist with defined responsibilities, execution records, and Google Workspace as identity hub. Format: internal document (not in codebase).
- **Item 6 — SOC Procedures**: Document alert triage, response, and escalation process for GuardDuty + Security Hub findings. Depends on Phase 2 (tooling must exist before documenting the response process). Create after Phase 2.
- **Item 7 — Internal Audit Procedure**: Document audit process with defined frequency covering all active security policies. Perform first audit and generate report. Can be done after Phase 2 tooling is active.

**Dependencies**: Item 6 and 7 depend on Phase 2 completion (tooling must be live before SOC procedures are finalized).

**Success Criteria**:
- [ ] Item 2: Written onboarding/offboarding procedure delivered to Positivo as evidence
- [ ] Item 6: Written SOC procedure covering GuardDuty and Security Hub alert handling
- [ ] Item 7: Internal Audit Procedure document + first audit report exists

---

### Phase 2 — AWS Security Services (Items 3 + 5 + 4) | Terraform | 90-day deadline

**Objective**: Activate GuardDuty, Security Hub, and Macie via Terraform. All three services have 30-day free trials. Items 3+5+6 resolve together with a single Terraform implementation.

**Infrastructure pattern**: The project uses separate Terraform stacks per environment/service (e.g., `app-shared-001/`, `monitoring/`). These new services should be organized as a new stack or within the existing `monitoring/` stack. No existing GuardDuty/Security Hub/Macie configuration found in the codebase — this is net new.

**Components**:

- **GuardDuty (Item 5)**: Activate in both regions (us-east-1 and sa-east-1). Analyzes CloudTrail logs, VPC Flow Logs, and DNS. CloudTrail is already active multi-region — GuardDuty will consume it automatically. Estimated cost: ~$20-25/month.
- **Security Hub (Item 3)**: Activate with CIS AWS Foundations Benchmark enabled. Per-check billing model. Estimated cost: ~$2-5/month.
- **Macie (Item 4)**: Activate for S3 sensitive data detection. 21 S3 buckets to scan. Estimated cost: ~$10-50/month.

**Estimated total AWS cost**: ~$50-80/month (worst case ~$120/month).

**Dependencies**: None. Can start immediately.

**Success Criteria**:
- [ ] GuardDuty active in us-east-1 and sa-east-1, findings visible in AWS console
- [ ] Security Hub active with CIS AWS Foundations Benchmark enabled, compliance score visible
- [ ] Macie active and scanning S3 buckets for sensitive data
- [ ] Terraform plan reviewed and applied without errors
- [ ] `terraform` CHANGELOG.md updated

---

### Phase 3 — Security Events API (Item 1) | App | 120-day deadline

**Objective**: Implement a read-only REST API that exposes security events per company, enabling SIEM integration. Opt-in per client via feature flag.

**Estimated effort**: 7-8 dev days. At 2 days/week available → ~4 weeks elapsed.

#### 3.1 — Database: `security_events` table

New table following the pattern of existing event tables (e.g., `commission_release_events`).

```
security_events
  id             bigserial primary key
  company_id     bigint not null (FK → companies)
  user_id        bigint (FK → users, nullable — some events have no user)
  event_type     string not null
  severity       string not null
  outcome        string not null
  ip_address     string
  user_agent     string
  auth_method    string
  failure_reason string
  resource_type  string
  resource_id    string
  metadata       jsonb
  occurred_at    datetime not null
  created_at     datetime not null
  updated_at     datetime not null

  index on company_id
  index on [company_id, occurred_at] (for time-range queries)
  index on event_type
```

**Note on `metadata` column**: Covers extensible context fields (e.g., `failure_reason`, `auth_method`) that vary per event type. Avoids nullable columns proliferating for each event variant.

#### 3.2 — Feature flag: `security_events_enabled` on companies

Add boolean column to `companies` table. Default `false`. Opt-in per client.

#### 3.3 — Model: `SecurityEvent`

Pattern: follows `CommissionReleaseEvent` (ActiveRecord, belongs_to company, belongs_to user optional).

```ruby
class SecurityEvent < ApplicationRecord
  belongs_to :company
  belongs_to :user, optional: true

  TYPES = %w[
    authentication.login_success
    authentication.login_failure
    authentication.logout
    authentication.account_locked
    authentication.account_unlocked
    authentication.password_reset_requested
    authentication.password_reset_completed
    user.disabled
    user.reactivated
    api.token_created
    api.token_revoked
  ].freeze

  SEVERITIES = %w[low medium high].freeze
  OUTCOMES   = %w[success failure].freeze

  scope :for_company, ->(id) { where(company_id: id) }
  scope :since,       ->(ts) { where('occurred_at >= ?', ts) if ts.present? }
  scope :until_ts,    ->(ts) { where('occurred_at <= ?', ts) if ts.present? }
  scope :by_type,     ->(type) { where(event_type: type) if type.present? }
end
```

#### 3.4 — Worker: `SecurityEventPersistorWorker`

Async persistence via Sidekiq. Follows `ApplicationWorker` base class. Receives serialized event attributes hash, finds or creates the record. Uses `sidekiq_options queue: :default` (or a dedicated `:security` queue if preferred — confirm with engineer).

#### 3.5 — Event instrumentation at the 3 authentication entry points

Instrument must happen at the controller layer, not model callbacks, to capture IP address and user agent from the request.

**Entry point 1: `SessionsController#create` (POST /sessions — password login)**

After `valid_credentials` check:
- Success → enqueue `SecurityEventPersistorWorker` with `authentication.login_success`, outcome: success, auth_method: password
- Failure → enqueue with `authentication.login_failure`, outcome: failure, failure_reason from context (user not found vs. invalid password vs. company disabled vs. basic_auth disabled)

**Entry point 2: `Authentication::SessionsController#show` (SSO via Keycloak)**

After `current_user` resolution:
- Success → enqueue `authentication.login_success`, auth_method: `sso_microsoft` / `sso_google` / `sso_keycloak` (derive from `authenticator_configuration` provider type)
- Failure (user not found / company disabled) → enqueue `authentication.login_failure`

**Entry point 3: Devise web login (POST /users/sign_in)**

Use Warden callbacks. The `config.warden` block in `devise.rb` is already present but commented out. Add:
- `manager.after_authentication` → enqueue `authentication.login_success`, auth_method: `devise_web`
- `manager.after_failed_authentication` → enqueue `authentication.login_failure`

**Account locked / unlocked**: Hook into Devise `:lockable` callbacks via `after_lock` / `after_unlock` — or instrument at `User` model level (acceptable since no request context needed for these events).

**Password reset**: Instrument in Devise `PasswordsController` or via model callbacks on `reset_password_token` presence.

**Logout**: Instrument in Devise `SessionsController#destroy` (Devise web) and add `DELETE /sessions` to the custom `SessionsController` if not present.

#### 3.6 — User lifecycle events

Instrument via ActiveRecord callbacks on `User` model or service objects that handle enable/disable:
- `user.disabled` → when `User#disabled_at` is set
- `user.reactivated` → when `User#disabled_at` is cleared

These events have no request context (done via API), so IP/user_agent will be nil.

#### 3.7 — API token events

Instrument in the code that creates/revokes `CompanyToken`:
- `api.token_created`
- `api.token_revoked`

#### 3.8 — API endpoint: `GET /api/v3/security_events`

Follows `ApiController` pattern (CompanyToken auth, company-scoped). Check `current_company.security_events_enabled` — return 404 if not enabled.

**Query parameters**:
- `since` — ISO 8601 datetime (inclusive lower bound on `occurred_at`)
- `until` — ISO 8601 datetime (inclusive upper bound on `occurred_at`)
- `event_type` — filter by event type
- `after` — event ID for cursor-based pagination (e.g., `after=evt_12345`). Returns events with ID greater than this value.
- `limit` — integer, max results per page (default 100, max 1000)

**JSON response per event** (matches the agreed format with Positivo):
```json
{
  "id": "evt_<id>",
  "timestamp": "<occurred_at ISO 8601 UTC>",
  "event_type": "authentication.login_failure",
  "severity": "medium",
  "outcome": "failure",
  "actor": {
    "email": "...",
    "user_id": "...",
    "ip_address": "...",
    "user_agent": "..."
  },
  "target": {
    "resource_type": "session",
    "resource_id": null
  },
  "context": {
    "company_id": "...",
    "auth_method": "password",
    "failure_reason": "invalid_credentials"
  }
}
```

Use `ActiveModel::Serializer` (existing pattern: `ApplicationSerializer` → `GoalSerializer`). Create `SecurityEventSerializer`.

#### 3.9 — Serializer: `SecurityEventSerializer`

Inherits `ApplicationSerializer`. Renders the agreed JSON format above with OpenAPI component schema for documentation.

**Dependencies**:
- Phase 3.1 (migration) must be done before 3.3 (model)
- Phase 3.3 (model) must be done before 3.4 (worker) and 3.8 (controller)
- Phase 3.5/3.6/3.7 (instrumentation) depends on 3.4 (worker exists)
- Phase 3.8 (endpoint) depends on 3.3, 3.9 (serializer)

**Success Criteria**:
- [ ] `security_events` table created via migration
- [ ] `security_events_enabled` column added to `companies`
- [ ] `SecurityEvent` model with all scopes and constants
- [ ] `SecurityEventPersistorWorker` persists events asynchronously
- [ ] All 3 login flows enqueue events on success and failure
- [ ] Account lock/unlock events captured
- [ ] Password reset events captured
- [ ] Logout events captured
- [ ] User disable/reactivate events captured
- [ ] API token create/revoke events captured
- [ ] `GET /api/v3/security_events` returns correct JSON for authorized company with flag enabled
- [ ] `GET /api/v3/security_events` returns 404 for company with flag disabled
- [ ] `app` CHANGELOG.md updated

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| API authentication | CompanyToken (existing `ApiController` pattern) | Consistent with all other v3 API endpoints; no new auth mechanism needed |
| Event persistence | Async via Sidekiq worker | Follows project pattern (395+ workers); keeps login path latency unaffected |
| Feature flag | Boolean column on `companies` table | Matches existing feature flag pattern (e.g., `deal_eligibility_module`, `subsidiaries_module`) |
| Event ID format | `evt_<database_id>` string | Stable, readable, avoids exposing raw integer IDs to external consumers |
| Extensible event context | `metadata` jsonb column | Avoids nullable columns per event type; allows future fields without migrations |
| Serializer | `ActiveModel::Serializer` | Existing project pattern — all API serializers inherit `ApplicationSerializer` |
| Pagination | Cursor-based (after=id, limit=100) | No existing read endpoints in the API v3 — this is the first. Cursor-based is optimal for SIEM polling (sequential, no offset drift). No gem needed — simple `where("id > ?", after).limit(n).order(:id)` |
| Terraform organization | New `security/` stack or extend `monitoring/` | Confirm with engineer which fits the existing convention |
| GuardDuty regions | us-east-1 + sa-east-1 | Matches existing infrastructure deployment regions |
| Warden hooks location | `config/initializers/devise.rb` warden block | Already present (commented out); correct place for Devise auth event hooks |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Sidekiq queue saturation | Medium | Use existing queue infrastructure; monitor during rollout; dedicated queue if needed |
| SSO auth_method detection | Medium | `authenticator_configuration` must expose provider type — verify before implementation |
| Rack::Attack only in pen_test mode | Low | Not blocking; security events complement rate limiting, not replace it |
| AWS service costs exceed estimate | Low | 30-day free trial available; monitor CloudWatch billing alarms; worst case ~$120/month |
| Warden callback fires for API logins too | Medium | Confirm Warden scope — `SessionsController` uses manual auth, not Warden; no double-counting |
| `company_id` null for unauthenticated failed logins | Medium | Store IP/user_agent only; omit company_id and user_id when email not resolved |

## Assumptions

- `authenticator_configuration` has a method or attribute to identify the OAuth provider (Microsoft, Google, Keycloak) for `auth_method` derivation — verify before implementation
- User disable/reactivate is done through a service object or direct model update — identify the exact call site before instrumenting
- Pagination is cursor-based (`after=id`, `limit=N`) — this is the first read endpoint in the API v3, no existing pattern to follow
- Terraform new security services will live in a dedicated `security/` directory under the terraform project (or `monitoring/` — confirm before creating files)
- Google Workspace DLP configuration (Item 4 partial) is handled separately by the operations team, not in this plan

**Status:** READY FOR TASK CREATION
