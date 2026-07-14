# PLAN — Enforce evidence-on-surfacing for `AskUserQuestion` (Mechanism B + E)

## Context

The `agent-over-elicitation` spike identified two composing failures in the decision/ask pipeline, both already documented in prose and injected by hook on every turn, both of which still fired on a real incident:

- **Failure 1 (pre-filter)** — the agent asks the engineer to decide a tactical, reversible, low-blast-radius point with an obvious recommended path. Judgmental by nature; no regex classifies "tactical vs strategic" (spike Finding 10).
- **Failure 2 (delivery)** — when a decision genuinely is strategic, the agent surfaces it as abstract text with no code excerpt. Root cause is verified: the `AskUserQuestion` tool schema has no field for evidence (spike Finding 6), so the Output-Policy-Layer-5 / Decision-Card rule has nowhere to land.

The gap is **not a missing concept** — it is missing enforcement of a judgmental rule. Every high-value 4Shark rule eventually migrated from prose to a mechanical hook; the ask/surfacing pipeline is the one major decision point that never received this treatment (spike Finding 8: zero hooks reference `AskUserQuestion` today).

## Decision (engineer, this session)

- **Mechanism A dropped — confirmed infeasible in the Claude Code runtime.** Claude Code does not server-side validate an MCP tool's `required` fields; a missing field is only rejected by the MCP server after the model already made the call. The schema-level guarantee that distinguished A from B does not hold here — A degrades to model-compliance + post-call rejection, no stronger than B. (Confirmed via Claude Code MCP + hooks docs.)
- **Go with Mechanism B** (PreToolUse hook gating `AskUserQuestion`) for Failure 2, **paired with Mechanism E** (prose hardening) for Failure 1.
- **Escalation path, not now:** if B + E proves insufficient for Failure 1 in practice, the next step is Mechanism C (ask-time verifier — the only option with an independent second pass, per spike Finding 9). Out of scope for this plan; revisit with evidence.

## Scope

A dot-claude configuration change delivered through the standard PR workflow (working copy, never editing `~/.claude` directly — per § Configuration Changes Policy). Three tracked artifacts:

1. A new PreToolUse hook script.
2. Its wiring in the tracked `settings.json`.
3. The prose hardening (Mechanism E) in the relevant doc(s).

## What B enforces (and what it deliberately does not)

- **Enforces (Failure 2, mechanical):** when an `AskUserQuestion` call surfaces a **code-shaped** decision and carries **no evidence marker** (a `path:line` reference or a fenced code block in the question/options text), the hook returns `permissionDecision: "deny"` with a corrective message telling the agent to re-issue the question with the code excerpt + file:line + flow narrative that Output Policy Layer 5 already requires.
- **Does not enforce (Failure 1, judgmental):** the hook does not attempt to classify tactical-vs-strategic — that is not regex-able (spike Finding 10). Failure 1 is addressed by Mechanism E (prose), reinforced by the fact that B raises the cost of asking (an ask now requires attaching real code), which indirectly discourages low-value asks.
- **Accepted limitation:** heuristic, not schema-level. A fabricated `path:line` string passes the regex. This is the same ceiling every `validate-*.sh` pattern-match hook already operates under (spike trade-off table). It raises the cost of a bare ask; it does not make one impossible.

## Tasks

### Task 0 — Empirical smoke-test: does a PreToolUse matcher fire on `AskUserQuestion`?

The hooks doc confirms PreToolUse matches by tool name and can `deny`, but does not list `AskUserQuestion` among its examples (`Bash`, `Edit|Write`, `mcp__.*`). `AskUserQuestion` is a first-class tool in the toolset, so it should match like any other — but this is unverified for this specific built-in. **Before building anything:** register a trivial no-op PreToolUse hook matching `AskUserQuestion` that logs and allows, trigger a question, confirm the hook fires. If it does not fire, B is infeasible and the plan escalates to C (ask-time verifier) — stop and surface to the engineer.

### Task 1 — The hook script (`scripts/validate-ask-user-question.sh`)

- Reads the `AskUserQuestion` tool input from the hook payload (the `questions` array: each `question` text + `options[].label/description`).
- Detects whether the surfaced decision is **code-shaped** (mentions code/implementation/a file/a method/a fix — heuristic keyword + the presence of code-decision vocabulary).
- Checks for an **evidence marker**: a `path:line` pattern (e.g. `foo.rb:42`) or a fenced code block, in the question or any option.
- **Code-shaped AND no evidence marker → `deny`** with a corrective `permissionDecisionReason` naming the missing pieces (code excerpt ~10-15 lines, file:line, flow narrative).
- **Otherwise → allow** (non-code decisions — workflow, naming, scope in the abstract — are out of scope for the evidence requirement).
- Fail-open on anything it cannot confidently parse (a false deny that blocks a legitimate question is worse than a false allow — same principle as `validate-commit-message.sh`).
- Single-purpose, single-file, mirrors the existing `validate-*.sh` shape.

### Task 2 — Wire the hook in the tracked `settings.json`

- Add a PreToolUse matcher on `AskUserQuestion` pointing at the new script.
- Tracked `settings.json` only, on the working copy, via the PR — never the installed `~/.claude/settings.json`.

### Task 3 — Mechanism E: prose hardening (Failure 1)

- Extend `DECISION-SURFACING.md` (and/or `CLAUDE.md` § Work Through to the Pull Request) to name **code-shaped tactical decisions** explicitly as in-scope for "decide, let the PR review catch it" — the PR is the engineer's real review surface, so a wrong tactical call costs one review comment, while a synchronous ask he cannot answer costs a blocking round-trip.
- Record the spike's confirmed findings as the rationale: over-asking is a named/measured failure mode (Finding 1); user-answerability + EVPI + attributability-gap formalize "asking someone who cannot answer is worse than deciding" (Findings 2/3/5); the self-critique paradox explains why prose alone is structurally weak for judgmental rules (Finding 9) — which is why E is paired with B, never shipped alone.
- Note honestly (per the spike) that the "cheap PR-gate lowers the value of synchronous clarification" argument has no direct external confirmation and is a by-analogy extension of the existing Work-Through-to-the-PR rationale.

### Task 4 — Changelog + PR

- `CHANGELOG.md` entry under `## [Unreleased]`.
- One commit, feature branch, PR to `develop` — stops at open PR for engineer review (never auto-merged).

## Risks

- **Task 0 fails (hook does not match `AskUserQuestion`)** → B is dead; escalate to Mechanism C. This is why Task 0 is first and gated.
- **Heuristic evasion** (fake `file:line`) → accepted; B raises cost, does not guarantee. Documented, not hidden.
- **False-positive denials** blocking legitimate non-code questions → mitigated by the code-shaped gate + fail-open parsing.
- **Over-reach into Failure 1** → deliberately excluded; the hook does not judge tactical-vs-strategic.

## Out of scope

- Mechanism A (infeasible), Mechanism C (escalation only), Mechanism D (unverified, addresses only frequency).
- Any change to the built-in `AskUserQuestion` tool itself (not ours to change).
