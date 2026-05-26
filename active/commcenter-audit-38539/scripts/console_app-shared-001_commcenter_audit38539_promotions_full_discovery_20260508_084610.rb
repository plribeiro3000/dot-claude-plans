# Phase 1 Discovery COMPLETO -- aba promocaodespromocao (12 users)
# Stack: app-shared-001 (multi-tenant, scope sempre via company.<association>)
# Cruza TODAS as colunas A do XLSX com o estado atual da app + subordinates
# + last seat history + lookups Adysson/Joel com homonimos

PORTUGUESE_TO_SEAT_TYPE = {
  'Administrador'   => 'Admin',
  'Coordenador'     => 'Coordinator',
  'Diretor'         => 'Director',
  'Gerente'         => 'Manager',
  'Gerente Geral'   => 'GeneralManager',
  'Presidente'      => 'President',
  'Superintendente' => 'Superintendent',
  'Supervisor'      => 'Supervisor',
  'Vendedor'        => 'SalesRepresentative',
  'Vice-Presidente' => 'VicePresident'
}.freeze

EXPECTED_FROM_XLSX = [
  {
    user_id: 1129005,
    xlsx_disabled_question: 'Não', xlsx_email: 'lslima@commcenter.com.br',
    xlsx_name: 'Lucimara De Souza Lima', xlsx_primary_value: '1926152',
    xlsx_register_type: 'CPF', xlsx_document: '432.351.528-65',
    xlsx_parent_primary: '1923597', xlsx_parent_name: 'Samuel Quaresma Martins',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'LOANDRA TEIXEIRA COSTA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1129008,
    xlsx_disabled_question: 'Não', xlsx_email: 'gabroliveira@mdxtelecom.com.br',
    xlsx_name: 'Gabriela Regina De Oliveira', xlsx_primary_value: '1925638',
    xlsx_register_type: 'CPF', xlsx_document: '441.995.858-85',
    xlsx_parent_primary: '1926540', xlsx_parent_name: 'Loandra Teixeira Costa',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'LOANDRA TEIXEIRA COSTA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'VERDADEIRO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1129009,
    xlsx_disabled_question: 'Não', xlsx_email: 'jessicaasilva@commcenter.com.br',
    xlsx_name: 'Jessica Aline Dos Santos Silva', xlsx_primary_value: '1925578',
    xlsx_register_type: 'CPF', xlsx_document: '442.436.718-50',
    xlsx_parent_primary: '1926540', xlsx_parent_name: 'Loandra Teixeira Costa',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'LUCIMARA DE SOUZA LIMA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119839,
    xlsx_disabled_question: 'Não', xlsx_email: 'maypaiva@mdxtelecom.com.br',
    xlsx_name: 'Mayara Machado De Oliveira Paiva', xlsx_primary_value: '1919013',
    xlsx_register_type: 'CPF', xlsx_document: '358.050.558-05',
    xlsx_parent_primary: '1918280', xlsx_parent_name: 'Flavia Dutra Castanheira De Oliveira',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'VERDADEIRO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119891,
    xlsx_disabled_question: 'Não', xlsx_email: 'gemachado@commcenter.com.br',
    xlsx_name: 'Geovanny Diniz Machado', xlsx_primary_value: '1926096',
    xlsx_register_type: 'CPF', xlsx_document: '456.678.508-42',
    xlsx_parent_primary: '1915689', xlsx_parent_name: 'Andresa Montezori',
    xlsx_seat_portuguese: 'Coordenador',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'Andresa Montezori', xlsx_correct_seat_portuguese: 'Vendedor',
    xlsx_manager_match_flag: 'VERDADEIRO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119930,
    xlsx_disabled_question: 'Não', xlsx_email: 'claudsilva@commcenter.com.br',
    xlsx_name: 'Claudia Millena De Meneses Da Silva', xlsx_primary_value: '1925535',
    xlsx_register_type: 'CPF', xlsx_document: '488.473.658-30',
    xlsx_parent_primary: '1923597', xlsx_parent_name: 'Samuel Quaresma Martins',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'CLAUDIA MILLENA DE MENESES DA SILVA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119704,
    xlsx_disabled_question: 'Não', xlsx_email: 'frrsilva@commcenter.com.br',
    xlsx_name: 'Fabio Rogerio Rodrigues Da Silva', xlsx_primary_value: '1926150',
    xlsx_register_type: 'CPF', xlsx_document: '300.263.678-90',
    xlsx_parent_primary: '1923597', xlsx_parent_name: 'Samuel Quaresma Martins',
    xlsx_seat_portuguese: 'Supervisor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'VAGO', xlsx_correct_seat_portuguese: 'Vendedor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119764,
    xlsx_disabled_question: 'Não', xlsx_email: 'brlopes@commcenter.com.br',
    xlsx_name: 'Breno Alisson Lopes', xlsx_primary_value: '1925985',
    xlsx_register_type: 'CPF', xlsx_document: '517.066.358-77',
    xlsx_parent_primary: '1918117', xlsx_parent_name: 'Alex Lima Lofeu',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'Luiz Felipe Sonego Bonini', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1243770,
    xlsx_disabled_question: 'Não', xlsx_email: '1926728@commcenter.com.br',
    xlsx_name: 'Mariana Vitoria Finochio Da Silva', xlsx_primary_value: '1926728',
    xlsx_register_type: 'CPF', xlsx_document: '499.491.398-64',
    xlsx_parent_primary: '1923597', xlsx_parent_name: 'Samuel Quaresma Martins',
    xlsx_seat_portuguese: 'Supervisor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'ADYSSON GOMES MARTINS', xlsx_correct_seat_portuguese: 'Vendedor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1243772,
    xlsx_disabled_question: 'Não', xlsx_email: 'lbonini@commcenter.com.br',
    xlsx_name: 'Luiz Felipe Sonego Bonini', xlsx_primary_value: '1927287',
    xlsx_register_type: 'CPF', xlsx_document: '282.996.818-20',
    xlsx_parent_primary: '1918117', xlsx_parent_name: 'Alex Lima Lofeu',
    xlsx_seat_portuguese: 'Supervisor',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'JOEL GERALDO JUNIOR', xlsx_correct_seat_portuguese: 'Coordenador',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1128986,
    xlsx_disabled_question: 'Não', xlsx_email: 'rafaraujo@mdxtelecom.com.br',
    xlsx_name: 'Rafael Araujo Lima', xlsx_primary_value: '1926032',
    xlsx_register_type: 'CPF', xlsx_document: '445.594.098-70',
    xlsx_parent_primary: '1926540', xlsx_parent_name: 'Loandra Teixeira Costa',
    xlsx_seat_portuguese: 'Supervisor',
    xlsx_senior_primary: '1915689', xlsx_senior_name: 'Andresa Montezori',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'GABRIELA REGINA DE OLIVEIRA', xlsx_correct_seat_portuguese: 'Vendedor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  },
  {
    user_id: 1119802,
    xlsx_disabled_question: 'Não', xlsx_email: 'imauch@mdxtelecom.com.br',
    xlsx_name: 'Ingrid Diana Campos Da Silva Mauch', xlsx_primary_value: '1926522',
    xlsx_register_type: 'CPF', xlsx_document: '325.638.088-39',
    xlsx_parent_primary: '1923597', xlsx_parent_name: 'Samuel Quaresma Martins',
    xlsx_seat_portuguese: 'Vendedor',
    xlsx_senior_primary: '1923597', xlsx_senior_name: 'Samuel Quaresma Martins',
    xlsx_senior_seat_portuguese: 'Administrador',
    xlsx_subsidiary: '14',
    xlsx_correct_manager: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA', xlsx_correct_seat_portuguese: 'Supervisor',
    xlsx_manager_match_flag: 'FALSO', xlsx_seat_match_flag: 'FALSO'
  }
].freeze

user_ids = EXPECTED_FROM_XLSX.map { |expected_row| expected_row[:user_id] }

# Multi-tenant: company explicita (commcenter), sanity check via company.users.
company = Company.find(2077)
user_ids_in_company = company.users.where(id: user_ids).pluck(:id)
missing_user_ids = user_ids - user_ids_in_company
raise "User IDs not found in company #{company.id}: #{missing_user_ids.inspect}" if missing_user_ids.any?
puts "company_id=#{company.id} name=#{company.name} subsidiaries_module=#{company.subsidiaries_module?}"
puts ''

puts '=== SECTION 1: CROSS-CHECK XLSX vs APP (12 users) ==='
puts %w[
  user_id
  app_name xlsx_name name_match
  app_email xlsx_email email_match
  app_primary_value xlsx_primary_value primary_match
  app_document xlsx_document document_match
  app_register_type xlsx_register_type register_type_match
  app_subsidiary xlsx_subsidiary subsidiary_match
  app_seat_type xlsx_seat_portuguese seat_match_xlsx
  app_parent_user_id app_parent_primary xlsx_parent_primary parent_primary_match_xlsx app_parent_seat_type
  app_senior_user_id app_senior_primary xlsx_senior_primary senior_primary_match_xlsx app_senior_seat_type
  app_disabled_at app_disabled_question xlsx_disabled_question disabled_match
  xlsx_correct_manager xlsx_correct_seat_portuguese expected_seat_type parent_valid_for_expected
  xlsx_manager_match_flag xlsx_seat_match_flag
  last_history_starts_at
  subordinates_total subordinates_breakdown highest_subordinated_index demotion_blocked_for_expected
  integrator_external_id all_identifiers
].join('@')

EXPECTED_FROM_XLSX.each do |expected_row|
  user = company.users.find_by(id: expected_row[:user_id])

  if user.nil?
    puts ([expected_row[:user_id], 'NOT_FOUND'] + Array.new(36, '')).join('@')
    next
  end

  app_name = user.name.to_s
  name_match = app_name == expected_row[:xlsx_name].to_s ? 'SIM' : 'NAO'

  app_email = user.email.to_s
  email_match = app_email == expected_row[:xlsx_email].to_s ? 'SIM' : 'NAO'

  app_document = user.unique_register_id.to_s
  document_match = app_document == expected_row[:xlsx_document].to_s ? 'SIM' : 'NAO'

  app_register_type = user.register_type.to_s
  register_type_match = app_register_type == expected_row[:xlsx_register_type].to_s ? 'SIM' : 'NAO'

  app_disabled_question = user.disabled? ? 'Sim' : 'Não'
  disabled_match = app_disabled_question == expected_row[:xlsx_disabled_question].to_s ? 'SIM' : 'NAO'

  primary_identifier = user.primary_identifier
  if primary_identifier.present?
    app_primary_value = primary_identifier.value.to_s

    if primary_identifier.subsidiary.present?
      app_subsidiary_external_id = primary_identifier.subsidiary.external_id.to_s
    else
      app_subsidiary_external_id = ''
    end
  else
    app_primary_value = ''
    app_subsidiary_external_id = ''
  end

  primary_match = app_primary_value == expected_row[:xlsx_primary_value].to_s ? 'SIM' : 'NAO'
  subsidiary_match = app_subsidiary_external_id == expected_row[:xlsx_subsidiary].to_s ? 'SIM' : 'NAO'

  seat = user.seat
  app_seat_type = seat.present? ? seat.type.to_s : ''
  expected_seat_type = PORTUGUESE_TO_SEAT_TYPE[expected_row[:xlsx_correct_seat_portuguese]].to_s
  xlsx_current_seat_type = PORTUGUESE_TO_SEAT_TYPE[expected_row[:xlsx_seat_portuguese]].to_s
  seat_match_xlsx = app_seat_type == xlsx_current_seat_type ? 'SIM' : 'NAO'

  app_parent_user_id = ''
  app_parent_primary = ''
  app_parent_seat_type = ''

  if seat.present? && seat.parent.present?
    parent_seat = seat.parent
    app_parent_seat_type = parent_seat.type.to_s
    parent_user = parent_seat.user

    if parent_user.present?
      app_parent_user_id = parent_user.id

      if parent_user.primary_identifier.present?
        app_parent_primary = parent_user.primary_identifier.value.to_s
      end
    end
  end

  parent_primary_match_xlsx = app_parent_primary == expected_row[:xlsx_parent_primary].to_s ? 'SIM' : 'NAO'

  parent_valid_for_expected = ''
  if expected_seat_type.present? && app_parent_seat_type.present?
    expected_index = Seat::TYPES.find_index(expected_seat_type)

    if expected_index.present?
      valid_parent_types = Seat::TYPES[0, expected_index]
      parent_valid_for_expected = valid_parent_types.include?(app_parent_seat_type) ? 'SIM' : 'NAO'
    end
  end

  app_senior_user_id = ''
  app_senior_primary = ''
  app_senior_seat_type = ''

  senior_user = user
  loop do
    break if senior_user.seat.nil?
    break if senior_user.seat.role.nil?

    if senior_user.seat.role.parent_needed?
      next_senior = senior_user.parent
      break if next_senior.nil?
      senior_user = next_senior
    else
      break
    end
  end

  if senior_user.seat.present?
    app_senior_user_id = senior_user.id
    app_senior_seat_type = senior_user.seat.type.to_s

    if senior_user.primary_identifier.present?
      app_senior_primary = senior_user.primary_identifier.value.to_s
    end
  end

  senior_primary_match_xlsx = app_senior_primary == expected_row[:xlsx_senior_primary].to_s ? 'SIM' : 'NAO'

  last_history_starts_at = ''
  if seat.present?
    last_history = seat.histories.order(:starts_at).last
    last_history_starts_at = last_history.starts_at if last_history.present?
  end

  subordinates_total = 0
  subordinates_breakdown = '{}'
  highest_subordinated_index = ''
  demotion_blocked_for_expected = ''

  if seat.present?
    subordinate_seats = seat.subordinates
    subordinates_total = subordinate_seats.count
    breakdown = subordinate_seats.group(:type).count
    subordinates_breakdown = breakdown.inspect

    if breakdown.any?
      indexes = breakdown.keys.map { |seat_type| Seat::TYPES.find_index(seat_type) }.compact
      highest_subordinated_index = indexes.min

      if expected_seat_type.present?
        expected_index = Seat::TYPES.find_index(expected_seat_type)

        if expected_index.present? && highest_subordinated_index.present?
          demotion_blocked_for_expected = highest_subordinated_index <= expected_index ? 'SIM' : 'NAO'
        end
      end
    else
      demotion_blocked_for_expected = 'NAO'
    end
  end

  identifier_descriptions = user.identifiers.map do |identifier|
    "#{identifier.value}(sub=#{identifier.subsidiary_id || 'nil'};primary=#{identifier.primary})"
  end
  all_identifiers_text = identifier_descriptions.join(';')

  four_shark_identifiers = user.identifiers.select { |identifier| identifier.value.to_s.start_with?('4sk_') }
  integrator_external_id = four_shark_identifiers.map { |identifier| identifier.value.sub('4sk_', '') }.join(';')

  puts [
    user.id,
    app_name, expected_row[:xlsx_name], name_match,
    app_email, expected_row[:xlsx_email], email_match,
    app_primary_value, expected_row[:xlsx_primary_value], primary_match,
    app_document, expected_row[:xlsx_document], document_match,
    app_register_type, expected_row[:xlsx_register_type], register_type_match,
    app_subsidiary_external_id, expected_row[:xlsx_subsidiary], subsidiary_match,
    app_seat_type, expected_row[:xlsx_seat_portuguese], seat_match_xlsx,
    app_parent_user_id, app_parent_primary, expected_row[:xlsx_parent_primary], parent_primary_match_xlsx, app_parent_seat_type,
    app_senior_user_id, app_senior_primary, expected_row[:xlsx_senior_primary], senior_primary_match_xlsx, app_senior_seat_type,
    user.disabled_at, app_disabled_question, expected_row[:xlsx_disabled_question], disabled_match,
    expected_row[:xlsx_correct_manager], expected_row[:xlsx_correct_seat_portuguese], expected_seat_type, parent_valid_for_expected,
    expected_row[:xlsx_manager_match_flag], expected_row[:xlsx_seat_match_flag],
    last_history_starts_at,
    subordinates_total, subordinates_breakdown, highest_subordinated_index, demotion_blocked_for_expected,
    integrator_external_id, all_identifiers_text
  ].join('@')
end

puts ''
puts '=== SECTION 2: SUBORDINATES detail ==='
puts %w[
  parent_user_id parent_name
  subordinate_user_id subordinate_name subordinate_seat_type
  subordinate_primary_value subordinate_subsidiary subordinate_disabled_at
].join('@')

EXPECTED_FROM_XLSX.each do |expected_row|
  user = company.users.find_by(id: expected_row[:user_id])
  next if user.nil?
  next if user.seat.nil?

  subordinate_seats = user.seat.subordinates
  next if subordinate_seats.empty?

  subordinate_seats.each do |subordinate_seat|
    subordinate_user = subordinate_seat.user

    if subordinate_user.nil?
      puts [user.id, user.name, '', 'NO_USER_FOR_SEAT', subordinate_seat.type, '', '', ''].join('@')
      next
    end

    subordinate_primary_identifier = subordinate_user.primary_identifier
    subordinate_primary_value = subordinate_primary_identifier.present? ? subordinate_primary_identifier.value : ''
    subordinate_subsidiary_external_id = ''

    if subordinate_primary_identifier.present? && subordinate_primary_identifier.subsidiary.present?
      subordinate_subsidiary_external_id = subordinate_primary_identifier.subsidiary.external_id
    end

    puts [
      user.id, user.name,
      subordinate_user.id, subordinate_user.name, subordinate_seat.type,
      subordinate_primary_value, subordinate_subsidiary_external_id, subordinate_user.disabled_at
    ].join('@')
  end
end

puts ''
puts '=== SECTION 3: LOOKUP "Adysson Gomes Martins" (parent novo da Mariana) ==='
puts %w[user_id name email primary_value subsidiary seat_type disabled_at].join('@')

adysson_candidates = company.users.where('name ILIKE ?', '%adysson%')
adysson_candidates.each do |adysson_user|
  primary_identifier = adysson_user.primary_identifier
  primary_value = primary_identifier.present? ? primary_identifier.value : ''
  subsidiary_external_id = ''

  if primary_identifier.present? && primary_identifier.subsidiary.present?
    subsidiary_external_id = primary_identifier.subsidiary.external_id
  end

  seat_type = adysson_user.seat.present? ? adysson_user.seat.type : ''

  puts [
    adysson_user.id, adysson_user.name, adysson_user.email,
    primary_value, subsidiary_external_id, seat_type, adysson_user.disabled_at
  ].join('@')
end

puts ''
puts '=== SECTION 4: LOOKUP "Joel Geraldo Junior" (parent novo do Luiz Felipe) ==='
puts %w[user_id name email primary_value subsidiary seat_type disabled_at].join('@')

joel_candidates = company.users.where('name ILIKE ?', '%joel%')
joel_candidates.each do |joel_user|
  primary_identifier = joel_user.primary_identifier
  primary_value = primary_identifier.present? ? primary_identifier.value : ''
  subsidiary_external_id = ''

  if primary_identifier.present? && primary_identifier.subsidiary.present?
    subsidiary_external_id = primary_identifier.subsidiary.external_id
  end

  seat_type = joel_user.seat.present? ? joel_user.seat.type : ''

  puts [
    joel_user.id, joel_user.name, joel_user.email,
    primary_value, subsidiary_external_id, seat_type, joel_user.disabled_at
  ].join('@')
end
