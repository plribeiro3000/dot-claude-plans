# Validation -- For each "SEM GRUPO" entry from Patrick's XLSX, check whether the existing groupification can be safely
# removed without leaving plan_statements orphaned.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Business rule: a groupification cannot be removed if any plan_statement (declaration) exists for the user on any plan
# attached to the group. If the group has no plans at all, no statement check is needed.
# Output is ";"-separated; "@" collides with email addresses.

PLANNED_DESTROYS = [
  { user_identifier_value: '1917259', group_external_id: '30' },
  { user_identifier_value: '1919025', group_external_id: '30' },
  { user_identifier_value: '1916502', group_external_id: '27' },
  { user_identifier_value: '1919025', group_external_id: '27' },
  { user_identifier_value: '1915698', group_external_id: '27' },
  { user_identifier_value: '1917259', group_external_id: '27' },
  { user_identifier_value: '1916502', group_external_id: '24' },
  { user_identifier_value: '1915698', group_external_id: '24' },
  { user_identifier_value: '1923605', group_external_id: '33' },
  { user_identifier_value: '1917531', group_external_id: '33' }
].freeze

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Validation: destroy viability of 10 SEM GRUPO groupifications ==='
puts %w[
  step
  user_identifier
  user_name
  group_external_id
  group_name
  groupification_id
  groupification_active
  group_plans_count
  blocking_plan_statements_count
  blocking_plan_ids
  result
].join(';')

ok_count = 0
blocked_count = 0
error_count = 0

PLANNED_DESTROYS.each_with_index do |action, index|
  user_name = ''
  group_name = ''
  groupification_id = ''
  groupification_active = ''
  group_plans_count = ''
  blocking_plan_statements_count = ''
  blocking_plan_ids = ''
  result = 'PENDING'

  user_identifier = company.user_identifiers.find_by(value: action[:user_identifier_value])
  group = company.groups.find_by(external_id: action[:group_external_id])

  if user_identifier.nil?
    result = 'USER_IDENTIFIER_NOT_FOUND'
    error_count += 1
  elsif group.nil?
    result = 'GROUP_NOT_FOUND'
    error_count += 1
  elsif user_identifier.user.nil?
    result = 'USER_NOT_FOUND'
    error_count += 1
  else
    user = user_identifier.user
    user_name = user.name
    group_name = group.name

    groupification = Groupification.find_by(group_id: group.id, user_id: user.id)

    if groupification.nil?
      result = 'GROUPIFICATION_NOT_FOUND'
      error_count += 1
    else
      groupification_id = groupification.id
      groupification_active = groupification.ends_at.nil? ? 'true' : 'false'

      plan_ids = group.plans.pluck(:id)
      group_plans_count = plan_ids.size

      if plan_ids.empty?
        blocking_plan_statements_count = 0
        result = 'OK_NO_PLANS_IN_GROUP'
        ok_count += 1
      else
        blocking_statements = PlanStatement.where(plan_id: plan_ids, user_id: user.id)
        statements_count = blocking_statements.count

        if statements_count.zero?
          blocking_plan_statements_count = 0
          result = 'OK_NO_PLAN_STATEMENTS'
          ok_count += 1
        else
          blocking_plan_statements_count = statements_count
          blocking_plan_ids = blocking_statements.pluck(:plan_id).uniq.sort.join('|')
          result = 'BLOCKED_HAS_PLAN_STATEMENTS'
          blocked_count += 1
        end
      end
    end
  end

  puts [
    index + 1,
    action[:user_identifier_value],
    user_name,
    action[:group_external_id],
    group_name,
    groupification_id,
    groupification_active,
    group_plans_count,
    blocking_plan_statements_count,
    blocking_plan_ids,
    result
  ].join(';')
end

puts ''
puts "Validation SUMMARY: ok=#{ok_count} blocked=#{blocked_count} error=#{error_count} total=#{PLANNED_DESTROYS.size}"
puts '=== END Validation ==='
