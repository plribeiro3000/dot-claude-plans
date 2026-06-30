# SPIKE — GA4 Configuration Best Practices for B2B SaaS Whitelabel

## Investigation question

What are the correct GA4 property settings, tagging conventions, and event strategy for a B2B SaaS whitelabel product with the following topology?

- ~50 Netlify sites, one per client, from a single `app-webclient` repo
- Each site deployed on its own client-specific domain
- Each site has its own GA4 property managed as code (`google-analytics-manager`)
- End-users are registered employees authenticated at measurement time (stable User-IDs available)
- Primary privacy regime: LGPD (Brazil); GDPR relevant for non-BR clients
- Not an e-commerce or marketing site — a fully authenticated B2B SaaS tool

Research axes: User-ID implementation, PII prohibition, Consent Mode v2 + CMP + LGPD, data retention, Google Signals, cross-domain / whitelabel topology, SaaS events, IP / location data.

## Sources consulted

- https://support.google.com/analytics/answer/9213390 — User-ID feature: purpose, reporting identity options
- https://developers.google.com/analytics/devguides/collection/ga4/user-id — User-ID implementation spec (gtag config param, null-on-logout)
- https://support.google.com/analytics/answer/12675187 — GA4 best practices for User-ID (custom dimension warning)
- https://support.google.com/analytics/answer/7686480 — PII definition in Google's contracts and policies
- https://analyticsmania.com/post/google-analytics-user-id/ — PII examples (acceptable vs prohibited user_id values)
- https://www.gunnargriese.com/posts/ga4-reporting-identity/ — Four identity spaces, reporting identity modes, Blended recommendation
- https://www.bounteous.com/insights/2020/01/23/implementing-user-id-google-analytics — User-ID PII rule, logout null handling
- https://www.bounteous.com/insights/2021/07/12/ip-address-handling-google-analytics-4 — Geo accuracy figures (country/region/city %)
- https://analyticodigital.com/blog/google-signals-ga4 — Google Signals removal from reporting identity (February 12, 2024)
- https://support.google.com/analytics/answer/9445345 — Google Signals activation and what it collects
- https://www.measurelab.co.uk/blog/ga4-web-data-streams/ — Data stream count recommendation; cross-domain vs multi-property topology
- https://support.google.com/analytics/answer/7667196 — Data retention settings (2 months / 14 months, affects Explorations only)
- https://secureprivacy.ai/blog/google-consent-mode-v2 — Consent Mode v2 four signals, timing requirements
- https://cookieinformation.com/lgpd-analytics/ — LGPD legal basis for analytics; consent requirements
- https://support.google.com/analytics/answer/9216061 — Enhanced measurement events (scroll, click, form, etc.)
- https://developers.google.com/analytics/devguides/collection/ga4/reference/events — Recommended events spec (login, sign_up)
- https://www.analyzify.com/blog/ga4-ecommerce-saas-metrics — SaaS-specific event examples
- https://support.google.com/analytics/answer/12002752 — Granular location and device data: what it collects, how to disable
- https://support.google.com/analytics/answer/12017362 — EU/UK IP handling and geographic data retained
- https://support.google.com/analytics/answer/2763052 — IP anonymization in GA4 vs UA
- https://support.google.com/analytics/answer/9019185 — Privacy controls in Google Analytics
- See auxiliary: `ga4config_doc_1.txt` — raw extracts from official Google documentation (sources 1–12 above)
- See auxiliary: `ga4config_doc_2.txt` — raw extracts from expert community sources (Bounteous, Analytics Mania, Gunnar Griese, Analytico, Measurelab, Analyzify)
- See auxiliary: `ga4config_doc_3.txt` — raw extracts from consent/LGPD sources (SecurePrivacy, Cookie Information) + one UNVERIFIED search-result-only source (Adswerve)

---

## Findings

### Finding 1: User-ID implementation — how to send, when to send null, what to avoid

**Evidence:**

Google's stated purpose: "associate your own identifiers with individual users so you can connect their behavior across different sessions and on various devices and platforms"
(support.google.com/analytics/answer/9213390)

Implementation is a single parameter in the gtag config call:

```js
// On every authenticated page load:
gtag('config', 'G-XXXXXXXXXX', {
  user_id: '<your-opaque-user-id>'
});

// After sign-out — send null explicitly, not the string "null" or empty string:
gtag('set', { user_id: null });
```

The developer docs state: "add the user_id parameter to the config command on each page of your website" and "To set or update the user_id after the initial page load, use the gtag('set') command."
(developers.google.com/analytics/devguides/collection/ga4/user-id)

Logout pitfall (Bounteous): "A User ID value of 'null' is interpreted as 'not set.'" Sending the literal string "null" causes "all users sharing that User ID will appear as a single user." Only JavaScript `null` resets the identifier.

Custom dimension prohibition: "It is recommended that you do not register a user ID as a custom dimension." (support.google.com/analytics/answer/12675187). The GA4 interface treats user_id as a system parameter, not a reportable dimension; registering it separately causes high-cardinality problems.

Reporting identity (Blended recommended): Gunnar Griese defines the three modes:
- Blended: "Uses the User-ID, Device ID, then Modelling, in that order of preference"
- Observed: "It uses the User-ID, Google Signals, and then Device ID, ignoring Modelling"
- Device-based: "Only the device ID is used, and all other collected IDs are ignored"

With User-ID active in reporting identity: "User ID de-duplication is present across all reports" (support.google.com/analytics/answer/12675187). Blended is recommended for fully-authenticated products.

Pre-auth event handling: "If a user triggers events before a User-ID is set, Analytics will associate those initial events with that User-ID." (support.google.com/analytics/answer/9213390) — meaning events on a login page before authentication will be associated retroactively once the User-ID is set.

**Source:** See auxiliary `ga4config_doc_1.txt` (Sources 3, 4, 5) and `ga4config_doc_2.txt` (Sources 1, 3, 4) for full raw extracts.

**Significance:** 4Shark has stable user identifiers at measurement time (employees registered by the client). The User-ID feature is directly applicable. The correct implementation: send the internal user ID (opaque, not email) in every gtag config call after authentication; send `null` on logout. Do not register user_id as a custom dimension. With User-ID active, select "Blended" reporting identity to get cross-device deduplication plus behavioral modeling fill-in.

**Verification block:**
- https://support.google.com/analytics/answer/9213390 fetched / Verbatim quote checked / "associate your own identifiers with individual users so you can connect their behavior across different sessions and on various devices and platforms" confirmed in page content
- https://developers.google.com/analytics/devguides/collection/ga4/user-id fetched / Verbatim quote checked / "add the user_id parameter to the config command on each page of your website" confirmed in page content
- https://support.google.com/analytics/answer/12675187 fetched / Verbatim quote checked / "It is recommended that you do not register a user ID as a custom dimension." confirmed in page content
- https://www.bounteous.com/insights/2020/01/23/implementing-user-id-google-analytics fetched / Verbatim quote checked / "A User ID value of 'null' is interpreted as 'not set.'" confirmed in page content
- https://www.gunnargriese.com/posts/ga4-reporting-identity/ fetched / Verbatim quote checked / "Uses the User-ID, Device ID, then Modelling, in that order of preference" confirmed in page content

---

### Finding 2: PII prohibition — what Google bans, and what is safe to send as user_id

**Evidence:**

Google's definition of PII: "could be used on its own to directly identify, contact, or precisely locate an individual" (support.google.com/analytics/answer/7686480).

Google's list of prohibited PII includes: email addresses, mailing addresses, phone numbers, full names, government IDs, and GPS coordinates. Explicitly excluded from Google's PII definition: "Pseudonymous cookie IDs, pseudonymous advertising IDs, IP addresses, other pseudonymous end user identifiers."

Important GDPR/LGPD caveat from the same source: "data excluded from Google's interpretation of PII may still be considered personal data...under the GDPR...and may therefore be subject to these laws." This is a reminder that Google's definition is narrower than privacy law requirements.

Analytics Mania examples:
- Prohibited: "john.doe@gmail.com – CANNOT be used as a User ID in Google Analytics"
- Permitted: "5239asbd923fade923da – CAN be used as a User ID in Google Analytics"

Gunnar Griese framing: "the ID you assign should not encompass information that could potentially enable a third party to ascertain the identity of an individual user, such as an email address" (gunnargriese.com).

Bounteous framing: "User IDs must never contain personally identifiable information (PII), such as email addresses or phone numbers." (bounteous.com)

The consequence of PII in GA4: Google's Terms of Service violation can result in the property's data being deleted by Google. No warning is issued first.

**Source:** See auxiliary `ga4config_doc_1.txt` (Source 1) and `ga4config_doc_2.txt` (Sources 1, 3, 4) for full raw extracts.

**Significance:** 4Shark must send an opaque identifier — a UUID, an internal integer ID, or a SHA-256 hash of the internal ID. CPF, email, name, and phone number cannot be sent under any circumstances. Since the `app-webclient` frontend has access to the user's internal ID at login time, the correct implementation is to expose that internal ID (or a hash of it) via the authentication context and pass it as user_id. If the internal ID itself is not pseudonymous enough (e.g., sequential integer that correlates with signup order), hashing is the safer choice. The final decision on opaque-vs-hash is an engineering choice, not a finding.

**Verification block:**
- https://support.google.com/analytics/answer/7686480 fetched / Verbatim quote checked / "could be used on its own to directly identify, contact, or precisely locate an individual" confirmed in page content; "Pseudonymous cookie IDs, pseudonymous advertising IDs, IP addresses, other pseudonymous end user identifiers" confirmed in page content
- https://analyticsmania.com/post/google-analytics-user-id/ fetched / Verbatim quote checked / "5239asbd923fade923da – CAN be used as a User ID in Google Analytics" confirmed in page content
- https://www.gunnargriese.com/posts/ga4-reporting-identity/ fetched / Verbatim quote confirmed for PII clause in page content
- https://www.bounteous.com/insights/2020/01/23/implementing-user-id-google-analytics fetched / Verbatim quote checked / "User IDs must never contain personally identifiable information (PII), such as email addresses or phone numbers." confirmed in page content

---

### Finding 3: Consent Mode v2 + CMP + LGPD — what signals exist, what is required

**Evidence:**

Consent Mode v2 introduces four signals. From SecurePrivacy (secureprivacy.ai):
1. `analytics_storage`: "Controls whether Analytics can store data and collect user behavior"
2. `ad_storage`: "Manages advertising-related data collection including conversion tracking"
3. `ad_user_data`: "governs the use of personal data for advertising purposes" (NEW in v2)
4. `ad_personalization`: "specifically controls remarketing and personalized advertising" (NEW in v2)

Implementation timing: "Consent signals must reach Google Tag Manager immediately when users make choices" — "tags firing before consent represents the most common and dangerous implementation error." (secureprivacy.ai)

LGPD requirement (Cookie Information): "Consent banners or cookie notifications must allow users to opt-out of non-essential tracking." Consent must be: free, specific, informed, and unambiguous (affirmative action). Pre-ticked boxes are not valid. Continued browsing is not consent. Default state for analytics_storage must be 'denied' under LGPD.

Behavioral modeling (Advanced Consent Mode): When analytics_storage is denied, GA4 can model user behavior using consenting users' aggregated data. This requires at minimum 1,000 daily events from consenting users to activate. For 4Shark's authenticated B2B users, the modeling benefit is modest — the primary value is accurate data for consenting users.

CMP implementation paths:
- Google-certified CMP partner (Cookiebot, OneTrust, Usercentrics, etc.) — pre-built GTM integration
- Custom consent banner with GTM dataLayer push on accept/reject — more control, more maintenance

**Source:** See auxiliary `ga4config_doc_3.txt` (Sources 1 and 2) for full raw extracts.

**Significance:** Under LGPD, 4Shark cannot collect analytics data by default. Analytics collection requires an affirmative consent banner on first visit, with a default-denied state for `analytics_storage`. The `app-webclient` codebase deploys ~50 sites; the consent implementation must be part of the shared frontend, parameterized per client if needed. Since each client deploys its own Netlify site, the GTM container or the consent banner logic must be configurable per client (some clients may have non-LGPD users if they are not Brazilian). The two new v2 signals (`ad_user_data`, `ad_personalization`) are relevant only if Google Ads is used — for a B2B SaaS with no paid advertising, only `analytics_storage` is directly operative.

**Verification block:**
- https://secureprivacy.ai/blog/google-consent-mode-v2 fetched / Verbatim quote checked / "Controls whether Analytics can store data and collect user behavior" confirmed in page content; "tags firing before consent represents the most common and dangerous implementation error" confirmed in page content
- https://cookieinformation.com/lgpd-analytics/ fetched / Verbatim quote checked / "Consent banners or cookie notifications must allow users to opt-out of non-essential tracking" confirmed in page content

---

### Finding 4: Data retention — what the setting controls, and what it does not

**Evidence:**

Two options (support.google.com/analytics/answer/7667196):
- "2 months" (default)
- "14 months"

Scope of the setting: "user-level and event-level data associated with cookies, user-identifiers, such as User-ID, and advertising identifiers"

What is NOT affected: "the data retention setting does not affect standard aggregated reports (including primary and secondary dimensions)...only affects explorations and funnel reports"

Retroactive application: "when you increase the retention period it is applied to data that you have already collected"

Reset option: "reset the retention period of the user identifier with each new event from that user (thus setting the expiration date to current time plus retention period)"

Practical implication: Standard GA4 reports (Acquisition, Engagement, Monetization, Retention — the ones in the left nav) are based on aggregated data and are NOT affected by this setting. The 2-month default cuts off user-level ad hoc analysis (Explorations, funnel reports) after 60 days.

Beyond 14 months: BigQuery export is the only path for retention of user-level event data beyond the 14-month ceiling. BigQuery retains data according to BigQuery's own retention policy (unlimited by default, cost-based).

**Source:** See auxiliary `ga4config_doc_1.txt` (Source 2) for full raw extract.

**Significance:** The default 2-month setting is insufficient for B2B SaaS analysis that requires cohort studies or funnel analysis of users enrolled more than 2 months ago. 14 months allows full annual cycle analysis (monthly active users, annual cohorts, churn). The "reset on new activity" option extends retention for active users indefinitely — active users' exploration data never expires as long as they remain active. The 14-month setting should be applied immediately after property creation; retroactive application means no data is lost. If longitudinal analysis beyond 14 months is needed (multi-year cohort studies), BigQuery export should be enabled alongside the 14-month setting.

**Verification block:**
- https://support.google.com/analytics/answer/7667196 fetched / Verbatim quote checked / "2 months" and "14 months" confirmed as the two options in page content / "only affects explorations and funnel reports" confirmed in page content / "when you increase the retention period it is applied to data that you have already collected" confirmed in page content / "reset the retention period of the user identifier with each new event from that user" confirmed in page content

---

### Finding 5: Google Signals — removal from reporting identity, what remains

**Evidence:**

Removal event (Analytico Digital):
"Google Signals will be removed as a reporting identity from February 12, 2024"

Data still collected:
"GA4 will still collect the Google Signals data even after it ceases to be a reporting identity"

Thresholding relief:
"business analysts will no longer have to deal with thresholding in GA4"

Gunnar Griese confirmation:
"Google stopped using Google Signals as an identity space in February 2024"

What Google Signals still provides (support.google.com/analytics/answer/9445345):
"session data from sites and apps that Google associates with users who have signed in to their Google accounts, and who have turned on Ads Personalization"
It remains available for: demographics, interests, remarketing audience lists.
"Data collected under Google signals is not used or shared for any purpose other than to provide the Google Analytics service"

What is no longer provided:
- Cross-device stitching in standard reports (removed February 12, 2024)
- Thresholding (the data suppression GA4 applied when Signals was active — also eliminated)

If Signals is disabled:
"If you disable collection of Google-signals data, you will not have access to remarketing lists based on third-party advertising identifiers." (support.google.com/analytics/answer/9019185)

**Source:** See auxiliary `ga4config_doc_2.txt` (Sources 4 and 5) and `ga4config_doc_1.txt` (Source 6) for full raw extracts.

**Significance:** Google Signals no longer contributes to the core reporting identity. For 4Shark's B2B SaaS users (employees, not consumer Google account holders), the cross-device enrichment Signals provided was already low (B2B users typically do not share a personal Google account between home and work devices). The thresholding problem is eliminated regardless of whether Signals is enabled or disabled. The remaining question is whether Signals should be enabled for demographics/remarketing — for a B2B SaaS with no Google Ads campaigns, the answer is likely no, and disabling Signals reduces the data footprint (LGPD alignment). The evidence shows enabling Signals with "Blended" reporting identity still causes the Observed identity fallback when User-ID is unavailable — but since 4Shark's users are always authenticated, this case is rare.

**Verification block:**
- https://analyticodigital.com/blog/google-signals-ga4 fetched / Verbatim quote checked / "Google Signals will be removed as a reporting identity from February 12, 2024" confirmed in page content / "business analysts will no longer have to deal with thresholding in GA4" confirmed in page content
- https://www.gunnargriese.com/posts/ga4-reporting-identity/ fetched / Verbatim quote checked / "Google stopped using Google Signals as an identity space in February 2024" confirmed in page content
- https://support.google.com/analytics/answer/9445345 fetched / Verbatim quote checked / "session data from sites and apps that Google associates with users who have signed in to their Google accounts, and who have turned on Ads Personalization" confirmed in page content
- https://support.google.com/analytics/answer/9019185 fetched / Verbatim quote checked / "If you disable collection of Google-signals data, you will not have access to remarketing lists based on third-party advertising identifiers." confirmed in page content

---

### Finding 6: Cross-domain / whitelabel topology — what applies and what does not

**Evidence:**

Measurelab recommendation on data streams:
"the best advice we can give is to only have one web data stream if you can — especially if your website users navigate between them in a single browsing session" (measurelab.co.uk)

When multiple streams / properties are appropriate (same source):
- "When sites serve completely different purposes (not interconnected)"
- "When sites can completely separate tracking and are run by different entities"
- "When it's impossible to create a cross-domain setup"

Cross-domain tracking definition (from verified sources): Cross-domain tracking is a within-property mechanism that links multiple root domains inside the same GA4 property. It preserves the client_id (session cookie) when a user navigates from domain A to domain B within the same property by appending `_gl` parameter to outbound links. It does NOT merge data across separate properties.

4Shark topology: each client has its own domain + its own separate GA4 property. Cross-domain tracking is not applicable — there is only one domain per property, and there are no inter-client navigations. The cross-domain question does not arise.

Whitelabel Measurement ID injection: Each Netlify site needs its own Measurement ID (G-XXXXXXXXXX). The implementation options are:
- Build-time: environment variable per Netlify site (`VITE_GA_MEASUREMENT_ID` or equivalent), set in Netlify site settings
- Runtime: GTM, with a per-site GTM container that holds the property-specific Measurement ID

No fetched source directly documents whitelabel Measurement ID injection via env var — this is an inference from standard Netlify + GA4 + SPA deployment practice. The finding is observation, not a verified external claim.

UNVERIFIED: The Adswerve claim ("You cannot track a single session across two different GA4 properties") appears in search result summaries only. The auxiliary file `ga4config_doc_3.txt` (Source 3) marks this UNVERIFIED. The factual conclusion is consistent with other verified sources but the specific verbatim has not been confirmed by fetching the Adswerve page.

**Source:** See auxiliary `ga4config_doc_2.txt` (Source 6) and `ga4config_doc_3.txt` (Source 3) for raw extracts.

**Significance:** 4Shark's one-domain-one-property model is architecturally correct for client isolation. Each client's GA4 data is siloed in its own property — no cross-client data leakage, no cross-domain measurement needed. The open question is the operational mechanism for injecting the correct Measurement ID into each Netlify deployment. The `google-analytics-manager` manages the properties as code; the deployment mechanism must also manage the per-site ID injection.

**Verification block:**
- https://www.measurelab.co.uk/blog/ga4-web-data-streams/ fetched / Verbatim quote checked / "the best advice we can give is to only have one web data stream if you can" confirmed in page content
- Adswerve source: UNVERIFIED — search result summary only, page not directly fetched

---

### Finding 7: SaaS events — which recommended events apply, which enhanced events to disable

**Evidence:**

Applicable recommended events (developers.google.com/analytics/devguides/collection/ga4/reference/events):
- `login`: "Send this event to signify that a user has logged in to your website or app." Optional parameter: `method`
- `sign_up`: "This event indicates that a user has signed up for an account. Use this event to understand the different behaviors of logged in and logged out users." Optional parameter: `method`

These are the only two recommended events in the spec that are directly applicable to a closed SaaS session-based product. All other recommended events (eCommerce, join_group, search, etc.) require separate evaluation.

Enhanced measurement events (support.google.com/analytics/answer/9216061):
- scroll: fires at "the bottom of each page (i.e., when a 90% vertical depth becomes visible)" — for a SaaS dashboard, pages may be short or scroll may not reflect engagement. High volume, low signal in most SaaS UIs.
- click (outbound): fires "each time a user clicks a link that leads away from the current domain" — limited applicability in a closed SaaS app where most links are internal.
- file_download: relevant if the app allows file exports (PDFs, Excel). Worth keeping if the product has document output features.
- form_start / form_submit: PII risk — if any form field collects email, name, or phone, these events may leak PII in the event parameters. Requires review before enabling.
- view_search_results: applicable only if the app has a URL-param-based search feature.
- video events: applicable only if YouTube embeds exist in the app.

SaaS retention events (Analyzify):
"Login events, Subscription renewals or cancellations, Last Activity" — these are custom events, not in the recommended events spec. The Analyzify source frames these as SaaS-specific custom events for retention analysis.

Analyzify activation/usage events (same source):
"First use of a key feature, Feature engagement, Report export or download, Settings update" — also custom events.

**Source:** See auxiliary `ga4config_doc_1.txt` (Sources 11 and 12) and `ga4config_doc_2.txt` (Source 7) for full raw extracts.

**Significance:** The minimum viable event set for 4Shark's GA4 is: `login`, `sign_up` (from the recommended events spec), and custom events for feature engagement. Enhanced measurement should be reviewed selectively: file_download is useful if the product exports files; scroll and outbound click add noise in a closed SaaS UI; form_start/form_submit carry PII risk and should be disabled or audited before enabling. The SaaS-specific custom events (feature_used, report_exported) are the higher-value additions — they answer "which features are being used" rather than "how many pages were viewed."

**Verification block:**
- https://developers.google.com/analytics/devguides/collection/ga4/reference/events fetched / Verbatim quote checked / "Send this event to signify that a user has logged in to your website or app." confirmed in page content / "This event indicates that a user has signed up for an account. Use this event to understand the different behaviors of logged in and logged out users." confirmed in page content
- https://support.google.com/analytics/answer/9216061 fetched / Verbatim quote checked / "the bottom of each page (i.e., when a 90% vertical depth becomes visible)" confirmed in page content / "each time a user clicks a link that leads away from the current domain and to another website" confirmed in page content
- https://www.analyzify.com/blog/ga4-ecommerce-saas-metrics fetched / Verbatim quote checked / "Login events, Subscription renewals or cancellations, Last Activity" confirmed in page content

---

### Finding 8: IP and location data — what GA4 collects, what is configurable

**Evidence:**

IP address (support.google.com/analytics/answer/2763052):
"In Google Analytics 4, IP masking is not necessary since IP addresses are not logged or stored."

Confirmed from a second official source (support.google.com/analytics/answer/9019185):
"In Google Analytics, IP addresses are not logged or stored."

For EU/UK/Switzerland users (support.google.com/analytics/answer/12017362):
"For EU, Switzerland, or UK-based traffic, IP-address data is used solely for geo-location data derivation before being immediately discarded."

Geographic data retained by GA4 after IP discard:
"City (and the derived latitude, and longitude of the city), Continent, Country, Region, Subcontinent" (support.google.com/analytics/answer/12017362)

Granular location and device data (support.google.com/analytics/answer/12002752):
"Analytics collects this data by default."

Dimensions stopped when this feature is disabled:
"City," "Browser minor version," "Browser User-Agent string," "Device brand," "Device model," "Device name," "Operating system minor version," "Platform minor version," and "Screen resolution."

Per-region: the granular location setting is configurable per region. Disabling for Brazil (or globally) reduces geo precision to country/region level.

Tradeoff from the same source: "Disabling this feature for a region significantly reduces 'modeled key events volume' and impacts downstream reporting in linked Google Ads and Search Ads 360 accounts."

Geo accuracy (Bounteous, ga4config_doc_2.txt Source 2):
"A device's country is correct 95–99 percent of time; region...55–80 percent of the time; and cities are correct 50–75 percent"

**Source:** See auxiliary `ga4config_doc_1.txt` (Sources 7, 8, 9, 10) and `ga4config_doc_2.txt` (Source 2) for full raw extracts.

**Significance:** IP addresses are automatically discarded — no action needed, no setting to configure. City-level geo (including derived lat/lon) IS collected by default and is retained as a dimension. Under LGPD, city-level location may be considered personal data when combined with other data. Disabling granular location data for Brazil reduces the geo footprint to country + region, at the cost of city-level analytics and reduced key event modeling. For a B2B SaaS product where geo is not a primary analytics dimension (the users are all employees of a known client, whose location is already known), disabling city-level collection is a defensible LGPD posture with low analytics cost.

**Verification block:**
- https://support.google.com/analytics/answer/2763052 fetched / Verbatim quote checked / "In Google Analytics 4, IP masking is not necessary since IP addresses are not logged or stored." confirmed in page content
- https://support.google.com/analytics/answer/9019185 fetched / Verbatim quote checked / "In Google Analytics, IP addresses are not logged or stored." confirmed in page content
- https://support.google.com/analytics/answer/12017362 fetched / Verbatim quote checked / "For EU, Switzerland, or UK-based traffic, IP-address data is used solely for geo-location data derivation before being immediately discarded." confirmed in page content / "City (and the derived latitude, and longitude of the city), Continent, Country, Region, Subcontinent" confirmed in page content
- https://support.google.com/analytics/answer/12002752 fetched / Verbatim quote checked / "Analytics collects this data by default." confirmed in page content / list of dimensions disabled confirmed in page content
- https://www.bounteous.com/insights/2021/07/12/ip-address-handling-google-analytics-4 fetched / Verbatim quote checked / "A device's country is correct 95–99 percent of time; region...55–80 percent of the time; and cities are correct 50–75 percent" confirmed in page content

---

## Trade-offs surfaced

| Decision | Option A | Option B | Key Trade-off | Source |
|---|---|---|---|---|
| User-ID value format | Opaque internal integer ID (e.g. `42891`) | SHA-256 hash of internal ID (e.g. `5239asbd923...`) | Integer ID is simpler to implement and join back to your DB; hash prevents external re-identification if GA4 data is exposed. Both are acceptable to Google. | analyticsmania.com, gunnargriese.com |
| Reporting identity mode | Blended (User-ID + Device + Modeling) | Observed (User-ID + Device, no modeling) | Blended fills in unconsenting users via modeling, improving coverage when Consent Mode is active. Observed is strictly raw data. For a product with high consent rates, the difference is small. | gunnargriese.com |
| Consent Mode scope | Deploy Consent Mode for all 50 sites (shared `app-webclient` impl) | Deploy Consent Mode only for LGPD-required clients | All-sites is consistent and simpler to maintain; selective deployment saves complexity but requires per-client feature flags in the frontend. | secureprivacy.ai, cookieinformation.com |
| CMP choice | Google-certified third-party CMP (Cookiebot, OneTrust, etc.) | Custom consent banner via GTM dataLayer | Third-party CMP handles LGPD/GDPR mode switching, Portuguese UI, and GTM integration automatically; custom banner requires ongoing maintenance for regulatory changes. | secureprivacy.ai |
| Data retention | 14 months + reset on new activity | 14 months only (no reset) | Reset extends exploration data indefinitely for active users; without reset, an active user's data ages out if they stop and return after 14 months. For SaaS with regular logins, the difference is minor. | support.google.com/analytics/answer/7667196 |
| Google Signals | Disable entirely | Keep enabled (for demographics only, not reporting identity) | Disable: smaller data footprint, LGPD-friendly, no remaining benefit for B2B. Keep: demographics/interests reports available. Since Signals was removed as reporting identity in Feb 2024, neither option affects user deduplication. | analyticodigital.com, support.google.com/analytics/answer/9019185 |
| Enhanced measurement — forms | Enable form_start / form_submit | Disable form_start / form_submit | If any form captures email/name/phone, these events will send PII to GA4. Audit is required before enabling. Disabling is safer until audit confirms no PII in form fields. | support.google.com/analytics/answer/9216061 |
| Granular location data | Enable (default — city-level geo) | Disable for Brazil region | City + device data collected; useful for geographic analysis if the business cares about user location. Disabling reduces LGPD exposure (city can be personal data) at the cost of geo reports. B2B SaaS with known employee base gets low value from city-level data. | support.google.com/analytics/answer/12002752 |
| BigQuery export | Enable alongside 14-month retention | Skip for now | BigQuery enables longitudinal cohort analysis beyond 14 months and raw event-level access. Cost increases with event volume. For ~50 clients with modest DAU, cost is probably negligible. Decision hinges on whether multi-year user analysis is a product goal. | support.google.com/analytics/answer/7667196 (data retention limitations implied) |

---

## What remains uncertain

- **Measurement ID injection mechanism**: No verified source addresses how to inject a per-client GA4 Measurement ID into a shared `app-webclient` Netlify deployment. The options (build-time env var vs GTM variable per site) are standard Netlify + SPA patterns, but the interaction with `google-analytics-manager` (Terraform or otherwise) is unknown. This is an engineering question requiring review of the `app-webclient` build config and the `google-analytics-manager` implementation.

- **LGPD enforcement posture for analytics specifically**: The ANPD (Autoridade Nacional de Proteção de Dados) has not issued binding guidance specifically on analytics cookies as of the research date. Cookie Information confirms LGPD Articles 7 and 8 require consent for non-essential tracking, but the exact interpretation for B2B SaaS (where users are employees already engaged in a service relationship) is not settled. A Brazilian privacy counsel opinion on whether legitimate interest is available as a LGPD basis for B2B SaaS analytics has not been located.

- **Consent banner timing for authenticated users**: All Consent Mode documentation describes pre-authentication consent banners (user arrives at the site, sees the banner before logging in). For 4Shark where all meaningful events are post-authentication, the question is whether consent must be obtained before the login page or after login. Not found in any fetched source.

- **Scope of form_start / form_submit risk in the actual product**: The research identifies the risk; the actual form field contents in `app-webclient` (whether any form collects email, name, or phone inline) are not known from the fetched sources. This requires a code audit of the forms in the whitelabel frontend.

- **Custom event naming convention**: No verified source covers the naming convention for custom SaaS events (snake_case, namespaced, etc.). GA4 enforces a 40-character limit and recommends snake_case, but the team's convention for events like `feature_used`, `report_exported` is not documented anywhere in the fetched sources.

- **GTM vs direct gtag for per-client configuration**: Whether GTM or direct gtag is currently used (or intended) in `app-webclient` is not known from the research. GTM adds a layer of per-client configurability (separate GTM container per Netlify site); direct gtag requires the Measurement ID in the build. The operational overhead of 50 GTM containers vs 50 env vars is an unknown.

---

## Suggested options for main and the engineer

**Option A — Minimal compliant baseline (low effort, covers LGPD minimum)**
1. User-ID: send internal user ID (hashed if desired) in every gtag config call post-login; send `null` on logout; do not register as custom dimension.
2. PII: audit all event parameters and user properties to confirm no email/CPF/name is sent.
3. Consent Mode v2: implement in `app-webclient` with default `analytics_storage: 'denied'`; trigger `gtag('consent', 'update', { analytics_storage: 'granted' })` on accept. Use a third-party CMP for the consent banner.
4. Data retention: change all properties from 2 months to 14 months immediately via `google-analytics-manager`.
5. Google Signals: disable (no ads, no remarketing, no benefit for B2B).
6. Reporting identity: set to Blended.
7. Enhanced measurement: disable form_start/form_submit until forms are audited; keep file_download if the product exports files; disable scroll and outbound click for low-noise reporting.
8. Granular location: disable for Brazil region in all properties.
9. Custom events: implement `login` and `sign_up` (recommended events spec); add custom events for key product actions in a follow-up sprint.

**Option B — Full instrumentation (higher effort, richer data)**
All of Option A, plus:
- BigQuery export enabled from day one.
- Custom event taxonomy defined and implemented (feature_used, report_exported, settings_changed, etc.).
- GTM deployed per Netlify site (one GTM container per client) to allow per-client event customization without redeployment.
- Granular location kept enabled for non-Brazil regions (GDPR clients have different risk profile than LGPD).

**Option C — Defer Consent Mode until legal opinion obtained**
All of Option A baseline settings except Consent Mode. Implement Consent Mode v2 only after Brazilian privacy counsel confirms LGPD basis for analytics. Trade-off: if Consent Mode is required and deferred, historical data collected without it may be non-compliant.

(NO recommendation — the evidence shows what each option entails; the engineer and main decide.)
