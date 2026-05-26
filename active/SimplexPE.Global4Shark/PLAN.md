# PLAN — Run SimplexPE.Global4Shark on a 4Shark Windows machine

**Project:** SimplexPE.Global4Shark
**Operator:** Pedro (4Shark)
**Target host:** Windows machine on 4Shark infrastructure, full local admin, network-level access to Atento databases (VPN already in place), **staging credentials only — no production credentials yet**
**Date:** 2026-05-09
**Status:** Pending execution
**Inputs:** `ANALYSIS.md` (this folder); meeting transcripts at `~/Downloads/Atento-Mexico-dessarollos/meeting-transcript-2026-04-{08,09}.txt` (partial — see Open Questions §1)

## Goal

Build and run the existing Atento .NET 6 ETL on a 4Shark-controlled Windows machine, against the test databases for which Pedro already has the connection strings. Outputs: working build, run logs, populated destination tables, list of any anomaly to investigate before 4Shark takes over operations.

---

## Phase 1 — Set up Git on the Windows machine with a read-only fine-grained PAT

The Windows machine is **pull-only** — findings travel back to the Mac, fixes are committed and pushed from there. So the PAT is scoped to a single repo with **read-only** access. No SSH keys on Windows, no commits authored from there, no personal email written to disk.

### 1.1 — Generate the PAT directly from the Windows machine

Generating the PAT on the Windows machine itself avoids the token ever transiting email/chat/copy-paste. GitHub shows the token only once — best to feed it straight into Git Credential Manager from the same browser session.

1. On the Windows machine, log into GitHub.
2. Go to `https://github.com/settings/personal-access-tokens/new` (Settings → Developer settings → Personal access tokens → Fine-grained tokens).
3. Fields:
   - **Token name**: `simplex-windows-pedro` (or anything identifiable for revocation)
   - **Expiration**: 90 days (rotate periodically; max is 1 year for fine-grained)
   - **Resource owner**: `4shark` org (the token will need org approval if 4shark requires admin approval for fine-grained PATs — request and wait for it)
   - **Repository access**: "Only select repositories" → `4shark/SimplexPE.Global4Shark`
   - **Repository permissions**:
     - `Contents`: **Read-only** (clone + fetch + pull only — no push)
     - `Metadata`: **Read-only** (mandatory, auto-checked)
   - All other permissions: leave at "No access". `Pull requests` not needed since PRs are opened from the Mac.
4. Generate. Copy the token (starts with `github_pat_...`). Keep the page open until step 1.4 succeeds — you cannot retrieve it later.

### 1.2 — Install Git for Windows

1. Download from `https://git-scm.com/download/win`
2. Install with defaults — **Git Credential Manager (GCM)** is bundled and is what stores the PAT inside Windows Credential Manager, encrypted per Windows user.
3. Verify: `git --version`

### 1.3 — Configure Git Credential Manager only

No `user.name` / `user.email` is needed because no commits will be authored on this machine. Just point GCM to be the credential helper:

```
git config --global credential.helper manager
```

If you ever do need to commit from Windows in the future, add `user.name` and a noreply email (`<id>+username@users.noreply.github.com` from `https://github.com/settings/emails` with "Keep my email addresses private" enabled) at that point.

### 1.4 — Clone via HTTPS, store the PAT in GCM

```
cd C:\path\where\you\want\it
git clone https://github.com/4shark/SimplexPE.Global4Shark.git
cd SimplexPE.Global4Shark
```

The first prompt opens a browser-based auth window or a username/password prompt:
- **Username**: your GitHub username (e.g., `plribeiro3000`)
- **Password**: paste the PAT from step 1.1

GCM stores the credential under host `github.com` for the current Windows user. Subsequent `git pull` / `git fetch` / `git push` use it transparently.

### Day-to-day flow

- **Pull on Windows**: `git pull` — GCM uses the stored PAT.
- **Commit + push from Mac**: existing SSH remote keeps working unchanged. All authoring happens here.
- **Findings flow**: capture artifacts on Windows → copy to Mac → fix on Mac → commit + push on Mac → `git pull` on Windows to retest.
- **PAT expired** (after 90 days): regenerate at GitHub Settings → next pull gets a 401 → GCM re-prompts → paste the new token.
- **Revoke immediately** (e.g., Windows machine compromised): `https://github.com/settings/personal-access-tokens` → delete `simplex-windows-pedro`. Access revoked on the next call. Read-only scope means there's nothing destructive a stolen token could do — only repo source disclosure.

**Belt-and-suspenders against accidental commits on Windows:** even though the PAT cannot push, a local commit could still happen and create a divergent local branch that `git pull` then has to merge. Two cheap guards:
- After Phase 4, mark the modified file: `git update-index --skip-worktree appsettings.json`
- After Phase 6, mark the SQLite cache: `git update-index --skip-worktree Data\MEX_4Shark.sqlite`

These keep `git status` clean despite the local edits, so a stray `git commit -a` doesn't sweep them up.

---

## Phase 2 — Install .NET 6 SDK

The project targets `net6.0`. .NET 6 reached Microsoft EOL in November 2024 but the SDK is still downloadable.

1. Download from `https://dotnet.microsoft.com/download/dotnet/6.0` — Windows x64 SDK installer
2. Run the installer (admin rights confirmed)
3. Verify: `dotnet --version` → expect `6.0.x`
4. Verify: `dotnet --list-sdks`

If for any reason .NET 6 SDK won't install: bump `<TargetFramework>net6.0</TargetFramework>` → `net8.0` in `SimplexPE.Global4Shark.csproj` and `dotnet build`. EF Core 6 packages should resolve under .NET 8 SDK; if anything breaks (Serilog 3.1.1, SSH.NET 2020.0.2, CommandLineParser 2.9.1), report and decide per case. Do not commit a framework bump unless validated.

---

## Phase 3 — Restore packages and build

```
cd C:\...\SimplexPE.Global4Shark
dotnet restore
dotnet build
```

Expected output: `bin\Debug\net6.0\SimplexPE.Global4Shark.dll` plus a copy of `appsettings.json` (the `.csproj` declares `CopyToOutputDirectory: PreserveNewest`).

---

## Phase 4 — Point appsettings.json at the test environment

The committed `appsettings.json` has connection strings pre-loaded under these keys (treat the file as secret — host details are sensitive, do **not** copy them outside the customer's secure channel):

| Key | Environment |
|---|---|
| `ConnectionStrings_Simplex:MEX` | **PRODUCTION** Simplex |
| `ConnectionStrings_Simplex:MEX_TEST` | TEST Simplex |
| `ConnectionStrings_Simplex:MEX_DEV` | DEV Simplex |
| `ConnectionStrings_4Shark:MEX_4S` | **PRODUCTION** 4Shark normalized DB |
| `ConnectionStrings_4Shark:MEX` | Test / Dev 4Shark normalized DB (verify in the file — historically had a copy-paste pointing at Simplex DEV) |

The code (`Services/_4SharkService.cs`) reads connection strings by **literal `countryName`** from the `COUNTRIES` config section. With `COUNTRIES:MEX` active (the only entry), it resolves `ConnectionStrings_Simplex:MEX` and `ConnectionStrings_4Shark:MEX`. **A default run as committed = production Simplex + a broken 4Shark target — verify before any run.**

**Required edit (do NOT commit):**

1. Replace `ConnectionStrings_Simplex:MEX` value with the **STAGING** Simplex string (Pedro's credentials).
2. Replace `ConnectionStrings_4Shark:MEX` value with the **STAGING** 4Shark string (Pedro's credentials).
3. **Defense-in-depth — also overwrite (or empty) the prod-pointing entries** so the file on this machine has no prod connection details at all:
   - `ConnectionStrings_Simplex:MEX` (the original prod string)
   - `ConnectionStrings_4Shark:MEX_4S` (the prod 4Shark Azure SQL string)

   Pedro doesn't have prod credentials anyway, but removing them locally guarantees that no code path on this machine can ever try to authenticate against prod — turning an "auth-failure-in-logs" risk into "wrong server, instant TCP fail or doesn't even attempt".
4. Rebuild (`dotnet build`) — the `.csproj` `CopyToOutputDirectory: PreserveNewest` will refresh `bin\Debug\net6.0\appsettings.json`.

Mark the file as locally-modified-only to prevent accidental commit:
```
git update-index --skip-worktree appsettings.json
```
Reverse with `--no-skip-worktree` if needed.

---

## Phase 5 — Verify reachability from the Windows machine

```
Test-NetConnection <simplex-test-host> -Port 1433
Test-NetConnection <4shark-test-host> -Port 1433
```

Both must return `TcpTestSucceeded : True`. If either fails: VPN/firewall investigation before running anything.

---

## Phase 6 — Prepare local SQLite cache

The repo ships two SQLite files in `Data/`:
- `MEX_4Shark.sqlite` — the snapshot from Atento's last working environment (committed binary, age unknown — **stale**)
- `MEX_4Shark_vacio.sqlite` — empty schema

For a clean test, replace the working file with the empty one:
```
copy Data\MEX_4Shark_vacio.sqlite Data\MEX_4Shark.sqlite
```

Without this, the first daily-load (`-t 2`) would diff against a months-old snapshot and likely classify the entire current population as "departed + new" — producing a massive `disable_user` + `create_user` storm. The right sequence is therefore: **initial load (Phase 7) before daily load (Phase 8).**

---

## Phase 7 — Run the initial load (`-t 0`)

`-t 0` invokes `LoadGlobalInitial`, which fetches the full Simplex hierarchy and creates every user in 4Shark from scratch.

**Pre-check:** the destination 4Shark test DB must be empty for this to succeed cleanly — `create_user` will hit duplicate-key conditions if users already exist with the same external IDs. If Pedro has DBA access on the test DB (admin rights on the machine but the DB is remote — confirm), truncate the `fsk_*` tables before running:

```sql
DELETE FROM fsk_groupifications;
DELETE FROM fsk_user_fields;
DELETE FROM fsk_user_identifiers;
DELETE FROM fsk_user_activities;
DELETE FROM fsk_users;
DELETE FROM fsk_groups;
DELETE FROM fsk_subsidiaries;
```

(Order matters because of foreign keys. `DELETE` rather than `TRUNCATE` because of FK constraints — adjust if the test DB allows TRUNCATE.)

Run:
```
dotnet run -- -t 0
```

Tail `log\log.txt` (Serilog daily roll, up to 100 files × 20 MB).

**Validate against the destination DB** (SSMS or `sqlcmd`):
- `SELECT COUNT(*) FROM fsk_users` — should match the row count returned by `EXEC sp_reporte_jeraquia_4shark @empresa_codigo=1` against Simplex TEST
- `SELECT COUNT(*) FROM fsk_subsidiaries` — should be ≥ 1 (typically exactly 1, given `RecoverySubsidiarie` hardcoded `id=1`)
- `SELECT COUNT(*) FROM fsk_user_fields` — roughly users × 10 fields (MODALIDAD, CARGO, CECO, DESC_CECO, CLIENTE, CLIENTE_SAP, PEP, DESC_PEP, GRUPO_OCUPACIONAL, SITE)

Confirm `Data\MEX_4Shark.sqlite` now contains one snapshot row per Simplex employee.

---

## Phase 8 — Run the daily load (`-t 2`)

`-t 2` invokes `LoadGlobalDayli`: read previous snapshot from local SQLite, fetch current hierarchy from Simplex, diff, apply create/disable/update.

```
dotnet run -- -t 2
```

Immediately after Phase 7: small or zero delta expected. This validates the no-op path.

---

## Phase 9 — Force a synthetic delta (optional, recommended)

Exercise the `Update*` and `LoadCesados` paths with a controlled change:

1. In Simplex TEST, manually update one employee's `Cargo`, department, or active flag (Pedro has the credentials — should be doable).
2. `dotnet run -- -t 2`
3. Verify in `log\log.txt` that the corresponding `CheckChange*` / `Update*` method fired.
4. Verify in the destination DB that the change landed (and only that change).

This is the cheapest way to confirm `RealizarCambio`, `update_user_parent`, `disable_user`, `create_promotion/demotion` are intact end-to-end.

---

## Phase 10 — Wrap up

1. Capture run artifacts in a local folder (e.g., `C:\Temp\simplex-run-YYYY-MM-DD\`):
   - `log\log.txt`
   - `Data\MEX_4Shark.sqlite` (post-run)
   - Any error output captured from the console
2. Copy artifacts back to the Mac for archiving under `~/.claude/plans/active/SimplexPE.Global4Shark/run-YYYY-MM-DD/`.
3. Open issues in the 4Shark fork for any failure or anomaly, referencing line numbers in `_4SharkService.cs`.
4. **Do not commit** the modified `appsettings.json` or the post-run `Data\MEX_4Shark.sqlite`. The `--skip-worktree` flag from Phase 4 covers `appsettings.json`; for the SQLite, simply discard local changes.
5. Move this plan from `active/` to `completed/SimplexPE.Global4Shark/` once finished.

---

## Phase 11 — Eliminate the local SQLite cache (2026-05-13) — ✅ DELIVERED

Delivered by PR #11 (`refactor: drop SQLite snapshot, unify Load, and clean up dead code`), merged into `feature/4shark-improvements` on 2026-05-13 (squashed commit `4f198b2`, merge commit `61f97de`). Net: 27 files changed, +309/-1091 lines. Includes: SQLite removal, unified `Load()`, raw-SQL ROW_NUMBER() per-user batch in `LoadUpdates`, multi-company isolation hardening (cesados scope via parent-id ancestry, `LoadJearquia` self-resetting state, Extract\* unconditional HashSet reset, `break`→`continue`), GRUPO_OCUPACIONAL user_field + broken promotion machinery removed, `--company` CLI + CommandLineParser package removed, 13 dead `Comparer` classes + 4 dead model entities (Log/LogDetalle/Campana/Empresa) + dead `FileHelper` + dead `GetDataContextSQLite` + `EFCore.Sqlite`/`EFCore.InMemory` package references removed.

### Why

The local `Data/MEX_4Shark.sqlite` was the source-of-truth for "what was loaded in the previous run", powering `ExtractDiferences` and the `CheckChange*` filters via in-memory `Except`/`Intersect` against the `_jerarquias` snapshot.

Three concrete problems with that design:
- **Stale on idle**: today's expiration is `fecha_extraccion <= today - 7 days`. If the integrator runs once and then stays idle for over a week, the next run finds an empty SQLite, treats every Simplex row as a newcomer, and the comparison logic is silently lost. Retention by execution count (e.g. last 15) was an intermediate proposal that doesn't fix the deeper problem.
- **Two sources of truth**: the 4Shark normalized SQL Server already holds the authoritative state. Keeping a parallel snapshot in SQLite invites drift and bugs (e.g. someone disables a user directly in 4Shark — the next `LoadDayli` thinks the user is still active because the SQLite snapshot disagrees).
- **Duplicated work**: `BuildFskUserCache` already loads the entire `fsk_users` from the 4Shark server. `RecoveryLastLoad` loads the previous Simplex snapshot from SQLite. Both serve the same comparison purpose.

### Approach — per-user batch load against 4Shark, not bulk-load of everything

Eager-loading every field for every user back into the process (the `fskFieldCache` of an earlier draft) recreated the same memory problem the SQLite was causing — just with less structure. The DB is optimised for this; the right place to keep field/activity history is the SQL Server, queried on demand per user.

**Persistent in-memory state** (lives across the whole run, used to decide newcomers/cesados/reactivations):

```csharp
private Dictionary<string, FskUser> fskUserCache;        // keyed by ExternalId (carnet)
private Dictionary<int, string> lastActivityByUserId;    // user_id → "enable" | "disable" | …
```

For Atento MX (~10k users) this is ~5 MB. For a tenant with 100k users it grows to ~50 MB — linear in user count, independent of activity history and field volume.

**Per-user batch load** (inside the `LoadUpdates` foreach, discarded between iterations):

```csharp
foreach (var j in this.jerarquias)
{
    if (j.CarnetEmpleado == null || !preExistingEnabledCarnets.Contains(j.CarnetEmpleado))
        continue;

    var fskuser = this.fskUserCache[j.CarnetEmpleado];

    // 1 query — all fields currently held for this user
    var userFields = dataContext.FskUserFields
        .Where(f => f.UserId == fskuser.Id && (f.Type == "create" || f.Type == "update"))
        .GroupBy(f => f.Key)
        .Select(g => g.OrderByDescending(f => f.Id).First())
        .ToDictionary(f => f.Key);

    // Every UpdateX consults `userFields` instead of issuing its own SELECT.
    if (j.GrupoOcupacional != 2) UpdateMando(j, fskuser, …);
    else UpdateSuper(j, fskuser, …);

    UpdateArea(j, fskuser, userFields, …);
    UpdateCargo(j, fskuser, userFields, …);
    // …
}
```

Active memory per iteration: ~2 KB (10 fields × ~200 B). Garbage-collected as soon as the next user is processed.

**Cost vs the alternatives**:

| Approach | Persistent cache | Per-user cache | Queries during LoadUpdates | Time (Atento MX, 10k users) |
|---|---|---|---|---|
| Original SQLite | ~25 MB (full snapshot) | — | 1 SQLite read | ~5 min |
| Bulk-load (rejected) | ~35 MB (users + activities + fields) | — | 2 SQL Server bulks | ~5 min |
| **Per-user batch (this phase)** | **~5 MB** | **~2 KB** | **~10k SQL Server pointed queries** | **~5–6 min** |
| Naive inline queries | — | — | ~100k SQL Server pointed queries | ~15–20 min |

The per-user batch keeps memory linear in users (not in users × fields × activity), and relies on the `fsk_user_fields(user_id)` index added by integrator PR #2193 so each query is O(log N + ~10).

### Steps

1. **Trim `BuildFskUserCache`**:
   - Drop the `Include(u => u.LFskUserActivity)` — the activity history is no longer eagerly loaded.
   - Add a second query that builds `lastActivityByUserId` (`GroupBy(a => a.UserId).Select(g => g.OrderByDescending(a => a.Id).Select(a => a.Type).First())`).
   - Provide `private bool IsEnabled(FskUser u)` and replace every `fskuser.LFskUserActivity?.OrderByDescending(...)…` site with this helper.

2. **Add a `newcomers / cesados / reactivations` block in `LoadDayli`** based on the cache:
   - Newcomers/reactivations = `jerarquias.Where(j => !preExistingEnabledCarnets.Contains(j.CarnetEmpleado))`
   - Cesados = `fskUserCache.Values.Where(u => IsEnabled(u) && !carnetsAtuais.Contains(u.ExternalId))`
   - Reattach `Id4Shark` for persistent users via the cache.

3. **`LoadUpdates` per-user batch**:
   - Iterate `this.jerarquias`, skip everyone that isn't in `preExistingEnabledCarnets`.
   - For each user: 1 query to materialise that user's `userFields` dictionary.
   - Each `UpdateX` (for field-bearing keys) receives `userFields` as a parameter and resolves via dict lookup; no extra SELECTs.

4. **Update signature of `UpdateUserField` / `UpdateGrupoOcupacionalField`** to take the per-user `Dictionary<string, FskUserField> userFields` instead of querying `dataContext.FskUserFields` themselves.

5. **Remove the legacy machinery**:
   - Methods: `SaveLoad`, `RecoveryLastLoad`, `ExtractDiferences`, `LoadCesadosRango`, `AddCesados`, all 10 `CheckChange*`.
   - Fields: `_jerarquias`, `cesados`, `ultima_nueva`, `nueva_ultima`.
   - Config: `ConnectionString` (SQLite path) and `DiasAntiguedadCesados` from the example appsettings.

6. **Build + smoke-test** against `ME_4Shark_DB`:
   - `fsk_users` count matches the source row count
   - `fsk_user_fields` no duplicate `(user_id, key)` pairs (continuation of PR #10 validation)
   - LoadDayli on a synthetic delta still detects all the changes that the SQLite-based version detected (parent changes, field changes, cesados, reactivations)

7. **PR**: single commit against `feature/4shark-improvements`.

### Items that fall out of this work (track separately if not delivered in the same PR)

- **Reactivation path of `SaveUserFields`** (backlog item C in ANALYSIS.md) — same compare-then-write semantics now exist in `RealizarCambio`; `SaveUserFields` can pick that up next.
- **`fsk_users.type` not updated in LoadDayli** — `update_user` only takes `@department` today, so a Manager promoted to Director never has the `type` column refreshed. Out of scope unless aligned with Atento/4Shark on promotion semantics, but worth flagging.
- **Real promotion / demotion detection — rebuild as its own subsystem (deferred to the alteração-de-hierarquia phase).** Context surfaced during PR #11 fresh review on 2026-05-13. The previous implementation was a gambiarra: it stored the source's `GrupoOcupacionalDescripcion` (a string like "Manager", "Analista") as a `fsk_user_fields[GRUPO_OCUPACIONAL]` row, and on every daily run `UpdateGrupoOcupacionalField` → `ProcessGrupoOcupacionalChanges` tried `int.Parse(oldValue)` on that description to compute promotion/demotion. The parse always threw (description is never numeric); the catch in `UpdateGrupoOcupacional` swallowed it; `create_promotion` / `create_demotion` were never invoked. The conceptually correct sibling (`CheckChangeGrupoOcupacional` + `GrupoOcupacionalComparer`) depended on the SQLite snapshot that PR #11 removed. PR #11 deleted both paths plus the user_field they fed. **`Models/Jerarquia.cs:GrupoOcupacionalDescripcion` was intentionally kept** in case the real solution wants to reuse the description string. **When designing the real feature:** (1) the integrator's `update_user` SP needs to accept `@type` (or a new SP `update_user_type`) so the role transition on `fsk_users.type` can be persisted — without that, even with detection working, the source-of-truth column never reflects reality; (2) detection logic compares `fsk_users.type` (previous state) against the role derived from the current run's classification (Mando vs Super vs Rac vs Analista — see `_4SharkService.cs:434,446,1196`); (3) on transition, fire `create_promotion` or `create_demotion` with `@parent_id` and `@user_id`; (4) **alignment needed with Atento** on which `fsk_users.type` transitions count as promotion semantically — every Director ↔ Manager ↔ Supervisor ↔ SalesRepresentative pairing, or only specific ones (SalesRepresentative → Manager seems to be the canonical example the engineer mentioned); (5) decide whether within-SalesRepresentative finer-grained transitions (Rac ↔ Analista, both `type="SalesRepresentative"` but distinguished only by `j.GrupoOcupacional == 2` from source) also count — if yes, will need either a new `fsk_users` column or a secondary state store, since `fsk_users.type` cannot distinguish them.

  **Additional finding surfaced on 2026-05-13 while triaging PR #11 review comments — 4-role vs 2-branch mismatch in `LoadUpdates`.** The pre-existing `LoadUpdates` logic (`_4SharkService.cs:1196-1203`, kept as-is by PR #11) has only two branches for routing the parent-update path:
  ```csharp
  if (j.GrupoOcupacional != 2) UpdateMando(...);  // → FindParentMando: walks hierarchy (Director → Gerente → ...) for the next mando UP
  else                          UpdateSuper(...);  // → FindSuper: reads j.ResponsableCodigo, returns the direct super
  ```
  But there are **4 distinct roles** in `Add` / `LoadNuevos`, each created with a different parent-resolution helper (`_4SharkService.cs:849-863`):

  | Role | Parent resolver at CREATE | What `LoadUpdates` does | Status |
  |---|---|---|---|
  | Mando | `FindParentMando` (mando above in hierarchy) | `UpdateMando` (when `GrupoOcupacional != 2`) → `FindParentMando` | ✓ correct |
  | Super | `FindParentSuper` (mando owning the area) | **no branch handles it** | ✗ super's parent never refreshes if the area's mando changes |
  | Analista | `FindSuper` (direct super) | `UpdateMando` (when `GrupoOcupacional != 2`, fallback because not rac) → `FindParentMando` | ✗ analista's parent is overwritten with a mando id every daily run |
  | Rac | `FindSuper` (direct super) | `UpdateSuper` (when `GrupoOcupacional == 2`) → `FindSuper` | ✓ correct (the method name is misleading — `UpdateSuper` internally calls `FindSuper`, which is the rac/analista resolver) |

  **When this bug fires:** only from the second daily run onwards on a given user — the first run is greenfield (`fskUsersByCarnet` empty → `preExistingEnabledCarnets` empty → `LoadUpdates` body skipped via `continue`). Day 1 in production lands users with correct parents via `LoadNuevos`. Day 2+ rewrites analistas' parents from their super to a higher mando, and never refreshes supers if their mando moves. **If smoke tests ran the ETL multiple times against the same staging database during onboarding, the staging data is likely already corrupted — verify before reading any hierarchy from staging.** Production (Mexico go-live on a fresh ME_4Shark_DB) has a one-day window where data is correct.

  **What the alteração-de-hierarquia phase must do for this:**
  1. Replace the binary `if/else` in `LoadUpdates` with a 4-way switch that mirrors `GetParentIdForFlag` (`_4SharkService.cs:849-863`). The role of a pre-existing user can be derived the same way `LoadNuevos` does at create time: classify into mando / super / rac / analista using the source `j.GrupoOcupacional` + the role HashSets that `ExtractMandos/Supers/Racs/Analistas` already populate. Route each to a parent-update path that calls the *same* resolver used at creation.
  2. Add `UpdateAnalista` (calls `FindSuper`, compares with `fskuser.ParentId`, updates if changed) — currently missing.
  3. Add `UpdateSuper` *for actual supers* — the existing method named `UpdateSuper` is mis-named (it serves racs). Rename one of the two so the four methods are unambiguous: `UpdateMando`, `UpdateSuperOfRac`, `UpdateSuperOfAnalista`, plus a real `UpdateSuper` that calls `FindParentSuper`.
  4. The `j.GrupoOcupacional != 2` branch in `LoadUpdates` (and the same shape in `ExtractRacs` / `ExtractAnalistas`) treats `null` as not-rac. Decide with Atento whether this is intentional or whether NULL means "skip the user" / "data missing — fix in source first". Today the source likely never returns NULL for `grupo_ocupacional`, so it is theoretical, but the contract should be explicit in code once the 4-branch restructure lands.
  5. Decide whether this 4-role parent-update restructure can land **before** the `fsk_users.type` SP work, or must land together. Mechanically separable, but if both lands in the same PR the review is cleaner.
- **NEXT TASK after this PR — Subsidiary registration & user binding. Even with one company today, every user must be tied to a `fsk_subsidiaries` row.** This is the canonical pattern the integrator schema was designed for. Investigation during PR #11 fresh review on 2026-05-13 clarified the mental model and the user committed to this as the immediate next phase (before alteração de hierarquia).

  **Design intent (validated against integrator + app masters on 2026-05-13):**
  - `fsk_users.subsidiary_id` is **not vestigial** — it is auxiliary infrastructure deliberately kept on the integrator schema for batch integrations like this ETL. The integrator schema (`docs/mssql-prefixed/Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql` on integrator master `bddb277e`) keeps the column, the FK to `fsk_subsidiaries`, and two partial unique indexes (`idx_users_external_id` UNIQUE WHERE `subsidiary_id IS NULL`, and `idx_users_external_id_subsidiary_id` UNIQUE on `(external_id, subsidiary_id)` WHERE `subsidiary_id IS NOT NULL`). The partial-unique design is deliberate: same `external_id` (carnet) can exist in two different subsidiaries.
  - The app's v3 HTTP API does **not** accept `subsidiary_id` in the user body (neither `/api/v3/users` nor `/api/v3/subsidiaries/:subsidiary_id/users` — verified against app master `6e4ad80db`). HTTP uses identifier-based lookup with subsidiary in the URL; the resolved subsidiary id is applied to `user_identifiers` rows, not to the user record. The HTTP and batch entry points coexist by design — HTTP doesn't write `users.subsidiary_id`, the batch path (this ETL) does.

  **Canonical pattern — applies regardless of how many companies the customer has:**
  1. For every `appsettings.COMPANIES.<key>`, a `fsk_subsidiaries` row exists in the destination DB. **Even for Atento Mexico today (single company), there must be one subsidiary row.** Single-company is just a degenerate case of multi-company; the same code path applies.
  2. Every `create_user` call passes `@subsidiary_id` pointing to the resolved row. Never NULL.
  3. Every read query that scopes to a company uses `WHERE subsidiary_id = X` — single index seek.

  **First part of the work — what becomes the next PR after this one:**

  1. **Resolve subsidiary id per company**: at the start of each company iteration in `Load()`, look up (or create) the `fsk_subsidiaries` row mapped to `appsettings.COMPANIES.<key>`. Decide with Carlos whether the mapping is auto (subsidiary `external_id` matches the COMPANIES key) or explicit (a new config field per company entry like `COMPANIES.<key>.SubsidiaryExternalId`). Store the resolved id (auto-increment from `fsk_subsidiaries.id`) in a runtime variable for the iteration.
  2. **Bind every `create_user` call**: replace `object subsidiaryValue = DBNull.Value;` (`_4SharkService.cs:835`) with the resolved subsidiary id. This ties every new user to the subsidiary at creation time.
  3. **Backfill for Mexico (if any users were created before the migration)**: a one-off SQL UPDATE setting `subsidiary_id` for every existing `fsk_users` row, scoped by the parent-id ancestry to the right company. Mexico is greenfield today, so this may be a no-op for the first migration — but the script needs to exist for any prior smoke test data and for future customers who already have users.
  4. **Scope `LoadFskUsers` query**: change `dataContext4Shark.FskUsers.AsNoTracking().ToList()` to `dataContext4Shark.FskUsers.AsNoTracking().Where(u => u.SubsidiaryId == currentCompanySubsidiaryId).ToList()`. Per-company scope is now at SQL, not in memory.
  5. **Simplify cesados filter** (`_4SharkService.cs:267-271`): drop the `rootAncestorByUserId[u.Id] == this.admin.Id4Shark!.Value` clause. With `LoadFskUsers` scoped, the universe is already the current company; cesados is just "enabled and not in `carnetsActuales`".
  6. **Delete the parent-walk machinery** — this becomes dead code as soon as step 5 lands:
     - `WalkToRoot` (`_4SharkService.cs:166-192`) — removed entirely.
     - `rootAncestorByUserId` field (line 34) — removed entirely.
     - The foreach in `LoadFskUsers` that populates it (lines 150-154) — removed.
     - The `byId` dictionary built in `LoadFskUsers` (line 138) — removed (was only fed `WalkToRoot`).
  7. **`appsettings.example.json` / `appsettings.exampleDevOps.json`**: document the per-company subsidiary mapping (whatever shape is chosen in step 1).

  **What the achado #4 thread on PR #11 was about — the `WalkToRoot` self-as-root bug:** real bug, real semantics issue (a user can't be its own root). Not fixed in PR #11 because the entire `WalkToRoot` mechanism is deleted by step 6 of this next-task — fixing a method that is about to disappear is wasted work. The bug does not trigger in Atento Mexico greenfield (no orphan parent_id chains exist on day 1).

  **Open questions to settle with Carlos before starting:**
  - Why does this ETL not call `create_user_identifier`? Other 4Shark integrations create at least one primary identifier per user. Is the direct-create path intentional for Atento (single-source-of-truth via Simplex carnet), or a regression that should be paired with the subsidiary work?
  - Does Atento Mexico expect to ever run multi-company on `ME_4Shark_DB`, or will each Atento country always be its own DB? Either way the work above is the same shape; this question only affects how many subsidiary rows get created.

  **Roadmap framing**: cleanup (PR #11) → **subsidiary registration & user binding (THIS entry — next PR)** → alteração de hierarquia (promotion/demotion with proper `fsk_users.type` updates — depends on subsidiary scope being correct first, otherwise hierarquia work would entangle with the parent-walk machinery).

- **Integrator app needs an explicit `subsidiaries_module` config — implicit detection via row presence breaks once batch integrations populate `subsidiary_id`.** Flagged by Paulo on 2026-05-13 while the subsidiary-binding PR was being written. Today the app's v3 HTTP API decides whether a company has the subsidiaries module by checking `current_company.subsidiaries_module?`, which appears to be derived implicitly from the existence of `fsk_subsidiaries` rows under the company (or an equivalent shortcut). That heuristic worked while no integration populated subsidiaries from the batch side. Once the ETL starts creating `fsk_subsidiaries` rows during `ReifySubsidiaries` (this PR) and tagging users with `subsidiary_id` on `create_user`, the heuristic flips a company into "subsidiaries module" mode automatically — and any other integration that uses the root `/api/v3/users` path for that company starts getting `400 Bad Request: Use subsidiary scoped api: /api/v3/subsidiaries/:subsidiary_id/users`. Silent regression for anything that was running before. **Fix in the integrator (separate PR in `4shark/integrator`, before or together with rolling out this ETL change to production):** add an explicit boolean config on `companies` (or wherever the module flag lives) — no default value, so every existing customer is forced to opt in or opt out before the new behaviour ships. `true` → the company always uses the subsidiary-scoped API; `false` → always uses the root API. Removes the implicit row-existence detection entirely. Coordinate the rollout: integrator change → set the flag on Atento Mexico → then deploy this ETL.
- **`SaveGroupifications` is dead code — campaign membership never reaches 4Shark.** Surfaced during PR #11 fresh review on 2026-05-13. The Simplex SP `sp_reporte_jeraquia_4shark` exposes `cod_campana_4shark` (`sql/sp_reporte_jeraquia_4shark.sql:43,299`); the model `Models/Jerarquia.cs:111` captures it as `CodCampana4Shark`. The method `SaveGroupifications` in `Services/_4SharkService.cs:564-591` reads it and would call `start_groupification` / `finish_groupification` on the 4Shark side — but **the method has zero call sites**, neither in `Add()` nor in any `Update*`/`LoadUpdates` path. Net effect: every user is loaded into 4Shark without ever being attached to a campaign, and campaign transitions in Simplex are never propagated. **Confirmed pre-existing on `develop` (verified on commit `9b2d40c`, the base of PR #11)** — the PR #11 refactor did not introduce this gap, only re-exposed it during the fresh review pass. **When the campaign/groupification phase opens:** (1) confirm with Atento whether the 4Shark app side is supposed to surface campaign-level data for Mexico users (Brazil's Field count on 2026-05-13 shows that account uses keys but groupifications are tracked separately — check `fsk_groupifications` for Brazil to understand the expected shape); (2) decide whether to wire `SaveGroupifications` into `InitializeUser` (create + reactivate path) and/or `LoadUpdates` (steady-state path), or remove the dead method entirely.

---

## Phase 12 — Alteração de hierarquia (2026-05-14) — IN PLANNING

Esta fase resolve os dois bugs originalmente registrados nos fall-out items de Phase 11 ("Real promotion / demotion detection" e "4-role vs 2-branch mismatch in `LoadUpdates`") + um achado arquitetural novo de 2026-05-14: `fsk_hierarchy` é log de *intenção* da ETL, não de estado aceito pelo app.

### Source-data investigation (2026-05-14)

Queries rodadas contra `DB_PERSONAL01` / `empresa_codigo = 1` (Atento México). Dataset achatado (`vDatosTotal` + `CA_Asignacion_Empleados` + `vw_empresa_area_codigo_jeraquia`), mesmos filtros que `sp_reporte_jeraquia_4shark`. **9806 funcionários em scope** (diferença de 6 pra os 9812 do test run de 2026-05-13 é turnover dentro da janela).

**Q1 — Cobertura de `responsable_codigo` (Fonte 1) por papel inferido:**

| Papel | Total | NULL `responsable_codigo` | % |
|---|---:|---:|---:|
| Mando | 172 | 6 | 3.49% |
| Super | 306 | 16 | 5.23% |
| Rac | 6526 | 271 | 4.15% |
| Analista | 2802 | 164 | 5.85% |
| **TOTAL** | **9806** | **457** | **4.66%** |

**Q2 — Consistência Fonte 1 vs Fonte 2 pros Supers** (`responsable_codigo` vs `GetMandoCodigoFromArea`):

| Comparação | Total | Pct |
|---|---:|---:|
| COINCIDEM (ambas apontam pra mesma pessoa) | 248 | 81% |
| DIVERGEM (apontam pra pessoas diferentes) | 39 | 13% |
| AMBAS_NULL (área não mapeada + sem responsable) | 15 | 5% |
| SO_RESPONSABLE (área não mapeada, responsable existe) | 3 | 1% |
| SO_AREA (responsable NULL, area-match resolve) | 1 | 0.3% |

**Q3 — Sub-causa da falha de area-match:** 100% dos casos têm `Area_Codigo` ausente do `vw_empresa_area_codigo_jeraquia` (sub-causa `AREA_NAO_NO_VW`). Zero casos de `NOME_NAO_BATE` (nome de área não casando com nenhum nível da hierarquia) — então a heurística por texto não é o problema, é a tabela de áreas que está incompleta.

### 23 áreas que Atento precisa mapear em `vw_empresa_area_codigo_jeraquia`

Sem isso, **21 líderes** (18 Supers + 3 Mandos) caem no admin via fallback do PR #5, e 467 racs/analistas dessas áreas perdem context de área (mas seguem com pai correto via Fonte 1).

| Area_Codigo | Descrição | Total | Sup | Man |
|---:|---|---:|---:|---:|
| 403 | GERENCIA NEGOCIO TELEFONICA - B004 | 2 | 0 | 0 |
| 414 | GERENCIA SR NEGOCIO BBVA COBRANZA / HUNTING / PRESENCIAL | 250 | 1 | 1 |
| 449 | JEFATURA RECLUTAMIENTO CALL | 20 | 0 | 0 |
| 452 | JEFATURA DE COMPENSACIONES | 1 | 0 | 0 |
| 462 | JEFATURA SEGURIDAD SOCIAL | 2 | 1 | 0 |
| 465 | JEFATURA RECLUTAMIENTO PRESENCIAL | 2 | 0 | 0 |
| 466 | JEFATURA RECLUTAMIENTO - C003 | 1 | 0 | 1 |
| 481 | COORDINACION SERVICE DESK | 3 | 0 | 0 |
| 519 | COORDINACION NEGOCIO PRINCESS HOUSE - NEARSHORE - E108 | 1 | 0 | 0 |
| 534 | COORDINACION NEGOCIO SAC BBVA - BBVA - E060 | 43 | 2 | 0 |
| 562 | COORDINACION NEGOCIO SEGUROS BBVA TELEMARKETING - BBVA - E085 | 55 | 4 | 0 |
| 605 | GERENCIA NEGOCIO MULTISECTOR - B013 | 2 | 0 | 1 |
| 616 | JEFATURA ACTIVO FIJO & LOGISTICA | 5 | 1 | 0 |
| 669 | COORDINACION MEJORA CONTINUA - C003 | 12 | 2 | 0 |
| 676 | COORDINACION FORMACION TECNICA - BBVA01 | 16 | 5 | 0 |
| 688 | COORDINACION NEGOCIO SEGUROS BBVA - BBVA - E009 | 61 | 2 | 0 |
| 702 | COORDINACION NEGOCIO - MULTISECTOR - E008 | 1 | 0 | 0 |
| 712 | JEFATURA DE SELECCION DE TALENTO-ESTRUCTURA | 4 | 0 | 0 |
| 716 | JEFATURA RECLUTAMIENTO BILINGÜE | 3 | 0 | 0 |
| 767 | COORDINACION DE ADP - ESTRUCTURA | 1 | 0 | 0 |
| 773 | COORDINACION DE CONTROL DE GESTION INFRAESTRUCTURA | 1 | 0 | 0 |
| 785 | COORDINACION DE RECLUTAMIENTO BIL - C002 | 2 | 0 | 0 |
| 789 | COORDINACION RECLUTAMIENTO CALL - C002 | 1 | 0 | 0 |

**Caveat operacional:** mapear o `Area_Codigo` no view não é suficiente — a cadeia hierárquica precisa estar preenchida em cada `nivelXX_responsable_codigo`. Se Atento adicionar o `Area_Codigo` mas deixar responsáveis NULL, o area-match ainda retorna NULL e o supervisor segue caindo no admin.

### Source-of-truth — estado atual e mudança nesta fase

**Estado atual (que vamos corrigir):**
- `fsk_users.parent_id` e `fsk_users.type` são populados no `create_user` e **ficam congelados a partir daí** — o SP `update_user` não aceita `@parent_id` nem `@type`. Alterações de hierarquia vão só pra `fsk_hierarchy`. Resultado: a comparação `if (newParent != fskuser.ParentId)` em `_4SharkService.cs:1057,1079` sempre dispara depois da primeira alteração, e a ETL gera linha `update_parent` duplicada em toda execução subsequente.
- `fsk_hierarchy` é o log de pedidos de alteração. Não tem retorno do app — o app pode rejeitar (ex: Super sob Analista), mas o app envia relatório de erro pra Atento, que analisa e corrige a base origem pra que a próxima execução funcione. Não fica silencioso.

**Mudança que esta fase introduz:**
- A cada mudança hierárquica, o .NET passa a fazer **duas chamadas em transação atômica**:
  1. `EXEC <sp>` — escreve o pedido em `fsk_hierarchy` (audit log, mantém comportamento atual)
  2. `UPDATE fsk_users SET parent_id = ..., [type = ...,] updated_at = ...` — atualiza estado atual
- Wrapper único `WriteHierarchyChange(...)` orquestra os dois writes via `dataContext.Database.BeginTransaction()` + `Commit()`. Padrão novo na codebase (zero transações hoje, conforme `grep BeginTransaction|TransactionScope`).
- Existe linha comentada de UPDATE em `UpdateSuper` (`_4SharkService.cs`) que era exatamente esse padrão — alguém já tinha considerado, só não levou adiante.

**Resultado:** `fsk_users` vira o estado mais recente solicitado pela ETL, `fsk_hierarchy` continua sendo o log histórico. Comparações no `LoadUpdates` (tasks #3 e #4) usam `fsk_users.parent_id` e `.type` direto do `fskUserCache` — sem cache extra, sem fallback chain.

**Validação defensiva antes de escrever (mantida):** antes de cada `WriteHierarchyChange`, verificar `rank(new_parent.type) < rank(user.type)`. Se inválido (ex: Super sob Analista), pular a chamada e logar. Reduz o volume de erros que vão pro relatório do app.

### Algoritmo determinístico — decisão arquitetural

**Pré-condição operacional:** Atento mantém `vw_empresa_area_codigo_jeraquia` correto — áreas mapeadas, cadeia hierárquica preenchida. Sem isso, o algoritmo segue funcionando mas o fallback do PR #5 (pai = admin) cobre as falhas.

**Três regras claras, despachadas pelo papel inferido. Sem `if (GrupoOcupacional != 2)`. Sem divergência entre `LoadNuevos` e `LoadUpdates`.**

| Papel | Resolver | Resultado garantido |
|---|---|---|
| Rac / Analista | `FindSuper` — `j.ResponsableCodigo` (Fonte 1) | Direto. NULL → fallback admin. |
| Super | `FindParentSuper` — match `AsesorArea` contra os níveis (Fonte 2) | Sempre um Mando. |
| Mando | `FindParentMando` — walk-up nos níveis da própria linha (Fonte 2) | Sempre o Mando do nível imediatamente acima. |

**Cobertura sob pré-condição satisfeita: 100% pra liderança.** Todos os 478 líderes (172 Mandos + 306 Supers) têm pai correto. Racs/analistas: 95% via Fonte 1; os 4.66% restantes são problema de qualidade de dados em `CA_Asignacion` (Atento fix, fora do nosso escopo).

**Caveat dos 39 Supers DIVERGEM:** ficam com pai pelo `FindParentSuper` (Fonte 2), não `responsable_codigo` (Fonte 1). É comportamento consistente com `LoadNuevos` hoje — Supers já são criados com Fonte 2. O que muda é que `LoadUpdates` para de reescrever pro Mando errado via `FindParentMando` aplicado equivocadamente sobre Super.

### Detecção de promoção e demoção

Sobre o algoritmo determinístico, fica trivial:

1. **Pra cada usuário pré-existente:**
   - Classificar pelo papel atual no source (Mando / Super / Rac / Analista).
   - Calcular `type` correspondente (`Director` / `Manager` / `Supervisor` / `SalesRepresentative` etc — vem do nível pra Mandos via `NivelDescripciones`, fixo pra outros papéis).
   - Carregar `type_anterior` direto do `fskUserCache[carnet].Type` — já em memória, sem query extra (consequência da decisão de espelhar mudanças em `fsk_users` via UPDATE em transação).
2. **Se `type_anterior != type_atual`:**
   - `rank(type_atual) < rank(type_anterior)` (subiu) → `create_promotion @user_id @date @role @parent_id`
   - `rank(type_atual) > rank(type_anterior)` (desceu) → `create_demotion @user_id @date @role @parent_id`
3. **Se `type` igual mas `parent_id` mudou:**
   - `update_user_parent @user_id @date @parent_id`
4. **Se nada mudou:**
   - Nenhum write. Resolve o bug das linhas duplicadas.

Ranking proposto (menor = mais alto):

```
President=1, VicePresident=2, Director=3, Superintendent=4,
GeneralManager=5, Manager=6, Coordinator=7, Supervisor=8, SalesRepresentative=9
```

**Validação antes de escrever** (protege contra rejeição da API):

- Antes de qualquer `create_promotion` / `create_demotion` / `update_user_parent`, verificar `rank(new_parent.type) < rank(user.type)`. Se não, **não emitir** e logar o caso pra investigação. Defensiva — não devemos confiar que a origem sempre produz hierarquia consistente.

**Limitação conhecida:** Rac e Analista compartilham `type = "SalesRepresentative"` (mesmo rank). A transição Rac ↔ Analista não é detectável via `fsk_hierarchy.role` nem `fsk_users.type`. Se Atento quiser rastrear, precisaria campo extra. **Out of scope nesta fase.**

### Implementation outline

1. **Refactor `LoadUpdates`** (`_4SharkService.cs:1259-1317`): substituir o `if (GrupoOcupacional != 2)` por dispatch baseado no classificador. Reutiliza a mesma estrutura de 4 vias que `GetParentIdForFlag` (`_4SharkService.cs:953-968`) já usa em `LoadNuevos`.
2. **Estender o classificador** (`ExtractMandos`/`Supers`/`Racs`/`Analistas`, `_4SharkService.cs:493-559`): hoje opera só sobre `newcomersOrReactivations`. Estender pra cobrir `this.jerarquias` inteira ou adicionar helper `ClassifyRole(asesorCodigo)` reutilizando as HashSets já populadas.
3. **Renomear métodos enganosos:**
   - `UpdateMando` → `UpdateMandoParent`
   - `UpdateSuper` (que hoje serve racs) → `UpdateSubordinateParent` (ou similar)
   - Adicionar `UpdateSuperParent` (real, chama `FindParentSuper`) — hoje não existe
4. **Wrapper `WriteHierarchyChange(action, userId, newParentId, newType?)` em transação:** abre `dataContext.Database.BeginTransaction()`, executa o SP correspondente (`update_user_parent` / `create_promotion` / `create_demotion`) + executa `UPDATE fsk_users SET parent_id = @parent_id, [type = @role,] updated_at = GETUTCDATE() WHERE id = @user_id`, commit no fim. Rollback automático via `Dispose` se algo throw. Substitui as chamadas diretas de `ExecuteSqlInterpolated` espalhadas em `UpdateMando` / `UpdateSuper`. **Padrão novo** — `grep BeginTransaction|TransactionScope` em todo o projeto retorna zero hoje.
5. **Implementar detecção de transição:** novo método `DetectRoleTransition(j, fskuser, latestHierarchy)` que retorna `(type_atual, type_anterior, ação)`. Chamado em `LoadUpdates` antes de decidir entre `update_user_parent` e `create_promotion`/`create_demotion`.
6. **Validação pre-write:** antes de cada chamada SP relacionada a hierarquia, validar `rank(new_parent.type) < rank(user.type)`. Logar e pular se inválido.
7. **Tests:** rodar end-to-end contra `ME_4Shark_DB` greenfield + executar uma segunda rodada simulando promoções/demoções (mudar Cargo no Simplex test, validar emissão de `fsk_hierarchy` correta).

### Open issues

- **23 áreas faltam em `vw_empresa_area_codigo_jeraquia` (Atento).** Lista entregue acima. Sem isso, 21 líderes seguem no admin via PR #5. Mapear no source — não exige mudança no nosso código.
- **39 Supers DIVERGEM entre Fonte 1 e Fonte 2.** Confirmar com Atento qual é canônica. Algoritmo determinístico atual aplica Fonte 2 (consistente com `LoadNuevos`). Se Atento disser que Fonte 1 é a verdade, é outra mudança.
- **Rac ↔ Analista transitions** — confirmar com Atento se importa detectar (impossível hoje, `fsk_users.type` não distingue).

### Roadmap

cleanup (PR #11) → subsidiary registration & user binding (PR #12) → **alteração de hierarquia (THIS PHASE)**

Single PR contra `feature/4shark-improvements`.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| 1 | Hitting PRODUCTION by accident. **Largely de-risked**: Pedro has no prod credentials, so a `dotnet run` against the committed `appsettings.json` would auth-fail rather than damage data. Residual risk: passwords for prod **are** literally present in the committed file, so any process with network reach to prod hosts could in theory attempt those passwords. | Phase 4 still required — replace staging targets and **delete the prod entries from the local appsettings.json** (defense-in-depth). Phase 5 confirms reachability targets are staging only. |
| 2 | Stale local SQLite causes the daily load to compute everyone-as-departed. | Phase 6 resets SQLite; Phase 7 runs init first to populate. |
| 3 | Initial load against non-empty destination — duplicate-key crashes. | Phase 7 truncates `fsk_*` tables before running. |
| 4 | .NET 6 is past EOL; corporate antivirus / policy may flag the installer. | Full local admin → can override. Phase 2 fallback: bump target framework to `net8.0`. |
| 5 | `RecoverySubsidiarie()` hardcoded to `id=1`. If the destination DB seeds subsidiaries with different IDs (or none), behavior is wrong. | Inspect `fsk_subsidiaries` immediately after Phase 7. |
| 6 | `RealizarCambio()` is delete-then-create, not idempotent. A mid-update crash strips the field value. | Watch for null-field anomalies in `fsk_user_fields` after Phase 8/9. |
| 7 | Modified `appsettings.json` (with credentials) accidentally committed locally on Windows, then carried back to Mac and pushed from there. | Phase 4 uses `git update-index --skip-worktree` (covered for Windows). The PAT itself is read-only, so the Windows machine cannot push — but the source of truth for commits is the Mac, so the same discipline applies there: never `git add appsettings.json`. |
| 8 | `log\log.txt` may capture connection strings or sensitive data at verbose level. | The log file is local; do not share without redacting. |

---

## Open questions

1. **Knowledge transfer transcripts are partial.** Whisper hallucinated infinite loops on both files: only ~56 lines of the 70-min meeting (2026-04-08) and ~318 lines of the 24-min meeting (2026-04-09) are usable. Either re-process the audio with chunking (≤10-min segments) or VAD pre-processing, or schedule a new walkthrough with Atento. Tracked separately from this plan.
2. **DBA-level access on the destination test DB?** Phase 7 needs `DELETE` on `fsk_*`. If the credentials Pedro has are app-user only (read/write on data, no DDL/TRUNCATE rights and no permission to bypass FK), the cleanup step needs a separate path.

---

## Document chain

`ANALYSIS.md` (current state of the app) → `PLAN.md` (this — how to run it on a 4Shark Windows machine). After execution, findings feed back into `ANALYSIS.md` (corrections) or open new spikes / plans.

---

## Execution Status (2026-05-11)

Phases 1–8 effectively executed (Pedro/Paulo on the Windows machine + me on the Mac driving the SQL/PR work in parallel). The plan as written assumed a clean test-and-report cycle; the reality turned into a series of fixes shipped as PRs as bugs surfaced. Findings and full chain of work are in **ANALYSIS.md → "Execution & Findings (2026-05-11)"**.

### Branch strategy adopted for SimplexPE

- Working fork: `4shark/SimplexPE.Global4Shark` (`origin`)
- Integration branch (long-lived, lives on `origin`): **`feature/4shark-improvements`** — branched off `develop` (which mirrors `atento/develop` content). All intermediate fixes go here.
- Per-fix branches go into `feature/4shark-improvements` via PR
- At the end of the cycle, a **single PR** from `feature/4shark-improvements` against `atento/develop` consolidates everything for the customer

### PRs shipped or in flight

| PR | Repo | Title | Status | Notes |
|---|---|---|---|---|
| #2191 | `4shark/integrator` | fix: create_user_identifier/remove_user_identifier returning wrong table | merged | Both MSSQL variants + UNRELEASED migrations |
| #2192 | `4shark/integrator` | docs: normalized schema release lifecycle (UNRELEASED convention) | merged | README §2.1/§2.2 + integrator CLAUDE.md pointer |
| #2193 | `4shark/integrator` | feat: add indexes for foreign keys without coverage | merged | 11 FK indexes across all 3 SGBDs (setup + new UNRELEASED migrations including new PGSQL one). Already applied to `ME_4Shark_DB` via `sqlcmd` |
| #1 | `4shark/SimplexPE.Global4Shark` | fix: avoid duplicate enable_user and default city when distrito is empty | merged into `feature/4shark-improvements` | |
| #2 | `4shark/SimplexPE.Global4Shark` | fix: abort when ExtractAdmins finds no admin in the source | merged into `feature/4shark-improvements` | Later superseded conceptually by PR #3, but still serves as defense-in-depth |
| #3 | `4shark/SimplexPE.Global4Shark` | refactor: load admins from appsettings via a single EnsureAdmins method | merged into `feature/4shark-improvements` | Commit `78ce6c9`. Replaces 4 legacy methods (`ExtractAdmins`, `UploadAdminPrincipal`, `RecoverAdmin`, `HandleAdminChange`) with one `EnsureAdmins`. Code-reviewer pass done by independent agent + Copilot — concerns addressed |
| #4 | `4shark/SimplexPE.Global4Shark` | fix: sync sp_reporte_jeraquia_4shark with production version | merged into `feature/4shark-improvements` | Commit `7dcce33`. Resolved schema drift between the committed `sql/sp_reporte_jeraquia_4shark.sql` and what actually runs in the customer source — the production version returns `''` when `asesor_distrito IS NULL`, the committed file had `Local_Descripcion`. No behavior change for the integrator (PR #1's fallback covers both cases) |
| #5 | `4shark/SimplexPE.Global4Shark` | fix: fall back to admin in FindParentSuper when supervisor area is not in the hierarchy view | merged into `feature/4shark-improvements` | Commit `e2b2569`. Adds defensive fallback to `this.admin.Id4Shark` (mirrors what `ResolveParentSuperId` already does) when `GetMandoCodigoFromArea` returns null. Caught 13 supervisors with `parent_id=NULL` after the 2026-05-11 staging run |
| #8 | `4shark/SimplexPE.Global4Shark` | (intermediate work consolidated into PR #11) | superseded | |
| #9 | `4shark/SimplexPE.Global4Shark` | feat: order UploadMandos top-down to avoid duplicate fsk_user_fields | merged into `feature/4shark-improvements` | Commit `4c3f815`. Prevents recursive Add(parent) + delete-then-create cycles by iterating mandos in top-down `NivelOrder` (President → Coordinator). |
| #10 | `4shark/SimplexPE.Global4Shark` | fix: exclude mandos from supers and drop now-unreachable parent fallback | merged into `feature/4shark-improvements` | Commit `f03e730`. Mutual exclusion in ExtractSupers — anyone already classified as mando is filtered out. |
| #11 | `4shark/SimplexPE.Global4Shark` | refactor: drop SQLite snapshot, unify Load, and clean up dead code | merged into `feature/4shark-improvements` | Squashed commit `4f198b2`, merge commit `61f97de`. See Phase 11 status note above. |

### State of `feature/4shark-improvements` after PRs #1 → #5 merged

Accumulated fixes ready to send upstream as one PR to `atento/develop`:
- `city` fallback to `"Ciudad de México"` (PR #1)
- `enable_user` only fires on real reactivation (PR #1)
- Hard abort if admin config missing/invalid (PR #2)
- Full admin extraction moved to `appsettings.Admins`/`RootAdmin` with idempotent `EnsureAdmins` (PR #3) — removes 4 legacy methods (`ExtractAdmins`, `UploadAdminPrincipal`, `RecoverAdmin`, `HandleAdminChange`) and ~140 lines of code
- Local `sql/sp_reporte_jeraquia_4shark.sql` synced with the version actually running on the customer source (PR #4)
- `FindParentSuper` falls back to root admin instead of returning NULL when the supervisor's area is not registered in `vw_empresa_area_codigo_jeraquia` (PR #5)

### Operational config defined this session

- **`RootAdmin` = `71447`** — `BRAVO RODRIGUEZ LUIS HUMBERTO` (RFC `BARL8607134M7`, email `luis.bravo@atento.com`). Confirmed by decoding the RFC: `B` (first letter of paternal `BRAVO`) + `A` (first internal vowel of `BRAVO`) + `R` (first letter of maternal `RODRIGUEZ`) + `L` (first letter of first name `LUIS`). RE confirmed via `vDatosTotal` query `WHERE empleado LIKE '%BRAVO%' AND empleado LIKE '%LUIS%'`.
- **`Admins` = `[]`** for now — only `RootAdmin` is set; extra admins can be added later by Atento.

### Test run results (2026-05-11, after PRs #1/#2/#3 only — PRs #4/#5 not yet in this run)

| Metric | Value |
|---|---|
| Total `fsk_users` created | **9827** |
| `fsk_user_activity` rows | **0** — `enable_user` fix working (was 1332 in previous broken run) |
| `fsk_user_identifiers` with `primary=true` | **9827** (one per user) — DEBUG branch fix from PR #2191 working |
| Users with `city = "Ciudad de México"` (fallback) | **9826** |
| Users with `city` from real source | **1** (`Alvaro Obregon` — the only `vDatosTotal.distrito` populated row in MX) |
| Users with `state = "MX-CMX"` | **9827** (all, hardcoded) |
| Users skipped during run | **1** (RE `305854`, no `CarnetEmpleado` in source) |
| Users with `parent_id NULL` (anomaly) | **13 supervisors** — root cause: 5 Area_Codigo missing from `vw_empresa_area_codigo_jeraquia`. PR #5 (later run) makes them fall back to the admin instead of NULL |
| Users without `CECO` field | **292** (~3%) — source-side data gap (see ANALYSIS.md) |
| `fsk_versions` rows | 1 (`3.0-p1` preserved) |

### Test run results (2026-05-13, after PR #11 + PR #12 merged into `feature/4shark-improvements`)

End-to-end test run on the Windows machine against a freshly-cleaned `ME_4Shark_DB` (script `/tmp/run_clean_tables.sh` → all `fsk_*` tables zeroed; identities reseed). SQL Server `integrator-atento-sqlserver-simplex` (`i-08b28ace85761d7e4`, sa-east-1) brought up from `stopped`. `dotnet run` executed the unified `Load()` entrypoint with no CLI flags.

**Result: 100% success for everything in scope for the two delivered PRs.**

| Objetivo | Status |
|---|---|
| PR #11 — Eliminar cache SQLite | ✅ ETL roda sem o arquivo, sem SQLite provider |
| PR #11 — `LoadInitial` + `LoadDayli` unificadas | ✅ greenfield comportou como primeira carga sem flag |
| PR #11 — Multi-company isolation hardening | ✅ Extract* resetam, LoadJearquia limpa estado, cesados scoped |
| PR #11 — SAP_PEP → DESC_PEP | ✅ 0 rows SAP_PEP, 7143 DESC_PEP |
| PR #11 — GRUPO_OCUPACIONAL removido | ✅ 0 rows |
| PR #11 — Dead code cleanup (19 files) | ✅ build limpa |
| PR #12 — ReifySubsidiaries (subsidiary registration) | ✅ 1 row em `fsk_subsidiaries` criada: ATENTO MÉXICO, RUC `20414989277`, register_type `MX_RFC_PERSON`, external_id `1` |
| PR #12 — User binding por `subsidiary_id` | ✅ 9812 / 9812 usuários com `subsidiary_id` setado (zero NULL), todos apontando para a row criada |
| PR #12 — Cesados scoped por SQL (sem WalkToRoot) | ✅ no-op em greenfield (esperado) |
| PR #12 — JOIN no SQL no lugar de `Contains` (achado do Copilot) | ✅ activities query funciona |
| Integridade hierárquica | ✅ só RootAdmin (LUIS HUMBERTO BRAVO RODRIGUEZ, RE `47`) com `parent_id NULL`; 0 orphan parents |

**Counts finais:**
- `fsk_subsidiaries`: 1
- `fsk_users`: 9812 (todos com `subsidiary_id` populado)
- `fsk_user_fields`: 72314 (9 keys × ~80% fill rate médio)
- `fsk_user_activity`: 0 (esperado — `create_user` não gera activity; `enable_user` só dispara em reativação)
- `fsk_user_identifiers` / `fsk_groupifications` / `fsk_hierarchy` / `fsk_groups`: 0 (esperado — ETL não toca)

**Oddity cosmética:** `fsk_subsidiaries.id = 0` (em vez de 1). Side effect do `DBCC CHECKIDENT('fsk_subsidiaries', RESEED, 0)` no script de limpeza: numa tabela 100% vazia, o RESEED 0 faz o primeiro INSERT cair em 0. FK funciona normal — todos os 9812 usuários referenciam `subsidiary_id=0` consistentemente. Ajustar script de limpeza pra próxima rodada se quiser id=1.

### Structural validation queries run

Bundled into `/tmp/integrity_validation_me_4shark_db_*.sql` (regeneratable from the runbook in ANALYSIS.md). 22 checks total covering hierarchy correctness, duplicates (external_id, RFC, email), orphan identifiers/fields, mandatory fields, state/city values, RFC format. **All passed except the 2 known issues above** (13 sem parent + 292 sem CECO).

### SQL Server permissions delegated

User `4Shark` on `DB_PERSONAL01` already has (granted by the customer's existing DB user, who is not sysadmin but has GRANT rights on owned objects):
- `CONNECT` (DATABASE)
- `EXECUTE` + `VIEW DEFINITION` on `sp_reporte_jeraquia_4shark`
- Role `db_datareader`

**Missing** (still needs to be granted before the cesados SP can be uploaded):
- `CREATE PROCEDURE` (database-level)
- `ALTER ON SCHEMA::dbo`

Command to apply when ready:
```sql
USE DB_PERSONAL01;
GRANT CREATE PROCEDURE TO [4Shark];
GRANT ALTER ON SCHEMA::dbo TO [4Shark];
```

## Phase 13 — Positional Mando mapping does not distinguish nested sub-areas (open issue, 2026-05-15)

### Problem

The positional classification (`ClassifyRole` → `Mando` at `nivelXX`) maps an asesor_codigo to a 4Shark type based on the first `nivelXX_responsable_codigo` column where it appears in any row of the Simplex source. The logic is flat: if asesor X appears at `nivel04_responsable_codigo` anywhere, X is classified as GeneralManager.

Found during the integration run on 2026-05-15 (atento-cl-staging, source = ME_4Shark_DB at 9812-user state). Out of 82126 API requests, 534 failed (0.65%). Of those, 58 failures were `seat.parent_id: no puede estar en blanco` — caused by ONE chain:

- `LOPEZ AVILES CECILIA` (asesor 43405, carnet 10703) — true head of `Area_Codigo` 730, appears as nivel04_responsable_codigo in 190 rows
- `ACOSTA MONROY ANA KAREN` (asesor 64631, carnet 104021) — sub-manager that reports DIRECTLY to LOPEZ (`responsable_codigo = 43405`), but appears as nivel04_responsable_codigo in 58 rows (for her subordinates in `Area_Codigo` 539, a sub-area of 730)

Both were classified as `GeneralManager` by the positional mapping, producing an invalid chain: GeneralManager → GeneralManager → Supervisor → SalesRepresentative. When the integrator tried to register ACOSTA (GM) under LOPEZ (GM), the API rejected the chain; ACOSTA's `parent_id` got nulled by the integrator's defensive mechanism; ACOSTA failed; her downstream Supervisor (asesor 46043, carnet 4625, user_id 331 in fsk_users) failed in cascade; the 56 SalesRepresentatives that hung off that Supervisor all failed with `seat.parent_id: no puede estar en blanco`.

### Root cause

Simplex models the org chart per `Area_Codigo` via `vw_empresa_area_codigo_jeraquia`. Each area has its OWN nivel chain. Two areas (a parent area 730 and its sub-area 539) can both have `nivel04 = head of that area`. The positional mapping reads `nivelXX_responsable_codigo` across ALL rows of the Simplex output without knowing that some of those rows belong to nested sub-areas.

LOPEZ is head of 730 → her own row has 43405 at nivel04_resp.
ACOSTA is head of 539 (sub-area) → 58 employee rows from sub-area 539 have 64631 at nivel04_resp.
The positional logic sees both at nivel04 and gives them the same role.

### Required fix (sketch)

The classification must consider **chain depth**, not absolute nivel position. Possible approaches:

1. **Use own row's nivel position only** — for asesor X, look ONLY at the row where `Empleado_Codigo = X` (their own row). Check the deepest `nivelXX_responsable_codigo` that equals X in that single row. If they appear as nivel04 in their OWN row, they are GM. If they appear as nivelXX only in OTHER rows (subordinates' rows), they are at nivel(X+1).
2. **Walk the responsable_codigo chain** — for asesor X, if `responsable_codigo` (direct boss) is another Mando classified as nivelN, then X is nivel(N+1). Recursive resolution.
3. **Compare own-row position vs subordinates'-row position** — same intuition as 1, but framed as a delta.

Approach 1 is the cleanest. Implementation: in `ClassifyRole` or wherever the Mando level is determined, scan the empleado's OWN row's nivel00_resp..nivel09_resp columns and find the deepest position where the value equals their own asesor_codigo. That's the empleado's own level. Currently the logic likely scans all rows globally for the asesor_codigo, which is what causes the conflation.

### Investigation needed before fixing

Run against Simplex (read-only, single PK lookup, no impact):

```sql
-- For each Mando candidate, count how many distinct rows (by Area_Codigo) have its asesor at nivelXX_resp.
-- If many Mandos appear in >1 area's chain, the problem is widespread, not isolated to LOPEZ/ACOSTA.
SELECT asesor, nivel, COUNT(DISTINCT area_codigo) AS areas
FROM (
  SELECT nivel04_responsable_codigo AS asesor, 'nivel04' AS nivel, area_codigo FROM vw_empresa_area_codigo_jeraquia WHERE nivel04_responsable_codigo IS NOT NULL
  UNION ALL
  SELECT nivel05_responsable_codigo, 'nivel05', area_codigo FROM vw_empresa_area_codigo_jeraquia WHERE nivel05_responsable_codigo IS NOT NULL
  UNION ALL
  SELECT nivel06_responsable_codigo, 'nivel06', area_codigo FROM vw_empresa_area_codigo_jeraquia WHERE nivel06_responsable_codigo IS NOT NULL
  -- continue for niveis 00..09 as needed
) AS m
GROUP BY asesor, nivel
HAVING COUNT(DISTINCT area_codigo) > 1
ORDER BY areas DESC;
```

This gives the magnitude. If it's a handful of pairs like LOPEZ/ACOSTA, the fix can be narrow. If it's hundreds, the classification logic needs a serious rewrite.

### Acceptance criteria

- After the fix, a re-run of the integration on the same source state should NOT produce `seat.parent_id: no puede estar en blanco` errors for cascades originating in this pattern.
- The 56 SRs + 1 Supervisor (4625) + 1 sub-manager (104021) that failed in the 2026-05-15 run all register successfully.
- No regression on the 9754 users that already integrate correctly (the classification of single-area heads like LOPEZ must still produce GeneralManager).

### References

- Report file: `4shark-report-20260515-6a07318b3a7d8261e42c357f.xlsx` (Users sheet, 58 rows of `seat.parent_id: no puede estar en blanco`)
- Simplex source rows (live query 2026-05-15): LOPEZ (Empleado_Codigo 43405) and ACOSTA (Empleado_Codigo 64631) — both `Area_Codigo = 730`, identical nivel chain, ACOSTA's `Responsable_Codigo = 43405`
- 58 distinct rows in Simplex have `nivel04_responsable_codigo = 64631` (ACOSTA at nivel04 of sub-area 539); 190 distinct rows have `nivel04_responsable_codigo = 43405` (LOPEZ at nivel04 of area 730)
- `vDatosTotal` view definition confirms cesados detection filter is `Empleados.Estado_Codigo = 1` (not modalidad-based) — unrelated to this issue but documented for context

## Phase 14 — Test cycles plan (2026-05-16)

### Goal

Run 3 additional incremental cycles after the current baseline (day 13) to validate the .NET ETL and the integrator behaving correctly across daily updates. Cycles: **today (2026-05-16)**, **tomorrow (2026-05-17)**, **Sunday (2026-05-18)**.

### Pipeline (incremental at both ends)

```
Atento source SQL (live)
    │
    ▼ .NET app (reads source rows with date > last .NET execution)
ME_4Shark_DB on 10.12.255.51 (normalized base)
    │
    ▼ Integrator Ruby (reads ME_4Shark_DB rows with date > last integrator execution)
App demo-001 (us-east-1) via HTTPS POST
```

The integrator's `last_finish_at` lives in **MongoDB** (per execution record), not in SQL. The .NET app keeps its own marker for source-side incremental.

### Serialization rule

The .NET app and the integrator **MUST NEVER run at the same time**. Reason: if .NET writes a record to `ME_4Shark_DB` while the integrator is mid-execution, the record's `updated_at` falls inside the integrator's `[start, finish]` window and may be missed by both the current run (already past the query point) and the next run (the next filter is `> last_finish_at`, which is greater than the missed record's `updated_at`).

Always serialize: wait for one to finish before starting the other.

### Cycle sequence (repeats for each day)

| Step | Action | Done when |
|---|---|---|
| 1 | Wait for previous integrator cycle to finish | Sidekiq queue empty, no consumers running, final execution report emitted |
| 2 | Take SQL backup of `ME_4Shark_DB` (rollback safety net) | `.bak` file written and verified |
| 3 | Run the .NET app from this repo (`dotnet run` or published binary) | .NET process exits cleanly, logs report end |
| 4 | If .NET completed cleanly → continue. If .NET broke `ME_4Shark_DB` → restore the `.bak` from step 2, fix the bug, go back to step 3 | n/a |
| 5 | Trigger the integrator's next execution (the worker is already scaled; the producer runs on schedule or via manual trigger) | Sidekiq queue empty, final execution report emitted |
| 6 | Validate: counts and spot-check across source SQL ↔ ME_4Shark_DB ↔ app demo-001; review error counts in the integrator's final report; review .NET log for ETL errors | All counts reconcile or differences are explained |

### Backup strategy — rollback only when needed, never after integrator runs

The backup taken at step 2 of each cycle exists for **one purpose only**: rollback if the .NET execution in step 3 corrupts `ME_4Shark_DB`. In that case:

- Restore the `.bak` → SQL returns to the post-previous-integrator state
- MongoDB's `last_finish_at` on the integrator side is already at that same moment (it was set when the previous integrator cycle finished, before this cycle's .NET ran)
- The two stay aligned; no Mongo restore needed
- Re-run .NET after fixing whatever broke

**Once the integrator runs (step 5)**, the SQL `.bak` from step 2 is no longer a valid rollback target — restoring it without also rolling back the integrator's MongoDB state would create a mismatch where the integrator thinks it has already processed records that the restored SQL no longer claims to have shipped. The next cycle's step-2 backup replaces it.

### Backup naming convention

```
ME_4Shark_DB_<YYYY-MM-DD>.bak
```

The date in the file name is the **BRT date of the work session** that produced the state being backed up — not the UTC date of the `BACKUP DATABASE` command. The work sessions typically run late at night BRT and finish in the very early UTC morning of the next day; using UTC for the filename produces dates that don't match the engineer's mental model of which day's work the backup represents. Examples:

- `ME_4Shark_DB_2026-05-13.bak` — baseline snapshot of post-day-13 .NET extraction (existed before this session)
- `ME_4Shark_DB_2026-05-15.bak` — post-.NET state from the Friday May 15 BRT work session (`BACKUP DATABASE` actually ran 2026-05-16 03:37 UTC, but the work was Friday night BRT)
- `ME_4Shark_DB_2026-05-16.bak` — post-.NET state from the Saturday May 16 BRT work session (`BACKUP DATABASE` ran 2026-05-17 03:10 UTC)
- `ME_4Shark_DB_2026-05-17.bak` — post-.NET state from the Sunday May 17 BRT work session

The convention does not encode lifecycle position (pre/post) — the backup is simply a snapshot of `ME_4Shark_DB` at the moment of that day's work session, after that day's .NET ran and before that day's integrator did. Storage: on the SQL Server EC2 itself at `/var/opt/mssql/data/`, retained at least until the next cycle's backup completes.

### What each cycle should reveal

- Incremental volume picked up by .NET (delta of new/updated rows in the source since last .NET execution)
- Incremental volume picked up by the integrator (delta of new/updated rows in `ME_4Shark_DB` since last integrator execution)
- Errors that only surface on **update** (vs. creation) — the positional Mando bug documented in Phase 13 is the prime candidate; other update-only behaviors may emerge

### Operational hazards

**SQL Server EC2 auto-shutdown at midnight (BRT).** The instance hosting `ME_4Shark_DB` (`i-08b28ace85761d7e4`, IP `10.12.255.51`, `sa-east-1`) is stopped **once a day at midnight Brasília time** by an automated principal — CloudTrail shows the `StopInstances` event at `00:00:14 -03` from a hashed AssumeRole identity (`d8b4981274e337199a6b5cd6186956e5`), which is a Lambda-driven cost-saving job somewhere in the account. It bit this session twice — once mid-integrator (caused TinyTds connect failures and spurious queue growth from retries; misdiagnosed several times before discovering the EC2 was stopped) and once between cycles. Before each cycle that runs across midnight BRT, verify the instance is `running` and start it if needed. Restart procedure: `/aws-elevate` → `aws ec2 start-instances --region sa-east-1 --profile 4shark-mfa --instance-ids i-08b28ace85761d7e4`.

**`demo-001-web` saturation under integrator load.** With 1 web task (us-east-1, 1 vCPU 1GB) and the integrator pushing from 1 worker (30 sidekiq threads), `demo-001-web` saturates at **96% CPU avg** sustained — requests still finish in ~150ms (no rack-timeout in the 22s budget) but the box is at the ceiling. With 2 web tasks the avg stayed at 96% as well — both tasks saturated. With 3 web tasks the avg dropped to **~50-60%** with peak ~73% — comfortable. **Rule of thumb for test cycles**: 1 integrator worker → minimum 2 web tasks; 2 integrator workers → minimum 3 web tasks. Memory is never the bottleneck (~430MB / 1GB even at saturation). The MongoDB cluster (`4client-atento-mongo003/004/005`, sa-east-1) and ElastiCache (`ec-atento`, cache.t3.medium) stay below 15% CPU at 2 workers — they are not in the critical path; the web layer is.

### Cycle execution log

#### Cycle 1 — baseline (day 13 source → completed 2026-05-16 02:37 UTC)

**Initial state of `ME_4Shark_DB` at integrator-run start (post-.NET-day-13):**

| Table | Rows |
|---|---|
| `fsk_users` | 9.812 |
| `fsk_user_fields` | 72.314 |
| `fsk_subsidiaries` | 1 |
| `fsk_hierarchy` | 0 |
| `fsk_user_identifiers` | 0 |
| `fsk_user_activity` | 0 |
| `fsk_groups` | 0 |
| `fsk_groupifications` | 0 |

**Integrator execution (`atento-cl-staging`):**

- Integrator version: **8.4.8** (with `SUBSIDIARIES_MODULE=false` gating shipped earlier in this session)
- Normalized base version: **3.0-p1**
- Window: 2026-05-15 23:40:06 UTC (record search) → 2026-05-16 02:37:20 UTC (envío start) → finished ~02:37 UTC
- Total wall time: **3h 33min 51s**
- Búsqueda: 8s · Procesamiento: 2h 57min 6s · Envío: 36min 37s
- Total HTTP requests to `demo-001`: **82.126** — **81.592 successful (99.35%)** / 534 failed (0.65%)
- Worker scaled to 2 tasks (after starting at 1 and observing low throughput) — decision path documented in chat

#### Cycle 2 — first incremental (started 2026-05-16 03:30 UTC .NET, ~03:38 UTC integrator)

**State of `ME_4Shark_DB` after .NET (deltas vs. cycle 1 baseline):**

| Table | Before | After | Row count Δ | Records actually touched |
|---|---|---|---|---|
| `fsk_users` | 9.812 | **9.824** | +12 inserts | **137** (12 new + 125 with `updated_at` = today) |
| `fsk_user_fields` | 72.314 | **72.610** | +296 inserts | **296** (no UPDATE — pattern is `delete` row + `create` row, both as new rows) |
| `fsk_hierarchy` | 0 | **125** | +125 inserts | **125** (123 `update_parent` + 2 `demotion`) |
| `fsk_user_activity` | 0 | **43** | +43 inserts | **43** (`disable` events) |

**Why the two columns differ for `fsk_users`:** `fsk_users` is overwritten in place (UPDATE), so `row count delta = inserts only`. The 125 users whose hierarchy changed had their row updated but the row count didn't grow — only the 12 net-new ones did. The other tables append history (insert-only — `delete`/`create` types in `fsk_user_fields`), so `row count delta = records touched`. Always check both numbers when reporting cycle deltas; counting only rows hides updates on `fsk_users`.

**Confirmation from the integrator's `bin/rails int...` NUMBERS report** (taken at integrator-cycle-2 start, before push):

```
Hierarchy: 125
Users: 137
User Activities: 43
User Fields: 296
```

These are the same numbers the integrator decided to push to `demo-001` — bate exatamente.

**Validation findings (no anomalies):**

- 0 users without `subsidiary_id` / `email`
- 0 orphan `parent_id` references in `fsk_users`
- 0 duplicate `external_id`
- 0 orphan `user_id` / `parent_id` in `fsk_hierarchy`, `fsk_user_fields`, `fsk_user_activity`
- Distribution by `type`: SalesRepresentative 9.345 + Supervisor 304 + Superintendent 61 + GeneralManager 56 + Director 42 + VicePresident 8 + Manager 6 + President 1 + Admin 1 = 9.824 ✓
- 137 users updated today (12 new + 125 with hierarchy change) — matches the 125 `fsk_hierarchy` entries 1:1
- `fsk_user_fields` stores history via `type='create'` / `type='delete'` rather than UPDATE — the apparent "duplicate" CARGO/CLIENTE/PEP entries (96 extra rows on CARGO etc.) were verified as audit-trail pairs (`delete` of old value + `create` of new value, all with `distinct_values > 1`) — **not a duplication bug**

**Backups taken on `i-08b28ace85761d7e4:/var/opt/mssql/data/`:**

- `ME_4Shark_DB_2026-05-13.bak` (3.9M, pre-existing) — baseline post-day-13-.NET
- `ME_4Shark_DB_2026-05-15.bak` (4.1M, taken 2026-05-16 03:37 UTC = 00:37 BRT Sat) — post-cycle-2-.NET state (cycle done in the Friday May 15 BRT session, overflowed into Saturday early morning UTC); the file is named after the BRT work date

**Cycle 2 integrator execution (completed 2026-05-16 ~03:46 UTC):**

- Integrator version: **8.4.8** · Normalized base: **3.0-p1**
- `Búsqueda desde`: 2026-05-16 03:13:57 UTC (= end of cycle 1's envío phase, not end of cycle 1 overall)
- Window: 03:45:09 UTC (search start) → 03:45:33 UTC (envío start) → ~03:46 UTC (envío end)
- Total wall time: **35 s** (1s búsqueda + 23s procesamiento + 11s envío)
- Total HTTP requests: **601** — matches the NUMBERS report (137 + 125 + 43 + 296 = 601)
- **543 successful (90.35%)** / **58 failed (9.65%)** ⚠️
- Worker scaled to 2, integrator web at 1, `demo-001-web` at 3 — no infra saturation observed

**⚠️ Regression: success rate dropped from 99.35% (cycle 1) to 90.35% (cycle 2).** 58 failures out of 601 — much worse than cycle 1's 0.65%. The cycle 2 deltas were heavy on hierarchy updates (125 `update_parent` + 2 `demotion`) and disable activities (43) — both are **update-only** scenarios that the cycle 1 baseline (mostly creates) didn't exercise. Prime suspects:

1. The positional Mando mapping bug from Phase 13 — same root cause should cause more failures on hierarchy updates because the update path re-resolves the parent with the same flawed lookup
2. Disable events failing on users that the app has in a state the disable endpoint doesn't expect
3. Hierarchy demotion (2 events) — rare path, likely never tested

**Next step:** pull the integrator's failure report (the `4shark-report-<execution_id>.xlsx` attached to the email — execution `6a07e845ea0dfb358a36a778`) and break down the 58 failures by error type to confirm which suspect dominates. Until that's done, do not run cycle 3 — repeating without understanding the failure mode adds noise.

#### Cycle 3 — second incremental (2026-05-17 ~03:12 UTC)

**Deltas produced by today's .NET run (`LoadUpdates resumo` from console):** promotion=2 · demotion=3 · update_parent=191 · no_change=9.531 · error=0 · skipped=1

**State of `ME_4Shark_DB` after .NET (deltas vs. cycle 2 end state):**

| Table | Before | After | Row count Δ | Records actually touched |
|---|---|---|---|---|
| `fsk_users` | 9.824 | **9.826** | +2 inserts | **239** (2 new + 237 with `updated_at` = today) |
| `fsk_user_fields` | 72.610 | **73.043** | +433 inserts | **433** |
| `fsk_hierarchy` | 125 | **321** | +196 inserts | **196** (191 update_parent + 3 demotion + 2 promotion) |
| `fsk_user_activity` | 43 | **96** | +53 inserts | **53** (disable) |

**Integrator NUMBERS report (`bin/rails integration:start`, executed manually):** Users 239 · Hierarchy 196 · User Activities 53 · User Fields 433 — matches the DB deltas exactly.

**Integrator execution (`atento-cl-staging`):**

- Execution id: `6a0931bbcd233b834284b84d` · Integrator 8.4.8 · Base 3.0-p1
- `Búsqueda desde`: 2026-05-16 03:45:44 UTC (= end of cycle 2's envío)
- Window: 2026-05-17 03:10:51 UTC (search) → 03:12:00 UTC (envío start) → ~03:13 UTC (end)
- Total wall time: **1 min 46 s** (2s búsqueda + 1m 7s procesamiento + 37s envío)
- Total HTTP requests: **921** (matches NUMBERS sum 239+196+53+433)
- **735 successful (79.8%)** / **186 failed (20.2%)** ⚠️⚠️
- Backup taken pre-cycle: `ME_4Shark_DB_2026-05-16.bak` (4.1M, BACKUP DATABASE actually ran 2026-05-17 03:10 UTC = 00:10 BRT Sun; the file is named after the BRT work date — Saturday May 16's session)
- Worker 1, integrator web 1, demo-001-web 3 — no infra saturation (volume too small)

**⚠️⚠️ Trend across the three cycles is clearly downward:**

| Cycle | Type | Requests | Success | Fail | % success | % fail |
|---|---|---|---|---|---|---|
| 1 | full baseline | 82.126 | 81.592 | 534 | **99.35%** | 0.65% |
| 2 | incremental | 601 | 543 | 58 | **90.35%** | 9.65% |
| 3 | incremental | 921 | 735 | 186 | **79.80%** | 20.20% |

Each cycle is losing ~10 percentage points. Two important observations:

1. **Absolute failures in cycle 3 (186) > number of hierarchy changes (196)** — failures are not concentrated only in `Hierarchy` requests; something is breaking across Users, User Fields, and/or User Activities too.
2. **Cycles only see deltas — fail rate compounds per change, not per total dataset.** Each new hierarchy change re-exercises the same buggy code path and likely creates a new bad parent reference that cascades into child failures on the next cycle.

#### Failure analysis (244 failures across cycle 2 + cycle 3)

Reports downloaded and analyzed:

- `~/Downloads/4shark-report-20260516-6a07e845ea0dfb358a36a778.xlsx` (cycle 2, 58 failures)
- `~/Downloads/4shark-report-20260517-6a0931bbcd233b834284b84d.xlsx` (cycle 3, 186 failures)

**Cross-cycle ID overlap: ZERO in every sheet.** No user, hierarchy entry, user_field, or user_activity that failed in cycle 2 failed again in cycle 3. This **refutes** the "cascading bad-state of the same user across cycles" hypothesis. Each cycle generates its own set of failures, driven by the deltas of that cycle.

**Breakdown by error type:**

| Failure mode | Cycle 2 | Cycle 3 | Total | Root cause |
|---|---|---|---|---|
| `UserFields.key: ya ha sido tomado` | 54 | 72 | **126** | **Integrator bug** — see "New bug" below |
| `Users.seat.parent_id: no puede estar en blanco` | 0 | 55 | **55** | Phase 13 (positional Mando mapping) |
| `Hierarchies.user_id: no se ha encontrado` | 0 | 55 | **55** | Cascade from Users failure above (one-to-one) |
| `Hierarchies.type: tiene conflicto con los subordinados` | 2 | 3 | 5 | Legitimate business rule (promo/demo of a user whose current subordinates are incompatible types) |
| `Hierarchies.parent_id: es igual al valor actual` | 1 | 0 | 1 | Integrator noise — should pre-filter same-value updates |
| `UserActivities.identificador: não cadastrado na plataforma` | 1 | 1 | 2 | Cascade from a previous failed user creation |
| **TOTAL** | **58** | **186** | **244** | |

**Two patterns dominate (236 of 244 failures = 96.7%):**

1. **UserField key collision — 126 failures.** When any user_field key changes on the source (CARGO, CECO, PEP, etc.), the .NET writes the audit-trail pair to `ME_4Shark_DB`: one row `type='delete'` for the old value + one row `type='create'` for the new value. The integrator picks both up and pushes them to `demo-001`'s API. The CREATE always fails with `key: ya ha sido tomado` because the app enforces uniqueness on `(user_id, key)` and the field already exists for that user. This will fail every time any user_field key changes anywhere, and the rate will scale with the volume of changes. This is a **new bug**, not previously tracked.

2. **Phase 13 positional Mando bug + dependent hierarchy — 110 failures (55 + 55).** 55 users newly created today fell into the positional Mando misclassification (same root cause as the LOPEZ/ACOSTA case in Phase 13). Their POST to `/api/v3/users` failed with `seat.parent_id: no puede estar en blanco`. For each of those 55 users, the integrator also tried to push a hierarchy entry — those 55 hierarchy POSTs failed with `user_id: no se ha encontrado` because the user creation never completed. **One root cause produces exactly two failures per affected user.**

The remaining 8 failures are: legitimate business validations (5), integrator noise (1), and cascades from a prior failed user (2).

#### New bug to track — UserField CREATE collision on key change

**Symptom:** every time a `fsk_user_fields` row of `type='create'` is sent for a `(user_id, key)` pair that the app already has, the request fails with `key: ya ha sido tomado` (HTTP 422). The integrator does not first DELETE the existing field on the app side (or the DELETE doesn't reach the app, or it's ordered after the CREATE).

**Where to investigate (not yet done):**
- `~/Projects/4Shark/integrator/app/workers/user_field/loader_consumer.rb` — what does it POST and what does it skip?
- Order of operations: does the consumer process `delete` and `create` records for the same `(user_id, key)` in a guaranteed order, or in parallel? If parallel, a CREATE can race ahead of the DELETE.
- App side: `~/Projects/4Shark/app/app/controllers/api/v3/users/fields_controller.rb` (or similar) — confirm the uniqueness validation and whether there's an upsert endpoint we should use instead.

**Scale risk:** this bug fires on every key change. Cycle 2 had 54 key changes → 54 fails. Cycle 3 had 72 → 72 fails. Real-world daily volume of CARGO/CECO/PEP changes will determine the recurring fail rate. It's deterministic — same change = same failure.

**Suggested next step before cycle 4:** add this as Phase 15 in this PLAN.md (separate from Phase 13), then fix in the integrator. Without fixing, every future cycle will keep losing ~10pp on success rate.

#### Cycle 4 — third incremental (2026-05-17 evening BRT — Sunday session, ~22:30 UTC)

This cycle ran as a second `.NET` session on the same UTC day as cycle 3 (cycle 3 ran at 03:06 UTC = 00:06 BRT Sunday, cycle 4 ran at ~22:09 BRT Sunday = 01:09 UTC Monday). The BRT date convention treats them as separate sessions: cycle 3 = "Saturday May 16 BRT" session, cycle 4 = "Sunday May 17 BRT" session.

**Deltas produced by today's `.NET` run (`LoadUpdates resumo`):** promotion=0 · demotion=0 · update_parent=3 · no_change=9.725 · error=0 · skipped=1

**State of `ME_4Shark_DB` after .NET (deltas since end of cycle 3 integrator):**

| Table | Δ | Detail |
|---|---|---|
| `fsk_users` | 3 updated, 0 new | 3 with `updated_at` > cycle-3 cutoff |
| `fsk_user_fields` | +16 | 8 `create` + 8 `delete` (= 8 key changes) |
| `fsk_hierarchy` | +3 | 3 `update_parent` |
| `fsk_user_activity` | +2 | 1 `disable` + 1 `enable` (first `enable` event observed in cycles 2-4) |

**Integrator NUMBERS report (`bin/rails integration:start`):** Users 3 · Hierarchy 3 · User Activities 2 · User Fields 16 — matches DB deltas exactly.

**Integrator execution:**

- Execution id: `6a0a419b1f32bdc150347404` · Integrator 8.4.8 · Base 3.0-p1
- `Búsqueda desde`: 2026-05-17 03:12:37 UTC (= end of cycle 3's envío)
- Window: 2026-05-17 22:30:51 UTC (search) → 22:30:57 UTC (envío start) → ~22:31:09 UTC (end)
- Total wall time: **12 s** (2s búsqueda + 4s procesamiento + 6s envío)
- Total HTTP requests: **24** (matches NUMBERS sum 3+3+2+16)
- **18 successful (75.0%)** / **6 failed (25.0%)** ⚠️
- Backup taken pre-cycle: `ME_4Shark_DB_2026-05-17.bak` (4.1M, BACKUP DATABASE ran 2026-05-17 22:13 UTC = 19:13 BRT Sun)
- Worker 1, integrator web 1, demo-001-web 3 — no infra saturation (volume tiny)

**Trend through 4 cycles:**

| Cycle | Type | Requests | Success | Fail | % success | % fail |
|---|---|---|---|---|---|---|
| 1 | full baseline | 82.126 | 81.592 | 534 | 99.35% | 0.65% |
| 2 | incremental | 601 | 543 | 58 | 90.35% | 9.65% |
| 3 | incremental | 921 | 735 | 186 | 79.80% | 20.20% |
| 4 | incremental | 24 | 18 | 6 | **75.00%** | 25.00% |

Percentage continues downward but cycle 4 has too few absolute failures (6) to read a trend on its own. The 6 failures need cross-reference against the cycle 2 + 3 breakdown — if they're also dominated by `UserFields.key: ya ha sido tomado` (predicted: ~6 of the 8 user_field creates collide), the dominant-bug hypothesis is reinforced. If a new failure pattern appears (e.g., the first `enable` event failing), it's a new finding worth tracking.

**Failure breakdown (from `4shark-report-20260517-6a0a419b1f32bdc150347404.xlsx`):**

| Sheet | Count | Error |
|---|---|---|
| UserFields | 3 | `key: ya ha sido tomado` (known dominant bug — confirmed) |
| Hierarchies | 3 | `date: debe ser después 17/05/2026` (new error message, but NOT a bug — see below) |

**On the Hierarchies `date debe ser después` error:** the 3 failures are exactly the 3 `update_parent` entries from this cycle (DB IDs 321, 322, 323). The app enforces that each hierarchy update for a user must have `date > date_of_previous_entry`. Cycle 3 (this morning, 03:06 UTC = 00:06 BRT Sun) created hierarchy entries with `date = 2026-05-17`; cycle 4 (tonight, 22:30 UTC = 19:30 BRT Sun, still 17/05 BRT) tried to add more entries for the same users with the same date and got rejected.

**This is by design, not a bug.** The app only accepts 1 hierarchy update per user per day. The 3 failures are an artifact of running `.NET` twice on the same BRT day during testing — won't happen in normal daily operations where `.NET` runs once a day on schedule. Cycle 4 confirmed the dominant bug (user_field key collision) and surfaced a benign app validation that's good to know about for future debugging.

**Final cycle 4 conclusion:** UserField key collision remains the only **real bug** worth fixing. The hierarchy date validation requires no fix — just discipline to keep one .NET run per day per BRT.

## Phase 15 — Integrator loader ordering hotfix 8.4.9 (2026-05-18) — ✅ DELIVERED

### What this fixed

The integrator was the source of two failure modes documented during cycles 2-4:

1. **UserField key collision (`key: ya ha sido tomado`) — 126 failures (54+72+~3 across cycles 2-4).** The `delete` row and the `create` row for the same `(user_id, key)` pair were being pushed in parallel by 30+ sidekiq threads; whenever the CREATE landed before the DELETE, the app rejected it on uniqueness.
2. **UserIdentifier race-condition pairs.** The single `UserIdentifier::LoaderConsumer` ran every operation (create / select_primary / delete) on the same threadpool without ordering — analogous race surface.

Both root causes are the same: a single consumer worker mixing operations of different semantics with no ordering guarantee.

### The fix

Split each loader into ordered, sequential phases:

- **UserField:** `DeleteLoaderProducer → DeleteLoaderConsumer` (all DELETEs flush) → `CreateLoaderProducer → CreateLoaderConsumer` (then all CREATEs)
- **UserIdentifier:** `CreateLoaderProducer → CreateLoaderConsumer` → `PrimaryLoaderProducer → PrimaryLoaderConsumer` → `DeleteLoaderProducer → DeleteLoaderConsumer`

Each phase's producer waits for the prior phase's computation counter to reach zero before producing its workload. Within a phase, parallelism inside the threadpool is safe because every job in that phase has the same semantics (all DELETEs, or all CREATEs).

Architecture chosen: **no filter at the producer + skip at the consumer.** The producer iterates ALL UserField/UserIdentifier records for the job; the consumer's first action is an early-skip guard (`return unless import.delete?` for the delete consumer, etc.). Reason: filtering at the producer would require a `$elemMatch` index on `imports.data.type` and `imports.data.primary` over a `resources` collection that already holds tens of millions of rows for some clients — not viable. The skip-at-consumer pattern keeps Mongo cold and only burns one cheap document load per skipped job.

### Repository deltas

Integrator (`~/Projects/4Shark/integrator/`):

- 10 new files under `app/workers/user_field/` and `app/workers/user_identifier/` — split producers/consumers
- 2 deleted: old monolithic `user_field/loader_consumer.rb` and `user_identifier/loader_consumer.rb`
- Chain redirects updated: `groupification/loader_consumer.rb` → `UserField::DeleteLoaderProducer`; `parent_update/loader_consumer.rb` → `UserIdentifier::CreateLoaderProducer`
- `config/normalized_schema.rb`: UserIdentifier → 3 stream entries (Create/Primary/Delete), UserField → 2 stream entries (Delete/Create). Caveat noted: all entries share the same source table without per-phase `condition` — every Stream fetches the same rows, leading to 3x (or 2x) Mongo write amplification. Acceptable for now; revisit if write volume becomes a problem (will require adding per-phase `condition` clauses based on a discriminator column the customer must populate).
- `config/version.rb`: bumped to 8.4.9
- 6 docs updated to reflect the 27-step execution flow: `docs/mssql/`, `docs/mssql-prefixed/`, `docs/pgsql-prefixed/` × pt-br / es
- CHANGELOG: `[8.4.9] - 2026-05-18` with "User field loader ordering" + "User identifier loader ordering"

### Release flow

1. PR #2200 (`hotfix/8.4.9` → master): opened, triaged via `/triage-pr` (8 threads classified, resolved via GraphQL), reviewed (Copilot + manual), merged
2. `git hf hotfix finish 8.4.9` — tag pushed, master forward, develop back-merged via PR #2203
3. Build workflow run on `master` (PR #2203 merge): completed successfully — `latest` ECR images for all 12 integrators rebuilt to point at 8.4.9
4. Deploy workflow dispatched on `master` for all 12 integrators (2026-05-18 16:23 UTC): almaviva, atento-br, atento-cl, atento-cl-staging, atento-co, atento-co-staging, atento-mx, atento-mx-staging, commcenter, commcenter-staging, maqnelson, redebrasil

### Validation post-deploy

To confirm the fix is real:

- Run a new cycle (cycle 5) against `atento-cl-staging` after the deploy completes
- Compare `UserFields.key: ya ha sido tomado` count vs. cycles 2-4 (expected: zero)
- If zero confirmed, the dominant bug is resolved; the remaining failure profile is **Phase 13 (positional Mando)** + the handful of legitimate business validations

## Phase 16 — Phase 13 positional Mando bug — UP NEXT (2026-05-18)

### Where this stands

After Phase 15, the failure breakdown across cycles 2-4 reduces to:

| Failure mode | Cycle 2 | Cycle 3 | Cycle 4 | Total | Status |
|---|---|---|---|---|---|
| `UserFields.key: ya ha sido tomado` | 54 | 72 | 3 | 129 | ✅ Phase 15 fix shipped |
| `Users.seat.parent_id: no puede estar en blanco` | 0 | 55 | 0 | **55** | 🎯 Phase 13 — open |
| `Hierarchies.user_id: no se ha encontrado` | 0 | 55 | 0 | **55** | Cascade from row above |
| `Hierarchies.type: tiene conflicto con los subordinados` | 2 | 3 | 0 | 5 | Legitimate validation |
| `Hierarchies.parent_id: es igual al valor actual` | 1 | 0 | 0 | 1 | Integrator noise (low priority) |
| `UserActivities.identificador: não cadastrado na plataforma` | 1 | 1 | 0 | 2 | Cascade from prior failure |
| `Hierarchies.date: debe ser después` | 0 | 0 | 3 | 3 | Test artifact — not a bug |

**Phase 13 is now the dominant bug.** It accounts for 55 user-creation failures + 55 cascading hierarchy failures = 110 of the ~118 remaining real failures.

### Why "data or architecture"

Phase 13 is on the **.NET side** (`~/Projects/Atento/SimplexPE.Global4Shark/`), not the integrator. The root cause sits in how `vw_empresa_area_codigo_jeraquia` is consumed and how a user's position in a nested sub-area is resolved to a Mando type. Two failure dimensions:

- **Data dimension:** sub-areas the customer hasn't registered in `vw_empresa_area_codigo_jeraquia` cause certain employees to fall through the positional mapping with no parent assignment. This part is partially documented in ANALYSIS.md § "Areas missing from vw_empresa_area_codigo_jeraquia" (5 codigos listed: 449, 688, 534, 616, 414). Resolution = customer registers them.
- **Architecture dimension:** the positional algorithm itself may not distinguish nested sub-areas correctly — same root area but different sub-area can still resolve to the same Mando, hiding nested structure. The "Investigation needed before fixing" subsection of Phase 13 (line 721+) lists what we don't yet know.

### Source-data investigation closed (2026-05-18)

Cycle 5 skipped — high confidence Phase 15 is working in prod. Investigation went directly to source data via 4 indexed queries against `DB_PERSONAL01` (Simplex Peru). Findings:

**1. `vw_empresa_area_codigo_jeraquia` only goes 6 levels deep** (nivel00 → nivel05). The 7-level mapping in `Services/_4SharkService.cs:152-180` (President → Coordinator) has **sobra de cobertura**. Hernan was right on level count — hypothesis "Hernan errou na arquitetura" is **refuted**.

**2. Mando classifications across the entire base (184 people):** 5 President + 12 VicePresident + 45 Director + 60 Superintendent + 56 GeneralManager + 6 Manager.

**3. Same-level collision check across ALL levels via `CA_Asignacion_Empleados`:**

| Level | Collisions |
|---|---|
| President | 0 |
| VicePresident | 0 |
| Director | 0 |
| Superintendent | 0 |
| **GeneralManager** | **1** — 64631 ACOSTA → 43405 LOPEZ |
| Manager | 0 |

GM-debaixo-de-GM is **isolated exception, not structural pattern**. The LOPEZ-ACOSTA case is real but unique in 184 Mandos.

**4. Responsables without classification (responsable trabalha em área não cadastrada em `vw_empresa_area_codigo_jeraquia`):** 5 cases pointing to 4 distinct unmapped areas:

| Responsable | Area_Codigo | Area_Descripcion |
|---|---|---|
| 37338 | **737** | GERENCIA SR DE NEGOCIO MULTISECTOR B016 |
| 42577 | **392** | GERENCIA NEGOCIO BBVA - B006 |
| 44482 | **639** | COORDINACION NEGOCIO MTS - E099 |
| 75441 | **430** | **GERENCIA NEGOCIO TELEFONICA - B001** |

TELEFONICA (430) is a large Atento account — its absence from the chain likely explains a disproportionate share of failures.

**5. Complete list of unmapped areas (Atento action required):** 9 confirmed → 449, 688, 534, 616, 414 (already documented) + **737, 392, 639, 430 (new)**.

### Root cause of the 55 `seat.parent_id: no puede estar en blanco` failures

**Bug é de dados, não de código.** Mando trabalha em área que não foi cadastrada em `vw_empresa_area_codigo_jeraquia` → fica sem classificação no `.NET` → todo subordinado (Supervisor, SalesRep, etc.) que aponta pra ele em `CA_Asignacion_Empleados.Responsable_Codigo` recebe `parent_id` em branco → API recusa.

**Não é um erro arquitetural do `.NET`.** O mapeamento de 7 níveis está adequado para a profundidade real dos dados (que vai até nivel05). O algoritmo posicional do Hernan funciona corretamente quando os dados estão completos.

### Next steps — conversa com Atento

**Princípio adotado:** não vamos resolver no `.NET` com fix de código defensivo genérico — sempre haverão novos cenários e corner cases. Tentar cobrir todos é buraco de coelho sem fim. Decisões abaixo são todas de dados (do lado do cliente) ou config-driven.

**Pitch pro Atento:**

1. **9 áreas não cadastradas em `vw_empresa_area_codigo_jeraquia`** (449, 688, 534, 616, 414, 737, 392, 639, 430). Cada Mando que trabalha numa área não cadastrada fica sem classificação no `.NET`, e todo subordinado dele tem `parent_id` em branco e a API recusa.
   - **Opção A (preferida — solução de raiz):** Atento cadastra as 9 áreas no view. Qualquer área nova que surgir depois também precisa ser cadastrada, mas o fix é estrutural e escalável.
   - **Opção B (fallback — config-driven override):** se o Atento não puder cadastrar agora, eles nos passam o nível correto de cada área e a gente adiciona uma nova seção `AreaLevelOverrides` no `appsettings.json` da nossa aplicação. Terceira passada em `Services/_4SharkService.cs:ResolveNivelJerarquico` aplica o override só pros casos sem classificação. ~20 linhas, isolado. Limitação: só vale pros codigos listados — qualquer área nova fora da config dá o mesmo bug.

2. **LOPEZ-ACOSTA (1 caso, 64631 → 43405)** — dois GMs com um reportando ao outro. Sem fix de código. Decisão organizacional do Atento:
   - Move um dos dois para nível diferente no source, OU
   - Aceita como exceção: 64631 ACOSTA fica com `parent_id` em branco e cai sob admin root (não dá erro novo, só consequência conhecida)

3. **Validação pós-decisão:** rodar um ciclo depois das ações do Atento e confirmar que `seat.parent_id: no puede estar en blanco` cai (a zero se cadastrarem todas as 9 + tratarem ACOSTA, ou só ao LOPEZ-ACOSTA isolado se aceitarem como exceção).

### To pick up after the context window resets

**Immediate next step:**
- Merge PR #3 (`4shark/SimplexPE.Global4Shark`) — already approved logically by Paulo before the squash; he just hadn't clicked merge. After merge, run `/merge-cleanup` adapted for the integration base (`feature/4shark-improvements`), as done for PR #1 and PR #2 (non-trivial: the skill assumes `develop` as base, must override to verify against `feature/4shark-improvements`).

**Awaiting Atento action (now non-blocker — integrator runs, but full fidelity needs this):**
- ~~Confirm RE of Luis Bravo~~ — **DONE**: RE = `71447`, applied to `appsettings.json` as `RootAdmin`. Integration is running.
- **Register 9 Area_Codigo in `vw_empresa_area_codigo_jeraquia`** (449, 688, 534, 616, 414 — originally documented; **737, 392, 639, 430 — discovered 2026-05-18 during Phase 16 source-data investigation**). See ANALYSIS.md § "Areas missing from vw_empresa_area_codigo_jeraquia" and Phase 16 of this PLAN.md. The 4 new areas correspond to responsables 37338 (MULTISECTOR B016), 42577 (BBVA B006), 44482 (MTS E099) and 75441 (**TELEFONICA B001** — large account, high impact). Until cadastrado, todo subordinado dessas áreas tem `parent_id` em branco e a API recusa.
- **Populate `Ccto_Codigo`** for the 292 employees who don't have a centro de costo — see ANALYSIS.md § "Users without CECO". Until done, those users have no CECO field in 4Shark.
- **Create `sp_reporte_cesados_4shark` on `DB_PERSONAL01`** — the SP does not exist in the customer source today. Source code is committed at `~/Projects/Atento/SimplexPE.Global4Shark/sql/sp_reporte_cesados_4shark.sql`. Until it exists, `LoadCesadosRango` fails silently (try/catch swallows) and no users are marked as `disable` in 4Shark on first load. The `4Shark` user needs `CREATE PROCEDURE` + `ALTER ON SCHEMA::dbo` to upload it (see "SQL Server permissions delegated" above).
- **Investigate RE `305854` (`VEGL9008299J0`)** — user has no `CarnetEmpleado` in the source. Skipped during integration with error `Error en {flag}:{j.AsesorCodigo}, no posee carnet`. Atento needs to either set the `carnet_empleado` for this employee or confirm whether they should be excluded.

**Cleanup PRs (post go-live, not urgent):**
- Remove dead multi-country leftovers: `LoadCountryDayli` empty method, `COUNTRIES.{c}.{co}.sap.code`, `COUNTRIES.{c}.{co}.name`, `Helpers/FileHelper.cs::saveLog`. Reference: ANALYSIS.md findings A and C.
- Decide and act on the multi-country fachada: either keep the per-country `foreach` and document the constraint (one country per scheduled run), or refactor to mono-country per instance (reads single country from env or CLI flag). Reference: ANALYSIS.md finding B.

**Backlog (longer term):**
- `FindParentMando` / `FindParentSuper` NullReferenceException for mandos with bad source data (38353, 40296, 40189 and others) — listed in old run logs, root cause not fully traced. Reference: ANALYSIS.md finding D.
- Source adapter abstraction (Simplex vs. BookCo for Chile) — large refactor, not urgent for MX.
- Mono-country deploy model + per-country scheduling (depends on the architectural decision above).

## Phase 17 — Clean-slate retest with integrator 8.4.9 (2026-05-18)

### Goal

Validate that integrator 8.4.9 (Phase 15 hotfix — UserField/UserIdentifier loader split) rebuilds Atento Mexico's world correctly from an empty app + empty Mongo state, with `ME_4Shark_DB` as the populated source of truth. Cycles 1-4 ran on 8.4.8 and accumulated state; this phase drops that state and replays with 8.4.9.

### Integrator config reference (values that govern pickup)

Confirmed values for `integrator-atento-cl-staging` via ECS task definition `integrator-atento-cl-staging-worker` on 2026-05-18 — **neither env var is set, so both use code defaults**:

| Setting | Value in this env | Code default | Effect |
|---|---|---|---|
| `FETCH_DAYS` | **unset** (not in task def `environment` nor `secrets`) | `0` (`application_configuration.rb:233-235`) | `fetch_since = last_job.ends_at - 0` = exact pickup, no overlap |
| `INITIAL_FETCH_DATE` | **unset** | `1964-01-01` (`application_configuration.rb:227-231`) | When no Job exists, integrator pulls everything since 1964 (effectively all-time) |

`fetch_since` calculation (`app/workers/job/starter.rb:23-30`):

```ruby
last_job = Job.ne(ends_at: nil).order_by(starts_at: :asc).last
fetch_since =
  if last_job
    last_job.ends_at - ApplicationConfiguration.fetch_days
  else
    ApplicationConfiguration.initial_fetch_date
  end
```

**Implications for Phase 17:**
- `Job.delete_all` → next run uses `INITIAL_FETCH_DATE` (1964) → pulls all of `ME_4Shark_DB`. Clean full-reload path
- Keeping Jobs but rewinding `ends_at` → next run picks up exactly from that timestamp (no overlap because `FETCH_DAYS=0`)

### Step 1 — Clean the app side (demo-001 / atento-001)

Use `Company::Cleansing::UserConsumer` directly with a 2x queue inflation trick so the cleansing chain stops at users (does not cascade to `UserDocumentProducer` / `UserHistoryProducer` / …).

How the chain normally works (`app/workers/company/cleansing/user_producer.rb:8-22` + `user_consumer.rb:8-17`):

- `UserProducer` plucks up to 10k user_ids, increments `company.computation.queue` by N, push_bulk's N `UserConsumer` jobs
- Each `UserConsumer` calls `user.destroy!` (ActiveRecord cascade), increments `executions`
- When `executions == queue` (i.e., `computation.done?`), the last consumer reinvokes `UserProducer`
- `UserProducer` either fetches the next 10k batch, or — if no more users — calls `UserDocumentProducer` (next resource in the chain)

The 2x trick:

```ruby
# Rails console on the app deployment (demo-001 or atento-001 — depends on subsidiary)
company = Company.find(<atento_mexico_company_id>)
user_ids = company.users.pluck(:id)
company.computation.increment_queue(by: user_ids.count * 2)
Sidekiq::Client.push_bulk('class' => Company::Cleansing::UserConsumer, 'args' => user_ids.zip)
```

Effect:
- N consumers fire in parallel on the `cleansing` Sidekiq queue, each destroys one user
- After N executions, `executions = N`, `queue = 2N` → `done?` never returns true
- Chain stops at users — `UserDocumentProducer` and downstream never fire
- The Redis key holding `computation` expires by TTL (~10h30 per current setup), no residual

**Caveats:**
- Atento Mexico has ~9.8k users (one batch fits in `UserProducer`'s 10k limit). If a future client > 10k, the 2x trick covers only the first batch
- `user.destroy!` cascades via ActiveRecord `dependent: :destroy` associations — wipes user_fields, user_activities, hierarchies, etc. Verify cascade scope on `app/models/user.rb` before running in prod-like environments
- Wait for the Sidekiq queue to drain before proceeding to Step 2

### Step 2 — Clean the integrator side (Mongo)

Decide between two paths depending on intent:

**Option A — Full reload (replay cycle-1 baseline from scratch):**

```ruby
# Rails console on integrator-atento-cl-staging
Resource.delete_all  # wipes resources + embedded imports
Job.delete_all       # forces next job to use INITIAL_FETCH_DATE (default 1964) → pulls all of ME_4Shark_DB
```

**Option B — Resume from a specific cycle boundary** (keep Job history, pick where to resume):

```ruby
Resource.delete_all
Job.ne(ends_at: nil).order_by(starts_at: :asc).last.update!(ends_at: <desired_pickup_timestamp_utc>)
```

Where `<desired_pickup_timestamp_utc>` is the exact moment you want the next run's `fetch_since` to be (e.g., cycle 1's start so the next run replays cycles 2-4's deltas).

The integrator field used for `fetch_since` is `Job.ends_at` — **not** `updated_at`. Mongoid::Timestamps adds `updated_at` automatically but the starter doesn't read it.

### Step 3 — Take ME_4Shark_DB backup (rollback safety net)

Per the Phase 14 convention: `/var/opt/mssql/data/ME_4Shark_DB_<YYYY-MM-DD>.bak` (BRT date of the work session).

For Phase 17 the `.NET` is NOT re-run — `ME_4Shark_DB` already has all data from cycles 1-4 .NET runs. Backup is purely defensive: if the integrator run goes wrong, restore the `.bak` and Mongo state stays aligned because Mongo was just emptied.

### Step 4 — Run the integrator

Trigger the integrator manually or wait for schedule. With 8.4.9 deployed (Phase 15 confirmed), observe in logs the new 5-phase loader sequence per resource:

- `UserField`: `DeleteLoaderProducer → DeleteLoaderConsumer` (all DELETEs) → `CreateLoaderProducer → CreateLoaderConsumer` (all CREATEs)
- `UserIdentifier`: `CreateLoaderProducer → CreateLoaderConsumer` → `PrimaryLoaderProducer → PrimaryLoaderConsumer` → `DeleteLoaderProducer → DeleteLoaderConsumer`

Each phase's producer waits for the prior phase's `computation` counter to drain before firing. Watch for "all 5 phases observed, none skipped" in logs.

Web/worker sizing per Phase 14 hazard note: 1 integrator worker → minimum 2 web tasks; 2 integrator workers → minimum 3 web tasks.

### Step 5 — Validate

After the integrator's final execution report:

| Metric | Expected | Why |
|---|---|---|
| `UserFields.key: ya ha sido tomado` | **0** | Phase 15 fix validated |
| `seat.parent_id: no puede estar en blanco` | depends on Atento's area registration | If 9 areas cadastradas: ≤1 (LOPEZ-ACOSTA only). If not: ~55 |
| `Hierarchies.user_id: no se ha encontrado` | matches `seat.parent_id` count | Cascade from above |
| `Hierarchies.type: tiene conflicto con los subordinados` | a few | Legitimate validation, won't go to zero |
| `users.count` in app | ~9.8k (matches `fsk_users` for Atento Mexico) | Full reload integrity |

### Step 6 — Manipulating `Job.ends_at` between subsequent cycles

After the first Phase 17 cycle, each subsequent run normally picks up where the previous one ended. To control the pickup point manually (e.g., to replay the same window twice, or to force a fixed delta range):

```ruby
Job.ne(ends_at: nil).order_by(starts_at: :asc).last.update!(ends_at: <next_pickup_timestamp_utc>)
```

This is the safer alternative to `Job.delete_all` between cycles — keeps the audit trail of past runs but rewinds the pickup pointer.

### Operational notes carried from Phase 14

- **EC2 auto-shutdown 00:00:14 BRT** on `i-08b28ace85761d7e4` (the SQL Server hosting `ME_4Shark_DB`). Verify `running` before each cycle; restart via `/aws-elevate` + `aws ec2 start-instances ...`
- **Serialization rule**: if `.NET` ever runs alongside this phase, never in parallel with the integrator — same window collision risk as Phase 14
- **Backup naming**: BRT date of the work session, not UTC

### Execution log (2026-05-18 evening BRT) — ✅ PHASE 15 VALIDATED

5 cycles executed against `integrator-atento-cl-staging` running 8.4.9. **Across 5 cycles, zero `UserFields.key: ya ha sido tomado` failures observed (vs 129 expected from Phase 14 / 8.4.8 timeline). Phase 15 fix definitively validated.**

#### Cycle-1 (baseline, from `ME_4Shark_DB_2026-05-13.bak`)

- Execution id: `6a0b6dd868cd87915855cd9e` · Integrator 8.4.9 · Base 3.0-p1
- `fetch_since`: 1964-01-01 (full reload via `Job.delete_all`)
- Total: **82.126** · Success: **81.592 (99.35%)** · Failed: 534
- **Identical numbers to Phase 14 cycle 1 (8.4.8 baseline) — confirms 8.4.9 doesn't break baseline.**
- Failure breakdown: 474 `UserField identificador: não cadastrado` (cascade from Users) + 59 `Users.seat.parent_id: no puede estar en blanco` (Phase 16 — 9 unmapped areas) + 1 `unique_register_id invalid` (data issue)
- **0 UserField key collisions** — Phase 15 fix has no negative impact on baseline (no delete+create pairs in initial full reload, by design)
- Wall time: 3h 9min 28s

#### Cycle-2 (incremental replay, from `ME_4Shark_DB_2026-05-15.bak`)

- Execution id: `6a0b9d108e3a45758a0cad61` · 8.4.9
- `fetch_since`: 2026-05-14 23:00:00 UTC (between day-13 baseline data and cycle-2 .NET writes)
- Total: **601** · Success: **475 (79.03%)** · Failed: 126
- **UserField key collisions: 0 (vs 54 in Phase 14 / 8.4.8 cycle 2)** ✅
- Failure breakdown: 122 `Hierarchies.date: debe ser después 18/05/2026` (test replay artifact — see "Replay artifact" below) + 2 Hierarchies type conflict (legitimate) + 1 parent_id same value (noise) + 1 cascade

#### Cycle-3 (incremental replay, from `ME_4Shark_DB_2026-05-16.bak`)

- Execution id: `6a0ba154a2163b76d5607446` · 8.4.9
- `fetch_since`: 2026-05-16 12:00:00 UTC
- Total: **921** · Success: **669 (72.64%)** · Failed: 252
- **UserField key collisions: 0 (vs 72 in Phase 14 / 8.4.8 cycle 3)** ✅
- Failure breakdown: 72 hierarchy date artifact + 66 hierarchy `parent_id is invalid` (cascade artifact — parent_id points to a Phase-13-failed user) + 55 hierarchy user_id cascade + 55 Users seat.parent_id (Phase 16) + 3 type conflict + 1 cascade
- All hierarchy entries cascaded to fail (196/196) because the day-of-test creation order broke chronological validation downstream

#### Cycle-4 (incremental replay, from `ME_4Shark_DB_2026-05-17.bak`)

- Execution id: `6a0ba5e489bc3bf14a816e78` · 8.4.9
- `fetch_since`: 2026-05-17 22:09:00 UTC (precision required — fsk_hierarchy boundary is 210ms between cycle-3 max and cycle-4 min)
- Total: **24** · Success: **21 (87.5%)** · Failed: 3
- **UserField key collisions: 0 (vs 3 in Phase 14 / 8.4.8 cycle 4)** ✅
- Failure breakdown: 3 hierarchy date artifact only

#### Cycle-5 (fresh .NET delta — most representative test)

- Execution id: `6a0ba962e5549617b06b0566` · 8.4.9
- New `.NET` run executed before cycle-5 to generate genuine source deltas (not replay)
- `fetch_since`: 2026-05-18 00:00:00 UTC
- Generated by `.NET`: 6 users updated · 6 new hierarchy · 1 new user_activity · 16 new user_fields (8 delete + 8 create pairs)
- Total: **29** · Success: **23 (79.31%)** · Failed: 6
- **UserField key collisions: 0** (would have been ~8 in 8.4.8 based on delete/create pair ratio) ✅
- Failure breakdown: 4 hierarchy `parent_id es igual al valor actual` (.NET noise — sending no-op parent updates) + 2 hierarchy date artifact
- **Most important validation: 16 user_fields incrementais reais, zero collisions.**

### Cycle summary — UserField key collision count across runs

| Cycle | Source | UserField.key in 8.4.8 | UserField.key in 8.4.9 |
|---|---|---|---|
| 1 (baseline 82k) | replay .bak | 0 (n/a on full reload) | **0** |
| 2 incremental (601) | replay .bak | 54 | **0** |
| 3 incremental (921) | replay .bak | 72 | **0** |
| 4 incremental (24) | replay .bak | 3 | **0** |
| 5 incremental (29) | fresh `.NET` | N/A (not run on 8.4.8) | **0** |
| **Total observed in replay (cycles 2-4)** | | **129** | **0** |

### Phase 16 status post-cycles

Cycle 2 surfaced 59 `Users.seat.parent_id: no puede estar en blanco` failures in cycle 1 baseline (same as Phase 16 prediction — 8 Mandos in unmapped areas + cascading subordinates). Atento has not yet registered the 9 missing areas, so the Phase-13/16 failures persist as expected. **Phase 16 outcome is still pending Atento action (register 9 areas in `vw_empresa_area_codigo_jeraquia`, or alternative: send 4Shark the `AreaLevelOverrides` mapping).**

### Replay artifact — `Hierarchies.date: debe ser después`

Discovered during cycle 2 retest: app's `SeatPromotionForm`/`SeatForm`/`SeatDemotionForm` (`~/Projects/4Shark/app/app/forms/seat_promotion_form.rb:26`) enforces strict chronological hierarchy:

```ruby
if date <= seat.histories.last.starts_at
  errors.add(:date, :after, starts_at: I18n.l(seat.histories.last.starts_at))
end
```

In Phase 17 replay: baseline created all users today (May 18) → users' first seat history has `starts_at = today`. Replaying cycle-2/3/4 `.bak` data sends hierarchy updates with `date = May 15/16/17` → fails because `May 15 ≤ today`. **Not a bug in the integrator nor the app — artifact of compressing 4 days of source-data evolution into a single test day.** Would not occur in production (cycle deltas arrive on later calendar days).

### Boundary timing discovery during cycle 4

When tuning `Job.ends_at` to capture only cycle-4 deltas, found that fsk_hierarchy cycle-3-max (22:09:26.313 UTC May 17) and cycle-4-min (22:09:26.523 UTC May 17) are only **210ms apart**. This is far tighter than fsk_user_fields (~19h gap between cycles). The `.NET` cycle-4 run actually executed at 22:09 UTC May 17 (not 01:09 UTC May 18 as previously documented in Phase 14 cycle 4 entry — **correction needed there**). Practical implication: when isolating cycle-4 from cycle-3 via timestamp manipulation, fetch_since must be < min(cycle-4 timestamps across all tables) = 22:09:22.000 UTC; otherwise some cycle-4 records get skipped.

### Operational lessons from Phase 17

1. **`bin/ecs connect atento-cl-staging worker`** opens a Rails console on the running worker task — used for `Job.ends_at` adjustments between cycles
2. **`bin/rails integration:start`** displays NUMBERS preview (Y/n confirm) — abort with `n` and adjust `Job.ends_at` if NUMBERS doesn't match expected delta before committing to the run
3. **Integrator scales itself down** to 0 web/worker at job-finish — manual scale-up needed before each cycle (`bash ~/.claude/scripts/ecs-scale.sh --desired-count 1`)
4. **The 8.4.9 5-phase loader sequence works:** UserField Delete→Create, UserIdentifier Create→Primary→Delete, with computation counters draining between phases. No race condition observed across 5 cycles
5. **SQL Server access via 1Password key:** `op read "op://Employee/KP 4shark/private key" --account 4shark | ssh-add -` (in-memory, no key on disk) then `ssh ubuntu@10.12.255.51` — never persist keys to `/tmp/`
6. **Backups available on EC2 (`i-08b28ace85761d7e4:/var/opt/mssql/data/`):** `2026-05-13`, `2026-05-15`, `2026-05-16`, `2026-05-17` (`QUEBRADO_NAO_USAR.bak` marked explicitly do-not-use)

### Memory notes (saved in this session)

- `~/.claude/projects/-Users-plribeiro3000-Downloads-Atento-Mexico-dessarollos/memory/feedback_invoke_skills_autonomously.md` — when a command fails and a skill resolves it (aws-elevate, op-signin, etc.), invoke directly via Skill tool without asking. **Already existed** before this session; reaffirmed by usage today (e.g. /aws-elevate path discovery for `ME_4Shark_DB`).
- Two memories I created and then deleted as redundant: `user_name.md` (Paulo's name; project-scoped memory is useless for a global fact — to be persisted in `~/.claude/CLAUDE.md` via a separate PR on `dot-claude` when convenient), and `feedback_no_name_guessing.md` (redundant with the name memory once it's global).

## Phase 18 — Communication artifacts for Mexico delivery (2026-05-19)

Not strictly required by the technical workflow, but needed to formalize the handover. Two artifacts produced in `/tmp/` (deliberately ephemeral — final versions live in the engineer's mail history).

### Files

- **`/tmp/entrega_atento_mexico_pdf_source_20260519.md`** — technical reference PDF source (Spanish, markdown intended for `pandoc`/Chrome HTML conversion; engineer to render to PDF using their preferred tool)
- **`/tmp/email_atento_entrega_mexico_20260519.txt`** — email body (Spanish, plain text)

### PDF structure (`entrega_atento_mexico_pdf_source_20260519.md`)

- **Contexto** — short intro: app received non-functional, "diversos bugs menores, flujos incorrectos y cambios en arquitectura" → presents only the major changes (no top list of 16 items; engineer decided that level of detail belonged to the underlying commits, not the PDF)
- **Cambios principales** — 7 sections (architectural impact ordered):
  1. SQLite cache removal (single source of truth; agravante: disco exponencial, 7d cap vs cierre mensual 30d)
  2. Unified load (initial = daily, single command, no SQLite snapshot)
  3. Removal of email identifiers (email not valid as identifier in 4Shark)
  4. UploadMandos top-down ordering (President → ... → Coordinator) to avoid `fsk_user_fields` duplicates
  5. Subsidiarias: company-to-subsidiary mapping in normalized base + integrator flag NOT to publish to platform (México doesn't want module; mapping kept for multi-company future + uniqueness guarantee)
  6. Multi-country iteration removed (sequential structure could not honor "00:00 todos los países" SLA)
  7. **Fallback to admin root when hierarchy unresolvable** — preserves user access despite source-data gaps; integration self-heals on next run after source fix. This is the section that frames "Pendientes" as non-blocking.
- **Pendientes del lado de Atento México** — explicit "no bloquean la activación en producción" line at the top. Then: 9 unmapped `Area_Codigo` in source feeding `vw_empresa_area_codigo_jeraquia` (449, 688, 534, 616, 414, 737, 392, 639, 430 — last is BBVA, highest volume). Plus minor observations: empleados sin `Ccto_Codigo` (no CECO field) and sin `Empleado_Carnet` (not integrated).
- **Validación** — generic framing: two snapshots captured at different moments in homologation, compared, divergences resolved. Six flows listed (creación/actualización/desactivación/reactivación/promoción-democión/cambio de gestor). **Deliberately does NOT mention**: 5 cycles, specific dates (Friday vs Monday), procedure names, or hardcoded production user details — engineer's access to homologation is sensitive ground.
- **Próximo paso** — only requirement from Atento: credenciales del usuario de producción del sistema Simplex de Atento México.

### Email structure (`email_atento_entrega_mexico_20260519.txt`)

- **Subject**: *Entrega de integración de usuarios — Atento México · Avance regional Chile, Colombia y Brasil*
- **Recipients** grouped into 5 blocks: Global System (3) / México (3) / Chile (3) / Colombia (2) / Brasil (3). Engineer's confidence in the recipient list comes from cross-referencing Granola meeting transcript against Gmail thread participation
- **Body sections**:
  1. Formalization paragraph + Global cost note (4Shark assumes execution cost, no additional Atento infra cost — argued with Global)
  2. Por-país blocks: **México entregado** (with non-blocking pendencies for hierarchy + auto-correction promise) / **Colombia bloqueada por acceso BBDD** / **Chile activación en producción hoy** / **Brasil funcional en producción**
  3. **Resumen del pedido** — México: credenciales prod; Colombia: restablecimiento `CO_4Shark_DB_SIMPLEX`
  4. PDF attachment reference: "el detalle técnico de los cambios principales aplicados en la aplicación de integración"

### Strategic framing decided with co-founder

The "send to all four countries at once" approach was deliberate (per co-founder Danilo Assis on 2026-05-19): (a) makes México accountable in front of peers, (b) turns the delivery into a Global-scale event harder to suppress, (c) provides cover to include strategic Brazil recipients (Bruno Sexto, Márcio Silva) without the appearance of going around Daniel. The cost-framing line ("conforme acordado con Global, esse custo queda del lado de 4Shark") removes Atento TI's typical leverage point.

### Open follow-ups

- Wait for México credentials of production user
- ~~Restablecer acesso `CO_4Shark_DB_SIMPLEX` (Colombia) — needed to resume Colombia development~~ — **DONE 2026-05-20**: access restored, Colombia test cycle now unblocked
- ~~Chile go-live for users-integration scheduled for today~~ — **DONE 2026-05-19**: Chile in production, first integration cycle ran successfully on 2026-05-19
- Brasil ongoing in production

## Phase 19 — Colombia source validation kickoff (2026-05-20) — IN PROGRESS

### Goal

Inventário do source `DB_PERSONAL01` da Colômbia (Simplex CO) antes de propor adaptação do SP e configuração do `.NET`. Validar read-only o que existe vs o que falta, sem mexer em produção do cliente. Todas as queries da sessão estão em `colombia-source-validation.sql` (supporting file neste diretório).

### Contexto histórico do Simplex (pesquisado 2026-05-21)

Pesquisa pública não confirma origem do `DB_PERSONAL01`. Indícios circunstanciais:

- **"Simplex by Atento"** ([atento.com/en/assets/simplex](https://atento.com/en/assets/simplex)) é um produto **WFM** da própria Atento — controle de jornada/ponto/acesso. **Não é HRMS.** O `DB_PERSONAL01` é o sistema interno de RH/folha que **alimenta** o Simplex
- **Schema legacy** datado de 2002-2007 (`Areas` 2002, `Empleados` 2007, `Centro_Costo` 2002)
- **Terminologia peruana**: `tipo_documento` lista "DNI" como tipo 1 (DNI é nome usado em Peru/Argentina/Espanha, não Colômbia que usa CC)
- **AplexCorp** ([rhplus.pe](https://www.rhplus.pe/)) tem produto **RHplus** — sistema peruano de planillas há 14+ anos. Possível origem mas **não confirmado publicamente**

**Hipótese de trabalho (sujeita a confirmação Atento):** o sistema base foi clonado por país quando Atento entrou em cada mercado. Cada clone evoluiu independentemente — após 15-20 anos de divergência:
- MX tem `Empleado_Cesado` ❌ CO não tem
- CO tem `V_EMPLEADO_ACTIVO_CESADO` ❓ MX desconhecido
- MX é multi-tenant (`empresa_codigo` em vDatosTotal) ❌ CO single-tenant
- Mesma raiz, código divergiu localmente

**Implicação prática:** **não existe um "Simplex padrão"** que possa ser referência ground-truth. Cada país é caso isolado. O que aprendemos pra MX **não é diretamente transportável** pra CO — cada estrutura precisa ser revalidada localmente. **Esta sessão e as próximas devem operar nesse princípio:** observar dados, perguntar à Atento, nunca assumir paridade com MX.

### Pre-existing infrastructure (DB_PERSONAL01 on Simplex CO)

- **Server**: `COLBOGSQL43SOX`, SQL Server 2016 SP3-GDR
- **DB**: `DB_PERSONAL01` (mesmo nome que México — cada país tem sua instância dedicada)
- **Login 4Shark**: `userCO_4Shark_DB_SIMPLEX`
- **Tabela `empresa`**: **1 row apenas** → `empresa_codigo=1`, "ATENTO COLOMBIA", RUC `20414989277`, ativa. **Source é single-tenant** (vs MEX que é multi-tenant na mesma instância)

### Permissões do user 4Shark — LIMITADAS

Não tem `db_datareader` nem nenhuma role. Permissões vêm de GRANTs específicos por objeto:

- DB scope: `CONNECT`, `VIEW ANY COLUMN ENCRYPTION KEY DEFINITION`, `VIEW ANY COLUMN MASTER KEY DEFINITION`
- Object SELECT confirmado em: `vDatosTotal`, `CA_Asignacion_Empleados`, `empresa`, `vw_jerarquia_simplex_total2`
- **Sem `VIEW DEFINITION`** em `vDatosTotal` — não vemos query interna nem dependências (Bloco 4.b retornou denied em `sys.sql_expression_dependencies`). Não bloqueia, já que SELECT direto na view funciona
- **`CREATE PROCEDURE` / `ALTER ON SCHEMA::dbo`** não verificadas — necessárias pra subir SPs novos, pendente pedir pra Atento CO

### Inventário de objetos críticos

| Objeto | Status |
|---|---|
| `sp_reporte_jeraquia_4shark` | ❌ MISSING |
| `sp_reporte_cesados_4shark` | ❌ MISSING |
| `vw_empresa_area_codigo_jeraquia` (nome MX) | ❌ MISSING |
| `vDatosTotal` | ✅ PRESENT (42 col, criada 2011-02-14, modificada 2018-04-18) |
| `CA_Asignacion_Empleados` | ✅ PRESENT (criada 2005, modificada hoje 2026-05-20) |

### Diferenças estruturais com México

- **Sem `empresa_codigo` em `vDatosTotal`** — view já pré-filtrada internamente pra empresa_codigo=1. Consequência: SP CO não precisa de filtro dinâmico, mas mantém a assinatura `@empresa_codigo INT` pra contrato com `.NET` (apenas popula `#t_erp.empresa_codigo` a partir do parâmetro). Zero mudança no `.NET`
- **Sem `tipo_documento_abreviado`** em `vDatosTotal` — vai precisar default NULL ou outra coluna
- **Schema de hierarquia é completamente diferente.** México usa `vw_empresa_area_codigo_jeraquia` com colunas `nivelXX_responsable_*` (6 níveis efetivos). CO tem **outras views na família `jera*`** — descobertas abaixo

### Índices em `CA_Asignacion_Empleados`

- PK clustered: `(Asignacion_Codigo, Responsable_Codigo)`
- 3 NC começando com `Responsable_Codigo`: `xResp_Activo`, `responsable_empleado`, `xResponsable_activo`
- 1 NC `_dta_index_..._9_477244755_...` começando com `Empleado_Codigo` — cobre walk-up por código
- 1 IX em `Asignacion_Activo` + includes

Cobertura adequada pra qualquer JOIN futuro na Round 2.

### Inventário das views de hierarquia (19 objetos com "jera" no nome)

**Descartadas (7):** `jerarquia` (lookup id+descripcion), `jerarquia_emp_sup_jef_ger` (só 3 níveis), `perfil_mando_jerarquico` (não-hierarquia), `TBL_CCARGA_TURNO_BIO_JERARQUIA` + `_LOGGER_JERARQUIA` (turno/biometria), `vw_Ccto_Jerarquia` / `vw_jerarquia` (tree recursivo, não wide).

**Candidatas reais (12), divididas em 2 famílias:**

**Família A — `vca_jerarquia_*` (8 views, orientadas por ÁREA):**
- Estrutura padrão: `Area_Descripcion1`, `cargo1`, `empleado_rut1..5`, `empleado1..5`, `Empleado_Codigo1..5`, `jefatura`/`gerencia`/`direccion`/`direccionPAIS` (+ codigos), `responsable_codigo`, `responsable_fecha`, `asesor_fecha_asignacion`, `cod_campana`
- Variantes: `_empleado` (3 níveis), `_organizacion` (3), `_personal_no_contratado` (4), `_por_tipo_area` (4), `_por_tipo_area_atento_colombia` (4, **filtrada Atento CO**), `_por_tipo_area_COLP` (4), `_por_tipo_area_total` (4 + `Area_a1..a4`), `vca_jerarquia03` (3), `vca_jerarquia05` (3)

**Família B — `vw_jerarquia_simplex*` (3 views, orientadas por EMPLEADO):**
- Estrutura: `DNI_PERSONAL`, `NOMBRE_PERSONAL`, + por nível: `JEFATURA`/`NOMBRE_JEFATURA`/`DNI_JEFATURA` (idem `GERENCIA`, `DIRECCION`, `DIRECCION_PAIS`), + `*_RESPONSABLE_SUPERVISOR` (chefe direto), + dados auxiliares (`Cod_Campana`, `SERVICIO`, `MODALIDAD`, `CENTRO_COSTO`, `CC_DESCRIPCION`, etc)
- Variantes: `vw_jerarquia_simplex` (37 col), `_total` (44 col, adiciona `Cargo_Nomina`/`Estado_usuario`/`Local`/`distrito`/`Empleado_ultima_fecha_cese`), `_total2` (45 col, adiciona `ESTADO_EMPLEADO` texto)

### Sample analisado: `vw_jerarquia_simplex_total2`

Aggregate sobre `Estado_usuario = 1` (ativos):

| Métrica | Valor | % |
|---|---:|---:|
| total_active | 6810 | 100% |
| `DIRECCION_PAIS` NULL | 0 | 0.00% |
| `DIRECCION` NULL | 125 | 1.84% |
| `GERENCIA` NULL | 311 | 4.57% |
| `JEFATURA` NULL | 585 | 8.59% |
| `DNI_RESPONSABLE_SUPERVISOR` NULL | 158 | 2.32% |
| **Cadeia completa nos 4 níveis** | **5994** | **88.02%** |

**Confirmado: a Colômbia tem 4 níveis hierárquicos** (`JEFATURA` / `GERENCIA` / `DIRECCION` / `DIRECCION_PAIS`) — bate com o que Atento havia comunicado.

### Achados pra considerar no SP adapter

1. **`Empleado_Codigo1..4` desliza dependendo da cadeia.** Empleado com cadeia completa: `Empleado_Codigo4 = 33160` (DIRECCION_PAIS). Empleado sem JEFATURA: `Empleado_Codigo3 = 33160` (mesma pessoa, posição deslocada). **Estratégia recomendada: ignorar `Empleado_CodigoX`, resolver código de cada nível via JOIN com `vDatosTotal` por DNI.** A salvar: a coluna numerada não é confiável como mapping fixo.
2. **`responsable_codigo` na view geralmente NULL pra ativos com cadeia completa.** Chefe direto vem de `DNI_RESPONSABLE_SUPERVISOR` + JOIN com `vDatosTotal` pra resolver o `Empleado_Codigo`.
3. **12% dos ativos com gaps em hierarquia** — vai exigir fallback to admin (mesmo padrão do México: PR #5).
4. **`Estado_usuario = 1` = ativo, `= 2` = cesado** (`ESTADO_EMPLEADO` é texto: "Cesado", etc).

### Identifier strategy (2026-05-21)

Análise das colunas candidatas em `vDatosTotal` pra identifier no 4Shark:

| Coluna | Populated | Unique | Veredito |
|---|---:|---:|---|
| `Empleado_Carnet` | 4/6809 (0.06%) | — | ❌ vestigial — **não usar** |
| `Empleado_Codigo` | 6809/6809 (100%) | ✅ 6809 distintos | ✅ external_id natural |
| `Empleado_Dni` | 6809/6809 (100%) | ✅ 6809 distintos | ✅ identifier primary natural |
| `Empleado_Email` | 4876/6809 (71.6%) | ⚠️ 4875 distintos (1 duplicata) | ✅ atributo opcional (não identifier) |

**Diferença material vs México:**

| Propósito | México | Colômbia |
|---|---|---|
| `external_id` no 4Shark | `Empleado_Carnet` | **`Empleado_Codigo`** |
| `user_identifier` primary | `<carnet>@atento.com` (sintético) | **`Empleado_Dni`** (sujeito a validação CC, ver caveat abaixo) |
| Email (atributo opcional) | construído do carnet | **`Empleado_Email`** real quando existe (~71.6%); NULL nos 28.4% restantes |

**Implicação pro SP CO:**
- Linha 274-276 do SP MX (`CONCAT(carnet_empleado, '@atento.com')`) **não se aplica** — passar `Empleado_Email` direto da view
- `#t_erp.carnet_empleado` pode ficar NULL na CO ou ser preenchida com `Empleado_Dni`

**⚠️ Investigação `Empleado_Dni` vs CC (Cédula de Ciudadanía) — 2026-05-21**

Na Colômbia o documento único é **CC** (DNI é o nome do documento no Peru/Argentina/Espanha). A coluna `Empleado_Dni` no source CO foi validada contra todos os 6809 ativos:

| Métrica | Valor | % |
|---|---:|---:|
| Total | 6809 | 100% |
| Formato compatível com CC (8-10 dígitos numéricos puros) | 6704 | 98.46% |
| Contém não-numéricos (letras/hífens/espaços) | 0 | 0.00% |
| Length 8 (CC antiga típica) | 779 | 11.44% |
| Length 9 | 0 | 0.00% |
| Length 10 (NUIP moderno) | 5925 | 87.02% |
| **Length < 8 (outliers)** | **105** | **1.54%** |
| — Length 6 | 8 | 0.12% |
| — Length 7 | 97 | 1.43% |

**Catálogo `tipo_documento` no source:** 1 = DNI, 2 = PASAPORTE, 3 = LIBRETA MILITAR. **Não tem "CC" como entrada explícita.** Tabela `Empleados` **não tem FK pra `tipo_documento`** — todos os empleados são tratados como tipo "DNI" implicitamente.

**Hipótese "DNI = CC com nome legacy" se sustenta pra 98.46%** (formato 8-10 dígitos numéricos é o padrão CC colombiana — 8 dígitos antigas, 10 dígitos NUIP moderno).

**Hipótese "outliers = CC antigas pré-1970" REFUTADA pelos dados.** Sample dos 8 empleados com length 6:

| Empleado | DNI | Nascimento | Ingresso |
|---|---|---|---|
| KARELLIM GUTIERREZ | 704284 | 1981 | 2020 |
| ERNESTO SEGURA | 843101 | 1976 | 2022 |
| HERCILIA MORA | 550740 | 1982 | 2025 |
| EDGAR REYES | 327676 | 1993 | 2025 |
| JESUS PORTOCARRERO | 458011 | 1992 | 2025 |
| SAMUEL SALAZAR | 523310 | 1986 | 2025 |
| VALENTINA SEGOVIA | 642799 | 1999 | 2026 |
| OSCAR BRICEÑO | 647703 | **2006** | 2026 |

Empleado nascido em 2006 (19 anos) com documento de 6 dígitos não é CC válida na Colômbia — NUIP moderno tem 10 dígitos. Length 7 tem mesmo padrão: muitos nascidos após 1990 com dígitos insuficientes (ex: RIVERO MARIANA nascida 1992 com DNI 1241277).

**Possibilidades pros 105 outliers (PRECISA CONFIRMAÇÃO ATENTO CO — não assumir nada):**

1. Cédula de Extranjería (CE) com prefixo de letras descartado no armazenamento
2. Pasaporte truncado ao numérico (apesar do catálogo listar pasaporte como tipo 2 separado)
3. Tarjeta de Identidad (TI — menores de idade)
4. Documentos de terceirizados / contratos especiais
5. Erros de cadastro (zeros à esquerda perdidos no armazenamento, dados truncados)

**Ação:** levar a lista completa dos 105 outliers (exportável via filtro `WHERE LEN(Empleado_Dni) < 8`) pra Atento CO classificar. Sem essa confirmação, **não podemos garantir que `Empleado_Dni` é uniformemente CC pra usar como identifier**. O caminho seguro é tratar os 98.46% como CC, e os 1.54% como casos especiais a serem definidos com o cliente.

### Validação da fonte de cesados (2026-05-21)

SP MX `sp_reporte_cesados_4shark` depende de `Empleado_Cesado` (MISSING na CO) + `Empleados` + `empleado_historico` + outros. Investigação:

**Inventário do SP cesados na CO:**

| Objeto | Status |
|---|---|
| `Empleado_Cesado` | ❌ MISSING (bloqueia o SP MX original tal-qual) |
| `empleado_historico` | ✅ PRESENT |
| `empleado_historico_BCK` | ❌ MISSING (secundário, era backup) |
| `Empleados` | ✅ PRESENT (todas colunas críticas) |
| `Areas`, `Locales`, `Items`, `Tipo_Documento_Identidad` | ✅ PRESENT |
| `Grupos_Cargos`, `Grupos_Ocupacionales`, `Atributos`, `CA_turnos_combinacion` | ✅ PRESENT |
| `DB_GESTION` (cross-DB pra Campanas) | ✅ existe |

**Diferenças de schema vs MX:**
- `empleado_historico` na CO **não tem `empresa_codigo` nem `pais_codigo`** (consistente com source single-tenant)
- `Empleados.Empleado_Dni` é `varchar(50)` mas `vDatosTotal.Empleado_Dni` é `varchar(10)` — view trunca silenciosamente em relação à base

**Fonte alternativa de cesados — `V_EMPLEADO_ACTIVO_CESADO`:**

View que combina ativos + cesados. Schema:
- `Empleado_Codigo`, `Empleado_Apellido_Paterno/Materno/Nombres`, `Empleado_Dni`
- `Estado_Codigo` (1 = Activo, 2 = Cesado), `Estado_descripcion`
- `Empleado_Fecha_Ingreso`, `fecha_cese`
- `Area_Codigo` + `Area_Descripcion`, `modalidad_codigo` + `Modalidad`
- `Campaña`, `Cod_SAP`, **`Tipo_Retiro`** (extra)

Falta: cargo, email, carnet, responsable/supervisor — resolveriam via JOIN com `Empleados` e `empleado_historico` (mesmo padrão que o SP MX faz).

**Observações dos dados (NÃO conclusões — exigem confirmação Atento CO):**

- 118.327 cesados acumulados (histórico desde 2012-05-23 até 2026-05-20)
- 2.050 cesados em janela de 90 dias
- Volume mensal nos últimos 12 meses varia entre 249 (parcial) e 876 (mês completo), majoritariamente entre 580-880
- `fecha_cese` 100% populada nos cesados; `Tipo_Retiro` populado em 99.997%
- `Tipo_Retiro` tem 2 valores apenas: "No Deseada" (63%) e "Deseada." (37%, com ponto final no source)
- Zero ocorrências de mesmo `Empleado_Codigo` aparecendo como ativo + cesado na view

**Inconsistência de "ativos" no source — 4 contagens diferentes:**

| Source | Ativos |
|---|---:|
| `Empleados.Empleado_activo=1` (tabela base) | 6861 |
| `vw_jerarquia_simplex_total2` (Estado_usuario=1) | 6810 |
| `vDatosTotal` (sem filtro) | 6809 |
| `V_EMPLEADO_ACTIVO_CESADO` (Estado_Codigo=1) | 6797 |

Cada view aplica filtros internos próprios. Diferença de até 64 rows entre fonte mais permissiva e mais restritiva. **Source of truth pra "ativos" ainda a definir.**

**Perguntas que precisam de resposta da Atento CO antes de qualquer afirmação:**

1. Os 2050 cesados em janela de 90 dias representam saídas reais ou inclui movimentos lógicos (transferência, mudança de contrato, fim de campanha)?
2. Semântica de "No Deseada" vs "Deseada" — quais ações o `.NET` deve tomar pra cada tipo? Ambos viram `disable_user` no 4Shark, ou tratamento diferente?
3. Reativação: empleado que volta vira mesmo `Empleado_Codigo` ou novo? Como deve ser tratado na integração?
4. Janela de 90 dias é adequada pra Atento CO ou precisa ajustar?
5. Qual das 4 views de "ativos" é a fonte oficial do que o `.NET` deve registrar como população ativa?

### Estado da decisão sobre qual view usar

**Top candidate atual: `vw_jerarquia_simplex_total2`** — pelo nome "simplex" + 45 colunas + ESTADO_EMPLEADO + Empleado_ultima_fecha_cese. Mas **a decisão NÃO está fechada** — falta comparar com `vca_jerarquia_por_tipo_area_atento_colombia` (orientada por área, 4 níveis + 5 IDs, filtrada Atento CO) que estruturalmente é mais alinhada com a view do México.

### Pending — primeira query de amanhã

```sql
SELECT permission_name FROM fn_my_permissions('vca_jerarquia_por_tipo_area_atento_colombia', 'OBJECT');

SELECT TOP 5 *
FROM vca_jerarquia_por_tipo_area_atento_colombia
WHERE jefatura IS NOT NULL
  AND gerencia IS NOT NULL
  AND direccion IS NOT NULL
  AND direccionPAIS IS NOT NULL;
```

### Open questions / pendências Atento CO

1. **Conceder `CREATE PROCEDURE` + `ALTER ON SCHEMA::dbo`** ao `userCO_4Shark_DB_SIMPLEX` (necessário pra criar `sp_reporte_jeraquia_4shark` e `sp_reporte_cesados_4shark` na CO)
2. **Conceder `VIEW DEFINITION`** em `vDatosTotal` (opcional — não bloqueia, mas ajudaria a ver internals)
3. **Confirmar com Atento CO**: hierarquia da Colômbia é mesmo só 4 níveis? Validação dos 88% sugere que sim
4. **Definir `RootAdmin` da Colômbia com Atento CO** — NÃO é a pessoa de nível mais alto na hierarquia (essa não acessa a plataforma). RootAdmin deve ser alguém da **operação RH / comissões** na Colômbia que efetivamente usa o 4Shark. LOPEZ ESTRADA MIGUEL JOSE (DNI `94305777`, Empleado_Codigo `33160`) aparece como topo (`DIRECCION_PAIS`) nos dados, mas explicitamente **descartado como candidato** — Atento define a pessoa correta

### Supporting file

`colombia-source-validation.sql` neste diretório — script com 7 blocos de queries metadata-only usados nesta investigação. Reutilizável pra próximos países.

### To-do list pra amanhã

- [ ] Rodar comparação com `vca_jerarquia_por_tipo_area_atento_colombia` (query acima)
- [ ] Decidir entre `vw_jerarquia_simplex_total2` vs `vca_jerarquia_por_tipo_area_atento_colombia` baseado em dados
- [ ] Inventariar dependências auxiliares do SP do México na CO (`Atributos`, `items`, `Empleado_Servicio`, `V_PROGRAMAS`, `centro_costo`, `Empleado_Proveedor`, `Proveedor`, `empleado_indicador`, `nomina`, `tipo_nomina`, `db_gestion.dbo.campanas`, `db_gestion.dbo.clientes`, `empleados`)
- [ ] Montar versão mínima viável do SP CO (INSERT inicial em `vDatosTotal` + UPDATE responsable em `CA_Asignacion_Empleados` + UPDATE jerarquia da view escolhida via JOIN por DNI)
- [ ] Decidir `RootAdmin` da Colômbia com Atento CO
- [ ] Pedir permissões `CREATE PROCEDURE` / `ALTER SCHEMA` pra Atento CO
- [x] ~~Confirmar se `Empleado_Dni` é mesmo CC~~ — **DONE 2026-05-21**: 98.46% (6704/6809) compatível com CC; 1.54% (105) outliers requerem classificação pela Atento (vide tabela na sub-seção "Investigação `Empleado_Dni` vs CC")
- [ ] **Levar a lista dos 105 outliers (length < 8 em `Empleado_Dni`) pra Atento CO classificar** — hipótese "CC antigas" foi refutada pelos dados (empleados nascidos pós-1990 entre os outliers). Atento precisa identificar tipo real (CE, Pasaporte, TI, terceirizado, ou erro de cadastro)
- [ ] Após classificação dos outliers: validar estratégia final de identifier. Default: 98.46% via `Empleado_Dni` como CC; tratamento dos 105 depende da resposta da Atento (possível fallback pra `Empleado_Codigo` quando `Empleado_Dni` não for CC válida, ou um identifier alternativo a definir por tipo de documento)
- [ ] Após SPs subidos: adaptar `appsettings.json` (connection strings staging + `RootAdmin` + `COMPANIES.COL` mapeado a `empresa_codigo=1`)

### Gaps observados na análise do código `.NET` (2026-05-21)

Investigação do `_4SharkService.cs` revelou pontos que não estavam mapeados nas seções anteriores:

#### Hard-coded MX no código — parametrizar como config por país

Valores fixos no source `.cs` que precisam virar configuração no `appsettings.json` (junto com `ConnectionString_*`, `RootAdmin`, `Admins`):

```csharp
// Services/_4SharkService.cs:1111 — create_user
$"EXEC create_user @email=..., @register_type={"MX_RFC_PERSON"}, ..., @state={"MX-CMX"}, ..."

// Services/_4SharkService.cs:1092 — fallback city
var city = string.IsNullOrWhiteSpace(j.AsesorDistrito) ? "Ciudad de México" : j.AsesorDistrito!;

// Services/_4SharkService.cs:315 — ReifySubsidiaries / create_subsidiary
$"EXEC create_subsidiary @name=..., @register_type={"MX_RFC_PERSON"}, ..."
```

3 valores fixos hoje: `register_type`, `state`, `city` fallback. **Decisão a tomar no design:** parametrizar TODOS os valores que diferem por país (não só esses 3) como opções no `appsettings.json` sob `COMPANIES:<key>:*`, permitindo configurações distintas por país no mesmo binário. Junto com as connection strings e senhas.

#### Regra `GrupoOcupacional == 2` (linhas 620 + 632)

```csharp
private void ExtractRacs(...)
{
    foreach (var j in lista)
    {
        if (j.GrupoOcupacional == 2 && !this.supers.Contains(j.AsesorCodigo))
            this.racs.Add(j.AsesorCodigo);
    }
}

private void ExtractAnalistas(...)
{
    foreach (var j in lista)
    {
        if (!this.mandos.Contains(j.AsesorCodigo)
            && !this.supers.Contains(j.AsesorCodigo)
            && j.GrupoOcupacional != 2)
            this.analistas.Add(j.AsesorCodigo);
    }
}
```

Distingue **Rac vs Analista** via valor literal `2` em `GrupoOcupacional`. Em MX é um valor de catálogo `Grupos_Ocupacionales`.

**Validação na CO (2026-05-21):** o conceito `id=2 = RAC` **existe** na Colômbia também (mesmo schema legacy compartilhado entre os clones por país). Catálogo `Grupos_Ocupacionales` da CO tem 23 entradas (1=ANALISTA, **2=RAC**, 5=SUPERVISOR, 8=JEFATURA, 9=GERENTE, 10=DIRECTOR, 21=ADMINISTRATIVO, 22=SUPERVISOR DE ESTRUCTURA, 23=DIRECTOR N/2, etc.).

**Distribuição real em `vDatosTotal` da CO (6809 ativos):**

| Id | Descripcion | Cnt | % | Bucket no `.NET` |
|---|---|---:|---:|---|
| 2 | RAC | 5842 | 85.8% | Rac |
| 1 | ANALISTA | 315 | 4.6% | Analista (else `!= 2`) — semanticamente correto |
| 5 | SUPERVISOR | 266 | 3.9% | Cai no else, mas se aparecer em `ResponsableCodigo` vira Super via `ExtractSupers` |
| 8 | JEFATURA | 154 | 2.3% | Mesmo padrão — Mando se aparecer em níveis de hierarquia |
| 21 | ADMINISTRATIVO | 153 | 2.2% | Cai no else → "Analista" ⚠️ semanticamente questionável |
| 22 | SUPERVISOR DE ESTRUCTURA | 38 | 0.6% | Cai no else → "Analista" ⚠️ é supervisor |
| 9 | GERENTE | 35 | 0.5% | Mando se aparecer em níveis; else senão |
| 10/23/20 | DIRECTOR / DIRECTOR N/2 / Expertos | 6 | 0.1% | — |

**Observação semântica (não conclusão):**

O `.NET` MX particiona `SalesRepresentative` em 2 buckets via `== 2`: Rac (id=2) e Analista (qualquer outro). Na CO, isso joga ~197 empleados em "Analista" que semanticamente não são analistas (ADMINISTRATIVO, SUPERVISOR DE ESTRUCTURA, Expertos, etc.).

**Pra confirmar com Atento CO:**
- Os ~197 empleados em categorias minoritárias (ADMINISTRATIVO, SUPERVISOR DE ESTRUCTURA, etc.) devem cair no bucket "Analista" no 4Shark, ou requerem classificação diferente?
- A regra `id=2 = RAC, resto = Analista` é aceitável pra CO ou precisa refinamento?

#### `AsesorArea` matching exato no `GetMandoCodigoFromArea` (linhas 943-956)

```csharp
private int? GetMandoCodigoFromArea(Jerarquia super)
{
    if (super.AsesorArea.Equals(super.DireccionPais)) return super.DirectorPaisCodigo;
    if (super.AsesorArea.Equals(super.Direccion))     return super.DirectorCodigo;
    if (super.AsesorArea.Equals(super.Gerencia))      return super.GerenteCodigo;
    if (super.AsesorArea.Equals(super.Jefatura))      return super.JefeCodigo;
    if (super.AsesorArea.Equals(super.Nivel4))        return super.ResponsableNivel4Codigo;
    // ... Nivel5..9
    return null;
}
```

`.Equals()` é case + espaço sensível. **Pra CO funcionar**: o SP CO precisa retornar `AsesorArea` **EXATAMENTE** igual a um dos campos `DireccionPais`/`Direccion`/`Gerencia`/`Jefatura`/`Nivel4..9` da mesma row. A view `vw_jerarquia_simplex_total2` da CO tem nomes em UPPERCASE (`JEFATURA`, `GERENCIA`, `DIRECCION`, `DIRECCION_PAIS`) — possível mismatch silencioso de case. Validar no momento de montar o SP CO.

#### Sobre `sp_reporte_cesados_4shark`

Grep em todos os `.cs` confirma: **a versão atual do código não chama esse SP** (`sp_reporte_cesados` ausente em `*.cs`). Cesados são deduzidos por delta no `Load()`:

```csharp
// Services/_4SharkService.cs:448
var cesados = this.fskUsersByCarnet.Values
    .Where(u => IsEnabled(u) && !carnetsActuales.Contains(u.ExternalId))
    .ToList();
```

**Histórico git confirmado** (`git log -S 'sp_reporte_cesados'` em `*.cs`):

| Commit | Ação |
|---|---|
| `bc5dfa4` / `d22cbe4` — "carga cesados" (#152011) | Adicionou o uso do SP no `.cs` (método `LoadCesadosRango` + `AddCesados`) |
| `4f198b2` — "refactor: drop SQLite snapshot, unify Load, and clean up dead code" (Phase 11) | **Removeu** o uso completamente |

O `4f198b2` deletou `LoadCesadosRango` (que chamava `EXEC sp_reporte_cesados_4shark @empresa_codigo, @dias_antiguedad`) e `AddCesados`, substituindo por dedução por delta entre `fskUsersByCarnet` e `carnetsActuales`.

**Implicação prática pra Colômbia:** **não precisamos criar `sp_reporte_cesados_4shark` no source CO.** Reduz o escopo de coisas a entregar no `DB_PERSONAL01` da Colômbia — só precisaremos do `sp_reporte_jeraquia_4shark` equivalente. A lógica de cesados roda inteiramente no `.NET`, comparando carnets do 4Shark com carnets do source.

**Nota lateral:** o arquivo `sql/sp_reporte_cesados_4shark.sql` continua no repo como código morto — candidato pra remoção em PR de limpeza posterior, mas não é prioridade.

### Email enviado a Atento Colombia (2026-05-21)

Email enviado em **2026-05-21** em resposta à thread existente "Integraciones 4Shark Colombia" (`19d9686e28942116`), com o documento de validação anexado em PDF (`Validacion_Atento_Colombia_20260521.pdf`, gerado a partir do markdown em `~/Downloads/Validacion_Atento_Colombia_20260521.md`).

**Destinatários nominais no corpo do email:** Gabriel Adames, Pedro Cardenas, Juan Diego Rubio. Jéssica Camacho mencionada como apoio para coordenação da reunião. Restante da thread mantido em cópia.

**Mensagem-chave:** solicitação de **reunião ainda hoje** para resolver as 6 dúvidas em conjunto, com tom de urgência (não opcional).

**Os 6 pontos enviados pra Atento CO validar:**
1. Identificador único do empleado (Empleado_Codigo vs Empleado_Dni + classificação dos 105 outliers)
2. Filtros para empleados a integrar (Estado_Codigo=1 + outros filtros equivalentes ao `NOT IN (79, 479)` do MX)
3. Jerarquía organizacional (confirmação da view `vw_jerarquia_simplex_total2` + hipótese sobre níveis NULL + fallback to admin)
4. Classificação Rac/Analista (equivalência a SalesRepresentative + tratamento dos ~197 empleados em categorias minoritárias)
5. RootAdmin (pessoa da operação RH/comisiones de Atento CO)
6. Procedure custom (ponto de contato técnico pra registro)

**Aguardando resposta para destravar:**
- Construção da procedure custom no source CO
- Adaptação dos valores hard-coded MX (state, register_type, city fallback) no `.NET` pra parametrização por país
- Mapeamento de subsidiaria e RootAdmin no `appsettings.json`
