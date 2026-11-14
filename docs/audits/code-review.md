# Bondbell: code review (stage 4a)

Reviewer: mobile-code-reviewer · 2026-11-14 · HEAD `c9346e5` (whole codebase,
native config included: `android/app/build.gradle.kts`, `proguard-rules.pro`,
`res/raw/keep.xml`, `AndroidManifest.xml`, `data_extraction_rules.xml`,
`ios/Runner/{AppDelegate,SceneDelegate}.swift`, `Info.plist`, `Podfile`).

## Re-verification, fix round 2 (14 Nov 2026, commit `5d100a1`)

I checked each fix against its original failure scenario myself; I did not
rely on the fixer's notes. I also reviewed the diff from `c9346e5` as new
code. Probe tests ran in an isolated copy of `5d100a1` in my scratchpad, not
in the repo, and were thrown away afterwards.

- `flutter analyze`: no issues. `flutter test`: **327 passed**.
- **Scan engine, which now uses a new `BoundedLineSplitter`.** I re-ran the
  real-file comparison against my separate Python scanner: Nov 2026 winners
  **66/66 identical** and unclaimed **180/180 identical**, plus the 8
  anonymous and duplicate-bond probes. Integrity ok on both. I also
  fuzz-tested `BoundedLineSplitter` against `dart:convert`'s `LineSplitter`:
  20,000 random texts mixing `\r\n`, `\n`, `\r`, `\r\r` and blank lines, cut
  at random points including `\r|\n` splits and empty chunks. The output
  matched every time.
- **m3 month check on more months.** I downloaded NS&I's **June 2026** and
  **October 2026** winners files as well. The heading parses to "June 2026"
  and "October 2026" and integrity is ok, so the new hard refusal does not
  fire on genuine files. That makes three of the six months currently listed.
- **Vault and migration probes** (`DataVault` / `LocalStore.withVault`
  against a temp directory and mock prefs):
  - An upgrade moves the `real.`/`sample.` keys into the vault, deletes them
    from prefs, keeps `settings.*` and `purchases.proOwned`, and survives a
    re-open.
  - First launch with no data writes nothing and returns null.
  - If the write fails during migration (directory made read-only), **the
    prefs copy is kept**.
  - 200 unawaited writes leave the last value on disk, so writes stay in
    order.
  - A corrupt vault is copied to `vault.json.bak` and the vault starts
    empty.
  - A failed write after migration is silent. See new finding N1.
  - No private key is ever stored as a non-string, so `migrateFrom`'s
    `getString` cannot throw at launch. I grepped every `setBool`,
    `setString` and `writeJson` call to confirm this.
- **Native.** `flutter build ios --release --no-codesign` on the copy
  succeeded. The new Run Script guard passed with
  `FLUTTER_TARGET=lib/main.dart`, and
  `strings Runner | grep com.froggyeye.bondbell/backup` finds the channel. I
  also ran `ios/scripts/release_guard.sh` directly. It exits 1 for an
  `integration_test/…` target and for a base64 `SCREENSHOT_MODE=true`
  define, and exits 0 for a clean release. Android has no native changes in
  this round.

| Finding | Status (14 Nov 2026) |
|---|---|
| M1 stale index for the session | **Verified fixed** |
| m1 Play "already owned" with an empty id | **Verified fixed** (residual: N2) |
| m2 iOS debug tip assert | **Verified fixed** |
| m3 file month not cross-checked | **Verified fixed** |
| m4 orientation from a zero-size view | **Verified fixed** |
| m5 one bad range wipes every holder | **Verified fixed** |
| m6 duplicate bonds double-counted | **Verified fixed** |
| m7 double-submit on the range sheet | **Verified fixed** |
| m8 unclaimed result never superseded | **Verified fixed** (partial; see note) |
| n1 to n4 | **Verified fixed** |
| n5 off-domain redirects | **Verified fixed** (through security L-1) |
| n6 fixed 4 s restore window | Not addressed (cosmetic, accepted) |

New this round: **0 Critical, 0 Major, 2 Minor (N1, N2), 3 Nit (N3 to N5)**,
listed after the original Nits.

## What I ran (original review, c9346e5)

- `flutter analyze`: no issues.
- `flutter test`: **283 passed** (PIPELINE's test row says 266; the suite has
  grown since).
- **Scan engine checked against a separate implementation.** I wrote a
  separate Python scanner from the file layout alone, without reading the
  app's parser logic. It splits on whitespace, takes the prize from `Part … £X`
  headings (winners) or `LGS UNCLAIMED/ANONYMOUS £X` / `END OF` (unclaimed),
  and matches by series plus serial range. I compared its matches with the
  app's engine (`tool/scan_bench.dart`, which runs `ScanJob` in a spawned
  isolate) on NS&I's real files: Nov 2026 winners (33.6 MB zip, 6,575,175
  numbers) and the unclaimed list (12.4 MB zip, 2,878,934 numbers). There were
  16 random ranges per file, covering every prefix length (3-digit, 2-digit,
  1-digit and none), plus the £1m bond and the £100k unclaimed bond as
  exact single-number ranges.
  - Winners: **66/66 hits identical** (bond, prize). Integrity ok, every tier
    count equals NS&I's table.
  - Unclaimed: **180/180 identical**. A further probe of 4 `LGS ANONYMOUS`
    entries and 2 bonds that appear twice (e.g. `AB191419`, £1,000 and £500)
    was also identical, with the anonymous flag and both prizes reported.
  - Scan time 0.74 s and 0.33 s (Mac JIT); max RSS 222 MB and 207 MB for the
    whole Dart VM process. The engine streams; nothing scales with file size
    except the hit list.
- Money paths checked against the plugin sources actually resolved
  (`in_app_purchase_android` 0.5.5, `in_app_purchase_storekit` 0.4.17, on
  StoreKit 2 by default), not only against the test fake.

## What is good (keep it)

- **Engine**: a streaming ZIP (central directory) → raw inflate → Latin-1 →
  line pipeline in a killable isolate. The structural token check is tight,
  and the integrity check compares every tier count with NS&I's own totals.
  It found no differences against the separate implementation above.
- **Generation counter** in `CheckSessionController`: every `await` is
  followed by a `gen != _generation` re-check. Sample-mode toggles, "Delete
  all my data" and dispose all bump it before changing scope, so a sample
  result cannot land in real history, and the reverse cannot happen either.
- **The download is deleted on every exit path**, and the scratch folder is
  cleared at launch.
- **Pro entitlement** is read synchronously from prefs. `PurchaseController`
  is created on the first frame through `ref.listen` in `BondbellApp.build`,
  so it is not a lazy provider that nothing reads. The flag is persisted
  before the transaction is finished, Android silently restores at launch so
  unacknowledged purchases get acknowledged, and Pro is grant-only.
- **Tips**: Play tips are consumed through one path (`finishConsumable`),
  whatever their history. On iOS, unfinished SK2 transactions are re-delivered
  on `Transaction.updates` at launch and finished there.
- **Release config**: R8 keeps for flutter_local_notifications/Gson/Billing.
  `keep.xml` keeps `@drawable/ic_notification`, which Dart refers to only by
  name; I confirmed the resource is present in the built release APK. The
  manifest declares both notification receivers. iOS has adopted UIScene
  (`FlutterImplicitEngineDelegate` + `SceneDelegate`), so it is clear of the
  iOS 27 launch crash. Deployment target 15.0 is set everywhere.

## Critical

None.

## Major

### M1. The NS&I index is cached for the whole app session, so "the latest draw" can be last month's on results day

- **Where**: `lib/features/draws/presentation/check_session.dart:171-173`
  (`ref.read(indexProvider).value ?? await …refresh()`), with
  `indexProvider` kept alive (`check_session.dart:55`). Affected callers:
  `home_screen.dart:180` ("Look for a newer draw"), `home_screen.dart:197`
  ("Check the latest draw") and `home_screen.dart:242` (Earlier draws).
- **Failure scenario**: the user checks November on 20 Nov, so the index is
  fetched and holds November as newest. Android keeps the process alive, or
  iOS keeps the app suspended in memory. On 2 Dec at 09:00 the results-day
  reminder fires, the user opens the app and taps "Look for a newer draw".
  `prepare()` finds a cached index, never calls nsandi.com, resolves `latest`
  to `2026-11`, and offers to re-download November's 34 MB file. If they go
  ahead, it overwrites November's record. Home keeps saying "November 2026
  draw". Pro users' Earlier-draws list also lacks December. The user
  reasonably concludes December's results aren't out or that they didn't win.
  Nothing short of killing the app fixes it. That is a missed real win on
  exactly the day the reminder exists for. For a free user, December cannot
  be checked at all in that session, because the gate also uses the stale
  `index.latest`.
- **Fix**: always refresh the index when the request is `latest`, and when
  the cached copy is older than a short TTL (say 10 minutes), or older than
  the most recent `ResultsCalendar` results day. Keep `fetchedAt` on
  `NsiIndex`. Refresh on `AppLifecycleState.resumed` if stale. Regression
  test: cache an index with only `2026-11`, have the fake source then return
  `2026-12`, call `prepare(CheckRequest.draw('latest'))`, and expect
  `state.list.id == '2026-12'`. Against today's code this fails: the fake's
  `fetchIndex` is called once, and `list.id` is `2026-11`.
- **Verified fixed (14 Nov 2026, `5d100a1`).**
  - `prepare` calls `ensure(force: true)` for `latest`, so nsandi.com is
    always asked again. `check_session_paths_test.dart:375` is the test
    specified above. Against the old `value ?? refresh()` it would see one
    fetch and `2026-11`, so the test bites.
  - Named-month requests reuse the cached index for at most 10 minutes, and
    never across midnight at the start of a results day
    (`latestResultsDayStart`). Traced against the real publication pattern:
    files go up at about 23:00 on the first working day, and results day is
    the next day.
    - An index fetched at 23:30 on 1 Dec, before the upload, is stale by
      00:00 on 2 Dec.
    - An index fetched just after midnight is stale 10 minutes later.
    - Either way, the only thing that can still be served from cache is a
      *named* month, and that cannot be mislabelled as "latest".
  - The free-tier gate now uses the freshly fetched `index.latest`.
  - Resume (`AppHooks` → `dropIfStale`) clears a stale index so Home stops
    calling an old month "latest".
  - Residual, accepted: if the app stays in the foreground across results
    day with no resume, Home's "<Month> draw" card keeps the old label until
    the user taps. Every tap re-fetches, so nothing wrong is downloaded or
    recorded.

## Minor

### m1. Play's "item already owned" never reaches the restore branch, and the test fake hides it

- **Where**: `purchase_controller.dart:222` and `:259-265`.
- In the resolved `in_app_purchase_android` 0.5.5
  (`in_app_purchase_android_platform.dart`, `_getPurchaseDetailsFromResult`),
  an `ITEM_ALREADY_OWNED` callback has an empty purchases list. The plugin
  then emits a `PurchaseDetails` with **`productID: ''`**. `isPro` is
  therefore false and the `alreadyowned` branch is dead. The user sees "The
  purchase didn't go through. Please try again." Retrying gives the same
  result. If `launchBillingFlow` itself returns the code, `started` is false,
  and the result is the same.
- `test/purchase_controller_test.dart:317` passes only because the fake
  emits the error with `productID = pro`, a shape the real plugin never
  produces.
- **Scenario**: an Android reinstall (backup is disabled, so the flag is
  gone) with no network at launch, so the silent restore fails. Later the
  user taps Unlock and gets a misleading failure. Restore on the same screen
  does recover it, which is why this is Minor. The same code on a tip whose
  consume failed gives a confusing "didn't go through".
- **Fix**: treat an empty-id error as "already owned" when its message
  contains `itemAlreadyOwned` and a Pro buy is in flight. Remember the
  in-flight product id (`_purchasingId`) and use it instead of
  `p.productID`. Run restore for Pro; for a tip, re-query and consume. Make
  the fake emit `productID: ''` for this case.
- **Verified fixed (14 Nov 2026).**
  - `_purchasingId` resolves the empty id. `_recoverOwned` restores. The
    restored Pro goes through the normal persist-then-complete path and shows
    "restored", and a restored tip is consumed and shows `tipCleared`.
  - `launchBillingFlow` refusing outright (`!started`) triggers a quiet
    restore.
  - `fakes.dart` `playAlreadyOwned()` now emits the plugin's real shape:
    empty id, `BillingResponse.itemAlreadyOwned`. I checked it against
    `in_app_purchase_android` 0.5.5 `_getPurchaseDetailsFromResult`.
  - The quiet restore on iOS is harmless: SK2 `buyNonConsumable` always
    returns true, and its `restorePurchases` iterates
    `Transaction.currentEntitlements` without an `AppStore.sync` sign-in
    prompt.
  - Residual: see N2 (a *pending* purchase hitting this path gets a
    misleading notice).

### m2. iOS debug builds cannot tip: `buyConsumable(autoConsume: false)` trips the StoreKit plugin's assert

- **Where**: `store_gateway.dart:51-54`. In `in_app_purchase_storekit`
  0.4.17, `buyConsumable` starts with
  `assert(autoConsume, 'On iOS, we should always auto consume')`.
- In debug, every tip throws an `AssertionError` before the sheet opens.
  `_buy` catches it and shows "didn't go through". Release (and TestFlight)
  strips asserts, so it works there. This is a debug/release difference that
  will make the planned sandbox tip test fail if it is run from
  `flutter run`. Someone could then "fix" working code.
- **Fix**: `autoConsume: defaultTargetPlatform != TargetPlatform.android`,
  or pass `autoConsume: false` only on Android.
- **Verified fixed (14 Nov 2026).** `autoConsumeFor(platform)` gives true on
  iOS, which satisfies the assert, and false on Android, which keeps manual
  consumption. iOS still finishes the transaction in `finishConsumable`.

### m3. The draw month inside the file is never compared with the month that was requested

- **Where**: `nsi_list_parser.dart:159-160` reads `drawLabel`. Nothing reads
  it (`check_session.dart:300`).
- A results list is identified only by the link text, or else the href.
  NS&I's page is hand-edited (an old link already sits inside an HTML
  comment). If a link labelled "December 2026" points at November's file,
  the app stores November's wins as December's with "integrity ok".
- **Fix**: in `_record`, compare `summary.drawLabel` with
  `NsiIndexParser.labelFor(request.drawId)`. On a mismatch, fail with the
  layout-changed message, or at least set `integrityOk = false`.
- **Verified fixed (14 Nov 2026).**
  - `monthMismatch` refuses a mismatch, or a missing heading, before
    anything is stored. Sample mode is exempt.
  - Confirmed on the real June, October and November 2026 files that it
    accepts genuine lists.
  - It is now a hard failure if NS&I ever rewords the heading. That is the
    safe direction, but re-check the live file each release, as TEST_PLAN
    already says.

### m4. Phone-versus-tablet orientation is decided from the view size before the first frame

- **Where**: `lib/main.dart:25-32`. `views.first.physicalSize` read in
  `main()` can still be `Size.zero` before the platform has sent viewport
  metrics. It is commonly zero on Android cold starts. With UIScene's
  implicit engine, `main()` can also run before the view's first layout.
- When it is zero, `shortest < 600` is true and **tablets and iPads are
  locked to portrait**. That contradicts the spec ("iPad supports all
  orientations"). Foldables are locked by whichever state they started in.
- **Fix**: on iOS, rely on Info.plist, which is already portrait-only for
  iPhone and allows all four orientations on iPad, and drop the Dart call
  there. On Android, decide after the first frame, e.g. in the shell from
  `MediaQuery.sizeOf(context).shortestSide`, and re-apply when the size class
  changes. Verify: rotate a real iPad or iPad simulator to landscape on a
  cold launch.
- **Verified fixed (14 Nov 2026).**
  - `main()` no longer touches orientation.
  - `AppHooks` (inside `MaterialApp.builder`, so MediaQuery exists) skips an
    empty size, applies the rule only on Android, and re-applies it when the
    size class changes, which covers foldables.
  - iOS is left to Info.plist: iPhone portrait-only, iPad all four.
  - I did not rotate a device myself.

### m5. One unreadable range deletes every holder at the next save

- **Where**: `holders_controller.dart:49-58`.
- If any range fails `BondRange.fromJson`, the whole list falls back to `[]`
  (or the sample holder). The next `_save` (adding any range or holder) then
  overwrites the stored list, so the user's bonds are gone. Today every
  stored value comes from a validated parse. This is a trap for any future
  format or validation change, such as tightening `allowedLetters`.
- **Fix**: parse per holder and per range and skip only the bad entry. Or,
  on failure, copy the raw string to `real.holders.bak` before returning a
  fallback, and never overwrite a key that failed to parse.
- **Verified fixed (14 Nov 2026).**
  - `parseHoldersTolerant` skips only the bad holder or range.
  - On any loss, the raw text goes to `<scope>.holders.bak` before the next
    save can overwrite it.
  - `.bak` is only written while the stored text is lossy. After the save,
    the key parses cleanly, so the backup is not overwritten again.
  - "Delete all my data" clears it, because it shares the prefix.
  - Records were already tolerant per entry.

### m6. Duplicate bonds still double-count "bonds checked" and held totals

- **Where**: `check_session.dart:443-445`, `home_screen.dart:26`,
  `history_screen.dart:67`.
- Prizes are now de-duplicated (`Win.hit`). Bond counts are not: the same
  range saved under two holders, or twice under one, counts twice in "Checked
  … against N of your bonds", in Home's "N bonds (£N)", and in the History
  "Held now" figure and annualised rate. The rate is understated by half.
- **Fix**: count the union of ranges per series once for these totals.
  Per-holder totals can stay as they are.
- **Verified fixed (14 Nov 2026).** `uniqueBondCount` sorts and merges
  overlapping and adjacent spans per series, which I checked by hand. It is
  used in Home, My bonds, Unclaimed, History and `bondsChecked`. Per-holder
  totals are unchanged.

### m7. The range sheet can save the same range twice

- **Where**: `holder_screen.dart`, `_RangeSheetState._save`.
- There is no in-flight guard. A double tap on Save (or Save plus the
  keyboard's Done, which also calls `_save`) adds two identical ranges before
  the sheet pops. That feeds m6.
- **Fix**: add a `_saving` flag that disables the button while the save
  runs.
- **Verified fixed (14 Nov 2026).** `_saving` guards both the button and
  `onSubmitted`, and is reset in `finally`.

### m8. A stored unclaimed result never goes stale when NS&I publishes a new unclaimed list

- **Where**: `unclaimed_screen.dart:50` and the `fingerprint` logic.
- Staleness tracks only the user's holdings. The current list is "June 1957
  to March 2025". When NS&I republishes, the old "Nothing unclaimed found"
  stays shown as current.
- **Fix**: store `list.url`, or the label, in the record. When a later index
  shows a different unclaimed URL, mark the record "NS&I has published a
  newer list".
- **Verified fixed, with a limit (14 Nov 2026).**
  - Records carry `sourceUrl`, and `supersededBy` flags them on the result
    and in the Unclaimed list.
  - The flag can only appear once an index has been fetched in that session.
    The app deliberately does not contact nsandi.com until the user taps, so
    a superseded result looks current until the next check or "Show
    available draws".
  - Acceptable given the no-background-fetch design.

## Nit

- n1. `check_session.dart:258-264`: `state` is rebuilt for every download
  chunk, roughly 500 rebuilds of `CheckScreen` for 34 MB. Throttle to
  whole-percent changes, as the scan does.
- n2. `result_view.dart:31-33` groups wins by `holderName`, so two holders
  with the same name merge into one card. Group by `holderId`.
- n3. `scan_worker.dart:57-86`: if `cancel()` lands between
  `Isolate.spawn` returning and `_job` being assigned, the isolate is never
  killed. It fails quickly on the deleted file, so the cost is negligible.
  If `Isolate.spawn` throws, the `ReceivePort` is never closed.
- n4. `purchase_controller.dart:226-228`: the Android silent restore at
  launch shows the "waiting for approval" snackbar on every launch while a
  Play purchase is pending, without the user doing anything. Suppress
  notices that come from the silent launch restore.
- n5. `draw_source.dart:184-186`: `package:http` follows redirects, so a
  redirect from nsandi.com to another host is followed, and the bytes are
  only checked for `PK`. This is for the security auditor to weigh. A
  `followRedirects = false` loop that allows only `*.nsandi.com` would close
  it.
- n6. `restore()` reports `nothingToRestore` after a fixed 4 s, even when a
  slow store delivers the purchase a moment later. The purchase is still
  granted when it arrives, so this is cosmetic.

Nit status (14 Nov 2026):

- n1: whole-percent throttle. Verified fixed.
- n2: grouped by `holderId`, titled with the name. Verified fixed.
- n3: the job is killed if the generation changed during spawn, and the
  port is closed if spawn throws. Verified fixed.
- n4: a pending notice is only shown while busy. Verified fixed.
- n5: manual redirects, each hop checked as https `*.nsandi.com`. Verified
  fixed.
- n6: not addressed; accepted.

## New findings, fix round 2 (14 Nov 2026)

### N1 (Minor). Vault write failures are silent, and a corrupt vault silently shows an empty app

- **Where**: `local_store.dart`, `DataVault._flush` and `DataVault.open`.
- `_flush` catches every error and only logs it, and the log is compiled out
  of release. `_values` already holds the new value. So a failed write (disk
  full, a protection-class error) tells the user "saved" while the file
  keeps the old data. They lose the change at the next launch. I proved this
  with a probe that makes the directory read-only after the first save.
- A later successful write heals it, because each write rewrites the whole
  snapshot.
- If `vault.json` is ever unreadable, it is copied to `vault.json.bak` and
  the app opens with **no bonds and no explanation**. Nothing reads the
  `.bak` back. A second corruption overwrites the first `.bak`.
- Likelihood is low: temp file plus rename is atomic, and 1.0 has no
  installed base to migrate, so this is not blocking.
- **Fix**:
  - Have `set` return the write's success. Let `HoldersController._save`
    and `RecordsController.put` show "Couldn't save on this phone" and keep
    the sheet open.
  - On open, if the vault is unreadable and a `.bak` from a previous good
    state exists, offer to restore it.
  - Name each `.bak` with a timestamp, or never overwrite an existing one.

### N2 (Minor). A pending Play purchase that hits "already owned" gets the wrong message

- **Where**: `purchase_controller.dart`, `_recoverOwned` and the
  `_isPlayPending` branch.
- A slow-card or cash Play order stays pending. If the user taps the same
  item again, Play answers `ITEM_ALREADY_OWNED`, and `_recoverOwned` runs a
  restore. The restore delivers the pending purchase, which shows "waiting
  for approval" and clears busy. Then, 4 s later:
  - For a tip, `tipCleared` says "An earlier tip hadn't finished and has now
    been cleared. Please try again." That is false: it is still pending, so
    trying again repeats the loop.
  - For Pro, `found` is false, so "The purchase didn't go through"
    overwrites "waiting for approval".
- No one is charged twice, and Pro still unlocks when the order clears.
- **Fix**: in the pending branch, set `_restoreFound = true`, or a
  `_sawPending` flag, while `_restoring`. In `_recoverOwned`, if a pending
  purchase was seen, finish with `pending` instead of
  `tipCleared`/`failed`. Add a fake test: a pending purchase is delivered on
  restore after `playAlreadyOwned()`.

### N3 (Nit). The scan is about twice as slow with the `async*` line splitter

- **Where**: `scan_worker.dart`, `BoundedLineSplitter`.
- Nov winners went from 0.74 s to 1.51 s, and unclaimed from 0.33 s to
  0.68 s (Mac JIT, same files). The cause is one `yield` and stream event
  per line, about 900k of them.
- The output is correct (fuzz-tested). On a low-end phone this is perhaps
  a few seconds more with a progress bar showing.
- A synchronous `StreamTransformer.fromHandlers`/`ChunkedConversionSink`
  splitter, or `LineSplitter` plus a separate length check on the pending
  partial, would recover it.

### N4 (Nit). The 10-minute total download deadline may cut off slow connections

- **Where**: `draw_source.dart`, `totalDeadline`.
- 34 MB in 10 minutes needs about 0.45 Mbit/s sustained. Rural 3G or a weak
  signal, which this older audience is likely to have, can fall below that.
- The user then sees "taking far longer than it should… try again later".
- Consider 20 to 30 minutes. The 30 s idle timeout already catches a dead
  connection, and the cap protects against a trickle attack, not against
  slow users.

### N5 (Nit). The second timeout on the downloads page is not a total deadline

- **Where**: `draw_source.dart`, in `fetchIndex`:
  `r.stream.timeout(_timeout).timeout(_timeout * 2)`.
- Both calls are per-event idle timeouts, so the second never fires before
  the first.
- Use the `Stopwatch` check that `download` uses if a total bound is meant.

## Totals

Original review (c9346e5): Critical 0 · Major 1 · Minor 8 · Nit 6. All are
verified fixed at 5d100a1 except n6, which is accepted.

Fix round 2 (5d100a1): new Critical 0 · Major 0 · Minor 2 (N1, N2) · Nit 3
(N3 to N5).

## Final re-check, fix round 3 (14 Nov 2026, HEAD `ca1d081`)

This covers commit `3623a80` (N1, N2 and the N3 to N5 nits, plus security
and compliance items) and commit `ca1d081` (sample mode opens every Pro
feature on sample data). I reviewed both diffs as new code. Probes ran in a
throwaway copy of `ca1d081` in my scratchpad, which I deleted afterwards. I
wrote nothing to the repo except this file and `PIPELINE.md`.

### What I ran

- `flutter analyze`: no issues. `flutter test`: **352 passed**.
- **Engine, after the line-splitter rewrite.** `BoundedLineSplitter` is now
  `LineSplitter` behind a synchronous `map` that only measures the run
  since the last line break. I re-ran my separate Python scanner on the real
  files:
  - Nov 2026 winners **66/66 identical**, in **0.80 s**. That is back to
    the original 0.74 s, from 1.51 s in round 2.
  - Unclaimed **180/180 identical**, in 0.36 s.
  - The 8 anonymous and duplicate-bond probes were identical.
  - The June and October 2026 files still parse their own month, and
    integrity is ok.
  - The guard is correct: a line that ends inside a chunk is emitted by
    `LineSplitter` at once, so only the unfinished tail of a chunk can grow,
    and `run` measures exactly that tail.
- **Vault probes** (7 probe tests, all pass):
  - A failed write returns false, leaves memory unchanged, and a later write
    repairs it.
  - `HoldersController` throws `SaveFailedException` and leaves the holder
    list unchanged. The save queue keeps working after a failure: a
    following save still lands.
  - A corrupt `vault.json` with a good `.bak` comes back as `recovered` with
    the old data. Each corrupt file is set aside under its own
    `.corrupt-<ms>` name, so a second corruption keeps the first.
  - A corrupt file with no `.bak` comes back as `lost`, and the user sees a
    dialog explaining it.
  - `deleteAllPrivateData` leaves only an empty `vault.json` (`.bak`,
    `.corrupt-*` and `.tmp` are removed) and keeps `purchases.proOwned` and
    the settings.
  - Migration with a failing write keeps the prefs copy, and a later launch
    completes it.
- **Sample-mode Pro gate (`ca1d081`).** Every gate reader is in this list:
  - `proFeaturesProvider` (real Pro OR sample mode) controls features only:
    the add-holder flow and `addHolder`, `CheckSessionController._gate`,
    History, Earlier draws, and Unclaimed "search all".
  - `isProProvider` still drives the entitlement display: the Pro screen
    and Settings.
  - Nothing writes `purchases.proOwned` from sample mode.

### Can a paid feature reach REAL data without a purchase? No

These are the paths I traced and probed.

- **Data and source scoping.** In sample mode `drawSourceProvider` is
  `SampleDrawSource`, which only reads bundled assets, and holders and
  records use the `sample.` keys. So even a sample-mode Pro check of numbers
  the user typed in only reads made-up lists.
- **Switching modes mid-flow.** All three switches call
  `checkSessionProvider.reset()` before flipping the mode: the shell
  banner's Exit, the Settings switch, and Home's "Try with sample numbers".
  `reset()` bumps the generation, so a sample check that finishes after the
  exit is thrown away. Onboarding sets the mode before any check can exist.
- **Worst case without the reset.** I built a probe that prepares a free
  user's `unclaimedAll` and `2026-10` checks in sample mode, flips to real
  mode **without** a reset, then calls `start()` against the real
  `NsiDrawSource`. Both end **failed with nothing recorded**: the prepared
  list's `asset:///` URL cannot pass the https `*.nsandi.com` check. That
  is a second layer behind the reset.
- **Holder limit.** In a probe, a free user with one real holder is refused
  a second. In sample mode, adding is allowed and goes into the sample
  holders. After exit, the real list is unchanged (`['Me']`), `isPro` is
  false, and `proOwned` is never written.
- **Routes.** Gated routes (`/check/unclaimed`, `/check/draw/:id`) re-run
  `_gate` in `prepare` whatever screen pushed them. Nothing sets
  `restorationScopeId`, and there are no deep links, so neither state
  restoration nor a URL can open a check outside these gates.
- **A paying user** is unaffected: `proFeaturesProvider` is `isPro || …`,
  and the Pro screen and Settings still read `isProProvider`.

### Status of the round-2 findings

| Finding | Status (14 Nov 2026, `ca1d081`) |
|---|---|
| N1 silent vault failures / unexplained empty app | **Verified fixed**. Writes are committed to memory only after they succeed. A failed save is reported: the range sheet stays open with the message, other saves show a snackbar via `saveOrExplain`, and a check fails with "couldn't save the result". The previous launch's good copy is kept as `.bak`, with `recovered`/`lost` explained once at launch, and corrupt files are kept under unique names. Probed as above. |
| N2 pending order hitting "already owned" | **Verified fixed**. During a restore or recovery, a pending purchase sets `_sawPending` and the window ends with `pendingEarlier` ("still waiting for approval… no need to buy again") instead of `tipCleared`/`failed`. A user-initiated Restore that finds only a pending order says the same instead of "nothing to restore". The fake `playPendingRestored` and its test exercise it. |
| N3 scan twice as slow | **Verified fixed** (0.80 s, results identical). |
| N4 10-minute total download deadline | **Verified fixed** (30 minutes; the 30 s stall timeout still catches a dead connection). |
| N5 second page timeout not a total deadline | **Verified fixed** (a 60 s `Stopwatch` deadline on the whole page read). |

### New findings, fix round 3 (none blocking)

- **N6 (Nit). A holders save queued across a mode switch could land in the
  wrong scope.**
  - **Where**: `holders_controller.dart`, `_mutate`.
  - The Notifier instance survives the rebuild that a sample-mode toggle
    causes. A write already in flight then assigns `state = next` (the old
    scope's holders) after `_key` and `state` have switched. The next real
    save would persist that.
  - It is unreachable through the UI: every save runs inside a modal sheet,
    dialog or screen, and the write takes milliseconds.
  - **Fix**: capture `_key` when the mutation starts, write to that key, and
    skip the `state` assignment if `_key` has changed by the time it lands.
- **N7 (Nit). `_gate` runs in `prepare()`, not again in `start()`.**
  - Today this is safe: every mode switch resets the session, and the
    prepared URL check stops a cross-mode start (both probed above).
  - Re-running `_gate` and checking that `source.isSample` matches the
    prepared list at the top of `start()` would make the Pro gate hold even
    if a future change adds a mode switch without a reset.

## Totals

Original review (c9346e5): Critical 0 · Major 1 · Minor 8 · Nit 6. All are
verified fixed except n6, which is accepted.

Fix round 2 (5d100a1): Minor 2 · Nit 3. All verified fixed at ca1d081.

Fix round 3 (ca1d081): new Critical 0 · Major 0 · Minor 0 · Nit 2 (N6, N7).

## Release commit (14 Nov 2026, `b4f1e5c`; also holds for `c62ca56`)

- **`b4f1e5c`** adds `_TrySampleCard` to Home. It is shown only when not in
  sample mode. Its button calls `checkSessionProvider.reset()` and then
  `setSampleMode(true)`. This is the same reset-then-switch order my
  mode-switch analysis above relied on, so a check in progress is discarded
  before the data scope changes.
  - It touches no gate and no entitlement.
  - The new widget test asserts `proFeaturesProvider` is true and
    `isProProvider` is false afterwards, and that the card is hidden while in
    sample mode.
  - No new findings.
- **`c62ca56`**, the current HEAD, is metadata, privacy-policy and
  audit-document changes only. `git diff b4f1e5c c62ca56 -- lib ios/Runner
  android/app pubspec.yaml` shows no code changes.
- At HEAD: `flutter analyze` reports no issues, and `flutter test` passes
  **352**.

The verdict below applies to the code at `b4f1e5c`, which is identical in
code to `c62ca56`.

Verdict: PASS
