# Phase 3 Verification -- aba promocaodespromocao (17 acoes em 7 etapas)
# Stack: app-shared-001 (multi-tenant)
# Confere: estado pos-fix dos 12 users vs expected; e que os 10 subs estao sob Samuel.

EXPECTED_POST_FIX = [
  { user_id: 1129005, name: 'Lucimara De Souza Lima',                expected_seat: 'Supervisor',          expected_parent_user_id: 1026105, skipped_for_client: false },
  { user_id: 1129008, name: 'Gabriela Regina De Oliveira',           expected_seat: 'Supervisor',          expected_parent_user_id: 1026105, skipped_for_client: false },
  { user_id: 1129009, name: 'Jessica Aline Dos Santos Silva',        expected_seat: 'SalesRepresentative', expected_parent_user_id: 1026105, skipped_for_client: true  },
  { user_id: 1119839, name: 'Mayara Machado De Oliveira Paiva',      expected_seat: 'Supervisor',          expected_parent_user_id: 1119700, skipped_for_client: false },
  { user_id: 1119891, name: 'Geovanny Diniz Machado',                expected_seat: 'SalesRepresentative', expected_parent_user_id: 1119694, skipped_for_client: false },
  { user_id: 1119930, name: 'Claudia Millena De Meneses Da Silva',   expected_seat: 'SalesRepresentative', expected_parent_user_id: 1026061, skipped_for_client: true  },
  { user_id: 1119704, name: 'Fabio Rogerio Rodrigues Da Silva',      expected_seat: 'SalesRepresentative', expected_parent_user_id: 1026061, skipped_for_client: false },
  { user_id: 1119764, name: 'Breno Alisson Lopes',                   expected_seat: 'Supervisor',          expected_parent_user_id: 1243772, skipped_for_client: false },
  { user_id: 1243770, name: 'Mariana Vitoria Finochio Da Silva',     expected_seat: 'SalesRepresentative', expected_parent_user_id: 1119708, skipped_for_client: false },
  { user_id: 1243772, name: 'Luiz Felipe Sonego Bonini',             expected_seat: 'Coordinator',         expected_parent_user_id: 1026079, skipped_for_client: false },
  { user_id: 1128986, name: 'Rafael Araujo Lima',                    expected_seat: 'SalesRepresentative', expected_parent_user_id: 1129008, skipped_for_client: false },
  { user_id: 1119802, name: 'Ingrid Diana Campos Da Silva Mauch',    expected_seat: 'Supervisor',          expected_parent_user_id: 1119700, skipped_for_client: false }
].freeze

REALLOCATED_SUB_IDS = [1243912, 1248713, 1119778, 1129003, 1128992, 1128997, 1243858, 1243862, 1243860, 1243934].freeze

company = Company.find(2077)
samuel_quaresma_user_id = 1026061

puts ''
puts '=== SECTION 1: Estado pos-fix dos 12 users ==='
puts %w[user_id name skipped expected_seat app_seat seat_match expected_parent_user_id app_parent_user_id parent_match subordinates_total last_history_starts_at].join('@')

EXPECTED_POST_FIX.each do |row|
  user = company.users.find_by(id: row[:user_id])

  if user.nil?
    puts [row[:user_id], row[:name], row[:skipped_for_client], row[:expected_seat], 'NOT_FOUND', '', row[:expected_parent_user_id], '', '', '', ''].join('@')
    next
  end

  seat = user.seat
  app_seat_type = seat.present? ? seat.type : ''

  app_parent_user_id = ''
  if seat.present? && seat.parent.present? && seat.parent.user.present?
    app_parent_user_id = seat.parent.user.id
  end

  subordinates_total = seat.present? ? seat.subordinates.count : 0

  last_history_starts_at = ''
  if seat.present?
    last_history = seat.histories.order(:starts_at).last
    last_history_starts_at = last_history.starts_at if last_history.present?
  end

  if row[:skipped_for_client]
    seat_match = 'PULADO'
    parent_match = 'PULADO'
  else
    seat_match = app_seat_type == row[:expected_seat] ? 'SIM' : 'NAO'
    parent_match = app_parent_user_id.to_s == row[:expected_parent_user_id].to_s ? 'SIM' : 'NAO'
  end

  puts [
    row[:user_id], row[:name], row[:skipped_for_client],
    row[:expected_seat], app_seat_type, seat_match,
    row[:expected_parent_user_id], app_parent_user_id, parent_match,
    subordinates_total, last_history_starts_at
  ].join('@')
end

puts ''
puts '=== SECTION 2: 10 subs realocados devem estar sob Samuel Quaresma (user_id=1026061) ==='
puts %w[sub_user_id sub_name app_parent_user_id is_under_samuel last_history_starts_at].join('@')

REALLOCATED_SUB_IDS.each do |sub_user_id|
  sub_user = company.users.find_by(id: sub_user_id)

  if sub_user.nil?
    puts [sub_user_id, 'NOT_FOUND', '', '', ''].join('@')
    next
  end

  sub_seat = sub_user.seat
  app_parent_user_id = ''

  if sub_seat.present? && sub_seat.parent.present? && sub_seat.parent.user.present?
    app_parent_user_id = sub_seat.parent.user.id
  end

  is_under_samuel = app_parent_user_id == samuel_quaresma_user_id ? 'SIM' : 'NAO'

  last_history_starts_at = ''
  if sub_seat.present?
    last_history = sub_seat.histories.order(:starts_at).last
    last_history_starts_at = last_history.starts_at if last_history.present?
  end

  puts [sub_user_id, sub_user.name, app_parent_user_id, is_under_samuel, last_history_starts_at].join('@')
end
