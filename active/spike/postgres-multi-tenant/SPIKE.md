# SPIKE — PostgreSQL schema-per-tenant migration strategy

**Conducted by:** Engineering Team
**Date:** 2026-03-07
**Status:** Research complete — on hold (cost-prohibitive at current team capacity)

---

## Goal

Answer the following questions:

1. **Is schema-per-tenant the right model for 4Shark?** Are there trade-offs worth considering versus the current row-level approach?
2. **How can we migrate ~153 tables × N companies from a single shared schema to isolated per-tenant schemas with zero downtime?**
3. **Can we avoid duplicating the entire database once per tenant?** What is the actual data movement cost?
4. **What is the Rails/Sidekiq surface area that needs to change?** What breaks, what is easy, what is hard?

---

## Decisions Recorded

The following decisions were made after the initial research phase:

1. **Proceed with schema-per-tenant (Option B).** Row-level tenancy (Option A) is ruled out as a long-term solution.
2. **Superadmin cross-tenant access via Option 3** — keep company identity and configuration tables in `public`; isolate all tenant operational data in tenant schemas. No aggregation layer, no UNION ALL queries.
3. **No external gem.** Custom Rack + Sidekiq middleware only (~30 lines total). Avoids `apartment` maintenance risk.
4. **Middleware added as a no-op first** — deployed to all environments before any data migration begins, so deploys are never blocked.
5. **Four-environment rollout** — migration is validated sequentially: Beta → Demo → Atento → Shared. Fake/low-risk data first, largest environment last. Shared (120–150 tenants, 300+ GB) is treated as production and is the final and riskiest environment.

---

## Method

- Analyzed `db/schema.rb` (153 tables, ~154 `company_id` column occurrences)
- Analyzed `app/models/company.rb` and `app/models/application_record.rb`
- Mapped which tables do/do not carry `company_id`
- Researched PostgreSQL schema mechanics, logical replication, and `pg_dump`/`pg_restore` capabilities
- Reviewed available Rails multi-tenant gems (Apartment, acts_as_tenant, Tenant)
- Reviewed the existing `TenantWorker::Queue` and Sidekiq queue-per-company pattern already in place

---

## Evidence

### Current State

**Tenancy model:** Row-level. Every tenant's data lives in the `public` schema. A `company_id` foreign key discriminates ownership.

**Scale:**
- 153 tables total
- ~95 tables carry `company_id` directly
- ~58 tables have no `company_id` (see classification below)
- No multi-tenant gem in the Gemfile
- ApplicationRecord has no automatic tenant scoping — queries are not filtered by company unless explicitly coded

**Relevant existing patterns:**
- `TenantWorker::Queue` already routes Sidekiq jobs per company (queue suffix = `company.commission_queue_suffix`)
- The app has primary + replica PostgreSQL setup via `ApplicationRecord.connects_to`
- 9 company locales are supported — no data shape difference per locale

---

### Option A — Keep Row-Level Tenancy (status quo, improved)

Do not migrate to schema-per-tenant. Instead, add automatic scoping via `acts_as_tenant` or a custom `default_scope` in ApplicationRecord.

**Pros:**
- Zero migration risk
- Cross-tenant queries (admin, analytics) remain simple
- No infrastructure change
- Rails migrations work normally (one migration = all tenants)

**Cons:**
- Data of all tenants still in the same tables — one miscoded query leaks data
- No native PostgreSQL isolation (row-level security possible but complex)
- Indexes must scan the full table; performance degrades as tenant count grows
- Cannot easily point a single tenant at a different database shard

**Verdict:** ~~A viable intermediate step but does not address isolation or scalability concerns long-term.~~ **Ruled out.**

---

### Option B — Schema-Per-Tenant (PostgreSQL schemas)

Each company gets its own PostgreSQL schema (e.g., `tenant_42`). A shared `public` schema holds global and company-configuration tables.

Rails connects using `SET search_path = tenant_42, public` at the start of each request/job.

**Gem options:**
- **`apartment`** (archived, unmaintained since 2020) — not recommended for new projects
- **`apartment-activejob`** / community forks — fragmented, risky
- **Custom middleware** — set `search_path` in a Rack middleware or around_action + Sidekiq middleware. Straightforward, no gem dependency. ✅ **Chosen**

**Pros:**
- Strong data isolation: a missing `WHERE company_id = ?` no longer leaks data
- Per-tenant index size shrinks proportionally to tenant count
- Future: can move a tenant's schema to a separate database with logical replication
- PostgreSQL's `search_path` is the standard mechanism — well-understood

**Cons:**
- Rails migrations must run once per tenant (or via a rake task that loops)
- Sidekiq workers need `search_path` middleware (already partially in place via TenantWorker::Queue)
- Total storage does not decrease — same rows, different namespace
- Cross-schema FK constraints are not enforced by PostgreSQL — application layer handles integrity

---

### Option C — Hybrid (shared schema now, schema-per-tenant for new tenants)

New companies get isolated schemas. Existing companies remain in public until individually migrated.

**Pros:** No big-bang migration; gradual path.

**Cons:** Two code paths for years. Complex. Avoid unless team size and timeline make B impossible.

**Verdict:** **Ruled out.** The incremental middleware approach (Option B with no-op default) achieves the same gradual migration without the dual-code-path problem.

---

### Pre-Migration Phase: Add `company_id` to All Group 4 Tables

**Decision: Backfill `company_id` on all ~70 Group 4 tables before any schema migration begins.**

This is a prerequisite phase, not part of the schema migration itself. The schema migration only starts after every table in Groups 3 and 4 has a direct `company_id` column.

#### Why this is the right call

**Reason 1 — Validation becomes uniform and reliable**

With `company_id` on every table, migration validation is identical for all tables:
```sql
SELECT company_id, COUNT(*) FROM public.table GROUP BY company_id;
-- compare to:
SELECT COUNT(*) FROM tenant_X.table;
```
Without `company_id`, validation requires a custom JOIN per table. 70 custom JOIN-based validation queries, each with its own opportunity for a silent bug.

**Reason 2 — Multi-hop chains are a silent data loss risk**

Group 4 contains chains of 1, 2, and 3 hops:
- 1 hop: `periods → calendar_id → calendars.company_id`
- 2 hops: `rankings → user_commission_id → user_commissions.commission_id → commissions.company_id`
- 3 hops: `ranking_results → ranking_id → rankings → user_commissions → commissions.company_id`

Each hop is an opportunity for an orphaned record to silently drop a row during a JOIN-based migration INSERT. You would not know that data was lost.

**Reason 3 — Polymorphic associations cannot be handled with a single JOIN**

At least 3 tables use polymorphic associations:
- `attachments` — `attachable_type/attachable_id`
- `downloads` — `downloadable_type/downloadable_id`
- `kpi_document_enrollments` — two possible parent FKs (`deal_id` or `modifier_id`)

There is no single JOIN query that handles all polymorphic types. Without `company_id`, migration would require one INSERT per polymorphic type — easy to miss a type, easy to get wrong.

**Reason 4 — Backfill scripts become uniform**

With `company_id` on every table, the schema migration INSERT becomes:
```sql
INSERT INTO tenant_X.table SELECT * FROM public.table WHERE company_id = X;
```
This template works identically for all ~130 tables in Groups 3 and 4. The complexity is paid upfront (once, in the migration scripts), not at migration time under pressure.

#### Backfill approach per tier

Group 4 tables split into 3 tiers by backfill complexity:

**Tier A — Single-hop (estimated ~50 tables):**
One JOIN to the parent table. Simple, low risk.
```sql
UPDATE periods p
  SET company_id = c.company_id
  FROM calendars c
  WHERE p.calendar_id = c.id;
```
Tables: `periods`, `intervals`, `commission_goals`, `commission_payments`, `goal_plans`, `groupifications`, `groupification_histories`, `incentivations`, `incentive_variables`, `plan_variables`, `rankifier_variables`, `requirements`, `reward_funds`, `reward_fund_events`, `rules`, `tracks`, `plan_participation_approvals`, `plan_statement_portables`, `plan_goal_audit_rows`, `plan_statement_audit_rows`, `responsible_audit_rows`, `user_audit_rows`, `calendar_audit_rows`, `user_identifier_audit_rows`, `user_deal_histories`, `user_goal_histories`, `user_groupification_histories`, `user_modifier_histories`, `user_payment_histories`, `user_plan_statement_histories`, `user_seat_histories`, `user_statement_histories`, `variable_track_collections`, `voucher_catalogations`, `voucher_catalogation_histories`, `voucher_catalogation_overrides`, `voucher_orders`, `deal_document_enrollments`, `deal_eligibilities`, `deal_fields`, `deal_field_enrollments`, `document_errors`, `modifier_document_enrollments`, `payroll_events`, `payment_reports`, `payment_exportation_fields`, `collaborative_deal_document_enrollments`, `deal_collaboration_enrollments`, `deal_collaborations`, `approvals`, `user_field_snapshots`, `user_payments`, `commissionings`, `user_commissions`, `voucher_item_orders`, `accumulated_deals`, `aggregated_modifiers`, `commission_creation_events`, `commission_report_creation_events`

**Tier B — Multi-hop (estimated ~15 tables):**
Two or more JOINs required. Higher care needed; run in smaller batches and validate intermediate counts.
```sql
UPDATE ranking_results rr
  SET company_id = c.company_id
  FROM rankings r
  JOIN user_commissions uc ON uc.id = r.user_commission_id
  JOIN commissions c ON c.id = uc.commission_id
  WHERE rr.ranking_id = r.id;
```
Tables: `rankings`, `ranking_results`, `eligible_modifiers`, `modifier_aggregations`, `pre_modifier_aggregations`, `user_payment_type_commissions`, `deal_document_rows`, `group_document_rows`, `variable_tracks`, `eligibility_periods`, `pre_aggregated_modifiers`, `legal_document_acceptances`, `calendar_performance_analyses`

**Tier C — Polymorphic (3 tables):**
Requires one UPDATE per polymorphic type. Must enumerate all types explicitly, validate count per type.
```sql
-- Example for attachments, per type:
UPDATE attachments a
  SET company_id = b.company_id
  FROM commission_report_creation_batches b
  WHERE a.attachable_type = 'CommissionReportCreationBatch'
    AND a.attachable_id = b.id;
-- Repeat for each attachable_type...
```
Tables: `attachments`, `downloads`, `kpi_document_enrollments`

**Enumerating polymorphic types:** Before writing the backfill, query production to get all distinct `attachable_type` values. This avoids assuming types from the codebase.
```sql
SELECT DISTINCT attachable_type, COUNT(*) FROM attachments GROUP BY attachable_type;
```

#### Migration pattern (safe, zero-downtime)

Each of the ~70 tables follows the same Rails migration pattern:

```ruby
# 1. Add column (instant — PostgreSQL adds null column without table rewrite)
add_column :periods, :company_id, :bigint

# 2. Backfill in batches (background job, off-hours)
Period.in_batches(of: 1000).each_with_index do |batch, i|
  batch.update_all(<<~SQL)
    company_id = (SELECT company_id FROM calendars WHERE id = periods.calendar_id)
  SQL
  sleep(0.1) if i % 10 == 0  # yield to avoid replication lag
end

# 3. Add index
add_index :periods, :company_id

# 4. After validation: add not-null constraint (separate migration, after backfill confirmed)
change_column_null :periods, :company_id, false
```

Step 4 is a separate migration deployed only after 100% backfill validation passes.

#### This phase eliminates the Group 3/4 distinction

After this phase, ALL tables being migrated to tenant schemas have a direct `company_id`. The classification simplifies to:
- **Group 1 + 2:** stays in `public` — no change
- **Group 3 + 4 (combined):** all move to `tenant_X` schema using the same `WHERE company_id = X` pattern

---

### Zero-Downtime Migration Strategy (for Option B)

The core constraint: **we cannot take downtime, and we cannot copy the entire database once per company** (that would multiply storage by N tenants).

#### Step 1 — Schema preparation (no data movement yet)

For each company, create a new schema and all table DDLs (without data):

```sql
CREATE SCHEMA tenant_42;
SET search_path = tenant_42;
-- run schema.rb DDL here (empty tables — tenant tables only, see classification below)
```

This is fast, no data copied, no downtime.

#### Step 2 — Logical replication per tenant (live copy without downtime)

Use PostgreSQL **logical replication** or **`pg_logical`** to stream rows from `public.plans WHERE company_id = 42` into `tenant_42.plans`.

PostgreSQL 16+ supports row filters on publications:

```sql
CREATE PUBLICATION tenant_42_pub
  FOR TABLE plans (id, name, ...)
  WHERE (company_id = 42);
```

The subscriber is the same cluster, different schema:

```sql
CREATE SUBSCRIPTION tenant_42_sub
  CONNECTION 'host=localhost dbname=app'
  PUBLICATION tenant_42_pub
  WITH (create_slot = true);
```

This keeps `tenant_42.*` in sync with `public.*` in real time, with no downtime and no full-database copy.

**Important:** Logical replication in the same cluster is possible but requires care (avoid replication loops). Alternatively, use an intermediate script (`pg_logical_emit_message`, `COPY`, or a background Ruby process) to do the initial backfill incrementally.

#### Step 3 — Incremental backfill via batched background jobs

If logical replication on the same cluster is ruled out:

```ruby
# Pseudocode — runs as a background job per company per table
Company.find_each do |company|
  schema = "tenant_#{company.id}"
  Table.where(company_id: company.id).find_in_batches(batch_size: 1000) do |batch|
    execute_insert_into(schema, table_name, batch)
  end
end
```

This is slower than logical replication but simpler operationally. At estimated 1000 rows/sec per table, a company with 1M rows in a single table takes ~17 minutes — acceptable if run off-hours per tenant.

#### Step 4 — Sync during transition (two options)

**Option A — PostgreSQL triggers (recommended for native sync):**

Add one trigger per Group 3+4 table that mirrors every write to the appropriate tenant schema. The trigger checks `company.schema_migrated` and routes dynamically via `company_id`:

```sql
CREATE OR REPLACE FUNCTION sync_to_tenant_schema() RETURNS TRIGGER AS $$
DECLARE
  tenant_schema text;
  is_migrated   boolean;
BEGIN
  SELECT schema_migrated INTO is_migrated
  FROM companies WHERE id = COALESCE(NEW.company_id, OLD.company_id);

  IF NOT is_migrated THEN RETURN COALESCE(NEW, OLD); END IF;  -- no-op

  tenant_schema := 'tenant_' || COALESCE(NEW.company_id, OLD.company_id);

  IF TG_OP = 'DELETE' THEN
    EXECUTE format('DELETE FROM %I.%I WHERE id = $1', tenant_schema, TG_TABLE_NAME) USING OLD.id;
    RETURN OLD;
  ELSE
    -- Generic upsert via dynamic column list
    EXECUTE format(
      'INSERT INTO %I.%I SELECT ($1).* ON CONFLICT (id) DO UPDATE SET ' ||
      (SELECT string_agg(col || ' = EXCLUDED.' || col, ', ')
       FROM (SELECT column_name AS col FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = TG_TABLE_NAME AND column_name != 'id') c),
      tenant_schema, TG_TABLE_NAME
    ) USING NEW;
    RETURN NEW;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Applied once per table (not per tenant):
CREATE TRIGGER sync_plans_to_tenant
  AFTER INSERT OR UPDATE OR DELETE ON public.plans
  FOR EACH ROW EXECUTE FUNCTION sync_to_tenant_schema();
```

**Why triggers, not PostgreSQL logical replication for this case:**

PostgreSQL logical replication was designed for database → database (different servers or databases), not schema → schema within the same database. Within the same database, the subscriber cannot cleanly remap `public.plans` to `tenant_42.plans` without hacks — there is no native schema remapping. Additionally, one subscription per tenant × ~130 tables = thousands of replication slots, which causes WAL retention and performance problems.

Triggers work natively within the same database and route dynamically via `company_id`.

**Cost:** Each write on a public table triggers: 1 SELECT on `companies` (cacheable) + 1 dynamic EXECUTE in the tenant schema. For non-migrated tenants, the trigger is a near-no-op after the `schema_migrated` check.

**Option B — Application-layer dual-write:**

The Rack middleware intercepts writes and replays them in the tenant schema after the primary write. More control, less database overhead, but requires application-level changes during the transition period.

**Option C — Atomic cutover without sync (simplest):**

Skip the dual-write/sync entirely. At cutover time for a tenant:
1. Pause writes briefly (seconds) or use a short transaction window
2. Copy remaining delta rows: `INSERT INTO tenant_X.table SELECT * FROM public.table WHERE company_id = X AND id > last_backfill_id`
3. Flip `schema_migrated = true` in the same transaction
4. Resume writes — they now go to `tenant_X` directly

This eliminates the sync phase entirely. The downside is a short write-pause per tenant cutover, but since cutover is per-tenant and off-hours, this is acceptable.

**Recommendation:** Start with Option C (simplest). If write pause is unacceptable for large tenants, use Option A (triggers) for the transition.

#### Step 5 — Cutover per tenant (rolling, no downtime)

Switch one tenant at a time:

1. Update a feature flag / company attribute: `company.schema_migrated = true`
2. The connection middleware checks this flag and routes to `tenant_X` schema
3. Validate for 24–48 hours
4. Move to next tenant

Since each tenant switch is independent, there is no global downtime window required.

#### Step 6 — Cleanup

After all tenants are migrated:

1. Drop dual-write logic
2. Drop `public` tenant rows (keeping only public tables — see classification below)
3. Remove `company_id` columns from tenant-schema tables (optional, long-term)

---

### Table Classification (complete — 153 tables)

Four groups define the destination of every table in the schema.

#### Group 1 — Truly global / reference data → stays in `public` forever

No company ownership. Never migrated. Visible to all tenants via `search_path`.

| Table | Reason |
|---|---|
| `actions` | Permission action definitions, system-wide |
| `countries` | Geographic reference data |
| `states` | Geographic reference data (belongs to country) |
| `register_types` | Document type reference (belongs to country) |
| `click_through_campaigns` | Global campaign definitions (no company_id) |
| `voucher_categories` | Global voucher taxonomy |
| `voucher_items` | Global voucher catalog |

#### Group 2 — Company identity and configuration → stays in `public` (superadmin visibility)

These tables have `company_id` but exist to configure and identify the company itself. A superadmin needs to query these cross-tenant without navigating through tenant schemas. Keeping them in `public` eliminates any cross-schema query for admin use cases.

| Table | Reason |
|---|---|
| `companies` | The tenant registry — must be in public |
| `company_branches` | 1:1 with company; currency and holding config |
| `company_business_territories` | Company geographic scope |
| `company_tokens` | Company API tokens — admin manages these |
| `authenticator_configurations` | Company SSO configuration |
| `monthly_usages` | Billing/usage per company — admin billing view |
| `monthly_usage_responsibilities` | Billing responsibility tracking |
| `users` | Superadmin needs to find users across companies (support scenarios, email lookup) |

**FK implication:** Because `users` stays in `public`, all tables that reference `users` and live in a tenant schema lose native PostgreSQL FK enforcement. Rails application-layer integrity remains. This is acceptable and mirrors how the app currently works.

The following tables are children of `users` and must also stay in `public`:

| Table | Reason |
|---|---|
| `profiles` | 1:1 with user |
| `fields` | User custom key-value fields |
| `password_resets` | User password reset flow |
| `permissions` | Links user/role to action — needed for auth across context |
| `roles` | Company-scoped role definitions (FK from users via seats) |
| `seats` | User-role hierarchy (FK to role and user) |
| `seat_histories` | Seat change audit trail |
| `user_identifiers` | Company-scoped user identifiers (login credentials) |

#### Group 3 — Tenant operational data with direct `company_id` → moves to `tenant_X` schema

The bulk of the data. Isolated per tenant. `company_id` column is preserved during migration and can be dropped after validation (long-term cleanup).

`acceptment_reasons`, `acceptments`, `audits`, `authenticator_configurations`* (see note), `calendars`, `campaigns`, `click_throughs`, `clients`, `collaborative_deals`, `commission_creation_batches`, `commission_processing_events`, `commission_release_events`, `commission_report_creation_batches`, `commissions`, `deals`, `documents`, `goals`, `groups`, `incentives`, `indicator_document_rows`, `legal_documents`, `metrics`, `modifiers`, `partial_commissions`, `payroll_integrations`, `payroll_requests`, `payrolls`, `payment_exportations`, `payment_types`, `payments`, `performance_analyses`, `performances`, `plan_acceptments`, `plan_participation_approval_batches`, `plan_participations`, `plan_rollbacks`, `plan_slice_commissions`, `plan_slices`, `plan_statement_portable_batches`, `plan_statements`, `plans`, `products`, `rankifiers`, `reward_accounts`, `reward_payments`, `reward_transactions`, `reward_user_payments`, `rewards`, `signatures`, `statements`, `statuses`, `subsidiaries`, `user_histories`, `user_identifier_actions`, `variables`

> **Note on `authenticator_configurations`:** Has `company_id` and is configuration-like, but is a security-sensitive credential. Decision needed: treat as Group 2 (public, admin-managed) or Group 3 (tenant schema, isolated). **Recommendation:** Group 2 (public), since admin manages SSO credentials directly.

#### Group 4 — Tenant data without direct `company_id` (indirect ownership) → moves to `tenant_X` schema

Child tables of Group 3 entities. FK chain leads back to a company. Must migrate together with their parent tables.

| Table | Reaches company via |
|---|---|
| `accumulated_deals` | `user_commission_id → commissions.company_id` |
| `aggregated_modifiers` | `user_commission_id → commissions.company_id` |
| `approvals` | `plan_id → plans.company_id` |
| `attachments` | `commission_report_creation_event_id → ...company_id` (polymorphic) |
| `calendar_audit_rows` | `audit_id → audits.company_id` |
| `calendar_payment_types` | `calendar_id → calendars.company_id` |
| `calendar_performance_analyses` | `calendar_id → calendars.company_id` |
| `collaborative_deal_document_enrollments` | `collaborative_deal_id → collaborative_deals.company_id` |
| `commission_creation_events` | `commission_creation_batch_id → ...company_id` |
| `commission_goals` | `commission_id → commissions.company_id` |
| `commission_payments` | `commission_id → commissions.company_id` |
| `commission_report_creation_events` | `commission_report_creation_batch_id → ...company_id` |
| `commissionings` | `user_commission_id → commissions.company_id` |
| `deal_collaboration_enrollments` | `collaborative_deal_id → collaborative_deals.company_id` |
| `deal_collaborations` | `collaborative_deal_id → company_id` |
| `deal_document_enrollments` | `deal_id → deals.company_id` |
| `deal_document_rows` | `document_id → documents.company_id` |
| `deal_eligibilities` | `deal_id → deals.company_id` |
| `deal_field_enrollments` | `deal_document_id → documents.company_id` |
| `deal_fields` | `deal_id → deals.company_id` |
| `document_errors` | `document_id → documents.company_id` |
| `downloads` | `user_id → users.company_id` (polymorphic downloadable) |
| `eligibility_periods` | `user_commission_id → commissions.company_id` |
| `eligible_modifiers` | `eligibility_period_id → ...company_id` |
| `goal_plans` | `plan_id → plans.company_id` |
| `group_document_rows` | `document_id → documents.company_id` |
| `groupification_histories` | `groupification_id → groups.company_id` |
| `groupifications` | `group_id → groups.company_id` |
| `incentivations` | `plan_id → plans.company_id` |
| `incentive_variables` | `incentive_id → incentives.company_id` |
| `intervals` | `calendar_id → calendars.company_id` |
| `kpi_document_enrollments` | `deal_id / modifier_id → company_id` |
| `legal_document_acceptances` | `user_id → users.company_id` |
| `modifier_aggregations` | `aggregated_modifier_id → user_commissions → company_id` |
| `modifier_document_enrollments` | `modifier_id → modifiers.company_id` |
| `payroll_events` | `payroll_id → payrolls.company_id` |
| `payment_exportation_fields` | `payment_exportation_id → ...company_id` |
| `payment_reports` | `payment_id → payments.company_id` |
| `periods` | `calendar_id → calendars.company_id` |
| `plan_goal_audit_rows` | `audit_id → audits.company_id` |
| `plan_participation_approvals` | `plan_participation_id → plan_participations.company_id` |
| `plan_statement_audit_rows` | `audit_id → audits.company_id` |
| `plan_statement_portables` | `plan_statement_id → plan_statements.company_id` |
| `plan_variables` | `plan_id → plans.company_id` |
| `pre_aggregated_modifiers` | `user_id → users.company_id` |
| `pre_modifier_aggregations` | `pre_aggregated_modifier_id → ...company_id` |
| `rankifier_variables` | `rankifier_id → rankifiers.company_id` |
| `ranking_results` | `ranking_id → user_commissions → company_id` |
| `rankings` | `user_commission_id → commissions.company_id` |
| `requirements` | `plan_participation_id → plan_participations.company_id` |
| `responsible_audit_rows` | `audit_id → audits.company_id` |
| `reward_fund_events` | `reward_fund_id → rewards.company_id` |
| `reward_funds` | `reward_id → rewards.company_id` |
| `rules` | `incentive_id → incentives.company_id` |
| `tracks` | `performance_analysis_id → performance_analyses.company_id` |
| `user_audit_rows` | `audit_id → audits.company_id` |
| `user_commissions` | `commission_id → commissions.company_id` |
| `user_deal_histories` | `user_history_id → user_histories.company_id` |
| `user_field_snapshots` | `plan_statement_id → plan_statements.company_id` |
| `user_goal_histories` | `user_history_id → user_histories.company_id` |
| `user_groupification_histories` | `user_history_id → user_histories.company_id` |
| `user_identifier_audit_rows` | `audit_id → audits.company_id` |
| `user_modifier_histories` | `user_history_id → user_histories.company_id` |
| `user_payment_histories` | `user_history_id → user_histories.company_id` |
| `user_payment_type_commissions` | `user_commission_id → commissions.company_id` |
| `user_payments` | `payment_id → payments.company_id` |
| `user_plan_statement_histories` | `user_history_id → user_histories.company_id` |
| `user_seat_histories` | `user_history_id → user_histories.company_id` |
| `user_statement_histories` | `user_history_id → user_histories.company_id` |
| `variable_track_collections` | `plan_slice_id → plan_slices.company_id` |
| `variable_tracks` | `variable_track_collection_id → ...company_id` |
| `voucher_catalogation_histories` | `voucher_catalogation_id → rewards.company_id` |
| `voucher_catalogation_overrides` | `voucher_catalogation_id → rewards.company_id` |
| `voucher_catalogations` | `reward_id → rewards.company_id` |
| `voucher_item_orders` | `voucher_order_id → reward_accounts.company_id` |
| `voucher_orders` | `reward_account_id → reward_accounts.company_id` |

---

### Frontend Impact Analysis

**Conclusion: The frontend (app-webclient Angular) requires zero changes.**

#### How the frontend communicates with the backend

- All GraphQL queries go to a single API endpoint (`serverUrl: '/api'` — relative path to the same host)
- Authentication is JWT-only: the token is stored in `sessionStorage`/`localStorage` after login and sent as `Authorization: Bearer ...` on every request
- The frontend stores `company_id` locally (from login response) but **never passes it explicitly in GraphQL queries** — the backend derives tenant context from the JWT
- The Apollo client uses a single named connection (`defaultConnection`) pointed at one backend URL

The frontend has **no knowledge of PostgreSQL schemas, tenant isolation, or `search_path`**. All tenant routing is backend-side and transparent to the Angular app.

#### How `identify_company` must work in the middleware

The Rack middleware cannot rely on the HTTP Host header alone because:
- The webclient deploys on per-tenant subdomains (e.g., `acme.app4shark.com.br`) — host-based lookup works for webclient requests
- Mobile apps and API clients may use different host patterns

**Recommended implementation**: decode the JWT from `Authorization` header → `user_id` → `User.find(user_id).company`. This mirrors the existing `JwtAuthorizedController#authenticate!` logic exactly and works for all clients.

An alternative is `Company.find_by("? = ANY(webclient_hosts)", request.host)` — simpler and avoids a DB query for user → company, but only works for webclient sessions. Both approaches can be combined (host-first, JWT fallback).

#### The main company (superadmin) routing decision

Users belonging to `company.main?` (4Shark's own company) currently see all tenants' data with no `company_id` filter — this is enforced entirely by the scope layer, not the frontend.

With schema isolation, the middleware must handle the main company explicitly:

```ruby
def call(env)
  company = identify_company(env)

  if company.nil? || company.main? || !company.schema_migrated?
    @app.call(env)  # no-op: search_path stays at public
  else
    with_schema("tenant_#{company.id}") { @app.call(env) }
  end
end
```

**Why main company users must NOT get a tenant schema set:**
- Their scope resolves with `company.main? → no company_id filter` → returns all visible rows
- If `search_path = tenant_main, public`, Group 3/4 queries return only that tenant's data — not all tenants
- Keeping `search_path = public` means Group 2 tables (users, companies, roles, etc.) return all tenants naturally
- Group 3/4 tables are NOT visible from `public` → main company users see no operational data for other tenants

#### Risk: silent regression for main company users on operational pages

Today, `company.main?` + no `company_id` filter returns ALL rows across all companies — including Group 3/4 tables (deals, commissions, plans, etc.).

After schema isolation with the routing above, main company users will see **no rows** in Group 3/4 tables (since those tables are in tenant schemas, not public). This is only a regression if 4Shark's own admin panel includes pages that list operational data from all tenants simultaneously.

**Required audit before Phase 0 (existing next step):** confirm which pages superadmin users actually access, and whether any of them query Group 3/4 tables cross-tenant. If they do, those pages must either:
1. Be restricted to main-company-specific alternatives (e.g., list companies, not list all deals)
2. Accept that after schema isolation they will only show the main company's own data
3. Be explicitly removed or hidden for main company users

---

### Superadmin Cross-Tenant Access (Decision: Option 3)

**Decision:** Keep company identity and configuration tables in the `public` schema with `company_id` discrimination. A superadmin querying `public.users`, `public.companies`, etc. sees all tenants naturally. No UNION ALL queries, no aggregation layer, no materialized views.

**How it works:**
- Superadmin requests: `search_path = public` (default) — cross-tenant queries work as today
- Regular user requests: `search_path = tenant_X, public` — isolated to their tenant
- The middleware routes based on `company.schema_migrated?` and the authenticated company

**Trade-off accepted:** Tables in Group 2 (`users`, `roles`, `seats`, etc.) retain the row-level `company_id` discriminator permanently. Data isolation for these tables is not schema-level — it is enforced at the application layer, same as today. The isolation benefit applies to all Group 3 and Group 4 tables (the operational data that matters most for leakage risk).

---

### Incremental Middleware Introduction (No Deploy Blocking)

The migration spans weeks to months. Deploys cannot be blocked during this period. The solution: **the middleware is introduced as a no-op and activated per-tenant via a feature flag.**

**Phase 0 (deploy once, immediately):**

```ruby
# app/middleware/tenant_schema_middleware.rb
class TenantSchemaMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    company = identify_company(env)

    if company&.schema_migrated?
      with_schema("tenant_#{company.id}") { @app.call(env) }
    else
      @app.call(env)  # no-op: existing behavior, search_path = public
    end
  end

  private

  def with_schema(schema)
    conn = ActiveRecord::Base.connection
    conn.schema_search_path = "#{schema}, public"
    yield
  ensure
    conn.schema_search_path = "public"
  end

  def identify_company(env)
    # extract company from JWT / session / host — same logic as current auth
  end
end
```

```ruby
# config/application.rb
config.middleware.use TenantSchemaMiddleware
```

**Result:**
- Deployed to all 4 environments with zero behavior change
- `company.schema_migrated` defaults to `false` — all tenants hit the no-op branch
- Data migration runs per-tenant in the background
- When a tenant's migration is complete, flip `schema_migrated = true` — only that tenant is affected
- All other tenants continue with current behavior, deploys are unblocked

The same pattern applies to Sidekiq middleware: add it immediately, activate per-tenant via the same flag.

---

### Multi-Environment Rollout

There are 4 actual environments. Migration runs independently in each one, sequentially from lowest-risk to highest-risk. Completion of one environment is a gate for advancing to the next.

| Order | Environment | Tenants | Data volume | Data type | Risk |
|---|---|---|---|---|---|
| 1 | **Beta** | Unknown (many seeds/POCs) | ~2–3 GB shared | Fake / POC | Low — data loss acceptable |
| 2 | **Demo** | Unknown (many seeds/POCs) | ~2–3 GB shared | Fake / staging | Low — data loss acceptable |
| 3 | **Atento** | 8 tenants | Small (dedicated cluster) | Real production data | Medium — dedicated client |
| 4 | **Shared** | 120–150 tenants | 300+ GB | Real production data | High — multi-client, large scale |

**Environment notes:**

**Beta** — Development/integration environment. All data is seeded, generated, or left over from past POCs. No client data. If a migration goes wrong and data is lost, it can be reseeded. Ideal for validating tooling, middleware boot, and the `schema_migrated` flag flow.

**Demo** — Staging/demo environment. Fake data plus some past POC tenants. Some of these may be ex-clients but the data has no operational value. Same risk profile as Beta. Used to validate the backfill scripts against realistic data shapes (table counts, column diversity) without production risk.

**Atento** — Dedicated cluster for a single enterprise client, split across 8 tenant accounts. Real production data. Migration here must be treated as a production exercise even though the environment is smaller. Used as a low-scale dress rehearsal for real-data migration before tackling Shared.

**Shared** — The critical production environment. 120–150 real tenant companies with live operational data. 300+ GB on disk. This is the most complex migration:
- Highest tenant count (parallelism and tooling must be proven in prior environments first)
- Largest data volume (backfill duration measured in hours per tenant for the largest tenants)
- Peak disk usage: ~500–600 GB during migration (data exists in both `public` and tenant schemas simultaneously before cleanup)
- Rolling cutover strategy is mandatory — no global downtime window is acceptable

**Tenant size tiers for Shared (recommended classification):**

Before starting Shared, classify all 120–150 tenants into tiers based on their row counts in the largest Group 3/4 tables. This allows the migration to proceed small-first and catch scaling issues before hitting the largest tenants.

| Tier | Row count estimate | Suggested cutover order |
|---|---|---|
| Small | < 100k rows total across tenant tables | First — validate the process at scale |
| Medium | 100k – 1M rows | Second — tune batch sizes and parallelism |
| Large | > 1M rows | Last — maximum care, off-hours only |

**Per-environment requirements:**
- Each environment has its own PostgreSQL cluster — migration scripts run independently
- Migration scripts must be parametrized by environment (connection strings, schema names)
- `company.schema_migrated` flag is per-environment (not synced between environments)
- Peak disk capacity must be confirmed before starting: each environment needs ~2× the current data size available during migration
- Shared requires confirming 500–600 GB free before any migration begins

**Advancement criteria (environment N → N+1):**
- All tenants have `schema_migrated = true`
- Row counts in tenant schemas match public schema row counts (per company) within tolerance
- Superadmin cross-tenant queries return correct results from public tables
- No regressions in 48h monitoring window after final tenant cutover in that environment

---

### Rails Infrastructure Changes Required

| Component | Change needed | Effort |
|---|---|---|
| `TenantSchemaMiddleware` (new) | Rack middleware — no-op by default, activates per tenant flag | Low |
| Sidekiq middleware (new) | Same `search_path` logic for background jobs — `company_id` already in job metadata | Low |
| `Company` model | Add `schema_migrated` boolean column (migration) | Low |
| ActionMailer | Ensure tenant context is set before mailer jobs run | Low |
| Migrations | Wrap `db:migrate` in a rake task loop over all active tenant schemas | Medium |
| Admin / superadmin queries | Confirm all admin queries target Group 2 tables (public) — audit required | Medium |
| `schema.rb` | Must remain schema-agnostic (no hardcoded `public.` prefix) | Low — already the case |
| Tests | Each integration test needs tenant schema setup or mock `search_path` | Medium |

---

### Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Data leak during dual-write period | Medium | High | Strict integration tests; row-count reconciliation before cutover |
| Group 4 table left behind (indirect FK chain not traced) | High | High | The Group 4 classification above is exhaustive — verify against schema before starting |
| Admin query hits tenant schema instead of public | Medium | Medium | Audit all admin/superadmin queries before first environment migration |
| Migration loop times out on large tenants | Medium | Low | Batch inserts, off-hours, per-table parallelism |
| Logical replication lag causes stale reads | Low | Medium | Monitor replication lag; only cut over when lag = 0 |
| `schema_migrated` flag flipped prematurely | Low | High | Flip only after row-count validation passes; automated check before flag update |
| Middleware breaks existing auth (identify_company) | Medium | High | Phase 0 middleware is no-op — safe to deploy first and validate identification logic in isolation |
| Environment A migration invalidates assumption for environment B | Low | Medium | Each environment is independent; treat each as a full migration exercise |
| Main company users silently lose cross-tenant operational data | Medium | Medium | Audit superadmin pages before Phase 0; main company users should be routed to `search_path = public` only (see middleware routing decision above) |
| JWT decoding in Rack middleware adds latency | Low | Low | Cache decoded user → company mapping per request (already done in controller layer — extract to shared concern) |

---

### Project Scope, Timeline, and Resource Requirements

#### Why this project is on hold

The migration is technically sound and fully designed. It is on hold because the effort required is not compatible with the current team size. This is not a technical blocker — it is a resource and opportunity-cost decision.

**Resumption condition:** The project becomes viable when 1–2 engineers can be dedicated to it for approximately one year without being pulled into feature development or support.

#### Resource requirements

| Role | Headcount | Duration |
|---|---|---|
| Dedicated backend engineers | 1–2 | ~1 year |
| Part-time DBA support | Shared | During Shared migration only |
| Engineering manager sign-off | — | Before each environment gate |

A single engineer can execute this project but the calendar timeline stretches longer. Two engineers can parallelize the pre-migration phase (adding `company_id` to ~70 tables) and the tooling development.

#### Time estimate (rough breakdown)

All estimates assume 1 dedicated engineer and are calendar-time, not effort-hours. With 2 engineers, some phases can be parallelized.

| Phase | Description | Estimate |
|---|---|---|
| **Pre-migration: company_id backfill** | ~70 migrations across 3 tiers (Tier A/B/C); includes writing, testing, and validating all backfill scripts; batched execution + validation per table | 6–8 weeks |
| **Tooling: middleware + rake tasks** | `TenantSchemaMiddleware`, Sidekiq middleware, multi-tenant migration runner, row-count validation scripts, `schema_migrated` flag infrastructure | 2–3 weeks |
| **Phase 0 deploy (no-op middleware)** | Deploys to all 4 environments, validate `identify_company` works in Rack context, smoke test with `schema_migrated = false` everywhere | 1 week |
| **Beta migration** | Validate all tooling end-to-end; all tenants are low-risk (fake data); expected to expose tooling bugs | 2–3 weeks |
| **Demo migration** | Same as Beta; catches environment-specific issues; slightly more realistic data shapes | 2–3 weeks |
| **Atento migration** | First real-data migration; 8 tenants; treat as a production exercise; includes pre-cutover audit and 48h monitoring | 3–4 weeks |
| **Shared migration (120–150 tenants)** | Tiered by tenant size (small → medium → large); includes disk capacity confirmation, parallelism tuning, and per-tenant cutover with 24–48h monitoring windows | 3–4 months |
| **Public schema cleanup** | Drop tenant rows from `public` after all tenants migrated; remove dual-write logic; optional: drop `company_id` from tenant tables | 2–3 weeks |
| **Buffer and unexpected issues** | Past experience shows 30–50% overhead on infra migrations of this scale | +2 months |

**Total rough estimate: 9–14 months** with 1 dedicated engineer. With 2 engineers working in parallel on the pre-migration and tooling phases, the timeline compresses to approximately 7–10 months.

#### Disk space warning for Shared

The Shared environment currently has 300+ GB on disk. During migration, every row exists in two places simultaneously — in `public` (the source) and in `tenant_X` (the destination). The public rows are only deleted after all tenants are migrated and validated.

**Peak disk estimate:** ~500–600 GB, sustained for weeks during the Shared migration.

**Required action before Shared migration begins:** Confirm that the Shared PostgreSQL cluster has at least 600 GB free (or provision additional storage). This is a hard prerequisite — if disk runs out mid-migration, the database stops accepting writes.

---

## Conclusions

1. **Schema-per-tenant (Option B) is the correct long-term direction.** Chosen. Implementation starts with Phase 0 middleware.

2. **Add `company_id` to all Group 4 tables before any schema migration.** This is a prerequisite phase. The ~70 Group 4 tables have indirect company ownership via FK chains (1–3 hops) and polymorphic associations. Without a direct `company_id`, migration scripts require complex custom JOINs per table that are hard to validate and prone to silent data loss. With `company_id`, the migration becomes uniform: one `WHERE company_id = X` template for all ~130 tables.

3. **After the pre-migration phase, Group 3 and Group 4 merge into a single unified group.** The distinction only existed because of missing `company_id` columns — once added, all migrated tables behave identically.

4. **No full database copy per tenant is needed.** PostgreSQL logical replication (or batched `INSERT INTO ... SELECT`) can populate each schema incrementally, live, without downtime.

5. **Zero-downtime is achievable** via the rolling cutover pattern: create schemas → backfill → dual-write → switch per tenant → cleanup. Each step is reversible.

6. **Superadmin cross-tenant access is solved by Option 3** — keep Groups 1 and 2 in `public`. The ~15 tables in Group 2 retain row-level `company_id` isolation. The ~130+ tables in Groups 3 and 4 get full schema isolation. Net result: no aggregation layer needed, no UNION ALL, no materialized views.

7. **Deploys are never blocked** because the middleware is introduced as a no-op. Migration progress is per-tenant via `schema_migrated` flag. Existing tenants continue unchanged until their migration is complete.

8. **4-environment rollout ensures confidence at each stage.** Beta and Demo validate tooling against fake data safely. Atento is the first real-data dress rehearsal (8 tenants). Shared is the final rolling cutover across 120–150 real tenants and 300+ GB of data.

9. **The frontend requires zero changes.** The Angular webclient is completely unaware of tenant schemas — it sends JWT-authenticated GraphQL queries and receives scoped results. Tenant routing is entirely backend-side and transparent to the frontend. The only behavioral difference visible to the UI is in data volume returned for main company users on Group 3/4 pages (see risk above).

10. **The project is on hold.** The migration is fully designed and technically sound. The blocker is team capacity: the estimated 9–14 months of dedicated engineering effort is not compatible with the current team size. The project is ready to resume when 1–2 engineers can be dedicated to it without competing priorities.

11. **The biggest remaining unknowns before implementation resumes:**
    - Classify Shared tenants into small/medium/large tiers by row count (requires querying production — not accessible without dedicated engineering time)
    - Is logical replication on the same PostgreSQL cluster acceptable, or do we use the atomic cutover approach?
    - **Does 4Shark's admin panel include pages that query Group 3/4 tables for all tenants simultaneously?** (requires audit before Phase 0)
    - Is `authenticator_configurations` treated as Group 2 (public) or Group 3 (tenant)?
    - Should `identify_company` use JWT decoding or Host-header lookup, or both?
    - What are all distinct polymorphic types in `attachments`, `downloads`, and `kpi_document_enrollments`?

---

## Next Steps

> **Project is on hold.** These steps are ordered by execution priority for when dedicated engineering capacity becomes available. No action is expected until then.

### When resources become available — start here

- [ ] **Assign 1–2 dedicated engineers** — no competing feature work during the pre-migration and tooling phases
- [ ] **Confirm disk capacity for Shared** — verify the Shared PostgreSQL cluster has 500–600 GB free before any migration work begins; provision storage if needed
- [ ] **Classify Shared tenants by size** — query production for row counts in the largest Group 3/4 tables per company; classify into small/medium/large tiers to define the rolling cutover order

### Pre-migration phase (prerequisite — must complete before schema migration)

- [ ] **[PRE-MIGRATION] Enumerate polymorphic types** — query production for all distinct `attachable_type` values in `attachments`, `downloads`, and `kpi_document_enrollments` before writing backfill scripts; do not assume from codebase
- [ ] **[PRE-MIGRATION] Add `company_id` to all Group 4 tables** — ~70 migrations in 3 tiers (Tier A: single-hop, Tier B: multi-hop, Tier C: polymorphic); validate 100% backfill coverage per table before declaring done; this phase alone takes 6–8 weeks

### Tooling and infrastructure

- [ ] **Add `schema_migrated` boolean column to `companies`** — prerequisite for the middleware flag; defaults to `false`
- [ ] **Implement Phase 0 middleware** (no-op) — deploy to all 4 environments with `schema_migrated = false` everywhere; validate `identify_company` works correctly in Rack middleware context before any data migration
- [ ] **Confirm `identify_company` strategy** — JWT decoding (universal, all clients) vs. Host-header lookup via `webclient_hosts` (simpler, webclient-only); recommended: JWT-first with host fallback
- [ ] **Write migration backfill rake task** — parametrized by company_id and environment; table list = all Groups 3 + 4 (unified after pre-migration phase)
- [ ] **Prototype atomic cutover on Beta** — validate the copy-delta → flip-flag → resume-writes flow in a safe environment before using it on real data

### Open decisions (answer before execution begins)

- [ ] **Audit main company (superadmin) pages** — identify every page/query accessible to `company.main?` users that reads Group 3/4 tables; decide per page: restrict, remove, or accept behavioral change
- [ ] **Team confirmation: `authenticator_configurations` in Group 2 or Group 3?** — recommendation is Group 2 (stays in public, admin-managed), but needs explicit team sign-off
- [ ] **Sync strategy: atomic cutover (Option C) or triggers (Option A)?** — atomic cutover is simpler and recommended for most tenants; triggers may be needed for Shared's largest tenants to avoid write pauses

### After all decisions are resolved

- [ ] **Define advancement criteria checklist** — formal gate between Beta → Demo → Atento → Shared
- [ ] **Create PLAN.md** for phased implementation based on this spike

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making.
