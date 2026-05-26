---
name: spark-to-granola-migration
description: Migração de cliente de e-mail/agenda/notes do Spark (Readdle) para combinação Apple Mail + Apple Calendar + Granola, incluindo estratégia de arquivamento do histórico de meeting notes
type: spike
---

# SPIKE — Migração Spark → Apple Mail/Calendar + Granola

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-15
**Status:** Research complete — em execução (migração manual de notes históricas em andamento)

---

## Goal

Resolver a frustração com o Spark Desktop e definir um setup alternativo que atenda:
1. Cliente de e-mail (uso pessoal + conta Google Workspace 4Shark)
2. Agenda (uso pessoal + 4Shark)
3. Meeting notes com gravação **local** (sem bot entrando na call, invisível aos participantes) amarrada a eventos da agenda — **este é o must-have**

Problemas do Spark que motivaram a troca:
- Sync do calendário do Google Workspace travado — novos eventos não aparecem mesmo após fechar/reabrir o app; não existe botão de refresh manual
- Cliente de e-mail ruim (formatação quebrada)
- Funcionalidade útil hoje no Spark: só a parte de meeting notes + busca com IA

Restrição de custo: até ~2x o preço do Spark Premium (~$20/mês), não aceitável chegar a $500.

---

## Method

- Pesquisa web sobre problemas conhecidos de sync do Spark (confirmado: reclamação antiga, sem fix da Readdle)
- Comparativo de alternativas: Superhuman, Shortwave, Granola
- Leitura da documentação oficial do Granola (pricing, integrações Slack/MCP, calendar sync)
- Avaliação de cenários de migração do histórico de meeting notes

---

## Evidence

### Sobre o problema do Spark

- Sync do Google Workspace no Spark Desktop é reclamação recorrente documentada no MacPowerUsers e sem solução oficial da Readdle.
- Spark **não tem** botão de force-refresh — a doc oficial não menciona refresh manual.
- Único "reset" efetivo: remover e re-adicionar a conta (força re-OAuth + sync inicial).

### Alternativas avaliadas

| Ferramenta | E-mail | Agenda | Notes local sem bot | Preço | Veredito |
|---|---|---|---|---|---|
| Superhuman | ✅ | ✅ | ❌ (só via Fireflies — bot) | $30/mês | Rejeitado — perde o must-have |
| Shortwave | ✅ (Gmail only) | ✅ básico | ❌ | $9/mês | Rejeitado pelo mesmo motivo |
| **Granola** | ❌ | ❌ (só lê) | ✅ | $14/mês (Business) | **Escolhido** |
| Apple Mail + Calendar | ✅ | ✅ | ❌ | Grátis | Escolhido pra e-mail/agenda |

**Nenhuma ferramenta entrega as 3 coisas (e-mail + agenda + notes local)** num app só hoje — Spark é único nisso, mas ruim em sync.

### Granola — detalhes operacionais confirmados

- **Captura áudio do sistema localmente** (macOS). Nenhum bot entra na call; participantes não sabem.
- **Gravação é sempre manual**: Granola mostra um aviso ~1min antes do evento e tu clica pra começar. Se não clicar, não grava. Não há risco de reuniões emendadas se misturarem.
- **Calendar sync**: só lê do provedor em que foi feito login. Usuário logou com `paulo@4shark.com.br` (Workspace).
- **Multi-conta Google**: Granola **não** suporta adicionar múltiplas contas. Workaround oficial: compartilhar a agenda da conta pessoal com a conta principal via Google Calendar (permissão "Ver todos os detalhes do evento") e ativar em Settings > Calendar.
- **Integração Slack**:
  - Modo manual: clicar no botão Slack em cada note, escolher canal
  - Modo automático por pasta: pastas do Granola amarradas a canais Slack
  - Requer Google Workspace ou Microsoft 365 (não funciona com Gmail pessoal) — OK pro caso do usuário
- **MCP oficial**: disponível apenas no plano Enterprise (beta). Plano Business não tem acesso ao MCP oficial — existem MCPs comunitários no GitHub que funcionam com qualquer plano.
- **Plano escolhido**: Business ($14/mês), mas usuário está testando com **free tier** primeiro.

### Migração do histórico de meeting notes do Spark

- Spark **não tem** export bulk de meeting notes. Nenhuma API pública, nenhuma ferramenta comunitária para automação.
- Opções oficiais: copy/paste por note (manual) ou "Save as PDF" individual.
- Granola **não importa** notes históricos — mesmo exportados, viram arquivo morto em outro app (os eventos do calendar que produziram os notes já passaram, não tem como amarrar no Granola retroativamente).
- **Decisão**: arquivar histórico como markdown local em pasta oculta. Granola começa a trabalhar daqui pra frente.

---

## Conclusions

### Stack definida

| Função | Ferramenta | Custo |
|---|---|---|
| E-mail | Apple Mail (ou Spark Free como fallback) | $0 |
| Agenda | Apple Calendar | $0 |
| Meeting notes | **Granola** (teste no free; depois Business) | $0 → $14/mês |
| Histórico de notes | Markdown local em `~/.meeting-notes/` | $0 |

### Estrutura de arquivamento de meeting notes

**Localização**: `~/.meeting-notes/` (pasta oculta com prefixo `.`, escondida do Finder e do Spotlight por padrão — objetivo de privacidade)

**Hierarquia**:
```
~/.meeting-notes/
├── 2024/
├── 2025/
│   ├── 2025-04-29-aster-ponto-controle-integracao-resumo.md
│   └── 2025-04-29-aster-ponto-controle-integracao-transcript.md
└── 2026/
```

- Pasta por **ano apenas** (mês/dia seriam overkill — criariam pastas-órfãs com 1 arquivo)
- Data no nome do arquivo em formato ISO (`YYYY-MM-DD`) pra ordenar cronologicamente
- **Um arquivo separado para resumo e outro para transcript** (decisão do usuário) — conectados via campo `related` no frontmatter

**Template do arquivo**:

```markdown
---
date: YYYY-MM-DD
time: HH:MM-HH:MM GMT-03:00
title: [título exato do evento da agenda]
client: [nome do cliente]
invitees:
  - Nome (empresa)
source: spark  # ou granola quando for da ferramenta nova
summary_type: ai  # ou manual — opcional, só no arquivo de resumo. ai = gerado pela ferramenta, manual = anotação curta do usuário
type: meeting-summary  # ou meeting-transcript
related: [nome do arquivo irmão]
---

# [título] — Resumo/Transcript

[conteúdo]
```

**Por que essa estrutura**:
- Frontmatter permite busca por metadados (data, cliente, participantes)
- Markdown puro é universal — funciona em Obsidian/VS Code/TextEdit
- Seções Resumo/Decisões/Transcript permitem busca precisa sem varrer transcript ruidoso
- Pasta oculta: ninguém que abrir a máquina casualmente vê o histórico

### Uso do Slack integration (quando chegar no Business)

- **Padrão**: modo manual (reunião confidencial = não compartilha)
- **Exceção**: pastas automáticas só pra reuniões recorrentes com times fixos (1:1s semanais, dailies)

---

## Next Steps

### Feito
- [x] Decisão de stack (Apple Mail/Calendar + Granola)
- [x] Granola instalado, logado com conta 4Shark
- [x] Estrutura de arquivamento definida
- [x] Pasta `~/.meeting-notes/` criada com hierarquia `{scope}/{year}/`
- [x] Primeiro par de arquivos migrado: reunião Áster/4Shark de 2025-04-29 (resumo + transcript)
- [x] Convidados do evento Áster 2025-04-29 verificados via Google Calendar MCP e frontmatter corrigido (campo renomeado de `participants` para `invitees` — transcript não permite saber quem efetivamente participou, apenas quem foi convidado)
- [x] **60 reuniões migradas** (2025-04-29 a 2025-06-20) — 120 arquivos (-resumo.md + -transcript.md)
- [x] Estrutura reorganizada: `~/.meeting-notes/{scope}/{year}/` onde scope = `4shark` ou `personal`
- [x] Invitees preenchidos para todas as 60 reuniões via Google Calendar MCP
  - 27 reuniões com invitees preenchidos via busca no Calendar (sessão 2026-04-16)
  - 2 mantidas com invitees vazios por design (Adam entrevista, Suelen WhatsApp — sem evento no Calendar)
  - 1 mantida com invitees vazios (Salesforce 06-18 — evento solo sem convidados)
- [x] Correção de client em 2 reuniões: "4Shark" → "Grupo Luiz Hohl" (Suelen WhatsApp 06-09, Status Report Comissionamento 06-17)
- [x] Scripts de automação criados em `~/spark_extract.sh` (Chrome + AppleScript) + `~/spark_write.py` (gera arquivos .md)
- [x] **Sessão 2026-04-16 — +16 reuniões migradas** (2025-06-23 a 2025-06-30) — total passa a 76 reuniões / 153 arquivos (145 em 4shark/2025, 8 em personal/2025)
- [x] **Sessão 2026-04-16 continuação — +24 reuniões migradas** (2025-07-01 a 2025-07-18) — total passa a 100 reuniões / 201 arquivos (193 em 4shark/2025, 8 em personal/2025)
- [x] **Sessão 2026-04-16 batch 3 — +27 reuniões migradas** (2025-07-21 a 2025-07-31) — total passa a 127 reuniões / 255 arquivos (247 em 4shark/2025, 8 em personal/2025)
- [x] **Sessão 2026-04-16 batch 4 — +43 reuniões migradas** (2025-08-01 a 2025-09-30) — total passa a 170 reuniões / 341 arquivos (333 em 4shark/2025, 8 em personal/2025). Novos tipos: `community:` (RAP program), `investor:` (Vortex Capital)
- [x] **Sessão 2026-04-16 batch 5 — +90 reuniões migradas** (2025-10-01 a 2025-12-22) — total passa a 260 reuniões / 521 arquivos (513 em 4shark/2025, 8 em personal/2025). Script `spark_write.py` ajustado: `Action Items` tornou-se opcional (formato moderno do Spark omite essa seção)
- [x] **Sessão 2026-04-16 batch 6 — +89 reuniões migradas** (2025-12-23 a 2026-03-27) — total passa a ~349 reuniões / 697 arquivos. Criada pasta `~/.meeting-notes/4shark/2026/`. Permissões do `spark_write.py` generalizadas em `settings.local.json` (`Bash(~/spark_write.py:*)`)
- [x] **Sessão 2026-04-16 batch 7 — +29 reuniões migradas** (2026-03-27 a 2026-04-14) — total passa a ~378 reuniões / 755 arquivos. Novos vendors: Agência Mestre (planejamento de mídia)
- [x] **Sessão 2026-04-17 — auditoria de consistência e normalização retroativa**:
  - Normalização de casing (102 arquivos): `atento` → `Atento`, `commcenter` → `Commcenter`, `ecom-energia` → `Ecom Energia`, `magnatech` → `Magnatech`, `virtual-connection` → `Virtual Connection`, `spray-tools` → `Spray Tools`, `positivo` → `Positivo`, `cielo` → `Cielo`, `"Grupo Luiz Hohl"` (com aspas) → sem aspas, `Atento México` → `Atento`, `Áster` → `Aster Máquinas`, `Maq Nelson` → `Maqnelson`, `Macsynie Silva` → `Macsynie`
  - Reclassificações: 4 arquivos `client: 4Shark` corrigidos para categoria correta (`Brisanet`, `vendor: Orbe`, `internal: novo-produto`), `Jackson Tirone` e `Adam` viraram `internal: interview`, `Luis Quintino` virou `vendor:`, `mestre-seo` virou `Agência Mestre`, `pentest-vendor` virou `Avant Services`
  - Conteúdo: 1033 ocorrências de 4Shark misspellings (`Force Shark`, `Forcheck`, `Forchar`, `ForChat`, `For Shark`) em 239 arquivos normalizadas para `4Shark`; 17 ocorrências de Almaviva misspellings (`Alma Viva`, `AlmaViva`, `almaviva`) normalizadas para `Almaviva`
  - Dadosfera: par completo regenerado (resumo + transcript estavam órfãos — re-extraído do Spark via URL)
- [x] `spark_write.py` estendido: novo 4º parâmetro `context_type` substituindo o mapeamento implícito (scope → client/event)
  - `client:` — cliente pagante
  - `vendor:` — fornecedor (novo, ex: Elven Works, Salesforce)
  - `internal:` — reunião interna 4Shark, valor = tipo (novo, ex: `alignment`)
  - `event:` — categoria pessoal (wedding, family, etc.)
- [x] Correções retroativas de classificação:
  - 6 dailies (12/06, 13/06, 16/06, 17/06, 18/06, 20/06): `client: 4Shark` → `client: Grupo Luiz Hohl` (12 arquivos)
  - 2 Barigui antigos (08/05): `client: Barigui` → `client: Grupo Barigui` (2 arquivos)
  - 1 Salesforce (18/06): `client: Salesforce` → `vendor: Salesforce` (2 arquivos)

### Em andamento / pendente

1. **Adicionar conta pessoal ao Granola** via compartilhamento do Google Calendar:
   - Abrir Google Calendar de `plribeiro3000@gmail.com` no navegador
   - Configurações da agenda → Compartilhar com pessoas específicas → adicionar `paulo@4shark.com.br` com permissão "Ver todos os detalhes do evento"
   - Aceitar o compartilhamento na conta 4Shark
   - Ativar a agenda nova em Granola → Settings → Calendar

2. **Continuar migração manual** das meeting notes antigas do Spark:
   - Usuário vai colando título + data + resumo + transcript
   - Criar dois arquivos por reunião (resumo e transcript) seguindo template
   - Convidados vêm do Google Calendar MCP (não do transcript) — campo `invitees` no frontmatter
   - Usuário disse que tem "quase um ano" de notes no Spark — pode priorizar as que realmente importam em vez de migrar tudo
   - **Última reunião migrada: 2026-04-14** — próxima sessão começa a partir de 2026-04-15 (ou data seguinte com notes)

3. **Cancelar Spark** só depois que a migração manual do histórico relevante terminar (manter pago por mais ~1 mês).

4. **Avaliar upgrade do Granola Business** após teste no free, se experiência confirmar valor.

### Notas de execução

#### Busca de invitees no Google Calendar

- **Calendário principal**: `paulo@4shark.com.br` — tem acesso às agendas de todos os funcionários 4Shark
- **Calendário pessoal**: `plribeiro3000@gmail.com` — para reuniões pessoais e adhoc criadas via Spark
- **Outros calendários acessíveis**: sergio@, danilo.assis@, camila.bergamasco@, santiago.velasquez@, patrick.mares@, ione.ruguzina@, elisio.filho@ (todos @4shark.com.br)
- **Reuniões Atento LATAM**: quando não encontradas em paulo@, buscar em santiago.velasquez@4shark.com.br
- **Dica**: usar `fullText` com termo-chave do título + `timeMin/timeMax` com janela de 2h em torno do horário
- **Formato invitees**: apenas emails, um por linha, sem nomes ou empresas

#### Mapeamentos de eventos recorrentes

- **"4SHARK Daily | Comissionamento"** (organizado por suelen.santana@grupoluizhohl.com.br) = reunião diária do projeto Grupo Luiz Hohl. Mapeado para:
  - `daily-acompanhamento-interno` (12/06, 13/06, 16/06, 17/06, 18/06, 20/06)
  - `ponto-controle-grupo-luiz-hohl` (18/06 — mesma reunião, 3min iniciais antes do daily)
- **"Alignment"** (organizado por paulo@4shark.com.br, recorrente) = reunião interna 4Shark. Mapeado para:
  - `status-report-sistema-comissionamento` (17/06 — status report discutido no Alignment)
- **"Áster / 4Shark - Ponto de Controle Integração"** (organizado por camila.bergamasco@) = recorrente semanal
- **"Alignment"** (recorrente interna 4Shark, organizado por paulo@) → `internal: alignment` (context_type `internal`, valor = tipo da reunião interna)
- **"bate papo founders"** (ad-hoc entre Paulo + Sergio + Danilo Assis) → `internal: founders`
- **"Ponto de Controle Grupo Luiz Hohl | 4Shark"** = alias para o daily recorrente (Suelen), mesmo invitees

#### Convenções de nomenclatura de entidades

- **Salesforce** = `vendor:` (não cliente — Salesforce é fornecedor de Heroku)
- **Elven / Elven Works** = `vendor:` (domínio `elven.works`)
- **Grupo Barigui** (não "Barigui") = `client:` (nome canônico, domínio `grupobarigui.com.br`)
- **Grupo Luiz Hohl** = `client:` para dailies "4SHARK Daily | Comissionamento" (organizado por suelen.santana@grupoluizhohl.com.br)
- **Aster Máquinas** = `client:` (domínio `astermaquinas.com.br`)
- **Atento** = `client:` (unificado — não "Atento Mexico" nem "Atento MX"; contexto regional vai no slug)
- **Orbe** = `vendor:` (domínio `orbe.ai` — consultoria de IA contratada pela 4Shark)
- **Macsynie** = `client:` (email `contatomacsynie@gmail.com`)
- **Self Telecom** = `client:` (nome canônico)
- **Grupo SADAR** = `client:` (operador Peugeot no Uruguai, domínio `peugeot.com.uy`)
- **Commcenter** = `client:` (domínio `commcenter.com.br`)
- **Grupo Barigui** = `client:` (domínio `grupobarigui.com.br`)
- **Ecom Energia** = `client:` (domínio `ecomenergia.com.br`)
- **Brisanet** = `client:` (domínio `grupobrisanet.com.br`)
- **PageGroup** = `vendor:` (recrutamento — domínios `pageinterim.com.br` / `michaelpage.com.br`)
- **Giftty** = `vendor:` (fornecedor de vouchers)
- **Livve** = `vendor:` (parceiro via arista.com.br)
- **Incentivale** = `vendor:` (fornecedor de incentivos)
- **Maqnelson** = `client:` (domínio `maqnelson.com.br`)
- **Rede Brasil** = `client:` (domínio `redebrasil.com.br`)
- **Vortex Capital** = `investor:` (domínio `vortexcapital.io` — novo tipo)
- **RAP** = `community:` (programa de empreendedorismo, novo tipo)
- **Hiperbanco** = `vendor:` (BaaS — Banking as a Service para produto 4Shark Pay)
- **Swap** = `vendor:`/concorrência (`vortexcapital.io`) — classificado como `internal: founders` quando é discussão interna sobre eles
- **Frete.com** = `client:` (domínio `frete.com`)
- **Lavronorte** = `client:` (domínio `lavronorte.com.br`)
- **Grupo Oyama** = `client:` (domínio `grupooyama.com.br`)
- **Tecar** = `client:` (via cairodale/dvaassets — parceiros externos)
- **Lumira Tech** = `vendor:` (domínio `lumiratech.com`)
- **Ciarama Máquinas** = `client:` (domínio `ciarama.com.br`)
- **BanaTech Consulting** = `vendor:` (consultoria de tecnologia)
- **Datarails** = `vendor:` (plataforma FP&A, domínio `datarails.com`)
- **Hevo** = `vendor:` (data integration, domínio `hevodata.com`)
- **Airbyte** = `vendor:` (data integration, domínio `airbyte.io`)
- **Zing** = `vendor:` (podcast que convidou Paulo como entrevistado, `zingfuel@gmail.com`)
- **PageGroup** = `vendor:` (recrutamento)
- **Wonderful** = recrutamento externo → `internal: interview` (Paulo como candidato pitchado pelo GM Helder Somoggi)
- **Magnatech** = `client:` (integração, contato `brunap.magna@gmail.com`)
- **Virtual Connection** = `client:` (domínios `vconnection.com.br` / `virtualconnection.com.br`)
- **Positivo** = `client:` (security assessment — 4Shark sendo avaliada)
- **Cielo** = `vendor:` (suporte de adquirência — 4Shark como cliente da Cielo)
- **Avant Services** = `vendor:` (prestador de pentest para compliance Positivo, domínio `avantservices.com.br`) — substitui o placeholder `pentest-vendor`
- **Spray Tools** = `client:` (domínio `spraytools.com.br`)
- **Agência Mestre** = `vendor:` (agência de planejamento de mídia / SEO, domínio `mestreseo.com.br`) — canônico (substitui `mestre-seo`)
- **Almaviva** = `client:` (nome canônico — corrigir speech-to-text `Alma Viva`/`AlmaViva`/`almaviva` para `Almaviva` no conteúdo)
- **Luis Quintino** = `vendor:` (parceiro externo para internacionalização)
- **Dadosfera** = `vendor:` (PoC de ETL/IA, domínios `dadosfera.io` / `dadosfera.ai`)
- **Archbit** = `vendor:` (consultoria/parceiro — reuniões internas 4Shark ao discutir o engajamento com eles)

#### Novos tipos de reunião interna (`internal:`)

- `interview` — entrevistas de candidatos. Convenção: convidar o candidato via email externo, slug = `entrevista-{nome}` ou `bate-papo-{nome}-roundN`
- `learning` — eventos externos de aprendizado (CTO Fellowship, conferências, treinamentos)
- `1-on-1` — reuniões 1:1 entre integrantes 4Shark. Slug = `1-on-1-{pessoa1}-{pessoa2}`
- `founders` — conversas entre fundadores (Paulo + Sergio + Danilo)
- `estrategia-comercial` — reuniões de estratégia de vendas/comercial
- `novo-produto` — discussões de design de produto novo (Incentive Card, campanhas, frontend novo, 4Shark Pay, Integrador PivotXL)
- `roadmap` — discussões internas de roadmap de produto, feedback de plataforma, iniciativas de melhoria (renomeado de `melhoria-processos` — a ideia é "o que queremos construir/melhorar", não execução)

#### Novos context_types

- `investor:` — reuniões com investidores / VCs (ex: Vortex Capital)
- `community:` — programas / comunidades de aprendizado com estrutura de módulos/sessões (ex: RAP)

### Contexto pra continuação em nova sessão

- Este spike documenta tudo. Nova sessão deve ler `SPIKE.md` primeiro e continuar a partir do item "Em andamento / pendente".
- **Estrutura no filesystem**:
  ```
  ~/.meeting-notes/
  ├── 4shark/2025/    # ~257 reuniões (513 arquivos)
  ├── 4shark/2026/    # ~117 reuniões (234 arquivos)
  └── personal/2025/  # 4 reuniões (8 arquivos)
  ```
- **Última reunião migrada**: 2026-04-14 (magnatech-configuracoes-integracao-regras, atento-integracao-pagamentos)
- Preferências do usuário confirmadas:
  - Comunicação em pt-BR
  - Resposta direta, sem rodeios
  - Prefere dividir transcript e resumo em arquivos separados
  - Prefere pasta oculta (privacidade)
  - Pasta por ano apenas, data no nome do arquivo
  - Invitees = apenas emails do Calendar (sem nomes)
