# SPIKE — ActiveRecord query discipline (preventing raw SQL by default, enforcing database-side processing, and index awareness)

**Conducted by:** Main session (WebSearch + WebFetch) — spike agent was launched twice and self-blocked on Pattern Priming hook injection in an empty research directory; strategy switched to direct research.
**Date:** 2026-05-28
**Status:** Research complete — pending engineer decisions on rule framing

---

## Goal

The 4Shark engineer keeps catching Claude generating queries that violate three established 4Shark norms. Latest example flagged:

```ruby
calendar_ids_by_month = company.calendars
  .where(starts_at: Date.new(2025, 7, 1)..Date.new(2026, 4, 30))
  .pluck(:id, :starts_at)
  .group_by { |_id, starts_at| starts_at.beginning_of_month.to_date }
  .transform_values { |rows| rows.map(&:first) }
```

The query pulls `[id, starts_at]` pairs out of the DB then groups + transforms in Ruby. The grouping should live in the database via `group(...).pluck(...)`.

The three pain points to investigate:

1. **Raw SQL generation when ActiveRecord is expected** — bypasses Rails callbacks, validations, and business-logic integrity, all of which live in the application (98% of 4Shark backends). The exception is querying an external customer database where SQL is the only option (~2% of cases).
2. **Ruby-side filtering / grouping / sorting / transforming** — extends the existing 4Shark `Data Processing Pattern` rule (return IDs/aggregations, not loaded objects) into the shape of post-`pluck` Ruby processing.
3. **No index awareness before writing the query** — risks full table scans on large tables.

This spike collects community evidence to back a new rule plus injection hook (no mechanical blocker — customer-DB queries remain legitimate).

---

## Method

- WebSearch on four targeted angles (database-side vs Ruby-side, raw SQL vs ActiveRecord, index awareness, naming).
- WebFetch on the top community sources for verbatim quotes per Citation Discipline.
- Cross-reference against the existing 4Shark rules: `Data Processing Pattern`, `Script Discipline`, `Research-First Policy`.
- Quote-or-drop applied: every Finding ends with the URL + verbatim substring + confirmation. Sources that returned 404 / certificate errors / no relevant content are marked UNVERIFIED and may not sustain conclusions.

Two prior attempts via `@agent-spike` were terminated by the agent itself after misinterpreting the `inject-code-pattern-on-write.sh` reminder as a hard block on writing into the empty spike directory. Flagged as an unrelated bug to address separately.

---

## Evidence

### Finding 1 — `pluck` exists specifically to avoid building ActiveRecord objects

The Rails Guides explicitly describe `pluck` as the optimization for "I only need the column values, not the model instances".

> "`pluck` directly converts a database result into a Ruby `Array`, without constructing `ActiveRecord` objects. This can mean better performance for a large or frequently-run query."
> — Rails Guides, Active Record Query Interface

**Implication for the rule:** `pluck` is correct when the goal is to get column values cheaply. It is **incorrect** when followed by Ruby-side `group_by` / `transform_values` / `sort_by` to produce a shape the database could have produced via `GROUP BY` / `ORDER BY` directly. The 4Shark example fits the second case.

- URL fetched: https://guides.rubyonrails.org/active_record_querying.html
- Verbatim quote checked
- Quote substring confirmed in the `pluck` section of the Rails Guides

### Finding 2 — `group` is the database-side equivalent of `group_by`

The same Rails Guides chapter documents the `group` query method, which translates to SQL `GROUP BY`:

> "To apply a `GROUP BY` clause to the SQL fired by the finder, you can use the `group` method."
> — Rails Guides, Active Record Query Interface

**Implication for the rule:** the existence of `group(...)` on `ActiveRecord::Relation` means there is always a database-side alternative to `pluck(...).group_by { ... }` in Ruby. The decision tree is: shape via `group(...).count` / `group(...).pluck(...)` / `group(...).sum(...)` first; fall back to Ruby `group_by` only when the grouping logic cannot be expressed in SQL (rare).

- URL fetched: https://guides.rubyonrails.org/active_record_querying.html
- Verbatim quote checked
- Quote substring confirmed in the `group` section of the Rails Guides

### Finding 3 — `find_each` / `find_in_batches` are the canonical memory-safe pattern

For unavoidable Ruby iteration over a large result set, Rails ships explicit batching:

> "Rails provides two methods that address this problem by dividing records into memory-friendly batches for processing. The first method, `find_each`, retrieves a batch of records and then yields _each_ record to the block individually as a model."
> — Rails Guides, Active Record Query Interface

**Implication for the rule:** when the developer truly must iterate in Ruby (e.g., calling an external API per record), the correct shape is `find_each` / `find_in_batches`, not loading the full collection into memory. This aligns with 4Shark's existing `Data Processing Pattern`.

- URL fetched: https://guides.rubyonrails.org/active_record_querying.html
- Verbatim quote checked
- Quote substring confirmed in the batching section of the Rails Guides

### Finding 4 — `update_all` does not instantiate models, fires no callbacks, fires no validations

The canonical reference for raw-SQL-equivalent ActiveRecord methods:

> "It does not instantiate the involved models and it does not trigger Active Record callbacks or validations."
> — APIdock, `ActiveRecord::Relation#update_all`

> "As Active Record callbacks are not triggered, this method will not automatically update updated_at/updated_on columns."
> — APIdock, `ActiveRecord::Relation#update_all`

**Implication for the rule:** `update_all` (and by extension `delete_all`, raw SQL via `connection.execute`) bypasses every guarantee the Rails app provides — including the business-logic integrity the 4Shark engineer flagged as the central risk. The same hazard exists every time Claude is tempted to write a SQL `UPDATE` / `DELETE` "just to be faster".

- URL fetched: https://apidock.com/rails/ActiveRecord/Relation/update_all
- Verbatim quotes checked
- Quote substrings confirmed on the APIdock page

### Finding 5 — Rubocop ships `Rails/SkipsModelValidations` as the canonical lint for this

From the first-pass search summary (sourced from Stack Overflow / Rubocop docs discussion):

> "If you use Rubocop as your linter, the rule `Rails/SkipsModelValidations` will get you most of the way there."
> — surfaced in search results for "Rails update_all delete_all bypass callbacks validations"

**Status:** UNVERIFIED — the quote appears in the WebSearch summary but I did not fetch the underlying Rubocop docs page to confirm the substring. Treat as a lead, not a citation, until the rule's official page (`rubocop-rails/lib/rubocop/cop/rails/skips_model_validations.rb` on GitHub or `docs.rubocop.org/rubocop-rails/cops_rails.html`) is fetched.

### Finding 6 — `strong_migrations` is the canonical safety net for unsafe schema changes (including index ones)

> "Catch unsafe migrations in development"
> — `ankane/strong_migrations` README

> "In Postgres, adding an index non-concurrently blocks writes."
> — `ankane/strong_migrations` README

> "Rails adds an index non-concurrently to references by default, which blocks writes in Postgres."
> — `ankane/strong_migrations` README

**Implication for the rule:** index-related decisions are not just a "performance nicety" — adding the wrong index the wrong way on production locks writes. Any rule about "check the index before the query" should also include "if no index exists and one is needed, do not just add it — `strong_migrations` exists for a reason".

- URL fetched: https://github.com/ankane/strong_migrations
- Verbatim quotes checked
- Quote substrings confirmed in the README

### Finding 7 — `lol_dba` does static analysis to surface missing indexes

> "Missing indexes on database tables causes performance issues. lol_dba gem helps finding out missing indexes on database table in Rails code."
> — RubyInRails, "Rails find missing indexes on tables with lol_dba gem"

> "lol_dba performs static analysis of the code to find out missing indexes."
> — RubyInRails, same article

> "The missing indexes suggested by lol_dba is just a guideline. It suggests which columns should probably be indexed. It is not mandatory to add indices on the suggested tables."
> — RubyInRails, same article

**Implication for the rule:** there is a community-accepted tool that already does the "is this column indexed?" check via static analysis. The rule does not need to be "Claude must run EXPLAIN" — it can be "Claude must check `db/schema.rb` (or `lol_dba`'s output, if the project uses it) before assuming a `WHERE` / `JOIN` / `ORDER BY` will use an index".

- URL fetched: https://www.rubyinrails.com/2018/02/22/rails-find-missing-indexes-with-lol-dba-gem/
- Verbatim quotes checked
- Quote substrings confirmed in the article body

### Finding 8 — Rails ships `explain` and PostgreSQL distinguishes Seq Scan from Index Scan

> "Rails provides the `explain` method on Active Record relations to show the query execution plan. This is one of the most powerful tools for understanding how the database executes queries."
> — Saeloun blog, "Different Approaches to Debugging Query Performance in Rails"

> "Seq Scan – Full table scan, might need an index"
> — Saeloun blog, same article

> "Index Scan – Using an index efficiently"
> — Saeloun blog, same article

**Implication for the rule:** the verification mechanism for "is this query going to be fast?" is built into Rails. The rule can say: when writing a query against a non-trivial table, run `.explain` and check that the plan is not a Seq Scan over a large relation.

- URL fetched: https://blog.saeloun.com/2026/04/15/approaches-to-debugging-query-performance-in-rails/
- Verbatim quotes checked
- Quote substrings confirmed in the article body

### Finding 9 — Sources that did NOT pan out (UNVERIFIED, may not sustain conclusions)

- **Nate Berkopec / Speedshop, "3 ActiveRecord Mistakes That Slow Down Rails Apps"** — fetched, but the verbatim substrings I needed about "filter in DB vs Ruby" do not appear in the page. The article is about `count` / `where` / `present?` specifically, not about post-`pluck` Ruby processing. Drop the attribution to Berkopec; the underlying idea is supported by the Rails Guides quotes above without needing his endorsement.
- **Brandon Weaver / Lapidary Lemur, "Aggregate Active Record"** — URL returned HTTP 404. Cannot be used.
- **RoRvsWild, "Super Fast Rails"** — fetched, but no verbatim quotes on the specific topics. "Missing/unused indexes" appears as a PgHero feature label only, not as explanatory prose. Drop.
- **Flexport Engineering, "How to Safely Use ActiveRecord's after_save"** — fetch failed with TLS error ("unable to verify the first certificate"). UNVERIFIED.
- **Daniela Baron, "Efficient Database Queries in Rails"** — fetched, but the article focuses on PostgreSQL query optimization (indexes, joins, column selection) rather than the Ruby-vs-DB processing question. The relevant substrings are absent. Drop the attribution.

### Finding 10 — No widely-accepted name for the "post-`pluck` Ruby processing" anti-pattern

Across the sources surveyed, the community does **not** appear to have a single canonical name for the shape "pluck then `group_by`/`sort_by`/`transform_values` in Ruby instead of letting the database do it". Adjacent terms exist ("N+1", "loading too many records", "in-memory filtering") but none is a precise match.

**Implication for the rule:** per Citation Discipline rule 3 (no invented term attributions), the rule cannot claim "the community calls this X". The rule can name it internally (e.g., "Ruby-side reshaping anti-pattern" or just "post-pluck Ruby processing") without attribution. Suggestion is to use a 4Shark-internal label and not pretend it comes from elsewhere.

---

## Conclusions

Three rules emerge cleanly from the verified findings:

1. **ActiveRecord-first by default; raw SQL by exception** (Finding 4 — bypass risk). When the target is a 4Shark Rails application (`app`, `integrator`, `onboarding`, `setup`), ActiveRecord is the default. Raw SQL / `update_all` / `delete_all` / `connection.execute` requires explicit engineer authorization in the prompt because they silently skip every callback, validation, and business-rule guarantee the application provides. When the target is an external customer database, raw SQL is normal and the rule does not apply.

2. **Database-side shaping over Ruby-side reshaping** (Findings 1, 2, 3 — `pluck`, `group`, `find_each` are first-class). The decision tree:
   - Need to filter? `where(...)`.
   - Need to group / aggregate? `group(...).count` / `group(...).pluck(...)` / `group(...).sum(...)`.
   - Need to sort? `order(...)`.
   - Need to iterate over many records? `find_each` / `in_batches`.
   - Need to transform a row shape that SQL cannot express? Only then post-`pluck` Ruby is acceptable, and the choice must be explicit (a comment naming the SQL limitation).

3. **Index awareness before non-trivial queries** (Findings 6, 7, 8 — `strong_migrations`, `lol_dba`, `EXPLAIN`/Seq Scan). Before writing a `where` / `join` / `order` against a non-trivial table:
   - Check `db/schema.rb` for an index covering the columns used.
   - If no index exists, surface that to the engineer as a finding (do not silently add one — `strong_migrations` exists because schema changes are dangerous in production).
   - For queries that will be hot (cron, web request hot path, ETL), recommend running `.explain` and confirming the plan is not Seq Scan on a large relation.

**Naming the rule (Finding 10):** no community-standard name exists. Suggest `ACTIVE-RECORD-QUERY-DISCIPLINE.md` as a 4Shark-internal label — parallel to the existing `SCRIPT-DISCIPLINE.md` and `CODE-PATTERN-DISCIPLINE.md`.

**Enforcement choice already made by engineer:** only text + injection hook (no mechanical blocker), because external-DB queries are a legitimate ~2% case.

---

## Next Steps

Engineer to confirm or revise:

1. **Rule structure** — single new doc `ACTIVE-RECORD-QUERY-DISCIPLINE.md` covering all three rules, vs. three separate concerns added to the existing `Data Processing Pattern` section in `CLAUDE.md`. Recommendation: one new doc, referenced from a short `CLAUDE.md` § "ActiveRecord Query Discipline" pointer.
2. **Injection trigger** — keyword set for the hook. Candidates: `query`, `SQL`, `pluck`, `group_by`, `banco`, `database`, `where`, `find_by_sql`, `update_all`, `delete_all`, `connection.execute`. Engineer to prune.
3. **Verification asks** before publication:
   - Confirm Finding 5 by fetching the actual Rubocop `Rails/SkipsModelValidations` documentation page.
   - (Optional) Find a stronger primary source on "process in DB, not Ruby" if the engineer wants the rule to cite a community author by name — current draft relies on Rails Guides only.
4. **Rule expansion candidates** (deferrable to follow-up):
   - The same shape exists in Mongoid (`integrator` project) — verify Mongoid's equivalents (`pluck`, `group`, `aggregate`) and whether the rule applies symmetrically.
   - The `lol_dba` / `strong_migrations` / `EXPLAIN` part of the rule may be heavier than the engineer wants for daily queries. Engineer to scope: full rule for every query, vs. lightweight default + escalation for hot-path / migration-adjacent queries.

Output to the engineer next: HTML summary of the findings (per Output Policy — research output goes to HTML for visual review), then proceed to compose the rule + hook.
