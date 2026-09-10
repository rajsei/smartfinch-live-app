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
| `html_report.dart` | 1,803 | ~~Keep, re-point~~ → **deleted.** The day image shares its purpose and none of its content — this was a research artefact (detection tables, confidence columns, a session's coordinates), all three excluded by `LOG-11` by name |
| `session_export.dart` | 1,664 | ~~Keep, split in two~~ → **deleted.** `SET-07`'s backup writes the Drift tables directly and `LOG-11`'s day image renders the card widget, so neither ever used it; it went with the session review screen |
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
> **The editorial register is now the dominant non-code risk.** The bundled species descriptions are written for adults, in 11 locales. `SAM-11` asks for 2–3 child-friendly sentences plus a call mnemonic per species — and under D5 the species pool is no longer birds only. Under D4 the l10n discipline in `AGENTS.md` means every new Smartfinch UI string needs 12 translations. Recommendation unchanged: German first, English second, everything else keeps the adult text until someone funds the rewrite. **Status:** the mechanism shipped with `SAM-11` and 24 species are written in both languages; the remaining ~100 are writing, not engineering, and the risk is unchanged in kind — only smaller.

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

Mechanical but wide, and easy to half-finish. **Mostly done** — see the rebranding section in phase 3 for what the two names turned out to mean:

- ✅ `pubspec.yaml`: `name: smartfinch`, and every `package:smartfinch/...` import with it
- ✅ Android application ID `de.tu_chemnitz.mi.rajs.smartfinch` — a **new** ID, so this installs alongside BirdNET Live rather than replacing it on a researcher's phone
- ✅ App name in all 12 locales — and it is **two** names: Schlaumeise in German, Smartfinch elsewhere, with an artwork each
- ✅ `README.md`, and the citation block with it
- ✅ Launcher icons, both brands, generated from the PNG marks by `tools/build_launcher_icons.py`. Smartfinch is the one baked in; a German build swaps four lines
- ⬜ `mkdocs.yml` and the files under `docs/user/`
- ⬜ Store listings in `dev/store/` — there is no listing yet, and the README says so rather than linking one that does not exist
- **Attribution obligations stay**, and have. The BirdNET model licence (`MODEL_LICENSE`), the classifier and geo-model names, the funding and partner sections and the Cornell / TU Chemnitz credit are untouched and still visible in the About screen. A children's app does not get to drop them.

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

*Chapter LOG is complete.* `LOG-04`/`LOG-05` (day/week/month/year with a sticky month header), `LOG-07` (expandable individual detections) and `LOG-11` (share a day as one image) all went in during phase 3; none of them were load-bearing for the field test, which is why they waited.

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

**`AUS-02` is honoured literally:** unearned *loyalty* badges are not shown at all. `AUS-04`/`AUS-05` later brought the full day and week catalogue, which is shown open-and-all — the two rules coexist because an open daily badge is an invitation for this afternoon while a greyed "Regular · blackbird" would be a reproach about a bird. The Achievements tab does show one line for the next medal, which is a goal without being a row of eight faded ones.

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

*The UI for marking a favourite arrived with `LOG-07`* — the keep switch on the journal's clip player. `ScoringRepository.setClipFavourite` had existed since phase 2 with nothing calling it; the policy already honoured the flag, so closing the gap was one control and one write.

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

**`LOG-07` is done** ✅ — 22 tests. A species row in the day detail opens into the times it was heard: 07:12, 07:40, 09:03, each with how sure the app was and the recording where one was kept. This is the level the specification promised the old session concept would survive at, and it is the last of them.

**Only the first hearing is marked "counted".** `PKT-04` says the first detection of a species on a day scores and the rest do not, and a child who expands a blackbird heard five times learns that rule in one glance without anyone explaining it. That makes the sort order load-bearing rather than cosmetic — sorted the other way the badge lands on the wrong line and teaches the opposite. There is a test on the order for its own sake.

**The confidence shown is the peak, not the opening one.** A call that opened at 40 % and reached 88 % is an 88 % detection (D15). Showing what it opened at would make the app look wrong about a bird it got right, which is worse than showing nothing.

**A tap now expands, so "About this bird" moved inside the row.** The row's own contents are one level in and the species page is two; putting the link at the bottom of the expansion keeps one tap target per row instead of two competing ones. Tested, because `LOG-07` could otherwise have quietly removed `SAM-06`'s way in.

**The clip player is new rather than reused, and that was the point.** The session-review player exists and does all of this already — but it grew for adults doing fieldwork: it shares the audio, exports Raven selection tables, edits notes, records voice memos, confirms detections. Sharing audio is the one that mattered: `LOG-11` decided the rendered day image is the app's **only** sharing path, and it carries no audio. So the journal has its own sheet that draws the spectrogram, plays the clip, and stops. There is a test asserting the absence, because "just reuse the other sheet" is a plausible future edit that would put a share button in a child's hands without anyone noticing.

*It reuses the computation, not the screen* — `renderSpectrogram` was already a pure function, and this is the first caller to run it in an isolate rather than yielding on the UI thread every 200 columns.

**`SET-12`'s missing half went in with it.** `setClipFavourite` has existed since phase 2 with nothing to call it; the keep switch on the clip player is that caller, and it closes the open item. It belongs there rather than in a settings list because the moment a child knows a recording is worth keeping is the moment they are listening to it — and what it buys is concrete: retention deletes the oldest clips once a species is over its cap, and a kept clip is exempt.

*A hearing with no recording says so.* Retention having been through is ordinary, not an error, so the row renders a muted icon with an explanation rather than a gap the child has to interpret.

**`LOG-11` is done** ✅ — 10 tests, and the `LOG` block is complete. "Show grandma your bird day": one rendered card per day — date, stars, species, first finds — shared as a PNG. It is the app's only path out.

**Most of the tests are about absence, because that is the half nobody can see.** What is on the card can be checked by looking at it. What is missing cannot, and the specification's list of exclusions is the requirement: no audio, no coordinates, no free text.

**The place name is where two requirements meet in one widget.** `LOG-13` lets a child type "Oma" and shows it on the day card; `KID-07` says free text must never reach another person. So the name lives inside the app and stops at the picture's edge — and nothing on screen would look wrong if that were got wrong, which is exactly why there is a test naming "Oma" and asserting it does not render.

**The share is two steps on purpose.** The day screen's button opens a **preview**, not a share sheet. A one-tap share would mean a child hands a picture to a chat app without ever having seen what is on it, and this is the one action in Smartfinch that cannot be undone by the app. Under the preview, a line says plainly what stayed behind — place names, recordings, where you were — so a child who wonders does not have to squint at the card to find out.

**The picture is the widget, not a second drawing of it.** `RepaintBoundary.toImage` renders the subtree already on screen, so "what you see is what grandma gets" holds by construction. A `PictureRecorder` and a hand-written layout would have been a second implementation of the same card, and the two would have drifted the first time someone restyled a chip. The test proves the previewed subtree renders at 1080 px rather than merely that a boundary exists somewhere.

*Two small things.* The card is sized in logical pixels rather than to its parent, so a tablet does not produce a different picture from a phone. And `mimeTypeForSharedPath` had no `.png` case — without it chat apps offer the day as a file to download instead of showing the image, which defeats the point.

*What is deliberately not reused:* the existing HTML report, which the specification named as the basis. It is a research artefact — full detection tables, timestamps, confidence columns, and a session's coordinates — and every one of those is either gone with the research modes or excluded here by name. The day card shares its purpose and none of its content.

**`AUS-04` to `AUS-08` are done** ✅ — 45 tests. The badge catalogue, the rarity and persistence achievements, and the card that fires when one lands.

**`AUS-04`/`AUS-05` · the catalogue is shown in full, and that is a different rule from `AUS-02`.** Nine daily badges and three weekly ones, every one of them on screen with a tick or a quiet "still open" mark. The loyalty badges stay hidden until earned, exactly as before. The distinction is worth stating because it looks like an inconsistency and is not: an open **daily** badge is a suggestion for this afternoon — "Evening listener, not yet today" is an invitation — while a permanently greyed "Regular · blackbird" would be a reproach about a bird. An open badge is marked open, never failed; there is no cross anywhere on the tab.

*Each row says what earns it, earned or not.* Without the condition an open badge is a mystery rather than a suggestion, which would make the whole "show them all" decision pointless.

**Two badges needed something the database does not hold.**

🌱 **Herald of spring** is the same judgement `PKT-17` puts on screen as a sentence — a bird heard in the early shoulder of its own season — and that lives in the geo model's 48-week curve, not in any table. So `overview()` takes a `WeeklyScoresLookup`: the *rule* stays in the repository beside the other eleven, only the curve is injected. Without a lookup the badge is simply unearnable, which is honest — no curve, no season to be early for. The alternative, a second season rule computed in the widget layer, would have let the app award a badge for an arrival it simultaneously described as ordinary.

🗺️ **New ground** reads `Sessions.gridCell` rather than the place names of `LOG-13`: a badge that needed labelled walks would be a badge for bookkeeping. The first cell is never new ground — everywhere is, the first time the app is opened.

**A real bug fell out of writing the clock rules.** `ScoreEvents.awardedAt` was `DateTime.now()` at insert time rather than the moment of detection, so it could disagree with the `dayKey` sitting beside it — a bird heard at 23:59 and written a second later carried yesterday's day and today's time. Harmless while nothing read the hour off that row; not harmless now that six badges do. It is `context.now` now, like every other frozen field (`PKT-15`). `updatedAt` stays wall-clock, because that one really is about the row.

**`AUS-06` · rarity, counted at the level frozen at detection.** `levelAtDetection`, never today's tier. The scale is rebuilt per grid cell *and* per geo week, so re-deriving it would un-earn a redwing that was rare in November because the same bird is common in January — achievements that drifted with the seasons would be worse than none. The other trap is the direction of "the upper half of the rarity levels": the field runs 0 = rare … 5 = abundant, so the rarer half is 0–2, and reading it the other way round would hand out the rarity medals for blackbirds. Both have a test.

**`AUS-07` · persistence, and nothing here can be lost.** The streak rungs read the *longest* run there has ever been, so there is no number on the tab that falls on the day a child misses. That is `AUS-07` and principle 1 in the same sentence, and the cheapest way to keep the promise was to have nothing that can go down. There is a test that earns a week, breaks the streak, and asserts the badge is still there and the screen still says nothing about it.

**`AUS-08` · one queue, two kinds of celebration.** The specification says "same queuing rule as `LIVE-07`", so rather than write that rule twice `CelebrationQueue` became generic: first finds carry species names, unlocks carry badge definitions, and burst-collection and one-at-a-time are defined once. Two copies would have eventually disagreed about what "at most one" means, and the bug would have been a child watching four popups in a row.

*The card says what was earned and why* — "🌅 The early bird · Heard something before 9 in the morning" — because the moment the rule is satisfied is the one moment a child is guaranteed to be reading.

*The two restraints are what the tests are about.* `BadgeWatcher` returns nothing on its first look: the badge list is derived from all of history (`AUS-12`), so a first derivation reports everything ever earned, and celebrating that would mean opening the app after a month away and watching forty popups. And it throttles — the rules read the whole score journal, so running them after every bird would put a year of history through a query on the audio thread's heels. A badge landing twenty seconds late is still a surprise; a first find has to be immediate, which is why that one is pushed by the score board rather than polled.

*Not built:* 🌧️ **Bad weather hero**, the tenth row of 3.2's daily table. It is `AUS-11`'s, at a different priority, and it needs the weather consent gate — a child who declines weather simply never earns it. The catalogue is otherwise complete.

**`SAM-06` and `SAM-11` are done** ✅ — 22 tests, with one caveat on `SAM-11` that is stated below rather than buried.

**`SAM-06` · the personal half, and a stale tile that had to go first.** The species page already showed "you have detected this N times, last seen …" — reading `sessionListProvider`, the **old JSON session library**. On a Smartfinch install that panel could only ever say nothing, because detections live in Drift now. It is the same class of bug as the Explore ticks in phase 2, in the one place a child goes to look at *their own* history. Replaced by `CollectionRepository.personalStatsFor`, which reads the real tables.

**It reads across both layers on purpose.** The raw `Detections` answer "how often, when, where" — *including* the ones heard while scoring was paused, because a bird heard in test mode was still heard (`LOG-15`). The scoring layer answers "is it collected" and "what has it been worth". Reading only the second would tell a child they have never heard a robin on the evening they spent listening to one. There is a test with that exact shape.

⚠️ **"Where" is the name the child typed** (`LOG-13`), never a coordinate. The app coarsens location to a 0.1° cell before storing anything (`NFA-08`) and the shared day image carries no place at all (`LOG-11`, `KID-07`) — a species page that quietly reintroduced a location would undo all three, and nothing on screen would look wrong. Tested by asserting that no `"50.8,12.9"`-shaped string reaches the widget.

*A bird never heard gets no panel at all.* An empty box reading "0 times" would turn the album into a report card about everything the child has not managed.

**`SAM-11` · the mechanism is complete, the editorial work is not, and that distinction is the honest one.** The requirement is a **rewrite, not a translation** — 130 species × 3 sentences — and the specification says so twice. What shipped:

- `ChildProfileService` and `assets/species_profiles/child_profiles.json`, hand-written, keyed by scientific name → locale → `{ text, call }`. Its own directory, because `assets/species_data/` holds the *generated* bundle and is gitignored wholesale — an authored file put there would never have been committed, which is how it was first written and how it was caught.
- The species page renders the child text **instead of** the adult paragraph where one exists. Two descriptions of the same bird would be two things to read, and the second one is the one written for grown-ups.
- The call mnemonic gets its own block (`SAM-12`), because it is the one part used *outdoors* — everything above it is read on the sofa.
- **24 species written, German and English.** The commonest garden, park and woodland birds a child here actually hears. Every other species falls back to the bundled adult description, which is the ordinary case and is tested as such.

*Two deliberate omissions, both of which look like gaps.* A locale with no rewrite returns **null rather than English** — `SET-10`'s recommendation, and the right one: a Czech child reading an English paragraph is worse served than one reading the Czech adult description. And a species gets **no mnemonic** unless a real one exists; inventing one would teach a child something false about a bird, which is worse than saying nothing.

*Why a separate asset rather than a twelfth bundle locale:* different kind of text, different lifecycle. The adult descriptions are generated by `tools/build_species_bundle.py` from the taxonomy; these are written by a person, one species at a time. Merging them would let a bundle regeneration silently overwrite editorial work.

**What remains on `SAM-11` is writing, not engineering.** Roughly a hundred more species in two languages. The shape is fixed, there is a test that every shipped profile has both languages and is the right length, and adding one is a JSON entry.

**`SET-07` is done** ✅ — 20 tests. It was the last item on the phase-3 list this document has been working through; it is **not** the last P1 in the specification, and the gap is worth naming — see the audit below.

The app has no account and stores everything on the device, which is the right trade for `NFA-07` and the wrong one the day the phone goes in a river. `DAT-09`'s rolling local backups survive a crash; they do not survive a lost device. This does.

**Nothing is recomputed, and that is the whole design.** `LOG-12` was rewritten around exactly this: a backup carries the `ScoreEvent` journal, every event already holds its **frozen** base value, level, `geoWeek`, grid cell, threshold and rule version (`PKT-15`), and a restore writes them back unchanged. The alternative — re-deriving stars from today's rarity scale — would look harmless and silently rewrite a child's history, because the scale is rebuilt per grid cell *and* per geo week: a redwing worth 1,000 stars in November would come back worth 200 in January. There is no historical lookup that can go wrong here because there is no historical lookup, and there is a test asserting all seven frozen fields survive the round trip byte for byte.

**Restore replaces, it never merges.** Row ids are UUIDs, so nothing can tell a re-imported detection from a genuinely new one and a merge would double every star it touched. The case this exists for is a *new phone*, where there is nothing to merge with. Replace is also what makes the operation safe to repeat — there is a test that restores the same file twice and asserts the star total does not move.

⚠️ **Levels ratchet through a restore** (`AUS-12`). Restoring a backup taken at level 3 onto a phone that has since reached level 7 must not take a level, and with it an avatar stage, away from a child — principle 1 forbids it. So the highest level reached is read *before* the wipe and re-applied as a floor afterwards. This is exactly the sort of loss nobody would think to test for, so there is a test for it in both directions.

**One transaction.** A half-restored collection — detections without the events that scored them — would be worse than the empty database it replaced, because nothing would look broken. A refused file leaves the existing collection untouched, and that is asserted too.

**The recordings were deliberately not in the file** — since reversed, see the section below: they travel when the owner asks for them, and the default is still off because a year of clips is hundreds of megabytes and a backup too large to send protects nothing. The consequence is handled rather than ignored: **clip paths are cleared on the way in**, so the journal never offers a play button for a file that is on the old phone. `clipIsFavourite` survives, because it says something about what the child valued and costs nothing.

*A bug caught by writing that:* Drift's `toJson` keys by the **Dart field name**, not the column name — `audioClipPath`, not `audio_clip_path`. The first version of the clearing override used the column name, compiled, ran, and did nothing at all.

**The screen is the one place in Smartfinch not written for a child.** It sits on the plain Settings screen rather than behind Advanced — the thing standing between a broken phone and a lost collection should not be hidden from the parent who needs it — and next to the danger zone, because those are the two irreversible data actions and a parent should find both in one place.

*Saving is a share; restoring is a decision.* Save hands the file to the system share sheet, so it goes wherever the family already keeps things; the app manages no backup location, because it has no account and a file the parent put somewhere they chose is one they can find again. Restore **reads the file before asking**: "this backup holds 412 species and was saved on 4 May" — confirming a filename is not consent. Both consequences are stated before either button is pressed, including that recordings stay behind, which is otherwise the thing a parent discovers on the new phone.

*One implementation note worth keeping.* After a restore the read-side repository providers are invalidated rather than `appDatabaseProvider`. Invalidating the database would cascade further and be tidier, and it also closes the database — which a live session's coordinator would still be writing to.

### What is still open at P1 — an audit, after `SET-07`

The phase-3 list in this document was built from the requirements the transition *changed*. Re-reading the specification's P1 rows against the code afterwards turns up a set that was never on it, and most of them cluster:

**~~The avatar and the level are not built at all~~ — done, with the home-screen redesign; see the section below.** `AVA-01`, `AVA-02`, `AVA-05`, `STAT-07` and `HOME-07` went in as one cluster, because the level *is* the avatar's stage of life and building either alone would have meant building half the other. The paragraph below is left as written, because the reason it was one gap rather than five is the same reason it was one change. The *data* is there and always has been: `UserProfiles.highestLevelReached` is written, and `AUS-12`'s ratchet already protects it — including through a restore, as of `SET-07`. What is missing is every part a child would see. This is the largest single gap left, and it is a feature cluster rather than five separate jobs.

**Smaller, and each independent:**

| | |
|---|---|
| `HOME-05` | A 7-day sparkline in the star header |
| `HOME-06` | A "Still possible today" card naming 1–2 open daily badges — cheap now that `AUS-04` knows which are open |
| `STAT-03` | Tapping a bar in the 30-day chart jumps to that day in the journal |
| `STAT-04` | A 7 / 30 / 365 range switch on the chart (`PointsRepository.overview` already takes `chartDays`) |
| `SAM-04b` | Per-species silhouettes for undetected cells, replacing the shared placeholder |
| `SAM-08` | A sample call on the species page — blocked on licence-free recordings, not on code |
| `SET-04` | Sounds and haptics separately switchable |
| `SET-06` | Storage management: space used, delete audio |
| `DAT-09` | Automatic rolling local backup, 3 generations — related to `SET-07` but not the same thing: that one survives a lost phone, this one survives a crash |
| `AUS-11` | 🌧️ Bad weather hero, the tenth daily badge, behind the weather consent gate |
| `KID-04` | Everything operable without reading — an audit, not a feature |
| `KID-06` | No pressuring push notifications — currently true by absence, which is not the same as decided |
| `NFA-04` | Thermal behaviour under sustained inference |
| `LIVE-09` | Celebrating a variety threshold the moment it is crossed |

`SAM-11` also remains partly open, in the way described above: the mechanism ships, the register is written for 24 species out of roughly 130.

*None of this contradicts what phase 3 set out to do* — the list at the top of this section was the set of requirements the transition **changed**, and every one of those is now built. But "phase 3 is done" and "P1 is done" are different sentences, and only the first is true.

### The avatar block, and the home screen it lives on

**`AVA-01`, `AVA-02`, `AVA-05`, `STAT-07` and `HOME-07` are done** ✅ — 35 tests. This was the largest gap the P1 audit above turned up, and it was one cluster rather than five jobs: the level *is* the avatar's stage of life, so building either alone would have meant building half of the other.

**The ladder was already specified and already half-built.** §3.5's fifteen rungs go in as a const table — egg, chick, nestling, fledgling, young bird, scout, listener, singer, territory holder, far flier, migrant, returner, old bird, flock leader, legend — and `UserProfiles.highestLevelReached` has been in the schema since phase 1. What was missing was anything that *wrote* it: the column existed, `AUS-12`'s ratchet was described in three documents and defended through a restore in `SET-07`, and nothing had ever raised it. It is raised now in `ScoringRepository._addStars`, which is the one place the star total changes.

⚠️ **A ratchet that is only ever read is not a ratchet.** That is the failure this cluster is most likely to regress into, because everything looks correct until the first rebalancing — which is exactly when nobody is looking at it. There is a test that plays until a threshold is crossed and asserts the stored floor moved, and another that sets the floor above the total and asserts play cannot lower it.

**Four stages, not fifteen.** `AVA-02` words it as egg → chick → fledgling → adult, and that is what shipped. Fifteen pictures would be fifteen pieces of artwork nobody has drawn; the level number and its title carry the finer progression, the picture carries the shape of it. The stages are **emoji, deliberately** — a placeholder PNG looks like a decision, and this is explicitly not one. Real illustrations replace one getter and nothing else.

**`STAT-07`'s bar can never say a child has lost ground.** After a rebalancing the stored level sits above what today's stars would earn, so the progress fraction clamps at zero and the bar reads empty rather than negative. Nothing anywhere mentions it — the whole point of the ratchet is that the child never finds out the level was defended. `LevelProgress.isRatcheted` exists only so a test can assert that state is reachable and stable.

**`AVA-05` · a list, never a text field.** Twelve preset names, and the reason is in the requirement: free text is a moderation surface the app has decided not to acquire (`KID-07`). `LOG-13`'s place names are the one exception the specification made deliberately, and it made it because a place name is for the child's own memory of a walk; an avatar's name has no such argument. The names are **not localised** — translating "Pieps" into eleven languages would rename a child's bird when the family switches the app's language. The name lives in `UserProfiles.avatarState`, so it travels with a backup (`SET-07`) instead of being the one thing lost on a new phone.

### The home screen, redesigned

The direction sketched at the end of phase 3 is built, with one deliberate restraint: **theme roles, not chosen colours.** A block of `primaryContainer` at the top carrying the logo, the avatar and the star figures; a `surface`-coloured panel below carrying the tile navigation. Both come from `ColorScheme`, so the layout follows light/dark/dynamic-colour/high-contrast the way the rest of the app does and nothing commits to a palette the sketch explicitly left unsettled.

**The panel pulls down, and that is the load-bearing part.** It was the one piece the sketch marked as meant to survive: the lower area drops to a handle at the screen's edge and frees the space above it. Today that space is the header; later it is where a child arranges the birds their level has unlocked.

*It is arithmetic, not a `DraggableScrollableSheet`.* It was one, and it did not work: that widget sizes itself in **fractions of its parent**, which is right for a modal over a finished screen and wrong for a panel that has to leave a particular header visible. The fraction and the header's real height are unrelated numbers, and when they disagree the panel covers the header and clips its own contents — on a phone it opened over the star figures and cut the tiles off mid-row, which read as the app having stopped drawing. The split is computed now: the header gets the status-bar inset plus a fixed content height, the panel takes the rest, and the panel keeps its height while it slides so nothing reflows mid-animation.

**Where the slack goes is a decision.** The panel is taller than its contents on every screen worth shipping to, so the leftover height had to be put somewhere rather than left as a gap under the last row. On a **phone** it goes above the tiles, which puts them under the thumb; on a **tablet** it is split, because a tablet is not held by one thumb and the same alignment would read as half a blank screen rather than as room. `minHeight` plus a main-axis alignment is the pairing that does this and still scrolls when the content is genuinely taller than the box — which is what a 360 × 640 phone does.

*The buttons grew, and the tablet grew more.* The five destinations were the smallest thing on the screen: their padding, icons and labels all went up a step, and a tablet gets a second step on top of that. The Live tile grew most, because `HOME-08` says there is exactly one thing you are meant to do. The tablet's content cap went from 620 to 760 so the extra width lands in the tiles instead of in margin.

*And the header grew with them.* A phone-sized header on a 1,280-pixel tablet is a small block floating in a band of colour, so on a tablet the bird is 96 rather than 64, the star total is a size larger, and the header's share of the screen goes from 200 to 300 — which is also what stops the panel from being so tall that centring its contents looks like a mistake.

*It is not a hidden gesture.* The handle is visible, it answers to a **tap as well as a drag** — a child who never discovers the drag can still press it — there are two positions rather than a free float, and every destination is still one tap away in the default position (`KID-04`). Tested at 360 × 640, by measuring that each tile's label ends above the bottom of the screen: "one tap away" is not one tap away if the last row is below the fold.

**Landscape is the same two blocks turned ninety degrees.** Portrait splits top and bottom because that is where the room is; held sideways a phone has the opposite problem — plenty of width, barely any height — so the blocks stand side by side: the coloured one on the left with the bird and the figures, the surface one on the right with the tiles, its rounded edge facing the header exactly as the top edge does in portrait.

*It is the same `HomeHeader`*, not a landscape arrangement of the same numbers. The star display with its rules is the one a child already knows, and the two orientations cannot drift into showing different things.

*Two parts to three.* The header's width need is close to fixed — a bird, a gap, a six-figure number beside it. The tiles are the half that *uses* extra width, so they get the larger share.

*No handle there.* In portrait, pulling the panel down frees the screen for something — today the header, later the diorama. Sideways there is nothing to free: the header is already beside the panel, not behind it. A gesture that only half-matched the other orientation would be worse than none.

**The logo and the app title are gone from both orientations**, and the warm-up's logo precache went with them — it existed to have the image decoded before the header painted it, and no header paints it now. That also removed a two-second timer that every home-screen test had to pump past.

**The header was laid out twice.** The first pass reused the existing pieces — logo block, then an `AvatarCard`, then the star header — and it was wrong on a phone: three stacked cards inside 40 % of the screen, nothing like the sketch. The second pass is `HomeHeader`, built to the agreed arrangement:

- the bird in a circle on the left, its level on a chip
- ⭐ the total, large, with its label beside it
- a rule, then the two smaller figures side by side — 30 days, and today
- the level line and its bar across the full width

*The logo and the app title are gone from it.* They were the first thing on the old home screen and they cost the block a third of its height to tell a child the name of the app they had just opened. The header's job is to say what *they* have; the app's own name is on the icon they tapped.

*The secondary tiles are two then three*, as the sketch has them. Five across a phone leaves each tile narrower than its own label, and "Einstellungen" wrapping onto three lines is how a grid stops reading as one. Landscape keeps the single row, where there is width for it.

**`LIVE-18` survives the restyle**, which is the part of this worth a note: while scoring is off the figures are still replaced by the same notice live mode shows, in the same words. A header that kept displaying stale totals during a paused session would be the app quietly lying about a number a child is watching.

*And a test that would have caught the first pass.* The existing home tests pump at 1,000 logical pixels, which the layout treats as a tablet — the size that actually squeezes this header is a short phone. There is now one at 360 × 640 with a six-figure star total, and it found a real overflow on the level line the moment it was written: at level 13 the right-hand text reads "14,343 to level 14", which is wider than what is left beside "Level 13". It gives way now instead of overflowing.

**What this does not include:** `HOME-05` (the 7-day sparkline) and `HOME-06` ("Still possible today"). Both belong in the new header and both are now cheap — `AUS-04` already knows which daily badges are open — but neither is part of the avatar, and bundling them would have made one reviewable change into three.

### The session-review branch is gone

`LOG-01` retired the session as a level of navigation in phase 2.5, and the journal replaced the library. One route never got the message: **the end of a live session still pushed the session review screen**. A child who stopped recording landed in a research view of one recording — spectrogram strip, per-detection confirm and share menu, export options — instead of in the day they had just spent listening to.

That single push was what kept an entire branch alive. A finished session now lands in **`JournalDayScreen`** for the day it started (`LOG-03`), with the journal underneath so closing the day goes there rather than to the home screen. With it removed, the following had no reachable caller and went:

`session_review_screen.dart` · `session_library_screen.dart` · `session_map_screen.dart` · `session_export.dart` · `html_report.dart` · `export_metadata_helper.dart` · `clip_player_sheet.dart` · `session_review_widgets.dart` · `voice_memo_overlay.dart` · `detection_actions.dart` · `detection_sharing_service.dart` · `audio_export_normalizer.dart` · `audio_share_extension.dart` · `session_audio_trim.dart` · `detection_audio_window.dart` — and their nine test files.

*Two of these were already flagged in §3 as "decide separately whether it survives at all".* This is that decision.

**The live detection tile lost its action menu**, which turned out to be dead in a second way: `DetectionTile` accepted a `DetectionActions` contract, but nothing in Live ever passed one — only the review screen did. The chevron that says "tap for the bird" is now the only trailing chrome. `KID-07` had already ruled out the share half of that menu.

**Settings shrank accordingly.** The **Playback** section (voice memos, ducking, playback overlay) configured only the review screen and is gone. **Export** kept exactly one switch — "include audio files" — and lost the Raven/CSV/JSON/GPX picker, "share as WAV", the app-metadata block and the HTML report: what those exported was a *session*, in formats meant for people who open selection tables. Seven providers and five preference keys went with them.

*`features/history` no longer exists.* Five files survived it, and each moved to where its one consumer lives: `global_species_history.dart` → Explore, `session_repository.dart` and `session_path_codec.dart` → Live, `share_file_params.dart` → `shared/utils`, `spectrogram_renderer.dart` → the spectrogram feature. A directory named for a feature that is gone is a map that lies.

*Still open, and bigger than it looks:* **648 of 1,366 l10n keys now have no reference in `lib/`.** Most predate this — the survey, point-count and file-analysis modes went in phase 0 and took their vocabulary with them. Removing them is a sweep across twelve files and worth doing on its own, not as a rider.

### The audio can leave the device — a decision reversed

`LOG-11` was being read as "the rendered day image is the app's **only** way out", and two things had been built on that reading: the backup deliberately left the recordings behind, and the journal's clip player deliberately had no share button.

**That reading was too broad, and it has been corrected.** `LOG-11` decided what a *shared day* contains — no audio, no coordinates, no free text — and that is still exactly true and still tested: the day image carries none of them. It did not decide that a child may never hand anybody a bird they recorded. `KID-07` is untouched either way: it bans free text reaching another person, and a five-second clip of a blackbird is not text.

The principle behind the correction is the one that should have been applied first: **the recordings are theirs, on their device.** An app that will not give them back is not protecting a child, it is keeping somebody else's data.

**`SET-07` can now carry the recordings.** "Include the recordings" sits on the backup screen, off by default — a year of clips is hundreds of megabytes and a file too large to send protects nothing — but off by default is a different thing from not offered. When it is on, each clip goes into the archive under `clips/<detection id>`, and a restore writes them back and repoints the rows at their new location.

*Named by the detection id, not by the original filename*, because the id is what the row carries and the filenames were only ever unique inside one session's directory. *Restored into one directory* rather than the `recordings/<sessionId>/` tree they came from: those belong to the JSON session store, which a restore does not repopulate, and a clip's home is its `Detection` row.

*Two ordering decisions worth keeping.* The files are written **before** the transaction, because a file write is not part of the database's all-or-nothing and a restore that rolled back after spilling a hundred megabytes would leave them behind with nothing pointing at them; the worst case now is orphans the next restore overwrites by name. And a clip retention has already deleted is **skipped in silence** — the row keeps its path, the restore finds no file, the path is cleared, and nothing reports a failure for a recording that was always allowed to go.

**One recording can be shared on its own**, from the clip player in the journal. The file itself, not a copy in an export format. That is the whole feature; none of the research chrome came back with it, and there is a test that says so.

*What this leaves unchanged:* the day image (`LOG-11`) still renders date, stars and species and nothing else, and the place names of `LOG-13` still stop at its edge.

### Rebranding — and the app turning out to have two names

**In German the app is Schlaumeise; everywhere else it is Smartfinch.** They are not translations of one another: *Schlaumeise* is a tit and a pun on *Schlaumeier* that exists only in German, and a finch is not a tit. So this is not one wordmark with a swapped string — it is two brands with two pieces of artwork, and the app picks between them the way it picks every other string, by locale.

*The failure that would be invisible:* the picture and the caption drifting apart, so a German child reads "Schlaumeise" under a finch. `AppLogo.assetFor` and `l10n.appTitle` are both driven by the locale, and there is a test that walks all twelve and asserts they agree.

**SVG, not PNG.** The mark is drawn at 40 logical pixels in a settings row and 220 on the onboarding card; a raster asset would have to ship at the larger size to survive the larger use. `flutter_svg` is a new dependency and the first one added since the transition began — worth naming, because the alternative was six PNGs in three sizes each.

**Where the name comes from now:**

| | |
|---|---|
| Interface | `l10n.appTitle` — Schlaumeise in `app_de.arb`, Smartfinch in the other eleven |
| Android launcher | `@string/app_name`, with `values-de/strings.xml` carrying the German one |
| iOS launcher | `CFBundleDisplayName`, with `de.lproj/InfoPlist.strings` overriding it |
| Logs, filenames | `AppConstants.appName` — a stable ASCII token, marked ⚠️ *not for the interface* |

*Eleven strings still said "BirdNET Live"* — the onboarding welcome, the privacy description, the help intro, the data-clear failure and others. All twelve locales are rebranded. What deliberately stays is every mention of **BirdNET the model and the organisation**: the classifier's name, the geo-model, the taxonomy version, the funding and partners sections, the acceptable-use policy. Those are attribution and licensing, not branding.

**The README was still BirdNET Live's** — "Professional bioacoustics in your pocket", a feature list headed by Point Count and ARU modes, store links to an app this is no longer, and a documentation site belonging to the upstream project. It now describes what this app is, says plainly that there is no store listing yet rather than linking one that does not exist, and points at the `docs/` directory rather than at the upstream site.

**The launcher icon is the new bird**, once the PNG marks arrived. `tools/build_launcher_icons.py` turns each 2000² brand mark into the two things the platforms actually want, for **both** brands:

- an **opaque** 1024² square for iOS and the legacy Android icon, composited onto the mark's own outer-rim colour rather than onto whatever the toolchain would have filled the transparency with;
- a **transparent** adaptive foreground with the mark scaled into Android's safe zone, because a launcher crops roughly a quarter of that layer to whatever shape it prefers.

The rim colour is **sampled from the artwork** rather than written down — `#262626` for Smartfinch, `#12253F` for Schlaumeise — which keeps the adaptive background matching the mark's edge when the artwork is redrawn. A mask that cuts into the badge then cuts into more of the same colour, so the crop is invisible whichever shape a launcher uses.

⚠️ **This is the one place the two brands cannot both win.** A launcher icon is baked at build time and cannot follow the device language the way `AppLogo` does. Smartfinch is the default — it matches the package name, the application ID and eleven of the twelve locales — and a German-market build swaps four lines in `pubspec.yaml` for the `schlaumeise-` files and `#12253F`. Both sets are generated and committed, so that swap is a config change and not a redraw. A real answer for a German store release is a build flavour.

*The old artwork went with it:* `app-icon.png`, its adaptive foreground and background, and `logo-birdnet-circle.png` had no reference left in `lib/` once the header stopped drawing a logo.

*One asset is missing and the app works around it.* `smartfinch_logo_full.svg` — the bird-plus-wordmark lock-up — is in the tree; its Schlaumeise counterpart is not. `AppLogoStyle` therefore offers only the variants **both** brands have, because a style one of them is missing would render for a Czech child and throw for a German one, and nothing would reveal it until somebody set their phone to German. The onboarding hero uses the round mark, with the app's name already in text beneath it.

### The season hint stopped naming the bird — a grammar bug in seven languages

`PKT-17`'s sentence read "**Die** {species} ist normalerweise erst ab April hier." The article is the problem, and it is not a German problem: **`El`, `Le`, `Il`, `De`, `O`, `Die`** were all written into the sentence, and each of them is a guess about a noun that arrives at runtime from a taxonomy of thousands.

German bird names take all three genders — *der* Zilpzalp, *die* Amsel, *das* Sumpfhuhn — so any article in the sentence is wrong for roughly two thirds of them. "Die Sumpfhuhn" is what that looks like on screen.

**It is not fixable by choosing a better article, because no article is right for every noun.** It is fixable by not needing one — and the name was redundant anyway: the banner only ever renders directly *under* the species' own name, on the live detection card and on the species page. So the sentence lost the name and, with it, the article:

> 🌱 **Früh dran!** Normalerweise erst ab April hier.

*Article-free, pronoun-free, and shorter* — which for an eight-year-old is a gain, not a loss. All twelve locales were rewritten; Norwegian was already the only one that had dropped the article.

**A test now holds the line.** It renders the banner in all twelve locales and asserts that none of the thirteen definite articles those languages reach for appears anywhere in the text. A future string that puts a species into a sentence has this problem waiting for it, and the guard is what makes that visible rather than shipped.

⚠️ **The same sentence has a second grammar bug, which is not fixed.** `{month}` is rendered with `DateFormat.MMMM`, which yields the **nominative**: `апрель`, `kwiecień`, `duben`. Russian, Polish and Czech all need a case after the preposition — *с апреля*, *od kwietnia*, *od dubna* — so those three read as broken to a native speaker. This one cannot be dodged by rephrasing the way the article could, and hand-inflecting twelve month names in three languages I cannot check with a speaker is the same bet `SAM-11` declined to make. **It needs 36 short strings from someone who speaks them.**

**~~A second home-screen redesign direction is being explored, not yet built.~~ Built — see the section above.** The sketch as it stood: Phase 2's `HOME-01/02/03/08` header and tile grid shipped and works; a two-tone layout is under discussion as its successor — a colour block at the top carrying the avatar and the star figures, and a lower, surface-coloured area carrying the tile navigation, both still adapting to light/dark/dynamic-colour/high-contrast the way `AppTheme` already does today. **Neither the colours nor the tile split are settled** — mockups exist in four theme variants purely to show that the header can carry any accent, not to pick one, and the sketched 1-large-Live + 2 + 3 tile arrangement is a rough placement, not a layout requirement. The one piece meant to survive into the real design: the lower area should be built so it can later be **dragged further down** — collapsing to a small handle at the screen's bottom edge and freeing the screen above it. That is the surface a future per-level bird unlock would use, letting a child arrange their unlocked birds on screen like a small diorama before pulling the handle back up to restore the tile navigation. No requirement ID exists for this yet — it is a UI direction, not a scored feature.

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
