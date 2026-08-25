# Phase 9 — RESTORE. Recreate mirrors from any audit CSV this routine wrote.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# Writes one CSV to the environment's own bucket with the per-record outcome.
#
# THE STACK GUARD RUNS FIRST. A console opened against another stack answers every query with zero,
# which reads as "the data is gone" instead of "wrong environment".
#
# THIS IS THE GUARANTEE BEHIND EVERY DESTROY IN THIS ROUTINE: 06 and 08 write sixteen columns per
# record precisely so this script can put them back. Point audit_key at the CSV of the removal being
# undone.
#
# THE GATE RUNS FIRST OVER THE WHOLE SET AND NOTHING IS WRITTEN when a column is missing or a mirror
# already exists under the unique index (deal.rb:71). A partial write leaves a batch nobody can
# reason about, which is the state this restore exists to end.
#
# date, client_id, product_id and status_id are what the metric filters on: a mirror recreated
# without them exists and is invisible to the calculation, which is worse than not restoring at all.

require 'csv'

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_id = 78939
audit_key = 'integration-debug/audits/2077/premiacao-duplicate-cleanup/20260824-214726.csv'
required_columns = %w[user_id external_id installment sold_price quantity date client_id product_id status_id]

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[restore] wrong stack -- nothing was read'
else
  aws_bucket = ApplicationConfiguration.aws_bucket
  plan = Plan.find(plan_id)
  deal_class = plan.deal_type

  audit_body = Aws.connection.get_object(aws_bucket, audit_key).body
  audit_rows = CSV.parse(audit_body, headers: true)

  missing_columns = required_columns - audit_rows.headers.compact

  puts "audit_rows@#{audit_rows.size}@deal_class@#{deal_class}@headers@#{audit_rows.headers.compact.join('|')}"

  if missing_columns.any?
    puts "[restore] gate failed -- audit CSV is missing: #{missing_columns.join(', ')}"
  else
    already_exists_count = 0

    audit_rows.each do |audit_row|
      already_exists_count += 1 if Deal.exists?(company_id: company_id, external_id: audit_row['external_id'], installment: audit_row['installment'])
    end

    puts "candidates@#{audit_rows.size}@already_exists@#{already_exists_count}"

    if already_exists_count.positive?
      puts '[restore] gate failed -- nothing was written'
    else
      rows = []
      created_count = 0
      failed_count = 0

      audit_rows.each do |audit_row|
        restored_deal = deal_class.new(
          company_id: company_id,
          user_id: audit_row['user_id'],
          owner_id: audit_row['owner_id'],
          external: false,
          external_id: audit_row['external_id'],
          date: audit_row['date'],
          originated_at: audit_row['originated_at'],
          installment: audit_row['installment'],
          quantity: audit_row['quantity'],
          sold_price: audit_row['sold_price'],
          client_id: audit_row['client_id'],
          product_id: audit_row['product_id'],
          status_id: audit_row['status_id'],
          description: audit_row['description']
        )

        if restored_deal.save
          created_count += 1
          rows << [audit_row['deal_id'], restored_deal.id, restored_deal.user_id, restored_deal.external_id, restored_deal.sold_price, restored_deal.quantity, 'RESTORED', nil]
        else
          failed_count += 1
          rows << [audit_row['deal_id'], nil, audit_row['user_id'], audit_row['external_id'], audit_row['sold_price'], audit_row['quantity'], 'FAILED', restored_deal.errors.full_messages.join(' / ')]
        end
      rescue StandardError => error
        failed_count += 1
        rows << [audit_row['deal_id'], nil, audit_row['user_id'], audit_row['external_id'], nil, nil, 'ERROR', error.message]
      end

      timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
      file_path = "integration-debug/audits/#{company_id}/premiacao-restore/#{timestamp}.csv"

      csv_string =
        CSV.generate do |csv|
          csv << %w[original_deal_id restored_deal_id user_id external_id sold_price quantity outcome detail]
          rows.each { |row| csv << row }
        end

      Aws.connection.put_object(aws_bucket, file_path, csv_string)

      puts "s3://#{aws_bucket}/#{file_path}"
      puts "RESTORED@#{created_count}"
      puts "FAILED@#{failed_count}"
      puts 'RESTORE_DONE'
    end
  end
end
