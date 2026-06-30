# PLAN-SPIKE — Tenant-Scoped Authentication

> Reference: SPIKE.md (spike/devise-tenant-scoped-email/SPIKE.md) — prior research on
> why tenant-scoped email is the correct model and what Devise provides.

---

## Objective

The app uses a partial unique index `(company_id, email) WHERE anonymized=false`, meaning
the same email can legitimately belong to different people in different companies (e.g.,
a Mexico carnet `170472@atento.com` and a Brazil RE `170472@atento.com` are two distinct
humans). The goal is to make login resolve the correct user when a cross-tenant email
collision exists, without breaking anything for the majority of users whose emails are
globally unique.

The implementation must be backward-compatible at every step: the backend ships first
and works with or without a `company_id` param. Clients update incrementally.

---

## Scope

### In scope

- Backend (`app`) — accept optional `company_id` at login; scope user lookup when
  present; fall back to current behavior when absent.
- Setup service — add `company_id` to the configuration payload returned to clients, so
  the mobile app knows which tenant to send.
- Web frontend (`app-webclient`) — thread `company_id` from stored credentials into the
  login POST body.
- Mobile (`app-mobileclient`) — effort-sizing only: identify where to thread
  `company_id` into the existing POST; no full design.

### Out of scope (open question)

- Forgot-password / Devise `recoverable` scoping — currently, the app does NOT use
  Devise's built-in `send_reset_password_instructions`. Password reset goes through a
  CSV document upload (`PasswordDocument::Processor`). Whether any email-triggered reset
  path exists is a decision point surfaced in §"Technical decisions to be made".
- SSO / Keycloak paths — `Authentication::SessionsController` already scopes by company
  (it resolves the company from `AuthenticatorConfiguration.find_by(uuid:)` before any
  user lookup). SSO is not affected by this feature.
- `Devise::PasswordsController` override — not needed if no email-triggered reset exists.
- `confirmation_keys` / `unlock_keys` scoping — `User` does not include `:confirmable`
  (`devise` line lists only `database_authenticatable, lockable, registerable,
  rememberable, trackable, timeoutable`); `unlock_strategy` is `:time`, not `:email`.
  No email-driven confirmation or unlock flow exists today.

---

## Current-state map per repo

### app — the login path

**Two entry points exist, only one is affected.**

**Entry point 1 — Devise web form (`GET /sign_in`, `POST /sign_in`)**

Mounted via `devise_for :users, skip: :registrations, path: ''` at
`app/config/routes.rb:96-98`:

```ruby
devise_for :users,
           skip: :registrations,
           path: ''
```

This triggers the stock `Devise::SessionsController`. The `before_failure` Warden hook
at `app/config/initializers/devise.rb:307-332` uses:

```ruby
attempted_user = User.find_for_database_authentication(email: attempted_email)
```

`find_for_database_authentication` delegates to `find_for_authentication`, which calls
`find_first_by_auth_conditions` — a plain `User.find_by(email:)` with no `company_id`
scope. When two users share the same email across companies, the first one found wins.

**Entry point 2 — Custom JSON `SessionsController` (`POST /sessions`)**

`app/config/routes.rb:94`: `resources :sessions, only: :create`

`app/app/controllers/sessions_controller.rb:7`:

```ruby
user = User.enabled.find_for_database_authentication(email: params[:email])
```

Same problem: pure email lookup, no company scope. This is the endpoint the mobile app
and web client hit for JSON/JWT-based authentication.

**The Warden / Devise web entry point also records SecurityEvents** on login success and
failure (hooks in `app/config/initializers/devise.rb:283-353`). The failure hook runs
`User.find_for_database_authentication(email: attempted_email)` — same unscoped call.

**No existing `find_for_authentication` or `authentication_keys` override** in the `User`
model (`app/app/models/user.rb`) — the model delegates entirely to Devise defaults.

**Devise modules in use** (`app/app/models/user.rb:12`):

```ruby
devise :database_authenticatable, :lockable, :registerable, :rememberable, :trackable, :timeoutable
```

No `:recoverable`, no `:confirmable`. The email-driven password reset risk from the
prior spike (Finding 3) does NOT apply to this app — password reset uses a document
upload flow (`PasswordDocument::Processor`), not Devise's `send_reset_password_instructions`.

**Composite index confirming tenant-scoped uniqueness** (`app/db/schema.rb:2356`):

```ruby
t.index ["company_id", "email"], name: "index_users_on_company_id_and_email",
        unique: true, where: "(anonymized = false)"
```

No global unique index on email alone. The index name (`index_users_on_company_id_and_email`)
is also the constraint name used by `rescue_unique_constraint` in `user.rb:233`:

```ruby
rescue_unique_constraint index: :index_users_on_company_id_and_email, field: :email
```

**SSO path is already tenant-scoped** (`app/app/controllers/authentication/sessions_controller.rb:85-90`):

```ruby
@current_user = current_company.users.enabled.find_by(email: email)
```

`current_company` is derived from `AuthenticatorConfiguration.find_by(uuid: params[:id])`,
which is per-company by construction. SSO does NOT have the collision problem.

**Lockable**: `unlock_strategy :time` (devise.rb:191), `unlock_keys [:email]` (devise.rb:183).
With `:time` strategy, the unlock email is never sent; `unlock_keys` is used only
for the email-based `:email` strategy. This is out of scope.

---

### setup — configuration delivery

The mobile app boots by scanning a QR code. The QR code is a configuration UUID.
The mobile POSTs `{ device: { uuid, kind } }` to `POST /api/v1/devices` to register
(`setup/app/controllers/api/v1/devices_controller.rb:6-23`), then GETs the configuration
via `GET /api/v1/devices/:device_id/configurations/:uuid`
(`setup/app/controllers/api/v1/devices/configurations_controller.rb:9`):

```ruby
def show
  if current_device.nil? || configuration.nil? || device_mismatch?
    head :not_found
  else
    current_device.update(configuration_id: configuration.id) if current_device.configuration.nil?
    render json: current_device.configuration, status: :ok
  end
end
```

The response is serialized by `ConfigurationSerializer`
(`setup/app/serializers/configuration_serializer.rb:3-6`):

```ruby
attributes :auth_origin, :auth_provider, :auth_url, :favicon_ico_url, :favicon_png_url,
           :graphql_endpoint_url, :name, :primary_color, :primary_logo_url,
           :secondary_color, :secondary_logo_url, :uuid
```

The `configurations` table has NO `company_id` column (`setup/db/schema.rb:18-36`).
The `Configuration` model has NO `company_id` attribute. This is the central gap:
the mobile app receives a JSON payload that includes `graphql_endpoint_url`, `auth_url`,
`auth_provider`, `auth_origin` — but no `company_id`.

The mobile stores the full configuration blob in `SharedPreferences` under `'configuration'`
and reads fields from it at login time
(`app-mobileclient/lib/http/login/login_http.dart:10-14`):

```dart
final prefs = await SharedPreferences.getInstance();
var config = prefs.getString('configuration');
dynamic configuration = jsonDecode(config!);
```

---

### app-webclient — the login form

The web client has two auth paths:

**Path 1 — Basic auth (email + password) via `LoginComponent`**
(`app-webclient/src/app/login/login.component.ts`)

Form fields: `email`, `password`, `remember`. No `company_id` field
(`app-webclient/src/app/login/login.component.ts:57-63`):

```typescript
this.loginForm = this.formBuilder.group({
  email: ['', Validators.required],
  password: ['', Validators.required],
  remember: false,
});
```

The form value is POSTed verbatim to `/sessions`
(`app-webclient/src/app/core/authentication/authentication.service.ts:35`):

```typescript
return this.http.post<any>(loginUrl, formData, { observe: 'response' })
```

No `company_id` is sent. The web client already stores `company_id` in credentials
after login (from `response.body.user.company_id`) and in the SSO flow from the `me`
query (`session-create.component.ts:63: company_id: meResponse.companyId`).

**Path 2 — SSO (Microsoft/Google) via `SessionService`**
(`app-webclient/src/app/core/session/session.service.ts:12-16`)

```typescript
login(): void {
  this.credentialsService.destroyCredentials();
  window.open(env.AUTH_URL, '_self');
}
```

Redirects to `AUTH_URL` — the Keycloak/provider URL. Already tenant-scoped at the
`Authentication::SessionsController` level. Not affected.

**`company_id` is already available** in the web client after authentication (stored
in `CredentialsService`). The question is only whether to pass it in the login request body.

---

### app-mobileclient — mobile Flutter login

Login HTTP call (`app-mobileclient/lib/http/login/login_http.dart:22-31`):

```dart
var body = jsonEncode({
  'email': account,
  'password': password,
  'remember': true,
});
```

No `company_id`. The configuration blob is loaded from `SharedPreferences` before
the call (line 10-14). The configuration blob already has `graphql_endpoint_url`
and `name` — it would need a `company_id` field added by setup.

**Provisioning flow** (how the mobile gets the configuration):
1. App boots — checks `SharedPreferences['configuration']`.
2. If absent → shows QR code scanner (`qr_code.dart`).
3. User scans QR → calls `DeviceHttp.PostDevicesConfiguration(mapBody, qrCode)` which
   hits `GET /api/v1/devices/:id/configurations/:uuid` on setup.
4. Response JSON (configuration blob) is stored in `SharedPreferences['configuration']`.
5. Mobile uses `configuration['graphql_endpoint_url']` as the login endpoint host
   and `configuration['auth_origin']` as the `Origin` header.

The `company_id` is not in the configuration blob today. Adding it to the setup
response is the prerequisite for the mobile to know what to send at login.

---

## Candidate approaches

### Option A: Override `find_for_authentication` on the `User` model

**Approach summary:**

Add a `self.find_for_authentication` override directly to the `User` model. When
`company_id` is present in the conditions, scope by it; when absent, fall back to
email-only. The backend `SessionsController#create` passes `company_id` from params
if present. Devise's `find_for_database_authentication` already calls
`find_for_authentication`, so both the Devise web form and the custom JSON controller
go through the same override.

```ruby
# app/app/models/user.rb
def self.find_for_authentication(tainted_conditions)
  conditions = devise_parameter_filter.filter(tainted_conditions)
  if conditions[:company_id].present?
    find_first_by_auth_conditions(conditions)
  else
    find_first_by_auth_conditions(conditions.except(:company_id))
  end
end
```

For the custom JSON controller (`SessionsController#create`), change:

```ruby
# Before:
user = User.enabled.find_for_database_authentication(email: params[:email])

# After:
auth_conditions = { email: params[:email] }
auth_conditions[:company_id] = params[:company_id] if params[:company_id].present?
user = User.enabled.find_for_database_authentication(auth_conditions)
```

**What `find_for_database_authentication` does today** (Devise 5.0.4,
`app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/database_authenticatable.rb:198-200`):

```ruby
def find_for_database_authentication(conditions)
  find_for_authentication(conditions)
end
```

And `find_for_authentication` at
`app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb:263-265`:

```ruby
def find_for_authentication(tainted_conditions)
  find_first_by_auth_conditions(tainted_conditions)
end
```

The override slots in exactly here — one method, two behaviors based on presence of
`company_id`.

**Pros:**
- Single override in one file (`user.rb`). Minimal surface area.
- Works for both the Devise web form path and the custom JSON sessions controller.
- Fully backward-compatible: absent `company_id` → unchanged behavior.
- No Devise config changes (`authentication_keys` untouched).
- The `Warden::Manager.before_failure` hook in `devise.rb:308` calls
  `User.find_for_database_authentication(email: attempted_email)` — this passes through
  the override with no `company_id`, so the fallback branch fires.

**Cons:**
- `find_for_authentication` is also called by Devise for password-recovery lookups —
  but the app does not use Devise `:recoverable`, so this is moot here.
- The override reads `devise_parameter_filter.filter(tainted_conditions)` internally —
  must call it explicitly in the override, or use a simpler approach. The simplest safe
  approach is to let `find_first_by_auth_conditions` call the filter internally (it already
  does via `to_adapter.find_first(devise_parameter_filter.filter(tainted_conditions))`).
  Calling the filter explicitly in the override adds a double-filter risk; simpler to
  pass the raw conditions to `find_first_by_auth_conditions` and let it handle filtering.

**Cost / effort:** Small — one model method addition, one controller line change.

**Risk:** Low. The override is narrowly scoped. The fallback branch preserves current
behavior. One test covers the scoped path, one covers the unscoped path.

**Source patterns referenced:**
- `app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb:263-265` — canonical Devise `find_for_authentication` default
- `app/app/controllers/sessions_controller.rb:7` — current unscoped lookup
- Devise wiki `find_for_authentication` override pattern: `~/.claude/plans/active/spike/devise-tenant-scoped-email/devise_doc_1_scope_login.txt:47-50`

---

### Option B: Use `authentication_keys` config on the `User` model

**Approach summary:**

Configure `authentication_keys: { email: true, company_id: false }` directly on the
Devise call in the `User` model. The `false` value means the key is optional (does not
abort authentication when absent). Devise's strategy builds the condition hash from
`params` for each listed key, and passes it to `find_for_authentication`.

```ruby
# app/app/models/user.rb
devise :database_authenticatable, :lockable, :registerable,
       :rememberable, :trackable, :timeoutable,
       authentication_keys: { email: true, company_id: false }
```

**How `authentication_keys` with a hash works** (Devise 5.0.4,
`app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb:157-167`):

```ruby
def parse_authentication_key_values(hash, keys)
  keys.each do |key, enforce|
    value = hash[key].presence
    if value
      self.authentication_hash[key] = value
    else
      return false unless enforce == false
    end
  end
  true
end
```

When `company_id: false`, if `params[:company_id]` is absent, the key is skipped but
auth is not aborted. If present, it is included in `authentication_hash` and passed to
`find_for_authentication` → `find_first_by_auth_conditions`.

**BUT:** `find_first_by_auth_conditions` calls `to_adapter.find_first(...)` — for
ActiveRecord this is a `User.find_by(...)` with whatever conditions are in the hash.
If `company_id` is included in the conditions hash, the query scopes by it. If absent,
it queries by email only. **This is the correct behavior with no model override.**

**Pros:**
- No model method override — purely declarative Devise config.
- `company_id` in params → automatically scopes the DB query.
- Handles the optional/required distinction in the Devise layer.
- Works for the Devise web form path (`devise_for` route).

**Cons:**
- The custom JSON `SessionsController#create` calls
  `User.enabled.find_for_database_authentication(email: params[:email])` directly with
  a hand-built conditions hash. It does NOT use the Warden strategy (which reads
  `authentication_keys`). This means `authentication_keys` config alone does NOT fix
  the custom controller — the controller must also be updated to pass `company_id`
  in its conditions hash.
- Adds `company_id` to the list of expected params for the Devise web form, which may
  affect CSRF param filtering or strong params (needs verification).
- Less explicit than Option A — the scoping happens inside the Devise call chain rather
  than in visible code.

**Cost / effort:** Small for Devise config + small for controller update.

**Risk:** Medium. The `authentication_keys` option affects the Warden strategy for the
Devise web form. The custom `SessionsController` must still be updated separately.
Two points of change vs. Option A's one.

**Source patterns referenced:**
- `app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb:157-167` — `parse_authentication_key_values` with hash keys
- `app/config/initializers/devise.rb:38-42` — existing `authentication_keys` comment block
- `app/app/controllers/sessions_controller.rb:7` — custom controller that must also be updated

---

### Option C: Scope inside the custom controller only (skip Devise internals)

**Approach summary:**

The mobile app and web client use the custom JSON `SessionsController` at
`POST /sessions`, NOT the Devise web form. Instead of touching Devise config or the
User model, scope the lookup entirely in the controller:

```ruby
# app/app/controllers/sessions_controller.rb
def create
  user = if params[:company_id].present?
           User.enabled.find_by(email: params[:email], company_id: params[:company_id])
         else
           User.enabled.find_for_database_authentication(email: params[:email])
         end
  # ... rest unchanged
end
```

**Pros:**
- Narrowest blast radius — no Devise model or config change.
- Only one file changes.
- The Devise web form path remains entirely unchanged (which is acceptable if the web
  form is internal/admin-only and never hits email collisions).

**Cons:**
- Does NOT fix the Devise web form path (`/sign_in`). If any collision user tries to
  log in through the Devise web form, the first-found problem remains.
- The `Warden::Manager.before_failure` hook also calls
  `User.find_for_database_authentication(email: attempted_email)` without a company
  scope — failure events may log the wrong user.
- Bypasses `find_for_database_authentication` for the scoped branch — any future
  logic added there (rate limiting, auditing) would not apply.
- Inconsistent: the JSON endpoint is tenant-aware, the Devise form endpoint is not.

**Cost / effort:** Smallest possible.

**Risk:** Low for the mobile/web path; leaves Devise form unpatched (acceptable if form
is confirmed admin-only).

**Source patterns referenced:**
- `app/app/controllers/sessions_controller.rb:7-13` — the existing lookup pattern
- `app/config/routes.rb:94` — `resources :sessions, only: :create`

---

## How company_id is discovered before login (the setup flow)

The mobile does not know `company_id` — it only knows the configuration UUID (from the QR
code). The setup service resolves the configuration blob, but the `Configuration` model
has no `company_id` column (`setup/db/schema.rb:18-36`) and the serializer does not
include it (`setup/app/serializers/configuration_serializer.rb:3-6`).

**To make `company_id` available at mobile login time**, the sequence must be:

1. Add a `company_id` column (integer, nullable) to the `configurations` table in setup.
2. Populate it when configurations are created/updated (this requires knowing the mapping
   between a `Configuration` and the app's `Company` — an open question; see below).
3. Add `company_id` to `ConfigurationSerializer`.
4. The mobile reads `company_id` from the stored configuration blob and passes it at login.

**The web client does not use setup.** The web client is deployed per-tenant (the Angular
`environment` file contains the backend URL). `company_id` is already in the session
response (`app/app/models/session.rb:14: company_id: @user.company_id`). The web client
already stores `company_id` after login in `CredentialsService`. The question is where
to get it BEFORE the first login — e.g., from the Angular environment config.

**Open question:** How does the setup `Configuration` know which `company_id` to return?
The setup DB has no reference to the app's companies table. The mapping might be:
- Explicit `company_id` column added to configurations and set by an admin.
- Derived from `graphql_endpoint_url` hostname (if per-company hostnames exist).
- Not possible without a data bridge between setup's DB and the app's DB.

This is a blocker for the mobile path and an open question for the engineer.

---

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| **Backend mechanism** | A: `find_for_authentication` override in User model; B: `authentication_keys` config + controller update; C: Controller-only scope | A: cleaner, single override; B: Devise-native but two changes; C: narrowest but leaves Devise form unpatched | □ |
| **How setup knows company_id** | (a) Add `company_id` column to configurations (admin-set); (b) derive from endpoint URL; (c) deploy separate config per company with company_id hardcoded | (a) requires admin tooling; (b) fragile (URL coupling); (c) simplest if configs are already per-company | □ |
| **Web client source of company_id at first login** | (a) Hardcoded in Angular env file; (b) Read from setup before login (if setup exposes it); (c) Read from URL param at login | Web client is per-tenant-deployed; env file is the natural place | □ |
| **Scope Devise web form (`/sign_in`) too?** | Yes (Options A or B) vs. No (Option C) | Devise form is likely internal/admin only; confirm whether collisions can reach it | □ |
| **Password reset scope** | Confirm no Devise `:recoverable` email path exists (seems confirmed by model); close as out of scope or audit | App uses `PasswordDocument::Processor`, not Devise recoverable — confirm and close | □ |
| **Mobile: when to ship** | Size effort now, implement separately after backend ships | Mobile is backward-compatible until updated (non-collision users unaffected) | □ |

---

## Decomposition into discrete tasks

Tasks follow the engineer's sequence: backend → setup → web → mobile effort-sizing.

### Task 1 — Backend: accept optional `company_id` at login (app)

**Independently shippable, backward-compatible.** No clients need to change for this
to be safe in production.

Subtasks:
1a. Add `find_for_authentication` override to `User` model (if Option A chosen) OR add
    `authentication_keys` to `devise` call (if Option B chosen).
1b. Update `SessionsController#create` to pass `company_id` when present in params.
1c. Update `Warden::Manager.before_failure` hook to scope the failure lookup when
    `company_id` is in params (currently reads only `request.params.dig('user', 'email')`).
1d. Write unit tests: scoped login succeeds with correct user; unscoped login picks
    first-found (unchanged behavior); scoped login with wrong company returns 401.

**Dependencies:** None.

**Risk:** Low — fallback branch preserves current behavior for all existing clients.

---

### Task 2 — Setup: add `company_id` to configuration response

**Depends on:** Resolution of the open question of how setup knows the company_id.
Blocked until engineer decides the mapping strategy.

Subtasks:
2a. Generate migration to add `company_id` integer column (nullable) to configurations.
2b. Populate existing configurations (either admin UI, rake task, or manual).
2c. Add `company_id` to `ConfigurationSerializer`.
2d. Write controller test: configuration response includes `company_id`.

**Dependencies:** Open question on setup-to-app mapping resolved (engineer decision).

**Risk:** Medium — adds a new field; nullable so existing configs without it work but
mobile won't send company_id until the config is populated.

---

### Task 3 — Web frontend: pass `company_id` at login (app-webclient)

**Depends on:** Task 1 deployed. Independently shippable once backend accepts the param.

Subtasks:
3a. Add `company_id` to the `Login` model interface
    (`app-webclient/src/app/login/login.model.ts`).
3b. In `LoginComponent.createForm()`, add `company_id` read from Angular environment
    config (or from `CredentialsService` if available from a prior session).
3c. In `AuthenticationService.login()`, confirm `company_id` flows through `formData`
    (it is already passed verbatim as `formData` in `this.http.post(..., formData, ...)`).
3d. Confirm existing credentials storage picks up `company_id` for reuse (already done
    via `response.body.user.company_id`).

**Dependencies:** Task 1.

**Risk:** Low — `company_id` is optional on the backend; sending it is additive.

---

### Task 4 — Mobile effort sizing (app-mobileclient)

**Not a design or implementation task.** Sizing only.

**What exists today:**
- `LoginHttp.PostLogin` constructs the body with `email`, `password`, `remember`
  (`lib/http/login/login_http.dart:22-31`). No `company_id`.
- The configuration blob is in `SharedPreferences['configuration']` and already accessed
  before the login call (line 10-14).
- Adding `company_id` requires: (a) setup returns it in the configuration blob (Task 2),
  (b) `LoginHttp.PostLogin` reads `configuration['company_id']` from the blob and adds it
  to the body.

**Effort sizing: Small.**

- One field added to `LoginHttp.PostLogin` body.
- One field read from the already-loaded configuration map.
- No state machine changes, no new screens, no new dependencies.
- The provisioning (QR scan → setup call → store config) already works; the config blob
  just needs `company_id` in it.

**The only risk:** if `company_id` is absent from the config blob (e.g., a configuration
that was not yet populated in Task 2), the mobile sends no `company_id` and the backend
falls back to first-found — unchanged current behavior, correct for non-collision users.

**Blocked on:** Task 2 (setup must return `company_id`).

---

## Mobile effort sizing

| Dimension | Assessment |
|---|---|
| Files to change | `lib/http/login/login_http.dart` (1 file, 1 line added to body) |
| Prerequisite | Task 2 (setup returns `company_id` in config blob) |
| New screens | None |
| New dependencies | None |
| Testing | Manual test with a collision-user config; one unit test for `PostLogin` body |
| Effort | Small (< 1 day of Dart work once setup is done) |
| Risk | None for non-collision users; collision users remain broken until both Task 2 and Task 4 are done |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Setup has no mapping to app company_id | Task 2 is blocked; mobile cannot discover company_id | Decide mapping strategy before Task 2 starts; may require an admin UI or a rake task to backfill |
| Partial rollout: some configs have company_id, others don't | Mixed population: some mobile users send company_id, others don't | Backend fallback branch handles this correctly; no action needed |
| Devise web form (`/sign_in`) remains unscoped if Option C chosen | Admin users with collision emails cannot log in via web form | Confirm whether collision users ever use the Devise form; if yes, choose Option A or B |
| `Warden::Manager.before_failure` runs unscoped lookup | Failure `SecurityEvent` logs wrong user_id when collision exists | Update hook to pass `company_id` from params when present (subtask 1c) |
| Mobile backward compat | Collision users on un-updated mobile still fail | Acceptable per the engineer's stated plan; non-collision users unaffected |
| company_id not in Angular env file for web client | Web client cannot send company_id at initial login | Engineer to confirm whether env file is the right source; alternative is a setup-call before login |

---

## Open questions for the engineer

1. **Setup ↔ app mapping**: How does the `Configuration` in setup know which
   `company_id` to return? Does each configuration correspond to exactly one company?
   Is there an existing admin UI that creates configurations, and could `company_id`
   be added there?

2. **Devise web form (`/sign_in`)**: Is the Devise web form used by anyone other than
   internal/admin users? If collision emails can reach it, Option A or B is needed. If
   it is purely internal and collision users never use it, Option C suffices.

3. **Web client `company_id` source before first login**: The web client is deployed
   per-tenant — is `company_id` available in the Angular environment file? Or does the
   web client need to call setup before login?

4. **`company_id` type**: In the app schema (`app/db/schema.rb:2326`), `company_id` on
   users is `integer`. In the setup configurations table, no `company_id` column exists
   yet. When added, it should be `integer` to match; confirm.

5. **`Warden::Manager.before_failure` scope**: The hook reads only
   `request.params.dig('user', 'email')` for the unscoped lookup. The JSON sessions
   controller reads `params[:email]` (not nested under `user`). These are different
   param shapes. The failure hook only fires for the Devise web form path (the JSON
   controller returns 401 directly). Worth confirming before subtask 1c.

6. **Confirm `:recoverable` is absent**: The `devise` call in `user.rb` lists
   `database_authenticatable, lockable, registerable, rememberable, trackable, timeoutable`
   — no `:recoverable`. The schema has `reset_password_token` and `reset_password_sent_at`
   columns (schema:2347-2348). Was `:recoverable` removed intentionally, or was it
   never included? If the columns exist but the module is not active, Devise will not
   call `send_reset_password_instructions` via its normal route. Confirm this is expected
   and close the password reset question.

---

## Sources

- `app/app/controllers/sessions_controller.rb:7` — current unscoped login lookup
- `app/app/models/user.rb:12` — Devise modules in use (no `:recoverable`)
- `app/config/initializers/devise.rb:1-353` — full Devise config and Warden hooks
- `app/config/routes.rb:94-98` — sessions routes and devise_for mount
- `app/db/schema.rb:2323-2369` — users table, composite index on `(company_id, email)`
- `app/db/schema.rb:504-533` — companies table with `basic_authentication` flag
- `app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb:263-269` — `find_for_authentication` and `find_first_by_auth_conditions` defaults
- `app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/database_authenticatable.rb:198-200` — `find_for_database_authentication` delegates to `find_for_authentication`
- `app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb:128-167` — `authentication_keys` strategy behavior with hash values
- `app/app/models/session.rb:8-27` — session payload (already includes `company_id`)
- `app/app/controllers/authentication/sessions_controller.rb:85-90` — SSO already scoped to company
- `setup/app/controllers/api/v1/devices/configurations_controller.rb:9-32` — how config is served
- `setup/app/serializers/configuration_serializer.rb:3-6` — configuration response fields
- `setup/db/schema.rb:18-36` — configurations table (no `company_id` column)
- `setup/app/models/configuration.rb:1-23` — Configuration model (no `company_id`)
- `app-webclient/src/app/login/login.component.ts:57-63` — login form fields (no `company_id`)
- `app-webclient/src/app/core/authentication/authentication.service.ts:27-57` — login POST
- `app-webclient/src/app/login/login.model.ts:1-17` — Login model interface
- `app-mobileclient/lib/http/login/login_http.dart:7-43` — full mobile login HTTP call
- `app-mobileclient/lib/model/bloc/bloc_login.dart:1-23` — BlocLogin connecting UI to HTTP
- `app-mobileclient/lib/http/device/device_http.dart:40-98` — device provisioning (hardcoded to setup.app4shark.com)
- Devise wiki scope-to-subdomain pattern: `~/.claude/plans/active/spike/devise-tenant-scoped-email/devise_doc_1_scope_login.txt`
- Devise wiki scope email validation caveat: `~/.claude/plans/active/spike/devise-tenant-scoped-email/devise_doc_2_scope_email_validation.txt`
- Prior spike full analysis: `~/.claude/plans/active/spike/devise-tenant-scoped-email/SPIKE.md`
