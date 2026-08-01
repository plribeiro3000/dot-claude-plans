# SPIKE — Forcing verification before output

## Question

Three failure categories observed across a full working session have no mechanical
gate, and two of them resist every gate shape tried so far. What mechanism — if
any — can force a verification step into the critical path of an action, when the
thing being verified leaves no trace in the generated text?

## Context

A single session (2026-07-31, backfill of `error_constraint` across four
environments) produced 31 engineer corrections. The transcript is the source:
`~/.claude/projects/-/ec18c40e-1644-46d8-9855-5b71bdb1a079.jsonl`, engineer
messages extracted with `jq`.

Classified by cause:

| Category | Occurrences | Gate status |
|---|---|---|
| Source not consulted before acting | 11 | 2 covered by `validate-console-script.sh` |
| Policy not read before acting | 7 | 2 covered by the same gate |
| Decision item delivered with no evidence | 4 | covered by `validate-decision-evidence.sh` |
| State reported falsely | 3 | none |
| Decision taken where the engineer had already decided | 3 | none |

Four of the 31 were repetitions of a correction the engineer had already made in
the same session — including one identical pair: shipping code untested while
citing a local environment failure, corrected explicitly, then repeated hours
later on the hotfix PR.

## Finding 1 — Where a hook existed, the mistake did not repeat

Four hook blocks fired during the session (`validate-bash-command.sh` on compound
commands, three times; `validate-closing-summary.sh` once). None of the four
required an engineer correction afterwards, and none recurred.

Every one of the four repeat offences fell in a category with no gate. The
correlation is not proof of causation on a sample this size, but it inverts the
usual assumption: the rule text was present, injected per-turn, and recitable in
all four cases. Presence of the rule did not predict compliance; presence of a
mechanism did.

## Finding 2 — The 4Shark rule set inverts the training default, which makes
memory an anti-signal

Most conventions in this repository are deliberate inversions of the Rails
mainstream: `optional: true` on `belongs_to`, no `delegate`, no ternary, no safe
navigation, no bang methods in web flows, IDs instead of loaded objects. Writing
"the normal way" therefore produces the wrong result systematically, not
occasionally.

This matters for gate design: a mechanism that only *reminds* competes against a
strong prior that points the other way. A mechanism that *blocks* does not.

## Finding 3 — Two categories leave no textual trace, and that is what defeats
the matcher

`validate-console-script.sh` and `validate-decision-evidence.sh` both work because
the defect becomes a string in the output: `first(50)`, `ActiveRecord::Base.uncached`,
an options list with no code block. A regex reaches those.

The remaining categories do not produce such a string:

- **Source not consulted** — an unread `db/schema.rb` looks exactly like a read
  one. The query text is identical either way; only the correctness differs, and
  correctness is what the reader is trying to establish.
- **State reported falsely** — "resolved 10 threads" is well-formed text. Judging
  it requires comparing the claim against the tool trace.
- **Decision taken where the engineer had already decided** — requires modelling
  the engineer's intent across turns.

## Options considered and rejected

**A read-marker gate** (`PostToolUse(Read)` writes `/tmp/claude_doc_read_<hash>`;
`PreToolUse` requires the marker before a matching action). The mechanism is
proven in this repository — `sidekiq-queue-check.sh` writes a GO marker that
`validate-productive-deploy.sh` requires. Rejected for now on two grounds: it
proves a file was opened, not that the relevant rule was applied, so it converts a
judgment gate into a ritual one; and a false negative blocks a legitimate release,
which is expensive enough that fail-open would be tempting — and fail-open defeats
the gate.

**A claim-versus-trace gate** at `Stop`, comparing quantified completion claims
("N resolved", "all N done") against the turn's tool calls. Rejected: the `Stop`
payload exposes `transcript_path`, but the hooks reference warns it "may lag
behind", and a gate whose input can lag produces false blocks on correct replies.

**A broader `Stop` matcher on assertion language** ("done", "confirmed", "already
handled"). Rejected as certain noise: those words appear in almost every
substantive reply, and a gate that fires constantly gets disabled.

## Open questions

1. Can a gate distinguish *reading a document* from *applying it*, or is the
   read-marker the honest ceiling for the policy category? If it is the ceiling,
   is a ritual gate still net-positive against no gate at all?
2. Is there a reliable, non-lagging way for a `Stop` hook to see the turn's tool
   calls? If yes, the false-state category becomes mechanizable and it is the
   highest-consequence one on the list.
3. Does the community have a name for the underlying failure — producing output
   before verifying the premise it rests on, with the rule present and recitable?
   Nearest neighbours seen so far are automation complacency and the
   plausibility-over-evidence framing, neither an exact fit. Verify before
   attributing either.
4. Would raising the cost of the *first* output (a forced pre-action checklist)
   beat gating the *last* one? Every gate built so far fires at `Stop`, after the
   work is done, which spends a turn on rework.

## Status

Two gates shipped from this analysis (`validate-console-script.sh`,
`validate-decision-evidence.sh`), covering 8 of the 31 occurrences. The remaining
23 stay under engineer correction until one of the open questions above resolves.
