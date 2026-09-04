# SPIKE — Google Workspace SAML IdP Certificate Rotation

## Investigation question

4Shark uses Google Workspace as the SAML Identity Provider (IdP) for three Service Providers (SPs): Cloudflare, MongoDB Atlas, and AWS. The Google-issued IdP signing certificate embedded in `identity/cloudflare_sso.tf:10` expires 2026-09-20 13:07:43 UTC. The investigation answers five questions:

1. Can the rotation be automated end to end, on the IdP side and on each SP side?
2. If not fully automatable, what control guarantees the expiry is never missed and access is never lost?
3. What is the maximum certificate validity Google actually issues, and is 5 years already the ceiling?
4. Where, exactly, does an engineer go in each console to read the current certificate state?
5. What is the correct rotation order and overlap window per SP, and which SPs support two simultaneously valid certificates?

## Sources consulted

- `identity/cloudflare_sso.tf:1-12` — Cloudflare `cloudflare_zero_trust_access_identity_provider` resource, `idp_public_certs` list, decoded certificate validity (openssl)
- `identity/mongodb_federation.tf:1-23` — MongoDB Atlas `mongodbatlas_federated_settings_identity_provider` and `mongodbatlas_federated_settings_org_config` resources
- `identity/sso.tf:1-141` — AWS IAM Identity Center resources (permission sets, identity store users/groups, account assignments); no `aws_iam_saml_provider`-shaped or external-IdP resource present
- `identity/README.md:145-247` — Platforms Managed table, Cloudflare Dashboard SSO section, break glass fallback per platform, Engineer Identity Model (AWS identity source statement)
- `identity/.terraform.lock.hcl:100-107` — `mongodbatlas` provider pinned at 2.16.0
- `identity/policy_arbiter_policies.tf:30-53` — `sso:*`/`iam:*` reads gated to the policy-arbiter identity, explaining why `aws iam list-saml-providers` / `aws sso-admin list-instances` returned AccessDenied on the engineer profile
- See auxiliary `sources/01-google-maintain-saml-certificates.md` — Google's certificate count limit, 5-year lifetime, rotation steps
- See auxiliary `sources/02-google-optional-sso-settings-maintenance.md` — Google's two-certificate overlap window, 24-hour propagation
- See auxiliary `sources/03-google-set-up-custom-saml-app.md` — Google Admin console navigation, no public metadata URL, no API
- See auxiliary `sources/04-google-legacy-sso-vs-sso-profiles.md` — disambiguates Google-as-IdP (this spike) from Google-as-SP (`inboundSamlSsoProfiles`, unrelated)
- See auxiliary `sources/05-cloudflare-terraform-idp-public-certs.md` — `idp_public_certs` schema type (`List[String]`)
- See auxiliary `sources/06-cloudflare-signed-authn-requests.md` — Cloudflare's own automatic key rotation is a different certificate, not `idp_public_certs`
- See auxiliary `sources/07-mongodbatlas-terraform-resource-doc.md` — full Argument Reference of `mongodbatlas_federated_settings_identity_provider`, no certificate field
- See auxiliary `sources/08-mongodbatlas-admin-api-update-identity-provider.md` — Atlas Admin API PATCH endpoint, `pemFileInfo.certificates[]`
- See auxiliary `sources/09-mongodbatlas-manage-federated-auth.md` — Atlas console certificate upload field
- See auxiliary `sources/10-aws-identity-center-rotate-saml-cert.md` — AWS IAM Identity Center external-IdP multi-certificate rotation procedure
- See auxiliary `sources/11-aws-iam-create-saml-provider.md` — AWS IAM SAML provider (`aws_iam_saml_provider`-shaped), whole-metadata-document update, no built-in expiry evaluation
- See auxiliary `sources/12-google-maintain-saml-certificates-navigation.md` — Admin console navigation to the Certificates section, per-app certificate dropdown, which apps use a certificate
- See auxiliary `sources/13-cloudflare-generic-saml-navigation.md` — Zero Trust dashboard navigation to the SAML identity provider, "Set a reminder for the expiry date"
- See auxiliary `sources/14-cloudflare-dashboard-sso-connector.md` — Dashboard SSO connector on the Members page, `SSO Connector Edit` backup token

## Findings

### Finding 1: The Google IdP certificate has a fixed 5-year lifetime — the 1-year premise does not hold

**Evidence:** Decoding the certificate embedded in `identity/cloudflare_sso.tf:10` with openssl gives `notBefore=Sep 21 13:07:43 2021 GMT`, `notAfter=Sep 20 13:07:43 2026 GMT`, `subject=O=Google Inc., OU=Google For Work, CN=Google` (self-signed) — a five-year span. Independently, Google's own documentation states: *"X.509 certificates have a five-year lifetime."* (`sources/01`)

**Source:** `identity/cloudflare_sso.tf:10` (local decode) + `sources/01-google-maintain-saml-certificates.md`

**Significance:** Google does not offer a 1-year certificate to shorten and does not appear to offer a way to lengthen it either — no source found states the lifetime is configurable in either direction. If the engineer's premise was "we only get 1 year and want 2 or 5", the evidence shows the currently-issued certificate already sits at what Google documents as its standard, non-configurable, lifetime. Whether a longer-than-5-year certificate can be requested is addressed in Finding 2 as a genuine gap — no source states it either way.

### Finding 2: No source states whether Google offers anything longer than 5 years, or whether a customer-generated certificate can be substituted

**Evidence:** `sources/01` and `sources/03` describe certificate creation exclusively as a Google-generated action inside the Admin console (*"click Add another certificate to create a second certificate"*, *"Deleting a certificate has these results: If you have one certificate, a new certificate is automatically generated to replace it"*) — every certificate-creation action described is Google minting a new certificate, never an upload of one supplied by the customer.

**Source:** `sources/01-google-maintain-saml-certificates.md`, `sources/03-google-set-up-custom-saml-app.md`

**Significance:** Not found: any statement that a customer can upload their own X.509 certificate to a "SSO with SAML applications" profile, or that Google offers a certificate lifetime other than 5 years. This spike surfaces the absence rather than asserting a negative from silence — the honest answer to "can we get 2 or 5 years" is "5 years is what Google issues by default and no configuration path to a different value was found in the documentation consulted."

### Finding 3: The IdP side of rotation is console-only for the outbound "SSO with SAML applications" feature — no Admin SDK/API path exists for it

**Evidence:** *"In the Google Admin console, go to Menu and then Apps and then Web and mobile apps"* is the only creation/rotation path documented; the only API pointer on the setup page is to the Admin SDK for user-schema attributes, unrelated to SAML app or certificate management (`sources/03`). Separately, the Cloud Identity API's `inboundSamlSsoProfiles` resource — the one API surface with genuine SAML provider CRUD — governs a DIFFERENT feature: Google acting as Service Provider for third-party IdPs authenticating INTO Workspace ("legacy SSO" / "SSO profiles"), not Google acting as IdP for outbound SPs like Cloudflare, AWS, and MongoDB Atlas (`sources/04`).

**Source:** `sources/03-google-set-up-custom-saml-app.md`, `sources/04-google-legacy-sso-vs-sso-profiles.md`

**Significance:** The IdP half of the rotation cannot be scripted or automated by 4Shark — a human must go into the Admin console, generate the second certificate, and download it, every time. This is the fixed manual step regardless of what is automated on the SP side.

### Finding 4: Google supports a two-certificate overlap window; the rotation is not a hard cutover on the IdP side

**Evidence:** *"You can have up to 2 certificates at one time"* and *"If you upload two certificates to a SAML Single Sign-On (SSO) profile, Google can use either certificate to validate a SAML response from your IdP"* — though this second quote's wording (Google *validating* rather than *signing*) suggests the maintenance-and-rotation guide's language is shared across Google's inbound and outbound SAML documentation; read together with Finding 3's disambiguation, the operative fact for our outbound case is the "up to 2 certificates" ceiling and the two-certificate window it enables during rotation.

**Source:** `sources/01-google-maintain-saml-certificates.md`, `sources/02-google-optional-sso-settings-maintenance.md`

**Significance:** A new certificate can be created and assigned to the Cloudflare/AWS/MongoDB Atlas SAML app while the old one is still valid, then the old one deleted once every SP has the new one. Google recommends starting this *"at least 24 hours before a certificate is due to expire"* (`sources/02`) — for the 2026-09-20 13:07:43 UTC expiry, that is a floor, not a target; more lead time is safer given three SPs must each independently be updated.

### Finding 5: Cloudflare's `idp_public_certs` accepts multiple certificates — the SP side is terraform-automatable for Cloudflare

**Evidence:** `idp_public_certs: List[String]` (`sources/05`) — the terraform argument at `identity/cloudflare_sso.tf:10` is a list. Cloudflare's own documented automatic certificate rotation (*"Cloudflare Access routinely rotates the public key as a security measure"*) is a separate certificate entirely — Cloudflare's own outbound-AuthnRequest signing key, not the Google-issued verification certificate in `idp_public_certs` (`sources/06`).

**Source:** `sources/05-cloudflare-terraform-idp-public-certs.md`, `sources/06-cloudflare-signed-authn-requests.md`

**Significance:** Adding the new Google certificate to `idp_public_certs` as a second list entry, applying via terraform (a PR against the `identity` stack per `identity/README.md:41-51` — apply-only by the policy-arbiter account), then removing the old entry once Google's app is switched over, is a fully code-reviewable, terraform-native path for the Cloudflare side. Cloudflare's own automatic rotation feature provides zero protection here — it rotates a different key.

### Finding 6: MongoDB Atlas's certificate is NOT managed by terraform at all — by construction of the resource schema

**Evidence:** The full Argument Reference of `mongodbatlas_federated_settings_identity_provider` (`sources/07`) lists `federation_settings_id`, `name`, `description`, `authorization_type`, `associated_domains`, `sso_debug_enabled`, `status`, `issuer_uri`, `sso_url`, `request_binding`, `response_signature_algorithm`, `protocol`, and the OIDC-only fields `audience`/`client_id`/`groups_claim`/`requested_scopes`/`user_claim`. No field in this list concerns the certificate. This matches what is actually declared in `identity/mongodb_federation.tf:5-16` — the same absence, now confirmed as a schema-level fact rather than an omission in this one file.

**Source:** `sources/07-mongodbatlas-terraform-resource-doc.md` cross-referenced against `identity/mongodb_federation.tf:5-16`

**Significance:** Even a hypothetical future edit to `mongodb_federation.tf` could not add a certificate argument — the terraform provider's schema has none. Whatever process updates the Google certificate on the MongoDB Atlas side happens entirely outside the `identity` terraform stack.

### Finding 7: MongoDB Atlas's Admin API supports a SAML certificate update, outside terraform, requiring an Organization Owner-scoped credential

**Evidence:** `PATCH /api/atlas/v2/federationSettings/{federationSettingsId}/identityProviders/{identityProviderId}` *"supports both SAML and OIDC identity providers"* and accepts `pemFileInfo.certificates[]` — an array, meaning more than one certificate object can be supplied in a single request. The call *"requires the requesting Service Account or API Key to have the Organization Owner role in one of the connected organizations"* (`sources/08`). The console exposes the same value manually: *"Upload the certificate from your computer, or Paste the contents of the certificate into a text box"* (`sources/09`).

**Source:** `sources/08-mongodbatlas-admin-api-update-identity-provider.md`, `sources/09-mongodbatlas-manage-federated-auth.md`

**Significance:** The Atlas side of the rotation is scriptable via the Admin API — but is not currently automated by anything in the `identity` stack, and doing so would need a 4Shark-held Service Account or API key carrying Organization Owner on the connected Atlas organization, a credential whose existence and location this spike did not investigate (out of scope for a read-only spike; a genuine follow-up question).

### Finding 8: AWS's rotation path depends entirely on which of two distinct AWS mechanisms is actually configured, and the current terraform state says neither is external-IdP-backed

**Evidence:** `identity/README.md:245-247` states, for the IAM Identity Center console-login identity: *"The identity source is the Identity Center directory itself — no external identity provider is configured, so the person signs in with a password held by that directory rather than with their Google account."* `identity/sso.tf` (read in full) declares only `aws_ssoadmin_permission_set`, `aws_identitystore_user`, `aws_identitystore_group`, `aws_identitystore_group_membership`, and `aws_ssoadmin_account_assignment` resources — no `aws_iam_saml_provider` and no Identity Center external-IdP configuration resource anywhere in the `identity` stack.

**Source:** `identity/README.md:245-247` + `identity/sso.tf:1-141` (full read)

**Significance:** As documented and as terraform-managed, AWS Identity Center login is NOT federated through Google SAML — which conflicts with the premise that AWS is one of the three SPs whose Google-issued certificate expires 2026-09-20. Reading `aws iam list-saml-providers` or `aws sso-admin list-instances` requires the `policy-arbiter-elevated` profile (`identity/policy_arbiter_policies.tf:36-53` scopes `iam:*`/`sso:*` reads to that identity only) — both calls return `AccessDenied` on the default engineer profile.

**Resolution (policy-arbiter session, 2026-09-03):** mechanism (b) is the one in use. `aws iam list-saml-providers` returns a single provider, `AWSSSO_ddde7fecc0d50ba5_DO_NOT_DELETE` (the provider Identity Center creates for itself, created 2023-03-31) — no Google-issued IAM SAML provider exists, so mechanism (a) is ruled out. `aws sso-admin list-instances` returns instance `ssoins-7223dc329b8e9333`, identity store `d-906791aeb2`, primary region `us-east-1`. An unauthenticated request to the access portal `https://d-906791aeb2.awsapps.com/start` lands on `https://accounts.google.com` ("Sign in — Use your Google Account"), which only happens when the Identity Center identity source is an external SAML IdP. `identity/README.md:245-247` therefore describes a state that no longer holds and needs correcting; the identity-store users (`ivo@`, `paulo@`) carry no `ExternalIds`, so provisioning is manual (terraform), not SCIM. The rotation path is Finding 9's Identity Center four-step procedure (`sources/10`), which supports two simultaneously active certificates.

### Finding 9: If AWS Identity Center IS the mechanism, AWS supports genuine zero-downtime multi-certificate rotation; if it is an IAM SAML provider, the update replaces the whole metadata document at once

**Evidence:** For IAM Identity Center's external-IdP path: *"All imported certificates are automatically active"* and *"IAM Identity Center will trust all incoming SAML messages signed from both of the certificates that you have imported"* once a second is imported (`sources/10`) — a documented four-step procedure (obtain → import → activate on IdP → delete old). For an IAM SAML provider (`aws_iam_saml_provider`-shaped, `AssumeRoleWithSAML`): *"You can update the metadata file, SAML encryption settings, and rotate private key decryption files for your IAM SAML provider"* via a single `update-saml-provider` call that replaces the metadata document wholesale (`sources/11`) — no source found confirms or denies whether that metadata document may carry more than one certificate for an overlap window.

**Source:** `sources/10-aws-identity-center-rotate-saml-cert.md`, `sources/11-aws-iam-create-saml-provider.md`

**Significance:** The rotation procedure for AWS cannot be finalized without first resolving Finding 8 (which mechanism is actually in play). IAM itself performs no expiry evaluation of its own — *"IAM does not evaluate or take action on the expiration of the SAML metadata document or X.509 certificates in SAML metadata documents during SAML authentication"* (`sources/11`) — so whichever mechanism is in use, there is no AWS-side automatic warning.

### Finding 10: Break-glass fallback exists per platform, already documented, and is the recovery path if a certificate expires before rotation completes

**Evidence:** `identity/README.md:210-217`: *"AWS: IAM Identity Center supports direct login fallback"*, *"MongoDB Atlas: Separate authentication path available"*, *"Cloudflare: Requires a backup API token"* — with the Cloudflare procedure spelled out at `identity/README.md:220-228`: *"Use the backup API token with SSO Connector Edit permission to deactivate the SSO connector"*, then log in directly, then *"Re-enable the SSO connector after the incident is resolved."* `identity/README.md:227`: *"This backup API token must be created before activating the SSO connector."*

**Source:** `identity/README.md:198-237` (full section read)

**Significance:** This is the existing recovery mechanism, not a new one this spike proposes — it already exists and is documented per-platform. It answers half of Question 2 (what happens if the deadline is missed): the break-glass account can still authenticate on every platform even with SSO down, so a missed rotation is a service-degradation incident for `@4shark.com.br`-domain SSO users, not an access-lockout incident for administrators.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Manual Admin-console rotation, no automation | Matches every platform's documented default path; needs no new credential or script | Repeated exactly the same way every ~5 years; nothing prevents the human step being forgotten | `sources/01`, `sources/03` |
| Terraform-managed rotation on the Cloudflare side only (the SP side terraform already touches) | `idp_public_certs` is already a `List[String]` in code today — a PR adds the new cert, another PR removes the old one; fully reviewed and applied under existing `identity` stack governance | Covers only one of three SPs; MongoDB Atlas and AWS remain manual or need separate automation | `identity/cloudflare_sso.tf:10`, `sources/05` |
| Script the MongoDB Atlas side via the Admin API's PATCH `pemFileInfo` | Confirmed to accept a SAML certificate update without going through the console | Needs an Organization-Owner-scoped Service Account/API key whose existence/location was not investigated by this spike; still bypasses terraform, so the value is not tracked as code | `sources/08` |
| An expiry-monitoring check reading the certificate's `notAfter` | Would catch the human forgetting, ahead of the 24-hour-minimum window Google itself recommends | No public Google metadata URL exists to fetch the IdP-side certificate's expiry automatically (`sources/03`) — the source of truth for "when does the CURRENTLY ACTIVE Google certificate expire" is the Admin console, or the certificate 4Shark already has embedded in `cloudflare_sso.tf`, which only tells you about the Cloudflare-side copy, not whether Google has already rotated | `sources/03` |
| Rely solely on the platform break-glass fallback as the safety net | Already built, already documented, needs nothing new | Is a recovery for AFTER the deadline is missed, not a way to avoid missing it; Cloudflare's fallback specifically requires a backup token created in advance (`identity/README.md:227`) — its own precondition can also be forgotten | `identity/README.md:198-237` |

## What remains uncertain

- Whether the Identity Center external-IdP configuration can be read or managed through any API — no `sso-admin` operation for the identity source or its certificates was found; the console path in `sources/10` is the only documented one, so the AWS side of the rotation is console-only even though the mechanism is settled (Finding 8, Resolution).
- Whether Google offers any certificate validity longer than 5 years, or accepts a customer-generated certificate for a "SSO with SAML applications" profile — not found in any source consulted.
- Whether an IAM SAML provider's metadata document (as opposed to IAM Identity Center's separate certificate-import UI) can carry more than one `<KeyDescriptor>`/certificate for an overlap window during `update-saml-provider` — not found in any AWS source consulted.
- Whether Google sends any automatic notification (email or otherwise) before a "SSO with SAML applications" certificate expires — not found in any source consulted; every source describes the administrator manually checking the Admin console's Certificates section to see which ones are close to expiring.
- Where a 4Shark-held MongoDB Atlas Service Account/API key with Organization Owner role would live, if the PATCH-based automation in Finding 7 were pursued — out of scope for this spike's read-only research.

## Suggested options for main and the engineer

- **Option A — Manual rotation on all three platforms, following each vendor's documented console procedure, started well ahead of the 24-hour Google minimum.** No new code, no new credential. Requires a human to touch three consoles once every ~5 years and to first resolve which AWS mechanism (Finding 8) is actually in play.
- **Option B — Terraform-automate the Cloudflare side (`idp_public_certs` is already list-shaped and already terraform-managed); handle MongoDB Atlas and AWS manually via their consoles.** Reduces the manual surface by one of three platforms using code that already exists in this stack.
- **Option C — Script the MongoDB Atlas side too, via the Admin API's `pemFileInfo` PATCH, once the Organization-Owner-scoped credential question is resolved.** Extends automation to two of three platforms; the certificate value would live outside terraform state either way, since the resource schema has no field for it (Finding 6).
- **Option D — Build an expiry-monitoring check against the certificate 4Shark already has embedded in `cloudflare_sso.tf`, since no public Google endpoint exists to check Google's own copy directly.** Addresses "never missed" independently of which rotation approach (A/B/C) is chosen, but the check can only ever be a lower bound — it can flag when 4Shark's Cloudflare-side copy is nearing expiry, not whether Google has already generated a replacement Google is not yet using.
- **Option E — Rely on the documented break-glass fallback as the sole safety net, with no proactive monitoring.** Already exists, needs nothing new; accepts that a missed rotation is a service-degradation window for SSO users rather than a lockout, per Finding 10.

No recommendation is made among these — the evidence above is what main and the engineer weigh against 4Shark's own risk tolerance for a ~5-year-cadence, easy-to-forget maintenance task.

## Console navigation — where the current state is read

| Platform | Path | What it shows | Source |
|----------|------|---------------|--------|
| Google Workspace (IdP) | *"In the Google Admin console, go to Menu > Security > Authentication > SSO with SAML applications."* → **Certificates** section | *"The certificate name, expiration date, contents, and SHA-256 fingerprint are shown."* Create the second one with **Add another certificate** (2 max). Which apps use a certificate is listed only in the delete confirmation window (*"a window lists the affected apps"* — cancel after reading). Per-app switch: *"Click the Down arrow and choose a certificate."* | `sources/12` |
| Cloudflare (identity provider) | *"In the Cloudflare dashboard, go to Zero Trust > Integrations > Identity providers."* → "Google Workspace" | Field **Signing certificate**; terraform-managed in `identity/cloudflare_sso.tf:10`, so the value must match the list there | `sources/13` |
| Cloudflare (dashboard SSO connector) | *"go to the Members page to manage SSO connectors"* (Manage Account → Members → Settings → `@4shark.com.br`, `identity/README.md:233`) | The connector only points at the identity provider above; the certificate is not on it. Backup token with `SSO Connector Edit` must exist first | `sources/14`, `identity/README.md:220-228` |
| MongoDB Atlas | Organization → sidebar **Identity & Access** → **Federation** → *"Click Open Federation Management App."* → Identity Providers screen → "Google Workspace" (`federation_settings_id` in `identity/mongodb_federation.tf:2`) | Field **IdP Signature Certificate** (*"PEM‐encoded public key certificate of the IdP"*); replaced by upload or paste, or by the Admin API PATCH `pemFileInfo` | `sources/09`, `sources/08` |
| AWS — mechanism (a) | IAM → Identity providers | A SAML provider whose issuer is the Google `idpid` URL. The displayed **Valid until** *"is set by IAM at provider creation time"* and does not reflect the certificate | `sources/11` |
| AWS — mechanism (b) | IAM Identity Center → Settings → Identity source → *"Actions > Manage authentication"* → **Manage SAML 2.0 certificates** | Lists imported certificates; *"All imported certificates are automatically active."* | `sources/10` |

Both AWS reads (`iam:ListSAMLProviders`, `sso:ListInstances`) are granted only to the policy-arbiter identity (`identity/policy_arbiter_policies.tf:42`); the engineer profile receives `AccessDenied`.

## Zero-downtime rotation order (derived from Findings 4, 5, 6, 7, 9)

1. Confirm which AWS mechanism exists (Finding 8) and that the Cloudflare `SSO Connector Edit` backup token exists in 1Password (Finding 10).
2. Google: create the second certificate and download its PEM. Do not switch any app yet.
3. SPs that accept two certificates — add the new one alongside the old: Cloudflare (PR on the `identity` stack, `idp_public_certs` with two entries, applied by the policy-arbiter) and AWS if it is Identity Center (Import certificate).
4. SP whose overlap is unconfirmed — MongoDB Atlas (and AWS if it is an IAM SAML provider): replace and test the login immediately.
5. Google: switch each of the three SAML apps to the new certificate; test the login on all three.
6. Cleanup: remove the old certificate from Cloudflare (second PR) and from Identity Center; delete the old certificate on Google last (its confirmation window must list no apps).
7. Record the next expiry (~2031-09) with months of lead time, and the expiry monitor if adopted.

---

> **Authoring:** written by `@agent-spike` on 2026-09-03 from the sources listed above; the console-navigation table and the rotation order were added by the main session from `sources/12`–`14`. Verified by `@agent-output-verifier` (ACCEPT_WITH_WARNINGS — per-Finding verification blocks absent; every citation re-checked, 3 of 11 URLs re-fetched live) and `@agent-policy-verifier` (ACCEPT_WITH_WARNINGS — same citation-block shape note; no Tier 1 or Tier 2 violation).
