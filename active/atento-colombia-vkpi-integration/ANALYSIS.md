# ANALYSIS — Atento Colombia VKPI integration: state, commitments, and guardrails

**Date:** 2026-07-31
**Status:** Atento's proposal has arrived — Andrés sent `Maqueta.csv` (30-jul, 60,924 data rows, 22 columns) with two written notes: the primary key is `NR_CHAVE_EMPRESA_MES_RE` (`..._SOPORTE` if Simplex changes), and the metas template is still pending. It answers part of §6 and leaves four blockers open (§9). **No development starts until those four close.** In parallel, Atento cancelled the 31-jul call and moved the agenda to the following week, awaiting 4Shark's roadmap — the commitment 4Shark made on 29-jul. This document is the single reference for the workstream: a cold session should be able to read it top to bottom and know exactly what is settled, what is open, and what goes back to Atento.

**Read the file itself, never a preview of it.** `Maqueta.csv` is `;`-delimited, UTF-8 with BOM, CRLF-terminated, and 21 MB. A spreadsheet preview renders only the first 200 rows and parses the decimal comma of `RESULTADO` as a thousands separator, so `0,029829545` displays as `29,829,545`. Both distortions invert the conclusions: the collision in §3.3 is invisible in the first 200 rows, and `RESULTADO` looks malformed when it is not. Every figure in this document comes from the full file.

**Sources:** requirements document 4Shark sent Atento (via Santiago, 28-jul); Granola meeting "Integraciones Atento Prime (4Shark) Colombia" (29-jul, verbatim transcript); Andrés's reply on the thread "Integracion de KPIs Colombia | Análisis de la base y puntos para la reunión" (30-jul 18:51, resent 19:07) with `Maqueta.csv`; Estefani's meeting cancellation (31-jul). Quotes below are verbatim from those sources.

---

## 1. Scope — what this integration actually is

From the VKPI base (`COLBOGSQL58\MSSQL58_KPI`) we consume **one table**, `tb_dim_indicadores_score`: the apurado value per person, per indicator, per period. Each row becomes an `Indicator` on the 4Shark platform via `POST /api/v3/indicators`, through the integrator's **Modifier** stream (payload `{compiled_at, user_id, value, variable}`).

Everything else about the person — identity, role, manager, the whole org hierarchy — already reaches the platform through the **Simplex** integration, which is live. The VKPI catalog table (`tb_dim_indicadores`) is Atento's internal reference for registering Variables; we do not consume it. The mapa-operacional and programa tables we do not consume.

Colombia's integrator already exists (stack `co`, base `CO_4Shark_DB`, **root mode** → `/api/v3/indicators`, no subsidiary scope). The work is: add a second **non-normalized Source** pointing at the VKPI server + a **Modifier** stream. `NR_RE` is confirmed as the identifier that resolves to the user (see §5-G-Identity).

---

## 2. Point-by-point — what we asked vs. what Atento committed (29-jul)

| # | Our request | Atento's answer | What the 30-jul delivery shows | Status |
|---|---|---|---|---|
| 1 | Creation + update date columns | Agreed. Building an internal process capturing creation + modification date. | `DT_CREACION` and `DT_ACTUALIZACION` are datetime with milliseconds, and each holds exactly **one value across all 60,924 rows** (`2026-07-20 23:44:10.033` and `2026-07-30 23:44:10.033`). They are file-generation stamps, not per-record dates. | ⚠️ Partial (§9-A) |
| 2 | Fix `DT_DATA` day/month swap → ISO | Accepted: text `año-mes-día` (= ISO 8601 hyphenated, our recommendation). | Delivered as compact `yyyymmdd` (`20260501`), always day 01, plus an `AñoMes` column (`2026-05`). Unambiguous, so the day/month inversion cannot recur — but it is not the agreed shape, and historical correction is unstated. | ⚠️ Partial (§9-B) |
| 3 | Which column is the indicator value | Two options promised for operation type (sum vs. division). | The two options were not sent. The file carries a single `RESULTADO` per row and no calc-type column — the shape of Option A, unconfirmed in writing. The unit behind that value is ambiguous (§9-E). | ⚠️ Partial (§9-C) |
| 4 | `NR_RE` = Simplex `Empleado_Codigo` | Confirmed, kept until the Simplex implementation. | 3,535 distinct `NR_RE` and 3,535 distinct `Cedula`, none empty — an exact 1:1. The `..._SOPORTE` key over `Cedula` is a working switch plan. | ✅ Confirmed |
| 5 | Primary key | `NR_CHAVE_EMPRESA_MES_RE`; `NR_CHAVE_EMPRESA_MES_RE_SOPORTE` after the Simplex change. | Composed of `DT_DATA + NR_RE + NR_SERVIVIO_CODIGO`, verified on every row. It excludes the indicator, so **6,415 of its 6,547 distinct values (98.0%) repeat**. | ❌ Reject (§3.3, §9-D) |
| 6 | Metas in a separate table | Confirmed: independent table (different update cadence). Fields `nombre indicador + programa + meta`, differentiated by unidad de servicio; naming `KPI_<ID>_<unidad>`. | Andrés, verbatim: *"esta pendiente la definición de la plantilla de metas."* | ❌ Open |

Three commitments from the meeting and where they stand:

- **Santiago:** email Simplex requesting the **table of `unidad de servicio` IDs**. For the indicators table this is no longer a dependency — `NR_SERVIVIO_CODIGO`, `NM_PROGRAMA` and `NM_CLIENTE` arrive inline on every row. It remains a dependency for metas. The email is not visible in Paulo's mailbox; confirm with Santiago whether it went out.
- **4Shark:** deliver a **roadmap** (phases, owners, estimates), estimates the week after 29-jul. Atento is waiting on exactly this: Estefani cancelled the 31-jul call and moved the agenda to the following week *"aguardando por el update por parte del proveedor sobre rodemap, actualización informativa del nuevo desarrollo y resumen de la evolución en las configuraciones"*. The clock started at the 29-jul meeting, not at the maqueta.
- **Andrés:** send the consolidated answer. Delivered 30-jul as `Maqueta.csv` plus two written notes (the key, and metas pending).

---

## 3. The three findings the meeting surfaced that were not in our document

### 3.1 The indicator value splits by level — and WHO computes the supervisor value is OPEN

- **Asesor (agent):** value is a division — `sum(numerador) / sum(denominador)`.
- **Supervisor:** cannot be re-derived from agents' rows; needs an **accumulated** value. Andrés: *"al supervisor sí me le podría afectar porque yo no puedo calcular, ejemplo, nivel de ventas por un promedio, sino por un acumulado"*.

Andrés floated adding a calc-type column so 4Shark applies it (*"¿sumamos una columna adicional en score, que me diga cálculo?"*); we asked for **two options** (*"nos puedes colocar las dos soluciones que tú veas... nosotros respondemos"*). They reduce to:

- **Option A — Atento delivers the supervisor row already accumulated.** No hierarchy walk on our side; we load the value as-is, exactly like an agent's. This is the only acceptable option — see §5-G1. Paulo's stated preference: *"seria mais simples se já tivesse o valor calculado final pra gente"*.
- **Option B — Atento sends a calc-type flag and 4Shark accumulates across the hierarchy.** **Rejected** — §5-G1 explains why. Paulo already flagged the surface blocker in the call: *"se for baseado no cargo... hoje a gente não tem o cargo atual que está vindo do Simplex... Poderia ter algum problema"*.

**Misreading to correct:** the explicit "we will not do this" Paulo said in the call was about **not integrating the Variables** (item 4), NOT the supervisor hierarchy. On the supervisor the call left it open (*"a gente vê de implementar"*). It is therefore NOT yet declined with Atento — we must decline it explicitly in our reply, on the single-source-of-truth ground (§5-G1).

### 3.2 `unidad de servicio` is a new dimension

It participates in the primary key (§3.3), differentiates metas (same indicator → different meta per unidad, so the metas table "sería grandísima"), and on our side it most likely maps to an existing 4Shark concept (Group / Subsidiary / a Variable dimension) — the mapping is decided when metas scope is confirmed. For the **indicators** table the dimension arrives inline: `NR_SERVIVIO_COD` (the column name carries that typo in the source), `NM_PROGRAMA` and `NM_CLIENTE` are on every row, so the ID catalog from Simplex is not a dependency there. For **metas** it still is, and the metas template does not exist yet. Not yet in the Modifier payload.

### 3.3 Atento's proposed primary key excludes the indicator, so it collides at the grain we consume

Our provisional script (`script-indicadores-score-PROVISIONAL.sql`) built the unique index + MERGE join on `(NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA)`. Atento's key is `NR_CHAVE_EMPRESA_MES_RE`, composed as `DT_DATA + NR_RE + NR_SERVIVIO_CODIGO` — month, person, service, and **no indicator**. Each row is person × indicator × month, and a person carries **9.31 indicators per month on average** (maximum 19), so the key repeats for nearly everyone:

```
20260501-128178-2242  → AUSENTISMO
20260501-128178-2242  → TMO           same key, distinct rows
20260501-128178-2242  → Calidad
```

Measured on the full file:

| Metric | Value |
|---|---|
| Data rows | 60,924 |
| Distinct `NR_CHAVE_EMPRESA_MES_RE` | 6,547 |
| Keys appearing more than once | 6,415 (98.0%) |
| Maximum rows under one key | 19 |
| Person-months carrying exactly one indicator | 132 of 6,547 |
| Duplicates of `NR_CHAVE_EMPRESA_MES_RE + NR_ID` | **0** |

The last row is the fix and it is proven, not proposed: adding `NR_ID` makes the key unique across all 60,924 rows. **The script stays PROVISIONAL until the key includes the indicator** — either a `NR_CHAVE_EMPRESA_MES_RE_INDICADOR` column, or written confirmation that we key on the tuple `NR_CHAVE_EMPRESA_MES_RE + NR_ID`.

`NR_SERVIVIO_CODIGO` inside the key is redundant in this data — no person-month appears in more than one service (0 of 6,547), and no person+month+indicator is duplicated across services. Harmless, but ask whether a person can span two services in a month, because that is what would make the segment load-bearing.

---

## 4. What is blocked vs. what we can prepare now

**Blocked until Atento closes the four open points (§9):**
- Modifier `value` mapping — blocked by the `RESULTADO` scale/separator (§9-E) and by the supervisor accumulation (§3.1).
- The unique index / MERGE key in our script — blocked by the key grain (§3.3).
- Metas scope + `unidad de servicio` mapping — blocked by the pending metas template.

**Can prepare now, no blocker:**
- The `create_or_update` (MERGE) pattern is settled (mirrors integrator `create_modifier`); only the key columns are provisional.
- The integrator plumbing is known (stack `co`, root mode, `NR_RE` resolves).
- The column-to-payload mapping for everything except `value`: `NR_RE` → `user_id`, `DT_DATA` → `compiled_at`, `NR_ID`/indicator name → `variable`.
- The roadmap (phases/owners/estimates) — this document is its input, and the phases are expressed as dependencies on the four open points rather than as absolute dates.

---

## 5. GUARDRAILS — the non-negotiables, and why (read this before replying to Atento)

These are the positions we hold regardless of what Atento proposes. Each carries the reason it cannot be traded away, because a reason is what survives a negotiation.

### G1 — The hierarchy has ONE source of truth (Simplex). VKPI must never be a second one. We do NOT resolve hierarchy at integration time; the supervisor value arrives pre-accumulated.

The platform already gets its whole org structure from Simplex: we register each user, their seat (role), and their parent (manager) from the Simplex normalized base. **That is the hierarchy of record.** It is what decides that a given person is a Supervisor with these agents under them.

The VKPI base carries hierarchy-shaped columns too (`NR_SUPERVISOR_RE`, `NR_GESTOR_RE`, `NR_GERENTE_RE`, and the mapa-operacional table). If we computed supervisor indicators by walking VKPI's hierarchy, we would be trusting a **second, independent** hierarchy — and two problems compound:

1. **It is a duplicate authority.** The same fact ("who is X's manager", "what level is X") would now be asserted by two systems maintained by different processes on different cadences. They *will* drift. The moment they drift, we register a person as Manager from Simplex but attribute or roll up their indicator as if they were an operator from VKPI — or aggregate agents onto the wrong supervisor. Every supervisor number becomes silently wrong, and the failure is invisible until someone audits a payroll. This is the textbook two-sources-of-truth integration failure.
2. **The VKPI hierarchy is not even trustworthy.** Our own profiling showed its hierarchy keys truncated by 15-digit float rounding, gestor/superintendente names apparently swapped, and the VP/director levels literally the string `"Null"`. So VKPI is not just a *duplicate* authority — it is a *corrupted* one. There is no reliable hierarchy data there to resolve against, even if we wanted to.

**Therefore:** VKPI delivers values keyed by the person's identifier and nothing about org structure. If a supervisor needs an accumulated value, **Atento computes that accumulation on their side** (where their own hierarchy lives) and delivers it as a plain value against the supervisor's identifier — exactly like an agent's value. We load it; we never derive it. This is Option A in §3.1, and it is the only acceptable option. Option B (4Shark accumulates) is rejected on this ground.

Say this to Atento as the reason, not as a preference: *the hierarchy lives in Simplex; giving VKPI a parallel hierarchy creates two sources of truth for the same fact, which desynchronizes and corrupts every supervisor number — so the accumulated supervisor value must come pre-computed from your side.*

### G2 — We consume ONE final value per (person, indicator, period). No cross-row or cross-level computation on our side.

The Modifier payload carries a single `value`. Whatever the operation type (sum, division, accumulation), it must be resolved **before** the row reaches us. We do not sum numerador/denominador across a set, we do not average, we do not aggregate up a tree. Verify that Andrés's "two options" both deliver a final per-row value and neither asks us to compute across rows. This is the same principle as G1, generalized: computation that needs data we don't own (other rows, the tree) cannot live on our side.

### G3 — Variables are owned by the platform (Héctor's team), not derived from the VKPI catalog. The platform's calc mode is independent from Atento's table.

Already agreed in the call and must not drift back. 4Shark does not read `tb_dim_indicadores` to create Variables; Héctor's team registers them in the platform, where the calc mode (sum/average) lives as a business decision. Paulo, verbatim, on why: *"esse foi até ponto que eu coloquei de não fazer a integração das variáveis, porque isso viraria uma [dependência]... se ele fazendo diretamente só na tabela dos indicadores, a gente não tem essa dependência."* If an indicator arrives whose Variable is not registered, the API rejects it, the reject shows in the integration report, we contact them, and once registered we force the resend. No auto-creation.

### G4 — Incremental sync depends on the two date columns behaving correctly. This is the whole point of item 1.

Verify, when the base arrives: **both** `DT_CREACION` and `DT_ACTUALIZACION` present; proper `datetime` (not text); `DT_ACTUALIZACION` moves **only when a value actually changed** (equal-value re-writes must not touch it). Without that last property, "give me what changed since yesterday" is impossible and we fall back to full-base comparison every day — which does not scale. A creation date alone does not solve this; the update date is the load-bearing one.

### G5 — Metas only via a dedicated table with its OWN date columns. Indicator and meta never share a row.

Confirmed by Atento, must hold. The reason (verbatim territory from the call): indicator and meta change on different cadences, so sharing one row means sharing one pair of dates, and then `DT_ACTUALIZACION` moving cannot tell us which of the two changed — forcing us to reprocess both and risking overwriting a meta nobody touched, on top of variable pay. Two resources, two endpoints (`/indicators` vs `/goals`), two tables, two date pairs. If metas enter scope, apply G4 to the metas table too.

---

## 6. The delivered file — `Maqueta.csv`

21 MB, 60,924 data rows, 22 columns, `;`-delimited, UTF-8 with BOM, CRLF. Accents survive intact (`Londoño`, `retención`). Header, verbatim:

```
AñoMes;DT_DATA;NM_CLIENTE;NR_SERVIVIO_CODIGO;NM_PROGRAMA;NR_RE;Cedula;
NR_CHAVE_EMPRESA_MES_RE;NR_CHAVE_EMPRESA_MES_RE_SOPORTE;NM_FUNCIONARIO;
NM_SUPERVISOR;NM_GERENTE;NM_GESTOR;RESULTADO;NR_ID;NM_INDICADOR_EN_EL_PAIS;
NM_CARGO_DESCRIPCION;NM_EMPLEADO_ACTIVO;HC;HC_Total;DT_CREACION;DT_ACTUALIZACION
```

Both key columns are derived, and the derivation holds on every row with zero mismatches:

```
NR_CHAVE_EMPRESA_MES_RE         = DT_DATA "-" NR_RE  "-" NR_SERVIVIO_CODIGO
NR_CHAVE_EMPRESA_MES_RE_SOPORTE = DT_DATA "-" Cedula "-" NR_SERVIVIO_CODIGO
```

Cardinalities:

| Dimension | Value |
|---|---|
| Data rows | 60,924 |
| Periods | 3 — `2026-05` (30,572), `2026-06` (30,265), `2026-07` (87) |
| People (`NR_RE` = `Cedula`, 1:1, none empty) | 3,535 |
| Person-months | 6,547 — 9.31 indicators each on average, max 19 |
| Indicators (`NR_ID`) | 228, over 224 distinct names |
| End clients | 27 |
| Roles (`NM_CARGO_DESCRIPCION`) | 7, all operational |
| Named supervisors / gestores / gerentes | 229 / 34 / 13 |
| `NM_EMPLEADO_ACTIVO` | `Activo` 59,515 · `Cese` 1,409 |
| `HC` and `HC_Total` | the value `1` on every row |
| Distinct `DT_CREACION` / `DT_ACTUALIZACION` | 1 / 1 |

The file settles three things cleanly: `NR_RE` is the identifier and has a working `Cedula` fallback (item 4); `unidad de servicio` arrives inline for indicators (§3.2); and the indicator names follow the platform's Variable naming with an `NR_ID` alongside — consistent with G3, and nothing in the delivery implies 4Shark should create Variables from the catalog.

**Resolve the Variable by `NR_ID`, never by name.** There are 228 IDs over 224 names, so four names carry two IDs each — `Penalizacion - Variable` (543, 283), `Caso Facturado - Variable` (306, 284), `TMO - Variable` (285, 270), `Efectividad - Variable` (288, 658). The suffix is inconsistent on top of that: `- Variable` (60,015 rows), `-Variable` with no space (224), `-  Variable` with a double space (280), `- Comision` (40), and `Fcr Com` with no suffix at all (365). Name-based matching fails on both axes; `NR_ID` → name is a clean function.

---

## 7. What goes back to Atento

Four points to ask, two to declare. Each carries the reason, because a reason is what survives a negotiation (§5). Every number below is measured on the delivered file, so the asks are demonstrations rather than opinions.

**Ask — these block development:**

1. **Key at the right grain.** The key must include the indicator: a `NR_CHAVE_EMPRESA_MES_RE_INDICADOR` column, or written confirmation that we key on `NR_CHAVE_EMPRESA_MES_RE + NR_ID`. State the measurement — 6,415 of 6,547 key values (98.0%) repeat, up to 19 rows under one key, and adding `NR_ID` yields zero duplicates across all 60,924 rows. (§3.3)
2. **A unit dictionary per indicator.** The format is fine (decimal comma, no thousands separator). The unit is not: several ratio-shaped indicators hold most values in 0–1 and a minority above it — `AUSENTISMO` reaches 73.35, `Productividad` reaches 20,100, `Vacaciones` reaches 20. Ask for unit and expected range per `NR_ID`, and for the five scientific-notation values (`5,99E-05` and siblings) to be fixed at export. This feeds variable pay. (§9-E)
3. **Supervisor value pre-accumulated, confirmed in writing.** That `RESULTADO` is always the final per-row value with no computation on 4Shark's side, and that a supervisor's row arrives already accumulated against the supervisor's own identifier. The file contains **zero supervisor rows** — all 7 role values are operational, and 225 of the 229 named supervisors have no row of their own. Ground it on G1: the hierarchy lives in Simplex; a parallel hierarchy in VKPI creates two sources of truth for the same fact and corrupts every supervisor number. (§3.1)
4. **`DT_ACTUALIZACION` semantics, and a date for the metas template.** That an equal-value rewrite does not touch `DT_ACTUALIZACION` — without it, "give me what changed since yesterday" does not exist. Ask for a sample where the two dates vary per record, since both are a single constant today. And restate the metas template requirements before it is designed: separate table, its own date pair, key carrying `unidad de servicio` *and* the indicator, never a meta and an indicator on the same row (G4/G5).

**Declare — no answer needed, but it must be on the record:**

5. **4Shark ignores `NM_SUPERVISOR`, `NM_GERENTE`, `NM_GESTOR`, `NM_CARGO_DESCRIPCION` and `NM_EMPLEADO_ACTIVO`.** Hierarchy and role continue to come only from Simplex. Those columns carry names with no identifier, so they could not resolve to a user even if we wanted them to. Saying it now prevents a reconciliation argument against those columns three months from now. (G1)
6. **`yyyymmdd` is accepted as the definitive `DT_DATA` format**, in place of the hyphenated shape agreed in the call — it is unambiguous, so the day/month inversion cannot recur. Fix the file contract in the same breath: `;` delimiter, UTF-8, CRLF. Confirm the correction reached the history and not only new rows.

Smaller confirmations to fold in: the date or trigger of the Simplex change that switches the key to `Cedula` (an identifier switch discovered on the day is an emergency migration; announced ahead it is configuration); whether a person can hold rows in two `NR_SERVIVIO_CODIGO` in one month; whether a month in progress is exported partially (`2026-07` carries 87 rows of a single indicator); the meaning of `HC` / `HC_Total`, constant `1` on every row; and the five indicators that are entirely zero across the sample — `RECHAZADOS`, `% Devoluciones`, `Devolucion Casos Escalados`, `CASTIGOS OPERACIONALES`, `CALIDAD EN LA ENTREGA`.

**Two decisions that are 4Shark's, not Atento's.** Whether the platform accepts a negative `Indicator` value — 272 rows are negative, 267 of them NPS, which is legitimate for that metric. And whether we import indicators for people already terminated — 1,409 rows carry `NM_EMPLEADO_ACTIVO = Cese`, which affects commission in the month someone leaves.

---

## 8. Adjacent workstream — NOT part of this VKPI integration (do not conflate)

The 29-jul call also covered a separate, larger platform feature Santiago presented: **variables auxiliares / nested incentives** — letting one incentive's *result* feed another incentive's formula (e.g. a limitador reading a `resultado_TMO` produced by an indicator norm), via a new output-variable type computed inside the platform during commission calc, without creating incentive-to-incentive dependencies. This is **Fase 2 (variables)** of the broader Atento Prime Colombia roadmap; **Fase 3 is groups/groupifications**. It is a platform capability for all Atento clients (and beyond), still at sketch stage (no effort estimate yet), and is **out of scope for the VKPI base integration** this document covers. Noted so the two are not confused when the roadmap lands.

---

## 9. Open blockers, roadmap, and timing

### 9-A `DT_ACTUALIZACION` semantics are unstated

The two date columns exist as datetime with milliseconds, which settles the visible half of item 1. The half that carries incremental loading — the update date moving only on a real value change — is asserted nowhere, and the file cannot demonstrate it: `DT_CREACION` holds `2026-07-20 23:44:10.033` and `DT_ACTUALIZACION` holds `2026-07-30 23:44:10.033` on all 60,924 rows. They are file-generation stamps. Without the per-record property we fall back to a full-base comparison every day, which does not scale (G4).

### 9-B `DT_DATA` format changed unilaterally

The call agreed on hyphenated `año-mes-día`; the file delivers compact `yyyymmdd`, always day 01. The compact form is unambiguous, so the day/month inversion that motivated the request cannot recur — accept it, fix it in writing together with the delimiter/encoding contract, and confirm the correction reached the history rather than only new rows.

### 9-C The two options for the operation type were not sent, and no supervisor row exists

Andrés committed to two options for sum vs. division and for who computes the supervisor value. Neither arrived. The file's shape — one `RESULTADO` per row, no calc-type column — is Option A in form, which is what we want, but it is stated nowhere. And the supervisor case is not merely unconfirmed, it is absent: all seven `NM_CARGO_DESCRIPCION` values are operational (`Rac Telefonico` 55,955 · `Rac Bo` 3,227 · `Rac Aprendiz` 1,217 · `Rac Ventas` 259 · `Rac Experto` 137 · `Analista De Negocios` 109 · `Rac Presencial` 20), and 225 of the 229 named supervisors have no row of their own. Open on G1/G2.

### 9-D The key collides at the row grain

See §3.3 for the measurement. This is the single largest technical blocker, and the fix — appending `NR_ID` — is already verified unique against the delivered data.

### 9-E `RESULTADO` is well formed but its unit is ambiguous

The representation is consistent: 27,869 values are decimals with a comma, 33,050 are plain integers, none carry a thousands separator. What is ambiguous is the unit. Several ratio-shaped indicators hold most values in 0–1 and a minority above it:

| Indicator | Rows | ≤ 1 | > 1 | Maximum |
|---|---|---|---|---|
| `AUSENTISMO - Variable` | 2,369 | 2,113 | 256 | 73.35 |
| `Adherencia - Variable` | 2,615 | 2,407 | 208 | 1.29 |
| `Productividad - Variable` | 548 | 330 | 218 | 20,100 |
| `Satisfaccion - Variable` | 383 | 282 | 101 | 5.00 |
| `Vacaciones - Variable` | 985 | 896 | 89 | 20.00 |
| `FALTAS - Variable` | 1,722 | 1,531 | 191 | — |
| `Tipificacion - Variable` | 682 | 607 | 75 | 1.52 |

Either these are not percentages — and then `0,0298` days of absence makes no sense — or a subset of rows was written in a different unit. Either way one indicator carrying values with two meanings cannot load into a single platform Variable. Five values additionally leak scientific notation (`5,99E-05`, `1,00E-05`, `5,70E-05`, `9,66E-05`), which breaks a naive numeric parser. This column feeds variable pay, so it cannot be integrated on a guess.

### 9-F Hierarchy columns arrive and must be declared out of scope

`NM_SUPERVISOR` (229 names), `NM_GERENTE` (13), `NM_GESTOR` (34), `NM_CARGO_DESCRIPCION` and `NM_EMPLEADO_ACTIVO` ship complete — no empty values — but as names with no identifier, so they cannot resolve to a platform user at all. If either side starts reconciling on them, VKPI becomes the second authority on a fact Simplex already owns, and the two will drift (G1). The mitigation is a written declaration, not a question — §7 item 5.

### 9-G Validation 4Shark owes itself before estimating

The file spans 27 end clients, including offshore campaigns run from Bogotá for Chilean, Mexican and Costa Rican accounts (`Vtr` 10,005 rows, `America Movil` 8,632, `Scotiabank` 5,578, `Banco Bci` 5,286, `Telefonica Colombia` 4,646, `Telefónica Mexico` 4,284, `Cabletica` 2,298, among others). The employees are Colombian, so this is ordinary for a BPO — but the integrator runs on stack `co` in root mode, so every `NR_RE` has to resolve to a user in the Colombia normalized base or the API rejects the row.

Cross the 3,535 distinct `NR_RE` against the CO base before committing to a phase-1 estimate. The size of the gap is a direct input to the roadmap. A related nuance: 65 `NR_RE` appear under more than one spelling of the employee name — harmless, since we consume `NR_RE` and not the name, but it says the name is not stable per RE at the source.

### Roadmap and timing

Atento is waiting on the roadmap, and that is 4Shark's own 29-jul commitment coming due — the clock started at the meeting, not at the maqueta. Estefani cancelled the 31-jul call and moved the agenda to the following week for exactly this.

So the roadmap is delivered, not deferred. What makes it honest is its shape: phases with **dependencies rather than absolute dates**, each phase starting D+n after the four open points in §7 close, and phase 1 additionally gated on the `NR_RE` resolution check in 9-G. That gives Atento the visibility they asked for without committing 4Shark to a delivery date on inputs it does not control.
