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
import 'package:smartfinch/shared/utils/app_icons.dart';

/// Only the loyalty badges, which are the ones AUS-02 keeps hidden until
/// earned. The day and week catalogue is always earnable alongside them, so a
/// claim about loyalty has to say so.
List<EarnedBadge> loyaltyIn(PointsOverview overview) => [
  for (final badge in overview.badges)
    if (badge.definition.kind == BadgeKind.loyalty) badge,
];

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

        // Narrowed once AUS-04 filled the catalogue in: these days still
        // earn 🌅 and ✨, and the claim was only ever about 🔟.
        final overview = await points.overview(now: may4);
        expect(overview.badgeFor(kTenInOneGo.key), isNull);
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

        expect(loyaltyIn(await points.overview(now: may4)), isEmpty);
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

        expect(loyaltyIn(await points.overview(now: may4)), isEmpty);
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

    // =======================================================================
    // AUS-04 · the daily catalogue
    // =======================================================================
    //
    // Read from `ScoreEvents`, so a badge means what a star means: listening
    // with scoring paused is kept and is worth nothing, badges included.
    // The clock rules are the ones most likely to drift, because an hour
    // boundary off by one is invisible until a child complains in June.
    // =======================================================================
    group('AUS-04 · the daily badges', () {
      final at0730 = DateTime(2026, 5, 4, 7, 30);
      final at1900 = DateTime(2026, 5, 4, 19, 0);
      final at2230 = DateTime(2026, 5, 4, 22, 30);

      test('🌅 The early bird wants anything before 09:00', () async {
        await hear('Species sp0', at: at0730);

        final overview = await points.overview(now: may4);
        expect(overview.badgeFor(kEarlyBird.key), isNotNull);
      });

      test('🌅 09:00 exactly is too late', () async {
        await hear('Species sp0', at: DateTime(2026, 5, 4, 9, 0));

        expect(
          (await points.overview(now: may4)).badgeFor(kEarlyBird.key),
          isNull,
        );
      });

      test('🌆 Evening listener wants anything from 18:00', () async {
        await hear('Species sp0', at: at1900);

        final overview = await points.overview(now: may4);
        expect(overview.badgeFor(kEveningListener.key), isNotNull);
        // Two rhythm setters, not one badge with two names: an afternoon
        // walk earns neither.
        expect(overview.badgeFor(kEarlyBird.key), isNull);
      });

      test('🌙 Night owl needs 22:00, not the evening', () async {
        // 3.2 moved this from 18:00 on purpose — at 18:00 the name would
        // simply be wrong in June.
        await hear('Species sp0', at: at1900);
        expect(
          (await points.overview(now: may4)).badgeFor(kNightOwl.key),
          isNull,
        );

        await hear('Species sp1', at: at2230);
        expect(
          (await points.overview(now: may4)).badgeFor(kNightOwl.key),
          isNotNull,
        );
      });

      test('🎵 Dawn chorus wants five *different* species', () async {
        for (var i = 0; i < 4; i++) {
          await hear('Species sp$i', at: at0730);
        }
        expect(
          (await points.overview(now: may4)).badgeFor(kDawnChorus.key),
          isNull,
        );

        await hear('Species sp4', at: at0730);
        expect(
          (await points.overview(now: may4)).badgeFor(kDawnChorus.key),
          isNotNull,
        );
      });

      test('🎵 Dawn chorus starts at 05:00, not at midnight', () async {
        for (var i = 0; i < 5; i++) {
          await hear('Species sp$i', at: DateTime(2026, 5, 4, 3, 0));
        }

        expect(
          (await points.overview(now: may4)).badgeFor(kDawnChorus.key),
          isNull,
        );
      });

      test('✨ Discovery day means a first find *ever*', () async {
        await hear('Species sp0');
        final first = await points.overview(now: may4);
        expect(first.badgeFor(kDiscoveryDay.key)?.timesEarned, 1);

        // The same bird tomorrow is not a discovery, however pleased the
        // child is to hear it (LOG-09).
        await hear('Species sp0', at: may4.add(const Duration(days: 1)));
        final second = await points.overview(now: may4);
        expect(second.badgeFor(kDiscoveryDay.key)?.timesEarned, 1);
      });

      test('🥇 Rare guest wants the rarer half of the scale', () async {
        await hear('Species sp0'); // the most abundant bird there is
        expect(
          (await points.overview(now: may4)).badgeFor(kRareGuest.key),
          isNull,
        );

        await hear('Species sp39'); // the rarest
        expect(
          (await points.overview(now: may4)).badgeFor(kRareGuest.key),
          isNotNull,
        );
      });

      test('🗺️ New ground is somewhere you have not been', () async {
        // A home cell first — the setUp session has no location at all.
        final home = await scoring.startSession(startedAt: may4, cell: cell);
        await scoring.recordDetection(
          sessionId: home,
          scientificName: 'Species sp0',
          confidence: 0.9,
          context: contextAt(may4),
        );

        // The first cell is not new ground: everywhere is, the first time the
        // app is opened, and a badge for that teaches nothing.
        expect(
          (await points.overview(now: may4)).badgeFor(kNewGround.key),
          isNull,
        );

        final elsewhere = await scoring.startSession(
          startedAt: may4.add(const Duration(days: 1)),
          cell: const GridCell(511, 133),
        );
        await scoring.recordDetection(
          sessionId: elsewhere,
          scientificName: 'Species sp1',
          confidence: 0.9,
          context: contextAt(may4.add(const Duration(days: 1))),
        );

        expect(
          (await points.overview(now: may4)).badgeFor(kNewGround.key),
          isNotNull,
        );
      });

      test('🌱 Herald of spring needs the curve, and says so', () async {
        // Without a geo model there is no season to be early for, so the
        // badge is simply unearnable rather than wrongly earned.
        await hear('Species sp0', at: DateTime(2026, 2, 4, 10));

        expect(
          (await points.overview(now: may4)).badgeFor(kHeraldOfSpring.key),
          isNull,
        );
      });

      test('🌱 Herald of spring fires on a bird that is early', () async {
        // A summer visitor — nothing until May, peak in July — heard in
        // February. That is exactly the sentence PKT-17 puts on screen, and
        // the badge must not disagree with it.
        final summerVisitor = [
          for (var week = 1; week <= 48; week++)
            week >= 17 && week <= 36 ? 1.0 : 0.02,
        ];

        await hear('Species sp0', at: DateTime(2026, 2, 4, 10));

        final overview = await points.overview(
          now: may4,
          weeklyScores: (name) => summerVisitor,
        );
        expect(overview.badgeFor(kHeraldOfSpring.key), isNotNull);
      });

      test('🌱 a resident is never early, which is the whole point', () async {
        // A blackbird has no season to be early for. A badge that fired for
        // one would teach a child something false.
        final resident = [for (var week = 1; week <= 48; week++) 0.8];

        await hear('Species sp0', at: DateTime(2026, 2, 4, 10));

        final overview = await points.overview(
          now: may4,
          weeklyScores: (name) => resident,
        );
        expect(overview.badgeFor(kHeraldOfSpring.key), isNull);
      });

      test('a badge that resets can be earned again, and counts', () async {
        await hear('Species sp0', at: at0730);
        await hear('Species sp1', at: at0730.add(const Duration(days: 1)));

        expect(
          (await points.overview(
            now: may4,
          )).badgeFor(kEarlyBird.key)?.timesEarned,
          2,
        );
      });

      test('⚠️ a paused detection earns nothing', () async {
        // PKT-20 and LOG-15: the recording is kept and is worth nothing. A
        // badge is worth something, so it must follow the star.
        await hear('Species sp39', at: at0730, filterEnabled: false);

        final overview = await points.overview(now: may4);
        expect(overview.badgeFor(kEarlyBird.key), isNull);
        expect(overview.badgeFor(kRareGuest.key), isNull);
      });
    });

    // =======================================================================
    // AUS-05 · the weekly catalogue
    // =======================================================================
    group('AUS-05 · the weekly badges', () {
      test('📅 Consistent wants four days of one week', () async {
        for (var day = 0; day < 3; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }
        expect(
          (await points.overview(now: may4)).badgeFor(kConsistent.key),
          isNull,
        );

        await hear('Species sp0', at: may4.add(const Duration(days: 3)));
        expect(
          (await points.overview(now: may4)).badgeFor(kConsistent.key),
          isNotNull,
        );
      });

      test('📅 four days across two weeks is not consistency', () async {
        // Monday, Tuesday, then Monday and Tuesday of the week after.
        await hear('Species sp0', at: may4);
        await hear('Species sp0', at: may4.add(const Duration(days: 1)));
        await hear('Species sp0', at: may4.add(const Duration(days: 7)));
        await hear('Species sp0', at: may4.add(const Duration(days: 8)));

        expect(
          (await points.overview(now: may4)).badgeFor(kConsistent.key),
          isNull,
        );
      });

      test('🌍 Well travelled counts places, not walks', () async {
        Future<void> listenIn(GridCell cell, int dayOffset) async {
          final session = await scoring.startSession(
            startedAt: may4.add(Duration(days: dayOffset)),
            cell: cell,
          );
          await scoring.recordDetection(
            sessionId: session,
            scientificName: 'Species sp0',
            confidence: 0.9,
            context: contextAt(may4.add(Duration(days: dayOffset))),
          );
        }

        await listenIn(const GridCell(508, 129), 0);
        await listenIn(const GridCell(508, 129), 1);
        expect(
          (await points.overview(now: may4)).badgeFor(kWellTravelled.key),
          isNull,
        );

        await listenIn(const GridCell(509, 130), 2);
        await listenIn(const GridCell(510, 131), 3);
        expect(
          (await points.overview(now: may4)).badgeFor(kWellTravelled.key),
          isNotNull,
        );
      });

      test('🎯 Weekly target is 5,000 stars in one week', () async {
        // sp39 is the rarest tier: 1000 base, ×3 for the first find.
        for (var i = 36; i < 40; i++) {
          await hear('Species sp$i');
        }

        final overview = await points.overview(now: may4);
        expect(overview.figures.totalStars, greaterThanOrEqualTo(5000));
        expect(overview.badgeFor(kWeeklyTarget.key), isNotNull);
      });
    });

    // =======================================================================
    // AUS-06 · rarity achievements
    // =======================================================================
    //
    // The one rule with a ⚠️ on it: counted at the level **frozen at the
    // moment of detection** (`PKT-15`). The scale is rebuilt per cell and per
    // geo week, so re-deriving it today would un-earn a redwing that was rare
    // in November because the same bird is common in January.
    // =======================================================================
    group('AUS-06 · the rarity achievements', () {
      test('one rare bird is a Lucky one', () async {
        await hear('Species sp39');

        final earned = (await points.overview(now: may4)).rarityAchievements;
        expect(earned.map((a) => a.key), contains(kLuckyOne.key));
      });

      test('an abundant bird is not', () async {
        await hear('Species sp0');

        expect((await points.overview(now: may4)).rarityAchievements, isEmpty);
      });

      test('the rungs are distinct species, not detections', () async {
        // The same rarity heard five times is one rare bird.
        for (var day = 0; day < 5; day++) {
          await hear('Species sp39', at: may4.add(Duration(days: day)));
        }

        final earned = (await points.overview(now: may4)).rarityAchievements;
        expect(earned.map((a) => a.key), isNot(contains(kTracker.key)));
      });

      test('five different rare birds make a Tracker', () async {
        for (var i = 29; i < 34; i++) {
          await hear('Species sp$i');
        }

        final earned = (await points.overview(now: may4)).rarityAchievements;
        expect(earned.map((a) => a.key), contains(kTracker.key));
      });

      test('🎆 Sensation! wants the very top of the scale', () async {
        // Not "a rare-ish bird": the rarest tier there is.
        await hear('Species sp29'); // scarce, upper half but not the top
        var earned = (await points.overview(now: may4)).rarityAchievements;
        expect(earned.map((a) => a.key), contains(kLuckyOne.key));
        expect(earned.map((a) => a.key), isNot(contains(kSensation.key)));

        await hear('Species sp39');
        earned = (await points.overview(now: may4)).rarityAchievements;
        expect(earned.map((a) => a.key), contains(kSensation.key));
      });
    });

    // =======================================================================
    // AUS-07 · persistence achievements
    // =======================================================================
    //
    // ⚠️ Every one of these is a **record**. A broken streak is not commented
    // on, not marked and not presented as a loss (principle 1), and the
    // cheapest way to keep that promise is to have no number that can go down.
    // =======================================================================
    group('AUS-07 · the persistence achievements', () {
      test('seven days in a row is a week kept up', () async {
        for (var day = 0; day < 7; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }

        final earned =
            (await points.overview(now: may4)).persistenceAchievements;
        expect(earned.map((a) => a.key), contains(kWeekKeptUp.key));
      });

      test('six is not', () async {
        for (var day = 0; day < 6; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }

        expect(
          (await points.overview(now: may4)).persistenceAchievements,
          isEmpty,
        );
      });

      test('⚠️ a broken streak never takes the badge away', () async {
        // The heart of principle 1. Seven days, then a gap, then two more —
        // the record stands, and nothing anywhere says the run ended.
        for (var day = 0; day < 7; day++) {
          await hear('Species sp0', at: may4.add(Duration(days: day)));
        }
        await hear('Species sp0', at: may4.add(const Duration(days: 20)));
        await hear('Species sp0', at: may4.add(const Duration(days: 21)));

        final overview = await points.overview(now: may4);
        expect(
          overview.persistenceAchievements.map((a) => a.key),
          contains(kWeekKeptUp.key),
        );
        expect(overview.figures.longestStreak, 7);
      });

      test('Star collector counts stars, not days', () async {
        for (var i = 36; i < 40; i++) {
          await hear('Species sp$i');
        }

        final overview = await points.overview(now: may4);
        final earned = overview.persistenceAchievements.map((a) => a.key);
        expect(
          earned.contains(kStarCollectorI.key),
          overview.figures.totalStars >= 10000,
        );
      });

      test('an empty history earns nothing at all', () async {
        final overview = await points.overview(now: may4);

        expect(overview.persistenceAchievements, isEmpty);
        expect(overview.rarityAchievements, isEmpty);
        expect(overview.badges, isEmpty);
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

    testWidgets('AUS-02 · an unearned loyalty badge is not shown at all', (
      tester,
    ) async {
      await pump(tester, const PointsOverview(figures: KeyFigures()));

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      // A permanent reminder of a bird you have not been loyal to is the
      // opposite of what this screen is for — so the loyalty section is not
      // even there. The day and week catalogues *are* (AUS-04, AUS-05): an
      // open daily badge is a suggestion for this afternoon.
      expect(find.text('Regular'), findsNothing);
      expect(find.text('Always here'), findsNothing);
      expect(find.text('Your regulars'), findsNothing);
      expect(find.text('The early bird'), findsOneWidget);
    });

    testWidgets('AUS-04 · the whole daily catalogue is on screen', (
      tester,
    ) async {
      await pump(tester, const PointsOverview(figures: KeyFigures()));

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      expect(
        find.byType(BadgeTile),
        findsNWidgets(kDailyBadges.length + kWeeklyBadges.length),
      );
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
    });

    testWidgets('AUS-04 · an open badge is marked open, not failed', (
      tester,
    ) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(),
          badges: [EarnedBadge(definition: kEarlyBird)],
        ),
      );

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      // One tick for the one earned badge; every other row carries the quiet
      // "still open" mark rather than a cross.
      expect(find.byIcon(AppIcons.checkCircle), findsOneWidget);
      expect(
        find.byIcon(AppIcons.lockOutline),
        findsNWidgets(kDailyBadges.length + kWeeklyBadges.length - 1),
      );
    });

    testWidgets('AUS-04 · a badge says what earns it, earned or not', (
      tester,
    ) async {
      await pump(tester, const PointsOverview(figures: KeyFigures()));

      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();

      // The condition is the invitation. Without it an open badge is a
      // mystery rather than a suggestion.
      expect(find.text('Heard something after 10 at night'), findsOneWidget);
      expect(find.text('5,000 stars in one week'), findsOneWidget);
    });

    testWidgets('AUS-06 · rarity achievements get their own section', (
      tester,
    ) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(),
          rarityAchievements: [kLuckyOne, kSensation],
        ),
      );

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('Rare finds'), findsOneWidget);
      expect(find.text('Lucky one'), findsOneWidget);
      expect(find.text('Sensation!'), findsOneWidget);
    });

    testWidgets('AUS-07 · persistence achievements do too', (tester) async {
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(),
          persistenceAchievements: [kWeekKeptUp],
        ),
      );

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.text('Staying power'), findsOneWidget);
      expect(find.text('A week kept up'), findsOneWidget);
    });

    testWidgets('⚠️ AUS-07 · nothing on this tab can be lost', (tester) async {
      // Principle 1. Persistence achievements are records, so the tab has no
      // vocabulary for a run that ended — no "current streak", no red, no
      // "you lost it". If this ever fails, something on screen learnt how to
      // take a badge away.
      await pump(
        tester,
        const PointsOverview(
          figures: KeyFigures(longestStreak: 7),
          persistenceAchievements: [kWeekKeptUp],
        ),
      );

      await tester.tap(find.text('Achievements'));
      await tester.pumpAndSettle();

      expect(find.textContaining('lost'), findsNothing);
      expect(find.textContaining('broken'), findsNothing);
      expect(find.text('A week kept up'), findsOneWidget);
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
