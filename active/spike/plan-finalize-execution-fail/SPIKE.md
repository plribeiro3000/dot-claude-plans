# SPIKE — Plan finalization "Execution fail!" (Atento report)

## Investigation question

Camila (support, #suporte) reported that Atento Brasil cannot finalize a plan — "Passo 2: Indicadores e Metas" returns the generic **"Execution fail!"**. Atento's calendar has a **single period**. Camila's reproduction hypothesis on demo: the user created **two incentivações pointing to the same incentive** (duplicate incentive), finalized without touching metas, and got the error.

Question: where does the failure actually originate — frontend, backend, or the duplicate-incentive path — and what (if anything) still needs fixing after the current develop release?

## Sources consulted

- `app-webclient` `src/app/plan/finish/plan-finish.component.ts` — the finalize page; fires `finishPlan(id, planVariablesAttributes)` and its error handler shows `err.errors[0].message` (the generic string).
- `app-webclient` `src/app/plan/update/plan-update.component.ts` (master vs develop) — where incentivações are added to a plan.
- `app` `app/graphql_mutations/finish_plan_graphql_mutation.rb:10-16` — the mutation; `Plan.find(id)` then `plan.finalize(...)`.
- `app` `app/models/plan.rb` — `after_create :create_variables` (:151), `finalize` (:339-347), `variable_ids` (:445-451, `.uniq`), `update_variables` (:454-458).
- `app` `app/models/plan_variable.rb:32-39` — `goals_presence` validation.
- `app` `app/services/matching_group_goals_counter.rb`, `matching_user_goals_counter.rb` — the goal counters.
- `app` `app/models/incentivation.rb:20` + `db/schema.rb:947` — the unique constraint on `incentivations(plan_id, incentive_id)`.

## Findings

### Finding 1: The generic "Execution fail!" is a presentation artifact, not the cause

**Evidence:** `Plan#finalize` rescues `ActiveRecord::RecordInvalid` and replaces the specific error with a plan-level base error:

```ruby
def finalize(plan_variables_attributes)
  transaction do
    update!(plan_variables_attributes)
    update!(finished_at: Time.zone.now)
    finish_registration!
  end
rescue ActiveRecord::RecordInvalid
  errors.add(:base, :invalid)
end
```

`ApplicationMutation#respond_with` then raises `GraphQL::ExecutionError.new('Execution fail!', extensions: record.errors.to_hash)`, so the real message lands in `extensions` while the user sees the hardcoded string.

**Source:** `app` `app/models/plan.rb:339-347`; `app/graphql_mutations/application_mutation.rb` (`respond_with`).

**Significance:** The user-visible string never identifies which validation failed. The real error for a goal problem is `plan_variable` `goal_type: :missing_goal` (`goals_presence`), stranded in `extensions`.

### Finding 2: Frontend bug confirmed on master, already fixed on develop

**Evidence:** On master the plan form lets you add the **same incentive more than once** — `getIncentives` sends no `ignore`, and neither `addIncentivation` (`:334-337`) nor `selectIncentive` (`:389`) checks whether the incentive is already selected. On develop, commit `b374746d6` ("feat(plan): group incentives by type on the plan form") added the guard: `selectIncentive` returns early via `if (this.isIncentiveSelected(event.id)) return;` (`:432-435`), the search excludes already-selected incentives with `ignore: this.activeIncentiveIds()` (`:408`), and `activeIncentiveIds`/`isIncentiveSelected` live at `:687-693`.

**Source:** `app-webclient` `src/app/plan/update/plan-update.component.ts` (master vs develop); `git show b374746d6`.

**Significance:** The next release carries the frontend fix — the UI will no longer let the user select a duplicate incentive.

### Finding 3: The plan is already persisted when the finalize page loads

**Evidence:** `finishPlan` requires `id: ID!` and runs `Plan.find(id)` (`finish_plan_graphql_mutation.rb:10-11`); the finalize page loads an existing plan via `plans(id: $id)`. `plan_variables` are created in `after_create :create_variables` (`plan.rb:151`). `finalize` does not rebuild variables — `update_variables` is `before_update` and returns early unless `changed_incentive_ids.any?` (`plan.rb:454-455`), which finalize does not trigger.

**Source:** `app` `app/graphql_mutations/finish_plan_graphql_mutation.rb:10-11`, `app/models/plan.rb:151,454-458`.

**Significance:** The plan (and its incentivações + plan_variables) exist before finalize. So any constraint on incentivações already applied at plan create/update time, not at finalize. Finalize only writes `goal_type` onto existing plan_variables.

### Finding 4: Duplicate incentivações do not double the plan_variables, and the backend intends to reject them outright

**Evidence:** `Plan#variable_ids` is `.uniq`, so `create_variables` builds one plan_variable per unique variable regardless of duplicate incentivações (`plan.rb:445-451`). The goal counters count `Goal` rows by variable + group/user + dates, independent of incentivação count (`matching_group_goals_counter.rb`, `matching_user_goals_counter.rb`). Separately, `Incentivation` declares `rescue_unique_constraint index: :index_incentivations_on_plan_id_and_incentive_id, field: :incentive_id` (`incentivation.rb:20`), and `schema.rb:947` declares that index `unique: true`. The engineer confirmed the index exists in the demo DB.

**Source:** `app` `app/models/plan.rb:445-451`, `app/models/incentivation.rb:20`, `db/schema.rb:947`.

**Significance:** With the unique index present, a second incentivação to the same incentive should raise on INSERT, be caught by `rescue_unique_constraint`, and fail the plan save at Passo 1 — the backend should not let a plan with duplicate incentivações be created at all. And even if one existed, `.uniq` means the finalize `goals_presence` path is unaffected. So the "doubled meta expectation at finalize" hypothesis does not hold in the code.

## Trade-offs surfaced

| Theory tried | Why it was ruled out |
|---|---|
| Surface the `extensions` message via a toast on finalize (first attempt) | The engineer rejected it — the fix belongs in the form marking the offending meta, not a global error toast. |
| GroupGoal option offered when `matchingGroupGoalsCount != plan.periods.count` (multi-period coverage) | Only bites with more than one period; Atento is single-period, so this is not Atento's bug. |
| Duplicate incentive doubles the meta expectation at finalize | Contradicts the code: `variable_ids.uniq` keeps plan_variables unique, finalize does not reprocess incentivações, and the unique index should stop the duplicate at creation. |

## What remains uncertain

- With the unique index present and the plan persisted before finalize, it is unclear how Camila persisted a plan with duplicate incentivações on demo. Either the duplicate never actually persisted (and what she saw was two distinct incentive records, i.e. a copied incentive, or the error was a different single-period case), or there is a record that slipped past the index. This is the one fact the code cannot settle — it needs the demo data.

## Suggested options for main and the engineer

- **Next step (read-only, decides everything):** run the console check on the demo `bin/ecs run`. If `duplicate_incentivations` returns zero, the index is doing its job and the "duplication" was something else; the `would_fail` column shows, per meta, whether `goals_presence` would break, pointing at the real single-period cause. If it returns pairs, a duplicate persisted despite the index and that record is the lead.

```ruby
connection = ActiveRecord::Base.connection
incentivation_index = connection.indexes(:incentivations).find { |index| index.columns.sort == %w[incentive_id plan_id] }
puts "== unique index on incentivations(plan_id, incentive_id) =="
if incentivation_index
  puts "present, unique=#{incentivation_index.unique}"
else
  puts "MISSING"
end

puts "\n== plans with more than one incentivation for the same incentive =="
duplicate_incentivations = Incentivation.group(:plan_id, :incentive_id).having('COUNT(*) > 1').count
puts "affected pairs: #{duplicate_incentivations.size}"
duplicate_incentivations.each do |(plan_id, incentive_id), total|
  puts "plan_id=#{plan_id} incentive_id=#{incentive_id} incentivations=#{total}"
end

puts "\n== goals_presence evaluation on the affected plans =="
affected_plan_ids = duplicate_incentivations.keys.map { |pair| pair.first }.uniq
Plan.where(id: affected_plan_ids).each do |plan|
  periods_total = plan.periods.count
  puts "plan_id=#{plan.id} periods=#{periods_total} finished_at=#{plan.finished_at.inspect}"
  plan.plan_variables.each do |plan_variable|
    group_total = MatchingGroupGoalsCounter.new(plan_variable: plan_variable).call
    user_total = MatchingUserGoalsCounter.new(plan_variable: plan_variable).call
    would_fail =
      if plan_variable.goal_type.blank?
        false
      elsif plan_variable.group_goal?
        group_total != periods_total
      elsif plan_variable.user_goal?
        !user_total.positive?
      else
        false
      end
    puts "  variable_id=#{plan_variable.variable_id} goal_type=#{plan_variable.goal_type.inspect} group=#{group_total} user=#{user_total} periods=#{periods_total} would_fail=#{would_fail}"
  end
end
```

- **Backend fix, conditional on the check:** if the index is `MISSING` on demo (schema drift), add the migration that creates the unique index — the `rescue_unique_constraint` is already in place to turn the violation into a validation error. If the index is present and no duplicates exist, no backend change is needed and the frontend fix (already on develop) closes the reported case.
- **Independent of the above — worth deciding separately:** whether to also surface the real `extensions` message on the finalize page so a future `missing_goal` (or any validation) stops showing "Execution fail!". This is the presentation gap from Finding 1; the engineer rejected the toast shape, so any such fix must mark the specific meta in the form rather than show a global message.
