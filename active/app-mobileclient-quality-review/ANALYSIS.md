# ANALYSIS — app-mobileclient Flutter Quality Review

Full code review of the `app-mobileclient` Flutter application against Flutter/Dart
community best practices. Current state, gap catalogue, and a phased remediation plan.

- **Repository**: `~/Projects/4Shark/app-mobileclient`
- **Version reviewed**: `1.1.4+1` (shipped: SSO, digital signature, offline-first, sales dashboard, ES translation)
- **Flutter**: 3.32.0 (pinned via `.fvmrc`) · Dart SDK constraint `^3.5.3`
- **Reviewed**: 2026-09-16
- **Scope**: `lib/`, `android/`, `ios/`, `pubspec.yaml`, `analysis_options.yaml`, `codemagic.yaml`, `test/`

---

## 1. Executive summary

The app works and ships to the stores, but it is a **prototype that reached production without
an architecture**. There is effectively no layering, no test coverage, and several
store-rejection / security issues live in the current build.

The dominant problem is structural: **~15,450 lines of application code across only 25 files**,
with single files of 3,582 (`bloc.dart`), 2,201 (`statement_result.dart`) and 1,103 (`main.dart`)
lines. Data models, business logic, GraphQL queries and UI are all interleaved. This is not a
style complaint — it is why every change is risky and why release builds keep breaking (two
"release build" fixes in the last changelog entry alone).

**Overall health: POOR, with the urgent block cleared.** None of the findings is unfixable, and the
three urgent security/store items — iOS ATS disabled (SEC-1), IDFA/ATT tracking without its usage
string (SEC-2), and the JWT in plaintext storage (SEC-3) — are resolved (PRs #11, #12, #13). A
GitHub Actions analyze/test gate now runs on every pull request (CI-1), self-hosted dependency
automation with a 7-day minimum-release-age quarantine guards the supply chain, and a navigation
guard test pins the router's login route. The remaining weight is architectural, not security.

### Headline metrics

| Metric | Value | Healthy target |
|---|---|---|
| Non-generated Dart files in `lib/` | 25 | — |
| Total non-generated LOC in `lib/` | ~15,450 | — |
| Largest single file (`model/bloc/bloc.dart`) | 3,582 LOC | < 300 |
| Files over 900 LOC | 8 | 0 |
| Real tests | foundation in place (secure-storage / bloc-parser / unauthorized / navigation specs) | broad coverage |
| `setState(...)` calls | 96 | low (state lives in Bloc) |
| Inline color literals (`Color.fromRGBO/ARGB`) | 120 | 0 (design tokens) |
| `Navigator.*` calls (app uses go_router) | 47 | 0 — navigate via router |
| Nested `MaterialApp(...)` | 4 (1 root + 3 inner) | 1 |
| `context` usage inside `model/` (business layer) | 40 | 0 |
| Inline GraphQL query sites | 35 | 0 (typed operations) |
| `TODO/FIXME` left in code | 22 | 0 |
| `flutter analyze` / `flutter test` in CI | required PR gate (GitHub Actions) | required gate |
| Secure storage for auth token | `flutter_secure_storage` | `flutter_secure_storage` |

---

## 2. Method

- Read every non-generated file in `lib/` in full or in representative depth (all networking,
  state, routing, entry-point files fully; the giant view files sampled for structure).
- Read all native config: `android/app/build.gradle`, `AndroidManifest.xml`, `MainActivity.kt`,
  `ios/Runner/Info.plist`.
- Read `pubspec.yaml`, `analysis_options.yaml`, `codemagic.yaml`, `l10n.yaml`, `test/`.
- Quantified systemic smells with `grep` across `lib/`.
- Two external claims (package deprecation, lint version) verified against pub.dev via web search
  rather than asserted from memory.

Severity legend: **Critical** (security, store rejection, or user-facing crash in the current
build) · **High** (breaks maintainability/correctness at scale) · **Medium** · **Low**.

---

## 3. Findings

### D. Security — the urgent block

**SEC-1 (Critical · ✅ RESOLVED — PR #11) — iOS App Transport Security fully disabled.**
`ios/Runner/Info.plist` had `NSAllowsArbitraryLoads = true`, turning off ATS for the whole app. The
app talks to its backend over HTTPS only, so this blanket exception was both unnecessary and
dangerous (it silently permits cleartext and downgraded-TLS connections to any host) and is a common
App Store review rejection reason. ✓ Resolved in PR #11 — the key was removed entirely; scope any
future host exception under `NSExceptionDomains`.

**SEC-2 (Critical · ✅ RESOLVED — PR #12) — IDFA/ATT tracking without `NSUserTrackingUsageDescription`.**
`lib/http/device/device_http.dart` called `AppTrackingTransparency.requestTrackingAuthorization()`
and read the advertising id, while `ios/Runner/Info.plist` declared no `NSUserTrackingUsageDescription`.
On iOS the tracking prompt without this key is a guaranteed App Store rejection and the tracking
call can throw. ✓ Resolved in PR #12 — the IDFA/ATT path was removed: device identification moved to
`flutter_udid`, and `advertising_id` + `app_tracking_transparency` were dropped, so no tracking
prompt (and no missing-key rejection) remains (see DEP-3).

**SEC-3 (Critical · ✅ RESOLVED — PR #13) — auth JWT stored in plaintext `SharedPreferences`.**
The session token was written to and read from `SharedPreferences` under `auth_token`.
`SharedPreferences` is unencrypted (plist / XML on disk) and readable on rooted/jailbroken or
backed-up devices. A bearer token for a signing-capable financial app belongs in the Keychain /
Keystore. ✓ Resolved in PR #13 — `auth_token` and the device `configuration` payload were moved to
`flutter_secure_storage` (Keychain / Keystore), with a one-time migration off `SharedPreferences`.

**SEC-4 (High) — real JWT and demo credentials committed in source.**
`lib/main.dart:326,336` contain a live-looking bearer token
(`eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjozMDIyMTIs...`) in comments; demo credentials
`roberto.carlos@demo.com.br` / `Empresademo2022#` are commented in `lib/main.dart:532,596` and
`lib/view/initialization/login.dart:144,206`; `renata.freire@demo.com.br` at `lib/model/bloc/bloc.dart:2723`.
Even if expired, tokens and credentials must never live in the repo. → Remove them; rotate the
token/account if still valid; scrub from history if warranted.

**SEC-5 (Medium) — all backend errors are swallowed into empty maps.**
Every network method does `catch (e) { return {}; }` (`login_http.dart:40`, `device_http.dart:68,94`,
`bloc_login.dart:19`) and none checks `response.statusCode`. A 401, a 500, an expired token and a
network outage are indistinguishable to the caller, so the UI cannot tell "wrong password" from
"server down", and security-relevant failures are invisible. → Return typed results
(success/failure), inspect status codes, and surface auth failures explicitly.

### A. Architecture & state management

**ARCH-1 (High) — no layering; one 3,582-line god file.**
`lib/model/bloc/bloc.dart` mixes Hive `@HiveType` data models, `fromJson` parsing, ~25 Cubits,
and inline GraphQL query strings in a single file. There is no data/domain/presentation
separation and no repository layer. → Split into `models/`, `repositories/` (data access),
`blocs/` (one file per bloc/cubit), and typed GraphQL operations. This is the root cause behind
most other findings.

**ARCH-2 (High) — business logic reads `BuildContext` and drives navigation.**
Cubits take `BuildContext` and act on the UI: `BlocDashInit.fetchUser(BuildContext context)` calls
`context.read<BlocConnected>()` and `Navigator.pushAndRemoveUntil(context, ...)` from inside the
cubit (`bloc.dart:75-120`); `bloc.dart:3429` navigates to `LoginView` from the business layer.
40 `context` references live under `model/`. This defeats the entire point of BLoC (UI-independent
logic, testability). → Cubits expose state only; the widget layer reacts (`BlocListener`) and
navigates.

**ARCH-3 (High) — three overlapping state/data mechanisms plus a redundant one.**
`flutter_bloc` (state), `provider` (also present — largely redundant, `flutter_bloc` re-exports it),
`graphql_flutter` (its own cache/state) and `hive` (local) are all in play with no clear
boundaries, and a client is rebuilt per request (see NET-1) so the GraphQL cache never works.
→ Pick one state approach (Bloc), one data-access pattern (repository over a single long-lived
GraphQL client), and remove `provider` if unused.

**ARCH-4 (Medium) — 28 `BlocProvider`s instantiated at the root, several eagerly, two duplicated.**
`lib/main.dart:85-221` registers 28 blocs globally. `BlocPlanStatementRules` is created twice
(lines 92 and 142) and `BlocStatementRulesView` twice (157 and 167). Global eager creation wastes
memory and couples everything to the root. → Scope blocs to the routes/screens that use them;
remove the duplicates.

**ARCH-5 (Medium) — models are mutable and have no value equality.**
Hive models (e.g. `DashboardModel`, `bloc.dart:13-45`) carry mutable fields and no `==`/`hashCode`.
`Cubit<DashboardModel>` therefore can't diff states reliably (rebuild-always or miss-rebuild).
`loading` is a bool field on the data model rather than a modelled state. → Use immutable models
with value equality (`equatable`/`freezed`) and model loading/error as distinct states.

### B. Routing & navigation

**NAV-1 (High) — `MaterialApp` nested inside `MaterialApp`.**
`lib/main.dart:222` builds a root `MaterialApp.router`, and each `GoRoute.builder` returns *another*
full `MaterialApp` (lines 230, 256, 297). Nested `MaterialApp`s create competing `Navigator`s,
`Theme`s and localization scopes — this is why localization delegates had to be duplicated on every
inner app, and it is a documented source of navigation/back-button and theming bugs. This is an
architecture/maintainability item, not a security or store risk. → Exactly one `MaterialApp.router`;
routes return plain screens; declare theme/localization once. The removal is a navigation redesign,
not a mechanical edit: the whole app navigates imperatively (`Navigator.push`/`pop`, NAV-2) inside
the per-route nested `Navigator`, so collapsing to one `MaterialApp` moves the entire imperative flow
onto go_router's root navigator and needs device validation. A router guard test now pins the login
route (PR #18) as the net beneath that change — best done together with NAV-2 as its own scoped
project, not a quick edit.

**NAV-2 (High) — imperative `Navigator.push` mixed with declarative go_router.**
47 `Navigator.*` calls coexist with go_router (`main.dart:662`, `start.dart:49,56,68`,
`bloc.dart:109,3429`, etc.). The two navigation models fight (deep links, back stack, redirects).
→ Route exclusively through go_router (`context.go`/`context.push`); define auth redirect in the
router's `redirect`.

**NAV-3 (Medium) — a route builder returns a bare `CircularProgressIndicator()`.**
`lib/main.dart:294,338` return a raw `CircularProgressIndicator` as a full route body — no
`Scaffold`/`Directionality`, which risks a runtime "No Directionality widget" error and shows an
unstyled spinner. → Return a proper loading screen.

**NAV-4 (Medium) — auth gating done inside a widget's `initState` with post-frame navigation.**
`lib/view/initialization/start.dart:18-83` decides the whole entry flow in `initState` via
`addPostFrameCallback`, nested `.then()` chains and `Navigator.pushAndRemoveUntil`, with a blank
`Scaffold()` as the visible screen. → Move to a router redirect / `refreshListenable` driven by an
auth cubit.

### C. Networking & data layer

**NET-1 (High) — a new `GraphQLClient` is built on every query/mutation.**
`GraphQLService.performQuery/performMutation` call `getClient()` each time, which re-reads
`SharedPreferences` and constructs a fresh `GraphQLClient` + empty `GraphQLCache`
(`lib/model/graphql.dart:9-47`). The cache is discarded every call, so `graphql_flutter`'s caching,
normalization and dedup never happen. → One long-lived client (or `GraphQLProvider`), token
supplied via an `AuthLink` that reads secure storage lazily.

**NET-2 (High) — GraphQL queries are hand-built strings with interpolated variables.**
35 inline query sites; values are string-interpolated into the query body, e.g.
`calendarId: "373"` hardcoded and `beforeDate: "${DateFormat(...).format(...)}"` (`bloc.dart:62-102`).
This is stringly-typed, unmaintainable, and an injection vector. → Use GraphQL `variables` (never
interpolation) and adopt `graphql_codegen` for typed operations.

**NET-3 (Medium) — two networking stacks and two base-URL strategies.**
Both `http` (devices, login) and `graphql_flutter` (everything else) are used. The base host is
hardcoded in one place (`setup.app4shark.com`, `device_http.dart:44,80`) and read from stored
`configuration` in another (`login_http.dart:18`, `graphql.dart:24`). → Centralize endpoint
resolution; consider one HTTP approach or a clear split with a shared config source.

**NET-4 (Medium) — no request timeouts, no ret/status handling, `config!` force-unwrap.**
None of the HTTP/GraphQL calls set a timeout; `jsonDecode(config!)` (`login_http.dart:14`,
`graphql.dart:21`) crashes if the device was never configured. → Add timeouts, handle nulls
explicitly (no `!`), and return typed errors.

**NET-5 (Low) — `BuildContext` passed into the HTTP layer unused.**
`DeviceHttp.PostDevices(BuildContext context)` never uses `context` (`device_http.dart:40`). → Drop
the parameter; the data layer must not depend on the widget tree.

### E. Code quality & structure

**CQ-1 (High) — monolithic `build()` methods; no widget extraction.**
The large view files contain only two classes each (the widget + its `State`) across 900–2,201
lines — e.g. `statement_result.dart` (2,201), `statement_rules.dart` (1,794),
`dashboard_component.dart` (1,104), `deal.dart` (941). Everything is one deeply-nested `build`.
`StartApp` alone is a ~700-line widget living inside `main.dart` (400-1103). → Extract small,
`const`, reusable widgets into `widgets/`; keep files under ~300 LOC.

**CQ-2 (High) — the two login screens are duplicated.**
`StartApp` (`main.dart:400+`) and `LoginView` (`view/initialization/login.dart`) are near-identical
login forms (both carry the same demo-credential comments). → Extract one shared login form widget.

**CQ-3 (Medium) — method names violate Dart lowerCamelCase.**
`PostLogin`, `PostDevices`, `PostDevicesConfiguration`, `getAdvertisingId`-siblings use PascalCase
(`login_http.dart:7`, `device_http.dart:40,73`). Effective Dart: methods are `lowerCamelCase`.
→ Rename.

**CQ-4 (Medium) — pervasive misnaming: `Modal` for `Model`.**
`PeriodsModal`, `PeriodModal`, `PlanModelView` vs `PeriodModal`… "Modal" (a UI dialog) is used
where "Model" (data) is meant, throughout `bloc.dart`. → Rename to `Model`.

**CQ-5 (Medium) — 120 inline color literals, no design system.**
`Color.fromRGBO(0, 71, 120, 1)` and friends are repeated 120× across the UI; `AppStyle`
(`configuration/app_style.dart`, 101 LOC) exists but is barely used, and colors are also hardcoded
on inner `ThemeData`. → Centralize colors/typography/spacing in the theme + a token file; consume
via `Theme.of(context)`.

**CQ-6 (Medium) — hardcoded UI strings despite full l10n setup.**
`"Você não possui permissão!"`, `"Tentar Novamente"` (`main.dart:351,379`), `"Desconhecido"`
(`device_http.dart:37`) are hardcoded while the rest uses `AppLocalizations`. → Move all
user-facing strings to ARB.

**CQ-7 (Medium) — dead code, `.then()` pyramids, 22 TODOs, empty `class UserAdapter {}`.**
Large commented-out blocks throughout (`bloc.dart`, `graphql.dart:49-66`, `main.dart`), nested
`.then()` where `async/await` belongs, 22 `TODO/FIXME`, and empty classes (`bloc.dart:123`). →
Delete dead code, convert to `async/await`, resolve or ticket the TODOs.

**CQ-8 (Medium) — `BuildContext` used across `await` gaps without `mounted` guards.**
`start.dart:29-78` uses `context` for `Navigator` after several `await`s inside a post-frame
callback with no `if (!mounted) return;`. → Guard every context use after an await.

### F. Testing & CI

**TEST-1 (High · ◐ IN PROGRESS — PRs #15, #18) — thin test coverage.**
The default `widget_test.dart` counter test was replaced by a real foundation: secure-storage,
bloc-parser and unauthorized-screen specs (PR #15), plus a navigation guard test that drives the
real `GoRouter` to `/login` and asserts the unauthorized screen renders with localization resolved,
no network (PR #18). `bloc_test` + `mocktail` are wired in. Coverage is still far from broad — the
~25 cubits, the repository/parsing paths and the large view files remain largely uncovered. →
Continue: cubit unit tests for auth and dashboard, repository/parsing tests, key widget tests; wire
coverage into CI.

**CI-1 (High · ✅ RESOLVED — PR #16) — no analyze/test gate on changes.**
A GitHub Actions workflow (`.github/workflows/ci.yaml`) runs `flutter analyze --no-fatal-infos`
(warnings fatal) and `flutter test` on every pull request, so lint-failing or test-failing code can
no longer merge to `develop`/`master`. ✓ Resolved by the PR gate (PR #16). Residual (lower
priority): `codemagic.yaml` — the store delivery pipeline on `master` push — still carries no
analyze/test step of its own; the PR gate covers the merge path, which is where broken code is
caught before it can reach a delivery build.

### G. Native / platform configuration

**PLAT-1 (High) — three inconsistent Android package identities.**
`applicationId`/`namespace` = `com.sharkapp.sharkreal` (`build.gradle:9,25`); `MainActivity`
declared as `com.shark.four_shark.MainActivity` (`AndroidManifest.xml:8`, matching the file's
`package com.shark.four_shark`); but the file physically lives under
`kotlin/com/4shark/four_shark/MainActivity.kt` — a directory whose segment `4shark` is not even a
legal Java/Kotlin package identifier (starts with a digit). It compiles today, but the identity is
fragmented and fragile. → Align the Kotlin package, directory path, and manifest reference under a
single, valid namespace.

**PLAT-2 (Medium) — no ProGuard/R8 keep rules with minify + shrink enabled.**
`build.gradle:47-51` enables `minifyEnabled true` + `shrinkResources true` for release but ships no
`proguard-rules.pro`. Reflection-based plugins (graphql, appauth, pdf, hive) can be stripped,
producing release-only crashes — consistent with the changelog's repeated "Fixed release build".
→ Add keep rules and verify a release build end-to-end.

**PLAT-3 (Medium) — no environment/flavor separation.**
Single build config; the backend host is hardcoded/prod-ish. There is no dev/staging/prod flavor.
→ Add flavors (or `--dart-define`) so beta and prod are distinct builds.

**PLAT-4 (Low) — launcher icon generated from JPG; landscape allowed on a portrait UI.**
`flutter_icons.image_path: assets/icon-blue.jpg` (JPG has no alpha) and `Info.plist` allows all
orientations though the UI is portrait-only. → Use a PNG source; restrict orientation if intended.

**PLAT-5 (Low) — Android `CAMERA` permission not declared explicitly.**
The QR scanner relies on the plugin's merged manifest for `CAMERA`; the app manifest declares only
`INTERNET`. → Declare `android.permission.CAMERA` explicitly for clarity.

### H. Dependencies

**DEP-1 (High · ✅ RESOLVED — PR #31) — `qr_code_scanner` is in maintenance mode / effectively deprecated.**
pub.dev states it was moved to maintenance mode because its native frameworks (zxing,
MTBBarcodeScanner) are unmaintained; the recommended replacement for new/long-term projects is
`mobile_scanner`. ✓ Resolved in PR #31 — the QR scanner screen was migrated to `mobile_scanner` 7.

**DEP-2 (High · ✅ RESOLVED — PR #30) — `graphql_flutter: ^5.2.0-beta.8` — a beta pinned in production.**
Shipping a `-beta` dependency in a store app. ✓ Resolved in PR #30 — moved to the `5.3.0` stable
release and re-tested against the app's GraphQL operations.

**DEP-3 (Medium · ✅ RESOLVED) — unused / redundant dependencies.**
Fully pruned: `advertising_id` + `app_tracking_transparency` (the IDFA/ATT obligation behind SEC-2)
in PR #12; the dead third-party `flutter_localization` removed and `provider` removed (redundant —
`flutter_bloc` re-exports it); `flutter_launcher_icons` moved to `dev_dependencies`; and the unused
`flutter_gen_runner` dropped during the Flutter 3.47 upgrade.

**DEP-4 (Medium · ✅ RESOLVED) — `flutter_lints: ^4.0.0` is behind the current major.**
`flutter_lints` was upgraded to `6.0.0`. Adopting stricter analyzer settings (strict-casts /
strict-inference / strict-raw-types) is still open and tracked under TOOL-1.

### I. Internationalization

**I18N-1 (Medium) — gen-l10n configured but coverage is incomplete and partly bypassed.**
`l10n.yaml` + `generate: true` drive gen-l10n (en/pt/es ARB present), yet hardcoded strings remain
(CQ-6) and a redundant third-party localization package is declared (DEP-3). ARB keys use
un-spaced lowercase concatenations (`seuemailpodeestarincorreto`) rather than descriptive ids.
→ Route all strings through ARB, remove the redundant package, adopt readable keys.

### J. Tooling, lints & project hygiene

**TOOL-1 (Medium) — default lint set, no strict analyzer.**
`analysis_options.yaml` only includes `flutter_lints` with no added rules and none of
`strict-casts` / `strict-inference` / `strict-raw-types`. Given the `!` force-unwraps and untyped
`Map`s, stricter analysis would catch real bugs. → Enable strict language modes and a stronger lint
set; treat `use_build_context_synchronously` and `always_declare_return_types` as errors.

**TOOL-2 (Low) — package name and metadata are boilerplate.**
`pubspec.yaml` `name: FourShark` violates Dart package naming (should be `lower_snake_case`, e.g.
`four_shark`; the uppercase leaks into every `import 'package:FourShark/...'`); `description: "A new
Flutter project."`; `README.md` is the default Flutter template. → Fix the name (rename import
prefix), write a real description and README.

**TOOL-3 (Low) — 7 inline `// ignore:` lint suppressions.**
Small but worth auditing — each hides a real warning. → Review and remove where possible.

---

## 4. Severity summary

| Severity | Open | IDs (✅ resolved · ◐ in progress) |
|---|---|---|
| **Critical** | 0 | SEC-1 ✅, SEC-2 ✅, SEC-3 ✅ — all resolved (PRs #11 / #12 / #13) |
| **High** | 12 | NAV-1, SEC-4, ARCH-1, ARCH-2, ARCH-3, NAV-2, NET-1, NET-2, CQ-1, CQ-2, PLAT-1 · TEST-1 ◐ (PRs #15/#18) · CI-1 ✅ (#16), DEP-1 ✅ (#31), DEP-2 ✅ (#30) |
| **Medium** | 17 | SEC-5, ARCH-4, ARCH-5, NAV-3, NAV-4, NET-3, NET-4, CQ-3, CQ-4, CQ-5, CQ-6, CQ-7, CQ-8, PLAT-2, PLAT-3, I18N-1, TOOL-1 · DEP-3 ✅ (#12 +migration), DEP-4 ✅ |
| **Low** | 5 | NET-5, PLAT-4, PLAT-5, TOOL-2, TOOL-3 |

**Total: 42 findings — 8 resolved (SEC-1/2/3, CI-1, DEP-1/2/3/4), 1 in progress (TEST-1), 33 not yet started.**
No Critical remains open: the three security/store criticals are fixed, the dependency stack is
modernized (all four DEP findings resolved), and NAV-1 is reclassified High (architecture, not
security). The remaining open weight is architectural (ARCH / NAV / NET / CQ) plus SEC-4 repo
hygiene and the native/tooling items.

---

## 5. Remediation plan

Phased so that store/security risk is retired first, then the architecture is put in place, then
the code is brought onto it. Each phase is independently shippable. Items reference the finding IDs
above.

### Phase 0 — Urgent: security & store risk (the urgent block is cleared)

0.1 ✅ (PR #11) Removed `NSAllowsArbitraryLoads` from `Info.plist` (SEC-1).
0.2 ✅ (PR #12) Removed the IDFA/ATT path — moved to `flutter_udid`, dropped `advertising_id` +
    `app_tracking_transparency` (SEC-2, DEP-3 partial).
0.3 ✅ (PR #13) Moved `auth_token` + `configuration` to `flutter_secure_storage` (SEC-3).
0.4 ☐ Remove committed token/credentials; rotate if still valid (SEC-4). **Still open.**
0.5 ✅ (PR #16) Added a GitHub Actions PR gate running `flutter analyze` + `flutter test` (CI-1).
0.6 ☐ Add ProGuard/R8 keep rules and verify a release build end-to-end (PLAT-2). **Still open.**

The two open items (0.4, 0.6) are not blockers to a working build; SEC-4 is repo hygiene (removing
commented-out tokens/credentials) and PLAT-2 is a release-build hardening step.

### Phase 1 — Foundations: architecture skeleton

1.1 Collapse to a single `MaterialApp.router`; move theme/localization to the root; return plain
    screens from routes (NAV-1, NAV-3).
1.2 Split `bloc.dart` into `models/`, `repositories/`, `blocs/`; one bloc per file (ARCH-1).
1.3 Introduce a repository layer over a single long-lived `GraphQLClient`; token via `AuthLink`
    reading secure storage (NET-1, ARCH-3).
1.4 Remove `BuildContext`/navigation from cubits; cubits emit state, widgets react and navigate
    (ARCH-2).
1.5 Route all navigation through go_router; define auth redirect via `refreshListenable`
    (NAV-2, NAV-4).
1.6 Immutable models with value equality (`equatable`/`freezed`); model loading/error as states
    (ARCH-5).

### Phase 2 — Data & networking hardening

2.1 Replace string-interpolated queries with GraphQL `variables`; adopt `graphql_codegen`
    (NET-2).
2.2 Typed request results, status-code handling, timeouts, no `!` force-unwraps, no empty-map
    swallowing (NET-4, SEC-5).
2.3 Centralize endpoint/config resolution; converge networking approach (NET-3, NET-5).
2.4 ✅ (#31) Migrated `qr_code_scanner` → `mobile_scanner` (DEP-1).
2.5 ✅ (#30) Moved `graphql_flutter` off the beta channel to `5.3.0` stable (DEP-2).
2.6 ✅ Pruned dependencies: dropped `flutter_localization`, removed `provider`, moved
    `flutter_launcher_icons` to `dev_dependencies`, dropped unused `flutter_gen_runner` (DEP-3).

### Phase 3 — UI decomposition & consistency

3.1 Extract widgets from the monolithic `build()`s; target < 300 LOC/file; `const` where possible
    (CQ-1).
3.2 Extract one shared login form; delete the duplicate (CQ-2).
3.3 Design tokens in theme; remove the 120 inline color literals (CQ-5).
3.4 Move remaining hardcoded strings to ARB; remove redundant l10n package; readable ARB keys
    (CQ-6, I18N-1).
3.5 Replace 96 `setState` uses in stateful screens with bloc-driven state where they represent
    domain state (ARCH-2 follow-through).

### Phase 4 — Quality, tests & hygiene

4.1 Scope blocs to routes; remove the two duplicate providers (ARCH-4).
4.2 Rename PascalCase methods; fix `Modal`→`Model`; fix package name `FourShark`→`four_shark`
    (CQ-3, CQ-4, TOOL-2).
4.3 Align Android package identity (namespace / Kotlin package / directory) (PLAT-1).
4.4 Add flavors/`--dart-define` for beta vs prod; declare `CAMERA`; PNG launcher icon; orientation
    lock (PLAT-3, PLAT-4, PLAT-5).
4.5 ✅ (DEP-4) `flutter_lints` upgraded to 6.0.0. Still open: enable strict analyzer modes and
    audit `// ignore:` suppressions (TOOL-1, TOOL-3).
4.6 Delete dead code, convert `.then()`→`async/await`, guard context-after-await, resolve TODOs
    (CQ-7, CQ-8).
4.7 Build a real test suite: cubit unit tests (`bloc_test`), repository/parsing tests, key widget
    tests; wire coverage into CI (TEST-1).
4.8 Real README + description (TOOL-2).

---

## 6. Suggested sequencing note

Phase 0 is a few days of low-risk, high-value work and should ship on its own. Phases 1–2 are the
real investment (they change the shape of the app and touch every screen) — best done behind a
period where feature work pauses or is minimized, because Phase 3 depends on the skeleton existing.
Phases 3–4 can then proceed screen-by-screen and file-by-file, incrementally, without a big-bang
rewrite.
