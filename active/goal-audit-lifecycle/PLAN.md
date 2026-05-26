# PLAN — Goal Audit Lifecycle Awareness

## Current Situation

- **Relevant context/architecture:**
  - Variable compensation plans follow a lifecycle: Editing → Finalized → (optional) Restarted → Final/Approved
  - Goal audits are spreadsheets generated on demand showing which people have individual goals for each indicator
  - Audits can be generated at any lifecycle state (before/after finalization)
  - Before finalization: audit reflects "possibilities" (people/goals can still change)
  - After finalization: audit reflects definitive data (goals are locked)
  - Plan can be restarted by the creator at any time (except final state), unlinking all goals and returning to editing
  - Approvers review the finalized plan and can request corrections (triggering a restart)
  - Multiple restart cycles can occur, each generating audits that become stale
  - Currently, audits from different lifecycle states look identical, causing confusion

- **Impacted components:**
  - **app (Ruby on Rails):** VariableAudit model, GraphQL schema, Excel export generation
  - **app-webclient (Angular):** Audit listing page, audit generation UI, plan step UI

- **Versions/environment:**
  - Backend: Ruby on Rails, GraphQL API
  - Frontend: Angular, TypeScript, GraphQL

## Objective / Target State

- **Desired outcome:**
  - Audit listing clearly shows: generation date, plan state at generation time, and whether it matches the current plan state
  - Audits matching the current plan state are marked as "current"; all others are "historical"
  - Generation button reflects the nature of the action (preview vs. definitive export)
  - Exported files include header with plan state context (self-documenting)
  - Historical audits remain accessible for comparison but are visually distinct

- **Success metrics / acceptance criteria:**
  - Users can distinguish current from historical audits at a glance in the listing
  - Files shared outside the system carry their own validity context in the header
  - No confusion about audit validity when plan is restarted multiple times
  - Preview audits remain available before finalization (not blocked)

## Problem / New Feature

- **Objective description:**
  Goal audits lack context about the plan lifecycle state at generation time. An audit generated during editing looks identical to one generated after finalization. When plans are restarted (possibly multiple times), old audits become misleading. Files circulate outside the system (email, WhatsApp) without validity context.

- **Symptoms/logs/errors (if any):**
  - User confusion about "which audit to trust" when multiple exist
  - Approvers uncertain about data validity when reviewing plans
  - No technical errors — purely a UX/data context problem

## Challenges, Difficulties and Risks

- **Technical:**
  - Backend currently only generates meaningful audit data after finalization; before finalization the export is blank
  - Backend must be updated to generate preview audits based on current possibilities (all people in groups × all indicators), not just finalized/locked goals
  - Backend must store plan state at audit generation time (snapshot, not live reference)
  - GraphQL schema must expose this new field
  - "Current vs. historical" logic: comparing stored state with plan's current state
  - Excel header generation requires backend changes to include state context

- **Product/UX:**
  - Keep the listing clean — avoid visual clutter with too many badges/columns
  - Button text must be intuitive ("preview" vs "export")
  - Historical audits should be visually de-emphasized but not hidden

- **Security/privacy:**
  - No significant concerns — state info is non-sensitive metadata

- **Performance:**
  - Listing is paginated — rendering state badges is negligible
  - State comparison is a simple string check — no performance impact

## Solution Options (comparative)

### Option 1 — State Snapshot with Current/Historical Flag (Recommended)

- **How it works:**
  - Backend stores `planState` at audit creation time (e.g., "editing", "finalized")
  - Listing page shows three pieces of info per audit: date, plan state at generation, current/historical flag
  - "Current" = audit's stored state matches plan's current state; "Historical" = state changed since generation
  - Generation button: outline/secondary "Gerar prévia da auditoria" (before finalization) vs. primary "Exportar auditoria" (after)
  - Contextual banner on the audit page (warning for preview, success for definitive)
  - Excel export header includes plan name, generation date, state at generation, and warning/confirmation text

- **Pros:**
  - Simple mental model: "does this match the current state? yes = current, no = historical"
  - No complex versioning — the plan's own state is the anchor
  - Historical audits remain visible for comparison
  - Self-documenting exports

- **Cons:**
  - Requires backend schema change (new field on VariableAudit)
  - Adds info to listing table

- **When NOT to use:**
  - If granular revision tracking is needed (e.g., "3rd time in editing phase")

### Option 2 — Version/Revision Number Tracking

- **How it works:**
  - Sequential revision counter incremented on each finalization/restart
  - Audits tagged with revision number
  - Latest revision highlighted as "current"

- **Pros:**
  - Clear chronological ordering

- **Cons:**
  - Revision numbers lack semantic meaning ("Revision 3" tells nothing about state)
  - Doesn't communicate if data is provisional or definitive
  - More complex backend logic
  - Doesn't solve the core problem

- **When NOT to use:**
  - When semantic meaning matters more than sequence

### Option 3 — Block Audit Before Finalization

- **How it works:**
  - Disable audit generation in editing state
  - All audits are definitive by definition

- **Pros:**
  - Simplest solution, eliminates confusion

- **Cons:**
  - Removes valuable preview functionality
  - Large groups (5000+ people) need pre-finalization checks
  - Forces blind finalization

- **When NOT to use:**
  - When preview/validation workflows have business value

## Proposed Steps (high level, don't execute yet)

### For Option 1 (Recommended):

1. **Backend (app):**
   - Enable audit generation before finalization: generate preview data based on current group members × indicators (today it returns blank)
   - Add `plan_state` column to `variable_audits` table (stores plan status at generation time)
   - Populate `plan_state` when creating an audit (snapshot current plan status)
   - Expose `planState` field in GraphQL `VariableAudit` type
   - Add plan state context to Excel export header (warning text for preview, confirmation for definitive)

2. **Frontend (app-webclient):**
   - Update `VariableAudit` model to include `planState`
   - Update GraphQL queries to fetch `planState`
   - Add state and current/historical columns to audit listing
   - Differentiate generation button (text, style) based on current plan state
   - Add contextual banner on audit page
   - Add i18n translation keys

3. **Testing:**
   - Backend: test `plan_state` is correctly stored and exposed
   - Frontend: test listing display, button differentiation, banner logic
   - Integration: test across plan lifecycle states (editing, finalized, restarted, approved)

## Internal References

- Code:
  - **app-webclient:** `/src/app/variable-audit/` (component, service, model), `/src/app/plan/` (plan model/service)
  - **app:** VariableAudit model, GraphQL types, Excel export service (paths TBD — need to explore backend codebase)

- GraphQL:
  - `variableAudits` query (needs `planState`)
  - `variableAuditCreate` mutation (backend stores plan state)
  - `plan` query (for current status comparison)

---

**Question:** Which option do you prefer to follow?
Answer with: `APPROVED: Option 1` **or** `APPROVED: Option 2` **or** `APPROVED: Option 3`.
(Alternative options are welcome, describe if applicable.)
