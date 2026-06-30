# SPIKE — Frontend translation format migration (monolithic JSON → domain split)

> Scope: **Problem 1 only** — migrate the `app-webclient` monolithic translation JSON into a per-domain split mirroring the Rails backend layout. The per-tenant override (Atento branches) is **Problem 2**, tracked separately. This spike deliberately keeps the existing compile-time-bundled architecture (no runtime HTTP loading) so it does not pre-empt Problem 2.

## Question

How do we migrate the three monolithic translation files (`src/translations/{pt-BR,en,es}.json`, ~140–150KB / 138 top-level keys each) into a per-domain split mirroring `config/locales/<lang>/` in the Rails backend (`app`), without changing runtime behavior and without a heavy loader rewrite?

## Current state (verified)

- **Translations**: 3 monolithic JSON files, one per language (`pt-BR`, `en`, `es`), 138 top-level keys each, nested, Rails-like (`one`/`other`, `errors.*`).
- **Loader foundation already exists and is under-used:**
  - `src/app/core/translation-files.config.ts` — `TRANSLATION_FILES: Record<string, any[]>` maps each language to an **array** of imported JSON objects. Today each array has exactly one file.
  - `src/app/core/multi-file-translate-loader.ts` — `loadTranslations(lang)` returns the single file, or `mergeTranslations(...files)` when there are several.
  - `src/app/core/translation-merger.ts` — `deepMerge` where **later sources win** (override layering), starting from `{}` (no mutation of inputs).
  - `src/app/core/i18n.service.ts` — constructor calls `setTranslation(lang, loadTranslations(lang))` for the three languages. Compile-time bundled, no HTTP.
- **Key finding:** the multi-file + deep-merge machinery is the foundation of the ~1-year-old plan. Migrating the format is mostly **splitting the JSON into N files and populating the `TRANSLATION_FILES[lang]` array** — the loader, merger, and `i18n.service` do not change.
- **Builder**: `@angular-devkit/build-angular:application` (Angular 19, esbuild). `resolveJsonModule: true`, `allowSyntheticDefaultImports: true`. Consequence: **no `require.context` (webpack) and no `import.meta.glob` (Vite)** — static JSON imports are the supported path.
- **Extract**: `yarn translations:extract` (`@biesbjerg/ngx-translate-extract`) writes a single `src/translations/template.json` (`--format=json --clean --sort`). No `template.json` exists in the tree today (never committed / git-ignored). Extract is a key-discovery aid, not part of the runtime.

## Target layout (engineer-chosen: Hybrid)

```
src/translations/pt-BR/
  models/
    acceptment.json
    company.json
    ...        (one file per domain, mirroring Rails config/locales/<lang>/models/)
  ui.json       (frontend-only chrome: buttons, nav, placeholders, hints, pagination)
  pages.json
  generic.json
(replicated under en/ and es/)
```

Rationale: the Rails backend splits `pt-BR/models/` into **89 files** (one per model). Mirroring that for the ~115 frontend keys that carry `one`/`other` (the model-shaped keys) gives backend parity where it matters; the remaining frontend-only keys (UI chrome, pages, generic) are grouped into a few files instead of one-per-key.

## Open decision A — how the many files get imported (esbuild constraint)

The hybrid layout produces **dozens of `models/` files × 3 languages** (potentially ~115 × 3). The current `translation-files.config.ts` lists static imports by hand; that does not scale to hundreds of entries.

| Option | How | Pros | Cons |
|---|---|---|---|
| **A1 — Manual static imports** | Hand-list every `import x from './pt-BR/models/x.json'` in `translation-files.config.ts` | Explicit, type-safe, tree-shakeable, zero build step | Hundreds of lines to write and maintain by hand; every new domain file needs a manual edit; merge-conflict-prone |
| **A2 — Codegen at prebuild** | A Node script scans `src/translations/<lang>/**/*.json` and generates `translation-files.config.ts` (all imports + the array). Runs in the `build`/`env` prebuild chain (precedent: `yarn run env`, `analytics:compile` already run there) | Config is generated, not maintained; adding a domain file is automatic; stays compile-time bundled (no architecture change) | Adds a generated file + a build step; generated config must be git-tracked or generated on every build |

(Runtime HTTP loading — `TranslateHttpLoader` — would remove the import problem entirely but changes the compile-time-bundled architecture and overlaps Problem 2; **out of scope here**.)

## Open decision B — key classification criterion (which keys go to `models/` vs `ui`/`pages`/`generic`)

Need an explicit rule for splitting the 138 top-level keys. Candidate rule: a key whose value is `{ one, other }` and whose name matches a Rails model (cross-reference `config/locales/<lang>/models/*.yml`) → `models/<key>.json`; keys that are UI chrome → `ui.json`; page-scoped copy → `pages.json`; everything else → `generic.json`. The exact buckets for the ~23 non-`one`/`other` keys need a pass.

## Migration strategy (behavior-neutral, testable)

1. **Generator script** (one-off, not shipped): read each monolithic `<lang>.json`, classify each top-level key per the rule in Decision B, write the split files under `src/translations/<lang>/`.
2. **Equivalence assertion**: `mergeTranslations(...all split files for a lang)` must deep-equal the original monolithic `<lang>.json`, key for key, for all three languages. This is the correctness gate — the migration is a pure reshuffle; the merged result is byte-for-byte the same translation tree.
3. **Populate `TRANSLATION_FILES`** (manually per A1, or via the generated config per A2) with the split files in a defined order.
4. **Delete the monolithic files** once the assertion passes and the app renders identically.
5. Keep `i18n.service.ts`, `multi-file-translate-loader.ts`, `translation-merger.ts` **unchanged**.

The equivalence assertion (step 2) is what makes this safe to ship without a frontend test suite: the merged tree is provably identical to today's.

## Open decision C — `translations:extract` handling

`translations:extract` outputs one `template.json`. After the split, decide: (a) leave it as-is (single template, still a discovery aid), or (b) reconfigure extract to emit per-domain templates matching the new layout. Low urgency — extract is not in the runtime path.

## What this spike does NOT cover (Problem 2)

- Moving the Atento/atento-mx seat-type label overrides off git branches into a per-company backend override. The split here only makes the eventual override cleaner (a tenant overlay file appended to `TRANSLATION_FILES[lang]` would deep-merge on top) — but the override mechanism itself is Problem 2.

## Decisions needed from the engineer before PLAN

1. **Decision A** — Manual static imports (A1) or prebuild codegen (A2)? (Hybrid scale points to A2.)
2. **Decision B** — Confirm the key-classification rule and the buckets for the ~23 non-`one`/`other` keys.
3. **Decision C** — Reconfigure `translations:extract` now, or defer.
