# PLAN — 4Shark Internal AI Assistant

> Status: **planning in progress** (deliberation log). Research lives in `SPIKE.md` (same directory) + auxiliary `doc_1.txt`…`doc_9.txt`. This file records the engineer's decisions and the open questions as of the session date. It is NOT yet a full implementation plan — several technical decisions remain open (see § Open Decisions).

## Goal

An internal, voice-capable AI assistant for the 4Shark support team, built on top of the Claude Agent SDK. The user opens a per-environment URL reachable only over the 4Shark VPN, asks questions by voice, and the assistant queries production data (read-only), returns answers, and (later) generates spreadsheets/charts and predictions. Employees only — never clients (at least initially).

## Decisions taken (2026-06-25)

### D1 — Voice tier: **L1 push-to-talk** (not full "redonda" L2)
- The user presses to talk; the waveform animates from their own mic (Web Audio FFT, browser-native); the assistant replies with text on screen + a TTS voice reading it, with a toggle to turn voice off.
- **Rationale:** L1 keeps the backend architecture intact (Claude Agent SDK + tools survive unchanged) and costs only "a few days" over a text MVP. L2 ("redonda" — free speech, barge-in, streaming-synced text+voice) is NOT an increment — it is an architecture replacement: adopting LiveKit/Pipecat/OpenAI-Realtime displaces the Agent SDK and forces re-implementing every tool as a framework-native handler. That is the "doubles the timeline" the engineer ruled out.
- **What L1 delivers of the original vision:** live mic waveform, spoken answer, on-screen text, voice toggle. **What it defers:** free speech (L1 has a button), barge-in, and perfectly streaming-synced text+voice (L1 reads after the text is ready).
- L2 is recorded as a possible future phase, to be decided with real usage. See `SPIKE.md` § Q1-delta.
- pt-BR voice path (confirmed verbatim in research): Deepgram Nova-3 (STT) + ElevenLabs Flash v2.5 (TTS).

### D2 — Compliance / LGPD: **not a blocker** — same category 4Shark already manages with AWS
- 4Shark already sends 100% of client-employee PII to a US provider (AWS, `app` in us-east-1). That is already an international transfer to a foreign sub-processor under LGPD, handled via DPA + contractual clauses. Adding Anthropic (with a DPA that incorporates EU SCCs) is the **same legal category** — not a new scenario.
- Market evidence (see `SPIKE.md` § Q4-delta): ANPD/GDPR enforcement targeted model *training*, not inference-API usage; 87% of enterprises use closed-source LLM APIs rather than self-hosting; self-hosting is driven by HIPAA/SOC2/ITAR, not LGPD; Art. 33 Inciso II (contractual clauses) is an autonomous transfer basis that does not depend on a US adequacy decision.
- **Residual (not a blocker, a homework item):** whether ANPD formally accepts EU SCCs as the LGPD standard clause for US transfers is not settled by published guidance — same open question that already applies to the AWS relationship. Requires legal/DPO confirmation, not engineering.
- Technical mitigation to keep the highest-PII step (the DB query) under ZDR: replace the MCP connector with a custom tool layer (no `mcp_servers` param), keeping the Agent SDK. Add PII minimization in the system prompt + restricted tables + audit logging. See `SPIKE.md` § Q4 D1/D4.

## Architecture (emerging — from the spike, subject to the open decisions below)

- **UI:** React + a voice-waveform library (candidates in `SPIKE.md` § Q1: react-ai-voice-visualizer / Vercel Persona / LiveKit Agents UI). L1 push-to-talk.
- **Agent brain:** Claude Agent SDK (same runtime as Claude Code), wrapped behind a backend HTTP/WebSocket API.
- **Data access:** read-only to Postgres (RDS) and MongoDB. MCP servers OR a custom tool layer (the ZDR consideration in D2 pushes toward a custom tool layer for the query path).
- **Voice (L1):** browser MediaRecorder → `/api/stt` (Deepgram Nova-3) → agent → response text → ElevenLabs TTS readback (toggle).
- **Deploy / access:** ECS Fargate in a private subnet, internal ALB (scheme=internal), security group restricted to the VPN CIDR, Route53 private hosted zone with one record per environment (`ia-staging.app.4shark.com`, `ia.app.4shark.com`, …). Environment known via the ECS task definition env var. Keycloak SSO as an optional second auth layer.

## Open decisions (still to make)

1. **File generation (Q3, interrupted before deciding):** Anthropic `code_execution` (zero infra, not-ZDR) vs a custom Python MCP/tool on ECS (data stays home, more work) vs defer to post-MVP. Note: the D2 ZDR mitigation (custom tool layer) interacts with this.
2. **Backend language (Q2, deferred to follow Q3):** TypeScript (one language full-stack with the React front) vs Python (native pandas/openpyxl for files/prediction). Decide after #1.
3. **"Prediction" — what it means (most underspecified):** (a) Claude running regression/forecast via code execution, (b) a separate ML model as a tool, or (c) LLM trend analysis over queried data. Needs a definition.
4. **Which tables/collections the agent may read:** business decision, ties to the PII-minimization mitigation.
5. **Keycloak in the MVP or VPN-only first.**
6. **Documents impact (new, this session):** which 4Shark privacy/compliance documents must be updated/created when Anthropic (+ Deepgram/ElevenLabs) become sub-processors — see the open research item below.

## MVP scope (thin slice — see `SPIKE.md` § "MVP scope")

Prove three things: (1) the agent takes a natural-language query, calls a read-only DB tool, returns a streamed result; (2) the L1 waveform animates the states in the browser; (3) the service is reachable on the VPN at the per-environment subdomain and unreachable off-VPN. Voice (STT/TTS), file generation, MongoDB, Keycloak are phase-2 candidates.

## Risks / homework

- **Legal:** confirm EU-SCC acceptance under LGPD Art. 33 for US transfers with legal/DPO; confirm DPAs in force with Anthropic, Deepgram, ElevenLabs; check whether client contracts require authorization/notification to add a new sub-processor.
- **Documents:** update the document set (see open decision #6) — ROPA, sub-processor list, possibly privacy policy + client DPAs, possibly a new DPIA/RIPD.
- **Evidence caveats (from the spike):** LGPD article text was quoted from a secondary site (planalto.gov.br was unreachable) — confirm at planalto before any binding legal decision; Court-of-Rome annulment quotes (GDPR context, non-binding for ANPD) are being re-verified; self-hosting cost figures come from a commercial blog (one reference point).

## Next steps

- Resolve open decisions #1–#5 (continue the point-by-point session).
- Run the focused "documents impact" research (#6) and cross-reference against the docs 4Shark actually maintains.
- When the technical decisions are settled, promote this into a full implementation PLAN (phases + TASKS), or run the plan-researcher → plan-composer pipeline.
