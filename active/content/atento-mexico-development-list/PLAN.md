# Plan: Atento — Lista Consolidada de Desenvolvimentos (Entregue + Roadmap)

## Overview

**Topic:** atento-mexico-development-list
**Type:** Client-facing content deliverable (XLSX; presentation version later if needed)
**Status:** 🟡 Plan written — pending extraction/curation

## Context

Atento México is a politically sensitive account. Stefani (Global Systems, covers Atento LATAM), responding to our utilization/access email, asked for a macro project view — milestones, phases, what's done vs pending, a timeline — plus a chart-labels fix and a list of findings/recommendations.

The engineer's strategic intent for THIS deliverable: build a **deliberately large** list of everything the 4Shark platform has delivered since Atento joined, so the conversation shifts from "estimates and delivery timelines" toward "look how much has already been delivered". The message to Stefani is reassurance: **we never stopped delivering improvements** the entire time they have been a client. The fact that Atento was ~3 months late on payment during this period is context for us only — **it must NOT appear anywhere in the deliverable.**

This plan covers ONLY the consolidated development list. Two follow-ups are explicitly deferred: (a) how to respond to Stefani's email, (b) the chart-labels fix on the corporate report. They are out of scope here.

## Objective

Produce a consolidated **development list (XLSX)** with two parts:
1. **Delivered** — everything the platform shipped since the Atento relationship began (~2024), curated and grouped into client-presentable product themes.
2. **Roadmap (pending)** — the remaining Atento development items, with phase/estimate, deduplicated across sources.

The engineer will review and cut items case by case. Volume is a feature, not a bug — the goal is breadth.

## Scope

### In scope
- Sweep + curate the "delivered" history from `app` and `app-webclient` changelogs, 2024 → present.
- Consolidate the "pending" roadmap from the México SOW + the Atento slice of the "Pedidos Clientes" spreadsheet, deduplicated.
- Group delivered work into product themes (not a raw changelog dump).
- Spanish for client-facing text (Mexican audience).
- Output as XLSX in `~/Downloads/`.

### Out of scope
- How to respond to Stefani's email (deferred).
- Chart-labels fix on the corporate utilization report (deferred, separate quick task).
- The "findings / recommendations / puntos de atención" Stefani requested (deferred with the email-response decision).
- Presentation (PPTX) version — only if judged necessary after the XLSX exists.
- Any reference to payment status / delay.
- Non-Atento clients from the spreadsheet (Ecom, Maqnelson, Commcenter, Barigui, Óticas Carol, Luiz Hohl, etc.).

## Sources

### Delivered (the "we already did a lot" list)
Anchor: Atento relationship since ~2024 (Atento Brasil contract; Atento México onboarded ~early 2025). The changelogs are multi-tenant (platform-wide), so everything from 2024 onward is framed as **platform evolution available to Atento** — not Atento-exclusive development.

| Source | Coverage | Approx. raw entries |
|---|---|---|
| `app/changelogs/2024.md` | 2024 | 518 |
| `app/changelogs/2025.md` | 2025 | 766 |
| `app/CHANGELOG.md` | 2026 (from 3.3.0, 2026-01) | 273 |
| `app-webclient/CHANGELOG.md` | 2019→present (filter 2024+) | ~half of 2,331 |

Raw total in window ≈ **2,500–3,000 bullets**. The work is curation/grouping, not discovery.

### Roadmap (the "what's pending" list)
- `~/.claude/plans/active/spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` — Phase 1 (immediate fixes), Phase 2 (platform improvements, with hours: 2.1 Access Control 70h, 2.2 Bulk employee update 25h, 2.3 History export 35h, 2.4 Extra columns 50h, 2.5 Bulk Group import 40h, 2.6 Bulk Plan import 160h, 2.7 Validation Rules 120h), Phase 3 (3.1 Field encryption 80h, 3.2 Sábana 160h), Training.
- "Pedidos Clientes" tab (Google Sheet) — Atento slice only:
  - Atento MX / Almaviva / Luiz Hohl — Criação de grupo em massa via upload (P1, 6d) — **dup of SOW 2.5**
  - Almaviva / México — Desativar usuários em massa via upload (P1, 3d) — **in dev now (Emerson)**
  - Atento BR — Desativação de usuários, popup p/ retirar de grupos (P3, 4d)
  - Atento BR — Auditoria de usuários, incluir CPF — ✅ done (integration resolves it)

**Dedup rule:** the same feature appears in both sources (bulk Group import, bulk user deactivation). Merge into one roadmap row, keeping the SOW estimate as the canonical hour figure.

## Method

### Phase 1 — Extract & curate the "delivered" list
- [ ] Read each changelog file in the window (`app` 2024.md, 2025.md, 2026 CHANGELOG.md; `app-webclient` CHANGELOG filtered 2024+).
- [ ] Classify each entry: **client-relevant feature** vs **noise** (infra, refactor, internal bugfix, dependency bump, CI). Noise is dropped — it does not impress a client.
- [ ] Normalize each kept entry into a short, benefit-oriented phrase (not the raw commit-style line).
- [ ] Group into ~10–15 **product themes**. Working set (to refine during extraction): Integração automática (Simplex/folha), Controle de acessos & histórico, Auditorias, Cargas em massa (usuários/grupos/planos), Dashboards & visualizações, Relatórios & exportações, Regras & incentivos, Metas, Declarações & assinatura, Transações & cálculo, Simulador, Plataforma & usabilidade.
- [ ] Translate the kept entries to Spanish.
- [ ] Tag each with the period (year) for an optional timeline view.

### Phase 2 — Consolidate the "pending" roadmap
- [ ] Pull SOW-v2 items (phase, hours).
- [ ] Pull Atento slice from the spreadsheet.
- [ ] Dedup against the SOW (bulk group import, bulk user deactivation).
- [ ] Mark current state (done / in dev / pending) and keep the SOW estimate as canonical.

### Phase 3 — Build the XLSX
- [ ] Write to `~/Downloads/`.
- [ ] Sheet **Entregado**: `Tema | Funcionalidad | Descripción (ES) | Período`.
- [ ] Sheet **Roadmap**: `Ítem | Descripción (ES) | Fase | Estimativa | Estado | Prioridad`.
- [ ] Sheet **Resumen**: counts (nº de entregas, nº de temas, nº de itens em roadmap) — the "look how much" headline.
- [ ] Internal columns (changelog ref / repo) kept on a hidden/working tab only — not shown to the client.

### Phase 4 — Engineer review
- [ ] Engineer cuts items case by case.
- [ ] Decide whether a presentation (PPTX) version is needed.

## Strategic framing (baked into the deliverable)
- Tone: reassurance — "nunca paramos de entregar mejoras".
- "Delivered" framed as value Atento received continuously.
- Multi-tenant features framed as "evolución de la plataforma disponible para ustedes" — never overclaimed as Atento-exclusive.
- **No mention of payment status / delay, anywhere.**

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Raw volume (2,500–3,000 bullets) overwhelms / reads as noise | High — defeats the purpose | Curate into themes; drop infra/refactor/bugfix; benefit-oriented phrasing |
| Multi-tenant attribution — these are not Atento-exclusive | Medium — credibility if challenged | Frame as "platform evolution available to you", never "built only for you" |
| Translation quality (ES) for a Mexican audience | Medium | Pass client-facing text through Santi (native) before delivery, per the team norm |
| Dedup misses (same feature in SOW + spreadsheet) | Low | Explicit dedup rule; SOW estimate canonical |

## Open items / deferred
1. Email response to Stefani — deferred (decide after this list exists).
2. Chart-labels fix on the corporate report — deferred, separate quick task.
3. "Findings / recommendations / puntos de atención" (her item 3) — deferred with the email-response decision; must be framed as Atento-side actions (adoption, Simplex corrections), not 4Shark pendencies.

## Changelog
- **2026-06-18** — Plan created. Sources locked (app changelogs 2024–2026 + app-webclient CHANGELOG; SOW-v2; Atento slice of Pedidos Clientes). Anchor: Atento relationship since ~2024. Deliverable: XLSX, delivered + roadmap. Payment-delay context excluded by instruction.
