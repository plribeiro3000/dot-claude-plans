# SPIKE — Claude Code integrated terminal: full history preservation vs. disabling

- **Date**: 2026-07-20
- **Status**: Closed
- **Time-box**: ~30 min
- **Author**: main session (research delegated to `claude-code-guide` agent + direct doc verification)

## Question

When running commands in the **integrated terminal of the Claude Code desktop app**, only the last ~100 lines of scrollback are retained/visible. The engineer needs the **full history of a terminal tab, from the start of the session, with nothing lost**.

Two sub-questions:

1. Can the full terminal history be preserved (from the beginning of the tab)?
2. If not, is there a way to disable the integrated terminal entirely, so it stops being used via Claude Code?

## Verdict (short)

| Sub-question | Answer |
|---|---|
| Preserve full scrollback **in the app UI** | **No** — the scrollback is capped and there is no setting/env var to lift it. |
| Preserve the full execution history **as data** | **Yes, partially** — the full session transcript is written to disk as JSONL. |
| **Disable** the integrated terminal | **No** — no documented setting, permission, policy key, or env var exists. |

Neither literal option is fully available. The practical resolution (below) is a **workflow** change that solves the actual underlying need — *never lose execution history* — better than either.

## Findings

### F1 — The integrated terminal exists, but its scrollback limit is undocumented

The desktop app ships a built-in terminal pane (Ctrl+`, or the Views menu), local sessions only. The official docs describe *how to open it* but say **nothing** about a scrollback/history/buffer limit or any way to configure it.

- Source: [Desktop Quickstart](https://code.claude.com/docs/en/desktop-quickstart) — documents the terminal pane; no limit mentioned.
- Source: [Settings](https://code.claude.com/docs/en/settings) — verified directly this session. No `disableTerminal`, `terminalEnabled`, or any terminal-scrollback key. Verbatim result of the check: *"there is no mention of any setting, key, permission, or environment variable to disable, hide, or turn off the integrated terminal"* and *"The documentation does not document ... Terminal scrollback/history/buffer size limits."*

### F2 — The scrollback cap is a known, reported limitation (not independently issue-verified)

Multiple GitHub issues on `anthropics/claude-code` report the scrollback being truncated / wiped in long sessions, tracing it to the alternate-screen-buffer / Ink render loop clearing the terminal. A cap in the ~250-line range was reported.

> **Caveat**: the specific issue numbers came from a research subagent and were **not** independently opened and confirmed this session. Treat the *existence and shape* of the limitation as confirmed (it matches the engineer's first-hand experience and the docs' silence), but treat any exact issue number / exact line count as **unverified**.

### F3 — The full history survives on disk as JSONL

The complete session transcript is persisted at `~/.claude/projects/<project>/<session_id>.jsonl`, independent of what the UI scrollback shows. This is the backend store, not a browsable "terminal history" view — recovering output from it means reading/parsing the file, not scrolling the pane.

### F4 — The terminal cannot be disabled via configuration

No `settings.json` key, no `permissions` rule, no managed-settings/policy key, no environment variable turns the terminal off. It is a built-in UI component; the only "disable" is behavioral — don't open the pane.

## The real problem, and why option 2 is the wrong frame

The stated need is *"não posso perder histórico de execução em nenhum momento"* — never lose execution history. That is an **output-preservation** requirement, not a terminal requirement. 4Shark already has a rule for exactly this:

- **§ Output Policy → Command Safety, Rule 5** (`~/.claude/CLAUDE.md`): never truncate a work command's output to fit context; **save the FULL output to a file, then read the file** — `command > /tmp/out.log 2>&1` (or `2>&1 | tee /tmp/out.log`). The harness also auto-persists oversized tool output to a Read-able file.

When commands run through Claude's **Bash tool**, this is already the standing convention and history is not lost. The scrollback cap only bites when the engineer **types commands manually into the integrated terminal pane** — a surface Rule 5 doesn't automatically cover because Claude isn't the one running the command.

So "block the terminal" is trying to remove a surface, when the fix is to route command execution through a surface that already preserves output.

## Recommendation

**Do not pursue disabling the terminal (not possible) and do not wait on full-scrollback support (not available).** Instead, adopt the redirect-to-file workflow for anything whose output must be kept:

1. **Preferred** — run the command through Claude's Bash tool (Rule 5 applies: full output → `/tmp` file → Read). Nothing is lost regardless of scrollback.
2. **When typing manually in the integrated terminal pane** — redirect output to a timestamped file and open/read that file instead of relying on scrollback:
   `<command> > /tmp/<name>_$(date +%Y%m%d_%H%M%S).log 2>&1`
   (see the file-naming convention in § Output Policy).
3. **Recovering a past session's output** — read the on-disk transcript at `~/.claude/projects/<project>/<session_id>.jsonl` (F3).

If a hard block on the integrated terminal is still wanted as a team policy, it is **not achievable through Claude Code configuration today** — it would have to be a convention the team agrees to, or a feature request filed upstream. That is a decision for the engineer, not something this spike can implement.

## Open items / gaps

- Exact scrollback line count and the exact upstream issue(s) are **unverified** (F2). If the precise number matters, the issues on `anthropics/claude-code` should be opened and read directly.
- No upstream feature request for "export terminal tab history" or "disable terminal" was confirmed to exist; filing one is an option if the team wants either capability supported.

## Sources

- [Claude Code Desktop Quickstart](https://code.claude.com/docs/en/desktop-quickstart)
- [Claude Code Settings](https://code.claude.com/docs/en/settings) (verified directly, 2026-07-20)
- 4Shark `~/.claude/CLAUDE.md` § Output Policy / § Command Safety Policy (Rule 5, output preservation)
