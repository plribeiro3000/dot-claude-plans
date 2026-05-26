# Phase 1D Discovery -- last seat_history.starts_at por user (12 users + 10 subs)
# Stack: app-shared-001 (multi-tenant)
# Justificativa: cliente pode pedir alteracao futura com data retroativa;
# usar last.starts_at + 1.day como `date` do form deixa margem entre last_history e a proxima edicao.

USER_IDS_TO_INSPECT = [
  1119704, 1119764, 1119802, 1119839, 1119891, 1119930, 1128986, 1129005, 1129008, 1129009, 1243770, 1243772,
  1119778, 1128992, 1128997, 1129003, 1243858, 1243860, 1243862, 1243912, 1243934, 1248713
].freeze

company = Company.find(2077)
user_ids_in_company = company.users.where(id: USER_IDS_TO_INSPECT).pluck(:id)
missing_user_ids = USER_IDS_TO_INSPECT - user_ids_in_company
raise "User IDs not in company #{company.id}: #{missing_user_ids.inspect}" if missing_user_ids.any?

today = Date.today
puts "today=#{today}"
puts ''

puts %w[
  user_id
  name
  app_seat_type
  app_disabled_at
  histories_total
  last_history_kind
  last_history_starts_at
  last_history_ends_at
  last_history_parent_id
  last_history_parent_type
  proposed_date_for_form
  days_of_margin_to_today
].join('@')

USER_IDS_TO_INSPECT.each do |user_id|
  user = company.users.find_by(id: user_id)

  if user.nil?
    puts ([user_id, 'NOT_FOUND'] + Array.new(10, '')).join('@')
    next
  end

  seat = user.seat

  if seat.nil?
    puts [user_id, user.name, 'NO_SEAT', user.disabled_at].concat(Array.new(8, '')).join('@')
    next
  end

  histories_total = seat.histories.count
  last_history = seat.histories.order(:starts_at).last

  if last_history.nil?
    puts [user_id, user.name, seat.type, user.disabled_at, histories_total].concat(Array.new(7, '')).join('@')
    next
  end

  last_history_starts_at = last_history.starts_at
  proposed_date_for_form = last_history_starts_at + 1.day
  days_of_margin_to_today = (today - proposed_date_for_form).to_i

  puts [
    user_id,
    user.name,
    seat.type,
    user.disabled_at,
    histories_total,
    last_history.kind,
    last_history_starts_at,
    last_history.ends_at,
    last_history.parent_id,
    last_history.parent_type,
    proposed_date_for_form,
    days_of_margin_to_today
  ].join('@')
end
