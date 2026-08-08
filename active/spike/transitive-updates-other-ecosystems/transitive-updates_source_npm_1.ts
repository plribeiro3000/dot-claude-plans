// Source: https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/npm/index.ts
// and https://github.com/renovatebot/renovate/blob/main/lib/modules/manager/npm/post-update/npm.ts
// Fetched via: gh api repos/renovatebot/renovate/contents/lib/modules/manager/npm/{index.ts,post-update/npm.ts}
// Retrieved: 2026-08-07 (base64-decoded, byte-for-byte GitHub content)

// ===== index.ts =====
export const supportsLockFileMaintenance = true;
export const lockFileNames = [
  'package-lock.json',
  'pnpm-lock.yaml',
  'yarn.lock',
];
export const lockFileMaintenanceIsDelegatedToPackageManager =
  'Delegated to the underlying package manager CLI - `npm`, `pnpm`, or Yarn - depending on which lock file is present.';

// ===== post-update/npm.ts (relevant excerpt — the ONLY manager with a cooldown flag) =====
// This code runs for BOTH regular lockfile updates and lockFileMaintenance (isLockFileMaintenance
// only changes whether the existing lock file is deleted first, at line ~289 below — the --before
// flag itself is computed unconditionally from config.minimumReleaseAge and applied to every
// `npm install` command, including the ones lockFileMaintenance issues).

let beforeFlag = '';
if (config.minimumReleaseAge) {
  const ms = toMs(config.minimumReleaseAge);
  if (ms === null) {
    // invalid config, skip
  } else {
    const npmrcCooldown = parseNpmrcCooldownDate(npmrcContent);

    // npm rejects --before when min-release-age is set in .npmrc,
    // so let the .npmrc handle cooldown natively in that case
    if (npmrcCooldown?.source === 'min-release-age') {
      // skip --before, .npmrc already enforces it
    } else {
      let beforeDate = DateTime.now().minus(ms).toUTC();

      if (npmrcCooldown && npmrcCooldown.date < beforeDate) {
        beforeDate = npmrcCooldown.date;
      }

      const beforeISO = beforeDate.toISO();
      beforeFlag = ` --before=${beforeISO}`;
    }
  }
}

// ...
if (!upgrades.every((upgrade) => upgrade.isLockfileUpdate)) {
  commands.push(`npm install ${cmdOptions}${beforeFlag}`.trim());
}
// ...

if (upgrades.find((upgrade) => upgrade.isLockFileMaintenance)) {
  // Removes the existing lock file first, then the `npm install` commands above
  // (which already carry beforeFlag) regenerate it from scratch — a full re-resolve
  // of the whole dependency tree, transitive included, bounded by --before.
  await deleteLocalFile(lockFileName);
}

// Run the commands, retrying without --before on ETARGET if needed
await exec(commands, execOptions).catch(async (err) => {
  if (beforeFlag && err.stderr?.includes('with a date before')) {
    // retries without --before if the existing lock file has newer packages than the cutoff
    const commandsWithoutBefore = commands.map((cmd) =>
      cmd.replace(beforeFlag, ''),
    );
    return exec(commandsWithoutBefore, execOptions);
  }
  throw err;
});

// ===== NpmrcCooldownResult type (top of file) =====
export interface NpmrcCooldownResult {
  date: DateTime<true>;
  source: 'before' | 'min-release-age';
}
