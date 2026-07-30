# SPIKE — Claude Code CLI Permissions Management Hygiene

## Investigation question

The engineer reported (verbatim, pt-BR):

> "Ao iniciar `claude --resume <id>`, o CLI cospe DEZENAS de linhas do tipo: `Permission
> allow rule (.claude/settings.json): Write(**) is not matched by file permission checks
> — only Edit(path) rules are. Use Edit(**) instead (Edit rules cover all file-editing
> tools).` e o equivalente para `Glob(**)` → `Read(**)`, e para dezenas de regras `deny`
> do tipo `Write(./**/*.pem)`, `Write(~/.ssh/**)` etc."
>
> "As mesmas mensagens aparecem DUPLICADAS (o bloco inteiro de allow e o bloco inteiro de
> deny aparecem duas vezes na saída)."
>
> "A hipótese do engenheiro: quando ele responde ao prompt de permissão escolhendo a opção
> 'não perguntar mais' (a tecla 2 / 'Yes, and don't ask again'), o Claude Code sai
> ESCREVENDO regras num arquivo de settings sem curadoria — acumulando entradas
> duplicadas, redundantes e desnecessárias, e agora isso está conflitando/gerando
> warnings. Ele também esperava que 'allow' fosse escopado À SESSÃO, não permanente."
>
> "O problema acontece com mais de um engenheiro da equipe (não é máquina específica)."

Six sub-questions were posed, reproduced in the Findings below in the same order:
(1) the current permission-rule syntax contract and which tools accept path specifiers;
(2) where "don't ask again" writes rules, the settings-file precedence, and whether the
choice is session-scoped or permanent; (3) the root cause of the duplicated warning
block; (4) the sanctioned way to audit/clean accumulated rules; (5) what the community
does to prevent the allow-list from becoming clutter; (6) whether a session-only
permission-grant mechanism exists or is requested.

## Sources consulted

- [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) — the canonical rule-syntax contract, the Edit(path)/Read(path)-only file-permission check, the hooks-as-alternative section. See auxiliary `permissions-hygiene_doc_1.txt`.
- [code.claude.com/docs/en/settings](https://code.claude.com/docs/en/settings) — settings-file hierarchy, `settings.local.json` semantics and its v2.1.211 relocation. See auxiliary `permissions-hygiene_doc_2.txt`.
- [raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md) — confirms the exact version (2.1.210) the startup warning was added, and the exact version (2.1.211) the repo-root save location was introduced. See auxiliary `permissions-hygiene_log_1.txt`.
- GitHub Issues API (`gh api repos/anthropics/claude-code/issues/<n>`), 15 issues fetched directly and state-verified, not taken from search summaries. See auxiliary `permissions-hygiene_data_1.md`.
- [news.ycombinator.com/item?id=47343927](https://news.ycombinator.com/item?id=47343927) — "Show HN: A context-aware permission guard for Claude Code", community discussion of allow-list scaling problems.
- Local read-only inspection of this machine's `~/.claude/settings.json` and `~/.claude/settings.local.json` (`claude --version`, `jq` counts). See auxiliary `permissions-hygiene_data_2.txt`.

## Findings

### Finding 1: The Edit(path)/Read(path)-only file-permission-check contract — confirmed, but contested by two currently open bugs

**Evidence:** From the official docs (2.1.210+):

> "The file permission checks match only `Edit(path)` and `Read(path)` rules. A
> `Write(path)`, `NotebookEdit(path)`, or `Glob(path)` rule is accepted but never matched
> by those checks, so Claude Code warns at startup for each allow, deny, or ask rule in
> one of these unmatched forms. Use `Edit(docs/**)` in place of `Write(docs/**)` or
> `NotebookEdit(docs/**)`, and `Read(docs/**)` in place of `Glob(docs/**)`."

Confirmed independently in the CHANGELOG at the exact version cited:

> "## 2.1.210 [...] Added a startup warning for `Write(path)`, `NotebookEdit(path)`, and
> `Glob(path)` permission rules — use `Edit(path)` or `Read(path)` instead"

So the message the engineer saw is not a bug in itself — it is the documented, versioned
behavior, and the exact wording the engineer quoted matches the docs' own example
warning almost verbatim (docs example: `Write(docs/**) is not matched by file permission
checks — only Edit(path) rules are. Use Edit(docs/**) instead (Edit rules cover all
file-editing tools)`).

However, two issues opened in the last four days before this spike (both still OPEN as
of the `gh api` check) show the community currently cannot get a consistent answer from
Claude Code's own tooling about this same contract:

- **#81170** (opened 2026-07-25): the engineer got the startup warning telling them to
  use `Edit(path)` only, then ran `/doctor`, which recommended the *opposite* — re-adding
  the `Write(path)` rule alongside `Edit(path)`. Quoted from the issue: "I've now had this
  flagged both ways across separate sessions, with no way to verify which claim about the
  permission engine is actually true."
- **#75315** (opened 2026-07-07, reproduced on 2.1.186/187/198/202): a distinct, deeper
  bug — a path-scoped `Write(...)` **allow** rule does not just get a deprecation warning,
  it **silently denies every matching call**, with no error, no prompt, `is_error: false`
  in headless mode. Quoted: "Path-scoped `Write(...)` allow rules are accepted without
  any warning but never match, so every `Write` tool call they were meant to allow is
  denied." The reporter measured this across four CLI versions and concluded "the form
  appears to have never matched" — i.e. this is not a regression introduced by the
  2.1.210 warning, it may predate it.
- **#80893** (opened 2026-07-24, on 2.1.218): reports that on their setup, `deny` and
  `ask` rules have **no effect at all** on Write/Edit/Read tools — files are written
  silently regardless of rule configuration, tested with both `Write(...)` and
  `Edit(...)` syntax as the rule form.

**Source:** https://code.claude.com/docs/en/permissions (see `permissions-hygiene_doc_1.txt`); https://github.com/anthropics/claude-code/issues/81170; https://github.com/anthropics/claude-code/issues/75315; https://github.com/anthropics/claude-code/issues/80893
**Significance:** the documented contract answers the engineer's literal question — yes,
only `Edit(path)`/`Read(path)` are matched by file-permission checks since 2.1.210, and
"Edit rules cover all file-editing tools" is the docs' own wording, not a paraphrase.
But the contract is not settled in practice: independent, currently open reports say the
engine's actual enforcement of `Write`/`Edit`/`Read`/deny/ask rules is inconsistent
across at least three distinct failure shapes, filed within the same week as this spike.
**Verification:** URL fetched (both pages, plus one re-fetch of the settings page for
self-check) / Verbatim quote checked against the full persisted page text via the Read
tool / Quote substrings confirmed at the line numbers recorded in `permissions-hygiene_doc_1.txt`. GitHub issue bodies fetched directly via `gh api`, not via search-summary paraphrase (see the #57346 mismatch documented in `permissions-hygiene_data_1.md`).

### Finding 2: File-modification "don't ask again" is documented as session-only and is never written to any settings file — this appears to contradict the engineer's hypothesis

**Evidence:** The docs' tiered permission table states, verbatim:

| Tool type | Example | Approval required | "Yes, don't ask again" behavior |
|---|---|---|---|
| Read-only | File reads, Grep | No | N/A |
| Bash commands | Shell execution | Yes, except read-only commands | **Permanently per repository and command** |
| File modification | Edit/write files | Yes | **Until session end** |

And, explaining the mechanism directly:

> "When you choose 'Yes, don't ask again' and the approval saves permanently, such as for
> a Bash command, Claude Code saves the rule to `.claude/settings.local.json` at the root
> of the git repository [...] A file-modification approval isn't saved to the file: as
> the table shows, it lasts until the session ends."

**Source:** https://code.claude.com/docs/en/permissions, lines 15-21 (see `permissions-hygiene_doc_1.txt`)
**Significance:** per the current docs, choosing "don't ask again" on an **Edit/Write**
prompt is *already* scoped to the session and is never persisted anywhere — the exact
behavior the engineer said he expected. What IS persisted permanently is the **Bash**
"don't ask again" choice, and it is written to `.claude/settings.local.json` at the git
repository root (not to the shared `~/.claude/settings.json`), scoped per-repository —
confirmed by the local audit: this machine's personal `~/.claude/settings.local.json`
holds 181 accumulated Bash-shaped allow entries and zero unmatched-shape (Write/Glob)
rules (see `permissions-hygiene_data_2.txt`), which is consistent with the doc's
description of what that file accumulates.
This means the 23 unmatched-shape `Write()`/`Glob()`/`NotebookEdit()` rules found in this
machine's *shared* `~/.claude/settings.json` (3 allow-side, 20 deny-side — see
`permissions-hygiene_data_2.txt`) cannot be the product of an engineer pressing "don't
ask again" on a file edit, because that choice is documented as never persisting to any
file. Combined with 4Shark's own documented practice that changes to the shared,
version-controlled `settings.json` go through an explicit PR (`~/.claude/CLAUDE.md` §
"Configuration Changes Policy": *"An allow-list change [...] is a config decision the
engineer makes, not the agent [...] through a dot-claude PR"*), the more consistent
explanation is that these are **rules deliberately curated over time** by the team,
written before the engine's Edit(path)-only matching took effect (2.1.210) or before
their author knew about it, and never migrated since — a state directly evidenced by
Finding 4 (no auto-migration tool exists).
**Verification:** URL fetched / Verbatim quote checked against the persisted page text /
Quote substring confirmed at lines 15-21 and line 21 of the fetched permissions page. The
changelog search for a version where this "until session end" behavior was introduced or
changed came back empty (see `permissions-hygiene_log_1.txt`) — marked as an open question
below, not asserted as a fact with a version number.

### Finding 3: The exact "duplicated block" behavior was not found in any filed issue — Not found

**Evidence:** A local dedup check on this machine's `~/.claude/settings.json`
(`jq ... | sort | uniq -d`) returned **empty** — there are no literal duplicate rule
strings inside the file. Whatever produces the doubled block of warnings in the
engineer's terminal output is not a data-duplication problem in the settings file itself.
A targeted GitHub issue search for the specific behavior (same warning block twice on one
`claude --resume` startup) returned no matching issue. A related but distinct bug
CLASS does recur in Claude Code's history — output being rendered twice for unrelated
UI elements — evidenced by four issues, all CLOSED: #29069 ("Bash tool timeout error
message is printed twice"), #20760 ("/context usage stuck at 0% [...] + output printed
twice"), #20488 ("/context command output prints twice"), #1858 ("The task planning tool
is duplicating the output in the terminal twice").
**Source:** local `jq` inspection (this session); `gh api search/issues` queries for
"printed twice" / duplicate + startup + permission (see `permissions-hygiene_data_1.md`)
**Significance:** the settings data itself is not duplicated, so a fix would not be
"remove the duplicate lines from settings.json" — there is nothing to remove there. The
recurring "prints twice" bug class in unrelated parts of the CLI is circumstantial
evidence that this shape of defect (some rendering path double-emitting the same output)
has precedent in this codebase, but this spike found no issue confirming that mechanism
applies to the permission-rule startup warnings specifically. This is an honest gap, not
a resolved finding.
**Verification:** URL fetched (GitHub search API) / no matching issue existed to quote,
so no quote is claimed / the four cited "prints twice" issues were each individually
state-checked via `gh api` and confirmed CLOSED (see `permissions-hygiene_data_1.md`).

### Finding 4: No official tool exists to migrate or deduplicate accumulated rules — two feature requests, both open, ask for exactly this

**Evidence:** `/permissions` is the one sanctioned management surface documented today:

> "You can view and manage Claude Code's tool permissions with `/permissions`. This UI
> lists all permission rules and the `settings.json` file each rule comes from."

But `/permissions` cannot write to the shared/user-scope file at all — confirmed by an
issue opened the day before this spike (#81956, 2026-07-28, OPEN): *"`/permissions`
currently only reads all scopes but writes exclusively to the current repo's
`.claude/settings.local.json` — there's no way to target the global
`~/.claude/settings.json` through the UI [...] the only way to add or edit a global
permission rule is to hand-edit `~/.claude/settings.json` directly."*
There is no automatic `Write(path)` → `Edit(path)` migration. A feature request for
exactly this (#78817, 2026-07-18, OPEN) states: *"Deprecated Write(<path>) permission
rules written into settings.json by older Claude Code versions are not auto-migrated on
update. They silently stop matching [...] so the user gets a per-session 'Fix:' notice
but has to edit settings.json by hand. Please auto-migrate Write(path) -> Edit(path)
(with dedup) during settings migration, instead of only showing a warning."*
A broader request for a general hygiene/audit command (#74705, 2026-07-06, OPEN)
confirms no built-in audit exists today: *"There's no single command that audits
everything and recommends cleanup [...] I've built this as a personal skill
(.claude/skills/session-hygiene/SKILL.md) which works well, but it would benefit all
users as a built-in."*
**Source:** https://code.claude.com/docs/en/permissions (`/permissions` description);
https://github.com/anthropics/claude-code/issues/81956; https://github.com/anthropics/claude-code/issues/78817; https://github.com/anthropics/claude-code/issues/74705
**Significance:** as of this spike, cleaning up the 23 unmatched-shape rules in the
shared `~/.claude/settings.json` (Finding 2) requires a manual, hand-edited fix (find
each `Write(path)`/`Glob(path)`/`NotebookEdit(path)` rule and replace it with the
equivalent `Edit(path)`/`Read(path)` form, watching for the depth-matching differences
the docs describe between allow rules and deny/ask rules on single-segment directory
patterns) — there is no command or script, official or third-party-but-verified, that
does this automatically.
**Verification:** URL fetched (3 issues + docs page) / Verbatim quote checked against
each issue's raw `body` field returned by the GitHub API / Quote substrings confirmed
directly in the JSON responses saved during this session (see `permissions-hygiene_data_1.md`).

### Finding 5: One verified community strategy — deterministic PreToolUse-hook classification instead of a hand-maintained allow-list

**Evidence:** From a Hacker News discussion of a third-party tool ("nah") built as a
PreToolUse hook classifier for Claude Code, commenter schipperai stated (confirmed via a
second, independent re-fetch of the same page — self-check passed):

> "Claude Code's permission system is allow-or-deny per tool, but that doesn't really
> scale."

and, on maintaining a deny-list specifically:

> "Maintaining a deny list is a fool's errand."

The same source reported that the deterministic classification layer of their tool
handled "about 95% of inputs with zero latency/tokens over 13.5k tool calls" without
prompting — i.e., the strategy replaces a growing static allow-list with a runtime
classifier hook, which is the same mechanism 4Shark's own docs describe as the sanctioned
escape hatch: *"To run all Bash commands without prompts except for a few you want
blocked, add 'Bash' to your allow list and register a PreToolUse hook that rejects those
specific commands"* (code.claude.com/docs/en/permissions, "Extend permissions with
hooks" section).
**Source:** https://news.ycombinator.com/item?id=47343927 ("Show HN: A context-aware
permission guard for Claude Code"); https://code.claude.com/docs/en/permissions
**Significance:** this is one verified community data point, not a consolidated
"industry practice" — a search for other community sources (blog posts on
petefreitag.com, a generalanalysis.com security guide) did not turn up quotable, directly
confirmed statements about periodic allow-list review or explicit avoidance of "don't ask
again" as a stated practice; those candidate claims were dropped per the quote-or-drop
rule rather than asserted from a paraphrased search summary. **The one relevant practice
already documented and followed internally** (not "community", but worth recording
alongside this Finding since it addresses the same question) is in 4Shark's own
`~/.claude/CLAUDE.md`, § "Configuration Changes Policy": settings.json is version
controlled and changed only via an explicit PR on the engineer's go-ahead, and
`settings.local.json` is personal/gitignored — i.e., strategies (a) and (e) from the
engineer's question are already 4Shark's standing practice, independent of any external
community source.
**Verification:** URL fetched (HN page), fetched twice (self-check) / Verbatim quotes
checked on both fetches, matched exactly / Quote substrings confirmed on the second,
independent fetch of the same URL.

### Finding 6: A session-only permission scope is requested for Bash-type approvals — not yet shipped; the CLI file-modification behavior is already session-only per Finding 2

**Evidence:** the engineer's expectation ("ele também esperava que 'allow' fosse escopado
À SESSÃO, não permanente") is already the documented CLI behavior for File-modification
approvals (Finding 2) but explicitly is NOT the behavior for Bash approvals, which the
docs state save "Permanently per repository and command." A feature request search found
issue #48479, titled "[FEATURE] Add 'Allow for Session' permission option to Claude Code
Desktop," reportedly open, asking for exactly a session-scoped grant option distinct from
permanent allow, and reportedly noting the VS Code extension already exposes this choice
while the Desktop app does not.
**Source:** https://github.com/anthropics/claude-code/issues/48479
**Significance:** UNVERIFIED — this issue's state and body were obtained via a WebSearch
summary in this session; two direct `gh api` calls issued to confirm it returned no
output and were not re-attempted before the spike's time-box closed. Per the citation
discipline governing this spike, an UNVERIFIED finding may not sustain a firm conclusion.
What CAN be asserted with full verification (Finding 2) is that file-edit "don't ask
again" is already session-scoped today in the CLI; whether an equivalent session-scope
option is coming for Bash approvals, or for the Desktop app specifically, remains
unconfirmed pending a direct API check of #48479.
**Verification:** URL NOT independently re-fetched via `gh api` in this session / quote
attribution above is qualified as UNVERIFIED for exactly this reason, per Citation
Discipline rule 4.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Hand-edit the shared `~/.claude/settings.json` to replace the 23 unmatched-shape rules with `Edit(path)`/`Read(path)` equivalents | Removes the startup warnings; aligns with the documented, versioned contract (Finding 1) | Manual, error-prone given the allow-vs-deny/ask depth-matching difference the docs describe for single-segment directory patterns; no official tool assists (Finding 4) | `permissions-hygiene_doc_1.txt` |
| Replace some/all broad allow rules with a PreToolUse hook classifier | Scales better than a growing static list per one community report (95% deterministic classification with no prompts); sanctioned by the docs' own "Extend permissions with hooks" section | Requires building/maintaining the hook logic; only one community data point found, not a consolidated practice (Finding 5) | Finding 5 |
| Wait for official tooling (`/permissions` global-scope write, auto-migration, or a hygiene/audit command) | No manual work; matches how the underlying rules are structured | All three are open feature requests as of this spike, not shipped (Finding 4) | Finding 4 |

## What remains uncertain

- The exact mechanism producing the duplicated allow/deny warning block on `claude
  --resume` was not found in any filed issue (Finding 3) — marked Not found rather than
  guessed.
- Whether "file-modification approval lasts only until session end" is new-in-2.1.210
  behavior or long-standing, undocumented-by-version behavior could not be determined from
  the CHANGELOG (Finding 2) — the search across the full 5248-line file found no entry
  describing this specific persistence rule at any version.
- Issue #48479 ("Allow for Session" for Desktop) and #22292 ("Persistent permission
  preferences across sessions") were not independently re-verified via `gh api` in this
  session — their state should be confirmed before being relied on (Finding 6).
- Whether the three currently-open enforcement bugs found under Finding 1 (#81170,
  #75315, #80893) are related to each other or are three independent defects in the same
  area of the permission engine is not established — each was filed by a different
  reporter with a different reproduction, and none cross-references a common root cause
  beyond #80893 citing #75315 as a possible (but tested-and-ruled-out) explanation for its
  own symptom.

## Suggested options for main and the engineer

- **Option A** — hand-edit the 23 unmatched-shape rules in the shared `~/.claude/settings.json`
  to their `Edit(path)`/`Read(path)` equivalents via the normal dot-claude PR workflow
  (per 4Shark's own Configuration Changes Policy), which would silence the startup
  warnings regardless of what causes them to print twice. Grounded in Finding 1, Finding 2,
  and the local audit in `permissions-hygiene_data_2.txt`.
- **Option B** — leave the rules as-is for now and treat the startup warnings as cosmetic
  noise, given that three separate open bugs (Finding 1) suggest the underlying
  file-permission engine's enforcement is not fully stable in the current version line
  regardless of rule syntax chosen.
- **Option C** — investigate replacing some of the broad `Write(**)`/`Glob(**)` and the
  20 secrets-path deny rules with a PreToolUse hook (per Finding 5 and the docs' own
  "Extend permissions with hooks" section), which would sidestep the Edit/Write/Glob/Read
  matching question entirely for the rules it covers.
- **Option D** — file or upvote the existing open feature requests (#78817 auto-migration,
  #74705 hygiene audit, #81956 global `/permissions` scope) rather than building tooling
  in-house, since all three ask for the exact capability the engineer's question 4 sought.

(No recommendation — surface options, let main and the engineer choose.)
