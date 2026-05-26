# Plan: Remove ActionText Dependency

## Overview

Remove the unused `actiontext` gem (and its dependency `action_text-trix`) from three Rails repositories that don't use rich text functionality.

## Problem Statement

The `rails` meta-gem automatically includes `actiontext` as a dependency. Even though:
- None of the repositories use `has_rich_text` or any ActionText features
- The `config/application.rb` files don't require `action_text/railtie`

The gem is still installed and present in `Gemfile.lock`, adding unnecessary dependencies.

## Affected Repositories

| Repository | Rails Version | Current State |
|------------|---------------|---------------|
| app | 8.1.1 | Uses `gem 'rails'` meta-gem |
| integrator | 8.0.4 | Uses `gem 'rails'` meta-gem |
| setup | 8.0.3 | Uses `gem 'rails'` meta-gem |

## Analysis Summary

### app (Rails 8.1.1)

**Components in use (from `config/application.rb`):**
- `active_model/railtie`
- `active_record/railtie`
- `action_controller/railtie`
- `action_view/railtie`
- `action_mailer/railtie`
- `propshaft`

**Not using:**
- ActionText (no `has_rich_text` in models)
- ActiveStorage (no `has_one_attached` / `has_many_attached`)
- ActionCable (no `app/channels` directory)
- ActionMailbox (no inbound email routing)
- ActiveJob (uses Sidekiq directly via `ApplicationWorker`)

### integrator (Rails 8.0.4)

**Components in use (from `config/application.rb`):**
- `active_model/railtie`
- `action_controller/railtie`
- `action_mailer/railtie`
- `action_view/railtie`

**Not using:**
- ActiveRecord (uses Mongoid)
- ActionText
- ActiveStorage
- ActionCable
- ActionMailbox
- ActiveJob (uses Sidekiq directly)

### setup (Rails 8.0.3)

**Components in use (from `config/application.rb`):**
- `active_model/railtie`
- `active_record/railtie`
- `action_controller/railtie`
- `action_view/railtie`

**Not using:**
- ActionMailer
- ActionText
- ActiveStorage
- ActionCable
- ActionMailbox
- ActiveJob

## Decision (2026-03-30)

**Keep the `gem 'rails'` meta-gem** in all three repositories. Do not replace it with individual component gems.

### Rationale

1. **Runtime risk is zero** — all three repositories already use selective requires in `config/application.rb` (individual railties instead of `require 'rails/all'`). ActionText is never loaded.
2. **Supply chain risk is already mitigated** — dependency auditing is in place.
3. **Upgrade complexity not worth it** — replacing the meta-gem with 6-7 individual gems in 3 repositories makes every Rails upgrade more tedious for a marginal security benefit.
4. **Community standard** — most Rails applications keep the meta-gem and control loaded components via `application.rb`, which is what we already do.

## Solution

Keep using `gem 'rails'` in all three repositories and continue controlling which components are loaded via `config/application.rb`. The unused components (ActionText, ActiveStorage, ActionCable, ActionMailbox, ActiveJob) remain installed but never loaded.

No code changes needed.

## Verification Checklist

For each repository:
- [x] `config/application.rb` uses individual requires (not `rails/all`)
- [x] ActionText railtie is NOT required
- [x] ActiveStorage railtie is NOT required
- [x] ActionCable railtie is NOT required
- [x] ActionMailbox railtie is NOT required

## Notes

- This is a low-risk situation since the functionality isn't being loaded at runtime
- If Rails provides a way to exclude sub-dependencies from the meta-gem in the future, revisit this decision
- Future Rails upgrades remain simple: update one gem version
