# PLAN — Automated store delivery for app-mobileclient (Codemagic, Android + iOS)

## Goal

Replace the current manual, undocumented release process for the `app-mobileclient`
Flutter app with an automated pipeline: merging a PR to `master` builds, signs, and
publishes **both** the Android app bundle to Google Play **and** the iOS build to
App Store Connect, with no manual steps.

## Current status

The pipeline is built and live: a push to `master` builds, signs, and publishes both stores automatically, driven by `codemagic.yaml` in the repo root. Release 1.1.4 shipped through it — **Android 1.1.4 is public in Google Play production (100%)** and **iOS 1.1.4 is released and public on the App Store**. Both are restricted to the 14-country availability list below. Store detail is in § Store submission status; the credentials that drive the pipeline (1Password vault: Technology Administration):

- **Android upload key** — the original keystore was lost (former third party held it); a new upload key was generated and the Play Console upload-key reset took effect Sep 6, 2026. Keystore + password in 1Password item **"CodeMagic (Google Play Store)"** (alias `upload`).
- **Google Play service account** — Google Cloud project **Google Play Publishing** (`halogen-byte-507615-r6`), Play Android Developer API enabled. JSON key in 1Password item **"Codemagic - Google Play Service Account (JSON)"**. Scoped in Play Console → Users & permissions to `com.sharkapp.sharkreal` with production + testing-track release permissions. Active. A stray Google Cloud default project "My First Project" also carries the Play API enabled by mistake — harmless, deletable anytime.
- **App Store Connect API key** — the active key is `codemagic-ios-publisher`, Key ID `WX5BG9ZZN7`, access App Manager. `.p8` + Key ID + Issuer ID (`53fe768e-920c-46fd-a228-0586120b783e`) in 1Password item **"CodeMagic (Apple Store)"**. The superseded key `CodeMagic` (`VNGXS2378P`) is revoked (visible under Revoked for 30 days after revocation).

## Country availability

Both stores are available in these 14 countries and no others: Argentina, Brasil, Chile, Colômbia, Costa Rica, Equador, Estados Unidos, México, Panamá, Paraguai, Peru, República Dominicana, Uruguai, Venezuela. The footprint is the Atento contract region plus the United States — the contract covers the region and the 4Shark site advertises availability there, so the app stays available region-wide even though only some countries are in active use.

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
- `codemagic.yaml` in the repo root drives both workflows (`android-release`, `ios-release`); there is no `.github/` or `fastlane`. Store releases before the pipeline (up to Play production versionCode 25) were built out-of-band — local `flutter build` + manual upload by the former third party — which is why the pipeline derives the build number from each store's latest rather than from `pubspec.yaml`.
- Codemagic account: login `paulo@4shark.com.br` (passwordless email code), billed to `billing@4shark.com.br`, free/pay-as-you-go plan.

## Store submission status

### Google Play (`com.sharkapp.sharkreal`)

- **1.1.4 is live in production at 100%.** The privacy-policy requirement that blocked an earlier update (Policy status: User Data policy → "Política de Privacidade inválida") is satisfied — the policy is published at `https://www.4shark.com.br/politica-de-privacidade` and set in Play Console → App content → Privacy policy. The Data safety form must stay consistent with the policy text.
- Country availability matches the 14-country list in § Country availability: the change (add Costa Rica, Equador, Panamá, Paraguai, República Dominicana, Uruguai; remove Bolívia, Canadá, Cuba, Guatemala, Nicarágua, Suriname) is submitted for review and publishes on approval, with managed publishing off.

### Apple App Store

- **1.1.4 is released and public.** The IPA is built and delivered to App Store Connect by the pipeline; the App Store submission and the "Release this version" step are manual (`codemagic.yaml` sets `submit_to_app_store: false`), so every iOS release needs that manual submission. Availability is set to the 14 countries in § Country availability.

## References

- Codemagic — Google Play publishing with codemagic.yaml: https://docs.codemagic.io/yaml-publishing/google-play/
- Codemagic — App Store Connect publishing with codemagic.yaml: https://docs.codemagic.io/yaml-publishing/app-store-connect/
- Play Console — target API level requirements: https://support.google.com/googleplay/android-developer/answer/11926878
