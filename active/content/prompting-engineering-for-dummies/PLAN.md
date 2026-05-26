# Prompting Engineering for Dummies — Presentation Plan

> Note: prompt examples and facilitator quotes below are translated to English for planning purposes. The actual delivery is in Portuguese (pt-BR). A future auxiliary file will hold the original pt-BR copy that goes into Gamma slides.

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
| 2 | Text only | Prompt: *"Build me a car"* |
| 3 | Image | A picture of a car (just an image, a photo) |
| 4 | Text | *"Hey, that's not what I meant. Make an image of a car that works."* |
| 5 | Image | A car driving on a road (still just an image) |
| 6 | Text | *"No, dude, I don't want an image. I want a car that works!"* |
| 7 | Image | A technical blueprint/architectural drawing of a car — exploded view showing how parts connect (doors, steering wheel, engine, chassis) |

**Purpose**: Each iteration shows the AI doing *exactly* what was asked — the problem is never the AI, it's the instruction.

### Act 2 — Where's the Error? (Slide 8)

| Slide | Type | Content |
|-------|------|---------|
| 8 | Question slide | **"Where is the error?"** |

**Facilitator notes**: Pause here. Ask the team directly. Let them articulate the problem themselves. Push until someone says "communication" or "context." Reinforce: *"I know I'm hammering the same point, but did the problem land for you?"*

### Act 3 — The Bakery Joke (Slides 9–12)

| Slide | Type | Content |
|-------|------|---------|
| 9 | Text + illustration | The setup: A mother tells her son: *"Go to the bakery and buy five loaves of bread. But if they have milk, bring two."* |
| 10 | Text + illustration | The result: The kid comes back with **two loaves**. His logic: there was milk → bring two (instead of five). |
| 11 | Text | The lesson: *"Can you blame the kid? In his understanding, he did the best he could. The message was ambiguous. Without context, without experience, without street smarts — he interpreted literally."* |
| 12 | Practical tool | **"Colleague Test"**: *"Before sending your prompt, show it to a colleague who knows nothing about the context. If they get confused, the AI will too."* — That is the practical way to avoid the bakery problem. |

**Purpose**: The joke proves the concept emotionally. The Colleague Test gives them a practical tool to prevent it. Same idea, two forms: story + action.

**Source**: The Colleague Test is Anthropic's official golden rule for prompt evaluation.

### Act 4 — The Revelation (Slides 13–14)

| Slide | Type | Content |
|-------|------|---------|
| 13 | Statement | *"Any communication problem is a problem of..."* |
| 14 | Big reveal + mind-blown image | **CONTEXT** (full screen, bold). Image: the "mind blown" meme/reaction. |

### Act 5 — This Is About Communication (Slides 15–19)

This is the heart of the presentation. Not about AI — about them.

| Slide | Type | Content |
|-------|------|---------|
| 15 | Text | *"AI has access to virtually all the information in the world. It can process anything in real time. That is absurd power."* |
| 16 | Text (contrast) | *"But it is like a 10-year-old kid. It can talk, express itself, have opinions, do anything — but it does exactly what you say. If you don't say it right, it doesn't do it right."* |
| 17 | Statement (big, bold) | **"This presentation is not about AI. It's about communication."** |
| 18 | The deeper insight | *"When you communicate poorly with a person, they make a huge effort to understand you. They fill the gaps. They figure it out. That's why you think you communicate well."* |
| 19 | The mirror | *"AI doesn't do that. It interprets exactly what you say. AI is the mirror of your real communication."* |

**Facilitator notes**: This is where the audience should feel uncomfortable. The point: *"If you are failing to communicate with AI, it is because you also fail to communicate with people. The difference is that people make an effort to understand you. AI doesn't."*

### Act 6 — Your First Framework: APE (Slides 20–23)

Start simple. APE is the most recommended beginner framework (Action, Purpose, Expectation). Validated by multiple sources as the entry point for beginners.

| Slide | Type | Content |
|-------|------|---------|
| 20 | Framework intro | **APE — The simplest framework to get started.** Validated by the prompt engineering community as the ideal starting point for beginners. |
| 21 | Element: **A — Action** | *What do you want the AI to do?* Examples: *"Write an email", "Summarize this text", "Help me organize"* |
| 22 | Element: **P — Purpose** | *Why do you need this?* Examples: *"Because I need to reply to an unhappy client", "Because I have to present this to my boss tomorrow"* |
| 23 | Element: **E — Expectation** | *What does the result have to look like?* Examples: *"Professional tone, max 5 lines", "Bullet-point list", "Simple language anyone can understand"* |

**Facilitator notes**: *"Folks, this is the minimum. Just doing this changes the result completely. There are more complete frameworks — RACE, CO-STAR — but today we start with the simplest."*

### Act 7 — The Catches: Common Mistakes (Slides 24–43)

**Transition slide (24)**: *"Now that you understand APE, let's see what happens when we get it wrong. For each problem I'll show: the bad prompt, the disaster, the fix, and the side-by-side."*

Each "catch" follows a 4-slide storytelling mechanic:
1. **The bad prompt** — just the text, clean
2. **The disaster** — same layout + the bad result appears (disaster image, hands on head)
3. **The fix** — the correct prompt overlays/replaces the bad one (crossing out / overwriting effect)
4. **Side by side** — bad prompt + bad result vs. good prompt + good result. The good prompt visibly follows APE. A small tag or label shows which part is A, which is P, which is E — connecting back to the framework.

#### Catch 1 — Being vague / no context (Slides 25–28)

Merged: being vague and not giving context are the same root problem. The #1 most cited mistake across 100% of sources.

| Slide | Beat | Content |
|-------|------|---------|
| 25 | Bad prompt | *"Build me a control spreadsheet"* |
| 26 | Disaster + reaction image | Result: random spreadsheet with irrelevant columns — expenses, dates from 2019, categories that make no sense. *"Nothing to do with what I needed!"* |
| 27 | Fix (overlays) | ~~Build me a control spreadsheet~~ → *"I'm in operations. I need to track deliveries for 15 clients per week. I want a spreadsheet with: client, expected date, actual date, status (late/on time/delivered), and an observations column."* |
| 28 | Side by side | Left: vague → useless. Right: with context → ready to use. **Labels on the good prompt**: [A] track deliveries / [P] 15 clients per week / [E] specific columns. |

#### Catch 2 — Wall of text without structure (Slides 29–32)

The "wall of text" anti-pattern — overloading with noise is as bad as being vague.

| Slide | Beat | Content |
|-------|------|---------|
| 29 | Bad prompt | *"I need help with a thing here, the client called angry because the thing isn't working, and my boss asked me to fix it, and I don't know what to say, and I tried calling but no one answered, and I think it's a system problem but I'm not sure, and they are an important client..."* |
| 30 | Disaster + reaction image | Result: confused, contradictory response that tries to address everything and solves nothing. *"The AI got as lost as I was!"* |
| 31 | Fix (overlays) | ~~wall of text~~ → *"Client: João Silva. Problem: no system access since yesterday. Likely cause: login error. What I need: apology email with a fix ETA by tomorrow 10am. Tone: professional and empathetic."* |
| 32 | Side by side | Left: wall of text → confused. Right: structured → precise. **"Giving context isn't talking a lot. It's saying exactly what you need. No more, no less."** Labels: [A] apology email / [P] client without access / [E] professional tone, fix ETA. |

#### Catch 3 — Asking everything at once (Slides 33–36)

Overloading a single prompt with multiple tasks.

| Slide | Beat | Content |
|-------|------|---------|
| 33 | Bad prompt | *"Summarize this document, then write an email to the client, create a presentation about it, and give me 5 ideas to improve the process"* |
| 34 | Disaster + reaction image | Result: superficial summary, generic email, no real presentation, random ideas. *"Did everything half-way!"* |
| 35 | Fix (overlays) | ~~all at once~~ → *"First: summarize this document into 5 bullet points."* (then, in another prompt: *"Now, based on the summary, write the email..."*) |
| 36 | Side by side | Left: everything at once → shallow. Right: one at a time → deep and useful. **"One thing at a time. The AI does better when it focuses."** |

#### Catch 4 — Using negative language (Slides 37–40)

Counter-intuitive finding from research: telling AI what NOT to do is less effective than telling what TO do. Positive instructions give a clear target; negative ones leave ambiguity.

| Slide | Beat | Content |
|-------|------|---------|
| 37 | Bad prompt | *"Write a text about the product, but don't use hard words, don't make it long, don't use technical terms, don't be formal"* |
| 38 | Disaster + reaction image | Result: AI avoids everything you said not to, but has no idea what TO do — produces a bland, directionless text. *"Okay... but what did I actually want?"* |
| 39 | Fix (overlays) | ~~don't this, don't that~~ → *"Write a text about the product in simple, direct language, as if explaining it to a friend. Max 150 words, light and accessible tone."* |
| 40 | Side by side | Left: "don't do X" → lost. Right: "do Y" → clear. **"Say what you WANT, not what you DON'T want."** Labels: [A] text about the product / [P] explain to a friend / [E] 150 words, light tone. |

#### Catch 5 — Not iterating / "one-shot" mindset (Slides 41–44)

The "prompt and pray" anti-pattern — send one prompt, get a bad result, give up or complain. Directly connected to the evolution message.

| Slide | Beat | Content |
|-------|------|---------|
| 41 | Bad prompt | *"Write an action plan for my team"* → bad result → person gives up. *"AI doesn't work."* |
| 42 | Disaster + reaction image | Shows the person giving up. One prompt, one bad result, done. *"Ugh, this AI is useless."* |
| 43 | Fix (overlays) | ~~give up~~ → **Talk to the AI**: *"This didn't turn out well. What could I have done differently in this prompt to get a better result?"* → The AI responds with suggestions → You rewrite the prompt better → 10x better result. |
| 44 | Side by side | Left: one-shot → bad result → give up. Right: iterate → ask why → improve → great result. **"AI is a conversation, not a form. If it didn't work, ask what to improve."** |

**Facilitator note for Catch 5**: *"This is what I do every day. Didn't work? I ask the AI: 'what did I do wrong in this prompt?' It tells me, I improve, and the next result is better. That's how you evolve."*

### Act 8 — The Wake-Up Call (Slides 45–53)

This is one continuous storytelling arc. Each slide builds on the previous — it's a conversation with the audience. The tone is NOT accusatory — it's a wake-up call. Not "you're wrong" but "what are you doing to get better?"

| Slide | Type | Content |
|-------|------|---------|
| 45 | Opening question | *"Are you having trouble getting AI to do what you want?"* |
| 46 | Build | *"If the AI isn't doing what you want, it's because the communication wasn't clear enough."* |
| 47 | Statement | *"AI is the smartest intern in the world. It knows everything, but it knows nothing about YOUR problem — until you tell it."* |
| 48 | Wake-up (big, bold) | **"So, what are you doing to get better?"** |
| 49 | Challenge | *"AI is not a static tool — it's different every day. If you send the same prompt every day, you suffer from the same problem every day, you don't change anything — you won't evolve."* |
| 50 | The learning loop | *"When it goes wrong, don't get angry. Investigate. Ask the AI: 'why did you take that path? What in my prompt led you there?' And there you find out: sometimes the error is yours — your communication wasn't clear. Sometimes it's an AI limitation — it works that way. In both cases, you adjust your process."* |
| 51 | Key insight (big, bold) | **"Every error is a learning opportunity."** *Either you improve your communication, or you adapt your process to how the AI works. Either way, you evolve.* |
| 52 | Personal example | *"I mess up too. Every day. But when I do, I ask the AI why it went that way. I've already found things about my process — and adjusted. I've already found AI limitations — and adapted. I use speech-to-text to give more context without losing speed. That's what I do daily. And you?"* |
| 53 | Closing (celebration image — champagne, confetti, success) | **"Improve your communication."** |

**Purpose**: One arc: "You have problems? → The communication wasn't clear → What are YOU doing about it? → You need to evolve → When it goes wrong, investigate — is it your communication or an AI limitation? → Adjust your process → I do this every day, here's how → Now it's your turn."

**Facilitator notes**: The tone here is a coach giving a shake, not a boss pointing fingers. It's: "Folks, I get the frustration. But staying angry doesn't solve anything. What solves it is understanding why it went wrong. Sometimes it's us who need to improve. Sometimes the AI works differently and we need to adapt the process. Either way, we evolve."

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
> 2. Text slide: the prompt "Build me a car" (just the text, nothing else)
> 3. Image slide: a photo of a car (the AI made an image of a car — not what was wanted)
> 4. Text slide: "That's not it. Make an image of a car that works."
> 5. Image slide: a car driving on a road (still just an image)
> 6. Text slide: "I don't want an image! I want a car that works!"
> 7. Image slide: a technical blueprint/exploded diagram of a car — engineering schematic
>
> **Act 2 — Where's the Error?**
> 8. Question slide: "Where is the error?" — big, centered, bold. Pause for discussion.
>
> **Act 3 — The Bakery Joke**
> 9. Story slide with illustration: A mother tells her son: "Go to the bakery and buy five loaves of bread. But if they have milk, bring two."
> 10. Result slide with illustration: The kid comes back with two loaves. There was milk, so he brought two instead of five.
> 11. Lesson slide: "Can you blame the kid? In his understanding, he did the best he could. Without context, literal interpretation wins."
> 12. Practical tool slide: "Colleague Test — Before sending your prompt, show it to a colleague who knows nothing about the context. If they get confused, the AI will too." This is the practical way to avoid the bakery problem.
>
> **Act 4 — The Revelation**
> 13. Build-up slide: "Any communication problem is a problem of..."
> 14. Reveal slide: "CONTEXT" — big, bold, with a mind-blown reaction image
>
> **Act 5 — This Is About Communication**
> 15. Power slide: "AI has access to all information in the world. Processes anything in real time. That is absurd power."
> 16. Analogy slide: "But it is like a 10-year-old kid. It can talk, express itself, do anything — but it does exactly what you say. If you don't say it right, it doesn't do it right."
> 17. Reframe slide (big, bold): "This presentation is not about AI. It is about communication."
> 18. Deeper insight slide: "When you communicate poorly with a person, they make a huge effort to understand you. They fill the gaps. They figure it out. That's why you think you communicate well."
> 19. Mirror slide: "AI doesn't do that. It interprets exactly what you say. AI is the mirror of your real communication."
>
> **Act 6 — Your First Framework: APE**
> 20. Framework intro: "APE — The simplest framework to get started." Subtitle: "Validated by the prompt engineering community as the ideal starting point."
> 21. A = Action: "What do you want the AI to do?" Examples: "Write an email", "Summarize this text", "Help me organize"
> 22. P = Purpose: "Why do you need this?" Examples: "Because I need to reply to an unhappy client", "Because I have to present this to my boss tomorrow"
> 23. E = Expectation: "What does the result have to look like?" Examples: "Professional tone, max 5 lines", "Bullet-point list", "Simple language"
>
> **Act 7 — The Catches (Common Mistakes)**
> 24. Transition slide: "Now that you understand APE, let's see what happens when we get it wrong."
>
> This section uses a repeating 4-slide mechanic for each mistake. The slides should feel like the same slide building — adding content progressively, not jumping to new layouts. On each "side by side" slide, the good prompt has small [A], [P], [E] labels showing how it follows the framework.
>
> **Catch 1 — Being vague / no context:**
> 25. Bad prompt: "Build me a control spreadsheet"
> 26. Disaster: random spreadsheet with irrelevant columns. "Nothing to do with what I needed!"
> 27. Fix (overlays): "I'm in operations. I need to track deliveries for 15 clients per week. I want a spreadsheet with: client, expected date, actual date, status, and observations."
> 28. Side-by-side with APE labels on the good prompt.
>
> **Catch 2 — Wall of text (talking too much without structure):**
> 29. Bad prompt: a long rambling paragraph about a client problem, full of noise.
> 30. Disaster: confused AI response. "The AI got as lost as I was!"
> 31. Fix (overlays): clean structured version — Client, Problem, Cause, What I need, Tone.
> 32. Side-by-side + message: "Giving context isn't talking a lot. It's saying exactly what you need."
>
> **Catch 3 — Asking everything at once:**
> 33. Bad prompt: "Summarize, write email, build presentation, give 5 ideas"
> 34. Disaster: everything shallow. "Did everything half-way!"
> 35. Fix (overlays): "First: summarize into 5 bullet points." Then another prompt for the next step.
> 36. Side-by-side + message: "One thing at a time. The AI does better when it focuses."
>
> **Catch 4 — Negative language (saying what NOT to do):**
> 37. Bad prompt: "Write a text, but don't use hard words, don't make it long, don't use technical terms, don't be formal"
> 38. Disaster: bland, directionless text. "Okay... but what did I actually want?"
> 39. Fix (overlays): "Write a text in simple language, as if explaining to a friend. 150 words, light tone."
> 40. Side-by-side + message: "Say what you WANT, not what you DON'T want."
>
> **Catch 5 — Not iterating (one-shot mentality):**
> 41. Bad prompt: "Write an action plan for my team" → bad result → person gives up. "AI doesn't work."
> 42. Disaster: person giving up after one try. "Ugh, this AI is useless."
> 43. Fix (overlays): Instead of giving up, ask the AI: "What could I have done differently in this prompt?" → AI suggests improvements → Better prompt → Great result.
> 44. Side-by-side + message: "AI is a conversation, not a form. If it didn't work, ask what to improve."
>
> **Act 8 — The Wake-Up Call (one continuous storytelling arc, coach tone — not accusatory)**
> 45. Opening question: "Are you having trouble getting AI to do what you want?"
> 46. Build: "If the AI isn't doing what you want, it's because the communication wasn't clear enough."
> 47. Statement: "AI is the smartest intern in the world. It knows everything, but it knows nothing about YOUR problem — until you tell it."
> 48. Wake-up (big, bold): "So, what are you doing to get better?"
> 49. Challenge: "AI is not a static tool — it's different every day. If you send the same prompt every day and don't change anything — you won't evolve."
> 50. Learning loop: "When it goes wrong, don't get angry. Investigate. Ask the AI: 'why did you go that way?' You'll find: sometimes the error is yours, sometimes it's an AI limitation. Either way, adjust your process."
> 51. Key insight (big, bold): "Every error is a learning opportunity." Either improve your communication, or adapt your process.
> 52. Personal example (leading by example, not vulnerability): "I mess up too. Every day. But when I do, I ask the AI why it went that way. I've found things about my process — and adjusted. I've found AI limitations — and adapted. I use speech-to-text to give more context. That's what I do daily. And you?"
> 53. Closing (celebration image — champagne, confetti): "Improve your communication."
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
> - Language: English (planning version). Final delivery is in Portuguese (Brazil) — to be produced as an auxiliary file with the pt-BR slide copy.
