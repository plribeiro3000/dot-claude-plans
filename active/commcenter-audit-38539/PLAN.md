# Commcenter Audit 38539 — Hierarchy, subsidiary and groupification fixes

## Customer fixed references

**App-side**:
- `Company.find(2077)` — Commcenter
- Stack: `app-shared-001` (multi-tenant)
- Active subsidiaries: **14 (primary)** and **3** (cross-subsidiary management is enabled by design)
- Locale: `pt-BR`
- Subsidiaries module: enabled (UserIdentifier requires subsidiary_id)

**Integrator-side**:
- ECS stack: `integrator-commcenter-cluster` in `sa-east-1`, tags `Project=integrator, Client=commcenter, Environment=production`
- Services: `integrator-commcenter-web-service`, `-worker-service`, `-runner-service`
- Log groups: `/ecs/integrator-commcenter-{web,worker,runner}`
- **Production branch: master** (not develop)
- Normalized base: MSSQL with 840 users at the time of audit 38539
- `fsk_users` schema: `id, email, city, unique_register_id, register_type, department, external_id, first_name, last_name, parent_id, type, state, subsidiary_id, anonymized, created_at, updated_at`

**Key personas in the org chart**:
- Samuel Quaresma Martins (1026061, Admin, sub 14) — used as temporary parent for relocations awaiting customer decision
- Andresa Montezori (1119694, Admin, sub 14)
- Joel Geraldo Junior (1026079, Manager, sub 14 after subsidiary migration on 2026-05-08) — only Manager in scope; cross-subsidiary management used during audit
- Ricardo Morais (1119695, Manager, sub 14)
- Coordinators in sub 14: Loandra (1026105), Flavia (1119700), Alex (1119697)

**Integrator API surface (master branch)**:
- `Database.with_connection { |adapter| adapter.fetch(:users, conditions) }` — singleton with pool, prefix applied by the adapter via `ApplicationConfiguration.table_prefix`
- The `develop` branch uses `Source.normalized.first.connect!` with `source.table_prefix` — do not use against production

## /integration-debug working conventions (consolidated)

1. **Validation BEFORE bulk execution** — for any execution covering 10+ actions, generate a validation script first (no side effects) that checks: user exists, parent exists, parent_seat is strictly higher than user_seat, current parent ≠ expected parent (same_parent), `last_history.starts_at`. The engineer runs it, reviews the summary, and authorizes execution.
2. **Form date = `last_history.starts_at + 1.day`** (computed dynamically per user) — NEVER `Date.today`. Reason: the customer may request retroactive corrections later; we need a margin between `last_history` and today.
3. **Excel paste separator = `;` (semicolon)** — NEVER `@` (collides with email). Customer-facing spreadsheets: ONLY the 18 columns from `UserAudit::Consumer` (Data Criação through Data Atualização). NEVER include Auditoria, Motivo, Confronto*, Cargo RH, situação RH, Grupo correto, OBS, Admissão RH. The reason for each row goes in a **separate plain-text message**, not in a column.
4. **Scripts for the integrator's `bin/ecs run`** — use `{...}` blocks on a single line. The integrator's IRB enters a wedged state when a multi-line `do...end` breaks. App-shared-001 does not have this problem (Rails runner), so `do...end` is fine there.
5. **Always check the integrator branch before generating a script** — `git -C integrator branch --show-current`. Production runs against master.
6. **`fsk_users` schema**: `first_name`, `last_name` are separate columns (no `name`); `anonymized` (no `active`). Use `LOWER(CONCAT(first_name, ' ', last_name)) LIKE ?` for portable name lookups across MSSQL/Postgres.
7. **VAGO in the audit XLSX = keep current parent** = silent no-op. NOT a customer-facing issue.
8. **Temporary relocation under Samuel Quaresma Martins** is the customer pattern when: (a) the correct manager does not exist, (b) there is a circular dependency (self-reference), (c) the original manager is being demoted and has active subordinates. The customer receives a "Pending Manager" spreadsheet listing those users so they can return the real manager later.
9. **Never resolve users by name** in execution scripts. Discovery by name: ILIKE with 2+ name tokens plus a homonym check. The engineer cross-references visually; execution then uses user_id only.
10. **`SeatDemotionForm.conflicted?`** does NOT filter disabled subordinates — by design, to preserve the hierarchy in case the user is reactivated.
11. **Before generating the first script of a session**, the engineer may ask for a documentation reload. Re-read: CODE-STYLE-RULES, NO-HIDDEN-COMPLEXITY, NO-PREMATURE-DRY, NO-SAFE-NAVIGATION, NO-UNLESS-CONVENTION, ALPHABETICAL-ORDERING, RAILS-CONVENTIONS-CONTEXT, LINTING, COMMAND-SAFETY, OUTPUT-FORMATTING. And the three skill docs: API_DOMAIN, API_PATTERNS, INTEGRATOR_DOMAIN.
12. **Engineer prefers one staged file over many small ones** — generate a single script with stages marked (`=== START STAGE N ===` / `=== END STAGE N ===`). The engineer pastes one stage at a time, validates output, then continues. NOT one file per stage.
13. **Use local snake_case variables, not constants** in console scripts. Constants raise "already initialized constant" warnings on re-run inside the same console session.
14. **`UserIdentifier` lookup must be by the FULL tuple `(value, subsidiary_id)` (or by `user_id` directly)**. Never `find_by(value: ...)` alone — the unique index is `(subsidiary_id, value)`, so the same value can exist in multiple subsidiaries and the bare lookup may pick the wrong record.
15. **`Groupification` lookup and destroy must use `groupification_id` directly**, derived from a prior resolve script that proves the (user_id, value, subsidiary_id, group_id, groupification_id) tuple is unambiguous. Never search by identifier value at destroy time.

## Typical Commcenter audit volume

Audit 38539 (2026-05-08): ~507 users touched across 5 sheets — disable (251), promotion (12), manager fix (137), groupification (101), subsidiary (3).

## Audit 38539 status

| Sheet | Total | Status |
|---|---|---|
| `desativar` | 251 | ✅ done 2026-05-07 |
| `promoçãodespromoção` | 12 | ✅ done 2026-05-08 (17 actions) |
| `correção de gerente imediato` | 137 | ✅ done 2026-05-08 (120 actions, including Jessica reclassified as a promotion + Samuel temp) |
| `subsidiária` | 3 | ✅ done 2026-05-08 (3 primary identifier migrations sub 3 → sub 14) |
| `grupificação` | 101 | ✅ in-app actions done; customer pending items remain (see below) |

Customer audit file: `/Users/plribeiro3000/Downloads/Analise do arquivo Commcenter.xlsx`

## Promotion/demotion sheet — 17 executed actions (2026-05-08)

**Stage 1 — Relocate 10 subordinates under Samuel Quaresma (1026061, Admin)** via `ParentSeatForm`:
Marcia (1243912), Bko Bko (1248713), Carlos (1119778, disabled), Alef (1129003, disabled), Kelly (1128992, disabled), Geovana (1128997, disabled), Aparecida (1243858), Ianca (1243862), Juliana (1243860, disabled), Geiza (1243934, disabled).

**Stage 2 — Free promotions/demotions (4)**:
- Lucimara (1129005) → Supervisor with parent Loandra (1026105)
- Gabriela (1129008) → Supervisor (parent Loandra kept)
- Mayara (1119839) → Supervisor (parent Flavia 1119700 kept)
- Mariana (1243770) → Vendedor with parent Adysson (1119708)

**Stage 3 — Demotions whose subordinates were already relocated**:
- Geovanny (1119891) → Vendedor (parent Andresa 1119694 kept)
- Fabio (1119704) → Vendedor (parent Samuel 1026061 kept)

**Stage 4 — Luiz Felipe (1243772)** → Coordenador with parent Joel Geraldo Junior (1026079, sub 3 — cross-subsidiary by design at the time of execution; Joel later migrated to sub 14)
**Stage 5 — Breno (1119764)** → Supervisor with parent Luiz Felipe
**Stage 6 — Rafael (1128986)** → Vendedor with parent Gabriela
**Stage 7 — Ingrid (1119802)** → `ParentSeatForm` only (Samuel → Flavia 1119700; seat was already Supervisor)

## Manager-fix sheet — 120 executed actions + 17 no-action (2026-05-08)

**Special cases (4) — promoted/relocated under Samuel Quaresma**:
- Claudia Millena (1119930) → `SeatPromotionForm` Vendedor → Supervisor with parent Samuel (XLSX listed self-reference; promotion unblocks her 5 dependents)
- Joao Luis Carnelos (1119696) → `ParentSeatForm` Andresa → Samuel (correct manager Fernando Da Costa Duschitz does NOT exist in the normalized base)
- Alex Lima Lofeu (1119697) → same
- Joel Geraldo Junior (1026079) → same

**Claudia dependents (5)** — `ParentSeatForm` retargeted to Claudia (1119930):
Francisca (1128996), Adriely (1128999), Gabriella (1129007), Maiza (1129015), Keila (1243798)

**Standard ParentSeatForm (110)** — covered by a single bulk run with a name → user_id mapping for 28 known parents.

**Extra promotion (1) — Jessica Aline Dos Santos Silva (1129009)** — `SeatPromotionForm` Vendedor → Supervisor with parent Samuel. Reason: the XLSX correct manager (Lucimara De Souza Lima) was also promoted to Supervisor in this audit, making the parent invalid (same hierarchy level). Treated as the Claudia rule: promotion needed → execute promotion + Samuel temp.

**No-action (17)**:
- 7 overlap with promotion sheet (already handled there): 1129005 (Lucimara), 1119704 (Fabio), 1119764 (Breno), 1243770 (Mariana), 1243772 (Luiz Felipe), 1128986 (Rafael), 1119802 (Ingrid)
- 2 SAME_PARENT (current parent already matches the correct one): Priscilla 1119738, Bruna 1243846
- 8 silent no-op (rule: empty / self-reference / circular correct-manager value, with no promotion needed → silent no-op, NOT raised to the customer):
  - Renato Ferreira 1119709 (self-reference, current seat already correct)
  - Loandra Teixeira Costa 1026105 (empty, current seat already correct — subsidiary change handled in the subsidiary sheet)
  - 6 VAGO with current seat already correct: Diego Fernandes 1119721, Selma Amanda 1119717, Alison Henrique 1119702, Lucas Henrique 1119711, Tamiris Cristine 1119714, Leticia Luana 1119705

## Subsidiary sheet — 3 executed actions (2026-05-08)

The customer XLSX listed 3 users to migrate from subsidiary 3 (VMT_COMMCENTER, internal_id 3788) to subsidiary 14 (TERRA_AXT, internal_id 3954). Strategy: delete + create within a transaction, applied **only to the primary identifier** of each user (secondary `4sk_*` identifiers stayed in sub 3 per the engineer's strict scope decision).

| User | Old primary identifier (sub 3) | New primary identifier (sub 14) |
|---|---|---|
| Loandra Teixeira Costa (1026105) | 633050 / `1926540` (destroyed) | 638723 / `1926540` |
| Udo Dieter Hansen Murback Uematu (1026093) | 633053 / `1926629` (destroyed) | 638724 / `1926629` |
| Joel Geraldo Junior (1026079) | 553337 / `1922319` (destroyed) | 638725 / `1922319` |

Per-user transaction sequence:
1. Open transaction.
2. Build a new `UserIdentifier` in the target subsidiary with `primary: false`.
3. Call `.promote` on the new identifier — zeros every primary on the user, then sets new=primary=true, flipping the old identifier to `primary: false` in the same transaction.
4. Reload old, destroy old (`validate_primary_existence` now passes because `primary: false`).
5. Commit.

Verification: each user ends with 1 primary in sub 14 + 1 secondary `4sk_*` in sub 3, and the original primary identifier id no longer exists.

**Residual risk** (acknowledged): the secondary `4sk_*` identifiers remained in sub 3. On the next integrator run, if the integrator decides the user belongs to sub 14 only, it may recreate `4sk_*` in sub 14, producing a duplicate `4sk_*` value across the two subsidiaries. Monitor; not blocking.

## Groupification work — across 2026-05-08 and 2026-05-09

The audit XLSX listed 101 users to fix; Patrick later expanded the scope by sending a separate XLSX (`auditoria-de-grupos-08052026.xlsx`) containing every groupification of the company (505 entries: 481 active + 24 already-finished) with a `grupo correto` column proposing per-row corrections.

### 2026-05-08 — Wave 1 of the audit XLSX

70 ADD_TO_TARGET (users not in any group yet, only need a `start` in the correct group). All succeeded on a single bulk run.

19 ALREADY_CORRECT_ONLY (already in the right group, no-op).

### Status before Patrick's expansion

| Status | Count | Action |
|---|---|---|
| ADD_TO_TARGET | 70 | ✅ done (Wave 1) |
| ALREADY_CORRECT_ONLY | 19 | ✅ no-op |
| ALREADY_IN_TARGET_PLUS_OTHERS | 3 | pending Patrick decision (finish vs destroy of extras) |
| MIGRATE_FROM_OTHERS | 7 | pending Patrick decision (migrate vs add) |
| MISSING_TARGET_GROUP (TERRA_VendedorII_PAP) | 2 | pending customer decision (create group or change target) |

Customer-facing spreadsheet sent to Patrick: 3 sheets (`Em mais de 1 grupo` / `Migrar ou Adicionar` / `Grupo Inexistente`).

### Patrick's expanded scope

Patrick's XLSX flagged 165 entries to change (everything else marked `0` = no action) — this is broader than the audit's 101. Distribution of the 165:
- 10 → `SEM GRUPO` (just remove the entry)
- 6 → `TERRA_VendedorII_PAP` (group does not exist on the company)
- 1 → `Terra_Vendedor_Afiliado` (case mismatch — app has `TERRA_Vendedor_AFILIADO`)
- 148 → an existing group (destroy current + recreate at correct group)

Patrick's instruction: **wrong-group entries should be destroyed, not finished** (the user got into the group erroneously, not via a real role transition).

### 2026-05-09 — Destroy work (Patrick scope)

**Validation rule**: a `Groupification` cannot be safely destroyed if any `PlanStatement` exists for the user on any plan attached to the group. If the group has zero plans, no statement check is needed.

**Resolve step**: each Patrick entry was resolved against the app to a unique `groupification_id` by joining on `(value, subsidiary_id, user_id, group_id)` — the full tuple — to avoid identifier ambiguity across subsidiaries. Result for the 155 wrong-group + SEM GRUPO entries: 155 OK / 0 ambiguous / 0 not found (every primary identifier was in sub 14).

**Destroy results**:

| Batch | Count | Outcome |
|---|---|---|
| SEM GRUPO destroy | 10 | ✅ all destroyed (0 plans on any of the involved groups) |
| Wrong-group destroy | 153 | ✅ all destroyed (0 plans on any of the involved groups) |
| BLOCKED (`PAP_Supervisor`) | 2 | NOT destroyed — preserved due to active plan_statements |

**Start at correct groups (Patrick scope)**:

After the destroy, the 153 wrong-group entries (minus 6 `TERRA_VendedorII_PAP` that cannot be re-added until the customer creates the group) were re-created at the correct group. Patrick's XLSX listed 147 (user_id, target_group) entries, of which 22 were duplicate pairs (same user listed in multiple destroyed groupifications but all pointing at the same target — one start covers each unique pair).

| Phase | Count | Outcome |
|---|---|---|
| Start at correct groups | 125 unique pairs | ✅ all started with `starts_at = 2026-01-01` |
| Pending start at `TERRA_VendedorII_PAP` | 6 | awaiting customer — group does not exist |
| Pending finish + start for the 2 BLOCKED | 2 | start already done in the 125 batch (Udo at TERRA_Lider_PAP, Loandra at TERRA_Coordenador); the `finish` on PAP_Supervisor is still pending Patrick's confirmation |

### BLOCKED entries (preserved on purpose, must appear in the final report)

Two groupifications were intentionally left intact because their group (`PAP_Supervisor`, group_id 40345, external_id 13) has plans and the user has plan_statements on those plans. Destroying would orphan the statement from the eligibility relationship.

| groupification_id | user_id | user_name | seat | group | blocking plan_ids |
|---|---|---|---|---|---|
| 558487 | 1026093 | Udo Dieter Hansen Murback Uematu | Supervisor | PAP_Supervisor (40345) | 63717, 64402 |
| 558503 | 1026105 | Loandra Teixeira Costa | Coordenador | PAP_Supervisor (40345) | 63717, 64402 |

Patrick's "grupo correto" for these 2: `TERRA_Lider_PAP` (Udo) and `TERRA_Coordenador` (Loandra). The intended next step is `finish` (not destroy) on `PAP_Supervisor` — preserves plan_statement integrity — followed by `start` in the correct group. Awaiting Patrick's confirmation that finish is acceptable for these two cases.

## Customer-facing pending items

### 1. "Aguardando Gestor Imediato" (`commcenter.xlsx`) — 15 users

Temporarily reparented under Samuel Quaresma Martins, awaiting the real manager from the customer:
- 10 originals (subordinates of managers demoted in this audit): Marcia, Bko Bko, Carlos, Alef, Kelly, Geovana, Aparecida, Ianca, Juliana, Geiza
- 4 from the missing Fernando: Claudia, Joao Luis, Alex, Joel — XLSX listed self-reference for Claudia or "Fernando Da Costa Duschitz" who does not exist in the normalized base
- 1 extra: Jessica Aline — XLSX correct manager Lucimara was promoted to the same level

Customer must also register Fernando Da Costa Duschitz in the normalized base if he is to remain the manager of the 4 affected users.

### 2. Groupification (`commcenter-2.xlsx`) — 12 users

Sent to Patrick before he sent his expanded XLSX. Three sheets:
- `Em mais de 1 grupo` (3 users): TARGET + extras — Loandra, Udo Dieter, Kauana
- `Migrar ou Adicionar` (7 users): in a different group than the XLSX target
- `Grupo Inexistente` (2 users): Mayara and Lucas Henrique — `TERRA_VendedorII_PAP` does not exist

### 3. Patrick's expanded scope — pending follow-up

After the destroy of the 153 wrong-group entries (2026-05-09) and the start at the correct groups:
- ✅ 125 unique (user, target_group) pairs started successfully with `starts_at = 2026-01-01` (147 from Patrick - 22 duplicate pairs)
- ⏸️ 6 entries (Patrick's `TERRA_VendedorII_PAP` target) cannot be re-added until the customer creates the group or chooses an existing one
- ✅ 1 entry (Patrick's `Terra_Vendedor_Afiliado` target) — confirmed as a typo; group ID matches existing `TERRA_Vendedor_AFILIADO` (external_id 31). User Alea Eletro Comercial Ltda (1243874) was started there
- ⏸️ 2 BLOCKED PAP_Supervisor entries — `start` at the correct group already done (Udo at TERRA_Lider_PAP, Loandra at TERRA_Coordenador). The `finish` on PAP_Supervisor is still pending Patrick's confirmation (preserves plan_statement integrity)

### Internal-only items (NOT communicated to the customer)

- 8 silent no-op entries from the manager-fix sheet (rule: empty / self-reference / circular correct-manager and current seat already correct)
- The residual `4sk_*` secondary identifiers in sub 3 for Loandra, Udo Dieter and Joel (subsidiary migration's strict-scope side effect)

## Parent lookups completed (29 parents identified)

| XLSX name | user_id | seat | sub |
|---|---|---|---|
| FLAVIA DUTRA CASTANHEIRA DE OLIVEIRA | 1119700 | Coordinator | 14 |
| Luiz Felipe Sonego Bonini | 1243772 | Coordinator (after this audit) | 14 |
| ROBERTA DOS SANTOS CARDOSO DA SILVA | 1119878 | Supervisor | 14 |
| CLAUDIA MILLENA | 1119930 | Supervisor (after this audit) | 14 |
| LOANDRA TEIXEIRA COSTA | 1026105 | Coordinator | 14 (after subsidiary migration on 2026-05-08) |
| Ricardo Morais | 1119695 | Manager | 14 |
| TAMIRIS CRISTINE BARBOSA NANDES | 1119714 | Supervisor | 14 |
| DIEGO FERNANDES BARBOSA | 1119721 | Supervisor | 14 |
| LUCIMARA DE SOUZA LIMA | 1129005 | Supervisor (after this audit) | 14 |
| GRAZIELE ESPINEL D AVILA | 1119707 | Supervisor | 14 |
| BIANCA EZILDINHA LOBO DOS SANTOS | 1119713 | Supervisor | 14 |
| GABRIELA REGINA DE OLIVEIRA | 1129008 | Supervisor (after this audit) | 14 |
| SANDRA MENDES DE MENEZES DE MELO | 1243774 | Supervisor | 14 |
| GUILHERME SANTOS DA SILVA | 1128984 | Supervisor | 14 |
| JOEL GERALDO JUNIOR | 1026079 | Manager (after the audit, parent Samuel) | 14 (after subsidiary migration on 2026-05-08) |
| ANA CAROLINE DA SILVA ZANIBONI | 1119722 | Supervisor | 14 |
| YASMIN DUTRA FERREIRA | 1119701 | Supervisor | 14 |
| BRENO ALISSON LOPES | 1119764 | Supervisor (after this audit) | 14 |
| UDO DIETER HANSEN MURBACK UEMATU | 1026093 | Supervisor | 14 (after subsidiary migration on 2026-05-08) |
| ADYSSON GOMES MARTINS | 1119708 | Supervisor | 14 |
| DENISE SILVA DE MENEZES | 1128990 | Supervisor | 14 |
| LUCAS HENRIQUE DA SILVA | 1119711 | Supervisor | 14 (NOT the "Sales" 1243786) |
| JAQUELINE BEATRIZ CARDOSO GOMES | 1119712 | Supervisor | 14 |
| SELMA AMANDA QUIRINO | 1119717 | Supervisor | 14 |
| INGRID DIANA CAMPOS DA SILVA MAUCH | 1119802 | Supervisor | 14 |
| RUTI DOS SANTOS SILVA | 1128988 | Supervisor | 14 |
| Andresa Montezori | 1119694 | Admin | 14 |
| AMANDA VICTOR GONCALVES | 1248167 | Supervisor | 14 |
| Samuel Quaresma Martins (temporary Admin parent) | 1026061 | Admin | 14 |
| **FERNANDO DA COSTA DUSCHITZ** | **DOES NOT EXIST** in the normalized base (840 users) — confirmed against the integrator commcenter master branch via `LOWER(CONCAT(first_name, ' ', last_name)) LIKE '%fernando%duschitz%'` = 0 hits |

## Established execution conventions

- **Multi-tenant**: every query goes through `company.<association>` with `Company.find(2077)` hardcoded.
- **`ParentSeatForm` / `SeatPromotionForm` / `SeatDemotionForm`** accept `user_id`, `parent_id` (= the parent user's id), `type`, `date`.
- **Form `date`**: `last_history.starts_at + 1.day` computed dynamically — leaves room for retroactive corrections later.
- **Cross-subsidiary management** (parent in a different subsidiary): works naturally through the forms — the `external_parent_subsidiary_id` attribute is only used by the integrator's API surface, not the console.
- **`SeatDemotionForm.conflicted?`** does NOT filter disabled subordinates — by design, to preserve the hierarchy if the user is reactivated.
- **VAGO in the XLSX = keep the current parent** — no action.
- **Mandatory pre-validation**: before any bulk execution, run a validation script that checks `correct_parent` (parent strictly higher), `same_parent`, `last_history.starts_at`, and the existence of user/parent.
- **`Groupification` destroy validation**: starting from `Groupification.find_by(id:)`, take `group.plans.pluck(:id)`; if empty → safe; otherwise verify `PlanStatement.where(plan_id: plan_ids, user_id: groupification.user_id)` is empty before destroying. Never look up by `user_identifier.value` alone — always use the resolved `groupification_id` from a prior tuple-based resolve step.

## Output-for-paste conventions

- **`bin/ecs run app-shared-001`** accepts multi-line `do...end` blocks without issue.
- **`bin/ecs run commcenter` (integrator)** is interactive IRB — use single-line `{...}` blocks to avoid wedging on paste.
- **Excel paste**: separator `;` (semicolon) — `@` collides with email addresses.
- **Customer-facing spreadsheets**: ONLY the 18 columns from `UserAudit::Consumer` (Data Criação through Data Atualização). Do NOT include `Auditoria`, `Motivo`, or any RH/derived column. The reason goes in a **separate plain-text message**, not in a column.
- **Integrator stack**: run against **master**, not develop — on master use `Database.with_connection { |adapter| adapter.fetch(:users, conditions) }` (singleton with pool, prefix applied by the adapter via `ApplicationConfiguration.table_prefix`).

## Per-user state for the manager-fix sheet (137 total)

- **7 overlap with promotion sheet** (already handled there): 1129005, 1119704, 1119764, 1243770, 1243772, 1128986, 1119802
- **4 special cases** (Claudia + 3 missing-Fernando dependents): 1119930, 1119696, 1119697, 1026079
- **5 Claudia dependents**: 1128996, 1128999, 1129007, 1129015, 1243798
- **1 extra promotion** (Jessica): 1129009
- **110 standard ParentSeatForm**: covered by the bulk run with the 28-parent name → user_id mapping
- **2 SAME_PARENT** (current parent already correct, no action): 1119738 (Priscilla), 1243846 (Bruna)
- **8 silent no-op** (empty / self-reference / circular correct-manager and current seat already correct): 1119709 (Renato), 1026105 (Loandra), 1119721, 1119717, 1119702, 1119711, 1119714, 1119705
