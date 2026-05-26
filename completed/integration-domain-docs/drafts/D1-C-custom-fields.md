# Custom fields — two models, one concept

The platform supports custom fields on User and on Deal, but the implementation differs because the use cases differ. The same conceptual feature ("attach extra business data to a resource") is served by two distinct models: `Field` for User, `DealField` for Deal.

| | Field (User) | DealField (Deal) |
|---|---|---|
| Endpoint | `/users/:user_id/fields` (create + destroy) | `/deals/:deal_id/fields` (create + update); also nested in Deal create AND update |
| Payload | `{key, value}` | `{variable, value}` |
| Key resolution | free string (the `key` is whatever the client chose) | the `variable` must reference a registered Variable on the server |
| Type validation | none beyond presence and format | the Variable's type drives validation (e.g. date variables require ISO 8601) |

## Why two designs

The 4Shark platform is SaaS serving companies of every shape. Each company's commercial area has its own vocabulary — what one calls "department", another calls "division", another calls "cell". The User table cannot fit every client's vocabulary directly. Custom fields extend the User schema with whatever the client needs: department, hire date, line manager's identifier in some external system, work shift code, anything.

The semantic of those fields is **client-defined**. The platform does not interpret them. A `key: "department"` field on User is just a label; it shows up wherever User attributes are displayed, but no commission rule reads it. The free-form `{key, value}` shape matches that semantic — the platform doesn't need to validate something it doesn't interpret.

Deal custom fields are different. A custom field on a Deal can participate in commission calculation: a Variable referenced by an indicator might pull its value from the Deal's custom fields. That means the platform DOES interpret the value — it has to know whether the value is a number, a date, a boolean, in order to compute reliably. Free-form `{key, value}` would force every commission rule to handle string-to-typed coercion at calculation time, with no way to validate the value at the moment it was set.

The DealField design solves this by requiring every custom field to reference a registered Variable. The Variable carries the type, the format rules, and any other metadata the platform needs to validate the value at write time. The integration script cannot push a malformed value into a DealField; the rejection happens at the API call, not at the calculation step weeks later.

## Implication for the integrator

When configuring the integrator's custom-field mapping for a new client, the two contracts require different work:

- **For User custom fields**, the integrator writes a translator that takes the client's source-data column and emits `{key, value}`. Whatever the client's column name is becomes the `key` (or a normalized version of it). No server-side configuration is required.
- **For Deal custom fields**, the integrator team must first ensure the corresponding Variable exists on the app side. Pushing a `DealField` referencing an unregistered Variable will reject. This is a coordination requirement between the integration setup and the app's onboarding configuration.

This is a class of drift that does not surface at User integration but does at Deal integration: a client whose User integration runs cleanly may still see all their Deal custom fields rejected because nobody created the Variables.
