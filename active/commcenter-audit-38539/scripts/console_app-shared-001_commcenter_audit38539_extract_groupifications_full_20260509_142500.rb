# Extract -- Full snapshot of every groupification of company 2077 (Commcenter), with the data needed to unambiguously
# match against Patrick's XLSX (which lists only the user's primary identifier value, no subsidiary).
# Stack: app-shared-001 (multi-tenant). No side effects.
# Includes both active (ends_at IS NULL) and finished (ends_at IS NOT NULL) groupifications.
# Columns:
#   groupification_id (internal)
#   user_id (internal)
#   user_name
#   user_primary_identifier_value
#   user_primary_identifier_subsidiary_external_id
#   user_seat (humanized in company locale)
#   group_id (internal)
#   group_external_id
#   group_name
#   starts_at
#   ends_at
# Output separator: ";" -- "@" collides with email addresses.

company_id = 2077
company = Company.find(company_id)

header = [
  'groupification_id',
  'user_id',
  'user_name',
  'user_primary_identifier_value',
  'user_primary_identifier_subsidiary_external_id',
  'user_seat',
  'group_id',
  'group_external_id',
  'group_name',
  'starts_at',
  'ends_at'
]
puts header.join(';')

Groupification.joins(:group)
              .where(groups: { company_id: company.id })
              .includes(:group, user: { primary_identifier: :subsidiary })
              .find_each do |groupification|
  user = groupification.user
  group = groupification.group

  user_name = user.present? ? user.name : ''
  primary_identifier = user.present? ? user.primary_identifier : nil
  primary_identifier_value = primary_identifier.present? ? primary_identifier.value : ''
  primary_identifier_subsidiary = primary_identifier.present? ? primary_identifier.subsidiary : nil
  primary_identifier_subsidiary_external_id = primary_identifier_subsidiary.present? ? primary_identifier_subsidiary.external_id : ''

  seat = user.present? ? user.seat : nil
  user_seat = seat.present? ? I18n.with_locale(company.locale) { seat.model_name.human } : ''

  group_internal_id = group.present? ? group.id : ''
  group_external_id = group.present? ? group.external_id : ''
  group_name = group.present? ? group.name : ''

  puts [
    groupification.id,
    user.present? ? user.id : '',
    user_name,
    primary_identifier_value,
    primary_identifier_subsidiary_external_id,
    user_seat,
    group_internal_id,
    group_external_id,
    group_name,
    groupification.starts_at,
    groupification.ends_at
  ].join(';')
end
