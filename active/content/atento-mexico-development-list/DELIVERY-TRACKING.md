# Atento México — Delivery and Client-Notification Tracking

## Overview

**Topic:** atento-mexico-development-list (companion to `PLAN.md`)
**Type:** Internal tracking record
**Status:** 🟢 Current as of 2026-07-28

## Purpose

Atento México submitted a list of 9 development requests. Three separate facts about each item have been drifting apart: whether the code is written, whether it reached production, and whether the client was told. This document holds all three in one table so the next client email is composed from the record instead of from memory.

An earlier session answered "which items can we announce?" from keyword guesses against a single repository and got two items wrong in opposite directions — declaring a shipped item missing and a missing item shipped. This document exists so that question is never answered that way again.

## Sources of truth

| Source | What it settles |
|---|---|
| `../../spike/atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` | The canonical definition and numbering of each item (sections 2 and 3), with hour estimates |
| `app/CHANGELOG.md`, `app/changelogs/*.md` | Whether the backend shipped, and in which version |
| `app-webclient/CHANGELOG.md` | Whether the frontend shipped, and in which version |
| Sent mail to the client contact | Whether the client was notified, and on which date |
| Recorded call with the backend engineer, 2026-07-28 | Independent confirmation of delivered vs pending, plus known partial deliveries |

**Two repositories, always.** Several of these items are frontend-only (listing columns, filters). Checking only `app` produces false negatives — that is exactly how item 5 was first misread.

## Status table

| # | Item | SOW | Code | Production | Client notified |
|---|---|---|---|---|---|
| 1 | Desactivación masiva de usuarios vía carga | — | Done | Yes | Yes — 2026-07-08 |
| 2 | Importación masiva de grupos | 2.5 · 40h | Done | Yes | Yes — 2026-07-17 |
| 3 | Actualización masiva de colaboradores vía carga | 2.2 · 25h | Started, not finished | No | No |
| 4 | Exportación del historial del colaborador | 2.3 · 35h | Done (partial — see notes) | Yes | Yes — 2026-07-17 |
| 5 | Información adicional en listados de Parciales y Compensaciones | 2.4 · 50h | Done | Yes | Yes — 2026-07-28 |
| 6 | Reglas de validación de indicadores | 2.7 · 120h | Not started | No | No |
| 7 | Cifrado de campos adicionales del colaborador | 3.1 · 80h | Not started | No | No |
| 8 | Reporte consolidado por calendario (Sábana) | 3.2 · 160h | Not started | No | No |
| 9 | Filtros de mes en la auditoría de declaración de reglas | — | Done | Yes | No — **held back deliberately** |

**Totals:** 5 delivered, 4 pending. Of the 5 delivered, 4 announced and 1 held back for a later message.

### Outside the numbered list

Work reaches the client that the original nine requests never named. It still needs the same three-column treatment, because the client sees it in the product regardless of whether they asked for it.

| Item | Backend | Frontend | Production | Client notified |
|---|---|---|---|---|
| Upload error report download (spreadsheet) | Done — `3.59.0` | Done — `1.281.0` | Yes | Yes — 2026-07-28 |
| Newest-first plan listing order | Done — `3.59.0` | Done — `1.281.0` | Yes | No |

**The upload error report download is complete on both sides and live.** The `app` repository carries the models (`app/app/models/document_error_report_download.rb`, `document_error_report_attachment.rb`), shipped in `3.59.0` and deployed to all four environments on 2026-07-28. The `app-webclient` side is commit `8baf48ac9` *"feat(document-error): add error report download to document-show pages"* — a download service plus a control on 18 document-show pages, with translations in Spanish, English and Portuguese. It shipped in release `1.281.0` (PR https://github.com/4shark/app-webclient/pull/6643, tagged and back-merged on 2026-07-28).

## Client communications

Three messages have gone to the client, each announcing what had shipped since the previous one. The recipient list is the same across all three: Luis Bravo as the primary contact, with the Atento program leads and the 4Shark account team copied.

| Date | Announced |
|---|---|
| 2026-07-08 | Item 1 (bulk user deactivation), plus the bulk hierarchy change that was not on the numbered list |
| 2026-07-17 | Item 2 (bulk group import), item 4 (employee history export) |
| 2026-07-28 | Upload error report download, item 5 (additional information on the Parciales and Compensaciones listings) |

**Item 9 is held back on purpose — it is delivered, not forgotten.** The month filter on the rule-declaration audit is live in production and stays available for a later message. Keeping the July 28 message at two items was an editorial choice, not a statement about item 9's status: a short list of two substantial items lands better than three, and the error report download was the timely one because its interface only reached production that day. Whoever writes the next email should start from item 9, since it is now the oldest delivered-but-unannounced item on the list.

**What each message did not say.** None of the three named a navigation path except the July 8 one, which pointed at the "Acciones en Lote" button in the Usuarios menu. The two later messages describe the functionality without saying where to click, because in both cases the feature surfaces on a screen the user is already on. The one time a path mattered and was given, the client still could not see the option until they re-authenticated — so a path in the text is not a substitute for confirming the frontend actually reached them.

## Delivery evidence

Each entry below cites the changelog line that proves the delivery. A claim without one of these is not a delivery.

**Item 1 — Bulk user deactivation.** `app` `[3.40.1] - 2026-06-18` *"Bulk user deactivation by spreadsheet"* and `[3.41.0] - 2026-06-22` *"Bulk user activation by spreadsheet"*; `app-webclient` `[1.272.0] - 2026-06-25` *"Bulk user activation and deactivation by spreadsheet"*.

**Item 2 — Bulk group import.** `app` `[3.45.0] - 2026-06-30` *"Bulk group creation"*; `app-webclient` `[1.274.0] - 2026-06-30` *"Bulk group creation"*.

**Item 4 — Employee history export.** `app` `[3.48.0] - 2026-07-07` *"User history Excel export"*, extended by `[3.49.0]` (regeneration and retention); `app-webclient` `[1.277.0] - 2026-07-07` *"User history Excel download"*.

**Item 5 — Additional information on listings.** `app-webclient` `[1.280.0] - 2026-07-10` *"Group and collaborator count columns in commission and partial commission listings"*.

**Item 9 — Month filter on the rule-declaration audit.** The product's "rule declaration" is `plan_statement` in the code, and its sibling "result declaration" is `statement` — searching the code for "rules" finds nothing, which is why this item was initially misread as unbuilt. `app` `[3.42.0] - 2026-06-23` added *"Month filter for plan statement audits"*, `[3.43.0]` removed it, and `[3.45.0] - 2026-06-30` replaced it with *"Plan statement audit time window filter"*; `app-webclient` `[1.272.0] - 2026-06-25` carries *"Month and year selection for plan statement audit generation"*. The result-declaration sibling received the same treatment in `app` `[3.48.0]`.

## Notes on the pending items

**Item 3 (bulk employee update)** is the closest to done and is the agreed next priority. Code was started but not finished; the upload processor today only creates records (`app/app/workers/user_document/processor.rb:42-64` builds `User.new` per row and saves — there is no lookup-and-update path). Finishing it completes the upload family alongside items 1 and 2.

**Item 4 is a partial delivery, not a complete one.** The export ships, but two structurally complex fields were left out and need further analysis. The client has already been told the feature is available, so any follow-up needs to add the missing fields without re-announcing the whole feature.

**Item 7 (field encryption) gates item 8 (Sábana).** The extra employee fields carry sensitive data — the monthly salary is the driving case — and must be encrypted at rest before the consolidated report can carry them. Encryption today covers other columns (`app/app/models/user.rb:250` encrypts the unique register id; `payroll_integration.rb` and `authenticator_configuration.rb` encrypt credentials) but not the extra-field values. A related piece already exists: a snapshot of the extra fields is captured at commission-calculation time so declarations keep an immutable history.

**Items 6 and 8 are the two largest** (120h and 160h) and are deliberately deferred while the upload family is completed.

## Do not confuse the Sábana with the statement exportation

The `statement_portable` / "portable exportation" family shipped across releases 3.54–3.58 and looks like the Sábana from the commit volume. It is not. It renders each employee's declaration to **PDF** by opening the page in headless Chromium and printing it (`app/app/workers/statement_portable_batch/consumer.rb:21-28` — `Ferrum::Browser.new`, `browser.go_to(...)`, `browser.pdf(path:)`). The Sábana is a consolidated **table** — one row per employee, columns for employee data, extra fields, indicators, and results per payment type, across all plans. Different deliverable entirely.

## Verify the interface before announcing anything — and fetch before you verify

A feature is announceable only when the client can actually reach it. Backend shipped is not the same as usable, and the two repositories move independently, so confirm the frontend side in `app-webclient` and not only the backend in `app`.

The cost of skipping the check is on record: the 2026-07-17 email announced the bulk group import, the client replied that week that the option was not visible in their menu, and it took a support exchange plus a forced re-login to resolve.

**The check itself has a failure mode, and it fired here.** A local checkout can be many commits behind its remote, and grepping it returns a confident, wrong "this does not exist". That is what happened on 2026-07-28: the working tree was 24 commits behind `origin/develop`, and the search concluded the upload error report download had no interface when the commit adding it across 18 pages was already on the remote. Always `git fetch` and search against `origin/develop` — never trust a working tree whose sync state you have not just confirmed.

## Next actions

1. **Watch for a "we cannot see it" reply** — the two previous announcements each had a lag between the message and the client actually reaching the feature. If it comes, the first thing to check is whether their browser session predates the frontend release.
2. **Open the next email with item 9** — the month filter on the rule-declaration audit, delivered and in production, deliberately kept out of the July 28 message.
3. **Finish item 3** as the next development priority.

## Maintenance

Update this document whenever an item's code, production, or notification status changes. The table is the record the next client email is composed from — if it drifts, the email drifts with it.

## Changelog

- **2026-07-28** — Created. Status of all 9 items reconciled against the SOW, both repository changelogs, sent mail, and the engineer call of the same date. Items 5 and 9 identified as delivered but never announced.
- **2026-07-28 (later)** — Release `3.59.0` deployed to all four environments. Added the section for work outside the numbered list, and the rule to verify the frontend before announcing.
- **2026-07-28 (corrected)** — The frontend claim in the entry above was wrong: it was made by grepping a working tree 24 commits behind its remote. The upload error report download interface exists (`8baf48ac9`, 18 document-show pages, three languages) and ships in `app-webclient` release `1.281.0`. Extended the verification rule to require fetching before searching.
- **2026-07-28 (email scope set)** — `app-webclient` `1.281.0` tagged and back-merged, so the upload error report download is live on both sides. The next email carries two items: that download and item 5. Item 9 is held back for the following message — delivered and in production, kept out of this one to keep the list short.
- **2026-07-28 (announced)** — Third client message sent, carrying the upload error report download and item 5. Both marked notified. Four of the five delivered items are now announced; item 9 is the only delivered-but-unannounced one left and opens the next message.
