# SPIKE — Test suite for app-mobileclient (Flutter)

Reduce uncertainty on how to add a real test suite to `app-mobileclient`, which today
has none (only the default `test/widget_test.dart` counter boilerplate). The immediate
driver is confidence to change navigation (NAV-1, the nested `MaterialApp`): a compile
does not prove the app still navigates, so a test that exercises the flows is what makes
that change safe.

- **Repository**: `~/Projects/4Shark/app-mobileclient` · Flutter 3.32.0
- **Date**: 2026-09-16
- **Status**: research complete; awaiting one decision (backend strategy) before implementation

---

## 1. The three Flutter test types

Flutter has exactly three kinds, and the difference that matters here is **where each runs**.

- **Unit test** — verifies one method or class of pure Dart logic. No Flutter runtime, no
  widget tree. Runs on the host machine (the Mac), milliseconds each.
- **Widget test** — renders one widget or screen in a test harness and verifies rendering
  and interaction, without launching the full app. Also runs on the host, fast. This is the
  layer that catches loading/error/success path bugs.
- **Integration test** — runs the **full app** on a real device or emulator (Android
  Emulator / iOS Simulator), end-to-end. The test script runs on the computer; the app runs
  on the device. Slow, but the only layer that proves real navigation and platform behavior.

The recommended distribution is the test pyramid: roughly **80% unit + widget, ~15%
integration, ~5% E2E**.

## 2. One suite or one-per-platform? (the direct question)

**Unit and widget tests are platform-agnostic** — they run on the host Dart VM, no Android
or iOS device involved. So they are **one general suite**, never duplicated per platform.
That is 80–95% of the tests.

**Integration tests run on a device**, so they execute per platform — but the **test code is
shared**. You write the flow once and run the same suite on an Android emulator and again on
an iOS simulator; you do not write separate Android and iOS tests. So the answer is: general
(host) for unit + widget, and the *same* integration suite executed against both an Android
emulator and an iOS simulator.

## 3. Recommended tooling (grounded in current community practice)

- **`flutter_test`** (built-in) — unit and widget tests. Already present.
- **`bloc_test`** — a DSL purpose-built for testing Cubits/Blocs; the app has ~25 of them, so
  this pays off immediately.
- **`mocktail`** — null-safe mocking with **no code generation**; the 2026 community default
  over `mockito` (which needs build_runner). Cleaner for this repo.
- **`integration_test`** (official Flutter package) — end-to-end flows on device; replaced the
  old `flutter_driver`.
- **`flutter test --coverage`** + lcov — coverage reporting.
- **Optional, later**: `patrol` — builds on `integration_test` and can drive **native** UI
  (permission dialogs, the camera used for the QR scanner, biometrics). The app has a camera
  permission and a tracking prompt, so patrol becomes relevant for true end-to-end; start
  without it and add it only when a flow needs a native dialog. `alchemist` for golden
  (pixel) tests is a later maturity step, not day one.

## 4. Reality check — this repo's architecture fights testing

This is the honest constraint, not a detail. The current code resists unit testing:

- Cubits take `BuildContext` and perform navigation (`BlocDashInit.fetchUser(context)` calls
  `Navigator.pushAndRemoveUntil`) — business logic welded to the UI (ANALYSIS finding ARCH-2).
- Business logic lives inside 900–2,200-line widget `build` methods (CQ-1).
- There are no repository seams, so the network layer can't be swapped for a fake without
  touching many call sites.

Consequence for sequencing:

- **Testable now, cleanly**: the `SecureStorage` service (new, pure, one dependency to mock),
  the `fromJson` parsers in `bloc.dart` (pure functions over a JSON map), and widget tests of
  the smaller screens (`UnauthorizedScreen`, the login form).
- **Testable only after refactor**: the context-taking, navigating cubits and the giant
  build methods. These map onto refactors already in the review (ARCH-2, CQ-1) — testing and
  that refactor reinforce each other.
- **The NAV-1 confidence** specifically comes from a **navigation test**: either a widget test
  that mocks `SecureStorage` + HTTP and asserts "start → login → dashboard", or an integration
  test running the real flow. That test is the deliverable that makes NAV-1 safe to change.

## 5. The one decision needed before implementation — backend strategy

Unit and widget tests need **no** backend and **no** build artifact from anyone — they run via
`flutter test` on the host. Integration tests of the real flows, though, hit the app's backend
(device pairing against `setup.app4shark.com`, login, GraphQL), and those flows need either:

- **(A) a mocked network layer** — introduce a seam so tests inject a fake HTTP/GraphQL client
  returning canned responses. More upfront work (it's a small refactor), but the tests are
  fast, deterministic, run in CI with no credentials, and touch no real environment. Recommended.
- **(B) a real test account / test environment** — point integration tests at a beta backend
  with a throwaway account. Less test code, but the tests need network + credentials, are
  flaky, and can't run in CI cleanly.

Recommendation: **(A)**, mock the network at a seam, so the suite is CI-friendly and needs
nothing from a live environment. This is the only input required from the engineer.

## 6. Proposed starter plan (after the decision)

1. Add dev dependencies: `bloc_test`, `mocktail`, `integration_test` (SDK).
2. Structure: `test/` mirrors `lib/` (`test/storage/secure_storage_test.dart`,
   `test/model/...`, `test/view/...`); `integration_test/` at the repo root for E2E.
3. Replace the boilerplate `test/widget_test.dart` (its counter test does not match this app).
4. First tests, in order of value: `SecureStorage` (unit, incl. the migration path — a real
   behavior with a bug surface), the `fromJson` parsers (unit), a widget test of the login
   screen, then the navigation test that underpins NAV-1.
5. CI: add `flutter analyze --fatal-infos` + `flutter test --coverage` to `codemagic.yaml`
   before the build — this also closes review finding CI-1 (the pipeline has no quality gate
   today).

## 7. Sources

- [Flutter — Testing overview (the three types, where each runs)](https://docs.flutter.dev/testing/overview)
- [Very Good Ventures — Flutter testing resources (mocktail, bloc_test, the tooling kit)](https://verygood.ventures/blog/flutter-testing-resources/)
- [freeCodeCamp — Unit, Widget, Golden, and Integration tests explained](https://www.freecodecamp.org/news/how-to-test-flutter-apps-unit-widget-golden-and-integration-tests-explained/)
- [Patrol — native-interaction E2E on top of integration_test](https://patrol.leancode.co/)
- [Firebase — Integration testing with Flutter (per-platform device execution)](https://firebase.google.com/docs/test-lab/flutter/integration-testing-with-flutter)
