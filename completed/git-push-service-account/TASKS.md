# TASKS — Non-interactive `git push` via per-dev 1Password Service Accounts

Derived from `PLAN.md` (all decisions resolved; execution model = committed tooling that self-provisions each machine). Executes D1 (Service Account), D7 (one credential per developer), D3 (fresh dedicated key), D2 (transient materialization), D4 (OS-native token store), D5 (90-day expiry), D6 (standalone TI-owned vault).

**Forced by D7 + Service-Account scoping:** a Service Account scopes to a **vault**, not an item (SPIKE Finding 10/16). Per-dev isolation therefore requires **one vault per machine** — a shared vault would let any dev's token read every dev's key. So: three vaults `Git Automation - <tag>`, three fresh keys, three tokens. Machine tags: `mac-paulo`, `ubuntu-leandro`, `wsl-emerson`.

**Two safety properties baked in:**
- **Token value never enters the session (R6 / Output Policy Layer 0):** `op service-account create` output is piped straight into the OS-native store in a single command — never printed, never written to a file, never Read back.
- **Committed rollout is inert until opted into (R7):** the change must not break Leandro's/Emerson's working git. Detection only *offers* migration; nothing switches without their explicit *"confirm I can migrate these"*. Until then their existing biometric-agent git keeps working.

Claude runs the provisioning (the dev approves each `op`/`gh` write with their biometric at the moment). Pattern Priming applies to all dot-claude tooling below — read sibling scripts/skills/hooks first.

---

## Phase 0 — Build artifact A: the idempotent provisioner (dot-claude tooling)

- [ ] **0.1** Pattern Priming: read sibling scripts (`~/.claude/scripts/*.sh`, e.g. `ruby.sh`, `setup-worktree.sh`) and the `op-signin` skill; confirm the shape before writing.
- [ ] **0.2** Provisioner performs, all **idempotent** (detect-and-skip on re-run), for a given `<tag>`:
  - create vault `Git Automation - <tag>` (standalone, TI-owned — D6);
  - generate a **fresh** ed25519 push-only key inside it (R1);
  - register the **public** half on GitHub via `gh`;
  - `op service-account create git-push-<tag> --expires-in 90d --vault "Git Automation - <tag>:read_items"`, **piping the token straight into the OS store in one command** (R6 — never surfaced);
  - install the wiring from 0.3.
- [ ] **0.3** Wiring the provisioner installs (D2): a `core.sshCommand`/wrapper that sets `OP_SERVICE_ACCOUNT_TOKEN` **only for its own invocation** (Finding 12 — never a global export), materializes the key transiently via `op read` (`ssh-format=openssh`), releases it after; plus SSH config — 4Shark remotes → this key, `Host *` → `IdentityAgent` at the 1Password socket (Finding 13, biometric preserved for everything else).
- [ ] **0.4** Per-OS branch inside the provisioner (see table under Phase 3): token store + `op` binary path (WSL uses a distinct native binary, NOT `/usr/local/bin/op`).

## Phase 1 — Build artifact B: detection + guided, confirm-gated migration

- [ ] **1.1** Detection hook (SessionStart / UserPromptSubmit): on a 4Shark dev machine NOT yet provisioned, surface the migration offer **once** (do not nag), **benefit-framed** — lead with the payoff: *"if you run this migration you stop having to approve 1Password every time it needs the git credential — no more per-push prompt."* Not "there is a new config."
- [ ] **1.2** Migration path: discover the existing 4Shark git SSH key(s), present them, migrate into the new vault + switch wiring **only** on the explicit *"confirm I can migrate these"* gate.
- [ ] **1.3** Prove inertness (R7): with the tooling committed but not yet confirmed, existing biometric-agent `git push` still works unchanged.

## Phase 2 — Pilot on macOS (Paulo)

- [ ] **2.1** Run the provisioner end-to-end on the Mac.
- [ ] **2.2** Validate: `git push` on a throwaway branch → **no** biometric prompt; an unrelated 1Password/SSH op → **still** prompts; `terraform apply` → still prompts.

## Phase 3 — Self-serve rollout to Ubuntu & WSL

Leandro and Emerson pull; the detection flow offers migration on their next session; each confirms and is provisioned by the same tooling. One procedure, per-OS specifics:

| Machine | `op` binary | Token store (D4) |
|---|---|---|
| `mac-paulo` | native `op` | macOS Keychain |
| `ubuntu-leandro` | native `op` | Secret Service (libsecret / GNOME Keyring) — verify `op`-readability at setup |
| `wsl-emerson` | **distinct native Linux `op`** (NOT `/usr/local/bin/op`) | inside WSL |

- [ ] **3.1** Leandro: confirm migration → provisioned → validate (as 2.2).
- [ ] **3.2** Emerson: confirm migration → provisioned → validate (as 2.2). Verify the distinct `op` path does not disturb the existing `op.exe` wrapper / `op-signin` flow.

## Phase 4 — Lifecycle & documentation

- [ ] **4.1** Encode 90-day cadence + per-dev re-issue + pre-expiry reminder (R3); vaults/Service Accounts managed by the responsible-for-IT.
- [ ] **4.2** Write the revoke/rotate step: leak → revoke that machine's token + rotate its key, isolated to one machine (D7 payoff). Decide if it becomes a mapped runbook under `~/.claude/docs/runbooks/`.
- [ ] **4.3** Update `~/.claude/plans/active/legal-compliance-documents/mapa-de-vaults-1password.md` with the new machine-identity vault category (the three `Git Automation - <tag>` vaults).
- [ ] **4.4** End-to-end from a real Remote Control session (mobile): `git push` while away from the Mac completes with no local prompt.

## Out of scope (unchanged)

- `terraform apply`, AWS console, every other 1Password-gated secret — biometric untouched.
- The 4 open credential-hygiene service items; vault-membership IaC/SSO (blocked by Teams Starter).

## Delivery note

The tooling (Phases 0–1) is a **dot-claude change** → per § Configuration Changes Policy it ships through the normal feature-branch → PR workflow on this working copy, not a direct edit to `~/.claude/`.
