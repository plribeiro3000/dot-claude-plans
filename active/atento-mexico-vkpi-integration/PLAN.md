# PLAN — VKPI Mexico integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Mexico integrator's Modifier stream. The integration consumes **one table** — `dbo.tbl_VKPI_incentivos` on `MXDCQSIMBVP003` / `dbIndicadoresAt`.

## Where this stands

Atento México delivered a first populated version of the table on **25-ago** and 4Shark validated it on **27-ago** against the same checklist used with Colombia, returning six pending points plus the carnet confirmation — the message Santiago carried into the 27-ago meeting. Atento applied a revised structure and reported it on **2-sep** (Joel Acevedo); 4Shark verified that revision against the live base the same day, and it does not close the central requirements. A revision document for Atento (Spanish) with the consolidated points was sent to Atento México through Santiago on **2-sep** — `revision_tecnica_vkpi_atento_mexico_20260902.pdf` in this folder.

**The `llave` column was not implemented.** No column in the base carries the 4Shark Variable key, and there is no catalogue table to hold it either: the base has only `tbl_agentkpis_incentivos` (legacy) and `tbl_VKPI_incentivos`, with no column named `llave`/`clave` anywhere — consistent with the one-table model Santiago agreed on 5-ago (one table, the key as a column in it, no catalogue). The `NK_KEY` column Atento added is a different thing: a per-row identifier, a `DEFAULT` (not a computed column) of `CONVERT(VARCHAR(64), HASHBYTES('SHA2_256', CONCAT(DT_DATE, RFC, id_VKP)))`. It was their attempt to block duplicate records, and it fails at that too — because `id_VKP` (the surrogate identity) is in the hash, every row gets a distinct value (1616 distinct over 1616 rows), so the composite PK on `(DT_DATE, RFC, NK_KEY)` is unique but vacuous, and the same grain with conflicting `Resultados` survives (`NR_RE 53433`, `% Ausentismo`, `20260801` → 0 and 0.565).

**The person key uses `RFC`, not the carnet.** The PK's person dimension is `RFC` (the fiscal id), while the identifier already agreed for Mexico — and the one 4Shark resolves people by — is the carnet (`NR_RE` / Simplex `Empleado_Carnet`).

What holds: `Resultados` is a single value per row, and the compilation date sits on the period's first day (only August, a monthly load, is present). What Atento owns, so it is not a raised point: `DT_MODIFIED` — 4Shark offered the procedure on 27-ago and Atento committed to guarantee the creation/update behaviour on their side.

The four points carried to Atento on **2-sep**, each with the SQL to fix it: (1) add the `llave` column, loaded with the 4Shark Variable key, which repeats per person·period — not a row hash; (2) the person must be the carnet (`NR_RE`), not `RFC`; (3) there is no real unique index, so the conflicting duplicates persist — create the unique index over fecha + carnet + `llave`, and because the base is already dirty, truncate it and repopulate only after the structure is corrected; (4) the period date lives in three columns (`AÑOMES` text, `DT_DATA` int, `DT_DATE` datetime) — Atento designates which single column is the period date, and it must be a `date` type (not the month/text column); 4Shark reads that column as-is, logs the exact value, and any discrepancy between columns or bad data is Atento's.

Atento built a **new table** rather than modifying the structure 4Shark originally reviewed. The older `dbo.tbl_agentkpis_incentivos` (636 rows) still exists on the server and is not used; the integration reads `dbo.tbl_VKPI_incentivos` (1616 rows) only. The new table follows the shape of the VKPI extract (client, program, supervisor/manager names, indicator, `Resultados`) rather than the six surgical edits proposed for the old table.

On **2026-09-04**, 4Shark sent Janaína Soares (CC Estefani Pérez) a priority-request email covering the VKPI integration in México, Colômbia and Chile: it states the integration is progressing within Atento's own flows, asks Atento to prioritize the teams on the remaining points so it closes faster, and commits 4Shark to deliver within a few business days of each unblock — México, with the correction script already in hand, in up to 5 business days. Full text: `email-janaina-2026-09-04-PT.txt`.

## The source structure

`vkpi-schema-2026-08-27.txt` in this folder is the full capture read live from the server on 27-ago: the target table, its 19 columns with type and nullability, its single index, the absence of foreign keys, and the data findings. Read that file instead of reconnecting. `vkpi-schema-2026-08-03.txt` describes the older `tbl_agentkpis_incentivos` and is kept only as the prior reference.

Two facts settle most of the reading. The person is `NR_RE` (stable per person); `NR_ID` varies per row and is the **indicator** id; `RFC` is the fiscal id. And the primary key `id_VKP` is a surrogate identity column, so it counts rows and constrains nothing about the business key.

## The person identifier is the carnet, and that is not a question

The Mexico integration already identifies each person by the **carnet** — Simplex's `Empleado_Carnet`. This is configured, not inferred: `terraform/integrator-atento/main.tf:71` sets `ExternalIdSource = "carnet"` for the `mx` harvester, resolved to `j.CarnetEmpleado` in `SimplexHarvesterService.cs:118-124`, which the Simplex procedure exposes as `v1.Empleado_Carnet AS carnet_empleado` (`sql/sp_reporte_jeraquia_4shark.sql:140`).

**Both systems must use the same identifier or the rows find nobody.** The carnet is the agreed identifier — confirmed in the integration sessions ("¿Vamos a buscarlo por el carnet?", 2026-07-02), with `RFC` only ever floated as a fallback. In the delivered table the person is `NR_RE` (the carnet), but Atento's PK keys the person on `RFC`, which must be corrected. 4Shark still owes itself the cross-check of `NR_RE` against the Mexico normalized base before estimating (§ Validation 4Shark owes itself) — that is a query, not an open question about which column is the identifier.

## Validation result — requirement status

The four points carried to Atento, plus what holds and what Atento owns:

| Point (verified 2-sep) | Status | Evidence in `tbl_VKPI_incentivos` |
|---|---|---|
| 1. A `llave` column carrying the 4Shark Variable key | **Not implemented** | No column holds the 4Shark key, and there is no catalogue table. `NK_KEY` (nvarchar(150), not null) is a per-row hash `HASHBYTES('SHA2_256', CONCAT(DT_DATE, RFC, id_VKP))` — a row identifier, not the key |
| 2. Person = the carnet (`NR_RE` / Simplex `Empleado_Carnet`) | **Wrong column** | The PK's person dimension is `RFC` (fiscal id), not the carnet |
| 3. Real unique index over fecha + carnet + `llave`, on a clean base | **Absent → duplicates persist** | PK on `(DT_DATE, RFC, NK_KEY)` is unique but vacuous (row-unique `NK_KEY`); the same grain still appears twice with conflicting `Resultados` (`NR_RE 53433`, `% Ausentismo`, `20260801` → 0 and 0.565). Needs the index over fecha+carnet+`llave`, plus truncate and reload |
| 4. Period date: one `date`-typed column Atento designates | **Split across three columns** | `AÑOMES` (text), `DT_DATA` (int), `DT_DATE` (datetime). Atento names the column; it must be `date` type (not the month/text). 4Shark reads it as-is and logs the value; discrepancies are Atento's |
| A single result column, replacing `Numerador` / `Denominador` | **OK** | `Resultados` (float) |
| Supervisors as ordinary rows, no headcount rule | **OK** | One row per person·indicator·period; no aggregation column |
| `DT__INSERT` / `DT_MODIFIED` create-and-update behaviour | **Atento's to guarantee** | Not a raised point — 4Shark offered the procedure (27-ago) and Atento committed to guarantee it on their side |
| Period rule (monthly day 1 / weekly / daily) | **Note — open decision** | August (monthly) sits at `20260801`; weekly/daily to confirm when they exist. Whether to re-raise it as a formal point (it was point 6 on 27-ago) is undecided |

### The duplicate carries conflicting values

The same `(NR_RE, DT_DATA, NR_ID, NR_SERVICIO_CODIGO, NM_PROGRAMA)` appears twice with **different** `Resultados` — e.g. `NR_RE 53433`, `% Ausentismo`, `TELEVIA IN`, `20260801` → one row `0`, one row `0.565`. This reads as two calculation moments (pre-cierre / reproceso) stacked on the same grain with no discriminator column. For commissioning 4Shark needs a **single consolidated value** per person·indicator·period; this is also what unblocks the unique index.

### Why the unique index spans date + person + `llave`

That trio mirrors the platform's own identity — `index_modifiers_uniqueness` on company, period, user and variable (`schema.rb:1122`) — so it is the same constraint expressed at the source. The `llave` column must NOT be unique on its own: it repeats across people and periods by design.

### The created/updated behaviour is Atento's to guarantee

4Shark's incremental load processes only the records whose update timestamp moved: `DT__INSERT` set once on insert, `DT_MODIFIED` advanced on every change. 4Shark offered the procedure/trigger for this on 27-ago; Atento chose to guarantee the behaviour on their own side. It is therefore not among the four points raised on 2-sep — it stays a point of attention 4Shark verifies at acceptance, not a demand.

### The compilation date and the period rule

The period date must land on the platform's calendar: a monthly indicator on the first day of the period, a weekly one indexed from the first day, a daily one on the day. Only August (monthly) is loaded, and it is compliant (`20260801`). The 2-sep points ask Atento to designate a single `date`-typed column for the period (point 4); the period rule for weekly and daily indicators was point 6 on 27-ago and sits as a note until those frequencies exist — whether to re-raise it as a formal point is undecided.

## The supervisor question is resolved

The table carries supervisors and coordinators as **ordinary rows** — `NM_CARGO_DESCRIPCION` shows `SUPERVISOR BASICO`, `COORDINADOR DE SERVICIO DE CC`, `ANALISTA DE WFM`, alongside the operator roles, one row per person·indicator·period. There is no headcount or aggregation column, so a supervisor loads exactly like an asesor — the workable case. This is the item Colombia spent a month on (`HC` / `HC_Total`); here it needs no rule on 4Shark's side.

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are platform configuration, not a source requirement. Whoever registers each Variable chooses between `PercentDataType` and `NumberDataType` by the indicator's real scale: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so a 0–1 ratio registered as a percentage enters a hundred times smaller.

## How the keys get agreed between the two sides

Variables are registered in the 4Shark platform, and the key that registration produces is what goes in the `llave` column. The Variable is registered first, its key loaded into the table afterwards. On registering new Variables, Atento's team tells whoever maintains the table and copies 4Shark on the same message.

## Acceptance — what happens when Atento says it is done

Their report closes nothing on its own. When Atento states the changes are applied, connect to `MXDCQSIMBVP003` / `dbIndicadoresAt` and verify each one against the live database, using the queries in `../atento-colombia-vkpi-integration/vkpi-schema-queries.sql` so the result is comparable with the capture on file.

On `tbl_VKPI_incentivos`: the `llave` column exists, is text, and is never null, carrying the 4Shark Variable key; the person key is the carnet (`NR_RE`), not `RFC`; a single consolidated value exists per grain (no conflicting duplicates) and a unique index covers fecha + carnet + `llave`; the base was truncated and repopulated after the structure was corrected; the period date is the single `date`-typed column Atento designated; `DT_MODIFIED` advances on update (Atento's guarantee); and `NR_RE` is confirmed as the carnet against the normalized base.

When every check passes, the estimate follows.

## Phases

**Phase 0 — Atento confirms, then applies.** Confirmation of the agreed shape starts the estimate; the application of the changes gates the testing. Duration is Atento's.

**Phase 1 — Indicators.** A non-normalized Source pointing at the VKPI server plus a Modifier stream on the Mexico integrator (stack `mx`). Estimated once Atento confirms.

## Validation 4Shark owes itself before estimating Phase 1

Cross `NR_RE` against the Mexico normalized base. The integrator runs in root mode, so an identifier that does not resolve is a rejected row. This is a query, not a question — and it confirms the carnet at the same time.

## Risks

The dominant risk is the identifier: `NR_RE` must equal the Simplex carnet, and only Atento's data plus the normalized-base cross-check settle it.

The second risk is the source's own consistency: the table loads the same grain twice with conflicting values, so without the unique index over fecha + carnet + `llave` (and a clean reload) a wrong value can enter variable pay silently. The update-timestamp behaviour is Atento's guarantee; if it does not hold, the incremental load silently misses later changes — 4Shark verifies it at acceptance. Both failures are silent: a wrong value in variable pay does not raise an error.
