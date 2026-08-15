# External doc/blog excerpts — Ruby Bundler support (Renovate) and Gemfile versioning policy

## Renovate `docs/usage/ruby.md`

Fetched verbatim via curl, 2026-08-14, from
raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/ruby.md (full file, 29 lines):

```
## Warnings

When using `"rangeStrategy": "update-lockfile"`, all gems listed in the `Gemfile` will be updated, even if they do not have a version specified.

When using other `rangeStrategy` options, Renovate doesn't update dependencies without a version constraint.
Example: `gem 'some-gem', '~> 1.2.3'` will update `some-gem` if a new version matching the constraint is available, but `gem 'some-gem'` won't.
If you always want to have the latest available version, consider specifying `gem 'some-gem', '> 0'`.
```

Note: the `gem 'some-gem', '> 0'` tip is an alternative to setting `rangeStrategy: update-lockfile`
at all — it turns an unconstrained gem into a (trivially) constrained one with an unbounded
floor, so the DEFAULT `rangeStrategy` (not `update-lockfile`) can update it. This requires
editing every currently-unconstrained Gemfile line and is a different trade-off entirely from
the manager-wide `update-lockfile` approach; it is not evaluated further in this spike because
it reintroduces exactly the manual-editing cost the engineer's framing rejects.

## Renovate `docs/usage/dependency-pinning.md` ("Should you Pin your JavaScript Dependencies?")

Fetched verbatim via curl, 2026-08-14. Full doc argues FOR pinning (opposite of the engineer's
team's chosen default), and its own recommendation section states:

> We recommend:
> 1. Any apps (web or Node.js) that aren't `require()`'d by other packages should pin all types of dependencies for greatest reliability/predictability
> ...
> 4. Use a lock file

This is Renovate's own documented philosophy, JS/npm-scoped by title but stated as general
guidance. It is the opposite default from the "unconstrained unless proven broken" policy
the engineer's team runs. Cited here as a trade-off data point, not as a refutation — the
doc itself frames pinning-vs-ranges as "It's your choice."

## Blog: "Your Rails and Ruby Versioning and Gemfile Policy" — David Bryant Copeland,
## naildrivin5.com, published 2022-11-17

URL: https://naildrivin5.com/blog/2022/11/17/your-rails-and-ruby-versioning-and-gemfile-policy.html

Fetched via WebFetch (AI-summarized; GitHub raw-endpoint style verbatim fetch is not
available for this blog, so confidence is lower than the raw.githubusercontent.com and
GraphQL API sources above). Self-checked by re-fetching and re-confirming the same
substring is present both times.

Quoted (per two independent fetches, consistent both times):

> "No other gems should have a version specifier unless the latest version is incompatible with your app in some way."

> "If the latest version of any gem is not compatible with your app or another dependency, pin the version of the gem in your `Gemfile` (using the pessimistic operator if possible) and add a comment"

> "Your `Gemfile` should specify the version of Rails using the pessimistic operator and the lowest version of Rails required by your app in `MAJOR.MINOR.PATCH` form"

> "If you use a tool like Dependabot, that can manage the general updates for you, but it won't create a forcing-function around checking that pinned dependencies can be unpinned."

This is a named, dated, independent community source describing almost exactly the policy
the engineer's team runs: unconstrained by default, pin only on proven incompatibility, with
a comment explaining why. It mentions Dependabot (not Renovate) and does not discuss
`rangeStrategy` composition at all — its concern is a different one (does the bot create a
"forcing function" to revisit a pin later), not how to configure the bot's range-update
behavior for the hybrid shape.
