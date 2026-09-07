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

**2.1 · Wire the engine into Live.** Detection → `ScoreEvent`, using the shared scale from 1.2.

**2.2 · Live mode UI** (`LIVE-02`…`LIVE-08`), laid out **around** the full-size spectrogram (D7): star chip per card, "already collected today ✓" on repeats, multiplier chip, day total in the header. Then the celebration layer: confetti and the non-modal species card, with the queue from `LIVE-07` so a walk in the woods cannot stack five popups.

**2.3 · The scoring-paused surface** — `LIVE-18` in live mode and on the home star header, `SET-13` at both settings. Suppresses the first-find celebration while paused.

**2.4 · Home screen** (`HOME-01/02/03/08`): star header with total, last 30 days and today; one large Live tile; secondary tiles for Sammlung, Erkunden, Tagebuch, Punkte, Einstellungen.

**2.5 · The Journal** (`LOG-01/02/03/09/13/15`) — the largest single UI job. Day cards, day detail with per-species points and the applied multiplier, ✨ NEW markers, child-written place names, and out-of-scoring detections shown with their note.

**2.6 · The Collection** (`SAM-02`…`SAM-05`, `SAM-17`) as its own area: found species only, all taxon groups by default with a group filter, the placeholder for open ones, progress counter. **Per-species silhouettes are P1** (`SAM-04b`), so this step needs no pipeline work — but it does need the species bundle to have been built at least once, or every cell shows the placeholder and the Collection looks broken.

**2.7 · Points area and badges** (`STAT-01/02/05/06`, `AUS-01/02/03`): tabs, the 30-day bar chart with empty days shown as empty, key figures, and the three P0 badge groups.

**2.8 · Child-facing polish**: animation level (`SET-02`), the rules page (`SET-11`) including "why do the points change during the year?", clip retention (`SET-12`), onboarding with the home region on the permissions screen (`KID-01`, `SET-09`).

### Phase 3 — Version 1.0

The specification's P1, with one reordering: **pull the year list forward** (`PKT-12`, `SAM-16`, `AUS-13`). Since D20 removed the off-list case, the year list is the main way a child experiences the year changing (§5), and `PKT-12` is cheap enough to belong in P0 if there is room. Then `PKT-17` and `SAM-15` early, because until the app explains why points move, the movement reads as a bug.

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
