# Play Console answer sheet: Bondbell (com.froggyeye.bondbell)

Play app id `4974856772682329433`, default language en-GB. Everything on this sheet is
console-only (`supply` cannot upload it). Written 14 Nov 2026 against the code in `lib/`
and the merged release manifest. Where the console's exact current wording was not
checked live, the line says **(verify wording)**; answer by meaning, not by matching
the quoted text.

Facts the answers rest on (verified in code):

- No analytics, ads, crash-reporting or tracking SDKs in `pubspec.yaml`; no accounts;
  no backend. All persistence is `shared_preferences` on the device.
- The app's own network traffic is `http` GETs/HEADs to `https://www.nsandi.com` only
  (`lib/features/draws/data/draw_source.dart`), started by the user (check a draw,
  "Show available draws", unclaimed search). Nothing is sent but the request itself
  and the user agent `Bondbell/1.0.0 (Android; personal bond checker;
  +https://bondbell.froggyeye.com)`. Bond numbers are never transmitted. The file is
  deleted after the scan.
- Play Billing (via `in_app_purchase`) queries prices and restores purchases at launch;
  Google processes that, not us. The Play Billing library also sends Google its own
  telemetry (security audit, fix round 2). So never write "the app contacts nothing but
  NS&I": the app's own requests go only to nsandi.com, and Google's billing library
  talks to Google.
- Android backup and device transfer are disabled (`allowBackup=false` plus
  `data_extraction_rules.xml`).
- Merged release manifest permissions: `INTERNET`, `ACCESS_NETWORK_STATE`,
  `com.android.vending.BILLING`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
  `VIBRATE`, `com.froggyeye.bondbell.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
  None of these has a Play declaration form. There is **no** `SCHEDULE_EXACT_ALARM`,
  `USE_EXACT_ALARM`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE_*`, photo/video,
  location or `AD_ID` permission, so **do not file** any of those declarations.

---

## 1. Data safety (App content > Data safety)

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| (Every data-type category) | Leave all unchecked |
| Privacy policy | `https://mksoft-ltd.github.io/bondbell/privacy_policy.html` (must return 200 text/html before submission) |

With "No", Play skips the encryption-in-transit and deletion questions. If the form
still shows them **(verify wording)**: encrypted in transit = **Yes** (HTTPS only);
deletion request = not applicable, nothing is collected; on-device data is removed in
Settings > "Delete all my data" or by uninstalling.

Why "No" is right, so nobody "fixes" it later:

- **Bond numbers, holder names, results:** stored only on the device and never
  transmitted. Play counts data as collected only when it leaves the device.
- **The nsandi.com request:** a user-initiated download of a public file, like a
  browser loading a page. It carries no user data type from Play's list. The IP
  address NS&I's server sees is inherent to any connection and is not data the app
  collects or shares.
- **Purchases:** handled by Google Play Billing. Purchase history held by Google is
  not developer collection. The billing library's telemetry goes to Google for
  Google's own purposes (Play Billing is part of Google Play, not a third-party SDK
  added for our use), and we receive none of it. If Google's Play Billing data-safety
  guidance changes and asks apps to declare it, revisit this answer.
- **Notifications:** scheduled locally; no push token, no FCM.

## 2. Advertising ID

| Question | Answer |
|---|---|
| Does your app use advertising ID? | **No** (no `AD_ID` permission in the merged manifest) |

## 3. Ads

| Question | Answer |
|---|---|
| Does your app contain ads? | **No, my app does not contain ads** |

## 4. App access

| Question | Answer |
|---|---|
| Access | **All functionality is available without special access** (no login, no account) |

## 5. Content rating (IARC questionnaire)

| Question | Answer |
|---|---|
| Email for IARC | info@froggyeye.com |
| Category | **All other app types** (not Game; not Reference/News/Educational) **(verify wording)** |
| Violence, fear, sexuality, nudity, language, drugs, alcohol, tobacco | **No** to all |
| Crude humour, hate speech, discrimination | **No** |
| Gambling: real-money gambling, or simulated gambling | **No.** Bondbell takes no stakes, sells no entries and pays no prizes; it checks published results of a government savings product. Premium Bonds are a savings product: the holder never risks the money they put in. |
| Does the app reference or promote gambling? | **No** (same reasoning; it references a savings product's prize draw) |
| Users can interact or exchange content (chat, UGC, sharing) | **No** |
| Shares the user's physical location with other users | **No** |
| Allows users to purchase digital goods | **Yes** (one non-consumable unlock and three consumable tips) |
| Unrestricted internet / web browser | **No.** It downloads specific files from nsandi.com; links open the user's own browser. |

Expected result: Everyone / PEGI 3 / USK 0 (or equivalent), with an "In-App Purchases"
interactive element. If the result differs, re-read the gambling answers before
changing anything; never answer "simulated gambling: Yes" to move the rating.

## 6. Target audience and content

| Question | Answer |
|---|---|
| Target age groups | **18 and over** only |
| Could the app unintentionally appeal to children? | **No** (plain finance utility, no characters, no games, no child-oriented art) |
| Designed for Families / Teacher Approved | **Do not opt in** |

Premium Bonds can be held from age 16 in the holder's own name, so ticking 16–17 as
well would also be honest. The listing is written for adult savers and families
managing a relative's bonds, so 18+ alone is the cleaner choice. Do not tick any band
under 13: that pulls in the Families policy for no benefit.

## 7. Financial features (App content > Financial features)

| Question | Answer |
|---|---|
| Which financial features does your app provide? | Select the option for **none of the listed features** **(verify wording)** |

Bondbell offers no banking, loans, payments, money transfers, investment trading,
crypto, insurance, financial advice or account access. It reads public prize lists.
If the console instead lists features to tick, tick none. Do not pick "investment" or
"savings account" features: the app does not provide them, it only checks results.

## 8. Other declarations

| Declaration | Answer |
|---|---|
| Government apps | **No.** Not developed by or on behalf of a government; independent of NS&I |
| News apps | **No** (not a news app) |
| Health apps | **No health features** (select none) |
| COVID-19 contact tracing / status | **No** / not applicable |
| Data safety: account deletion URL | Not applicable (no accounts); the form should not ask once "No accounts" is implied by section 1 **(verify)** |
| Photo and video permissions, exact alarms, full-screen intent, foreground services | **Not filed** (no such permissions; see the top of this sheet) |

## 9. Store settings and listing contact

| Field | Value |
|---|---|
| App or game | **App** |
| Category | **Finance** |
| Tags | Choose up to five that describe a savings/finance utility if offered (for example "Personal finance", "Savings"); none that suggest banking or investing products the app does not provide **(verify available tags)** |
| Contact email | info@froggyeye.com |
| Website | https://bondbell.froggyeye.com (must be live before submission; fallback https://froggyeye.com) |
| Phone | Leave blank (optional on Play) |
| External marketing | Leave on (default) |

## 10. Pricing and distribution

- Free app; IAP products as in `docs/IAP_PRODUCTS.md`.
- Countries: all available (ASO §7). The en-GB listing is the only locale; write
  release notes for en-GB only (house-facts §19).

## 11. Optional reviewer note (if the console offers a notes field)

```
Bondbell checks a user's own UK Premium Bond numbers against the prize lists NS&I
publishes on nsandi.com. The download happens on the device at the user's tap; bond
numbers never leave the device. No login, no account, no ads, no analytics. It offers
no NS&I account access and no financial service; Premium Bonds are a government
savings product, not gambling, and the app sells no entries. To see the full flow,
tap "Try with sample numbers" on the last onboarding page, then "Check the latest
draw" > "Check the sample". Bondbell Pro (one-time unlock) and three optional tips
(unlock nothing) are in Settings. Independent; not affiliated with NS&I.
Contact: info@froggyeye.com
```
