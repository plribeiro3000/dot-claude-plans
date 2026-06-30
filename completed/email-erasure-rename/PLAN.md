# PLAN — Rename `client-offboarding` (infra→`workspace-access`, tool→`email-erasure`)

## Goal

Coherence rename, split by responsibility after the naming discussion:
- The **Terraform stack is an access gate** — it provisions programmatic Google Workspace access
  (Gmail + Directory, DWD) and does nothing with it. Named for what it provisions:
  **`workspace-access`**.
- The **runtime tool does the erasure** — it lives in `data-privacy` and is named for the action:
  **`email-erasure`**.

So infra and tool get different, accurate names. The `fourshark-` prefix is required **only** on the
GCP project ID (globally unique across all of GCP, ≤30 chars); the folder/SA/env var need no prefix.

### Name cascade
| Layer | From | To |
|---|---|---|
| Terraform stack dir | `terraform/client-offboarding/` | `terraform/workspace-access/` |
| Terraform SA account_id | `client-offboarding` | `workspace-access` |
| Terraform backend state key | `client-offboarding/terraform.tfstate` | `workspace-access/terraform.tfstate` |
| GCP project (recreate — ID is immutable) | `fourshark-client-offboarding` | `fourshark-workspace-access` |
| Service account email | `client-offboarding@…` | `workspace-access@fourshark-workspace-access…` |
| Env var / 1Password field | `CLIENT_OFFBOARDING_SA_KEY` | `WORKSPACE_ACCESS_SA_KEY` |
| Runtime tool dir (data-privacy) | `client-offboarding/` | `email-erasure/` |
| Out-dir convention (docs) | `/tmp/offboarding-<client>` | `/tmp/<client>-email-erasure` |
| `--admin-user` (impersonated super-admin) | `ivo@4shark.com.br` | **unchanged** |
| DWD scopes | mail + directory.readonly | **unchanged** (only the SA client-id changes) |

## Safe-order principle

**Create the new capability alongside the old, validate it, then retire the old.** The GCP project ID
is immutable, so "rename" = recreate. Never break the running capability: the old project/SA/key stay
live until a pilot proves the new one works.

## Phases

### Phase 1 — New GCP stack (terraform PR + apply) — ✅ PR merged (#494)
- Added a **new** `workspace-access/` stack in `terraform` (project_id `fourshark-workspace-access`,
  SA account_id `workspace-access`, backend state key `workspace-access/terraform.tfstate`,
  access-gate framing, provisioning README pointing to `data-privacy/email-erasure/`). The old
  `client-offboarding/` stack stays untouched for now. **PR #494 merged.**
- **OPEN — engineer:** `plan` → `apply` (this stack uses `AWS_PROFILE=4shark-mfa` for the S3 backend +
  GCP ADC) → creates the new project + SA. Note the new `service_account_email` +
  `service_account_unique_id` outputs. (Confirm whether the apply ran before/at merge — Phase 2 needs
  the outputs.)

### Phase 2 — Manual GCP/1P setup (engineer)
- **Grant domain-wide delegation** for the **new** SA's client-id (`service_account_unique_id`) in the
  Workspace Admin console, same scopes (`https://mail.google.com/`, admin.directory.user.readonly).
- **Generate the new SA key** (as `ivo@4shark.com.br`, project `fourshark-workspace-access`) and store
  it as **`WORKSPACE_ACCESS_SA_KEY`** in **your own** `Terraform ENV` 1Password item; delete the local
  `key.json`.
- ✅ **DONE** — DWD granted (client-id `100725473573119076992`, scopes mail + directory.readonly); key
  generated and stored as `WORKSPACE_ACCESS_SA_KEY` in 1P. **Note:** the old `CLIENT_OFFBOARDING_SA_KEY`
  field was deleted now (not at Phase 5) — harmless: the old tool just can't run anymore, and it is
  being retired anyway with no erasure in flight.

### Phase 3 — Rename the runtime tool (data-privacy PR) — 🔄 PR #3 open (against `main`)
- Rename `data-privacy/client-offboarding/` → `data-privacy/email-erasure/`.
- In the script: `KEY_ENV_VAR = "CLIENT_OFFBOARDING_SA_KEY"` → `"WORKSPACE_ACCESS_SA_KEY"`; rename any
  `client-offboarding` references (the tool's own `client-offboarding` package-name exclusions and
  the `delete` hint paths are about the *client's* data, not this tool — leave the
  `NAME_EXCLUSIONS` / 4Shark-tooling-package list alone; only rename the tool's own identifiers).
- `.envrc`: export `WORKSPACE_ACCESS_SA_KEY` (+ `ANTHROPIC_API_KEY`).
- READMEs (top + component): rename, update the out-dir convention to `/tmp/<client>-email-erasure`,
  update the pointer to the terraform `workspace-access/` stack.
- CHANGELOG entry.

### Phase 4 — Validate (engineer, pilot) — ✅ superseded by the hardening pilot (keyless, proven on paulo@4shark.com.br)
- With the **new** SA key + DWD grant, run a **pilot** `plan` on a seeded test mailbox
  (`--mailboxes <test@4shark.com.br> --out-dir /tmp/pilot-email-erasure`) → confirm it authenticates,
  scans, and triages. Optionally a `delete` on the seeded test message. **Do not proceed to Phase 5
  until the new capability is proven.**

### Phase 5 — Retire the old (terraform PR + apply, then manual) — 🔄 infra destroyed; PR #495 open
- terraform PR #495: **removes the old `client-offboarding/` stack dir** — **OPEN, awaiting merge**.
- ✅ **Infra destroyed.** `terraform destroy` removed the SA + Gmail + Admin SDK. The project hit the
  google-provider-v7 `deletion_policy = "PREVENT"` default (blocks `terraform destroy`); since the
  partial destroy had already dropped SA/APIs from state, a re-`apply` would have **recreated** them —
  so the project was removed via `terraform state rm google_project.this` + `gcloud projects delete
  fourshark-client-offboarding` (30-day pending-deletion, reversible via `gcloud projects undelete`).
  **Lesson for tearing down `workspace-access` later:** add `deletion_policy = "DELETE"` to the
  `google_project` *before* destroying, while state still matches config — avoids this two-step.
- ✅ Old `CLIENT_OFFBOARDING_SA_KEY` 1Password field already deleted (Phase 2).
- **OPEN — engineer (manual):** remove the old DWD grant (client-id `106577996691387091601`) in the
  Admin console. Optional: delete the orphan empty S3 state object `client-offboarding/terraform.tfstate`.

### Phase 6 — Docs (dot-claude PR) — ✅ absorbed into the hardening PLAN's Phase 5 (dot-claude PR #234, merged)
- Runbook `LGPD-DATA-ERASURE.md` §7/§8: update names — tool dir `email-erasure`, terraform stack
  `workspace-access`, GCP project `fourshark-workspace-access`, env var `WORKSPACE_ACCESS_SA_KEY`,
  out-dir convention `/tmp/<client>-email-erasure`. `--admin-user ivo@4shark.com.br` and the scopes stay.
- Verify cross-links: terraform `workspace-access/README.md` ↔ data-privacy `email-erasure/README.md`
  (done in their PRs; verify consistency).

## Cross-references to update (checklist)
- [x] terraform: new `workspace-access/` stack (Phase 1, PR #494 merged)
- [ ] terraform: remove old `client-offboarding/` stack (Phase 5)
- [~] data-privacy: dir rename → `email-erasure/` + `KEY_ENV_VAR`→`WORKSPACE_ACCESS_SA_KEY` + `.envrc` + READMEs + out-dir convention (Phase 3, PR #3 open)
- [ ] dot-claude runbook §7/§8 names (Phase 6)
- [ ] GCP: new project + SA + DWD (Phases 1–2); destroy old + remove DWD (Phase 5)
- [ ] 1Password: add `WORKSPACE_ACCESS_SA_KEY`, remove `CLIENT_OFFBOARDING_SA_KEY` (Phases 2, 5)

## Risks & rollback
- **Don't change project_id in place** — that would force a destroy+create in one apply and break the
  capability mid-flight. The new-alongside-old order avoids this.
- **GCP project destroy is recoverable for 30 days** (pending deletion) — Phase 5 is reversible.
- **Env-var cutover:** the tool reads `WORKSPACE_ACCESS_SA_KEY` after Phase 3; ensure the 1P field
  exists (Phase 2) before merging Phase 3, or the tool can't find the key.
- The Aster run output the engineer moved to home is unaffected — it is data, not tied to the names.

## Done criteria
- Tool runs from `data-privacy/email-erasure/` using `WORKSPACE_ACCESS_SA_KEY` against the
  `fourshark-workspace-access` project's SA; the old project/SA/grant/1P-field are gone; runbook +
  READMEs use the new names; nothing references `client-offboarding` except the client's-own-data
  package exclusions (which are unrelated).
