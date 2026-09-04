Source: AWS IAM Identity Center User Guide — "Rotate SAML 2.0 certificates" and "Rotate a SAML 2.0 certificate"
URLs:
- https://docs.aws.amazon.com/singlesignon/latest/userguide/managesamlcerts.html
- https://docs.aws.amazon.com/singlesignon/latest/userguide/rotatesamlcert.html
Fetched: 2026-09-03

## Verbatim excerpts

- "When you add an external IdP in IAM Identity Center, you must also obtain at least one public SAML 2.0 X.509 certificate from the external IdP. That certificate is usually installed automatically during the IdP SAML metadata exchange during trust creation."
- "All imported certificates are automatically active."
- "You should also consider that some IdPs might not support multiple certificates. In this case, the act of rotating certificates with these IdPs might mean a temporary service disruption for your users."
- "There must always be at least one valid certificate listed, and it cannot be removed."
- Console navigation for import: "In the IAM Identity Center console, choose Settings. On the Settings page, choose the Identity source tab, and then choose Actions > Manage authentication. On the Manage SAML 2.0 certificates page, choose Import certificate."
- Full four-step rotation process quoted verbatim:
  1. "Obtaining a new certificate from the IdP"
  2. "Importing the new certificate into IAM Identity Center" — "At this point, IAM Identity Center will trust all incoming SAML messages signed from both of the certificates that you have imported."
  3. "Activating the new certificate in the IdP"
  4. "Deleting the older certificate"

## Finding

This procedure applies ONLY if the AWS side is configured as IAM Identity Center with an external SAML IdP (Settings > Identity source > Actions > Manage authentication). AWS supports multiple simultaneously active certificates for exactly this zero-downtime rotation shape. This is contingent on the AWS identity source actually being external-IdP-configured — see the local-code finding in SPIKE.md regarding `identity/README.md:246-247`, which states the current terraform-managed identity source is the Identity Center directory itself, not an external IdP.
