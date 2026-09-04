Source: MongoDB Atlas Admin API v2 — "Update One Identity Provider"
URL: https://www.mongodb.com/docs/api/doc/atlas-admin-api-v2/2024-10-23/operation/operation-updateidentityprovider
Fetched: 2026-09-03 (fetched twice, independently, for self-check — second fetch confirmed and expanded the first)

## Verbatim excerpts

- Endpoint: "PATCH /api/atlas/v2/federationSettings/{federationSettingsId}/identityProviders/{identityProviderId}"
- Protocol support (second fetch): "This endpoint supports both SAML and OIDC identity providers. The request body accepts one of three types: SAML object, OIDC WORKFORCE object, OIDC WORKLOAD object."
- Required role: "requires the requesting Service Account or API Key to have the Organization Owner role in one of the connected organizations."
- `pemFileInfo` schema (first fetch, exact structure):

```
pemFileInfo object
  PEM file information for the identity provider's current certificates.
  certificates array[object]
    List of certificates in the file.
    content string — Certificate content.
    notAfter string(date-time) — Latest date that the certificate is valid. ISO 8601 UTC.
    notBefore string(date-time) — Earliest date that the certificate is valid. ISO 8601 UTC.
  fileName string — Human-readable label given to the file.
```

## Finding

The Atlas Admin API's PATCH (update) endpoint for an identity provider accepts a `pemFileInfo.certificates` array — meaning it can be given more than one certificate object in a single request, and the update path (as opposed to the create path) is confirmed to support SAML identity providers. This is a candidate for automating the SAML-side certificate value once Google issues the new certificate, bypassing the terraform resource entirely (source 07) since terraform has no field to carry it.

Authentication for this call requires a Service Account or API key with Organization Owner role in the connected organization — a credential this spike does not have and did not attempt to use.
