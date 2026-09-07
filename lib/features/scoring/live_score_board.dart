// =============================================================================
// LiveScoreBoard — what the live screen knows about today's scoring
// =============================================================================
//
// The detection list rebuilds on every inference cycle, so it cannot ask the
// database what a species earned: that would be a query per row per second.
// This holds the answers in memory instead, written once as each detection is
// scored and read synchronously by the cards.
//
// It is a **view of the day, not of the session**. A child who stops and starts
// listening three times before lunch has one day, and the blackbird from the
// first outing must still say "already collected today" in the third (LIVE-03).
// So the board is keyed by day and survives a session ending.
// =============================================================================

import 'package:flutter/foundation.dart';

import 'scoring_engine.dart';
import 'scoring_repository.dart';
import 'scoring_rules.dart';

/// What one species earned today, as far as the live screen needs to know.
@immutable
class LiveSpeciesScore {
  const LiveSpeciesScore({
    required this.stars,
    required this.multiplier,
    this.skipReason,
    this.isFirstFind = false,
  });

  /// Stars awarded for the species itself. Day bonuses are not included —
  /// they belong to the day, not to a card (2.6).
  final int stars;

  final ScoreMultiplier multiplier;

  /// Null when the detection scored.
  final ScoringSkipReason? skipReason;

  /// Whether this was the species' first ever scoring detection (PKT-04).
  final bool isFirstFind;

  bool get scored => skipReason == null;

  /// Whether the card should say "already collected today ✓" rather than a
  /// number (LIVE-03).
  ///
  /// Answers the question a child asks out loud — *why didn't I get
  /// anything?* — before they ask it.
  bool get isRepeat => skipReason == ScoringSkipReason.alreadyScoredToday;

  /// Whether a multiplier chip belongs on the card (LIVE-04).
  bool get hasMultiplier => scored && multiplier != ScoreMultiplier.none;
}

/// Today's running totals (LIVE-08).
@immutable
class DaySummary {
  const DaySummary({
    required this.dayKey,
    this.stars = 0,
    this.speciesCount = 0,
  });

  final String dayKey;

  /// Every star earned today, species awards and day bonuses alike.
  final int stars;

  /// Distinct species that scored today.
  final int speciesCount;

  DaySummary copyWith({int? stars, int? speciesCount}) => DaySummary(
    dayKey: dayKey,
    stars: stars ?? this.stars,
    speciesCount: speciesCount ?? this.speciesCount,
  );
}

/// The live screen's view of today's scoring.
@immutable
class LiveScoreBoardState {
  const LiveScoreBoardState({
    required this.summary,
    this.speciesScores = const {},
  });

  /// Empty state for [dayKey].
  factory LiveScoreBoardState.emptyFor(String dayKey) =>
      LiveScoreBoardState(summary: DaySummary(dayKey: dayKey));

  final DaySummary summary;

  /// Scientific name → what it earned today.
  final Map<String, LiveSpeciesScore> speciesScores;

  LiveSpeciesScore? scoreFor(String scientificName) =>
      speciesScores[scientificName];

  LiveScoreBoardState copyWith({
    DaySummary? summary,
    Map<String, LiveSpeciesScore>? speciesScores,
  }) => LiveScoreBoardState(
    summary: summary ?? this.summary,
    speciesScores: speciesScores ?? this.speciesScores,
  );
}

/// Holds [LiveScoreBoardState] and folds each scored detection into it.
///
/// Deliberately not a database read on every change: the totals are derived
/// from what the repository just returned, and [reloadFrom] rebuilds them from
/// disk when a session starts or the day rolls over.
class LiveScoreBoard extends ChangeNotifier {
  LiveScoreBoard(this._state);

  factory LiveScoreBoard.forDay(String dayKey) =>
      LiveScoreBoard(LiveScoreBoardState.emptyFor(dayKey));

  LiveScoreBoardState _state;
  LiveScoreBoardState get state => _state;

  /// Species whose first find has not been celebrated yet.
  ///
  /// Read and cleared by the celebration queue (LIVE-07), so a first find is
  /// celebrated once even if the card rebuilds twenty times.
  final List<String> pendingCelebrations = [];

  /// Replaces everything with what the database says about [dayKey].
  ///
  /// Called when a session starts, so a second outing on the same day opens
  /// with the morning's total rather than at zero.
  Future<void> reloadFrom(ScoringRepository repository, String dayKey) async {
    final summary = await repository.summaryFor(dayKey);
    final scored = await repository.speciesScoredOn(dayKey);

    _state = LiveScoreBoardState(
      summary: summary,
      speciesScores: {
        for (final entry in scored.entries)
          entry.key: LiveSpeciesScore(
            stars: entry.value,
            multiplier: ScoreMultiplier.none,
            // Everything reloaded already scored earlier today, so anything
            // heard again now is a repeat.
            skipReason: ScoringSkipReason.alreadyScoredToday,
          ),
      },
    );
    pendingCelebrations.clear();
    notifyListeners();
  }

  /// Folds one recorded detection into the board.
  void record(String scientificName, RecordedDetection result) {
    final outcome = result.outcome;

    // A day rollover mid-session: start the new day clean rather than adding
    // today's stars to yesterday's total.
    if (outcome.dayKey != _state.summary.dayKey) {
      _state = LiveScoreBoardState.emptyFor(outcome.dayKey);
      pendingCelebrations.clear();
    }

    final existing = _state.scoreFor(scientificName);

    // A repeat must never overwrite what the species actually earned. The card
    // keeps showing the award and adds the ✓ (LIVE-03).
    final score =
        outcome.scored
            ? LiveSpeciesScore(
              stars: outcome.stars,
              multiplier: outcome.multiplier,
              isFirstFind: outcome.addToLifeList,
            )
            : LiveSpeciesScore(
              stars: existing?.stars ?? 0,
              multiplier: existing?.multiplier ?? ScoreMultiplier.none,
              skipReason: outcome.skipReason,
              isFirstFind: existing?.isFirstFind ?? false,
            );

    final summary =
        outcome.scored
            ? _state.summary.copyWith(
              stars: _state.summary.stars + result.starsAwarded,
              speciesCount: _state.summary.speciesCount + 1,
            )
            : _state.summary;

    _state = _state.copyWith(
      summary: summary,
      speciesScores: {..._state.speciesScores, scientificName: score},
    );

    if (outcome.scored && outcome.addToLifeList) {
      pendingCelebrations.add(scientificName);
    }

    notifyListeners();
  }

  /// Takes every species waiting to be celebrated and clears the queue.
  List<String> takePendingCelebrations() {
    if (pendingCelebrations.isEmpty) return const [];
    final taken = List<String>.from(pendingCelebrations);
    pendingCelebrations.clear();
    return taken;
  }
}
