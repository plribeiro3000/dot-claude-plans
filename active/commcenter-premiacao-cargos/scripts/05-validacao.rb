# Phase 5 — VERIFICATION (READ-ONLY). Prove each target carries the figure it should.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# THE STACK GUARD RUNS FIRST. A console opened against another stack answers every query with zero,
# which reads as "the data is gone" instead of "wrong environment".
#
# RUN IMMEDIATELY AFTER the competence's commission is processed again, and never against a figure
# written down earlier: HierarchyScope has no period window (hierarchy_scope.rb:5-12), so on an
# override plan the expected value is a property of the hierarchy at the instant it is taken. A
# divergence against a stored projection means someone changed manager, not that the mirror is wrong.
#
# The expected value is rebuilt here rather than assumed, and its shape follows the plan:
#   override off -> the target's OWN deals matching the metric; nothing rolls up
#                   (aggregated_indicator.rb:99 reads that one row alone)
#   override on  -> the same own figure PLUS the Indicator row of every other subtree member
#                   (aggregated_indicator.rb:92-97 walks the subtree reading rows that already exist)
#
# Self is recomputed from deals instead of read: the reprocessing rewrites that row, so its stored
# value is the previous run's answer. The other members' rows are read as they stand, because that is
# literally what the walk will find.

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_ids = [78940, 79175]
competence_period_id = 528210

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[verification] wrong stack -- nothing was read'
else
  plan_ids.each do |plan_id|
    plan = Plan.find(plan_id)
    period = plan.periods.find(competence_period_id)
    commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

    puts "plan@#{plan.id}@#{plan.name}@override@#{plan.override?}"
    puts "commission@#{commission.id}@status@#{commission.status}@uuid@#{commission.uuid}"

    UserCommission.where(commission_id: commission.id).order(:user_id).each do |user_commission|
      target_user = User.find(user_commission.user_id)
      subtree_user_ids = HierarchyScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]

      puts "target@#{target_user.id}@#{target_user.name}@money@#{user_commission.money}@subtree@#{subtree_user_ids.size}"

      plan.variables.with_metrics.each do |variable|
        metric = variable.metric

        own_deals = Deal.for_company(company_id).for_user(target_user.id).enabled
        own_deals = own_deals.for_type(plan.deal_type)
        own_deals = own_deals.where(date: period.starts_at..period.ends_at)
        own_deals = own_deals.for_client(metric.client_id).for_product(metric.product_id)
        own_deals = own_deals.where(status_id: metric.status_id) if metric.status_id.to_i.positive?
        own_deals = own_deals.where("installment #{metric.comparator} ?", metric.installment) if metric.comparator.present? && metric.installment.present?

        own_value = own_deals.sum('sold_price * quantity').to_f

        subtree_indicators =
          Indicator
          .for_company(company_id)
          .for_variable(variable.id)
          .where(user_id: subtree_user_ids)
          .where(compiled_at: period.starts_at..period.ends_at)

        if plan.override?
          subtree_value = subtree_indicators.sum { |subtree_indicator| subtree_indicator.format.to_f }
        else
          subtree_value = 0.0
        end

        aggregated_indicator = user_commission.aggregated_indicators.find_by(variable_id: variable.id)

        if aggregated_indicator.nil?
          aggregated_value = 'ABSENT'
        else
          aggregated_value = aggregated_indicator.format.to_s
        end

        puts "  variable@#{variable.id}@#{variable.key}@aggregated@#{aggregated_value}" \
             "@own@#{own_value.round(2)}@carriers@#{subtree_indicators.count}@subtree@#{subtree_value.round(2)}" \
             "@expected@#{(own_value + subtree_value).round(2)}"
      rescue StandardError => error
        puts "  variable@#{variable.id}@ERROR: #{error.message}"
      end
    rescue StandardError => error
      puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
    end
  end

  puts 'VERIFICATION_DONE'
end
