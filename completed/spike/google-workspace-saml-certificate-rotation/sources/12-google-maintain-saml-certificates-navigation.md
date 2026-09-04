Source: Google Workspace Help — "Maintain SAML certificates" (second fetch, navigation and certificate-assignment steps)
URL: https://knowledge.workspace.google.com/admin/apps/maintain-saml-certificates?hl=en
Fetched: 2026-09-03 (by main, complementing sources/01)

## Verbatim excerpts

- Navigation: "In the Google Admin console, go to Menu > Security > Authentication > SSO with SAML applications."
- Certificates section: "The **Certificates** section shows your current X.509 certificates...The certificate name, expiration date, contents, and SHA-256 fingerprint are shown."
- Create a second certificate: "If you have only one certificate, click **Add another certificate** to create a second certificate."
- Assign a certificate to a SAML app: "Click the Down arrow and choose a certificate."
- Which apps use a certificate: "If the certificate you're deleting is used by any installed SAML apps, a window lists the affected apps."

## Finding

The Certificates section under Security > Authentication > SSO with SAML applications is where the expiry date of each Google-issued IdP certificate is read, where the second certificate is created, and where each SAML app is pointed at a certificate through a per-app dropdown. The only documented way to list which apps use a given certificate is the confirmation window shown on delete.
