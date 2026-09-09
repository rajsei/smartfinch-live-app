import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/app_data_clear_service.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/settings_providers.dart';
import '../../shared/widgets/content_width_constraint.dart';
import '../../shared/widgets/map_picker_screen.dart';
import '../about/about_screen.dart';
import '../announcements/widgets/announcements_settings_section.dart';
import '../audio/widgets/audio_source_tile.dart';
import '../explore/explore_providers.dart';
import '../rules/rules_screen.dart';
import '../scoring/scoring_rules.dart';
import '../spectrogram/color_maps.dart';
import 'animation_level.dart';
import 'backup/backup_screen.dart';
import 'offline_map_download_tile.dart';

bool get _showOfflineMapDownloadSetting => false;

// ---------------------------------------------------------------------------
// The expert inference controls are gone (SET-01)
// ---------------------------------------------------------------------------
//
// Pooling parameters, sensitivity and the species ignore list used to live in
// the Inference section. They are the **one genuine deletion** in the settings
// reorganisation, and unlike everything else here they are not merely hidden:
// they change what counts as a detection, and a settings screen that can be
// used to arrange your own collection has no place in a scoring app.
//
// Every provider stays wired, persisted and exported — only the controls are
// gone, so the pipeline runs on the shipped defaults:
//
// **Score pooling `adaptive_lme_peak`** — Log-Mean-Exp pooling at all inference
// rates (alpha 5.0), displaying the recent per-window peak as the confidence,
// guarded by:
//   * **Temporal support gate** — a new detection needs >= 2 recent windows at
//     or above the per-window support threshold (confidence x 0.6, floored at
//     0.25), unless a single window hits the 0.98 immediate-bypass score.
//   * **Pooling window + time gate** — up to 5 recent windows, dropping any
//     older than 10 s of real time.
//
// **Sensitivity 1.0** and **nothing ignored** — no taxon group suppressed, no
// common-species cutoff.
//
// These mirror `temporalPooling` in `assets/models/model_config.json` and the
// provider defaults in `settings_providers.dart`. Change them there, not here.

String _detectedSpeciesSortHelp(AppLocalizations l10n, String sortMode) {
  switch (DetectedSpeciesSortMode.normalize(sortMode)) {
    case DetectedSpeciesSortMode.confidence:
      return l10n.settingsHelpDetectedSpeciesSortConfidence;
    case DetectedSpeciesSortMode.alphabetical:
      return l10n.settingsHelpDetectedSpeciesSortAlphabetical;
    case DetectedSpeciesSortMode.occurrences:
      return l10n.settingsHelpDetectedSpeciesSortOccurrences;
    case DetectedSpeciesSortMode.newest:
    default:
      return l10n.settingsHelpDetectedSpeciesSortNewest;
  }
}

// ---------------------------------------------------------------------------
// Plain and Advanced — which settings appear where (SET-01, D13)
// ---------------------------------------------------------------------------

/// Which half of the settings a [SettingsScreen] instance renders.
///
/// This replaces the old per-mode `SettingsContext`, which tagged every section
/// with the research modes it belonged to (Survey, ARU, Point Count, File
/// Analysis). Those modes are gone, so every section applied to every context
/// and the mechanism filtered nothing.
///
/// The split it does now is the one SET-01 asks for: **reorganised, not cut
/// back**. Nothing is lost for the adult who wants it; nothing is in the way of
/// the child who does not.
enum SettingsView {
  /// What a child or a parent actually touches: appearance, language,
  /// announcements, location, privacy, storage.
  plain,

  /// Everything else, one tap away — audio, inference, spectrogram, recording,
  /// playback, the species filter and export.
  advanced,
}

/// Settings screen with categorized preferences.
///
/// Renders either half of the settings depending on [view]; the plain screen
/// carries a tile that pushes the advanced one.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.view = SettingsView.plain});

  /// Which half to render.
  final SettingsView view;

  /// Which view each section belongs to.
  ///
  /// One entry per section, so a section can never be silently missing from
  /// both screens — the thing the old context map could not guarantee. Public
  /// because that property is worth asserting: SET-01's promise is
  /// *reorganised, not cut back*, and a section on neither screen breaks it
  /// without anything visibly failing.
  static const Map<String, SettingsView> sectionViews = {
    'general': SettingsView.plain,
    'announcements': SettingsView.plain,
    'location': SettingsView.plain,
    'privacy': SettingsView.plain,
    'about': SettingsView.plain,
    'backup': SettingsView.plain,
    'danger': SettingsView.plain,
    'audio': SettingsView.advanced,
    'inference': SettingsView.advanced,
    'spectrogram': SettingsView.advanced,
    'recording': SettingsView.advanced,
    'speciesFilter': SettingsView.advanced,
    'export': SettingsView.advanced,
  };

  /// Returns `true` if [section] belongs on the screen being built.
  bool _showSection(String section) => sectionViews[section] == view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          view == SettingsView.advanced ? l10n.settingsAdvanced : l10n.settings,
        ),
      ),
      body: ContentWidthConstraint(
        child: ListView(
          children: [
            // A standing reminder rather than a one-off warning: the screen is
            // reachable at any time, and the settings on it change what the app
            // counts as a detection.
            if (view == SettingsView.advanced)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(
                  color: theme.colorScheme.surfaceContainerHighest,
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          AppIcons.infoOutline,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.settingsAdvancedNotice,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // --- General ---
            if (_showSection('general')) ...[
              _SectionHeader(
                title: l10n.settingsGeneral,
                subtitle: l10n.settingsGeneralDescription,
              ),
              _ThemeTile(l10n: l10n),

              // SET-02 sits on the plain screen, not behind Advanced: it is
              // both an accessibility setting and an annoyance control, and
              // both of those are things a parent looks for on the first
              // screen rather than two taps in.
              _ChoiceTile<String>(
                title: l10n.settingsAnimationLevel,
                helpBody: l10n.settingsAnimationLevelHelp,
                value: ref.watch(animationLevelSettingProvider),
                options: {
                  AnimationLevel.full.storageValue:
                      l10n.settingsAnimationLevelFull,
                  AnimationLevel.reduced.storageValue:
                      l10n.settingsAnimationLevelReduced,
                  AnimationLevel.off.storageValue:
                      l10n.settingsAnimationLevelOff,
                },
                onChanged:
                    (v) =>
                        ref.read(animationLevelSettingProvider.notifier).set(v),
              ),

              // The rules, in the child's own language (SET-11). On the plain
              // screen and near the top, because a child who cannot find out
              // why a number moved decides the app is arbitrary.
              ListTile(
                leading: const Icon(AppIcons.helpOutlineRounded),
                title: Text(l10n.rulesTitle),
                trailing: const Icon(AppIcons.chevronRight),
                onTap:
                    () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RulesScreen(),
                      ),
                    ),
              ),

              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsDynamicColor,
                  helpBody: l10n.settingsHelpDynamicColor,
                ),
                subtitle: Text(l10n.settingsDynamicColorDescription),
                value: ref.watch(dynamicColorProvider),
                onChanged:
                    (v) => ref.read(dynamicColorProvider.notifier).set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsHighContrastTheme,
                  helpBody: l10n.settingsHelpHighContrastTheme,
                ),
                value: ref.watch(highContrastThemeProvider),
                onChanged:
                    (v) => ref.read(highContrastThemeProvider.notifier).set(v),
              ),
              _LanguageTile(l10n: l10n),
              _SpeciesLanguageTile(l10n: l10n),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsShowSciNames,
                  helpBody: l10n.settingsHelpShowSciNames,
                ),
                value: ref.watch(showSciNamesProvider),
                onChanged:
                    (v) => ref.read(showSciNamesProvider.notifier).set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsShowAllDetectedSpecies,
                  helpBody: l10n.settingsHelpShowAllDetectedSpecies,
                ),
                subtitle: Text(l10n.settingsShowAllDetectedSpeciesDescription),
                value: ref.watch(showAllDetectedSpeciesProvider),
                onChanged:
                    (v) => ref
                        .read(showAllDetectedSpeciesProvider.notifier)
                        .set(v),
              ),
              if (ref.watch(showAllDetectedSpeciesProvider))
                _ChoiceTile<String>(
                  title: l10n.settingsDetectedSpeciesSortMode,
                  value: ref.watch(detectedSpeciesSortModeProvider),
                  options: {
                    DetectedSpeciesSortMode.newest:
                        l10n.settingsDetectedSpeciesSortNewest,
                    DetectedSpeciesSortMode.confidence:
                        l10n.settingsDetectedSpeciesSortConfidence,
                    DetectedSpeciesSortMode.alphabetical:
                        l10n.settingsDetectedSpeciesSortAlphabetical,
                    DetectedSpeciesSortMode.occurrences:
                        l10n.settingsDetectedSpeciesSortOccurrences,
                  },
                  subtitle: _detectedSpeciesSortHelp(
                    l10n,
                    ref.watch(detectedSpeciesSortModeProvider),
                  ),
                  helpBody: _detectedSpeciesSortHelp(
                    l10n,
                    ref.watch(detectedSpeciesSortModeProvider),
                  ),
                  onChanged:
                      (v) => ref
                          .read(detectedSpeciesSortModeProvider.notifier)
                          .set(v),
                ),
              ListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsTimestampDisplayMode,
                  helpBody: l10n.settingsHelpTimestampDisplayMode,
                ),
                subtitle: Text(l10n.settingsTimestampDisplayModeDescription),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'relative',
                        label: _SegmentLabel(
                          text: l10n.settingsTimestampDisplayModeRelative,
                        ),
                      ),
                      ButtonSegment(
                        value: 'absolute',
                        label: _SegmentLabel(
                          text: l10n.settingsTimestampDisplayModeAbsolute,
                        ),
                      ),
                    ],
                    selected: {ref.watch(timestampDisplayModeProvider)},
                    onSelectionChanged: (selected) {
                      HapticFeedback.selectionClick();
                      ref
                          .read(timestampDisplayModeProvider.notifier)
                          .set(selected.first);
                    },
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ),
              if (ref.watch(timestampDisplayModeProvider) == 'absolute')
                SwitchListTile(
                  title: _TitleWithHelp(
                    title: l10n.settingsTimestampShowSeconds,
                    helpBody: l10n.settingsHelpTimestampShowSeconds,
                  ),
                  subtitle: Text(l10n.settingsTimestampShowSecondsDescription),
                  value: ref.watch(timestampShowSecondsProvider),
                  onChanged:
                      (v) => ref
                          .read(timestampShowSecondsProvider.notifier)
                          .set(v),
                ),
              const Divider(),
            ],

            // --- Audio ---
            if (_showSection('audio')) ...[
              _SectionHeader(
                title: l10n.settingsAudio,
                subtitle: l10n.settingsAudioDescription,
              ),
              const AudioSourceTile(),
              _SliderTile(
                title: l10n.settingsGain,
                helpBody: l10n.settingsHelpGain,
                value: ref.watch(audioGainProvider),
                min: 0.0,
                max: 2.0,
                divisions: 20,
                format: (v) => v.toStringAsFixed(1),
                onChanged: (v) => ref.read(audioGainProvider.notifier).set(v),
              ),
              _SliderTile(
                title: l10n.settingsHighPassFilter,
                helpBody: l10n.settingsHelpHighPassFilter,
                value: ref.watch(highPassFilterProvider),
                min: 0,
                max: 1000,
                divisions: 100,
                format: (v) => '${v.toInt()} Hz',
                onChanged:
                    (v) => ref.read(highPassFilterProvider.notifier).set(v),
              ),
              const Divider(),
            ],

            // --- Inference ---
            if (_showSection('inference')) ...[
              _SectionHeader(
                title: l10n.settingsInference,
                subtitle: l10n.settingsInferenceDescription,
              ),
              _DiscreteSliderTile<int>(
                title: l10n.settingsWindowDuration,
                helpBody: l10n.settingsHelpWindowDuration,
                value: ref.watch(windowDurationProvider),
                values: const [1, 3, 5, 7, 10, 15],
                format: (v) => '${v}s',
                onChanged:
                    (v) => ref.read(windowDurationProvider.notifier).set(v),
              ),
              const _ConfidenceThresholdTile(),
              _DiscreteSliderTile<double>(
                title: l10n.settingsInferenceRate,
                helpBody: l10n.settingsHelpInferenceRate,
                value: ref.watch(inferenceRateProvider),
                values: inferenceRateHzValues,
                format: (v) => '${v.toStringAsFixed(2)} Hz',
                onChanged:
                    (v) => ref.read(inferenceRateProvider.notifier).set(v),
              ),
              const Divider(),
            ],

            // --- Spectrogram ---
            if (_showSection('spectrogram')) ...[
              _SectionHeader(
                title: l10n.settingsSpectrogram,
                subtitle: l10n.settingsSpectrogramDescription,
              ),
              _ChoiceTile<int>(
                title: l10n.settingsFftSize,
                helpBody: l10n.settingsHelpFftSize,
                value: ref.watch(fftSizeProvider),
                options: const {
                  512: '512',
                  1024: '1024',
                  2048: '2048',
                  4096: '4096',
                },
                onChanged: (v) => ref.read(fftSizeProvider.notifier).set(v),
              ),
              _ColorMapChoiceTile(
                title: l10n.settingsColorMap,
                helpBody: l10n.settingsHelpColorMap,
                value: ref.watch(colorMapProvider),
                options: {
                  'viridis': l10n.settingsColorMapViridis,
                  'magma': l10n.settingsColorMapMagma,
                  'plasma': l10n.settingsColorMapPlasma,
                  'cividis': l10n.settingsColorMapCividis,
                  'jet': l10n.settingsColorMapJet,
                  'turbo': l10n.settingsColorMapTurbo,
                  'grayscale': l10n.settingsColorMapGrayscale,
                  'birdnet': l10n.settingsColorMapBirdnet,
                },
                onChanged: (v) => ref.read(colorMapProvider.notifier).set(v),
              ),
              _ChoiceTile<int>(
                title: l10n.settingsSpectrogramDuration,
                helpBody: l10n.settingsHelpSpectrogramDuration,
                value: ref.watch(spectrogramDurationProvider),
                options: const {
                  5: '5 s',
                  10: '10 s',
                  15: '15 s',
                  20: '20 s',
                  30: '30 s',
                },
                onChanged:
                    (v) =>
                        ref.read(spectrogramDurationProvider.notifier).set(v),
              ),
              _ChoiceTile<int>(
                title: l10n.settingsFrequencyRange,
                helpBody: l10n.settingsHelpFrequencyRange,
                value: ref.watch(spectrogramMaxFreqProvider),
                options: const {
                  4000: '4 kHz',
                  6000: '6 kHz',
                  8000: '8 kHz',
                  10000: '10 kHz',
                  12000: '12 kHz',
                  16000: '16 kHz',
                },
                onChanged:
                    (v) => ref.read(spectrogramMaxFreqProvider.notifier).set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsLogAmplitude,
                  helpBody: l10n.settingsHelpLogAmplitude,
                ),
                value: ref.watch(logAmplitudeProvider),
                onChanged:
                    (v) => ref.read(logAmplitudeProvider.notifier).set(v),
              ),
              _ChoiceTile<String>(
                title: l10n.settingsSpectrogramQuality,
                helpBody: l10n.settingsHelpSpectrogramQuality,
                value: ref.watch(spectrogramQualityProvider),
                options: {
                  'low': l10n.settingsSpectrogramQualityLow,
                  'medium': l10n.settingsSpectrogramQualityMedium,
                  'high': l10n.settingsSpectrogramQualityHigh,
                },
                onChanged:
                    (v) => ref.read(spectrogramQualityProvider.notifier).set(v),
              ),
              const Divider(),
            ],

            // --- Recording ---
            if (_showSection('recording')) ...[
              _SectionHeader(
                title: l10n.settingsRecording,
                subtitle: l10n.settingsRecordingDescription,
              ),
              _ChoiceTile<String>(
                title: l10n.settingsRecordingMode,
                helpBody: l10n.settingsHelpRecordingMode,
                value: ref.watch(recordingModeProvider),
                options: {
                  'full': l10n.settingsRecordingModeFull,
                  'detections': l10n.settingsRecordingModeDetections,
                  'off': l10n.settingsRecordingModeOff,
                },
                onChanged:
                    (v) => ref.read(recordingModeProvider.notifier).set(v),
              ),
              // Clip context (visible only when recording mode = detections)
              if (ref.watch(recordingModeProvider) == 'detections') ...[
                ListTile(
                  title: Text(l10n.surveyClipContext),
                  subtitle: Text(l10n.surveyClipContextDescription),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Semantics(
                    label: l10n.surveyClipContext,
                    value: '\u00b1${ref.watch(clipContextProvider)}s',
                    child: Slider(
                      value: ref.watch(clipContextProvider).toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      label: '\u00b1${ref.watch(clipContextProvider)}s',
                      onChanged:
                          (v) => ref
                              .read(clipContextProvider.notifier)
                              .set(v.round()),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              // Audio file format only matters when something is being
              // recorded; hiding it for mode = off avoids implying that the
              // setting has any effect.
              if (ref.watch(recordingModeProvider) != 'off')
                _ChoiceTile<String>(
                  title: l10n.settingsRecordingFormat,
                  helpBody: l10n.settingsHelpRecordingFormat,
                  value: ref.watch(recordingFormatProvider),
                  options: const {'wav': 'WAV', 'flac': 'FLAC'},
                  onChanged:
                      (v) => ref.read(recordingFormatProvider.notifier).set(v),
                ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsSaveSessionAutomatically,
                  helpBody: l10n.settingsHelpSaveSessionAutomatically,
                ),
                subtitle: Text(
                  l10n.settingsSaveSessionAutomaticallyDescription,
                ),
                value: ref.watch(saveSessionAutomaticallyProvider),
                onChanged:
                    (v) => ref
                        .read(saveSessionAutomaticallyProvider.notifier)
                        .set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsLiveAutoStart,
                  helpBody: l10n.settingsHelpLiveAutoStart,
                ),
                subtitle: Text(l10n.settingsLiveAutoStartDescription),
                value: ref.watch(liveAutoStartProvider),
                onChanged:
                    (v) => ref.read(liveAutoStartProvider.notifier).set(v),
              ),
              const Divider(),
            ],

            // --- Announcements ---
            if (_showSection('announcements'))
              AnnouncementsSettingsSection(
                sectionHeader:
                    ({required String title, required String subtitle}) =>
                        _SectionHeader(title: title, subtitle: subtitle),
                titleWithHelp:
                    ({required String title, String? helpBody}) =>
                        _TitleWithHelp(title: title, helpBody: helpBody),
              ),

            // --- Location / Geo ---
            if (_showSection('location')) ...[
              _SectionHeader(
                title: l10n.settingsLocation,
                subtitle: l10n.settingsLocationDescription,
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsUseGps,
                  helpBody: l10n.settingsHelpUseGps,
                ),
                subtitle: Text(l10n.settingsUseGpsDescription),
                value: ref.watch(useGpsProvider),
                onChanged: (v) => ref.read(useGpsProvider.notifier).set(v),
              ),
              if (!ref.watch(useGpsProvider)) ...[
                const _ManualCoordinatesTile(),
              ],
              if (ref.watch(useGpsProvider)) const _GpsRefreshTile(),
              if (_showOfflineMapDownloadSetting && ref.watch(useGpsProvider))
                const OfflineMapDownloadTile(),
              const Divider(),
            ],

            // --- Species filter (advanced) ---
            //
            // Split out of the Location section: the GPS switch belongs on the
            // plain screen — without a position there is no rarity level and
            // therefore no stars (SET-09) — while the filter mode changes what
            // counts as a detection and belongs behind Advanced with the
            // SET-13 warning.
            if (_showSection('speciesFilter')) ...[
              // Headed "Location" rather than "Species filter" so the header
              // does not simply repeat the tile beneath it — and because that
              // names where the section came from, which is where an adult
              // will look for it.
              _SectionHeader(
                title: l10n.settingsLocation,
                subtitle: l10n.settingsSpeciesFilterSectionDescription,
              ),
              _ChoiceTile<String>(
                title: l10n.settingsSpeciesFilter,
                helpBody: l10n.settingsHelpSpeciesFilter,
                value: ref.watch(speciesFilterModeProvider),
                options: {
                  'off': l10n.settingsFilterOff,
                  'geoExclude': l10n.settingsFilterGeoExclude,
                  'geoAdaptive': l10n.settingsFilterGeoAdaptive,
                  'geoMerge': l10n.settingsFilterGeoMerge,
                },
                onChanged: (v) async {
                  // Turning the filter off pauses scoring entirely (PKT-20),
                  // so it is confirmed before it takes effect rather than
                  // explained afterwards.
                  if (v == 'off' &&
                      !await confirmScoringPause(context, ref, l10n)) {
                    return;
                  }
                  ref.read(speciesFilterModeProvider.notifier).set(v);
                },
              ),
              // Adaptive mode derives its own bar from the local score
              // distribution, so the manual threshold does not apply there.
              if (ref.watch(speciesFilterModeProvider) != 'off' &&
                  ref.watch(speciesFilterModeProvider) != 'geoAdaptive')
                _SliderTile(
                  title: l10n.settingsGeoThreshold,
                  helpBody: l10n.settingsHelpGeoThreshold,
                  value: ref.watch(geoThresholdProvider),
                  min: 0.0,
                  max: 0.5,
                  divisions: 50,
                  format: (v) => v.toStringAsFixed(2),
                  onChanged:
                      (v) => ref.read(geoThresholdProvider.notifier).set(v),
                ),
              const Divider(),
            ],

            // --- Export ---
            if (_showSection('export')) ...[
              _SectionHeader(
                title: l10n.settingsExport,
                subtitle: l10n.settingsExportDescription,
              ),
              // Everything else this section used to carry — the Raven /
              // CSV / JSON / GPX picker, "share as WAV", the app-metadata
              // block and the HTML report — went with the research modes it
              // configured. What it exported was a *session*, the level of
              // navigation `LOG-01` removed, in formats meant for people who
              // open selection tables. The one switch left is the one anybody
              // can answer for themselves: whether the audio goes with it.
              CheckboxListTile(
                dense: true,
                title: _TitleWithHelp(
                  title: l10n.settingsIncludeAudioFiles,
                  helpBody: l10n.settingsHelpIncludeAudioFiles,
                ),
                value: ref.watch(includeAudioProvider),
                onChanged:
                    (v) =>
                        ref.read(includeAudioProvider.notifier).set(v ?? false),
              ),
              const Divider(),
            ],

            // --- Privacy ---
            if (_showSection('privacy')) ...[
              _SectionHeader(
                title: l10n.settingsPrivacy,
                subtitle: l10n.settingsPrivacyDescription,
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsPrivacyAllowMap,
                  helpBody: l10n.settingsHelpPrivacyAllowMap,
                ),
                subtitle: Text(l10n.settingsPrivacyAllowMapSubtitle),
                value: ref.watch(privacyAllowMapProvider),
                onChanged:
                    (v) => ref.read(privacyAllowMapProvider.notifier).set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsPrivacyAllowReverseGeocoding,
                  helpBody: l10n.settingsHelpPrivacyAllowReverseGeocoding,
                ),
                subtitle: Text(
                  l10n.settingsPrivacyAllowReverseGeocodingSubtitle,
                ),
                value: ref.watch(privacyAllowReverseGeocodingProvider),
                onChanged:
                    (v) => ref
                        .read(privacyAllowReverseGeocodingProvider.notifier)
                        .set(v),
              ),
              SwitchListTile(
                title: _TitleWithHelp(
                  title: l10n.settingsPrivacyAllowWeather,
                  helpBody: l10n.settingsHelpPrivacyAllowWeather,
                ),
                subtitle: Text(l10n.settingsPrivacyAllowWeatherSubtitle),
                value: ref.watch(privacyAllowWeatherProvider),
                onChanged:
                    (v) =>
                        ref.read(privacyAllowWeatherProvider.notifier).set(v),
              ),
              const Divider(),
            ],

            // --- Advanced settings ---
            //
            // The door to everything the plain screen does not carry. One tap,
            // not a hidden gesture: nothing here is secret, it is only out of
            // the way (SET-01).
            if (view == SettingsView.plain)
              ListTile(
                leading: const Icon(AppIcons.tune),
                title: Text(l10n.settingsAdvanced),
                subtitle: Text(l10n.settingsAdvancedDescription),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder:
                          (_) =>
                              const SettingsScreen(view: SettingsView.advanced),
                    ),
                  );
                },
              ),

            // --- About ---
            if (_showSection('about'))
              ListTile(
                title: Text(l10n.about),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  );
                },
              ),

            // --- Backup (SET-07) ---
            //
            // On the plain screen, not behind Advanced: it is the only thing
            // standing between a broken phone and a lost collection, and the
            // parent who needs it is not going looking for it. It sits beside
            // the danger zone because those are the two irreversible data
            // actions, and a parent finds both in one place.
            if (_showSection('backup')) ...[
              const Divider(),
              ListTile(
                leading: const Icon(AppIcons.save),
                title: Text(l10n.backupTitle),
                subtitle: Text(l10n.backupSubtitle),
                trailing: const Icon(AppIcons.chevronRight),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BackupScreen(),
                    ),
                  );
                },
              ),
            ],

            // --- Danger Zone ---
            if (_showSection('danger')) ...[
              const Divider(),
              _SectionHeader(
                title: l10n.settingsDangerZone,
                subtitle: l10n.settingsDangerZoneDescription,
              ),
              ListTile(
                title: Text(l10n.settingsResetOnboarding),
                onTap: () => _showResetOnboardingDialog(context, ref, l10n),
              ),
              ListTile(
                title: Text(l10n.settingsResetAll),
                subtitle: Text(l10n.settingsResetAllSubtitle),
                onTap: () => _showResetAllSettingsDialog(context, l10n),
              ),
              ListTile(
                title: Text(
                  l10n.settingsClearData,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                onTap: () => _showClearDataDialog(context, l10n),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showResetOnboardingDialog(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.settingsResetOnboardingConfirmTitle),
            content: Text(l10n.settingsResetOnboardingConfirmMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () {
                  ref.read(onboardingCompleteProvider.notifier).reset();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.settingsOnboardingReset)),
                  );
                },
                child: Text(l10n.confirm),
              ),
            ],
          ),
    );
  }

  void _showResetAllSettingsDialog(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.settingsResetAllConfirmTitle),
          content: Text(l10n.settingsResetAllConfirmMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.of(dialogContext).pop();
                // Clear every persisted preference. Sessions, recordings,
                // voice memos and downloaded map tiles live outside of
                // SharedPreferences and are intentionally untouched.
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.settingsResetAllDone)),
                );
                // On Android we close the app so the next launch boots
                // with the freshly-reset defaults applied to every
                // provider. Other platforms leave the app running and
                // rely on the user to relaunch manually.
                await Future<void>.delayed(const Duration(milliseconds: 800));
                await SystemNavigator.pop();
              },
              child: Text(l10n.confirm),
            ),
          ],
        );
      },
    );
  }

  void _showClearDataDialog(BuildContext context, AppLocalizations l10n) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        var isClearing = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            final typed = controller.text.trim().toUpperCase() == 'DELETE';
            return AlertDialog(
              title: Text(l10n.settingsClearDataConfirmTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.settingsClearDataConfirmMessage),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    onChanged: (_) => setState(() {}),
                    enabled: !isClearing,
                    decoration: InputDecoration(
                      labelText: l10n.settingsClearDataTypeConfirm,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isClearing ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton.tonal(
                  onPressed:
                      typed && !isClearing
                          ? () async {
                            final navigator = Navigator.of(context);
                            final messenger = ScaffoldMessenger.of(context);
                            setState(() => isClearing = true);
                            try {
                              await const AppDataClearService().clearAllData();
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.settingsDataCleared),
                                ),
                              );
                              await Future<void>.delayed(
                                const Duration(milliseconds: 800),
                              );
                              await SystemNavigator.pop();
                            } catch (_) {
                              if (!context.mounted) return;
                              setState(() => isClearing = false);
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.settingsDataClearFailed),
                                ),
                              );
                            }
                          }
                          : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                  ),
                  child:
                      isClearing
                          ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : Text(l10n.confirm),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// SET-13 — the warning on the settings that stop scoring
// ---------------------------------------------------------------------------

/// Asks whether the user really wants to pause scoring, and returns `true` if
/// the change should go ahead.
///
/// The species filter and the confidence threshold both change what counts as
/// a detection, so rather than locking them the app pauses the whole scoring
/// layer while they sit outside the scoring range (`PKT-20`). That trade is
/// shown **at the moment of change**, not buried in a help text, because it is
/// reachable by an adult experimenting on a child's device.
///
/// The wording has to carry four things and every one of them matters:
///
///   * the honest cost — no stars, nothing added to the collection;
///   * **the streak**, which follows from `STAT-06`'s definition of an active
///     day and would otherwise be discovered days later as a mystery;
///   * that recordings are kept and still appear in the journal (`LOG-15`), so
///     nothing is thrown away;
///   * that everything already collected stays untouched.
Future<bool> confirmScoringPause(
  BuildContext context,
  WidgetRef ref,
  AppLocalizations l10n,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          icon: const Icon(AppIcons.warningAmberRounded),
          title: Text(l10n.settingsScoringPauseTitle),
          content: Text(l10n.settingsScoringPauseBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.settingsScoringPauseConfirm),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

/// The confidence threshold, with the scoring floor drawn on its track.
///
/// Two things separate this from a plain [_SliderTile]:
///
///   * **The floor is visible before the drag**, not only in the warning
///     afterwards — `SET-13` asks for it as a marked point on the track, and a
///     mark you can see is worth more than a dialog you have to read.
///   * **The confirmation fires once, on release.** A slider reports every
///     intermediate value, so confirming in `onChanged` would open a dialog the
///     instant the thumb crossed 35 and again on the way back. The value is
///     therefore held locally while dragging and committed in `onChangeEnd`.
class _ConfidenceThresholdTile extends ConsumerStatefulWidget {
  const _ConfidenceThresholdTile();

  @override
  ConsumerState<_ConfidenceThresholdTile> createState() =>
      _ConfidenceThresholdTileState();
}

class _ConfidenceThresholdTileState
    extends ConsumerState<_ConfidenceThresholdTile> {
  /// Non-null only while the thumb is being dragged.
  double? _dragging;

  Future<void> _commit(double value) async {
    final l10n = AppLocalizations.of(context)!;
    final threshold = value.toInt();
    final floor = ScoringRules.current.scoringThresholdFloor;
    final wasScoring = ref.read(confidenceThresholdProvider) >= floor;

    // Only the crossing is confirmed. Moving from 20 to 25 is already paused
    // and asking again would be noise; raising the bar never asks at all,
    // because a stricter threshold produces fewer and safer detections and
    // cannot be abused.
    if (wasScoring && threshold < floor) {
      final ok = await confirmScoringPause(context, ref, l10n);
      if (!ok) {
        setState(() => _dragging = null);
        return;
      }
    }

    ref.read(confidenceThresholdProvider.notifier).set(threshold);
    if (mounted) setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final floor = ScoringRules.current.scoringThresholdFloor;
    final value =
        _dragging ?? ref.watch(confidenceThresholdProvider).toDouble();
    final paused = value < floor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: _TitleWithHelp(
            title: l10n.settingsConfidenceThreshold,
            helpBody: l10n.settingsHelpConfidenceThreshold,
          ),
          subtitle: Semantics(
            label: l10n.settingsConfidenceThreshold,
            value: '${value.toInt()}%',
            child: Slider(
              value: value,
              min: 0,
              max: 100,
              divisions: 100,
              label: '${value.toInt()}%',
              // The floor as a real division on the track, so the point where
              // scoring stops is part of the control rather than a footnote.
              secondaryTrackValue: floor.toDouble(),
              onChanged: (v) => setState(() => _dragging = v),
              onChangeEnd: _commit,
            ),
          ),
          trailing: Text('${value.toInt()}%', style: theme.textTheme.bodySmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                paused ? AppIcons.warningAmberRounded : AppIcons.infoOutline,
                size: 18,
                color:
                    paused
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  paused
                      ? l10n.settingsScoringPausedNow
                      : l10n.settingsScoringFloorHint(floor),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        paused
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Inline title row that appends a small "?" help button when [helpBody]
/// is provided. Tap opens [showHelpSheet] with the same [title] and the
/// localized explanatory paragraph.
///
/// When [helpBody] is null, falls back to a plain `Text(title)` so the
/// surrounding layout stays identical for settings without help text.
class _TitleWithHelp extends StatelessWidget {
  const _TitleWithHelp({required this.title, this.helpBody});

  final String title;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    if (helpBody == null) return Text(title);
    return Row(
      children: [
        Flexible(child: Text(title)),
        const SizedBox(width: 4),
        _HelpIconButton(title: title, body: helpBody!),
      ],
    );
  }
}

/// Compact info-icon button that opens a settings help bottom sheet.
class _HelpIconButton extends StatelessWidget {
  const _HelpIconButton({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      icon: const Icon(AppIcons.helpOutline, size: 18),
      visualDensity: VisualDensity.compact,
      tooltip: l10n.settingsHelpTooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () => showSettingHelpSheet(context, title: title, body: body),
    );
  }
}

/// Show a Material 3 modal bottom sheet with a setting's help text.
///
/// Centralized here so the styling (handle, padding, typography) stays
/// consistent across all per-setting help affordances.
Future<void> showSettingHelpSheet(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                body,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return ListTile(
      title: Text(l10n.settingsTheme),
      trailing: SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text(l10n.settingsThemeDark),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            label: Text(l10n.settingsThemeLight),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            label: Text(l10n.settingsThemeSystem),
          ),
        ],
        selected: {themeMode},
        onSelectionChanged: (selected) {
          HapticFeedback.selectionClick();
          ref.read(themeModeProvider.notifier).setThemeMode(selected.first);
        },
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({required this.l10n});
  final AppLocalizations l10n;

  static const double _dropdownWidth = 164;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return ListTile(
      title: Text(l10n.settingsAppLanguage),
      trailing: SizedBox(
        width: _dropdownWidth,
        child: DropdownButton<String?>(
          value: locale?.languageCode,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem(
              value: null,
              child: Text(
                l10n.settingsSpeciesLanguageSystem,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const DropdownMenuItem(value: 'cs', child: Text('Čeština')),
            const DropdownMenuItem(value: 'de', child: Text('Deutsch')),
            const DropdownMenuItem(value: 'en', child: Text('English')),
            const DropdownMenuItem(value: 'es', child: Text('Español')),
            const DropdownMenuItem(value: 'fr', child: Text('Français')),
            const DropdownMenuItem(value: 'it', child: Text('Italiano')),
            const DropdownMenuItem(value: 'nl', child: Text('Nederlands')),
            const DropdownMenuItem(value: 'nb', child: Text('Norsk bokmål')),
            const DropdownMenuItem(value: 'pl', child: Text('Polski')),
            const DropdownMenuItem(value: 'pt', child: Text('Português')),
            const DropdownMenuItem(value: 'ru', child: Text('Русский')),
            const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
          ],
          onChanged: (value) {
            ref
                .read(localeProvider.notifier)
                .setLocale(value == null ? null : Locale(value));
          },
        ),
      ),
    );
  }
}

/// Available species name locales (code → native name).
const _speciesLanguages = <String, String>{
  'system': '', // placeholder — label comes from l10n
  'app': '', // placeholder — label comes from l10n
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'pl': 'Polski',
  'nl': 'Nederlands',
  'ru': 'Русский',
  'ja': '日本語',
  'cs': 'Čeština',
  'pt': 'Português',
  'ca': 'Català',
  'no': 'Norsk',
  'bg': 'Български',
  'sv': 'Svenska',
  'da': 'Dansk',
  'zh-CN': '中文 (CN)',
  'tr': 'Türkçe',
  'sk': 'Slovenčina',
  'sr': 'Српски',
  'uk': 'Українська',
  'fi': 'Suomi',
  'es_ES': 'Español (ES)',
  'es_MX': 'Español (MX)',
  'es_EC': 'Español (EC)',
  'pt_PT': 'Português (PT)',
  'hr': 'Hrvatski',
  'lt': 'Lietuvių',
  'fa': 'فارسی',
  'cy': 'Cymraeg',
  'et': 'Eesti',
};

class _SpeciesLanguageTile extends ConsumerWidget {
  const _SpeciesLanguageTile({required this.l10n});
  final AppLocalizations l10n;

  static const double _dropdownWidth = _LanguageTile._dropdownWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speciesLang = ref.watch(speciesLanguageProvider);

    return ListTile(
      title: Text(l10n.settingsSpeciesLanguage),
      trailing: SizedBox(
        width: _dropdownWidth,
        child: DropdownButton<String>(
          value: speciesLang,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items:
              _speciesLanguages.entries.map((e) {
                return DropdownMenuItem(
                  value: e.key,
                  child: Text(
                    e.key == 'system'
                        ? l10n.settingsSpeciesLanguageSystem
                        : e.key == 'app'
                        ? l10n.settingsSpeciesLanguageFollowApp
                        : e.value,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
          onChanged: (value) {
            if (value != null) {
              ref.read(speciesLanguageProvider.notifier).set(value);
            }
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ManualCoordinatesTile — editable latitude / longitude entry
// ---------------------------------------------------------------------------
//
// Lets the user type or paste precise coordinates when GPS is off,
// addressing the imprecision of dragging a slider on a touch screen.
// Pasting a combined "lat, lon" string (comma-, semicolon-, or
// whitespace-separated) into either field fills both fields at once.
// Values are validated against geographic ranges and persisted to
// [manualLatitudeProvider] / [manualLongitudeProvider] as the user types.
// ---------------------------------------------------------------------------

class _ManualCoordinatesTile extends ConsumerStatefulWidget {
  const _ManualCoordinatesTile();

  @override
  ConsumerState<_ManualCoordinatesTile> createState() =>
      _ManualCoordinatesTileState();
}

class _ManualCoordinatesTileState
    extends ConsumerState<_ManualCoordinatesTile> {
  late final TextEditingController _latController = TextEditingController(
    text: _format(ref.read(manualLatitudeProvider)),
  );
  late final TextEditingController _lonController = TextEditingController(
    text: _format(ref.read(manualLongitudeProvider)),
  );
  final FocusNode _latFocus = FocusNode();
  final FocusNode _lonFocus = FocusNode();

  String? _latError;
  String? _lonError;

  static String _format(double v) => v.toStringAsFixed(5);

  @override
  void dispose() {
    _latController.dispose();
    _lonController.dispose();
    _latFocus.dispose();
    _lonFocus.dispose();
    super.dispose();
  }

  /// Parses a combined coordinate string such as "52.52, 13.40",
  /// "52.52; 13.40", or "52.52 13.40". Returns null when the text is not
  /// exactly two parseable numbers.
  static (double, double)? _parsePair(String text) {
    final parts =
        text
            .trim()
            .split(RegExp(r'[,;\s]+'))
            .where((p) => p.isNotEmpty)
            .toList();
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return null;
    return (lat, lon);
  }

  /// Applies a full lat/lon pair (typically pasted) to both providers and
  /// both text fields, validating each value against its range.
  void _applyPair(double lat, double lon, AppLocalizations l10n) {
    final latValid = lat >= -90 && lat <= 90;
    final lonValid = lon >= -180 && lon <= 180;
    setState(() {
      _latError = latValid ? null : l10n.settingsLatitudeRange;
      _lonError = lonValid ? null : l10n.settingsLongitudeRange;
    });
    if (latValid) {
      ref.read(manualLatitudeProvider.notifier).set(lat);
      final text = _format(lat);
      _latController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    if (lonValid) {
      ref.read(manualLongitudeProvider.notifier).set(lon);
      final text = _format(lon);
      _lonController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _onLatChanged(String value, AppLocalizations l10n) {
    final pair = _parsePair(value);
    if (pair != null) {
      _applyPair(pair.$1, pair.$2, l10n);
      return;
    }
    final trimmed = value.trim();
    final lat = double.tryParse(trimmed);
    setState(() {
      if (trimmed.isEmpty) {
        _latError = null;
      } else if (lat == null) {
        _latError = l10n.settingsCoordinateInvalid;
      } else if (lat < -90 || lat > 90) {
        _latError = l10n.settingsLatitudeRange;
      } else {
        _latError = null;
        ref.read(manualLatitudeProvider.notifier).set(lat);
      }
    });
  }

  void _onLonChanged(String value, AppLocalizations l10n) {
    final pair = _parsePair(value);
    if (pair != null) {
      _applyPair(pair.$1, pair.$2, l10n);
      return;
    }
    final trimmed = value.trim();
    final lon = double.tryParse(trimmed);
    setState(() {
      if (trimmed.isEmpty) {
        _lonError = null;
      } else if (lon == null) {
        _lonError = l10n.settingsCoordinateInvalid;
      } else if (lon < -180 || lon > 180) {
        _lonError = l10n.settingsLongitudeRange;
      } else {
        _lonError = null;
        ref.read(manualLongitudeProvider.notifier).set(lon);
      }
    });
  }

  /// Opens the shared full-screen map picker seeded with the current manual
  /// coordinates, then applies the tapped location to both fields/providers.
  Future<void> _pickOnMap(AppLocalizations l10n) async {
    final result = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute<LatLng>(
        builder:
            (_) => MapPickerScreen(
              initialLat: ref.read(manualLatitudeProvider),
              initialLon: ref.read(manualLongitudeProvider),
            ),
      ),
    );
    if (result != null && mounted) {
      _applyPair(result.latitude, result.longitude, l10n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Keep the fields in sync when the providers change from elsewhere
    // (e.g. a reset), but never stomp on the field the user is editing.
    ref.listen(manualLatitudeProvider, (_, next) {
      if (!_latFocus.hasFocus) {
        final formatted = _format(next);
        if (_latController.text != formatted) _latController.text = formatted;
      }
    });
    ref.listen(manualLongitudeProvider, (_, next) {
      if (!_lonFocus.hasFocus) {
        final formatted = _format(next);
        if (_lonController.text != formatted) _lonController.text = formatted;
      }
    });

    const keyboardType = TextInputType.numberWithOptions(
      decimal: true,
      signed: true,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleWithHelp(
            title: l10n.settingsManualCoordinates,
            helpBody: l10n.settingsHelpManualCoordinates,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _latController,
                  focusNode: _latFocus,
                  keyboardType: keyboardType,
                  textInputAction: TextInputAction.next,
                  onChanged: (v) => _onLatChanged(v, l10n),
                  decoration: InputDecoration(
                    labelText: l10n.settingsLatitude,
                    border: const OutlineInputBorder(),
                    errorText: _latError,
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lonController,
                  focusNode: _lonFocus,
                  keyboardType: keyboardType,
                  textInputAction: TextInputAction.done,
                  onChanged: (v) => _onLonChanged(v, l10n),
                  decoration: InputDecoration(
                    labelText: l10n.settingsLongitude,
                    border: const OutlineInputBorder(),
                    errorText: _lonError,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.settingsCoordinatesHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _pickOnMap(l10n),
              icon: const Icon(AppIcons.map, size: 18),
              label: Text(l10n.settingsPickOnMap),
            ),
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
    this.helpBody,
  });

  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: _TitleWithHelp(title: title, helpBody: helpBody),
      subtitle: Semantics(
        label: title,
        value: format(value),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: format(value),
          onChanged: onChanged,
        ),
      ),
      trailing: Text(
        format(value),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _DiscreteSliderTile<T> extends StatelessWidget {
  const _DiscreteSliderTile({
    required this.title,
    required this.value,
    required this.values,
    required this.format,
    required this.onChanged,
    this.helpBody,
  }) : assert(values.length > 1);

  final String title;
  final T value;
  final List<T> values;
  final String Function(T) format;
  final ValueChanged<T> onChanged;
  final String? helpBody;

  int get _selectedIndex {
    final index = values.indexOf(value);
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;
    final selectedValue = values[selectedIndex];
    return ListTile(
      title: _TitleWithHelp(title: title, helpBody: helpBody),
      subtitle: Semantics(
        label: title,
        value: format(selectedValue),
        child: Slider(
          value: selectedIndex.toDouble(),
          min: 0,
          max: (values.length - 1).toDouble(),
          divisions: values.length - 1,
          label: format(selectedValue),
          onChanged: (raw) {
            final rounded = raw.round();
            final index =
                rounded < 0
                    ? 0
                    : rounded >= values.length
                    ? values.length - 1
                    : rounded;
            onChanged(values[index]);
          },
        ),
      ),
      trailing: Text(
        format(selectedValue),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.helpBody,
  });

  final String title;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final String? subtitle;
  final String? helpBody;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: _TitleWithHelp(title: title, helpBody: helpBody),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        items:
            options.entries
                .map(
                  (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                )
                .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Variant of [_ChoiceTile] for color-map selection that shows a small
/// gradient swatch next to each option's label, both in the closed dropdown
/// and in the expanded menu.
class _ColorMapChoiceTile extends StatelessWidget {
  const _ColorMapChoiceTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.helpBody,
  });

  final String title;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final String? helpBody;

  /// Build a horizontal gradient strip from the named color map's LUT.
  Widget _swatch(String name, {double width = 56, double height = 14}) {
    final stops = List<double>.generate(11, (i) => i / 10);
    final colors =
        stops.map((s) => SpectrogramColorMap.color(name, s)).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors, stops: stops),
        ),
      ),
    );
  }

  Widget _row(String name, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_swatch(name), const SizedBox(width: 10), Text(label)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: _TitleWithHelp(title: title, helpBody: helpBody),
      trailing: DropdownButton<String>(
        value: value,
        underline: const SizedBox.shrink(),
        selectedItemBuilder:
            (_) =>
                options.entries
                    .map((e) => Center(child: _row(e.key, e.value)))
                    .toList(),
        items:
            options.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: _row(e.key, e.value),
                  ),
                )
                .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// Two-line auto-shrinking label for a [SegmentedButton] segment.
///
/// Some locales (notably German "Nur Detektionen" and French
/// "Détections uniquement") overflow the default single-line label when
/// three segments share the row. Allowing two lines plus a small
/// font-scale fallback keeps every locale legible without forcing tiny
/// fixed text everywhere.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      softWrap: true,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, height: 1.1),
    );
  }
}

// ---------------------------------------------------------------------------
// _GpsRefreshTile — manual "Refresh GPS now" entry in the Location section
// ---------------------------------------------------------------------------
//
// Forces the location service to fetch a fresh fix instead of using the
// FutureProvider-cached value. Useful when the user has moved since last
// open (the cached value can be miles away) or when they just want to
// verify the receiver is working.  We also surface the current cached
// coordinates as the subtitle so users can see at a glance what the app
// thinks their location is right now.
// ---------------------------------------------------------------------------

class _GpsRefreshTile extends ConsumerStatefulWidget {
  const _GpsRefreshTile();

  @override
  ConsumerState<_GpsRefreshTile> createState() => _GpsRefreshTileState();
}

class _GpsRefreshTileState extends ConsumerState<_GpsRefreshTile> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    try {
      ref.invalidate(currentLocationProvider);
      final location = await ref.read(currentLocationProvider.future);
      if (!mounted) return;
      final svc = ref.read(locationServiceProvider);
      final String message;
      if (location == null) {
        message = l10n.settingsGpsRefreshFailed;
      } else if (svc.lastFetchUsedCachedFallback) {
        message = l10n.gpsStaleWarning;
      } else {
        message = l10n.settingsGpsRefreshed;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.settingsGpsRefreshFailed),
            duration: const Duration(seconds: 3),
          ),
        );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final loc = ref.watch(currentLocationProvider).value;
    final subtitle =
        _refreshing
            ? l10n.settingsGpsRefreshing
            : loc == null
            ? l10n.settingsGpsRefreshSubtitle
            : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
    return ListTile(
      leading: const Icon(AppIcons.myLocation),
      title: Text(l10n.settingsGpsRefresh),
      subtitle: Text(subtitle),
      trailing:
          _refreshing
              ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
              : const Icon(AppIcons.refresh),
      onTap: _refreshing ? null : _refresh,
    );
  }
}
