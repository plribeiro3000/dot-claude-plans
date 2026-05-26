# SPIKE — Config Repo: Versioning + Proactive Capability Discovery

## Investigation questions

**Q1 — Versioning:** What versioning scheme is appropriate for the 4Shark dot-claude config repo? Is the current master + develop + semver tags via HubFlow "kind of resolved"? How do consumers know when to pull? How are breaking changes communicated?

**Q2 — Proactive capability discovery:** How can the agent be smarter about surfacing capabilities the engineer might not know exist — without making the engineer ask first? Two sub-mechanisms: (A) agent silently switches to the better output format, (B) agent tips the engineer toward a skill/agent they did not think to invoke.

---

## Sources consulted

- `~/.claude/scripts/check-claude-version.sh` — current version-check and pull-discipline mechanism; see `discoverability_excerpt_1.txt`
- `~/.claude/settings.json:58-96` — established hook injection pattern (UserPromptSubmit, SessionStart); see `discoverability_excerpt_2.txt`
- `~/.claude/scripts/inject-output-policy-reminder.sh` — minimal stateless-reminder pattern; see `discoverability_excerpt_2.txt`
- `https://github.com/mathiasbynens/dotfiles` — no versioning; continuous update model
- `https://github.com/holman/dotfiles` — no versioning; fork-and-customize model
- `https://github.com/nicknisi/dotfiles` — no versioning; living config
- `https://ulhpc-dotfiles.readthedocs.io/en/latest/contributing/versioning/` — semver with build-number suffix; only dotfiles repo found with formal versioning
- `https://code.claude.com/docs/en/settings` — official Anthropic docs; no versioning guidance for team configs; project settings commit to git and flow through standard git workflows
- `https://code.claude.com/docs/en/skills` — skill description + when_to_use field; two-stage loading; disable-model-invocation; budget overflow behavior
- `https://scottspence.com/posts/claude-code-skills-dont-auto-activate` — real-world evidence: skills do not auto-activate reliably; workaround = hook injection
- `https://arxiv.org/html/2410.04596v1` (CHI 2025) — proactive AI assistant timing; 12-18% productivity gain; overuse causes distraction; 20-second rate limit optimal; see `discoverability_excerpt_4.txt`
- `https://www.nngroup.com/articles/pop-up-adaptive-help/` — "Systems cannot predict everything, and users know it"; help should be available without interfering
- `https://www.command.ai/blog/what-clippy-taught-us-all/` — Clippy failure: shallow triggers, overeagerness, no contextual awareness
- `https://www.conventionalcommits.org/en/v1.0.0/` — BREAKING CHANGE footer; fix→PATCH, feat→MINOR, BREAKING CHANGE→MAJOR
- `https://frontside.com/blog/2022-02-09-semver-or-calver-by-project-type/` — CalVer vs SemVer by project type
- `https://gosink.in/versioning-strategies-explained-semver-to-calver-and-beyond-and-which-one-should-you-choose-2/` — CalVer better fit for internal apps; SemVer for libraries with stable APIs
- `git -C ~/.claude log --oneline --tags --decorate` — confirms single tag `0.1.0`; all subsequent work sits in `## [Unreleased]`
- See auxiliary: `versioning_data_1.csv` — comparative table across dotfiles repos and 4Shark
- See auxiliary: `discoverability_excerpt_1.txt` — annotated check-claude-version.sh showing pull-discipline gap
- See auxiliary: `discoverability_excerpt_2.txt` — annotated hook injection pattern from settings.json and inject-output-policy-reminder.sh
- See auxiliary: `discoverability_excerpt_3.txt` — verbatim quotes from official skills docs + scottspence.com finding
- See auxiliary: `discoverability_excerpt_4.txt` — verbatim quotes from CHI 2025 paper + NN/g + Clippy analysis

---

## Research Question 1 — Versioning

### Finding 1.1: No comparable dotfiles repo uses formal versioning

**Evidence:** All three canonical personal dotfiles repos (mathiasbynens, holman, nicknisi) have zero tags, no CHANGELOG, and no releases. The only dotfiles project found with formal versioning is ULHPC/dotfiles, which uses `MAJOR.MINOR.PATCH[-bN]` (build number = total commit count on master) and documents it in a contributing guide. See `versioning_data_1.csv` for the full comparison.

**Source:** GitHub pages for mathiasbynens/dotfiles, holman/dotfiles, nicknisi/dotfiles (all fetched May 2026); ULHPC readthedocs page fetched May 2026.

**Significance:** The norm for dotfiles repos is no versioning at all. 4Shark dot-claude is already more structured than all surveyed peers by having a CHANGELOG.md, HubFlow, and one semver tag. The baseline the engineer is comparing against (peer dotfiles repos) does not version at all.

---

### Finding 1.2: Anthropic provides no official versioning guidance for team config repos

**Evidence:** The official settings documentation states: "Project scope is best for: Team-shared settings (permissions, hooks, MCP servers) [...] These settings are committed to git and automatically shared with all collaborators on the repository." On update distribution: "Since project settings are committed to git, updates flow through standard git workflows (commits/pulls), but the documentation provides no guidance on rollout strategies, notification mechanisms, or version pinning for configuration changes."

**Source:** `https://code.claude.com/docs/en/settings` (fetched May 2026)

**Significance:** Anthropic's documented model is "commit to git, pull to update." There is no official concept of pinning to a config version or of a version-mismatch warning. The 4Shark `check-claude-version.sh` hook is a 4Shark-invented extension that goes beyond anything Anthropic ships.

---

### Finding 1.3: The current mechanism reports commit count, not version delta

**Evidence:** From `~/.claude/scripts/check-claude-version.sh:56-60`:

```bash
echo "Your Claude config (dot-claude) is on '${branch}'. There are ${behind} commit(s)"
echo "on origin/${branch} that you have not pulled yet."
if [[ "${branch}" == "master" ]]; then
    echo "These are tagged release updates."
```

**Source:** `~/.claude/scripts/check-claude-version.sh:56-60`

**Significance:** The check tells the engineer "N commits behind" but not "you are at version X.Y.Z, current is A.B.C" and not "here are the CHANGELOG entries you missed." The CHANGELOG's `## [Unreleased]` section (which is very large — 90+ entries) has never been cut to a versioned release after 0.1.0. So even if the version-delta message were added, it would only ever say "0.1.0 → 0.1.0" for most engineers, because no tags have been cut since.

---

### Finding 1.4: SemVer's "breaking change" definition requires a public API; the config repo has a behavioral API instead

**Evidence:** The Conventional Commits spec states: "a commit that has a footer `BREAKING CHANGE:`, or appends a `!` after the type/scope, introduces a breaking API change (correlating with MAJOR in Semantic Versioning)." SemVer 2.0.0 states: "You MUST declare a public API."

**Source:** `https://www.conventionalcommits.org/en/v1.0.0/` (fetched May 2026); `https://semver.org/` (cited in search results)

**Significance:** The config repo has no source-code API. Its "API" is behavioral: the set of rules Claude follows, the hooks that fire, the skills that are available, and the permissions granted. A "breaking change" in this context could mean: a hook is removed that engineers depended on, a permission is tightened that previously auto-approved, a rule is inverted (e.g. "always ask" flips to "never ask"), or a skill is renamed. Patch = bug fix in a hook/script. Minor = new capability added. Major = behavior that was previously guaranteed is now absent or inverted. This mapping is workable but requires the team to explicitly agree on what "breaking" means for a config repo. No existing industry guidance was found that defines this for config-only repos specifically.

---

### Finding 1.5: CalVer carries different signal than SemVer for internal tooling

**Evidence:** From the versioning strategy survey: "CalVer ties version numbers to dates rather than API changes. A common format is YYYY.MM.PATCH [...] CalVer shines for projects with predictable timelines, making it a favorite for OS releases, browsers, and enterprise software [...] SemVer is the gold standard for libraries and packages."

**Source:** `https://gosink.in/versioning-strategies-explained-semver-to-calver-and-beyond-and-which-one-should-you-choose-2/` (search result, May 2026)

**Significance:** CalVer (e.g. `2026.05.1`) signals "when it was released" rather than "what kind of change it carries." For a config repo consumed by engineers on a team, the version primarily answers "am I up to date?" — a question CalVer answers directly. SemVer answers "will this break me?" — a question that is harder to answer for a behavioral config repo without a formal breaking-change definition.

---

### Finding 1.6: The existing pull-discipline mechanism is consent-gated and fires daily

**Evidence:** From `~/.claude/scripts/check-claude-version.sh:32-33`:

```bash
MARKER="/tmp/claude_version_check_$(date +%Y%m%d).done"
[[ -f "${MARKER}" ]] && exit 0
```

And lines 82-97 show the consent notice that fires once per day, requiring the engineer to explicitly approve `git fetch` before the check runs (due to 1Password SSH popup).

**Source:** `~/.claude/scripts/check-claude-version.sh:32-33, 72-97`

**Significance:** The pull-discipline mechanism is functional but stops at "N commits behind." It does not surface what those commits contain (no CHANGELOG digest), does not tell the engineer whether any of those commits add new capabilities they could use, and does not tell them whether any are breaking. The gap between "you are behind" and "here is what you are missing" is the actionable improvement space.

---

### Options for Q1

**Option A — Status quo confirmed ("kind of resolved").**
Keep master + develop + semver tags via HubFlow. Accept that 0.x means pre-stable. Cut a new tag (0.2.0 or 1.0.0) when the Unreleased section is stable enough. Evolve `check-claude-version.sh` to also report the version delta (current tag vs. remote tag) alongside the commit count. Minimal work; consistent with engineer's hypothesis.

Trade-offs: SemVer's "breaking change" semantics are fuzzy for a config repo (no public API). Peers don't version at all, so the overhead of HubFlow releases for every batch of additions may not be worth it if the cadence is low.

**Option B — CalVer tags instead of SemVer.**
Switch to `YYYY.MM.N` (e.g. `2026.05.1`). Cut tags monthly or on meaningful milestones. The version carries date signal instead of compatibility signal. Engineers can immediately answer "am I on the current month's config?"

Trade-offs: Loses the MAJOR.MINOR.PATCH signal that distinguishes "new capability" from "breaking change." If the team cares about distinguishing those, CalVer hides it. Conventional Commits' `BREAKING CHANGE:` footer still works with CalVer for commit-level signal even without version-level signal.

**Option C — Extend the version-check script to surface CHANGELOG entries.**
Keep the versioning scheme as-is (Option A). When the script detects N commits behind, additionally extract and display new `### Added` / `### Changed` / `### Fixed` entries from the CHANGELOG between the last-pulled tag and HEAD. This answers "what am I missing?" without a scheme change.

Trade-offs: Requires CHANGELOG to be kept current between releases (currently the Unreleased section is healthy). Script complexity increases. Only works when commits are behind the tracked branch, not for engineers on develop who are current.

**Option D — Drop formal versioning; rely on git log discipline.**
Remove HubFlow release overhead. Keep CHANGELOG.md updated on every PR. Engineers pull develop, check `git log --oneline`, and read the CHANGELOG. The check-claude-version.sh script stays as-is (commit count warning).

Trade-offs: Simplest operationally. Loses the version-number anchor ("I'm on 0.2.0") that makes it easy to compare environments. The single tag `0.1.0` becomes permanently the only tag.

---

## Research Question 2 — Proactive Capability Discovery

### Finding 2.1: Sub-mechanism A (agent silently switches format) is already partially in place via hooks — the gap is reliability

**Evidence:** Three hooks already inject capability reminders on every prompt:
- `inject-output-policy-reminder.sh` — tells the agent which format to use before producing output
- `inject-code-pattern-rule.sh` — enforces code pattern before writing
- `inject-subagent-contract.sh` — enforces research-only contract before Task calls

The Output Policy rule is also in CLAUDE.md and in every session start via `read-context.sh`. The rule is: "comparative content → HTML" and "≥2 options → HTML."

**Source:** `~/.claude/settings.json:58-96`; `~/.claude/scripts/inject-output-policy-reminder.sh` (full file); see `discoverability_excerpt_2.txt`

**Significance:** The mechanism for Sub-mechanism A already exists in production. The question is whether it is reliable. The scottspence.com finding (see Finding 2.3) shows that injection does not guarantee compliance — Claude "barrels ahead" with its own goal path. But the existing pattern (hook injection + CLAUDE.md rule) is the strongest available path; no more reliable mechanism exists within current Claude Code capabilities.

---

### Finding 2.2: The "format mismatch" trigger (Sub-mechanism A) is a rule, not a decision — the ASK-DONT-DECIDE line is clear

**Evidence:** From `~/.claude/docs/ASK-DONT-DECIDE.md:23-30`:

```
What is NOT a decision (you may proceed without asking):
- Mechanical execution of an explicit instruction ("rename X to Y everywhere")
- Following a pattern that is unambiguous in the surrounding code (the file and 2-3 siblings agree)
- Following a written rule in ~/.claude/docs/ that covers the situation
```

**Source:** `~/.claude/docs/ASK-DONT-DECIDE.md:23-30`

**Significance:** "Switch to HTML when content is comparative" is covered by a written rule in `~/.claude/CLAUDE.md` § Output Policy. By the ASK-DONT-DECIDE principle, this is NOT a design decision — it is mechanical rule-following. The agent should silently switch and not ask. The only open question is whether the agent reliably does so. The format-mismatch trigger (Sub-mechanism A) does not require the engineer to be asked; it requires the agent to execute.

---

### Finding 2.3: Skill auto-invocation is unreliable in practice; hook injection is the reliable path

**Evidence:**
- From scottspence.com: "Spoiler: they don't [auto-activate]." "Claude is so goal focused that it barrels ahead with what it thinks is the best approach." The documented workaround: inject explicit instructions via a hook: `"INSTRUCTION: Use Skill(research) to handle this request with source verification."`
- From official docs: "If a skill seems to stop influencing behavior after the first response, the content is usually still present and the model is choosing other tools or approaches. Strengthen the skill's `description` and instructions so the model keeps preferring it, or use hooks to enforce behavior deterministically."

**Source:** `https://scottspence.com/posts/claude-code-skills-dont-auto-activate` (fetched May 2026); `https://code.claude.com/docs/en/skills` (fetched May 2026); see `discoverability_excerpt_3.txt`

**Significance:** The skill `description` + `when_to_use` fields are the official discoverability mechanism, but they are not reliable for auto-invocation. The hook-injection pattern (already used in 4Shark for code-pattern, output-policy, and subagent-contract) is the mechanically reliable path. Sub-mechanism B (surfacing "we have a skill for this") would follow the same hook pattern.

---

### Finding 2.4: Proactive tips improve outcomes only when rate-limited and context-matched; unconditional per-prompt injection is the Clippy anti-pattern

**Evidence:**
- CHI 2025 research: "when a proactive assistant provides too many suggestions, participants can be easily distracted [...] when the suggestions are provided too often, participants are less likely to make use of the suggestions." Only 45% preferred the aggressive (5-second) interval vs. 80-90% for the moderated version.
- Clippy failure: "Clippy's number-one problem was overeagerness [...] offer writing tips or formatting help based on shallow triggers, not actual user intent."
- NN/g: "help should be 'Available without interfering' and remain 'out of the way until users need it'"

**Source:** `https://arxiv.org/html/2410.04596v1` (CHI 2025, fetched May 2026); `https://www.command.ai/blog/what-clippy-taught-us-all/` (search result); `https://www.nngroup.com/articles/pop-up-adaptive-help/` (fetched May 2026); see `discoverability_excerpt_4.txt`

**Significance:** Three hooks already fire unconditionally on every UserPromptSubmit in 4Shark. Adding a fourth unconditional hook ("did you know we have /pr-triage?") increases the risk of desensitization. The effective pattern from the CHI research is: rate-limit + context-match. "Rate-limit" in Claude Code terms = SessionStart only (not every prompt). "Context-match" = the hook inspects the prompt and only fires when there is a signal match.

---

### Finding 2.5: The `when_to_use` skill field plus `disable-model-invocation: false` is the documented path for Sub-mechanism B

**Evidence:** From official skills docs:
"when_to_use: Additional context for when Claude should invoke the skill, such as trigger phrases or example requests."
"In a regular session, skill descriptions are loaded into context so Claude knows what's available, but full skill content only loads when invoked."
"disable-model-invocation: true — Set to true to prevent Claude from automatically loading this skill."

**Source:** `https://code.claude.com/docs/en/skills` (fetched May 2026); see `discoverability_excerpt_3.txt`

**Significance:** For Sub-mechanism B (engineer doing something manually that a skill handles), the official path is: ensure the skill's `description` and `when_to_use` contain the trigger phrases, and leave `disable-model-invocation` as `false` (the default). Claude should then notice the match and suggest or invoke the skill. The real-world reliability gap (Finding 2.3) means this alone is insufficient — a complementary hook may still be needed for high-value skills.

---

### Finding 2.6: A SessionStart CHANGELOG digest hook is technically feasible with the existing infrastructure

**Evidence:**
- `check-claude-version.sh` already uses `git -C "${CLAUDE_DIR}" rev-list --count "HEAD..origin/${branch}"` and a `/tmp` marker file (lines 32-33, 47).
- `read-context.sh` (SessionStart) already surfaces CHANGELOG.md content indirectly via Tier 2 pointers.
- `inject-output-policy-reminder.sh` shows the minimal additionalContext injection pattern.
- LaunchDarkly session-start hook pattern: "instructions are automatically added to your context on session start" by querying an external source and returning additionalContext.

**Source:** `~/.claude/scripts/check-claude-version.sh:32-33, 47`; `~/.claude/scripts/inject-output-policy-reminder.sh` (full file); `https://github.com/launchdarkly-labs/claude-code-session-start-hook` (fetched May 2026)

**Significance:** A "since your last session" CHANGELOG digest could be implemented as: a SessionStart hook that reads the CHANGELOG.md, extracts the most recent N entries from `## [Unreleased]` (or since the last tag), and injects them as a brief additionalContext block. This is a bottom-up discovery trigger — surfaces new capabilities at session start without requiring the engineer to ask. The token cost is the main constraint: the Unreleased section is currently 90+ entries. The hook would need to either cap the output or extract only the last N PRs.

---

## Trade-offs surfaced

### Q1 — Versioning

| Approach | Pros | Cons | Source |
|---|---|---|---|
| A: Status quo (semver + HubFlow, cut tags more frequently) | Consistent with existing setup; angular commits already follow semver signals; BREAKING CHANGE footer works | Breaking-change semantics fuzzy for config repo; overhead of HubFlow per batch | `git log` + conventional commits spec |
| B: Switch to CalVer | Immediately answers "am I current?"; no need to define breaking-change boundary | Loses MAJOR/MINOR/PATCH compatibility signal; Conventional Commits' BREAKING CHANGE footer still works but version number doesn't reflect it | CalVer research sources |
| C: Extend version-check script to surface CHANGELOG entries | High engineer value ("what am I missing?"); no scheme change | Script complexity; only works when behind; Unreleased section may need trimming | `check-claude-version.sh` analysis |
| D: Drop formal versioning; git log + CHANGELOG discipline | Simplest; no release overhead | Loses version anchor; engineers cannot compare environments by version number | Dotfiles peer survey |

### Q2 — Capability Discovery

| Mechanism | Pros | Cons | Source |
|---|---|---|---|
| A1: Improve existing Output Policy hook (more specific trigger phrases) | Already in production; no new infrastructure | Does not guarantee compliance; relies on model following the injected rule | inject-output-policy-reminder.sh + scottspence.com |
| A2: Convert Output Policy rules to a skill with `when_to_use` field | Official documented path; skill descriptions in context; auto-invocation when matched | Real-world auto-activation is unreliable (scottspence.com); still needs hook backup | skills docs |
| B1: Add `when_to_use` to existing skill/agent descriptions | Zero new infrastructure; improves natural language matching | Reliability gap per Finding 2.3; Claude barrels ahead | skills docs + scottspence.com |
| B2: Conditional UserPromptSubmit hook (inspect prompt → inject skill tip when matched) | Mechanically reliable (hook is deterministic); targeted, not every prompt | Keyword collision maintenance; scales poorly with many skills; shallow-trigger Clippy risk | scottspence.com workaround |
| B3: SessionStart CHANGELOG digest hook | Low noise (once per session); surfaces new capabilities at natural break point; consistent with LaunchDarkly pattern | Token cost of large Unreleased section; does not know what engineer has "already seen" | check-claude-version.sh + LaunchDarkly hook |
| B4: Passive discoverability: dedicated CAPABILITIES.md + improved README | Zero noise; engineer pulls when ready; always accurate | Requires engineer to seek it; does not proactively surface; current README + CLAUDE.md partially serve this | peer survey (none of surveyed repos have this but ULHPC has contributing guide) |

---

## What remains uncertain

1. **What is "breaking" for a config repo?** No industry definition was found for breaking changes in a behavioral config-only repository. The team would need to define this before semver MAJOR bumps carry meaningful signal. Examples that might qualify: removing a hook, tightening a permission that was previously auto-approved, removing a command/skill, renaming a slash command. Examples that probably do not qualify: adding new docs, adding new skills, changing CLAUDE.md prose.

2. **Token budget impact of additional hooks.** Three unconditional UserPromptSubmit hooks already fire. The current total additionalContext injected per prompt is not measured in the codebase. Adding a fourth hook — whether for capability tips or CHANGELOG digest — increases context size per turn. The exact cost depends on message length. This was not measured during this spike.

3. **Session-to-session state tracking.** The CHANGELOG digest approach (Finding 2.6) would ideally surface only entries "since your last session." The existing check-claude-version.sh uses a daily `/tmp` marker, which is coarse. A finer-grained "last seen commit" marker (e.g., written to `~/.claude/memory/last-seen-commit.txt` at session end) would enable precise "new since you last pulled" digests, but no SessionEnd hook exists in the current `settings.json` to write it.

4. **Skill auto-invocation reliability for the existing 4Shark agents.** The scottspence.com finding applies to skills, but the 4Shark agent corpus uses the `agents/` directory (subagents), not `skills/`. The auto-invocation reliability question for agents vs. skills was not directly tested or documented separately in the sources found.

5. **Whether the Unreleased CHANGELOG section should be cut before adding version-delta surfacing.** The script in Option C (Finding 1.6) would surface Unreleased entries as "new since 0.1.0" — but the Unreleased section has 90+ entries spanning potentially months of work. Surfacing all of them at once would be overwhelming. This implies that CHANGELOG digest surfacing is only useful after the Unreleased work is cut into versioned sections (i.e., a 0.2.0 or 1.0.0 release).

---

## Suggested options for main and the engineer

### Q1 — Versioning

- **Option A (status quo + more frequent tags):** Keep semver + HubFlow. Define the team's behavioral breaking-change criteria (what constitutes a MAJOR vs. MINOR for a config repo). Cut a 1.0.0 when the Unreleased section stabilizes. Extend `check-claude-version.sh` to show version delta alongside commit count. Hypothesis: "kind of resolved" confirmed — the infrastructure is correct, the gap is just that tags haven't been cut.

- **Option B (CalVer):** Switch to `YYYY.MM.N`. Simpler to answer "am I current?", no need to define breaking-change semantics. Loses MAJOR/MINOR signal.

- **Option C (extend version-check for CHANGELOG digest):** Keep versioning as-is. Add a CHANGELOG digest to the existing script so engineers see "what changed" not just "N commits behind." Contingent on first cutting a new release (Unreleased → versioned).

- **Option D (drop formal versioning):** Remove HubFlow overhead. Rely on CHANGELOG + git log. Simplest, consistent with all peer dotfiles repos.

### Q2 — Proactive Capability Discovery

- **Sub-mechanism A:** Strengthen the existing `inject-output-policy-reminder.sh` with more explicit trigger phrases (e.g., "if you are about to produce a comparison or list of findings: use HTML"). No new infrastructure. This tightens rule-following without adding noise.

- **Sub-mechanism B, lower-noise path:** Add `when_to_use` fields to the descriptions of high-value agents and skills (especially those the engineer is least likely to know about: `/pr-triage`, `@agent-spike`, `/create-integrator`). This is zero-overhead and uses the official mechanism. Accept that it is not 100% reliable and that engineers can always invoke directly via `/skill-name`.

- **Sub-mechanism B, higher-coverage path:** Add a conditional UserPromptSubmit hook that inspects the prompt for signals matching a specific skill and injects a one-line tip. Limit to 2-3 high-value skills to avoid Clippy risk. Rate-limit to once per session per skill (marker file).

- **Sub-mechanism B, session-start digest:** Add a SessionStart hook that extracts the last N entries from CHANGELOG.md `## [Unreleased]` and injects them as "recent additions to your config." Contingent on Unreleased being cut to versioned releases first so "recent" is bounded.

(NO recommendation — surface options, let main and the engineer choose)
