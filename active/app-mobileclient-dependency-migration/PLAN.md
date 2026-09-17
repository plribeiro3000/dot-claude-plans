# PLAN — app-mobileclient Dependency Migration

Migrate the fragile / outdated dependency stack of `app-mobileclient` to current,
maintained versions, one dependency per pull request merged one at a time (the 4Shark
sequencing rule), to unblock the Flutter 3.32.0 → 3.47.x upgrade — which is what enables
an iOS build under Xcode 27 (the `lipo -verify_arch` change in flutter/flutter#188461 and
the iOS 27 UIScene mandate both require Flutter ≥ 3.47).

- **Repository**: `~/Projects/4Shark/app-mobileclient`
- **Flutter**: 3.32.0 → **3.47.4** (Dart 3.13.3) — done
- **Grounding**: `flutter pub outdated` on 3.32.0 (the `Resolvable` column = what can move
  without the Flutter bump; `Latest` = needs the newer SDK)

**Goal achieved.** iOS builds under Xcode 27: `flutter build ios --simulator` produces
`Runner.app` on Flutter 3.47.4. The sibling quality review
(`../app-mobileclient-quality-review/ANALYSIS.md`) carries the architecture work, which is
out of scope here.

## Why two phases

`flutter pub outdated` splits the work cleanly. Anything whose **Resolvable** version was
newer than **Current** moved on Flutter 3.32.0 in its own PR, keeping the app building
(Phase 1). The build-codegen stack moved **with** the Flutter bump (Phase 2), because it is
what breaks `pub get` on 3.47.4 — and the shape of that break was not what the plan first
assumed:

- `flutter_gen_runner` was unused (no `Assets.` / `.gen.dart` reference in `lib/`) and its
  `build ^4.0.0` constraint conflicted on Dart 3.47 — **dropped**, not upgraded.
- The direct `dart_style: ">=2.3.7 <3.0.0"` pin forced 2.3.x, which pulls `_macros` from the
  SDK (removed on newer Dart) — the **pin was dropped**, letting `dart_style` 3.x resolve.
- The real hard blocker was **`hive_generator`**: frozen at 2.0.1, it pins `analyzer <7.0.0`,
  which the Dart 3.47 analyzer (8–14, required by `graphql_flutter` / `bloc_test` /
  `flutter_test`) rejects. `hive` itself is discontinued. This forced a migration to the
  maintained successor `hive_ce`, as its own PR before the Flutter bump.

Renovate (self-hosted, configured in this repo) opens the safe minor/patch PRs on its own;
this manual effort targeted only the breaking / fragile migrations Renovate will not
auto-apply.

## Phase 1 — resolvable on Flutter 3.32.0 (one PR each) — ✅ complete

13 PRs (**#19–#31**), all merged, each verified green (`flutter analyze --no-fatal-infos` at
the 147-info baseline + `flutter test` + an Android build). Ordered safest-first, the two
large code migrations last:

- Removed the dead third-party `flutter_localization` (the app uses the SDK
  `flutter_localizations` + gen-l10n).
- Moved `flutter_launcher_icons` to `dev_dependencies` (build-time tool).
- Removed `provider` (redundant — `flutter_bloc` re-exports it).
- `flutter_lints` 4.0.0 → 6.0.0 (dev-only).
- `flutter_udid` major upgrade (device-id API verified at the call site).
- Android build toolchain (foundational): Gradle 8.13, AGP 8.12.1, Kotlin 2.2.0 — the
  prerequisite for the plugin majors below and for the Phase 2 Flutter bump.
- `connectivity_plus` 6 → 7 (Dart API unchanged; the breaking part was the Android toolchain).
- `another_flushbar` 1 → 2.
- `skeletonizer` 2 → 3.
- `go_router` 16 → 17 (verified against the router config + navigation guard test).
- `flutter_appauth` 9 → 11 (**#29**) — SSO.
- `graphql_flutter` 5.2.0-beta.8 → 5.3.0 stable (**#30**) — ~35 query sites (DEP-2).
- `qr_code_scanner` → `mobile_scanner` (**#31**) — QR screen code migration; `qr_code_scanner`
  is discontinued (DEP-1).

## Phase 1.5 — the hive blocker — ✅ complete

**#32** — migrated the discontinued `hive` / `hive_flutter` / `hive_generator` stack to the
maintained `hive_ce` / `hive_ce_flutter` / `hive_ce_generator`. Compatible on-disk format and
the same `@HiveType` codegen model; adapter registration adopts the generated
`hive_registrar.g.dart` (`Hive.registerAdapters()`). Verified on Flutter 3.32.0 (analyze,
test, Android APK). This is the prerequisite that unblocks Phase 2 — the frozen
`hive_generator`'s `analyzer <7.0.0` pin was the last thing failing `pub get` on 3.47.

## Phase 2 — the Flutter bump + iOS enablement — ✅ complete

**#33 — Flutter 3.32.0 → 3.47.4.** Gradle 8.13 → 8.14 and Kotlin 2.2.0 → 2.2.20 (the 3.47
minimums; AGP stays 8.12.1); dropped `flutter_gen_runner` and the `dart_style` pin (the
`_macros` cascade). Verified: analyze at the 146-info 3.47 baseline, tests, Android APK.
**The minimum Android version rose API 23 → 24** — Flutter 3.47 dropped Android 6.0 support,
and its build migrator forces any minSdk below the framework floor upward; there is no path to
3.47 that keeps API 23.

**#34 — iOS build under Xcode 27.** The Flutter 3.32 → 3.47 upgrade cleared the actual blocker
(the Xcode 27 `lipo -verify_arch` change, flutter/flutter#188461). Flutter 3.47's tooling
auto-migrated the app to the **UIScene** lifecycle (iOS 27 SDK mandate) — plugin registration
moves to the implicit-engine delegate. The migration also brings Swift Package Manager
alongside CocoaPods (Flutter 3.47's default; the `printing` plugin stays on CocoaPods, a hybrid
that builds but which Flutter warns will error in a future version). Verified:
`flutter build ios --simulator` produces `Runner.app` under Xcode 27.0.

## Status — ✅ complete

- Android local dev environment: functional (emulator `Pixel_API_36`, API 36 arm64).
- iOS under Xcode 27: **the app builds, installs and runs on an iOS 27 simulator** and is
  navigable — the app reaches its account-linking entry screen (`Scan QR Code` / `Link code`).
  The whole chain is proven end to end: modernized dependencies → Flutter 3.47.4 → iOS build →
  app running on the simulator.
- Architecture remediation (layering, state, routing, tests) is tracked separately in
  `../app-mobileclient-quality-review/ANALYSIS.md`.

### Local iOS run — machine setup a reader will need

Two environment facts about this machine, independent of the app, that a first local iOS run
must reconcile:

- **CocoaPods is a Homebrew install (`/opt/homebrew/bin/pod`) while the interactive shell runs
  the RVM `ruby-4.0.6`.** With RVM active, its gem environment leaks into the Homebrew `pod` and
  breaks it ("CocoaPods installed but broken"). Fix: `gem install cocoapods` under the active RVM
  ruby, so `pod` resolves to the RVM copy and matches the ruby invoking it.
- **This Xcode 27 install has no `Simulator.app`** (the GUI window app is absent from the bundle;
  `open -a Simulator` fails and the `com.apple.iphonesimulator` bundle id is unregistered). The
  iOS runtime and `simctl` still work: boot a device headless with
  `xcrun simctl boot <udid>`, then `fvm flutter run -d <udid>` installs and runs the app on it.
  The device does not stay booted on its own between commands, so boot and run as one motion. The
  simulator can be viewed and driven through the Claude desktop app's iOS simulator panel without
  the native `Simulator.app`.
