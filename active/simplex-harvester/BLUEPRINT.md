# BLUEPRINT — CO identity key: `CarnetEmpleado` → configured external id

**Status:** EXECUTED 2026-06-23 in PR #23 (`feature/harvester-country-config`, commit `6abec1d`). Engineer signed off on: helper `SourceIdentity(j)`, the misleading-name renames (now), logging switched to `external_id=`, and a new `DefaultCity` config key (replaces the hardcoded `"Ciudad de México"` city fallback — a second CO gap found in review). All 12 identity sites route through `SourceIdentity`; `dotnet build` clean; PR marked ready (non-draft, MERGEABLE). MX behaviour unchanged (carnet path byte-equivalent). Pending before CO actually runs (Phase 21 steps 3-5, separate track): seed CO SSM, CO dry-run (confirm `AsesorCodigo` non-zero/non-empty per row so the identity guard never trips), enable schedule.
**Scope:** `simplex-harvester` ETL, `Services/_4SharkService.cs`, on top of PR #23 (`feature/harvester-country-config`, which already added `ExternalIdSource` + `ResolveExternalId`).
**Why:** CO `carnet_empleado` is NULL for ~99.94% of rows. The identity/dedup/routing layer keys on `j.CarnetEmpleado`, so CO users are filtered out before `create_user`. This is the one remaining net-new code blocker for CO (Phase 21).

## Key finding — the mismatch is source-side only

The in-memory dictionary is **already keyed by the persisted external id**, not by carnet:

```csharp
// _4SharkService.cs:216-219
this.fskUsersByCarnet = dataContext4Shark.FskUsers
    .AsNoTracking()
    .Where(u => u.SubsidiaryId == this.currentSubsidiaryId)
    .ToDictionary(u => u.ExternalId);   // <-- key = fsk_users.external_id (country-correct)
```

`external_id` is written by `create_user` via `ResolveExternalId(j, externalIdSource)` (carnet for MX, `AsesorCodigo` for CO). So the **dictionary side is already country-correct**. Every bug is on the **lookup side**, where the code uses raw `j.CarnetEmpleado` to probe/route instead of the same `ResolveExternalId(j, this.externalIdSource)`. The inconsistency is already visible today: `carnetsActuales` is built from `j.CarnetEmpleado` (L463) but compared against `u.ExternalId` (L511) — for CO that set is ~empty, so **every CO user would be flagged cesado**.

## The change — one concept

Define a single source-side identity value `= ResolveExternalId(j, this.externalIdSource)` and use it everywhere the code currently uses `j.CarnetEmpleado` **as an identity/dedup/routing key**. The dictionary keying (L219) stays as `u.ExternalId` — no change. Logging-only uses of carnet are a separate, cosmetic decision (below).

## Sites to change — identity keys (these are what break CO)

| # | Line(s) | Current | Proposed |
|---|---|---|---|
| 1 | 463-466 | `carnetsActuales` from `j.CarnetEmpleado` | from `ResolveExternalId(j, externalIdSource)` (also closes the L511 inconsistency) |
| 2 | 478-480 | `newcomersOrReactivations` filter on `j.CarnetEmpleado` | filter on the identity value |
| 3 | 485-491 | reattach `Id4Shark` via `fskUsersByCarnet.TryGetValue(j.CarnetEmpleado)` | via identity value |
| 4 | 1085-1088 | `Add` guard `if (j.CarnetEmpleado == null)` | `if (string.IsNullOrEmpty(identity))` (codigo never empty → CO not skipped; carnet still guards MX) |
| 5 | 1097-1100 | register `fskUsersByCarnet[j.CarnetEmpleado] = fskuser` | key by identity value |
| 6 | 1119-1121 | `LoadExistingUser` probe on `j.CarnetEmpleado` | identity value |
| 7 | 1409,1449,1478,1504,1523,1541,1559 | `FindEnabledUserByCarnet(j.CarnetEmpleado)` | pass identity value |
| 8 | 1434-1442 | `FindEnabledUserByCarnet(string? carnetEmpleado)` | rename method/param to external-id; body unchanged |
| 9 | 1585-1590 | `LoadUpdates` filter + `fskUsersByCarnet[j.CarnetEmpleado]` | identity value |
| 10 | 1017 | parent resolve `auxMando.CarnetEmpleado ?? ""` | `ResolveExternalId(auxMando, externalIdSource)` |
| 11 | 1225 | parent resolve `auxSuper.CarnetEmpleado ?? ""` | identity value |
| 12 | 471-474 | `preExistingEnabledCarnets` from `kv.Key` (= ExternalId) | **no source change** — already correct; rename only (see below) |

## Naming — currently misleading (4Shark Variable Naming rule)

These names now hold **external ids**, not carnets, so per the naming rule ("the name must describe what it actually holds") the current names are misleading, not just abbreviated:

- `fskUsersByCarnet` → `fskUsersByExternalId`
- `carnetsActuales` → `currentExternalIds`
- `preExistingEnabledCarnets` → `preExistingEnabledExternalIds`
- `FindEnabledUserByCarnet` → `FindEnabledUserByExternalId`

Recommendation: do the renames in this same change (same concept). Engineer confirms.

## Open decisions (need engineer sign-off before coding)

1. **Helper vs inline.** Introduce `private string? SourceIdentity(Jerarquia j) => ResolveExternalId(j, this.externalIdSource);` (domain-named, reads the cached field) and call it at each site, **vs** inline `ResolveExternalId(j, this.externalIdSource)` everywhere. Helper reduces repetition; inline keeps it explicit. Recommend the helper.
2. **Rename scope.** Do the misleading-name renames now (recommended) or defer to a follow-up?
3. **Logging sites** (1107, 1165, 1182, 1383, 1390 — `carnet={j.CarnetEmpleado}`). For CO these print empty. Switch them to the identity value, or leave carnet? Recommend switch (useful CO logs).

## Verification

- **Confirm `AsesorCodigo` shape** — `ResolveExternalId` "codigo" returns `j.AsesorCodigo.ToString()`. Confirm `AsesorCodigo` is always present and non-zero for CO active rows (Phase 19 indicated codigo is the CO identity) so the empty-guard never trips for a real CO user.
- **Build:** `dotnet build` clean.
- **Behavioral check (MX unchanged):** with `ExternalIdSource=carnet`, `ResolveExternalId` returns `j.CarnetEmpleado`, so every changed site is byte-for-byte equivalent to today for MX — the change is a no-op for MX and only activates the `codigo` path for CO. This is the safety property to assert in review.
- **CO dry-run:** against a CO test target (per Phase 21 step 4), confirm newcomers route to create (not filtered out), cesados detection does not flag the whole base, and updates resolve.

## Out of scope

- Subsidiary identity (`ReifySubsidiaries`) — keyed separately; CO is single-tenant, not affected here.
- The email change — already done (PR #23, `c504f99`).
- Infra (SSM seed, terraform `scheduled_task_harvester_co`) — Phase 21 steps 3-5, separate track.
