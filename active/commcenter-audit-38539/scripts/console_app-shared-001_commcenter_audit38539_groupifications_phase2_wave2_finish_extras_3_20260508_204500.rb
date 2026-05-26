# Phase 2 Wave 2 -- ALREADY_IN_TARGET_PLUS_OTHERS (3 users): leave the target group untouched and finish the other active groupifications.
# Stack: app-shared-001 (multi-tenant). No transaction across users -- each user is independent.
# Date rule: last_history.ends_at if present, otherwise last_history.starts_at, plus 1 day.
# For active groupifications last_history.ends_at is nil, so we fall back to starts_at + 1 day.
# Output is ";"-separated.

PLANNED_FINISHES = [
  { user_id: 1026105, group_to_finish_internal_id: 40345, group_to_finish_name: 'PAP_Supervisor' },
  { user_id: 1026093, group_to_finish_internal_id: 40345, group_to_finish_name: 'PAP_Supervisor' },
  { user_id: 1243859, group_to_finish_internal_id: 48179, group_to_finish_name: 'TERRA_Vendedor_Callcenter' }
].freeze

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Phase 2 Wave 2: finish extras (3 users) ==='
puts %w[step user_id user_name group_to_finish_internal_id group_to_finish_name ends_at result errors].join(';')

ok_count = 0
failed_count = 0

PLANNED_FINISHES.each_with_index do |action, index|
  result = 'PENDING'
  errors_text = ''
  ends_at_value = ''
  user_name = ''

  user = company.users.find_by(id: action[:user_id])

  if user.nil?
    result = 'USER_NOT_FOUND'
  else
    user_name = user.name
    groupification = Groupification.find_by(group_id: action[:group_to_finish_internal_id], user_id: user.id)

    if groupification.nil?
      result = 'GROUPIFICATION_NOT_FOUND'
    elsif groupification.inactive?
      result = 'ALREADY_INACTIVE'
    else
      last_history = groupification.histories.order(:starts_at).last

      if last_history.nil?
        result = 'NO_HISTORY'
      else
        reference_date = last_history.ends_at.present? ? last_history.ends_at : last_history.starts_at
        ends_at_value = reference_date.to_date + 1.day

        if groupification.finish(ends_at: ends_at_value)
          result = 'OK'
        else
          result = 'FINISH_FAILED'
          errors_text = groupification.errors.full_messages.join('|')
        end
      end
    end
  end

  if result == 'OK'
    ok_count += 1
  else
    failed_count += 1
  end

  puts [index + 1, action[:user_id], user_name, action[:group_to_finish_internal_id], action[:group_to_finish_name], ends_at_value, result, errors_text].join(';')
end

puts ''
puts "Phase 2 Wave 2 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{PLANNED_FINISHES.size}"
puts '=== END Phase 2 Wave 2 ==='
