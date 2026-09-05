# PLAN-SPIKE — Dependent Follow-Up Query for Integrator Streams

> No DDD documents exist for this feature (no `KNOWLEDGE.md` / `PROCESS.md` / `DOMAIN.md` / `CONTEXT-MAP.md` under this directory). Codebase read from the worktree `~/Projects/4Shark/integrator/.claude/worktrees/stream-follow-up-request` (branch `feature/stream-follow-up-request`, clean, no commits ahead of `origin/develop` yet).

## Objective

The integrator's normalized Extract → Transform → Load pipeline needs a general capability: a stream can be declared DEPENDENT on another stream in the same flow, and its query runs after the parent stream finishes, consuming the parent's output. The immediate driver is replacing a hardcoded enrichment lookup — roughly 20 Transform-stage call sites that fetch a `users` row per record via `connection.fetch(:users, { id: ... })` — with a config-driven dependent query registered on the `Stream` model, so a future flow can register two related queries (parent + follow-up) without new Ruby code per case.

## Scope

### In scope

- The `Stream` model gaining a dependency declaration (depends-on-another-stream flag + reference to the parent `Stream`, scoped to the same flow).
- The producer/consumer/computation machinery needed so a dependent stream's query runs only after its parent finishes, consumes the parent's output, and does not independently occupy an `increment_queue` slot.
- `Computation.increment_queue` counting chains (initial streams) rather than the total stream count, so the counter still closes correctly.
- Rewriting the ~20 Transform-stage enrichment call sites to use the new dependent-query mechanism instead of the inline `connection.fetch(:users, { id: ... })` / `connection.fetch(:users, { id: record['parent_id'] })` calls.
- The `Stream` UI (`app/views/streams/_form.html.erb`, `StreamsController#stream_params`) exposing the new field(s).
- The `Integrator::NORMALIZED_SCHEMA` bootstrap mechanism (`config/normalized_schema.rb`, `lib/tasks/integration/normalized/bootstrap.rake`) accounting for the new field so a dependency stream CAN be declared through it, even though registering the two actual production queries for a live flow is explicitly out of scope (see below).
- Resolving the relationship between this work and the open bug fix in `4shark/integrator#2373` (adapter `fetch` signature).

### Out of scope (open question)

- Registering the actual two queries for any specific production flow (e.g. wiring up Hierarchy's real enrichment against a real client's `users` table) — the engineer does this once the capability exists.
- The Load stage — nothing about how enriched data reaches the 4Shark API changes.
- API-sourced (non-database) streams — the replaced call sites are all inside the `if stream.source.normalized?` branch of each transformer; the `else` branch (custom Liquid attribute mapping for non-normalized sources) is untouched.
- Whether `4shark/integrator#2373` itself should be merged, reworked, or closed — this plan states the relationship, the decision on that PR is separate.

## Fixed design (engineer-decided — treated as requirements, not reopened)

| # | Requirement | Grounding in the current codebase |
|---|---|---|
| 1 | Config lives on `Stream` — each query is its own `Stream` row, not two query bodies in one record. Add a dependency field: "depends on another?" + a reference to the parent `Stream`, chosen via a UI select scoped to the same flow. | `app/models/stream.rb:3-127` — `Stream` already `belongs_to :resource_type, optional: true` and `belongs_to :source, optional: true` (`stream.rb:7-8`); a third `belongs_to` for the parent stream is the same shape. `app/controllers/streams_controller.rb:37-54` and `app/views/streams/_form.html.erb:5-11` show the existing pattern for a `belongs_to` exposed as a `collection` select (`resource_type_id`, `source_id`). |
| 2 | The producer dispatches only the streams with no dependency ("initial" streams). | `app/workers/subsidiary/extractor_producer.rb:15-38` (representative of all 25 `*/extractor_producer.rb` files) enumerates `ResourceType.find_by(name:).streams.enabled` and dispatches every one; this is the method that must add a "has no dependency" filter. |
| 3 | On finishing, a stream checks for a dependent follow-up; if one exists, it triggers it with its output (ids) and does NOT call `increment_executions`; if none exists, it calls `increment_executions` as today. | `app/workers/subsidiary/database_extractor_consumer.rb:35-40` and `app/workers/hierarchy/transformer_consumer.rb:75-76` show the current unconditional `job.computation.increment_executions` + chain-to-next-resource call — this is the exact branch point that needs the "has a dependent?" check. |
| 4 | `Computation.increment_queue` must count chains (initial streams), not total streams. | `app/models/computation.rb:23-46` and `app/models/counter.rb` — `done?` compares `queue.value` against `executions.value`, two Redis counters keyed by `"j_#{job.id}"` (`app/models/job.rb:74-76`) that are **never reset between resources or stages** (`grep` across `app/workers/` found no `reset_queue`/`reset_executions` call outside `database_warmer`, a separate flow — see Finding F1 below). The invariant the whole pipeline depends on is: every `increment_queue` call is eventually matched by exactly one `increment_executions` call. Today that holds because 1 dispatched stream = 1 terminal completion. Once a dependency chain exists, only the CHAIN's dispatch may increment the queue, and only the chain's TERMINAL stream may increment executions — otherwise the two counters permanently diverge and `done?` never returns `true` again for that job. |

**Finding F1 — the counters are a running total for the whole job, not reset per resource/stage.** Confirmed by reading `app/models/job.rb:74-76` (`Computation.new("j_#{id}")` — one `Computation` object per job, memoized) and by grepping every `*/extractor_producer.rb`, `*/transformer_producer.rb`, `*/loader_producer.rb`, `*/*_consumer.rb` for `reset_queue`/`reset_executions`: the only hits are in `app/workers/database_warmer/producer.rb:13-14`, a warm-up flow unrelated to the E→T→L pipeline. This is why requirement 4 is exact rather than approximate: `increment_queue`/`increment_executions` must stay in lockstep across the ENTIRE job, not just within one resource's step, or `done?` breaks for every subsequent resource too.

## Current state — what is being replaced

Every one of these 20 call sites lives inside `Transform` (the `*/transformer_consumer.rb` worker for that resource), inside the `if stream.source.normalized?` branch, and does a single-record lookup keyed by one field of the just-extracted record:

| Resource | File | Line | Join key | Verbatim |
|---|---|---|---|---|
| Deal | `app/workers/deal/transformer_consumer.rb` | 20 | `user_id` | `connection.fetch(:users, { id: record['user_id'] })` |
| Groupification | `app/workers/groupification/transformer_consumer.rb` | 20 | `user_id` | same shape |
| UserField | `app/workers/user_field/transformer_consumer.rb` | 20 | `user_id` | same shape |
| Hierarchy | `app/workers/hierarchy/transformer_consumer.rb` | 20 | `user_id` | same shape (unconditional) |
| Hierarchy | `app/workers/hierarchy/transformer_consumer.rb` | 24 | `parent_id` | `connection.fetch(:users, { id: record['parent_id'] })` (conditional on `record['parent_id'].present?`) |
| UserIdentifier | `app/workers/user_identifier/transformer_consumer.rb` | 20 | `user_id` | same shape |
| Modifier | `app/workers/modifier/transformer_consumer.rb` | 20 | `user_id` | same shape |
| Goal | `app/workers/goal/transformer_consumer.rb` | 21 | `user_id` | same shape |
| UserActivity | `app/workers/user_activity/transformer_consumer.rb` | 20 | `user_id` | same shape |
| User::Admin … User::Unknown (11 files) | `app/workers/user/{admin,president,vice_president,director,superintendent,general_manager,manager,coordinator,supervisor,sales_representative,unknown}/transformer_consumer.rb` | 22 | `parent_id` | `connection.fetch(:users, { id: record['parent_id'] })`, conditional on `record['parent_id'].present?` — verified verbatim at `app/workers/user/manager/transformer_consumer.rb:21-24` |

Two distinct shapes, not one: 8 call sites do an unconditional `user_id` lookup (the record enriches itself with its own owning user), and 12 do a conditional `parent_id` lookup (the record enriches itself with its manager). Both resolve against the same `users` table with no type filter, via a single-record `.first` (`app/adapters/postgres_sql_adapter.rb:31-36`, `#fetch`).

## `4shark/integrator#2373` — subsumption analysis

`app/adapters/postgres_sql_adapter.rb:31-36` (`MicrosoftSqlAdapter` is byte-identical in shape) is ONE overloaded `fetch(collection, conditions = '')` method serving two incompatible call shapes today:

1. **Extract path**, e.g. `app/workers/subsidiary/database_extractor_consumer.rb:14`: `connection.fetch(Sequel.lit(query))` — the first argument is a full rendered SQL string (from `Stream#render_query`, `app/models/stream.rb:74-83`), no `conditions`.
2. **The 20 Transform-time enrichment call sites above**: `connection.fetch(:users, { id: ... })` — the first argument is a bare table name (a Symbol), the second is a Sequel condition Hash.

The `develop` implementation always treats the first argument as a table name — correct for shape 2, wrong for shape 1 (a rendered SQL string gets `.to_s`'d and re-prefixed with `ApplicationConfiguration.table_prefix` as if it were a bare table name, producing the "0 records" bug PR #2373 fixes; see auxiliary `pr-2373_diff_1.md` for the full diff and PR body, fetched via `gh pr diff 2373`).

PR #2373 flips `fetch` to always treat the first argument as a query to run directly (`dataset = connection.fetch(query)`) — correct for shape 1. **As written, this breaks every one of the 20 shape-2 call sites**: `connection.fetch(:users, { id: value })` would become `connection.fetch(:users)` executing the bare Symbol `:users` as SQL text through `Sequel::Database#fetch`, which is not valid SQL.

This plan's scope — replacing all 20 shape-2 call sites with a dependent-stream query that itself renders through `Stream#render_query` and runs through the same extractor mechanics as any primary stream (see Design Point 1 below) — removes every remaining caller of shape 2. If the dependent query is implemented as a genuine Extract-stage query (Design Point 1, Option A), **shape 2 has no callers left once this feature ships**, and PR #2373's redefinition of `fetch` becomes the single, consistent calling convention for every adapter caller. Under that path, no separate `execute_query(sql)` primitive is needed — `fetch`, once PR #2373's shape is the only one in use, already is that primitive.

If instead the dependent query is implemented as a Transform-stage, per-record live call (Design Point 1, Option B), shape 2 survives in a new form (e.g. `connection.fetch(Sequel.lit(stream.render_query(...)))` built from a configured template rather than a hardcoded table+hash), and the two adapter call shapes converge on their own without needing anything from PR #2373 specifically — but this path still does not need a distinct `execute_query` primitive, because it would use the SAME rendered-query call shape PR #2373 already produces.

**Either way, this plan's call-site rewrite is what makes PR #2373's `fetch` redefinition safe to merge — the two are not independent.** Sequencing PR #2373 before this feature's call-site rewrite lands would leave the 20 sites broken in between; sequencing it after (or in the same PR) does not have that window.

## Candidate approaches

### Design Point 1 — where the follow-up query executes and how its result reaches Transform

#### Option A: the follow-up runs at Extract time, as its own `Stream`, producing its own collection

The dependent `Stream` is extracted exactly like any primary stream — through a `*::DatabaseExtractorConsumer` (or a shared one), using `Stream#render_query` (`app/models/stream.rb:74-83`) and the adapter's `fetch` (post-PR-#2373 shape: a raw rendered query), writing its own `<resource>_collections` row (`app/workers/subsidiary/database_extractor_consumer.rb:18-29` is the reference shape: `job.<resource>_collections.build(stream_id:, source_type: 'database', query:)`, JSON body written to `collection.raw_body`). At Transform time, the transformer for the PARENT stream loads BOTH its own collections and the follow-up's collections (`job.<resource>_collections.where(stream_id: stream_id)` already does this per-stream lookup, `app/workers/hierarchy/transformer_consumer.rb:11`), builds an in-memory `id => row` hash from the follow-up's collection once, and looks up each parent record's `user_id`/`parent_id` in that hash instead of calling `connection.fetch` per record.

**Pros:**
- Matches `~/.claude/docs/DATA-ACCESS.md`'s join-decomposition rule for workers ("fetch by id and navigate associations per record... shift the join from the database... to the application/worker fleet") — the join happens in Ruby against an already-extracted, already-JSON-serialized collection, not a live per-record database round trip.
- The follow-up becomes a first-class `Stream` with its own `StreamCheck`/`availability_probe` (`app/workers/job/starter.rb:40-42` already creates a `StreamCheck` for every `Stream.enabled`, dependency or not), so its own reachability is verified before the job runs, exactly like any other stream.
- Removes the live `stream.source.connect!` call from the transformer entirely (`app/workers/hierarchy/transformer_consumer.rb:14`) — Transform no longer opens a database connection at all for the normalized-source branch.
- The follow-up's query is batched (one `WHERE id IN (...)` covering every distinct `user_id`/`parent_id` in the parent's collection) rather than one query per record — fewer round trips to the client's database than today's per-record `connection.fetch`.

**Cons:**
- New moving part: a producer that fires the follow-up's `DatabaseExtractorConsumer` args (`[job_id, dependent_stream_id]`) with a query variable carrying the collected ids, rather than reusing the existing `Sidekiq::Client.push_bulk` dispatch shape verbatim (that shape assumes the producer already knows every stream_id up front, `app/workers/subsidiary/extractor_producer.rb:21-38`).
- The set of "output ids" is not the record's own primary key — it is a specific FIELD of each extracted record (`user_id` for 8 sites, `parent_id` for 12 — see the call-site table above), so the trigger code needs to know WHICH field of the just-finished collection to collect, per dependency (see Design Point 4).
- Introduces a second raw-body-per-collection artifact per job per dependency (storage/IO cost proportional to distinct ids, not to record count — likely far smaller, but a new artifact nonetheless).

**Cost / effort:** New producer/consumer pair (or a generalized one shared across dependencies) + Transform-side join code touching every one of the 20 sites' host files + collection-model wiring (a `job.<resource>_collections` scope already exists per resource, so the follow-up needs either its own `_collections` association or to reuse the target resource's, e.g. writing into `job.user_collections` since the target is always `users`).

**Risk:** medium — new fan-out shape to get right, but every primitive it composes (`Stream#render_query`, `DatabaseExtractorConsumer`'s collection-write pattern, `Computation`) already exists and is exercised by every other resource.

**Source patterns referenced:**
- `app/workers/subsidiary/database_extractor_consumer.rb:1-49` — the collection-write shape to replicate for a dependent stream's own extraction.
- `app/models/stream.rb:74-83` (`render_query`) — the Liquid rendering mechanism the follow-up's query would use.
- `~/.claude/docs/DATA-ACCESS.md` § join decomposition (cited in `~/.claude/CLAUDE.md` § Data Access) — "in a worker, do NOT write a multi-table `joins`; fetch by id and navigate associations per record... shift the join from the database... to the application/worker fleet."

#### Option B: the follow-up runs at Transform time, replacing the live per-record call with a live batched call

Transform keeps doing the enrichment itself (no new Extract-stage `Stream` dispatch), but instead of `connection.fetch(:users, { id: record['user_id'] })` per record, it collects the distinct ids from ALL records in the collection first, renders the dependent `Stream`'s `query_template` once via `Stream#render_query` with the id list as a Liquid variable (e.g. `WHERE id IN ({{ ids }})`), issues ONE `connection.fetch(Sequel.lit(rendered_query))` call, and builds the same `id => row` hash in Ruby before iterating records.

**Pros:**
- Smaller diff — no new producer/consumer, no new `_collections` model or Mongoid association; the change stays inside the existing 20 transformer files plus the `Stream` config model.
- Batches the query (one call instead of N), which alone removes the N+1 shape of today's code even without moving anything to Extract.
- Still uses `Stream#render_query`, so the query is genuinely config-driven (satisfies the stated goal) without needing a second worker pair.

**Cons:**
- Diverges from the join-decomposition-at-Extract-time shape every OTHER dependent-data pattern in the pipeline follows (Extract writes a `raw_body` collection; Transform only ever reads collections that were already fetched — `job.hierarchy_collections.where(stream_id:)`, never opens a NEW query against the source mid-Transform in the general case). The 20 call sites being replaced are themselves the only place in the codebase where Transform opens a live connection (`stream.source.connect!` inside a `*/transformer_consumer.rb`) — this option keeps that shape rather than removing it.
- The dependent `Stream`'s `availability_probe`/`StreamCheck` becomes disconnected from when its query actually runs — the check happens at job start (`app/workers/job/starter.rb:40-42`) against ALL enabled streams, but the query itself only runs deep inside Transform, so a mid-job failure of the dependent query has no equivalent early-failure signal the way a genuine Extract-stage stream would.
- Still needs a `Stream::TransformerConsumer` (or similar) to be threaded past `Computation.increment_queue`/`increment_executions` for the "how does queue vs. executions balance" question (Design Point 3) even though nothing is technically queued for it — the chain/no-increment logic from requirement 3 still applies to WHEN the transformer moves to the next resource, just without a genuine dispatched job for the dependent stream.

**Cost / effort:** Smaller than Option A — touches only the 20 existing files + the `Stream` config model; no new worker classes, no new collection association.

**Risk:** low-to-medium — smaller surface, but leaves the exact shape (a live per-transform database call) that made the enrichment "hardcoded" in spirit, just parameterized instead of literal Ruby.

**Source patterns referenced:**
- `app/workers/hierarchy/transformer_consumer.rb:13-14` — the live `stream.source.connect!` call this option keeps.
- `app/models/stream.rb:74-83` — `render_query`, reused identically to Option A.

---

### Design Point 2 — parameterizing the follow-up query with the parent's collected ids

Both options below assume the follow-up is driven through `Stream#render_query` (`app/models/stream.rb:74-83`), which is `Liquid::Template.parse(template_source).render(variables.stringify_keys)` — plain string interpolation, no automatic SQL quoting or escaping. This is a genuine difference from what is being replaced: today's `connection.fetch(:users, { id: value })` builds its `WHERE` clause through Sequel's own hash-condition builder (`app/adapters/postgres_sql_adapter.rb:31-36`, `dataset.where(conditions)`), which parameterizes the value safely regardless of type. A Liquid-rendered SQL string does not get that safety for free.

#### Option A: batch as a single `WHERE id IN (...)` variable, ids coerced to integers before templating

The triggering code collects the distinct values of the join-key field (`user_id` or `parent_id`) across every record in the just-finished collection(s), coerces each to `.to_i` (or whatever `Stream#primary_key`'s type contract is) in Ruby, joins them into a literal comma-separated string, and passes that string as a single Liquid variable (e.g. `'ids' => user_ids.map(&:to_i).join(',')`) so the dependent stream's `query_template` reads `... WHERE id IN ({{ ids }})`.

**Pros:** one query per collection regardless of record count (matches the batched, worker-side-join shape); the `.to_i` coercion closes the injection surface for the common case (the join key is a database-native integer id) without adding a new templating primitive.

**Cons:** the coercion is a Ruby-side convention the template author has no way to see or enforce — a future stream whose join key is a UUID/string primary key would need a different (quoting-aware) variable-building path, and nothing currently in `Stream#render_query` distinguishes "safe because coerced" from "unsafe because interpolated raw." This is a genuine gap relative to Sequel's hash-condition builder, which handles any value type safely.

**Risk:** low for the immediate case (all 20 replaced sites join on `users.id`, an integer surrogate key per `stream.primary_key` default `'id'` in `app/models/stream.rb:22`), open-ended for a future non-integer join key.

#### Option B: per-record query via `render_query`, one call per record (no batching)

Instead of collecting ids up front, the follow-up's `query_template` takes a single `id` variable (`... WHERE id = {{ id }}`) and is rendered once per record, mirroring today's per-record call shape exactly but through the config-driven template instead of a hardcoded Ruby call.

**Pros:** no coercion/joining logic to get wrong; the template is trivially simple; behaviorally identical (N calls) to what exists today, so behavior change is isolated to "the query text is configured, not hardcoded" rather than also changing the query's cardinality.

**Cons:** does not address the N+1 shape at all — same number of round trips as today; does not benefit from Design Point 1 Option A's batching rationale (a batched Extract-stage follow-up naturally wants Option A's shape); reintroduces exactly the per-record live-call cost `~/.claude/docs/DATA-ACCESS.md`'s join-decomposition guidance argues against paying when it can be avoided.

**Risk:** low from a correctness standpoint, but forfeits the main efficiency argument for building this feature in the first place.

---

### Design Point 3 — `Computation` semantics: chain counting vs. pagination self-re-enqueue

This is a correctness question, not a style choice, worked out against the real `Computation`/`Counter` API (`app/models/computation.rb`, `app/models/counter.rb`) and the one place it already has to coexist with self-re-enqueuing: `app/workers/subsidiary/database_extractor_consumer.rb:31-41`.

**The mechanics, established from reading the code (not an option — this is how the counters actually behave):**

- `Computation` is ONE object per job (`Computation.new("j_#{job.id}")`, `app/models/job.rb:74-76`), and its two Redis counters are a running total for the ENTIRE job — never reset between resources or stages (Finding F1 above). `done?` (`app/models/computation.rb:39-46`) is simply `queue.value == executions.value`.
- `DatabaseExtractorConsumer#perform` (`app/workers/subsidiary/database_extractor_consumer.rb:7-46`) already has to decide, on EVERY invocation, whether to call `increment_executions` — and the answer is "only on the branch that does NOT re-enqueue itself": the paginated branch (`stream.paginated?` true) re-enqueues (`Subsidiary::DatabaseExtractorConsumer.perform_async(job_id, stream_id, collection_last_id)`, line 33) and explicitly skips `increment_executions`; only the non-paginated / final-page branches (lines 35-40) call it. This is the SAME shape requirement 3 asks for (increment execution only at the true end of a chain of related invocations for one stream_id) — pagination is already "a chain that doesn't increment until its last hop."

**What follows for the dependency feature:** the "does this stream have a dependent follow-up?" check and the "trigger the follow-up instead of incrementing" branch belong at the SAME decision point pagination already occupies — the branch that currently unconditionally calls `job.computation.increment_executions` (line 35 and line 39 in the extractor; line 75 in `hierarchy/transformer_consumer.rb`). A paginated stream that ALSO has a dependent follow-up must reach its last page (pagination's own termination) before evaluating the dependency check — the two conditions compose in sequence (finish pagination, THEN check dependency), never in parallel, because the dependency's input (the full set of collected ids) is only complete once every page has been fetched.

#### Option A: check the dependency at the SAME call site pagination's `increment_executions` already lives at

Concretely: replace the unconditional `job.computation.increment_executions; NextResource::Producer.perform_async(...) if job.computation.done?` at the tail of each of the 20 host workers (and, symmetrically, the Extract-stage consumer if Design Point 1 Option A is chosen) with `if <stream has dependent> then <trigger dependent, passing collected ids> else <increment_executions as today>`.

**Pros:** minimal structural change — one `if` at an existing decision point already proven to coexist correctly with pagination; the dependency check is naturally per-stream (`stream.stream_dependents` or similar), matching requirement 1's "the dependency is declared on the CHILD."

**Cons:** the check itself (`Stream` has a dependent?) is the INVERSE of what requirement 1 stores (child points to parent) — finding "does anything depend on ME" from a stream that only stores "I depend on X" needs either a reverse Mongoid association (`has_many :dependents, class_name: 'Stream', foreign_key: :depends_on_stream_id`) or a `Stream.where(depends_on_stream_id: stream.id)` query at this call site. Either is cheap, but it is one more read on the hot path of every stream's completion.

**Risk:** low — reuses a proven branch point; the only new work is the reverse lookup.

#### Option B: a wrapper/concern shared by every `*/database_extractor_consumer.rb` and `*/transformer_consumer.rb` that owns the "increment-or-chain" decision

Extract the "increment_executions or trigger dependent" logic into one shared method (e.g. on `ApplicationWorker` or a small module), called from all 20+ sites instead of duplicating the `if` in each file.

**Pros:** one place to get the Computation/pagination/dependency interaction right instead of ~25 (20 transformer sites + the corresponding extractor sites); a bug fix or a future rule change (e.g. a second kind of terminal condition) touches one file.

**Cons:** the Code Pattern Discipline anti-pattern catalog (`~/.claude/docs/CODE-PATTERN-DISCIPLINE.md`, referenced from `~/.claude/CLAUDE.md` § Code Pattern Discipline) names "Extracted Wrapper Methods" and "Phase Extraction" among the forbidden shapes for exactly this kind of thin cross-cutting wrapper — whether a shared "finish this stream" method crosses that line is a judgment call the actual `/execute` phase would need to make against the current pattern in this codebase (each of the 25 resources already duplicates its OWN producer/consumer/transformer shape near-verbatim; that duplication is the established pattern, not an oversight — see e.g. `deal/*_consumer.rb` vs `groupification/*_consumer.rb`, structurally identical).

**Risk:** medium — right instinct (reduce 20+ copies of new logic), but needs to be weighed against the codebase's existing per-resource duplication convention before being decided; not this document's decision.

---

### Design Point 4 — the `Stream` config-model change

**The concrete fields, grounded against `app/models/stream.rb:3-127` and the form/controller pair that expose it:**

- A boolean, e.g. `field :depends_on_previous_stream, type: Boolean, default: false` (naming TBD at `/execute` time) — mirrors the existing `field :disabled, type: Boolean, default: false` (`stream.rb:17`) plus its `validates :disabled, inclusion: { in: [true, false] }` (`stream.rb:28`) and `enabled?`/`disabled?` predicate pair (`stream.rb:101-107`).
- A `belongs_to :depends_on, class_name: 'Stream', optional: true, inverse_of: :dependents` (association name chosen per `~/.claude/docs/ASSOCIATION-NAMING.md`'s no-stutter rule — `stream.depends_on`, not `stream.parent_stream`) plus the reverse `has_many :dependents, class_name: 'Stream', foreign_key: :depends_on_id, inverse_of: :depends_on` needed by Design Point 3's "does anything depend on me" check.
- A validation that the reference, when present, points to a `Stream` in the "same flow" — grounded in `Source` (`app/models/source.rb:13`, `has_many :streams`): every `Stream` already belongs to exactly one `Source`, and a `Source` is one client's connection — so "same flow" most directly maps to `depends_on.source_id == source_id`. `ResourceType` (`app/models/resource_type.rb:7`) is NOT the right scoping axis: it groups streams ACROSS sources for parallel multi-connector dispatch of the SAME step (`Hierarchy::ExtractorProducer` fetches `ResourceType.find_by(name: 'Subsidiary').streams.enabled` — deliberately spanning every connector for one step), which is orthogonal to a same-client, cross-step dependency.
- The which-field-feeds-the-follow-up question the call-site table above surfaces directly: 8 sites need `user_id`, 12 need `parent_id`, and Hierarchy needs BOTH from the same parent stream. Since requirement 1 says a `Stream` points to exactly ONE parent, Hierarchy's two enrichments (today two `connection.fetch` calls in the SAME transformer, `hierarchy/transformer_consumer.rb:20` and `:24`) become TWO separate dependent `Stream` rows, each depending on `Hierarchy`, each naming a different join-key field.

#### Option A: the join-key field name lives on the DEPENDENT stream (e.g. `field :dependency_source_key, type: String`)

The child stream stores which field of the parent's raw record supplies its input (`'user_id'` or `'parent_id'`), read by whatever triggers the follow-up (Design Point 1/3).

**Pros:** keeps the parent `Stream` completely unaware of who depends on it or why — the parent stays a plain producer of records; all dependency-specific knowledge lives on the consumer side, matching who actually needs the information at trigger time.

**Cons:** the field name is a free-text string with no validation against what the parent's raw records actually contain — a typo (`'usr_id'`) fails silently until the follow-up runs against an empty id set.

#### Option B: the parent `Stream` declares which field(s) may be exposed to a dependent, and the dependent selects among that declared list

Adds a second field on the PARENT (e.g. `field :exposed_join_keys, type: Array, default: []`), and the dependent's select in the UI only offers values from the CHOSEN parent's `exposed_join_keys`.

**Pros:** the UI select becomes self-documenting and harder to typo (a dropdown of the parent's declared keys, not free text); catches the mismatch at configuration time instead of at run time.

**Cons:** two fields to keep synchronized instead of one; for the 20-site replacement (a known, finite, already-enumerated set of parent/child/key triples), the extra validation machinery may be more structure than the immediate need — same caution Design Point 3 Option B raises about wrapper machinery introduced ahead of a second real use case (§ No Premature DRY, `~/.claude/docs/NO-PREMATURE-DRY.md`: "the Rule of Three is the MINIMUM, not the trigger").

**Cost / effort common to both options:** `Stream` model fields + 2 new `belongs_to`/`has_many` associations + `StreamsController#stream_params` allow-list update (`app/controllers/streams_controller.rb:37-54`) + `app/views/streams/_form.html.erb` gaining a scoped select input, following the exact `form.input ... collection: ...` shape already used for `resource_type_id`/`source_id` (`_form.html.erb:5-11`) + `Integrator::NORMALIZED_SCHEMA` (`config/normalized_schema.rb:4-40`) and `lib/tasks/integration/normalized/bootstrap.rake:57-90` gaining a `depends_on:`-shaped key in a schema definition hash and the corresponding `stream.depends_on = Stream.find_by(...)` assignment in the bootstrap loop, so a client's dependent streams CAN be declared through the same bootstrap path new clients already go through (registering the real production queries stays out of scope per this plan, but the bootstrap MECHANISM needing to support it is in scope).

---

### Design Point 5 — shape of the 20 transformer rewrites

#### Option A: each of the 20 files keeps its own inline enrichment code, now driven by the dependent-stream's already-extracted (Design Point 1A) or freshly-rendered (Design Point 1B) result instead of the current hardcoded call

Each transformer's `if stream.source.normalized?` branch changes from `users = connection.fetch(:users, { id: record['user_id'] }); record['user'] = users.first` to a lookup against the pre-built `id => row` hash (Design Point 1A) or the batched query result (Design Point 1B).

**Pros:** matches the codebase's existing convention exactly — every one of the 25 resources already carries its own near-identical producer/consumer/transformer trio rather than sharing one generic implementation (compare `deal/transformer_consumer.rb` and `groupification/transformer_consumer.rb`, structurally identical apart from the resource name and `_collections` association); this option changes the smallest possible surface per file and follows Pattern Priming's default (`~/.claude/CLAUDE.md` § Code Pattern Discipline: "follow the pattern... a deliberate DEVIATION is what needs a reason").

**Cons:** 20 near-identical edits to review; a mistake in one (e.g. forgetting the `.present?` guard on the 12 `parent_id` sites) is a mistake isolated to that file, not caught by a shared implementation.

**Risk:** low per-file, moderate in aggregate (20 edits to get right and review).

#### Option B: a shared helper/concern for "look up the enrichment result for this record" used by all 20 sites

**Pros:** one implementation of the id-hash-lookup logic instead of 20 (each currently ~5 lines: build/consult hash, assign to `record['user']` or `record['parent']`).

**Cons:** same Code Pattern Discipline tension as Design Point 3 Option B — the anti-pattern catalog explicitly names "Extracted Wrapper Methods" and "Per-Branch Delegation" as forbidden shapes, and this codebase's established convention is per-resource duplication, not shared cross-resource helpers, for the transformer bodies specifically. Whether 5 lines × 20 sites clears the Rule-of-Three bar for extraction (§ No Premature DRY) that Design Point 3 already had to reckon with is the same open call, now on the Transform side.

**Risk:** the technical risk is low (the logic is simple), but the PATTERN risk (deviating from an established per-resource-duplication convention without the codebase showing a precedent for a shared Transform-side helper) is the one worth flagging for `/execute` to resolve against the actual sibling files at write time, per Pattern Priming.

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| Where the follow-up executes (Design Point 1) | A: Extract-stage, own `Stream`/collection, Transform joins in Ruby / B: Transform-stage, live batched query | A matches join-decomposition and gives the follow-up its own StreamCheck; B is a smaller diff but keeps a live DB call inside Transform | ☐ |
| Follow-up query parameterization (Design Point 2) | A: batched `IN (...)` with `.to_i`-coerced ids / B: per-record `id = {{ id }}`, no batching | A removes the N+1 shape but the injection-safety coercion is a Ruby-side convention, not enforced by the template layer; B is behaviorally identical to today (same N calls), just config-driven | ☐ |
| Where the dependency check/branch lives (Design Point 3) | A: inline at the existing pagination-aware `increment_executions` call site, per file / B: shared wrapper across all 20+ consumer/transformer files | A reuses a proven branch point with minimal structural change; B centralizes the logic but runs into the same Extracted-Wrapper-Methods anti-pattern tension the codebase's per-resource convention argues against | ☐ |
| Join-key ownership on the config model (Design Point 4) | A: free-text field on the dependent naming the parent's join-key field / B: parent declares exposed keys, dependent selects from that list | A is simpler and matches the immediate 20-site need; B is more self-documenting but adds validation machinery ahead of a second confirmed use case | ☐ |
| Shape of the 20 transformer rewrites (Design Point 5) | A: each file keeps its own inline lookup, now against the dependent's result / B: one shared helper for all 20 | A matches the codebase's per-resource duplication convention; B reduces line count 20× but risks the same wrapper anti-pattern Design Point 3 Option B raises | ☐ |
| Sequencing against `4shark/integrator#2373` | Merge #2373 together with / immediately before this feature's call-site rewrite, vs. independently | Either order avoids a broken-in-between window ONLY if the 20 call sites and the `fetch` signature change land in the same release; landing #2373 alone first breaks all 20 sites until this feature's rewrite also lands | ☐ |

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| `Computation`'s queue/executions counters are a single running total for the whole job (Finding F1) — any path that increments one without eventually incrementing the other the same number of times stalls `done?` for the REST of the job, not just the current resource | High — a stalled `done?` halts the entire E→T→L chain past that point | The dependency-vs-terminal branch (Design Point 3) needs a test that exercises a chain end-to-end (queue incremented once at chain dispatch, executions incremented exactly once at chain termination) before it reaches a job that also has unrelated resources still to process |
| Pagination (`stream.paginated?`) and the dependency check both need to gate on "is this truly the last invocation for this stream_id" — composing them wrong (e.g. checking the dependency before pagination's last page) would trigger the follow-up with an incomplete id set | Medium — silently incomplete enrichment, not a crash | Design Point 3's "same call site" framing keeps the two checks sequential by construction; whichever option is chosen, the dependency check must sit strictly after the existing pagination termination check, never in parallel with it |
| Liquid-rendered SQL has no automatic escaping (`Stream#render_query`, `stream.rb:74-83`) — unlike the Sequel hash-condition builder it replaces | Medium — a future dependent stream keying on a non-integer/non-coerced value reopens an injection surface the current code does not have | Whichever Design Point 2 option is chosen, the coercion/quoting rule needs to be explicit and documented at the `Stream` model or template-building call site, not left implicit in each caller |
| `4shark/integrator#2373` merging independently of this feature (see subsumption analysis) | High for the 20 call sites specifically — they break outright, not silently | Sequence the two pieces of work together, or hold #2373 until this feature's call-site rewrite is ready to land in the same release |
| A new dependent `Stream` sharing a `ResourceType` name with an existing scheduled resource would ALSO get independently dispatched by that resource's `ExtractorProducer` unless the "dispatch only initial streams" filter (requirement 2) checks the dependency flag regardless of `ResourceType` grouping | High if missed — the follow-up would run twice: once correctly triggered by its parent, once incorrectly as an independent top-level dispatch | The `ResourceType.find_by(name:).streams.enabled.select { ready_for?(job) }` filter in every `*/extractor_producer.rb` needs an explicit "and has no `depends_on`" clause, independent of which `ResourceType` the dependent stream is filed under |

## Open questions for the engineer

- Design Point 1: does the follow-up run as a genuine Extract-stage `Stream` (Option A) or as a Transform-time batched live call (Option B)? This decides whether a new producer/consumer pair and a new `_collections`-style association are needed.
- Design Point 2: is the id list always safely coercible to integers for the streams this feature targets, or should the templating layer gain an explicit, enforced quoting/coercion step now rather than later?
- Design Point 4: does the dependent stream name its parent's join-key field freely (Option A), or does the parent declare which fields it exposes (Option B)? This also decides whether Hierarchy's two enrichments (`user_id` and `parent_id`) are modeled as two separate dependent `Stream` rows (implied by requirement 1's "one parent reference per stream") — confirming that reading is itself worth a one-line answer before `/execute` begins.
- Design Point 5: does the 20-site rewrite stay one-file-per-resource (matching the established per-resource duplication convention) or introduce a shared helper — and if shared, where does 4Shark's Rule-of-Three (§ No Premature DRY) land on 20 near-identical 5-line call sites?
- Sequencing: should `4shark/integrator#2373` be merged as part of this feature's PR (so the `fetch` signature change and its only remaining safe caller land together), or held until this feature is ready, or reworked to keep both call shapes valid during a transition window?

## Sources

- `app/models/stream.rb:3-127` — `Stream` model: existing fields, `belongs_to :resource_type`/`belongs_to :source`, `render_query`, `ready_for?`.
- `app/models/source.rb:3-64` — `Source` model: `has_many :streams`, the "same flow" scoping candidate.
- `app/models/resource_type.rb:1-17` — `ResourceType`: `has_many :streams`, the multi-connector parallel-dispatch grouping (NOT the same-flow dependency scope).
- `app/models/computation.rb:1-63` and `app/models/counter.rb:1-52` — the queue/executions Redis-counter mechanism `done?` depends on.
- `app/models/job.rb:74-76` — `Computation.new("j_#{id}")`, confirming one `Computation` per job, not per resource/stage.
- `app/workers/subsidiary/extractor_producer.rb:1-45` and `app/workers/hierarchy/extractor_producer.rb:1-40` — the producer dispatch shape requirement 2 changes.
- `app/workers/subsidiary/database_extractor_consumer.rb:1-49` — the collection-write shape and the existing pagination/`increment_executions` branch point (Design Point 3).
- `app/workers/hierarchy/transformer_consumer.rb:1-80` and `app/workers/deal/transformer_consumer.rb:1-75` — the enrichment call sites and the `increment_executions`/chain-to-next-resource tail.
- `app/workers/user/manager/transformer_consumer.rb:1-79` — verbatim confirmation of the `parent_id`-keyed enrichment shape shared by all 11 `User::*` transformers.
- `app/adapters/postgres_sql_adapter.rb:1-137` — the overloaded `fetch` method central to the PR #2373 subsumption analysis.
- `app/models/variables.rb:1-60` — the `Variables`/Liquid-variable shape already used for custom (non-normalized) query templating, the closest existing analog to Design Point 2's id-list variable.
- `config/normalized_schema.rb:1-41` and `lib/tasks/integration/normalized/bootstrap.rake:1-100` — the schema-bootstrap mechanism a dependency field needs to flow through.
- `app/controllers/streams_controller.rb:1-56` and `app/views/streams/_form.html.erb:1-21` — the existing `Stream` CRUD form/params pattern the new field(s) extend.
- `app/models/stream_check.rb:1-28`, `app/workers/job/starter.rb:1-74`, `app/workers/availability_check/producer.rb:1-42` — confirms every enabled `Stream`, dependent or not, already gets its own `StreamCheck`/availability probe independent of dispatch order.
- 4shark/integrator#2373 (`gh pr view 2373` / `gh pr diff 2373`, fetched 2026-09-04) — full diff and body preserved verbatim in `pr-2373_diff_1.md`.
- `~/.claude/CLAUDE.md` § Data Access, § Data Processing Pattern, § Code Pattern Discipline, § No Premature DRY, § Association Naming — cited inline above; full text at `~/.claude/docs/DATA-ACCESS.md`, `~/.claude/docs/DATA-PROCESSING.md`, `~/.claude/docs/CODE-PATTERN-DISCIPLINE.md`, `~/.claude/docs/NO-PREMATURE-DRY.md`, `~/.claude/docs/ASSOCIATION-NAMING.md`.
- See auxiliary: `pr-2373_diff_1.md` — verbatim PR body and diff for `4shark/integrator#2373`.
