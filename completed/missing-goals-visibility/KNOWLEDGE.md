# KNOWLEDGE - Missing Goals Visibility

## The Problem

The goal finalization dashboard (dashboard-plan) displays indicators showing aggregated numbers about goal assignment status (e.g., "40 goals out of 50 eligible people"). However, **the system does not show WHICH specific people are missing goals**. This makes it impossible for plan administrators to:
- Identify which employees still need goals assigned
- Take corrective action to complete goal assignment
- Contact specific people who haven't received goals
- Ensure 100% goal coverage before finalizing the plan period

This is a **visibility problem** - the data exists (the system knows the count), but users cannot see the details needed to take action.

## Current State

### How It Works Today

**Frontend (app-webclient):**
- Component: `src/app/dashboard/plan/dashboard-plan.component.ts`
- Template: `src/app/dashboard/plan/dashboard-plan.component.html` (lines 369-536)
- Model: `src/app/goal-dataset/goal-dataset.model.ts`

**Current GraphQL Query:**
```graphql
query {
  goalDatasets(periodId: "...", planId: "...", userId: "...") {
    nodes {
      baseline
      count              # Number of goals registered
      formattedBaseline
      formattedGoal
      formattedValue
      goal
      lastUpdateAt
      value
      variableId
      variableName
      variableType
    }
  }
}
```

**What's Displayed:**
- Aggregated metrics per indicator (variable)
- Count of registered goals
- Current result vs. goal vs. baseline
- Progress bar for goal achievement
- Historical indicator charts

**What's Missing:**
- List of eligible users/employees
- Which specific users have goals assigned
- Which specific users are missing goals
- User details (name, email, position, etc.)

### What Works Well

- Clean visual representation of goal progress
- Easy-to-understand aggregated numbers
- Existing goal upload functionality through GoalDocument feature
- Excel-based bulk upload already implemented
- GraphQL API structure is extensible

### Pain Points

- **No visibility into missing goals**: Administrator sees "40/50" but doesn't know which 10 people are missing
- **Manual investigation required**: Need to check each employee individually
- **Time-consuming**: For large teams (50+ people), finding missing assignments is impractical
- **Risk of incomplete plans**: Plans may be finalized without complete goal coverage
- **No actionable data**: Numbers without details don't enable corrective action

### Difficulties

- Backend API currently returns only aggregated data (count)
- No existing endpoint to retrieve list of users without goals
- Need to determine "eligible users" per indicator (not all users qualify for all indicators)
- Must maintain performance with large datasets (100+ users, 50+ indicators)

## Domain Concepts

| Term | Definition |
|------|------------|
| **Goal** | A target value assigned to an employee for a specific indicator/variable during a period |
| **Indicator** | A measurable metric/variable (e.g., "Total Sales", "Call Volume") |
| **Variable** | Technical term for Indicator - represents a data point that can have goals |
| **Goal Dataset** | Aggregated data about goals for a specific variable/indicator in a period |
| **Eligible User** | An employee who should have a goal assigned for a specific indicator |
| **Plan** | A compensation/commission plan with multiple indicators and goals |
| **Period** | Time range for which goals are set (e.g., monthly, quarterly) |
| **Goal Document** | Excel file used for bulk uploading goals (existing feature) |
| **Individual Goal** | Goal assigned to a single employee (GoalType: "IndividualGoal") |
| **Group Goal** | Goal assigned to a team/group of employees (GoalType: "GroupGoal") |
| **Goal Finalization** | Process of reviewing and completing goal assignments before period starts |
| **Dashboard Plan** | Administrative view showing plan status and goal progress |

## Proposed Solution

### User Workflow

1. Administrator opens dashboard-plan page
2. Views indicator cards showing:
   - Total eligible users for that indicator
   - Total users with goals assigned
   - Gap: "40 out of 50 have goals" → 10 missing
3. Clicks "Export Pending" button on indicator card
4. Downloads Excel file containing ONLY users WITHOUT goals
5. Excel format matches existing GoalDocument template
6. Administrator fills in goal values in Excel
7. Uploads filled Excel using existing GoalDocument upload feature

### Technical Requirements

**Backend API Changes:**
- Extend `goalDatasets` query OR create new query
- Return list of eligible users without goals per indicator
- User data needed: ID, name, email (minimum)
- Filter by: periodId, planId, variableId
- Performance consideration: pagination or reasonable limit

**Frontend Changes:**
- Update indicator card UI to show counts clearly
- Add "Export Pending" button per indicator
- Generate Excel file client-side with missing users
- Excel format must match GoalDocument template structure
- No changes needed to upload functionality (already exists)

**Data Flow:**
```
Backend (Rails) → GraphQL API → Frontend (Angular) → Excel Export → User fills → Upload (existing)
```

## Constraints

**Technical:**
- Must use existing GraphQL API architecture
- Excel format must match GoalDocument import expectations
- Performance: queries must handle 100+ users, 50+ indicators
- Frontend export must work client-side (no backend export endpoint initially)

**Business:**
- Only users with proper permissions should see missing users
- Goal documents already have approval workflow
- Cannot bypass existing security/audit controls
- Must preserve existing upload validation logic

**Data:**
- "Eligible users" definition varies by indicator/variable type
- Group goals vs. individual goals affect eligibility
- User permissions affect who can be assigned goals
- Existing goal data must not be duplicated or overwritten

## Open Questions

1. **Eligibility Definition**: How does the system determine which users are "eligible" for a specific indicator?
   - Is it based on user role/position?
   - Plan participant list?
   - Variable configuration?
   - Group membership?

2. **Group Goals**: How should the export handle group goals vs. individual goals?
   - Should group goals show all group members?
   - Should export only show users needing individual goals?

3. **Excel Format**: Does the GoalDocument template vary by goal type or indicator type?
   - What columns are required?
   - Are there different templates for different scenarios?

4. **Performance**: What are acceptable query response times?
   - Should we paginate results?
   - Is there a practical upper limit on team size?

5. **Export Scope**: Should export include:
   - Only missing users? (proposed)
   - All eligible users with status indicator?
   - Additional metadata (existing goals, baselines)?

6. **Backend First**: Since frontend depends on API contract, backend development must complete first
   - What should the GraphQL query structure look like?
   - Should it be a new query or extend existing `goalDatasets`?
   - What fields are needed in the response?

## Key Insights

- This is a **reporting/visibility feature**, not a new business process
- Leverages **existing upload infrastructure** - no new import logic needed
- Problem is in the **API layer** - frontend just displays what backend provides
- Excel export is a **bridge** between visibility and action
- Success depends on correctly defining **"eligible users"** per indicator
- **Backend must be implemented first** to define data contract
- Frontend implementation is relatively straightforward once API is ready

## Technical Discovery Needed

Before planning can proceed, need to understand:
1. Backend model: How are eligible users determined? (Rails app investigation)
2. Goal types: Exact logic for individual vs. group goals
3. Excel template: Current GoalDocument import format and validation rules
4. API contract: Optimal GraphQL query design for this data

---

**Status:** READY FOR BACKEND DISCOVERY

**Next Steps:**
1. Investigate Rails backend to understand eligibility logic
2. Review GoalDocument import format and validation
3. Design GraphQL API contract
4. Begin backend implementation first
5. Frontend implementation after API is ready
