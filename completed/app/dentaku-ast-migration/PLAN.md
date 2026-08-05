# PLAN — Migrating rule handling to the Dentaku AST

> Reference: `SPIKE.md` in this directory. Every factual claim below traces to a numbered Finding there.

## Objective

Replace text-level and execution-by-sampling handling of incentive rule formulas with the Dentaku AST and tokenizer, so that formula structure, referenced variables and error reporting are all derived from the same engine that evaluates the formula in production. The migration removes the branch blindness of the current validation, removes the false positives of the regex-based variable identification, and opens the path to specific validation messages in place of the current generic one.

## Scope

### In scope

- `Rule` syntax validation for all five rule types (`app/models/rule.rb:65–170`).
- Variable identification in `Incentive#update_variables` (`app/models/incentive.rb:149–175`, four call sites).
- Accumulation detection in `Incentive#check_accumulation` (`app/models/incentive.rb:145–147`).
- Specific validation error messages derived from `ParseError#reason` / `#meta`, replacing the single `:invalid` tag.
- The `Variable#key_regex` builder (`app/models/variable.rb:138–140`), once its last caller is gone.

### Out of scope

- `Track#syntax` (`app/models/track.rb:39–43`). Same shape, but the model is marked `DEPRECATED` and blocks all writes via `before_save { throw :abort }` (`track.rb:20`). No behavior reaches it.
- The frontend. `app-webclient` carries no Dentaku dependency and no formula validation — confirmed by search; validation errors surface only through the GraphQL mutation response.
- Changing the runtime evaluation path itself (`Rule#calculate` in the six consumers). The silent zero is the business rule — a rule that cannot be calculated earns nothing — so the rescue and its exception list stay exactly as they are.
- Reconciliation of already-persisted data. Both backfills are named in items 3 and 4 but scoped as separate work, gated on the blast-radius numbers.

## Chosen approach

**Direction:** items 1–4 are common to all three options carried from `SPIKE.md` § "Suggested options"; only item 5 differed, and its "Direction" block carries the choice that shipped.

**Rationale (from engineer):** The engineer's stated reason for the current design is that validation deliberately executes the same code path that runs in production, so validation and calculation cannot diverge. The AST preserves that property rather than abandoning it: `Calculator#ast` is literally what `evaluate!` calls internally (`dentaku-3.5.7/lib/dentaku/calculator.rb:72`), so a parse-based validation is the same engine, not a second implementation. The engineer also stated that the fake-value approach was adopted because AST use was not understood at the time and there was no time to investigate — which is what this plan revisits.

**Source patterns referenced:** No new code pattern is introduced. `Rule` already owns its validation methods inline (`rule.rb:65–170`); `Incentive` already owns `update_variables` and `check_accumulation` as private callbacks (`incentive.rb:145–175`). Both changes stay inside those existing methods.

## Execution order

One item per PR, ascending by blast radius. The ordering criterion is not effort — it is how far a mistake propagates. An item that cannot change any calculation outcome ships before one that can.

| # | Item | Files touched | Can it change a calculation? | Status |
|---|---|---|---|---|
| 1 | `Formula` model + identifier extraction | 2 models + 2 specs | No — no caller | **Merged**, PR #5274 |
| 2 | Specific validation messages | 2 models + 9 locale files | No — changes which message is shown, never which formula is accepted | **Merged**, PR #5276 + `app-webclient` #6651, #6652 |
| 3 | Accumulation detection | 1 model | Yes — flips `accumulated_deals` | **Merged**, PR #5278 |
| 4 | Variable identification | 1 model + 5 specs | Yes — changes `incentive_variables` rows | **Merged**, PR #5288 |
| 5 | Both-branch validation | 3 models + 4 new + 9 locales + 5 specs | Yes — rejects formulas that pass today | **Merged**, PR #5290 |

Item 2 moved ahead of item 3 during execution of item 1 — see "Learned during execution" below.

## Items

### Item 1 — `Formula` model + identifier extraction

**Objective:** One operation that answers "which variables does this formula reference", complete across all branches, available to every consumer that used regex or execution.

**Shipped:** `app/models/formula.rb`, with Dentaku private to it and `referenced_identifiers` built from the tokenizer's `:identifier` tokens — complete by construction because the lexer has no notion of `IF` (Findings 2, 7). Returns both branches of an `IF` including when the predicate is a constant expression, the case `Calculator#dependencies` still misses (Finding 2), and excludes string literals, function names and comment text (Finding 7). A malformed formula raises; item 4 establishes why that state is unreachable.

### Item 2 — Specific validation messages

**Objective:** Replace the single `:invalid` tag with messages naming what is actually wrong. Every parse failure already carries a typed `reason` from a closed vocabulary plus structured `meta` (Finding 4), so each maps to one key with interpolation and no exception-message parsing is needed.

**Shipped:** an `errors` block per rule type across the nine locales that carry `rule.yml`, one key per reason, with `Rule#validate_syntax` mapping `reason` to key and `meta` to interpolation values. Seven of the gem's fifteen reasons earn a message; the rest collapse to `invalid`. Unbalanced parenthesis, undefined function and wrong arity each produce a distinct message, and no locale silently falls back. The unknown-variable message belongs to item 5, where the name actually comes from.

### Item 3 — Accumulation detection

**Objective:** Ask the accumulation question over the identifier set rather than over raw text.

**Shipped:** `Formula#accumulates_deals?` — public and unit-testable — with `Incentive#check_accumulation` reduced to one line that needs no test of its own. Semantics preserved: `group_total_executed` triggers accumulation under neither the old pattern nor the prefix test.

### Item 4 — Variable identification

**Objective:** Remove the four regex call sites, and with them the false positives.

**Shipped:** `Incentive#update_variables` computes the identifier set once from all rules and tests each variable with a set lookup, which also lifts `rules.pluck(:value)` out of the per-variable loop (Finding 10). The four false-positive cases from Finding 7 no longer create a link, and cases where regex and tokenizer already agree produce identical links. `Variable#key_regex` deleted along with its four inherited spec blocks. Backfill of existing `incentive_variables` rows remains open work, gated on the blast-radius number.

### Item 5 — Both-branch validation

**Objective:** Replace "execute once and see whether it raises" with an explicit parse plus a vocabulary check, so a structural error or an unknown variable is detected regardless of which branch a random value happens to select.

**Dependencies:** items 1–4.

**Direction: structural inspection of the parsed tree, with no values at all.** Validation asks the tree what the formula *says*, never what it *computes*. The dividing line the engineer set: what is written explicitly into the formula is caught at registration; what depends on a variable's runtime value is a calculation-time concern and is left alone. `valor / 0` is rejected because the zero is in the text; `valor / quantidade` is accepted because whether `quantidade` is zero is unknowable until the commission runs.

The same-engine property survives: `Calculator#ast` is the call `evaluate!` makes internally, so validation and calculation still share one engine — the property the current design exists to guarantee.

Rejected: **A — typed-vocabulary execution** (building samples from `Variable#format_default` keeps the execution-by-sampling the plan set out to remove) and **C — additive** (keeps `rand` and two hand-maintained notions of a valid variable, and adds a third code path beside them).

**Shipped:** `Formula#tree` (memoized parse) plus four inspection classes under `Formula`, each an infix visitor answering one structural question — `DivisionByZero#exists?`, `ZeroArgumentFunction#name`, `InvalidDateLiteral#literal`, `TextArithmetic#variable`. `Formula#error` chains the first three (they need only the tree); `Rule#syntax` runs the vocabulary check and then `TextArithmetic`, which needs the company's text-variable names and so cannot live inside `Formula`. Four new error keys across the nine locales. `Rule::Options` lost the samples entirely and gained `#text_variables`, which unions the two built-in status keys with the company's string variables.

**Success criteria:**

- [x] The chosen direction is recorded here with its reason before implementation starts.
- [x] `IF(quantidade > 0, valor / quantidade, variavel_inexistente)` is rejected — the reproduction case from Finding 1.
- [x] Undefined function, wrong arity and unbalanced parentheses are all rejected (Finding 4).
- [x] The four functions registered in `config/initializers/dentaku.rb:3–6` (`time`, `percent`, `boolean`, `date`) are resolvable by the calculator instance used for validation, so a legitimate formula using them is not rejected.
- [x] Validation is deterministic — the same formula and the same vocabulary always produce the same outcome.
- [x] The unknown-variable message names the offending variable.
- [x] The unknown-variable case stays covered, since the execution that catches it today is what goes away.
- [x] The three failure classes the execution caught by accident — a written division by zero, an aggregate called with no arguments, an unparseable date literal — are caught structurally instead of being dropped.
- [x] The two pre-existing line-wrap violations inside the `*_syntax` methods are cleaned up here, since this item rewrites those exact methods.
- [x] The companion `app-webclient` keys ship, so the spreadsheet-import path does not render a raw translation path — PR [#6682](https://github.com/4shark/app-webclient/pull/6682).

**Blast radius was answered by measurement rather than by a count.** The question the plan gated this item on — how many existing `Rule` rows the stricter validation would reject — was replaced by a sharper one: what happens to an incentive already saved with a formula the new validation rejects. Every such formula already returns `calculate = 0` on `develop`, so no commission value changes; see "From item 5" below.

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Identifier source | Tokenizer `:identifier` tokens, not `Calculator#dependencies` | `dependencies` still short-circuits on a constant predicate (Finding 2); the lexer cannot (Finding 7) |
| Structure validation | `Calculator#ast` | It is the same call `evaluate!` makes internally, so validation and calculation share one engine — the property the current design exists to guarantee |
| Error message source | `ParseError#reason` + `#meta` | Closed reason vocabulary and structured metadata (Finding 4); no message-string parsing |
| `Track` | Excluded | Deprecated and write-blocked (`track.rb:20`) |
| Accumulation semantics | Prefix test over identifiers | `check_accumulation` asks a prefix question, not an exact-key question; verified equivalent on the `group_total_*` edge case |
| Item 5 direction | **Structural inspection of the tree, no values** | What is written explicitly into the formula is a registration-time question and is caught; what depends on a variable's runtime value is a calculation-time concern and is left to `#calculate`, which answers zero |
| Where a structural check lives | Under `Formula` when the tree is enough, on `Rule` when it needs the company's vocabulary | `TextArithmetic` needs the names of the company's string variables, which `Formula` has no access to and must not acquire |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Existing rules fail the stricter validation on their next save | Low | Realized and accepted: the client must fix the formula to save the incentive again. Commission values are untouched — the calculation path never validates, and every newly-rejected formula already answered `0` |
| Existing `incentive_variables` rows diverge from what item 4 creates | Medium | Rows persist until each incentive is next saved; the divergence resolves by natural convergence, and a mass correction stays open work |
| Rules referencing a company variable absent from the plan (Finding 5) | Unknown | Confirm with the engineer whether this occurs; if it does, it is a distinct defect that stricter validation alone does not address |
| Silent zero masks the failure (Finding 6) | Accepted | It is the business rule, not a defect: a rule that cannot be calculated earns nothing. Validation stops new occurrences from being saved; it deliberately does not surface existing ones |
| Removing `NoMethodError` / `ArgumentError` / `NameError` from `PARSE_EXCEPTIONS` surfaces latent failures | Medium | Not done: `PARSE_EXCEPTIONS` is untouched, because it protects the commission run rather than the validation. Flagged so any later removal is a deliberate decision rather than an incidental one |

## Assumptions

- Rules reaching `after_save` have already passed validation, so a malformed formula in `update_variables` is unreachable — item 4 establishes the two layers that make it so. Item 1 raises in that case rather than defaulting to empty.
- Variable keys conform to `/\A[a-z]+[a-z0-9_]*\z/` (`variable.rb:37`), so no key can contain a character that would make regex and tokenizer semantics diverge (Finding 8).
- The nine locales that define `rule.yml` are the complete set requiring new message keys.

## Learned during execution

Recorded as each item ships, so later items are planned against what the code actually turned out to be rather than against the original reading.

### From item 1 (PR #5274)

**The Dentaku encapsulation is a `Formula` model, and every later item consumes it rather than adding methods of its own.** Item 1 first landed as a method directly on `Rule`. The engineer rejected that shape for two reasons: the method re-tokenized on every call because it had nowhere to memoize, and AST handling does not belong on a class whose job is database persistence. The replacement is `app/models/formula.rb` — a plain class named for the concept, with Dentaku private to it, following `Counter` and `Computation` (POROs in `app/models/` named for their role while Redis stays behind a private method). The engineer's framing: the same reason pgbouncer is called a connection pooler in our infrastructure.

This changes how the remaining items are written. Item 5 does not add parsing to `Rule#validate_syntax` — it asks `Formula` whether it parses. Item 2's error reasons come from `Formula`, not from a rescue in the model. Item 4 does not add identifier extraction to `Incentive` — it reads the identifiers `Formula` already produces. The engineer also raised moving the variable-identification logic itself out of `Incentive` ("talvez a gente pode até tirar essa lógica ali dos incentivos"), which is a live option for item 4 rather than a settled decision — it was raised as a possibility, not chosen.

**`delegate` is deprecated at 4Shark and must not appear in any later item.** The engineer flagged it as an anti-pattern. It is not in any convention doc and `rubocop-fourshark` ships no cop for it, so nothing catches a recurrence — and 23 models under `app/models/` still use it as legacy (`variable.rb`, `counter.rb`, `commission.rb`, and others), which makes it look sanctioned to anyone reading the surrounding code. Those are left untouched here (§ Scope Discipline), but the absence of enforcement is worth closing: a cop plus a convention-doc entry would stop the next writer from copying the legacy shape. **The replacement is not a hand-written forwarding method** — that reproduces the shape the rule forbids. The collaborator is exposed (`Rule#formula` is public) and callers use it through its own named methods, which is also what keeps `Rule` from growing one forwarding method per `Formula` capability as later items add validity, error reasons and evaluation.

**Memoizing a derived value on an AR model needs invalidation, not a plain `||=`.** `Rule#formula` rebuilds when `value` changes. A plain `@formula ||=` would keep validating the previous formula when the same in-memory record is assigned a new `value` and re-validated — precisely the nested-attributes flow every later item runs inside. The existing `Variable#data_type_object` uses a plain `||=` and carries the same latent staleness; it is not touched here, but later items must not copy that shape for a value that changes mid-object.

**Specific error messages ship without the validation change, which is why item 2 sits ahead of item 3.** Specific messages do not require the parse-based validation to exist first. `Dentaku::ParseError` and `Dentaku::TokenizerError` both descend from `Dentaku::Error` (`dentaku-3.5.7/lib/dentaku/exceptions.rb:2, 33, 59`), which is already the first entry of `PARSE_EXCEPTIONS` (`rule.rb:5`), so today's `validate_syntax` already catches them — it just collapses them into one generic tag. Splitting the rescue to handle `ParseError` / `TokenizerError` separately and emit a message per `reason` changes **which message is shown, never which formula is accepted**. That makes it a zero-blast-radius item, so it moves ahead of accumulation in the order.

**Item 4 must also remove a spec.** `spec/models/variable_spec.rb:61–151` is 22 examples covering `#key_regex`. When item 4 deletes `key_regex`, those examples go with it. The replacement coverage already exists as `Rule#referenced_identifiers` specs, so this is a removal rather than a rewrite — but it needs to be in the diff, not discovered at review.

**Two pre-existing line-wrap violations sit inside the methods item 5 will rewrite.** The line-wrap check flags `validate_syntax(` (reconstructing to ~121 columns) and its `.merge(` chain in `rule.rb`, both inside the `*_syntax` methods. They were left alone in item 1 as out of scope, but item 5 rewrites those exact methods, so the cleanup rides along there instead of needing its own PR.

**`Dentaku::Token#is?(:identifier)` is the gem's own predicate** (`dentaku-3.5.7/lib/dentaku/token.rb:39–41`), preferable to comparing `category` directly. Noted so later items that touch tokens use the same form.

### From item 2 (PR #5276)

**The unknown-variable message belongs to item 5, where the name actually comes from.** Item 2's success criteria listed it, but it is an evaluation-time failure (`UnboundVariableError`), not a parse failure. Reporting it from `Rule` would mean rescuing a Dentaku class in the model, which is the direction this migration is moving away from. It belongs with the both-branch vocabulary check, which is what produces the variable name in the first place.

**Only 7 of the gem's 15 parse reasons are worth a message.** The remaining eight (`unprocessed_token`, `unknown_case_token`, `unbalanced_bracket`, `unbalanced_parenthesis`, `unknown_grouping_token`, `not_implemented_token_category`, `invalid_statement`, `unexpected_zero_width_match`) are either unreachable from a formula a client can type or carry nothing actionable, so they collapse to `invalid`. Later items adding messages should apply the same test rather than mapping the whole vocabulary.

**Interpolating gem metadata needs a filter.** `too_few_operands` / `too_many_operands` carry `operator: Dentaku::AST::Addition` — a gem class. Rendering it would put `ADDITION` in front of a client. Counts (`expect`, `actual`) carry the same information without leaking internals. Any later item that surfaces gem metadata must check each field the same way.

**A locale-coverage check is cheap and worth repeating.** Nine `rule.yml` files each needed the same seven keys; a one-off script parsing every file and diffing against the expected key list caught nothing this time but is the only thing standing between a missing translation and a silent fallback to the generic Rails message.

**Three code rules are enforced only by the engineer's memory, and that is now a measured pattern rather than an anecdote.** `delegate` (item 1) and the ternary operator (item 2) were both caught at review, and both share the same three properties: no entry in any convention doc, no `rubocop-fourshark` cop, and legacy usage that makes the forbidden shape look sanctioned to anyone reading the surrounding code — 23 models still `delegate`, 8 models still carry a ternary. `CODE-PATTERN-DISCIPLINE.md` line 14 actually lists "ternary vs full if" as a *dimension to compare against siblings*, which reads as permission when the siblings use one. The remedy is the progressive-hardening loop this plan already relies on: a convention-doc entry plus a cop, proposed as its own dot-claude PR rather than absorbed into a feature branch.

**The spec conventions have a carve-out that is easy to invert.** `RSPEC-CONVENTIONS.md` allows a `let` inside a `context` for the single scenario input that is a constructor argument of an immutable value object, and explicitly excludes the object under test from that carve-out. Item 2's first revision did the opposite — `Formula.new('...')` per context — which passes rubocop and reads fine. Later items writing specs for `Formula` and `SyntaxProblem` should start from the documented `TypedCell` shape: object under test at the top level parameterized by a per-context input `let`.

**Open linting conflict, surfaced not resolved.** `Naming/RescuedExceptionsVariableName` requires `e` for a used rescued exception, matching all 11 existing occurrences under `app/`, and that contradicts the single-letter-variable ban in § Variable Naming. The cop was followed (the Linting Policy forbids disabling it or editing its config) and the conflict is flagged in the PR for the engineer to settle — either a carve-out in the naming rule for this slot, or a `PreferredName` in the cop config.

### From item 2's merge (PR #5276 + `app-webclient` #6651, #6652)

**A new error key on `Rule` is a two-repo change, and the frontend half is not optional.** Two paths surface a rule validation error and they behave differently. The incentive form is free: `ApplicationMutation#respond_with` sends `errors.to_hash`, already-translated strings, and the component renders them verbatim. The spreadsheet import is not: `IncentiveDocument::Processor` persists `error_key` on a `DocumentError`, and `DocumentErrorComponent` builds `<snake_case(resource)>.errors.<attribute_key>.<error_key>` and translates that path. A key with no frontend entry renders as the raw path string to the client, because `TranslateModule.forRoot()` registers no `missingTranslationHandler`. **Item 5 adds an unknown-variable key, so it inherits this: budget a companion `app-webclient` PR.**

**The frontend translation must be nested, never a dotted key.** ngx-translate's `getValue` splits the requested path and descends into the first segment that resolves to an object, so a literal key containing a dot is unreachable whenever a sibling shadows its first segment. Every incentive file had `"rules"` shadowing `"rules.value"`, so those messages had never displayed. #6651 fixed the incentive files; #6652 cleared the rest after a sweep of all 135 files per language found 12 more dead keys in `user.json` and `collaborative_deal.json`. The sweep is worth re-running after any translation change: merge the files the way `translation-merger.ts` does, enumerate every leaf, and assert `getValue` resolves each leaf's own path. Leaf count before and after is the invariant that proves a restructure lost nothing.

**Interpolation does not reach the spreadsheet report on `develop`, and the engineer's own unmerged branch is what changes that.** The processor writes `error_constraint: error[:value].to_s`, so only an option literally named `value` survives, and Rails' length validator uses `count` (`activemodel/lib/active_model/validations/length.rb:59`) — which is why `user.errors.identifiers.too_short` renders with an empty slot today. Item 2 therefore shipped its seven messages **without** interpolation on that path: the function name and the operand counts appear only in the form. Passing them as `value:` was rejected because Rails already gives `%{value}` the attribute's own value.

`feature/document-error-constraint` (commit `b2dcfc3f0`, unmerged) rewrites this across every processor and adds `ApplicationRecord#constraint_from(error)`, which resolves the option from the attribute's validators (`count` for length and numericality, `date` for date) and lets a model declare its own for hand-added errors:

```ruby
CONSTRAINT_OPTION_BY_ATTRIBUTE_AND_ERROR_KEY = {}.freeze
# dig(error.attribute, error.type) => the option name to read from error.options
```

**Two consequences for later items.** First, once that branch lands, `Rule` can declare its own mapping (`value: { undefined_function: :function, parse_error: :excerpt, … }`) and the import report gains the interpolated fragment — a follow-up that finishes item 2 rather than new scope. Second, the mechanism resolves **one** option per attribute-and-key pair, so `too_few_operands` and `too_many_operands`, which carry both `expected` and `actual`, can surface only one of the two there; either the message is rewritten around a single count or that pair stays uninterpolated. Item 5's unknown-variable message carries a single value (the variable name), so it fits the mechanism cleanly.

**The spreadsheet-import path has no automated coverage, by design.** The repository has no `spec/workers/` directory at all — the Testing Philosophy excludes chained-pipeline workers. So the guarantee for any new key on that path is not a CI test. What item 2 used instead, and what later items should reuse, is a **closed-set argument**: enumerate what the model can emit (`Rule` puts exactly `blank`, one of the seven reasons, or `invalid` on `value`, because `Formula::Error#reason` collapses anything unknown), then show the frontend covers that set exhaustively. That is stronger than sampling, and it does not decay when the gem adds a reason.

### From item 3 (PR #5278)

**A private method cannot be tested, so complexity that needs a test cannot live in one — and this is the rule that decides how item 4 is written.** The first revision put the accumulation predicate inside `Incentive#check_accumulation`, a `before_save` callback, and covered it with `incentive.send(:check_accumulation)`. The engineer rejected it on the language: a private method in Ruby is not reachable, so there is no valid unit test for it; reaching it means an integration test through its caller, at much higher cost. The `send` was justified by precedent in `spec/models/acceptment_spec.rb`, which does the same — but legacy is not precedent, and that is written in the rules injected on every write. **The symptom was the diagnosis**: feeling the need for a test on a private method means the method is carrying too much.

The fix moved the knowledge to `Formula#accumulates_deals?` — public, unit-testable, and the object that already knows which identifiers the formula references. `check_accumulation` became one line that needs no test of its own, and the backfill worker asks the same object the same question. **Item 4 inherits this directly**: `Incentive#update_variables` is a large private method, and decomposing it means moving behavior to public surfaces (`Formula`, `Variable`), never extracting more privates.

**Name the operation in the domain space, not the implementation space.** The predicate shipped first as `references_accumulation_key?` — "reference" is tokenizer mechanics and "key" is the technical word for the token. The business question is whether the incentive accumulates deals, and the attribute it feeds is already called `accumulated_deals`, so `accumulates_deals?` was there for the taking. The constant kept `ACCUMULATION_KEY_PATTERN`, deliberately: it describes a pattern over key names, so implementation vocabulary *is* its subject.

**Collapsing a redundant alternation deletes intent.** The old `ACCUMULATION_KEY_PATTERN` repeated `total_quantity_` even though `total_` already subsumes it. An intermediate revision removed the redundancy as dead weight; the engineer pushed back that the repetition existed to *name* `total_quantity_` as its own family. Behaviour was identical either way — what the collapse destroyed was documentation. The union stayed at three alternatives with a comment saying why.

**Measure before arguing about behavior, and measure again after.** Two rounds of review turned on claims about which identifiers the old pattern matched. Running both patterns side by side over a list of boundary identifiers settled each one in seconds and produced the table now in the PR body. Two results contradicted everyone's intuition, mine included: the old pattern never matched a bare `total`, nor `quantidade_total` without a suffix. Whether a bare `total` — a built-in vocabulary key — *should* accumulate is still open, and deliberately untouched by item 3.

**A release back-merge dissolves `[Unreleased]` without conflicting.** When release 3.60.0 finished, the `[Unreleased]` block became `## [3.60.0]`. A branch whose CHANGELOG hunk anchors on a line inside that block rebases **cleanly** and lands the entry inside the released section — git sees identical context lines and cannot know the heading above them changed meaning. Caught here by simulating the merge (`git merge-tree`) rather than trusting a clean rebase. Any item still open when a release finishes must re-check where its changelog entry landed.

**Environment note.** A release that bumps Rails leaves `vendor/bundle` behind in whichever checkout was not updated. The worktree and the main checkout have separate bundles: `bundle install` in one does not serve the other, and `foreman` for the local databases must run from the checkout whose bundle is current.

### From item 4 (PR #5288)

**An unparseable rule cannot reach `after_save`, and that settles Open decision 2.** Two independent layers stop it. `Rule#validate_syntax` calls `formula.error` and adds the error, and `Incentive` declares `accepts_nested_attributes_for :rules`, so autosave validates the rules with the incentive — an unparseable rule fails the save. Even if it somehow passed, `check_accumulation` is a `before_save` that calls `rule.formula.accumulates_deals?` on every rule, which tokenizes and raises `Dentaku::TokenizerError` before `after_save :update_variables` ever runs. So item 1's behavior on a malformed formula is **raise**, and the reason is that the state is unreachable rather than tolerable: guarding it would trade a loud failure for a silent one that drops a rule's identifiers and unlinks variables.

**An unknown identifier is already rejected today; a known-but-different one is silently not linked.** `Dentaku::AST::Identifier#value` resolves through `context.fetch` and raises `UnboundVariableError` (`dentaku-3.5.7/lib/dentaku/ast/identifier.rb:15-19`), which descends from `Dentaku::Error` and so lands in `PARSE_EXCEPTIONS` — `validate_syntax` turns it into `errors.add(:value, :invalid)`. That is what item 5 makes deterministic: the rejection exists, it just depends on which branch the random values happen to select. The other half is not a validation question at all — with variables `carro` and `carro_usado` both defined, a formula naming `carro_usado` validates and links only `carro_usado`, because `referenced_identifiers` yields whole tokens and `include?` compares by `==`.

**A review finding is a claim to verify, not an instruction to apply.** The `pr-review` agent reported that the new `flat_map` dropped a short-circuit `any?` had, so a persisted unparseable rule could abort the save. The guard was written and shipped before anyone checked whether that state was reachable — it is not, per the first note above, and no reading of `check_accumulation` would have sustained the premise. Later items should measure a finding's premise against the code before changing anything, exactly as item 3 established for behavior claims.

**Blast radius for this item was never measured, and the change shipped anyway.** The plan gated item 4 on the `incentive_variables` count; that number was not obtained. Existing rows persist until each incentive is next saved, so divergence resolves by natural convergence rather than at deploy — which is why shipping was safe, not because the number stopped mattering. The reconciliation named in item 4 is still open work.

**The spec convention question is open and chipped, not settled.** `RSPEC-CONVENTIONS.md` documents a carve-out permitting a `let` per `context` for the scenario input of an immutable value object, and item 2 already recorded it as "easy to invert". Item 4 followed the carve-out literally — root `let(:formula) { Formula.new(text) }` with `let(:text)` per context — and the engineer rejected it: a root `let` depending on a context-only `let` is the indirection the convention exists to prevent. The shipped shape is one named `let` per scenario at the file's top level (`prefixed_key_formula`, `case_statement_formula`, …) with zero `let` inside any context. Whether the documented `TypedCell` example is a genuinely different case or the carve-out is simply wrong is under investigation in its own task — later items writing specs should follow the shipped shape and not the doc's example until that resolves.

### From item 5 (PR #5290)

**The two moments are the whole design, and they carry opposite rules.** At **calculation**, a formula that cannot be computed must not halt the commission — `Rule#calculate` rescues and answers `0`, and that IS the business rule: a rule that cannot be calculated earns nothing. At **registration**, the same failure must be reported, because the client is typing the formula and can fix it. Everything item 5 shipped follows from placing each check on the right side of that line: `PARSE_EXCEPTIONS` stays exactly as it was (it protects the commission), and the structural inspections are new (they protect registration).

**What separates the two is whether the answer is in the text.** A division by a literal zero is written; a division by a variable that happens to be zero is not. An aggregate called with no arguments is written; an aggregate whose collection turns out empty is not. This test decides every check that will be added later, and it is the engineer's, not a derivation from the gem.

**Replacing the execution meant recovering three classes of failure it caught by accident, not merely deleting it.** Dropping `calculate!` dropped `SUM()`, `estado + 1` and `DATE("nao-e-data")` — none of which is a parse error, so `Calculator#ast` alone does not see them. Each came back as a structural inspection over the tree. The plan's earlier reading, that the execution covered nothing a parse does not, was measured wrong: the coverage it provided was real, it was just incidental to sampling rather than designed.

**The old bug was deterministic, not flaky, and that changes what "both-branch" means.** Every numeric sample came from `rand(1..65)` — a strictly positive range — so a predicate like `quantidade > 0` was **always** true and the else branch was **never** evaluated. Three consecutive runs on `develop` over the same corpus came back byte-identical. So the reproduction case in Finding 1 does not pass "sometimes"; it passes every time, and the branch containing the unknown variable was unreachable by construction.

**Differential measurement against `origin/develop` is the technique that settled every behavior claim here, and it is cheap.** A detached worktree at `origin/develop`, the same 19-formula corpus run through both versions, one table of outcomes. Result: 9 identical, 4 message-only improvements, 2 newly caught, 3 recovered structurally, 1 open. Any later item that changes what validation accepts should build the corpus first — arguing about it in review costs more than running it.

**An incentive saved before the stricter validation keeps earning exactly what it earned.** The commission consumers call `rule.calculate`, which never validates and never saves, so a formula the new rules reject is not re-judged at commission time. Measured on `develop`: all four formulas that item 5 makes invalid already returned `calculate = 0` there. The stricter validation therefore changes nothing about money — it changes only what a client can save from here on. The one path that re-judges an old rule is the client editing the incentive through the mutation, where `accepts_nested_attributes_for` autosaves the rules and the save is refused until the formula is fixed.

**A function registered from a lambda is an anonymous class, and its `.name` is the symbol it was registered under.** `Dentaku::Function.register` builds the class at runtime, so `Dentaku::AST::Function::Date` does not exist as a constant and `.name.demodulize` raises `NoMethodError` on a `Symbol`. The forms that work are `node.class.name.to_s.upcase` for display and comparison against the registered symbol (`node.class.name != :date`) for identity. Any later inspection that matches a specific function must use the symbol.

**Fixed-arity functions never reach a visitor — only splat aggregates do.** `DATE()` raises `too few operands` at parse time, so `ZeroArgumentFunction` never sees it. The empty-call check is therefore meaningful only for aggregates whose signature accepts a splat (`SUM`, `MAX`, …). A spec written for the fixed-arity case fails, and the reason is the parser, not the visitor.

**Dentaku's infix visitor stops at a case node, and that gap is known and uncovered.** None of the four inspections reaches inside a `CASE` branch, so a division by zero written inside one is not caught at registration — it falls through to calculation, where it answers zero like any other non-calculable formula. Each class carries a comment saying so. Closing it means either a visitor that descends into `Dentaku::AST::Case` or a different traversal; it is separate work, not a defect of these classes.

**`@x ||=` inside a visitor's `process` is not memoization and rubocop is right to reject it.** `Naming/MemoizedInstanceVariableName` fires because the shape looks like a memo for a method named `x`. What the visitor actually wants is "keep the first match", which is an explicit `return if @x.present?` guard at the top — clearer than the `||=` and no cop conflict.

**A comment states what the code does, not the alternative that was rejected.** Several first drafts of the four classes carried comments explaining why the check is structural rather than executed. That is PR-body material; the class comment says what the class answers and what it does not reach.

## Open work that outlives this plan

Named here so it is not lost when the folder moves to `completed/`. None of it blocks the migration, and each is separate work rather than an unfinished item.

- **Formulas inside a `CASE` branch are not inspected**, because Dentaku's infix visitor stops at the case node.
- **Backfill of `incentive_variables` rows** created by the old regex (item 4). Rows converge naturally as each incentive is next saved; a mass correction is a decision, not a pending step.
- **A `rubocop-fourshark` cop plus a convention-doc entry for `delegate` and the ternary**, so the two rules enforced by the engineer's memory across items 1 and 2 stop depending on it.
- **`Naming/RescuedExceptionsVariableName` versus the single-letter-variable ban** — still an unresolved conflict between a cop and a 4Shark rule.

## Open decisions for the engineer

Every decision this plan opened is settled. They are kept because each one's reason is what makes the shipped code read as deliberate.

1. ~~**Item 5 direction**~~ — settled: structural inspection of the parsed tree, with no sample values. See item 5's Direction block.
2. ~~**Malformed formula in item 1**~~ — settled by item 4: it raises. The state is unreachable (two independent layers stop it before `after_save`), so a guard would only convert a loud failure into a silent one. See "From item 4".
3. ~~**Silent zero (Finding 6)**~~ — settled by the engineer: it is intended business behavior. A rule that cannot be calculated earns nothing, so `#calculate` rescuing and answering `0` is the rule, not a risk. The work stops at validation and does not extend into runtime.
4. ~~**Rollout shape**~~ — settled: shipped directly in one PR, no shadow mode. The argument for splitting was the unknown blast radius, and the measurement below removed it.
5. ~~**Blast-radius measurement**~~ — settled by answering the question the count was a proxy for. A production count of newly-rejected rules would not have said what happens to those rules, and what happens is nothing: the commission path never validates, and every formula the stricter validation rejects already returned `0`. The count is still unobtained and no longer load-bearing.
