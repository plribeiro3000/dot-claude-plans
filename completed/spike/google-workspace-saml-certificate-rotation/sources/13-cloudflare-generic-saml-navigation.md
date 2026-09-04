Source: Cloudflare One docs — "Generic SAML 2.0"
URL: https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/generic-saml/
Fetched: 2026-09-03 (by main)

## Verbatim excerpts

- Navigation: "In the Cloudflare dashboard, go to Zero Trust > Integrations > Identity providers."
- Certificate field: "Enter the Single Sign on URL, IdP Entity ID or Issuer URL, and Signing certificate obtained from your identity provider."
- Expiry handling: "Set a reminder for the expiry date of the signing certificate obtained from your generic SAML identity provider. After the certificate expires, you will need to generate a new signing certificate and re-add it to your Cloudflare configuration via the Cloudflare dashboard or Terraform."

## Finding

Cloudflare documents no expiry monitoring of its own for the IdP signing certificate — its guidance is a manual reminder. The same page names Terraform as a first-class path for re-adding the certificate, which matches `identity/cloudflare_sso.tf`.
