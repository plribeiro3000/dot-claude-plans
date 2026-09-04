Source: Google Workspace Help — "Migrating from legacy SSO to SSO profiles"
URL: https://knowledge.workspace.google.com/admin/apps/migrating-from-legacy-sso-to-sso-profiles (canonical redirect target of https://support.google.com/a/answer/15209818)
Fetched: 2026-09-03

## Purpose of this fetch

To settle whether "SSO profiles" / "legacy SSO" (and the Cloud Identity API's `inboundSamlSsoProfiles` resource surfaced by search results) is the SAME feature as the "SSO with SAML applications" Google-as-IdP feature the spike investigates, or a DIFFERENT feature.

## Verbatim excerpts

- Legacy SSO: "Allows you to configure only one IdP for your organization."
- SSO profiles: "The newer, recommended way to set up SSO. Lets you apply different SSO settings to different users in your organization, supports both SAML and OIDC."

## Finding

"Legacy SSO" / "SSO profiles" and `inboundSamlSsoProfiles` (Cloud Identity API) describe Google Workspace acting as the Service Provider — SSO with third-party IdPs authenticating users INTO Google Workspace. This is the opposite direction from the "SSO with SAML applications" feature (Menu > Security > Authentication > SSO with SAML applications), where Google Workspace is the Identity Provider signing assertions FOR third-party SPs (Cloudflare, AWS, MongoDB Atlas). The two features are NOT the same, and the `inboundSamlSsoProfiles` API does not manage the outbound-direction certificate this spike investigates.

The page content available through this fetch did not confirm or deny whether the `accounts.google.com/o/saml2/idp?idpid=...` URL pattern belongs to one feature or the other — that association is drawn independently from the "SSO with SAML applications" documentation (source 03), which uses exactly this URL pattern in its own configuration examples, and from the terraform code (`cloudflare_sso.tf:7-8`) whose `sso_target_url`/`issuer_url` use this same pattern for a resource explicitly typed `type = "saml"` naming Google as the IdP.
