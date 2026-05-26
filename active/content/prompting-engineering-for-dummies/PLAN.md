# Prompting Engineering for Dummies — Presentation Plan

## Objective

Internal team presentation to shake the team out of their comfort zone. The title says "Prompt Engineering" but the real subject is **communication**. The goal: they leave thinking "I know nothing, I need to catch up."

## Target Audience

4Shark team — mixed audience: majority is operational and commercial staff, plus one engineer and one agency developer. Most of the audience is non-technical. They have access to ChatGPT (operations) and Claude Code (engineering) but barely use them. Examples and language must be universal.

## The Real Message

This presentation is about **communication**, not about AI.

The core insight: people who fail at communicating with AI also fail at communicating with people. The difference? When you communicate poorly with a person, that person makes a **huge effort** to understand the gaps, fill in the missing context, and figure out what you actually meant. They compensate for you. So you walk away thinking you communicated well.

AI doesn't do that. AI interprets exactly what you say. AI is the **mirror of your real communication skills** — no one on the other side compensating for your gaps.

That's why people think AI "doesn't work" — it works perfectly. It just exposes that their communication was never as good as they thought.

---

## Narrative Arc

### Act 1 — The Car Example (Slides 1–7)

Hook. Show how the same request, poorly communicated, produces wrong results every time.

| Slide | Type | Content |
|-------|------|---------|
| 1 | Title | **Prompting Engineering for Dummies** |
| 2 | Text only | Prompt: *"Faz um carro pra mim"* |
| 3 | Image | A picture of a car (just an image, a photo) |
| 4 | Text | *"Pô, mas não era isso. Faz a imagem de um carro que funciona."* |
| 5 | Image | A car driving on a road (still just an image) |
| 6 | Text | *"Não, cara, eu não quero imagem. Eu quero um carro que funciona!"* |
| 7 | Image | A technical blueprint/architectural drawing of a car — exploded view showing how parts connect (doors, steering wheel, engine, chassis) |

**Purpose**: Each iteration shows the AI doing *exactly* what was asked — the problem is never the AI, it's the instruction.

### Act 2 — Where's the Error? (Slide 8)

| Slide | Type | Content |
|-------|------|---------|
| 8 | Question slide | **"Onde está o erro?"** |

**Facilitator notes**: Pause here. Ask the team directly. Let them articulate the problem themselves. Push until someone says "communication" or "context." Reinforce: *"Eu sei que tô batendo na mesma tecla, mas ficou claro pra vocês o problema?"*

### Act 3 — The Bakery Joke (Slides 9–12)

| Slide | Type | Content |
|-------|------|---------|
| 9 | Text + illustration | The setup: A mother tells her son: *"Vai lá na padaria e compra cinco pães. Mas se tiver leite, traz dois."* |
| 10 | Text + illustration | The result: The kid comes back with **two breads**. His logic: there was milk → bring two (instead of five). |
| 11 | Text | The lesson: *"Você pode culpar a criança? No entendimento dela, ela fez o melhor que podia. A mensagem era ambígua. Sem contexto, sem experiência, sem malandragem — ela interpretou literalmente."* |
| 12 | Practical tool | **"Teste do colega"**: *"Antes de mandar seu prompt, mostra pra um colega que não sabe nada do contexto. Se ele ficar confuso, a IA também vai ficar."* — Essa é a forma prática de evitar o problema da padaria. |

**Purpose**: The joke proves the concept emotionally. The Colleague Test gives them a practical tool to prevent it. Same idea, two forms: story + action.

**Source**: The Colleague Test is Anthropic's official golden rule for prompt evaluation.

### Act 4 — The Revelation (Slides 13–14)

| Slide | Type | Content |
|-------|------|---------|
| 13 | Statement | *"Qualquer problema de comunicação é um problema de..."* |
| 14 | Big reveal + mind-blown image | **CONTEXTO** (full screen, bold). Image: the "mind blown" meme/reaction. |

### Act 5 — This Is About Communication (Slides 15–19)

This is the heart of the presentation. Not about AI — about them.

| Slide | Type | Content |
|-------|------|---------|
| 15 | Text | *"A IA tem acesso a praticamente toda informação do mundo. Ela consegue processar qualquer coisa em tempo real. É um poder absurdo."* |
| 16 | Text (contrast) | *"Mas ela é como uma criança de 10 anos. Ela sabe falar, se expressar, tem opiniões, tem capacidade de fazer qualquer coisa — mas ela faz exatamente o que você falar. Se você não falar direito, ela não faz direito."* |
| 17 | Statement (big, bold) | **"Essa apresentação não é sobre IA. É sobre comunicação."** |
| 18 | The deeper insight | *"Quando você se comunica mal com uma pessoa, ela se esforça pra entender. Ela preenche os gaps. Ela se vira nos 30. Por isso você acha que se comunica bem."* |
| 19 | The mirror | *"A IA não faz isso. Ela interpreta exatamente o que você fala. A IA é o espelho da sua comunicação real."* |

**Facilitator notes**: This is where the audience should feel uncomfortable. The point: *"Se vocês estão falhando pra se comunicar com IA, é porque vocês também falham pra se comunicar com pessoas. A diferença é que pessoas se esforçam pra entender vocês. A IA não."*

### Act 6 — Your First Framework: APE (Slides 20–23)

Start simple. APE is the most recommended beginner framework (Action, Purpose, Expectation). Validated by multiple sources as the entry point for beginners.

| Slide | Type | Content |
|-------|------|---------|
| 20 | Framework intro | **APE — O framework mais simples pra começar.** Validado pela comunidade de prompt engineering como o ponto de partida ideal pra iniciantes. |
| 21 | Element: **A — Ação** | *O que você quer que a IA faça?* Ex: *"Escreve um e-mail", "Resume esse texto", "Me ajuda a organizar"* |
| 22 | Element: **P — Propósito** | *Por que você precisa disso?* Ex: *"Porque preciso responder um cliente insatisfeito", "Porque tenho que apresentar isso pro meu chefe amanhã"* |
| 23 | Element: **E — Expectativa** | *Como o resultado tem que ser?* Ex: *"Tom profissional, máximo 5 linhas", "Em formato de lista com bullet points", "Linguagem simples que qualquer pessoa entenda"* |

**Facilitator notes**: *"Pessoal, isso aqui é o mínimo. Só de fazer isso, o resultado já muda completamente. Existem frameworks mais completos — RACE, CO-STAR — mas hoje a gente começa pelo mais simples."*

### Act 7 — The Catches: Common Mistakes (Slides 24–43)

**Transition slide (24)**: *"Agora que vocês entenderam o APE, vamos ver o que acontece quando a gente erra. Pra cada problema, vou mostrar: o prompt errado, o desastre, a correção, e o comparativo."*

Each "catch" follows a 4-slide storytelling mechanic:
1. **The bad prompt** — just the text, clean
2. **The disaster** — same layout + the bad result appears (disaster image, hands on head)
3. **The fix** — the correct prompt overlays/replaces the bad one (crossing out / overwriting effect)
4. **Side by side** — bad prompt + bad result vs. good prompt + good result. The good prompt visibly follows APE. A small tag or label shows which part is A, which is P, which is E — connecting back to the framework.

#### Catch 1 — Ser vago / não dar contexto (Slides 25–28)

Merged: being vague and not giving context are the same root problem. The #1 most cited mistake across 100% of sources.

| Slide | Beat | Content |
|-------|------|---------|
| 25 | Bad prompt | *"Faz uma planilha de controle"* |
| 26 | Disaster + reaction image | Result: random spreadsheet with irrelevant columns — expenses, dates from 2019, categories that make no sense. *"Nada a ver com o que eu precisava!"* |
| 27 | Fix (overlays) | ~~Faz uma planilha de controle~~ → *"Sou do operacional. Preciso controlar entregas de 15 clientes por semana. Quero uma planilha com: cliente, data prevista, data real, status (atrasado/no prazo/entregue), e uma coluna de observações."* |
| 28 | Side by side | Left: vague → useless. Right: with context → ready to use. **Labels on the good prompt**: [A] controlar entregas / [P] 15 clientes por semana / [E] colunas específicas. |

#### Catch 2 — Falar demais sem estrutura (Slides 29–32)

The "wall of text" anti-pattern — overloading with noise is as bad as being vague.

| Slide | Beat | Content |
|-------|------|---------|
| 29 | Bad prompt | *"Preciso de ajuda com um negócio aqui, é que o cliente ligou bravo porque não tá funcionando o negócio lá, e meu chefe pediu pra resolver, e eu não sei o que falar, e já tentei ligar mas não atendeu, e acho que é um problema do sistema mas não tenho certeza, e ele é um cliente importante..."* |
| 30 | Disaster + reaction image | Result: confused, contradictory response that tries to address everything and solves nothing. *"A IA ficou tão perdida quanto eu!"* |
| 31 | Fix (overlays) | ~~wall of text~~ → *"Cliente: João Silva. Problema: sem acesso ao sistema desde ontem. Causa provável: erro no login. O que preciso: e-mail de desculpas com previsão de solução até amanhã 10h. Tom: profissional e empático."* |
| 32 | Side by side | Left: wall of text → confused. Right: structured → precise. **"Dar contexto não é falar muito. É falar exatamente o que precisa. Não mais, não menos."** Labels: [A] e-mail de desculpas / [P] cliente sem acesso / [E] tom profissional, previsão de solução. |

#### Catch 3 — Pedir tudo de uma vez (Slides 33–36)

Overloading a single prompt with multiple tasks.

| Slide | Beat | Content |
|-------|------|---------|
| 33 | Bad prompt | *"Resume esse documento, depois faz um e-mail pro cliente, cria uma apresentação sobre o tema, e me dá 5 ideias de como melhorar o processo"* |
| 34 | Disaster + reaction image | Result: superficial summary, generic email, no real presentation, random ideas. *"Fez tudo pela metade!"* |
| 35 | Fix (overlays) | ~~tudo de uma vez~~ → *"Primeiro: resume esse documento em 5 bullet points."* (depois, em outro prompt: *"Agora, com base no resumo, escreve um e-mail..."*) |
| 36 | Side by side | Left: everything at once → shallow. Right: one at a time → deep and useful. **"Uma coisa de cada vez. A IA faz melhor quando foca."** |

#### Catch 4 — Usar linguagem negativa (Slides 37–40)

Counter-intuitive finding from research: telling AI what NOT to do is less effective than telling what TO do. Positive instructions give a clear target; negative ones leave ambiguity.

| Slide | Beat | Content |
|-------|------|---------|
| 37 | Bad prompt | *"Escreve um texto sobre o produto, mas não usa palavras difíceis, não faz muito longo, não coloca termos técnicos, não escreve de forma formal"* |
| 38 | Disaster + reaction image | Result: AI avoids everything you said not to, but has no idea what TO do — produces a bland, directionless text. *"Tá... mas o que eu queria mesmo?"* |
| 39 | Fix (overlays) | ~~não isso, não aquilo~~ → *"Escreve um texto sobre o produto em linguagem simples e direta, como se tivesse explicando pra um amigo. Máximo 150 palavras, tom leve e acessível."* |
| 40 | Side by side | Left: "não faça X" → lost. Right: "faça Y" → clear. **"Diga o que você QUER, não o que você NÃO quer."** Labels: [A] texto sobre o produto / [P] explicar pra um amigo / [E] 150 palavras, tom leve. |

#### Catch 5 — Não iterar / mentalidade "one-shot" (Slides 41–44)

The "prompt and pray" anti-pattern — send one prompt, get a bad result, give up or complain. Directly connected to the evolution message.

| Slide | Beat | Content |
|-------|------|---------|
| 41 | Bad prompt | *"Faz um plano de ação pro meu time"* → resultado ruim → pessoa desiste. *"IA não funciona."* |
| 42 | Disaster + reaction image | Shows the person giving up. One prompt, one bad result, done. *"Ah, essa IA é inútil."* |
| 43 | Fix (overlays) | ~~desistir~~ → **Conversa com a IA**: *"Isso não ficou bom. O que eu poderia ter feito de diferente nesse prompt pra ter um resultado melhor?"* → A IA responde com sugestões → Você refaz o prompt melhor → Resultado 10x melhor. |
| 44 | Side by side | Left: one-shot → bad result → give up. Right: iterate → ask why → improve → great result. **"A IA é uma conversa, não um formulário. Se deu errado, pergunta o que melhorar."** |

**Facilitator note for Catch 5**: *"Isso é o que eu faço todo dia. Deu errado? Pergunto pra IA: 'o que eu fiz de errado nesse prompt?' Ela me fala, eu melhoro, e o próximo resultado é melhor. É assim que se evolui."*

### Act 8 — The Wake-Up Call (Slides 45–53)

This is one continuous storytelling arc. Each slide builds on the previous — it's a conversation with the audience. The tone is NOT accusatory — it's a wake-up call. Not "you're wrong" but "what are you doing to get better?"

| Slide | Type | Content |
|-------|------|---------|
| 45 | Opening question | *"Vocês têm problemas com a IA fazendo o que vocês querem?"* |
| 46 | Build | *"Se a IA não faz o que você quer, é porque a comunicação não foi clara o suficiente."* |
| 47 | Statement | *"A IA é o estagiário mais inteligente do mundo. Ela sabe tudo, mas não sabe nada sobre o SEU problema — até você contar pra ela."* |
| 48 | Wake-up (big, bold) | **"E aí, o que você tá fazendo pra melhorar?"** |
| 49 | Challenge | *"A IA não é uma ferramenta estática — todo dia ela tá diferente. Se você faz o mesmo prompt todo dia, sofre do mesmo problema todo dia e não muda nada — não vai evoluir."* |
| 50 | The learning loop | *"Quando dá errado, não fica puto. Investiga. Pergunta pra IA: 'por que você foi por esse caminho? O que no meu prompt te levou a essa resposta?' E aí você descobre: às vezes o erro é seu — sua comunicação não foi clara. Às vezes é uma limitação da IA — ela funciona assim. Nos dois casos, você ajusta o seu processo."* |
| 51 | Key insight (big, bold) | **"Todo erro é uma oportunidade de aprender."** *Ou você melhora sua comunicação, ou você adapta seu processo pra como a IA funciona. Nos dois casos, você evolui.* |
| 52 | Personal example | *"Eu também erro. Todo dia. Mas quando erro, pergunto pra IA por que foi por aquele caminho. Já descobri coisas que são do meu processo — e ajustei. Já descobri limitações da IA — e adaptei. Uso speech-to-text pra dar mais contexto sem perder agilidade. Isso é o que eu faço diariamente. E vocês?"* |
| 53 | Closing (celebration image — champagne, confetti, success) | **"Melhore a sua comunicação."** |

**Purpose**: One arc: "You have problems? → The communication wasn't clear → What are YOU doing about it? → You need to evolve → When it goes wrong, investigate — is it your communication or an AI limitation? → Adjust your process → I do this every day, here's how → Now it's your turn."

**Facilitator notes**: The tone here is a coach giving a shake, not a boss pointing fingers. It's: "Pessoal, eu entendo a frustração. Mas ficar puto não resolve. O que resolve é entender por que deu errado. Às vezes é a gente que tem que melhorar. Às vezes é a IA que funciona diferente e a gente tem que adaptar o processo. Nos dois casos, a gente evolui."

---

## Research

Full research documented in `SPIKE.md` (this directory) and raw data in:
- `/tmp/prompt_engineering_presentations_research_20260328.md`
- `/tmp/prompt_engineering_comparison_analysis_20260328.md`

---

## Visual Style Notes (for Gamma)

- Clean, minimal slides — no walls of text
- Dark background preferred
- Fast-paced: each slide should take 20-30 seconds max
- Heavy on images, light on text — emotional, visual, impactful
- **Catch slides**: The 4-slide mechanic needs smooth transitions — each slide should feel like the same slide building. The "fix" should cross out the bad prompt and overwrite it.
- **APE labels on catch comparisons**: Small tags [A], [P], [E] on the good prompts to connect back to the framework
- Side-by-side slides: clear two-column layout, left = red/bad, right = green/good
- **Act 8 (Wake-Up Call)**: Tone is coach, not judge. It's a shake, not an attack. Builds energy toward action, not toward guilt
- The closing should feel celebratory and light — "it's simpler than you think"

---

## Prompt Draft for Gamma

> Create a presentation called "Prompting Engineering for Dummies". Theme: dark, clean, minimal, image-heavy. Fast-paced — each slide should be digestible in 20-30 seconds. The presentation's title says "Prompt Engineering" but the real subject is COMMUNICATION. It teaches a mixed team (commercial, operations, and a couple of engineers) that their problem with AI is really a communication problem. The audience is mostly non-technical, so all examples must be universal — no code, no jargon.
>
> **Core message:** When you communicate poorly with a person, that person makes a huge effort to understand you — they fill the gaps, they figure it out. So you think you communicate well. AI doesn't do that. AI interprets exactly what you say. AI is the mirror of your real communication skills.
>
> **Flow:**
>
> **Act 1 — The Car Example (hook)**
> 1. Title slide: "Prompting Engineering for Dummies"
> 2. Text slide: the prompt "Faz um carro pra mim" (just the text, nothing else)
> 3. Image slide: a photo of a car (the AI made an image of a car — not what was wanted)
> 4. Text slide: "Não era isso. Faz a imagem de um carro que funciona."
> 5. Image slide: a car driving on a road (still just an image)
> 6. Text slide: "Eu não quero imagem! Eu quero um carro que funciona!"
> 7. Image slide: a technical blueprint/exploded diagram of a car — engineering schematic
>
> **Act 2 — Where's the Error?**
> 8. Question slide: "Onde está o erro?" — big, centered, bold. Pause for discussion.
>
> **Act 3 — The Bakery Joke**
> 9. Story slide with illustration: A mother tells her son: "Vai na padaria e compra cinco pães. Mas se tiver leite, traz dois."
> 10. Result slide with illustration: The kid comes back with two breads. There was milk, so he brought two instead of five.
> 11. Lesson slide: "Você pode culpar a criança? No entendimento dela, ela fez o melhor que podia. Sem contexto, a interpretação literal vence."
> 12. Practical tool slide: "Teste do colega — Antes de mandar seu prompt, mostra pra um colega que não sabe nada do contexto. Se ele ficar confuso, a IA também vai ficar." This is the practical way to avoid the bakery problem.
>
> **Act 4 — The Revelation**
> 13. Build-up slide: "Qualquer problema de comunicação é um problema de..."
> 14. Reveal slide: "CONTEXTO" — big, bold, with a mind-blown reaction image
>
> **Act 5 — This Is About Communication**
> 15. Power slide: "A IA tem acesso a toda informação do mundo. Processa qualquer coisa em tempo real. É um poder absurdo."
> 16. Analogy slide: "Mas ela é como uma criança de 10 anos. Sabe falar, se expressar, tem capacidade de fazer qualquer coisa — mas faz exatamente o que você falar. Se você não falar direito, ela não faz direito."
> 17. Reframe slide (big, bold): "Essa apresentação não é sobre IA. É sobre comunicação."
> 18. Deeper insight slide: "Quando você se comunica mal com uma pessoa, ela se esforça pra entender. Ela preenche os gaps. Ela se vira nos 30. Por isso você acha que se comunica bem."
> 19. Mirror slide: "A IA não faz isso. Ela interpreta exatamente o que você fala. A IA é o espelho da sua comunicação real."
>
> **Act 6 — Your First Framework: APE**
> 20. Framework intro: "APE — O framework mais simples pra começar." Subtitle: "Validado pela comunidade de prompt engineering como o ponto de partida ideal."
> 21. A = Ação: "O que você quer que a IA faça?" Examples: "Escreve um e-mail", "Resume esse texto", "Me ajuda a organizar"
> 22. P = Propósito: "Por que você precisa disso?" Examples: "Porque preciso responder um cliente insatisfeito", "Porque tenho que apresentar isso pro meu chefe amanhã"
> 23. E = Expectativa: "Como o resultado tem que ser?" Examples: "Tom profissional, máximo 5 linhas", "Em formato de lista", "Linguagem simples"
>
> **Act 7 — The Catches (Common Mistakes)**
> 24. Transition slide: "Agora que vocês entenderam o APE, vamos ver o que acontece quando a gente erra."
>
> This section uses a repeating 4-slide mechanic for each mistake. The slides should feel like the same slide building — adding content progressively, not jumping to new layouts. On each "side by side" slide, the good prompt has small [A], [P], [E] labels showing how it follows the framework.
>
> **Catch 1 — Being vague / no context:**
> 25. Bad prompt: "Faz uma planilha de controle"
> 26. Disaster: random spreadsheet with irrelevant columns. "Nada a ver com o que eu precisava!"
> 27. Fix (overlays): "Sou do operacional. Preciso controlar entregas de 15 clientes por semana. Quero uma planilha com: cliente, data prevista, data real, status, e observações."
> 28. Side-by-side with APE labels on the good prompt.
>
> **Catch 2 — Wall of text (talking too much without structure):**
> 29. Bad prompt: a long rambling paragraph about a client problem, full of noise.
> 30. Disaster: confused AI response. "A IA ficou tão perdida quanto eu!"
> 31. Fix (overlays): clean structured version — Client, Problem, Cause, What I need, Tone.
> 32. Side-by-side + message: "Dar contexto não é falar muito. É falar exatamente o que precisa."
>
> **Catch 3 — Asking everything at once:**
> 33. Bad prompt: "Resume, faz e-mail, cria apresentação, e dá 5 ideias"
> 34. Disaster: everything shallow. "Fez tudo pela metade!"
> 35. Fix (overlays): "Primeiro: resume em 5 bullet points." Then another prompt for the next step.
> 36. Side-by-side + message: "Uma coisa de cada vez. A IA faz melhor quando foca."
>
> **Catch 4 — Negative language (saying what NOT to do):**
> 37. Bad prompt: "Escreve um texto, mas não usa palavras difíceis, não faz longo, não usa termos técnicos, não escreve formal"
> 38. Disaster: bland, directionless text. "Tá... mas o que eu queria mesmo?"
> 39. Fix (overlays): "Escreve um texto em linguagem simples, como se tivesse explicando pra um amigo. 150 palavras, tom leve."
> 40. Side-by-side + message: "Diga o que você QUER, não o que você NÃO quer."
>
> **Catch 5 — Not iterating (one-shot mentality):**
> 41. Bad prompt: "Faz um plano de ação pro meu time" → bad result → person gives up. "IA não funciona."
> 42. Disaster: person giving up after one try. "Ah, essa IA é inútil."
> 43. Fix (overlays): Instead of giving up, ask the AI: "O que eu poderia ter feito de diferente nesse prompt?" → AI suggests improvements → Better prompt → Great result.
> 44. Side-by-side + message: "A IA é uma conversa, não um formulário. Se deu errado, pergunta o que melhorar."
>
> **Act 8 — The Wake-Up Call (one continuous storytelling arc, coach tone — not accusatory)**
> 45. Opening question: "Vocês têm problemas com a IA fazendo o que vocês querem?"
> 46. Build: "Se a IA não faz o que você quer, é porque a comunicação não foi clara o suficiente."
> 47. Statement: "A IA é o estagiário mais inteligente do mundo. Ela sabe tudo, mas não sabe nada sobre o SEU problema — até você contar."
> 48. Wake-up (big, bold): "E aí, o que você tá fazendo pra melhorar?"
> 49. Challenge: "A IA não é uma ferramenta estática — todo dia ela tá diferente. Se você faz o mesmo prompt todo dia e não muda nada — não vai evoluir."
> 50. Learning loop: "Quando dá errado, não fica puto. Investiga. Pergunta pra IA: 'por que você foi por esse caminho?' Descobre: às vezes o erro é seu, às vezes é uma limitação da IA. Nos dois casos, você ajusta o seu processo."
> 51. Key insight (big, bold): "Todo erro é uma oportunidade de aprender." Ou melhora sua comunicação, ou adapta seu processo.
> 52. Personal example (leading by example, not vulnerability): "Eu também erro. Todo dia. Mas quando erro, pergunto pra IA por que foi por aquele caminho. Já descobri coisas do meu processo — e ajustei. Já descobri limitações da IA — e adaptei. Uso speech-to-text pra dar mais contexto. Isso é o que eu faço diariamente. E vocês?"
> 53. Closing (celebration image — champagne, confetti): "Melhore a sua comunicação."
>
> **Style notes:**
> - Minimal text, maximum images, dark theme, high contrast
> - Fast-paced: 20-30 seconds per slide
> - Catch slides must feel like the same slide building/updating — not jumping layouts
> - The fix slides cross out / overwrite the bad prompt
> - Side-by-side: left = red/bad, right = green/good, with [A][P][E] labels on good prompts
> - Act 8 tone is COACH, not JUDGE — it's a wake-up call, not an attack. Energy builds toward action, not guilt
>> - Closing should feel celebratory and light — "it's simpler than you think"
> - All examples universal — no code, no jargon, no area-specific scenarios
> - Language: Portuguese (Brazil)
