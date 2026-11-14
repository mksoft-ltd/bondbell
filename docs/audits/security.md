# Bondbell: security audit (stage 4b)

Auditor: mobile-security-auditor · 14 Nov 2026 · source at HEAD `c9346e5`

Artifacts inspected:

- Android: `build/app/outputs/bundle/release/app-release.aab` (built 14 Nov
  11:26; no file under `lib/`, `android/app/src`, `pubspec.*` is newer except
  the git-ignored `GeneratedPluginRegistrant.java`). I copied it to a
  scratch directory and inspected the copy. The original is untouched.
- iOS: `flutter build ios --release --no-codesign` run fresh at HEAD
  (`build/ios/iphoneos/Runner.app`, 20.0 MB).

## Threat model

A local-first utility with no backend, no accounts and no first-party
server. The assets worth protecting:

1. The user's bond numbers and holder names. They are financial
   identifiers, but not credentials: NS&I pays a prize only to the registered
   holder.
2. The truth of the store promise, "no data collected; your bond numbers
   never leave your phone".
3. The £4.99 Pro entitlement.
4. The app's robustness against what it downloads: an HTML page, any
   redirects, and a ~34 MB ZIP that inflates to ~82 MB of text.

The realistic adversaries:

- **A hostile or broken response from www.nsandi.com over valid TLS.**
  Possible causes: compromise or misconfiguration on NS&I's side, a CDN or
  bot-protection interstitial, or a device-trusted CA doing interception.
  minSdk 24 means Android does not trust user-installed CAs, so on Android
  this takes MDM or a system CA. iOS honours a user-installed, user-trusted
  root profile.
- **The owner of the device**, who has full control over local state.
- **Another app on the same device.**

There is no adversary with a server to attack, because there is no server.

## Summary

Status is as of the re-verification on 14 Nov 2026, against `5d100a1`
(see "Re-verification" below).

| ID | Severity | Title | Status (14 Nov 2026, 5d100a1) |
|---|---|---|---|
| M-1 | Medium | Downloaded content has no size bound (download, page body, inflated text, line length) | **Verified fixed.** Residual: N-2 (Low) |
| M-2 | Medium | Pro entitlement is a plaintext local bool with no receipt check and no revocation | **Accepted** (house no-backend design; not changed) |
| L-1 | Low | Redirects are followed to any host/scheme; the nsandi.com allowlist only checks the href | **Verified fixed** |
| L-2 | Low | iOS backups include bond numbers and holder names, while the in-app copy says they never leave the device | **Verified fixed** (simulator upgrade test). Residual: N-1 (Low) |
| L-3 | Low | iOS release links `integration_test`; `Generated.xcconfig` was left pointing at the screenshot test | **Partly fixed; residual accepted** |
| L-4 | Low | `debugPrint` survives release; one path can write stored JSON (bond numbers) to the device log | **Verified fixed** |
| L-5 | Low | Local data at rest is unencrypted (sandboxed SharedPreferences) | **Accepted** (data now in the vault file; still sandboxed, unencrypted) |
| L-6 | Low | Dart code is not obfuscated in either release binary | **Accepted** |
| N-1 | Low (new) | `vault.json.bak` / `vault.json.tmp` survive "Delete all my data" | **Verified fixed** at ca1d081 (also covers `vault.json.corrupt-*`) |
| N-2 | Low (new) | The downloads page read has no total deadline (two inter-chunk timeouts) | **Verified fixed** at ca1d081 (60 s page deadline) |
| F-1 | Info (ca1d081) | Sample mode opens Pro features on sample data | Reviewed: no entitlement bypass |
| N-3 | Info (new) | New native backup-exclusion channel and build-guard script: reviewed, no issue | n/a |
| I-1 … I-10 | Informational | Verified controls and context (privacy claim, transport, manifest, signing, debug switches, ZIP parsing, Play pending, dependencies) | Re-checked on fresh artifacts |

No Critical or High findings, before or after the fix round.

---

## Re-verification, 14 Nov 2026 (fix round 2, commit `5d100a1`)

I re-ran my own probes against the real code rather than relying on the
fixer's tests.

- **Probes:** a scratch Flutter package depends on the repo by path,
  calls `NsiDrawSource` through `package:http/testing` `MockClient`
  responses, and calls `scanZipFile` on ZIP bombs generated in the scratch
  area.
- **Simulator:** an iOS simulator build of `5d100a1` was exported with
  `git archive` into scratch and run on a spare, otherwise unused iPhone 17
  Pro (iOS 27.0) simulator, which I then shut down and cleaned.
- **Artifacts:** both freshly built release artifacts were re-inspected
  (copies only).

### M-1: verified fixed

| Probe (production limits unless noted) | Result |
|---|---|
| 400 MB chunked body, no Content-Length | `SourceException: …much larger than expected…` (stopped at the 200 MB cap, file deleted) |
| `Content-Length: 300 MB` | Rejected before the first byte is written |
| 1 byte every 200 ms, deadline set to 2 s via the test seam | `…taking far longer than it should…` after 2005 ms |
| Downloads page body of 5 MB | `…downloads page is far larger than expected…` (2 MB cap) |
| ZIP: 600 MB of `A` with no newline (612 KB compressed) | `ScanLimitException` (line > 4096 chars) in 13 ms, maxRss 190 MB |
| ZIP: 700 MB of 80-char lines, size declared truthfully | `ScanLimitException` (512 MB ceiling) |
| ZIP: 300 MB of lines, declaring 80 MB | `ScanLimitException` at 81 MB (declared + 1 MB slack) in 4.1 s |
| ZIP: 700 MB of lines, declaring 0xFFFFFFFE | `ScanLimitException` (512 MB ceiling); maxRss stayed ~250 MB |

`BoundedLineSplitter` checks the partial line after each decoded chunk,
so a line can exceed 4096 characters by up to one inflate output chunk
before it throws. That is bounded and fine.

The total deadline is checked when a chunk arrives. A stall is still
caught by the 30 s inter-chunk timeout.

### L-1: verified fixed

`_send` sets `followRedirects = false` and re-checks `https` plus
`isNsiHost` on every hop, including the first, before any request is
made. The requested URLs show nothing off-site was ever contacted:

| Redirect `Location` | Result | Hosts requested |
|---|---|---|
| `https://evil.example/x.zip` | `offSite` | only `www.nsandi.com` |
| `http://www.nsandi.com/x.zip` (downgrade) | `offSite` | only the first |
| `https://www.nsandi.com.evil.example/…` | `offSite` | only the first |
| `https://www.nsandi.com@evil.example/…` (userinfo) | `offSite` | only the first |
| `/files/b.zip` (relative) | followed, OK | nsandi.com only |
| `https://cdn.nsandi.com/b.zip` | followed, OK | subdomain allowed, as designed |
| 5 hops on nsandi.com | OK | — |
| 6 hops | error (302) | stops after hop 5 |

`fetchIndex` redirected off-site also gives `offSite`. `sizeOf`
redirected off-site returns `null` without requesting evil.example.

### L-2: verified fixed (simulator upgrade test plus code review)

The upgrade was simulated by installing the `5d100a1` build, writing the
pre-fix format into the app container's
`Library/Preferences/com.froggyeye.bondbell.plist` before the first
launch, then launching:

- `flutter.real.holders`, holding one holder with range
  `999ZZ111111–999ZZ111120`, plus `flutter.settings.onboarded = true`.

Results:

- **Migration worked.** After launch, `Library/Application
  Support/bondbell_private/vault.json` holds `real.holders`, and Home shows
  "10 bonds (£10) across 1 holder".
- **Nothing is left behind in NSUserDefaults.** After the app synced and
  was terminated, the prefs plist contains only
  `flutter.settings.onboarded`.
- **The folder is excluded from backup.**
  `xattr -l bondbell_private` shows
  `com.apple.metadata:com_apple_backup_excludeItem: com.apple.MobileBackup`.
- **The flag survives atomic saves.** It sits on the directory, which is
  never deleted or recreated. Saves write `vault.json.tmp` in the same
  directory and rename it over `vault.json`. Apple excludes a directory's
  contents with it.
- **The vault-level `.bak` stays inside the excluded folder.** I corrupted
  `vault.json` and relaunched: `vault.json.bak` was written inside
  `bondbell_private`.
- **The tolerant parser's copies are vault keys, not files.**
  `holders_controller.dart:87` writes `real.holders.bak` /
  `sample.holders.bak` as keys, so they go into the vault and are removed
  by "Delete all my data". The vault-level file is not (N-1).
- **Android:** the fresh AAB's merged manifest still has
  `allowBackup="false"`, `fullBackupContent="false"` and
  `dataExtractionRules` (rules file unchanged). Exported components and
  permissions are identical to the first audit.

One residual that no code can fix: iCloud or computer backups taken
**before** the update still contain the old NSUserDefaults copy until
those backups roll over.

**Conclusion:** "your numbers never leave your phone/iPad" is now
literally true for current data on both platforms.

### L-3: partly fixed, residual accepted

`integration_test.framework` is still linked in the iOS release. It is
dead code, as before: `strings App | grep -c IntegrationTest` gives 0, and
there is no XCTest linkage.

`ios/scripts/release_guard.sh` runs first in Runner's Run Script phase and
does its job. Exercised directly:

| Configuration, target, defines | Exit |
|---|---|
| Release, `lib/main.dart` (relative or absolute), no defines | 0 |
| Release, empty target | 0 |
| Release, `integration_test/screenshots_test.dart` | **1** |
| Release with `SCREENSHOT_MODE`, `SCREENSHOT_TOUR` or `HOST_CAPTURE` | **1** |
| Debug / Profile with any of those | 0 (by design) |

The script only reads environment variables and echoes them. There is no
injection surface. This turns a bare Xcode Archive after a capture from a
silent bad build into a failed build, which is the right control.

**Accepted:** dead `integration_test` code in the binary is Low and is
Flutter 3.44 tooling behaviour.

### L-4: verified fixed

- `LocalStore.readJson` now logs `Corrupt value at $key
  (${e.runtimeType})` through `appLog`, which is a no-op when
  `kReleaseMode`.
- Every other diagnostic moved to `appLog`.
- The only remaining `debugPrint` is the timing line
  (`check_session.dart:351`): list id, timings, counts and maxRss. It
  contains no bond numbers or names.
- The literal "Corrupt value" survives in both binaries as a constant, but
  it is never printed in release.

### N-1 (new, Low): `vault.json.bak` and `vault.json.tmp` survive "Delete all my data"

> **14 Nov 2026 (ca1d081): verified fixed.** See "Final re-check".

**Affected:** `local_store.dart` (`DataVault.open`, `_flush`),
`settings_screen.dart:146-176`.

**What is wrong.**

- `DataVault.open` copies an unreadable vault to `vault.json.bak`.
- A crash between write and rename can leave `vault.json.tmp`.
- `_deleteAll` → `clearPrefix` → `DataVault.removeWhere` rewrites only
  `vault.json`.

So after a corruption event, the old bond numbers and holder names stay
in `vault.json.bak` indefinitely, even after the user picks "Delete
everything", whose dialog says "This removes every holder, bond
number…".

Both files are inside the backup-excluded folder, so nothing leaves the
device. This is a delete-claim accuracy issue on a rare path, not a leak.

**Fix:** in `clearPrefix` (or a `DataVault.wipe()` called from
`_deleteAll`), also delete `vault.json.bak` and `vault.json.tmp` when
the vault becomes empty of `real.`/`sample.` keys. Add a test that
creates both files and asserts they are gone after Delete all.

### N-2 (new, Low): the downloads page read has no total deadline

> **14 Nov 2026 (ca1d081): verified fixed.** See "Final re-check".

**Affected:** `draw_source.dart` (`fetchIndex`):
`r.stream.timeout(_timeout).timeout(_timeout * 2)`.

Both calls are `Stream.timeout`, which is inter-chunk, so the second adds
nothing. The read is size-capped at 2 MB, so memory is bounded. But a
server trickling one byte every 29 s would keep the "finding NS&I's list"
state alive for a very long time.

The user can leave the screen, because the generation counter discards the
late result. The impact is a stuck spinner only.

**Fix:** put a total deadline on the page read, using the same
`deadline`/`Stopwatch` pattern as `download`, or wrap the whole `fetchIndex`
body in `Future.timeout(...)`. Delete the redundant second `.timeout`.

### N-3 (new, Informational): new attack surface reviewed

- **Native channel `com.froggyeye.bondbell/backup`**
  (`AppDelegate.swift`). It handles only `excludeFromBackup`, taking a
  String path. It can only *set* the exclude flag, which can only reduce
  backups, and only Dart in-process can call it.
  - `main.dart` calls it before the vault is opened, so on a normal launch
    nothing is written before the flag is set. If it returns `false`
    (engine not ready) it retries once after the first frame, and again on
    every launch.
  - In the test above the flag was present after the first launch.
- **Vault file.** It is plain JSON in the app sandbox (L-5 applies).
  Writes are serialised and atomic. A corrupt file is preserved and does
  not crash the app (verified on the simulator).
  - Migration copies the data before deleting the prefs keys, and only
    deletes once `vault.json` exists, so an interrupted upgrade cannot
    lose data.
- **Release guard script.** See L-3: environment input only, fails closed
  on Release.
- **Fresh artifacts** (AAB 17:30, iOS `Runner.app`; no source under
  `lib/`, `android/app/src` or `ios/Runner` is newer than either). These
  are unchanged from the first audit:
  - Dart URL list: nsandi.com ×3, privacy, support.
  - `seedScreenshotData`, `_runTour`, `SCREENSHOT` and `312KM104217`
    count 0 in both binaries.
  - AAB upload certificate SHA-1 is `6F:08:DF:…:C5`.
  - iOS `Info.plist` has no ATS exceptions or usage strings, and the same
    5 privacy manifests.
  - The new `BoundedLineSplitter` and `bondbell_private` symbols are
    present in both binaries, and the channel name is in the iOS `Runner`.

---

## Critical

None.

## High

None.

I specifically checked the one entitlement defect I would rate High for this
portfolio: granting Pro on an Android `restored` event that is really a
PENDING Play purchase. It is **correctly handled** (see I-8).

---

## Medium

### M-1: Downloaded content has no size bound

> **14 Nov 2026 (5d100a1): verified fixed.** See Re-verification; residual N-2.


**Affected:** `lib/features/draws/data/draw_source.dart:171-256`
(`NsiDrawSource.download`), `:101-140` (`fetchIndex`),
`lib/features/draws/engine/scan_worker.dart:23-36`,
`lib/features/draws/engine/zip_entry_stream.dart:79-90`.

**What is wrong.**

- **The download has no byte cap.** The loop at `draw_source.dart:205-220`
  writes every chunk to disk. The only size check (`:230`) compares
  `received` against the server's own `Content-Length`. A chunked response,
  or one with no length, is accepted at any size.
- **There is no total deadline.** `r.stream.timeout(_timeout)` (`:205`) is
  an inter-chunk timeout, so a server that keeps trickling bytes never trips
  it. The user can still cancel, which mitigates this.
- **The downloads page is read whole into memory** (`c.get(page)`, `:105`),
  with only a 30 s total deadline. That is a lot of bytes on a fast link.
- **Inflation is unbounded.** The scan pipes raw inflate output into
  `latin1.decoder` and then `LineSplitter`. Neither the entry's declared
  `uncompressedSize` nor any ceiling is enforced. `LineSplitter` buffers a
  partial line until it sees a newline. Deflate reaches roughly 1000:1, so
  a ~34 MB payload of one newline-free line asks the scan isolate for a
  multi-gigabyte string. The isolate shares the app's heap, so this is an
  out-of-memory kill of the whole app, not a caught error.

**Evidence (executed, not argued).** I put a throwaway test in a scratch
package that depends on `bondbell` by path, so nothing was written to the
repo. It calls the real `NsiDrawSource.download` against a local
`HttpServer` that sends `PK` followed by 400 × 1 MB, chunked, with
`content-type: application/zip`:

```
ACCEPTED bytes=419430402 in 1360ms (expected list ~34MB)
```

That is 12.3× the real file, and nothing would have stopped it at 4 GB. On
a full disk, the `IOSink` error lands in the `on Object` branch, which
deletes the partial file (`:239`). The damage is therefore transient, not
persistent.

**Attack or failure scenario.** An interception CA on iOS, or a bad day
at NS&I's CDN, serves an endless or oversized body. The phone's free space
fills until the write fails, or a crafted ZIP gets the app killed on every
check. No data is exposed. The harm is denial of service of the app's core
feature and temporary storage pressure.

**Why Medium and not High.** The attacker needs a TLS-valid response for
`www.nsandi.com`. The impact is availability only, and it recovers on its
own. The fix is small, and the conductor named this exact surface.

**Recommended fix.**

```dart
// draw_source.dart
static const int _maxDownloadBytes = 200 * 1024 * 1024; // real file ~34 MB
static const Duration _totalDeadline = Duration(minutes: 10);
...
final int? total = r.contentLength;
if (total != null && total > _maxDownloadBytes) {
  throw const SourceException('NS&I\'s file is much larger than expected. '
      'Please check on NS&I\'s site instead.', layoutChanged: true);
}
final Stopwatch clock = Stopwatch()..start();
await for (final List<int> chunk in r.stream.timeout(_timeout)) {
  ...
  received += chunk.length;
  if (received > _maxDownloadBytes || clock.elapsed > _totalDeadline) {
    throw const SourceException('NS&I\'s file is much larger than expected. '
        'Please check on NS&I\'s site instead.', layoutChanged: true);
  }
  ...
}
```

- **Page body:** stream it with `c.send()` and stop at 2 MB. The real page
  is tens of KB.
- **Inflated stream:** count the decompressed bytes and stop past
  `max(uncompressedSize, 0) + slack`, or past a hard ceiling such as
  512 MB. Also reject a decoded line longer than ~4 KB. NS&I's data lines
  are 8 × 11-character tokens, so a small cap is safe. Wrap the
  `LineSplitter` output in a guard, or count bytes in the `.map` at
  `zip_entry_stream.dart:83`.
- **Tests:** assert a bound the code actually guarantees. For example,
  accepted bytes stay far below the 400 MB offered (say, under
  `_maxDownloadBytes + 8 MB`). Do not assert "cap plus 64 KB": a stream
  chunk is one socket read, so the overshoot scales with the peer's write
  size.

### M-2: Pro entitlement is a plaintext local bool with no receipt check and no revocation

> **14 Nov 2026 (5d100a1): accepted.** House no-backend design; unchanged.


**Affected:** `lib/features/purchases/presentation/purchase_controller.dart:78, 117, 230-237`.

**What is wrong.**

- Pro is `purchases.proOwned` in SharedPreferences. That is
  `shared_prefs/FlutterSharedPreferences.xml` on Android and the app's
  `NSUserDefaults` plist on iOS.
- It is granted on any `purchased` or `restored` event for the Pro product
  ID. The app never checks `verificationData`.
- Nothing ever sets it back to false: the silent Android restore is
  documented as "Grant-only: never revokes Pro" (`:126`). So a refunded Pro
  stays unlocked.

This is the deliberate house design (no backend, therefore nowhere to verify
a receipt).

**Attack scenario.** Someone with a rooted or jailbroken device, or an
unencrypted iOS backup they restore after editing, sets
`flutter.purchases.proOwned=true` and gets Pro free. Separately, a buyer
who obtains a refund keeps Pro.

**Why Medium.** The blast radius is one £4.99 unlock on a device the
attacker already owns. No credential, PII or backend is exposed. This is
the same ranking as every other local-IAP app in the portfolio.

**Recommended fix (hardening, not a gate item).**

- Carry `verificationData` through `StoreGateway`.
- On cold start, re-query the store and downgrade only when the store gives
  a trustworthy negative. On Android, a successful `queryPurchases` that
  does not list a non-consumable means it is not owned. Silence or an error
  must never revoke. Name that trade-off in the code comment.
- Optionally, add a Keystore- or Keychain-backed HMAC over the flag.

---

## Low

### L-1: Redirects are followed to any host or scheme; the nsandi.com allowlist only checks the href

> **14 Nov 2026 (5d100a1): verified fixed.** Every hop is re-checked.


**Affected:** `lib/features/draws/data/nsi_index.dart:60`,
`lib/features/draws/data/draw_source.dart:184-186`.

**What is wrong.** `NsiIndexParser` admits a link only if it is `https` and
on `nsandi.com` or a subdomain. That check is good, and look-alike hosts are
rejected. But `package:http` follows redirects by default (up to 5), and
`download()` never looks at where it ended up.

**Evidence.** In the same scratch test, a 302 from the first server to
`http://localhost:<other>/elsewhere.zip` was followed and the second
server's body was accepted:

```
REDIRECT followed to localhost:61006, bytes=5
```

**Scenario.** An open redirect on nsandi.com, or an NS&I-side
misconfiguration, sends the ZIP download to a third-party host. That host
then supplies the list the user's bonds are checked against, which could
show fake wins or hide real ones. It also gets the user's IP address and
user agent.

- The redirect response itself is protected by TLS. A network attacker
  cannot inject it.
- An `https` → `http` hop is blocked on Android, because target SDK 36
  disables cleartext and dart:io applies Android's cleartext policy.
- On iOS, dart:io sockets are not governed by ATS, so I would not count on
  that hop being refused there. I did not exercise this on a device.

**Fix.** After `send()`, check the final URL:

```dart
final Uri finalUrl = r is http.BaseResponseWithUrl ? r.url : list.url;
if (finalUrl.scheme != 'https' || !NsiIndexParser.isNsiHost(finalUrl.host)) {
  throw const SourceException(webPageInsteadOfFile, layoutChanged: true);
}
```

Alternatively, set `followRedirects = false` and re-validate each hop
yourself. Apply the same check to `fetchIndex` and `sizeOf`.

### L-2: iOS backups include bond numbers and holder names, while the in-app copy says they never leave the device

> **14 Nov 2026 (5d100a1): verified fixed.** Simulator upgrade test; residual N-1.


**Affected:** `lib/core/storage/local_store.dart` (SharedPreferences, which
is `NSUserDefaults` on iOS), copy at
`lib/features/draws/presentation/check_screen.dart:150-153` and
`lib/features/onboarding/onboarding_screen.dart:34`.

**What is wrong.**

- **Android excludes this data from backup, deliberately.** The merged
  manifest in the AAB has `allowBackup="false"`, `fullBackupContent="false"`
  and `data_extraction_rules` excluding every domain. `PRODUCT_SPEC.md:138`
  gives the reason: "because the data is bond numbers".
- **iOS has no equivalent.** `Library/Preferences/<bundle>.plist` is
  included in iCloud Backup and in Finder/iTunes backups by default.
- **The in-app copy says otherwise.** The app tells the user "Your numbers
  never leave your iPhone".
- **The privacy policy is already accurate.** `PRIVACY_POLICY.md:34-36`
  says iOS app data can be in the user's own backup.

**Scenario.** There is no attacker gain beyond what any iCloud account
compromise already yields. The issue is that the app's headline claim is
literally untrue on iOS for most users, who have iCloud Backup on. The two
platforms also treat the same data differently.

This does not affect the privacy nutrition label. A backup to the user's
own iCloud is not developer collection.

**Fix (pick one).**

1. **Preferred:** move `real.holders` and `real.records` into a JSON file
   under Application Support, with `NSURLIsExcludedFromBackupKey`. That
   needs a small method channel, or keep shared_preferences only for
   non-sensitive flags. This matches Android.
2. Keep the current storage and soften the copy, for example: "Your
   numbers are never sent anywhere by Bondbell". Then tell the metadata
   stage that the listing must not say "never leave your phone".

### L-3: iOS release links `integration_test`; `Generated.xcconfig` was left pointing at the screenshot test

> **14 Nov 2026 (5d100a1): partly fixed, residual accepted.** The release guard fails a bad Release build; the dead framework remains.


**Evidence (fresh iOS release).**

- `ls Runner.app/Frameworks` includes `integration_test.framework`.
- `strings Runner | grep -c IntegrationTestPlugin` gives `1`.
- `nm -u integration_test | grep -c XCT` gives `0`, so there is no XCTest
  linkage.
- `strings App.framework/App | grep -c IntegrationTest` gives `0`.

So this is dead code: a registered plugin with an in-process channel and no
Dart caller in the release `App`.

**Also, at audit start**, `ios/Flutter/Generated.xcconfig` held
`FLUTTER_TARGET=integration_test/screenshots_test.dart`. Its base64
`DART_DEFINES` decoded to `SCREENSHOT_MODE=true` and `HOST_CAPTURE=true`.
My `flutter build ios` regenerated it to `lib/main.dart` with no app
defines. An Xcode Archive does **not** regenerate this file. So archiving
right after a screenshot capture would ship the integration-test harness as
the app's entry point. Pro would stay locked even then, because
`!kReleaseMode` compiles the unlock out (I-6). The real risk is shipping a
broken app.

**Fix.**

- Stage 7 builds with `flutter build ipa` (or `flutter build ios`
  immediately before archiving), never a bare Xcode Archive after a
  capture.
- Optionally, remove `integration_test` from the iOS release registrant.
  Do not hand-edit `GeneratedPluginRegistrant.m`.

### L-4: `debugPrint` survives release; one path can write stored JSON (bond numbers) to the device log

> **14 Nov 2026 (5d100a1): verified fixed.**


**Affected:** `lib/core/storage/local_store.dart:27`.

**What is wrong.** `debugPrint` is not compiled out of release builds. It
writes to logcat on Android and to the unified log on iOS. Most of the
app's calls log only exception text with no user data. The timing line at
`check_session.dart:282` is deliberately free of bond numbers.

The exception is `debugPrint('Corrupt value at $key: $e')` on a
`FormatException` from `jsonDecode`. That exception's `toString()` includes
the offending source text, which here is the holders or records JSON:
bond numbers and holder names. It fires only on a corrupt value.

**Scenario.** Someone with ADB or Console.app access to an unlocked device
reads bond numbers from the log. That is low value and needs the device.

**Fix.**

- Log only the key and `e.message`/offset: `debugPrint('Corrupt value at
  $key')`.
- Optionally, route all logging through a helper that is a no-op when
  `kReleaseMode`.

### L-5: Local data at rest is unencrypted (sandboxed SharedPreferences)

> **14 Nov 2026 (5d100a1): accepted.** The data now lives in the sandboxed vault file.


Holders, ranges, names and win records are plain JSON strings inside the
app sandbox. On Android, the sandbox plus backup exclusion protects them.
On iOS, the sandbox plus the default Data Protection class (encrypted until
first unlock) protects them.

Bond numbers cannot be used to claim prizes, so a Keychain- or
Keystore-backed encryption layer would cost more than it protects. Accept
this. Revisit it only if the app ever stores NS&I account details. It must
not.

### L-6: Dart code is not obfuscated in either release binary

> **14 Nov 2026 (5d100a1): accepted.**


`strings libapp.so` (arm64) and `strings App.framework/App` show class names
such as `NsiIndexParser`, `PurchaseController` and `bondbell-scan`. The
builds did not use `--obfuscate --split-debug-info`.

Nothing secret is in the code: no keys and no endpoints beyond public URLs.
Obfuscation would only slow down an attacker patching the Pro check, which
M-2 already concedes. This is optional. If adopted, keep the symbol
directory for crash triage.

---

## Informational

### I-1: The privacy claim, checked in the shipped binaries

**Network endpoints in the Dart code of both binaries.** I extracted them
with `strings … | grep -oE 'https?://…'` and excluded flutter.dev,
github.com/flutter and pub.dev. Only these remain:

- `https://www.nsandi.com/get-to-know-us/winning-bonds-downloads`
- `…/prize-checker`
- `…/contact-us`
- `https://mksoft-ltd.github.io/bondbell/privacy_policy.html`
- `https://bondbell.froggyeye.com`

Only the first is fetched in-app. The rest open in the external browser.

**What a request carries.** A request to NS&I carries only the user agent
`Bondbell/1.0.0 (<iOS|Android>; personal bond checker; +https://bondbell.froggyeye.com)`.
It carries no identifiers, cookies or bond numbers. Matching happens in a
local isolate, and only matches are stored. The unclaimed single-number
search also runs locally: the number goes only into a route path, never
into a URL sent off the device.

**Third-party SDKs.**

- No analytics, ads or crash SDKs on either platform.
- iOS privacy manifests: none declares collected data, and all set
  `NSPrivacyTracking=false`. Flutter declares FileTimestamp and
  SystemBootTime. shared_preferences and flutter_local_notifications
  declare UserDefaults.
- Android: the dex carries Play Billing's `datatransport`/Firelog client
  (interleaved endpoint fragments present, 3 hits). This is Google Play's
  own billing telemetry. It carries no app data, and Play's purchase
  carve-out covers it. "No data collected" holds on both stores.
- Corollary: no store text may claim the app never contacts anything but
  NS&I. The draft privacy policy already says the store is contacted at
  launch (`PRIVACY_POLICY.md:67-68`).

**Backups.** Android backup is off in the merged manifest, verified from
the AAB. iOS backup is on (L-2).

**Verdict on the claim.** "Your bond numbers never leave your phone" holds
in the artifacts with respect to anything Bondbell sends. Bond numbers are
never transmitted. The only literal exception is the user's own iOS device
backup (L-2).

### I-2: Transport configuration

- **iOS:** the built `Info.plist` has no `NSAppTransportSecurity` key, so
  ATS runs at its defaults with no exceptions.
- **Android:** `targetSdkVersion 36` with no `networkSecurityConfig` and no
  `usesCleartextTraffic`, so cleartext is denied.
- Every URL in the app is `https`.
- Certificate pinning is absent, and that is appropriate. The content is
  public, the user can verify every result against NS&I, and NS&I can
  rotate certificates at any time, so a pin would break the app.

### I-3: Android manifest (merged, from the AAB via `bundletool dump manifest`)

**Exported components:**

- `MainActivity`: launcher only, with no VIEW or deep-link filters.
- `androidx.profileinstaller.ProfileInstallReceiver`: guarded by
  `android.permission.DUMP`.

Every other component is `exported="false"`: the notification receivers,
the billing proxy activities, url_launcher's `WebViewActivity` and the
datatransport services.

**Permissions merged:** `INTERNET`, `ACCESS_NETWORK_STATE`,
`RECEIVE_BOOT_COMPLETED`, `VIBRATE`, `POST_NOTIFICATIONS`,
`com.android.vending.BILLING`, and the signature-level
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. There is no exact-alarm, storage
or location permission.

**Explicit intents.** An explicit intent with a data URI aimed at the
exported `MainActivity` could hand go_router a route, because Flutter deep
linking is on by default. The worst case is opening a check screen. That
fetches NS&I's index, but a download still needs a tap. Pro gates are
enforced in logic (`check_session.dart` `_gate`), and nothing is returned
to the caller. No action is needed. Set
`flutter_deeplinking_enabled=false` in the manifest if you want to close
it.

### I-4: iOS Info.plist and entitlements

- No usage-description strings and no background modes.
- No URL schemes and no `LSApplicationQueriesSchemes`.
- No file sharing or `LSSupportsOpeningDocumentsInPlace`.
- `ITSAppUsesNonExemptEncryption=false`. This is correct, because the app
  uses only OS-provided TLS.
- There is no entitlements file in `ios/Runner`, and the build adds none.
  In-App Purchase needs no entitlement.

### I-5: Secrets and signing

- `git grep` for passwords, API-key patterns and PEM headers over tracked
  files returns only a comment.
- `key.properties` and `*.jks` are ignored and untracked.
- The AAB upload certificate is `CN=Froggy Eye Ltd`, SHA-1
  `6F:08:DF:5E:7F:C9:44:35:A6:9C:0B:95:35:7D:12:2C:81:F6:98:C5`, which
  matches PIPELINE.md.
- The AAB's `BUNDLE-METADATA` holds native debug symbols and the R8
  mapping. That is normal: Play keeps them server-side and does not ship
  them to devices.
- The only assets packaged are the two synthetic sample ZIPs, fonts and
  shaders.

### I-6: Debug and screenshot switches

- `SCREENSHOT_MODE` and `SCREENSHOT_TOUR` are `bool.fromEnvironment(...) &&
  !kReleaseMode` (`lib/app/debug_flags.dart`).
- `test/screenshot_seed_test.dart` asserts the guard from the source text.
  That is the right kind of test, because a runtime test only ever sees
  debug mode.
- In both release binaries, `seedScreenshotData`, `_runTour`, `SCREENSHOT`
  and the seeded bond `312KM104217` all count 0 in `strings`.
- `forceProProvider` remains but is constant `false`.
- The docs give only debug or profile capture commands.

### I-7: ZIP handling

- Entries are never extracted to disk; the content is inflated into memory
  only, so there is no zip-slip.
- The EOCD, central-directory and local-header signatures are checked.
- ZIP64 is refused.
- Only methods 0 and 8 are accepted.
- `dataOffset + compSize` is bounded by the file length.
- `int.parse` overflow on a hostile number becomes a caught scan failure.
- The `PK` magic check now holds back sub-2-byte first chunks.
- Every exit path deletes the download, and `clearScratch()` sweeps only
  `tmp/bondbell_lists`.

The remaining gap is the size bounds in M-1.

The integrity check (counts against NS&I's printed totals) catches format
drift but not a self-consistent forged list. That is acceptable: every
result tells the user to confirm with NS&I.

### I-8: Play PENDING purchases are handled correctly; keep it that way

`purchase_controller.dart:226` checks
`GooglePlayPurchaseDetails.billingClientPurchase.purchaseState ==
PurchaseStateWrapper.pending` before granting on **both** `purchased` and
`restored`. This matters because `in_app_purchase_android` rewrites every
restored item's status to `restored`. It also enables PENDING one-time
products. Without this check, a cash or bank-transfer buyer would get Pro
before paying.

Pro is persisted before the transaction is completed, and tips grant
nothing and are always consumed. Do not "simplify" any of this.

### I-9: Dependencies

- No git or path dependencies in `pubspec.lock`, and no git pods in
  `Podfile.lock`.
- `flutter_local_notifications` is pinned at 22.3.1, one major behind,
  with the AGP and compileSdk rationale given in pubspec. I am not aware of
  any security advisory for it.
- The other direct dependencies (`http` 1.6, `url_launcher` 6.3,
  `in_app_purchase` 3.3, `shared_preferences` 2.5) are current.

### I-10: Notifications

Reminder text is generic ("New prize results are due… Open Bondbell to
check your bonds."). It contains no bond numbers, holder names or win
amounts, so nothing sensitive appears on the lock screen.

---

## Final re-check, 14 Nov 2026 (HEAD `ca1d081`; commits `3623a80` and `ca1d081`)

This round used the same method as before: a scratch probe package that
calls the real code, ZIP inputs generated in the scratch area, and copies
of the fresh artifacts. Nothing in the repo was written apart from this
file and `PIPELINE.md`.

### N-1: verified fixed

`LocalStore.deleteAllPrivateData` clears `real.` and `sample.` from both
SharedPreferences and the vault. It then calls `DataVault.deleteLeftovers`,
which removes every `vault.json.*` side file once the vault holds no
private keys.

Probe sequence on a real `DataVault` with a real `LocalStore`:

| Step | Folder contents |
|---|---|
| Write holders (real and sample), then relaunch | `vault.json`, `vault.json.bak` (the last good copy is refreshed at each clean launch) |
| Corrupt `vault.json`, then relaunch | `status=recovered`; `vault.json`, `vault.json.bak`, `vault.json.corrupt-<millis>`; holders restored from `.bak` |
| Plant a `vault.json.tmp` holding a bond number, then **Delete all my data** | `ok=true`; only `vault.json` remains, holding `{}`; prefs keep only `settings.onboarded` |
| Any file in the folder still containing `999ZZ` | **none** |

**Side files stay in the excluded folder.** Every side file is created as
`${vault.json path}.<suffix>` in the same `bondbell_private` directory,
which carries the iOS backup-exclusion attribute (verified on the
simulator in the previous round). Android excludes all app data. So
`.bak`, `.corrupt-*` and `.tmp` never reach a backup.

The one open window: between a normal edit and the next launch, `.bak`
still holds the previous state. That is inside the excluded folder, and
Delete all removes it. Accepted.

### N-2: verified fixed

`fetchIndex` now has a 60 s whole-read deadline (`pageDeadline`) on top
of the 30 s stall timeout and the 2 MB cap. Probe: a page trickling one
byte every 200 ms, with the deadline set to 2 s through the test seam,
fails with "took too long" after 2007 ms.

The overall ZIP download deadline was raised from 10 to 30 minutes (review
N4). The 200 MB cap and the 30 s stall timeout are unchanged, so this does
not weaken M-1.

### Rewritten line splitter: the 4 KB bound still holds

`BoundedLineSplitter` is now a synchronous guard in front of
`LineSplitter`. It throws when the run of characters with no line break
exceeds 4096, either across chunk boundaries or inside a chunk's first or
last segment.

Lines entirely between two breaks in one chunk are not measured. They are
bounded by the chunk size, which I measured at **65,536 bytes**, the
maximum inflate output chunk. `LineSplitter` emits them at once without
buffering, so memory stays bounded.

| Input | Result |
|---|---|
| 600 MB of `A` with no newline (`longline.zip`) | `ScanLimitException` in 18 ms |
| 2,000 lines of 50,000 chars each | `ScanLimitException` in 8 ms (the first line is caught) |
| A 5,000-char line ending in CRLF | `ScanLimitException` |

The declared-size and 512 MB inflate caps are unchanged from the previous
round.

### F-1 (ca1d081): sample mode opens Pro features. No entitlement bypass beyond M-2

`proFeaturesProvider = isPro || sampleMode` now drives every feature gate:

- `addHolder`
- `addHolderFlow`
- Home's earlier draws
- the bulk unclaimed search
- History
- `CheckSessionController._gate`

I checked whether this can be turned into Pro on the user's own data:

- **The data scope and the draw source both derive from sample mode.**
  `dataScopeProvider` (`sample.` vs `real.`) and `drawSourceProvider`
  (`SampleDrawSource` vs `NsiDrawSource`) are both computed from
  `sampleModeProvider`. In sample mode the app reads and writes only
  `sample.*` holders and records, and checks only against the bundled
  synthetic lists. `SampleDrawSource` never touches the network. A user
  can type their real bond numbers into the sample holders, but they can
  only be checked against made-up lists, so this gives none of what Pro
  sells: checking real NS&I draws, history of real results, and more than
  one real holder.
- **No path copies data between scopes.** `grep` finds no code that copies
  `sample.*` into `real.*`, and no import or export feature.
- **Leaving sample mode restores the real gates.** Each mode change
  (Settings toggle, banner Exit) first calls
  `checkSessionProvider.notifier.reset()`. That bumps the generation and
  clears the prepared list, so a check prepared and gated in sample mode
  cannot be started afterwards in real mode.
  - Home's "Try sample mode" only turns sample mode *on*, which is not the
    risky direction. Onboarding sets it before any session exists.
  - Even with no reset, a sample `RemoteList` carries an `asset:///` URL.
    `NsiDrawSource._send` refuses any non-https, non-nsandi.com URL, so a
    stale sample list cannot become a real download.
- **The Pro flag is never written by sample mode.** `isProProvider`
  (the stored entitlement) still drives the Pro screen and Settings, and
  `purchases.proOwned` is written only by the purchase path.
- **In real mode** (`sampleMode=false`), `proFeaturesProvider ==
  isProProvider`. So deep links to `/check/draw/<earlier>`, `/history` or
  the bulk unclaimed check stay gated, exactly as before.

The only way to "unlock" sample mode on real data is to change the stored
flags themselves, which is M-2 (already accepted).

### Release artifacts (fresh: AAB 18:02, iOS `App` 18:03)

Copies were inspected; the originals are untouched.

- **Network endpoints** (Dart `strings`, both binaries): unchanged.
  `nsandi.com` ×3 (downloads page, prize checker, contact), the privacy
  policy and the support site.
- **Screenshot and debug switches:** `seedScreenshotData`, `_runTour`,
  `SCREENSHOT`, `HOST_CAPTURE` and `312KM104217` all count **0** in both
  binaries. `ios/Flutter/Generated.xcconfig` is `FLUTTER_TARGET=lib/main.dart`
  with no app defines.
- **The new code is present in both binaries:** `Grandad (sample)`, the
  sample-mode Pro note and `deleteLeftovers`. All four sample ZIPs are
  bundled.
- **AAB merged manifest:** `allowBackup="false"`,
  `fullBackupContent="false"`, `dataExtractionRules` present. Permissions
  and exported components are identical to the first audit. The upload
  certificate SHA-1 is still `6F:08:DF:…:C5`.
- **Native code and dependencies:** no change since `5d100a1` in
  `android/app`, `ios/Runner`, `ios/scripts`, the Xcode project or
  `pubspec.*`.
- **Freshness caveat:** `lib/features/home/home_screen.dart` is being
  edited after both builds (18:02 and 18:03). At the end of this audit it
  carried an **uncommitted** change adding a "Try with sample numbers"
  card to Home. That card resets the check session and then turns sample
  mode on, the same safe pattern as the other toggles. It adds no new
  gate and has no security effect. The release builds that come next must
  be made from the final committed tree, not these artifacts.

## Remaining work (after the final re-check, 14 Nov 2026, HEAD ca1d081)

There are no gate blockers. No security finding is open, apart from the
accepted M-2, L-3 residual, L-5 and L-6.

For the publish stage:

1. Make the release builds from HEAD `ca1d081`. The current artifacts may
   predate the last `home_screen.dart` edit.
2. Build the iOS archive with `flutter build ipa`. The release guard fails
   a stale Xcode Archive.

Verdict: PASS
