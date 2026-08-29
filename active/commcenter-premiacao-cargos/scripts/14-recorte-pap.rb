# Phase 14 — PAP SPLIT (READ-ONLY). Split each Executivo's subtree between the PAP population and the
# rest, and total vendas_instaladas on both sides.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# The cargo carries only PAP revenue, so the mirror source set needs a filter the metric cannot
# provide: the three revenue variables separate by status alone and none of them says where a sale
# came from. The candidate discriminator is the hierarchy — the PAP population is the union of the
# subtrees of the leaders in the Líderes PAP commission.
#
# THE MEASUREMENT DECIDES IT, not the reasoning: the PAP side of Luiz Felipe has to land near
# R$ 15.608,39. The whole subtree is around R$ 19 mil, so a split that reproduces the subtree total
# is a split that filtered nothing.
#
# The status breakdown runs once at company level, unfiltered by status, because the client's own
# discriminator is the "condição de estado" carrying a city name — the labels have to be visible to
# be ruled in or out.

company_id = 2077
competence_period_id = 528210

executivos_plan_id = 79175
lideres_pap_plan_id = 78938

vendas_instaladas_variable_id = 36311

expected_bucket = '4shark-shared-001'

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[pap] wrong stack -- nothing was read'
else
  executivos_plan = Plan.find(executivos_plan_id)
  period = executivos_plan.periods.find(competence_period_id)
  executivos_commission = Commission.for_company(company_id).for_plan(executivos_plan_id).for_period(competence_period_id).first

  lideres_pap_commission = Commission.for_company(company_id).for_plan(lideres_pap_plan_id).for_period(competence_period_id).first
  lideres_pap_user_ids = UserCommission.where(commission_id: lideres_pap_commission.id).pluck(:user_id)

  vendas_instaladas_variable = IndicatorVariable.find(vendas_instaladas_variable_id)
  vendas_instaladas_metric = vendas_instaladas_variable.metric

  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
  puts "lideres_pap@commission@#{lideres_pap_commission.id}@participants@#{lideres_pap_user_ids.size}"

  executivos_plan.variables.with_metrics.each do |variable|
    metric = variable.metric

    puts "metric@#{variable.key}@id@#{metric.id}@status@#{metric.status_id}@client@#{metric.client_id}" \
         "@product@#{metric.product_id}@comparator@#{metric.comparator}@installment@#{metric.installment}"
  end

  UserCommission.where(commission_id: executivos_commission.id).order(:user_id).find_each do |executivo_commission|
    executivo = User.find(executivo_commission.user_id)
    subtree_user_ids = UserScope.new(executivo, User).resolve.pluck(:id) - [executivo.id]

    lideres_in_subtree_ids = lideres_pap_user_ids & subtree_user_ids

    pap_population_ids = []

    lideres_in_subtree_ids.each do |lider_id|
      lider = User.find(lider_id)
      pap_population_ids += UserScope.new(lider, User).resolve.pluck(:id)
    end

    pap_population_ids = pap_population_ids.uniq
    pap_source_ids = subtree_user_ids & pap_population_ids
    remainder_source_ids = subtree_user_ids - pap_population_ids

    puts "executivo@#{executivo.id}@#{executivo.name}@subtree@#{subtree_user_ids.size}" \
         "@lideres_pap@#{lideres_in_subtree_ids.size}@pap_source@#{pap_source_ids.size}" \
         "@remainder@#{remainder_source_ids.size}"

    { 'subtree' => subtree_user_ids, 'pap' => pap_source_ids, 'remainder' => remainder_source_ids }.each do |label, source_ids|
      deals = Deal.for_company(company_id).where(user_id: source_ids).enabled.where(external: true)
      deals = deals.for_type(executivos_plan.deal_type)
      deals = deals.where(date: period.starts_at..period.ends_at)
      deals = deals.for_client(vendas_instaladas_metric.client_id).for_product(vendas_instaladas_metric.product_id)
      deals = deals.where(status_id: vendas_instaladas_metric.status_id) if vendas_instaladas_metric.status_id.to_i.positive?

      if vendas_instaladas_metric.installment.present?
        deals = deals.where("installment #{vendas_instaladas_metric.comparator} ?", vendas_instaladas_metric.installment)
      end

      puts "  #{label}@deals@#{deals.count}@total@#{deals.sum('sold_price * quantity')}"
    end
  rescue StandardError => error
    puts "executivo@#{executivo_commission.user_id}@ERROR: #{error.message}"
  end

  puts '=== status breakdown of every Sale in the competence, company-wide'

  status_totals =
    Deal
    .for_company(company_id)
    .enabled
    .where(external: true)
    .for_type(executivos_plan.deal_type)
    .where(date: period.starts_at..period.ends_at)
    .group(:status_id)
    .sum('sold_price * quantity')

  status_counts =
    Deal
    .for_company(company_id)
    .enabled
    .where(external: true)
    .for_type(executivos_plan.deal_type)
    .where(date: period.starts_at..period.ends_at)
    .group(:status_id)
    .count

  status_names = Status.where(id: status_totals.keys).pluck(:id, :name).to_h

  status_totals.each do |status_id, status_total|
    puts "status@#{status_id}@#{status_names[status_id]}@deals@#{status_counts[status_id]}@total@#{status_total}"
  end

  puts 'PAP_DONE'
end
