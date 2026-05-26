# Extract -- All groups of company 2077 (Commcenter), in the same shape as the "Grupo" tab of Patrick's XLSX.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Columns: Grupo (Group.name); ID Externo (Group.external_id); Created at (Group.created_at);
# Usuários (count of active groupifications, ends_at IS NULL).
# Output separator: ";" -- "@" collides with email addresses.

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

header = ['Grupo', 'ID Externo', 'Created at', 'Usuários']
puts header.join(';')

company.groups.order(:created_at).find_each do |group|
  active_count = group.groupifications.where(ends_at: nil).count
  puts [group.name, group.external_id, group.created_at, active_count].join(';')
end
