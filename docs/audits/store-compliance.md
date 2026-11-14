# Bondbell: store compliance audit (stage 6)

Auditor: app-store-review-auditor, 14 Nov 2026. Scope: source at HEAD `5d100a1` plus the
uncommitted metadata; built artifacts `build/app/outputs/bundle/release/app-release.aab`
(17:30) and `build/ios/iphoneos/Runner.app` (12:04, newer than every source file it
compiles); all of `ios/fastlane/`, `android/fastlane/`, `PRIVACY_POLICY.md`, `docs/ASO.md`,
`docs/IAP_PRODUCTS.md`, `docs/AGE_RATING.md`, `store_assets/` (icon, Play icon and feature
graphic opened as images) and the `docs/build_evidence/` captures. Store screenshots do not
exist yet (`ios/fastlane/screenshots/` and `.../images/` are absent), so they were audited
from `store_assets/SCREENSHOTS.md` and the evidence captures only.

Policy text was fetched live today rather than taken from memory: Apple App Store Review
Guidelines (2.3.7, 2.3.8, 3.1.1, 4.1, 5.1.1(ix), 5.2.1, 5.2.2, 5.3.3–5.3.4), Google Play
"Real-money gambling, games and contests" and "Payments", and NS&I's own "Site conditions
and legal" page and winning-bonds downloads page.

## Summary

| Severity | Count | Items |
|---|---|---|
| Blocker | 1 | B-1 privacy-policy and support URLs are not live |
| Should-fix | 4 | S-1 paid access to NS&I content (5.2.2), S-2 wrong trade-mark owner in the app, S-3 IAP review screenshot shows the unlocked state, S-4 pipeline order puts the website after publish |
| Advisory | 8 | A-1 to A-8 |

Code, binaries and copy are in good shape. No permission, SDK, tracking, payment-routing or
age-rating defect was found, and every factual claim in the listings checks out against the
code and NS&I's live site. The verdict is FAIL only because the two URLs a reviewer opens
first return errors today. Both are closed by publishing the privacy page and the support
page; nothing in the code or binaries needs to change for that.

---

## Blocker

### B-1. Privacy-policy URL is 404 and the support/marketing URL does not resolve

- **Policy:** Apple 5.1.1(i) (a privacy policy link in App Store Connect **and** inside the
  app, which must work) and 1.5 (the support URL must lead to a way to contact the
  developer). Google Play User Data policy (a working privacy-policy link in the listing and
  in the app). Play also requires the website field to be a working URL.
- **Evidence (curl, 14 Nov 2026, run against the strings compiled into both binaries):**
  - `https://mksoft-ltd.github.io/bondbell/privacy_policy.html` gives **404**. The GitHub
    repository `mksoft-ltd/bondbell` does not exist (`gh repo view` cannot resolve it).
  - `https://bondbell.froggyeye.com` has **no DNS** (curl exit 6). It is the iOS support URL
    and marketing URL, the Play website field, the in-app "Help and support" link, the
    About screen link, and part of the User-Agent string sent to NS&I.
  - Both strings appear verbatim in `App.framework/App` and in `libapp.so` (arm64), so the
    binaries and the listings agree with each other. They just point at nothing.
- **Fix:**
  1. Create `mksoft-ltd/bondbell`, push `PRIVACY_POLICY.md` and `docs/privacy_policy.html`,
     and turn on Pages from `/docs`. Confirm a **200 with `content-type: text/html`** from
     the exact constant `AppConstants.privacyPolicyUrl` (house-facts §5).
  2. Create the `bondbell` page on froggyeye.com and the subdomain
     (`scripts/create_subdomain.py`). Confirm it returns 200 and shows a contact route
     (info@froggyeye.com).
  3. Re-run the curl for all three fields before pressing Submit on either store.
- Once both URLs return 200 this finding closes with no further audit needed.

---

## Should-fix

### S-1. Pro sells access to NS&I's lists; Apple 5.2.2 can ask for authorisation we do not hold

- **Policy:**
  - Apple 5.2.2: "If your app uses, accesses, **monetizes access to**, or displays content
    from a third-party service, ensure that you are specifically permitted to do so under
    the service's terms of use. **Authorization must be provided upon request.**"
  - Apple 5.2.1: no protected third-party material without permission.
  - Google Play Intellectual Property policy. This one is complaint-driven.
- **Evidence:**
  - NS&I's Site conditions (fetched today) say: "You may print, copy, download, or
    temporarily store extracts from our site for your personal use … Any other use is
    prohibited unless you first get our written permission."
  - The same page says: "Other than as provided above, you may not use or reproduce our
    trademarks, logo or brand name."
  - The app's design keeps within the personal-use wording. The user's own device fetches
    the file, only when the user taps, and nothing is mirrored, bundled or altered
    (`draw_source.dart`; the sample files are synthetic).
  - However, two of the four Pro benefits are paid access to NS&I files:
    - "Earlier draws", gated in `check_session.dart` `_gate()` and on the Home screen
      `_EarlierDraws` card.
    - "Unclaimed search for all your bonds", gated in `unclaimed_screen.dart`.
  - That is the "monetizes access to" case in 5.2.2's wording. If a reviewer asks for
    "documentation that you are authorised to use NS&I's content", the studio has none to
    send.
  - Precedent lowers the odds but does not remove them. "Numo – Premium Bonds & Savings"
    (individual developer, approved Jan 2026) carries the trade mark in its **name**, and a
    third-party "Premium Bonds Prize Checker +" is live on Play with a subscription.
- **Assessment:**
  - This is the most likely reason for an Apple rejection or information request. My
    estimate is roughly a 15–25% chance that a reviewer raises it.
  - It is also the most likely route to a **takedown** on either store, through an NS&I
    complaint, because the listing names NS&I and its product and sells a paid tier.
  - It is not a Blocker. The design follows NS&I's personal-use terms, and the founder
    knowingly accepted the descriptive trade-mark use.
- **Fix (recommended, in this order):**
  1. **Re-gate Pro to the app's own value.** Make earlier draws and the all-bonds
     unclaimed search free. Keep Pro as unlimited holders plus history and stats. Those two
     features are Bondbell's own work on the user's own data, so nothing paid is "access to"
     NS&I content.
     - This touches `_gate()`, `_EarlierDraws`, `UnclaimedScreen`, `ProScreen.benefits`,
       the Settings Pro card, both descriptions, `IAP_PRODUCTS.md` descriptions and the
       review notes.
     - It is a founder pricing call. If it is declined, keep the answer in the Q&A below
       ready to paste.
  2. Email NS&I (press office or digital team) to describe the app and ask for written
     comfort. Do this in parallel; do not wait for a reply before submitting. A written
     "no objection" removes both the 5.2.2 risk and the takedown risk for good.
  3. Keep every safeguard already in place: no mirroring, no bundling, an honest
     User-Agent, the independence notice on four screens, "confirm with NS&I", and links
     out to NS&I to claim.

### S-2. The in-app independence notice names the wrong trade-mark owner

- **Policy:** Apple 2.3.1 (accuracy) and 5.2.1. Google Play Impersonation and Metadata
  policies.
- **Evidence:**
  - `lib/core/constants/app_constants.dart:36-39` reads: `"Premium Bonds" and "NS&I" are
    trade marks of National Savings and Investments.` It is compiled into both binaries
    (confirmed with `strings libapp.so`) and shown in onboarding, on Home, in Settings and
    in About.
  - NS&I's legal page says the marks are "registered to the Director of Savings… All
    rights in and to these trademarks vest in the Director of Savings".
  - Both store descriptions already say this correctly. The app and the store listing
    disagree on a legal statement made about a third party.
- **Fix:** change the constant to `"Premium Bonds" and "NS&I" are registered trade marks of
  the Director of Savings.` Then rebuild both binaries. It is a one-line copy change with no
  logic impact.

### S-3. The planned IAP review screenshot shows Pro already unlocked

- **Policy:**
  - App Store Connect requires a review screenshot for each IAP, showing the purchase
    being offered.
  - Apple 2.1 (incomplete submission) applies if Pro's purchase UI cannot be seen.
- **Evidence:**
  - `docs/IAP_PRODUCTS.md` names `docs/build_evidence/ios_iphone_09_pro.png` as the Pro
    review screenshot.
  - That image (opened) reads "**You have Bondbell Pro** … Everything below is unlocked",
    with no price and no "Unlock Pro" button. It was taken in `SCREENSHOT_MODE`, which
    forces Pro on (`main.dart`, `forceProProvider`).
  - The same mode can never produce the locked state. The tip screenshot is also still to
    be captured.
- **Fix:** at the publish stage, after the four products exist in sandbox:
  - Run a debug or profile build **without** `SCREENSHOT_MODE`.
  - Capture the Pro screen showing "Unlock Pro · £4.99".
  - Capture the Settings Tip jar card with its three priced buttons.
  - Correct the file reference in `IAP_PRODUCTS.md`.

### S-4. The pipeline runs the website stage after publish

- **Evidence:** in `PIPELINE.md` the stage order is compliance → publish → website. The
  website row says the subdomain and the privacy repo do not exist yet.
- **Fix:** move the website and privacy-repo work ahead of the review submission, or make
  B-1's curl check a hard gate inside the publish stage. Building and uploading binaries
  can go ahead in parallel; only **Submit for review** has to wait.

---

## Advisory

- **A-1. App name close to NS&I's official app.**
  - "Bondbell: Bond Prize Checker" sits beside NS&I's own "Premium Bonds prize checker" in
    search results (live iTunes search, GB).
  - Apple 4.1(c) forbids another developer's product name in the app name. "Prize checker"
    is generic wording, NS&I's product name ("Premium Bonds") is not in the name, and the
    distinct brand "Bondbell" leads the name.
  - The icon (a brass bell on bottle green) is nothing like NS&I's coral "NS&I" lettermark.
  - Low risk. Keep the trade mark out of the name and icon, as the founder decided.
- **A-2. Gambling and lottery classification.** Neither store's gambling rules are
  triggered, and the declarations are right.
  - Apple 5.3.4 covers apps that *offer* real-money gaming or lotteries, which "must have
    consideration, chance, and a prize". Bondbell sells no entries, takes no stakes and
    pays nothing.
  - Play's policy targets apps that "enable or facilitate users' ability to wager, stake or
    participate using real money", or that show a call to action to do so. Bondbell has no
    "buy bonds" link at all: its links go to NS&I's contact page, prize-checker page and
    downloads page only (verified in `App` and `libapp.so`).
  - Correct answers, as already written in `docs/AGE_RATING.md` and
    `data_safety_answers.md` §5:
    - Apple: Gambling No, Simulated gambling None, Contests None, which gives 4+.
    - IARC: gambling No, digital purchases Yes.
  - Do not tick "Contests" or "Gambling" to look cautious. Either answer would be
    inaccurate, and it would invite the very scrutiny you want to avoid.
- **A-3. Not a regulated financial service.**
  - Apple 5.1.1(ix) concerns apps that *provide* banking or financial services, and its
    remedy is that a legal entity submits the app. Bondbell provides no such service, and
    it is submitted by Froggy Eye Ltd (a company) anyway.
  - Play's Financial features declaration: choose "none of the listed features", as
    `data_safety_answers.md` §7 says.
  - The one finance-flavoured surface is History's "Your prizes as a yearly rate" card
    (Pro, screenshot 6). It carries "For information only, not financial advice", which is
    adequate. Keep that note visible in the screenshot, as the spec already requires.
- **A-4. Tip jar is compliant on both stores.**
  - Apple 3.1.1 explicitly allows IAP used "to 'tip' the developer". Tips are Consumable
    products, unlock nothing, and say so in the app.
  - Play Payments requires Play Billing for in-app digital payments, and it is used here.
    The only payments Play keeps outside Play Billing are tax-exempt donations, and these
    tips are not donations to a charity.
  - Keep the word "donate" out of all copy.
  - The card under a winning result ("Glad Bondbell helped?") never appears on a no-prize
    result or in sample mode (`result_view.dart`), so it cannot read as paying to improve a
    result.
- **A-5. Play Data safety and the Billing library's telemetry.**
  - The AAB contains `com.google.android.datatransport` components, which is the Billing
    library's Firelog transport. The answer "No data collected" follows the common reading
    that Google Play's own billing stack is part of Google Play rather than an SDK
    collecting data for the developer.
  - I could not find a published Google disclosure page for Play Billing that settles the
    question either way.
  - Low risk, and Google does not verify the form. Revisit if Play's pre-review flags it.
- **A-6. History label in the evidence capture.**
  - `ios_ipad_05_history.png` shows the newest sample row labelled "**Sample**", while the
    other rows read "October 2026 (sample)" and so on.
  - It looks like a label leaking from the sample ZIP header. If it shows in store
    screenshot 6 it looks unfinished (2.1 polish).
  - Check the label at capture time. Fix the label code or the seed before framing.
- **A-7. No app-level `PrivacyInfo.xcprivacy`.**
  - Runner's own Swift (backup exclusion through `setResourceValues`) uses no
    required-reason API. Every plugin that does (shared_preferences,
    flutter_local_notifications, Flutter) ships its own manifest in the `.app`.
  - No ITMS-91053 is expected. Add an app-level manifest with `NSPrivacyTracking false`
    and no collected types if you want belt and braces.
- **A-8. First version without What's New.** As PIPELINE already notes, do not upload
  `release_notes.txt` with 1.0.0 on iOS. Play's `changelogs/1.txt` is harmless.

---

## Explicit assessments requested by the conductor

**Third-party trade mark and data.**
- Descriptive use of "Premium Bonds" in the subtitle, keywords and descriptions is nominative
  use (UK TMA 1994 s.11(2)). It always sits beside the non-affiliation notice, and the term
  is kept out of the name and the icon. Apple's 2.3.7 bar is "to game the system", and this
  use does not meet it. Precedent (Numo's name) shows Apple accepts more than we use.
- NS&I is named only as the data source and in the disclaimer. "ERNIE" and "NS&I" are not
  in the keyword fields (verified in `keywords.txt`).
- The data question is S-1: personal-use terms plus a paid tier over NS&I files.
- Fix S-2 so the attribution is right everywhere.

**Gambling, lottery or contest content, and regulated finance.** None of these, on either
store (A-2, A-3). The declarations as drafted are correct. The review notes' "NOT A
FINANCIAL SERVICE, NOT GAMBLING" paragraph is accurate and useful.

**Tip jar.** Compliant on both stores (A-4). It needs one review screenshot per product
(S-3).

**Factual claims versus code.** Every claim below was checked against the code and found
true:

| Claim | Where it was verified |
|---|---|
| No login and no account | the whole app |
| Numbers never sent | the only Dart HTTP host is nsandi.com, every redirect hop is re-validated, and requests carry only the User-Agent |
| Downloads directly, keeps matches, deletes the file | `draw_source.dart` and `clearScratch` |
| Size shown first | HEAD request plus the "Download size" fact |
| Cancel at any time | `DownloadCancel` |
| "About six" months | NS&I's page today lists Jun–Nov 2026 |
| "Back to 1957" | NS&I's file is "June 1957 – March 2025" |
| Unclaimed list gives values | parser `LGS UNCLAIMED £n` |
| 09:00 UK time on results day | `reminderTimes` uses Europe/London |
| Reminder is not a win alert | notification text |
| Holder-number explanation | `bond_number.dart:40` |
| Free/Pro split exactly as listed | `_gate`, `FreeTier`, History gate, Unclaimed gate |
| Tips unlock nothing | `PurchaseController` grants nothing for a tip |
| Not in backups | iOS: vault folder excluded through the channel, present in the built `Runner`. Android: `allowBackup=false` and `data_extraction_rules.xml` exclude everything (merged manifest) |
| "Delete all my data" | Settings → `clearPrefix` |

- The privacy policy's statements match too, including the iOS settings and Pro flag being
  backed up and the Play Billing telemetry.
- No sentence anywhere claims the app contacts only NS&I.

**Privacy label and Data safety versus binaries.**
- Apple "Data Not Collected" is correct.
  - iOS binaries scanned with `nm` and `strings`: no AVCapture, PHPhotoLibrary,
    CoreLocation, Contacts, ATT, AdSupport, HealthKit, EventKit or Bluetooth symbols.
  - No `NS*UsageDescription` keys are needed, and none are present.
  - `ITSAppUsesNonExemptEncryption = false` is correct: only OS TLS is used.
- Play "No" is correct, with the caveat in A-5.
  - Merged release manifest: INTERNET, ACCESS_NETWORK_STATE, BILLING, POST_NOTIFICATIONS,
    RECEIVE_BOOT_COMPLETED, VIBRATE and the androidx dynamic-receiver permission.
  - No AD_ID, no exact-alarm permission, no foreground service, no media or location
    permission, so no Play declaration forms are triggered.
  - targetSdk 36, minSdk 24. Signed with the upload key: SHA-1 `6F:08:…:C5` matches
    PIPELINE.

**Reviewer access.**
- Sample mode reaches every free feature with no setup.
- Pro is reachable from Settings, History, Unclaimed, Home's Earlier draws card, and when
  adding a second holder.
- Restore purchases is on the Pro screen and in Settings.
- Tips are in Settings. The notification permission is asked only in context.
- Play App access answer "All functionality available without special access" is right:
  there is no login, and paid features are bought normally.
- One gap: earlier draws cannot be shown in sample mode, which has a single draw. The
  review notes cover this with a real-data test range.

**iPad.**
- `UIDeviceFamily` is [1, 2]. The iPad supports all four orientations and has no
  `UIRequiresFullScreen`, so it is multitasking-capable. A UIScene manifest is present, so
  the iOS 27 launch-crash pattern does not apply.
- The navigation rail layout is verified in the iPad captures, and `deviceNoun` gives
  iPad-correct copy.
- iPad 13" screenshots are planned and are mandatory for upload.

**Spam, copycat or misleading metadata.**
- The code is original, the icon is distinct, the name is unique (the iTunes search for
  "bondbell" finds no other app), and the copy is specific.
- There are no kid-audience terms (house §31), no prices in the name or subtitle, and no
  leaked AI-conversation lines. Both descriptions were read end to end as a customer would.
- Field lengths: iOS name 28, subtitle 26, keywords 98, promo 167, description 3042,
  review notes 3757. Play title 28, short 76, full 3097. All are within limits.
- Remaining risk is A-1 only.

---

## What a reviewer will ask, and our answer

1. **"Do you have permission to use NS&I's content?" (Apple 5.2.2)**

   > Bondbell does not host, copy or redistribute any NS&I content. When the user taps
   > Check, the user's own device downloads the winning-numbers file that NS&I publishes
   > for the public at nsandi.com/get-to-know-us/winning-bonds-downloads, exactly as the
   > user could in a browser. NS&I's site conditions permit downloading for personal use.
   > The comparison runs on the device, the file is deleted afterwards, and nothing passes
   > through a server of ours. The app identifies itself honestly to NS&I's server in its
   > user agent, states on four screens that it is independent of NS&I, and sends users to
   > NS&I to confirm and claim. [If S-1 option 1 is taken: All NS&I lists are free to
   > check; the one-time Pro unlock covers Bondbell's own features: multiple holders,
   > history and statistics.]

2. **"Is this gambling or a lottery?" (Apple 5.3, Play Real-money gambling)**

   > No. Premium Bonds are a UK government savings product sold by NS&I; holders keep
   > their capital, and the monthly prize draw is how interest is paid. Bondbell sells no
   > entries, takes no stakes, pays no prizes and contains no link to buy bonds. It only
   > checks numbers the user already owns against lists NS&I publishes.

3. **"Is this a financial service? (5.1.1(ix) / Financial features)"**

   > No. There is no account access, login, payment, transfer, trading or advice. The app
   > is submitted by Froggy Eye Ltd, a UK company.

4. **"Are you affiliated with NS&I?"**

   > No. The notice is shown in onboarding, on the Check tab, in Settings and in About, and
   > in both store descriptions. "Premium Bonds" is used only to say which product's
   > results the app checks. It is not used in the app name or icon.

5. **"What do the tips unlock?"**

   > Nothing. They are consumable thank-you payments through in-app purchase (Guideline
   > 3.1.1 allows tipping the developer). The app says so next to the buttons, and they
   > never appear on a no-prize result or in sample mode.

6. **"How do I test without real bonds?"**

   > On the last onboarding page, tap "Try with sample numbers", then "Check the latest
   > draw", then "Check the sample". To try a real check, enter any range, for example
   > 100AB100000 to 100AB100999.

7. **"Why is the privacy label 'Data Not Collected' when the app uses the network?"**

   > The only requests the app makes are downloads of NS&I's public files, and they
   > contain no user data (NS&I's server sees an IP address, as with any web request).
   > Purchases are handled by StoreKit or Play Billing. Bond numbers, names and results
   > stay on the device.

## First-submission approval estimate (after B-1 is closed)

- **Google Play: about 90%.** The realistic failure modes are a metadata or impersonation
  query about the NS&I and "Premium Bonds" wording (answer 4) and the Data safety caveat in
  A-5. Play's risk is a later IP complaint, not first review.
- **Apple: about 75%, or about 85% if Pro is re-gated per S-1.** The main risk is a 5.2.2
  documentation request (answer 1). Next comes a 2.1 query on the IAP screenshot if S-3 is
  missed. 4.1(c) on the name is a small residual.

*(First-pass verdict, superseded by the re-verification below: FAIL on B-1.)*

---

## Re-verification: 14 Nov 2026, HEAD c62ca56 (code at b4f1e5c)

Every item below was re-checked directly against live URLs, the source code and the rebuilt
artifacts, not taken from fix notes.

**Artifacts checked**
- `app-release.aab` was built at 18:08 and `Runner.app` (App.framework) at 18:09.
- `find lib -newer` returns nothing for either, so both builds contain the final code.
- The AAB is still signed by the upload key, SHA-1 `6F:08:…:C5`.
- The merged-manifest permission set is unchanged: no AD_ID, no alarm or
  foreground-service permissions.
- `Info.plist` is unchanged: `ITSAppUsesNonExemptEncryption=false`, no
  usage-description keys, `UIDeviceFamily` [1, 2].
- Neither binary contains the string "SCREENSHOT".
- The URL set in both binaries is identical to the first pass.

**Process note.** I ran `scripts/build_privacy_html.py --help`. The script ignores the
flag, so it regenerated `docs/privacy_policy.html` in the working tree. `git status` and
`git diff HEAD` show the output is byte-identical to HEAD. That incidentally proves the
Markdown source and the HTML are in sync. Nothing else in the repo was touched.

### Status of first-pass findings

| Item | Status | Evidence |
|---|---|---|
| **B-1** privacy and support URLs | **Resolved** | Privacy URL: `curl` returns 200 `text/html; charset=utf-8`, and the served file is byte-identical (`cmp`) to `docs/privacy_policy.html` at HEAD, which is generated from `PRIVACY_POLICY.md` with no diff (see the process note). Support URL: `https://bondbell.froggyeye.com/` returns 200 `text/html` and was read in full. It says "an independent app … not affiliated with, endorsed by or connected to NS&I", gives the Director of Savings attribution twice, uses no "official" or "approved" claim, has a working email contact, links the privacy policy, and its Free/Pro split matches the app exactly. |
| **S-1** Pro gates NS&I-data features (5.2.2) | **Accepted risk (founder decision, 14 Nov)** | Pro is unchanged: earlier draws and the all-bonds unclaimed search stay paid. It does not lead to certain rejection: the design keeps to NS&I's personal-use wording and there is live precedent on both stores. If a reviewer raises 5.2.2, use reviewer answer 1 above, without the bracketed re-gating sentence. If Apple insists, re-gating those two features to free is a one-build fix. The NS&I email for written comfort is still recommended. |
| **S-2** trade-mark owner | **Resolved** | `lib/core/constants/app_constants.dart:39-42` now reads "…Premium Bonds is a registered trademark of the Director of Savings." The same string is in `libapp.so` (arm64) and `App.framework/App`, and the old "trade marks of National Savings and Investments" string is gone from both. It matches the store descriptions and the support page word for word. |
| **S-3** IAP review screenshots | **Resolved in the procedure; capture pending** | `docs/IAP_PRODUCTS.md` now requires captures from a normal build showing Pro not owned, with price and buy button, and the tip jar. Taking them is a publish-stage task; check them before attaching. |
| **S-4** website before submit | **Resolved** | The site is live (B-1). |

### New since the first pass

**Sample mode opens every Pro feature on sample data: compliant on both stores, no
problem found.**

How it works (`ca1d081`):
- `proFeaturesProvider` is true when the user owns Pro **or** sample mode is on. It drives
  every feature gate: extra holders, earlier draws, the bulk unclaimed search, History, and
  the defence-in-depth `_gate()` in `check_session.dart`.
- `isProProvider`, the real entitlement, still drives the Pro screen and Settings, so the
  real buy button and price stay visible in sample mode.
- The Pro flag is never written.

The decisive point is what sample mode can reach:
- `drawSourceProvider` returns `SampleDrawSource` whenever sample mode is on, and that
  source reads only bundled, synthetic ZIPs.
- Holders and records are stored under `sample.*` keys through `dataScopeProvider`.
- So nothing a user does in sample mode reaches NS&I's real lists or the user's real bonds.
  Typing real bond numbers into a sample holder only checks them against made-up lists.
- No paid functionality is delivered outside in-app purchase. What sample mode gives is a
  labelled demo of the paid screens.

Against the rules:
- **Apple 3.1.1** ("own mechanisms to unlock content or functionality") is not triggered,
  because no real content or functionality is unlocked.
- **Apple 2.3.1** (hidden or undocumented features) is not triggered. The behaviour is
  disclosed in the banner, in the Pro screen note ("open to try on the sample data. To use
  them with your own bonds, unlock Pro"), in both store descriptions and in the review
  notes.
- **Apple 3.1.2** (time-limited trials) does not apply, because there is no time limit and
  no real use.
- **Google Play Payments** is not affected, because Play Billing remains the only way to
  get real Pro.
- **Google Play App access** is answered properly. "Yes (paid content), instructions only"
  with the sample-mode walkthrough is the right filing for a no-login app with paid
  features, and Play reviewers, who cannot buy, can reach every paid screen.

Apple reviewers can also buy in sandbox, so for Apple the demo is a convenience rather than
a dependency. Notes step 2 says the sample check finds "2 sample prizes worth £125"; that
matches `test/check_session_test.dart` and `check_result_test.dart`.

"Search 20,100 bonds" matches the sample holders: 20,000 + 50 + 50. The "October 2026
(sample)" and "September 2026 (sample)" draws exist in `SampleDrawSource.index`, and the
tip card is still hidden in sample mode (`result_view.dart:103`).

**Other new code matched against the policy and metadata**
- The privacy policy now describes the recovery copy (`vault.json.bak`, refreshed at each
  clean open), the damaged-file set-aside (`vault.json.corrupt-<ms>`) and exactly what
  "Delete all my data" removes. All of it matches `DataVault.open` and
  `deleteAllPrivateData()`, which clears `real.*` and `sample.*` and deletes the leftover
  files.
- The policy also matches the dialog text in `deleteAllDialogText`: holders, bond numbers
  and results are removed, including sample data; settings, reminders and Pro are kept.
- On iOS everything sits in the backup-excluded folder, as both descriptions and the
  policy say.

**Metadata re-read in full at HEAD**
- Files read: both descriptions, promo text, subtitle, keywords, review notes (3,809
  characters), the Play short description and changelog, `PRIVACY_POLICY.md`,
  `app_privacy_details.json` (`DATA_NOT_COLLECTED`) and `data_safety_answers.md` §11–12.
- The only description change is the TRY IT FIRST paragraph, which is accurate.
- Field lengths: iOS description 3,110 and Play description 3,165, both under 4,000. All
  other fields are unchanged and within limits.
- The banned-word and leaked-text grep finds nothing apart from known false positives: the
  disclaimer's "endorsed by", the review notes' "NOT GAMBLING" heading, and £125 inside the
  review notes, which are not public. Read end to end as prose, there are no
  conversational artefacts.

#### New Should-fix

**S-5. One review-note sentence is now false.**
- `ios/fastlane/metadata/review_information/notes.txt` line 6 says: "(Later, Settings >
  'Sample mode' turns it on; **there is no sample button on the Check tab**.)"
- Commit `b4f1e5c` added a "Try with sample numbers" button to Home, which *is* the Check
  tab (`home_screen.dart:110`), and the Play instructions rely on it.
- A false statement to the reviewer is not a rejection reason in itself, but it is exactly
  the kind of mismatch that makes a reviewer distrust the rest of the notes.
- **Fix (metadata only, no rebuild):** replace the bracket with "(Or later: 'Try with
  sample numbers' on the Check tab, or Settings > 'Sample mode'.)". It costs about the
  same number of characters, so the notes stay well under 4,000. Optionally, add the Check
  tab button to `data_safety_answers.md` §11 step 1 as well.

#### New Advisory

**A-9.** The support page's App Store and Google Play badges link to `#`. That is fine
before launch. Point them at the live listings once each store approves.

A-6 is carried forward: check the newest History row's label when capturing store
screenshot 6. The Should-fix and Advisory items do not block submission.

### Updated first-submission approval estimate

- **Google Play: about 92%.** Every App content declaration is filed, the URLs are live,
  and reviewers can reach all paid content without buying.
- **Apple: about 78%.** The single largest risk is the accepted S-1, a possible 5.2.2
  request for authorisation. Answer it with reviewer answer 1, and re-gate those two
  features if Apple insists. The other risks are small: a 4.1(c) name query, or a review
  screenshot that does not show the locked Pro state.

Verdict: PASS
