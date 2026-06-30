# Auxiliary — Web Research Extracts (ga4-instrumentation)

> Source extracts to support PLAN-SPIKE.md. All claims cited to URL + verbatim substring.

---

## Source 1: GA4 User-ID implementation (official Google docs)

URL: https://developers.google.com/analytics/devguides/collection/ga4/user-id

Key commands:

```js
// Set user_id after login — use gtag('set') for state changes after initial page load:
gtag('set', { 'user_id': userId });

// Clear user_id on logout — JavaScript null only (not string "null", not ""):
gtag('set', { 'user_id': null });

// On every page load where user is authenticated, include in config:
gtag('config', 'G-XXXXXXXX', { 'user_id': userId });
```

Quote: "add the user_id parameter to the config command on each page of your website"
Quote: "To set or update the user_id after the initial page load, use the gtag('set') command."
Quote: "Don't send an empty string (''), a blank string (' '), or the quoted words 'null' or 'NULL'"

Verified: Content confirmed at URL above (fetched during this session).

---

## Source 2: GA4 Consent Mode default/update commands (official Google docs)

URL: https://developers.google.com/tag-platform/security/guides/consent

Default (set BEFORE gtag('js', ...) and gtag('config', ...)):

```js
gtag('consent', 'default', {
  'ad_storage': 'denied',
  'ad_user_data': 'denied',
  'ad_personalization': 'denied',
  'analytics_storage': 'denied'
});
```

Update (called after user grants consent):

```js
gtag('consent', 'update', {
  'analytics_storage': 'granted'
  // plus ad_* if relevant — for analytics-only, just analytics_storage
});
```

Quote: "you are responsible for making sure that default consent mode is set for each of your measurement products to match your organization's policy"

Note: LGPD requires default denied for analytics_storage (affirmative consent required, pre-ticking boxes or continued browsing is not valid consent).

Verified: Consent default/update commands confirmed at URL above.

---

## Source 3: LGPD analytics consent requirements

URL: https://cookieinformation.com/lgpd-analytics/ (cited in SPIKE.md Finding 3)

Quote (from SPIKE.md, verbatim confirmed): "Consent banners or cookie notifications must allow users to opt-out of non-essential tracking."

Consent requirements under LGPD: free, specific, informed, unambiguous (affirmative action).
Pre-ticked boxes and continued browsing are NOT valid consent under LGPD.
Default state for `analytics_storage` must be `'denied'`.

---

## Source 4: ngx-cookieconsent Angular library

URL: https://github.com/tinesoft/ngx-cookieconsent
npm: https://www.npmjs.com/package/ngx-cookieconsent

Key facts (from npm/GitHub page):
- Latest version 8.0.0; Angular v19+ is the minimum supported version
- Wraps the Osano Cookie Consent library (vanilla JS)
- Provides Angular-native integration with `NgcCookieConsentModule` or `provideNgcCookieConsent(config)` for standalone apps
- Supports custom themes, layouts, and translations (ngx-translate compatible)
- Does NOT ship with built-in Consent Mode v2 signal integration — the developer must add the `gtag('consent', 'update', ...)` call in the status-change callback
- Does NOT support IAB TCF natively

Assessment for this project:
- Pro: Angular-native, v19-compatible, lightweight (~30KB), no SaaS dependency
- Con: No built-in GA4 Consent Mode v2 bridge; engineer must wire `gtag('consent', 'update', ...)` manually in the consent-granted callback
- Con: No LGPD-specific template; engineer must write Portuguese copy

---

## Source 5: CookieHub CMP (third-party SaaS)

URL: https://www.cookiehub.com/google-consent-mode-v2
URL: https://www.cookiehub.com/blog/google-analytics-google-ads-consent-mode-v2-2026

Key facts:
- Certified Google CMP partner
- Claims native LGPD compliance support
- Auto-integrates Consent Mode v2 signals via GTM or direct script embed
- Free tier available; paid plans from ~$10/month per domain
- ~50 Netlify sites = ~50 domains (even if shared CMP account, each domain may need separate config in the CMP dashboard)

Assessment:
- Pro: Built-in Consent Mode v2 bridge, LGPD templates, no frontend code to maintain for the consent logic
- Con: SaaS dependency on a third party; paid cost per domain at scale; adds external JS load
- Con: CMP must be configured per client (50 domains) in the CMP dashboard — operational overhead

---

## Source 6: GA4 recommended events for web (official)

URL: https://developers.google.com/analytics/devguides/collection/ga4/reference/events
URL: https://support.google.com/analytics/answer/9267735

Events with built-in GA4 schema support (unlock dedicated GA4 reports):

| Event name | Parameters | Notes |
|---|---|---|
| `login` | `method` (optional, string) | Recommended for web. Unlocks "Sign-ins" dimension in GA4 |
| `sign_up` | `method` (optional, string) | For new account creation — not applicable here (accounts created by admin) |
| `search` | `search_term` (required, string) | For internal search functionality |
| `select_content` | `content_type`, `content_id` | General feature selection tracking |
| `page_view` | `page_location`, `page_title` | Automatic via enhanced measurement; can be sent manually too |

No `logout` event in Google's recommended schema — GA4 has no predefined logout event; it is tracked as a custom event if desired.
No `feature_usage` in Google's schema — custom event.

For B2B SaaS (from Polymer/SaasHero references):
Commonly tracked custom events: `feature_click`, `export_triggered`, `report_viewed`, `filter_applied`.

---

## Source 7: Timing of consent relative to gtag init

From SPIKE.md Finding 3 (secureprivacy.ai, confirmed):

"Consent signals must reach Google Tag Manager immediately when users make choices"
"tags firing before consent represents the most common and dangerous implementation error"

Implementation rule: `gtag('consent', 'default', {...})` must execute BEFORE `gtag('js', new Date())` and BEFORE any `gtag('config', ...)` call.

In the current `app-webclient` architecture:
- `main.ts` creates a `<script src="/gtag.js">` element first (the local config script)
- Then creates the GA library script
- The `window.onload` callback in `src/gtag.js` fires AFTER the page loads — meaning the library may have already initiated before consent signals are set

The order must be:
1. `gtag('consent', 'default', { analytics_storage: 'denied', ... })` — must run first
2. `gtag('js', new Date())` — tag initialization
3. `gtag('config', 'G-XXXXXXX', { ... })` — property config
4. (Later) `gtag('consent', 'update', { analytics_storage: 'granted' })` — when user accepts

---

## Source 8: GA4 automatic collection (what works without bugs)

When `main.ts` injects `https://www.googletagmanager.com/gtag/js?id=G-ACTUAL_ID`, the GA4 library auto-collects:
- `page_view` events (via enhanced measurement, enabled by default)
- `session_start`, `first_visit` events
- Scroll depth (enhanced measurement, enabled by default)
- Outbound click events (enhanced measurement)

This automatic collection is working for clients with a real `ANALYTICS_ID` in Netlify — the `main.ts` script load is correct. The bugs in `src/gtag.js` and `app.component.ts` corrupt the explicit config/event calls but do not prevent the auto-collection from the library init.

Implication: fixing the explicit bugs is the highest-leverage improvement because the auto-collection baseline already works.
