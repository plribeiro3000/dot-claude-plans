Source: MongoDB Atlas docs — "Manage Identity Providers"
URL: https://www.mongodb.com/docs/atlas/security/manage-federated-auth/
Fetched: 2026-09-03

## Verbatim excerpts

- Field label and description: "IdP Signature Certificate — PEM‐encoded public key certificate of the IdP. You can obtain this value from your IdP."
- "You can either: Upload the certificate from your computer, or Paste the contents of the certificate into a text box."
- "The SAML trust model requires certificate exchange over trusted channels during setup and doesn't require CA-signed certificates. During federated authentication, all traffic between MongoDB Atlas and the browser runs over TLS using a CA-signed certificate. Therefore, `metadata.xml` provides only a self-signed certificate for request signing and signature validation."

## Finding

The MongoDB Atlas console exposes the IdP signature certificate as a manual field — uploaded as a file or pasted as PEM text. No mention of automatic metadata-URL fetching, certificate rotation procedure, or expiration handling was found on this page. This is consistent with the Admin API finding (source 08): the certificate is a value supplied by the administrator, either through the console or through the PATCH API's `pemFileInfo`, never derived automatically by Atlas.
