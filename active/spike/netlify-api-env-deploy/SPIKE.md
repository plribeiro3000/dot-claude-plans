# SPIKE — Netlify API: Set Env Var + Trigger Redeploy

## Investigation question

A Python tool creates a GA4 property, retrieves its `measurementId` (`G-XXXXXXX`), then must (a) push that ID into the corresponding Netlify site as an environment variable and (b) trigger a redeploy so the new value takes effect. What are the exact API calls for each step, and does step (a) auto-trigger step (b)?

## Sources consulted

- https://docs.netlify.com/api/get-started/ — auth header shape, PAT creation, site identifier note
- https://open-api.netlify.com/ — full endpoint table (env vars, builds, deploys, build hooks, sites)
- https://docs.netlify.com/api-and-cli-guides/api-guides/get-started-with-api/ — env var endpoints + explicit "requires a build" quote
- https://docs.netlify.com/configure-builds/build-hooks/ — build hook URL shape, POST trigger, clear_cache param
- https://docs.netlify.com/configure-builds/stop-or-activate-builds/ — POST /sites/{site_id}/builds confirmed
- See auxiliary: `netlify_env_deploy_raw_1.txt` — verbatim snippets from all fetched pages

---

## Executive answer (end-to-end call sequence)

```
1. GET  /api/v1/sites?name={slug}            → resolve site_id
2. PUT  /api/v1/accounts/{account_id}/env/{key}?site_id={site_id}
        body: { "key": "GA_MEASUREMENT_ID", "values": [{"value": "G-XXXXXXX", "context": "production"}] }
3. POST /api/v1/sites/{site_id}/builds       → trigger fresh build (no body required)
   OR  POST https://api.netlify.com/build_hooks/{hook_id}?clear_cache=true  (if hook pre-exists)
```

Step 2 does NOT auto-trigger step 3 — they are always separate calls.

---

## Findings

### Finding 1: Env var API — modern account-scoped endpoints, site_id query param scopes to one site

**Evidence:**
```
POST  /accounts/{account_id}/env              → create
PUT   /accounts/{account_id}/env/{key}        → replace all values for that key
PATCH /accounts/{account_id}/env/{key}        → update one value entry

?site_id={site_id}   ← query param on all three
```
Values array item shape:
```json
{ "id": "string", "value": "string",
  "context": "all|dev|dev-server|branch-deploy|deploy-preview|production|branch",
  "context_parameter": "string" }
```
Verbatim quote: `"If provided, create an environment variable on the site level, not the account level."`

**Source:** https://open-api.netlify.com/ (operations: createEnvVars, updateEnvVar, setEnvVarValue)

**Verification block:**
URL fetched / Verbatim quote checked / Quote substring `"create an environment variable on the site level"` confirmed in fetched content.

**Significance:** `PUT` replaces all values for a key (correct for idempotent upsert of a single `GA_MEASUREMENT_ID`). `PATCH` creates/updates a single context-value entry. For the tool, `PUT` with `context: "production"` is the cleanest shape — one call, idempotent, context-scoped to production only.

---

### Finding 2: Env var change does NOT auto-deploy

**Evidence:**
Verbatim quote (two pages, same text):
`"Environment variable changes require a build and deploy to take effect."`
Second form: `"To apply environment variable changes, build and deploy."`

**Source:** https://docs.netlify.com/api-and-cli-guides/api-guides/get-started-with-api/ and https://docs.netlify.com/environment-variables/get-started/

**Verification block:**
Both URLs fetched / Verbatim quote `"Environment variable changes require a build and deploy to take effect."` confirmed in fetched content from first source.

**Significance:** The tool must always issue a separate build trigger after every env var write. Hypothesis confirmed: no auto-deploy.

---

### Finding 3: Two mechanisms to trigger a build

**Mechanism A — Build hook (POST to opaque URL):**
```
POST https://api.netlify.com/build_hooks/{hook_id}
Body: {}   (empty JSON)
Optional: ?clear_cache=true   ← triggers build with cleared cache
```
Verbatim: `"To trigger this hook, you need to send a POST request to that URL."`
Verbatim: `"this parameter triggers a build with a cleared cache."`
Constraint: `"Builds must be active for build hooks to trigger builds of your site."`

**Mechanism B — REST builds endpoint:**
```
POST /api/v1/sites/{site_id}/builds
```
Verbatim: `"Any POST requests to /api/v1/sites/{site_id}/builds will return an error message."` (when builds are stopped — confirms the endpoint exists and is the correct shape)

**Source A:** https://docs.netlify.com/configure-builds/build-hooks/
**Source B:** https://docs.netlify.com/configure-builds/stop-or-activate-builds/

**Verification block:**
Both URLs fetched / Substring `"To trigger this hook, you need to send a POST request to that URL."` confirmed (Source A) / Substring `"POST requests to /api/v1/sites/{site_id}/builds will return an error message"` confirmed (Source B).

**Significance:** Build hooks require pre-creation (one-time setup per site). The REST endpoint `/builds` is always available without setup. For a tool managing ~50 sites, REST (`POST /sites/{site_id}/builds`) avoids per-site hook management. The `clear_cache` query param exists on build hooks; whether it exists on the REST builds endpoint was not confirmed in fetched docs (see "What remains uncertain").

---

### Finding 4: Authentication — PAT as Bearer token

**Evidence:**
Verbatim: `"Authorization: Bearer <YOUR_PERSONAL_ACCESS_TOKEN>"`
Token creation: `Applications > Personal access tokens > New access token`
Verbatim: `"If your team requires you to log in with single sign-on (SSO), your personal access tokens will be denied access to the team by default."`

**Source:** https://docs.netlify.com/api/get-started/

**Verification block:**
URL fetched / Verbatim quote `"Authorization: Bearer <YOUR_PERSONAL_ACCESS_TOKEN>"` confirmed in fetched content.

**Significance:** A single PAT from the team owner account covers env var writes and build triggers across all ~50 sites (no per-site credential). SSO teams must explicitly grant PAT access at token creation. Token expiration and password-reset invalidation are operational risks for an automated tool.

---

### Finding 5: Site identification — list by name, resolve to site_id

**Evidence:**
```
GET /api/v1/sites?name={name}
```
Query params: `name` (string), `filter` (all|owner|guest), `page`, `per_page`
Verbatim: `"you can either use the id of a site obtained through the API, or the domain of the site (for example, mysite.netlify.app or www.example.com). These two are interchangeable whenever they're used in API paths."`

**Source:** https://open-api.netlify.com/ (listSites) and https://docs.netlify.com/api/get-started/

**Verification block:**
Both URLs fetched / Substring `"These two are interchangeable whenever they're used in API paths"` confirmed at https://docs.netlify.com/api/get-started/ / `GET /sites` with `name` query param confirmed at https://open-api.netlify.com/ (listSites).

**Significance:** The tool can carry a slug/name in config and resolve `site_id` at runtime with `GET /sites?name={slug}`. Alternatively, `site_id` can be replaced with `mysite.netlify.app` directly in per-site API calls (env var PUT, builds POST) — eliminates the lookup step if site subdomains are already known.

---

## What remains uncertain

- Whether `POST /api/v1/sites/{site_id}/builds` accepts a `clear_cache` body parameter (docs confirm the endpoint exists but no request body schema was returned from the fetched pages).
- Whether `PUT /accounts/{account_id}/env/{key}?site_id=…` with `context: "production"` leaves `deploy-preview` and `branch-deploy` contexts unset or inherits from account-level — needs a live test or deeper OpenAPI schema read.
- Legacy `build_settings.env` on `PATCH /api/v1/sites/{site_id}` still exists in the API but docs do not mention it in the env var guides — treat as deprecated; do not use.
- Rate limit for env var writes is not stated (only builds: 3/min, 100/day).
