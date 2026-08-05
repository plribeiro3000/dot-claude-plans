# SPIKE — Migrating rule handling to the Dentaku AST

## Investigation question

Where in the `app` backend can the Dentaku AST/tokenizer replace text-level formula handling, and what is still unknown before the migration can be planned to completion?

This spike backs `PLAN.md` in the same directory. Findings below are the verified grounding for that plan; the open items in "What remains uncertain" are what the plan cannot resolve without the engineer or without production data.

## Sources consulted

- `app/models/rule.rb:47–170` — the current validate-by-executing-once flow and the five per-type vocabularies.
- `app/models/incentive.rb:4–7, 145–175` — the four `key_regex` call sites and the accumulation pattern.
- `app/models/variable.rb:37, 138–140` — the variable key format and the regex builder.
- `app/services/commission/indicator_options_processor.rb:5–49` — how the **runtime** vocabulary is actually built.
- `app/workers/indicator_incentive/consumer.rb:29–39` — how a rule is evaluated in production.
- `config/initializers/dentaku.rb:3–6` — the four custom functions registered on the default registry.
- `dentaku-3.5.7/lib/dentaku/ast/functions/if.rb:26–42` — the short-circuit in both `value` and `dependencies`.
- `dentaku-3.5.7/lib/dentaku/exceptions.rb:33–83` — the typed `reason` + `meta` carried by `ParseError` / `TokenizerError`.
- `dentaku-3.5.7/lib/dentaku/token_scanner.rb:35–56, 173–189` — scanner order and the `:identifier` category.
- `dentaku-3.5.7/lib/dentaku/calculator.rb:67–126` — `evaluate!`, `dependencies`, `ast`.
- `activerecord-8.1.3.1/lib/active_record/relation/calculations.rb:295–311` — when `pluck` reads from memory.

All Dentaku behavior below was verified by executing the installed gem, not read from documentation. Raw output is preserved in the auxiliary logs listed per finding.

## Findings

### Finding 1: `If#dependencies` short-circuits, so one branch is never validated

**Evidence:**

```ruby
# dentaku-3.5.7/lib/dentaku/ast/functions/if.rb:38-42
def dependencies(context = {})
  predicate.value(context) ? left.dependencies(context) : right.dependencies(context)
rescue Dentaku::Error, Dentaku::ArgumentError, Dentaku::ZeroDivisionError
  args.flat_map { |arg| arg.dependencies(context) }.uniq
end
```

Executed against the gem:

```
formula = "IF(quantidade > 0, valor / quantidade, variavel_que_nao_existe)"
ctx     = { "quantidade" => 5, "valor" => 100 }

c.dependencies(formula, ctx)  # => []
c.evaluate!(formula, ctx)     # => 20.0
c.dependencies(formula, {})   # => ["quantidade", "valor", "variavel_que_nao_existe"]
```

**Source:** `if.rb:38–42`; auxiliary `/tmp/dentaku_probe_20260729.log`

**Significance:** The `rescue` that would return all three arguments only fires when the predicate itself raises. Because `Rule#validate_syntax` supplies a fully-populated vocabulary, the predicate always resolves, so the fallback never runs. `If#value` (`if.rb:26–28`) has the same shape, so neither the unbound-variable check nor the evaluation reaches the untaken branch.

**Verification:** File read at `if.rb:38–42`; quoted lines confirmed present. Gem executed; output confirmed at `/tmp/dentaku_probe_20260729.log:1–4`.

### Finding 2: `Calculator#dependencies` with an empty context is not a complete fix

**Evidence:** Executed against the gem, `dependencies(formula, {})` per formula:

| Formula | Result | Complete? |
|---|---|---|
| `IF(a > 0, b, c)` | `["a","b","c"]` | yes |
| `IF(1 > 0, a, b)` | `["a"]` | **no — loses `b`** |
| `IF(TRUE, a, b)` | `["a"]` | **no — loses `b`** |
| `CASE status WHEN 0 THEN x ELSE z END` | `["status","x","z"]` | yes |

**Source:** auxiliary `/tmp/dentaku_edge_20260729.log`

**Significance:** When the predicate is a constant expression it resolves without raising even against an empty context, so the `rescue` fallback still does not fire. Any approach that relies on `dependencies` alone retains a residual hole. The tokenizer's `:identifier` tokens do not have this property because the lexer has no notion of `IF`.

**Verification:** Gem executed; output confirmed at `/tmp/dentaku_edge_20260729.log:1–21`.

### Finding 3: `Calculator#ast` rejects a strictly larger class of errors than assumed

**Evidence:** Executed against the gem, `ast(formula)`:

| Formula | Parse result |
|---|---|
| `"texto" + 1` | rejected statically |
| `a + "texto"` | rejected statically |
| `a + b` (both variables) | accepted — raises `Dentaku::ArgumentError` only at evaluation |
| `FOO(a)` | rejected — `ParseError`, `reason: :undefined_function` |
| `IF(a > 0, b)` | rejected — `ParseError`, `reason: :too_few_operands` |

**Source:** auxiliary `/tmp/dentaku_types2_20260729.log`, `/tmp/dentaku_errors_20260729.log`

**Significance:** This locates the exact boundary of what static parsing covers. A type conflict where at least one operand is a **literal** is caught without executing. A type conflict between **two variables** is not, because the parser has no type information for an identifier. Consequently the AST does not by itself subsume everything the current execution step covers — the residue is precisely variable-vs-variable type conflict.

**Verification:** Gem executed; outputs confirmed at `/tmp/dentaku_types2_20260729.log:1–6` and `/tmp/dentaku_errors_20260729.log:1–10`.

### Finding 4: parse failures carry a typed reason and structured metadata

**Evidence:**

```
IF(a > 0, b, c        => TokenizerError  reason=:too_many_opening_parentheses  meta={}
IF(a > 0, b, c))      => TokenizerError  reason=:too_many_closing_parentheses  meta={}
FOO(a)                => ParseError      reason=:undefined_function   meta={function_name: :foo}
IF(a > 0, b)          => ParseError      reason=:too_few_operands     meta={operator: Dentaku::AST::If, expect: 3, actual: 2}
IF(a > 0, b, c, d)    => ParseError      reason=:too_many_operands    meta={operator: Dentaku::AST::If, expect: 3, actual: 4}
a @ b                 => TokenizerError  reason=:parse_error          meta={at: "@ b"}
```

The reason vocabulary is closed and declared in the gem:

```ruby
# dentaku-3.5.7/lib/dentaku/exceptions.rb:43-48
VALID_REASONS = %i[
  node_invalid too_few_operands too_many_operands undefined_function
  unprocessed_token unknown_case_token unbalanced_bracket
  unbalanced_parenthesis unknown_grouping_token not_implemented_token_category
  invalid_statement
].freeze
```

**Source:** `exceptions.rb:33–83`; auxiliary `/tmp/dentaku_errors_20260729.log`

**Significance:** This is the material for the specific error messages the engineer asked for. Each reason maps to one i18n key, and `meta` supplies the interpolation values (which function, expected vs actual arity, the offending substring). No parsing of exception message strings is required.

**Verification:** File read at `exceptions.rb:43–48`; quoted lines confirmed present. Gem executed; output confirmed at `/tmp/dentaku_errors_20260729.log:1–10`.

### Finding 5: the validation vocabulary and the runtime vocabulary are built from different sources

**Evidence:** Validation, for an indicator rule, draws from the **company**:

```ruby
# app/models/rule.rb:90
variable_options = incentive.company.easy? ? easy_variables_options : indicator_variables_options
# app/models/rule.rb:198-204
def indicator_variables_options
  incentive.company.variables.indicators.enabled.each_with_object({}) do |variable, options|
```

Runtime draws from the **plan**:

```ruby
# app/services/commission/indicator_options_processor.rb:41-46
variable_ids = Variable.with_uncached_connection { plan.variables.pluck(:id) }

variable_ids.each do |variable_id|
  variable = Variable.with_uncached_connection { Variable.find(variable_id) }
  options[variable.key] = aggregated_indicator_value(user_commission_id: user_commission.id, variable: variable)
end
```

**Source:** `rule.rb:90, 198–204`; `indicator_options_processor.rb:41–46`

**Significance:** A rule can pass validation by referencing a company variable that is not attached to the plan the commission runs against. At runtime that key is simply absent from `options`. Whether this is a real divergence or is prevented by some invariant elsewhere is not established by the code read so far — it is listed under "What remains uncertain".

**Verification:** Both files read at the cited lines; quoted code confirmed present.

### Finding 6: a missing variable at runtime produces a silent zero, not an error

**Evidence:**

```ruby
# app/models/rule.rb:47-51
def calculate(options = {})
  calculate!(options)
rescue *PARSE_EXCEPTIONS => _e
  0
end
```

```ruby
# app/models/rule.rb:4-5
PARSE_EXCEPTIONS =
  [Dentaku::Error, Dentaku::ZeroDivisionError, Dentaku::ArgumentError, NoMethodError, ArgumentError, NameError].freeze
```

Every consumer calls the non-bang form:

```ruby
# app/workers/indicator_incentive/consumer.rb:39
indicator_value = rule.calculate(options)
```

**Source:** `rule.rb:4–5, 47–51`; `indicator_incentive/consumer.rb:39`; same shape at `limiter_incentive/consumer.rb:38`, `ranking_incentive/consumer.rb:45`, `redemption_incentive/consumer.rb:35`, `deal_incentive/consumer.rb:49`, `deal_incentive/period_processor.rb:35`

**Significance:** This is what makes the validation gap consequential rather than cosmetic. An `UnboundVariableError` at commission time is swallowed and the rule contributes `0`. The rescue list also includes `NoMethodError`, `ArgumentError` and `NameError`, which are Ruby-level errors rather than formula errors, so a genuine code defect inside the evaluation path is also absorbed into the same silent zero.

**Verification:** All cited files read at the cited lines; quoted code confirmed present.

### Finding 7: the regex used for variable identification matches text that is not a variable reference

**Evidence:** The builder and the four call sites:

```ruby
# app/models/variable.rb:138-140
def key_regex
  Regexp.new("(^#{key}$)|(^#{key}[\\W])|([\\W]#{key}$)|([\\W]#{key}[\\W])")
end
```

Executed comparison against the tokenizer:

| Key | Formula | Regex | Tokenizer |
|---|---|---|---|
| `vendas` | `IF(estado = "vendas", premio, 0)` | matches (string literal) | no match |
| `round` | `ROUND(premio, 2)` | matches (function name) | no match |
| `time` | `time(horas_trabalhadas)` | matches (custom function) | no match |
| `premio` | `/* usa premio aqui */ meta * 2` | matches (comment) | no match |
| `vendas` | `meta_vendas * 2` | no match | no match |

**Source:** `variable.rb:138–140`; `incentive.rb:156, 160, 164, 172`; auxiliary `/tmp/dentaku_varid_20260729.log`

**Significance:** The four divergences are all false positives — the incentive is linked to a variable the formula does not use. The tokenizer cannot produce them because the function scanner runs before the identifier scanner (`token_scanner.rb:35–56`), quoted strings carry the `:string` category, and comments are stripped in `Tokenizer#strip_comments` (`tokenizer.rb:66–68`). Where the two agree, behavior is unchanged.

**Verification:** Files read at the cited lines; quoted code confirmed present. Gem executed; output confirmed at `/tmp/dentaku_varid_20260729.log:1–10`.

### Finding 8: variable keys cannot contain characters that would make the two approaches diverge

**Evidence:**

```ruby
# app/models/variable.rb:37
validates :key, presence: true, format: { with: /\A[a-z]+[a-z0-9_]*\z/ }
```

**Source:** `variable.rb:37`

**Significance:** Keys are lowercase, without dots and without accents. The tokenizer's identifier scanner accepts a broader set (`[[[:word:]]\.]+\b`, `token_scanner.rb:184`) including dotted paths, but no valid key can contain a dot, so the only shape where the two would disagree cannot occur. Case is also not a divergence: the identifier scanner normalizes case when `case_sensitive` is false, and `update_variables` already downcases before matching.

**Verification:** File read at `variable.rb:37`; quoted line confirmed present.

### Finding 9: each variable can already produce a correctly-typed sample value

**Evidence:**

```ruby
# app/models/variable.rb:130-136
def format_default
  format(default)
end

def output_default
  output(default)
end
```

`format` is delegated to the data type object (`variable.rb:103`), and the data types are `StringDataType`, `NumberDataType`, `PercentDataType`, `DurationDataType`, `DateDataType`, `BooleanDataType` (`app/data_types/`).

**Source:** `variable.rb:103, 130–136`; `app/data_types/`

**Significance:** The material for a typed validation vocabulary already exists on the model. This is what would let the validation keep executing the formula — the property the current design was built for — while replacing `rand` with values of the correct type, making the execution both deterministic and meaningful for the variable-vs-variable type conflict that Finding 3 shows parsing cannot catch.

**Verification:** File read at `variable.rb:103, 130–136`; quoted code confirmed present. Directory listing of `app/data_types/` confirmed the six classes.

### Finding 10: `pluck` inside the variable loop may issue one query per variable

**Evidence:**

```ruby
# activerecord-8.1.3.1/lib/active_record/relation/calculations.rb:304-311
if loaded? && all_attributes?(column_names)
  result = records.pluck(*column_names)
  ...
end
```

The call site places `pluck` inside the per-variable loop:

```ruby
# app/models/incentive.rb:163-165
company.variables.indicators.enabled.each do |variable|
  incentive_variables.create(variable_id: variable.id) if rules.pluck(:value).map(&:downcase).grep(variable.key_regex).any?
end
```

**Source:** `calculations.rb:304–311`; `incentive.rb:156, 160, 164, 172`

**Significance:** `pluck` reads from memory only when the association is already loaded. On any save path that does not load `rules`, each loop iteration issues a `SELECT`. Whether that path occurs in practice was not established — it is listed under "What remains uncertain".

**Verification:** Both files read at the cited lines; quoted code confirmed present.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Parse-only validation (`ast`, no execution) | Deterministic; covers both branches; typed error reasons | Loses variable-vs-variable type conflict coverage | Findings 3, 4 |
| Parse + tokenizer vocabulary check, no execution | Adds complete identifier coverage including constant predicates | Same type-coverage loss as above | Findings 2, 3 |
| Parse + typed-vocabulary execution | Keeps the same-engine property the current design was built for; adds both-branch coverage; deterministic | Larger change; needs a typed value per data type | Findings 3, 9 |
| Keep execution, add tokenizer check alongside | Smallest diff; loses nothing currently covered | Keeps `rand` non-determinism and the dual vocabulary | Findings 1, 7 |

## What remains uncertain

- **Blast radius of stricter validation.** How many existing `Rule` rows would fail a both-branch vocabulary check. Requires a production read; not obtainable from the code.
- **Blast radius of the variable-identification change.** How many `incentive_variables` rows exist that a tokenizer-based pass would not create. Requires a production read.
- **Whether Finding 5 is a real divergence.** A rule may validate against a company variable absent from the plan's variable set. Whether an invariant elsewhere prevents this — or whether it is a known, tolerated behavior — is a domain question for the engineer.
- **Whether the silent zero in Finding 6 is intentional.** Returning `0` rather than failing the commission may be deliberate business behavior. This decides whether the plan should merely tighten validation or also change runtime behavior.
- **Whether `rules` is loaded at `after_save` time (Finding 10).** Determines whether the query cost is real. Verifiable with instrumentation on a non-productive environment; not verified here.
- **Whether the `NoMethodError` / `ArgumentError` / `NameError` entries in `PARSE_EXCEPTIONS` are load-bearing.** They absorb Ruby-level defects into the same silent zero as formula errors. Whether removing them would surface real failures is unknown without the production blast radius above.

## Suggested options for main and the engineer

- Option A: Parse + typed-vocabulary execution — keeps the same-engine property, adds both-branch coverage, removes `rand`.
- Option B: Parse + tokenizer vocabulary check without execution — simpler, accepts the loss of variable-vs-variable type coverage.
- Option C: Additive only — keep the current execution untouched and add the tokenizer check beside it.

(No recommendation — these are surfaced for the engineer to choose. `PLAN.md` in this directory carries the phased shape of whichever is chosen.)
