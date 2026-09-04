Source: Cloudflare One docs — "Signed AuthN requests (SAML)"
URL: https://developers.cloudflare.com/cloudflare-one/identity/idp-integration/signed_authn/
Fetched: 2026-09-03

## Verbatim excerpts

- "Cloudflare Access routinely rotates the public key as a security measure."
- "Ensure that your IdP validation uses the most recent certificate."

## Finding — scope disambiguation

This page describes Cloudflare's OWN signing key pair, used when Cloudflare Access itself signs outbound SAML AuthnRequests sent TO an external IdP, so that the IdP can validate the request came from Cloudflare. This is a DIFFERENT certificate from `config.idp_public_certs` (source 05), which is the certificate Cloudflare uses to validate INCOMING SAML responses signed BY the external IdP (here, Google). Cloudflare's automatic rotation of its own signing key does not touch, and provides no protection for, the Google-issued certificate stored in `idp_public_certs` — that certificate's expiry is 4Shark's own concern, entirely outside Cloudflare's automatic-rotation feature.

No statement about multiple-certificate overlap for `idp_public_certs` specifically was found on this page; that is covered independently in source 05 (the `List[String]` schema type).
