# Bondbell: store screenshot spec

Six screenshots per device class, in marketing order. The first two carry the
hooks, because most store visitors never swipe further. Every image is a **real
capture** of the app. Nothing in a screenshot is generated, and the framing
adds only the plate and the headline. Brand rules are in `BRAND.md`.

## Capture setup (for the capture stage)

| Store set | Device / emulator | Raw capture | Framed output |
|---|---|---|---|
| App Store iPhone 6.9" | iPhone 17 Pro Max (or any 6.9" sim) | native | **1320 × 2868** |
| App Store iPad 13" | iPad Pro 13" (M4/M5) | native, portrait | **2064 × 2752** |
| Google Play phone | Pixel-class emulator, 1080 × 2400 | native | **1080 × 1920** (9:16) |

- Build with `--dart-define=SCREENSHOT_MODE=true` (debug or profile). This skips onboarding, turns on sample mode, unlocks Pro, and seeds the sample holder (£20,050: range `312KM100000–312KM119999` plus old certificate `47DW185520–47DW185569`) and six months of sample history.
- All numbers on screen are made up, and the app shows its own **"Sample mode: made-up numbers, not real results"** banner. Leave the banner in every shot where the app shows it: it is honest, and it is part of the real UI.
- Use light theme and the default text size. Set the status bar to 09:41 with full battery (`xcrun simctl status_bar … override`; Android demo mode).
- Shot 2 needs a **fresh install without SCREENSHOT_MODE**, because onboarding is skipped in that mode. Launch, swipe once, and capture onboarding page 2.

## The six shots

The `Headline` is what the plate shows, set by the framing script. Where the iPad wording differs, both are given.

| # | Screen and exact state | Headline (all stores) | Subheadline |
|---|---|---|---|
| 1 | **Result**: `/check/draw/latest` after the sample check finishes (tour stop 2). Top of the page: the "Congratulations!" card with the sample holder's two rows. Scroll position 0. | **Your bond prizes, checked for you** | Saved once. Checked on your device. |
| 2 | **Onboarding page 2**, "Your numbers stay on this phone" (lock icon), fresh install, page dots on 2 of 3. | iPhone and Android: **No login. Your numbers stay on your phone.** iPad: **No login. Your numbers stay on your iPad.** | No account, no tracking. |
| 3 | **Check (home)**: `/home` at the top, showing the "Next results expected in N days" hero card, the latest-draw card and the "Remind me on results day" card. | **Know when new results are due** | One reminder a month. Nothing else. |
| 4 | **Holder**: `/holder/sample-holder`, the sample holder's two entries (statement range and old certificate) with counts. | **Old paper certificates? Add them too** | Ranges or single numbers. |
| 5 | **Unclaimed**: `/unclaimed` at the top, with the intro text, the "Search one bond number" card and the "Search all my bonds" card. | **Look for prizes never claimed** | Back to 1957. |
| 6 | **History (Pro)**: `/history` at the top, showing the four stat tiles and the yearly-rate card with its "not financial advice" note fully visible. | **Every draw you've checked, together** | Part of Bondbell Pro. |

Notes per shot:

- **Shot 1** is the hook, but the result card shows sample prize amounts. The headline makes no claim about winning; it says the checking is done for you. The subheadline must not change to anything about odds or winning.
- **Shot 2** is the required privacy point. The headline says only what is true of the app: no login, no account, and the comparison is on the device. On the iPad set, "phone" becomes "iPad". The in-app copy still says "this phone" on iPad; that was flagged to the conductor and is not a framing issue.
- **Shot 3**: the days count changes with the capture date. That is fine, because it is real output. Do not use the "Checking…" progress screen anywhere: in sample mode it reads "0.0 MB of 0.0 MB" (see the design report).
- **Shot 5**: "Back to 1957" is factual. NS&I's unclaimed file covers June 1957 onwards, as the app's own text says.
- **Shot 6**: the yearly-rate card must be captured with its disclaimer visible. If it does not fit at 6.9"/phone height, scroll so the card's top sits under the app bar rather than cutting the note.

## Copy rules (all headlines)

- "Premium Bond" may appear descriptively; none of the six headlines needs it. Never use it as a title or logo.
- Never imply NS&I made, endorses or checks the app. NS&I's name and logo never appear in headline text (it appears in captured UI text, which is fine).
- No claims about winning, odds, returns, speed or "never miss a prize". No currency figures in headline or plate text.
- Every headline is true on both the UK and the other storefronts. Nothing in them is UK-law-specific.
- Keep to one idea per shot, of about six words or fewer. Shot 2 is longer because it carries two required facts.

## Framing (scriptable; the same for every release)

- **Plate:** a solid bottle green `#1F5C45` across the full canvas. No gradient, no generated art.
- **Headline:** Inter Bold (`store_assets/fonts/Inter.ttf`, weight 700) in paper `#FAF7F0`, centred, a maximum of 2 lines, line height 1.15. Size: iPhone 96 px, iPad 112 px, Android 68 px.
- **Subheadline:** Inter Medium 500 in light brass `#E2B85C`, one line. Size: iPhone 48 px, iPad 56 px, Android 34 px. Leave 24/28/18 px between it and the headline.
- **Top margin to the headline:** iPhone 150 px, iPad 140 px, Android 96 px.
- **Screenshot:** no device frame or bezel. Scale the capture to 84% of the canvas width (iPhone and Android) or 80% (iPad). Centre it horizontally and place it 64/72/44 px below the subheadline. Round the corners to 6% of the scaled width, and add a 2 px `#FAF7F0` outline at 25% opacity so the paper-coloured UI separates from the green. The bottom of the capture may run off the canvas bottom. The captured status bar stays.
- **Output:** PNG, RGB, no alpha, at the exact pixel sizes in the table above. File names follow `ios/fastlane/screenshots/en-GB/<n>_<device>.png` and `android/fastlane/metadata/android/en-GB/images/phoneScreenshots/<n>.png`.
- **Play feature graphic:** `store_assets/feature_graphic/feature_graphic_1024x500.png`. Hi-res icon: `store_assets/icon/play_icon_512.png`.

## Preview video

None planned. If one is wanted later, use a 15–20 s screen recording of shots 3 → 1 → 4 in sample mode with no voice-over, and keep the sample banner visible throughout.
