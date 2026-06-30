# PLAN — Per-stack `.envrc` for the Terraform repo

## Context

Today the Terraform repo has a single root `.envrc` that pulls 7 secrets from the `Terraform ENV`
1Password item (Employee vault) and exports all of them. Every terraform command runs as
`direnv exec ~/Projects/4Shark/terraform terraform -chdir=<stack> <cmd>`, so **every stack run
loads all 7 secrets** regardless of need. The repo root manages no resources — it is only the
direnv entry point.

The `client-offboarding` stack already broke this pattern: it has its own standalone `.envrc`
(no `source_up`) exporting only `CLIENT_OFFBOARDING_SA_KEY`. This plan generalizes that to every
stack.

## Goal

Each stack carries its own `.envrc` exporting only the secrets it actually needs. The root
`.envrc` is removed. A leaked shell (or an env dump in a stack's run) exposes only that stack's
secrets, not the full set.

## Decisions (locked by the engineer)

- **a)** Adopt per-stack `.envrc`. ✅
- **b)** Remove the root `.envrc` entirely (no fallback). ✅
- **c)** `identity` lists its secrets explicitly (drop `source_up`). ✅

## Verified secret → stack mapping

Source of truth: each stack's `.terraform.lock.hcl` (records every provider, including those
pulled via modules — the `provider "X"` grep was unreliable and is NOT used here).

| Stack | Secrets the `.envrc` must export | Profile |
|---|---|---|
| `app-atento-001` | `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY`, `REDISCLOUD_ACCESS_KEY`, `REDISCLOUD_SECRET_KEY` | default / 4shark-mfa |
| `app-beta-001` | same as atento | default / 4shark-mfa |
| `app-demo-001` | same as atento | default / 4shark-mfa |
| `app-shared-001` | same as atento | default / 4shark-mfa |
| `onboarding` | `REDISCLOUD_ACCESS_KEY`, `REDISCLOUD_SECRET_KEY` | default / 4shark-mfa |
| `dns` | `CLOUDFLARE_API_TOKEN` | default / 4shark-mfa |
| `monitoring` | `ROLLBAR_API_KEY` | default / 4shark-mfa |
| `identity` | `CLOUDFLARE_API_TOKEN`, `MONGODB_ATLAS_PUBLIC_KEY`, `MONGODB_ATLAS_PRIVATE_KEY`, `ROLLBAR_API_KEY`, `GITHUB_TOKEN` + `AWS_PROFILE=ivo` | ivo (break-glass) |
| `audit` | none (AWS-only) + `AWS_PROFILE=ivo` | ivo (break-glass) |
| `client-offboarding` | `CLIENT_OFFBOARDING_SA_KEY` (already done) | default / 4shark-mfa |
| all others — `auth-001`, `networking`, `vpn`, `setup`, `integrator-*` (5), `shared-resources`, `app-outbound-atento-br` | none — no `.envrc` needed | default / 4shark-mfa |

## Target execution model

New canonical form (load the **stack's** `.envrc`, not the root):

```
direnv exec ~/Projects/4Shark/terraform/<stack> terraform -chdir=~/Projects/4Shark/terraform/<stack> <subcommand>
```

- Stacks with an `.envrc` → direnv loads their scoped secrets.
- Stacks without an `.envrc` → direnv loads nothing; terraform runs with the AWS profile only.
- `identity` / `audit` → their `.envrc` exports `AWS_PROFILE=ivo`; no inline `env AWS_PROFILE` needed.
- Apply for non-break-glass stacks still layers MFA inline:
  `direnv exec ~/Projects/4Shark/terraform/<stack> env AWS_PROFILE=4shark-mfa terraform -chdir=<stack> apply <file>`

## Scope — two repos

### Repo 1: `terraform`

1. **7 new `.envrc`** (standalone, no `source_up`, `op item get 'Terraform ENV'` + export only the
   stack's vars): `app-atento-001`, `app-beta-001`, `app-demo-001`, `app-shared-001`, `onboarding`,
   `dns`, `monitoring`. Pattern mirrors `client-offboarding/.envrc`.
2. **Rewrite `identity/.envrc`**: replace `source_up` + `AWS_PROFILE=ivo` with explicit exports of
   the 5 secrets it uses + `AWS_PROFILE=ivo`.
3. **Rewrite `audit/.envrc`**: replace `source_up` + `AWS_PROFILE=ivo` with just `AWS_PROFILE=ivo`.
4. **Remove the root `.envrc`** (decision b).
5. Each new/changed `.envrc` needs a one-time `direnv allow`.

### Repo 2: `dot-claude` (the convention lives here — must change in lockstep)

1. **`settings.json` `permissions.allow`** — the 17 patterns hardcode the root path. Rewrite:
   - Read (11): `Bash(direnv exec ~/Projects/4Shark/terraform/* terraform -chdir=* <subcommand>*)`
   - Mutating (6): `Bash(direnv exec ~/Projects/4Shark/terraform/* env AWS_PROFILE=4shark-mfa terraform -chdir=* <subcommand>*)`
   - **RISK / must-test**: the `~/Projects/4Shark/terraform/*` glob and prefix-matcher behavior
     (greedy `*`, the anchoring literal ` terraform -chdir=`). Verify each subcommand still
     auto-approves and that mutating stays scoped to the MFA form. This is the load-bearing,
     fiddly part of the whole plan.
2. **`docs/TERRAFORM-CONVENTIONS.md`** — § Environment Variables (lines ~64-102): the canonical
   form, the `.envrc`-at-root description, the allow-list mirror explanation.
3. **`docs/TERRAFORM-POLICY.md`** — the "ALWAYS prefix with `direnv exec ~/Projects/4Shark/terraform`" bullet.
4. **`scripts/inject-terraform-context.sh`** — the injected text repeats the root-path rule.
5. **`CLAUDE.md`** — any reference to the root-`.envrc` execution model (e.g. Terraform Policy section).

## Execution phases (staged to avoid breaking terraform access mid-flight)

The two repos must not drift: if the root `.envrc` is removed while the convention still says
"`direnv exec <root>`", secret-needing stacks fail auth. Staging:

- **Phase 1 — terraform (additive only).** Add the 7 new `.envrc`, rewrite `identity`/`audit`,
  but **keep the root `.envrc`** for now. `direnv allow` each. Open PR. No resource changes →
  no plan/apply, but verify auth (next section). Merge.
- **Phase 2 — dot-claude.** Update docs + hook + `settings.json` patterns to the per-stack form.
  Open PR. Test that terraform commands still auto-approve under the new patterns. Merge, then
  `git -C ~/.claude pull`.
- **Phase 3 — terraform (removal).** Remove the root `.envrc` (decision b). Open PR. Re-verify a
  couple of secret stacks under the now-final convention. Merge.

Rationale: after Phase 1 both old (root) and new (per-stack) forms work, so nothing breaks while
Phase 2 switches the convention. Phase 3 drops the now-unused root file last.

## Verification (per secret-needing stack)

For each stack with an `.envrc`, confirm provider auth works under the **new** form before relying
on it (read-only, safe):

```
direnv exec ~/Projects/4Shark/terraform/<stack> terraform -chdir=<stack> plan
```

A clean plan (no Cloudflare `Missing X-Auth-Key` / Atlas / Redis auth error) = the scoped `.envrc`
exports the right vars.

- `app-atento-001`, `app-beta-001`, `app-demo-001`, `app-shared-001`, `onboarding`, `dns`,
  `monitoring` — Claude can verify (default profile, read-only plan).
- `identity`, `audit` — **break-glass only**; the `guard.tf` postcondition rejects any caller but
  the break-glass owner. The owner (ivo) verifies these two, not Claude.

## Risks

1. **Permission-matcher rewrite (highest).** `settings.json` glob behavior with `~/.../terraform/*`
   is prefix-matched and greedy; a wrong pattern silently turns every terraform command into an
   approval prompt (or, worse, over-broadens auto-approve). Must be tested command-by-command.
2. **Two-repo coordination.** Phases must land in order; a half-applied change breaks terraform
   auth. Mitigated by keeping the root `.envrc` through Phase 2.
3. **Break-glass stacks.** `identity` / `audit` cannot be verified by Claude — handoff to the
   break-glass owner.
4. **`op item get` duplication.** Each scoped `.envrc` repeats the `op item get 'Terraform ENV'`
   boilerplate. Accepted — direnv files are self-contained by design; not worth a shared helper.

## Rollback

Each phase is its own PR. If Phase 2's permission patterns misbehave, revert the dot-claude PR
(`git -C ~/.claude pull` after revert) — Phase 1 left the root `.envrc` in place, so the old form
still works. Phase 3 (root removal) only runs after Phase 2 is proven.

## Out of scope

- No change to which secrets live in 1Password (still one `Terraform ENV` item with all fields).
- No change to stacks that need no third-party secret beyond not giving them an `.envrc`.
- No change to the AWS MFA flow.
