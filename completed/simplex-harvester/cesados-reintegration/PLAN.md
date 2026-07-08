# PLAN — Reintegrate `sp_reporte_cesados_4shark` into the harvester flow

Project: `simplex-harvester` (.NET) · Context: Atento MX/CO reconciliation
Origin: divergences reported by Atento MX (118 active users disabled, 406 terminations still active, 1 negative carnet)
Reference meeting: "Usuarios Atento MX" (2 Jul 2026) — Luis Bravo (Atento) + Hernán (original author of the Simplex procedures) + Santiago/Paulo (4Shark)

## Status — RESOLVED (2026-07-07)

The termination-detection bug is fixed and in production (release **1.3.0**). Final state:

- **MX — done.** Harvester on the report path (`sp_reporte_cesados_4shark`); the padrón was reconciled this session (**286 users corrected + verified** — see "Phase 4 — execution results") and the client deliverable (spreadsheet `Atento_MX_Conciliacion_usuarios_20260707.xlsx` + reply to Luis Bravo) is prepared. Two edge cases (`enable`, carnet not in Simplex) are returned to the client to validate; the negative carnet is Atento's fix in Simplex (Arturo Mercado).
- **CO — waiting on Atento, not urgent.** CO's Simplex does not yet have `sp_reporte_cesados_4shark`, so CO stays on the unchanged hierarchy-absence fallback and keeps working as-is. It **auto-switches** to the report path the moment the SP is deployed on CO's Simplex — no code change, no redeploy. CO is **not** reporting active/inactive divergences, so there is no pressure; deploying the SP on CO is a later, optional step.
- **Group 90-day retention — deferred (separate track).** Access deactivation is immediate and operative; the 90-day **group** retention is NOT delivered — it depends on the groupification integration, blocked on group-membership source data (Atento's manual monthly upload today). Sequenced **after the VKPIs** (in progress, meeting scheduled). See `groupification-integration/PLAN.md`. The inert `ScheduleGroupExitOnTermination` added in PR #38 is a no-op today and should be removed as part of that work.

Everything remaining is external or deferred — nothing blocking on 4Shark's side:
- **Atento (Arturo Mercado):** correct the negative carnet in Simplex; regularize the old (B2) terminations; deploy `sp_reporte_cesados_4shark` on CO's Simplex when ready.
- **Luis Bravo:** validate the 2 edge-case users not found in Simplex.
- **4Shark follow-ups:** remove the inert `ScheduleGroupExitOnTermination`; retire the hierarchy-absence fallback once CO is on the report path.

## Objective

Replace termination detection by **set difference** (normalized base × current hierarchy) with the **authoritative termination source** (`sp_reporte_cesados_4shark`, based on `Empleado_Cesado.EC_Fecha_Cese`). The harvester disables **whoever the cesados SP returns** (with the real termination date), no longer whoever "disappears" from the hierarchy report.

## Architecture principle (the review's yardstick) — harvester and integrator are faithful pipes, not validators

Intentional design: Simplex → harvester (brings **raw** data into the normalized base) → integrator (takes the raw data from the base and sends it to the API **as-is**) → the **API validates and rejects**. Errors are logged by the integrator, which sends a **daily error report by email (spreadsheet of failures)** to the client. That report is the visibility source: the client sees "ran 100%" vs "ran 30%", identifies whether it is a data or a flow problem, and calls 4Shark. **Treating/validating in the harvester suppresses that visibility** (the harvester has no email logic). Therefore: our-side improvements that **add validation/treatment in the harvester are vetoed by design**; the legitimate ones are (a) making the pipe more **faithful** (propagate correctly, e.g. stop disabling on mere disappearance) and (b) anything needing automatic validation/visibility belongs to the **API + integrator report**, not the harvester.

## Meeting context (2 Jul) — what changes the understanding

- **The 90-day rule is a business rule.** Atento pays commission in arrears with a **90-day cascade**: someone who leaves in January still generates commission recorded in Jan/Feb/Mar. When Hernán delivered the procedures, the cesados one was **configurable (90 or 120 days)** and Luis asked for **90**; production ran **120**.
- **What Luis actually wants:** the employee **loses platform access** at termination, but must **remain in the groups for ~90 days** so the commission cascade can close. Paulo proposed: disable the user at termination and schedule the **group exit for termination date + 90 days**. This was confirmed workable in code (see "Group retention" below).
- **Bucket A root cause (Paulo's admission):** the refactor 4Shark did after taking over Hernán's code **collapsed three sources of truth** — Simplex/`vDatosTotal` (hierarchy), normalized base, and **cesados** — into a single direct comparison, and **dropped the cesados source**. Hernán suggested a **lighter support view** (query `empleados` directly, without `vDatosTotal`'s joins) to confirm "still active?" before disabling.
- **Atento contact for Simplex data fixes:** **Mauricio Arturo Mercado** — Simplex functional lead in Mexico (took over after the previous one left). Responsible for regularizing terminations and fixing the carnet in the source.

## The three buckets — attribution corrected by the meeting

- **Bucket A — 118 active users disabled → our code bug.** They disappeared transiently from `vDatosTotal` (e.g. a supervisor reassignment breaks a join momentarily) and the current flow disabled them. Validated with a snapshot: 116/118 present and active in the base today; 21 stuck at `pending` in the integrator. 4Shark reactivates and fixes the flow.
- **Bucket B — 406 terminations still active → TWO distinct problems:**
  - **B1 (recent, ≤90 days):** legitimate retention for the cascade — solved by the "disable at termination + keep in group 90 days" mechanism.
  - **B2 (old, >90 days, 2020–2022):** **still ACTIVE in Simplex** — never registered as terminated there (no Simplex×payroll reconciliation; with no shift registered, the automatic termination-by-absence never fires). **This is Simplex data → Atento regularizes.** The code fix does not touch them (they have no `EC_Fecha_Cese`).
- **Bucket C — carnet -138855 → Simplex data.** Negative value loaded manually into `vDatosTotal`; in SAP/Simplex the number is normal. **Atento fixes it in the source;** it propagates automatically on the next extraction. If it does not, 4Shark fixes it manually.

## Point-by-point review — our-side improvement opportunities

Every point the meeting raised, each through the lens "is there something **4Shark** can improve/fix in its own process?" — including the ones whose root cause is Atento data (there the opportunity would be a safety net on our side, not the source fix). Assessed against the architecture principle above.

| # | Point (meeting) | Nature | Decision | Status |
|---|---|---|---|---|
| 1 | 118 active users disabled (Bucket A) | Our bug | Reintegrate `sp_reporte_cesados_4shark`; stop disabling on disappearance; consider Hernán's lighter view | In scope |
| 2 | 90-day group retention (Bucket B1) | Business / our feature | Disable at termination + each group `ends_at` = last business day of `EC_Fecha_Cese + 90d` | In scope |
| 3 | `@dias_antiguedad` (SP window) | Our config | **DECIDED: 120, fixed, with documented rationale** — see "Window decision" | In scope |
| 4 | Idempotency (do not re-disable) | Our process | Guard 2 — only disable users currently `IsEnabled` in the base | In scope |
| 5 | Late-registered termination | Our process | Wide window (120) gives ample slack; apply overlap only if we ever move to "since last run" | In scope |
| 6 | Negative carnet (Bucket C) | Atento data | **Dropped in the harvester** (violates the faithful-pipe principle). Propagate as-is; client fixes the source. Automatic visibility would only come from **API** validation (app side), out of this scope | Dropped |
| 7 | Old terminations still active in Simplex (Bucket B2) | Atento data | **Dropped.** Source problem; no reliable signal on our side, not even manually. Handled by the client's temporary process (pull the 4Shark audit, cross-reference their base, flag the wrong ones) → regularize in Simplex | Dropped |
| 8 | Silent mass disable (118 in a single run) | Our process | **Dropped.** The cause (set difference) is fixed by items 1–5; with terminations from `Empleado_Cesado`, a mass disable means many real terminations, so holding it would be wrong. A guardrail also strains the faithful-pipe principle | Dropped |
| 9 | Traceability ("why was this user disabled?") | Our observability | **In scope (folded into item 3's phase).** Include the termination date/reason (`EC_Fecha_Cese`) in the `disable_user` log line — this is logging, not treatment; it respects the principle | In scope |
| 10 | Refactor collapsed three sources of truth | Our architecture | Reintroducing the cesados source (items 1–3) is the fix; review whether the simplification left other points fragile | In scope (partial) |
| 11 | Missing Simplex × payroll reconciliation | Atento process | Not ours to fix; our reach is only item 7's handling (client audit) | Out of our scope |

## Technical root cause (current code)

The current `Load()` decides terminations like this (`Services/SimplexHarvesterService.cs:619-621`):

```csharp
var cesados = this.fskUsersByExternalId.Values
    .Where(u => IsEnabled(u) && !currentExternalIds.Contains(u.ExternalId))
    .ToList();
// then: LoadCesados -> EXEC disable_user per user  (:1394-1412)
```

`currentExternalIds` comes from `sp_reporte_jeraquia_4shark` (`:570-574`), which reads `vDatosTotal` **with no termination filter** (only `modalidad_codigo not in (79,479)` and `asesor_area_codigo not in (178)`). An active user who drops off the view gets disabled; a terminated user who stays on the view never does.

## How it was before (archaeology)

The cesados SP **was already in the flow** and was removed in the refactor `11524f0` ("drop SQLite snapshot, unify Load"). Pre-refactor state (`Services/_4SharkService.cs@11524f0^`):

- **`LoadInitial` → `LoadCesadosRango` (`:313-364`):** `EXEC sp_reporte_cesados_4shark @empresa_codigo, @dias_antiguedad=DiasAntiguedadCesados(default 120)`, then `ExceptBy(jerarquias.AsesorCodigo)` (does not disable whoever returned to the hierarchy), and per termination `AddCesados → disable_user` (`:1465-1490`).
- **`LoadDayli` → `LoadCesados` (`:978`):** set difference over an **SQLite** snapshot of the previous run (`SaveLoad`/`RecoveryLastLoad`, retained 7 days). SQLite was the "last run" persistence.
- **Refactor `11524f0`** removed both SQLite AND `LoadCesadosRango`, leaving only the current base×hierarchy set difference.

## Proposed new termination flow

In the current `Load()`, per company, replace the `cesados` computation (`:619-621`) and `LoadCesados` (`:1394-1412`) with an SP-based step, keeping the guards that prevent false disables:

1. **Source:** `EXEC sp_reporte_cesados_4shark @empresa_codigo, 120` (Simplex connection).
2. **Guard 1 — do not disable whoever returned:** `ExceptBy(currentExternalIds)` (rehire / reappearance in the current hierarchy).
3. **Guard 2 — idempotency:** disable **only users currently `IsEnabled` in the base** (`:280-288`). Already-disabled users are skipped → no redundant activity, no redundant deactivate at the integrator. **This resolves the "re-disable the same user every day" concern even with a fixed window.**
4. **Action:** per eligible termination, `EXEC disable_user @user_id`, logging the termination reason/`EC_Fecha_Cese` (item 9).
5. **Remove** the base×hierarchy set difference.
6. **(Hernán's suggestion)** evaluate a lighter support view (`empleados` directly) to confirm "still active?" — optional reinforcement of Guards 1/2.

## Window decision — 120 days, fixed, with documented rationale

> **Post-merge update (PR #39).** PR #38 reintroduced the value as `DiasAntiguedadCesados` at the root of `appsettings.example.json`, which contradicted the config-envvars convention established in `62d0bef` (root scalars live as dedicated env vars; the container entrypoint rewrites `appsettings.json` with only `COMPANIES`, so a JSON-root scalar never reaches production and the value was always the code default anyway). PR #39 renames the key to `TerminationLookbackDays`, drops it from the example, and documents it as an optional per-country env-var override (default 120 in code). The rationale below is unchanged — only the config key's name and placement moved.

**Decision: `@dias_antiguedad` = 120, fixed window, plus Guard 2 (idempotency).** We keep the value that ran in production — but now **with a documented rationale**. Hernán's actual mistake was not the 120; it was leaving the value undocumented while the SP header said 90 (a contradiction that caused the confusion). With Guard 2, a fixed window does not re-disable anyone, so we do **not** need a "since last run" mechanism or last-run persistence.

**RATIONALE (must be documented in the code comment and, ideally, in the SP header):** `@dias_antiguedad` bounds **two** things — the terminations reported (`EC_Fecha_Cese >= today−N`) **and** the `empleado_historico` snapshot that enriches each termination (`eh.fecha >= today−N`, joined via INNER JOIN on `fecha_con_datos = max(eh.fecha) where EC_Fecha_Cese >= eh.fecha`). A termination near the window edge finds little/no `empleado_historico` inside the window and before the termination date → the INNER JOIN drops it → it is not reported → the user is not disabled. So the lookback window must be **larger** than the business window: **120 = 90 (retention/cascade) + ~30 (enrichment slack)**, guaranteeing terminations up to 90 days old are always reported. **It is not 90, precisely because of this edge effect.**

**Two distinct numbers, on purpose (do not conflate):** the **SP window = 120 days** (lookback to find + enrich terminations) and the **group retention = 90 days** (`EC_Fecha_Cese + 90`) are different things with different purposes. 90 is business (cascade); 120 is 90 + technical enrichment slack.

### History of the 120 value (Nov 2025 → Jun 2026)

- **The SP was always "90 days" by design** — header `-- Reporta últimos 90 dias de personal cesados` since creation (`d22cbe4`, Nov 2025), unchanged (`ad1410b` only changed casing/example). `@dias_antiguedad` has no default in the SP.
- **120 is config, not SP** — `GetValue<int>("DiasAntiguedadCesados", 120)` + `"DiasAntiguedadCesados": 120` in appsettings, introduced in `97ec0a1` (24 Feb 2026, a generic "update config" commit, **no stated reason**), contradicting the SP header. Never 90 in config. Removed in `11524f0`.

## Group retention (Bucket B1) — confirmed design

**"Do groups accept an inactive user?" — ANSWERED in code: yes, and so does the calculation.**

- `Groupification` (`app/models/groupification.rb`): `belongs_to :user, optional: true`, no active scope; `user_presence` only checks `user_id` nil/zero. The controller (`api/v3/groups/groupifications_controller.rb`) resolves the user via `UserIdentifier.get(...).user_id` (no active filter) and calls `start`. No `disabled` check.
- **Commission calculation** (`app/models/commission.rb:247-267`): `user_ids` comes **only** from group membership overlapping the period (`GroupificationHistory` overlap → `Groupification.pluck(:user_id)`); `users = User.where(id: user_ids)` — does **not** apply `User.active`. So a disabled user still in the group **is computed**.
- Edge: `finishing_date` requires `ends_at >= end of the last closed period`. A date 90 days in the future satisfies it.

**Design (simple, without the roundabout the old code did):** when processing a termination, in the same step:
1. `disable_user` (loses access immediately).
2. For each **active** groupification, schedule the exit: `ends_at = last business day of (EC_Fecha_Cese + 90 days)` — relative to the **real termination date**, not the processing day (robust to late-processed terminations).

During the 90 days the groupification_history overlaps the periods → the cascade computes; afterwards, the user leaves the groups. The harvester already has `finish_groupification` (via `SaveGroupifications`) to write `ends_at`. **Only control needed: idempotency (Guard 2) — do not reprocess whoever was already disabled.**

## Execution phases

1. **DONE — code (PRs #38, #39):** `Termination` keyless model + `Terminations` DbSet; `ProcessTerminations` (cesados SP + Guard 1 reappearance + Guard 2 idempotency + `disable_user`, logging the termination date); `ScheduleGroupExitOnTermination` + `LastBusinessDay`; set difference removed. Config key `TerminationLookbackDays` = 120 with the documented rationale, sourced as a dedicated env var (PR #39 aligned it to the config-envvars convention). Build clean (0 errors). Clean English names (no `Cesado`/`LoadCesados`).
2. **DONE — GATE resolved in code (Option A), non-blocking.** MX prod runs the report path immediately; CO stays on the hierarchy-absence fallback until its SP is deployed, then auto-switches. **No staging validation run** — the QA Simplex has no daily integration feeding it, so a staging harvester run cannot be measured meaningfully. Validation happens on the first production runs (monitoring the disable / group-exit log lines and the base snapshot).
3. **DONE — deployed to production (release 1.3.0, PR #40).** HubFlow release cut, merged to `master`, tag `1.3.0`; the build pushed the image to both prod ECRs (`harvester-mx` + `harvester-co`), verified. The MX `TerminationLookbackDays=120` env var is set on prod + staging (terraform PR #656, applied). The scheduled task picks up `:latest` on its next daily run.
4. **IN PROGRESS — Data remediation (current phase).**
   - **4Shark side (this phase):** reconcile the Atento MX survey discrepancies (users active in 4Shark that should be inactive, and inactive that should be active, plus hierarchy corrections) directly on the MX normalized base via the integrator Rails console — see "Phase 4 — reconciliation mechanism" below. Includes reactivating the 118 (incl. the 21 `pending`). Distrust-the-data first: the survey premise is confirmed and split into Atento-source vs 4Shark-fixable buckets **before** any mutation (SCRIPT-DISCIPLINE).
   - **Atento side:** Atento (Mauricio Arturo Mercado) regularizes the old terminations (B2) and the negative carnet (C) in Simplex — the discrepancies attributed to their source, not ours.
   - Recent terminations (B1) are handled automatically by the new flow (+ group retention).

## Phase 4 — execution results (2026-07-07)

Fresh audit-rake snapshot (this date, app-atento-001 company 1318 + integrator-atento-mx) reconciled against Luis Bravo's list (`usuarios atento mx.xlsx`):

- **Release 1.3.0 confirmed working in production** — of the 406 `bajas`, **235 were already correctly disabled** by the new termination-report flow (automatic). 171 remained active (old terminations, cese date outside the 120-day window → not reachable by the report).
- **Integrator (normalized base) — 124 corrected + verified:** 115 `enable_user` + 9 `disable_user` written to `fsk_user_activity` (via `Database.with_connection` + `execute_procedure`, `@mode='DEBUG'`) and confirmed by the verification script (124/124 `ok`). The app reflects these on the integrator's next run.
- **App (direct) — 162 orphan `bajas` disabled:** active in the app but absent from the normalized base (so unreachable by the integrator), disabled directly via `user.disable(by: nil)` on `app-atento-001` (162/162 `done`, `disabled_at` set immediately; disabler nil = same convention as the automated disables).
- **Total corrected this session: 286.**

Scripts kept in this folder: `preflight_/mutation_/verify_integrator_atento_mx.rb`, `app_preflight_/app_mutation_disable_atento_mx.rb`.

Pending:
- **2 `enable` with carnet absent from the normalized base** — investigate (likely anonymized/edge); not actioned.
- **Post-integrator-run validation** — after the integrator runs, re-snapshot to confirm the 124 enable/disable flipped the app `user_disabled`; whatever still diverges then is a real exception (the separation the engineer wanted).

## Phase 4 — reconciliation mechanism (integrator Rails console → MX normalized base)

The 4Shark-side survey fixes are applied to the **MX normalized base** through the integrator's Rails console (the integrator holds that connection). The active/inactive discrepancies are the primary case → **`enable_user` / `disable_user`**. Hierarchy corrections, if any surface, use `create_promotion` / `create_demotion` / `update_user_parent` (the atento-mx-hierarchy rebuild is already done via the app, so these are only for residual cases).

**Console mechanism** — the integrator's `Database` class is the normalized-base surface (`integrator/app/models/database.rb` on `master`; the same entry `integration_audit:normalized:user` uses). `Database.connect!` returns a pooled adapter (delegating via `method_missing`); `execute_procedure` (`microsoft_sql_adapter.rb:156`) runs `connection.execute("#{name} #{params}")`. In the integrator Rails console (`bin/ecs run <integrator>`):

```ruby
Database.connect!.execute_procedure(name: 'enable_user',  params: '@user_id=<id>')
Database.connect!.execute_procedure(name: 'disable_user', params: '@user_id=<id>')
```

NOT `Source.normalized.first.connect!` — that came from the dev-only `db:sql:seed` rake (`return if Rails.env.production?`). Always read integrator code from `origin/master` (production runs master; `develop` carries unreleased refactors).

**Procedures (verified — `integrator/docs/mssql-prefixed/Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql`):**

| Procedure | Signature | Writes (type) | Line |
|---|---|---|---|
| `enable_user`  | `@user_id int, @mode='PRODUCTION'` | `fsk_user_activity` (`enable`)  | :921 |
| `disable_user` | `@user_id int, @mode='PRODUCTION'` | `fsk_user_activity` (`disable`) | :939 |
| `create_promotion`   | `@date, @parent_id=NULL, @role=NULL, @user_id, @mode` | `fsk_hierarchy` (`promotion`)    | :859 |
| `create_demotion`    | `@date, @parent_id=NULL, @role=NULL, @user_id, @mode` | `fsk_hierarchy` (`demotion`)     | :880 |
| `update_user_parent` | `@user_id, @date, @parent_id, @mode` | `fsk_hierarchy` (`update_parent`) | :901 |

All are append-only log inserts (add an activity/hierarchy row; the integrator's next run propagates the change to the app). `@mode='DEBUG'` makes the SP SELECT the inserted row instead of running silently — useful for pre-flight/verification reads.

**Discipline (SCRIPT-DISCIPLINE — production MX base).** Discovery first: confirm the survey premise and split Atento-source (B2/C, not ours) vs 4Shark-fixable. Then, per bucket (enable / disable), three scripts in order — pre-flight (read-only: confirm each user is in the expected pre-state), mutation (per-user `enable_user`/`disable_user`, log each, continue past errors, lowercase variables), verification (re-read `fsk_user_activity` latest-per-user, confirm the new state). Consolidated report at the end.

## Phase 4 — survey data (supporting files, in this folder)

The reconciliation input is Luis Bravo's list (sent via Santiago on Slack) plus the client-facing conciliation deck we produced. Both live alongside this PLAN:

- **`usuarios atento mx.xlsx`** — Luis Bravo's source list. Three sheets = the three buckets, one row per user (columns include `ID 4shark de Usuario` = app `User.id`, `Identificador de Usuario` = carnet/`external_id`, `estatus atento mx`, `fecha` = cese date):
  - `activos` — **118 rows**, disabled in 4Shark (`Desactivado? = Sí`) but `estatus atento mx = Activo` → Bucket A → **`enable_user`**.
  - `bajas` — **406 rows**, active in 4Shark but `Dado de baja` with a `fecha` de cese (2020–2026) → Bucket B → **`disable_user`** (apply per the real cese date; the very old ones are B2/Simplex-data, see the buckets table).
  - `negativo` — **1 row**, carnet `-138855` (RFC `RERJ020803TZ8`) → Bucket C → Atento corrects in Simplex.
- **`Atento_MX_Conciliacion_usuarios_20260702.pdf`** — the client-facing deck (3 hallazgos: 406 / 118 / 1) presented to Atento MX. Findings 1 & 2 = 4Shark (flow reinforced by release 1.3.0 + this remediation); Finding 3 = Atento.

**Discovery must resolve the ID space before any mutation.** `enable_user`/`disable_user` write to the **normalized base** and take the normalized `fsk_users.user_id` — NOT the app `User.id` that the XLSX `ID 4shark de Usuario` column carries. The bridge is `external_id`: the XLSX `Identificador de Usuario` (carnet) → normalized `fsk_users.external_id` → `fsk_users.id`. Pre-flight resolves carnet → normalized id per row (read-only, via `Database.connect!`) and confirms each user's current activity state matches the expected pre-state; only then does the mutation run. This is the app-id-vs-normalized-id trap the integration-debug skill exists to catch — do not feed `ID 4shark de Usuario` straight into `@user_id`.

## Deploy prerequisite — cesados SP on all 4 Simplex targets (validate before enabling)

**Resolved in code (Option A) — safe to merge/deploy; no source regresses.** `ProcessTerminations` checks per-source whether `sp_reporte_cesados_4shark` exists (`OBJECT_ID`) and branches: where it exists (MX) it uses the report path (the fix); where it does not (CO) it keeps the previous hierarchy-absence behavior, unchanged, and auto-switches once the SP is deployed on that source — no code change or redeploy. This matters because CI builds one image pushed to both `-mx` and `-co` ECR (`compute_harvester.tf:93,167`), so there is no image-level isolation; the code-level fallback is what makes a shared-image rollout CO-safe. Deploying the SP on CO's Simplex is now an *optional later step* to give CO the fix, not a blocker.

Verified SP presence (tells us which sources are already on the report path):

| Harvester | ExternalIdSource | Simplex target | SP present? (VERIFIED 2026-07-03) |
|---|---|---|---|
| MX prod | `carnet` | prod Simplex (MX) | ✅ **EXISTS**, our user has EXECUTE |
| MX staging | `carnet` | QA Simplex (MX) | ✅ **EXISTS**, our user has EXECUTE |
| CO prod | `codigo` | prod Simplex (CO) | ❌ **MISSING** |
| CO staging | `codigo` | QA Simplex (CO) | ❌ **MISSING** |

**How verified:** the Simplex hosts are only reachable from inside the Atento VPC; checked by tunnelling an SSH local-forward through a Mongo box in that VPC (`4client-atento-mongo003`, `ubuntu@10.12.255.22`) and running `OBJECT_ID` + `HAS_PERMS_BY_NAME` via `sqlcmd` through the tunnel (connection strings pulled decrypted from SSM, never printed). Script: `scratchpad/check_cesados_sp_tunnel.py`.

**Conclusion:** MX (prod + staging) runs the report path (the fix) immediately. CO (prod + staging) stays on the unchanged hierarchy-absence fallback until `sp_reporte_cesados_4shark` is deployed on its Simplex, then auto-switches. No regression either way — the harvester can ship now; CO gets the fix whenever its SP is deployed.

Config verified in `terraform/integrator-atento/compute_harvester.tf` (prod) and `compute_harvester_staging.tf` (staging): CO = `codigo`, MX = `carnet`, all `ENABLED`; `DiasAntiguedadCesados` unset → 120 fallback everywhere.

**Why CO is missing (confirmed):** CO went live 2026-06-26, **after** `11524f0` (2026-05-29) removed the SP call — CO's harvester never called it, so the SP was never deployed to CO's Simplex (only the jerarquia SP, used daily). Verified missing on both CO prod and CO staging.

**Action (optional, to give CO the fix — no rollout sequencing needed):** deploy `sp_reporte_cesados_4shark` on CO prod + CO staging Simplex (MX already has it, with EXECUTE). Same SP file as MX; the MX email hardcode (`@atento.com.mx`, `sql/sp_reporte_cesados_4shark.sql:168-169`) is in `asesor_email`, unused by the flow, so it is CO-safe. The code fallback keeps CO on its current behavior until the SP lands, then it auto-switches on the next run. Re-run `scratchpad/check_cesados_sp_tunnel.py` to confirm EXISTS on CO afterward.

## Risks / considerations

- **`Empleado_Cesado` completeness:** with the pure-SP approach, someone removed from the source **without** a registered termination is never disabled — exactly case B2 (hence a Simplex data fix, not code).
- **First run after deploy:** wide window sweeps the backlog of valid terminations in one pass; the edge effect on the oldest ones is Bucket B2 (Simplex data) anyway.
- **No SP change and no last-run persistence** — the fixed 120-day window + Guard 2 removes the need for both.
- **CO Simplex lacks the SP (confirmed):** CO went live after the SP was dropped, so its Simplex (prod + staging) never had `sp_reporte_cesados_4shark`. Handled by the code fallback (Option A) — CO keeps its current hierarchy-absence behavior, unchanged, until the SP is deployed there, then auto-switches. Not a blocker.

## Follow-ups (not blocking merge — from the pre-merge code review)

0. **DONE (PR #39) — align the lookback config to the env-var convention.** The key `DiasAntiguedadCesados` was reintroduced at the `appsettings.example.json` root by PR #38, against the `62d0bef` config-envvars convention (and a JSON-root scalar never reaches the container, which the entrypoint rewrites with only `COMPANIES`). Renamed to `TerminationLookbackDays`, removed from the example, documented as an optional per-country env-var override (default 120 in code). No behavior change.
1. **Group-exit vs rehire within 90 days.** `ScheduleGroupExitOnTermination` writes `finish_groupification` with a future date (`EC_Fecha_Cese + 90`) for every active group. If the person is rehired before that date, the pending future finish still fires — it may drop them from a group they rejoined. Confirm the desired behavior with the business and handle if needed.
2. **Retire the hierarchy-absence fallback.** `DisableTerminationsByHierarchyAbsence` is a temporary dual path kept only until `sp_reporte_cesados_4shark` exists on every source (currently missing on CO prod + staging). Once CO's Simplex has the SP and is verified on the report path, remove the fallback and the `TerminationReportExists` branch so the code carries a single path.

(Resolved in the PR: the existence check is now cached per run via `terminationReportAvailable` — `TerminationReportExists` runs once, not per company. Decided to keep the 90-day group retention in this single PR rather than split it — the work was already done.)

## Sources

- `simplex-harvester@origin/master` — `Services/SimplexHarvesterService.cs:570-574,:619-621,:1394-1412,:280-288`; `sql/sp_reporte_cesados_4shark.sql`; `sql/sp_reporte_jeraquia_4shark.sql`; `Data/DataContext.cs`.
- History: `d22cbe4` (original cesados load), `97ec0a1` (introduced the 120 config, 24 Feb 2026), `11524f0` (drop SQLite + unify Load, removed the SP); pre-refactor `_4SharkService.cs@11524f0^:313-364,:978,:301-311,:1465-1490`.
- Meeting "Usuarios Atento MX" (2 Jul 2026): 90-day rule (cascade), three-sources-of-truth, B2 = Simplex data, contact Mauricio Arturo Mercado, Hernán's lighter-view suggestion.
- Validation: `integration_audit:normalized:user` + `:mongo:user` snapshot of atento-mx.
- App side: `app/models/groupification.rb`, `app/controllers/api/v3/groups/groupifications_controller.rb`, `app/models/commission.rb:247-267`, `app/models/user.rb:203` (`scope :active`).
