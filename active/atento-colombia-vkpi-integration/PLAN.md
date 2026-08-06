# PLAN — VKPI Colombia integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Colombia integrator's Modifier stream. The integration consumes **two tables**: `tb_dim_indicadores_score` for the values, and `tb_dim_indicadores` (the catalogue) to resolve each score row to the 4Shark Variable it belongs to. Every other VKPI table is Atento's internal use and out of scope.

## Where this stands

One structural item is open, and it is the last one: a `llave` column on the catalogue holding the 4Shark Variable key. Everything else on the score table is either closed or already proposed by Atento and awaiting application to the live database.

**Confirmation from Atento is what starts the build.** No code is written before it, because building against a shape they have not agreed to is work that may be thrown away.

## The three sources, and what each one proves

Confusing these is the most expensive mistake available here, because each answers a different question and none of them substitutes for another.

**The live database is the current structure, and 4Shark has access to it.** `vkpi-schema-2026-08-03.txt` in this folder is the full capture, read directly from `COLBOGSQL58\MSSQL58_KPI`: the four tables, every column with type and nullability, the indexes, the foreign keys and the row counts. Read that file instead of reconnecting. Its rows are sample data and prove nothing about production volumes or values.

**The files Atento sends (`Maqueta.csv`, `Propuesta 4shark.xlsx`) are a proposal of changes, not the database.** The live score table still carries `NR_NUMERADOR` / `NR_DENOMINADOR` and the misspelled `NR_SERVIVIO_CODIGO`, has no `DT_CREATED` / `DT_MODIFIED`, and carries no unique index. The proposed shape exists only in the files. Every measurement about data — uniqueness, cardinality, value ranges, coverage — is made against the file, because that is the only place the proposed structure exists.

**A proposal is not an implementation, and that gap is what the acceptance step below closes.** When Atento reports the changes are done, 4Shark connects to the live database and verifies each one landed. Only then does the estimate follow.

**Metas are out of scope until the indicator integration is delivered.** They are a second workstream, taken up after indicators are in production. Do not analyse them, do not ask Atento about the template, do not carry them as a pending item. Atento raised the metas master table again in the 05-ago call and both sides re-deferred it.

## Position

**Atento owns the source database, so Atento fixes the source database.** Every requirement on the source is a property of a base they build and operate; none of them moves to 4Shark as a workaround.

What 4Shark contributes is the remediation itself — the SQL that creates the unique index, and the load procedure that guarantees the date semantics. The execution on their side, and the ownership, stay with Atento.

## Gate and the committed timeline

**No effort estimate is issued until Atento confirms they can work with the agreed shape.** A confirmation of intent is not an applied change, but it is enough to start: the estimate follows the confirmation, and the code is tested against the database once the changes are actually applied.

The timeline communicated to Atento on 05-ago, and therefore binding:

**On their confirmation** — the estimate of effort and the code delivery date, the same day or at the latest the next. **After the code is delivered** — testing against the real base, one to two days if nothing unexpected surfaces, then release for daily running.

**Internal working figure: one to two weeks, possibly less.** Stated by Paulo in the 05-ago LatAm alignment on the basis that the integration consumes one score table plus a catalogue lookup. It is a planning number, not the estimate, and it is not communicated before the analysis that produces the real one.

## Requirement status

| Requirement | Where | Status |
|---|---|---|
| A row is uniquely identifiable at period + person + programa + indicator | Score table | Closed — confirmed against the supervisor case in the 05-ago call |
| A single person identifier, stable over time | Score table | Closed — `NR_RE` is the Simplex code; a document-based variant exists as fallback |
| `DT_DATA` free of day/month ambiguity | Score table | Closed — delivered as `yyyymmdd` |
| One column carrying the indicator value | Score table | Closed — `RESULTADO` is the final value; `HC` / `HC_Total` are informational |
| Per-record creation and update dates | Score table | Closed in the proposal — `DT_CREATED` / `DT_MODIFIED` |
| How the supervisor's value is composed | Score table | Closed — confirmed verbally in the 05-ago call |
| **The proposed score-table shape applied to the live database** | Score table | **Open — requested 05-ago as parallel work** |
| **A text column `llave` on the catalogue, unique and not null, holding the 4Shark Variable key** | Catalogue | **Open — the last structural item, requested 05-ago** |
| One catalogue row per indicator per operation | Catalogue | **Open and not yet requested — see below** |
| Every score row references an indicator that exists in the catalogue | Process | Open — load-bearing, the integrator reads the catalogue on every load |
| Héctor Javier notifies Andrés and copies 4Shark on each Variable upload | Process | Open — requested 05-ago |
| Metas table | — | Out of scope — a separate workstream after indicators |

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

## The gap the 05-ago request does not close

**One `llave` per catalogue row gives one key per `NR_ID`, and one `NR_ID` spans several operations.** The catalogue carries no service or programa column (`vkpi-schema-2026-08-03.txt`, query 2 — 17 columns, none of them a service), so a row is per indicator only. In the delivered sample, 166 of the 224 `NR_ID` appear in more than one service, across 2,461 distinct service+indicator pairs.

The consequence: a supervisor with `calidad` in four operations needs four Variables, but the join `score.NR_INDICADOR → catalogue.NR_ID` returns one key for all four. They collapse onto a single Variable and one value overwrites the others silently — the exact failure the unique index on `llave` exists to prevent, arriving through a different door.

**Closing it needs one catalogue row per indicator per operation, each with its own `NR_ID` and its own `llave`.** That was item 3 of the 03-ago email and it was neither withdrawn nor resolved. The 05-ago request went out without restating it, so it is open on both sides: unstated to Atento, and unresolved here.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are **platform configuration**, not a source requirement. The API accepts `value` as a string (`indicators_controller.rb:22-26`) and the `Variable` carries `data_type` and `calculation` (`variable.rb:45-89`); `Indicator` only delegates to it (`indicator.rb:87-92`).

One consequence to carry into Variable registration: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so the platform expects a percentage on a 0–100 scale. The VKPI values for ratio-shaped indicators sit in 0–1. Whoever registers each Variable has to look at the indicator's real scale to choose between `PercentDataType` and `NumberDataType`, or a percentage enters a hundred times smaller.

## The 05-ago request — what Atento was told

Paulo wrote the text; Santiago sends it. It carries three things.

**The variable-registration reversal, framed as a conclusion Andrés's question produced.** The text thanks him for raising it, explains that reading the catalogue would cost Héctor Javier the autonomy he has today, and states that the previous format stands. It does not present itself as a correction of the 03-ago email.

**The structural ask — one column.** `tb_dim_indicadores` needs a text column named `llave` holding the exact key each Variable was registered with in 4Shark, **unique** (two rows sharing a key means two indicators resolving to one Variable, and the load overwrites silently) and **not null** (an indicator without a key cannot be integrated).

**The parallel work — the score-table changes are still not applied.** The text states that 4Shark checked the live base and found `NR_NUMERADOR` / `NR_DENOMINADOR` still present with no single result column, no creation and update dates, no unique index on the key, and `NR_SERVIVIO_CODIGO` still misspelled. It frames this as work that can start immediately without waiting for anything, and names the consequence of not starting: testing stops at the base and the calendar slips by however long the application takes.

## Acceptance — what happens when Atento says it is done

Atento's report closes nothing on its own. When they state the changes are applied, connect to `COLBOGSQL58\MSSQL58_KPI` and verify each one against the live database, the same way the current structure was captured. Every check below is a query; none of them is a question.

**On the catalogue `tb_dim_indicadores`:** the `llave` column exists and is text; a unique index covers it; no value repeats; no value is null for an indicator in use.

**On the score table `tb_dim_indicadores_score`:** `RESULTADO` present, `NR_NUMERADOR` / `NR_DENOMINADOR` gone, `DT_CREATED` and `DT_MODIFIED` present and populated; the composite key (date, person, programa, indicator) has zero duplicates.

**Across both:** zero score rows whose indicator does not exist in the catalogue, and zero score rows whose indicator has no `llave`.

When every check passes, the estimate is confirmed and the build proceeds. A check that fails goes back to Atento naming exactly which one and what the query returned.

## Phases

**Phase 0 — Atento confirms, then applies.** Confirmation of the agreed shape starts the estimate and the build. The application of the changes — the `llave` column with its unique index, plus the score-table shape already proposed — runs in parallel and gates only the testing. Duration is Atento's, not ours.

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

The Friday sync does not happen this week — it is a public holiday in Colombia. The next one is the following Friday. Andrés asked to be contacted directly before then for anything that cannot wait, so the `llave` request does not wait for the sync.

## Risks

The dominant risk is schedule pressure converting into a premature estimate. The mitigation is the gate above, held consistently and stated constructively.

A second risk is accepting a report in place of a verification. The acceptance section exists precisely because a reported change and an applied change are different facts.

A third risk is the per-operation catalogue split surfacing after the code is written. It is the one open item Atento has not been told about, and it changes how many rows their catalogue holds — a change they would rather hear before applying the `llave` column than after.
