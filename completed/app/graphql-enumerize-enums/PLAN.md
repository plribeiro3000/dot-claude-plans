# PLAN - GraphQL Enum Types for Enumerize Fields

## ⛔ ABANDONED

**Status:** Abandoned
**Date:** 2025-12-31
**Reason:** GraphQL specification limitation - not fixable without frontend changes

### Why This Approach Does Not Work

GraphQL enums MUST be sent as unquoted identifiers in queries. This is a GraphQL specification requirement, not a graphql-ruby limitation.

```graphql
campaigns(status: final)     # ✅ GraphQL enum (no quotes)
campaigns(status: "final")   # ❌ String literal (with quotes) - REJECTED
```

**All frontends would need to be updated** to send enum values without quotes. This is not viable for backwards compatibility.

### What Was Tried

1. **Tag 3.2.0:** Replaced String with Enum types in resolver filters → Broke all frontends
2. **Tag 3.2.1:** Added `coerce_input` to accept strings → Did not work (validation happens before coercion)
3. **Tag 3.2.2:** Rollback to String types → Current state

### Conclusion

Using GraphQL Enum types for filter arguments requires ALL clients to change how they send queries. The only way to validate enum values server-side while accepting string literals is to keep using String type and add manual validation in resolvers.

---

# PLAN - Fix GraphQL Enum Validation for String Literals (ARCHIVED)

## Context

**Previous Implementation (tags 3.2.0 and 3.2.1):**
- Replaced String fields with GraphQL Enum types for enumerize fields
- Created `app/graphql_enums/` directory with `ApplicationGraphqlEnum` base class
- Generated 20 enum types (e.g., `CampaignStatusGraphqlEnum`, `UserPaymentIntegrationStatusGraphqlEnum`)
- Updated resolvers to use enum types in option filters

**Breaking Issue:**
GraphQL specification requires enum values in queries to be unquoted identifiers:

```graphql
# Frontend sends (string literal with quotes)
campaigns(status: "final")   # ❌ GraphQL rejects

# GraphQL expects (identifier without quotes)
campaigns(status: final)     # ✅ Correct
```

**Error Message:**
```
Argument 'status' on Field 'campaigns' has an invalid value ("final").
Expected type 'CampaignStatusGraphqlEnum'.
```

**Attempted Fix (3.2.1):**
Added `coerce_input` method to `ApplicationGraphqlEnum` to accept string inputs. However, this does not work because GraphQL validates the query **before** coercion happens. String literals fail at the parsing/validation stage.

**GraphQL Specification:**
Per [graphql-ruby documentation](https://graphql-ruby.org/type_definitions/enums.html): "In a GraphQL query, enums are written as identifiers (not strings)". Strings are only accepted via JSON variables.

## Objective

**Target State:**
1. Keep enum types for OUTPUT fields (return values) - they work correctly and provide type safety
2. Accept STRING LITERALS in INPUT (filter arguments in resolvers) - backwards compatible with frontends
3. Validate string values against allowed enum values
4. Return 400 Bad Request (not 500 Internal Server Error) when invalid values are sent
5. Maintain backwards compatibility with all frontends (web, mobile, integrations)

**Success Criteria:**
- [ ] Frontends can send `campaigns(status: "final")` without errors
- [ ] Invalid values return 400 with clear validation message
- [ ] Output fields continue using enum types (type-safe responses)
- [ ] Zero code changes required in frontends
- [ ] Zero 500 errors from invalid enumerize values

## Problem Analysis

**Current Architecture:**
```ruby
# Model
class Campaign < ApplicationRecord
  enumerize :status, in: { draft: 0, active: 1, final: 2 }
end

# Enum (EXISTS)
class CampaignStatusGraphqlEnum < ApplicationGraphqlEnum
  source Campaign, :status
  # Generates: value "draft", value "active", value "final"
end

# Type (EXISTS)
class CampaignGraphqlType < ObjectType
  field :status, CampaignStatusGraphqlEnum, null: true  # ✅ Output works
end

# Resolver (EXISTS - BROKEN)
class CampaignGraphqlResolver < CollectionGraphqlResolver
  option(:status, type: CampaignStatusGraphqlEnum) { |scope, status| scope.for_status(status) }
  # ❌ Rejects "final" at query validation stage
end
```

**Why `coerce_input` Doesn't Work:**

GraphQL query processing stages:
1. **Parsing** - Query string → AST (Abstract Syntax Tree)
2. **Validation** - Check types, arguments, fields ❌ **Fails here for string literals**
3. **Execution** - Call resolvers
4. **Coercion** - `coerce_input` is called ⚠️ **Never reached**

String literals (`"final"`) fail at stage 2 (validation) before coercion happens.

## Solution Options

### Option 1 - Use String Type with Manual Validation (RECOMMENDED)

**How it works:**
1. Keep enum types for OUTPUT fields (responses)
2. Use String type for INPUT arguments (filters)
3. Add validation in the option block to check against allowed values
4. Raise `GraphQL::ExecutionError` with 400 status for invalid values

**Implementation:**

```ruby
# Resolver
class CampaignGraphqlResolver < CollectionGraphqlResolver
  option(:status, type: String) do |scope, status|
    validate_enum_value!(Campaign, :status, status) if status.present?
    scope.for_status(status)
  end

  private

  def validate_enum_value!(model, attribute, value)
    allowed = model.send(attribute).values
    return if allowed.include?(value)

    raise GraphQL::ExecutionError.new(
      "Invalid value '#{value}' for #{attribute}. Allowed values: #{allowed.join(', ')}",
      extensions: { code: 'BAD_USER_INPUT' }
    )
  end
end
```

**Pros:**
- ✅ Accepts string literals (backwards compatible)
- ✅ Clear validation errors (400 Bad Request)
- ✅ No frontend changes required
- ✅ Simple implementation
- ✅ Keeps enum types for output (type safety)
- ✅ Validation happens at resolver level (clear error context)

**Cons:**
- ❌ Manual validation in each resolver option
- ❌ Duplication across resolvers
- ❌ Loses schema-level type checking for inputs

**Mitigation for Cons:**
- Extract validation to shared concern/module
- Add to `ApplicationGraphqlResolver` base class

### Option 2 - Create Custom EnumString Scalar Type

**How it works:**
1. Create custom scalar that accepts strings
2. Override `coerce_input` to validate against enum values
3. Store enum reference in scalar instance
4. Use scalar type for input arguments

**Implementation:**

```ruby
# app/graphql/scalars/enum_string_scalar.rb
class EnumStringScalar < GraphQL::Schema::Scalar
  def self.for_enum(enum_class)
    Class.new(self) do
      @enum_class = enum_class

      def self.coerce_input(value, context)
        return nil if value.nil?

        unless value.is_a?(String)
          raise GraphQL::CoercionError, "#{value.inspect} is not a string"
        end

        allowed = @enum_class.values.keys
        unless allowed.include?(value)
          raise GraphQL::CoercionError,
            "Invalid value '#{value}'. Allowed: #{allowed.join(', ')}"
        end

        value
      end

      def self.coerce_result(value, context)
        value.to_s
      end
    end
  end
end

# Usage in resolver
class CampaignGraphqlResolver < CollectionGraphqlResolver
  CampaignStatusString = EnumStringScalar.for_enum(CampaignStatusGraphqlEnum)

  option(:status, type: CampaignStatusString) { |scope, status| scope.for_status(status) }
end
```

**Pros:**
- ✅ Accepts string literals
- ✅ Validation at type level
- ✅ Reusable pattern
- ✅ Clear error messages

**Cons:**
- ❌ Complex implementation
- ❌ Need to create scalar instance for each enum
- ❌ Additional boilerplate in resolvers
- ❌ Mixes concerns (scalar vs enum)

### Option 3 - Hybrid with Input Object Types

**How it works:**
1. Create separate Input types for filters
2. Use String with validation for input types
3. Keep Enum for output types
4. Consolidate validation logic in input types

**Implementation:**

```ruby
# app/graphql/inputs/campaign_filter_input.rb
class CampaignFilterInput < GraphQL::Schema::InputObject
  argument :status, String, required: false

  def prepare
    if status.present?
      allowed = Campaign.status.values
      unless allowed.include?(status)
        raise GraphQL::ExecutionError.new(
          "Invalid status '#{status}'. Allowed: #{allowed.join(', ')}"
        )
      end
    end

    self
  end
end

# Resolver
class CampaignGraphqlResolver < CollectionGraphqlResolver
  argument :filters, CampaignFilterInput, required: false

  def resolve(filters: nil)
    scope = Campaign.all
    scope = scope.for_status(filters.status) if filters&.status
    scope
  end
end
```

**Pros:**
- ✅ Centralized validation
- ✅ Better organization
- ✅ Reusable filter objects

**Cons:**
- ❌ Major refactoring required
- ❌ Changes resolver interface
- ❌ Breaking change for API structure
- ❌ Not backwards compatible

## Recommended Solution

**Option 1 - String Type with Shared Validation Module**

This option provides the best balance:
- Backwards compatible (critical requirement)
- Simple to implement
- Clear validation errors
- Minimal changes to existing code

**Implementation Strategy:**

1. Create shared validation module in `ApplicationGraphqlResolver`
2. Keep enum types for output fields
3. Change resolver options from enum type to String type
4. Add validation call in each option block
5. Return 400 errors for invalid values

## Execution Phases

### Phase 1 - Create Validation Infrastructure

**Objective:** Add shared validation logic to base resolver

**Components:**
- `ApplicationGraphqlResolver#validate_enum_value!` - Shared validation method
- Error handling with 400 status code
- Clear error messages with allowed values

**Dependencies:** None

**Success Criteria:**
- [ ] Validation method available in all resolvers
- [ ] Raises `GraphQL::ExecutionError` with code `BAD_USER_INPUT`
- [ ] Error message includes allowed values list

### Phase 2 - Update Resolver Options

**Objective:** Change enum types to String with validation

**Components:**
- Update all resolver `option` calls using enum types
- Change `type: {Model}{Field}GraphqlEnum` to `type: String`
- Add `validate_enum_value!` call in option block

**Dependencies:** Phase 1 complete

**Success Criteria:**
- [ ] All resolver options use String type for filters
- [ ] All options validate input values
- [ ] Invalid values return 400 with clear message
- [ ] Valid values work as before

### Phase 3 - Testing and Validation

**Objective:** Verify all scenarios work correctly

**Components:**
- Test valid enum values work
- Test invalid enum values return 400
- Test null/empty values work
- Test all affected resolvers

**Dependencies:** Phase 2 complete

**Success Criteria:**
- [ ] All existing tests pass
- [ ] New validation tests pass
- [ ] No 500 errors from enum values
- [ ] Frontends work without changes

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Output field type | Keep Enum types | Works correctly, provides type safety |
| Input argument type | Change to String | Required for backwards compatibility |
| Validation location | Resolver option block | Clear error context, simple implementation |
| Validation method | Shared module in base class | DRY principle, consistent errors |
| Error type | `GraphQL::ExecutionError` | Standard GraphQL error handling |
| Error code | `BAD_USER_INPUT` | GraphQL best practice for validation errors |

## Affected Components

**Resolvers with enum filters (20 files):**
- `campaign_graphql_resolver.rb` - status filter
- `campaign_fund_graphql_resolver.rb` - status filter
- `commission_graphql_resolver.rb` - status filter
- `company_graphql_resolver.rb` - status filter
- `incentive_campaign_graphql_resolver.rb` - status filter
- `incentive_credit_graphql_resolver.rb` - status filter
- `incentive_payment_graphql_resolver.rb` - status filter
- `partial_commission_graphql_resolver.rb` - status filter
- `payment_graphql_resolver.rb` - status filter
- `payroll_request_graphql_resolver.rb` - action/status filters
- `plan_graphql_resolver.rb` - status filter
- `plan_participation_graphql_resolver.rb` - status filter
- `plan_slice_graphql_resolver.rb` - status filter
- `plan_slice_commission_graphql_resolver.rb` - status filter
- `plan_statement_graphql_resolver.rb` - status filter
- `user_payment_graphql_resolver.rb` - integration_status filter
- `variable_graphql_resolver.rb` - calculation/frequency filters
- `calendar_graphql_resolver.rb` - frequency filter
- `metric_graphql_resolver.rb` - calculation filter

**Enum files to keep (for output):**
- All 20 existing enum files remain unchanged
- Continue to be used in GraphQL type field definitions

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Miss a resolver during update | Medium | Grep for all `type:.*GraphqlEnum` in resolvers |
| Validation logic inconsistent | Low | Use shared method in base class |
| Performance impact from validation | Low | Enumerize lookup is fast, cached in memory |
| Error messages unclear | Low | Include allowed values in error text |

## Assumptions

- Frontends send enum values as string literals (`"final"`, not `final`)
- All enumerize fields use symbol values internally (`:draft`, `:active`, `:final`)
- Validation errors should return 400, not 500
- Backwards compatibility is critical (no frontend changes)
- Enum types for output fields are working correctly

## Out of Scope

- Changing frontend code to send unquoted identifiers
- Creating new enum types
- Modifying mutation arguments (separate task if needed)
- Performance optimization for validation
- Internationalization of error messages

## References

**Documentation:**
- [GraphQL-Ruby Enums](https://graphql-ruby.org/type_definitions/enums.html)
- [GraphQL-Ruby Scalars](https://graphql-ruby.org/type_definitions/scalars)
- [GraphQL Specification on Enums](http://spec.graphql.org/June2018/)

**Code:**
- Base enum: `app/graphql_enums/application_graphql_enum.rb`
- Base resolver: `app/graphql_resolvers/application_graphql_resolver.rb`
- Example resolver: `app/graphql_resolvers/campaign_graphql_resolver.rb`
- Example enum: `app/graphql_enums/campaign_status_graphql_enum.rb`

**Related Tags:**
- `3.2.0` - Initial enum implementation (broke frontends)
- `3.2.1` - Attempted fix with `coerce_input` (insufficient)

---

**Status:** READY FOR TASK CREATION

**Next Step:** Invoke `@agent-task-creator` to break down this plan into actionable tasks.
