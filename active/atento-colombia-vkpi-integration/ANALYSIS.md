# ANALYSIS — Atento Colombia VKPI integration: state, commitments, and guardrails

**Date:** 2026-07-30
**Status:** Awaiting Atento's deliverables + Andrés's summary email (committed for ~30-jul, realistic gate early next week). **No development starts until that email arrives.** This document is the single reference for the workstream: a cold session should be able to read it top to bottom, understand everything discussed, and — when Atento's response lands — check it against the guardrails in §5 and the checklist in §6 to help compose our reply.

**Sources:** requirements document 4Shark sent Atento (via Santiago, 28-jul); Granola meeting "Integraciones Atento Prime (4Shark) Colombia" (29-jul, verbatim transcript). Quotes below are verbatim from that transcript.

---

## 1. Scope — what this integration actually is

From the VKPI base (`COLBOGSQL58\MSSQL58_KPI`) we consume **one table**, `tb_dim_indicadores_score`: the apurado value per person, per indicator, per period. Each row becomes an `Indicator` on the 4Shark platform via `POST /api/v3/indicators`, through the integrator's **Modifier** stream (payload `{compiled_at, user_id, value, variable}`).

Everything else about the person — identity, role, manager, the whole org hierarchy — already reaches the platform through the **Simplex** integration, which is live. The VKPI catalog table (`tb_dim_indicadores`) is Atento's internal reference for registering Variables; we do not consume it. The mapa-operacional and programa tables we do not consume.

Colombia's integrator already exists (stack `co`, base `CO_4Shark_DB`, **root mode** → `/api/v3/indicators`, no subsidiary scope). The work is: add a second **non-normalized Source** pointing at the VKPI server + a **Modifier** stream. `NR_RE` is confirmed as the identifier that resolves to the user (see §5-G-Identity).

---

## 2. Point-by-point — what we asked vs. what Atento committed (29-jul)

| # | Our request | Atento's answer | Owner | Date | Status |
|---|---|---|---|---|---|
| 1 | Creation + update date columns | Agreed. Building an internal process capturing creation + modification date. | Andrés | 30-jul midday (slowest item, may slip) | ✅ Committed |
| 2 | Fix `DT_DATA` day/month swap → ISO | Accepted: text `año-mes-día` (= ISO 8601 hyphenated, our recommendation). No objection. | Andrés | with the base | ✅ Resolved |
| 3 | Which column is the indicator value | **Not closed.** Depends on level (§3.1). Andrés to send **two options** for operation type (sum vs. division). | Andrés | 30-jul | ⚠️ Pending |
| 4 | `NR_RE` = Simplex `Empleado_Codigo` | Confirmed, kept until the Simplex implementation. Reviewing to configure. | Andrés | by 30-jul | ✅ Confirmed |
| 5 | Primary key | **Pending.** Proposed (06-jul): `indicador + unidad de servicio + supervisor`. On 29-jul: will unify monthly, define next day. | Andrés | 30-jul | ⚠️ Pending (§3.3) |
| 6 | Metas in a separate table | Confirmed: independent table (different update cadence). Fields `nombre indicador + programa + meta`, differentiated by unidad de servicio; naming `KPI_<ID>_<unidad>`. Metas de ForChart today **not reaching** the KPI process — Andrés to investigate. | Andrés | same-day (29-jul) | ⚠️ Partial |

Two 4Shark-side commitments from the meeting:

- **Santiago:** email Simplex requesting the **table of `unidad de servicio` IDs** (the column/table where the service-unit identifiers live). No date. Blocks metas and, later, groups/groupifications.
- **4Shark:** deliver a **roadmap** (phases, owners, estimates). Estimates the week after 29-jul.
- **Andrés:** send a **summary email** with all points and statuses (Santiago requested explicitly). This is our trigger.

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

It participates in the primary key (§3.3), differentiates metas (same indicator → different meta per unidad, so the metas table "sería grandísima"), and its ID table must be requested from Simplex (Santiago's email). On our side it most likely maps to an existing 4Shark concept (Group / Subsidiary / a Variable dimension) — the mapping is decided when metas scope is confirmed. Not yet in the Modifier payload.

### 3.3 Atento's proposed primary key diverges from the grain we consume

Our provisional script (`script-indicadores-score-PROVISIONAL.sql`) built the unique index + MERGE join on `(NR_EMPRESA, NR_RE, NR_INDICADOR, DT_DATA)` — the key we derived empirically (355 rows = 355 distinct combos). Atento's proposal is `indicador + unidad de servicio + supervisor`, unified monthly — a **different grain** (per-supervisor + unidad, not per-person). When Andrés defines the real key (30-jul), the script's index and MERGE `ON` must be re-aligned or the MERGE misbehaves. **The script is PROVISIONAL until the key is confirmed.**

---

## 4. What is blocked vs. what we can prepare now

**Blocked until Atento delivers:**
- Modifier `value` mapping — blocked by §3.1 (the two options).
- The unique index / MERGE key in our script — blocked by §3.3 (real PK).
- Metas scope + `unidad de servicio` mapping — blocked by item 6.

**Can prepare now, no blocker:**
- The `create_or_update` (MERGE) pattern is settled (mirrors integrator `create_modifier`); only the key columns are provisional.
- The integrator plumbing is known (stack `co`, root mode, `NR_RE` resolves).
- Santiago's Simplex email (unidad-de-servicio IDs) can go out now.
- The roadmap (phases/owners/estimates) — this document is its input.

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

## 6. Checklist to run against Andrés's summary email (Monday)

When the response arrives, verify each — this is the concrete gate before we reply:

1. **Dates (item 1):** both columns present? `datetime`, not text? Does `DT_ACTUALIZACION` move only on real change? (G4)
2. **Value (item 3):** do the two options each define, per `NR_INDICADOR`, exactly which value we consume (numerador / denominador / division), as a **final per-row value**? Does either option ask us to accumulate across levels? If yes → reject on G1/G2, ask for pre-accumulated supervisor rows.
3. **Supervisor accumulation (§3.1):** explicitly confirm Atento computes it on their side (Option A). If their email assumes 4Shark does it, push back with G1.
4. **Primary key (item 5):** is the key defined at the grain we read (per person / per indicator / per period)? Re-align the provisional script's unique index + MERGE `ON` to it. (§3.3)
5. **`NR_RE` (item 4):** confirmed in writing = Simplex `Empleado_Codigo`, and it is the value loaded in the indicator table (not an internal KPI code)?
6. **`DT_DATA` (item 2):** delivered as `año-mes-día`, and the historical inversion corrected (not only new rows)?
7. **Metas (item 6):** separate table, own date columns (G4/G5), fields incl. unidad de servicio ID; and confirm whether metas are in THIS phase or later. Is the internal "metas de ForChart not reaching KPIs" problem resolved on their side?
8. **Variables (G3):** nothing in their response implies 4Shark auto-creates Variables from the catalog.
9. **unidad de servicio:** did Santiago's Simplex email go out / get answered? The ID table is a dependency for metas.

---

## 7. Adjacent workstream — NOT part of this VKPI integration (do not conflate)

The 29-jul call also covered a separate, larger platform feature Santiago presented: **variables auxiliares / nested incentives** — letting one incentive's *result* feed another incentive's formula (e.g. a limitador reading a `resultado_TMO` produced by an indicator norm), via a new output-variable type computed inside the platform during commission calc, without creating incentive-to-incentive dependencies. This is **Fase 2 (variables)** of the broader Atento Prime Colombia roadmap; **Fase 3 is groups/groupifications**. It is a platform capability for all Atento clients (and beyond), still at sketch stage (no effort estimate yet), and is **out of scope for the VKPI base integration** this document covers. Noted so the two are not confused when the roadmap lands.

---

## 8. Timing note

Engineer's recollection was "maybe next Monday". The meeting record is tighter: most items committed for **Wed 30-jul** (date columns possibly slipping), metas answer same-day (29-jul). The real gate for us is **Andrés's summary email** consolidating statuses. Plan on early next week; the individual commitments were for 30-jul.
