# SPIKE — Encoding Infrastructure Knowledge for AI Coding Agents

**Conducted by:** spike agent
**Date:** 2026-06-26
**Status:** Research complete — pending decisions

---

## Goal

How is the community solving the problem of encoding operational, infrastructure, and environment knowledge for AI coding agents (Claude Code, Cursor, GitHub Copilot, Codex CLI) so the agent acts assertively — without re-discovering context each session?

Specifically, for a team running a multi-tenant white-label SaaS:
- A service catalog (which services exist, what they do)
- A client→URL→environment→deploy-trigger mapping (client X lives at URL Y, environment Z, deploy via command W)
- Deploy procedures (what the agent must do to push to staging vs production)

The core tension: **inline everything** (agent is fast and assertive, but context fills up) vs **load on demand** (context stays lean, but agent may not have what it needs at the moment it acts).

Seven candidate approaches were investigated:
1. Always-loaded instruction files (CLAUDE.md / AGENTS.md / .cursor/rules / copilot-instructions.md)
2. Service catalogs (Backstage catalog-info.yaml) consumed via MCP
3. Structured machine-readable YAML/JSON registries referenced from instruction files
4. Tiered/progressive-disclosure documentation (Skills with body-on-demand)
5. MCP servers for live infra state vs static documentation
6. Runbook-style Skills with deploy-gate frontmatter
7. Multi-tenant / white-label architecture documentation patterns

---

## Method

External community research across official documentation and practitioner writing:
- Fetched Anthropic Claude Code official documentation: memory loading model and Skills system
- Fetched practitioner articles: progressive disclosure patterns, MCP vs CLI token comparison, AGENTS.md Princeton study, Backstage+MCP integration examples
- Fetched multi-tool comparison: CLAUDE.md vs AGENTS.md vs .cursorrules vs copilot-instructions.md
- Searched for multi-tenant environment registry patterns specifically for agent consumption
- Cross-referenced token cost data between sources

All factual claims below are backed by a directly fetched source. Claims that could not be verified from a fetched source are labeled NOT FOUND.

---

## Evidence

### Finding 1: Always-loaded instruction files share a hard instruction budget

**Evidence:**

> "Frontier thinking LLMs can follow ~ 150-200 instructions with reasonable consistency."
> "Claude Code system prompt ≈ 50 instructions already."
— humanlayer.dev/blog/writing-a-good-claude-md

> "Target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."
— code.claude.com/docs/en/memory

> "Frontier LLMs can reliably follow around 150-200 instructions. Claude Code's system prompt already uses about 50 of those, so keep your CLAUDE.md concise."
— deployhq.com/blog/ai-coding-config-files-guide

**Source:** See auxiliary: `agent-infra-knowledge_doc_1.txt` (Anthropic memory docs), `agent-infra-knowledge_doc_2.txt` (humanlayer.dev, alexop.dev), `agent-infra-knowledge_doc_4.txt` (deployhq.com)

**Significance:** The always-loaded file pattern has a concrete ceiling: roughly 100-150 instructions remain after the tool's own system prompt. A service catalog with 20 clients, each with 3 environments and a deploy command, could consume that budget entirely — leaving no room for project conventions. The community has converged on "always-loaded = facts only; procedures go elsewhere."

---

### Finding 2: Tiered loading (Skills / body-on-demand) is the community's primary solution

**Evidence:**

> "Create a skill when you keep pasting the same instructions, checklist, or multi-step procedure into chat, or when a section of CLAUDE.md has grown into a procedure rather than a fact. Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it."
— code.claude.com/docs/en/skills

> "All 17 skills together cost ~1,700 tokens, meaning an agent can be aware of dozens of skills for less context than a single activated skill."
— newsletter.swirlai.com

> "Claude reads the skill description (~100 tokens) at startup; full procedures load only when relevant."
— pulumi.com/blog/top-8-claude-skills-devops-2026/

Three loading tiers confirmed by Anthropic's Skills documentation and independent practitioner sources:
- **Discovery**: description only (~80 tokens per skill); always in context; Claude reads this to decide relevance
- **Activation**: full SKILL.md body (275–8,000 tokens); loads only when skill is invoked or auto-matched
- **Supporting files**: files in the skill directory; loaded on demand when referenced by the body

**Source:** See auxiliary: `agent-infra-knowledge_doc_1.txt` (Anthropic skills docs), `agent-infra-knowledge_doc_2.txt` (swirlai, pulumi)

**Significance:** This directly addresses the inline-vs-load-on-demand tension. A 17-skill toolkit costs 1,700 tokens at the discovery layer — less than most single activated skills. The community answer to "where does the client catalog go?" is: in a Skill's body, not in CLAUDE.md.

The Agent Skills open standard (agentskills.io) was adopted in December 2025 by OpenAI, Google, GitHub, and Cursor. Claude Code skills follow this standard, meaning the pattern is cross-tool (source: deployhq.com, morphllm.com — "400K+ skills indexed within weeks").

---

### Finding 3: MCP is 35x more token-expensive than CLI for static knowledge

**Evidence:**

> "That's a 35x reduction in token usage"
— jannikreinhard.com/2026/02/22/why-cli-tools-are-beating-mcp-for-ai-agents/

Measured comparison (same task, MCP vs CLI approach):
- MCP approach: 145,000 tokens consumed; schema injection alone ~28,000 tokens; ~82,300 tokens remaining in 128K window
- CLI approach: 4,150 tokens consumed; ~121,300 tokens remaining

**Source:** See auxiliary: `agent-infra-knowledge_doc_2.txt` (jannikreinhard.com measurement)

**Significance:** For knowledge that does not change between sessions (service names, client URLs, environment mappings), MCP costs ~35x more tokens than a file-based approach for equivalent information. MCP is justified only when the data is live/dynamic (e.g., current ECS service count, live health status) — not for the stable catalog facts that are the primary target of this investigation.

---

### Finding 4: Service catalogs (Backstage + MCP) are emerging for live infra state, not static facts

**Evidence:**

> Plugin: @backstage/plugin-mcp-actions-backend — exposes catalog as MCP server
> Tools exposed: ListTemplatesAsync, ListSystemsAsync
> "A healthy catalog starts with a clear taxonomy"
> "Deliberately limited to dev environments initially due to auth/rate-limit concerns with write access."
— nitin15j.medium.com

Three Backstage+MCP patterns identified (gokhan-gokalp.com):
1. Structured entity modeling (catalog-info.yaml with owner, system, domain, tags)
2. MCP server as abstraction layer (agent queries catalog; catalog is source of truth)
3. Tool description as semantic contract (description text drives relevance matching)

> "copilots are becoming the primary interface to internal infrastructure knowledge"
— gokhan-gokalp.com

Entity taxonomy used: Domain → System → Component → API (each level owned by a team).

**Source:** See auxiliary: `agent-infra-knowledge_doc_3.txt` (Backstage/MCP evidence)

**Significance:** The Backstage+MCP pattern answers "what exists in the catalog and who owns it" well. It does NOT natively answer "given client X, what is the deploy URL, which environment, and what command do I run?" — that specific client→URL→environment→command mapping has no documented canonical shape in either source. Neither source shows a production-ready example of per-tenant deploy routing via Backstage MCP. The pattern is emerging and limited to read-only dev environments in documented cases.

---

### Finding 5: Deploy procedures belong in Skills with disable-model-invocation: true

**Evidence:**

From Anthropic Skills documentation (code.claude.com/docs/en/skills):

`disable-model-invocation: true`
  → Claude will not auto-load this skill
  → User must type /skill-name explicitly
  → Prevents accidental deploy from a casual mention of "deploy"

`user-invocable: false`
  → Hides skill from the / menu
  → Claude can still load it automatically when relevant
  → Use for background knowledge (service catalog, client list)

Dynamic context injection:
  The `!`command`` syntax runs a shell command and replaces the line with its output before Claude sees the skill content. Example: `!`cat .env.local | grep DEPLOY_URL`` injects the current URL into the skill at invocation time.

> "Pulumi's own deploy skills use disable-model-invocation: true for commands that touch production, to prevent accidental execution."
— pulumi.com/blog/top-8-claude-skills-devops-2026/

**Source:** See auxiliary: `agent-infra-knowledge_doc_1.txt` (Anthropic skills frontmatter), `agent-infra-knowledge_doc_2.txt` (pulumi.com pattern)

**Significance:** This frontmatter pair answers the assertive-deploy requirement directly. A deploy skill with `disable-model-invocation: true` will not fire when the engineer says "push to staging" casually — it fires only when explicitly invoked with `/deploy-staging`. Combined with `!`command`` injection, the skill can read the current client's URL from a local file and present it to Claude before Claude acts, eliminating round-trips.

---

### Finding 6: Multi-tenant / white-label mapping has no canonical agent-consumption pattern

**Evidence:**

NOT FOUND: A canonical community pattern for per-client environment registries in the context of AI agent consumption was not found in any fetched source.

Closest available: Backstage catalog-info.yaml entity model supports custom `annotations` metadata fields, which could carry per-tenant deploy URLs. Neither source (nitin15j.medium.com nor gokhan-gokalp.com) documents this usage.

Alternative pattern identified (deployhq.com): Using exact commands with client-specific flags as the encoding mechanism:
> "Exact commands with flags. 'uv run pytest tests/unit/ -v', not 'run the tests'. Include environment setup, migration scripts, and dev server startup."
— morphllm.com/agents-md-guide

The community's practical answer is to encode the command, not the mapping. Instead of "client X → URL Y → environment Z → trigger W," the community pattern is to encode "/deploy-client-x" as a Skill with the exact command and URL pre-loaded via dynamic injection.

Nested Skills support (from Anthropic documentation): "When Claude reads or edits a file in a subdirectory, skills from that subdirectory's .claude/skills/ become available." This enables per-client skills in a monorepo layout (`.claude/skills/client-x/SKILL.md`) but no documented example of this pattern exists in the community for multi-tenant deploy routing.

**Source:** See auxiliary: `agent-infra-knowledge_doc_3.txt` (Backstage entity model), `agent-infra-knowledge_doc_4.txt` (morphllm.com commands-not-descriptions)

**Significance:** The specific 4Shark problem (client→URL→environment→deploy mapping) is not directly addressed by any published community pattern. The evidence supports two possible shapes: (a) encode as per-client Skills with static content, (b) encode as a central registry YAML read by a single dispatch Skill via dynamic injection. Neither is confirmed as "the community way" — both are extrapolations from documented primitives.

---

### Finding 7: YAML/JSON registries are referenced from instruction files, not loaded directly

**Evidence:**

From morphllm.com/agents-md-guide:
> "Redundancy hurts performance. Information already available in code, package manifests, or READMEs should not be duplicated."

Princeton study (morphllm.com): "LLM-generated AGENTS.md files slightly reduced task success while increasing cost by 23%." The increase was attributed to redundant information that the model had to reconcile with information already available elsewhere.

From deployhq.com: "Tech stack documentation: Deployment: DeployHQ → Ubuntu 22.04 VPS" — the article recommends naming the deployment target in the instruction file, not encoding the full deployment procedure there.

From Anthropic Skills docs: "Supporting files in a skill directory load only when needed." This is the documented path for a YAML registry: place it in the skill directory, reference it from the SKILL.md body via `!`cat clients.yaml``.

**Source:** See auxiliary: `agent-infra-knowledge_doc_4.txt` (morphllm.com, deployhq.com), `agent-infra-knowledge_doc_1.txt` (Anthropic supporting files)

**Significance:** The community pattern is: machine-readable registries (YAML/JSON) belong as supporting files inside a Skill directory, not in CLAUDE.md. The SKILL.md body references the registry via dynamic injection; CLAUDE.md carries only a pointer to the Skill. This avoids duplication while keeping the registry queryable.

---

## Conclusions

### Where the community is converging

All fetched sources point toward the same structural answer:

**CLAUDE.md = facts only, ~50-150 lines**
The always-loaded file carries project identity, universal conventions, and pointers. Service catalogs, environment mappings, and deploy procedures do not belong here. The instruction budget (150-200 total, ~50 already used by the tool's system prompt) does not accommodate them.

**Skills = operational knowledge, loaded on demand**
The description layer (~80-100 tokens per skill) keeps the agent aware of what is available. The full body loads only when relevant. `disable-model-invocation: true` is the accepted gating mechanism for deploy procedures — requiring explicit invocation, not casual matching. `user-invocable: false` is the accepted pattern for background knowledge (client catalogs, environment tables) that Claude should auto-load when working in a relevant context but that the engineer should not invoke manually.

**Dynamic injection (!`command`) = live truth**
Rather than keeping environment state in static files that can go stale, the community pattern is to inject live state at skill invocation time via `!`command``. This combines the token-efficiency of file-based approaches with the freshness of live queries.

**MCP = live/dynamic data only**
The 35x token cost differential (jannikreinhard.com) makes MCP impractical for static catalog facts. MCP is justified for data that changes between sessions (ECS service counts, health status, current task ARNs) but not for stable mappings (client X lives at URL Y).

**Multi-tenant mapping gap**: No community pattern exists for the specific client→URL→environment→command shape this investigation was asked about. The evidence supports deriving one from the available primitives (per-client Skills + dynamic injection + YAML registry as supporting file), but this would be a 4Shark-specific design, not a community-validated pattern.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Always-loaded (CLAUDE.md / AGENTS.md) | Zero invocation latency; always present; broadest tool support | 100–150 instruction ceiling after system prompt overhead; catalog consumes entire budget | humanlayer.dev, deployhq.com |
| Skills (body on demand, description always-on) | ~80 tokens for awareness; body loads only when needed; supports dynamic injection | Requires description match or explicit invocation; body not available mid-task unless activated | code.claude.com/docs/skills, swirlai.com |
| `disable-model-invocation: true` Skills | Prevents accidental deploy execution; explicit engineer action required | Adds one round-trip (engineer must type /skill-name); deploy cannot be agent-initiated | code.claude.com/docs/skills, pulumi.com |
| `user-invocable: false` Skills | Auto-loaded when Claude deems relevant; transparent to engineer | Relies on description match; may not load if engineer phrasing does not match description | code.claude.com/docs/skills |
| MCP server (Backstage or custom) | Live data; always current; queryable catalog | 35x token cost vs CLI; ~28K tokens for schema alone; limits available context by ~40% | jannikreinhard.com |
| Service catalog (Backstage entity model) | Structured ownership; queryable via MCP; team-maintained | No documented per-tenant deploy routing; limited to dev environments in published examples; MCP cost applies | nitin15j.medium.com, gokhan-gokalp.com |
| YAML/JSON registry as supporting file | Machine-readable; stable; zero cost until activated; injected via !`cat` | Not queryable without tooling; must be injected explicitly; no community validation for deploy routing | morphllm.com, code.claude.com/docs/skills |
| Nested Skills (per-client directory) | Scoped activation when working on client files; isolates per-tenant knowledge | Undocumented in community for deploy routing; relies on Anthropic's subdirectory activation behavior | code.claude.com/docs/skills |

---

## What remains uncertain

- **Per-client Skills activation trigger**: Anthropic's documentation states skills in a subdirectory activate "when Claude reads or edits a file in that subdirectory." Whether this reliably fires for a per-client configuration directory (e.g., `.claude/skills/client-x/`) — rather than a code subdirectory — is not demonstrated in any fetched source. Needs validation against a running Claude Code instance.

- **`disable-model-invocation: true` exact scope**: The documentation states Claude will not "invoke the skill on its own" but does not specify whether this prevents the skill body from being referenced indirectly (e.g., via a dispatching skill that reads it). Not found in any fetched source.

- **Backstage annotations for deploy routing**: The Backstage entity model supports custom `annotations` fields on catalog-info.yaml entities. Whether this is a community-validated path for encoding client→URL→environment→command mappings for AI agent consumption was NOT FOUND in any fetched source.

- **Princeton AGENTS.md study generalizability**: The 28.6% runtime reduction was measured in a controlled research environment. Generalizability to multi-tenant infra knowledge (larger, more volatile catalog) is not demonstrated.

- **YAML registry via dynamic injection at scale**: Injecting a full client registry via `!`cat clients.yaml`` into a Skill at invocation time is technically supported by the Anthropic Skills documentation. Performance implications (token cost of a large YAML file appearing in context) are not benchmarked in any fetched source.

---

## Suggested options for main and the engineer

**Option A — Three-layer static stack (all primitives available today)**

Layer 1: CLAUDE.md (~50 lines)
  Universal project identity, coding conventions, pointer to the catalog skill.
  Example pointer: "For client environments and deploy procedures, see /clients and /deploy-* skills."

Layer 2: `user-invocable: false` background Skill (`/clients`)
  Description: "Client registry — use when engineer mentions a client name, URL, or environment"
  Body: YAML client table injected via `!`cat .claude/skills/clients/clients.yaml``
  clients.yaml (supporting file): { client: X, url: Y, environment: Z, deploy_skill: /deploy-X }

Layer 3: `disable-model-invocation: true` deploy Skills, one per environment class
  Description: "Deploy to [environment] — invoke explicitly with /deploy-staging or /deploy-production"
  Body: exact command sequence with URL pre-loaded via dynamic injection

Trade-off: The catalog (Layer 2) is static — if a new client is added, the YAML must be updated manually. No live query. Appropriate when the catalog changes infrequently (monthly or less).

**Option B — Two-layer + MCP for live catalog**

Layer 1: CLAUDE.md (~50 lines) — same as Option A
Layer 2: MCP server exposing the client catalog via tools (one tool per environment class)
Layer 3: `disable-model-invocation: true` deploy Skills — same as Option A

Trade-off: MCP costs ~28K tokens in schema injection (jannikreinhard.com). Appropriate only if the client catalog changes frequently enough that a static YAML would require weekly manual updates, and the team can absorb the 35x token cost differential.

**Option C — Monolithic background Skill (simpler, less structured)**

Single `user-invocable: false` Skill containing all environment knowledge inline (no YAML).
Description: "Infrastructure context — loads automatically when engineer asks about clients, environments, or deploy"
Body: formatted table: client names, URLs, environments, deploy commands

`disable-model-invocation: true` Skills: one per deploy target (same as Options A and B)

Trade-off: Simpler to set up (no YAML supporting file, no injection command). Harder to update programmatically (human edits a markdown table vs. edits a YAML key). Appropriate for catalogs under ~20 entries where programmatic update is not needed.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
