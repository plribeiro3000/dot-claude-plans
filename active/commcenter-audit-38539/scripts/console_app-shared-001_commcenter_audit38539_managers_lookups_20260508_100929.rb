# Lookup -- Parents novos da aba "correcao de gerente imediato" (19 nomes desconhecidos)
# Stack: app-shared-001 (multi-tenant)
# Cada lookup roda ILIKE com 2+ palavras-chave para detectar homonimos.
# Engineer cross-references visualmente o resultado contra o que cliente queria.
# Separador: ";" (semicolon) -- "@" colide com email

LOOKUPS = [
  { label: 'Roberta Dos Santos Cardoso Da Silva', search: 'roberta%cardoso' },
  { label: 'Ricardo Morais',                      search: 'ricardo%morais' },
  { label: 'Tamiris Cristine Barbosa Nandes',     search: 'tamiris%nandes' },
  { label: 'Diego Fernandes Barbosa',             search: 'diego%fernandes%barbosa' },
  { label: 'Bianca Ezildinha Lobo Dos Santos',    search: 'bianca%ezildinha' },
  { label: 'Sandra Mendes De Menezes De Melo',    search: 'sandra%mendes' },
  { label: 'Graziele Espinel D Avila',            search: 'graziele%espinel' },
  { label: 'Guilherme Santos Da Silva',           search: 'guilherme%santos%silva' },
  { label: 'Ana Caroline Da Silva Zaniboni',      search: 'ana caroline%zaniboni' },
  { label: 'Yasmin Dutra Ferreira',               search: 'yasmin%dutra' },
  { label: 'Fernando Da Costa Duschitz',          search: 'fernando%duschitz' },
  { label: 'Udo Dieter Hansen Murback Uematu',    search: 'udo%uematu' },
  { label: 'Denise Silva De Menezes',             search: 'denise%silva%menezes' },
  { label: 'Lucas Henrique Da Silva',             search: 'lucas henrique%silva' },
  { label: 'Jaqueline Beatriz Cardoso Gomes',     search: 'jaqueline%cardoso%gomes' },
  { label: 'Selma Amanda Quirino',                search: 'selma%quirino' },
  { label: 'Ruti Dos Santos Silva',               search: 'ruti%silva' },
  { label: 'Renato Ferreira De Souza',            search: 'renato%ferreira' },
  { label: 'Amanda Victor Goncalves',             search: 'amanda victor%goncalves' }
].freeze

company = Company.find(2077)

LOOKUPS.each do |lookup|
  puts ''
  puts "=== LOOKUP: #{lookup[:label]} (search ILIKE %#{lookup[:search]}%) ==="
  puts %w[user_id name email primary_value subsidiary seat_type disabled_at].join(';')

  candidates = company.users.where('name ILIKE ?', "%#{lookup[:search]}%")

  if candidates.empty?
    puts 'NO_HITS'
    next
  end

  candidates.each do |candidate|
    primary_identifier = candidate.primary_identifier
    primary_value = primary_identifier.present? ? primary_identifier.value : ''

    subsidiary_external_id = ''
    if primary_identifier.present? && primary_identifier.subsidiary.present?
      subsidiary_external_id = primary_identifier.subsidiary.external_id
    end

    seat_type = candidate.seat.present? ? candidate.seat.type : ''

    puts [
      candidate.id,
      candidate.name,
      candidate.email,
      primary_value,
      subsidiary_external_id,
      seat_type,
      candidate.disabled_at
    ].join(';')
  end
end
