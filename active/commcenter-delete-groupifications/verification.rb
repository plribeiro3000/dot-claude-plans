# Phase 3 — VERIFICATION (READ-ONLY). Commcenter groupification deletion.
# app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001 'bundle exec rails console'
# Asserts every target is gone (groupification / plan_statement / user_commission == 0)
# AND that the KEEP set is intact (each group and user still exists — we only removed
# the participation, never the person or the group). Mutates nothing.

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

remaining_groupifications = 0
remaining_plan_statements = 0
remaining_user_commissions = 0
missing_groups = []
missing_users = []

puts %w[line bucket gf_id gf_remaining plan_statements_remaining user_commissions_remaining group_kept user_kept].join('@')

targets.each do |target|
  begin
    groupification = Groupification.find_by(id: target[:gf_id])
    gf_remaining = groupification.nil? ? 0 : 1
    remaining_groupifications += gf_remaining

    group = Group.find_by(id: target[:group_id])
    user = User.find_by(id: target[:user_id])
    missing_groups << target[:group_id] if group.nil?
    missing_users << target[:user_id] if user.nil?

    plan_ids = group.nil? ? [] : group.plans.select(:id)
    plan_statement_remaining = group.nil? ? 0 : PlanStatement.where(user_id: target[:user_id], plan_id: plan_ids).count
    user_commission_remaining = group.nil? ? 0 : UserCommission.joins(:commission).where(user_id: target[:user_id], commissions: { plan_id: plan_ids }).count
    remaining_plan_statements += plan_statement_remaining
    remaining_user_commissions += user_commission_remaining

    puts [
      target[:line], target[:bucket], target[:gf_id],
      gf_remaining, plan_statement_remaining, user_commission_remaining,
      group.nil? ? 'GROUP_MISSING' : 'kept', user.nil? ? 'USER_MISSING' : 'kept'
    ].join('@')
  rescue StandardError => error
    puts [target[:line], target[:bucket], target[:gf_id], "ERROR: #{error.message}", '-', '-', '-', '-'].join('@')
  end
end

puts '---'
puts "REMAINING_groupifications@#{remaining_groupifications}"    # expect 0
puts "REMAINING_plan_statements@#{remaining_plan_statements}"    # expect 0
puts "REMAINING_user_commissions@#{remaining_user_commissions}"  # expect 0
puts "GROUPS_missing@#{missing_groups.uniq.sort}"                # expect [] (groups KEPT)
puts "USERS_missing@#{missing_users.uniq.sort}"                  # expect [] (users KEPT)
puts 'VERIFICATION_DONE@' + company.name.to_s
