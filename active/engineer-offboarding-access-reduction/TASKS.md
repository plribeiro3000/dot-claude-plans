# Tasks — Engineer Offboarding, AWS Access Reduction

Companion to `PLAN.md`. Subject: IAM user `emerson.silva@4shark.com.br`, account `405749097490`.
Run every AWS command with `--profile 4shark-mfa`.

## Done — interim reduction (2026-07-31)

- [x] Map the engineer's effective AWS access from the deployed policy documents
- [x] Confirm the other platforms need no action (Atlas read-only, Cloudflare read-only, SSO
      `ReadOnlyAccess`, GitHub `member`)
- [x] Create and attach `DestructiveActionGuardrail` to the user
- [x] Set permissions boundary `arn:aws:iam::aws:policy/ReadOnlyAccess` on the user
- [x] Deactivate MFA device `arn:aws:iam::405749097490:mfa/4shark-1Password`
- [x] Verify the end state with `simulate-principal-policy` — reads allowed, everything else denied

## Pending — at the cut

- [ ] List the access keys before deleting the user, so the record shows what existed. A second
      key could have been created up to the moment the boundary landed.

      aws iam list-access-keys --user-name emerson.silva@4shark.com.br --profile 4shark-mfa

- [ ] Delete every access key found, starting with `AKIAV46EH4QJB5QNOWER`

      aws iam delete-access-key --user-name emerson.silva@4shark.com.br --access-key-id <KEY_ID> --profile 4shark-mfa

- [ ] Delete the orphaned virtual MFA device. The seed is still in the engineer's 1Password;
      the boundary blocks re-enrolment, but the device should not outlive the account.

      aws iam delete-virtual-mfa-device --serial-number arn:aws:iam::405749097490:mfa/4shark-1Password --profile 4shark-mfa

- [ ] Remove the engineer from `engineers` in `identity/terraform.tfvars` and apply the
      `identity/` stack from the break-glass account (`AWS_PROFILE=ivo` — `identity/guard.tf`
      admits no other caller). This deletes the IAM user, and with it the boundary and the
      guardrail attachment, resolving the CLI drift.

- [ ] Delete the now-unattached `DestructiveActionGuardrail` policy

      aws iam delete-policy --policy-arn arn:aws:iam::405749097490:policy/DestructiveActionGuardrail --profile 4shark-mfa

- [ ] Revoke access on the platforms outside AWS: MongoDB Atlas, Cloudflare, Rollbar and the
      GitHub org — all driven by the same `engineers` map, so the single `identity/` apply covers
      them. Confirm each one afterwards rather than assuming the apply reached it.

- [ ] Revoke VPN access (Pritunl) — outside the `identity/` stack, so it needs its own step.

## Follow-up, independent of the cut

- [ ] Trace where `iam:PutUserPermissionsBoundary` and `iam:DeactivateMFADevice` against another
      user actually come from. Neither appears in the deployed documents of any policy on the
      `engineers` group, yet both succeeded. See `PLAN.md` § Open item. If the grant is real and
      intentional, document it in ADR-004; if it is drift, reconcile it into the identity stack.

- [ ] Three unrelated orphaned virtual MFA devices sit in the account inventory —
      `1password-2`, `Ivan-4shark`, `my-auth-app`. Unrelated housekeeping, safe to delete once
      each is confirmed to belong to nobody.
