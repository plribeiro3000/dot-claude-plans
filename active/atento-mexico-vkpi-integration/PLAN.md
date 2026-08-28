# PLAN — VKPI Mexico integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Mexico integrator's Modifier stream. The integration consumes **one table** — `dbo.tbl_VKPI_incentivos` on `MXDCQSIMBVP003` / `dbIndicadoresAt`.

## Where this stands

Atento México delivered a first populated version of the table on **25-ago** (Aryadna Espinosa / Christian Rojas / Joel Acevedo) and asked 4Shark to validate it. The structure and the loaded data were validated on **27-ago** against the same checklist used with Colombia. Six points remain open before the integration can be built and estimated; they are the subject of the message below.

A message with the validation result and the six pending points was handed to Santiago to present at the **27-ago noon meeting** with Atento México. After that meeting, pull the Granola summary of what was discussed and update this plan with any Atento commitments or changes to the six points.

Atento built a **new table** rather than modifying the structure 4Shark originally reviewed. The older `dbo.tbl_agentkpis_incentivos` (636 rows) still exists on the server and is not used; the integration reads `dbo.tbl_VKPI_incentivos` (1616 rows) only. The new table follows the shape of the VKPI extract (client, program, supervisor/manager names, indicator, `Resultados`) rather than the six surgical edits proposed for the old table.

## The source structure

`vkpi-schema-2026-08-27.txt` in this folder is the full capture read live from the server on 27-ago: the target table, its 19 columns with type and nullability, its single index, the absence of foreign keys, and the data findings. Read that file instead of reconnecting. `vkpi-schema-2026-08-03.txt` describes the older `tbl_agentkpis_incentivos` and is kept only as the prior reference.

Two facts settle most of the reading. The person is `NR_RE` (stable per person); `NR_ID` varies per row and is the **indicator** id; `RFC` is the fiscal id. And the primary key `id_VKP` is a surrogate identity column, so it counts rows and constrains nothing about the business key.

## The person identifier is the carnet, and that is not a question

The Mexico integration already identifies each person by the **carnet** — Simplex's `Empleado_Carnet`. This is configured, not inferred: `terraform/integrator-atento/main.tf:71` sets `ExternalIdSource = "carnet"` for the `mx` harvester, resolved to `j.CarnetEmpleado` in `SimplexHarvesterService.cs:118-124`, which the Simplex procedure exposes as `v1.Empleado_Carnet AS carnet_empleado` (`sql/sp_reporte_jeraquia_4shark.sql:140`).

**Both systems must use the same identifier or the rows find nobody.** In the delivered table the person is `NR_RE`; it is the carnet candidate. The one thing still to confirm — with Santiago, cross-referencing the Mexico normalized base — is that `NR_RE` equals the Simplex `Empleado_Carnet`.

## Validation result — requirement status

| Requirement | Status | Evidence in `tbl_VKPI_incentivos` |
|---|---|---|
| A `llave` column, text, not null, carrying the 4Shark Variable key | **Missing** | Not present. `NR_ID` / `NM_INDICADOR_EN_EL_PAIS` is Atento's internal indicator id/name, not the 4Shark key |
| A single result column, replacing `Numerador` / `Denominador` | **OK** | `Resultados` (float) |
| A single consolidated value per person·indicator·period | **Broken** | The same person·date·indicator·service·program appears twice with different `Resultados` (see below) |
| A unique index over date + person + `llave` | **Missing / blocked** | Only the surrogate PK on `id_VKP`. Cannot be created today because the grain repeats |
| `Fecha` as a real `date` column | **Missing** | `DT_DATA` is `int` (yyyymmdd). It must be a `date` |
| A creation date alongside the update date | **OK (structure)** | `DT__INSERT` (creation, `default getdate()`) and `DT_MODIFIED` (update) exist |
| Creation set only on insert, update refreshed on every change | **Not guaranteed** | `DT_MODIFIED` has no default and no visible mechanism — needs a procedure/trigger |
| Compilation date follows the 4Shark period rule | **To confirm** | `DT_DATA` is the period date; the monthly sample (`% Ausentismo`) is `20260801` (first day) — confirm across all frequencies |
| Carnet as the person identifier | **To confirm** | `NR_RE` is the candidate; confirm it equals the Simplex `Empleado_Carnet` |

### The duplicate carries conflicting values

The same `(NR_RE, DT_DATA, NR_ID, NR_SERVICIO_CODIGO, NM_PROGRAMA)` appears twice with **different** `Resultados` — e.g. `NR_RE 53433`, `% Ausentismo`, `TELEVIA IN`, `20260801` → one row `0`, one row `0.565`. This reads as two calculation moments (pre-cierre / reproceso) stacked on the same grain with no discriminator column. For commissioning 4Shark needs a **single consolidated value** per person·indicator·period; this is also what unblocks the unique index.

### Why the unique index spans date + person + `llave`

That trio mirrors the platform's own identity — `index_modifiers_uniqueness` on company, period, user and variable (`schema.rb:1122`) — so it is the same constraint expressed at the source. The `llave` column must NOT be unique on its own: it repeats across people and periods by design.

### The created/updated behaviour is load-bearing

4Shark's incremental load processes only the records whose update timestamp moved. `DT__INSERT` carries a creation default, but `DT_MODIFIED` has no mechanism, so nothing guarantees it advances on every change. Without a procedure or trigger that sets the creation timestamp only on insert and refreshes the update timestamp on every update, the incremental load does not work.

### The compilation date must follow the 4Shark period rule

The compilation/period date (`DT_DATA`) must land on the platform's calendar: a monthly indicator referenced to the first day of the period, a weekly one indexed from the first day, a daily one on the day. The monthly sample is compliant (`20260801`); confirm it holds for weekly and daily indicators.

## The supervisor question is resolved

The table carries supervisors and coordinators as **ordinary rows** — `NM_CARGO_DESCRIPCION` shows `SUPERVISOR BASICO`, `COORDINADOR DE SERVICIO DE CC`, `ANALISTA DE WFM`, alongside the operator roles, one row per person·indicator·period. There is no headcount or aggregation column, so a supervisor loads exactly like an asesor — the workable case. This is the item Colombia spent a month on (`HC` / `HC_Total`); here it needs no rule on 4Shark's side.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are platform configuration, not a source requirement. Whoever registers each Variable chooses between `PercentDataType` and `NumberDataType` by the indicator's real scale: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so a 0–1 ratio registered as a percentage enters a hundred times smaller.

## How the keys get agreed between the two sides

Variables are registered in the 4Shark platform, and the key that registration produces is what goes in the `llave` column. The Variable is registered first, its key loaded into the table afterwards. On registering new Variables, Atento's team tells whoever maintains the table and copies 4Shark on the same message.

## Acceptance — what happens when Atento says it is done

Their report closes nothing on its own. When Atento states the changes are applied, connect to `MXDCQSIMBVP003` / `dbIndicadoresAt` and verify each one against the live database, using the queries in `../atento-colombia-vkpi-integration/vkpi-schema-queries.sql` so the result is comparable with the capture on file.

On `tbl_VKPI_incentivos`: the `llave` column exists, is text, and is never null; a single consolidated value exists per grain (no conflicting duplicates); a unique index covers date + person + `llave`; `DT_DATA` is a `date` type; a procedure/trigger guarantees the creation/update timestamp behaviour; the compilation date follows the period rule across frequencies; `NR_RE` is confirmed as the carnet.

When every check passes, the estimate follows.

## Phases

**Phase 0 — Atento confirms, then applies.** Confirmation of the agreed shape starts the estimate; the application of the changes gates the testing. Duration is Atento's.

**Phase 1 — Indicators.** A non-normalized Source pointing at the VKPI server plus a Modifier stream on the Mexico integrator (stack `mx`). Estimated once Atento confirms.

## Validation 4Shark owes itself before estimating Phase 1

Cross `NR_RE` against the Mexico normalized base. The integrator runs in root mode, so an identifier that does not resolve is a rejected row. This is a query, not a question — and it confirms the carnet at the same time.

## Risks

The dominant risk is the identifier: `NR_RE` must equal the Simplex carnet, and only Atento's data plus the normalized-base cross-check settle it.

The second risk is the source's own consistency: the table already loads the same grain twice with conflicting values, and it has no mechanism guaranteeing the update timestamp advances. Both are Atento's to fix, and both are silent — a wrong value in variable pay does not raise an error.
