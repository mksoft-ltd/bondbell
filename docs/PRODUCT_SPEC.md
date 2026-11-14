# Bondbell: product spec

Store title: **Bondbell: Bond Prize Checker** · home-screen name **Bondbell** ·
bundle/application ID `com.froggyeye.bondbell` · iPhone + iPad (universal,
iOS 15.0+) · Android minSdk per Flutter default, targetSdk 36.

## Summary

A UK Premium Bond prize checker that needs no NS&I login. The user saves bond
number ranges once (from a statement or old paper certificates). When asked,
the app downloads NS&I's public monthly winners file **directly from
nsandi.com onto the device**, checks it against the saved ranges on the
device, keeps only the matches, and deletes the download. It works equally
for a relative's old paper bonds, which is the gap NS&I's own (login-based)
checker leaves.

Bondbell is independent and not affiliated with NS&I. "Premium Bonds" is used
only descriptively in body copy; never in the name or icon.

## Target users

- Bondholders who don't want to log in to NS&I each month, or who hold bonds
  for several family members.
- Families sorting out a relative's affairs who have found old paper
  certificates (the unclaimed-prizes search is aimed at them).
- The audience skews older: large type (body 16–18pt), high contrast, the
  user's text size is honoured everywhere, 48dp+ touch targets.

## Features

### MVP (built)

1. **Holders and bond ranges.** Add/rename/delete holders; each holds ranges
   (start–end, inclusive) or single numbers. Count of bonds and value (£1
   each) per range, holder and in total. Validation with plain-English errors
   (see "Bond number format"). Overlap warning; a gentle warning above NS&I's
   £50,000 per-person limit (never a block, since old bonds can be odd).
2. **Check the latest draw.** Read NS&I's downloads page → show file size +
   "Wi-Fi recommended" → download with progress and Cancel → scan in a
   background isolate with progress and Cancel → per-holder wins with prize
   amounts, or a clear no-win state. Every result says to confirm with NS&I
   and explains how to claim (links to NS&I contact page and prize checker).
   An integrity check compares the numbers read with NS&I's own totals in the
   same file and warns if they disagree. Results are marked stale if the
   user's bonds change afterwards.
3. **Unclaimed prizes search** against NS&I's unclaimed list. Free: one number
   at a time. Pro: every saved range at once. Anonymous-holder entries are
   labelled as such.
4. **Results-day reminder.** Opt-in; permission is asked only when the user
   taps "Turn on reminders" (Home card or Settings switch), never at launch.
   Six months of reminders are queued at 09:00 UK time on each results day
   and topped up at every launch; restored after reboot on Android.
5. **History and stats (Pro).** Every checked draw, total won, prizes, draws
   checked, held now, and an informational yearly-rate figure (prizes over
   the checked draws, annualised, over today's holding) with a "not financial
   advice; past prizes don't predict future ones" note.
6. **Sample mode.** "Try with sample numbers" in onboarding, a Settings
   switch, and an Exit button on the always-visible "Sample mode: made-up
   numbers, not real results" banner. Runs the real download/scan pipeline
   against bundled **synthetic** ZIPs (`tool/generate_sample_data.py`,
   random numbers, fixed seed; nothing from NS&I). Sample data lives in its
   own storage namespace (`sample.*`) and never mixes with real data. Two
   sample holders: "Sample holder" (£20,050: a statement range and an old
   certificate) and "Grandad (sample)" (£50 of old certificates). Three
   sample months: November (£100 + £25), October (£50 + £25, one prize each
   holder), September (no prizes); the sample unclaimed list has £50 + £25.
7. **Tip jar** (Settings, and one quiet card under a real win result; never
   blocks the result, hidden in sample mode). Says plainly that tips unlock
   nothing.

### Free vs Pro (one-time £4.99, `com.froggyeye.bondbell.pro`)

| | Free | Pro |
|---|---|---|
| Holders | 1 (unlimited ranges) | Unlimited |
| Draws | Latest | Any month NS&I lists (about six) |
| Unclaimed search | One number at a time | All saved ranges at once |
| History and stats | — | Yes |
| Reminders, sample mode | Yes | Yes |

**Sample mode opens every Pro feature** on the built-in sample data
(store reviewers can't buy): `proFeaturesProvider` = real Pro OR sample
mode, used by every feature gate. Sample data lives under `sample.` keys, so
nothing opened there touches the user's own bonds; leaving sample mode
returns every gate to the real entitlement. The Pro flag is never written,
and the Pro screen and Settings show the real, unbought state (buy button,
store price). The banner says "Pro features are open so you can try them
with sample data." and the Pro screen adds "You're in sample mode, so these
features are open to try on the sample data. To use them with your own
bonds, unlock Pro."

The real entitlement lives in one provider (`isProProvider`) plus a second check inside
the check-session controller. Paywall copy (`ProScreen.benefits`) lists
exactly these four things; there is no platform-specific gating, so every
benefit is reachable on both platforms. No timers, no strike-through prices,
no pressure. Prices are always the store's own `ProductDetails.price`.

Tips: `com.froggyeye.bondbell.tip.small` / `.tip.medium` / `.tip.large`
(consumables, £1.99 / £4.99 / £9.99 set in the stores). Restore purchases is
on the Pro screen and in Settings.

### Later (not built)

- Import ranges from an NS&I statement PDF or camera.
- Per-holder stats; CSV export of results.
- Home-screen widget with "next results" countdown.
- Optional monthly auto-check on Wi-Fi (would need background download
  work and a clear consent screen; deliberately out of MVP because the
  brief requires fetching on the user's action).

## Screen map

```
Onboarding (3 pages; independence notice on the last)
 ├─ "Add my bond numbers" → My bonds
 └─ "Try with sample numbers" → Check (sample mode)

Shell: bottom NavigationBar on phones, NavigationRail at ≥720dp width
 ├─ Check (home): next results date · latest draw card · reminder card ·
 │     earlier draws (Pro) · independence notice
 │      ├─ /check/draw/:id  (find → size → download → scan → result)
 │      └─ /result/:id      (stored result)
 ├─ My bonds: holders list (+ add holder, Pro gate after 1)
 │      └─ /holder/:id: ranges list, add/edit range sheet, rename, delete
 ├─ Unclaimed: single-number search · search all bonds (Pro)
 │      ├─ /check/unclaimed-single/:n
 │      └─ /check/unclaimed
 ├─ History (Pro; locked explanation for free)
 └─ Settings: Pro + restore · reminders switch · sample mode switch ·
       tip jar · About · privacy policy · support · NS&I page ·
       delete all my data · independence notice
/pro (paywall) · /about
```

iPad: content is a centred column (max 760dp) with 32dp gutters; stats tiles
go to four across; onboarding pages are vertically centred; rail navigation.
iPhone is portrait-only; iPad supports all orientations.

## Data model (all on device, SharedPreferences JSON)

- `settings.onboarded`, `settings.sampleMode`, `settings.reminders` (bool)
- `purchases.proOwned` (bool; written before the transaction is finished)
- `<scope>.holders`: `[{id, name, ranges: [{id, start, end}]}]`, where scope
  is `real.` or `sample.`
- `<scope>.records`: `{listId: CheckRecord}`; `listId` is `YYYY-MM` for a
  draw, `unclaimed` (all bonds) or `unclaimed-single`. A `CheckRecord` holds
  label, checkedAt (UTC ISO), holdings fingerprint, wins
  `[{bond, prize, holderId, holderName, anonymous?}]`, numbersScanned,
  integrityOk, bondsChecked, singleNumber?.

Only Bondbell's own findings are stored, never NS&I's lists. Android backups
and device-transfer are disabled (`allowBackup=false` plus
`data_extraction_rules.xml` excluding every domain), because the data is
bond numbers. "Delete all my data" clears both scopes.

## Bond number format (measured, not assumed)

Every one of the 9,454,109 numbers in NS&I's Nov 2026 winners file and Oct
2026 unclaimed file matches:

```
[1–3 digit prefix, no leading zero, optional] [2 letters] [6 digits]
```

| Shape | Example | Winners (Nov 2026) | Unclaimed |
|---|---|---|---|
| 3-digit prefix | `688ZY673096` | 6,275,867 | 967,801 |
| 2-digit prefix | `85LV272879` | 272,274 | 1,119,002 |
| 1-digit prefix | `3JA171611` | 24,565 | 713,398 |
| no prefix (oldest) | `DW369715` | 2,469 | 78,733 |

Prefixes seen: 1–692. Letters never include **I, O or U** (23 letters used
in both positions). The app accepts spaces and separators from certificates
(`12 AB 345678`), uppercases input, and explains each failure: holder number
instead of bond number, wrong letter count, I/O/U (with "did you mean 1/0"),
wrong digit count, prefix too long or starting with 0. A range must stay in
one series (prefix + letters) with end ≥ start.

## NS&I data source (inspected 14 Nov 2026)

**Downloads page** `https://www.nsandi.com/get-to-know-us/winning-bonds-downloads`
(96KB HTML, 200 OK with a plain User-Agent; Imperva/Incapsula cookies are set
but no challenge was served). Six `<a href="/files/asset/zip/premium-bonds-
winning-bond-numbers-MM-YYYY.zip">Month YYYY</a>` links (June–November 2026),
one `unclaimed-prizes-june-1957-to-march-2025.zip` link, and an old
September 2024 link **inside an HTML comment** (the parser strips comments).
The app parses `.zip` anchors by href and text, accepts only https
`*.nsandi.com`, and on an empty result shows "the page may have changed"
with an "Open NS&I's page" button.

**Winners ZIP** (Nov 2026): 33,606,244 bytes, `application/zip`,
`Accept-Ranges: bytes`, one entry `PWREP_02112026.txt`, 82,466,828 bytes,
Latin-1 (£ = 0xA3), CRLF. Layout: a heading line `PREMIUM BOND PRIZE DRAW …
November 2026`; a notes line "The amount for distribution is £500,535,100
… a total of 6,575,175 prizes"; a `|`-boxed table of 11 tiers ("IX.
2,381,417 prizes of £100"); then sections headed `Part I - Number(s) drawn
for Prize(s) of £1,000,000` … `Part XI - Numbers drawn for Prizes of £25
each`, each holding 11-character right-aligned numbers, 8 per line, with
`Page No. N` and `Part IX - Prizes of £100 each (contd.)` lines repeated
throughout. Tiers in Nov 2026: £1m ×2, £100k ×96, £50k ×192, £25k ×385, £10k
×962, £5k ×1,922, £1k ×20,020, £500 ×60,060, £100 ×2,381,417, £50 ×2,381,417,
£25 ×1,728,702. The file contains no draw date beyond the month and no
holder data.

**Unclaimed ZIP**: 12,417,443 bytes, one entry `UAREP_05102026.txt`,
35,076,680 bytes, Latin-1, CRLF. Sections `LGS UNCLAIMED £<value>` (the
heading repeats on every page: 8,009 heading lines), values £100,000 down to
£25 including £250, each closed by `END OF £<value>, TOTAL BSN = <count>`,
then `LGS ANONYMOUS £500/£100/£50/£25` sections (prizes whose holder's name
is unknown). Numbers are 12 characters wide, 8 per line. 2,878,934 numbers
in total, which equals NS&I's page figures (2,878,093 unclaimed + 841
anonymous). There is **no draw date per number**, so the app can say which
value is unclaimed but not which month it was won. A bond can appear more
than once (several unclaimed prizes); each is reported.

Both files' totals are checked on every scan (`ScanSummary.integrityOk`).

**Publication schedule.** The six ZIPs carry Last-Modified times of
22:55–23:58 UTC on the first working day of their month (1 Jun, 1 Jul, 3 Aug,
1 Sep, 1 Oct, 2 Nov 2026), and nsandi.com's prize checker said "Next results
available 2 December" (1 Dec 2026 is a Tuesday). Rule implemented: **results
are due the calendar day after the first working day** (England & Wales;
weekends and bank holidays excluded). Bank holidays 2026–2028 are a table
taken from GOV.UK's `bank-holidays.json` (fetched 14 Nov 2026); beyond 2028 a
rule-based fallback (tested to reproduce the 2026–2028 table exactly) is
used, and a dated test fails from 2028 to force the table to be extended.
Not observed directly: a month whose first working day is a Friday (e.g. 1
May 2026); the rule says the following Saturday, which matches the evening
upload pattern.

**Terms.** NS&I's site permits personal use. Bondbell fetches on the user's
device, on the user's tap, from nsandi.com only, with an honest
User-Agent (`Bondbell/1.0.0 (iOS|Android; personal bond checker;
+https://bondbell.froggyeye.com)`). Nothing is mirrored, proxied, cached on a
server or bundled; the download is deleted in a `finally` after every scan
(and the scratch folder is cleared at launch in case the app was killed
mid-check). NS&I files are not in the repo.

## Processing pipeline and measured performance

ZIP on disk → central directory read (`ZipEntryStream`) → raw-deflate
`ZLibDecoder` stream → Latin-1 decoder → `LineSplitter` → per-token structural
check → series-keyed range match (a letter-pair prefilter avoids substring
allocation for almost every token). Runs in a spawned isolate with progress
messages; Cancel kills the isolate. Only matches are kept.

| Run | Download | Scan | Numbers | Integrity |
|---|---|---|---|---|
| Android emulator, **release** build, live Nov 2026 winners (33.6MB) | 8.4 s | 1.08 s | 6,575,175 | ok |
| Android emulator, release, live unclaimed (12.4MB) | 3.3 s | 0.50 s | 2,878,934 | ok |
| Mac, Dart JIT (`tool/scan_bench.dart`), Nov winners | — | 0.69 s | 6,575,175 | ok |
| Mac, Dart JIT, unclaimed | — | 0.30 s | 2,878,934 | ok |

Memory (emulator, release, `dumpsys meminfo` sampled every second through
the Nov check): baseline ~185MB RSS / ~79MB PSS; peak 210MB RSS / 93MB PSS
for about one second during the scan, back to ~189MB RSS afterwards. So the
check costs about 25MB RSS at peak, against an 82MB uncompressed file.
Emulator figures are an indication only; no physical device was measured.

## Permissions

| Platform | Permission | Why |
|---|---|---|
| Android | `INTERNET` | Download NS&I's downloads page and list files when the user checks. |
| Android | `POST_NOTIFICATIONS` (from flutter_local_notifications) | Results-day reminder; asked only when the user turns reminders on. |
| Android | `RECEIVE_BOOT_COMPLETED` | Re-queue the scheduled reminders after a reboot or update (plugin's boot receiver). |
| Android | `VIBRATE` (from flutter_local_notifications) | Default notification behaviour; install-time, no prompt. |
| Android | `com.android.vending.BILLING`, `ACCESS_NETWORK_STATE` (from Play Billing) | In-app purchases. |
| iOS | Notifications (UNUserNotificationCenter, runtime prompt) | Results-day reminder; prompt only on opt-in. |

No usage-description strings are needed or present on iOS: a symbol scan of
the release Runner and every embedded framework found no camera, photos,
location, contacts, calendar, Bluetooth, motion, health, speech, media
library, NFC, AdSupport or ATT references. `ITSAppUsesNonExemptEncryption`
is false (HTTPS only). No exact-alarm permission: reminders use inexact
`AndroidScheduleMode.inexactAllowWhileIdle`.

## Privacy

No accounts, no backend, no analytics, no crash reporting, no ads. The only
network traffic is to nsandi.com (on the user's action) and the app stores
(purchases). Privacy label target: **Data not collected**.
Privacy policy: `https://mksoft-ltd.github.io/bondbell/privacy_policy.html`
(not yet published; see PIPELINE.md). Support/marketing:
`https://bondbell.froggyeye.com` (not yet live). Both live in
`lib/core/constants/app_constants.dart`.

## Developer notes

- `--dart-define=SCREENSHOT_MODE=true` (debug/profile only; compiled out of
  release): skips onboarding, turns on sample mode, unlocks Pro, seeds six
  months of sample history.
- `--dart-define=SCREENSHOT_TOUR=true` (with SCREENSHOT_MODE): walks Home →
  sample check (auto-started) → History → My bonds → Unclaimed → Settings →
  Pro on a timer, for headless `simctl io` capture. The iOS simulator build
  needs xcodebuild with `DART_DEFINES` (base64, comma-separated) because
  `flutter build ios --simulator` fails on this Mac's Xcode 27 lipo.
- `tool/scan_bench.dart <zip> winners|unclaimed series:lo:hi …` benchmarks
  the engine against a locally downloaded NS&I ZIP kept outside the repo.
- `tool/generate_sample_data.py` regenerates the synthetic sample ZIPs.
- `flutter_local_notifications` is pinned at 22.3.1: 23.x requires
  compileSdk 37 and androidx.core 1.19, which needs AGP 9.1 (project is on
  AGP 9.0.1).
