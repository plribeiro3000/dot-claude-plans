# SPIKE — Session Plan Files for Context Persistence in AI Coding Agents

## Investigation question

Is the developer/AI-agent community (blog posts, social media, forums, GitHub, docs) discussing the practice of keeping a living "session plan" file to minimize context loss in AI coding agents (Claude Code, Cursor, Aider, Windsurf, etc.)? Specifically:

1. **Session-start plan creation** — a rule/hook that, at the START of every session, forces the agent to create a plan file stating "what we're working on this session / what we're NOT doing" — even when the goal isn't fully known yet.
2. **Continuous plan updating** — a rule that forces the agent to keep that plan file UPDATED over time (periodically, or on each distinct action/step) so the session and the plan don't drift apart.

**Round 2 refinement (from the engineer):** Round 1 assumed the work CAN be planned up front (spec-driven, clarify-then-plan). The engineer's actual recurring pain is a different class of work — **exploratory / learn-as-you-go work where the human cannot plan up front because they don't know the domain** (concrete example: setting up PgBouncer through Docker + GitHub Actions + database connectivity, using Claude Code precisely so he does not have to stop and study everything first). Round 2 investigates whether the community has a lighter answer for avoiding context loss during genuinely emergent work, without paying the full spike→study→plan→execute tax that would defeat the productivity premise of using an agent at all.

## Sources consulted

- [docs.cline.bot/prompting/cline-memory-bank](https://docs.cline.bot/prompting/cline-memory-bank) — official Cline docs for the "Memory Bank" methodology
- [cline.bot/blog/memory-bank-how-to-make-cline-an-ai-agent-that-never-forgets](https://cline.bot/blog/memory-bank-how-to-make-cline-an-ai-agent-that-never-forgets) — Cline's own blog framing of the pain point and update lifecycle
- [anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) — Anthropic's first-party engineering blog on context engineering, incl. "structured note-taking"
- [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) — official Claude Code hooks reference (SessionStart, Stop, PreCompact)
- [code.claude.com/docs/en/agent-sdk/todo-tracking](https://code.claude.com/docs/en/agent-sdk/todo-tracking) — official Claude Code/Agent SDK docs for TodoWrite → Task tools migration
- [lucumr.pocoo.org/2025/12/17/what-is-plan-mode](https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/) — Armin Ronacher's technical breakdown of Claude Code Plan Mode internals
- [threads.com/@boris_cherny/post/DRgyCN5jjYA](https://www.threads.com/@boris_cherny/post/DRgyCN5jjYA/claude-now-writes-plan-files-to-your-filesystem-and-you-can-edit-them-by) — Boris Cherny (Anthropic, Claude Code) announcing plan-file sync-back
- [martinfowler.com/articles/reduce-friction-ai/context-anchoring.html](https://martinfowler.com/articles/reduce-friction-ai/context-anchoring.html) — Martin Fowler site article naming and defining "Context Anchoring"
- [martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html) — companion piece; fetched, contained no plan/scratchpad-specific content (see Finding 12)
- [github.com/github/spec-kit](https://github.com/github/spec-kit) — GitHub's Spec-Driven Development toolkit (spec.md/plan.md/tasks.md)
- [aider.chat/docs/usage/conventions.html](https://aider.chat/docs/usage/conventions.html) — official Aider docs on CONVENTIONS.md and plan files (`.coding-aider-plans`)
- [github.com/cofin/flow](https://github.com/cofin/flow) — "Context-Driven Development" toolkit using Beads as source of truth, auto-syncing spec.md
- [nikiforovall.blog/ai/2026/06/08/scratch.html](https://nikiforovall.blog/ai/2026/06/08/scratch.html) — "Structured Scratchpads for Coding Agents" blog post + `scratch` CLI
- [samfrenchblog.com/2026/02/15/how-i-use-todo-md-with-claude-code-to-never-lose-context-between-sessions](https://samfrenchblog.com/2026/02/15/how-i-use-todo-md-with-claude-code-to-never-lose-context-between-sessions/) — DIY TODO.md practice
- [chudi.dev/blog/claude-context-management-dev-docs](https://chudi.dev/blog/claude-context-management-dev-docs) — DIY "3-file system" (plan.md/context.md/tasks.md) with slash commands
- [dev.to/whoffagents/why-your-claude-code-sessions-keep-losing-context-and-how-to-fix-it-nia](https://dev.to/whoffagents/why-your-claude-code-sessions-keep-losing-context-and-how-to-fix-it-nia) — DIY session-spec-file pattern (`.claude/session.md`)
- [dev.to/gonewx/claude-code-lost-my-4-hour-session-heres-the-0-fix-that-actually-works-24h6](https://dev.to/gonewx/claude-code-lost-my-4-hour-session-heres-the-0-fix-that-actually-works-24h6) — incident narrative + JSONL-backup fix (not a plan-file approach)
- [jdhodges.com/blog/ai-session-handoffs-keep-context-across-conversations](https://www.jdhodges.com/blog/ai-session-handoffs-keep-context-across-conversations/) — HANDOVER.md handoff-prompt practice
- [artemxtech.substack.com/p/never-lose-your-work-between-claude](https://artemxtech.substack.com/p/never-lose-your-work-between-claude) — per-session "session file" dashboard practice
- [dev.to/manfredmacx/why-your-agent-cant-follow-a-plan-and-how-to-fix-it-f4g](https://dev.to/manfredmacx/why-your-agent-cant-follow-a-plan-and-how-to-fix-it-f4g) — checkpoint/resumable-workflow critique of plan-following failures
- [usewire.io/blog/agent-drift-why-long-running-ai-agents-lose-the-plot](https://usewire.io/blog/agent-drift-why-long-running-ai-agents-lose-the-plot/) — "plan decay" as a named agent-drift mechanism, with the "revise on schedule" fix
- [medium.com/@cdcore/your-claude-md-is-making-your-agent-dumber-953f6dbed308](https://medium.com/@cdcore/your-claude-md-is-making-your-agent-dumber-953f6dbed308) — critique of living-doc decay, cites "AGENTbench" study
- [aicodex.to/articles/claude-md-maintenance](https://www.aicodex.to/articles/claude-md-maintenance) — "why your CLAUDE.md stops working" — decay mechanism + maintenance cadence
- [redreamality.com/blog/claude-md-agents-md-deep-dive](https://redreamality.com/blog/claude-md-agents-md-deep-dive/) — counterintuitive patterns (self-updating MEMORY.md, "Darwinian" rule lifecycle)
- [readysolutions.ai/blog/2026-04-08-agentic-development-starter-guide](https://readysolutions.ai/blog/2026-04-08-agentic-development-starter-guide/) — fetched; Plan-Audit-Implement-Verify workflow, no content on unknown-goal or continuous-update mechanics (see What Remains Uncertain)
- [github.com/launchdarkly-labs/claude-code-session-start-hook](https://github.com/launchdarkly-labs/claude-code-session-start-hook) — fetched; example SessionStart hook that injects context but does NOT create a plan document (negative finding)

### Round 2 additions

- [hbr.org/1995/07/discovery-driven-planning](https://hbr.org/1995/07/discovery-driven-planning) / [en.wikipedia.org/wiki/Discovery-driven_planning](https://en.wikipedia.org/wiki/Discovery-driven_planning) — Rita McGrath & Ian MacMillan's original HBR framing of planning under uncertainty (search-summary level; original HBR text is paywalled, not independently fetched — see Finding 19 sourcing note)
- [bryceyork.com/steel-threads](https://bryceyork.com/steel-threads/) — "Steel Threads: How to Build With AI Without Burning Tokens on the Wrong Thing" — AI-specific application of the walking-skeleton/tracer-bullet pattern
- [aihero.dev/tracer-bullets](https://www.aihero.dev/tracer-bullets) — "Tracer Bullets: Keeping AI Slop Under Control" — vertical-slice-per-context-window mechanism for AI coding agents
- [thedigitalbusinessanalyst.co.uk/building-features-as-part-of-discovery](https://thedigitalbusinessanalyst.co.uk/building-features-as-part-of-discovery-952df9c5a65b) — general tracer-bullet/discovery framing (search-summary level, not independently fetched)
- [addyosmani.com/blog/automated-decision-logs](https://addyosmani.com/blog/automated-decision-logs/) — Addy Osmani on Automated Decision Logs (ADL) as backward-looking capture
- [www.mindstudio.ai/blog/what-is-domain-verifiability-ai-agents](https://www.mindstudio.ai/blog/what-is-domain-verifiability-ai-agents) — "Domain Verifiability" — names the novice-can't-verify-agent's-plan risk and mitigations
- [threads.com/@boris_cherny/post/DRgyAbeDvYX](https://www.threads.com/@boris_cherny/post/DRgyAbeDvYX/plan-mode-now-spins-up-multiple-subagents-in-parallel-to-explore-your-codebase) — Boris Cherny (Anthropic) on Plan Mode's parallel-subagent exploration + clarifying questions before plan commit
- [medium.com/@ritagitamo/how-i-built-a-complete-agentic-devops-workflow-with-claude-code](https://medium.com/@ritagitamo/how-i-built-a-complete-agentic-devops-workflow-with-claude-code-2d54ae155d1b) — first-person account of learning DevOps/infra while building with Claude Code
- [medium.com/@bengilashe/how-i-built-my-first-agentic-devops-workflow-with-claude-code](https://medium.com/@bengilashe/how-i-built-my-first-agentic-devops-workflow-with-claude-code-d3c606c1da7c) — fetched; did NOT contain content on the learning-while-building angle (negative fetch, not used as a Finding)
- [extremeprogramming.org/rules/spike.html](http://www.extremeprogramming.org/rules/spike.html) / [en.wikipedia.org/wiki/Spike_(software_development)](https://en.wikipedia.org/wiki/Spike_(software_development)) — canonical XP "spike solution" definition (search-summary level, not independently fetched)
- [arxiv.org/pdf/2603.10808](https://arxiv.org/pdf/2603.10808) — "Nurture-First Agent Development: Building Domain-Expert AI Agents Through Conversational Knowledge Crystallization" (search-summary level, not independently fetched)
- [dev.to/chenverdent/why-plan-matters-in-coding-ai-agent-fixing-misaligned-prompts-1d74](https://dev.to/chenverdent/why-plan-matters-in-coding-ai-agent-fixing-misaligned-prompts-1d74) — fetched; "Keep planning lean. Planning should pay for itself" (minor supporting quote; did NOT contain the "defeats the purpose" claim — see Finding 26 UNVERIFIED note)
- [opencode.ai/docs/agents](https://opencode.ai/docs/agents/) — fetched to trace the "defeats the purpose" claim; phrase NOT found on this page (see Finding 26 UNVERIFIED note) — UNVERIFIED source for that claim
- [devops.com/what-a-good-plan-really-means-for-ai-coding-agents](https://devops.com/what-a-good-plan-really-means-for-ai-coding-agents/) — fetch failed, HTTP 403 — UNVERIFIED, not used

## Findings

### Finding 1: Cline "Memory Bank" — the most-cited named practice

**Description:** A structured multi-file documentation system (`memory-bank/` folder: `projectbrief.md`, `productContext.md`, `activeContext.md`, `systemPatterns.md`, `techContext.md`, `progress.md`) that Cline reads at the start of every task and updates as work progresses, specifically because Cline's memory "resets completely between sessions."

**Evidence:**
> "A structured documentation system that helps Cline maintain context across sessions." — describing itself as turning Cline "from a stateless assistant into a persistent development partner."

`activeContext.md` is explicitly the fastest-changing file: "Current focus, recent changes, next steps (updates most frequently)." Updates are triggered "when discovering new project patterns," "after implementing significant changes," and explicitly on the user command **"update memory bank"** — and separately, `activeContext.md` "changes most frequently; update it after each session."

**Source:** [docs.cline.bot/prompting/cline-memory-bank](https://docs.cline.bot/prompting/cline-memory-bank)

**Significance:** This is the most mature, longest-running, and most widely referenced named implementation of "living plan file" behavior in the community (predates 2026, still the reference point other blog posts compare against). It combines BOTH sub-practices the engineer asked about: a mandated read-at-start step and a mandated update step, but the update is triggered by an explicit user command or "after implementing significant changes" — not a hard per-step or per-timer rule enforced mechanically.

---

### Finding 2: Cline's own framing of the pain point

**Evidence:**
> "Every time you start a new chat, your context window fills up or resets, forcing you to waste precious minutes re-explaining your project, tech stack, and architecture."

The lifecycle described has three explicit phases — "Before work begins: Read all Memory Bank files... Verify context is complete", "During active work: Follow established patterns... Track changes and decisions", and "After significant changes: Update relevant documentation... Ensure consistency across files."

**Source:** [cline.bot/blog/memory-bank-how-to-make-cline-an-ai-agent-that-never-forgets](https://cline.bot/blog/memory-bank-how-to-make-cline-an-ai-agent-that-never-forgets)

**Significance:** Confirms the pain point (session amnesia costing "precious minutes") is the explicit stated reason the tool vendor built this feature — not a fringe complaint. The three-phase lifecycle ("before / during / after") is a concrete instance of continuous updating tied to milestones ("significant changes"), not a fixed cadence.

---

### Finding 3: Anthropic's own "structured note-taking" / agentic memory pattern (first-party)

**Evidence:**
> "Structured note-taking, or agentic memory, is a technique where the agent regularly writes notes persisted to memory outside of the context window. These notes get pulled back into the context window at later times."

The same article gives Claude Code's own todo list as the canonical example: "Like Claude Code creating a to-do list, or your custom agent maintaining a NOTES.md file, this simple pattern allows the agent to track progress across complex tasks." Anthropic also states this "allows agents to build up knowledge bases over time, maintain project state across sessions, and reference previous work without keeping everything in context."

**Source:** [anthropic.com/engineering/effective-context-engineering-for-ai-agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) (verified by re-fetch)

**Significance:** This is the strongest possible endorsement source — the vendor's own engineering blog names the general pattern (regularly-written, externalized notes) as a recommended context-engineering technique, and explicitly ties it to Claude Code's own todo-list behavior. It does not, however, specify a mandatory cadence ("regularly" is left open) or address the session-start-with-unknown-goal case.

---

### Finding 4: Claude Code TodoWrite → Task tools (official, live task list)

**Description:** Claude Code's SDK has a built-in, model-invoked mechanism for maintaining a live task list during a session, historically `TodoWrite` and — as of Claude Code v2.1.142 — the structured `TaskCreate`/`TaskUpdate`/`TaskGet`/`TaskList` tool family.

**Evidence:**
> "Todos follow a predictable lifecycle: Created as pending when tasks are identified. Activated to in_progress when work begins. Completed when the task finishes successfully."

The SDK "automatically creates todos for: Complex multi-step tasks requiring 3 or more distinct actions... Non-trivial operations that benefit from progress tracking." The migration guide states plainly the difference in update mechanics: "TaskCreate adds one item, TaskUpdate patches one item by taskId" versus the older "One tool call rewrites the full todos array."

**Source:** [code.claude.com/docs/en/agent-sdk/todo-tracking](https://code.claude.com/docs/en/agent-sdk/todo-tracking)

**Significance:** This is a first-party, mechanically-enforced (model-tool-driven, not hook-driven) instance of continuous plan/task updating — every distinct step is expected to produce a `TaskUpdate` call. It is scoped to *task-list* granularity, not a free-form narrative plan document, and it is triggered automatically by task complexity heuristics rather than a hard "every session must have one" rule.

---

### Finding 5: Claude Code Plan Mode — plan.md as first-class filesystem artifact (official + first-party commentary)

**Description:** In Plan Mode, Claude Code writes an actual markdown file to a plans folder, and — as of a recent release — syncs manual edits to that file back into the model's context.

**Evidence:**
> "A plan in Claude Code is effectively a markdown file that is written into Claude's plans folder by Claude in plan mode." ... "When exiting plan mode it will read the plan file that it wrote to disk and then start working off that." ... "The edit file tool is actually used to manipulate the plan file. So the agent is seemingly editing its own plan file!"

Boris Cherny (Anthropic, Claude Code): "Claude now writes plan files to your filesystem, and you can edit them by running: /plan open. Any changes you make are automatically synced back to Claude's context, so you can tailor Claude's plan to your exact requirements if it's not perfect."

**Sources:** [lucumr.pocoo.org/2025/12/17/what-is-plan-mode](https://lucumr.pocoo.org/2025/12/17/what-is-plan-mode/); [threads.com/@boris_cherny/post/DRgyCN5jjYA](https://www.threads.com/@boris_cherny/post/DRgyCN5jjYA/claude-now-writes-plan-files-to-your-filesystem-and-you-can-edit-them-by)

**Significance:** This confirms the mechanism the engineer is imagining (a plan file that is both machine-written and human/agent-editable, bidirectionally synced) exists as a native Claude Code feature — but it is scoped to ONE planning artifact per Plan Mode invocation, entered deliberately by the user/agent, not auto-created at every SessionStart. Ronacher's piece gives no guidance on when the plan should be created relative to how well the goal is known, nor on update cadence beyond "the agent is seemingly editing its own plan file."

---

### Finding 6: SessionStart hooks are officially for *reading* context, not writing plan files (negative finding)

**Evidence:**
> "Runs when Claude Code starts a new session or resumes an existing session. Useful for loading development context like existing issues or recent changes to your codebase, or setting up environment variables. For static context that does not require a script, use CLAUDE.md instead."

The reviewed documentation provides no official example or recommendation for a SessionStart hook that WRITES a plan/state file; its documented use is injecting `additionalContext` (e.g., current branch, uncommitted files, active issue) into the model's context at boot. The Stop and PreCompact hook events support a `decision: "block"` return, but the docs give no worked example of using either to persist a plan/state file.

**Source:** [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks) (verified by re-fetch)

**Significance:** Directly relevant to the engineer's proposed rule — there is no first-party, documented hook pattern that forces plan-file creation at session start. Every "session-start plan creation" implementation found in this research (Findings 1, 7, 9, 10) is a community/DIY convention layered on top of general-purpose hooks (`CLAUDE.md` auto-read, custom SessionStart scripts, or slash commands), not a built-in Claude Code feature.

---

### Finding 7: GitHub Spec Kit / Spec-Driven Development — explicitly goal-first, not goal-agnostic

**Description:** GitHub's open-source SDD toolkit runs a fixed pipeline of persistent markdown artifacts: `/speckit.constitution` → `/speckit.specify` → `/speckit.clarify` → `/speckit.plan` → `/speckit.tasks` → `/speckit.implement`, storing `spec.md`, `plan.md`, `tasks.md` per feature under a `specs/<NNN-slug>/` directory.

**Evidence:**
> "Be as explicit as possible about _what_ you are trying to build and _why_. Do not focus on the tech stack at this point." (guidance for the `/speckit.specify` step, which precedes planning)

`/speckit.clarify` should run "before creating a technical plan to reduce rework downstream." The output of the plan step "will include a number of implementation detail documents" stored under the feature's spec directory.

**Source:** [github.com/github/spec-kit](https://github.com/github/spec-kit)

**Significance:** Directly bears on the engineer's "goal unknown at session start" sub-question. Spec Kit's answer is the OPPOSITE of "plan first, goal figured out later" — it enforces specify → clarify → plan in that strict order, i.e., the specification of what/why must exist and be clarified BEFORE a technical plan is written. This is evidence the dominant "spec-driven" school treats an unclarified goal as a blocking precondition for planning, not something a plan file works around.

---

### Finding 8: Aider — CONVENTIONS.md (static) vs `.coding-aider-plans/` (per-feature plan files)

**Evidence:**
> "The easiest way to specify coding conventions with Aider is to create a small markdown file like CONVENTIONS.md and include it in the chat." It is "best to load the conventions file with `/read CONVENTIONS.md`... which marks it as read-only and caches it."

For planning specifically, "the main plan file should include sections like ## Overview, ## Problem Description, ## Goals, ## Additional Notes and Constraints, and ## References, and should be saved in a new markdown file with a suitable name in the `.coding-aider-plans` directory."

**Source:** [aider.chat/docs/usage/conventions.html](https://aider.chat/docs/usage/conventions.html)

**Significance:** Aider draws the same two-tier distinction the DIY community reinvents repeatedly (Findings 1, 10, 11): a static, rarely-changed "rules" document (CONVENTIONS.md) versus a per-task, actively-maintained plan document. Aider does not document an automatic session-start plan-creation hook; the plan file is a manual convention (a "suitable name" chosen by the developer), reinforcing Finding 6's pattern that plan-file automation is a community layer, not built into the base tools.

---

### Finding 9: DIY community pattern — TODO.md at two levels, Claude-maintained

**Evidence:**
> "you start a new session, Claude has no idea what you were working on, and you spend the first five minutes re-explaining context." ... "Claude Code sessions are stateless by default. Each new terminal window starts from scratch."

Mechanism: "I now maintain TODO.md files at two levels: 1. Global (~/TODO.md)... 2. Per-project (project/TODO.md)... Each project's CLAUDE.md references its TODO.md, so Claude reads it automatically." Update rule: "**Update TODO.md** as tasks are completed ([x]), started ([~]), or skipped ([-])" and explicitly "Don't manually edit TODO.md — let Claude do it as part of the workflow."

**Source:** [samfrenchblog.com/2026/02/15/how-i-use-todo-md-with-claude-code-to-never-lose-context-between-sessions](https://samfrenchblog.com/2026/02/15/how-i-use-todo-md-with-claude-code-to-never-lose-context-between-sessions/)

**Significance:** A concrete, individually-authored implementation of BOTH sub-practices — the file is auto-read at session start (via `CLAUDE.md` reference) and the update rule is stated as a standing instruction ("as tasks are completed/started/skipped"), i.e., per-step rather than per-timer. No hook is used; the update discipline relies on the model following the standing instruction in `CLAUDE.md`, not a mechanical enforcement.

---

### Finding 10: DIY community pattern — the "3-file system" (plan.md / context.md / tasks.md) with slash commands

**Evidence:**
> "plan.md, context.md, and tasks.md. Each task gets its own directory containing all three." — `plan.md`: "The implementation plan, approved before coding begins." `context.md`: "Current progress, key findings, blockers. Updated frequently." `tasks.md`: "Granular work items with status."

Mechanism: a custom slash command `/create-dev-docs` generates the three files "from the approved plan" (i.e., after the plan is approved, not blind at session start), and `/update-dev-docs` is run "before compaction" to preserve state: "Before compaction, run /create-dev-docs. After compaction, say 'continue' and Claude picks up exactly where you left off."

**Source:** [chudi.dev/blog/claude-context-management-dev-docs](https://chudi.dev/blog/claude-context-management-dev-docs)

**Significance:** This is the closest DIY analogue to the engineer's exact ask, but it inverts the ordering he described: the plan file is created only AFTER a plan is approved (i.e., after the goal is known), and the update trigger is compaction-driven (a context-window event), not a fixed per-step or per-timer rule.

---

### Finding 11: DIY community pattern — session-spec files and the "why files beat conversation" argument

**Evidence:**
> "Context loss is the most common productivity killer in long Claude Code sessions. You start with a clear plan, 45 minutes in Claude has forgotten key decisions, and you're re-explaining things you already covered." ... "Stop relying on conversation history and start encoding context into files Claude reads. Conversation history is ephemeral and degrades. Files are persistent and re-readable."

Proposed mechanism: "Session spec files (`.claude/session.md`): 'Start each message in the session with: Read .claude/session.md for context, then [actual request]'" — plus decision comments, checkpoint summaries, and git commit messages as "context anchors." Note: the article does NOT describe a hook-based automatic update mechanism — updates are manual/instructional.

**Source:** [dev.to/whoffagents/why-your-claude-code-sessions-keep-losing-context-and-how-to-fix-it-nia](https://dev.to/whoffagents/why-your-claude-code-sessions-keep-losing-context-and-how-to-fix-it-nia)

**Significance:** Independently arrives at the "externalize state to a re-readable file, reference it every turn" pattern — the same shape as Anthropic's own "structured note-taking" (Finding 3) — but confirms this specific author's version is manual discipline, not a mechanically enforced rule.

---

### Finding 12: Martin Fowler site — "Context Anchoring" (the closest thing to a formally named, authoritative practice)

**Description:** An article on martinfowler.com explicitly naming and defining "context anchoring": externalizing decision context into a living document, distinct from a project-level "priming document."

**Evidence:**
> "Context anchoring is the practice of making that alignment durable." ... "developers keep conversations running far longer than they should, not because long sessions are productive, but because closing the session means losing everything." ... critically, "the _reasoning_ behind decisions degrades faster than the decisions themselves."

On creation timing: the document was created AFTER a design conversation, not before the goal was known — "After the design conversation... I had a set of decisions worth preserving... went into a feature document." On update cadence: "In practice, the updates happened at natural pause points: at the end of a design level, when a significant decision was made, or when an open question was resolved" — with the effort framed as "a few lines after each significant moment." On the document/conversation relationship: "This is, at its core, a shift from chat-driven development to document-driven development. The conversation remains the _medium_ for making decisions, but the document becomes the _record_. Conversations are disposable by design — they are where thinking happens, not where conclusions are stored."

**Source:** [martinfowler.com/articles/reduce-friction-ai/context-anchoring.html](https://martinfowler.com/articles/reduce-friction-ai/context-anchoring.html) (verified by re-fetch: all three core phrases confirmed verbatim)

**Significance:** This is the strongest evidence of a NAMED, community-endorsed (reputable industry publication) practice matching sub-practice 2 (continuous updating) closely — "natural pause points," milestone-triggered, not per-timer or per-token-count. It directly contradicts the engineer's sub-practice 1 as literally described: the article's version of the document is created only once decisions exist to preserve, i.e., after some goal/design clarity, not blind at session zero. The companion article on the same site, [context-engineering-coding-agents.html](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html), was fetched and contains no additional content on plan/scratchpad file mechanics — it covers CLAUDE.md/Rules/Skills/Subagents/MCP/Hooks/Plugins at a higher level.

---

### Finding 13: Structured Scratchpads (`scratch` CLI) — mid-task registration, not session-start

**Evidence:**
> A scratchpad is "a folder containing a scratchpad.json manifest," described as "a thin metadata layer over the filesystem, not a database." Files are created with normal tools, "Then it registers each one" via a CLI command (`scratch add "auth-refactor" findings.md --desc "..." --type note`), with the description field emphasized as capturing "why this file exists, not just that it does."

On minimalism: "it's files on disk. Delete the folder and the knowledge is gone; the CLI never authors, copies, or moves your content."

**Source:** [nikiforovall.blog/ai/2026/06/08/scratch.html](https://nikiforovall.blog/ai/2026/06/08/scratch.html)

**Significance:** A named tool-supported pattern for the "temporary knowledge per session" problem, but its design center is mid-task artifact registration (notes, snippets, command output as they're produced), not a single plan document written blind at session start and then narratively updated. No stated critique of stale scratchpads was found in this source.

---

### Finding 14: cofin/flow — "Context-Driven Development," Beads as source of truth for auto-sync

**Evidence:**
> "By treating context as a managed artifact alongside your code, you transform your repository into a single source of truth that drives every agent interaction." ... "Create specs and plans before writing code" ... lifecycle "Context → Spec & Plan → Implement → Learn."

On auto-updating: "Beads is the source of truth. The default `syncPolicy.flowSyncAfterMutation` setting makes agents run `/flow-sync` after Beads state changes to update `spec.md`."

**Source:** [github.com/cofin/flow](https://github.com/cofin/flow)

**Significance:** A concrete, mechanically-triggered (not manual-discipline) implementation of continuous plan updating: `spec.md` is regenerated automatically whenever the underlying task-tracker ("Beads") state mutates, rather than relying on the model remembering to update a markdown file. This is architecturally different from every other "continuous updating" example found (which rely on the model following an instruction) — it derives the plan file FROM a structured state store instead of asking the model to hand-edit prose.

---

### Finding 15: "Plan decay" as a named agent-drift mechanism, with an explicit "revise on schedule" mitigation

**Evidence:**
> "Plan decay is when the agent's plan is still in context, still being followed, but no longer correct for the current state of the world." ... "Treat the plan as mutable state that must be re-evaluated at checkpoints, not as an instruction list to execute." ... "separate the plan from the execution log and revise it on schedule." This "renders plan decay visible rather than allowing it to persist silently."

The same taxonomy names five other mechanisms — goal drift (mitigated by "re-anchoring via goal restatement"), context drift (attention dilution, mitigated by compression/output offloading), role drift (mitigated by "role pinning" via periodic system-prompt re-injection).

**Source:** [usewire.io/blog/agent-drift-why-long-running-ai-agents-lose-the-plot](https://usewire.io/blog/agent-drift-why-long-running-ai-agents-lose-the-plot/)

**Significance:** This is the clearest independent articulation of WHY sub-practice 2 (continuous plan updating) matters as a distinct concern from sub-practice 1 — a plan that is never revised becomes actively misleading ("still being followed, but no longer correct"), not merely stale-and-ignored. It corroborates the engineer's stated fear ("the connection between what's written and what's actually happening breaks") almost verbatim, framed as a named, distinct failure mode.

---

### Finding 16: Critiques — living-doc decay is a widely reported failure mode, not a hypothetical

**Evidence:**
> "Most teams set up CLAUDE.md once and never touch it again. Three months later, Claude is ignoring parts of it, following instructions that no longer apply, and producing inconsistent output for reasons nobody can identify." ... "Nobody updated CLAUDE.md" after a refactor, so Claude "confidently creates files in the wrong directory, writes imports that reference a path that no longer exists." ... "Dead instructions are not harmless. Claude follows them anyway."

Recommended countermeasure (not a hook, a process discipline): "Treat architecture changes as CLAUDE.md changes. When you rename a directory, update a library, or restructure how a module works — add updating CLAUDE.md to the same PR," plus "Once every quarter, go through CLAUDE.md line by line and ask a single question for each instruction: is this still true?"

**Source:** [aicodex.to/articles/claude-md-maintenance](https://www.aicodex.to/articles/claude-md-maintenance)

**Significance:** Direct evidence for the engineer's stated fear that "plans go stale" — this source describes exactly that failure mode for the sibling artifact CLAUDE.md, and the fix offered is a PROCESS rule (tie updates to PRs; quarterly audit), not a mechanical per-step enforcement. No hook-based or automatic solution to staleness was found anywhere in this research — every mitigation found relies on either (a) the model's own discipline (Findings 1, 9, 11, 12) or (b) deriving the doc from a separate structured state store so there is nothing to go stale in prose form (Finding 14, cofin/flow).

---

### Finding 17: Critique — a study on LLM-generated context files reducing task success (partially corroborated, numeric claims UNVERIFIED)

**Evidence:**
> "LLM-generated context files — the kind you get when you run `/init` and let the model describe your repo back to you — decreased success rates." The source article references a named study, "AGENTbench" (arXiv:2602.11988), for this claim, and separately reports personal experience: "three months of accumulated instructions, half of which described a codebase that had moved on without them."

**Source:** [medium.com/@cdcore/your-claude-md-is-making-your-agent-dumber-953f6dbed308](https://medium.com/@cdcore/your-claude-md-is-making-your-agent-dumber-953f6dbed308)

**UNVERIFIED note (per Citation Discipline):** An earlier, non-fetched WebSearch result summary attributed specific figures ("reduced task success rates by approximately 3%... increased inference costs by over 20%... only a marginal 4% performance gain" for human-curated files, and an attribution to "ETH Zurich") to this topic. Direct fetch of the Medium article did **not** confirm the ETH Zurich attribution or these specific percentages — the article names a different study ("AGENTbench") and gives no percentages in the fetched text. The specific numeric figures are marked **UNVERIFIED** and are NOT used to sustain any finding above; only the qualitative claim ("LLM-generated context files... decreased success rates," directly quoted) is treated as verified.

**Significance:** Illustrates a real risk in this exact research process — a plausible-sounding statistic can appear in a search-engine synthesis without being traceable to the actual source text. Surfaced here per the citation-discipline requirement to flag rather than silently drop or silently trust.

---

### Finding 18: Checkpoint/resumability as an alternative framing to narrative plan updates

**Evidence:**
> "Implicit task structure — the agent doesn't have an explicit list of what needs to happen and in what order." ... "No resumability — if the process crashes at step 14 of 20, you start over from step 1." ... "On restart, load_workflow() finds all COMPLETED tasks and the executor skips them. You resume from exactly where you crashed." On adaptation: "Real tasks reveal unexpected information... the plan needs to adapt," with replanning capped ("at three") "to prevent infinite revision loops."

**Source:** [dev.to/manfredmacx/why-your-agent-cant-follow-a-plan-and-how-to-fix-it-f4g](https://dev.to/manfredmacx/why-your-agent-cant-follow-a-plan-and-how-to-fix-it-f4g)

**Significance:** Reframes "keep the plan updated" as a structured/state-machine problem (explicit task list + status field + resumable checkpoint) rather than a prose-document-maintenance problem — structurally similar to Finding 14 (cofin/flow) and to Claude Code's own Task tools (Finding 4). This is a recurring alternative to "ask the model to keep a markdown narrative current": several sources converge on making the plan a structured, machine-readable state object instead, precisely because prose narratives are what goes stale.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Narrative living-doc (Memory Bank, HANDOVER.md, TODO.md, feature doc) | Human-readable, easy to start, works with any agent that can read files (Finding 1) | Relies entirely on model/developer discipline to update; widely reported to decay silently over ~3 months (Finding 16) | Findings 1, 9, 12, 16 |
| Structured task list (TodoWrite/Task tools, `scratch` CLI registrations) | Model-tool-enforced updates at per-step granularity; status is explicit, not prose (Finding 4, 13) | Scoped to task/artifact tracking, not narrative "why" or "what we're NOT doing" context; triggered by complexity heuristics, not guaranteed at session start (Finding 4) | Findings 4, 13 |
| Derived-from-state-store doc (cofin/flow `spec.md` from Beads) | Nothing to go stale in prose — the doc is regenerated from the actual state (Finding 14) | Requires standing up a separate structured task tracker (Beads); more moving parts than a markdown file | Finding 14 |
| Compaction/checkpoint-triggered update (`/update-dev-docs` before compaction, PreCompact hooks) | Update trigger is an objective context-window event, not a subjective "did I remember" moment | No official Claude Code hook example ties PreCompact to writing a plan file (Finding 6); DIY implementations exist but are manual slash commands (Finding 10) | Findings 6, 10 |
| Milestone/pause-point-triggered update ("Context Anchoring") | Update effort is small ("a few lines"); ties naturally to when there's something worth recording (Finding 12) | By construction, this creates the FIRST document only once a decision exists — does not address writing a plan before the goal is known | Finding 12 |

## What the "goal unknown at session start" sub-question found

No source in this research directly endorses or documents "force the agent to write a plan file at the very start of a session, before the goal is known, stating what we're doing / what we're NOT doing." Every plan/spec-creation mechanism found is triggered AFTER some minimum of goal clarity exists:

- **GitHub Spec Kit** makes goal clarification (`/speckit.specify`, then `/speckit.clarify`) an explicit, ordered PRECONDITION to planning (`/speckit.plan`) — Finding 7.
- **Claude Code Plan Mode** writes `plan.md` only once the model exits an explore/plan cycle — Ronacher's description gives no session-zero trigger — Finding 5.
- **Martin Fowler's "Context Anchoring"** document is created only after a design conversation produced "a set of decisions worth preserving" — Finding 12.
- **chudi.dev's 3-file system** generates `plan.md`/`context.md`/`tasks.md` "from the approved plan," i.e., after approval — Finding 10.
- The closest thing to a session-zero artifact found is `CLAUDE.md`/`AGENTS.md` itself (read automatically at every SessionStart, per official docs — Finding 6) — but that is a static, project-level rules file, not a session-specific "what are we doing this session" plan, and multiple sources document it decaying when NOT the goal-scoping document (Findings 6, 16).

This is a genuine, unfilled gap in the public discussion as researched — not evidence that no one does it, only that this specific research pass (WebSearch + WebFetch across the sources above) did not surface a documented practice matching the engineer's exact "force a plan even before the goal is known" formulation.

## What remains uncertain

- Whether any Reddit (r/ClaudeAI, r/cursor) or Hacker News THREAD-level discussion specifically debates the "plan before goal is known" tension — site-scoped searches on Reddit returned no indexed results in this pass (search engine coverage limitation, not confirmation of absence).
- The specific numeric performance-impact claims referenced by a WebSearch summary (attributed to "ETH Zurich," ~3%/20%/4% figures) could NOT be verified against the actual source text fetched — see Finding 17 UNVERIFIED note. The underlying "AGENTbench" arXiv paper (2602.11988) referenced by the Medium article was not independently fetched in this pass.
- Whether X/Twitter has a more concentrated, named-hashtag discussion of this exact practice — WebSearch in this environment surfaced only the single Boris Cherny post (Finding 5) and did not return broader X thread results.
- No source explicitly addresses "periodically" (timer-based) plan updates as a distinct alternative to "on each distinct action" — every continuous-updating example found is event-triggered (milestone, compaction, task-status-change, explicit command), not wall-clock periodic.

## Suggested options for main and the engineer

- **Option A — narrative living doc, model-disciplined** (Cline Memory Bank / TODO.md / HANDOVER.md shape): a markdown plan file, read at session start via `CLAUDE.md` reference, updated by standing instruction on each distinct action. Lowest setup cost; documented failure mode is silent decay (Finding 16) absent an explicit re-audit habit.
- **Option B — structured task-list, tool-enforced** (Claude Code Task tools / `scratch` CLI shape): status-tracked items rather than prose, updated by the model's own tool calls rather than instruction-following. Narrower in scope (task status, not narrative "why"/"what we're not doing") but harder to silently ignore since it's a first-class tool call.
- **Option C — goal-gated plan creation** (Spec Kit shape): do not force a plan file at session start; require a minimum goal-clarity step (spec/clarify) before any plan file is created, on the reasoning that a plan written before the goal is known is exactly the kind of document Finding 16 shows decays fastest ("dead instructions... Claude follows them anyway").
- **Option D — derive-don't-narrate** (cofin/flow shape): keep a structured state store (task tracker) as source of truth and regenerate/sync the plan markdown from it on state-change, rather than asking the model to hand-maintain prose — removes the staleness failure mode structurally rather than procedurally (Finding 14).
- **Option E — event-triggered update, not session-start-forced** (Context Anchoring / PreCompact shape): skip the "always create at session start" rule; instead trigger plan-file writes at natural checkpoints (design decision made, compaction about to happen, significant change committed) — matches the one authoritative, named, community-endorsed pattern found (Finding 12) most closely, and sidesteps the unanswered "goal unknown" tension entirely by not requiring the artifact until there is something to anchor.

No recommendation is made among these — they trade off setup cost, staleness resistance, and fit to the "goal unknown at session start" constraint differently, and the engineer's own config context (hooks-driven enforcement, `AskUserQuestion`-based design decisions) may favor one mechanism over another for reasons outside this research's scope.

---

## Round 2 — Context persistence in exploratory / learn-as-you-go work

**Refined question:** For work the human cannot plan up front because they don't know the domain (concrete example: wiring PgBouncer through Docker + GitHub Actions + DB connectivity, using the agent specifically to avoid stopping to study everything first), what does the community actually do to avoid losing context — and is there a light option that doesn't defeat the productivity premise of using an agent?

### Finding 19: Discovery-Driven Planning (Rita McGrath & Ian MacMillan) — the plan-is-a-hypothesis school

**Description:** A planning method from strategy/management literature (HBR, 1995) built for exactly the condition Round 2 names: high uncertainty where the shape of the work cannot be known up front.

**Evidence (from search-result synthesis; original HBR article is paywalled and was NOT independently fetched — treat the framing below as a secondary summary, not a verbatim primary quote):** the method "assumes that plan parameters may change as new information is revealed," treats "assumptions as hypotheses that must be tested and validated," and uses "checkpoints, or 'milestones,' at key stages to evaluate whether these assumptions hold... assess findings, modify assumptions, and decide whether to continue, pivot, or halt."

**Source:** [hbr.org/1995/07/discovery-driven-planning](https://hbr.org/1995/07/discovery-driven-planning); [en.wikipedia.org/wiki/Discovery-driven_planning](https://en.wikipedia.org/wiki/Discovery-driven_planning) — NOT independently fetched, sourced from WebSearch synthesis only

**Significance:** This is a 30-year-old, named, well-documented answer to "how do you plan when you don't yet know enough to plan" — outside the AI-agent literature entirely, which suggests the underlying problem (plan under domain uncertainty) is a solved-shape problem in general project management, not a new one AI agents introduced. The core move — replace "is the plan accurate" with "are the plan's assumptions still holding, checked at milestones" — maps directly onto the engineer's "the connection between what's written and what's actually happening breaks" fear: Discovery-Driven Planning's answer is to make checking the assumptions a scheduled activity, not to write a more-accurate plan up front. Because this finding rests on a search summary rather than a fetched primary source, it is weighted as directional context, not a hard citation.

---

### Finding 20: Tracer bullets / walking skeleton / steel thread — the software-engineering analogue, now reapplied to AI agents

**Description:** A pre-AI Extreme-Programming-era pattern (Hunt & Thomas, *The Pragmatic Programmer*; also called walking skeleton, vertical slice, spike solution in various communities) — build the THINNEST possible end-to-end path through a system first, before deciding the full shape of the work — that multiple 2025–2026 sources explicitly re-apply to AI coding agent workflows.

**Evidence:**
> "These approaches go by many names including: vertical slices, walking skeleton, spike solution, and even 'tracer bullets'. The tracer-bullet — also called walking skeleton or steel-thread — is functionality we attempt to deliver from design to production with the purpose of exploring and de-risking." ... "The steel thread might be the single most useful mental model for anyone building software using AI in 2026... build the thinnest possible path that demonstrates the system actually works before adding width."

**Source:** search-result synthesis across [thedigitalbusinessanalyst.co.uk](https://thedigitalbusinessanalyst.co.uk/building-features-as-part-of-discovery-952df9c5a65b) and general query results — NOT independently fetched at this exact substring; corroborated directly in Findings 21–22 below via fetched primary sources

**Significance:** Names the exact "middle path" shape the engineer is asking about: instead of a comprehensive up-front plan OR pure improvisation, commit to the smallest concrete slice with a clear finish line, execute it, and let the NEXT slice's plan be informed by what the first slice taught. This is structurally identical to Discovery-Driven Planning's "milestone checkpoint" (Finding 19) but expressed as a software-engineering technique with AI-agent-specific tooling (Findings 21–22).

---

### Finding 21: Steel Threads applied to AI coding agents (Bryce York)

**Evidence:**
> "A thin wire from one bank to the other. It's not a bridge yet. You can't drive trucks across it." ... "AI doesn't feel integration pain... If you haven't defined a thin enough steel thread before you start building, you're asking the AI to hold too much in its head at once." ... "You're giving the AI a narrow, concrete goal with a clear definition of done. One input, one output, working end-to-end." ... "Once that thread exists, every subsequent prompt has something real and functional to build on."

**Source:** [bryceyork.com/steel-threads](https://bryceyork.com/steel-threads/)

**Significance:** This is a direct, AI-agent-specific mechanism for the engineer's exact problem. It does not require the human to know the domain up front — it requires only a narrow, concrete, verifiable NEXT step ("one input, one output, working end-to-end"). Context is not preserved by a written plan document at all in this account; it is preserved by the fact that each completed thread becomes a real, working, inspectable artifact the next prompt builds on — the codebase itself is the persisted state, not a markdown file. This is the clearest evidence found across both rounds of a genuinely lighter-weight alternative to "write a plan first."

---

### Finding 22: Tracer Bullets — vertical slices per fresh context window (aihero.dev)

**Evidence:**
> "Build a small feature end-to-end, test it immediately, get feedback, move to the next slice in a fresh context window, repeat." ... "Instead of building horizontal layers in isolation, you build one tiny vertical slice" ... "This approach solves the 'outruns its headlights' problem directly. You get feedback loops built into the process instead of churning out features blindly." ... "Tracer bullets are small slices of functionality that go through all layers of the system, allowing you to test and validate your approach early."

**Source:** [aihero.dev/tracer-bullets](https://www.aihero.dev/tracer-bullets)

**Significance:** Adds a specific tactic Finding 21 doesn't state explicitly: pairing each vertical slice with a **fresh context window**. This reframes "avoiding context loss" entirely — instead of fighting to keep one long session's context intact (Round 1's whole premise), this source's answer is to deliberately END the context window after each thin, verified slice and start clean, because the working code + a short slice-level note is sufficient carry-over. This is a structurally different answer to the engineer's problem than everything in Round 1: rather than "never lose context," the goal becomes "make each unit of work small enough that losing context doesn't matter."

---

### Finding 23: Automated Decision Logs (Addy Osmani) — backward-looking capture instead of forward-looking planning

**Evidence:**
> "An Automated Decision Log (ADL) is a targeted, low-overhead mechanism for capturing the reasoning behind significant AI-driven code modifications." ... "less as a comprehensive log and more as a structured set of notes-to-self, automatically generated." ... "Instruct your AI explicitly. Something like: Make sure to keep a log of what, why and how you did what you did in fyi.md." ... "Don't trust, verify. Regularly review the log. It's your responsibility to ensure it's accurate."

**Source:** [addyosmani.com/blog/automated-decision-logs](https://addyosmani.com/blog/automated-decision-logs/)

**Significance:** A named, low-overhead mechanism that is explicitly RETROSPECTIVE — it records what was done and why AFTER each significant step, rather than requiring a plan BEFORE the step. It is procedurally the exact inverse of Round 1's "write a plan, then follow it" premise, and is explicitly framed as "low-overhead" (not a heavy spike/study/plan cycle). The one caveat the author states is that verification of the log's accuracy remains the human's job — it does not remove human oversight, it relocates the human's effort from "approve the plan before work starts" to "spot-check the log afterward."

---

### Finding 24: Domain Verifiability — naming the exact risk of a novice human overseeing expert-agent work

**Description:** A named framework for when a human cannot meaningfully judge an AI agent's output/plan because they lack the domain expertise the judgment requires — directly on point for the engineer's situation (he understands PgBouncer/Docker/GHA concepts but hasn't done the wiring by hand).

**Evidence:**
> "Domain verifiability refers to how easily and reliably you can confirm that a task was completed correctly without having to do the task yourself." ... "If an AI agent summarizes a legal document and you need a lawyer to verify the summary, you haven't really automated anything — you've just added a step." ... "A task has low verifiability if checking the output requires the same level of expertise and effort as doing the work in the first place."

Mitigations offered: "For agentic workflows with multiple sequential steps, identify the steps where errors would be most costly if they propagated forward. Build explicit verification or human approval requirements at those points." ... "Break tasks into smaller steps: Large ambiguous tasks often contain sub-tasks that are individually verifiable. Breaking the workflow down lets you verify at the component level." ... "Start by defining how you will verify the output... Only once you've answered these questions should you design the automation."

**Source:** [mindstudio.ai/blog/what-is-domain-verifiability-ai-agents](https://www.mindstudio.ai/blog/what-is-domain-verifiability-ai-agents)

**Significance:** This is the clearest treatment found of the novice-human/expert-agent dynamic the engineer described. Critically, its mitigation ("break tasks into smaller, individually verifiable steps") is MECHANICALLY THE SAME MOVE as the tracer-bullet/steel-thread pattern (Findings 20–22) — arrived at independently from a verification-risk angle rather than a planning-speed angle. Two unrelated lines of argument (productivity concern vs. trust/verification concern) converge on the identical mechanism: work in small, concretely-checkable increments instead of committing to — or trying to verify — one large upfront plan.

---

### Finding 25: Claude Code Plan Mode's iterative, exploration-first refinement (official + first-party)

**Evidence:**
> "Plan Mode now spins up multiple subagents in parallel to explore your codebase and generate plans from different perspectives. Then it asks clarifying questions before committing to an approach. The result: more comprehensive, better thought-out plans before Claude writes a single line of code."

**Source:** [threads.com/@boris_cherny/post/DRgyAbeDvYX](https://www.threads.com/@boris_cherny/post/DRgyAbeDvYX/plan-mode-now-spins-up-multiple-subagents-in-parallel-to-explore-your-codebase)

**Significance:** This is the first-party tool's own answer to "how do you plan when you don't know the domain yet" — the AGENT explores first (multiple parallel subagents, read-only), and the plan is generated FROM that exploration, with clarifying questions surfaced back to the human before commitment. The human is not required to know the domain well enough to write the plan; they are only required to answer clarifying questions and review a plan the agent already grounded in actual codebase/environment inspection. This differs from Round 1 Finding 5 (which covered plan.md as a filesystem artifact) by specifically addressing the SEQUENCING question this round is about: explore → plan → clarify → commit, not plan → explore.

---

### Finding 26: First-person account — learning DevOps/infrastructure while building it with Claude Code (closest concrete analogue to the engineer's PgBouncer situation)

**Evidence:**
> "Everything I had built so far was working with local files and training data. MCP — the Model Context Protocol — changes that." (the author discovers a new tool's value through hands-on use, not upfront study) ... "CLAUDE.md is a file that lives in your project root. It is not code. It is not configuration. It is context — and it auto-loads every single time Claude Code starts in your project." (cited by the author as the mechanism that prevented context loss across a multi-session build) ... "The errors are part of the learning. The circular dependency, the wrong directory, the blocked MCP path — every failure taught me something specific about how the system works. An AI agent that self-corrects in front of you is showing you its reasoning, which is more valuable than an agent that always succeeds silently."

**Source:** [medium.com/@ritagitamo/how-i-built-a-complete-agentic-devops-workflow-with-claude-code](https://medium.com/@ritagitamo/how-i-built-a-complete-agentic-devops-workflow-with-claude-code-2d54ae155d1b)

**A companion search result (not independently confirmed by fetch) suggested a broader community framing along the lines of "spelling out every step in advance defeats the purpose of having an agent" — this specific phrasing could NOT be traced to a fetched primary source ([dev.to/chenverdent](https://dev.to/chenverdent/why-plan-matters-in-coding-ai-agent-fixing-misaligned-prompts-1d74) and [opencode.ai/docs/agents](https://opencode.ai/docs/agents/) were both fetched and checked directly; neither contains the phrase). It is marked UNVERIFIED and not used to sustain this finding. The dev.to/chenverdent article, once fetched, instead offered the more modest, confirmed quote: "Keep planning lean. Planning should pay for itself."

**Significance:** A concrete, first-person account of exactly the engineer's situation — a builder without prior hands-on infrastructure experience, using Claude Code to build real infra (MCP servers, integrations) they hadn't done by hand before. The account does not describe writing an upfront plan at all; it describes learning the tool's value through use, relying on `CLAUDE.md`'s auto-load as the persistence mechanism (same mechanism as Round 1 Findings 6 and 9), and explicitly reframing errors/failed attempts as informative rather than as planning failures. This is weak evidence (a single blog post, not a broader survey) but it is the most directly analogous account found to the engineer's stated PgBouncer/Docker/GHA scenario.

---

### Finding 27: XP "Spike Solution" — the original timeboxed-exploration pattern, with a caveat on fit

**Evidence (from search summary; canonical XP sources not independently fetched):** "A spike is a product development method... uses the simplest possible program to explore potential solutions... not to craft the perfect solution first time out." ... "Spikes represent activities such as exploration, architecture, infrastructure, research, design, and prototyping. Their purpose is to gain the knowledge necessary to reduce the risk of a technical approach." ... "Spike solutions are not meant to be part of the final product, but rather to inform or inspire it. Therefore, you need to isolate the spike solution from the main codebase."

**Source:** [extremeprogramming.org/rules/spike.html](http://www.extremeprogramming.org/rules/spike.html); [en.wikipedia.org/wiki/Spike_(software_development)](https://en.wikipedia.org/wiki/Spike_(software_development)) — NOT independently fetched, WebSearch synthesis only

**Significance — explicit fit caveat:** The XP spike is the direct namesake of this repository's own `SPIKE.md` document type and is the closest classical pattern to "explore an unfamiliar domain before committing." However, as classically defined it is explicitly THROWAWAY and ISOLATED from the main codebase ("you need to isolate the spike solution from the main codebase") — which does not match the engineer's PgBouncer scenario, where the exploration IS the production work (there is no separate throwaway prototype; the Docker/GHA/DB wiring being explored is the actual deliverable). This is a genuine mismatch worth surfacing: the classical spike-solution pattern solves "de-risk an unfamiliar technique in a sandbox," not "do unfamiliar production work directly, safely, without a separate study phase" — which is closer to what Findings 20–22 (tracer bullets/steel threads, explicitly NOT thrown away) and Finding 25 (Plan Mode explore-then-clarify) describe instead.

---

### Finding 28: "Nurture-First Agent Development" — academic framing of expertise accumulated through use, not specified up front (weak sourcing)

**Evidence (from search summary; arXiv paper not independently fetched):** "agents are not 'built' and then 'deployed' — instead they are born with minimal scaffolding and then raised through sustained interaction with their users, with development and deployment as concurrent, interleaved processes." ... "The agent's domain expertise grows organically through daily use, accumulates in its memory system as fragmented experiential data, and is periodically consolidated into structured knowledge assets through deliberate crystallization processes."

**Source:** [arxiv.org/pdf/2603.10808](https://arxiv.org/pdf/2603.10808) — NOT independently fetched, WebSearch synthesis only; treat as UNVERIFIED-tier evidence per Citation Discipline (no direct quote confirmation possible without a fetch)

**Significance:** Academically frames the same shape found practically in Findings 21–26: expertise (here, of the AGENT rather than the human) is accumulated through interleaved use rather than front-loaded, with periodic "crystallization" standing in for what Round 1 called continuous plan updating. Because this is search-summary-only and not independently verified, it should be treated as directional corroboration, not a load-bearing citation.

---

## Round 2 trade-off note

| Approach | How it avoids losing context WITHOUT upfront planning | What it costs | Source |
|---|---|---|---|
| Steel thread / tracer bullet (thin vertical slice, no comprehensive plan) | The completed, working slice itself IS the persisted state — next prompt builds on real code, not a document | Requires discipline to keep each slice genuinely thin; no source describes a mechanical enforcement | Findings 20–22 |
| Fresh context window per slice | Sidesteps context loss by ending the session on purpose after each verified unit, instead of fighting to preserve one long session | Assumes slices are small enough that a short handoff note (not a full plan) suffices between them | Finding 22 |
| Automated Decision Log (retrospective, not a plan) | Captures reasoning AFTER each significant step; low overhead, no upfront authoring required | Human must still spot-check the log for accuracy — moves the verification burden, does not remove it | Finding 23 |
| Domain-verifiability decomposition (small, individually verifiable steps) | Human doesn't need full domain expertise to verify one small step, even if they couldn't verify the whole plan | Requires the work to be genuinely decomposable into checkable units; not all infra wiring decomposes cleanly | Finding 24 |
| Agent explores first, human clarifies, plan emerges from exploration (Plan Mode) | The agent (not the human) supplies the domain grounding before a plan is proposed; human only judges clarifying questions | Still produces an upfront plan artifact eventually — the sequencing changes (explore-then-plan) but a plan document still exists at the end | Finding 25 |
| Discovery-Driven Planning (assumptions-as-hypotheses + milestone checks) | Plan is allowed to be wrong; correctness is measured by "did we check the assumption at the milestone," not "did we predict correctly" | Pre-AI, general-management origin — no AI-agent-specific tooling found; would need adaptation | Finding 19 |

## Round 2 synthesis

For work the human genuinely cannot plan up front because they don't know the domain, this research pass did **not** find a "just don't plan, and here's a magic context-preservation trick" answer. What it found instead is **convergence on a single mechanism, reached independently from at least three different angles**:

1. From a **token/productivity angle** (Bryce York, aihero.dev — Findings 20–22): don't write a comprehensive plan; commit to the *thinnest possible concrete, verifiable next step* ("one input, one output, working end-to-end"), execute it, and let the completed, working artifact — not a markdown plan — be the thing the next step builds on and the thing that carries context forward.
2. From a **trust/verification angle** (MindStudio Domain Verifiability — Finding 24): a novice human cannot verify a large plan in a domain they don't know, but they CAN verify a small, concrete step ("does this one thing work end-to-end?") — so the same "make it small" move that solves the productivity problem also solves the "I can't judge whether this plan is right" problem.
3. From a **tooling angle** (Claude Code Plan Mode's explore-then-clarify sequencing — Finding 25): the agent supplies the domain grounding through its own exploration BEFORE proposing anything, so the human is not required to already know the domain to participate meaningfully — they answer clarifying questions and review a plan already grounded in real inspection, rather than authoring the plan themselves.

None of these three requires the heavy spike→study→plan→execute cycle the engineer is trying to avoid. All three replace "write an accurate upfront plan" with "make each unit of committed work small enough that (a) it doesn't matter if the plan for the NEXT unit isn't known yet, and (b) a non-expert can still tell whether THIS unit worked." Backward-looking capture (Automated Decision Logs, Finding 23; Round 1's "structured note-taking," Finding 3; "Context Anchoring," Finding 12) is the complementary piece — once a slice is done, log what was decided and why, cheaply, after the fact, rather than trying to have predicted it beforehand.

The XP "spike solution" (Finding 27) — the pattern whose name this document type borrows — turns out to be a **poor fit** on close reading: it is explicitly a throwaway, isolated exploration, whereas the engineer's PgBouncer/Docker/GHA work is the actual production deliverable, not a disposable prototype. The tracer-bullet/steel-thread/walking-skeleton family (Finding 20) is the closer analogue precisely because it is explicitly NOT thrown away — "every subsequent prompt has something real and functional to build on" (Finding 21).

Discovery-Driven Planning (Finding 19) supplies the conceptual justification for why this works, from outside software engineering entirely: in high-uncertainty settings, a plan's job is not to be accurate, it's to name the assumptions and force a scheduled check on whether they still hold — which is a different, cheaper obligation than "know the domain well enough to plan it correctly up front."

This synthesis should be read with the sourcing-strength caveat stated throughout: Findings 19, 20 (general form), 27, and 28 rest on WebSearch summaries rather than independently fetched primary text, and are weighted as directional/corroborating rather than as hard, quote-verified citations. Findings 21, 22, 23, 24, 25, and 26 are fetched-and-quote-verified.
