# Phase 13 — ERRATA (READ-ONLY). The anchors of the plan that apures the Executivos, printed beside
# the plan it replaces. Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# Every Executivo anchor in 01/03/05/07/08/09/10/11 names the superseded plan, so nothing about the
# cargo can be re-run before this answers three things: which commission is live, which variables it
# carries, and whether the revenue rule still leaves 80%-100% uncovered while both rules fire above
# 100%.
#
# The stored value of each variable without metric is printed as it stands, raw column included: hc
# was corrected by hand to zero, and a pass that recomputes it with the summing definition writes
# R$ 1.000 back onto four Executivos without anything reporting an error.

company_id = 2077
competence_period_id = 528210
plan_ids = [79175, 78939]
count_variable_ids = [36927, 36928, 36480, 36929, 36940]

expected_bucket = '4shark-shared-001'

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[errata] wrong stack -- nothing was read'
else
  plan_ids.each do |plan_id|
    plan = Plan.find_by(id: plan_id)

    if plan.nil?
      puts "plan@#{plan_id}@ABSENT"
      next
    end

    period = plan.periods.find_by(id: competence_period_id)

    puts "plan@#{plan.id}@#{plan.name}@type@#{plan.type}@status@#{plan.status}@deal_type@#{plan.deal_type}" \
         "@override@#{plan.override?}@group@#{plan.group_id}@calendar@#{plan.calendar_id}@disabled_at@#{plan.disabled_at}"
    puts "  variables_with_metrics@#{plan.variables.with_metrics.pluck(:id, :key).inspect}"
    puts "  variables_all@#{plan.variables.pluck(:id, :key).inspect}"

    plan.incentives.order(:id).each do |incentive|
      puts "  incentive@#{incentive.id}@#{incentive.name}@disabled_at@#{incentive.disabled_at}"

      incentive.rules.order(:id).each do |rule|
        puts "    rule@#{rule.id}@#{rule.type}@#{rule.description}"
        puts "      value@#{rule.value}"
      end
    end

    if period.nil?
      puts "  period@#{competence_period_id}@NOT_IN_CALENDAR"
      next
    end

    puts "  period@#{period.id}@#{period.starts_at}@#{period.ends_at}"

    commission = Commission.for_company(company_id).for_plan(plan.id).for_period(competence_period_id).first

    if commission.nil?
      puts '  commission@NOT_CUT'
      next
    end

    puts "  commission@#{commission.id}@status@#{commission.status}@uuid@#{commission.uuid}" \
         "@participants@#{commission.user_commissions.count}@disabled_at@#{commission.disabled_at}"

    UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
      target_user = User.find(user_commission.user_id)

      mirrors_on_target =
        Deal
        .for_company(company_id)
        .where(user_id: target_user.id)
        .where(date: period.starts_at..period.ends_at)
        .where(external: false)
        .enabled

      puts "  target@#{target_user.id}@#{target_user.name}@money@#{user_commission.money}" \
           "@mirrors@#{mirrors_on_target.count}@total@#{mirrors_on_target.sum('sold_price * quantity')}"

      plan.variables.with_metrics.each do |variable|
        aggregated_indicator = user_commission.aggregated_indicators.find_by(variable_id: variable.id)

        if aggregated_indicator.nil?
          puts "    aggregated@#{variable.key}@ABSENT"
        else
          puts "    aggregated@#{variable.key}@#{aggregated_indicator.format}"
        end
      end

      count_variable_ids.each do |count_variable_id|
        variable = IndicatorVariable.find_by(id: count_variable_id)

        if variable.nil?
          puts "    indicator@#{count_variable_id}@VARIABLE_ABSENT"
          next
        end

        stored_indicator =
          Indicator
          .for_company(company_id)
          .for_variable(count_variable_id)
          .where(user_id: target_user.id)
          .where(compiled_at: period.starts_at..period.ends_at)
          .first

        if stored_indicator.nil?
          puts "    indicator@#{variable.key}@ABSENT"
        else
          puts "    indicator@#{variable.key}@#{stored_indicator.format}@raw@#{stored_indicator.value.inspect}" \
               "@external@#{stored_indicator.external}@destroyable@#{stored_indicator.destroyable?}"
        end
      end
    rescue StandardError => error
      puts "  target@#{user_commission.user_id}@ERROR: #{error.message}"
    end
  rescue StandardError => error
    puts "plan@#{plan_id}@ERROR: #{error.message}"
  end
end

puts 'ERRATA_DONE'
