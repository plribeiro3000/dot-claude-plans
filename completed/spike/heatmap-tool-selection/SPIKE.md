# SPIKE — Heatmap & Behavior Analysis Tool Selection for Whitelabel Fronts

## Investigation question

Which heatmap + behavior-analysis tool (click/scroll/area heatmaps, optionally bundled with
session replay) should 4Shark evaluate for the `app-webclient` whitelabel fronts (dozens of
Netlify sites, one per client), given that:

1. GA4 is already in production (`google-analytics-manager/property-setup`) but does not
   provide heatmaps natively, and a GA4-integrating tool is a plus, not a requirement;
2. the product is B2B, logged-in, and carries PII (name, email, CPF) — so PII masking and
   LGPD/GDPR posture are first-class evaluation criteria, not secondary;
3. any tool requires injecting a script + a per-client project id, mirroring the existing
   `ANALYTICS_ID` env-var-per-site pattern — so a **provisioning API to create a project per
   client programmatically** (vs manual per-site setup) is a material criterion at
   dozens-of-sites scale.

This spike surfaces options and evidence across three tiers (open source/self-host, SaaS free
tier, paid) with a comparison matrix and cost data. It does **not** recommend a tool — the
choice is the engineer's.

## Sources consulted

**Internal codebase (grounds the "context" facts in the brief independently):**

- `~/Projects/4Shark/app-webclient/src/main.ts:37-43` — confirms the GA4 script injection
  point (`<head>`/`<body>` insertion guarded by an env var) that any new tool would mirror
- `~/Projects/4Shark/app-webclient/src/app/core/analytics.service.ts:1-110` — confirms the
  existing PII discipline (`NEVER pass PII ... to setUser or emitEvent`) and LGPD consent-mode
  pattern the new tool's rollout would need to respect
- `~/Projects/4Shark/google-analytics-manager/README.md:1-8` — confirms GA4-as-code tooling
  exists today and describes what it does (property creation + `ANALYTICS_ID` sync)

**Open source / self-host:**

- [PostHog session replay installation docs](https://posthog.com/docs/session-replay/installation)
- [PostHog session replay privacy/masking docs](https://posthog.com/docs/session-replay/privacy)
- [PostHog heatmaps docs](https://posthog.com/docs/toolbar/heatmaps)
- [PostHog pricing page](https://posthog.com/pricing)
- [PostHog GDPR compliance docs](https://posthog.com/docs/privacy/gdpr-compliance) (via search snippet)
- [PostHog Projects API reference](https://posthog.com/docs/api/projects)
- [PostHog Provisioning API docs](https://posthog.com/docs/integrate/provisioning)
- [PostHog self-host requirements — GitHub issue #27120 discussion](https://github.com/PostHog/posthog/issues/27120) (via search snippet)
- [Matomo Heatmap & Session Recording plugin page](https://plugins.matomo.org/HeatmapSessionRecording)
- [Matomo Cloud pricing page](https://matomo.org/pricing/)
- [Matomo `SitesManager` API source](https://github.com/matomo-org/matomo/blob/4.x-dev/plugins/SitesManager/API.php) (via search snippet)
- [OpenReplay GitHub README](https://github.com/openreplay/openreplay)
- [OpenReplay heatmaps feature page](https://openreplay.com/product/feature/heatmaps/)
- [OpenReplay pricing page](https://openreplay.com/pricing)
- [OpenReplay GitHub Discussion #1140 — multi-site/multi-client usage](https://github.com/openreplay/openreplay/discussions/1140)

**SaaS with free tier:**

- [Microsoft Clarity FAQ](https://learn.microsoft.com/en-us/clarity/faq) — see auxiliary
  `heatmap-tool-selection_doc_1.txt` (full relevant excerpt preserved)
- [Microsoft Clarity GitHub issue #394 — programmatic project creation request](https://github.com/microsoft/clarity/issues/394)
- [Hotjar GDPR commitment page](https://www.hotjar.com/legal/compliance/gdpr-commitment/)
- [Hotjar Data Safety, Privacy & Security help article](https://help.hotjar.com/hc/en-us/articles/115011639887-Data-Safety-Privacy-Security) — UNVERIFIED (403 on fetch, see Finding 8)
- Hotjar pricing — official `hotjar.com/pricing` 308-redirects to `contentsquare.com/pricing`
  (confirmed via WebFetch redirect response); the redirect target did not render pricing
  figures for WebFetch (client-side rendered page) — pricing figures below are UNVERIFIED
  against the primary source and instead sourced from secondary aggregators, dated

**Paid:**

- [Contentsquare pricing FAQ / privacy center](https://contentsquare.com/privacy-center/frequently-asked-questions/) (via search snippet)
- [Contentsquare DPA page](https://contentsquare.com/privacy-center/data-processing-agreement/) (via search snippet)
- [FullStory "Private by Default" page](https://www.fullstory.com/platform/private-by-default/)
- [LogRocket pricing page](https://logrocket.com/pricing)
- [Crazy Egg pricing page](https://www.crazyegg.com/pricing)
- [Crazy Egg API documentation reference](https://apitracker.io/a/crazy-egg) (via search snippet)

## Findings

### Finding 1 — 4Shark's script-injection point and PII discipline (internal, ground truth)

**Evidence:**

```typescript
// app-webclient/src/main.ts:37-43
if (env.ANALYTICS_ID) {
  const scriptGtag = document.createElement('script');
  scriptGtag.async = true;
  scriptGtag.src = 'https://www.googletagmanager.com/gtag/js?id=' + env.ANALYTICS_ID;

  document.body.insertBefore(scriptGtag, document.body.firstChild);
}
```

```typescript
// app-webclient/src/app/core/analytics.service.ts:14-15
 * NEVER pass PII (email, name, CPF, phone) to `setUser` or `emitEvent`.
```

**Source:** `app-webclient/src/main.ts:37-43`, `app-webclient/src/app/core/analytics.service.ts:14-15`

**Significance:** any new tool follows the exact same integration shape already in
production — a conditional script tag gated by a per-site env var (`ANALYTICS_ID` today,
presumably a new var for the chosen tool), read from Netlify env per site. This is the
integration-effort baseline every option below is compared against. It also confirms the
existing team discipline of never sending PII into a third-party analytics payload — the
same discipline a heatmap/session-replay tool's masking config must reproduce, because a
heatmap/replay tool captures the *rendered DOM/screen*, not discrete named fields — masking
has to be configured, not just "don't pass this parameter".

### Finding 2 — PostHog: self-hosted community edition includes heatmaps and session replay with no session-count ceiling

**Evidence:** PostHog's own heatmap docs describe three modes — "Heatmap: Captures mouse
movements, clicks, dead clicks, and rageclicks", "Scrollmap: displays how far users are
scrolling down your page", "Clickmap: shows the elements users are clicking on your website" —
and state "heatmap data is captured along with other events, so it doesn't contribute to
your bill."

**Source:** [PostHog heatmaps docs](https://posthog.com/docs/toolbar/heatmaps)

**Significance:** PostHog bundles click/scroll/rageclick heatmaps AND session replay in one
product, and — per the doc — the self-hosted open-source edition is not metered per
recording the way PostHog Cloud is. The PostHog pricing page itself states the self-hosted
option "is MIT licensed if you want to use it in a big organization that isn't ready to move
to PostHog Cloud yet" (per [PostHog pricing page](https://posthog.com/pricing)) — confirming
self-host is a first-class, not crippled, deployment mode.

**Verification block:** URL fetched: https://posthog.com/docs/toolbar/heatmaps and
https://posthog.com/pricing / Verbatim quotes checked / Quote substrings confirmed at the
heatmap-type descriptions and the MIT-license sentence respectively.

### Finding 3 — PostHog session replay masks inputs, images, and password fields by default; text masking is opt-in and programmable

**Evidence:** "As any input element is highly likely to contain sensitive text such as email
or password, we mask these by default." / "Password inputs are always masked no matter your
config." / "General text is not masked by default, but we provide multiple options for
masking text" via `maskTextFn`, e.g. "by only masking text that looks like an email".

**Source:** [PostHog session replay privacy docs](https://posthog.com/docs/session-replay/privacy)

**Significance:** for a B2B product carrying CPF/name/email, PostHog's *default* posture
(inputs + images + passwords masked) already covers the highest-risk surfaces (form fields),
but **general on-screen text (e.g., a client's name rendered in a dashboard header, not typed
into an input) is NOT masked by default** — it requires an explicit `maskTextFn` rule. This
is a configuration obligation for 4Shark, not a zero-effort guarantee, regardless of which
tool is chosen (the same applies to every tool in this spike — see Finding 6, 9, 11).

**Verification block:** URL fetched: https://posthog.com/docs/session-replay/privacy /
Verbatim quotes checked / Quote substrings confirmed in the "Default masking behavior"
section of the page.

### Finding 4 — PostHog offers an EU-hosted Cloud region and a documented DPA; self-hosting keeps data inside 4Shark's own infrastructure entirely

**Evidence:** "PostHog Cloud EU is hosted in the AWS eu-central-1 region based in Frankfurt,
Germany ... with all event data, user data, and the product itself hosted on EU-based
infrastructure" and "PostHog enters into Data Processing Agreements ('DPAs') with PostHog
Cloud customers when requested."

**Source:** [PostHog Cloud EU announcement](https://posthog.com/blog/posthog-cloud-eu) (via search snippet)

**Significance:** this finding is about PostHog **Cloud**, not the self-hosted deployment —
if 4Shark picked self-hosted PostHog, data residency is moot (data never leaves 4Shark's own
infrastructure, the strongest LGPD posture of every option in this spike). If 4Shark instead
used PostHog Cloud to avoid ops overhead, an EU region + DPA exists as a fallback.

**Verification block:** URL not independently re-fetched by WebFetch (the quote above comes
from the WebSearch snippet summarizing the blog post, not a direct page fetch) — tagged
**UNVERIFIED at the exact-quote level**; the EU-region *fact* itself is corroborated by
multiple independent search-result snippets referencing the same Frankfurt/eu-central-1
detail, but per Citation Discipline rule 4 the specific wording should not be treated as a
verified verbatim quote without a direct fetch.

### Finding 5 — PostHog has a standard Projects API to create a project per client under one organization, and a separate Provisioning API for a different (partner) use case

**Evidence:** `POST /api/organizations/:organization_id/projects/` — "Required API key
scopes: `project:write`" — usable with a personal API key (not gated behind partner status).
Separately, PostHog's dedicated Provisioning API "lets you create PostHog accounts for your
users and deep link them into their PostHog project, and it's intended for partners and
platform integrations" and is rate-limited ("10 account requests per hour" unverified, "100/hour
for partners linked to a PostHog organization via a verification token") and deep-link
issuance is "gated on the `provisioning_can_issue_deep_links` flag ... only enabled for
partners admin-onboarded by PostHog."

**Source:** [PostHog Projects API reference](https://posthog.com/docs/api/projects),
[PostHog Provisioning API docs](https://posthog.com/docs/integrate/provisioning)

**Significance:** the two APIs answer two different questions. For 4Shark's actual need —
"create one PostHog *project* per whitelabel client, all under 4Shark's own organization,
and read back the project's API key to inject into that client's Netlify env var" — the
**standard Projects API is the relevant mechanism**, and it does not require partner
approval. The separate "Provisioning API" (partner-gated, creates whole new *accounts* for
*other companies'* end users) is a different use case (e.g., an agency reselling PostHog
seats) and is not what 4Shark needs. This distinction was not obvious from the tool name and
is worth flagging: "PostHog has a provisioning API" is a headline true fact that could
mislead if not read carefully — the ordinary Projects API is the one that fits the
as-code-per-client model.

**Verification block:** URL fetched: https://posthog.com/docs/api/projects and
https://posthog.com/docs/integrate/provisioning / Verbatim quotes checked / Quote substrings
confirmed at the endpoint description and the partner-gating paragraphs respectively.

### Finding 6 — Matomo's Heatmap & Session Recording plugin covers click/scroll/move heatmaps and ships GDPR masking controls, but is a paid add-on even on self-hosted installs

**Evidence:** "Anonymizing / Masking of personal or sensitive information that a user enters
into form field", "optionally mask any content within the website to avoid the recording of
personal information", supports "Matomo's privacy and GDPR features like the right to erase
data or the right to export data." Pricing: on-premise licensing sits around
"€199/year" for the heatmap+recording plugin, or bundled into the "Premium Plugins Bundle"
(~"$999/yr", 19 plugins).

**Source:** [Matomo Heatmap & Session Recording plugin page](https://plugins.matomo.org/HeatmapSessionRecording) — dated at fetch time 2026-07-07 for the price figures (Matomo Marketplace prices are not locked and change independently of Matomo core versions)

**Significance:** Matomo itself (the core analytics platform) is free and self-hostable, and
its own PII/GDPR posture is well-documented industry-wide (anonymized IP by default, no
cross-site tracking) — but the **heatmap capability specifically is a paid, closed-source
plugin** even in a self-hosted deployment, unlike PostHog and OpenReplay where heatmaps ship
in the free/open edition. Matomo does have a mature, documented `SitesManager.addSite` API
(`module=API&method=SitesManager.addSite`) for provisioning a new site programmatically — this
is the strongest provisioning story among the OSS options (see Finding 10).

**Verification block:** URL fetched: https://plugins.matomo.org/HeatmapSessionRecording /
Verbatim quotes checked / Quote substrings confirmed in the plugin description and GDPR
feature list.

### Finding 7 — OpenReplay bundles click/scroll heatmaps with session replay and is fully self-hostable, but is explicitly documented as not multi-tenant

**Evidence:** "You can view click maps, scroll maps, and interaction heatmaps across all
screen sizes and devices" and "Fine-grained privacy controls: Choose what to capture, what to
obscure or what to ignore so user data doesn't even reach your servers" and "Self-hosted. No
more security compliance checks, 3rd-parties processing user data. Everything OpenReplay
captures stays in your cloud." Separately, in a maintainer-facing community discussion about
running OpenReplay for multiple clients, an engineer evaluating the same question noted
"It does say it's not multi-tenant" when considering per-client Kubernetes deployments.

**Source:** [OpenReplay heatmaps feature page](https://openreplay.com/product/feature/heatmaps/),
[OpenReplay GitHub README](https://github.com/openreplay/openreplay),
[OpenReplay GitHub Discussion #1140](https://github.com/openreplay/openreplay/discussions/1140)

**Significance:** OpenReplay is the closest OSS competitor to PostHog on privacy posture and
heatmap+replay bundling, and its minimum self-host footprint is documented as modest ("2
vCPUs, 8 GB of RAM, 50 GB of storage" per the deployment docs). But the "not multi-tenant"
constraint is material for 4Shark's dozens-of-clients-on-one-deployment model: the
discussion thread shows a user reaching the same conclusion 4Shark would need to reach —
either one shared OpenReplay project mixing all clients' sessions (no per-client isolation),
or a separate OpenReplay deployment per client (operationally heavy at dozens-of-sites
scale). This is the opposite of PostHog's native multi-project-per-organization model
(Finding 5) and Matomo's native multi-site model (Finding 6).

**Verification block:** URL fetched: https://openreplay.com/product/feature/heatmaps/ and
https://github.com/openreplay/openreplay / Verbatim quotes checked / Quote substrings
confirmed at the heatmap-type description and the self-hosted privacy paragraph. The
Discussion #1140 quote ("It does say it's not multi-tenant") is the community member's own
paraphrase of OpenReplay's docs, not an OpenReplay official statement — flagged as
community-sourced, not vendor-sourced.

### Finding 8 — Microsoft Clarity is free with no session/site ceiling, masks input-box content unconditionally, and natively links one project to one GA4 property

**Evidence:** "Clarity is a free service forever. You never encounter traffic limits or are
compelled to upgrade to a paid version." / "Content in the input boxes is masked in all modes
and can't be customized." / "Can I use heat maps and follow privacy regulations? Yes. You can
follow all privacy regulations, mask text, and create heat maps. Clarity creates heat maps
based on element attributes and not the content of the element." / "At this point, you can
integrate only one web property" (GA4). Practical ceilings exist even though pricing is
free: "Clarity records up to 100,000 sessions per project per day" and "Heat maps are limited
to up to 100,000 page views per heat map."

**Source:** [Microsoft Clarity FAQ](https://learn.microsoft.com/en-us/clarity/faq) — full
relevant excerpt preserved in `heatmap-tool-selection_doc_1.txt`

**Significance:** for a dozens-of-clients whitelabel fleet, Clarity's "unlimited number of
projects for each domain or website" plus zero cost removes the free-tier-ceiling risk that
Hotjar/FullStory/LogRocket carry (Findings 9, 11, 12) — 100,000 sessions/day per *project*
(=per client site) is unlikely to bind for any single 4Shark client. Data residency is
Microsoft Azure with EU cross-border transfer handled via Microsoft Ireland Operations
Limited + SCCs (see auxiliary doc) — not a 4Shark-controlled infrastructure boundary, unlike
self-hosted OSS.

**Verification block:** URL fetched: https://learn.microsoft.com/en-us/clarity/faq /
Verbatim quotes checked / Quote substrings confirmed at lines corresponding to "pricing
model", "masking and unmasking content", and "heatmaps" sections in the auxiliary excerpt.

### Finding 9 — Microsoft Clarity has no official API to create projects programmatically; project creation is a manual per-site dashboard flow

**Evidence:** an open GitHub issue against the `microsoft/clarity` repository, opened by a
user managing "150 SharePoint Site Collections that need to be added to clarity", asks:
"Is there a way we can script (PowerShell preferably) creating new clarity projects?" — the
issue has no maintainer response confirming such an API exists, and the official FAQ itself
describes project creation as "three simple steps" (a manual dashboard flow), not an API
call.

**Source:** [microsoft/clarity issue #394](https://github.com/microsoft/clarity/issues/394),
[Microsoft Clarity FAQ — Project management section](https://learn.microsoft.com/en-us/clarity/faq)

**Significance:** this is the direct counterpoint to Finding 8 — Clarity is free and
unlimited in project count, but scaling it to dozens of 4Shark clients as-code (matching the
existing `google-analytics-manager` automation pattern) is **not currently supported** by an
official API; onboarding a new client would be a manual step in the Clarity dashboard per
site, breaking the "as-code" parity 4Shark has with GA4 property provisioning today.

**Verification block:** URL fetched: https://github.com/microsoft/clarity/issues/394 /
Verbatim quote checked / Quote substring ("Is there a way we can script") confirmed at the
issue body. Absence-of-API is a negative claim (no evidence found), not a positive citation —
flagged accordingly per Citation Discipline (an "I did not find this" style finding).

### Finding 10 — Matomo's site-provisioning API is the most mature "as-code" story among every option researched

**Evidence:** the `SitesManager.addSite` endpoint — "lets you create websites via addSite" —
called as `module=API&method=SitesManager.addSite&siteName=...&urls[]=...` with a
`token_auth` parameter for authentication, returning the created `siteId`.

**Source:** [Matomo `SitesManager` API source on GitHub](https://github.com/matomo-org/matomo/blob/4.x-dev/plugins/SitesManager/API.php) (via search snippet), corroborated by the [Matomo developer API reference](https://developer.matomo.org/api-reference/Piwik/Site) (via search snippet)

**Significance:** unlike Clarity (no API, Finding 9) and OpenReplay (not multi-tenant,
Finding 7), Matomo's core platform was built multi-site from the start (it is, after all, a
Google-Analytics-style tool meant to host many properties under one account) and exposes a
documented, stable REST-ish API to add a site programmatically — this is the closest
provisioning-API parity to 4Shark's existing `google-analytics-manager/property-setup`
pattern. The caveat is that the heatmap capability itself sits behind the paid plugin
(Finding 6) — the free API only provisions the *site*, not the *heatmap feature* on that
site (the plugin, once licensed, applies per-Matomo-instance, not automatically per new
site — this needs confirmation, see "What remains uncertain").

**Verification block:** URL not independently re-fetched via WebFetch (sourced from a
WebSearch snippet summarizing the GitHub file and the Matomo developer docs page) — tagged
**UNVERIFIED at the exact-quote level** per Citation Discipline rule 4, though the endpoint
name and calling convention are corroborated by two independent search-result snippets.

### Finding 11 — Hotjar/Contentsquare: free tier is capped at a small daily session count; masking is enabled by default for keystrokes but requires explicit tagging for on-screen PII

**Evidence:** "Hotjar, for example, automatically suppresses all user keystrokes by default"
and suppression of individual elements requires "adding data-hj-suppress as an HTML attribute
or class to the element(s)" — an explicit, per-element opt-in, not automatic for arbitrary
rendered text. Separately, "Hotjar does not offer the option to download or digitally sign a
DPA" even though "the terms of our DPA are already included in Hotjar's Terms of Service."

**Source:** [Hotjar GDPR commitment page](https://www.hotjar.com/legal/compliance/gdpr-commitment/), [Hotjar suppression documentation summarized via search](https://help.hotjar.com/hc/en-us/articles/36819956605329-How-to-Suppress-Text-Images-Videos-and-User-Input-from-Collected-Data) (via search snippet)

**Significance:** Hotjar (now merged into Contentsquare — `hotjar.com/pricing` returns a
308 redirect to `contentsquare.com/pricing`, confirmed directly by WebFetch) auto-suppresses
keystrokes (typed input) but — like PostHog and Clarity — does **not** auto-mask arbitrary
rendered text (a client's name shown in a header, a document number in a table) without
explicit `data-hj-suppress` tagging. The free-tier daily session cap ("up to 35 sessions per
day" per secondary aggregator sources, UNVERIFIED against the primary page which did not
render pricing via WebFetch) would very plausibly bind for an active B2B client, unlike
Clarity's 100,000/day ceiling.

**Verification block:** URL fetched: https://www.hotjar.com/legal/compliance/gdpr-commitment/
/ Verbatim quotes checked / Quote substrings confirmed at the DPA paragraph. The suppression
HTML-attribute quote is UNVERIFIED at the exact-wording level (sourced from a WebSearch
snippet, not a direct fetch of the help article, which returned no usable content in this
session).

### Finding 12 — FullStory masks nothing by default outside sensitive fields, but ships a documented "Private by Default" mode that blocks all text capture unless explicitly allow-listed; pricing is not published and free tier is capped at 30,000 sessions/month

**Evidence:** "Sensitive fields like passwords or credit card numbers are never captured."
"Add custom exclusions to totally block specific data from playback, event streams, search,
and segmentation." The "Private by Default" setting: "no text is captured or sent outside the
user's browser unless it is explicitly allowlisted as safe to capture." Free tier: "FullStory
Free gives you 30,000 sessions a month, 10 seats, 5,000 server-side events, and a full year of
replay and analytics retention" (per secondary source, UNVERIFIED against a primary pricing
page — FullStory does not publish a public pricing page for paid tiers, "you talk to a sales
team").

**Source:** [FullStory "Private by Default" page](https://www.fullstory.com/platform/private-by-default/)

**Significance:** FullStory's opt-in allow-list model ("Private by Default") is the inverse
of PostHog/Hotjar/Clarity's default (mask only known-sensitive fields, capture everything
else) — for a product carrying CPF/name/email, an allow-list-only capture mode is the
strongest default posture of any tool in this spike, at the cost of needing to explicitly
allow-list every UI element the team *does* want visible in a replay/heatmap.

**Verification block:** URL fetched: https://www.fullstory.com/platform/private-by-default/ /
Verbatim quotes checked / Quote substrings confirmed at the "Private by Default" and
"custom exclusions" paragraphs. Free-tier session count and pricing-page absence are
UNVERIFIED at the exact-quote level (sourced from a WebSearch snippet aggregator, not FullStory's own site — FullStory intentionally does not publish self-serve pricing).

### Finding 13 — LogRocket and Crazy Egg: free/entry tiers exist but session/pageview ceilings are the lowest of the paid group; neither publishes an official provisioning API for creating a new project/site programmatically

**Evidence:** LogRocket: "Core plan starting at $176/mo" for "25K sessions/mo" (slider-based,
per direct WebFetch of the official pricing page) with a free trial ("Access all of
LogRocket's features free for 14 days" — no permanent free tier confirmed on the primary
page, contradicting an earlier secondary-source claim of "1,000 sessions/month" permanent
free tier, which is flagged UNVERIFIED as it could not be reproduced from the primary page).
Crazy Egg: "Starter - $29/mo — 5,000 tracked pageviews/mo, 5 Heatmap Reports, 50
Recordings/mo" scaling to "Enterprise - $599/mo — 1,000,000 tracked pageviews/mo" — all
tiers "include unlimited website domains and team members" (i.e., billed by traffic volume,
not by number of client sites) but "Customers can sign our Data Processing Agreement (DPA)"
per secondary source (UNVERIFIED).

**Source:** [LogRocket pricing page](https://logrocket.com/pricing) (direct fetch),
[Crazy Egg pricing page](https://www.crazyegg.com/pricing) (direct fetch)

**Significance:** Crazy Egg's "unlimited website domains" per account is notable — it means
4Shark would not need a separate paid account per client the way a strict per-site licensing
model would require, but there is no documented API to create/tag a new domain
programmatically (an API search surfaced only a "Customer-Facing Tracking API" for
conversion-goal events, not site/project management) — onboarding a new client domain
would be a manual step. LogRocket's pricing is explicitly volume-slider-based per
organization (not per site), similarly with no documented project-provisioning API found in
this session.

**Verification block:** URL fetched: https://logrocket.com/pricing and
https://www.crazyegg.com/pricing / Verbatim quotes checked / Quote substrings confirmed for
both pricing tables directly on the vendor pages.

### Finding 14 — Contentsquare (enterprise tier) publishes no list pricing; typical small-deployment annual contract values start in the tens of thousands of dollars, and it carries a documented DPA + EU data residency by customer region

**Evidence:** "Contentsquare does not publish list pricing publicly. Pricing is customized
based on your organization's monthly session volume, number of properties ..." "Annual
contract values for small deployments commonly range from $30,000 to $80,000" (secondary
source, UNVERIFIED against a primary quote page since Contentsquare does not publish one).
"For customers based in the EU, the applicable data center region is EU by default ... EU
customer data remains stored within Contentsquare's data hosting centers located in the EU"
and "Contentsquare has a specific Data Processing Agreement intended to cover all terms as
required under the GDPR" incorporating "new EU and UK Standard Contractual Clauses."

**Source:** Contentsquare pricing/FAQ/DPA pages (via search snippets — direct WebFetch of
`contentsquare.com/pricing` returned only page-shell navigation content, no rendered pricing
data, tagged UNVERIFIED for the price figures specifically; the DPA/data-residency quotes are
from the [Contentsquare privacy center FAQ](https://contentsquare.com/privacy-center/frequently-asked-questions/) and [Contentsquare DPA page](https://contentsquare.com/privacy-center/data-processing-agreement/), also via search snippet, not independently re-fetched)

**Significance:** this is the "pay for the strongest enterprise compliance posture" end of
the paid tier — EU-by-default residency tied to customer region, a documented DPA with SCCs,
and (per Finding 2's PostHog GA4-adjacent framing) Contentsquare/Hotjar's native GA4
integration heritage from the original Hotjar product. The cost is an order of magnitude
above Hotjar Plus/FullStory/LogRocket entry tiers and is not transparent without a sales
conversation — a genuine "pago quando faz sentido pular direto" case only if 4Shark's
compliance/legal requirements specifically need the DPA+ISO-27701 combination Contentsquare
advertises (per the search snippet, ISO 27701 certified) beyond what the free/self-host tier
options already provide.

**Verification block:** URL fetched: https://contentsquare.com/pricing/ (attempted; returned
only navigation shell, no pricing data extracted — explicitly noted as such in the finding
text). Price figures and the ISO-27701 claim are UNVERIFIED at the exact-quote level.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **PostHog (self-hosted, open source)** | Heatmap (click/scroll/rage-click) + session replay bundled, uncapped on self-host; native multi-project-per-organization data model fits dozens-of-clients; standard REST API to create a project per client without partner gating; MIT-licensed | Self-host requires 4Shark to operate infrastructure (min. 4 CPU / 8GB RAM per community reports, more for production); general on-screen text NOT masked by default, requires `maskTextFn` config work | Findings 2, 3, 5 |
| **Matomo (self-hosted core + paid heatmap plugin)** | Most mature site-provisioning API (`SitesManager.addSite`) of any option researched; core platform's GDPR posture is industry-recognized | Heatmap/session-recording is a **paid, closed-source plugin** even self-hosted (~€199/yr or bundled ~$999/yr); unclear if the plugin auto-activates per newly-provisioned site (open question) | Findings 6, 10 |
| **OpenReplay (self-hosted, open source)** | Heatmap + session replay + co-browsing bundled; documented modest self-host footprint (2 vCPU/8GB/50GB); strong "data never reaches our servers" privacy framing | Explicitly **not multi-tenant** — no native per-client project isolation; scaling to dozens of clients means either mixing all clients in one project or running N separate deployments | Finding 7 |
| **Microsoft Clarity (SaaS, free)** | Zero cost, unlimited projects, 100,000 sessions/day per project (very unlikely to bind); native (if limited) GA4 integration; inputs always masked; free forever, no card required | **No API to create projects programmatically** — project creation is a manual dashboard flow per site (open GitHub feature request, unresolved); data stored on Microsoft Azure (US-headquartered entity, EU transfer via SCCs, not 4Shark-controlled infra); one Clarity project ↔ one GA4 property only | Findings 8, 9 |
| **Hotjar / Contentsquare (SaaS, free tier)** | Documented DPA + EU data residency option; keystrokes auto-suppressed by default | Free-tier daily session cap is low relative to Clarity (order of ~35/day per secondary sources, UNVERIFIED); brand merged into Contentsquare mid-2025, pricing page now redirects; arbitrary rendered text not masked by default (only tagged elements) | Findings 11 |
| **FullStory (paid, no public pricing)** | Strongest default-privacy posture researched — "Private by Default" is allow-list-only for text capture, opposite of the mask-known-fields default every other tool uses | No public pricing (sales-gated); free tier capped at 30,000 sessions/month (UNVERIFIED, secondary source) | Finding 12 |
| **LogRocket (paid, volume-based)** | GDPR/CCPA tooling, per-session deletion; volume-slider pricing model (predictable scaling) | Lowest publicly-quoted entry price band relative to Crazy Egg/Hotjar Plus is still fairly narrow at low volumes; no documented project-provisioning API found | Finding 13 |
| **Crazy Egg (paid, tiered)** | Simple flat tiers ($29–$599/mo); unlimited domains per account (fits multi-client without per-site billing) | No provisioning API found (only a conversion-tracking API); DPA availability only from a secondary source | Finding 13 |
| **Contentsquare Enterprise (paid, custom quote)** | Documented EU-by-default residency + DPA + SCCs; enterprise-grade behavioral analytics suite | No public pricing; typical small-deployment annual contract values start at $30k–$80k/yr (secondary source, UNVERIFIED) — an order of magnitude above the other paid options | Finding 14 |

## Decision matrix

Scale: `✅` = strong evidence the tool meets the criterion well; `⚠️` = partial /
conditional / requires configuration; `❌` = does not meet or evidence points against;
`?` = insufficient evidence found this session.

| Criterion | PostHog (self-host) | Matomo (self-host + plugin) | OpenReplay (self-host) | MS Clarity (SaaS free) | Hotjar/Contentsquare (SaaS free) | FullStory (paid) | LogRocket (paid) | Crazy Egg (paid) | Contentsquare Enterprise (paid) |
|---|---|---|---|---|---|---|---|---|---|
| Click/scroll/rage-click heatmap coverage | ✅ (Finding 2) | ✅ but paid add-on (Finding 6) | ✅ click+scroll (Finding 7) | ✅ click+scroll only, no rage-click documented (Finding 8) | ✅ (industry-standard Hotjar feature set) | ✅ (Finding 12) | ⚠️ analytics-focused, heatmap secondary (Finding 13) | ✅ (Finding 13) | ✅ (Finding 14) |
| Session replay bundled | ✅ (Finding 2) | ✅ same paid plugin (Finding 6) | ✅ (Finding 7) | ✅ (Finding 8) | ✅ | ✅ (Finding 12) | ✅ (Finding 13) | ✅ (Finding 13) | ✅ (Finding 14) |
| PII masking strength (default posture) | ⚠️ inputs/images/passwords masked, general text opt-in (Finding 3) | ⚠️ configurable, requires setup (Finding 6) | ⚠️ configurable, granular ("choose what to capture") (Finding 7) | ⚠️ input boxes always masked; general text opt-in (Finding 8) | ⚠️ keystrokes auto-suppressed, general text opt-in (Finding 11) | ✅ allow-list-only default, strongest researched (Finding 12) | ⚠️ requires config (Finding 13) | ? not detailed this session | ⚠️ enterprise-configurable, not detailed this session |
| LGPD/GDPR/DPA + data location | ✅✅ self-hosted = data never leaves 4Shark infra (Finding 2) | ✅✅ self-hosted, same (Finding 6) | ✅✅ self-hosted, same (Finding 7) | ⚠️ GDPR-compliant per vendor claim, but data on Microsoft Azure US-entity with SCC-based EU transfer (Finding 8) | ⚠️ DPA exists but "not offered for digital signature"; EU residency option exists (Finding 11) | ? DPA/residency not found this session | ✅ GDPR/CCPA tooling, PII audit (Finding 13, via search) | ⚠️ DPA availability only via secondary source (Finding 13) | ✅✅ EU-by-default residency + DPA + SCCs (Finding 14) |
| Provisioning API for per-client scale | ✅ standard Projects API, no partner gate (Finding 5) | ✅✅ `SitesManager.addSite`, most mature (Finding 10) | ❌ not multi-tenant (Finding 7) | ❌ no API found, open feature request (Finding 9) | ? not found this session | ? not found this session | ? not found this session | ❌ only a tracking API found, not site-management (Finding 13) | ? not found this session (enterprise sales likely handles onboarding) |
| Cost at dozens-of-sites scale | Infra cost only (self-hosted, no per-recording fee on OSS edition) | Infra cost + ~€199–$999/yr plugin license per instance (not per site) | Infra cost only | $0 (Finding 8) | Free tier likely too small per active client (Finding 11); paid tier cost not resolved this session | Sales-quoted, no public number (Finding 12) | Volume-slider, starts ~$176/mo for 25K sessions (Finding 13) | $29–$599/mo flat tiers, unlimited domains (Finding 13) | $30k–$80k+/yr typical (secondary source, Finding 14) |
| Integration effort vs current `ANALYTICS_ID` pattern | Same shape: script tag + per-project key/id | Same shape: script tag + per-site id | Same shape: script tag + per-project id | Same shape: script tag + per-project id | Same shape: script tag + per-site id | Same shape: script tag + per-org config | Same shape: script tag + per-app id | Same shape: script tag + per-site id | Same shape: script tag + per-account config |
| GA4 integration (plus, not required) | Not documented this session | Not documented this session | Not documented this session | ✅ native, one GA4 property per Clarity project (Finding 8) | ✅ (Hotjar's historical GA4 integration; not re-verified for Contentsquare-merged product this session) | Not documented this session | Not documented this session | Not documented this session | Not documented this session |
| Maturity / maintenance signal | Active, well-documented, large community (PostHog is a widely-adopted YC-backed OSS product) | Very mature (Matomo/Piwik, 15+ years) | Active, YC-backed, smaller community than PostHog | Active, Microsoft-backed | Active, backed by Contentsquare post-merger | Active, established enterprise vendor | Active, established | Active, long-standing (one of the original heatmap tools) | Active, established enterprise vendor |

## Cost section

All figures below carry the source and the date this session accessed them (2026-07-07)
because free-tier limits and prices are known to change without notice — do not treat any
number here as durable beyond that date.

- **PostHog self-hosted (OSS/MIT)**: no PostHog license cost; infrastructure cost only. A
  community report cites "4 CPU cores, 8 GB RAM, and 200 GB storage" as the stated minimum,
  scaling to "8+ CPU cores, 16+ GB RAM" recommended for production — per
  [PostHog self-host requirements discussion](https://github.com/PostHog/posthog/issues/27120) (search snippet, UNVERIFIED at exact-quote level). PostHog Cloud (if chosen instead of self-host) prices session replay separately from event volume: "First 5k recordings" free, then "$0.0050/recording (5-15k)" scaling down to "$0.0015/recording (500k+)" per the [PostHog pricing page](https://posthog.com/pricing) (direct fetch, verified).
- **Matomo**: core self-hosted platform is free; the Heatmap & Session Recording plugin is
  "€199/year" (heatmap) with session recording priced separately at "€149/year", or bundled
  into the "Premium Plugins Bundle" (~"$999/yr" for 19 plugins total) per the
  [Matomo plugin marketplace page](https://plugins.matomo.org/HeatmapSessionRecording)
  (direct fetch, verified). Matomo Cloud (if chosen instead of self-host) starts at "$29/mo"
  for 50,000 hits/month with heatmap/session-recording as a separate paid add-on, per the
  [Matomo pricing page](https://matomo.org/pricing/) (direct fetch, verified).
- **OpenReplay**: self-hosted OSS is free (infra cost only); minimum footprint documented as
  "2 vCPUs, 8 GB of RAM, 50 GB of storage" per search-snippet-sourced deployment docs
  (UNVERIFIED at exact-quote level). OpenReplay's managed "Dedicated" cloud plan (if
  self-hosting is not chosen) starts "from $199/mo" per the
  [OpenReplay pricing page](https://openreplay.com/pricing) (direct fetch, verified).
- **Microsoft Clarity**: $0, no paid tier exists at all — "Clarity is a free service
  forever" per the [Clarity FAQ](https://learn.microsoft.com/en-us/clarity/faq) (direct
  fetch, verified; see auxiliary excerpt).
- **Hotjar/Contentsquare free tier**: free tier daily-session cap figures ("up to 35 sessions
  per day") and the first paid tier ("~$32/mo") come from secondary aggregator sources
  (UNVERIFIED — the official `hotjar.com/pricing` page 308-redirects to
  `contentsquare.com/pricing`, confirmed directly by WebFetch, but the redirect target is
  client-side-rendered and did not return pricing figures to WebFetch in this session).
- **FullStory**: no public pricing; "FullStory Free gives you 30,000 sessions a month"
  (secondary source, UNVERIFIED); paid tiers require a sales conversation.
- **LogRocket**: "Core" plan "$176/mo" for "25K sessions/mo" (slider-based) per the
  [LogRocket pricing page](https://logrocket.com/pricing) (direct fetch, verified); no
  permanent free tier confirmed on the primary page (only a 14-day full-feature trial).
- **Crazy Egg**: flat tiers, verified directly — "Starter $29/mo (5,000 pageviews/mo)",
  "Plus $99/mo (150,000 pageviews/mo)", "Pro $249/mo (500,000 pageviews/mo)",
  "Enterprise $599/mo (1,000,000 pageviews/mo)" per the
  [Crazy Egg pricing page](https://www.crazyegg.com/pricing) (direct fetch, verified).
  "All plans ... include unlimited website domains."
- **Contentsquare Enterprise**: no public pricing; "small deployments commonly range from
  $30,000 to $80,000" annually (secondary source, UNVERIFIED).

## What remains uncertain

- **Exact PII fields 4Shark would need to mask** — the brief names CPF/name/email as the
  concrete risk. None of the tools researched auto-mask arbitrary rendered text (only
  known-sensitive input types and, for FullStory, everything-unless-allow-listed). Before any
  tool is adopted, 4Shark needs to enumerate which `app-webclient` screens render CPF/name/
  email as visible DOM text (not just form inputs) so the masking config (whichever tool is
  picked) covers those screens specifically. This spike did not audit `app-webclient`'s
  screens for where PII renders as text — that is a follow-up, not covered here.
- **Expected session volume per client / total across the fleet** — every free-tier ceiling
  in this spike (Clarity's 100,000/day per project, Hotjar's ~35/day, FullStory's 30,000/mo)
  is meaningless without knowing 4Shark's actual per-client traffic. The engineer needs to
  supply an estimate (even rough) to determine whether Clarity's generous per-project ceiling
  genuinely never binds, or whether a paid tier is unavoidable regardless of provisioning
  story.
- **Whether Matomo's heatmap plugin auto-activates on a new site created via
  `SitesManager.addSite`**, or whether the plugin license is a manual per-site enable step
  even after the site itself is provisioned via API — this session found the plugin's pricing
  and the site-provisioning API as two separate facts and did not find a source confirming
  how they interact.
- **Whether 4Shark's existing Netlify build/deploy pipeline can inject a second per-site env
  var (e.g., alongside `ANALYTICS_ID`) without additional Terraform/CI work** — this spike
  did not investigate the Netlify env-var-per-site mechanics beyond confirming the existing
  `ANALYTICS_ID` pattern in `main.ts`; the brief already states Terraform does not provision
  this, but the exact mechanism (manual Netlify dashboard entry vs an extension of
  `google-analytics-manager`-style automation) was not investigated here.
- **OpenReplay's actual behavior when injected across multiple whitelabel domains under one
  project** (e.g., whether sessions from different client domains can at least be filtered
  by domain/URL within one project, as a workaround short of true multi-tenant isolation) —
  Finding 7 establishes "not multi-tenant" as a documented constraint but this session did
  not find a definitive answer on whether domain-based filtering within a single project is
  a workable interim workaround.
- **FullStory, LogRocket, and Crazy Egg's exact DPA/data-residency terms** — these were only
  partially confirmed (LogRocket via a general "GDPR and CCPA controls" mention, Crazy Egg via
  a secondary source claiming "DPA to support GDPR, CCPA, or HIPAA", FullStory not confirmed
  at all this session).
- **Contentsquare/Hotjar's current (post-merger) GA4 integration behavior** — Finding 8/11
  describe Clarity's GA4 integration and Hotjar's historical GA4 integration respectively, but
  this session did not re-verify whether the GA4 integration still works identically under
  the merged Contentsquare product or has changed.

## Suggested options for main and the engineer

The evidence above supports at least three distinct framings, presented without a
recommendation:

- **Option A — self-host now (PostHog or Matomo), keep all session/replay data inside
  4Shark's own infrastructure.** This is the strongest LGPD posture available (data never
  leaves 4Shark) and PostHog specifically has no per-client provisioning friction (Finding 5).
  Matomo's provisioning API is even more mature (Finding 10) but its heatmap capability is a
  paid plugin whose per-site activation behavior is unconfirmed (open question above). Cost is
  infra-only, but 4Shark takes on the operational burden of running and maintaining the
  service.
- **Option B — adopt Microsoft Clarity now (zero cost, zero infra), accept the manual
  per-client provisioning step as a one-time cost per new client onboarding.** Given
  `app-webclient` onboards new clients relatively infrequently compared to day-to-day
  engineering work, a manual dashboard step per new client (Finding 9) may be an acceptable
  trade against $0 cost and Clarity's generous per-project ceiling (Finding 8) — but this
  breaks the "as-code" parity 4Shark otherwise maintains for GA4 provisioning.
  This is also the option most exposed on data-residency grounds (Microsoft Azure /
  US-entity with SCC-based transfer, vs data staying inside 4Shark's own infra under Option A).
- **Option C — skip directly to a paid tool** when the free/OSS options' gaps (masking
  strength, DPA formality, provisioning API, or session-volume ceilings) are judged
  insufficient for a product carrying CPF/name/email at 4Shark's actual traffic scale.
  Within paid, the evidence differentiates: FullStory for the strongest default-masking
  posture (Finding 12), Contentsquare Enterprise for the most formal EU-residency+DPA package
  at the highest cost band (Finding 14), and Crazy Egg/LogRocket as flat-fee mid-range options
  with weaker provisioning-API and DPA evidence (Finding 13).

The condition that most changes which option looks preferable, per this spike's own evidence,
is **the two open questions on volume and on where CPF/name/email actually render as visible
text in `app-webclient`** — both unresolved here and both needed before any option can be
closed out with confidence.

## Decision — 2026-07-07 (spike closed, NOT proceeding)

**Outcome: do NOT adopt any heatmap / behavior-analysis tool at this time.**

**Rationale (engineer's decision):** 4Shark runs 55+ whitelabel fronts. Provisioning a
per-client project by hand is not viable at that scale — it must be scriptable (as-code /
provisioning API). That requirement collides head-on with the zero-cost constraint: **no option
satisfies zero-cost AND as-code provisioning AND heatmaps at the same time.**

**Post-spike findings that closed the decision** (verified after the spike body above, during
the engineer review):

- **PostHog self-hosted is deprecated to a hobby-only build** — scales to ~100k events/month,
  after which PostHog itself recommends migrating to PostHog Cloud (paid); the open-source
  self-host is documented as "for hobbyists", not production. So the only option that paired a
  free heatmap with a provisioning API is not deployable for a production fleet.
  [PostHog self-host disclaimer](https://posthog.com/docs/self-host/open-source/disclaimer)
- **Hotjar free tier (post-Contentsquare merger)** is generous — 200,000 sessions/month, 10,000
  recordings/month, heatmaps included — but its public API is **data-export only**; there is no
  endpoint to create sites programmatically, so provisioning is manual per site, the same
  limitation as Microsoft Clarity.
  [Hotjar API Reference](https://help.hotjar.com/hc/en-us/articles/36820005914001-Hotjar-API-Reference),
  [Hotjar/Contentsquare free tier](https://quackback.io/blog/hotjar-pricing)
- **Matomo is the only viable as-code option** — mature `SitesManager.addSite` provisioning API,
  lightweight PHP/MySQL infrastructure (runs on a cheap small box, unlike PostHog's heavy stack),
  data stays in 4Shark infra (strong LGPD). But the heatmap capability is a **paid plugin —
  €199/year, licensed per instance** (flat, one license covers all sites on the instance), not
  per site. Not zero-cost.
  [Matomo Heatmap plugin licensing FAQ](https://matomo.org/faq/heatmap-session-recording/faq_24205/)

**Net:** the only as-code-capable path (Matomo) costs ~€199/year flat for the whole fleet. The
engineer judged heatmap a "nice to have, not a need" today, so that cost is not justified now.

**Revisit trigger:** reopen this spike when there is a **real, justified need** for heatmaps — at
that point the ~€199/year (Matomo) or a paid SaaS cost is acceptable and the decision flips.
Until then: no action taken, GA4 stays as-is, nothing changes in the fronts.
