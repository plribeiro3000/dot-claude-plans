# Phase 3 -- Verification of the subsidiary migration executed in Phase 2.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Output is ";"-separated.
# For each user, expected end state:
#   - exactly 1 identifier in sub 14 (internal 3954) with primary=true and the original primary value
#   - the secondary "4sk_*" identifier still in sub 3 (internal 3788), primary=false (unchanged)
# Plus an explicit check that the previous primary identifier IDs (in sub 3) no longer exist.

EXPECTED = [
  { user_id: 1026105, expected_primary_value: '1926540', destroyed_old_identifier_id: 633050 },
  { user_id: 1026093, expected_primary_value: '1926629', destroyed_old_identifier_id: 633053 },
  { user_id: 1026079, expected_primary_value: '1922319', destroyed_old_identifier_id: 553337 }
].freeze
SOURCE_SUBSIDIARY_INTERNAL_ID = 3788
TARGET_SUBSIDIARY_INTERNAL_ID = 3954
COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Phase 3: subsidiary migration verification ==='
puts ''
puts 'identifiers_per_user_after_migration'
puts %w[user_id user_name identifier_id identifier_value identifier_subsidiary_internal_id primary identifier_disabled_at].join(';')

EXPECTED.each do |entry|
  user = company.users.find_by(id: entry[:user_id])

  if user.nil?
    puts [entry[:user_id], 'USER_NOT_FOUND', '', '', '', '', ''].join(';')
    next
  end

  user.identifiers.reload.each do |identifier|
    puts [
      user.id,
      user.name,
      identifier.id,
      identifier.value,
      identifier.subsidiary_id,
      identifier.primary,
      identifier.disabled_at
    ].join(';')
  end
end

puts ''
puts 'destroyed_old_identifier_check'
puts %w[user_id destroyed_old_identifier_id still_exists].join(';')

EXPECTED.each do |entry|
  still_exists = UserIdentifier.exists?(id: entry[:destroyed_old_identifier_id])
  puts [entry[:user_id], entry[:destroyed_old_identifier_id], still_exists].join(';')
end

puts ''
puts 'expected_state_assertions'
puts %w[user_id expected_primary_value primary_in_target_sub primary_value_match secondary_in_source_sub identifier_count].join(';')

EXPECTED.each do |entry|
  user = company.users.find_by(id: entry[:user_id])
  if user.nil?
    puts [entry[:user_id], entry[:expected_primary_value], 'USER_NOT_FOUND', '', '', ''].join(';')
    next
  end

  identifiers = user.identifiers.reload
  primary_identifier = identifiers.find(&:primary)
  primary_in_target_sub = primary_identifier.present? && primary_identifier.subsidiary_id == TARGET_SUBSIDIARY_INTERNAL_ID
  primary_value_match = primary_identifier.present? && primary_identifier.value == entry[:expected_primary_value]
  secondary_in_source_sub = identifiers.any? { |identifier| !identifier.primary && identifier.subsidiary_id == SOURCE_SUBSIDIARY_INTERNAL_ID }
  identifier_count = identifiers.size

  puts [
    user.id,
    entry[:expected_primary_value],
    primary_in_target_sub,
    primary_value_match,
    secondary_in_source_sub,
    identifier_count
  ].join(';')
end

puts ''
puts '=== END Phase 3 ==='
