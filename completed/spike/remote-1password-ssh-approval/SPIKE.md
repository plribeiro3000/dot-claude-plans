# SPIKE — Remote/Mobile Approval of 1Password SSH Agent Biometric Prompts for Claude Code Remote Control

## Investigation question

Is there a configuration or architecture that lets the biometric/authorization approval for a
1Password SSH agent (and for other privileged operations such as `terraform apply`) be granted
from the remote/mobile side — approved from the phone — instead of requiring physical presence
at the Mac where the prompt renders? If direct remote approval is not possible, what are the
viable alternatives and their security trade-offs?

Concrete trigger: a Claude Code Remote Control session, driven from the mobile app while the
engineer was in another city, attempted `git push`. This triggered the 1Password Touch ID
authorization prompt on the physical Mac at home. The engineer had only the phone and could not
satisfy the prompt, so the push stalled.

## Sources consulted

- [1Password SSH agent security](https://developer.1password.com/docs/ssh/agent/security) — how the authorization prompt and process-to-key session model work
- [1Password SSH agent forwarding](https://developer.1password.com/docs/ssh/agent/forwarding/) — confirms the prompt always renders on the local 1Password app, even when the SSH client runs elsewhere
- [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/) — non-interactive, non-biometric authentication method for automation
- [1Password Community: "Forwarding biometric auth?"](https://www.1password.community/discussions/developers/forwarding-biometric-auth/151389) — official 1Password staff answer on whether biometric approval can be triggered/satisfied remotely
- [op-forward (GitHub, third-party tool)](https://github.com/ekovshilovsky/op-forward) — a community workaround for headless remotes borrowing a present host's Touch ID; shows the biometric gate cannot be removed, only relayed
- [Claude Code docs: Remote Control](https://code.claude.com/docs/en/remote-control) — where a Remote Control session actually executes, and the separate Trusted Devices biometric layer
- [Claude Code docs: Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) — the cloud-execution alternative and its GitHub-App-based credential model (no SSH keys involved)
- [Claude Code docs: Security](https://code.claude.com/docs/en/security) — explicit statement that Remote Control keeps all execution local, contrasted with cloud sessions
- [Claude Code docs: Desktop application (Dispatch)](https://code.claude.com/docs/en/desktop) — a second mobile-triggered mode with the same default local-execution behavior
- See auxiliary: `remote-1password-ssh-approval_doc_1.md` — verbatim 1Password developer-doc excerpts (SSH agent security, forwarding, Service Accounts)
- See auxiliary: `remote-1password-ssh-approval_doc_2.md` — verbatim Community thread excerpts and the op-forward tool's README, including one UNVERIFIED source (404 on direct fetch)
- See auxiliary: `remote-1password-ssh-approval_doc_3.md` — full verbatim Remote Control doc, including the Trusted Devices section and the "choose the right approach" comparison table
- See auxiliary: `remote-1password-ssh-approval_doc_4.md` — full verbatim Claude Code on the web, Security, and Desktop/Dispatch excerpts

## Findings

### Finding 1: The 1Password SSH agent authorization prompt binds a specific local process to a specific key — it is not a message that can be redirected to another device

**Evidence:**

> a session is established between the key and the process the SSH command was run from (a process can be a terminal window or tab, an IDE, or a GUI application, like a Git or SFTP client).

**Source:** [1Password SSH agent security](https://developer.1password.com/docs/ssh/agent/security) (`developer.1password.com/docs/ssh/agent/security`, 301-redirects to `www.1password.dev/ssh/agent/security`)

**Significance:** The prompt is not a generic "someone wants to use your key" notification — it is scoped to (a) the specific 1Password desktop app installation that holds the private key, and (b) the specific requesting process on that same machine. There is no message payload in this model that a different device (the phone) could intercept or answer on the Mac's behalf; the approval loop is local by construction, not by an incidental default setting.

### Finding 2: SSH agent forwarding does not solve the problem — the approval prompt still renders on the machine holding the 1Password app, never on the machine running the SSH client

**Evidence:**

> Instead of storing your private keys on the remote host, you can use SSH agent forwarding to forward your requests to your local 1Password SSH Agent.
>
> The 1Password app on your local machine should prompt you to authorize the request.

**Source:** [1Password SSH agent forwarding](https://developer.1password.com/docs/ssh/agent/forwarding/) (redirects to `www.1password.dev/ssh/agent/forwarding/`)

**Significance:** Forwarding changes *where the SSH client runs*, not *where the biometric check happens*. If the engineer's phone could somehow act as an SSH client forwarding to the Mac's agent, the prompt would still appear on the Mac — with nobody there to answer it. This directly rules out "just forward the agent to the phone" as a fix, and it is the same architectural reason a third-party tool like op-forward (Finding 5) cannot remove the requirement either.

### Finding 3: 1Password's official position (confirmed by staff) is that biometric authorization is local-host-only, with no cross-device remote-approval flow — the vendor's own answer to this exact class of question

**Evidence:**

Community member's question:

> Is there any way to make `op signin` trigger biometric authentication back to the machine I'm initiating the SSH from?

1Password staff (identified as "Phil") reply:

> Biometric auth is limited to the local host, but you can use Service Accounts (available via Family/Business Accounts) to provide access to a specific Vault and Item.

**Source:** [1Password Community: "Forwarding biometric auth?"](https://www.1password.community/discussions/developers/forwarding-biometric-auth/151389)

**Significance:** This is the closest direct answer available to the core research question, and it comes from 1Password staff rather than community speculation. The scoping caveat: the question is about `op signin` (CLI vault unlock), not the SSH agent's per-key authorization prompt specifically — but both are gated by the same local 1Password desktop process and the same OS biometric hook (Touch ID / Secure Enclave), so the same architectural answer applies to both. No 1Password feature discovered in this research — official docs, support articles, or community threads — offers "approve this desktop biometric prompt from my phone" for either case. The staff answer's own proposed alternative is not "approve remotely" but "stop requiring biometric approval at all for this flow" (Service Accounts — see Finding 4), which is a materially different trade-off than the one asked for.

### Finding 4: 1Password Service Accounts remove the biometric/interactive requirement entirely, rather than relocating it — explicitly designed to bypass MFA/SSO for automation

**Evidence:**

> Using a service account helps you implement the principal of least privilege and avoid the limitations of personal accounts (for example, SSO and MFA requirements).

**Source:** [1Password Service Accounts](https://developer.1password.com/docs/service-accounts/) (redirects to `www.1password.dev/service-accounts/`)

**Significance:** Service Accounts are 1Password's sanctioned answer for "no human present, no biometric possible" — but the mechanism achieves this by removing the live-approval boundary from the operation entirely, not by moving that boundary to the phone. A Service Account token, once issued, authorizes access to whatever vaults/items it is scoped to without a per-use human check. This is a fundamentally different security posture than "the engineer approves each push from the phone" — it is closer to "the engineer pre-approved a standing capability, once, when the token was created."

### Finding 5: Claude Code Remote Control executes entirely on the physical Mac — the mobile app is only a window into that local session, which is exactly why the Touch ID prompt appeared on the Mac and not the phone

**Evidence:**

> When you start a Remote Control session on your machine, Claude keeps running locally the entire time, so nothing moves to the cloud.
>
> Unlike Claude Code on the web, which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem. The web and mobile interfaces are just a window into that local session.

**Source:** [Claude Code docs: Remote Control](https://code.claude.com/docs/en/remote-control)

Corroborated in the Security doc:

> Remote Control sessions work differently: the web interface connects to a Claude Code process running on your local machine. All code execution and file access stays local ... No cloud VMs or sandboxing are involved.

**Source:** [Claude Code docs: Security](https://code.claude.com/docs/en/security)

**Significance:** This confirms the engineer's premise precisely. `git push` under Remote Control runs as a literal shell command on the Mac, using whatever SSH agent socket that Mac's shell environment points to — which is the 1Password agent, per the current 4Shark setup. The weekend incident is the expected behavior of this architecture, not a bug or misconfiguration: Remote Control was never designed to relocate execution, only to relocate the *steering interface*.

### Finding 6: A separate Claude-side biometric layer exists ("Trusted Devices") but authorizes a different thing — viewing/steering the session, not the 1Password SSH key

**Evidence:**

> Trusted Devices is an organization-wide setting that requires members to verify their device before they can view or steer Remote Control sessions from claude.ai, the Claude mobile apps, or Claude Desktop. It ties Remote Control access to a known device and a recent authentication, not just a signed-in account.
>
> Biometric checks run on the device through the operating system or browser, the same mechanism as passkey sign-in. Anthropic never receives or stores fingerprints, face data, or any other biometric information.
>
> The setting applies only to Remote Control. Regular Claude chat, Claude Code in the terminal, and API usage are unaffected.

**Source:** [Claude Code docs: Remote Control](https://code.claude.com/docs/en/remote-control) § Trusted Devices

**Significance:** This is worth flagging because it is easy to conflate with the engineer's problem: Trusted Devices does let the engineer confirm presence with the *phone's* Face ID/Touch ID. But that confirms "this is really you accessing the Claude session," which is Anthropic's account-security layer — it has no channel into 1Password and cannot satisfy 1Password's SSH-key authorization prompt on the Mac. Enabling it (Team/Enterprise only, off by default) would not change the outcome of the weekend incident.

### Finding 7: Claude Code on the web is architecturally a different execution model that avoids the SSH-agent problem altogether — because it does not use SSH keys or 1Password for git access at all

**Evidence:**

> Claude Code on the web runs tasks on Anthropic-managed cloud infrastructure at claude.ai/code. Sessions persist even if you close your browser, and you can monitor them from the Claude mobile app.
>
> For security, all GitHub operations go through a dedicated proxy service that transparently handles all git interactions. Inside the sandbox, the git client authenticates using a custom-built scoped credential. This proxy: Manages GitHub authentication securely: the git client uses a scoped credential inside the sandbox, which the proxy verifies and translates to your actual GitHub authentication token.

**Source:** [Claude Code docs: Claude Code on the web](https://code.claude.com/docs/en/claude-code-on-the-web) § GitHub proxy

Also relevant — cloud sessions explicitly cannot do interactive/biometric-style auth of any kind:

> Interactive auth like AWS SSO | No | Not supported. SSO requires browser-based login that can't run in a cloud session.

**Source:** same page, "What's available in cloud sessions" table

**Significance:** This is a structurally different answer to the underlying need (git operations while away from the Mac) rather than a fix to the Remote Control + 1Password combination. Cloud sessions authenticate to GitHub via a GitHub App / scoped-token proxy, never touching an SSH private key or 1Password at all. The trade-off is that the session is not "your Mac" — it runs in an Anthropic-managed VM with a fresh clone, no local MCP servers/tools/config unless committed to the repo, and (per the same doc) "a dedicated secrets store is not yet available," so any other secret the workflow needs (e.g. Terraform's AWS credentials) has no clean equivalent path yet.

### Finding 8: Dispatch (mobile-triggered tasks) defaults to the same local-execution model as Remote Control, with cloud/self-hosted-remote as an explicit alternate target

**Evidence:**

> Dispatch is a persistent conversation with Claude that lives in the Cowork tab. You message Dispatch a task, and it decides how to handle it.
>
> Environment: choose where Claude runs. Select Local for your machine, Remote for Anthropic-hosted cloud sessions, or an SSH connection for a remote machine you manage.

**Source:** [Claude Code docs: Desktop application](https://code.claude.com/docs/en/desktop)

The "choose the right approach" comparison table on the Remote Control doc lists Dispatch's execution target as "Your machine (Desktop)" by default.

**Source:** [Claude Code docs: Remote Control](https://code.claude.com/docs/en/remote-control) § Choose the right approach

**Significance:** Dispatch does not change the core finding — by default it has the identical local-execution property as Remote Control, so a Dispatch-triggered `git push` would hit the same Touch-ID-on-an-empty-house problem. Its "SSH connection (a remote machine you manage)" option is architecturally the same category as switching to a self-hosted remote environment with its own credential story (Service Account, deploy key, etc.) rather than the personal Mac's 1Password-backed SSH agent — it moves the execution host but does not, on its own, solve the biometric-delegation question.

### Finding 9: Even a purpose-built third-party forwarding tool cannot remove the local biometric requirement — it can only relay the request to the same local sensor

**Evidence:**

> Every privileged 1Password operation triggers biometric approval on the host. The proxy cannot bypass this.

**Source:** [op-forward (GitHub)](https://github.com/ekovshilovsky/op-forward)

**Significance:** op-forward solves a different, narrower problem than the engineer's (a headless remote machine borrowing Touch ID from a host where someone IS physically present to tap the sensor). Its own documentation is explicit that Touch ID approval on the host machine is not something the tool bypasses — it only tunnels the *request*, not the *approval*. This corroborates Findings 1–3 from an independent, non-1Password source: nobody in the ecosystem, official or community, has built a way to satisfy this prompt from a device other than the one showing it.

## Trade-offs surfaced

| Approach | What it enables | What it costs in the security model | Source |
|---|---|---|---|
| Do nothing (current setup) | Full presence-bound protection: every privileged action needs a live biometric at the Mac | Remote/mobile Claude Code sessions cannot complete `git push`, `terraform apply`, or any other 1Password-key-gated action while the engineer is away from the Mac | Findings 1, 2, 3, 5 |
| 1Password Service Accounts scoped to the git-push flow | Non-interactive git authentication for a Remote Control (or Dispatch) session — no Touch ID needed, works from anywhere the phone can reach the session | Removes the per-action biometric gate for whatever the Service Account token is scoped to; the token becomes a standing credential rather than a one-time approval, and its blast radius is whatever vaults/items it is scoped to | Finding 4 |
| Claude Code on the web (cloud execution) | Push/PR creation happens through Anthropic's GitHub-App-based credential proxy — no SSH key or 1Password agent involved at all | The session is not the engineer's Mac: no local MCP servers/tools/config unless committed to the repo, no dedicated secrets store yet for anything beyond GitHub (e.g. AWS/Terraform creds), and interactive/SSO auth is unsupported in-cloud | Finding 7 |
| Defer/queue privileged operations | The remote session prepares the change (commit, plan) and the engineer completes the privileged step (push, apply) later at the Mac with live biometric | Preserves the full current security boundary unchanged; costs turnaround time — the remote session cannot finish end-to-end while the engineer is away | Findings 1–3 (no evidence a native "queue for later" feature exists in Claude Code or 1Password for this purpose — not verified) |
| SSH agent forwarding from a remote host back to the Mac | None found | Does not solve anything for this scenario — the prompt still renders on the Mac with nobody there; it would only help if a *different* trusted person were physically at the Mac | Finding 2 |
| Split biometric requirement per operation class (e.g., git yes, terraform no; or vice versa) | Lets the engineer tune which operations are blocked from remote/mobile use vs which get a lighter-weight credential (e.g., Service Account) | Requires deciding, per operation class, whether presence-bound approval is essential (this is a judgment call the SPIKE does not make) | Not independently sourced — inferred from Finding 4's scoping capability ("You control which vaults and Environments are accessible") |

## What remains uncertain

- **Not verified**: whether 1Password has any private/enterprise-tier feature (beyond what public docs and community threads surfaced) that supports cross-device biometric delegation for the SSH agent specifically. The official staff answer (Finding 3) is the strongest available evidence and it says no, but it is one community-forum reply, not an exhaustive product-line audit.
- **Not verified**: whether a native "prepare now, approve later" queuing mechanism exists inside 1Password's SSH agent (e.g., a request that persists until answered, satisfiable from a queue rather than an immediate live prompt) — no such feature was found in the docs consulted, and this SPIKE does not conclude it does not exist, only that it was not found.
- **Not verified**: the exact shell/SSH-agent-socket wiring on the engineer's Mac (e.g., whether `SSH_AUTH_SOCK` is explicitly pointed at the 1Password agent via `.zshrc`/`.envrc` or via the 1Password app's own shell integration) — this SPIKE treated the 4Shark-documented setup ("all SSH keys live in 1Password... 1Password SSH agent is configured with biometric approval turned ON") as given, per the task's instruction to treat it as the premise, not something to re-derive from the local machine.
- **One community source (`1password.community/discussion/140898`) returned HTTP 404 on direct fetch** and is marked UNVERIFIED in `remote-1password-ssh-approval_doc_2.md` — its content is not used to sustain any Finding above.
- Whether the engineer's Terraform `apply` flow (also gated by 1Password, per the setup description) has any Remote-Control-specific consideration beyond what applies to `git push` was not separately investigated — the underlying mechanism (a local process requesting a local 1Password-held key/credential) is architecturally the same, so Findings 1–5 are expected to apply equally, but this was not independently confirmed against 4Shark's specific Terraform + 1Password wiring.

## Options for the engineer

- **Option A — Keep the current model, accept that remote/mobile sessions cannot finish privileged operations.** The remote session does everything up to the privileged step (edits, commits locally, prepares a plan) and stops there; the engineer finishes the push/apply once physically at a machine with the biometric sensor. Preserves the full current security guarantee. Deciding question: is the engineer willing to trade "finish everything from the phone" for "prepare everything from the phone, finish later"?

- **Option B — Issue a narrowly-scoped 1Password Service Account for the specific credential(s) the remote/mobile flow needs (e.g., a git-push-capable SSH key, or a deploy key), and configure the Remote Control session's shell environment to use it instead of the personal 1Password agent for that operation.** Removes the per-action biometric prompt for whatever is scoped into that Service Account. Deciding question: is a standing, non-biometric credential (issued once, used repeatedly without live approval) an acceptable trade against a per-action live approval, for this specific operation class — and can the scope be drawn tightly enough (e.g., one vault, one key) that a compromised phone/session cannot pivot beyond it?

- **Option C — Switch the mobile workflow from Remote Control to Claude Code on the web for tasks that need to complete a `git push`/PR while away from the Mac.** The cloud session authenticates to GitHub through Anthropic's own GitHub-App-based proxy, never touching 1Password or an SSH key. Deciding question: is losing the local environment (no local MCP servers/tools/config unless committed to the repo, no clean secrets story yet for non-GitHub credentials like AWS/Terraform) acceptable for the subset of tasks that are pure git/GitHub work — and does the engineer want two different mobile workflows (Remote Control for most things, Web for git-completion tasks) or a single one?

- **Option D — Split the biometric requirement by operation class rather than an all-or-nothing choice.** For example: keep live biometric approval mandatory for `terraform apply` (higher blast radius, infrequent, usually planned in advance) while granting a scoped Service Account or deploy key for `git push` (higher frequency, lower blast radius per push, already protected by branch/PR review). Deciding question: does the engineer agree with that specific risk ranking (git push materially lower-stakes than terraform apply), and where exactly should the line be drawn across the rest of the privileged-operation surface (AWS console actions, other secrets)?

No option above restores "approve the Mac's Touch ID prompt from the phone" as the engineer originally framed it — the evidence gathered (Findings 1–3, 9, from both 1Password's own docs/staff and an independent third-party tool) indicates that specific capability does not exist today, in any product or workaround found. Every option instead changes some other part of the equation: where the operation executes, what credential it uses, or when in time the privileged step happens.

---

## Deep dive — 1Password Service Accounts for the remote git-push flow

The engineer chose to pursue Option B/D (Service-Account-backed, non-biometric `git push`;
biometric stays live for `terraform apply`, AWS console actions, and other secrets) across three
machines: macOS, Leandro's Ubuntu, and Emerson's Windows+WSL2. This section verifies the concrete
mechanics rather than accepting the plan's mental model at face value.

### Sources consulted (deep dive)

- [Use service accounts with 1Password CLI](https://developer.1password.com/docs/service-accounts/use-with-1password-cli) — what commands a Service Account token can and cannot drive
- [Get started with 1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started) — token creation, scoping, expiration
- [1Password Service Account security](https://developer.1password.com/docs/service-accounts/security) — token protection, rotation, revocation
- [1Password SSH agent — Get started](https://developer.1password.com/docs/ssh/get-started/) — SSH agent prerequisites (desktop app sign-in, no Service Account path)
- [1Password Community: service accounts + regular accounts in the same environment](https://www.1password.community/discussions/developers/how-to-use-service-accounts-and-regular-accounts-in-the-same-environment/97657) — official staff answer on coexistence
- [1Password SSH agent — Advanced use cases](https://developer.1password.com/docs/ssh/agent/advanced/) — running the 1Password agent alongside another SSH agent, per-host `IdentityAgent` routing, Windows limitation
- [1Password WSL integration](https://developer.1password.com/docs/ssh/integrations/wsl/) — official WSL SSH-agent path (Windows-desktop-app-gated)
- [`op read` command reference](https://developer.1password.com/docs/cli/reference/commands/read/) — the actual mechanism that extracts key material non-interactively
- [1Password load-secrets-action (GitHub)](https://github.com/1Password/load-secrets-action) — `ssh-format` extraction pattern used in CI/CD
- [GitHub Docs: Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys) — the non-1Password alternative for git-push specifically
- `~/.claude/commands/op-signin.md` (internal 4Shark source) — the existing WSL2/`op.exe` wiring already in place on Emerson's machine class
- See auxiliary: `remote-1password-ssh-approval_doc_5.md` — Service Account mechanics, limitations, and the coexistence-conflict community thread
- See auxiliary: `remote-1password-ssh-approval_doc_6.md` — the `op read`/GitHub Action key-extraction pattern, agent coexistence/`IdentityAgent` routing, and the WSL integration docs plus 4Shark's own `op-signin` wiring
- See auxiliary: `remote-1password-ssh-approval_doc_7.md` — GitHub deploy keys as a non-1Password alternative

### Finding 10 (THE CRUX): A 1Password Service Account does not, and architecturally cannot, drive the SSH agent — it is a completely separate mechanism from the biometric-gated agent the engineer wants to keep for everything else

**Evidence:**

The full list of `op` CLI commands confirmed to work with a Service Account token: `op read`,
`op inject`, `op run`, `op vault create`, plus `op item` and `op document` management. There is no
SSH-agent-specific subcommand in this list, and there is no SSH-agent-specific subcommand in the
product at all — the agent is a background process started and controlled by the 1Password
desktop app, not something the `op` CLI drives.

**Source:** [Use service accounts with 1Password CLI](https://developer.1password.com/docs/service-accounts/use-with-1password-cli) (redirects to `www.1password.dev/service-accounts/use-with-1password-cli`)

Independently, the SSH agent's own prerequisites never mention a Service Account as an
authentication option:

> Sign up for 1Password [and] Install and sign in to 1Password for Mac/Windows/Linux

**Source:** [1Password SSH agent — Get started](https://developer.1password.com/docs/ssh/get-started/) (redirects to `www.1password.dev/ssh/get-started/`)

**Significance:** This directly answers the engineer's first, most load-bearing question. The
engineer's mental model — "the fingerprint-per-push only happens because the key lives in
1Password; swap in a Service Account and the same SSH-agent-based push stops prompting" — is not
how the two mechanisms relate. The 1Password SSH agent (the thing that shows the Touch ID prompt)
is a desktop-app feature tied to a signed-in personal/team account. A Service Account is a
completely separate `op` CLI/SDK authentication mode that never touches the SSH agent. Getting a
non-interactive `git push` therefore does not mean "point the existing SSH agent at a Service
Account" — it means using a different mechanism entirely for that operation (Findings 11–13
below). This is not a failure of the plan; it just means the plan's mechanism needs to change,
not its goal.

**Verification block:** URL fetched (`developer.1password.com/docs/service-accounts/use-with-1password-cli` → `www.1password.dev/service-accounts/use-with-1password-cli`, and `developer.1password.com/docs/ssh/get-started/` → `www.1password.dev/ssh/get-started/`) / Verbatim quote checked / Quote substrings confirmed present in both fetch passes and preserved in `remote-1password-ssh-approval_doc_5.md`.

### Finding 11: The actual non-interactive path is extracting the raw private key material out of 1Password with `op read`, then handing it to a standard (non-1Password) SSH mechanism — the opposite of "the private key never leaves 1Password"

**Evidence:**

> op read --out-file ./key.pem op://app-prod/server/ssh/key.pem

> op read "op://app-prod/ssh key/private key?ssh-format=openssh"

**Source:** [`op read` command reference](https://developer.1password.com/docs/cli/reference/commands/read/) (redirects to `www.1password.dev/cli/reference/commands/read`)

Corroborated by 1Password's own GitHub Action for CI/CD, which uses the identical pattern:

> When loading SSH keys, you can specify the format using the `ssh-format` query parameter. This is useful when you need the private key in a specific format like OpenSSH.

**Source:** [1Password load-secrets-action](https://github.com/1Password/load-secrets-action)

**Significance:** This is the honest, load-bearing answer to "what IS the non-interactive
mechanism, then." A Service Account authorizes `op read` (and `op run`/`op inject`) to pull the
plaintext private key value out of the vault — either to a file (`--out-file`) or into a process's
memory/environment (`op run`). That key then either sits on disk (to be loaded into a standard
OpenSSH `ssh-agent` with `ssh-add`, or referenced directly via `IdentityFile`) or is injected
per-invocation. This is architecturally the opposite of the 1Password SSH agent's own stated
guarantee for the interactive path — "Your private keys never leave 1Password, are never stored
locally" (see Finding 1 area / `remote-1password-ssh-approval_doc_1.md`). Choosing Option B
necessarily means the git-push key, specifically, stops enjoying that "never leaves 1Password"
property. That is not a defect in the research — it is the actual shape of the trade-off the
engineer is asking to make, and it should be stated in exactly these terms so the decision is
informed.

**Verification block:** URL fetched (`developer.1password.com/docs/cli/reference/commands/read/`) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_6.md`. Second URL fetched (`github.com/1Password/load-secrets-action`) / Verbatim quote checked / Quote substring confirmed present in the same auxiliary file.

### Finding 12: A Service Account token and a signed-in personal account cannot both be active in the same process environment — by 1Password's explicit design — which is the actual coexistence mechanism the engineer needs to plan around

**Evidence:**

> Indeed it is not possible to use a user account with a service account token in the environment. This is by design, as we intend the service accounts credentials to only exist within the scope of their usage.

**Source:** [1Password Community: service accounts + regular accounts in the same environment](https://www.1password.community/discussions/developers/how-to-use-service-accounts-and-regular-accounts-in-the-same-environment/97657), official reply attributed to 1Password staff member Horia Culea

Suggested mitigation, from the same reply:

> you could use an envvar with a different name (e.g. having the token exported as `OP_SERVICE_ACCOUNT_TOKEN_GLOBAL`) and move its value to `OP_SERVICE_ACCOUNT_TOKEN` at the beginning of the scripts

**Significance:** This is the concrete answer to "coexistence — can git use a Service Account
while everything else on the same machine still uses the biometric agent?" The collision is
narrower than it first sounds: it is a per-process-environment collision inside the `op` CLI's own
credential resolution, not a machine-wide lock. Practically, this means: never `export
OP_SERVICE_ACCOUNT_TOKEN` in a login shell's global profile (`.zshrc`, `.bashrc`) if the engineer
also wants that same shell's `op` CLI invocations to keep working against the personal account.
The token should be scoped to exactly the invocation that needs it — a dedicated wrapper script, a
`git` credential/`core.sshCommand` helper, or a subshell — consistent with 1Password staff's own
suggested workaround. This research found no separate statement, official or community, that
setting `OP_SERVICE_ACCOUNT_TOKEN` in a shell also disrupts the independently-running 1Password
SSH agent background process (which is a desktop-app-owned daemon, not something that reads this
env var) — that absence of a stated conflict is treated here as a plausible-but-not-confirmed
"no interference," not as a verified guarantee.

**Verification block:** URL fetched (`www.1password.community/discussions/developers/how-to-use-service-accounts-and-regular-accounts-in-the-same-environment/97657`) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_5.md`.

### Finding 13: On macOS and Linux, the 1Password SSH agent officially supports running alongside a different SSH agent, with per-host routing — the mechanism that lets git use one credential path while everything else keeps using the biometric agent

**Evidence:**

> The 1Password SSH agent can run alongside another SSH agent, like the OpenSSH agent.

Example config for selective 1Password usage per host:

```
Host raspberry-pi
  IdentityAgent ~/.1password/agent.sock
Host ec2-server
  IdentityFile ~/.ssh/ssh-key-not-on-1password.pem
```

**Source:** [1Password SSH agent — Advanced use cases](https://developer.1password.com/docs/ssh/agent/advanced/) (redirects to `www.1password.dev/ssh/agent/advanced/`)

**Significance:** This is the official, sanctioned mechanism for exactly the coexistence the
engineer wants — a `Host github.com` (or a dedicated host alias for 4Shark's git remotes) block
pointing at a standard OpenSSH agent (or a directly-referenced `IdentityFile`) loaded from a key
extracted via a Service-Account-scoped `op read`, while `Host *` (or every other host) keeps
`IdentityAgent` pointed at the 1Password socket, preserving live Touch ID for everything else —
Terraform's underlying SSH usage (if any), other git remotes not carved out, and any other SSH
target. This confirms the coexistence the engineer's plan assumes is architecturally sound on
macOS and Linux, via SSH config, not via anything Service-Account-specific.

**Verification block:** URL fetched (`developer.1password.com/docs/ssh/agent/advanced/` → `www.1password.dev/ssh/agent/advanced/`) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_6.md`.

### Finding 14: Windows does not have the same per-host flexibility — the 1Password SSH agent occupies a single fixed pipe for all hosts — but this constraint applies to the Windows host, not to WSL2 itself

**Evidence:**

> Windows doesn't have the same flexibility with the `~/.ssh/config` file as macOS and Linux, because Microsoft OpenSSH listens to a fixed pipe.

**Source:** [1Password SSH agent — Advanced use cases](https://developer.1password.com/docs/ssh/agent/advanced/)

**Significance:** For Emerson's machine, the actual `git push` work happens inside the WSL2 Linux
environment, not directly on the Windows host — so the per-host `IdentityAgent` routing available
on Linux (Finding 13) is available to him inside WSL, even though it would not be available if he
were running `ssh`/`git` directly from Windows PowerShell/cmd. This constraint becomes relevant
only if any part of the 4Shark workflow runs git or SSH directly from the Windows side rather than
from within WSL — this SPIKE did not find evidence either way about whether that happens in
4Shark's actual usage and flags it as something to confirm with Emerson directly, not something
resolved by public documentation.

**Verification block:** URL fetched (same as Finding 13) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_6.md`.

### Finding 15: 4Shark's existing WSL2 setup already routes the interactive/biometric path through `op.exe` and Windows Hello — a Service-Account-based git path would need its own, separate `op` binary, not the same wrapper path

**Evidence:**

> The 1Password Windows Subsystem for Linux (WSL) integration allows you to authenticate SSH and Git commands and sign your Git commits within WSL using the 1Password SSH agent running on your Windows host.

**Source:** [1Password WSL integration](https://developer.1password.com/docs/ssh/integrations/wsl/) (redirects to `www.1password.dev/ssh/integrations/wsl/`)

4Shark's own documented wiring for this exact pattern:

> `/usr/local/bin/op` is a wrapper script that forwards all `op` commands to `op.exe` (the Windows binary) via WSL interop. Because execution happens on the Windows side, the 1Password desktop app authenticates via Windows Hello — no master password or session token required.

**Source:** `~/.claude/commands/op-signin.md` (internal 4Shark repository file, read directly)

**Significance:** This confirms Emerson's machine already implements the official, biometric-gated
WSL pattern for the interactive account — good, that is exactly the path that should keep working
unchanged for `terraform apply` and everything else. But it also means `/usr/local/bin/op` is
already reserved, on his machine, for the `op.exe`/Windows-Hello wrapper. A Service Account only
needs `OP_SERVICE_ACCOUNT_TOKEN` plus any `op` CLI binary — official 1Password docs describe
installing a native Linux `op` binary inside WSL as a normal, independent installation path,
unrelated to the Windows-forwarding wrapper. Reusing the same `/usr/local/bin/op` path for both
purposes would recreate exactly the collision described in Finding 12. The clean approach is a
second, distinctly-named `op` binary (native Linux, e.g., at a different path) invoked only by the
git-push-specific script/tooling with `OP_SERVICE_ACCOUNT_TOKEN` scoped to that invocation, leaving
`/usr/local/bin/op` (the `op.exe` wrapper) untouched for the interactive/biometric flows the
`op-signin` skill already manages.

**Verification block:** URL fetched (`developer.1password.com/docs/ssh/integrations/wsl/` → `www.1password.dev/ssh/integrations/wsl/`) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_6.md`. Internal file `~/.claude/commands/op-signin.md` read directly (not a web fetch) / Verbatim quote checked against the file's actual line 30–32 content.

### Finding 16: 1Password does not prescribe a specific secure-storage mechanism for a Service Account token on a developer workstation — it explicitly places that responsibility on the operator

**Evidence:**

> It's up to you to save and protect the service account token.

**Source:** [1Password Service Account security](https://developer.1password.com/docs/service-accounts/security) (redirects to `www.1password.dev/service-accounts/security`)

Token lifecycle capabilities that do exist:

> You can rotate or revoke service account tokens.
>
> op service-account create <serviceAccountName> --expires-in <duration> --vault <vault-name:<permission>,<permission>>

**Source:** same page, and [Get started with 1Password Service Accounts](https://developer.1password.com/docs/service-accounts/get-started)

**Significance:** There is no official 1Password guidance to cite for "store the token in macOS
Keychain" / "store it in the Secret Service API on Linux" / "store it in Windows Credential
Manager" — those are generic OS-level secure-storage mechanisms, not something this research found
1Password specifically recommending for this use case. What IS confirmed and citable: the token
can be created with a bounded lifetime (`--expires-in`) and can be rotated or revoked at any time,
which bounds the exposure window of a leaked token independent of where it is stored. Any
per-OS storage recommendation in the cross-platform section below is this SPIKE's own generic
secure-secret-storage reasoning, not a 1Password-documented recommendation — flagged accordingly.

**Verification block:** URL fetched (`developer.1password.com/docs/service-accounts/security/` → `www.1password.dev/service-accounts/security`) / Verbatim quote checked / Quote substring confirmed present in `remote-1password-ssh-approval_doc_5.md`.

### Finding 17: A GitHub deploy key is a materially simpler, non-1Password alternative for the git-push case specifically — but a write-enabled deploy key is not automatically scoped down to "push only," and it carries its own distinct risks

**Evidence:**

> An SSH key that grants access to a single repository. GitHub attaches the public part of the key directly to your repository instead of a personal account, and the private part of the key remains on your server.
>
> Deploy keys only grant access to a single repository.
>
> Deploy keys are usually not protected by a passphrase, making the key easily accessible if the server is compromised.
>
> Deploy keys are credentials that don't have an expiry date.

**Source:** [GitHub Docs: Managing deploy keys](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys)

**Significance:** A deploy key sidesteps 1Password (and the Service-Account/`op read` extraction
step) entirely — it is a plain SSH key pair, public half registered on the specific GitHub repo,
private half placed directly on the machine that needs to push. This is simpler to set up per
repository than provisioning a Service-Account-scoped vault item and scripting `op read`, but it
trades away 1Password's vaulting, rotation tooling, and audit trail (Finding 16) — GitHub's own
docs flag that deploy keys "don't have an expiry date" and are "usually not protected by a
passphrase," i.e., GitHub does not provide the token-lifecycle hygiene 1Password's Service Account
model does (Finding 16). Whichever mechanism supplies the key, 4Shark's own branch-protection
convention (force-push to `develop`/`master` blocked; see 4Shark `CLAUDE.md` § Git Safety) and
GitHub's branch protection rules apply to the resulting push independent of which credential
authenticated it — this is not a 1Password-specific protection, it sits at the git-hosting layer
and is unaffected by the choice between a Service-Account-extracted key and a deploy key.

**Verification block:** URL fetched (`docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys`) / Verbatim quote checked / Quote substrings confirmed present in `remote-1password-ssh-approval_doc_7.md`.

### Coexistence, concretely: what changes and what stays the same

Combining Findings 10–15 into the shape of the actual setup, if the engineer proceeds with a
Service-Account-backed git-push credential:

1. **What stays exactly as-is:** the 1Password desktop app, signed into the personal/team
   account, running the SSH agent with biometric approval turned on, for every host and every
   operation NOT explicitly carved out. `terraform apply` and any other 1Password-gated secret
   keep the current live-approval behavior untouched.
2. **What is new:** one 1Password Service Account, created with a narrow vault scope (ideally one
   vault holding only the git-push-capable key, nothing else), a bounded `--expires-in` lifetime,
   and `write_items` only if the token itself will ever need to rotate the key it manages (a
   read-only `read_items` scope is sufficient if the key is provisioned once and only read
   thereafter).
3. **What is new, mechanically:** a script/wrapper — not a global shell export — that sets
   `OP_SERVICE_ACCOUNT_TOKEN` only for its own invocation, calls `op read` (with `--out-file` or
   piped into `ssh-add`) to materialize the private key, and an SSH config `Host` block (or a
   per-repo `core.sshCommand`) that points ONLY the relevant git remotes at that
   separately-loaded key/agent — leaving `Host *` (or every other host) pointed at the 1Password
   agent socket as today.
4. **What is a genuinely new exposure, not a repackaging of the old one:** for the specific
   git-push key, "private key never leaves 1Password" (the interactive path's own stated
   guarantee) stops being true — Finding 11. The key material will exist, at least transiently, on
   disk or in a process's memory outside the 1Password vault. This is the actual price of removing
   the biometric prompt for this operation, and it is worth the engineer weighing explicitly
   against the "git push is low-stakes, protected by branch rules/PR review anyway" reasoning that
   motivated Option B in the first place (Finding 17's closing point: the git-hosting-layer
   protections apply regardless of which key mechanism is chosen, but the 1Password-vaulting
   protection specifically does not survive the Service-Account/`op read` path).

### Cross-platform provisioning — per machine, marking which parts are sourced vs this SPIKE's own reasoning

| Machine | Sourced facts | This SPIKE's own reasoning (not independently sourced) |
|---|---|---|
| macOS (engineer) | Native `op` CLI + Service Account token via `OP_SERVICE_ACCOUNT_TOKEN` (Finding 10, `doc_5`); `op read --out-file`/`ssh-format` extraction (Finding 11, `doc_6`); coexistence via scoped env var, not global export (Finding 12, `doc_5`); per-host `IdentityAgent` routing officially supported (Finding 13, `doc_6`) | Token storage: macOS Keychain is a generic, well-known secure-storage primitive for a secret like this — NOT a 1Password-specific recommendation (Finding 16 explicitly notes no such recommendation was found) |
| Ubuntu (Leandro) | Same `op` CLI + Service Account mechanism (Findings 10–12 are platform-agnostic, `doc_5`); per-host `IdentityAgent` routing officially supported on Linux (Finding 13, `doc_6`) | Token storage: the Secret Service API (`libsecret`/GNOME Keyring) is the closest Linux analogue to Keychain — again, generic OS practice, not a 1Password recommendation; not independently verified as integrable with `op` CLI's token-reading flow in this research pass |
| Windows + WSL2 (Emerson) | Official WSL integration is the biometric/Windows-Hello-gated path via `op.exe` (Finding 15, `doc_6`); Windows lacks per-host `IdentityAgent` flexibility at the Windows-host level (Finding 14, `doc_6`); 4Shark's existing `op-signin` skill already reserves `/usr/local/bin/op` for the `op.exe` wrapper (Finding 15, internal source); a native Linux `op` binary in WSL is an official, independent installation path | Recommend (not sourced, this SPIKE's own inference from Finding 15) installing the native Linux `op` binary at a distinctly different path than `/usr/local/bin/op` specifically so it never collides with the existing wrapper, and scoping `OP_SERVICE_ACCOUNT_TOKEN` only inside the git-push script's own environment, never exported in the interactive shell profile that also runs `op-signin`'s interactive flow |

### Trade-offs surfaced (deep dive)

| Approach | What it enables | What it costs in the security model | Source |
|---|---|---|---|
| Service Account + `op read`-extracted SSH key, scoped SSH config `Host` block for git only | No biometric prompt for `git push` from any Remote Control/Dispatch session; biometric stays live for everything else via the same 1Password agent, on the same machine | The extracted private key exists outside the 1Password vault (on disk or in process memory) for the git-push flow specifically — the "never leaves 1Password" guarantee is given up for that one key; token lifecycle (rotation/revocation/expiry) must be managed deliberately since 1Password does not prescribe secure storage | Findings 10, 11, 12, 13, 16 |
| GitHub deploy key (no 1Password involvement for this key at all) | Simpler per-repo setup, no `op` scripting needed, no Service Account to provision | No 1Password vaulting, audit trail, or built-in rotation tooling; GitHub's own docs note no expiry date and typically no passphrase; a write-enabled deploy key is as powerful as a full collaborator, not inherently "push-only" | Finding 17 |
| Keep git on the biometric 1Password SSH agent; do not introduce a Service Account or deploy key at all | No new credential to manage, no new exposure surface | Returns to the original Option A/pre-decision state — remote/mobile sessions cannot complete `git push` while away from the Mac | Findings 1–5 (original section) |

### Open decisions for the engineer

- **Service-Account-extracted key vs. a plain GitHub deploy key for the git-push credential itself.** Both remove the biometric prompt; they differ in whether the key lives inside 1Password's vaulting/rotation/audit system (Service Account) or entirely outside it (deploy key). Deciding question: does the team want this credential inventoried and rotatable through the same 1Password tooling as everything else, or is a simpler, GitHub-native deploy key acceptable for this one narrow case?
- **Exact vault/item scope for the Service Account, if chosen.** Findings 10–12 confirm scoping is possible and immutable once created (a new Service Account must be created to change scope). Deciding question: one dedicated vault holding only the git-push key(s), or a broader existing vault — and `read_items` only, or `write_items` too (needed only if the token will itself rotate the key)?
- **Where the extracted key/token lives on disk, per OS, and who is responsible for its file permissions and cleanup.** Finding 16 confirms 1Password does not prescribe this. Deciding question: does 4Shark want a written, version-controlled setup script per OS (macOS/Ubuntu/WSL) so all three machines end up provisioned identically, given `op read --out-file` and `--file-mode` are the concrete primitives available (Finding 11, `doc_6`)?
- **Whether any 4Shark workflow runs git/SSH directly from the Windows side of Emerson's machine (outside WSL).** Finding 14 flags that Windows lacks the per-host `IdentityAgent` routing available on macOS/Linux; if all git/SSH work already happens inside WSL, this constraint does not bite, but the SPIKE could not confirm this either way from Emerson's Windows/WSL boundary and did not treat it as automatically no.
- **Naming/placement of the second `op` binary on Emerson's WSL machine so it does not collide with the existing `/usr/local/bin/op` → `op.exe` wrapper.** Finding 15 and 4Shark's own `op-signin` skill establish the existing reservation; deciding question: what path and invocation convention keeps the two unambiguous for future engineers reading the setup (e.g., the git-push wrapper script calling a fully-qualified path to the native Linux binary rather than relying on `PATH` order)?
- **Token expiration cadence.** Service Account tokens can be created with `--expires-in <duration>` (Finding 10/16). Deciding question: what rotation cadence does the team want for this specific token, and who owns re-issuing it before expiry so `git push` does not silently start failing for whoever is remote at that moment?

As with the first round of options, this deep dive surfaces mechanisms and their exact trade-offs
without picking among them — the evidence is clear on how each piece works and what it costs; it
does not decide, for 4Shark, whether the git-push key should live inside or outside 1Password's
vaulting system, nor exactly how tightly to scope it.
