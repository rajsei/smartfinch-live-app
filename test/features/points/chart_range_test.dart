// =============================================================================
// The chart's windows, and what a tap on one can reach (STAT-03, STAT-04)
// =============================================================================
//
// Two things are worth a test here and the rest is drawing:
//
//   **The bucketing.** An off-by-one in the weekly grouping shifts every
//   column of the year view by a day and nothing looks broken — the chart is
//   still a plausible chart, it is just describing different days.
//
//   **Which columns are reachable.** `STAT-03` sends a tap to a journal day,
//   and a day with nothing in it has no journal entry. The rule that keeps a
//   child out of a blank screen is a null `dayKey`, so it is asserted directly
//   rather than through a widget.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfinch/features/points/chart_range.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';

/// A run of days ending on [last], oldest first, with [stars] by index.
List<DayStars> _days(DateTime last, List<int> stars) {
  final first = last.subtract(Duration(days: stars.length - 1));
  return [
    for (var i = 0; i < stars.length; i++)
      () {
        final date = DateTime(first.year, first.month, first.day + i);
        return DayStars(dayKey: dayKeyFor(date), date: date, stars: stars[i]);
      }(),
  ];
}

void main() {
  group('ChartRange', () {
    test('only the year is drawn as buckets', () {
      expect(ChartRange.week.isBucketed, isFalse);
      expect(ChartRange.month.isBucketed, isFalse);
      expect(ChartRange.year.isBucketed, isTrue);
    });

    test('the windows are the three STAT-04 names', () {
      expect(ChartRange.week.days, 7);
      expect(ChartRange.month.days, 30);
      expect(ChartRange.year.days, 365);
    });
  });

  group('columnsFor, day by day', () {
    test('keeps one column per day, including the empty ones', () {
      final days = _days(DateTime(2026, 3, 15), [4, 0, 0, 9, 0, 0, 2]);

      final columns = columnsFor(days, ChartRange.week);

      expect(columns, hasLength(7));
      expect(columns.map((c) => c.stars), [4, 0, 0, 9, 0, 0, 2]);
    });

    test('an empty day carries no day key, so it cannot be tapped', () {
      final days = _days(DateTime(2026, 3, 15), [4, 0, 2]);

      final columns = columnsFor(days, ChartRange.month);

      expect(columns[0].dayKey, days[0].dayKey);
      expect(columns[1].dayKey, isNull);
      expect(columns[2].dayKey, days[2].dayKey);
    });
  });

  group('columnsFor, bucketed into weeks', () {
    test('groups a year into ISO weeks and sums each one', () {
      // A Monday, so the first column is a whole week rather than a stub.
      final start = DateTime(2026, 1, 5);
      expect(start.weekday, DateTime.monday);

      final days = [
        for (var i = 0; i < 21; i++)
          () {
            final date = DateTime(2026, 1, 5 + i);
            // 1 star on every day of week one, 2 on week two, 3 on week three.
            return DayStars(
              dayKey: dayKeyFor(date),
              date: date,
              stars: (i ~/ 7) + 1,
            );
          }(),
      ];

      final columns = columnsFor(days, ChartRange.year);

      expect(columns, hasLength(3));
      expect(columns.map((c) => c.stars), [7, 14, 21]);
      expect(columns.map((c) => c.spansDays), [7, 7, 7]);
      expect(columns.first.date, DateTime(2026, 1, 5));
    });

    test('a window starting mid-week keeps its short first column', () {
      // Thursday: three days to the end of that ISO week, then a full one.
      final days = _days(DateTime(2026, 1, 11), [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]);
      expect(days.first.date.weekday, DateTime.friday);

      final columns = columnsFor(days, ChartRange.year);

      expect(columns, hasLength(2));
      expect(columns.first.spansDays, 3, reason: 'Friday to Sunday');
      expect(columns.last.spansDays, 7);
    });

    test('a tap on a week lands on the first day that produced something', () {
      // Saturday first, so the window opens on the tail of the week before.
      final days = _days(DateTime(2026, 1, 9), [0, 0, 5, 0, 0, 0, 0]);
      final monday = days[2];
      expect(monday.date.weekday, DateTime.monday);

      // Monday opens its own week; the two days before it are the tail of the
      // week before, which produced nothing at all.
      final columns = columnsFor(days, ChartRange.year);

      expect(columns.first.dayKey, isNull);
      expect(columns.last.dayKey, monday.dayKey);
    });

    test('a week nobody went out is an empty column, not a missing one', () {
      final days = _days(DateTime(2026, 1, 25), [
        // Three ISO weeks, the middle one silent.
        ...List.filled(7, 3),
        ...List.filled(7, 0),
        ...List.filled(7, 3),
      ]);

      final columns = columnsFor(days, ChartRange.year);

      expect(columns, hasLength(3));
      expect(columns[1].isEmpty, isTrue);
      expect(columns[1].dayKey, isNull);
    });
  });
}
