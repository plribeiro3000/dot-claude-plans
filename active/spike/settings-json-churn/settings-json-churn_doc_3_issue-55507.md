# Auxiliary — GitHub issue anthropics/claude-code#55507 (fetched)

Source: https://github.com/anthropics/claude-code/issues/55507
Title: "[BUG] #55507" (permission settings problems)
Reporter: sigma8labs, opened 2026-05-02
Status: Closed as not planned
Labels: `area:permissions`, `bug`, `platform:macos`, `stale`

## Problem 1 — settings block replacement, not merge

Setting `permissions.defaultMode: "bypassPermissions"` at the user level (`~/.claude/settings.json`) is silently ignored if ANY higher-precedence settings file (project `.claude/settings.json` or `.claude/settings.local.json`) contains a `permissions` block — even one that only defines `permissions.allow`.

Expected (per reporter): per-key merge so `defaultMode` set anywhere applies unless explicitly overridden.
Actual (per reporter): the entire `permissions` block from the highest-precedence file wins, silently dropping `defaultMode` from lower-precedence files.

## Problem 2 — settings.local.json auto-rewriter strips defaultMode (verbatim quote)

> the rewriter dropped a previously-set `permissions.defaultMode: "bypassPermissions"` field. Adding it back manually fixed it temporarily but it was at risk of being stripped again on the next auto-write.

Keys affected: `defaultMode` removed/not preserved during auto-writes when the engineer approves an "always allow" prompt (which appends to `permissions.allow`); other non-`allow` keys are not guaranteed to be preserved either.

## Problem 3 — running sessions cannot pick up settings changes

Settings changes only apply to NEW sessions; no in-session command to elevate to `bypassPermissions` mode existed at the time of the report.

## Suggested fixes (from the reporter)

1. Per-key merge for the `permissions` block (`defaultMode` + `allow` merge independently)
2. Auto-rewriter must preserve `defaultMode` and other non-`allow` keys
3. In-session `/permissions` mutation command
4. Optional: visible warning when higher-precedence blocks override lower-precedence settings

## Anthropic acknowledgment status

Closed as "not planned", labeled `stale`. No maintainer/staff response documented.

## Relevance to this spike

Confirms, from a second independent report, that Claude Code's settings auto-rewriter does a partial/selective write (add to `allow`) that can silently drop unrelated keys — the same class of defect as issue #62486, this time on `settings.local.json` rather than the tracked user `settings.json`. Reinforces that Claude Code's own settings-write path is not a full round-trip serialize, which is the mechanical root of the churn this spike investigates.
