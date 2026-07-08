# Auxiliary source — Sandbox environment choices, Security page, Remote Control

All fetched 2026-07-07.

---

## Source A: https://code.claude.com/docs/en/sandbox-environments

Compare-sandboxing table (relevant rows):

| Approach | What is isolated | Requires Docker | Setup effort |
|---|---|---|---|
| Virtual machine | Full operating system | No | High |
| Claude Code on the web | Full operating system, hosted by Anthropic | No | None; requires a Claude subscription and GitHub |

> Isolation also does not change what is sent to the model. Your prompts and the files Claude reads are transmitted to the Anthropic API or your configured provider with or without a sandbox. See [Data usage](/en/data-usage) for what Claude Code sends and how to reduce it.

> ## Claude Code on the web
> [Claude Code on the web](/en/claude-code-on-the-web) runs each session in an isolated, Anthropic-managed virtual machine. A network proxy enforces a default allowlist, and a separate proxy holds your GitHub token outside the sandbox while issuing scoped credentials for repository access inside it.
>
> Use this approach when you want full VM isolation without provisioning infrastructure yourself, or when you are delegating tasks from a device that does not have a local development environment.

> Use this approach when you are evaluating untrusted code, when your security policy requires kernel-level separation between the agent and the host, or when no host-level approach meets your compliance requirements.

**Significance**: Anthropic's own comparison table frames "Claude Code on the web" purely as an *isolation-from-the-host* mechanism (protects the engineer's machine from untrusted code), not as a compliance/data-residency control. It is listed alongside local VM/container options as one point on an isolation spectrum — the doc never claims cloud-sandbox isolation is equivalent to, or a substitute for, data-residency/compliance controls.

---

## Source B: https://code.claude.com/docs/en/security — "Cloud execution security"

> When using Claude Code on the web, additional security controls are in place:
> * **Isolated virtual machines**: Each cloud session runs in an isolated, Anthropic-managed VM
> * **Network access controls**: Network access is limited by default and can be configured to be disabled or allow only specific domains
> * **Credential protection**: Authentication is handled through a secure proxy...
> * **Branch restrictions**: Git push operations are restricted to the current working branch
> * **Audit logging**: All operations in cloud environments are logged for compliance and audit purposes
> * **Automatic cleanup**: Cloud environments are automatically terminated after session completion

**Note**: this "Automatic cleanup ... terminated after session completion" phrasing is *looser* than the more detailed `claude-code-on-the-web` doc, which says the environment is reclaimed only "after a period of inactivity" and that reopening a session restores "your conversation history" — i.e. termination of the VM/compute is not the same claim as deletion of the underlying session data. The Security page does not reconcile this distinction; the Data Usage doc's retention numbers (30-day standard / no ZDR for this surface) are the more precise source of truth for how long session data is retained (see `anthropic_doc_2_data-usage-retention.md`).

> [Remote Control](/en/remote-control) sessions work differently: the web interface connects to a Claude Code process running on your local machine. All code execution and file access stays local, and the same data that flows during any local Claude Code session travels through the Anthropic API over TLS. No cloud VMs or sandboxing are involved.

---

## Source C: https://code.claude.com/docs/en/remote-control

> Remote Control connects claude.ai/code or the Claude app... to a Claude Code session running on your machine. ... When you start a Remote Control session on your machine, Claude keeps running locally the entire time, so nothing moves to the cloud.

> Unlike Claude Code on the web, which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem. The web and mobile interfaces are just a window into that local session.

> Your local Claude Code session makes outbound HTTPS requests only and never opens inbound ports on your machine. When you start Remote Control, it registers with the Anthropic API and polls for work. When you connect from another device, the server routes messages between the web or mobile client and your local session over a streaming connection.

> All traffic travels through the Anthropic API over TLS, the same transport security as any Claude Code session. The connection uses multiple short-lived credentials, each scoped to a single purpose and expiring independently.

**Significance**: Remote Control is architecturally identical to local CLI usage from a data-handling perspective — Anthropic's servers relay control-plane messages (steering/monitoring) but files and execution never leave the engineer's machine. This is the mode the engineer described as "phone/web is just a control surface."
