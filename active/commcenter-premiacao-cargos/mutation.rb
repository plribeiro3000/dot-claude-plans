# Phase 2 — MUTATION. Mirror every deal in the target's subtree onto the target.
# Target: app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001
# Writes one CSV to the environment's own bucket with the per-record outcome.
#
# One deal per original. The mirror copies date, originated_at, installment, quantity, sold_price,
# client, product, status and owner so it lands inside the same metric filter and under the same
# reduction; only user and external_id change.
#
# A mirror identifies itself by external: false, following the same column on Indicator
# (schema.rb:1116, indicator.rb:95-97) — a real column, indexable and visible in the schema, rather
# than a naming convention only the people who know it can filter on.
#
# external_id = <original external_id>_<target User.id>. The suffix exists for uniqueness alone,
# because two targets can mirror the same original; the originals are already unique per
# (external_id, installment, company_id), so the pair is too, and the unique index refuses a second
# run instead of duplicating.
#
# The description is human-readable context, never the lookup key — it is free text anyone can write.
#
# Requires the external column on deals. Run only after the pre-flight reports length_ok=YES and
# already_exists=false on every row.

require 'csv'

company_id = 2077
aws_bucket = ApplicationConfiguration.aws_bucket

target_user_id = 1119697    # Alex Lima Lofeu
target_plan_id = 78941      # Remuneração Variável Coordenador de Call Center Julho 26
target_period_id = 528210   # 2026-07-01..2026-07-31

if aws_bucket.blank?
  puts '[mutation] AWS_BUCKET is not configured in this environment'
else
  target_user = User.find(target_user_id)
  plan = Plan.find(target_plan_id)
  period = plan.periods.find(target_period_id)
  subtree_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user_id]

  puts "target@#{target_user.id}@#{target_user.name}"
  puts "plan@#{plan.id}@#{plan.name}@deal_type@#{plan.deal_type}"
  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}@subtree@#{subtree_user_ids.size}"

  rows = []
  created_count = 0
  failed_count = 0

  plan.variables.with_metrics.each do |variable|
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

    original_deal_ids = original_deals.order(:id).pluck(:id)
    puts "  variable@#{variable.id}@#{variable.key}@metric@#{metric.id}@deals_to_mirror@#{original_deal_ids.size}"

    original_deal_ids.each do |original_deal_id|
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
        rows << [variable.id, variable.key, original_deal.id, original_deal.user_id, mirrored_external_id, 'CREATED', mirrored_deal.id]
      else
        failed_count += 1
        rows << [variable.id, variable.key, original_deal.id, original_deal.user_id, mirrored_external_id, 'FAILED', mirrored_deal.errors.full_messages.join(' / ')]
      end
    rescue StandardError => error
      failed_count += 1
      rows << [variable.id, variable.key, original_deal_id, nil, nil, 'ERROR', error.message]
    end
  rescue StandardError => error
    rows << [variable.id, variable.key, nil, nil, nil, 'ERROR', error.message]
  end

  timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
  file_path = "integration-debug/audits/#{company_id}/premiacao-mutation/#{timestamp}.csv"

  csv_string =
    CSV.generate do |csv|
      csv << %w[variable_id variable_key original_deal_id original_user_id mirrored_external_id outcome detail]
      rows.each { |row| csv << row }
    end

  Aws.connection.put_object(aws_bucket, file_path, csv_string)

  puts "s3://#{aws_bucket}/#{file_path}"
  puts "CREATED@#{created_count}"
  puts "FAILED@#{failed_count}"
  puts 'MUTATION_DONE'
end
