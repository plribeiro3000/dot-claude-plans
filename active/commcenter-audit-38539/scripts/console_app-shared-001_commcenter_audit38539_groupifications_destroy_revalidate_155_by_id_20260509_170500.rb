# Re-validation -- For each of the 155 resolved groupification_ids, check whether destroy is safe by going from
# Groupification.find(id) directly to its group.plans and then to PlanStatement(plan_id, user_id).
# No identifier lookup, no ambiguity. The user_id used here comes straight from groupification.user_id.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Output is ";"-separated.

groupification_ids = [
  705422, 705430, 654485, 705369, 705403, 705551, 705580, 558283,
  558487, 558503,
  705552, 705555, 705560, 705566, 705399, 705401, 705404, 705410,
  705411, 705426, 705428, 705431, 705438, 705439, 705423, 705425,
  705441, 705408, 705418, 705413, 705443, 705421, 705424, 705558,
  705559, 705567, 705583, 705586, 705589, 705590, 705595, 705608,
  705611, 705612, 705358, 705371, 705409, 705427, 705429, 705419,
  654493, 705373, 705390, 705391, 705393, 705394, 705395, 705396,
  705397, 705398, 705402, 705407, 705414, 705416, 705417, 705437,
  705440, 705415, 705412, 705432, 705434, 705545, 705546, 705547,
  705548, 705549, 705550, 705553, 705554, 705556, 705557, 705561,
  705562, 705563, 705564, 705565, 705568, 705569, 705570, 705571,
  705572, 705573, 705574, 705575, 705576, 705577, 705578, 705579,
  705581, 705582, 705584, 705591, 705593, 705594, 705596, 705597,
  705598, 705601, 705603, 705606, 705607, 705609, 705365, 705366,
  705368, 705375, 705382, 705383, 705384, 705385, 705386, 705388,
  705588, 705433, 705420, 705360, 705361, 705370, 705387, 705389,
  705405, 705585, 705592, 705599, 705605, 705610, 705613, 705359,
  705362, 705363, 705364, 705367, 705372, 705374, 705376, 705377,
  705378, 705380, 705392, 705400, 705406, 705587, 705600, 705602,
  705604
]

puts ''
puts '=== START Re-validation: destroy viability of 155 groupifications by id ==='
puts %w[
  step
  groupification_id
  user_id
  group_id
  group_name
  group_plans_count
  blocking_plan_statements_count
  blocking_plan_ids
  result
].join(';')

ok_count = 0
blocked_count = 0
not_found_count = 0

groupification_ids.each_with_index do |groupification_id, index|
  user_id = ''
  group_id = ''
  group_name = ''
  group_plans_count = ''
  blocking_plan_statements_count = ''
  blocking_plan_ids = ''
  result = 'PENDING'

  groupification = Groupification.find_by(id: groupification_id)

  if groupification.nil?
    result = 'GROUPIFICATION_NOT_FOUND'
    not_found_count += 1
  else
    user_id = groupification.user_id
    group = groupification.group
    group_id = group.present? ? group.id : ''
    group_name = group.present? ? group.name : ''

    if group.nil?
      result = 'GROUP_NOT_FOUND'
      not_found_count += 1
    else
      plan_ids = group.plans.pluck(:id)
      group_plans_count = plan_ids.size

      if plan_ids.empty?
        blocking_plan_statements_count = 0
        result = 'OK_NO_PLANS_IN_GROUP'
        ok_count += 1
      else
        blocking_statements = PlanStatement.where(plan_id: plan_ids, user_id: user_id)
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
    groupification_id,
    user_id,
    group_id,
    group_name,
    group_plans_count,
    blocking_plan_statements_count,
    blocking_plan_ids,
    result
  ].join(';')
end

puts ''
puts "Re-validation SUMMARY: ok=#{ok_count} blocked=#{blocked_count} not_found=#{not_found_count} total=#{groupification_ids.size}"
puts '=== END Re-validation ==='
