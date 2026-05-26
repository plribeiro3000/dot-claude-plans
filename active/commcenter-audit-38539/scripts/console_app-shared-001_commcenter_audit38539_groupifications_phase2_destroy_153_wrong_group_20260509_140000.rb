# Phase 2 -- Destroy 153 wrong-group groupifications (155 candidates minus 2 BLOCKED by plan_statements).
# Stack: app-shared-001 (multi-tenant). No transaction across rows -- each row independent.
# The 2 BLOCKED entries (Udo and Loandra in PAP_Supervisor, ext 13) are NOT in this list -- they will be handled
# separately (finish instead of destroy, to preserve plan_statement integrity).
# Defensive: if the groupification does not exist anymore (re-run scenario), reports ALREADY_DESTROYED instead of failing.
# Output is ";"-separated; "@" collides with email addresses.

planned_destroys = [
  { user_identifier_value: '1927432', group_external_id: '38' },
  { user_identifier_value: '4sk_736', group_external_id: '38' },
  { user_identifier_value: '1926629', group_external_id: '3' },
  { user_identifier_value: '1926540', group_external_id: '3' },
  { user_identifier_value: '1927099', group_external_id: '3' },
  { user_identifier_value: '1918280', group_external_id: '3' },
  { user_identifier_value: '1918117', group_external_id: '3' },
  { user_identifier_value: '1922319', group_external_id: '8' },
  { user_identifier_value: '1914875', group_external_id: '26' },
  { user_identifier_value: '1915915', group_external_id: '26' },
  { user_identifier_value: '1915916', group_external_id: '26' },
  { user_identifier_value: '1917854', group_external_id: '26' },
  { user_identifier_value: '1927286', group_external_id: '27' },
  { user_identifier_value: 'AFILIADO_04', group_external_id: '27' },
  { user_identifier_value: '1927099', group_external_id: '27' },
  { user_identifier_value: '1927308', group_external_id: '27' },
  { user_identifier_value: '1927316', group_external_id: '27' },
  { user_identifier_value: '1927246', group_external_id: '27' },
  { user_identifier_value: '1927080', group_external_id: '27' },
  { user_identifier_value: '4sk_736', group_external_id: '27' },
  { user_identifier_value: '1927223', group_external_id: '27' },
  { user_identifier_value: '1927228', group_external_id: '27' },
  { user_identifier_value: '1927311', group_external_id: '27' },
  { user_identifier_value: '1927280', group_external_id: '27' },
  { user_identifier_value: '1918832', group_external_id: '27' },
  { user_identifier_value: '1927210', group_external_id: '27' },
  { user_identifier_value: '4sk_728', group_external_id: '27' },
  { user_identifier_value: '1927401', group_external_id: '27' },
  { user_identifier_value: '1915933', group_external_id: '27' },
  { user_identifier_value: '1927204', group_external_id: '27' },
  { user_identifier_value: '1927432', group_external_id: '27' },
  { user_identifier_value: '1926323', group_external_id: '27' },
  { user_identifier_value: '1926136', group_external_id: '27' },
  { user_identifier_value: '1926274', group_external_id: '27' },
  { user_identifier_value: '1927095', group_external_id: '27' },
  { user_identifier_value: '1926838', group_external_id: '27' },
  { user_identifier_value: '1927067', group_external_id: '27' },
  { user_identifier_value: '1916856', group_external_id: '27' },
  { user_identifier_value: '1926877', group_external_id: '27' },
  { user_identifier_value: '1927089', group_external_id: '27' },
  { user_identifier_value: '1927066', group_external_id: '27' },
  { user_identifier_value: '1926836', group_external_id: '27' },
  { user_identifier_value: '1926386', group_external_id: '25' },
  { user_identifier_value: '1926150', group_external_id: '25' },
  { user_identifier_value: '1927316', group_external_id: '25' },
  { user_identifier_value: '1927223', group_external_id: '25' },
  { user_identifier_value: '1927280', group_external_id: '25' },
  { user_identifier_value: '1927204', group_external_id: '25' },
  { user_identifier_value: '1926540', group_external_id: '24' },
  { user_identifier_value: '1926287', group_external_id: '24' },
  { user_identifier_value: '1926753', group_external_id: '24' },
  { user_identifier_value: '1926754', group_external_id: '24' },
  { user_identifier_value: '1926683', group_external_id: '24' },
  { user_identifier_value: '1926729', group_external_id: '24' },
  { user_identifier_value: '1926728', group_external_id: '24' },
  { user_identifier_value: '1926810', group_external_id: '24' },
  { user_identifier_value: '1926850', group_external_id: '24' },
  { user_identifier_value: '1926913', group_external_id: '24' },
  { user_identifier_value: '1927287', group_external_id: '24' },
  { user_identifier_value: '1927308', group_external_id: '24' },
  { user_identifier_value: '1927080', group_external_id: '24' },
  { user_identifier_value: '1926866', group_external_id: '24' },
  { user_identifier_value: '4sk_728', group_external_id: '24' },
  { user_identifier_value: '1918832', group_external_id: '24' },
  { user_identifier_value: '1915933', group_external_id: '24' },
  { user_identifier_value: '1927210', group_external_id: '24' },
  { user_identifier_value: '1927401', group_external_id: '24' },
  { user_identifier_value: '4sk_737', group_external_id: '24' },
  { user_identifier_value: '1927228', group_external_id: '24' },
  { user_identifier_value: '1926454', group_external_id: '24' },
  { user_identifier_value: '1926395', group_external_id: '24' },
  { user_identifier_value: '1926592', group_external_id: '24' },
  { user_identifier_value: '1926455', group_external_id: '24' },
  { user_identifier_value: '1917884', group_external_id: '24' },
  { user_identifier_value: '1922579', group_external_id: '24' },
  { user_identifier_value: '1926387', group_external_id: '24' },
  { user_identifier_value: '1925685', group_external_id: '24' },
  { user_identifier_value: '1925614', group_external_id: '24' },
  { user_identifier_value: '1926288', group_external_id: '24' },
  { user_identifier_value: '1927119', group_external_id: '24' },
  { user_identifier_value: '1925959', group_external_id: '24' },
  { user_identifier_value: '1926465', group_external_id: '24' },
  { user_identifier_value: '1922639', group_external_id: '24' },
  { user_identifier_value: '1925535', group_external_id: '24' },
  { user_identifier_value: '1925666', group_external_id: '24' },
  { user_identifier_value: '1926636', group_external_id: '24' },
  { user_identifier_value: '1926294', group_external_id: '24' },
  { user_identifier_value: '1925795', group_external_id: '24' },
  { user_identifier_value: '1925835', group_external_id: '24' },
  { user_identifier_value: '1926241', group_external_id: '24' },
  { user_identifier_value: '1926441', group_external_id: '24' },
  { user_identifier_value: '1924815', group_external_id: '24' },
  { user_identifier_value: '1926639', group_external_id: '24' },
  { user_identifier_value: '1923713', group_external_id: '24' },
  { user_identifier_value: '1924327', group_external_id: '24' },
  { user_identifier_value: '1926735', group_external_id: '24' },
  { user_identifier_value: '1926981', group_external_id: '24' },
  { user_identifier_value: '1927351', group_external_id: '24' },
  { user_identifier_value: '1927322', group_external_id: '24' },
  { user_identifier_value: '1926032', group_external_id: '24' },
  { user_identifier_value: '1927064', group_external_id: '24' },
  { user_identifier_value: '1926902', group_external_id: '24' },
  { user_identifier_value: '1926732', group_external_id: '24' },
  { user_identifier_value: '1927047', group_external_id: '24' },
  { user_identifier_value: '1927195', group_external_id: '24' },
  { user_identifier_value: '1927323', group_external_id: '24' },
  { user_identifier_value: '1927304', group_external_id: '24' },
  { user_identifier_value: '1927353', group_external_id: '24' },
  { user_identifier_value: '1927355', group_external_id: '24' },
  { user_identifier_value: '1926930', group_external_id: '24' },
  { user_identifier_value: '1916009', group_external_id: '33' },
  { user_identifier_value: '1925578', group_external_id: '33' },
  { user_identifier_value: '1925985', group_external_id: '33' },
  { user_identifier_value: '1926152', group_external_id: '33' },
  { user_identifier_value: '1924260', group_external_id: '33' },
  { user_identifier_value: '1915892', group_external_id: '33' },
  { user_identifier_value: '1915241', group_external_id: '33' },
  { user_identifier_value: '1921661', group_external_id: '33' },
  { user_identifier_value: '1911961', group_external_id: '33' },
  { user_identifier_value: '1915913', group_external_id: '33' },
  { user_identifier_value: '1916655', group_external_id: '34' },
  { user_identifier_value: '4sk_736', group_external_id: '37' },
  { user_identifier_value: '1927432', group_external_id: '37' },
  { user_identifier_value: '1924957', group_external_id: '36' },
  { user_identifier_value: '1925039', group_external_id: '36' },
  { user_identifier_value: '1926508', group_external_id: '36' },
  { user_identifier_value: '1919832', group_external_id: '36' },
  { user_identifier_value: '1926410', group_external_id: '36' },
  { user_identifier_value: '1919013', group_external_id: '36' },
  { user_identifier_value: '1927385', group_external_id: '36' },
  { user_identifier_value: '1927383', group_external_id: '36' },
  { user_identifier_value: '1927386', group_external_id: '36' },
  { user_identifier_value: '1927398', group_external_id: '36' },
  { user_identifier_value: '1927401', group_external_id: '36' },
  { user_identifier_value: '1927432', group_external_id: '36' },
  { user_identifier_value: '1923700', group_external_id: '32' },
  { user_identifier_value: '1924647', group_external_id: '32' },
  { user_identifier_value: '1925638', group_external_id: '32' },
  { user_identifier_value: '1926629', group_external_id: '32' },
  { user_identifier_value: '1925764', group_external_id: '32' },
  { user_identifier_value: '1926522', group_external_id: '32' },
  { user_identifier_value: '1926397', group_external_id: '32' },
  { user_identifier_value: '1922332', group_external_id: '32' },
  { user_identifier_value: '1925885', group_external_id: '32' },
  { user_identifier_value: '1926219', group_external_id: '32' },
  { user_identifier_value: '1926452', group_external_id: '32' },
  { user_identifier_value: '1918369', group_external_id: '32' },
  { user_identifier_value: '1926802', group_external_id: '32' },
  { user_identifier_value: '1927311', group_external_id: '32' },
  { user_identifier_value: '1913622', group_external_id: '32' },
  { user_identifier_value: '1920454', group_external_id: '32' },
  { user_identifier_value: '1918909', group_external_id: '32' },
  { user_identifier_value: '1924445', group_external_id: '32' }
]

company_id = 2077
company = Company.find(company_id)

puts ''
puts '=== START Phase 2: destroy 153 wrong-group groupifications ==='
puts %w[step user_identifier user_name group_external_id group_name groupification_id result errors].join(';')

ok_count = 0
already_count = 0
failed_count = 0

planned_destroys.each_with_index do |action, index|
  result = 'PENDING'
  errors_text = ''
  user_name = ''
  group_name = ''
  groupification_id = ''

  user_identifier = company.user_identifiers.find_by(value: action[:user_identifier_value])
  group = company.groups.find_by(external_id: action[:group_external_id])

  if user_identifier.nil?
    result = 'USER_IDENTIFIER_NOT_FOUND'
  elsif group.nil?
    result = 'GROUP_NOT_FOUND'
  elsif user_identifier.user.nil?
    result = 'USER_NOT_FOUND'
  else
    user = user_identifier.user
    user_name = user.name
    group_name = group.name

    groupification = Groupification.find_by(group_id: group.id, user_id: user.id)

    if groupification.nil?
      result = 'ALREADY_DESTROYED'
    else
      groupification_id = groupification.id

      if groupification.destroy
        result = 'OK_DESTROYED'
      else
        result = 'DESTROY_FAILED'
        errors_text = groupification.errors.full_messages.join('|')
      end
    end
  end

  if result == 'OK_DESTROYED'
    ok_count += 1
  elsif result == 'ALREADY_DESTROYED'
    already_count += 1
  else
    failed_count += 1
  end

  puts [
    index + 1,
    action[:user_identifier_value],
    user_name,
    action[:group_external_id],
    group_name,
    groupification_id,
    result,
    errors_text
  ].join(';')
end

puts ''
puts "Phase 2 SUMMARY: ok=#{ok_count} already_destroyed=#{already_count} failed=#{failed_count} total=#{planned_destroys.size}"
puts '=== END Phase 2 ==='
