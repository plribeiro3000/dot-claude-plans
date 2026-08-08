// Source: https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/pub/index.ts
// and https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/pub/artifacts.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/modules/manager/pub/{index,artifacts}.ts
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)

// ===== index.ts =====
export const supportsLockFileMaintenance = true;
export const lockFileNames = ['pubspec.lock'];
export const lockFileMaintenanceIsDelegatedToPackageManager = true;

// ===== artifacts.ts (relevant excerpt) =====
export async function updateArtifacts({
  packageFileName,
  updatedDeps,
  newPackageFileContent,
  config,
}: UpdateArtifact): Promise<UpdateArtifactsResult[] | null> {
  const { isLockFileMaintenance } = config;
  // ...
  try {
    await writeLocalFile(packageFileName, newPackageFileContent);

    const isFlutter = newPackageFileContent.includes('sdk: flutter');
    const toolName = isFlutter ? 'flutter' : 'dart';
    const cmd = getExecCommand(toolName, updatedDeps, isLockFileMaintenance);
    // ...
    await exec(cmd, execOptions);
    // ...
  }
  // ...
}

function getExecCommand(
  toolName: string,
  updatedDeps: Upgrade<Record<string, unknown>>[],
  isLockFileMaintenance: boolean | undefined,
): string {
  if (isLockFileMaintenance) {
    return `${toolName} pub upgrade`;
  }
  // ... per-dependency incremental commands (not relevant to this spike)
}

// NOTE: `dart pub upgrade` / `flutter pub upgrade` is the exact "update everything the
// lockfile resolves" equivalent (question 2 in the brief), and it is what lockFileMaintenance
// runs. No date-filtering flag or env var is constructed anywhere in this file.
