# Phase 1B Discovery -- subordinates check (11 users que ainda divergem)
# Stack: app-shared-001 (multi-tenant)
# Foco: SeatDemotionForm#conflicted? bloqueia se highest_subordinated_index <= expected_index
# (highest_subordinated_index = menor indice em Seat::TYPES entre os subordinates)

PT_TO_SEAT = {
  'Administrador'   => 'Admin',
  'Presidente'      => 'President',
  'Vice-Presidente' => 'VicePresident',
  'Diretor'         => 'Director',
  'Superintendente' => 'Superintendent',
  'Gerente Geral'   => 'GeneralManager',
  'Gerente'         => 'Manager',
  'Coordenador'     => 'Coordinator',
  'Supervisor'      => 'Supervisor',
  'Vendedor'        => 'SalesRepresentative'
}.freeze

# 11 users ainda divergentes (Ingrid 1119802 ja corrigida, fora)
EXPECTED = [
  { user_id: 1129005, xlsx_correct: 'Supervisor'  },
  { user_id: 1129008, xlsx_correct: 'Supervisor'  },
  { user_id: 1129009, xlsx_correct: 'Supervisor'  },
  { user_id: 1119839, xlsx_correct: 'Supervisor'  },
  { user_id: 1119891, xlsx_correct: 'Vendedor'    },
  { user_id: 1119930, xlsx_correct: 'Supervisor'  },
  { user_id: 1119704, xlsx_correct: 'Vendedor'    },
  { user_id: 1119764, xlsx_correct: 'Supervisor'  },
  { user_id: 1243770, xlsx_correct: 'Vendedor'    },
  { user_id: 1243772, xlsx_correct: 'Coordenador' },
  { user_id: 1128986, xlsx_correct: 'Vendedor'    }
].freeze

user_ids = EXPECTED.map { |row| row[:user_id] }

distinct_company_ids = User.where(id: user_ids).pluck(:company_id).uniq
raise "Users span multiple companies: #{distinct_company_ids.inspect}" if distinct_company_ids.size != 1

company = Company.find(distinct_company_ids.first)
puts "company_id=#{company.id} name=#{company.name}"
puts ''

puts '=== SUMMARY ==='
puts %w[
  parent_user_id
  parent_name
  parent_app_seat
  expected_seat
  expected_index
  subordinates_total
  subordinates_breakdown
  highest_subordinated_index
  demotion_blocked
].join('@')

EXPECTED.each do |row|
  user = company.users.find_by(id: row[:user_id])

  if user.nil?
    puts [row[:user_id], 'USER_NOT_FOUND', '', row[:xlsx_correct], '', '', '', '', ''].join('@')
    next
  end

  expected_seat_type = PT_TO_SEAT[row[:xlsx_correct]]
  expected_index = Seat::TYPES.find_index(expected_seat_type)

  seat = user.seat
  app_seat_type = seat.present? ? seat.type : ''

  if seat.nil?
    puts [user.id, user.name, '', expected_seat_type, expected_index, 0, {}.inspect, '', 'NAO'].join('@')
    next
  end

  subordinate_seats = seat.subordinates
  total = subordinate_seats.count
  breakdown = subordinate_seats.group(:type).count

  if breakdown.any?
    indexes = breakdown.keys.map { |seat_type| Seat::TYPES.find_index(seat_type) }.compact
    highest_subordinated_index = indexes.min
    demotion_blocked =
      if expected_index.present? && highest_subordinated_index.present?
        highest_subordinated_index <= expected_index ? 'SIM' : 'NAO'
      else
        ''
      end
  else
    highest_subordinated_index = ''
    demotion_blocked = 'NAO'
  end

  puts [
    user.id,
    user.name,
    app_seat_type,
    expected_seat_type,
    expected_index,
    total,
    breakdown.inspect,
    highest_subordinated_index,
    demotion_blocked
  ].join('@')
end

puts ''
puts '=== DETAIL: per-subordinate listing ==='
puts %w[
  parent_user_id
  parent_name
  subordinate_user_id
  subordinate_name
  subordinate_seat
  subordinate_primary_value
  subordinate_disabled_at
].join('@')

EXPECTED.each do |row|
  user = company.users.find_by(id: row[:user_id])
  next if user.nil?

  seat = user.seat
  next if seat.nil?

  subordinate_seats = seat.subordinates.includes(user: :primary_identifier)
  next if subordinate_seats.empty?

  subordinate_seats.each do |subordinate_seat|
    subordinate_user = subordinate_seat.user

    if subordinate_user.nil?
      puts [user.id, user.name, '', 'NO_USER_FOR_SEAT', subordinate_seat.type, '', ''].join('@')
      next
    end

    primary_identifier = subordinate_user.primary_identifier
    primary_value = primary_identifier.present? ? primary_identifier.value : ''

    puts [
      user.id,
      user.name,
      subordinate_user.id,
      subordinate_user.name,
      subordinate_seat.type,
      primary_value,
      subordinate_user.disabled_at
    ].join('@')
  end
end
