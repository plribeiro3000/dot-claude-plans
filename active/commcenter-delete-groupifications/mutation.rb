# Phase 2 — MUTATION (DESTRUCTIVE). Commcenter groupification deletion.
# app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001 'bundle exec rails console'
# Destroys, per target: the user's UserCommission(s) + PlanStatement(s) in the group's
# plans, then the Groupification itself. Each target runs in its own transaction (atomic
# per participation) and per-target errors are logged and skipped (never aborts the run).
# Bucket A targets have 0 plan/commission, so only the Groupification is destroyed.
# Cascades (verified): UserCommission.destroy -> eligibility_periods/statements/rankings/etc.;
# PlanStatement.destroy blocked by user_plan_statement_histories (restrict) -> cleared first
# (pure link rows, no callbacks); Groupification.destroy -> its histories.

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

targets.each do |target|
  begin
    ActiveRecord::Base.transaction do
      groupification = Groupification.find_by(id: target[:gf_id], user_id: target[:user_id], group_id: target[:group_id])
      raise "groupification #{target[:gf_id]} not found or drifted" if groupification.nil?

      plan_ids = Group.find(target[:group_id]).plans.select(:id)

      user_commission_ids = UserCommission.joins(:commission).where(user_id: target[:user_id], commissions: { plan_id: plan_ids }).pluck(:id)
      user_commission_ids.each { |user_commission_id| UserCommission.find(user_commission_id).destroy! }

      plan_statement_ids = PlanStatement.where(user_id: target[:user_id], plan_id: plan_ids).pluck(:id)
      plan_statement_ids.each do |plan_statement_id|
        plan_statement = PlanStatement.find(plan_statement_id)
        plan_statement.user_plan_statement_histories.delete_all
        plan_statement.destroy!
      end

      groupification.destroy!

      puts "OK@line#{target[:line]}@#{target[:bucket]}@gf#{target[:gf_id]}@uc_destroyed#{user_commission_ids.size}@ps_destroyed#{plan_statement_ids.size}"
    end
  rescue StandardError => error
    puts "FAIL@line#{target[:line]}@#{target[:bucket]}@gf#{target[:gf_id]}@#{error.message}"
  end
end

puts 'MUTATION_DONE@' + company.name.to_s
