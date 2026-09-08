# From BirdNET Live to Smartfinch — Transition Analysis

**Date:** 4 September 2026 · **Basis:** `birdnet_live` v1.1.2+223 (commit `8efbd7d`) · **Target:** Smartfinch App Vision & Requirements Specification

---

## 0. Purpose of this document

The specification describes the app that is to be built. This document describes the app that **exists**, and what has to happen to it. It answers three questions per module:

- **Keep** — usable as-is, no Smartfinch work needed
- **Change** — the substance is right, the surface or the semantics must change
- **Remove** — not part of Smartfinch

It also records the four foundational decisions that were taken before writing it, and the consequences that follow from them.

---

## 1. The decisions

Four foundational decisions (D1–D4), then the module-by-module verdicts from the second review pass (D5–D14), then the decisions that unblock the MVP (D15–D23). All are settled; this document reflects them.

| # | Question | Decision | What follows from it |
|:---:|---|---|---|
| **D1** | Fate of the professional modes | **Remove entirely** | Survey, ARU, Point Count, File Analysis, Batch Analysis and their session-type machinery are deleted. ~20,000 lines out of the feature tree, plus the session-type dimension throughout the history layer. |
| **D2** | Relationship to upstream | **Fork with periodic upstream merges** | The inference / audio / recording / spectrogram core stays structurally close to upstream so BirdNET model and ONNX-runtime fixes keep merging. All Smartfinch code goes in *new* directories. See §7. |
| **D3** | Rarity source for scoring | **Use the existing adaptive tier as-is** | `PKT-01` is taken literally. No new frequency banding is written. The consequence for week coupling is analysed in §5 — it is real, and the specification has been amended accordingly. |
| **D4** | Capabilities preserved for later | **All 12 UI locales**; **audio clips, sharing, TTS announcements and export formats** | The l10n discipline from `AGENTS.md` stays in force for every new Smartfinch string. The audio/export machinery survives the removal of the modes that used it — see §3.4. |

### Module verdicts from the second review

| # | Subject | Decision | What follows from it |
|:---:|---|---|---|
| **D5** | Non-bird species (340 amphibians, 268 mammals, 254 insects) | **Keep all of them.** The collection shows everything by default, with a filter by taxon group | No second album, no separate branding track — one collection, filterable. The real influence of non-birds is a question for the field test, not for the design table. New requirement `SAM-17` |
| **D6** | Species images | **Use them exactly as the original app does.** Silhouettes are **deferred out of the MVP** | The existing bundle pipeline and its licence situation carry over unchanged — no new licensing project. `SAM-04` keeps only the photo-vs-placeholder contrast for the MVP; per-species silhouettes become `SAM-04b` at P1 and are derived from the same images rather than drawn. ⚠️ The bundle is a **gitignored build output**: without a pipeline run there are no photos and no profile texts at all — see §4 |
| **D7** | Spectrogram | **Keep, at full size** | It is not decoration: it shows *how sound becomes a picture*, and it makes interference visible — when you talk, you can see the calls disappear underneath. That is a teaching surface, so the scoring UI is laid out around it, not on top of it |
| **D8** | Spoken announcements (TTS) | **Keep unchanged, default off** — as they are today | Explicitly **not** reworded to "something new!". Naming the species is the point for anyone who cannot look at the screen right now. Accessibility beats the guessing game |
| **D9** | Maps and place names | **Keep the maps** — and add child-written place names | New: a session gets a name the child types ("Oma", "Urlaub", "Schulweg"), editable afterwards, with a pick-list of names already used. This is what lets a child place their own recordings. New requirement `LOG-13` |
| **D10** | Audio clips | **Keep BirdNET Live's logic** and add a deletion policy in Settings | Order of deletion: most-recorded species with the lowest confidence first, once older than 30 days, above 100 recordings per species. Favourites are protected. New requirement `SET-12` |
| **D11** | Weather service | **Keep** | Open-Meteo with its consent gate and cache carries over. Makes the *Bad weather hero* badge (`AUS-11`) reachable rather than theoretical |
| **D12** | Collection vs. Explore | **Two separate areas, not a toggle** | Explore (`Erkunden`) stays what it is — the list of all species. The **Collection** (`Sammlung`) becomes its own destination. This changes `SAM-02` from a toggle into an information-architecture decision |
| **D13** | Settings | **Do not over-prune — hide instead** | Advanced settings move into their own area rather than being deleted. The exception is the expert inference knobs (pooling, sensitivity, custom species lists), which go entirely |
| **D14** | Background recording | **Rescued for later** — extracted before Survey is deleted | The foreground-service implementation is lifted out of `features/survey` into a standalone module *first*, then Survey goes. It is not wired into Live mode for the MVP, but it stays in the codebase and compiling, so `LIVE-10`/`LIVE-11` remain reachable when the walking use case proves it needs them |

### Decisions on the MVP specification gaps (chapter 9 of the specification)

| # | Gap | Decision | What follows from it |
|:---:|---|---|---|
| **D15** | When a detection scores | **The moment it is shown** — the first inference window that clears the threshold. Peak confidence is written back when the record closes | Stars appear at the same instant the species does (`LIVE-02`), and `PKT-11`/audits still get the peak rather than the first frame. The `ScoreEvent` is therefore written once and updated once |
| **D16** | Which confidence threshold governs points | **The existing user slider**, moved into Advanced settings. Kept adjustable through the MVP as a test instrument | The applied threshold **must** be frozen into every `ScoreEvent` (`PKT-15`), or moving the slider silently rewrites history. The worry that a scoring-rule control cannot ship in a children's app is answered by **D21** rather than by locking the slider |
| **D17** | One rarity scale or one per animal group | **One shared scale for all animals** | Simpler, and consistent with `SAM-17`'s single collection. Amphibians, mammals and insects take whatever rank their raw scores earn among the birds. Watch this in the field test — it is the assumption most likely to need revisiting |
| **D18** | What happens with no location | **The home region is chosen during onboarding** | `SET-09` moves from P2 into the onboarding flow and becomes a precondition for scoring. Affects `KID-01`'s four-screen budget |
| **D19** | Background recording, concretely | **Extract first, delete second** | A named work item in Phase 0, and the ordering matters — see §3.3 |
| **D20** | Species not on the local list | **They score nothing.** The off-list rule in §2.3 of the specification is removed; `geoExclude` stays the default filter; `geoAdaptive` is documented as a future option, not switched on | Rule and filter now say the same thing. Removes the central misdetection risk (§2.9) rather than defending against it, and takes `PKT-11`/`PKT-18` down to P2. Note that under `geoExclude` **every species faces the same confidence bar** — the point value does not raise it. ⚠️ It also removes the sharpest seasonal signal, see §5 |
| **D21** | Detection parameters that can be changed | **Leaving the scoring range pauses the whole scoring layer** | The species filter and the confidence slider stay in Advanced settings, but switching the filter off or dropping the threshold below **35 — the shipped default, now also the scoring floor** — pauses **stars, collection, life list, year list and badges** together. Raising the threshold above 35 keeps scoring; only lowering pauses — the collection included, or a lowered threshold becomes a way to fill the album with species that were never there. **Detection keeps running and the recordings are kept**, shown in the journal marked as outside scoring. New `PKT-20`, `SET-13`, `LIVE-18`, `LOG-15`, `DAT-11`. This is what makes D16's adjustable slider safe to ship |
| **D22** | Legacy data from BirdNET Live | **There is none to migrate** | Smartfinch's own application ID (§8) means sandboxing keeps the old app's session files out of reach. `LOG-12` is rewritten from "migrate legacy sessions" to "a restore reinstates rather than recomputes", and drops to P1. Gap H in chapter 9 is withdrawn — the case it described cannot occur |
| **D23** | The grid cell | **0.1° everywhere, rebuilt on cell change** | One grid for the rarity scale, the place bonus (`PKT-13`, no longer a separate 5 km) and the weather cache. The position is re-checked every few minutes at **coarse** accuracy; the scale is rebuilt only when the cell actually changes, in an isolate, without interrupting listening, with a small LRU cache. Fixes the walk-to-school case and hands `PKT-13` its trigger for free. Closes the last MVP gap |

> **A tension that resolves cleanly:** D1 (remove the pro modes) and D4 (keep export formats) pull against each other, because the export code lives inside the session layer D1 deletes. The resolution is in §3.4: the format writers and the sharing service are kept and re-pointed at the new Journal; the survey/ARU-specific export paths (Raven, GPX) go with their modes.

---

## 2. Where the app stands today

**Scale:** 158 Dart files, ~78,800 lines in `lib/`, 99 test files, 91 MB of ONNX model assets, 2,215 English UI strings across 12 locales.

| Module | Lines | What it is |
|---|---:|---|
| `features/history` | 20,676 | Session library, session review, export (Raven/CSV/JSON/GPX/HTML/ZIP), audio clip playback, voice memos, map |
| `features/survey` | 8,554 | Long transect surveys with GPS tracking, background monitoring, species alerts |
| `features/aru` | 6,819 | Autonomous recording-unit mode: multi-day scheduled deployments |
| `shared` | 5,480 | Models, providers, taxonomy, weather, share sheet, common widgets |
| `features/live` | 5,138 | Live mode: capture → inference → detection list, session model |
| `features/inference` | 4,490 | ONNX classifier + geo model, post-processing, species filtering, abundance tiers |
| `features/recording` | 4,293 | WAV/FLAC encoders, decoders, playback normalisation |
| `features/explore` | 3,447 | Location species list, species cards, info overlay |
| `features/announcements` | 3,285 | Spoken TTS detection announcements with per-locale phrasing templates |
| `features/settings` | 2,656 | 10 settings sections, 85 setting providers, 129 preference keys |
| `features/file_analysis` | 2,642 | Analyse existing audio files |
| `core` | 2,257 | Constants, location, asset packs, theme, wakelock |
| `features/point_count` | 1,936 | Timed point-count survey sessions |
| `features/audio` | 1,919 | Capture service, ring buffer, source selection |
| `features/home` | 1,551 | Home screen with six mode tiles plus library/explore/settings/help/about |
| `features/spectrogram` | 1,455 | FFT, colour maps, `CustomPainter` renderer |
| `features/onboarding` | 962 | 4-page onboarding with permission and consent tiles |
| `features/about` | 275 | Credits, licences |

**Platforms:** Android, iOS, Windows. **Persistence:** JSON files on disk, one per session, plus 129 `SharedPreferences` keys. **No database.**

---

## 3. Keep · Change · Remove

### 3.1 Keep unchanged — the technical foundation

This is the part of BirdNET Live that Smartfinch is being built *on*, and the reason the fork is worth doing at all. None of it needs Smartfinch work, and under D2 none of it should be restructured.

| Module | Why it stays | Spec IDs satisfied |
|---|---|---|
| `features/inference` | On-device BirdNET+ classifier (9,789 species) and geo model. Isolate-based — already the architecture `NFA-13` asks for | `LIVE-01`, `NFA-01`, `NFA-13` |
| `features/audio` | Capture service and ring buffer. Battery and latency behaviour already tuned | `NFA-02`, `NFA-03` |
| `features/spectrogram` | FFT plus `CustomPainter` on its own layer — literally the implementation `NFA-13` prescribes | `LIVE-01`, `NFA-13` |
| `features/recording` | WAV/FLAC encode/decode. Needed for `LIVE-14` audio snippets (D4) | `LIVE-14` |
| `core/services/asset_pack_service` | Play Asset Delivery plus sideload model extraction. Solves the 91 MB shipping problem | `NFA-05` |
| `core/services/location_service` | Location with a GPS on/off switch and manual coordinates | `NFA-08`, `SET-09` |
| `core/theme` | Material 3 theme, dynamic colour, CVD-safe score ramps, high-contrast mode | `NFA-10` |
| `shared/services/taxonomy_service` | 12.7 MB taxonomy CSV: names in 12 locales, families, image refs, Wikipedia URLs | `SAM-06`, `SAM-09` |
| `shared/services/species_description_service` | Bundled gzip descriptions in 11 locales, fully offline | `SAM-11` (adult register — see §4) |
| `features/announcements` | TTS announcements with per-locale phrasing templates. Kept under D4 | — |

**The single most valuable inherited asset** is the geo model: `assets/models/BirdNET+_Geomodel_V3.0.4_Global_10K-pruned_FP16.onnx` (13.6 MB) takes `[latitude, longitude, week]` and returns a probability per species, for **48 weeks worldwide**. `GeoModel.predictAllWeeks()` already produces the full annual curve per species in one pass.

This makes three specification requirements substantially cheaper than written:

- **`DAT-06`** ("ship range data at weekly resolution as a precomputed asset, cropped to the target region") is **already solved, and better** — a 13.6 MB model beats a precomputed table, needs no region cropping, and works anywhere on Earth. The requirement should be reworded, not implemented.
- **`SAM-15`** (annual cycle bar, 48 weeks per species) is **essentially free** — `ExploreSpecies.weeklyScores` already carries the 48-value curve.
- **Open question 1 of chapter 9** is answered: **six levels** (`ExploreTier.rare` … `abundant`), **week-accurate**, 48 weeks per year.

### 3.2 Change — the substance is right, the framing is wrong

| Module | Today | Becomes | Effort |
|---|---|---|---|
| `features/explore` | Species list for the current location, six abundance tiers, taxon filters, search, `_DetectionFilter { all, detected, undetected }`, detected-species ticks | **Stays Explore** (`Erkunden`) — the list of all species, essentially as it is (D12). Gains the point value per species (`SAM-03`) and the annual cycle bar (`SAM-15`) | Small — this is the module that changes least |
| **new** `features/collection` | — | **The Collection** (`Sammlung`) as its own destination (D12): only what the child has actually found, all taxon groups shown by default with a group filter (`SAM-17`), silhouettes for the open ones (`SAM-04`), progress counter (`SAM-05`), "This year" view (`SAM-16`) | Medium — the data layer exists (`detectedSpeciesSetProvider`), the screen does not |
| `features/live` | Detection list with confidence, sorted, filterable, full-size spectrogram | **Live mode with stars.** Spectrogram keeps its size (D7); the scoring UI is laid out *around* it. Add star chip per card (`LIVE-02`), "already collected today" (`LIVE-03`), multiplier chip (`LIVE-04`), confetti (`LIVE-05`), species card sheet (`LIVE-06/07`), day total header (`LIVE-08`) | Medium — all additive; the detection pipeline is untouched. Layout is the hard part, since the spectrogram is not negotiable |
| `features/history` | Session library and session review, per recording | **Journal** (`Tagebuch`), per day. `LOG-01` is the core rebuild: sessions stay in the data model, disappear from navigation. Gains child-written place names (`LOG-13`, D9) | Large — see §3.4 |
| `features/home` | Six mode tiles plus five secondary buttons | Star header (`HOME-01/02`), **one large Live tile** plus equal secondary tiles for Collection, Explore, Journal, Points, Settings (`HOME-08`). The tile grid stays — only its contents change | Small–medium — the layout survives, the destinations change |
| `features/settings` | 10 sections, 85 providers, 129 pref keys, expert controls (sensitivity, pooling, inference rate, high-pass) | **Reorganised, not gutted** (D13). A plain first screen for what a child or parent touches; everything else moves behind **Advanced settings**. Only the expert inference knobs are deleted outright. Add `SET-02` animation level, `SET-11` scoring rules, `SET-12` clip retention | Medium — mostly moving, which is cheaper than deleting: fewer ARB removals across 12 locales |
| `features/onboarding` | 4 pages, permission and consent tiles, adult register | Child register (`KID-01/03`), parent notice (`KID-08`), first guided detection (`KID-02`) | Small structurally, large editorially |
| `features/announcements` | TTS announcements, default off, 12 locales | **Unchanged** (D8). Not reworded, not re-toned, default stays off | None |
| `shared/services/weather_service` | Open-Meteo lookup with consent gate and 10 km cache | **Unchanged** (D11). Enables `AUS-11` | None |
| Maps (`flutter_map`, tile layer, map picker) | Session map, setup pickers, location picker | **Kept** (D9). The survey map goes with Survey; the location picker stays and serves `SET-09` | Small |
| `shared/services/quick_action_service` | Home-screen shortcuts to Live / Point Count / Survey | Live only | Trivial |

### 3.3 Remove — decision D1

| Module | Lines | Tests | Note |
|---|---:|---:|---|
| `features/survey` | 8,554 | 7 files | Transect surveys, GPS tracking, species alert engine, survey map |
| `features/aru` | 6,819 | 6 files | Multi-day deployments, scheduling, storage estimation |
| `features/file_analysis` | 2,642 | 1 file | File import and offline analysis |
| `features/point_count` | 1,936 | — | Timed counts with station metadata |
| **Total** | **19,951** | **14** | |

**The removal is unusually clean.** Only three files in the entire codebase import these modules: `lib/app.dart`, `lib/main.dart` and `lib/shared/services/quick_action_service.dart` — ten import statements in total. The modules are genuinely self-contained.

**Also removed** (D13, D14, and the second-pass verdicts):

| Item | Lines | Note |
|---|---:|---|
| ~~Background recording / foreground service~~ | ~600 | **D14 reversed — rescued, not deleted.** See the extraction note below |
| Voice memos (`widgets/voice_memo_overlay.dart`) | 879 | Field-researcher tool, and spoken free text is awkward under `KID-07` |
| Session map (`session_map_screen.dart`) | 188 | Displays precise GPS tracks — what `NFA-08` forbids. The *map picker* stays (D9) |
| Expert inference controls | ~1,200 | Pooling parameters, sensitivity, custom species lists, score blacklist UI. Uploading your own species list is a way to arrange your own collection |
| Raven and GPX export writers | ~400 | Research formats; go with the modes that produced them |

**⚠️ Extract the foreground service before deleting Survey (D14/D19).** This is an ordering constraint, not a preference: once `features/survey` is gone, the only working screen-off recording implementation goes with it, and `LIVE-10` becomes a rewrite rather than a rewiring. The work is small and belongs at the very start of Phase 0:

1. Move `survey_notification.dart`'s foreground-service lifecycle into a mode-agnostic `shared/services/background_recording/` — start, stop, notification, permission handling, nothing survey-specific.
2. Drop `foreground_service_guard.dart` down to a single owner, or delete it: with ARU and Survey gone there is nothing left to arbitrate between.
3. Keep `flutter_foreground_task` in `pubspec.yaml` and the `FOREGROUND_SERVICE_MICROPHONE` permission in the manifest. `ACCESS_BACKGROUND_LOCATION` and `FOREGROUND_SERVICE_LOCATION` still go — those were Survey's GPS tracking, which is not being rescued.
4. Leave it unwired for the MVP. It must compile and be covered by its tests, so that connecting it to Live mode later is a day's work rather than a project.

**What removal drags with it:**

- `SessionType` (`lib/features/live/live_session.dart:312`) collapses from six values to one. `lib/shared/utils/session_type_visuals.dart` (icon and colour per type) becomes unnecessary.
- `SessionSettings` sheds roughly 30 survey/ARU fields (`alertMode`, `alertWatchlistName`, `gpsIntervalSeconds`, `autoStopBatteryPercent`, `targetDurationSeconds`, `backgroundGps`, …). **Legacy sessions on disk must still deserialise** — keep the fields tolerated on read, drop them on write.
- Twelve files in `features/history` branch on session type and need pruning.
- `shared/services/shared_media_service` (share-in handling that routes an audio file into File Analysis) goes.
- `AndroidManifest.xml`: `ACCESS_BACKGROUND_LOCATION` and `FOREGROUND_SERVICE_LOCATION` go with Survey's GPS tracking. `FOREGROUND_SERVICE_MICROPHONE` **stays** — the rescued background recording needs it (D14). `INTERNET` stays too: maps and weather need it (D9, D11).
- ARB cleanup across 12 locales for every removed string. Smaller than first estimated: under D13 most settings strings *move* rather than disappear.

### 3.4 The history layer — the one genuinely hard piece

`features/history` is 20,676 lines and cannot simply be deleted, because D4 keeps the export formats and audio clips, and `LOG-01` rebuilds the same area as the Journal.

| File | Lines | Fate |
|---|---:|---|
| `session_review_screen.dart` | 5,730 | **Rebuild** as the day detail (`LOG-03/07/09`) |
| `widgets/session_review_widgets.dart` | 4,500 | **Rebuild** as day-detail widgets. Not salvageable as-is — built around one recording |
| `session_library_screen.dart` | 2,106 | **Rebuild** as the day list (`LOG-02/04/05`) |
| `html_report.dart` | 1,803 | **Keep, re-point** — becomes the basis for `LOG-11` (export a day as an image) |
| `session_export.dart` | 1,664 | **Keep, split in two.** *Backup*: complete JSON/ZIP, in Settings, for parents → `SET-07`. *Share*: one image of the day, no audio, no coordinates, no free text. Raven and GPX are deleted |
| `widgets/clip_player_sheet.dart` | 940 | **Keep** — playback for `LIVE-14` and `SAM-08` |
| `widgets/voice_memo_overlay.dart` | 879 | **Remove** — a field-researcher feature |
| `services/detection_sharing_service.dart` | 746 | **Keep, narrow** — one share path (the day image), not per-detection audio sharing. `KID-07` |
| `services/session_audio_trim.dart` | 626 | **Keep** — needed for `LIVE-14` snippets and the `SET-12` retention job |
| `session_repository.dart` | 232 | **Replace** — see §6 |
| `global_species_history.dart` | 213 | **Keep** — this is already the life list `PKT-04` needs |
| `session_map_screen.dart` | 188 | **Remove** — precise GPS tracks, forbidden by `NFA-08`. The map *picker* stays (D9) |

> `global_species_history.dart` deserves a note: it already maintains a persisted lifetime set of every scientific name ever detected, with a one-time backfill from existing sessions. That is `PKT-04`'s first-find check, built and shipping. The `detectedSpeciesSetProvider` in the same file already drives Explore's detected-ticks — the `SAM-02` toggle is a UI change on top of working data.

---

## 4. What must be built from nothing

Nothing in BirdNET Live resembles these. This is the actual Smartfinch project.

| Area | Spec IDs | Note |
|---|---|---|
| **Scoring engine** | `PKT-01`…`PKT-19`, `NFA-06`, `NFA-14` | The heart. Pure Dart, no UI, fully unit-testable. Build it first and build it alone |
| **Relational database and migrations** | `DAT-01`…`DAT-09` | The app has **no database at all** today — see §6 |
| **Badges, achievements, levels** | `AUS-01`…`AUS-13` | |
| **Points / statistics area** | `STAT-01`…`STAT-10` | No charting library in `pubspec.yaml` today |
| **Journal (day-based)** | `LOG-01`…`LOG-12` | Rebuild of the history layer |
| **Avatar** | `AVA-01`…`AVA-06` | Also an illustration project, not only code |
| **Child-appropriate copy** | `KID-01`…`KID-10`, `SAM-11`, `SET-11` | See the warning below |
| **Species images** | `SAM-04`, `SAM-06` | See the warning below |

> **Species images — resolved by D6, with one piece of work left.** The images are not a procurement project: `tools/build_species_bundle.py` already downloads and packs them as 480×320 WebP, and `assets/models/taxonomy.csv` carries `image_url`, `image_author` and `image_license` per species. D6 says: use them exactly as the original app does, on the same licensing basis. Nothing new to negotiate.
>
> **The silhouettes are out of the MVP** (`SAM-04b`, P1). The Pokédex effect rests on the *contrast* between a filled cell and an empty one, and the placeholder the app already ships delivers that without any pipeline work. What silhouettes add is the shape of the bird you are missing — recognisably a woodpecker, a duck — which is what turns a grid of blanks into a wanted list. Worth having, not worth blocking the prototype on.
>
> When it is built: **do not commission 130 drawings.** Derive them from the images already in the bundle — a pass in the same pipeline (desaturate, flatten to a single dark tone against the surface colour, keep the outline) covers all ~9,800 species instead of a curated 130 and stays correct when the taxonomy is rebuilt. Attribution follows the image into the silhouette, since it is a derivative.
>
> ⚠️ **Unrelated but urgent:** `assets/species_images/` and `assets/species_data/` are gitignored build outputs, and a fresh clone has neither. Until `tools/build_species_bundle.py` has run, **every species falls back to the placeholder and no profile text appears at all** — which looks exactly like a bug in the Collection. Run the bundle before judging any species UI.
>
> **The editorial register is now the dominant non-code risk.** The bundled species descriptions are written for adults, in 11 locales. `SAM-11` asks for 2–3 child-friendly sentences plus a call mnemonic per species — and under D5 the species pool is no longer birds only. Under D4 the l10n discipline in `AGENTS.md` means every new Smartfinch UI string needs 12 translations. Recommendation unchanged: German first, English second, everything else keeps the adult text until someone funds the rewrite.

---

## 5. Decision D3 in practice — what "use the existing tier as-is" actually does

This section exists so that nobody is surprised in month three. **The decision stands; this is what to expect from it.**

The existing tiers (`lib/features/inference/geo_abundance.dart`) are **rank-percentile based**. `ExploreTierScale.fromScores()` sorts every species scoring above `0.03` at the current location and week, then cuts the list at fixed shares: 8 % *Abundant*, 12 % *Common*, 25 % *Frequent*, 28 % *Uncommon*, 17 % *Scarce*, 10 % *Rare*. Two gentle absolute floors (0.20 and 0.10) stop a weak area from minting an *Abundant* species out of a poor guess.

**Consequence 1 — the tier population is constant.** Roughly 10 % of the locally present species are *Rare* in every week of the year. The number of 1,000-star species available to a child does not change with the season.

**Consequence 2 — seasonality inside the point value now rests on one mechanism only.**

| Mechanism | Still works? | Note |
|---|---|---|
| **Rank shift within the list** | Yes | A blackcap dropping from `f=30` to `f=0.5` falls past most of the list and lands in a rarer tier. The *direction* of §2.2 is preserved — and after **D20** this is the only seasonality the point value itself carries |
| ~~Off-list spike~~ | **Removed (D20)** | A species below the geo threshold has no level and scores nothing. `geoExclude` — the app's default filter — already keeps those detections off the screen, so rule and filter now agree |
| **Absolute size of the swing** | Damped | §2.2's "blackcap ×6" is not guaranteed. The swing depends on how many *other* species also thinned out that week — in a winter list that shrank overall, the blackcap's rank may barely move |
| **Cross-region comparability** | Different by design | An inner-city child's *Rare* is their local top 10 %, not a nationally rare bird. **This is a feature, not a bug** — principle 3 ("common species stay valuable") enforced automatically, and the strongest argument for this decision |

> **What D20 costs, and what pays for it.** The off-list case was the sharpest seasonal signal in the scoring system. Without it, a child may not notice from the numbers that the year outside changes at all. **The year list has to carry that instead** — the year-first multiplier (`PKT-12`), the "This year" view (`SAM-16`) and the year achievements (`AUS-13`). Those three were the safety net against the motivation drop after ~40 species; they are now also the main seasonal rhythm, and they should be built earlier than their P1 position suggests. `PKT-12` is cheap enough to belong in P0.

**Consequence 3 — the misdetection risk in §2.9 is designed out rather than defended against.** The tier is a bounded rank, not an unbounded inverse frequency, so a marginal species cannot climb arbitrarily high — and D20 removes the one path where a single false positive bought the maximum. `PKT-11` (confirmation) and `PKT-18` (confidence tiering) both drop to P2; `PKT-19` (damping) is dead weight.

**What this requires in the implementation:**

1. `ExploreTierScale` is currently built **inside** `exploreSpeciesProvider`, which runs 48 ONNX inferences and is scoped to the Explore screen. Scoring needs the same scale at detection time in Live mode. **Extract a shared `WeeklyTierScaleProvider`** keyed by `(gridCell, isoWeek)` and cached, used by both Explore and the scoring engine — otherwise Explore and Live can disagree about what a bird is worth, which breaks principle 6 loudly and visibly.
2. The scale must be **derived from a coarsened grid cell**, not raw coordinates (`NFA-08`). Otherwise walking 200 m re-ranks the list and the same bird changes value mid-session.
3. `PKT-15` (freeze the base value in the `ScoreEvent`) becomes **more** important, not less: the scale is now recalibrated per location *and* per week, so an unfrozen base would be even less reproducible than the specification assumed.

**Recommended before the prototype:** run `predictAllWeeks()` once for the target region and count how many species change tier over the year, and by how many steps. That is chapter 9's open question 2, it takes an afternoon, and the answer decides whether the seasonal story is worth telling in the UI at all (`PKT-17`, `SAM-15`).

---

## 6. Persistence — the largest single technical gap

**Today:** one JSON file per session in the documents directory (`session_repository.dart`), plus 129 `SharedPreferences` keys. No schema, no migrations, no queries, no constraints.

**Required:** `DAT-01` asks for a relational database with migrations; `PKT-03` asks for a `UNIQUE(dayKey, speciesId)` constraint that makes double-awarding *technically impossible*; `DAT-03` asks for an append-only `ScoreEvent` journal with `recomputeAllScores()`; `NFA-11` asks for immediate persistence rather than persist-on-session-end; `NFA-12` asks for tested upgrade *and* downgrade paths.

None of that is expressible in JSON files. **Drift (SQLite) is the right call** — it is what the specification recommends, and this query shape (group by day, group by week, unique constraints, aggregates for charts) is exactly what it is good at.

**There is no legacy migration to write (D22).** An earlier draft of this document planned a JSON→SQLite migration of BirdNET Live's saved sessions, including retroactive scoring at historical weeks. That was wrong: **Smartfinch ships under its own application ID and installs alongside BirdNET Live** (§8), so platform sandboxing puts the old app's files out of reach. A fresh Smartfinch install starts empty, and `LOG-12` in its original sense has nothing to do.

What replaces it:

1. **Build the database before Phase 0 reaches any real user.** Then no Smartfinch install ever holds JSON sessions, and the migration never has to exist. If Phase 0 does go out to testers first, a one-off import is needed — cheaper to avoid than to write.
2. **Restore reinstates, it does not recompute** (`SET-07`, `LOG-12` as rewritten). A backup carries the `ScoreEvent` journal, and every event already holds its frozen base value, level, `geoWeek`, grid cell and applied threshold (`PKT-15`). The restore writes them back unchanged — no historical geo-model lookup, so nothing can go wrong in one.
3. **`recomputeAllScores()` must be safe to run over restored events.** It re-derives multipliers and bonuses only; the frozen fields stay authoritative. Worth an explicit test, because this is the one path where a bug would rewrite a real child's history.
4. `DAT-07` (`profileId`) and `DAT-08` (`updatedAt`, `syncState`, stable UUIDs) cost a handful of columns **in the first schema** and are effectively unbuildable later. Include them now.
5. `NFA-12` keeps its full weight — it is about *future* Smartfinch schema changes, which will happen. Tested upgrade and downgrade paths, every time.

---

## 7. Upstream merge strategy (decision D2)

The fork keeps merging from `birdnet-team/birdnet-live-app`. Deleting 20,000 lines that upstream still maintains makes that harder, but it stays manageable if the boundary is explicit.

**Rules:**

1. **Do not restructure** `features/inference`, `features/audio`, `features/recording`, `features/spectrogram`, `core/services/asset_pack_service`. Additive changes only. These are where upstream fixes land, and where a rename costs a conflict on every future merge.
2. **All Smartfinch code goes in new directories** — `features/scoring`, `features/collection`, `features/journal`, `features/awards`, `features/avatar`. New files never conflict.
3. **Deletions are recorded once.** Deleting `features/survey` produces a "deleted by us" conflict on every upstream touch of it; resolve with `git rm` and move on. Keep a `docs/developer/upstream-merge.md` listing the deleted trees so the next person resolving a merge does not resurrect them by accident.
4. **`lib/app.dart`, `lib/main.dart`, `home_screen.dart` and `settings_screen.dart` are permanent conflict zones.** They diverge in both directions. Accept it, and keep the Smartfinch versions small so the conflicts stay readable.
5. **ARB files will conflict constantly.** Upstream adds research strings, Smartfinch deletes them. Consider putting Smartfinch strings in a separate ARB namespace if `flutter gen-l10n` supports it in this setup — verify before committing to it.
6. **Pin the merge cadence.** Monthly, or on every upstream model bump. Merging quarterly is how a fork silently becomes a hard fork.

---

## 8. Rebranding checklist

Mechanical but wide, and easy to half-finish:

- `pubspec.yaml`: `name: birdnet_live` is the Dart package name, and it appears in **every** `package:birdnet_live/...` import
- Android application ID `de.tu_chemnitz.mi.kahst.birdnet_live`, iOS bundle ID, Windows installer identifiers — use a **new** ID, so Smartfinch installs alongside BirdNET Live rather than replacing it on a researcher's phone
- `assets/images/app-icon.png` and the adaptive-icon background; regenerate via `flutter_launcher_icons`
- App name in all 12 locales, store listings in `dev/store/`, mockups in `dev/mockups/`
- `README.md`, `mkdocs.yml`, 154 files in `docs/user/`, `CITATION.cff`, `LICENSE` attribution
- **Attribution obligations stay.** The BirdNET model licence (`MODEL_LICENSE`) and the Cornell / TU Chemnitz credit are not optional and must remain visible in the About screen. A children's app does not get to drop them.

---

## 9. The build plan

Every decision is settled and all eight MVP specification gaps are closed, so this is a work list rather than a sketch. Steps are numbered for reference; **the arrows mark real dependencies** — everything else can move.

### Step 0 — One afternoon, before anything else

**0.1 · Measure the annual swing** (specification 2.10). Run `predictAllWeeks()` over the target region and count: how many species change tier over the year, by how many steps, and how many leave the local list entirely. **Break it down by taxon group** — birds, amphibians, mammals, insects — because D17 puts them all on one scale and that is the assumption most likely to need revisiting.

This is the only piece of work whose result changes what gets built. It tells you whether the seasonal story is worth a UI (`PKT-17`, `SAM-15`), and whether non-birds land sensibly on the shared scale. It is an afternoon of work and it can run in parallel with everything in Phase 0.

### Phase 0 — Clear the ground

*No new features. The app at the end still does exactly what Live mode did, minus screen-off operation. Ship it internally: if something is broken, you know it was the deletion.*

**0.2 · ⚠️ Extract the background recording → blocks 0.3.**
Lift the foreground-service lifecycle out of `features/survey/survey_notification.dart` into `shared/services/background_recording/` — start, stop, notification, permissions, nothing survey-specific. Reduce or delete `foreground_service_guard.dart` (with ARU and Survey gone there is nothing left to arbitrate). Leave it **unwired**, compiling, with its tests. *This must happen before 0.3 or `LIVE-10` becomes a rewrite.*

**0.3 · Delete the research modes.** ✅ *Done: 46 files, 20,601 lines — `lib/` went from 78,836 to 58,235 lines.* `features/survey`, `features/aru`, `features/point_count`, `features/file_analysis`, `shared/services/shared_media_service.dart` and their tests.

Two things the deletion exposed, both now gone: `app.dart`'s `_AudioWorkflowProbe` — 375 lines that arbitrated which of five modes owned the microphone, including a cold-start storage scan for unfinished ARU deployments — and `QuickListenSafety`, a registry of "recording screens Quick Listen must not replace" that was left with no callers at all. `app.dart` is down from 872 to 373 lines.

**Left for the rebuild that removes them anyway:** voice memos and the session map (`voiceMemoPath` runs through ~20 places in the 5,730-line `session_review_screen`, which phase 2.5 rebuilds), the Raven/GPX writers (inside `session_export.dart`), and the expert inference controls (they belong to 0.5).

**0.4 · Collapse what the deletion exposed.** *Revised while doing it — the original wording asked for more than is worth doing now.*

**Done:** the Help screen no longer explains five modes that do not exist (it was telling users about Point Count, Survey, File Analysis, Batch Analysis and ARU). The session-type **filter** is gone — a filter offering one option filters nothing. `SessionType` and the survey/ARU block in `SessionSettings` are documented as legacy, with a note saying what may and may not be built on them.

**Deliberately not done:** collapsing `SessionType` to a single value, deleting `session_type_visuals.dart`, and pruning the twelve `features/history` files that branch on the type. Three reasons: the enum values **are the on-disk format**, so a legacy session file must still deserialize rather than be skipped as corrupt; the branching code lives in `session_review_screen`, `session_library_screen` and `html_report`, which phase 2.5 rebuilds as the Journal, so the work would be thrown away; and the type disappears for real in **1.1**, where the Drift session table simply has no type column. Keeping the values also keeps the existing history tests meaningful — they verify that legacy sessions still load.

**The general rule this produced, worth applying to the rest of Phase 0:** delete what is *wrong in front of a user* now; leave what is merely *unused* to the rebuild that removes it anyway.

**0.5 · Reorganise Settings** (D13). Plain first screen: appearance, sounds and haptics, location, privacy, storage. Everything else behind **Advanced settings**. Delete only the expert inference block. The species-filter mode and the confidence slider both land in Advanced and both need the `SET-13` warning — which means `PKT-20` has to exist by then, so either do 0.5 after Phase 1 or ship the settings move first and the warning with the engine. ✅ *Done after Phase 1, so the warning shipped with the move rather than after it — 13 tests.*

**The split.** `SettingsScreen` renders either half, chosen by a new `SettingsView`. Plain: general, announcements, location, privacy, about, danger zone, plus the tile that opens the other half. Advanced: audio, inference, spectrogram, recording, playback, the species filter and export. The Location section split in two — the GPS switch stays on the plain screen, because without a position there is no rarity level and therefore no stars (`SET-09`), while the filter mode changes what counts as a detection and belongs behind Advanced.

*This replaced `SettingsContext`, which tagged every section with the research modes it belonged to. With those modes gone every section applied to every remaining context, so the mechanism filtered nothing. The map is now one entry per section, and a test asserts that both views are populated — a section on neither screen would otherwise break SET-01's "nothing is lost" promise without anything visibly failing.*

**The deletion.** Sensitivity, the pooling block and the species ignore list are gone, along with the ignore-species sheet and its test. Every provider stays wired, persisted and exported, so the pipeline runs on the shipped defaults — the header comment in `settings_screen.dart` now records what those are, since there is no longer a UI that shows them.

**`SET-13`.** Both settings confirm before they pause scoring, and the dialog says all four things the requirement asks for, including the streak consequence. Two details worth keeping: the confidence slider draws the floor on its own track (`secondaryTrackValue`), so 35 is visible *before* the drag rather than only in the warning afterwards; and the confirmation fires on release, not on change — a slider reports every intermediate value, so confirming in `onChanged` would open a dialog the instant the thumb crossed 35 and again on the way back. Raising the threshold never asks, and a threshold already below the floor does not ask again.

*Still open from `PKT-20`: `LIVE-18`, the indicator in Live mode saying scoring is paused, and `LOG-15`, the journal entries flagged as outside scoring. Both need screens that phase 2 builds.*

**0.6 · Platform cleanup.** ✅ *Done, and it turned up a half-finished deletion from 0.3.*

**The native side had been left behind.** 0.3 removed the Dart half of File Analysis and ARU but not the platform half: the Android manifest still advertised the app as an `ACTION_SEND` / `ACTION_VIEW` target for `audio/*`, `MainActivity.kt` still served `com.birdnet/shared_media` and the two ARU notification channels, and iOS still declared `CFBundleDocumentTypes` with an `AppDelegate` that answered on a channel **no Dart code listens to any more**. Share an audio file with the app and it would have appeared in the share sheet and then done nothing. A children's app has no business being a general audio import target either. All of it is gone: `MainActivity.kt` 595 → 319 lines, `AppDelegate.swift` 374 → 93.

**Permissions.** `ACCESS_BACKGROUND_LOCATION` and `FOREGROUND_SERVICE_LOCATION` removed; `foregroundServiceType` narrowed from `microphone|location` to `microphone`; iOS `UIBackgroundModes` lost `location`. `FOREGROUND_SERVICE_MICROPHONE` and the `audio` background mode stay — 0.2 rescued the service they belong to. `ACCESS_FINE_LOCATION` stays because Geolocator needs it to reach GPS at all.

**Accuracy.** `buildLocationSettings` now defaults to `LocationAccuracy.low` instead of `.high`. A 0.1° cell is 7–11 km across, so metre-level precision was being discarded by the rounding while costing a GPS wake-up; `low` also lets the platform answer from a cached or network fix. GPS stays the source — only the request changed.

**ARB pruning: deliberately deferred.** 422 of 1,107 keys in `app_en.arb` are unused — a third of the file, and 12 locales deep. Removing them now is half premature: phase 2 rebuilds Home, the Journal, the Collection and Settings, which will retire more keys and add others. Tote keys are invisible to a user, so by the rule from 0.4 they wait for the rebuild that touches them anyway. **Do it once, after phase 2**, and preferably with a script rather than by hand.

**0.7 · Rebrand identifiers.** ✅ *Done for everything that ships in the binary.*

| What | From | To |
|---|---|---|
| Dart package | `birdnet_live` | `smartfinch` — 250 import lines across 109 files |
| Android `applicationId` **and** `namespace` | `de.tu_chemnitz.mi.kahst.birdnet_live` / `com.birdnet.birdnet_live` | `de.tu_chemnitz.mi.rajs.smartfinch` |
| Kotlin package path | `kotlin/com/birdnet/birdnet_live/` | `kotlin/de/tu_chemnitz/mi/rajs/smartfinch/` (directory move + `package` declarations + the asset pack's manifest) |
| iOS bundle ID | `de.tu-chemnitz.mi.kahst.birdnet-live` | `de.tu-chemnitz.mi.rajs.smartfinch` (6 occurrences incl. RunnerTests) |
| Display name | "BirdNET Live" | **Smartfinch** — Android label, `CFBundleDisplayName`, `appTitle` in all 12 ARBs, Windows window title |
| Windows | `birdnet_live` project/binary | `smartfinch`, plus a **fresh installer `AppId` GUID** so it does not present itself as an update to an installed BirdNET Live |

The application ID is deliberately a *new* one, so Smartfinch installs alongside BirdNET Live rather than replacing it on a researcher's phone — and it keeps its own institutional namespace (`…mi.rajs…`) rather than inheriting `kahst`.

**Left alone on purpose:** the platform channel names (`com.birdnet/wakelock`, `com.birdnet/audio_decoder`, the `com.birdnet.live.notification_icon` meta-data). They are internal contracts that must match on both sides of the bridge, they are invisible to users, and renaming them is risk without benefit. Rename them whenever the native code is touched for another reason.

**Still open:** the **app icon** is still BirdNET Live's (`assets/images/app-icon.png` + the adaptive background), so `flutter_launcher_icons` has nothing new to generate from. Store metadata in `dev/store/`, the mockups in `dev/mockups/`, `README.md`, `mkdocs.yml` and the 154 files in `docs/user/` also still say BirdNET Live — none of it ships in the binary, so it does not block anything, but it should be done before any release. **`MODEL_LICENSE` and the Cornell / TU Chemnitz credit in About stay untouched** — those obligations do not go away with a rename.

### Phase 1 — Foundations, no UI

*Nothing here is visible to a child, and none of it can be retrofitted later.*

**1.1 · The Drift schema.** ✅ *Done — `lib/core/database/`, 8 tables, 12 tests.*

Eight tables in two layers: **raw** (`Sessions`, `Detections`) written always, **scoring** (`ScoreEvents`, `DaySpecies`, `YearSpecies`, `LifeSpecies`, `Achievements`, `UserProfiles`) written only while scoring is active (`DAT-11`). Species names, images and rarity levels are **not** in the database — they come from `taxonomy.csv` and the geo model, which already ship; §6.2 of the specification listed them as entities, but that sketch predates the codebase review.

All six unretrofittable fields are in schema version 1: `profileId` (`DAT-07`), `updatedAt` + `syncState` + UUID primary keys (`DAT-08`), `scoringPaused` on `Detections` (`DAT-11`), and `highestLevelReached` on `UserProfiles` (levels ratchet).

**The rules are constraints, not code.** `UNIQUE(profileId, dayKey, scientificName)` makes double-awarding impossible (`PKT-03`) — the database refuses the second insert, so it is not a bug a later refactor can reintroduce. Same for the life list and the year list. `PRAGMA foreign_keys = ON` in `beforeOpen`, because SQLite leaves them off and a journal referencing a deleted detection would otherwise be silently possible.

Two things the tests pin down that are easy to break later: a **paused detection leaves every scoring table empty** (especially `LifeSpecies` — writing there burns the first-find ×3 forever), and a **`ScoreEvent` round-trips all six frozen fields** including the applied threshold, without which moving the settings slider would rewrite what the history meant (`D16`, `NFA-06`).

*Generated code (`*.g.dart`) is gitignored, like the l10n output — it would conflict on every upstream merge. Run `dart run build_runner build` after changing a table.*

*Side fix: `assets/species_data/` now has a tracked `.gitkeep`. Without the directory `flutter test` and `flutter build` fail outright on a fresh clone, which looks like a bug rather than a missing bundle build.*

**1.2 · Extract the rarity scale** (`DAT-10`). ✅ *Done — `core/services/grid_cell.dart`, `features/scoring/rarity_scale_provider.dart`, 23 tests.*

`GridCell` is now the app's one notion of "roughly here": 0.1°, stored as integer tenths rather than doubles so equality is exact — `0.1 * 508` is not `50.8` in binary floating point, and a cache key that compares unequal to itself would rebuild the scale on every lookup.

`RarityScaleCache` builds and caches scales keyed `(GridCell, geoWeek)`, with an LRU of 6 — enough for a home cell, a school route that crosses a boundary, and a weekend trip. **`peek()` is the method a detection uses**: synchronous, never triggers work, returns null rather than blocking the audio pipeline on 48 inferences. In-flight requests are shared, so Explore and a detection asking at the same moment cost one inference run rather than two.

**Explore now reads the same scale** — the actual point of `DAT-10`. It still runs `predictAllWeeks()` itself for the annual cycle bar (`SAM-15`), which the cache does not keep because scoring only needs the current week; but the *tier boundaries* come from the shared object, so a bird's tier in the Collection is by construction the tier it scores with.

`RarityScale.tierFor()` returns **null for a species below the inclusion threshold**, not the top tier — the off-list rule that awarded full points was removed in D20, and this is where rule and filter finally say the same thing.

*Two corrections while building: `rarityScaleCacheProvider` is a `FutureProvider` rather than a synchronous one that throws when the geo model is not loaded — pretending the dependency is not there only moves the wait somewhere less obvious. And the position re-check every few minutes belongs with the Live integration in 2.1; the cache is ready for it, but nothing polls yet.*

**1.3 · `ScoringRules` as a versioned configuration object** (`DAT-04`). ✅ *Done — `features/scoring/scoring_rules.dart`, 28 tests.*

Every number from chapter 2 in one `const` object: the tier→stars table, the four multipliers with the highest-wins rule (`PKT-07`), the five cumulative variety bonuses, early riser, new place, week wrap-up, the loyalty days, and the scoring floor of 35. Entries at P1 and P2 are defined too — an unused number costs nothing, and having it written down is what makes the later step an edit rather than a design discussion.

**The trap worth naming:** `ExploreTier` runs `rare` (index 0) → `abundant` (index 5), while §2.3's table lists common first. Reversed, every blackbird is a sensation and every hoopoe worthless — and it looks entirely plausible in a debug print. Three tests pin the direction down, including one that walks the tiers and asserts values rise monotonically as species get rarer.

**§2.8's worked examples are now tests**: an ordinary May garden day comes to exactly 1,500 stars, the same day as a very first day to 4,100. If a later rebalance moves those, it moves them deliberately.

*On versioning: `version` is recorded on every `ScoreEvent` so a day stays explainable ("scored under rules v1"). It is **not** a way to re-score old events under old rules — `recomputeAllScores` re-derives multipliers and bonuses under the current rules and never touches the frozen base value (`PKT-15`). That is the point: a rebalance should apply retroactively, or badges earned under the old rules could never be recomputed (`AUS-12`).*

**1.4 · The scoring engine** — pure Dart, no Flutter imports, no UI. `PKT-01`…`PKT-08`, `PKT-15`, `PKT-20`. Awards on the first window over threshold, writes peak confidence back on close (D15). Freezes base value, level, `geoWeek`, cell, applied threshold. Writes nothing to the scoring layer while paused. ✅ *Done — `features/scoring/scoring_engine.dart`, 46 tests.*

*The engine decides; it never writes. `ScoringOutcome` carries `addToLifeList` / `addToYearList` as flags for the caller rather than performing the write itself, because writing a life-list row for a detection that did not score burns that species' first-find ×3 permanently (`DAT-11`) — and nothing in the app could later explain to a child why their real first find was worth 100 instead of 300. Keeping the decision and the write apart makes that a testable property instead of a hope.*

*A note on the test scales: tiers are **rank-relative**, so a scale built from a handful of species does not populate all six bands — the bottom species becomes the scarce edge and `rare` stays empty. The first draft of the tests did exactly that, and its two ceiling assertions passed while testing nothing. The scales now hold 40 species and every worked example asserts its tier alongside its star count.*

**1.5 · The test suite** (`NFA-14`, `NFA-06`). Chapter 2's worked examples as a table-driven test, plus: the once-per-day rule, highest-multiplier-only stacking, cumulative variety bonuses, `dayKey`/`isoWeek` across timezone and DST edges, and — separately — that a paused detection touches neither the life list nor `DaySpecies`, and that `recomputeAllScores()` respects the flag and never rewrites a frozen base value.

*Mostly covered by 1.3 and 1.4 (74 tests across the two files): all nine §2.7 worked examples with their tiers pinned, week coupling (the same blackcap at 100 in May and 600 in January), the ×3 ceiling under every multiplier combination, `dayKey` across midnight and both 2026 DST transitions, and each `ScoringSkipReason`. What remains needs the persistence layer and therefore belongs with 2.1: that a paused detection leaves `LifeSpecies` and `DaySpecies` untouched **on disk**, and that `recomputeAllScores()` honours `Detections.scoringPaused` and never rewrites a frozen base value.*

> **Phase 1 is done when the tests pass, not when something is visible.** Resisting the urge to build UI here is the difference between a scoring system you can rebalance in an afternoon and one you cannot change at all.

### Phase 2 — Make it visible (the P0 prototype)

*This is what a real child uses for two weeks.*

**2.1 · Wire the engine into Live.** Detection → `ScoreEvent`, using the shared scale from 1.2. ✅ *Done — `scoring_repository.dart`, `live_scoring_coordinator.dart`, `scoring_providers.dart`, 48 tests.*

**Three pieces, and the split is the safety property.** `ScoringEngine` decides, `ScoringRepository` writes, `LiveScoringCoordinator` carries values between them and decides nothing. That means **every write to `LifeSpecies` goes through one method in one file** — the rule that protects the first-find ×3 has exactly one place it can be broken (`DAT-11`), and a test asserts it holds for both pause triggers.

**Two transactions, not one.** The `Detection` row is written first and on its own, because it is the single source of truth (`DAT-02`); the scoring layer follows atomically. A failure in the second half then costs the child some stars, not their morning — and there is no way to leave a `LifeSpecies` row standing without the `ScoreEvent` that justifies it.

**The seam was already there.** `DetectionAccumulator` publishes exactly D15's two moments: `isNew` is the first window over threshold, so that is when the species scores; `closedRecords` is when the peak confidence is written back. The controller got one new callback and nothing else changed in the inference loop.

**Serial, not concurrent.** Scoring is four queries; inference must not wait (`NFA-13`). Detections are queued and drained one at a time — not for tidiness, but because two concurrent detections of one species would both read "not scored today" and both try to insert the same `DaySpecies` row. The constraint would hold, but the child would see a detection fail for no reason they could understand.

*Two things caught while wiring, both about lifetime.* A live session **outlives its screen** — leaving Live mode keeps recording — so the first version's callback, which captured the screen's `ref`, would have thrown partway through a walk and quietly stopped scoring the rest of it. The coordinator now reads its conditions through the provider's own `ref`. And it reads them **per cycle rather than at session start**, so an adult who switches the species filter back on mid-walk does not have to restart the session for the child to start earning again.

**2.2 · Live mode UI** (`LIVE-02`…`LIVE-08`), laid out **around** the full-size spectrogram (D7): star chip per card, "already collected today ✓" on repeats, multiplier chip, day total in the header. Then the celebration layer: confetti and the non-modal species card, with the queue from `LIVE-07` so a walk in the woods cannot stack five popups. ✅ *Done — `live_score_board.dart`, `day_summary_bar.dart`, `score_chips.dart`, `first_find_celebration.dart`, `celebration_queue.dart`, 40 tests.*

**A board, not a query.** The detection list rebuilds on every inference cycle, so a card asking the database what its species earned would be a query per row per second. `LiveScoreBoard` holds the answers in memory, written once as each detection is scored. It is a view of the **day**, not of the session: a child who stops and starts three times before lunch has one day, and the blackbird from the first outing still says "already collected today" in the third.

**The card never shows a bare number.** `NEW ×3` before `⭐ +300`, because a child who sees 300 where they saw 100 yesterday decides the app is arbitrary unless the chip says why (principle 6). A repeat *replaces* the number with the ✓ rather than sitting beside it — two answers to one question is exactly the confusion `LIVE-03` exists to remove. And a species first heard while scoring was paused says "heard again", not "already collected", because the second would be a lie.

**`LIVE-18` shares the bar with `LIVE-08`.** Same slot, two states, because they answer the same question: *what has today been worth?* The notice is styled as information, not as a warning — no red, no exclamation mark — and it names the effect ("no stars") rather than the cause ("species filter disabled"). A test asserts it is not `errorContainer`, since that is the kind of thing a later refactor changes without noticing.

**The celebration queue is where `LIVE-07` lives.** Finds within 900 ms of each other become one card — "3 new species!" — and anything arriving while a card is up waits for it. Tested with `FakeAsync`, so six seconds of card time costs nothing to run. The confetti is a `CustomPainter` rather than a package: ninety lines against a dependency for two seconds of animation, and `MediaQuery.disableAnimations` skips it while keeping the card — losing the feeling is an accessibility setting, losing the information would be a bug.

*One real bug found by a test: the card's six-second auto-dismiss was a `Future.delayed` with no way to cancel it, so a swipe-dismissed card kept a timer alive behind a screen that had gone away. Now a `Timer`, cancelled in `dispose`.*

**2.3 · The scoring-paused surface** — `LIVE-18` in live mode and on the home star header, `SET-13` at both settings. Suppresses the first-find celebration while paused. *Mostly done ahead of schedule: `SET-13` shipped with 0.5, and `LIVE-18` plus the suppressed celebration with 2.2 — the paused case was cheaper to build alongside each surface than to retrofit. **What remains is the home star header**, which 2.4 builds; `ScoringPausedNotice` is already public and takes a `compact` flag for it.*

**2.4 · Home screen** (`HOME-01/02/03/08`): star header with total, last 30 days and today; one large Live tile; secondary tiles for Sammlung, Erkunden, Tagebuch, Punkte, Einstellungen. ✅ *Done — `star_header.dart`, `home_tiles.dart`, 12 tests plus 7 on the repository queries.*

**The carousel is gone.** It made sense with six modes; 0.3 deleted five and left a carousel of one card with two page-indicator dots under it — the clearest example yet of the 0.4 rule about deleting what is *wrong in front of a user*. What replaces it says what the app says: one large Live tile, then equal secondary tiles. `home_screen.dart` went from 796 to 462 lines, and Journal, Explore and Settings moved out of the footer into the grid, leaving Help and About behind.

**Three numbers, three questions.** The **total** is what a child has built, the **last 30 days** is whether they are still building it, and **today** is the only one that can still be changed before bedtime. A test asserts the total renders larger than the 30-day figure, because "total large, small beside it" is the requirement and a later restyle could satisfy the words while inverting the point. An empty header shows `0` rather than a spinner: a child arriving at a fresh home screen should see a number they understand.

**Two tiles are deliberately missing.** Collection and Points arrive with 2.6 and 2.7, and until then they are **absent rather than greyed out** — a disabled tile is not something an eight-year-old reads as "later", and one that opens an empty screen is a broken promise. A test asserts they are not there, so adding each one is a single entry in `_secondaryTiles` and a one-line test change.

**`LIVE-18` reached its second surface.** The home header shows the identical notice live mode does, from the same widget, so the two cannot drift apart. That completes 2.3.

*One thing to decide, not a blocker:* the Live tile is labelled **"Live"** in all twelve locales. `AGENTS.md` explicitly retired the old rule that kept *Live Mode* in English — it "belonged to a research tool" — so this wants a German word. It is the app's central noun, though, and renaming it touches a lot of strings, so it is worth choosing deliberately rather than in passing.

**2.5 · The Journal** (`LOG-01/02/03/09/13/15`) — the largest single UI job. Day cards, day detail with per-species points and the applied multiplier, ✨ NEW markers, child-written place names, and out-of-scoring detections shown with their note. ✅ *Done — `features/journal/`, 41 tests.*

**A second repository, deliberately.** `JournalRepository` reads; `ScoringRepository` writes. Putting the journal's queries in the scoring repository would have buried its one real guarantee — that every path into `LifeSpecies` runs through one method in one file (`DAT-11`) — under three hundred lines of `SELECT`. Nothing in the journal layer can award a star.

**A day comes from two sources.** Days with stars come from `ScoreEvents`; days that produced only paused detections come from `Detections`. Reading only the first would make an afternoon of test-mode listening vanish, which is exactly what `LOG-15` promises cannot happen — so there is a test for a day whose entire content is unscored.

**Two lists, not one list with a flag.** `JournalDayDetail` keeps `scored` and `outsideScoring` apart in the *data*, so a screen cannot accidentally total them in. The day card follows: "8 species · ⭐ 450" with "3 more outside scoring" underneath, and the second line is a note rather than a warning — a test asserts the banner is not `errorContainer`, the same guard `LIVE-18` got.

**✨ NEW is read from the life list, not from the day.** First time *ever*, not first time today — so reopening a day next month still marks the right species. Three tests cover that, including the one that matters: the original day keeps its marker after the species is heard again weeks later.

**`LOG-13` is editable, which is the point.** A walk gets named in the evening, when there is time to think of a name for it; during the walk the child is looking at birds. The dialog also offers names used before (`LOG-14`, ahead of schedule) — one tap for "Oma", and the same place keeps the same spelling, which is what makes a per-place view possible later.

**Sessions left navigation** (`LOG-01`). The home tile and the post-session hand-off both point at the Journal now; the session library has no entry point left. It and `session_review_screen` stay in the tree because §3.4 keeps what they carry (export writers, clip playback), and removing them is its own step rather than a side effect of this one.

*Still open from chapter LOG:* `LOG-04` (day/week/month/year), `LOG-05` (sticky month header), `LOG-07` (expandable individual detections) and `LOG-11` (share a day as one image) are all P1 and none of them are load-bearing for the field test.

**2.6 · The Collection** (`SAM-02`…`SAM-05`, `SAM-17`) as its own area: found species only, all taxon groups by default with a group filter, the placeholder for open ones, progress counter. **Per-species silhouettes are P1** (`SAM-04b`), so this step needs no pipeline work — but it does need the species bundle to have been built at least once, or every cell shows the placeholder and the Collection looks broken. ✅ *Done — `features/collection/`, 19 tests.*

**"Found" means `LifeSpecies`, and nothing else.** That table is what the first-find ×3 checks (`PKT-04`), so the album and the scoring engine cannot disagree. Had the Collection drawn its own conclusions — from raw detections, say — a child could see a species in their album and then be awarded ×3 for "finding" it a week later, with nothing in the app able to explain which of the two was lying. The consequence is deliberate and tested: a species heard while scoring was paused is in the journal with its recording (`LOG-15`), and is **not** in the album.

**⚠️ That fixed a live inconsistency.** `detectedSpeciesSetProvider` — the ticks Explore draws — was computed from the on-disk *session files*. That was right when a detection was simply a detection; it is wrong now, and on a fresh Smartfinch install (where the JSON store is empty by design, gap H) Explore would have shown nothing ticked while the album filled up. It now reads the same life list.

**A resolved tension in the requirements.** `SAM-02` says the Collection "shows only what the child has actually found"; `SAM-04` rests the whole Pokédex effect on the contrast between filled and empty cells, and `SAM-05` counts "37 of 128". The grid therefore shows the local list with found/open contrast, and **"only mine" is a filter rather than the starting state** — a grid of only what you already have has nothing to fill. `SAM-02`'s sentence is about the distinction from Explore, which still holds: two destinations, two questions.

*Two small deliberate choices.* An open cell keeps its **name** — the album is a wanted list, and a row of question marks is not one. And an empty result distinguishes "you have nothing yet" from "nothing here matches this filter", because telling a child the first when the second is true is discouraging for no reason.

**Progress is against the local list**, not against everything the model knows: 37 of 128 is a number a child can act on, 37 of 9,789 is not.

*The bundle caveat from the plan still stands* — without `tools/build_species_bundle.py` having run, every collected cell falls back to a blank tile. It fails quietly rather than as a crash, but it does make the album look wrong.

**2.7 · Points area and badges** (`STAT-01/02/05/06`, `AUS-01/02/03`): tabs, the 30-day bar chart with empty days shown as empty, key figures, and the three P0 badge groups. ✅ *Done — `features/points/`, 35 tests.*

**Nothing is stored.** Every badge and achievement is derived from `DaySpecies`, `ScoreEvents` and `LifeSpecies` on demand rather than written to the `Achievements` table. That is what `AUS-12` asks for — after a rebalance, badges already earned must still be derivable from history — and it means a rule change cannot leave a stale row for someone to find months later. The table stays for the day an unlock animation needs to know whether something is *newly* earned (`AUS-08`, P1).

**`STAT-06`'s definition of an active day is load-bearing and now tested.** A day counts when it produced at least one *scoring* detection — which is exactly what a `DaySpecies` row is. So a day spent entirely in test mode is not an active day and does not extend a streak, and there is a test that walks precisely that: active, paused, active → two active days, longest run of one.

**The empty columns are the point of the chart.** Omit them and five scattered days across a month draw the same shape as five days in a row, so the chart would tell every child they are consistent. Kept, an empty day is a visible sliver rather than nothing — a bar of zero height is indistinguishable from no bar at all. Hand-drawn: thirty bars is a `Row` of `Container`s, and a charting dependency would cost more than it saves.

**The streak figure is the *longest*, never the current one.** `AUS-07` says a broken streak is not commented on, so the screen carries no number that can fall to zero overnight. The chart already says it, quietly, and once is enough.

**Loyalty badges are derived from the days, not from the multiplier.** The multiplier on a `ScoreEvent` records what was *paid*, and only the highest one ever is (`PKT-07`) — so a species that was a first find on the day it also became a Regular would have no ×2 to find. Counting the days directly is the only reading that cannot lose a badge.

**`AUS-02` is honoured literally:** unearned badges are not shown greyed out. `AUS-04`/`AUS-05` bring the full day and week catalogue at P1, where an open badge reads as a goal rather than as a gap. The Achievements tab does show one line for the next medal, which is a goal without being a row of eight faded ones.

**The tile grid is complete.** Sammlung · Erkunden · Tagebuch · Punkte · Einstellungen, with a test per tile asserting it actually opens its screen.

**2.8 · Child-facing polish**: animation level (`SET-02`), the rules page (`SET-11`) including "why do the points change during the year?", clip retention (`SET-12`), onboarding with the home region on the permissions screen (`KID-01`, `SET-09`). ⚠️ *Three of four done — 28 tests. `SET-12` is blocked and needs its own step; see below.*

**`SET-02` · Animation level** — Full · Reduced · Off, on the plain settings screen because it is an accessibility setting as much as an annoyance control. `SET-03` came with it: a system-wide reduce-motion preference pulls Full down to Reduced, leaves an explicit *Off* alone, and is **not written back** — turning the system preference off restores what the child chose rather than what the phone decided for them. *What no level removes is the information:* at every setting the life-list row is written, the ×3 is paid and the journal marks it ✨ NEW. Only the celebration is a setting.

**`SET-11` · The rules page** — principle 6 as a screen. Two things make it work and both are easy to lose in a redesign. **The numbers come from `ScoringRules`**, not from the prose: a page with them typed in would go quietly wrong on the first rebalance, and be wrong in the one place a child goes to check. A test asserts every tier's real value appears. And **"Why do the points change during the year?" is its own section**, which the requirement names — without it week coupling looks like a bug: same bird, same app, a different number. The location half sits beside it, because the value moves with the place too and a child on holiday needs to have been told in advance.

**`KID-01` / `SET-09` · Onboarding** — five screens became four. The two info pages were one thought and merged; the home region joined the permissions page rather than adding a fifth. With location granted there is nothing to ask. Without it — declined, unavailable, or a desktop build — the child picks a place **on a map**, because `SET-09` is explicit that this must work for a child and two decimal numbers are not something an eight-year-old has. Picking a home also switches GPS off, since otherwise the coordinates they just chose would be ignored the moment a fix arrived.

**`SET-12` · Clip retention** ✅ *Done in the two steps its blocker forced — `features/storage/`, 22 tests.*

**The blocker, for the record.** The retention rule ranks clips by species and confidence, which means reading them from `Detections`. But `DetectionClipWriter` attached clips to the **in-memory `DetectionRecord`** only — `Detections.audioClipPath` existed and nothing ever filled it. Built in one pass, this would have been a job with nothing to read.

**Step one: the clip path reaches the row.** A new `onClipAttached` hook on the writer, routed through the controller to `LiveScoringCoordinator.submitClip`, queued like every other write so it cannot interleave. *One thing had to change to make it work:* the coordinator used to **remove** a detection's row id when the detection closed. Cutting a clip means waiting for post-roll and then encoding, so clips routinely land after the close — every one of them would have been silently dropped. Ids now survive the close and are cleared when the session ends, and a test covers exactly that ordering.

**Step two: the policy.** Pure over rows, so "would this remove the only nuthatch?" is a question a test can ask without a filesystem. **Most-recorded species first, lowest confidence first within a species** — a plain oldest-first rule would delete exactly backwards, since a child's earliest recordings are the ones they were most excited about. Two thresholds, both generous and both adjustable: 30 days and 100 clips per species.

**Favourites are excluded before anything is ranked, and still occupy the cap.** Excluding them from the count would let favourites quietly raise the ceiling; counting them is what lets the app say "12 of your 100". A library of nothing but favourites therefore loses nothing and stays over the cap — deliberate, because the alternative is breaking the one promise the clean-up rests on.

**The job deletes the file first, then clears the row.** The reverse would leave orphaned audio that nothing in the app can find or count. A file that cannot be removed keeps its path, so the next run retries rather than losing track of it. It runs once per app start, off the critical path — a clean-up competing with inference for the disk is one that drops frames (`NFA-13`).

*What is not built:* the UI for marking a favourite. `ScoringRepository.setClipFavourite` is there and the policy honours it; the toggle belongs on the clip player, which `LOG-07` opens up at P1.

### Phase 3 — Version 1.0

The specification's P1, with one reordering: **pull the year list forward** (`PKT-12`, `SAM-16`, `AUS-13`). Since D20 removed the off-list case, the year list is the main way a child experiences the year changing (§5), and `PKT-12` is cheap enough to belong in P0 if there is room. Then `PKT-17` and `SAM-15` early, because until the app explains why points move, the movement reads as a bug.

**The year list is done** ✅ — 39 tests. Three requirements, and the first turned out to be free.

**`PKT-12`** was already complete. The ×2 and the `YearSpecies` write went in with phase 1, because at that point they cost one enum value and one insert — the recommendation to consider pulling it into P0 was right, and it happened without anyone deciding to.

**`SAM-16` · the year list as a second collection.** The album's "only mine" toggle became a three-way scope: **All · Only mine · This year**. A segmented control rather than a third chip, because they are three views of one grid and only one can be true. The consequence worth naming: a species on the life list but not heard since January is **found** in the collection and **open** in the year view — that difference *is* the feature, and it is what makes every spring interesting again once the local region is largely exhausted (3.4).

*Two small things follow from it.* The progress line says "1 of 2 species **this year**", not the life total — the number means something different and reusing the sentence would have made it wrong. And an empty year gets its own message: in January the life list is full and the year list is not, so telling a child their collection is empty would be plainly untrue. It also says *why*, so the reset reads as the game rather than as loss.

**`AUS-13` · six achievements, derived like the rest.** From `YearSpecies` — the same table `PKT-12`'s ×2 checks, so the medal and the multiplier cannot disagree about what counted as a year first. Kept in their own section on the Achievements tab: the Collector ladder only ever grows, the year list starts again every January, and mixing them would suggest the second can be lost.

*One rule reads from somewhere else on purpose.* **All year round** counts *active days*, not new species — a month in which only birds you already had that year were heard is still a month you went outside. Each of the four rules has a calendar edge (a month boundary, March–May, December-or-January, another year's days) that would be easy to get wrong and invisible when it was; there is a test per edge.

*One test caught its own mistake:* the counted rungs were first written with 25 species in May, which also earns **The Returners**. The code was right and the expectation too narrow — moved to August, a month that is neither spring nor winter.

**`SAM-15` and `PKT-17` are done** ✅ — 23 tests. The plan pairs them, and the pairing turned out to be the whole point.

**`SAM-15` was already built.** The 48-week chart is inherited: 48 bars, the current week highlighted and outlined, month labels underneath. The specification called it "confirmed free — a chart over data that is sitting there", and it was right. What it lacked was any sentence saying what the shape *means*.

**`PKT-17` is that sentence, and it now does a different job.** Before D20 it defended a strange number; the off-list case is gone, the swings are smaller, and it is now what the specification says it became: **a phenology lesson in one sentence**. "🌱 Early! The blackcap is normally only here from April."

**A species is compared only against itself.** Its *season* is the weeks where it reaches at least half its own annual peak. That one decision is what makes the rule work for a resident and a migrant alike: a blackbird never leaves its season, never gets a hint, and correctly so — there is nothing remarkable about hearing one in February. Half is deliberately generous; a stricter bar would fire through the shoulders of a long season, and a hint that appears for four months is wallpaper.

**Most of the tests are about staying quiet**, because that is where the value is. A hint that fires for a blackbird teaches a child something false. There is a test that sweeps all 48 weeks of a resident's year and expects nothing at any of them.

*The case that needed real thought:* a **winter visitor**, whose season wraps December into January. Such a season has no lowest week that means "start" — the boundary is the week whose *previous* week is out of season. Without that it would have announced its season as starting in January and ending in November, which is exactly backwards. Tested.

**One widget, two places** — the detection card and the species detail, directly under the curve it explains — so the app cannot say two different things about the same bird on the same day. Neutral styling in both: being early is not a problem, it is the most interesting thing that can happen on a walk in March.

**`LOG-04` and `LOG-05` are done** ✅ — 38 tests. The journal can be read at four zoom levels now, and the day list keeps its place while you scroll it.

**`LOG-04` · four levels, one of which is the day.** Day · Week · Month · Year, as a segmented control above the list. Days stay the level the journal *opens* on, because that is the one a child recognises; `LOG-06`'s "pick the level from how much data there is" is deliberately deferred until there is a year of data to pick from. The wider levels exist for one reason: a year of listening is three hundred cards, and scrolling is not navigation.

**A week card counts species, not species-days.** A blackbird heard on five days of a week is *one* species that week. Summing the day counts would have been the obvious implementation and would have turned every quiet week into a busy-looking one — the number is meant to be comparable between a week and a month, and a sum is not. So a bucket collects a set across its whole span, and reports `activeDays` separately for the thing a sum actually measures.

**The number a child looks for when zoomed out is ✨.** A month with four first finds was a different month from one with none, however similar the star totals — so `newSpeciesCount` is on the card, read from `LifeSpecies.firstSeenAt` rather than from anything week-shaped. It means *first ever*, not *first since last week*: the same promise `LOG-09` makes on the day.

**Empty buckets are dropped, and that is not the choice `STAT-02` made.** A blank week between two busy ones gets no card; the 30-day chart, in the same app, draws the gap on purpose. The difference is what the reader does with it — a list is read by scrolling, and two blank cards in the middle are noise; a chart is read by shape, and a gap *is* shape.

*Two pieces of calendar arithmetic that would have been invisible when wrong.* Weeks are ISO weeks, Monday to Sunday — the same ones `PKT-05`'s loyalty multipliers count, so a child cannot be "regular" in a week the journal does not show. And months advance through `DateTime(year, month + 1)` rather than 30 days, which is the only reason February does not swallow the first of March. Both are tested at the boundary.

*One asymmetry with the day list, deliberately kept.* A day of nothing but paused listening still appears in the journal, because the recordings are still there and `LOG-15` promises nothing is lost. The same day produces no week card: a bucket is a scoring summary, and a week that scored nothing has nothing to summarise.

*Tapping a card goes one level in* — a year opens its months, a month its weeks, a week its days, and a day still opens the detail it always did. **It narrows rather than scrolls**, which was not the first instinct: "switch to the months and scroll to 2026" is the obvious reading, and it cannot be built. Both lists are capped at sixty entries, so a March week is not in the newest sixty days for any amount of scrolling to reach — and even where it is, landing a child somewhere in the middle of a long list is not the same as showing them the thing they tapped. So the deeper level *becomes* the months of 2026, and a trail across the top ("2026 › May 2026") says where they are and walks back out one step at a time. The system back button climbs the trail before it leaves the journal.

*The awkward case is the ISO week that straddles the turn of the month.* A bucket belongs to a span if it **overlaps** it, not if it sits inside: the week of 27 April appears under both April and May, and takes the first three days of May with it. Containment would have been tidier and would have made 1–3 May unreachable through the drill-down while still counting in May's totals.

**`LOG-05` · the month header stays put.** `SliverMainAxisGroup` around each month's header and its days, rather than a plain pinned header — pinning alone stacks every month at the top, one under the next, instead of April pushing May away as it arrives. The background is opaque, because the cards scroll *underneath* it. The wider levels get no header at all: a "May 2026" bar above a list of months would say the same thing twice.

**A second home-screen redesign direction is being explored, not yet built.** Phase 2's `HOME-01/02/03/08` header and tile grid shipped and works; a two-tone layout is under discussion as its successor — a colour block at the top carrying the avatar and the star figures, and a lower, surface-coloured area carrying the tile navigation, both still adapting to light/dark/dynamic-colour/high-contrast the way `AppTheme` already does today. **Neither the colours nor the tile split are settled** — mockups exist in four theme variants purely to show that the header can carry any accent, not to pick one, and the sketched 1-large-Live + 2 + 3 tile arrangement is a rough placement, not a layout requirement. The one piece meant to survive into the real design: the lower area should be built so it can later be **dragged further down** — collapsing to a small handle at the screen's bottom edge and freeing the screen above it. That is the surface a future per-level bird unlock would use, letting a child arrange their unlocked birds on screen like a small diorama before pulling the handle back up to restore the tile navigation. No requirement ID exists for this yet — it is a UI direction, not a scored feature.

### What to watch during the two-week test

Not "was it used", but the four things the design is betting on:

1. **Did the child go somewhere they would not otherwise have gone?** The real question, per the specification.
2. **Do non-birds land sensibly on the shared scale** (D17), or is a chorus of frogs worth nothing while a miscalibrated insect pays 1,000?
3. **Is the seasonal signal noticeable at all** now that the off-list case is gone?
4. **What does a month of audio clips actually cost** — the `SET-12` defaults are a guess.

---

## 10. Open points

**All eight MVP specification gaps are closed** (chapter 9 of the specification, D15–D23). Phase 1 is specified: the scoring engine can be written without anyone having to guess. What remains is product and content work, not blocking questions.

1. **Pull the year list forward.** D20 leaves the year list carrying the seasonal story on its own (§5). `PKT-12`, `SAM-16` and `AUS-13` sit at P1 today; `PKT-12` is cheap and belongs in P0, and the other two should be early P1 rather than late.
2. **⚠️ One implementation trap in `PKT-20`, worth reading before the scoring engine is written.** The pause must not touch the **life list**. If a test-mode detection were recorded there, the first-find ×3 for that species would be silently burned — the child's real nuthatch, weeks later, would score 100 instead of 300, for a reason nothing in the app could explain. That is precisely the hidden punishment principle 1 forbids. Same for `DaySpecies` (the species must still be able to score later that day) and for `recomputeAllScores()`, which has to honour the flag or it will retroactively award every test recording ever made. Written up as `DAT-11`.
3. **Which of the 12 locales get child-register copy?** Keeping 12 locales (D4) is a UI-string decision. Rewriting species profiles in a child's register in 12 languages is a different order of magnitude — and under D5 the species pool includes amphibians, mammals and insects. Recommendation: German first, English second.
4. **Silhouette rendering** (`SAM-04b`, P1 — deferred out of the MVP) — one pass in the bundle pipeline, plus a decision on how attribution follows a derivative image.
5. **The species bundle has to be built on every dev machine.** `assets/species_images/` and `assets/species_data/` are gitignored outputs; without a `tools/build_species_bundle.py` run there are no photos and no profile texts anywhere. Worth a line in the README, because it presents as a bug rather than as missing setup.
6. **Windows build** — still exists, still costs CI time, not in the specification's target platforms. Decide explicitly: drop it, or keep it unmaintained behind a note.
7. **`SET-12` defaults need a real number.** The deletion rule (most-recorded species, lowest confidence first, 30 days, 100 clips per species) is sound, but nobody has measured what a child actually accumulates in a month. Set generous defaults, then check against the field test rather than guessing now.
8. **Do favourites survive the cap?** Proposed in D10 with a question mark. Recommendation: yes, and show the count — "12 of your 100 favourites" — so a child understands why the number stops growing. It is cheap and it prevents the one loss that would actually hurt.
9. **Documentation drift.** `AGENTS.md` refers to `dev/build_species_bundle.py`; the script actually lives in `tools/`.
10. **Chapter 9's open question 2** (how much the tiers swing over a year) — an afternoon's work, and under D3 it decides whether the seasonal narrative is worth building UI for.
