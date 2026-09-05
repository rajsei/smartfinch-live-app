# Smartfinch Agent Guide

This file is for coding agents working in this repository.

## What this repository is

**Smartfinch is a fork of BirdNET Live**, being rebuilt from a professional bioacoustics tool into a **collecting game for children aged 8–13**. The rebuild is in progress: most of the research app is still here, and a large part of it is scheduled for deletion.

Two documents govern the work and outrank anything you infer from the code:

| Document | What it settles |
|---|---|
| `Smartfinch_App_Vision_and_Requirements Specification.md` | The product: vision, scoring rules, requirement catalogue with IDs (`PKT-`, `LIVE-`, `SAM-`, `LOG-`, `DAT-`, …) |
| `BirdNET_Live_to_Smartfinch_Transition.md` | The rebuild: what is kept, changed or deleted, decisions D1–D23, and the upstream merge strategy |

**When code and specification disagree, the specification wins** — the code is the app being left behind. When you touch anything scoring-related, cite the requirement ID in the commit message.

## Product Snapshot

- Flutter app, **Android and iOS** (Windows still builds; unmaintained, decision pending).
- **One mode: Live.** A child listens, species are detected on-device, stars are awarded, the collection fills up.
- Audience: children 8–13. Fully offline for every core function; no account, no ads, no purchases, no tracking.
- Stack: Flutter 3.27+, Dart ^3.7.0, Riverpod, ONNX Runtime, Drift/SQLite (planned), Geolocator, SharedPreferences.

## Where the project stands

The tree does not yet match the target. Know which side of the line you are on before you write anything.

| Area | State | What to do |
|---|---|---|
| `features/survey`, `features/aru`, `features/point_count`, `features/file_analysis` | **Scheduled for deletion** | Do not extend, do not refactor, do not add tests. Bug-fix only if it blocks something else |
| Foreground service inside `features/survey` | **Rescue first, then delete** | Must be lifted into `shared/services/background_recording/` *before* Survey is removed (D14/D19). It is the only working screen-off recording implementation |
| `features/history` | **Becomes the Journal** | Roughly 12,000 lines are built around a single recording and are not salvageable. Export writers, clip playback and the life list are kept — see the transition document §3.4 |
| `features/explore` | **Stays Explore** | The list of all species. Changes least of everything |
| `features/live`, `features/home`, `features/settings`, `features/onboarding` | **Reworked** | Additive where possible; the detection pipeline underneath is not touched |
| `features/inference`, `features/audio`, `features/recording`, `features/spectrogram` | **Keep as-is** | See "Upstream merge discipline" below |
| `features/collection`, `features/scoring`, `features/journal`, `features/awards`, `features/avatar` | **Do not exist yet** | All new Smartfinch code goes in new directories like these |

## The rules that protect the game

These are Smartfinch-specific and have no equivalent in BirdNET Live. Breaking one of them corrupts a child's collection in ways that are invisible until much later.

**1. Two layers, and only one of them is authoritative.**
`Detection` is raw data and is always written. The scoring layer — `ScoreEvent`, `DaySpecies`, `YearSpecies`, the life list — is derived and is written **only when scoring is active** (`PKT-20`). When scoring is paused, write the detection, flag it, and write nothing else (`DAT-11`).

**2. Never write the life list casually.**
Adding a species to the life list burns its first-find ×3 multiplier forever (`PKT-04`). A test-mode detection, a manually added species (`LIVE-16`), an import — none of them may touch it. The child's real first find, weeks later, must still count. This is the single easiest way to break the game silently.

**3. Frozen fields are frozen.**
Every `ScoreEvent` stores its base value, rarity level, `geoWeek`, grid cell and the confidence threshold that applied (`PKT-15`). `recomputeAllScores()` re-derives multipliers and bonuses and **never** touches those. A recomputation that rewrites base values rewrites a child's history.

**4. Two calendars, two names.**
`geoWeek` is the geo model's 1–48 (four weeks per month, the fourth runs 9–10 days) and decides rarity. `isoWeek` is Monday–Sunday and drives the loyalty multipliers. They are different calendars. Never let one variable mean both.

**5. One rarity scale, shared.**
Explore and Live must read the same `(gridCell, geoWeek)` scale (`DAT-10`), or the app contradicts itself about what a bird is worth. Grid cell is **0.1°** everywhere — rarity scale, place bonus, weather cache (D23).

**6. Levels ratchet.**
Store the highest level ever reached; a recomputation may raise it, never lower it. Otherwise the first rebalancing takes a level away from a child who did nothing.

**7. Nothing is ever taken away, and every number can be explained.**
Principles 1 and 6 of the specification. No punishment, no deducted points, no commentary on a broken streak. If a value changed, the app must be able to say why — which is why frozen fields and one shared scale are not optional.

## Upstream merge discipline

Smartfinch keeps merging from `birdnet-team/birdnet-live-app` (D2). That only stays possible if the boundary is respected:

- **Do not restructure** `features/inference`, `features/audio`, `features/recording`, `features/spectrogram`, `core/services/asset_pack_service`. Additive changes only — these are where upstream fixes land.
- **All new Smartfinch code goes in new directories.** New files never conflict.
- `lib/app.dart`, `lib/main.dart`, `home_screen.dart` and `settings_screen.dart` are permanent conflict zones. Keep the Smartfinch versions small so merges stay readable.
- Record deletions once; do not resurrect a deleted tree while resolving a merge.

## Project Structure

- `lib/core`: app-wide constants, services, theme, infrastructure.
- `lib/shared`: shared models, providers, utilities, widgets.
- `lib/features`: feature modules — see the table above for which are staying.
- `lib/l10n`: ARB localization sources and generated output.
- `docs`: user and developer documentation.
- `dev` and `tools`: maintenance scripts, model pipelines, release helpers.

## Language and Localization

**The app ships in German.** English remains the source language for code, comments, ARB keys and `app_en.arb` — but German is the reference for tone and register, and it is what a child actually reads. When a German string reads badly, that is a bug even if the English is fine.

- Keep user-facing strings translated in all 12 locales: en, de, cs, es, fr, it, pt, nl, nb, pl, ru, zh.
- After ARB edits run `flutter gen-l10n` and verify no missing keys.
- Use `l10n` keys in UI; never hardcode user-facing text.
- **Keep in English across locales only what is genuinely a format or a proper noun:** WAV, FLAC, CSV, JSON, BirdNET. Everything else gets a real German word — the old rule that kept *Point Count*, *Survey*, *Session* and *Live Mode* in English belonged to a research tool. An eight-year-old does not know what a session is (`KID-03`).
- A locale is not "added" until every surface carries it:
  - `lib/l10n/app_<loc>.arb` (UI strings)
  - `assets/announcements/templates_<loc>.json` (spoken announcements; a missing file falls back to English silently)
  - `assets/species_data/descriptions_<loc>.json.gz` + `SpeciesDescriptionService.availableLocales` + `DESCRIPTION_LOCALES` in the species bundle script. Re-run the whole script — it also writes the `wikipedia_url_<loc>` column into `assets/models/taxonomy.csv`, and a partial run leaves that column absent.
  - the app-language dropdown in `lib/features/settings/settings_screen.dart`
  - `AppConstants.policyDocsLocales` + `docs/privacy.<loc>.md` + `docs/acceptable-use.<loc>.md` + the `mkdocs.yml` locale block
  - `docs/index.<loc>.md` + `docs/user/*.<loc>.md` + the locale's `nav_translations` block in `mkdocs.yml`. Developer Guide and API Reference stay English.
  - `dev/store/store-desc.md` (all five sections)
  - `dev/mockups/`: slide copy belongs in `mockups.copy.md` (then run `node sync-copy.js`), not inline in `mockups.config.js`
  - the locale list in `dev/build_release.dart`
  - the locale lists in `test/features/announcements/templates_*_test.dart`

> **Note on species profiles:** UI strings stay at 12 locales. The child-register species texts (`SAM-11`) ship German first, English second; the other ten keep the adult descriptions until someone funds the rewrite. Do not treat a missing child-register text as a translation bug.

## Writing for children

- Short sentences, no unexplained jargon, minimum 16 sp base size (`KID-03`).
- Name the **effect**, not the cause: "no stars right now", not "species filter disabled".
- No time pressure, no countdowns, no red warnings for things the child did not do wrong (`KID-05`, principle 1).
- Core functions must be operable without reading — icon plus colour (`KID-04`).
- No free text may leave the device. Place names (`LOG-13`) are local and are never rendered into the shared day image (`KID-07`).

## UI and Theme Constraints

- Support portrait and landscape; keep tablet layouts aligned with `ContentWidthConstraint` (600 dp intent).
- **The spectrogram keeps its size** (D7). It shows how sound becomes a picture and makes interference visible; the scoring UI is laid out *around* it, never on top of it.
- Keep score ramps and spectrogram colormaps fixed; do not remap them to dynamic color.
- Use `AppIcons` from `lib/shared/utils/app_icons.dart`, not raw `Icons.*` or `Symbols.*`.
- Use the error palette for destructive actions — but **not** for the "not scoring" notice (`LIVE-18`), which is information, not an error.
- Dynamic color: with one mode left, the live=`error` mapping is the only one still in use.

## Settings and Docs Discipline

- Settings are **reorganised, not deleted** (D13): a plain first screen for what a child or parent touches, everything else behind **Advanced settings**. The exception is the expert inference block (pooling, sensitivity, custom species lists), which is removed outright.
- Two settings pause scoring when moved out of range — the species filter and the confidence threshold (`PKT-20`). Both need the warning from `SET-13`, and the live notice from `LIVE-18` must appear while they are out of range. The scoring floor is **35**, a constant, not a setting.
- For new or changed settings: update `PrefKeys` and the providers/UI, document the rationale in `docs/user/settings.md`, and record user-visible behaviour changes in `CHANGELOG.md`.

## Species Bundle and Assets

- `assets/species_images/dummy.webp` is the hand-crafted fallback shown for species with no image. It is **not** generated by the pipeline and must never be deleted.
- Species images are used exactly as the original app uses them (D6). The **silhouettes** for undetected species (`SAM-04`) should be derived from the same images in the same pipeline, not drawn by hand — attribution follows the image into the derivative.
- The bundle script clears `assets/species_images/`; `dummy.webp` is preserved explicitly. Add any other hand-crafted file to `PRESERVED_OUTPUT_FILES`.
- To refresh with a new taxonomy version: download the taxonomy JSON, point `DEFAULT_TAXONOMY_JSON` at it, run the bundle script from the repo root with the venv active.
- `assets/species_images/` and `assets/species_data/` are generated and gitignored.

## Data and Models

- ONNX assets are managed with Git LFS. On a fresh clone: `git lfs install` then `git lfs pull`.
- Keep model behavior JSON-driven via `assets/models/model_config.json`.
- **Do not widen the `flutter_onnxruntime` pin** without re-testing on-device — see `docs/developer/onnxruntime-pin.md`.
- ARM64 rule: sensitive compute may require FP32 casting for stable output.
- The geo model answers `[latitude, longitude, week]` for 48 weeks worldwide. It is the source of every rarity level and therefore of every star. Treat changes to it as scoring changes.
- Do not hardcode thresholds or model config values when constants/config already exist. Scoring rules belong in a versioned `ScoringRules` object (`DAT-04`), never scattered as constants.

## Audio, Maps, and Runtime Safety

- Do not use `Picture.toImageSync()` for spectrogram rendering.
- Inference runs in an isolate and the UI holds 60 fps (`NFA-13`). A rarity-scale rebuild during a live session must also run in an isolate — the Explore screen's version deliberately does not, because there it happens once on a loading screen.
- Never block listening. Nothing — animation, popup, scale rebuild, level-up — may interrupt live detection (principle 7).
- Position is requested at **coarse accuracy**, not `LocationAccuracy.high`. GPS stays as a source; a 0.1° cell needs nothing finer.
- Use the shared OSM tile layer. OSM public tile policy: interactive use only, no offline or bulk downloads.

## Build and Release

- `flutter pub get` · `flutter gen-l10n` · `flutter analyze` · `flutter test`
- `pubspec.yaml` is the version source of truth.
- **Never bump the version without explicit user consent in the current turn.** Do not change version/build, version badges, or add a CHANGELOG version header unless asked. Fold user-facing changes into the current unreleased section.
- For release bumps: increment patch and build together, then run `dart dev/sync_version.dart`.
- Release notes for all 12 locales, UTF-8, `<xx-XX>` tags; write zh-CN in Simplified Chinese, never pinyin.

## Testing

- The scoring engine is pure Dart with no UI and **must** be covered by the rule table from chapter 2 of the specification (`NFA-14`). It is finished when those tests pass, not when it looks right on screen.
- Every scoring rule change needs a test. Scoring must be deterministic and reproducible (`NFA-06`): the same detection history always yields the same total.
- Test the timezone and daylight-saving edges of `dayKey` and `isoWeek` explicitly (`DAT-05`).
- Schema changes need tested upgrade **and** downgrade paths (`NFA-12`).

## Dev Folder Sync Rule

- Do not sync or copy broad content from `dev` by default. Only when the user explicitly names the files or folders. Treat `dev` as a tooling area.

## Search for All Affected Call Sites Before Implementing

When a feature touches a shared function, setting, or data path, grep the full codebase for every place it is used — not just the location in the request. Implement the change at **all** affected locations in the same pass.

- Before writing code, grep for the function name, setting key, and provider name across `lib/`.
- If multiple screens or services do "the same thing" independently, update all of them.

## Git Workflow

- Conventional one-line commit messages: `feat(scope): ...`, `fix(scope): ...`, `docs(scope): ...`
- Reference the requirement ID for scoring-related changes: `feat(scoring): freeze applied threshold in ScoreEvent (PKT-15)`.
- Group related changes; avoid mixed-purpose commits.
- Never run `git push` without explicit user consent in the current conversation.
