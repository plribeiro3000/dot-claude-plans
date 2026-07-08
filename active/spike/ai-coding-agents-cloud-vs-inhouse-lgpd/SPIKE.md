# SPIKE — AI Coding Agents: Cloud-Hosted Execution/Storage vs In-House, for an LGPD-Bound PII Processor

## Investigation question

4Shark handles client PII and is bound by LGPD. The engineer draws a sharp distinction between two categories of Claude Code usage:

- **Acceptable**: data sent to Anthropic purely for inference — tokens in, tokens out, ephemeral, no persistence.
- **Questionable / possible dealbreaker**: cloud-hosted sessions ("Claude Code on the web", Anthropic-managed VMs/sandboxes) where *generated files and client data* live on storage Anthropic controls and 4Shark does not, based on a retention *claim* ("we wipe sandboxes every N days") that is not independently auditable.

The engineer's hypothesis to test: serious engineering orgs handling real PII do **not** run coding agents on vendor-controlled cloud storage — they keep persisted execution/storage in-house and use the cloud only for inference traffic. Fly-by-night AI startups are the ones putting everything in the cloud; mature teams keep to inference-only.

This spike answers, with cited evidence: (1) precisely how each Claude Code mode handles data, (2) what Anthropic's actual commercial/API terms vs cloud-sandbox terms say, (3) what the market/community evidence shows about the hypothesis, (4) what specifically satisfies LGPD here, and (5) the option space for 4Shark, without recommending one.

## Sources consulted

- https://code.claude.com/docs/en/claude-code-on-the-web — cloud-sandbox architecture, session lifecycle, security/isolation. See auxiliary `anthropic_doc_1_claude-code-on-the-web.md`.
- https://code.claude.com/docs/en/data-usage — training policy, retention periods, local vs cloud data flow. See auxiliary `anthropic_doc_2_data-usage-retention.md`.
- https://platform.claude.com/docs/en/manage-claude/api-and-data-retention — ZDR scope/eligibility table, HIPAA readiness. See auxiliary `anthropic_doc_2_data-usage-retention.md`.
- https://code.claude.com/docs/en/zero-data-retention — Claude Code-specific ZDR scope, disabled-features table. See auxiliary `anthropic_doc_2_data-usage-retention.md`.
- https://code.claude.com/docs/en/sandbox-environments — isolation-approach comparison table. See auxiliary `anthropic_doc_3_sandbox-security-remote-control.md`.
- https://code.claude.com/docs/en/security — "Cloud execution security" and general security model. See auxiliary `anthropic_doc_3_sandbox-security-remote-control.md`.
- https://code.claude.com/docs/en/remote-control — Remote Control architecture. See auxiliary `anthropic_doc_3_sandbox-security-remote-control.md`.
- https://privacy.claude.com/en/articles/7996862-how-do-i-view-and-sign-your-data-processing-addendum-dpa — DPA + SCC confirmation.
- https://privacy.claude.com/en/articles/9267385-does-anthropic-act-as-a-data-processor-or-controller — controller/processor framing for commercial products.
- https://claude.com/blog/claude-managed-agents-updates — Anthropic's own self-hosted-sandbox / MCP-tunnel architecture split. See auxiliary `market_doc_1_enterprise-perimeter-and-self-hosted.md`.
- https://www.baytechconsulting.com/blog/keep-code-off-cloud-self-hosted-ai-dev-agents — practitioner argument that ZDR is a legal, not technical, control. See auxiliary `market_doc_1_enterprise-perimeter-and-self-hosted.md`.
- https://www.truefoundry.com/blog/claude-enterprise-security — enterprise governance guidance, PHI/GDPR routing via Bedrock/Vertex. See auxiliary `market_doc_1_enterprise-perimeter-and-self-hosted.md`.
- https://claude.com/solutions/financial-services — Citi adoption quote (adoption confirmed, architecture not confirmed). See auxiliary `market_doc_1_enterprise-perimeter-and-self-hosted.md`.
- https://news.ycombinator.com/item?id=44537830 — thin community signal on ZDR. See auxiliary `market_doc_1_enterprise-perimeter-and-self-hosted.md`.
- https://www.conjur.com.br/2024-dez-07/armazenamento-em-nuvem-configura-transferencia-internacional-de-dados/ — LGPD transfer concept applies to transmission/access, not just storage duration. See auxiliary `lgpd_doc_1_international-transfer.md`.
- LGPD Lei 13.709/2018 arts. 33-36 and Resolução CD/ANPD nº 19/2024 — see auxiliary `lgpd_doc_1_international-transfer.md` (text assembled from multiple secondary transcriptions; the Planalto.gov.br primary-source fetch failed with a connection error and is flagged as unverified against the primary text).

## Findings

### Finding 1 — The three modes have genuinely different data-handling architectures, and Anthropic documents this precisely

**Evidence:**

> "Claude Code runs locally. To interact with the LLM, Claude Code sends data over the network. This data includes all user prompts and model outputs, encrypted in transit via TLS 1.2+."
**Source**: code.claude.com/docs/en/data-usage

> "Unlike Claude Code on the web, which runs on cloud infrastructure, Remote Control sessions run directly on your machine and interact with your local filesystem. The web and mobile interfaces are just a window into that local session." ... "When you start a Remote Control session on your machine, Claude keeps running locally the entire time, so nothing moves to the cloud."
**Source**: code.claude.com/docs/en/remote-control

> "Each session runs in a fresh Anthropic-managed VM with your repository cloned." ... "Code and data storage: Your repository is cloned to an isolated VM. Code and session data are subject to the retention and usage policies for your account type."
**Source**: code.claude.com/docs/en/claude-code-on-the-web; code.claude.com/docs/en/data-usage

**Significance**: the engineer's three-way split (local CLI / Remote Control / cloud sandbox) maps exactly onto Anthropic's own documented architecture, not onto a mischaracterization. Local CLI and Remote Control are architecturally identical from a data-handling standpoint (files and execution never leave the engineer's machine; only prompts/outputs cross the network for inference, plus control-plane routing messages for Remote Control). Claude Code on the web is architecturally distinct: the repository is cloned onto, and executes on, Anthropic-managed compute, and "session data" (which includes code changes/generated files, per the quote above) is explicitly subject to Anthropic's account-level retention policy rather than never leaving the engineer's machine.

### Finding 2 — Zero Data Retention (ZDR) and the cloud-sandbox product are mutually exclusive by Anthropic's own design

**Evidence:**

> "ZDR covers model inference calls made through Claude Code on Claude for Enterprise. When you use Claude Code in your terminal, the prompts you send and the responses Claude generates are not retained by Anthropic."
**Source**: code.claude.com/docs/en/zero-data-retention

> Features disabled under ZDR — "Claude Code on the Web | Requires server-side storage of conversation history." / "Cloud sessions from the Desktop app | Requires persistent session data that includes prompts and completions." ... "These features are blocked in the backend regardless of client-side display."
**Source**: code.claude.com/docs/en/zero-data-retention

**Significance**: this is the clearest documented fact bearing on the engineer's hypothesis. An organization cannot have both ZDR enabled *and* use Claude Code on the web — enabling ZDR disables the cloud-sandbox product outright, at the backend level, "regardless of client-side display." Conversely, using Claude Code on the web takes that session's data out of ZDR's scope and back onto the standard 30-day commercial retention window (see Finding 3). This is not the engineer's inference or a market rumor — it is Anthropic's own documented product boundary, and it draws exactly the line the engineer is drawing: inference-only-with-ZDR is one product configuration, and cloud-hosted execution/storage is a structurally different, mutually exclusive one.

### Finding 3 — Cloud-sandbox retention is the standard commercial window (30 days), not indefinite, but there is no ZDR path and no documented fixed "wipe after N days" figure specific to VM/file storage beyond that window

**Evidence:**

> "Commercial users (Team, Enterprise, and API): Standard: 30-day retention period... Zero data retention: available to qualified accounts for Claude Code on Claude for Enterprise."
**Source**: code.claude.com/docs/en/data-usage

> "Session data: Prompts, code changes, and outputs follow the same data policies as local Claude Code usage."
**Source**: code.claude.com/docs/en/data-usage

> "Cloud sessions stop after a period of inactivity and the underlying environment is reclaimed... Reopen the session from claude.ai/code to provision a fresh environment with your conversation history restored."
**Source**: code.claude.com/docs/en/claude-code-on-the-web

> "Deleting a session permanently removes the session and its data. This action can't be undone."
**Source**: code.claude.com/docs/en/claude-code-on-the-web

> "Automatic cleanup: Cloud environments are automatically terminated after session completion."
**Source**: code.claude.com/docs/en/security

**Significance**: there is a real distinction between the *compute environment* (VM) being reclaimed after inactivity, and the *session data* (transcript, code diffs) being retained under the account's standard 30-day policy until either that window elapses or the engineer manually deletes the session. The Security page's "automatically terminated after session completion" is looser/less precise than the more detailed Claude Code on the web page, which frames reclamation as inactivity-triggered and reversible (history is restored on reopen). Taken together: the "N days" retention the engineer is skeptical of auditing is, per documentation, 30 days standard for commercial accounts (or up to 2 years if flagged for a policy violation) — not an infinite retention, but also not something 4Shark can independently verify happened on Anthropic's infrastructure, which is precisely the audit-trust gap the engineer named.

### Finding 4 — "We don't train on it" and "it isn't stored" are different, separately-documented guarantees

**Evidence:**

> "Commercial users: (Team and Enterprise plans, API, 3rd-party platforms, and Claude Gov) maintain existing policies: Anthropic does not train generative models using code or prompts sent to Claude Code under commercial terms, unless the customer has chosen to provide their data to us for model improvement."
**Source**: code.claude.com/docs/en/data-usage

> "Retained data is never used for model training without your express permission." (this is stated as a property of *retained* data — i.e., non-training is a separate axis from non-retention)
**Source**: platform.claude.com/docs/en/manage-claude/api-and-data-retention

**Significance**: for commercial/Team/Enterprise use (which is 4Shark's category, not consumer Free/Pro/Max), Anthropic does not train on the data regardless of retention mode. But non-training does not imply non-storage — data can sit on Anthropic's servers for the standard 30-day window (or persist as a stateful cloud-sandbox session/transcript) without ever being used for training. The engineer's distinction (inference-only-ephemeral vs persisted-on-vendor-storage) is therefore orthogonal to, not resolved by, the training guarantee — a persisted cloud-sandbox session is never trained on, but it is still sitting on infrastructure 4Shark does not control for up to 30 days (or longer if flagged).

### Finding 5 — Anthropic's own May 2026 enterprise product move validates the engineer's "cloud for inference, in-house for execution/storage" pattern — but as a *separate, additive* product, not a property of Claude Code on the web itself

**Evidence:**

> "the agent loop that handles orchestration, context management, and error recovery stays on Anthropic's infrastructure, while tool execution moves to your own configured environment." ... "sensitive files, packages, and services in your own infrastructure or with a managed sandbox provider... files and repositories don't leave [your perimeter]."
**Source**: claude.com/blog/claude-managed-agents-updates (Claude Managed Agents — self-hosted sandboxes, announced May 2026)

**Significance**: this is Anthropic's own architecture, in Anthropic's own words, and it draws the engineer's exact line: keep the "agent loop" (an inference/orchestration-like function) in the vendor's cloud, but move "tool execution" and file/repository storage into the customer's own perimeter. This is strong, primary-source corroboration that even Anthropic recognizes regulated customers want this separation. The important caveat: this is a **separate product** ("Claude Managed Agents" self-hosted sandboxes), distinct from "Claude Code on the web," which does not offer this split — Claude Code on the web keeps both compute and storage on Anthropic's VM. Adopting the "cloud for inference only" pattern with Claude Code specifically means avoiding Claude Code on the web, not configuring a setting within it.

### Finding 6 — Practitioner/consultancy guidance for regulated data explicitly avoids the cloud-sandbox path and routes through Bedrock/Vertex with customer-controlled regions, or full self-hosting

**Evidence:**

> "adopting commercial cloud-hosted AI orchestration means deliberately transmitting proprietary source code, internal architectural diagrams, and potentially sensitive user data across the corporate firewall to third-party model providers." ... "from a strict DevSecOps perspective, ZDR is entirely a legal control, not a technical network boundary."
**Source**: baytechconsulting.com/blog/keep-code-off-cloud-self-hosted-ai-dev-agents

> "If your organization processes Protected Health Information (PHI) with Claude, a Zero Data Retention (ZDR) addendum is required before any PHI enters any Claude interface." ... "For workloads requiring EU data residency, route traffic through AWS EU regions via Bedrock or Google Vertex AI with Private Service Connect."
**Source**: truefoundry.com/blog/claude-enterprise-security

**Significance**: both sources are consultancy/practitioner guidance (not academic or regulatory), but both are current (2026), specific, and converge on the same pattern: regulated data goes through Bedrock/Vertex with the customer's own cloud region/VPC, not through Anthropic's own cloud-sandbox product. The baytechconsulting source explicitly frames ZDR as a *legal* commitment rather than a *technical* boundary the customer can verify — this is the same audit-trust concern the engineer raised about "Anthropic may say it wipes sandboxes... a claim on infrastructure he can't audit."

### Finding 7 — Confirmed adoption by a large regulated bank (Citi) exists, but the deployment architecture for that adoption is not documented in available sources

**Evidence:**

> "Citi chose to leverage Claude as part of its AI powered Developer Platform because of its advanced planning and agentic coding capabilities, focus on safety and reliability, and compatibility with our workloads." — David Griffiths, CTO at Citi
**Source**: claude.com/solutions/financial-services

**Significance**: this confirms the engineer's premise that mature, regulated organizations do adopt Claude/Claude Code. It does **not** confirm or refute the "cloud for inference only" half of the hypothesis, because the source does not state whether Citi's deployment uses the API directly, Bedrock, ZDR, an on-prem gateway, or Claude Code on the web. This is a genuine gap — the specific deployment architecture of named enterprise adopters was not found in this spike's time-box.

### Finding 8 — Community (Hacker News) discussion on this specific distinction is thin

**Evidence:**

> "It uses a regular API token, which promises no retention." — user james_marks
**Source**: news.ycombinator.com/item?id=44537830

**Significance**: this is a single, casual comment, not a substantive debate, and it conflates "API token" broadly with "no retention" without distinguishing CLI/inference calls (which can be ZDR-eligible) from the cloud-sandbox product (which per Finding 2 is explicitly not ZDR-eligible). No robust HN or community thread specifically debating "cloud sandbox vs local execution for regulated PII" was found in this spike's search pass. **This is a real gap, not evidence either way** — the strongest signal for the "mature orgs avoid vendor cloud storage" pattern in this research is vendor-side (Anthropic's own product architecture in Finding 5) and consultancy guidance (Finding 6), not grassroots developer-community consensus. The engineer's hypothesis that this is a documented, widely-discussed pattern in developer community spaces is **not strongly supported** by what this spike found — the pattern exists and is real, but the visible evidence for it is enterprise-vendor and consultancy material, not community discourse.

### Finding 9 — Self-hosted local models (Ollama, vLLM) are a recognized category for the most restrictive cases, but sources here are secondary/unverified

**Evidence** (all from `market_doc_1_enterprise-perimeter-and-self-hosted.md`, Section G — WebSearch summaries, **not independently fetched and quote-verified against primary vendor docs**):

> "For organizations governed by FedRAMP High, HIPAA, PCI-DSS, or the EU AI Act, allowing proprietary source code and sensitive data to traverse external networks to third-party models is a fundamental impossibility." (summarized)

**Significance**: directionally, local/self-hosted open-weight models (via Ollama, vLLM) plus an IDE-integration layer (e.g., Continue.dev) are a recognized alternative when an organization cannot send code externally under any circumstances. This spike did not fetch primary vendor documentation (ollama.com, vllm.ai) to verify specifics (model quality, throughput, feature parity with Claude Code's agentic capabilities) — flagged as a follow-up research gap, not a settled finding.

### Finding 10 — LGPD's international-transfer requirement (arts. 33-36) applies to the act of transmission itself, not to retention duration — meaning it applies equally to ephemeral inference and to persisted cloud storage

**Evidence:**

> "transferência" (transfer) is defined as "toda operação de tratamento por meio do qual um agente de tratamento transmite, compartilha ou disponibiliza acesso a dados pessoais a outro agente" [any data processing operation where one agent transmits, shares, or provides access to personal data to another agent]
**Source**: conjur.com.br/2024-dez-07/armazenamento-em-nuvem-configura-transferencia-internacional-de-dados

> "os casos de cloud computing configuram uma transmissão de dados para o servidor localizado no exterior ou, no mínimo, uma disponibilização de acesso aos dados guardados na nuvem do provedor" [cloud computing instances constitute either transmission of data to foreign servers or, at minimum, provision of access to data stored in the provider's cloud]
**Source**: same

**Significance**: this is the crux legal finding for the engineer's question, and it complicates a purely binary reading of his hypothesis. LGPD arts. 33-36 (see auxiliary for full text) require a legal basis for **any** transmission of personal data to a foreign processor — including a single ephemeral, ZDR-protected inference call to Anthropic's US-based API. The United States has no ANPD adequacy decision (Finding 11), so the legal basis in practice is art. 33-II: contractual guarantees (SCCs / DPA). **This means "inference only, ephemeral" does not exempt 4Shark from needing an art. 33 legal basis — both modes need one.** What genuinely differs between "inference-only, ephemeral, ZDR" and "files persisted on vendor cloud storage" is not whether LGPD's transfer rule applies, but: (a) the volume/duration of PII sitting on infrastructure 4Shark does not control (LGPD's storage-limitation/data-minimization principle, art. 6º-X), (b) the blast radius if Anthropic's storage is breached or subject to a foreign legal process (e.g., US CLOUD Act) during that retention window, and (c) the residual, less-auditable artifact a persisted session/transcript represents versus a call that leaves no server-side trace.

### Finding 11 — The United States has no ANPD adequacy decision; the applicable transfer mechanism is contractual (SCCs/DPA), and Anthropic's DPA does include SCCs

**Evidence:**

> "Regarding the United States specifically, the vast majority of international data transfers have as their destination countries that still do not have recognition of adequacy by ANPD, and the main one is the United States... the perspective that the US will be included in the list of countries with adequate protection is, in the current scenario, quite remote." (WebSearch summary of dponet.com; not independently fetched)

> "Anthropic's DPA with Standard Contractual Clauses (SCCs) is automatically incorporated into our Commercial Terms of Service... When you accept Anthropic's Commercial Terms of Service, you also accept our DPA."
**Source**: privacy.claude.com/en/articles/7996862-how-do-i-view-and-sign-your-data-processing-addendum-dpa

> "the customer is the 'Controller' of the data submitted by its Users" while "Anthropic acts as a 'Processor' of the data on behalf of the customer."
**Source**: privacy.claude.com/en/articles/9267385-does-anthropic-act-as-a-data-processor-or-controller (stated for "Claude for Work and the Anthropic API" — the commercial-products category that Claude Code under commercial/Team/Enterprise terms falls into per Finding 4's source categorization; the page does not use the words "Claude Code" in the fetched excerpt, so this mapping is an inference from the data-usage.md categorization, not a direct quote naming Claude Code)

**Significance**: for a 4Shark-Anthropic relationship, art. 33-I (adequacy) is not available; art. 33-II (contractual guarantees) is the applicable path, and Anthropic's DPA does incorporate SCCs, which is the standard LGPD-compliant mechanism for this kind of transfer regardless of which Claude Code mode is used. This satisfies the *transfer legality* question but — per Finding 10 — does not by itself resolve the *data-minimization/storage-limitation* question, which is where the local-CLI-vs-cloud-sandbox distinction still matters.

**Not found / could not verify**: the exact subprocessor notice/objection period in Anthropic's DPA is reported inconsistently across secondary sources (10 days per one PDF summary found via search, 15 days per another) and was not resolved against a primary DPA text fetch in this spike — flagged as UNVERIFIED, not asserted as fact.

## Trade-offs surfaced

| Approach | Data location (execution + persisted files) | LGPD transfer basis needed? | ZDR available? | Audit/control by 4Shark | Source |
|---|---|---|---|---|---|
| Local CLI only | 4Shark's machine | Yes (inference call itself is a transfer) | Yes, if enabled at org level | Full — nothing persists outside 4Shark except the ephemeral inference call | Findings 1, 2, 10 |
| Local CLI + Remote Control | 4Shark's machine (control-plane routing only via Anthropic) | Yes (same as above) | Yes, same as local CLI | Full — architecturally identical to local CLI for data handling | Finding 1 |
| Claude Code on the web (cloud sandbox) | Anthropic-managed VM; session data retained per account policy | Yes | No — explicitly disabled by backend policy when ZDR is on | Partial — standard 30-day retention, no way to independently verify deletion, "environment expired" ≠ documented data deletion | Findings 2, 3 |
| Self-hosted Agent SDK / Claude Managed Agents self-hosted sandbox in 4Shark's own AWS/VPC | 4Shark's own infrastructure; "agent loop" (orchestration) still calls Anthropic's API for inference | Yes (inference call itself is a transfer) | Depends on inference path (API ZDR is available) | High — tool execution and files stay in 4Shark's perimeter; inference calls are the only egress | Finding 5 |
| Local/self-hosted open models (Ollama, vLLM) for the most sensitive work | Entirely 4Shark's infrastructure | No — no data leaves Brazil/4Shark's control at all | N/A — no vendor inference call | Full — but with a capability/quality trade-off not evaluated in this spike | Finding 9 (unverified secondary sources) |

## What remains uncertain

- The exact deployment architecture used by named enterprise adopters (e.g., Citi) — confirmed adoption, unconfirmed architecture (Finding 7).
- Whether there is a genuinely active developer-community (HN/forums) debate specifically on "cloud sandbox vs local execution for regulated PII" — this spike found the pattern is real but the visible evidence is vendor/consultancy-sourced, not grassroots (Finding 8).
- The exact subprocessor notice/objection period in Anthropic's DPA — conflicting secondary reports (10 vs 15 days), not resolved against primary text (Finding 11).
- Whether Anthropic's LGPD-relevant SCCs specifically reference the ANPD's Resolução 19/2024 Annex clauses, or a separate (e.g., EU-style) SCC set that would need a Brazil-specific addendum — not confirmed in available sources.
- Primary-source verification of the Planalto.gov.br LGPD text (fetch failed with a connection error); the art. 33-36 text used here is corroborated by multiple independent secondary transcriptions but not fetched directly from the government source in this pass.
- Quality/capability parity of self-hosted open models (Ollama/vLLM-based coding assistants) versus Claude Code's agentic capabilities — not evaluated; flagged as a separate research question if Option 5 is pursued.

## Suggested options for main and the engineer

- **Option A — Local CLI only.** Simplest to reason about; every inference call still needs an LGPD art. 33-II legal basis (Anthropic's DPA/SCCs), but no files or persisted session data ever leave 4Shark's machines.
- **Option B — Local CLI + Remote Control.** Same data posture as Option A; adds phone/web as a pure control surface with no additional data-location exposure, per Anthropic's own architecture documentation (Finding 1).
- **Option C — Claude Code on the web (cloud sandbox).** Convenience and no local setup, at the cost of code/session data sitting on Anthropic-managed VM storage under the standard 30-day retention window, with no ZDR path available and no independent way for 4Shark to audit deletion (Findings 2, 3).
- **Option D — Self-hosted Agent SDK / Claude Managed Agents self-hosted sandbox in 4Shark's own AWS/VPC.** Matches the "cloud for inference only" pattern that Anthropic itself now offers as a distinct product; tool execution and files stay in 4Shark's perimeter, only the agent-loop/inference call reaches Anthropic (Finding 5). Requires more setup than Option C.
- **Option E — Local/self-hosted open models (Ollama, vLLM) for the most sensitive work.** No data leaves 4Shark's control at all, at the cost of unverified capability parity with Claude Code (Finding 9).

No recommendation is made among these — the evidence shows the LGPD transfer-basis requirement (art. 33-II, SCCs/DPA) applies to every option that calls Anthropic's API at all, including Option A; the meaningful differentiator across options is the storage-limitation/audit-control axis (Finding 10), which is starkest between Option C and the rest.
