# PLAN — Granola → ~/.meeting-notes/ nightly sync

## Current Situation

- **Canonical archive**: `~/.meeting-notes/{4shark,personal}/{year}/{date}-{slug}-{resumo,transcript}.md` — 378+ reuniões migradas do Spark, corrigidas e classificadas por frontmatter.
- **Granola**: fonte ativa pós-migração. Transcript e summary do Granola têm erros de speech-to-text (4Shark → "Four Shark", Almaviva → "Alma Viva", etc.).
- **Granola é read-only**: não há API/MCP oficial para escrever transcript ou folders. Correção tem que acontecer fora do Granola.
- **Wispr Flow**: app local no macOS com dicionário de correções em SQLite (`~/Library/Application Support/Wispr Flow/flow.sqlite`, tabela `Dictionary`). Hoje tem 48 entradas com mapeamento `phrase → replacement` relevante (ex: `foreshark → 4Shark`).
- **Skill `/meeting-context`**: já deployada, busca SÓ em `~/.meeting-notes/`. Depende do sync pra ter cobertura atualizada.
- **Folder structure no Granola**: classificação visual/organizacional, manual via UI. Recorrentes herdam folder automaticamente.

## Objective / Target State

- **Desired outcome**: reuniões gravadas no Granola durante o dia aparecem de manhã, no dia seguinte, em `~/.meeting-notes/4shark/YYYY/` já com:
  - Transcript com correções do Wispr aplicadas
  - Summary regenerado (Sonnet) a partir do transcript corrigido
  - Frontmatter classificado (`client:`/`vendor:`/`internal:`/etc.) baseado em heurísticas + fallback via LLM
  - Invitees extraídos do Granola
- **Notificação macOS** ao terminar: "N reuniões sincronizadas (X ok, Y com erro)".
- **Success criteria**:
  - Script roda 04:00 seg-sex via launchd sem intervenção
  - Pelo menos 95% das reuniões do dia anterior viram pares de arquivos em `~/.meeting-notes/` automaticamente
  - Reuniões que falham na classificação automática são surfaced na notificação pra revisão manual
  - Wispr é source of truth único pro vocabulário (editado no Wispr, script lê do SQLite)
  - Skill `/meeting-context` consegue responder sobre reunião do dia anterior sem hack

## Problem / New Feature

- **Objective description**: criar automação noturna que consolida Granola + Wispr vocabulary num pipeline: extract → correct → re-summarize → classify → write → notify.
- **Dependências**:
  - Granola macOS app instalado (rodando em background, cache atualizado)
  - Wispr Flow rodando ou com vocabulário editado (SQLite pode ser lido mesmo com app aberto via `PRAGMA busy_timeout`)
  - Anthropic API key (pra Sonnet) — do 1Password

## Challenges, Difficulties and Risks

- **Técnicos**:
  - **Acesso ao Granola**: MCP oficial é pra invocação interativa de agentes, não pra scripts. Alternativas: (a) ler cache local `~/Library/Application Support/Granola/cache-v3.json`, (b) usar REST API `api.granola.ai` com token extraído do cache, (c) adaptar algum MCP comunitário em Python.
  - **Formato do cache do Granola pode mudar**: comunitários já lidam com v3 e v4. Precisa fallback ou versão-aware parsing.
  - **SQLite lock** no Wispr: se Wispr está escrevendo, leitura pode travar. Copiar o SQLite pra /tmp antes de ler mitiga.
  - **Classification fidelity**: invitee domain matching (ex: `@atento.com` → `client: Atento`) cobre o easy path. Reuniões internas/ambíguas vão precisar de LLM ou revisão manual.
  - **Rate limit**: Sonnet tem limite. Em dias de muitas reuniões (10+), serializar chamadas com pequeno delay.
- **Produto/UX**:
  - Se o script falhar silenciosamente, eu só descubro quando tento buscar e não acho — notificação de erro é crítica
  - Duplicatas: se o script rodar duas vezes no mesmo dia, não pode duplicar arquivos. Idempotência via checagem de existência de `{date}-{slug}-resumo.md`
- **Security/privacy**:
  - Token do Granola (WorkOS access_token) no cache local — script pode extrair, mas não pode logar em /tmp/logs
  - Anthropic API key precisa vir do 1Password via `op read`, não hardcoded
- **Performance**:
  - Script deve terminar em <5 min mesmo com 20 reuniões. Sonnet regen é o gargalo (~15s por reunião) — paralelizar ou serializar com budget.

## Solution Options (comparative)

- **Option 1 — Python script + REST API + launchd**
  - **How it works**: Python 3 script. Lê Wispr SQLite. Lê Granola cache pra pegar token + meeting IDs → chama REST API `api.granola.ai` pra pegar metadata e transcript. Aplica regex replacement do Wispr. Chama Anthropic SDK Sonnet pra regenerar summary. Classifica via rules + LLM fallback. Escreve markdown com frontmatter em `~/.meeting-notes/`. Notifica via `osascript -e 'display notification...'`. Agenda via launchd plist em `~/Library/LaunchAgents/`.
  - **Pros**: controle total; código em Python é legível e testável; launchd é o jeito macOS-nativo; REST API é mais estável que parsear cache
  - **Cons**: token extraction do cache é hack documentado mas não oficial; se Granola revogar o token, script quebra
  - **When NOT to use**: se Granola publicar API write oficial (substituiria a arquitetura)

- **Option 2 — Shell script + jq + cache-only**
  - **How it works**: bash + jq lê `cache-v3.json` direto. Sed/awk aplica correções. curl + anthropic API pra regen. Mesma escrita + notification.
  - **Pros**: zero dependências Python; mais rápido pra setup
  - **Cons**: lógica complexa em shell é inferno; parsing de cache-v3.json (JSON aninhado dentro de string) é chato em jq; regen de summary e classificação via LLM ficam awkward; testabilidade zero
  - **When NOT to use**: quando esperamos manter o script por mais de 2 meses (que é o caso)

- **Option 3 — MCP client Python com SDK oficial**
  - **How it works**: usa a lib `mcp` do Anthropic (Python) pra conectar no MCP do Granola, mesmos tools que o Claude usa. Aplica correções, regen, escreve, notifica.
  - **Pros**: usa API oficial (não hackeia cache); mais resiliente a mudanças do Granola
  - **Cons**: o MCP oficial do Granola é HTTP remoto; autenticação é via navegador (OAuth); pra rodar headless no launchd pode ser problemático
  - **When NOT to use**: se auth OAuth não funcionar sem interação

## Proposed Steps (high level, don't execute yet)

1. **Setup scripts directory**:
   - Criar `~/Projects/4Shark/.claude/scripts/` já existe. Colocar script pessoal fora do repo team (em `~/bin/sync-granola-to-notes.py` ou similar), pois é personal tooling.
   - Ou, se preferir consolidar, colocar no repo team como skill/command com pre-check condicional (outros devs sem Granola/Wispr não ativam).

2. **Python script** (`~/bin/sync-granola-to-notes.py`):
   - Deps: `sqlite3` (stdlib), `requests` ou `httpx`, `anthropic` SDK, `pyyaml`
   - Módulos:
     - `wispr.py` — lê SQLite, retorna dict `{phrase: replacement}`
     - `granola.py` — acesso ao Granola (REST ou cache), retorna list de meetings com transcript
     - `corrector.py` — aplica o dict do Wispr como regex case-sensitive word-boundary
     - `summarizer.py` — chama Sonnet via Anthropic SDK, regenera summary em estrutura equivalente ao formato Spark
     - `classifier.py` — rules engine (domain→entity map) + LLM fallback
     - `writer.py` — escreve `{date}-{slug}-resumo.md` e `{date}-{slug}-transcript.md` seguindo o template da migração
     - `notify.py` — osascript display notification + arquivo de log em `~/Library/Logs/granola-sync.log`
     - `sync.py` — orquestrador, idempotente (pula se arquivo já existe)

3. **Classification rules** (hardcoded + dinâmicas):
   - Primeira passada: domain-based rules (`@atento.com` → `client: Atento`, `@4shark.com.br` only → `internal: alignment`, etc.). Pegar do SPIKE arquivado as convenções.
   - Segunda passada (fallback): se rules não bateram, chama Sonnet passando título + invitees + lista de entidades conhecidas → retorna classificação
   - Terceira: se LLM retornar "unknown", escreve com `tags: [UNCLASSIFIED]` e surface na notificação

4. **Idempotência e retry**:
   - Antes de escrever, checar se `{date}-{slug}-resumo.md` já existe — skip
   - Se Sonnet falhar, 3 retries com backoff exponencial
   - Se Granola API falhar, aborta o meeting e continua com próximo; report na notificação

5. **launchd plist**:
   - `~/Library/LaunchAgents/com.plribeiro3000.granola-sync.plist`
   - `StartCalendarInterval`: 04:00, weekday 1-5 (seg-sex)
   - `Program`: path do script
   - `StandardOutPath` + `StandardErrorPath`: `~/Library/Logs/granola-sync-{out,err}.log`
   - `RunAtLoad: false` (não rodar na carga inicial)

6. **macOS notification**:
   - Sucesso: "✅ Granola sync: N reuniões (todas ok)" — click silencioso
   - Com unclassified: "⚠️ Granola sync: N reuniões (X precisam revisão)" — lista os títulos não classificados
   - Falha total: "❌ Granola sync falhou — ver /tmp/granola-sync-*.log"
   - Usar `osascript -e 'display notification ... with title ... sound name "Glass"'`

7. **Anthropic API key**:
   - `op read "op://Private/Anthropic API/credential"` (ou caminho correto no 1Password)
   - Script faz esse read no início, falha early se não tiver MFA session no op

8. **Testing**:
   - Dry-run flag (`--dry-run`) que não escreve arquivos, só loga o que faria
   - Run manual em modo verbose pra primeira vez (hoje: sincronizar 16-17/abr)

9. **Documentation**:
   - Criar `~/.meeting-notes/.README.md` com link pro script + troubleshooting
   - Entrada no CLAUDE.md global explicando o fluxo (opcional — esse é o tipo de coisa que só eu uso)

## Internal References

- Wispr SQLite: `~/Library/Application Support/Wispr Flow/flow.sqlite`, tabela `Dictionary`
- Granola cache: `~/Library/Application Support/Granola/cache-v3.json`
- Granola REST: `https://api.granola.ai/v1/get-documents`, `get-document-transcript/:id`
- SPIKE arquivado: `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md` — tem canonical entity names, classification schema, naming conventions
- Meeting-context skill: `~/.claude/commands/meeting-context.md`
- launchd format: https://www.launchd.info/ (para reference do plist)

---

## Decisions (approved 2026-04-17)

- **Option 1** — Python + REST API `api.granola.ai` + launchd
- **Script location**: `~/bin/sync-granola-to-notes.py` (pessoal, fora de repo)
- **Classification on miss = skip + notify**: se nenhuma regra bate pro meeting, **NÃO escreve arquivo**. Notifica o usuário com lista dos meetings pendentes. Usuário adiciona a regra nova, próximo run reprocessa.
- **Lookback window de 7 dias**: script sempre escaneia os últimos 7 dias do Granola, não só o dia anterior. Pula idempotentemente o que já existe em `~/.meeting-notes/`. Isso dá 1 semana de janela pra tratar entidades novas.
- **Granola folders**: não é responsabilidade do script. Fica desacoplado.
- **Schedule**: seg-sex 04:00 via launchd. Segunda-feira cobre sex/sab/dom dentro do lookback de 7 dias.
