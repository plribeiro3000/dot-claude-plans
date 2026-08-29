# Phase 16 — DESCRIPTION BACKFILL. Rewrite the description of every mirror already in the base.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# dry_run = true reports and writes NOTHING. dry_run = false UPDATES DEALS IN PRODUCTION.
#
# The description is client-facing text on the transaction, so it is Portuguese and names the sale by
# the identifier the client owns. An internal id identifies nothing outside this database.
#
# THE GATE RUNS FIRST OVER THE WHOLE SET AND NOTHING IS WRITTEN when a mirror cannot be traced back
# to its source: a partial pass leaves a set nobody can reason about.
#
# The original is reached through external_id rather than by parsing the old description — the
# description is a free field anybody can overwrite, while the mirror's external_id is
# "<original external_id>_<target user id>" and the target is the mirror's own user.

require 'csv'

dry_run = true

expected_bucket = '4shark-shared-001'
company_id = 2077

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}@dry_run@#{dry_run}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[description] wrong stack -- nothing was read'
else
  aws_bucket = ApplicationConfiguration.aws_bucket

  mirror_deal_ids = Deal.for_company(company_id).where(external: false).order(:id).pluck(:id)

  puts "mirrors@#{mirror_deal_ids.size}"

  rewrites = []
  untraceable_count = 0

  mirror_deal_ids.each do |mirror_deal_id|
    mirror_deal = Deal.find(mirror_deal_id)
    original_external_id = mirror_deal.external_id.to_s.sub(/_#{mirror_deal.user_id}\z/, '')

    original_deal =
      Deal
      .for_company(company_id)
      .where(external_id: original_external_id, installment: mirror_deal.installment)
      .where(external: true)
      .first

    if original_deal.nil?
      untraceable_count += 1
      puts "untraceable@#{mirror_deal.id}@external_id@#{mirror_deal.external_id}"
      next
    end

    seller = User.find(original_deal.user_id)
    rewrites << [mirror_deal.id, mirror_deal.description, "espelho da venda #{original_deal.external_id} de #{seller.name}"]
  rescue StandardError => error
    untraceable_count += 1
    puts "untraceable@#{mirror_deal_id}@ERROR: #{error.message}"
  end

  puts "traceable@#{rewrites.size}@untraceable@#{untraceable_count}"

  if untraceable_count.positive?
    puts '[description] gate failed — nothing was written'
  else
    updated_count = 0
    failed_count = 0
    rows = []

    rewrites.each do |mirror_deal_id, previous_description, corrected_description|
      if previous_description == corrected_description
        rows << [mirror_deal_id, previous_description, corrected_description, 'UNCHANGED', nil]
        next
      end

      if dry_run
        rows << [mirror_deal_id, previous_description, corrected_description, 'PLANNED', nil]
        next
      end

      mirror_deal = Deal.find(mirror_deal_id)

      if mirror_deal.update(description: corrected_description)
        updated_count += 1
        rows << [mirror_deal_id, previous_description, corrected_description, 'UPDATED', nil]
      else
        failed_count += 1
        rows << [mirror_deal_id, previous_description, corrected_description, 'FAILED',
                 mirror_deal.errors.full_messages.join(' / ')]
      end
    end

    puts "PLANNED@#{rewrites.size}@UPDATED@#{updated_count}@FAILED@#{failed_count}"

    timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    file_path = "integration-debug/audits/#{company_id}/premiacao-description/#{timestamp}.csv"

    csv_string =
      CSV.generate do |csv|
        csv << %w[deal_id previous_description corrected_description outcome detail]
        rows.each { |row| csv << row }
      end

    Aws.with_connection { |connection| connection.put_object(aws_bucket, file_path, csv_string) }

    puts "s3://#{aws_bucket}/#{file_path}"

    if dry_run
      puts 'DESCRIPTION_REPORTED'
    else
      puts 'DESCRIPTION_DONE'
    end
  end
end
