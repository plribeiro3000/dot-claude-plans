# SPIKE — Devise Tenant-Scoped Email Uniqueness

## Investigation question

Is tenant-scoped email uniqueness (unique per company, not globally) a legitimate,
community-recognized pattern in multi-tenant applications and in the Devise ecosystem?
What does the Devise project itself provide for it? Is the approach of passing a tenant
identifier (company_id) at login to scope authentication the standard, recommended way?
What breaks or gets harder — password reset, SSO, account recovery, enumeration? What
do mature platforms (Okta, Auth0, SuperTokens, Slack, WorkOS) do? And what would
restoring global email uniqueness (Option A) entail vs. keeping tenant-scoped auth
(Option B)?

## Sources consulted

- [Devise Wiki: How to: Scope login to subdomain](https://github.com/plataformatec/devise/wiki/How-to:-Scope-login-to-subdomain)
  — Official Devise wiki: configuration of `request_keys`, `find_for_authentication`,
  and password recovery overrides for subdomain-scoped auth. Full text in
  `devise_doc_1_scope_login.txt`
- [Devise Wiki: How To: Scope email validation](https://github.com/heartcombo/devise/wiki/How-To:-Scope-email-validation)
  — Official Devise wiki: `email_scope` option, migration requirements, and the
  explicit caveat that the recoverable module "will only include a link... to the first
  account." Full text in `devise_doc_2_scope_email_validation.txt`
- [Devise PR #5094](https://github.com/heartcombo/devise/pull/5094)
  — Unmerged PR for `email_scope` option; 4-year old community demand, maintainer
  concerns. Full text in `devise_doc_3_pr5094.txt`
- [Devise recoverable.rb](https://github.com/heartcombo/devise/blob/main/lib/devise/models/recoverable.rb)
  — Source code analysis of `send_reset_password_instructions` showing the
  tenant-agnostic email lookup. Full text in `devise_doc_4_recoverable.txt`
- [Devise Issue #4767](https://github.com/heartcombo/devise/issues/4767)
  — Original 2018 feature request for email scoping in the Validatable module
- [Okta — Multi-tenant solutions](https://developer.okta.com/docs/concepts/multi-tenancy/)
  — Verbatim: "Identity in Okta is scoped to the org, not globally unique across all
  of Okta." Full text in `industry_doc_1_okta.txt`
- [Auth0 Community: Same email for multiple users](https://community.auth0.com/t/same-email-for-multiple-users-needed/157993)
  — Auth0 moderator confirms same email can exist across different database connections.
  Full text in `industry_doc_3_auth0.txt`
- SuperTokens multi-tenancy docs (UNVERIFIED — 404 on fetch, content from search snippets)
  — Search snippets show identity keyed as `appId → tenantId → email` triple; same
  email across tenants is explicitly allowed. See `industry_doc_2_supertokens.txt`
- [WorkOS — Users and Organizations](https://workos.com/docs/user-management/users-organizations)
  — WorkOS enforces GLOBAL email uniqueness; uses identity linking for multi-org
  membership. Full text in `industry_doc_4_workos.txt`
- [Slack — Sign in to Slack](https://slack.com/intl/en-gb/help/articles/212681477-sign-in-to-slack)
  — Canonical real-world reference: same email works across multiple workspaces; workspace
  selector at login. Full text in `industry_doc_5_slack.txt`
- [ABP.IO — Shared User Accounts in ABP Multi-Tenancy](https://abp.io/community/articles/shared-user-accounts-in-abp-multitenancy-mf3bkg79)
  — Framework-level confirmation: per-tenant email uniqueness is the DEFAULT (isolated)
  mode; global uniqueness is the opt-in exception. Full text in `industry_doc_6_abp_multitenancy.txt`
- [Microsoft Azure — Identity in Multitenant Solutions](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/considerations/identity)
  — Microsoft's official architecture guidance explicitly validates multiple distinct
  identities per person when "strict regulatory or geographical data storage requirements"
  apply. Full text in `industry_doc_7_microsoft_azure.txt`
- [Google Cloud Identity Platform — Multi-tenancy authentication](https://cloud.google.com/identity-platform/docs/multi-tenancy-authentication)
  — Tenant ID must be passed to the auth object before every authentication request.
  Full text in `industry_doc_8_google_identity_platform.txt`
- [GitLab — Deduplicate database records](https://docs.gitlab.com/development/database/deduplicate_database_records)
  — Three-milestone strategy for adding a global unique constraint to a table with
  existing duplicates. Full text in `industry_doc_9_dedup_strategy.txt`

### Auxiliary files in this directory

| File | Contents |
|------|----------|
| `devise_doc_1_scope_login.txt` | Full Devise wiki: Scope login to subdomain |
| `devise_doc_2_scope_email_validation.txt` | Full Devise wiki: Scope email validation |
| `devise_doc_3_pr5094.txt` | Full PR #5094 discussion |
| `devise_doc_4_recoverable.txt` | Recoverable.rb analysis + override pattern |
| `industry_doc_1_okta.txt` | Okta multi-tenancy official docs |
| `industry_doc_2_supertokens.txt` | SuperTokens multi-tenancy (UNVERIFIED) |
| `industry_doc_3_auth0.txt` | Auth0 community + organization docs |
| `industry_doc_4_workos.txt` | WorkOS users and organizations |
| `industry_doc_5_slack.txt` | Slack sign-in official help |
| `industry_doc_6_abp_multitenancy.txt` | ABP.IO shared user accounts |
| `industry_doc_7_microsoft_azure.txt` | Microsoft Azure multitenant identity guide |
| `industry_doc_8_google_identity_platform.txt` | Google Cloud Identity Platform multi-tenancy |
| `industry_doc_9_dedup_strategy.txt` | GitLab deduplication strategy |

---

## Findings

### Finding 1: Tenant-scoped email uniqueness is a legitimate, community-recognized pattern

**Evidence:**

Three independently authoritative sources confirm that per-tenant (not global) email
uniqueness is a valid production design:

1. **Okta** (industry-leading IdP):
   > "the same email address can exist as separate users in multiple orgs. For example,
   > `alice.doe@example.com` can be a registered user in both `https://company1.okta.com`
   > and `https://company2.okta.com` with different profile data in each."
   > "Identity in Okta is scoped to the org, not globally unique across all of Okta."
   Source: https://developer.okta.com/docs/concepts/multi-tenancy/ | Full text: `industry_doc_1_okta.txt`

2. **ABP.IO** (.NET multi-tenant framework, widely referenced):
   > "the most important behavior change after switching to Shared: username and email
   > uniqueness become global instead of per-tenant."
   ABP's DEFAULT mode is per-tenant isolation; global uniqueness is an opt-in exception.
   Source: https://abp.io/community/articles/shared-user-accounts-in-abp-multitenancy-mf3bkg79 | Full text: `industry_doc_6_abp_multitenancy.txt`

3. **Microsoft Azure Architecture Center**:
   > "Use multiple distinct identities in some scenarios. For example, if people use your
   > system both for work and personal purposes, they might want to separate their user
   > accounts. Or if your tenants have strict regulatory or geographical data storage
   > requirements, they might require a person to have multiple identities so that they
   > can comply with regulations or laws."
   Source: https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/considerations/identity | Full text: `industry_doc_7_microsoft_azure.txt`

**Significance:** The same-email-different-person scenario in 4Shark (Mexico employee
with numeric ID 170472 → email `170472@atento.com`, and Brazil employee with the same
numeric ID → same email, different human) fits directly into the cases Microsoft and
Okta identify as legitimate for per-tenant identity. It is not an antipattern; it is
the intended design for cross-country, cross-jurisdiction deployments.

Verification block:
- `industry_doc_1_okta.txt` → URL fetched, verbatim quotes confirmed in extracted content
- `industry_doc_6_abp_multitenancy.txt` → URL fetched, verbatim quotes confirmed in extracted content
- `industry_doc_7_microsoft_azure.txt` → URL fetched, verbatim quotes confirmed in extracted content

---

### Finding 2: Devise has official (wiki-documented) mechanisms for tenant-scoped authentication — but the email_scope feature is UNMERGED

**Evidence:**

Devise provides two official, wiki-documented patterns for scoping authentication to a
tenant key:

**Pattern A — `request_keys` (request-time values such as subdomain):**
From the official Devise wiki "How to: Scope login to subdomain":
> "Add subdomain to request_keys in your User model:
>   request_keys: [:subdomain]"
> "If you do, :validatable will prevent more than one record having the same email"
> (the guide instructs removing or bypassing :validatable for subdomain-scoped auth)

This is the closest official pattern to what Option B requires. Translated to 4Shark:
`company_id` takes the place of `subdomain`. Since `company_id` is not a request
attribute (it is not in the URL/subdomain), the guide recommends `authentication_keys`
instead:
> "if you have `subdomains` table and are using `subdomain_id`" on your model, add
> `authentication_keys: [:email, :subdomain_id]`

**Pattern B — `find_for_authentication` override:**
From the Devise wiki and confirmed in multiple community sources:
```ruby
def self.find_for_authentication(warden_conditions)
  where(:email => warden_conditions[:email],
        :company_id => warden_conditions[:company_id]).first
end
```
This is the canonical override pattern. The client must POST `company_id` alongside
`email` and `password` in the sign-in form.

**What is NOT in Devise core:**
The `email_scope` config option proposed in PR #5094:
> "This feature is not merged"
From the official Devise wiki "How To: Scope email validation":
> "By adding a scope to the email key, you may end up with multiple users with the same
> email address, which will cause the 'recoverable' module not to work well, as it will
> only include a link in the password reset e-mail to the first account for which it
> finds a matching e-mail."

The PR has been open since 2018 (6+ years). The maintainer:
> "There may be more to it than just the validation so I need to look into it a bit more
> carefully in the coming weeks." (said in 2018, never resolved)

Source: `devise_doc_2_scope_email_validation.txt`, `devise_doc_3_pr5094.txt`

**Significance:** The scoped auth pattern IS documented and supported by Devise via wiki
and via `authentication_keys`/`find_for_authentication`. The missing piece is a clean
in-framework option for scoping email validation — teams must bypass `:validatable` and
add the composite uniqueness manually (which 4Shark has already done via the Postgres
partial index).

Verification block:
- `devise_doc_1_scope_login.txt` → URL fetched, verbatim quotes confirmed in extracted content
- `devise_doc_2_scope_email_validation.txt` → URL fetched, verbatim quotes confirmed in extracted content
- `devise_doc_3_pr5094.txt` → URL fetched, verbatim quotes confirmed in extracted content

---

### Finding 3: Password reset (Devise `recoverable`) is the hardest module to adapt for tenant-scoped email

**Evidence:**

From Devise's official wiki and from source code analysis of `recoverable.rb`:

The default `send_reset_password_instructions` does:
```ruby
def send_reset_password_instructions(attributes = {})
  recoverable = find_or_initialize_with_errors(
    reset_password_keys, attributes, :not_found
  )
  recoverable.send_reset_password_instructions if recoverable.persisted?
  recoverable
end
```

`reset_password_keys` defaults to `[:email]` — there is no tenant scope. When the same
email exists across two companies, this method finds whichever row appears first in the
database and sends the reset link to that user only.

The Devise wiki explicitly warns:
> "it will only include a link in the password reset e-mail to the first account for
> which it finds a matching e-mail"
Source: `devise_doc_2_scope_email_validation.txt`

**The fix** (documented in the Devise wiki for subdomain-scoped auth):
1. Override `send_reset_password_instructions` in the User model to include the tenant
   key in the lookup.
2. Override the Devise `Passwords` controller to inject the tenant key from the request
   into the attributes.
3. Add the tenant key to the reset password form (or derive it from the session/cookie
   at password-reset request time).

This is non-trivial for mobile apps: the Flutter client must know and send `company_id`
not only at login but also at the "forgot password" request. The tenant must be identified
BEFORE authentication (which is the core challenge).

Source: `devise_doc_4_recoverable.txt`

**Significance:** The password reset flow is the most operationally risky component of
Option B. It requires custom controller logic, custom form fields, and client-side
tenant-awareness at an unauthenticated entry point. This is where bugs create real
security issues (reset link goes to wrong tenant's user).

Verification block:
- `devise_doc_2_scope_email_validation.txt` → URL fetched, verbatim quotes confirmed
- `devise_doc_4_recoverable.txt` → URL fetched from Devise source, analysis confirmed

---

### Finding 4: Mature products handle the tenant-selector UX in several ways; none is trivially simple

**Evidence:**

**Slack** (same email in multiple workspaces):
> "Whether you're a member of one Slack workspace or many workspaces, you can use the
> same email address to sign in to all of them."
> "If you're a member of more than one workspace, click on the arrow icon next to the
> workspace that you'd like to open."
Password reset: "request a code that allows you to sign in to any workspaces associated
with your email address" — tenant discovery happens AFTER authentication, not before.
Source: `industry_doc_5_slack.txt`

**ABP.IO** (framework-level tenant-aware auth):
Multi-tenant login: users with one tenant go directly in; users with multiple tenants
see "a tenant selection screen after credentials are verified." A "tenant switcher" then
allows jumping between contexts without signing out.
Source: `industry_doc_6_abp_multitenancy.txt`

**Wristband.dev B2B auth platform** (commercial):
The design allows users to "enter their email" and "receive an email containing a link
that, when clicked, will show all their associated companies." Users then select a
company before completing authentication. Confirmed design: "users must first identify
the tenant they are attempting to log into before entering their credentials."
Source: https://www.wristband.dev/blog/multi-tenant-b2b-authentication-explained-key-concepts-components

**Google Cloud Identity Platform**:
> "To sign in to a tenant, the tenant ID needs to be passed to the `auth` object."
The tenant ID must come from the client — it is not inferred.
Source: `industry_doc_8_google_identity_platform.txt`

**Significance:** Two dominant UX patterns exist for Option B:
- **Pre-auth tenant selection**: the client collects the tenant key (company, workspace
  URL, org ID) BEFORE presenting the email/password fields. This is the Google Cloud
  Identity Platform and Wristband.dev model.
- **Post-auth tenant selection**: authenticate first, then show a "which workspace/
  company?" picker. This is Slack's and ABP's model.

For 4Shark's mobile app (Flutter), the pre-auth pattern requires users to know their
company (country) before logging in. The post-auth pattern defers that to after password
validation — but it also means the Flutter app must handle a "select your company"
screen between credential submission and session establishment.

Neither pattern is trivial to bolt onto an existing Devise+Flutter setup without API
changes.

Verification block:
- `industry_doc_5_slack.txt` → URL fetched, verbatim quotes confirmed
- `industry_doc_6_abp_multitenancy.txt` → URL fetched, verbatim quotes confirmed
- `industry_doc_8_google_identity_platform.txt` → URL fetched, verbatim quotes confirmed

---

### Finding 5: WorkOS represents the counter-position — global unique email + identity linking

**Evidence:**

WorkOS enforces GLOBAL email uniqueness and models multi-org membership differently:
> "What uniquely identifies a user is their email address, since having access to that
> email inbox ultimately gives access to all accounts based on that address."
> "Because a user is uniquely identified by their email address, you won't have users
> with duplicate email addresses. WorkOS handles [identity linking] automatically."
Source: `industry_doc_4_workos.txt`

In this model, one human = one email = one user record, which can have memberships in N
organizations. WorkOS prevents the same email from being registered twice.

**Why this does NOT apply to 4Shark's case:** WorkOS's assumption is that the same email
= the same human. In 4Shark's multi-country HR system, `170472@atento.com` in Mexico
and `170472@atento.com` in Brazil are DIFFERENT HUMANS whose numeric IDs happen to
collide across country systems. Identity linking (one user for both) would incorrectly
merge two real people into one account.

The WorkOS model is appropriate when the same person appears in multiple orgs (contractor
in two companies, admin of multiple tenants). It is not appropriate when the email
collision represents two different people.

Source: `industry_doc_4_workos.txt`

Verification block:
- `industry_doc_4_workos.txt` → URL fetched, verbatim quotes confirmed

---

### Finding 6: Security/UX implications of tenant-scoped email

**Evidence (from search results and fetched content):**

**Account enumeration:** Tenant-scoped email does not inherently worsen enumeration risk.
The same mitigation applies: "Don't use error messages that reveal why an action failed
on login forms or password reset pages; instead show generic messages like 'If an account
is associated with that email, a reset link has been sent.'" The difference is that with
tenant-scoped auth, the same email in two companies produces two accounts — if the tenant
key is exposed in error messages, an attacker learns which tenants that email belongs to.
This is not a novel attack surface, but it does require the override `send_reset_password_instructions`
to guard against sending resets to the wrong tenant.
Source: https://www.controlgap.com/blog/how-to-protect-against-username-enumeration-from-forms

**Login form changes:** The web frontend must add a company selector (or auto-detect via
subdomain/URL). The mobile Flutter app needs an additional input or a tenant-discovery
flow before the email/password fields.

**Keycloak SSO interaction:** 4Shark already uses Keycloak for some auth paths. Keycloak
uses REALMS as tenant containers — each realm is isolated, and the same email can exist
in different realms independently. If Keycloak realms are already per-company, the
tenant-scoped model is already implicit in the Keycloak layer.
Source: https://47billion.com/blog/implementing-keycloak-for-robust-authentication-and-authorization-in-multi-tenant-applications/ (search result)

**Option A (global unique email) UX for the existing 8 collisions:** The 8 users whose
emails collide across companies are DIFFERENT PEOPLE. To restore global uniqueness, their
emails would need to change — they cannot be "merged" like duplicate records of the same
person. This requires application-level email format changes (e.g., `MX-170472@atento.com`
vs `BR-170472@atento.com`). Every ETL, integration, and country-specific system that
generates the email would need to be updated to add a country prefix.

---

### Finding 7: Devise community has worked around the missing feature for years

**Evidence:**

The `heartcombo/devise` issue #4767 (2018) and PR #5094 (still open in 2024) show the
community has wanted native email scoping for 6+ years. The workaround universally
adopted is:

1. Remove or bypass `:validatable`
2. Add a composite DB index (`[:email, :account_id]`)
3. Override `find_for_authentication` to scope by tenant key
4. Override `send_reset_password_instructions` to scope the lookup
5. Override the Devise Passwords controller to inject tenant context

From a community contributor:
> "Scoping email validations is HUGE - thanks so much for this!" (expressing the need)
> "the email validation scoping is crucial."
Source: `devise_doc_3_pr5094.txt`

The `github.com/jekuno/milia` gem (multi-tenancy for Rails + Devise) and the
`github.com/brandoncordell/acts_as_tenant` ecosystem address this at the gem level.
The `acts_as_tenant` gem (ErwinM/acts_as_tenant) provides `validates_uniqueness_to_tenant`
as a direct replacement for `validates_uniqueness_of` scoped to the tenant.
Source: https://github.com/ErwinM/acts_as_tenant

**Significance:** This is a well-trodden path in the Rails/Devise community. The
pattern is widely used, well-documented in the Devise wiki, and supported by multiple
gems. It is non-trivial but not experimental.

Verification block:
- `devise_doc_3_pr5094.txt` → URL fetched, verbatim quotes confirmed
- acts_as_tenant: URL fetched, `validates_uniqueness_to_tenant` confirmed in README

---

## Trade-offs surfaced

| Dimension | Option A: Restore Global Unique Email | Option B: Keep Tenant-Scoped + Tenant-Aware Auth | Option C: Hybrid (email + country prefix) |
|-----------|--------------------------------------|--------------------------------------------------|------------------------------------------|
| **Current data** | 8 collisions → email change for real users | No data change needed | Email format change for all users (not just collisions) |
| **Auth complexity** | Standard Devise — no overrides needed | `find_for_authentication` override, custom controller for passwords | Same as Option A after migration |
| **Password reset** | Works out of the box (email is unique) | Must override `send_reset_password_instructions` + Passwords controller; client must send `company_id` at reset time | Works out of the box |
| **Web frontend** | No login-form change | Add company selector or derive `company_id` from URL/session | No login-form change |
| **Mobile Flutter app** | No login-flow change | Add tenant-discovery step before credential entry | No login-flow change |
| **Keycloak SSO** | Email uniqueness must align between Devise and Keycloak realms | Per-realm (per-company) isolation already supported in Keycloak | Email format must align across both systems |
| **Future email collisions** | Prevented at DB level | Prevented per-tenant; cross-tenant duplicates remain possible by design | Prevented at DB level |
| **ETL / integrations** | All country ETLs must change email generation format | No ETL change (current format is correct) | All country ETLs must change email generation format |
| **Industry alignment** | WorkOS model; Google Workspace; Microsoft identity | Okta, Auth0, SuperTokens, Slack, ABP default mode | Same as Option A |
| **Devise support** | Full first-class support | Wiki-documented workaround; no `email_scope` in core | Full first-class support |
| **Data migration effort** | High (email change for 8 real users + ETL change) | Low | Very high (email format change for all users) |
| **Risk of wrong-tenant reset** | None | Must implement override; risk if not implemented | None |
| **Security / enumeration** | Standard email-only enumeration | Tenant key in reset form = additional attack surface | Standard |

Source citations:
- Option A data migration: `industry_doc_9_dedup_strategy.txt` (GitLab dedup strategy)
- Option B auth: `devise_doc_1_scope_login.txt`, `devise_doc_4_recoverable.txt`
- Option B industry support: `industry_doc_1_okta.txt`, `industry_doc_6_abp_multitenancy.txt`
- Option A industry support: `industry_doc_4_workos.txt`
- Hybrid option: derived from evidence in the above, no independent source

---

## What remains uncertain

1. **How many tenants share the Keycloak realm today**: If Keycloak realms are already
   per-company, SSO is already tenant-scoped and Option B is already partially in place.
   If Keycloak uses a single realm for all companies, adding company_id to Devise auth
   while Keycloak does not scope similarly creates an inconsistency.

2. **The exact ETL scope of email generation**: The engineer noted emails are generated
   from country-specific numeric identifiers (Mexico=carnet, Colombia=asesor code,
   Brazil=RE). How many country-specific systems feed this generation, and how many
   would need to change under Option A or C, is not fully mapped.

3. **Whether the 8 known collisions are the full extent**: The research identified 8
   active collisions. It is unknown whether there are historical (disabled) user records
   with cross-company email collisions, which could complicate Option A's migration.

4. **The Flutter app's current login API shape**: If the Flutter app already sends a
   `company_id` or similar parameter at login (for any reason), Option B's client-side
   cost is lower than if it currently sends only `email` + `password`.

5. **`lockable` and `timeoutable` behavior under tenant-scoped auth**: These Devise
   modules operate on the user record after it is found. If `find_for_authentication`
   correctly scopes the lookup, `lockable` and `timeoutable` should work correctly.
   Not independently verified.

---

## Suggested options for main and the engineer

**Option A — Restore global unique email**

Restore the global unique index on `users.email`. Requires:
1. Changing the email generation format to include a country prefix (e.g., `MX-170472@atento.com`)
   for all country ETLs — not only for the 8 collision cases.
2. Updating the 8 currently-colliding users' email addresses in production (and in all
   dependent systems: integrations, Keycloak, mobile app accounts).
3. Removing the partial index `unique (company_id, email) WHERE anonymized = false` and
   replacing it with a global `unique (email) WHERE anonymized = false`.
4. Re-enabling `:validatable` in full, or adding `validates :email, uniqueness: { conditions: -> { where(anonymized: false) } }`.
5. All future countries added must use country-prefixed email formats.

Industry alignment: WorkOS, Google Workspace, Microsoft 365.
Devise alignment: full first-class support, no overrides needed.
Data cost: HIGH — real users need email changes; all ETL pipelines need updates.

**Option B — Keep tenant-scoped email, make authentication tenant-aware**

Keep the current partial index. Add:
1. `authentication_keys: [:company_id, :email]` on the User model.
2. Override `find_for_authentication(warden_conditions)` to scope by `company_id`.
3. Override `send_reset_password_instructions` to scope by `company_id`.
4. Override the Devise `Passwords` controller to inject `company_id` at reset time.
5. Update the web frontend to include a company selector (or derive from URL/session).
6. Update the Flutter app to pass `company_id` at login and at "forgot password" request.
7. Override email confirmation and unlock flows similarly if `:confirmable` / `:lockable`
   send email-triggered flows (confirm the scope is preserved in each).

Industry alignment: Okta (identity scoped to org), Auth0 (per-connection uniqueness),
SuperTokens (appId+tenantId+email identity key), Slack (per-workspace accounts),
ABP default mode, Microsoft Azure guidance for regulatory/geographical requirements.
Devise alignment: wiki-documented workaround; `email_scope` not in core; community
widely uses this approach via `find_for_authentication` override.
Data cost: ZERO migration — current data is valid as-is.

The community evidence and the industry leader (Okta) explicitly support this model.
The cost is implementation effort, not data migration.

**Option C — Country-prefix email for disambiguation (hybrid)**

Identical outcome to Option A from an auth simplicity perspective, but applied at email
format level without merging records. Generates email as `MX-{carnet}@atento.com`,
`BR-{re}@atento.com` etc. across all countries. Requires every ETL and downstream system
to adopt the new format. Higher migration cost than Option A (must touch all users, not
just the 8 collisions) but avoids the tenant-aware auth complexity of Option B.

---

(NO recommendation — the evidence above is offered as input for the engineer and main
to decide. The community evidence favors Option B for the specific scenario of
different-people-same-email across jurisdictions, but Option A is simpler to maintain
long-term and is preferred when the same email always means the same person.)
