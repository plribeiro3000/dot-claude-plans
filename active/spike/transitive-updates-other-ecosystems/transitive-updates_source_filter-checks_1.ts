// Source: https://github.com/renovatebot/renovate/blob/main/lib/workers/repository/process/lookup/filter-checks.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/workers/repository/process/lookup/filter-checks.ts
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)
//
// This is the function that decides whether minimumReleaseAge applies to a given
// update. Lines 27-45 are the load-bearing evidence for this spike: lockFileMaintenance
// is explicitly excluded from minimumReleaseAge filtering, with the reason given in
// the code comment itself.

/** Given an UpdateType, should `minimumReleaseAge` apply to it? **/
export function isMinimumReleaseAgeApplicable(
  updateType: UpdateType | undefined,
): boolean {
  return (
    // Possible, but not wanted, as this is intentionally rolling back to a previous (generally older) release to unblock the build
    updateType !== 'rollback' &&
    // Not yet supported: TODO #40288
    updateType !== 'pin' &&
    // Not yet supported: TODO #39400
    updateType !== 'replacement' &&
    // Not possible, as we delegate to the package manager to perform the required changes to update package(s).
    updateType !== 'lockFileMaintenance' &&
    // Not supported
    updateType !== 'bump' &&
    // Not supported
    updateType !== 'lockfileUpdate'
  );
}
