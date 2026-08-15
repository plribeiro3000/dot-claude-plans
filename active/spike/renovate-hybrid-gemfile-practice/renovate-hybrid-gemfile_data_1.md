# Raw Gemfiles fetched verbatim (via curl to raw.githubusercontent.com), 2026-08-14

Fetched to determine whether each of the three repositories examined by the prior spike
(`renovate-mixed-constraint-rangestrategy/SPIKE.md`, Finding 6) is genuinely a HYBRID
Gemfile (mix of constrained and unconstrained gems) or uniformly unconstrained.

## Source 1: getlago/lago-api

URL: https://raw.githubusercontent.com/getlago/lago-api/main/Gemfile

Full file, 181 lines. Verdict: **HYBRID.** Majority of gems unconstrained (`gem "aasm"`,
`gem "sidekiq"`, `gem "redis"`, etc.). A documented minority carries a constraint, and three
of those constraints carry an explicit "known-bad-version" comment matching the engineer's
framing exactly:

```
Line 11: gem "redlock", "~> 2.0.6" # Used through `activejob-uniqueness`. It's pinned to 2.0.x because we patched the library to fix a bug.
Line 16: gem "puma", "~> 7.2"
Line 17: gem "rails", "~> 8.0"
Line 27: gem "sidekiq-throttled", "1.4.0" # '1.5.0' was losing some jobs
Line 35: gem "googleauth", "~> 1.16.2"
Line 42: gem "clickhouse-activerecord", "~> 1.6.1"
Line 43: gem "discard", "~> 1.2"
Line 52: gem "connection_pool", "<3" # Temporary fix. See https://github.com/mperham/connection_pool/issues/212
Line 67: gem "gocardless_pro", "~> 2.34"
Line 111: gem "karafka", "~> 2.5.0"
Line 112: gem "karafka-web", "~> 0.11.3"
Line 118: gem "csv", "~> 3.0"
Line 138: gem "knapsack_pro", "~> 9.0"
Line 139: gem "parallel_tests", "~> 5.3"
Line 155: gem "vernier", "~> 1.10"
Line 156: gem "super_diff", "~> 0.18.0"
Line 164: gem "rspec-snapshot", "~> 2.0"
Line 165: gem "htmlbeautifier", "~> 1.4"
```

## Source 2: catatsuy/private-isu

URL: https://raw.githubusercontent.com/catatsuy/private-isu/master/webapp/ruby/Gemfile

Full file, 15 lines (this is the ONLY Gemfile in the repository — confirmed via
`gh search code "filename:Gemfile" --repo catatsuy/private-isu`, which returned only
`webapp/ruby/Gemfile` and its `.lock`; `portal/Gemfile.org` is a differently-named
non-Gemfile file, not picked up by Bundler/Renovate's bundler manager).

```ruby
# A sample Gemfile
source "https://rubygems.org"

gem "sinatra"
gem "sinatra-contrib"
gem "rack"
# The released unicorn gem has not been updated for Ruby 4 yet, so use the
# unreleased git revision until a compatible gem is published.
gem "unicorn", git: "https://github.com/defunkt/unicorn.git", ref: "e9862718a7e98d3cbec74fc92ffc17a1023e18da"
gem 'bigdecimal'
gem "mysql2"
gem "rack-flash3"
gem 'connection_pool'
gem "dalli"
```

Verdict: **NOT hybrid.** Every gem is declared with no version constraint. `unicorn` is
pinned to a git `ref:`, which is a different extraction mechanism (git-refs datasource, not
a Gemfile version-range `currentValue`) — Renovate's `matchCurrentValue`/`CurrentValueMatcher`
does not see a git-ref pin the same way it sees `"~> 1.2.3"`. This repository is NOT evidence
of the constrained/unconstrained hybrid scenario.

## Source 3: geeksforsocialchange/PlaceCal

URL: https://raw.githubusercontent.com/geeksforsocialchange/PlaceCal/main/Gemfile

Full file, 121 lines. Verdict: **HYBRID.** Majority unconstrained (`gem 'kamal'`,
`gem 'pg'`, `gem 'puma'`, `gem 'dartsass-rails'`, etc.). A documented minority carries a
constraint:

```
Line 10: gem 'rails', '~> 8.0'             # Web framework
Line 37: gem 'phlex-rails', '~> 2.3'       # Ruby-native view components
Line 78: gem 'brakeman', '~> 8.0'        # Static security analysis
Line 85: gem 'lookbook', '>= 2.3.14'    # Component preview UI (Storybook for Rails)
Line 89: gem 'rubocop', '1.88.2', require: false
Line 90: gem 'rubocop-graphql', '1.7.0', require: false
Line 91: gem 'rubocop-performance', '1.26.1', require: false
Line 92: gem 'rubocop-rails', '2.36.0', require: false
Line 103: gem 'axe-core-rspec', '~> 4.8'  # Accessibility testing
Line 111: gem 'pundit-matchers', '~> 4.0' # Policy spec matchers
Line 112: gem 'rspec-rails', '~> 8.0'     # Test framework
Line 114: gem 'shoulda-matchers', '~> 8.0' # Model/controller matchers
```

## Summary

| Repository | Hybrid? | Evidence for the engineer's exact scenario (unconstrained default + documented pin-on-breakage) |
|---|---|---|
| getlago/lago-api | YES | Strong — 3 gems carry an inline comment naming the specific breakage reason |
| catatsuy/private-isu | NO | None — uniformly unconstrained; retracts this repo from Finding 6's framing |
| geeksforsocialchange/PlaceCal | YES | Partial — constrained gems present, but comments describe what the gem does, not why it is pinned |
