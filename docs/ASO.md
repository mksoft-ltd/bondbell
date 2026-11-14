# Bondbell: ASO and store positioning

Written by growth-monetization on 14 Nov 2026 for the metadata stage (release-manager).
Store data was fetched live on 13 and 14 Nov 2026 from the iTunes Search API
(GB and US storefronts) and from Google Play's search and listing pages (`gl=GB`).
Any line marked **(inference)** is my judgement and was not measured.

Fixed inputs, decided by the founder:

- Store title: **Bondbell: Bond Prize Checker**. Both stores have accepted it.
- Business model: a free app, a one-time Pro unlock at £4.99, and a consumable tip jar.
- Devices: iPhone and iPad.
- "Premium Bond(s)" may be used descriptively in the iOS subtitle, the keyword
  field and both descriptions. It must never appear in the name or the icon,
  and every use must sit alongside the not-affiliated notice.

---

## 1. Positioning in one line

An independent checker for UK Premium Bond numbers. It needs no login, and
your numbers stay on your device. It also works for a relative's old paper
certificates, and it searches the unclaimed-prizes list.

Every word of store copy must stay within what the app does
(`docs/PRODUCT_SPEC.md`):

- It saves ranges.
- It downloads NS&I's public lists onto the device when the user taps.
- It checks the latest draw (free), or any of the roughly six listed months (Pro).
- It searches unclaimed prizes: one number at a time free, all saved ranges in Pro.
  - The unclaimed list gives the prize value only. **It has no draw date per number**, so copy must never say "find out which month you won it".
- It sets a results-day reminder. This is a reminder that results are due, **not** an alert that you have won.
- It keeps history and stats (Pro).

---

## 2. Live evidence: what the searches show

### App Store, GB storefront

| Query | Page-one results | Reading |
|---|---|---|
| `premium bond` / `premium bonds` | 1. NS&I "Premium Bonds prize checker" (1,363 ratings, 2.6★, last updated **28 Nov 2024**) · 2. NS&I main app (327 ratings, 1.6★) · HMRC · **Numo – Premium Bonds & Savings (0 ratings)** · Pakistani and Bangladeshi prize-bond checkers · MoneySavingExpert · Trading 212 | There is huge proven demand, and the only real competitor is a stale, badly rated official app. No well-rated third-party checker exists. **This is the primary target.** |
| `premium bonds checker` | The official checker, the NS&I app, MoneySavingExpert, then Pakistan prize-bond apps from position 4 | Winnable. Our title already supplies "checker". |
| `bond checker` / `bond prize checker` | The official checker, then **Pakistani and Bangladeshi prize-bond checkers** at positions 2–4, and the National Lottery and BOTB further down | The shelf is nearly empty for a UK audience. Our title matches it exactly. |
| `prize checker` | The official checker, the NS&I app, a Pakistan bond app, then the National Lottery, Solitaire Clash and Elite Competitions | Mixed intent. Some of the traffic is lottery and competition players. The title covers this query, so spend no more keyword weight on it. |
| `unclaimed premium bonds` | The official checker, then **foreign bond-investment apps** (IndiaBonds, Bonds PH, YieldGimp, BondbloX) | Empty for our intent. It is a high-intent query and the shelf is free. |
| `ernie` | The official checker, then **ErnieApp** (an unrelated data-privacy app with 4 ratings), Ernie Sports, a Chinese AI app | The shelf is empty, but see §4 for why we still leave "ernie" out. |
| `premium bond odds` | The official checker, then bond-yield and trading apps | This is odds and calculator intent, and the app does not calculate odds. **Do not target it.** |
| `bond numbers` | **Children's maths "number bonds" apps** (Squeebles, Number Bonds KS1…) | **Intent trap.** Never use "bond numbers" as a phrase in the subtitle. |
| `bondbell` (GB and US) | No app with this name. The only result is "BondItSFA" (GB); US returns nothing. | The name is clean. |

### Google Play, GB

| Query | Ranked packages (top 8) | Reading |
|---|---|---|
| `premium bonds checker` | `com.nsandi.nsiPrizechecker`, `com.nsandi.transactapp`, then Pakistani and Bangladeshi bond apps, Revolut and a wallet app. **The third-party "Premium Bonds Prize Checker +" is not in the top 8.** | Weak. A clear title-plus-description match should rank (inference). |
| `bond checker` | NS&I checker, Pakistani bond checkers ×5, NS&I app | Same as iOS. Pakistan vocabulary fills the shelf. |
| `unclaimed premium bonds` | NS&I checker, NS&I app, `com.steveh.pbcp`, then a Pakistan bond app, National Bonds (UAE), a council waste app, a bill-splitting app | Empty after position 3. |
| `ernie premium bonds` | NS&I checker, NS&I app, `com.steveh.pbcp`, then unrelated apps ("Beyond Bonds" is a social app, "Blessed by Bonds" is a faith app) | Empty after position 3. |
| `prize checker` | NS&I checker, NS&I app, Pakistan and Bangladesh bond apps, Discord, PhonePe | Weak. |

---

## 3. iOS metadata

### Subtitle (limit 30)

**`Premium Bonds draw results`**: **26 characters**

- It adds the three words most worth indexing that the title lacks: *premium*, *bonds* (the title already has the singular "Bond") and *draw* / *results*. Queries such as "premium bonds results", "premium bonds draw" and "premium bond draw results" then match across the title and subtitle.
- It is descriptive, not a claim: the app checks NS&I's draw results. It does not say "official", "win" or "alerts".
- It reads well under the title: *Bondbell: Bond Prize Checker / Premium Bonds draw results*.
- The privacy hook ("No login…") goes in screenshot 2 and the promotional text instead, because the words "login" and "no" carry little search value.

Variant to test later: `Check Premium Bonds results` (**27**). This variant moves "check" into the subtitle and "draw" into the keywords. Changing the subtitle requires a new version, so try it only if the 30-day data says the first wording is underperforming (see §9).

### Keyword field (limit 100; commas, no spaces)

```
unclaimed,winning,numbers,won,check,winners,list,tracker,certificate,savings,reminder,old,month,uk
```

**98 characters** (counted by script). There are 14 terms and no duplicates.

None of these words appears in the title or subtitle. Those already index *bondbell, bond, prize, checker, premium, bonds, draw, results*.

| Term | Query it completes (with title/subtitle words) | Why it is honest |
|---|---|---|
| unclaimed | "unclaimed premium bonds", "unclaimed prizes" | Built feature (Unclaimed tab) |
| winning, numbers, winners, list | "premium bonds winning numbers", "premium bond winners list" | The app checks NS&I's lists of winning numbers |
| won | "have I won premium bonds" (natural phrasing) | It answers that question for saved bonds |
| check | "check premium bonds" | The core action |
| tracker | "premium bonds tracker" | It saves holdings and keeps history |
| certificate, old | "old premium bond certificate" | It supports old paper certificates (screenshot 4) |
| savings | "premium bonds savings" | Descriptive |
| reminder, month | "premium bonds reminder", "this month's draw" | Results-day reminder, monthly draw |
| uk | "premium bonds uk" | UK product |

Words deliberately left out:

- **"ernie", "nsandi", "NS&I", "national"**: see §4.
- **"lottery", "jackpot", "millionaire"**: it is not a lottery, and these words sell the dream of winning (BRAND.md tone rules).
- **"odds", "calculator"**: the app does neither.
- **"alert"**: users would read it as a win alert.
- **"login"**: low value.
- **"prizes"**: the plural of a word already in the title.
- **"probate", "inheritance"**: the app helps a family check a relative's bonds, but it is not an estate tool, and the traffic would be mismatched (inference).

Known side effect: "numbers" plus the title's "Bond" can surface Bondbell for children's "number bonds" searches. Those are impressions that never convert. The cost is a slightly lower conversion rate, which is acceptable for the "winning numbers" queries we gain. If iOS conversion looks diluted in App Analytics, drop "numbers" first.

### Promotional text (limit 170; editable without a new version)

> `No login, no account. Save your Premium Bond numbers once, including old paper certificates, and check each draw on your device. Independent; not affiliated with NS&I.`

**167 characters.**

### Category

- **Primary: Finance. Secondary: Utilities.** Reasoning is in §6.

---

## 4. "ernie" and "NS&I" in metadata: recommendation

**Recommendation: leave both out of every keyword field and short-text field on both stores.** Name NS&I only where honesty requires it:

- the not-affiliated notice;
- the sentence saying where the data comes from ("downloads NS&I's public winners lists to your device").

Do not use "ERNIE" anywhere in store copy.

- **Apple, guideline 2.3.7** tells developers not to pack metadata with "trademarked terms, popular app names … or other irrelevant phrases just to game the system".
  - NS&I's site states that "National Savings and Investments®, NS&I® and Premium Bonds®" are registered to the Director of Savings, and that the list is not exhaustive.
  - "Premium Bonds" passes a nominative test: there is no other way to say which bonds the app checks, and the founder has accepted the risk.
  - "NS&I" as a keyword passes no such test. It is the publisher name of the competing official app, so it is exactly the "popular app name" case.
  - "ERNIE" is not needed to describe the app. I could not confirm whether it is registered, and NS&I's list is "not limited to" the marks it names. Its only purpose would be to catch nickname searches, and a small, empty shelf (§2) is not worth a 2.3.7 rejection or an NS&I complaint.
- **Google Play metadata and impersonation policies** ban misleading or irrelevant keywords, repeated brand terms, and anything that implies affiliation with another brand.
  - Naming NS&I once, as the data source and in the disclaimer, is the factual minimum.
  - Putting "NS&I" or "ERNIE" in the short description, or repeating them in the long description, would read as borrowing their brand.
- **Upside lost (inference): small.** People who search "ernie" mostly want NS&I itself. The `premium bonds` and `unclaimed premium bonds` queries carry the volume, and we cover both.

Disclaimer wording for both long descriptions. Use it once, near the end, not as small print:

> Bondbell is an independent app and is not affiliated with, endorsed by or connected to NS&I (National Savings and Investments). Premium Bonds is a registered trademark of the Director of Savings. Results come from the public lists NS&I publishes; always confirm a prize with NS&I before relying on it.

---

## 5. Google Play metadata

### Short description (limit 80)

**`Independent Premium Bond checker. No login; your numbers stay on your phone.`**: **76 characters**

- It leads with "Independent", which makes the non-affiliation clear in the most visible text field.
- It carries "Premium Bond checker", the head query.
- It states the privacy difference as a fact.
- The short description can be changed at any time, so the variant below can be tried without a release.

Variant B, to try second: `Check Premium Bond numbers for prizes, unclaimed ones too. No login needed.` (**75**). This puts the unclaimed hook first, but loses the word "Independent".

### Long description: themes it must work in naturally

Play indexes the long description. Each theme below should appear in plain sentences, a few times across about 2,000–3,000 characters, never as a keyword list.

1. **Premium Bond prize checker**. Use "Premium Bond numbers" and "check your Premium Bonds" two or three times in total. No more, so it never reads as stuffing.
2. **Results day and the monthly draw**. Results are due the day after the first working day of each month, and an optional reminder is sent that morning.
3. **Unclaimed prizes going back to 1957**. Explain that the list shows the prize value but not the month it was won, and that the user claims through NS&I.
4. **Old paper certificates and family members**. Ranges or single numbers can be saved for parents or grandparents. One holder is free; Pro allows any number.
5. **No login, no account, nothing uploaded**. The phone downloads NS&I's public list, checks it on the device, keeps only the matches, and deletes the file. There is no tracking, no ads and no analytics.
6. **How to claim**. Every result points the user to NS&I to confirm and claim.
7. **Free vs Pro**. Pro is one payment of £4.99 and covers unlimited holders, the earlier listed months (about six), searching all saved ranges in the unclaimed list, and history and stats. Use the store's price wording and do not hard-code any non-GBP figure.
8. **Tip jar**. It is optional and unlocks nothing.
9. **Disclaimer** (from §4).

Words that are banned in both descriptions:

- official, approved, endorsed, partner;
- ERNIE;
- "never miss a prize";
- "find out if you've won" phrased as a promise (say "check whether your numbers are on the list" instead);
- odds, returns, instant, fastest;
- winning streaks, jackpot imagery;
- any currency amount other than the Pro price;
- anything about the month of an unclaimed prize.

The iOS description follows the same themes. iOS does not index the description, so write it for conversion, not keywords.

---

## 6. Categories

| Store | Primary | Secondary |
|---|---|---|
| App Store | **Finance** | **Utilities** |
| Google Play | **Finance** (one category only) | — |

**Why Finance:**

- Both direct competitors are in Finance:
  - the NS&I checker on both stores;
  - Numo on iOS;
  - Prize Checker + on Play.
- Users think of Premium Bonds as savings, and Play's "similar apps" and browse surfaces group apps partly by category (inference).
- In Utilities we would sit next to the Pakistani prize-bond checkers, whose own category was Utilities on iOS. That is the wrong neighbourhood for a UK savings audience.
- Chart rank is not a factor either way. The UK Finance top charts are banks with 100k+ ratings, and a new app will not chart in Utilities either (inference).

**Extra scrutiny Finance brings, and how to handle it:**

- **Apple.** No extra form is needed for the category. However, Finance apps that mention a bank are more likely to be checked against guideline **5.1.1(ix)**, which requires apps offering services in regulated fields such as banking to come from the institution itself.
  - Bondbell offers no financial service: no account access, no purchase of bonds, no advice.
  - The App Review notes should say so in one paragraph:
    - it checks the public lists NS&I publishes, on the user's device, on the user's tap;
    - there is no login and no NS&I account access;
    - it is not affiliated with NS&I.
  - The notes should also say that Premium Bonds are a government savings product and not gambling, and that the app sells no draw entries. This heads off a gambling (5.3) question.
  - This risk exists in either category, because the content is about an NS&I product. Finance only makes the reviewer's lens a little more likely (inference).
- **Google Play.** Complete the **Financial features declaration** under App content, and choose the option for an app that provides none of the listed financial features. Release-manager should check the exact wording in the console; I did not open it.
  - The personal-loan and financial-services licence requirements apply only to apps that offer those services, which Bondbell does not.
  - Answer "no gambling" in the content-rating questionnaire (IARC), because the app offers no real-money or simulated gambling.

---

## 7. Pricing confirmation and regional notes

- **Pro (non-consumable), `com.froggyeye.bondbell.pro`: £4.99.** Confirmed. This is the house default (a one-time unlock), and it is the clearest point of difference from Prize Checker +, which charges a subscription (one of its own reviews complains about the subscription).
  - "Pay once" suits an audience that skews older and dislikes subscriptions (inference).
  - The monthly draw already brings users back without a subscription.
- **Tips (consumables): £1.99 / £4.99 / £9.99** under `com.froggyeye.bondbell.tip.small` / `.medium` / `.large`. Confirmed.
  - The copy must keep saying that tips unlock nothing.
  - The quiet card under a real win must not suggest that tipping affects results or future draws.
  - Never show the tip card on a no-win result, so that it never reads as "pay to improve your luck".
  - The spec already hides tips in sample mode.
- **What a sale earns (corrected from my scout estimate, which forgot VAT):**
  - The £4.99 UK price includes 20% VAT, which leaves £4.16. After the 15% small-business commission the studio receives **about £3.53 per Pro sale**.
  - A £4.99 tip earns the same. A £1.99 tip earns about £1.41.
  - On that basis the scout's upper revenue estimate of about £150/month becomes **about £125/month** for the same volume.
- **Regions:**
  - Set GBP as the base price on both stores and **let each store auto-convert other currencies**.
  - Bondbell is useful only to Premium Bond holders. Outside the UK, the buyers are UK expats who already hold bonds (inference). Hand-picked round prices in foreign currencies are not worth the console work, and they would need maintaining.
  - Make the app available in all territories: it costs nothing, and NS&I's site served the downloads page normally to a plain request.
  - Write metadata in **en-GB only**. The US storefront has no Premium Bond audience, so do not localise for en-US.
  - Price changes later: the Pro unlock is not a subscription, so on Apple a change has no consent flow. Lower prices for a sale only if a test calls for it, and never show strike-through prices in the app (BRAND.md).

---

## 8. Competitor profile

All figures were fetched on 13–14 Nov 2026 and use the names exactly as the stores list them.

| App (store listing name) | Publisher | Store(s) | Ratings | Installs | Last update | Model | What it does / gap |
|---|---|---|---|---|---|---|---|
| **Premium Bonds prize checker** | National Savings & Investments | iOS (id 474172893, Finance) · Play `com.nsandi.nsiPrizechecker` (Finance) | iOS 1,363 at 2.6★ · Play 2,803 at 3.6★ | Play 1,000,000+ | iOS 28 Nov 2024 · Play 20 Nov 2024 | Free | Checks by **holder's number or NS&I number**. Its description says it asks for consent to collect usage data. It cannot check paper bonds when the user doesn't know the holder's number. The listing is stale and badly rated. |
| **NS&I** | National Savings & Investments | iOS (Finance) · Play `com.nsandi.transactapp` | iOS 327 at 1.6★ · Play 2,155 at 1.3★ | Play 500,000+ | Oct 2026 | Free | Account app with prize history. Needs a full NS&I account login. |
| **Premium Bonds Prize Checker +** | pbcpdev | Play only, `com.steveh.pbcp` (Finance). Not found on iOS GB. | 94 at 4.0★ | 10,000+ | 4 Oct 2026 | No ads; in-app purchases, which a user review describes as a subscription | The only third-party checker with traction. Its short description says it "even shows how close they were to winning". **Do not copy that angle**: it is a winning-adjacent claim BRAND.md rules out. |
| **Numo – Premium Bonds & Savings** | Utkarsh Shigihalli | iOS (Finance) | 0 | — | 6 Jan 2026 | Free | A savings, AER and mortgage calculator that also tracks Premium Bonds. Not a draw checker. |
| Pakistani and Bangladeshi prize-bond checkers (e.g. "Prize Bond Checker – Pakistan", `com.pak_bond_checker`) | various | both | iOS 0–5 ratings · Play up to 50,000+ installs | — | 2026 | Free | A different country's product. They fill the "bond checker" shelf and are not competitors for UK users, but our screenshots and first line must make "UK Premium Bonds" obvious. |

---

## 9. What to measure in the first 30 days

The app has no analytics SDK (house rule). Everything below comes from the store consoles or from manual rank checks.

**Dates to watch (from the app's own results-day rule):**

- **Wed 2 Dec 2026**: results day.
- **Tue 5 Jan 2027**: the next results day. 1 Jan is a bank holiday and 4 Jan is the first working day.

Expect searches and installs to spike on each results day (inference). Read the metrics around these days, not as daily averages.

| Metric | Source | Why / decision it drives |
|---|---|---|
| Rank for `premium bonds`, `premium bonds checker`, `premium bonds results`, `unclaimed premium bonds`, `bond checker`, `prize checker`, `premium bonds winning numbers` | iTunes Search API (`country=gb`, limit 25) and Play search (`gl=GB`). Check weekly, plus on 2 Dec. | If iOS ranks below 10 for `premium bonds` after two weeks, ship subtitle variant `Check Premium Bonds results` in the next version. |
| Impressions → product page views → downloads, split by source (App Store Search vs Browse) | App Store Connect App Analytics | A low impression-to-view rate points at the icon and title. A low view-to-download rate points at screenshots 1–2. |
| Play store listing acquisition and the **search terms report** | Play Console, Store performance | Play names the actual queries. Fold any strong unexpected term into the long description. Try short-description variant B through Play's store listing experiments. |
| Pro conversion = Pro units ÷ first-time downloads | ASC Sales and Trends · Play Console Orders | Target **3% or better** by day 30. Under 1.5% means the free tier gives too much away, or the paywall is not seen. Review the Pro screen rather than changing the price. |
| Tips: count and total | Same | The tip jar is a bonus, so nothing depends on it. If tips outnumber Pro sales, the tip card is too prominent relative to Pro. |
| Ratings and review text | Both consoles | **Most important early signal.** Any "Bondbell said no prize but NS&I says I won" (or the reverse) is a correctness emergency for the scan engine. Reply to every review. |
| Crashes, ANRs, app hangs | Play Vitals · Xcode Organizer | The scan is a 33MB download plus an 82MB parse, and no physical device has been measured yet (spec). |
| Play uninstall rate within 7 days | Play Console | High churn after a no-win result is expected (inference). Churn before any check suggests onboarding friction. |
| Refunds | ASC / Play | Rising refunds suggest Pro is being bought for a feature the user misunderstood, for example expecting the unclaimed search to show the month a prize was won. |

Possible next step to raise ratings: the app has **no review prompt yet**. Adding a native in-app review prompt, shown only after a completed check, is the cheapest lever for ratings volume. This is not built; it is a recommendation for the conductor.
