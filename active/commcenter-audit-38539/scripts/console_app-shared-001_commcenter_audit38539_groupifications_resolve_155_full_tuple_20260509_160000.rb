# Resolve -- For each of Patrick's 155 entries, return every candidate Groupification with the FULL tuple
# (user_id, value, subsidiary_id) explicit in the output, plus group_id and groupification_id.
# Stack: app-shared-001 (multi-tenant). No side effects.
# One Patrick entry can produce multiple output lines (one per candidate). If candidate_count > 1, the entry is
# AMBIGUOUS and the engineer decides which row is the correct one before any destroy.
# Output is ";"-separated; "@" collides with email addresses.

patrick_entries = [
  { value: '1927432', group_external_id: '38' },
  { value: '4sk_736', group_external_id: '38' },
  { value: '1926629', group_external_id: '3' },
  { value: '1926540', group_external_id: '3' },
  { value: '1927099', group_external_id: '3' },
  { value: '1918280', group_external_id: '3' },
  { value: '1918117', group_external_id: '3' },
  { value: '1922319', group_external_id: '8' },
  { value: '1926629', group_external_id: '13' },
  { value: '1926540', group_external_id: '13' },
  { value: '1914875', group_external_id: '26' },
  { value: '1915915', group_external_id: '26' },
  { value: '1915916', group_external_id: '26' },
  { value: '1917854', group_external_id: '26' },
  { value: '1927286', group_external_id: '27' },
  { value: 'AFILIADO_04', group_external_id: '27' },
  { value: '1927099', group_external_id: '27' },
  { value: '1927308', group_external_id: '27' },
  { value: '1927316', group_external_id: '27' },
  { value: '1927246', group_external_id: '27' },
  { value: '1927080', group_external_id: '27' },
  { value: '4sk_736', group_external_id: '27' },
  { value: '1927223', group_external_id: '27' },
  { value: '1927228', group_external_id: '27' },
  { value: '1927311', group_external_id: '27' },
  { value: '1927280', group_external_id: '27' },
  { value: '1918832', group_external_id: '27' },
  { value: '1927210', group_external_id: '27' },
  { value: '4sk_728', group_external_id: '27' },
  { value: '1927401', group_external_id: '27' },
  { value: '1915933', group_external_id: '27' },
  { value: '1927204', group_external_id: '27' },
  { value: '1927432', group_external_id: '27' },
  { value: '1926323', group_external_id: '27' },
  { value: '1926136', group_external_id: '27' },
  { value: '1926274', group_external_id: '27' },
  { value: '1927095', group_external_id: '27' },
  { value: '1926838', group_external_id: '27' },
  { value: '1927067', group_external_id: '27' },
  { value: '1916856', group_external_id: '27' },
  { value: '1926877', group_external_id: '27' },
  { value: '1927089', group_external_id: '27' },
  { value: '1927066', group_external_id: '27' },
  { value: '1926836', group_external_id: '27' },
  { value: '1926386', group_external_id: '25' },
  { value: '1926150', group_external_id: '25' },
  { value: '1927316', group_external_id: '25' },
  { value: '1927223', group_external_id: '25' },
  { value: '1927280', group_external_id: '25' },
  { value: '1927204', group_external_id: '25' },
  { value: '1926540', group_external_id: '24' },
  { value: '1926287', group_external_id: '24' },
  { value: '1926753', group_external_id: '24' },
  { value: '1926754', group_external_id: '24' },
  { value: '1926683', group_external_id: '24' },
  { value: '1926729', group_external_id: '24' },
  { value: '1926728', group_external_id: '24' },
  { value: '1926810', group_external_id: '24' },
  { value: '1926850', group_external_id: '24' },
  { value: '1926913', group_external_id: '24' },
  { value: '1927287', group_external_id: '24' },
  { value: '1927308', group_external_id: '24' },
  { value: '1927080', group_external_id: '24' },
  { value: '1926866', group_external_id: '24' },
  { value: '4sk_728', group_external_id: '24' },
  { value: '1918832', group_external_id: '24' },
  { value: '1915933', group_external_id: '24' },
  { value: '1927210', group_external_id: '24' },
  { value: '1927401', group_external_id: '24' },
  { value: '4sk_737', group_external_id: '24' },
  { value: '1927228', group_external_id: '24' },
  { value: '1926454', group_external_id: '24' },
  { value: '1926395', group_external_id: '24' },
  { value: '1926592', group_external_id: '24' },
  { value: '1926455', group_external_id: '24' },
  { value: '1917884', group_external_id: '24' },
  { value: '1922579', group_external_id: '24' },
  { value: '1926387', group_external_id: '24' },
  { value: '1925685', group_external_id: '24' },
  { value: '1925614', group_external_id: '24' },
  { value: '1926288', group_external_id: '24' },
  { value: '1927119', group_external_id: '24' },
  { value: '1925959', group_external_id: '24' },
  { value: '1926465', group_external_id: '24' },
  { value: '1922639', group_external_id: '24' },
  { value: '1925535', group_external_id: '24' },
  { value: '1925666', group_external_id: '24' },
  { value: '1926636', group_external_id: '24' },
  { value: '1926294', group_external_id: '24' },
  { value: '1925795', group_external_id: '24' },
  { value: '1925835', group_external_id: '24' },
  { value: '1926241', group_external_id: '24' },
  { value: '1926441', group_external_id: '24' },
  { value: '1924815', group_external_id: '24' },
  { value: '1926639', group_external_id: '24' },
  { value: '1923713', group_external_id: '24' },
  { value: '1924327', group_external_id: '24' },
  { value: '1926735', group_external_id: '24' },
  { value: '1926981', group_external_id: '24' },
  { value: '1927351', group_external_id: '24' },
  { value: '1927322', group_external_id: '24' },
  { value: '1926032', group_external_id: '24' },
  { value: '1927064', group_external_id: '24' },
  { value: '1926902', group_external_id: '24' },
  { value: '1926732', group_external_id: '24' },
  { value: '1927047', group_external_id: '24' },
  { value: '1927195', group_external_id: '24' },
  { value: '1927323', group_external_id: '24' },
  { value: '1927304', group_external_id: '24' },
  { value: '1927353', group_external_id: '24' },
  { value: '1927355', group_external_id: '24' },
  { value: '1926930', group_external_id: '24' },
  { value: '1916009', group_external_id: '33' },
  { value: '1925578', group_external_id: '33' },
  { value: '1925985', group_external_id: '33' },
  { value: '1926152', group_external_id: '33' },
  { value: '1924260', group_external_id: '33' },
  { value: '1915892', group_external_id: '33' },
  { value: '1915241', group_external_id: '33' },
  { value: '1921661', group_external_id: '33' },
  { value: '1911961', group_external_id: '33' },
  { value: '1915913', group_external_id: '33' },
  { value: '1916655', group_external_id: '34' },
  { value: '4sk_736', group_external_id: '37' },
  { value: '1927432', group_external_id: '37' },
  { value: '1924957', group_external_id: '36' },
  { value: '1925039', group_external_id: '36' },
  { value: '1926508', group_external_id: '36' },
  { value: '1919832', group_external_id: '36' },
  { value: '1926410', group_external_id: '36' },
  { value: '1919013', group_external_id: '36' },
  { value: '1927385', group_external_id: '36' },
  { value: '1927383', group_external_id: '36' },
  { value: '1927386', group_external_id: '36' },
  { value: '1927398', group_external_id: '36' },
  { value: '1927401', group_external_id: '36' },
  { value: '1927432', group_external_id: '36' },
  { value: '1923700', group_external_id: '32' },
  { value: '1924647', group_external_id: '32' },
  { value: '1925638', group_external_id: '32' },
  { value: '1926629', group_external_id: '32' },
  { value: '1925764', group_external_id: '32' },
  { value: '1926522', group_external_id: '32' },
  { value: '1926397', group_external_id: '32' },
  { value: '1922332', group_external_id: '32' },
  { value: '1925885', group_external_id: '32' },
  { value: '1926219', group_external_id: '32' },
  { value: '1926452', group_external_id: '32' },
  { value: '1918369', group_external_id: '32' },
  { value: '1926802', group_external_id: '32' },
  { value: '1927311', group_external_id: '32' },
  { value: '1913622', group_external_id: '32' },
  { value: '1920454', group_external_id: '32' },
  { value: '1918909', group_external_id: '32' },
  { value: '1924445', group_external_id: '32' }
]

company_id = 2077
company = Company.find(company_id)

puts ''
puts '=== START Resolve: 155 patrick entries -> full tuple (user_id, value, subsidiary_id) ==='
puts %w[
  step
  patrick_value
  patrick_group_external_id
  candidate_index
  candidate_count
  user_identifier_id
  user_id
  user_name
  value
  subsidiary_internal_id
  subsidiary_external_id
  group_internal_id
  group_external_id
  groupification_id
  status
].join(';')

ok_count = 0
ambiguous_count = 0
not_found_count = 0
total_candidates = 0

patrick_entries.each_with_index do |entry, index|
  step = index + 1

  group = company.groups.find_by(external_id: entry[:group_external_id])

  if group.nil?
    puts [step, entry[:value], entry[:group_external_id], 0, 0, '', '', '', '', '', '', '', '', '', 'GROUP_NOT_FOUND'].join(';')
    not_found_count += 1
    next
  end

  identifiers = company.user_identifiers.where(value: entry[:value]).to_a

  if identifiers.empty?
    puts [step, entry[:value], entry[:group_external_id], 0, 0, '', '', '', '', '', '', group.id, group.external_id, '', 'IDENTIFIER_NOT_FOUND'].join(';')
    not_found_count += 1
    next
  end

  candidates = []

  identifiers.each do |identifier|
    next if identifier.user_id.nil?

    groupification = Groupification.find_by(group_id: group.id, user_id: identifier.user_id)
    next if groupification.nil?

    candidates << {
      identifier: identifier,
      user: identifier.user,
      groupification: groupification
    }
  end

  if candidates.empty?
    puts [step, entry[:value], entry[:group_external_id], 0, 0, '', '', '', '', '', '', group.id, group.external_id, '', 'GROUPIFICATION_NOT_FOUND'].join(';')
    not_found_count += 1
    next
  end

  candidate_count = candidates.size
  status = candidate_count == 1 ? 'OK' : 'AMBIGUOUS'

  if status == 'OK'
    ok_count += 1
  else
    ambiguous_count += 1
  end

  candidates.each_with_index do |candidate, candidate_index|
    identifier = candidate[:identifier]
    user = candidate[:user]
    groupification = candidate[:groupification]
    subsidiary = identifier.subsidiary

    puts [
      step,
      entry[:value],
      entry[:group_external_id],
      candidate_index + 1,
      candidate_count,
      identifier.id,
      user.present? ? user.id : '',
      user.present? ? user.name : '',
      identifier.value,
      identifier.subsidiary_id,
      subsidiary.present? ? subsidiary.external_id : '',
      group.id,
      group.external_id,
      groupification.id,
      status
    ].join(';')
    total_candidates += 1
  end
end

puts ''
puts "Resolve SUMMARY: ok=#{ok_count} ambiguous=#{ambiguous_count} not_found=#{not_found_count} total_patrick=#{patrick_entries.size} total_candidates=#{total_candidates}"
puts '=== END Resolve ==='
