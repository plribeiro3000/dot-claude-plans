# PLAN — VKPI Mexico integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Mexico integrator's Modifier stream. The integration consumes **one table** — `dbo.tbl_agentkpis_incentivos` on `MXDCQSIMBVP003` / `dbIndicadoresAt`. There is no second table, and none needs to be created.

## Where this stands

The first round of structural requests has been written and is going to Atento México. Nothing has been agreed yet, no code exists, and no estimate has been given.

This is one round behind Colombia, and it is not a coincidence: Atento's Mexico and Colombia teams do not coordinate with each other. Santiago proposed to Estefani that Mexico adopt the structure Colombia already converged on, and that was declined. So the same requirement set is being negotiated from the start with a different team, using what Colombia's iterations taught rather than the table Colombia built.

## The source structure

`vkpi-schema-2026-08-03.txt` in this folder is the full capture, read directly from the live server: the one table, its eleven columns with type and nullability, its single index, the absence of foreign keys, and the row count. Read that file instead of reconnecting. Its 617 rows are sample data and prove nothing about production.

**One table is enough, and the missing catalogue is not a problem to solve.** Variables are registered in the 4Shark platform by Atento's own team, and each score row resolves to a Variable through the key that registration produced. Colombia carries that key in its indicator catalogue because a catalogue already exists there; Mexico has none, so the key goes straight onto the score row.

Carrying the key on the row also settles the service dimension for free. A supervisor's `calidad` in one operation and in another are two different keys on two different rows, so no catalogue split is required — which is the one item still open on the Colombia side.

**Two facts about the current table decide most of the requests.** `idAgent` is a surrogate identity column (`COLUMNPROPERTY(..., 'IsIdentity')` returns 1), so the primary key counts rows and constrains nothing about the business key — Colombia's original defect, arriving here through the same door. And `idAgent` is not the agent's code despite its name, so it is not a candidate for the person identifier; the person is one of `SAP`, `PBX` or `UserID`.

## The person identifier is the carnet, and that is not a question

The Mexico integration already identifies each person by the **carnet** — Simplex's `Empleado_Carnet`. This is configured, not inferred: `terraform/integrator-atento/main.tf:71` sets `ExternalIdSource = "carnet"` for the `mx` harvester, resolved to `j.CarnetEmpleado` in `SimplexHarvesterService.cs:118-124`, which the Simplex procedure exposes as `v1.Empleado_Carnet AS carnet_empleado` (`sql/sp_reporte_jeraquia_4shark.sql:140`). Colombia's `mx` counterpart is `ExternalIdSource = "codigo"` — a different column, which is why the answer does not transfer between countries.

**Both systems must use the same identifier or the rows find nobody.** So the request is that the table carry the carnet, in whichever of `SAP` / `PBX` / `UserID` already holds it, or in a new column if none does.

### If they cannot send the carnet

The platform admits more than one identifier per person, so a second one can be registered: each user would carry the carnet plus that second value, and indicators would resolve by the second. This is exactly what the Simplex integration already does when it registers the carnet — one more of the same.

The API resolves the user through `UserIdentifier.get(company_id:, value:)` (`indicators_controller.rb:212`), by value alone, and the schema imposes no per-user limit beyond one `primary` (`schema.rb:2350-2356`). So the mechanism works.

**Two conditions have to hold before committing to that path.** The value must be populated for every person — whoever lacks it cannot be identified. And it must not collide with the carnet: `value` carries a unique index per company (`schema.rb:2350`), so a value that already exists as another person's carnet is **rejected by the database**, not silently mismapped. Two independent numeric sequences collide by construction.

Taking this path also requires Atento to say **where in Simplex that value lives**, because the harvester has to read it from there in order to register it. Without that source there is nothing to load, and the column in their table has nothing to correspond to.

## Requirement status

| Requirement | Status |
|---|---|
| A `llave` column, text, not null, carrying the 4Shark Variable key | Requested 05-ago |
| A unique index over date + person + `llave` | Requested 05-ago |
| The carnet as the person identifier | Requested 05-ago |
| One column with the final performance value, replacing `Numerador` / `Denominador` | Requested 05-ago |
| `Fecha` as a real date column, or its format stated | Requested 05-ago |
| A creation date, alongside the existing `Fecha_Actualizacion` | Requested 05-ago |
| Whether the table carries supervisors, and whether their value arrives resolved | Asked 05-ago |
| Metas | Not in scope, not raised |

### Why the unique index spans date + person + `llave`

That trio mirrors the platform's own identity — `index_modifiers_uniqueness` on company, period, user and variable (`schema.rb:1122`) — so it is the same constraint expressed at the source rather than a convention invented for this integration.

**The `llave` column must NOT be unique on its own.** It repeats across people and periods by design; a unique index on it alone would reject the second person to receive the same indicator. This is the opposite of Colombia, where `llave` sits on the catalogue and one indicator is one Variable, so uniqueness there is required. The same column name carries opposite constraints in the two countries because it sits on a different table.

## The supervisor question

The table shows nothing that distinguishes a supervisor from an asesor — no headcount column, no aggregation field. In Colombia those columns exist (`HC` / `HC_Total`) and are what made the supervisor's value a month-long discussion.

Their absence here has two readings and the difference matters: either the table carries only asesores, or supervisors arrive exactly like everyone else. Both are workable; what is not workable is loading without knowing which.

A supervisor is loaded in the platform exactly as an asesor — one value per person, per period, per variable. If their number required any operation on 4Shark's side, that operation would be a guessed business rule, and a wrong guess does not raise an error: it produces a wrong number in variable pay.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are **platform configuration**, not a source requirement. Whoever registers each Variable has to look at the indicator's real scale to choose between `PercentDataType` and `NumberDataType`: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so a ratio-shaped value on a 0–1 scale registered as a percentage enters a hundred times smaller.

## How the keys get agreed between the two sides

Variables are registered in the 4Shark platform, as already happens, and the key that registration produces is what goes in the `llave` column. The only thing to agree is the order: the Variable is registered first, its key loaded into the table afterwards.

The notification loop matches Colombia's: on registering new Variables, Atento's team tells whoever maintains the table and copies 4Shark on the same message, so a pending request stays visible rather than sitting invisibly on their side.

## Acceptance — what happens when Atento says it is done

Their report closes nothing on its own. When they state the changes are applied, connect to `MXDCQSIMBVP003` / `dbIndicadoresAt` and verify each one against the live database, using the queries in `../atento-colombia-vkpi-integration/vkpi-schema-queries.sql` so the result is comparable with the capture already on file.

**On `tbl_agentkpis_incentivos`:** the `llave` column exists, is text, and is never null; a unique index covers date + person + `llave`; the single result column is present and `Numerador` / `Denominador` are gone; `Fecha` is a date type or its format is confirmed in writing; a creation date exists alongside `Fecha_Actualizacion`; the carnet is present in a named column.

**Plus the supervisor answer in writing** — correspondence rather than a query.

When every check passes, the estimate follows.

## Phases

**Phase 0 — Atento confirms, then applies.** Confirmation of the agreed shape starts the estimate; the application of the changes gates the testing. Duration is Atento's.

**Phase 1 — Indicators.** A non-normalized Source pointing at the VKPI server plus a Modifier stream on the Mexico integrator (stack `mx`). Estimated once Atento confirms.

## Validation 4Shark owes itself before estimating Phase 1

Cross the person identifiers in whatever file or table Atento delivers against the Mexico normalized base. The integrator runs in root mode, so an identifier that does not resolve is a rejected row. This is a query, not a question — but it cannot run until the carnet question is answered, because until then it is not known which column to cross.

## Risks

The dominant risk is the identifier. Every other request is a column or a constraint on a table Atento controls; the carnet is the one item where a "no" pushes work onto 4Shark's side, and the fallback carries a condition (no collision with the carnet) that only their data can settle.

A second risk is the coordination gap between Atento's country teams. Colombia's structure was offered to Mexico and declined, so every lesson has to be re-taught rather than transferred — which is why this plan states the reasoning behind each request rather than only the request.
