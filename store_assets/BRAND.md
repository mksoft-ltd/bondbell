# Bondbell: brand

Source of truth for Bondbell's look, store art and copy rules. Set at the design
stage on 14 Nov 2026. The in-app tokens live in `lib/core/theme/app_theme.dart`;
if the two disagree, fix whichever is wrong and keep them identical.

## Product and audience

An independent UK Premium Bond prize checker. The user saves bond ranges once;
on their tap the app downloads NS&I's public winners list onto the device and
checks it there. The audience skews older UK savers, plus families sorting out a
relative's old paper certificates. The feel is a well-kept savings book: calm,
trustworthy and plain-spoken. It should feel premium yet approachable, and never
like a lottery or a casino.

## Palette

Bottle green and brass on warm paper. The palette is chosen to look nothing like
NS&I's own branding, and it must stay that way.

| Token | Light | Dark | Use |
|---|---|---|---|
| Primary (bottle green) | `#1F5C45` | `#8FD3B4` | Buttons, hero card, icons, links |
| On primary | `#FFFFFF` | `#00382A` | Text on primary |
| Secondary (brass) | `#9A6B12` | `#E2B85C` | Prize amounts, the bell, accents |
| On secondary | `#FFFFFF` | `#3D2A00` | Text on brass |
| Surface (paper) | `#FAF7F0` | `#121614` | Scaffold background |
| Card | `#FFFFFF` | `#1B201D` | Cards, inputs |
| On surface (ink) | `#1B1F1C` | `#E6E9E6` | Body text |
| Nav bar | `#FFFFFF` | `#181C1A` | Bottom bar |

Containers, outlines and variants come from `ColorScheme.fromSeed(#1F5C45)`.

Measured contrast (WCAG):

- Ink on paper is 15.6:1, and paper on bottle green is 7.3:1.
- Brass `#9A6B12` is 4.4:1 on paper and 4.7:1 on white. That passes on white, but on paper it is only fit for large or bold text (prize amounts at 18pt+ bold) and for icons. Never use it for small body text on paper.
- Light brass `#E2B85C` is 4.2:1 on bottle green, so use it for large text there only (the feature graphic's tagline is 34px). On the dark surface it is 9.8:1.

Store art uses only these colours: bottle green as the field, brass for the bell and accents, paper for the title.

## Typography

- **In the app:** the platform system font (SF Pro on iOS, Roboto on Android), set one step larger than Material's defaults for this audience. Body is 18/16/14 at a 1.4 line height, with titles at w700 and list titles at 18 w600. Body tracking is tightened to 0.15/0.1/0.2, because Material's 0.5/0.25/0.4 reads as gappy at these sizes. The user's text-size setting is always honoured. No custom font is bundled.
- **In store art:** Inter (SIL Open Font License, variable, in `store_assets/fonts/Inter.ttf`). Titles are Bold 700 and taglines Medium 500. Inter sits close to SF and Roboto, so the store art and the screenshots read as one family. SF Pro is not used in marketing art (its licence covers UI mock-ups only).

## Iconography

- **App mark:** one upright brass hand bell, with a top loop, a darker brass lip, a round clapper and one paper-coloured highlight stripe, on flat bottle green. It stands for the results-day reminder and "your bell rings when results are in", without promising a win.
- **In the app:** Material Symbols, outlined, coloured with the primary green. Use a filled icon only for the selected navigation item.
- **Do not add to the mark:** sound arcs, sparkles or a second object. The arcs appear only in the feature graphic.

## Design rules (store art and icon)

These apply to the icon, the adaptive and monochrome layers, the Play hi-res icon, the feature graphic and any screenshot backgrounds:

1. No text, letters or numbers inside the icon. Text in other store art is rendered in code, never drawn by a model.
2. No tick, badge, seal, rosette, laurel, ribbon, medal or star. Google Play's Metadata policy reads these as award or endorsement imagery and rejected a portfolio app for one (Aug 2026, house-facts §29). Ticks inside genuine captured UI are fine.
3. No coins with symbols, currency signs, banknotes, confetti, trophies or jackpot imagery. Bondbell checks numbers; it does not sell the dream of winning. Never put currency figures in headline or art text.
4. Nothing that resembles NS&I's branding (colours, logo or typography) or its "ERNIE" machine imagery. No third-party logos.
5. "Premium Bonds" is never used as a logo-like element, in the app name or in the icon. It may appear descriptively in body copy and headlines ("Premium Bond numbers").
6. No device bezels or fake UI in generated art. Store screenshots are real captures (see `SCREENSHOTS.md`).

## Tone

- **Plain, warm and exact,** like a helpful branch clerk. Use short sentences and British spelling.
- **Say what the app does, not what the user might win.** Make no claims about winning, odds, returns or speed.
- **Make independence clear wherever it matters:** "Bondbell is an independent app and is not affiliated with NS&I." Never imply NS&I made, approved or checks the app.
- **Privacy is a fact, not a slogan:** no login, no account, and the numbers stay on the device.
- **No pressure:** no countdown timers, no strike-through prices, no "don't miss out".

## Assets and how to rebuild them

| Asset | File | Built by |
|---|---|---|
| iOS / master icon, 1024 RGB, no alpha | `icon/app_icon_1024.png` | `icon/build_icon.py` |
| Android adaptive foreground (mark at 0.37 max radius → inside the 66 dp safe circle after the 16% inset) | `icon/adaptive_foreground.png` | same |
| Android 13+ monochrome layer | `icon/adaptive_monochrome.png` | same |
| Play hi-res icon 512 | `icon/play_icon_512.png` | same |
| Keyed mark (transparent) | `icon/mark.png` | same |
| Proofs 180/120/48, round mask, safe-zone guide, monochrome | `icon/proofs/` | same |
| Play feature graphic 1024×500 | `feature_graphic/feature_graphic_1024x500.png` | `feature_graphic/build_feature_graphic.py` |

To rebuild:

```
/opt/homebrew/bin/python3 store_assets/icon/build_icon.py
dart run flutter_launcher_icons          # config: flutter_launcher_icons.yaml
git checkout -- ios/Runner.xcodeproj/project.pbxproj   # see note below
/opt/homebrew/bin/python3 store_assets/feature_graphic/build_feature_graphic.py
```

`flutter_launcher_icons` 0.14.4 rewrites the project-level `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS` to `AppIcon`, which is a known package bug. Revert the pbxproj after every run; the app icon itself is set by the target's `ASSETCATALOG_COMPILER_APPICON_NAME`. The tool also owns `android/app/src/main/res/values/colors.xml` (`ic_launcher_background = #1F5C45`).

The model's green is a few RGB units off brand and slightly noisy. `build_icon.py` keys the mark off it, un-mixes the edge pixels so no green halo remains, and lays it on the exact `#1F5C45`.

## Generated artwork

Account: OpenArt Pro (froggyeye.ltd@gmail.com), CLI 0.1.1. The balance was 24,000 credits before this pass and 23,755 after, so the pass used **245 credits** against a 300 budget. The list prices below add up to 242; the CLI does not explain the other 3. The raw outputs and the exact prompt files (`prompt_*.txt`) are kept under `icon/openart/` and `feature_graphic/openart/`.

| Asset | Model | Creation id | Date | Credits | File | Chosen |
|---|---|---|---|---|---|---|
| Icon v1: upright brass bell with highlight | nano-banana-pro (1:1) | `rDYiyp4hYRsxWeb2flhg` | 2026-11-14 | 40 | `icon/openart/v1.png` | **Yes** |
| Icon v2: cream bell with sound arcs | nano-banana-pro | `edkZ5ZJZUJno0dbYmEpw` | 2026-11-14 | 40 | `icon/openart/v2.png` | No: reads as the generic system notification glyph, the same as the app's own nav icon |
| Icon v3: tilted geometric bell | nano-banana-pro | `2XPlCgnEMrhG9QfcSM08` | 2026-11-14 | 40 | `icon/openart/v3.png` | No: strong, but the flat bar rim reads less as a bell at 48 px than v1's flared lip |
| Feature bg f1: hand bell with arcs | gpt-image-2 (4:3) | `8HAsXi2bHmhxjoz4StXR` | 2026-11-14 | 40 | `feature_graphic/openart/f1.png` | No: good composition, but the turned-handle bell does not match the icon. Used as the reference for f3 |
| Feature bg f2: bell on a paper card | gpt-image-2 | `5fB57pZ9YpB17DoHCsS2` | 2026-11-14 | 40 | `feature_graphic/openart/f2.png` | No: torn card shape cut off by the right edge |
| Feature bg f3: f1's layout with the icon's bell (image-to-image, refs f1 + icon v1) | gpt-image-2 (image2image) | `3qqXsqPVQCDEkvlcxFNG` | 2026-11-14 | 42 | `feature_graphic/openart/f3.png` | **Yes** |

Full prompts:

**Icon v1 (chosen):**
> Flat vector app icon mark: a single classic hand bell, simple bold geometric shape, solid brass gold colour #C99A3A with a slightly darker brass #9A6B12 for the lip and the round clapper, one small cream #FAF7F0 highlight stripe on the left of the bell. Centred with generous margins, bell occupies about 55 percent of the canvas. Flat solid bottle green background #1F5C45 filling the entire square edge to edge. Minimal, premium, calm, modern flat design, crisp edges, no texture. No text, no letters, no numbers, no badges, no ticks or check marks, no seals, no laurels, no ribbons, no stars or sparkles, no coins, no currency signs, no logos, no device frames, no user interface, no shadows on the background, no gradient background, no border.

**Icon v2:**
> Flat vector app icon mark: a single rounded bell silhouette in warm cream #FAF7F0 with a solid brass #9A6B12 clapper ball below it and a short brass handle loop on top, plus two thin cream curved sound arcs on each side of the bell showing it is ringing. Centred with generous margins, the whole mark about 60 percent of the canvas. Flat solid bottle green background #1F5C45 filling the entire square edge to edge. Minimal, premium, friendly, modern flat design, crisp edges, no texture. *(same negative list as v1)*

**Icon v3:**
> Flat vector app icon mark: a single bell built from simple geometry, a smooth dome bell body in brass #E2B85C, a flat brass #9A6B12 rim band across the bottom of the bell, and a round brass clapper. The bell is tilted slightly to the right as if mid-ring. Centred with generous margins, about 55 percent of the canvas. Flat solid bottle green background #1F5C45 filling the entire square edge to edge. Minimal, premium, approachable, modern flat design, crisp edges, no texture, no gloss. *(same negative list as v1)*

**Feature f1:**
> Wide flat vector illustration for a banner background. Flat solid bottle green background #1F5C45 across the whole image. On the right third, vertically centred, a single brass hand bell (#E2B85C body, #9A6B12 rim and clapper) tilted slightly as if ringing, with three thin concentric cream #FAF7F0 arcs radiating softly from it. The left two thirds of the image are calm empty green space with only a very faint tone-on-tone large circle shape. The whole bell must sit within the middle horizontal band of the image, away from the top and bottom edges. Minimal, premium, calm, modern flat design, crisp edges, no gloss. No text, no letters, no numbers, no badges, no ticks or check marks, no seals, no laurels, no ribbons, no stars or sparkles, no confetti, no coins, no currency signs, no banknotes, no logos, no phones or device frames, no user interface, no people.

**Feature f2:**
> Wide flat vector illustration for a banner background. Flat solid bottle green background #1F5C45. On the right side, vertically centred, a single simple brass bell (#E2B85C with #9A6B12 rim and clapper) resting on a plain warm paper-coloured #FAF7F0 rounded card that is partly visible, like a ticket-shaped card without any markings, slightly angled. The left 60 percent is quiet empty green space for a title. Everything important sits in the middle horizontal band, well away from the top and bottom edges. Minimal, premium, approachable, modern flat design, crisp edges, subtle soft shadow under the card only. *(same negative list as f1)*

**Feature f3 (chosen; `--image f1.png --image icon v1.png`):**
> Wide flat vector banner background, landscape. Use the first reference image for the exact composition: flat solid bottle green background #1F5C45, a very faint tone-on-tone large circle on the left, three thin concentric cream #FAF7F0 arcs on the right. Replace the hand bell with the exact bell from the second reference image: an upright classic brass bell #C99A3A with a small top loop, a darker brass #9A6B12 lip and round clapper, and one cream highlight stripe on its left side, drawn flat with crisp edges, tilted slightly as if ringing, placed on the right third and vertically centred, with the arcs radiating from its left side. The left 60 percent stays calm empty green space for a title. Keep everything within the middle horizontal band of the image. No text, no letters, no numbers, no badges, no ticks, no seals, no laurels, no ribbons, no stars or sparkles, no confetti, no coins, no currency signs, no logos, no devices, no user interface, no people.

Feature graphic text, rendered in code in Inter: the title **"Bondbell"** (92px Bold, paper) and the tagline **"Check your bond numbers / on your phone. No login."** (34px Medium, light brass).
