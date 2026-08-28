# ANALYSIS v2 — VKPI Colombia: acceptance of the 20-ago structure

**Date: 2026-08-27.** Live database audited directly: `COLBOGSQL58\MSSQL58_KPI`. Score table `tb_dim_indicadores_score` now holds 3.995 rows (reloaded — no longer empty).

This is the acceptance verification the PLAN's § Acceptance called for: Atento reported the structure changes were applied, so 4Shark connected to the live base and checked each requirement against real queries, not against the report. The verdict is that the two central requirements are still unmet, and that the fastest path forward is the normalized base, not more rounds on the source table.

## What we asked for, and where it stands

The two requirements the whole effort turned on:

1. **A unique key at the grain the integration consumes** — period + person + programa + indicator (`DT_DATA`, `NR_RE`, `NR_SERVIVIO_CODIGO`, `NR_ID`). Agreed against the supervisor case in the 05-ago call.
2. **A `llave` column on the catalogue** (`tb_dim_indicadores`) — text, NOT NULL, unique, holding the 4Shark Variable key per indicator. Asked on 03-ago, reinforced 05-ago.

Neither is present in the delivered structure.

## What the audit found — filtered to what 4Shark can legitimately raise

The filter matters: 4Shark can raise (a) requirements it stated that were not delivered, and (b) new objects Atento added that break the integration or fail to guarantee correctness. It does NOT raise pre-existing conditions it never flagged, nor content defects on data that is still fictitious test data. Applying that filter:

### Raise — requirement not met

**The unique constraint is on a surrogate id, not the business key.** The only index in the whole database is a clustered PK on `NR_CHAVE_EMPRESA_MES_RE`. That column is a sequential surrogate (range 1.008.527–3.061.325 for 3.995 rows), not the business key — proven: it resolves to no column of any table in this database (tested against `mapa_operacional_mensal`'s four key columns, all zero). A unique constraint on a running counter is trivially satisfied and guarantees nothing about business uniqueness. Two rows with the same period + person + programa + indicator would both be accepted. The grain that must be unique (`DT_DATA, NR_RE, NR_SERVIVIO_CODIGO, NR_ID`) is unique in the current data (3.995 distinct = 3.995 rows) but has no index enforcing it. The constraint is new (the baseline had no index at all), so the ask is legitimate: enforce uniqueness — and referential integrity — at the grain we consume, so wrong data cannot enter.

**The `llave` column was not created on the catalogue.** `tb_dim_indicadores` still carries its original 17 columns; the column does not exist. Without it the resolution chain (score indicator → catalogue → llave → 4Shark Variable) does not close. This is the explicit ask that is simply absent.

**The created/updated columns came as `date`, not `datetime` — and datetime is not a new ask.** The need for a timestamp *with the time of day* was stated in the 03-jul meeting: 4Shark explained that the update column must record the moment the row changes ("la fecha de actualización en aquella hora"), because the incremental read — reading only what changed since the last load — depends on knowing exactly when a row was created or modified; `date` (day only) cannot distinguish two changes on the same day. The 4Shark reference script has declared these columns `datetime` with a server-set UTC timestamp since 2026-07-29, and the 20-ago consolidated script carries the same. They were delivered as `date`. No formal DATE-vs-DATETIME DDL decision was minuted, but the functional requirement (with time) is on record from 03-jul, so this is a reinforcement of an early ask, not a new one.

**The minimum guarantees we shipped a path for are not there, by any route.** 4Shark delivered not just the requirement but a script and a load procedure (MERGE) that would satisfy uniqueness and the incremental-read semantics. Atento was free to solve it another way; they did neither — the database has no procedure, view, function or trigger, and the guarantees are absent. This is raised as "the guarantees are missing," not "you didn't use our procedure."

### Do NOT raise — dropped on purpose

- **Column names** (`DT_CREATED` vs `DT_CREACION`, etc.). Irrelevant. The integration does not care what the columns are called.
- **`NR_EMPRESA` 100% NULL.** Internal to Atento; single account, single country; the integration does not use it.
- **`NR_INDICADOR` 100% NULL (dead column).** The integration does not use it — the value lives in `RESULTADO`, the person in `NR_RE`, the date in `DT_DATA`. Those three, plus the indicator identifier for the Variable mapping, are all we need.
- **Person mismatch score↔mapa (21 of 190).** The data is fictitious test data; a content-consistency complaint on test data is not defensible. (And 4Shark resolves the person by the Simplex code against its own base, not against `mapa` — the parallel hierarchy guardrail G1 forbids consuming.)
- **The 32 orphan score rows vs the catalogue** as a *data* complaint. Same test-data reason. It survives only reframed as a *constraint* ask (a NOT NULL foreign key from score's indicator to the catalogue would stop bad data entering) — folded into the uniqueness/integrity point above.

## Timeline — how long this has run (dates from email and meeting record)

The clock that counts is the table work, which starts only once the base was accessible. June and most of July were access/permissions provisioning on SQL58 — credentials, ports (1433/1434 opened around 24-jul), URL, password — handled by the networks/infra team, not the integration work, and excluded here.

- **2026-07-27** — the base becomes usable and 4Shark completes its technical analysis of it (Santiago's 28-jul email: "el día de ayer finalizamos el análisis técnico de la base de datos habilitada"). This is the start of the table work.
- **2026-07-29** — alignment meeting; agreements on the indicators table.
- **2026-07-30 / 31** — Atento sends the maqueta; 4Shark's requirements review (2 open points: unique key, supervisor).
- **2026-08-02** — Atento sends the base for approval; proposes the concatenated-column approach for the key ("se tomará la fecha…").
- **2026-08-03** — 4Shark advances on the score table; remaining ask = the `llave` on the catalogue.
- **2026-08-05** — LatAm call: supervisor mechanism and the key grain confirmed; variable-registration reverted to the platform.
- **2026-08-20** — 4Shark's definitive delivery: roadmap PDF + `estructura_final_vkpi_atento_colombia_20260820.sql`, converting 16→22 columns "al formato requerido"; 17-sep named as the deadline to object.
- **2026-08-12, 2026-08-25** — Santiago follow-ups asking whether the table changes were executed.
- **2026-08-27 (today)** — Atento reports the changes are done; 4Shark verifies against the live base; none of the two required elements is present.

From the base becoming usable at end-July to today — about one month — the source table still does not carry what the integration needs. Counting from 17-jun overstates it: that period was access/infra provisioning, a separate team's work, not the table effort.

## Recommendation — pivot to the normalized base

Stop trying to reshape the VKPI source table and integrate from the **normalized base** instead. Its structure is already defined, it is a structure 4Shark integrates against, and 4Shark is **already integrated** with it. Atento's remaining work collapses to one thing: put the data there. That removes every open point above at once — no unique-index debate, no `llave` column to create, no date-type argument, no load procedure to write — because the normalized base already guarantees the shape the integration consumes.

The comparison is stark: ten weeks of rounds on the source table have produced a structure with none of the two things we need, while the normalized base is a ready, already-integrated target that only needs the data loaded. The source-table path keeps both sides fighting the same structure; the normalized-base path is faster and lower-risk.

## Communication

On 2026-08-27 the four points above plus the normalized-base recommendation were sent to Santiago (Slack) for him to relay to Atento (Estefani and team). The message opens by stating Atento reported the structure done while the live-base check shows it is not, lists the four points framed as what the integration needs (with point 3 anchored to the 03-jul ask so it reads as reinforcement, not a new demand, and point 4 framed as support rather than a missing-deliverable reproach), and closes with the normalized-base recommendation on the grounds that it is ready, already integrated, and carries no cost of operating an extra database. Text preserved verbatim in `mensaje-santi-2026-08-27-ES.txt`.

## Supporting artifact

Full findings with per-item evidence and the query results: `vkpi-colombia-buracos-20260827.html` (audit report, 2026-08-27), in this folder.
