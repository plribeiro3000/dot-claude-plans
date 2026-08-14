<!-- Raw source capture. Downloaded via curl from raw.githubusercontent.com, exact line ranges extracted with Read for citation accuracy. -->
<!-- Source: https://raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/configuration-options.md -->
<!-- Fetched: 2026-08-14 -->

## Section: packageRules.matchCurrentValue and packageRules.matchCurrentVersion
## (lines 3367-3439 of configuration-options.md)

### `packageRules.matchCurrentValue`

This option is matched against the `currentValue` field of a dependency.

`matchCurrentValue` supports Regular Expressions and glob patterns. For example, the following enforces that updates from `1.*` versions will be merged automatically:

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["io.github.resilience4j**"],
      "matchCurrentValue": "1.*",
      "automerge": true
    }
  ]
}
```

Regular Expressions must begin and end with `/`.

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["io.github.resilience4j**"],
      "matchCurrentValue": "/^1\\./"
    }
  ]
}
```

This field also supports a special negated regex syntax to ignore certain versions.
Use the syntax `!/ /` like this:

```json
{
  "packageRules": [
    {
      "matchPackageNames": ["io.github.resilience4j**"],
      "matchCurrentValue": "!/^0\\./"
    }
  ]
}
```

### `packageRules.matchCurrentVersion`

The `currentVersion` field will be one of the following (in order of preference):

- locked version if a lock file exists
- resolved version
- current value

Consider using instead `matchCurrentValue` if you wish to match against the raw string value of a dependency.

`matchCurrentVersion` can be an exact version or a version range:

```json
{
  "packageRules": [
    {
      "matchCurrentVersion": ">=1.0.0",
      "matchPackageNames": ["angular"]
    }
  ]
}
```

The syntax of the version range must follow the [versioning scheme](modules/versioning/index.md#supported-versioning) used by the matched package(s).
This is usually defined by the [manager](modules/manager/index.md#supported-managers) which discovered them or by the default versioning for the package's [datasource](modules/datasource/index.md).
For example, a Gradle package would typically need Gradle constraint syntax (e.g. `[,7.0)`) and not SemVer syntax (e.g. `<7.0`).

This field also supports Regular Expressions which must begin and end with `/`.

## Section: rangeStrategy
## (lines 4519-4549 of configuration-options.md)

## `rangeStrategy`

Behavior:

- `auto` = Renovate decides (this will be done on a manager-by-manager basis)
- `pin` = convert ranges to exact versions, e.g. `^1.0.0` → `1.1.0`
- `bump` = e.g. bump the range even if the new version satisfies the existing range, e.g. `^1.0.0` → `^1.1.0`
- `replace` = Replace the range with a newer one if the new version falls outside it, and update nothing otherwise
- `widen` = Widen the range with newer one, e.g. `^1.0.0` → `^1.0.0 || ^2.0.0`
- `update-lockfile` = Update the lock file when in-range updates are available, otherwise `replace` for updates out of range. Works for `bundler`, `cargo`, `composer`, `gleam`, `npm`, `yarn`, `pnpm`, `terraform`, `poetry` and `uv` so far
- `in-range-only` = Update the lock file when in-range updates are available, ignore package file updates

Renovate's `"auto"` strategy works like this for npm:

1. Widen `peerDependencies`
1. If an existing range already ends with an "or" operator like `"^1.0.0 || ^2.0.0"`, then Renovate widens it into `"^1.0.0 || ^2.0.0 || ^3.0.0"`
1. Otherwise, if the update is outside the existing range, Renovate replaces the range. So `"^2.0.0"` is replaced by `"^3.0.0"`
1. Finally, if the update is in-range, Renovate will update the lockfile with the new exact version.

By default, Renovate assumes that if you are using ranges then it's because you want them to be wide/open.
Renovate won't deliberately "narrow" any range by increasing the semver value inside.

For example, if your `package.json` specifies a value for `left-pad` of `^1.0.0` and the latest version on npmjs is `1.2.0`, then Renovate won't change anything because `1.2.0` satisfies the range.
If instead you'd prefer to be updated to `^1.2.0` in cases like this, then configure `rangeStrategy` to `bump` in your Renovate config.

This feature supports caret (`^`) and tilde (`~`) ranges only, like `^1.0.0` and `~1.0.0`.

The `in-range-only` strategy may be useful if you want to leave the package file unchanged and only do `update-lockfile` within the existing range.
The `in-range-only` strategy behaves like `update-lockfile`, but discards any updates where the new version of the dependency is not equal to the current version.
We recommend you avoid using the `in-range-only` strategy unless you strictly need it.
Using the `in-range-only` strategy may result in you being multiple releases behind without knowing it.
