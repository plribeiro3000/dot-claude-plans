// Source: https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/bundler/index.ts
// and https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/bundler/artifacts.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/modules/manager/bundler/{index,artifacts}.ts
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)

// ===== index.ts =====
export const supportsLockFileMaintenance = true;
export const lockFileNames = ['Gemfile.lock'];
export const lockFileMaintenanceIsDelegatedToPackageManager = true;

// ===== artifacts.ts (relevant excerpt — the command construction) =====
export async function updateArtifacts(
  updateArtifact: UpdateArtifact,
  recursionLimit = 10,
): Promise<UpdateArtifactsResult[] | null> {
  // ...
  try {
    // ...
    const commands: string[] = [];

    if (config.isLockFileMaintenance) {
      commands.push('bundler lock --update');
    } else {
      // per-dependency incremental update commands (not relevant to this spike)
    }
    // ...
    await exec(commands, execOptions);
    // ...
  }
  // ...
}

// NOTE: no BUNDLE_COOLDOWN or any date-filtering value is set anywhere in this file.
// `bundler lock --update` is the exact equivalent of 4Shark's `bundle update --all` —
// it is what runs when Renovate's own lockFileMaintenance branch fires — and it runs
// with no cooldown protection from Renovate's side. This is the gap 4Shark's weekly
// GHA workflow (BUNDLE_COOLDOWN env var) fills for Ruby.
