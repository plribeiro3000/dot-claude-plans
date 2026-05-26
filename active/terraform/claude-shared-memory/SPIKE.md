# SPIKE — AI Memory Database for Shared Team Knowledge

**Conducted by:** Claude Code (research) + Engineer (decisions)
**Date:** 2026-02-25
**Status:** Research complete — pending decisions

---

## Goal

**Primary question:** Which AI memory database solution should 4Shark adopt to provide shared team knowledge and per-engineer private workspaces, self-hosted on AWS via Terraform, accessible via VPN?

**Why this investigation is needed:**
- Engineers lose context between Claude Code sessions
- Knowledge learned by one engineer is not accessible to others
- The current `~/.claude/` Git repository handles rules and configuration well, but does not support semantic search, knowledge graphs, or dynamic memory
- The market has exploded with 40+ solutions in 2025-2026, making an informed choice critical

**Requirements:**
1. **Team-shared knowledge** — one engineer learns, all benefit
2. **Per-engineer workspace** — private context for individual work
3. **Self-hosted on AWS** — deployable via Terraform on EC2 or similar
4. **VPN access only** — no public internet exposure
5. **MCP compatible** — must integrate with Claude Code via Model Context Protocol
6. **Reliable maintainer** — low bus factor risk, sustainable open-source or company-backed

---

## Method

- Web search across 80+ sources covering MCP servers, vector databases, AI memory platforms, and deployment patterns
- Analysis of GitHub repositories (stars, contributors, commit frequency, licenses)
- Review of official documentation, blog posts, and community discussions
- Cross-referencing maintainer profiles for bus factor assessment
- Cost estimation for AWS self-hosted deployments

---

## Evidence

### A. Market Landscape (40+ solutions found)

The research identified 40+ solutions across 5 tiers. Only solutions meeting ALL 4Shark requirements (self-hosted, MCP, multi-user, active maintenance) are analyzed in depth below.

### B. Solutions That Meet Core Requirements

#### B.1 — Mem0 + OpenMemory MCP

| Attribute | Detail |
|-----------|--------|
| **What** | Open-source AI memory platform with knowledge graph |
| **GitHub** | https://github.com/mem0ai/mem0 |
| **Stars** | ~48,000 (main repo), 601 (MCP server) |
| **Contributors** | 254 (main repo) |
| **Maintainer** | Mem0 Inc — YC-backed startup (Taranjeet Singh, Dev Khant) |
| **License** | Apache 2.0 |
| **Architecture** | FastAPI + PostgreSQL/pgvector + Neo4j knowledge graph |
| **Self-hosted** | Docker Compose (3 containers: API + Postgres + Neo4j) |
| **AWS minimum** | t3.medium (2 vCPU, 4GB RAM) — ~$30/month |
| **Multi-user** | `user_id`, `agent_id`, `app_id`, `run_id` scoping |
| **Workspace isolation** | PARTIAL — API-level filtering by user_id, no native workspace concept |
| **MCP** | OpenMemory MCP server (official), also self-hosted variant with Qdrant + Neo4j + Ollama |
| **Search** | Semantic (vector) + knowledge graph traversal |
| **Team features** | Workspace governance, audit logs, scoped memory, per-app access control |
| **Bus factor** | LOW RISK — Company-backed (YC), 254 contributors, active community |
| **Terraform** | No official module, but standard Docker Compose on EC2 is straightforward |
| **Last activity** | Feb 2026 (v1.0.4) |

**Strengths:** Most popular and mature solution. Large community. Company-backed with funding. Full REST API. Multiple deployment options. Knowledge graph + vector search.

**Weaknesses:** Multi-tenancy is API-level filtering (not native workspace isolation). Neo4j container is memory-hungry (~2GB). Requires OpenAI or similar for embeddings (or Ollama for local).

---

#### B.2 — Zep / Graphiti (Knowledge Graph MCP)

| Attribute | Detail |
|-----------|--------|
| **What** | Temporal knowledge graph framework for AI agents |
| **GitHub** | https://github.com/getzep/graphiti |
| **Stars** | ~23,100 |
| **Maintainer** | Zep Inc (Preston Rasmussen) |
| **License** | Apache 2.0 |
| **Architecture** | Temporal knowledge graph + Neo4j/FalkorDB backend |
| **Self-hosted** | Docker Compose with Neo4j or FalkorDB |
| **Multi-user** | `group_id`-based multi-tenancy with full isolation |
| **Workspace isolation** | FULL — group_id prevents data leaks between users/projects |
| **MCP** | MCP Server 1.0 (official) — Episode Management, Entity Management, search |
| **Search** | Semantic + BM25 keyword + temporal queries |
| **Bus factor** | MEDIUM RISK — Company-backed, but Community Edition (OSS) was deprecated in April 2025. Current open-source offering is Graphiti only |
| **Last activity** | Feb 2026 (v0.4.5) |

**Strengths:** Best workspace isolation (true multi-tenancy). Temporal awareness (knows WHEN things happened). Academic paper backing (arXiv 2501.13956). Strong graph relationships.

**Weaknesses:** Community Edition was deprecated April 2025 (concerning signal). Expensive API calls for graph generation. Requires Neo4j or FalkorDB. Higher complexity.

**CRITICAL WARNING:** Zep deprecated its open-source Community Edition in April 2025. Only Graphiti (the graph library) remains open-source. This is a significant trust signal — the company pivoted to cloud-only for the full product.

---

#### B.3 — Qdrant + Official MCP Server

| Attribute | Detail |
|-----------|--------|
| **What** | High-performance vector database with official MCP server |
| **GitHub DB** | https://github.com/qdrant/qdrant (22k+ stars) |
| **GitHub MCP** | https://github.com/qdrant/mcp-server-qdrant (1,200 stars) |
| **Maintainer** | Qdrant (VC-funded company) |
| **License** | Apache 2.0 |
| **Architecture** | Rust vector database + Python MCP server |
| **Self-hosted** | Docker, Kubernetes, Terraform module available |
| **Terraform** | https://github.com/CTOFriendly/terraform-aws-qdrant (EC2-based) + official Terraform provider |
| **Multi-user** | Tiered multitenancy (v1.16.0+), JWT-based RBAC |
| **Workspace isolation** | FULL — collections per workspace, JWT with granular permissions |
| **MCP** | Official: `qdrant-store`, `qdrant-find` tools; stdio, SSE, streamable-HTTP transport |
| **Search** | Semantic vector search (cosine, euclidean, dot product) |
| **Auth** | Static API key (simple) + JWT with RBAC (advanced) |
| **Bus factor** | LOW RISK — VC-funded company, strong open-source track record, SSO/RBAC enterprise features |
| **AWS cost** | ~$50-100/month (EC2 + EBS) |
| **Last activity** | Active (2026) |

**Strengths:** Best-in-class vector search performance. Official Terraform module for AWS. Native tiered multitenancy. JWT RBAC. Company-backed with strong enterprise features. Official MCP server.

**Weaknesses:** Pure vector database — no knowledge graph (only stores/retrieves vectors). MCP server is simple (store + find only). You'd need to build the memory logic layer on top (how to structure memories, when to consolidate, etc.).

---

#### B.4 — mcp-memory-service (doobidoo)

| Attribute | Detail |
|-----------|--------|
| **What** | Open-source persistent memory for AI agents with REST API + knowledge graph |
| **GitHub** | https://github.com/doobidoo/mcp-memory-service |
| **Stars** | ~1,400 |
| **Maintainer** | doobidoo (individual developer) |
| **License** | Apache 2.0 |
| **Architecture** | SQLite-vec + optional ChromaDB + Cloudflare sync |
| **Self-hosted** | 100% local, zero cloud dependencies |
| **Multi-user** | OAuth 2.1 Dynamic Client Registration for teams, X-Agent-ID header for scoping |
| **Workspace isolation** | PARTIAL — per-project, X-Agent-ID based |
| **MCP** | Native MCP + REST API (15 endpoints) |
| **Search** | Hybrid BM25 + vector search (5ms local access) |
| **Features** | Knowledge graph, web dashboard, D3.js visualization, SSE real-time events |
| **Team** | ChromaDB backend for multi-client, litestream sync for SQLite, git export/import |
| **Bus factor** | **HIGH RISK — Single individual developer** |
| **AWS cost** | ~$15-30/month (lightweight, SQLite-based) |
| **Last activity** | Feb 25, 2026 (v10.18.1) — extremely active |

**Strengths:** Most feature-rich MCP memory server. Incredibly active development (v10.18.1). Fast (5ms). Knowledge graph + vector search + REST API + dashboard. Team OAuth support. Very low resource requirements.

**Weaknesses:** **SINGLE maintainer is the critical risk.** If doobidoo stops maintaining, the project dies. No company backing. High release velocity could indicate instability (10+ major versions in ~1 year).

---

#### B.5 — Redis Agent Memory Server

| Attribute | Detail |
|-----------|--------|
| **What** | Official Redis memory layer for AI agents |
| **GitHub** | https://github.com/redis/agent-memory-server |
| **Stars** | 188 |
| **Maintainer** | Redis Inc (official) |
| **License** | Apache 2.0 |
| **Architecture** | Two-tier: session working memory + persistent long-term memory |
| **Self-hosted** | Redis server + Python API |
| **Multi-user** | Multi-tenancy with user_id + namespace isolation |
| **Workspace isolation** | FULL — user_id + namespace |
| **MCP** | Yes — stdio and SSE modes |
| **Search** | Vector search via Redis, multiple extraction modes |
| **Features** | LangChain integration, 100+ LLM providers via LiteLLM |
| **Bus factor** | LOW RISK — Redis Inc (major company) |
| **AWS cost** | ~$30-60/month (ElastiCache or self-hosted Redis) |
| **Last activity** | Jan 2026 |

**Strengths:** Backed by Redis (major company). Two-tier memory architecture. Native namespace isolation. LangChain integration. Can use ElastiCache on AWS.

**Weaknesses:** Relatively new (188 stars). Redis is primarily a cache, not a knowledge database. No knowledge graph. Limited MCP tools compared to dedicated solutions.

---

#### B.6 — Cognee

| Attribute | Detail |
|-----------|--------|
| **What** | Open-source knowledge engine: raw data → persistent memory via knowledge graphs + vector search |
| **GitHub** | https://github.com/topoteretes/cognee |
| **Stars** | ~12,500 |
| **Contributors** | 105 |
| **Maintainer** | Topoteretes (company) |
| **License** | Apache 2.0 |
| **Architecture** | ECL pipeline (Extract, Cognify, Load) + Neo4j + vector databases |
| **Self-hosted** | Docker, pip install |
| **Multi-user** | Multi-tenant support |
| **MCP** | cognee-mcp with tools: cognify, codify, search (6 modes), delete, prune, save_interaction |
| **Search** | 6 search modes including graph traversal and vector similarity |
| **Bus factor** | MEDIUM — Company-backed but smaller |
| **AWS cost** | ~$50-80/month (Neo4j + vector DB + API) |
| **Last activity** | Feb 2026 (v0.5.3) |

**Strengths:** Most sophisticated knowledge processing pipeline. 30+ data source integrations. Graph + vector combined. Company-backed with 105 contributors.

**Weaknesses:** Complex setup (requires LLM provider for processing). Still pre-1.0. Higher resource requirements.

---

#### B.7 — CaviraOSS OpenMemory

| Attribute | Detail |
|-----------|--------|
| **What** | Local persistent memory with hierarchical memory decomposition and temporal graph |
| **GitHub** | https://github.com/CaviraOSS/OpenMemory |
| **Stars** | ~3,400 |
| **Maintainer** | Cavira OSS (community) |
| **License** | Apache 2.0 |
| **Architecture** | 5 memory sectors (episodic, semantic, procedural, emotional, reflective) + temporal knowledge graph |
| **Self-hosted** | Docker, Railway, local |
| **Multi-user** | Multi-user support |
| **MCP** | Zero-config MCP endpoint |
| **Search** | Composite scoring (not just vector similarity), adaptive decay engine |
| **Features** | Data connectors (GitHub, Notion, Google Drive), temporal graph |
| **Bus factor** | MEDIUM RISK — Community project, not company-backed |
| **AWS cost** | ~$20-40/month |
| **Last activity** | Active |

**Strengths:** Most cognitive approach to memory (5 sectors). Data connectors for external sources. Temporal knowledge graph. Low resource requirements.

**Weaknesses:** Community-maintained (no company backing). Less mature than Mem0. Smaller community.

---

### C. Solutions EXCLUDED and Why

| Solution | Reason for Exclusion |
|----------|---------------------|
| **Anthropic Official Memory Server** | No multi-user support, JSONL file storage, no vector search |
| **Pinecone MCP** | Cloud-only, cannot self-host |
| **HPKV Memory MCP** | Cloud-only service, not self-hostable |
| **ByteRover** | SaaS-only, not self-hostable |
| **Amazon Bedrock AgentCore** | No MCP support, AWS lock-in |
| **Supermemory** | Primarily cloud (Cloudflare), self-hosting is partial |
| **Letta (MemGPT)** | Agent framework, not standalone memory DB; overkill for the use case |
| **LangMem (LangChain)** | Tied to LangGraph ecosystem, not standalone MCP server |
| **SurrealDB 3.0** | No MCP server, BSL license (not truly open source), too new (Feb 2026) |
| **Knowledge Plane** | No public pricing, limited self-hosting info, unknown company |
| **SimpleMem** | Academic research project, not production-ready |
| **claude-mem** | AGPL license, single maintainer, Claude Code-only |
| **claude-cognitive** | Too new (4 days old at time of research), single maintainer |
| **MemoryGate** | Single individual developer (PStryder), high bus factor risk |
| **mcp-memory-libsql** | 81 stars, single developer, high bus factor risk |
| **Roo Code Memory Bank** | Roo Code-specific, not Claude Code |
| **Memori (MemoriLabs)** | No direct MCP support |

---

### D. Comparison Matrix — Viable Candidates

| Criteria | Mem0 | Qdrant + MCP | mcp-memory-service | Redis Memory | Cognee | Zep/Graphiti | CaviraOSS |
|----------|------|-------------|---------------------|--------------|--------|-------------|-----------|
| **MCP Native** | Yes (OpenMemory) | Yes (official) | Yes (native) | Yes | Yes (cognee-mcp) | Yes (v1.0) | Yes |
| **Team Shared Memory** | Yes (agent_id scope) | Yes (collections) | Yes (OAuth, ChromaDB) | Yes (namespaces) | Yes (multi-tenant) | Yes (group_id) | Yes |
| **Per-Engineer Workspace** | user_id filtering | JWT per-user | X-Agent-ID | user_id + namespace | per-pipeline | group_id isolation | multi-user |
| **Workspace Isolation** | Partial (API-level) | **Full (JWT RBAC)** | Partial (header) | **Full (namespace)** | Yes | **Full (group_id)** | Yes |
| **Self-hosted AWS** | Docker Compose on EC2 | **Terraform module** | pip install on EC2 | Redis on EC2/ElastiCache | Docker on EC2 | Docker Compose on EC2 | Docker on EC2 |
| **Terraform Ready** | No (manual Docker) | **Yes (official)** | No | No (but ElastiCache TF exists) | No | No | No |
| **Vector Search** | Yes (pgvector) | **Yes (best-in-class)** | Yes (BM25 + vector) | Yes | Yes | Yes | Yes (composite) |
| **Knowledge Graph** | Yes (Neo4j) | No | Yes | No | **Yes (Neo4j)** | **Yes (temporal)** | **Yes (temporal)** |
| **Search Performance** | Good | **Excellent** | **Excellent (5ms)** | Good | Good | Good (P95 300ms) | Good |
| **GitHub Stars** | **48,000** | **22,000 + 1,200** | 1,400 | 188 | 12,500 | 23,100 | 3,400 |
| **Bus Factor** | **Low (YC company)** | **Low (VC company)** | **HIGH (1 person)** | **Low (Redis Inc)** | Medium (company) | Medium (OSS deprecated) | Medium (community) |
| **License** | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 | Apache 2.0 |
| **AWS Monthly Cost** | ~$30-60 | ~$50-100 | ~$15-30 | ~$30-60 | ~$50-80 | ~$40-70 | ~$20-40 |
| **Maturity** | **High (v1.0+)** | **High** | Medium (v10.x) | Low-Medium | Medium (v0.5) | High (but OSS risk) | Medium |
| **Complexity to Deploy** | Medium (3 containers) | **Low (1 container + TF)** | **Low (pip install)** | Low-Medium | High (Neo4j + LLM) | Medium (Neo4j) | Low-Medium |
| **Embeddings** | OpenAI/Ollama | Local (FastEmbed) | **Local (ONNX)** | LiteLLM (100+ providers) | OpenAI/providers | Requires LLM API | Local/OpenAI |

---

### E. Bus Factor Deep Analysis

| Solution | Maintainer | Type | Funding | Contributors | Risk Level | Rationale |
|----------|-----------|------|---------|-------------|------------|-----------|
| **Mem0** | Mem0 Inc | YC Startup | $4.7M seed | 254 | **Low** | YC-backed, large community, active hiring |
| **Qdrant** | Qdrant GmbH | VC Startup | Series A+ | 100+ | **Low** | VC-funded, enterprise customers, Terraform provider |
| **Redis Memory** | Redis Inc | Public company | N/A | 21 | **Low** | Redis is a $1B+ company, but this specific project is small |
| **Cognee** | Topoteretes | Startup | Unknown | 105 | **Medium** | Company-backed but smaller, 105 contributors is healthy |
| **Zep/Graphiti** | Zep Inc | Startup | Unknown | ~20 | **Medium-High** | Deprecated OSS Community Edition in Apr 2025 — concerning precedent |
| **CaviraOSS** | Community | OSS Community | None | Unknown | **Medium-High** | No company backing, community-driven |
| **mcp-memory-service** | doobidoo | Individual | None | 1 | **Critical** | Single developer, no company, no backup maintainers |

---

### F. AWS Deployment Feasibility

#### Tier 1 — Terraform Ready
- **Qdrant**: Official Terraform module (`CTOFriendly/terraform-aws-qdrant`) + official cloud provider. Deploys to EC2 with EBS. Most IaC-ready option.

#### Tier 2 — Docker Compose on EC2 (Simple)
- **Mem0**: `docker compose up` with 3 containers. Add Terraform for EC2 + Security Group + EBS.
- **Zep/Graphiti**: Docker Compose with Neo4j. Similar Terraform wrapper.
- **Redis Memory**: Single Redis container. Could use ElastiCache (has Terraform support).

#### Tier 3 — Lightweight (pip install)
- **mcp-memory-service**: `pip install mcp-memory-service`. Runs as a process on EC2. Lightest option.
- **CaviraOSS**: Docker or direct install.

#### Tier 4 — Complex (Kubernetes preferred)
- **Cognee**: Requires Neo4j + vector DB + LLM provider. More moving parts.

#### VPN Compatibility
All solutions work behind VPN since they expose HTTP APIs or MCP stdio/SSE transports. The key is:
- EC2 in private subnet
- Security Group allowing only VPN CIDR
- No public IP / no internet-facing load balancer

---

### G. Workspace Architecture for 4Shark

The ideal architecture has two layers:

```
┌─────────────────────────────────────────────────┐
│                SHARED TEAM MEMORY                │
│  (patterns, conventions, debugging solutions,    │
│   architectural decisions, domain knowledge)     │
│                                                  │
│  All engineers READ + WRITE                      │
└──────────────────────┬──────────────────────────┘
                       │
       ┌───────────────┼───────────────┐
       │               │               │
┌──────┴──────┐ ┌──────┴──────┐ ┌──────┴──────┐
│ Engineer A  │ │ Engineer B  │ │ Engineer C  │
│  Private    │ │  Private    │ │  Private    │
│  Workspace  │ │  Workspace  │ │  Workspace  │
│             │ │             │ │             │
│ (current    │ │ (current    │ │ (current    │
│  tasks,     │ │  tasks,     │ │  tasks,     │
│  WIP notes, │ │  WIP notes, │ │  WIP notes, │
│  personal   │ │  personal   │ │  personal   │
│  context)   │ │  context)   │ │  context)   │
└─────────────┘ └─────────────┘ └─────────────┘
```

**How each solution implements this:**

| Solution | Shared Layer | Private Layer | Promotion Mechanism |
|----------|-------------|---------------|---------------------|
| **Mem0** | `agent_id="4shark-team"` | `user_id="engineer-a"` | Engineer stores with team agent_id |
| **Qdrant** | Collection `team-shared` | Collection `engineer-a-private` | Copy vector to shared collection |
| **Redis** | Namespace `team` | Namespace `engineer-a` | Write to both namespaces |
| **mcp-memory-service** | Shared ChromaDB instance | Per-engineer SQLite | Export/import via git |

---

## Conclusions

### Key Findings

1. **The market is exploding** — 40+ solutions exist, but only ~7 meet all 4Shark requirements (self-hosted, MCP, multi-user, reliable maintainer).

2. **No perfect solution exists** — Every option requires trade-offs between maturity, features, and deployment complexity.

3. **Bus factor is the #1 differentiator** — The technically best solutions (mcp-memory-service) have the worst bus factor. The safest solutions (Qdrant, Mem0) require more custom work.

4. **Two viable architectures emerge:**

   **Option A — Mem0 (Recommended for most teams):**
   - Best balance of maturity, features, and maintainability
   - Docker Compose deployment is simple
   - Knowledge graph + vector search built-in
   - YC-backed with 48k stars and 254 contributors
   - Workspace isolation is partial but sufficient (user_id/agent_id filtering)
   - Cost: ~$30-60/month on AWS
   - **Trade-off:** No native workspace isolation, multi-tenancy is API-level

   **Option B — Qdrant + Custom MCP Layer (Recommended for control-focused teams):**
   - Best infrastructure maturity (Terraform ready, RBAC, JWT)
   - True workspace isolation with collections + JWT
   - Highest search performance
   - VC-backed with 22k stars
   - Cost: ~$50-100/month on AWS
   - **Trade-off:** Need to build memory logic layer on top (how memories are structured, consolidated, and promoted from private to shared)

5. **Zep/Graphiti is technically excellent but risky** — The deprecation of the Community Edition in April 2025 is a red flag. They could further restrict the open-source offering at any time.

6. **mcp-memory-service has the best features but critical bus factor** — If doobidoo stops maintaining, the project dies. Not acceptable for production team infrastructure.

7. **Redis Agent Memory is promising but too early** — Only 188 stars and limited MCP tools. Worth monitoring but not ready for production adoption.

### Recommendation

**Primary: Mem0 + OpenMemory MCP**

Rationale:
- Strongest community and maintainer (YC-backed, 48k stars, 254 contributors)
- Built-in knowledge graph AND vector search (no need to build memory logic)
- Docker Compose deployment fits EC2 + Terraform wrapper
- user_id/agent_id scoping is sufficient for shared vs private
- OpenMemory MCP integrates directly with Claude Code
- Active development (v1.0.4, Feb 2026)
- Apache 2.0 license — no restrictions

**Secondary consideration: Qdrant** as the underlying vector store for Mem0 (replacing pgvector) for better search performance and native multi-tenancy, if the team needs stricter workspace isolation in the future.

---

## Next Steps

1. **Decision needed:** Does the team agree with the Mem0 recommendation, or prefer the Qdrant approach?
2. **If Mem0 approved → Generate PLAN.md** covering:
   - Terraform module for EC2 + Docker Compose + Security Group + EBS
   - Mem0 configuration with team `agent_id` + per-engineer `user_id`
   - OpenMemory MCP configuration for Claude Code (settings.json)
   - VPN-only access configuration
   - Backup strategy (pg_dump + Neo4j snapshots)
   - Engineer onboarding guide
3. **Prototype first:** Deploy on a t3.medium for 2-week evaluation before committing
4. **Monitor alternatives:** Keep watching Redis Agent Memory and Cognee — both could become viable in 6-12 months

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
