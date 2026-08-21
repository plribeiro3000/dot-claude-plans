# PLAN — VKPI Colombia integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Colombia integrator's Modifier stream. The integration consumes **two tables**: `tb_dim_indicadores_score` for the values, and `tb_dim_indicadores` (the catalogue) to resolve each score row to the 4Shark Variable it belongs to. Every other VKPI table is Atento's internal use and out of scope.

## Where this stands

The structure 4Shark builds against is defined, written as an executable script, and delivered. `~/Downloads/estructura_final_vkpi_atento_colombia_20260820.sql` takes the score table from its 16 columns to the 22 of the 30-jul maqueta, applies the recommendations issued through July and August, and adds the `llave` column to the catalogue. Santiago sent it to Atento on 20-ago over Slack, together with the roadmap PDF.

**Both tables are truncated before the script runs, and that decision is what makes it a single pass.** The server holds sample rows for structural work, not the operation, so nothing there is worth preserving: the score rows predate `RESULTADO` and the date columns, and the catalogue rows predate `llave`. On empty tables the script can declare `llave` NOT NULL and unique immediately, instead of creating a nullable column and waiting for someone to come back and close it. The real data enters afterwards — the score table through the load procedure, the catalogue through Atento's own process.

**The estimate is calculated on the structure that script produces, not on a confirmation from Atento.** Nothing has been confirmed in writing since 04-ago, so waiting on a confirmation postpones the estimate indefinitely. The script is the statement of what the structure is; Atento has until 17-sep to say something changed, and after that the build proceeds on what the script leaves.

## The three sources, and what each one proves

Confusing these is the most expensive mistake available here, because each answers a different question and none of them substitutes for another.

**The live database is the current structure, and 4Shark has access to it.** `vkpi-schema-2026-08-03.txt` in this folder is the full capture, read directly from `COLBOGSQL58\MSSQL58_KPI`: the four tables, every column with type and nullability, the indexes, the foreign keys and the row counts. Read that file instead of reconnecting. Its rows are sample data and prove nothing about production volumes or values.

**The files Atento sends (`Maqueta.csv`, `Propuesta 4shark.xlsx`) are a proposal of changes, not the database.** The live score table still carries `NR_NUMERADOR` / `NR_DENOMINADOR` and the misspelled `NR_SERVIVIO_CODIGO`, has no `DT_CREATED` / `DT_MODIFIED`, and carries no unique index. The proposed shape exists only in the files. Every measurement about data — uniqueness, cardinality, value ranges, coverage — is made against the file, because that is the only place the proposed structure exists.

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
| Per-record creation and update dates | Score table | Closed in the script — `DT_CREACION` / `DT_ACTUALIZACION`, PASO 3.1 |
| How the supervisor's value is composed | Score table | Closed — confirmed verbally in the 05-ago call |
| **The script's structure applied to the live database** | Score table | **Open — delivered 20-ago, deadline 17-sep** |
| **A text column `llave` on the catalogue, unique and not null, holding the 4Shark Variable key** | Catalogue | **Open — PASO 4 creates it constrained; Atento's catalogue load must carry a key per indicator from then on** |
| **The score table repopulated after the truncate** | Atento | **Open — the integration has nothing to read until it happens** |
| One catalogue row per indicator per operation | Catalogue | Closed — already true; the split lives inside `NR_ID` (see below) |
| The list of exact Variable keys, for Atento to load into `llave` | 4Shark | **Open — owed by 4Shark, blocks the catalogue load** |
| What distinguishes the 18 catalogue names that carry several `NR_ID` | Atento | **Open and not yet raised — those indicators cannot receive a key until it is answered** |
| Network reachability from the integrator to `COLBOGSQL58`, plus a read-only database user on the two tables | Atento | **Open — not yet requested; blocks the 17-sep start** |
| Every score row references an indicator that exists in the catalogue | Process | Open — load-bearing, the integrator reads the catalogue on every load; not verifiable at script time, since both tables are empty then |
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

## Risks

**The access request never being made is the risk closest to the calendar.** Network reachability from the integrator to `COLBOGSQL58` and a read-only database user are not database structure, so they are absent from both the script and the roadmap; nothing Atento holds tells them to prepare either, and without both the 17-sep start does not happen.

A second risk is the reload after the truncate. The script leaves both tables empty by design, so testing cannot start until Atento repopulates them — and nothing on 4Shark's side can substitute for that or estimate how long it takes. It is the one dependency where a delay translates directly into idle days inside the three weeks.

A third risk is accepting a report in place of a verification. The acceptance section exists precisely because a reported change and an applied change are different facts.

A third risk is `develop`: the normalized-customer migration has not been rehearsed against a homologation base, and it carries the eight-to-twelve-day half of the estimate.

A fourth risk is the supervisor case reaching production untested. The sample Atento delivered carries no supervisor rows at all, so nothing in it exercises the path where a person holds the same indicator concept across several operations. The catalogue's own split by `NR_ID` is what makes that path correct, and it has been reasoned about rather than observed — the first load that includes supervisors is where it gets confirmed.
