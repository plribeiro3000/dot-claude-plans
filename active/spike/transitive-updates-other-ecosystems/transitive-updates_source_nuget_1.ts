// Source: https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/nuget/index.ts
// and https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/nuget/artifacts.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/modules/manager/nuget/{index,artifacts}.ts
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)

// ===== index.ts =====
export const supportsLockFileMaintenance = true;
export const lockFileNames = ['packages.lock.json'];
export const lockFileMaintenanceIsDelegatedToPackageManager = true;

// ===== artifacts.ts (relevant excerpt) =====
export async function updateArtifacts({
  packageFileName,
  newPackageFileContent,
  config,
  updatedDeps,
}: UpdateArtifact): Promise<UpdateArtifactsResult[] | null> {
  // ...
  const lockFileNames = deps.map((f) =>
    getSiblingFileName(f.name, 'packages.lock.json'),
  );

  const existingLockFileContentMap = await getFiles(lockFileNames);

  const hasLockFileContent = Object.values(existingLockFileContentMap).some(
    (val) => !!val,
  );
  if (!hasLockFileContent) {
    // No lock file found for package or dependents — returns null, lockFileMaintenance
    // silently does nothing for a project that has never opted into packages.lock.json.
    return null;
  }

  try {
    if (updatedDeps.length === 0 && config.isLockFileMaintenance !== true) {
      return null;
    }

    await writeLocalFile(packageFileName, newPackageFileContent);
    await runDotnetRestore(packageFileName, packageFiles, config, updatedDeps);
    // ...
  }
  // ...
}

// runDotnetRestore (relevant excerpt — the command that actually regenerates the lock file)
async function runDotnetRestore(
  packageFileName: string,
  dependentPackageFileNames: string[],
  config: UpdateArtifactsConfig,
  updatedDeps: Upgrade[],
): Promise<void> {
  // ...
  const cmds = dependentPackageFileNames.map(
    (fileName) =>
      `dotnet restore ${quote(fileName)} --force-evaluate --configfile ${quote(nugetConfigFile)}`,
  );
  // ...
  await exec(cmds, execOptions);
}

// NOTE: no date-filtering flag or env var is constructed anywhere in this file.
// `dotnet restore --force-evaluate` re-resolves the whole graph (direct + transitive)
// against whatever is currently on the feed, with no cooldown from Renovate's side.
