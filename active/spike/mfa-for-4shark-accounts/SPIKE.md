# SPIKE — Second Authentication Factor for 4Shark's Own Accounts on `app`

## Investigation question

How complex is it to add a second authentication factor to 4Shark's own accounts on the `app` platform (local email + password login, `POST /sessions`), scoped initially to Super Admin accounts, and does a maintained library already do it so TOTP is not built by hand? The hard constraint from the engineer: the factor must be generated locally by the authenticator (TOTP app or WebAuthn/FIDO2 hardware key) — no SMS, no email codes.

Driver: Atento TPRM questionnaire item 6.5 (MFA on all administrative-access accounts), currently `NO`. It fails on the one surface where a 4Shark employee authenticates with credential + password locally on the platform, on an account that can create users and reset passwords inside client organizations.

## Sources consulted

- `app/app/controllers/sessions_controller.rb` — the local login endpoint and its Devise/company gate
- `app/app/models/user.rb` — Devise module list (no two-factor module present)
- `app/config/routes.rb` — routing surface for sessions, including the parallel Devise-web and SSO paths
- `app/Gemfile` / `app/Gemfile.lock` — confirms no OTP/2FA/WebAuthn gem, and pins Devise 5.0.4 / Rails ~> 8.1.3
- `app/app/models/company.rb`, `app/db/schema.rb` (companies table) — `basic_authentication`/`client` boolean columns
- `app/app/models/seat.rb`, `app/app/models/super_admin.rb` — the `Seat` STI hierarchy and `SuperAdmin` subclass
- `app/docs/architecture/SECURITY_EVENTS.md` — the event catalog and its design rationale (synchronous, no worker, no rescue)
- `app/app/models/security_event.rb` — the frozen event-type/severity constants
- `app/app/models/authenticator_configuration.rb`, `app/app/controllers/authentication/sessions_controller.rb`, `app/app/models/authenticator_configuration/azure_identity_provider.rb` — the existing per-company SSO mechanism
- `app-webclient/src/app/core/authentication/authentication.service.ts`, `app-webclient/src/app/login/login.component.ts`, `login.model.ts` — the frontend login flow
- `dot-claude/docs/PROJECTS-CATALOG.md:102` — documented scope of the `keycloak` project
- `https://rubygems.org/gems/devise-two-factor` and `/versions/6.4.0/dependencies` — current release and dependency constraints
- `https://github.com/devise-two-factor/devise-two-factor` (README + API) — setup requirements, encryption, backup codes
- `https://api.github.com/repos/devise-two-factor/devise-two-factor` — repository activity (`pushed_at`, `open_issues_count`, `archived`)
- `https://rubygems.org/gems/rotp`, `https://api.github.com/repos/mdp/rotp`, `https://api.github.com/repos/mdp/rotp/commits` — rotp release and commit recency
- `https://rubygems.org/gems/webauthn`, `https://api.github.com/repos/cedarcode/webauthn-ruby`, `https://github.com/cedarcode/webauthn-ruby/blob/master/README.md` — webauthn-ruby release, activity, and challenge-storage requirement
- `https://rubygems.org/gems/active_model_otp`, `https://api.github.com/repos/heapsource/active_model_otp`, `https://libraries.io/rubygems/active_model_otp` — active_model_otp release and repository activity
- `https://docs.keycloak.org` family / community sources on Keycloak conditional-OTP configuration (via `WebSearch`, summarized below — no single page fetched and quoted; treated as background, not a Finding)

## Findings

### Finding 1 — the local login endpoint is a single, bespoke insertion point

**Evidence:**

```ruby
# app/app/controllers/sessions_controller.rb:6-17
def create
  authentication_parameters = { email: params[:email] }
  authentication_parameters[:company_id] = params[:company_id] if params[:company_id].present?
  user = User.enabled.find_for_database_authentication(authentication_parameters)

  valid_credentials =
    user.present? &&
    user.company.enabled? &&
    user.company.basic_authentication? &&
    user.valid_password?(params[:password])

  if valid_credentials
    ...
    render json: Session.new(user).payload, status: :created
```

**Significance:** `POST /sessions` (`app/config/routes.rb:94`) is a hand-rolled controller, not Devise's own session flow. It validates the password and immediately renders a full session payload (JWT + user data) in one step. This is the one place a second-factor check would be inserted for the password path. `config/routes.rb:96` also declares `devise_for :users, skip: :registrations, path: ''` — the standard Devise routes exist alongside the bespoke controller, and `SECURITY_EVENTS.md:31` documents that this Devise path is still reachable (`devise_web` auth method, "Devise web form login at `/users/sign_in`. Gates the Rails root page only, not the JWT product") via Warden hooks in `config/initializers/devise.rb:286-345` (`Warden::Manager.after_authentication`, `before_failure`, `before_logout`). A TOTP/WebAuthn requirement scoped to the JWT product only needs `SessionsController#create`; the Devise-web path is a separate, narrower surface (it "gates the Rails root page only") that would need its own decision if in scope.

**Source:** `app/app/controllers/sessions_controller.rb:6-17`, `app/config/routes.rb:94,96`, `app/docs/architecture/SECURITY_EVENTS.md:31`

### Finding 2 — no 2FA module exists today; Devise 5.0.4 on Rails ~> 8.1.3

**Evidence:**

```ruby
# app/app/models/user.rb:12-13
devise :database_authenticatable, :lockable, :registerable, :rememberable, :trackable, :timeoutable,
       authentication_keys: { email: true, company_id: false }
```

```
# app/Gemfile:8,11
ruby '4.0.6'
gem 'rails', '~> 8.1.3'
```

```
# app/Gemfile.lock:202
devise (5.0.4)
```

**Significance:** No `:two_factor_authenticatable`, `:two_factor_backupable`, `otp_secret`, or any related column/module exists on `User` or in the schema. The Gemfile carries no `devise-two-factor`, `rotp`, `active_model_otp`, or `webauthn` gem. Any path (library or hand-rolled) starts from zero.

**Source:** `app/app/models/user.rb:12-13`, `app/Gemfile:8,11`, `app/Gemfile.lock:202`

### Finding 3 — a per-company authentication-mode gate already exists, and it decides whether the password path is even reachable

**Evidence:**

```ruby
# app/app/models/user.rb:429-433
def basic_authentication?
  return false if company_id.nil?

  company.basic_authentication?
end
```

```
# app/db/schema.rb:508-509
t.boolean "basic_authentication", default: true, null: false
t.boolean "client", default: true
```

```ruby
# app/app/models/company.rb:150-152
def main?
  !client?
end
```

**Significance:** `basic_authentication` is a per-company boolean column (default `true`), not a code-level constant — `SessionsController#create` requires it before accepting a password login at all. `client` is also a boolean column (default `true`); `Company#main?` is `!client?`, i.e. the "main" company is the one row with `client: false`. This is the same predicate `config/routes.rb:11,18` uses to gate `/sidekiq`, `/pg_extras`, and `/api/docs` (`user.company.main? || user.seat.role.unscoped_queries?`), confirming `main?` identifies 4Shark's own internal tenant as distinct from every client company. **Not found**: which specific company row is `client: false` in any given environment, or whether it currently has `basic_authentication: true` — that is data, not code, and was not queried (no production DB access; per `AWS Policy`/`Production Access`, that would need the engineer to provide the value or a read via the app itself).

**Source:** `app/app/models/user.rb:429-433`, `app/db/schema.rb:508-509`, `app/app/models/company.rb:150-152`, `app/config/routes.rb:11,18`

### Finding 4 — Keycloak, as deployed today, does not participate in `app`'s SSO flow at all, and is documented as client-only

**Evidence:**

```
# dot-claude/docs/PROJECTS-CATALOG.md:102
| `keycloak` | HCL / Docker | The **authenticator** (a Keycloak deployment, the `auth-001` instance) — an
**optional** SSO layer for a client's users. It sits in front of the web and mobile clients and redirects to
`app` after authentication. For clients only; 4Shark does not use it for internal application auth. A
dedicated flow, unrelated to setup or onboarding. |
```

```ruby
# app/app/models/authenticator_configuration.rb:4,26-32
PROVIDERS = %w[microsoft google].freeze
...
def identity_provider
  @identity_provider ||= AzureIdentityProvider.new(self)
end
```

```ruby
# app/app/controllers/authentication/sessions_controller.rb:65-71,77-91
def authenticator_configuration
  ...
  @authenticator_configuration = AuthenticatorConfiguration.find_by(uuid: params[:id])
end

def current_user
  ...
  if authenticator_configuration.identity_provider_user_uuid.present?
    user_identifier = authenticator_configuration.find_user_identifier_by(code: params[:code], base_url: request.base_url)
    ...
  else
    email = authenticator_configuration.find_user_email_by(code: params[:code], base_url: request.base_url)
    ...
  end
end
```

**Significance:** `app`'s existing SSO mechanism (`AuthenticatorConfiguration` + `Authentication::SessionsController`) is a per-company, direct-to-IdP OIDC/SAML integration — `PROVIDERS` accepts only `microsoft` and `google`, and the identity-provider class it instantiates (`AzureIdentityProvider`, file at `app/app/models/authenticator_configuration/azure_identity_provider.rb`) is hardcoded regardless of the `provider` value. No `Keycloak` string appears anywhere in the `app` repository's `app/` or `docs/` trees (checked via `Grep`, zero matches). So the two things the engineer asked to be evaluated as a single option — "federate 4Shark's own company to the existing Keycloak" — are actually two separate facts: (a) `PROJECTS-CATALOG.md` documents Keycloak as scoped to client end users only, and (b) even setting that documented scope aside, `app`'s current SSO code path has no wiring to Keycloak at all — it would need a new `provider` value, a new identity-provider class alongside `AzureIdentityProvider`, and (per Finding 3) `main?`'s company would need `basic_authentication: false` and a new `AuthenticatorConfiguration` row pointed at a Keycloak realm that itself enforces OTP. This is a real, buildable path — Keycloak's own conditional-OTP mechanism is a documented product feature (community sources describe a "Conditional OTP Form" execution inside a browser authentication flow) — but it is not a configuration-only change to an already-wired integration; it is new integration code in `app` plus a Keycloak realm/flow to administer.

**Source:** `dot-claude/docs/PROJECTS-CATALOG.md:102`, `app/app/models/authenticator_configuration.rb:4,26-32`, `app/app/controllers/authentication/sessions_controller.rb:65-71,77-91`

**Verification block:** `PROJECTS-CATALOG.md` was read directly via `Read` (file:line citation, not fetched externally). The `AuthenticatorConfiguration`/`AzureIdentityProvider` code was read directly via `Read`/`Grep` in the `app` repository. No external URL is load-bearing for this finding's core claim; the Keycloak conditional-OTP background is WebSearch summary only, not quoted as a Finding.

### Finding 5 — `devise-two-factor` is the maintained option; `rotp` is its dependency and is also alive; `active_model_otp` is stale at the gem-release level despite recent repo commits

**Evidence:**

```
# RubyGems, gem page for devise-two-factor
Latest Version: 6.4.0, released February 02, 2026
```

```
# RubyGems, /gems/devise-two-factor/versions/6.4.0/dependencies
activesupport >= 7.2, < 8.2
devise >= 4.0, < 6.0
railties >= 7.2, < 8.2
rotp ~> 6.0
```

```
# GitHub release notes for devise-two-factor 6.4.0
"Drop support for EOL rails versions"
"Allow devise version five in gemspec"
```

```
# https://api.github.com/repos/devise-two-factor/devise-two-factor
pushed_at: 2026-06-22T01:02:35Z
open_issues_count: 45
archived: false
```

```
# https://api.github.com/repos/mdp/rotp/commits (most recent 5)
bad1a35  2025-06-03T23:49:27Z
b186a11  2025-06-03T23:48:44Z
...
```

```
# https://api.github.com/repos/mdp/rotp
pushed_at: 2025-11-24T21:17:25Z
open_issues_count: 11
archived: false
```

```
# https://api.github.com/repos/heapsource/active_model_otp
pushed_at: 2026-05-02T01:46:48Z
open_issues_count: 12
archived: false
```

```
# RubyGems, gem page for active_model_otp
Latest Version: 2.3.4, released April 18, 2024
```

**Significance:** `devise-two-factor` 6.4.0's own dependency constraint is `activesupport/railties >= 7.2, < 8.2` — `app` pins Rails `~> 8.1.3` (Finding 2), which satisfies `< 8.2`. Its `devise` constraint is `>= 4.0, < 6.0`, and `app` pins Devise 5.0.4 — inside range. The gem's own release notes explicitly call out dropping EOL Rails support and allowing Devise 5, meaning this compatibility is a deliberate, recent maintenance action, not an accident of wide version ranges. Its GitHub repo shows a push six weeks before this spike and is not archived. `rotp` (the gem `devise-two-factor` depends on for the actual TOTP math) has commits as recent as June 2025 and a repository `pushed_at` of November 2025 — not archived, actively pushed to, though its last tagged *gem* release on RubyGems is 6.3.0 (August 2023); the commit history shows work landing on `main` without a new gem cut in that window. `active_model_otp`'s repository is also not archived and was pushed to as recently as May 2026, but its RubyGems release cadence stopped at 2.3.4 in April 2024 — over two years stale at the point of publication, against `devise-two-factor`'s six-week-old release. Given the engineer's ask to report current maintenance honestly: `devise-two-factor` is the actively-released, actively-compatible option; `rotp` (its transitive dependency) is alive at the repository level even though its own gem tag is older; `active_model_otp` is the weakest of the three by release cadence even though its repository is not dormant.

**Source:** `https://rubygems.org/gems/devise-two-factor`, `https://rubygems.org/gems/devise-two-factor/versions/6.4.0/dependencies`, `https://github.com/devise-two-factor/devise-two-factor/releases`, `https://api.github.com/repos/devise-two-factor/devise-two-factor`, `https://api.github.com/repos/mdp/rotp/commits?per_page=5`, `https://api.github.com/repos/mdp/rotp`, `https://api.github.com/repos/heapsource/active_model_otp`, `https://rubygems.org/gems/active_model_otp`

**Verification block:** Each URL above was fetched via `WebFetch`; the RubyGems dependency page and the `devise-two-factor` GitHub repo were each fetched twice in this session (once for the initial claim, once as part of a follow-up query) and returned consistent version/date figures both times — the closest self-check available given `WebFetch` returns a processed summary rather than raw HTML, not a byte-level re-confirmation. Quote substrings above are as returned by the tool from each cited URL.

### Finding 6 — `webauthn-ruby` is actively maintained and its own setup instructions require a server-side challenge store this app does not currently have

**Evidence:**

```
# RubyGems, gem page for webauthn
Latest Version: 3.4.3 (released October 23, 2025)
Ruby Version Requirement: >= 2.5
```

```
# https://api.github.com/repos/cedarcode/webauthn-ruby
pushed_at: 2026-07-29T16:53:49Z
open_issues_count: 8
archived: false
```

```
# webauthn-ruby README (registration and authentication setup)
"Store the newly generated challenge somewhere so you can have it for the verification phase."
```

**Significance:** `webauthn-ruby` is well-maintained — a push six weeks before this session, 8 open issues, not archived — and satisfies `app`'s Ruby `4.0.6` easily (its own floor is `>= 2.5`). But its documented mechanics require a two-step handshake: the server generates a challenge, the browser's WebAuthn API signs it with the hardware key, and the server must have that same challenge available at verification time. The README's own examples store it in the Rails session (`session[:authentication_challenge]`). `app`'s `POST /sessions` flow is stateless JWT (Finding 1, Finding 7) — no server-side session exists between the first request (issue a challenge) and the second (verify the signed assertion). Building WebAuthn login here means adding a short-lived, per-attempt server-side store (Redis or a DB row with a TTL) purely to hold that challenge across the two round trips — infrastructure the password-only flow never needed.

**Source:** `https://rubygems.org/gems/webauthn`, `https://api.github.com/repos/cedarcode/webauthn-ruby`, `https://github.com/cedarcode/webauthn-ruby/blob/master/README.md`

**Verification block:** URLs fetched via `WebFetch`. The challenge-storage quote was fetched once, directly prompted to quote the storage instructions verbatim from the README; the tool returned the same "store...somewhere" phrasing for both the registration and authentication sections, which is internally consistent (the two sections of the same page agreeing) even without a separate re-fetch.

### Finding 7 — sessions are stateless, self-expiring JWTs with no server-side revocation; a 2FA rollout only changes future issuance, not tokens already in the wild

**Evidence:**

```ruby
# app/app/models/json_web_token.rb
class JsonWebToken
  SECRET_KEY = Rails.application.credentials.secret_key_base

  def self.encode(payload)
    payload[:exp] = Time.now.to_i + ApplicationConfiguration.jwt_token_expiration_ttl
    JWT.encode(payload, SECRET_KEY, 'HS256')
  end

  def self.decode(token)
    JWT.decode(token, SECRET_KEY, true, algorithm: 'HS256')[0]
  rescue StandardError
    nil
  end
end
```

**Significance:** There is no server-side session table and no revocation list — a JWT is valid until its `exp` claim (`ApplicationConfiguration.jwt_token_expiration_ttl`) passes, full stop. Enrolling second-factor requirements at `SessionsController#create` only affects the moment a **new** token is minted; a token issued yesterday keeps working exactly as it does today until it naturally expires. This means a 2FA rollout for existing Super Admins does not need a forced-logout step or a maintenance window to be safe — the risk window is bounded by whatever the existing TTL already is, not by the rollout itself. (`ApplicationConfiguration.jwt_token_expiration_ttl`'s actual value was not read in this spike — it is a Ruby method, not a literal, and its source was not located; `Not found: the concrete TTL value`.)

**Source:** `app/app/models/json_web_token.rb`

### Finding 8 — `Company` already has a precedent for a per-tenant opt-in boolean "module," and `Seat`/`SuperAdmin` gives a ready predicate for scoping to Super Admin only

**Evidence:**

```
# app/db/schema.rb:505-532 (companies table, partial)
t.boolean "deal_eligibility_module", default: false, null: false
t.boolean "goal_calculation_module", default: true, null: false
t.boolean "manager_legal_module", default: true, null: false
t.boolean "operator_legal_module", default: true, null: false
t.boolean "payment_api_exportation_module", default: false, null: false
t.boolean "subsidiaries_module", default: false, null: false
```

```ruby
# app/app/models/user.rb:208
scope :admin, -> { joins(:seat).where('seats.type': 'Admin') }
```

```ruby
# app/app/models/super_admin.rb
class SuperAdmin < Seat
  def subordinated_seats
    %w[SuperAdmin Admin Director Superintendent Manager Coordinator Supervisor SalesRepresentative]
  end
end
```

**Significance:** The codebase's existing idiom for "this behavior is opt-in per tenant" is a `*_module` boolean column on `companies`, e.g. `security_events_module` (`app/docs/architecture/SECURITY_EVENTS.md:5`: *"The store is opt-in per company via the `security_events_module` boolean on `companies`"*). A second-factor requirement follows the same shape naturally. Scoping "Super Admin accounts only" is a one-line predicate against the existing `Seat` STI table — the same pattern `User.admin` already uses for `Admin` — e.g. `joins(:seat).where('seats.type': 'SuperAdmin')`, with no new column needed for the seat-type check itself. Whether the per-user "is 2FA required for this account" flag lives directly on `users` (à la `devise-two-factor`'s `otp_required_for_login`) or is derived at login time from `seat.type == 'SuperAdmin'` is a design choice the codebase does not settle by itself.

**Source:** `app/db/schema.rb:505-532`, `app/docs/architecture/SECURITY_EVENTS.md:5`, `app/app/models/user.rb:208`, `app/app/models/super_admin.rb`

### Finding 9 — the security-events catalog has no enrollment or second-factor event types today, and its own design doc states its capture sites are enumerated deliberately

**Evidence:**

```ruby
# app/app/models/security_event.rb:30-34
TYPES =
  %w[api.token_created api.token_revoked authentication.account_locked authentication.account_unlocked
     authentication.login_failure authentication.login_success authentication.logout
     authentication.password_change_failure authentication.password_changed authentication.password_reset
     authentication.session_refresh user.created user.disabled user.reactivated].freeze
```

**Significance:** No `mfa`/`otp`/`two_factor` event type exists in the frozen `TYPES` list, and `SEVERITY_BY_TYPE` (`app/app/models/security_event.rb:12-28`) would need a matching new key for each new type — the model's own `fetch` on that map "fails loudly if a new event type is added to `TYPES` without a severity" (`SECURITY_EVENTS.md:112`). Adding 2FA means extending this whitelist (at minimum something like enrollment success, challenge success, challenge failure) and deciding severities, following the same synchronous, no-rescue, no-worker capture pattern the doc documents for every other event (`SECURITY_EVENTS.md:321-338`) — this is a small, mechanical extension of an existing pattern, not new architecture.

**Source:** `app/app/models/security_event.rb:12-34`, `app/docs/architecture/SECURITY_EVENTS.md:112,321-338`

### Finding 10 — the frontend login is a single form and a single HTTP call; a second factor means a genuinely new partial-auth state, not a cosmetic addition

**Evidence:**

```typescript
// app-webclient/src/app/core/authentication/authentication.service.ts:29-63
login(formData: Login): Observable<HttpResponse<any> | HttpErrorResponse> {
  const loginUrl = `${environment.graphql_api_server}/sessions`;
  this.credentialsService.destroyCredentials();
  ...
  return this.http.post<any>(loginUrl, body, { observe: 'response' }).pipe(
    map((response: HttpResponse<any>) => {
      this.credentialsService.setCredentials(response.body, formData.remember);
      this.analyticsService.setUser(response.body.user.id);
      this.analyticsService.emitEvent('login', { method: 'password' });

      if (response.body.user.registration_password) {
        this.router.navigateByUrl('/change_password').then();
      } else if (response.body.user.pending_legal_documents_acceptance) {
        this.router.navigateByUrl('/legalDocumentAcceptance').then();
      } else if (this.route.snapshot.queryParams.redirectTo) {
        this.router.navigateByUrl(this.route.snapshot.queryParams.redirectTo).then();
      } else if (this.accessControlService.hasPermission('holdingDashboard')) {
        this.router.navigateByUrl('/dashboard/maps/america').then();
      } else {
        this.router.navigateByUrl('/dashboard/calendars').then();
      }

      return response;
    }),
    ...
  );
}
```

```typescript
// app-webclient/src/app/login/login.component.ts:34-52
login() {
  this.error = null;
  this.logging = true;

  this.authService.login(this.loginForm.value).subscribe(
    () => { this.logging = false; },
    (errors: HttpErrorResponse) => {
      if (errors.status === 401) {
        this.error = this.translateService.instant('user.form.username_password_incorrect');
        ...
      }
    },
  );
}
```

**Significance:** `AuthenticationService#login` treats the `POST /sessions` response as final — it stores credentials and navigates immediately on any non-error response, and the component only has one error branch (`401` → wrong password). This is exactly the small-looking-hides-real-work case the engineer flagged: a second factor requires the backend to return a distinct, non-`201` (or a `201` with a distinguishing field) "partial authentication, OTP required" response instead of a session payload; the frontend needs a new intermediate screen (OTP code entry, or a WebAuthn browser-API prompt) that holds a partial-auth reference (e.g. a short-lived token identifying "this credential check passed, waiting on the second factor") and only calls a **second** endpoint to actually receive the JWT and complete the existing navigation logic above. This is genuinely new frontend state — a partial-auth flow, a new route/component, error handling for a wrong OTP distinct from a wrong password, and (for the enrollment side) a first-time-setup screen to display the QR code and backup codes. None of this exists today in any form (no `mfa`/`otp`/`totp`/`webauthn` string found in `app-webclient/src/app/login/` or `app-webclient/src/app/core/authentication/`).

**Source:** `app-webclient/src/app/core/authentication/authentication.service.ts:29-63`, `app-webclient/src/app/login/login.component.ts:34-52`

### Finding 11 — Rails ActiveRecord Encryption (which `devise-two-factor` requires for the OTP secret) is already configured and used elsewhere in this codebase

**Evidence:**

```ruby
# app/app/models/authenticator_configuration.rb:21
encrypts :client_secret, :identity_provider_client_id, :identity_provider_client_secret, :identity_provider_tenant_id
```

```ruby
# app/app/models/user.rb:246
encrypts :unique_register_id, deterministic: true
```

```ruby
# app/app/models/payroll_integration.rb:12-14
encrypts :email, deterministic: true
encrypts :user_name, deterministic: true
encrypts :user_password, deterministic: true
```

```
# devise-two-factor README (fetched via WebFetch)
"Devise-Two-Factor uses ActiveRecord encrypted attributes. If you haven't already set up ActiveRecord
encryption you must generate a key set and configure your application to use them either with Rails'
encrypted credentials or from another source such as environment variables."
```

**Significance:** `encrypts` (Rails' built-in ActiveRecord Encryption, GA since Rails 7) is already used on four columns across three models in this codebase, which means the encryption key set `devise-two-factor` needs already exists and is already exercised in production-shaped code — this is not a new piece of infrastructure to stand up, only a new column (`otp_secret`) added to the same mechanism.

**Source:** `app/app/models/authenticator_configuration.rb:21`, `app/app/models/user.rb:246`, `app/app/models/payroll_integration.rb:12-14`, devise-two-factor README (fetched via `WebFetch` from `https://github.com/devise-two-factor/devise-two-factor`)

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| `devise-two-factor` + `rotp` (TOTP, authenticator app) | Actively maintained (6.4.0, Feb 2026); compatible with `app`'s Rails ~> 8.1.3 and Devise 5.0.4 by the gem's own stated constraint; reuses `app`'s existing ActiveRecord Encryption (Finding 11); backup codes built in (`generate_otp_backup_codes!`, bcrypt-hashed, single-use); no server-side challenge state needed (unlike WebAuthn) | Still needs a new backend response shape + endpoint for the second step, a new frontend partial-auth screen and enrollment/QR UI (Finding 10), a new `SecurityEvent` type set (Finding 9), and an admin-reset flow the gem does not provide out of the box | Findings 5, 6, 7, 9, 10, 11 |
| WebAuthn/FIDO2 hardware key (`webauthn-ruby`) | Actively maintained (3.4.3, Oct 2025); phishing-resistant by design; 4Shark already issues YubiKeys for the AWS break-glass account, so the physical-key operational pattern is not new to the org | Requires a server-side challenge store `app`'s stateless JWT login does not have today (Finding 6) — genuinely new infrastructure, not just a new column; same frontend partial-auth cost as TOTP, plus browser WebAuthn API integration; no backup-code equivalent is native (lost-key recovery is an admin process to design) | Findings 6, 10 |
| Federate 4Shark's own company to the existing Keycloak (`auth-001`) with OTP enforced there | Keycloak's conditional-OTP is a documented native feature, so TOTP enrollment/verification UI is Keycloak's, not `app`'s to build; no `devise-two-factor`/`webauthn-ruby` gem needed at all | Documented as client-only today (`PROJECTS-CATALOG.md:102`); `app`'s SSO code has zero wiring to Keycloak — it only speaks to Microsoft/Google directly (Finding 4) — so this path is new integration code (a Keycloak `provider` type, a new identity-provider class) plus a Keycloak realm to administer, not a configuration flip; still needs `basic_authentication: false` on the main company, meaning every 4Shark employee login moves off the password path entirely, not just Super Admins, unless a further split is designed | Findings 3, 4 |
| `active_model_otp` (TOTP, hand-integrated) | Also does TOTP/QR provisioning | Weakest release cadence of the candidates evaluated — last RubyGems release April 2024 versus `devise-two-factor`'s six-week-old 6.4.0 (Finding 5); not a Devise integration, so more of the enrollment/verification wiring `devise-two-factor` provides would need to be hand-built | Finding 5 |

## What remains uncertain

- Whether the 4Shark "main" company (`client: false`) currently has `basic_authentication: true`, and what its `id` is in each environment — this is data, not code, and was not queried (no production DB access per `Production Access` policy).
- The concrete value of `ApplicationConfiguration.jwt_token_expiration_ttl` (the JWT lifetime) — the method's source was not located in this spike; it decides how long a pre-2FA token stays valid after rollout (Finding 7).
- Whether "Super Admin accounts only" should be modeled as a per-user flag (`otp_required_for_login`-style, settable per account) or purely derived from `seat.type == 'SuperAdmin'` at login time — both are one-line implementations off existing structures (Finding 8), but they have different operational behavior when an account's seat type changes.
- Whether the Devise-web path (`/users/sign_in`, `devise_web` auth method) is in scope for the second factor, given `SECURITY_EVENTS.md:31` documents it as gating "the Rails root page only, not the JWT product" — the engineer's framing was about the JWT-issuing login, and this spike did not investigate what the Rails root page actually is or who uses it.
- Keycloak's own conditional-OTP mechanism was not verified against a primary Keycloak documentation page with a quoted, re-fetched substring in this spike (WebSearch summary only) — if the Keycloak path is pursued further, that deserves its own verified citation pass.
- No community source was found stating a specific migration/compatibility issue between `devise-two-factor` and Rails 8.1 beyond the gem's own stated version range (Finding 5); the range itself is the evidence, not a separate confirming report.

## Suggested options for main and the engineer

- **Option A — `devise-two-factor` + `rotp` (TOTP via authenticator app).** Sustained by Findings 2, 3, 5, 7, 8, 9, 10, 11. Adds `otp_secret`/`otp_required_for_login`/backup-code columns to `users`, a new "OTP required" branch in `SessionsController#create`, a new verification endpoint, a new frontend partial-auth screen + enrollment UI, new `SecurityEvent` types, and a `SuperAdmin`-scoped gate (per-user flag or seat-type derived). No new server-side state beyond the DB.
- **Option B — WebAuthn/FIDO2 hardware key via `webauthn-ruby`.** Sustained by Findings 2, 6, 7, 10. Same backend/frontend/event-catalog shape as Option A, plus a new short-lived server-side challenge store this login flow does not currently have, and no built-in backup-code equivalent — lost-key recovery is a 4Shark-designed admin process.
- **Option C — federate 4Shark's own company to Keycloak with OTP enforced there.** Sustained by Findings 3, 4. Removes the need to build TOTP/WebAuthn logic inside `app` at all, but requires new integration code (a Keycloak provider type + identity-provider class) plus administering a Keycloak realm, and currently would move every login on the main company off the password path — not a Super-Admin-only cut without further design.
- **Option D — combine A/B and C's scoping idea:** use Option A or B for the mechanism, but gate it as a company-level `*_module` boolean (Finding 8's existing idiom) so it can later extend past Super Admin without new columns.

No option is recommended here — the choice is the engineer's, per the library-maintenance evidence in Finding 5 and the cost breakdown in Findings 6 and 10.

---

> **Authoring:** written by `@agent-spike` as time-boxed research to reduce uncertainty. Surfaces findings + options — does NOT recommend or pick; main and the engineer choose. Every claim cites its source (`file:line` + quote, or URL + quote); an uncitable claim is written as "Not found: <…>" instead. Large or structured evidence goes to auxiliary files (`{topic}_{kind}_{n}.{ext}`) in the same directory, each referenced from this document by relative link. The `output-verifier` runs the seven structural checks after the write — including citation integrity and auxiliary-file integrity — and the `policy-verifier` checks convention conformance.
