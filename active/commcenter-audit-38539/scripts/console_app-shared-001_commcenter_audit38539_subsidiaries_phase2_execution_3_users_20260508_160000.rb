# Phase 2 -- Subsidiary migration of the 3 primary identifiers from sub 3 (internal 3788) to sub 14 (internal 3954).
# Stack: app-shared-001 (multi-tenant). Strategy: delete + create within a transaction (option B).
# Scope is strict: only the primary identifier listed in the customer XLSX is moved. Secondary "4sk_*"
# identifiers stay where they are (per the engineer's instruction).
# Per-user sequence:
#   1. Open a transaction.
#   2. Build a new UserIdentifier in the target subsidiary with primary=false.
#   3. Call .promote on the new identifier -- this zeros every primary on the user, then sets new=primary=true,
#      flipping the old identifier to primary=false in the same transaction.
#   4. Reload the old identifier and destroy it (validate_primary_existence now passes because primary=false).
#   5. Commit.
# Output is ";"-separated; "@" collides with email addresses.

PLANNED_ACTIONS = [
  { user_id: 1026105, primary_identifier_id: 633050, value: '1926540' },
  { user_id: 1026093, primary_identifier_id: 633053, value: '1926629' },
  { user_id: 1026079, primary_identifier_id: 553337, value: '1922319' }
].freeze
TARGET_SUBSIDIARY_INTERNAL_ID = 3954
COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Phase 2: subsidiary migration (3 primary identifiers) ==='
puts %w[step user_id old_identifier_id value new_identifier_id result errors].join(';')

ok_count = 0
failed_count = 0

PLANNED_ACTIONS.each_with_index do |action, index|
  result = 'PENDING'
  errors_text = ''
  new_identifier_id = ''

  UserIdentifier.transaction do
    old_identifier = company.user_identifiers.find_by(id: action[:primary_identifier_id])

    if old_identifier.nil?
      result = 'OLD_NOT_FOUND'
      raise ActiveRecord::Rollback
    end

    if old_identifier.value != action[:value] || old_identifier.user_id != action[:user_id] || !old_identifier.primary
      result = 'OLD_MISMATCH'
      errors_text = "value=#{old_identifier.value} user_id=#{old_identifier.user_id} primary=#{old_identifier.primary}"
      raise ActiveRecord::Rollback
    end

    new_identifier = UserIdentifier.new(
      company_id: company.id,
      user_id: old_identifier.user_id,
      subsidiary_id: TARGET_SUBSIDIARY_INTERNAL_ID,
      value: old_identifier.value,
      primary: false
    )

    if !new_identifier.save
      result = 'NEW_INVALID'
      errors_text = new_identifier.errors.full_messages.join('|')
      raise ActiveRecord::Rollback
    end

    new_identifier_id = new_identifier.id

    if !new_identifier.promote
      result = 'PROMOTE_FAILED'
      errors_text = new_identifier.errors.full_messages.join('|')
      raise ActiveRecord::Rollback
    end

    old_identifier.reload

    if !old_identifier.destroy
      result = 'OLD_DESTROY_FAILED'
      errors_text = old_identifier.errors.full_messages.join('|')
      raise ActiveRecord::Rollback
    end

    result = 'OK'
  end

  if result == 'OK'
    ok_count += 1
  else
    failed_count += 1
  end

  puts [index + 1, action[:user_id], action[:primary_identifier_id], action[:value], new_identifier_id, result, errors_text].join(';')
end

puts ''
puts "Phase 2 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{PLANNED_ACTIONS.size}"
puts '=== END Phase 2 ==='
