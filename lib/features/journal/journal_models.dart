// =============================================================================
// Journal models — a day, and what happened in it
// =============================================================================
//
// `LOG-01` is the core rebuild: the app stops being organised by *recording*
// and starts being organised by *day*. A child who listened for ten minutes
// before school and forty in the park has had one day, not two sessions, and
// nothing in the journal should suggest otherwise.
//
// Sessions survive in the data model — they are what a detection belongs to
// and what carries a place name — but they are no longer a level of navigation.
//
// ### Two kinds of species on a day
//
// The split runs through every model here. A species either **scored** (it has
// a `DaySpecies` row, points, a multiplier) or it was heard **outside
// scoring** (`LOG-15`, `PKT-20`) — recorded, kept, listed, and worth nothing.
// Keeping them apart in the data rather than in the UI is what stops a day
// total quietly including recordings that never counted.
// =============================================================================

import 'package:meta/meta.dart';

import '../scoring/scoring_rules.dart';

/// One row in the day list (`LOG-02`).
@immutable
class JournalDay {
  const JournalDay({
    required this.dayKey,
    required this.date,
    this.stars = 0,
    this.speciesPreview = const [],
    this.speciesCount = 0,
    this.unscoredSpeciesCount = 0,
    this.placeNames = const [],
  });

  /// `YYYY-MM-DD` (DAT-05).
  final String dayKey;

  /// The same day as a `DateTime`, for formatting.
  final DateTime date;

  /// Every star earned that day, species awards and day bonuses alike.
  final int stars;

  /// A few scientific names for the card, richest first.
  final List<String> speciesPreview;

  /// Distinct species that scored.
  final int speciesCount;

  /// Species heard that day that scored nothing at all (`LOG-15`).
  ///
  /// Counted separately rather than folded into [speciesCount], so the day
  /// total stays honest: "8 species · ⭐ 450" with "3 more outside scoring"
  /// underneath.
  final int unscoredSpeciesCount;

  /// What the child called the places they listened in (`LOG-13`).
  ///
  /// Stays on the device and never reaches the shared day image (`KID-07`).
  final List<String> placeNames;

  /// Whether anything at all happened on this day.
  bool get isEmpty => speciesCount == 0 && unscoredSpeciesCount == 0;
}

/// How far the journal zooms out (`LOG-04`).
///
/// Days are what a child remembers; the wider levels are what makes a full
/// year navigable once the day list is three hundred entries long. `LOG-06`
/// will eventually pick the starting level from how much data there is; until
/// then it opens on days, which is the one a child recognises.
enum JournalPeriod {
  day,
  week,
  month,
  year;

  /// The level one step in — what tapping a card opens.
  ///
  /// Days are the floor: a day opens its detail, not another list.
  JournalPeriod? get deeper => switch (this) {
    JournalPeriod.year => JournalPeriod.month,
    JournalPeriod.month => JournalPeriod.week,
    JournalPeriod.week => JournalPeriod.day,
    JournalPeriod.day => null,
  };
}

/// What the journal is showing: one level, optionally narrowed to one span.
///
/// Narrowing is what tapping a card does (`LOG-04`). Tapping 2026 does not
/// scroll the month list to 2026 — it *becomes* the month list of 2026, which
/// is both what the child meant and the only version that works: the lists are
/// capped, so a March week is not reachable by scrolling a 60-day list at all.
///
/// The span is a half-open range, and a bucket belongs to it if it **overlaps**
/// rather than sits inside. An ISO week straddling the turn of the month would
/// otherwise be reachable through April and invisible in May, taking the first
/// three days of May with it.
@immutable
class JournalScope {
  const JournalScope(this.period) : start = null, end = null;

  const JournalScope.within(
    this.period, {
    required DateTime this.start,
    required DateTime this.end,
  });

  final JournalPeriod period;

  /// First day of the span, inclusive. Null means the whole journal.
  final DateTime? start;

  /// First day *after* the span, exclusive.
  final DateTime? end;

  bool get isNarrowed => start != null;

  @override
  bool operator ==(Object other) =>
      other is JournalScope &&
      other.period == period &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(period, start, end);

  @override
  String toString() =>
      isNarrowed
          ? 'JournalScope(${period.name}, $start–$end)'
          : 'JournalScope(${period.name})';
}

/// One week, month or year of the journal (`LOG-04`).
@immutable
class JournalBucket {
  const JournalBucket({
    required this.period,
    required this.start,
    required this.end,
    this.stars = 0,
    this.speciesCount = 0,
    this.newSpeciesCount = 0,
    this.activeDays = 0,
  });

  final JournalPeriod period;

  /// First day of the bucket, inclusive.
  final DateTime start;

  /// First day *after* the bucket. Exclusive, so ranges tile without gaps.
  final DateTime end;

  final int stars;

  /// Distinct species that scored anywhere in the bucket.
  ///
  /// Counted across the whole span rather than summed per day: a blackbird
  /// heard on five days of a week is one species that week, and adding the
  /// days would turn a quiet week into a busy-looking one.
  final int speciesCount;

  /// Species that entered the **life list** inside this bucket.
  ///
  /// The number a child actually looks for when zoomed out — a month with
  /// four first finds was a different month from one with none, however
  /// similar the star totals.
  final int newSpeciesCount;

  /// Days in the bucket that produced at least one scoring detection.
  final int activeDays;

  bool get isEmpty => speciesCount == 0 && stars == 0;
}

/// One species within a day (`LOG-03`).
@immutable
class JournalSpecies {
  const JournalSpecies({
    required this.scientificName,
    required this.firstHeardAt,
    this.stars = 0,
    this.multiplier = ScoreMultiplier.none,
    this.detectionCount = 1,
    this.isNew = false,
    this.scored = true,
    this.peakConfidence,
  });

  final String scientificName;

  /// When it was first heard that day — the moment it scored, if it did (D15).
  final DateTime firstHeardAt;

  /// Stars this species earned that day. Zero when it did not score.
  final int stars;

  /// The one multiplier that applied (`PKT-07`).
  final ScoreMultiplier multiplier;

  /// How many times it was heard that day. Only the first one scored.
  final int detectionCount;

  /// ⚠️ First time ever, not first time today (`LOG-09`).
  ///
  /// True only when this day is the one the species entered the life list, so
  /// the "✨ NEW" marker means what it says however often the day is reopened.
  final bool isNew;

  /// False when the species was only ever heard outside scoring (`LOG-15`).
  final bool scored;

  /// Highest confidence reached, written back when the detection closed (D15).
  final double? peakConfidence;

  bool get hasMultiplier => scored && multiplier != ScoreMultiplier.none;
}

/// Everything a day-detail screen shows (`LOG-03`, `LOG-09`, `LOG-15`).
@immutable
class JournalDayDetail {
  const JournalDayDetail({
    required this.day,
    this.scored = const [],
    this.outsideScoring = const [],
    this.bonuses = const [],
  });

  final JournalDay day;

  /// Species that earned stars, richest first.
  final List<JournalSpecies> scored;

  /// Species heard while scoring was paused (`LOG-15`).
  ///
  /// A separate list rather than a flag on one list, so a screen cannot
  /// accidentally total them in.
  final List<JournalSpecies> outsideScoring;

  /// Day-level bonuses (2.6) — variety, early riser. They belong to the day
  /// rather than to any species, which is why they are not in [scored].
  final List<JournalBonus> bonuses;

  bool get hasOutsideScoring => outsideScoring.isNotEmpty;
}

/// One day-level bonus, for the day detail.
@immutable
class JournalBonus {
  const JournalBonus({required this.key, required this.stars});

  /// Stable identifier, e.g. `variety_5` or `early_riser`.
  final String key;

  final int stars;
}
