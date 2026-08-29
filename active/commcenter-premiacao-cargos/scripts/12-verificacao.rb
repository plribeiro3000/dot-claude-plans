# Phase 12 — MUTATION VERIFICATION (READ-ONLY). Re-read every record a mutation touched and prove it
# landed correctly, against the source rather than against the mutation's own report.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# THIS IS THE THIRD OF THE THREE QUERIES EVERY MUTATION RUNS: dry-run (report the delta), execution
# (apply), verification (this one). The execution printing CREATE@9 is its OWN report, not
# verification — it proves the script tried nine, never that nine exist and are correct. This re-reads
# them from the live base.
#
# It reads the reconciliation CSV(s) the apply wrote — the s3 keys 10-reconciliacao.rb printed — and,
# for every action row, re-reads the touched mirror:
#   CREATE / UPDATE / ENABLE -> the mirror exists, external: false, enabled, and equals its source
#                               deal on the eight fields the calculation reads.
#   DISABLE                  -> the mirror is disabled.
# Any FAIL is a partial mutation, which hides here and nowhere else — the bucket is not done.
#
# The eight comparable fields are the same list 10-reconciliacao compares on, so a PASS here is
# exactly what a fresh dry_run would count as UNCHANGED.
#
# 11-contagens.rb is NOT covered here: it mutates Indicator rows, not deals, and writes no per-mirror
# CSV. Its verification is a second 11 run in dry_run, which must report DIVERGING@0.

require 'csv'

expected_bucket = '4shark-shared-001'
company_id = 2077

# The reconciliation CSVs the apply wrote — one per plan, replaced each run from 10-reconciliacao.rb's
# RECONCILIATION_DONE output.
audit_keys = [
  'integration-debug/audits/2077/premiacao-reconciliation/<timestamp>-78940.csv',
  'integration-debug/audits/2077/premiacao-reconciliation/<timestamp>-79175.csv'
]

comparable_fields = %w[sold_price quantity status_id date client_id product_id originated_at owner_id]

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[verify-mutation] wrong stack -- nothing was read'
else
  aws_bucket = ApplicationConfiguration.aws_bucket

  pass_count = 0
  fail_count = 0

  audit_keys.each do |audit_key|
    audit_body = Aws.with_connection { |connection| connection.get_object(aws_bucket, audit_key).body }
    audit_rows = CSV.parse(audit_body, headers: true)

    action_rows = audit_rows.reject { |audit_row| audit_row['action'].nil? }
    puts "audit@#{audit_key}@rows@#{action_rows.size}"

    action_rows.each do |audit_row|
      action = audit_row['action']
      mirror_deal_id = audit_row['mirror_deal_id']
      original_deal_id = audit_row['original_deal_id']
      external_id = audit_row['external_id']

      mirror = Deal.find_by(id: mirror_deal_id)
      problems = []

      if mirror.nil?
        problems << 'mirror not found'
      else
        case action
        when 'CREATE', 'UPDATE', 'ENABLE'
          problems << "external@#{mirror.external}" if mirror.external != false
          problems << 'disabled' if mirror.disabled_at.present?

          original = Deal.find_by(id: original_deal_id)

          if original.nil?
            problems << "original@#{original_deal_id}@not_found"
          else
            comparable_fields.each do |field_name|
              mirror_value = mirror.public_send(field_name)
              original_value = original.public_send(field_name)

              if mirror_value.to_s != original_value.to_s
                problems << "#{field_name}@#{mirror_value}!=#{original_value}"
              end
            end
          end
        when 'DISABLE'
          problems << 'still_enabled' if mirror.disabled_at.nil?
        end
      end

      if problems.empty?
        pass_count += 1
      else
        fail_count += 1
        puts "  FAIL@#{action}@mirror@#{mirror_deal_id}@external_id@#{external_id}@#{problems.join(' / ')}"
      end
    end
  end

  puts "VERIFY_MUTATION@PASS@#{pass_count}@FAIL@#{fail_count}"
  puts 'VERIFY_MUTATION_DONE'
end
