# SPIKE — Console script delivery channel

## Investigation question

A Rails console script the engineer runs through `bin/ecs run` executes on a remote Fargate/ECS task, not on the engineer's machine. The engineer copies it out of the chat and pastes it into that session. Sessions have nevertheless been writing those scripts to `/tmp/*.rb` on the local machine, where the engineer cannot reach them from the remote console.

Which rule produces that behavior, and what is the smallest correction that removes it without weakening the rules around it?

A second, lower-frequency complaint is in scope: raw SQL delivered where Ruby was expected.

## Sources consulted

- `~/.claude/CLAUDE.md` § Output Policy → Layer 2 — the table row that routes generated code to a file
- `~/.claude/docs/SCRIPT-DISCIPLINE.md:1-206` — the canonical rules for production-data scripts
- `~/.claude/docs/ACTIVE-RECORD-QUERY-DISCIPLINE.md` (rule 1, summarized in `CLAUDE.md`) — ActiveRecord-first, raw SQL on explicit authorization only
- `~/.claude/scripts/validate-console-script.sh:15,60,110-112` — the only gate covering console scripts
- `~/.claude/settings.json:7-37` — the `PostToolUse` matcher the query checks are wired to
- `~/.claude/skills/integration-debug/SKILL.md:6,11,254-255` — the one place the paste-into-`bin/ecs` contract is written down

## Findings

### Finding 1: Output Policy Layer 2 actively routes a console script to a local file

The Layer 2 table splits generated code on **copy vs run**:

> `| Code the engineer will **copy** into an editor or shell — of any length […] | **In-chat** as a fenced code block. |`
>
> `| Code the engineer will **run**, a configuration file, a real file deliverable, or any external tool output (terraform plan, aws describe, db query, HTTP response) | **File** in `/tmp/`; the path is reported in the chat |`

**Source:** `~/.claude/CLAUDE.md` § Output Policy → Layer 2, verbatim rows above.

**Significance:** a console script is both — the engineer copies it *and* runs it — and "run" is the more literal reading of what happens to it, so the table sends it to `/tmp/`. The axis the table uses cannot separate the two cases. The axis that can is **where the code executes**: on this machine (a file is reachable) or on a host reached by pasting into a remote session (a local file is invisible). This is the rule that produced the behavior; it is not a lapse against a rule.

### Finding 2: SCRIPT-DISCIPLINE.md governs the content of console scripts and says nothing about the channel

The document opens by naming the exact artifact — *"Rails console pastes via `bin/ecs run`"* (`SCRIPT-DISCIPLINE.md:3`) — and Rule 3 is written for it: *"Scripts the engineer pastes into a console (`bin/ecs run`, `rails console`, ad-hoc rake) define their data as **variables**, never as constants"* (`SCRIPT-DISCIPLINE.md:79`).

**Significance:** the document knows the script is pasted, and regulates what goes *inside* it (discovery, three scripts per bucket, variables, the consolidated report, bulk transfer). It never states that the script must arrive in the chat. So the only doc dedicated to this artifact leaves the delivery channel to Layer 2, which decides it wrongly per Finding 1.

### Finding 3: the paste contract is written down only inside one skill

`integration-debug/SKILL.md:6` states the division of labour explicitly: *"**generate the Phase 2 mutation scripts the engineer pastes into `bin/ecs run`**"*, and `:11` reinforces it — *"You generate the script text; the engineer reviews, pastes, runs, reports back."*

**Significance:** the contract exists and is correct, but it is scoped to `integration-debug`. `SCRIPT-DISCIPLINE.md:202` explicitly extends the *content* rules to *"Main-session work where the engineer asks Claude to write a console script directly, without going through a skill"* — the delivery contract does not travel with them. Main-session console scripts are exactly where the complaint comes from.

### Finding 4: writing the script to a file also silently swaps which gate inspects it

`validate-console-script.sh` reads the chat reply and extracts only fenced Ruby blocks:

```
ruby_blocks=$(printf '%s\n' "$last_assistant_message" | sed -n '/^```ruby[[:space:]]*$/,/^```[[:space:]]*$/p')
```

**Source:** `~/.claude/scripts/validate-console-script.sh:112`; its header states the reason at `:15` — *"generated as TEXT in a chat reply, the engineer copies it, and it runs against"* production.

The complementary checks run on the other channel: `check-raw-sql-query.sh` and `check-pluck-ruby-reshape.sh` are registered under the `"matcher": "Edit|Write|MultiEdit"` PostToolUse block (`settings.json:21,26,36`).

**Significance:** the two channels are inspected by disjoint gates. A script delivered in chat is checked for the sample-over-data / `uncached` / `.get` shapes and is **not** checked for raw SQL or pluck-reshape; a script written to `/tmp/x.rb` is checked for raw SQL and pluck-reshape and is **not** checked by the console gate at all. So the wrong channel does not merely inconvenience the engineer — it removes the guard built specifically for production console scripts. The severity of Finding 1 is higher than the ergonomics complaint suggests.

### Finding 5: the raw-SQL complaint already has a rule, and no gate on the delivery path

`ACTIVE-RECORD-QUERY-DISCIPLINE` rule 1 is unambiguous — ActiveRecord-first by default, raw SQL only on explicit engineer authorization, with a documented exception for external customer databases (which have no ActiveRecord layer to bypass).

**Significance:** nothing needs to be decided or added for this complaint at the rule level; the rule is correct as written. What is missing is enforcement on the channel the script actually travels — `check-raw-sql-query.sh` only ever sees file writes (Finding 4). This is consistent with the engineer's own report that the SQL problem is now rare: the rule holds most of the time on instruction alone.

## Trade-offs surfaced

| Approach | Pros | Cons |
|---|---|---|
| Correct the Layer 2 axis (execute-here vs execute-elsewhere) and add the channel to `SCRIPT-DISCIPLINE.md` | Fixes the rule that produced the behavior; keeps every existing gate pointed at the channel it was built for; no new machinery | Instruction-only for the borderline cases a matcher cannot classify |
| Add a `PreToolUse` block on `Write` for a `.rb` file under `/tmp/` whose body makes ActiveRecord calls | Mechanical; the wrong channel becomes impossible rather than discouraged | A local one-off Ruby script under `/tmp/` is legitimate, so the matcher would need to separate "console script" from "local script" — which is intent, not a fact readable off the path |
| Extend `check-raw-sql-query.sh` / `check-pluck-ruby-reshape.sh` to the `Stop` event so they inspect chat-delivered scripts too | Closes the disjoint-gate gap in Finding 4 on the correct channel | Independent of the delivery fix; adds two more `Stop` gates competing for the single per-turn block budget (`stop_hook_active` is a property of the turn) |

## What remains uncertain

- Whether the `Stop` block budget can absorb more gates. Three already share it (`validate-console-script.sh`, `validate-decision-evidence.sh`, `validate-closing-summary.sh`) and the first one to block spends it for the turn. Moving the raw-SQL/pluck checks onto `Stop` would need a decision about ordering, not just a registration.
- Whether any other artifact class is mis-routed by the same copy-vs-run axis. `bin/ecs run` is the case that surfaced; a script pasted into a psql session, a `mongosh` session, or an SSH session on a customer host has the same shape and was not audited here.

## Proposed correction (smallest form)

Two text changes, no new hook:

1. **`CLAUDE.md` § Output Policy → Layer 2** — replace the copy-vs-run split with **where the code executes**. Code that executes on the engineer's own machine (a script they open and run locally, a config file, a real file deliverable, tool output) goes to `/tmp/`. Code that executes somewhere the engineer reaches by **pasting into a remote session** — `bin/ecs run`, a Rails console on ECS, `psql`, `mongosh`, an SSH session — goes **in the chat as a fenced code block**, at any length. A local file is unreachable from the remote host, so it is not a delivery at all.

2. **`SCRIPT-DISCIPLINE.md`** — add the delivery channel as a stated rule alongside the four content rules, so the contract that today lives only in `integration-debug/SKILL.md:6` reaches main-session work, which `:202` already claims for the content rules. Name Finding 4 as its reason: the wrong channel bypasses `validate-console-script.sh` entirely.

Both are `dot-claude` changes and go through a PR per § Configuration Changes Policy.

---

> **Authoring:** written in the main session (not `@agent-spike`) as time-boxed research on a behavior the engineer reported. Every claim cites `file:line` plus the quoted text. The proposed correction is main's synthesis, not a finding — the engineer decides whether it lands.
