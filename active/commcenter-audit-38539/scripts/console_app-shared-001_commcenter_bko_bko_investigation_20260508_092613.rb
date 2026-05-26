# Investigacao Bko Bko (1248713) -- entender por que seat_history foi criado hoje
# Stack: app-shared-001 (multi-tenant)
# Hipotese: User existia ontem mas Seat foi recriado/movido/etc. hoje madrugada (01:03 BRT)

company = Company.find(2077)

bko_user = company.users.find_by(id: 1248713)
raise 'Bko Bko not found' if bko_user.nil?

puts '=== USER ==='
puts %w[user_id name email created_at updated_at disabled_at register_type].join('@')
puts [
  bko_user.id, bko_user.name, bko_user.email,
  bko_user.created_at, bko_user.updated_at, bko_user.disabled_at, bko_user.register_type
].join('@')
puts ''

puts '=== USER IDENTIFIERS (todos) ==='
puts %w[id value primary subsidiary_id created_at updated_at disabled_at].join('@')
bko_user.identifiers.order(:created_at).each do |identifier|
  puts [
    identifier.id, identifier.value, identifier.primary, identifier.subsidiary_id,
    identifier.created_at, identifier.updated_at, identifier.disabled_at
  ].join('@')
end
puts ''

puts '=== SEAT atual ==='
seat = bko_user.seat
if seat.nil?
  puts 'NO_SEAT'
else
  puts %w[seat_id type role_id parent_id parent_type created_at updated_at].join('@')
  puts [seat.id, seat.type, seat.role_id, seat.parent_id, seat.parent_type, seat.created_at, seat.updated_at].join('@')
end
puts ''

puts '=== TODAS as SeatHistory desse user_id (mesmo de seats diferentes) ==='
puts 'Olhar se houve seats anteriores com historias antigas que persistem'
puts %w[id seat_id kind starts_at ends_at parent_id parent_type owner_id created_at updated_at].join('@')
SeatHistory.joins(:seat).where('seats.user_id': bko_user.id).order(:created_at).each do |history|
  puts [
    history.id, history.seat_id, history.kind, history.starts_at, history.ends_at,
    history.parent_id, history.parent_type, history.owner_id,
    history.created_at, history.updated_at
  ].join('@')
end
puts ''

puts '=== UserHistory do Bko (mudancas no User registradas) ==='
puts %w[id starts_at ends_at created_at updated_at].join('@')
bko_user.histories.order(:created_at).each do |user_history|
  puts [
    user_history.id, user_history.starts_at, user_history.ends_at,
    user_history.created_at, user_history.updated_at
  ].join('@')
end
puts ''

puts '=== Outros users com primary_value LIKE "BKO_%" na company (homonimos historicos) ==='
puts %w[user_id name email created_at disabled_at anonymized identifier_value identifier_primary].join('@')
bko_pattern_identifiers = company.user_identifiers.where('value ILIKE ?', 'BKO_%')
bko_pattern_identifiers.each do |identifier|
  identifier_user = identifier.user
  if identifier_user.nil?
    puts ['', 'NO_USER_FOR_IDENTIFIER', '', '', '', '', identifier.value, identifier.primary].join('@')
    next
  end
  puts [
    identifier_user.id, identifier_user.name, identifier_user.email,
    identifier_user.created_at, identifier_user.disabled_at, identifier_user.anonymized,
    identifier.value, identifier.primary
  ].join('@')
end
