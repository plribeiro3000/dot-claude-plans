# Phase 2 EXTRA -- 4 acoes pra realocar pro Samuel Quaresma
# - Claudia (1119930): SeatPromotionForm Vendedor -> Supervisor (parent Samuel)
# - Joao Luis Carnelos (1119696): ParentSeatForm (Andresa -> Samuel)
# - Alex Lima Lofeu (1119697): ParentSeatForm (Andresa -> Samuel)
# - Joel Geraldo Junior (1026079): ParentSeatForm (Andresa -> Samuel)
# Stack: app-shared-001 (multi-tenant). date = last_history.starts_at + 1.day por user.

puts ''
puts '=== START Phase 2 EXTRA: 4 acoes Samuel Quaresma ==='

company = Company.find(2077)
samuel_quaresma_user_id = 1026061

actions = [
  { kind: :promotion, user_id: 1119930, name: 'Claudia Millena De Meneses Da Silva', new_seat_type: 'Supervisor' },
  { kind: :parent,    user_id: 1119696, name: 'Joao Luis Carnelos' },
  { kind: :parent,    user_id: 1119697, name: 'Alex Lima Lofeu' },
  { kind: :parent,    user_id: 1026079, name: 'Joel Geraldo Junior' }
]

puts %w[step user_id name kind new_seat_type parent_id date result errors].join('@')
ok_count = 0
failed_count = 0

actions.each_with_index do |action, index|
  user = company.users.find_by(id: action[:user_id])

  if user.nil?
    puts [index + 1, action[:user_id], action[:name], action[:kind], action[:new_seat_type], samuel_quaresma_user_id, '', 'USER_NOT_FOUND', ''].join('@')
    failed_count += 1
    next
  end

  last_history = user.seat.histories.order(:starts_at).last
  date_form = (last_history.starts_at + 1.day).to_s

  form =
    case action[:kind]
    when :promotion
      SeatPromotionForm.new(user_id: action[:user_id], type: action[:new_seat_type], parent_id: samuel_quaresma_user_id, date: date_form)
    when :parent
      ParentSeatForm.new(user_id: action[:user_id], parent_id: samuel_quaresma_user_id, date: date_form)
    end

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

  puts [index + 1, action[:user_id], action[:name], action[:kind], action[:new_seat_type], samuel_quaresma_user_id, date_form, result, errors_text].join('@')
end

puts "Phase 2 EXTRA SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{actions.size}"
puts '=== END Phase 2 EXTRA ==='
