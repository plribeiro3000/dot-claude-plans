# SPIKE — Transitive Dependency Update Strategies Under a Minimum-Release-Age Quarantine

## Investigation question

Teams running Renovate get their direct dependencies updated on a quarantine schedule, but Renovate does not manage transitive dependencies by design (established in a prior spike, `~/Projects/4Shark/dot-claude-plans/active/spike/bundler-version-in-dockerfile/SPIKE.md`, not re-derived here). What does the community actually do about that gap — do they treat it as a real problem or an accepted trade-off — and specifically: is there a way to close it WITHOUT giving up the 7-day `minimumReleaseAge` quarantine 4Shark already runs across 14 repositories?

The refusal to trade away the 7-day quarantine is the constraint this research operates under, not a question reopened here.

## Sources consulted

- [ruby/rubygems PR #9576](https://github.com/ruby/rubygems/pull/9576) — the Bundler `cooldown` implementation PR; settles that `cooldown` covers transitive dependencies during resolution.
- [ruby/rubygems Discussion #9113](https://github.com/ruby/rubygems/discussions/9113) — the design discussion; a maintainer (hsbt) explains directly why transitive dependencies cannot be excluded from `cooldown`.
- [ruby/rubygems PR #9599](https://github.com/ruby/rubygems/pull/9599) — a follow-up fix, with test coverage naming a transitive-dependency-through-cooldown scenario explicitly.
- [RubyGems Blog — "Cool down before you install"](https://blog.rubygems.org/2026/06/03/cooldown-let-new-gems-be-vetted.html) — first-party announcement; confirms the shipping version and motivation.
- [Andrew Nesbitt — "Package Managers Need to Cool Down"](https://nesbitt.io/2026/03/04/package-managers-need-to-cool-down.html) — independent corroboration that Bundler's cooldown covers transitive dependencies, and that pnpm and Yarn ship the equivalent.
- [renovatebot/renovate Discussion #33505](https://github.com/renovatebot/renovate/discussions/33505) — a Renovate maintainer (rarkins) stating the project's position on transitive dependencies directly.
- [renovatebot/renovate Discussion #38115](https://github.com/renovatebot/renovate/discussions/38115) — a report of `minimumReleaseAge` not applying to `lockFileMaintenance`-introduced transitive dependencies, with a maintainer response pointing at a tracking epic.
- [docs.renovatebot.com — Minimum Release Age](https://docs.renovatebot.com/key-concepts/minimum-release-age/) — canonical documentation stating Renovate does not manage transitive dependencies.
- [docs.renovatebot.com — Security Presets](https://docs.renovatebot.com/presets-security/) — the officially documented workaround: disable `minimumReleaseAge` for `lockFileMaintenance` and rely on the package manager's own validation instead.
- [renovatebot/renovate Issue #41652](https://github.com/renovatebot/renovate/issues/41652) — the tracking epic for passing minimum-age constraints to package managers via CLI/env flags.
- [GitHub Docs — Controlling which dependencies are updated by Dependabot](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/controlling-dependencies-updated) — Dependabot's `allow`/`dependency-type` configuration for transitive dependencies.
- [GitHub Docs — Vulnerable dependency detection](https://docs.github.com/en/code-security/reference/supply-chain-security/troubleshoot-dependabot/vulnerability-detection) — the scope of Dependabot alerts vs. auto-fix PRs for transitive dependencies, and the npm-vs-other-ecosystems split.
- [GitHub Blog — "The case for a cooldown: Why Dependabot now waits before issuing version updates"](https://github.blog/security/supply-chain-security/the-case-for-a-cooldown-why-dependabot-now-waits-before-issuing-version-updates/) — the July 2026 default 3-day Dependabot version-update cooldown.
- [docs.github.com — Dependabot options reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference) — the `cooldown` config key documentation.
- [dependabot/dependabot-core Issue #14683](https://github.com/dependabot/dependabot-core/issues/14683) — a filed and closed bug report about Dependabot cooldown not respecting a transitive dependency, scoped to npm.
- [GitHub orgs/community Discussion #174897](https://github.com/orgs/community/discussions/174897) — the community report that surfaced the #14683 bug, with reproduction detail.
- [TechDebt.guru — Dependency Management Guide](https://techdebt.guru/dependency-management/) — a documented manual-cadence practice for transitive dependency refresh.
- [masutaka/circleci-bundle-update-pr](https://github.com/masutaka/circleci-bundle-update-pr) and [supermanner/pull-request-on-bundle-update](https://github.com/supermanner/pull-request-on-bundle-update) — two independent, existing community tools that run `bundle update` on a schedule and open a PR.
- See auxiliary `transitive-dependency-strategies_sources_1.md` — full raw quotes, including everything reported via WebFetch's summarization but not independently re-confirmed by direct substring search, and the two sources that could not be fetched at all (marked UNVERIFIED there).

## Findings

### Finding 1: Renovate's own maintainer treats non-coverage of transitive dependencies as an accepted, deliberate trade-off, not a defect to fix

**Evidence:**

> "It's too noisy and inefficient to update all transitive dependencies individually by default (code bases can have thousands of transitive, and hundreds may be outdated)."

and, on whether Renovate should surface transitive vulnerabilities:

> "Renovate is not the right tool for transitive vulnerabilities"

**Source:** GitHub user `rarkins` (a Renovate maintainer), in `renovatebot/renovate` Discussion #33505, `https://github.com/orgs/renovatebot/renovate/discussions/33505` — reported via WebFetch, not independently re-confirmed by a second substring-search fetch.

**Significance:** this is the project's own position, from a maintainer, on the specific question this spike asks about scope 1 — the answer is that Renovate deliberately does not treat this as a gap to close inside Renovate itself; the recommended path is `lockFileMaintenance` (delegating to the package manager) plus a dedicated vulnerability-composition tool (Mend SCA) for detection, not Renovate doing the update.

### Finding 2: A security-focused independent writer treats the same gap as a real, exploitable risk — not a trade-off to accept

**Evidence:**

> "Cooldowns must apply to your entire dependency graph, not just direct dependencies. A malicious package introduced as a transitive can still reach production even when your direct imports are carefully curated."

and:

> "The anti-pattern: floating transitive dependencies in production with cooldowns only on direct dependencies. That just moves the golden-hour problem one level down the graph, which is exactly where attackers increasingly aim."

**Source:** `https://christian-schneider.net/blog/dependency-cooldowns-supply-chain-defense/` — fetched successfully once; a second fetch to the same URL for the self-check re-confirmation returned HTTP 403 (inconsistent server behavior, not a retraction of the content). Per Citation Discipline rule 5 this Finding's self-check is incomplete; it is included because the first fetch returned the quoted text directly and is corroborated in substance (though not in exact wording) by Finding 4 below, but it should be treated as less rigorously verified than the other Findings in this spike.

**Significance:** this is direct evidence that "is the community worried about this?" does not have one answer — it splits along the writer's role. A tool maintainer managing false-positive/noise trade-offs at scale (Finding 1) reaches a different conclusion than a supply-chain-security writer reasoning about attacker behavior (this Finding).

### Finding 3: The community split is not purely opinion — newer package-manager-native cooldown features (pnpm, Yarn, Bundler) are independently converging on covering the whole dependency graph, including transitive dependencies, at the package-manager level rather than at the update-bot level

**Evidence:**

> "with pnpm shipping minimumReleaseAge in version 10.16 in September 2025, covering both direct and transitive dependencies with a minimumReleaseAgeExclude list for packages you trust enough to skip."

> "Yarn shipped npmMinimalAgeGate in version 4.10.0 the same month (also in minutes, with npmPreapprovedPackages for exemptions)"

> "The filter applies to transitive dependencies too, and lockfile-pinned versions bypass it so existing locks don't break."

**Source:** Andrew Nesbitt, "Package Managers Need to Cool Down", `https://nesbitt.io/2026/03/04/package-managers-need-to-cool-down.html`, fetched twice with consistent results (initial fetch, then re-fetched to confirm each of the three substrings independently).

**Significance:** this establishes that the mechanism 4Shark's engineer is asking about (a package-manager-native age gate that reaches transitive dependencies) is not a Bundler-specific curiosity — it is one instance of a pattern three separate package-manager projects shipped independently within roughly the same window (pnpm September 2025, Yarn the same month, Bundler's `cooldown` per Finding 6 below shipped in 4.0.13). The pattern is "push the age gate into the resolver, which already sees the whole graph" rather than "have the update bot re-implement resolution."

### Finding 4: Bundler's `cooldown` explicitly applies to the whole dependency resolution, including transitive dependencies — settled directly by the implementation PR

**Evidence:**

> "`--cooldown 0` is the global escape hatch and applies to the whole resolve including transitive dependencies; combine with `--conservative` to minimize churn during urgent updates."

**Source:** `ruby/rubygems` PR #9576, "Add `cooldown` to delay newly published gem" (hsbt), `https://github.com/ruby/rubygems/pull/9576`, fetched twice — once for general content, once specifically to confirm this substring by direct search — with consistent results both times.

**Significance:** this directly answers the decisive question the investigation named: `cooldown` is not scoped to the gems named in the `Gemfile`. It is a filter applied during dependency resolution itself, and Bundler's resolution necessarily walks the whole graph (direct and transitive) to produce a lockfile — so there is no resolution step that could see only direct dependencies.

### Finding 5: The Bundler maintainer explicitly rejected excluding transitive dependencies from `cooldown`, and named the reason — resolution correctness, not policy preference

**Evidence:**

> "An alternative was considered: applying `--cooldown 0` only to the specified gem while maintaining cooldown for its transitive dependencies. This was rejected because RubyGems/Bundler resolves dependencies by seeking the newest version satisfying constraints. When a new version of a direct dependency requires a new version of a transitive dependency (e.g., `rails 8.0.2` requires `activesupport = 8.0.2`), cooldown on the transitive dependency would make resolution impossible — even with `--conservative`."

**Source:** GitHub user `hsbt` (RubyGems/Bundler maintainer), comment dated 2026-04-09 in `ruby/rubygems` Discussion #9113, `https://github.com/ruby/rubygems/discussions/9113`, fetched twice — once for general content, once to confirm this exact substring — with consistent results.

**Significance:** this is not merely a description of current behavior — it is the maintainer's stated reason why the alternative (direct-only cooldown) was considered and rejected as infeasible, not merely undesirable. It closes the door on a hypothetical "cooldown but only for what I named" mode ever existing in Bundler, because per this maintainer's account it would make ordinary resolution fail whenever a direct dependency's newer version requires a newer transitive one.

### Finding 6: A follow-up PR added explicit test coverage for the transitive-dependency-through-cooldown interaction, confirming the feature was built and verified against that exact scenario, not merely designed for it

**Evidence:**

> "Cover transitive and upgrade paths for in-cooldown locked versions
> The previous tests only exercised a top-level locked gem. Add a transitive dependency that resolves only through an in-cooldown version, and a case where a cooldown-eligible version above the locked one still gets picked up, so the full update behavior stays pinned down."

**Source:** commit `5deac9f` in `ruby/rubygems` PR #9599, "Don't exclude the locked version from cooldown during bundle update", `https://github.com/ruby/rubygems/pull/9599`, fetched twice — once for general content, once to confirm this exact substring in the commit message — with consistent results.

**Significance:** together with Findings 4 and 5, this closes the decisive question from three independent angles inside the same feature's development history: the PR description states the scope, the design-discussion maintainer comment explains why the scope could not be narrower, and this follow-up PR's own test suite specifically exercises a transitive dependency through the cooldown filter. `lockFileMaintenance` (which deletes `Gemfile.lock` and lets Bundler re-resolve from scratch, established in the prior spike) would therefore run through the same cooldown-aware resolver Bundler always uses — the combination is not a speculative pairing, it is Bundler's `bundle install`/`bundle update` behaving as designed on whatever `Gemfile` state `lockFileMaintenance` leaves behind.

### Finding 7: Renovate's own official documentation instructs users to rely on the package manager's own minimum-age validation specifically because Renovate's `lockFileMaintenance` cannot validate it itself

**Evidence:**

> "Renovate's lock file maintenance functionality does not support validating Minimum Release Age, as the package manager performs the required changes to update package(s). Confirm whether your package manager perform its own validation for the Minimum Release Age of packages."

**Source:** `docs.renovatebot.com/presets-security/`, `https://docs.renovatebot.com/presets-security/`, fetched twice — once for general content, once to confirm this exact substring — with consistent results both times; the identical sentence appears across the `security:minimumReleaseAgeNpm`, `security:minimumReleaseAgeCrate`, and `security:minimumReleaseAgePypi` presets.

**Significance:** this is the single most directly relevant finding to the investigation's core question. Renovate does not merely fail to enforce `minimumReleaseAge` on `lockFileMaintenance`-triggered changes (established in the prior spike) — its own documentation names the fix as "confirm whether your package manager performs its own validation", which is exactly the shape of `lockFileMaintenance` + Bundler `cooldown`. However, **no equivalent preset exists for Bundler/RubyGems** — the pattern is documented and pre-packaged only for npm, Cargo (Rust), and PyPI (Python) as of this research. For Ruby, applying the same idea would mean configuring Bundler's own `cooldown` (via `bundle config set cooldown 7`, `BUNDLE_COOLDOWN`, or the `Gemfile` `source` option) independently of Renovate — a manual application of a pattern Renovate's docs already endorse in principle for other ecosystems, not something Renovate ships pre-built for Bundler.

### Finding 8: The tracking epic for making Renovate pass minimum-age constraints to package managers exists, is open, and does not currently name Bundler or RubyGems

**Evidence:**

> "we have noted that it would be good to make sure that Renovate passes package manager specific flags when installing dependencies"

and, on scope:

> "We'll add Issues for package managers as we see they're supported"

**Source:** `renovatebot/renovate` Issue #41652, `https://github.com/renovatebot/renovate/issues/41652`, fetched once via WebFetch; not re-confirmed by a second substring-search fetch. The fetch explicitly reported the only concrete example given in the epic is npm, and neither "Bundler" nor "RubyGems" appears in the content it returned.

**Significance:** this shows Renovate-the-project is aware of and actively tracking the general shape of the problem (getting the package manager to enforce the age gate that `lockFileMaintenance` bypasses), but as of this research Bundler is not a named target. Whether Renovate ever wires `--cooldown` into its own `lockFileMaintenance` invocation for Bundler specifically is an open question this epic does not resolve.

### Finding 9: Dependabot's `allow`/`dependency-type` configuration can widen version-update PRs to transitive dependencies, but Dependabot's ability to actually fix a transitive dependency (not just alert on it) is ecosystem-dependent, and non-npm ecosystems are explicitly the weaker case

**Evidence:**

> "By default, Dependabot creates version update pull requests only for the dependencies that are explicitly defined in a manifest (`direct` dependencies)."

and:

> "This configuration uses `allow` to tell Dependabot that we want it to maintain `all` types of dependency. That is, both the `direct` dependencies and their dependencies (also known as indirect dependencies, sub-dependencies, or transient dependencies)."

Separately, on the fix-capability split:

> "Dependabot alerts advise you about dependencies you should update, including transitive dependencies, where the version can be determined from a manifest or a lockfile."

> "Dependabot security updates only suggest a change where Dependabot can directly 'fix' the dependency, that is, when these are: Direct dependencies explicitly declared in a manifest or lockfile [or] Transitive dependencies declared in a lockfile."

**Source:** GitHub Docs, "Controlling which dependencies are updated by Dependabot" (`https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/controlling-dependencies-updated`) for the first two quotes, reported via WebFetch and not independently re-confirmed by substring search; and GitHub Docs, "Vulnerable dependency detection" (`https://docs.github.com/en/code-security/reference/supply-chain-security/troubleshoot-dependabot/vulnerability-detection`) for the last two quotes, both independently confirmed by a second substring-search fetch.

**Significance:** 4Shark runs Dependabot in security-only mode today (established context, not re-derived). Switching `allow`/`dependency-type` to cover transitive dependencies is a version-update-mode setting, so it is orthogonal to the security-only mode 4Shark uses — it would require also enabling non-security version updates, which is a separate decision (opening the noise/review-burden question the `minimumReleaseAge` quarantine already manages for direct dependencies today). Separately, and regardless of that setting: this research did not find a source stating whether Dependabot's Bundler support can auto-fix a transitive dependency the way it can for npm. The vulnerability-detection page's own reported framing ("for other ecosystems, Dependabot is unable to update an indirect or transitive dependency if it would also require an update to the parent dependency") suggests Ruby is more likely to fall on the weaker side of this split than npm, but this exact sentence was not independently re-confirmed by substring search — flagged in "What remains uncertain."

### Finding 10: Dependabot alerts (vulnerability detection, distinct from update PRs) DO cover transitive dependencies today, independent of whether a fix can be automated

**Evidence:**

> "Dependabot alerts advise you about dependencies you should update, including transitive dependencies, where the version can be determined from a manifest or a lockfile."

**Source:** GitHub Docs, "Vulnerable dependency detection", `https://docs.github.com/en/code-security/reference/supply-chain-security/troubleshoot-dependabot/vulnerability-detection`, fetched twice — once for general content, once to confirm the substring "Transitive dependencies declared in a lockfile" appears verbatim as a list item — with consistent results.

**Significance:** this is the direct answer to "what actually protects a transitive dependency today, independent of whether it was ever bumped". A CVE in an un-updated transitive gem does not require anyone to have previously updated that gem for GitHub to detect it — detection is a separate mechanism (the dependency graph read against the GitHub Advisory Database) from update-PR generation. This distinguishes "nobody bumped it" from "nobody would find out if it were vulnerable" — the two are not the same failure, and this Finding establishes that the second one is covered by the alert mechanism regardless of Bundler/Ruby's weaker auto-fix capability (Finding 9).

### Finding 11: GitHub shipped a default 3-day cooldown for Dependabot's own non-security version updates in July 2026, but no source found in this research states whether it covers transitive dependencies

**Evidence:**

> "For non-security version bumps, Dependabot now waits at least three days after a release is published before opening a pull request."

**Source:** GitHub Blog, "The case for a cooldown: Why Dependabot now waits before issuing version updates", `https://github.blog/security/supply-chain-security/the-case-for-a-cooldown-why-dependabot-now-waits-before-issuing-version-updates/`, fetched twice; the fetch explicitly reported it could not find text stating whether this default cooldown applies to transitive/indirect dependencies. The Dependabot options-reference documentation for the `cooldown` config key was also fetched (`https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference`) and likewise reported no explicit statement on transitive scope.

**Significance:** this is a genuine open question, not a gap in this research's effort — two separate official GitHub sources were checked and neither settles it. It also does not currently bear on 4Shark's configuration because 4Shark runs Dependabot in security-only mode (§ Automated Dependency Updates, established context), and this cooldown applies "only for version updates, not security updates" per the options-reference page. It is documented here because the engineer's question specifically named Dependabot as a candidate, and this is the most recent, most relevant Dependabot feature to that question — flagged as unresolved rather than answered.

### Finding 12: A specific bug — Dependabot's cooldown not respecting a transitive dependency — was filed, confirmed by a second reporter, and closed as fixed, but scoped explicitly to npm

**Evidence:**

Issue title, confirmed present:
> "npm: dependabot does not respect cooldown period for transitive dependencies #14683"

Reporter's finding (paraphrased by the fetch, not itself independently re-confirmed as a verbatim quote): direct dependency `aws-cdk-lib` correctly respected a 7-day cooldown, while the transitive dependency `@aws-cdk/cloud-assembly-schema` was suggested at a version less than 1 day old.

Confirming reply from a second reporter, `suntsa`, confirmed verbatim on a second fetch:
> "dependabot indeed bumps a transient dependency to a version that violates the cooldown period"

**Source:** `dependabot/dependabot-core` Issue #14683, `https://github.com/dependabot/dependabot-core/issues/14683`, fetched twice; and `orgs/community` Discussion #174897, `https://github.com/orgs/community/discussions/174897`, fetched twice, with the `suntsa` quote confirmed present on the second, more targeted fetch (a first, less careful fetch had appended words to this quote that are not present verbatim — corrected here to the confirmed substring only).

**Significance:** this is direct evidence that "does Dependabot's cooldown reach transitive dependencies" is a real, reported, reproduced defect for npm — not a hypothetical. The issue is closed as "Done", meaning some fix shipped, but a second WebFetch attempt at the same issue page could not retrieve resolution comments or a linked fixing PR, so this research cannot state HOW it was fixed or whether the fix generalizes past this one npm scenario. No evidence was found in this research that the fix (or the underlying bug) extends to or was ever reported for Bundler/RubyGems specifically.

### Finding 13: A documented manual-cadence practice exists in the community for exactly the gap the engineer named — periodic lockfile regeneration with review discipline

**Evidence:**

> "Regenerate lock files periodically to pick up transitive dependency updates."

**Source:** TechDebt.guru, "Dependency Management Guide", `https://techdebt.guru/dependency-management/`, fetched twice — once for general content, once to confirm this exact substring under a "Lock File Hygiene" heading — with consistent results.

**Significance:** this confirms the "manual process" alternative the engineer named is a documented practice, not a strawman. The same source also documents companion review discipline ("diff lock files in code review to catch unexpected changes") and a cadence framework (weekly for minor/batched updates, quarterly for major). This source is a general dependency-management guide, not Ruby/Bundler-specific, and does not address how (or whether) this practice would interact with a `minimumReleaseAge`-style quarantine.

### Finding 14: Two independent, existing community tools automate the "scheduled `bundle update` via a workflow, opening a PR" pattern the engineer floated

**Evidence:**

> "`circleci-bundle-update-pr` is an automation script for continuous bundle update and for sending a pull request using Scheduling a Workflow of CircleCI"

and, separately:

> "send pull request on bundle update"

**Source:** `masutaka/circleci-bundle-update-pr`, `https://github.com/masutaka/circleci-bundle-update-pr`, and `supermanner/pull-request-on-bundle-update`, `https://github.com/supermanner/pull-request-on-bundle-update`, both fetched once via WebFetch, not independently re-confirmed by a second substring-search fetch.

**Significance:** this establishes that scheduled `bundle update` PRs are an existing, if niche, community pattern with working reference implementations — it is not a novel idea the engineer would be inventing from scratch. Neither tool's README, per the fetch, states a recommended production cadence or discusses PR-noise/review-burden trade-offs; the example schedules shown range from weekly (`circleci-bundle-update-pr`, Friday 10:00) to every 15 minutes (`pull-request-on-bundle-update`'s illustrative example — not stated as a recommendation). Neither tool was found to have any age-gating or `minimumReleaseAge`-equivalent behavior of its own; a plain `bundle update` run this way would pull whatever is newest at run time, with no quarantine unless Bundler's own `cooldown` is separately configured in the environment running the workflow.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| `lockFileMaintenance` + Bundler `cooldown` configured independently (e.g. `BUNDLE_COOLDOWN=7` in the CI environment running Renovate's lockfile-maintenance branch, or `bundle config set cooldown 7` in the repo) | Renovate's own docs already endorse "confirm your package manager performs its own validation" for exactly this gap (Finding 7); Bundler's `cooldown` is confirmed to reach the whole resolve including transitive dependencies (Findings 4–6); no change to Renovate's existing 7-day `minimumReleaseAge` for direct dependencies is required | No pre-built Renovate preset exists for Bundler (unlike npm/Cargo/PyPI, Finding 7); this would be a manually-configured combination, not a documented, reference-implemented pairing anywhere found in this research; whether Renovate's `lockFileMaintenance` invocation of `bundle update`/`bundle lock` would itself pick up `BUNDLE_COOLDOWN` from the environment, or whether it needs to be set some other way, was not tested in this research | Findings 4, 5, 6, 7, 8 |
| Dependabot alongside Renovate, version-update mode with `allow: dependency-type: all` | Directly surfaces transitive-dependency updates as PRs (Finding 9); Dependabot alerts already cover transitive-dependency vulnerability detection today regardless of this setting (Finding 10) | Requires enabling non-security version updates (a mode 4Shark does not run today), reopening a noise/review-burden question the 7-day quarantine exists to manage for direct dependencies; Ruby/Bundler's auto-fix capability for a transitive dependency is not established as being as capable as npm's (Finding 9, flagged uncertain); Dependabot's own new default version-update cooldown does not have confirmed transitive-dependency scope (Finding 11); a prior transitive-cooldown bug was confirmed and fixed only for npm (Finding 12) | Findings 9, 10, 11, 12 |
| Manual periodic `bundle update` cadence (documented practice) | A real, named community practice (Finding 13), not a novel idea; pairs naturally with review discipline (diffing the lockfile) | The source describing this practice is generic (not Ruby-specific) and does not address interaction with a minimum-release-age quarantine; a manual `bundle update` with no `cooldown` configured would defeat the quarantine entirely unless `cooldown` is set in the same shell/session doing the update | Finding 13 |
| Scheduled `bundle update` via a CI workflow/cron, opening a PR (the daily-job idea the engineer floated) | Two independent, working reference implementations exist (Finding 14); fully automatable; can run at any cadence including daily | Neither existing tool has any built-in age-gating; a bare `bundle update` on a schedule pulls whatever is newest at run time, so it would defeat the 7-day quarantine unless `cooldown` is explicitly configured in the same job; no source found in this research reports actual experience with daily-cadence PR noise for this specific tool shape (the example schedules found were weekly and an illustrative 15-minute example, not a stated daily recommendation) | Finding 14 |

## What remains uncertain

- **Whether Renovate's `lockFileMaintenance` invocation of Bundler would itself respect `BUNDLE_COOLDOWN`/`bundle config set cooldown` set in the CI environment.** This spike confirmed that Bundler's own resolver honors `cooldown` for the whole graph (Findings 4–6) and that Renovate's docs point at exactly this kind of external validation for other ecosystems (Finding 7), but no source found in this research describes anyone actually running `lockFileMaintenance` with `cooldown` configured for Bundler specifically, and no Renovate-shipped preset exists for it (Finding 7, Finding 8). This is the central open question for closing the gap without giving up the quarantine — it is plausible from the evidence gathered, not confirmed by a report of it working.
- **Whether Ruby/Bundler falls on the weaker or stronger side of Dependabot's ecosystem-dependent transitive auto-fix capability.** The vulnerability-detection docs describe an npm-vs-"other ecosystems" split (Finding 9) without naming Ruby specifically as one of the "other ecosystems" in the text this research was able to confirm verbatim.
- **Whether GitHub's July 2026 default 3-day Dependabot version-update cooldown covers transitive dependencies.** Two official GitHub sources were checked; neither states this either way (Finding 11). Not load-bearing for 4Shark today (security-only mode), but genuinely unresolved if the engineer later considers enabling version-update mode.
- **How dependabot/dependabot-core#14683 was actually fixed, and whether that fix generalizes beyond the specific npm scenario reported.** The issue is closed "Done" but this research could not retrieve the resolution comments or linked PR (Finding 12).
- **Whether "the community" has a single answer to "is this a real problem or an accepted trade-off".** This research found both positions held by credible, on-topic sources (Findings 1 and 2) and does not attempt to adjudicate between them — the honest finding is that the answer depends on whether the speaker is reasoning about tool-maintenance trade-offs (noise, false positives, update-bot scope) or about attacker behavior (a compromised transitive package is exploitable exactly the same way a compromised direct one is).
- **Actual production experience with daily-cadence scheduled `bundle update` PRs.** Neither tool found in Finding 14 documents this cadence as tested or recommended; the engineer's "daily job" idea is technically buildable from existing pieces but this research found no report of anyone running it at that frequency.

## Suggested options for main and the engineer

- **Option A — configure Bundler's `cooldown` directly in the environment(s) that run Renovate's `lockFileMaintenance` for the four Ruby repositories**, so that when Renovate deletes the lockfile and lets Bundler re-resolve, Bundler's own resolver (confirmed to cover the whole graph, Findings 4–6) enforces the same 7-day window Renovate enforces for direct dependencies. This is the combination Renovate's own documentation gestures at for other ecosystems (Finding 7) but does not yet ship a preset for; it would need to be set up and verified independently, since no report of this exact pairing working was found.
- **Option B — enable Dependabot version-update mode (in addition to the existing security-only mode) with `allow: dependency-type: all`**, accepting the noise/review-burden trade-off the 7-day quarantine currently manages only for direct dependencies, and accepting the unresolved question of whether Bundler gets npm's level of transitive auto-fix capability (Finding 9).
- **Option C — adopt a manual or scheduled `bundle update` cadence** (per Finding 13's documented practice or Finding 14's existing tooling), paired with `cooldown` configured in the same job/session so the age gate is not silently defeated, and lockfile-diff review discipline at PR time.
- **Option D — do nothing beyond what already exists**, relying on Dependabot security alerts (which cover transitive dependencies today independent of update capability, Finding 10) to catch a CVE in an un-updated transitive gem, and accepting the remaining gap named in Finding 1/Finding 2's split (non-CVE bugs, incompatibilities, and accumulating upgrade debt in transitive dependencies) as the accepted trade-off Renovate's own maintainer describes.

(No recommendation — the evidence above surfaces the options and what each one costs; the engineer decides given the standing refusal to trade away the 7-day quarantine.)
