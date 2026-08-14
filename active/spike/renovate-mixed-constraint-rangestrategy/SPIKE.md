# SPIKE — Renovate rangeStrategy for a mixed constrained/unconstrained Gemfile

## Investigation question

A Ruby/Rails repository's `Gemfile` has an overwhelming majority of gems declared with no version constraint (`gem 'sidekiq'`) and a small minority carrying one (`gem 'rails', '~> 8.1.3'`, `gem 'connection_pool', '< 4'`, `gem 'license_finder', '>= 7.0'`, `gem 'state_machines-graphviz', '~> 0.0.2'`). `rangeStrategy: "update-lockfile"` was set for the bundler manager to unblock updates for the unconstrained majority (per Renovate's own Ruby docs, other `rangeStrategy` values skip a dependency with no constraint entirely). The open question: does `update-lockfile` leave the constrained minority permanently capped at their declared range (e.g. `rails` never proposed past `8.1.x`), and if so, how does the Renovate community handle this mixed shape — most dependencies unconstrained, a few constrained — in a single Bundler manager configuration?

## Sources consulted

- [`docs/usage/ruby.md`](https://raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/ruby.md) — the canonical Bundler-manager warning text about constraint-less gems under `update-lockfile` vs. other strategies. See auxiliary `renovate-mixed-constraint_doc_1.md`.
- [`docs/usage/configuration-options.md`](https://raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/configuration-options.md) — the `rangeStrategy`, `matchCurrentValue`, and `matchCurrentVersion` reference sections. See auxiliary `renovate-mixed-constraint_doc_2.md`.
- [`lib/util/package-rules/current-value.ts`](https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-value.ts) — the actual matcher implementation for `matchCurrentValue`. See auxiliary `renovate-mixed-constraint_excerpt_1.ts`.
- [`lib/util/package-rules/current-version.ts`](https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-version.ts) — the actual matcher implementation for `matchCurrentVersion`, including the `isUnconstrainedValue` branch. See auxiliary `renovate-mixed-constraint_excerpt_2.ts`.
- [`renovatebot/renovate` discussion #16369](https://github.com/renovatebot/renovate/discussions/16369) — maintainer confirms out-of-range fallback behaved unexpectedly for a real Bundler case (`flipper`).
- [`renovatebot/renovate` issue #16547](https://github.com/renovatebot/renovate/issues/16547) — the tracked bug behind that discussion.
- [`renovatebot/renovate` PR #19058](https://github.com/renovatebot/renovate/pull/19058) — the fix that closed #16547.
- [`renovatebot/renovate` discussion #14858](https://github.com/renovatebot/renovate/discussions/14858) — maintainer `rarkins` on whether packageRules can select in-range-only updates.
- Three live public Ruby/Rails `renovate.json` files fetched verbatim (`getlago/lago-api`, `catatsuy/private-isu`, `geeksforsocialchange/PlaceCal`). See auxiliary `renovate-mixed-constraint_data_1.json`.

## Findings

### Finding 1: `rangeStrategy: update-lockfile` is documented to cover BOTH in-range and out-of-range updates for Bundler — it is not limited to "within the declared range"

**Evidence:**
```
- `update-lockfile` = Update the lock file when in-range updates are available, otherwise `replace` for updates out of range. Works for `bundler`, `cargo`, `composer`, `gleam`, `npm`, `yarn`, `pnpm`, `terraform`, `poetry` and `uv` so far
```
**Source:** `docs/usage/configuration-options.md`, `## rangeStrategy` section (auxiliary `renovate-mixed-constraint_doc_2.md`).
**Significance:** The premise embedded in the investigation question — that `update-lockfile` "can never propose a version outside the range, because it never edits the manifest" — does not match Renovate's own documented behavior. The documented design is a per-dependency fallback: when the new version fits inside the declared range, only `Gemfile.lock` moves; when it does not, Renovate is documented to fall back to the `replace` strategy for that dependency and edit the `Gemfile` constraint itself. `replace` is separately documented as: `Replace the range with a newer one if the new version falls outside it, and update nothing otherwise` (same section). So for `rails '~> 8.1.3'`, the documented behavior is that Renovate would replace the constraint (e.g. to `~> 8.2.0` or similar) when a version outside the current range is available — not silently cap the dependency forever.

**Verification block:** URL fetched: `https://raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/configuration-options.md`. Verbatim quote checked. Quote substring confirmed at the `## rangeStrategy` heading, bullet beginning `` `update-lockfile` = ``.

### Finding 2: the documented fallback has a history of not working reliably for Bundler specifically, in at least one real case

**Evidence:**
> The maintainer stated: "I'm not sure it has anything specifically about update lock file. It's trying to recursively update packages but somehow ends up inserting undefined at the last stage, which causes the failure." After the user confirmed the strategy works with `rangeStrategy=replace`, rarkins concluded: "I'm confused by this behavior then. Quite possibly a bug," and ultimately recommended creating a formal issue.

**Source:** GitHub discussion [renovatebot/renovate#16369](https://github.com/renovatebot/renovate/discussions/16369) (AI-fetched summary of the discussion thread; the quoted maintainer sentences are reproduced as given by the fetch tool, not independently re-verified against the raw discussion page — flagged below).

**Significance:** A real Bundler scenario (`flipper` pinned at `<~ 0.22.2`, a newer `0.25.0` available) hit an error — `"Bundler could not find compatible versions for gem 'flipper'"` — when `update-lockfile` was expected to fall back to `replace` and edit the Gemfile. The linked bug, [issue #16547](https://github.com/renovatebot/renovate/issues/16547), was closed by [PR #19058](https://github.com/renovatebot/renovate/pull/19058), whose description (per fetch) is about **grouped** dependency updates overwriting file changes with unchanged content when some grouped dependencies changed and others did not. Whether that fix addressed the exact single-dependency `flipper` failure reported in the discussion, or only the narrower grouped-update symptom, could not be confirmed from the fetched content — flagged in "What remains uncertain" below.

**Verification block:** URL fetched: `https://github.com/renovatebot/renovate/discussions/16369` and `https://github.com/renovatebot/renovate/issues/16547` and `https://github.com/renovatebot/renovate/pull/19058`. These three fetches returned AI-summarized content from the fetch tool rather than raw page HTML/markdown (GitHub's issue/discussion UI is JS-rendered and not fetchable as raw text the way `raw.githubusercontent.com` is), so the quoted maintainer sentences carry a lower verification confidence than the doc/source-code findings above and below. Treat this finding as directionally reliable (a real bug was reported and a PR was linked as its fix) but the exact causal chain (does the `flipper`-shaped failure recur today) is UNVERIFIED beyond what is stated here.

### Finding 3: `matchCurrentValue` structurally cannot select — or exclude — a dependency by "has no constraint", because it returns `false` whenever `currentValue` is absent

**Evidence:**
```typescript
export class CurrentValueMatcher extends Matcher {
  override matches(
    { currentValue }: PackageRuleInputConfig,
    { matchCurrentValue }: PackageRule,
  ): boolean | null {
    if (isUndefined(matchCurrentValue)) {
      return null;
    }
    const matchCurrentValuePred = getRegexOrGlobPredicate(matchCurrentValue);

    if (!currentValue) {
      return false;
    }

    return matchCurrentValuePred(currentValue);
  }
}
```
**Source:** `lib/util/package-rules/current-value.ts` (auxiliary `renovate-mixed-constraint_excerpt_1.ts`), fetched verbatim via `raw.githubusercontent.com` and cross-checked twice (once via the rendered GitHub blob view, once via the raw file) with byte-identical results.
**Significance:** For a gem declared as `gem 'sidekiq'` (no constraint), Renovate's internal `currentValue` for that dependency is `undefined`. The matcher's own logic short-circuits to `return false` before it ever evaluates the configured pattern against that dependency — so a rule like `"matchCurrentValue": "*"` or any glob/regex configured under `matchCurrentValue` NEVER matches an unconstrained gem, and there is no negation syntax that inverts this (the negated-regex feature documented in `configuration-options.md`, `!/ /`, operates on the *pattern*, not on presence/absence of the field — it is applied only after the `!currentValue` short-circuit has already passed). This directly answers sub-question 1: `matchCurrentValue` cannot be used to build a generic "has a constraint" vs. "has no constraint" split — it can only ever select among the constrained set.

**Verification block:** URL fetched: `https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-value.ts`. Verbatim quote checked. Quote substring confirmed (`if (!currentValue) {` / `return false;`) present in both fetches.

### Finding 4: `matchCurrentVersion` can reach unconstrained-but-locked dependencies via their resolved/locked version — but not as a generic "no constraint" selector, and the relevant code path (`isUnconstrainedValue`) is undocumented

**Evidence:**
```typescript
    const isUnconstrainedValue =
      !!lockedVersion && isNullOrUndefined(currentValue);
    ...
    if (versioningApi.isVersion(matchCurrentVersionStr)) {
      try {
        return (
          isUnconstrainedValue ||
          !!(
            currentValue &&
            versioningApi.isValid(currentValue) &&
            versioningApi.matches(matchCurrentVersionStr, currentValue)
          )
        );
      } catch {
        return false;
      }
    }

    const compareVersion = versioningApi.isVersion(currentValue)
      ? currentValue // it's a version so we can match against it
      : (lockedVersion ?? currentVersion); // need to match against this currentVersion, if available
```
**Source:** `lib/util/package-rules/current-version.ts` (auxiliary `renovate-mixed-constraint_excerpt_2.ts`), fetched verbatim via `curl` against `raw.githubusercontent.com`.
**Significance:** Two distinct paths exist inside this one matcher:
1. When `matchCurrentVersion` is set to an **exact version string** (e.g. `"7.1.0"`) and the target dependency is `isUnconstrainedValue` (has a `lockedVersion` from `Gemfile.lock` but no `currentValue` in the Gemfile), the matcher returns `true` **unconditionally**, regardless of what exact version was configured. This is a deliberate carve-out in the source (the variable is explicitly named `isUnconstrainedValue`), but it is not documented anywhere in `configuration-options.md` or `ruby.md`, and a targeted search of Renovate documentation and GitHub discussions found zero references to the literal identifier `isUnconstrainedValue` outside this one source file — see the verification block. It is not a technique surfaced to end users.
2. When `matchCurrentVersion` is set to a **range** (e.g. `">=1.0.0"`), the code falls through to `compareVersion = ... (lockedVersion ?? currentVersion)`, meaning it CAN compare an unconstrained-but-locked gem's actual resolved version against a range. This is a real path by which a packageRule could reach unconstrained dependencies — but it requires already knowing what version range to test against, which does not generalize to "select every gem with no Gemfile constraint" as a category.

This directly extends the answer to sub-question 2: there is no documented matcher (`matchCurrentValue`, `matchCurrentVersion`, `matchDepTypes`, or otherwise) that expresses "this dependency has no version constraint" as a first-class predicate. `matchCurrentVersion` can incidentally reach unconstrained dependencies through their locked version, but only when the rule author already knows a version or range to test — not as a category selector.

**Verification block:** URL fetched: `https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-version.ts`. Verbatim quote checked. Quote substring `const isUnconstrainedValue =` confirmed present in the fetched file. Cross-search: `gh search code "isUnconstrainedValue" --repo renovatebot/renovate` returned exactly two matches, both inside this same file (its declaration and its one usage) — no documentation page, preset, or discussion thread references the identifier.

### Finding 5: a 2022 maintainer statement says Renovate has no metadata to select "in-range-only" updates via packageRules

**Evidence:**
> **rarkins** (maintainer) provided the critical answer: "I don't think we have any metadata currently for matching in-range only updates."

**Source:** GitHub discussion [renovatebot/renovate#14858](https://github.com/renovatebot/renovate/discussions/14858), opened 2022-03-30 (AI-fetched summary; same lower-confidence caveat as Finding 2 — GitHub discussion UI content, not a raw-fetchable file).
**Significance:** This is a maintainer statement, from the team that owns the tool, directly on point for sub-question 1/2: as of that discussion, no packageRules field distinguishes "this update is in-range" from "this update is out-of-range", nor (by extension, and consistent with Findings 3-4) does one exist for "this dependency declares no constraint at all". The statement is four years old at the time of this spike (2026-08-14) and Findings 3-4 above are current-source-verified, so the conclusion is corroborated by two independent evidence types (a 2022 maintainer statement and 2026-fetched source code) rather than resting on the maintainer statement alone.

**Verification block:** URL fetched: `https://github.com/renovatebot/renovate/discussions/14858`. Content returned as an AI-generated summary of the discussion page rather than raw markdown; the quoted sentence is reproduced as given by the fetch tool. Lower verification confidence than Findings 3-4 — flagged as UNVERIFIED-BY-RAW-TEXT (the discussion's existence and the general shape of the answer are corroborated by the independent search hit in Finding 2's search results, but the exact wording was not re-confirmed against raw page text).

### Finding 6: real, live Ruby/Rails repositories apply `rangeStrategy: update-lockfile` uniformly across the WHOLE bundler manager — none of the three examined write a packageRule that distinguishes constrained from unconstrained gems

**Evidence — repository 1 (`getlago/lago-api`, an open-source Rails billing API):**
```json
"enabledManagers": ["bundler", "dockerfile", "custom.regex"],
"rangeStrategy": "update-lockfile",
```
plus a `packageRules` entry that groups the constrained `rails` family gems together for coordinated updates:
```json
{
  "description": "Group the Rails framework gems so interdependent packages bump together",
  "matchPackageNames": ["rails", "railties", "actioncable", ...],
  "groupName": "Rails"
}
```
**Source:** `https://raw.githubusercontent.com/getlago/lago-api/main/renovate.json`, fetched verbatim via `curl`. Full file in auxiliary `renovate-mixed-constraint_data_1.json`, source block 1.

**Evidence — repository 2 (`catatsuy/private-isu`, a multi-language monorepo including a Ruby webapp):**
```json
{ "matchManagers": ["bundler"], "rangeStrategy": "update-lockfile" },
{ "matchManagers": ["composer"], "rangeStrategy": "update-lockfile" },
{ "matchManagers": ["npm"], "rangeStrategy": "bump" },
{ "matchManagers": ["pep621"], "rangeStrategy": "bump" }
```
**Source:** `https://raw.githubusercontent.com/catatsuy/private-isu/master/renovate.json`, fetched verbatim via `curl`. Full file in auxiliary `renovate-mixed-constraint_data_1.json`, source block 2.

**Evidence — repository 3 (`geeksforsocialchange/PlaceCal`, a Ruby/Rails community-calendar app):**
```json
"rangeStrategy": "pin",
...
"packageRules": [
  { "matchManagers": ["bundler"], "rangeStrategy": "update-lockfile" },
  ...
]
```
**Source:** `https://raw.githubusercontent.com/geeksforsocialchange/PlaceCal/main/renovate.json`, fetched verbatim via `curl`. Full file in auxiliary `renovate-mixed-constraint_data_1.json`, source block 3.

**Significance:** In all three real, currently-live configurations, the split that exists is by **manager/ecosystem** (bundler vs. composer vs. npm vs. pep621), never by whether an individual gem inside the Gemfile carries a version constraint. None of the three configs contains a `matchCurrentValue`, `matchCurrentVersion`, or any other packageRule attempting to treat the constrained minority differently from the unconstrained majority. `lago-api`'s one constraint-aware packageRule (`groupName: "Rails"`) groups the Rails family by NAME so their (constrained) updates land in one coordinated PR — it does not change their `rangeStrategy`, and it exists for PR-grouping convenience, not to work around any range-strategy limitation. This is direct evidence — not inference — that the practice observed among these three public Ruby/Rails projects is to apply `update-lockfile` uniformly to the bundler manager and let Renovate's per-dependency logic (documented in Finding 1: lockfile-only bump when in-range, `replace`-style constraint edit when out-of-range) handle both the constrained and unconstrained gems without any additional splitting configuration.

**Verification block:** URLs fetched: the three `raw.githubusercontent.com` URLs above, via `curl` (not the AI-summarizing WebFetch tool — direct byte-for-byte retrieval). Verbatim quotes checked against the retrieved JSON directly. Quote substrings confirmed present at the cited keys in each file.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Apply `rangeStrategy: update-lockfile` uniformly to the whole bundler manager (no packageRule split) — what all 3 examined real repos do | Zero extra config; matches documented per-dependency fallback design (Finding 1); is what the community visibly does (Finding 6) | Relies on the `replace`-fallback path for out-of-range constrained deps, which has at least one documented history of failing for Bundler (Finding 2) and whose current reliability for a fresh single-dependency case was not independently re-tested in this spike | Findings 1, 2, 6 |
| Group the constrained minority by name (`matchPackageNames` + `groupName`), keep `rangeStrategy: update-lockfile` unchanged | Coordinates interdependent constrained gems (e.g. the Rails family) into one reviewable PR; matches `lago-api`'s real pattern | Does not change or guarantee the range-crossing behavior itself — it is a PR-grouping convenience, not a fix for the fallback risk in Finding 2 | Finding 6 (source block 1) |
| Set `rangeStrategy: "replace"` explicitly for the constrained minority via a `matchPackageNames` packageRule, leave `update-lockfile` as the manager-wide default for everything else | `replace` is the strategy the maintainer confirmed worked reliably in the one documented failure case (Finding 2 — "the user confirmed the strategy works with `rangeStrategy=replace`") | Requires enumerating every currently-constrained gem by name and maintaining that list as constraints are added/removed; not observed in any of the 3 real repos examined | Finding 2 |
| Remove the constraints from the minority (follow `ruby.md`'s own suggestion pattern in reverse — i.e. treat the repo as "everything unconstrained") | Simplest mental model; matches the documented behavior that `update-lockfile` treats every listed gem uniformly regardless of constraint | Loses the intentional lower/upper bound the minority's constraints exist to express (e.g. `state_machines-graphviz '~> 0.0.2'` may be pinned for a real compatibility reason) — a scope decision outside this spike's evidence | `ruby.md` (Finding 1's source) |

## What remains uncertain

- Whether the `flipper`-style out-of-range failure reported in [discussion #16369](https://github.com/renovatebot/renovate/discussions/16369) / [issue #16547](https://github.com/renovatebot/renovate/issues/16547) is fully resolved by [PR #19058](https://github.com/renovatebot/renovate/pull/19058) for a **single, non-grouped** constrained dependency, or whether that PR only fixed the narrower grouped-dependency symptom. This spike did not find a follow-up test case or changelog entry confirming the single-dependency case specifically. Not found: a definitive current-state confirmation.
- Whether Renovate's current (2026) behavior for a constrained Bundler gem under `update-lockfile`, when the available upstream version is outside the declared range, reliably executes the documented `replace` fallback in practice today. The three real-world configs examined (Finding 6) do not by themselves prove the fallback works reliably — they show that maintainers of those repos chose not to special-case it, which is evidence about community *practice*, not about whether the underlying fallback mechanism is bug-free today. A live test against the actual repository in question (opening a Renovate run and observing whether `rails '~> 8.1.3'` gets proposed a `8.2.0`-class update) was outside this spike's scope (no write/execution access) and was not performed.
- Whether `matchCurrentVersion` with a range string (Finding 4, path 2) is a documented/recommended technique anywhere in Renovate's official docs for reaching unconstrained dependencies, versus being an incidental consequence of the fallback-chain implementation. Not found: any doc page describing this specific use.
- Findings 2 and 5 rest on AI-summarized fetches of GitHub's JS-rendered discussion/issue pages rather than raw text (GitHub discussions and issues have no `raw.githubusercontent.com`-equivalent endpoint that was accessible to this spike's tooling). Their general shape is corroborated by independent search results and by the issue/PR linkage, but the exact maintainer wording quoted should be treated as lower-confidence than Findings 1, 3, 4, and 6, which were verified against byte-identical raw source fetches.

## Suggested options for main and the engineer

- **Option A — do nothing extra; keep `rangeStrategy: "update-lockfile"` as the sole bundler-manager setting.** This matches Renovate's documented design (Finding 1) and is what all three examined real Ruby/Rails repositories do (Finding 6). The risk is Finding 2's documented history of the out-of-range fallback misbehaving for at least one real Bundler case — the residual exposure is untested for this specific repository's constrained gems (`rails`, `connection_pool`, `license_finder`, `state_machines-graphviz`).
- **Option B — add a `matchPackageNames` packageRule naming the small constrained set and set `rangeStrategy: "replace"` for just that set**, leaving `update-lockfile` as the default for everything else via the manager-level or `matchManagers: ["bundler"]` setting. This follows the one path the maintainer confirmed worked in the documented failure case (Finding 2), at the cost of maintaining an explicit list.
- **Option C — group the constrained gems by `groupName` (as `lago-api` does for the Rails family, Finding 6) without changing their `rangeStrategy`**, accepting Option A's underlying risk profile but gaining coordinated review PRs for interdependent constrained gems.
- **Option D — run a live test**: open a Renovate dependency-dashboard run (or a scoped one-off run) against this repository with the current `update-lockfile` configuration and observe directly whether `rails '~> 8.1.3'` is proposed an update outside that range. This would resolve the first open uncertainty above with a first-party fact rather than inference from other repositories' issue histories, but requires actually running Renovate against the repo — outside this spike's read-only research scope.

No option is recommended above another — the trade-offs table and the open uncertainties are the deciding inputs.
