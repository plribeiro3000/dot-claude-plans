# SPIKE — Monitor vs. ScheduleWakeup: why the agent drifts into fixed-interval polling, and the native blocking-watch primitives that fix it

## Investigation question

When waiting on an external state change (a GitHub Actions deploy, an ECS service
stabilizing, a Kubernetes rollout, a log line, a filesystem change), why does this agent
reach for a hand-authored fixed-interval `sleep` poll loop inside `Monitor` instead of a
single command that natively blocks and returns the instant the state changes? What is the
catalog of native blocking-watch commands available for the states 4Shark waits on, and
what decision rule should govern how a `Monitor` command is constructed going forward?

## Sources consulted

- [code.claude.com/docs/en/tools-reference](https://code.claude.com/docs/en/tools-reference) — official Monitor tool section and ScheduleWakeup table row. Full text preserved in `monitor-event-driven-pattern_doc_1_official-tools-reference.txt`.
- [code.claude.com/docs/en/scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks) — official `/loop` dynamic-mode and ScheduleWakeup semantics, including the one explicit Monitor-vs-polling comparison found in either official page. Full text preserved in `monitor-event-driven-pattern_doc_2_official-scheduled-tasks.txt`.
- [github.com/anthropics/claude-code/issues/86085](https://github.com/anthropics/claude-code/issues/86085) — community bug report quoting the harness's own sleep-block message, which recommends "Monitor with an until-loop (e.g. `until <check>; do sleep 2; done`)". Full text preserved in `monitor-event-driven-pattern_doc_3_issue-86085.txt`.
- [github.com/anthropics/claude-code/issues/94178](https://github.com/anthropics/claude-code/issues/94178) — independent community bug report quoting the Monitor tool description's own worked example as an `until ... sleep ...` loop. Full text preserved in `monitor-event-driven-pattern_doc_4_issue-94178.txt`.
- [github.com/anthropics/claude-code/issues/65985](https://github.com/anthropics/claude-code/issues/65985) — community bug report of the near-exact failure this spike investigates (hand-rolled `gh run view` polling loop instead of `gh run watch`), with the reporter's own root-cause diagnosis. Full text preserved in `monitor-event-driven-pattern_doc_5_issue-65985.txt`.
- [github.com/anthropics/claude-code/issues/55151](https://github.com/anthropics/claude-code/issues/55151) — community bug report explaining why Monitor's per-stdout-line-is-a-notification design amplifies the cost of a repeating poll shape.
- [github.com/anthropics/claude-code/issues/51304](https://github.com/anthropics/claude-code/issues/51304) and [issues/54086](https://github.com/anthropics/claude-code/issues/54086) — community bug reports on ScheduleWakeup's prompt-replay footgun, relevant to why ScheduleWakeup is a weaker substitute for Monitor on a single bounded external wait.
- [github.com/openai/codex/issues/29922](https://github.com/openai/codex/issues/29922) — cross-vendor (OpenAI Codex) feature request explicitly citing Claude Code's Monitor as the design to copy, with independent cost reasoning. Full text preserved in `monitor-event-driven-pattern_doc_6_codex-29922-and-claudeworld.txt`.
- [claude-world.com/tutorials/s31-scheduled-autonomy](https://claude-world.com/tutorials/s31-scheduled-autonomy/) — third-party (unofficial) tutorial; used only for corroboration of the "poll external state, never harness-tracked work" discriminator, explicitly flagged as unverified against any primary source. Full text preserved alongside doc_6.
- [cli.github.com/manual/gh_run_watch](https://cli.github.com/manual/gh_run_watch) and [gh_pr_checks](https://cli.github.com/manual/gh_pr_checks) — GitHub CLI manual, verified verbatim.
- [docs.aws.amazon.com/cli/.../ecs/wait/services-stable.html](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html), [.../ecs/wait/tasks-stopped.html](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/tasks-stopped.html), and [github.com/aws/aws-cli waiters.py source](https://github.com/aws/aws-cli/blob/develop/awscli/customizations/waiters.py) — AWS CLI reference and source, verified verbatim.
- [kubernetes.io/docs/reference/kubectl/generated/kubectl_wait](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/) — Kubernetes documentation, verified verbatim.
- [docs.aws.amazon.com/cli/.../logs/tail.html](https://docs.aws.amazon.com/cli/latest/reference/logs/tail.html) — AWS CLI reference, verified verbatim.
- [github.com/emcrisostomo/fswatch README](https://github.com/emcrisostomo/fswatch) and [man7.org inotifywait(1)](https://man7.org/linux/man-pages/man1/inotifywait.1.html) — verified verbatim.

## Findings

### Finding 1: the official docs describe Monitor's mechanics but supply no catalog of commands to reach for

**Evidence:** From the official Monitor tool section (verified verbatim against the raw page):

> "The Monitor tool lets Claude watch something in the background and react when it changes, without pausing the conversation. Ask Claude to: Tail a log file and flag errors as they appear / Poll a PR or CI job and report when its status changes / Watch a directory for file changes / Track output from any long-running script you point it at / Connect to a WebSocket feed and report each message as it arrives"

**Source:** [code.claude.com/docs/en/tools-reference](https://code.claude.com/docs/en/tools-reference), full text in `monitor-event-driven-pattern_doc_1_official-tools-reference.txt`.

**Significance:** The doc names the *use cases* ("Poll a PR or CI job") but never a *command* that satisfies them well. Neither this page nor the scheduled-tasks page names `gh run watch`, `aws ecs wait`, `kubectl wait`, or any other native blocking primitive, anywhere. The only place Monitor is explicitly framed as superior to polling is on a different page, inside the ScheduleWakeup/`/loop` documentation, not inside Monitor's own section (see Finding 2) — so a reader (human or model) who reads only the Monitor tool's own doc encounters no comparison to polling and no worked example to pattern-match against. What fills that gap is training-data convention, which for "wait for a condition in a shell script" defaults to `until <check>; do sleep N; done` — an extremely common shell idiom independent of Claude Code.

**Verification:** URL fetched: `https://code.claude.com/docs/en/tools-reference` · Verbatim quote checked: yes (re-confirmed via `grep -o "without pausing the conversation"` against the raw downloaded page) · Quote substring confirmed at: `monitor-event-driven-pattern_doc_1_official-tools-reference.txt`, "Monitor tool" section.

### Finding 2: the one explicit Monitor-vs-polling framing lives outside Monitor's own doc, inside ScheduleWakeup's

**Evidence:**

> "In a session where the Monitor tool is available, Claude may use it directly when you ask for a dynamic `/loop` schedule. Monitor runs a background script and streams each output line back, which avoids polling altogether and is often more token-efficient and responsive than re-running a prompt on an interval."

**Source:** [code.claude.com/docs/en/scheduled-tasks](https://code.claude.com/docs/en/scheduled-tasks), full text in `monitor-event-driven-pattern_doc_2_official-scheduled-tasks.txt`.

**Significance:** This sentence is the strongest available evidence that Anthropic's own documentation *intends* Monitor to replace polling, and it is genuinely well-put ("avoids polling altogether"). But it is positioned as a cross-reference from the `/loop`/ScheduleWakeup page, framed around dynamic *interval scheduling*, not as guidance embedded in Monitor's own section about *what kind of command* to put inside a Monitor call. The asymmetry matters: ScheduleWakeup's whole official framing (both here and in the table row quoted in Finding 4) is "pick a delay, between one minute and one hour, based on what you observed" — an interval-selection mental model. Nothing in either official page tells the reader to first ask "does a command exist that blocks until this exact state changes?" before reaching for an interval at all.

**Verification:** URL fetched: `https://code.claude.com/docs/en/scheduled-tasks` · Verbatim quote checked: yes (re-confirmed via `grep -o "avoids polling altogether"` against the raw downloaded page) · Quote substring confirmed at: `monitor-event-driven-pattern_doc_2_official-scheduled-tasks.txt`, "Let Claude choose the interval" section.

### Finding 3: two independent community bug reports quote the harness's own guidance text as an until-loop-with-sleep example

**Evidence (issue #86085, quoting the block message the reporter observed):**

> "Blocked: sleep 90 followed by: <command> ...
> To wait for a condition, use Monitor with an until-loop (e.g. `until <check>; do sleep 2; done`)
> — you get a notification when the loop exits. Do not chain shorter sleeps to work around this
> block."

**Evidence (issue #94178, quoting the Monitor tool description the reporter observed, filed five weeks later on a different platform):**

> "Monitor: for a single notification, 'use Bash with `run_in_background` and a command that exits when the condition is true, e.g. `until grep -q "Ready in" dev.log; do sleep 0.5; done`.'"

**Source:** [github.com/anthropics/claude-code/issues/86085](https://github.com/anthropics/claude-code/issues/86085) and [issues/94178](https://github.com/anthropics/claude-code/issues/94178), full text in `monitor-event-driven-pattern_doc_3_issue-86085.txt` and `monitor-event-driven-pattern_doc_4_issue-94178.txt`.

**Significance:** This is the strongest available explanation for the observed drift, with an important caveat on its verification status. Two different reporters, five weeks apart, on different platforms, independently transcribe the same shape: whatever internal guidance text they saw (either a Bash sleep-block error, or the Monitor tool's own description) offers a hand-rolled `until <check>; do sleep N; done` as its *own worked example*. If the guidance text a model actually reads (as opposed to the public documentation pages fetched for Findings 1–2) demonstrates a sleep-poll loop as the canonical pattern, then a model generalizing "wait for a GitHub Actions deploy" from that example — swapping the check and the interval — produces almost exactly the `for i in $(seq 1 15); do <gh check>; sleep 45; done` shape this spike's originating task observed. This spike could not independently reproduce or verify this text (no access to trigger the block or inspect the live tool schema from this environment) — it is reported, second-hand evidence from two community bug reports, not confirmed against Anthropic's own primary source. It is also possible the guidance text has since changed: the official pages fetched on 2026-09-16 (Findings 1–2) show no such example anywhere, which is consistent with either a fix having landed, or the exact example text living in a system-prompt/tool-schema surface that is not published on either public doc page.

**Verification:** URLs fetched: `https://github.com/anthropics/claude-code/issues/86085`, `https://github.com/anthropics/claude-code/issues/94178` · Verbatim quote checked: yes (re-confirmed via `grep -n "until <check>; do sleep 2; done"` and manual re-read of the fetched issue bodies) · Quote substring confirmed at: `monitor-event-driven-pattern_doc_3_issue-86085.txt` (Defect 1), `monitor-event-driven-pattern_doc_4_issue-94178.txt` ("Why it happens" section). Note: this verification confirms the ISSUE TEXT is quoted accurately; it does not and cannot confirm the underlying harness message itself, which is second-hand per the Significance note above.

### Finding 4: ScheduleWakeup's own framing is explicitly interval-selection, not condition-blocking

**Evidence:**

> "Reschedules the next iteration of a self-paced `/loop`. Claude calls this at the end of each iteration to pick when the next one runs, between one minute and one hour out; you don't call it directly."

**Source:** [code.claude.com/docs/en/tools-reference](https://code.claude.com/docs/en/tools-reference), ScheduleWakeup table row, `monitor-event-driven-pattern_doc_1_official-tools-reference.txt`.

**Significance:** ScheduleWakeup has no notion of "the condition I'm waiting on" — it only has a delay, clamped to [60, 3600] seconds, chosen once per iteration based on what the previous iteration observed. There is no mechanism by which it can return the instant a state changes; by construction, every use of ScheduleWakeup on external state is a fixed(-ish)-granularity poll, at best re-chosen each round. This matches this spike's originating task description exactly. The scheduled-tasks page independently confirms the interval range and the "based on what it observed" framing:

> "After each iteration it picks a delay between one minute and one hour based on what it observed: short waits while a build is finishing or a PR is active, longer waits when nothing is pending."

Two additional community reports ([issue #51304](https://github.com/anthropics/claude-code/issues/51304), [issue #54086](https://github.com/anthropics/claude-code/issues/54086)) independently document that passing a re-entrant prompt to ScheduleWakeup can re-fire an entire slash command (including its side effects) on wake, which is a second, unrelated reason ScheduleWakeup is a weaker choice than Monitor for a single bounded wait: Monitor's wake is scoped to the watched command's output, ScheduleWakeup's wake re-enters a prompt.

**Verification:** URLs fetched: `https://code.claude.com/docs/en/tools-reference`, `https://code.claude.com/docs/en/scheduled-tasks` · Verbatim quote checked: yes (re-confirmed via `grep -o "picks a delay between one minute and one hour based on what it observed"` against the raw downloaded page) · Quote substring confirmed at: `monitor-event-driven-pattern_doc_1_official-tools-reference.txt` (ScheduleWakeup row), `monitor-event-driven-pattern_doc_2_official-scheduled-tasks.txt` ("Let Claude choose the interval" section).

### Finding 5: the catalog of native blocking-watch primitives, verified per state

**Evidence:** Each command below was independently fetched and its description confirmed verbatim against the raw page (`grep -o` on the downloaded HTML/text before quoting).

| State being waited on | Command | Verified description |
|---|---|---|
| A GitHub Actions run reaching a terminal state | `gh run watch <run-id> --exit-status` | "Watch a run until it completes, showing its progress." / `--exit-status`: "Exit with non-zero status if run fails." ([cli.github.com/manual/gh_run_watch](https://cli.github.com/manual/gh_run_watch)) |
| All checks on a PR reaching a terminal state (when a run-id is not on hand, only a PR number) | `gh pr checks <n> --watch --fail-fast` | `--watch`: "Watch checks until they finish." ([cli.github.com/manual/gh_pr_checks](https://cli.github.com/manual/gh_pr_checks)) |
| An ECS service reaching a stable deploy | `aws ecs wait services-stable --cluster <c> --services <s>` | "Wait until JMESPath query `length(services[?!(length(deployments) == 1 && runningCount == desiredCount)]) == 0` returns True when polling with `describe-services`. It will poll every 15 seconds until a successful state has been reached. This will exit with a return code of 255 after 40 failed checks." ([docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html)) |
| A one-off ECS task finishing | `aws ecs wait tasks-stopped --cluster <c> --tasks <t>` | "Wait until JMESPath query `tasks[].lastStatus` returns `STOPPED` for all elements when polling with `describe-tasks`. It will poll every 6 seconds until a successful state has been reached. This will exit with a return code of 255 after 100 failed checks." ([docs.aws.amazon.com](https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/tasks-stopped.html)) |
| Any AWS resource reaching a documented state (the general `aws <service> wait <condition>` family — confirmed present for EC2 `instance-status-ok`/`instance-running`/`snapshot-completed`, SSM `command-executed`, Lambda `function-updated-v2`, and others, each following the same shape) | `aws <service> wait <condition> ...` | "Wait until a particular condition is satisfied. Each subcommand polls an API until the listed requirement is met." (`WaitCommand.DESCRIPTION`, [aws-cli waiters.py source](https://github.com/aws/aws-cli/blob/develop/awscli/customizations/waiters.py), line 55) |
| A Kubernetes resource reaching a condition | `kubectl wait --for=condition=<name> --timeout=<duration> <resource>` | "Wait for a specific condition on one or many resources. The command takes multiple resources and waits until the specified condition is seen in the Status field of every given resource. [...] A successful message will be printed to stdout indicating when the specified condition has been met." ([kubernetes.io](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/)) |
| A local filesystem change (macOS) | `fswatch <path>` | "`fswatch` is a file change monitor that receives notifications when the contents of the specified files or directories are modified." ([github.com/emcrisostomo/fswatch](https://github.com/emcrisostomo/fswatch)) — NOT installed by default on macOS; requires `brew install fswatch`. |
| A local filesystem change (Linux) | `inotifywait -m <path>` (add `-r` for recursive) | "inotifywait efficiently waits for changes to files using Linux's inotify(7) interface by default. It is suitable for waiting for changes to files from shell scripts." ([man7.org inotifywait(1)](https://man7.org/linux/man-pages/man1/inotifywait.1.html)) — ships in the `inotify-tools` package, not present by default on a minimal image. |

**Significance:** A genuine, verified, native blocking primitive exists for every state this task asked about **except one** — see Finding 6 for the honest gap.

**Verification:** URLs fetched: `https://cli.github.com/manual/gh_run_watch`, `https://cli.github.com/manual/gh_pr_checks`, `https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/services-stable.html`, `https://docs.aws.amazon.com/cli/latest/reference/ecs/wait/tasks-stopped.html`, `https://github.com/aws/aws-cli/blob/develop/awscli/customizations/waiters.py`, `https://kubernetes.io/docs/reference/kubectl/generated/kubectl_wait/`, `https://github.com/emcrisostomo/fswatch`, `https://man7.org/linux/man-pages/man1/inotifywait.1.html` · Verbatim quote checked: yes, every cell's quote was re-confirmed via `grep -o`/`grep -n` against its own separately downloaded raw page or source file (see the Bash tool-call history for this spike) · Quote substring confirmed at: each row's cited URL, at the raw page/file downloaded for it.

### Finding 6: a log line appearing has no built-in "block until match, then exit" primitive — this is the honest gap

**Evidence:** `aws logs tail` documents its `--follow` flag as:

> "Whether to continuously poll for new logs. By default, the command will exit once there are no more logs to display. To exit from this mode, use Control-C."

**Source:** [docs.aws.amazon.com/cli/latest/reference/logs/tail.html](https://docs.aws.amazon.com/cli/latest/reference/logs/tail.html), verified verbatim.

**Significance:** `--follow` streams indefinitely; it has no "exit when this line appears" semantics of its own. There is no native CLI equivalent of `gh run watch` for "wait until a specific log line shows up." The honest answer, confirmed independently by the cross-vendor Codex proposal's own worked example (`tail -F <log> | grep --line-buffered <pattern>`, [issue #29922](https://github.com/openai/codex/issues/29922)), is that Monitor's *own* per-stdout-line-is-an-event mechanism is what supplies the missing "wait for a match" behavior — not the tailing command itself. `aws logs tail --follow --since <window> | grep --line-buffered <pattern>` (or the local-file equivalent, `tail -F <log> | grep --line-buffered <pattern>`) run as the Monitor command produces silence until the pattern matches, at which point the one matching line becomes the one notification, and Monitor's own deadline (5 minutes default / 30 minutes max, confirmed in Finding 1's source) bounds how long it runs if the line never appears. This is a bounded, justified exception to "prefer a command that blocks and exits on its own" — the state genuinely has no such command, so a filtered stream inside Monitor is the correct fallback, not a defect.

**Verification:** URLs fetched: `https://docs.aws.amazon.com/cli/latest/reference/logs/tail.html`, `https://github.com/openai/codex/issues/29922` · Verbatim quote checked: yes (re-confirmed via `grep -o "Whether to continuously poll for new logs"` against the raw downloaded page, and `grep -n "tail -F app.log"` against the fetched issue body) · Quote substring confirmed at: raw `logs_tail.html` and `monitor-event-driven-pattern_doc_6_codex-29922-and-claudeworld.txt`, Part A.

### Finding 7: Monitor's per-stdout-line-is-a-notification design amplifies the cost of a poll-with-echo shape

**Evidence:**

> "The Monitor tool fires a notification for each stdout line of the watched command. Each notification is delivered as a new model turn. The model treats turns as requiring a response, ... Monitor is the nearest available tool, so it gets called reflexively."

**Source:** [github.com/anthropics/claude-code/issues/55151](https://github.com/anthropics/claude-code/issues/55151), reporter's own root-cause analysis (this spike quotes the reporter's diagnosis; it did not independently reproduce the 309-Monitor-spawn incident described in that issue).

**Significance:** This is a distinct but related failure to the one this spike's originating task describes: if a poll loop *inside* Monitor prints a status line on every iteration (e.g., `echo "checking..."` before each `gh run view`), each of those lines becomes its own notification/turn — 15 iterations means (up to) 15 turns, not one. This reinforces, from a different angle, why the fix the task's engineer found (`gh run watch` — one command, one exit, one final line) is strictly better than even a *well-written* sleep-poll loop inside Monitor: it is not just about wall-clock granularity, it is about how many notifications/turns the watch generates before it resolves.

**Verification:** URL fetched: `https://github.com/anthropics/claude-code/issues/55151` · Verbatim quote checked: yes (re-confirmed via direct re-read of the fetched issue body) · Quote substring confirmed at: the issue's "Root cause" section, fetched 2026-09-16 via `gh issue view 55151 -R anthropics/claude-code`.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Native blocking command inside `Monitor` (`gh run watch`, `aws ecs wait`, `kubectl wait`) | Fires on the instant the state changes (fine-grained); zero manual interval tuning; typically one notification (the exit line); reuses vendor-maintained polling internals (rate-limit-aware, terminal-state-aware) | Requires such a command to exist for the state in question; some (`gh run watch`) still poll internally on a fixed interval (default 3s) under the hood — the caller just doesn't pay for that complexity | Findings 3, 5; [cli.github.com/manual/gh_run_watch](https://cli.github.com/manual/gh_run_watch) |
| Filtered stream inside `Monitor` (`tail -F log \| grep --line-buffered pattern`) | The only option when no purpose-built blocking command exists (Finding 6); still zero manual interval tuning, wakes on match | Streams indefinitely if the pattern never matches — relies entirely on Monitor's own deadline to bound it, not on the command's own logic | Finding 6; [issue #29922](https://github.com/openai/codex/issues/29922) |
| Bounded sleep-poll loop inside `Monitor` (`until <check>; do sleep N; done`) | Works for literally any state, including ones with no CLI at all (a bespoke internal API); the shape the harness's own guidance appears to demonstrate (Finding 3) | Coarse, fixed granularity (the exact complaint in the originating task); each iteration is its own notification/turn if it echoes anything (Finding 7); the exact anti-pattern named in three independent bug reports (#65985, #86085, #94178) | Findings 3, 5, 7 |
| `ScheduleWakeup` on external state | Survives across the session even when Monitor is unavailable (e.g., Bedrock/Vertex/Foundry, if that restriction does in fact cover Monitor's core capability — see Finding 1's reading notes) | No notion of "the condition"; every use on external state is a poll at a chosen interval, never truly event-driven; carries its own prompt-replay footguns (issues #51304, #54086) unrelated to Monitor | Finding 4 |

## What remains uncertain

- **Whether the exact guidance text quoted in issues #86085 and #94178 (the `until <check>; do sleep N; done` worked example) still exists in the live tool schema as of 2026-09-16.** The two official documentation pages fetched for this spike show no such example anywhere, and no comparison of blocking commands vs. polling within Monitor's own section. This could mean the guidance changed between when those issues were filed (2026-08-11 and version 2.1.270 respectively) and now, or that the exact wording a model sees lives in a system-prompt/tool-schema surface not published on either public doc page. This spike could not access that surface directly and did not attempt to trigger the block message to check.
- **Whether the Bedrock/Google Cloud Agent Platform/Microsoft Foundry restriction in the official Monitor doc applies to Monitor as a whole, or only to its WebSocket-source sub-feature.** The restriction sentence sits in a shared, unheaded paragraph between the general permission-rules text and the "WebSocket source" heading; the co-occurring `DISABLE_TELEMETRY` clause suggests (but does not confirm) it is scoped to the WebSocket variant specifically. See the reading notes in `monitor-event-driven-pattern_doc_1_official-tools-reference.txt`.
- **Whether `persistent` is a genuine current Monitor parameter.** Only `timeout_ms` is independently confirmed against the official primary source (via its reuse in the WebSocket-source section); `persistent` (and the exact top-level parameter table: `description`/`command`/`timeout_ms`/`persistent`) comes only from a third-party blog (claudefa.st) not independently verified against the official page.
- **Whether `gh run watch`'s internal polling interval (default 3 seconds, per its `--interval`/`-i` flag) matters for the GitHub API rate-limit concern raised in issue #65985.** This spike did not investigate whether `gh run watch` itself is rate-limit-safe at scale (the issue's own top comment states it "opens a single streaming connection," which is inconsistent with a 3-second poll internally, and this spike did not resolve that apparent tension — it is worth confirming before treating `gh run watch` as categorically rate-limit-immune under heavy concurrent use).

## Suggested options for main and the engineer

- **Option A — codify the decision rule as a CLAUDE.md addition (or a Tier 2 doc), covering the catalog in Finding 5 and the "blocking command first, filtered stream second, bounded sleep-poll last" ordering from the Trade-offs table.** This directly targets the observed failure by giving the agent, inside this repository's own context, the worked examples that the public Claude Code documentation and (per Finding 3) possibly the tool's own guidance do not supply.
- **Option B — file the equivalent of issue #65985/#86085/#94178 upstream against Anthropic**, since Finding 3's root-cause hypothesis — the harness's own guidance text demonstrating a sleep-poll shape as its worked example — if still current, is a defect in the product this repository depends on, not merely a 4Shark-side gap. This does not preclude Option A; the two are independent and address different layers (this repo's own agent behavior vs. the upstream tool's guidance).
- **Option C — do nothing beyond this spike**, accepting that the single observed incident was corrected in-session by the engineer and treating recurrence as a signal to revisit. Weighed against the cross-referenced evidence in Findings 3, 5, and 7 (three independent, dated, still-open community bug reports describing the same class of drift across a five-month span), this risks the same coarse-granularity/wasted-notification failure recurring on the next GitHub Actions wait, ECS deploy wait, or Kubernetes rollout wait this agent is asked to perform.

(No recommendation — the trade-offs above and the options here are for main and the engineer to weigh.)
