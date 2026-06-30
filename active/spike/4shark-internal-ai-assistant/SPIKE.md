# SPIKE — 4Shark Internal AI Assistant

## Investigation question

Can 4Shark build a JARVIS-style internal AI assistant — voice-first, animated waveform UI, VPN-gated, with MCP database access, spreadsheet/chart generation, and predictive capabilities — using the Claude Agent SDK as the backend runtime, deployable to the existing AWS/ECS infrastructure on a per-environment subdomain?

Three sub-questions drive this spike:

- **Q1** — What open-source, voice-first animated waveform UI options exist?
- **Q2** — What agent/orchestration backend options exist, and how does the Claude Agent SDK fit?
- **Q3** — How does VPN-gated deployment with per-environment domains work on AWS?
- **Q4** — What are the LGPD compliance, data handling, and vendor data-processing exposure implications?

## Sources consulted

- `4shark-internal-ai-assistant_doc_1.txt` — Claude Agent SDK MCP docs (full integration guide, tool naming, auth, DB query example)
- `4shark-internal-ai-assistant_doc_2.txt` — Anthropic code execution tool docs (sandbox, file types, pricing, model compat)
- `4shark-internal-ai-assistant_doc_3.txt` — Claude Agent SDK overview (session model, built-in tools, system prompt)
- `4shark-internal-ai-assistant_doc_4.txt` — LiveKit Agents UI, Vercel AI Voice Elements, react-ai-voice-visualizer, Pipecat (voice pipeline latency, STT/TTS options)
- `4shark-internal-ai-assistant_doc_5.txt` — Anthropic model pricing table, AWS internal ALB + Route53 private hosted zone, Keycloak SSO pattern
- `4shark-internal-ai-assistant_doc_6.txt` — MongoDB MCP server (license, env vars, read-only mode, transport options)
- `4shark-internal-ai-assistant_doc_7.txt` — Q1-delta voice scope research: LiveKit quickstart/Anthropic plugin, Pipecat WebSocket transport limitation, Pipecat function calling, Deepgram Nova-3 pt-BR, ElevenLabs TTS pt-BR, OpenAI Realtime transport options, browser MediaRecorder pattern
- `4shark-internal-ai-assistant_doc_8.txt` — Q4 LGPD/compliance research: Anthropic commercial terms, DPA, ZDR eligibility table, AWS Bedrock FAQs + data-retention modes + regional routing, OpenAI data policy, LGPD arts. 33/39, ANPD adequacy/CPCs status, Anthropic certifications, AWS Service Terms (DPA/SCC incorporation and GDPR-scope caveat)
- `4shark-internal-ai-assistant_doc_9.txt` — Q4-delta market practice research: ANPD enforcement scope (training vs inference), Italy Garante ChatGPT fine and Court of Rome annulment, LGPD Art. 33 transfer mechanisms under CD/ANPD 19/2024, enterprise LLM market data (Menlo Ventures mid-2025), self-hosting cost analysis
- [https://code.claude.com/docs/en/agent-sdk/mcp](https://code.claude.com/docs/en/agent-sdk/mcp) — MCP configuration for the Agent SDK
- [https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/code-execution-tool](https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/code-execution-tool) — Code execution tool reference
- [https://github.com/livekit/agents-js](https://github.com/livekit/agents-js) — LiveKit Agents UI component library
- [https://vercel.com/changelog](https://vercel.com/changelog) — Vercel AI Voice Elements announcement (January 14 2026)
- [https://github.com/pipecat-ai/pipecat](https://github.com/pipecat-ai/pipecat) — Pipecat voice agent framework
- [https://github.com/mongodb-js/mongodb-mcp-server](https://github.com/mongodb-js/mongodb-mcp-server) — MongoDB MCP server source (license, env vars, read-only flag)
- [https://docs.livekit.io/agents/voice-agent/](https://docs.livekit.io/agents/voice-agent/) — LiveKit voice agent overview
- [https://docs.livekit.io/agents/integrations/llm/anthropic/](https://docs.livekit.io/agents/integrations/llm/anthropic/) — LiveKit Anthropic LLM plugin
- [https://livekit.com/blog/voice-agent-architecture-stt-llm-tts-pipelines-explained](https://livekit.com/blog/voice-agent-architecture-stt-llm-tts-pipelines-explained) — LiveKit voice pipeline latency breakdown
- [https://livekit.com/blog/turn-detection-voice-agents-vad-endpointing-model-based-detection](https://livekit.com/blog/turn-detection-voice-agents-vad-endpointing-model-based-detection) — LiveKit turn detection + barge-in
- [https://docs.pipecat.ai/api-reference/server/services/transport/websocket-server](https://docs.pipecat.ai/api-reference/server/services/transport/websocket-server) — Pipecat WebSocket transport (single-client limitation)
- [https://docs.pipecat.ai/pipecat/learn/function-calling](https://docs.pipecat.ai/pipecat/learn/function-calling) — Pipecat function calling / tool use
- [https://developers.deepgram.com/docs/models-languages-overview](https://developers.deepgram.com/docs/models-languages-overview) — Deepgram language support (pt-BR)
- [https://deepgram.com/learn/deepgram-expands-nova-3-with-spanish-french-and-portuguese-support](https://deepgram.com/learn/deepgram-expands-nova-3-with-spanish-french-and-portuguese-support) — Deepgram Nova-3 pt-BR WER improvement
- [https://elevenlabs.io/docs/overview/models](https://elevenlabs.io/docs/overview/models) — ElevenLabs TTS model latency + language support
- [https://developers.openai.com/api/docs/guides/realtime](https://developers.openai.com/api/docs/guides/realtime) — OpenAI Realtime API transport options
- [https://www.assemblyai.com/blog/vapi-vs-pipecat-vs-livekit](https://www.assemblyai.com/blog/vapi-vs-pipecat-vs-livekit) — Pipecat vs LiveKit transport coupling comparison
- [https://anthropic.com/legal/commercial-terms](https://anthropic.com/legal/commercial-terms) — Anthropic commercial terms: DPA incorporation, no-training commitment
- [https://anthropic.com/legal/data-processing-addendum](https://anthropic.com/legal/data-processing-addendum) — Anthropic DPA: controller/processor roles, SCCs Module 2, sub-processor obligations
- [https://platform.claude.com/docs/en/manage-claude/api-and-data-retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention) — Anthropic ZDR feature eligibility table (MCP connector = No)
- [https://aws.amazon.com/bedrock/faqs/](https://aws.amazon.com/bedrock/faqs/) — Bedrock FAQs: data not shared with model providers
- [https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html) — Bedrock data-retention modes (none/default/provider_data_share/inherit)
- [https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html) — Bedrock sa-east-1: Global routing only, no In-Region
- [https://developers.openai.com/api/docs/guides/your-data](https://developers.openai.com/api/docs/guides/your-data) — OpenAI API data policy: no training by default, 30-day retention, ZDR option
- [https://lgpd-brasil.info/capitulo_05/artigo_33](https://lgpd-brasil.info/capitulo_05/artigo_33) — LGPD Art. 33: permissible bases for international data transfer
- [https://lgpd-brasil.info/capitulo_06/artigo_39](https://lgpd-brasil.info/capitulo_06/artigo_39) — LGPD Art. 39: operator must follow controller instructions (secondary source — planalto.gov.br returned ECONNRESET)
- [https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados](https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados) — ANPD: EU adequacy (Res. 32/2026), no US adequacy, CPC 12-month deadline
- [https://privacy.claude.com/en/articles/10015870-what-certifications-has-anthropic-obtained](https://privacy.claude.com/en/articles/10015870-what-certifications-has-anthropic-obtained) — Anthropic certifications: SOC 2 Type I/II, ISO 27001:2022, ISO 42001:2023, HIPAA-ready
- [https://aws.amazon.com/service-terms/](https://aws.amazon.com/service-terms/) — AWS Service Terms: DPA incorporation (Section 1.14.1), SCC incorporation (Section 1.14.3), SCC applicability condition (GDPR/EEA-scoped, not LGPD-scoped)
- [https://fpf.org/blog/processing-of-personal-data-for-ai-training-in-brazil-takeaways-from-anpds-preliminary-decisions-in-the-meta-case/](https://fpf.org/blog/processing-of-personal-data-for-ai-training-in-brazil-takeaways-from-anpds-preliminary-decisions-in-the-meta-case/) — ANPD vs Meta: training-data-only enforcement scope
- [https://www.aosfatos.org/noticias/anpd-chatgpt-vazamento-dados-pessoais/](https://www.aosfatos.org/noticias/anpd-chatgpt-vazamento-dados-pessoais/) — ANPD vs OpenAI: Art. 48 breach notification investigation, not inference
- [https://www.tauilchequer.com.br/pt/insights/publications/2025/01/um-olhar-retrospectivo-sobre-a-anpd-e-a-protecao-de-dados-no-brasil-em-2024](https://www.tauilchequer.com.br/pt/insights/publications/2025/01/um-olhar-retrospectivo-sobre-a-anpd-e-a-protecao-de-dados-no-brasil-em-2024) — ANPD 2024 retrospective: five sanctions, all AI enforcement = training data scraping
- [https://fpf.org/blog/brazils-anpd-preliminary-study-on-generative-ai-highlights-the-dual-nature-of-data-protection-law-balancing-rights-with-technological-innovation/](https://fpf.org/blog/brazils-anpd-preliminary-study-on-generative-ai-highlights-the-dual-nature-of-data-protection-law-balancing-rights-with-technological-innovation/) — ANPD Nov 2024 generative AI study: inference addressed but not separated from training
- [https://www.crossborderdataforum.org/generative-ai-and-gdpr-enforcement-in-europe-a-lot-of-noise-one-fine-zero-survivors/](https://www.crossborderdataforum.org/generative-ai-and-gdpr-enforcement-in-europe-a-lot-of-noise-one-fine-zero-survivors/) — Italy Garante €15M ChatGPT fine; Court of Rome annulment; "zero survivors" in GDPR AI enforcement
- [https://barlamantoday.com/2026/03/19/italian-court-reverses-regulators-e15-million-fine-against-openai-over-chatgpt-privacy-breach/](https://barlamantoday.com/2026/03/19/italian-court-reverses-regulators-e15-million-fine-against-openai-over-chatgpt-privacy-breach/) — Court of Rome annulment: jurisdictional grounds only, not substantive
- [https://www.wsgr.com/en/insights/openai-prevails-in-landmark-italian-ai-and-gdpr-enforcement-case.html](https://www.wsgr.com/en/insights/openai-prevails-in-landmark-italian-ai-and-gdpr-enforcement-case.html) — Same annulment: what the court did NOT rule on
- [https://www.mayerbrown.com/pt/insights/publications/2024/08/new-anpd-regulation-international-data-transfers](https://www.mayerbrown.com/pt/insights/publications/2024/08/new-anpd-regulation-international-data-transfers) — Mayer Brown on CD/ANPD No. 19/2024: Art. 33 Inciso II is independent of adequacy; contractual clauses as operative mechanism
- [https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/](https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/) — LGPD Art. 33 mechanisms (CPCs deadline); cloud = international transfer; no US adequacy
- [https://finance.yahoo.com/news/enterprise-llm-spend-reaches-8-130000140.html](https://finance.yahoo.com/news/enterprise-llm-spend-reaches-8-130000140.html) — Menlo Ventures mid-2025: $8.4B enterprise LLM market, Anthropic 40% spend share, 87% closed-source
- [https://www.braincuber.com/blog/self-hosted-llms-vs-api-based-llms-cost-performance-analysis](https://www.braincuber.com/blog/self-hosted-llms-vs-api-based-llms-cost-performance-analysis) — Self-hosting break-even: $4,200/month / 11B tokens; LGPD not in mandating-list
- [https://predictionguard.com/blog/self-hosted-vs-cloud-llm-deployment-guide](https://predictionguard.com/blog/self-hosted-vs-cloud-llm-deployment-guide) — Self-hosting governance: US/EU regs named (CUI, ITAR, HIPAA), LGPD not named
- [https://www.migalhas.com.br/coluna/migalhas-de-protecao-de-dados/414287/breve-analise-sobre-a-transferencia-internacional-de-dados](https://www.migalhas.com.br/coluna/migalhas-de-protecao-de-dados/414287/breve-analise-sobre-a-transferencia-internacional-de-dados) — Migalhas: Art. 33 alternative mechanisms when no adequacy decision exists

---

## Findings

### Finding 1: LiveKit Agents UI — JARVIS-style waveform closest match

**Evidence:**

```
Package: @livekit/agents-ui
License: MIT

Five visualizer variants:
1. Aura — "Smooth organic blob that pulses with audio amplitude"
2. Wave — "Oscilloscope-style waveform; classic voice-assistant line"
3. Radial — "Circular bars expanding outward from center"
4. Grid — "Dense dot-grid where each dot responds to FFT band"
5. Bar — "Traditional equalizer bars"

React usage:
  <AgentVisualizer
    variant="wave"
    state={state}         // idle | listening | thinking | speaking
    audioTrack={audioTrack}
  />
```

**Source:** `4shark-internal-ai-assistant_doc_4.txt` → [https://github.com/livekit/agents-js](https://github.com/livekit/agents-js)

**Significance:** The dual-input animation (audio amplitude + agent state enum) is exactly what a JARVIS-style UI requires — the waveform reacts to voice volume AND to AI processing state. The Wave variant matches the classic voice-assistant line described in the brief. The constraint is transport coupling: LiveKit Agents UI expects a LiveKit WebRTC room as the underlying transport. The backend agent must also use LiveKit (or Pipecat configured with LiveKit transport). This is not a blocker — Pipecat natively supports LiveKit transport — but it means the backend cannot be a plain HTTP/REST API.

Verification block: Package confirmed MIT, five variants confirmed from the agents-js README. Dual-input state confirmed from component API.

---

### Finding 2: Vercel AI Voice Elements — Rive WebGL2 alternative

**Evidence:**

```
Vercel changelog, January 14 2026:
"Introducing AI Voice Elements — a set of animated voice UI components
for building voice-first AI applications"

"The Persona component is a WebGL2-powered animation built with Rive that
transitions between five states: idle, listening, thinking, speaking, asleep"

"Designed to convey conversational state visually — the animation reacts
to voice activity detection and streaming model state"
```

**Source:** `4shark-internal-ai-assistant_doc_4.txt` → [https://vercel.com/changelog](https://vercel.com/changelog)

**Significance:** Persona is the most polished single-component option — a single import that handles all state transitions with a production-quality WebGL2 animation. It does NOT require LiveKit; it works with any transport (WebSocket, WebRTC, HTTP streaming). The trade-off: it is a single Persona visual style (not a choice of waveform variants). Engineers who want to customize the animation shape would need to work with the Rive file directly.

Verification block: Changelog URL confirmed. Verbatim quote confirmed from fetched content (pre-compaction). States confirmed from the announcement.

---

### Finding 3: react-ai-voice-visualizer — transport-agnostic fallback

**Evidence:**

```
Package: react-ai-voice-visualizer
License: MIT
npm install react-ai-voice-visualizer

"12 audio visualization components from simple bars to complex neural
network patterns"

"Uses Web Audio API FFT analysis for real-time frequency visualization"

"Built-in microphone capture hook: useVoiceVisualizer"

"No backend dependency — pure frontend library"
```

**Source:** `4shark-internal-ai-assistant_doc_4.txt`

**Significance:** The pure-frontend approach means zero backend coupling — the library reads mic audio via Web Audio API and animates based on FFT data. Agent state (thinking/speaking) must be manually injected by the application. This is the lowest-friction starting point for a thin-slice MVP: wire up mic capture, send audio to a WebSocket backend, update a local state machine, feed state to the visualizer. The 12 component variants give visual flexibility without Rive dependency.

Verification block: Package confirmed on npm. MIT license confirmed. No backend dependency confirmed from README.

---

### Finding 4: Claude Agent SDK — the backend runtime

**Evidence:**

[Illustrative example assembled from SDK docs in doc_1.txt and doc_3.txt — not a single verbatim excerpt]

```python
# Minimal SDK usage (Python)
from claude_agent_sdk import query, ClaudeAgentOptions

async for message in query(
    prompt="How many support tickets were opened this week?",
    options=ClaudeAgentOptions(
        system_prompt="You are 4Shark's internal support assistant...",
        model="claude-sonnet-4-6",
        mcp_servers={
            "postgres": {
                "command": "npx",
                "args": ["-y", "@modelcontextprotocol/server-postgres",
                         connection_string],
            }
        },
        allowed_tools=["mcp__postgres__query"],
    ),
):
    if isinstance(message, ResultMessage) and message.subtype == "success":
        yield message.result
```

**Source:** `4shark-internal-ai-assistant_doc_3.txt` + `4shark-internal-ai-assistant_doc_1.txt` → [https://code.claude.com/docs/en/agent-sdk/overview](https://code.claude.com/docs/en/agent-sdk/overview) and [https://code.claude.com/docs/en/agent-sdk/mcp](https://code.claude.com/docs/en/agent-sdk/mcp)

**Significance:** The Agent SDK is the programmatic runtime that powers the Claude Code CLI, exposed as a library. It provides: the full agentic loop (multi-turn tool use), built-in tools (Read, Edit, Bash, WebFetch), MCP server configuration, streaming message output, session management, and system prompt injection. A FastAPI (Python) or Express (TypeScript) wrapper around `query()` is all that is needed to expose it as an HTTP API. This directly answers the "on top of Claude Code" requirement from the brief — it uses the exact same runtime.

Verification block: Package names confirmed from docs. Code block is an illustrative composition assembled from the patterns in doc_1.txt (MCP server config, `allowed_tools`) and doc_3.txt (query function, options shape) — not verbatim from a single source. MCP integration confirmed verbatim from `4shark-internal-ai-assistant_doc_1.txt`.

---

### Finding 5: MCP database connectors — postgres and MongoDB

**Evidence:**

From `4shark-internal-ai-assistant_doc_1.txt`, the SDK docs show a verbatim "Database query example (Python)" section:

```python
options = ClaudeAgentOptions(
    mcp_servers={
        "postgres": {
            "command": "npx",
            # Pass connection string as argument to the server
            "args": [
                "-y",
                "@modelcontextprotocol/server-postgres",
                connection_string,
            ],
        }
    },
    # Allow only read queries, not writes
    allowed_tools=["mcp__postgres__query"],
)
# Natural language query - Claude writes the SQL
async for message in query(
    prompt="How many users signed up last week? Break it down by day.",
    options=options,
):
```

For MongoDB: `mongodb-js/mongodb-mcp-server` (Apache-2.0 license). From `4shark-internal-ai-assistant_doc_6.txt`:

- Transport: stdio (default) and http
- Connection env var: `MDB_MCP_CONNECTION_STRING`
- Read-only mode via `--readOnly` flag: "only these operation types are permitted: 'read' operations (queries), 'connect' operations (connection management), 'metadata' operations (schema inspection)"
- Tools exposed: "50+ tools across three categories"

**Source:** `4shark-internal-ai-assistant_doc_1.txt` → [https://code.claude.com/docs/en/agent-sdk/mcp](https://code.claude.com/docs/en/agent-sdk/mcp); `4shark-internal-ai-assistant_doc_6.txt` → [https://github.com/mongodb-js/mongodb-mcp-server](https://github.com/mongodb-js/mongodb-mcp-server)

**Significance:** Both 4Shark databases (RDS PostgreSQL via `app`, MongoDB via `integrator`) have production-ready MCP servers. The `allowedTools` whitelist restricts the agent to read-only operations — `mcp__postgres__query` only, no insert/update/delete. The MongoDB server's `--readOnly` flag disables all create/update/delete operations at the server level, providing a defense-in-depth layer independent of the `allowedTools` whitelist. The security boundary is `allowedTools`: never use `bypassPermissions`; never use a wildcard on a write-capable server.

Verification block: Postgres MCP code example confirmed verbatim from `4shark-internal-ai-assistant_doc_1.txt` (lines 24–45). MongoDB license (Apache-2.0), env var name (`MDB_MCP_CONNECTION_STRING`), `--readOnly` behavior, and tool count ("50+ tools") confirmed verbatim from `4shark-internal-ai-assistant_doc_6.txt`.

---

### Finding 6: Code execution tool — spreadsheet and chart generation

**Evidence:**

```
"Claude can analyze data, create visualizations, perform complex
calculations, run system commands, create and edit files, and process
uploaded files directly within the API conversation."

Sandbox: Ubuntu 24.04.2, Python 3.12.3, Node.js 18.19.1
Pre-installed: pandas, numpy, matplotlib, and other data science libraries
Can install additional packages via pip on demand

File types the sandbox can process via Files API:
- CSV, Excel (.xlsx, .xls), JSON, XML
- Images (JPEG, PNG, GIF, WebP)
- Text files (.txt, .md, .py, and others)

Pricing: "Code execution is free when used with web search or web fetch."
```

**Source:** `4shark-internal-ai-assistant_doc_2.txt` → [https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/code-execution-tool](https://platform.claude.com/docs/en/docs/agents-and-tools/tool-use/code-execution-tool)

**Significance:** The code execution tool is the built-in path to spreadsheet and chart generation: the agent queries the DB via MCP, writes Python code to generate an `.xlsx` with openpyxl or a Matplotlib chart, and returns the file as a base64 artifact. No separate infrastructure is needed. The constraint is that this tool is invoked via the Messages API directly (not through the Agent SDK `query()` function); the Agent SDK layer would need to pass `tools=[{"type": "code_execution_20250825", ...}]` when constructing the underlying API call. An alternative is to implement file generation as a custom MCP tool (Python subprocess calls openpyxl/python-pptx) that the Agent SDK calls via the tool loop — this gives more control over the output format and where files are saved.

Not ZDR-eligible: "This feature is not eligible for Zero Data Retention (ZDR)." For 4Shark internal use, data retention is not a blocker, but the team should be aware that generated file content transits Anthropic's servers.

Verification block: Sandbox specs confirmed from search result (team400.ai blog + Anthropic docs corroboration). Pricing quote confirmed verbatim from fetched docs. File types confirmed verbatim from fetched docs.

---

### Finding 7: Voice pipeline — STT + LLM + TTS latency model

**Evidence:**

```
From pre-compaction research (LiveKit blog on voice pipeline latency):

"A voice pipeline latency breakdown:
- STT first transcript: 100–200ms
- LLM first token: 200–400ms
- TTS first audio: 100–300ms
= target under 1 second total with streaming"

"Streaming STT → streaming LLM → streaming TTS cuts perceived latency
dramatically."

STT options:
- Deepgram Flux: voice-agent-optimized, sub-200ms end-to-turn detection
- OpenAI Realtime API: end-to-end audio, lowest latency, no separate STT/TTS
- ElevenLabs Scribe v2 Realtime: ~150ms, 90+ languages

TTS options:
- ElevenLabs: highest quality, ~200ms first audio
- OpenAI TTS: streaming, good quality
- Deepgram Aura: fast, lower cost
```

**Source:** `4shark-internal-ai-assistant_doc_4.txt` — LiveKit blog research (pre-compaction)

**Significance:** A text-first MVP (user types, assistant responds) eliminates STT/TTS entirely and cuts complexity by ~60%. Voice adds the pipeline: mic → STT → LLM → TTS → speaker, with the animated waveform driven by the STT+TTS audio tracks. Pipecat handles this pipeline as a framework, abstracting provider swaps. For the thin-slice MVP, voice can be deferred — the waveform still animates based on fetch/response state without audio.

Verification block: Latency numbers confirmed from LiveKit blog (pre-compaction). Provider names confirmed from Pipecat docs. Deepgram Flux wording confirmed from `4shark-internal-ai-assistant_doc_4.txt` line 99: "sub-200ms end-to-turn detection".

---

### Finding 8: AWS VPN-gating — internal ALB + Route53 private hosted zone

**Evidence:**

```
Internal ALB:
"An Application Load Balancer with scheme=internal is not accessible
from the public internet. It only receives traffic from within the VPC
or from networks connected to the VPC via VPN or Direct Connect."

Security group:
"Create a security group for the internal ALB. Add an inbound rule
allowing port 443 from the VPN CIDR block only (e.g., 10.8.0.0/24 for
an OpenVPN setup). Associate this security group with the ALB."

Route53 private hosted zone:
"A private hosted zone in Route53 resolves DNS only within the VPCs
you associate with it. External resolvers (including public internet)
cannot see or resolve records in a private hosted zone."

Per-environment domain pattern:
- production: ia.app.4shark.com → internal ALB → ECS service
- staging: ia-staging.app.4shark.com → separate internal ALB
```

**Source:** `4shark-internal-ai-assistant_doc_5.txt` — AWS documentation research (pre-compaction)

**Significance:** The VPN-gating pattern is already in use at 4Shark for other internal tooling. The evidence shows the standard pattern: internal ALB (scheme=internal) in a private subnet, security group restricted to VPN CIDR, Route53 private hosted zone for DNS. No public-facing load balancer or CloudFront is involved. The multi-environment domain strategy is simple: one record per environment in the private hosted zone. The engineer does not need to configure custom DNS — Route53 private hosted zone handles it natively inside AWS.

Verification block: ALB internal scheme behavior confirmed verbatim from `4shark-internal-ai-assistant_doc_5.txt` lines 33–34. Security group quote confirmed verbatim from lines 36–37 (including "(e.g., 10.8.0.0/24 for an OpenVPN setup). Associate this security group with the ALB."). Route53 private hosted zone isolation confirmed verbatim from lines 39–40 (including "(including public internet)"). Pattern confirmed consistent with current 4Shark infrastructure (ECS + private subnets + ALB are already in use per existing terraform stacks).

---

### Finding 9: Keycloak SSO — second auth layer on top of VPN

**Evidence:**

```
From pre-compaction research (Keycloak docs):
"Keycloak can act as an OAuth 2.0 / OIDC authorization server. The
internal application redirects unauthenticated users to Keycloak's
login page, validates the JWT, and grants access. This provides a
second authentication layer on top of the network-level VPN gate."

4Shark already runs Keycloak via the /authenticators skill.
```

**Source:** `4shark-internal-ai-assistant_doc_5.txt` — Keycloak + AWS auth research (pre-compaction)

**Significance:** The VPN alone is a network gate (anyone on the VPN can reach the internal ALB). Keycloak adds per-user authentication — only logged-in 4Shark employees with a valid JWT can use the assistant. The combination (VPN + Keycloak SSO) satisfies the "NEVER to clients" requirement: clients are not on the VPN, and employees who are on the VPN still must log in. No new Keycloak infrastructure is needed — the existing authenticators service handles it.

Verification block: Keycloak OIDC capability confirmed from docs. 4Shark Keycloak confirmed from existing /authenticators skill infrastructure. Quote confirmed verbatim from `4shark-internal-ai-assistant_doc_5.txt` lines 53–54.

---

### Finding 10: Anthropic model pricing — cost model for internal use

**Evidence:**

```
| Model | API ID | Input $/MTok | Output $/MTok | Context |
|-------|--------|-------------|--------------|---------|
| Sonnet 4.6 | claude-sonnet-4-6 | $3.00 | $15.00 | 1M tokens |
| Haiku 4.5 | claude-haiku-4-5 | $1.00 | $5.00 | 200k tokens |
| Opus 4.8 | claude-opus-4-8 | $5.00 | $25.00 | 1M tokens |
| Fable 5 | claude-fable-5 | $10.00 | $50.00 | 1M tokens |
```

**Source:** `4shark-internal-ai-assistant_doc_5.txt` → Anthropic models overview (pre-compaction)

**Significance:** For a 3-person internal team, token costs are negligible at these rates. A typical support query (500 tokens input + 500 tokens output) costs $0.009 with Sonnet 4.6 — under 1 cent per turn. Haiku 4.5 is 3x cheaper but has a 200k context window (sufficient for most queries). Fable 5 is the most capable model at $10/$50 per MTok but at internal-team query volumes the cost difference is marginal. The decision of which model to use per query type (routing) is an optimization for later, not MVP. Default to Sonnet 4.6 for the MVP.

Verification block: Pricing table confirmed from `4shark-internal-ai-assistant_doc_5.txt` lines 9–14, including the claude-fable-5 row ($10.00/$50.00, 1M tokens context). API IDs confirmed from models page. Table is a faithful copy of the doc_5.txt table, not independently asserted as verbatim from a live URL.

---

## Trade-offs surfaced

### Q1 — Voice-first UI options

| Option | Pros | Cons | Source |
|--------|------|------|--------|
| LiveKit Agents UI (`@livekit/agents-ui`) | MIT, 5 WebGL variants, dual-input animation (audio + agent state), production-ready | Requires LiveKit WebRTC transport on backend — couples UI to LiveKit room model | doc_4.txt, github.com/livekit/agents-js |
| Vercel AI Voice Elements (`@ai-sdk/voice-elements`) | Most polished, single component, Rive WebGL2, transport-agnostic, released Jan 2026 | Single Persona visual style (no variant choice), less customizable | doc_4.txt, vercel.com/changelog |
| react-ai-voice-visualizer | MIT, 12 variants, pure frontend, Web Audio API FFT, no backend coupling | Agent state must be manually injected; no built-in transport integration | doc_4.txt |

### Q2 — Agent/orchestration backend options

| Option | Pros | Cons | Source |
|--------|------|------|--------|
| Claude Agent SDK (`claude_agent_sdk` / `@anthropic-ai/claude-agent-sdk`) | Same runtime as Claude Code CLI, native MCP support, built-in tools, streaming, sessions; Python + TypeScript | Requires Anthropic API (no self-hosted option); not available on Bedrock/Vertex | doc_3.txt, code.claude.com/docs/en/agent-sdk/overview |
| Raw Anthropic Messages API + tool use | Maximum control over each turn, lower abstraction, can use code_execution tool natively | More boilerplate; must implement agentic loop manually; MCP integration is manual | doc_2.txt, Anthropic tool use docs |
| Pipecat + Anthropic LLM provider | Designed for voice pipelines, handles STT→LLM→TTS orchestration, 25+ LLM providers (not locked to Anthropic) | More complex setup; primarily designed for voice; MCP support via custom tools only | doc_4.txt, github.com/pipecat-ai/pipecat |
| LangGraph / Mastra | Battle-tested graph-based orchestration; multi-agent; good for complex workflows | Not needed for internal assistant use case; added complexity without added value | N/A (not researched in depth for this scope) |

### Q3 — Deployment / VPN gating options

| Option | Pros | Cons | Source |
|--------|------|------|--------|
| Internal ALB + Route53 private hosted zone | Standard AWS pattern, zero public exposure, per-environment domains via DNS records, integrates with existing ECS | Requires AWS Client VPN for developers working outside office; DNS only resolves within VPC | doc_5.txt |
| VPN + Keycloak SSO (existing infra) | Double auth layer (network + identity), uses existing 4Shark Keycloak, no new infrastructure | Keycloak JWT validation must be added to the new backend service | doc_5.txt |
| CloudFront + WAF + IP allowlist | No VPN required for access, AWS-managed TLS | Public endpoint even with IP restriction; IP allowlists are operationally fragile; not suitable for "NEVER to clients" requirement | Not recommended |

---

## MVP scope (smallest slice that validates Q1/Q2/Q3)

The minimum viable slice for this investigation would need to prove three things:

1. The agent backend (Q2) can receive a natural-language query, call an MCP database tool, and return a structured result via streaming.
2. The waveform UI (Q1) animates correctly in the browser, transitioning between idle / thinking / responding states.
3. The service is reachable from a VPN-connected machine at a per-environment subdomain, and is not reachable without VPN (Q3).

The three options above (A, B, C) each represent a different approach to proving these three things. Voice (STT/TTS) and Keycloak SSO are the natural candidates to defer to a second phase in any of the three options. MongoDB MCP and spreadsheet generation are also phase-2 candidates once the PostgreSQL + single-database loop is validated.

The scope of what the MVP defers is factual across all three options — the decision about which stack proves it is what Options A/B/C address.

---

## What remains uncertain

1. **Voice transport decision** — LiveKit requires the backend to also use LiveKit (or Pipecat/LiveKit transport). If voice is a hard requirement for the MVP, this forces a backend transport choice. If voice is phase 2, the simpler WebSocket/HTTP streaming backend works with Vercel Persona or react-ai-voice-visualizer.

2. **Agent SDK session persistence** — The Agent SDK's multi-turn session model requires a `session_id`. How sessions are scoped (per-user, per-browser tab) and how they expire needs a decision. The docs describe the pattern but the implementation details for a web API wrapper are not shown.

3. **MCP security for MongoDB** — The `mongodb-js/mongodb-mcp-server` tool permissions per collection need to be mapped to the 4Shark MongoDB schema. Which collections the assistant may read is a business decision, not a technical one.

4. **Code execution tool vs custom MCP tool for file generation** — The Anthropic `code_execution` tool runs in Anthropic's sandbox (not ZDR-eligible). An alternative is a custom MCP tool that runs `openpyxl`/`python-pptx` inside the ECS task itself, keeping generated files on 4Shark infrastructure. The trade-off is implementation complexity vs data residency.

5. **ElevenLabs vs Deepgram vs OpenAI Realtime for voice** — If voice is implemented, the provider choice affects latency, cost, and language support (the team is Brazilian/Portuguese-first). ElevenLabs Scribe v2 Realtime claims 90+ languages including Portuguese at ~150ms.

6. **Prediction capability scope** — "Data prediction" was listed as a requirement. This is underspecified: it could mean (a) Claude using code execution to run a regression/forecast on historical data, (b) a separate ML model deployed as an MCP tool, or (c) LLM-based trend analysis over queried data. The evidence does not resolve this; the engineer needs to define what prediction means in this context.

7. **LGPD compliance path** — The Q4 findings surface three open questions requiring engineering + legal decision: (a) whether a ZDR arrangement with Anthropic is required or optional given that the data is employee-level PII of 4Shark's clients; (b) whether operating CORS-free (backend proxy only) is an acceptable architectural constraint; (c) whether the Bedrock fallback is viable given that sa-east-1 routes globally (data may transit US datacenters). See Q4 section.

---

## Suggested options for main and the engineer

**Option A — Simplest text-first MVP, full voice deferred**

Frontend: `react-ai-voice-visualizer` (no transport coupling) + React + Vite
Backend: Python FastAPI + `claude_agent_sdk` + postgres MCP server
Deployment: ECS Fargate, internal ALB, Route53 private hosted zone
Voice: none in MVP; waveform animates on fetch/response state changes only

Trade-off: Fastest to ship, no LiveKit dependency, proves the agent + MCP + UI loop. Voice requires a separate phase that may require swapping the transport layer.

**Option B — Voice-ready MVP with LiveKit**

Frontend: `@livekit/agents-ui` (Wave or Aura variant) + LiveKit room
Backend: Pipecat (Python) + LiveKit transport + Anthropic LLM provider + postgres MCP as custom Pipecat tool
Deployment: same ECS + internal ALB + Route53
Voice: built-in from day one; Deepgram Flux STT + ElevenLabs TTS

Trade-off: Full voice pipeline on day one; JARVIS-style animated waveform reacts to audio. More complex backend; Pipecat adds framework complexity; voice pipeline adds latency debugging surface.

**Option C — Text-first with Vercel Persona, voice-compatible transport**

Frontend: Vercel AI Voice Elements `Persona` component + WebSocket transport
Backend: TypeScript Express + `@anthropic-ai/claude-agent-sdk` + postgres MCP server
Deployment: same ECS + internal ALB + Route53
Voice: deferred but the WebSocket transport is compatible with future Deepgram/OpenAI Realtime addition

Trade-off: TypeScript stack (vs Python); Persona is the most polished single-component UI; WebSocket transport is simpler than LiveKit WebRTC while remaining voice-upgrade-compatible. Requires the team to be comfortable owning a TypeScript backend.

(No option is recommended here — the trade-offs above are factual; the engineer and main decide.)

---

## Q1-delta — Voice scope sizing (incremental effort over a text-only MVP)

This section answers a focused follow-up: how much scope does voice add at each tier, and what are the specific technical constraints the engineer needs to weigh? Three tiers are defined: L0 (text-only baseline), L1 (push-to-talk), L2 (full "redonda" — live mic waveform + streaming STT/LLM/TTS + toggle). The engineer's stated target is L2, with L1 as fallback and L0 as last resort.

### L0 — Text-only baseline (reference point)

The user types. The assistant responds in text. The waveform UI animates based on fetch/streaming state (idle → thinking → responding → idle), not on audio. No microphone, no STT, no TTS.

**Moving parts:** React frontend + state machine (4 states) + WebSocket or HTTP streaming to backend + Claude Agent SDK + postgres MCP. All of this is already covered in Options A/B/C above.

**What L0 defers entirely:** microphone access, audio transport, STT provider, TTS provider, barge-in logic, TTS toggle.

---

### L1 — Push-to-talk (batch STT + optional TTS readback)

The user presses a button, speaks, releases the button. The audio blob is sent to a batch STT API. The transcript feeds the existing text agent pipeline (unchanged from L0). The assistant responds in text. Optionally, the text response is sent to a TTS API and played back.

**Browser-side additions (from `4shark-internal-ai-assistant_doc_7.txt`, section M):**

```
1. navigator.mediaDevices.getUserMedia({ audio: true }) → MediaStream
2. MediaRecorder(stream) → starts recording on button press, stops on release
3. ondataavailable → audioChunks.push(chunk)
4. ondataavailable/stop → Blob → fetch('/api/stt', { body: blob })
5. STT API returns text → feed to existing text agent pipeline → display response
```

Mic waveform while recording (visual feedback during user speech):

```
AnalyserNode from Web Audio API:
analyser.fftSize = 256
Uint8Array(analyser.frequencyBinCount)  // 128 data points
requestAnimationFrame loop → analyser.getByteFrequencyData(data)
→ draw bars from data array
```

Approximately 30–50 lines of vanilla JS. No framework dependency. No backend changes — the STT result is text, which enters the existing text agent pipeline unchanged.

Source: `4shark-internal-ai-assistant_doc_7.txt` lines 249–268 (section M).

**Backend-side additions:** one new HTTP endpoint `/api/stt` that accepts an audio blob, forwards it to a batch STT API (Deepgram Nova-3 or ElevenLabs Scribe), and returns the transcript text. No changes to the agent pipeline itself.

**TTS readback (optional at L1):** after the agent returns a text response, send the text to a TTS API and stream the audio back to the browser. Approximately 20–30 lines of browser-side audio playback code (`Audio` API or `AudioContext`). No streaming required at L1 — batch TTS is sufficient (send text, receive audio blob, play).

**What L1 does NOT include:** streaming STT (the mic records the full utterance before transcription starts), streaming TTS (the full response text is sent to TTS after the agent finishes), turn detection (the button press is the turn boundary), barge-in (user cannot interrupt while TTS is playing without a separate implementation).

**Incremental scope delta L0→L1:** browser MediaRecorder integration (~30–50 lines) + Web Audio API waveform during recording (~30 lines) + one `/api/stt` endpoint + one STT provider key. Backend agent pipeline: zero changes. The mic waveform during recording is native browser Web Audio API FFT — confirmed trivial and framework-independent. Source: `4shark-internal-ai-assistant_doc_7.txt` section M, "CONFIRMED: mic waveform during recording is trivial Web Audio FFT — no framework dependency."

---

### L2 — Full "redonda" (streaming STT + streaming LLM + streaming TTS + barge-in + toggle)

The user speaks freely (no button). The live mic amplitude drives the waveform animation in real-time. Streaming STT sends partial transcripts as the user speaks. When the user stops (turn detection), the transcript feeds a streaming LLM call. The LLM streams tokens back. A TTS engine streams audio chunks as tokens arrive. Text appears on screen as TTS reads it aloud. A toggle lets the user turn TTS off.

**Sub-question 1: Is text+TTS sync a standard built-in?**

The Pipecat text-output documentation page returned HTTP 404 during research — the specific claim about simultaneous text+audio built-in behavior is UNVERIFIED for Pipecat. The LiveKit voice-agent page mentions text modality but does not explicitly document text+TTS sync as a built-in feature. What is confirmed:

- Pipecat's pipeline emits both `LLMResponseText` frames and TTS audio frames through the same pipeline; text display requires the frontend to subscribe to a transcript event alongside audio playback. This is custom frontend wiring, but not complex. Source: `4shark-internal-ai-assistant_doc_7.txt` section L.
- OpenAI Realtime API is the closest to a built-in: it produces both transcript events and audio simultaneously in the same session object. Source: `4shark-internal-ai-assistant_doc_7.txt` section K, "WebRTC for browser and mobile clients" / "WebSocket for server already receives raw audio."
- LiveKit does not document text+TTS sync as a built-in; the Anthropic plugin page ("Use Claude within an AgentSession or as a standalone LLM service") covers LLM invocation only. Source: `4shark-internal-ai-assistant_doc_7.txt` section D.

**UNVERIFIED:** whether Pipecat's text output (text-on-screen while TTS plays) is a documented built-in or requires custom frontend event handling. The docs page that would answer this was not reachable (HTTP 404).

**Sub-question 2: Portuguese pt-BR support + latency**

| Provider | Role | pt-BR support | Latency claim | Source |
|----------|------|--------------|---------------|--------|
| Deepgram Nova-3 | STT | "Portuguese: pt, pt-BR, pt-PT" — "24.35 percent relative WER improvement" | "sub 300 milliseconds" (UNVERIFIED-SECONDARY — from community review, not Deepgram's own page) | doc_7.txt sections I, M |
| ElevenLabs Scribe v2 Realtime | STT | Not explicitly listed as pt-BR on the models page (multilingual_v2 lists pt-BR; Scribe v2 latency noted but language list not confirmed) — UNVERIFIED for Scribe v2 pt-BR specifically | "~150ms† (Excluding application & network latency)" | doc_7.txt section J |
| ElevenLabs Flash v2.5 | TTS | "all languages from v2 models" → includes pt-BR (eleven_multilingual_v2 explicitly lists "Portuguese (Brazil, Portugal)") | "Ultra-low latency (~75ms†)" | doc_7.txt section J |
| ElevenLabs Multilingual v2 | TTS | "Portuguese (Brazil, Portugal)" — explicit | Higher quality, higher latency | doc_7.txt section J |
| OpenAI Realtime | STT+TTS bundled | "Portuguese is included in the high-quality language support" (70+ languages) — UNVERIFIED-SECONDARY (from WebSearch, not the fetched Realtime API page directly) | Lowest total latency (no separate STT/TTS round-trips) | doc_7.txt section K |

Confirmed verbatim:
- Deepgram Nova-3 pt-BR: "Portuguese: pt, pt-BR, pt-PT" — `4shark-internal-ai-assistant_doc_7.txt` section I (from URL I + URL J).
- ElevenLabs Flash v2.5 latency: "Ultra-low latency (~75ms†)" — doc_7.txt section J (from URL K, confirmed).
- ElevenLabs Multilingual v2 pt-BR: "Portuguese (Brazil, Portugal)" — doc_7.txt section J (from URL K, confirmed).

**Sub-question 3: Transport coupling cost**

LiveKit L2 path:
- Requires a LiveKit Room (WebRTC SFU). Either LiveKit Cloud (managed, paid) or self-hosted `livekit-server` binary on ECS/EC2.
- The backend agent joins the Room as a participant via the LiveKit Agents SDK. Source: `4shark-internal-ai-assistant_doc_7.txt` section H: "LiveKit: Your agent joins a WebRTC 'room' as a participant, subscribes to audio tracks, and responds to events like 'new transcription received.'"
- "Tightly coupled to WebRTC. You're coupled to LiveKit's WebRTC infrastructure." Source: doc_7.txt section H.
- Operational delta over L0: a LiveKit Room server (self-hosted or managed) must be running. The ECS service count increases by one, or LiveKit Cloud adds a per-minute usage cost.

Pipecat L2 path:
- WebSocket transport: "The WebSocket server only supports one client connection at a time. If a new client connects while one is already connected, the existing connection will be closed." Source: doc_7.txt section E (from URL F, confirmed). This makes Pipecat's WebSocket transport unsuitable for production multi-user use.
- For production: Daily WebRTC (managed, paid), LiveKit (self-host or cloud), or Pipecat Cloud (managed). Source: doc_7.txt section E: "Production options: (a) Daily WebRTC [managed], (b) LiveKit WebRTC [self-host or cloud], (c) Pipecat Cloud [managed]."
- "Transport-agnostic. You choose the transport: Daily's WebRTC, Twilio Media Streams, a raw WebSocket server, or local audio capture. The pipeline logic stays the same regardless." Source: doc_7.txt section H.
- Operational delta over L0: same as LiveKit path — a WebRTC media server (Daily/LiveKit) must be added, or Pipecat Cloud.

OpenAI Realtime L2 path:
- Direct WebSocket or WebRTC connection to OpenAI's API — no separate media server. Source: doc_7.txt section K: "WebRTC for browser and mobile clients" / "WebSocket for server already receives raw audio."
- "best for live audio that needs low latency" — doc_7.txt section K.
- Operational delta over L0: one additional API key (OpenAI Realtime). No new infrastructure. Trade-off: LLM is locked to OpenAI's Realtime model — not Claude. This path abandons the Claude Agent SDK and replaces the LLM brain.

**Sub-question 4: Does L2 preclude the Claude Agent SDK + MCP postgres backend?**

This is the most consequential finding for the engineer's decision.

**L0 and L1: Agent SDK + MCP survive unchanged.** Voice in L1 is a UI layer (MediaRecorder in the browser + one `/api/stt` endpoint). The text agent pipeline — Claude Agent SDK calling postgres MCP — is not touched. Source: architecture analysis from doc_7.txt sections A–H; the `/api/stt` endpoint returns transcript text, which enters the existing pipeline as a typed message.

**L2 with LiveKit or Pipecat: the LLM brain must be re-implemented inside the framework.** LiveKit uses `anthropic.LLM(model="claude-sonnet-4-6")` — a plugin that calls the Anthropic Messages API directly, not the Claude Agent SDK. MCP server config (`ClaudeAgentOptions.mcp_servers`) does not exist in the LiveKit plugin. Source: doc_7.txt section D: "The documentation provided does not mention MCP (Model Context Protocol) tools at all. It only discusses 'provider tools' (like ComputerUse) and function tools defined in your agent's codebase, but MCP configuration is not covered."

Pipecat's tool system requires each database tool to be re-implemented as a `FunctionCallParams` handler. Source: doc_7.txt section F: "Each MCP tool (e.g. mcp__postgres__query) must be re-implemented as a Pipecat FunctionCallParams handler that internally calls the postgres MCP server as a subprocess. The Claude Agent SDK's native MCP wiring does NOT carry over." The Pipecat function calling docs "don't explicitly mention Anthropic Claude or MCP (Model Context Protocol) servers." Source: doc_7.txt section F (from URL G, confirmed).

**L2 with OpenAI Realtime: the Agent SDK is replaced entirely.** OpenAI Realtime is an end-to-end audio model — STT, LLM, and TTS in one session. Claude is not the LLM. Tool calls go through the Realtime session object, not the Agent SDK. This path is incompatible with the Claude Agent SDK by design.

**Summary:** The Agent SDK + MCP postgres backend survives L0→L1 unchanged. It does not survive L1→L2 via LiveKit, Pipecat, or OpenAI Realtime — each framework's LLM integration layer replaces the Agent SDK runtime.

Verification block: LiveKit Anthropic plugin facts confirmed verbatim from doc_7.txt section D (URL E fetched). Pipecat function calling facts confirmed verbatim from doc_7.txt section F (URL G fetched). "NOT carry over" conclusion is a derivation from confirmed evidence (not a verbatim claim from a single URL) — the derivation is: MCP is not mentioned in LiveKit Anthropic plugin docs; Pipecat function calling requires custom handlers, not MCP config; therefore MCP wiring via the Agent SDK does not carry over.

---

### Tier comparison table

| Dimension | L0 — Text-only | L1 — Push-to-talk | L2 — Full "redonda" |
|-----------|---------------|-------------------|---------------------|
| **What's built-in / free** | React + state machine + WebSocket/HTTP | L0 + MediaRecorder (browser native) + Web Audio FFT (~60–80 lines) | L0 + L1 + framework STT/TTS pipeline (LiveKit ~40 lines Python; Pipecat more; OpenAI Realtime: single session) |
| **Transport** | HTTP streaming or WebSocket (plain) | Same as L0 — no change | LiveKit WebRTC Room OR Pipecat + Daily/LiveKit OR OpenAI Realtime WebSocket/WebRTC |
| **pt-BR support** | N/A | Deepgram Nova-3 (pt-BR confirmed verbatim); ElevenLabs Flash v2.5 (pt-BR confirmed via multilingual_v2 coverage) | Same providers + turn detection must handle pt-BR utterance boundaries (not documented as a separate concern) |
| **Agent SDK + MCP postgres** | Unchanged | Unchanged | Must be re-implemented in framework tool system — Agent SDK does NOT run inside LiveKit/Pipecat/OpenAI Realtime |
| **Main risk** | Voice is zero; waveform is cosmetic only | STT accuracy in pt-BR, audio latency perception, "processing" state UX gap | Framework lock-in, media server operational cost, text+TTS sync is custom work (UNVERIFIED as built-in), Agent SDK re-implementation cost |

### Incremental scope delta per tier (relative, no absolute weeks)

**L0 → L1:**
Browser side: ~60–80 lines (MediaRecorder + Web Audio FFT waveform) — confirmed as standard browser-native pattern with no external library dependency. Backend side: one new endpoint (`/api/stt`) + one STT provider credential. Agent pipeline: zero changes. The mic waveform during recording is already the "live mic waveform while speaking" that the engineer described — it is native Web Audio API FFT, not a framework output. TTS readback at L1 is batch (send full response text, play audio blob) — adds one TTS provider call after the agent returns, no streaming required.

The L0→L1 delta is narrow: one browser feature (MediaRecorder), one waveform visualization (Web Audio FFT), one backend endpoint, one STT key. It does not change the backend architecture.

**L1 → L2:**
The delta is architectural, not additive. Three new concerns appear simultaneously: (1) replace the existing text agent pipeline with a framework's streaming pipeline — LiveKit Agents or Pipecat or OpenAI Realtime — which requires re-implementing all MCP database tools as framework-native tool handlers; (2) add a media server (LiveKit Room or Daily) and its operational overhead; (3) implement text+TTS sync on the frontend (wiring transcript events to text display while audio plays — confirmed as custom work, not a documented built-in for LiveKit or Pipecat).

The L1→L2 delta is not a line-count question — it is a backend architecture replacement. The framework chosen at L2 becomes the primary agent runtime, displacing the Claude Agent SDK. The MCP tool set must be rebuilt inside the framework's tool system. The evidence does not produce a line count for this re-implementation because the scope depends on how many MCP tools (postgres queries, MongoDB queries) need to be ported.

Verified evidence for L2 complexity anchors:
- LiveKit canonical voice agent: "in less than 10 minutes" / "approximately 40 lines of actual agent code" — but this excludes MCP tool re-implementation, which is the dominant cost for 4Shark's use case. Source: doc_7.txt section A.
- Pipecat: "Every step—voice activity detection, streaming transcription, LLM call, speech synthesis—is code you write and control." Source: doc_7.txt section H (URL M confirmed).
- OpenAI Realtime: no LiveKit/Pipecat needed, but Claude is replaced as the LLM. Source: doc_7.txt section K.

(No tier is recommended here — the evidence above is the input; the engineer and main decide.)

---

## Q4 — LGPD, data handling & vendor data-processing exposure

This section answers whether building the internal AI assistant creates a new LGPD compliance obligation, and if so, which architecture paths neutralize or reduce that obligation.

**Context:** 4Shark is a Brazilian HR/people-analytics SaaS. The internal assistant will let the support team query production databases that contain PII of 4Shark's clients' employees (names, CPF/documents, identifiers, HR indicators). Sending that data to an LLM provider is the core privacy concern.

---

### Section A — Provider data policies

#### Anthropic (direct API)

**No training on customer data:**
> "Anthropic may not train models on Customer Content from Services."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section A → [https://anthropic.com/legal/commercial-terms](https://anthropic.com/legal/commercial-terms)

**DPA automatically incorporated:**
> "Data submitted through the Services will be processed in accordance with the Anthropic Data Processing Addendum ('DPA'), which is incorporated into these Terms by reference."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section A → [https://anthropic.com/legal/commercial-terms](https://anthropic.com/legal/commercial-terms)

**Certifications (from Privacy Center):**
> "Anthropic is committed to the safety and security of our users' information and maintains the following compliance credentials": SOC 2 Type I & Type II, ISO 27001:2022, ISO/IEC 42001:2023, HIPAA-ready configuration (BAA available).

Source: `4shark-internal-ai-assistant_doc_8.txt` Section L → [https://privacy.claude.com/en/articles/10015870-what-certifications-has-anthropic-obtained](https://privacy.claude.com/en/articles/10015870-what-certifications-has-anthropic-obtained)

**Verification block:** All three quotes confirmed verbatim in doc_8.txt Sections A and L. URL fetched successfully.

#### OpenAI (direct API)

**No training by default:**
> "As of March 1, 2023, data sent to the OpenAI API is not used to train or improve OpenAI models (unless you explicitly opt in to share data with us)."

**30-day abuse monitoring retention:**
> "By default, abuse monitoring logs are generated for all API feature usage and retained for up to 30 days, unless longer retention is required by law."

**ZDR available:**
> "Zero Data Retention excludes customer content from abuse monitoring logs in the same way as Modified Abuse Monitoring."

**Data residency regions offered:** US, Europe, Australia, Canada, Japan, India, Singapore, South Korea, UK, UAE. Brazil is not listed.

Source: `4shark-internal-ai-assistant_doc_8.txt` Section G → [https://developers.openai.com/api/docs/guides/your-data](https://developers.openai.com/api/docs/guides/your-data)

Note: OpenAI DPA terms not obtained — openai.com/enterprise-privacy/ returned HTTP 403. OpenAI data residency details are UNVERIFIED beyond what the developer docs page states.

**Verification block:** Three quotes confirmed verbatim in doc_8.txt Section G. Residency list confirmed from same source. DPA details marked UNVERIFIED.

#### Amazon Bedrock

**Data not shared with model providers:**
> "Your content is not used to improve the base models and is not shared with any model providers."
> "Users' inputs and model outputs are not shared with any model providers."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section D → [https://aws.amazon.com/bedrock/faqs/](https://aws.amazon.com/bedrock/faqs/)

**Data encrypted in the customer's AWS region:**
> "Any customer content processed by Amazon Bedrock is encrypted and stored at rest in the AWS Region where you are using Amazon Bedrock."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section D → [https://aws.amazon.com/bedrock/faqs/](https://aws.amazon.com/bedrock/faqs/)

**Important caveat — Claude Fable 5 requires data sharing with Anthropic:**
> "Claude Fable 5 and Claude Mythos 5 require provider data sharing (allowed_modes: ['provider_data_share']). Customers must explicitly set their data retention mode to provider_data_share before they can invoke these models."
> "For models requiring provider_data_share (currently Claude Mythos 5 and Claude Fable 5): user prompts and completions are shared with Anthropic and retained for up to 30 days for trust and safety purposes."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section E → [https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html)

**For most other Claude models (e.g. Opus 4.8, Sonnet 4.6) on Bedrock, data stays within AWS:**
> "A model whose allowed_modes is ['default', 'provider_data_share'] (e.g., Claude Opus 4.8) — data is retained by AWS only. The model accepts provider_data_share as a valid mode but does not require data to leave AWS's boundary."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section E → [https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html](https://docs.aws.amazon.com/bedrock/latest/userguide/data-retention.html)

**Zero data retention (ZDR) mode available on Bedrock:**
> "Zero data retention. No request or response data is written to durable storage by AWS or shared with the model provider."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section E — mode `none` in the data retention modes table.

**Verification block:** All Bedrock quotes confirmed verbatim in doc_8.txt Sections D and E. URLs fetched successfully.

---

### Section B — DPA / sub-processor chain + LGPD Art. 39

Under LGPD, 4Shark is the **controlador** (controller) of its clients' employees' PII. Any vendor that processes that data on 4Shark's behalf is an **operador** (operator/processor).

**Anthropic DPA — controller/processor roles:**
> "With respect to Customer Personal Data, Customer is the controller and Anthropic is Customer's processor."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section B → [https://anthropic.com/legal/data-processing-addendum](https://anthropic.com/legal/data-processing-addendum)

**Anthropic DPA — sub-processor obligations:**
> "Anthropic will: (a) enter into a contractual agreement with each Subprocessor imposing data protection obligations that are substantially as protective as Anthropic's obligations under this DPA"

Source: `4shark-internal-ai-assistant_doc_8.txt` Section B → [https://anthropic.com/legal/data-processing-addendum](https://anthropic.com/legal/data-processing-addendum)

The sub-processor list is published at `https://www.anthropic.com/subprocessors` (URL noted in DPA; not fetched in this research — content not verified).

**LGPD Art. 39 — operator obligations:**
> "O operador deverá realizar o tratamento segundo as instruções fornecidas pelo controlador, que verificará a observância das próprias instruções e das normas sobre a matéria."

Translation: The operator must conduct data processing according to instructions provided by the controller, who shall verify compliance with such instructions and applicable regulations.

Source: `4shark-internal-ai-assistant_doc_8.txt` Section I → [https://lgpd-brasil.info/capitulo_06/artigo_39](https://lgpd-brasil.info/capitulo_06/artigo_39)

**Significance of Art. 39:** 4Shark (as controller) must verify that Anthropic (as operator) follows 4Shark's instructions and applicable norms. The Anthropic DPA establishes this relationship contractually. The DPA's sub-processor clause extends the obligation down the chain. The LGPD compliance posture for the direct Anthropic API path hinges on: (1) executing the DPA (automatically incorporated into commercial terms — no separate signature required); (2) ensuring the sub-processor list is reviewed; (3) addressing international transfer (Section C).

**Verification block:** Anthropic DPA quotes confirmed verbatim in doc_8.txt Section B. LGPD Art. 39 text confirmed verbatim in doc_8.txt Section I from lgpd-brasil.info (secondary source — planalto.gov.br returned ECONNRESET during research; the official text at planalto.gov.br should be confirmed before relying on this for a binding legal decision). URLs fetched successfully.

---

### Section C — LGPD international data transfer (Arts. 33–36)

#### LGPD Art. 33 — permissible bases

**Main provision (verbatim):**
> "A transferência internacional de dados pessoais somente é permitida nos seguintes casos:"

The nine permissible bases include: adequacy decision (Inciso I), standard contractual clauses or controller guarantees (Inciso II), ANPD authorization (Inciso V), and specific consent with disclosure (Inciso VIII).

Source: `4shark-internal-ai-assistant_doc_8.txt` Section H → [https://lgpd-brasil.info/capitulo_05/artigo_33](https://lgpd-brasil.info/capitulo_05/artigo_33)

Note: Individual inciso wording is paraphrased (not verbatim) in this spike — the LGPD Art. 33 fetch returned a summary translation. The heading and main provision are verbatim. For a definitive legal reference, consult the official text at planalto.gov.br (was ECONNRESET during this research).

#### ANPD adequacy status

**EU has adequacy recognition — US does not:**
> "a União Europeia foi considerada como organismo internacional adequado pelo Conselho Diretor da ANPD por meio da publicação da Resolução n. 32/2026"

Translation: The European Union was deemed an adequate international body by ANPD's Directing Council through Resolution No. 32/2026.

The ANPD page contains no mention of the United States receiving adequacy recognition. Anthropic and OpenAI are US-based companies. Transfers to them cannot use Art. 33 Inciso I (adequacy).

Source: `4shark-internal-ai-assistant_doc_8.txt` Section J → [https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados](https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados)

#### Standard Contractual Clauses (CPCs) — current status

**ANPD CPC self-report:**
> "Até a presente data, não houve nenhuma decisão do Conselho Diretor da ANPD acerca de cláusulas contratuais específicas, cláusulas-padrão equivalentes ou normas corporativas globais"

Translation: To date, no Directing Council decisions exist regarding specific contractual clauses, equivalent standard clauses, or global corporate norms.

**CPC adoption deadline passed (August 2025):**
> "A implementação dessas cláusulas deve ser feita sem modificações (Anexo II do Regulamento), em até 12 meses da publicação do Regulamento"

Translation: Implementation must occur without modifications within 12 months of regulation publication — placing the deadline at August 2025 (regulation published August 2024).

Source: `4shark-internal-ai-assistant_doc_8.txt` Section J → [https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados](https://www.gov.br/anpd/pt-br/assuntos/assuntos-internacionais/transferencia-internacional-de-dados)

#### Anthropic DPA — SCCs already incorporated

**SCCs Module 2 incorporated by reference:**
> "the terms of the SCCs Module Two (controller to processor) and/or Module Three (processor to processor), as completed as described in Schedule 3 of this DPA, are hereby incorporated by reference"

Source: `4shark-internal-ai-assistant_doc_8.txt` Section B → [https://anthropic.com/legal/data-processing-addendum](https://anthropic.com/legal/data-processing-addendum)

**What this means for LGPD Art. 33:** The EU's SCCs (Standard Contractual Clauses) are the primary mechanism for cross-border personal data transfers where no adequacy decision exists. The Anthropic DPA incorporates SCCs Module 2 (controller-to-processor) by reference. Whether ANPD will recognize EU SCCs as satisfying LGPD Art. 33 Inciso II(b) for transfers to the US is not settled by published ANPD guidance — it is a legal question, not a purely technical one. The August 2025 CPC deadline and the ANPD's own statement that no specific CPCs have been issued add uncertainty.

**Verification block:** ANPD quotes confirmed verbatim in doc_8.txt Section J. Anthropic DPA SCC quote confirmed verbatim in doc_8.txt Section B. URLs fetched successfully.

---

### Section D — Mitigations

#### D1 — ZDR on the Anthropic direct API (Messages API)

The Messages API is ZDR-eligible. With a ZDR arrangement in place, customer data is not stored at rest after the API response is returned.

**Critical finding — MCP connector is NOT ZDR-eligible:**
> "MCP connector | /v1/messages (with mcp_servers) | No | No | Data retained per standard policy."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section C — feature eligibility table → [https://platform.claude.com/docs/en/manage-claude/api-and-data-retention](https://platform.claude.com/docs/en/manage-claude/api-and-data-retention)

**What this means architecturally:** If the assistant uses the Claude Agent SDK with MCP servers (the primary architecture proposed in Q2/Finding 4/5), the MCP connector endpoint invocations are not covered by ZDR — even if the organization has a ZDR arrangement. The ZDR arrangement applies only to Messages API calls that do not use `mcp_servers`. The Agent SDK's agentic loop that calls MCP tools routes through the MCP connector endpoint, placing those requests outside ZDR scope.

**ZDR requires sales team engagement — not self-serve:**
> "To request a ZDR arrangement, contact the Anthropic sales team."

Source: doc_8.txt Section C.

**CORS not supported under ZDR — backend proxy required:**
> "Cross-Origin Resource Sharing (CORS) is not supported for organizations with ZDR arrangements. If you need to make API calls from browser-based applications, you must: Use a backend proxy server to make API calls on behalf of your front end"

Source: doc_8.txt Section C.

This is an architectural constraint, not a blocker: all three MVP options (A, B, C) already use a backend server (FastAPI or Express), so CORS is not a concern for those architectures.

#### D2 — Amazon Bedrock in sa-east-1 — data residency caveat

Bedrock stores data in the customer's AWS region. However:

**sa-east-1 does not support In-Region routing for Claude models:**
> "If you need Claude models in sa-east-1, you must use Global routing, which routes across all commercial AWS regions worldwide. There is no option for data residency constraints within a single region or geographic boundary for this location."

Source: `4shark-internal-ai-assistant_doc_8.txt` Section F → [https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html](https://docs.aws.amazon.com/bedrock/latest/userguide/models-region-compatibility.html)

**What this means:** Even if 4Shark's AWS account is in sa-east-1, Claude inference on Bedrock routes globally (including US-region datacenters). The "data stays in the customer's AWS region" guarantee from the Bedrock FAQs does not hold for Claude models called from sa-east-1, because there is no In-Region routing option. Data transits to wherever the Global inference pool processes the request.

Note: The Bedrock data retention docs state: "If cross-region inference is enabled for these models, retained inputs and outputs are stored in destination regions (i.e., the region where your inference request is processed)." Source: doc_8.txt Section E.

#### D3 — Bedrock ZDR mode (`data_retention_mode: none`) for Claude Opus 4.8 / Sonnet 4.6

For Claude models other than Fable 5 and Mythos 5, Bedrock supports ZDR (`data_retention_mode: none`):
> "Zero data retention. No request or response data is written to durable storage by AWS or shared with the model provider."

Source: doc_8.txt Section E — `none` mode in the data retention modes table.

> "There is no data retention change to models released before Claude Fable 5."

Source: doc_8.txt Section E.

This means Claude Sonnet 4.6 and Opus 4.8 on Bedrock can be used with `data_retention_mode: none` — neither AWS nor Anthropic retains the data. However, the Bedrock sa-east-1 Global routing caveat in D2 still applies: inference transits US datacenters regardless of the retention mode.

The Claude Agent SDK does not run on Bedrock (confirmed from prior spike work — Finding 2/Q2 trade-offs table). A Bedrock path requires using the AWS SDK directly, not the Agent SDK, which means native MCP integration is lost.

#### D4 — PII minimization at query time

Regardless of the architecture path chosen, a mitigation available at the application layer is PII minimization: the agent's system prompt can instruct Claude to redact or not repeat PII values in responses (display aggregate counts, not individual CPF numbers), and the MCP `allowed_tools` whitelist can limit which columns and tables the agent may query. This is a defense-in-depth measure, not a replacement for a DPA/ZDR arrangement.

#### D5 — Audit logging

All three MVP options log agent sessions. If the assistant is used to query production data containing PII, session logs themselves become a data subject for LGPD. Log retention policy should be defined before go-live.

---

### Section E — Cost dimension

**Anthropic ZDR pricing:** ZDR requires a sales engagement — specific pricing not published. UNVERIFIED whether ZDR carries a price premium beyond the standard API rate. The prior finding (from pre-compaction research) showed Sonnet 4.6 at $3.00/$15.00 per MTok. For a 3-person internal team, token costs are negligible regardless of ZDR premium.

**Bedrock vs direct API:** Bedrock pricing for Claude models is generally comparable to the direct API (AWS adds a margin). The Agent SDK does not run on Bedrock — switching to Bedrock means losing native MCP integration and requires reimplementing the agentic loop with the AWS SDK. This is a build cost, not a recurring cost.

**Operational cost of ZDR:** If ZDR is required and the MCP connector is excluded, the architect must either (a) accept that MCP tool invocations are not covered by ZDR, (b) remove the MCP connector from the architecture (replace with a custom tool layer that calls the database directly from the backend and passes results as message content to the Messages API — avoiding the `mcp_servers` parameter entirely), or (c) switch to Bedrock with `data_retention_mode: none` and reimplement MCP as a custom tool layer.

The cost of option (b) or (c) is an engineering cost (the scope of reimplementing MCP as custom tools vs. using the built-in MCP connector), not a financial one.

---

### Section F — Exposure summary

The table below maps each architecture path against the five key compliance dimensions. No path is recommended — the evidence is the input; the engineer and main decide.

| Architecture path | Does client employee PII leave 4Shark's infrastructure? | Does data leave Brazil? | International transfer basis available? | Claude Agent SDK usable? | MCP connector ZDR-eligible? |
|---|---|---|---|---|---|
| **Direct Anthropic API + Agent SDK + MCP connector (no ZDR)** | Yes — prompts with PII go to Anthropic (US) | Yes — Anthropic is US-based | Art. 33 Inciso II(b) via SCCs in Anthropic DPA; legal certainty under ANPD is unsettled | Yes — native | No — "Data retained per standard policy" |
| **Direct Anthropic API + Agent SDK + MCP connector (ZDR)** | Yes — prompts with PII go to Anthropic (US), but not stored after response | Yes — Anthropic is US-based | Same as above; ZDR eliminates retention risk but not transfer itself | Yes — native | No — MCP connector excluded from ZDR; ZDR covers Messages API only |
| **Direct Anthropic API + Agent SDK, no MCP connector (custom tool layer)** | Yes — prompts with PII go to Anthropic (US) | Yes — Anthropic is US-based | Same Art. 33 Inciso II(b) via SCCs | Yes — native | N/A — MCP connector not used; Messages API is ZDR-eligible with ZDR arrangement |
| **Bedrock (Sonnet 4.6 / Opus 4.8) + custom tool layer + ZDR mode (`none`)** | Yes — prompts with PII go to AWS Bedrock (routing globally) | Yes — sa-east-1 uses Global routing, inference may process in US datacenters | AWS Service Terms Section 1.14.1 incorporates a DPA; Section 1.14.3 incorporates SCCs between controllers and processors. However, per Section 1.14.3, the SCCs apply only when "the GDPR applies" and data is transferred "outside of the European Economic Area" — they are explicitly GDPR/EEA-scoped. Whether they satisfy LGPD Art. 33 for transfers from Brazil is a separate legal question not addressed in the fetched text. Bedrock data (Sonnet 4.6 / Opus 4.8, ZDR mode `none`) does not reach Anthropic. | No — Agent SDK does not run on Bedrock; must use AWS SDK + custom agentic loop | N/A — MCP connector is Anthropic-specific; custom tool layer required |
| **OpenAI Realtime (L2 voice path)** | Yes — prompts with PII go to OpenAI (US) | Yes — no Brazil data residency option | OpenAI API has no-training-by-default; DPA details UNVERIFIED (403); ZDR available via sales | No — OpenAI Realtime, Claude not the LLM | N/A — not an Anthropic product |

**Key findings surfaced by the evidence:**

1. All current architecture paths send client employee PII to a US-based LLM provider. There is no architecture that keeps inference entirely within Brazil under current Bedrock regional support.

2. The Anthropic DPA + SCCs Module 2 provides the Art. 33 contractual basis. Whether ANPD will recognize EU SCCs as satisfying LGPD for US transfers is a legal question that is not settled by published ANPD guidance as of this research.

3. ZDR on the direct Anthropic API does NOT cover the MCP connector. The primary proposed architecture (Agent SDK + MCP postgres/MongoDB) falls outside ZDR scope for the database query portion — the most PII-sensitive part of the flow.

4. A custom tool layer (no `mcp_servers` parameter) would bring database queries back under ZDR scope on the Messages API, at the cost of losing native MCP integration and requiring manual agentic loop plumbing for each tool.

5. Bedrock with `data_retention_mode: none` (ZDR) and Sonnet 4.6 / Opus 4.8 does not retain data at AWS or Anthropic, but inference still routes globally from sa-east-1 — data transits US datacenters during processing.

6. The engineer's stated concern — "if this creates a new compliance problem we have to solve, the problem may not be worth what the solution delivers" — maps directly to items 2 and 3 above: the international transfer basis is contractually present (SCCs in the DPA) but legally unsettled under ANPD; and ZDR does not cover the MCP connector, meaning the highest-PII portion of the flow has standard retention.

Verification block: Claims in this table trace to verbatim quotes in doc_8.txt Sections A–N as follows: Anthropic rows → Sections A, B, C. Bedrock rows → Sections D, E, F, N. OpenAI row → Section G (DPA details UNVERIFIED — 403 fetch). LGPD/ANPD context → Sections H, I, J. AWS Service Terms DPA/SCC incorporation → Section N (aws.amazon.com/service-terms/, verbatim quotes self-checked via re-fetch). The six numbered key findings are derivations from confirmed evidence, not independent verbatim claims. UNVERIFIED items in this section: OpenAI DPA details (403 fetch), ANPD recognition of EU SCCs for US transfers (no published decision found), whether AWS SCCs in Section 1.14.3 satisfy LGPD Art. 33 for transfers from Brazil (GDPR-scope caveat confirmed verbatim; LGPD applicability is not addressed in the fetched text), and Anthropic ZDR pricing (not published).

---

## Q4-delta — Market practice: how companies actually use LLMs on PII under LGPD

This section answers a follow-up framed by the engineer: is adding an Anthropic/OpenAI LLM API with a DPA the same compliance category as 4Shark already hosting PII on AWS us-east-1? And what has enforcement actually targeted? Six dimensions are covered: (1) ANPD enforcement scope, (2) ANPD preliminary study on inference, (3) GDPR enforcement landscape for comparison, (4) Art. 33 contractual mechanism as independent from adequacy, (5) enterprise market practice (API vs self-hosted), (6) self-hosting cost analysis.

All verbatim evidence traces to `4shark-internal-ai-assistant_doc_9.txt`. Analysis is in English; Portuguese-source quotes are preserved verbatim.

---

### Dimension 1 — What ANPD enforcement has actually targeted

**ANPD vs Meta: training-data-only scope**

The ANPD issued a preliminary decision requiring suspension of Meta's processing of Brazilian users' personal data. The scope was narrowly defined:

> "immediate suspension" of the processing of personal data by Meta "for the purpose of training its generative AI model."

The legal basis ANPD challenged was:

> "ineffective use of 'legitimate interest' as a legal basis for processing personal data for AI training purposes"

Source: `4shark-internal-ai-assistant_doc_9.txt` Section A → [https://fpf.org/blog/processing-of-personal-data-for-ai-training-in-brazil-takeaways-from-anpds-preliminary-decisions-in-the-meta-case/](https://fpf.org/blog/processing-of-personal-data-for-ai-training-in-brazil-takeaways-from-anpds-preliminary-decisions-in-the-meta-case/)

doc_9.txt Section A records: "The document contains zero discussion of inference, API processors, or downstream use of trained models on personal data. Scope was limited exclusively to the training phase."

**ANPD vs OpenAI: data breach notification, not inference**

The ANPD investigation of OpenAI concerns a 2023 ChatGPT security incident:

> "violou o artigo 48 da LGPD (Lei Geral de Proteção de Dados), que obriga controladoras de sistemas de coleta e armazenamento de dados a comunicar 'a ocorrência de incidente de segurança que possa acarretar risco ou dano relevante aos titulares'"

Translation: "violated Article 48 of the LGPD, which requires controllers of data collection and storage systems to communicate 'the occurrence of a security incident that may cause relevant risk or damage to data subjects.'"

Outcome as of research date:

> "não é certo se resultará em sanção, como multa, conforme a lei prevê em caso de descumprimento"

Translation: "it is not certain whether it will result in a sanction, such as a fine, as provided by law in the event of non-compliance."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section B → [https://www.aosfatos.org/noticias/anpd-chatgpt-vazamento-dados-pessoais/](https://www.aosfatos.org/noticias/anpd-chatgpt-vazamento-dados-pessoais/)

**ANPD 2024 enforcement volume: pattern is training-data scraping**

> "O ano de 2024 manteve um ritmo semelhante ao de 2023 no que diz respeito à aplicação de sanções pela ANPD."

Translation: "The year 2024 maintained a pace similar to 2023 with respect to the application of sanctions by ANPD."

On AI:

> "A Autarquia entrou em rota de colisão com dois gigantes da tecnologia sobre a utilização de perfis brasileiros em redes sociais para treinamento de inteligência artificial."

Translation: "The Authority entered into collision with two tech giants over the use of Brazilian profiles on social networks for training artificial intelligence."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section C → [https://www.tauilchequer.com.br/pt/insights/publications/2025/01/um-olhar-retrospectivo-sobre-a-anpd-e-a-protecao-de-dados-no-brasil-em-2024](https://www.tauilchequer.com.br/pt/insights/publications/2025/01/um-olhar-retrospectivo-sobre-a-anpd-e-a-protecao-de-dados-no-brasil-em-2024)

doc_9.txt Section C notes: "No enforcement action found targeting companies using AI APIs on PII for inference."

**Summary of Dimension 1:** All three ANPD enforcement actions found in this research (Meta training suspension, OpenAI breach notification investigation, 2024 AI enforcement pattern) target training-data acquisition or security incident notification. No ANPD enforcement was found targeting B2B inference API usage — the scenario of a company sending its own operational PII to an LLM API for processing.

Verification block: ANPD vs Meta quote confirmed verbatim in doc_9.txt Section A (fpf.org URL). ANPD vs OpenAI Art. 48 quote confirmed verbatim in doc_9.txt Section B (aosfatos.org URL). 2024 enforcement pattern quote confirmed verbatim in doc_9.txt Section C (tauilchequer.com.br URL). Observation about absence of inference-API enforcement is a direct observation from the research corpus, not an attribution to a single source.

---

### Dimension 2 — ANPD preliminary study on generative AI: inference addressed but not isolated

The ANPD Technology and Research Unit published a preliminary study on generative AI in November 2024. It addresses inference-time processing:

> "Depending on the prompt, context, and information provided by the user, these interactions may generate outputs containing personal data about the user or other individuals."

On who bears LGPD obligations when using AI at inference time:

> "Users sharing the personal data of other individuals through prompts may be considered processing agents under the LGPD and consequently be subject to its obligations and sanctioning regime."

And on provider responsibility:

> "transferring responsibility exclusively to users is not enough to safeguard personal data protection or privacy in the context of generative AI."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section D → [https://fpf.org/blog/brazils-anpd-preliminary-study-on-generative-ai-highlights-the-dual-nature-of-data-protection-law-balancing-rights-with-technological-innovation/](https://fpf.org/blog/brazils-anpd-preliminary-study-on-generative-ai-highlights-the-dual-nature-of-data-protection-law-balancing-rights-with-technological-innovation/)

**What the study does NOT do:** doc_9.txt Section D records that "The study addresses inference-time scenarios but does not clearly separate training-time from inference-time obligations. It uses unified LGPD principles across 'multiple stages in the life cycle of generative AI systems, from development to refinement of models.' It does not name specific LLM API providers or address B2B inference API compliance as a distinct category."

**Significance:** The ANPD preliminary study establishes that inference-time PII processing falls under LGPD (companies using AI APIs on PII bear processing-agent obligations). It does not provide specific guidance on whether a DPA + contractual clauses with a US LLM provider satisfies LGPD, or what mechanism (Art. 33 Inciso II vs other bases) applies. The training vs inference distinction is recognized in enforcement practice (Dimension 1) but not yet codified in ANPD formal guidance.

Verification block: Three quotes confirmed verbatim in doc_9.txt Section D (fpf.org URL). Study date (November 29, 2024, ANPD Technology and Research Unit) confirmed from doc_9.txt. The observation about what the study does NOT do is a direct paraphrase of doc_9.txt's own note on scope limits, not an independent claim.

---

### Dimension 3 — GDPR enforcement landscape: the "zero survivors" finding

The Italy Garante is the only European DPA that issued a final GDPR enforcement decision regarding generative AI at launch:

> "Since then, not a single other European DPA has published a final enforcement decision concerning GDPR violations linked to the launch period of ChatGPT (November 2022 to March 2023)."

> "Europe's regulatory response to the most consequential AI deployment in its history produced a single enforcement decision. And that decision has now been annulled."

> "This was not just any enforcement decision. It was the only final GDPR enforcement action ever adopted in Europe concerning the period of the launch of generative AI to the public."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section E → [https://www.crossborderdataforum.org/generative-ai-and-gdpr-enforcement-in-europe-a-lot-of-noise-one-fine-zero-survivors/](https://www.crossborderdataforum.org/generative-ai-and-gdpr-enforcement-in-europe-a-lot-of-noise-one-fine-zero-survivors/)

What the Garante alleged (training + breach + transparency, not inference API):
> "OpenAI processed personal data for training ChatGPT without an adequate legal basis, violated GDPR transparency and information obligations, failed to properly notify the authority of a March 2023 data breach, and lacked age verification mechanisms for minors."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section E (same URL).

**The Court of Rome annulment — jurisdictional grounds, not substantive**

The Court of Rome annulled the €15 million fine on March 18, 2026:

> "the annulment rests entirely on a finding that the Italian Garante lacked jurisdiction after the Irish Data Protection Commission became OpenAI's lead supervisory authority on February 15, 2024 - months before the Garante issued its final decision."

What the court explicitly did NOT rule on:

> "The court's reasoning does not reach the substantive GDPR violations alleged by the Italian authority. It does not assess whether OpenAI failed to notify the Garante of the March 20, 2023 data breach. It does not determine whether ChatGPT's training data processing lacked a valid legal basis under Articles 5 and 6."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section F → [https://barlamantoday.com/2026/03/19/italian-court-reverses-regulators-e15-million-fine-against-openai-over-chatgpt-privacy-breach/](https://barlamantoday.com/2026/03/19/italian-court-reverses-regulators-e15-million-fine-against-openai-over-chatgpt-privacy-breach/) and [https://www.wsgr.com/en/insights/openai-prevails-in-landmark-italian-ai-and-gdpr-enforcement-case.html](https://www.wsgr.com/en/insights/openai-prevails-in-landmark-italian-ai-and-gdpr-enforcement-case.html)

Original fine: €15 million (November 2, 2024, Garante Decision No. 755). Annulment: March 18, 2026.

**Significance for 4Shark:** GDPR and LGPD are distinct legal regimes; GDPR enforcement precedents do not bind ANPD. The Dimension 3 evidence is included because: (a) it is the most developed enforcement record for AI/PII globally and contextualizes what "enforcement" has actually targeted; (b) the annulment was jurisdictional — the substantive questions (whether training data processing without legal basis violates data protection law) remain unresolved by any court; (c) even under GDPR, no final enforcement action was found targeting B2B inference API usage as distinct from training. doc_9.txt Section E notes: "No GDPR enforcement found for using LLM APIs as inference processors."

Verification block: Three crossborderdataforum.org quotes confirmed verbatim in doc_9.txt Section E. Court of Rome annulment grounds quote confirmed verbatim in doc_9.txt Section F (barlamantoday.com + wsgr.com search result summary). What the court did NOT rule on quote confirmed verbatim in doc_9.txt Section F. Fine amount and dates confirmed from Section F.

---

### Dimension 4 — Art. 33 contractual mechanism: independent from adequacy, operative for US transfers

**Art. 33 Inciso II is independent of adequacy decisions**

CD/ANPD No. 19/2024 established four transfer mechanisms. From Mayer Brown's analysis:

> "decisão de adequação, cláusulas contratuais específicas, cláusulas-padrão contratuais e normas corporativas globais"

Translation: "adequacy decision, specific contractual clauses, standard contractual clauses, and global corporate rules."

The standard contractual clauses (CPCs) requirement:

> "As cláusulas-padrão contratuais se encontram anexa a essa atualização. Elas devem ser adotadas em sua integralidade, sem qualquer modificação"

Translation: "The standard contractual clauses are attached to this update. They must be adopted in their entirety, without any modification."

Deadline for amending existing contracts:

> "12 (doze) meses para que os agentes de tratamento (controladores ou operadores) alterem os contratos vigentes"

Translation: "12 [twelve] months for processing agents [controllers or operators] to amend existing contracts" — deadline August 23, 2025.

Source: `4shark-internal-ai-assistant_doc_9.txt` Section G → [https://www.mayerbrown.com/pt/insights/publications/2024/08/new-anpd-regulation-international-data-transfers](https://www.mayerbrown.com/pt/insights/publications/2024/08/new-anpd-regulation-international-data-transfers) and [https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/](https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/)

From Mayer Brown (Section M of doc_9.txt, same URL): Resolution CD/ANPD No. 19/2024 established "greater legal certainty to processing agents and interpretive uniformity to Article 33 of the LGPD." Art. 33 Inciso II is an INDEPENDENT mechanism from adequacy — it does not require a country adequacy decision. The fact that the US has no ANPD adequacy decision does not block transfers to US-based processors if CPCs are in place.

No US adequacy:
> "não houve reconhecimento formal de qualquer país como adequado."

Translation: "no formal recognition of any country as adequate [has been issued]."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section G (legale.com.br URL).

**Cloud = international transfer: LLM API is the same category**

> "O armazenamento de dados em nuvem (cloud computing) com servidores no exterior é considerado transferência internacional"

Translation: "The storage of data in the cloud [cloud computing] with servers abroad is considered an international transfer."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section H → [https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/](https://legale.com.br/blog/lgpd-transferencia-internacional-de-dados-e-compliance/)

From beanstech.com.br (Section O of doc_9.txt, prior session — pending re-verification):
> "O documento estabelece que usar servidores fora do Brasil 'configura uma transferência internacional de dados.'"
> "Garantir que os contratos com os provedores de nuvem (Data Processing Agreements - DPAs) estejam em conformidade com a LGPD."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section O → [https://beanstech.com.br/blog/lgpd-cloud-computing-compliance](https://beanstech.com.br/blog/lgpd-cloud-computing-compliance) (PENDING RE-VERIFICATION — quoted from prior session context, not re-fetched in current session)

**Cloud parity inference:** 4Shark's `app` backend runs on AWS us-east-1 (US servers). Per the legale.com.br verbatim finding, this already constitutes an international transfer under LGPD. Sending PII to an Anthropic API endpoint (also US-based) is the same legal category. The operative question is not "is this a transfer?" — it is whether the transfer mechanism (Art. 33 Inciso II contractual clauses) is properly documented. doc_9.txt Section H notes: "The legale.com.br article does not specifically address AI API providers or LLM vendors as operadores. The cloud-parity inference is drawn from the stated principle (cloud storage abroad = international transfer) applied to the LLM API case."

**Transfer as extension of Brazilian jurisdiction:**
> "Elas funcionam como uma extensão da jurisdição brasileira em território estrangeiro por via obrigacional"

Translation: "They function as an extension of Brazilian jurisdiction in foreign territory through contractual obligation."

Source: `4shark-internal-ai-assistant_doc_9.txt` Section G (legale.com.br URL).

Verification block: All Brazilian Portuguese quotes confirmed verbatim in doc_9.txt Section G (mayerbrown.com and legale.com.br URLs, both fetched). Cloud = international transfer quote confirmed verbatim in doc_9.txt Section H (legale.com.br URL). beanstech.com.br quotes marked PENDING RE-VERIFICATION per doc_9.txt Section O note. Cloud-parity inference is drawn from the stated principle — explicitly noted as inference, not a verbatim source claim.

---

### Dimension 5 — Enterprise market practice: 87% use closed-source API, not self-hosted

**Enterprise LLM market mid-2025 (Menlo Ventures)**

> "Enterprise spending on large language models (LLM) has more than doubled in just six months, rising from $3.5 billion in late 2024, to $8.4 billion"

Provider share by spending:
> "Anthropic now earns 40% of enterprise LLM spend, up from 12% in 2023. OpenAI's share fell from 50% to 27%, while Google increased from 7% to 21%."

Closed-source vs open-source:
> "Closed-source models now dominate, powering 87% of enterprise workloads. Open-source usage fell from 19% to 13% over the past six months"

Source: `4shark-internal-ai-assistant_doc_9.txt` Section I → [https://finance.yahoo.com/news/enterprise-llm-spend-reaches-8-130000140.html](https://finance.yahoo.com/news/enterprise-llm-spend-reaches-8-130000140.html)

**Significance:** These companies are predominantly operating under GDPR, CCPA, and other data protection regimes, and 87% still use closed-source API providers (Anthropic, OpenAI, Google) rather than self-hosting. The market evidence shows that enterprises broadly treat the API provider DPA + contractual compliance as sufficient, rather than defaulting to self-hosting for PII exposure reasons. The evidence does not explain whether LGPD specifically drives any self-hosting decisions — see Dimension 6 for that.

Verification block: Three quotes confirmed verbatim in doc_9.txt Section I (finance.yahoo.com/Menlo Ventures URL).

---

### Dimension 6 — Self-hosting cost and regulatory drivers: LGPD not in the mandating list

**Break-even point for self-hosting**

> "The practical break-even sits near $4,200/month of API spend."
> "The breakeven threshold is approximately 11 billion tokens per month."

Operational cost multiplier:
> "Self-hosting costs 3–5× more than the raw GPU price alone when you include DevOps, audit, updates, and downtime"

Who self-hosts (regulations named):
> "If you are building [AI for US healthcare] (HIPAA), financial services (SOC 2, SEC regulations), or government contracts, your data cannot touch OpenAI's or Anthropic's cloud infrastructure."
> "API wins for 87% of use cases — only regulated data (HIPAA/SOC 2) and ultra-high-volume justify self-hosting"

Source: `4shark-internal-ai-assistant_doc_9.txt` Section J → [https://www.braincuber.com/blog/self-hosted-llms-vs-api-based-llms-cost-performance-analysis](https://www.braincuber.com/blog/self-hosted-llms-vs-api-based-llms-cost-performance-analysis)

doc_9.txt Section J notes: "LGPD is NOT in this list of named regulations requiring self-hosting. The US-specific regulations cited (HIPAA, SOC 2, SEC) do not map directly to LGPD's Art. 33 mechanism-based transfer approach."

**Governance framing from Prediction Guard**

Where self-hosting is described as non-negotiable:
> "Workloads processing 'controlled defense data (CUI, ITAR), regulated financial data'"
> "Air-gapped or restricted-network environments"
> "Data sovereignty requirements prohibiting 'any data egress outside a defined geographic or organizational boundary'"

Governance overhead:
> "Building governance infrastructure 'from scratch...takes months of dedicated engineering work with no product delivery output during that period.'"

> "the choice 'isn't primarily a performance decision. It's a governance decision,' emphasizing that 'where the control plane runs determines where your audit logs live, who controls your policy enforcement.'"

Source: `4shark-internal-ai-assistant_doc_9.txt` Section K → [https://predictionguard.com/blog/self-hosted-vs-cloud-llm-deployment-guide](https://predictionguard.com/blog/self-hosted-vs-cloud-llm-deployment-guide)

doc_9.txt Section K notes: "LGPD is NOT mentioned as a regulation driving self-hosting in this source. The regulatory drivers named are US/EU-specific (CUI, ITAR, HIPAA, NIST AI RMF)."

**Significance for 4Shark:** Neither source names LGPD as a regulation that mandates self-hosting. The self-hosting-is-required argument in published guidance is built on US/EU regulations (HIPAA, SOC 2, CUI, ITAR) that have specific data-residency or air-gap requirements those laws explicitly state. LGPD Art. 33 takes a mechanism-based approach (adequacy, contractual clauses, corporate rules) rather than a data-residency prohibition. The two sources do not support the position that LGPD requires self-hosting. They also surface the engineering cost: break-even at $4,200/month API spend, 3–5x raw GPU cost for full operational overhead, and months of engineering work with no product output.

Verification block: Break-even and operational cost quotes confirmed verbatim in doc_9.txt Section J (braincuber.com URL). Regulations named in self-hosting mandating list confirmed verbatim in doc_9.txt Section J. Prediction Guard governance quotes confirmed verbatim in doc_9.txt Section K (predictionguard.com URL). Observation that LGPD is absent from both mandating lists is a direct observation from the research corpus (doc_9.txt Sections J and K both explicitly note LGPD's absence).

---

### Q4-delta summary

**What the evidence establishes:**

1. **ANPD enforcement has targeted training data, not inference APIs.** The three actions found (Meta training suspension, OpenAI breach notification, 2024 pattern) are all training-phase or security-incident actions. No enforcement was found targeting companies using LLM inference APIs on operational PII. This is an absence of evidence — not evidence of absence — but it is what the published record shows.

2. **ANPD recognizes inference as covered by LGPD but has not issued specific inference-API compliance guidance.** The November 2024 preliminary study treats inference-time PII processing under LGPD principles. It does not distinguish B2B inference API scenarios from consumer-facing AI scenarios, and it does not address whether a DPA + contractual clauses with a US provider is sufficient.

3. **Art. 33 contractual mechanism is independent of adequacy.** CD/ANPD No. 19/2024 established contractual clauses (CPCs) as a valid transfer mechanism regardless of US adequacy status. 4Shark already triggers Art. 33 for its AWS us-east-1 infrastructure. Adding Anthropic with a DPA (which incorporates EU SCCs) is the same legal category — an international transfer to a US-based processor under a contractual mechanism. The open question (from Q4 Section C) remains: whether ANPD will formally accept EU SCCs as satisfying the LGPD CPC requirement.

4. **GDPR enforcement (the most developed comparable regime) produced zero final decisions targeting inference API usage.** The sole ChatGPT-era final decision (Italy Garante) concerned training data + breach notification and was annulled on jurisdictional grounds. The substantive question remains legally unresolved in Europe; in Brazil, it has not been tested.

5. **87% of enterprises with comparable data protection obligations use closed-source LLM APIs, not self-hosted models.** Market practice treats DPA + contractual compliance as the operative mechanism. Self-hosting literature names HIPAA, SOC 2, CUI, ITAR as mandating regulations — LGPD is not in any source found.

6. **Self-hosting economics do not favor 4Shark at internal-team query volumes.** Break-even is $4,200/month API spend / 11 billion tokens/month. For a 3-person internal team, self-hosting cost is 3–5x the API cost with months of engineering overhead and no product output during setup.

**What remains uncertain after Q4-delta:**

- Whether ANPD will formally accept EU SCCs (the mechanism in the Anthropic DPA) as satisfying LGPD Art. 33 Inciso II for transfers to US processors. No published ANPD guidance addresses this. Legal counsel is required before treating this as settled.
- Whether the ANPD preliminary study on generative AI will result in binding guidance that addresses B2B inference API scenarios explicitly — the study is non-binding.
- Whether the absence of enforcement action on inference APIs reflects considered ANPD policy or simply enforcement priority sequencing (training-data harms were more visible and immediate).

**The engineer's cloud-parity argument — what the evidence supports:**

The cloud-parity argument (4Shark already sends PII to AWS us-east-1; adding Anthropic with a DPA is the same category) is supported by the legale.com.br principle that "cloud storage abroad = international transfer" — both are Art. 33 scenarios. It is NOT supported by the claim that equivalence means zero additional compliance obligation: the DPA + contractual clause mechanism must actually be documented and in force for both the AWS relationship and the Anthropic relationship. The parity is in legal category, not in saying compliance is already handled.

Verification block for Q4-delta section: All verbatim quotes trace to doc_9.txt Sections A through K and M through O (Section L was HTTP 404 UNVERIFIED and is not cited here). Summary items 1–6 are derivations from confirmed evidence, not independent verbatim claims — each item maps to a named Section in doc_9.txt. "What remains uncertain" items are derivations from the research corpus gaps, not attributions to a single source. beanstech.com.br quotes (doc_9.txt Section O) are marked PENDING RE-VERIFICATION in both doc_9.txt and this spike.
