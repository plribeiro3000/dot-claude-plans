# PLAN — VKPI Colombia integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Colombia integrator's Modifier stream. The integration consumes **two tables**: `tb_dim_indicadores_score` for the values, and `tb_dim_indicadores` (the catalogue) to register the Variables those values resolve to. Every other VKPI table is Atento's internal use and out of scope.

## The three sources, and what each one proves

Confusing these is the most expensive mistake available here, because each answers a different question and none of them substitutes for another.

**The live database is the current structure, and 4Shark has access to it.** `vkpi-schema-2026-08-03.txt` in this folder is the full capture, read directly from `COLBOGSQL58\MSSQL58_KPI`: the four tables, every column with type and nullability, the indexes, the foreign keys and the row counts. Read that file instead of reconnecting. Its rows are sample data and prove nothing about production volumes or values.

**The files Atento sends (`Maqueta.csv`, `Propuesta 4shark.xlsx`) are a proposal of changes, not the database.** They show what Atento intends `tb_dim_indicadores_score` to look like after their work. Every measurement about data shape — uniqueness, cardinality, value ranges, coverage — is made against the file they sent, because that is the only place the proposed structure exists.

**A proposal is not an implementation, and that gap is what the acceptance step below closes.** When Atento reports the changes are done, 4Shark connects to the live database and verifies each one landed. Only then does the estimate follow.

**Metas are out of scope until the indicator integration is delivered.** They are a second workstream, taken up after indicators are in production. Do not analyse them, do not ask Atento about the template, do not carry them as a pending item — the only correct answer on metas is that they come later.

## Position

**Atento owns the source database, so Atento fixes the source database.** Every requirement on the source is a property of a base they build and operate; none of them moves to 4Shark as a workaround. Compensating on our side for a key that does not identify a row would make 4Shark permanently responsible for a structure it does not control, and would hide the defect instead of closing it.

What 4Shark contributes is the remediation itself — the SQL that creates the unique index, and the load procedure that guarantees the date semantics — plus, now, taking the Variable registration off Atento's hands entirely. Handing over working code and absorbing a manual step removes the last reason for the corrections not to land; the execution on their side, and the ownership, stay with Atento.

## Gate

**No effort estimate and no delivery date are issued until the requirements are verified applied in the live database.** A confirmation that the work will be done is not the same fact: between intent and implementation an obstacle can appear that leads Atento to solve it another way, and an estimate given against the intent stops being valid the moment we connect.

The commitment stands and is honored: the roadmap is delivered, structured by phases whose durations count from the date the requirements close rather than from an absolute calendar.

## Requirement status

| Requirement | Where | Status |
|---|---|---|
| A row is uniquely identifiable at period + person + service + indicator | Score table | Closed — Atento's 02-ago proposal is date + simplex code + programa + indicator, exactly the granularity required |
| A single person identifier, stable over time | Score table | Closed — `NR_RE` is the Simplex code, confirmed in the 29-jul call and consistent with the data |
| `DT_DATA` free of day/month ambiguity | Score table | Closed — delivered as `yyyymmdd` |
| One column carrying the indicator value | Score table | Closed — `RESULTADO` |
| Per-record creation and update dates | Score table | Closed — `DT_CREATED` / `DT_MODIFIED` added to their internal process |
| How the supervisor's value is composed | Score table | Awaiting one confirmation — Atento states the rows now follow the asesor standard; see below |
| Creation and update dates on the catalogue | Catalogue | Requested 03-ago |
| A unique identifier column on the catalogue, with a unique index | Catalogue | Requested 03-ago |
| One catalogue row per indicator per operation | Catalogue | Requested 03-ago |
| Every score row references an indicator that exists in the catalogue | Process | Requested 03-ago |
| Metas table | — | Out of scope — a separate workstream after indicators are delivered |

## The supervisor value — what is still owed

Atento's 02-ago reply states *"se agregó a la base los resultados del supervisor cumpliendo los mismos estándares del asesor"*. That is exactly the solution 4Shark proposed: the supervisor's row arrives like an asesor's, carrying the supervisor's own identifier and the value already resolved.

The data is what keeps it from being closed outright. On asesor rows `HC` and `HC_Total` are 1 in all 34,348 of them; on supervisor rows both vary (1–38 and 1–33) across 4,167 rows, and `RESULTADO` equals `HC / HC_Total` in only 21 of them. Under a true "same standard as asesor" those columns would not vary.

So the open item is a single yes/no: is `RESULTADO` already the final performance value for the supervisor too, with `HC` / `HC_Total` informational? A one-sentence confirmation closes it with no change to the base.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are **platform configuration**, not a source requirement. The API accepts `value` as a string (`indicators_controller.rb:22-26`) and the `Variable` carries `data_type` and `calculation` (`variable.rb:45-89`); `Indicator` only delegates to it (`indicator.rb:87-92`).

One consequence to carry into Variable registration: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so the platform expects a percentage on a 0–100 scale. The VKPI values for ratio-shaped indicators sit in 0–1. Whoever registers each Variable has to look at the indicator's real scale to choose between `PercentDataType` and `NumberDataType`, or a percentage enters a hundred times smaller.

## How a score row resolves to a Variable

**4Shark registers the Variables itself, through a new API, reading Atento's catalogue.** The integration reads `tb_dim_indicadores`, creates in the platform each Variable that does not yet exist, stores the catalogue's own identifier as that Variable's `external_id`, and only then consumes `tb_dim_indicadores_score`. Registering from the catalogue also removes a failure the manual flow carries: a score row whose Variable nobody remembered to create, leaving the load silently incomplete.

**The identifier column is Atento's to name.** Today it would be `NR_ID`, but the requirement is a unique identifier guaranteed by an index, not that specific column — asserting which column they use internally is a claim 4Shark cannot make.

This makes `Variable` conform to a pattern the platform already applies to every integrable entity, rather than inventing a special case. `clients` (`schema.rb:290`), `groups` (`:928`), `payment_types` (`:1242`), `products` (`:1702`), `roles` (`:1943`) and `subsidiaries` (`:2153`) each carry an `external_id` with a unique index per company, a `get_id(company_id:, external_id:)` resolver, `rescue_unique_constraint` on that index, and a `<table>.cid.N.eid.X` cache key (`product.rb:16-36`, `role.rb:17-28`). Each also has its own controller under `app/controllers/api/v3/`. `Variable` has neither the column nor a controller — it is the outlier, not the exception.

The `NR_ID` fits the existing format constraints unchanged: a plain integer in the range 66–741, well inside `Product`'s `/\A[a-zA-Z0-9_-]*\z/` and `Role`'s `/\A[A-Za-z0-9]*\z/`, both capped at 30 characters.

**No foreign key is needed on the source.** With the catalogue identifier stored as `external_id`, the integrator resolves the Variable straight from the score row and never reads the catalogue at load time; the catalogue is consulted only when registering Variables. The relation `tb_dim_indicadores_score.NR_INDICADOR` → `tb_dim_indicadores.NR_ID` is logical only — no foreign key, primary key, index or unique constraint exists on any of the four VKPI tables (`vkpi-schema-2026-08-03.txt`, queries 3 and 4, both empty) — and that stays acceptable, provided the referential guarantee holds by process.

### Why the service dimension needs one catalogue row per operation

The platform's identity is `(company, compiled_at, user, variable)` with no service in it (`index_modifiers_uniqueness`, `schema.rb:1122`), while 166 of the 224 `NR_ID` in the delivered sample appear in more than one service (2,461 distinct service+indicator pairs). Without the split, one person carrying the same indicator in two operations in one period resolves to a single Variable and the second value overwrites the first, silently.

Split per operation, each pair gets its own Variable and the problem does not exist. A consequence worth carrying into the integrator: `NR_SERVIVIO_CODIGO` stays on the score row but is no longer needed to resolve the Variable, because the catalogue identifier already encodes operation and indicator together.

### What 4Shark decides on its own side

Whether `external_id` is mandatory on `Variable`, matching the six siblings, or optional and owned by the integration when present. Mandatory breaks the front-end registration flow every other client uses today. This changes the API's design, not what is asked of Atento.

## Correspondence — what Atento has been told

The 31-jul email listed two open points: the unique key and the supervisor's value. Atento's 02-ago reply addresses both — the key with a proposal that meets the required granularity, the supervisor with the claim that the rows now follow the asesor standard.

The 03-ago reply (thread `19faa09227fa81f6`, message `19fc9833c2406fe3`) reconciles that board and introduces the catalogue requirements. **It frames the Variable registration as an improvement 4Shark identified and is absorbing, not as a gap that was missed.** That framing is deliberate and load-bearing: what was agreed in point 4 of the 28-jul document is that Atento registers each Variable in the platform; 4Shark is now taking that over, and the catalogue requirements are the counterpart of a manual task being removed from their team. Presenting it as an oversight would be both inaccurate — the internal shape of their catalogue was never 4Shark's to audit — and needlessly costly.

## Acceptance — what happens when Atento says it is done

Atento's report closes nothing on its own. When they state the changes are applied, connect to `COLBOGSQL58\MSSQL58_KPI` and verify each one against the live database, the same way the current structure was captured. Every check below is a query; none of them is a question.

**On the catalogue `tb_dim_indicadores`:** the creation and update date columns exist; a unique index exists on the identifier column; no identifier value repeats; the number of rows matches the number of distinct indicator+operation pairs.

**On the score table `tb_dim_indicadores_score`:** the composite key (date, person, operation, indicator) has zero duplicates; `DT_CREATED` and `DT_MODIFIED` are present and populated.

**Across both:** zero score rows whose indicator does not exist in the catalogue.

**Plus the supervisor answer in writing** — the yes/no on `RESULTADO`, which is correspondence rather than a query.

When every check passes, the gate opens and the estimate follows. A check that fails goes back to Atento naming exactly which one and what the query returned.

## Phases

**Phase 0 — Remediation by Atento, verified by 4Shark.** Atento applies the catalogue changes and answers the supervisor question. 4Shark runs the acceptance checks above against the live database. Phase 0 closes when they all pass. Duration is Atento's, not ours.

**Phase 1 — Agent-level indicators.** A second non-normalized Source pointing at the VKPI server, the new Variable-registration API, and a Modifier stream on the existing Colombia integrator (stack `co`, root mode). Estimated once Phase 0 closes.

**Phase 2 — Supervisor coverage.** Depends on the supervisor rows arriving pre-accumulated, which Atento states is already the case.

**Phase 3 — Metas.** Deferred; retaken after indicators close. Consumes `/goals`, never `/indicators`.

## Validation 4Shark owes itself before estimating Phase 1

Cross the 3,535 distinct `NR_RE` in the sample against the Colombia normalized base. The integrator runs in root mode, so an `NR_RE` that does not resolve is a rejected row. The identifier itself is settled — Andrés confirmed in the 29-jul call that `NR_RE` is the Simplex code the platform already receives, and the data corroborates it: a 4-to-6-digit internal code ranging 3,433 to 129,053, distinct from the document in every row, 1:1 with it, none empty. What remains is confirming they all resolve to existing users, which is a query, not a question.

## Decisions that belong to 4Shark

**Negative indicator values.** 272 rows are negative, 267 of them NPS. Accept them — the Modifier value is signed and NPS is negative by definition of the metric.

**Terminated employees.** 1,409 rows carry a termination marker. Import them. A person terminated mid-month still earns commission for that month, and excluding their indicators produces a wrong final settlement — on the one payment that cannot be corrected afterwards.

**Supervisor scope in Phase 1.** Whether supervisor coverage is contractually required in the first delivery decides whether it gates Phase 1 or only Phase 2. Engineer and commercial, not technical.

**`external_id` mandatory or optional on `Variable`.** Open; see above.

## Risks

The dominant risk is schedule pressure converting into a premature estimate. Atento has asked for effort and dates before the source is integrable, and the pressure will repeat. The mitigation is the gate above, held consistently and stated constructively: 4Shark wants to build, has said what is missing, is supplying the code, and is absorbing the Variable registration — the remaining step is theirs.

A second risk is accepting a report in place of a verification. The acceptance section exists precisely because a reported change and an applied change are different facts, and only the second one supports an estimate.
