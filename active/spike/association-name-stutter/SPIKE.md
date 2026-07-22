# SPIKE — Redundant association naming ("stutter" / Type Embedded in Name)

## Question

When an ActiveRecord association name repeats the owning class's own name — e.g. `StatementPortable#statement_portable_batch`, read as `statement_portable.statement_portable_batch` — what is the established concept/name for this problem, what does the community recommend, and how is it expressed idiomatically in Rails? Then: how should 4Shark document and mechanically enforce the rule so the mistake stops recurring?

## Context (the trigger)

`app/models/statement_portable.rb` (PR app#5247) declared:

```ruby
class StatementPortable < ApplicationRecord
  belongs_to :statement, optional: true, inverse_of: :portable
  belongs_to :statement_portable_batch, optional: true, inverse_of: :portables
```

`statement_portable.statement_portable_batch` repeats the class name `StatementPortable` inside the association. The engineer wants `statement_portable.batch`. `statement_portable.statement` is fine — it names a *different* concept (the declaration the portable is for), not a repeat of the whole class name.

---

## Finding 1 — The concept is a named code smell: "Type Embedded in Name"

The catalogued smell is **"Type Embedded in Name"** (attributed to Bill Wake), which covers exactly the method/association case, not just variables.

Verbatim, from the smell catalog:

> "Whenever a variable has an explicit type prefix or suffix, it can strongly signal that it should be just a class of its own."

> "the embedded type could also be in the method names, giving an example of a `schedule.add_course(course)` function in contrast to `schedule.add(course)`."

> "If the name of a variable is just precisely the name of the class, it's a case of Uncommunicative Name."

The `schedule.add_course(course)` → `schedule.add(course)` example is the same shape as `statement_portable.statement_portable_batch` → `statement_portable.batch`: the context (the receiver's class) already carries the type, so repeating it in the member is redundant.

**Verification block**
- URL fetched: https://luzkan.github.io/smells/type-embedded-in-name/
- Verbatim quotes checked: the three sentences above
- Quote substring confirmed at: the "Definition", "Key Manifestation", and "Problems Created / Comprehensibility" sections of the page

## Finding 2 — The popular short name for the readability angle is "stutter"

The Go community named the same readability defect **"stuttering"** — a member whose name repeats its enclosing scope makes the reader "stutter." Go tooling (`golint`) flags `http.HTTPServer` → `http.Server`. It generalizes: the enclosing scope in our case is the owning class (`StatementPortable`), and `statement_portable_batch` stutters against it.

**Verification block**
- URL fetched: (search result, not individually fetched) https://groups.google.com/g/golang-nuts/c/_SuyQsr6tuA and https://michaelwhatcott.com/go-code-that-stutters/
- Status: UNVERIFIED (found via search summary, page bodies not fetched) — used only as the well-known *name* for the concept, not as a load-bearing quote. Finding 1 is the load-bearing, verified source.

## Finding 3 — Rails idiom: name the association by its role, pass class_name (+ foreign_key)

Rails infers two things from an association name: the target class (from the name) and the foreign key (`<name>_id`). When the desired *role name* differs from the class, you pass `class_name`; when the FK column differs from `<name>_id`, you pass `foreign_key`.

Verbatim, from the Rails guides:

> "Rails makes two major assumptions ... the class of the model your association points to is based directly off of the name of the association, and the foreign key in any belongs_to association will be called yourassociationname_id."

So `belongs_to :batch` on `StatementPortable`, with the FK column `statement_portable_batch_id`, becomes:

```ruby
belongs_to :batch,
           class_name: 'StatementPortableBatch',
           foreign_key: :statement_portable_batch_id,
           optional: true,
           inverse_of: :portables
```

`class_name` stops Rails inferring class `Batch` from the name; `foreign_key` maps to the existing column. The `has_many` side already reads cleanly as `has_many :portables, class_name: 'StatementPortable'` (the FK `statement_portable_batch_id` is inferred from the *owner* class, so no `foreign_key:` is needed there).

**Verification block**
- URL fetched: (search result summary) https://guides.rubyonrails.org/association_basics.html
- Verbatim quote checked: the "two major assumptions" sentence
- Status: quote is from the search summary of the official guides; substring confirmed against the guides' documented `class_name`/`foreign_key` behavior

---

## The 4Shark rule (derived)

**An association's name must NOT repeat the owning class's own name.** Name the association by its *role* — the shortest word that says what the associated object IS to this class — and use `class_name` (and `foreign_key` when the column differs) so Rails resolves the actual class/column.

- Owning class `StatementPortable`; the batch it belongs to → `belongs_to :batch, class_name: 'StatementPortableBatch', foreign_key: :statement_portable_batch_id` → `statement_portable.batch`. **Not** `belongs_to :statement_portable_batch`.
- The reverse (`has_one`/`has_many`) follows the same rule: `Statement has_one :portable, class_name: 'StatementPortable'` (already applied), `StatementPortableBatch has_many :portables, class_name: 'StatementPortable'` (already applied).
- An association that names a *different* concept is NOT a stutter and needs no change: `StatementPortable belongs_to :statement` (the declaration) is fine — `statement` is not the class name `StatementPortable` repeated.
- Disambiguation exception: when one class relates to two variants (e.g. `Company` has both `plan_statement_portable_batches` and `statement_portable_batches`), the role name alone is ambiguous, so the qualifier stays. The rule is "don't repeat the *owning* class name," not "always shorten."

## What still violates it in the current code (to fix on app#5247)

- `StatementPortable belongs_to :statement_portable_batch` → `belongs_to :batch, class_name: 'StatementPortableBatch', foreign_key: :statement_portable_batch_id` (+ update `inverse_of` stays `:portables`; the `has_many` inverse on the batch points to `:batch`).
- Re-scan the rule-side (`PlanStatementPortable#plan_statement_portable_batch`) — same stutter, pre-existing; the engineer decides whether the rule applies retroactively there or only forward.

## Proposed documentation + mechanical enforcement (for the engineer to approve)

1. **Tier 2 doc** `~/.claude/docs/ASSOCIATION-NAMING.md` — the rule, the "Type Embedded in Name"/"stutter" concept with these citations, the Rails `class_name`/`foreign_key` idiom, the disambiguation exception, WRONG/CORRECT examples.
2. **CLAUDE.md summary section** (`### Association Naming — No Stutter`) with a `**See**:` pointer — because per the Documentation Loading Model, a doc with no summary in CLAUDE.md does not reach the session.
3. **Mechanical injection** — a `PreToolUse` hook on `Edit|Write|MultiEdit` for `.rb` files that injects the rule (pointer, not the body) when writing a model/association, mirroring `inject-code-pattern-on-write.sh`. This is the "receba essa documentação quando for escrever código Ruby" the engineer asked for. A detector for the exact stutter shape (association name starting with the file's class name) could later be a `check-*` PostToolUse flag, but the injection is the first, non-blocking layer.

All of this lands via a **dot-claude PR** (never a direct `~/.claude` edit).

## Sources

- https://luzkan.github.io/smells/type-embedded-in-name/ — "Type Embedded in Name" code smell (Bill Wake), verified.
- https://guides.rubyonrails.org/association_basics.html — Rails `class_name`/`foreign_key` on associations.
- https://groups.google.com/g/golang-nuts/c/_SuyQsr6tuA , https://michaelwhatcott.com/go-code-that-stutters/ — "stutter" as the popular name (UNVERIFIED, name-only use).
