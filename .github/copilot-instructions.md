# Smartfinch — Copilot Instructions (Focused)

> Full guide: `AGENTS.md`. Product and rebuild are governed by `Smartfinch_App_Vision_and_Requirements Specification.md` and `BirdNET_Live_to_Smartfinch_Transition.md`. **Where code and specification disagree, the specification wins.**

## Response Style (Token Efficiency)

- Default to concise responses: short summary + only essential details.
- Avoid long restatements of context; reference files/functions directly.
- Use bullets over prose. Prefer <= 6 bullets unless user asks for depth.
- Ask at most one clarifying question only when blocked.
- Minimize tool usage and file reads: read only relevant ranges/files.
- For edits, make minimal diffs; do not reformat unrelated code.

## Project Snapshot

- **Smartfinch is a fork of BirdNET Live, being rebuilt into a collecting game for children aged 8–13.** The rebuild is in progress; much of the research app is still present and scheduled for deletion.
- Flutter app (Android/iOS; Windows unmaintained). **One mode: Live.**
- Fully offline for every core function. No account, ads, purchases or tracking.
- Stack: Flutter 3.27+, Dart ^3.7.0, Riverpod, ONNX Runtime, Drift/SQLite (planned), Geolocator, SharedPreferences.

## Where the code stands

- **Scheduled for deletion — do not extend:** `features/survey`, `features/aru`, `features/point_count`, `features/file_analysis`, voice memos, session map, expert inference controls.
- **Rescue before deleting:** the foreground service inside `features/survey` moves to `shared/services/background_recording/` first (D14/D19). It is the only working screen-off recording.
- **Keep unchanged (upstream merge surface):** `features/inference`, `features/audio`, `features/recording`, `features/spectrogram`, `core/services/asset_pack_service`. Additive changes only, no restructuring.
- **Reworked:** `features/live`, `features/home`, `features/settings`, `features/onboarding`, `features/history` (becomes the Journal).
- **New Smartfinch code goes in new directories:** `features/scoring`, `features/collection`, `features/journal`, `features/awards`, `features/avatar`.

## Rules that protect the game — break one and a collection corrupts silently

- **Two layers.** `Detection` is always written. The scoring layer (`ScoreEvent`, `DaySpecies`, `YearSpecies`, life list) is written **only while scoring is active** (`PKT-20`, `DAT-11`).
- **Never write the life list casually.** It burns the first-find ×3 forever (`PKT-04`). Test-mode detections, manually added species (`LIVE-16`) and imports must not touch it.
- **Frozen fields stay frozen.** `ScoreEvent` stores base value, level, `geoWeek`, grid cell and applied threshold (`PKT-15`). `recomputeAllScores()` re-derives multipliers and bonuses only.
- **Two calendars:** `geoWeek` (1–48, four per month) decides rarity; `isoWeek` (Mon–Sun) drives loyalty multipliers. Never one variable for both.
- **One shared rarity scale** keyed `(gridCell, geoWeek)` for Explore and Live (`DAT-10`). Grid cell is **0.1°** everywhere (D23).
- **Levels ratchet** — a recomputation may raise a level, never lower it.
- **Nothing is taken away; every number is explainable** (principles 1 and 6).

## Required Coding Rules

- American English in code, comments and ARB keys. **The app ships in German** — German is the reference for tone and register.
- Keep user-facing strings in all 12 locales: `en`, `de`, `cs`, `es`, `fr`, `it`, `pt`, `nl`, `nb`, `pl`, `ru`, `zh`.
- Use `l10n.keyName` in widgets; after ARB edits run `flutter gen-l10n` and ensure 0 untranslated messages.
- **Keep in English only genuine formats and proper nouns:** WAV, FLAC, CSV, JSON, BirdNET. Everything else gets a real German word — an eight-year-old does not know what a session is (`KID-03`).
- Add/modify settings via `PrefKeys` + settings providers/UI, and update `docs/user/settings.md`.
- Use `AppIcons` (`lib/shared/utils/app_icons.dart`) instead of raw `Symbols.*` or `Icons.*`.
- Keep Dart file header block comments (`// ===...`).
- No hardcoded thresholds or config values when constants/config exist. Scoring rules live in a versioned `ScoringRules` object (`DAT-04`).

## Writing for children

- Name the **effect**, not the cause: "no stars right now", not "species filter disabled".
- Short sentences, no jargon, 16 sp minimum. No countdowns, no time pressure (`KID-05`).
- No free text leaves the device; place names (`LOG-13`) never reach the shared day image (`KID-07`).

## UI/Theming Constraints

- Portrait + landscape; tablet layouts aligned with `ContentWidthConstraint` (600dp).
- **The spectrogram keeps its size** (D7). Scoring UI is laid out around it, never on top.
- Keep score ramps and spectrogram colormaps fixed (not dynamic-color remapped).
- Error palette for destructive actions — but **not** for the "not scoring" notice (`LIVE-18`), which is information.
- Prefer `surfaceContainer*` for elevated surfaces.

## Models, Inference, and Data

- ONNX assets in `assets/models` are Git LFS; on fresh clone run `git lfs install` and `git lfs pull`.
- **Do not widen the `flutter_onnxruntime` pin** without on-device retesting — see `docs/developer/onnxruntime-pin.md`.
- Keep model behavior JSON-driven via `assets/models/model_config.json`.
- ARM64 precision rule: weights stay FP16 on disk, sensitive compute casts to FP32.
- The geo model (`[lat, lon, week]`, 48 weeks, worldwide) is the source of every rarity level and therefore every star. Changes to it are scoring changes.
- Species images are used as the original app uses them (D6); silhouettes for `SAM-04` are derived from the same images in the same pipeline.

## Build, Test, and Release

- `flutter pub get` · `flutter analyze` · `flutter test` · `flutter run` · `flutter build apk --release` · `flutter build appbundle`
- **The scoring engine is pure Dart and must pass the chapter 2 rule table as tests** (`NFA-14`). Scoring is deterministic (`NFA-06`). Test `dayKey`/`isoWeek` timezone and DST edges (`DAT-05`). Schema changes need upgrade **and** downgrade paths (`NFA-12`).
- `pubspec.yaml` is version source of truth. Bump patch + build together, then `dart dev/sync_version.dart`.
- **Never bump the version** (version/build, badges, new CHANGELOG header) without explicit user consent in the current turn. Fold user-facing changes into the current unreleased section.
- Release notes per locale, <= 500 chars, user-facing, no implementation detail.
- Integration fixtures in `assets/test_fixtures` are not bundled; push to device when needed.

## Repo Workflow and Git Rules

- One-line conventional commits (`feat(scope): ...`). Reference the requirement ID for scoring changes: `feat(scoring): freeze applied threshold (PKT-15)`.
- Do not include internal tracker-like IDs (e.g. `F1`, `Q3`) in commit messages.
- Group related changes; avoid mixed-purpose commits.
- Never run `git push` unless the user explicitly asks in the current turn.

## Asset/Ignore Rules

- Keep `/dev/*` broadly ignored except tracked paths like `dev/sync_version.dart` and `dev/mockups/**`.
- `assets/species_images/` and `assets/species_data/` are generated bundle outputs and stay ignored. `dummy.webp` is hand-crafted and must never be deleted.
- Use `tools/download_taxonomy_json.py` + `tools/build_species_bundle.py` for bundle regeneration.

## Runtime Safety / Known Pitfalls

- Do not use `Picture.toImageSync()` for spectrogram rendering (GPU leak risk).
- **Never block listening** (principle 7). A rarity-scale rebuild during a live session runs in an isolate and keeps the current scale in use until the new one is ready.
- Position is requested at **coarse accuracy**, not `LocationAccuracy.high`. GPS stays as a source; a 0.1° cell needs nothing finer (`NFA-08`).
- For map tiles use the shared OSM tile layer; public tile usage stays interactive only (no offline/bulk downloads).

## Clear-Data Behavior

- "Clear All Data" wipes sessions, recordings, custom species lists, preferences, OSM tile cache and temp caches, then exits.
- Do not delete extracted ONNX model files (app assets, may be memory-mapped).
- Once the database exists, this must also clear the scoring layer — and the **life list** with it, or a wiped app still refuses first-find bonuses (`PKT-04`).
