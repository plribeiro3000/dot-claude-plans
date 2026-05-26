# Export -- Aba 2: 7 users currently active in groups OTHER than the XLSX target group.
# Customer decision: migrate (remove from current) or add (keep current and also add target)?
# Stack: app-shared-001 (multi-tenant). Replicates the per-row logic of app/workers/user_audit/consumer.rb.
# Output separator: ";" (the "@" separator collides with email addresses).

PENDING_USER_IDS = [1243869, 1243772, 1243774, 1243775, 1243854, 1243872, 1243858].freeze

company = Company.find(2077)

header = [
  'Data de Criação',
  'Desativado?',
  'Data de Desativação',
  'Desativado por',
  'E-mail do Usuário',
  'ID 4shark do Usuário',
  'Nome do Usuário',
  'Identificador do Usuário',
  'Tipo do Documento do Usuário',
  'Documento do Usuário',
  'Identificador do Gerente Imediato',
  'Gerente Imediato',
  'Nível de Acesso',
  'Identificador da Gerente Sênior',
  'Gerente Sênior',
  'Nível de Acesso do Gerente Sênior',
  'Subsidiária',
  'Data de Atualização'
]
puts header.join(';')

PENDING_USER_IDS.each do |user_id|
  user = company.users.find_by(id: user_id)
  next if user.nil?

  primary_identifier = user.primary_identifier
  primary_value = primary_identifier.present? ? primary_identifier.value : ''

  if user.disabled_at.present?
    disabled_question = 'Sim'
    disabler = user.disabler
    disabler_name = disabler.present? ? disabler.name : ''
    disabled_at_text = user.disabled_at
  else
    disabled_question = 'Não'
    disabler_name = ''
    disabled_at_text = ''
  end

  parent = user.parent
  parent_identifier_value = parent.present? ? parent.primary_identifier_value : ''
  parent_name = parent.present? ? parent.name : ''

  seat = user.seat
  seat_humanized = seat.present? ? I18n.with_locale(company.locale) { seat.model_name.human } : ''

  senior_manager = user
  loop do
    break if senior_manager.seat.nil?
    break if senior_manager.seat.role.nil?

    if senior_manager.seat.role.parent_needed?
      next_senior = senior_manager.parent
      break if next_senior.nil?
      senior_manager = next_senior
    else
      break
    end
  end

  senior_identifier_value = ''
  senior_name = ''
  senior_seat_humanized = ''
  if seat.present? && seat.role.present? && seat.role.parent_needed?
    senior_identifier_value = senior_manager.primary_identifier_value
    senior_name = senior_manager.name

    if senior_manager.seat.present?
      senior_seat_humanized = I18n.with_locale(company.locale) { senior_manager.seat.model_name.human }
    end
  end

  subsidiary_external_id = ''
  if company.subsidiaries_module? && primary_identifier.present? && primary_identifier.subsidiary.present?
    subsidiary_external_id = primary_identifier.subsidiary.external_id
  end

  puts [
    user.created_at,
    disabled_question,
    disabled_at_text,
    disabler_name,
    user.email,
    user.id,
    user.name,
    primary_value,
    user.register_type,
    user.unique_register_id,
    parent_identifier_value,
    parent_name,
    seat_humanized,
    senior_identifier_value,
    senior_name,
    senior_seat_humanized,
    subsidiary_external_id,
    user.updated_at
  ].join(';')
end
