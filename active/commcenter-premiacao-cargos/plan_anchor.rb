# Phase 0 — PLAN ANCHOR (READ-ONLY). Reach the plan from the user, and the period from the plan.
# Target: app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001
# READ-ONLY. Nothing is mutated.
#
# Plan#calendar carries the periods (plan.rb:8,35), so a competência exists as soon as the calendar
# does — independent of whether a commission was ever cut for it. Anchoring on Commission makes a
# live competência look absent, because the commission is cut later.
#
# Two paths from the user are walked because both are real: his plan statements, and his
# groupifications -> groups -> plans.
#
# Run this first in any new competência: it yields the plan id, the period id, the plan type (which
# decides the metric reduction) and the variables the plan actually consumes.

company_id = 2077
target_user_ids = [1119697, 1119878]    # Alex Lima Lofeu (coordenador), Roberta (líder)
competence_starts_at = Date.new(2026, 7, 1)
competence_ends_at = Date.new(2026, 7, 31)

target_user_ids.each do |target_user_id|
  user = User.find(target_user_id)
  puts "=== user@#{user.id}@#{user.name}"

  statement_plan_ids = PlanStatement.where(user_id: target_user_id).pluck(:plan_id).compact.uniq
  group_ids = Groupification.where(user_id: target_user_id).pluck(:group_id).compact.uniq
  group_plan_ids = Plan.for_company(company_id).where(group_id: group_ids).pluck(:id)

  puts "  plans_from_statements@#{statement_plan_ids.size}@plans_from_groups@#{group_plan_ids.size}"

  (statement_plan_ids | group_plan_ids).each do |plan_id|
    plan = Plan.find(plan_id)
    reached_by = []
    reached_by << 'statement' if statement_plan_ids.include?(plan_id)
    reached_by << 'group' if group_plan_ids.include?(plan_id)

    competence_periods =
      plan.periods.where('periods.ends_at >= ? AND periods.starts_at <= ?', competence_starts_at, competence_ends_at)

    puts "  plan@#{plan.id}@#{plan.name}@type@#{plan.type}@status@#{plan.status}@override@#{plan.override?}" \
         "@shared@#{plan.shared?}@group@#{plan.group_id}@calendar@#{plan.calendar_id}@via@#{reached_by.join('+')}"

    competence_periods.each do |period|
      puts "    period@#{period.id}@#{period.starts_at}@#{period.ends_at}@number@#{period.number}"
    end

    puts "    period@NONE@calendar_periods@#{plan.periods.count}" if competence_periods.none?
    puts "    variables@#{plan.variables.pluck(:id, :key).inspect}"
  rescue StandardError => error
    puts "  plan@#{plan_id}@ERROR: #{error.message}"
  end
end

puts 'PLAN_ANCHOR_DONE'
