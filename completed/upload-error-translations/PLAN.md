# Feature: Upload Error Translations

**Status:** ✅ COMPLETED

## Overview

Ensure all validation error messages produced by document processors (CSV uploads) are translated in the frontend across 3 languages (pt-BR, en, es).

## Scope

**Type**: Multi-project (Backend + Frontend)

**Projects Affected**:
- `app` (Backend - Rails) - Validations and error messages
- `app-webclient` (Frontend - Angular) - Translations

---

## Analysis Summary

### Total Keys
- **163 error keys** identified
- **Final coverage**: 163/163 (100%) across all 3 languages

### Backend Translation Sources

1. **Generic Rails Messages** (`config/locales/{locale}/gems/rails.yml`)
   - Default messages: blank, invalid, taken, too_short, too_long, etc.
   - Available in: pt-BR, en, es

2. **Model-Specific Messages** (`config/locales/{locale}/models/*.yml`)
   - Custom messages per model
   - Some only have pt-BR (pending addition of en, es on the backend)

---

## Document Processors

| Processor | Resource | Key Error Categories |
|-----------|----------|---------------------|
| UserDocument | User | password, identifiers, seat, base, id.anonymous |
| ClientDocument | Client | external_id, name |
| ProductDocument | Product | external_id, name |
| DealDocument | Deal | date, external_id, quantity, sold_price, work_hours, fields, deal_collaboration_id |
| GroupDocument | Groupification | group_id, starts_at, ends_at, user_id (already_active, never_active, already_inactive) |
| GoalDocument | Goal | baseline (bigger_than_value, smaller_than_value), direction, ends_at, group_id.in_use, starts_at, type, user_id.in_use |
| VariableDocument | Variable | calculation, data_type, default, frequency, key (invalid_key), name, type |
| IndicatorDocument | Indicator | compiled_at, user_id, value, variable_id (internal_variable) |
| IncentiveDocument | Incentive | commission_type, name, rules, type |
| PasswordDocument | PasswordReset | user_id, password (requirements) |
| AcceptmentDocument | Acceptment | signature, from, user_id, plan_statement_id, statement_id |
| CollaborativeDealDocument | CollaborativeDeal | collaborations, type, collaborations.user_id, collaborations.value |

---

## Implementation Status

### Completed (Frontend)

All 163 keys implemented across the 3 languages:

| Resource | Keys Added |
|----------|------------|
| document | invalid_encoding |
| user | password.too_long, password.confirmation, password.requirements, identifiers.too_short, identifiers.value.is_primary, identifiers.value.already_primary, seat.blank, base.invalid, id.anonymous |
| client | name.blank |
| product | external_id.blank, name.blank |
| deal | work_hours.greater_than, deal_collaboration_id.is_collaborative_deal, fields.value.invalid, fields.value.blank, originated_at.before_or_equal_to |
| groupification | starts_at.date_after, ends_at.after, ends_at.blank, user_id.never_active (+ fixed typo "errors " → "errors") |
| goal | baseline.blank, baseline.bigger_than_value, baseline.smaller_than_value, direction.blank, ends_at.after, group_id.in_use, starts_at.before, type.blank, user_id.in_use |
| variable | key.invalid |
| indicator | variable_id.invalid |
| incentive | rules.blank |
| password_reset | password.blank, password.too_short, password.too_long, password.requirements, user_id.blank |
| acceptment | signature.blank, from.blank, from.invalid, user_id.blank, statement_id.invalid |
| collaborative_deal | **NEW SECTION** - collaborations.blank, type.blank, type.inclusion, collaborations.user_id.blank, collaborations.value.not_a_number, collaborations.value.invalid |

### Bug Fixes Applied
- Fixed `"errors "` typo (trailing space) in groupification section (pt-BR, es)
- Fixed `"carracteres"` → `"caracteres"` typo in password.too_short (pt-BR)
- Fixed `"too short"` → `"too_short"` key format (en)
- Fixed `"internal variable"` → `"internal_variable"` key format (en)

### Completed (Backend)

All model-specific messages now have translations in all locales (pt-BR, en, es):
- ✅ User.password.requirements
- ✅ User.id.anonymous
- ✅ Deal.deal_collaboration_id.is_collaborative_deal
- ✅ Goal.baseline.bigger_than_value/smaller_than_value
- ✅ Goal.group_id.in_use / user_id.in_use
- ✅ Groupification.user_id.already_active/already_inactive/never_active

---

## Unique Error Keys Reference

```
after                    in_use
already_active           inclusion
already_inactive         internal_variable
already_primary          invalid
anonymous                invalid_encoding
before                   invalid_file
before_or_equal_to       invalid_file_content
bigger_than_value        invalid_key
blank                    invalid_opening
confirmation             is_collaborative_deal
date_after               is_primary
date_after_or_equal_to   never_active
greater_than             not_a_number
                         requirements
                         smaller_than_value
                         taken
                         too_long
                         too_short
```

---

## Translation Key Structure

```json
{
  "resource_name": {
    "errors": {
      "attribute": {
        "error_key": "Translated message with {{ interpolation }}"
      }
    }
  }
}
```

Example:
```json
{
  "goal": {
    "errors": {
      "baseline": {
        "blank": "Valor base não pode ficar em branco",
        "bigger_than_value": "Valor base é maior que a meta",
        "invalid_opening": "Valor base não deve ser igual a {{ constraint }}"
      }
    }
  }
}
```

---

## Related Files

### Backend (app)
- `config/locales/{locale}/gems/rails.yml` - Generic messages
- `config/locales/{locale}/models/*.yml` - Model-specific messages
- `app/models/*.rb` - Model validations
- `app/sidekiq/*_document_processor.rb` - Document processors

### Frontend (app-webclient)
- `src/translations/pt-BR.json`
- `src/translations/en.json`
- `src/translations/es.json`
