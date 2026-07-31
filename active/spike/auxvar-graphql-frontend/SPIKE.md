# SPIKE — API and front-end validation for auxiliary variables (BE-8, FE-1..FE-4)

> Reference: `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/PLAN.md` and
> `TASKS.md` (engineer-approved). Repositories: `~/Projects/4Shark/app` and
> `~/Projects/4Shark/app-webclient`, branch `develop` in both.
> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).

## Investigation question

Validate, step by step against real documentation and the current `develop` state of both
repositories (which moved under release 3.60.0 on 2026-07-30, the same day this spike runs), the
API and front-end work of the auxiliary-variables feature — task **BE-8** (GraphQL surface) and
tasks **FE-1..FE-4** (`app-webclient`) — so each can be broken into micro-steps with a size signal
for estimation. Specifically: confirm graphql-ruby's additive-vs-breaking rule and whether exposing
`Variable#type` as a plain `String` is genuinely non-breaking; confirm what Apollo/Apollo Angular's
`errorPolicy: 'none'` actually does with a schema-validation error, since a whole rollout-ordering
decision (`TASKS.md:601` — "FE-2 ships strictly after the backend deploy") rests on it; ground the
Angular reactive-forms shape for the "replicate to all rules" action; and confirm what triggers a
Netlify build, whether it can be held, and what rollback looks like.

## Sources consulted

- `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/PLAN.md` (read in full, 408
  lines) — the approved technical decisions, phases 8 and 9, risks, assumptions.
- `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/TASKS.md` (read in full, 874
  lines, paged) — BE-8, FE-1..FE-4 acceptance criteria, sequencing, the stale-line-number note.
- `app/app/models/rule.rb`, `app/app/models/formula.rb` — re-verified every line number BE-4 cites.
- `app/app/models/variable.rb` — the `if: :indicator?` validations that decide which controls an
  auxiliary variable needs on the frontend.
- `app/app/graphql_types/rule_graphql_type.rb`, `rule_input_graphql_type.rb`,
  `variable_graphql_type.rb`, `incentive_variable_graphql_type.rb` — current field/argument lists.
- `app/app/graphql_mutations/create_incentive_graphql_mutation.rb`,
  `update_incentive_graphql_mutation.rb`, `create_easy_variable_graphql_mutation.rb`,
  `create_variable_graphql_mutation.rb` — the rule allow-lists and the two variable-creation
  mutation shapes.
- `app/Gemfile.lock` — `graphql (2.6.2)`, `dentaku (3.5.7)`.
- `app/CHANGELOG.md` — the `## [3.60.0] - 2026-07-30` section.
- `app-webclient/package.json` — `apollo-angular: ^14.0.0`, `@apollo/client: ^4.2.0`,
  `graphql: ^17.0.0`.
- `app-webclient/src/app/rule/*`, `indicator-incentives/{create,update,clone}/*`,
  `plan/create/plan-create-form-builder.service.ts`, `plan/finish/*`,
  `plan-variable/plan-variable-update-form-builder.service.ts`, `plan-variable/plan-variable.model.ts`,
  `variable/{create,update,show}/*`, `variable/create/variable-create-form-builder.service.ts`,
  `easy-product/easy-variable/create/*`, `build.js`, `netlify.toml` — read directly for every code
  claim below.
- See auxiliary: `auxvar-graphql-frontend_sources_1.md` — every fetched external URL with its
  verbatim quote and a confirming re-fetch, per `CITATION-DISCIPLINE.md`.

## Findings

### Finding 1: graphql-ruby's additive-change rule matches TASKS.md's premise

**Evidence:** graphql-ruby's own Changesets documentation states the general rule the plan relies
on for every field/argument addition in BE-8.

**Source:** https://graphql-ruby.org/changesets/overview — *"You can _always_ add new fields, new
arguments, and new types to implement new features and customize existing behavior."* Also, on enum
values specifically: *"if you add a values to an Enum, you can just add it to the existing schema"*.

**Significance:** this grounds BE-8's five additions (an argument on `RuleInputGraphqlType`, a field
on `RuleGraphqlType`, a field on `IncentiveVariableGraphqlType`, and the two mutation allow-list
entries) as non-breaking by the library's own stated policy — no client that doesn't request the new
field/argument is affected. It also confirms that even the more conservative case in the same family
— adding a new *value* to an existing enum — is additive per graphql-ruby, which is one rung more
conservative than what this feature actually needs (a fourth `Variable` type is not modeled as a
GraphQL enum at all, per Finding 2).

### Finding 2: `VariableGraphqlType#type` is verified `String`, not an enum — the claim holds

**Evidence:**

```ruby
# app/app/graphql_types/variable_graphql_type.rb:33
field :type, String, null: false
```

**Source:** `app/app/graphql_types/variable_graphql_type.rb:33`, read directly on `develop`
(2026-07-30, post-3.60.0).

**Significance:** confirms PLAN.md:270's and TASKS.md:493's claim exactly. Combined with Finding 1,
this is a stronger case than "adding an enum value is additive" — there is no enum at the schema
level to enumerate at all, so a fourth string value (`AuxiliaryVariable`) is invisible to schema
introspection and carries zero risk to a client that has hardcoded a `switch` over the three known
values, until that client is updated to recognize the fourth. `Variable.for_type`
(`app/app/models/variable.rb:55`, confirmed present) already backs the resolver's type filter, and
`create_variable_graphql_mutation.rb:4-11,30-40` already lists `type` in both `argument` and
`permit` — so, as TASKS.md:488-492 states, no touch to that mutation is needed for the type to
exist. Confirmed by reading the file; the diff genuinely need not touch it.

### Finding 3: BE-8 micro-step decomposition

**Evidence:** current state of the five files BE-8 touches, read directly.

```ruby
# app/app/graphql_types/rule_input_graphql_type.rb (current, 7 lines)
class RuleInputGraphqlType < InputObjectGraphqlType
  argument :_destroy, Boolean, required: false
  argument :description, String, required: false
  argument :id, ID, required: false
  argument :type, String, required: false
  argument :value, String, required: false
end
```

```ruby
# app/app/graphql_mutations/create_incentive_graphql_mutation.rb:43-47 (current)
rules: %i[
  description
  type
  value
]
```

**Source:** `app/app/graphql_types/rule_input_graphql_type.rb:1-7`,
`app/app/graphql_mutations/create_incentive_graphql_mutation.rb:43-47`,
`update_incentive_graphql_mutation.rb:39-45`, `incentive_variable_graphql_type.rb:1-6`, all read
directly.

**Significance — the ordered micro-steps:**

| # | Step | Code shape | What breaks if skipped | Size |
|---|---|---|---|---|
| 1 | `output_variable_id` argument on `RuleInputGraphqlType` | one `argument :output_variable_id, ID, required: false` line, following the FK-argument naming already used in the same mutation file (`client_id`, `group_id`, `product_id`, `rankifier_id`) — no `output_variable_id` naming precedent exists elsewhere in the GraphQL layer, so this is the first of its kind | Nothing yet; inert until the allow-lists carry it | S |
| 2 | `output_variable` (and/or `output_variable_id`) field on `RuleGraphqlType` | one `field` line, mirroring `incentive_id` (`ID`) next to `incentive` (object) at `rule_graphql_type.rb:6-7` | The API cannot read back what was bound | S |
| 3 | `role` field on `IncentiveVariableGraphqlType` | one `field :role, String, null: true` line | FE-4's picker cannot distinguish an input from an output binding | S |
| 4 | `output_variable_id` added to `create_incentive_graphql_mutation.rb`'s `rules: %i[...]` allow-list | one array entry | **Silent drop.** Rails strong-parameter `permit` on an unlisted key drops it with no error — a rule saved through create with the binding set would simply not persist it | S, high review weight |
| 5 | Same entry added to `update_incentive_graphql_mutation.rb`'s allow-list | one array entry | Same silent-drop failure on update, and this is the mutation a **clone** goes through (there is no dedicated clone mutation — confirmed, no `create_easy_variable`-style dedicated clone mutation exists for incentives) | S, high review weight |
| 6 | Clone round-trip request spec | new example in `graphql_controller_create_incentive_spec.rb` (file confirmed present) asserting a rule created with `output_variable_id` set returns it, simulating the clone builder's payload shape | Nothing breaks by omission, but the risk TASKS.md:479-487 names ("a cloned incentive silently loses its output bindings") has no regression net | M |
| 7 | Confirm no touch to `create_variable_graphql_mutation.rb` / `variable_graphql_type.rb:33` | none — verification only | N/A | verification only |

**Overall BE-8 size**: small in raw lines (~6-10 lines of production code across 5 files), but the
review weight is disproportionate to the line count — steps 4 and 5 are exactly where a silent
allow-list omission would reproduce the clone-loses-binding failure TASKS.md's own decision D5
(`TASKS.md:30`) already names as the reason BE-8 and BE-9 are split into separate PRs.

### Finding 4: Apollo/Apollo Angular `errorPolicy: 'none'` does apply to a validation error, and the failure is total, not partial

**Evidence:** the plan's ordering argument (`TASKS.md:598-602`) is: *"No query selects a field the
server does not have. Apollo is configured with `errorPolicy: 'none'` ... so a partial result is
discarded and the whole screen errors. This is why FE-2 ships strictly after the backend deploy."*

Two Apollo-maintained sources describe the mechanism precisely:

> "If a syntax error or validation error occurs, your server doesn't execute the operation at all
> because it's invalid." — Apollo Client docs (see auxiliary, source 3)

> "Any GraphQL Errors are treated the same as network errors and any data is ignored from the
> response." — Apollo Angular docs, describing the `none` policy verbatim (see auxiliary, source 4)

**Source:** https://raw.githubusercontent.com/apollographql/apollo-client/main/docs/source/data/error-handling.mdx
and https://the-guild.dev/graphql/apollo-angular/docs/data/error-handling — both re-fetched and the
quoted substrings reconfirmed present.

**Significance:** the substantive conclusion in TASKS.md holds and is, if anything, understated. A
query selecting `outputVariableId` before the backend deploy ships is a **validation** error (the
field literally does not exist in the schema) — per the Apollo Client documentation, the server
*does not execute the operation at all* in that case, so there is no partial `data` object to
discard; the response carries only `errors`. `errorPolicy: 'none'` (confirmed as the value in both
`indicator-incentive-create.service.ts:15-28` and `indicator-incentive-permissions.service.ts:16-29`,
read directly) then rejects the promise and surfaces nothing to the UI. One imprecision in the
phrasing worth noting for the reviewer, not a substantive gap: "a partial result is discarded" implies
some data existed and was thrown away; the documentation shows there is no partial result at all in
the validation-error case — the failure is total from the first request. The ordering conclusion
("FE-2 ships strictly after the backend deploy") is unaffected either way, and is if anything *more*
strongly justified: even a query for a single new field alongside many old ones would fail entirely,
not degrade gracefully.

### Finding 5: FE-1 — the generic-screen decision, and why the `EasyVariable` precedent does not transfer

**Decision.** Auxiliary variables join the generic `variable/create` screen, following the Deal
precedent, not the `EasyVariable` dedicated-mutation-and-module precedent. This is not open — it is
decided by 4Shark's own code (source 2 on the resolution ladder in `DECISION-AUTHORITY.md`), and the
reasoning is recorded below.

**Evidence — the generic form builder already carries the mechanism a type without the
indicator-only attributes needs:**

```typescript
// app-webclient/src/app/variable/create/variable-create-form-builder.service.ts:36,46,56
variableCalculation(value: string, require = false): UntypedFormControl {
  const controlValue = value === null ? '' : value;
  const formControl = new UntypedFormControl(controlValue);
  if (require === true) {
    formControl.setValidators([Validators.required]);
  }

  return formControl;
}

variableFrequency(value: string, require = false): UntypedFormControl { /* same shape, :46 */ }

variableOverrideCalculation(value: string, require = false): UntypedFormControl { /* same shape, :56 */ }
```

**Source:** `app-webclient/src/app/variable/create/variable-create-form-builder.service.ts:36-64`,
read directly — each of the three helpers takes a `require = false` default, building an
unrequired, present-but-optional control unless the caller explicitly asks for `require: true`.

```ruby
# app/app/models/variable.rb:32,36,39
validates :calculation, presence: true, if: :indicator?
validates :frequency, presence: true, if: :indicator?
validates :override_calculation, presence: true, if: :indicator?
```

**Source:** `app/app/models/variable.rb:32,36,39`, read directly — all three validations are
`if: :indicator?` only.

**Reasoning.** The screen already accommodates exactly this shape for Deal: `calculation`,
`frequency` and `override_calculation` are validated `if: :indicator?` on the backend model, so a
non-indicator type needs those three controls present (the form always builds them) and not
required (`require` stays `false`). This is not a new construct FE-1 introduces — it is the
mechanism the screen already uses for Deal, and an auxiliary variable is in the identical backend
position (no `if: :indicator?` validation fires for it either).

The `EasyVariable` precedent does not transfer, and the reason is a difference in what the type
*is*, not in what fields it needs: `CreateEasyVariableGraphqlMutation` hardcodes
`variable.type = 'EasyVariable'` server-side (`app/app/graphql_mutations/create_easy_variable_graphql_mutation.rb:19`,
read directly) because Easy is scoped to a company mode — an operator does not choose "Easy" from a
list of peer options, the dedicated `easy-product/` module is Easy's only entry point. Auxiliary is
the opposite: it is chosen among peers on the same screen as Deal and Indicator, per PLAN.md's own
framing (an author picks a `Variable` type when creating one, exactly as they pick Deal or
Indicator today). Following Easy's shape would mean standing up a new
`CreateAuxiliaryVariableGraphqlMutation` and a new dedicated frontend module for a type that needs
neither — Finding 5's own evidence above is what shows the generic screen already has the
accommodation Auxiliary needs, at zero marginal construct cost.

**Micro-steps:**

| # | Step | Size |
|---|---|---|
| 1 | Add `AuxiliaryVariable` option to `variable.component.html:101-102`'s filter select | S |
| 2 | Add it to `variable-create.component.html:30-31` | S |
| 3 | Add it to `variable-update.component.html:30-31` | S |
| 4 | Add `variable.type.options.AuxiliaryVariable` (or equivalent key) to every locale file the other three values already have — locale-file count not enumerated in this spike; confirm before sizing | S–M, pending count |
| 5 | Confirm `changeType()`'s `else` branch fires for the new value (below, verification only) | verification only |
| 6 | CHANGELOG entry (decision D11) | S |

**Verification — `changeType()`'s `else` branch, confirmed by reading the file:**

```typescript
// app-webclient/src/app/variable/create/variable-create.component.ts:104-116
changeType(event: Event) {
  const selectedOption = (event.target as HTMLSelectElement).value;
  if (selectedOption === 'IndicatorVariable') {
    this.form.addControl('calculation', this.formBuilder.variableCalculation(this.variable.calculation, true));
    this.form.addControl('frequency', this.formBuilder.variableFrequency(this.variable.frequency, true));
    this.form.addControl(
      'overrideCalculation',
      this.formBuilder.variableOverrideCalculation(this.variable.overrideCalculation, true),
    );
  } else {
    this.form.removeControl('calculation');
    this.form.removeControl('frequency');
    this.form.removeControl('overrideCalculation');
  }
}
```

**Source:** `app-webclient/src/app/variable/create/variable-create.component.ts:104-116`, read
directly. Confirms an `AuxiliaryVariable` selection hits the `else` branch (no controls added), with
no code change needed to this method — the same conclusion TASKS.md:552-561 already states.

**Overall FE-1 size**: unchanged from TASKS.md's own framing — S, a list-and-locale change with no
new form construct, no new mutation, and no new module.

### Finding 6: FE-2 micro-step decomposition — fifteen sites, confirmed by directory listing

**Evidence:**

```
app-webclient/src/app/indicator-incentives/
├── clone/  (indicator-incentive-clone-form-builder.service.ts, ...)
├── create/ (indicator-incentive-create-form-builder.service.ts, ...)
├── show/
└── update/
```

**Source:** `ls app-webclient/src/app/indicator-incentives/`, read directly — confirms `clone/`,
`create/`, `show/`, `update/` all exist per incentive-type module, matching TASKS.md:584-586's
"fifteen sites" claim (5 incentive types × 3 of the 4 folders — `create`, `update`, `clone` — `show`
is out of scope per TASKS.md:603-605, confirmed correct since `show/` renders read-only and has no
form builder to wire).

```typescript
// app-webclient/src/app/indicator-incentives/create/indicator-incentive-create-form-builder.service.ts:16-27
build(model: IndicatorIncentive): UntypedFormGroup {
  return this.formBuilder.group({
    // ...
    rules: this.ruleFormBuilder.buildArray(),
    type: 'IndicatorIncentive',
  });
}
```

**Source:** confirmed identical shape in the clone builder
(`indicator-incentives/clone/indicator-incentive-clone-form-builder.service.ts:16-27` — both files
read directly, byte-for-byte structurally identical apart from the model import path). This confirms
the mechanism of the clone gap named in BE-8/TASKS.md:589-593: `rule.model.ts`'s shape
(`_destroy`, `description`, `expanded`, `id`, `value`, `type` — read directly, no
`outputVariableId` field today) is shared by every one of the fifteen sites through the same
`RuleCreateFormBuilder` / `RuleUpdateFormBuilder`, so the binding control needs adding in exactly
two files (`rule.model.ts`, `rule-create-form-builder.service.ts`, and
`rule-update-form-builder.service.ts` for the update variant — three files total) rather than
fifteen, and the fifteen sites only need their payload-building method
(`indicator-incentive-create.component.ts:153-165`-shaped) to pass the new field through when set.

**Micro-steps:**

| # | Step | Size |
|---|---|---|
| 1 | Add `outputVariableId` to `Rule` interface/class in `rule.model.ts` | S |
| 2 | Add the control to `RuleCreateFormBuilder.build()` / `.buildArray()` (a `<select>`-bound `FormControl`) | S |
| 3 | Add the same to `RuleUpdateFormBuilder` | S |
| 4 | For each of 5 incentive types, confirm the create/update/clone payload-builder method (the `indicator-incentive-create.component.ts:153-165` shape) passes `outputVariableId` through conditionally, matching the existing `value`/`description` conditional-inclusion pattern | S × 5 types × 3 flows = 15 call sites, mechanically identical once the pattern is set in one |
| 5 | Confirm every one of the 5 `clone/` flows specifically — this is the risk TASKS.md names, and it is the same builder class as `create/` (confirmed structurally identical for indicator), so the fix in step 2 is shared, but the manual verification (clone an incentive with a binding, confirm survival) must be repeated per type | verification, 5× |

**Overall FE-2 size**: M — mechanically small per site once the shared builder is fixed, but breadth
across 5 types × 3 flows makes the manual-verification surface (no automated test convention exists
at this layer, confirmed in Finding 10) the dominant cost, not the code volume.

### Finding 7: FE-3 — Angular's documented `FormArray` primitives support the replicate action, but no named pattern exists for "patch one control across all"

**Evidence:** Angular's own reference confirms the two primitives available — `.controls` (the array
of `AbstractControl`) and `.at(index)` — but documents no higher-level "patch this field across every
item" helper.

**Source:** https://angular.dev/api/forms/FormArray — *"Get the AbstractControl at the given index in
the array."* — and https://angular.dev/guide/forms/reactive-forms — *"FormArray is an alternative to
FormGroup for managing any number of unnamed controls... you can dynamically insert and remove
controls from form array instances."* Both re-fetched.

**Significance:** the "replicate to all rules" action (TASKS.md:608-621) is a plain application of
these primitives — iterate `this.rules.controls` (a `FormArray` of `FormGroup`, since
`RuleCreateFormBuilder.buildArray()` returns an empty `FormArray` that each `build()` call pushes a
`FormGroup` into — confirmed at `rule-create-form-builder.service.ts:14-16`), and call
`.get('outputVariableId').patchValue(sourceValue)` on each. No community-named pattern exists for
this beyond "iterate and patchValue", so there is nothing further to ground — this is a small,
single-method addition on the incentive form component (confirmed to sit "at the incentive form
level, not inside `src/app/rule/`" per TASKS.md:617-618, since the `FormArray` itself lives on each
incentive's form, not the shared rule module).

**Micro-steps:**

| # | Step | Size |
|---|---|---|
| 1 | One method on each of the 5 incentive form components: `replicateOutputVariable(rules: FormArray)` iterating `.controls` and `.patchValue`-ing each | S × 5, mechanically identical |
| 2 | One button/action in each of the 5 templates | S × 5 |
| 3 | Manual verification: bind one rule, replicate, confirm all rules carry it; confirm an unbound rule can still be left unbound after a replicate that was never triggered | verification only |

### Finding 8: FE-4 — ordered micro-steps for the goal-suppression front-end half, and where it sits relative to `PLAN.md`'s decision

**Where this sits.** `PLAN.md:368` already decided that auxiliary variables **do** reach
`plan_variables` — *"Yes, with goal binding suppressed for the type"* — because the read path in
Phase 6/7 requires the row to exist there; withholding the row is not an option BE-3 leaves open.
The consequence is structural: since the backend keeps the row, the only place left to suppress the
goal control is the **UI**. `TASKS.md:210-214` (BE-3) already states the same division: *"The backend
half of goal suppression: the plan-finish path can distinguish an auxiliary `plan_variable`."* ...
*"The frontend half — not rendering the goal control — is FE-4."* This spike's contribution is not a
new decision — it is the three concrete steps that decision requires and that TASKS.md's own
criterion (`TASKS.md:641-644`) states as an outcome without enumerating.

**Step 1 — the query.**

```typescript
// app-webclient/src/app/plan/finish/plan-finish.component.ts:85-99 (current)
getPlanVariables() {
  const query = `query($id: ID) {
    plans(id: $id) {
      nodes {
        id
        actions
        usersCount
        planVariables {
          id
          planId
          goalType
          matchingGroupGoalsCount
          matchingUserGoalsCount
          variable {
            id
            name
```

**Source:** `app-webclient/src/app/plan/finish/plan-finish.component.ts:85-99`, read directly — the
nested `variable { id name }` selection stops short of `type`.

**Code shape:** add `type` inside the nested `variable { }` selection, so the query reads
`variable { id name type }`.

**What breaks if skipped:** the client has no way to know, for any given `plan_variable`, whether its
variable is auxiliary — step 3's template guard would have nothing to test against, and the goal
control would keep rendering for every variable, auxiliary or not.

**How to verify manually:** run the query against a company carrying at least one auxiliary variable
in a plan and confirm the response's `variable` object includes `"type": "AuxiliaryVariable"` for
that row.

**Step 2 — the form control.**

```typescript
// app-webclient/src/app/plan-variable/plan-variable-update-form-builder.service.ts:11-21 (current)
build(model: PlanVariable): UntypedFormGroup {
  return this.formBuilder.group({
    id: this.id(model.id),
    planId: this.planId(model.planId),
    goalType: this.goalType(model.goalType),
    matchingGroupGoalsCount: this.matchingGroupGoalsCount(model.matchingGroupGoalsCount),
    matchingUserGoalsCount: this.matchingUserGoalsCount(model.matchingUserGoalsCount),
    variableId: this.variableId(model.variable.id),
    variableName: this.variableName(model.variable.name),
  });
}
```

**Source:** `app-webclient/src/app/plan-variable/plan-variable-update-form-builder.service.ts:11-21`,
read directly — the builder flattens `model.variable` into `variableId` / `variableName` controls
only; `Variable.type` already exists on the shared model
(`app-webclient/src/app/variable/variable.model.ts:20,38`, confirmed present) but nothing here reads
it.

**Code shape:** add a `variableType: this.variableType(model.variable.type)` entry to the group,
mirroring the existing `variableId`/`variableName` disabled-control shape.

**What breaks if skipped:** step 1's query field arrives in the GraphQL response but never reaches
the form, so the template in step 3 has no control to guard on.

**How to verify manually:** in the browser dev tools, inspect the built `FormGroup` for a
`planVariable` row known to be auxiliary and confirm a `variableType` control exists with value
`AuxiliaryVariable`.

**Step 3 — the template guard.**

```html
<!-- app-webclient/src/app/plan/finish/plan-finish.component.html:48-58 (current) -->
<span class="column-xl">
  <select (change)="changeGoalType($event, planVariable)">
    <option value="">{{ 'forms.none' | translate }}</option>
    <option *ngIf="planVariable.get('matchingGroupGoalsCount').value > 0" value="GroupGoal">
      {{ 'goal.type.options.GroupGoal' | translate }}
    </option>
    <option *ngIf="planVariable.get('matchingUserGoalsCount').value > 0" value="UserGoal">
      {{ 'goal.type.options.UserGoal' | translate }}
    </option>
  </select>
</span>
```

**Source:** `app-webclient/src/app/plan/finish/plan-finish.component.html:48-58`, read directly — the
`<select>` renders unconditionally today for every `plan_variable` row.

**Code shape:** wrap the `<span>`/`<select>` block in
`*ngIf="planVariable.get('variableType').value !== 'AuxiliaryVariable'"` — a guard around the whole
block, not an option inside it, since an auxiliary row should offer no goal-type choice at all
(unlike FE-1's list-only change, this is a template-structure change, not a list entry).

**What breaks if skipped:** the goal-type `<select>` keeps rendering for an auxiliary variable, and
an operator could set a `goalType` on a row `PlanVariable#goals_presence`
(`app/models/plan_variable.rb:32-39`) validates as optional but that the domain never intends to
carry one — the UI would offer a choice the feature's own design says should not exist.

**How to verify manually:** open the plan-finish screen for a plan containing an auxiliary variable
and confirm no goal-type dropdown renders for that row, while a non-auxiliary row's dropdown is
unaffected.

**Step 4 — the plan-create picker (Finding 8's remaining, less-specified piece).**

**Code shape:** extend whatever component consumes `IncentivationCreateFormBuilderService`
(`plan-create/plan-create-form-builder.service.ts:23`) to read the new `role` field on
`IncentiveVariableGraphqlType` (Finding 3, step 3) and filter the incentive options offered.

**What breaks if skipped:** the picker keeps offering every incentive regardless of whether its
auxiliary reads have an exporter earlier in the plan — not a correctness bug (BE-5's backend
validation still rejects an incompatible plan), but the UX guidance TASKS.md:634-637 describes would
be absent.

**How to verify manually:** build a plan whose incentives combine an exporter and a reader in the
wrong stage order and confirm the **backend** validation (BE-5) rejects it regardless of what the
picker offered — the picker is UX, not the guarantee, exactly as TASKS.md:638-640 states.

**Size**: no existing "filter compatible related records" precedent was found anywhere in
`app-webclient` for step 4 — the filtering logic itself needs to be designed fresh, which is why it
carries a larger size signal (M) than steps 1-3 (each S).

| # | Step | Size |
|---|---|---|
| 1 | Add `type` to the `variable { }` selection in the plan-finish query | S |
| 2 | Add `variableType` control to `PlanVariableUpdateFormBuilderService` | S |
| 3 | Guard the `<select>` block with `*ngIf` on the new control | S |
| 4 | Plan-create picker: filter by `role` | M |
| 5 | Manual verification of the backend guarantee (BE-5) independent of the picker | verification only |

### Finding 9: Netlify build trigger, lock, and rollback — TASKS.md's ROLLOUT-1 language is one degree less precise than the documented mechanism

**Evidence:** ROLLOUT-1's stated rollback (TASKS.md:705) is *"Rollback is a Netlify redeploy of the
previous build, per site."*

**Source — what "redeploy" actually is:**

> "If you need to roll back, you can publish one of the previous deploys listed in the UI as the live
> version of your site in production. Use the Publish Deploy button on the detail page of any
> successful deploy. This doesn't trigger a new deploy but instead publishes a previous atomic deploy
> that is still available to you." — https://docs.netlify.com/deploy/manage-deploys/manage-deploys-overview/
> (re-fetched, quote confirmed present)

> "Rollbacks are instantaneous." — same page.

**Source — what triggers a build in the first place:**

> "By default, Netlify deploys your site's production branch after every merge to the production
> branch." — https://docs.netlify.com/site-deploys/overview/ (re-fetched, quote confirmed present)

**Source — locking (holding) a deploy:**

> "Locked deploys give you the ability of pinning a site to the latest published deploy for the time
> being. New deploys won't be published to the main site, although Netlify will still build them and
> they will be ready for whenever you want to publish them." — same manage-deploys page.

**Significance:** the documented mechanism is not a "redeploy" in the sense of re-running the build —
it is **Publish Deploy**, which re-points production traffic at an already-built, already-cached
atomic deploy with no rebuild step, and Netlify's own copy calls this "instantaneous". "Redeploy"
could be misread by an engineer executing ROLLOUT-1 as "trigger a fresh build of the old commit",
which is slower and unnecessary — the correct action is the **Publish Deploy** button on the
previous deploy's detail page. This is a precision refinement to record in ROLLOUT-1, not a
contradiction: the outcome ("the old frontend is live again") is identical either way, and PLAN.md's
own text (`PLAN.md:338`) already says "Rollback path confirmed: a Netlify redeploy of the previous
build, per site" using the same loose term. Separately, the documentation confirms PLAN.md:331's
claim that "which branch each site tracks lives in each site's Netlify settings rather than in the
repository" — production-branch configuration is confirmed to live at *"Project configuration >
Build & deploy > Continuous Deployment > Branches and deploy contexts"*, a per-site UI setting, not
`netlify.toml` (confirmed: the fetched `netlify.toml` carries `[build]`, `[[redirects]]`,
`[[headers]]` blocks only — no `[context.*]` block, matching PLAN.md's own reading).

### Finding 10: `app/models/rule.rb` and `formula.rb` line-number citations in BE-4 are all confirmed current

**Evidence:** direct `grep -n` against the file on `develop` (post-3.60.0, same day as this spike):

```
76:  def formula_syntax
100:  def indicator_syntax
119:  def ranking_syntax
145:  def limiter_syntax
166:  def redemption_syntax
177:  def validate_syntax(options = {})
187:  def metrics_options
207:  def deal_extra_fields_options
213:  def indicator_variables_options
221:  def easy_variables_options
```

**Source:** `app/app/models/rule.rb`, read directly, `grep -n` against every method BE-4 cites.
Every number matches TASKS.md:239-248's `187,207,213,221` (the four builders) and the surrounding
validator line numbers exactly. `app/app/models/formula.rb`'s `referenced_identifiers` (lines 10-12)
and `error` (lines 14-21) also match TASKS.md's citation exactly.

**Significance:** BE-4 can proceed on the cited line numbers with no re-verification needed at
implementation time — TASKS.md's own "Stale `rule.rb` line numbers" section (`TASKS.md:822-833`) had
already flagged the file's history of drift and stated the current numbers were re-verified for that
document; this spike independently reproduces the same re-verification and confirms it.

### Finding 11: one line-citation discrepancy in `PLAN.md`, unrelated to BE-8/FE-1..4 but caught in the same file-move check

**Evidence:**

```
## [3.60.0] - 2026-07-30

### Added

- Bulk user update by spreadsheet
- Identification of the variables a formula references     ← line 27

### Changed

- Rule validation message when the formula has a syntax problem     ← line 31
```

**Source:** `app/CHANGELOG.md:20-31`, read directly.

**Significance:** `PLAN.md:170` cited *"`app/CHANGELOG.md:32` records it as 'Identification of the
variables a formula references'"* — the actual line is **27**, not 32. `TASKS.md:831`'s separate
citation of `app/CHANGELOG.md:31` for *"Rule validation message when the formula has a syntax
problem"* is correct as written. This is a minor, isolated citation slip in `PLAN.md` (off by five
lines, the same file-shift magnitude the rest of `PLAN.md`/`TASKS.md` already discuss for
`rule.rb`) — it does not affect any BE-8/FE-1..4 decision, since neither task cites this
CHANGELOG line for anything actionable.

### Finding 12: the `app-webclient` test-surface claim (seven `.spec.ts` files) is confirmed exactly

**Evidence:**

```
app.component.spec.ts
cropper-dialog/cropper-dialog.component.spec.ts
core/http/error-handler.interceptor.spec.ts
core/http/api-prefix.interceptor.spec.ts
core/http/http-cache.service.spec.ts
core/http/cache.interceptor.spec.ts
core/http/http.service.spec.ts
```

**Source:** `find app-webclient/src -name "*.spec.ts"`, read directly — seven files, none under
`rule/`, `indicator-incentives/`, `plan/`, or `variable/`.

**Significance:** confirms TASKS.md:795-800's claim exactly — there is no test convention at the
feature-component/form-builder/service layer in `app-webclient`, so every FE-1..FE-4 verification
criterion is correctly scoped to a manual checklist rather than an automated test, per
`~/.claude/docs/TESTING-PHILOSOPHY.md`'s "read 2-3 similar existing test files" instruction having
nothing to read at this layer.

## Trade-offs surfaced

| Approach (Netlify rollback wording) | Pros | Cons | Source |
|---|---|---|---|
| "Redeploy the previous build" (current ROLLOUT-1/PLAN.md phrasing) | Familiar, generic term | Could be read as "trigger a new build from the old commit" — slower and unnecessary | Finding 9 |
| "Publish the previous deploy" (Netlify's own terminology) | Matches the documented, instantaneous mechanism exactly | Requires the reader to know Netlify's specific UI term | Finding 9 |

## What remains uncertain

- The i18n locale-file count for FE-1's new `variable.type.options.AuxiliaryVariable` key was not
  enumerated in this spike (out of the stated scope: API and front-end *work validation*, not a
  full locale-file audit) — confirm the file count before finalizing FE-1's size signal.
- FE-4's plan-create picker (Finding 8, step 4) has no existing "filter compatible related records"
  precedent anywhere in `app-webclient` that this spike found — the filtering logic itself needs to
  be designed fresh, not adapted from a sibling.
- Whether `output_variable_id` is the right GraphQL argument/field name (Finding 3) was chosen by
  this spike from the surrounding naming convention (`client_id`, `group_id`, `product_id`,
  `rankifier_id` on the same mutation), not confirmed against any existing precedent for an
  `output_*` prefixed FK argument — none exists in the codebase today.
- Two proposal decks named in the background SPIKE (`incentive-calculated-variables/SPIKE.md` §6)
  remain unreviewed per `PLAN.md:402` — if either constrains the authoring surface's visual design,
  FE-1/FE-2's estimates in this spike should be re-checked against it.

## Suggested options for main and the engineer

- Option A (Netlify wording): update ROLLOUT-1's rollback language from "redeploy" to "publish the
  previous deploy" to match the documented, instantaneous mechanism precisely — a documentation-only
  change with no effect on the actual rollback action already planned.
- Option B (FE-4 query/model gap): fold Finding 8's four ordered micro-steps (query field, form
  control, template guard, picker filter) into FE-4's acceptance criteria before implementation
  starts, since the first three are necessary for the stated criterion to be achievable at all.

(No recommendation — surface options, let main and the engineer choose.)
