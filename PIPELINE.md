# Bondbell: pipeline

Store title: Bondbell: Bond Prize Checker · display name: Bondbell ·
bundle/application ID `com.froggyeye.bondbell` · Froggy Eye Ltd

## Store records (created before build)

| Store | Record |
|---|---|
| App Store Connect | app id `6834613888`, bundle ID resource `ZSQ79WX3Y3`, SKU `bondbell`, primary language en-GB, team `696939LPWV` |
| Google Play | app id `4974856772682329433`, free app, default language en-GB. Play Console for this account is at `/u/1/` in the founder's Chrome (as of 14 Nov 2026), not `/u/2/`. |

IAP product IDs (same on both stores): `com.froggyeye.bondbell.pro`
(non-consumable, £4.99), `com.froggyeye.bondbell.tip.small` / `.tip.medium` /
`.tip.large` (consumables, £1.99 / £4.99 / £9.99). Not yet created in either
console.

Android upload key: generated 14 Nov 2026 (none existed). Copies at
`~/.app-keystores/bondbell/` and `android/app/upload-keystore.jks` +
`android/key.properties` (both git-ignored). Alias `upload`, cert SHA-1
`6F:08:DF:5E:7F:C9:44:35:A6:9C:0B:95:35:7D:12:2C:81:F6:98:C5`. Never
regenerate: verify against a built AAB first (house-facts §26, §30).

## Stages

| Stage | Status | Date | Notes |
|---|---|---|---|
| build | done | 2026-11-14 | `flutter analyze` clean; 50 tests pass; release AAB (signed with the upload key above) and iOS release (`--no-codesign`) build. Release APK installed and run on Android 16 emulator: sample flow, live NS&I Nov 2026 winners check (wins found, integrity ok), live unclaimed single-number search, reminders scheduled. iPhone 17 Pro and iPad Pro 13" simulators (iOS 26.5 / 26.0): onboarding plus the sample check end to end via the debug screenshot tour; earlier launch on iOS 27.0 sims stayed alive (no UIScene crash). See docs/PRODUCT_SPEC.md and docs/build_evidence/. |
| design | pending | | App icon is still the Flutter default. Palette: bottle green #1F5C45 and brass #9A6B12 on paper #FAF7F0 (deliberately not NS&I's look). No NS&I marks; "Premium Bonds" never in name or icon. |
| test | pending | | Existing suites: test/*.dart (engine, parser, calendar, index, check session). No widget tests or integration_test/screenshots_test.dart yet. |
| code-review | pending | | |
| security | pending | | |
| metadata | pending | | |
| compliance | pending | | Independence notice is in onboarding, Home, Settings and About. Purchases could not be exercised (products not yet created). |
| publish | pending | | |
| website | pending | | bondbell.froggyeye.com does not exist yet; privacy policy repo (mksoft-ltd/bondbell, PRIVACY_POLICY.md → privacy_policy.html) not created yet. Both URLs are already in `lib/core/constants/app_constants.dart`. |
