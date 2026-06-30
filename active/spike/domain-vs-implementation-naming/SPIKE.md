# SPIKE — Domain vs Implementation Naming

## Investigation question

When an AI agent names a variable after the technical format or implementation type of its value (e.g., `table_number`, `table_percent`, `table_date` — named after Excel format codes and DataType class names) rather than the business meaning of the value it holds, what is the established software engineering concept that names this failure mode? Does the existing 4Shark Variable Naming rule already cover it? What options exist to reduce the failure mode in this config?

The concrete trigger is `app/app/work_books/application_work_book/style.rb`, where the new attributes `table_number`, `table_percent`, and `table_date` name the style after the Excel presentation format / DataType class hierarchy rather than the business meaning of what those table columns hold. See auxiliary file `naming_codebase_excerpt_1.md` for the full code context.

---

## Sources consulted

- [McConnell, Code Complete 2 — "The Power of Variable Names" (via Nikola Brežnjak blog)](https://nikola-breznjak.com/blog/books/programming/code-complete-2-steve-mcconnell-power-variable-names/) — verbatim quote: "The name must fully and accurately describe the entity that the variable represents."
- [Martin, Clean Code Chapter 2 — "Use Solution Domain Names" / "Use Problem Domain Names" (via dev.to teamradhq)](https://dev.to/teamradhq/clean-code-chapter-2-41ph) — section headings and quotes from Chapter 2 on the two-level naming hierarchy.
- [Spolsky, "Making Wrong Code Look Wrong" (2005)](https://www.joelonsoftware.com/2005/05/11/making-wrong-code-look-wrong/) — distinction between Apps Hungarian (semantic/domain encoding) and Systems Hungarian (compiler-type encoding).
- [Fowler / Evans, "Ubiquitous Language" (2006)](https://martinfowler.com/bliki/UbiquitousLanguage.html) — Evans quote on domain-grounded naming.
- [Evans / Khalil Stemmler, "Intention-Revealing Interfaces" (DDD)](https://khalilstemmler.com/articles/typescript-domain-driven-design/intention-revealing-interfaces/) — Evans quote on encapsulation and naming.
- [GitHub Issue anthropics/claude-code #42796](https://github.com/anthropics/claude-code/issues/42796) — convention adherence degradation when thinking budget is reduced; abbreviated names reappearing.
- [GitHub Issue anthropics/claude-code #4954](https://github.com/anthropics/claude-code/issues/4954) — Claude defaulting to training data patterns instead of project conventions.
- [GitHub Issue anthropics/claude-code #21119](https://github.com/anthropics/claude-code/issues/21119) — Claude ignoring CLAUDE.md naming rules, falling back to trained patterns.
- See auxiliary: `naming_excerpt_1.md` — verbatim source passages and attribution for all cited quotes, with URL and confirmation method.
- See auxiliary: `naming_codebase_excerpt_1.md` — full code excerpts from style.rb, typed_cell.rb, and application_data_type.rb with significance notes.

---

## Findings

### Finding 1: The concept is "Use Problem Domain Names" vs "Use Solution Domain Names" — a Clean Code Chapter 2 distinction

**Evidence:**

Robert C. Martin, *Clean Code* Chapter 2 ("Meaningful Names") defines two named sections — "Use Solution Domain Names" and "Use Problem Domain Names". The section titles are cross-confirmed across multiple independent secondary sources.

A publicly-fetchable secondary summary paraphrases the two sections as (verbatim from the dev.to page):

> "Use solution domain names because other engineers will be able to infer their meaning. Use problem domain names as non-technical stakeholders will be able to infer their meaning."

**UNVERIFIED**: the exact original wording from the book (the "programmer-eese" phrasing, the "people who read your code will be programmers" sentence) could NOT be confirmed verbatim from any public secondary source — every reachable summary paraphrases rather than quotes the book. The literal text requires the original Clean Code (p. 27). Only the section titles and the paraphrased meaning are confirmed.

The hierarchy Martin establishes (as paraphrased consistently across sources): solution domain names (CS/technical terms) are the default; problem domain names (business language) are the fallback when no technical term exists. What Martin does NOT endorse is naming by technical implementation artifact — naming a variable after what format the value happens to be stored in, or after the type class that produced it. His third named section, "Use Intention-Revealing Names," targets exactly the naming-by-accident failure: names that describe how or where, rather than what.

**Source:** [dev.to teamradhq Clean Code Chapter 2 summary](https://dev.to/teamradhq/clean-code-chapter-2-41ph) — paraphrase quote confirmed present on page; section titles cross-confirmed by [thecoderoad.blog](https://thecoderoad.blog/2020/03/29/clean-code-naming-conventions/) and [fabrizioduroni.it](https://www.fabrizioduroni.it/2017/09/11/clean-code-meaningful-names/).

**Significance:** The `table_number` / `table_percent` / `table_date` names are solution-domain names in the wrong sense: they name the Excel cell format code (`0.00`, `0.00\%`, `yyyy-mm-dd`) rather than the business concept the column holds. They are not CS algorithm terms that every programmer recognizes as neutral; they are presentation-layer labels that leak implementation detail into the style interface.

**Verification block:** URL fetched / section titles confirmed present across 3 sources / paraphrase quote confirmed verbatim at dev.to URL / original book wording marked UNVERIFIED (no public verbatim source located).

---

### Finding 2: Steve McConnell's formulation — "fully and accurately describe the entity"

**Evidence:**

McConnell, *Code Complete 2*, Chapter 11 ("The Power of Variable Names"):

> "The name must fully and accurately describe the entity that the variable represents."

And on constants:

> "When naming constants, name the abstract entity the constant represents rather than the number the constant refers to."

The second quote is structurally identical to the `style.rb` problem: `table_number` names the format code (`0.00`) rather than the abstract entity (a commission indicator value measured in numeric form).

**Source:** [Nikola Brežnjak blog — Code Complete 2 notes](https://nikola-breznjak.com/blog/books/programming/code-complete-2-steve-mcconnell-power-variable-names/) — quotes confirmed present on page.

**Significance:** McConnell's rule ("describe the entity, not the number") applies directly: `table_number` describes the format artifact, not the entity (a variable's measured value with a specific data type). The entity is the commission indicator result; the format is implementation detail.

**Verification block:** URL fetched / verbatim quote "The name must fully and accurately describe the entity that the variable represents." confirmed at source URL / substring "fully and accurately describe" confirmed present.

---

### Finding 3: Joel Spolsky's framing — "Apps Hungarian" vs "Systems Hungarian"

**Evidence:**

Spolsky, "Making Wrong Code Look Wrong" (2005):

> "Apps Hungarian had very useful, meaningful prefixes like 'ix' to mean an index into an array, 'c' to mean a count, 'd' to mean the difference between two numbers (for example 'dx' meant 'width'), and so forth."

> "Systems Hungarian had far less useful prefixes like 'l' for long and 'ul' for 'unsigned long' and 'dw' for double word, which is, actually, uh, an unsigned long."

> "Somebody, somewhere, read Simonyi's paper, where he used the word 'type,' and thought he meant type, like class, like in a type system, like the type checking that the compiler does. He did not."

The distinction Spolsky draws is precisely the dimension at issue: encoding semantic/domain meaning (Apps Hungarian — what the variable IS in the business) vs encoding compiler type or representation format (Systems Hungarian — how the data happens to be stored or formatted). `table_number` / `table_percent` / `table_date` are Systems Hungarian shapes: they encode the DataType class name and Excel format code, not the business meaning.

**Source:** [joelonsoftware.com "Making Wrong Code Look Wrong"](https://www.joelonsoftware.com/2005/05/11/making-wrong-code-look-wrong/) — verbatim quotes confirmed present on page.

**Significance:** The `style.rb` naming follows the Systems Hungarian failure mode — taking a name from the implementation dimension (Excel format / DataType class) rather than the semantic dimension (what the column holds in the business domain). This is the misunderstanding Spolsky identifies as the widespread corruption of the original naming insight.

**Verification block:** URL fetched / all three verbatim quotes confirmed at source URL.

---

### Finding 4: Eric Evans — Ubiquitous Language and naming after the domain model

**Evidence:**

Martin Fowler / Evans, "Ubiquitous Language" (2006):

> "By using the model-based language pervasively and not being satisfied until it flows, we approach a model that is complete and comprehensible, made up of simple elements that combine to express complex ideas... Domain experts should object to terms or structures that are awkward or inadequate to convey domain understanding; developers should watch for ambiguity or inconsistency that will trip up design."

Evans, *DDD* (via Stemmler):

> "If a developer must consider the implementation of a component in order to use it, the value of encapsulation is lost."

Evans' "Intention-Revealing Interfaces" principle (as cited by Stemmler from the Los Techies blog, attributed to Evans):

> "Name classes and operations to describe their effect and purpose, without reference to the means by which they do what they promise."

The `table_number` / `table_percent` / `table_date` names violate the "without reference to the means" clause: they reference the format code (`0.00`) and the DataType class name — both means, not purpose.

**Source:** [martinfowler.com/bliki/UbiquitousLanguage.html](https://martinfowler.com/bliki/UbiquitousLanguage.html) — Evans quote confirmed at URL. [khalilstemmler.com Intention-Revealing Interfaces](https://khalilstemmler.com/articles/typescript-domain-driven-design/intention-revealing-interfaces/) — Evans and Stemmler quotes confirmed at URL.

**Significance:** The three new Style attributes are named after implementation artifacts of the DataType hierarchy and Axlsx format codes. Under Ubiquitous Language, they should be named after the business concepts they serve. The domain question the engineer needs to answer is: what does the business call a commission result that is measured numerically? (A "number variable value"? An "indicator measurement"?) That is the language these names should come from, not the DataType class hierarchy.

**Verification block:** URL fetched / Evans quote "By using the model-based language pervasively..." confirmed at martinfowler.com URL / Evans encapsulation quote confirmed at khalilstemmler.com URL.

---

### Finding 5: Anthropic / Claude Code documented evidence on this failure mode

**Evidence:**

Three GitHub issues in `anthropics/claude-code` document the failure mode from different angles:

**Issue #42796** — "[MODEL] Claude Code is unusable for complex engineering tasks with the Feb updates"

> "After thinking was reduced, convention adherence degraded measurably: [...] Abbreviated variable names (buf, len, cnt) reappeared despite explicit rules against them [...]" (the source lists this as the first of several bulleted violations — see auxiliary `naming_excerpt_1.md` Source 5 for the full list)
>
> "These violations are not the model being unaware of the conventions — the conventions are in its context window. They are the model not having the thinking budget to check each edit against the conventions before producing it."

This confirms that convention violations (including naming) occur when the model does not apply sufficient reasoning steps to cross-check the name it is about to produce against the documented rule. The domain-vs-implementation dimension requires an additional reasoning step beyond "avoid abbreviations": the agent must actively ask "is this name from the domain or from the implementation?" — a higher-level check the #42796 reporter found to be the first to drop.

**Issue #4954** — "Claude defaults to training data patterns instead of following CLAUDE.md project guidelines"

Root cause: "Claude pattern-matched to Sass/SCSS examples (more prevalent in training data) instead of following the documented modern CSS nesting requirements."

This is structurally the same failure: the agent defaults to the high-frequency pattern from training data (in this case, Sass syntax) rather than the project-specified approach. For naming, the high-frequency training-data pattern is naming after the technical dimension (data types, formats), because most open-source code does exactly that.

**Issue #21119** — "Bug: Claude repeatedly ignores CLAUDE.md instructions in favor of training data patterns"

> "The CLAUDE.md instructions ARE in my context, but they don't seem to have sufficient weight to override trained patterns. Reading "ALWAYS use git-commit-manager" doesn't prevent me from typing `git commit` when that's the pattern I've seen thousands of times in training."

**Source URLs:** [#42796](https://github.com/anthropics/claude-code/issues/42796), [#4954](https://github.com/anthropics/claude-code/issues/4954), [#21119](https://github.com/anthropics/claude-code/issues/21119) — all quotes confirmed present on fetched pages.

**Significance:** No Anthropic issue specifically names "domain vs implementation naming" as a failure mode. The closest documented evidence is #42796 (convention adherence drops when thinking depth is reduced) and #4954/#21119 (training data patterns override project conventions). The domain-vs-implementation naming failure is a specific instance of the general "training data over project convention" class — the training corpus has far more variable names drawn from technical artifacts (types, formats, IDs) than from business vocabulary.

**Verification block:** All three URLs fetched / all verbatim quotes confirmed at source URLs.

---

### Finding 6: Gap analysis against existing 4Shark Variable Naming rule

**Evidence (codebase, `~/.claude/docs/CODE-STYLE-RULES.md` § "Variable Naming"):**

```
Variable naming has two parts. Both are required.

1. No abbreviations. Use full English words for every variable, parameter, block argument, SQL alias,
   and Terraform local.
2. The name must accurately describe what the variable actually holds. The name is a contract with
   the next reader: "this is what is in here". A misleading name is worse than an abbreviated one —
   the reader acts on the wrong assumption and the bug is shipped.
```

**Source:** `~/.claude/docs/CODE-STYLE-RULES.md:178–182`

The existing rule's Part 2 says "the name must accurately describe what the variable actually holds." The question is whether `table_number` accurately describes what it holds:

- What it holds: an Axlsx style object configured with format code `'0.00'`
- What the reader deduces from the name `table_number`: a style for "table cells that contain numbers"
- What the business concept is: a style for table cells displaying values of variables with `NumberDataType`

`table_number` is not exactly a lie — it is an incomplete truth. A "NumberDataType" variable produces numeric values, so "number" is not wrong. But it names the DIMENSION of the format/type rather than the dimension of the business concept. The existing rule ("accurately describe what it holds") does not explicitly require choosing between naming dimensions. It would catch `table_decimal_format` (describes the format code) or `axlsx_number_style` (describes the technical layer), but it might not fire on `table_number` because "number" is technically accurate at the data-type layer.

**The gap:** The existing rule does not distinguish between two classes of names that both satisfy "describes what it holds":
- Names from the domain/business dimension: what business concept does this cell hold?
- Names from the implementation/format dimension: what technical type or format does this cell use?

Both can be accurate. The rule does not specify which dimension to prefer when both are accurate.

**Mechanical enforcement gap:** `check-abbreviated-variables.sh` catches only single-letter variables and single-letter SQL aliases. It explicitly does not check whether names "accurately describe content" (the script's own comment: "that requires human judgment"). The domain-vs-implementation dimension is entirely outside mechanical reach.

**Significance:** The existing rule is necessary but insufficient for this class of failure. It would not have flagged `table_number`, `table_percent`, or `table_date` — they are not abbreviations, they are not single-letter, and they do describe something real about the variables. The gap is in the dimension-preference clause: when two names are both accurate, prefer the domain dimension.

---

### Finding 7: The concrete `style.rb` case — what domain-aligned names might look like

**Evidence (codebase):**

From `typed_cell.rb`, the full call context:

```ruby
when 'NumberDataType' then [value.to_f, :float, style.table_number]
when 'PercentDataType' then [value.to_f, :float, style.table_percent]
when 'DateDataType' then [variable.format(value), :date, style.table_date]
```

The `variable` in `TypedCell` is a `Variable` model instance (commission indicator variable). The domain entities at stake are:
- `NumberDataType` → the variable tracks a numeric measurement (e.g., number of deals closed)
- `PercentDataType` → the variable tracks a rate (e.g., quota attainment percentage, conversion rate)
- `DateDataType` → the variable tracks a date (e.g., a deal closing date, a milestone date)

The business concepts behind these names are partially visible through the `Variable` model's scope names: `Variable.scope :booleans`, `:dates`, `:durations`, `:easy`. The scopes use domain-neutral short names, not format-specific names.

The domain question that determines what the names should be: "In the commission indicator report, what does a cell in the 'NumberDataType column' represent to a business user?" The answer is unknown from the code alone — it depends on which indicator variables a company configures. Without the engineer's domain knowledge, candidate names remain hypothetical.

**Possible domain-aligned naming directions (offered as questions for the engineer — not decisions):**

1. If the existing data type names ARE the domain vocabulary (business users speak of "number variables", "percent variables", "date variables"), then `table_number`, `table_percent`, `table_date` are already domain-aligned, and the concern is the style of alignment (naming after DataType class vs naming after business concept). In that case, the names may be acceptable and the Pattern Priming dimension that flags this is "Convention Drift" — the pre-existing style attributes (`table_value`, `table_title`) are not type-specific; the new ones break that surface pattern.
2. If the business concept is "indicator measured value / indicator target / indicator percentage achievement / indicator measurement date", then names like `table_indicator_numeric_value`, `table_indicator_rate`, `table_indicator_date` would be domain-aligned — but they are also long and may be over-specified for a generic base class.
3. If the business concept is simply "a cell with a numeric presentation format / a cell with a percent presentation format / a cell with a date presentation format" (i.e., the names ARE meant to describe presentation format, not domain meaning), then the names are correctly from the solution domain in Martin's sense — they describe what programmers need to know (the Excel format applied). In this reading, `table_number` is equivalent to `table_with_decimal_format_code`, and the question becomes whether that solution-domain name is clearer than the data-type-derived name.

None of these three readings can be resolved without the engineer's input on what the business calls these column types.

**Source:** `app/app/work_books/application_work_book/typed_cell.rb:9–14`, `app/app/models/variable.rb:45–49` (scope names).

**Significance:** The codebase does not resolve which naming dimension is correct for this class. The engineer knows whether "number variable / percent variable / date variable" is the business vocabulary or whether the business uses different terms for these columns.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Accept the current names (`table_number`, `table_percent`, `table_date`) — they mirror the DataType class names which IS the domain vocabulary in this codebase | Consistent with the DataType hierarchy; callers already say `when 'NumberDataType' then style.table_number` — the parallel reads clearly; no rename needed | Names come from the implementation dimension (DataType class names), not an independently verified business vocabulary; if the class hierarchy changes, names drift | Finding 7 |
| Rename to solution-domain names reflecting the presentation format (`table_decimal`, `table_percentage`, `table_iso_date`) | Makes the Excel format intent explicit; programmer reading the style knows immediately what format code is applied | Still solution-domain (Excel format), not problem-domain (business concept); same dimension problem, different vocabulary | Martin Clean Code §"Use Solution Domain Names" (Finding 1) |
| Rename to problem-domain names reflecting business meaning (requires engineer to supply the business vocabulary for these column types) | Aligns with Ubiquitous Language; Evans quote: "without reference to the means by which they do what they promise" | Requires knowing the business vocabulary; may produce long names for a generic base class; could over-specify for styles meant to be data-type-agnostic | Finding 4 |
| Add an explicit "prefer domain dimension" clause to the Variable Naming rule in `CODE-STYLE-RULES.md` | Closes the gap at the rule level; survives context compaction; applies to all future naming decisions | Does not change mechanical enforcement; requires the Pattern Priming step to be active for it to trigger; still depends on the agent asking "which dimension am I naming from?" | Findings 5, 6 |
| Add the domain-vs-implementation dimension as an explicit check in the Pattern Priming step (`CODE-PATTERN-DISCIPLINE.md`) | Pattern Priming already fires before code writes; adding this as a sixth dimension (alongside structural, signature, return, naming-local, syntactic) makes it mandatory to surface | Adds one more item to an already long Pattern Priming checklist; the AskUserQuestion gate would catch it if the engineer reviews the priming result carefully | Finding 6 |
| Mechanical hook to detect naming-from-type | Would structurally enforce the rule | "Naming from type" is not mechanically detectable — `table_number` does not pattern-match to "single letter" or "abbreviation"; any regex would have excessive false positives (e.g., `user_count` is legitimately named after what it counts, not a type) | Finding 6 |

---

## What remains uncertain

- **What the business vocabulary for these column types is.** The codebase uses `NumberDataType`, `PercentDataType`, `DateDataType` as class names — whether these are ALSO the terms business users use for "indicator variables" in commission reports is not resolvable from the code alone. If they are, the current names may be acceptable.
- **Whether the DataType class names constitute "the domain vocabulary" for this feature.** The `Variable` model's scopes use `:booleans`, `:dates`, `:numbers`, `:percents` — these are scope names, not user-facing terms. Whether a business user says "date variable" or "measurement date variable" or something else is unknown.
- **Whether the existing Variable Naming rule Part 2 is intended to cover dimension-preference.** The rule says "the name must accurately describe what the variable actually holds" — it is ambiguous on whether accuracy requires domain-dimension preference or merely technical accuracy.
- **Whether a sixth Pattern Priming dimension would be surfaced in practice.** Pattern Priming already has five dimensions and an explicit AskUserQuestion gate. Adding a sixth dimension that is hard to verify mechanically depends on the agent having thinking budget to apply it (see Finding 5, issue #42796).

---

## Suggested options for main and the engineer

**Option A — No rule change; accept the current naming as DataType-vocabulary-aligned**

The current names (`table_number`, `table_percent`, `table_date`) mirror the DataType class names. If the engineer confirms that `NumberDataType`/`PercentDataType`/`DateDataType` ARE the domain vocabulary for these indicator types in the business, then the names are already domain-aligned and the Pattern Priming "naming convention (local)" dimension is the relevant check (new names break the pre-existing type-agnostic pattern of the other style attributes like `table_value`, `table_title`). The Convention Drift anti-pattern in `CODE-PATTERN-DISCIPLINE.md` already covers this.

**Option B — Extend the Variable Naming rule with an explicit domain-dimension preference clause**

Add to Part 2 of the Variable Naming rule: "When a name can be drawn from either the domain/business dimension (what this value IS in the business) or the implementation/format dimension (what type this value has, or how it is formatted), prefer the domain dimension. The domain-dimension name is the one a business user would recognize; the implementation-dimension name is the one a programmer would recognize from the code's type system or format configuration. When only the programmer recognizes the name and not the business user, check whether a domain-dimension name exists." This closes the gap identified in Finding 6 at the rule level.

**Option C — Add a "dimension check" to the Pattern Priming in `CODE-PATTERN-DISCIPLINE.md`**

Add a sixth Pattern Priming dimension alongside the existing five: "Naming dimension — are the names drawn from the domain/business vocabulary (what the value IS in the problem space) or from the implementation/format vocabulary (what type the value has, what format it uses, what class produces it)? If from implementation, ask the engineer whether a domain-dimension name is available." This makes the check mandatory at every code-write AskUserQuestion gate, not only when the engineer flags it in review.

**Option C2 — Reframe the existing "Naming convention (local)" Pattern Priming dimension** to explicitly include the domain-vs-implementation axis, rather than adding a sixth dimension. This avoids checklist growth while adding specificity: "Naming convention (local) — verbs siblings use for the same kind of action, noun shape for collections vs individuals, prefix/suffix patterns, and the dimension from which names are drawn (domain/business vs implementation/format)."

**Option D — Rename the three style attributes now**

Independent of any rule change, the engineer decides whether to rename `table_number`, `table_percent`, `table_date` to domain-aligned or format-aligned alternatives. Options include:
- Domain-aligned (requires engineer to supply business vocabulary): unknown without engineer input
- Format-aligned (solution-domain in Martin's sense): `table_decimal`, `table_percentage_rate`, `table_date_formatted` — these describe the presentation format explicitly, which is a legitimate solution-domain naming approach
- DataType-class-aligned (current): `table_number`, `table_percent`, `table_date` — names mirror the DataType class names exactly, which is a valid solution-domain approach if DataType class names are treated as technical vocabulary

(No recommendation — these are options for the engineer to choose between.)
