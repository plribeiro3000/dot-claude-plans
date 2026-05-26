# Discovery -- list every Group of company 2077 (Commcenter) so we can match XLSX "Grupo correto" values
# against the real external_id / name in the database.
# Stack: app-shared-001 (multi-tenant). No side effects.
# Output is ";"-separated.

COMPANY_ID = 2077

company = Company.find(COMPANY_ID)

puts ''
puts '=== START Discovery: company groups ==='
puts ''
puts 'group_count'
puts company.groups.count

puts ''
puts 'groups'
puts %w[id external_id name disabled_at active_groupifications_count].join(';')

company.groups.order(:external_id).each do |group|
  active_count = group.groupifications.where(ends_at: nil).count
  puts [group.id, group.external_id, group.name, group.disabled_at, active_count].join(';')
end

puts ''
puts '=== END Discovery ==='
