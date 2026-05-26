# Research: LangChain e Soluções LLM para Integração de Dados

## Contexto do Problema

Startup pequena que precisa integrar dados de vendas de múltiplos clientes, onde cada cliente tem regras de negócio diferentes (filtros, multiplicadores, categorias) que não estão documentadas — existem apenas na cabeça de pessoas ou em APIs legadas.

---

## A) LangChain para Integração de Dados

### Text-to-SQL

LangChain possui integração nativa com bancos SQL via `create_sql_query_chain` e `SQLDatabaseToolkit`. O fluxo: pergunta em linguagem natural → LLM gera SQL → executa → retorna resultado.

**Desafios críticos em produção:**
- Usuários falam em "linguagem de negócio", não em nomes de tabelas
- Bancos grandes não cabem no contexto do prompt — precisa de RAG para metadados
- LLMs alucinam nomes de colunas/tabelas que não existem
- Benchmark Spider 2.0 (casos reais): apenas **6% de precisão** vs. 86% em benchmarks sintéticos

**Fontes:**
- https://python.langchain.com/docs/integrations/toolkits/sql_database/
- https://www.getwren.ai/post/how-do-you-use-langchain-to-build-a-text-to-sql-solution-what-are-the-challenges-how-to-solve-it
- https://medium.com/dataherald/high-accuracy-text-to-sql-with-langchain-840742133b83

### LangGraph (Agentes Stateful)

LangGraph permite criar agentes que consultam múltiplas fontes, corrigem erros automaticamente e mantêm estado entre etapas.

**Casos reais em produção (2024):**
- **LinkedIn**: SQL Bot multi-agente (linguagem natural → SQL)
- **Fastweb + Vodafone**: Pipeline ETL automatizado com LangGraph (9.5M clientes, 90% precisão)
- **Uber**: Migrações de código em larga escala

**Fontes:**
- https://blog.langchain.com/top-5-langgraph-agents-in-production-2024/
- https://www.langchain.com/customers

### LangChain + Airbyte

Integração oficial: PyAirbyte para mover dados (600+ conectores) + LangChain para processar com LLMs. Airbyte lançou Agent Connectors compatíveis com LangChain.

**Fontes:**
- https://airbyte.com/tutorials/end-to-end-rag-using-github-pyairbyte-and-langchain
- https://github.com/airbytehq/airbyte-agent-connectors

---

## B) Competidores e Alternativas

### LlamaIndex
- Foco em data retrieval e RAG (300+ conectores)
- **Multi-tenant RAG nativo**: particionamento por cliente
- Complementar ao LangChain (retrieval vs. orquestração)
- https://www.llamaindex.ai/
- https://www.llamaindex.ai/blog/building-multi-tenancy-rag-system-with-llamaindex-0d6ab4e0c44b

### Airbyte (Open-source)
- 600+ conectores, AI-powered Connector Builder
- Self-healing jobs (reescreve mapeamento quando schema muda)
- https://airbyte.com/data-engineering-resources/ai-data-integration

### Fivetran + dbt (fusão em 2025)
- **dbt Semantic Layer** define métricas/regras de negócio centralizadas
- LLMs geram MetricFlow requests (estruturados) em vez de SQL direto
- Resultado: **83% precisão** com Semantic Layer vs. ~40% com SQL direto
- https://www.getdbt.com/blog/semantic-layer-as-the-data-interface-for-llms

### Vanna AI
- Open-source (MIT, ~20k stars), especializado em Text-to-SQL com RAG
- Treinável com terminologia de negócio por cliente
- Compatível com qualquer LLM
- https://github.com/vanna-ai/vanna
- https://vanna.ai/

### Wren AI
- Open-source, Generative BI com Semantic Engine
- Mapeia termos de negócio para fontes de dados
- https://github.com/Canner/WrenAI
- https://www.getwren.ai/oss

### n8n
- Automação de workflow open-source com 70+ nós de IA
- Integração nativa com LangChain
- Self-hostable, cobra por execução de workflow
- https://n8n.io/ai/

---

## C) Padrões Práticos

### 1. Semantic Layer + LLM (padrão mais eficaz)

Em vez de LLM gerar SQL diretamente:
1. Definir regras de negócio em semantic layer (dbt MetricFlow, Cube.dev)
2. LLM gera query semântica estruturada
3. Semantic layer compila em SQL correto

Resultado: 83% precisão vs. ~40% com SQL direto.

### 2. Multi-tenant RAG para regras por cliente

```
[Regras do Cliente A] → Embeddings → Vector Store (namespace A)
[Regras do Cliente B] → Embeddings → Vector Store (namespace B)

Query → Recupera regras do namespace correto → LLM gera SQL contextualizado
```

### 3. Abordagem Híbrida (consenso da literatura)

| Situação | LLM | Código Tradicional |
|----------|-----|-------------------|
| Dados não estruturados, lógica ambígua | Sim | Não |
| Extração de regras de texto/código legado | Sim | Não |
| Volume alto (1TB+), ETL simples | Não | Sim |
| Cálculos financeiros exatos | Não | Sim |
| Queries previsíveis | Não | Sim |

---

## D) Prós e Contras Gerais

### Prós
- Lida com dados não estruturados e regras ambíguas
- Reduz tempo de desenvolvimento de conectores
- Self-healing em mudanças de schema
- Acessível a usuários não-técnicos
- Custo de LLMs em queda

### Contras
- **Alucinação**: até 28-39% de erro sem mitigação
- **Inconsistência**: mesma pergunta pode gerar respostas diferentes
- **Precisão real**: benchmark Spider 2.0 = apenas 6% em casos reais
- **Custo**: vendors premium $50k-$200k/ano
- **Latência**: mais lento que código tradicional
- **LGPD/GDPR**: RAG + LLMs externos criam riscos

---

## E) Stack Recomendado para Startup com Baixo Orçamento

1. **Airbyte (open-source, self-hosted)** — movimentação de dados, 600+ conectores, custo zero
2. **LlamaIndex** — multi-tenant RAG, open-source
3. **Vanna AI ou Wren AI** — Text-to-SQL open-source, treinável por cliente
4. **dbt Core + MetricFlow** — semantic layer open-source para regras de negócio
5. **n8n (self-hosted)** — orquestração de workflows com LLM

### Gestão de custos de LLM:
- Modelos open-source (Llama, Mistral) via Ollama para casos simples (~zero)
- GPT-4o ou Claude apenas para queries complexas (roteamento inteligente reduz 85% dos custos)
- Semantic caching com Redis (até 80% cache hit rate)
