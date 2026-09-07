// =============================================================================
// ScoringRules — the balancing, as data (DAT-04)
// =============================================================================
//
// Every number from chapter 2 of the specification lives here and nowhere else.
// Not because a config object is tidier, but because of what chapter 9 names as
// the central risk of the whole concept:
//
//   > **Balancing is wrong — too generous or too stingy.**
//   > Handling: DAT-03/DAT-04 — rules are versioned and retroactively
//   > recomputable. Balancing is a setting, not a rebuild.
//
// After four weeks with a real child it will turn out that the variety bonus
// fires too early or the loyalty multiplier is too strong. With the numbers
// scattered through the engine that is a rewrite; with them here it is an edit
// and a bumped [version].
//
// ### What `version` is for — and what it is not
//
// Every `ScoreEvent` records the version in force when it was awarded, so the
// history stays explainable ("this day was scored under rules v1").
//
// It is **not** a way to score old events under old rules. `recomputeAllScores`
// re-derives multipliers and bonuses under the *current* rules and never
// touches the frozen base value (PKT-15). That is the whole point: a rebalance
// should change the numbers, including retroactively, or badges earned under
// the old rules could never be recomputed (AUS-12).
//
// ### Priorities
//
// The table is complete; the engine implements it in priority order. A P1 or P2
// entry defined here costs nothing until something reads it, and having the
// number written down now is what makes the later step an edit rather than a
// design discussion.
// =============================================================================

import 'package:flutter/foundation.dart';

import '../inference/geo_abundance.dart';

/// Why a multiplier applied. Only one ever does — see [ScoringRules.multiplierFor].
enum ScoreMultiplier {
  /// Nothing special about this detection.
  none(1),

  /// M4 · Regular (`Stammgast`) — 3rd day this week featuring the species.
  /// PKT-05, P0.
  regular(2),

  /// M3 · Year first (`Jahresneuling`) — first time this calendar year.
  /// PKT-12, P1 (worth pulling into P0: after D20 the year list carries most
  /// of the seasonal story).
  yearFirst(2),

  /// M2 · Permanent guest (`Dauergast`) — 6th day this week. PKT-06, P1.
  permanentGuest(3),

  /// M1 · First find (`Erstfund`) — never detected before, ever. PKT-04, P0.
  ///
  /// ⚠️ Checked against the life list, and writing to that list too early
  /// burns this multiplier for the species permanently (DAT-11).
  firstFind(3);

  const ScoreMultiplier(this.factor);

  /// What the base value is multiplied by.
  final int factor;
}

/// An additive bonus. Applied **after** the multiplier and never itself
/// multiplied — that is the inflation guard (2.6).
@immutable
class ScoreBonus {
  const ScoreBonus({
    required this.key,
    required this.stars,
    required this.priority,
  });

  /// Stable identifier, also used as the badge key where one exists.
  final String key;

  final int stars;

  /// Specification priority, so the engine can implement in order.
  final String priority;
}

/// The complete balancing.
@immutable
class ScoringRules {
  const ScoringRules({
    required this.version,
    required this.starsByTier,
    required this.varietyBonuses,
    required this.earlyRiserBonus,
    required this.earlyRiserBefore,
    required this.newPlaceBonus,
    required this.weekWrapUpBonus,
    required this.weekWrapUpMinDays,
    required this.regularOnDay,
    required this.permanentGuestOnDay,
    required this.scoringThresholdFloor,
  });

  /// The rules in force. Bump [version] whenever a number below changes.
  static const ScoringRules current = ScoringRules(
    version: 1,

    // ── 2.3 · Levels to points ───────────────────────────────────────────
    //
    // "The commonest level is worth 50 stars, the rarest 1,000. Everything in
    // between is distributed geometrically." Six levels means a factor of 1.82
    // per step — 50 × 1.82⁵ ≈ 1000.
    //
    // ⚠️ **The order is the reverse of the specification's table.** `ExploreTier`
    // runs `rare` (index 0) → `abundant` (index 5), while 2.3 lists common
    // first. Getting this backwards would make every blackbird a sensation and
    // every hoopoe worthless, and both would look plausible in a debug print.
    starsByTier: {
      ExploreTier.rare: 1000,
      ExploreTier.scarce: 600,
      ExploreTier.uncommon: 350,
      ExploreTier.frequent: 200,
      ExploreTier.common: 100,
      ExploreTier.abundant: 50,
    },

    // ── 2.6 · Additive bonuses ───────────────────────────────────────────
    //
    // Cumulative: reaching 15 species yields 50 + 150 + 300 = 500. That is what
    // makes a day a staircase — something visibly happens at 5, 10 and 15.
    varietyBonuses: {
      5: ScoreBonus(key: 'variety_5', stars: 50, priority: 'P0'),
      10: ScoreBonus(key: 'variety_10', stars: 150, priority: 'P0'),
      15: ScoreBonus(key: 'variety_15', stars: 300, priority: 'P1'),
      20: ScoreBonus(key: 'variety_20', stars: 500, priority: 'P1'),
      25: ScoreBonus(key: 'variety_25', stars: 750, priority: 'P2'),
    },

    // 09:00, not 07:00: a reliable morning reward every walk to school earns,
    // rather than a feat that is unreachable on a school day. Kept small at +50
    // so its frequency is not inflationary.
    earlyRiserBonus: ScoreBonus(key: 'early_riser', stars: 50, priority: 'P1'),
    earlyRiserBefore: 9,

    newPlaceBonus: ScoreBonus(key: 'new_place', stars: 200, priority: 'P2'),

    weekWrapUpBonus: ScoreBonus(
      key: 'week_wrap_up',
      stars: 300,
      priority: 'P2',
    ),
    weekWrapUpMinDays: 4,

    // ── 2.5 · Loyalty ────────────────────────────────────────────────────
    //
    // The rising shape (1, 1, ×2, 1, 1, ×3, 1) builds towards the weekend
    // instead of peaking mid-week. Counted in ISO days, not geo weeks.
    regularOnDay: 3,
    permanentGuestOnDay: 6,

    // ── Scoring floor (PKT-20, gap D) ────────────────────────────────────
    //
    // The shipped default confidence threshold, which is also the floor: at or
    // above it the app scores, below it scoring pauses entirely. Deliberately
    // asymmetric — raising the threshold is always allowed, because a stricter
    // bar produces fewer and safer detections and cannot be abused.
    scoringThresholdFloor: 35,
  );

  /// Rule set version, recorded on every `ScoreEvent`.
  final int version;

  /// Star value per rarity tier (PKT-02).
  final Map<ExploreTier, int> starsByTier;

  /// Species-count threshold → bonus (PKT-08, PKT-09).
  final Map<int, ScoreBonus> varietyBonuses;

  final ScoreBonus earlyRiserBonus;

  /// Hour before which the early-riser bonus applies, local time.
  final int earlyRiserBefore;

  final ScoreBonus newPlaceBonus;
  final ScoreBonus weekWrapUpBonus;

  /// Days in an ISO week that must have a detection for the week wrap-up.
  final int weekWrapUpMinDays;

  /// ISO-week day count at which `Stammgast` applies.
  final int regularOnDay;

  /// ISO-week day count at which `Dauergast` applies.
  final int permanentGuestOnDay;

  /// Confidence below which nothing scores at all (PKT-20).
  final int scoringThresholdFloor;

  /// Base stars for a tier.
  ///
  /// A species with **no** tier scores nothing (2.3, D20) — that case is the
  /// caller's to handle, and it is deliberately not a value here: there is no
  /// "off-list" star amount to look up any more.
  int starsFor(ExploreTier tier) => starsByTier[tier]!;

  /// The one multiplier that applies (PKT-07).
  ///
  /// > **Multipliers do not multiply with each other. Only the highest one
  /// > applies.**
  ///
  /// Without this the maximum per species per day would be 1000 × 3 × 2 =
  /// 6,000 and the curve would come apart. With it the ceiling is ×3, the
  /// maximum is 3,000, and the rule fits in one sentence a child can hold:
  /// *the best bonus always wins*.
  ScoreMultiplier multiplierFor({
    required bool isFirstFind,
    required bool isYearFirst,
    required int daysThisWeekWithSpecies,
  }) {
    final applicable = <ScoreMultiplier>[
      if (isFirstFind) ScoreMultiplier.firstFind,
      if (isYearFirst) ScoreMultiplier.yearFirst,
      if (daysThisWeekWithSpecies == permanentGuestOnDay)
        ScoreMultiplier.permanentGuest,
      if (daysThisWeekWithSpecies == regularOnDay) ScoreMultiplier.regular,
    ];

    if (applicable.isEmpty) return ScoreMultiplier.none;
    return applicable.reduce((a, b) => a.factor >= b.factor ? a : b);
  }

  /// Total variety bonus for a day that reached [speciesCount] species.
  ///
  /// Cumulative, so 15 species yields every threshold up to 15.
  int varietyBonusFor(int speciesCount) {
    var total = 0;
    for (final entry in varietyBonuses.entries) {
      if (speciesCount >= entry.key) total += entry.value.stars;
    }
    return total;
  }

  /// Whether a detection at [when] earns the early-riser bonus (B6).
  ///
  /// Once per day, not per species — the caller enforces that.
  bool qualifiesAsEarlyRiser(DateTime when) => when.hour < earlyRiserBefore;

  /// Whether scoring is active at [threshold] with the species filter in
  /// [filterEnabled] (PKT-20).
  ///
  /// Both conditions must hold. Restoring either resumes scoring immediately —
  /// nothing is lost, it simply did not count while paused.
  bool isScoring({required int threshold, required bool filterEnabled}) =>
      filterEnabled && threshold >= scoringThresholdFloor;
}
