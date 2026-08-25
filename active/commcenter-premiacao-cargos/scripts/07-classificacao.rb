# Phase 7 — CLASSIFICATION (READ-ONLY). Split existing mirrors into essential and duplicated.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# THE STACK GUARD RUNS FIRST. A console opened against another stack answers every query with zero,
# which reads as "the data is gone" instead of "wrong environment".
#
# A mirror is DUPLICATED when its source seller already carries an Indicator row on that variable in
# the period: AggregatedIndicator#result (aggregated_indicator.rb:92-97) already reaches that row, so
# the mirror counts the same revenue twice. A mirror is ESSENTIAL when the source carries no row and
# the walk cannot see it at all.
#
# The classification is recomputed from the base on every run rather than read from a stored list.
# HierarchyScope has no period window (hierarchy_scope.rb:5-12), so the subtree — and therefore this
# answer — is a property of the instant it is taken.
#
# Runs on any cargo. On an override-off plan no walk happens, no subtree member carries a row that
# matters, and every mirror comes back essential.

expected_bucket = '4shark-shared-001'
company_id = 2077

plan_id = 78939
competence_period_id = 528210
revenue_variable_id = 36311

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[classification] wrong stack -- nothing was read'
else
  plan = Plan.find(plan_id)
  period = plan.periods.find(competence_period_id)
  commission = Commission.for_company(company_id).for_plan(plan_id).for_period(competence_period_id).first

  total_duplicated = 0

  UserCommission.where(commission_id: commission.id).order(:user_id).each do |user_commission|
    target_user = User.find(user_commission.user_id)
    subtree_user_ids = HierarchyScope.new(target_user, User).resolve.pluck(:id)

    carrier_user_ids =
      Indicator
      .for_company(company_id)
      .for_variable(revenue_variable_id)
      .where(user_id: subtree_user_ids)
      .where(compiled_at: period.starts_at..period.ends_at)
      .pluck(:user_id)
      .uniq

    mirrors =
      Deal
      .for_company(company_id)
      .for_user(target_user.id)
      .where(date: period.starts_at..period.ends_at)
      .where(external: false)
      .enabled

    essential_count = 0
    essential_value = 0.0
    duplicated_count = 0
    duplicated_value = 0.0
    unresolved_count = 0

    mirrors.each do |mirror|
      # The mutation built external_id as "<original external_id>_<target user id>", so stripping the
      # suffix and matching on (external_id, installment) recovers the seller.
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

      mirrored_value = mirror.sold_price.to_f * mirror.quantity.to_f

      if carrier_user_ids.include?(original_deal.user_id)
        duplicated_count += 1
        duplicated_value += mirrored_value
      else
        essential_count += 1
        essential_value += mirrored_value
      end
    end

    total_duplicated += duplicated_count

    puts "target@#{target_user.id}@#{target_user.name}@subtree@#{subtree_user_ids.size}" \
         "@carriers@#{carrier_user_ids.size}@mirrors@#{mirrors.count}" \
         "@essential@#{essential_count}@essential_value@#{essential_value.round(2)}" \
         "@duplicated@#{duplicated_count}@duplicated_value@#{duplicated_value.round(2)}" \
         "@unresolved@#{unresolved_count}"
  rescue StandardError => error
    puts "target@#{user_commission.user_id}@ERROR: #{error.message}"
  end

  puts "duplicated_total@#{total_duplicated}"
  puts 'CLASSIFICATION_DONE'
end
