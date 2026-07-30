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
- Changing the runtime evaluation path itself (`Rule#calculate` in the six consumers). Whether the silent zero becomes an error is a decision listed under Open decisions, not an assumed change.
- Reconciliation of already-persisted data. Both backfills are named in Phase 5 but scoped as separate work, gated on the blast-radius numbers.

## Chosen approach

**Direction:** Not yet chosen — the engineer selects between the three options carried from `SPIKE.md` § "Suggested options". The phasing below is written so that Phases 1–2 are common to all three, and only Phase 3 differs.

**Rationale (from engineer):** The engineer's stated reason for the current design is that validation deliberately executes the same code path that runs in production, so validation and calculation cannot diverge. The AST preserves that property rather than abandoning it: `Calculator#ast` is literally what `evaluate!` calls internally (`dentaku-3.5.7/lib/dentaku/calculator.rb:72`), so a parse-based validation is the same engine, not a second implementation. The engineer also stated that the fake-value approach was adopted because AST use was not understood at the time and there was no time to investigate — which is what this plan revisits.

**Source patterns referenced:** No new code pattern is introduced. `Rule` already owns its validation methods inline (`rule.rb:65–170`); `Incentive` already owns `update_variables` and `check_accumulation` as private callbacks (`incentive.rb:145–175`). Both changes stay inside those existing methods.

## Execution order

One item per PR, ascending by blast radius. The ordering criterion is not effort — it is how far a mistake propagates. An item that cannot change any calculation outcome ships before one that can.

| # | Item | Phase | Files touched | Can it change a calculation? | Status |
|---|---|---|---|---|---|
| 1 | `Formula` model + identifier extraction | 1 | 2 models + 2 specs | No — no caller | **Merged**, PR #5274 |
| 2 | Specific validation messages | 4 | 2 models + 9 locale files | No — see note below | **Merged**, PR #5276 + `app-webclient` #6651, #6652 |
| 3 | Accumulation detection | 5 (part) | 1 model | Yes — flips `accumulated_deals` | Blocked on nothing |
| 4 | Variable identification | 5 (part) | 1 model + 1 spec removal | Yes — changes `incentive_variables` rows | Blocked on blast radius |
| 5 | Both-branch validation | 2 + 3 | 1 model | Yes — rejects formulas that pass today | Blocked on blast radius + Phase 3 choice |

Item 2 moved ahead of item 3 during execution of item 1 — see "Learned during execution" below.

## Execution phases

### Phase 1: Extract referenced identifiers from the formula

**Objective:** One operation that answers "which variables does this formula reference", complete across all branches, available to every consumer that currently uses regex or execution.

**Components:**

- `Rule`: a method returning the set of identifiers in `value`, built from the tokenizer's `:identifier` tokens. Complete by construction because the lexer has no notion of `IF` (Findings 2, 7).

**Dependencies:** None.

**Success criteria:**

- [ ] Returns both branches of an `IF`, including when the predicate is a constant expression (`IF(TRUE, a, b)` yields `a` and `b`) — the case `Calculator#dependencies` still misses (Finding 2).
- [ ] Excludes string literals, function names and comment text (Finding 7).
- [ ] Behavior on a malformed formula is decided explicitly, not inherited — see Open decisions.

### Phase 2: Validate structure through the parser

**Objective:** Replace "execute once and see whether it raises" with an explicit parse, so that structural errors are detected without depending on which branch a random value happens to select.

**Components:**

- `Rule#validate_syntax`: call `Calculator#ast(value)` for structure, then compare the Phase 1 identifier set against the per-type permitted vocabulary.

**Dependencies:** Phase 1.

**Success criteria:**

- [ ] `IF(quantidade > 0, valor / quantidade, variavel_inexistente)` is rejected — the reproduction case from Finding 1, which passes today.
- [ ] Undefined function, wrong arity and unbalanced parentheses are all rejected (Finding 4).
- [ ] The four functions registered in `config/initializers/dentaku.rb:3–6` (`time`, `percent`, `boolean`, `date`) are resolvable by the calculator instance used for validation, so a legitimate formula using them is not rejected.
- [ ] Validation is deterministic — the same formula and the same vocabulary always produce the same outcome.

### Phase 3: Decide the fate of the execution step

**Objective:** Settle what covers variable-vs-variable type conflict, which parsing alone does not catch (Finding 3).

This phase is where the three options diverge. The condition that decides between them is whether losing that type coverage is acceptable.

**Option A — typed-vocabulary execution.** Keep executing, but build the vocabulary from `Variable#format_default` (`variable.rb:130–132`) instead of `rand`, so each variable carries a value of its declared data type (Finding 9). Retains the same-engine property in the strongest form, removes non-determinism, and keeps type coverage.

**Option B — parse only.** Drop the execution. Simplest end state; accepts that a string variable summed with a numeric variable is caught at commission time rather than at save time.

**Option C — additive.** Leave the current execution untouched and add Phases 1–2 beside it. Smallest diff, loses nothing currently covered, but keeps `rand` and keeps two hand-maintained notions of what a valid variable is.

**Dependencies:** Phases 1–2.

**Success criteria:**

- [ ] The chosen option is recorded here with the engineer's reason before implementation starts.
- [ ] If A: every data type in `app/data_types/` yields a usable sample value.
- [ ] If B or C: the type-coverage position is stated explicitly so it is not lost as an implicit assumption.

### Phase 4: Specific validation messages

**Objective:** Replace the single `:invalid` tag with messages naming what is actually wrong.

Today `Rule` has no `errors` block in its locale files — `config/locales/pt-BR/models/rule.yml` defines only attribute and model names, so `:invalid` falls back to Rails' generic message. Every parse failure already carries a typed `reason` from a closed vocabulary plus structured `meta` (Finding 4), so each maps to one key with interpolation and no exception-message parsing is needed.

**Components:**

- Locale files: an `errors` block per rule type, one key per reason, across the nine locales that already carry model files.
- `Rule#validate_syntax`: map `reason` to key, `meta` to interpolation values.

**Dependencies:** Phase 2.

**Success criteria:**

- [ ] Unbalanced parenthesis, undefined function, wrong arity and unknown variable each produce a distinct message.
- [ ] The unknown-variable message names the offending variable.
- [ ] The wrong-arity message names the function and the expected count, both available in `meta`.
- [ ] Every message exists in all locales that currently define `rule.yml`; no locale silently falls back.

### Phase 5: Variable identification and accumulation

**Objective:** Remove the four regex call sites, and with them the false positives.

**Components:**

- `Incentive#update_variables`: compute the identifier set once from all rules, then test each variable with a set lookup. This also lifts `rules.pluck(:value)` out of the per-variable loop (Finding 10).
- `Incentive#check_accumulation`: prefix test over the identifier set rather than over raw text. Semantics preserved — verified that `group_total_executed` triggers accumulation under neither the current pattern nor a prefix test.
- `Variable#key_regex`: delete once no caller remains.

**Dependencies:** Phase 1.

**Success criteria:**

- [ ] The four false-positive cases from Finding 7 no longer create a link.
- [ ] Cases where regex and tokenizer already agree produce identical links — no unintended behavior change.
- [ ] `pluck` executes once per save rather than once per variable.
- [ ] Backfill of existing `incentive_variables` rows is scoped as separate work, gated on the blast-radius number.

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Identifier source | Tokenizer `:identifier` tokens, not `Calculator#dependencies` | `dependencies` still short-circuits on a constant predicate (Finding 2); the lexer cannot (Finding 7) |
| Structure validation | `Calculator#ast` | It is the same call `evaluate!` makes internally, so validation and calculation share one engine — the property the current design exists to guarantee |
| Error message source | `ParseError#reason` + `#meta` | Closed reason vocabulary and structured metadata (Finding 4); no message-string parsing |
| `Track` | Excluded | Deprecated and write-blocked (`track.rb:20`) |
| Accumulation semantics | Prefix test over identifiers | `check_accumulation` asks a prefix question, not an exact-key question; verified equivalent on the `group_total_*` edge case |
| Phase 3 | **Open** | Depends on whether losing variable-vs-variable type coverage is acceptable — engineer's call |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Existing rules fail the stricter validation on their next save | High | Blast radius must be measured before Phase 2 ships; consider a shadow mode that records what would be rejected without rejecting |
| Existing `incentive_variables` rows diverge from what Phase 5 would create | Medium | Rows persist until each incentive is next saved; measure first, then decide between mass correction and natural convergence |
| Rules referencing a company variable absent from the plan (Finding 5) | Unknown | Confirm with the engineer whether this occurs; if it does, it is a distinct defect that stricter validation alone does not address |
| Silent zero masks the failure today (Finding 6) | High | Any rule that currently contributes `0` because of a missing variable is already producing wrong commission values; tightening validation stops new ones but does not surface existing ones |
| Removing `NoMethodError` / `ArgumentError` / `NameError` from `PARSE_EXCEPTIONS` surfaces latent failures | Medium | Not part of this plan; flagged so it is a deliberate later decision rather than an incidental one |

## Assumptions

- Rules reaching `after_save` have already passed validation, so a malformed formula in `update_variables` should be unreachable. Phase 1's behavior in that case is nonetheless decided explicitly rather than defaulting to empty.
- Variable keys conform to `/\A[a-z]+[a-z0-9_]*\z/` (`variable.rb:37`), so no key can contain a character that would make regex and tokenizer semantics diverge (Finding 8).
- The nine locales that define `rule.yml` are the complete set requiring new message keys.

## Learned during execution

Recorded as each item ships, so later items are planned against what the code actually turned out to be rather than against the original reading.

### From item 1 (PR #5274)

**The Dentaku encapsulation is a `Formula` model, and every later item consumes it rather than adding methods of its own.** Item 1 first landed as a method directly on `Rule`. The engineer rejected that shape for two reasons: the method re-tokenized on every call because it had nowhere to memoize, and AST handling does not belong on a class whose job is database persistence. The replacement is `app/models/formula.rb` — a plain class named for the concept, with Dentaku private to it, following `Counter` and `Computation` (POROs in `app/models/` named for their role while Redis stays behind a private method). The engineer's framing: the same reason pgbouncer is called a connection pooler in our infrastructure.

This changes how the remaining phases are written. Phase 2 does not add parsing to `Rule#validate_syntax` — it asks `Formula` whether it parses. Phase 4's error reasons come from `Formula`, not from a rescue in the model. Phase 5 does not add identifier extraction to `Incentive` — it reads `rule.referenced_identifiers`. The engineer also raised moving the variable-identification logic itself out of `Incentive` ("talvez a gente pode até tirar essa lógica ali dos incentivos"), which is a live option for item 4 rather than a settled decision — it was raised as a possibility, not chosen.

**`delegate` is deprecated at 4Shark and must not appear in any later item.** The engineer flagged it as an anti-pattern. It is not in any convention doc and `rubocop-fourshark` ships no cop for it, so nothing catches a recurrence — and 23 models under `app/models/` still use it as legacy (`variable.rb`, `counter.rb`, `commission.rb`, and others), which makes it look sanctioned to anyone reading the surrounding code. Those are left untouched here (§ Scope Discipline), but the absence of enforcement is worth closing: a cop plus a convention-doc entry would stop the next writer from copying the legacy shape. **The replacement is not a hand-written forwarding method** — that reproduces the shape the rule forbids. The collaborator is exposed (`Rule#formula` is public) and callers use it through its own named methods, which is also what keeps `Rule` from growing one forwarding method per `Formula` capability as phases 2 and 4 add validity, error reasons and evaluation.

**Memoizing a derived value on an AR model needs invalidation, not a plain `||=`.** `Rule#formula` rebuilds when `value` changes. A plain `@formula ||=` would keep validating the previous formula when the same in-memory record is assigned a new `value` and re-validated — precisely the nested-attributes flow every later item runs inside. The existing `Variable#data_type_object` uses a plain `||=` and carries the same latent staleness; it is not touched here, but later items must not copy that shape for a value that changes mid-object.

**Specific error messages can ship without the validation change, which reorders the plan.** The original phasing put Phase 4 after Phase 2 on the assumption that specific messages require the parse-based validation to exist first. That is wrong. `Dentaku::ParseError` and `Dentaku::TokenizerError` both descend from `Dentaku::Error` (`dentaku-3.5.7/lib/dentaku/exceptions.rb:2, 33, 59`), which is already the first entry of `PARSE_EXCEPTIONS` (`rule.rb:5`), so today's `validate_syntax` already catches them — it just collapses them into one generic tag. Splitting the rescue to handle `ParseError` / `TokenizerError` separately and emit a message per `reason` changes **which message is shown, never which formula is accepted**. That makes it a zero-blast-radius item, so it moves ahead of accumulation in the order.

**Phase 5 must also remove a spec.** `spec/models/variable_spec.rb:61–151` is 22 examples covering `#key_regex`. When Phase 5 deletes `key_regex`, those examples go with it. The replacement coverage already exists as `Rule#referenced_identifiers` specs, so this is a removal rather than a rewrite — but it needs to be in the diff, not discovered at review.

**Two pre-existing line-wrap violations sit inside the methods Phase 2 will rewrite.** The line-wrap check flags `validate_syntax(` (reconstructing to ~121 columns) and its `.merge(` chain in `rule.rb`, both inside the `*_syntax` methods. They were left alone in item 1 as out of scope, but Phase 2 rewrites those exact methods, so the cleanup rides along there instead of needing its own PR.

**`Dentaku::Token#is?(:identifier)` is the gem's own predicate** (`dentaku-3.5.7/lib/dentaku/token.rb:39–41`), preferable to comparing `category` directly. Noted so later items that touch tokens use the same form.

### From item 2 (PR #5276)

**The unknown-variable message moved to item 5, where the name actually comes from.** Phase 4's success criteria listed it, but it is an evaluation-time failure (`UnboundVariableError`), not a parse failure. Reporting it from `Rule` would mean rescuing a Dentaku class in the model, which is the direction this migration is moving away from. It belongs with the both-branch vocabulary check, which is what produces the variable name in the first place.

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

## Open decisions for the engineer

1. **Phase 3 direction** — A, B or C. Decided by whether variable-vs-variable type coverage must be retained at save time.
2. **Malformed formula in Phase 1** — raise, or treat as no identifiers. Treating it as empty means an unreachable state fails silently; raising means an unreachable state fails loudly.
3. **Silent zero (Finding 6)** — whether `Rule#calculate` returning `0` on a missing variable is intended business behavior or an accepted risk. This decides whether the work stops at validation or extends into runtime.
4. **Rollout shape** — a shadow mode that logs what would be rejected, versus shipping the stricter validation directly. Nothing here changes a `Computation` key, a job argument shape, or introduces a non-idempotent step, so a single deploy is technically legitimate; the argument for phasing is the unknown blast radius, not the deploy machinery.
5. **Blast-radius measurement** — both numbers in `SPIKE.md` § "What remains uncertain" require a production read, which is behind an access boundary. The engineer runs the queries or provides the counts.
