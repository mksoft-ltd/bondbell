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
| design | done | 2026-11-14 | OpenArt bell icon (nano-banana-pro v1, upright brass bell on #1F5C45) finished in code by `store_assets/icon/build_icon.py` (iOS 1024 no-alpha master, adaptive fg inside the safe zone, monochrome, Play 512, proofs) and wired with flutter_launcher_icons (`flutter_launcher_icons.yaml`; pbxproj bug reverted). Feature graphic 1024x500 = gpt-image-2 background (image-to-image to match the icon bell) + Inter title in code (`store_assets/feature_graphic/build_feature_graphic.py`). `store_assets/BRAND.md` (palette, type, tone, store-art bans, Generated artwork table) and `store_assets/SCREENSHOTS.md` (6 shots x iPhone 6.9"/iPad 13"/Play phone, headlines, framing). **OpenArt credits: 245** (24,000 -> 23,755). lib/ polish: app bar titles were rendering at 14pt (theme titleTextStyle captured before Material geometry was merged) -> now the 22pt default; body letter-spacing tightened. No labels, keys or behaviour changed. Release APK built and its adaptive icon checked. |
| test | done | 2026-11-14 | `flutter analyze` clean; `flutter test` **266 passed** (216 added: purchases against a fake IAP platform, Pro gates in logic, hand-derived scan correctness, every check exit path deleting the download, NS&I HTTP failures, calendar + 09:00 UK reminders across time zones, widget tests for every main flow/state, a layout sweep at iPhone SE/phone/iPad x 1.0-2.0 text). `integration_test/screenshots_test.dart` passed on Android 16 emulator (in-test capture) and iPhone 17 Pro + iPad Pro 13" sims (host capture via `integration_test/capture_ios.sh`), 8 distinct shots each. 4 small logic fixes in lib/ (look-alike nsandi host, holder limit in controller, check session after dispose, reset during navigation build), each verified against its reverted defect. Open, not fixed: large-text overflow on result win row (Medium) and History row (Low), same bond under two holders doubles totals, unconsumed Android tip after restore. Products untested against real stores (not created). See docs/TEST_PLAN.md. |
| code-review | done (PASS) | 2026-11-14 | Re-verified at 5d100a1: **Verdict PASS**. M1, m1–m8 and n1–n5 verified fixed against their original scenarios; n6 not addressed (cosmetic, accepted). New: 0 Critical, 0 Major, 2 Minor (N1: vault write failures and a corrupt vault are silent; N2: a pending Play purchase that hits "already owned" gets a misleading notice), 3 Nit. 327 tests pass. Engine re-run against my separate implementation on the real files (66/66, 180/180). New line splitter fuzz-tested against LineSplitter (20k cases, identical). m3 month check confirmed on the real Jun/Oct/Nov 2026 files. Vault migration probed: upgrade, first launch, failed write keeps prefs, ordered writes, corrupt vault. iOS release build OK and release_guard tested both ways. Previous round at c9346e5: Verdict FAIL — Critical 0 · Major 1 · Minor 8 · Nit 6. M1: the NS&I index is cached for the whole app session, so on results day "latest" still resolves to last month until the app is killed. analyze clean; 283 tests pass. Scan engine checked against a separate Python implementation on the real Nov 2026 winners file (66/66 hits identical) and the unclaimed file (180/180, plus anonymous entries and duplicate-bond probes); integrity ok on both. |
| security | done (PASS, re-verified) | 2026-11-14 | `docs/audits/security.md`. First audit at c9346e5 found no Critical/High. Re-verified at 5d100a1 with my own probes, a simulator upgrade test and the fresh AAB + iOS release. Verified fixed: M-1 (caps proven: 400 MB body, 300 MB declared size, trickle and 5 MB page all rejected; zip bombs stop at the line/declared/512 MB limits), L-1 (off-site, http downgrade, look-alike and userinfo redirects refused before any request; 6th hop refused), L-2 (prefs migrated to Application Support/bondbell_private/vault.json, the folder carries the backup-exclude xattr, nothing left in NSUserDefaults; Android backup still off), L-4 (log scrub). L-3 partly fixed: the release guard fails a stale Archive; dead integration_test framework accepted. Accepted: M-2, L-5, L-6. New Lows: N-1 vault.json.bak/.tmp survive Delete all; N-2 page read has no total deadline. Privacy claim now literally true on iOS and Android for current data. |
| metadata | done | 2026-11-14 | en-GB only, both stores. iOS: `ios/fastlane/metadata/en-GB/*` (name 28, subtitle 26, keywords 98, promo 167, description 3042), copyright/categories (FINANCE/UTILITIES), `review_information/` (notes 3757), `ios/fastlane/app_privacy_details.json` (Data Not Collected). Play: `android/fastlane/metadata/android/en-GB/` (title 28, short 76, full 3097, `changelogs/1.txt` 245) + `android/fastlane/data_safety_answers.md` (data safety No, IARC, target 18+, ads No, Financial features none, gov/news/health No). `PRIVACY_POLICY.md` → `scripts/build_privacy_html.py` → `docs/privacy_policy.html` (Pages must serve `/docs` for the URL in AppConstants). `docs/IAP_PRODUCTS.md`, `docs/AGE_RATING.md` (Apple 4+, contests/gambling none). No £ figures in store copy (en-GB text is served in every storefront). **Skip What's New on first version**: `ios/.../release_notes.txt` stays in the repo but must not be uploaded with 1.0.0. Support URL bondbell.froggyeye.com and the privacy URL not live yet (curl 14 Nov: no DNS / 404). Updated after fix round 2 (5d100a1): policy states the iOS backup-excluded vault vs backed-up settings, Play Billing's own telemetry to Google, and what "Delete all my data" keeps; no store text claims the app contacts nothing but NS&I or checks automatically. |
| compliance | pending | | Independence notice is in onboarding, Home, Settings and About. Purchases could not be exercised (products not yet created). |
| publish | pending | | |
| website | pending | | bondbell.froggyeye.com does not exist yet; privacy policy repo (mksoft-ltd/bondbell, PRIVACY_POLICY.md → privacy_policy.html) not created yet. Both URLs are already in `lib/core/constants/app_constants.dart`. |

## Release build commands (security audit L-3)

- **iOS: always build through Flutter**, never a bare Xcode Archive:
  `flutter build ipa --release` (or `flutter build ios --release` immediately
  before archiving). Flutter rewrites `ios/Flutter/Generated.xcconfig` on
  every build; a screenshot capture leaves it pointing at
  `integration_test/screenshots_test.dart` with `SCREENSHOT_MODE`/
  `HOST_CAPTURE` defines, and Xcode alone does not regenerate it.
  `ios/scripts/release_guard.sh` (Runner's Run Script phase) now fails any
  Release build with a non-`lib/main.dart` target or a screenshot/capture
  define, so a stale file stops the archive instead of shipping.
- Android: `flutter build appbundle --release` (signs with the upload key above).
- Never pass `--dart-define=SCREENSHOT_MODE` / `SCREENSHOT_TOUR` to a release
  build; both are compiled out (`&& !kReleaseMode`) but the guard rejects them
  on iOS anyway.
- `integration_test.framework` is still embedded in the iOS Release app:
  Flutter 3.44 does not filter dev-dependency plugins out of the iOS plugin
  registrant (flutter/flutter#163874), and restricting the pod to Debug makes
  the generated registrant fail to compile. It is dead code in Release (no
  Dart caller, no XCTest linkage). Revisit when Flutter fixes the issue.
