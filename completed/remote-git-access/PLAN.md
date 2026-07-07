# PLAN — GitHub git-push SSH key on disk (personal, opt-in)

**Status:** ✅ DONE on Paulo's macOS (2026-07-06). **Created:** 2026-07-06. **Simplified:** 2026-07-06 (dropped the team-enforcement machinery — see below).

**Executed (Paulo / macOS):** fresh git-only key `~/.ssh/github` (ed25519, no passphrase; registered on GitHub as `github-mac-m2`, fingerprint `SHA256:6teYcROu…bLY`); `~/.ssh/config` `Host github.com` block now carries `IdentityFile ~/.ssh/github` + `IdentitiesOnly yes`, so github.com uses the on-disk key instead of the 1Password agent. `ssh -T git@github.com` authenticated as `plribeiro3000` with **no biometric prompt**. Remote/mobile `git push` now works.

**Go-forward rule ratified:** the key is the developer's general GitHub key (all their GitHub sources, not only 4Shark) — named simply `github`. For every OTHER service that needs a key, create a NEW dedicated key rather than reusing one. The old GitHub key material stays on the machine for history (in case an old, forgotten service still relies on it); it is removed from GitHub as rotation hygiene (manual, engineer-side).

**End-to-end confirmed (2026-07-06):** pushed `HEAD` to a throwaway remote branch on `git@github.com:4shark/dot-claude.git` and deleted it — push authenticated via `~/.ssh/github` over SSH, no biometric prompt, no residue.

**Old key dropped from GitHub (2026-07-06):** rotation complete. The old private key stays on the machine / in 1Password for history, so its public half can be regenerated (`ssh-keygen -y -f <old-private-key>`) and re-registered anytime if a forgotten service still needs it. Nothing left to do.

**Anchored on:** `~/.claude/plans/active/spike/credential-risk-classification/SPIKE.md` (the SSH-key inventory — GitHub is the only git-style key; infra keys stay biometric) and `~/.claude/plans/completed/git-push-service-account/PLAN.md` (why the Service-Account path was dropped — Teams Starter).

## The solution (final, deliberately simple)

Take the **GitHub git-push SSH key out of the 1Password biometric agent and keep it only on disk** (`~/.ssh`, `0600`), used for `github.com` via SSH config. `git push` then works from a remote/mobile Claude Code Remote Control session with no biometric prompt. Everything else is untouched.

That is the whole change. No new tooling, no team rollout.

## What was dropped, and why (the engineer's call)

The earlier version of this plan built a `provision-git-access` skill + a blocking PreToolUse hook + a cross-machine rollout to force the same setup on all three engineers. **Dropped as over-engineering:**

- This is **personal and opt-in**. The engineer wants the key on disk to use Remote Control (work from a phone). Leandro and Emerson are not doing Remote Control, so forcing them to move their key out of 1Password solves a problem they do not have.
- The others keep their GitHub key in 1Password if they prefer the extra security. If either ever wants the on-disk setup, the same four commands (below) are the whole procedure — documented, available, not enforced.
- No dot-claude code change is needed for the core solution — it is a per-machine `~/.ssh` change plus doc updates.

## Decisions (all resolved 2026-07-06)

- **Mechanism:** GitHub key on disk, out of the 1Password agent (Service Accounts unavailable on Teams Starter; Business upgrade not justified; the elaborate on-disk-provisioning machinery not worth it).
- **Which key:** ONLY the GitHub git-push key. `kp-4shark` (infra SSH to Mongo/Windows/VPN boxes), `4Shark-key`, VPN PIN, AWS MFA, the Terraform ENV bundle → unchanged, biometric/machine-bound. (Redis/Atlas/Rollbar are API tokens, not SSH keys; Codeship/Heroku retired.)
- **Granularity:** account-level GitHub SSH key (all repos), not per-repo deploy keys.
- **Fresh vs export:** a **fresh git-only key generated on disk** is the clean path — it never requires exporting existing private-key material through any channel, and scopes the on-disk key to git only. (Exporting the existing key via the 1Password app UI is an alternative if the engineer wants to keep the same public key already on GitHub; not via `op read`, which would surface the private value.)
- **Enforcement:** none. Personal, opt-in.

## Accepted trade-off (stated plainly)

Once the GitHub key is on disk, it is **no longer behind the 1Password biometric gate**. Someone with physical access to the unlocked machine can `git push` as the engineer. This is accepted: git push is bounded by branch protection + PR review (force-push/deletion to `develop`/`master` blocked), and the whole point is to enable remote work. The high-blast-radius credentials that would justify the biometric gate all stay in 1Password.

## Governing rule (still stands as the principle behind this)

*A developer-workstation credential is MACHINE-BOUND (biometric, in 1Password) when a mistake/compromise with it is not fully reversible through an existing control AND recovery needs full keyboard/tooling at the machine. It is REMOTE-ABLE (on disk) when the mistake is bounded and reversible.* The GitHub git-push key is REMOTE-ABLE; every other inventoried credential is MACHINE-BOUND.

## Execution

- **Step 1 — inspect current state** (engineer runs; `~/.ssh` is denied to the agent's sandbox): `ls -la ~/.ssh` and `cat ~/.ssh/config`, so the exact SSH-config edit is correct (append a `Host github.com` block, or replace an existing one that points at the 1Password agent).
- **Step 2 — put a git-only key on disk + route github.com to it** (four commands, engineer runs): generate a fresh ed25519 key, `gh ssh-key add` its public half, add the `Host github.com` → `IdentityFile` + `IdentitiesOnly yes` block, `ssh -T git@github.com` to confirm no prompt. Then a real `git push` on a throwaway branch end-to-end.
- **Step 3 — confirm the biometric boundary is intact** for everything else (an unrelated 1Password/SSH op still prompts; `terraform apply` still prompts).
- **Step 4 — docs:** record the on-disk GitHub key as an intentional, opt-in per-engineer choice in `~/.claude/plans/active/legal-compliance-documents/mapa-de-vaults-1password.md` (one line), and keep the governing rule above as the documented principle.

## Out of scope

- Any change to Leandro's / Emerson's machines (opt-in only).
- `kp-4shark` / `4Shark-key` classification, the Terraform ENV item structure, the `op` 10-minute CLI-session window — separate follow-ups, none block this.
