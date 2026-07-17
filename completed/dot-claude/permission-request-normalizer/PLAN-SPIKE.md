# PLAN-SPIKE — Permission Request Normalizer

> Reference: `~/Projects/4Shark/dot-claude-plans/active/spike/command-form-redirect-hook/SPIKE.md` (prior research, read in full — its Finding C catalog, Finding D safety/form boundary, and Finding A5 maintenance-liability point are load-bearing here and are not re-derived). `/tmp/decision_matrix_session_stall_20260716_150000.html` (the reframe that identified `PermissionRequest` as the un-researched lever). `/tmp/interactive_report_community_command_redirect_20260716_143000.html` (community sweep).

## Objective

The chosen direction (already decided by the engineer, not re-opened here): a new `PermissionRequest` hook in dot-claude that normalizes a Bash command the same way `validate-bash-command.sh`'s existing "Ask-bypass detection" block already does (strip leading env-var assignments, the `env` wrapper, and the absolute path of the binary), and auto-approves the pending permission prompt when the normalized form is equivalent to something already on `permissions.allow` — so a session never freezes on a prompt for a command that is, in substance, already sanctioned. This document researches HOW to build it: the exact mechanism guarantees Anthropic documents, the design options for the auto-approve catalog, the shared-logic question against the existing normalizer in `validate-bash-command.sh`, and the shape of the PR that ships it.

## Scope

### In scope

- The `PermissionRequest` hook's documented input/output schema, precedence, and re-validation guarantees
- Whether a `PreToolUse` block (the existing `validate-bash-command.sh` `exit 2` shapes) can ever be silently bypassed by this new hook
- Design options for deciding "is the normalized form allow-list-equivalent" (parse `settings.json` live vs. hand-maintained mirror list)
- Adversarial cases where a normalization could over-approve
- The shared-logic question between the new hook and `validate-bash-command.sh`'s existing normalizer (per `NO-PREMATURE-DRY.md`)
- Execution shape: worktree/PR mechanics, how to test a `PermissionRequest` hook before merging, CLAUDE.md summary placement per the Documentation Loading Model

### Out of scope (explicitly, per the task)

- Re-litigating auto mode / `dontAsk` / `bypassPermissions` / sandbox — evaluated and rejected in the prior spike/decision-matrix research
- The Bash Single-Line Policy citation error surfaced by the community sweep — real, but a separate dot-claude PR and a separate decision. Noted once, not planned here. Per Anthropic maintainer bcherny on `anthropics/claude-code#11932`, 2026-04-07: "The original bug here — `*` in `Bash(...)` allow rules not matching across newlines — was fixed in early March 2026 (the wildcard regex now uses the dotAll flag)." Corroborated by the Claude Code changelog § 2.1.72: "Fixed several permission rule matching issues: wildcard rules not matching commands with heredocs, embedded newlines, or no arguments."
- Any change to `validate-bash-command.sh`'s existing `exit 2` blocks

## A. The mechanism

### A1. Confirmed schema (high confidence — single detailed fetch, see caveat in A2)

`PermissionRequest` fires "When a permission dialog appears" (hook lifecycle table, `permission-request-normalizer_doc_1.md`). Its output shape is **structurally different from `PreToolUse`'s** — a nested `decision` object, not a flat `permissionDecision` string:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "message": "npm is an approved package manager",
      "addPermissionRules": ["Bash(npm *)"]
    }
  }
}
```

Fields, quoted from `code.claude.com/docs/en/hooks` § "PermissionRequest decision control" (full quotes in `permission-request-normalizer_doc_1.md`):

| Field | Required | What it does |
|---|---|---|
| `behavior` | yes | `"allow"` or `"deny"` |
| `updatedInput` | no | Replaces the tool input before it runs. Only applies when `behavior` is `"allow"` |
| `addPermissionRules` | no | Array of permission rule strings (e.g. `"Bash(npm *)"`) added to the **session's** permission rules — "remembered for the rest of the session, so the user won't be prompted again for matching tool calls" |
| `message` | no | Shown to the user explaining the decision |

`hookEventName` must echo `"PermissionRequest"` — consistent with the general rule already stated in this repo's `~/.claude/CLAUDE.md` § Documentation Loading Model: "`hookSpecificOutput.hookEventName` must name the event that actually fired, or the harness discards the block" (that sentence is NOT in ADR-001 — grepped, zero matches for `hookEventName` there; ADR-001 does independently ground the 10,000-character output-cap half of this same constraint, see §D4).

### A2. MUST-ANSWER — is a `behavior: "allow"` re-checked against `permissions.deny`/`ask`? ANSWERED, with a confidence caveat

**Yes, but only when `updatedInput` is also supplied.** Quoted in full:

> "When `behavior` is `"allow"` and you provide `updatedInput`, Claude Code re-validates the updated input against your project's permission rules. If the updated input matches a deny rule, the tool call is rejected and the user sees the denial reason, not your hook's message. This safety check prevents hooks from accidentally circumventing security policies. **To avoid re-validation, omit `updatedInput` and only modify the tool call if it already matches an allow rule.**"

This directly resolves the task's MUST-ANSWER question. It also has a design implication the engineer can weigh: the docs describe omitting `updatedInput` — deciding `behavior: "allow"` on the ORIGINAL, unmodified command (env-prefix and all) — as the documented way to "avoid re-validation... only modify the tool call if it already matches an allow rule", which matches this hook's stated purpose (approve when the NORMALIZED form already matches an allow rule). Whether the hook uses this no-`updatedInput` path, or uses `updatedInput` to also canonicalize the command, is a decision left to §B3/the Technical Decisions table — not settled here.

**Confidence caveat** (Citation Discipline self-check, rule 5): two follow-up re-fetches of the same URL, asked to reconfirm the exact substring, both failed to reproduce it — one explicitly admitted page truncation, the other returned a bare "No". This is consistent with the fetch tool serving a different summarized slice of the page per query (documented instability, not a claim the page content itself changed). The quote above came from a single, internally consistent, detailed extraction (full field table + two matching JSON examples in the documented shape) and is independently corroborated by a real bug report (`anthropics/claude-code#19298`, see `permission-request-normalizer_doc_2.md`) showing the flat `PreToolUse`-shaped output silently failing on a `PermissionRequest` hook — consistent with a genuinely different, nested schema existing. Treated as high-but-not-certain confidence. **The engineer should view `code.claude.com/docs/en/hooks` § "PermissionRequest decision control" directly before this safety design is finalized in the PR.**

### A3. Does a `PreToolUse` block ever reach `PermissionRequest`? Answered by inference from two directly-quoted facts, not a single explicit sentence

No sentence stating "a `PreToolUse` block prevents `PermissionRequest` from firing" was found after five separate targeted queries against the hooks reference (`permission-request-normalizer_doc_1.md`). The conclusion is an inference from combining:

1. `PermissionRequest` fires only "When a permission dialog appears" (hooks reference, lifecycle table).
2. "A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed" (Configure permissions doc, quoted in full in the sibling spike's `command-form-redirect-hook_doc_1.md`).

A dialog is part of permission-rule evaluation; a call stopped BEFORE that evaluation cannot reach the point where a dialog — and therefore `PermissionRequest` — fires. This means: **`validate-bash-command.sh`'s existing `exit 2` blocks (`gh pr merge`, `terraform apply` without approval routing, `git reset --hard`, EC2 start/stop, DB install, release-branch creation, etc.) structurally cannot be silently laundered past by the new hook** — they never reach `PermissionRequest` at all. This is the same shape of guarantee the prior spike established empirically for `PreToolUse` redirects (Finding A3's terraform `-out` worked example) — here it is closer to definitional (the dialog literally cannot appear) rather than observed, but it rests on two independently quoted sentences, not on one.

**What remains genuinely open**: whether `validate-bash-command.sh`'s `emit_ask` (a `PreToolUse` hook returning `permissionDecision: "ask"`, not an `exit 2` block) also prevents `PermissionRequest` from ever being reachable by OUR hook for that same command, or whether it is exactly the case where the dialog DOES appear and our hook gets a chance to look at it. Reasoning (not directly quoted): an `ask` decision explicitly "prompts the user to confirm" (hooks reference, quoted in the prior spike), and a prompt IS a dialog — so this is the expected, intended path: `validate-bash-command.sh` forces a prompt for a dangerous raw form (e.g. env-prefixed `aws ec2 start-instances`), the dialog appears, `PermissionRequest` fires, and our hook then decides whether to auto-approve based on whether the NORMALIZED form matches `permissions.allow` — which for a genuinely dangerous command it will not (that command was never allow-listed to begin with; it is deliberately in the `ask`/block catalog). This reasoning is the crux of why the mechanism is safe by construction for THIS use case, but it has not been empirically observed (no test was run in this spike — see Open Questions).

### A4. `addPermissionRules` — scope and lifetime

"Rules added this way are remembered for the rest of the session, so the user won't be prompted again for matching tool calls" (quoted in `permission-request-normalizer_doc_1.md`). **Session-scoped, not persisted to `settings.json`.** This means `addPermissionRules` is a DIFFERENT mechanism from what the task describes — it teaches the CURRENT session, once, rather than deciding per-call whether an already-allow-listed equivalent exists. It is a candidate worth surfacing (Option in § B) but is not automatically the same thing as "auto-approve because the normalized form matches an existing allow entry" — using it would mean the FIRST occurrence of a given wrong-shape command in a session still prompts once, then self-heals for the rest of that session only (not across sessions, and not across the engineer's 10-20 parallel sessions — each session has its own rule set).

### A5. `async` / `asyncRewake` — unresolved for this event specifically

Both fields exist only in the generic "command hook fields" table, not scoped to one event. No sentence was found either confirming or excluding them for `PermissionRequest` specifically after a targeted query. A separate synthesized claim that "`PermissionRequest` does not support them... is a synchronous blocking event" could not be reconfirmed via direct quote and is DROPPED per Citation Discipline (quote-or-drop). **Not researched further**: whether the new hook could run a slower check (e.g. genuinely parsing `settings.json` and running a fuller matcher) without blocking the turn.

### A6. Minimum version — UNVERIFIED

A `WebSearch` result claims `PermissionRequest` was added in v2.0.45; this is an unverified search-summary claim (Citation Discipline rule 4 — not a directly fetched changelog line) and sustains nothing here. A direct fetch of the raw `CHANGELOG.md` searching for the literal string "PermissionRequest" found no matches across the entries the fetch tool covered (2.1.160–2.1.211) — consistent with an earlier introduction that was never revisited, but not a confirmation. Full detail in `permission-request-normalizer_doc_2.md`. **Recommended before shipping**: confirm the installed Claude Code version supports the event (e.g. via `/hooks` after registering it, or `claude --version` cross-referenced against `code.claude.com/docs/en/whats-new`).

### A7. Fail-open safety property (a genuine finding, not asked for but load-bearing)

A broken/malformed `PermissionRequest` hook does **not** silently auto-approve anything. Two documented failure modes, both safe:

- Exit code 2 → "Denies the permission" (exit-code table, `permission-request-normalizer_doc_1.md`)
- Any other non-zero exit / malformed output → "non-blocking error... Execution continues" (fail-open quote, same doc) — in context this means the call falls through to the dialog the hook was supposed to intercept, i.e. it still prompts.

Only `WorktreeCreate` is documented as failing closed among all hook events. This means a bug in the new hook's script degrades to "still prompts" or "denies", never to "silently runs something it should not have."

## B. The auto-approve catalog — design options (not decided here)

### B1. Adversarial framing — what could go wrong

The task asks to be adversarial: can `FOO=$(curl evil) terraform plan` normalize into something that auto-approves? Tracing it through the existing `validate-bash-command.sh` normalizer logic (`~/.claude/scripts/validate-bash-command.sh:518-539`, quoted in the sibling spike's Finding A5) — the loop strips a LEADING `[A-Za-z_]*=*` token repeatedly, then strips a leading absolute path. It does not evaluate or strip `$(...)` — a `$(...)` substring inside an env-var VALUE would survive into `normalized_command` if the value itself is not the leading token being stripped. For `FOO=$(curl evil) terraform plan`, the loop strips `FOO=$(curl` as a single whitespace-delimited "token" (since `$(curl evil)` contains an unescaped space, the shell-splitting inside the hook's own `read` would break it into `FOO=$(curl` then `evil)` then `terraform` then `plan` — the exact re-tokenization depends on how the hook parses `tool_input.command`, which is a single string, not pre-split shell arguments). **This is exactly the class of risk the task calls out** — a substitution embedded in a stripped-away segment could leave `normalized_command` looking like a clean, safe command. Whether that is actually dangerous depends on the `updatedInput` decision in §B3/§A2: if the hook never uses `updatedInput` (approve-as-typed only), the ORIGINAL command — `$(...)` intact — is what executes if approved, so the substitution would still run. If the hook instead used `updatedInput` to rewrite the command, the REWRITTEN (substitution-stripped) form would run instead. Either way, **whether the normalizer should refuse to auto-approve whenever the stripped prefix or ANY part of the command contains `$(` is a design option for the engineer, not decided here.** Note: the community sweep (`interactive_report_community_command_redirect_20260716_143000.html`) already found `$(...)` handling is a live, open, 32-reaction upstream issue (`#31373`) at the settings.json layer — "any command containing `$(...)` always triggers a manual permission approval dialog, regardless of allow rules" — which independently suggests a raw `$(...)`-bearing command may never even reach a clean "allow-list match" state in the first place, but this was not verified for the `PermissionRequest` path specifically in this spike.

### B2. How to decide "is the normalized form allow-list-equivalent" — two options, not decided

**Option 1 — parse `settings.json`'s `permissions.allow` array at hook-run time and apply the documented match rules** (prefix matching, `:*` suffix, process-wrapper stripping per `code.claude.com/docs/en/permissions` § "Bash — process wrappers", quoted in the sibling spike's `command-form-redirect-hook_doc_1.md`). Pro: single source of truth, no second list to maintain. Con: reimplementing the vendor's own matcher risks reproducing it incorrectly — the sibling spike already found one documented case where the built-in wildcard matcher itself did not behave as its own rules implied (`anthropics/claude-code#29616`, cited in `~/.claude/scripts/auto-approve-aws-readonly.sh:14-20`), meaning even Anthropic's own implementation has had bugs in this exact area; a hand-rolled reimplementation has no reason to be more reliable.

**Option 2 — hand-maintained mirror list inside the new hook**, matching the pattern `validate-bash-command.sh`'s "Ask-bypass detection" block already uses (Finding A5 of the sibling spike: normalize, then re-match against a hardcoded canonical list). Pro: proven pattern, already in production for the mirror-image use case (turning an improper allow into a prompt). Con: Finding A5's own stated liability applies symmetrically here — "two independent hand-edited lists nothing keeps in sync." A future addition to `permissions.allow` would NOT automatically also let its env-prefixed/wrapped form auto-approve unless the same PR also updates this new hook's mirror list.

Neither is decided here. The two options are not mutually exclusive with the process-wrapper stripping (`timeout`, `time`, `nice`, `nohup`, `stdbuf` — documented, quoted in the sibling spike) — that stripping is Claude Code's OWN behavior, applied automatically before ANY rule match, independent of what our hook does.

### B3. `updatedInput` usage — an option surfaced, not decided

Per §A2, the docs describe two paths: omit `updatedInput` (decide `behavior: "allow"` on the command as typed — the path the docs frame as avoiding re-validation), or supply `updatedInput` to also canonicalize the command (the path the docs say DOES get re-validated against `permissions.deny`). Using `updatedInput` reopens the re-validation area the sibling spike could not fully resolve for `PreToolUse`'s own bare-`allow`-with-`updatedInput` interaction (its own Finding A2), and this spike did not independently re-test the `PermissionRequest`-plus-`updatedInput` branch beyond the direct quote in §A2. **Whether the hook ever rewrites the command (vs. only approves it as typed) is an open design choice for the engineer** — see the Technical Decisions table.

### B4. Bash-only scoping

The `matcher` field on a hook registration "filters on tool name" (`permission-request-normalizer_doc_1.md`, and the general matcher-syntax doc in the sibling spike). Scoping the new hook's registration to `"matcher": "Bash"` (or an `if: "Bash(*)"` condition) is a straightforward option, mirroring how `redirect-terraform.sh` and `validate-bash-command.sh` are wired today. Not decided here whether other tools (e.g. a hypothetical future MCP tool prompt) should ever be in scope — out of scope per the task framing (this is about Bash commands).

## C. Shared-logic question — options, per `NO-PREMATURE-DRY.md`

The normalization logic (strip leading env-var assignments, strip `env` wrapper, strip absolute path of the binary) would exist in TWO places if the new hook duplicates `validate-bash-command.sh:518-539` inline: the existing ask-bypass block (turns improper-allow → prompt) and the new hook (turns improper-prompt → allow). Per `~/.claude/docs/NO-PREMATURE-DRY.md`: "Repeat code until it ACTUALLY hurts" — and per this repo's `~/.claude/CLAUDE.md` § No Premature DRY summary of that same doc: "the Rule of Three is the MINIMUM, not the trigger — 2 repetitions is too early." Two call sites is below even the stated floor.

**Options, not decided:**

1. **Duplicate the ~20-line normalization loop verbatim in the new hook.** Consistent with the doc's own worked example philosophy ("repeat everywhere... each method is independent... easy to modify one without affecting others"). Con: if the normalization logic itself has a bug (e.g. the `$(...)`-survival risk in §B1), fixing it requires remembering to fix it in two files.
2. **Extract a shared sourced helper** (e.g. `~/.claude/scripts/lib/normalize-bash-command.sh`, sourced by both `validate-bash-command.sh` and the new hook). Con: this is exactly the "wrong abstraction from too few examples" risk the doc warns against — at 2 call sites, the shape of what each script needs from normalization (a "would this match the ask-list" question vs. a "would this match the allow-list" question) has not yet had a chance to diverge or reveal a real shared contract.
3. **Something else the engineer proposes.**

`NO-PREMATURE-DRY.md` explicitly states "when in doubt, repeat" and reserves abstraction for "10+ exact repetitions" with "team consensus that abstraction would help" — at 2 sites, the doc's own decision tree points toward Option 1, but this is presented as an option, not a directive, per the task's instruction not to decide.

## D. Execution shape

### D1. PR mechanics (per § Configuration Changes Policy, already-standing rule, not a new decision)

This ships as a PR to `dot-claude` from a worktree: `git worktree add .claude/worktrees/<name> -b feature/<name> origin/develop` inside `~/Projects/4Shark/dot-claude/`, then `bash ~/.claude/scripts/setup-worktree.sh <path>` (a no-op for this repo per the allowlist, but run for consistency). NEVER edit the installed `~/.claude/settings.json` — `scripts/validate-installed-config-edit.sh` blocks it mechanically. All work happens on the tracked copy.

### D2. Change surface

- The new hook script (e.g. `~/.claude/scripts/normalize-permission-request.sh` — name not decided here)
- `settings.json` hook wiring under `hooks.PermissionRequest` (a NEW top-level key — confirmed via `grep -n "PermissionRequest" settings.json` returning zero matches; there is no existing `PermissionRequest` registration in this repo today, so this is a first-of-its-kind wiring point, not a modification of an existing block)
- A CLAUDE.md summary section (per § Documentation Loading Model: "A rule with no summary here does not reach the session" — a hook with no CLAUDE.md summary is invisible to the next session reasoning about why prompts stopped appearing for certain commands)
- `CHANGELOG.md` entry under `## [Unreleased]` (this repo is on a feature branch, not release/hotfix — per § Git Tag & Version Policy, new entries go under Unreleased, no dated section)

### D3. Testing before merge — options surfaced, not decided

No first-party "dry-run" or "would this be allowed" query exists for hooks (re-confirms the sibling spike's Finding B2, and `permission-request-normalizer_doc_1.md`'s dedicated search found none either). What IS available:

- **`/hooks`** — a read-only browser that "shows every hook event with a count of configured hooks... verify configuration, check which settings file a hook came from" (quoted in `permission-request-normalizer_doc_1.md`). Confirms the hook is REGISTERED and recognized, but does not simulate a call.
- **The installed `~/.claude/settings.local.json` is NOT an available staging option for an agent.** `~/.claude/CLAUDE.md` § Configuration Changes Policy states outright: "NEVER edit the installed `~/.claude/settings.json` or `~/.claude/settings.local.json`", and `scripts/validate-installed-config-edit.sh` (PreToolUse on Edit/Write/MultiEdit) mechanically blocks any agent write to either installed file — so an agent cannot perform this staging step regardless of intent. If the engineer judges a personal, pre-merge local registration to be a useful test step, it would have to be **the engineer's own manual edit** to their installed `settings.local.json` (git-ignored, personal), never an agent-performed one; this is a possible engineer-side testing option, not an agent-executable step in this plan.
- **The fail-open safety property (§A7)** means a testing mistake (bad JSON, a crashing script) degrades to "still prompts" or "denies" — never to an unintended silent allow — which lowers the risk of testing, whichever staging approach is used.
- **A manual empirical test of the A3 open question** (does `validate-bash-command.sh`'s `emit_ask` decision actually result in a `PermissionRequest`-eligible dialog our hook can intercept, for a command that should stay blocked): not performed by this spike; proposed as a pre-merge verification step — register the new hook with a rule that ALWAYS logs (not necessarily approves) every `PermissionRequest` payload it receives, then trigger a known `emit_ask` case (e.g. `git tag` — the sibling spike's catalog item confirms this is on the ask-list) and confirm the payload does arrive.

### D4. Hook-authoring constraints (already-standing, re-confirmed here)

Hook output is capped at 10,000 characters — this half of the constraint IS grounded in `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md` (a normalize-and-decide hook's output is a single short JSON object, well under this — not a concern for THIS hook's own output, but worth noting if `message`/`additionalContext` fields are used verbosely). `hookSpecificOutput.hookEventName` must echo the event that actually fired (`"PermissionRequest"`, confirmed in every worked example in §A1) — this half is grounded in `~/.claude/CLAUDE.md` § Documentation Loading Model, not in ADR-001 (see the correction in §A1).

## Technical decisions to be made (NOT decided here)

| Decision point | Options | Trade-off summary | Engineer to choose |
|---|---|---|---|
| Matcher strategy (§B2) | (1) Parse `settings.json` live (2) Hand-maintained mirror list | Live parse = single source of truth but reimplements a matcher with known upstream bugs (`#29616`). Mirror list = proven pattern but creates a second hand-edited list (Finding A5 liability) | □ |
| `$(...)` handling (§B1) | (a) Refuse to auto-approve whenever the ORIGINAL (or stripped-away) command contains `$(` (b) No special handling, rely on Claude Code's own upstream `$(...)`-always-prompts behavior (`#31373`, unverified for `PermissionRequest`) | (a) is a defensive, testable rule; (b) relies on unverified upstream behavior at this specific event | □ |
| `updatedInput` usage (§B3) | (a) Never use it — approve-as-typed only (b) Use it to also canonicalize the command | (a) sidesteps the re-validation question entirely, matches the documented "avoid re-validation" pattern; (b) reopens an area the sibling spike could not resolve for PreToolUse and this spike did not fully re-test for PermissionRequest | □ |
| Shared normalization logic (§C) | (1) Duplicate in the new hook (2) Extract a shared sourced helper (3) Other | `NO-PREMATURE-DRY.md`'s own decision tree points toward (1) at 2 call sites, but not decided here | □ |
| `addPermissionRules` usage (§A4) | (a) Never use it — every session re-decides per call via the normalizer (b) Use it as an ADDITIONAL mechanism so a wrong-shape command self-heals within a session after the first auto-approve | (a) is simpler, stateless per-call; (b) reduces hook invocations for repeated commands within one session but adds session-mutable state to reason about | □ |
| Hook script name and location (§D2) | Not researched — any name consistent with the `redirect-*.sh` / `validate-*.sh` naming convention already in `~/.claude/scripts/` | — | □ |
| Testing approach before merge (§D3) | `/hooks` registration check vs. an engineer-performed manual `settings.local.json` staging edit (agent cannot perform this) vs. other | Neither is a true dry-run since none exists; the `settings.local.json` path is engineer-only, not agent-executable | □ |

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|---|---|---|
| Re-validation confidence caveat (§A2) is based on a single fetch that could not be reproduced on self-check | The entire safety argument for "approve without `updatedInput` = safe" rests on one quote | Engineer views the official doc page directly before finalizing; empirical test proposed in §D3 |
| `$(...)` survives normalization in the ORIGINAL command that actually executes (§B1) | A malicious or accidental substitution could execute if the normalized (substitution-stripped) form happens to match an allow entry | Design decision in the table above — refuse on any `$(` presence |
| Two-list drift if Option 2 (§B2) is chosen | A future `permissions.allow` addition doesn't automatically get its wrong-shape forms auto-approved, or worse, a REMOVAL from `permissions.allow` doesn't get mirrored, meaning the new hook keeps auto-approving something that was deliberately un-allow-listed | Same liability already documented and accepted for `validate-bash-command.sh`'s existing mirror list (Finding A5) — no new mitigation invented here, engineer decides whether the precedent is acceptable twice |
| Minimum version unverified (§A6) | If the installed Claude Code version predates `PermissionRequest` support, the hook silently never fires (fail-open, per §A7 — not a security risk, but the mechanism simply does nothing and the stall problem persists undiagnosed) | Confirm version before merge; the `/hooks` browser (§D3) is the cheapest verification |
| `A3`'s `emit_ask` reachability is inferred, not empirically confirmed | If wrong, the whole mechanism could either (a) never see `ask`-routed commands at all (mechanism does nothing for its main target) or (b) something unexpected happens that was not modeled | Empirical pre-merge test proposed in §D3 |

## Open questions for the engineer

- Does the engineer want the empirical pre-merge test in §D3 run before this plan is composed into a `PLAN.md`, or is the documented (if imperfectly self-checked) evidence in §A2/§A3 sufficient to proceed to composition and test during implementation instead?
- Which matcher strategy (§B2) — live `settings.json` parse or a hand-maintained mirror list?
- Should the hook refuse to auto-approve on any `$(` presence (§B1), and if so, in the ORIGINAL command, the stripped-away segments, or both?
- Should `updatedInput` be used at all (§B3), or is approve-as-typed the whole scope of this hook?
- Shared-logic choice (§C): duplicate, extract, or other?
- Is `addPermissionRules` (§A4) worth using as a secondary, session-scoped self-healing mechanism alongside the per-call normalizer, or out of scope for this PR?
- Is a manual, engineer-performed `settings.local.json` staging test (§D3) worth doing before merge, given it cannot be delegated to the agent?

## Sources

- `~/Projects/4Shark/dot-claude-plans/active/spike/command-form-redirect-hook/SPIKE.md` — prior research, read in full; Findings A1, A3, A5, C, D directly load-bearing
- `~/Projects/4Shark/dot-claude-plans/active/spike/command-form-redirect-hook/command-form-redirect-hook_doc_1.md` — Configure permissions doc excerpts (deny/ask/allow precedence, hook-decision-doesn't-bypass-rules quote, process-wrapper stripping)
- `~/Projects/4Shark/dot-claude-plans/active/spike/command-form-redirect-hook/command-form-redirect-hook_doc_2.md` — Hooks reference excerpts (schema, 10,000-char cap, parallel execution)
- `/tmp/decision_matrix_session_stall_20260716_150000.html` — the reframe identifying `PermissionRequest` as the un-researched lever
- `/tmp/interactive_report_community_command_redirect_20260716_143000.html` — community sweep (`$(...)` upstream issue `#31373`, env-prefix issue `#51057`, RTK precedent, the `#11932` fix-status correction cited in this document's Out-of-scope section)
- `~/.claude/scripts/validate-bash-command.sh:502-539` — the existing "Ask-bypass detection" normalizer (the mirror-image mechanism, quoted in full in the sibling spike's Finding A5)
- `~/.claude/scripts/redirect-terraform.sh:1-40` — existing `updatedInput`-based redirect precedent and its header rationale
- `~/.claude/docs/NO-PREMATURE-DRY.md` — read in full, § C
- `~/.claude/CLAUDE.md` § No Premature DRY — summary quote used in § C ("the Rule of Three is the MINIMUM, not the trigger")
- `~/.claude/CLAUDE.md` § Documentation Loading Model — summary quote used in §A1/§D4 (`hookEventName` requirement)
- `~/.claude/docs/adr/ADR-001-rules-loading-mechanism.md` — read in full; grounds the 10,000-character output-cap half of §D4 only
- `~/.claude/CLAUDE.md` § Configuration Changes Policy — grounds §D3's correction on `settings.local.json`
- See auxiliary: `permission-request-normalizer_doc_1.md` — full `PermissionRequest` hooks-reference excerpts (schema, re-validation, lifecycle, fail-open behavior, `/hooks` browser, `async`/`asyncRewake` non-resolution)
- See auxiliary: `permission-request-normalizer_doc_2.md` — version-history research (UNVERIFIED tag) and the `#19298` schema-mismatch bug report
- [Configure permissions — Claude Code Docs](https://code.claude.com/docs/en/permissions)
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks), § "PermissionRequest decision control", § "Hook lifecycle", § "Debugging and testing hooks"
- [anthropics/claude-code#19298](https://github.com/anthropics/claude-code/issues/19298) — closed, not planned; schema-mismatch evidence
- [anthropics/claude-code#31373](https://github.com/anthropics/claude-code/issues/31373) — OPEN, `$(...)` always triggers a prompt regardless of allow rules (cited via the community sweep aux file)
- [anthropics/claude-code#51057](https://github.com/anthropics/claude-code/issues/51057) — closed not planned, env-prefix bypass confirmed still present after 2.1.72 (cited via the community sweep aux file)
- [anthropics/claude-code#29616](https://github.com/anthropics/claude-code/issues/29616) — cited in `~/.claude/scripts/auto-approve-aws-readonly.sh:14-20`, the built-in wildcard matcher's own documented bug
- [anthropics/claude-code#11932](https://github.com/anthropics/claude-code/issues/11932) — maintainer bcherny comment, 2026-04-07, cited in this document's Out-of-scope section (fix-status correction only, not planned further here)
