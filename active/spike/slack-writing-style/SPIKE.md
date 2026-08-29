# SPIKE — Paulo's Slack writing style

**Question**: can the engineer's own Slack writing style be extracted from history well enough to be encoded as a rule?

**Answer**: yes for one of the two registers, with a caveat that decides whether the whole exercise is worth doing.

**Storage decision**: this stays OUT of the `dot-claude` repository. A personal writing style is not a team standard, and `dot-claude` is readable by everyone with access to the 4Shark configuration repo. Where it eventually lives is still open — see § Open question.

---

## Source material

Slack search over `from:<@U32986XT6>`, sampled across 2026-08-18 → 2026-08-28: roughly 100 messages spanning `#suporte`, `#commcenter`, `#virtual-connection`, `#atento-co`, and DMs with Sergio Ajimura, Leandro Almeida, Camila Bergamasco and Santiago Velasquez.

Coverage is good for the recent window. Older history was not sampled — the recent window already produced a stable pattern, and every additional page returned the same shapes.

---

## The central finding — there are TWO registers, and only one of them is his

The history splits cleanly into two kinds of message, and they do not share a single convention.

**Register A — the fast conversational message.** This is unmistakably his, it is the overwhelming majority of the volume, and it is what a style rule would actually have to reproduce.

**Register B — the long structured technical report.** Accented, punctuated, paragraphed, em-dashes, a clean "what I did → what I found → what I need from you" arc. Several of these appear in `#commcenter` and `#suporte`.

**The caveat**: Register B carries the fingerprints of assistant-authored text — the em-dash apposition, the paragraph rhythm, the closing actionable ask. Those messages were very likely drafted in a Claude session and pasted. **Encoding Register B as "how Paulo writes" would be teaching the assistant to imitate itself**, which is worth nothing. Register A is the only register the history proves is his.

---

## Register A — the fast conversational message

### Orthography

Lowercase throughout, including proper nouns and the start of a sentence: `blz sergio`, `oi sergio`, `foi esse sim camila`.

Accents are dropped: `nao`, `voce`, `ja`, `entao`, `declaracoes`, `correcao`, `migracao`, `usuario`. This is consistent, not occasional — an accented short message does not appear in the sample.

No terminal period. A short message ends where the thought ends.

### Message shape

One idea per message, fired in sequence seconds apart, rather than one paragraph carrying three ideas. A single exchange routinely spans five or six messages within a minute:

```
resolvido
nao era a gente
ele saiu da vpn e funcionou
é caca la na cpn da atento que nao ta aceitando esse dominio ou redirecionando de alguma forma
```

### Openers

A message that starts a turn almost always opens with a marker before the content: `opa`, `oi <nome>`, `blz`, `ah`, `hmmm` / `hmmmm`, `show`.

```
opa, vou ver agora
opa, to meio corrido aqui agora, pode ser daqui a pouco
hmmm, deixa eu ver, acho que foi por email entao
ah, eles pediram por email junto com o cancelamento
```

### Naming the person

The name lands mid-sentence or at the end as often as at the start — it is a softener, not an address label: `foi esse sim camila`, `blz sergio`, `nao tenho certeza camila, vou confirmar`, `acabei de subir o fix para esse cenario @Ione`.

### Voice

First person, active, present or immediate past: `vou ver`, `ja testei aqui`, `acabei de subir o fix`, `to fazendo`, `ja vi aqui`, `rodei o script`.

Uncertainty is stated plainly and immediately paired with the next action — never hedged and never left hanging:

```
nao tenho certeza camila, vou confirmar
deixa eu pedir para ia checar
vou ver se tem alguma outra coisa que pode justificar isso do nosso lado
```

A commitment to come back is explicit: `ja te chamo`, `quando puder rodar avisa`, `me avisa que é permissão e eu ajusto`.

### Register markers

Informal, warm, Brazilian: `top demais`, `boaaaa`, `mandou bala`, `ta na mao`, `que caca`, `valeu`, `show`, `demais`.

Diminutive for downplaying a problem: `bugzinho`.

Repeated vowel for emphasis: `boaaaa`, `hmmmm`.

Laughter: `rs` for a small one, `kkkkkkk` for a real one.

Self-deprecating and candid about the work, including about the tooling:

```
eu ja tava brigando com a IA aqui que tinha algo errado e ela dizendo que tava tudo lindo
ai fui olhar os logs eu mesmo e de fato ta tudo lindo
kkkkkkk
```

### Spanish / portuñol

With Santiago and in the LATAM channels he switches into a freely mixed Spanish-Portuguese without correcting himself, and the informality carries over unchanged:

```
tambien no tengo certeza santi
ah si, esso és muy simples de explicar
muy buena Santi
pero no entendi la pronunciación
```

The mixing is the style, not an error to clean up. `nao`, `esso`, `nosotros ... respondemos`, `pero ahora, lo proprio sistema identifica` all coexist in the same message.

---

## Register B — the structured technical report

Described here for completeness, and flagged as **not usable as a style source** for the reason above.

Full accents and punctuation. Paragraphs separated by blank lines. Opens by naming the recipient. Carries exact figures — currency to the cent, percentages to two decimals, entity IDs verbatim. Corrects his own earlier statement inline rather than in a follow-up. Enumerates with `Primeira:` / `Segunda:` when two subjects share one message. Closes with a concrete actionable ask.

The one trait in Register B that is plausibly his rather than the assistant's is the **self-correction in the same breath** (`e me corrigindo antes: eles não passam de 100% como eu te disse`) — it matches Register A's candor, which is a genuine signal.

---

## What a rule could actually encode

Register A is reproducible mechanically: lowercase, no accents, no terminal period, one idea per message, an opener marker, first-person active verbs, an explicit next step, the informal marker vocabulary.

What a rule cannot decide is **which register a given message wants**. That is a judgment about audience and stakes — a support answer to Camila is Register A, a reconciliation report to Patrick is Register B — and it is exactly the judgment that made Register B get drafted with assistance in the first place.

---

## Open question — where this lives, and whether it is worth the price

Three shapes were considered. None is decided.

**`~/.claude/CLAUDE.local.md`** — machine-local, git-ignored, loaded into every session automatically. Cheapest to reach, zero sharing risk. Cost: it lives on one machine only, and it is loaded on every session including ones that will never touch Slack.

**A file under `~/Projects/4Shark/dot-claude-plans/`** — his own private repo, so it survives across machines via his own remote, and it is not shared with the team. Cost: nothing loads it automatically; a session has to be told to read it.

**A personal skill outside `dot-claude`** — invocable on demand, so it costs nothing until a Slack message is actually being written. Cost: it has to be installed per machine, and `dot-claude`'s own tooling does not manage anything outside itself.

The price to weigh is not storage — it is that any of these adds a per-machine step that `dot-claude`'s PR flow currently handles for free, and the repository's own history shows that per-machine setup steps do not propagate on their own (the `check-plans-autocommit` and `check-config-self-heal` nudges exist precisely because of that).
