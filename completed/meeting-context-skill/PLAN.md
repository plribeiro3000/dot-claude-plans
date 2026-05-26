# PLAN — meeting-context skill (meeting notes + Granola MCP fallback)

## Current Situation

- **Meeting notes migradas**: 378 reuniões em `~/.meeting-notes/{scope}/{year}/` como markdown com frontmatter (resumo + transcript pairs). Fonte canônica de histórico pré-Granola.
- **Granola MCP**: já configurado em `~/.claude.json` sob scope `~/Projects/4Shark/app` (tipo HTTP, URL `https://mcp.granola.ai/mcp`). Disponibiliza `mcp__granola__get_meeting_transcript`, `mcp__granola__query_granola_meetings`, `mcp__granola__list_meetings`, `mcp__granola__list_meeting_folders`, `mcp__granola__get_meetings`.
- **Estado do Claude Code**: quando o usuário pergunta sobre reuniões passadas, não há comportamento estruturado — Claude improvisa (lê diretórios, faz grep sem ordem, ou apenas responde do training).
- **Ambiente compartilhado**: `~/.claude/` é git-tracked via `~/Projects/4Shark/.claude/` (team 4Shark). Mudanças aplicadas lá afetam todos os engenheiros.
- **Limitação**: só o Paulo tem `~/.meeting-notes/` e Granola configurado. Outros devs não podem ter quebra por falta desses recursos.

## Objective / Target State

- **Desired outcome**: quando o engenheiro faz pergunta sobre reuniões ("o que o cliente X disse?", "quando começou o projeto Y?", "histórico de alinhamentos com Z"), Claude:
  1. Primeiro faz grep determinístico em `~/.meeting-notes/`
  2. Se não achar ou resultado for parcial, cai pra Granola MCP
  3. Responde com citação de arquivo + data (ou ID da reunião do Granola)
- **Condicional e silencioso**: se `~/.meeting-notes/` não existe, skill não ativa. Se Granola MCP não está configurado, skill pula fallback. Sem erro, sem ruído.
- **Success criteria**:
  - Engenheiro do time 4Shark que faz `git pull` em `~/.claude/` não vê comportamento novo nem erro
  - Paulo, ao perguntar sobre reuniões, tem busca automática em meeting notes primeiro e Granola depois
  - Respostas sempre citam a fonte (arquivo `:linha` ou meeting ID)

## Problem / New Feature

- **Objective description**: criar uma skill invocável `meeting-context` que estrutura a busca em duas fontes hierárquicas (local markdown → Granola MCP), com auto-detecção de disponibilidade.
- **Symptoms atuais**: Claude hoje, quando perguntado "o que cliente X disse em março?", pode tentar WebSearch, listar diretórios aleatórios, ou responder "não tenho acesso". Sem consistência.

## Challenges, Difficulties and Risks

- **Técnicos**:
  - Invocação: skill tem que ativar em perguntas relevantes sem ser invasiva (não rodar em toda conversa)
  - Deduplicação: reuniões novas do Granola podem eventualmente ser espelhadas em `~/.meeting-notes/` — skill precisa não retornar duplicatas
  - Escala: grep em 755 arquivos é barato, mas Granola MCP pode ter latência
- **Produto/UX**:
  - Condicional por filesystem é frágil — se Paulo deletar `~/.meeting-notes/` por engano, skill desliga silenciosamente (sem aviso)
  - Outros devs podem ficar confusos ao ver skill listada mas que "não faz nada" na máquina deles
- **Security/privacy**:
  - Meeting notes contêm conversas confidenciais com clientes — skill nunca deve vazar conteúdo em commits, PRs, issues
  - Granola MCP é HTTP — tráfego passa pela rede da Granola
- **Performance**:
  - Grep é local, instantâneo
  - Granola MCP tem roundtrip de rede — só usar como fallback, não como primário

## Solution Options (comparative)

- **Option 1 — Skill única com auto-check de ambiente**
  - **How it works**: arquivo `~/.claude/skills/meeting-context.md` (via PR no repo team). Primeira instrução do skill: verificar se `~/.meeting-notes/` existe. Se não, skill termina imediatamente sem fazer nada. Se sim, procede com grep → Granola fallback. Description do skill ativa auto-match em perguntas sobre reuniões/histórico/clientes.
  - **Pros**: um único arquivo versionado no repo team; outros devs não têm efeito adverso; fluxo de invocação explícito (`/meeting-context`) ou auto-match via description
  - **Cons**: skill aparece na lista de skills dos outros devs mesmo não servindo pra eles (ruído visual baixo); auto-match depende da qualidade da description
  - **When NOT to use**: se time decidir que skills condicionais são antipattern

- **Option 2 — Skill pessoal fora do repo**
  - **How it works**: criar skill em local fora de `~/.claude/` (ex: `~/my-skills/meeting-context.md`) e referenciar via `settings.local.json` personal. Não entra no repo team.
  - **Pros**: zero ruído pros outros devs; totalmente isolado
  - **Cons**: Claude Code padrão busca skills em `~/.claude/skills/` — mecanismo pra skills externas exige configuração custom; divergência entre pessoal e time; se esquecer, eu perco ao trocar de máquina
  - **When NOT to use**: quando o skill pode ser útil pro time no futuro (ex: se outros devs começarem a usar Granola, skill já existe)

- **Option 3 — CLAUDE.md reference condicional**
  - **How it works**: adicionar no `~/.claude/CLAUDE.md` uma seção que referencia `@~/.meeting-notes/INSTRUCTIONS.md` (arquivo que só existe na máquina do Paulo). Se arquivo não existe, @-include falha silenciosamente ou gera warning.
  - **Pros**: carrega automaticamente, sem precisar invocar skill
  - **Cons**: consome contexto sempre (não sob demanda); se @-include quebrar em outros devs, CLAUDE.md vira incompatível; comportamento de @-include em arquivos ausentes não é garantido
  - **When NOT to use**: sempre que possível usar skill sob demanda

## Proposed Steps (high level, don't execute yet)

1. Criar branch `feature/meeting-context-skill` em `~/Projects/4Shark/.claude/`
2. Criar `~/Projects/4Shark/.claude/skills/meeting-context.md` com:
   - Frontmatter YAML (name, description com keywords de ativação)
   - Seção "Pre-check" instruindo: se `~/.meeting-notes/` não existe, encerrar imediatamente
   - Seção "Primary source": instruções de grep em `~/.meeting-notes/{4shark,personal}/{year}/`, filtros por frontmatter (client, vendor, internal, date)
   - Seção "Fallback": como invocar `mcp__granola__query_granola_meetings` se resultado local for vazio/parcial
   - Seção "Output contract": respostas sempre com citação `arquivo:linha` ou `granola_meeting_id`
   - Seção "Deduplicação": se Granola retornar reuniões com data/título já presentes nas notes locais, descartar o duplicado do Granola
3. Atualizar `~/Projects/4Shark/.claude/README.md` ou `CLAUDE.md` (se fizer sentido) listando a skill como opcional
4. Commit: `feat(skills): add meeting-context skill for history queries`
5. Push + abrir PR contra `develop`
6. Após merge: `cd ~/.claude && git pull`
7. Testar invocação: "o que conversamos com Atento em março?" → skill deveria ativar, grepar `~/.meeting-notes/`, retornar matches com citação
8. Testar auto-desativação em máquina sem `~/.meeting-notes/` (ou simulando com `mv ~/.meeting-notes /tmp/meeting-notes-bak`)

## Internal References

- Meeting notes: `~/.meeting-notes/{4shark,personal}/{2025,2026}/*.md` (755 arquivos)
- Frontmatter structure: documented in `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md`
- Granola MCP config: `~/.claude.json` → `projects → ~/Projects/4Shark/app → mcpServers.granola`
- Skills directory convention: `~/.claude/skills/*.md` (team-shared via git)

---

**Question:** Which option do you prefer to follow?
Answer with: `APPROVED: Option 1` **or** `APPROVED: Option 2` **or** `APPROVED: Option 3`.
(Alternative options are welcome, describe if applicable.)
