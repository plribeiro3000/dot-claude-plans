# Phase 10 — RECONCILIATION. Bring the mirrors already in the base back in line with the deals as
# they stand now. Covers the three cargos in one pass.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
#
# ############################################################################
# dry_run = true  reports the delta and writes NOTHING.
# dry_run = false WRITES TO PRODUCTION: creates, updates and disables deals.
# ############################################################################
#
# A mirror is a copy frozen at the instant it was created and nothing keeps it in sync with its
# origin. When the origin changes — a corrected value, a different status, a deactivated sale, a sale
# that did not exist before — the mirror stays as it was, and the calculation has no way to notice:
# to the metric a mirror is a deal like any other. The divergence never surfaces as an error, it
# surfaces as a plausible figure nobody can explain later. That is why this runs daily.
#
# 04-mutacao.rb cannot do this pass. Its gate counts the mirrors that already exist and refuses to
# write anything when that count is positive (04-mutacao.rb:100-101). That is correct for a first run
# — a partial write across several targets leaves a batch nobody can audit — and it is exactly what
# stops a second run from creating the handful of mirrors that are missing.
#
# THE SOURCE SET DEPENDS ON THE PLAN'S override FLAG, and a mismatch here deactivates mirrors that
# are legitimate. Under override the recursive scan already reaches a subordinate who carries an
# Indicator row, so that subordinate is excluded; without override nothing rises on its own and the
# whole subtree is the source. The rest of the chain is fixed: external: true, enabled, the plan's
# deal type, the period, client, product, status, installment and the metric's day interval.
#
# The carrier count is printed per target and per variable because it is the only visible signal that
# the hierarchy moved: a subtree that changed size between two runs shows up there before it shows up
# in the money.
#
# Identity is the (external_id, installment) pair, the same one the unique index uses (deal.rb:71),
# so a mirror is matched back to its original without parsing anything out of the name.
#
# A value that goes to zero arrives here as an ORPHAN, never as an update: sold_price and quantity
# are numericality greater_than 0 (deal.rb:41-42), and a sale zeroed or deactivated at the origin
# leaves the source set, which is what marks its mirror for deactivation.
#
# Deactivation is disable, never destroy — the row stays and enable puts it back
# (application_record.rb:109-125). The CSV carries the recreate columns plus the before/after of
# every field changed, so an entire reconciliation can be undone from it.
#
# Nothing here moves a figure on its own: the metric reads deal ids from an index keyed by
# commission_uuid (deal_search_index.rb:7-8), so the competence's commission has to be processed
# again afterwards.

require 'csv'

dry_run = true

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_ids = [78941, 78940, 78939]
competence_period_id = 528210

comparable_fields = %w[sold_price quantity status_id date client_id product_id originated_at owner_id]

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}@dry_run@#{dry_run}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[reconciliation] wrong stack -- nothing was read'
elsif Deal.column_names.exclude?('external')
  puts '[reconciliation] the external column is absent from deals in this environment'
else
  aws_bucket = ApplicationConfiguration.aws_bucket

  plan_ids.each do |plan_id|
    plan = Plan.find(plan_id)
    period = plan.periods.find(competence_period_id)
    commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first
    metric_variables = plan.variables.with_metrics

    puts "plan@#{plan.id}@#{plan.name}@deal_type@#{plan.deal_type}@override@#{plan.override?}"
    puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
    puts "commission@#{commission.id}@status@#{commission.status}"
    puts "metric_variables@#{metric_variables.pluck(:id, :key).inspect}"

    rows = []
    create_count = 0
    update_count = 0
    disable_count = 0
    enable_count = 0
    unchanged_count = 0
    failed_count = 0

    UserCommission.where(commission_id: commission.id).order(:user_id).find_each do |user_commission|
      target_user = User.find(user_commission.user_id)
      recursive_user_ids = UserScope.new(target_user, User).resolve.pluck(:id) - [target_user.id]

      expected_originals = {}
      carrier_report = []

      metric_variables.each do |variable|
        metric = variable.metric

        # Only an override plan walks the subtree, so only there does a subordinate's own Indicator
        # row already reach the target. Excluding carriers under a non-override plan drops revenue
        # that has no other path up (PLAN.md, the source-set column of the cargo table).
        carrier_user_ids =
          if plan.override?
            Indicator
              .for_company(company_id)
              .for_variable(variable.id)
              .where(user_id: recursive_user_ids)
              .where(compiled_at: period.starts_at..period.ends_at)
              .pluck(:user_id)
              .uniq
          else
            []
          end

        carrier_report << "#{variable.key}:#{carrier_user_ids.size}"
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
          original_deal = Deal.find(original_deal_id)
          identity = ["#{original_deal.external_id}_#{target_user.id}", original_deal.installment]
          expected_originals[identity] = [original_deal_id, variable.key]
        end
      end

      existing_mirrors = {}

      Deal
        .for_company(company_id)
        .where(user_id: target_user.id)
        .where(date: period.starts_at..period.ends_at)
        .where(external: false)
        .order(:id)
        .pluck(:id)
        .each do |mirror_deal_id|
          mirror_deal = Deal.find(mirror_deal_id)
          existing_mirrors[[mirror_deal.external_id, mirror_deal.installment]] = mirror_deal_id
        end

      total_before =
        Deal
        .for_company(company_id)
        .where(user_id: target_user.id)
        .where(date: period.starts_at..period.ends_at)
        .where(external: false)
        .enabled
        .sum('sold_price * quantity')

      puts "target@#{target_user.id}@#{target_user.name}@recursive@#{recursive_user_ids.size}" \
           "@carriers@#{carrier_report.join(',')}" \
           "@expected@#{expected_originals.size}@existing@#{existing_mirrors.size}@total_before@#{total_before}"

      expected_originals.each do |identity, expected_entry|
        mirrored_external_id, installment = identity
        original_deal_id, variable_key = expected_entry
        original_deal = Deal.find(original_deal_id)
        mirror_deal_id = existing_mirrors[identity]

        recreate_columns = [
          original_deal.type, target_user.id, original_deal.owner_id, mirrored_external_id,
          original_deal.date, original_deal.originated_at, installment, original_deal.quantity,
          original_deal.sold_price, original_deal.client_id, original_deal.product_id, original_deal.status_id
        ]

        if mirror_deal_id.nil?
          create_count += 1

          if mirrored_external_id.length > 36
            failed_count += 1
            rows << ['CREATE', target_user.id, target_user.name, variable_key, nil, original_deal_id,
                     original_deal.user_id, *recreate_columns, nil, 'REFUSED',
                     "external_id has #{mirrored_external_id.length} characters"]
          elsif dry_run
            rows << ['CREATE', target_user.id, target_user.name, variable_key, nil, original_deal_id,
                     original_deal.user_id, *recreate_columns, nil, 'PLANNED', nil]
          else
            mirrored_deal = original_deal.class.new(
              company_id: company_id,
              user_id: target_user.id,
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
              rows << ['CREATE', target_user.id, target_user.name, variable_key, mirrored_deal.id,
                       original_deal_id, original_deal.user_id, *recreate_columns, nil, 'CREATED', nil]
            else
              failed_count += 1
              rows << ['CREATE', target_user.id, target_user.name, variable_key, nil, original_deal_id,
                       original_deal.user_id, *recreate_columns, nil, 'FAILED',
                       mirrored_deal.errors.full_messages.join(' / ')]
            end
          end
        else
          mirror_deal = Deal.find(mirror_deal_id)

          differences =
            comparable_fields.filter_map do |field_name|
              mirror_value = mirror_deal.public_send(field_name)
              original_value = original_deal.public_send(field_name)

              if mirror_value != original_value
                "#{field_name}:#{mirror_value}->#{original_value}"
              end
            end

          if mirror_deal.disabled_at.present?
            enable_count += 1

            if dry_run
              rows << ['ENABLE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                       original_deal_id, original_deal.user_id, *recreate_columns,
                       differences.join('; '), 'PLANNED', nil]
            elsif mirror_deal.enable
              rows << ['ENABLE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                       original_deal_id, original_deal.user_id, *recreate_columns,
                       differences.join('; '), 'ENABLED', nil]
            else
              failed_count += 1
              rows << ['ENABLE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                       original_deal_id, original_deal.user_id, *recreate_columns,
                       differences.join('; '), 'FAILED', mirror_deal.errors.full_messages.join(' / ')]
            end
          elsif differences.empty?
            unchanged_count += 1
          else
            update_count += 1

            if dry_run
              rows << ['UPDATE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                       original_deal_id, original_deal.user_id, *recreate_columns,
                       differences.join('; '), 'PLANNED', nil]
            else
              updated_attributes = {
                sold_price: original_deal.sold_price,
                quantity: original_deal.quantity,
                status_id: original_deal.status_id,
                date: original_deal.date,
                client_id: original_deal.client_id,
                product_id: original_deal.product_id,
                originated_at: original_deal.originated_at,
                owner_id: original_deal.owner_id
              }

              if mirror_deal.update(updated_attributes)
                rows << ['UPDATE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                         original_deal_id, original_deal.user_id, *recreate_columns,
                         differences.join('; '), 'UPDATED', nil]
              else
                failed_count += 1
                rows << ['UPDATE', target_user.id, target_user.name, variable_key, mirror_deal_id,
                         original_deal_id, original_deal.user_id, *recreate_columns,
                         differences.join('; '), 'FAILED', mirror_deal.errors.full_messages.join(' / ')]
              end
            end
          end
        end
      rescue StandardError => error
        failed_count += 1
        rows << ['EXPECTED', target_user.id, target_user.name, nil, nil, nil, nil, nil, nil, nil,
                 identity.first, nil, nil, identity.last, nil, nil, nil, nil, nil, nil, 'ERROR', error.message]
      end

      orphan_identities = existing_mirrors.keys - expected_originals.keys

      orphan_identities.each do |identity|
        mirror_deal_id = existing_mirrors[identity]
        mirror_deal = Deal.find(mirror_deal_id)

        if mirror_deal.disabled_at.present?
          unchanged_count += 1
        else
          disable_count += 1

          recreate_columns = [
            mirror_deal.type, mirror_deal.user_id, mirror_deal.owner_id, mirror_deal.external_id,
            mirror_deal.date, mirror_deal.originated_at, mirror_deal.installment, mirror_deal.quantity,
            mirror_deal.sold_price, mirror_deal.client_id, mirror_deal.product_id, mirror_deal.status_id
          ]

          if dry_run
            rows << ['DISABLE', target_user.id, target_user.name, nil, mirror_deal_id, nil, nil,
                     *recreate_columns, nil, 'PLANNED', nil]
          elsif mirror_deal.disable(by: nil)
            rows << ['DISABLE', target_user.id, target_user.name, nil, mirror_deal_id, nil, nil,
                     *recreate_columns, nil, 'DISABLED', mirror_deal.disabled_at]
          else
            failed_count += 1
            rows << ['DISABLE', target_user.id, target_user.name, nil, mirror_deal_id, nil, nil,
                     *recreate_columns, nil, 'FAILED', mirror_deal.errors.full_messages.join(' / ')]
          end
        end
      rescue StandardError => error
        failed_count += 1
        rows << ['ORPHAN', target_user.id, target_user.name, nil, existing_mirrors[identity], nil, nil,
                 nil, nil, nil, identity.first, nil, nil, identity.last, nil, nil, nil, nil, nil, nil,
                 'ERROR', error.message]
      end

      if dry_run
        puts "  target@#{target_user.id}@reported"
      else
        total_after =
          Deal
          .for_company(company_id)
          .where(user_id: target_user.id)
          .where(date: period.starts_at..period.ends_at)
          .where(external: false)
          .enabled
          .sum('sold_price * quantity')

        puts "  target@#{target_user.id}@total_after@#{total_after}"
      end
    rescue StandardError => error
      puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
    end

    # Counters before the upload: a failure reaching S3 must not take the delta down with it.
    puts "plan@#{plan.id}@CREATE@#{create_count}@UPDATE@#{update_count}@DISABLE@#{disable_count}" \
         "@ENABLE@#{enable_count}@UNCHANGED@#{unchanged_count}@FAILED@#{failed_count}"

    timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
    file_path = "integration-debug/audits/#{company_id}/premiacao-reconciliation/#{timestamp}-#{plan_id}.csv"

    csv_string =
      CSV.generate do |csv|
        csv << %w[action target_id target_name variable_key mirror_deal_id original_deal_id original_user_id
                  type user_id owner_id external_id date originated_at installment quantity sold_price
                  client_id product_id status_id changes outcome detail]
        rows.each { |row| csv << row }
      end

    Aws.with_connection { |connection| connection.put_object(aws_bucket, file_path, csv_string) }

    puts "s3://#{aws_bucket}/#{file_path}"
  end

  if dry_run
    puts 'RECONCILIATION_REPORTED'
  else
    puts 'RECONCILIATION_DONE'
  end
end
