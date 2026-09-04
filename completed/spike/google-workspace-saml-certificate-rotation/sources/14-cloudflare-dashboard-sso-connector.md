Source: Cloudflare One docs — "Cloudflare Dashboard SSO"
URL: https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/dash-sso-apps/
Fetched: 2026-09-03 (by main)

## Verbatim excerpts

- Prerequisites: "You must control your email domain and be able to add a TXT record to verify this."; "You must be a super administrator and be able to access the Cloudflare API."; "A Cloudflare Zero Trust organization with any subscription tier (including Free) must be created."
- Connector navigation: "Once you have configured an IdP in Cloudflare One, go to the **Members** page to manage SSO connectors."
- Backup token: "You must create an [Account API token] with the role `SSO Connector Edit` and store it securely. This acts as a backup plan, allowing you to disable SSO via the API if you are accidentally locked out"
- "Before disabling SSO, make sure you have access to your Cloudflare user email."

## Finding

The Dashboard SSO connector (Members page) sits on top of the Zero Trust identity provider object — the certificate lives on the identity provider (`Zero Trust > Integrations > Identity providers`, terraform-managed in `identity/cloudflare_sso.tf`), not on the connector. Cloudflare's own lockout recovery is the `SSO Connector Edit` API token, the same backup `identity/README.md:220-228` documents.
