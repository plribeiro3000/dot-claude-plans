# Phase 2 — CONJUNTOS (READ-ONLY). Which notion of "below me" the calculation actually reads.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# Three different notions of "below me" exist in this codebase and they are NOT interchangeable:
#   Plan#subordinate_ids_by (plan.rb:214-225) — SeatHistory whose parent_id is the person's seat,
#     bounded by the period window. Commission#subordinate_ids (commission.rb:260-275) and
#     Commission::DealOptionsProcessor (deal_options_processor.rb:15-20) build the same query, so
#     THIS is what the override calculation reads.
#   User#subordinate_ids (user.rb:407-409) — seat.subordinates, a has_many of Seat on itself.
#   UserScope -> HierarchyScope (hierarchy_scope.rb:5-12) — WITH RECURSIVE over seats.parent_id.
#
# Run this when a cargo's numbers do not add up and the reason is not obvious. It prints all three
# with the deal total each produces under the plan's own metric filter, so which set matches is
# read off the output instead of deduced from a method name.
#
# THE SETS ARE NOT NESTED. The calculation reads seat HISTORY inside the period, so someone who
# changed manager mid-competence counts on both sides — one executive showed 31 people in the
# calculation set against 29 in the current subtree. Any subtraction between them is by user id,
# never by total.
#
# The aggregated figure a commission already carries is NOT a reference to calibrate against when
# that commission ran before the latest data corrections: it was compiled at that instant and does
# not follow deal or hierarchy changes since.

company_id = 2077
plan_id = 79175
competence_period_id = 528210
metric_variable_id = 36311

plan = Plan.find(plan_id)
period = plan.periods.find(competence_period_id)
commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first
metric_variable = Variable.find(metric_variable_id)
metric = metric_variable.metric

deal_total_for =
  lambda do |user_ids|
    deals = Deal.for_company(company_id).where(user_id: user_ids).enabled.where(external: true)
    deals = deals.for_type(plan.deal_type)
    deals = deals.where(date: period.starts_at..period.ends_at)
    deals = deals.for_client(metric.client_id).for_product(metric.product_id)
    deals = deals.where(status_id: metric.status_id) if metric.status_id.to_i.positive?
    deals = deals.where("installment #{metric.comparator} ?", metric.installment) if metric.installment.present?
    [deals.count, deals.sum('sold_price * quantity')]
  end

UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
  target_user = User.find(user_commission.user_id)

  calculation_ids = plan.subordinate_ids_by(user_id: target_user.id, starts_at: period.starts_at, ends_at: period.ends_at).uniq.compact
  seat_association_ids = target_user.subordinate_ids.uniq.compact
  recursive_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]
  remainder_ids = recursive_ids - calculation_ids

  aggregated_indicator = user_commission.aggregated_indicators.find_by(variable_id: metric_variable.id)

  if aggregated_indicator.nil?
    aggregated_value = 'ABSENT'
  else
    aggregated_value = aggregated_indicator.format
  end

  calculation_count, calculation_total = deal_total_for.call(calculation_ids)
  seat_association_count, seat_association_total = deal_total_for.call(seat_association_ids)
  recursive_count, recursive_total = deal_total_for.call(recursive_ids)
  remainder_count, remainder_total = deal_total_for.call(remainder_ids)

  puts "target@#{target_user.id}@#{target_user.name}@seat@#{target_user.seat.id}"
  puts "  aggregated_today@#{aggregated_value}"
  puts "  plan_subordinate_ids_by@#{calculation_ids.size}@deals@#{calculation_count}@total@#{calculation_total}"
  puts "  user_subordinate_ids@#{seat_association_ids.size}@deals@#{seat_association_count}@total@#{seat_association_total}"
  puts "  hierarchy_recursive@#{recursive_ids.size}@deals@#{recursive_count}@total@#{recursive_total}"
  puts "  remainder_recursive_minus_calculation@#{remainder_ids.size}@deals@#{remainder_count}@total@#{remainder_total}"
rescue StandardError => error
  puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
end

puts 'CONJUNTOS_DONE'
