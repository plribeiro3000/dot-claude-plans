# Auxiliary source — Market/enterprise evidence on "cloud for inference, in-house for execution/storage"

All fetched/searched 2026-07-07.

---

## A. Anthropic's own May 2026 product move: self-hosted sandboxes + MCP tunnels

**URL**: https://claude.com/blog/claude-managed-agents-updates (fetched directly, verbatim quotes below)

> the agent loop that handles orchestration, context management, and error recovery stays on Anthropic's infrastructure, while tool execution moves to your own configured environment.

> [With self-hosted sandboxes, organizations can keep] sensitive files, packages, and services in your own infrastructure or with a managed sandbox provider ... files and repositories don't leave [your perimeter].

> [MCP tunnels let agents] reach MCP servers inside your private network without exposing them to the public internet ... no inbound firewall rules, no public endpoints, and traffic encrypted end to end.

**Significance**: this is Anthropic's OWN architecture split, described in Anthropic's own words, and it maps almost exactly onto the engineer's distinction: the "agent loop" (orchestration/inference-like control flow) stays on Anthropic's cloud, while "tool execution" and "files and repositories" move into the customer's own perimeter. Anthropic built this specifically as a *separate, newer product surface* from Claude Code on the web — meaning the default cloud-sandbox product (Claude Code on the web) does NOT have this separation; the self-hosted-execution option is additive and requires deliberate adoption of "Claude Managed Agents" self-hosted sandboxes, a different product from "Claude Code on the web."

Secondary summaries (WebSearch-derived, **not independently fetched/quote-verified — treat as UNVERIFIED corroboration only**, from InfoQ and business-news-today.com coverage of the same May 19, 2026 "Code with Claude London" announcement):
- "addresses a recurring challenge in enterprise AI deployments, where organizations want to use autonomous agents but cannot allow execution environments or internal systems to leave their security perimeter" (WebSearch summary of InfoQ/multiple outlets covering the announcement)
- The direct fetch of business-news-today.com's article failed (`ECONNREFUSED`), so its specific "root problem" framing quote is **UNVERIFIED** and is not used as a sourced claim in SPIKE.md; only the directly-fetched claude.com/blog quotes above are treated as verified.

---

## B. Bedrock / Vertex — enterprise regulated-data deployment pattern

WebSearch-derived summaries (**not independently fetched from AWS/Google primary docs — UNVERIFIED as literal quotes**, presented as directional corroboration only):

- "Anthropic launched a self-hosted Claude Code gateway compatible with both Amazon Bedrock and Google Cloud Vertex AI that lets enterprise teams route Claude Code through their own cloud tenancy, keeping code, credentials, and context inside their security perimeter." (fourweekmba.com, summarized)
- "AWS states that prompts and completions sent to Bedrock are not used to train any models, are not shared with model providers like Anthropic, and stay within your AWS account and chosen region." (fourweekmba.com, summarized — not verified against an AWS primary source in this spike)
- "With Cowork on 3P in an EU region of Bedrock or Vertex, all data remains within the EU with no Schrems discussions or additional contractual safeguards needed." (vanbeaumond.nl, summarized)

**Directly fetched and verified**: `code.claude.com/docs/en/data-usage` confirms the encryption-at-rest table showing Bedrock/Vertex/Foundry as distinct providers with their own encryption regimes (AWS-managed / Google-managed keys), consistent with "data processed in the customer's own cloud tenancy" — see `anthropic_doc_2_data-usage-retention.md`, Source A.

---

## C. Practitioner argument: ZDR is a legal control, not a technical boundary

**URL**: https://www.baytechconsulting.com/blog/keep-code-off-cloud-self-hosted-ai-dev-agents (fetched directly)

> adopting commercial cloud-hosted AI orchestration means deliberately transmitting proprietary source code, internal architectural diagrams, and potentially sensitive user data across the corporate firewall to third-party model providers.

> from a strict DevSecOps perspective, ZDR is entirely a legal control, not a technical network boundary.

> It is completely blind to whether the developer is transmitting harmless boilerplate code, highly classified internal authentication infrastructure, or raw patient records.

**Significance**: this practitioner source makes almost exactly the engineer's argument — that a vendor's retention *promise* (ZDR, "we wipe it") is a contractual/legal commitment, not something the customer can technically verify or audit, and the exposure already occurred at the moment of transmission regardless of what happens after. This directly corroborates the engineer's framing that "Anthropic may SAY it wipes sandboxes... a claim on infrastructure he can't audit."

---

## D. Practitioner enterprise-governance guide

**URL**: https://www.truefoundry.com/blog/claude-enterprise-security (fetched directly)

> Claude Code is now running on developer machines across thousands of enterprises. Most of those deployments share the same characteristics: developers authenticate with personal Anthropic accounts, API keys live in environment variables or `.bash_profile`, there is no audit trail of what code context flows to Anthropic's servers, and there is no mechanism to revoke access when an engineer leaves the organization.

> The security problem isn't Claude Code itself. It's the assumption that a developer tool requires developer-level governance.

> If your organization processes Protected Health Information (PHI) with Claude, a Zero Data Retention (ZDR) addendum is required before any PHI enters any Claude interface.

> For workloads requiring EU data residency, route traffic through AWS EU regions via Bedrock or Google Vertex AI with Private Service Connect.

**Significance**: a named enterprise-governance vendor's guidance for regulated data explicitly routes through Bedrock/Vertex with a customer-controlled cloud region — not through Claude Code on the web.

---

## E. Confirmed adoption example (adoption confirmed; deployment architecture NOT confirmed)

**URL**: https://claude.com/solutions/financial-services (fetched directly, verified quote)

> "Citi chose to leverage Claude as part of its AI powered Developer Platform because of its advanced planning and agentic coding capabilities, focus on safety and reliability, and compatibility with our workloads." — David Griffiths, CTO at Citi

**Important limitation**: this quote confirms Citi (a large regulated bank) adopted Claude for its developer platform, but the page does **not** state which deployment architecture Citi uses (direct API, Bedrock, ZDR, on-prem gateway, or cloud sandbox). This citation supports "regulated orgs adopt Claude Code" but does **not** support any specific claim about how they deploy it — that gap is not resolved by available sources in this spike's time-box.

---

## F. Community/HN signal (thin)

**URL**: https://news.ycombinator.com/item?id=44537830 ("does claude code have a privacy mode with zero data retention?") — fetched directly

> "It uses a regular API token, which promises no retention." — user james_marks

**Significance**: this is a single, casual community comment, not a substantive debate. It conflates "API token" with "no retention" without distinguishing CLI/inference calls from the cloud-sandbox product (which, per `anthropic_doc_2_data-usage-retention.md` Source C, is explicitly NOT ZDR-eligible). No broader HN thread with a substantive "cloud sandbox vs local execution for regulated data" debate was found in this spike's search pass — this is a genuine gap, not a search failure to report as a finding elsewhere.

---

## G. Self-hosted local models (Ollama / vLLM) as the most-restrictive alternative

WebSearch-derived summaries only (**not fetched from primary tool docs — UNVERIFIED as literal quotes, directional signal only**):

- "For organizations governed by FedRAMP High, HIPAA, PCI-DSS, or the EU AI Act, allowing proprietary source code and sensitive data to traverse external networks to third-party models is a fundamental impossibility." (baytechconsulting.com, summarized restatement)
- "vLLM delivers 3.23x better throughput than Ollama... For production multi-user scenarios, vLLM provides 35x higher RPS at peak load compared to llama.cpp on GPU-equipped servers." (aggregated from promptquorum.com / alpacked.io summaries)
- "Continue.dev is the clear winner for local-first developers—it was built with Ollama and LM Studio as primary targets." (promptquorum.com, summarized)

**Significance**: directionally confirms local/self-hosted open models (Ollama, vLLM, Continue.dev as the IDE-integration layer) are a recognized category for organizations that cannot send code externally at all — but none of these specific sources were fetched and quote-verified in this spike; they should be treated as a starting point for further research, not settled fact.
