# SPIKE — Bash allow-list entries not auto-approving local script invocations

**Status:** CLOSED — root cause confirmed, fix shipped in [dot-claude#424](https://github.com/4shark/dot-claude/pull/424) (merged 2026-07-16).

## Question

Every invocation of a local skill script fell through to the approval prompt, even though `permissions.allow` carried an entry for exactly that path. Reported repro:

```
bash $HOME/.claude/skills/apps/scripts/apps-services.sh --project app --environment atento-001
```

The opening hypothesis was that `$HOME` and `~` are stored literally in a rule while the command arrives canonicalized, so neither form matches — which would mean nearly all 228 allow entries were dead.

## Answer

**The path form is not the variable. The argument is.** `$HOME` stops matching its allow-list entry the moment any argument follows; `~` matches in every case.

| Command | Prompted? |
|---|---|
| `cksum /etc/hosts` (control — in no allow list) | yes |
| `bash $HOME/.claude/scripts/check-plans-location.sh` | no |
| `bash $HOME/.claude/scripts/check-plans-location.sh --foo bar` | **yes** |
| `bash ~/.claude/scripts/check-plans-location.sh --foo bar` | no |

Mechanism: the `$HOME` form matches only when the command string is byte-identical to the rule's prefix — it matches by exact equality and the `:*` wildcard is never exercised. Add any argument and the wildcard has to work, and it does not. The `~` form matches both ways.

The hypothesis was right in direction, wrong in scope: 27 entries were dead (the `$HOME` ones), and their 27 `~` twins always worked. No rewrite of the allow list was needed.

**Why it survived so long:** the failure is intermittent. The bare form works, so the habit is rewarded often enough to persist, and the paired `$HOME` entries signalled that `$HOME` was a supported form. Nothing in the skill docs taught it — `apps/SKILL.md` uses `~` in all six examples. The agent drifted to `$HOME` on its own.

Measured 2026-07-16 on Claude Code v2.1.203, macOS, isolated one variable at a time against a live control.

## Second finding — `updatedInput` IS re-evaluated against the allow list

A `PreToolUse` hook that rewrites a command via `updatedInput` and emits **no** `permissionDecision` has its REWRITTEN command matched against the allow list, not the original.

This was previously unknown in this repo. `redirect-terraform.sh`'s own header hedged it ("even if the harness re-validates the rewritten input") and neither existing redirect hook proves it — both emit `permissionDecision: "allow"` alongside `updatedInput`, so neither exercises the bare-`updatedInput` path.

Verified with a throwaway hook loaded via `claude --settings <file>` (never installed into `~/.claude`), with two controls: the tilde form auto-approving inside the test session (proving `--settings` merges rather than replaces, so the allow list was live) and a hook-side log proving the hook fired. `settings.local.json` was confirmed untouched, ruling out a "Sempre permitir" entry from the earlier repro.

This fact is reusable beyond this case — any future hook can rewrite a command and let the normal permission flow judge the result.

## Not in the community's record

No issue describes this shape (`Bash(bash <path>:*)` matching a bare command and failing once arguments follow). Nearest neighbours, all a different problem:

- [#18160](https://github.com/anthropics/claude-code/issues/18160) — OPEN, same class, reporter hypothesises tilde-expansion timing. No maintainer reply.
- [#15421](https://github.com/anthropics/claude-code/issues/15421) — CLOSED as duplicate. `Bash(mkdir:*)` not matching.
- [#20254](https://github.com/anthropics/claude-code/issues/20254) — CLOSED not-planned. Docs-only, about bypassing a `curl` rule.
- [#17619](https://github.com/anthropics/claude-code/issues/17619) — CLOSED. Docs contradiction between `settings.md` and `iam.md`.

The table above is a ready repro if an issue is ever opened upstream.

## Shipped

- 27 dead `$HOME` allow entries removed from `settings.json`
- `integration-debug/SKILL.md` and `docs/AWS-MFA.md` corrected — both taught the `$HOME` form, and the skill asserted it was "the form the allowlist matches against"
- Rule added to `CLAUDE.md` § Command Safety Policy, next to its sibling allow-list-matching rule

## Open follow-ups

1. ~~**The rewrite hook**~~ — DONE. `scripts/redirect-home-path.sh`, shipped in [dot-claude#425](https://github.com/4shark/dot-claude/pull/425). Rewrites any unquoted `$HOME/` to `~/` via `updatedInput`, emitting NO `permissionDecision` (the two existing redirect hooks' `allow` would auto-approve an arbitrary command here — theirs is safe only because their rewrite target is read-only by construction). Defers on quotes (correctness: `~` does not expand there), compound commands, and env-var prefixes. The two "open design points" recorded earlier — rewrite scope and the script name — were never the engineer's to decide: the rewrite is identity-preserving so the broad scope is free, and `redirect-*` is the established local prefix for an `updatedInput` rewrite. Surfacing them as questions was over-asking, the inverse of the ASK-DONT-DECIDE failure.
2. ~~**`Bash($HOME/.rvm/wrappers/*:*)` entries**~~ — DONE, shipped in [dot-claude#427](https://github.com/4shark/dot-claude/pull/427). The earlier note that "the new hook does NOT cover these" was wrong: `redirect-home-path.sh` rewrites any unquoted `$HOME/`, which includes these, verified against the live hook (`$HOME/.rvm/wrappers/ruby-3.2.2@app/bundle exec rspec` → `~/.rvm/...`). They were also worse than the 27: their pattern carries a `*` mid-string, so no command can ever be byte-equal to it — they had no exact-match path to ride on and **never matched anything, in any form**. All 11 removed; the allow list now carries zero `$HOME` entries.

## Closed as WONT-FIX — `validate-bash-command.sh` false positive on a quoted wrapper path

Found while probing the hooks. The Ruby-wrapper guard (`validate-bash-command.sh:242-243`) blocks when BOTH a leading `VAR=` assignment is present AND a version-manager wrapper path appears anywhere in the command. It fired on `h=/tmp/x.sh; printf '{"command":"$HOME/.rvm/wrappers/r@g/bundle exec rspec"}' | bash "$h"` — where `h=` is a local variable of a compound command (not an env prefix) and the wrapper path is data inside a JSON string (not a program).

**The obvious fix is wrong, and this is the reason to record it.** The script already computes `command_without_quotes` (line 154) and uses it for the compound-operator guard; applying it at line 243 looks like the natural fix. Measured against the real shapes:

| Command | Today | With the strip applied |
|---|---|---|
| `BUNDLE_GEMFILE=x ~/.rvm/wrappers/r@g/bundle exec rspec` | blocks | blocks |
| `BUNDLE_GEMFILE=x "$HOME/.rvm/wrappers/r@g/bundle" exec rspec` | blocks | **leaks** |
| `RAILS_MASTER_KEY=$(cat master.key) ~/.rvm/wrappers/r@g/bundle exec rspec` | blocks | blocks |
| `~/.rvm/wrappers/r@g/gem list` (no `VAR=`) | passes | passes |
| `h=/tmp/x.sh; printf '...$HOME/.rvm/...' \| bash "$h"` | **blocks (the bug)** | passes |

Row 2 is the trap: `$HOME` **does** expand inside double quotes (unlike `~`), so that command works, and stripping quoted spans erases the very path the guard looks for. The strip would trade a rare false positive for a real bypass in a guard that blocks.

**Decision: leave it alone.** The guard is correct on every real shape. The false positive is meta — it needs a wrapper path inside a quoted string, which happens when probing hooks with JSON payloads, not in working commands — and the workaround is to put the payloads in a file. Do NOT "fix" this by reusing `command_without_quotes` at line 243.

A precise fix exists if it ever becomes worth it: scope the guard to the command's FIRST SEGMENT (before any `;`/`&&`/`||`/`|`), since the real shape `VAR=value program args` is always a single segment while the false positive is not. It was not pursued because it redesigns a blocking guard's condition and its edge cases were not mapped (notably `cd /x && BUNDLE_GEMFILE=y ~/.rvm/...`, whose first segment is `cd /x` — that would need another guard to be catching it).
3. ~~**`inject-terraform-context.sh`**~~ — DONE, and it was far worse than the false positive it was logged as. Shipped in [dot-claude#426](https://github.com/4shark/dot-claude/pull/426). It was NOT "registered 3× by mistake": three entries with three different `if` matchers, all pointing at the same script, was deliberate — the earlier claim of duplicate registration came from a `jq` that printed the matcher group's `.if` (null) instead of each entry's. The real defects were: (a) it emitted `permissionDecision: "allow"` on everything it fired on, **including `terraform apply`** — the hook injecting "NEVER auto-approve a write — that is the terraform PR #527 incident class" was granting the write approval in the same response; (b) no self-filter, by design, trusting the `if` matchers; (c) those matchers were not gating (20 injections in one session, none on a terraform command). The `allow` was never deliberate — the introducing commit (`faca4fd`) describes only context injection. Fixed by emitting `additionalContext` alone, self-filtering on the command text, and collapsing the wiring to one unscoped entry. The exact `if` misfire condition was never pinned down; self-filtering makes it moot.
4. ~~**`CLAUDE.md` is 223.1k chars against a 150k limit**~~ — CLOSED. **It does not truncate.** Confirmed 2026-07-16 in the CLI entrypoint itself (`claude -p "..." --disallowedTools Read Grep Glob Bash ...`, a headless CLI session forced to answer from context alone), removing the SDK-vs-CLI caveat the earlier measurement carried. Probes by depth: § Language Policy (line 13) correct; `wolfmexico` (line 556, ~33%) correct; § Scope Discipline's three categories (line 1056, at **177,215 chars** — already past the 150k banner) correct and complete; the last section's title (line 1674) correct ("Important Reminders"); the five bullets of § "Why This Structure?" (lines 1645-1649) recited verbatim with their descriptions. The whole 226,896 chars arrive.

   The silent-truncation issues that search surfaces are about **MEMORY.md** — a different file, different limits ([#39811](https://github.com/anthropics/claude-code/issues/39811) 200 lines, [#57574](https://github.com/anthropics/claude-code/issues/57574) ~25KB, [#25006](https://github.com/anthropics/claude-code/issues/25006)). The documented CLAUDE.md warning is about performance ("Large CLAUDE.md will impact performance"). So the item is **cost and latency** — 223k of context every session, 51% over the recommended size — not rules silently vanishing. The remedy, whenever it is wanted, is what CLAUDE.md already prescribes for itself: summary + pointer, body in the docs.

   **The probe design nearly produced the opposite conclusion, and that is the lesson.** Two tail probes ended with `Se nao souber, responda exatamente NAO SEI` — and both returned NAO SEI, which reads exactly like truncation. It was not: the model took the cheap escape on a low-salience lookup. Re-asked without the escape ("the text is in your context, look for it"), it recited the same tail verbatim. **An escape hatch in a probe makes "absent" and "not retrieved" indistinguishable** — and the alarming reading is the one that gets believed. The discriminator that settled it was asking a question the model could not dodge and could only answer if the tail were present: "what is the title of the last section?"

## Closed as NOT-A-DEFECT — the `Write(...)` deny rules

The `claude -p` probes surfaced 23 startup warnings never seen in normal sessions:

```
Permission deny rule (settings.json): Write(~/.ssh/**) is not matched by file
permission checks — only Edit(path) rules are. Use Edit(~/.ssh/**) instead.
```

Every `Write(...)` allow and deny rule in `settings.json` is ignored by Claude Code — including the ones protecting `~/.ssh/**`, `~/.aws/**`, `.env`, `master.key`, `*.pem`, `id_rsa*`, `credentials.yml.enc`. That reads like every secret-protecting deny rule being a no-op.

**It is not.** Every `Write(X)` deny has an `Edit(X)` twin sitting beside it in the same list, and per the warning's own text, "Edit rules cover all file-editing tools". The protection is intact; the `Write` rules are redundant. Same on the allow side: `Write(**)` is ignored but `Edit(**)` covers it, and `Glob(**)` is ignored but `Read(**)` covers it.

So: 23 dead rules producing startup noise on every session, zero security gap. Removing them is safe and cosmetic; leaving them costs 23 warning lines the interactive UI does not surface. Not fixed — nobody asked, and the value is close to zero. Recorded so the next person who sees those warnings does not spend the afternoon believing the secrets are unguarded, which is exactly how this one started.

## Method note — the recurring failure of this session

Three separate times, a confident readout came from a broken instrument, and each time the correction came from the engineer or from a control, never from the agent noticing on its own:

1. **"The session bypasses the permission gate"** — inference from tool results, which look identical whether auto-approved or engineer-approved. The transcript records `permissionMode` and results but no per-command decision, so it was unobtainable from that side. The engineer running one command at a time, with a control command in no allow list, was the only working instrument.
2. **"Tests 2 and 3 prove the tilde form matches"** — they ran with no arguments, so the command string equalled the rule prefix and the `:*` wildcard was never exercised. The tests could not fail, so they proved nothing.
3. **"None of the triggering commands contain 'terraform'"** — the extraction was `grep -o '"command":"[^"]\{0,120\}'`, which stops at the first escaped quote; for one command it captured 17 characters. The substring check ran against a fragment.

The pattern: an instrument that returns a plausible value is trusted, while an instrument that returns nothing is investigated. A control that can fail is the only defence, and it has to be built before the measurement, not after the result looks wrong.

## Method note

The session's first conclusion was wrong and worth recording. The agent claimed the session bypassed the permission gate — inference, not measurement: it cannot observe a prompt, and an approved command and an auto-approved one return identical results. The session transcript records `permissionMode` and tool results but no per-command permission decision, so the fact was unobtainable from that side. What worked was the engineer running one command at a time and reporting whether the dialog opened, with a control command (`cksum`, in no allow list) proving the gate was live. Two of the early tests were also void for a subtler reason: they ran with no arguments, so they never exercised the `:*` wildcard — the exact thing under test.
