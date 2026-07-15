# SPIKE — Safe remote (SSH) command execution by the agent

## Question

How should the session avoid ever running a **destructive, irreversible SSH command without a rollback**, WITHOUT blocking SSH (which is part of the daily 4Shark workflow — upgrading a Mongo node, restarting a service, migrating data)?

The trigger: the local-database guard in `validate-bash-command.sh` was matching `apt-get install <db>` / `systemctl restart <db>` substrings inside `ssh host "..."`, producing a false-positive block with the wrong ("local DB") message. The first fix attempt over-corrected — a hard `exit 2` on any `ssh` — which walls off SSH entirely and breaks the workflow. The engineer's actual requirement: SSH runs only WITH a plan; that cannot be enforced mechanically; the session must have the planning discipline in context every time an SSH command runs.

## Findings (sourced)

**Finding 1 — Gate by reversibility and blast radius, not by command type.**
The decision about whether an action needs a gate is context-dependent and *"is calculated fresh each time"* for actions whose impact depends on current state, routing by scope and reversibility rather than the command name.
Source: https://www.port.io/blog/human-in-the-loop-for-ai-coding-agents

**Finding 2 — Plan-then-execute is the protection against irreversible harm.**
*"the agent must formulate a comprehensive action strategy before implementing any steps"* — this temporal ordering *"contrasts with reactive approaches where agents execute actions then attempt recovery, which may prove impossible for certain destructive operations."*
Source: Del Rosario, Krawiecka, Schroeder de Witt — "Architecting Resilient LLM Agents: A Guide to Secure Plan-then-Execute Implementations", https://arxiv.org/pdf/2509.08646

**Finding 3 — Bare human approval is insufficient.**
Approval-in-front-of-everything fails two ways: people approve destructive commands without grasping the scope, and a gate reading stale/partial context "makes confident, wrong calls." The discipline has to be present in the session, not left to a rubber-stamped prompt.
Sources: https://www.port.io/blog/human-in-the-loop-for-ai-coding-agents ; search result summaries on human-in-the-loop guardrails.

**Finding 4 — Hooks are the deterministic vehicle for injecting this discipline.**
Agentic coding hooks are used as deterministic guardrails that add context/policy at the moment a tool runs. This matches 4Shark's existing `inject-*.sh` PreToolUse pattern (deployment-strategy, output-preservation, query-discipline).
Source: https://ranthebuilder.cloud/blog/agentic-coding-hooks-deterministic-ai-guardrails/

## Approach A — context injection (delivered, PR #388)

**Context injection, not a block.** A hook cannot read "is there a plan?" (judgment, not a fixed fact). So:

- **Do NOT block SSH.** `inject-remote-execution-context.sh` (PreToolUse / Bash) fires when the command's segment-leading token is `ssh`, injects the plan/rollback/backup discipline as `additionalContext`, and always exits 0. The command continues through the normal permission prompt (engineer in the loop).
- **The discipline injected**: (1) is there a plan and is every command understood? (2) is anything destructive/irreversible on the remote host, and if so is a backup/rollback in place FIRST — no rollback path is a Blocker; data-touching remote scripts use the three-script pre-flight/mutation/verification pattern of `SCRIPT-DISCIPLINE.md`; (3) uncertain how to do it safely → spike current community/vendor guidance first.
- **Matching precision**: `ssh` must be a segment-leading token followed by whitespace/end, so `ssh-add` / `ssh-keygen` / `sshpass` / `scp` and `ssh`-as-argument (`grep ssh file`) do not trip it; env-prefixed `AWS_PROFILE=x ssh ...` does.
- **The false positive that started this is fixed as a side effect**: the local-DB guard is unchanged and still governs the engineer's LOCAL machine; a remote `ssh host "apt-get install mongodb"` no longer hits it as a block — it gets the injected discipline instead.

## Verification

12 payloads run through the injector: every `ssh <host> "..."` (install / systemctl / df / -T / env-prefixed) INJECTS the discipline; `ssh-add`, `ssh-keygen`, `sshpass`, `scp`, `grep ssh`, `brew install jq`, `brew services start mongodb-community` stay silent. Nothing is blocked by the injector.

## Approach B — lock SSH, one wrapper binary per remote operation (engineer's proposal, PENDING DECISION)

Instead of leaving raw `ssh` reachable and relying on injected discipline (Approach A is *soft* — it depends on the agent + human following the plan/rollback discipline), **block raw `ssh` and expose one bounded wrapper per operation type**. The agent can only reach a remote host through a sanctioned wrapper — `remote-<operation>.sh <validated-params>` — and only those wrappers are allow-listed. SSH itself is locked.

This is the same reasoning 4Shark already applies to `ruby.sh`, `terraform.sh`, `hubflow.sh`, and `start-instance.sh`/`stop-instance.sh`: the wrapper is **bounded by construction** (fixed command shape, validated parameters, the dangerous/opaque form kept inside), which is exactly what makes a single broad allow-list entry safe. Extending that pattern to SSH: each wrapper can also bake the safety in mechanically — take the backup FIRST, run the operation, verify, and know the rollback — per operation type, so the discipline is enforced by code, not by memory.

### Prior art (for Approach B)

- **agent-callable (Evaneos)** — a **deny-by-default** CLI wrapper for LLM agents: *"The rule is simple: when in doubt, block."* Runs as a Claude Code PreToolUse hook (approved commands run silently; the rest hit the normal approval prompt) or as a standalone binary the agent prefixes. Per-tool policy (TOML for simple cases, Go for edge cases), grew out of `kubectl-readonly` / the `kubepolicy` engine. Covers 12+ CLI tools but **NOT ssh** — so it is a reusable *architecture and source*, not a drop-in. Its own disclaimer is the key caveat: *"This tool filters commands to reduce accidental side effects from LLM agents. It is not a sandbox, does not isolate processes, and a determined or creative agent may find ways around it."* → a client-side wrapper is a guardrail, not a security boundary. Source: https://github.com/Evaneos/agent-callable
- **SSH-native server-side lock** — `command=` in `authorized_keys` (forces one command regardless of what the client requests) + `ForceCommand` in `sshd_config` + the `SSH_ORIGINAL_COMMAND` variable a wrapper reads to validate the requested command against an allowlist. This is the OS-native, **server-side** enforcement: the remote host itself refuses anything but the sanctioned wrapper, which the agent cannot bypass. Sources (search-surfaced, page fetch 403'd — treat as directional, confirm before implementing): Baeldung "Restrict Commands for SSH Users", Virtono, oneuptime, the OpenSSH `sshd` / `authorized_keys` man pages.

### The two-layer insight

- **Client-side wrapper** (the 4Shark `*.sh` pattern, allow-list the wrapper + block raw `ssh`): guards against the *agent* picking a raw command — a guardrail, bypassable in principle by a creative agent (per agent-callable's disclaimer).
- **Server-side `ForceCommand`/`command=`**: the actual security boundary — enforced by the remote host, not bypassable from the client. Requires a change on every target host (via Ansible/Terraform), so it is more work.
- Strongest posture is **both**; the client-side wrapper alone is the cheaper, weaker version.

## Approach A vs B — trade-offs (for the engineer to decide)

| Dimension | A — context injection (delivered) | B — locked SSH + per-op wrappers (proposed) |
|---|---|---|
| Coverage | Any remote op, incl. novel/ad-hoc | Only operations someone built a wrapper for; a novel one-off has no wrapper → build one (friction) or it is blocked |
| Safety | Soft — relies on the agent + human following the injected discipline | Hard (client-side) / hardest (with server-side ForceCommand) — mechanically bounded per operation; backup-first can be baked in |
| Effort | Done — one hook | Enumerate every remote-op type + write/maintain a wrapper each + block raw `ssh` + (for real security) server-side ForceCommand on every host |
| Maintenance | ~none | Wrapper set must grow as new ops appear; a missing wrapper is friction, not danger |
| Bypass risk | The agent may just not follow the discipline | Client-side wrapper bypassable by a creative agent; server-side layer is not |

**Likely real answer — hybrid**: Approach B (hard wrappers + raw-`ssh` block) for the KNOWN recurring high-risk operations worth hardening, with Approach A (injected discipline) as the fallback for the long tail / ad-hoc. Whether to lock raw `ssh` entirely (every remote op must go through a wrapper, accepting the friction) or keep A as the fallback is the decision.

## Enumeration task (what "levantar todas as possibilidades" needs)

Before B can be built, enumerate the remote-operation TYPES 4Shark actually performs over SSH — each becomes a candidate wrapper. First cut to confirm/extend with the engineer:

- MongoDB node version upgrade (`apt-get` + stop + backup + upgrade + start + verify)
- Service restart / stop / start (`systemctl`) on a node
- Log / diagnostics fetch (read-only: status, `df`, `journalctl`, tail a log)
- Backup trigger / snapshot before a change
- Config file change on a node (with backup-first)
- Package install/upgrade generally (the riskiest — conflicts)

This enumeration is itself a work item; the list is the input to deciding how many wrappers B needs.

## Open questions for the engineer (decisions, not yet made)

1. **Lock raw `ssh` entirely (B-only)** — every remote op must go through a wrapper, accepting that a novel op needs a new wrapper first — **or hybrid** (B for known ops + A as the fallback)?
2. **Client-side wrapper only** (cheaper guardrail) **or also server-side `ForceCommand`/`command=`** on every host (the real boundary, needs Ansible/Terraform changes)?
3. **Confirm/extend the operation-type enumeration** above — which get a wrapper first.

## Status

- **Approach A — DELIVERED**: dot-claude PR #388 — `inject-remote-execution-context.sh` + settings.json wiring + `REMOTE-EXECUTION.md` + CLAUDE.md § Remote Command Execution + Tier 2 pointer + CHANGELOG. Non-blocking; SSH stays usable.
- **Approach B — PROPOSED, PENDING DECISION**: this spike captures the prior art, the two-layer (client/server) insight, the A-vs-B trade-offs, the enumeration task, and the open questions. No code written for B; it awaits the engineer's decision on the three questions above. A and B are compatible — B can be built on top of A later (hybrid) without undoing A.
