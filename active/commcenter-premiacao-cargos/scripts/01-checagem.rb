# Phase 1 — CHECAGEM (READ-ONLY). Confirm every anchor before the reconciliation.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# Nothing here is taken from a document. The plan is reached FROM the participants of its own
# commission, the period from plan.calendar, the variables from the plan — and each answer is
# printed so a divergence is visible instead of being carried into the projection.
#
# Three environment gates are printed first. A console opened against another stack answers every
# query with zero, which reads as "the data is gone" instead of "wrong environment". Without the
# external column on deals nothing below can run at all; search_index on means the metric reads deal
# ids from an index keyed by commission_uuid (deal_search_index.rb:7-8), so no mirror moves a figure
# until that commission is processed again.
#
# reaches_other_target and mirrors_already_in_subtree are what decide whether this cargo can be
# mirrored safely: a target sitting above another target already holds that target's mirrors, and
# mirroring them again pays the same revenue twice.

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_ids = [78940, 79175]
competence_period_id = 528210

# Targets already carrying mirrors in the other cargos of this apuração. The Gerentes sit above the
# Executivos and the Coordenador, so these ids are expected to show up inside their subtrees — what
# keeps that from paying twice is the external: true filter on the source set in 10-reconciliacao.rb.
other_target_user_ids = [1119697, 1026105, 1119698, 1119699, 1119700, 1243772]

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[checagem] wrong stack -- nothing was read'
else
  puts "gate@external_column@#{Deal.column_names.include?('external')}"
  puts "gate@search_index@#{ApplicationConfiguration.search_index?}"

  plan_ids.each do |plan_id|
    plan = Plan.find(plan_id)
    period = plan.periods.find(competence_period_id)
    commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

    puts "plan@#{plan.id}@#{plan.name}@type@#{plan.type}@status@#{plan.status}@deal_type@#{plan.deal_type}" \
         "@override@#{plan.override?}@group@#{plan.group_id}@calendar@#{plan.calendar_id}"
    puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
    puts "variables_with_metrics@#{plan.variables.with_metrics.pluck(:id, :key).inspect}"
    puts "variables_all@#{plan.variables.pluck(:id, :key).inspect}"

    if commission.nil?
      puts 'commission@NOT_CUT'
      next
    end

    puts "commission@#{commission.id}@status@#{commission.status}@uuid@#{commission.uuid}" \
         "@participants@#{commission.user_commissions.count}"

    UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
      target_user = User.find(user_commission.user_id)
      identifier_values = UserIdentifier.where(company_id: company_id, user_id: target_user.id).pluck(:value)
      subtree_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]
      already_delivered_user_ids = plan.subordinate_ids_by(user_id: target_user.id, starts_at: period.starts_at, ends_at: period.ends_at).uniq.compact

      existing_mirrors_on_target =
        Deal
        .for_company(company_id)
        .where(user_id: target_user.id)
        .where(date: period.starts_at..period.ends_at)
        .where(external: false)
        .enabled

      mirrors_in_subtree =
        Deal
        .for_company(company_id)
        .where(user_id: subtree_user_ids)
        .where(date: period.starts_at..period.ends_at)
        .where(external: false)
        .enabled

      puts "target@#{target_user.id}@#{target_user.name}@identifiers@#{identifier_values.inspect}" \
           "@disabled_at@#{target_user.disabled_at}@money@#{user_commission.money}"
      puts "  subtree@#{subtree_user_ids.size}@already_delivered_by_override@#{already_delivered_user_ids.size}" \
           "@source@#{(subtree_user_ids - already_delivered_user_ids).size}"
      puts "  reaches_other_target@#{(other_target_user_ids & subtree_user_ids).inspect}"
      puts "  mirrors_already_on_target@#{existing_mirrors_on_target.count}" \
           "@total@#{existing_mirrors_on_target.sum('sold_price * quantity')}"
      puts "  mirrors_already_in_subtree@#{mirrors_in_subtree.count}@total@#{mirrors_in_subtree.sum('sold_price * quantity')}"

      plan.variables.with_metrics.each do |variable|
        aggregated_indicator = user_commission.aggregated_indicators.find_by(variable_id: variable.id)

        if aggregated_indicator.nil?
          puts "    variable@#{variable.id}@#{variable.key}@aggregated_today@ABSENT"
        else
          puts "    variable@#{variable.id}@#{variable.key}@aggregated_today@#{aggregated_indicator.format}"
        end
      end
    rescue StandardError => error
      puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
    end
  end

  puts 'CHECAGEM_DONE'
end
