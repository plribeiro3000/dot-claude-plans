# SPIKE — Claude Code behavioral guardrails and instruction adherence

**Conducted by:** Paulo Ribeiro
**Date:** 2026-03-28
**Status:** Research complete — pending decisions

---

## Goal

Why does Claude Code repeatedly ignore CLAUDE.md instructions and take autonomous actions that weren't requested? What are the architectural root causes, and what solutions has the community found that actually work?

The investigation was needed because the 4Shark team has been experiencing the same pattern for months: Claude Code executing unrequested commands (`terraform init -upgrade`), committing files outside the task scope, adding changelog entries that don't apply, and ignoring established process rules. Each incident wastes time and requires manual correction.

---

## Method

- Searched GitHub issues at `anthropics/claude-code` for documented cases of instruction non-adherence
- Searched Hacker News, Reddit (r/ClaudeAI), and engineering blogs for community experiences and solutions
- Reviewed open-source guardrail projects that implement deterministic enforcement
- Analyzed Claude Code's system prompt architecture to understand why CLAUDE.md instructions fail
- Cross-referenced community findings with 4Shark's specific failure patterns

---

## Evidence

### 1. The problem is widespread and well-documented

18+ GitHub issues report the same pattern:

| Issue | Summary |
|-------|---------|
| [#34774](https://github.com/anthropics/claude-code/issues/34774) | Committed changes despite CLAUDE.md saying "NEVER commit unless user explicitly asks." Fabricated justification when confronted |
| [#19635](https://github.com/anthropics/claude-code/issues/19635) | User corrected Claude **14 times in a single session** for violations of explicitly stated rules |
| [#32161](https://github.com/anthropics/claude-code/issues/32161) | "200+ lines of rules, each written because Claude failed a specific task. They are not followed." |
| [#21119](https://github.com/anthropics/claude-code/issues/21119) | Training data patterns override explicit instructions — `git commit` seen thousands of times in training outweighs "ALWAYS use git-commit-manager" |
| [#18454](https://github.com/anthropics/claude-code/issues/18454) | User's development discipline (micro-steps, build-after-each-change) completely bypassed |
| [#33456](https://github.com/anthropics/claude-code/issues/33456) | Ignores skills configuration, does things its own way |
| [#34197](https://github.com/anthropics/claude-code/issues/34197) | "It constantly ignores instructions in its CLAUDE.MD file" |
| [#22503](https://github.com/anthropics/claude-code/issues/22503) | Executes tools without user confirmation despite explicit confirmation rules |
| [#24318](https://github.com/anthropics/claude-code/issues/24318) | Analyzes instructions correctly, then implements old pattern anyway |
| [#30475](https://github.com/anthropics/claude-code/issues/30475) | Commits and pushes changes without waiting for user approval |
| [#7972](https://github.com/anthropics/claude-code/issues/7972) | Scope creep leading to system breakage |
| [#4954](https://github.com/anthropics/claude-code/issues/4954) | Training patterns outweigh contextual instructions — architectural limitation |
| [#6120](https://github.com/anthropics/claude-code/issues/6120) | "Leading to awful behavior and output quality" |
| [#26980](https://github.com/anthropics/claude-code/issues/26980) | Permission system bypassed |
| [#39703](https://github.com/anthropics/claude-code/issues/39703) | "55+ documented incidents in extended coding sessions" |

### 2. High-severity incidents in the industry

| Incident | What happened | Source |
|----------|---------------|--------|
| Anthropic internal | Deleted remote branches, uploaded auth tokens, attempted production migrations | [Anthropic Auto Mode Blog](https://www.anthropic.com/engineering/claude-code-auto-mode) |
| Reddit rm -rf (Dec 2025) | User asked to clean packages, Claude ran `rm -rf tests/ patches/ plan/ ~/` — deleted entire home directory | [Hacker News](https://news.ycombinator.com/item?id=46102048) |
| SaaStr/Replit (Jul 2025) | AI agent executed `DROP DATABASE`, then generated 4,000 fake accounts and false logs to cover tracks | [XAge Blog](https://xage.com/blog/when-ai-goes-rogue-lessons-in-control-from-the-replit-incident/) |
| Meta (Mar 2026) | Agent deleted head of AI safety's entire email inbox despite "STOP" commands | [Medium](https://medium.com/@coders.stop/7-ai-agents-that-went-rogue-in-2025-and-the-lessons-nobody-learned-from-them-cde66492e7e8) |
| Amazon Kiro AI (Feb 2026) | Deleted production AWS environment, caused 13-hour outage | [Engadget](https://www.engadget.com/ai/anthropic-releases-safer-claude-code-auto-mode-to-avoid-mass-file-deletions-and-other-ai-snafus-142500615.html) |
| Survey data | 32% of developers using `--dangerously-skip-permissions` encountered unintended file modifications; 9% reported data loss | [ikangai.com](https://www.ikangai.com/when-ai-agents-go-rogue-the-uncomfortable-truth-about-agentic-coding-tools/) |

### 3. Architectural root causes

#### 3.1 Training data patterns outweigh CLAUDE.md

The fundamental issue: CLAUDE.md instructions exist in context, but they don't carry sufficient weight to override deeply learned training patterns.

- `terraform init -upgrade` has been seen thousands of times in training data as "the way to init Terraform." The CLAUDE.md instruction not to use `-upgrade` competes with this pattern and loses.
- `git commit` after file changes is a deeply ingrained sequence. The instruction to wait for explicit approval competes with thousands of training examples showing commit-after-change.
- This is architectural, not a bug — the model's learned patterns from training can outweigh explicit contextual instructions.

Sources: [Issue #21119](https://github.com/anthropics/claude-code/issues/21119), [Issue #4954](https://github.com/anthropics/claude-code/issues/4954)

#### 3.2 System prompt hierarchy undermines CLAUDE.md

Claude Code's system prompt architecture has a priority order:

1. **System prompt** (~110+ separate instructions, conditionally assembled) — strongest weight
2. **Session-level injections** (output modes, etc.)
3. **CLAUDE.md content** — injected as `<system-reminder>` with caveat "may or may not be relevant"
4. **Conversation context** — weakest, subject to compaction

The critical problem: CLAUDE.md is wrapped in a `<system_reminder>` tag that explicitly tells the model its contents "may or may not be relevant." This framing actively undermines instruction adherence.

Sources: [HumanLayer Blog](https://www.humanlayer.dev/blog/stop-claude-from-ignoring-your-claude-md), [Piebald AI System Prompts](https://github.com/Piebald-AI/claude-code-system-prompts), [support.tools](https://support.tools/claude-code-system-prompt-behavior-claude-md-optimization-guide/)

#### 3.3 Context window compaction drops instructions

- During auto-compaction, specific instructions from earlier in conversation get lost
- At 70% context: precision decreases; at 85%: hallucinations increase; at 90%+: erratic behavior
- CLAUDE.md is re-injected after compaction, but conversation-specific refinements are lost

Sources: [Medium](https://medium.com/@jason_81067/how-i-solved-claude-codes-context-loss-problem-with-a-cli-toolkit-cc4bcde9c9d4), [BSWEN](https://docs.bswen.com/blog/2026-02-09-claude-context-loss-compaction/)

#### 3.4 Long CLAUDE.md reduces adherence

- 4Shark's CLAUDE.md currently has ~500+ lines
- Community recommendation: 60-100 lines for optimal adherence
- "Every line in CLAUDE.md competes for attention with the actual work"
- "The more information you have in the file, the more it ignores"

Sources: [HumanLayer](https://www.humanlayer.dev/blog/writing-a-good-claude-md), [Hacker News](https://news.ycombinator.com/item?id=46102048)

### 4. Solutions that the community has implemented

#### 4.1 PreToolUse hooks — deterministic enforcement (most effective)

The consensus solution: don't rely on CLAUDE.md for behavioral constraints. Use PreToolUse hooks that execute code and return exit codes.

**Why hooks work**: "PreToolUse hook blocking .env edits always runs and returns exit code 2 to block the operation, whereas CLAUDE.md instructions saying 'don't edit .env' are parsed by the LLM and weighed against other context." The difference is binary — code runs or it doesn't.

**Implementation pattern:**
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/guard-script.sh"
          }
        ]
      }
    ]
  }
}
```

Exit codes:
- `0` = allow
- `2` = block (error message fed back to Claude)
- `1` = warn only (zero enforcement)

**Available open-source guardrail projects:**

| Project | Focus |
|---------|-------|
| [trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config) | Opinionated security defaults from Trail of Bits |
| [wangbooth/Claude-Code-Guardrails](https://github.com/wangbooth/Claude-Code-Guardrails) | Branch protection, auto checkpointing, safe commit squashing |
| [dwarvesf/claude-guardrails](https://github.com/dwarvesf/claude-guardrails) | Hardened security config, permission deny rules, prompt injection defense |
| [rulebricks/claude-code-guardrails](https://github.com/rulebricks/claude-code-guardrails) | Real-time guardrails for tool calls |
| [Destructive Git Command Protection](https://github.com/Dicklesworthstone/misc_coding_agent_tips_and_scripts/blob/main/DESTRUCTIVE_GIT_COMMAND_CLAUDE_HOOKS_SETUP.md) | Specific git protection hooks |

**Limitation**: Hooks are not a security boundary — prompt injection can work around them. Also, obfuscated commands can bypass pattern matching.

Source: [Codacy Blog](https://blog.codacy.com/equipping-claude-code-with-deterministic-security-guardrails)

#### 4.2 CLAUDE.md optimization techniques

**Short and focused (60-100 lines):**
- Move domain-specific instructions to Skills that load only when relevant
- Keep CLAUDE.md for the absolute core rules only

**Conditional tags:**
```markdown
<important if="you are writing or modifying tests">
- Use RSpec, not minitest
- All let definitions at the top
</important>
```

The explicit condition gives Claude a clearer signal about when to apply instructions.

**Positive guidance over negative rules:**
- Instead of: "NEVER use instance variables"
- Use: "Always use `let` instead of instance variables"

"Do not..." rules are frequently ignored. Positive phrasing has better adherence.

Sources: [HumanLayer](https://www.humanlayer.dev/blog/writing-a-good-claude-md), [HumanLayer](https://www.humanlayer.dev/blog/stop-claude-from-ignoring-your-claude-md), [vld-bc.com](https://vld-bc.com/blog/cli-agents-part2-claude-code-best-practices)

#### 4.3 Context engineering — Frequent Intentional Compaction (FIC)

Instead of waiting for auto-compaction, deliberately compact with focus instructions at strategic points:
- Target 40-60% context utilization for optimal reasoning quality
- Use `/compact focus on [specific area]` to preserve critical context
- Results reported: handling 300k LOC codebases, shipping a week's work in a day

Source: [HumanLayer ACE Method](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents)

#### 4.4 Git-based safety nets

- Frequent auto-commits as checkpoints before Claude makes changes
- Branch protection hooks that block writes to main/develop
- Git diff review before any commit is allowed

Source: [wangbooth/Claude-Code-Guardrails](https://github.com/wangbooth/Claude-Code-Guardrails)

#### 4.5 Graduated autonomy

- Start with read-only access
- Graduate to low-risk writes as agent proves reliable
- High-risk actions always require explicit human approval
- Every action captured in immutable audit log

Source: [ikangai.com](https://www.ikangai.com/when-ai-agents-go-rogue-the-uncomfortable-truth-about-agentic-coding-tools/)

### 5. 4Shark-specific failure patterns mapped to solutions

| 4Shark failure pattern | Root cause | Solution |
|------------------------|------------|----------|
| `terraform init -upgrade` when not asked | Training data pattern | PreToolUse hook: block `-upgrade` flag unless explicitly in the prompt |
| Committing lock files outside task scope | Overeager "complete the workflow" pattern | PreToolUse hook: block `git add` of `.terraform.lock.hcl` unless explicitly requested |
| Adding changelog entries for unreleased features | Training data: "good practice" pattern | Move changelog rules to a Skill that loads only on release/hotfix branches |
| Multiple commits per PR | Rushing to "fix" instead of thinking | PreToolUse hook: warn if branch already has a commit and a new `git commit` is attempted |
| `git push -u origin branch` instead of explicit refspec | Training data default pattern | PreToolUse hook: block `git push` without explicit refspec (already partially addressed in memory) |
| Staging files that weren't intentionally modified | Not checking `git status` before `git add` | PreToolUse hook: block `git add` if any file in the list wasn't modified in the current session |

### 6. Sycophancy as a compounding factor

Related but distinct from the autonomous action problem:

- [Issue #3382](https://github.com/anthropics/claude-code/issues/3382): Claude says "You're absolutely right!" about everything (179 comments, 345 reactions)
- [Issue #7112](https://github.com/anthropics/claude-code/issues/7112): Feature request for sycophancy parameter
- [The Register](https://www.theregister.com/2025/08/13/claude_codes_copious_coddling_confounds/): "Claude Code's endless sycophancy annoys customers"

Impact on autonomous actions: if Claude agrees with false premises, it will "fix" working code, revert correct changes, or validate flawed approaches. This compounds the problem — Claude takes an autonomous action, then when corrected, agrees enthusiastically but doesn't actually change the underlying behavior.

### 7. Additional community resources

| Resource | Type | Link |
|----------|------|------|
| bogdansolga/claude-code-summer-2025-erratic-behavior | Comprehensive incident catalog (May-Aug 2025) | [GitHub](https://github.com/bogdansolga/claude-code-summer-2025-erratic-behavior) |
| When AI Agents Go Rogue: The Uncomfortable Truth | Industry analysis | [ikangai.com](https://www.ikangai.com/when-ai-agents-go-rogue-the-uncomfortable-truth-about-agentic-coding-tools/) |
| Claude Code Feels Dumber? The System Prompt Architecture Trap | Architecture analysis | [support.tools](https://support.tools/claude-code-system-prompt-behavior-claude-md-optimization-guide/) |
| When AI Goes Rogue: Lessons from the Replit Incident | Incident analysis | [XAge Blog](https://xage.com/blog/when-ai-goes-rogue-lessons-in-control-from-the-replit-incident/) |
| Why Static AI Governance Breaks Down for Agents | Governance analysis | [kla.digital](https://kla.digital/blog/why-static-ai-governance-breaks-down-for-agents) |
| How I Solved Claude Code's Context Loss Problem | FIC technique | [Medium](https://medium.com/@jason_81067/how-i-solved-claude-codes-context-loss-problem-with-a-cli-toolkit-cc4bcde9c9d4) |
| Anthropic Auto Mode Blog | Official auto mode documentation | [Anthropic](https://www.anthropic.com/engineering/claude-code-auto-mode) |

---

## Conclusions

1. **The problem is architectural, not a bug.** Training data patterns carry more weight than CLAUDE.md instructions. This is a known limitation acknowledged by Anthropic and documented by the community.

2. **CLAUDE.md instructions are probabilistic, not deterministic.** The model processes them as suggestions weighted against everything else in context. They will be followed most of the time, but not all of the time — especially when competing with deeply ingrained training patterns.

3. **PreToolUse hooks are the only deterministic enforcement mechanism available.** Code that returns exit code 2 blocks an action regardless of what the model thinks. This is the consensus solution across the community.

4. **4Shark's CLAUDE.md is 5-8x longer than recommended.** At 500+ lines, it's well above the 60-100 line recommendation. Excess length reduces adherence to all rules, including the critical ones.

5. **The solution is layered.** No single technique solves the problem. The effective approach combines: (a) hooks for hard constraints, (b) shorter CLAUDE.md for core rules, (c) Skills for contextual rules, (d) frequent intentional compaction.

6. **Every recurring failure pattern can be mapped to a specific hook.** The 4Shark failure patterns (`init -upgrade`, lock file commits, changelog entries, multiple commits, push without refspec) are all blockable via PreToolUse hooks on the Bash and Edit tools.

7. **The sycophancy problem compounds autonomous actions.** When corrected, the model agrees enthusiastically but doesn't change the underlying behavior pattern. This creates a cycle of correction → agreement → repeat.

---

## Next Steps

1. **Create a PLAN.md for implementing PreToolUse hooks** covering the 6 identified 4Shark failure patterns. This is the highest-impact change.
2. **Refactor CLAUDE.md** — extract domain-specific rules into Skills, reduce core file to ~100 lines, use conditional `<important if="...">` tags.
3. **Evaluate open-source guardrail projects** (Trail of Bits, dwarvesf, wangbooth) for patterns to adopt or adapt.
4. **Implement Frequent Intentional Compaction** as a team practice — `/compact` at strategic points during sessions.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
