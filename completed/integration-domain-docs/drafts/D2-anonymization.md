# Anonymization and the 5-year rule

The `DELETE /api/v3/users/:user_id/activity` endpoint deactivates a user. There is no explicit "anonymize" endpoint. Anonymization happens automatically as a downstream consequence of deactivation, on a timer that the integrator must understand.

## The legal driver

Brazilian labor law (CLT) gives a former employee the right to file a wrongful-payment claim against an employer for up to 5 years after the end of the employment relationship. As long as that window is open, the employer must be able to produce records of every commission, statement, and payment ever issued to the employee. Anonymizing the employee's record before the window closes would destroy the evidence the employer needs to defend itself.

The 4Shark platform models this directly: a deactivated user is preserved in full for 5 years. Anonymization runs at 5 years + 1 month after deactivation — the extra month is a buffer for the client to reactivate the user before the point of no return.

## What anonymization means

When the timer fires, the user's personally-identifying attributes (name, document number, email) are blanked or replaced with placeholders. The User row stays in the database; foreign keys pointing to it remain valid; but the row no longer carries information that could identify the original employee.

The model expresses this through an `anonymized` flag and conditional validations:

- `unique_register_id` and `identifiers` presence are skipped on anonymized users
- The `anonymization` validation prevents accidentally un-anonymizing a record

After anonymization, the user cannot be reactivated to its original state — the original data is gone. The user can be referenced for historical lookups (which Goals were attached, which Commissions were paid) but the connection to the real person is broken.

## Reactivation resets the counter

If the integrator reactivates a user (`POST /api/v3/users/:user_id/activity`) before anonymization, the deactivation timer is canceled. If the user is later deactivated again, a new 5-year + 1 month clock starts from the new deactivation date.

This matters for re-hiring scenarios. An employee leaves, comes back two years later, leaves again three years after that — the second deactivation resets the clock; the platform anonymizes 5 years + 1 month from the second leaving, not from the first.

## Implication for the integrator

The integrator's contract with the client must clarify:

- **Deactivation is the action**, not deletion. The client's source system marks an employee as no-longer-employed; the integrator translates that to a deactivation call
- **Reactivation is supported up to ~5 years** after deactivation. If the client is uncertain about a re-hire, deactivating is safer than waiting; the integrator can always undo it
- **After ~5 years, the connection is gone**. If the client asks "can we resurrect this person?", the answer is no — the source data must be re-pushed as a new user

A drift specific to anonymization: an integrator that runs reconciliation against the app's data (the app says X users, the source says Y users) will see anonymized users as "users that exist but have no identifying info matching the source". The reconciliation logic must explicitly skip anonymized rows; treating them as drift produces noise and can lead to incorrect "fix" attempts.

## Why this is in the cross-cutting deliverable

Anonymization is not a per-resource behavior — it is a platform-wide rule that affects User specifically but is rooted in legal compliance, not in the User resource's API contract. Documenting it next to the activity sub-resource pattern keeps the activity → deactivation → anonymization chain together, and emphasizes that the integrator's understanding of "deactivation" must include the downstream consequences.
