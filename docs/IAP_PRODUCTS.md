# Bondbell: in-app products (both stores)

Written 14 Nov 2026 for the publish stage. Product IDs are fixed in
`lib/core/constants/app_constants.dart`; display names match the labels the app shows
(`ProScreen`, `TipJarCard`). Prices are set in GBP and auto-converted by each store
(ASO §7). The app always shows the store's own `ProductDetails.price`, so nothing in
the app needs to change if a store rounds a converted price.

Limits used: iOS display name ≤30, iOS description ≤45; Play title ≤55, Play
description ≤200. Counts below are characters as stored (no trailing newline).

| | Bondbell Pro | Small tip | Medium tip | Large tip |
|---|---|---|---|---|
| Product ID (both stores) | `com.froggyeye.bondbell.pro` | `com.froggyeye.bondbell.tip.small` | `com.froggyeye.bondbell.tip.medium` | `com.froggyeye.bondbell.tip.large` |
| Type | Apple: Non-Consumable · Play: one-time product | Apple: Consumable · Play: one-time product (consumed in app) | same | same |
| Price (GBP, incl. VAT) | £4.99 | £1.99 | £4.99 | £9.99 |
| Reference name (Apple, internal) | Bondbell Pro | Tip small | Tip medium | Tip large |
| Display name (Apple, en-GB) | Bondbell Pro (12) | Small tip (9) | Medium tip (10) | Large tip (9) |
| Description (Apple, en-GB) | Unlimited holders, earlier draws and stats (42) | Optional thank-you. Unlocks nothing. (36) | Optional thank-you. Unlocks nothing. (36) | Optional thank-you. Unlocks nothing. (36) |
| Title (Play, en-GB) | Bondbell Pro (12) | Small tip (9) | Medium tip (10) | Large tip (9) |
| Description (Play, en-GB) | see below (158) | see below (122) | see below (122) | see below (122) |

Play descriptions:

- **Pro:** `One-time unlock, no subscription. Adds unlimited holders, earlier draws NS&I still lists, unclaimed search for all saved bonds at once, and history and stats.` (158)
- **Each tip:** `An optional tip to say thank you to the developer. Tips are a thank-you only: they unlock no features, content or results.` (122)

Family sharing (Apple): leave **off** for all four. Consumables cannot use it, and
turning it on for Pro is irreversible; it can be a later decision.

## App Review notes and review screenshots

Apple requires a review screenshot per product (any honest capture of the purchase
UI). Use the Pro screen (`docs/build_evidence/ios_iphone_09_pro.png`) for Pro and a
fresh capture of the Settings Tip jar card with its three buttons for the tips
(`ios_iphone_08_settings.png` cuts the card off above the buttons, and the products did
not exist yet, so capture it at the publish stage once they load from the store).

**Bondbell Pro, review note:**

```
Non-consumable unlock, no subscription. Unlocks: unlimited holders (free: one),
checking any earlier month NS&I lists (free: latest draw), unclaimed-prize search
across all saved bonds at once (free: one number at a time), and the History tab.
Reach it from Settings > "See what Pro adds", the History tab, or by adding a second
holder on My bonds. "Restore purchases" is on the Pro screen and in Settings. To test
without real bonds, tap "Try with sample numbers" in onboarding.
```

**Tips (same note for small, medium and large):**

```
Optional consumable tip. It unlocks nothing and changes nothing in the app; the app
says so next to the buttons ("Tips don't unlock anything"). Shown in the Tip jar card
in Settings, and once as a quiet card under a real result that lists prizes. It is
never shown on a no-prize result or in sample mode, so it cannot read as paying to
change a result.
```

## Store-side caveats to check at creation

- Play: a product can be created only once a build with the BILLING permission is
  active in a track (house-facts §18); internal testing counts.
- Apple: Pro must be added to the 1.0.0 submission from the IAP's own page ("Add for
  Review"); verify the submission lists the version plus the IAPs before sending
  (house-facts §15). Tips are consumables and also need review with the first version
  if they are to be live at launch.
