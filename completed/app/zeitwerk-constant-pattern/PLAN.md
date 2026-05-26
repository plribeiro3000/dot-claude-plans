# PLAN - Zeitwerk-Friendly Constant Pattern Standardization

> **Status:** ABANDONED
> **Decision Date:** 2025-01-30
> **Reason:** After research, the current pattern (nested style) is the recommended best practice

---

## Original Objective

Standardize constant definition patterns across the backend codebase by converting class reopening patterns to explicit namespace syntax (compact style).

**Original suggestion:** Change from nested style to compact style:

```ruby
# Current (nested style)
class DealDocument < Document
  class Row < ApplicationRecord
  end
end

# Proposed (compact style)
class DealDocument::Row < ApplicationRecord
end
```

---

## Analysis Result

### The Two Styles Are NOT Equivalent

The difference is in **constant lookup** via `Module.nesting`:

| Style | Module.nesting | Constant Search Path |
|-------|----------------|---------------------|
| Nested | `[Parent::Child, Parent]` | Child → Parent → Top-level |
| Compact | `[Parent::Child]` | Child → Top-level (skips Parent!) |

### When Compact Style Breaks

```ruby
module API
  RATE_LIMIT = 1000
end

# NESTED - works
module API
  class Controller
    def limit
      RATE_LIMIT  # ✅ Finds API::RATE_LIMIT
    end
  end
end

# COMPACT - breaks
class API::Controller
  def limit
    RATE_LIMIT  # ❌ NameError: uninitialized constant
  end
end
```

### Community Recommendation: NESTED Style

| Source | Recommendation |
|--------|----------------|
| **RuboCop** (default) | `nested` style |
| **Thoughtbot** | "stick with nesting to avoid gotchas entirely" |
| **Alchemists.io** | Compact/flat listed as **antipattern** |
| **Randy Coulman** | "namespaced classes always be defined using the standard [nested] method" |

---

## Decision: Keep Current Pattern

The current code follows Ruby community best practices:

1. **Nested style is the RuboCop default** - The linter recommends it
2. **Safer constant lookup** - `Module.nesting` includes all levels
3. **No pre-definition required** - Parent doesn't need to exist first
4. **Future-proof** - If constants are added to parent, child classes find them automatically
5. **Open/Closed Principle alignment** - Reopening class to add nested classes is valid; we're not modifying the original class, we're adding new responsibilities in a well-defined scope

### Current Pattern Benefits

```ruby
class DealDocument < Document
  class Row < ApplicationRecord
    # Can access any constant defined in DealDocument
    # Can access any constant defined in Document
    # Full lexical scope preserved
  end
end
```

### Why NOT to Change

- Compact style can cause `NameError` if child references parent constants
- RuboCop marks compact→nested autocorrection as "unsafe"
- The "problem" (reopening class) is actually the **recommended pattern**
- Change would go AGAINST community best practices

---

## References

### Documentation
- [RuboCop Style/ClassAndModuleChildren](https://www.rubydoc.info/gems/rubocop/RuboCop/Cop/Style/ClassAndModuleChildren) - Default is `nested`
- [Ruby modules_and_classes Documentation](https://docs.ruby-lang.org/en/2.1.0/syntax/modules_and_classes_rdoc.html)

### Best Practices Articles
- [Why you should nest modules in Ruby - Thoughtbot](https://thoughtbot.com/blog/why-you-should-nest-modules-in-ruby)
- [Ruby Antipatterns - Alchemists.io](https://alchemists.io/articles/ruby_antipatterns) - Flat modules as antipattern
- [Namespaced Classes in Rails - Randy Coulman](https://randycoulman.com/blog/2014/12/09/namespaced-classes-in-rails/)

### Technical Deep Dives
- [Everything you ever wanted to know about constant lookup in Ruby](https://cirw.in/blog/constant-lookup.html)
- [How You Nest Modules Matters in Ruby - theScore Tech Blog](https://techblog.thescore.com/2014/05/28/how-you-nest-modules-matters-in-ruby/)
- [Avoid these traps when nesting Ruby modules - Honeybadger](https://www.honeybadger.io/blog/avoid-these-traps-when-nesting-ruby-modules/)
- [Compact vs Nested class definition in Ruby - GoGrow](https://www.gogrow.dev/blog/compact-vs-nested-class-definition-in-ruby-whats-the-difference)
- [Ruby's Constant System and Autoloading - Better Stack](https://betterstack.com/community/guides/scaling-ruby/constant-system-autoloading/)

---

## Files Analyzed (No Changes Needed)

**12 files were identified, all correctly using nested style:**

1. `app/models/calendar_audit/row.rb`
2. `app/models/monthly_usage_audit/row.rb`
3. `app/models/plan_goal_audit/row.rb`
4. `app/models/plan_statement_audit/row.rb`
5. `app/models/responsible_audit/row.rb`
6. `app/models/user_audit/row.rb`
7. `app/models/user_identifier_audit/row.rb`
8. `app/models/deal_document/row.rb`
9. `app/models/group_document/row.rb`
10. `app/models/indicator_document/row.rb`
11. `app/models/authenticator_configuration/azure_identity_provider.rb`
12. `app/models/incentive_item/option.rb`

**Conclusion:** All files follow the recommended pattern. No action required.
