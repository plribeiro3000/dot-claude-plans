# Validation -- For each of the 147 (user_id, target_group_internal_id) pairs derived from Patrick's "grupo correto",
# check the current state of the Groupification(target_group_id, user_id):
#   - If it does not exist     -> READY_TO_START_NEW       (will create on start)
#   - If it exists and active  -> ALREADY_ACTIVE           (start would be a no-op)
#   - If it exists and inactive -> READY_TO_RESUME         (start will resume)
# Stack: app-shared-001 (multi-tenant). No side effects.
# The 6 TERRA_VendedorII_PAP entries (group does not exist) and the 2 BLOCKED PAP_Supervisor entries are NOT in this list.
# Output is ";"-separated; "@" collides with email addresses.

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
  { user_id: 1243774, target_group_internal_id: 50216 },
  { user_id: 1243846, target_group_internal_id: 48177 },
  { user_id: 1243860, target_group_internal_id: 48182 },
  { user_id: 1243869, target_group_internal_id: 48182 },
  { user_id: 1243859, target_group_internal_id: 48182 },
  { user_id: 1243873, target_group_internal_id: 48184 },
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
  { user_id: 1243865, target_group_internal_id: 50215 },
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
  { user_id: 1243860, target_group_internal_id: 48182 },
  { user_id: 1243872, target_group_internal_id: 48182 },
  { user_id: 1243866, target_group_internal_id: 48182 },
  { user_id: 1243858, target_group_internal_id: 48182 },
  { user_id: 1026105, target_group_internal_id: 40315 },
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
  { user_id: 1243846, target_group_internal_id: 48177 },
  { user_id: 1243859, target_group_internal_id: 48182 },
  { user_id: 1243798, target_group_internal_id: 48182 },
  { user_id: 1243863, target_group_internal_id: 48179 },
  { user_id: 1243876, target_group_internal_id: 48179 },
  { user_id: 1243878, target_group_internal_id: 48179 },
  { user_id: 1243861, target_group_internal_id: 48177 },
  { user_id: 1243862, target_group_internal_id: 50215 },
  { user_id: 1243874, target_group_internal_id: 48187 },
  { user_id: 1243875, target_group_internal_id: 48182 },
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
  { user_id: 1243873, target_group_internal_id: 48184 },
  { user_id: 1243865, target_group_internal_id: 50215 },
  { user_id: 1243914, target_group_internal_id: 50215 },
  { user_id: 1243909, target_group_internal_id: 50215 },
  { user_id: 1243906, target_group_internal_id: 50215 },
  { user_id: 1243918, target_group_internal_id: 50215 },
  { user_id: 1243862, target_group_internal_id: 50215 },
  { user_id: 1243865, target_group_internal_id: 50215 },
  { user_id: 1128988, target_group_internal_id: 50216 },
  { user_id: 1119703, target_group_internal_id: 50216 },
  { user_id: 1129008, target_group_internal_id: 50216 },
  { user_id: 1026093, target_group_internal_id: 50216 },
  { user_id: 1128990, target_group_internal_id: 50216 },
  { user_id: 1119802, target_group_internal_id: 50216 },
  { user_id: 1119715, target_group_internal_id: 50216 },
  { user_id: 1119722, target_group_internal_id: 50216 },
  { user_id: 1128985, target_group_internal_id: 50216 },
  { user_id: 1119708, target_group_internal_id: 50216 },
  { user_id: 1119710, target_group_internal_id: 50216 },
  { user_id: 1119718, target_group_internal_id: 50216 },
  { user_id: 1243771, target_group_internal_id: 50216 },
  { user_id: 1243854, target_group_internal_id: 48182 },
  { user_id: 1119714, target_group_internal_id: 50216 },
  { user_id: 1119705, target_group_internal_id: 50216 },
  { user_id: 1119701, target_group_internal_id: 50216 },
  { user_id: 1119707, target_group_internal_id: 50216 }
]

puts ''
puts '=== START Start-validation: 147 (user_id, target_group) pairs ==='
puts %w[
  step
  user_id
  target_group_internal_id
  target_group_name
  groupification_id
  current_state
  current_starts_at
  current_ends_at
  result
].join(';')

ready_new_count = 0
ready_resume_count = 0
already_active_count = 0
duplicate_pair_count = 0
not_found_count = 0

seen_pairs = {}

planned_starts.each_with_index do |action, index|
  step = index + 1
  pair_key = "#{action[:user_id]}_#{action[:target_group_internal_id]}"

  if seen_pairs.key?(pair_key)
    puts [step, action[:user_id], action[:target_group_internal_id], '', '', '', '', '', "DUPLICATE_OF_STEP_#{seen_pairs[pair_key]}"].join(';')
    duplicate_pair_count += 1
    next
  end
  seen_pairs[pair_key] = step

  group = Group.find_by(id: action[:target_group_internal_id])
  if group.nil?
    puts [step, action[:user_id], action[:target_group_internal_id], '', '', '', '', '', 'GROUP_NOT_FOUND'].join(';')
    not_found_count += 1
    next
  end

  groupification = Groupification.find_by(group_id: group.id, user_id: action[:user_id])
  target_name = group.name

  if groupification.nil?
    puts [step, action[:user_id], action[:target_group_internal_id], target_name, '', 'NEW', '', '', 'READY_TO_START_NEW'].join(';')
    ready_new_count += 1
  elsif groupification.ends_at.nil?
    puts [step, action[:user_id], action[:target_group_internal_id], target_name, groupification.id, 'ACTIVE', groupification.starts_at, '', 'ALREADY_ACTIVE'].join(';')
    already_active_count += 1
  else
    puts [step, action[:user_id], action[:target_group_internal_id], target_name, groupification.id, 'INACTIVE', groupification.starts_at, groupification.ends_at, 'READY_TO_RESUME'].join(';')
    ready_resume_count += 1
  end
end

puts ''
puts "Validation SUMMARY: ready_new=#{ready_new_count} ready_resume=#{ready_resume_count} already_active=#{already_active_count} duplicate_pairs=#{duplicate_pair_count} not_found=#{not_found_count} total=#{planned_starts.size}"
puts '=== END Start-validation ==='
