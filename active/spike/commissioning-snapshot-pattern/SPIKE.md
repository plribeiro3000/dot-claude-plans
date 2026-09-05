# SPIKE — Commissioning Calculation-Input Snapshot Pattern

## Investigation question

How does the software community idiomatically solve "freeze the inputs a calculation read at commit time, so a later change to the source data does not alter the already-computed historical result" — and which of the candidate storage shapes fits 4Shark's `commissionings` table, given its Single-Table-Inheritance (STI) layout, its heterogeneous per-subtype granularity, and its multi-million-row size?

Concretely: `app`'s `commissionings` table is STI (`type`: `DealCommissioning`, `LimiterCommissioning`, `IndicatorCommissioning`, `RankingCommissioning`, `RedemptionCommissioning`). Only `DealCommissioning` rows carry a `deal_id` and read live deal-transaction state at calculation time. A later edit or deactivation of the deal makes the stored commission value and what the UI shows diverge from what was actually computed. The engineer wants a way to persist the deal inputs at calculation time so the result is reproducible/auditable, without imposing schema cost on the ~4/5 of subtypes that have no deal inputs, and without an expensive backfill over the existing multi-million-row table.

## Sources consulted

- [martinfowler.com/eaaDev/Snapshot.html](https://martinfowler.com/eaaDev/Snapshot.html) — defines the "Snapshot" analysis pattern: a point-in-time, temporality-stripped, normally-immutable view.
- [martinfowler.com/eaaDev/EventSourcing.html](https://martinfowler.com/eaaDev/EventSourcing.html) — defines Event Sourcing as capturing the full sequence of state-changing events, a different scope than a single point-in-time snapshot.
- [martinfowler.com/eaaCatalog/classTableInheritance.html](https://martinfowler.com/eaaCatalog/classTableInheritance.html) — one-line definition of Class Table Inheritance (one table per class); no sparse-column comparison on the page itself.
- [stripe.dev/blog/ledger-...](https://stripe.dev/blog/ledger-stripe-system-for-tracking-and-validating-money-movement) — Stripe's Ledger: immutable, auditable financial log; entries cannot be modified once published.
- [bluepes.com/blog/product-bundle-pricing-marketplace](https://bluepes.com/blog/product-bundle-pricing-marketplace) — the direct e-commerce analog: copy price/component data into the order row at purchase time rather than referencing the live catalog record.
- [kimballgroup.com/2008/09/slowly-changing-dimensions-part-2](https://www.kimballgroup.com/2008/09/slowly-changing-dimensions-part-2/) — Type 2 Slowly Changing Dimension: the data-warehousing technique for preserving the dimension state that was "in effect" for a fact row.
- [github.com/collectiveidea/audited](https://github.com/collectiveidea/audited) — describes itself as a change-log/audit-trail tool, a different job than freezing calculation inputs.
- [nathanmlong.com/2013/05/better-single-table-inheritance](https://nathanmlong.com/2013/05/better-single-table-inheritance/) — names the STI sparse-column problem and the "extract detail table" / delegation fix.
- [dev.37signals.com/the-rails-delegated-type-pattern](https://dev.37signals.com/the-rails-delegated-type-pattern/) — 37signals' own account of moving off STI for exactly the sparse/bloat/migration-cost reason.
- [api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html](https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html) — Rails' own framing of the STI-forces-a-mega-table problem that delegated types solves.
- [postgresql.org/docs/current/sql-altertable.html](https://www.postgresql.org/docs/current/sql-altertable.html) — authoritative behavior of `ADD COLUMN` on an existing table (metadata-only vs full rewrite).
- [heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema](https://www.heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema) — jsonb vs typed-column guidance, with measured costs.
- [writesoftwarewell.com/readonly-attributes-in-rails](https://writesoftwarewell.com/readonly-attributes-in-rails) and [mohnishjadwani.com/posts/attr_readonly](https://www.mohnishjadwani.com/posts/attr_readonly/) — `attr_readonly`, the ActiveRecord-layer mechanism nearest to "write-once" enforcement.
- See auxiliary: `commissioning-snapshot_excerpts_1.md` — every quote above with its surrounding paragraph, kept so the engineer can re-weigh a source without a re-fetch.

## Findings

### Finding 1 — The named pattern for "point-in-time view, temporality stripped, normally immutable" is Fowler's Snapshot

**Evidence:** "A Snapshot is simply a view of an object with all the temporal aspects removed." … "Snapshots are a view to help accessing, so in most cases they should be immutable."

**Source:** https://martinfowler.com/eaaDev/Snapshot.html

**Significance:** This is the closest named, general-purpose pattern to what the engineer described: a record derived from a live object's state at a specific moment, expected to stay fixed afterward. Fowler's own text frames the *reason* for a snapshot as removing temporal complexity for a specific use ("you want to do work with respect to a particular timepoint... maybe you are linking to a system that doesn't understand temporality") — the commission calculation is exactly this: the calculation needs the deal's state "as of" the calculation moment, not perpetually chasing whatever the deal record says today.

**Verification:** URL fetched (https://martinfowler.com/eaaDev/Snapshot.html) / verbatim quote checked / substring "Snapshots are a view to help accessing, so in most cases they should be immutable" confirmed present on re-fetch.

### Finding 2 — Event Sourcing is a different, broader scope: the full change history, not a single frozen input set

**Evidence:** "Capture all changes to an application state as a sequence of events." … "Event Sourcing ensures that all changes to application state are stored as a sequence of events... we can also use the event log to reconstruct past states."

**Source:** https://martinfowler.com/eaaDev/EventSourcing.html

**Significance:** Event Sourcing would replace the live-deal-read entirely with a permanent event log of every deal change, then compute commissions by replaying/reconstructing state as of any date. That is a substantially larger architectural commitment than "freeze the inputs of one calculation" — it requires an event store and a replay mechanism for the deal aggregate, which `app` does not have today for deals. This finding narrows the search: 4Shark's problem is answered by the narrower Snapshot pattern (Finding 1), not by adopting Event Sourcing for deals.

**Verification:** URL fetched (https://martinfowler.com/eaaDev/EventSourcing.html) / verbatim quote checked / substring "Capture all changes to an application state as a sequence of events" confirmed present.

### Finding 3 — Financial-ledger practice treats "immutable, cannot be modified after the fact" as the load-bearing property, not the storage shape

**Evidence:** "Ledger, an immutable and auditable log, as a trustworthy system of record for all of our financial data." … "Transactions previously published into Ledger cannot be deleted or modified, and we can always reconstruct past state by processing all events up to that point."

**Source:** https://stripe.dev/blog/ledger-stripe-system-for-tracking-and-validating-money-movement

**Significance:** Stripe's framing corroborates the general principle behind the request — a financial record's inputs, once committed, must not be alterable by a later change elsewhere in the system — but it does not by itself say HOW to shape the columns for a per-subtype calculation. It supports the *why* (auditability, reproducibility) rather than the *where* (which table, jsonb vs columns). Note: Stripe's Ledger is itself closer in shape to Event Sourcing (Finding 2) — an append-only log of transactions — not a single-row snapshot embedded in an existing record, so it does not directly transfer as a storage-shape template for `commissionings`.

**Verification:** URL fetched (https://stripe.dev/blog/ledger-stripe-system-for-tracking-and-validating-money-movement) / verbatim quote checked / substring "Transactions previously published into Ledger cannot be deleted or modified" confirmed present on re-fetch.

### Finding 4 — The closest direct structural analog is the e-commerce "snapshot the price/line-item into the transactional row at commit time" practice

**Evidence:** "If the order holds a live reference, changing the package's price or swapping a component silently rewrites what every past order appears to contain, and last quarter's numbers stop matching what customers paid. A snapshot makes the order a record of what happened, which is the same principle behind event sourcing: history is an append-only set of facts, not a live projection that mutates when the present changes." The snapshot captures "the bundle's component list as it was at the time of purchase, the quantity of each component, the price charged for the bundle, any per-component price allocation needed for tax, refunds, or accounting."

**Source:** https://bluepes.com/blog/product-bundle-pricing-marketplace

**Significance:** This is structurally identical to 4Shark's problem: an order line references a catalog item (analogous to `DealCommissioning` referencing `deal`), and the community-documented fix is to copy the specific input values the calculation needs directly into the transactional row at the moment of commit — not to keep a live foreign key and re-derive the historical value later. This source explicitly frames the failure mode 4Shark is already experiencing ("last quarter's numbers stop matching") and treats denormalizing the inputs into the transactional record as the standard fix, not an afterthought.

**Verification:** URL fetched (https://bluepes.com/blog/product-bundle-pricing-marketplace) / verbatim quote checked / substring "A snapshot makes the order a record of what happened, which is the same principle behind event sourcing" confirmed present on re-fetch.

### Finding 5 — Type 2 Slowly Changing Dimensions is the data-warehousing analog, but it versions the REFERENCED entity, not the transactional row

**Evidence:** "The Type 2 SCD requires that we issue a new employee record for Ralph Kimball effective July 18, 2008." … "great care must be taken to use the correct contemporary surrogate keys from this dimension in every affected fact table. This assures that the correct dimension profiles are associated with fact table activity."

**Source:** https://www.kimballgroup.com/2008/09/slowly-changing-dimensions-part-2/

**Significance:** SCD Type 2 solves a related but structurally different problem: it keeps a full version history of the *dimension* (here, `deal`) as its own rows, and the fact table (here, `commissionings`) stores a foreign key to whichever dimension version was active at the time. Applied literally, this would mean versioning `deal` itself (a new `deals` row, or a `deal_versions` table, every time a deal changes) and pointing `DealCommissioning` at the specific version — a materially larger change than adding a snapshot to the commissioning row, and one that affects the `deal` model for every consumer, not just commissions. This is a legitimate alternative shape but a different cost profile than Finding 4's "denormalize the specific inputs into the transactional row."

**Verification:** URL fetched (https://www.kimballgroup.com/2008/09/slowly-changing-dimensions-part-2/) / verbatim quote checked / substring "great care must be taken to use the correct contemporary surrogate keys from this dimension in every affected fact table" confirmed present.

### Finding 6 — Rails change-tracking gems (`audited`, and by the same self-description `paper_trail`) solve a different problem than a calculation-input snapshot

**Evidence:** "Audited (previously acts_as_audited) is an ORM extension that logs all changes to your models." … "Audits contain information regarding what action was taken on the model and what changes were made."

**Source:** https://github.com/collectiveidea/audited

**Significance:** `audited` (and gems in its family) records a history of *changes to a record over time* — a diff log an administrator can browse to see "who changed what, when." It does not produce a single frozen record of "the values a calculation consumed at the moment it ran," and it does not attach to a different, unrelated record (`deal`'s history vs. `commissioning`'s stored result) in the shape 4Shark needs. Using it here would mean auditing `deal` changes and then, at read time, reconstructing "what did the deal look like when this commission was calculated" by replaying diffs against a timestamp — closer in spirit to Event Sourcing (Finding 2) than to a one-shot snapshot, and a materially heavier read path than a stored column.

**Verification:** URL fetched (https://github.com/collectiveidea/audited) / verbatim quote checked / substring "is an ORM extension that logs all changes to your models" confirmed present.

### Finding 7 — The Rails/database community's named failure mode for "one subtype's attributes sparsely populate a shared table" is well documented, with a named fix

**Evidence:** "This is bad OO. It's also bad database normalization: lots of NULLs in the table. That, in turn, means you can't set non-shared columns to NOT NULL as a last-resort guard against bad data." The fix: store "common attributes in a single table, non-shared attributes in separate tables with foreign key references, and use object delegation so that each model transparently pulls what it needs from both," e.g. `has_one :details, class_name: 'WrestlingContractDetails'`.

**Source:** https://nathanmlong.com/2013/05/better-single-table-inheritance/

**Significance:** This maps directly onto 4Shark's structural constraint: `commissionings` is STI, only `DealCommissioning` needs the snapshot columns, and putting them on the shared table produces exactly the "lots of NULLs... can't enforce NOT NULL" condition this source names. The documented, named fix is extracting the subtype-specific attributes into their own table joined 1:1 — i.e., Candidate 3 below.

**Verification:** URL fetched (https://nathanmlong.com/2013/05/better-single-table-inheritance/) / verbatim quote checked / substring "lots of NULLs in the table" confirmed present on re-fetch.

### Finding 8 — 37signals' own account of moving off STI cites table-width growth and migration cost as the reasons, and names the fix as "give the new attributes their own fresh table"

**Evidence:** "the table keeps getting bigger widthwise. It has to have all the different kinds of columns that you might have for any type" … "The bigger the table is, the harder and slower it is to migrate." … "your recordings table basically never changes. You just add new types, which are their own fresh tables."

**Source:** https://dev.37signals.com/the-rails-delegated-type-pattern/

**Significance:** This directly speaks to the 4Shark-stated fear of an expensive migration: 37signals' complaint is specifically that a WIDENING shared table becomes harder to migrate over time, and their fix is that the shared table "basically never changes" once subtype-specific attributes live in their own tables. This does not mean any single `ADD COLUMN` is slow (see Finding 11) — it means every future subtype or attribute addition compounds the cost and risk against one shared, ever-growing table, versus a dedicated table that only that subtype's rows ever touch.

**Verification:** URL fetched (https://dev.37signals.com/the-rails-delegated-type-pattern/) / verbatim quote checked / substring "the bigger the table is, the harder and slower it is to migrate" confirmed present.

### Finding 9 — Rails' own documentation frames STI's core defect as forcing a shared "mega table" across all subclasses

**Evidence:** "You can get around the pagination problem by using single-table inheritance, but now you're forced into a single mega table with all the attributes from all subclasses."

**Source:** https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html

**Significance:** This is Rails' own framing (in the class documentation for the alternative it ships, `delegated_type`, added in Rails 6.1) of exactly the trade-off in the concrete problem statement: STI forces `LimiterCommissioning`, `IndicatorCommissioning`, `RankingCommissioning`, and `RedemptionCommissioning` rows to carry columns that only `DealCommissioning` uses. `delegated_type` is the fully-general Rails-native version of Finding 7/8's pattern (each subclass gets its own table, joined by a polymorphic association) — it is a bigger refactor than adding a single satellite table for one subtype, since converting to `delegated_type` typically means every subtype gets its own table, not just the one that needs extra columns.

**Verification:** URL fetched (https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html) / verbatim quote checked / substring "now you're forced into a single mega table with all the attributes from all subclasses" confirmed present.

### Finding 10 — PostgreSQL's `ADD COLUMN` is metadata-only (near-instant) for a nullable column or one with a non-volatile default, on any table size

**Evidence:** "When a column is added with ADD COLUMN and a non-volatile DEFAULT is specified, the default value is evaluated at the time of the statement and the result stored in the table's metadata, where it will be returned when any existing rows are accessed... In neither case is a rewrite of the table required." A volatile default (e.g. `clock_timestamp()`), a stored generated column, an identity column, or a domain type with constraints is the exception that "will cause the entire table and its indexes to be rewritten."

**Source:** https://www.postgresql.org/docs/current/sql-altertable.html

**Significance:** This directly narrows the "expensive migration" fear stated in the problem: adding a nullable `jsonb` column, or nullable typed columns, to the existing multi-million-row `commissionings` table is NOT itself a slow or locking operation in modern PostgreSQL — it is a metadata-only catalog change regardless of row count, as long as no volatile default or new constraint is added in the same statement. This means Candidates 1 and 2 (below) do not actually carry the "expensive backfill" cost the team fears, for the schema-change step itself. What Findings 7-9 argue against is a *different* cost: the permanent, ongoing sparse-column condition across every future row of 4 of 5 subtypes — a design cost, not a migration-runtime cost. Both costs are real; they are just not the same cost, and this finding shows they must be evaluated separately.

**Verification:** URL fetched (https://www.postgresql.org/docs/current/sql-altertable.html) / verbatim quote checked / substring "the default value is evaluated at the time of the statement and the result stored in the table's metadata" confirmed present on re-fetch.

### Finding 11 — jsonb is recommended for optional/sparse/rarely-filtered attributes; typed columns are recommended once a field is present in most rows or is queried directly, with a measured cost difference

**Evidence:** "For values that occur in most of your rows, it's still a good idea to keep them separate [as columns]." … "We found a disk space savings of about 30% by pulling 45 commonly used fields out of JSONB and into first-class columns." … "For datasets with many optional values, it is often impractical or impossible to include each one as a table column. In cases like these, JSONB can be a great fit."

**Source:** https://www.heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema

**Significance:** This bears directly on Candidates 1 vs 2 and on Candidate 3's internal design. If the snapshot fields are stored on the shared `commissionings` table (sparse across ~4/5 of rows, but ALWAYS present as a fixed, known set for the ~1/5 that are `DealCommissioning`), this source's own dividing line ("values that occur in most of your rows... keep them separate [as columns]") is ambiguous at the whole-table level but resolves cleanly if the snapshot moves to its own table (Candidate 3): inside that dedicated table, the fields are present in 100% of rows, which this source's own criterion places squarely on the "typed columns" side, not jsonb.

**Verification:** URL fetched (https://www.heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema) / verbatim quote checked / substring "We found a disk space savings of about 30% by pulling 45 commonly used fields out of JSONB and into first-class columns" confirmed present on re-fetch.

### Finding 12 — Rails' nearest built-in mechanism for "write-once" is `attr_readonly`, and it is an application-layer guard, not a database-level one

**Evidence:** `attr_readonly` marks "some attributes on your Active Record models as readonly, to prevent them from further modification." In Rails 7.1+, an attempted update on an already-persisted readonly attribute raises `ActiveRecord::ReadonlyAttributeError`; in earlier Rails, the update is silently ignored. "You can only set the value of a readonly attribute when the object isn't saved in the database."

**Source:** https://writesoftwarewell.com/readonly-attributes-in-rails

**Significance:** This is the practical Rails answer to Fowler's "snapshots... should be immutable" (Finding 1) for whichever storage shape is chosen. It is enforced only through ActiveRecord's own `save`/`update` path — a raw SQL `UPDATE`, `update_all`, or `update_column` bypasses it, so it communicates intent and blocks the ordinary Rails write path but is not a database-level immutability guarantee (e.g., a `BEFORE UPDATE` trigger or a `REVOKE UPDATE` grant would be the stronger, DB-enforced version, and no source in this research addresses that stronger form for Rails specifically).

**Verification:** URL fetched (https://writesoftwarewell.com/readonly-attributes-in-rails) / verbatim quote checked / substring "You can only set the value of a readonly attribute when the object isn't saved in the database" confirmed present.

## Comparison of candidate shapes

| # | Shape | Sustained by | Pros | Cons |
|---|-------|--------------|------|------|
| 1 | `jsonb` snapshot column on shared `commissionings` (STI base table) | F7, F8, F9 (sparse-column objection), F10 (ALTER TABLE is cheap either way), F11 (jsonb favored for sparse/optional fields) | Schema-change step is metadata-only regardless of row count (F10); no new table/join; jsonb's flexibility tolerates the snapshot's field set evolving without a migration | Directly reproduces the sparse-column condition the Rails/STI community names as the problem to avoid (F7, F9); "lots of NULLs... can't set non-shared columns NOT NULL" for the ~4/5 non-deal subtypes (F7); jsonb loses the "occurs in most rows" cost-efficiency line from F11 for the subset of rows that DO have it; every future STI subtype addition inherits an ever-widening base table (F8) |
| 2 | Typed snapshot columns on shared `commissionings` | Same as #1 minus jsonb-specific trade-offs; F11's "keep as columns" guidance applies once present in most rows, but here it is present in only ~1/5 | Query/read simplicity (no jsonb parsing); enforceable column types/constraints for deal-specific fields | Same sparse-NULL objection as #1, with less flexibility than jsonb if the input set changes shape later (schema migration required each time, though F10 shows each such migration is itself cheap); does not resolve the base-table-widens-forever concern (F8) |
| 3 | Dedicated 1:1 satellite table (e.g. `deal_commissioning_snapshots`, `belongs_to :commissioning`), populated only for `DealCommissioning` rows, forward-only | F7 (named fix: "non-shared attributes in separate tables... object delegation"), F8 (37signals: shared table "basically never changes... no penalty to adding a new type"), F9 (Rails' own framing of the STI mega-table defect), F11 (100% of rows in the satellite table would have the fields — favors typed columns per Heap's own line) | Directly implements the community-documented fix for STI sparse-columns (F7, F8, F9); `commissionings` base table gains nothing extra for the other 4 subtypes — zero NULL cost there; forward-only means the satellite table starts empty, so there is no backfill of the millions of existing rows (this is explicitly a data-migration cost, not a schema-migration cost — F10 already shows the schema step is cheap regardless); satellite table's own fields are typed columns per F11's own criterion, since inside that table the fields are always present | Adds a join for any read that needs both the commissioning and its snapshot (not evaluated by any fetched source for cost — flagged as uncertain below); introduces a second migration/model to maintain; does not, by itself, address `IndicatorCommissioning`'s different (per-user, not per-transaction) granularity — a separate mechanism/table would be needed if per-user indicator inputs are ever snapshotted too |
| 4 | Cache shared indicator inputs on the `user_commissions` parent row | No fetched source addresses this granularity question directly — see "what remains uncertain" | Matches the actual sharing granularity described (indicator/option inputs are constant across a user's incentives, not per-transaction) | Blurs a parent record's responsibility with a child-type-specific concern (`user_commissions` would carry `IndicatorCommissioning`-specific fields the same way the STI base table would carry `DealCommissioning`-specific ones — the SAME sparse-column shape the F7/F8/F9 fix argues against, just one level up the hierarchy); no source found evaluating this specific "cache on the parent of a polymorphic one-to-many" shape |
| 5 | Adopt a change-auditing gem (`audited`/`paper_trail`) instead of a purpose-built snapshot | F2 (Event Sourcing is a different scope), F3 (Stripe's Ledger is itself closer to an event log than a single-row snapshot), F6 (`audited`'s own description is "logs all changes to your models" — a diff history, not a frozen input set) | Off-the-shelf, well-known gems; produces a browsable change history of `deal` for other purposes too | Solves a different problem (browsing what changed on `deal` over time) than reproducing exactly what a commission calculation consumed (F6); reconstructing "the deal as it was at calculation time" from a diff log at read time is closer to Event Sourcing's replay model (F2) than to a stored snapshot, and is a heavier read path than a column lookup |
| 6 | Version the `deal` entity itself (SCD Type 2 style) and point `DealCommissioning` at the specific version | F5 (Kimball's Type 2 SCD) | Textbook data-warehousing answer for "which version of a referenced entity applied at fact-row time"; reusable if other fact-like records ever need the same versioned-deal reference | Materially larger scope than the other candidates — requires versioning `deal` itself, which is a change to the `deal` model used by every consumer, not just commissions (F5); no source found scoping this to a single feature the way Candidate 3 is scoped to `commissionings` alone |

## Immutability (applies to whichever storage shape is chosen)

Fowler's Snapshot pattern states plainly that a snapshot "should be immutable" in the ordinary case (Finding 1), and the financial-ledger sources (Findings 3, 4) treat "cannot be modified after the fact" as the property that makes the record trustworthy for audit. The nearest Rails-native mechanism is `attr_readonly` (Finding 12), which blocks the ordinary ActiveRecord `update`/`save` path (raising in Rails 7.1+) but is not a database-enforced constraint — a raw SQL statement, `update_all`, or `update_column` still bypasses it. No fetched source in this research describes a stronger, database-level enforcement (trigger, `REVOKE UPDATE`) specifically in a Rails context; that remains open if database-level enforcement is a hard requirement.

## What remains uncertain

- **Join cost of Candidate 3 (satellite table) on the specific `app` read paths that show commission history to the UI.** No fetched source measures or discusses the cost of a `has_one`-style join at 4Shark's stated scale; this needs to be evaluated against `app`'s actual read patterns (§ ActiveRecord Query Discipline — index awareness, `.explain`), not against a general web source.
- **Whether Candidate 4 (cache on `user_commissions`) has an established community name or evaluation.** No fetched source evaluates "cache a child's shared attributes on its polymorphic parent" as a named pattern; this research found no citation to sustain or reject it beyond the general sparse-column reasoning in Findings 7-9, which applies to it only by analogy, not directly.
- **Database-level (not ActiveRecord-level) immutability enforcement for a Rails-managed table.** `attr_readonly` (Finding 12) is the only mechanism this research surfaced, and it is explicitly an application-layer guard. Whether 4Shark needs a stronger guarantee (trigger-level) was not settled by any fetched source.
- **The exact backfill cost for Candidate 1/2 is a data question, not a schema one.** Finding 10 settles that the `ALTER TABLE ADD COLUMN` step itself is cheap. It does not address whether the team's original "expensive migration" fear was about that step, or about a planned backfill of historical rows with reconstructed values — which, per the prompt's own framing (deal state is forward-only, past state is unreconstructable), would not be attemptable for either shape.

## Suggested options for main and the engineer

- **Option A** — jsonb or typed snapshot columns directly on `commissionings` (Candidates 1/2). Cheapest to add mechanically (Finding 10) but reproduces the exact sparse-column condition multiple sources name as the STI anti-pattern to avoid (Findings 7-9).
- **Option B** — a dedicated 1:1 satellite table for `DealCommissioning` only, forward-only, typed columns (Candidate 3). Matches the community-documented fix for STI sparse columns (Findings 7-9) and needs no backfill of the existing table (forward-only, per the prompt's own constraint). Leaves the join-cost question open (see "what remains uncertain").
- **Option C** — treat indicator-style shared-per-user inputs (Candidate 4) as a separate decision from the deal-specific per-transaction snapshot (Candidate 3), since the two have different granularity and no single source or shape covers both — pick the shape for each independently rather than forcing one mechanism to serve both grains.
- **Option D** — do not adopt a change-auditing gem or full deal-versioning (Candidates 5/6) for this specific problem; both were found to solve a different-shaped problem or to carry a substantially larger scope than the commissioning-snapshot need (Findings 2, 5, 6), though either remains available if 4Shark later wants full deal history for reasons beyond commission reproducibility.
- **Option E** — whichever storage shape is chosen, apply `attr_readonly` (Finding 12) to the snapshot columns/table as the readily-available immutability guard, while treating database-level enforcement as a separately-scoped follow-up if a stronger guarantee is required.

No option is recommended over another here — the engineer decides at the review gate.
