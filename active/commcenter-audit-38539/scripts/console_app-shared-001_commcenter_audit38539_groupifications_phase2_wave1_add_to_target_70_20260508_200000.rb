# Phase 2 Wave 1 -- ADD_TO_TARGET (70 users without any active groupification, just start at the target group).
# Stack: app-shared-001 (multi-tenant). No transaction across users -- each user is independent.
# Date rule: Date.today when there is no prior Groupification for this (user, target group).
# When a Groupification record already exists (inactive), use last_history.ends_at if set,
# otherwise last_history.starts_at, plus 1 day.
# Output is ";"-separated.

PLANNED_ACTIONS = [
  { user_id: 1128996, target_group_internal_id: 48182 },
  { user_id: 1129000, target_group_internal_id: 48182 },
  { user_id: 1129007, target_group_internal_id: 48182 },
  { user_id: 1128999, target_group_internal_id: 48182 },
  { user_id: 1129015, target_group_internal_id: 48182 },
  { user_id: 1119738, target_group_internal_id: 48182 },
  { user_id: 1119700, target_group_internal_id: 40315 },
  { user_id: 1119733, target_group_internal_id: 48175 },
  { user_id: 1119787, target_group_internal_id: 48182 },
  { user_id: 1119746, target_group_internal_id: 48182 },
  { user_id: 1119725, target_group_internal_id: 48175 },
  { user_id: 1119754, target_group_internal_id: 48182 },
  { user_id: 1119775, target_group_internal_id: 48182 },
  { user_id: 1119789, target_group_internal_id: 48179 },
  { user_id: 1119768, target_group_internal_id: 48179 },
  { user_id: 1119724, target_group_internal_id: 48175 },
  { user_id: 1119823, target_group_internal_id: 48182 },
  { user_id: 1119765, target_group_internal_id: 48182 },
  { user_id: 1119727, target_group_internal_id: 48182 },
  { user_id: 1119840, target_group_internal_id: 48182 },
  { user_id: 1119930, target_group_internal_id: 48182 },
  { user_id: 1119846, target_group_internal_id: 48175 },
  { user_id: 1119784, target_group_internal_id: 48179 },
  { user_id: 1119838, target_group_internal_id: 48182 },
  { user_id: 1119851, target_group_internal_id: 48182 },
  { user_id: 1119936, target_group_internal_id: 48182 },
  { user_id: 1119933, target_group_internal_id: 48182 },
  { user_id: 1119758, target_group_internal_id: 48182 },
  { user_id: 1119774, target_group_internal_id: 48182 },
  { user_id: 1119797, target_group_internal_id: 48182 },
  { user_id: 1119929, target_group_internal_id: 48182 },
  { user_id: 1119938, target_group_internal_id: 48182 },
  { user_id: 1119859, target_group_internal_id: 48182 },
  { user_id: 1119928, target_group_internal_id: 48182 },
  { user_id: 1243786, target_group_internal_id: 48182 },
  { user_id: 1119697, target_group_internal_id: 40315 },
  { user_id: 1243863, target_group_internal_id: 48179 },
  { user_id: 1243818, target_group_internal_id: 48182 },
  { user_id: 1243843, target_group_internal_id: 48182 },
  { user_id: 1243841, target_group_internal_id: 48179 },
  { user_id: 1243911, target_group_internal_id: 48182 },
  { user_id: 1243914, target_group_internal_id: 50215 },
  { user_id: 1243794, target_group_internal_id: 48179 },
  { user_id: 1119714, target_group_internal_id: 50216 },
  { user_id: 1119878, target_group_internal_id: 50213 },
  { user_id: 1243845, target_group_internal_id: 48179 },
  { user_id: 1243864, target_group_internal_id: 48179 },
  { user_id: 1128986, target_group_internal_id: 48182 },
  { user_id: 1243909, target_group_internal_id: 50215 },
  { user_id: 1243870, target_group_internal_id: 48182 },
  { user_id: 1243802, target_group_internal_id: 48182 },
  { user_id: 1243796, target_group_internal_id: 48179 },
  { user_id: 1243789, target_group_internal_id: 48182 },
  { user_id: 1243905, target_group_internal_id: 48182 },
  { user_id: 1243871, target_group_internal_id: 48182 },
  { user_id: 1243906, target_group_internal_id: 50215 },
  { user_id: 1119705, target_group_internal_id: 50216 },
  { user_id: 1243916, target_group_internal_id: 48182 },
  { user_id: 1119701, target_group_internal_id: 50216 },
  { user_id: 1243928, target_group_internal_id: 48182 },
  { user_id: 1119707, target_group_internal_id: 50216 },
  { user_id: 1243918, target_group_internal_id: 50215 },
  { user_id: 1243907, target_group_internal_id: 48182 },
  { user_id: 1243921, target_group_internal_id: 48182 },
  { user_id: 1243867, target_group_internal_id: 48179 },
  { user_id: 1243813, target_group_internal_id: 48182 },
  { user_id: 1243862, target_group_internal_id: 50215 },
  { user_id: 1243842, target_group_internal_id: 48179 },
  { user_id: 1243792, target_group_internal_id: 48179 },
  { user_id: 1243865, target_group_internal_id: 50215 }
].freeze

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Phase 2 Wave 1: ADD_TO_TARGET (70 users) ==='
puts %w[step user_id user_name target_group_internal_id starts_at result errors].join(';')

ok_count = 0
failed_count = 0

PLANNED_ACTIONS.each_with_index do |action, index|
  result = 'PENDING'
  errors_text = ''
  starts_at_value = ''
  user_name = ''

  user = company.users.find_by(id: action[:user_id])
  target_group = company.groups.find_by(id: action[:target_group_internal_id])

  if user.nil?
    result = 'USER_NOT_FOUND'
  elsif target_group.nil?
    result = 'TARGET_GROUP_NOT_FOUND'
  else
    user_name = user.name
    groupification = Groupification.find_or_initialize_by(group_id: target_group.id, user_id: user.id)

    last_history = groupification.new_record? ? nil : groupification.histories.order(:starts_at).last

    if last_history.nil?
      starts_at_value = Date.today
    else
      reference_date = last_history.ends_at.present? ? last_history.ends_at : last_history.starts_at
      starts_at_value = reference_date.to_date + 1.day
    end

    if groupification.start(starts_at: starts_at_value)
      result = 'OK'
    else
      result = 'START_FAILED'
      errors_text = groupification.errors.full_messages.join('|')
    end
  end

  if result == 'OK'
    ok_count += 1
  else
    failed_count += 1
  end

  puts [index + 1, action[:user_id], user_name, action[:target_group_internal_id], starts_at_value, result, errors_text].join(';')
end

puts ''
puts "Phase 2 Wave 1 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{PLANNED_ACTIONS.size}"
puts '=== END Phase 2 Wave 1 ==='
