Source: mongodb/terraform-provider-mongodbatlas — docs/resources/federated_settings_identity_provider.md (GitHub, master branch)
URL: https://github.com/mongodb/terraform-provider-mongodbatlas/blob/master/docs/resources/federated_settings_identity_provider.md
Fetched: 2026-09-03, via `gh api repos/mongodb/terraform-provider-mongodbatlas/contents/docs/resources/federated_settings_identity_provider.md` (raw file content, base64-decoded locally)

## Verbatim excerpt — the note above the example

"~> **IMPORTANT** If you want to use a SAML Identity Provider, you **MUST** import this resource before you can manage it with this provider."

## Verbatim excerpt — full Argument Reference section

```
* `federation_settings_id` - (Required) Unique 24-hexadecimal digit string that identifies the federated authentication configuration.
* `name` - (Required) Human-readable label that identifies the identity provider.
* `description` - (Required for OIDC IdPs) The description of the identity provider.
* `authorization_type` - (Required for OIDC IdPs) Indicates whether authorization is granted based on group membership or user ID. Valid values are `GROUP` or `USER`.
* `associated_domains` - List that contains the domains associated with the identity provider.
* `sso_debug_enabled` - Flag that indicates whether the identity provider has SSO debug enabled.
* `status`- String enum that indicates whether the identity provider is active or not. Accepted values are ACTIVE or INACTIVE.
* `issuer_uri` - (Required) Unique string that identifies the issuer of the IdP.
* `sso_url` - Unique string that identifies the intended audience of the SAML assertion.
* `request_binding` - SAML Authentication Request Protocol HTTP method binding (`POST` or `REDIRECT`) that Federated Authentication uses to send the authentication request. Atlas supports the following binding values:
    - HTTP POST
    - HTTP REDIRECT
* `response_signature_algorithm` - Signature algorithm that Federated Authentication uses to encrypt the identity provider signature.  Valid values include `SHA-1 `and `SHA-256`.
* `protocol` - The protocol of the identity provider. Either `SAML` or `OIDC`.
* `audience` - (Required for OIDC IdPs) Identifier of the intended recipient of the token used in OIDC IdP.
* `client_id` - Client identifier that is assigned to an application by the OIDC Identity Provider.
* `groups_claim` - (Required for OIDC IdP with `authorization_type = GROUP`) Identifier of the claim which contains OIDC IdP Group IDs in the token.
* `requested_scopes` - Scopes that MongoDB applications will request from the authorization endpoint used for OIDC IdPs.
* `user_claim` - (Required for OIDC IdP) Identifier of the claim which contains the user ID in the token used for OIDC IdPs.
```

## Finding

The `mongodbatlas_federated_settings_identity_provider` resource's Argument Reference carries NO field named `pem_file_info`, `certificate`, `x509`, or any equivalent — none of the arguments listed above concern the SAML signing certificate. This matches the shape already declared in `identity/mongodb_federation.tf:5-16`, which sets `name`, `protocol`, `status`, `issuer_uri`, `sso_url`, `request_binding`, `response_signature_algorithm`, `associated_domains`, `sso_debug_enabled` — no certificate argument. The Google IdP signing certificate for the MongoDB Atlas SAML integration is therefore NOT managed by this terraform resource, by construction of the resource's schema, not merely by omission in this particular `.tf` file.
