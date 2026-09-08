// =============================================================================
// SeasonHint — a phenology lesson in one sentence (PKT-17)
// =============================================================================
//
// The 48-week curve (`SAM-15`) shows a child *that* a species comes and goes.
// This says *what that means right now*: "🌱 Early! The blackcap is normally
// only here from April."
//
// ### What it is for, after D20
//
// It used to be a defence of a strange number — the off-list case could make a
// bird worth ten times its usual value, and something had to explain that. D20
// removed that case, so the swings it covers are smaller and the job changed:
// it is now **a phenology lesson**, and the best learning element the app has
// for the price of one sentence.
//
// ### The rule
//
// A species' *season* is the weeks where it reaches at least half its own
// annual peak. Within that season there is nothing to explain. Outside it,
// hearing one is genuinely notable, and the hint says which way round: the
// season is still coming (**early**) or has already passed (**late**).
//
// Comparing a species only against **itself** is what makes this work for a
// resident and a migrant alike. A blackbird is here all year, never reaches a
// season boundary, and never gets a hint — correctly, because there is nothing
// unusual about hearing one in February.
// =============================================================================

import 'package:meta/meta.dart';

/// Which side of its season a detection falls on.
enum SeasonPhase {
  /// The species' season has not started yet — an early arrival.
  early,

  /// Its season is over — a straggler, or one that stayed.
  late,
}

/// Why hearing this species now is worth remarking on (`PKT-17`).
@immutable
class SeasonHint {
  const SeasonHint({
    required this.phase,
    required this.seasonStartMonth,
    required this.seasonEndMonth,
  });

  final SeasonPhase phase;

  /// Calendar month, 1–12, the species' season normally begins in.
  final int seasonStartMonth;

  /// Calendar month, 1–12, it normally ends in.
  final int seasonEndMonth;

  /// The month a sentence should name: when it *starts*, if it has not yet;
  /// when it *ends*, if it is already over.
  int get relevantMonth =>
      phase == SeasonPhase.early ? seasonStartMonth : seasonEndMonth;
}

/// Fraction of its own annual peak a species must reach to count as in season.
///
/// Half is deliberately generous. A stricter bar would make the hint fire
/// through the shoulders of a long season — a swallow in August is not an
/// early swallow — and a hint that appears for four months is not a hint.
const double kInSeasonFraction = 0.5;

/// The hint for a species at [currentWeek], or null when there is nothing to
/// say.
///
/// [weeklyScores] is the geo model's 48-week curve for this species; only its
/// *shape* is used, so it does not matter whether it has been normalised.
/// [currentWeek] is the geo model's 1–48 week — **not** the ISO week.
SeasonHint? seasonHintFor({
  required List<double> weeklyScores,
  required int currentWeek,
}) {
  if (weeklyScores.length != 48) return null;

  final peak = weeklyScores.reduce((a, b) => a > b ? a : b);
  if (peak <= 0) return null;

  final threshold = peak * kInSeasonFraction;
  final inSeason = [
    for (var i = 0; i < 48; i++)
      if (weeklyScores[i] >= threshold) i,
  ];

  // A species that is always here, or one whose curve is too flat to have a
  // season, has nothing to explain.
  if (inSeason.isEmpty || inSeason.length >= 48) return null;

  final currentIndex = (currentWeek - 1).clamp(0, 47);
  if (weeklyScores[currentIndex] >= threshold) return null;

  // Distances around a 48-week circle. Whichever edge is nearer decides
  // whether the season is coming or gone.
  final forward = _weeksUntilNext(inSeason, currentIndex);
  final backward = _weeksSinceLast(inSeason, currentIndex);

  final start = _seasonStart(inSeason);
  final end = _seasonEnd(inSeason);

  return SeasonHint(
    phase: forward <= backward ? SeasonPhase.early : SeasonPhase.late,
    seasonStartMonth: monthOfGeoWeek(start + 1),
    seasonEndMonth: monthOfGeoWeek(end + 1),
  );
}

/// Calendar month for a geo week, 1–48 → 1–12.
///
/// The geo model divides the year into four weeks per month, so this is exact
/// rather than an approximation.
int monthOfGeoWeek(int week) => ((week - 1) ~/ 4).clamp(0, 11) + 1;

int _weeksUntilNext(List<int> inSeason, int from) {
  var best = 48;
  for (final week in inSeason) {
    final distance = (week - from + 48) % 48;
    if (distance < best) best = distance;
  }
  return best;
}

int _weeksSinceLast(List<int> inSeason, int from) {
  var best = 48;
  for (final week in inSeason) {
    final distance = (from - week + 48) % 48;
    if (distance < best) best = distance;
  }
  return best;
}

/// The first week of the season, following the gap round the year.
///
/// A season that wraps December into January — a winter visitor — has no
/// lowest index that means "start", so the start is the week whose *previous*
/// week is out of season.
int _seasonStart(List<int> inSeason) {
  final set = inSeason.toSet();
  for (final week in inSeason) {
    if (!set.contains((week - 1 + 48) % 48)) return week;
  }
  return inSeason.first;
}

int _seasonEnd(List<int> inSeason) {
  final set = inSeason.toSet();
  for (final week in inSeason) {
    if (!set.contains((week + 1) % 48)) return week;
  }
  return inSeason.last;
}
