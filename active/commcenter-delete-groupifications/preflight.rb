# Phase 2 — PRE-FLIGHT (READ-ONLY). Commcenter groupification deletion.
# app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001
# Re-confirms the exact 24 targets from Discovery still exist and match (drift check),
# and reports exactly what the mutation will destroy: per-user PlanStatement(s) +
# UserCommission(s) in each group's plans, plus the total premiacao (money) about to go.
# Mutates NOTHING. Targets are addressed by the Groupification id confirmed in Discovery.

company_id = 2077
company = Company.find(company_id)

targets = [
  { line: 2,  bucket: 'A', gf_id: 705616, user_id: 1243873, group_id: 48184 },
  { line: 3,  bucket: 'A', gf_id: 709070, user_id: 1026093, group_id: 40315 },
  { line: 24, bucket: 'A', gf_id: 709069, user_id: 1243865, group_id: 50370 },
  { line: 25, bucket: 'A', gf_id: 709075, user_id: 1243873, group_id: 50370 },
  { line: 4,  bucket: 'B', gf_id: 720098, user_id: 1243774, group_id: 48179 },
  { line: 5,  bucket: 'B', gf_id: 709068, user_id: 1243772, group_id: 48179 },
  { line: 6,  bucket: 'B', gf_id: 709067, user_id: 1243861, group_id: 48179 },
  { line: 7,  bucket: 'B', gf_id: 720105, user_id: 1243858, group_id: 48177 },
  { line: 8,  bucket: 'B', gf_id: 720111, user_id: 1243872, group_id: 48177 },
  { line: 9,  bucket: 'B', gf_id: 705682, user_id: 1119930, group_id: 48182 },
  { line: 10, bucket: 'B', gf_id: 705708, user_id: 1243813, group_id: 48182 },
  { line: 11, bucket: 'B', gf_id: 709061, user_id: 1026105, group_id: 48182 },
  { line: 12, bucket: 'B', gf_id: 719890, user_id: 1119931, group_id: 48182 },
  { line: 13, bucket: 'B', gf_id: 719969, user_id: 1119816, group_id: 48182 },
  { line: 14, bucket: 'B', gf_id: 720108, user_id: 1243861, group_id: 48182 },
  { line: 15, bucket: 'B', gf_id: 720109, user_id: 1243863, group_id: 48182 },
  { line: 16, bucket: 'B', gf_id: 719196, user_id: 1026105, group_id: 50212 },
  { line: 17, bucket: 'B', gf_id: 719197, user_id: 1119700, group_id: 50212 },
  { line: 18, bucket: 'B', gf_id: 719198, user_id: 1243772, group_id: 50212 },
  { line: 19, bucket: 'B', gf_id: 720099, user_id: 1243854, group_id: 50216 },
  { line: 20, bucket: 'B', gf_id: 705720, user_id: 1243914, group_id: 50215 },
  { line: 21, bucket: 'B', gf_id: 705721, user_id: 1243909, group_id: 50215 },
  { line: 22, bucket: 'B', gf_id: 709172, user_id: 1248170, group_id: 50215 },
  { line: 23, bucket: 'B', gf_id: 705723, user_id: 1243918, group_id: 50215 }
]

total_groupifications = 0
total_plan_statements = 0
total_user_commissions = 0
total_money = 0.0

puts %w[line bucket gf_id gf_status user_id group_id plan_statements user_commissions commission_money].join('@')

targets.each do |target|
  begin
    groupification = Groupification.find_by(id: target[:gf_id], user_id: target[:user_id], group_id: target[:group_id])
    if groupification.nil?
      puts [target[:line], target[:bucket], target[:gf_id], 'DRIFT_OR_GONE', target[:user_id], target[:group_id], '-', '-', '-'].join('@')
      next
    end
    total_groupifications += 1

    plan_ids = Group.find(target[:group_id]).plans.select(:id)
    plan_statement_scope = PlanStatement.where(user_id: target[:user_id], plan_id: plan_ids)
    user_commission_scope = UserCommission.joins(:commission).where(user_id: target[:user_id], commissions: { plan_id: plan_ids })

    plan_statement_count = plan_statement_scope.count
    user_commission_count = user_commission_scope.count
    commission_money = user_commission_scope.sum(:money)

    total_plan_statements += plan_statement_count
    total_user_commissions += user_commission_count
    total_money += commission_money

    puts [
      target[:line], target[:bucket], target[:gf_id], 'OK',
      target[:user_id], target[:group_id],
      plan_statement_count, user_commission_count, format('%.2f', commission_money)
    ].join('@')
  rescue StandardError => error
    puts [target[:line], target[:bucket], target[:gf_id], "ERROR: #{error.message}", target[:user_id], target[:group_id], '-', '-', '-'].join('@')
  end
end

puts '---'
puts "TOTAL_groupifications_to_destroy@#{total_groupifications}"
puts "TOTAL_plan_statements_to_destroy@#{total_plan_statements}"
puts "TOTAL_user_commissions_to_destroy@#{total_user_commissions}"
puts "TOTAL_commission_money_to_destroy@#{format('%.2f', total_money)}"
puts "SIDEKIQ_busy@#{Sidekiq::Workers.new.size}"
puts 'PREFLIGHT_DONE@' + company.name.to_s
