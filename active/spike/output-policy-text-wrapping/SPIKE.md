# SPIKE — Output Policy: Prose Hard-Wrap at ~80 Columns

## Investigation question

The agent, when asked to produce prose text for the engineer to paste into Gmail, Outlook, or Slack, inserts hard newlines at approximately column 80 within every paragraph. When the engineer copy-pastes that output, the embedded newlines survive the paste and break each paragraph into ragged short lines inside the destination app.

Two distinct issues need to be disentangled and traced to their respective rule locations:

1. **Hard-wrap gap** — No rule in the Output Policy explicitly forbids the agent from inserting hard line breaks in prose content destined for email/chat. The policy covers format (plain text vs markdown), channel (chat vs file), and destination (/tmp vs Downloads), but is silent on line-length within a plain-text prose output.

2. **Terminal-dump compliance failure** — The policy already mandates that email drafts >10 lines go to a `.txt` file in `/tmp/` (Layer 2, line 576, CLAUDE.md). Dumping the draft into the terminal chat instead of writing it to `/tmp/` is a compliance failure against an existing rule, not a gap.

---

## Sources consulted

- [http://www.righto.com/2019/11/ibm-sonic-delay-lines-and-history-of.html](http://www.righto.com/2019/11/ibm-sonic-delay-lines-and-history-of.html) — History of IBM 80×24 terminal standard tracing back to punch cards
- [https://www.arp242.net/email-wrapping.html](https://www.arp242.net/email-wrapping.html) — Primary source on why hard-wrapping email body text is problematic
- [https://datatracker.ietf.org/doc/html/rfc5322#section-2.1.1](https://datatracker.ietf.org/doc/html/rfc5322#section-2.1.1) — RFC 5322 section 2.1.1, origin of the 78-character email line recommendation
- [https://mathiasbynens.be/notes/gmail-plain-text](https://mathiasbynens.be/notes/gmail-plain-text) — Gmail's hard-wrap behavior and RFC misuse
- [https://github.com/anthropics/claude-code/issues/13378](https://github.com/anthropics/claude-code/issues/13378) — Claude Code bug: 2-space indent and 80-char hard wrap breaking copy-paste
- [https://github.com/anthropics/claude-code/issues/43113](https://github.com/anthropics/claude-code/issues/43113) — Feature request: flag to stop hard-wrap in prose output
- [https://github.com/anthropics/claude-code/issues/6827](https://github.com/anthropics/claude-code/issues/6827) — Bug: hard line breaks at ~80 chars in VS Code extension
- [https://github.com/anthropics/claude-code/issues/24224](https://github.com/anthropics/claude-code/issues/24224) — Feature request: config option to control text wrapping
- [https://github.com/anthropics/claude-code/issues/33666](https://github.com/anthropics/claude-code/issues/33666) — Bug: model ignores configured line width in CLAUDE.md (closed as not planned)
- [https://github.com/anthropics/claude-code/issues/27953](https://github.com/anthropics/claude-code/issues/27953) — Bug: remove hard wrap when copying
- [https://github.com/anthropics/claude-code/issues/32190](https://github.com/anthropics/claude-code/issues/32190) — Bug: copied text includes word-wrap line breaks
- `/Users/plribeiro3000/.claude/CLAUDE.md` lines 550–726 — Output Policy (all five layers)
- `/Users/plribeiro3000/.claude/docs/OUTPUT-EDGE-CASES.md` full file — Edge cases for each destination
- See auxiliary: `wrapping_excerpt_1.txt` — Verbatim quotes from all external sources with URLs
- See auxiliary: `wrapping_excerpt_2.txt` — Verbatim quotes from CLAUDE.md Output Policy + grep results on OUTPUT-EDGE-CASES.md

---

## Findings

### Finding 1: The 80-column convention traces to IBM punch cards (1928), not to human reading preference

**Evidence:**

> "The source of 80-column lines is clearly punch cards, as commonly claimed."
> "The 80-character width allowed the terminals to take the place of 80-column punch cards for data entry."
> "The impact of these systems remains decades later: 80-character lines are still a standard, along with both 80×24 and 80×25 terminal windows."

**Source:** http://www.righto.com/2019/11/ibm-sonic-delay-lines-and-history-of.html

**Significance:** The 80-column standard was a physical storage constraint of 1928-era punch cards. IBM's 3270 terminal (1971) inherited it, and its market dominance propagated it into Unix and terminal emulators. The constraint was never about readability of prose on a modern display — it was about data card physical size and early CRT memory economics. The standard has no architectural relationship to how a reader perceives a paragraph in a modern email or chat client.

URL fetched / Verbatim quotes checked / Quote substrings confirmed in fetched content.

---

### Finding 2: RFC 5322 recommends 78 characters for transmission compatibility with legacy implementations, not for display

**Evidence:**

> "Each line of characters MUST be no more than 998 characters, and SHOULD be no more than 78 characters, excluding the CRLF."
> "The more conservative 78 character recommendation is to accommodate the many implementations of user interfaces that display these messages which may truncate, or disastrously wrap, the display of more than 78 characters per line."

**Source:** https://datatracker.ietf.org/doc/html/rfc5322#section-2.1.1

**Significance:** RFC 5322 section 2.1.1 establishes the 78-character recommendation as a compatibility measure for legacy implementations that could not handle longer lines. The hard limit is 998 characters. The recommendation is about email transport/wire format, not about the visual wrapping of prose content inside a compose window or a paste target. Modern email clients (Gmail, Outlook) handle long lines without truncation. Applying the RFC 5322 recommendation to a prose message the engineer will paste into a GUI compose window conflates "wire format" with "display format."

URL fetched / Verbatim quotes checked / Quote substrings confirmed in fetched content.

---

### Finding 3: Hard-wrapping prose destined for modern email/chat clients creates ragged paragraphs and is considered incorrect practice

**Evidence:**

> "The forced linebreaks are intermingled with the wrapping linebreaks, and there is no way the client can figure out if a hard wrap is meaningful and can be safely omitted; the result is not great and rather annoying to read."
> "Wrapping by character count is incorrect with proportional (non-monospace) fonts anyway, which is what the overwhelming majority of people use."
> "It seems to me that 'hard-wrap all text at 78 characters' is a misreading of the standard and a confusion between 'how things should be sent on the wire' and 'how things should be displayed'."

**Source:** https://www.arp242.net/email-wrapping.html

**Supporting evidence (Gmail side):**

> "Gmail hard-wraps emails that are composed in plain text mode before sending them."
> "Instead of filling up the available screen width and letting the text flow naturally, the automatically inserted hard breaks ensure no line is longer than 78 characters."

**Source:** https://mathiasbynens.be/notes/gmail-plain-text

URL fetched / Verbatim quotes checked / Quote substrings confirmed in fetched content.

**Significance:** When a plain-text paragraph contains embedded newlines at column 80, and the recipient's email client or chat client applies its own viewport-width soft-wrapping on top, the two sets of breaks compound. A short viewport renders single-word lines. The client has no way to distinguish intentional breaks (list items, paragraph separators) from mechanical column-counting breaks. The consensus in the web standards / email community is that prose paragraphs should be single long lines; let the client's viewport wrap. Gmail's own behavior — inserting hard breaks before sending — confirms that the problem originates at composition time and compounds at render time.

---

### Finding 4: Claude Code's terminal UI inserts hard newlines in prose output at ~80 columns — multiple open GitHub issues, no shipped fix

**Evidence (issue #13378):**

> "Claude Code adds a 2-space indent to all code block content and hard-wraps at ~80 characters. When copying commands from the terminal, these artifacts get included, breaking pasted commands."
> "posting this bug report verbatim as Claude Code output it - complete with the 2-space indent and 80-char wrap. The bug demonstrates itself."

**Source:** https://github.com/anthropics/claude-code/issues/13378 (open)

**Evidence (issue #43113):**

> "Currently, Claude Code uses Ink's word wrapping to insert \n characters at word boundaries based on process.stdout.columns. These hard newlines create issues: Hard newlines are stored in the terminal's scrollback buffer and treated as intentional paragraph breaks."

**Source:** https://github.com/anthropics/claude-code/issues/43113 (open, labeled enhancement/duplicate)

**Evidence (issue #6827, Claude Code's own acknowledgment):**

> "That's exactly right - and I can see it happening in my responses too. When I try to write naturally flowing text, something on the server side is inserting hard line breaks at around 80 characters, which breaks copy-paste functionality for things like markdown files or release notes. This seems like a bug or overly aggressive formatting rule in Claude Code that should definitely be configurable or removed entirely."

**Source:** https://github.com/anthropics/claude-code/issues/6827 (open)

**Evidence (issue #33666 — CLAUDE.md configuration resistance):**

> "The model acknowledges the rules when asked but fails to apply them when generating text."

**Source:** https://github.com/anthropics/claude-code/issues/33666 (closed as **not planned**)

**Significance:** The behavior has two layers. The Claude Code terminal UI (Ink renderer) inserts hard newlines at `process.stdout.columns` for display purposes — this is a TUI rendering choice that affects what gets copied. Additionally, the model itself tends to generate prose with embedded newlines at ~80 columns, which is a model output behavior separate from the TUI renderer. Issue #33666 being closed as "not planned" means Anthropic has no current plan to make the model's line-width configurable via CLAUDE.md. The path available to the engineer is to write rules that instruct the model about how to format prose output — even if those rules fight against a learned default.

URL fetched / Verbatim quote checked / Quote substring confirmed at source.

---

### Finding 5: The use case (prose to be pasted into email/chat) is explicitly called out in the GitHub community as broken and needing a config option — no official workaround has shipped

**Evidence:**

> "Drafting social media posts, emails, Slack messages, or any prose content in Claude Code that needs to be pasted elsewhere cleanly. This is increasingly common as Claude Code becomes a general-purpose assistant, not just a code editor."
> "Current workarounds: Write to file, open in TextEdit, copy from there. Pipe to pbcopy via Bash tool."

**Source:** https://github.com/anthropics/claude-code/issues/24224 (closed as duplicate)

**Evidence (issue #32190, root cause):**

> "This appears to be caused by Claude Code's TUI rendering text with actual newline characters in the terminal buffer rather than relying on the terminal's soft-wrap."

**Source:** https://github.com/anthropics/claude-code/issues/32190 (closed)

**Significance:** The community workaround of writing prose to a file and opening in a text editor is consistent with what the 4Shark Output Policy already requires (Layer 2, line 576): email drafts >10 lines go to `/tmp/` as plain text. If the agent writes to `/tmp/email_draft_YYYYMMDD_HHMMSS.txt` and the engineer opens it in a text editor, the terminal TUI's hard-wrap renderer does not affect what gets copied. This makes the file-write path important not only for channel reasons (Layer 2) but also as the practical mitigation for the hard-wrap problem — but it only works if the file itself does not contain hard-wrapped paragraphs.

URL fetched / Verbatim quotes checked / Quote substrings confirmed in fetched content.

---

### Finding 6: The current Output Policy is silent on line-wrap of prose — this is a gap, not a compliance failure

**Evidence (CLAUDE.md line 552):**

> "Every output obeys the same question: **what kind of output is this, who consumes it, where will they use it?** The engineer should not have to clean up the output before using it — fences to strip, lines to dewrap, characters to escape, files to move out of `/tmp/`. If they would, the output is in the wrong shape."

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md:552`

**Evidence (CLAUDE.md Layer 1, lines 558–564):**

The table at Layer 1 specifies that email/chat destinations require **plain text** (no Markdown syntax). It does not say anything about paragraph line length or hard vs soft wrapping.

**Evidence (CLAUDE.md Layer 2, line 576):**

> "email drafts > 10 lines, any external tool output (terraform plan, aws describe, db query, HTTP response) | **File** as plain text in `/tmp/`, opened with `open`"

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md:576`

**Evidence (OUTPUT-EDGE-CASES.md grep):**

Bash grep for "wrap", "column", "80", "72", "newline", "hard", "soft", "width" in `/Users/plribeiro3000/.claude/docs/OUTPUT-EDGE-CASES.md` returned:
- Line 52: Slack table row mentioning "line break" (formatting element, not prose wrapping)
- Line 87: reference to "wrapper" (code block fence, not line wrapping)

Zero mentions of column width, hard wrap, soft wrap, or line length for prose.

**Source:** `/Users/plribeiro3000/.claude/docs/OUTPUT-EDGE-CASES.md` (full file read, 2026-06-19)

**Significance:** The phrase "lines to dewrap" at line 552 signals the policy author's intent — the engineer should not have to manually remove line breaks. But this is stated as a problem the policy prevents, not as a rule with a specific clause. No layer of the Output Policy contains a statement like "do not insert hard line breaks within prose paragraphs" or "each paragraph is a single line." The hard-wrap behavior violates the spirit of line 552 (the engineer has to clean up) but violates no explicit rule. This is a gap, not a compliance failure.

Quote verified in file / Line numbers confirmed.

---

### Finding 7: The terminal-dump failure (prose delivered in chat instead of /tmp/) is a compliance failure against an existing rule

**Evidence (CLAUDE.md Layer 2, line 576):**

> "| Long code blocks, multi-line command sequences (multi-line curl, AWS CLI with many flags), configuration files, email drafts > 10 lines, any external tool output (terraform plan, aws describe, db query, HTTP response) | **File** as plain text in `/tmp/`, opened with `open` |"

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md:576`

**Evidence (CLAUDE.md Layer 3, line 582):**

> "| `/tmp/` | **Default for any file output** — working scripts, intermediate code, tool output dumps, HTML reports for local review, **email drafts the engineer will copy-paste into a mail client**, code blocks the engineer will run once, logs, anything the engineer consumes and discards on their own machine |"

**Source:** `/Users/plribeiro3000/.claude/CLAUDE.md:582`

**Significance:** The rule at line 576 is unambiguous: an email draft >10 lines goes to a file in `/tmp/`. The agent's behavior of dumping the draft into the terminal chat (mixing agent framing prose with the actual message text) directly violates this rule. This is not a gap — the rule exists and was not followed. The fix for this failure is enforcement (a rule restatement, a mechanical hook, or a behavior check) rather than a new rule.

Quote verified in file / Line numbers confirmed.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Sources |
|---|---|---|---|
| **Option A: Add explicit no-hard-wrap clause to Layer 1** — "For email and chat destinations: write each paragraph as a single line; do not insert hard newlines within prose paragraphs. Let the destination app soft-wrap." | Directly names the gap. Works regardless of whether the file-write rule is followed. Actionable for the model. | The Ink TUI renderer will still visually hard-wrap in the terminal; the engineer will see what looks like wrapped text even though the underlying content is correct. Could cause confusion ("why is the chat text wrapping?"). Does not help with code destinations. | Findings 3, 4, 6 |
| **Option B: Add no-hard-wrap clause to OUTPUT-EDGE-CASES.md under Email clients and Chat clients** — same substance as Option A but placed in the edge-cases companion file | Keeps CLAUDE.md shorter. Consistent with how other email/chat edge cases are documented. | Tier 2 doc: only loaded on SubagentStart in full; in main session it is a pointer. Lower probability of being applied in short sessions without a hook injection. | Findings 6, 7 |
| **Option C: Strengthen Layer 2 compliance for the terminal-dump failure only** — add a sentence: "A prose message >10 lines must be written to `/tmp/` even if it is a single paragraph (not just long code or tool output)" | Directly addresses the compliance gap (Finding 7). Keeps the hard-wrap gap as a separate concern. | Does not prevent hard-wrap inside the `/tmp/` file itself; the engineer still gets wrapped lines when opening the file in a text editor that preserves newlines. | Finding 7 |
| **Option D: Mechanical hook** — a PostToolUse or PreToolUse hook that detects Write tool calls to `/tmp/*.txt` and validates that prose lines are not hard-wrapped (lines >120 characters that don't start with a list/heading marker) | Mechanically enforced, does not rely on model compliance. | Significant engineering effort. May fire false positives on log files, command output, code blocks. Adds another hook to the hook chain. Does not catch in-chat prose (no file is written). | Findings 4, 5 |
| **Option E: Add a hook that injects the no-hard-wrap rule into every SubagentStart AND UserPromptSubmit** — similar to how `inject-output-policy-reminder.sh` works | Maximally visible. Survives context compaction. | Another hook, more context injection overhead. The model's tendency to hard-wrap at 80 is documented as resistant to CLAUDE.md instructions (issue #33666, closed as not planned). An injected rule may also not persist. | Finding 4 |
| **Option F: Combine A + C** — add the no-hard-wrap clause to Layer 1 (gap fix) AND add an explicit compliance restatement for the terminal-dump failure at Layer 2 | Addresses both issues in the most direct location. | Adds content to an already long CLAUDE.md. | Findings 6, 7 |

---

## What remains uncertain

- **Whether the model's hard-wrap behavior is a model-level default or purely a TUI renderer default.** Issue #43113 attributes it to Ink's `process.stdout.columns`; issue #6827 attributes it to "something on the server side." The two mechanisms are distinct: if it is TUI-only, writing to `/tmp/` already solves the problem (the file contains no hard wraps). If it is also a model-level default, adding a CLAUDE.md rule is necessary.
- **Whether issue #33666 (closed as not planned) means a CLAUDE.md rule is ineffective.** The issue shows the model ignoring configured line widths. However, that issue was about enforcing a specific column limit, not about forbidding hard wraps entirely. A "no hard wrap" instruction may be easier for the model to follow than "wrap at exactly 120 columns."
- **Whether the OutputPolicy's Layer 2 file-write rule, if followed, already resolves the paste problem in practice.** If the agent writes to `/tmp/email_draft.txt` and the engineer opens it in a text editor (VS Code, TextEdit), and if the text editor preserves newlines on copy, the engineer still gets hard-wrapped paragraphs on paste. The file-write alone is not sufficient unless the file content is itself unwrapped.
- **Mechanical enforcement feasibility.** No investigation was done into how complex a PostToolUse hook would be to implement for this purpose.

---

## Suggested options for main and the engineer

- **Option A alone** (add explicit no-hard-wrap clause to Layer 1 of the Output Policy): addresses the gap directly, immediately improves agent behavior for in-chat and file-written prose alike.
- **Option C alone** (strengthen the Layer 2 compliance restatement for the terminal-dump failure): addresses the compliance issue without touching the hard-wrap question.
- **Option F = A + C** (fix both gap and compliance failure in CLAUDE.md simultaneously): the most complete single-PR fix; adds two targeted sentences to the policy.
- **Option B** (put the no-hard-wrap clause in OUTPUT-EDGE-CASES.md instead): lower impact than Option A due to Tier 2 loading model.
- **Option D or E** (mechanical hooks): higher engineering cost, may be combined with Option A/F if the model is found to resist the prose rule.

No recommendation — the engineer decides which option(s) to pursue and the scope of the change.
