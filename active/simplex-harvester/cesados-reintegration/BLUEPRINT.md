# BLUEPRINT — Cesados SP reintegration in the harvester

Companion to `PLAN.md`. Method-by-method implementation design for `simplex-harvester`. Design only — no code is written until `/execute` and the Pattern Priming confirmation below is accepted.

## Files affected

- `Services/SimplexHarvesterService.cs` — the termination step in `Load()` (rewrite), plus a new termination loader and a group-retention helper.
- `Models/Jerarquia.cs` **or** a new `Models/Cesado.cs` — to carry `fecha_cese` (open sub-decision D1).
- `appsettings*.json` + config read site — reintroduce `DiasAntiguedadCesados = 120` with the rationale comment.
- `sql/sp_reporte_cesados_4shark.sql` — no logic change; optional header-comment alignment (90 → 120 rationale), and only if D1 picks the SP-column option.

## Pattern found in the sibling code (confirm before `/execute`)

Read in full: `Services/SimplexHarvesterService.cs` (current) and `Services/_4SharkService.cs@11524f0^` (pre-refactor). Observed conventions the new code will follow:

- **Structural shape:** one service class; private methods per stage; the per-company `foreach` in `Load()` calls stage methods in sequence. Each stage method is `void` (or returns `int?` for an id) and wraps its body in `try/catch`.
- **Signature shape:** positional params; the recurring shapes are `(IConfigurationSection company, DataContext dataContext4Shark)` for stage methods and `(Jerarquia j, …, IConfigurationSection company, DataContext dataContext)` for per-record helpers.
- **Return/error shape:** errors are caught inside the method, logged as `_logger.Error(e, $"MethodName\t{company.Key}\t{e.Message}")`, and the loop continues past per-record failures (no throw for per-record errors). Run-aborting failures also call `RollbarReporter.Report(e)`.
- **Naming:** domain terms inherited from the source (`cesados`, `jerarquias`, `disable_user`, `LoadCesados`). New members mirror this — e.g. `LoadCesados` (reused name for the new SP-based loader), `ScheduleGroupExitOnCese`.
- **Naming dimension:** domain-space (the value IS a termination / a group exit), not implementation-space.
- **Syntactic preferences:** `FromSqlInterpolated` for SP reads, `ExecuteSqlInterpolated` for writes, `_logger.Information` with tab-separated fields, `Stopwatch` for per-stage timing, early `TryGetValue` guards.
- **Anti-patterns checked:** the new loader is a single cohesive method (not a Per-Branch Delegation like the old `switch(GrupoOcupacional)` — role is irrelevant to `disable_user`, so that switch is dropped). No Iceberg/Parameter-Passing-Pipeline introduced.

## Change 1 — Config: `DiasAntiguedadCesados` = 120, documented

Reintroduce the key. At the read site, the fixed English comment (this is the "document the reason" requirement — do not repeat the undocumented-value mistake):

```
// Cesados lookback window, in days, for sp_reporte_cesados_4shark.
// 120 = 90 (business retention: commission is paid in arrears over a 90-day cascade,
// so a terminated user must stay reportable for ~90 days) + ~30 (technical slack).
// The slack is required because @dias_antiguedad also bounds the empleado_historico
// snapshot that enriches each termination (INNER JOIN on fecha_con_datos): a termination
// near the window edge has no historico inside the window before its EC_Fecha_Cese and is
// dropped by the join. 120 guarantees terminations up to 90 days old are always reported.
// NOT 90 — that would drop ~90-day-old terminations at the window edge.
var diasAntiguedad = Configuration.GetValue<int>("DiasAntiguedadCesados", 120);
```

The SP header still reads `-- Reporta últimos 90 dias`; it is misleading given we pass 120. Optional: align it on the next Simplex SP deploy (cosmetic; coordinate with Atento). Not required for this change.

## Change 2 — Obtain `fecha_cese` (D1 — resolved)

The cesados SP returns `fecha_cese` (`CONVERT(varchar(10), EC_Fecha_Cese, 23)` → `'YYYY-MM-DD'` string). `Jerarquia` does **not** map it, and `Jerarquia` is shared with `sp_reporte_jeraquia_4shark`, which does **not** return `fecha_cese`; adding the column to `Jerarquia` would break the jerarquia-SP mapping (EF requires every mapped property in the result set).

**Resolved: dedicated keyless model `Models/Cesado.cs`** with only the columns the flow needs (`asesor_codigo`, `carnet_empleado`, `fecha_cese`). Map the SP to it via `dataContext.Set<Cesado>().FromSqlInterpolated(...)` (register as `[Keyless]`). No `Jerarquia` change, no SP change. External-id resolution is the same rule as `ResolveExternalId` (carnet for MX / asesor_codigo for CO) — extract a small shared helper both `Jerarquia` and `Cesado` can feed, rather than duplicating. (Implementation detail, not a design fork.)

## Change 3 — New termination step in `Load()` (replaces the set difference)

Remove the current block (`SimplexHarvesterService.cs:619-621` + the `LoadCesados` call `:1394-1412`, the base×hierarchy set difference). Replace with an SP-based loader, called at the same point in the per-company sequence (after users are loaded, `currentExternalIds` is known). Design (pseudocode, not final code):

```
LoadCesados(company, dataContext4Shark):
  cesados = EXEC sp_reporte_cesados_4shark @empresa_codigo, @dias_antiguedad=120   // as List<Cesado> (D1-a)
  for each cesado:
    identity = SourceIdentity(cesado)                       // MX: carnet; CO: asesor_codigo
    if identity == null: continue
    if currentExternalIds.Contains(identity): continue      // Guard 1 — reappeared/rehired, keep active
    if not fskUsersByExternalId.TryGetValue(identity, fskuser): continue   // not on our side, nothing to disable
    if not IsEnabled(fskuser): continue                     // Guard 2 — already disabled, idempotent skip
    EXEC disable_user @user_id = fskuser.Id
    _logger.Information($"LoadCesados\tdisabled\tuser_id={fskuser.Id}\texternal_id={identity}\tfecha_cese={cesado.FechaCese}")  // item 9
    ScheduleGroupExitOnCese(fskuser, cesado.FechaCese, dataContext4Shark)
  // per-method try/catch + timing per the pattern
```

Notes:
- **No role mapping.** The old `LoadCesadosRango` had a `switch(GrupoOcupacional)` → role → `AddCesados`. `disable_user` needs only `user_id`; role is irrelevant. Dropped.
- **Guard order:** Guard 1 (reappearance) before Guard 2 (enabled) — cheapest, and a reappeared user must never be disabled regardless of base state.

## Change 4 — Group retention on termination (`ScheduleGroupExitOnCese`)

New helper. On termination, finish every currently-active groupification of the user with `ends_at = last business day of (EC_Fecha_Cese + 90 days)`.

```
ScheduleGroupExitOnCese(fskuser, fechaCese, dataContext):
  exitDate = LastBusinessDay(Parse(fechaCese).AddDays(90))
  activeGroupIds = current-active groupifications of fskuser
                   // per group: latest fsk_groupifications row by CreatedAt has Type == "start"
  for each groupId in activeGroupIds:
    EXEC finish_groupification @user_id=fskuser.Id, @group_id=groupId, @date=exitDate
```

Resolved details:
- **D2 — "last business day" (resolved w/ flag).** `exitDate` = `cese+90` rolled back to the previous weekday if it lands on Sat/Sun (weekends only; the harvester has no MX holiday calendar). **FYI to confirm with the business:** this is the literal reading of "último dia útil daqui a 3 meses"; if the cascade needs month-end alignment or holiday-awareness, revisit — not a blocker.
- **D3 — `finish_groupification` contract (resolved).** The SP is `finish_groupification(@user_id int, @group_id int, @date date, @mode)` and inserts `fsk_groupifications (user_id=@user_id, group_id, date, type='finish')` (`integrator/docs/mssql-prefixed/Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql:839`). So `@user_id` is the **real user id**. Our helper passes `fskuser.Id`. **Flagged (not fixing here):** the existing `SaveGroupifications` passes `f.Id` (the groupification row id) as `@user_id` — a latent bug that writes a finish row with the wrong `user_id`. Out of this change's scope; leave a follow-up.
- **D4 — old terminations (resolved).** `finish_groupification` only appends the finish row; the app validates on integration, where `Groupification#finishing_date` requires `ends_at >= end of the last closed period` (always `< today`). So `exitDate = max(businessDay(cese+90), today)` guarantees the app accepts it. Recent terminations (the normal case) have `cese+90` in the future and are unaffected; old ones (cese 90–120 days ago) just retain slightly longer than 90 days — harmless.
- **Active-groupification query** reuses the `FskGroupification` model (`UserId`, `GroupId`, `Type`, `CreatedAt`); shape mirrors the existing `SaveGroupifications` latest-row logic, generalized from one campaign to all active groups.

## Change 5 — Remove the set difference

Delete the `cesados = fskUsersByExternalId.Values.Where(IsEnabled && !currentExternalIds.Contains).ToList()` computation and the old `LoadCesados` body. `currentExternalIds` stays (Guard 1 uses it).

## Status of the sub-decisions

All four are resolved by research/judgment (see the sections above): **D1** dedicated `Cesado` model; **D2** weekday-adjusted `cese+90`; **D3** `@user_id` = real user id; **D4** `exitDate = max(businessDay(cese+90), today)`.

Remaining, non-blocking:
- **Pattern Priming** — confirm the "Pattern found" section before `/execute` (the only gate that needs the engineer).
- **FYI (D2)** — "last business day" is the literal reading; adjust only if the business needs month-end/holiday alignment.
- **Follow-up (out of scope)** — existing `SaveGroupifications` passes the groupification id as `@user_id` to `finish_groupification` (latent bug); leave a separate task.

## Test plan

- Staging harvester against a QA Simplex: a fresh termination (recent `EC_Fecha_Cese`) → user disabled + each active group scheduled to exit at `cese+90`; a reappeared user (in cesados and in the current hierarchy) → NOT disabled (Guard 1); a re-run → no redundant disable/activity (Guard 2).
- Verify against the base with `integration_audit:normalized:user` / `:mongo:user` (the same snapshots used in the PLAN validation).
- Confirm the commission calculation still includes a disabled-but-in-group user for a period within the 90-day window (already verified in code: `commission.rb:247-267`).
