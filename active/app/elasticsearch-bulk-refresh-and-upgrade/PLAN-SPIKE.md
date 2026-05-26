# PLAN-SPIKE — OpenSearch Heap Pressure: Bulk API, Refresh Interval, and Gem Upgrade

> Reference: Contexto fornecido pelo engenheiro (diagnóstico já concluído) + novos fatos confirmados nesta iteração de revisão

## Objective

Reduzir a pressão de heap JVM no cluster OpenSearch `app-shared-001` (2x `t3.small.search`, ~1GB heap por nó) sem trocar as instâncias. A causa identificada é rajada de indexação individual (1 doc por request HTTP) chegando a 1644 docs/s. Quatro mudanças complementares atacam o problema do lado do produtor:

1. Agregar chamadas ao OpenSearch via `_bulk` API (200-500 docs por request)
2. Elevar `index.refresh_interval` de 1s para 30s
3. Remover o pin `< 7.14.0` e migrar para `opensearch-ruby` (decisão tomada pelo engenheiro)
4. Substituir `elasticsearch-persistence` 7.2.1 e `elasticsearch-model` 7.2.1 por adapter compatível com `opensearch-ruby` (decisão de qual adapter ainda pendente)

---

## Scope

### In scope
- `app/elastic_indexes/application_elastic_index.rb` — adicionar suporte a bulk save; substituir namespaces `Elasticsearch::*`
- `app/elastic_indexes/deal_elastic_index.rb` — adicionar `refresh_interval` nos settings de índice
- `app/workers/deal_elastic_index/consumer.rb` e `grower.rb` — pontos de chamada do `save_document!` que precisam mudar para bulk
- `Gemfile` e `Gemfile.lock` — remover `elasticsearch`, `elasticsearch-persistence`; adicionar `opensearch-ruby` + adapter escolhido

### Out of scope (open question)
- Monitoramento/alertas no OpenSearch (não é bloqueador desta entrega)
- Outros índices que não sejam `DealElasticIndex`
- Mudança de instância do cluster (descartada pelo contexto operacional)
- Ajuste de `number_of_replicas` ou outros settings de cluster

---

## Frente 1 — Bulk API no `ApplicationElasticIndex`

### Contexto atual

**Pattern 1: `save_document!` (1 doc por request)** — `app/elastic_indexes/application_elastic_index.rb:36-39`

```ruby
def save_document!(document, extra_attributes = nil, options = nil)
  response = new.save(document, extra_attributes, options)
  raise ElasticIndexationException unless response['result'].in?(%w[created updated])
end
```

Cada chamada faz um POST individual ao OpenSearch. `save` chama `elasticsearch_repository_save(document)` que por sua vez usa a API REST `PUT /{index}/_doc/{id}`.

**Pattern 2: `client.bulk` já existe na gem instalada** — `app/vendor/bundle/ruby/4.0.0/gems/elasticsearch-api-7.13.3/lib/elasticsearch/api/actions/bulk.rb:40-70`

O método `bulk` na gem atual aceita `arguments[:body]` como array e serializa via `Elasticsearch::API::Utils.__bulkify(body)`, enviando `Content-Type: application/x-ndjson`. O `client` é acessível via `new.client` no repository (vide `vendor/bundle/ruby/4.0.0/gems/elasticsearch-persistence-7.2.1/lib/elasticsearch/persistence/repository.rb:118-122`).

**Pattern 3: `dynamic_push_bulk` no enfileiramento Sidekiq** — `app/workers/tenant_worker.rb:92-104`

```ruby
def dynamic_push_bulk(payload)
  result =
    Sidekiq::Client.push_bulk(
      payload.merge(
        'class' => self,
        'queue' => queue.name,
        **queue.metadata
      )
    )
  Thread.current[:tenant_company_id] = nil
  result
end
```

O projeto já usa enfileiramento em lote (Sidekiq `push_bulk`) no lado do producer. O problema é que cada job do consumer ainda chama `save_document!` individualmente.

### Mapa do fluxo produtor/consumidor

```
Producer (1 job por commission)
  → UserProducer (1 job por user_id, push_bulk)
      → Consumer (1 job por deal_id, push_bulk)   ← save_document! aqui (1 request/doc)

Grower (1 job por eligibility_period)
  → save_document! em loop por deal_id             ← save_document! aqui (1 request/doc)
```

Os dois pontos de indexação são `Consumer#perform` (`app/workers/deal_elastic_index/consumer.rb:16`) e `Grower#perform` (`app/workers/deal_elastic_index/grower.rb:27-28`).

### Option A: Bulk síncrono no Grower (oportunidade imediata)

**Approach summary:** O `Grower` já tem a lista completa de `deal_ids` antes do loop de indexação (linhas 18-24 do grower.rb). Trocar o loop de `save_document!` por uma única chamada `bulk_save_documents!(deal_ids, commission_uuid: commission.uuid)` no `ApplicationElasticIndex`. Nenhuma mudança na topologia de jobs.

**Pros:**
- Mudança cirúrgica: só o Grower e o método bulk no ApplicationElasticIndex
- O Grower já tem os ids coletados — nenhum refactoring de fluxo
- Redução imediata de N requests para 1 (ou ceil(N/batch_size) para batches grandes)
- Sem risco de condição de corrida no `computation.increment_executions`

**Cons:**
- O Consumer (fluxo UserProducer → Consumer) continua com 1 doc por request — esse é o fluxo dominante na rajada diagnosticada (1644 docs/s)
- Redução de heap pressure parcial

**Cost / effort:** ~2-3h. Um método `bulk_save_documents!` em `ApplicationElasticIndex` + modificação do Grower.

**Risk:** Baixo. Mudança localizada, sem alterar topologia de jobs.

### Option B: Bulk via coalescência no Consumer (buffer em Redis)

**Approach summary:** O Consumer passa a enfileirar documentos num buffer Redis (por `commission_id`) em vez de indexar imediatamente. Um job separado (`Flusher`) drena o buffer em lotes quando atinge 200-500 docs ou após TTL (ex: 5s). O `computation.increment_executions` acontece no Consumer (antes de indexar), e o Flusher não tem acesso ao contador — o counter precisa ser separado do ato de indexação.

**Pros:**
- Cobre o fluxo dominante (Consumer é acionado pelo UserProducer, que é o fluxo mais volumoso)
- Elasticidade: burst grande → buffer grande → poucos requests bulk

**Cons:**
- Aumenta complexidade: novo worker, TTL no buffer, edge cases (TTL expirou antes de completar, Redis OOM)
- O `computation.done?` e o `Metric::Producer` atual são disparados no Consumer por deal. Com buffer, esse disparo precisa migrar para o Flusher — risco de regressão no controle de completude da commission
- TTL do buffer cria janela de latência para a busca (docs recentes aparecem com delay)

**Cost / effort:** ~1-2 dias. Novo worker + buffer Redis + ajuste no fluxo de completude.

**Risk:** Médio-alto. Mudança no fluxo de controle de completude da commission.

### Option C: Batch-aware enqueueing no UserProducer

**Approach summary:** Em vez de enfileirar 1 job por deal_id, o UserProducer enfileira jobs de "lote de deal_ids" (ex: 200 ids por job). O Consumer recebe uma lista e faz uma chamada bulk por job.

**Pros:**
- Não requer buffer Redis nem Flusher separado
- O job é autocontido (recebe os ids, faz o bulk, incrementa executions)
- Consistente com o padrão 4Shark de "IDs, não objetos"

**Cons:**
- Muda a assinatura do Consumer (`perform(commission_id, deal_ids_array, partial)`) — requer migration de jobs em voo durante o deploy
- O `computation.increment_executions` precisa ser chamado uma vez por job mas incrementar `deal_ids_array.count` — mudança no protocolo do `computation`
- O Grower (fluxo alternativo) também precisaria ser ajustado para enfileirar em batches ou indexar em bulk diretamente

**Cost / effort:** ~4-6h mais testes. Mudança em UserProducer + Consumer + possivelmente Grower.

**Risk:** Médio. Mudança de interface de job com jobs em voo durante deploy zero-downtime.

### Decisão mecânica a ser feita (Frente 1)

| Ponto | Opções | Trade-off |
|-------|--------|-----------|
| Qual fluxo atacar primeiro | Grower only (A) / Consumer via buffer (B) / Consumer via batch enqueueing (C) | A é mais seguro e imediato; B e C cobrem o fluxo dominante mas têm custo e risco maiores |
| Tamanho do batch bulk | 200 / 500 / configurável | 200 é conservador para heap 1GB; 500 expõe request size maior |
| Implementar A + C combinados | Sim / Não | Cobre ambos os fluxos num PR; aumenta o diff |

---

## Frente 2 — `index.refresh_interval`

### Contexto atual

**Pattern 4: Settings do índice em `DealElasticIndex`** — `app/elastic_indexes/deal_elastic_index.rb:8`

```ruby
settings index: { number_of_shards: 1 }
```

`refresh_interval` não está definido — usa o default OpenSearch/Elasticsearch de `1s`. Não há nenhuma ocorrência de `refresh_interval` em todo o projeto (grep confirmou zero resultados em `.rb`, `.json`, `.yml`, `.yaml`).

O método `create!` em `ApplicationElasticIndex` chama `new.create_index!(force: true)` — os settings são passados para a API de criação do índice via `Elasticsearch::Persistence::Repository::DSL`. Para mudar em índice existente usa-se a API `PUT /{index}/_settings`.

### Option A: Mudar no `settings` do `DealElasticIndex` (aplicado em `create!`)

**Approach summary:** Adicionar `refresh_interval: '30s'` no hash `settings index: { ... }` do `DealElasticIndex`. Efeito ativo apenas em novos índices (ex: após um `DealElasticIndex.create!`). O índice existente em produção não é afetado automaticamente.

**Pros:**
- Mudança de 1 linha
- A configuração fica codificada como source of truth junto ao índice

**Cons:**
- Não altera o índice existente em produção sem uma migration separada
- Requer um `PUT /deals/_settings { "index": { "refresh_interval": "30s" } }` manual/rake antes de ver efeito

**Cost / effort:** ~30min (código) + operação de migration (via console/rake).

**Risk:** Baixo. A API de settings dinâmicos do OpenSearch não requer reindex — aplica-se on-the-fly.

### Option B: Rake task de migration de settings

**Approach summary:** Criar uma rake task `elastic:migrate_settings` que chama `client.indices.put_settings(index: 'deals', body: { index: { refresh_interval: '30s' } })`. Pode rodar independentemente do deploy.

**Pros:**
- Aplica no índice existente sem `create!`
- Idempotente: pode rodar múltiplas vezes

**Cons:**
- Código extra (rake task) que não tem uso recorrente

**Cost / effort:** ~1h (rake task + documentação no PR).

**Risk:** Baixo.

### Decisão mecânica a ser feita (Frente 2)

| Ponto | Opções | Trade-off |
|-------|--------|-----------|
| Valor do refresh_interval | 10s / 30s / 60s | 30s é o sweet spot para workload bursty; 60s reduz mais mas aumenta staleness para busca |
| Como aplicar em produção | Manual via console (A) / Rake task (B) | Rake task é auditável e reproduzível |

---

## Frente 3 — Migração para `opensearch-ruby` (decisão tomada)

### Fatos confirmados

**O pin no Gemfile** — `app/Gemfile:30`:

```ruby
gem 'elasticsearch', '< 7.14.0'
```

**Razão do pin — confirmada por duas fontes independentes:**

1. A partir da versão 7.14.0 a Elastic introduziu verificação de produto via header `x-elastic-product: Elasticsearch` e tagline `"You Know, for Search"`. O OpenSearch nunca emitiu esse header — busca por `x-elastic-product` no repositório `opensearch-project/OpenSearch` via GitHub Code Search API retornou **zero ocorrências**.

2. Posição oficial do projeto OpenSearch (issue #1166, fechada por dblock em 2021-08-28):

   > "The `override_main_response_version` option in OpenSearch was introduced to support clients that worked previously against ES 7.10.2, the last OSS version, but elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch."

   E na mesma thread:

   > "Expect an opensearch-ruby release soon. It will work against ES and OpenSearch..."

   Fonte: https://github.com/opensearch-project/OpenSearch/issues/1166

3. AWS CLI confirmou: `app-shared-001` tem `"override_main_response_version": "true"` em `AdvancedOptions` — mas isso cobre apenas o body de `GET /`, não o header `x-elastic-product` exigido por `elasticsearch-ruby` >= 7.14.

**Conclusão:** nenhuma versão da gem `elasticsearch` >= 7.14 funciona com OpenSearch (inclusive 7.17.x e 8.x). A rota de upgrade dentro do ecossistema `elastic/elasticsearch-ruby` está fechada para usuários de OpenSearch. A migração para `opensearch-ruby` é o único caminho.

### O que a migração envolve

Substituir no `Gemfile`:

```ruby
# remover:
gem 'elasticsearch', '< 7.14.0'
gem 'elasticsearch-persistence'

# adicionar:
gem 'opensearch-ruby', '~> 3.4'
# + adapter (ver Frente 4)
```

No `ApplicationElasticIndex`:

- `Elasticsearch::Transport::Transport::Errors::*` → `OpenSearch::Transport::Transport::Errors::*` (linhas 4-6)
- `include Elasticsearch::Persistence::Repository` → equivalente do adapter escolhido (linha 8)
- `include Elasticsearch::Persistence::Repository::DSL` → equivalente do adapter (linha 9)
- Os aliases `elasticsearch_repository_save/update/delete` → aliases equivalentes

O método `client.bulk` continua disponível em `opensearch-ruby` com a mesma interface — `OpenSearch::Client` expõe `bulk(body: [...])` identicamente ao `Elasticsearch::Client`.

**URL fetched:** https://github.com/opensearch-project/OpenSearch/issues/1166
**Verbatim quote checked:** "elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch." — presente nos comentários da issue #1166 fechada por dblock.
**Quote substring confirmed:** comentário de dblock em 2021-08-28.

---

## Frente 4 — Adapter para substituir `elasticsearch-persistence` e `elasticsearch-model`

### Contexto atual

O `ApplicationElasticIndex` usa o `Elasticsearch::Persistence::Repository` pattern:

- `include Elasticsearch::Persistence::Repository` — provê `save`, `update`, `delete`, `search`, `find`, `create_index!`, `delete_index!`, `refresh_index!`, `index_exists?`, `client`
- `include Elasticsearch::Persistence::Repository::DSL` — provê `index_name`, `klass`, `document_type`, `settings`, `mappings`
- O `DealElasticIndex` usa o DSL para `settings`, `mappings`, `indexes` (linha 8-20 do deal_elastic_index.rb)

Lockfile atual (`app/Gemfile.lock:222-234`):

```
elasticsearch-model (7.2.1)
  activesupport (> 3)
  elasticsearch (~> 7)
  hashie
elasticsearch-persistence (7.2.1)
  activemodel (> 4)
  activesupport (> 4)
  elasticsearch (~> 7)
  elasticsearch-model (= 7.2.1)
  hashie
```

Ambas as gems dependem de `elasticsearch (~> 7)`. Ao trocar para `opensearch-ruby`, essas dependências ficam incompatíveis.

### Situação das alternativas verificadas

#### `compliance-innovations/opensearch-rails`

- **Tags no GitHub:** 30 tags — 5 nativas OpenSearch (`v0.1.0`, `v0.1.1`, `v1.0.0`, `v1.1.0.a`, `v1.1.0.b`) + 25 históricas prefixadas `es-v*` (fork original do `elasticsearch-rails`)
- **Último commit:** 2024-02-09 (adição de script de publicação + suporte Ruby 3.2)
- **Publica no RubyGems.org?** Não verificado como publicado no rubygems.org público. O script `bin/publish_gem.sh` usa `gem inabox --host $host` — publicação em gem server privado, não no rubygems.org. Busca no rubygems.org por `opensearch-model` e `opensearch-persistence` retornou "No gems found".
- **Interface:** `OpenSearch::Persistence::Repository` com `client`, `document_type`, `index_name`, `klass`, `mapping`, `settings`, `index_exists?` — estruturalmente análogo ao `Elasticsearch::Persistence::Repository`
- **Atividade:** 10 stars, 15 forks, last updated 2026-04-15 (metadata GitHub), mas último commit de código em fev 2024
- **Supply chain:** não publicado no rubygems.org público; dependência via `github:` conflitaria com Renovate/Dependabot e a política de supply chain da 4Shark

**Source pattern referenced:**
- `compliance-innovations/opensearch-rails` — gemspec em `opensearch-model/opensearch-model.gemspec` lista `gem 'opensearch-ruby', '>= 2'` como dependência runtime
- `bin/publish_gem.sh` — usa `gem inabox --host $host`, não `gem push` para rubygems.org

#### `opensearch-ruby` direto (sem Repository pattern)

- Usar `OpenSearch::Client` diretamente, sem layer de persistence
- Reescrever `ApplicationElasticIndex` sobre a API raw: `client.index`, `client.update`, `client.delete`, `client.search`, `client.bulk`, `client.indices.create`, `client.indices.delete`, `client.indices.refresh`, `client.indices.exists`
- O DSL de `settings`/`mappings` do `DealElasticIndex` seria substituído por hashes Ruby passados diretamente para `client.indices.create(body: { settings: {...}, mappings: {...} })`
- Nenhuma dependência de gem de terceiro além do `opensearch-ruby` oficial
- `opensearch-ruby` 3.4.0 publicado no rubygems.org (verificado: https://rubygems.org/gems/opensearch-ruby/versions/3.4.0)

#### `esse` gem (marcosgz/esse)

- **Versão atual:** 0.5.3 (lançada 20 mai 2026) — desenvolvimento ativo
- **Publicado no rubygems.org:** sim (24.230 downloads totais verificados)
- **Dependências runtime:** apenas `multi_json` e `thor` — sem `elasticsearch` ou `opensearch-ruby` como dependência hard (usa o que o projeto configurar)
- **Suporte a OpenSearch:** explícito — README: "Ruby simple and extremely flexible client for ElasticSearch and OpenSearch based on official clients such as elasticsearch-ruby and opensearch-ruby"
- **Repository pattern:** sim — arquitetura Index/Repository/Document com collection em chunks; suporte a bulk indexing via CLI (`esse index reset`) e API
- **Ecosistema:** gems companion (`esse-rails`, `esse-active_record`, `esse-async_indexing`, `esse-redis_storage`)
- **Atividade:** último commit 20 mai 2026, 11 stars, 1 fork
- **Fit com `ApplicationElasticIndex`:** a arquitetura esse é diferente do Repository pattern do elasticsearch-persistence. O `ApplicationElasticIndex` teria que ser reescrito seguindo o padrão esse (Index + Repository subclasses), não apenas namespace swap
- **Risco de adoção:** 24K downloads totais, 1 fork — adoção baixa. Gem de terceiro sem endosso do projeto OpenSearch nem da Elastic

**Source pattern referenced:**
- `rubygems.org/gems/esse` — versão 0.5.3, 20 mai 2026, 24.230 downloads
- `github.com/marcosgz/esse` — 317 commits, último 20 mai 2026

#### `searchkick` (ankane/searchkick)

- **Publicado no rubygems.org:** sim — gem mainstream, battle-tested em produção (README cita Instacart)
- **Suporte declarado:** README — "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."
- **Endosso oficial OpenSearch:** o projeto OpenSearch declinou manter um `opensearch-rails` e empurrou a comunidade para o `searchkick`. Posição registrada na issue `opensearch-project/opensearch-ruby#50` ("Proposal: Fork and maintain elasticsearch-rails", fechada em 2023-02-07)
- **Paradigma:** busca dentro do modelo (`class Deal; searchkick; end`) — diferente das outras três opções que mantêm a separação `Deal` (AR) × `DealElasticIndex` (index isolado)
- **Supply chain:** publicado no rubygems.org público — Renovate funciona, supply chain checks operam
- **Mantenedor:** ankane (Andrew Kane) — reputado, ativo

**Posição oficial OpenSearch documentada na issue #50 (2023-02-07):**

wbeckler (mantenedor OpenSearch), comentário em 2022-11-17:

> "I feel like if an opensearch-rails were built off a forked elasticsearch-rails, it could be to the detriment of searchkick... I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick"

simi (mantenedor rubygems.org), comentário em 2022-11-12, explicando por que ninguém da comunidade quis bancar `opensearch-rails` público:

> "Initially I was about to go with 1., but then I realized I don't want to spend my time contributing to billion dollar company projects."

**URL fetched:** https://github.com/opensearch-project/opensearch-ruby/issues/50
**Verbatim quote checked (wbeckler):** "I feel like if an opensearch-rails were built off a forked elasticsearch-rails, it could be to the detriment of searchkick... I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick" — presente no comentário de wbeckler em 2022-11-17 na issue #50.
**Quote substring confirmed (wbeckler):** comentário de wbeckler, 2022-11-17, issue opensearch-project/opensearch-ruby#50.

**URL fetched:** https://github.com/opensearch-project/opensearch-ruby/issues/50
**Verbatim quote checked (simi):** "Initially I was about to go with 1., but then I realized I don't want to spend my time contributing to billion dollar company projects." — presente no comentário de simi em 2022-11-12 na mesma issue #50.
**Quote substring confirmed (simi):** comentário de simi, 2022-11-12, issue opensearch-project/opensearch-ruby#50.

**URL fetched:** https://github.com/ankane/searchkick
**Verbatim quote checked:** "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3." — presente no README do repositório ankane/searchkick.
**Quote substring confirmed:** seção de introdução do README, ankane/searchkick.

**Superfície atual do `DealElasticIndex` que precisaria ser migrada:**

| Ponto de uso atual | Arquivo:linha | Impacto em searchkick |
|---|---|---|
| `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request swap tenant-aware) | `app/middlewares/elastic_index_connection.rb:5`, `app/config/initializers/elastic_indexes.rb:6` | Searchkick usa `Searchkick.client` global — per-request swap requer monkey-patch ou wrapper customizado |
| `DealElasticIndex.fetch_ids_by(...)` — query bool/must/range/match | `app/adapters/metric/total_adapter.rb:26`, `app/adapters/metric/quantity_adapter.rb:19`, `app/workers/deal_eligibility/grower.rb:20` | Precisa ser traduzido para DSL searchkick; resultados devem ser idênticos byte-a-byte |
| `search(query, options).raw_response` + `scroll(scroll_id:, scroll:)` | `app/workers/deal_elastic_index/expirator.rb:25,27` | Scroll não é first-class no searchkick — requer `body:` raw ou acesso ao `searchkick_index` low-level |
| `save_document!` | `app/workers/deal_elastic_index/consumer.rb:16`, `app/workers/deal_elastic_index/grower.rb:28` | Vira `Deal#reindex` ou `Deal.searchkick_index.bulk_index(...)` |
| `delete_document!` | `app/workers/deal_elastic_index/destroyer.rb:8` | Vira `Deal#reindex(:delete)` |

### Option A: `compliance-innovations/opensearch-rails` via dependência `github:`

**Approach summary:** Adicionar `gem 'opensearch-model', github: 'compliance-innovations/opensearch-rails', glob: 'opensearch-model/*.gemspec'` e `gem 'opensearch-persistence', github: 'compliance-innovations/opensearch-rails', glob: 'opensearch-persistence/*.gemspec'`. Trocar namespaces `Elasticsearch::Persistence::*` por `OpenSearch::Persistence::*` no `ApplicationElasticIndex`.

**Pros:**
- Interface mais próxima do atual: `OpenSearch::Persistence::Repository` expõe os mesmos métodos (`client`, `index_name`, `klass`, `settings`, `mappings`, etc.)
- O DSL de `settings`/`mappings` no `DealElasticIndex` provavelmente funciona sem mudança (mesmo bloco `settings index: { ... }` e `mappings dynamic: 'false' do ... end`)
- Menor reescrita do `ApplicationElasticIndex`

**Cons:**
- Não publicado no rubygems.org público — dependência `github:` conflita com Renovate/Dependabot e política de supply chain da 4Shark
- Último commit de código: fev 2024 (>1 ano sem manutenção de código)
- Compatibilidade com Ruby 4.0.4 (versão do projeto, vide Gemfile linha 8) não verificada — CI do fork testa Ruby 3.2 no máximo

**Cost / effort:** ~4-6h (namespace swap + testes de integração).

**Risk:** Alto. Dependência `github:` viola supply chain policy. Ruby 4.0 compatibility não verificada.

### Option B: `opensearch-ruby` direto (reescrita de `ApplicationElasticIndex`)

**Approach summary:** Eliminar `elasticsearch-persistence` e `elasticsearch-model` completamente. Reescrever `ApplicationElasticIndex` usando `OpenSearch::Client` diretamente. O bulk, o search, o serialize/deserialize e o index management são implementados sobre a API raw do cliente, sem o Repository pattern.

**Pros:**
- Única dependência: `opensearch-ruby` — gem oficial do projeto OpenSearch, publicada no rubygems.org, compatível com Renovate/Dependabot
- Controle total da implementação (bulk nativo, refresh, retry, error handling)
- Remove dívida das gems `elasticsearch-persistence`/`elasticsearch-model` que não têm equivalente OpenSearch estável publicado
- O método `bulk` do `OpenSearch::Client` tem interface idêntica ao do `Elasticsearch::Client`

**Cons:**
- Reescrita do `ApplicationElasticIndex` — perda do DSL de `settings`/`mappings` (o `DealElasticIndex` precisaria mudar a forma como declara settings e mappings)
- Sem layer de Repository: serialize/deserialize, `create_index!`, `delete_index!`, `refresh_index!`, `index_exists?` precisam ser reimplementados
- Nenhum outro projeto 4Shark usa este padrão — sem referência interna
- Maior esforço de implementação e teste

**Cost / effort:** ~2-3 dias (reescrita + testes de integração).

**Risk:** Médio. Reescrita de infrastructure-level code. O risco é de regressão no search (query DSL em `fetch_ids_by`, scroll, etc.) — testável em staging antes de produção.

### Option C: `esse` gem como adapter

**Approach summary:** Substituir `elasticsearch-persistence` pela gem `esse`. O `ApplicationElasticIndex` seria reescrito seguindo o padrão esse (classe que herda de `Esse::Index`, com subclasses de Repository para cada fonte de dados).

**Pros:**
- Suporte explícito a OpenSearch E Elasticsearch na mesma gem
- Publicada no rubygems.org (compatível com supply chain policy)
- Desenvolvimento ativo (último commit 20 mai 2026)
- Suporte a bulk indexing nativo
- Ecosistema de gems companion (`esse-async_indexing` pode ser relevante para o problema de heap)

**Cons:**
- Arquitetura diferente do Repository pattern atual — reescrita significativa do `ApplicationElasticIndex` e do `DealElasticIndex`
- 24K downloads totais, 1 fork — adoção muito baixa para uma gem de infrastructure
- Sem endosso do projeto OpenSearch
- Nenhum outro projeto 4Shark usa esse padrão
- A gem `esse` resolve o problema de cliente (Elasticsearch vs OpenSearch) mas exige aprender uma nova abstração

**Cost / effort:** ~3-4 dias (aprendizado da API esse + reescrita + testes).

**Risk:** Médio-alto. Adoção baixa + nova abstração + reescrita de infrastructure.

### Option D: `searchkick` como adapter

**Approach summary:** Substituir `elasticsearch-persistence` e `elasticsearch-model` pelo gem `searchkick`. A busca passa a ser declarada no modelo ActiveRecord (`class Deal; searchkick; end`), com `search_data` definindo o documento indexado. O `DealElasticIndex` como objeto isolado deixa de existir — a separação `Deal` (AR) × `DealElasticIndex` (index) é abandonada em favor do modelo integrado do searchkick.

**Pros:**
- Endossado oficialmente pelo projeto OpenSearch — wbeckler (mantenedor OpenSearch) empurrou a comunidade para o searchkick em vez de manter um `opensearch-rails` (issue opensearch-project/opensearch-ruby#50, fechada 2023-02-07)
- Publicada no rubygems.org público — Renovate funciona, supply chain checks operam normalmente
- Battle-tested em produção (README: Instacart)
- Suporta Elasticsearch 8/9 e OpenSearch 2/3 na mesma gem
- ankane é mantenedor reputado e ativo

**Cons:**
- API completamente diferente de `elasticsearch-persistence` — a separação `Deal/DealElasticIndex` é eliminada; `searchkick` coloca a busca dentro do modelo
- Per-tenant client swap (`DealElasticIndex.client = Elasticsearch::Client.new(...)` por request) não é suportado nativamente — `Searchkick.client` é global; swap per-request requer monkey-patch ou wrapper customizado (risco técnico alto, superfície desconhecida)
- Esforço de migração ~3-4 dias vs ~1-2 dias das Options B/C com paths mais claros
- Tradução de `fetch_ids_by` (bool/must/range/match → DSL searchkick) com equivalência de resultados obrigatória — risco médio nos metric adapters
- Scroll API não é first-class no searchkick; `expirator.rb` requer acesso low-level ao `searchkick_index`

**Cost / effort:**

| Trabalho | Estimativa | Risco |
|---|---|---|
| `searchkick` no `Deal` + mappings + `search_data` | 1-2h | Baixo |
| Reescrever `save_document!` callers | 2-3h | Baixo |
| Reescrever `delete_document!` callers | 30min | Baixo |
| Reescrever `fetch_ids_by` (3 callers) — traduzir bool/must/range/match para DSL searchkick com resultados idênticos | 4-6h | Médio |
| Reescrever `expirator.rb` (scroll API) | 3-4h | Médio |
| Per-tenant client swap — `Searchkick.client` é global; per-request requer gambiarra | 6-8h | Alto (unknown) |
| Testes de equivalência | 4-6h | — |
| Reindex de dados existentes em produção | 2h | Baixo |

**Total estimado: ~22-31h (~3-4 dias de trabalho focado)**

**Risk:** Médio-alto. O per-tenant client swap é o bloqueador principal — superficie desconhecida que pode escalar o esforço. A eliminação da separação `Deal/DealElasticIndex` é uma mudança de paradigma irreversível no diff.

**Source patterns referenced:**
- `app/middlewares/elastic_index_connection.rb:5` — `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request swap tenant-aware)
- `app/config/initializers/elastic_indexes.rb:6` — inicialização do client por tenant
- `app/adapters/metric/total_adapter.rb:26`, `app/adapters/metric/quantity_adapter.rb:19`, `app/workers/deal_eligibility/grower.rb:20` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_elastic_index/expirator.rb:25,27` — `raw_response` + `scroll`
- `app/workers/deal_elastic_index/consumer.rb:16` — `save_document!`
- `app/workers/deal_elastic_index/grower.rb:28` — `save_document!`
- `app/workers/deal_elastic_index/destroyer.rb:8` — `delete_document!`
- [github.com/opensearch-project/opensearch-ruby/issues/50](https://github.com/opensearch-project/opensearch-ruby/issues/50) — posição oficial OpenSearch empurrando para searchkick; verbatim wbeckler: "I think anyone can do a minor patch of elasticsearch-rails to get it to use opensearch-ruby, but I don't want to encourage that as a solution over adding whatever is missing from searchkick"
- [github.com/ankane/searchkick](https://github.com/ankane/searchkick) — README: "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."

### Decisão mecânica a ser feita (Frente 4)

| Ponto | Opções | Trade-off |
|-------|--------|-----------|
| Qual adapter substitui `elasticsearch-persistence` | `compliance-innovations/opensearch-rails` via `github:` (A) / `opensearch-ruby` direto (B) / `esse` gem (C) / `searchkick` (D) | A viola supply chain policy; B é o mais limpo mas exige reescrita; C tem adoção baixa; D tem endosso oficial OpenSearch mas per-tenant swap é risco alto e elimina separação Deal/DealElasticIndex |
| Frentes 3+4 no mesmo PR que 1+2 | Sim / PR separado | As frentes são tecnicamente independentes; separar reduz risco por PR |

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Qual fluxo atacar com bulk | Grower only (A) / Consumer via buffer Redis (B) / Consumer via batch enqueueing (C) | A é imediato e seguro; B e C cobrem o fluxo dominante mas têm mais risco | □ |
| Tamanho de batch bulk | 200 / 500 | 200 é conservador para 1GB heap; 500 maximiza throughput mas expõe requests maiores | □ |
| Valor de refresh_interval | 10s / 30s / 60s | 30s é o sweet spot documentado para workload bursty | □ |
| Como aplicar refresh_interval em produção | Manual console / rake task | Rake task é auditável | □ |
| Adapter para substituir elasticsearch-persistence | `opensearch-rails` via `github:` (A) / `opensearch-ruby` direto (B) / `esse` (C) / `searchkick` (D) | A viola supply chain policy; B exige reescrita mas é o mais limpo; C tem adoção baixa; D tem endosso oficial OpenSearch mas per-tenant swap é unknown e elimina separação Deal/DealElasticIndex | □ |
| Frentes 3+4 neste PR ou em PR separado | Junto com 1+2 / PR separado | As frentes são independentes; separar reduz o risco por PR | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| `computation.done?` dispara prematuramente se o bulk falha parcialmente | Commission marcada como concluída sem todos os docs indexados | Checar `errors` na response do `_bulk` e re-raise `ElasticIndexationException` por item com erro |
| Jobs em voo durante deploy com nova interface de Consumer (Option C da Frente 1) | Jobs enfileirados com assinatura antiga falham ao ser processados pelo novo Consumer | Manter compatibilidade de assinatura durante o deploy (aceitar tanto array quanto integer) |
| `refresh_interval: 30s` aumenta staleness da busca | Deals recém-indexados não aparecem em buscas por até 30s | Confirmar com o engenheiro se há SLA de visibilidade para buscas no `DealElasticIndex` |
| `compliance-innovations/opensearch-rails` sem publicação no rubygems.org | Dependência `github:` viola supply chain policy da 4Shark | Usar Option B, C ou D da Frente 4 |
| `esse` gem com adoção baixa | Risco de abandono; suporte limitado | Monitorar atividade; ter plano de migração para `opensearch-ruby` direto |
| Ruby 4.0.4 incompatibilidade com forks | `compliance-innovations` CI testa até Ruby 3.2 | Testar em staging antes de decidir pelo fork |
| `searchkick` per-tenant client swap — superfície desconhecida | Esforço pode escalar além de 8h; solução pode ser frágil | Prototipar o swap em staging antes de comprometer com Option D |

---

## Open questions for the engineer

1. O `DealElasticIndex` tem SLA de visibilidade para busca? Ou seja: após um deal ser indexado, em quanto tempo ele precisa aparecer nos resultados de `fetch_ids_by`? Isso determina se `refresh_interval: 30s` é aceitável.

2. Para a Frente 1, qual fluxo tem maior impacto real na rajada observada: o Grower (fluxo override/eligibility) ou o Consumer (fluxo principal UserProducer → Consumer)?

3. Há testes automatizados de integração com OpenSearch em CI? Ou os testes de elastic são apenas unitários com mocks?

4. Para a Frente 4: a política de supply chain da 4Shark permite dependência `github:` em produção? Se não, a Option A está descartada mecanicamente.

5. A reescrita do `ApplicationElasticIndex` (Options B, C e D da Frente 4) pode ir em PR separado, ou precisa ser atômica com a migração de gems da Frente 3?

6. Para a Option D (searchkick): o per-tenant client swap é um requisito inegociável? Se sim, vale prototipar antes de comprometer — o risco "unknown" pode encarecer bastante o esforço total.

---

## Sources

- `app/Gemfile:30` — `gem 'elasticsearch', '< 7.14.0'` (pin atual)
- `app/Gemfile.lock:217-234` — versões resolvidas de todas as gems elastic
- `app/elastic_indexes/application_elastic_index.rb:1-128` — implementação completa do ApplicationElasticIndex com `Elasticsearch::Persistence::Repository` e `DSL`
- `app/elastic_indexes/application_elastic_index.rb:36-39` — `save_document!` (1 doc por request)
- `app/elastic_indexes/deal_elastic_index.rb:8-20` — `settings index: { number_of_shards: 1 }` + mappings DSL (sem `refresh_interval`)
- `app/workers/deal_elastic_index/consumer.rb:16` — `DealElasticIndex.save_document!` no Consumer
- `app/workers/deal_elastic_index/grower.rb:27-28` — loop de `save_document!` por deal_id
- `app/workers/deal_elastic_index/destroyer.rb:8` — `DealElasticIndex.delete_document!` no Destroyer
- `app/middlewares/elastic_index_connection.rb:5` — `DealElasticIndex.client = Elasticsearch::Client.new(...)` (per-request swap tenant-aware)
- `app/config/initializers/elastic_indexes.rb:6` — inicialização do client por tenant
- `app/adapters/metric/total_adapter.rb:26` — `DealElasticIndex.fetch_ids_by(...)`
- `app/adapters/metric/quantity_adapter.rb:19` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_eligibility/grower.rb:20` — `DealElasticIndex.fetch_ids_by(...)`
- `app/workers/deal_elastic_index/expirator.rb:25,27` — `search(...).raw_response` + `scroll(scroll_id:, scroll:)`
- `app/workers/tenant_worker.rb:92-104` — `dynamic_push_bulk` via Sidekiq
- `app/vendor/bundle/ruby/4.0.0/gems/elasticsearch-api-7.13.3/lib/elasticsearch/api/actions/bulk.rb:40-70` — `client.bulk` disponível na gem instalada (verbatim: `raise ArgumentError, "Required argument 'body' missing" unless arguments[:body]`)
- [opensearch-project/OpenSearch#1166](https://github.com/opensearch-project/OpenSearch/issues/1166) — posição oficial: `elasticsearch-ruby 7.14` falha com OpenSearch; `override_main_response_version` não cobre o header `x-elastic-product`; verbatim: "elasticsearch-ruby 7.14 no longer does, so this won't be fixed in OpenSearch."
- [rubygems.org/gems/opensearch-ruby/versions/3.4.0](https://rubygems.org/gems/opensearch-ruby/versions/3.4.0) — `opensearch-ruby` 3.4.0 publicado no rubygems.org (gem oficial do projeto OpenSearch)
- [rubygems.org/gems/esse](https://rubygems.org/gems/esse) — `esse` 0.5.3 (20 mai 2026), 24.230 downloads, dependências runtime: `multi_json`, `thor`
- [github.com/marcosgz/esse](https://github.com/marcosgz/esse) — README: "Ruby simple and extremely flexible client for ElasticSearch and OpenSearch based on official clients such as elasticsearch-ruby and opensearch-ruby"; 317 commits, último 20 mai 2026
- [github.com/compliance-innovations/opensearch-rails](https://github.com/compliance-innovations/opensearch-rails) — 30 tags (5 nativas OpenSearch: v0.1.0 a v1.1.0.b); script `bin/publish_gem.sh` usa `gem inabox --host $host` (gem server privado, não rubygems.org); último commit de código fev 2024
- `github.com/compliance-innovations/opensearch-rails` — `opensearch-model/opensearch-model.gemspec`: dependência runtime `opensearch-ruby (>= 2)`; interface `OpenSearch::Persistence::Repository` com os métodos `client`, `index_name`, `klass`, `settings`, `mappings`, `index_exists?`
- [rubygems.org search: opensearch-model](https://rubygems.org/search?utf8=%E2%9C%93&query=opensearch-model) — "No gems found" — confirma que `opensearch-model` não está publicado no rubygems.org público
- [rubygems.org search: opensearch-persistence](https://rubygems.org/search?utf8=%E2%9C%93&query=opensearch-persistence) — "No gems found" — confirma que `opensearch-persistence` não está publicado no rubygems.org público
- [github.com/opensearch-project/opensearch-ruby/issues/50](https://github.com/opensearch-project/opensearch-ruby/issues/50) — posição oficial OpenSearch empurrando para searchkick; wbeckler (2022-11-17): "I don't want to encourage that as a solution over adding whatever is missing from searchkick"; simi (2022-11-12): "I don't want to spend my time contributing to billion dollar company projects."; issue fechada 2023-02-07
- [github.com/ankane/searchkick](https://github.com/ankane/searchkick) — README: "The latest version works with Elasticsearch 8 and 9 and OpenSearch 2 and 3."
- Not researched: suporte dual elasticsearch+OpenSearch na gem `elasticsearch` 9.x — não encontrado em changelog, release notes ou issues oficiais
