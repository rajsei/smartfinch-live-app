// =============================================================================
// BadgeWatcher — noticing that something was earned (AUS-08)
// =============================================================================
//
// The badge rules live in `PointsRepository` and are derived from history on
// demand (`AUS-12`). That is the right shape for a screen you open, and the
// wrong shape for a celebration: nothing in a derived list says *when* a badge
// crossed from open to earned, and a card has to fire on exactly that moment.
//
// So this holds the last set it saw and reports the difference. Two properties
// are what make it worth its own file:
//
//   **It never fires twice for the same badge.** A badge that resets can be
//   earned again tomorrow, but within one session the set only grows, and a
//   rebuild that re-delivered it must not produce a second card.
//
//   **It throttles.** The rules read the whole score journal, and running them
//   after every bird would put a year of history through a query on the audio
//   thread's heels. A badge that lands twenty seconds late is still a
//   surprise — unlike a first find, which has to be immediate, which is why
//   that one is pushed by the score board instead of polled.
//
// Pure Dart with an injected clock, so both properties are testable without a
// database or a screen.
// =============================================================================

import 'package:meta/meta.dart';

import 'points_models.dart';

/// Reports badges that were not earned last time it looked.
class BadgeWatcher {
  BadgeWatcher({this.minimumInterval = const Duration(seconds: 20)});

  /// How long to wait between two derivations of the badge list.
  final Duration minimumInterval;

  final Set<String> _seen = {};

  DateTime? _lastLooked;

  /// Whether the caller should pay for another derivation now.
  ///
  /// The first call always says yes: the opening state of a session has to be
  /// established before any difference means anything.
  bool isDue(DateTime now) {
    final last = _lastLooked;
    if (last != null && now.difference(last) < minimumInterval) return false;
    _lastLooked = now;
    return true;
  }

  /// Badges in [earned] that were not there the last time it was called.
  ///
  /// ⚠️ The **first** call returns nothing, whatever it is handed. It is
  /// establishing what the child already had — a session that opened with
  /// forty badges must not begin with forty cards.
  List<BadgeDefinition> newlyEarned(List<EarnedBadge> earned) {
    final keys = {for (final badge in earned) badge.definition.key};

    if (!_primed) {
      _primed = true;
      _seen.addAll(keys);
      return const [];
    }

    final fresh = [
      for (final badge in earned)
        if (_seen.add(badge.definition.key)) badge.definition,
    ];

    // Loyalty badges are per species, so the same definition can arrive for a
    // second bird. One key, one card: the catalogue lists them by name, and
    // "Regular" twice in a row reads as a bug rather than as two birds.
    return fresh;
  }

  /// Whether the opening state has been recorded.
  @visibleForTesting
  bool get isPrimed => _primed;

  bool _primed = false;

  /// Forgets everything — a new session, or the screen going away.
  void reset() {
    _seen.clear();
    _primed = false;
    _lastLooked = null;
  }
}
