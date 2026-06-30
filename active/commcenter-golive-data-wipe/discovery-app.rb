# Phase 1 — Discovery (app-shared-001, company_id 2077). READ-ONLY.
# Paste into: bin/ecs run app-shared-001
# Output is @-separated for Excel paste. Each count is isolated — one failing
# association prints an error on its own line, it does not abort the run.

company = Company.find(2077)

deal_ids_relation      = company.deals.select(:id)
indicator_ids_relation = company.indicators.select(:id)
user_ids_relation      = company.users.select(:id)

discovery_counts = {
  # ---- DELETE set (top-level, company-scoped) ----
  'user_histories'        => -> { company.user_histories.count },
  'payments'              => -> { company.payments.count },
  'commission_payments'   => -> { CommissionPayment.joins(:payment).where(payments: { company_id: company.id }).count },
  'statements'            => -> { company.statements.count },
  'commissions'           => -> { company.commissions.count },
  'user_commissions'      => -> { UserCommission.where(user_id: user_ids_relation).count },
  'partial_commissions'   => -> { company.partial_commissions.count },
  'deals'                 => -> { company.deals.count },
  'clients'               => -> { company.clients.count },
  'products'              => -> { company.products.count },
  'indicators'            => -> { company.indicators.count },
  'plan_statements'       => -> { company.plan_statements.count },
  'plans'                 => -> { company.plans.count },
  'goals'                 => -> { company.goals.count },

  # ---- restrict-blockers (must be 0 before the parent destroy) ----
  'deal_eligibilities'        => -> { DealEligibility.where(deal_id: deal_ids_relation).count },
  'deal_fields'               => -> { DealField.where(deal_id: deal_ids_relation).count },
  'deal_document_enrollments' => -> { DealDocumentEnrollment.where(deal_id: deal_ids_relation).count },
  'eligible_indicators'       => -> { EligibleIndicator.where(modifier_id: indicator_ids_relation).count },

  # ---- KEEP baseline (verification must show these UNCHANGED) ----
  'KEEP_users'            => -> { company.users.count },
  'KEEP_subsidiaries'     => -> { company.subsidiaries.count },
  'KEEP_groups'           => -> { company.groups.count },
  'KEEP_groupifications'  => -> { Groupification.where(group_id: company.groups.select(:id)).count },
  'KEEP_variables'        => -> { company.variables.count },
  'KEEP_calendars'        => -> { company.calendars.count },
  'KEEP_roles'            => -> { company.roles.count },
  'KEEP_payment_types'    => -> { company.payment_types.count },
  'KEEP_incentives'       => -> { company.incentives.count },
  'KEEP_seat_histories'   => -> { SeatHistory.joins(seat: :user).where(users: { company_id: company.id }).count },
}

# ---- Computation pre-condition (idle when queue == executions) ----
# NOTE: do not call Computation#locked? — its connection.exists? is rejected by
# redis-client 0.29.0 against Redis Cloud (ERR unknown command 'exists?').
begin
  puts 'computation_queue@' + company.computation.send(:queue_value).to_s
  puts 'computation_executions@' + company.computation.send(:executions_value).to_s
rescue StandardError => error
  puts 'computation@ERROR: ' + error.message
end

discovery_counts.each do |label, counter|
  begin
    puts label + '@' + counter.call.to_s
  rescue StandardError => error
    puts label + '@ERROR: ' + error.message
  end
end

puts 'DISCOVERY_DONE@' + company.name.to_s
