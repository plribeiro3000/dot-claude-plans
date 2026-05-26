# Error contracts

Every state-changing endpoint under `/api/v3/` returns one of a small set of HTTP statuses, each with a documented body schema. The set is uniform across resources — the integrator can build error handling once and reuse it everywhere.

## The status set

| Status | Meaning | Body shape |
|---|---|---|
| 200 / 201 / 204 | success | resource serialization (200/201) or empty (204) |
| 400 | malformed JSON or wrong API surface | `{"error": "...descriptive text..."}` |
| 401 | unauthenticated or insufficient access | `{"error": "..."}` |
| 404 | resource not found (URL identifier doesn't resolve) | empty or `{"error": "..."}` |
| 409 | race condition — resource being processed by another operation | `{"error": "Resource is being processed by another operation. Please try again later."}` |
| 422 | validation failure (model rejected the payload) | per-field validation errors keyed by field name |

## What each status means at the domain level

**400 is not the same as 422.** 400 is "I cannot parse what you sent" or "you used the wrong API surface". 422 is "I parsed your payload, but the data violates business rules". The integrator must distinguish: a 400 indicates a code or configuration problem (malformed JSON, wrong endpoint); a 422 indicates a data problem (missing reference, invariant violation).

**404 always means the URL identifier doesn't resolve.** The URL identifier is a client-side identifier that the server tried to translate to an internal row and failed. A 404 on `/users/:user_id/seat` means the user identifier didn't resolve — not that the user has no seat (every user has a seat).

**409 is rare but real.** A few endpoints — notably groupifications — guard against concurrent modifications to the same resource. A 409 means another integration call (or a manual operation) is currently mutating the same row. The integrator should retry with backoff; the contention is short-lived.

**422 errors are field-keyed.** The body for a 422 is a JSON object where keys are field names and values are arrays of error messages. The field names refer to the **resolved** model columns, not always the **payload** keys (see the identity-translation cross-cutting section for the implications). The integrator must handle the resolved-vs-payload mapping when surfacing errors to operators.

## Per-endpoint error types

The API documentation declares per-endpoint error types: `CreateUserErrors`, `UpdateDealErrors`, `CreateGroupificationErrors`, etc. These are schema definitions describing which fields can appear in a 422 for that specific operation. They are useful for generating typed clients, but the integrator's runtime error handling does not need to switch on them — the schema is uniform within the 422 set.

## What is NOT in the error contract

- **The body of a 4xx response is informational, not actionable for retry**. A 422 says "fix the payload"; a 401 says "re-authenticate"; the integrator's logic should treat the body as a description, not a structured fix instruction
- **The order of fields in the error body is not guaranteed**. Multiple validation errors arrive together; the integrator should not assume the "primary" error is the first
- **There is no dedicated "rate limit" status**. The platform does not currently surface 429s; if it ever does, that will be a separate change with its own error contract

## Implication for the integrator

The integrator should build error handling in three layers:

1. **HTTP status switch** — discriminate 2xx, 4xx, 5xx categories
2. **Within 4xx**: 400/401 → bug or configuration; 404 → unknown identifier (re-check source data); 409 → backoff and retry; 422 → payload violation, log fields and surface to operator
3. **Within 422**: field-by-field, applying the resolved-vs-payload mapping where appropriate

Generic error handling at this level is sufficient for 90% of cases. The remaining 10% are domain-specific (the integrator team has to know that "groupification ends_at must be after starts_at" means the source data has the user leaving before they joined) and live in the runbook deliverable.
