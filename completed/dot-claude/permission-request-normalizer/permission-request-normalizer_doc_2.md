<!-- Fetched excerpts — version history and the schema-mismatch bug report —
     retrieved 2026-07-16. Two sources: raw CHANGELOG.md fetch (inconclusive)
     and a WebSearch summary (UNVERIFIED per Citation Discipline rule 4) plus
     a corroborating GitHub issue (fetched directly, quoted). -->

# Version history and a real-world schema-mismatch report

## Minimum version claim — UNVERIFIED

A `WebSearch` query ("Claude Code changelog PermissionRequest hook event added version") returned a search-result summary stating:

> "The PermissionRequest hook was added in v2.0.45, with PermissionDecision being exposed to hooks, including ask."

This is a **search-result summary, not a directly fetched and quoted changelog line** — per Citation Discipline rule 4, it carries the UNVERIFIED tag and sustains no candidate or decision in the main `PLAN-SPIKE.md`.

An attempt to independently confirm by fetching `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` and searching for the literal string "PermissionRequest" returned:

> "I searched the entire changelog text for lines containing 'PermissionRequest' and found no matches. The changelog does not reference 'PermissionRequest' in any version entry from 2.1.211 through 2.1.160."

This does not disprove the v2.0.45 claim — it only confirms the event is not mentioned by name in the most recent ~50 changelog entries the fetch tool covered (2.1.160–2.1.211), consistent with the event having shipped much earlier (2.0.x) and simply not been touched again since. **The exact introduction version remains unconfirmed.** Recommended before relying on it: `claude --version` on the machine running the hook, or checking `code.claude.com/docs/en/whats-new` directly, or simply registering the hook and observing whether `/hooks` lists it as recognized (a hook wired to an unsupported event name would presumably show 0 matches or be silently ignored — this itself was not tested).

## A real bug report that indirectly confirms the CORRECT output schema

`anthropics/claude-code#19298` — "[Bug] PermissionRequest hook cannot deny permissions - PermissionRequest hook decision ignored". **Closed as not planned.**

Quoted from the issue body (the reporter's own words, describing their reproduction):

> "Created a hook script at `~/.claude/hooks/permission-timeout.sh` returning `{"hookSpecificOutput":{"permissionDecision":"deny"}}`, but the interactive prompt still appeared when running commands like `mkdir /tmp/test`."

> "Multiple Formats Tested (All Ignored) — `{"hookSpecificOutput":{"permissionDecision":"deny"}}`; `{"decision":"deny"}`; `{"deny":true}`; Plain text `deny`; Exit code 2"

**Significance**: every format the reporter tried used the **`PreToolUse` output shape** (`hookSpecificOutput.permissionDecision` — a flat string) or ad-hoc shapes, never the `hookSpecificOutput.decision.behavior` **nested-object** shape documented in `permission-request-normalizer_doc_1.md` § "PermissionRequest decision control". This is indirect, corroborating evidence (not a direct confirmation — no maintainer comment resolving the issue was found in the fetched content) that `PermissionRequest`'s output schema is genuinely a DIFFERENT, nested shape from `PreToolUse`'s, and that using the `PreToolUse` shape on a `PermissionRequest` hook is a documented-in-the-wild failure mode (the dialog keeps appearing, i.e. fails safe/prompts — consistent with the fail-open behavior in `doc_1`).

The issue's "Expected Behavior" section also contains an unverified attribution the reporter makes to "documentation and DeepWiki" (DeepWiki is a third-party AI-generated wiki, not Anthropic):

> "PermissionRequest hooks run 'after initial rule-based filtering and wildcard matching, but before an interactive permission prompt is displayed'"

This phrase is the REPORTER's paraphrase of what they read elsewhere, not a quote Claude Code's own docs were shown to contain in this spike's fetches — it is **consistent** with the lifecycle-table ordering already established directly from the official docs (`doc_1.md`), but is not independently cited as an Anthropic statement here. Presented for completeness only; the ordering conclusion in the main `PLAN-SPIKE.md` rests on the two directly-quoted official sentences, not on this issue.

**Issue status**: Closed, "not planned". No text found in the fetched content explaining WHY it was closed this way (e.g., "not a bug, wrong schema used" vs "won't fix"). Not resolved by this spike.
