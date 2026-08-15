// Renovate source excerpt establishing that `rangeStrategy` scoped by
// `matchUpdateTypes` is a HARD CONFIGURATION VALIDATION ERROR in the current
// (2026-08-14) source, not merely discouraged in docs.
// Fetched verbatim via curl from
// raw.githubusercontent.com/renovatebot/renovate/main/lib/config/validation.ts

// It's too late to apply any of these options once you already have updates determined
const preLookupOptions = [
  'allowedVersions',
  'extractVersion',
  'followTag',
  'ignoreDeps',
  'ignoreUnstable',
  'rangeStrategy',
  'registryUrls',
  'respectLatest',
  'rollbackPrs',
  'separateMajorMinor',
  'separateMinorPatch',
  'separateMultipleMajor',
  'separateMultipleMinor',
  'versioning',
] as const;
if (isNonEmptyArray(resolvedRule.matchUpdateTypes)) {
  for (const option of preLookupOptions) {
    if (resolvedRule[option] !== undefined) {
      const message = `${currentPath}[${subIndex}]: packageRules cannot combine both matchUpdateTypes and ${option}. Rule: ${JSON.stringify(
        packageRule,
      )}`;
      errors.push({
        topic: 'Configuration Error',
        message,
      });
    }
  }
}

// Note: `errors.push` (not `warnings.push`) — this is a hard config-validation
// ERROR. A renovate.json combining `matchUpdateTypes` with `rangeStrategy` (or
// any of the other 13 preLookupOptions, including `allowedVersions`) in the
// SAME packageRule fails validation entirely; the docs page's "!!! warning"
// admonition box undersells the actual severity in code.

// =====================================================================
// Confirmed still present via GitHub code search, 2026-08-14:
//   gh api "search/code?q=repo:renovatebot/renovate+%22cannot combine both matchUpdateTypes%22"
// returned exactly 2 hits: lib/config/validation.ts (this file) and its
// matching lib/config/validation.spec.ts test file — both current, not
// historical/removed code.
// =====================================================================
