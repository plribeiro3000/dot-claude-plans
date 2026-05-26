# SPIKE — Claude Code Auto Memory: sentimento da comunidade e opções de mitigação

**Conducted by:** Research agent (Claude Sonnet 4.6)
**Date:** 2026-05-15
**Status:** Research complete — pending decisions

---

## Goal

Responder às seguintes perguntas antes de decidir se o 4Shark deve desativar, manter, ou substituir a auto-memory nativa do Claude Code:

1. Quando e como a auto-memory foi introduzida? O que a Anthropic comunicou oficialmente?
2. Quais issues existem no repositório oficial e qual o sentimento delas?
3. O que a comunidade (Reddit, HN, X, blogs) está dizendo?
4. Quais workarounds estão sendo adotados?
5. Quais são as opções concretas de mitigação para o 4Shark, com trade-offs?

**Contexto:** O 4Shark criou a skill `/cleanup-memories` como mitigação local — memórias de baixo valor sendo salvas sem controle estão poluindo o sistema. A pergunta é se vale desativar a feature ou se há alternativa melhor.

---

## Method

- Pesquisa web extensiva (~90 min): documentação oficial (`code.claude.com`), releases do GitHub (`gh api`), issues do repositório `anthropics/claude-code`, artigos técnicos, blogs de desenvolvedores, threads de HN, análises comparativas
- Acesso direto ao CHANGELOG do repositório via `gh api` para datas exatas
- Leitura do system prompt de auto-memory via repositório `Piebald-AI/claude-code-system-prompts` (exposto após o source leak de março 2026)
- Reddit inacessível diretamente via WebFetch — cobertura via agregações e artigos que citam threads

---

## Evidence

### 1. Linha do tempo oficial

#### v2.1.32 — 5 de fevereiro de 2026 (introdução)

Fonte: `gh api repos/anthropics/claude-code/releases`, entrada do CHANGELOG:

> "Claude now automatically records and recalls memories as it works"
> — Release notes v2.1.32, 2026-02-05T17:47:50Z

Essa versão também introduziu Agent Teams (preview). A auto-memory foi introduzida sem comunicado separado, como parte de um release maior que trouxe Opus 4.6.

#### v2.1.59 — 26 de fevereiro de 2026 (refinamento + comando /memory)

> "Claude automatically saves useful context to auto-memory. Manage with /memory"
> — Release notes v2.1.59, 2026-02-26T00:59:24Z

Esta versão adicionou o comando `/memory` e tornou a feature mais visível. A documentação oficial (`code.claude.com/docs/en/memory`) menciona v2.1.59 como requisito mínimo para auto-memory, sugerindo que a v2.1.32 era uma versão experimental/incompleta.

#### v2.1.63 — 28 de fevereiro de 2026 (compartilhamento entre worktrees)

> "Project configs & auto memory now shared across git worktrees of the same repository"
> — Release notes v2.1.63, 2026-02-28T03:45:37Z

#### Março-Abril 2026: auto-dream (preview fechado)

Anthropic testou internamente "Auto Dream" — um processo de consolidação nocturna que limpa e reorganiza o MEMORY.md. Visível no menu `/memory` mas controlado por feature flag server-side, não disponível para o público geral. Terceiros criaram alternativas open-source (ver seção de workarounds).

---

### 2. O que a Anthropic comunicou oficialmente

Fonte: [documentação oficial](https://code.claude.com/docs/en/memory)

**Design intent (declarado):**

> "Auto memory lets Claude accumulate knowledge across sessions without you writing anything. Claude saves notes for itself as it works: build commands, debugging insights, architecture notes, code style preferences, and workflow habits. Claude doesn't save something every session. It decides what's worth remembering based on whether the information would be useful in a future conversation."

**Anúncio oficial em X** (Thariq Shihipar, membro de staff na Anthropic):

> "We've rolled out a new auto-memory feature. Claude now remembers what it learns across sessions — your project context, debugging patterns, preferred approaches — and recalls it later without you having to write anything down."
> — [@trq212](https://x.com/trq212/status/2027109375765356723)

**Posicionamento do produto:** A Anthropic posiciona CLAUDE.md como "suas instruções para o Claude" e MEMORY.md como "o caderno de anotações do Claude sobre o seu projeto" — sistemas complementares, não substitutos.

---

### 3. System prompt da auto-memory (revelado pelo source leak)

Fonte: [`Piebald-AI/claude-code-system-prompts`](https://github.com/Piebald-AI/claude-code-system-prompts/blob/main/system-prompts/system-prompt-memory-instructions.md) (391 tokens)

O sistema instrui o Claude a manter arquivos com frontmatter estruturado. Categorias:

- **`user`** — quem é a pessoa, papel, expertise, preferências
- **`feedback`** — correções e guidance sobre abordagens de trabalho
- **`project`** — objetivos e constraints não visíveis no código ou git history
- **`reference`** — ponteiros externos (URLs, dashboards, tickets)

**Critérios de saving (extraídos do system prompt):**

> "Before creating new memories, check existing files to avoid duplicates — update instead. Remove memories proven incorrect. Don't save information the repository already records (code structure, past fixes, git history, documentation files) or details relevant only to the current conversation."
>
> "When asked to remember repository-level content, instead ask what insight was non-obvious and save that analysis."

**Critério de recall:**

> "Memories appearing in background context blocks reflect their creation time — if one references a file, function, or flag, verify it still exists before recommending it."

**Observação importante:** O system prompt instrui o agente a ser seletivo, mas não define um threshold quantitativo de qualidade. "Worth remembering based on whether the information would be useful in a future conversation" é julgamento subjetivo do modelo — daí a variabilidade relatada pela comunidade.

---

### 4. Mapeamento de issues no repositório oficial

| Issue | Título | Status | Categoria do problema |
|-------|--------|--------|----------------------|
| [#23544](https://github.com/anthropics/claude-code/issues/23544) | Need ability to disable auto-memory (MEMORY.md) | Closed | Sem flag de desativação, shadow state, context bloat |
| [#23750](https://github.com/anthropics/claude-code/issues/23750) | [FEATURE] Option to disable auto-memory | Closed | Conflito com `--no-memory` que desativa tudo inclusive CLAUDE.md |
| [#28276](https://github.com/anthropics/claude-code/issues/28276) | [FEATURE] Configurable auto-memory storage location | Open (duplicate) | Não sincroniza entre máquinas nem no git |
| [#28960](https://github.com/anthropics/claude-code/issues/28960) | [FEATURE] time-based reminders/triggers in auto-memory | Closed as not planned | Falta de triggers temporais, memórias ficam estáticas |
| [#34776](https://github.com/anthropics/claude-code/issues/34776) | [FEATURE] Memory system governance for long-running users | Closed as not planned | Degradação estrutural em projetos com 30+ sessões |
| [#37847](https://github.com/anthropics/claude-code/issues/37847) | Claude Code repeatedly ignores its own auto-memory feedback | Closed as not planned | Memórias salvas mas não aplicadas na prática |
| [#43393](https://github.com/anthropics/claude-code/issues/43393) | Auto-memory feedback not reliably applied | Closed | Mesmas corrigindo recorrendo mesmo com memória salva |
| [#44820](https://github.com/anthropics/claude-code/issues/44820) | [FEATURE] PreMemoryWrite / PostMemoryWrite hook events | Open (stale) | Sem hooks para interceptar/filtrar antes de salvar |
| [#48416](https://github.com/anthropics/claude-code/issues/48416) | [FEATURE] Auto-memory should support user-scoped entries | Closed (duplicate) | Memória não compartilhada entre projetos diferentes |
| [#48465](https://github.com/anthropics/claude-code/issues/48465) | [FEATURE] Allow MCP servers to replace auto memory backend | Open (stale) | MCP ignorado quando auto-memory está ativo |
| [#57574](https://github.com/anthropics/claude-code/issues/57574) | Auto-memory MEMORY.md silently truncated at ~25KB | Closed (duplicate) | Truncagem silenciosa remove as entradas MAIS RECENTES |

**Padrões nas reclamações:**

1. **Confiabilidade zero** — Memórias salvas mas não seguidas na prática (issues #37847, #43393)
2. **Context bloat** — Cada sessão carrega MEMORY.md nos primeiros 200 linhas ou 25KB, mesmo quando já existem regras no CLAUDE.md cobrindo o mesmo terreno
3. **Sem mecanismo de expiração** — Memórias ficam stale, contradizem-se, referenciam arquivos renomeados
4. **Truncagem silenciosa** — Em projetos longos, MEMORY.md cresce e o limite de 25KB trunca as entradas MAIS RECENTES (cronológico), exatamente as mais relevantes
5. **Scope errado** — User-preferences (ex: "prefiro Shell a Python") são salvas por projeto, não seguem o usuário para outros projetos

**Resposta da Anthropic:** Nenhuma das issues acima recebeu resposta pública da Anthropic. A maioria foi fechada como "not planned" ou "duplicate" sem comentário. A issue #44820 (PreMemoryWrite hooks) ficou "stale" sem feedback.

---

### 5. Sentimento por canal

#### GitHub (comportamento observado)

O padrão é claro: issues fechadas como "not planned" sem comentário, requests de desativação granular fechados como "duplicates". A Anthropic não está respondendo publicamente às críticas da auto-memory no repositório.

Citação representativa do issue #23544:

> "Auto-memory creates a parallel memory system outside user control that's difficult to view, audit, or understand. MEMORY.md lives in ~/.claude/projects/ (outside the repo), preventing version control, PR review, and codebase synchronization."

#### HN (Hacker News)

Thread [#47878905](https://news.ycombinator.com/item?id=47878905) sobre os quality reports de Claude Code (732 comentários, April 2026):

> "Silent changes without disclosure — users expressed frustration that behavioral modifications occurred without announcement, violating expectations of product consistency."

Thread de sentiment geral: desenvolvedores frustraram com "silent optimizations" que mudam comportamento sem anúncio — auto-memory se enquadra nessa categoria de mudanças que afetam o contexto de forma opaca.

#### Blogs técnicos e Medium

**Brent W. Peterson** ([fonte](https://medium.com/@brentwpeterson/automatic-memory-is-not-learning-4191f548df4c)):

> "Claude doesn't learn anything from auto memory the way you or I learn from experience...That's not learning. That's configuration."

Após meses de uso em 13 projetos, encontrou apenas 12 linhas no MEMORY.md — o sistema salvou menos do que esperava. A conclusão é que auto-memory captura "o quê" mas não "o porquê".

**Análise de comparação** ([ddewhurst.com](https://ddewhurst.com/blog/claude-mem-vs-auto-memory/)):

Três posições emergem na comunidade:

- **Minimalistas** (40-50%): "A well-crafted CLAUDE.md handles 80-90% of the memory problem with zero dependencies" — toleram ou desligam auto-memory
- **Pragmáticos** (30-40%): Querem auto-memory melhorado mas reconhecem limitações atuais — mantêm ligado, auditam periodicamente  
- **Power users** (10-20%): Relatam ganhos significativos e aceitam o overhead de manutenção

**Dev.to** ([fonte](https://dev.to/gonewx/i-tried-3-different-ways-to-fix-claude-codes-memory-problem-heres-what-actually-worked-30fk)):

> "None offer perfect solutions: 'You can't have perfect memory in a tool that was designed session-by-session.'"

#### Reddit

Acesso direto inacessível (reddit.com e old.reddit.com bloqueados para WebFetch). Cobertura indireta via agregações indica que r/ClaudeAI tem 4.200+ contribuidores semanais, com memória sendo um dos tópicos mais discutidos. Sentimento dividido, com desenvolvedores que investem tempo em configuração relatando ganhos, e os que tratam como autocomplete ficando frustrados.

Evidência indireta do issue #23544 que menciona "workarounds que a comunidade tentou":
- Deletar `~/.claude/projects/*/memory/` manualmente (inefetivo — arquivos são recriados)
- Adicionar "do not use auto-memory" ao CLAUDE.md (não confiável, conflita com system prompt)
- **Nenhum workaround viável reportado como realmente funcionando** antes do `autoMemoryEnabled: false` ser implementado

#### X/Twitter

Anthony Kroeger ([fonte](https://x.com/kr0der/status/2036235321780621738)) sobre auto-dream (encontrado no Reddit antes do anúncio oficial):

> "just found out Claude Code has a new (unreleased?) feature called 'Auto-dream' under /memory... this basically runs a subagent periodically to consolidate Claude's memory files for better long-term storage. this is pretty crazy because that's basically how [human memory works]"

---

### 6. Limitações técnicas documentadas

#### Truncagem silenciosa (issue #57574)

MEMORY.md tem cap de 200 linhas ou 25KB. Como o arquivo é cronológico, o truncamento silencioso remove as **entradas mais recentes** — exatamente as mais relevantes. O warning existe mas está no system prompt, não visível ao usuário:

> "WARNING: MEMORY.md is 34.3KB (limit: 24.4KB) — index entries are too long."

Um usuário com 60+ sessões chegou a 34.3KB e perdeu as últimas semanas de memória sem perceber.

#### Memórias salvas mas não aplicadas (issues #37847, #43393)

Citação do issue #43393:

> "The memories load as part of a large system context (CLAUDE.md, rules files, memory files). With many rules and memories competing for attention, behavioral memories may not have sufficient 'weight' compared to the immediate task context."

Exemplos concretos do issue #37847:
- Memória: "Use `&&` not newlines for chaining bash commands" → violada 8 vezes na mesma sessão
- Memória: "Always invoke available skills via the Skill tool" → Claude ignorou e procedeu manualmente

#### MCP conflito (issue #48465)

Quando MCP memory tools estão configurados, a auto-memory do system prompt tem **prioridade maior**. O agente usa MEMORY.md e ignora os MCP tools — impossível substituir o backend sem desativar auto-memory completamente.

---

### 7. Como outras ferramentas tratam memória

| Ferramenta | Abordagem | Característica |
|------------|-----------|----------------|
| **Cursor** | Codebase indexing via AST + vector embeddings (Turbopuffer) | "Memory is your codebase, and your codebase doesn't lie" — sem LLM-written summaries |
| **Aider** | Sem auto-memory nativa; CONVENTIONS.md manual | 4.2x menos tokens que Claude Code; sem overhead de memória |
| **Cline** | MCP-based memory opcional; sem auto-memory | Deixa para o usuário decidir se quer e como |
| **Claude Code** | Markdown files + MEMORY.md index | Auto-saving com critério do modelo; sujeito a noise |

A Anthropic escolheu a abordagem de texto plano (markdown) ao invés de vetores ou indexação de código — mais simples, mais barata, mais transparente, mas menos precisa e mais sujeita a degradação ao longo do tempo.

---

### 8. Projetos da comunidade que surgiram como resposta

**claude-mem** ([github.com/thedotmack/claude-mem](https://github.com/thedotmack/claude-mem)):
- 75.9k stars, 6.5k forks
- SQLite + ChromaDB + semantic search + web UI
- Surgiu em agosto 2025 (antes da auto-memory nativa) como alternativa pesada
- Riscos: instabilidade (7 releases em 3 dias com reverter), process leaks com centenas de zombies, 641 processos Python consumindo 75% de CPU em versões anteriores

**dream-skill** ([github.com/grandamenium/dream-skill](https://github.com/grandamenium/dream-skill)):
- 60 stars, 13 forks
- Replica o auto-dream não lançado da Anthropic
- 4 fases: Orient → Gather → Consolidate → Prune
- Trigger automático via Stop hook a cada 24h

---

## Conclusions

### Sentimento dominante

**Frustração estrutural com soluções pragmáticas** — a comunidade não está pedindo para remover auto-memory, está pedindo mais controle sobre ela. O sentimento é "tem potencial, mas na prática não cumpre a promessa por falta de governança".

Evidências que suportam isso:
1. Issues sobre **desativar** foram fechadas como "done" quando `autoMemoryEnabled: false` foi adicionado — a Anthropic interpretou como "dê controle, não remova"
2. Issues sobre **governança** (expiração, prioridade, audit) foram fechadas como "not planned" — a Anthropic não está investindo em sofisticar o sistema
3. A comunidade criou alternativas (dream-skill, claude-mem) ao invés de abandonar a feature

### O problema real é de confiabilidade, não de volume

O Paulo identificou "salva MUITA coisa de baixo valor". A pesquisa encontra um problema complementar que agrava: **as memórias são salvas mas frequentemente ignoradas na prática**. O sistema cria falsa sensação de segurança — você vê "Writing memory" e assume que o comportamento vai mudar, mas issues #37847 e #43393 documentam que a mesma correção precisa ser feita repetidamente mesmo com memória salva.

A causa raiz é que memórias no MEMORY.md competem com contexto de task imediato no context window, e o modelo prioriza o task context.

### Auto-memory é um sistema de `feedback` mais do que de `instructions`

O system prompt categoriza memórias como: `user`, `feedback`, `project`, `reference`. Para o 4Shark, que tem regras sofisticadas no CLAUDE.md global, o overlap com `feedback` é o problema maior — uma correção que já está codificada no CLAUDE.md como regra explícita não deveria entrar no MEMORY.md como feedback. Mas o agente não tem como saber que a regra já existe e salva de qualquer forma.

---

## Next Steps

### Opções de mitigação para o 4Shark

| Opção | Viabilidade | Trade-off | Evidência funciona |
|-------|------------|-----------|-------------------|
| **A: Desativar globalmente** (`"autoMemoryEnabled": false` em `~/.claude/settings.json`) | Fácil — 1 linha de config | Perde qualquer valor que auto-memory oferece; `/cleanup-memories` fica sem inbox para processar | Sim — documentado na [docs oficiais](https://code.claude.com/docs/en/memory); env var `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` como alternativa |
| **B: Manter + instruir threshold mais alto no CLAUDE.md** | Fácil — instrução de texto | Não confiável — system prompt tem prioridade sobre CLAUDE.md; comunidade relata que "do not use auto-memory in CLAUDE.md" não funciona consistentemente | Parcialmente — funciona como dica, não como restrição |
| **C: Hook PreToolUse bloqueando Writes em `~/.claude/projects/*/memory/`** | Médio — requer regex de path no hook | Frágil — naming interno não documentado pode mudar entre releases; community classifica como "unreliable workaround" | Parcialmente — possível mas issue #44820 documenta a fragilidade |
| **D: Manter `/cleanup-memories` como está** | Fácil — já existe | Custo recorrente de tempo; sintoma tratado, não a causa | Sim — já funciona para o 4Shark |
| **E: Desativar + usar apenas CLAUDE.md global + rules/** | Fácil — settings.json + organização de regras | Perde aprendizado automático; requer disciplina para atualizar CLAUDE.md manualmente | Sim — abordagem "minimalista" validada pela comunidade |
| **F: PreMemoryWrite hook** (filtra antes de salvar) | Difícil — não existe ainda | Issue #44820 propõe isso mas está "stale" sem resposta da Anthropic | Não — feature não disponível |

### Recomendação baseada em evidências

**Para o caso específico do 4Shark** (CLAUDE.md global sofisticado, skill `/cleanup-memories`, regras já explícitas):

A opção **A (desativar globalmente)** resolve o problema estrutural. O 4Shark já tem:
- CLAUDE.md global com regras detalhadas
- Sistema de tiers (Tier 1/2/3 docs)
- Hooks para injetar contexto situacional
- `/cleanup-memories` como workflow de curadoria

Auto-memory adicionaria valor em projetos sem essa estrutura. No 4Shark, o sistema de memória já é explícito e bem gerenciado — auto-memory é noise adicional competindo com regras já codificadas.

**Alternativa menos radical:** Opção **E** — desativar globalmente mas com uma instrução no CLAUDE.md para salvar explicitamente quando o engenheiro pedir ("lembre disso"). Isso preserva o comportamento sob demanda sem o saving automático.

**O que NÃO fazer:** Opção B (confiar em instrução de CLAUDE.md para restringir) — a pesquisa documentou que o system prompt de auto-memory tem prioridade e a instrução não é confiável.

### Decisão que o engenheiro precisa tomar

Antes de qualquer implementação, o engenheiro precisa responder: **O valor que `/cleanup-memories` extrai das memórias (ao rotear para CLAUDE.md ou Tier 2 docs) compensa o custo recorrente de executá-la periodicamente?**

- Se **não** → Opção A: desativar globalmente; memórias de qualidade entram no CLAUDE.md manualmente
- Se **sim, mas quero reduzir o ruído** → Opção E: desativar auto-save, preservar save explícito via `/memory`
- Se **sim, e o workflow atual está ok** → Opção D: manter como está, aceitar o custo como parte do processo

---

> **O que é um Spike?** Tarefa de pesquisa time-boxed para reduzir incerteza. O objetivo é encontrar fatos, não tomar decisões. Este spike pode gerar um PLAN.md (se a decisão for implementar uma mitigação) ou simplesmente documentar o conhecimento para referência futura.
>
> **Leitura adicional:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
