Source: Cloudflare API docs — Terraform resource schema for zero_trust identity_providers
URL: https://developers.cloudflare.com/api/terraform/resources/zero_trust/subresources/identity_providers/
Fetched: 2026-09-03

## Verbatim excerpt

"idp_public_certs: List[String] — X509 certificate to verify the signature in the SAML authentication response"

## Finding

The `config.idp_public_certs` argument used in `identity/cloudflare_sso.tf:10` (`cloudflare_zero_trust_access_identity_provider`) is typed as a list of strings, not a single string. This means the terraform resource can carry more than one certificate simultaneously — the mechanism by which Cloudflare would trust a SAML response signed by either an old or a new Google certificate during an overlap window.
