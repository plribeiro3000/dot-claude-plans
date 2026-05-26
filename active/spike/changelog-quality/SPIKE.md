# SPIKE — Changelog Quality: Best Practices, Philosophy, and Evidence

**Conducted by:** Claude (research agent)
**Date:** 2026-04-13
**Status:** Research complete — pending decisions

---

## Goal

What standard practices, philosophies, and evidence exist for writing high-quality changelogs?

Specifically:
1. What do authoritative sources say about what belongs in a changelog?
2. What is the relationship between changelog entries and semantic versioning?
3. How do leading open-source projects write their entries?
4. What is the "user-facing vs developer-facing" distinction?
5. Does any evidence support the "state vs behavior" and "past tense as historical record" framing?
6. What anti-patterns are documented?

Context: the 4Shark team wants to update its changelog documentation to enforce entries that capture what code cannot convey — motivation, user impact, and business context — rather than technical implementation details.

---

## Method

- Web research on keepachangelog.com, common-changelog.org, semver.org, and related sources
- Full-text fetch of primary sources (the actual specification pages, not summaries)
- Review of real project changelogs (Rails ActiveRecord, Shopify, GitLab, Stripe)
- Review of community debates about tense and format (GitHub issues on olivierlacan/keep-a-changelog)
- Review of dissenting positions (conventional changelogs critique, auto-generation critique)

---

## Evidence

### Theme 1: The Foundational Principle — Changelogs Are for Humans, Not Machines

The single most repeated statement across every primary source is identical:

> "Changelogs are for humans, not machines."

— keepachangelog.com v1.1.0 (https://keepachangelog.com/en/1.1.0/)
— common-changelog.org (https://common-changelog.org/)

Olivier Lacan, creator of Keep a Changelog, frames the purpose as empathy:

> "If you keep a changelog and you do that often and regularly, you're actually saving yourself the hassle of having to deal with people who misunderstand."

Source: Changelog podcast interview with Lacan (https://changelog.com/podcast/127)

Lacan's vision: a curated, chronologically ordered list of **notable** changes. The word "notable" is load-bearing — it implies curation, not transcription.

---

### Theme 2: Commit Logs Are Not Changelogs

Every authoritative source explicitly warns against treating git history as a changelog.

Keep a Changelog (https://keepachangelog.com/en/1.1.0/):
> "Using commit log diffs as changelogs is a bad idea: they're full of noise."

Common Changelog (https://common-changelog.org/):
> "Commits document steps in source code evolution; changelogs communicate impact to end users."

The distinction is audience-driven. Engineers writing commit messages write for other engineers. Changelog readers are people deciding whether to upgrade, understanding what broke, or learning what's new.

Sophia Willows (https://sophiabits.com/blog/conventional-changelogs-suck) extends this:
> "Commit messages are an internal-facing log of what changed. The target audience of any commit message you author are the other engineers on your team. Your customers do not care about these granular details."

This is why auto-generated changelogs (from tools like conventional-changelog) produce entries that look coherent but communicate nothing to end users — they are commit logs with better formatting, not changelogs.

---

### Theme 3: What a Changelog Entry Must Answer

Multiple sources converge on the same set of questions every entry must answer:

**AnnounceKit** (https://announcekit.app/guides/how-to-write-a-changelog):
1. What changed?
2. Who does it affect?
3. Why should they care?

**Mintlify** (https://www.mintlify.com/blog/five-changelog-principles-from-best-developer-brands):
> "Rather than 'Fix async loop timing,' write 'Fix dashboard freezes during large report generation' to show the user benefit."

**UserGuiding** (https://userguiding.com/blog/changelog-best-practices):
> "Write titles from the user's perspective, not the developer's. Instead of 'Improved threading API support,' write 'Schedule threads on Twitter.'"

The pattern: the code tells you *what* changed. The changelog tells you *why it matters to you as a user*.

---

### Theme 4: What the Code Cannot Show — The Unique Value of a Changelog

This is the most important theme for the 4Shark policy.

A code diff shows file changes. It cannot show:
- **Why** the decision was made
- **Who** is affected and how
- **What problem** was being solved
- **What the user experienced** before the fix
- **Business context** — market conditions, client requests, incident response

ProductLogic.org (https://productlogic.org/2021/06/07/lets-change-changelogs/) articulates this directly:
> "Traditional changelogs fail to capture the broader narrative of change. They omit context and causation (why changes were made), outcomes and learning, and external factors."

WorkOS (https://workos.com/blog/what-makes-a-good-changelog):
> "A changelog serves as a direct communication channel between product teams and users... it conveys transparency and builds user connection to the product's evolution."

Anne-Mieke Bovelett, writing for WordPress Developer Blog (https://developer.wordpress.org/news/2025/11/the-importance-of-a-good-changelog/):
> "Changelogs represent institutional memory, helping future developers and contributors understand project history and rationale."

The changelog preserves the *context around* the code, not just the code itself. This is information that disappears if not written down at the moment of the change.

---

### Theme 5: User-Facing vs Developer-Facing — What Belongs and What Does Not

GitLab maintains the clearest written policy (https://docs.gitlab.com/development/changelog/):

**Requires a changelog entry:**
- User-facing changes of any kind
- Performance improvements visible to users
- REST and GraphQL API changes
- Security fixes

**Does NOT require a changelog entry:**
- Developer-facing changes (refactoring, technical debt, test suite)
- Documentation-only changes
- Changes behind a feature flag (entry added when flag is removed)
- Regressions fixed within the same release cycle

GitLab's transformation examples:
- ❌ "Go to a project order" → ✅ "Show starred projects at dropdown top"
- ❌ "Strip out nils in Commit objects" → ✅ "Fix 500 errors from garbage-collected commits in search"
- ❌ "Copy (some text) to clipboard" → ✅ "Update tooltip indicating copy content"

The pattern: remove implementation language, add user-visible impact.

Sophia Willows (https://sophiabits.com/blog/conventional-changelogs-suck) recommends using towncrier-style "news fragments" — separate files per change, written in user language — to enforce this separation structurally.

---

### Theme 6: Good vs Bad Entries — Documented Examples

#### From Common Changelog (https://common-changelog.org/)

**Bad (verbatim git noise):**
```
- json-parser 8.0.2 is fixed (#295)
- doc: fix dead link (#296)
- Bump actions/checkout from v2.3.3 to v2.3.4 (#293)
```

**Good (curated, impact-focused):**
```
### Changed
- Unpin `json-parser` having fixed alice/json-parser#38 (#295)

### Fixed
- Clarify hyphenated fields in `filter` option require brackets (#291)
```

#### From AnnounceKit (https://announcekit.app/guides/how-to-write-a-changelog)

| Problem | Poor | Better |
|---------|------|--------|
| Too technical | "Refactored auth middleware" | "Login is now more reliable across browsers" |
| Too vague | "Various improvements" | "Faster load times on the dashboard" |
| No context | "Fixed timezone bug" | "Fixed: Calendar showed wrong timezone for recurring events" |
| No user benefit | "Added export functionality" | "Export to CSV — download any table for reporting/backups" |

#### From GitLab Documentation (https://docs.gitlab.com/development/changelog/)

- ❌ "Fixes and Improves CSS and HTML problems in mini pipeline graph"
- ✅ "Fix tooltips and hover states in mini pipeline graph and builds dropdown list"

- ❌ "Strip out nils in the Array of Commit objects returned from find_commits_by_message_with_elastic"
- ✅ "Fix 500 errors caused by Elasticsearch results referencing garbage-collected commits"

#### From Rails ActiveRecord CHANGELOG (https://github.com/rails/rails/blob/main/activerecord/CHANGELOG.md)

Rails entries use imperative mood with technical context appropriate for a developer audience (Rails is a developer tool):
- "Deprecate the `schema_order` option in PostgreSQL database configurations. Use `schema_search_path` instead."
- "Avoid issuing a `ROLLBACK` statement following `TransactionRollbackError` during `COMMIT`."
- "Fix SQLite3 data loss during table alterations with CASCADE foreign keys... The root cause was incorrect ordering of operations."

Note: Rails explains *why* (root cause, migration path) — even in a developer-facing changelog.

---

### Theme 7: The Tense Debate — Past vs Imperative

This is a genuine open debate with no universal resolution. Evidence from multiple sources:

**Past tense advocates:**
- Amarok project (KDE): explicit discussion (https://amarok-devel.kde.narkive.com/HN2CDWXz/changelog-please-use-past-tense). Conclusion: "Past tense is the most logical tense to use because it indicates something has already been done." Adopted as standard.
- Broadinstitute WARP (https://broadinstitute.github.io/warp/docs/contribution/contribute_to_warp/changelog_style): "Use past tense for change descriptions." Example: ✅ "Fixed the broken link" — ❌ "Fix the broken link."
- GitHub issue #54 on olivierlacan/keep-a-changelog: Lacan himself prefers past tense but acknowledges: "If it's awkward to phrase I'd much rather a changelog switch to present tense than do acrobatics to fit the past tense mold."

**Imperative/present advocates:**
- Common Changelog (https://common-changelog.org/): "Write using imperative mood (present-tense verbs)." Rationale: tells users what upgrading *will do*, consistent with commit message conventions.
- Rails ActiveRecord: uses imperative throughout ("Add," "Fix," "Deprecate," "Allow").

**The key insight from the debate (GitHub issue #54):**

One contributor proposed eliminating verbs entirely for the Added/Fixed/Removed sections, leaving only the noun phrase — since the section heading already provides the action context. Example: under "### Fixed", just write "Broken link in StarAlign task" rather than either "Fixed broken link" or "Fix broken link."

This is structurally closest to the 4Shark engineer's philosophy: the heading carries the action context; the entry names the subject.

**Conclusion from research:** No universal standard exists. Past tense is the more natural choice when the changelog is read as a historical record ("what happened"). Imperative is preferred when the entry must stand alone without the section heading. The section-heading-as-context approach (noun phrases only) is an under-documented but logically sound compromise.

---

### Theme 8: SemVer and Changelogs — Complementary, Not Redundant

Semantic Versioning 2.0.0 (https://semver.org/) was authored by Tom Preston-Werner (GitHub co-founder).

SemVer encodes *type* of change in the version number:
- MAJOR: breaking changes
- MINOR: backward-compatible features
- PATCH: backward-compatible fixes

But SemVer communicates **no content**. As found in community commentary:
> "SemVer is useless without a changelog: have a breaking change? Amazing, but what is it and what should your users do about it?"

The semver.org specification itself does not reference changelogs. The two systems are complementary: SemVer tells you *how much* changed (risk level), the changelog tells you *what* changed (content). Neither substitutes for the other.

---

### Theme 9: Industry Policies at Scale

**Stripe** (https://docs.stripe.com/changelog): Separates technical API details from user-facing release notes. Breaking changes are prominently called out. Each entry explains what a change enables or removes for the developer.

**Shopify shopify_app** (https://github.com/Shopify/shopify_app/blob/main/CHANGELOG.md): Entries linked to PR numbers, plain-language descriptions, no internal jargon.

**GitLab** (https://docs.gitlab.com/development/changelog/): Machine-generated from Git commit trailers, but the entry text is human-written and policy-enforced to be user-facing.

**WordPress** (https://developer.wordpress.org/news/2025/11/the-importance-of-a-good-changelog/): Emphasizes that changelogs reduce support tickets by answering user questions proactively.

---

### Theme 10: What Makes an Entry Excellent — The Positive Case

From Mintlify's analysis of best-in-class developer brands (https://www.mintlify.com/blog/five-changelog-principles-from-best-developer-brands):

1. **Write for human impact** — not implementation. Show what the user can now do.
2. **Structure with clear hierarchy** — consistent categories for scanability.
3. **Connect and reference** — link to docs, PRs, related issues for readers who want more.
4. **Include only what matters** — "Reduced API response time by 35% for large datasets" beats "Improved API performance."
5. **Make changelogs discoverable** — surface them where users are, not just in a root file.

WorkOS (https://workos.com/blog/what-makes-a-good-changelog) identifies five components for every entry:
1. Clarity — jargon-free, immediately understandable
2. Relevance — only details that add value
3. Organization — logical grouping
4. Concision — one-line preferred
5. Link-ability — each entry shareable

---

## Conclusions

### 1. The 4Shark philosophy is well-supported by evidence

The engineer's core premise — "the changelog contains what you can't see from the code" — aligns precisely with what the primary sources argue. Multiple independent sources (keepachangelog.com, common-changelog.org, GitLab docs, Sophia Willows, WorkOS, ProductLogic.org) reach the same conclusion: the changelog's job is to communicate impact and context, not to mirror code changes.

### 2. Internal changes should not appear in changelogs

GitLab's policy is the most explicit: refactoring, technical debt, test suite changes, and documentation-only changes do not warrant changelog entries. The rationale is consistent: these changes are not visible to users and carry no user-facing meaning.

### 3. Entries should name the subject, not describe the implementation

The strongest anti-pattern is entries that describe what the developer did rather than what the user experiences. The GitLab examples are the clearest illustration:
- ❌ "Strip out nils in Commit objects" — describes internal implementation
- ✅ "Fix 500 errors from garbage-collected commits in search" — describes user-visible impact

### 4. The section heading carries the action context — entries name the subject

The 4Shark format (entries as noun phrases under `### Fixed`, `### Added`, etc.) is logically sound and supported by the GitHub issue #54 debate. The section heading already says what happened. The entry only needs to say *what* was fixed/added/changed.

This is more minimal than either the imperative (Common Changelog) or past-tense (Amarok, WARP) conventions, but it is internally consistent and easier to follow.

### 5. Tense is secondary to clarity

No authoritative source treats tense as a blocking issue. What matters is:
- Consistency within the file
- Clarity for the reader
- Avoiding ambiguity (entries that read like TODOs rather than completed work)

Past tense is the most natural choice for a historical record. The 4Shark policy of reading entries as "what happened" (past) is linguistically coherent.

### 6. SemVer and changelogs are complementary, not redundant

SemVer encodes risk level (how much the API changed). The changelog encodes content (what specifically changed and why it matters). Both are necessary; neither substitutes for the other.

### 7. The "three questions" test is a useful quality gate

An entry passes quality if a reader can answer from it:
1. What changed? (subject)
2. Who is affected? (implicit from context)
3. Why does it matter? (motivation, user impact)

An entry that only answers question 1 is a commit log dump. An entry that answers all three is a proper changelog entry.

---

## Application to 4Shark Changelog Policy

The current 4Shark policy (`~/.claude/docs/CHANGELOG.md`) is consistent with best practices in structure and intent. Evidence from this research suggests the following refinements to the documentation:

**Reinforced by evidence:**
- "Changelogs are for humans, not machines" — directly from keepachangelog.com
- Section heading as context, entry as subject — supported by the GitHub issue #54 noun-phrase proposal
- No implementation details — directly from GitLab's documented anti-patterns
- Internal changes (refactoring, test changes) get no entry — directly from GitLab policy

**Underrepresented in current documentation:**
- The explicit principle that the changelog contains what the code *cannot* show — motivation, business context, user impact
- The distinction between commit log (engineering record) and changelog (user-facing record)
- The "three questions" test for entry quality (What? Who? Why?)
- Explicit anti-pattern examples showing the transformation from bad to good

**On tense:** the current policy uses past-tense section titles (`### Fixed`, `### Added`) and noun-phrase entries. This is logically consistent — the section title is the past-tense verb, the entry is the subject. The documentation could make this explicit to prevent confusion.

---

## Next Steps

This investigation is complete. The findings support updating `~/.claude/docs/CHANGELOG.md` with:

1. An explicit principle stating what the changelog captures that code cannot (motivation, user impact, business context)
2. Anti-pattern examples with transformations (bad → good)
3. The "three questions" quality gate
4. An explicit statement distinguishing changelog entries from commit messages
5. Examples drawn from real projects (GitLab, Rails) to illustrate the patterns

Recommended action: create a PLAN.md for updating `~/.claude/docs/CHANGELOG.md` with these additions.

---

## Sources

- Keep a Changelog v1.1.0: https://keepachangelog.com/en/1.1.0/
- Common Changelog: https://common-changelog.org/
- Common Changelog (GitHub): https://github.com/vweevers/common-changelog
- Semantic Versioning 2.0.0: https://semver.org/
- GitLab Changelog Entry Guidelines: https://docs.gitlab.com/development/changelog/
- Olivier Lacan interview (Changelog podcast): https://changelog.com/podcast/127
- Rails ActiveRecord CHANGELOG: https://github.com/rails/rails/blob/main/activerecord/CHANGELOG.md
- Shopify shopify_app CHANGELOG: https://github.com/Shopify/shopify_app/blob/main/CHANGELOG.md
- Sophia Willows — "Conventional changelogs suck": https://sophiabits.com/blog/conventional-changelogs-suck
- WorkOS — "What makes a good changelog": https://workos.com/blog/what-makes-a-good-changelog
- Mintlify — "Five changelog principles from best-in-class developer brands": https://www.mintlify.com/blog/five-changelog-principles-from-best-developer-brands
- AnnounceKit — "How to Write a Changelog": https://announcekit.app/guides/how-to-write-a-changelog
- WordPress Developer Blog — "The importance of a good changelog": https://developer.wordpress.org/news/2025/11/the-importance-of-a-good-changelog/
- ProductLogic.org — "Let's change changelogs": https://productlogic.org/2021/06/07/lets-change-changelogs/
- Broadinstitute WARP Changelog Style Guide: https://broadinstitute.github.io/warp/docs/contribution/contribute_to_warp/changelog_style
- Amarok KDE — "ChangeLog: Please use past tense": https://amarok-devel.kde.narkive.com/HN2CDWXz/changelog-please-use-past-tense
- GitHub Issue #54 — "Use same tense in changelog messages": https://github.com/olivierlacan/keep-a-changelog/issues/54
- GitHub Issue #181 — "Types of changes moods": https://github.com/olivierlacan/keep-a-changelog/issues/181
- UserGuiding — "Mastering Changelog Best Practices": https://userguiding.com/blog/changelog-best-practices

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
