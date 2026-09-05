# Contributing to Smartfinch

Thank you for your interest in contributing to Smartfinch! This guide will help you get started.

> **Smartfinch is a fork of BirdNET Live**, being rebuilt from a professional bioacoustics tool into a collecting game for children aged 8–13. The rebuild is in progress. Before investing work in anything, read:
>
> - `Smartfinch_App_Vision_and_Requirements Specification.md` — the product, and the requirement IDs (`PKT-`, `LIVE-`, `SAM-`, …) to reference in commits
> - `BirdNET_Live_to_Smartfinch_Transition.md` — what is kept, changed or deleted
> - `AGENTS.md` — the working rules, including the ones that protect a child's collection
>
> **Where the code and the specification disagree, the specification wins.** Several feature modules are scheduled for deletion — check the table in `AGENTS.md` before extending one.

## Development Setup

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.27+ with Dart 3.7+)
- [Git LFS](https://git-lfs.com/) for the large ONNX model files
- [Android Studio](https://developer.android.com/studio) (for Android SDK & emulator)
- [Xcode](https://developer.apple.com/xcode/) (macOS only, for iOS development)

### Getting Started

```bash
# Clone the repository
git clone https://github.com/rajsei/smartfinch-live-app.git
cd smartfinch-live-app

# Fetch the ONNX model files (do not skip on a fresh clone)
git lfs install
git lfs pull

# Install dependencies
flutter pub get

# Generate localization files
flutter gen-l10n

# Run the app
flutter run
```

### Running Tests

```bash
# All tests
flutter test

# Specific feature
flutter test test/features/audio/

# With coverage
flutter test --coverage
```

## Code Style

- Follow [Effective Dart](https://dart.dev/effective-dart) guidelines
- Use `flutter analyze` to check for lint issues
- Format code with `dart format .`
- Use dartdoc comments for public APIs
- Use `AppIcons` (`lib/shared/utils/app_icons.dart`) instead of direct `Symbols.*` or `Icons.*` in feature code
- Prefer neutral icon names; keep `...Outlined`/`...Rounded` names only when the style distinction is intentional and both variants are used

### File Structure

Each feature follows this pattern:

```
lib/features/{name}/
  {name}_screen.dart         # UI
  {name}_controller.dart     # Logic (if needed)
  {name}_provider.dart       # State
  widgets/                   # Feature-specific widgets
```

## Translation Contributions

**The app ships in German.** English stays the source language for code, ARB keys and `app_en.arb`, but German is the reference for tone and register — it is what a child actually reads. A German string that reads badly is a bug even when the English is fine.

Smartfinch has **two translation surfaces**, and both require complete coverage for all supported locales:

| Surface | Files | Covers |
|---------|-------|--------|
| UI strings | `lib/l10n/app_<locale>.arb` | Every label, button, help text, and message |
| Spoken phrasing | `assets/announcements/templates_<locale>.json` | The sentences the app speaks aloud on a detection |

> **Do not stop at the ARB file.** The announcement templates are not in ARB (they are variant *lists*, which ARB cannot model — see `assets/announcements/README.md` for the reasoning and the full guide). A missing or incomplete template file falls back to English **silently**, so the app can look fully translated while the voice is not.

### Supported Locales

- `en`
- `de`
- `cs`
- `es`
- `fr`
- `it`
- `pt`
- `nl`
- `nb` (Norwegian Bokmål)
- `pl`
- `ru`
- `zh` (Simplified Chinese)

### Translation Rules (UI strings)

- **Keep in English across locales only what is genuinely a format or a proper noun:** WAV, FLAC, CSV, JSON, BirdNET. Everything else gets a real word in the target language. The old rule kept *Point Count*, *Survey*, *Session*, *Live Mode*, *Raven Selection Table*, *Smart* and *Gain* in English because the audience were researchers; an eight-year-old does not know what a session is (`KID-03`).
- **Write for a child, not about a feature.** Name the effect, not the cause — "no stars right now", never "species filter disabled". Short sentences, no unexplained jargon.
- **Never phrase anything as a punishment** (principle 1). No red, no exclamation marks, no commentary on a broken streak. If a value changed, say why in plain words (principle 6).
- Prefer gender-neutral wording where it is natural and idiomatic in the target language.
- Keep register consistent within each locale: use either formal or informal phrasing, but do not mix both in the same locale.
- Keep placeholders and message syntax intact (`{count}`, `{name}`, ICU `plural`/`select` blocks).
- Add or update the `@key` metadata `description` for new or ambiguous strings so translators have context.
- Do not split one sentence into multiple keys just to compose it in code.
- Do not hardcode UI strings in Dart widgets; always use `l10n.keyName`.
- For wording changes that alter meaning, prefer a new key name instead of silently reusing an old one.
- If you use machine translation, always do a human review before opening a PR.

### Translation Rules (spoken announcements)

- **Rewrite, do not translate literally.** These are spoken sentences; what sounds natural in English rarely maps word for word. Variant counts may differ from the English file.
- **Never put an article or demonstrative directly before `{name}`.** Species names carry no grammatical gender in our data, so the app cannot inflect the determiner to agree (*der Zaunkönig* / *die Amsel* / *das Rotkehlchen*). This applies to `ten`/`ta`/`to` and `этот`/`эта`/`это` in Polish and Russian too.
- Keep placeholders intact and untranslated: `{name}`, `{name1}`, `{name2}`, `{name3}`.
- Preserve the confidence gradient across buckets — `A`/`B`/`C` state the species plainly, `D`/`E` hedge slightly, `F`/`G` hedge clearly.
- Keep utterances short (one clause, two at most) and free of abbreviations or symbols the TTS engine will mispronounce.
- Match the register the locale uses in its ARB file, so the voice is not formal where the UI is informal.

The bucket reference, commonness bins, and full conventions are in `assets/announcements/README.md`.

### Translation Workflow

1. Add or update the source string in `lib/l10n/app_en.arb`.
2. Add matching translations in every other locale ARB file.
3. If the change touches spoken announcements, update `assets/announcements/templates_<locale>.json` for every locale as well.
4. If you add a new language, make sure it is included in the app language selector and supported locale configuration, **and add its `templates_<locale>.json`**.
5. Run `flutter gen-l10n`.
6. Run `flutter analyze`.
7. Run focused tests when the string change affects behavior (for example plural/select logic). For announcement templates, run `flutter test test/features/announcements/` — it checks bucket and commonness coverage per locale and lints for gendered determiners before `{name}`.
8. Manually check the changed screens in at least one non-English locale and look for overflow/truncation in both portrait and landscape. For announcements, hear them via **Settings → Announcements → Preview**.

### Pull Request Checklist for Translation Changes

- Include only translation-related edits in a translation PR (ARB files, generated localization output, and announcement templates).
- Mention which locales were updated, and whether the change covers UI strings, spoken announcements, or both.
- Call out any intentionally untranslated terms.
- Add screenshots when the change affects layout-sensitive UI text.

For deeper localization conventions, see `docs/developer/localization.md`. For the spoken announcement templates specifically, see `assets/announcements/README.md`.

## Pull Request Guidelines

1. **Branch naming**: `feature/description`, `fix/description`, `docs/description`
2. **Commit messages**: Use [Conventional Commits](https://www.conventionalcommits.org/)
   - `feat: add spectrogram color map selector`
   - `fix: resolve audio buffer overflow`
   - `docs: update API integration guide`
   - For scoring-related changes, reference the requirement ID: `feat(scoring): freeze applied threshold in ScoreEvent (PKT-15)`
3. **Keep PRs focused**: One feature or fix per PR
4. **Tests**: Add tests for new functionality. **The scoring engine is not optional here** — every rule change needs a test, and scoring must stay deterministic (`NFA-06`, `NFA-14`)
5. **Documentation**: Update relevant docs for user-facing changes
6. **Changelog**: Add user-visible changes to the `Unreleased` section of `CHANGELOG.md`

### Before you open a PR that touches scoring

The scoring layer can corrupt a child's collection in ways that stay invisible for weeks. Check all four:

- [ ] Nothing writes to the **life list** except a genuine, scoring detection — writing it early burns that species' first-find ×3 forever (`PKT-04`, `DAT-11`)
- [ ] Frozen `ScoreEvent` fields stay frozen: base value, level, `geoWeek`, grid cell, applied threshold (`PKT-15`)
- [ ] `geoWeek` and `isoWeek` are not confused — different calendars, different jobs
- [ ] Nothing can *lower* a level or take a collected species away (principle 1)

### Upstream merges

This repository is a fork that keeps merging from `birdnet-team/birdnet-live-app`. To keep that possible:

- Do not restructure `features/inference`, `features/audio`, `features/recording`, `features/spectrogram` or `core/services/asset_pack_service` — additive changes only.
- Put new Smartfinch code in new directories; new files never conflict.
- Do not resurrect a deleted module while resolving a merge conflict.

## Reporting Issues

- Use GitHub Issues with the appropriate template
- Include device info, Flutter version, and steps to reproduce
- Attach logs if relevant (`flutter logs`)

## Code of Conduct

Please read our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.
