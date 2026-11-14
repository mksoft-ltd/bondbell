# Bondbell: test plan

Owner: test stage (mobile-qa-architect). Last updated **14 Nov 2026**.

## Latest run (14 Nov 2026)

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Unit + widget | `flutter test` | **266 passed, 0 failed** (50 from the build stage, 216 added here) |
| Screenshot journey, Android | `flutter drive -d emulator-5556 …` (below) | **All tests passed**. 8 PNGs at 1080×2400, all md5s distinct |
| Screenshot journey, iPhone | `integration_test/capture_ios.sh 6507CD01-9D66-4584-9755-EEAB2132FC59` (iPhone 17 Pro, iOS 26.5) | **All tests passed**. 8 host captures at 1206×2622, 0 duplicates |
| Screenshot journey, iPad | `integration_test/capture_ios.sh 27DBB6C6-9530-4293-8047-C857894EB063` (iPad Pro 13" M5, iOS 26.0) | **All tests passed**. 8 host captures, 0 duplicates |

The timing-sensitive files (`check_session_paths_test.dart`,
`scan_correctness_test.dart`: cancel mid-scan) were run 5 more times in a row
and passed every time.

## Test pyramid and coverage map

All fixtures are synthetic: made-up numbers in NS&I's measured layout, built
in the test (`test/helpers/fakes.dart`: `buildZip`, `winnersFile`). No NS&I
file is in the repo. Expected values in the correctness and calendar suites
were worked out by hand (the derivations are in the test comments), not
recorded from the engine's output.

### Unit (logic)

| File | Tests | Covers |
|---|---|---|
| `test/purchase_controller_test.dart` | 35 | **Money paths** against `FakeStoreGateway` (a fake of the `in_app_purchase` platform that reports outcomes only on the purchase stream, as the plugin does). Pro: success, pending then complete, cancel, Play's empty-id cancel (in flight vs stray), error, "item already owned" → restore, sheet fails to open or throws, store never answers (75 s ceiling), stream error, double tap, already owned. Restore: found, nothing found (after the 4 s window), store unreachable, never revokes Pro, owned Pro re-delivered. Launch: store's own prices (odd test prices prove nothing is hardcoded), entitlement read before the store answers, already-owned Pro delivered on the stream at launch is **persisted before it is finished**, entitlement survives a restart, Android silent restore at launch (and none on iOS). Products missing: none created, only Pro missing, store unavailable, query throws, retry. Tips: each tip is a consumable, finished, thanked, **never grants Pro**, can be given again, a restored tip is finished silently, a foreign product id is finished and ignored, a missing tip buys nothing. Product ids pinned literally. |
| `test/pro_gates_test.dart` | 12 | Every free/Pro line of the spec enforced **in logic**: second holder refused by `HoldersController` itself (free, sample mode), allowed with forced or purchased Pro, unlimited ranges for free; earlier draw and all-bonds unclaimed refused by the check session before any download; latest draw and single-number unclaimed allowed free; buying Pro lifts the gate; paywall lists exactly the four gated features. |
| `test/scan_correctness_test.dart` | 27 | Inclusive range ends, single numbers, serials 000000/999999, same letters + serial in a different series (`312KM` vs `12KM`/`2KM`/`KM`), a short series not fooled by a longer number with the same tail (`99AB…` vs `999AB…`), prefix-less certificates, all four shapes in one scan; ranges across the 99→100 prefix boundary refused, I/O/U refused with hints; overlapping ranges counted once, wins attributed per holder, one number under two holders, the same number drawn twice; prizes per section across page breaks and `(contd.)` headings; integrity fails on a tier mismatch, a grand-total mismatch, a file with no totals, unclaimed END totals, an empty file; deflated and stored ZIPs, truncated downloads, corrupt deflate data (fails rather than reporting a partial result), HTML saved as .zip, empty archive, cancelling a background scan. |
| `test/check_session_paths_test.dart` | 17 | Every way a check ends, each asserting the **downloaded file is deleted**: full check with hand-counted wins across two holders (£1,175), no win, integrity failure (reported and flagged), truncated ZIP, ZIP with no numbers, download error (HTML instead of ZIP), changed downloads page, no draws listed, missing unclaimed link, delisted draw, no bonds saved, **cancel mid-download**, **cancel mid-scan** (result never lands later), provider disposed mid-scan, a new check over a running one; single-number unclaimed search (anonymous entries, no saved bonds needed); real and sample results never mix. |
| `test/draw_source_test.dart` | 15 | `NsiDrawSource` against a scripted HTTP server: honest User-Agent, 503, redesigned page, bot-check page, no connection; HEAD size; good ZIP byte for byte, progress, **HTML instead of the ZIP** (by content type and by ZIP magic), non-200, short body vs Content-Length, network error mid-stream, **cancel mid-download**, each with **no partial file left**; `clearScratch` after a killed check. |
| `test/nsi_index_hosts_test.dart` | 7 | Which links are followed: nsandi.com and subdomains only, look-alike hosts refused (regression), http refused, query strings, month from text vs URL, duplicates. |
| `test/results_calendar_edge_test.dart` | 18 | Friday first working day → Saturday results (May 2026, Oct 2027, Dec 2028), weekend starts, weekend + bank holiday (May 2027), New Year incl. substitute day and the 2029 rule-based year, results day never in the next month, first working day never a weekend/holiday (2026–2032), Christmas substitutes, next results day across the year boundary, 09:00 "strictly after", six months ahead across the year. **09:00 UK time regardless of device time zone**: GMT, BST, the clock-change month, a phone in New York and one in Sydney. |
| `test/screenshot_seed_test.dart` | 3 | `SCREENSHOT_MODE`/`SCREENSHOT_TOUR` are ANDed with `!kReleaseMode` (read from source), off in a plain run; the seed writes only `sample.*`, never a saved purchase. |
| Build stage: `bond_number_test`, `engine_test`, `nsi_index_test`, `results_calendar_test`, `check_session_test` | 50 | Bond-number parsing and messages, parser layouts, the bundled sample ZIPs end to end, index parsing, published bank-holiday table, basic session flow. |

### Widget (UI behaviour)

All widget tests pump the **whole app** (router, theme, snackbar listener)
through `test/helpers/app_harness.dart` with every platform seam faked
(store, reminders, draw source, check session where a state needs showing).
`flutter_test` runs with `Platform.isIOS == false`; there is no
platform-gated UI in Bondbell, so that path is the same one iPhones take.

| File | Tests | Covers |
|---|---|---|
| `test/widgets/onboarding_bonds_test.dart` | 12 | Onboarding (3 pages, independence notice, no permission prompt at launch), sample-mode entry and Exit; add holder (blank name explained), range sheet validation messages, reversed and cross-series ranges, live count, upper-casing, overlap warning across holders, £50,000 warning, free second-holder → Pro dialog, Pro second holder, delete holder confirmation. |
| `test/widgets/check_result_test.dart` | 24 | Check screen in every phase (preparing + cancel, ready with size/Wi-Fi/privacy, unknown size, sample ready, downloading MB of MB + back-button confirm, scanning %, failed with/without "Open NS&I's page", done); leaving a ready check by navigation or "Not now" (regression); results: win, no win, integrity warning, stale bonds, sample win without tip jar, grouping by holder, anonymous unclaimed label, missing result; Home: no bonds, fresh result, stale result, reminder permission only on tap, free earlier-draws upsell. |
| `test/widgets/pro_settings_test.dart` | 22 | Pro screen: four benefits, **store price only** (no £4.99 literal), buy → spinner → unlocked + snackbar, products missing → disabled "Unavailable right now" + retry, cancel (no error), pending, restore with nothing; Settings: price, tips with store prices, tip thanks and Pro stays locked, store unavailable, Pro owned, reminders denied/on/off, sample-mode banner on every tab, delete all data (both scopes, Pro kept); Unclaimed: bad number explained, good number normalised and searched, free/Pro all-bonds; History: free locked, Pro hand-added totals and the 69.93 % yearly rate, newest first, empty. |
| `test/widgets/layout_sweep_test.dart` | 24 | Every main screen and three check states on iPhone SE (375×667), a 393×852 phone, iPad 13" portrait and landscape, at 1.0×, 1.5× and 2.0× text, plus onboarding: no overflow or layout error. Two known 2.0× phone issues are pinned (see Known issues) so any new one fails. |

### Integration

`integration_test/screenshots_test.dart`: one deterministic journey on the
real app with its own `SCREENSHOT_MODE` seed: onboarding page 2 (first run),
then seeded Home, the **real sample check** (bundled synthetic ZIP →
download → background-isolate scan → result, then the scratch folder is
checked empty), check-ready, holder, unclaimed, history (scrolled so the
yearly-rate note is fully visible), Pro. Shot names follow
`store_assets/SCREENSHOTS.md` marketing order:

| Name | Screen |
|---|---|
| `01_result` | Sample check result ("Congratulations!", £100 + £25) |
| `02_onboarding_privacy` | Onboarding page 2 (first run, unseeded) |
| `03_home` | Home: next results, latest draw, reminder card |
| `04_holder` | Sample holder's statement range and old certificate |
| `05_unclaimed` | Unclaimed search |
| `06_history` | History tiles + yearly-rate card with its note |
| `07_check_ready` | Supplementary: check screen before download |
| `08_pro` | Supplementary: Pro screen (forced Pro shows the owned state) |

## How to run

```sh
flutter analyze
flutter test                                   # everything, ~6 s after compile
flutter test test/purchase_controller_test.dart  # one file
```

If a full run ever flakes, rerun the single file alone before believing it.

### Screenshot journey

Debug or profile only: `SCREENSHOT_MODE` is compiled out of release builds.
The test clears the app's SharedPreferences on the device it runs on.

**Android** (in-test capture works; `convertFlutterSurfaceToImage` is called
once per run):

```sh
flutter drive -d emulator-5556 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshots_test.dart \
  --dart-define=SCREENSHOT_MODE=true
# → build/screenshots/<name>.png
md5 build/screenshots/*.png     # all eight must differ
```

Android demo-mode status bar (optional, before running):
`adb shell settings put global sysui_demo_allowed 1 && adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941`.

**iOS simulator** (host-side capture, because `takeScreenshot` on the
simulator can return the launch screen):

```sh
integration_test/capture_ios.sh <simulator-udid>
# e.g. iPhone 17 Pro:  6507CD01-9D66-4584-9755-EEAB2132FC59
#      iPad Pro 13":   27DBB6C6-9530-4293-8047-C857894EB063
# → build/screenshots/ios-<udid>/<name>.png
```

The script sets the 09:41 / full-battery status bar, runs `flutter drive`
with `--dart-define=HOST_CAPTURE=true`, captures with `xcrun simctl io <udid>
screenshot` each time the test prints `BONDBELL_SHOT <name>` (the test holds
the frame `HOLD_SECONDS`, default 4), clears the status bar, and exits
non-zero unless the drive passed, all 8 files exist and no two md5s match.
`flutter drive` built for the simulator without the `flutter build ios
--simulator` lipo failure noted in PRODUCT_SPEC.md (14 Nov 2026, Xcode 27).

Raw captures are not framed; framing is in `store_assets/SCREENSHOTS.md`.

## Regression tests verified against their defects

Each fix below was reverted in an isolated copy of the repo (rsync of HEAD
plus this stage's tests, in the session scratch area) and the test failed
with the predicted symptom; restoring the fix made it pass.

| Defect (fixed in `lib/`) | Test | Failure with the fix reverted |
|---|---|---|
| Downloads-page links accepted any host ending in `nsandi.com` (e.g. `evilnsandi.com`) | `nsi_index_hosts_test`: look-alike host | `Expected: empty, Actual: [Instance of 'RemoteList']` |
| Free holder limit only enforced by the Bonds screen, not the controller | `pro_gates_test`: second holder refused | `Expected: throws FreeTierLimitException, Actual: Future<Holder>` |
| Check session wrote to a disposed provider if torn down mid-check | `check_session_paths_test`: provider disposed mid-scan | `Cannot use the Ref … after it has been disposed` |
| Leaving a ready check by declarative navigation reset the session mid-build | `check_result_test`: leaving a ready check by navigating elsewhere; also failed the Android screenshot journey | `Tried to modify a provider while the widget tree was building` |

Mutation checks on key suites (same isolated copy): finishing a Pro
transaction before persisting it, tips granting Pro, finishing a pending
purchase, scheduling reminders in the device's zone, an exclusive range end,
and disabling the per-tier integrity check each made the matching tests
fail.

## Known issues (found here, not fixed: outside this stage's lane)

| Severity | Issue | Where |
|---|---|---|
| Medium | At 2.0× text on phones, the result win row overflows for a six-figure prize (prize text beside the bond number never shrinks). The test font draws glyphs 1 em wide, so 2.0× here roughly matches the largest iOS accessibility sizes on a real iPhone SE. | `lib/features/draws/presentation/result_view.dart` `_WinRow` |
| Low | At 2.0× text on a small phone, a History row's trailing amount + chevron takes the whole tile width (ListTile assertion). Likely only at the largest accessibility sizes on device. | `lib/features/history/history_screen.dart` |
| Low–Medium | The same bond saved under two holders is reported for both, so totals double (one £100 prize shows as "2 prizes worth £200"). The overlap warning is shown at entry. Product decision. | `check_session.dart` `_record` |
| Low | Android: a tip whose purchase update was never processed (app killed) comes back on restore as `restored`; it is acknowledged but never consumed, so that tip size stays "owned" and can't be bought again. Needs `consumePurchase` through the gateway. | `purchase_controller.dart` |
| Low | The ZIP-magic check skips a first chunk shorter than 2 bytes and then tests the next chunk's start; a non-ZIP still fails later in the ZIP reader, with a less specific message. | `draw_source.dart` `download` |
| Low (cosmetic) | Sample labels are inconsistent: History shows "Sample" next to "October 2026 (sample)", and the result says "in the Sample draw". Sample download size reads "0.0 MB" (already reported by design). | `screenshot_seed.dart`, `SampleDrawSource` |
| By design | Pro is grant-only; a store refund never revokes it. | `purchase_controller.dart` |

## Not covered, and why

- **Real store purchases.** The products do not exist in either console
  yet. Once created: one sandbox (iOS) and one licence-tester (Play) run of
  buy, cancel, restore on a second device, and each tip, including a Play
  "slow card" pending purchase.
- **OS notification scheduling.** `LocalReminderService` talks to
  `flutter_local_notifications`; the times it schedules are tested as a pure
  function, but the plugin call, the permission dialogs and the Android
  reboot receiver need a device check (reminders were seen scheduled on the
  Android emulator at build stage).
- **Live NS&I files.** Tests never touch nsandi.com. The build stage ran the
  live Nov 2026 winners and unclaimed files on an Android emulator; repeat
  that by hand each release, since NS&I can change the layout.
- **Full-size scans and memory.** The engine is tested on synthetic files up
  to 400,000 numbers; the 6.5 million-number file is benchmarked with
  `tool/scan_bench.dart`, not in CI. No physical device was measured.
- **External links** (`url_launcher`) are not tapped in tests.
- **Native code**: none in this app beyond plugins; nothing here exercises
  `android/` or `ios/` beyond the integration builds above.
