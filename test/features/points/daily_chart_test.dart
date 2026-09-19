// =============================================================================
// The chart as a way in — STAT-03, STAT-04
// =============================================================================
//
// The bucketing is tested in `chart_range_test.dart`, without a widget. What
// is left here needs one:
//
//   **A bar opens its day.** That is the whole of `STAT-03`, and it is the
//   only place in the app where a number turns back into the afternoon that
//   produced it.
//
//   **An empty column does not.** A day with nothing on it has no journal
//   entry, and a child who aims at a gap should get nothing rather than a
//   blank screen. The rule is a null `dayKey`; this is the proof that the
//   widget honours it.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/journal/journal_day_screen.dart';
import 'package:smartfinch/features/points/chart_range.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/features/points/widgets/daily_chart.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

void main() {
  /// Three days: one with stars, one empty, one with stars.
  final days = [
    for (var i = 0; i < 3; i++)
      () {
        final date = DateTime(2026, 3, 13 + i);
        return DayStars(
          dayKey: dayKeyFor(date),
          date: date,
          stars: i == 1 ? 0 : 40 + i,
        );
      }(),
  ];

  /// The label the widget gives a bar, which is also how a test finds one.
  String barLabel(DayStars day) =>
      '${DateFormat.yMMMd('en').format(day.date)}: ${day.stars} stars';

  Future<SemanticsHandle> pumpChart(
    WidgetTester tester, {
    ChartRange range = ChartRange.month,
  }) async {
    // Disposed by each test rather than in a tear-down: the framework checks
    // for live handles before tear-downs run.
    final handle = tester.ensureSemantics();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DailyStarsChart(days: days, peak: 42, range: range),
          ),
        ),
      ),
    );
    await tester.pump();
    return handle;
  }

  group('STAT-03 · a bar is a way into the day', () {
    testWidgets('tapping one opens that day in the journal', (tester) async {
      final handle = await pumpChart(tester);

      await tester.tap(find.bySemanticsLabel(barLabel(days.first)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final screen = tester.widget<JournalDayScreen>(
        find.byType(JournalDayScreen),
      );
      expect(screen.dayKey, days.first.dayKey);
      handle.dispose();
    });

    testWidgets('an empty column is not a button at all', (tester) async {
      final handle = await pumpChart(tester);

      // Two bars carry stars; the gap between them carries no label, because
      // it carries no day to open.
      expect(find.bySemanticsLabel(barLabel(days[0])), findsOneWidget);
      expect(find.bySemanticsLabel(barLabel(days[2])), findsOneWidget);
      expect(find.bySemanticsLabel(barLabel(days[1])), findsNothing);
      handle.dispose();
    });

    testWidgets('the empty day is still drawn, though', (tester) async {
      // STAT-02: it is a column, not an omission — five scattered days must
      // not draw the same shape as five in a row.
      final handle = await pumpChart(tester);

      expect(find.byType(Expanded), findsNWidgets(days.length));
      handle.dispose();
    });
  });

  group('STAT-04 · the range switch', () {
    testWidgets('offers the three windows and reports the choice', (
      tester,
    ) async {
      ChartRange? chosen;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ChartRangeSelector(
              range: ChartRange.month,
              onChanged: (range) => chosen = range,
            ),
          ),
        ),
      );

      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      expect(find.text('Year'), findsOneWidget);

      await tester.tap(find.text('Year'));
      await tester.pump();

      expect(chosen, ChartRange.year);
    });

    testWidgets('a year draws fewer columns than it has days', (tester) async {
      // Three days is less than a week, so they collapse into a single
      // column — 365 one-pixel bars would be unreadable and untappable.
      final handle = await pumpChart(tester, range: ChartRange.year);

      expect(find.byType(Expanded), findsOneWidget);
      handle.dispose();
    });
  });
}
