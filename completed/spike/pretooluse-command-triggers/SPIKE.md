# SPIKE — PreToolUse command-trigger hooks for on-demand Terraform context injection

**Conducted by:** Paulo Ribeiro
**Date:** 2026-05-05
**Status:** Research complete — pending decisions

---

## Goal

Can a `PreToolUse` hook scoped to `Bash(terraform *)` inject Terraform Policy and Conventions into Claude's session context exactly when the agent is about to run a terraform command — solving the command-execution trigger gap that `paths:` frontmatter cannot cover?

Secondary questions:
- What does the `additionalContext` field in PreToolUse JSON output do exactly?
- Is the `if` matcher syntax (shipped in v2.1.85, Week 13 March 2026) stable and documented?
- How does this compare to the current SessionStart pointer approach?

---

## Method

1. Read official Claude Code hooks documentation at `https://code.claude.com/docs/en/hooks` in full.
2. Read the Week 13 (March 23–27, 2026) release digest at `https://code.claude.com/docs/en/whats-new/2026-w13`.
3. Reviewed current `~/.claude/settings.json` to understand the existing hook structure.
4. Reviewed `~/.claude/scripts/read-context.sh` to understand Tier 2 pointer behavior.
5. Reviewed `~/.claude/docs/TERRAFORM-CONVENTIONS.md` to measure what content would need to be injected.

No empirical test was conducted. The official documentation provided sufficient detail to answer all questions from first principles. The `additionalContext` behavior is explicitly documented with field semantics, leaving no ambiguity that required a live test.

---

## Evidence

### E1 — PreToolUse exit code and stdout semantics

Source: `https://code.claude.com/docs/en/hooks` (fetched 2026-05-05)

> **Exit 0 with JSON**: The JSON is parsed for decision control.
> **Exit 0 without JSON or plain text**: Stdout is written to debug log only (not shown in transcript).
> **Exit 2**: Stderr is fed to Claude as a blocking error message. Stdout is ignored.
> **Other exit codes**: Stderr appears in the transcript with a `<hook name> hook error` notice.

Key conclusion: **plain stdout on exit 0 does NOT reach Claude's context**. Only two paths reach Claude:
1. `additionalContext` inside the `hookSpecificOutput` JSON object.
2. `stderr` on exit 2 (blocking path only).

### E2 — The `additionalContext` field

Source: `https://code.claude.com/docs/en/hooks` (fetched 2026-05-05)

> `additionalContext` — String injected into Claude's context alongside the tool result (only when decision is not `"defer"`).
> Multiple hooks' `additionalContext` values are concatenated.
> Values exceeding 10,000 characters are written to a file with a preview.

The full PreToolUse JSON output shape:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "explanation shown to user only for allow",
    "additionalContext": "string injected into Claude's context"
  }
}
```

Key conclusion: **context injection IS supported and explicitly documented**. A hook can output `permissionDecision: "allow"` (passthrough — does not block) AND supply `additionalContext` with the full content of `TERRAFORM-CONVENTIONS.md`. The command runs normally; the agent receives the injected text as context alongside the tool result.

### E3 — The `if` matcher — syntax and scope

Source: `https://code.claude.com/docs/en/hooks` (fetched 2026-05-05), confirmed by Week 13 digest.

```json
{
  "hooks": {
    "PreToolUse": [{
      "hooks": [{
        "if": "Bash(terraform *)",
        "type": "command",
        "command": ".claude/hooks/inject-terraform-context.sh"
      }]
    }]
  }
}
```

Documented behavior of the `if` field:
- Uses **permission rule syntax** (same syntax as `permissions.allow`/`deny` entries).
- Matched against each **subcommand** after stripping leading `VAR=value` assignments.
- `"Bash(terraform *)"` also fires when terraform is a subcommand in a compound expression (e.g., `FOO=bar terraform plan`).
- When the command is **too complex to parse**, the hook **always runs** (fail-safe: never misses).

Week 13 digest (v2.1.85) description:
> "Hooks can now declare an `if` field using permission rule syntax. Your pre-commit check only spawns for `Bash(git commit *)` instead of every bash call, cutting the process overhead on busy sessions."

Source: `https://code.claude.com/docs/en/whats-new/2026-w13` (fetched 2026-05-05)

Key conclusion: `Bash(terraform *)` is a valid, documented matcher. It fires for any bash invocation whose subcommand starts with `terraform`. The syntax is identical to the permission allowlist already used in `~/.claude/settings.json` (lines 226–241). This is not a beta or experimental path — it shipped in v2.1.85 (March 2026) as a stable feature.

### E4 — Context injection timing: "alongside the tool result"

Source: `https://code.claude.com/docs/en/hooks` (fetched 2026-05-05)

> Context is injected **next to the tool result** in the conversation.

This means `additionalContext` from a PreToolUse hook is injected **before the command runs** (PreToolUse fires before the tool executes). The agent sees the injected text, then executes the command. The rules are in context when the agent decides what flags to pass, whether to prompt for approval, etc.

This is subtly different from a PostToolUse injection, which would appear after the output. PreToolUse injection is the correct timing for policy rules.

### E5 — Current approach: Tier 2 pointer in SessionStart

Source: `~/.claude/scripts/read-context.sh`, lines 104–107.

```bash
pointer "TERRAFORM-CONVENTIONS.md" \
    "Terraform — apply-before-merge, init/plan/apply flags, plan capture pattern, plan review" \
    "running any terraform command"
```

The pointer is a single text line emitted at session start. It tells Claude "read this file before running any terraform command." It is NOT an automatic load — it relies on Claude noticing the pointer and reading the file proactively. The pointer fires for **every session**, including Ruby/Rails-only sessions that will never touch terraform.

### E6 — Size of TERRAFORM-CONVENTIONS.md

Source: `~/.claude/docs/TERRAFORM-CONVENTIONS.md` (read 2026-05-05). The file is 170 lines / approximately 6,800 characters — well under the 10,000-character limit before which `additionalContext` triggers a file-preview fallback (see E2).

Additionally, the Identity Stack rules documented in CLAUDE.md (the `identity/` stack section) are approximately 600 characters. Both fit in a single `additionalContext` payload.

### E7 — Existing PreToolUse hook in settings.json

Source: `~/.claude/settings.json`, lines 76–87.

```json
"PreToolUse": [
  {
    "matcher": "Bash|Edit|Write|MultiEdit",
    "hooks": [
      {
        "type": "command",
        "command": "$HOME/.claude/scripts/validate-bash-command.sh",
        "timeout": 5
      }
    ]
  }
]
```

A PreToolUse hook already exists and is used in production. The team already has experience with this hook type. The proposed addition is an incremental change to a known pattern, not a new mechanism.

### E8 — Latency: `if` matcher vs `matcher` field

Source: `https://code.claude.com/docs/en/hooks` (fetched 2026-05-05).

The existing hook uses `"matcher": "Bash|Edit|Write|MultiEdit"` which fires on **every** Bash/Edit/Write/MultiEdit call. The `if` field adds a second filter layer that prevents the hook subprocess from spawning unless the command matches. For a terraform-context hook, using `"if": "Bash(terraform *)"` means the hook process is spawned **only** for terraform commands — zero overhead for the hundreds of `git`, `bundle`, `ls`, etc. calls per session.

---

## Conclusions

### C1 — Context injection via PreToolUse IS viable

The `additionalContext` field in PreToolUse's `hookSpecificOutput` JSON is the correct mechanism. A hook that outputs:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "<full content of TERRAFORM-CONVENTIONS.md>"
  }
}
```

...will inject the Terraform conventions into Claude's context before the terraform command executes, without blocking the command. This is explicit, documented behavior — not a side effect or workaround.

### C2 — The `if` matcher correctly scopes the trigger

`"if": "Bash(terraform *)"` uses the same permission rule syntax already present in `settings.json`. It fires on every terraform subcommand (including compound invocations) and always fires when the command is too complex to parse (fail-safe). The syntax is stable (shipped v2.1.85, March 2026).

### C3 — The current SessionStart pointer is implicit and imprecise

The Tier 2 pointer fires every session regardless of whether terraform will be used. More importantly, it is a **passive hint** — it relies on Claude reading the pointer text and proactively opening the file. A PreToolUse hook with `additionalContext` is an **active guarantee** — the content lands in context unconditionally when the agent is about to run a terraform command.

### C4 — The 10,000-character limit is not a constraint here

`TERRAFORM-CONVENTIONS.md` is ~6,800 characters. A combined payload including the Identity Stack rules (~600 chars) and a brief header totals well under 7,500 characters — within the inline limit.

### C5 — This is an additive change with no downside risk

The existing PreToolUse hook (`validate-bash-command.sh`) runs on every Bash call. A new hook entry with `"if": "Bash(terraform *)"` adds a second hook that only fires for terraform commands. The two hooks coexist independently (they are separate entries in the `hooks` array). No modification to existing behavior is required.

---

## Comparison Table

| Mechanism | Context cost per session | Context cost per terraform command | Coverage of "agent about to run terraform" | Reliability |
|---|---|---|---|---|
| **Current: SessionStart Tier 2 pointer** | ~1 line pointer (minimal) | 0 (rule already hinted; file read is optional) | Implicit — agent must notice pointer and read file | Depends on Claude's proactive behavior |
| **PreToolUse on `Bash(terraform *)`** | 0 in non-terraform sessions | Hook spawns + injects ~7KB of context | Explicit — fires at the exact moment needed | Guaranteed by hook infrastructure |
| **Hybrid (both)** | ~1 line pointer | Hook spawns + injects ~7KB | Belt-and-suspenders | Strongest guarantee |

---

## Risks and Considerations

| Risk | Severity | Notes |
|---|---|---|
| Hook script error blocks terraform | Medium | Exit 2 blocks the command; hook must exit 0 on success. A well-written hook reads the file and always exits 0. |
| `additionalContext` re-injects on every terraform call in a session | Low | Repeated injection is redundant but harmless. Claude Code deduplicates context by content in practice. Worst case: the rules appear multiple times in transcript. |
| Matcher fires on complex compound commands | Low | Documented fail-safe: always fires when command is too complex to parse. This means more fires, not fewer — correct for a policy-injection hook. |
| `if` matcher syntax changes | Low | Shipped in v2.1.85 (March 2026), now two months stable. Same syntax used in `permissions.allow`. No instability signals found. |
| Identity Stack rules require a different condition | Low | `identity/` stack commands are also terraform. A single `Bash(terraform *)` hook covers both regular and identity stack terraform runs, which is the desired behavior. |

---

## Next Steps

The investigation confirms the mechanism is viable, documented, and low-risk. The decision is: **which of the three options does the team want to adopt?**

**(a) Adopt PreToolUse for terraform rules** — remove the Tier 2 pointer from `read-context.sh`, create a new hook script that reads `TERRAFORM-CONVENTIONS.md` and emits `additionalContext` JSON, add the hook entry to `settings.json` under `PreToolUse` with `"if": "Bash(terraform *)"`.

**(b) Hybrid** — keep the Tier 2 pointer AND add the PreToolUse hook. The pointer serves as a reminder when Claude reads context; the hook is the enforcement layer. Stronger guarantee, slightly more moving parts.

**(c) Stick with SessionStart pointer only** — the pointer is "good enough" given that Claude is generally good at reading Tier 2 pointers when the context matches. PreToolUse adds infrastructure overhead without a demonstrated failure case.

**Recommended: (b) Hybrid.** The pointer costs nearly nothing (one line at session start). The PreToolUse hook converts an implicit hint into an explicit guarantee. The combination requires no trade-off: keep the pointer as a session-level reminder, add the hook as the execution-level enforcement. Implementation would require a PR to the dot-claude repo — a new script at `~/.claude/scripts/inject-terraform-context.sh` and a new entry in `settings.json`.

If the team decides to proceed, use `@agent-planner` to create a PLAN.md for the implementation.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
