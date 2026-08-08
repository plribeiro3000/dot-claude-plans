# Raw source material — transitive dependency strategies spike

Preserved verbatim quotes and fetch results collected during research, organized by source. This file exists so a revision pass does not need to re-fetch everything.

## Bundler / RubyGems `cooldown` feature

### PR ruby/rubygems#9576 — "Add `cooldown` to delay newly published gem" (hsbt)

URL: https://github.com/ruby/rubygems/pull/9576

Confirmed verbatim (re-fetched, substring search):

> "`--cooldown 0` is the global escape hatch and applies to the whole resolve including transitive dependencies; combine with `--conservative` to minimize churn during urgent updates."

Located under a "Design decisions adopted from #9113 and the follow-up review" section of the PR description.

Also reported (not independently re-verified by substring search, but consistent with the confirmed quote above):
- "Precedence is CLI > config > Gemfile per-source, applied uniformly to every source — not just ones that declare their own `cooldown:` value."
- "Lockfile-pinned versions bypass the filter, and `bundle install` against an existing lockfile short-circuits the resolver entirely, so a cooldown setting never invalidates a working lock."

### Discussion ruby/rubygems#9113 — "Cooldown option for bundle update and bundle outdated"

URL: https://github.com/ruby/rubygems/discussions/9113

Confirmed verbatim (re-fetched, substring search), comment by maintainer **hsbt**, 2026-04-09:

> "An alternative was considered: applying `--cooldown 0` only to the specified gem while maintaining cooldown for its transitive dependencies. This was rejected because RubyGems/Bundler resolves dependencies by seeking the newest version satisfying constraints. When a new version of a direct dependency requires a new version of a transitive dependency (e.g., `rails 8.0.2` requires `activesupport = 8.0.2`), cooldown on the transitive dependency would make resolution impossible — even with `--conservative`."

Motivation quote (not independently re-verified by substring search):
> "supporting a cooldown (a window of time between when a dependency is published and when it's considered suitable for use) when updating dependencies is an effective way to mitigate common supply chain attacks."

### PR ruby/rubygems#9599 — "Don't exclude the locked version from cooldown during bundle update"

URL: https://github.com/ruby/rubygems/pull/9599

Confirmed verbatim (re-fetched, substring search), commit message on commit `5deac9f`:

> "Cover transitive and upgrade paths for in-cooldown locked versions
> The previous tests only exercised a top-level locked gem. Add a transitive dependency that resolves only through an in-cooldown version, and a case where a cooldown-eligible version above the locked one still gets picked up, so the full update behavior stays pinned down."

PR description quote (not independently re-verified by substring search):
> "A lockfile written before cooldown was enabled often pins a version now inside the cooldown window. `bundle update`/`outdated` floor each gem at `>= locked_version` but the cooldown filter then drops that same version, making resolution fail."

### RubyGems Blog — "Cool down before you install: give new gems a few days to be vetted" (2026-06-03)

URL: https://blog.rubygems.org/2026/06/03/cooldown-let-new-gems-be-vetted.html

Quotes obtained (not independently re-verified by substring search, but from the official RubyGems blog, first-party source):
- "Bundler 4.0.13" — release version cooldown shipped in.
- "Most supply-chain attacks against RubyGems exploit a narrow window: an account is compromised, a malicious version ships, and any `bundle install` in the minutes that follow resolves straight to it." — motivation.
- The fetch explicitly reported: "The document does not explicitly specify whether cooldown applies only to direct Gemfile dependencies or also to transitive/indirect dependencies during resolution" — i.e., this specific post does NOT itself settle the transitive-scope question (settled instead by PR #9576 and Discussion #9113 above).

### Andrew Nesbitt — "Package Managers Need to Cool Down" (nesbitt.io, 2026-03-04)

URL: https://nesbitt.io/2026/03/04/package-managers-need-to-cool-down.html

All three confirmed verbatim (re-fetched, substring search):

> "with pnpm shipping minimumReleaseAge in version 10.16 in September 2025, covering both direct and transitive dependencies with a minimumReleaseAgeExclude list for packages you trust enough to skip."

> "Yarn shipped npmMinimalAgeGate in version 4.10.0 the same month (also in minutes, with npmPreapprovedPackages for exemptions)"

> "The filter applies to transitive dependencies too, and lockfile-pinned versions bypass it so existing locks don't break."

Also reported (not independently re-verified by substring search):
- "eight had windows of opportunity under a week, so even a modest cooldown of seven days would have blocked most of them from reaching end users."

### Socket.dev blog — "RubyGems Adds Cooldown Feature to Bundler for Newly Published..."

URL: https://socket.dev/blog/rubygems-adds-bundler-cooldown

NOTE: this URL returned HTTP 403 on direct WebFetch on two attempts. Content below is from the WebSearch tool's synthesized snippet only — NOT independently fetched or verified. Marked UNVERIFIED; not used to sustain any Finding.

> "RubyGems and Bundler 4.0.13 introduced an opt-in cooldown feature that delays newly published gems during dependency resolution... passing --cooldown 0 disables the delay for a run when a project needs to install the newest available version."

## Renovate and transitive dependencies

### Discussion renovatebot/renovate#33505 — "Misconceptions about indirect / transitive dependencies update"

URL: https://github.com/renovatebot/renovate/discussions/33505

Reported via WebFetch (not independently re-verified by substring search on second pass, but WebFetch quoted maintainer directly):

Maintainer **rarkins**:
> "We recommend you run 'lock file maintenance'. It will run weekly by default, updating all transitive dependencies to the highest possible."

> "It's too noisy and inefficient to update all transitive dependencies individually by default (code bases can have thousands of transitive, and hundreds may be outdated)."

> "Renovate is not the right tool for transitive vulnerabilities" (recommending Mend SCA instead).

### Discussion renovatebot/renovate#38115 — "minimumReleaseAge is not working with lockFileMaintenance and transitive Dependencies"

URL: https://github.com/renovatebot/renovate/discussions/38115

Reported via WebFetch (not independently re-verified by substring search):

Original post:
> "LockFileMaintenance will delete the lockFile and ask the package manager to generate a new one. Unless the package manager also has a `minimumReleaseAge` it will choose the latest version."

Maintainer (jamietanna) pointed to epic #41652:
> "when we have clear indications of package managers that can be passed these constraints via CLI/environment variables, we'll share this information to enforce it"

### docs.renovatebot.com/key-concepts/minimum-release-age/

URL: https://docs.renovatebot.com/key-concepts/minimum-release-age/

Reported via WebFetch (not independently re-verified by substring search on second pass, but is the canonical Renovate documentation page):

> "Renovate does not currently manage any transitive dependencies - instead leaving that to package managers and lockFileMaintenance."

> "lockFileMaintenance - Not possible, as we delegate to the package manager to perform the required changes to update package(s)."

### docs.renovatebot.com/presets-security/

URL: https://docs.renovatebot.com/presets-security/

Confirmed verbatim (re-fetched, substring search), appears identically across the `security:minimumReleaseAgeNpm`, `security:minimumReleaseAgeCrate`, and `security:minimumReleaseAgePypi` presets:

> "⚠️ Renovate's lock file maintenance functionality does not support validating Minimum Release Age, as the package manager performs the required changes to update package(s). Confirm whether your package manager perform its own validation for the Minimum Release Age of packages."

Rule description quote (not independently re-verified by substring search):
> "Do not require Minimum Release Age for update types that are controlled by the package manager"

NOTE: no `security:minimumReleaseAgeBundler` (or equivalent Ruby-scoped) preset was found on this page or via search — only npm, crate (Rust/Cargo), and pypi (Python) presets exist for this pattern.

### Issue renovatebot/renovate#41652 (epic)

URL: https://github.com/renovatebot/renovate/issues/41652

Reported via WebFetch (not independently re-verified by substring search):

> "we have noted that it would be good to make sure that Renovate passes package manager specific flags when installing dependencies"

> "We'll add Issues for package managers as we see they're supported"

The fetch explicitly reported no mention of Bundler or RubyGems in this epic — only npm is used as the concrete example.

## Dependabot and transitive dependencies

### GitHub Docs — Controlling which dependencies are updated by Dependabot

URL: https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/manage-your-dependency-security/controlling-dependencies-updated

Reported via WebFetch (not independently re-verified by substring search):

> "By default, Dependabot creates version update pull requests only for the dependencies that are explicitly defined in a manifest (`direct` dependencies)."

> "This configuration uses `allow` to tell Dependabot that we want it to maintain `all` types of dependency. That is, both the `direct` dependencies and their dependencies (also known as indirect dependencies, sub-dependencies, or transient dependencies)."

### GitHub Docs — Vulnerable dependency detection

URL: https://docs.github.com/en/code-security/reference/supply-chain-security/troubleshoot-dependabot/vulnerability-detection

Both confirmed verbatim (re-fetched, substring search):

> "Dependabot alerts advise you about dependencies you should update, including transitive dependencies, where the version can be determined from a manifest or a lockfile."

> "Dependabot security updates only suggest a change where Dependabot can directly 'fix' the dependency, that is, when these are: Direct dependencies explicitly declared in a manifest or lockfile [or] Transitive dependencies declared in a lockfile." (list item "Transitive dependencies declared in a lockfile" independently confirmed present)

Also reported (not independently re-verified):
> "For npm, Dependabot will raise a pull request to update an explicitly defined dependency to a secure version, even if it means updating the parent dependency. However, for other ecosystems, Dependabot is unable to update an indirect or transitive dependency if it would also require an update to the parent dependency."

### Dependabot's new default version-update cooldown (July 2026)

URL: https://github.blog/security/supply-chain-security/the-case-for-a-cooldown-why-dependabot-now-waits-before-issuing-version-updates/

Reported via WebFetch (not independently re-verified by substring search):

> "A cooldown changes that math. Waiting a few days before adopting a new release gives maintainers, security researchers, and automated scanners time to spot a malicious version and get it pulled before it ever reaches your pull requests."

> "For non-security version bumps, Dependabot now waits at least three days after a release is published before opening a pull request."

Fetch explicitly reported: no verbatim text found specifying whether this cooldown applies to transitive/indirect dependencies vs only direct dependencies. This point is UNRESOLVED per the source itself.

### docs.github.com — Dependabot options reference (`cooldown`)

URL: https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference

Reported via WebFetch (not independently re-verified by substring search):

> "Defines a cooldown period for dependency updates, allowing updates to be delayed for a configurable number of days. The cooldown option is only available for version updates, not security updates."

Fetch explicitly reported: no explicit language addressing whether indirect/transitive dependencies are affected.

### dependabot/dependabot-core#14683 — "npm: dependabot does not respect cooldown period for transitive dependencies"

URL: https://github.com/dependabot/dependabot-core/issues/14683

Reported via WebFetch (not independently re-verified by substring search):

Title: "npm: dependabot does not respect cooldown period for transitive dependencies #14683"

Status: Closed, "Done", assigned to @robaiken, labeled "L: javascript", "T: feature-improvement", "cooldown".

Reporter's finding: direct dependency `aws-cdk-lib` correctly respected a 7-day cooldown; the transitive dependency `@aws-cdk/cloud-assembly-schema` was suggested at a version less than 1 day old, violating the same cooldown.

NOTE: a second WebFetch attempt could not retrieve resolution comments or a linked fixing PR from this issue page — so HOW it was fixed, and whether the fix generalizes beyond this one npm case, is unconfirmed. Scoped to npm only per the issue title; no evidence found that this resolution extends to Bundler/RubyGems.

## GitHub community discussion — Dependabot cooldown and transitive dependencies (generic)

URL: https://github.com/orgs/community/discussions/174897

Reported via WebFetch (not independently re-verified by substring search on final pass, but the phrase "does not recognize the cooldown option" was confirmed present without the "for transitive dependencies" suffix appended by an earlier, less careful fetch):

Original poster's update:
> "Update transitive dependency did not use cooldown option in my trial"

and reported testing detail: direct dependency `@babel/compat-data` updated to 7.28.0 (respecting a 23-day cooldown) while the same package as a transitive dependency (via `@jest/core`) was updated to 7.28.4 (ignoring cooldown).

Commenter **suntsa**, confirmed verbatim on second fetch:
> "dependabot indeed bumps a transient dependency to a version that violates the cooldown period"

suntsa filed dependabot/dependabot-core#14683 (see above) based on this.

## Manual / scheduled bundle-update alternatives

### TechDebt.guru — Dependency Management Guide

URL: https://techdebt.guru/dependency-management/

Confirmed verbatim (re-fetched, substring search):

> "Regenerate lock files periodically to pick up transitive dependency updates."

(under a "Lock File Hygiene" section)

Also reported (not independently re-verified):
> "security patches applied within SLA, minor updates batched weekly, major updates planned quarterly"
> "Diff lock files in code review to catch unexpected changes"
> "Configure auto-merge for patch updates that pass CI. Require manual review for minor and major bumps"

### masutaka/circleci-bundle-update-pr (GitHub repo README)

URL: https://github.com/masutaka/circleci-bundle-update-pr

Reported via WebFetch (not independently re-verified by substring search):

> "`circleci-bundle-update-pr` is an automation script for continuous bundle update and for sending a pull request using Scheduling a Workflow of CircleCI"

> "By requesting a nightly build to CircleCI with an environment variable configured in `circle.yml` or `.circleci/config.yml` to execute this script, bundle update is invoked, then commit changes and send a pull request to GitHub repository if there some changes exist."

Example cron shown in the fetch: weekly, Friday (`00 10 * * 5`). No caveats about PR noise/review burden found in the README itself.

### supermanner/pull-request-on-bundle-update (GitHub Action)

URL: https://github.com/supermanner/pull-request-on-bundle-update

Reported via WebFetch (not independently re-verified by substring search):

> "send pull request on bundle update" (Action description)

Example schedule shown in the fetch: every 15 minutes (illustrative in the README, not a recommended production cadence — the "significant review burden" framing in the earlier fetch summary was the fetch tool's own inference, not a quote from the README; dropped from any Finding).

Requires Gemfile and Gemfile.lock present; generates a dependency diff table via the `bundler-diff` tool; supports specifying reviewers and a custom bundler version.

## Not fetched / could not verify

- https://support.tidelift.com/hc/en-us/articles/26315406262292-Updating-transitive-dependencies — HTTP 403 on WebFetch, twice. UNVERIFIED, not used.
- https://christian-schneider.net/blog/dependency-cooldowns-supply-chain-defense/ — fetched once successfully (see below), not re-fetched for self-check on the second attempt (second attempt to this same URL 403'd — inconsistent server behavior). Quotes below are single-fetch only, flagged accordingly.

### christian-schneider.net — "Dependency cooldowns: a simple supply chain fix" (single fetch, not re-confirmed)

> "Cooldowns must apply to your entire dependency graph, not just direct dependencies. A malicious package introduced as a transitive can still reach production even when your direct imports are carefully curated."

> "The anti-pattern: floating transitive dependencies in production with cooldowns only on direct dependencies. That just moves the golden-hour problem one level down the graph, which is exactly where attackers increasingly aim."

> "Rebuild and review the full dependency graph on a schedule...to catch unexpected transitive additions or version shifts."
