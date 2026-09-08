// =============================================================================
// The Points area — STAT-02, STAT-05, STAT-06, AUS-01, AUS-02, AUS-03
// =============================================================================
//
// Two rules here are worth more than the rest:
//
//   **A day is active when it produced at least one scoring detection**
//   (`STAT-06`). Not "app opened", not "session started". It is the only
//   definition a child can check against their own journal — and it means a
//   day spent entirely in test mode is not an active day and does not extend a
//   streak.
//
//   **Empty days stay in the chart** (`STAT-02`). Omit them and five scattered
//   days across a month draw the same shape as five days in a row, so the
//   chart tells every child they are consistent.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/features/points/points_providers.dart';
import 'package:smartfinch/features/points/points_repository.dart';
import 'package:smartfinch/features/points/points_screen.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  const cell = GridCell(508, 129);

  /// Monday 4 May 2026.
  final may4 = DateTime(2026, 5, 4, 14, 30);

  final scale = () {
    final raw = <String, double>{
      for (var rank = 0; rank < 40; rank++)
        'Species sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: const RarityScaleKey(cell, 18),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }();

  group('longestStreakIn', () {
    test('an empty history has no streak', () {
      expect(longestStreakIn(const []), 0);
    });

    test('one day is a streak of one', () {
      expect(longestStreakIn(['2026-05-04']), 1);
    });

    test('consecutive days add up', () {
      expect(longestStreakIn(['2026-05-04', '2026-05-05', '2026-05-06']), 3);
    });

    test('a gap starts a new run, and the longest wins', () {
      expect(
        longestStreakIn([
          '2026-05-01',
          '2026-05-02',
          // gap
          '2026-05-05',
          '2026-05-06',
          '2026-05-07',
          '2026-05-08',
        ]),
        4,
      );
    });

    test('it survives a month boundary', () {
      // The kind of off-by-one that would quietly rewrite a personal best.
      expect(longestStreakIn(['2026-04-30', '2026-05-01']), 2);
    });

    test('it survives a year boundary', () {
      expect(longestStreakIn(['2025-12-31', '2026-01-01']), 2);
    });

    test('unsorted input is handled', () {
      expect(longestStreakIn(['2026-05-06', '2026-05-04', '2026-05-05']), 3);
    });
  });

  group('from the database', () {
    late AppDatabase db;
    late ScoringRepository scoring;
    late PointsRepository points;
    late String sessionId;

    ScoringContext contextAt(DateTime when, {bool filterEnabled = true}) =>
        ScoringContext(
          now: when,
          appliedThreshold: 35,
          filterEnabled: filterEnabled,
          scale: scale,
          cell: cell,
        );

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      scoring = ScoringRepository(db);
      points = PointsRepository(db);
      sessionId = await scoring.startSession(startedAt: may4);
    });

    tearDown(() async => db.close());

    Future<void> hear(String name, {DateTime? at, bool filterEnabled = true}) =>
        scoring
            .recordDetection(
              sessionId: sessionId,
              scientificName: name,
              confidence: 0.9,
              context: contextAt(at ?? may4, filterEnabled: filterEnabled),
            )
            .then((_) {});

    /// Hears [count] different species on [day].
    Future<void> hearMany(int count, {DateTime? at, int from = 0}) async {
      for (var i = from; i < from + count; i++) {
        await hear('Species sp$i', at: at);
      }
    }

    group('STAT-06 · the key figures', () {
      test('report stars, species, active days and the longest run', () async {
        await hearMany(3);
        await hearMany(2, at: may4.add(const Duration(days: 1)), from: 10);

        final figures = (await points.overview(now: may4)).figures;

        expect(figures.totalStars, greaterThan(0));
        expect(figures.speciesOverall, 5);
        expect(figures.activeDays, 2);
        expect(figures.longestStreak, 2);
      });

      test('⚠️ a test-mode day is not an active day', () async {
        // It produced no scoring detection, so by STAT-06's own definition it
        // does not count — and therefore does not extend a streak either.
        await hear('Species sp0');
        await hear(
          'Species sp1',
          at: may4.add(const Duration(days: 1)),
          filterEnabled: false,
        );
        await hear('Species sp2', at: may4.add(const Duration(days: 2)));

        final figures = (await points.overview(now: may4)).figures;

        expect(figures.activeDays, 2, reason: 'the middle day did not count');
        expect(figures.longestStreak, 1, reason: 'so the run is broken');
      });

      test('an empty database is all zeroes', () async {
        final figures = (await points.overview(now: may4)).figures;

        expect(figures.totalStars, 0);
        expect(figures.speciesOverall, 0);
        expect(figures.activeDays, 0);
        expect(figures.longestStreak, 0);
      });
    });

    group('STAT-02 · the chart', () {
      test('has one column per day, including the empty ones', () async {
        await hear('Species sp0');

        final chart = (await points.overview(now: may4)).dailyStars;

        expect(chart, hasLength(30));
        expect(chart.where((d) => d.isEmpty), hasLength(29));
      });

      test('runs oldest first and ends today', () async {
        final chart = (await points.overview(now: may4)).dailyStars;

        expect(chart.first.dayKey, '2026-04-05');
        expect(chart.last.dayKey, '2026-05-04');
      });

      test('a gap between two active days is preserved', () async {
        // Omitting it would draw the same shape as two days in a row.
        await hear('Species sp0', at: may4.subtract(const Duration(days: 3)));
        await hear('Species sp1', at: may4);

        final chart = (await points.overview(now: may4)).dailyStars;
        final active = [
          for (var i = 0; i < chart.length; i++)
            if (!chart[i].isEmpty) i,
        ];

        expect(active, hasLength(2));
        expect(active[1] - active[0], 3, reason: 'three days apart, still');
      });

      test('day bonuses are in the column too', () async {
        await hearMany(5);

        final chart = (await points.overview(now: may4)).dailyStars;
        final today = chart.last;

        expect(today.stars, greaterThan(0));
        expect(
          today.stars,
          (await points.overview(now: may4)).figures.totalStars,
        );
      });
    });

    group('AUS-01 · Ten in one go', () {
      test('is earned at ten different species in one day', () async {
        await hearMany(10);

        final badges = (await points.overview(now: may4)).badges;
        expect(badges.map((b) => b.definition.key), contains('tenInOneGo'));
      });

      test('is not earned at nine', () async {
        await hearMany(9);

        final badges = (await points.overview(now: may4)).badges;
        expect(
          badges.map((b) => b.definition.key),
          isNot(contains('tenInOneGo')),
        );
      });

      test('a badge that resets can be earned again, and counts', () async {
        await hearMany(10);
        await hearMany(10, at: may4.add(const Duration(days: 1)), from: 20);

        final badge = (await points.overview(
          now: may4,
        )).badges.firstWhere((b) => b.definition.key == 'tenInOneGo');

        expect(badge.timesEarned, 2);
        expect(badge.lastEarnedOn, '2026-05-05');
      });

      test('ten species across two days is not ten in one go', () async {
        await hearMany(5);
        await hearMany(5, at: may4.add(const Duration(days: 1)), from: 20);

        final badges = (await points.overview(now: may4)).badges;
        expect(badges, isEmpty);
      });
    });

    group('AUS-02 · the loyalty badges', () {
      test('Regular is earned on the 3rd day of a week', () async {
        for (var day = 0; day < 3; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }

        final badges = (await points.overview(now: may4)).badges;
        final regular = badges.firstWhere((b) => b.definition.key == 'regular');

        expect(regular.subject, 'Species sp0');
      });

      test('two days is not enough', () async {
        for (var day = 0; day < 2; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }

        expect((await points.overview(now: may4)).badges, isEmpty);
      });

      test('six days earns the higher badge instead, not as well', () async {
        for (var day = 0; day < 6; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }

        final keys =
            (await points.overview(
              now: may4,
            )).badges.map((b) => b.definition.key).toList();

        expect(keys, contains('permanentGuest'));
        expect(keys, isNot(contains('regular')));
      });

      test('three days spread across two weeks earns nothing', () async {
        // Monday and Wednesday of one week, Monday of the next.
        await hear('Species sp0', at: may4);
        await hear('Species sp0', at: may4.add(const Duration(days: 2)));
        await hear('Species sp0', at: may4.add(const Duration(days: 7)));

        expect((await points.overview(now: may4)).badges, isEmpty);
      });

      test('each species earns its own', () async {
        for (var day = 0; day < 3; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
          await hear('Species sp1', at: may4.add(Duration(days: day)));
        }

        final subjects =
            (await points.overview(now: may4)).badges
                .where((b) => b.definition.key == 'regular')
                .map((b) => b.subject)
                .toSet();

        expect(subjects, {'Species sp0', 'Species sp1'});
      });
    });

    group('AUS-03 · the Collector ladder', () {
      test('nothing is earned below the first rung', () async {
        await hearMany(9);

        expect((await points.overview(now: may4)).achievements, isEmpty);
      });

      test('ten species earns the first medal', () async {
        await hearMany(10);

        final earned = (await points.overview(now: may4)).achievements;
        expect(earned.map((t) => t.key), ['firstSteps']);
      });

      test('every rung passed is kept, highest first', () async {
        await hearMany(26);

        final earned = (await points.overview(now: may4)).achievements;
        expect(earned.map((t) => t.key), ['attentiveListener', 'firstSteps']);
      });

      test('a paused detection does not count towards it', () async {
        // The ladder counts the life list, and a paused detection never
        // reaches it (DAT-11).
        for (var i = 0; i < 10; i++) {
          await hear('Species sp$i', filterEnabled: false);
        }

        expect((await points.overview(now: may4)).achievements, isEmpty);
      });
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, PointsOverview overview) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            pointsOverviewProvider.overrideWith((ref) async => overview),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const PointsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('STAT-05 · three tabs', (tester) async {
      await pump(tester, const PointsOverview(figures: KeyFigures()));

      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Badges'), findsOneWidget);
      expect(find.text('Achievements'), findsOneWidget);
    });

    testWidgets('STAT-06 · the four key figures are on the overview', (
      tester,
    ) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(
            totalStars: 12400,
            speciesOverall: 37,
            activeDays: 21,
            longestStreak: 6,
          ),
        ),
      );

      expect(find.text('12400'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
    });

    testWidgets('the streak figure is the longest, not the current one', (
      tester,
    ) async {
      // A broken streak is never commented on (AUS-07, principle 1), so the
      // screen must not carry a number that can fall to zero overnight.
      await pump(
        tester,
        const PointsOverview(figures: KeyFigures(longestStreak: 6)),
      );

      expect(find.text('Longest run'), findsOneWidget);
    });

    testWidgets('AUS-02 · an unearned badge is not shown greyed out', (
      tester,
    ) async {
      await pump(tester, const PointsOverview(figures: KeyFigures()));

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      expect(find.text('No badges yet'), findsOneWidget);
      // A permanent reminder of what you have not managed is the opposite of
      // what this screen is for.
      expect(find.text('Regular'), findsNothing);
      expect(find.text('Always here'), findsNothing);
    });

    testWidgets('an earned loyalty badge names its species', (tester) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(),
          badges: [EarnedBadge(definition: kRegular, subject: 'Blackbird')],
        ),
      );

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      // Which species it is, is most of the badge's meaning.
      expect(find.text('Regular · Blackbird'), findsOneWidget);
    });

    testWidgets('a badge earned more than once says how often', (tester) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(),
          badges: [EarnedBadge(definition: kTenInOneGo, timesEarned: 3)],
        ),
      );

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      expect(find.text('Ten in one go'), findsOneWidget);
      expect(find.text('×3'), findsOneWidget);
    });

    testWidgets('AUS-03 · only earned medals are listed', (tester) async {
      await pump(
        tester,
        PointsOverview(
          figures: const KeyFigures(speciesOverall: 26),
          achievements: [kCollectorTiers[1], kCollectorTiers[0]],
        ),
      );

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('Attentive listener'), findsOneWidget);
      expect(find.text('First steps'), findsOneWidget);
      expect(find.text('Half a hundred'), findsNothing);
    });

    testWidgets('the next medal is one line, not a row of faded ones', (
      tester,
    ) async {
      // A ladder of eight greyed medals is a list of things you have not done.
      await pump(
        tester,
        PointsOverview(
          figures: const KeyFigures(speciesOverall: 12),
          achievements: [kCollectorTiers[0]],
        ),
      );

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('13 more species to the next medal'), findsOneWidget);
    });
  });
}
