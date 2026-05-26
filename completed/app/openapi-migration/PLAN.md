# Plan: Migrate from swagger-blocks to zero-rails_openapi

**Status:** ✅ COMPLETED

## Context

Migrate API documentation from swagger-blocks (Swagger 2.0) to zero-rails_openapi (OpenAPI 3.0), keeping schemas defined in serializers.

## Current State

- Controllers and serializers use the `swagger-blocks` gem
- Serializers define response schemas (Client, User, etc.) and errors (CreateClientErrors, etc.)
- Controllers define request param schemas

## Objective

Keep the same organizational structure (schemas in serializers), using zero-rails_openapi.

## Session Findings

### Correct zero-rails_openapi syntax

```ruby
# CORRECT - Arrow syntax with array
schema :Name => [{ prop!: Type, prop2: Type }, {}]

# WRONG - Does not work
schema :Name, :object, { prop!: { type: Type } }
```

### Required configuration

1. **ApplicationSerializer** — base class that includes OpenApi::DSL
2. **base_doc_classes** — must include both ApiController and ApplicationSerializer
3. **Patch for nil tags** — serializers generate tags with name: nil that break the sort

## Execution Plan

### Phase 1: Infrastructure ✅

1. **Create ApplicationSerializer**
   ```ruby
   # app/serializers/application_serializer.rb
   class ApplicationSerializer < ActiveModel::Serializer
     include OpenApi::DSL
   end
   ```

2. **Update config/initializers/open_api.rb**
   - Add patch to filter out nil tags
   - Add ApplicationSerializer to base_doc_classes

### Phase 2: Convert Serializers (22 files) ✅

For each serializer:
1. Change inheritance: `< ActiveModel::Serializer` → `< ApplicationSerializer`
2. Remove: `include Swagger::Blocks`
3. Convert `swagger_schema` to `schema :Name => [{ props }, {}]`

**Type mapping:**
- `key :type, :string` → `String`
- `key :type, :integer` → `Integer`
- `key :type, :boolean` → `'boolean'`
- `key :type, :array` with `items` → `{ type: Array, items: :RefName }`
- `key :$ref` → `:RefName` (symbol reference)

**Required mapping:**
- `key :required, %i[field1 field2]` → use `!` in the name: `field1!: Type, field2!: Type`

### Phase 3: Convert Controllers (28 files) ✅

For each V3 controller:
1. Remove: `include Swagger::Blocks`
2. Convert `swagger_schema` to `schema :Name => [{ props }, {}]`

### Phase 4: Update ApiController ✅

1. Remove: `include Swagger::Blocks` (if present)
2. Keep: `include OpenApi::DSL`
3. Convert the InvalidJsonErrors schema to the new syntax

### Phase 5: Cleanup ✅

1. Remove the swagger-blocks gem from the Gemfile (if not used elsewhere)
2. Remove assets/configs related to the old Swagger UI

### Phase 6: Validation ✅

1. Regenerate api.json
2. Validate JSON structure
3. Test on the Scalar frontend

## Files to Modify

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

## Conversion Example

### Before (swagger-blocks)
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

### After (zero-rails_openapi)
```ruby
class ClientSerializer < ApplicationSerializer
  attributes :external_id, :name

  components do
    schema :Client => [{ external_id!: String, name!: String }, {}]
    schema :CreateClientErrors => [{ external_id: String, name: String }, {}]
  end
end
```

## Required patch for open_api.rb

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

## Risks and Mitigations

1. **Risk**: Lose work via `git checkout`
   **Mitigation**: Make incremental commits after each phase

2. **Risk**: Incorrect syntax breaking generation
   **Mitigation**: Test with one file before converting all

3. **Risk**: Complex schemas with refs failing to convert correctly
   **Mitigation**: Manually review schemas that reference other schemas
