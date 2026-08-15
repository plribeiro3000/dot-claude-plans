# SPIKE — Renovate configuration for a hybrid Gemfile (unconstrained by default, pinned on proven breakage)

## Investigation question

A Rails team declares gems WITHOUT a version constraint by default (`gem 'sidekiq'`),
trusting its test suite and CI to catch a bad upgrade, and pins a small minority ONLY when a
specific upstream version is proven broken (`gem 'connection_pool', '< 4'`). The Gemfile is
therefore hybrid by necessity: a large unconstrained majority plus a small pinned minority
that exists to exclude known-bad versions. Renovate's Bundler manager skips a dependency with
no constraint unless `rangeStrategy: "update-lockfile"` is set; setting it manager-wide
unblocks the unconstrained majority. This spike answers: (1) does the hybrid framing this
question rests on actually hold for the repositories the prior spike examined; (2) can
`rangeStrategy` be scoped by update type (or by "has a constraint") inside a `packageRules`
entry, composed with a manager-wide `update-lockfile` default; (3) has the wider community
documented and solved this hybrid shape; (4) is `allowedVersions` the more idiomatic
Renovate-native tool for the "this version is broken" case, dissolving the need for a Gemfile
pin at all; (5) is the engineer's proposed alternative — two Renovate processes/configurations
running in parallel over the same repository, one handling manifest-level updates and one
handling lockfile-level updates — supported, practiced, and does it solve this specific
problem.

This spike SUPERSEDES `~/Projects/4Shark/dot-claude-plans/active/spike/renovate-mixed-constraint-rangestrategy/SPIKE.md`,
whose Finding 6 claimed three real repositories evidence the hybrid practice; this spike
verifies that claim against the repositories' actual Gemfiles (not just their renovate.json
files) and finds it holds for two of the three, not all three.

## Sources consulted

- `getlago/lago-api` Gemfile, `catatsuy/private-isu` Gemfile, `geeksforsocialchange/PlaceCal`
  Gemfile — fetched verbatim via `curl` from `raw.githubusercontent.com`. See auxiliary
  `renovate-hybrid-gemfile_data_1.md`.
- `lib/util/package-rules/current-value.ts`, `lib/util/string-match.ts`,
  `lib/util/minimatch.ts` — fetched verbatim via `curl`; the `matchCurrentValue: "*"`
  mechanism confirmed empirically against the real `minimatch` npm package. See auxiliary
  `renovate-hybrid-gemfile_excerpt_1.ts`.
- `lib/config/validation.ts` — fetched verbatim via `curl`; the `preLookupOptions` exclusion
  list that makes `rangeStrategy` + `matchUpdateTypes` a hard config-validation error. See
  auxiliary `renovate-hybrid-gemfile_excerpt_2.ts`.
- `docs/usage/configuration-options.md` (`rangeStrategy`, `in-range-only`,
  `packageRules.matchUpdateTypes`, `packageRules.matchCurrentValue`,
  `packageRules.allowedVersions` sections) — fetched verbatim via `curl`. See auxiliary
  `renovate-hybrid-gemfile_doc_1.md`.
- `docs/usage/ruby.md`, `docs/usage/dependency-pinning.md` — fetched verbatim via `curl`. See
  auxiliary `renovate-hybrid-gemfile_doc_2.md`.
- Blog: David Bryant Copeland, "Your Rails and Ruby Versioning and Gemfile Policy",
  naildrivin5.com, 2022-11-17 — fetched via WebFetch, self-checked by re-fetch. See auxiliary
  `renovate-hybrid-gemfile_doc_2.md`.
- `renovatebot/renovate` discussions #10165, #16407, #33609, #9216, #24416, #14727, #12927,
  and issue #16547 — fetched verbatim via `gh api graphql` (raw GitHub GraphQL API, not the
  AI-summarizing WebFetch tool). See auxiliary `renovate-hybrid-gemfile_data_2.json`.

## Findings

### Finding 1: two of the three repositories examined by the prior spike are genuinely hybrid; the third is not — Finding 6's framing partially retracted

**Evidence:** `getlago/lago-api`'s Gemfile carries three inline comments naming the exact
"known-bad-version" reason for a pin, matching the engineer's framing verbatim:

```ruby
# lago-api Gemfile:11
gem "redlock", "~> 2.0.6" # Used through `activejob-uniqueness`. It's pinned to 2.0.x because we patched the library to fix a bug.
# lago-api Gemfile:27
gem "sidekiq-throttled", "1.4.0" # '1.5.0' was losing some jobs
# lago-api Gemfile:52
gem "connection_pool", "<3" # Temporary fix. See https://github.com/mperham/connection_pool/issues/212
```

`geeksforsocialchange/PlaceCal`'s Gemfile also carries a constrained minority (`rails '~>
8.0'`, `brakeman '~> 8.0'`, four exact-pinned `rubocop*` gems, etc.) against an unconstrained
majority — hybrid, though without inline "why" comments.

`catatsuy/private-isu`'s ONLY Gemfile (`webapp/ruby/Gemfile`, confirmed via `gh search code
"filename:Gemfile" --repo catatsuy/private-isu`, which returns exactly `webapp/ruby/Gemfile`
and its `.lock`) is uniformly unconstrained — every gem line carries no version specifier at
all, aside from a `git:`/`ref:` pin on `unicorn` (a different mechanism entirely: a
git-refs-datasource pin, not a Gemfile version-range `currentValue` that
`matchCurrentValue`/`CurrentValueMatcher` reasons about the same way).

**Source:** Full Gemfiles in `renovate-hybrid-gemfile_data_1.md`.

**Significance:** The prior spike's Finding 6 stated that "real, live Ruby/Rails repositories
apply `rangeStrategy: update-lockfile` uniformly across the WHOLE bundler manager" as evidence
for the hybrid scenario. That underlying observation (none of the three write a packageRule
splitting constrained from unconstrained gems) remains true for all three — but as evidence
*specifically for the hybrid Gemfile shape*, it holds for `lago-api` and `PlaceCal` only.
`private-isu` is not hybrid and should not be cited as an example of the engineer's scenario.

**Verification block:** URLs fetched: the three raw Gemfile URLs, via `curl` (direct
byte-for-byte retrieval, not AI-summarizing fetch). Verbatim quotes checked. Quote
substrings confirmed present at the cited line numbers in each file (re-read after fetch).

### Finding 2: `rangeStrategy` cannot be scoped by `matchUpdateTypes` in a `packageRule` — this is a hard, current, config-validation ERROR, not a design limitation that could be worked around

**Evidence:**
```typescript
// lib/config/validation.ts
const preLookupOptions = [
  'allowedVersions', 'extractVersion', 'followTag', 'ignoreDeps', 'ignoreUnstable',
  'rangeStrategy', 'registryUrls', 'respectLatest', 'rollbackPrs', 'separateMajorMinor',
  'separateMinorPatch', 'separateMultipleMajor', 'separateMultipleMinor', 'versioning',
] as const;
if (isNonEmptyArray(resolvedRule.matchUpdateTypes)) {
  for (const option of preLookupOptions) {
    if (resolvedRule[option] !== undefined) {
      const message = `${currentPath}[${subIndex}]: packageRules cannot combine both matchUpdateTypes and ${option}. Rule: ...`;
      errors.push({ topic: 'Configuration Error', message });
    }
  }
}
```
Maintainer confirmation, current and historical, from two GitHub discussions fetched raw via
GraphQL:

> "`rangeStrategy` is used *before* update types are assigned. Therefore you can't assign a
> `rangeStrategy` with a rule that matches update types, because it will be assigned too
> late." — rarkins, discussion #10165, 2021-05-26

> "No, because range strategy is used to decide major/minor. What are you trying to achieve?"
> — rarkins, discussion #16407, 2022-07-04

**Source:** `lib/config/validation.ts` (verbatim `curl` fetch, cross-checked via `gh api
"search/code?q=repo:renovatebot/renovate+%22cannot combine both matchUpdateTypes%22"`, which
returns exactly 2 hits — `validation.ts` and its `.spec.ts` — confirming the rule is present
in the current codebase, not a historical/removed check); discussions #10165 and #16407 via
`gh api graphql`. Full text in auxiliaries `renovate-hybrid-gemfile_excerpt_2.ts` and
`renovate-hybrid-gemfile_data_2.json`.

**Significance:** This directly answers the highest-priority research question. The composed
config the engineer proposed evaluating —
`{ matchManagers: ["bundler"], matchUpdateTypes: ["major"], rangeStrategy: "replace" }`
alongside a manager-wide `update-lockfile` default — is not merely inadvisable; Renovate's own
config validator rejects it outright with `errors.push` (a hard failure the whole config run
would refuse to execute on), because `rangeStrategy` and `matchUpdateTypes` are structurally
sequenced: `rangeStrategy` determines which candidate update is even considered (and thereby
what "major"/"minor"/"patch" means for that dependency), so a rule that tries to read
`matchUpdateTypes` to decide `rangeStrategy` is asking for information that does not exist yet
at the point it would need it. This forecloses the literal shape of the highest-value research
question as asked.

**Verification block:** URL fetched: `https://raw.githubusercontent.com/renovatebot/renovate/main/lib/config/validation.ts`.
Verbatim quote checked. Quote substring `packageRules cannot combine both matchUpdateTypes and`
confirmed present. Discussions #10165 and #16407 fetched via `gh api graphql` (raw API
response, not AI-summarized); quoted maintainer sentences reproduced byte-for-byte from the
GraphQL `body`/`comments.nodes[].body` fields.

### Finding 3: a DIFFERENT mechanism — `matchCurrentValue: "*"` — is a generic, non-enumerated selector for "this gem carries a Gemfile constraint", and it is technically valid to combine with `rangeStrategy`

**Evidence:**
```typescript
// lib/util/package-rules/current-value.ts
export class CurrentValueMatcher extends Matcher {
  override matches({ currentValue }, { matchCurrentValue }): boolean | null {
    if (isUndefined(matchCurrentValue)) { return null; }
    const matchCurrentValuePred = getRegexOrGlobPredicate(matchCurrentValue);
    if (!currentValue) { return false; }          // unconstrained gem never reaches the predicate
    return matchCurrentValuePred(currentValue);
  }
}
```
Empirical test against the real `minimatch` npm package (installed locally, `node -e` run
directly, not inferred from documentation):

```
new Minimatch('*', {dot:true, nocase:true}).match('~> 8.0')  => true
new Minimatch('*', {dot:true, nocase:true}).match('<3')      => true
new Minimatch('*', {dot:true, nocase:true}).match('1.4.0')   => true
new Minimatch('*', {dot:true, nocase:true}).match('>= 7.0')  => true
new Minimatch('*', {dot:true, nocase:true}).match('')        => false
```

`lib/config/validation.ts` grep for `matchCurrentValue` shows no exclusivity restriction
against `rangeStrategy` — `matchCurrentValue` is checked only for regex-shape validity and for
being nested inside a `packageRule`, neither of which conflicts with `rangeStrategy`.

**Source:** `lib/util/package-rules/current-value.ts`, `lib/util/string-match.ts`,
`lib/util/minimatch.ts` (verbatim `curl` fetches); local empirical test run against the
`minimatch` package (`npm install minimatch --prefix /tmp/mm-test`, then `node -e`). Full
text and full test transcript in auxiliary `renovate-hybrid-gemfile_excerpt_1.ts`.

**Significance:** This was not asked for directly (the research question named
`matchUpdateTypes` specifically) but answers the same underlying need — a mechanical way to
scope `rangeStrategy` to "the constrained minority" without enumerating gem names. Because
`CurrentValueMatcher` short-circuits to `false` before ever running the glob predicate when
`currentValue` is falsy (unconstrained), and because `minimatch`'s `"*"` glob matches every
realistic non-empty Gemfile constraint string, a packageRule of the shape
`{ matchCurrentValue: "*", rangeStrategy: "replace" }` (or any other non-`update-lockfile`
strategy) would apply ONLY to gems that already carry a constraint, leaving every
unconstrained gem to the manager-wide `update-lockfile` default — with no name list, and no
recurring manual maintenance when a new pin is added or removed. This is a distinct
possibility from the `matchUpdateTypes` approach that Finding 2 forecloses, and it was not
identified by the prior spike (which examined `matchCurrentValue` in Finding 3 only to
conclude it "cannot be used to build a generic 'has a constraint' vs. 'has no constraint'
split" — that conclusion is correct in the negative direction (cannot select
*unconstrained*-only) but did not test the POSITIVE direction (`"*"` selecting
*constrained*-only), which this spike found to work.

**Verification block:** URLs fetched: `https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-value.ts`,
`.../lib/util/string-match.ts`, `.../lib/util/minimatch.ts`. Verbatim quotes checked. Quote
substrings confirmed present. The minimatch behavior is an independently-run empirical result,
not a claim sourced from a fetched page — reproducible via the exact commands recorded in the
auxiliary file.

### Finding 4: the community documents this exact hybrid policy for the Gemfile side, independent of Renovate — but does not connect it to a Renovate `rangeStrategy` configuration

**Evidence:**
> "No other gems should have a version specifier unless the latest version is incompatible
> with your app in some way." ... "If the latest version of any gem is not compatible with
> your app or another dependency, pin the version of the gem in your `Gemfile` (using the
> pessimistic operator if possible) and add a comment"

— David Bryant Copeland, "Your Rails and Ruby Versioning and Gemfile Policy",
naildrivin5.com, 2022-11-17.

The same post names Dependabot, not Renovate, and only in a different context ("it won't
create a forcing-function around checking that pinned dependencies can be unpinned") — it does
not discuss `rangeStrategy` or any bot's range-update composition at all.

Separately, a live GitHub discussion asking almost the identical question received no
maintainer answer:

> "generally we use caret ranges, but when we pin a package, it's usually because of an issue
> with more recent versions of that package that need to be resolved" — joekur, discussion
> #12927, 2021-12-02 (zero comments)

**Source:** Blog post (WebFetch, self-checked via re-fetch confirming the same substring twice);
discussion #12927 (`gh api graphql`, raw). Full text in auxiliaries `renovate-hybrid-gemfile_doc_2.md`
and `renovate-hybrid-gemfile_data_2.json`.

**Significance:** The engineer's premise that this is a common team policy is corroborated by
an independent, named, dated source describing the identical shape (unconstrained by default,
pin-with-a-comment on proven breakage). What was searched for and NOT found: any Ruby/Rails
blog post, conference talk, or Renovate discussion that connects this Gemfile-side policy to a
specific Renovate `rangeStrategy`/`packageRules` recipe. Search terms tried (recorded for
completeness): "Gemfile no version constraint trust CI Renovate rangeStrategy policy",
"renovate.json two separate configs one for lockfile updates one for manifest updates",
"allowedVersions renovate instead of pinning Gemfile package.json best practice avoid broken
release", "renovate.json rangeStrategy update-lockfile some gems pinned exception Gemfile
github issue", "Ruby Rails team policy unpinned Gemfile gems rely on test suite CI catch
breaking upgrade blog". The closest hit each time was the general pinning-vs-ranges debate
(Renovate's own `dependency-pinning.md`) or the mechanism discussions already covered in
Findings 2–3, not a worked hybrid-Gemfile-plus-Renovate example.

**Verification block:** URL fetched: `https://naildrivin5.com/blog/2022/11/17/your-rails-and-ruby-versioning-and-gemfile-policy.html`.
Quote substrings confirmed present on two independent fetches. Discussion #12927 fetched via
`gh api graphql`; body quoted verbatim from the raw API response.

### Finding 5: real-world hybrid Gemfiles do not special-case their pinned minority in `renovate.json` at all — they apply `update-lockfile` uniformly and rely on its documented per-dependency fallback

**Evidence:** Neither `lago-api` nor `PlaceCal` (the two confirmed-hybrid repositories from
Finding 1) writes any `matchCurrentValue`, `matchPackageNames`-enumerated, or other
packageRule that treats their pinned gems (`connection_pool`, `sidekiq-throttled`, `redlock`,
`rails`, `brakeman`, the pinned `rubocop*` family) any differently from the unconstrained
majority. `lago-api`'s renovate.json sets `"rangeStrategy": "update-lockfile"` once, globally.
`PlaceCal`'s sets a global `"rangeStrategy": "pin"` for everything else and overrides it to
`"update-lockfile"` for the whole `bundler` manager in one packageRule — again scoped by
MANAGER, not by individual-gem constraint status.

**Source:** `renovate-mixed-constraint_data_1.json` (prior spike's auxiliary, cross-referenced
in this spike; the two files' contents were re-read as part of this spike's Finding 1 work).

**Significance:** This is direct evidence — not inference — about actual practice among the
two confirmed hybrid examples: "do nothing extra; let the documented `update-lockfile` →
`replace`-on-out-of-range fallback handle both halves" is what real hybrid Gemfile
repositories using Renovate do today. This corroborates Option A from the prior spike, now on
a corrected evidence base (two hybrid repos, not three).

**Verification block:** Re-derived from the prior spike's already-verified auxiliary file
(`renovate-mixed-constraint_data_1.json`, itself fetched via `curl` from
`raw.githubusercontent.com`); no new fetch performed for this finding, cross-checked against
the newly-fetched Gemfiles in Finding 1 to confirm which repos the "no special-casing"
observation legitimately applies to.

### Finding 6: the specific "flipper" fallback failure the prior spike could not resolve was confirmed by the reporter to be a grouping-specific bug, not a general single-dependency failure — resolves the prior spike's open uncertainty

**Evidence:**
> "Does it only happen if you group the flipper dependencies?" — rarkins, 2022-07-12
>
> "OK, so it does appear to work without the grouping, so it's an issue w/ grouping." —
> narwold (the original reporter), 2022-07-13

Issue state, fetched fresh: `"state":"CLOSED","stateReason":"COMPLETED","closedAt":"2022-12-07T15:00:51Z"`.

**Source:** `gh api graphql`, issue #16547, raw API response including full comment thread.
Full text in auxiliary `renovate-hybrid-gemfile_data_2.json`.

**Significance:** The prior spike's "What remains uncertain" section could not confirm
"whether the `flipper`-style out-of-range failure ... is fully resolved ... for a single,
non-grouped constrained dependency, or whether that PR only fixed the narrower
grouped-dependency symptom." The reporter's own follow-up testing, in the original bug thread,
directly answers this: the `update-lockfile` → `replace` fallback worked correctly for a
single non-grouped dependency at the time of the report; the failure was specific to grouped
dependency updates (matching PR #19058's description from the prior spike). This raises
confidence in Option A/Finding 5's "do nothing extra" approach for an UNGROUPED constrained
gem — which is the shape of `lago-api`'s and `PlaceCal`'s pinned minorities (none of them are
grouped via `groupName` with another dependency in a way that would recreate the flipper
scenario).

**Verification block:** URL/API fetched: `gh api graphql` for `renovatebot/renovate` issue
#16547. Verbatim quotes checked against the raw `comments.nodes[].body` fields. Quote
substrings confirmed present.

### Finding 7: the engineer's two-process proposal is explicitly addressed by a maintainer — the literal shape ("two committed config files in one repo, each Renovate instance reads one") is refused as "not possible"; a different shape (two globally-configured bot identities) is offered as a working alternative, for a different underlying problem than this one

**Evidence:**

The literal shape — two `renovate.json`-style files committed in-repo, each instance pointed
at one via `RENOVATE_CONFIG_FILE` or similar:

> "I would like to split this one Renovate into two - one for terraform, one for everything
> else. My thinking was to create two files - `renovate.json5` and `renovate-terraform.json5`
> ... and point each Renovate instance at a single file. However, I cannot figure out how to
> actually do such a thing. Is this even possible?" — diversario, discussion #33609,
> 2025-01-14
>
> "not possible" — viceice (maintainer), 2025-01-17

A working alternative shape, offered by a maintainer for a DIFFERENT motivating problem
(credential/least-privilege isolation across AWS regions in one monorepo, not a
constrained-vs-unconstrained split within one manager):

> "You may be able to achieve what you want today with the following:
> - Use a different bot identity (either app or user PAT) for each bot
> - Do not use repo config (e.g. `renovate.json`) except if it's common for all bots
> - Use different global config (e.g. `config.js`) for each bot
> - Use a different `branchPrefix` for each bot so that they can ignore each others'
>   branches" — rarkins (maintainer), discussion #24416, 2023-09-14

The mechanism BEHIND the "not possible" answer, from an earlier, related discussion:

> "You cannot have multiple config files, but you can control your configuration fully
> through `packageRules`, each of which can have a `matchPaths` or `matchFiles` field to limit
> the rule." — rarkins, discussion #9216, 2021-03-18
>
> "This works except that renovate closes pull requests which it thinks should be cleaned up.
> For example, if config A runs an npm manager and config B runs a gomod manager, then running
> config B after config A seems to close all npm related pull requests." — jdechicchis,
> discussion #9216, 2021-03-18 (the failure mode the branchPrefix isolation in #24416's
> answer is built to avoid)

**Source:** `gh api graphql`, discussions #33609, #24416, #9216. Full text in auxiliary
`renovate-hybrid-gemfile_data_2.json`.

**Significance:** Directly answers Question 5. As LITERALLY proposed (two configs, same
manager, same repo, expecting Renovate to natively route each gem to the right process), a
maintainer states this is "not possible." The recipe that DOES work today (rarkins,
discussion #24416) requires: a distinct bot identity per process, no repo-committed config
shared between them, distinct global/server-side config per bot, and a distinct
`branchPrefix` per bot so each bot's cleanup pass ignores the other's branches (the mechanism
that would otherwise trigger the PR-closing conflict documented in discussion #9216). This
recipe is real and sourced, but it was designed for a DIFFERENT axis of separation than the
engineer's (least-privilege credential isolation across disjoint sub-trees of a monorepo, or
disjoint MANAGERS like terraform-vs-everything-else) — every example found uses a split where
the two processes' dependency SETS are disjoint by construction (different paths, different
managers, different credentials). The engineer's proposed split (manifest-level vs.
lockfile-level updates for gems within the SAME `bundler` manager, on the SAME `Gemfile`)
would require each process's config to select a DISJOINT SET of gems by
constrained-vs-unconstrained status — and Finding 2/Finding 3 already establish that the only
generic (non-enumerated) mechanism for that split is `matchCurrentValue: "*"`, which works
inside a SINGLE process's `packageRules` just as well as it would inside either of two
processes' configs. Running two processes does not remove the need for that selector, or for
an enumerated name list if the selector is not used; it only adds the operational cost of two
bot identities, two branch prefixes, and two schedules to coordinate.

**Verification block:** URL/API fetched: `gh api graphql` for discussions #33609, #24416, and
#9216 in `renovatebot/renovate`. Verbatim quotes checked against the raw `body`/`comments.nodes[].body`
fields. Quote substrings confirmed present.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| **A — do nothing extra**: `rangeStrategy: "update-lockfile"` manager-wide, no packageRule split | Zero extra config; matches documented per-dependency fallback design; is what BOTH confirmed hybrid repos (`lago-api`, `PlaceCal`) actually do; the specific historical fallback bug is confirmed grouping-specific, not general | Relies on the `replace`-fallback path for out-of-range constrained deps; current-day reliability for THIS repository's specific gems was not independently re-tested (no write/execution access in this spike) | Findings 1, 5, 6 |
| **B — enumerate the constrained gems by name** (`matchPackageNames`), set `rangeStrategy: "replace"` for that list, leave `update-lockfile` as the default | Matches the one path a maintainer confirmed worked in the one documented failure case; explicit, human-auditable list | Requires maintaining a name list by hand as pins are added/removed — the kind of recurring manual step the engineer's framing pushes against; not observed in either confirmed hybrid repo | Prior spike Finding 2; this spike Finding 5 |
| **C — `{ matchCurrentValue: "*", rangeStrategy: "replace" }` (or similar) as ONE packageRule, manager-wide `update-lockfile` as the fallback default** | No name list to maintain — the constrained/unconstrained split is generic and automatic as pins are added/removed; technically valid per current source (no exclusivity conflict); requires exactly one packageRule, once | Not observed in the wild in either confirmed hybrid repo (novel to this spike, not a documented community pattern); the semantics of "`replace` only for the constrained set, `update-lockfile` for everything else via the DEFAULT" needs to be confirmed to compose correctly at the config level (packageRule list ordering / merge semantics were not independently tested beyond the validation-layer check) | This spike, Finding 3 |
| **D — `matchUpdateTypes` scoped `rangeStrategy`** (the literally-proposed research question) | — | **Not viable at all** — hard config-validation error in the current source; the config would fail to load | This spike, Finding 2 |
| **E — move known-bad-version exclusions into `renovate.json` via `allowedVersions`, leave the Gemfile fully unconstrained** | Gemfile stays uniformly unconstrained (removes the hybrid shape entirely, so `update-lockfile` applies with no ambiguity); the exclusion lives in one central, versioned, PR-reviewable place; a regex-negation form (`!/^1\.5\.0$/`) can exclude one bad version while still allowing later fixed releases, which a hard Gemfile pin (`"1.4.0"`) cannot do without a manual revisit | `bundle install`/`bundle update` run OUTSIDE Renovate (a developer's machine, independent CI) has no knowledge of the exclusion — nothing stops a local `bundle update` from picking the known-bad version, unlike a Gemfile pin which Bundler itself enforces; still requires one packageRule per excluded gem (same list-maintenance cost as Option B, just relocated) | This spike, Finding-adjacent research (Question 4); `renovate-hybrid-gemfile_doc_1.md` |
| **F — two parallel Renovate processes, split by manifest-vs-lockfile updates** (engineer's proposal, as literally stated) | — | **The literal shape is refused by a maintainer as "not possible"** (two config files, one manager, one repo); the documented WORKING alternative (separate bot identity + branchPrefix + no shared repo config) was designed for a disjoint-dependency-set problem (credentials, different managers) and does not by itself supply the constrained/unconstrained selector this problem needs — Option C's `matchCurrentValue: "*"` would still be required inside each process's config, at which point a second process adds coordination cost without adding capability | This spike, Finding 7 |

## What remains uncertain

- Whether Option C's `{ matchCurrentValue: "*", rangeStrategy: "replace" }` packageRule
  actually produces the intended split when run against a real repository — this spike
  confirmed the MATCHER behaves as expected (via the source code and an empirical minimatch
  test) and confirmed no config-validation conflict, but did not run Renovate itself against a
  live repository (no write/execution access in this spike's scope). Not found: a documented
  case of anyone using this exact technique for this exact purpose.
- Whether `update-lockfile`'s `replace`-on-out-of-range fallback is reliable TODAY for the
  specific gems in this repository's Gemfile — Finding 6 resolves the historical `flipper`
  uncertainty (grouping-specific, not general) but that is still a 2022-era report; no fresh
  live test was run in this spike.
- Whether any Ruby/Rails-specific (as opposed to general npm/JS-ecosystem) writeup of the
  hybrid-Gemfile-plus-Renovate configuration problem exists outside what was found — the
  searches in Finding 4 were run in English only, against public web search and GitHub; a
  non-English source, a private/internal engineering blog, or a conference talk not indexed by
  the search tools used could exist and was not found.
- Whether the `allowedVersions` regex-negation form (`!/pattern/`) is validated by Renovate
  the same way `matchCurrentValue`'s documented `!/ /` negation is — the doc page for
  `allowedVersions` does not show a negation example the way `matchCurrentValue`'s does, and
  this spike did not independently test whether `allowedVersions` accepts the `!`-prefixed
  regex form in practice (the code path in `lib/config/validation.ts` treats both fields
  identically via the shared `isRegexMatch`/`getRegexPredicate` functions, which DO support
  the `!` prefix generically — so this is inferred from source, not confirmed by a live test
  or a documented example using `allowedVersions` specifically with `!/ /`).

## Suggested options for main and the engineer

- **Option A — do nothing extra.** Keep `rangeStrategy: "update-lockfile"` as the sole
  bundler-manager setting. Matches what both confirmed real hybrid Gemfile repositories
  (`lago-api`, `PlaceCal`) actually run, and the specific historical fallback bug is now known
  to be grouping-specific rather than a general risk for an ungrouped pinned gem.
- **Option B — enumerate the constrained gems by name** in a `matchPackageNames` packageRule
  with `rangeStrategy: "replace"`, leaving `update-lockfile` as the default elsewhere. Costs a
  name list to maintain.
- **Option C — a single generic packageRule using `matchCurrentValue: "*"`** to scope
  `rangeStrategy: "replace"` (or another non-`update-lockfile` strategy) to every currently
  constrained gem, with `update-lockfile` remaining the manager-wide default for everything
  else. No name list; technically valid per current source; not independently confirmed live
  and not observed as a documented community pattern.
- **Option E — relocate known-bad-version exclusions into `renovate.json`'s `allowedVersions`**,
  letting the Gemfile itself become uniformly unconstrained. Removes the hybrid shape at the
  source; trades a Gemfile-enforced exclusion (works even outside Renovate) for a
  Renovate-only one (a local `bundle update` would not respect it).
- **Option F — the two-process proposal, as literally stated, is not available.** A working
  two-process shape exists (separate bot identity, no shared repo config, separate
  `branchPrefix`) but was designed for a different problem (disjoint dependency sets by path,
  manager, or credential) and does not supply the constrained/unconstrained selector this
  problem needs on its own — Option C's selector would still have to do that work, inside
  whichever process(es) run.

No option is recommended above another — the trade-offs table and the open uncertainties are
the deciding inputs.
