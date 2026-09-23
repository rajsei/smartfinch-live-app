// =============================================================================
// What is stopping the stars right now
// =============================================================================
//
// One answer, read by every place that has to give it: the live screen's day
// bar, and the settings screen that highlights the switch responsible. Two
// places working it out separately is how they end up disagreeing — the bar
// saying "no location" while the settings highlight nothing.
//
// ### The three things, and why exactly these
//
//   * **The species filter is off** and **the confidence threshold is below
//     the floor** are the two that pause scoring outright (PKT-20). Both are
//     settings an adult changed.
//   * **No location** is not a pause in the engine's sense — the engine calls
//     it `noLocation` and records the bird anyway — but to a child it is the
//     same thing: a bird on the screen and nothing for it. Leaving it out is
//     how a session could run for twenty minutes without a star and without a
//     word about why.
//
// A GPS fix that is still on its way is not "no location". The provider is
// loading, not empty, and flashing a warning for the two seconds a fix takes
// would teach a child that the warning is noise.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../shared/providers/settings_providers.dart';
import '../explore/explore_providers.dart';
import 'scoring_rules.dart';

/// One reason there are no stars at the moment.
enum ScoringBlocker {
  /// The species filter is off — scoring is paused (PKT-20).
  speciesFilterOff,

  /// The confidence threshold is below the scoring floor (PKT-11, PKT-20).
  thresholdBelowFloor,

  /// No position: without one there is no rarity scale and no stars (SET-09).
  noLocation;

  /// Whether the fix lives on the advanced settings page rather than the
  /// plain one.
  bool get isAdvancedSetting => this != ScoringBlocker.noLocation;
}

/// Everything currently standing between a detection and its stars.
///
/// Empty when scoring works. Ordered by where the fix is: the plain page's
/// location first, then the advanced page's two switches.
final scoringBlockersProvider = Provider<List<ScoringBlocker>>((ref) {
  final location = ref.watch(currentLocationProvider);
  final noLocation = location.when(
    data: (value) => value == null,
    error: (_, _) => true,
    loading: () => false,
  );

  return [
    if (noLocation) ScoringBlocker.noLocation,
    if (ref.watch(speciesFilterModeProvider) == 'off')
      ScoringBlocker.speciesFilterOff,
    if (ref.watch(confidenceThresholdProvider) <
        ScoringRules.current.scoringThresholdFloor)
      ScoringBlocker.thresholdBelowFloor,
  ];
});

/// One reason, in the words the live bar and the settings screen share.
String blockerReason(AppLocalizations l10n, ScoringBlocker blocker) =>
    switch (blocker) {
      ScoringBlocker.speciesFilterOff => l10n.liveBlockerFilterOff,
      ScoringBlocker.thresholdBelowFloor => l10n.liveBlockerThresholdLow(
        ScoringRules.current.scoringThresholdFloor,
      ),
      ScoringBlocker.noLocation => l10n.liveBlockerNoLocation,
    };
