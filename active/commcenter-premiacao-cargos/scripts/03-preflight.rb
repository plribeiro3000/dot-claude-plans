# Phase 3 — PRE-FLIGHT (READ-ONLY). Project what each target will carry after mirroring.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated. Writes one CSV to the environment's own bucket.
#
# THE PROJECTION MUST MATCH 04's SOURCE SET EXACTLY or this gate measures a batch nobody will create:
# the subtree MINUS whoever already carries an Indicator row on that variable in the period. Both
# sets are taken in this same instant and subtracted BY USER ID, never by total.
#
# Targets come from the commission's own participants, never from a name list.
#
# Originals are restricted to external: true. A cargo above another cargo holds that cargo's
# mirrors inside its subtree, and mirroring them again pays the same revenue twice — for the
# commercial managers this filter excluded R$ 76.876,94 already mirrored onto the executives.
#
# The gate is COUNTED here, not left in the CSV: auditing hundreds of rows in a spreadsheet is not
# a gate. The mutation must not run until too_long and already_exists are both zero.

require 'csv'

company_id = 2077
aws_bucket = ApplicationConfiguration.aws_bucket

plan_id = 78941
competence_period_id = 528210

if aws_bucket.blank?
  puts '[preflight] AWS_BUCKET is not configured in this environment'
elsif Deal.column_names.exclude?('external')
  puts '[preflight] the external column is absent from deals in this environment'
else
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first
  metric_variables = plan.variables.with_metrics

  puts "plan@#{plan.id}@#{plan.name}@deal_type@#{plan.deal_type}@override@#{plan.override?}"
  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
  puts "metric_variables@#{metric_variables.pluck(:id, :key).inspect}"

  rows = []
  too_long_count = 0
  already_exists_count = 0

  UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
    target_user = User.find(user_commission.user_id)
    recursive_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]

    mirrors_excluded =
      Deal
      .for_company(company_id)
      .where(user_id: recursive_user_ids)
      .where(date: period.starts_at..period.ends_at)
      .where(external: false)
      .enabled

    puts "target@#{target_user.id}@#{target_user.name}@recursive@#{recursive_user_ids.size}" \
         "@mirrors_excluded@#{mirrors_excluded.count}@excluded_total@#{mirrors_excluded.sum('sold_price * quantity')}"

    metric_variables.each do |variable|
      metric = variable.metric

      # Per variable, not per target: a seller can carry a row on one variable and none on another.
      carrier_user_ids =
        Indicator
        .for_company(company_id)
        .for_variable(variable.id)
        .where(user_id: recursive_user_ids)
        .where(compiled_at: period.starts_at..period.ends_at)
        .pluck(:user_id)
        .uniq

      source_user_ids = recursive_user_ids - carrier_user_ids

      original_deals = Deal.for_company(company_id).where(user_id: source_user_ids).enabled.where(external: true)
      original_deals = original_deals.for_type(plan.deal_type)
      original_deals = original_deals.where(date: period.starts_at..period.ends_at)
      original_deals = original_deals.for_client(metric.client_id).for_product(metric.product_id)
      original_deals = original_deals.where(status_id: metric.status_id) if metric.status_id.to_i.positive?
      original_deals = original_deals.where("installment #{metric.comparator} ?", metric.installment) if metric.installment.present?

      if metric.interval?
        original_deals = original_deals.where('EXTRACT(DAY FROM date) BETWEEN ? AND ?', metric.starts_at, metric.ends_at)
      end

      puts "  variable@#{variable.id}@#{variable.key}@metric@#{metric.id}@deals@#{original_deals.count}" \
           "@projected_total@#{original_deals.sum('sold_price * quantity')}"

      original_deals.order(:id).pluck(:id).each do |original_deal_id|
        original_deal = Deal.find(original_deal_id)
        mirrored_external_id = "#{original_deal.external_id}_#{target_user.id}"

        if mirrored_external_id.length <= 36
          length_ok = 'YES'
        else
          length_ok = "NO_#{mirrored_external_id.length}"
          too_long_count += 1
        end

        already_exists = Deal.exists?(company_id: company_id, external_id: mirrored_external_id, installment: original_deal.installment)
        already_exists_count += 1 if already_exists

        rows << [
          target_user.id, target_user.name, variable.id, variable.key, 'OK',
          original_deal.id, original_deal.user_id, original_deal.external_id, original_deal.type,
          original_deal.date, original_deal.installment, original_deal.quantity, original_deal.sold_price,
          mirrored_external_id, length_ok, already_exists
        ]
      end
    rescue StandardError => error
      rows << [target_user.id, target_user.name, variable.id, variable.key, "ERROR: #{error.message}", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
    end
  rescue StandardError => error
    puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
  end

  timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
  file_path = "integration-debug/audits/#{company_id}/premiacao-preflight/#{timestamp}.csv"

  csv_string =
    CSV.generate do |csv|
      csv << %w[target_id target_name variable_id variable_key status original_deal_id original_user_id original_external_id type date installment quantity sold_price mirrored_external_id length_ok already_exists]
      rows.each { |row| csv << row }
    end

  Aws.with_connection { |connection| connection.put_object(aws_bucket, file_path, csv_string) }

  puts "s3://#{aws_bucket}/#{file_path}"
  puts "ROWS@#{rows.size}@too_long@#{too_long_count}@already_exists@#{already_exists_count}"
  puts 'PREFLIGHT_DONE'
end
