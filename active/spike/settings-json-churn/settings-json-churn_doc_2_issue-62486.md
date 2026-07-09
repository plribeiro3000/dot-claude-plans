# Auxiliary — GitHub issue anthropics/claude-code#62486 (fetched)

Source: https://github.com/anthropics/claude-code/issues/62486
Title: "settings.json partial rewrite strips statusLine, enabledPlugins, hooks mid-session"
Reporter: @Jwd-gity, opened 2026-05-26
Status: Closed as not planned
Labels: `area:core`, `bug`, `platform:linux`, `platform:wsl`, `stale`

## Exact problem description (verbatim quote)

> Claude Code periodically rewrites `~/.claude/settings.json` during a session (not only at startup), stripping fields it didn't explicitly modify — specifically `statusLine`, `enabledPlugins`, `hooks`, and other user-configured fields. This causes the statusline to disappear, hooks to stop firing, and plugins to become disabled mid-session without any user action.

## Stripped fields (explicit list from the issue)

- `statusLine`
- `enabledPlugins`
- `hooks`
- other user-configured fields

## When it occurs (verbatim quote, reproduction steps)

> 3. Use the session normally (interact with tools, change settings via `/config`, etc.)
> 4. At some point during the session, the statusline disappears and hooks stop firing

The exact trigger (which specific action fires the rewrite) is not pinned down further in the issue.

## Root cause as stated by the reporter (verbatim quote)

> The settings write path appears to serialize only the schema fields relevant to the current operation, rather than round-tripping the full settings object.

## Community workaround (verbatim quote)

> Requires a background daemon to monitor and restore `settings.json` every 3 seconds

A "SessionStart guard hook" is referenced as able to restore stripped fields from `settings.local.json`.

## Anthropic acknowledgment status

No maintainer/staff comment is present in the fetched content. Closed as "not planned"; labeled `stale`. No documented setting, flag, or environment variable exists to disable the auto-rewrite behavior.

## Relevance to this spike

This is the closest documented match to the 4Shark-observed churn: a partial/serialize-only write path that does not round-trip the full settings object, causing fields the app doesn't "own" for a given operation to be dropped or reset. It corroborates the ground-truth observation that the desktop app rewrites `~/.claude/settings.json` unprompted, mid-session, not only at startup — but it does NOT by itself confirm reordering or re-injection of personal UI prefs (theme/notification toggles) into the tracked file; that specific shape was not found as a standalone reported issue (see SPIKE.md § "What remains uncertain").
