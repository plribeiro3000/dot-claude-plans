# PLAN — Automated store delivery for app-mobileclient (Codemagic, Android + iOS)

## Goal

Replace the current manual, undocumented release process for the `app-mobileclient`
Flutter app with an automated pipeline: merging a PR to `master` builds, signs, and
publishes **both** the Android app bundle to Google Play **and** the iOS build to
App Store Connect, with no manual steps.

## Current status

Credentials for both stores are recovered and stored in 1Password (vault: Technology Administration); the pipeline itself is not built yet. Detail:

- **Android upload key** — the old keystore was lost (former third party held it). A new upload key was generated and an upload-key reset was requested in Play Console. **The new key is only valid from Sep 6, 2026, 15:15 UTC** — until then no upload of any kind is accepted. Keystore + password in 1Password item **"CodeMagic (Google Play Store)"** (alias `upload`).
- **Google Play service account** — created in the Google Cloud project **Google Play Publishing** (`halogen-byte-507615-r6`), Play Android Developer API enabled there. JSON key in 1Password item **"Codemagic - Google Play Service Account (JSON)"**. Invited in Play Console → Users & permissions, scoped to the 4Shark app (`com.sharkapp.sharkreal`) with production + testing-track release permissions. Status: active.
- **App Store Connect API key** — the old `.p8` was lost. A new key was generated: name `codemagic-ios-publisher`, Key ID `WX5BG9ZZN7`, access App Manager. `.p8` + Key ID + Issuer ID (`53fe768e-920c-46fd-a228-0586120b783e`) in 1Password item **"CodeMagic (Apple Store)"**. The old key `CodeMagic` (`VNGXS2378P`) is still active and must be **revoked once the new pipeline is proven working**.

## Remaining work (resumes after Sep 6, when the upload-key reset is approved)

- **Store the three secrets in Codemagic** (Phase 4): the Android keystore (code signing identity), the Google Play service account JSON, and the App Store Connect API key (`.p8` + Key ID + Issuer ID) as secure env var groups. Names must match what the `codemagic.yaml` references.
- **Write `codemagic.yaml`** (Phase 5, agent's PR): Android + iOS workflow, trigger on push to `master`, publish Android → internal track and iOS → TestFlight; remove the hardcoded password fallbacks from `android/app/build.gradle`.
- **First automated release** (Phase 6): merge to `master`, confirm both builds land, promote to public in each store. This also clears the Play target-API advisory (repo already at `targetSdk 36`).

## Where the signing secrets live

A signing secret has exactly two homes and one forbidden location:
- **1Password** — canonical store and backup (source of truth).
- **Codemagic** — encrypted code-signing identity / secure env var, so the pipeline can sign.
- **Never the repository** — the Android `.jks` and the iOS `.p8` are git-ignored; committing either leaks it.

## Decisions (recorded)

1. **`codemagic.yaml` in the repo root, not the UI Workflow Editor.** Version-controlled, reviewable in a PR, and it is what enables the "detected automatically, triggers on push" behavior.
2. **Merge to `master` publishes to the pre-release track on each store automatically; promotion to public is a manual click.** Android → internal testing track; iOS → TestFlight. A mobile public release is effectively irreversible (users update on their own; no server-side rollback), so full auto-to-public is not the default.
3. **Codemagic controls the build number** from each store's latest build number + 1, passed to `flutter build` as `--build-number`. Removes the "must be > 25" collision trap on the Android side; `pubspec.yaml`'s build number stops being authoritative for releases.
4. **Both platforms in one pipeline.** Android builds on Linux (~US$0.045/min); iOS builds require macOS (500 free M2 minutes/month, then US$0.095/min). Expected cost a few dollars/month — no paid plan upgrade.
5. **iOS code signing via the App Store Connect API key (Codemagic automatic signing)** rather than hand-managed distribution certificates. Codemagic fetches/creates the signing assets from the API key, so no iOS equivalent of the `keytool` step and no need to recover the third party's old distribution certificate.

## Context (verified this session)

- Repo `github.com/4shark/app-mobileclient`, Flutter `3.32.0`, Android `applicationId com.sharkapp.sharkreal`, both `android/` and `ios/` present.
- Repo already targets `targetSdk = 36` (`android/app/build.gradle:27`), so the Play API-36 requirement is met in code; only a release is missing.
- No `codemagic.yaml`, no `.github/`, no `fastlane` in the repo — build config was never committed. Codemagic shows the app as "Finish build setup"; past store releases (Play production versionCode 25) were built out-of-band, almost certainly local `flutter build` + manual upload by the former third party.
- Codemagic account: login `paulo@4shark.com.br` (passwordless email code), billed to `billing@4shark.com.br`, free/pay-as-you-go plan.

## Open follow-ups (not blocking)

- Revoke the old App Store Connect key `CodeMagic` (`VNGXS2378P`) after the new pipeline is confirmed publishing.
- Optional housekeeping: the stray Google Cloud default project "My First Project" got the Play API enabled on it by mistake; harmless, can be deleted anytime.

## References

- Codemagic — Google Play publishing with codemagic.yaml: https://docs.codemagic.io/yaml-publishing/google-play/
- Codemagic — App Store Connect publishing with codemagic.yaml: https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Play Console — target API level requirements: https://support.google.com/googleplay/android-developer/answer/11926878
