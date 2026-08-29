# Phase 15 — PAP GAP (READ-ONLY). Enumerate everything the PAP cut leaves out of one Executivo, so a
# difference against the client's own figure is attributed to a record instead of dismissed.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# A difference of a few reais between two totals is not rounding — deal values are stored to the
# cent and every sum here is exact. It is a record present on one side and absent on the other, and
# the only way to name it is to list the candidates.
#
# The manager of each excluded seller is printed because the PAP population is derived from the
# leaders who PARTICIPATE in the Líderes PAP commission: a leader who leads PAP without a
# participation carries the whole team into the excluded side, and nothing else would reveal it.

company_id = 2077
competence_period_id = 528210

executivos_plan_id = 79175
lideres_pap_plan_id = 78938

vendas_instaladas_variable_id = 36311

target_user_id = 1243772
reference_total = 15608.39

expected_bucket = '4shark-shared-001'

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[gap] wrong stack -- nothing was read'
else
  executivos_plan = Plan.find(executivos_plan_id)
  period = executivos_plan.periods.find(competence_period_id)

  lideres_pap_commission = Commission.for_company(company_id).for_plan(lideres_pap_plan_id).for_period(competence_period_id).first
  lideres_pap_user_ids = UserCommission.where(commission_id: lideres_pap_commission.id).pluck(:user_id)

  vendas_instaladas_variable = IndicatorVariable.find(vendas_instaladas_variable_id)
  vendas_instaladas_metric = vendas_instaladas_variable.metric

  target_user = User.find(target_user_id)
  subtree_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]
  lideres_in_subtree_ids = lideres_pap_user_ids & subtree_user_ids

  pap_population_ids = []

  lideres_in_subtree_ids.each do |lider_id|
    lider = User.find(lider_id)
    pap_population_ids += UserScope.new(lider, User).resolve.pluck(:id)
  end

  pap_population_ids = pap_population_ids.uniq
  pap_source_ids = subtree_user_ids & pap_population_ids
  remainder_source_ids = subtree_user_ids - pap_population_ids

  metric_deals =
    Deal
    .for_company(company_id)
    .enabled
    .where(external: true)
    .for_type(executivos_plan.deal_type)
    .where(date: period.starts_at..period.ends_at)
    .for_client(vendas_instaladas_metric.client_id)
    .for_product(vendas_instaladas_metric.product_id)

  if vendas_instaladas_metric.status_id.to_i.positive?
    metric_deals = metric_deals.where(status_id: vendas_instaladas_metric.status_id)
  end

  if vendas_instaladas_metric.installment.present?
    metric_deals = metric_deals.where("installment #{vendas_instaladas_metric.comparator} ?", vendas_instaladas_metric.installment)
  end

  pap_total = metric_deals.where(user_id: pap_source_ids).sum('sold_price * quantity')

  puts "target@#{target_user.id}@#{target_user.name}@subtree@#{subtree_user_ids.size}" \
       "@pap_source@#{pap_source_ids.size}@remainder@#{remainder_source_ids.size}"
  puts "pap_total@#{pap_total}@reference@#{reference_total}@gap@#{(reference_total - pap_total).round(2)}"

  puts '=== PAP leaders inside the subtree'

  lideres_in_subtree_ids.sort.each do |lider_id|
    lider = User.find(lider_id)
    lider_subtree_ids = UserScope.new(lider, User).resolve.pluck(:id)
    lider_total = metric_deals.where(user_id: lider_subtree_ids).sum('sold_price * quantity')

    puts "lider@#{lider.id}@#{lider.name}@subtree@#{lider_subtree_ids.size}@total@#{lider_total}"
  end

  puts '=== excluded sellers, with the manager that put them outside PAP'

  excluded_totals = metric_deals.where(user_id: remainder_source_ids).group(:user_id).sum('sold_price * quantity')
  excluded_counts = metric_deals.where(user_id: remainder_source_ids).group(:user_id).count

  excluded_totals.each do |seller_id, seller_total|
    seller = User.find(seller_id)
    seat = seller.seat
    manager_label = 'NO_SEAT'

    if seat.present? && seat.parent_type == 'Seat'
      parent_seat = Seat.find_by(id: seat.parent_id)
      manager_label = 'PARENT_WITHOUT_USER'

      if parent_seat.present? && parent_seat.user_id.present?
        manager = User.find(parent_seat.user_id)
        manager_in_pap_commission = lideres_pap_user_ids.include?(manager.id)
        manager_label = "#{manager.id}:#{manager.name}:in_pap_commission=#{manager_in_pap_commission}"
      end
    end

    puts "excluded@#{seller.id}@#{seller.name}@deals@#{excluded_counts[seller_id]}@total@#{seller_total}@manager@#{manager_label}"
  end

  puts '=== every excluded deal, one line each'

  metric_deals.where(user_id: remainder_source_ids).order(:id).pluck(:id).each do |deal_id|
    deal = Deal.find(deal_id)
    seller = User.find(deal.user_id)

    puts "deal@#{deal.id}@external_id@#{deal.external_id}@seller@#{seller.id}@#{seller.name}" \
         "@date@#{deal.date}@installment@#{deal.installment}@quantity@#{deal.quantity}" \
         "@sold_price@#{deal.sold_price}@total@#{deal.sold_price * deal.quantity}"
  end

  puts '=== the Executivo own deals matching the metric'

  own_total = metric_deals.where(user_id: target_user.id).sum('sold_price * quantity')

  puts "own@deals@#{metric_deals.where(user_id: target_user.id).count}@total@#{own_total}"

  puts '=== deals in the whole subtree whose value is exactly the gap'

  gap_value = (reference_total - pap_total).round(2)

  metric_deals
    .where(user_id: subtree_user_ids + [target_user.id])
    .where('sold_price * quantity = ?', gap_value)
    .order(:id)
    .pluck(:id)
    .each do |deal_id|
      deal = Deal.find(deal_id)
      seller = User.find(deal.user_id)
      in_pap = pap_source_ids.include?(deal.user_id)

      puts "gap_candidate@#{deal.id}@seller@#{seller.id}@#{seller.name}@in_pap@#{in_pap}" \
           "@date@#{deal.date}@total@#{deal.sold_price * deal.quantity}"
    end

  puts '=== disabled deals in the PAP set, which the metric skips and a spreadsheet may not'

  Deal
    .for_company(company_id)
    .where(user_id: pap_source_ids)
    .where(external: true)
    .for_type(executivos_plan.deal_type)
    .where(date: period.starts_at..period.ends_at)
    .where(status_id: vendas_instaladas_metric.status_id)
    .where.not(disabled_at: nil)
    .order(:id)
    .pluck(:id)
    .each do |deal_id|
      deal = Deal.find(deal_id)
      seller = User.find(deal.user_id)

      puts "disabled@#{deal.id}@seller@#{seller.id}@#{seller.name}@date@#{deal.date}" \
           "@total@#{deal.sold_price * deal.quantity}@disabled_at@#{deal.disabled_at}"
    end

  puts 'GAP_DONE'
end
