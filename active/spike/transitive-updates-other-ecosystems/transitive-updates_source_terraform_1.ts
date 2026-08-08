// Source: https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/terraform/index.ts
// and https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/terraform/lockfile/index.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/modules/manager/terraform/{index,lockfile/index}.ts
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)

// ===== index.ts =====
export const supportsLockFileMaintenance = true;
export const lockFileNames = ['.terraform.lock.hcl'];
export const lockFileMaintenanceIsDelegatedToPackageManager = false;
// (note the FALSE here — unlike bundler/npm/nuget/pub, Terraform does NOT shell out to
// `terraform init -upgrade`; Renovate resolves and rewrites the lock file itself.)

// ===== lockfile/index.ts (relevant excerpt) =====
async function updateAllLocks(
  locks: ProviderLock[],
): Promise<ProviderLockUpdate[]> {
  const updates = await p.map(
    locks,
    async (lock) => {
      const updateConfig: GetPkgReleasesConfig = {
        datasource: 'terraform-provider',
        packageName: lock.packageName,
        registryUrls: [lock.registryUrl],
      };
      const { releases } = (await getPkgReleases(updateConfig)) ?? {};
      if (!releases) {
        return null;
      }
      const versioning = getVersioning(
        getDefaultVersioning('terraform-provider'),
      );
      const versionsList = releases.map((release) => release.version);
      const newVersion = versioning.getSatisfyingVersion(
        versionsList,
        lock.constraints,
      );
      // no date/age filtering of `releases` or `versionsList` anywhere in this function
      // ...
      return update;
    },
    { concurrency: 4 },
  );
  return updates.filter(isTruthy);
}

export async function updateArtifacts({
  packageFileName,
  updatedDeps,
  config,
}: UpdateArtifact): Promise<UpdateArtifactsResult[] | null> {
  // ...
  const updates: ProviderLockUpdate[] = [];
  if (config.isLockFileMaintenance) {
    // update all locks in the file during maintenance --> only update version in constraints
    const maintenanceUpdates = await updateAllLocks(locks);
    updates.push(...maintenanceUpdates);
  } else {
    // per-dependency incremental update path (not relevant to this spike)
  }
  // ...
}

// NOTE: `getPkgReleases()` is Renovate's generic datasource-fetch primitive — the same
// one used everywhere else in the codebase — but calling it here does NOT route through
// `filterInternalChecks`/`isMinimumReleaseAgeApplicable` (see
// transitive-updates_source_filter-checks_1.ts), which is a separate, later step in the
// normal per-dependency PR-generation lookup pipeline that lockFileMaintenance's
// updateAllLocks() bypasses entirely. getPkgReleases() itself performs no age filtering;
// age filtering is applied by the caller, and this caller does not apply it.
