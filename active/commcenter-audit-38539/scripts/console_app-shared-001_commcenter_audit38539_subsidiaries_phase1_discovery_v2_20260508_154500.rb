# Phase 1 v2 -- Discovery for the subsidiary sheet (3 users moving from sub 3 to sub 14).
# Stack: app-shared-001 (multi-tenant). No side effects.
# Output is ";"-separated; "@" collides with email addresses.
# v2 fixes the subordinate query: hierarchy lives in Seat (parent polymorphic, parent_type='Seat'), not on users.parent_id.
# Regenerated from scratch -- previous output is invalid because the script aborted mid-run.

PLANNED_USER_IDS = [1026105, 1026093, 1026079].freeze
SOURCE_SUBSIDIARY_EXTERNAL_ID = '3'
TARGET_SUBSIDIARY_EXTERNAL_ID = '14'

company = Company.find(2077)

source_subsidiary = company.subsidiaries.find_by(external_id: SOURCE_SUBSIDIARY_EXTERNAL_ID)
target_subsidiary = company.subsidiaries.find_by(external_id: TARGET_SUBSIDIARY_EXTERNAL_ID)

puts ''
puts '=== START Phase 1 v2: subsidiaries discovery ==='
puts ''
puts 'subsidiaries_resolved'
puts %w[external_id internal_id name unique_register_id register_type].join(';')
[source_subsidiary, target_subsidiary].each do |subsidiary|
  if subsidiary.nil?
    puts ['MISSING', '', '', '', ''].join(';')
    next
  end
  puts [subsidiary.external_id, subsidiary.id, subsidiary.name, subsidiary.unique_register_id, subsidiary.register_type].join(';')
end

puts ''
puts 'identifiers_per_user'
puts %w[user_id user_name identifier_id identifier_value identifier_subsidiary_internal_id identifier_subsidiary_external_id primary identifier_disabled_at user_disabled_at].join(';')

PLANNED_USER_IDS.each do |user_id|
  user = company.users.find_by(id: user_id)

  if user.nil?
    puts [user_id, 'USER_NOT_FOUND', '', '', '', '', '', '', ''].join(';')
    next
  end

  user.identifiers.each do |identifier|
    identifier_subsidiary = identifier.subsidiary
    identifier_subsidiary_external_id = identifier_subsidiary.present? ? identifier_subsidiary.external_id : ''
    identifier_subsidiary_internal_id = identifier_subsidiary.present? ? identifier_subsidiary.id : ''

    puts [
      user.id,
      user.name,
      identifier.id,
      identifier.value,
      identifier_subsidiary_internal_id,
      identifier_subsidiary_external_id,
      identifier.primary,
      identifier.disabled_at,
      user.disabled_at
    ].join(';')
  end
end

puts ''
puts 'conflict_check_target_subsidiary'
puts %w[user_id identifier_value conflicting_identifier_id conflicting_user_id conflicting_user_name].join(';')

if target_subsidiary.nil?
  puts ['', '', 'TARGET_SUBSIDIARY_MISSING', '', ''].join(';')
else
  PLANNED_USER_IDS.each do |user_id|
    user = company.users.find_by(id: user_id)
    next if user.nil?

    user.identifiers.each do |identifier|
      conflicting = company.user_identifiers
                           .where(subsidiary_id: target_subsidiary.id, value: identifier.value)
                           .where.not(id: identifier.id)
                           .first

      if conflicting.nil?
        puts [user.id, identifier.value, 'NONE', '', ''].join(';')
      else
        conflicting_user = conflicting.user
        conflicting_user_name = conflicting_user.present? ? conflicting_user.name : ''
        puts [user.id, identifier.value, conflicting.id, conflicting.user_id, conflicting_user_name].join(';')
      end
    end
  end
end

puts ''
puts 'active_direct_subordinates_in_source_subsidiary'
puts %w[parent_user_id parent_user_name source_subsidiary_subordinates].join(';')

if source_subsidiary.nil?
  puts ['', '', 'SOURCE_SUBSIDIARY_MISSING'].join(';')
else
  PLANNED_USER_IDS.each do |user_id|
    user = company.users.find_by(id: user_id)
    next if user.nil?

    user_seat = user.seat
    if user_seat.nil?
      puts [user.id, user.name, 'USER_HAS_NO_SEAT'].join(';')
      next
    end

    subordinate_count = user_seat.subordinates
                                 .joins(user: :identifiers)
                                 .where(user_identifiers: { subsidiary_id: source_subsidiary.id, primary: true })
                                 .where(users: { disabled_at: nil })
                                 .distinct
                                 .count

    puts [user.id, user.name, subordinate_count].join(';')
  end
end

puts ''
puts '=== END Phase 1 v2 ==='
