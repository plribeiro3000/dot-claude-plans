# Phase 6 — DEACTIVATION / ROLLBACK (soft-delete). Take a plan's mirrors out of the calculation.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# Writes one CSV to the environment's own bucket with the per-record outcome.
#
# disable performs update(disabled_at: Time.zone.now, disabler_id: by) and KEEPS the row
# (application_record.rb:109-127). The metric stops seeing it because the enabled scope is
# where(disabled_at: nil) (application_record.rb:20-26) and Metric::TotalAdapter applies .enabled on
# both branches (total_adapter.rb:39,50) — so this removes the mirrors from the figure without
# destroying the evidence of what was created, and enable() puts them back.
#
# Idempotent by construction: disable on an already-disabled record returns false with an
# :already_inactive error rather than raising, so a second run reports and moves on.
#
# The figure only moves once the competence's commission is processed again.

require 'csv'

company_id = 2077
aws_bucket = ApplicationConfiguration.aws_bucket

plan_id = 78941
competence_period_id = 528210

if aws_bucket.blank?
  puts '[deactivation] AWS_BUCKET is not configured in this environment'
else
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

  target_user_ids = UserCommission.where(commission_id: commission.id).pluck(:user_id)

  mirrored_deal_ids =
    Deal
    .for_company(company_id)
    .where(user_id: target_user_ids)
    .where(date: period.starts_at..period.ends_at)
    .where(external: false)
    .enabled
    .order(:id)
    .pluck(:id)

  puts "plan@#{plan.id}@#{plan.name}@targets@#{target_user_ids.size}@mirrors_enabled@#{mirrored_deal_ids.size}"

  rows = []
  disabled_count = 0
  failed_count = 0

  mirrored_deal_ids.each do |mirrored_deal_id|
    mirrored_deal = Deal.find(mirrored_deal_id)

    if mirrored_deal.disable(by: nil)
      disabled_count += 1
      rows << [mirrored_deal.id, mirrored_deal.user_id, mirrored_deal.external_id, mirrored_deal.installment, mirrored_deal.sold_price, mirrored_deal.quantity, 'DISABLED', mirrored_deal.disabled_at]
    else
      failed_count += 1
      rows << [mirrored_deal.id, mirrored_deal.user_id, mirrored_deal.external_id, mirrored_deal.installment, mirrored_deal.sold_price, mirrored_deal.quantity, 'FAILED', mirrored_deal.errors.full_messages.join(' / ')]
    end
  rescue StandardError => error
    failed_count += 1
    rows << [mirrored_deal_id, nil, nil, nil, nil, nil, 'ERROR', error.message]
  end

  timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
  file_path = "integration-debug/audits/#{company_id}/premiacao-deactivation/#{timestamp}.csv"

  csv_string =
    CSV.generate do |csv|
      csv << %w[deal_id user_id external_id installment sold_price quantity outcome detail]
      rows.each { |row| csv << row }
    end

  Aws.connection.put_object(aws_bucket, file_path, csv_string)

  puts "s3://#{aws_bucket}/#{file_path}"
  puts "DISABLED@#{disabled_count}"
  puts "FAILED@#{failed_count}"
  puts 'DEACTIVATION_DONE'
end
