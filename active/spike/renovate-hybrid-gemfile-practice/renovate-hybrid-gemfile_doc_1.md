# Renovate configuration-options.md — excerpts relevant to this spike

Fetched verbatim via curl from
raw.githubusercontent.com/renovatebot/renovate/main/docs/usage/configuration-options.md, 2026-08-14.

## `rangeStrategy` (full allowedValues list, including `in-range-only` —
## not present in the prior spike's fetch)

- `auto` = Renovate decides how to update
- `pin` = convert ranges to exact versions, e.g. `^1.0.0` → `1.1.0`
- `bump` = e.g. bump the range even if the new version satisfies the existing range, e.g. `^1.0.0` → `^1.1.0`
- `replace` = Replace the range with a newer one if the new version falls outside it, and update nothing otherwise
- `widen` = Widen the range with newer one, e.g. `^1.0.0` → `^1.0.0 || ^2.0.0`
- `update-lockfile` = Update the lock file when in-range updates are available, otherwise `replace` for updates out of range. Works for `bundler`, `cargo`, `composer`, `gleam`, `npm`, `yarn`, `pnpm`, `terraform`, `poetry` and `uv` so far
- `in-range-only` = Update the lock file when in-range updates are available, ignore package file updates

> The `in-range-only` strategy may be useful if you want to leave the package file unchanged and only do `update-lockfile` within the existing range.
> The `in-range-only` strategy behaves like `update-lockfile`, but discards any updates where the new version of the dependency is not equal to the current version.
> We recommend you avoid using the `in-range-only` strategy unless you strictly need it.
> Using the `in-range-only` strategy may result in you being multiple releases behind without knowing it.

## `packageRules.matchUpdateTypes`

> Use `matchUpdateTypes` to match rules against types of updates.

> !!! warning
>   `matchUpdateTypes` and `allowedVersions` cannot be used in the same package rule.

(Note: the doc page presents this as a "warning" admonition box; the actual source code in
`lib/config/validation.ts` treats it as a hard `errors.push` config-validation failure, not a
soft warning — see `renovate-hybrid-gemfile_excerpt_2.ts`. The doc's own admonition box also
does not mention `rangeStrategy` specifically even though `rangeStrategy` is in the same
`preLookupOptions` exclusion list as `allowedVersions` in the actual source.)

## `packageRules.matchCurrentValue`

> This option is matched against the `currentValue` field of a dependency.
>
> `matchCurrentValue` supports Regular Expressions and glob patterns. For example, the following enforces that updates from `1.*` versions will be merged automatically:
>
> ```json
> {
>   "packageRules": [
>     {
>       "matchPackageNames": ["io.github.resilience4j**"],
>       "matchCurrentValue": "1.*",
>       "automerge": true
>     }
>   ]
> }
> ```
>
> This field also supports a special negated regex syntax to ignore certain versions.
> Use the syntax `!/ /` like this:
>
> ```json
> {
>   "packageRules": [
>     {
>       "matchCurrentValue": "!/^0\\./"
>     }
>   ]
> }
> ```

## `packageRules.allowedVersions`

> You can use `allowedVersions` - usually within a `packageRules` entry - to limit how far to upgrade a dependency.
>
> For example, if you want to upgrade to Angular v1.5 but _not_ to `angular` v1.6 or higher, you could set `allowedVersions` to `<= 1.5` or `< 1.6.0`:
>
> ```json
> {
>   "packageRules": [
>     {
>       "matchPackageNames": ["angular"],
>       "allowedVersions": "<=1.5"
>     }
>   ]
> }
> ```
>
> !!! warning
>   `allowedVersions` and `matchUpdateTypes` cannot be used in the same package rule.
>
> #### Using regular expressions
>
> You can use Regular Expressions in the `allowedVersions` config.
> You must _begin_ and _end_ your Regular Expression with the `/` character!
