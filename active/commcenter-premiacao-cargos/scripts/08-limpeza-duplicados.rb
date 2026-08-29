# Phase 8 — DUPLICATE CLEANUP. Destroy the mirrors whose source already carries an indicator.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# Writes one CSV to the environment's own bucket carrying every field needed to recreate each record.
#
# THE STACK GUARD RUNS FIRST. A console opened against another stack answers every query with zero,
# which reads as "the data is gone" instead of "wrong environment".
#
# Runs 07's classification again instead of trusting its output: the subtree it depends on has no
# period window (hierarchy_scope.rb:5-12), so a pause between the two invalidates the answer. Two
# runs minutes apart already disagreed by sixty-five records.
#
# THE GATE RUNS FIRST OVER THE WHOLE SET AND NOTHING IS DESTROYED when a mirror cannot be traced back
# to its source: a partial pass leaves a set nobody can reason about.
#
# 09-restauracao.rb recreates anything this removes, from the CSV written here.

require 'csv'

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_id = 79175
competence_period_id = 528210
revenue_variable_id = 36311

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[cleanup] wrong stack -- nothing was read'
else
  aws_bucket = ApplicationConfiguration.aws_bucket
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

  duplicated_deal_ids = []
  essential_count = 0
  unresolved_count = 0

  UserCommission.where(commission_id: commission.id).order(:user_id).each do |user_commission|
    target_user = User.find(user_commission.user_id)
    subtree_user_ids = HierarchyScope.new(target_user, User).resolve.pluck(:id)

    # Only an override plan walks the subtree, so only there does a source seller's own Indicator row
    # already reach the target. Without this gate an override-off plan calls every carrier-sourced
    # mirror duplicated and this script destroys the revenue the cargo depends on.
    carrier_user_ids =
      if plan.override?
        Indicator
          .for_company(company_id)
          .for_variable(revenue_variable_id)
          .where(user_id: subtree_user_ids)
          .where(compiled_at: period.starts_at..period.ends_at)
          .pluck(:user_id)
          .uniq
      else
        []
      end

    mirrors =
      Deal
      .for_company(company_id)
      .for_user(target_user.id)
      .where(date: period.starts_at..period.ends_at)
      .where(external: false)
      .enabled

    mirrors.each do |mirror|
      original_external_id = mirror.external_id.to_s.sub(/_#{target_user.id}\z/, '')

      original_deal =
        Deal
        .for_company(company_id)
        .where(external_id: original_external_id, installment: mirror.installment)
        .where(external: true)
        .first

      if original_deal.nil?
        unresolved_count += 1
        next
      end

      if carrier_user_ids.include?(original_deal.user_id)
        duplicated_deal_ids << mirror.id
      else
        essential_count += 1
      end
    end
  rescue StandardError => error
    unresolved_count += 1
    puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
  end

  puts "duplicated@#{duplicated_deal_ids.size}@essential@#{essential_count}@unresolved@#{unresolved_count}"

  if unresolved_count.positive?
    puts '[cleanup] gate failed -- classification did not reconcile; nothing was destroyed'
  else
    rows = []
    destroyed_count = 0
    failed_count = 0

    duplicated_deal_ids.each do |duplicated_deal_id|
      duplicated_deal = Deal.find(duplicated_deal_id)

      snapshot = [
        duplicated_deal.id,
        duplicated_deal.type,
        duplicated_deal.company_id,
        duplicated_deal.user_id,
        duplicated_deal.owner_id,
        duplicated_deal.external,
        duplicated_deal.external_id,
        duplicated_deal.date,
        duplicated_deal.originated_at,
        duplicated_deal.installment,
        duplicated_deal.quantity,
        duplicated_deal.sold_price,
        duplicated_deal.client_id,
        duplicated_deal.product_id,
        duplicated_deal.status_id,
        duplicated_deal.description
      ]

      if duplicated_deal.destroy
        destroyed_count += 1
        rows << snapshot + ['DESTROYED', nil]
      else
        failed_count += 1
        rows << snapshot + ['FAILED', duplicated_deal.errors.full_messages.join(' / ')]
      end
    rescue StandardError => error
      failed_count += 1
      rows << [duplicated_deal_id] + Array.new(15) + ['ERROR', error.message]
    end

    timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    file_path = "integration-debug/audits/#{company_id}/premiacao-duplicate-cleanup/#{timestamp}.csv"

    csv_string =
      CSV.generate do |csv|
        csv << %w[deal_id type company_id user_id owner_id external external_id date originated_at installment quantity sold_price client_id product_id status_id description outcome detail]
        rows.each { |row| csv << row }
      end

    Aws.with_connection { |connection| connection.put_object(aws_bucket, file_path, csv_string) }

    puts "s3://#{aws_bucket}/#{file_path}"
    puts "DESTROYED@#{destroyed_count}"
    puts "FAILED@#{failed_count}"
    puts 'DUPLICATE_CLEANUP_DONE'
  end
end
