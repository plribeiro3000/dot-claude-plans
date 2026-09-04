Source: AWS IAM User Guide — "Create a SAML identity provider in IAM"
URL: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_saml.html
Fetched: 2026-09-03 (direct raw fetch, full page)

## Verbatim excerpts

- "Get the SAML metadata document from your IdP. This document includes the issuer's name, expiration information, and keys that can be used to validate the SAML authentication response (assertions) that are received from the IdP."
- "The **Valid until** date displayed for the identity provider is set by IAM at provider creation time. It does not reflect the `validUntil` or `cacheDuration` attributes in your SAML metadata document. IAM does not use these metadata attributes to determine the **Valid until** date."
- "IAM does not evaluate or take action on the expiration of the SAML metadata document or X.509 certificates in SAML metadata documents during SAML authentication. SAML authentication validity is enforced at the assertion level, using the `NotOnOrAfter` attribute in the assertion's `Conditions` and `SubjectConfirmationData` elements. If you are concerned about expired X.509 certificates, we recommend monitoring certificate expiration dates and rotating certificates according to your organization's governance and security policies."
- CLI update path: "You can update the metadata file, SAML encryption settings, and rotate private key decryption files for your IAM SAML provider." — "Run this command: `aws iam update-saml-provider`"
- Private key (encryption) rotation, a SEPARATE mechanism from the metadata document's own embedded certificate: "You can save up to two private key files for each identity provider, allowing you to rotate private keys as necessary. When two files are saved, each request will first attempt to decrypt with the newest **Added on** date, then IAM attempts to decrypt the request with the oldest **Added on** date."

## Finding

An `aws_iam_saml_provider`-shaped resource (IAM > Identity providers, distinct from IAM Identity Center) is updated by replacing the WHOLE metadata document in one `update-saml-provider` call — there is no separate multi-certificate import/activate/delete dance the way IAM Identity Center's external-IdP flow has. The page does not state whether the metadata document itself may carry more than one `<KeyDescriptor>` (multiple certificates) for an overlap window during rotation, and no such statement was found in any fetched AWS page — this is UNVERIFIED and left as an open question rather than asserted either way.

IAM explicitly does NOT evaluate certificate/metadata expiration itself — there is no built-in expiry alert for this mechanism; monitoring is the administrator's own responsibility, per AWS's own recommendation quoted above.
