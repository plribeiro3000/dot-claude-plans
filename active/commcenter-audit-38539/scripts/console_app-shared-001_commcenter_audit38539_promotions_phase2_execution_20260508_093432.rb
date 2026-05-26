# Phase 2 Execution -- aba promocaodespromocao (17 acoes em 7 etapas)
# Stack: app-shared-001 (multi-tenant)
# Cada etapa eh um bloco auto-contido (recria `company`). Engineer copia/cola por bloco,
# valida o output, e prossegue. Cada acao roda um Form e imprime OK/FAILED + errors.

# ====================================================================================
# ETAPA 1: Realocacao de 10 subs pro Samuel Quaresma (user_id=1026061) via ParentSeatForm
# ====================================================================================
puts ''
puts '=== START ETAPA 1: Realocacao 10 subs pro Samuel Quaresma ==='

company = Company.find(2077)
samuel_quaresma_user_id = 1026061

reallocations = [
  { sub_user_id: 1243912, name: 'Marcia Mayumi Araki De Benedetto',         date: '2026-04-30' },
  { sub_user_id: 1248713, name: 'Bko Bko',                                  date: '2026-05-09' },
  { sub_user_id: 1119778, name: 'Carlos Eduardo Martins (disabled)',        date: '2025-11-19' },
  { sub_user_id: 1129003, name: 'Alef Silva Vieira (disabled)',             date: '2025-12-03' },
  { sub_user_id: 1128992, name: 'Kelly Mariane De Sousa Sampaio (disabled)', date: '2025-12-03' },
  { sub_user_id: 1128997, name: 'Geovana Almeida Souza (disabled)',         date: '2025-12-03' },
  { sub_user_id: 1243858, name: 'Aparecida Das Dores Sancao',               date: '2026-04-30' },
  { sub_user_id: 1243862, name: 'Ianca Raquel De Oliveira',                 date: '2026-04-30' },
  { sub_user_id: 1243860, name: 'Juliana Souza Galdino (disabled)',         date: '2026-04-30' },
  { sub_user_id: 1243934, name: 'Geiza Gabriele Morais De Campos (disabled)', date: '2026-04-30' }
]

puts %w[step sub_user_id name date result errors].join('@')
ok_count = 0
failed_count = 0

reallocations.each_with_index do |reallocation, index|
  form = ParentSeatForm.new(
    user_id: reallocation[:sub_user_id],
    parent_id: samuel_quaresma_user_id,
    date: reallocation[:date]
  )

  if form.save
    ok_count += 1
    result = 'OK'
    errors_text = ''
  else
    failed_count += 1
    result = 'FAILED'
    errors_text = form.errors.messages.inspect
  end

  puts [index + 1, reallocation[:sub_user_id], reallocation[:name], reallocation[:date], result, errors_text].join('@')
end

puts "ETAPA 1 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{reallocations.size}"
puts '=== END ETAPA 1 ==='


# ====================================================================================
# ETAPA 2: Promocoes/despromocoes livres (4 acoes, sem dependencia)
# Lucimara, Gabriela, Mayara: SeatPromotionForm
# Mariana: SeatDemotionForm
# ====================================================================================
puts ''
puts '=== START ETAPA 2: Promocoes/despromocoes livres ==='

company = Company.find(2077)
loandra_user_id = 1026105
flavia_user_id = 1119700
adysson_user_id = 1119708

# parent_id nil quando nao troca de parent (form puxa do atual via seat.parent.user_id)
free_actions = [
  { user_id: 1129005, name: 'Lucimara De Souza Lima',                form: :promotion, type: 'Supervisor',          parent_id: loandra_user_id, date: '2026-04-30' },
  { user_id: 1129008, name: 'Gabriela Regina De Oliveira',           form: :promotion, type: 'Supervisor',          parent_id: nil,             date: '2026-04-30' },
  { user_id: 1119839, name: 'Mayara Machado De Oliveira Paiva',      form: :promotion, type: 'Supervisor',          parent_id: nil,             date: '2025-11-19' },
  { user_id: 1243770, name: 'Mariana Vitoria Finochio Da Silva',     form: :demotion,  type: 'SalesRepresentative', parent_id: adysson_user_id, date: '2026-04-30' }
]

puts %w[step user_id name form type parent_id date result errors].join('@')
ok_count = 0
failed_count = 0

free_actions.each_with_index do |action, index|
  form_args = { user_id: action[:user_id], type: action[:type], date: action[:date] }
  form_args[:parent_id] = action[:parent_id] if action[:parent_id].present?

  form =
    if action[:form] == :promotion
      SeatPromotionForm.new(form_args)
    else
      SeatDemotionForm.new(form_args)
    end

  if form.save
    ok_count += 1
    result = 'OK'
    errors_text = ''
  else
    failed_count += 1
    result = 'FAILED'
    errors_text = form.errors.messages.inspect
  end

  puts [index + 1, action[:user_id], action[:name], action[:form], action[:type], action[:parent_id], action[:date], result, errors_text].join('@')
end

puts "ETAPA 2 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{free_actions.size}"
puts '=== END ETAPA 2 ==='


# ====================================================================================
# ETAPA 3: Despromocoes com subs ja realocados (Geovanny, Fabio)
# Pre-requisito: Etapa 1 OK (realocacao dos subs deles pro Samuel)
# ====================================================================================
puts ''
puts '=== START ETAPA 3: Despromocoes Geovanny + Fabio ==='

company = Company.find(2077)

dependent_demotions = [
  { user_id: 1119891, name: 'Geovanny Diniz Machado',           type: 'SalesRepresentative', date: '2026-04-30' },
  { user_id: 1119704, name: 'Fabio Rogerio Rodrigues Da Silva', type: 'SalesRepresentative', date: '2026-04-30' }
]

puts %w[step user_id name type date result errors].join('@')
ok_count = 0
failed_count = 0

dependent_demotions.each_with_index do |action, index|
  form = SeatDemotionForm.new(user_id: action[:user_id], type: action[:type], date: action[:date])

  if form.save
    ok_count += 1
    result = 'OK'
    errors_text = ''
  else
    failed_count += 1
    result = 'FAILED'
    errors_text = form.errors.messages.inspect
  end

  puts [index + 1, action[:user_id], action[:name], action[:type], action[:date], result, errors_text].join('@')
end

puts "ETAPA 3 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{dependent_demotions.size}"
puts '=== END ETAPA 3 ==='


# ====================================================================================
# ETAPA 4: Luiz Felipe -- promocao a Coordinator com parent Joel (cross-subsidiary by design)
# ====================================================================================
puts ''
puts '=== START ETAPA 4: Luiz Felipe -> Coordinator (parent Joel) ==='

company = Company.find(2077)
joel_user_id = 1026079

form = SeatPromotionForm.new(
  user_id: 1243772,
  type: 'Coordinator',
  parent_id: joel_user_id,
  date: '2026-04-30'
)

puts %w[user_id name type parent_id date result errors].join('@')

if form.save
  result = 'OK'
  errors_text = ''
else
  result = 'FAILED'
  errors_text = form.errors.messages.inspect
end

puts [1243772, 'Luiz Felipe Sonego Bonini', 'Coordinator', joel_user_id, '2026-04-30', result, errors_text].join('@')
puts '=== END ETAPA 4 ==='


# ====================================================================================
# ETAPA 5: Breno -- promocao a Supervisor com parent Luiz Felipe (depende ETAPA 4 OK)
# ====================================================================================
puts ''
puts '=== START ETAPA 5: Breno -> Supervisor (parent Luiz Felipe) ==='

company = Company.find(2077)
luiz_felipe_user_id = 1243772

form = SeatPromotionForm.new(
  user_id: 1119764,
  type: 'Supervisor',
  parent_id: luiz_felipe_user_id,
  date: '2026-04-30'
)

puts %w[user_id name type parent_id date result errors].join('@')

if form.save
  result = 'OK'
  errors_text = ''
else
  result = 'FAILED'
  errors_text = form.errors.messages.inspect
end

puts [1119764, 'Breno Alisson Lopes', 'Supervisor', luiz_felipe_user_id, '2026-04-30', result, errors_text].join('@')
puts '=== END ETAPA 5 ==='


# ====================================================================================
# ETAPA 6: Rafael -- despromocao a SalesRepresentative com parent Gabriela (depende ETAPA 1 + ETAPA 2)
# ====================================================================================
puts ''
puts '=== START ETAPA 6: Rafael -> SalesRepresentative (parent Gabriela) ==='

company = Company.find(2077)
gabriela_user_id = 1129008

form = SeatDemotionForm.new(
  user_id: 1128986,
  type: 'SalesRepresentative',
  parent_id: gabriela_user_id,
  date: '2025-12-03'
)

puts %w[user_id name type parent_id date result errors].join('@')

if form.save
  result = 'OK'
  errors_text = ''
else
  result = 'FAILED'
  errors_text = form.errors.messages.inspect
end

puts [1128986, 'Rafael Araujo Lima', 'SalesRepresentative', gabriela_user_id, '2025-12-03', result, errors_text].join('@')
puts '=== END ETAPA 6 ==='


# ====================================================================================
# ETAPA 7: Ingrid -- so troca parent (Samuel -> Flavia) via ParentSeatForm; seat ja eh Supervisor
# ====================================================================================
puts ''
puts '=== START ETAPA 7: Ingrid -- ParentSeatForm Samuel -> Flavia ==='

company = Company.find(2077)
flavia_user_id = 1119700

form = ParentSeatForm.new(
  user_id: 1119802,
  parent_id: flavia_user_id,
  date: '2026-05-08'
)

puts %w[user_id name parent_id date result errors].join('@')

if form.save
  result = 'OK'
  errors_text = ''
else
  result = 'FAILED'
  errors_text = form.errors.messages.inspect
end

puts [1119802, 'Ingrid Diana Campos Da Silva Mauch', flavia_user_id, '2026-05-08', result, errors_text].join('@')
puts '=== END ETAPA 7 ==='
