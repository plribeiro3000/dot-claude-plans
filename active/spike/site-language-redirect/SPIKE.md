# SPIKE — Automatic Browser-Language Redirect for 4shark.com.br / 4shark.com (Wix Multilingual)

## Investigation question

The institutional site `4shark.com.br` (and the international `4shark.com`) is hosted on Wix, configured in **Wix Multilingual** mode with three languages — Portuguese, English, Spanish — Portuguese being the **default language**. Today every visitor lands on the Portuguese version regardless of browser language. We want visitors to be routed automatically to the version matching their browser's language (`Accept-Language`).

How should this be done — covering both the native Wix front and the Cloudflare/DNS front — with trade-offs, so main and the engineer can choose?

## Sources consulted

- `terraform/dns/public_dns_4shark_com_br.tf:5-13`, `:139-147` — confirms the root and `www` records for `4shark.com.br` are `proxied = false` (Wix DNS-only)
- `terraform/dns/public_dns_4shark_com.tf:5-13`, `:99-107` — same pattern for `4shark.com`
- `terraform/dns/redirect_app4shark_com_br.tf:1-29` — the only existing Cloudflare `http_request_dynamic_redirect` ruleset in this stack, used for a plain domain-to-domain 301, not a language redirect
- `terraform/dns/public_dns_app4shark_com_br.tf:1-23` — the record it redirects sits on `proxied = true` pointing at the RFC 5737 test-net IP `192.0.2.1`, i.e. a redirect-only host with no real origin behind it
- [Wix Multilingual: Automatically Showing Your Site to Visitors in the Language of their Browser](https://support.wix.com/en/article/automatically-redirecting-visitors-based-on-their-browser-language-in-wix-multilingual) — the native auto-switch toggle, its behavior, and its limitations
- [Wix Multilingual: Editing Your Multilingual Site's URL Structure](https://support.wix.com/en/article/wix-multilingual-editing-your-multilingual-sites-url-structure) — the three URL structure options and their SEO trade-offs
- [Wix Multilingual: Optimizing SEO Settings for Multilingual Sites](https://support.wix.com/en/article/wix-multilingual-optimizing-seo-settings-for-multilingual-sites) — Wix's automatic hreflang/x-default tagging
- [Wix Multilingual Request: Choosing the Default Language for Site Visitors](https://support.wix.com/en/article/wix-multilingual-request-changing-your-sites-main-language) — a separate, newer (August 2025) feature about the default-language choice itself
- [Wix Help Center: Request Cloudflare Proxy Support](https://support.wix.com/en/article/request-cloudflare-proxy-support) — Wix's own statement that proxied DNS records are not supported, filed as an open feature request
- [tech-champion.com: Understanding the Compatibility Limits of Wix and Cloudflare Performance Features](https://tech-champion.com/websites/wix/understanding-the-compatibility-limits-of-wix-and-cloudflare-performance-features/) — third-party technical explanation of why the incompatibility exists
- [Cloudflare Docs: Fields reference (Ruleset Engine)](https://developers.cloudflare.com/ruleset-engine/rules-language/fields/reference/) — definition of `http.request.accepted_languages`
- [hegedus.me: Language-specific redirects based on Accept-Language header with Cloudflare](https://hegedus.me/en/blog/language-specific-redirects-based-on-accept-language-header-with-cloudflare/) — worked example of a Cloudflare redirect rule keyed on `accepted_languages`
- [Google Search Central: How Google Crawls Locale-Adaptive Pages](https://developers.google.com/search/docs/specialty/international/locale-adaptive-pages) — Googlebot's `Accept-Language` behavior and Google's official recommendation
- [MERJ: Your Accept-Language Redirects Could Be Blocking Search Engines and AI Crawlers](https://merj.com/blog/your-accept-language-redirects-could-be-blocking-search-engines-and-ai-crawlers) — third-party SEO risk analysis of Accept-Language-based redirects
- `community.cloudflare.com` SSL-handshake thread — attempted fetch returned **HTTP 403**; marked **UNVERIFIED**, not used to sustain any finding below

## Findings

### Finding 1: Wix Multilingual has a native, purpose-built toggle for exactly this behavior

**Evidence:** "Automatically show visitors the language version of your site that matches their browser's language." The toggle sits in the Multilingual dashboard under Settings, named "Language auto-switch":
- Enabled: "The site is automatically displayed in the visitor's browser language."
- Disabled: "The site is displayed in your site's main language, and visitors must switch to their preferred language using your language menu."

**Source:** [Wix Multilingual: Automatically Showing Your Site to Visitors in the Language of their Browser](https://support.wix.com/en/article/automatically-redirecting-visitors-based-on-their-browser-language-in-wix-multilingual)

**Significance:** The symptom described in the investigation question — "every visitor falls into PT regardless of browser language" — is the documented **disabled** state of this exact toggle. This is a one-click, no-code, no-infra-risk candidate that requires no DNS or Cloudflare change at all.

### Finding 2: The auto-switch feature has three documented limitations

**Evidence:**
- Requires at least one active secondary language: "This feature is only available if you have at least one active secondary language in Wix Multilingual."
- Fallback when no matching translation exists: "If you didn't add the relevant language to your site, the visitor will see your site's main language version, and can manually switch languages from the menu."
- Cookie-banner interaction: if Wix's cookie banner is enabled, visitors "won't be able to manually change the language to one different from their browser's default until they accept the cookie banner."
- Manual override remains possible even with auto-switch on: "visitors can still type the URL with a language code (like fr.wix.com or wix.com/fr) to reach other language versions of your site."

**Source:** [Wix Multilingual: Automatically Showing Your Site to Visitors in the Language of their Browser](https://support.wix.com/en/article/automatically-redirecting-visitors-based-on-their-browser-language-in-wix-multilingual)

**Significance:** None of these limitations block the stated goal (PT/EN/ES are all already configured as active languages per the investigation brief). The cookie-banner interaction is a UX nuance worth validating on the live site once the toggle is enabled.

### Finding 3: Wix Multilingual's URL structure choice affects what the redirect actually lands on

**Evidence:**
- Subdirectories (default): `https://mystunningwebsite.com/fr` — "all your site's language versions contribute to your search discoverability because they share the same domain."
- Subdomains: `https://fr.mystunningwebsite.com` — "Search engines consider each subdomain site as unique and distinct from your main site," so SEO does not transfer between versions; requires a Premium plan.
- Language parameters: `https://mystunningwebsite.com/?lang=fr` — "Search engines like Google do not recommend using language parameters because of the negative effect they can have on discoverability."

**Source:** [Wix Multilingual: Editing Your Multilingual Site's URL Structure](https://support.wix.com/en/article/wix-multilingual-editing-your-multilingual-sites-url-structure)

**Significance:** Subdirectories are both the Wix default and the SEO-preferred structure. Which structure `4shark.com.br` currently uses was not confirmed in this spike — see "What remains uncertain."

### Finding 4: Wix does not officially support proxied (orange-cloud) DNS records

**Evidence:** "Currently, Wix does not support proxied DNS records for domain connections." Wix's own workaround guidance: "you can ask Cloudflare to disable any active proxies or record masking for your domain." This is filed as an open feature request Wix is still "collecting votes for."

**Source:** [Wix Help Center: Request Cloudflare Proxy Support](https://support.wix.com/en/article/request-cloudflare-proxy-support)

**Significance:** This directly confirms, from Wix's own documentation, the constraint already observed in the Terraform stack (`proxied = false` on every Wix-pointing record). Any option that requires proxying the real `4shark.com.br` / `www.4shark.com.br` / `4shark.com` hostnames runs against Wix's documented, unsupported configuration.

### Finding 5: The technical reason is SSL/host-identification, and it is architectural, not a temporary bug

**Evidence:** "Wix requires full control over the incoming traffic flow. Introducing a proxy layer can interfere with how Wix identifies the source of the traffic." And: "Wix officially recommends the Grey Cloud setting because their system needs to see the actual visitor's IP and manage the SSL certificate renewal process."

**Source:** [tech-champion.com: Understanding the Compatibility Limits of Wix and Cloudflare Performance Features](https://tech-champion.com/websites/wix/understanding-the-compatibility-limits-of-wix-and-cloudflare-performance-features/)

**Significance:** Both Wix's own SSL certificate issuance/renewal and Wix's traffic-source identification depend on DNS-only resolution. Proxying breaks this at the platform level, not just as an edge case — consistent with the incident class documented in the Cloudflare Community ("Getting SSL Handshake Error on Wix website"), though that specific thread could not be fetched (HTTP 403, marked UNVERIFIED).

### Finding 6: The stack's own existing Cloudflare redirect (`app4shark.com.br`) is not a counter-example — it works precisely because there is no real Wix origin behind it

**Evidence:**
```hcl
// terraform/dns/public_dns_app4shark_com_br.tf:5-13
resource "cloudflare_dns_record" "app_br_root_a" {
  content  = "192.0.2.1"
  name     = "app4shark.com.br"
  proxied  = true
  ttl      = 1
  type     = "A"
  zone_id  = local.cloudflare_zone_ids["app4shark.com.br"]
  settings = {}
}
```
```hcl
// terraform/dns/redirect_app4shark_com_br.tf:5-28
resource "cloudflare_ruleset" "redirect_app4shark_com_br" {
  zone_id = local.cloudflare_zone_ids["app4shark.com.br"]
  phase   = "http_request_dynamic_redirect"
  rules = [{
    action     = "redirect"
    expression = "true"
    action_parameters = {
      from_value = {
        status_code = 301
        target_url  = { expression = "concat(\"https://app4shark.com\", http.request.uri.path)" }
      }
    }
  }]
}
```

**Source:** local codebase, cited above

**Significance:** `expression = "true"` fires the 301 unconditionally, at the Cloudflare edge, for every request — no request ever reaches an origin, because the origin IP (`192.0.2.1`) is a non-routable test-net address that answers nothing. This is fundamentally different from proxying the *real* `4shark.com.br`, where the traffic that does NOT match the redirect condition (i.e., the default-language visitors) must still reach the live Wix site behind the proxy — reintroducing Finding 4 and 5's constraint for exactly that portion of traffic.

### Finding 7: Cloudflare's Ruleset Engine exposes a field built for this exact use case

**Evidence:** `http.request.accepted_languages` is defined as "List of language tags provided in the Accept-Language HTTP request header." A worked example against a `http_request_dynamic_redirect`-phase rule:
```
(http.request.full_uri eq "https://hegedus.me/") and (starts_with(http.request.accepted_languages[0],"hu"))
```
with the caveats: "Only redirect homepage requests" (to avoid breaking asset paths), and "Use a fallback language" for unmatched browsers.

**Source:** [Cloudflare Docs: Fields reference](https://developers.cloudflare.com/ruleset-engine/rules-language/fields/reference/), [hegedus.me worked example](https://hegedus.me/en/blog/language-specific-redirects-based-on-accept-language-header-with-cloudflare/)

**Significance:** The mechanism the investigation brief anticipated (Single Redirects keyed on parsed Accept-Language) is real and already demonstrated in a public worked example, structurally identical to the stack's existing `redirect_app4shark_com_br.tf` ruleset shape. The blocking factor for 4Shark is not whether Cloudflare can express the rule — it is whether the real Wix hostname can be proxied at all (Finding 4/5).

### Finding 8: A "dedicated hostname" workaround does not cover the actual traffic in question

**Evidence:** This is a structural inference from Findings 4–6, not a quoted source: the existing `app4shark.com.br` pattern only works as a redirect-only, no-real-origin hostname. Applying the same shape to the institutional site would require a *separate* hostname (distinct from `4shark.com.br` / `www.4shark.com.br`) that could be proxied safely — but visitors who type or click the literal `4shark.com.br` / `4shark.com` domain (direct navigation, bookmarks, business cards, existing inbound links, organic search results) never touch that separate hostname. It would only intercept traffic that some other 4Shark-controlled surface (an ad campaign, a QR code, an email footer) is explicitly pointed at the dedicated hostname instead of the real domain.

**Significance:** This narrows the practical value of a Cloudflare-side dedicated-hostname approach to a small, deliberately-routed slice of traffic — it does not solve "every visitor who lands on 4shark.com.br gets the wrong language," which is the stated problem.

### Finding 9: Googlebot does not send `Accept-Language`, and Google's own guidance favors separate crawlable URLs + hreflang over content/redirect adaptation

**Evidence:** "The crawler sends HTTP requests without setting Accept-Language in the request header." Google's recommendation: "We recommend using separate locale URL configurations and annotating them with rel=\"alternate\" hreflang annotations."

**Source:** [Google Search Central: How Google Crawls Locale-Adaptive Pages](https://developers.google.com/search/docs/specialty/international/locale-adaptive-pages)

**Significance:** Because Googlebot sends no `Accept-Language` value, an edge rule keyed purely on `accepted_languages[0]` would, by construction, treat Googlebot as "unmatched" and fall through to whatever the rule's fallback branch does (per Finding 7's "use a fallback language" caveat) — typically the site's default language. A native Wix auto-switch, per Finding 1, is scoped to "the visitor's browser language" and is documented as a per-visitor UX feature layered on top of Wix's own hreflang generation (Finding 10), not as a mechanism that rewrites what gets indexed.

### Finding 10: Third-party SEO analysis warns generically against Accept-Language-keyed redirects at the routing layer

**Evidence:** "Redirecting HTML based on Accept-Language can reduce indexing quality and create 'wrong language' retrieval." Failure pattern described: "Bot requests canonical URL (e.g., /product) → Server redirects based on Accept-Language → Bot lands on /en/product." Recommendation: "Build following internet standards, make URLs explicit, and keep redirects predictable."

**Source:** [MERJ: Your Accept-Language Redirects Could Be Blocking Search Engines and AI Crawlers](https://merj.com/blog/your-accept-language-redirects-could-be-blocking-search-engines-and-ai-crawlers)

**Significance:** This risk is specifically about a *server/edge-level* redirect applied indiscriminately to every requester, including any crawler that does send a language header. It is a generic caution against the shape of Option B (Cloudflare-side redirect), not specific evidence about Option A (Wix's own auto-switch), which Wix positions as a client-facing feature coexisting with its own hreflang/x-default generation (Finding 11).

### Finding 11: Wix Multilingual already auto-generates hreflang and x-default tags independently of the auto-switch toggle

**Evidence:** "Wix adds hreflang and x-default tags to the code of your site's multilingual pages."

**Source:** [Wix Multilingual: Optimizing SEO Settings for Multilingual Sites](https://support.wix.com/en/article/wix-multilingual-optimizing-seo-settings-for-multilingual-sites)

**Significance:** Wix documents the auto-switch feature (Finding 1) and the hreflang/x-default tagging (this finding) as two separate, coexisting parts of the same Multilingual product — not as conflicting mechanisms. Turning on auto-switch does not, per Wix's own documentation, change or disable the hreflang tagging.

### Finding 12: The live site's current URL structure and hreflang output could not be confirmed in this spike

**Evidence:** A fetch of `https://www.4shark.com.br` returned only the rendered body content (Markdown-converted); no `<head>` element — and therefore no hreflang/canonical tags — was recoverable through this tool, and no language-switcher UI was visible in the rendered body either.

**Source:** direct fetch of `https://www.4shark.com.br` (this spike, current session)

**Significance:** This is a genuine gap, not a finding — see "What remains uncertain." It cannot be treated as evidence that hreflang tags or a language switcher are absent; the fetch tool's Markdown conversion is not a reliable way to inspect `<head>` content.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **A. Native Wix "Language auto-switch" toggle** | Zero infrastructure change; no DNS/Cloudflare touch; built by the platform that already generates hreflang/x-default tags (Finding 11); one toggle in the Wix dashboard (Finding 1); works for both `4shark.com.br` and `4shark.com` independently since each is its own Wix site | Requires each language to be an active secondary language already (Finding 2) — appears already true per the investigation brief; interacts with Wix's cookie banner (Finding 2); does not change what Googlebot sees, since Googlebot sends no Accept-Language (Finding 9) — that is actually the SEO-safe behavior, not a gap | Wix docs (Findings 1, 2, 11) |
| **B. Cloudflare proxy on the real domain + `http_request_dynamic_redirect` keyed on `accepted_languages`** | Reuses a ruleset shape already proven in this exact stack (Finding 6); Cloudflare's field model supports it natively (Finding 7) | Requires proxying `4shark.com.br` / `www.4shark.com.br` / `4shark.com`, which Wix documents as unsupported (Finding 4) and explains architecturally (SSL cert issuance/renewal, traffic-source identification — Finding 5); the "no real origin" trick that makes `app4shark.com.br` safe does not apply here because default-language traffic must still reach the live Wix origin (Finding 6); generic SEO caution against Accept-Language routing at the edge for crawlers (Finding 10) | Wix docs (Finding 4), tech-champion.com (Finding 5), local Terraform (Finding 6), Cloudflare docs (Finding 7), MERJ (Finding 10) |
| **C. Dedicated proxied hostname (mirroring the `app4shark.com.br` pattern)** | Technically safe — same no-real-origin shape as the existing redirect ruleset; does not touch the real Wix site or its DNS-only requirement | Only intercepts traffic 4Shark deliberately points at the dedicated hostname (ads, QR codes, email links) — does not affect anyone who types, bookmarks, or organically finds `4shark.com.br` / `4shark.com` directly, which is the traffic the investigation question is about (Finding 8) | Structural inference from Findings 4–6 (this spike) |
| **D. Do nothing (status quo)** | No risk, no effort | Every visitor keeps landing on Portuguese regardless of browser language — the stated problem persists | — |

## What remains uncertain

- Whether the Wix Multilingual "Language auto-switch" toggle is currently OFF (the most likely explanation for the described symptom) or ON but not functioning for another reason — this can only be confirmed inside the Wix dashboard, which is outside Claude's access boundary (per Production Access rules, this is a system the engineer would need to check or grant access to)
- Which URL structure (subdirectories, subdomains, or language parameters — Finding 3) `4shark.com.br` and `4shark.com` currently use — not discoverable via DNS or Terraform; requires the Wix dashboard
- Whether a visible language switcher is currently configured/published on the live site — a direct fetch of `https://www.4shark.com.br` in this session showed no switcher in the rendered body, but the fetch tool's Markdown conversion is not a reliable instrument for this check (Finding 12)
- The exact hreflang/x-default/canonical tags currently rendered in `<head>` on the live pages — same tooling limitation as above
- Whether Wix's Multilingual "Language auto-switch" is available on 4Shark's current Wix plan tier (the Wix docs reviewed here did not mention a plan restriction for auto-switch itself, only that subdomains — one of the three URL structures — require Premium; this was not independently cross-checked against 4Shark's specific Wix subscription)

## Suggested options for main and the engineer

- **Option A**: Enable Wix Multilingual's native "Language auto-switch" toggle (dashboard → Multilingual → Settings) for both `4shark.com.br` and `4shark.com`. No Terraform/DNS change. The evidence in Findings 1, 2, 9, 10, and 11 shows this is the mechanism Wix built specifically for this behavior, it coexists with Wix's own hreflang generation without documented conflict, and it does not touch what Googlebot indexes (Googlebot sends no Accept-Language header to begin with).
- **Option B**: Proxy the real domain through Cloudflare and add a `http_request_dynamic_redirect` ruleset keyed on `accepted_languages`, following the pattern already in `redirect_app4shark_com_br.tf`. The evidence in Findings 4, 5, and 6 shows this runs against Wix's own documented unsupported-configuration guidance and its stated architectural reason (SSL cert issuance/renewal + traffic-source identification), for the portion of traffic that must still reach the live Wix origin.
- **Option C**: Stand up a dedicated proxied hostname (mirroring `app4shark.com.br`) for language-based redirect, reserved for traffic 4Shark explicitly routes there (campaigns, QR codes). Per Finding 8, this does not address direct/organic/bookmarked traffic to the root domain, which is the traffic described in the investigation question.
- **Option D**: Leave the current configuration unchanged.
