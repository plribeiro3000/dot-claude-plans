# Phase 1 v2 -- Discovery for the groupification sheet (101 users with a target group from the XLSX).
# Stack: app-shared-001 (multi-tenant). No side effects.
# v2 fix: the "Grupo correto" column in the XLSX contains the Group.name, not the Group.external_id.
# Group.external_id on this company is a numeric string (1..38). Resolve target groups by name.
# Output is ";"-separated.

PLANNED_ACTIONS = [
  { user_id: 1128996, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1129008, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1129000, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1129007, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1128999, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1129015, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119738, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119700, target_group_name: 'TERRA_Coordenador' },
  { user_id: 1119733, target_group_name: 'TERRA_Vendedor_Digital' },
  { user_id: 1119787, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119746, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119725, target_group_name: 'TERRA_Vendedor_Digital' },
  { user_id: 1119754, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119775, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119789, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1119768, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1119724, target_group_name: 'TERRA_Vendedor_Digital' },
  { user_id: 1119823, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119765, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119727, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119839, target_group_name: 'TERRA_VendedorII_PAP' },
  { user_id: 1119840, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119930, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119846, target_group_name: 'TERRA_Vendedor_Digital' },
  { user_id: 1119784, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1119838, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119851, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119936, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119933, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119758, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119774, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119776, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119797, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119929, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119938, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119859, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119928, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119923, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1026105, target_group_name: 'TERRA_Coordenador' },
  { user_id: 1026093, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243786, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119697, target_group_name: 'TERRA_Coordenador' },
  { user_id: 1243863, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243791, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243770, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119708, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243818, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243771, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119711, target_group_name: 'TERRA_VendedorII_PAP' },
  { user_id: 1243798, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243843, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243841, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243911, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243869, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243772, target_group_name: 'TERRA_Coordenador' },
  { user_id: 1243787, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243914, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243794, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243774, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119714, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243775, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119878, target_group_name: 'TERRA_Lider_Callcenter' },
  { user_id: 1128990, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243845, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243864, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1128986, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243854, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243909, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243870, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243802, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243783, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243796, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243789, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243905, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243871, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243785, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243808, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243906, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243788, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119802, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119722, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119705, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243916, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243872, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1128988, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119701, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243928, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1119703, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1119707, target_group_name: 'TERRA_Lider_PAP' },
  { user_id: 1243918, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243859, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243907, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243921, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243858, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243867, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243813, target_group_name: 'TERRA_Vendedor_PAP' },
  { user_id: 1243862, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243842, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243792, target_group_name: 'TERRA_Vendedor_Callcenter' },
  { user_id: 1243865, target_group_name: 'Terra_Vendedor Novo 300_PAP' },
  { user_id: 1243804, target_group_name: 'TERRA_Vendedor_PAP' }
].freeze

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Phase 1 v2: groupifications discovery (lookup by Group.name) ==='
puts ''
puts 'unique_target_groups_resolution'
puts %w[target_name resolved_internal_id resolved_external_id].join(';')

unique_target_names = PLANNED_ACTIONS.map { |action| action[:target_group_name] }.uniq
unique_target_names.each do |target_name|
  group = company.groups.find_by(name: target_name)
  if group.nil?
    puts [target_name, 'MISSING', ''].join(';')
  else
    puts [target_name, group.id, group.external_id].join(';')
  end
end

puts ''
puts 'per_user_status'
puts %w[user_id user_name target_name target_internal_id current_active_group_names current_active_group_internal_ids action_status].join(';')

status_counts = Hash.new(0)

PLANNED_ACTIONS.each do |action|
  user = company.users.find_by(id: action[:user_id])
  target_group = company.groups.find_by(name: action[:target_group_name])

  if user.nil?
    puts [action[:user_id], 'USER_NOT_FOUND', action[:target_group_name], '', '', '', 'MISSING_USER'].join(';')
    status_counts['MISSING_USER'] += 1
    next
  end

  if target_group.nil?
    puts [action[:user_id], user.name, action[:target_group_name], 'MISSING', '', '', 'MISSING_TARGET_GROUP'].join(';')
    status_counts['MISSING_TARGET_GROUP'] += 1
    next
  end

  active_groupifications = user.groupifications.where(ends_at: nil).includes(:group)
  active_internal_ids = active_groupifications.map(&:group_id)
  active_names = active_groupifications.map { |groupification| groupification.group.present? ? groupification.group.name : '' }

  if active_internal_ids.empty?
    action_status = 'ADD_TO_TARGET'
  elsif active_internal_ids == [target_group.id]
    action_status = 'ALREADY_CORRECT_ONLY'
  elsif active_internal_ids.include?(target_group.id)
    action_status = 'ALREADY_IN_TARGET_PLUS_OTHERS'
  else
    action_status = 'MIGRATE_FROM_OTHERS'
  end

  status_counts[action_status] += 1

  puts [
    user.id,
    user.name,
    action[:target_group_name],
    target_group.id,
    active_names.join('|'),
    active_internal_ids.join('|'),
    action_status
  ].join(';')
end

puts ''
puts 'status_summary'
puts %w[status count].join(';')
status_counts.each do |status, count|
  puts [status, count].join(';')
end

puts ''
puts '=== END Phase 1 v2 ==='
