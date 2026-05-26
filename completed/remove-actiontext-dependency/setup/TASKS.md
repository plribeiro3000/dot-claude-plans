# Tasks: Remove ActionText from setup

## Prerequisites
- [ ] Ensure develop branch is up to date
- [ ] Create feature branch: `feature/remove-actiontext-dependency`

## Implementation

### 1. Update Gemfile
- [ ] Open `Gemfile`
- [ ] Replace `gem 'rails', '~> 8.0.3'` with individual components:
  ```ruby
  # Rails components (individually to avoid unused dependencies like actiontext)
  gem 'railties', '~> 8.0.3'
  gem 'activemodel', '~> 8.0.3'
  gem 'activerecord', '~> 8.0.3'
  gem 'actionpack', '~> 8.0.3'
  gem 'actionview', '~> 8.0.3'
  gem 'activesupport', '~> 8.0.3'
  # Note: No actionmailer - API only
  ```

### 2. Update dependencies
- [ ] Run `bundle install`
- [ ] Verify `Gemfile.lock` no longer contains `actiontext` or `action_text-trix`

### 3. Verification
- [ ] Run `bin/rails runner "puts 'Rails OK'"` to verify boot
- [ ] Run test suite: `bundle exec rspec`
- [ ] Run linter: `bundle exec rubocop`

### 4. Changelog
- [ ] Update `CHANGELOG.md` with entry under "Changed" section:
  ```
  - Optimized Rails dependencies to load only required components
  ```

## Completion Criteria
- Application boots without errors
- All tests pass
- ActionText gems not present in Gemfile.lock
