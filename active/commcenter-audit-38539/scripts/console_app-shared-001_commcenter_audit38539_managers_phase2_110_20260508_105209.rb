# Phase 2 -- 110 ParentSeatForm (correcao gerente imediato)
# Stack: app-shared-001 (multi-tenant)
# Excluidos os 2 SAME_PARENT detectados na validacao (1119738, 1243846 -- ja em estado correto)
# date = last_history.starts_at + 1.day por user, calculado dinamicamente

puts ''
puts '=== START Phase 2: 110 ParentSeatForm ==='

company = Company.find(2077)

actions = [
  { user_id: 1129006, name: 'Mariele Da Silva Miranda', parent_user_id: 1128984, parent_name: 'GUILHERME SANTOS DA SILVA' },
  { user_id: 1129014, name: 'Joao Henrique De Leao Dos Reis', parent_user_id: 1128984, parent_name: 'GUILHERME SANTOS DA SILVA' },
  { user_id: 1129016, name: 'Gleiciele Nicole Honorato', parent_user_id: 1026105, parent_name: 'LOANDRA TEIXEIRA COSTA' },
  { user_id: 1129012, name: 'Jéssica Nunes De Oliveira', parent_user_id: 1128984, parent_name: 'GUILHERME SANTOS DA SILVA' },
  { user_id: 1129000, name: 'Emily Duarte Celestino De Almeida', parent_user_id: 1128990, parent_name: 'DENISE SILVA DE MENEZES' },
  { user_id: 1129013, name: 'Karolaine Fernandes Domingues', parent_user_id: 1026105, parent_name: 'LOANDRA TEIXEIRA COSTA' },
  { user_id: 1129019, name: 'Kauhane Siqueira Ramos', parent_user_id: 1026105, parent_name: 'LOANDRA TEIXEIRA COSTA' },
  { user_id: 1119700, name: 'Flavia Dutra Castanheira De Oliveira', parent_user_id: 1026079, parent_name: 'JOEL GERALDO JUNIOR' },
  { user_id: 1119740, name: 'Maria Eduarda Liberato', parent_user_id: 1119721, parent_name: 'DIEGO FERNANDES BARBOSA' },
  { user_id: 1119733, name: 'Alex Silveira Costa', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1119787, name: 'Suelen Farias Damasceno', parent_user_id: 1119722, parent_name: 'ANA CAROLINE DA SILVA ZANIBONI' },
  { user_id: 1119746, name: 'Gabriel Raimundo Fernandes', parent_user_id: 1119711, parent_name: 'LUCAS HENRIQUE DA SILVA' },
  { user_id: 1119725, name: 'Raine Alves Rodrigues', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1119754, name: 'Manrryc Aparecido Dos Santos', parent_user_id: 1119707, parent_name: 'GRAZIELE ESPINEL D AVILA' },
  { user_id: 1119775, name: 'Lorena Gabrielle Leite Ramos', parent_user_id: 1119701, parent_name: 'YASMIN DUTRA FERREIRA' },
  { user_id: 1129023, name: 'Graciely Santos Cabral', parent_user_id: 1129005, parent_name: 'LUCIMARA DE SOUZA LIMA' },
  { user_id: 1119713, name: 'Bianca Ezildinha Lobo Dos Santos', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119747, name: 'Pedro Henrique Ferreira Costa Da Silva', parent_user_id: 1119713, parent_name: 'BIANCA EZILDINHA LOBO DOS SANTOS' },
  { user_id: 1119712, name: 'Jaqueline Beatriz Cardoso Gomes', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1119724, name: 'Crislane Ferreira Da Silva', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1119823, name: 'Larissa Chiarotto Peixoto', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119850, name: 'Tamires Stephanny Da Silva', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119864, name: 'Marcos Bruder Santana', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119867, name: 'Denize Trucolo', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119765, name: 'Guilherme Henrique Angeluci', parent_user_id: 1119722, parent_name: 'ANA CAROLINE DA SILVA ZANIBONI' },
  { user_id: 1119771, name: 'Fernanda Aparecida Valeretto', parent_user_id: 1119721, parent_name: 'DIEGO FERNANDES BARBOSA' },
  { user_id: 1119727, name: 'Luana Aparecida De Freitas', parent_user_id: 1248167, parent_name: 'AMANDA VICTOR GONCALVES' },
  { user_id: 1119734, name: 'Ingrid Vitoria De Santana', parent_user_id: 1119713, parent_name: 'BIANCA EZILDINHA LOBO DOS SANTOS' },
  { user_id: 1119726, name: 'Victor Augusto Da Silva Valencia', parent_user_id: 1119721, parent_name: 'DIEGO FERNANDES BARBOSA' },
  { user_id: 1119731, name: 'Ricardo Pereira Batista', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119862, name: 'Juliano Ramos', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119763, name: 'Xaianny Jamilly Da Silva Pereira Santana', parent_user_id: 1119764, parent_name: 'BRENO ALISSON LOPES' },
  { user_id: 1119729, name: 'Marcela Isabeli Campos Negrini', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119926, name: 'Alexandre Claudiomar De Oliveira', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
  { user_id: 1119941, name: 'Ultra Conecta', parent_user_id: 1026093, parent_name: 'UDO DIETER HANSEN MURBACK UEMATU' },
  { user_id: 1119739, name: 'Andrea Pereira De Sousa', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119846, name: 'Paula Cristina Da Silva Nani Rodrigues', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1119742, name: 'Fernando Jose Da Silva', parent_user_id: 1119721, parent_name: 'DIEGO FERNANDES BARBOSA' },
  { user_id: 1119735, name: 'Aline Batista De Oliveira', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1119792, name: 'Pamela Karolyna Leite De Queiroz', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1119838, name: 'Elienai Dos Santos Da Silva', parent_user_id: 1026093, parent_name: 'UDO DIETER HANSEN MURBACK UEMATU' },
  { user_id: 1119851, name: 'Deivid Henrique Simplicio', parent_user_id: 1119707, parent_name: 'GRAZIELE ESPINEL D AVILA' },
  { user_id: 1119936, name: 'Diego Paschoal Vieira', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
  { user_id: 1119933, name: 'Ingrid Luana Porto Dos Santos', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
  { user_id: 1119737, name: 'Analine Pereira Rodrigues', parent_user_id: 1119712, parent_name: 'JAQUELINE BEATRIZ CARDOSO GOMES' },
  { user_id: 1119924, name: 'Eletrobolinha Ltmtd', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119730, name: 'Julia Aparecida Da Silva Gonçalves', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1119869, name: 'Maria Alice Ruzisca Vaz', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119920, name: 'Detex Ltmtd', parent_user_id: 1026079, parent_name: 'JOEL GERALDO JUNIOR' },
  { user_id: 1119762, name: 'Leticia Ferreira Ponciano', parent_user_id: 1119713, parent_name: 'BIANCA EZILDINHA LOBO DOS SANTOS' },
  { user_id: 1119744, name: 'Isabella Evangelista Barbosa Oliva', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119753, name: 'Jessica Lopes Da Silva', parent_user_id: 1119713, parent_name: 'BIANCA EZILDINHA LOBO DOS SANTOS' },
  { user_id: 1119757, name: 'Leticia Lameu Siviero', parent_user_id: 1119717, parent_name: 'SELMA AMANDA QUIRINO' },
  { user_id: 1119776, name: 'Stephany Nicolly Pereira De Morais', parent_user_id: 1119701, parent_name: 'YASMIN DUTRA FERREIRA' },
  { user_id: 1119794, name: 'Lais Luzia Lavezzo', parent_user_id: 1119721, parent_name: 'DIEGO FERNANDES BARBOSA' },
  { user_id: 1119940, name: 'Valter Martins Me', parent_user_id: 1026093, parent_name: 'UDO DIETER HANSEN MURBACK UEMATU' },
  { user_id: 1119861, name: 'Diego Khattar Bernardes', parent_user_id: 1119695, parent_name: 'Ricardo Morais' },
  { user_id: 1119921, name: 'Venda Mais Conect', parent_user_id: 1119708, parent_name: 'ADYSSON GOMES MARTINS' },
  { user_id: 1119927, name: 'Tecno Shop', parent_user_id: 1119707, parent_name: 'GRAZIELE ESPINEL D AVILA' },
  { user_id: 1119928, name: 'Isabella De Oliveira Bitencourt Pereira', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
  { user_id: 1119923, name: 'Eyes Sistemas', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1026093, name: 'Udo Dieter Hansen Murback Uematu', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1243791, name: 'Alana Cristina Pinheiro Mouirim', parent_user_id: 1129008, parent_name: 'GABRIELA REGINA DE OLIVEIRA' },
  { user_id: 1119708, name: 'Adysson Gomes Martins', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243771, name: 'Diego Soares Da Fonseca', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243815, name: 'Deise De Oliveira Araujo Silva', parent_user_id: 1026105, parent_name: 'LOANDRA TEIXEIRA COSTA' },
  { user_id: 1243782, name: 'Ana Julia Dos Santos Dada', parent_user_id: 1119717, parent_name: 'SELMA AMANDA QUIRINO' },
  { user_id: 1243841, name: 'Ana Caroline Abranches Da Silva', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1243911, name: 'Lua Arissa Kavatoko', parent_user_id: 1129008, parent_name: 'GABRIELA REGINA DE OLIVEIRA' },
  { user_id: 1243873, name: 'Alexandre Claudiomar De Oliveira', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
  { user_id: 1243869, name: 'Breno Gustavo Da Silva Videira', parent_user_id: 1119711, parent_name: 'LUCAS HENRIQUE DA SILVA' },
  { user_id: 1243787, name: 'Rafaela Cristina Da Fonseca Vicente', parent_user_id: 1243774, parent_name: 'SANDRA MENDES DE MENEZES DE MELO' },
  { user_id: 1243822, name: 'Izabelly Rodrigues De Souza Araujo', parent_user_id: 1026105, parent_name: 'LOANDRA TEIXEIRA COSTA' },
  { user_id: 1243914, name: 'Kenely Cristina Cezario', parent_user_id: 1243774, parent_name: 'SANDRA MENDES DE MENEZES DE MELO' },
  { user_id: 1243821, name: 'Alexsandro Nonato Da Silva Andrelino', parent_user_id: 1129005, parent_name: 'LUCIMARA DE SOUZA LIMA' },
  { user_id: 1243919, name: 'Igor Da Silva Moura', parent_user_id: 1119764, parent_name: 'BRENO ALISSON LOPES' },
  { user_id: 1243774, name: 'Sandra Mendes De Menezes De Melo', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243775, name: 'Tanillys Ferreira Pinto', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1243845, name: 'Sofia Da Silva', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1243864, name: 'Luis Fernando Pereira Ribeiro', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1243909, name: 'Emile Rodrigues De Lima', parent_user_id: 1119802, parent_name: 'INGRID DIANA CAMPOS DA SILVA MAUCH' },
  { user_id: 1243870, name: 'Larissa Felix De Jesus', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243802, name: 'George Avenoso Do Carmo', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243783, name: 'Ana Carolina Da Silva De Souza', parent_user_id: 1119708, parent_name: 'ADYSSON GOMES MARTINS' },
  { user_id: 1243871, name: 'Ester Goncalves Lara', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243785, name: 'Lara Aparecida Lodi', parent_user_id: 1243774, parent_name: 'SANDRA MENDES DE MENEZES DE MELO' },
  { user_id: 1243808, name: 'Renata Silva Bastos', parent_user_id: 1128988, parent_name: 'RUTI DOS SANTOS SILVA' },
  { user_id: 1243788, name: 'Ellen Vitoria Da Silva Santos', parent_user_id: 1129008, parent_name: 'GABRIELA REGINA DE OLIVEIRA' },
  { user_id: 1243910, name: 'Marcos Vinicius De Oliveira Zanardo', parent_user_id: 1119764, parent_name: 'BRENO ALISSON LOPES' },
  { user_id: 1243890, name: 'Sheila Cristina De Freitas', parent_user_id: 1119694, parent_name: 'Andresa Montezori' },
  { user_id: 1119722, name: 'Ana Caroline Da Silva Zaniboni', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243916, name: 'Eduardo Jacinto Mendes Brandao', parent_user_id: 1243772, parent_name: 'LUIZ FELIPE SONEGO BONINI' },
  { user_id: 1243872, name: 'Bleica Ariadene Alves Possiano', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1119701, name: 'Yasmin Dutra Ferreira', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1243874, name: 'Alea Eletro Comercial Ltda', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1243928, name: 'Lara Bianca Ferreira De Abreu', parent_user_id: 1119701, parent_name: 'YASMIN DUTRA FERREIRA' },
  { user_id: 1119703, name: 'Maria Vitoria Suzana Cardozo', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1119707, name: 'Graziele Espinel D Avila', parent_user_id: 1243772, parent_name: 'Luiz Felipe Sonego Bonini' },
  { user_id: 1243918, name: 'Igor Henrique Menezes Ribeiro', parent_user_id: 1243774, parent_name: 'SANDRA MENDES DE MENEZES DE MELO' },
  { user_id: 1243907, name: 'Camille Vitoria Loureiro Da Silva', parent_user_id: 1119802, parent_name: 'INGRID DIANA CAMPOS DA SILVA MAUCH' },
  { user_id: 1243921, name: 'Angelica Pereira Goncalves Dos Santos', parent_user_id: 1243772, parent_name: 'LUIZ FELIPE SONEGO BONINI' },
  { user_id: 1243801, name: 'Jenifer Kely Almeida Pereira', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243858, name: 'Aparecida Das Dores Sancao', parent_user_id: 1128988, parent_name: 'RUTI DOS SANTOS SILVA' },
  { user_id: 1243867, name: 'Jackson Vitor Ribeiro Marques', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1243862, name: 'Ianca Raquel De Oliveira', parent_user_id: 1128990, parent_name: 'DENISE SILVA DE MENEZES' },
  { user_id: 1243797, name: 'Glaucia Aparecida Dos Santos', parent_user_id: 1119700, parent_name: 'FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA' },
  { user_id: 1243842, name: 'Sarah Antonia Ferreira Da Silva', parent_user_id: 1119878, parent_name: 'ROBERTA DOS SANTOS CARDOSO DA SILVA' },
  { user_id: 1243915, name: 'Danilo Damiao De Souza', parent_user_id: 1129005, parent_name: 'LUCIMARA DE SOUZA LIMA' },
  { user_id: 1243804, name: 'Angelica Pereira Lopes', parent_user_id: 1119722, parent_name: 'ANA CAROLINE DA SILVA ZANIBONI' },
  { user_id: 1243917, name: 'Luana Helen Fonseca Silva', parent_user_id: 1119714, parent_name: 'TAMIRIS CRISTINE BARBOSA NANDES' },
]

puts %w[step user_id name parent_user_id parent_name date result errors].join('@')
ok_count = 0
failed_count = 0

actions.each_with_index do |action, index|
  user = company.users.find_by(id: action[:user_id])

  if user.nil?
    puts [index + 1, action[:user_id], action[:name], action[:parent_user_id], action[:parent_name], '', 'USER_NOT_FOUND', ''].join('@')
    failed_count += 1
    next
  end

  last_history = user.seat.histories.order(:starts_at).last
  date_form = (last_history.starts_at + 1.day).to_s

  form = ParentSeatForm.new(user_id: action[:user_id], parent_id: action[:parent_user_id], date: date_form)
  saved = form.save

  if saved
    ok_count += 1
    result = 'OK'
    errors_text = ''
  else
    failed_count += 1
    result = 'FAILED'
    errors_text = form.errors.messages.inspect
  end

  puts [index + 1, action[:user_id], action[:name], action[:parent_user_id], action[:parent_name], date_form, result, errors_text].join('@')
end

puts "Phase 2 SUMMARY: ok=#{ok_count} failed=#{failed_count} total=#{actions.size}"
puts '=== END Phase 2 ==='
