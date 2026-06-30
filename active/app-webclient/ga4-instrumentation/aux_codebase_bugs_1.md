# Auxiliary — Confirmed Codebase Bugs (ga4-instrumentation)

> Source excerpts from `app-webclient` repo to support PLAN-SPIKE.md Option comparisons.

---

## Bug 1 — `gtag_compiler.js` wrong replacement token

File: `~/Projects/4Shark/app-webclient/gtag_compiler.js`

```js
const fileSystem = require('fs');
fileSystem.readFile('src/gtag.js', 'utf8', function (err, data) {
  let formatted = data.replace(/GTAG_ID/g, process.env.ANALYTICS_ID);
  fileSystem.writeFile('src/gtag.js', formatted, 'utf8', function (err) {
    if (err) return console.log(err);
  });
});
```

The regex `/GTAG_ID/g` looks for the literal string `GTAG_ID` inside `src/gtag.js`.

File: `~/Projects/4Shark/app-webclient/src/gtag.js`

```js
window.onload = function () {
  window.dataLayer = window.dataLayer || [];
  function gtag() {
    dataLayer.push(arguments);
  }
  gtag('js', new Date());
  gtag('config', 'xx-xxxxxxxxx-x');
};
```

`'xx-xxxxxxxxx-x'` is a Universal Analytics placeholder format (`UA-xxxxx-x`).
The string `GTAG_ID` does not appear anywhere in this file — so `replace(/GTAG_ID/g, ...)` replaces nothing.
Result: `ANALYTICS_ID` is never injected into `src/gtag.js`.

---

## Bug 2 — `app.component.ts` wrong dataLayer push API

File: `~/Projects/4Shark/app-webclient/src/app/app.component.ts` (lines 40–48)

```typescript
if (env.ANALYTICS_ID) {
  (window as any).dataLayer = (window as any).dataLayer || [];

  this.router.events.subscribe((event) => {
    if (event instanceof NavigationEnd) {
      (window as any).dataLayer.push('config', env.ANALYTICS_ID, { page_path: event.urlAfterRedirects });
    }
  });
}
```

`dataLayer.push()` accepts a single object argument per the dataLayer contract.
`dataLayer.push('config', env.ANALYTICS_ID, { page_path: ... })` pushes THREE separate primitive arguments onto the array — this is not a valid gtag or dataLayer command format.
The correct form would be: `gtag('config', env.ANALYTICS_ID, { page_path: event.urlAfterRedirects })`.
Result: page_path tracking is silently broken.

---

## Bug 3 — `dist/browser/gtag.js` confirms the broken state was deployed

File: `~/Projects/4Shark/app-webclient/dist/browser/gtag.js`

Identical content to `src/gtag.js` — the last production build deployed `'xx-xxxxxxxxx-x'` as the measurement ID.

---

## Missing feature — No User-ID set anywhere

No `gtag('config', ..., { user_id: ... })` or `gtag('set', { user_id: ... })` exists in the codebase.
Grep confirmed zero matches for `user_id` across the entire `src/` tree.

The user's internal ID is available at: `credentialsService.credentials?.user?.id` (type `string`).
File: `~/Projects/4Shark/app-webclient/src/app/core/authentication/user-credential.model.ts` (line 4): `id: string;`

---

## Missing feature — No consent banner / Consent Mode implementation

Grep for `consent`, `cookie`, `lgpd`, `banner` (excluding product carousel references) returned zero matches.
No CMP, no `gtag('consent', 'default', ...)`, no `gtag('consent', 'update', ...)` exists in the codebase.

---

## What partially works

File: `~/Projects/4Shark/app-webclient/src/main.ts` (lines 1–14 approximately)

```typescript
import { env } from 'src/environments/.env';

if (env.ANALYTICS_ID) {
  const scriptGtag = document.createElement('script');
  scriptGtag.async = true;
  scriptGtag.src = 'https://www.googletagmanager.com/gtag/js?id=' + env.ANALYTICS_ID;

  const scriptGtagConfig = document.createElement('script');
  scriptGtagConfig.src = '/gtag.js';

  document.body.insertBefore(scriptGtagConfig, document.body.firstChild);
  document.body.insertBefore(scriptGtag, document.body.firstChild);
}
```

The GA4 library itself IS loaded correctly with the correct `G-XXXXXXX` ID from `env.ANALYTICS_ID`.
The library load at `?id=G-ACTUAL_ID` triggers GA4's automatic collection (sessions, page_view via enhanced measurement) for clients with `ANALYTICS_ID` set in Netlify.
The local `/gtag.js` is also loaded, but its `gtag('config', 'xx-xxxxxxxxx-x')` call hits a non-existent UA property — effectively a no-op.

---

## Build pipeline — how ANALYTICS_ID flows into `env`

From `~/Projects/4Shark/app-webclient/package.json` (line 20):

```
"env": "ngx-scripts env npm_package_version GRAPHQL_API_SERVER ... ANALYTICS_ID ..."
```

`ngx-scripts env` reads the listed variables from `process.env` (set by Netlify at build time) and writes `src/environments/.env.ts`.

At Netlify deploy time each site has its own `ANALYTICS_ID` env var (its GA4 property's measurement ID).
The `analytics:compile` step (`node gtag_compiler.js`) runs after `env` but fails silently (never replaces anything).
The compiled `main.ts` correctly uses `env.ANALYTICS_ID` from the generated `.env.ts` — this part works.

---

## One shared `src/gtag.js` for all 39 projects

From `~/Projects/4Shark/app-webclient/angular.json` (lines 29, 152, ... — one entry per project):

```json
"assets": [
  "src/favicon.ico",
  "src/manifest.webmanifest",
  "src/assets",
  "src/environments/4shark",
  { "glob": "**/*", "input": "src/gtag.js", "output": "/" }
]
```

Every project in the monorepo lists `"src/gtag.js"` in its assets.
A single change to `src/gtag.js` propagates to all 39 builds.

---

## Backend env for user_id prefix

`GRAPHQL_API_SERVER` is the Netlify env var that identifies the backend a given site talks to.
All clients sharing the same backend have the same `GRAPHQL_API_SERVER` value.
Available in the Angular app as `env.GRAPHQL_API_SERVER` (string, e.g. `"api.4shark.com.br"`).

Already-decided user_id format: `{GRAPHQL_API_SERVER}_{user.id}` (engineer's decision, not open).

---

## Rollbar integration — pattern reference for AnalyticsService

File: `~/Projects/4Shark/app-webclient/src/app/rollbar.ts` (full file, 43 lines)

```typescript
import Rollbar from 'rollbar';
import { ErrorHandler, Inject, Injectable, InjectionToken } from '@angular/core';
import { env } from 'src/environments/.env';

// ...config object...

export const RollbarService = new InjectionToken<Rollbar>('rollbar');

@Injectable()
export class RollbarErrorHandler implements ErrorHandler {
  constructor(@Inject(RollbarService) private rollbar: Rollbar) {}
  handleError(err: any): void {
    this.rollbar.error(err.originalError || err);
  }
}

export function rollbarFactory() {
  return new Rollbar(rollbarConfig);
}
```

Registration in `~/Projects/4Shark/app-webclient/src/app/app.module.ts` (lines 283–284):

```typescript
{ provide: ErrorHandler, useClass: RollbarErrorHandler },
{ provide: RollbarService, useFactory: rollbarFactory },
```

Pattern: factory function registered in `AppModule.providers` → no `APP_INITIALIZER` in use.

---

## CSP — no changes needed for GA4 domains

File: `~/Projects/4Shark/app-webclient/netlify.toml` (headers section):

```toml
script-src 'self' www.googletagmanager.com www.google-analytics.com;
connect-src 'self' ... analytics.google.com www.google-analytics.com www.google.com.br stats.g.doubleclick.net www.googletagmanager.com;
```

All GA4 domains are already in the CSP policy. No changes needed for the instrumentation rebuild.

---

## Electron build path

`yarn electron:build` → `ng build --configuration production --base-href ./dist.electron --output-path dist.electron`

Electron does NOT use Netlify env vars. `env.ANALYTICS_ID` would be `null` or `'xx-xxxxxxxxx-x'` (the sample value) at build time unless the engineer provides it explicitly.
Options: (A) compile-time env var for Electron build, (B) hard-code a dedicated Electron GA4 property ID, (C) disable analytics in Electron builds.

---

## Authentication hook points

File: `~/Projects/4Shark/app-webclient/src/app/core/authentication/authentication.service.ts`

Login hook (line 39): `this.credentialsService.setCredentials(response.body, formData.remember);`
After this call, `response.body.user.id` and `env.GRAPHQL_API_SERVER` are both available.

Logout hook (line 68–69):
```typescript
this.router.navigate(['/login'], { replaceUrl: true }).then(() => {
  this.credentialsService.destroyCredentials();
});
```
User-ID null should be sent before or alongside `destroyCredentials()`.
