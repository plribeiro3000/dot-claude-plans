# Phase 2 -- Start 125 unique groupifications at the correct groups (Patrick's "grupo correto").
# Stack: app-shared-001 (multi-tenant). No transaction across rows -- each row is independent.
# starts_at fixed at 2026-01-01 per the engineer's instruction.
# Source: 147 (user_id, target_group_internal_id) pairs from Patrick's XLSX, dedup'ed against duplicate (user, group)
# pairs reported by the validation. 22 duplicates were removed -- one start covers each unique pair.
# Defensive: groupification.start returns false with `:already_active` if it already is, so re-run is safe.
# Output is ";"-separated.

planned_starts = [
  { user_id: 1243865, target_group_internal_id: 50215 },
  { user_id: 1243873, target_group_internal_id: 48184 },
  { user_id: 1026093, target_group_internal_id: 50216 },
  { user_id: 1026105, target_group_internal_id: 40315 },
  { user_id: 1243774, target_group_internal_id: 50216 },
  { user_id: 1119700, target_group_internal_id: 40315 },
  { user_id: 1119697, target_group_internal_id: 40315 },
  { user_id: 1026079, target_group_internal_id: 40314 },
  { user_id: 1119733, target_group_internal_id: 48175 },
  { user_id: 1119725, target_group_internal_id: 48175 },
  { user_id: 1119724, target_group_internal_id: 48175 },
  { user_id: 1119846, target_group_internal_id: 48175 },
  { user_id: 1243775, target_group_internal_id: 50216 },
  { user_id: 1119923, target_group_internal_id: 48179 },
  { user_id: 1243846, target_group_internal_id: 48177 },
  { user_id: 1243860, target_group_internal_id: 48182 },
  { user_id: 1243869, target_group_internal_id: 48182 },
  { user_id: 1243859, target_group_internal_id: 48182 },
  { user_id: 1243872, target_group_internal_id: 48182 },
  { user_id: 1243875, target_group_internal_id: 48182 },
  { user_id: 1243854, target_group_internal_id: 48182 },
  { user_id: 1243866, target_group_internal_id: 48182 },
  { user_id: 1243876, target_group_internal_id: 48179 },
  { user_id: 1243861, target_group_internal_id: 48177 },
  { user_id: 1243863, target_group_internal_id: 48179 },
  { user_id: 1243862, target_group_internal_id: 50215 },
  { user_id: 1243878, target_group_internal_id: 48179 },
  { user_id: 1243858, target_group_internal_id: 48182 },
  { user_id: 1119789, target_group_internal_id: 48179 },
  { user_id: 1119768, target_group_internal_id: 48179 },
  { user_id: 1119784, target_group_internal_id: 48179 },
  { user_id: 1243841, target_group_internal_id: 48179 },
  { user_id: 1243794, target_group_internal_id: 48179 },
  { user_id: 1243845, target_group_internal_id: 48179 },
  { user_id: 1243864, target_group_internal_id: 48179 },
  { user_id: 1243796, target_group_internal_id: 48179 },
  { user_id: 1243867, target_group_internal_id: 48179 },
  { user_id: 1243842, target_group_internal_id: 48179 },
  { user_id: 1243792, target_group_internal_id: 48179 },
  { user_id: 1119734, target_group_internal_id: 48177 },
  { user_id: 1119704, target_group_internal_id: 48177 },
  { user_id: 1119776, target_group_internal_id: 48182 },
  { user_id: 1243791, target_group_internal_id: 48182 },
  { user_id: 1243787, target_group_internal_id: 48182 },
  { user_id: 1243785, target_group_internal_id: 48182 },
  { user_id: 1243783, target_group_internal_id: 48182 },
  { user_id: 1243770, target_group_internal_id: 48182 },
  { user_id: 1243788, target_group_internal_id: 48182 },
  { user_id: 1243808, target_group_internal_id: 48182 },
  { user_id: 1243804, target_group_internal_id: 48182 },
  { user_id: 1243772, target_group_internal_id: 40315 },
  { user_id: 1243798, target_group_internal_id: 48182 },
  { user_id: 1243874, target_group_internal_id: 48187 },
  { user_id: 1128996, target_group_internal_id: 48182 },
  { user_id: 1129000, target_group_internal_id: 48182 },
  { user_id: 1129007, target_group_internal_id: 48182 },
  { user_id: 1128999, target_group_internal_id: 48182 },
  { user_id: 1129015, target_group_internal_id: 48182 },
  { user_id: 1119738, target_group_internal_id: 48182 },
  { user_id: 1119787, target_group_internal_id: 48182 },
  { user_id: 1119746, target_group_internal_id: 48182 },
  { user_id: 1119754, target_group_internal_id: 48182 },
  { user_id: 1119775, target_group_internal_id: 48182 },
  { user_id: 1119823, target_group_internal_id: 48182 },
  { user_id: 1119765, target_group_internal_id: 48182 },
  { user_id: 1119727, target_group_internal_id: 48182 },
  { user_id: 1119840, target_group_internal_id: 48182 },
  { user_id: 1119930, target_group_internal_id: 48182 },
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
  { user_id: 1243818, target_group_internal_id: 48182 },
  { user_id: 1243843, target_group_internal_id: 48182 },
  { user_id: 1243911, target_group_internal_id: 48182 },
  { user_id: 1128986, target_group_internal_id: 48182 },
  { user_id: 1243870, target_group_internal_id: 48182 },
  { user_id: 1243802, target_group_internal_id: 48182 },
  { user_id: 1243789, target_group_internal_id: 48182 },
  { user_id: 1243905, target_group_internal_id: 48182 },
  { user_id: 1243871, target_group_internal_id: 48182 },
  { user_id: 1243916, target_group_internal_id: 48182 },
  { user_id: 1243928, target_group_internal_id: 48182 },
  { user_id: 1243907, target_group_internal_id: 48182 },
  { user_id: 1243921, target_group_internal_id: 48182 },
  { user_id: 1243813, target_group_internal_id: 48182 },
  { user_id: 1119702, target_group_internal_id: 50212 },
  { user_id: 1129009, target_group_internal_id: 50212 },
  { user_id: 1119764, target_group_internal_id: 50212 },
  { user_id: 1129005, target_group_internal_id: 50212 },
  { user_id: 1128984, target_group_internal_id: 50212 },
  { user_id: 1119717, target_group_internal_id: 50212 },
  { user_id: 1119713, target_group_internal_id: 50212 },
  { user_id: 1119709, target_group_internal_id: 50212 },
  { user_id: 1119721, target_group_internal_id: 50212 },
  { user_id: 1119712, target_group_internal_id: 50212 },
  { user_id: 1119878, target_group_internal_id: 50213 },
  { user_id: 1243914, target_group_internal_id: 50215 },
  { user_id: 1243909, target_group_internal_id: 50215 },
  { user_id: 1243906, target_group_internal_id: 50215 },
  { user_id: 1243918, target_group_internal_id: 50215 },
  { user_id: 1128988, target_group_internal_id: 50216 },
  { user_id: 1119703, target_group_internal_id: 50216 },
  { user_id: 1129008, target_group_internal_id: 50216 },
  { user_id: 1128990, target_group_internal_id: 50216 },
  { user_id: 1119802, target_group_internal_id: 50216 },
  { user_id: 1119715, target_group_internal_id: 50216 },
  { user_id: 1119722, target_group_internal_id: 50216 },
  { user_id: 1128985, target_group_internal_id: 50216 },
  { user_id: 1119708, target_group_internal_id: 50216 },
  { user_id: 1119710, target_group_internal_id: 50216 },
  { user_id: 1119718, target_group_internal_id: 50216 },
  { user_id: 1243771, target_group_internal_id: 50216 },
  { user_id: 1119714, target_group_internal_id: 50216 },
  { user_id: 1119705, target_group_internal_id: 50216 },
  { user_id: 1119701, target_group_internal_id: 50216 },
  { user_id: 1119707, target_group_internal_id: 50216 }
]

starts_at_value = Date.new(2026, 1, 1)

puts ''
puts '=== START Phase 2: start 125 groupifications at correct groups ==='
puts %w[step user_id target_group_internal_id target_group_name groupification_id starts_at result errors].join(';')

ok_count = 0
already_active_count = 0
failed_count = 0

planned_starts.each_with_index do |action, index|
  step = index + 1
  result = 'PENDING'
  errors_text = ''
  groupification_id = ''
  target_group_name = ''

  group = Group.find_by(id: action[:target_group_internal_id])

  if group.nil?
    result = 'GROUP_NOT_FOUND'
    failed_count += 1
  else
    target_group_name = group.name
    groupification = Groupification.find_or_initialize_by(group_id: group.id, user_id: action[:user_id])

    if groupification.persisted? && groupification.ends_at.nil?
      groupification_id = groupification.id
      result = 'ALREADY_ACTIVE'
      already_active_count += 1
    else
      saved = groupification.start(starts_at: starts_at_value)
      groupification_id = groupification.id

      if saved
        result = 'OK_STARTED'
        ok_count += 1
      else
        result = 'START_FAILED'
        errors_text = groupification.errors.full_messages.join('|')
        failed_count += 1
      end
    end
  end

  puts [
    step,
    action[:user_id],
    action[:target_group_internal_id],
    target_group_name,
    groupification_id,
    starts_at_value,
    result,
    errors_text
  ].join(';')
end

puts ''
puts "Phase 2 SUMMARY: ok=#{ok_count} already_active=#{already_active_count} failed=#{failed_count} total=#{planned_starts.size}"
puts '=== END Phase 2 ==='
