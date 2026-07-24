# Phase 1 — Discovery: Commcenter groupification deletion.
# Target: app-shared-001, company_id 2077 (multi-tenant — everything scoped to this company).
# Paste into: bin/ecs run app-shared-001
# READ-ONLY. Nothing is mutated. One @-separated line per source CSV row; per-row
# errors are isolated so one bad row does not abort the run.
#
# Matching (verified against code + schema on origin/master):
#   Identificador -> UserIdentifier.value (unique per company_2077)      -> user
#   ID Externo    -> Group.external_id (string, unique per company_2077) -> group
#   (group_id, user_id) -> Groupification (the "participacao")
# Plan/commission for the pair (Patrick authorized deleting these too, decided per bucket):
#   plan_statements  = PlanStatement for the user in the group's plans
#   user_commissions = UserCommission for the user in the group's plans

company_id = 2077
company = Company.find(company_id)

rows = [
  { line: 2,  identifier: '4sk_736',  document: '444.898.168-12',     group_name: 'TERRA_Vendedor_TERCEIRO',       external_id: '30' },
  { line: 3,  identifier: '1926629',  document: '791.540.853-49',     group_name: 'TERRA_Coordenador',             external_id: '3'  },
  { line: 4,  identifier: '1927099',  document: '004.396.472-90',     group_name: 'TERRA_Vendedor_Callcenter',     external_id: '27' },
  { line: 5,  identifier: '1927287',  document: '282.996.818-20',     group_name: 'TERRA_Vendedor_Callcenter',     external_id: '27' },
  { line: 6,  identifier: '1927210',  document: '599.394.018-25',     group_name: 'TERRA_Vendedor_Callcenter',     external_id: '27' },
  { line: 7,  identifier: '1927204',  document: '547.710.498-82',     group_name: 'TERRA_Vendedor_Loja',           external_id: '25' },
  { line: 8,  identifier: '1927223',  document: '529.156.868-23',     group_name: 'TERRA_Vendedor_Loja',           external_id: '25' },
  { line: 9,  identifier: '1925535',  document: '488.473.658-30',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 10, identifier: '1926930',  document: '556.053.458-77',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 11, identifier: '1926540',  document: '365.614.428-14',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 12, identifier: '1925916',  document: '408.290.828-59',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 13, identifier: '1925630',  document: '494.338.848-50',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 14, identifier: '1927210',  document: '599.394.018-25',     group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 15, identifier: '4sk_728',  document: '55.444.515/0001-72', group_name: 'TERRA_Vendedor_PAP',            external_id: '24' },
  { line: 16, identifier: '1926540',  document: '365.614.428-14',     group_name: 'Terra_Gerente_Loja',            external_id: '33' },
  { line: 17, identifier: '1918280',  document: '362.931.188-12',     group_name: 'Terra_Gerente_Loja',            external_id: '33' },
  { line: 18, identifier: '1927287',  document: '282.996.818-20',     group_name: 'Terra_Gerente_Loja',            external_id: '33' },
  { line: 19, identifier: '1927311',  document: '488.475.528-69',     group_name: 'TERRA_Lider_PAP',               external_id: '32' },
  { line: 20, identifier: '1927385',  document: '511.703.638-73',     group_name: 'Terra_Vendedor Novo 300_PAP',   external_id: '36' },
  { line: 21, identifier: '1927383',  document: '409.845.938-88',     group_name: 'Terra_Vendedor Novo 300_PAP',   external_id: '36' },
  { line: 22, identifier: '1927430',  document: '406.188.908-74',     group_name: 'Terra_Vendedor Novo 300_PAP',   external_id: '36' },
  { line: 23, identifier: '1927398',  document: '403.307.128-88',     group_name: 'Terra_Vendedor Novo 300_PAP',   external_id: '36' },
  { line: 24, identifier: '1927432',  document: '492.091.648-57',     group_name: 'TERRA_VendedorII_PAP',          external_id: '39' },
  { line: 25, identifier: '4sk_736',  document: '444.898.168-12',     group_name: 'TERRA_VendedorII_PAP',          external_id: '39' }
]

puts %w[line identifier document_csv ext_id group_csv user group_app groupification gf_starts gf_ends plan_statements user_commissions].join('@')

rows.each do |row|
  begin
    identifier_records = UserIdentifier.where(company_id: company_id, value: row[:identifier])
    matched_user_ids = identifier_records.pluck(:user_id).compact.uniq

    if matched_user_ids.empty?
      puts [row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name], 'USER_NOT_FOUND', '-', '-', '-', '-', '-', '-'].join('@')
      next
    elsif matched_user_ids.size > 1
      puts [row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name], "USER_AMBIGUOUS(#{matched_user_ids.size})", '-', '-', '-', '-', '-', '-'].join('@')
      next
    end

    user = User.find(matched_user_ids.first)
    user_label = "#{user.id}:#{user.name}#{user.disabled_at.nil? ? '' : '(disabled)'}"

    group = company.groups.find_by(external_id: row[:external_id])
    if group.nil?
      puts [row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name], user_label, 'GROUP_NOT_FOUND', '-', '-', '-', '-', '-'].join('@')
      next
    end
    group_label = "#{group.id}:#{group.name}"

    groupification = Groupification.find_by(group_id: group.id, user_id: user.id)
    if groupification.nil?
      puts [row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name], user_label, group_label, 'GF_NONE', '-', '-', '-', '-'].join('@')
      next
    end

    plan_ids = group.plans.select(:id)
    plan_statement_count = PlanStatement.where(user_id: user.id, plan_id: plan_ids).count
    user_commission_count = UserCommission.joins(:commission).where(user_id: user.id, commissions: { plan_id: plan_ids }).count

    puts [
      row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name],
      user_label, group_label, "GF_FOUND:#{groupification.id}",
      groupification.starts_at, groupification.ends_at,
      plan_statement_count, user_commission_count
    ].join('@')
  rescue StandardError => error
    puts [row[:line], row[:identifier], row[:document], row[:external_id], row[:group_name], "ERROR: #{error.message}", '-', '-', '-', '-', '-', '-'].join('@')
  end
end

puts 'DISCOVERY_DONE@' + company.name.to_s
