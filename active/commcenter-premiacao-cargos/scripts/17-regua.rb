# Phase 17 — REVENUE RULE (READ-ONLY). Print every incentive rule of the Executivos plan verbatim,
# beside the inputs its condition reads. Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# Written because a rule was DESCRIBED to the client instead of being read, and the description was
# wrong twice over: the payout base is faturamento_parceiro rather than the revenue the condition
# gates on, and nobody was above 100% of goal. Both are one query away, and the client reads the
# formula rather than a summary of it.
#
# The condition and the payout are DIFFERENT variables in incentive 94277 — the gate is
# (vendas_instaladas + movel) / vendas_instaladas_goal, the multiplier lands on faturamento_parceiro.
# Reading the base off the gate overstates the payment by two orders of magnitude.
#
# Values come from the DEALS rather than from the stored aggregate, because the aggregate is the
# previous processing's answer and the question is what the next one will produce. Both are printed
# side by side so a divergence between them is visible instead of implied.
#
# The goal is resolved the way 11-contagens.rb resolves it: every goal exists twice and only the one
# bound to a plan is real (goal.rb:15,21), so a candidate without plans is skipped.

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_id = 79175
competence_period_id = 528210
vendas_instaladas_variable_id = 36311

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[regua] wrong stack -- nothing was read'
else
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

  puts "plan@#{plan.id}@#{plan.name}@override@#{plan.override?}"
  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
  puts "commission@#{commission.id}@status@#{commission.status}"

  plan.incentives.order(:id).each do |incentive|
    puts "incentive@#{incentive.id}@#{incentive.name}@disabled_at@#{incentive.disabled_at}"

    incentive.rules.order(:id).each do |rule|
      puts "  rule@#{rule.id}@#{rule.type}@#{rule.description}"
      puts "    formula@#{rule.value}"
    end
  end

  UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
    target_user = User.find(user_commission.user_id)

    vendas_instaladas_goal =
      Goal
      .where(company_id: company_id, type: 'UserGoal', group_id: nil)
      .where(variable_id: vendas_instaladas_variable_id)
      .where(user_id: target_user.id)
      .where(starts_at: period.starts_at, ends_at: period.ends_at)
      .find { |candidate_goal| candidate_goal.plans.any? }

    if vendas_instaladas_goal.nil?
      goal_value = 0.0
    else
      goal_value = vendas_instaladas_goal.variable.data_type.format(vendas_instaladas_goal.value).to_f
    end

    puts "target@#{target_user.id}@#{target_user.name}@money@#{user_commission.money}@goal@#{goal_value}"

    value_by_variable_key = {}

    plan.variables.with_metrics.each do |variable|
      metric = variable.metric

      own_deals = Deal.for_company(company_id).for_user(target_user.id).enabled
      own_deals = own_deals.for_type(plan.deal_type)
      own_deals = own_deals.where(date: period.starts_at..period.ends_at)
      own_deals = own_deals.for_client(metric.client_id).for_product(metric.product_id)
      own_deals = own_deals.where(status_id: metric.status_id) if metric.status_id.to_i.positive?
      own_deals = own_deals.where("installment #{metric.comparator} ?", metric.installment) if metric.comparator.present? && metric.installment.present?

      value_by_variable_key[variable.key] = own_deals.sum('sold_price * quantity').to_f

      aggregated_indicator = user_commission.aggregated_indicators.find_by(variable_id: variable.id)

      if aggregated_indicator.nil?
        aggregated_value = 'ABSENT'
      else
        aggregated_value = aggregated_indicator.format.to_s
      end

      puts "  variable@#{variable.id}@#{variable.key}@from_deals@#{value_by_variable_key[variable.key].round(2)}" \
           "@aggregated_now@#{aggregated_value}"
    end

    revenue_base = value_by_variable_key.fetch('vendas_instaladas', 0.0) + value_by_variable_key.fetch('movel', 0.0)

    if goal_value.positive?
      puts "  atingimento@#{(revenue_base / goal_value * 100).round(2)}%@base@#{revenue_base.round(2)}"
    else
      puts "  atingimento@NO_GOAL@base@#{revenue_base.round(2)}"
    end
  rescue StandardError => error
    puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
  end

  puts 'REGUA_DONE'
end
