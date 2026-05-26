# Plano: Migração de swagger-blocks para zero-rails_openapi

**Status:** ✅ COMPLETED

## Contexto

Migração da documentação da API de swagger-blocks (Swagger 2.0) para zero-rails_openapi (OpenAPI 3.0), mantendo os schemas definidos nos serializers.

## Estado Atual

- Controllers e serializers usam `swagger-blocks` gem
- Serializers definem schemas de resposta (Client, User, etc.) e erros (CreateClientErrors, etc.)
- Controllers definem schemas de request params

## Objetivo

Manter a mesma estrutura organizacional (schemas nos serializers), usando zero-rails_openapi.

## Descobertas da Sessão

### Sintaxe Correta do zero-rails_openapi

```ruby
# CORRETO - Arrow syntax com array
schema :Name => [{ prop!: Type, prop2: Type }, {}]

# ERRADO - Não funciona
schema :Name, :object, { prop!: { type: Type } }
```

### Configuração Necessária

1. **ApplicationSerializer** - Classe base que inclui OpenApi::DSL
2. **base_doc_classes** - Deve incluir tanto ApiController quanto ApplicationSerializer
3. **Patch para tags nil** - Serializers geram tags com name: nil que quebram o sort

## Plano de Execução

### Fase 1: Infraestrutura ✅

1. **Criar ApplicationSerializer**
   ```ruby
   # app/serializers/application_serializer.rb
   class ApplicationSerializer < ActiveModel::Serializer
     include OpenApi::DSL
   end
   ```

2. **Atualizar config/initializers/open_api.rb**
   - Adicionar patch para filtrar tags nil
   - Adicionar ApplicationSerializer ao base_doc_classes

### Fase 2: Converter Serializers (22 arquivos) ✅

Para cada serializer:
1. Mudar herança: `< ActiveModel::Serializer` → `< ApplicationSerializer`
2. Remover: `include Swagger::Blocks`
3. Converter `swagger_schema` para `schema :Name => [{ props }, {}]`

**Mapeamento de tipos:**
- `key :type, :string` → `String`
- `key :type, :integer` → `Integer`
- `key :type, :boolean` → `'boolean'`
- `key :type, :array` com `items` → `{ type: Array, items: :RefName }`
- `key :$ref` → `:RefName` (symbol reference)

**Mapeamento de required:**
- `key :required, %i[field1 field2]` → usar `!` no nome: `field1!: Type, field2!: Type`

### Fase 3: Converter Controllers (28 arquivos) ✅

Para cada controller V3:
1. Remover: `include Swagger::Blocks`
2. Converter `swagger_schema` para `schema :Name => [{ props }, {}]`

### Fase 4: Atualizar ApiController ✅

1. Remover: `include Swagger::Blocks` (se existir)
2. Manter: `include OpenApi::DSL`
3. Converter schema InvalidJsonErrors para nova sintaxe

### Fase 5: Limpeza ✅

1. Remover gem swagger-blocks do Gemfile (se não usada em outros lugares)
2. Remover assets/configs relacionados ao Swagger UI antigo

### Fase 6: Validação ✅

1. Regenerar api.json
2. Validar estrutura do JSON
3. Testar no Scalar frontend

## Arquivos a Modificar

### Serializers (22)
- client_serializer.rb
- deal_serializer.rb
- deal_field_serializer.rb
- deal_with_subsidiary_serializer.rb
- field_serializer.rb
- goal_serializer.rb
- group_serializer.rb
- groupification_serializer.rb
- identifier_serializer.rb
- indicator_serializer.rb
- indicator_with_subsidiary_serializer.rb
- product_serializer.rb
- role_serializer.rb
- seat_serializer.rb
- state_serializer.rb
- subsidiary_serializer.rb
- user_serializer.rb
- user_goal_serializer.rb
- user_identifier_serializer.rb
- user_identifier_with_subsidiary_serializer.rb
- user_with_subsidiary_serializer.rb
- variable_serializer.rb

### Controllers (28)
- api_controller.rb
- api/v3/clients_controller.rb
- api/v3/deals_controller.rb
- api/v3/deals/fields_controller.rb
- api/v3/goals_controller.rb
- api/v3/groups_controller.rb
- api/v3/groups/groupifications_controller.rb
- api/v3/indicators_controller.rb
- api/v3/products_controller.rb
- api/v3/roles_controller.rb
- api/v3/subsidiaries_controller.rb
- api/v3/subsidiaries/deals_controller.rb
- api/v3/subsidiaries/goals_controller.rb
- api/v3/subsidiaries/groups/groupifications_controller.rb
- api/v3/subsidiaries/indicators_controller.rb
- api/v3/subsidiaries/users_controller.rb
- api/v3/subsidiaries/users/demotions_controller.rb
- api/v3/subsidiaries/users/fields_controller.rb
- api/v3/subsidiaries/users/identifier_promotions_controller.rb
- api/v3/subsidiaries/users/identifiers_controller.rb
- api/v3/subsidiaries/users/promotions_controller.rb
- api/v3/subsidiaries/users/seat_controller.rb
- api/v3/users_controller.rb
- api/v3/users/demotions_controller.rb
- api/v3/users/fields_controller.rb
- api/v3/users/identifier_promotions_controller.rb
- api/v3/users/identifiers_controller.rb
- api/v3/users/promotions_controller.rb
- api/v3/users/seat_controller.rb

### Config
- config/initializers/open_api.rb

## Exemplo de Conversão

### Antes (swagger-blocks)
```ruby
class ClientSerializer < ActiveModel::Serializer
  include Swagger::Blocks

  attributes :external_id, :name

  swagger_schema :Client do
    key :type, :object
    key :required, %i[external_id name]
    property :external_id do
      key :type, :string
    end
    property :name do
      key :type, :string
    end
  end

  swagger_schema :CreateClientErrors do
    key :type, :object
    property :external_id do
      key :type, :string
    end
    property :name do
      key :type, :string
    end
  end
end
```

### Depois (zero-rails_openapi)
```ruby
class ClientSerializer < ApplicationSerializer
  attributes :external_id, :name

  components do
    schema :Client => [{ external_id!: String, name!: String }, {}]
    schema :CreateClientErrors => [{ external_id: String, name: String }, {}]
  end
end
```

## Patch Necessário para open_api.rb

```ruby
# Patch to filter out tags with nil names (from serializers that only define components)
module OpenApi
  class << self
    def generate_doc(doc_name)
      settings, doc = init_hash(doc_name)
      [*(bdc = settings[:base_doc_classes]), *bdc.flat_map(&:descendants)].each do |kls|
        next if kls.oas[:doc].blank?

        doc[:paths].merge!(kls.oas[:apis])
        doc[:tags] << kls.oas[:doc][:tag]
        doc[:components].deep_merge!(kls.oas[:doc][:components] || {})
        OpenApi.routes_index[kls.oas[:route_base]] = doc_name
      end

      doc[:components].delete_if { |_, v| v.blank? }
      doc[:tags] = doc[:tags].reject { |t| t[:name].nil? }.sort_by { |t| t[:name] }
      doc[:paths] = doc[:paths].sort.to_h
      OpenApi.docs[doc_name] = doc
    end
  end
end
```

## Riscos e Mitigações

1. **Risco**: Perder trabalho com git checkout
   **Mitigação**: Fazer commits incrementais após cada fase

2. **Risco**: Sintaxe incorreta quebrar geração
   **Mitigação**: Testar com um arquivo antes de converter todos

3. **Risco**: Schemas complexos com refs não converterem corretamente
   **Mitigação**: Revisar manualmente schemas com referências a outros schemas
