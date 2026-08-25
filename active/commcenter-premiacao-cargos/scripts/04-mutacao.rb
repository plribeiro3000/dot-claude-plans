# Phase 4 — MUTATION. Mirror the source set onto each target of the plan.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# Writes one CSV to the environment's own bucket with the per-record outcome.
#
# THE SOURCE SET EXCLUDES WHOEVER ALREADY CARRIES AN INDICATOR ROW, never a level of hierarchy.
# AggregatedIndicator#result walks the recursive subtree but only READS rows that already exist, so a
# member holding one is reached already and mirroring its deal counts the revenue twice. Excluding
# Plan#subordinate_ids_by instead fails SILENTLY: it returns one level while carriers sit at every
# depth. On an override-off plan no walk happens, the carrier set is empty, and this stays one script.
#
# One mirror per original. It copies date, originated_at, installment, quantity, sold_price, client,
# product, status and owner so it lands inside the same metric filter under the same reduction; only
# user and external_id change.
#
# A mirror identifies itself by external: false — a real column, indexable and visible in the
# schema, rather than a naming convention only the people who know it can filter on. Originals are
# restricted to external: true so a mirror is never mirrored upward.
#
# external_id is <original external_id>_<target User.id>. The suffix exists for uniqueness alone,
# because two targets can mirror the same original; originals are already unique per
# (external_id, installment, company_id), so the pair is too.
#
# THE GATE RUNS FIRST OVER THE WHOLE SET AND NOTHING IS WRITTEN when it finds a violation — an
# external_id past the 36-character limit (deal.rb:38) or a mirror already present under the unique
# index (deal.rb:71). Several targets share one run, so a partial write leaves a batch nobody can
# reason about.
#
# Nothing here moves a figure on its own: the metric reads deal ids from an index keyed by
# commission_uuid (deal_search_index.rb:7-8), so the competence's commission has to be processed
# again afterwards.

require 'csv'

company_id = 2077
aws_bucket = ApplicationConfiguration.aws_bucket

plan_id = 78941
competence_period_id = 528210

if aws_bucket.blank?
  puts '[mutation] AWS_BUCKET is not configured in this environment'
elsif Deal.column_names.exclude?('external')
  puts '[mutation] the external column is absent from deals in this environment'
else
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

  candidates = []

  UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
    target_user = User.find(user_commission.user_id)
    recursive_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]

    plan.variables.with_metrics.each do |variable|
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

      original_deals.order(:id).pluck(:id).each do |original_deal_id|
        candidates << [target_user.id, variable.id, variable.key, original_deal_id]
      end
    end
  end

  too_long_count = 0
  already_exists_count = 0

  candidates.each do |target_user_id, _variable_id, _variable_key, original_deal_id|
    original_deal = Deal.find(original_deal_id)
    mirrored_external_id = "#{original_deal.external_id}_#{target_user_id}"

    too_long_count += 1 if mirrored_external_id.length > 36
    already_exists_count += 1 if Deal.exists?(company_id: company_id, external_id: mirrored_external_id, installment: original_deal.installment)
  end

  puts "candidates@#{candidates.size}@too_long@#{too_long_count}@already_exists@#{already_exists_count}"

  if too_long_count.positive? || already_exists_count.positive?
    puts '[mutation] gate failed — nothing was written'
  else
    rows = []
    created_count = 0
    failed_count = 0

    candidates.each do |target_user_id, variable_id, variable_key, original_deal_id|
      original_deal = Deal.find(original_deal_id)
      mirrored_external_id = "#{original_deal.external_id}_#{target_user_id}"

      mirrored_deal = original_deal.class.new(
        company_id: company_id,
        user_id: target_user_id,
        owner_id: original_deal.owner_id,
        external: false,
        external_id: mirrored_external_id,
        date: original_deal.date,
        originated_at: original_deal.originated_at,
        installment: original_deal.installment,
        quantity: original_deal.quantity,
        sold_price: original_deal.sold_price,
        client_id: original_deal.client_id,
        product_id: original_deal.product_id,
        status_id: original_deal.status_id,
        description: "mirror of deal #{original_deal.id} from user #{original_deal.user_id}"
      )

      if mirrored_deal.save
        created_count += 1
        rows << [target_user_id, variable_id, variable_key, original_deal.id, original_deal.user_id, mirrored_external_id, 'CREATED', mirrored_deal.id]
      else
        failed_count += 1
        rows << [target_user_id, variable_id, variable_key, original_deal.id, original_deal.user_id, mirrored_external_id, 'FAILED', mirrored_deal.errors.full_messages.join(' / ')]
      end
    rescue StandardError => error
      failed_count += 1
      rows << [target_user_id, variable_id, variable_key, original_deal_id, nil, nil, 'ERROR', error.message]
    end

    timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    file_path = "integration-debug/audits/#{company_id}/premiacao-mutation/#{timestamp}.csv"

    csv_string =
      CSV.generate do |csv|
        csv << %w[target_id variable_id variable_key original_deal_id original_user_id mirrored_external_id outcome detail]
        rows.each { |row| csv << row }
      end

    Aws.connection.put_object(aws_bucket, file_path, csv_string)

    puts "s3://#{aws_bucket}/#{file_path}"
    puts "CREATED@#{created_count}"
    puts "FAILED@#{failed_count}"
    puts 'MUTATION_DONE'
  end
end
