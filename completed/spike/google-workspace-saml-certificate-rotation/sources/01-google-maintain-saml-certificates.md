Source: Google Workspace Help — "Maintain SAML certificates"
URL: https://knowledge.workspace.google.com/admin/apps/maintain-saml-certificates?hl=en (canonical redirect target of https://support.google.com/a/answer/7394709?hl=en)
Fetched: 2026-09-03 (fetched twice, independently, for self-check — both fetches returned the same quoted substrings)
Scope: Google-as-IdP — the "SSO with SAML applications" feature (Menu > Security > Authentication > SSO with SAML applications), where Google Workspace signs SAML assertions for third-party Service Providers such as Cloudflare, AWS, and MongoDB Atlas.

## Verbatim excerpts (returned in quotation marks by both independent fetches)

- "You can have up to 2 certificates at one time."
- "X.509 certificates have a five-year lifetime."
- "If you have only one certificate, click **Add another certificate** to create a second certificate."
- "Click **Delete certificate**. Deleting a certificate has these results: If you have one certificate, a new certificate is automatically generated to replace it."
- "The most recently generated (newest) certificate becomes the default certificate used to set up SSO for new SAML apps"
- "After assigning a new certificate to a SAML app in Admin console, you also need to update the corresponding SP side SSO configuration with the new certificate, or SSO with the app will fail."
- "If a certificate expires before you rotate it, your users won't be able to use SSO to sign in to any SAML applications that use that certificate until you replace it with a new certificate."

## Notes on what the page does NOT state

- No mention of an email/automatic notification before certificate expiry.
- No mention of a way to upload a customer-generated (non-Google-issued) certificate to a "SSO with SAML applications" profile.
- No mention of an Admin SDK / API path for this feature — the described workflow is entirely Admin-console based.
