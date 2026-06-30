// Codebase snapshot — Angular i18n setup (captured 2026-06-26)
// Source files referenced in SPIKE.md Finding 1

// ── src/app/core/i18n.service.ts (constructor) ────────────────────────────────
// All three locale bundles are embedded at startup via setTranslation.
// No HTTP loader is used — translations are compile-time bundled into the app.

// constructor(private translateService: TranslateService) {
//   translateService.setTranslation('pt-BR', loadTranslations('pt-BR'));
//   translateService.setTranslation('en', loadTranslations('en'));
//   translateService.setTranslation('es', loadTranslations('es'));
// }

// ── src/app/core/translation-files.config.ts ──────────────────────────────────
// Each language maps to one JSON file (or an array for future multi-file).

// import en from '../../translations/en.json';
// import es from '../../translations/es.json';
// import ptBR from '../../translations/pt-BR.json';
//
// export const TRANSLATION_FILES: Record<string, any[]> = {
//   'pt-BR': [ptBR],
//   en: [en],
//   es: [es],
// };

// ── src/app/core/multi-file-translate-loader.ts ───────────────────────────────
// loadTranslations returns a single JSON or deep-merges multiple files.
// mergeTranslations utility already exists in the codebase.

// export function loadTranslations(lang: string): any {
//   const files = TRANSLATION_FILES[lang];
//   if (!files || files.length === 0) {
//     console.warn(`No translation files configured for language: ${lang}`);
//     return {};
//   }
//   if (files.length === 1) return files[0];
//   return mergeTranslations(...files);
// }

// ── src/app/core/translation-merger.ts ───────────────────────────────────────
// Deep merge utility: mergeTranslations(...translations) → plain object.
// Supports override layering; does not mutate originals (starts from {}).

// export function mergeTranslations(...translations: any[]): any {
//   return deepMerge({}, ...translations);
// }

// ── src/environments/environment.ts / environment.prod.ts ────────────────────
// supportedLanguages: ['pt-BR', 'en', 'es']
// defaultLanguage: 'pt-BR'
// No tenant-specific language config in either file.

// ── src/environments/atento/ ──────────────────────────────────────────────────
// Contains: manifest.json, styles/colorVariables.scss, assets/ (icons only)
// No translation files. Atento build overrides branding only; translations
// are identical to the default build.

// ── package.json (i18n-related dependencies) ─────────────────────────────────
// "@ngx-translate/core": "^17.0.0"
// "@biesbjerg/ngx-translate-extract": "^7.0.4"
// No: i18n-js npm package, @angular/localize, ngx-translate-messageformat-compiler

// ── Translation JSON structure (pt-BR.json) ───────────────────────────────────
// ~148KB, 138 top-level keys.
// 115 of 138 keys contain { "one": "...", "other": "..." } sub-keys.
// These are used as STATIC DOMAIN LABELS, not ICU count-based pluralization.
// Example usage in templates: {{ 'company.one' | translate }} → "Empresa"
//
// Sample key (src/translations/pt-BR.json):
//   "acceptment": { "one": "Ciência", "other": "Ciências" }
// Compare backend (config/locales/pt-BR/models/acceptment.yml):
//   one: 'Aceitação'   ← DIVERGENT VALUE
