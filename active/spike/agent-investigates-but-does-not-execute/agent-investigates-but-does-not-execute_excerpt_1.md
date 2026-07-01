# CLAUDE.md Relevant Sections — Verbatim Excerpts
# Source: /Users/plribeiro3000/.claude/CLAUDE.md (1465 lines)
# Read in spike session: 2026-06-30

---

## Section: "Work Through to the Pull Request"

**Verbatim from CLAUDE.md (scope: code tasks only):**

> **A request to work on something IS the authorization to carry it through to an open Pull Request.** When the engineer asks to implement, fix, refactor, or otherwise change code, the default is the full cycle in one go: work in the worktree → commit → push → `gh pr create`. **Stop only when the PR is open** — that is the point where the engineer reviews and decides the merge. Do NOT stop after writing the code to ask "quer que eu faça commit e abra o PR?" — the request already answered that

> **The merge gate is the ONLY hard stop, and it stays intact.** Going through to an open PR is authorized; merging it never is

> **Why**: the only documented, legitimate stop in the git flow is the merge. Pausing at commit/PR is a model reflex...

**Analysis:** This section explicitly overrides the ask-reflex for code tasks. The word "code" is used three times in the description. The section scopes itself to: "implement, fix, refactor, or otherwise change code." It does not cover ops/infra actions (starting/stopping EC2 instances, running mongosh queries, MFA elevation for production operations).

---

## Section: "AWS Policy"

**Verbatim from CLAUDE.md § "AWS Policy" (lines 848-860, read in current session):**

> - **Use the default AWS profile for all read-only operations** — logs, service status, resource listing
> - **Only use the `4shark-mfa` profile** (via `--profile 4shark-mfa`) for write operations
> - **Do NOT preemptively check MFA or run `/elevate-aws-access`** for routine AWS commands
> - **If a command fails with a permission or session error — `AccessDenied`, `UnauthorizedAccess`, `ExpiredToken`, `RequestExpired`, or any message containing `security token ... is expired` / `signature has expired`**: execute `/elevate-aws-access` yourself (do NOT ask the engineer to run it — the skill and `elevate-aws-access.sh` are auto-approved via `auto-approve-local-skills.sh` and `permissions.allow`), then retry the original command with `--profile 4shark-mfa`.
> - **For starting/stopping EC2 instances, use the wrapper scripts** — `~/.claude/scripts/start-instance.sh` and `~/.claude/scripts/stop-instance.sh`. Both are auto-approved via `permissions.allow`, default region to `sa-east-1`, and accept `--profile 4shark-mfa`.

**Analysis:** The AWS Policy tells WHICH commands to use for start/stop (the wrapper scripts) and specifies the `4shark-mfa` profile. It does NOT address whether to re-confirm before starting 3 production instances when the original instruction was "sobe o MongoDB." The "execute `/elevate-aws-access` yourself" sentence shows the pattern CAN authorize self-execution — it does so for MFA elevation specifically. This authorization does not extend to the underlying infra action (starting instances).

---

## Section: "Questions Are Just Questions"

**Verbatim from CLAUDE.md § "Questions Are Just Questions":**

> **When the engineer asks a question: answer the question and stop** — do not continue implementing, do not resume previous work, do not take any action beyond answering
> **A question means the engineer interrupted for a reason** — they identified a gap or a doubt. Continuing to execute ignores the interruption
> **After answering, wait** — the engineer decides what happens next, not you
>
> **When a gap is identified during execution:**
> **If the gap is real: return to planning** — do not jump to a code fix. Unplanned problems cannot be solved at the code level. The plan needs to account for it first, then execution resumes
> **Execution only resumes when the engineer explicitly says so** — after the plan is updated and the engineer confirms, then go back to the task

**Analysis:** "Execution only resumes when the engineer explicitly says so" is a mandatory-stop rule that compounds with the ask-reflex during ops tasks. During the failing instance, the agent hit a perceived ambiguity (3 production instances = high-blast-radius?), interpreted it as a gap, and paused to confirm. This rule amplified the effect.

---

## Section: "Workflow Philosophy"

**Verbatim from CLAUDE.md § "Workflow Philosophy":**

> **Unanswered questions stop execution** — if a question appears during implementation, stop and return to planning. Never decide in micro without macro context

**Analysis:** Third gate that compounds. "Unanswered questions" is vague — it can be interpreted to include any perceived uncertainty during ops, not just design-decision uncertainty. No ops/infra exception is carved out.

---

## Section: "Scope Discipline" (Blockers subsection)

**Verbatim from CLAUDE.md § "Scope Discipline — Blockers":**

> A problem discovered mid-task that **must be resolved to deliver the engineer's request**. You did not decide to fix it; the task itself cannot finish without it.
> - STOP. Do not attempt the fix on your own.
> - Report: "I found X. Without it, Y cannot be delivered. Options: A, B, C. I recommend B."
> - Wait for the engineer's decision.

**Analysis:** The Blockers rule explicitly instructs STOP + report + wait for any mid-task discovery. During the failing instance, the agent discovered that 3 production EC2 instances needed to be started for a production MongoDB cluster. This was classified as a "blocker" requiring explicit authorization. Whether starting 3 production instances actually qualifies as a "blocker" (an unplanned problem requiring the engineer's decision) or as execution of the original instruction is the classification gap.

---

## CLAUDE.md — Stop/Confirm Gate Inventory

Complete count of stop or confirmation gate rules in CLAUDE.md (1465 lines), by section:

| Section | Gate type |
|---------|-----------|
| Git Safety — "NEVER merge a Pull Request unless the engineer instructs it explicitly" | Hard stop — always |
| Git Safety — destructive commands blocked | Mechanical block |
| Git Tag & Version Policy — "NEVER run git tag without explicit instruction" | Hard stop — always |
| Questions Are Just Questions — "answer the question and stop" | Hard stop — on any question |
| Questions Are Just Questions — "Execution only resumes when the engineer explicitly says so" | Hard stop — after gap |
| Scope Discipline (Blockers) — "STOP. Do not attempt the fix on your own." | Hard stop — on discovery |
| Workflow Philosophy — "Unanswered questions stop execution" | Hard stop — on any uncertainty |
| Code Pattern Discipline (Pattern Priming) — "Wait for confirmation" before writing code | Hard stop — pre-code |
| Ask, Don't Decide — AskUserQuestion gate | Hard stop — design decisions |
| Configuration Changes Policy — "NEVER edit ~/.claude/ directly" | Hard stop — config changes |
| Disagree and Commit — "Disagree once, explicitly" | Mandatory disagree before comply |
| Deployment Strategy — "Present BOTH paths to the engineer" | Present + wait — deploy decisions |

Counter-rules that explicitly override the ask-reflex:

| Section | Override |
|---------|----------|
| Work Through to the Pull Request | Authorized through PR — CODE TASKS ONLY |
| AWS Policy — `/elevate-aws-access` self-execution | Authorized self-execution — MFA ELEVATION ONLY |

Ratio: 12 stop/gate rules : 2 counter-rules
Ops/infra domain counter-rules: 1 (MFA elevation only) — starting/stopping production instances not covered

---

## ASK-DONT-DECIDE.md — Key Sections

**Verbatim from ~/.claude/docs/ASK-DONT-DECIDE.md line 32:**

> The boundary is judgment, but the safe direction is *ask*. The engineer can always say "use your judgment for this category" — but Claude does not get to grant that permission to itself.

**Verbatim from ASK-DONT-DECIDE.md lines 105-111:**

> The 4Shark balance:
> - **Ask** when the decision is non-trivial AND the answer is not in any documented rule AND the surrounding code does not unambiguously show the answer
> - **Do not ask** when the answer is in a rule, in the surrounding code, or in an explicit instruction the engineer just gave
> - **Bias toward asking** when in doubt — the cost of one question is lower than the cost of writing wrong code that the engineer only sees later

**Verbatim from ASK-DONT-DECIDE.md lines 117-126 (Hook injection table):**

> This document is loaded as Tier 1 (full content, every session) via `scripts/read-context.sh`. The same set of hooks that injects `CODE-PATTERN-DISCIPLINE.md` also injects this principle:
>
> | Hook event | Script |
> |---|---|
> | SessionStart | `inject-code-pattern-rule.sh` (carries reference to this doc) |
> | UserPromptSubmit | `inject-code-pattern-rule.sh` |
> | PreToolUse(Edit\|Write\|MultiEdit) | `inject-code-pattern-on-write.sh` |
> | SubagentStart | `read-context.sh` (subagent mode — inlines this doc as Tier 1) |

**Analysis:** "the safe direction is ask" is injected into context at 4 distinct hook events per session. No ops/infra exception exists in this doc. When the model evaluates an ops action (e.g., start 3 production EC2 instances), the Tier 1 rule "bias toward asking" applies by default, because no counter-rule overrides it for this domain.
