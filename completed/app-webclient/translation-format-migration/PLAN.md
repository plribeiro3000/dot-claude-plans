# PLAN — Frontend translation format migration (monolithic JSON → domain split)

> Single-project: `app-webclient`. Derived from `~/.claude/plans/active/spike/frontend-translation-split/SPIKE.md`.
> Scope is **Problem 1 only**: reshape the translation files. The Atento per-tenant override (Problem 2) is tracked separately and explicitly out of scope here.

## STATUS: COMPLETED — merged in PR #6523 (→ `develop`)

Final layout shipped: **126 `models/<domain>.json` + 7 `ui.json` + 6 `generic.json` per language** (no `pages.json` — no non-model key was page-scoped). The original count was 139 top-level keys (not 138 — initial count was off by one).

What actually happened vs the plan:
- **Classification refined by the engineer's domain review.** The generator first produced 116 models + 7 ui + 16 generic. The engineer flagged 10 of the `generic` keys as real domain models (`acceptment_reason_document`, `commission_creation_batch`/`event`, `commission_report_creation_batch`/`event`, `credit_recovery`, `sale`, `service_sale`, `plan_slice`, `incentivation`); these were moved to `models/`, giving the final 126/7/6. The 6 remaining in `generic.json`: `4s_incentive`, `easy_variable`, `errors`, `loanCampaign`, `message_center`, `validations`.
- **Equivalence proven two ways.** The migration script's `deepMerge`-vs-original gate passed for all three languages; an independent reviewer pass (leaf-level flatten of the *config-referenced* files vs the original from `develop`, a different method) confirmed **0 keys missing, added, or changed and 0 collisions** — 2881 / 2881 / 2882 leaves for pt-BR / en / es.
- **Validated by a full production build** of one project target (`ng build 4shark`) — bundle generated, no duplicate-identifier errors across the 384 generated imports.
- **Generated config is git-ignored + regenerated each build** (Phase 4 sub-decision confirmed via "manda bala"), mirroring `src/environments/.env.ts`.

Sibling work merged the same day (not part of this plan, no separate plan docs): PR #6521 removed the SHA-1 dynamic service-worker cache name; PR #6522 added SwUpdate auto-update on new version.

## Objective

Replace the three monolithic translation files (`src/translations/{pt-BR,en,es}.json`, ~140–150KB / 138 top-level keys) with a per-domain split mirroring the Rails backend layout, **without changing runtime behavior** and without touching the loader/merger/`i18n.service`.

## Locked decisions

| # | Decision | Choice |
|---|---|---|
| Layout | Granularity | **Hybrid** — `models/<domain>.json` (mirrors Rails `config/locales/<lang>/models/`) + grouped `ui.json`, `pages.json`, `generic.json`, per language |
| A | Import mechanism | **Prebuild codegen** — a script generates `translation-files.config.ts` from the file tree (esbuild builder has no `require.context`/`import.meta.glob`) |
| B | Key classification | `{one,other}` key matching a Rails model → `models/<key>.json`; UI chrome → `ui.json`; page copy → `pages.json`; remainder → `generic.json` |
| C | `translations:extract` | Leave as-is for now (single `template.json`, not in the runtime path); revisit later |

## Why this is safe without a frontend test suite

The migration is a pure reshuffle. The correctness gate is an **equivalence assertion**: for each language, `mergeTranslations(...all split files)` must deep-equal the original monolithic `<lang>.json`, key for key. The merged tree is provably identical to today's — no behavioral change is possible if the assertion passes.

(Each top-level key lands in exactly one split file, so merge order is irrelevant for correctness here. Order will only matter in Problem 2, when a tenant overlay is appended last.)

## Execution phases

### Phase 1 — Classification map
- Cross-reference the 138 frontend top-level keys against the Rails `config/locales/pt-BR/models/*.yml` (89 files) to identify the model-shaped keys.
- Produce an explicit **bucket map**: `key → target file`. The ~23 non-`{one,other}` keys get bucketed by hand into `ui`/`pages`/`generic`.
- Output: a mapping file driving Phase 2. Surface any ambiguous keys to the engineer.

### Phase 2 — Split generator (one-off script, not shipped)
- Node script reads each `<lang>.json`, applies the bucket map, writes:
  - `src/translations/<lang>/models/<domain>.json` (one per model-shaped key)
  - `src/translations/<lang>/ui.json`, `pages.json`, `generic.json`
- Run for all three languages. The script lives under `scratchpad`/`/tmp` — it is a migration tool, not application code.

### Phase 3 — Equivalence assertion (the gate)
- For each language: assert `deepMerge({}, ...allSplitFiles) ` deep-equals the original `<lang>.json`.
- Any mismatch → fix the bucket map and re-run Phase 2. Do not proceed until all three languages pass.

### Phase 4 — Config codegen
- Add a prebuild script (Node) that scans `src/translations/<lang>/**/*.json` and generates `src/app/core/translation-files.config.ts` (imports + the `TRANSLATION_FILES` array).
- Wire it into the same prebuild points as the existing generators (`yarn run env`, `analytics:compile`): the `build` script and the `start` script.
- **Sub-decision (proposed default):** mirror the `src/environments/.env.ts` pattern — the generated `translation-files.config.ts` is **git-ignored and regenerated on every build/serve**. Confirm before implementing; the alternative is committing the generated file.

### Phase 5 — Swap & cleanup
- Switch `TRANSLATION_FILES` from the hand-written single-file map to the generated multi-file config.
- Delete the monolithic `src/translations/{pt-BR,en,es}.json`.
- Build + serve; confirm the app renders identically (spot-check a few `| translate` keys across domains).
- Leave `i18n.service.ts`, `multi-file-translate-loader.ts`, `translation-merger.ts` **unchanged**.

### Phase 6 — Changelog + PR
- `CHANGELOG.md` under `[Unreleased]` → `### Changed` — "Frontend translations reorganized" (user-facing wording, no implementation detail).
- One commit, PR to `develop`.

## Risks & mitigations

- **Codegen must run before tsc/serve** — if it doesn't, the config is missing/stale. Mitigation: wire into `build` and `start` prebuild (same as `env`); if git-ignored, document that a fresh checkout must run the prebuild before opening in the IDE.
- **Hundreds of generated static imports** — esbuild handles it; bundle content is unchanged (same JSON). Verify the production build succeeds and bundle size is unchanged (it should be — identical data).
- **File-name collisions / special chars in keys** (e.g. `4shark_incentive`) — define a deterministic key→filename slug in the generator; assert no two keys map to the same file.
- **`ng serve` dev loop** — confirm the codegen runs on `yarn start` (it chains `yarn run env`); add the translation codegen to that chain so dev serve isn't stale.

## Out of scope (Problem 2)

Moving the Atento / `atento-mx` seat-type label overrides off git branches into a per-company backend override. The split here only makes that future override cleaner — a tenant overlay file appended last to `TRANSLATION_FILES[lang]` would deep-merge on top. The override mechanism itself is a separate plan.

## Open items — RESOLVED

1. **Phase 4 sub-decision** → generated config git-ignored + regenerated each build (confirmed).
2. **Classification rule B** → applied, then refined by the engineer's domain review (10 keys moved generic→models; see STATUS).
3. **C (extract)** → deferred, as proposed. `translations:extract` still emits a single `template.json` (not in the runtime path). Revisit if/when the team wants per-domain extract templates.

## No tracked follow-ups

By the engineer's call: the goal of this work was to **split** the translations, not to standardize them. The 6 keys left in `generic.json` stay as-is; any future refinement happens incrementally and does not need to live in a plan.

Problem 2 (per-tenant override off the `atento`/`atento-mx` branches) is intentionally **not** carried as a follow-up — it is large enough to warrant its own dedicated plan when prioritized. The research that seeds it lives at `~/.claude/plans/completed/spike/i18n-unification-rails-angular/SPIKE.md`.

Manual validation will happen on **beta** (auto-deploys after merge to `develop`).
