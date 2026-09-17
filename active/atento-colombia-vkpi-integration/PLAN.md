# PLAN — VKPI Colombia integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Colombia integrator's Modifier stream. The integration consumes **two tables**: `tb_dim_indicadores_score` for the values, and `tb_dim_indicadores` (the catalogue) to resolve each score row to the 4Shark Variable it belongs to. Every other VKPI table is Atento's internal use and out of scope.

## Where this stands

On 2026-09-10 4Shark ran the structural validation against the live base (`COLBOGSQL58\MSSQL58_KPI`) twice: a first read that morning found the score table truncated (0 rows), and a second read that afternoon found it **repopulated with data** — so the BBDD reprocess (escalated as ticket **RITM2266483**, opened 03-set; Nicolás Baracaldo's 09-set reply stated the field/date changes were done and the reprocess requested) evidently ran between the two reads. The data load happened; the requested structure did not. Read against the afternoon state:

- **Structure — the two blocking requirements are still absent.** Both `tb_dim_indicadores_score` and `tb_dim_indicadores` are heaps with **no index at all** (V1 FAIL), so no unique index enforces the business grain. The catalogue has no `llave` column (V2 FAIL — only `Homologo_4shark`, `datetime` nullable at position 20). `DT_CREATED` / `DT_MODIFIED` are `datetime` on both tables (V3 PASS). `NR_ID` is `float` in score against `int` in the catalogue.
- **Uniqueness is verified absent across EVERY SQL Server mechanism, not just the index.** `INV2` (both tables heap, zero indexes) plus a follow-up check returned no trigger, no PK/UNIQUE/CHECK constraint, and no indexed view. So nothing — declarative or procedural — guarantees row uniqueness. The current data is clean at the grain (**D1 returned zero** grain duplicates), but that is a property of the truncate-and-reload with data pre-deduplicated upstream, NOT a guarantee: the next load can bring a duplicate and the base accepts it.
- **Data reconciliation — 160 orphan score rows.** D2 returned **160** rows whose `NR_ID` is absent from the catalogue; the `float`-vs-`int` `NR_ID` type mismatch plausibly produces part of them.
- **Structural diff vs the 03-ago capture** (`vkpi-schema-2026-08-03.txt`): the score table went from 16 to 26 columns and the catalogue from 17 to 20. Added to score: `RESULTADO`, `NR_ID`, `HC`/`HC_Total`, `DT_CREATED`/`DT_MODIFIED`; `NR_CHAVE_EMPRESA_MES_RE` changed `bigint` → `varchar(255)`. Added to catalogue: `DT_CREATED`, `DT_MODIFIED`, `Homologo_4shark`. So SOME requested items DID land — the single value column (`RESULTADO`) and the `datetime` create/update dates — and only two of the asks remain open: the unique index and the `llave` column.

The message carrying this reading to Santiago is in `#atento-co` (2026-09-10 17:16, Spanish), and Santiago forwarded it to Atento by email the same minute ("ya envio un correo a ellos", 17:17). That message deliberately drops the foreign key and the 160 orphans (see "The foreign key — not an agreed requirement" below) and holds only the two defensible asks. The validation queries are `vkpi-validation-queries-colombia-20260908.sql`.

On 2026-09-08 Atento (Nicolás Baracaldo, standing in for Andrés during his leave) reported the field and date adjustments were done and the reprocess was requested but not yet run. 4Shark ran a structural validation against the live base (`COLBOGSQL58\MSSQL58_KPI`) and the result contradicts that report: only the datetime columns were corrected, the three structural requirements are still unmet, and the base regressed. Both `tb_dim_indicadores_score` and `tb_dim_indicadores` are now heaps with **no index at all** — not even the surrogate PK that existed on 27-ago — so nothing enforces uniqueness anywhere. The `llave` column does not exist on the catalogue; a `Homologo_4shark` column exists but is `datetime` and nullable, so it cannot serve as the text key. There is no FK from score to catalogue, 160 score rows carry an `NR_ID` absent from the catalogue, and `NR_ID` is `float` in the score table against `int` in the catalogue — a type mismatch that plausibly produces part of those orphans. What did land: `DT_CREATED` / `DT_MODIFIED` are `datetime` on both tables. The message asking Atento to confirm whether this is a pending reprocess, a wrong base/environment, or an unapplied change is `mensaje-santi-2026-09-08-ES.txt`; the metadata validation queries are `vkpi-validation-queries-colombia-20260908.sql`.

On 2026-08-27 Atento reported the structure changes were applied. 4Shark verified against the live base (`COLBOGSQL58\MSSQL58_KPI`, score table now 3.995 rows) and the two central requirements are not present: the unique constraint sits on a sequential surrogate id instead of the business grain, and the catalogue has no `llave` column. Atento restructured the score table on its own terms (26 columns, dates as `date`), not the 22-column shape the 20-ago script delivered. Full audit and the filtered list of what 4Shark can legitimately raise: `ANALYSIS-v2.md`.

**The direction changed to the normalized base.** About a month after the base became usable (2026-07-27, when 4Shark completed its technical analysis — June and most of July were access/infra provisioning by a separate team, excluded from the count) and several rounds, the source table still does not carry what the integration consumes. The recommendation is to stop reshaping the VKPI source table and integrate from the normalized base instead — its structure is defined, 4Shark already integrates against it, and Atento's remaining work collapses to loading the data. That removes every open source-table point at once. The message carrying this to Santiago/Atento is the 2026-08-27 deliverable.

**The 20-ago delivery** (`estructura_final_vkpi_atento_colombia_20260820.sql` + roadmap PDF, 17-sep deadline to object) remains the record of what 4Shark asked for on the source-table path, should that path be revived.

On **2026-09-04**, 4Shark sent Janaína Soares (CC Estefani Pérez) a priority-request email covering the VKPI integration in México, Colômbia and Chile: it states the integration is progressing within Atento's own flows, asks Atento to prioritize the teams on the remaining points so it closes faster, and commits 4Shark to deliver within a few business days of each unblock. Full text: `email-janaina-2026-09-04-PT.txt`.

## The three sources, and what each one proves

Confusing these is the most expensive mistake available here, because each answers a different question and none of them substitutes for another.

**The live database is the current structure, and 4Shark has access to it.** `vkpi-schema-2026-08-03.txt` in this folder is the full capture, read directly from `COLBOGSQL58\MSSQL58_KPI`: the four tables, every column with type and nullability, the indexes, the foreign keys and the row counts. Read that file instead of reconnecting. Its rows are sample data and prove nothing about production volumes or values.

**The files Atento sends (`Maqueta.csv`, `Propuesta 4shark.xlsx`) are a proposal of changes, not the database.** The live score table still carries `NR_NUMERADOR` / `NR_DENOMINADOR` and the misspelled `NR_SERVIVIO_CODIGO`, and carries no unique index — though it has taken on part of the proposed shape (`RESULTADO`, `NR_ID`, `HC`/`HC_Total`, `DT_CREATED`/`DT_MODIFIED`). The full proposed shape, with its guarantees, exists only in the files. Every measurement about data — uniqueness, cardinality, value ranges, coverage — is made against the file, because that is the only place the proposed structure exists.

**A proposal is not an implementation, and that gap is what the acceptance step below closes.** When Atento reports the changes are done, 4Shark connects to the live database and verifies each one landed. Only then does the estimate follow.

**Metas are out of scope until the indicator integration is delivered.** They are a second workstream, taken up after indicators are in production. Do not analyse them, do not ask Atento about the template, do not carry them as a pending item. Atento raised the metas master table again in the 05-ago call and both sides re-deferred it.

## Position

**Atento owns the source database, so Atento fixes the source database.** Every requirement on the source is a property of a base they build and operate; none of them moves to 4Shark as a workaround.

What 4Shark contributes is the remediation itself — the SQL that creates the unique index, and the load procedure that guarantees the date semantics. The execution on their side, and the ownership, stay with Atento.

## The committed timeline

**Development runs 17-sep to 08-oct — three weeks — and both dates are in the roadmap Atento holds.** The three weeks cover preparing the environment, configuring the new Source and its mappings, and validating the values against real data before production. The 08-oct date assumes the base is in the script's structure by 17-sep; each week of delay in applying it moves delivery by the same amount, and the roadmap states that in those terms.

**Two entries precede it in the roadmap and gate the start**: the output-variables delivery on 11-sep and the Simplex cesados adjustment on 14–16 sep.

The estimate is dominated by environment work, not by the VKPI itself. The integration consumes four payload fields (`compiled_at`, `user_id`, `value`, `variable` — `modifier.rb:6-15`) that map straight onto `DT_DATA`, `NR_RE`, `RESULTADO` and `llave`, and the SQL Server adapter already exists on both `master` and `develop` (`database_source.rb:4`), so the VKPI part is Source, Stream and AttributeMapping configuration — six to nine working days. The remaining eight to twelve are the cost of carrying `develop`: getting it green, rehearsing the normalized-customer migration on a homologation base, and releasing it to the other clients.

## Requirement status

| Requirement | Where | Status |
|---|---|---|
| A row is uniquely identifiable at period + person + programa + indicator | Score table | Closed — confirmed against the supervisor case in the 05-ago call |
| A single person identifier, stable over time | Score table | Closed — `NR_RE` is the Simplex code; a document-based variant exists as fallback |
| `DT_DATA` free of day/month ambiguity | Score table | Closed — delivered as `yyyymmdd` |
| One column carrying the indicator value | Score table | Closed — `RESULTADO` is the final value; `HC` / `HC_Total` are informational |
| Per-record creation and update dates | Score table | Closed — `DT_CREATED` / `DT_MODIFIED` are `datetime` on both tables, confirmed on the live base 2026-09-10 (V3 PASS) |
| How the supervisor's value is composed | Score table | Closed — confirmed verbally in the 05-ago call |
| **The unique index on the business grain applied to the live database** | Score table | **Open — 2026-09-10 both tables are heaps with no index at all (V1 FAIL); uniqueness verified absent across index, PK, unique constraint, trigger and indexed view — nothing enforces it** |
| **A text column `llave` on the catalogue, unique and not null, holding the 4Shark Variable key** | Catalogue | **Open — confirmed absent 2026-09-10 (V2 FAIL); a `Homologo_4shark` `datetime` nullable column exists but is not the key** |
| The score table repopulated after the truncate | Atento | Closed — 2026-09-10 the reprocess (ticket RITM2266483) ran and the score table carries data again (D2 returned 160, so rows are present) |
| One catalogue row per indicator per operation | Catalogue | Closed — already true; the split lives inside `NR_ID` (see below) |
| The list of exact Variable keys, for Atento to load into `llave` | 4Shark | **Open — owed by 4Shark, blocks the catalogue load** |
| What distinguishes the 18 catalogue names that carry several `NR_ID` | Atento | **Open and not yet raised — those indicators cannot receive a key until it is answered** |
| Network reachability from the integrator to `COLBOGSQL58`, plus a read-only database user on the two tables | Atento | **Open — not yet requested; blocks the 17-sep start** |
| Every score row references an indicator that exists in the catalogue | Data reconciliation (NOT a foreign key) | Open — 2026-09-10, 160 score rows carry an `NR_ID` absent from the catalogue; `NR_ID` is `float` in score against `int` in the catalogue. Raised to Atento as a data/type reconciliation. A foreign-key CONSTRAINT is explicitly NOT a 4Shark requirement — see "The foreign key — not an agreed requirement" |
| Héctor Javier notifies Andrés and copies 4Shark on each Variable upload | Process | Open — requested 05-ago |
| Metas table | — | Out of scope — a separate workstream after indicators |

## The foreign key — not an agreed requirement

A foreign-key constraint from `tb_dim_indicadores_score` to the catalogue is **not** something 4Shark asked Atento for, and it must not be charged as a requirement. The record confirms it across every channel: the 31-jul email to Andrés lists seven points (unique key, supervisor value, person id, `DT_DATA` format, single value column, dates recommendation, metas) with no FK; the 27-ago Slack message to Santiago lists four (unique index, `llave` column, `datetime` columns, load procedure) with no FK; and no Granola meeting between 05-ago and 10-set raises a foreign key, llave foránea, or physical referential integrity. The FK first appears in the 08-set message (`mensaje-santi-2026-09-08-ES.txt`, point 3), introduced without having been agreed before.

What is legitimate — and defensible with the written record — is the **unique index** and the **`llave` column** (the `datetime` columns are already delivered). The referential-integrity concern the FK was standing in for is real, but it is a **data/type reconciliation**: the 160 orphan rows and the `NR_ID` `float`-vs-`int` mismatch go to Atento as "these rows reference indicators that do not exist; the NR_ID types differ", never as "declare a foreign key". Raising a new structural constraint mid-engagement is what makes Atento read 4Shark as forever adding asks; the two standing requirements do not.

The `V4` check in `vkpi-validation-queries-colombia-20260908.sql` still tests for the FK — kept as a diagnostic signal for the orphan/type problem, not as an acceptance gate.

## The supervisor value — closed

Andrés and Héctor explained the mechanism in the 05-ago call. For an asesor, `HC` (headcount of the programa) and `HC_Total` are both 1. For a supervisor they differ: `HC` is how many people that supervisor has in **that** programa, `HC_Total` is the total across all their programas. Atento liquidates unit by unit — it loads a programa, runs its variables, weights the result by that programa's headcount, and sums across programas to reach the month's variable pay.

**That weighting is Atento's internal calculation and produces the number they pay, not the number 4Shark loads.** Paulo confirmed in the call that 4Shark takes `RESULTADO` and nothing else: `HC` and `HC_Total` are informational, no operation is performed on them, and no additional input is required from Colombia.

A supervisor therefore carries **one score row per programa per indicator** — Andrés confirmed a supervisor gets a `calidad` row for each of their programas.

## The unique key — confirmed against the supervisor case

The key is **period + person + programa + indicator**. The supervisor case is what tested it: a supervisor carries the same indicator (`calidad`) across several service units, so the question was whether the key still identifies a row. It does, because `programa` distinguishes them — `calidad` for programa Vampiro is a different row from `calidad` for programa Islas.

**Two key variants exist on Atento's side, and the difference matters to person resolution.** `NR_CHAVE_EMPRESA_MES_RE` uses the employee code (the Simplex code the platform already receives); `NR_CHAVE_EMPRESA_MES_RE_SOPORTE` replaces it with the national identity document, for when Simplex is deactivated. 4Shark resolves people by the Simplex code today, so a switch to the document variant changes how the integrator resolves a person and is not a transparent substitution.

## How a score row resolves to a Variable

**Héctor Javier registers each Variable in the 4Shark platform, and Andrés records that Variable's key in the catalogue.** The integrator reads the score row's `NR_INDICADOR`, looks the indicator up in `tb_dim_indicadores`, takes the 4Shark key stored there, and builds the call with it. The platform already resolves a Variable this way — `Variable.get_id(company_id:, key:)` (`indicators_controller.rb:218`) — so nothing new is needed on 4Shark's side.

### Why 4Shark does not register the Variables from the catalogue

Registering Variables by reading `tb_dim_indicadores` was explored and rejected in the 05-ago LatAm alignment, after Andrés surfaced the question that breaks it: with that design, how does Héctor Javier see the Variables in order to build the rules?

The underlying problem is that the same information has to exist in both places, so one of them has to be the source of truth. If the catalogue is the source, every new Variable Héctor Javier wants requires Andrés to create it in the database first — he becomes dependent on Andrés for his own routine work. If the platform is the source, he registers as he does today and Andrés follows.

Neither direction removes the manual step; both leave someone doing something by hand. **What decides it is whose work is manual.** Andrés's side is programmatic, so extra work there is a script change. Héctor Javier's side is a person doing uploads, so every step added to him is felt on every registration. The platform stays the source of truth, which is where the original design had it.

### The consequence Héctor Javier absorbs

A supervisor's indicator is a **distinct Variable per service unit**, so `calidad` across four operations is four Variables in the platform, named to distinguish the operation. When he registers the supervisor's rules he has to select the right per-operation Variable for each one. That is more work than a single `calidad` Variable would be, and it is the cost of the platform's identity carrying no service dimension (`index_modifiers_uniqueness`, `schema.rb:1122`).

### What is no longer needed

The Variable-registration API and the `external_id` column on `variables` are dropped. Both existed only to support registering from the catalogue. Whether `external_id` should be mandatory or optional on `Variable` is moot — the column is not being added.

## Why one `llave` per catalogue row is sufficient

The platform carries no service dimension in either identity: a Variable is unique on `(company_id, key)` (`schema.rb:2573`) and a Modifier on `(company_id, compiled_at, user_id, variable_id)` (`schema.rb:1133`). The VKPI score row, by contrast, is identified by four columns — period, person, programa, indicator. `NR_SERVIVIO_CODIGO` has no destination on the platform side, so two score rows differing only in programa would resolve to the same Modifier and one would overwrite the other.

**That collision cannot occur, because the per-operation split already lives inside `NR_ID`.** Read from the live catalogue on 20-ago, `calidad` exists as ten separate records, each with its own `NR_ID` and the operation in the name:

```
491  Calidad AR      499  Calidad AR - Variable
492  Calidad BC      500  Calidad BC - Variable
493  Calidad BP      501  Calidad BP - Variable
496  Calidad CO      504  Calidad CO - Variable
498  Calidad CL      506  Calidad CL - Variable
495  Calidad PE      503  Calidad PE - Variable
494  Calidad MX      502  Calidad MX - Variable
497  Calidad ON      505  Calidad ON - Variable
511  Calidad EC      512  Calidad EC - Variable
609  CALIDAD MZ - Variable
```

Distinct `NR_ID` means distinct `llave` and distinct Variables, so a supervisor's four rows land on four Variables. The catalogue is already at the granularity the platform needs; the join `score.NR_ID → catalogue.NR_ID` is correct as it stands.

**The measurement that looks like a contradiction is not one.** In the delivered sample, 166 of the 224 `NR_ID` appear in more than one service. Those are asesor indicators: an asesor is assigned to a single programa, so the same indicator serving many programas never puts two rows on one person in one period. The sample carries no supervisor rows at all, which is why it neither shows the split nor shows a collision.

The consequence for the ask: one `llave` per catalogue row, unique and not null, is the correct and complete requirement. No programa column on the catalogue is needed.

**Eighteen catalogue names carry more than one `NR_ID`, and some of them are byte-identical — this is the open obstacle to populating `llave`.** `Puntualidad - Variable` exists as 450 and 682 with the same string; `Penalizacion - Variable` and `Productividad` carry three ids each. Two rows sharing a name still need two distinct keys, and nothing in the name tells Andrés which is which. On the platform side the same wall exists in the other direction: `index_variables_on_company_id_and_name` is unique (`schema.rb:2574`), so Héctor cannot register two Variables both called `Puntualidad - Variable` for the keys to point at.

Resolving it needs Atento to say what distinguishes each duplicate — most likely the operation, as with `calidad`, but unnamed. Until then those indicators have no key, and PASO 4's unique index rejects any attempt to give them a shared one.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are **platform configuration**, not a source requirement. The API accepts `value` as a string (`indicators_controller.rb:22-26`) and the `Variable` carries `data_type` and `calculation` (`variable.rb:45-89`); `Indicator` only delegates to it (`indicator.rb:87-92`).

One consequence to carry into Variable registration: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so the platform expects a percentage on a 0–100 scale. The VKPI values for ratio-shaped indicators sit in 0–1. Whoever registers each Variable has to look at the indicator's real scale to choose between `PercentDataType` and `NumberDataType`, or a percentage enters a hundred times smaller.

## What Atento holds

**The 20-ago delivery supersedes every piecemeal ask below.** Santiago sent two files over Slack: the roadmap PDF, carrying the delivery history and the three committed dates, and the structure script, which consolidates into one executable file what had been spread across the 29-jul, 31-jul and 05-ago messages. The script names the 17-sep deadline for objecting to the structure, and it flags two things separately from what was agreed in July — an optional index on `DT_ACTUALIZACION`, and a correction to the load procedure.

**The procedure correction is not optional and Atento was told so.** The version sent on 31-jul compares the incoming value with the stored one using `<>`, and in SQL Server that comparison against NULL is neither true nor false — an unknown condition never fires the update. One indicator arriving without a value, or the process resending an empty one, is enough to freeze that row on its previous number with nothing raised. PASO 3.3 uses the `EXCEPT` form instead, which treats NULL as comparable.

**The constrained `llave` moves work into Atento's catalogue load, and that is the point.** Because the column is NOT NULL and unique from creation, an indicator loaded without a key, or with a key already in use, is rejected by the database. What used to depend on someone remembering to close a step is now enforced on every insert.

## The 05-ago request — what Atento was told

Paulo wrote the text; Santiago sends it. It carries three things.

**The variable-registration reversal, framed as a conclusion Andrés's question produced.** The text thanks him for raising it, explains that reading the catalogue would cost Héctor Javier the autonomy he has today, and states that the previous format stands. It does not present itself as a correction of the 03-ago email.

**The structural ask — one column.** `tb_dim_indicadores` needs a text column named `llave` holding the exact key each Variable was registered with in 4Shark, **unique** (two rows sharing a key means two indicators resolving to one Variable, and the load overwrites silently) and **not null** (an indicator without a key cannot be integrated).

**The parallel work — the score-table changes are still not applied.** The text states that 4Shark checked the live base and found `NR_NUMERADOR` / `NR_DENOMINADOR` still present with no single result column, no creation and update dates, no unique index on the key, and `NR_SERVIVIO_CODIGO` still misspelled. It frames this as work that can start immediately without waiting for anything, and names the consequence of not starting: testing stops at the base and the calendar slips by however long the application takes.

## Acceptance — what happens when Atento says it is done

Atento's report closes nothing on its own. When they state the script ran, connect to `COLBOGSQL58\MSSQL58_KPI` and verify against the live database, the same way the current structure was captured. Every check is a query; none of them is a question.

**PASO 5 of the script is that verification and it is theirs to run**, so the fastest path is asking for its two outputs: the 22 columns all present, and the three indexes — the composite unique on the score table, the one on `DT_ACTUALIZACION`, and `UX_indicadores_llave` on the catalogue. Re-run them here rather than accepting the report.

**PASO 5 proves the structure and says nothing about the data, because both tables are empty when it runs.** Everything about content is verified later, against what Atento reloads: that every score row's indicator exists in the catalogue, that the composite key holds no duplicates, and that `RESULTADO` carries the value the integration expects. `NR_NUMERADOR` / `NR_DENOMINADOR` are not checked at all — the script deliberately leaves those columns, since removing them is Atento's decision.

A check that fails goes back to Atento naming exactly which one and what the query returned.

## Phases

**Phase 0 — Atento truncates, runs the script, and reloads both tables.** It does not gate the estimate, which is already issued, nor the start of the build on 17-sep. It gates the testing, which is the second half of the three weeks: until the reload happens the integration has nothing to read. Duration is Atento's, not ours — and 4Shark owes them the list of Variable keys before their catalogue load can satisfy the `llave` constraint.

**Phase 1 — Indicators, agents and supervisors together.** A second non-normalized Source pointing at the VKPI server plus a Modifier stream on the existing Colombia integrator (stack `co`, root mode). Supervisors are no longer a separate phase: their rows arrive pre-calculated in `RESULTADO` like an asesor's, so the same stream carries both.

**Phase 2 — Metas.** Deferred; retaken after indicators close. Consumes `/goals`, never `/indicators`.

## Validation 4Shark owes itself before estimating Phase 1

Cross the 3,535 distinct `NR_RE` in the sample against the Colombia normalized base. The integrator runs in root mode, so an `NR_RE` that does not resolve is a rejected row. The identifier itself is settled — `NR_RE` is the Simplex code the platform already receives, and the data corroborates it: a 4-to-6-digit internal code ranging 3,433 to 129,053, distinct from the document in every row, 1:1 with it, none empty. What remains is confirming they all resolve to existing users, which is a query, not a question.

## Decisions that belong to 4Shark

**Negative indicator values.** 272 rows are negative, 267 of them NPS. Accept them — the Modifier value is signed and NPS is negative by definition of the metric.

**Terminated employees.** 1,409 rows carry a termination marker. Import them. A person terminated mid-month still earns commission for that month, and excluding their indicators produces a wrong final settlement — on the one payment that cannot be corrected afterwards.

**Whether to still ask for catalogue timestamps.** Creation and update dates on `tb_dim_indicadores` were requested in the 03-ago email to support incremental reading during Variable registration. With registration reverted to the platform, that purpose is gone and the 05-ago text dropped the ask. Reinstating it would cost credibility on the one column that matters.

**When to raise the per-operation catalogue split.** It is open and unstated (see above). Folding it into a follow-up costs one more round-trip with Andrés; leaving it costs a silent collision on every supervisor once the load runs.

## Working rhythm

Andrés asked to be contacted directly rather than waiting for the Friday sync on anything that cannot wait, so nothing here queues behind it.

## Draft — the score stream queries, for execution

Confirmed against the live base on 2026-09-14: the score table carries every column the integration reads (`RESULTADO`, `NR_RE`, `DT_DATA`, `DT_MODIFIED`), and its single-column primary key is `NR_CHAVE_EMPRESA_MES_RE` — `varchar(255)`, NOT NULL. That primary key is a unique index, and the column is **1:1 with the business grain**: across the whole base, `COUNT(*) = COUNT(DISTINCT NR_CHAVE_EMPRESA_MES_RE) = COUNT(DISTINCT (DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID)) = 33,079`, so the unique index on the key enforces grain-uniqueness in practice and there is no duplicate grain. The uniqueness requirement is met by this index — not by an index on the four grain columns, which is the literal shape `V1` looks for and does not find.

**This is the outcome of the 2026-09-11 meeting, not a workaround to reconcile after the fact.** 4Shark recommended the composite unique index on the four grain columns; Atento (Nicolás Baracaldo, standing in for Andrés) did not adopt it. Instead they build a concatenated key column — period + person (RE) + service + indicator, hyphen-joined — which is `NR_CHAVE_EMPRESA_MES_RE`, and place the unique index on that single column. In the meeting Nicolás first described deduplicating by hand before load; 4Shark pushed for the unique index on the concatenated column so a duplicate load violates the constraint instead, and he agreed. His email states the unique index "over the business key that carries period + person + service + indicator" is already executed, and the live base confirms it (PK, unique, 1:1 with the grain). Because the concatenation is exactly the grain fields, the index is deterministic on the grain and cannot drift the way Mexico's row-hash `NK_KEY` did (that one folded a surrogate id into the hash and so was grain-vacuous). The one item that formalizes it: Nicolás owes an email documenting the dedup method, and a control-point meeting is set for Tuesday 12:00 Colombia; the data already shows the guarantee holding.

There is **no** IDENTITY column. That single-column unique key is the pagination cursor: keyset pagination needs a unique, ordered column, not an auto-increment, so `NR_CHAVE_EMPRESA_MES_RE` serves. Because it is text, the cursor comparison is lexical and quoted, the only difference from the numeric `id` shape the normalized bootstrap generates (`lib/tasks/integration/normalized/sql_server/bootstrap.rake:71-82`).

These are the DRAFT `Stream` templates for the score table, to be finalized at execution time (they still need the catalogue join that carries `llave` into `variable` — the `llave` column does not yet exist on `tb_dim_indicadores`, so the join half waits on Atento; the pagination half below is settled):

`query_template` (first page):

```sql
SELECT NR_CHAVE_EMPRESA_MES_RE, NR_RE, DT_DATA, RESULTADO, NR_ID
FROM dbo.tb_dim_indicadores_score
WHERE DT_MODIFIED >= '{{ fetch_since }}'
ORDER BY NR_CHAVE_EMPRESA_MES_RE
OFFSET 0 ROWS FETCH NEXT {{ page_size }} ROWS ONLY
```

`paginated_query_template` (subsequent pages):

```sql
SELECT NR_CHAVE_EMPRESA_MES_RE, NR_RE, DT_DATA, RESULTADO, NR_ID
FROM dbo.tb_dim_indicadores_score
WHERE DT_MODIFIED >= '{{ fetch_since }}' AND NR_CHAVE_EMPRESA_MES_RE > '{{ previous_record_id }}'
ORDER BY NR_CHAVE_EMPRESA_MES_RE
OFFSET 0 ROWS FETCH NEXT {{ page_size }} ROWS ONLY
```

`Stream` fields: `primary_key = 'NR_CHAVE_EMPRESA_MES_RE'`; `page_size` = the integrator's `SQL_PAGE_SIZE`. The loop is the keyset walk of `Modifier::DatabaseCollectionExtractorConsumer` (`app/workers/modifier/database_collection_extractor_consumer.rb:31`): the extractor reads `primary_key` off the last row and feeds it into `{{ previous_record_id }}`, and the `> '...'` predicate advances the page.

**The score→catalogue join is `score.NR_ID = catalogue.NR_ID`** — settled against the live base 2026-09-14: that join returns 0 orphans across 33,079 rows, while `score.NR_INDICADOR = catalogue.NR_ID` orphans every row because `NR_INDICADOR` is NULL throughout the score table. The `BLUEPRINT.md` names `NR_INDICADOR` as the join column, which the data contradicts. `variable` therefore maps from `catalogue.llave` reached by `score.NR_ID = catalogue.NR_ID` — once the `llave` column exists.

The catalogue `tb_dim_indicadores` is a heap with no index at all (2026-09-14), so nothing guarantees `NR_ID` is unique in it; a duplicate `NR_ID` there fans out the join and duplicates the value. `V2b` in the validation set tests for a unique index on `catalogue.NR_ID`, which the `llave` load must add alongside the `llave` column.

The full re-validation set — structure (INV1–3, V1–V4, VAL1), pagination cursor (P1–P2), join resolution (J1–J2), and the data checks (D1–D2) — is `vkpi-validation-queries-colombia-20260914.sql`, superseding the 09-08 file. Run it whole against `COLBOGSQL58\MSSQL58_KPI` before responding to Atento. V1 reports FAIL only because it looks for the unique index on the four grain columns; the unique index that exists (on `NR_CHAVE_EMPRESA_MES_RE`, 1:1 with the grain) satisfies the uniqueness requirement.

**The catalogue key is loaded, in `NM_INDICADOR_EN_EL_PAIS`, not in a column named `llave`.** Nicolás's 2026-09-14 email confirms it and the live base agrees: `tb_dim_indicadores.NM_INDICADOR_EN_EL_PAIS` carries the 4Shark key for all 750 indicators, zero null/blank, 750 distinct values — one key per indicator, complete. Values are `<slug>_<NR_ID>` (`venta_cantada_478`, `productividad_diaria_480`). So `V2` reports FAIL only because it looks for a column literally named `llave`; the key exists under a different column, exactly as with V1's index. The `variable` mapping therefore reads `catalogue.NM_INDICADOR_EN_EL_PAIS`, reached by `score.NR_ID = catalogue.NR_ID`.

Both structural asks Atento owed — the unique index and the catalogue key — are delivered as of 2026-09-14. The one item left is an alignment, not a structure gap: confirm that the key strings in `NM_INDICADOR_EN_EL_PAIS` match exactly the keys Héctor's team registered each Variable with in the platform, so every indicator resolves to its Variable. That is the subject of the Tuesday control-point session. Two lower-priority notes stay on record: `NR_NUMERADOR`/`NR_DENOMINADOR` are still present alongside `RESULTADO` (VAL1; their removal is Atento's decision, the integration reads `RESULTADO`), and the catalogue is a heap with no unique index on `NR_ID` or on the key column (V2b) — the data is unique today but nothing enforces it, so a duplicate would fan out the join.

## Staging validation on atento-co-staging (execution)

The source structure is delivered and verified against the live base (2026-09-14): the unique index and the catalogue key are both in place. The build-and-test now runs on the `atento-co-staging` integrator, following the playbook proven on `atento-mx-staging` (`../integrator-develop-release-validation/PLAN.md`). The develop image is already deployed to `atento-co-staging` (staging images build from `develop`). Steps, in order — each mutation is an engineer-gated action:

1. **Bring the integrator up.** MongoDB running; web and worker scaled to 1 (the Terraform counts rest at 0; a manual run needs 1 of each). `bash ~/.claude/scripts/ecs-scale.sh` per service.
2. **Base hygiene — check for junk.** Inspect the staging Mongo for stale data left by prior runs. If it carries `master`-era `Resource`/`Collection` documents, reset it: wipe every collection except the primary `Account` and `data_migrations`, and flush the deployment's Redis database (the pre-flight → mutation → verification shape of `SCRIPT-DISCIPLINE.md`, `delete_all` the justified exception).
3. **Link the Account.** Verify `Account.primary` exists and points at the intended 4Shark backend company; if absent, create it by hand in the console with the staging API endpoint and token (the engineer supplies both; the token is typed in the console, never pasted into a chat).
4. **Configure the VKPI source.** Create the non-normalized `DatabaseSource` (VKPI host, `normalized: false`, `resources: ['Modifier']`) plus the `Modifier` `Stream` with the query drafts above, the five `AttributeMapping`s (§ The mapping), and the availability probe.
5. **Run and test.** `integration:start`; the `Modifier` stream extracts, transforms and builds one API request per record; validate that the indicators land in the backend for a known set of people and reconcile against the source for one period.

**End-to-end integration is achieved and validated on `atento-co-staging`.** A full run — source fetch → Modifier transform → per-record API load — completes cleanly and the indicators reach the backend. The build-and-configure work of steps 1–5 is done; the engagement now moves from "does it run" to "is the data right and is it fast enough". That is the phase below.

## Data validation and performance (current phase)

The end-to-end path works, so the open work is three parallel workstreams on the data it produces and the speed it runs at. None of these is a source-structure gap — those are closed (§ the score-stream and catalogue-key sections above); these are about the result of the run.

**Data correctness — did the values land the way they were expected to.** Reconcile the loaded indicators against the source for full periods, not just a known sample: every `RESULTADO` in the score table resolves to a backend Modifier for the right person, period, programa and indicator, with the value intact. The score→catalogue join (`score.NR_ID = catalogue.NR_ID`, key in `NM_INDICADOR_EN_EL_PAIS`) carries the Variable key, so a mismatch there surfaces as a wrong or missing Variable. The supervisor path is the one to watch — the sample carried no supervisor rows, so the first real load is where the per-operation `NR_ID` split gets confirmed rather than reasoned about.

**Flow errors — surface and classify every failed request.** A run reports `successful_requests_quantity` / `failed_requests_quantity` on the Job; any non-2xx is audited through the embedded `Imports → Requests` trail (response status + body) the way `/integration-debug` does. The two failure classes seen earlier in this integration are the ones to rule out first: a subsidiary-mode mismatch (HTTP 400 "Use subsidiary scoped api" — the CO company must stay in root mode, `SUBSIDIARIES_MODULE=false`) and an `Account.api_token` decrypt failure. A clean run is zero failed requests, not "mostly 2xx".

**Performance — the CPU-bound worker on a fractional vCPU.** The heavy phase is the VKPI Modifier compute, which is CPU-bound and runs on a `0.5 vCPU` worker under the Ruby GIL, so the run is bounded by CPU, not by memory or the send phase. The first performance lever is the Sidekiq thread count: reduced from 30 to 10 (terraform PR #1171, applied and merged 2026-09-16) because Sidekiq's own guidance reads a pegged-100% CPU as the signal to *lower* concurrency, not raise it. The measurement of whether 10 threads shortens the run against the 30-thread baseline, plus the oversubscription/throttling detail, lives in `../integrator-co-staging-thread-tuning/ANALYSIS.md`.

## Risks

**The access request never being made is the risk closest to the calendar.** Network reachability from the integrator to `COLBOGSQL58` and a read-only database user are not database structure, so they are absent from both the script and the roadmap; nothing Atento holds tells them to prepare either, and without both the 17-sep start does not happen.

A second risk is the reload after the truncate. The script leaves both tables empty by design, so testing cannot start until Atento repopulates them — and nothing on 4Shark's side can substitute for that or estimate how long it takes. It is the one dependency where a delay translates directly into idle days inside the three weeks.

A third risk is accepting a report in place of a verification. The acceptance section exists precisely because a reported change and an applied change are different facts.

A third risk is `develop`: the normalized-customer migration has not been rehearsed against a homologation base, and it carries the eight-to-twelve-day half of the estimate.

A fourth risk is the supervisor case reaching production untested. The sample Atento delivered carries no supervisor rows at all, so nothing in it exercises the path where a person holds the same indicator concept across several operations. The catalogue's own split by `NR_ID` is what makes that path correct, and it has been reasoned about rather than observed — the first load that includes supervisors is where it gets confirmed.
