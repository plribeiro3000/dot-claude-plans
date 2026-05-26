# SPIKE — LLM-Powered Client Data Integration

**Conducted by:** 4Shark Team
**Date:** 2026-03-04
**Status:** Research complete — pending decisions

---

## Goal

Investigate whether LangChain or similar LLM-based solutions can solve 4Shark's client integration scalability problem.

**Core problem**: Each client has different business rules for sales data (filters, multipliers, categories). These rules are undocumented — they exist only in people's heads or legacy APIs. Manual integration per client doesn't scale for a small startup with no dedicated integration team and no budget for one.

**Questions to answer**:
1. Can LangChain solve this integration problem?
2. What alternatives exist?
3. What would a practical architecture look like?
4. What would it cost per client?

---

## Method

- Web research across blog posts, case studies, documentation, and benchmarks (2024-2026)
- Analyzed LangChain, LlamaIndex, Airbyte, dbt, Vanna AI, Wren AI, n8n, Fivetran, Dataherald, Matillion
- Reviewed production case studies (LinkedIn, Fastweb/Vodafone, Uber)
- Compared Text-to-SQL accuracy benchmarks (synthetic vs. real-world)
- Cost modeling for different architecture scenarios

Full research saved at: `SPIKE-v2.md`

---

## Evidence

### 1. LangChain — Partial Fit, Not a Silver Bullet

LangChain is an LLM orchestration framework, not an integration tool by itself. Relevant capabilities:
- **SQLDatabase Toolkit**: native SQL integration via SQLAlchemy
- **LangGraph**: stateful agents for complex workflows
- **Document Loaders**: 150+ connectors

**Critical problems for our use case**:
- **Hallucination**: LLMs invent columns/tables that don't exist
- **Real-world accuracy is low**: Spider 2.0 benchmark (realistic scenarios) = only **6% accuracy** vs. 86% on synthetic benchmarks
- **Inconsistency**: same question can generate different SQL across runs
- **For financial calculations, this is unacceptable**

Production cases:
- LinkedIn: SQL Bot multi-agent (NL → SQL)
- Fastweb + Vodafone: automated ETL pipeline with LangGraph (9.5M clients, 90% accuracy)

Sources:
- https://python.langchain.com/docs/integrations/toolkits/sql_database/
- https://blog.langchain.com/top-5-langgraph-agents-in-production-2024/
- https://www.getwren.ai/post/how-do-you-use-langchain-to-build-a-text-to-sql-solution-what-are-the-challenges-how-to-solve-it

### 2. Most Effective Pattern: Semantic Layer + LLM

Instead of having the LLM generate SQL directly:
1. Define business rules per client in a **semantic layer** (dbt MetricFlow, Cube.dev)
2. LLM generates a **structured semantic query** (not SQL)
3. Semantic layer compiles it into correct, optimized SQL

Result: **83% accuracy** vs. ~40% with direct SQL generation.

Sources:
- https://www.getdbt.com/blog/semantic-layer-as-the-data-interface-for-llms
- https://aws.amazon.com/blogs/machine-learning/generating-value-from-enterprise-data-best-practices-for-text2sql-and-generative-ai/

### 3. Alternatives Evaluated

| Tool | Role | Cost | Notes |
|------|------|------|-------|
| **Airbyte** (open-source) | Data movement, 600+ connectors | Free self-hosted | AI-powered connector builder, self-healing jobs |
| **dbt Core + MetricFlow** | Semantic layer, business rules | Free open-source | DAG-based execution order, metrics as code |
| **Vanna AI** | Text-to-SQL with RAG | Free (MIT) | Trainable per client, any LLM |
| **Wren AI** | GenBI with semantic engine | Free open-source | Maps business terms to data sources |
| **LlamaIndex** | Multi-tenant RAG | Free open-source | Native client-partitioned vector search |
| **n8n** | Workflow orchestration with AI | Free self-hosted | 70+ AI nodes, native LangChain integration |
| **Fivetran + dbt** | Managed data movement + transform | Paid (merged 2025) | ~$600M ARR combined entity |
| **Dataherald** | Enterprise NL-to-SQL | Open-source | Without context, accuracy drops to ~3% |

Sources:
- https://airbyte.com/data-engineering-resources/ai-data-integration
- https://github.com/vanna-ai/vanna
- https://github.com/Canner/WrenAI
- https://www.llamaindex.ai/blog/building-multi-tenancy-rag-system-with-llamaindex-0d6ab4e0c44b
- https://n8n.io/ai/

### 4. Multi-tenant RAG Pattern for Per-Client Rules

```
[Client A Rules] → Embeddings → Vector Store (namespace A)
[Client B Rules] → Embeddings → Vector Store (namespace B)

Data request → Retrieve rules from correct namespace → LLM generates contextualized query
             → Human validation → Execution
```

Benefits: complete client isolation, fast vector search per namespace, add new clients without code changes.

### 5. Hybrid Approach (Literature Consensus)

| Scenario | Use LLM | Use Traditional Code |
|----------|---------|---------------------|
| Unstructured data, ambiguous logic | Yes | No |
| Extract rules from text/legacy code | Yes | No |
| High volume (1TB+), simple ETL | No | Yes |
| Exact financial calculations | No | Yes |
| Predictable, repeatable queries | No | Yes |

### 6. Pros and Cons of LLM-Powered ETL

**Pros**: handles unstructured data, reduces connector dev time, self-healing on schema changes, accessible to non-technical users, LLM costs dropping fast.

**Cons**: hallucination (28-39% error without mitigation), inconsistency across runs, real-world accuracy very low, premium vendor lock-in ($50k-$200k/year), latency, LGPD/GDPR risks with external LLMs.

### 7. Cost Modeling

**Existing approach (client provides queries)**: pragmatically solid, clear responsibility boundary.

**Three scenarios modeled**:

#### Scenario A — LLM only at onboarding (recommended)
LLM helps discover and document rules, then queries become fixed templates running daily.

#### Scenario B — LLM generating queries dynamically every day
More flexible but more expensive and hallucination risk.

#### Scenario C — Managed services (Airbyte Cloud, Pinecone, etc.)
Most expensive, scales poorly for startup.

### 8. Recommended Architecture (Distributed)

**Onboarding (once per client)**:
```
LLM + human → understand rules → generate dbt models per client
```

**Daily execution (no LLM)**:
```
n8n schedules daily →
  1. Airbyte extracts raw data from client (40-50 sources)
  2. dbt runs transformation models (in correct order via DAG)
  3. Data ready for consumption
  4. Notify on error
```

### 9. Infrastructure Cost — Distributed (1 service per VM)

Requirement: no shared VMs — each service on its own machine for resilience.

| Service | Suggested VM (AWS) | Cost/month (USD) | Cost/month (BRL)* |
|---------|-------------------|------------------|-------------------|
| **Airbyte** | t3.medium (2 vCPU, 4GB) | ~$30 | ~R$165 |
| **dbt Core** | t3.small (2 vCPU, 2GB) | ~$15 | ~R$82 |
| **n8n** | t3.small (2 vCPU, 2GB) | ~$15 | ~R$82 |
| **PostgreSQL** | db.t3.medium (RDS) or dedicated t3.medium | ~$30-65 | ~R$165-355 |
| **Total infra** | | **~$90-125** | **~R$495-685** |

*Estimated exchange rate: R$5.50/USD*

Notes:
- Airbyte is the heaviest — needs at least 4GB RAM (runs Temporal + workers internally)
- dbt Core is lightweight — only runs during transformation, then stops. Could be spot/burstable
- n8n is lightweight — orchestrator with few workflows uses little resources
- PostgreSQL — RDS gives automatic backup, failover, maintenance. Dedicated EC2 is cheaper but more ops work

#### Cost per client at scale

| Clients | Infra per client | Storage per client | Total per client |
|---------|-----------------|-------------------|-----------------|
| 10 | ~R$60 | ~R$20-50 | **~R$80-110** |
| 20 | ~R$30 | ~R$20-50 | **~R$50-80** |

Onboarding has a one-time LLM cost of R$50-200 per client (depends on rule complexity).

Infrastructure handles 10-20 clients at this volume (5k records/day). Beyond that, Airbyte would likely need to scale first (more RAM/CPU for parallel workers).

---

## Conclusions

1. **LangChain alone doesn't solve the problem** — it's an orchestration framework, not an integration solution. Useful as a component, not as the answer.

2. **The most effective pattern is Semantic Layer + LLM** — dbt MetricFlow defines rules as code, LLM generates structured queries (not raw SQL), achieving 83% accuracy vs. 40% with direct SQL.

3. **LLM should be used at onboarding, not daily execution** — for financial calculations, deterministic queries are essential. LLM helps discover and document rules, then queries become fixed templates.

4. **Best stack for 4Shark's constraints** (small team, low budget, need for resilience):
   - **Airbyte** (data extraction) → own VM
   - **dbt Core** (transformations/rules) → own VM
   - **n8n** (orchestration) → own VM
   - **PostgreSQL** (storage) → own VM or RDS

5. **Cost per client in regime**: R$50-110/month depending on number of clients (infrastructure amortization).

6. **The existing approach (client provides queries) remains pragmatically valid** as a responsibility boundary — LLM-assisted onboarding can complement it, not replace it.

---

## Next Steps

- [ ] **Decision needed**: Choose between approach A (LLM-assisted onboarding + deterministic execution) vs. current approach (client provides queries) vs. hybrid
- [ ] **If proceeding**: Create PLAN.md for implementation of chosen approach
- [ ] **Prototype candidate**: Airbyte + dbt + n8n stack with one real client to validate costs and complexity
- [ ] **Further investigation needed**: dbt MetricFlow semantic layer — how well does it handle the specific types of client rules 4Shark encounters?
- [ ] **Further investigation needed**: Airbyte connector coverage — verify it supports the specific databases/APIs 4Shark clients use

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
