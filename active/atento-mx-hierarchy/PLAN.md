# PLAN — atento-mx hierarchy reconciliation (app-atento-001, company 1318)

Source of truth: normalized base (`fsk_users`: `type` + `parent_id`). Production app is flat
(almost everyone SalesRepresentative under a few Admins). Goal: rebuild the real org tree in the app.

## Mechanism (verified on `origin/master`)

Seat changes go through three forms — never hand-rolled `seat.update`:

- `SeatPromotionForm` — promote up. Sets **type AND parent in one call**. `parent_id` = manager's **user_id**.
  Guard `parent_valid?`: parent must already be at a **strictly higher** level (`Seat::TYPES[0...index(type)].include?(parent.type)`).
- `ParentSeatForm` — change manager only (same level). For "level OK, manager wrong".
- `SeatDemotionForm` — demote down. Guard `conflicted?`: cannot demote to ≤ the highest subordinate's level.

All take `seat.lock!` and require `date > last history.starts_at` (no backdating). Attributes:
`user_id`, `type`, `parent_id` (manager user_id), `date`, `company_id`, `owner_id`.

`Seat::TYPES` (0 = top): SuperAdmin · Admin · President · VicePresident · Director · Superintendent ·
GeneralManager · Manager · Coordinator · Supervisor · SalesRepresentative.

## Why top-down is mandatory (not just tidy)

`parent_valid?` rejects a promotion whose parent is not already at a higher level. So a VP can only be
promoted after the President exists at President level; a Director only after its VP/President is set; etc.
Process strictly top-down so every user's target parent is already correct when its turn comes.

## Operation classification (from the hierarchy audit, 9384 audited)

| Phase | Operation | Form | Count |
|---|---|---|---|
| 1 | President: SalesRep → President | promotion | 1 |
| 2 | VicePresident → level + parent | promotion | 8 |
| 3 | Director → level + parent | promotion | 43 |
| 4 | Superintendent → level + parent | promotion | 58 |
| 5 | GeneralManager → level + parent | promotion | 53 |
| 6 | Manager → level + parent | promotion | 6 |
| 7 | Supervisor → level + parent | promotion | 286 |
| 8 | SalesRep (level OK, parent wrong) → re-parent | parent update | ~8700 |
| 9 | Wrongly `Admin` (3 should be SalesRep, 1 Director) → demote | demotion | 4 |

- Admin (1, Luis Bravo / ext 47): already correct — no-op, and it is the root every Phase-1+ parent hangs from.
- Coordinator: 0 in normalized base (app has 1 — an anomaly, sits with the 4 in Phase 9 review).
- Promotions (Phases 1-7) set level **and** parent together, so the 455 managers' parents are fixed inline.
- Phase 8 is the bulk (SalesReps keep their level, only the manager changes) — runs after all managers exist.
- Phase 9 LAST: the 4 wrongly-`Admin` can only be demoted once their fake children are re-parented (Phase 8),
  otherwise `conflicted?` blocks (they currently hold high-level subordinates).

## Per-phase 3-script structure (per the keys lesson: reads are local, only the write is server-side)

1. **Validation — LOCAL (from the Phase-1 snapshots).** For each user in the phase: confirm the app user
   exists, current seat, and that the **target parent is already at the correct higher level** (i.e. the prior
   phase landed). Output pass/fail per row. No paste.
2. **Execution — SERVER (engineer pastes into `bin/ecs run app-atento-001`).** Iterate the phase's rows, build
   the form (`SeatPromotionForm`/`ParentSeatForm`/`SeatDemotionForm`), `save`, log each, continue on error.
3. **Check — DRIVEN (me).** Re-audit (re-run the seat/user audit or re-pull) and diff: every row now at the
   right level + parent. Failures loop back into the next run of the same phase.

Input volume per phase ≤ a few hundred (except Phase 8) → inline in the script; Phase 8 goes via S3.

## Hierarchy phase status
- [x] Phase 1 President — DONE (Elia Santillan 1037510 -> President under Luis Bravo 739987)
- [x] Phase 2 VicePresident — DONE (8/8 under President 1037510)
- [x] Phase 3 Director — DONE (43/43; Estefani 345 wrongly-Admin -> Phase 9)
- [x] Phase 4 Superintendent — DONE (58/58)
- [x] Phase 5 GeneralManager — DONE (52/52; Ana Karen 104021 excluded -> escalation)
- [x] Phase 6 Manager — DONE (6/6)
- [x] Phase 7 Supervisor — DONE 283/286; 3 blocked (Ana Karen's reports: 96769, 58284, 16683) -> re-run after Ana Karen resolved
- [x] Phase 8 SalesRep re-parent — DONE 8630/8633; 3 fails were wrongly-Admin -> Phase 9
- [x] Phase 9 wrongly-Admin demotions — DONE 4/4 (Estefani->Director; Roman/Yonatan/Karina->SalesRep). Verified: 0 inversion (3 SalesRep with no subordinates; Estefani/Director with 2 subs below her). Coordinator (1032866, A_151534) = out of scope, not in normalized base, untouched.

## Live verification (after Phases 1-8, before Phase 9)
- 9384 in-scope: 9283 level+manager OK; 0 unexpected divergence. Only pending: Phase 9 (4) + Ana Karen cluster (4 + 93).
- Context: 22164 app users; 12780 out of scope (98% disabled = historical churn), never touched.

## Go-live (full flow) — DONE
- [x] `4sk_<id>` keys created on app: 9384 (bucket A 9378 + Claudia + 5 B) + verified against RDS.
- [x] Manual hierarchy: Phases 1-9 (9283 level+manager OK; live-verified).
- [x] First integration (Job 6a26eefef3641975fa91f388): 291 new (bucket D) + 71419 user fields; 9386 user "ya ha sido tomado" (expected, existing users) + 13 field fails (Kristal). Extract 3m / Transform 40m37s / Load 16m52s.
- [x] Flip `pending -> integrated`: 9384 (final mongo verified: 9675 integrated / 2 pending = Kristal 25965 + Fernando 29169). NOTE: `integration_status` is an Integer field (enumerize pending=1) — query by accessor `integration_status.to_s == 'pending'`, NOT `where(integration_status: 'pending')` (matches 0).
- [x] Email sent to Atento MX local team (Luis Bravo, Joel Acevedo, Aryadna Espinosa, Eduardo Rosales) — reply on thread "Procedimientos para añadir en el Simplex de Producción", Jessica removed (left Atento). Asked for (1) D-1 window and (2) record corrections. Attachment: `atento_mx_escalacion_cliente_20260608.xlsx`.

## Awaiting customer (Atento MX) — blocks closing
- **D-1 window**: the time the day's data is consolidated (daily closing) — to schedule the daily chain (Simplex -> normalized base -> integrator -> partials, in sequence).
- **RFCs (sheet tab "RFC divergentes", 7 cases):**
  - Kristal Gonzalez Gil (ext 185765): RFC belongs to Jose Juan (disabled) -> her correct RFC.
  - Fernando Leon Rodriguez (ext 111111): RFC `4128611810000` invalid (numeric only) -> correct RFC.
  - 5 cases differing by 1+ char (Jorge/Tania/Liliana/Armando/Mayra): which RFC is canonical.
- **Hierarchy (sheet tab "Jerarquía", 1 case):** Ana Karen Acosta Monroy (ext 104021): GM under GM (Cecilia 10703) -> customer decides to demote Ana Karen or promote Cecilia.

## After customer reply (re-run)
- Kristal + Fernando: once the RFC is fixed in Simplex, the next integration creates them (POST 2xx) and they flip normally.
- Ana Karen cluster: her (104021) + 3 Supervisors (96769/58284/16683) + 93 SalesReps blocked -> re-run promotion/re-parent after her level/manager is decided.

## Internal 4Shark follow-ups (do not block the customer)
- Consolidated session report (Step 4) — deferred at engineer's request.
- EC2 snapshot bug: the 10min waiter times out on slow audits AND the EXIT trap scales the ASG down, killing the in-flight task (memory: `~/.claude/memory/20260608-111845-...`). Fix via PR on dot-claude.
