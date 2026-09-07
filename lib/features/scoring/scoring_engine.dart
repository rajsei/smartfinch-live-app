// =============================================================================
// ScoringEngine — chapter 2 of the specification, as code
// =============================================================================
//
// Pure Dart. No Flutter import, no database, no provider, no clock of its own:
// everything it needs arrives as an argument and everything it decides comes
// back as a value. The caller persists the result.
//
// That shape is deliberate and worth defending:
//
//   * **It is testable without a database.** The chapter 2 rule table becomes a
//     table-driven test rather than a fixture-heavy integration test, which is
//     what NFA-14 asks for.
//   * **It cannot write to the wrong table.** The engine *says* a life-list
//     entry is due; it never writes one. Writing that row too early burns a
//     species' first-find ×3 forever (DAT-11), so the decision and the write
//     being separate is a safety property, not architecture for its own sake.
//   * **It is deterministic** (NFA-06). Same inputs, same output, always — no
//     `DateTime.now()`, no random, no ambient state.
//
// ### What it does not do
//
// Badges and achievements (AUS-*), levels, and the day/week aggregates the
// statistics screen reads. Those derive from what this produces and belong
// above it.
// =============================================================================

import 'package:meta/meta.dart';

import '../../core/services/grid_cell.dart';
import '../inference/geo_abundance.dart';
import 'rarity_scale_provider.dart';
import 'scoring_rules.dart';

/// Why a detection did not score. Every value here means zero stars.
enum ScoringSkipReason {
  /// Scoring is paused: the species filter is off, or the confidence threshold
  /// is below the floor (PKT-20).
  ///
  /// The detection is still recorded and shown in the journal, flagged
  /// "outside scoring" (LOG-15) — nothing is lost, it simply did not count.
  scoringPaused,

  /// The species has no rarity tier here this week (2.3, D20).
  ///
  /// Not "off the list, therefore maximum points" — that rule was removed. No
  /// tier, no stars.
  notOnLocalList,

  /// Already scored today (PKT-03). The card shows "already collected today ✓"
  /// rather than a number, so the child is not left wondering (LIVE-03).
  alreadyScoredToday,

  /// No position, so no scale, so no tier. Should not occur after D18 put the
  /// home region in onboarding, but the engine must not invent a value.
  noLocation,

  /// Confidence below the applied threshold — not a detection the app shows.
  belowThreshold,
}

/// What the caller knows about a species before this detection.
///
/// Supplied by the caller (a database read) rather than looked up here, so the
/// engine stays pure and the queries stay in one place.
@immutable
class SpeciesHistory {
  const SpeciesHistory({
    this.isOnLifeList = false,
    this.isOnYearList = false,
    this.daysThisIsoWeekWithSpecies = 0,
    this.alreadyScoredToday = false,
  });

  /// Whether the species has **ever** been scored, on any day (PKT-04).
  final bool isOnLifeList;

  /// Whether it has been scored this calendar year (PKT-12).
  final bool isOnYearList;

  /// How many days of the current ISO week already have this species,
  /// **including today** (PKT-05, PKT-06).
  ///
  /// ISO week, Monday to Sunday — not the geo model's 1–48 week, which decides
  /// rarity. Two different calendars.
  final int daysThisIsoWeekWithSpecies;

  /// Whether this species already scored today (PKT-03).
  final bool alreadyScoredToday;
}

/// The conditions in force at the moment of a detection.
@immutable
class ScoringContext {
  const ScoringContext({
    required this.now,
    required this.appliedThreshold,
    required this.filterEnabled,
    this.scale,
    this.cell,
    this.rules = ScoringRules.current,
  });

  /// Detection time. Passed in rather than read, so tests can place a detection
  /// at 08:59 on a Sunday without waiting for one.
  final DateTime now;

  /// The confidence threshold in force, 0–100. Frozen into the event
  /// (PKT-15) — the slider stays adjustable through the MVP (D16), and without
  /// this the history's meaning would change whenever it moves.
  final int appliedThreshold;

  /// Whether the species filter is on (PKT-20).
  final bool filterEnabled;

  /// The shared rarity scale for this cell and week (DAT-10). Null when no
  /// scale is available yet.
  final RarityScale? scale;

  /// Coarsened cell the scale belongs to (NFA-08, D23).
  final GridCell? cell;

  final ScoringRules rules;

  /// Local calendar day, `YYYY-MM-DD` (DAT-05).
  ///
  /// Built from the local date, so a detection at 23:59 and one at 00:01 fall
  /// on different days exactly as a child would expect. Timezone and DST are
  /// the platform's `DateTime` to get right; the engine only formats.
  String get dayKey =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  /// Whether scoring is active at all (PKT-20).
  bool get isScoring => rules.isScoring(
        threshold: appliedThreshold,
        filterEnabled: filterEnabled,
      );
}

/// What the caller should do about one detection.
@immutable
class ScoringOutcome {
  const ScoringOutcome._({
    required this.stars,
    required this.dayKey,
    this.skipReason,
    this.tier,
    this.baseValue = 0,
    this.multiplier = ScoreMultiplier.none,
    this.geoWeek,
    this.gridCell,
    this.appliedThreshold = 0,
    this.ruleVersion = 0,
    this.addToLifeList = false,
    this.addToYearList = false,
  });

  /// Nothing scored, and why.
  factory ScoringOutcome.skipped(ScoringSkipReason reason, String dayKey) =>
      ScoringOutcome._(stars: 0, dayKey: dayKey, skipReason: reason);

  /// Stars awarded. Zero whenever [skipReason] is set.
  final int stars;

  final String dayKey;

  /// Null when the detection scored.
  final ScoringSkipReason? skipReason;

  /// True when this detection is worth a `ScoreEvent` row.
  bool get scored => skipReason == null;

  // ── Frozen fields, for the ScoreEvent (PKT-15) ───────────────────────────

  final ExploreTier? tier;
  final int baseValue;
  final ScoreMultiplier multiplier;
  final int? geoWeek;
  final GridCell? gridCell;
  final int appliedThreshold;
  final int ruleVersion;

  // ── What the caller should write, beyond the event ───────────────────────

  /// ⚠️ True when this is the species' first ever scoring detection.
  ///
  /// **Only write the life-list row when this is true.** A row written for a
  /// paused or unscored detection burns the ×3 for that species permanently,
  /// and nothing in the app could later explain why the child's real first find
  /// was worth 100 instead of 300 (DAT-11, principle 1).
  final bool addToLifeList;

  /// True when this is the species' first scoring detection this year
  /// (PKT-12).
  final bool addToYearList;

  /// One-line explanation for the detection card (PKT-16, principle 6).
  ///
  /// "100 base × 2 (Regular) = 200" — a child does check the maths, and if the
  /// numbers look arbitrary they stop trusting them.
  String get explanation {
    if (!scored) return '';
    if (multiplier == ScoreMultiplier.none) return '$baseValue';
    return '$baseValue × ${multiplier.factor} = $stars';
  }
}

/// A bonus that applies to a whole day rather than to one species (2.6).
@immutable
class DayBonus {
  const DayBonus({required this.key, required this.stars});

  final String key;
  final int stars;
}

/// Chapter 2, as a pure function.
class ScoringEngine {
  const ScoringEngine();

  /// Scores one detection.
  ///
  /// Called at the moment the species appears on screen — the first inference
  /// window that clears the threshold (D15), so the stars land at the same
  /// instant the bird does. The peak confidence is written back later by the
  /// caller when the detection record closes; it does not change the award.
  ScoringOutcome scoreDetection({
    required String scientificName,
    required double confidence,
    required ScoringContext context,
    required SpeciesHistory history,
  }) {
    final dayKey = context.dayKey;

    // Order matters: the most specific reason should win, so the journal can
    // say something true rather than merely correct.
    if (!context.isScoring) {
      return ScoringOutcome.skipped(ScoringSkipReason.scoringPaused, dayKey);
    }

    if (confidence * 100 < context.appliedThreshold) {
      return ScoringOutcome.skipped(ScoringSkipReason.belowThreshold, dayKey);
    }

    final scale = context.scale;
    if (scale == null || context.cell == null) {
      return ScoringOutcome.skipped(ScoringSkipReason.noLocation, dayKey);
    }

    final tier = scale.tierFor(scientificName);
    if (tier == null) {
      return ScoringOutcome.skipped(ScoringSkipReason.notOnLocalList, dayKey);
    }

    // Checked after the tier so a repeat of an off-list species still reports
    // the more informative reason.
    if (history.alreadyScoredToday) {
      return ScoringOutcome.skipped(
        ScoringSkipReason.alreadyScoredToday,
        dayKey,
      );
    }

    final rules = context.rules;
    final base = rules.starsFor(tier);
    final multiplier = rules.multiplierFor(
      isFirstFind: !history.isOnLifeList,
      isYearFirst: !history.isOnYearList,
      daysThisWeekWithSpecies: history.daysThisIsoWeekWithSpecies,
    );

    return ScoringOutcome._(
      stars: base * multiplier.factor,
      dayKey: dayKey,
      tier: tier,
      baseValue: base,
      multiplier: multiplier,
      geoWeek: scale.key.geoWeek,
      gridCell: context.cell,
      appliedThreshold: context.appliedThreshold,
      ruleVersion: rules.version,
      addToLifeList: !history.isOnLifeList,
      addToYearList: !history.isOnYearList,
    );
  }

  /// Day-level bonuses triggered by this detection (2.6).
  ///
  /// Returns only what is *newly* earned, so the caller can award and celebrate
  /// it once. [speciesCountBefore] is the day's distinct scoring species before
  /// this detection; [speciesCountAfter] includes it.
  ///
  /// Bonuses are added after the multiplier and are never themselves
  /// multiplied — the inflation guard.
  List<DayBonus> bonusesFor({
    required ScoringContext context,
    required int speciesCountBefore,
    required int speciesCountAfter,
    required bool earlyRiserAlreadyAwarded,
  }) {
    if (!context.isScoring) return const [];

    final rules = context.rules;
    final bonuses = <DayBonus>[];

    // Variety thresholds crossed by this detection. Cumulative by design: at
    // species 15 the day has earned 50 + 150 + 300, and each step is a visible
    // event rather than a silent recalculation.
    for (final entry in rules.varietyBonuses.entries) {
      final threshold = entry.key;
      if (speciesCountBefore < threshold && speciesCountAfter >= threshold) {
        bonuses.add(
          DayBonus(key: entry.value.key, stars: entry.value.stars),
        );
      }
    }

    // Once per day, not per species.
    if (!earlyRiserAlreadyAwarded &&
        rules.qualifiesAsEarlyRiser(context.now)) {
      bonuses.add(
        DayBonus(
          key: rules.earlyRiserBonus.key,
          stars: rules.earlyRiserBonus.stars,
        ),
      );
    }

    return bonuses;
  }
}
