# PLAN — Security Events Platform

> **Handoff note:** this plan was authored by Paulo and will be executed by another engineer. Read § Context first — the two-client motivation drives every design decision below.

---

## Context — why this exists

Two unrelated clients asked for the same underlying data, in two different shapes, in two different commercial conversations. The platform is going to need this capability long-term — 4Shark operates with large corporations and the absence of an access-events product is going to keep showing up in security questionnaires and audit demands. Treat this as a **corporate platform capability** that happens to be paid for by Atento and Positivo first.

**Client 1 — Atento México (commercial commitment is live).**
Atento needs to audit employee access to the platform: who logged in, when, how many times, whether it succeeded, whether the user reset a password, whether they logged out. They want to query this **inside the platform** with filters, and they want an Excel export for evidence in employee disputes ("the employee claims they did not see the declaration"). Commercial deliverable signed off at 70h — `~/.claude/plans/active/spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` § 2.1.

**Client 2 — Positivo (commercial commitment is live, but deferrable inside the 120-day window).**
Positivo's vendor security assessment (Q1.17) requires "connectivity with corporate SIEM systems". They will poll a REST endpoint we expose; their SIEM ingests it. Our DISPOSITION-v2.md response committed only to "JSON format, enabling integration with any SIEM platform" — they did not specify OCSF/CEF/ECS or anything specific. See `~/.claude/plans/active/content/vendor-assessment-positivo/DISPOSITION-v2.md` § Item 1. Deadline: 2026-08-06 (120 days from 2026-04-08).

**Same data, two consumers.** Building two parallel systems creates drift, doubles the work, and burns a chance to ship a real platform capability. Building it once and exposing it twice is the correct shape.

---

## Priority and sequencing — read carefully

This is **not** a single batch of work. The phases are deliberately sequenced:

| Phase | Status | Why this status |
|---|---|---|
| **Phase 1 — Capture & storage** | **Build now** | Both clients depend on it; nothing else can ship without it; it's the engineering core |
| **Phase 2 — Atento UI + Excel export** | **Build now or right after Phase 1** | Atento's commercial deliverable; can ship with Phase 1 or immediately after |
| **Phase 3 — Positivo SIEM API** | **Defer — keep design open for it** | Positivo has a 120-day window; the value is in shipping it before the deadline, not now. **But Phase 1 MUST be designed so this drops in cleanly later** (see § Design constraints from deferred phases) |
| **Phase 4 — Retention archive (S3, 90d+)** | **Defer** | Storage will only matter after 90 days of capture; not urgent. Same design-open rule applies |

**Critical rule for the implementing engineer:** Phase 1 ships data. If Phase 1's schema or write path forecloses the SIEM API (Phase 3) or the archive (Phase 4), the rework cost lands on the team and on the client deadlines. The § Design constraints from deferred phases section below lists every constraint Phase 1 must respect.

---

## Objective

Build an opt-in **security events platform** with a single event store that is **today** consumed by the Atento UI and **later** by the Positivo SIEM API. Phase 1 produces durable, auditable events. Phase 2 makes them visible to admins. Phase 3 (later) makes them pullable by external systems. Phase 4 (later) keeps the live table bounded.

## Scope

### In scope — Phase 1 (now)

- New `security_events` table — single source of truth for all consumers
- Feature flag `security_events_enabled` on the `companies` table (opt-in per client)
- Event capture at every authentication / identity event listed in § Event catalog
- Async persistence via Sidekiq worker (`SecurityEventPersistorWorker`)
- Unit + integration tests for capture, model, worker
- `app` CHANGELOG.md updated

### In scope — Phase 2 (now or immediately after Phase 1)

- Backend endpoint for the Atento UI — JWT-authenticated, hierarchy-aware
- New screen in `app-webclient` with filters and pagination
- Excel export (`.xlsx`) — same filters, no pagination, server-streamed
- `app-webclient` CHANGELOG.md updated
- es-MX and pt-BR translations (es-MX first)

### Designed-for but not built — Phase 3 (deferred)

- `GET /api/v3/security_events` — CompanyToken auth, cursor pagination, canonical JSON envelope (actor/target/context)
- OpenAPI documentation for the public endpoint
- Phase 1's schema and write path **must not block this** — see § Design constraints

### Designed-for but not built — Phase 4 (deferred)

- Archive worker (`SecurityEventArchiveWorker`) — moves events older than 90 days to S3 (JSONL.gz, partitioned per company per month)
- Archive reader — restores archived events for on-demand queries
- Terraform — S3 bucket, lifecycle policies, IAM
- Phase 1's schema **must support partitioning by `(company_id, occurred_at)` without contortion** — see § Design constraints

### Out of scope (any phase)

- Page-level navigation tracking — explicitly excluded by Atento in the clarification meeting
- Real-time push / webhook delivery — polling only
- Adoption of a formal SIEM schema (OCSF, ECS, CEF) — Positivo did not specify; canonical JSON is enough. If a client later requests a formal schema, it becomes an adapter on top of the canonical JSON, not a re-modeling
- SIEM consumer implementation on the client side — Positivo configures their own
- Atento's migration to SSO-only — independent operational decision
- Other Positivo RFP items (2–7) — remain in `positivo-risk-mitigation/PLAN.md`
- Other Atento SOW items (2.2–3.2) — remain in `atento-mexico-improvements/STATEMENT-OF-WORK-v2.md`

---

## Design constraints from deferred phases

This section exists so the engineer building Phase 1 (and Phase 2) does not paint the project into a corner. Every constraint below traces to something Phase 3 or Phase 4 will need.

### From Phase 3 (Positivo SIEM API)

1. **Every field needed by the SIEM JSON envelope must exist as a first-class column or in `metadata` jsonb — no fields buried in joins or computed at read time.** The envelope shape (see § SIEM JSON envelope — design reference) maps directly to columns: `event_type`, `severity`, `outcome`, `user.email`, `user_id`, `ip_address`, `user_agent`, `company_id`, `auth_method`, `channel`, `failure_reason`, `resource_type`, `resource_id`, `occurred_at`. If Phase 1 collapses any of these into a single text blob, Phase 3 has to rebuild capture.
2. **Event IDs must be stable, opaque strings the platform owns** — `evt_<bigserial_id>`. Do not expose raw integers and do not adopt UUIDs (cursor pagination becomes harder).
3. **The table must support cursor pagination by `(company_id, id)` cleanly** — bigserial primary key, indexed on `(company_id, id)` and `(company_id, occurred_at)`. No composite primary keys, no functional indexes that complicate ordering.
4. **The opt-in must be per-company at the company row, not at the user row.** A SIEM is a corporate consumer; per-user opt-in does not match the SIEM ingestion model.
5. **No write path may depend on the consumer being present.** Events get written whether or not a SIEM ever polls — they are also the Atento audit log.
6. **`auth_method` must distinguish SSO providers** (`sso_microsoft`, `sso_google`, `sso_keycloak`), not just `sso`. The Positivo SIEM correlates by identity provider.

### From Phase 4 (archive)

7. **`occurred_at` must be set at capture time, not at insert time.** The async worker may write hours later; ordering and 90-day cutoff use `occurred_at`. Use `created_at` only for operational telemetry.
8. **Per-company-per-month physical layout must be cheap to compute.** This is automatic if (company_id, occurred_at) is indexed and the values are accurate.
9. **No `delete_all` migration paths** — the archive worker reads then deletes only after S3 confirms. Phase 1's table must allow per-row delete after archive without breaking referential integrity. No foreign keys *into* `security_events`.

### General

10. **No silent data loss.** The async worker must retry. Capture-site code (the auth flow) must not raise on enqueue failure — log and continue; never crash a login because the audit failed.
11. **Tests cover every event type listed in § Event catalog.** A new event type is a code change; missing tests now means missing events later that nobody notices.

---

## Event catalog

| Event type | Severity | Outcome | Triggers |
|---|---|---|---|
| `authentication.login_success` | low | success | Successful login on any entry point |
| `authentication.login_failure` | medium | failure | Failed login (with `failure_reason`: `invalid_credentials`, `user_not_found`, `company_disabled`, `basic_auth_disabled`, `sso_provider_error`, etc.) |
| `authentication.logout` | low | success | Explicit logout |
| `authentication.logout_failure` | low | failure | Logout request that did not complete (session already expired, token revoked, etc.) |
| `authentication.account_locked` | medium | success | Devise `:lockable` triggers lock after N failed attempts |
| `authentication.account_unlocked` | low | success | Lockout cleared (timer or manual) |
| `authentication.password_reset_requested` | low | success | Password reset email requested |
| `authentication.password_reset_completed` | low | success | Password reset finalized |
| `user.disabled` | medium | success | `User#disabled_at` set |
| `user.reactivated` | low | success | `User#disabled_at` cleared |
| `api.token_created` | low | success | `CompanyToken` created |
| `api.token_revoked` | medium | success | `CompanyToken` revoked |

`auth_method` per event: `password`, `devise_web`, `sso_microsoft`, `sso_google`, `sso_keycloak` (derived from `authenticator_configuration` provider type).

`channel` per event: `web`, `mobile`, `api`. Derived from request headers / endpoint; nil for events with no request context (lifecycle, scheduled actions).

---

## SIEM JSON envelope — design reference

Phase 3 ships this. Phase 1 must not foreclose it. Listed here so the Phase 1 engineer can confirm the schema supports it.

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
    "channel": "web",
    "failure_reason": "invalid_credentials"
  }
}
```

Every field maps to a column or `metadata` jsonb path. No joins required beyond `user.email` (FK already present).

---

## Execution phases

### Phase 1 — Capture & storage (now)

**Objective:** create the event store, the async persistence path, and the instrumentation at every capture point. Nothing is exposed externally yet — but everything is captured.

**Components:**

- **Migration — `security_events` table:**
  ```
  security_events
    id              bigserial primary key
    company_id      bigint not null   (FK → companies)
    user_id         bigint            (FK → users, nullable — pre-auth failures have no user)
    event_type      string not null
    severity        string not null
    outcome         string not null
    auth_method     string
    channel         string            (web | mobile | api | nil)
    ip_address      string
    user_agent      string
    failure_reason  string
    resource_type   string
    resource_id     string
    metadata        jsonb
    occurred_at     datetime not null
    created_at      datetime not null
    updated_at      datetime not null

    index on (company_id, id)
    index on (company_id, occurred_at)
    index on event_type
  ```

- **Migration — add `security_events_enabled` boolean to `companies`** (default false).

- **Model — `SecurityEvent`:** ActiveRecord, `belongs_to :company`, `belongs_to :user, optional: true`. Constants: `TYPES`, `SEVERITIES`, `OUTCOMES`, `CHANNELS`, `AUTH_METHODS`. Scopes: `for_company`, `since`, `until_ts`, `by_type`, `by_channel`, `by_auth_method`, `by_outcome`.

- **Worker — `SecurityEventPersistorWorker`:** receives a serialized attributes hash, creates the record. Inherits `ApplicationWorker`. Default queue (decision to dedicate a `:security` queue deferred to operational data — start in default and split later if it impacts other queues).

- **Capture — three login entry points:**
  - `SessionsController#create` (POST /sessions — password) → success/failure
  - `Authentication::SessionsController#show` (SSO via Keycloak) → success/failure (auth_method derived from `authenticator_configuration`)
  - Devise web (POST /users/sign_in) via Warden `manager.after_authentication` / `manager.after_failed_authentication` (already-commented warden block in `config/initializers/devise.rb` becomes the wiring point)

- **Capture — logout:** Devise `SessionsController#destroy` for web; `DELETE /sessions` on the custom controller for API/mobile. Both emit `authentication.logout` on success and `authentication.logout_failure` on failure.

- **Capture — Devise lockable:** `after_lock` / `after_unlock` hooks → `authentication.account_locked` / `authentication.account_unlocked`.

- **Capture — password reset:** Devise `PasswordsController` for request and completion.

- **Capture — user lifecycle:** ActiveRecord callbacks on `User` for `disabled_at` transitions.

- **Capture — API token:** in the code path that creates and revokes `CompanyToken`.

- **Channel detection:** request-bearing capture points read a single helper (e.g. `SecurityEventChannel.detect(request)`) that inspects request path/headers — `/api/v3/*` → `api`, mobile user-agent patterns → `mobile`, otherwise `web`. Lifecycle captures pass `channel: nil`.

**Dependencies:** None. Starts immediately.

**Success criteria:**
- [ ] Migration applied; both tables/columns exist in all environments
- [ ] Every event listed in § Event catalog is enqueued on its trigger
- [ ] Records land in `security_events` only when `current_company.security_events_enabled?` is true
- [ ] Async path adds <5ms p99 to login latency (benchmarked)
- [ ] Unit tests for the model, the worker, and one feature spec per capture point
- [ ] Enqueue failure does not crash a login (verified by test)
- [ ] `app` CHANGELOG.md updated

---

### Phase 2 — Atento UI + Excel export (now or right after Phase 1)

**Objective:** deliver the in-app screen that Atento admins use to audit access, with filters and Excel export. May ship in parallel with Phase 1 (separate engineer) or immediately after.

**Components:**

- **Backend endpoint — JWT-authenticated:** new internal endpoint (separate from the v3 public API) that the web client consumes. Same data, same shape; authenticated by user session JWT; hierarchy-aware (admin sees company-wide, manager sees their team).
  - Path: confirm against existing internal-API conventions before scaffolding (likely under the same controller namespace used by other web-client screens)
  - Filters: date range, employee (text search / picker), event type, auth method, channel, outcome
  - Server-side hierarchy filter
  - Cursor-based pagination matching the table's `(company_id, id)` index

- **Excel export endpoint (`.xlsx`):** same filters, no pagination, server-streamed. Output limited by date-range — refuse ranges > 90 days at Phase 2 (the archive is not live yet).

- **Frontend — new screen in `app-webclient`:**
  - Filter bar (date range, employee, auth method, channel, outcome)
  - Table (timestamp, employee, event type, auth method, channel, outcome, IP, failure reason)
  - Pagination (server-driven, cursor-based)
  - "Export to Excel" button → triggers the export endpoint
  - Empty state for companies with zero events
  - es-MX first; pt-BR alongside

- **Permissions:** new permission node `view_security_events`, defaults on for company admins. Per-role granularity deferred — confirm with engineer before scaffolding the permission tree.

**Dependencies:** Phase 1 must be live and producing events. (For parallel work: the backend endpoint can be scaffolded against an empty table — the frontend cannot meaningfully demo until events exist.)

**Success criteria:**
- [ ] Admin user opens the screen and sees their company's events
- [ ] Hierarchy filter respected (manager sees only their team)
- [ ] All filters work and combine
- [ ] Excel export delivers the same data the UI shows
- [ ] Empty state renders for zero events
- [ ] es-MX and pt-BR labels present
- [ ] `app-webclient` CHANGELOG.md updated

---

### Phase 3 — Positivo SIEM API (deferred)

**Listed for design constraints; not part of the current work order.**

When this phase is picked up, it should be a small delta on top of Phases 1+2:

- **Endpoint — `GET /api/v3/security_events`:**
  - Inherits `ApiController` (CompanyToken auth, company-scoped)
  - Returns 404 if `current_company.security_events_enabled?` is false
  - Query params: `since`, `until`, `event_type`, `channel`, `auth_method`, `outcome`, `after` (cursor = event ID), `limit` (default 100, max 1000)

- **Serializer — `SecurityEventSerializer`:** inherits `ApplicationSerializer`. JSON envelope per § SIEM JSON envelope — design reference.

- **OpenAPI documentation** for the endpoint (component schema for `SecurityEvent`).

If Phase 1 follows § Design constraints from deferred phases, this work is mostly serializer + controller + tests. No schema changes, no new captures.

**Deadline reference (when picked up):** Positivo Q1.17 — 2026-08-06 (120d from 2026-04-08).

---

### Phase 4 — Retention archive (deferred)

**Listed for design constraints; not part of the current work order. Only meaningful after Phase 1 has been live for 90 days.**

When picked up:

- **Archive worker (`SecurityEventArchiveWorker`):** scheduled. Reads events older than 90 days, writes to S3 in compressed JSON Lines (one file per company per month: `s3://<bucket>/security-events/<company_id>/<YYYY-MM>.jsonl.gz`), then deletes the rows from `security_events` only after S3 write confirms.

- **Archive reader:** small service object that, given `(company_id, since, until)`, lists the relevant S3 objects, streams them, filters in memory, returns event records of the same shape as the live table.

- **API behavior across the boundary:** the Phase 3 endpoint, if live, transparently merges archive + live results. UI shows a banner when the requested range includes archived data.

- **Terraform:** new S3 bucket with lifecycle policies (Standard → Standard-IA at 90d, Glacier at 365d), bucket-level encryption, restricted IAM. Stack location confirmed with engineer at pick-up time.

---

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Storage shape | Single `security_events` table for all consumers | Same data, multiple lenses; no duplication; no drift |
| Opt-in | `security_events_enabled` boolean on `companies` | Matches existing feature-flag pattern; SIEM is a corporate consumer (company-level) |
| Persistence path | Async via Sidekiq worker | Login latency is non-negotiable; matches the 395+ worker pattern in the codebase |
| Event ID format | `evt_<bigserial_id>` string | Stable, opaque, cursor-pagination-friendly |
| Extensible context | `metadata` jsonb column | No nullable column proliferation per event variant |
| Pagination | Cursor-based (`after=<id>`, `limit=N`) | First read endpoint in API v3; cursor is optimal for both SIEM polling and UI |
| SIEM format | Canonical JSON envelope (actor/target/context), deferred to Phase 3 | Positivo Q1.17 did not specify a format; DISPOSITION-v2.md committed only to "JSON format" |
| Retention | 90 days online + S3 archive (deferred to Phase 4) | Matches Atento SOW v2 § 2.1 commitment; keeps PG table bounded |
| Channel modeling | Dedicated `channel` column (web/mobile/api) | Engineer explicitly called out "se foi via mobile"; user_agent parsing is brittle |
| `logout_failure` event | Included | Engineer specified explicitly; capture cost is trivial; useful signal for both audit and SIEM |
| Hierarchy filter location | Server-side in the UI endpoint | Atento workflow #9 already establishes hierarchy filters as a backend responsibility |
| Worker queue | Default queue initially | No volume data yet; split into `:security` only if it impacts other queues |
| Atento permission node | Single `view_security_events` permission | Per-role granularity deferred until product confirms |
| Excel export range limit | ≤ 90 days while archive (Phase 4) is not live | Avoid surprising the user with a partial export |
| Foreign keys *into* `security_events` | Forbidden | Phase 4 archive deletes rows; FKs in would block delete |

---

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Login latency regression | High | Async via Sidekiq; benchmark p99 before/after; rollback by flipping the feature flag |
| `authenticator_configuration` does not expose provider type cleanly | Medium | Verify before Phase 1 starts; if missing, add a lookup method as a Phase-1 prerequisite |
| Warden hook double-fires for both API and web | Medium | `SessionsController` uses manual auth, not Warden — confirm Warden scope before wiring |
| Failed login with no resolvable user → `company_id` null | Medium | Store IP / user_agent / email-attempted only; events with null `company_id` land in a separate "anonymous failures" view. Confirm at implementation time whether to enforce `company_id` not-null or accept nulls for this case |
| Sidekiq queue saturation under attack | Medium | Default queue first; monitor; split to `:security` queue if needed |
| UI exposes one client's events to another | Critical | Mandatory `company_id` scope on every query; integration test that fails the build if any query lacks it |
| Phase 1 schema forecloses Phase 3 or Phase 4 | High | § Design constraints from deferred phases (above) — review at PR time |
| Atento expects auth events from before the rollout | Medium | Rollout date is t=0 for this client; no backfill from logs. Communicate this at delivery |
| Phase 2 ships before Phase 1 has produced events | Low | Frontend can mock data; backend endpoint tested with seeded events |

---

## Assumptions

- `authenticator_configuration` exposes a method or attribute identifying the OAuth provider (Microsoft / Google / Keycloak) — verify before Phase 1
- User disable/reactivate happens through a service object or direct `User#update` — identify the exact call site before instrumenting (avoid double-firing)
- The internal-API endpoint for the Atento UI follows the same convention as other `app-webclient` consumers — confirm controller namespace before scaffolding
- Atento permission model accepts a single `view_security_events` permission node; per-role granularity is deferred
- The Atento UI ships first in es-MX, then pt-BR; other locales are out of scope for this delivery
- `app` and `app-webclient` deploy in lockstep for Phase 2; if they cannot, Phase 2 ships behind a frontend feature flag
- Volume per company is low enough that a single default Sidekiq queue absorbs the writes; revisited based on rollout telemetry

---

## Deadlines

| Source | Deadline | Phases that satisfy it |
|---|---|---|
| Atento México Item 2.1 (Access Control and Login History) | Per SOW v2 commercial timeline | Phase 1 + Phase 2 |
| Positivo RFP Item 1 (SIEM API) | 2026-08-06 (120d from 2026-04-08) | Phase 3 — **handled separately when picked up** |

Phase 1 + Phase 2 form the current work order. Phase 3 and Phase 4 are deferred and will be picked up in a separate cycle; they appear here so the Phase 1+2 engineer respects the constraints they impose.

---

## References

- `~/.claude/plans/active/positivo-risk-mitigation/PLAN.md` — original Positivo RFP plan; Item 1 superseded by this plan, Items 2–7 still apply
- `~/.claude/plans/active/content/vendor-assessment-positivo/DISPOSITION-v2.md` § Item 1 — Q1.17 wording and our committed response (basis for "canonical JSON, no formal schema")
- `~/.claude/plans/active/spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` § 2.1 — Atento commercial commitment ("Access Control and Login History — 70h")
- `~/.claude/plans/active/spike/atento-mexico-improvements/KNOWLEDGE.md` § #18 — original Keycloak-based proposal (superseded by SOW v2)

---

**Status:** READY FOR TASK CREATION on Phases 1 + 2 (per `@agent-task-researcher` → `@agent-task-composer` pipeline). Phases 3 + 4 stay in this plan as design references; their task creation is a future, separate event.
