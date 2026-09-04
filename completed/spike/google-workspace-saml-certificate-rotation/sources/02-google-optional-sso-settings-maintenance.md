Source: Google Workspace Help — "Optional SSO settings and maintenance"
URL: https://knowledge.workspace.google.com/admin/apps/optional-sso-settings-and-maintenance?hl=en-EN (canonical redirect target of https://support.google.com/a/answer/6369487?hl=en-EN)
Fetched: 2026-09-03

## Verbatim excerpts

- "If you upload two certificates to a SAML Single Sign-On (SSO) profile, Google can use either certificate to validate a SAML response from your IdP."
- "Follow these steps at least 24 hours before a certificate is due to expire."

## Context

This page frames the rotation as: create a new certificate on the identity provider side, upload it as a secondary certificate in the Admin console, wait 24 hours for propagation, configure the IdP (i.e. the third-party SP consuming Google's signature, or vice versa depending on direction) to use the new certificate, then optionally remove the old one.

## Notes on what the page does NOT state

- No mention of automatic certificate expiry notifications or email alerts.
- No mention of downloading IdP metadata programmatically.
- No mention of an Admin API for automating SAML certificate management on this feature.
