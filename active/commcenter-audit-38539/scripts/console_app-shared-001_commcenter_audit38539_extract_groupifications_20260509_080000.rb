# Extract -- All groupifications of company 2077 (Commcenter), in the same shape as the "Grupificação" tab of Patrick's XLSX.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Includes both active (ends_at IS NULL) and finished (ends_at IS NOT NULL) groupifications.
# Columns: Usuário (User.name); Identificador (primary identifier value);
# Tipo de Documento Único (User.register_type); Documento Único (User.unique_register_id);
# Grupo (Group.name); ID Externo (Group.external_id);
# Data de entrada (Groupification.starts_at); Data de saída (Groupification.ends_at).
# Output separator: ";" -- "@" collides with email addresses.

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

header = [
  'Usuário',
  'Identificador',
  'Tipo de Documento Único',
  'Documento Único',
  'Grupo',
  'ID Externo',
  'Data de entrada',
  'Data de saída'
]
puts header.join(';')

Groupification.joins(:group)
              .where(groups: { company_id: company.id })
              .includes(:user, :group)
              .find_each do |groupification|
  user = groupification.user
  group = groupification.group

  user_name = user.present? ? user.name : ''
  primary_identifier_value = user.present? ? user.primary_identifier_value : ''
  register_type = user.present? ? user.register_type : ''
  unique_register_id = user.present? ? user.unique_register_id : ''
  group_name = group.present? ? group.name : ''
  group_external_id = group.present? ? group.external_id : ''

  puts [
    user_name,
    primary_identifier_value,
    register_type,
    unique_register_id,
    group_name,
    group_external_id,
    groupification.starts_at,
    groupification.ends_at
  ].join(';')
end
