// =============================================================================
// The Points overview, with a switchable window — STAT-04
// =============================================================================
//
// The pieces are tested apart: the bucketing in `chart_range_test.dart`, the
// bars and the switch in `daily_chart_test.dart`. What only shows up wired
// together is the reload.
//
// Changing the window rebuilds the whole overview — key figures, chart, badges
// and achievements come from one read — so without care a child tapping
// *Year* watches all three tabs blink to a spinner and back. The assertion
// below is that they do not.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/points/chart_range.dart';
import 'package:smartfinch/features/points/points_providers.dart';
import 'package:smartfinch/features/points/points_screen.dart';
import 'package:smartfinch/features/points/widgets/daily_chart.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  Future<ProviderContainer> pumpPoints(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    // Tall enough that the chart and the hint under it are built: the tab is a
    // `ListView`, and what is below the fold does not exist to a finder.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PointsScreen(),
        ),
      ),
    );
    // Bounded rather than `pumpAndSettle`: the avatar card and the overview
    // both read the database, and a settle here waits on whichever of them is
    // slowest to stop animating.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    return container;
  }

  testWidgets('the window starts on the month it was written for', (
    tester,
  ) async {
    final container = await pumpPoints(tester);

    expect(container.read(chartRangeProvider), ChartRange.month);
    expect(find.text('Stars per day'), findsOneWidget);
    expect(find.byType(ChartRangeSelector), findsOneWidget);
  });

  testWidgets('tapping a window changes it, and says so under the chart', (
    tester,
  ) async {
    final container = await pumpPoints(tester);

    await tester.tap(find.text('Year'));
    await tester.pump();

    expect(container.read(chartRangeProvider), ChartRange.year);
    expect(find.text('Tap a bar to open that day.'), findsOneWidget);
  });

  testWidgets('the chart does not blink to a spinner while it reloads', (
    tester,
  ) async {
    await pumpPoints(tester);

    await tester.tap(find.text('7 days'));
    // The very next frame, which is the one a child sees.
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DailyStarsChart), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(DailyStarsChart), findsOneWidget);
  });
}
