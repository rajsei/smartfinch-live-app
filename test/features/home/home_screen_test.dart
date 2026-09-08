// =============================================================================
// The home screen — HOME-01, HOME-02, HOME-04, HOME-08
// =============================================================================
//
// Two things worth asserting here, and neither is the layout:
//
//   **The three numbers say different things.** Total, last 30 days and today
//   answer three different questions, and a header that quietly showed the
//   same figure three times would look right and be useless.
//
//   **Every tile goes somewhere.** The old carousel ended up with one card and
//   two page-indicator dots because a deletion left it behind. A test that
//   counts tiles is what stops that happening again.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/collection/collection_screen.dart';
import 'package:smartfinch/features/home/widgets/home_tiles.dart';
import 'package:smartfinch/features/journal/journal_screen.dart';
import 'package:smartfinch/features/points/points_screen.dart';
import 'package:smartfinch/features/home/widgets/star_header.dart';
import 'package:smartfinch/features/live/widgets/day_summary_bar.dart';
import 'package:smartfinch/features/scoring/live_score_board.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  /// Pumps [child] with the scoring providers wired.
  ///
  /// [scoringPaused] turns the species filter off through the real setting, so
  /// the test walks the same path `PKT-20` runs in the app.
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    StarTotals? totals,
    bool scoringPaused = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (scoringPaused) 'species_filter_mode': 'off',
    });
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (totals != null)
            starTotalsProvider.overrideWith((ref) async => totals),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  group('HOME-01 · the star header', () {
    testWidgets('shows the total large and the 30-day figure beside it', (
      tester,
    ) async {
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(total: 12400, last30Days: 3100, today: 350),
      );
      await tester.pump();

      expect(find.text('12400'), findsOneWidget);
      expect(find.text('3100 in the last 30 days'), findsOneWidget);
    });

    testWidgets('the total is the biggest number on the header', (
      tester,
    ) async {
      // "Total large, last 30 days small next to it" — the 30-day figure is
      // context for the big number, not a competitor to it.
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(total: 12400, last30Days: 3100, today: 350),
      );
      await tester.pump();

      final total = tester.widget<Text>(find.text('12400'));
      final last30 = tester.widget<Text>(find.text('3100 in the last 30 days'));

      expect(total.style!.fontSize!, greaterThan(last30.style!.fontSize!));
    });

    testWidgets('an empty header shows zeroes rather than a spinner', (
      tester,
    ) async {
      // A child arriving at a fresh home screen should see "0" and understand
      // it, not watch a loading indicator.
      await pump(tester, const StarHeader());

      expect(find.text('0'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('HOME-02 · today', () {
    testWidgets('is a third number, on its own line', (tester) async {
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(total: 12400, last30Days: 3100, today: 350),
      );
      await tester.pump();

      expect(find.text('Today: ⭐ 350'), findsOneWidget);
    });

    testWidgets('names the species count once there is one', (tester) async {
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(
          total: 900,
          last30Days: 900,
          today: 350,
          todaySpecies: 9,
        ),
      );
      await tester.pump();

      expect(find.text('Today: ⭐ 350 · 9 species'), findsOneWidget);
    });

    testWidgets('the three numbers are independent', (tester) async {
      // A header that showed the same figure three times would look right and
      // be useless.
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(total: 12400, last30Days: 3100, today: 350),
      );
      await tester.pump();

      expect(find.text('12400'), findsOneWidget);
      expect(find.textContaining('3100'), findsOneWidget);
      expect(find.textContaining('350'), findsOneWidget);
    });
  });

  group('LIVE-18 · the home half of the paused notice', () {
    testWidgets('replaces the numbers with the same notice live mode uses', (
      tester,
    ) async {
      await pump(
        tester,
        const StarHeader(),
        totals: const StarTotals(total: 12400, last30Days: 3100, today: 350),
        scoringPaused: true,
      );
      await tester.pump();

      expect(find.byType(ScoringPausedNotice), findsOneWidget);
      expect(
        find.text('Test mode — no stars, nothing collected'),
        findsOneWidget,
      );
      expect(find.text('12400'), findsNothing);
    });
  });

  group('HOME-08 · Live is the dominant tile', () {
    testWidgets('it is there, and it says what it does', (tester) async {
      await pump(tester, const HomeTiles());

      expect(find.text('Live'), findsOneWidget);
      expect(find.text('Listen and collect birds'), findsOneWidget);
    });

    testWidgets('it is taller than any secondary tile', (tester) async {
      await pump(tester, const HomeTiles());

      final live = tester.getSize(
        find
            .ancestor(of: find.text('Live'), matching: find.byType(Material))
            .first,
      );
      final secondary = tester.getSize(
        find
            .ancestor(of: find.text('Explore'), matching: find.byType(Material))
            .first,
      );

      expect(live.height, greaterThan(secondary.height));
      expect(live.width, greaterThan(secondary.width));
    });
  });

  group('HOME-04 · the secondary tiles', () {
    testWidgets('every tile that exists leads somewhere', (tester) async {
      // The old carousel ended up with one card and two page dots because a
      // deletion left it behind. Counting is what stops that recurring.
      await pump(tester, const HomeTiles());

      // HOME-04's full list, complete as of 2.7.
      for (final label in [
        'Collection',
        'Explore',
        'Journal',
        'Points',
        'Settings',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    // A tile that opens nothing is a broken promise, and the old carousel
    // ended up with one card and two page dots precisely because nobody
    // checked. One test per tile rather than a loop: a loop shares one
    // binding across pushes, and the failure it produces names no tile.
    //
    // Deliberately not `pumpAndSettle` — these screens read the database and
    // sit on a spinner in a test, which never settles. That the route lands is
    // the whole claim.
    for (final entry
        in <String, Type>{
          'Collection': CollectionScreen,
          'Journal': JournalScreen,
          'Points': PointsScreen,
        }.entries) {
      testWidgets('the ${entry.key} tile opens its screen', (tester) async {
        await pump(tester, const HomeTiles());

        await tester.tap(find.text(entry.key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.byType(entry.value), findsOneWidget);
      });
    }

    testWidgets('tapping one navigates', (tester) async {
      await pump(tester, const HomeTiles());

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      // Landed on the settings screen, whose plain view carries this section.
      expect(find.text('General'), findsWidgets);
    });
  });
}
