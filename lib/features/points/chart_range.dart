// =============================================================================
// How far the chart looks back (STAT-04) — and what a bar means there
// =============================================================================
//
// Seven days, thirty, or a year. The first two are one bar per day, which is
// what `STAT-02` is about: *days without activity are shown as an empty
// column, not omitted*, because omitting them lets five scattered days draw
// the same shape as five in a row.
//
// ### A year is not 365 bars
//
// It could be — the arithmetic is the same — and on a 360-pixel phone each one
// would be a single pixel. That breaks two things at once: nobody can read an
// individual day, and `STAT-03`'s tap-a-bar-to-open-that-day has no target.
//
// So a year is **52 weekly columns**, and the gap principle survives intact: a
// week nobody went out is still an empty column, it is just a wider one. A tap
// resolves to the first day of that week that produced something, which is the
// day a child was actually asking about.
// =============================================================================

import 'package:meta/meta.dart';

import '../scoring/scoring_repository.dart';
import 'points_models.dart';

/// The three windows `STAT-04` offers.
enum ChartRange {
  week(7),
  month(30),
  year(365);

  const ChartRange(this.days);

  /// How far back the repository reads.
  final int days;

  /// Whether a bar stands for a week rather than a day.
  bool get isBucketed => this == ChartRange.year;
}

/// One column of the chart: a day, or a week of them.
@immutable
class ChartColumn {
  const ChartColumn({
    required this.stars,
    required this.date,
    this.dayKey,
    this.spansDays = 1,
  });

  final int stars;

  /// The day the column starts on — what its label reads.
  final DateTime date;

  /// Where a tap goes (`STAT-03`), or null when there is nothing to open.
  ///
  /// For a daily column that is its own day; for a weekly one it is the first
  /// day in the week that produced something. Null for an empty column, which
  /// is what makes it untappable — a tap that lands on a blank day screen is
  /// a dead end, and a child should not be able to reach one by aiming at a
  /// gap.
  final String? dayKey;

  final int spansDays;

  bool get isEmpty => stars == 0;
}

/// Turns the repository's per-day list into the columns [range] draws.
///
/// Pure, so the bucketing can be tested without a database or a widget — and
/// it is the part most likely to be quietly wrong, because an off-by-one in
/// the grouping shifts every column by a day and nothing looks broken.
List<ChartColumn> columnsFor(List<DayStars> days, ChartRange range) {
  if (!range.isBucketed) {
    return [
      for (final day in days)
        ChartColumn(
          stars: day.stars,
          date: day.date,
          dayKey: day.isEmpty ? null : day.dayKey,
        ),
    ];
  }

  final columns = <ChartColumn>[];
  var index = 0;

  while (index < days.length) {
    // Aligned to ISO weeks rather than to a rolling seven from today, so the
    // columns line up with the weeks `PKT-05` and the journal already count.
    final start = startOfIsoWeek(days[index].date);
    final end = start.add(const Duration(days: 7));

    var stars = 0;
    String? firstActive;
    var span = 0;

    while (index < days.length && days[index].date.isBefore(end)) {
      final day = days[index];
      stars += day.stars;
      if (!day.isEmpty) firstActive ??= day.dayKey;
      span++;
      index++;
    }

    columns.add(
      ChartColumn(
        stars: stars,
        date: start,
        dayKey: firstActive,
        spansDays: span,
      ),
    );
  }

  return columns;
}
