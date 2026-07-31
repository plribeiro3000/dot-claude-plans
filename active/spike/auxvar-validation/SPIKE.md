# SPIKE — Model and validation micro-steps for auxiliary (output) variables (BE-3, BE-4, BE-5)

> Language classification: internal engineering doc → English (`LANGUAGE-POLICY.md`, category 1).
> Repository: `~/Projects/4Shark/app`, branch `develop`.
> Read in full before this spike: `~/Projects/4Shark/dot-claude-plans/active/app/auxiliary-variables/PLAN.md`
> and `TASKS.md`.

## Investigation question

Validate, step by step, the model-and-validation work of BE-3 (registering output variables on
the incentive), BE-4 (extending the rule syntax validators so a rule can name an auxiliary
variable), and BE-5 (plan-level validation with stage order) — against the real Dentaku 3.5.7
gem source (not just its README), the current `app` codebase (re-verified today, 2026-07-30, the
same day release 3.60.0 shipped and shifted several of the cited files), and Rails 8.1.3.1's
actual validation-callback semantics — so the three tasks can be broken into implementable
micro-steps with a size signal, and any contradiction between `TASKS.md`/`PLAN.md` and the real
sources is named explicitly.

## Sources consulted

- `/Users/plribeiro3000/.rvm/gems/ruby-4.0.6@four_shark/gems/dentaku-3.5.7/lib/dentaku.rb` — the
  `Dentaku!`/`Dentaku.evaluate!` entry point `Rule#calculate!` goes through.
- `.../dentaku-3.5.7/lib/dentaku/calculator.rb` — `Calculator#evaluate!`, `Calculator#ast`; the
  separation of parse from binding-check.
- `.../dentaku-3.5.7/lib/dentaku/exceptions.rb` — the full exception hierarchy, confirming
  `UnboundVariableError < Error`.
- `.../dentaku-3.5.7/lib/dentaku/parser.rb` — `Parser#process_token`, `Parser#handle_function`;
  confirms an identifier is never checked against a binding at parse time, while a function name
  IS checked (`:undefined_function`).
- `.../dentaku-3.5.7/lib/dentaku/ast/identifier.rb` — the whole class; `Identifier#dependencies`
  is the single method that decides "unbound".
- `.../dentaku-3.5.7/lib/dentaku/tokenizer.rb` — `Tokenizer#tokenize`, `#strip_comments`.
- `.../dentaku-3.5.7/lib/dentaku/token_scanner.rb` — scanner registration order and the
  `:function` vs `:identifier` regexes.
- See auxiliary: `auxvar-validation_dentaku_1.rb` — consolidated excerpts of the six gem files
  above, assembled together because the spike's central claim depends on reading all of them in
  sequence.
- `https://github.com/rubysolo/dentaku/blob/main/README.md` — the documented `Calculator#dependencies`
  public API and the `evaluate` vs `evaluate!` contract.
- `https://github.com/rubysolo/dentaku/issues/236` — community confirmation that Dentaku has no
  per-expression opt-out of `UnboundVariableError`; the only lever is bang vs non-bang.
- `~/Projects/4Shark/app/app/models/rule.rb` — read in full; every line number in `TASKS.md`'s
  BE-4 re-verified directly against this file.
- See auxiliary: `auxvar-validation_rule_1.rb` — full verbatim copy of `rule.rb` at the state read
  for this spike, kept because the file has already shifted twice during this feature's planning.
- `~/Projects/4Shark/app/app/models/formula.rb` — read in full; `referenced_identifiers` and
  `error`.
- `~/Projects/4Shark/app/app/models/incentive.rb` — read in full; `update_variables`, the ranking
  `find_or_create_by` hazard.
- `~/Projects/4Shark/app/app/models/incentive_variable.rb` — read in full.
- `~/Projects/4Shark/app/app/models/plan.rb` — read in full; `redemption_incentive_requirements`,
  `incentive_ids`, custom validation declarations.
- `~/Projects/4Shark/app/app/models/variable.rb` — read in full; `TYPES`, `key_regex`, the
  indicator-only validations.
- `~/Projects/4Shark/app/app/models/easy_variable.rb` — read in full (8 lines).
- `~/Projects/4Shark/app/app/data_types/application_data_type.rb` (lines 4-9) — `DEAL_TYPES`,
  `INDICATOR_TYPES`, `EASY_TYPES`.
- `~/Projects/4Shark/app/app/graphql_types/plan_variable_input_graphql_type.rb` — read in full (5
  lines).
- `~/Projects/4Shark/app/app/workers/plan_document/consumer.rb` (lines 200-215) — the
  `incentivations.` prefix skip.
- `~/Projects/4Shark/app/app/workers/{deal,indicator,ranking,limiter,redemption}_incentive/finalizer.rb`
  — the `perform_async` line of each, to independently corroborate the enqueue chain order.
- `~/Projects/4Shark/app/Gemfile.lock` — confirms `dentaku (3.5.7)` (line 180) and `rails
  (8.1.3.1)` (line 507).
- `/Users/plribeiro3000/.rvm/gems/ruby-4.0.6@four_shark/gems/activemodel-8.1.3.1/lib/active_model/validations.rb`
  — the `validate` class method and its documented halting behavior.
- `/Users/plribeiro3000/.rvm/gems/ruby-4.0.6@four_shark/gems/activerecord-8.1.3.1/lib/active_record/nested_attributes.rb`
  and `autosave_association.rb` — nested-attributes assignment timing.

## Findings

### Finding 1: An unknown variable key parses cleanly and fails only at evaluation — confirmed against the gem source, not just the plan's assertion

**Evidence:**

```ruby
# dentaku-3.5.7/lib/dentaku/calculator.rb:67-82
def evaluate!(expression, data = {}, &block)
  context = evaluation_context(data, :strict)
  return evaluate_array!(expression, context, &block) if expression.is_a? Array

  store(context) do
    node = ast(expression)                       # tokenize + parse only
    unbound = node.dependencies(memory)           # binding check, separate step

    unless unbound.empty?
      raise UnboundVariableError.new(unbound),
            "no value provided for variables: #{unbound.uniq.join(', ')}"
    end

    node.value(memory)
  end
end
```

```ruby
# dentaku-3.5.7/lib/dentaku/parser.rb:118-130
def process_token(token, lookahead, index)
  case token.category
  ...
  when :identifier    then output << AST::Identifier.new(token, case_sensitive: case_sensitive)
  ...
  when :function
    handle_function(token)
  ...
```

An identifier token is wrapped into an `AST::Identifier` node unconditionally — no lookup against
any options hash happens at this point. Contrast `handle_function` (`parser.rb:154-159`), which
DOES raise a `ParseError` (`:undefined_function`) immediately when the function name is not
registered. This is the one case where an unknown *name* is caught during parsing; a variable
identifier is not checked until `Calculator#evaluate!` calls `node.dependencies(memory)`
(`ast/identifier.rb:33-35`): `context.key?(identifier) ? dependencies_of(...) : [identifier]` —
returning itself as "unbound" only if the context lacks the key.

**Source:** `dentaku-3.5.7/lib/dentaku/calculator.rb:67-82`, `parser.rb:118-159`,
`ast/identifier.rb:33-35`. See auxiliary `auxvar-validation_dentaku_1.rb` for the assembled
excerpts.

**Significance:** `PLAN.md:168` states *"An unknown variable key parses and tokenizes cleanly; it
fails at evaluation."* — this is now confirmed against the gem's own source, not asserted from
its README. This is the load-bearing fact behind BE-4: the reason a rule referencing an auxiliary
key fails today is *only* that the synthetic options hash used at validation time (`rule.rb`'s
`*_options` builders) does not contain the key — nothing in Dentaku's grammar rejects it.

### Finding 2: `UnboundVariableError` is caught by `Rule::PARSE_EXCEPTIONS` because it is a `Dentaku::Error` subclass

**Evidence:**

```ruby
# dentaku-3.5.7/lib/dentaku/exceptions.rb:1-12
class Error < StandardError
  attr_accessor :recipient_variable
end

class UnboundVariableError < Error
  attr_reader :unbound_variables
  def initialize(unbound_variables)
    @unbound_variables = unbound_variables
  end
end
```

```ruby
# app/models/rule.rb:9-10 (auxvar-validation_rule_1.rb)
PARSE_EXCEPTIONS =
  [Dentaku::Error, Dentaku::ZeroDivisionError, Dentaku::ArgumentError, NoMethodError, ArgumentError, NameError].freeze
```

**Source:** `dentaku-3.5.7/lib/dentaku/exceptions.rb:1-12`; `app/models/rule.rb:9-10`.

**Significance:** `PLAN.md:166` and `TASKS.md`'s BE-4 description both state this chain; it is
confirmed. `validate_syntax` (`rule.rb:177-185`) rescues `*PARSE_EXCEPTIONS`, so an
`UnboundVariableError` and a genuine grammar `ParseError` both collapse into the same
`errors.add(:value, :invalid)` with no distinction visible to the user — this is the "silent
about its cause" behavior `PLAN.md:138` names as the reason BE-4 exists.

### Finding 3: Release 3.60.0's new `formula.error` branch does not and cannot intercept the unbound-variable case — confirmed against `Formula#error`'s own rescue list

**Evidence:**

```ruby
# app/models/formula.rb:14-21
def error
  return @error if defined?(@error)

  Dentaku::Calculator.new.ast(text)
  @error = nil
rescue Dentaku::ParseError, Dentaku::TokenizerError => e
  @error = Error.new(e.reason, e.meta)
end
```

`Calculator#ast` (`calculator.rb:109-126`) only tokenizes and parses — it takes no options hash
and never calls `node.dependencies`. So it cannot raise `UnboundVariableError` (that exception is
only ever raised from `Calculator#evaluate!`, and separately from `AST::Identifier#value`, per
Finding 1). `Formula#error`'s rescue clause names exactly `Dentaku::ParseError,
Dentaku::TokenizerError` — it does not, and structurally cannot, catch `UnboundVariableError`.

**Source:** `app/models/formula.rb:14-21`; `dentaku-3.5.7/lib/dentaku/calculator.rb:109-126`.

**Significance:** `TASKS.md`'s BE-4 description states this outcome ("`formula.error` returns
`nil`, execution falls through to `calculate!`, and the bare `:invalid` is still what the user
sees") — confirmed as a structural certainty of the gem, not a probabilistic reading. This means
BE-4's fix genuinely has to touch the `*_options` builders; there is no smaller fix available
inside `Formula#error`'s existing rescue shape.

### Finding 4: `Formula#referenced_identifiers` is tokenizer-only and structurally cannot pick up function names — the `:function` scanner runs before `:identifier` and consumes the match first

**Evidence:**

```ruby
# app/models/formula.rb:10-12
def referenced_identifiers
  @referenced_identifiers ||= Dentaku::Tokenizer.new.tokenize(text).select { |token| token.is?(:identifier) }.map(&:value).uniq
end
```

```ruby
# dentaku-3.5.7/lib/dentaku/token_scanner.rb:35-57
def available_scanners
  [
    :null, :whitespace, :datetime, :numeric, :hexadecimal,
    :double_quoted_string, :single_quoted_string, :negate, :combinator,
    :operator, :grouping, :array, :access, :case_statement, :comparator,
    :boolean, :function, :identifier, :quoted_identifier
  ]
end

def function
  new(:function, '\w+!?\s*\(', lambda do |raw| ... end)
end

def identifier
  new(:identifier, '[[[:word:]]\.]+\b', lambda { |raw| standardize_case(raw.strip) })
end
```

`Tokenizer#tokenize` (`tokenizer.rb:24-33`) tries each scanner in `available_scanners` order per
position and stops at the first match (`TokenScanner.scanners(scanner_options).any? { ... }`). The
`:function` scanner's regex `\w+!?\s*\(` matches "word characters immediately followed by an
opening paren" and is tried before `:identifier`, so a call like `sum(x)` consumes `sum(` as a
`:function` token before `:identifier` ever gets a chance at that position. Consequently
`referenced_identifiers`'s `select { |token| token.is?(:identifier) }` filter is not doing
defensive work against function names — the tokenizer already routed them to a different
category.

**Source:** `app/models/formula.rb:10-12`; `dentaku-3.5.7/lib/dentaku/token_scanner.rb:35-57,
173-189`; `dentaku-3.5.7/lib/dentaku/tokenizer.rb:24-33`.

**Significance:** answers the engineer's question about whether identifier extraction is
"reliable for the formula shapes this codebase writes." It is reliable for excluding function
names by construction. Two edge cases are worth naming, both minor and neither contradicting
`TASKS.md`: (a) a variable key that is also a keyword the `boolean` or `case_statement` scanners
claim first — `true`, `false`, `case`, `end`, `then`, `when`, `else` — would never tokenize as
`:identifier`; `Variable#key`'s own format validation (`variable.rb:37`,
`format: { with: /\A[a-z]+[a-z0-9_]*\z/ }`) does not exclude these words, so a key literally named
`case` or `end` would silently fail to be "referenced" by this method. Not found in the codebase
today (this is a boundary case, not an observed bug). (b) The `identifier` regex
`[[[:word:]]\.]+\b` also matches dotted paths (`a.b`); `Variable#key`'s format never produces a
dot, so this is inert for 4Shark's actual keys.

### Finding 5: Comments are stripped identically for both `Formula#error` and `Formula#referenced_identifiers` — no divergence between the two call paths

**Evidence:**

```ruby
# dentaku-3.5.7/lib/dentaku/tokenizer.rb:66-68
def strip_comments(input)
  input.gsub(/\/\*[^*]*\*+(?:[^*\/][^*]*\*+)*\//, '')
end
```

`Tokenizer#tokenize` (`tokenizer.rb:16`) calls `strip_comments` unconditionally before scanning,
and both `Formula#error` (via `Dentaku::Calculator.new.ast(text)`, which tokenizes internally) and
`Formula#referenced_identifiers` (via a direct `Dentaku::Tokenizer.new.tokenize(text)` call) go
through the same `Tokenizer` class.

**Source:** `dentaku-3.5.7/lib/dentaku/tokenizer.rb:12-38, 66-68`.

**Significance:** rules out a possible discrepancy where a variable key mentioned only inside a
Dentaku-style `/* ... */` comment would be picked up by one method and not the other — it is
excluded from both consistently.

### Finding 6: the community's own documented API for "what does this formula reference" is `Calculator#dependencies`, a different, heavier mechanism than `Formula#referenced_identifiers`

**Evidence:** the Dentaku README (fetched) documents:

> "Pass a (string) expression to Dependencies and get back a list of variables (as `:symbols`) that are required for the expression."

with the example `calc.dependencies("annual_income / 5") #=> [:annual_income]`.

**Source:** `https://github.com/rubysolo/dentaku/blob/main/README.md` (fetched 2026-07-30).

**Significance:** `Calculator#dependencies` (`calculator.rb:96-107`) is context-aware and
recursive — it resolves through already-`store`d formulas in the calculator's memory
(`AST::Identifier#dependencies`, Finding 1, recurses into a bound `Node`). `Formula#referenced_identifiers`
does not use this API at all; it tokenizes the raw text directly with no context and no
recursion. This is the simpler, correct choice for the app's purpose (asking "which keys does
THIS one formula reference", with no evaluation context available at validation-authoring time),
and it means the two methods are not interchangeable — `referenced_identifiers` cannot be swapped
for `Calculator#dependencies` without also constructing a context, which the registration flow
(BE-3, `Incentive#update_variables`) does not have.

### Finding 7: Dentaku's own issue tracker confirms there is no per-expression opt-out of the strict/unbound behavior — the app's synthetic-options-hash approach is not working around a documented alternative

**Evidence:** GitHub issue #236, "A way to control unbound variable errors from expressions?" —
the reporter asks:

> "I wanted to start a discussion of how (or should) Dentaku have some way in expression to chose: an implicit strict behavior (the current one) in regards to unbound variable errors [or] explicit behavior where I can tell Dentaku: I understand there could be unbound variables here."

The issue carries no maintainer response and is not resolved.

**Source:** `https://github.com/rubysolo/dentaku/issues/236` (fetched 2026-07-30).

**Significance:** confirms the app's approach (build a synthetic options hash that covers every
variable key the company could legally reference, so `evaluate!` never hits an unbound key during
validation) is the only lever Dentaku exposes — there is no gem-level flag BE-4 could set
instead. This directly supports `PLAN.md`'s framing of the fix as extending the options hash, not
as a Dentaku configuration change.

### Finding 8 (decision recorded): BE-4's new builder follows `easy_variables_options`, NOT `indicator_variables_options` — `TASKS.md`'s cited pattern reference is superseded

**Evidence:**

```ruby
# app/models/rule.rb:213-219 — indicator_variables_options (TASKS.md's cited pattern reference)
def indicator_variables_options
  incentive.company.variables.indicators.enabled.each_with_object({}) do |variable, options|
    options["#{variable.key}_goal"] = rand(5000..10_000) # english variable
    options["meta_#{variable.key}"] = rand(5000..10_000) # portuguese variable
    options[variable.key] = rand(1..5_000)
  end
end
```

```ruby
# app/models/rule.rb:221-225 — easy_variables_options
def easy_variables_options
  incentive.company.variables.easy.enabled.to_h do |variable|
    [variable.key, rand(1..5_000)]
  end
end
```

```ruby
# app/models/easy_variable.rb — the whole file
class EasyVariable < Variable
  rescue_unique_constraint index: :index_variables_on_company_id_and_key, field: :key
  rescue_unique_constraint index: :index_variables_on_company_id_and_name, field: :name

  validates :data_type, inclusion: { in: ApplicationDataType::EASY_TYPES }
end
```

```ruby
# app/models/variable.rb:32,36,39
validates :calculation, presence: true, if: :indicator?
validates :frequency, presence: true, if: :indicator?
validates :override_calculation, presence: true, if: :indicator?
```

The two extra keys `indicator_variables_options` produces per variable (`#{key}_goal`,
`meta_#{key}`) exist because an `IndicatorVariable` carries goal-comparison semantics
(`calculation`, `frequency`, `override_calculation` — all `if: :indicator?`, `variable.rb:32,36,39`)
that formulas may reference by the goal/meta convention. `EasyVariable` carries none of those
validations (confirmed: the whole 8-line class has no `calculation`/`frequency`/
`override_calculation` declaration), and its options builder produces exactly one key per
variable, matching `deal_extra_fields_options`'s shape.

**Source:** `app/models/rule.rb:207-225`; `app/models/easy_variable.rb` (whole file);
`app/models/variable.rb:32,36,39`.

**Decision:** `PLAN.md:44` and `PLAN.md:368` state auxiliary variables reach `plan_variables`
"with goal binding suppressed for the type" and that "the type constrains `default` to zero" —
i.e., an auxiliary variable is designed to carry no goal/calculation semantics, the same shape as
`EasyVariable`. `AuxiliaryVariable` will therefore have no `calculation`, `frequency`, or
`override_calculation` validation (they are each `if: :indicator?`), the same as `EasyVariable`
today. On that basis, this is settled by 4Shark's own surrounding code — source 2 on the ladder in
`DECISION-AUTHORITY.md` — rather than left open: **BE-4's new `auxiliary_variables_options`
builder follows the `easy_variables_options` one-key-per-variable shape, binding exactly
`variable.key` with no `_goal`/`meta_` pair.** `TASKS.md`'s BE-4 "Pattern reference" section,
which names `indicator_variables_options` (`rule.rb:213-219`) as "the builder this one is modelled
on", is superseded by this finding — the two documents should not be read as agreeing on that
citation, and the blueprint should carry the correction forward so `TASKS.md` and this spike do
not silently disagree.

### Finding 9: Rails 8.1's own documentation states a custom `validate` callback cannot halt the chain — corroborates that BE-5's new validation is additive, never a short-circuit of the other four

**Evidence:**

```ruby
# activemodel-8.1.3.1/lib/active_model/validations.rb:135-136
# Note that the return value of validation methods is not relevant.
# It's not possible to halt the validate callback chain.
```

**Source:** `/Users/plribeiro3000/.rvm/gems/ruby-4.0.6@four_shark/gems/activemodel-8.1.3.1/lib/active_model/validations.rb:135-136`.

**Significance:** confirms that adding a fifth `validate :auxiliary_variable_requirements` next to
`Plan`'s existing four (`plan.rb:58-61`: `metric_rules`, `shared_conditions`,
`redemption_incentive_requirements`, `responsibility`) cannot be short-circuited by, and cannot
short-circuit, any of the other four — all run regardless of each other's outcome, and their
`errors.add` calls accumulate independently. This matters for BE-5's micro-steps: the new
validation can be developed and tested in isolation without needing to reason about validation
order relative to the other three.

### Finding 10: `accepts_nested_attributes_for` assigns children before `valid?` runs, so a plan-level validation reading the incentivations association sees current in-memory state, including `marked_for_destruction?` — confirmed from the gem, matching the exact distinction `TASKS.md` draws for BE-5

**Evidence:** `app/models/plan.rb:421-425`:

```ruby
def incentive_ids
  incentivations
    .reject(&:marked_for_destruction?)
    .map(&:incentive_id)
end
```

versus the sibling `redemption_incentive_requirements` (`plan.rb:389-398`), which at line 392
uses `incentivations.map(&:incentive_id)` with no `marked_for_destruction?` filter.

`accepts_nested_attributes_for :incentivations, allow_destroy: true` (`plan.rb:42`) generates an
`incentivations_attributes=` writer. This writer is invoked during attribute assignment
(`Plan.new(attrs)` / `plan.assign_attributes(attrs)`), which always happens before `valid?` is
called on the object — nested attributes are not a validation-time concern, they are an
assignment-time one. So by the time any `validate :method` runs, `incentivations` already
reflects every nested row the caller passed, including ones flagged `_destroy: true` (which
`AutosaveAssociation` marks via `mark_for_destruction`, not immediate removal from the in-memory
association array).

**Source:** `app/models/plan.rb:42, 389-398, 421-425`;
`activerecord-8.1.3.1/lib/active_record/nested_attributes.rb` (`assign_nested_attributes_for_collection_association`,
confirmed present at line 489); `activerecord-8.1.3.1/lib/active_record/autosave_association.rb`
(`marked_for_destruction?` at line 404).

**Significance:** confirms `TASKS.md`'s BE-5 criterion exactly: *"it reads `incentive_ids`
..., which rejects incentivations marked for destruction — the twin uses
`incentivations.map(&:incentive_id)` ... and does not."* This is not a subtle timing risk to
re-verify in a spec beyond what `TASKS.md` already asks for — the assignment-before-validation
ordering is a Rails guarantee, not a race.

### Finding 11: No existing precedent for an ordered pipeline constant anywhere in `app` — `CALCULATION_ORDER` would be the first of its kind

**Evidence:** `grep -rn "_ORDER = \[" app/app/` returns no matches anywhere in the repository.
`Incentive::TYPES` (`app/models/incentive.rb:15`) is declared
`%w[DealIncentive LimiterIncentive IndicatorIncentive RankingIncentive RedemptionIncentive]` — a
different order than the actual calculation sequence, and it carries no ordering semantics (it is
consumed only as a `validates :type, inclusion:` allow-list, `incentive.rb:50`).

**Source:** `grep -rn "_ORDER = \[" ~/Projects/4Shark/app/app/` (no output);
`app/models/incentive.rb:15, 50`.

**Significance:** confirms `PLAN.md:190`'s claim ("That order has no representation in code
today") as a negative finding, not an assumption. Not found: any STI-ordering precedent to copy
in this codebase. The web search for a general Ruby/Rails community convention on "STI subclass
ordering as an array constant" returned no on-point guidance either — the closest related
material (thoughtbot's STI article) addresses listing subclass *types*, not encoding a *processing
order* among them. This is recorded as "not found" rather than filled with a guess.

### Finding 12: the enqueue chain independently corroborates `CALCULATION_ORDER`'s claimed sequence

**Evidence:** each stage's `Finalizer#perform` enqueues the next stage's producer:

```
app/workers/deal_incentive/finalizer.rb:22       IndicatorIncentive::Producer...
app/workers/indicator_incentive/finalizer.rb:22  Ranking::Producer...
app/workers/ranking_incentive/finalizer.rb:22     UserCommission::LimiterOptionsProducer...
app/workers/limiter_incentive/finalizer.rb:22     RedemptionIncentive::Producer...
app/workers/redemption_incentive/finalizer.rb:16  Commission::MoneySanitizerProcessor...
```

**Source:** the five `finalizer.rb` files named above, each read directly.

**Significance:** independently corroborates `PLAN.md:190`'s stated order (Deal → Indicator →
Ranking → Limiter → Redemption) from the actual enqueue graph rather than from the plan's
assertion alone — this is exactly the sequence `BE-5`'s acceptance criterion "a spec asserting
`CALCULATION_ORDER` matches the observed enqueue chain" would need to encode.

### Finding 13: every `rule.rb` line number cited in `TASKS.md`'s BE-4 section is current as of this spike

**Evidence:** direct read of `app/models/rule.rb` (226 lines) on 2026-07-30 confirms: `PARSE_EXCEPTIONS`
at `9-10`; `formula_syntax` at `76`; `indicator_syntax` at `100`; `ranking_syntax` at `119`;
`limiter_syntax` at `145`; `redemption_syntax` at `166`; `validate_syntax` at `177-185`;
`metrics_options` at `187`; `deal_extra_fields_options` at `207`; `indicator_variables_options` at
`213`; `easy_variables_options` at `221`.

**Source:** `app/models/rule.rb` (read in full); preserved verbatim in
`auxvar-validation_rule_1.rb`.

**Significance:** `TASKS.md`'s own "Stale `rule.rb` line numbers" section (near its end) already
warns the file shifted twice and asks the implementer to re-verify before BE-4. This spike is that
re-verification, done once more on the same day release 3.60.0 shipped — no further drift found in
line numbers. The one correction this spike does carry against `TASKS.md`'s BE-4 section is the
pattern-reference citation itself (Finding 8), not a line-number drift.

## BE-3 — micro-steps (Register output variables on incentive save, carry into plan roll-up)

| # | Step | Code shape | What breaks at this step / why | How to verify | Size |
|---|---|---|---|---|---|
| 1 | Add `role` `enumerize` + presence validation on `IncentiveVariable` (depends on BE-1's migration existing) | `enumerize :role, in: { input: 0, output: 1 }, default: :input, scope: true` next to the two existing `validates :incentive_id, presence: true` / `validates :variable_id, presence: true` at `incentive_variable.rb:7-8` | Nothing yet — `IncentiveVariable.new` still defaults to `input`, matching every row written by the current `create(variable_id:)` calls | `spec/models/incentive_variable_spec.rb` (10 lines today) gains a role presence/enumerize one-liner | XS |
| 2 | `Incentive#update_variables` (`incentive.rb:149-175`) writes output rows alongside input rows | Inside each branch, after the existing `incentive_variables.create(variable_id: variable.id)` calls, add one pass over `rules.filter_map(&:output_variable_id).uniq.each { |id| incentive_variables.create(variable_id: id, role: :output) }` — a single additional loop, not per-branch duplication, since `rules` is already loaded for every incentive type | Nothing breaks — this is additive. The rebuild still opens with `incentive_variables.delete_all` (`:150`), so both input and output rows must be re-created every save; forgetting the output pass silently drops every output registration on the incentive's SECOND save onward (first save has nothing to lose yet) | A spec that creates an incentive with one rule bound to an output variable, saves twice, and asserts the output row survives both saves | S |
| 3 | Fix the ranking hazard at `incentive.rb:172` | Change `incentive_variables.find_or_create_by(variable_id: variable.id)` to `incentive_variables.find_or_create_by(variable_id: variable.id, role: :input)` | Without this, once role rows exist, a variable that is both a ranking-branch input AND some rule's output variable can be found by the bare `find_or_create_by(variable_id:)` — matching the OUTPUT row already created in step 2 — and the INPUT row is silently never created. This is the one `Rule::PARSE_EXCEPTIONS`-unrelated but registration-critical bug this task must not reintroduce | A spec: one variable that is a ranking input AND is the output_variable of a different rule on the SAME incentive; assert BOTH an `input` row and an `output` row exist after save | XS — one-line change, but the scenario needs its own test because M3's unique index (BE-1) is the only thing that would surface a regression here, and only at insert time |
| 4 | Confirm (not change) that an auxiliary variable reaches `plan_variables` via `Plan#create_variables`/`variable_ids` (`plan.rb:434-445`) | No code change — `variable_ids` (`plan.rb:438-445`) is `Incentive.joins(:incentive_variables).where(...).pluck('incentive_variables.variable_id').uniq`, unscoped by role, so an output-role row already flows through | Nothing to break; this step is a pinning spec, not a feature | A spec creating a plan whose only incentive_variable row for a variable is role `output`, asserting that variable appears in `plan_variables` after `create_variables` runs | XS |
| 5 | Confirm the auxiliary `plan_variable` row validates with a blank `goal_type` | No code change — `PlanVariable#goals_presence` (`plan_variable.rb:32-39`) opens `return if goal_type.blank?` | Nothing to break; pinning spec | A spec: `PlanVariable.new(variable_id: <auxiliary>, plan_id: ..., goal_type: nil).valid?` is true | XS |
| 6 | Note (do not fix) the pre-existing `delete_all` at `incentive.rb:150` | No change | Out of scope per `TASKS.md`'s own § "Two risks are deliberately not owned by any task" | Record as a follow-up in the PR, not a test | — |

**Size signal for BE-3 as a whole:** small-to-medium. Steps 1, 3, 4, 5 are each a one-to-a-few-line
change or a pinning spec; step 2 is the only step that adds real logic, and it is a single loop
appended once (not duplicated per incentive-type branch), because `rules` is already the same
loaded association in every branch of `update_variables`.

## BE-4 — micro-steps (Bind auxiliary keys in the `Rule` syntax validators)

**Decision recorded here, resolved by Finding 8 rather than left open:** the new builder
`auxiliary_variables_options` follows `easy_variables_options`'s one-key-per-variable shape, not
`indicator_variables_options`'s three-key shape. `TASKS.md`'s BE-4 "Pattern reference" citing
`indicator_variables_options` is superseded by this finding.

| # | Step | Code shape | What breaks at this step / why | How to verify | Size |
|---|---|---|---|---|---|
| 1 | Add `Variable.auxiliary` scope dependency (from BE-1) is available | No new code in `rule.rb` yet | N/A — prerequisite check only | N/A | — |
| 2 | Add a new private builder `auxiliary_variables_options` in `rule.rb`, alongside the other four `*_options` methods (`:187, :207, :213, :221`) | Per Finding 8 (decision recorded): `incentive.company.variables.auxiliary.enabled.to_h { |variable| [variable.key, rand(1..5_000)] }` — the `easy_variables_options` shape, one key per variable, no `_goal`/`meta_` pair | Nothing yet — an unreferenced private method changes no behavior | None yet (covered by step 3) | XS |
| 3 | Merge the new builder into exactly the three validators for the reading stages | `ranking_syntax` (`:119`), `limiter_syntax` (`:145`), `redemption_syntax` (`:166`) each already end their chain with `.merge(indicator_variables_options)` — append `.merge(auxiliary_variables_options)` after it, so an auxiliary key never shadows an indicator key sharing the same name (last-merge-wins; auxiliary and indicator variables share one per-company key namespace per `variable.rb:92-93`'s uniqueness, so a collision cannot occur in practice, but preserving merge order costs nothing) | Before this step, a rule in a ranking/limiter/redemption incentive referencing an auxiliary key still raises `UnboundVariableError` inside `calculate!` (`validate_syntax`, `:177-185`), caught by `PARSE_EXCEPTIONS`, surfacing as `errors.add(:value, :invalid)` with no distinguishing detail (Findings 1-3) | `spec/requests/graphql_mutations/graphql_controller_create_incentive_spec.rb`: create a ranking/limiter/redemption incentive whose rule formula is exactly an auxiliary variable's key; assert the mutation succeeds | S |
| 4 | Explicitly do NOT touch `indicator_syntax` (`:100`) or `formula_syntax` (`:76`) | No merge added to either | The indicator stage is a writer, not a reader (`PLAN.md:45`); adding the binding there would make a rule that should be rejected (an indicator rule referencing an auxiliary key, which the stage order forbids as a read) silently pass | A negative spec: an indicator-type rule referencing an auxiliary key still fails with `errors.add(:value, :invalid)` | XS |
| 5 | Negative-case spec: a rule referencing a genuinely unknown (non-existent) key still fails | No code change | Confirms the fix is additive, not an unconditional bind — without this, a typo'd key in a ranking rule would silently validate | `spec/models/rule_spec.rb` (60 lines today): a ranking rule whose formula references a key matching no variable at all still produces `errors.add(:value, :invalid)` | XS |
| 6 | Confirm runtime `calculate` (not `calculate!`) is unaffected | No code change — `calculate` (`:58-62`) already rescues `*PARSE_EXCEPTIONS` and returns `0` | Confirms a missing auxiliary VALUE at calculation time (as opposed to a missing auxiliary KEY at validation time) still yields `0`, not an error — this is existing, documented behavior (`PLAN.md:175`) that must not regress | A spec calling `rule.calculate({})` (no auxiliary value bound) on a rule referencing an auxiliary key returns `0.0` | XS |

**Size signal for BE-4 as a whole:** small. The entire fix is one new builder method plus three
one-line `.merge` insertions into existing chains; the bulk of the work is the four specs (steps
3-6), each independent and each a single scenario.

## BE-5 — micro-steps (Stage-order constant and plan-level exporter validation)

| # | Step | Code shape | What breaks at this step / why | How to verify | Size |
|---|---|---|---|---|---|
| 1 | Add `Incentive::CALCULATION_ORDER` | `CALCULATION_ORDER = %w[DealIncentive IndicatorIncentive RankingIncentive LimiterIncentive RedemptionIncentive].freeze`, placed near `TYPES` (`incentive.rb:15`) | Nothing yet — an unreferenced constant changes no behavior | A spec directly asserting this constant's value matches the five `finalizer.rb` enqueue targets read in Finding 12 (this is the sync mechanism `TASKS.md` calls out) | XS |
| 2 | Add `Plan#auxiliary_variable_requirements`, wired as a fifth `validate` | Modelled on `redemption_incentive_requirements` (`plan.rb:389-398`); uses `incentive_ids` (`plan.rb:421-425`, the `marked_for_destruction?`-aware one — NOT `incentivations.map(&:incentive_id)`), per Finding 10 | Before this step, a plan whose incentive reads an auxiliary variable with no earlier-stage exporter saves successfully and silently computes zero for that reader (Finding 1's runtime-`calculate` behavior means the missing value is invisible, not an error) | Five branch specs enumerated below | M |
| 3 | Branch: reader with no exporter at all | For every auxiliary variable an incentive's rules reference (via each reading incentive's rules' `Formula#referenced_identifiers`, filtered to keys that are auxiliary-variable keys), confirm at least one OTHER incentive in the plan, of a type whose `CALCULATION_ORDER` index is strictly less, has an `output`-role `incentive_variables` row for that variable | `errors.add(:incentivations, :missing_exporter)` (no dot — Finding-confirmed via `PlanDocument::Consumer:212`'s `start_with?('incentivations.')` skip) | Spec: a plan with only a ranking incentive reading an auxiliary variable, no other incentive; assert invalid | S |
| 4 | Branch: reader with an exporter in the SAME stage | Same-stage index equality does not satisfy "strictly earlier" | `errors.add` as above | Spec: two ranking incentives in the same plan, one exports, the other (also ranking) reads; assert invalid, because ranking cannot read what ranking writes in the same pass | XS |
| 5 | Branch: reader with an exporter in a LATER stage | Later index does not satisfy "strictly earlier" | `errors.add` as above | Spec: a redemption incentive exports, a ranking incentive (earlier stage) reads the same variable; assert invalid | XS |
| 6 | Branch: reader with an exporter in an EARLIER stage | Satisfies the rule | Plan is valid | Spec: an indicator incentive exports, a limiter incentive reads; assert valid | XS |
| 7 | Branch: two exporters into one variable | Not itself invalid under this validation (BE-6's summing semantics handle multiple writers) | No `errors.add` from THIS validation | Spec: two indicator incentives both export the same auxiliary variable, one limiter incentive reads it; assert valid (the sum semantics are BE-6's concern, not BE-5's) | XS |
| 8 | Bulk plan import surfaces the error | No code change needed — `PlanDocument::Consumer:212` only skips keys starting with `incentivations.`; a bare `:incentivations` key (no dot, per step 3's `errors.add`) is NOT skipped | Confirms the new validation's error is visible through the spreadsheet import path, not silently dropped like a dotted key would be | A request/worker spec against `PlanDocument::Consumer` with a plan missing an exporter; assert a `document_errors` row is created rather than the plan silently saving invalid | S |

**Size signal for BE-5 as a whole:** medium. The constant (step 1) and the validation method
itself (step 2) are each small, but five independent branch specs (steps 3-7) plus the import
surfacing spec (step 8) make this the largest of the three tasks in test surface, matching
`TASKS.md`'s own framing of BE-5 as needing "all five" validation branches covered.

## Trade-offs surfaced

The BE-4 builder question in this section is a decision, not a fork — see Finding 8. The
trade-offs below are kept as the rationale for that decision, not as options to choose between.

| Consideration | Weighs toward `easy_variables_options` shape (chosen) | Weighs toward `indicator_variables_options` shape (not chosen) |
|---|---|---|
| Auxiliary variable's own validations | `AuxiliaryVariable` carries no `calculation`, `frequency`, or `override_calculation` — each is `if: :indicator?` (`variable.rb:32,36,39`), same as `EasyVariable` today | None — no validation on the auxiliary type gives a `_goal`/`meta_` key any meaning |
| Synthetic-hash size and risk | One key per variable; no risk of a formula author writing `my_auxiliary_key_goal` and having it silently validate against a goal concept the type does not have | N/A |
| Literal match to `TASKS.md`'s cited pattern reference | Diverges from the literal citation | Matches the literal citation as written, before this spike re-examined it against `variable.rb`'s indicator-only validations |

**Source:** Finding 8; `app/models/rule.rb:207-225`; `app/models/easy_variable.rb`;
`app/models/variable.rb:32,36,39`.

## What remains uncertain

- Whether a variable keyed identically to a Dentaku keyword (`case`, `end`, `then`, `when`,
  `else`, `true`, `false`) is a real, reachable case in this codebase today — `Variable#key`'s
  format validation (`variable.rb:37`) does not exclude these words, but no instance was searched
  for or found; this is a boundary case worth a quick data check before BE-4 ships, not a blocker.
- The general community convention (if any) for encoding a processing pipeline's order as a class
  constant versus deriving it from data was searched for and not found — this spike states "not
  found" rather than filling the gap.

## Suggested options for main and the engineer

- BE-4's builder shape is resolved (Finding 8) and is not offered as a choice here.
- BE-5's `CALCULATION_ORDER`: no viable alternative to the ordered-constant approach was
  surfaced — the alternative ("derive order from the enqueue graph at validation time") would
  require walking Sidekiq queue definitions synchronously inside a model validation, which none of
  the read sources support as a pattern. Proceed as `PLAN.md`/`TASKS.md` specify.

(No open fork remains in this spike. The two items in "What remains uncertain" above are boundary
checks worth a quick look before implementation, not decisions requiring main or the engineer to
choose between options.)
