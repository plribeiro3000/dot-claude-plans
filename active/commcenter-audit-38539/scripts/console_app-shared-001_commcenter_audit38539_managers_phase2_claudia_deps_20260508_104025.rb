# Phase 2 -- 5 dependentes da Claudia (parent novo = Claudia agora Supervisor)
# Stack: app-shared-001 (multi-tenant)
# date = last_history.starts_at + 1.day por user

puts ''
puts '=== START Phase 2 deps Claudia: 5 ParentSeatForm ==='

company = Company.find(2077)
claudia_user_id = 1119930

actions = [
  { user_id: 1128996, name: 'Francisca Regilane Dos Santos' },
  { user_id: 1128999, name: 'Adriely Silva Pereira' },
  { user_id: 1129007, name: 'Gabriella Aparecida Ramos De Andrade' },
  { user_id: 1129015, name: 'Maiza Ortega Oliveira' },
  { user_id: 1243798, name: 'Keila Maria Ribeiro Barbosa' }
]

puts %w[step user_id name parent_id date result errors].join('@')
ok_count = 0
failed_count = 0

actions.each_with_index do |action, index|
  user = company.users.find_by(id: action[:user_id])

  if user.nil?
    puts [index + 1, action[:user_id], action[:name], claudia_user_id, '', 'USER_NOT_FOUND', ''].join('@')
    failed_count += 1
    next
  end

  last_history = user.seat.histories.order(:starts_at).last
  date_form = (last_history.starts_at + 1.day).to_s

  form = ParentSeatForm.new(user_id: action[:user_id], parent_id: claudia_user_id, date: date_form)
  saved = form.save

  if saved
    ok_count += 1
    result = 'OK'
    errors_text = ''
  else
    failed_count += 1
    result = 'FAILED'
    errors_text = form.errors.messages.inspect
  end

  puts [index + 1, action[:user_id], action[:name], claudia_user_id, date_form, result, errors_text].join('@')
end

puts "Phase 2 deps Claudia SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{actions.size}"
puts '=== END Phase 2 deps Claudia ==='
