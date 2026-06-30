# PLAN — Harden access to the workspace-access SA (keyless + JIT-DWD)

## Goal

Reduce the standing attack surface of the `workspace-access` service account (the Gmail+Directory
domain-wide-delegated identity consumed by the `email-erasure` tool). Two structural changes plus
runbook + IaC formalization:

- **Keyless auth** — remove the long-lived downloaded SA key (today a never-expiring bearer in 1Password);
  the tool authenticates via the operator's own MFA-protected Google identity impersonating the SA.
- **Just-in-time DWD** — the domain-wide delegation is granted only during an erasure run and revoked as
  a mandatory closing step, so between runs the SA has no power over any mailbox.

This plan also absorbs the rename's **Phase 6** (runbook `LGPD-DATA-ERASURE.md` §8 name updates) into a
single runbook PR, since the keyless + JIT-DWD flow rewrites the same section.

## Context — audit findings (2026-06-05, read-only)

Evidence captured in `/tmp/gcloud_iam_workspace-access_project_20260605.json` and `_sa_20260605.json`:

- **Project IAM** (`fourshark-workspace-access`): a single binding — `roles/owner` → `user:ivo@4shark.com.br`.
  Nobody else (org-inherited admins aside).
- **SA IAM** (`workspace-access@fourshark-workspace-access.iam.gserviceaccount.com`): **empty** — no direct
  `tokenCreator` / `actAs` binding on the SA.
- **SA keys**: one `USER_MANAGED` key (`7a7c96f7571b67a2190d8b7072cd2e72ec033a24`, **expires year 9999 =
  never**) — the one in Ivo's 1Password; plus the normal non-exportable `SYSTEM_MANAGED` key.

**Conclusion:** the IAM is already minimal (only Ivo). "Audit + lock IAM" is effectively already done — no
surplus binding to remove. The **single real weak point is the never-expiring user-managed key**: a bearer
credential that works from anywhere, without MFA, until deleted. So keyless (which deletes that key) is the
highest-value move; JIT-DWD complements it by removing the standing domain-wide capability.

## Threat model (what each control closes)

| Attack path | Today | After this plan |
|---|---|---|
| Steal the SA key (1P / disk / clipboard) → impersonate any mailbox, no MFA, anywhere | **open** (never-expiring key) | **closed** — no key exists (keyless) |
| Get GCP IAM to mint a key/token on the SA → impersonate | only Ivo (owner) can; minimal | unchanged-minimal; `tokenCreator` granted only to Ivo |
| Use the SA's DWD between runs | **open** (DWD always granted) | **closed** — DWD only during a run (JIT) |
| Compromise Ivo's Google account (owner) | full access | full access — **inherent, out of scope** |
| Org-level admins | full reach | full reach — **inherent, out of scope** |

## Decisions already taken (engineer)

- **JIT-DWD: adopt.** Grant DWD before a run, revoke after as a mandatory runbook step.
- **Keyless: yes.** Move auth to identity-impersonation; drop the downloaded key.
- **Key rotation: rejected** — superseded by keyless (no key to rotate).
- **"Only Ivo runs it"** is enforced by the `tokenCreator` binding on the SA granted only to Ivo's
  (MFA-protected) identity — NOT by repository access. Repo restriction protects code integrity, not
  execution.

## Resolved decisions (engineer, 2026-06-05)

1. **`--key-file`: REMOVE entirely — 100% keyless.** The tool authenticates only via impersonation; no
   key path in the code, no stored key, no break-glass key flag. If keyless ever fails in production, a
   key can be regenerated manually outside the tool, but the tool ships keyless-only.
2. **`tokenCreator` location: the `workspace-access` stack** (IaC, `google_service_account_iam_member`).
   Terraform locality wins — the binding lives with the SA it targets (recreate in lockstep), same
   GCP provider already configured. The `identity/` stack was considered (central identity governance)
   but has no GCP provider and this is the only GCP footprint; governance visibility is handled in the
   runbook instead. Decided after reading `identity/providers.tf` (aws/mongodb/cloudflare/github/rollbar,
   no google).
3. **Validation: full pilot is available** — Anthropic credit is restored (no longer a constraint).
   Phase 3 validates auth and can run the full plan/delete pilot on a seeded test mailbox.
4. **DWD-via-impersonation: implement directly in `strip_attachments.py`** (no isolated spike). The
   standard `service_account.Credentials.with_subject(...)` needs a key; keyless DWD requires signing the
   subject assertion via the IAM Credentials API `signJwt`, then exchanging it at Google's OAuth token
   endpoint for the impersonated user's access token (see jpassing reference below). `unauthorized_client`
   errors are common here — debug inside the tool against the Phase 3 pilot.

## Phases

### Phase 1 — IAM as code: tokenCreator for Ivo on the SA (terraform PR + apply) — ✅ DONE (PR #496 merged, applied)
- Added `google_service_account_iam_member.operator_token_creator` to the `workspace-access` stack
  granting `roles/iam.serviceAccountTokenCreator` on the SA to `user:ivo@4shark.com.br`.
- ✅ Applied (1 added) and PR #496 merged. Local feature branch left undeleted (terraform working tree was
  on another session's branch — `-d` later from develop).

### Phase 2 — Keyless auth in the tool (data-privacy PR) — ✅ DONE (PR #4 merged)
- Pattern Priming on `email-erasure/scripts/strip_attachments.py` before editing.
- Replace auth entirely: build credentials via impersonation of the SA using the operator's ADC, then
  obtain the DWD (`subject`) token via the `signJwt` flow. **Remove the key path completely** — no
  `--key-file` flag, no `load_key_info`, no `KEY_ENV_VAR`.
- `.envrc`: drop the `WORKSPACE_ACCESS_SA_KEY` export (only `ANTHROPIC_API_KEY` remains); update README
  setup (operator runs `gcloud auth login` instead of holding a key).
- CHANGELOG entry.

### Phase 3 — Validate (engineer, full pilot) — ✅ DONE
- Ran `plan --client-domain example.com --mailboxes paulo@4shark.com.br` → impersonated the mailbox via
  signBlob + DWD subject, scanned it, reported 0 hits. Keyless DWD path proven end to end (no
  `unauthorized_client`, no `signBlob denied`). Quota-project warning is benign (ADC user creds).

### Phase 4 — Destroy the key + scrub 1P (engineer, manual) — ✅ DONE
- ✅ Deleted the user-managed key `7a7c96f7571b67a2190d8b7072cd2e72ec033a24` (only the non-exportable
  SYSTEM_MANAGED key remains — no long-lived bearer exists).
- ✅ Removed the `WORKSPACE_ACCESS_SA_KEY` field from the 1Password `Terraform ENV` item.

### Phase 5 — Runbook (dot-claude PR) — absorbs rename Phase 6 — ✅ DONE (PR #234 merged)
- `LGPD-DATA-ERASURE.md` §8: update names (tool `email-erasure`, stack `workspace-access`, project
  `fourshark-workspace-access`) AND rewrite the auth/run flow for keyless + JIT-DWD:
  - **Before a run:** Ivo grants DWD for client-id `100725473573119076992` (scopes mail +
    directory.readonly) in the Admin console; `gcloud auth login ivo@4shark.com.br`.
  - **Run:** keyless (no key file).
  - **After a run (mandatory):** revoke the DWD grant in the Admin console.
- Record the **`deletion_policy` lesson** (google provider v7 defaults `google_project` to `PREVENT`; set
  `DELETE` before tearing a project down, while state still matches config) for any future
  `workspace-access` decommission.

## Sequencing & dependencies
- Phase 1 (tokenCreator) must land before Phase 2 can be validated.
- Phase 4 (delete key) must be LAST — only after Phase 3 proves keyless, so the key is the fallback during
  transition.
- Phase 5 (runbook) can be written in parallel but should reflect the final keyless flow, so finalize it
  after Phase 2's approach is settled.

## Risks & rollback
- **DWD-via-impersonation finickiness** (open question #4) — the biggest risk. Mitigation: Phase 3 auth
  smoke test before deleting the key; the `--key-file` break-glass and the still-present key (until Phase
  4) are the fallback if keyless can't be made to work.
- **Don't delete the key prematurely** — Phase 4 is gated on Phase 3 success.
- JIT-DWD operational risk: forgetting to revoke after a run — mitigated by making revoke a mandatory,
  checklisted closing step in the runbook (Phase 5).

## Done criteria
- The `email-erasure` tool authenticates keyless (operator's `gcloud` identity → SA impersonation → DWD
  subject); no SA key exists; `WORKSPACE_ACCESS_SA_KEY` gone from 1P and `.envrc`.
- `tokenCreator` on the SA is IaC, granted only to Ivo.
- Runbook §8 documents the keyless + JIT-DWD flow with grant-before / revoke-after as mandatory steps, and
  uses the post-rename names.

## References
- Audit evidence: `/tmp/gcloud_iam_workspace-access_project_20260605.json`, `/tmp/gcloud_iam_workspace-access_sa_20260605.json`
- Keyless DWD approach: https://jpassing.com/2022/01/15/using-domain-wide-delegation-on-google-cloud-without-service-account-keys/
- Org-policy key controls (`iam.serviceAccountKeyExpiryHours`, `iam.disableServiceAccountKeyCreation`): https://docs.cloud.google.com/organization-policy/restrict-service-accounts
- SA security best practices: https://docs.cloud.google.com/iam/docs/best-practices-service-accounts
