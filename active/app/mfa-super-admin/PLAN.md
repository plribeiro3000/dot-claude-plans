# PLAN — Second authentication factor (TOTP) for 4Shark Super Admin accounts

**Project**: `app` (backend) + `app-webclient` (frontend) · **Driver**: Atento TPRM questionnaire, item 6.5 (MFA on all administrative-access accounts) · **Owner**: Paulo Ribeiro

**Research**: `~/Projects/4Shark/dot-claude-plans/active/spike/mfa-for-4shark-accounts/SPIKE.md` — eleven sourced findings, four options evaluated. This plan implements Option A.

## Problem

Item 6.5 is answered `NO`. It fails on exactly one surface: a 4Shark employee authenticating with e-mail and password against `POST /sessions`, on an account that can create users and reset passwords inside client organizations. Setting another user's password is identity administration — whoever does it can authenticate as that user — so the account is administrative by definition, and it has no second factor.

Two adjacent surfaces are already answered and are **not** in scope. Administrative access to infrastructure (AWS, GitHub, Google Workspace, 1Password) requires MFA at every level. Client end users federate to their own corporate IdP through Keycloak, which respects the client's MFA policies — item 3.8, answered `SÍ`.

## Target shape

`POST /sessions` gains a third outcome. Today it has two: `401` on bad credentials, and `201` with the full session payload on good ones (`app/controllers/sessions_controller.rb`). The third says *the password was accepted and a second factor is required*, and carries no session token.

The frontend branches on those three. On the third it navigates to a new screen and completes the login against a second endpoint, which is the only place a real JWT is issued for an MFA-required account.

### The partial-authentication token, and why it is safe by construction

The third response carries a short-lived token proving the password step passed. It is a `JsonWebToken` like every other, but its claim is **not** `user_id`.

That single choice is what makes it safe everywhere else. `JwtAuthorizedController#user_id` reads `token_payload['user_id']` (`app/controllers/jwt_authorized_controller.rb:52-56`), and `authenticate!` does `User.enabled.find(user_id)` (`:26`). A token whose payload has no `user_id` decodes cleanly, resolves `user_id` to `nil`, and `find(nil)` raises `ActiveRecord::RecordNotFound`, which the same method already rescues into `401`. Every existing endpoint therefore rejects a partial token without a single line being added to any of them, and without a revocation list.

The verification endpoint is the one place that reads the other claim. It exchanges partial token + OTP code for the real `Session.new(user).payload`.

### Why the existing "flag on the payload" pattern must not be copied

The frontend already routes to a special screen after login, twice: `registration_password` sends the user to `/change_password`, and `pending_legal_documents_acceptance` to `/legalDocumentAcceptance` (`app-webclient/src/app/core/authentication/authentication.service.ts:29-63`). Both are fields on the payload of a **successful** login — the JWT is already issued and stored when the redirect happens.

Reusing that shape for the second factor would issue the session token before the factor is verified, which is the whole thing the control exists to prevent. The TOTP case is structurally different from its two siblings and must not follow them.

### Enrollment rides on the same third response

A Super Admin who has never enrolled cannot produce a code. If the requirement flips on and the enrollment screen is not reachable from the login, every Super Admin is locked out at once.

The third response therefore carries a field saying whether the account still needs to enrol. Same status, same partial token, one field deciding which screen the frontend opens: enrollment (QR code plus recovery codes, then a first code to confirm the secret) or verification (code only). This keeps the contract at three responses.

### Scoping to Super Admin

`devise-two-factor` ships a per-user `otp_required_for_login` boolean, and the requirement is read from it at login rather than derived from the seat type on the fly. Deriving it would silently grant or revoke the requirement when someone's seat changes, and would make "this account requires a second factor" unanswerable without recomputing it.

Which accounts get the flag set is a Super Admin question — `SuperAdmin` is an STI subclass of `Seat` (`app/models/super_admin.rb`), and the codebase's existing predicate shape for this is `User.admin`'s `joins(:seat).where('seats.type': 'Admin')` (`app/models/user.rb:208`).

The eventual extension past Super Admin follows the existing per-tenant idiom — a `*_module` boolean on `companies`, the shape `security_events_module` and its siblings already use — but nothing in this change needs that column yet.

## Execution

**Backend.** Add `devise-two-factor` (6.4.0 declares `devise >= 4.0, < 6.0` and `railties >= 7.2, < 8.2`; the repo is on Devise 5.0.4 and Rails ~> 8.1.3). Add the OTP secret, the `otp_required_for_login` flag and the recovery-code column to `users` through the generator, with the secret under `encrypts` — ActiveRecord Encryption is already configured and exercised on four columns across three models (`app/models/authenticator_configuration.rb:21`, `app/models/user.rb:246`, `app/models/payroll_integration.rb:12-14`), so no key set is being stood up.

Add the third branch to `SessionsController#create`, the verification endpoint, and the enrollment endpoints. Extend the `SecurityEvent` catalog: `TYPES` and `SEVERITY_BY_TYPE` are frozen and the model `fetch`es the severity, so a new type without a severity fails loudly — both get the same keys. `AUTH_METHODS` and `FAILURE_REASONS` need entries too, for a TOTP-verified login and for a wrong code.

**Frontend.** Branch on the three responses, hold the partial token between the two calls, and add the two screens the third response selects between. The existing navigation logic that runs after a successful login (`registration_password`, `pending_legal_documents_acceptance`, `redirectTo`, permission-based landing) moves behind the second call unchanged — it must still run when the session finally arrives.

## Deploy

Backend first, frontend after, and the order is not a coincidence: shipping the backend alone makes MFA-required accounts unable to finish logging in, because no screen exists to send the code. Nobody is locked out while the flag is off, so the sequence is backend deploy → frontend deploy → flip the flag for Super Admins.

Existing sessions need no handling. JWTs are stateless and self-expiring with no revocation list (`app/models/json_web_token.rb`), so a token issued before the change keeps working until its own expiry — the rollout needs no forced logout and no maintenance window.

## Decisions taken

**The partial token carries a claim other than `user_id`.** This is what makes every existing endpoint reject it with no change to any of them, per the mechanism above. The alternative — a claim named `user_id` plus a flag the endpoints check — would require every authenticated path to be audited for the check, and a missed one is a full session.

**The third response is a distinct status carrying no session token, not a `201` with a flag.** Its two siblings in the payload are flags precisely because the session is already legitimate at that point; here it is not.

**Enrollment and verification share one response, separated by a field.** Two distinct statuses would also work; one response keeps the contract at three and puts the branch where the frontend already branches.

**The requirement is a per-user flag, not derived from seat type at login.** Derivation changes the requirement as a side effect of an unrelated seat change.

## Open decisions

**How the flag gets turned on for the first cohort.** Forcing enrollment at next login needs no coordination and locks nobody out, but the first login after the flip is a surprise. Pre-enrolling with people at their desks is calmer and slower. This changes an operational sequence for real people, not the code.

**Who can reset a lost device.** The recovery codes cover the user who kept them; the account that lost both device and codes needs a human path. Whoever holds it can turn MFA off for another account, so it is itself an administrative capability and should be a separate permission key rather than falling to whoever can already edit users — the same reasoning that gave password reset its own key.

**Whether the Devise web path is in scope.** `devise_for :users` still exists alongside the bespoke controller (`config/routes.rb:96`), and `SECURITY_EVENTS.md:31` documents it as gating the Rails root page only, not the JWT product. If it reaches anything an administrator uses, it needs its own decision.

## Starting the implementation

This plan is the input to a fresh session, which loads `coding-policies` and `ruby-coding-policies` before writing anything (§ Policy Priming). The decisions above are settled — the implementing session does not reopen them.

Read before writing: `app/controllers/sessions_controller.rb` (the file being changed), `app/controllers/jwt_authorized_controller.rb` (the claim mechanism the partial token relies on), `app/models/session.rb` (the payload being withheld), `app/models/security_event.rb` (the frozen catalogs), `app/models/user.rb:12-13` (the Devise module list) and, on the frontend, `app-webclient/src/app/core/authentication/authentication.service.ts` and `src/app/login/login.component.ts`.
