# PLAN — Subagent Research-Only Contract

**Branch:** `feature/subagent-research-only-contract`
**Worktree:** `/Users/plribeiro3000/Projects/4Shark/dot-claude-subagent-contract/`
**Spike:** `~/.claude/plans/active/spike/subagent-shallow-execution-and-verification/SPIKE.md`
**One PR. Three layers. All together.**

---

## Decisions confirmed by the engineer (2026-05-15)

1. **`pr-writer` is killed** — file deleted from `agents/`. All references in `CLAUDE.md` removed (Repository Structure, Available Agents, Recommended Workflow). Main composes PR directly from the diff and runs `gh pr create` (already in the standard flow).
2. **`orchestrator` — frontmatter only.** Add `tools:` restricting to `Read, Glob`. Body unchanged (already research/guidance-only).
3. **Smoke test — manual on the PR.** I invoke a `Task` call after the changes are in place, capture evidence that `additionalContext` reaches the subagent, attach to the PR description.
4. **PLAN approved as-is** — proceed to execute phases below.

Agent count drops from 11 to 10 in Layer C (pr-writer removed entirely, not rewritten).

---

## 1. Goal in one sentence

Subagents become **research-only**: they gather and quote, they never write workflow documents, never write code, never conclude, never recommend. Main is the only one that synthesizes, decides, and writes files. The rule is documented (Layer A), enforced per-agent (Layer C), and injected mechanically at every `Task` invocation (Layer B).

## 2. Why

The May 15 2026 incident: the spike subagent claimed *"all 5 neighbors follow the same pattern as `plan_document/processor.rb`"*. Main accepted the claim. The engineer read the 5 files manually and found ~7 invented methods with zero precedent in the neighbors. Full diagnosis with industry evidence is in `SPIKE.md` — Issues #21585 (Bash subagent fabricates command output), #42796 (Read:Edit ratio dropped 70%), #46588 (*"Claude claims it read files it didn't read, reports results it didn't verify. When challenged, it admits to fabricating data."*).

The current architecture relies on subagents to **draw conclusions** (code-reviewer issues a verdict, spike recommends an option, planner writes a strategy). When the subagent fabricates the analysis behind that conclusion, main has no way to detect it — main never sees the work, only the summary. Subagents writing trust-critical documents (PLAN.md, SPIKE.md, KNOWLEDGE.md, etc.) is the worst-affected slot: the .md is the only artifact and main accepts it whole.

The fix is structural — remove the failure mode by removing the subagent's ability to conclude. If a subagent cannot return a verdict, it cannot return a fabricated verdict.

## 3. Principle the engineer set

| Subagents ARE allowed to | Subagents ARE NOT allowed to |
|---|---|
| Research codebase (`Read`, `Grep`, `Glob`) | Write code (`Edit`, `Write`, `NotebookEdit`) |
| Search the web (`WebFetch`, `WebSearch`) | Write workflow documents (PLAN.md, SPIKE.md, KNOWLEDGE.md, PROCESS.md, DOMAIN.md, CONTEXT-MAP.md, TASKS.md, BLUEPRINT.md, ANALYSIS.md, etc.) |
| Read external state via read-only Bash (`git log`, `git diff`, `aws describe-*`, `aws get-*`) | Execute state-changing commands (`gh pr create`, `git push`, `aws ec2 start-*`, `terraform apply`) |
| Return structured findings: citations, file:line + verbatim quotes, search results, URLs, factual data | Make recommendations, draw conclusions, issue verdicts (APPROVED, BLOCKED, etc.), choose among options |
| Suggest follow-up questions to main | Take any decision in the engineer's name |

Main is the synthesizer. Main writes every workflow document. Main runs every state-changing command. Main draws every conclusion.

## 4. Main's verification rule (refined per the engineer)

The verification is **scope compliance**, not re-reading the subagent's research. The latter is a waste of time — if main has to re-read everything the subagent read, the subagent bought nothing.

Main verifies, after every `Task` invocation:

1. **Did the subagent write any file?** Check git status in the worktree, check `~/.claude/plans/active/` mtimes, check `/tmp/` for new artifacts. If yes and that file wasn't explicitly authorized, **rollback the file** (`git restore`, `rm`) and **respawn the subagent** with a corrected briefing that names the violation.
2. **Did the subagent return a conclusion or recommendation?** Scan the subagent's reply for verdict-shaped language ("I recommend", "the best option is", "this is correct", "APPROVED", "CHANGES REQUESTED", "you should", etc.). If found, **discard the verdict portion** and re-prompt asking only for the underlying findings.
3. **Did the subagent execute a state-changing command?** Bash hooks already block destructive shapes, but write-shaped reads (`cat > file`, `tee`, `sed -i`, `gh pr create`, etc.) are not covered. Spot-check the subagent's tool-use trace if it ran any Bash.

Main does **NOT** verify "did the subagent actually read the files it claims to have read". That kind of check is what the engineer correctly called out as wasted effort. Trust the read, distrust the conclusion.

## 5. Changes — three layers, one PR

### Layer A — `~/.claude/CLAUDE.md` rule

Add a new section near "Questions Are Just Questions" / before "Lookup Resolution":

```markdown
### Subagent Contract — Research Only

Subagents are research-only. They gather and quote. They never:
- Write code (no `Edit`, `Write`, `NotebookEdit`)
- Write workflow documents (no PLAN.md, SPIKE.md, KNOWLEDGE.md, PROCESS.md,
  DOMAIN.md, CONTEXT-MAP.md, TASKS.md, BLUEPRINT.md, ANALYSIS.md, or any other
  type from the Document Types table)
- Execute state-changing commands (no `gh pr create`, no `git push`, no
  `aws ec2 start-*`, no `terraform apply`, no `cat > file`, no `tee`,
  no `sed -i`)
- Make recommendations, draw conclusions, issue verdicts, or choose
  among options

Subagents return **structured findings**: citations (file:line + verbatim
quote), search results, URLs, factual data, summaries of file contents.
Main synthesizes; main decides; main writes every file.

#### Verification after every Task invocation

The main session verifies **scope compliance** — not whether the subagent
actually read the files it claims (that is wasted effort; trust the read).

After every `Task` return, main MUST:

1. **Did the subagent write any file?** Check `git status`, check
   `~/.claude/plans/active/` for new files, check `/tmp/`. If yes and not
   explicitly authorized: rollback (`git restore`, `rm`) and respawn the
   subagent with a corrected briefing that names the violation.
2. **Did the subagent return a verdict or recommendation?** Scan the reply
   for verdict-shaped language ("I recommend", "the best option is",
   "APPROVED", "CHANGES REQUESTED", "you should X", etc.). If found,
   discard the verdict and re-prompt for the underlying findings only.
3. **Did the subagent execute a state-changing command via Bash?** Spot-check
   the tool-use trace. If a write-shaped command ran, rollback its effects
   and respawn.

This rule is the engineer's explicit standing instruction. Apply on every
Task invocation, without asking.

#### Why this exists

The May 15 2026 incident: the spike subagent claimed "all 5 neighbors follow
the same pattern". Verification (engineer reading the 5 files manually)
showed ~7 invented methods with zero precedent. Cost: 2 spikes discarded,
~25 minutes lost, full loss of trust in subagent output.

The root cause is documented across multiple `anthropics/claude-code` issues
(#21585, #42796, #46588) — subagents fabricate conclusions and main accepts
them as truth. This rule structurally removes the failure mode by removing
the subagent's permission to conclude.

See: `~/.claude/plans/completed/spike/subagent-shallow-execution-and-verification/SPIKE.md`
for the full diagnosis.
```

### Layer B — `scripts/inject-subagent-contract.sh` (PreToolUse on `Task`)

Mirrors `inject-terraform-context.sh`. Fires on every `Task` invocation, injects an `additionalContext` payload spelling out the contract directly in the subagent's prompt at the moment it spawns.

**Behavior:**

```bash
#!/bin/bash
# Subagent Contract Injection Hook (PreToolUse on Task)
#
# Fires before any Task tool invocation and injects the research-only
# contract into the subagent's context via additionalContext.
#
# Wiring: settings.json -> hooks.PreToolUse with matcher="Task".
#
# Always exits 0. A failing hook must NEVER block a Task invocation.

set -u
cat > /dev/null   # drain stdin

contract=$(cat <<'CONTRACT'
=== SUBAGENT CONTRACT (injected by PreToolUse hook) ===

You are a research-only subagent. The main Claude Code session delegated
this Task to you to gather information and return structured findings.

You MAY:
- Read files (Read tool)
- Search code (Grep, Glob)
- Search the web (WebFetch, WebSearch)
- Run read-only Bash commands (git log, git diff, aws describe-*, aws get-*)

You MUST NOT:
- Write or edit any file (no Edit, Write, NotebookEdit)
- Write workflow documents (no PLAN.md, SPIKE.md, KNOWLEDGE.md, PROCESS.md,
  DOMAIN.md, CONTEXT-MAP.md, TASKS.md, BLUEPRINT.md, ANALYSIS.md, etc.)
- Execute state-changing commands (no gh pr create, no git push, no
  aws ec2 start-*, no terraform apply, no cat > file, no tee, no sed -i)
- Make recommendations, draw conclusions, issue verdicts, or choose
  among options ("I recommend...", "the best option is...", "APPROVED",
  "you should...", etc.)

Your output is structured findings only:
- Citations: file:line + verbatim quotes
- Search results: URLs + relevant excerpts
- Factual data: counts, lists, summaries of what exists
- Direct observations: "file X contains Y", "command C returned R"

The main session will synthesize, decide, and write every file.

If the briefing asks you to write a file or draw a conclusion, refuse and
explain: "This task asks for a forbidden action. I can return findings;
main will synthesize."
CONTRACT
)

if command -v jq > /dev/null 2>&1; then
    jq -n --arg ctx "$contract" '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            additionalContext: $ctx
        }
    }'
else
    # fallback escape as in inject-terraform-context.sh
    ...
fi

exit 0
```

**Wired into `settings.json`** by adding a new block to `hooks.PreToolUse`:

```json
{
  "matcher": "Task",
  "hooks": [
    {
      "type": "command",
      "command": "$HOME/.claude/scripts/inject-subagent-contract.sh",
      "timeout": 5
    }
  ]
}
```

### Layer C — Agent definitions rewritten

Each agent in `agents/*.md` gets:

1. **Frontmatter `tools:` field restricted** to read-only tools. The default (no `tools:` field) gives subagents all tools. We add the field with an explicit allowlist.
2. **Description updated** to reflect research-only role ("returns structured findings", not "creates SPIKE.md").
3. **Body updated** to:
   - Replace any "write the .md file" step with "return structured findings to main; main writes the file"
   - Remove verdict-issuing language ("APPROVED", "BLOCKED", "I recommend")
   - Add a "Forbidden actions" section listing the contract from Layer B

Per-agent change table:

| Agent | Current responsibility | New tools | Output change |
|---|---|---|---|
| `orchestrator` | Guides workflow, asks questions | `Read, Glob` | No change to behavior (already research/guidance only). Confirm no Write usage. |
| `knowledge-cruncher` | Writes `KNOWLEDGE.md` | `Read, Grep, Glob, WebFetch, WebSearch` | Returns extracted concepts + constraints in structured format. Main writes `KNOWLEDGE.md`. |
| `context-mapper` | Writes `CONTEXT-MAP.md` | `Read, Grep, Glob` | Returns bounded-context relationships. Main writes `CONTEXT-MAP.md`. |
| `process-modeler` | Writes `PROCESS.md` | `Read, Grep, Glob` | Returns process model (actors, events, decision points). Main writes `PROCESS.md`. |
| `domain-modeler` | Writes `DOMAIN.md` | `Read, Grep, Glob` | Returns entities + value objects + relationships. Main writes `DOMAIN.md`. |
| `planner` | Writes `PLAN.md` | `Read, Grep, Glob, WebFetch, WebSearch, Bash` | Returns options analysis with trade-offs. Main writes `PLAN.md`. |
| `spike` | Writes `SPIKE.md` | `Read, Grep, Glob, WebFetch, WebSearch, Bash` | Returns findings + sources. Main writes `SPIKE.md`. |
| `task-creator` | Writes `TASKS.md` | `Read, Glob` | Returns task decomposition (titles + completion criteria). Main writes `TASKS.md`. |
| `code-reviewer` | Writes HTML + chat verdict | `Read, Grep, Glob, Bash` | Returns list of findings (file:line + quote + concern). Main composes the HTML report and decides verdict. |
| `security-reviewer` | Writes report + verdict | `Read, Grep, Glob, Bash` | Same as code-reviewer. |
| `pr-writer` | Runs `gh pr create` | `Read, Grep, Glob, Bash` | Returns proposed PR title + body. Main runs `gh pr create`. |

**Note on Bash:** Bash is included in some agents because read-only operations (`git log`, `git diff`, `aws describe-*`) are essential for their research. Layer B's contract text explicitly forbids state-changing Bash. The existing `validate-bash-command.sh` hook already blocks the most destructive shapes regardless of caller.

**Note on orchestrator:** It is the most narrowly scoped agent in the set — it asks questions and points to other agents. It does not write workflow documents. Likely no body changes; only the frontmatter tools field is added.

## 6. Execution phases

Each phase = one logical commit, but per project convention (one commit per PR, squashed at end), they coalesce. Phases are listed for **execution order**, not for separate commits.

| # | Phase | Files touched |
|---|---|---|
| 1 | Write Layer A — CLAUDE.md rule | `CLAUDE.md` (one new section + cross-reference from Repository Structure block) |
| 2 | Write Layer B — hook script | `scripts/inject-subagent-contract.sh` (new), `settings.json` (new PreToolUse block) |
| 3 | Rewrite agent definitions — Layer C | `agents/{orchestrator,knowledge-cruncher,context-mapper,process-modeler,domain-modeler,planner,spike,task-creator,code-reviewer,security-reviewer,pr-writer}.md` (11 files) |
| 4 | Audit existing commands/skills for subagent-writes-file patterns | `commands/*.md`, `skills/**/SKILL.md` — confirm none direct subagents to write files; document any exceptions |
| 5 | Update CHANGELOG.md | `CHANGELOG.md` (Added/Changed entries) |
| 6 | Update CLAUDE.md "Repository Structure" block | Mention new hook script in the scripts list |
| 7 | Smoke-test the hook | Manually invoke a Task call and verify `additionalContext` reaches the subagent prompt |
| 8 | Commit, push, PR | Single commit `feat(subagent): research-only contract — agents, rule, hook`. Push with explicit refspec. PR title same as commit, body links the SPIKE. |

## 7. Risks

- **Risk 1 — orchestrator workflow assumes subagents write files.** The standard workflow (`@agent-planner → @agent-task-creator → /execute`) expects each agent to leave a file. After the change, the agent returns findings and main writes the file. Main's prompt may need a follow-up instruction. **Mitigation:** in each agent's "Next Steps" section, explicitly tell main "now write the .md file at <path> with this structure: ..."
- **Risk 2 — Code review HTML report is large.** Currently `code-reviewer` writes a full HTML report. Moving that to main means main has to compose 100+ lines of HTML. **Mitigation:** the agent returns the structured findings; main copies the template and fills in fields. Template stays the source of truth.
- **Risk 3 — pr-writer was the only one running `gh pr create`.** Now main runs it. **Mitigation:** pr-writer returns proposed title + body in chat; main runs `gh pr create` with a HEREDOC body. Single-line policy still applies.
- **Risk 4 — Hook adds tokens to every Task invocation.** ~1 KB additional context per call. **Mitigation:** acceptable cost; same shape as `inject-terraform-context.sh`. If hook tokens become a problem, scope down by `if:` matcher (but Task has no sub-matchers currently).
- **Risk 5 — Built-in subagent types (`Explore`, `general-purpose`, `claude`) are NOT in `agents/*.md`.** They are Anthropic-defined. We cannot change their frontmatter. Layer B hook is the only way to enforce the contract on them. **Mitigation:** the hook matches `Task` without further constraint, so all subagent types receive the contract via `additionalContext`.
- **Risk 6 — `model: sonnet` agents may comply more readily than `model: opus` agents.** No data on this; community evidence (Issue #42796) suggests rule-following degraded for opus in March-May 2026. **Mitigation:** Layer A + B together; if compliance is still low, escalate to refusing the Task entirely via hook (would block, not allow). Defer that to a follow-up.

## 8. Acceptance criteria

The PR is mergeable when:

1. `CLAUDE.md` contains the new "Subagent Contract — Research Only" section with the verification rule.
2. `scripts/inject-subagent-contract.sh` exists, is executable, and emits valid PreToolUse JSON with the contract in `additionalContext`.
3. `settings.json` has a new PreToolUse block matching `Task` and pointing to the hook.
4. All 11 `agents/*.md` files have:
   - A `tools:` field in frontmatter restricting to read-only tools per the table in § 5
   - Description updated to reflect research-only role
   - Body updated to remove any "write the .md file" step and replace with "return findings to main"
   - No verdict-issuing language remaining
5. `CHANGELOG.md` has entries under `### Added` (the contract rule, the hook) and `### Changed` (subagent definitions).
6. Smoke test: invoke `Task(subagent_type=Explore, prompt="find all .rb files matching X")` and confirm the subagent receives the contract in its system prompt at spawn.

## 9. Open questions for the engineer

1. **Worktree path** — I created the worktree at `/Users/plribeiro3000/Projects/4Shark/dot-claude-subagent-contract/`. OK or move it?
2. **Built-in subagent types (Explore, general-purpose, claude)** — Layer B hook covers them via context injection, but their built-in system prompts may override. We can't see those prompts. Worth a follow-up to test compliance on each? Or accept and move on?
3. **`orchestrator` agent — body changes needed?** Reading suggests no — it already asks questions and points to agents, doesn't write. Confirm: skip body edits, only add `tools:` frontmatter?
4. **pr-writer's `gh pr create` ban** — current pr-writer runs the command directly. New behavior: returns title + body, main runs the command. Confirm this is the right split, or keep `gh pr create` as an allowed exception for pr-writer specifically?
5. **CHANGELOG.md entry wording** — current convention is one-line entries naming the subject. Proposal: `### Added — Subagent research-only contract` and `### Changed — Agent definitions and workflow`. OK?
6. **Test agent — should I include a test in this PR?** E.g., a deliberately-violating Task call to confirm the hook injects the contract and main rolls back. Or defer testing to manual verification?

---

**Ready for sign-off.** Once approved, I execute phases 1-8 in the worktree, then push and open the PR.
