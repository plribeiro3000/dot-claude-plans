# ANALYSIS — SimplexPE.Global4Shark

**Project**: `SimplexPE.Global4Shark`
**Local checkout**: `/Users/plribeiro3000/Projects/Atento/SimplexPE.Global4Shark`
**Owner today**: Atento (runs on Atento's infrastructure)
**Date of analysis**: 2026-04-17
**Status**: Reverse-engineering — current state documented; no implementation decisions yet

## Goal

Document what the existing Atento application does today, so 4Shark has a complete map of:
- Inputs, outputs, dependencies, and side effects
- Embedded business rules not documented elsewhere
- Technical debt and edge cases that any future replication, migration, or refactor must respect

The analysis is country-agnostic — the same codebase is intended to run for Atento Mexico (today) and Atento Colombia (planned), so findings are about the **application**, not the deployment.

## Project Overview

- **Stack**: .NET 6 console application
- **Namespace**: `global_bd`
- **Main class**: `_4SharService` (note: typo, missing the `k` — preserved as-is in production)
- **Purpose**: ETL of HR/payroll hierarchy data from **Simplex** (Atento's on-premise SQL Server payroll/HR system) into the **4Shark normalized database** (Azure SQL). Local SQLite snapshot acts as the previous-state cache to detect daily deltas.

### Naming inconsistencies (worth flagging)

- Repo is named `SimplexPE.Global4Shark` (`PE` suggesting Peru), but the entire codebase targets Mexico:
  - `COUNTRIES` configuration only contains `MEX`.
  - Default email domain is hardcoded to `@atento.com.mx`.
  - SQLite file is `Data/MEX_4Shark.sqlite`.
- The `Global` part of the name suggests multi-country ambition that never materialized in the current implementation.
- `_4SharService` (missing `k`) is the actual class name in production. Any rename would be a breaking change for any external reference.

## Public Entry Points

### `LoadGlobalInitial()` — lines 55–100
Initial full load across all configured countries and companies.

Flow:
1. Retrieves all countries from configuration (`COUNTRIES` section).
2. For each country–company pair:
   - Calls `LoadJearquia()` — fetches all hierarchy records from Simplex SP `sp_reporte_jeraquia_4shark` via SQL Server.
   - Extracts role sets: `ExtractMandos()`, `ExtractSupers()`, `ExtractRacs()`, `ExtractAnalistas()` — populates HashSets of distinct role holders.
   - Calls `LoadSubsidiaries()` to create/verify subsidiary records in 4Shark.
   - Loads user records role-by-role: `LoadMandos()`, `LoadSupers()`, `LoadRacs()`, `LoadAnalistas()`.
   - Saves all to SQLite cache via `SaveLoad()` (30-day retention).
3. Wrapped in try-catch that logs and continues (lines 91–96).

Note: `LoadCampanas()` and campaign checks are commented out (lines 71, 79–82) — campaign sync is disabled.

### `LoadGlobalDayli()` — lines 102–146
Incremental daily sync.

Flow:
1. For each country–company:
   - Recovers last snapshot from SQLite via `RecoveryLastLoad()`.
   - Fetches current Simplex hierarchy via `LoadJearquia()`.
   - Diffs old vs. new with `JerarquiaComparer`:
     - `ExtractDiferences()` populates `ultima_nueva` (departed users) and `nueva_ultima` (newcomers).
   - Recovers subsidiary reference via `RecoverySubsidiarie()`.
   - Re-extracts role sets from new data.
   - Processes changes: `LoadNuevos()` (create newcomers), `LoadCesados()` (disable departed), `LoadUpdates()` (sync field-level changes).
   - Saves updated snapshot to SQLite.

Note: campaign code commented out (lines 114, 129).

### `LoadCountryDayli(string countryKey, int companyNum = 0)` — lines 148–166
**Entirely commented out.** Original intent appears to have been a single-country daily run. Current implementation is a no-op. Either dead code, or unfinished feature.

## Methods Catalog

| Method | Lines | Summary |
|---|---|---|
| `Add()` | 1024–1092 | Creates or updates a 4Shark user; handles hierarchy lookup, user creation via `create_user`, field/identifier setup |
| `CheckChangeArea()` | 1389–1398 | Detects department changes via AreaComparer; calls `UpdateArea()` |
| `CheckChangeCargo()` | 1334–1343 | Detects job title changes via CargoComparer; calls `UpdateCargo()` |
| `CheckChangeCeco()` | 1429–1438 | Detects cost center changes via CecoComparer; calls `UpdateCeco()` |
| `CheckChangeCliente()` | 1502–1511 | Detects client changes via ClienteComparer; calls `UpdateCliente()` |
| `CheckChangeGroup()` | 1209–1218 | Detects group/campaign changes; calls `UpdateGroup()` |
| `CheckChangeGrupoOcupacional()` | 1574–1583 | Detects occupational group changes; calls `UpdateGrupoOcupacional()` |
| `CheckChangeMando()` | 1249–1258 | Detects manager hierarchy changes; calls `UpdateMando()` |
| `CheckChangeModalidad()` | 1639–1648 | Detects work modality changes; calls `UpdateModalidad()` |
| `CheckChangeSite()` | 1694–1703 | Detects site/location changes; calls `UpdateSite()` |
| `CheckChangeSuper()` | 1291–1300 | Detects supervisor hierarchy changes; calls `UpdateSuper()` |
| `CheckChangeUnidadServicio()` | 1749–1758 | Detects service unit (SAP PEP) changes; calls `UpdateUnidadServicio()` |
| `DeactivateGroups()` | 1821–1848 | Disables removed campaigns/groups via `disable_group` |
| `ExtractAnalistas()` | 384–397 | Analyst IDs: not managers, not supervisors, occupational group ≠ 2 |
| `ExtractDiferences()` | 1149–1163 | Diffs old vs. new hierarchy via JerarquiaComparer |
| `ExtractMandos()` | 302–351 | Manager IDs from hierarchy fields (DirectorPais, Director, Gerente, Jefe, ResponsableNivel4–9) |
| `ExtractRacs()` | 369–382 | RAC IDs: occupational group == 2 AND not supervisor |
| `ExtractSupers()` | 353–367 | Supervisor IDs: those with ResponsableCodigo |
| `FindParentMando()` | 420–731 | Locates superior manager in 9-level hierarchy; checks self-reference loops; verifies enabled status in 4Shark — **311 lines, most complex piece of business logic** |
| `FindParentSuper()` | 901–980 | Maps supervisor to manager by matching AsesorArea with hierarchy level |
| `FindSuper()` | 1094–1135 | Finds supervisor for RAC/analyst by ResponsableCodigo lookup; recursively creates supervisor if missing |
| `LoadAnalistas()` | 1003–1022 | Adds analysts to 4Shark via `Add()` |
| `LoadCampanas()` | 208–277 | Fetches campaigns from `DB_GESTION.dbo.campanas`; creates 4Shark groups via `create_group`; **commented out at call sites** |
| `LoadCesados()` | 1173–1199 | Disables departed users via `disable_user` |
| `LoadJearquia()` | 279–300 | Executes Simplex SP `sp_reporte_jeraquia_4shark`; throws if zero rows |
| `LoadMandos()` | 399–418 | Adds managers via `Add()` |
| `LoadNuevos()` | 1165–1171 | Orchestrates new-user load: LoadMandos + LoadSupers + LoadRacs + LoadAnalistas |
| `LoadRacs()` | 982–1001 | Adds RACs via `Add()` |
| `LoadSubsidiaries()` | 180–206 | Fetches subsidiary info from Simplex `empresa` table; creates/retrieves 4Shark subsidiary via `create_subsidiary` |
| `LoadSupers()` | 880–899 | Adds supervisors via `Add()` |
| `LoadUpdates()` | 1850–1864 | Orchestrates delta updates: calls all `CheckChange*` methods |
| `RealizarCambio()` | 1866–1890 | Generic field-update primitive: `delete_user_field` then `create_user_field` — **not idempotent** |
| `RecoveryLastLoad()` | 1137–1147 | Retrieves previous snapshot from SQLite by (company, max date) |
| `RecoverySubsidiarie()` | 1202–1207 | **Hardcoded**: retrieves subsidiary with `id=1` from 4Shark |
| `SaveGroupifications()` | 850–878 | Links user to group via `start_groupification` / `finish_groupification` — **commented out in Add flow** |
| `SaveLoad()` | 168–178 | Persists jerarquias to SQLite; deletes records older than 30 days |
| `SaveUserFields()` | 733–822 | Creates user custom fields (MODALIDAD, CARGO, CECO, DESC_CECO, CLIENTE, CLIENTE_SAP, PEP, DESC_PEP, GRUPO_OCUPACIONAL, SITE) via `create_user_field` |
| `SaveUserIdentifier()` | 824–848 | Links user email as primary identifier in 4Shark via `create_user_identifier` + `select_primary_user_identifier` |
| `UpdateArea()` | 1400–1427 | Updates department via `update_user` if changed |
| `UpdateCargo()` | 1345–1387 | Updates CARGO via `RealizarCambio()` |
| `UpdateCeco()` | 1440–1500 | Updates CECO and DESC_CECO |
| `UpdateCliente()` | 1513–1572 | Updates CLIENTE and CLIENTE_SAP |
| `UpdateGroup()` | 1221–1247 | Updates user group: finishes old, starts new |
| `UpdateGrupoOcupacional()` | 1585–1637 | Updates GRUPO_OCUPACIONAL; triggers `create_promotion` / `create_demotion` if level changes |
| `UpdateMando()` | 1260–1289 | Updates manager superior via `update_user_parent` + direct SQL |
| `UpdateModalidad()` | 1650–1692 | Updates MODALIDAD |
| `UpdateSite()` | 1705–1747 | Updates SITE |
| `UpdateSuper()` | 1302–1332 | Updates supervisor manager via `update_user_parent` + direct SQL |
| `UpdateUnidadServicio()` | 1760–1819 | Updates PEP and SAP_PEP |

## External Dependencies

### Simplex — SQL Server (on-premise, Atento)

Connection string config: `appsettings.json` lines 16–19.

Servers: production, test, and dev — connection strings (with hosts and credentials) live in `appsettings.json` of the running deployment. **Do not commit or share host details outside the customer's secure channel.**

Tables/views queried:
- `DB_GESTION.dbo.campanas` (line 215) — campaigns (currently unused, code commented).
- `empresa` (line 187) — company/subsidiary info.

Stored procedures:
- `sp_reporte_jeraquia_4shark @empresa_codigo` (line 285) — **PRIMARY**: returns full hierarchy for a company. Output is the `Jerarquia` model (74 fields covering hierarchy, payroll, roles, SAP codes, client info, cost centers).

### 4Shark — SQL Server (Azure)

Connection string config: `appsettings.json` lines 21–23.

- Server / database / user — in `appsettings.json` of the running deployment. **Do not commit or share host details outside the customer's secure channel.**

Tables accessed:
- `fsk_subsidiaries`
- `fsk_users`
- `fsk_user_activities`
- `fsk_user_fields`
- `fsk_user_identifiers`
- `fsk_groups`
- `fsk_groupifications`
- `fsk_hierarchies` (referenced in models, not in service)

Stored procedures called (all via `ExecuteSqlInterpolated`):
- `create_subsidiary @name, @unique_register_id, @register_type, @external_id, @mode`
- `create_user @email, @city, @unique_register_id, @register_type, @department, @first_name, @last_name, @parent_id, @subsidiary_id, @type, @state, @external_id, @mode`
- `enable_user @user_id`
- `disable_user @user_id`
- `create_user_identifier @user_id, @value, @subsidiary_id, @mode`
- `select_primary_user_identifier @user_identifier_id`
- `create_user_field @user_id, @key, @value` (10+ call sites)
- `delete_user_field @user_id, @key, @value`
- `create_group @name, @mode`
- `disable_group @group_id, @mode`
- `start_groupification @user_id, @group_id, @date`
- `finish_groupification @user_id, @group_id, @date`
- `update_user @user_id, @department`
- `update_user_parent @user_id, @date, @parent_id`
- `create_promotion @date, @parent_id, @user_id`
- `create_demotion @date, @parent_id, @user_id`

### SQLite — local cache

- File: `Data/MEX_4Shark.sqlite`
- Tables: `jerarquias` (mirrors Simplex structure)
- Purpose: stores snapshot of last successful load to detect delta changes daily; entries older than 30 days are pruned.

### Logging

- Framework: Serilog (via `Microsoft.Extensions.Logging` adapter), configured in constructor lines 44–52.
- File path: `log/log.txt` (relative to app directory).
- Rolling: daily, up to 100 files, 20MB each.
- Level: Verbose.

## Data Flow

### Source data — Simplex
```
sp_reporte_jeraquia_4shark @empresa_codigo
  ↓
Jerarquia model (74 fields)
  ↓
List<Jerarquia> jerarquias
```

### Initial load — `LoadGlobalInitial()`
```
Simplex SP output (jerarquias)
  ↓
Extract role sets: ExtractMandos / Supers / Racs / Analistas (HashSets of employee codes)
  ↓
LoadSubsidiaries() → create_subsidiary in 4Shark
  ↓
Load users role-by-role:
  - LoadMandos()    → Add(jerarquias, type="manager")
  - LoadSupers()    → Add(jerarquias, type="supervisor")
  - LoadRacs()      → Add(jerarquias, type="rac")
  - LoadAnalistas() → Add(jerarquias, type="analyst")
  ↓
SaveLoad() — persist snapshot to SQLite (30-day retention)
```

### Daily delta — `LoadGlobalDayli()`
```
RecoveryLastLoad() — load previous snapshot from SQLite
  ↓
LoadJearquia() — fetch current Simplex hierarchy
  ↓
ExtractDiferences() via JerarquiaComparer
  → ultima_nueva (departed)
  → nueva_ultima (newcomers)
  ↓
LoadCesados() — disable departed users (disable_user)
LoadNuevos()  — create newcomers (LoadMandos + LoadSupers + LoadRacs + LoadAnalistas)
LoadUpdates() — for each user in current snapshot, run all CheckChange* methods detecting:
                Area, Cargo, Ceco, Cliente, Group, GrupoOcupacional,
                Mando, Modalidad, Site, Super, UnidadServicio
  ↓
SaveLoad() — persist updated snapshot to SQLite
```

## Non-Obvious Findings

These are observations not documented elsewhere; without explicit recording they would be lost in a future rewrite or migration.

1. **Class name typo `_4SharService`** (missing `k`). Preserved as-is in production. Any rename is a breaking change for any external reference.

2. **Repo name vs. content mismatch**: `SimplexPE.Global4Shark` vs. MEX-only configuration. No PE/global support in code despite the name.

3. **`RecoverySubsidiarie()` hardcoded to `id=1`** (lines 1202–1207). Assumes exactly one subsidiary per country. If 4Shark ever has multiple subsidiaries within a country, this breaks silently.

4. **`LoadCountryDayli()` is fully commented out**. Either dead code or unfinished. Decision needed: delete or finish.

5. **Campaign feature (`LoadCampanas` + group/campaign sync) is fully commented out.** Existing `fsk_groups` data may be stale.

6. **`SaveGroupifications()` commented out in the Add flow** even though still defined. Inconsistent state — groups managed only via `LoadCampanas` / `UpdateGroup` paths, both partially disabled.

7. **Connection strings include credentials in plaintext** in `appsettings.json` for the Simplex source. Any migration must move secrets to a vault.

8. **`FindParentMando()` is 311 lines** (420–731). Walks a 9-level hierarchy with self-reference loop checks and 4Shark enabled-status verification. **Most complex piece of business logic** — needs careful study before any rewrite.

9. **`RealizarCambio()` is the generic field-update primitive** (delete old, then create new). Used by every `Update*` method. **Not idempotent** — partial failure between delete and create leaves the user with no value for that field.

10. **`ExecuteSqlInterpolated` is used for all SP calls** — string-interpolated SQL. EF Core does parameterize the values, but the manual pattern is easy to break in a refactor.

11. **Role classification rules embedded in code** (not configurable):
    - Manager (Mando): present in DirectorPais / Director / Gerente / Jefe / ResponsableNivel4–9 fields.
    - Supervisor (Super): has `ResponsableCodigo`.
    - RAC: occupational group == 2 AND not supervisor.
    - Analyst: not manager, not supervisor, occupational group ≠ 2.

## Open Questions

1. Where should this code live long-term — Atento side (current) or 4Shark side?
2. Is the campaign feature (commented out) coming back, or is it dead?
3. What does Atento's deployment look like? Scheduling, monitoring, secrets management.
4. Is `sp_reporte_jeraquia_4shark` owned by 4Shark or by Atento?
5. Why is `LoadCountryDayli` commented out — abandoned, or planned?
6. Are the other countries (the `Global` in the name) coming, or is it firmly per-country (today MEX, next CO)?
7. Does Colombia use the same Simplex schema (and same `sp_reporte_jeraquia_4shark`) or a variant? If variant, the role-extraction logic may need to be parameterized.

## Supporting Materials

### Source code
- `~/Projects/Atento/SimplexPE.Global4Shark/` (local checkout)

### Meeting recordings (provided by Atento)
- `~/Downloads/Atento-Mexico-dessarollos/4Shark Mexico-20260408_113312-Gravação de Reunião.mp4` (277 MB, full version)
- `~/Downloads/Atento-Mexico-dessarollos/4Shark Mexico-20260409_163716-Gravação de Reunião.mp4` (98 MB)
- Backup: Google Drive (engineer-managed)

### Recordings — processing status (completed 2026-05-09)
- **Audio transcripts**: generated with `whisper-cli` + `large-v3` (Spanish) on M2 8GB, sequential.
  - `~/Downloads/Atento-Mexico-dessarollos/meeting-transcript-2026-04-08.txt` (107 KB) + `.srt` (177 KB) — 70.4 min audio, ~38 min runtime.
  - `~/Downloads/Atento-Mexico-dessarollos/meeting-transcript-2026-04-09.txt` (22 KB) + `.srt` (41 KB) — 24.6 min audio, ~27 min runtime.
- **Frame extraction (1 fps, JPEG q:v 2)**: completed against the full source files.
  - `~/Downloads/Atento-Mexico-dessarollos/frames-2026-04-08/` — 4225 frames, 1.1 GB.
  - `~/Downloads/Atento-Mexico-dessarollos/frames-2026-04-09/` — 1475 frames, 403 MB.

## Related Workstreams

- **VPN AWS ↔ Atento MX (Equinix Querétaro)**: `~/.claude/plans/active/terraform/integrator-atento-mx-vpn/PLAN.md`. Prerequisite if 4Shark ever takes over hosting and needs to reach Simplex from AWS. Currently not the case — the C# extractor runs on Atento's infra, so direct AWS↔Simplex is not yet required.

---

# Execution & Findings (2026-05-11 → 2026-05-12)

Plan from `PLAN.md` was executed across two days against the 4Shark-controlled test SQL Server (SA password in SSM `/integrator-atento/sqlserver-simplex/sa-password` in `sa-east-1` — see Terraform stack `integrator-atento/sqlserver_simplex_destination.tf`). All findings below come from real runs against staging and direct queries against the customer Simplex source (prod and homol).

- **2026-05-11**: findings #1–5 confirmed and fixed via SimplexPE PRs #1, #2, #3 and integrator PRs #2191, #2193. Findings on `fsk_user_identifiers` and `fsk_user_fields` raised as backlog (items C and D, deferred).
- **2026-05-12**: findings #6–9 implemented. Multi-country code removed (PR #7), email-identifier feature dropped (PR #8), `UploadMandos` made top-down (PR #9), `mandos ∩ supers` reprocessing eliminated and `ResolveParentMandoId` cleaned up (PR #10). All `fsk_user_fields` duplication confirmed gone after the run.

## Bugs confirmed and fixed (in this order)

### 1. SP `create_user_identifier` / `remove_user_identifier` returning wrong table in DEBUG branch
- **Where**: integrator repo, MSSQL prefixed + non-prefixed setup scripts. PostgreSQL variant uses `RETURNING *` and was not affected.
- **Symptom**: DEBUG branch of `create_user_identifier` did `SELECT * from subsidiaries WHERE id = SCOPE_IDENTITY()` instead of `SELECT * from user_identifiers`. Same kind of bug on `remove_user_identifier`. The .NET caller materializes the result as `FskUserIdentifier`, so it crashed on column mismatch.
- **Fix**: integrator PR #2191 (merged) — both MSSQL setup scripts + new `UNRELEASED` migrations for both. PG not touched.
- **Audit performed**: `/tmp/audit_debug_branches.py` scanned all DEBUG branches in all setup scripts to confirm only these two had the wrong target.

### 2. `city` empty for 100% of users
- **Where**: `Services/_4SharkService.cs:1054` and `:1620`, both passing `j.AsesorDistrito` to `EXEC create_user @city=...`.
- **Root cause confirmed by querying source**: `vDatosTotal.distrito` is populated in only 3 out of 10,076 rows in `DB_PERSONAL01.MX` (0.03%). The SP `sp_reporte_jeraquia_4shark` does `CASE WHEN asesor_distrito IS NULL THEN '' ELSE asesor_distrito END`, so `city` arrived as `""` for almost everyone.
- **Investigation chain**: confirmed there's no other column in `vDatosTotal` or in `Locales`/`tablas` that holds a real city for the employees — `Local_Descripcion` is the site (`Roma`, `Sevilla`, `Dinamarca`, `Yucatán` — all internal site names, most physically in CDMX). `Locales` has `Local_Direccion` (full address text) but no clean `Ciudad` column.
- **Fix**: SimplexPE PR #1 (merged into integration branch) — fallback to literal `"Ciudad de México"` when `asesor_distrito` is null/whitespace, with comment explaining the temporary nature. When Atento populates the source column, the next run picks up the real value automatically.

### 3. `enable_user` redundant on every user creation
- **Where**: `Services/_4SharkService.cs:1038` (`InitializeUser` always called `EXEC enable_user` after `create_user`).
- **Symptom in data**: after the first full run, `fsk_user_activity` had 1332 rows of type `enable` for 1178 users — 152 users with 2 activities, 1 with 3 (false-positive API calls to 4Shark).
- **Fix**: SimplexPE PR #1 (merged into integration branch) — `enable_user` now only fires when `last activity = "disable"` (i.e. genuine reactivation of a previously disabled user); brand-new users and already-enabled users skip it. The right semantic check, not just `wasJustCreated` as initially proposed.

### 4. Hierarchy broken — `VicePresident`s with `parent_id = NULL`
- **Where**: cascading failure starting from `ExtractAdmins` (`Services/_4SharkService.cs:436`) which ran `SELECT item_default2 FROM items WHERE tabla_codigo=94 AND item_activo=1` against the Simplex source.
- **Root cause confirmed**: `tabla_codigo=94` literally **does not exist** in `dbo.tablas` in either prod or homol — the catalog only goes up to `93`. The convention is from another country's customer instance (Peru, per the team's hypothesis), copy-pasted without validation. Cross-checked: no other `tabla_codigo` has `item_default2` pointing to employee codes, no `MX_Roles` row marks any employee as admin in the expected pattern.
- **Cascade**: `this.admins` stayed empty → `UploadAdminPrincipal` didn't create any admin → `this.admin = null` → `FindParentMando` tried `this.admin.Id4Shark` → NullReferenceException OR (when partial state) `parent_id=NULL` for every `VicePresident`.
- **Fix path (3 PRs)**:
  - SimplexPE PR #2 (merged into integration branch) — abort with `InvalidOperationException` when `ExtractAdmins` returns empty, instead of silently proceeding. First fix; later superseded by PR #3.
  - SimplexPE PR #3 (merged into integration branch, simplified to a single `EnsureAdmins` method) — full replacement: reads `Admins` (list of REs) and `RootAdmin` (single RE) from `appsettings.json`, validates both, creates all admins idempotently, anchors the hierarchy on `RootAdmin`. Removes 4 legacy methods (`ExtractAdmins`, `UploadAdminPrincipal`, `RecoverAdmin`, `HandleAdminChange`).

### 5. 11 foreign keys without index in the normalized schema
- **Where**: integrator repo, all 3 SGBDs (mssql, mssql-prefixed, pgsql-prefixed). SQL Server and PostgreSQL do not auto-create indexes for FKs.
- **Symptom**: queries like `BuildFskUserCache.Include(LFskUserActivity)` (which joins on `fsk_user_activity.user_id`) and every `Where(x => x.UserId == ...)` against `fsk_user_fields`/`fsk_groupifications` were doing full table scans.
- **Missing FKs identified**: `fsk_users(subsidiary_id)`, `fsk_users(parent_id)`, `fsk_groupifications(user_id)`, `fsk_groupifications(group_id)`, `fsk_hierarchy(user_id)`, `fsk_hierarchy(parent_id)`, `fsk_user_activity(user_id)`, `fsk_user_fields(user_id)`, `fsk_deals(client_id)`, `fsk_deals(user_id)`, `fsk_deals(product_id)`. The other 6 FKs were already covered by existing single or composite indexes (verified column-by-column against `sys.indexes` on the live DB).
- **Fix**: integrator PR #2193 (merged) — 11 indexes added to setup scripts + new `UNRELEASED` migrations for all 3 SGBDs (including a new `PGSQL-Prefixo-UNRELEASED-Migration.sql` that did not exist before). Applied to `ME_4Shark_DB` via direct `sqlcmd` after merge.

### 6. Multi-country iteration removed — single-tenant only (2026-05-12)
- **Where**: `Program.cs`, `Services/I4SharkService.cs`, `Services/_4SharkService.cs`, `appsettings.example.json`, `appsettings.exampleDevOps.json`.
- **Rationale**: the outer `foreach country in COUNTRIES` loop was a facade — Atento operates one tenant per deployment (Atento MX today, Atento CO tomorrow as a separate deployment), and the operational model (separate schedule, separate source-system adapter for Chile/BookCo, separate normalized DB) does not fit the multi-country foreach. Keeping the facade adds parameter noise to ~40 method signatures.
- **Scope discipline**: removed only country-related code. `company` / `IConfigurationSection company` / the inner foreach kept intact — company is a real domain concept (each customer can hold N companies/subsidiaries in the Simplex source), and we will revisit multi-company in a future PR.
- **Changes**:
  - `Program.cs`: removed `--country` flag (`--company` kept). `--type` now accepts `INITIAL` (0) / `DAYLI` (1) — the old `DAYLI_ALL` (2) routing to `LoadGlobalDayli` was merged into `DAYLI`, and `LoadCountryDayli` (which was an empty method body) was removed.
  - `Services/I4SharkService.cs`: `LoadGlobalInitial` → `LoadInitial`, `LoadGlobalDayli` → `LoadDayli`, `LoadCountryDayli` deleted ("Global" in the original names meant "all countries").
  - `Services/_4SharkService.cs`: removed `string countryName` parameter from ~40 methods (and `country.Key` from call sites); removed the outer `foreach country` loop; log prefixes lost the `\t{countryName}\t` segment; config lookups went from `COUNTRIES:{countryName}:{company.Key}:RootAdmin` → `COMPANIES:{company.Key}:RootAdmin`, `ConnectionStrings:{countryName}` → `ConnectionString` (analogous for `ConnectionStrings_Simplex` and `ConnectionStrings_4Shark`).
  - `appsettings.example.json` + `appsettings.exampleDevOps.json`: `COUNTRIES.MEX.{1...}` collapsed to `COMPANIES.{1...}` (keeps the company-keyed structure that the foreach iterates); connection strings flattened.
- **Fix**: SimplexPE PR #7 (merged into integration branch).

### 7. `fsk_user_identifiers` polluted with email — feature dropped (2026-05-12)
- **Where**: `Services/_4SharkService.cs` `SaveUserIdentifier` method + the call site in `InitializeUser`.
- **Symptom**: `SaveUserIdentifier` was writing the employee's email as the primary identifier in `fsk_user_identifiers`. Email is not a valid operational identifier for the Atento integration — the unique key is already populated as `fsk_users.external_id` via `create_user`. The whole `fsk_user_identifiers` table was effectively garbage (9827 rows of email pollution on the 2026-05-11 run).
- **Fix**: SimplexPE PR #8 (merged into integration branch) — removed `SaveUserIdentifier` and its call site entirely. No `fsk_user_identifiers` rows are emitted by the integrator any more. Migrating `external_id` to a proper primary `fsk_user_identifiers` row (and removing the dedicated column) is a future change to be decided with Atento.

### 8. `UploadMandos` lacked top-down ordering, falling into recursion (2026-05-12)
- **Where**: `Services/_4SharkService.cs` `UploadMandos` foreach + `ResolveParentMandoId` recursive branch.
- **Symptom**: `UploadMandos` iterated `this.mandos` (a `HashSet<int>`, arbitrary order), so children were often processed before their parents. `FindParentMando` → `ResolveParentMandoId` fired recursive `Add(parent)` to create the missing parent on demand. Combined with finding #9 (mandos∩supers) this caused triplication in `fsk_user_fields`.
- **Fix**: SimplexPE PR #9 (merged into integration branch) — added a top-down `NivelOrder` dictionary (`President`=1, `VicePresident`=2, ..., `Coordinator`=7) and made `UploadMandos` iterate sorted by it. Parents are always created before children; recursive path inside `ResolveParentMandoId` no longer fires.

### 9. `mandos ∩ supers` reprocessing duplicated `fsk_user_fields` (2026-05-12)
- **Where**: `Services/_4SharkService.cs` `ExtractSupers` + the now-unreachable parent-fallback in `ResolveParentMandoId` + the dead `GetExistingMandoIdFromCache` method.
- **Symptom in data (2026-05-12 run, before fix)**: 9822 users, 84417 rows in `fsk_user_fields`, **168 users with 3 rows per key on 6 keys** (`CARGO`, `SITE`, `MODALIDAD`, `GRUPO_OCUPACIONAL`, `CECO`, `DESC_CECO`). All values identical (`distinct_values=1`), pattern was `create + delete + create` — `SaveUserFields` was being called twice per user.
- **Root cause**: a person who is **both** a manager (referenced in `DirectorPaisCodigo / DirectorCodigo / GerenteCodigo / JefeCodigo / ResponsableNivel4–9Codigo`) and the direct responsible of someone (referenced in `ResponsableCodigo`) landed in both `mandos` and `supers` HashSets. `UploadMandos` processed them first; `UploadSupers` re-ran `Add()` for the same carnet. `LoadExistingUser` found the cache hit but no `enable` activity (none is emitted for newly created users after finding #3), returned `needsUpdate=true`, and `InitializeUser` re-ran `SaveUserFields` (delete-then-create cycle).
- **Fix**: SimplexPE PR #10 (merged into integration branch) — `ExtractSupers` excludes anyone already in `mandos` (mirroring the mutual exclusion that `ExtractRacs` and `ExtractAnalistas` already used). With this + the top-down ordering from finding #8, `ResolveParentMandoId` simplified to a pure cache lookup; `GetExistingMandoIdFromCache` removed (was the only place referencing `fskUserCache.TryGetValue(codigo.ToString(), …)` — a latent bug from indexing the cache by `ExternalId`).
- **Validation (2026-05-12 run, after fix)**: 9822 users, **82203 rows** in `fsk_user_fields` (−2196 vs. before fix; matches expected 168 × 6 × 2 extra rows = 2016). All 4 duplication queries returned zero rows.

## Architectural findings (not fixed yet — backlog)

### A. App is still single-threaded, single-process, sequential
- Zero usage of `async`/`await`/`Task`/`Parallel.ForEach`/`Thread`/`Quartz`/`Hangfire`/`Timer` in the entire codebase.
- `<OutputType>Exe</OutputType>` (console app, not Worker Service).
- `4Shark.bat` is packaged → external scheduler (Windows Task Scheduler) triggers the exe.
- Refactor required before any parallelization attempt: mutable instance state (`this.jerarquias`, caches), single shared `DataContext`, blanket `try/catch` swallowing errors. See `SPIKE-parallelization.md` for the full analysis and the 3 migration paths.

### B. Hierarchy data quality (`FindParentMando` / `FindParentSuper` NREs) — deferred
- Several `NullReferenceException` cases in logs for mandos like 38353, 40296, 40189 — not yet investigated. The PR #3 fix removes one cause (admin being null), but other paths in `FindParentMando` may still NRE on bad source data. Track and revisit when working on the LoadDayli hierarchy update flow.

### C. `SaveUserFields` does blind delete-then-create on reactivation (found 2026-05-12)
- **Where**: `Services/_4SharkService.cs` `SaveUserFields` (called by `InitializeUser` when `Add()` decides `needsUpdate=true`).
- **Behavior**: deletes every existing `fsk_user_fields` row for the user (type `create` or `update`) and re-creates all of them from the current `Jerarquia`. No comparison with previous values.
- **Impact at initial load**: zero (table is empty for new users, so the DELETE is a no-op).
- **Impact on reactivation** (cesado that returns to active): generates `2N` extra rows in `fsk_user_fields` even when zero values changed — `N` "delete" rows + `N` "create" rows on an append-only table. Wasteful and clutters the per-user history.
- **Note**: the `LoadDayli` `CheckChange*` flow already does this **right** via `RealizarCambio` (`_4SharkService.cs:1485+`) — it compares `fsk.Value != value` and only emits delete/create when the value actually changed. The fix is to make `SaveUserFields` on reactivation follow the same pattern (per-key compare-then-write).
- **Plan**: tackle together with the LoadDayli hierarchy-update work — same area of the code, same semantics (smart per-key update).

## Resolved open questions (from original ANALYSIS.md)

- **Q1 (Where should this code live long-term)**: still open, but interim agreement is the 4Shark team is now actively fixing it on a fork (PRs #1/#2/#3 on `feature/4shark-improvements`) — eventual upstream of accumulated fixes to `atento/develop` planned at the end of the cycle.
- **Q5 (Why is `LoadCountryDayli` commented out)**: answered — it was an empty method body (not just commented). Confirmed abandoned, removed in finding #6 (multi-country code removal).
- **Q6 (Multi-country support)**: answered — the foreach didn't fit Atento's real operational model. Multi-country code removed in finding #6; per-country instances is the path forward.

## Data quality summary (LoadInitial against the full source — 2026-05-12, all fixes 1–9 applied)

| Table | Rows | Notable |
|---|---|---|
| `fsk_users` | 9822 | Single insert per user (no duplication). Type distribution mostly tracks the source hierarchy |
| `fsk_user_activity` | 0 | No activities created — finding #3 (`enable_user` only on reactivation) means brand-new users skip it. Acceptable but worth confirming downstream consumers don't depend on an initial `enable` row |
| `fsk_user_identifiers` | 0 | Finding #7 — feature removed; the email-based identifier was useless |
| `fsk_user_fields` | 82203 | No `(user_id, [key])` duplicates after findings #8 and #9. Average ~8.4 fields per user (mandatory + optional combined) |
| `fsk_versions` | 1 | Only `3.0-p1` (the indexes migration runs without recording its own version per UNRELEASED policy) |

### Earlier run (2026-05-11, fixes 1–5 only — for comparison)

| Table | Rows | Notable |
|---|---|---|
| `fsk_users` | 9827 | Different source population at the time |
| `fsk_user_activity` | 1332 | Redundant `enable` for 152 users (later fixed by #3) |
| `fsk_user_identifiers` | 9827 | All `primary=false`, all email values |
| `fsk_user_fields` | 84520 | 168 users with 3 rows on 6 keys (later fixed by #8 + #9) |

## Credentials / access discovered during execution

Do **not** record customer hosts, ports, usernames, or passwords here. References:

- **4Shark normalized destination (Atento test)** — Terraform stack `integrator-atento/sqlserver_simplex_destination.tf` defines the instance, IAM, and the SSM SecureString parameter that holds the SA password (`/integrator-atento/sqlserver-simplex/sa-password` in `sa-east-1`). Read the Terraform file for the current IP/instance ID.
- **Customer Simplex (prod / homol / dev)** — connection strings live in `appsettings.json` of the deployed SimplexPE binary. Treat that file as secret material; do not paste its contents anywhere outside the customer's secure channel.

## How to reproduce these investigations

Generic playbook for the work done in this session — the actual SQL files (and their outputs) are throwaway; what matters is being able to regenerate them against the current state of the DBs whenever needed.

## Pending source-side changes (Atento — escalate to Hernan)

These are **data gaps in the customer source** that the integrator cannot fix on its own. Until Atento populates them, the integrator applies fallback behavior (admin as parent) and continues — but the hierarchy in 4Shark is not accurate until the source is corrected.

### Areas missing from `vw_empresa_area_codigo_jeraquia` (MX)

The view `vw_empresa_area_codigo_jeraquia` maps each `Area_codigo` to its hierarchy levels (nivel00..nivel09 with responsable codes). When `FindParentSuper` looks up an Area_Codigo that is not in this view, it cannot resolve a real parent.

Areas detected as missing after the run on 2026-05-11 (13 supervisors affected):

| Area_Codigo | Area_Descripcion | Supervisors impacted |
|---|---|---|
| 449 | JEFATURA RECLUTAMIENTO CALL | 1 |
| 688 | COORDINACION NEGOCIO SEGUROS BBVA - BBVA - E009 | 8 |
| 534 | COORDINACION NEGOCIO SAC BBVA - BBVA - E060 | 2 |
| 616 | JEFATURA ACTIVO FIJO & LOGISTICA | 1 |
| 414 | GERENCIA SR NEGOCIO BBVA COBRANZA / HUNTING / PR... | 1 |

**Action**: Atento needs to register the hierarchy chain (nivel00..nivelN responsables) for these 5 Area_Codigo in `vw_empresa_area_codigo_jeraquia`. After that, on the next integrator run, the affected supervisors will get their real parent (instead of the root admin fallback).

### Stored procedure `sp_reporte_cesados_4shark` does not exist on the source

The integrator calls two SPs against `DB_PERSONAL01`: `sp_reporte_jeraquia_4shark` (exists and works) and `sp_reporte_cesados_4shark` (used by `LoadCesadosRango` to fetch already-terminated employees on the initial load). The cesados SP does **not** exist on the customer source database — confirmed by listing `sys.procedures` filtered by `name LIKE '%cesados%'`: the database has multiple legacy SPs (`SP_GET_EMPLEADOS_CESADOS`, `SP_REPORTE_CESADOS_FECHA_ATENCION`, etc.) but not `sp_reporte_cesados_4shark`.

The source code for the SP **is** committed in the repo: `~/Projects/Atento/SimplexPE.Global4Shark/sql/sp_reporte_cesados_4shark.sql`. It needs to be created (`CREATE PROCEDURE`) on `DB_PERSONAL01`.

**Impact while missing**: `LoadCesadosRango` is wrapped in a try/catch that swallows the `Could not find stored procedure` exception, logs it, and proceeds. The run completes successfully but no users are marked as `disable` during the initial load. For a first run on a fresh `ME_4Shark_DB`, the impact is null (there are no users to disable yet). For subsequent runs, the SP is not needed — the DAYLI flow uses SQLite snapshot diffing for cesados.

**Action**: Once the `4Shark` user has `CREATE PROCEDURE` + `ALTER ON SCHEMA::dbo` permissions (see PLAN.md), upload the SP via SSMS.

### Users without CECO (Centro de Costo) in the source

`CECO` (`Centro de Costo`) is one of the `fsk_user_fields` keys the integrator populates per user. The value comes from `vDatosTotal.Ccto_Codigo`. When that column is NULL/empty on the source, the integrator skips creating the field (it does not write a NULL value) — so the user ends up without a `CECO` entry in `fsk_user_fields`.

After the 2026-05-11 staging run: **292 users out of 9827 (~3%)** are missing CECO. The other obligatory fields (CARGO, SITE, MODALIDAD, GRUPO_OCUPACIONAL) are populated for all users.

**Action**: Atento should populate `Ccto_Codigo` for those employees on the source. Until then, the affected users are visible in 4Shark with all other attributes but the CECO field will not exist. This is data quality on the source, not a bug in the integrator.

To get the current list of impacted users (breakdown by type), run against `ME_4Shark_DB`:

```sql
SELECT u.type, COUNT(*) AS sem_ceco
FROM fsk_users u
WHERE NOT EXISTS (SELECT 1 FROM fsk_user_fields f WHERE f.user_id = u.id AND f.[key] = 'CECO')
GROUP BY u.type
ORDER BY sem_ceco DESC;
```

### Connecting via `sqlcmd` to the 4Shark test SQL Server

```bash
SQLCMDPASSWORD=$(aws ssm get-parameter --region sa-east-1 \
  --name /integrator-atento/sqlserver-simplex/sa-password \
  --with-decryption --query Parameter.Value --output text) \
  sqlcmd -S <host> -U sa -d ME_4Shark_DB -C -i <script.sql>
```

Resolve `<host>` from the Terraform stack `~/Projects/4Shark/terraform/integrator-atento/sqlserver_simplex_destination.tf` (it's the `aws_instance.sqlserver_simplex.private_ip` output). Notes: `-C` is `TrustServerCertificate`; the EC2 instance has a daily auto-stop at 22:00 BRT (01:00 UTC) via EventBridge — start with `aws ec2 start-instances --region sa-east-1 --instance-ids <id>` if it's stopped.

For the customer Simplex source, connect via SSMS on the Windows machine — host and credentials live in `appsettings.json` of the running deployment (treat that file as secret). The Mac does not have VPN access to the customer's internal network.

### Investigation 1 — Data quality after a full run

Question pattern: "did the .NET app create what we expected?". Output is row-count breakdowns that reveal duplicates, missing relationships, wrong defaults.

The skeleton (run against `ME_4Shark_DB`):

```sql
USE ME_4Shark_DB;

-- 1. Population per role
SELECT type, COUNT(*) FROM fsk_users GROUP BY type ORDER BY COUNT(*) DESC;

-- 2. Activity breakdown — any over-creation? (the smoking gun in this session)
SELECT type, COUNT(*) FROM fsk_user_activity GROUP BY type;
SELECT activities_per_user, COUNT(*) AS users FROM (
  SELECT user_id, COUNT(*) AS activities_per_user FROM fsk_user_activity GROUP BY user_id
) t GROUP BY activities_per_user ORDER BY activities_per_user;

-- 3. Orphan check (FK integrity)
SELECT COUNT(*) FROM fsk_user_activity ua LEFT JOIN fsk_users u ON u.id = ua.user_id WHERE u.id IS NULL;

-- 4. Field key distribution
SELECT [key], COUNT(*) FROM fsk_user_fields GROUP BY [key] ORDER BY COUNT(*) DESC;
SELECT type, COUNT(*) FROM fsk_user_fields GROUP BY type;

-- 5. Identifier integrity (e.g. primary flag — the SP DEBUG bug)
SELECT [primary], type, COUNT(*) FROM fsk_user_identifiers GROUP BY [primary], type;

-- 6. Migration history
SELECT * FROM fsk_versions;
```

Adapt by tweaking the per-role / per-key breakdowns based on what's suspect today.

### Investigation 2 — Identifying source-of-truth for a role/flag in Simplex

Question pattern: "where does the .NET app think value X lives, and does that source actually have it?". Run against `DB_PERSONAL01` (the Atento Simplex source).

The skeleton:

```sql
USE DB_PERSONAL01;

-- 1. Does the catalog table `dbo.tablas` describe the lookup code the .NET hardcoded?
--    (this is how we confirmed tabla_codigo=94 didn't exist in MX)
SELECT * FROM dbo.tablas WHERE tabla_codigo = <code>;
SELECT t.tabla_codigo, t.tabla_descripcion, COUNT(i.item_codigo) AS items_ativos
FROM dbo.tablas t
LEFT JOIN dbo.items i ON i.tabla_codigo = t.tabla_codigo AND i.item_activo = 1
GROUP BY t.tabla_codigo, t.tabla_descripcion
ORDER BY t.tabla_codigo;

-- 2. Search the catalog by semantic name (admin / role / etc.)
SELECT * FROM dbo.tablas WHERE tabla_descripcion LIKE '%admin%' OR ...;

-- 3. Find tables whose item_default2 references employee codes (i.e. "list of people marked for some role")
SELECT t.tabla_codigo, t.tabla_descripcion, COUNT(*) AS empleados_referenciados
FROM dbo.items i
JOIN dbo.tablas t ON t.tabla_codigo = i.tabla_codigo
JOIN dbo.empleados e ON e.empleado_codigo = TRY_CAST(i.item_default2 AS int)
WHERE i.item_activo = 1
GROUP BY t.tabla_codigo, t.tabla_descripcion
ORDER BY empleados_referenciados DESC;

-- 4. Inspect any field that looks like it should hold the data we're looking for,
--    in the view that the .NET reads (vDatosTotal)
SELECT TOP 20 <columns> FROM dbo.vDatosTotal WHERE empresa_codigo = 1;
SELECT COUNT(*) AS total, COUNT(NULLIF(LTRIM(RTRIM(<col>)),'')) AS com_valor FROM dbo.vDatosTotal;
```

This is how we found that `vDatosTotal.distrito` is 99.97% empty (the city bug) and that `tabla_codigo=94` never existed.

### Investigation 3 — Validating that FKs have backing indexes

Question pattern: "is this query doing a table scan because the FK column isn't indexed?". Works for any SQL Server schema.

```sql
-- All indexes on the tables you care about, with their columns
SELECT t.name AS tabela, i.name AS indice, c.name AS coluna, ic.key_ordinal AS posicao
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
JOIN sys.tables t ON t.object_id = i.object_id
WHERE t.name IN ('fsk_user_activity','fsk_user_fields','fsk_groupifications', ...)
  AND ic.is_included_column = 0
ORDER BY t.name, i.name, ic.key_ordinal;
```

Cross-reference with the FK list (`grep "FOREIGN KEY" <setup.sql>`) and check whether each FK column appears as the **first** column of some index. A composite index `(A, B)` covers `WHERE A = ?` but not `WHERE B = ?`. This is how we identified the 11 missing FK indexes.

### Investigation 4 — Confirming an integrator schema migration works on a live populated DB

Question pattern: "if we ship this migration, will it crash on a real client DB?". Run the relevant portion only — skip the version-registering `migrate '<version>';` call so the test doesn't pollute `fsk_versions`.

For PR #2193 we extracted only the `BEGIN TRANSACTION INDEXES … COMMIT TRANSACTION INDEXES` block from `MSSQL-Prefixo-UNRELEASED-Migration.sql`, ran via `sqlcmd` (snippet at top of this section), then verified with a `sys.indexes` query (Investigation 3).
