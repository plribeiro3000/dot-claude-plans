# Phase 1 — PRE-FLIGHT (READ-ONLY). Mirror every deal below the target onto the target.
# Target: app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001
# READ-ONLY. Nothing is mutated. Writes one CSV to the environment's own bucket.
#
# Anchored on the target's own plan: the period comes from plan.calendar (plan.rb:8,35), the
# variables from plan.variables narrowed to the metric-backed ones, and the reduction from the plan
# class — Metric::TotalAdapter reduces a SalesPlan by sold_price * quantity (total_adapter.rb:18-22).
#
# Override rolls up ONE level only, so it cannot reach the team below the immediate subordinate.
# The source set is therefore the target's whole subtree, resolved by UserScope -> HierarchyScope
# (a WITH RECURSIVE walk over seats.parent_id), minus the target himself so a re-run never mirrors
# its own mirrors.
#
# The mutation must not run until every row reports length_ok=YES and already_exists=false.

require 'csv'

company_id = 2077
aws_bucket = ApplicationConfiguration.aws_bucket

target_user_id = 1119697    # Alex Lima Lofeu
target_plan_id = 78941      # Remuneração Variável Coordenador de Call Center Julho 26
target_period_id = 528210   # 2026-07-01..2026-07-31

if aws_bucket.blank?
  puts '[preflight] AWS_BUCKET is not configured in this environment'
else
  target_user = User.find(target_user_id)
  plan = Plan.find(target_plan_id)
  period = plan.periods.find(target_period_id)
  subtree_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user_id]
  metric_variables = plan.variables.with_metrics

  puts "target@#{target_user.id}@#{target_user.name}"
  puts "plan@#{plan.id}@#{plan.name}@type@#{plan.type}@deal_type@#{plan.deal_type}@override@#{plan.override?}"
  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
  puts "subtree@#{subtree_user_ids.size}@metric_variables@#{metric_variables.pluck(:id, :key).inspect}"

  rows = []

  metric_variables.each do |variable|
    metric = variable.metric

    original_deals = Deal.for_company(company_id).where(user_id: subtree_user_ids).enabled
    original_deals = original_deals.for_type(plan.deal_type)
    original_deals = original_deals.where(date: period.starts_at..period.ends_at)
    original_deals = original_deals.for_client(metric.client_id).for_product(metric.product_id)
    original_deals = original_deals.where(status_id: metric.status_id) if metric.status_id.to_i.positive?
    original_deals = original_deals.where("installment #{metric.comparator} ?", metric.installment) if metric.installment.present?

    if metric.interval?
      original_deals = original_deals.where('EXTRACT(DAY FROM date) BETWEEN ? AND ?', metric.starts_at, metric.ends_at)
    end

    # sold_price and quantity are decimal columns (schema.rb:720-721), so the database reduces them.
    # modifiers.value is NOT — never SUM() that one in SQL.
    deal_count = original_deals.count
    projected_total = original_deals.sum('sold_price * quantity')

    puts "  variable@#{variable.id}@#{variable.key}@metric@#{metric.id}@calculation@#{metric.calculation}" \
         "@deals@#{deal_count}@projected_total@#{projected_total}"

    original_deals.order(:id).pluck(:id).each do |original_deal_id|
      original_deal = Deal.find(original_deal_id)
      mirrored_external_id = "#{original_deal.external_id}_#{target_user_id}"

      if mirrored_external_id.length <= 36
        length_ok = 'YES'
      else
        length_ok = "NO_#{mirrored_external_id.length}"
      end

      already_exists = Deal.exists?(company_id: company_id, external_id: mirrored_external_id, installment: original_deal.installment)

      rows << [
        variable.id, variable.key, 'OK', original_deal.id, original_deal.user_id, original_deal.external_id,
        original_deal.type, original_deal.date, original_deal.installment, original_deal.quantity,
        original_deal.sold_price, mirrored_external_id, length_ok, already_exists
      ]
    end
  rescue StandardError => error
    rows << [variable.id, variable.key, "ERROR: #{error.message}", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  end

  timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
  file_path = "integration-debug/audits/#{company_id}/premiacao-preflight/#{timestamp}.csv"

  csv_string =
    CSV.generate do |csv|
      csv << %w[variable_id variable_key status original_deal_id original_user_id original_external_id type date installment quantity sold_price mirrored_external_id length_ok already_exists]
      rows.each { |row| csv << row }
    end

  Aws.connection.put_object(aws_bucket, file_path, csv_string)

  puts "s3://#{aws_bucket}/#{file_path}"
  puts "ROWS@#{rows.size}"
  puts 'PREFLIGHT_DONE'
end
