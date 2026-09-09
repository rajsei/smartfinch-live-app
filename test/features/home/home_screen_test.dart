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

import 'package:drift/native.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/avatar/avatar_providers.dart';
import 'package:smartfinch/features/avatar/level_ladder.dart';
import 'package:smartfinch/features/home/widgets/home_header.dart';
import 'package:smartfinch/features/collection/collection_screen.dart';
import 'package:smartfinch/features/home/home_screen.dart';
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

  // ===========================================================================
  // The two-tone home screen, and the avatar on it (HOME-07)
  // ===========================================================================
  //
  // The layout itself is a UI direction rather than a requirement, so what is
  // asserted here is the part that is: the avatar is on the home screen
  // (`HOME-07`, `AVA-01`), every destination is still one tap away in the
  // default position (`HOME-04`, `KID-04`), and the panel that carries them
  // can be moved without any of them going missing.
  // ===========================================================================
  group('the two-tone home screen', () {
    Future<void> pumpHome(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // Portrait: the two-tone layout is the portrait one.
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            starTotalsProvider.overrideWith(
              (ref) async => const StarTotals(total: 4200),
            ),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 4200),
            ),
            avatarNameProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      // Past the home screen's own warm-up, which arms a 2-second timeout on
      // the taxonomy load. Left pending it fails the test at teardown for a
      // reason that has nothing to do with the layout.
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('HOME-07 · the bird is on it, with its level', (tester) async {
      await pumpHome(tester);

      expect(find.byType(AvatarBadge), findsOneWidget);
      // The chip on the circle, and the line under the bar.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Level 4'), findsOneWidget);
    });

    testWidgets('the three figures are there, each labelled', (tester) async {
      // HOME-01 and HOME-02: three numbers answering three questions, and a
      // header that showed the same figure three times would look right and
      // be useless.
      await pumpHome(tester);

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('4,200'), findsOneWidget);
    });

    testWidgets('and how far the next level is (STAT-07)', (tester) async {
      // Level 4 runs 4,000 → 8,000, so 3,800 to go.
      await pumpHome(tester);

      expect(find.textContaining('to level 5'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('it fits a small phone without overflowing', (tester) async {
      // The existing pump is 1000 logical px wide, which the layout treats as
      // a tablet. The header shares its screen with the panel, so the size
      // that actually squeezes it is a short phone — and an overflow there
      // fails this test rather than shipping as a yellow stripe.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            starTotalsProvider.overrideWith(
              // A long total, because the biggest number is what runs out of
              // room first.
              (ref) async =>
                  const StarTotals(total: 345657, last30Days: 1257, today: 114),
            ),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 345657),
            ),
            avatarNameProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      expect(find.text('345,657'), findsOneWidget);

      // Every destination on screen without scrolling, at the size that
      // squeezes hardest — KID-04's "one tap away" is not one tap away if the
      // last row is below the fold.
      for (final label in ['Collection', 'Explore', 'Journal', 'Points']) {
        final rect = tester.getRect(find.text(label));
        expect(
          rect.bottom,
          lessThanOrEqualTo(640),
          reason: '$label is off the bottom of a 640-pixel screen',
        );
      }
    });

    testWidgets('the app name is not taking up the header any more', (
      tester,
    ) async {
      // It cost a third of the block to tell a child the name of the app they
      // had just opened. The header's job is to say what *they* have.
      await pumpHome(tester);

      expect(find.text('Smartfinch'), findsNothing);
    });

    testWidgets('every destination is still one tap away', (tester) async {
      // HOME-04 and KID-04. A layout change must not bury a destination
      // behind a gesture.
      await pumpHome(tester);

      expect(find.byType(HomeTiles), findsOneWidget);
      for (final label in ['Collection', 'Explore', 'Journal', 'Points']) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label should be reachable without dragging',
        );
      }
    });

    testWidgets('the panel starts open, under the header', (tester) async {
      // The failure this replaces: the panel opened *over* the star figures
      // and clipped its own tiles, which on screen looked as though the app
      // had stopped drawing.
      await pumpHome(tester);

      final headerBottom = tester.getRect(find.byType(HomeHeader)).bottom;
      final panelTop = tester.getRect(find.byType(HomeTiles)).top;

      expect(panelTop, greaterThanOrEqualTo(headerBottom - 1));
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('the handle moves the panel down and back', (tester) async {
      // The one piece the sketch marked as meant to survive. Tapping counts:
      // a child who never discovers the drag can still press the handle
      // (KID-04).
      await pumpHome(tester);

      final openTop = tester.getRect(find.byType(HomeTiles)).top;

      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();
      final downTop = tester.getRect(find.byType(HomeTiles)).top;
      expect(downTop, greaterThan(openTop));

      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(HomeTiles)).top, closeTo(openTop, 1));
    });
  });

  // ===========================================================================
  // Landscape — the same two blocks, side by side
  // ===========================================================================
  group('the home screen held sideways', () {
    Future<void> pumpLandscape(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      // A phone on its side: plenty of width, barely any height. That is the
      // shape the layout has to answer, and the one a portrait test never
      // exercises.
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            starTotalsProvider.overrideWith(
              (ref) async =>
                  const StarTotals(total: 345657, last30Days: 1257, today: 114),
            ),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 345657),
            ),
            avatarNameProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('the logo and the app name are gone from it too', (
      tester,
    ) async {
      await pumpLandscape(tester);

      expect(find.text('Smartfinch'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('it is the same star display, rules and all', (tester) async {
      // Not a landscape arrangement of the same numbers — the identical
      // widget, so the two orientations cannot drift apart.
      await pumpLandscape(tester);

      expect(find.byType(HomeHeader), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('30 days'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('345,657'), findsOneWidget);
    });

    testWidgets('the bird and the level come with it', (tester) async {
      await pumpLandscape(tester);

      expect(find.byType(AvatarBadge), findsOneWidget);
      expect(find.textContaining('Level '), findsOneWidget);
    });

    testWidgets('header on the left, tiles on the right', (tester) async {
      await pumpLandscape(tester);

      final header = tester.getRect(find.byType(HomeHeader));
      final tiles = tester.getRect(find.byType(HomeTiles));

      expect(header.right, lessThanOrEqualTo(tiles.left + 1));
      // The navigation gets the larger share, because it is the half that
      // uses extra width.
      expect(tiles.width, greaterThan(header.width));
    });

    testWidgets('and it all fits, without overflowing', (tester) async {
      await pumpLandscape(tester);

      expect(tester.takeException(), isNull);
      for (final label in ['Collection', 'Explore', 'Journal', 'Points']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });
}
