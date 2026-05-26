# SPIKE — AI Agent Permission Control: Command Safety, Approval Fatigue, and Isolation Strategies

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-13
**Status:** Research complete — pending decisions

---

## Goal

Investigate how the industry is approaching AI agent permission control for coding assistants, with focus on three specific problems identified in 4Shark's workflow:

1. **Command chaining opacity** — AI agents concatenate multiple commands with `&&`, making human review ineffective because only the first command is visible in the approval prompt
2. **Approval fatigue** — constant permission prompts lead to rubber-stamping, defeating the purpose of human-in-the-loop oversight
3. **Infrastructure command safety** — AI agents bypass established patterns (e.g., `terraform plan` without `-out`, piped into `grep`) losing output and requiring re-execution

The broader question: **What are the available approaches to control AI agent command execution, and what are the tradeoffs of each?**

---

## Method

- Web research across academic papers, industry reports, vendor documentation, and engineering blogs (2025–2026)
- Analysis of frameworks from Anthropic, OpenAI, Docker, Meta, AWS, OWASP, and MIT
- Cross-referencing with 4Shark's current whitelist-based approach

---

## Evidence

### 1. The Three Approaches in the Market

The industry has converged on three distinct approaches to AI agent safety. Each has different tradeoffs. No single approach dominates — most mature organizations combine elements of all three.

#### Approach A: Permission-Based Control (Whitelist / Human-in-the-Loop)

**Who uses it:** 4Shark (current), most Claude Code users in default mode, enterprise teams

**How it works:** Every command requires explicit approval. A whitelist defines what auto-approves; everything else prompts the user. The human is the security boundary.

**Evidence:**
- Claude Code's default mode requires permission before modifications or commands. Safe operations like `echo` and `cat` auto-approve; most actions need explicit approval. ([Anthropic Engineering Blog](https://www.anthropic.com/engineering/claude-code-sandboxing))
- OWASP AI Agent Security Cheat Sheet recommends: "Grant agents the minimum tools required for their specific task" and "Require explicit approval for high-impact or irreversible actions." Actions are categorized by risk level (LOW, MEDIUM, HIGH, CRITICAL), with automatic approval only for low-risk read operations. ([OWASP Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html))
- AWS Agentic AI Security Scoping Matrix defines four scopes. Scope 2 (Prescribed Agency) = "Human approval required for all actions." This is where 4Shark currently operates. ([AWS Security Blog](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/))

**Strengths:**
- Maximum control — every action is visible and approvable
- No infrastructure investment required
- Works with any tool, any environment
- Auditable — the human made the decision

**Weaknesses:**
- **Approval fatigue is real and measured.** Anthropic found that Claude Code users approve 93% of permission prompts. Over time, users stop reading what they're approving. ([Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode))
- **Command chaining defeats the model.** When an agent sends `cmd1 && cmd2 && cmd3 && ... && cmd8`, the human sees a wall of text. Only the first command gets read. This is exactly the scenario 4Shark identified — the eighth command failed, nobody noticed until the error appeared.
- **Velocity cost.** Every prompt is an interruption. In a 30-minute session, dozens of approvals fragment the developer's attention.
- **False sense of security.** "Thirty approvals later, you're rubber-stamping everything without reading it. This is approval fatigue, and it's a security problem disguised as a safety feature." ([Docker Blog](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/))

#### Approach B: Sandbox / Isolated Environment ("Let It Break")

**Who uses it:** OpenAI Codex (default), Docker Sandboxes, E2B, Northflank, teams with disposable environments

**How it works:** The agent runs inside an isolated environment (microVM, container, or OS-level sandbox) with its own filesystem, network, and kernel. The agent can do anything inside the sandbox — install packages, delete files, run Docker — because the host is untouched. If something breaks, destroy the sandbox and start fresh.

**Evidence:**
- OpenAI Codex runs entirely in isolated cloud containers. Internet access is disabled during agent execution. Dependencies are installed in a setup phase (with network), then the agent runs offline. ([OpenAI Codex Security](https://developers.openai.com/codex/security))
- Docker Sandboxes use microVMs (not containers) — each sandbox gets its own kernel, Docker daemon, filesystem, and network. "Unlike containers that share the host kernel, each sandbox has its own kernel." ([Docker Blog](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/))
- Anthropic's sandboxing uses OS-level primitives (Linux bubblewrap, macOS Seatbelt) for filesystem and network isolation. Internal measurement: **sandboxing reduces permission prompts by 84%.** ([Anthropic Engineering Blog](https://www.anthropic.com/engineering/claude-code-sandboxing))
- The philosophy: "Once you accept that agents will misread context or hallucinate, the design goal changes — you stop trying to make the model perfectly safe and focus on blast radius through containment." ([Lushbinary](https://lushbinary.com/blog/ai-agent-security-autonomous-coding-production-guide/))

**Strengths:**
- Eliminates approval fatigue entirely — agent works autonomously
- Blast radius is contained by definition — worst case, destroy and rebuild
- Higher velocity — no interruptions
- Works well for code changes (reviewable via git diff after the fact)

**Weaknesses:**
- **Requires infrastructure investment.** MicroVMs, container orchestration, environment replication — this is not free.
- **Does not solve the infrastructure command problem.** A sandboxed agent running `terraform apply` against a real AWS account is still dangerous — the sandbox contains the agent's local filesystem, not the cloud resources it manages.
- **Review shifts to post-hoc.** Instead of approving each command, the developer reviews the final diff. This is better for code but worse for side effects (installed packages, config changes, network calls).
- **Environment fidelity.** The sandbox must replicate the real development environment closely enough that the agent's work is transferable. Drift between sandbox and real environment causes rework.
- **Not viable for 4Shark's current scale.** Setting up disposable environments for each AI session requires DevOps investment that exceeds the current pain point.

#### Approach C: Model-Based Classification (Auto Mode / AI Reviewing AI)

**Who uses it:** Anthropic (Claude Code Auto Mode, March 2026), research teams

**How it works:** A separate classifier model reviews each tool call before execution. Safe actions proceed automatically; risky actions are blocked or escalated to human review. The classifier is blind to the agent's reasoning (to resist prompt injection) and uses a two-stage filter: fast single-token check, then chain-of-thought reasoning if flagged.

**Evidence:**
- Claude Code Auto Mode uses a Sonnet 4.6 classifier that evaluates each action before execution. Three tiers: (1) Read-only tools auto-pass, (2) In-project file edits bypass classifier (reviewable via VCS), (3) High-risk actions (shell commands, external calls) go through classifier. ([Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode))
- Performance metrics: **0.4% false-positive rate** (benign actions blocked), **17% false-negative rate** (dangerous actions that slip through). ([Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode))
- "Not a drop-in replacement for careful human review on high-stakes infrastructure." ([Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode))
- Blocked categories include: force-pushes, mass deletions, data exfiltration, disabling logging, credential scanning, production deploys, modifying shared resources. ([Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode))

**Strengths:**
- Reduces approval fatigue while maintaining a safety net
- Can detect dangerous patterns that humans miss (the 8th command in a chain)
- Adapts to context — learns routine workflows
- Middle ground between full control and full autonomy

**Weaknesses:**
- **17% false-negative rate means dangerous commands get through.** For infrastructure commands, this is unacceptable.
- **Struggles with ambiguous intent.** "Clean up the PR" doesn't explicitly authorize `git push --force`, but a classifier might allow it.
- **Adds latency and cost.** Every tool call goes through a second model evaluation.
- **Opaque decision-making.** The developer doesn't know why something was allowed or blocked without investigating.
- **New attack surface.** The classifier itself can be targeted by adversarial inputs.

### 2. Key Frameworks and Research

#### Meta's "Rule of Two" ([Meta AI Blog](https://ai.meta.com/blog/practical-ai-agent-security/))

An agent must satisfy **no more than two** of three properties in a single session:
- **[A]** Processing untrustworthy inputs
- **[B]** Access to sensitive systems or private data
- **[C]** Ability to change state or communicate externally

If an agent reads untrusted data **[A]** and has access to production **[B]**, it must NOT be able to make changes **[C]** without human validation. This framework directly addresses the command chaining problem: a chained command that reads external data AND modifies state AND accesses sensitive resources violates the Rule of Two.

#### AWS Agentic AI Security Scoping Matrix ([AWS Security Blog](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/))

Four scopes of increasing autonomy:
| Scope | Agency | Autonomy | Human Role |
|-------|--------|----------|------------|
| 1 — No Agency | Read-only | Human-initiated | Direct control |
| 2 — Prescribed Agency | Limited actions | Human approval required | Gatekeeper |
| 3 — Supervised Agency | Broad actions | Autonomous after initiation | Supervisor |
| 4 — Full Agency | Self-initiating | Strategic oversight only | Observer |

Key principle: **"Greater autonomy should be earned through ongoing evaluation."** Organizations should expand agent autonomy progressively based on demonstrated performance, not grant it by default.

4Shark currently operates at Scope 2. The command chaining problem is a Scope 2 failure — the agent bypasses human approval by bundling multiple actions into a single approval prompt.

#### MIT 2025 AI Agent Index ([MIT AI Agent Index](https://aiagentindex.mit.edu/))

Documented 30 deployed AI agents across 1,350 fields. Key findings:
- **25/30 agents disclose no internal safety results**
- **23/30 have no third-party safety testing**
- User approval mechanisms are implemented "selectively based on task risk levels"
- The industry is still in early stages of standardizing safety features

#### International AI Safety Report 2026 ([International AI Safety Report](https://internationalaisafetyreport.org/publication/international-ai-safety-report-2026))

"AI agents could compound reliability risks because they operate with greater autonomy, making it harder for humans to intervene before failures cause harm." Recommends human-in-the-loop control with structured autonomy levels.

### 3. The Command Chaining Problem Specifically

This is the specific issue 4Shark identified. The evidence shows it's a recognized problem but **no vendor has a clean solution yet.**

**What happens:**
- Agent sends: `cmd1 && cmd2 && cmd3 && ... && cmdN`
- Human approval prompt shows the full string
- Human reads the first command, mentally validates it, approves
- Commands 2–N execute without meaningful review
- If command N fails or does something unexpected, it's only caught after the fact

**Why agents do it:**
- Efficiency — fewer round trips to the approval system
- Context — the agent plans a sequence of related steps and wants to execute them atomically
- Training — models are trained on shell workflows where `&&` chaining is normal

**The Terraform variant:**
- Agent runs `terraform plan | grep "something"` instead of `terraform plan -out=file`
- The plan output is consumed by `grep` and lost
- If `grep` doesn't find what it expected, the plan must be re-run
- The human approved the compound command without realizing the plan output wouldn't be saved

**What the research says:**
- OWASP recommends: "Validate agent outputs before execution." But this is about output validation, not command structure validation.
- The "atomic operations" pattern from multi-agent research applies: "Break work into atomic user stories or tasks, each small enough to fit in one AI session and having unambiguous pass/fail criteria." ([Addy Osmani](https://addyosmani.com/blog/self-improving-agents/))
- No specific paper or framework addresses `&&` chaining in shell commands as a safety problem. The closest is the Sequential Tool Attack Chaining (STAC) research, which studies "sequences of seemingly innocuous tool calls that individually pass safety checks but collectively achieve harmful goals." ([arXiv](https://arxiv.org/html/2510.23883v1))

### 4. The "Blast Radius" Formula

Multiple sources converge on the same formula:

> **Blast Radius = Access Scope × Operating Velocity × Detection Window**

- **Access Scope**: What can the agent touch? (files, cloud resources, databases)
- **Operating Velocity**: How fast does it act? (milliseconds per command)
- **Detection Window**: How long before a human notices? (seconds if watching, hours if not)

The command chaining problem maximizes all three: broad access (whatever the shell can do), maximum velocity (all commands execute in sequence), and minimal detection (the human approved the batch).

---

## Conclusions

### Finding 1: There Is No Silver Bullet

No single approach solves the problem completely. The market is not converging on one solution — it's converging on **layered defense**. Every serious framework (OWASP, Meta, AWS, Anthropic) recommends combining multiple approaches.

### Finding 2: 4Shark's Current Approach (Whitelist) Is Correct But Incomplete

The whitelist/permission model is the right foundation for 4Shark's scale and infrastructure. The sandbox approach requires DevOps investment that doesn't match the current pain point. The auto-mode classifier is too new and has a 17% false-negative rate that is unacceptable for infrastructure commands.

However, the whitelist approach has a **structural weakness in command chaining** that must be addressed at the policy level, not at the infrastructure level.

### Finding 3: The Command Chaining Problem Is a Policy Gap, Not a Technology Gap

The fix is not a new tool or sandbox — it's a rule in the agent's instructions:

1. **One command per approval.** The agent must never chain commands with `&&`, `||`, `;`, or pipes (`|`) when the command requires approval. Each command must be a separate tool call.
2. **Exception for read-only chains.** Chaining read-only commands (e.g., `grep | head`) is acceptable because the blast radius is zero.
3. **Infrastructure commands must be atomic and save output.** `terraform plan` must always use `-out=`. `curl` must always save to `/tmp/`. No piping infrastructure output into text processing.

### Finding 4: Approval Fatigue Is the Real Enemy

The 93% approval rate measured by Anthropic means the permission system is functionally a rubber stamp. 4Shark should:

1. **Reduce the number of prompts** by expanding the whitelist for truly safe operations (read-only file operations, linters, test runners)
2. **Make remaining prompts high-signal** by ensuring each prompt is for a genuinely risky action
3. **Keep the human review where it matters** — infrastructure commands, git operations, file deletions

### Finding 5: Progressive Autonomy Is the Industry Direction

AWS's framework ("greater autonomy should be earned through ongoing evaluation") aligns with 4Shark's current trajectory. The path is:

1. **Today (Scope 2)**: Whitelist + policy rules against chaining → fix the acute problem
2. **Near-term**: Expand whitelist aggressively for safe operations → reduce fatigue
3. **Medium-term**: Evaluate Claude Code Auto Mode when false-negative rates improve → selective automation of approval
4. **Long-term**: Sandbox environments for non-infrastructure work → full autonomy within containment

### Finding 6: The Terraform Problem Is Universally Recognized

"The most dangerous command you can give an AI: terraform apply" — this is not unique to 4Shark. The industry consensus is: **never give an AI agent direct infrastructure write access without a human gate.** The plan-then-approve pattern that 4Shark already uses is the recommended approach. The gap is enforcement (the agent sometimes skips `-out=`), not strategy.

---

## Next Steps

### Immediate (Policy Changes — No Infrastructure Required)

1. **Add "no command chaining" rule to CLAUDE.md** — Prohibit `&&`, `||`, `;` in commands that require approval. Each command must be a separate tool call. Read-only pipes are exempt.
2. **Audit and expand the whitelist** — Identify commands that always get approved and add them to the auto-approve list. Reduce prompt volume to make remaining prompts meaningful.
3. **Reinforce Terraform rules** — Add explicit examples of prohibited patterns (`terraform plan | grep`) alongside the existing `-out=` requirement.

### Short-term (Configuration Changes)

4. **Evaluate Claude Code Auto Mode** — Test in a controlled environment to measure false-negative rate against 4Shark's specific command patterns. If the 17% rate applies mostly to edge cases we don't hit, it may be viable for non-infrastructure commands.
5. **Add hooks for command validation** — Use Claude Code's hook system to reject chained commands at the tool level, before they reach the human for approval.

### Medium-term (Architecture Decision)

6. **Decide on sandbox strategy** — If AI usage grows significantly, evaluate Docker Sandboxes or similar for code-only sessions (no infrastructure access). This would be a PLAN.md, not a spike.

---

## Sources

### Academic / Research

- [The 2025 AI Agent Index — MIT](https://aiagentindex.mit.edu/) — Documented safety features of 30 deployed AI agents
- [International AI Safety Report 2026](https://internationalaisafetyreport.org/publication/international-ai-safety-report-2026) — Comprehensive AI safety analysis
- [Agentic AI Security: Threats, Defenses, Evaluation, and Open Challenges — arXiv](https://arxiv.org/html/2510.23883v1) — Includes STAC (Sequential Tool Attack Chaining)
- [2025 AI Safety Index — Future of Life Institute](https://futureoflife.org/ai-safety-index-summer-2025/)

### Industry Frameworks

- [OWASP AI Agent Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html) — Tool permissions, least privilege, risk classification
- [Meta — Agents Rule of Two](https://ai.meta.com/blog/practical-ai-agent-security/) — No more than two of: untrusted input, sensitive access, state change
- [AWS Agentic AI Security Scoping Matrix](https://aws.amazon.com/blogs/security/the-agentic-ai-security-scoping-matrix-a-framework-for-securing-autonomous-ai-systems/) — Four scopes of agency/autonomy
- [Databricks AI Security Framework (DASF v3.0)](https://www.databricks.com/blog/agentic-ai-security-new-risks-and-controls-databricks-ai-security-framework-dasf-v30)

### Vendor Documentation

- [Anthropic — Claude Code Sandboxing](https://www.anthropic.com/engineering/claude-code-sandboxing) — 84% prompt reduction, OS-level isolation
- [Anthropic — Claude Code Auto Mode](https://www.anthropic.com/engineering/claude-code-auto-mode) — Classifier-based approvals, 93% approval rate, 17% false-negative
- [OpenAI — Codex Security](https://developers.openai.com/codex/security) — Isolated cloud containers, offline agent execution
- [OpenAI — Codex Agent Approvals](https://developers.openai.com/codex/agent-approvals-security)
- [Docker — Sandboxes for Coding Agents](https://www.docker.com/blog/docker-sandboxes-run-claude-code-and-other-coding-agents-unsupervised-but-safely/) — MicroVM approach
- [Docker — A New Approach for Coding Agent Safety](https://www.docker.com/blog/docker-sandboxes-a-new-approach-for-coding-agent-safety/)

### Engineering Blogs

- [The Most Dangerous Command You Can Give an AI: terraform apply](https://medium.com/@premchandak_11/the-most-dangerous-command-you-can-give-an-ai-terraform-apply-57b44a5e2ff9) — Infrastructure safety
- [The Agent Approval Fatigue Problem — Molten.Bot](https://molten.bot/blog/agent-approval-fatigue/) — "Clicking Yes to Everything"
- [AI Coding Agents Security for Java Teams — Markus Eisele](https://www.the-main-thread.com/p/ai-coding-agents-security-java-blast-radius) — Blast radius analysis
- [Self-Improving Coding Agents — Addy Osmani](https://addyosmani.com/blog/self-improving-agents/) — Atomic operations pattern
- [AI Coding Agent Security — DEV Community](https://dev.to/maxkrivich/ai-coding-agent-security-practical-guardrails-for-claude-code-copilot-and-codex-och)
- [AI Agent Security — Lushbinary](https://lushbinary.com/blog/ai-agent-security-autonomous-coding-production-guide/) — Blast radius formula

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
