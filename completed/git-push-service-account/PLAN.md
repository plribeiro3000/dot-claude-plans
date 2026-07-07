# PLAN — Non-interactive `git push` via a scoped 1Password Service Account (remote/mobile-friendly)

**Status:** ⛔ CLOSED — NOT PROCEEDING. **Created:** 2026-07-06. **Closed:** 2026-07-06.

**Closing decision (engineer):** the required mechanism (1Password Service Accounts) is not available on 4Shark's **Teams Starter** plan (confirmed: no Service Account option under Developer in the admin console). Upgrading to 1Password Business is **not justified for this single use case** — the cost is not worth it. This plan is closed without execution; no code was written (halted at Phase 0 pattern-priming).

**Superseded by a better direction:** rather than work around the plan limit, the team is reframing the problem as a principle — keys currently gated by the 1Password biometric agent will be **inventoried and classified by blast radius**: low-risk keys move to disk (enabling remote/mobile work), high-risk keys (e.g. Terraform) stay biometric and machine-bound. See the follow-up spike `~/.claude/plans/active/spike/credential-risk-classification/` (the governing rule: *simple/low-blast-radius operations are remote-able; large/destructive operations require being at the machine*). The research in `~/.claude/plans/active/spike/remote-1password-ssh-approval/SPIKE.md` (1Password biometric is local-host-only; Remote Control executes locally) remains the valid grounding for that spike.

**Confirmed by engineer (2026-07-06 review):**
- **D1 = Service Account** (recommended path confirmed; the deploy-key alternative is rejected).
- **D7 = one credential per developer** — a fresh key + its own Service Account token per machine (isolated blast radius, per-machine revocation, inherent attribution).
- **D3 = fresh dedicated key** used only for push (R1); **D2 = transient materialization**, **D4 = OS-native secure store**, **D6 = standalone TI-owned vault** — proposed defaults accepted.
- **D5 = 90-day token expiry** (`--expires-in`); **owner of re-issuance:** each developer re-issues their own machine's token; the vault + Service Accounts are managed by the responsible-for-IT.
- **Vault name:** `Git Automation` (default; per-dev items named by machine inside it — adjustable).
- **Emerson / WSL:** all git + SSH run natively inside WSL2 — nothing traverses the Windows host (binaries `/usr/bin/git`, `/usr/bin/ssh`; keys/config in WSL `~/.ssh`; `gh` credential helper is the WSL `gh`, not the Windows GCM). Therefore Finding 14's Windows per-host limitation **does NOT apply** — per-host `IdentityAgent` routing is available on all three machines.

**Anchored on** (do not re-derive — these are the validated inputs):
- `~/.claude/plans/active/spike/remote-1password-ssh-approval/SPIKE.md` — Findings 10–17 (the mechanics, verified with 1Password official sources)
- `~/.claude/plans/completed/terraform/credential-hygiene/PLAN.md` — the "infra is the single source of truth; SSH keys deliberately KEPT in 1Password" precedent
- `~/.claude/plans/active/legal-compliance-documents/mapa-de-vaults-1password.md` + `categorizacao-vaults-1password.md` — the existing vault-tiering study this plan extends

## ⛔ BLOCKER (2026-07-06) — Service Accounts not available on the current 1Password plan

Confirmed by the engineer in the 1Password admin console: **there is no Service Account option under Developer** — 4Shark is on **Teams Starter**, which does not expose Service Accounts (public docs are silent on the tier gate; the console is authoritative). **D1 (Service Account) is not viable on the current plan.** The build (Phase 0) is halted before any code.

**Key reframe that reshapes the alternatives:** the Service-Account path was going to materialize the private key onto disk anyway (Finding 11 — `op read` extracts it). So the vaulting benefit of the SA path was mostly about the **token lifecycle** (rotation/audit/expiry), not the key at rest. A plain **dedicated on-disk git key** (outside 1Password, git-only via SSH-config routing) reaches nearly the same runtime outcome — key on disk, no prompt — with **zero plan change** and far less machinery, losing only the token-lifecycle layer that Teams Starter does not provide anyway.

**Revised direction — engineer decides (recorded once chosen):**
- **On-disk dedicated git key** (no 1Password, no plan change) — simplest; ≈ the SA path's runtime posture. Per-account key (covers all repos) or per-repo deploy keys (tighter scope, more setup).
- **Upgrade to 1Password Business** — unlocks Service Accounts and restores token rotation/audit; a cost/plan decision for the team.
- **Do nothing** — keep the biometric agent for git too; remote/mobile push stays blocked (the original state).

Everything below (the SA-specific mechanics, phases, per-machine SA provisioning) is **on hold pending this decision** and applies as-written only to the Business-upgrade branch. The on-disk-key branch reuses the coexistence wiring (SSH-config per-host routing, Findings 13/14) but drops all Service-Account / `op read` machinery.

## Problem

A Claude Code Remote Control session runs entirely on the physical Mac (SPIKE Finding 5). When it triggers `git push`, the 1Password SSH agent raises a Touch ID prompt on that Mac — which nobody can satisfy when the engineer is remote with only a phone. `git push` is low-stakes (protected by branch protection + PR review; force-push to `develop`/`master` is already blocked), so requiring a live biometric per push is friction without a matching security payoff. The goal: **`git push` authenticates non-interactively; every higher-stakes operation (`terraform apply`, AWS console, other secrets) keeps the live biometric untouched.**

## The mechanism, settled by the spike (so the plan does not relitigate it)

- A Service Account **cannot drive the 1Password SSH agent** — they are separate products (Finding 10). So this is NOT "point the biometric agent at a token."
- The non-interactive path is: a Service Account authorizes `op read` to pull the git-push **private key value** out of a scoped vault; that key is handed to a standard OpenSSH mechanism used **only** for git remotes (Finding 11).
- Coexistence with the biometric agent is official and clean, via SSH config per-host routing — `Host github.com` → the git-only key; `Host *` → the 1Password agent socket (Finding 13).
- Hard constraint: `OP_SERVICE_ACCOUNT_TOKEN` and a signed-in personal account **cannot both be active in the same process environment** (Finding 12). The token must be scoped to the git-push invocation, never a global shell export.

## Options analysis — the one decision that gates the plan's shape

### Decision D1 (RECOMMENDED path): git-push key stays inside 1Password, fronted by a scoped Service Account

The key lives in a new, dedicated, narrowly-scoped 1Password vault; a Service Account token (scoped read-only to that one vault) lets the local session materialize it non-interactively at push time.

- **Why recommended — grounded in your own docs, not a default:** the credential-hygiene effort removed copies from 1Password *only when a home existed elsewhere*, and **explicitly kept SSH keys in 1Password**. The stated principle valued vaulting, rotation, revocation, and audit — exactly the properties a Service Account preserves and a deploy key discards. The vault-tiering study already thinks in "which vault, which access tier"; a machine-scoped vault extends that model cleanly.
- **Cost (stated honestly, Finding 11):** for this one key, the interactive agent's "private key never leaves 1Password" guarantee no longer holds — the key is materialized (transiently or at rest) outside the vault. Blast radius is bounded to this single git-push key by the vault scope (Finding 10/16), NOT the whole keychain.

### Decision D1 (ALTERNATIVE, documented for your review): GitHub deploy key, no 1Password involvement

A plain per-repo SSH key pair, public half on the GitHub repo, private half on the machine.

- **Simpler** per repo; no `op` scripting, no Service Account to provision.
- **Rejected for our posture because** (Finding 17): no expiry, usually no passphrase, write-enabled deploy key = full collaborator power on that repo, and it sits entirely outside 1Password's vaulting/rotation/audit — the opposite of what credential-hygiene deliberately preserved. Surfaced so the choice is explicit; the engineer overrides here if desired.

**→ The rest of this plan assumes D1-RECOMMENDED (Service Account). If the engineer picks the deploy-key alternative at review, Phases 1–2 collapse to "generate key pair, register as deploy key, reference via SSH config" and Phases 3–5 simplify accordingly.**

## Sub-decisions carried INTO the plan (defaults proposed, engineer confirms at review)

- **D2 — key materialization: transient vs at-rest.** *Proposed default: transient.* A git `core.sshCommand` (or push wrapper) runs `op read` at push time to load the key into a short-lived agent/temp handle, rather than persisting the extracted key on disk. This keeps the *raw key* off disk; the secret genuinely at rest becomes the **token** (which is scopeable, rotatable, revocable, expirable — a raw persisted key is none of those). Trade-off: slightly more moving parts than a one-time `op read --out-file`.
- **D3 — vault scope & permission.** *Proposed default: one dedicated vault holding only the git-push key; token scoped `read_items` only* (write is needed only if the token itself must rotate the key — it does not, an engineer rotates it). Scope is immutable post-creation (Finding 16) — a scope change means a new Service Account, which is acceptable.
- **D4 — token storage per OS.** *Proposed default: OS-native secure store* (macOS Keychain / Linux Secret Service / for WSL see Phase 3). 1Password does not prescribe this (Finding 16) — it is our own choice; the alternative is a `0600` file, weaker.
- **D5 — token expiry / rotation cadence.** *Proposed default: bounded `--expires-in` with a named owner responsible for re-issuing before expiry,* so a token does not silently expire mid-remote-session and strand a push. Cadence is the engineer's call.
- **D6 — vault placement in the existing tier model.** The git-push vault is a **machine-identity vault**, a new axis the tiering study (human-access groups) did not cover. *Proposed default: a standalone vault owned by the responsible-for-IT, NOT shared into Platform/Technology/Marketing human tiers;* its "member" is effectively the Service Account. Vault membership stays Console-UI-managed (Teams Starter, no IaC — per the vault study's recorded constraint).
- **D7 — credential topology across the three machines (the plan under-specified this — raised at review).** The setup must work on Paulo's macOS, Leandro's Ubuntu, and Emerson's WSL2. Two shapes:
  - **(a) One shared credential** — a single git-push key + a single Service Account token, distributed to all three machines. Simpler (one vault, one token, one key to manage), but the token/key sits on three machines, a leak on any one exposes the shared credential, and pushes are not attributable to a specific machine at the credential layer.
  - **(b) One credential per developer** — a key + token per machine (three items in the vault, or three narrow vaults). More setup and lifecycle surface, but a leak is isolated to one machine, revocation is per-machine, and attribution is inherent. *No default proposed — this is a security/operational trade-off for the engineer.*

## Execution model — committed tooling that self-provisions each machine

Correction from review: **Claude can run the whole provisioning** — the `op` CLI creates the vault, generates the key, and `gh` registers the public key on GitHub; the developer approves each `op` write with their biometric at the moment it runs. So the deliverable is not a manual runbook but **committed dot-claude tooling** that provisions ANY of the three machines idempotently and safely, making rollout to Leandro/Emerson self-serve on their next session after they pull. Two artifacts:

- **A — the provisioner** (a dot-claude script/skill Claude runs with the dev present). One idempotent run does the full per-machine setup: create the per-machine vault `Git Automation - <tag>`, generate a fresh push-only key inside it, register the public half on GitHub via `gh`, create the 90-day Service Account, **pipe the token straight into the OS-native store in a single command so the value is never printed or read back** (Risk R6 / § Output Policy Layer 0), install the transient push wrapper + SSH-config `Host` routing. Re-running detects what already exists and skips it.
- **B — detection + guided migration** (a SessionStart/UserPromptSubmit hook + a confirm-gated migration in the provisioner). On a 4Shark dev machine not yet provisioned, the session surfaces a **benefit-framed** nudge — not "there is a change" but the payoff: *"if you run this migration, you stop having to approve 1Password every time it needs the git credential — no more per-push biometric prompt."* On the dev's confirmation Claude runs the provisioner, **finds the existing SSH key(s) used for 4Shark git, and — after an explicit "confirm I can migrate these" — moves them into the new vault and switches the wiring.** Backward-compatible by construction: until the dev confirms, **nothing changes and their current biometric git keeps working** — the committed change is INERT until opted into (Risk R7). This is what stops the commit from "locking" Leandro's or Emerson's machine.

### Phase 0 — Build artifact A: the idempotent provisioner
1. Author the provisioner (Pattern Priming applies — it is dot-claude tooling; read sibling scripts/skills first). Steps it performs, all idempotent: vault → fresh key → `gh` public-key registration → Service Account (`--expires-in 90d`, `--vault "Git Automation - <tag>:read_items"`) → token piped into the OS store (single command, never surfaced) → wrapper + SSH-config routing.
2. The wiring it installs (D2): a `core.sshCommand`/wrapper that sets `OP_SERVICE_ACCOUNT_TOKEN` **only for its own invocation** (Finding 12), materializes the key transiently via `op read` (`ssh-format=openssh`), releases it after; plus SSH config — 4Shark remotes → this key, `Host *` → the 1Password agent socket (Finding 13, live Touch ID preserved for everything else).

### Phase 1 — Build artifact B: detection + guided, confirm-gated migration
1. Detection hook (SessionStart/UserPromptSubmit): is this a 4Shark dev machine that is NOT yet provisioned? If so, surface the migration offer once, **benefit-framed** — lead with the payoff ("migrate and you stop approving 1Password on every git access"), not "there is a new config".
2. Migration path in the provisioner: discover the existing 4Shark git SSH key(s), present them, and migrate ONLY on explicit confirmation (the *"confirm I can migrate these"* gate). Until then, inert — existing git untouched (Risk R7).

### Phase 2 — Pilot on macOS (Paulo)
1. Run the provisioner end-to-end on the engineer's Mac.
2. Validate: `git push` on a throwaway branch completes with **no** biometric prompt; an unrelated 1Password/SSH op **still** prompts; `terraform apply` still prompts.

### Phase 3 — Self-serve rollout to Ubuntu & WSL
Leandro and Emerson pull; the detection flow offers migration on their next session; each confirms and is provisioned by the same tooling. One procedure, per-OS specifics:

| Machine | `op` binary | Token storage (D4) | Notes |
|---|---|---|---|
| macOS (Paulo) | native `op` | macOS Keychain | Full per-host `IdentityAgent` support (Finding 13). |
| Ubuntu (Leandro) | native `op` | Secret Service (libsecret/GNOME Keyring) | Same mechanism; per-host routing supported. Secret-Service ↔ `op` integration is our own choice, verify on setup (SPIKE flags it not independently verified). |
| Windows + WSL2 (Emerson) | **second, distinctly-named native Linux `op` inside WSL** | inside WSL | `/usr/local/bin/op` is reserved for the `op.exe`/Windows-Hello wrapper (`op-signin` skill) — the provisioner must NOT reuse that path (Finding 12 collision). All git/SSH runs natively in WSL2 (confirmed), so per-host routing IS available — Finding 14 does not apply. |

### Phase 4 — Lifecycle & documentation
1. Encode the 90-day cadence + per-dev re-issue + pre-expiry reminder (Risk R3); vaults/Service Accounts managed by the responsible-for-IT.
2. Write the revoke/rotate step: leak → revoke that machine's token + rotate its key, isolated to one machine (the D7 payoff). Decide whether it becomes a mapped runbook under `~/.claude/docs/runbooks/`.
3. Update `mapa-de-vaults-1password.md` to record the new machine-identity vault category (the three `Git Automation - <tag>` vaults), so the vault-tiering study stays the living source of truth.
4. Validate end-to-end from a real Claude Code Remote Control session (mobile): trigger `git push` while away from the Mac; confirm it completes with no local prompt.

## Risks

- **R1 — extracted-key exposure (inherent, bounded).** The git-push key is materialized outside the vault (Finding 11). Mitigations: transient materialization (D2), a **dedicated key used ONLY for pushing** (so its exposure never touches any other capability), vault scope bounding the token's reach to this one key (Finding 10). Recommend a fresh key, not reusing an existing multi-purpose one.
- **R2 — token at rest without biometric.** By design — "no human present" means something readable without biometric must exist locally. We bound it: scoped, expirable, revocable token in an OS secure store (D4/D5), never a global env export (Finding 12).
- **R3 — silent expiry stranding a remote push.** A token that expires mid-trip breaks the exact scenario this solves. Mitigation: D5 owner + cadence + a pre-expiry reminder.
- **R4 — WSL binary collision.** Reusing `/usr/local/bin/op` breaks the existing `op-signin` interactive flow. Mitigation: distinct path/name for the native Linux binary (Phase 3).
- **R5 — scope drift.** Someone later broadens the vault or reuses the token elsewhere. Mitigation: immutable scope (Finding 16) + D6 keeping the vault standalone and Console-UI-audited.
- **R6 — token value leaking into the session at creation.** `op service-account create` prints the token to stdout; a credential value must never enter session output (§ Output Policy Layer 0). Mitigation: the provisioner pipes the create output straight into the OS-native store in a single command, so the value never lands in a file, the session, or a Read — Claude never sees it. Treated as compromised + rotated if it ever surfaces anyway.
- **R7 — the committed rollout "locking" Leandro's / Emerson's machine.** The concern the engineer raised: merging this must NOT break the other devs' working git. Mitigation: the change is INERT until the dev explicitly confirms migration — before that, their existing biometric-agent git keeps working unchanged. Detection only *offers*; nothing switches without the *"confirm I can migrate these"* gate. Provisioner is idempotent, so a re-run or a partial run is safe.

## Out of scope (explicit)
- `terraform apply`, AWS console, and every other 1Password-gated secret — they KEEP the biometric agent unchanged. This plan touches the git-push path only.
- The 4 still-open service items from credential-hygiene (`Administrador Máquinas 4Shark`, `Setup 4Shark`, `Setup Authentication`, `Yubico API key`) — separate follow-up.
- Migrating vault membership to IaC/SSO — blocked by Teams Starter (recorded in the vault study), unchanged here.

## Decisions — all resolved (2026-07-06 review)
1. ~~**D1**~~ **Service Account.**
2. ~~**D2**~~ **Transient materialization.**
3. ~~**D3**~~ **Dedicated vault (`Git Automation`) + `read_items`; fresh dedicated key per dev.**
4. ~~**D4**~~ **OS-native secure store.**
5. ~~**D5**~~ **90-day expiry; each dev re-issues own token, vault/SA managed by responsible-for-IT.**
6. ~~**D6**~~ **Standalone TI-owned machine-identity vault.**
7. ~~**D7**~~ **One credential per developer.**
8. ~~**Emerson/WSL**~~ **All native in WSL2; Finding 14 does not apply.**

No open decisions remain — ready for task decomposition.
