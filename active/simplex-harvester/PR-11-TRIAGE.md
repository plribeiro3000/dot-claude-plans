---
name: PR #11 Triage
description: Combined review findings for the drop-SQLite PR — self review + Copilot + engineer decisions
type: DISPOSITION
---

# PR #11 Triage — drop SQLite snapshot, batch-load per user against 4Shark

PR: https://github.com/4shark/simplex-harvester/pull/11
Branch: `feature/drop-sqlite-cache`
Engineer: Paulo
Status: open, under triage on 2026-05-13

## Self-review findings (engineer-confirmed status)

| # | Issue | Engineer decision | Action |
|---|---|---|---|
| 1 | Comment at lines 23–26 (header of caches) claims "comparison passes never hit the SQL Server" — false, LoadUpdates does per-user query | **Fix** | Rewrite comment to describe persistent caches + per-user batch model |
| 2 | Comment "Snapshot of the pre-existing enabled population" at line 219 is confusing — "snapshot" suggests durable state | **Fix** | Reword to "Carnets already enabled in 4Shark at this point — used to route users into the create flow vs the update flow" |
| 3 | `carnetsAtuais` mixes pt/es | **Fix** → `carnetsActuales` | Rename |
| 4 | `LoadDayli` body has >80 lines inline, could extract `ClassifyJerarquiasByState` | **Need more context — not enough info to validate without seeing it laid out** | Defer / present concretely if revisited |
| 5 | Multiline LINQ formatting at lines 226–229 hard to read | **Fix** | Reformat |
| 6 | `LoadCesados` parameter name `cesadosFskUsers` is verbose | **Fix** → `cesados` | Rename parameter |
| 7 | Comment in LoadUpdates (lines 1211–1215) still mentions `fskFieldCache` (removed) | **Fix** | Rewrite to mention per-user batch load |
| 8 | `userFields` dict passed by reference, mutable across UpdateX calls | Engineer can't opine without more context | Defer |
| 9 | `userFields` filters to `Type == "create" \|\| Type == "update"`, excludes "delete" — does that match the integrator's API semantics? | **Investigate directly in the integrator code / APIs** | Verify against Ruby integrator's `create_user_field`/`delete_user_field` SPs |
| 10 | Index `fsk_user_fields(user_id)` (PR #2193) is the keystone for per-user query performance | **Fix** | Add reference comment near the batch-load query |

## Copilot review findings

| # | Path | Line | Comment | Action |
|---|---|---|---|---|
| C1 | `Services/_4SharkService.cs` | 26 | Header comment "comparison passes never hit SQL Server beyond initial bulk-load" is wrong now | **Same as self-review #1** — fix |
| C2 | `Services/_4SharkService.cs` | 184 | `BuildFskUserCache` materialises with tracked EF entities — consider `AsNoTracking()` + column projection to reduce change-tracker overhead | **Valid — apply `.AsNoTracking()` on both queries** |
| C3 | `Services/_4SharkService.cs` | 225 | `carnetsAtuais` mixes Portuguese with Spanish/English naming | **Same as self-review #3** — rename to `carnetsActuales` |
| C4 | `Services/_4SharkService.cs` | 940 | `LoadCesados` lost the `company.Key` segment from its error log — multi-company runs harder to diagnose | **Valid — restore `company.Key` in the log** |
| C5 | `Services/_4SharkService.cs` | 218 | `ExtractMandos/Supers/Racs/Analistas` only reset their HashSet when `lista.Count > 0`. If `newcomersOrReactivations` is empty in a company iteration, stale role sets from a previous company persist and `LoadNuevos` would process the wrong codes (latent multi-company bug). [Copilot second pass, comment 3235676245] | **Latent — Atento MX runs 1 company only, doesn't fire. Follow-up.** |
| C6 | `Services/_4SharkService.cs` | 198 | `cesados` is computed from `fskUserCache.Values` (every enabled user in 4Shark) minus `carnetsActuales` (current company only). In a multi-company run, company B would `disable_user` users belonging to company A. Needs per-company scoping (e.g., filter via RootAdmin hierarchy). [Copilot second pass, comment 3235676340] | **Latent — Atento MX runs 1 company only, doesn't fire. Follow-up. Same family as fresh-review achado #5.** |

## Engineer additional ask — unify LoadInitial and LoadDayli

**Rationale**: today the two flows do nearly the same thing once the cache exists. On first run, the cache is empty and every Simplex row becomes a newcomer — which is exactly what `LoadInitial` already does. Maintaining two flows means every fix has to be made twice.

**Plan**: validate that a single unified flow can handle both cases:
- First-run behaviour: empty `fskUserCache` → `preExistingEnabledCarnets` is empty → everyone is `newcomersOrReactivations` → `LoadNuevos` does the full create. No cesados (nothing to disable). No updates (no pre-existing users).
- Daily behaviour: populated cache → mix of newcomers, cesados, updates.

If validated, drop `LoadInitial` (and the `--type 0` switch case rerouted to `LoadDayli`).

## Status as of 2026-05-13 after force-push

All confirmed fixes were applied in commit `b11fe9b` on `feature/drop-sqlite-cache`:

- Header comment + line 219 "Snapshot" comment rewritten (self #1, #2; Copilot C1)
- `carnetsAtuais` → `carnetsActuales` (self #3; Copilot C3)
- LINQ formatting (self #5)
- `LoadCesados` parameter renamed `cesadosFskUsers` → `cesados` (self #6) and `company.Key` restored in the error log (Copilot C4)
- LoadUpdates comment rewritten — no more references to the removed `fskFieldCache`; mentions the per-user batch + the supporting index (self #7, #10)
- `.AsNoTracking()` applied to all three read-only queries in `BuildFskUserCache` and to the per-user `userFields` query inside `LoadUpdates` (Copilot C2)
- Issue #9 (delete-state) confirmed in `Integrador-4Shark-MSSQL-Prefixo-3.0-p1.sql:977` — `delete_user_field` is `INSERT type='delete'` (append-only). The filter `Type IN ('create','update')` was wrong because a deleted field would look indistinguishable from a never-set one. The query now pulls the latest row per (user_id, key) regardless of type; `UpdateUserField` / `RealizarCambio` rely on `existencia = fsk.Type.Equals("create")` to decide whether the field currently exists. **Bug fixed.**

`LoadInitial` and `LoadDayli` unified into a single `Load()` entrypoint:
- `I4SharkService` now exposes only `Load()`.
- `_4SharkService` removes `LoadInitial`; the surviving method (formerly `LoadDayli`) renamed to `Load`.
- `Program.cs` removes the `--type` switch and the `INITIAL` / `DAYLI` constants; the executable runs the single flow regardless of what the Windows scheduler passes.

Deferred items:
- Self-review #4 (extract a `ClassifyJerarquiasByState` helper inside Load) — engineer asked for richer context before deciding; left as-is for now.
- Self-review #8 (`userFields` mutability) — no concrete need yet; left as-is.

## Implementation order (after context compaction)

1. **Apply confirmed fixes from triage** (issues 1, 2, 3, 5, 6, 7, 10 + Copilot C2, C4):
   - Rewrite the two stale comments (header at line 23, "Snapshot" at line 219).
   - Rename `carnetsAtuais` → `carnetsActuales`.
   - Reformat multiline LINQ (lines 226–229).
   - Rename `cesadosFskUsers` → `cesados` in `LoadCesados` parameter.
   - Rewrite LoadUpdates comment (no `fskFieldCache`, mention per-user batch + the supporting index).
   - Add `.AsNoTracking()` on both queries in `BuildFskUserCache` and on the per-user query in `LoadUpdates`.
   - Restore `company.Key` in the `LoadCesados` error log.

2. **Investigate issue #9 — delete-state semantics in `fsk_user_fields`**:
   - Read the integrator Ruby code (`~/Projects/4Shark/integrator/`) for `create_user_field`/`delete_user_field` SPs or service-layer methods.
   - Confirm whether a field with last row "delete" should be treated as absent (current code: yes — filter excludes "delete") or whether the value should be reused.
   - Document the finding in this file and leave the filter as-is or change it accordingly.

3. **Evaluate unifying LoadInitial and LoadDayli**:
   - Walk through both flows step by step and confirm the unified flow does the right thing for an empty 4Shark.
   - Code experiment: route both `--type 0` and `--type 1` through `LoadDayli`; LoadInitial becomes obsolete.
   - Verify build, then decide whether to ship the unification in this PR or defer to a follow-up.

4. **Apply force-with-lease push** on `feature/drop-sqlite-cache`.

5. **Update PLAN.md Phase 11** with the final design choice (unified flow vs not) and the Copilot triage results.

## Quick-reference: what is in this PR

- Persistent in-memory caches: `fskUserCache` (FskUser, ~5 MB for 10k users) + `lastActivityByUserId` (~100 KB)
- Per-user batch load inside `LoadUpdates`: 1 SELECT per user against `fsk_user_fields`, fed into `Dictionary<string, FskUserField>` discarded between iterations
- Removed: `_jerarquias`, `cesados` (field), `ultima_nueva`, `nueva_ultima`, `SaveLoad`, `RecoveryLastLoad`, `ExtractDiferences`, `LoadCesadosRango`, `AddCesados`, all 10 `CheckChange*`, `GetEnabledUser` (DB-direct, unused)
- Config removed: `ConnectionString` (SQLite), `DiasAntiguedadCesados`
- Build: 0 errors. Memory linear in user count.
