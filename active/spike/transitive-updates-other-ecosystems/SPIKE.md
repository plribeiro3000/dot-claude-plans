# SPIKE — Extending the Weekly Transitive-Dependency Update Workflow Beyond Ruby/Bundler

## Investigation question

4Shark's weekly GitHub Actions workflow for Ruby (`bundle update --all` with `BUNDLE_COOLDOWN` set to the 7-day `DEPENDENCY_MINIMUM_RELEASE_AGE_DAYS` value) closes a gap in Renovate's transitive-dependency coverage for Bundler. Can the same pattern — or an equivalent — be extended to the other package ecosystems present in 4Shark's repositories: npm/Yarn, Dart/Flutter, Python/pip, Terraform, and .NET/NuGet?

For each ecosystem: (1) does the transitive gap actually exist the way it does for Bundler, (2) is there a native "update everything the lockfile resolves" command, (3) is there a minimum-release-age/cooldown mechanism that covers the whole resolve including transitive dependencies, (4) for Terraform specifically, does `.terraform.lock.hcl` cover module sources, and (5) for .NET specifically, what does enabling `packages.lock.json` change.

## Sources consulted

- [Renovate `minimumReleaseAge` docs](https://docs.renovatebot.com/key-concepts/minimum-release-age/) — the transitive-dependency exclusion statement and the npm-specific `--before` integration
- `~/.claude/docs/AUTOMATED-DEPENDENCY-UPDATES.md` and `app/.github/workflows/bundle-update.yaml` — the reference Ruby implementation
- Renovate source code (`renovatebot/renovate` on GitHub, fetched via `gh api` and base64-decoded — primary source, not summarized): `lib/workers/repository/process/lookup/filter-checks.ts`, `lib/modules/manager/{bundler,npm,nuget,pub,terraform}/index.ts` and their `artifacts.ts`/`lockfile/index.ts`, `lib/modules/manager/npm/post-update/{npm,yarn,pnpm}.ts` — see auxiliary files
- [HashiCorp — Dependency Lock File](https://developer.hashicorp.com/terraform/language/files/dependency-lock) — scope of `.terraform.lock.hcl`
- [HashiCorp — Module Sources](https://developer.hashicorp.com/terraform/language/modules/sources) — module version resolution behavior
- [Yarn — `npmMinimalAgeGate`](https://yarnpkg.com/configuration/yarnrc#npmMinimalAgeGate) — Yarn Berry's native cooldown
- [Microsoft Learn — NuGet PackageReference, "Locking dependencies"](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#locking-dependencies) — `RestorePackagesWithLockFile` / `packages.lock.json` mechanics
- [pip changelog / news](https://pip.pypa.io/en/stable/news/) — `--uploaded-prior-to` entry
- Local filesystem survey (`integrator`, `setup`, `app-webclient`, `data-privacy/email-erasure`, `google-analytics-manager/property-setup`, `simplex-harvester`, `app/.github/workflows/bundle-update.yaml`, `integrator/renovate.json`) — see auxiliary files for the Renovate source excerpts; the requirements.txt / yarn.lock content is quoted inline in Findings 5 and 2

## Findings

### Finding 1: Renovate does not manage transitive dependencies in ANY ecosystem — this is a universal design choice, not a Bundler-specific gap

**Evidence:** *"Renovate does not currently manage any transitive dependencies - instead leaving that to package managers and lockFileMaintenance."*

**Source:** [docs.renovatebot.com/key-concepts/minimum-release-age/](https://docs.renovatebot.com/key-concepts/minimum-release-age/)

**Significance:** The premise stated in the investigation background (a Renovate maintainer's "too noisy to update transitive dependencies individually") is confirmed at the documentation level, and confirmed to be general — Renovate's per-dependency PR-generation flow never opens an individual PR for a transitive dependency, in any ecosystem. The mechanism 4Shark relies on for coverage is `lockFileMaintenance`, Renovate's weekly (by default) job that regenerates a whole lock file in one PR. Whether that regeneration is itself cooldown-protected is a separate question, answered per-ecosystem in Findings 2–7 below.

### Finding 2: `lockFileMaintenance` support and its delegation shape differ per ecosystem — and this is the discriminator for whether a Bundler-style external cooldown workflow is even structurally possible

**Evidence (from Renovate's own source, `lib/modules/manager/*/index.ts`):**

| Ecosystem | `supportsLockFileMaintenance` | Lock file(s) | `lockFileMaintenanceIsDelegatedToPackageManager` |
|---|---|---|---|
| Bundler | `true` | `Gemfile.lock` | `true` |
| npm (covers npm/Yarn/pnpm lock files) | `true` | `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock` | `'Delegated to the underlying package manager CLI - npm, pnpm, or Yarn - depending on which lock file is present.'` |
| NuGet | `true` | `packages.lock.json` | `true` |
| pub (Dart/Flutter) | `true` | `pubspec.lock` | `true` |
| Terraform | `true` | `.terraform.lock.hcl` | `false` |
| pip_requirements | *(export absent — no `supportsLockFileMaintenance` at all)* | none | n/a |

**Source:** `~/Projects/4Shark/dot-claude-plans/active/spike/transitive-updates-other-ecosystems/transitive-updates_source_bundler_1.ts`, `..._npm_1.ts`, `..._nuget_1.ts`, `..._pub_1.ts`, `..._terraform_1.ts` (verbatim excerpts of `index.ts` for each manager, fetched via `gh api repos/renovatebot/renovate/contents/lib/modules/manager/<name>/index.ts` and base64-decoded — byte-for-byte GitHub content, retrieved 2026-08-07)

**Significance:** Five of six ecosystems present in 4Shark's repositories DO have a lockFileMaintenance mechanism structurally equivalent to Bundler's (a weekly job that runs the underlying package manager's own "regenerate the whole lock file" command). pip/`requirements.txt` is the one exception — it has no lock-file concept in Renovate at all, which changes the shape of the gap entirely (Finding 7). Terraform's `false` for delegation is also structurally different: Renovate does NOT shell out to a `terraform init -upgrade`-equivalent CLI call; it resolves provider versions using its own internal datasource-fetch code (Finding 6).

### Finding 3: Bundler, NuGet, and pub (Dart) all run their lockFileMaintenance-triggered "update everything" command with NO cooldown/age filter applied

**Evidence — Bundler** (`config.isLockFileMaintenance` branch of `updateArtifacts`):
```typescript
if (config.isLockFileMaintenance) {
  commands.push('bundler lock --update');
}
```
No `BUNDLE_COOLDOWN` or any date value is constructed anywhere in the file.

**Evidence — NuGet** (`runDotnetRestore`):
```typescript
const cmds = dependentPackageFileNames.map(
  (fileName) =>
    `dotnet restore ${quote(fileName)} --force-evaluate --configfile ${quote(nugetConfigFile)}`,
);
```
No date-filtering flag or env var appears anywhere in the file.

**Evidence — pub** (`getExecCommand`):
```typescript
if (isLockFileMaintenance) {
  return `${toolName} pub upgrade`;
}
```
No date-filtering flag or env var appears anywhere in the file.

**Source:** `transitive-updates_source_bundler_1.ts`, `transitive-updates_source_nuget_1.ts`, `transitive-updates_source_pub_1.ts` (all fetched from `renovatebot/renovate` on GitHub via `gh api`, base64-decoded, retrieved 2026-08-07)

**Significance:** The exact structural gap 4Shark closed for Bundler with a custom `BUNDLE_COOLDOWN`-wrapped workflow exists, unmodified, for NuGet (`dotnet restore --force-evaluate`) and Dart/Flutter (`dart pub upgrade` / `flutter pub upgrade`). These are also the answers to research question 2 for those two ecosystems — the native "update everything the lockfile resolves" commands are `dotnet restore --force-evaluate` and `<dart|flutter> pub upgrade` respectively.

### Finding 4: npm is the ONE ecosystem where Renovate itself applies a cooldown during lock file regeneration — but the mechanism is scoped to the `npm` CLI specifically, not to Yarn or pnpm, even though all three share the same Renovate manager

**Evidence — the npm `--before` construction** (unconditional on `config.minimumReleaseAge`, applied to every `npm install` command including the ones lockFileMaintenance issues after deleting the existing lock file):
```typescript
let beforeFlag = '';
if (config.minimumReleaseAge) {
  const ms = toMs(config.minimumReleaseAge);
  // ...
  const beforeISO = beforeDate.toISO();
  beforeFlag = ` --before=${beforeISO}`;
}
// ...
if (upgrades.find((upgrade) => upgrade.isLockFileMaintenance)) {
  await deleteLocalFile(lockFileName);
}
// commands.push(`npm install ${cmdOptions}${beforeFlag}`.trim());  (regenerates from scratch)
```

Also, from the general `minimumReleaseAge` doc: *"When minimumReleaseAge is configured, Renovate passes `--before=<date>` to npm commands during lock file generation."*

**Evidence — Yarn and pnpm carry NO such mechanism.** A keyword search (`before|cooldown|minimumReleaseAge|minimalAgeGate|npmRegistryServer`) across the decoded `lib/modules/manager/npm/post-update/yarn.ts` and `.../pnpm.ts` returned zero matches in either file.

**Source:** `transitive-updates_source_npm_1.ts` (npm/post-update/npm.ts excerpt) and `transitive-updates_source_yarn-pnpm_1.txt` (the negative-result grep evidence), both from `renovatebot/renovate`, fetched 2026-08-07; general doc quote from [docs.renovatebot.com/key-concepts/minimum-release-age/](https://docs.renovatebot.com/key-concepts/minimum-release-age/)

**Significance:** Answers research question 3 for the npm/Yarn family with a split result. For a `package-lock.json` project, Renovate's own lockFileMaintenance already regenerates the whole lock file (transitive dependencies included) bounded by `minimumReleaseAge` translated into `npm install --before=<date>` — a custom weekly GHA workflow of the Bundler shape would be redundant for npm specifically, PROVIDED `lockFileMaintenance` is turned on in `renovate.json` (it currently is not, in any 4Shark repository — see Finding 8). For a `yarn.lock` or `pnpm-lock.yaml` project the same code path runs `yarn install` / `pnpm install` with no cooldown flag at all — the gap is identical in shape to Bundler's.

### Finding 5: The 4Shark repos with `yarn.lock` use Yarn Classic (v1), which has no native cooldown mechanism; only Yarn Berry (4.10+) does

**Evidence — Yarn version per repo (local filesystem check):**
- `integrator/yarn.lock` and `setup/yarn.lock` both begin `# yarn lockfile v1` (Yarn Classic format marker) and neither repo has a `.yarnrc.yml` (the Berry config file)
- `app-webclient` has a `.yarnrc.yml`, indicating Yarn Berry

**Evidence — Yarn Berry's native cooldown**: *"Minimum age of a package version according to the publish date on the npm registry to be considered for installation. If a package version is newer than the minimal age gate, it will not be considered for installation."* Documented only in the Yarn Berry (2+) `.yarnrc.yml` configuration reference; the entry does not appear in the Yarn Classic (1.22.22) version of the same docs page.

**Source:** local files `~/Projects/4Shark/integrator/yarn.lock:1-2`, `~/Projects/4Shark/setup/yarn.lock:1-2`, presence check for `~/Projects/4Shark/app-webclient/.yarnrc.yml`; [yarnpkg.com/configuration/yarnrc#npmMinimalAgeGate](https://yarnpkg.com/configuration/yarnrc#npmMinimalAgeGate)

**Significance:** For `app-webclient` (Yarn Berry), a Bundler-style external workflow could in principle set `npmMinimalAgeGate` (in minutes, per a documented parsing bug around the `7d`-style duration suffix noted by the community — WebSearch summary, not independently verified against a primary source) alongside `yarn install` to reproduce the `BUNDLE_COOLDOWN` pattern. For `integrator` and `setup` (Yarn Classic v1), no native cooldown flag exists at all in the tool itself — the same absence Bundler has, but with no equivalent to `BUNDLE_COOLDOWN` to reach for, since Yarn Classic's own resolver has no age-filtering hook.

### Finding 6: `.terraform.lock.hcl` records ONLY provider versions — Terraform module versions, including nested/transitive module dependencies, are never locked at all

**Evidence:** *"At present, the dependency lock file tracks only provider dependencies. Terraform does not remember version selections for remote modules"* and *"Terraform will always select the newest available module version that meets the specified version constraints."*

**Source:** [developer.hashicorp.com/terraform/language/files/dependency-lock](https://developer.hashicorp.com/terraform/language/files/dependency-lock)

**Significance:** Directly answers research question 4's second half. There is no "stale lock" concern for Terraform modules because there is no lock — every `terraform init` (not only `-upgrade`) re-resolves every module reference, including nested ones, to the newest version satisfying its constraint string, with zero protection from Renovate's `minimumReleaseAge` UNLESS the version constraint itself was updated through a normal Renovate PR (which does apply age filtering to `terraform-module`/`terraform-provider` datasource candidates in the ordinary per-dependency PR flow, per the "Strong Support" table on the `minimumReleaseAge` doc page — this was not independently re-verified against a primary source beyond the earlier summarized fetch, so treat as lower confidence than the direct HashiCorp quote above).

On the provider side (what `.terraform.lock.hcl` DOES track): Renovate's `updateAllLocks` — the function that runs during `isLockFileMaintenance` — calls its own generic `getPkgReleases()` datasource primitive directly, with no date-based filtering of the returned release list:
```typescript
const { releases } = (await getPkgReleases(updateConfig)) ?? {};
// ...
const versionsList = releases.map((release) => release.version);
const newVersion = versioning.getSatisfyingVersion(versionsList, lock.constraints);
```
This bypasses `filterInternalChecks`/`isMinimumReleaseAgeApplicable` entirely (Finding 7 below) — that function is part of a separate, later step in the ordinary per-dependency PR-generation pipeline that `updateAllLocks` never calls.

**Source (provider-lock code):** `transitive-updates_source_terraform_1.ts` (`lib/modules/manager/terraform/lockfile/index.ts`, fetched from `renovatebot/renovate` via `gh api`, base64-decoded, retrieved 2026-08-07)

### Finding 7: The universal exclusion of `lockFileMaintenance` from `minimumReleaseAge` is explicit in Renovate's source, with the reason given in the code comment itself

**Evidence:**
```typescript
/** Given an UpdateType, should `minimumReleaseAge` apply to it? **/
export function isMinimumReleaseAgeApplicable(
  updateType: UpdateType | undefined,
): boolean {
  return (
    // ...
    // Not possible, as we delegate to the package manager to perform the required changes to update package(s).
    updateType !== 'lockFileMaintenance' &&
    // ...
  );
}
```

**Source:** `transitive-updates_source_filter-checks_1.ts` (`lib/workers/repository/process/lookup/filter-checks.ts`, fetched from `renovatebot/renovate` via `gh api`, base64-decoded, retrieved 2026-08-07)

**Significance:** This is the single function that governs whether `minimumReleaseAge` filtering applies to a given update, across every ecosystem. Its own comment states the reason for the `lockFileMaintenance` exclusion: once Renovate hands the update off to "the package manager" (the CLI tool itself), Renovate's own age-filtering logic has nothing left to filter — the CLI resolves the whole graph on its own terms. This is the root cause behind Findings 3, 4, and 6: whether a *given* package manager's CLI happens to offer its own cooldown flag (npm's `--before`, Yarn Berry's `npmMinimalAgeGate`) is what determines whether the resulting lockFileMaintenance PR is protected — Renovate's own filter never reaches this code path, in any ecosystem, unconditionally.

### Finding 8: No 4Shark repository currently has `lockFileMaintenance` enabled in its `renovate.json`

**Evidence:** `grep -rn "lockFileMaintenance" ~/Projects/4Shark/*/renovate.json` returned no matches across all 4Shark repositories checked.

**Source:** local filesystem, command run directly against `~/Projects/4Shark/*/renovate.json`

**Significance:** This bears on Finding 4's npm case specifically — Renovate's own `--before`-protected lockFileMaintenance path for `package-lock.json` is a real, already-built mechanism, but it does nothing today because the feature is off by default (`lockFileMaintenance` defaults to `false` per Renovate's own configuration-options documentation, not independently re-verified beyond the earlier summarized fetch) and no 4Shark `renovate.json` turns it on.

### Finding 9: pip/`requirements.txt` has a structurally different gap — not "lockFileMaintenance runs without a cooldown" but "there is no lock file and no cooldown integration at all"

**Evidence — no lock-file support in the manager itself:**
```typescript
export { updateArtifacts } from './artifacts.ts';
export { extractPackageFile } from './extract.ts';
// (no supportsLockFileMaintenance, no lockFileNames export)
export const supportedDatasources = [PypiDatasource.id, GitTagsDatasource.id];
```

**Evidence — the 4Shark files list only direct dependencies, pip-freeze-style enumeration of transitive packages is NOT present:**
- `data-privacy/email-erasure/requirements.txt`: 5 lines — `anthropic`, `google-api-python-client`, `google-auth`, `openpyxl`, `pypdf`, each pinned with `==`
- `google-analytics-manager/property-setup/requirements.txt`: 3 lines — `google-analytics-admin`, `google-auth`, `ruamel.yaml`, each pinned with `==`

Neither file lists the packages that `anthropic`, `google-api-python-client`, etc. themselves depend on (e.g., `httpx`, `pydantic`, `googleapis-common-protos` are not present).

**Evidence — pip's own native cooldown flag exists, separately from Renovate:** *"Add `--uploaded-prior-to` option to only consider packages uploaded prior to a given datetime when the `upload-time` field is available from a remote index."* Shipped in pip 26.0 (2026-01-30), with relative-duration support (`P3D`-style ISO 8601 durations) added in a later 26.1 release.

**Source:** `transitive-updates_source_pip is not a separate file — see the pip_requirements/index.ts excerpt confirming the absent export, quoted directly in Finding 2's table above; local files `~/Projects/4Shark/data-privacy/email-erasure/requirements.txt`, `~/Projects/4Shark/google-analytics-manager/property-setup/requirements.txt`; [pip.pypa.io/en/stable/news/](https://pip.pypa.io/en/stable/news/)

**Significance:** For pip specifically, no version of a Bundler-style workflow can reproduce "regenerate the whole lockfile with a cooldown" the way it works for the other five ecosystems, because there is no lockfile object for Renovate (or a custom job) to regenerate. `pip freeze > requirements.txt` would produce a file that DOES enumerate transitive dependencies explicitly and, once every line has an explicit `==` pin, Renovate's normal per-dependency PR flow (PyPI datasource, "Strong Support" for release timestamps per the summarized `minimumReleaseAge` doc fetch — lower-confidence citation, not independently re-verified) would then propose an individual PR per transitive package as it does for any other pinned direct dependency, WITH `minimumReleaseAge` filtering applied (since that only excludes the `lockFileMaintenance` update type, and a `pip freeze`-style file has no such update type). This is a structural option, not a finding about current behavior — the two 4Shark files surveyed are not `pip freeze` output today.

### Finding 10: NuGet's cooldown gap requires an explicit opt-in step (`RestorePackagesWithLockFile`) before it can even exist, and `simplex-harvester` has not taken that step

**Evidence — how the lock file is created:** *"In order to persist the full closure of package dependencies, you can opt-in to the lock file feature by setting the MSBuild property `RestorePackagesWithLockFile` for your project... If this property is set, NuGet restore will generate a lock file (`packages.lock.json`) at the project root directory that lists all the package dependencies."*

**Evidence — what the lock file covers:** *"Input to NuGet restore is a set of `PackageReference` items from the project file (top-level or direct dependencies) and the output is a full closure of all the package dependencies including transitive dependencies."*

**Evidence — the local state:** `find ~/Projects/4Shark/simplex-harvester -iname "*.csproj" -maxdepth 2` returns `SimplexHarvester.csproj` (confirming the repo is a .csproj-based project as stated in the investigation background) with no companion `packages.lock.json` found anywhere in the repository.

**Source:** [learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#locking-dependencies](https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#locking-dependencies); local filesystem check on `~/Projects/4Shark/simplex-harvester`

**Significance:** Directly answers research question 5. Enabling `RestorePackagesWithLockFile` would CREATE a transitive-update need that does not exist today, not merely expose one that is silently there — Finding 2's NuGet artifacts-code path (`hasLockFileContent` check returning `null` when no lock file exists) confirms that Renovate's `lockFileMaintenance` for NuGet is a complete no-op on `simplex-harvester` in its current state, because there is nothing for it to maintain. Adopting the lock file is the prerequisite before the Bundler-shaped gap (Finding 3: `dotnet restore --force-evaluate` runs with no cooldown) becomes a live concern at all.

## Trade-offs surfaced

| Ecosystem | Lockfile object exists today? | lockFileMaintenance no-op or live gap? | Native cooldown in the tool itself | Source |
|---|---|---|---|---|
| Bundler | Yes (`Gemfile.lock`, all 4 backend repos) | Live gap — closed by 4Shark's existing GHA workflow | No | Finding 3 |
| npm (`package-lock.json`) | N/A — not present in the surveyed 4Shark repos (they use `yarn.lock`) | — | Yes — Renovate's own `--before` integration | Finding 4 |
| Yarn Classic (`integrator`, `setup`) | Yes (`yarn.lock` v1) | Live gap if `lockFileMaintenance` is ever turned on | No | Finding 5 |
| Yarn Berry (`app-webclient`) | Yes (`yarn.lock` v2+ format, `.yarnrc.yml` present) | Live gap if `lockFileMaintenance` is ever turned on | Yes — `npmMinimalAgeGate` (4.10+) | Finding 5 |
| Dart/Flutter (`app-mobileclient`) | Yes (`pubspec.lock`) | Live gap if `lockFileMaintenance` is ever turned on | No (proposal only, `dart-lang/pub#4791`, unimplemented) | Finding 3 |
| pip (`data-privacy/email-erasure`, `google-analytics-manager/property-setup`) | No — plain `requirements.txt`, direct deps only | N/A — Renovate has no lock-file concept for this manager | Yes — `pip install --uploaded-prior-to` (pip 26.0+), but only reaches pip's OWN resolution, not Renovate's per-line PR flow | Finding 9 |
| Terraform (provider side) | Yes (`.terraform.lock.hcl`) | Live gap if `lockFileMaintenance` is ever turned on | No (feature request only, `hashicorp/terraform#38304`, unimplemented) | Findings 6, 7 |
| Terraform (module side) | No — no lock mechanism exists for modules at all | N/A | No | Finding 6 |
| NuGet (`rubocop-fourshark` N/A; `simplex-harvester`) | No — `RestorePackagesWithLockFile` not enabled | N/A until enabled; then a live gap identical to Bundler's | No (feature request only, `NuGet/Home#14657`, unimplemented) | Finding 10 |

## What remains uncertain

- Whether Renovate's `minimumReleaseAge` filtering genuinely applies to a normal (non-lockFileMaintenance) per-dependency PR for the `terraform-module`, `terraform-provider`, and `pypi` datasources was established only through an earlier AI-summarized fetch of the `minimumReleaseAge` docs page (the "Strong Support" table), not a direct quote independently re-verified against the raw page content. The `isMinimumReleaseAgeApplicable` source code (Finding 7) confirms the *exclusion* is scoped to specific `updateType` values including `lockFileMaintenance`, `bump`, and `lockfileUpdate` — but whether a plain `updateType: 'major'|'minor'|'patch'` PR for these three datasources actually carries a `releaseTimestamp` in practice (as opposed to merely being architecturally eligible) was not directly observed in a live Renovate run.
- Yarn Berry's `npmMinimalAgeGate` unit is documented as minutes, with a community-reported (not primary-source-confirmed in this spike) parsing bug around day-suffix durations like `7d`. Whether that bug is still present in the Yarn version 4Shark would actually pin was not checked.
- Whether Renovate's `config:recommended` preset (extended by `integrator/renovate.json`) or an account-level Renovate config sets `minimumReleaseAge` globally (the value referenced by `DEPENDENCY_MINIMUM_RELEASE_AGE_DAYS` in the GHA workflow) was not traced — `integrator/renovate.json` itself carries no top-level `minimumReleaseAge` key.
- What the actual value of `lockFileMaintenanceSchedule`'s default ("once weekly on Monday at 3am") is, and whether it was independently confirmed beyond an earlier AI-summarized fetch of the `configuration-options` docs page — the raw-markdown re-fetch of that specific section returned a truncated/unavailable result both times it was attempted.
- Whether `rubocop-fourshark` (the published gem also lacking the weekly Bundler workflow, per the investigation background) has any characteristic that would change its answer from the general Bundler finding — not separately investigated; Finding 3's Bundler conclusion is assumed to generalize to every Bundler-based repository, published gem or application, since the Renovate source code makes no distinction by repository type.
- The `lambda` repo's six separate `Gemfile.lock` files (also lacking the weekly workflow) were not individually investigated — the general Bundler finding (Finding 3) is assumed to apply uniformly per lock file, since Renovate's `updateArtifacts` operates per-`packageFileName`/per-lock-file, with no repo-wide or multi-lockfile-aware exception found in the source excerpts examined.

## Suggested options for main and the engineer

- **Option A — extend the exact Bundler pattern (external GHA workflow + native tool cooldown flag) per ecosystem, only where the tool has one**: Yarn Berry (`app-webclient`, via `npmMinimalAgeGate`) and pip (`data-privacy/email-erasure`, `google-analytics-manager/property-setup`, via `--uploaded-prior-to`, contingent on whether the resolution scope question in "What remains uncertain" is settled first). NuGet and Dart/Flutter and Terraform providers and Yarn Classic have no native flag to wrap, so this option does not apply to them as-is.
- **Option B — turn on Renovate's own `lockFileMaintenance` where it already carries a built-in cooldown**: npm's `package-lock.json` path (Finding 4) is the only ecosystem where this requires zero new custom tooling, if 4Shark had any `package-lock.json` repos (currently none surveyed use npm directly — all three npm-family repos use `yarn.lock`).
- **Option C — turn on `lockFileMaintenance` for the ecosystems where it exists but runs without a cooldown (Yarn Classic, Dart/Flutter, Terraform providers, NuGet-once-adopted)**, accepting the same unprotected-regeneration risk 4Shark's Bundler workflow was built specifically to avoid — i.e., not closing the gap, only formalizing that it is open.
- **Option D — build a Bundler-shaped external workflow even where the underlying tool has no native cooldown**, by having the workflow itself post-filter or pre-check candidate versions against a date threshold before letting the package manager resolve (a more involved build than wrapping an existing flag) — applicable in principle to Yarn Classic, Dart/Flutter, Terraform providers, and NuGet, but not investigated further in this spike.
- **Option E — for pip specifically, first convert `requirements.txt` to a `pip freeze`-style fully-pinned file** (making every transitive dependency a direct, Renovate-visible line), which brings pip's transitive coverage in line with the other ecosystems' normal per-dependency PR flow rather than needing a lockFileMaintenance-shaped mechanism at all — a structurally different fix than a weekly external job.
- **Option F — for NuGet specifically, adopt `RestorePackagesWithLockFile` first** (Finding 10) as a prerequisite decision, independent of and prior to any cooldown-workflow decision, since no gap exists to close until the lock file itself exists.
- **Option G — for Terraform module sources specifically, no lockFileMaintenance-shaped fix applies at all** (Finding 6) since there is no lock file for modules; any protection would have to come from Renovate's own per-dependency `minimumReleaseAge` filtering on the module version constraint string, which is a different mechanism than everything else in this spike.

No recommendation is made among these options — they are presented as the surfaced choices for the engineer to weigh against the "What remains uncertain" list above.
