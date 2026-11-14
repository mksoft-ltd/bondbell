# Bondbell: age-rating answers

Written 14 Nov 2026. Apple's questionnaire uses the 2025 age bands (4+, 9+, 13+, 16+,
18+); Google Play uses IARC (answers in `android/fastlane/data_safety_answers.md` §5).

## Apple App Store (App Information > Age Rating)

Expected result: **4+**. No override.

| Question (ASC) | Answer | Why |
|---|---|---|
| Cartoon or fantasy violence | None | |
| Realistic violence | None | |
| Prolonged graphic or sadistic realistic violence | None | |
| Guns or other weapons | None | |
| Horror or fear themes | None | |
| Profanity or crude humour | None | |
| Mature or suggestive themes | None | |
| Sexual content or nudity | None | |
| Graphic sexual content and nudity | None | |
| Alcohol, tobacco or drug use or references | None | |
| Medical or treatment information | None | |
| Health or wellness topics | No | |
| **Simulated gambling** | **None** | The app has no wagering, betting, casino or chance mechanic of its own. |
| **Contests** | **None** | The app runs no contest, prize draw or sweepstake. It checks the published results of NS&I's Premium Bond prize draw, a government savings product in which the holder's money is never at risk; Bondbell sells no entries and awards nothing. |
| **Gambling** (real-money) | **No** | No stakes, no wagers, no payouts. |
| Loot boxes | No | IAPs are a fixed unlock and fixed-price tips. |
| Unrestricted web access | No | No in-app browser. It downloads specific files from nsandi.com; links open the user's own browser. |
| Messaging and chat | No | |
| User-generated content | No | Holder names and bond numbers are private to the device and never shown to anyone else. |
| Advertising | No | |
| Parental controls | No | |
| Age assurance | No | |
| Made for Kids | No (not in the Kids category) | |

Same answers as ASC API attributes (`PATCH /v1/ageRatingDeclarations/{id}`):

```json
{
  "alcoholTobaccoOrDrugUseOrReferences": "NONE",
  "contests": "NONE",
  "gamblingSimulated": "NONE",
  "gunsOrOtherWeapons": "NONE",
  "horrorOrFearThemes": "NONE",
  "matureOrSuggestiveThemes": "NONE",
  "medicalOrTreatmentInformation": "NONE",
  "profanityOrCrudeHumor": "NONE",
  "sexualContentGraphicAndNudity": "NONE",
  "sexualContentOrNudity": "NONE",
  "violenceCartoonOrFantasy": "NONE",
  "violenceRealistic": "NONE",
  "violenceRealisticProlongedGraphicOrSadistic": "NONE",
  "gambling": false,
  "lootBox": false,
  "unrestrictedWebAccess": false,
  "messagingAndChat": false,
  "userGeneratedContent": false,
  "advertising": false,
  "parentalControls": false,
  "ageAssurance": false,
  "healthOrWellnessTopics": false,
  "kidsAgeBand": null,
  "ageRatingOverride": "NONE",
  "koreaAgeRatingOverride": "NONE"
}
```

The attribute names follow the set used by `pocket_copier/ios/fastlane/age_rating.json`
(Aug 2026). If ASC rejects an attribute name, answer by meaning in the console.

Note on 4+: store copy, screenshots and the app never address children, and the rating
does not make the app child-directed. Do not raise it with an override; there is no
content that would justify one.

## Google Play (IARC)

See `android/fastlane/data_safety_answers.md` §5. Gambling and simulated gambling:
**No**. Digital purchases: **Yes**. Expected: Everyone / PEGI 3 with "In-App Purchases".
