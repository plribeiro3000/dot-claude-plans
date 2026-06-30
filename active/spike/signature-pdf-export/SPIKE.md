# SPIKE — Signature PDF Export

## Investigation question

A cancelled customer used 4Shark only for declarations and signatures. They want all their signatures delivered as PDFs. The platform has no persisted PDF artifact — it re-renders the signed document from DB data every time the user opens the page.

Two deliverables are scoped:

1. **Long-term:** persist a PDF at signing time so future exports do not require re-rendering.
2. **Short-term / urgent:** a headless-browser script that authenticates as the admin user, navigates to each signature's view URL by ID, expands every collapsible section, captures a full-page PDF, and loops over a list of IDs in bulk.

The main focus of this spike is deliverable 2.

---

## Sources consulted

- `app/app/models/signature.rb` — CarrierWave uploader, no PDF stored
- `app/app/models/acceptment.rb` — signature association
- `app/app/models/statement.rb` — sign() method
- `app/app/models/plan_statement.rb` — sign_by() method
- `app/app/models/plan_statement_portable.rb` — existing "portable" export model
- `app/app/uploaders/signature_uploader.rb` — PNG only, no PDF
- `app/app/controllers/sessions_controller.rb` — basic email/password auth endpoint at `POST /sessions`
- `app-webclient/src/app/plan-statement/plan-statement-routing.module.ts` — Angular route `/planStatements/:planStatementId`
- `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html` — collapsible panels
- `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts` — data fetching and print()
- `app-webclient/src/app/signature/temporary-signature.service.ts` — presigned S3 URL for signature PNG
- `app-webclient/src/app/core/authentication/authentication.service.ts` — login flow
- `app-webclient/src/app/core/authentication/credentials.service.ts` — token stored in localStorage/sessionStorage key `credentials`
- `app-webclient/src/app/app.service.ts` — Bearer token injected into GraphQL requests from `credentials` key
- `app-webclient/src/main.scss` lines 3467–3473 — `@media print` block
- [Playwright docs — page.pdf()](https://playwright.dev/docs/api/class-page#page-pdf) — API and headless constraint
- [Playwright docs — Authentication](https://playwright.dev/docs/auth) — storageState and addInitScript patterns
- [Checkly — Generating PDFs with Playwright](https://www.checklyhq.com/docs/learn/playwright/generating-pdfs/) — printBackground, headless-only limitation
- [BrowserStack — Playwright PDF generation](https://www.browserstack.com/guide/playwright-pdf-html-generation) — SPA readiness signals
- [ScraperAPI — Playwright vs Puppeteer](https://www.scraperapi.com/blog/playwright-vs-puppeteer/) — **UNVERIFIED** (article body not retrievable on fetch; only the navigation shell loads)
- [PDF4.dev — HTML to PDF benchmark 2026](https://pdf4.dev/blog/html-to-pdf-benchmark-2026) — performance comparison
- [SimpleThread — Replacing PDFKit with Grover](https://www.simplethread.com/replacing-pdfkit-with-grover-for-rails-pdf-generation/) — Grover Rails integration
- [SimpleThread — Replacing Grover with ferrum_pdf](https://www.simplethread.com/replacing-grover-with-ferrum-pdf-for-pdf-generation/) — Ferrum as Grover alternative
- [GitHub — Studiosity/grover](https://github.com/Studiosity/grover) — gem README
- [GitHub — mileszs/wicked_pdf issue #290](https://github.com/mileszs/wicked_pdf/issues/290) — AngularJS renders blank with wicked_pdf
- See auxiliary: `signature_excerpt_1.ts` — getSignature() and print() from plan-statement-show component TS
- See auxiliary: `signature_excerpt_2.html` — all five collapsible panels from plan-statement-show HTML, plus signature block

---

## Findings

### Finding 1: No persisted PDF exists — the signature file is a PNG stored on S3

**Evidence:**
```ruby
# app/app/uploaders/signature_uploader.rb:12
def extension_allowlist
  %w[png]
end
```
The `SignatureUploader` accepts only `.png` files. The `Signature` model stores the user's drawn signature image via CarrierWave (`mount_uploader :file, SignatureUploader` at `app/app/models/signature.rb:15`). There is no PDF column, no PDF uploader, and no `wicked_pdf`, `prawn`, `grover`, or `puppeteer` in the Rails Gemfile.

The `PlanStatementPortable` model (`app/app/models/plan_statement_portable.rb`) exists and has its own uploader, but its `PlanStatementPortableUploader` stores under `uploads/plan_statement_portables/` with no extension constraint — its nature (what file type goes in) is not declared in the uploader code. Its GraphQL type (`app/app/graphql_types/plan_statement_portable_graphql_type.rb`) exposes only `id`, `status`, `plan_statement_id`, and `plan_statement_portable_batch_id` — no `file_url` field at the GraphQL level, meaning the frontend has no current path to download a portable file.

**Source:** `app/app/uploaders/signature_uploader.rb:12`, `app/app/models/signature.rb:15`, `app/app/uploaders/plan_statement_portable_uploader.rb`, `app/app/graphql_types/plan_statement_portable_graphql_type.rb`

**Significance:** There is genuinely no persisted PDF today. Each view of `/planStatements/:id` fetches data from GraphQL and renders the document in the browser. Export requires re-rendering.

---

### Finding 2: The signed document view URL pattern is `/planStatements/:planStatementId`

**Evidence:**
```typescript
// app-webclient/src/app/plan-statement/plan-statement-routing.module.ts:19
{
  path: 'planStatements/:planStatementId',
  component: PlanStatementShowComponent,
},
```

**Source:** `app-webclient/src/app/plan-statement/plan-statement-routing.module.ts:19`

**Significance:** The script needs to navigate to `https://<host>/planStatements/<id>` for each ID. The `:planStatementId` segment is the ID from the `plan_statements` table. The engineer noted they can provide a list of IDs; the script can construct the URL directly without navigating through any list view.

There is a separate route for `AcceptmentDocument` at `/acceptmentDocuments/:acceptmentDocumentId` — this is a different entity (a batch upload document), not the individual signed statement. The route for individual statements is `/planStatements/:planStatementId`.

---

### Finding 3: Five collapsible panels (the "diabinhas") — all controlled by Angular `*ngIf` + a boolean property on each item

**Evidence:**
```html
<!-- app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:114 -->
<div class="show-panel" (click)="dealIncentive.expanded = !dealIncentive.expanded">
  <div class="show-panel-header blue font-20">{{ dealIncentive.name }}</div>
  <div class="show-panel-body" *ngIf="dealIncentive.expanded">
    <!-- content -->
  </div>
</div>
```

The same `(click)="item.expanded = !item.expanded"` / `*ngIf="item.expanded"` pattern appears for all five incentive panel types:
- `dealIncentive.expanded` (lines 114–118)
- `indicatorIncentive.expanded` (lines 158–162)
- `rankingIncentive.expanded` (lines 202–206)
- `limiterIncentive.expanded` (lines 281–285)
- `redemptionIncentive.expanded` (lines 325–329)

There are **no** Angular Material `mat-expansion-panel` components, no `<details>` / `<summary>`, no CSS-only toggles. Every panel is hidden by `*ngIf` — when `expanded` is false, the element is **absent from the DOM**, not just hidden with CSS.

**Source:** `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:114–329`

**Significance:** A headless browser cannot use a CSS visibility trick to show hidden panels. The script must click each `.show-panel` header (or trigger a click event via `evaluate`) to set `.expanded = true` in Angular's change detection, which will then render the `*ngIf` block into the DOM. After clicking, the script must wait for Angular's change detection to complete before capturing.

The CSS selector for every clickable header is `.show-panel` (the outer container, not `.show-panel-header`). Clicking all `.show-panel` elements expands every panel.

See auxiliary file `signature_excerpt_2.html` for the full annotated markup.

---

### Finding 4: The signature PNG is fetched via a second async GraphQL call after page load

**Evidence:**
```typescript
// app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:213-226
getSignature() {
  const signatureId = this.planStatement?.acceptment?.signature?.id;
  if (!signatureId) { return; }

  this.temporarySignatureService.get(signatureId).valueChanges.subscribe((response: any) => {
    if (!response?.data?.temporarySignature) { return; }
    this.signature = response.data.temporarySignature;
  });
}
```
The signature PNG URL is a **presigned S3 URL** returned by a `temporarySignature(id)` GraphQL query. This call is made after `getPlanStatement()` completes. The URL is placed in `<img [src]="signature?.url">` which triggers a second network request to S3.

**Source:** `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:213–226`, `app-webclient/src/app/signature/temporary-signature.service.ts:35–52`

**Significance:** A naive `waitForLoadState('networkidle')` may or may not catch the S3 image load. The script should explicitly wait for the `img.signature` element's `src` attribute to be non-empty, or wait for the image to finish loading (`img.complete === true`), before generating the PDF. Using `networkidle` alone is unreliable for SPAs with multiple async API calls.

---

### Finding 5: Authentication is custom JWT Bearer token stored in `localStorage`/`sessionStorage` — no SSO/Keycloak for this flow

**Evidence:**
```typescript
// app-webclient/src/app/core/authentication/credentials.service.ts:101–115
storage.setItem('credentials', credentials.token);
// ...
// app-webclient/src/app/app.service.ts:28–34
authLink = setContext((_, { headers }) => {
  const token = sessionStorage.getItem('credentials') || localStorage.getItem('credentials');
  return {
    headers: existingHeaders.set('authorization', `Bearer ${token}`),
  };
});
```

Login posts `{ email, password }` to `POST /sessions` (a REST endpoint, not GraphQL), which returns a JSON body containing a `token`. The Angular app stores the token under the key `credentials` in either `sessionStorage` or `localStorage`. Every subsequent GraphQL request reads from that key and sends `Authorization: Bearer <token>`.

The login component also supports a `providerAuthentication()` flow (SSO via `AUTH_URL`) but that is a separate code path from `AuthenticationService.login()`, which is the standard email/password flow used by admin users.

**Source:** `app-webclient/src/app/core/authentication/credentials.service.ts:101–115`, `app-webclient/src/app/app.service.ts:28–34`, `app/app/controllers/sessions_controller.rb:6–16`, `app-webclient/src/app/login/login.component.ts:33–37`

**Significance:** The headless browser script has two options for authentication:

**Option A — UI login**: Navigate to `/login`, fill email/password, click submit, wait for redirect. The token is then in storage automatically.

**Option B — API login + inject**: Make a direct `POST /sessions` HTTP call from the script to get the token, then inject it into localStorage via `context.addInitScript()` before navigating to any Angular route. This avoids the UI login flow entirely and is more reliable (no DOM dependency on the login form).

---

### Finding 6: An existing print button calls `window.print()` — the `@media print` block is minimal

**Evidence:**
```typescript
// app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:237-239
print() {
  window.print();
}
```
```scss
/* app-webclient/src/main.scss:3467-3473 */
@media print {
  html, body {
    height: auto;
    overflow-y: visible !important;
  }
}
```

The only print-specific CSS is `height: auto` and `overflow-y: visible` on `html`/`body`. There is no `display: none` on navigation/sidebar elements, no print-specific layout. The page would print with the sidebar and navigation visible unless the script uses `emulateMedia('screen')` or the engineer adds print CSS.

**Source:** `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts:237–239`, `app-webclient/src/main.scss:3467–3473`

**Significance:** Using `page.pdf()` by default applies `@media print`, which reveals only the minimal print CSS above. The sidebar and navigation will appear in the PDF unless: (a) the script calls `page.emulateMedia({ media: 'screen' })` before `page.pdf()`, or (b) the engineer adds `@media print { .sidebar, .nav { display: none } }`. For a one-time export, option (a) is simpler.

---

### Finding 7: Tool landscape for deliverable 2 — Playwright and Puppeteer have native `page.pdf()`; Selenium does not

**Evidence from web research:**

From the [PDF4.dev HTML-to-PDF benchmark 2026](https://pdf4.dev/blog/html-to-pdf-benchmark-2026): *"Puppeteer is slower than Playwright at every data point — 147ms vs 42ms cold, 48ms vs 3ms warm."* (those are simple-document figures). For complex documents the same benchmark reports Playwright output at 59 KB (cold) / 125 KB (warm) vs Puppeteer at 197 KB (both cold and warm).

[ScraperAPI Playwright vs Puppeteer](https://www.scraperapi.com/blog/playwright-vs-puppeteer/) — **UNVERIFIED**: the article body was not retrievable on fetch (only the navigation shell loads), so no quote from it is relied upon.

From [Checkly Playwright PDF docs](https://www.checklyhq.com/docs/learn/playwright/generating-pdfs/): *"This feature is currently only supported in Chromium headless in Playwright."* — `page.pdf()` is Chromium-headless only in both Playwright and Puppeteer. Firefox and WebKit cannot generate PDFs.

From [Playwright page.pdf() API docs](https://playwright.dev/docs/api/class-page#page-pdf): *"To generate a pdf with `screen` media, call [page.emulateMedia()](https://playwright.dev/docs/api/class-page#page-emulate-media) before calling `page.pdf()`."*

Selenium / WebDriver: does not natively support PDF generation. Would require DevTools Protocol (CDP) invocation manually. No advantage over Playwright/Puppeteer for this use case.

**Source:** [PDF4.dev](https://pdf4.dev/blog/html-to-pdf-benchmark-2026), [Checkly](https://www.checklyhq.com/docs/learn/playwright/generating-pdfs/), [Playwright docs](https://playwright.dev/docs/api/class-page#page-pdf). ScraperAPI marked UNVERIFIED (body not retrievable).

**Significance:** Playwright (Node.js) and Puppeteer are the two tools with a native `page.pdf()`; Selenium has no native PDF and would require manual CDP invocation. The benchmark above shows Playwright faster with smaller output, but the choice between Playwright and Puppeteer is the engineer's. The script runs outside the Rails app — any machine with Node.js and a Chromium install.

**Verification:** PDF4.dev and Checkly re-fetched 2026-06-01. PDF4.dev figures (147ms vs 42ms cold, 48ms vs 3ms warm; 59/125 KB vs 197 KB complex) confirmed verbatim. Checkly headless-only quote confirmed. Playwright `page.pdf()` / `emulateMedia` quotes confirmed (Finding stands on verified sources only; ScraperAPI excluded as UNVERIFIED).

---

### Finding 8: Correct sequence for expanding all collapsible panels and capturing

The `*ngIf` pattern means panels are DOM-absent until clicked. The following sequence is required:

1. Navigate to `/planStatements/<id>` and wait for Angular to settle.
2. Wait for the signature image to load (second async call).
3. Click every `.show-panel` element to expand all panels.
4. Wait for Angular change detection to complete (all `*ngIf` blocks rendered).
5. Call `page.pdf()` (or `page.screenshot({ fullPage: true })`).

From [BrowserStack Playwright PDF guide](https://www.browserstack.com/guide/playwright-pdf-html-generation): *"Define stable markers like 'invoice total loaded' or 'table row count rendered' rather than depending on generic load events."* And: *"Network idleness alone is often insufficient because modern frameworks continue background activity even after the primary UI appears."*

For step 4, after clicking all panels, a reliable wait is `page.waitForFunction(() => document.querySelectorAll('.show-panel-body').length > 0)` — checking that at least one `.show-panel-body` element exists in the DOM. A more robust approach: count panels before clicking and then wait until `.show-panel-body` count equals the expected number.

**Source:** [BrowserStack](https://www.browserstack.com/guide/playwright-pdf-html-generation), `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:114–329`

**Verification:** BrowserStack re-fetched 2026-06-01; both quoted sentences confirmed verbatim — *"Define stable markers like 'invoice total loaded' or 'table row count rendered'..."* and the network-idleness sentence.

---

### Finding 9: Token injection approach via Playwright addInitScript

From [Playwright Authentication docs](https://playwright.dev/docs/auth):
```javascript
// Inject sessionStorage before page navigation
await context.addInitScript(storage => {
  if (window.location.hostname === 'example.com') {
    for (const [key, value] of Object.entries(storage))
      window.sessionStorage.setItem(key, value);
  }
}, sessionStorage);
```
The same pattern works for `localStorage`. The 4Shark app reads `credentials` from `sessionStorage.getItem('credentials') || localStorage.getItem('credentials')`, so either storage works.

The script can: (1) make a raw `fetch`/`axios` POST to `/sessions` to get the token, (2) inject the token into the page context via `context.addInitScript`, (3) navigate to the target URL. Angular's `AppService` will then find the token in storage and attach it to every GraphQL request automatically.

**Source:** [Playwright Authentication docs](https://playwright.dev/docs/auth), `app-webclient/src/app/app.service.ts:29–30`

---

### Finding 10: Server-side PDF options for deliverable 1 (long-term)

| Option | Fidelity to Angular view | Rails integration | Infrastructure cost | Notes |
|--------|--------------------------|-------------------|---------------------|-------|
| **Grover gem** (Puppeteer wrapper) | High — renders the full Angular SPA in headless Chrome | Rails middleware or direct call | Requires Node.js + Chromium in container | Can authenticate with Bearer token via custom headers or cookie; maintained (v1.2.2, Jan 2025) |
| **Ferrum gem** (direct CDP, no Node.js) | High — same Chromium engine | Direct Ruby API | Requires Chromium binary only | No Node.js dependency; [SimpleThread replaced Grover with Ferrum](https://www.simplethread.com/replacing-grover-with-ferrum-pdf-for-pdf-generation/) |
| **wicked_pdf / wkhtmltopdf** | Low — wkhtmltopdf uses an old WebKit; does not execute Angular JS | Rails view rendering | Requires wkhtmltopdf binary | GitHub issue #290 on wicked_pdf confirms Angular renders blank |
| **Prawn** | None — programmatic DSL, draws PDF by hand | Rails | Pure Ruby | Would require rebuilding the entire document layout in Prawn DSL |
| **Client-side capture at sign time** | Perfect — already rendered | Requires Angular + JS to generate PDF | No server infra | jsPDF or html2canvas on the Angular side; adds JS dependency to the webclient; PDF fidelity depends on library |

From [wicked_pdf issue #290](https://github.com/mileszs/wicked_pdf/issues/290): *"However, the html that gets rendered via angular is not showing up."* — this is a hard blocker for wicked_pdf.

From [SimpleThread Grover article](https://www.simplethread.com/replacing-pdfkit-with-grover-for-rails-pdf-generation/): Grover uses Chromium headless and renders the full page in a real browser. Note: passing authentication context (token or cookies) to the headless browser to reach protected routes is this spike's own inference, not a quoted claim from the article.

**Source:** [SimpleThread Grover](https://www.simplethread.com/replacing-pdfkit-with-grover-for-rails-pdf-generation/), [SimpleThread Ferrum](https://www.simplethread.com/replacing-grover-with-ferrum-pdf-for-pdf-generation/), [wicked_pdf issue #290](https://github.com/mileszs/wicked_pdf/issues/290), [Grover GitHub](https://github.com/Studiosity/grover)

**Verification:** wicked_pdf issue #290 re-fetched 2026-06-01; verbatim quote *"However, the html that gets rendered via angular is not showing up."* confirmed present. SimpleThread Grover/Ferrum: Chromium-headless rendering confirmed in original fetch; the auth-context claim is flagged above as inference, not attribution.

---

## Trade-offs surfaced

### Deliverable 2 (urgent script)

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **Playwright (Node.js)** | Built-in auto-wait APIs, `page.pdf()` native, smaller output, faster warm path (3ms simple-doc) | Chromium-headless only for PDF; requires Node.js | [PDF4.dev](https://pdf4.dev/blog/html-to-pdf-benchmark-2026) |
| **Puppeteer (Node.js)** | Identical API, wider existing community examples | Slower (48ms warm), larger output files, less automatic waiting | [PDF4.dev](https://pdf4.dev/blog/html-to-pdf-benchmark-2026) |
| **Selenium + CDP** | Language-agnostic (Ruby possible) | No native PDF; CDP invocation is manual; significantly more complex for this use case | [Playwright docs](https://playwright.dev/docs/api/class-page#page-pdf) |
| **PDF via `page.pdf()`** | Vector PDF; text selectable; legally cleaner; smaller file | Chromium-headless only; print CSS applied (sidebar may appear unless emulateMedia is set) | [Checkly](https://www.checklyhq.com/docs/learn/playwright/generating-pdfs/) |
| **Screenshot via `page.screenshot({ fullPage: true })`** | Works in any browser; captures exact visual state | PNG/JPEG only; large files; not text-searchable; legally weaker as artifact | [Playwright docs](https://playwright.dev/docs/api/class-page) |
| **UI login vs API token inject** | UI login: simpler code, no HTTP call needed | API inject: more reliable (no login form DOM dependency, no SSO redirect risk), one POST then inject | [Playwright auth docs](https://playwright.dev/docs/auth) |

### Deliverable 1 (long-term)

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **Grover** (Puppeteer + Chromium in Rails) | Full Angular fidelity; Rails-native middleware; maintained | Node.js required in container; must pass auth token to headless browser to reach protected routes | [SimpleThread](https://www.simplethread.com/replacing-pdfkit-with-grover-for-rails-pdf-generation/) |
| **Ferrum** (Ruby CDP, no Node.js) | Same Chromium fidelity as Grover; no Node.js dependency | Less battle-tested than Grover; same auth problem | [SimpleThread](https://www.simplethread.com/replacing-grover-with-ferrum-pdf-for-pdf-generation/) |
| **Client-side at sign time** | Zero server cost; perfect visual fidelity | Angular bundle grows; jsPDF/html2canvas have their own rendering quirks; PDF generated on user's machine raises custody questions | Not found in codebase; training-data observation |
| **wicked_pdf** | Simple Rails integration for server-rendered views | Angular renders blank — hard blocker | [wicked_pdf issue #290](https://github.com/mileszs/wicked_pdf/issues/290) |
| **Prawn** | Pure Ruby, no external dependencies | Must rebuild entire document layout from scratch in Prawn DSL; no Angular view reuse | [DEV Community](https://dev.to/jerryweyer/creating-pdfs-in-a-ruby-on-rails-application-2kk5) |

---

## What remains uncertain

- **Volume**: How many `plan_statement` records does this cancelled customer have? This determines whether the bulk script needs concurrency (multiple parallel pages) or sequential is sufficient.
- **Where the script runs**: Engineer's local machine? A CI/CD job? ECS task? This affects how Node.js + Chromium are provided (local brew install vs Docker image with `playwright install chromium`).
- **One-PDF-per-signature vs merged PDF**: Should each signature produce one `<id>.pdf` file, or should all signatures be merged into a single multi-page document? Playwright's `page.pdf()` produces one PDF per call; merging would require a library like `pdf-lib`.
- **Output file naming**: Should files be named by `plan_statement_id`, by user name, by date, or some combination?
- **SSO customers**: The login component supports both `basic_authentication` (email/password to `/sessions`) and a provider SSO flow (`AUTH_URL`). This spike assumes the cancelled customer uses basic authentication. If they use SSO (Microsoft/Keycloak), the API-token-inject approach needs adjustment.
- **Signature PNG S3 URL expiry**: The presigned URL returned by `temporarySignature` has an expiration time (`ApplicationConfiguration.signed_url_expiration_time`). If the script takes longer than that window, images will 403. The script should generate PDFs promptly and not batch too slowly.
- **Whether `PlanStatementPortable` files are relevant**: The `PlanStatementPortable` model exists and stores files under `uploads/plan_statement_portables/`. Its current content type and whether it already holds any PDF artifacts for this customer is not known from static code analysis alone.
- **Print CSS for sidebar**: The `@media print` block does not hide the navigation sidebar. Whether that sidebar appears in the PDF (and whether the engineer wants it hidden) needs confirmation.

---

## Suggested options for main and the engineer

### Deliverable 2 (urgent — this customer)

**Option A — Playwright with API token injection**

1. Script calls `POST <host>/sessions` with admin credentials, receives JWT token.
2. Script creates a Playwright `BrowserContext` and calls `context.addInitScript` to inject `localStorage.setItem('credentials', token)` before any navigation.
3. For each plan statement ID in the list:
   a. Navigate to `https://<host>/planStatements/<id>`.
   b. Wait for a known element that confirms data has loaded (e.g., `waitForSelector('.description')` — the signature block).
   c. Wait for the signature image to load (`waitForFunction(() => document.querySelector('img[alt="signature"]')?.complete)`).
   d. Click all `.show-panel` elements via `page.evaluate(() => document.querySelectorAll('.show-panel').forEach(el => el.click()))`.
   e. Wait for `.show-panel-body` elements to appear in the DOM.
   f. Optionally call `page.emulateMedia({ media: 'screen' })` to suppress sidebar-visible print CSS.
   g. Call `page.pdf({ path: '<id>.pdf', printBackground: true, format: 'A4' })`.
4. Script collects all PDFs into an output directory.

**Option B — Playwright with UI login**

Same as Option A but step 1–2 is replaced by: navigate to `/login`, fill email/password form, click submit, wait for redirect to dashboard. Simpler to write; more brittle if the login form or SSO flow changes.

**Option C — Full-page screenshot instead of PDF**

Replace step 3g with `page.screenshot({ path: '<id>.png', fullPage: true })`. Captures exact visual state. PNG files; not text-searchable. Trade-off: simpler (no print media issues, works across all browsers) but lower quality as a legal artifact.

### Deliverable 1 (long-term)

**Option D — Grover (Puppeteer + Rails middleware)**

Add `gem 'grover'` to the Gemfile. At sign time (after `create_acceptment!` succeeds), enqueue a Sidekiq worker that renders the plan statement URL using Grover, saves the resulting PDF to S3 via the existing `PlanStatementPortable` / `PlanStatementPortableAttachment` chain (or a new attachment type). Requires Chromium + Node.js in the container image.

**Option E — Ferrum (Ruby CDP, no Node.js)**

Same as Option D but with the `ferrum` gem instead of Grover. Eliminates the Node.js runtime dependency. The Ruby API calls Chrome directly via CDP.

**Option F — Client-side PDF capture at sign time**

In the Angular `PlanStatementAcceptComponent` (the modal opened by `openSignatureDialog()`), after the signature is submitted and the response comes back, use `jsPDF` + `html2canvas` to capture the current DOM and generate a PDF on the client, then upload it to the API. No server infrastructure. PDF generated on the user's device; chain of custody differs from server-side capture.

(No recommendation — the options above surface the trade-offs; main and the engineer decide.)
