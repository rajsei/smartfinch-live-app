// =============================================================================
// Year-list achievements — AUS-13
// =============================================================================
//
// Together with the year-first ×2 (`PKT-12`) these replace the removed season
// bonus, and they are what keeps every spring interesting once the local
// region has been largely exhausted (3.4).
//
// Each of the four rules has a calendar edge that would be easy to get wrong
// and invisible when it was — a month boundary, a season boundary, a year
// boundary. That is what these tests are for.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/features/points/points_repository.dart';

void main() {
  /// One row of the year list.
  YearSpecy entry(String name, DateTime firstSeen) => YearSpecy(
    id: name,
    profileId: kDefaultProfileId,
    updatedAt: firstSeen,
    syncState: 0,
    year: firstSeen.year,
    scientificName: name,
    firstDetectionId: 'd-$name',
    firstSeenAt: firstSeen,
  );

  /// [count] species first seen in [month] of 2026.
  List<YearSpecy> inMonth(int month, int count, {String prefix = 's'}) => [
    for (var i = 0; i < count; i++)
      entry('$prefix-$month-$i', DateTime(2026, month, 10)),
  ];

  List<YearAchievement> earned({
    List<YearSpecy> yearList = const [],
    Iterable<String> activeDays = const [],
  }) => PointsRepository.yearAchievementsFor(
    yearList: yearList,
    activeDayKeys: activeDays,
    year: 2026,
  );

  Set<String> keysOf(List<YearAchievement> list) => {
    for (final a in list) '${a.key}${a.tierLabel ?? ''}',
  };

  group('the three counted rungs', () {
    test('nothing below 25 species', () {
      // August: outside spring and winter, so only the count is under test.
      expect(earned(yearList: inMonth(8, 24)), isEmpty);
    });

    test('25 earns the first', () {
      expect(keysOf(earned(yearList: inMonth(8, 25))), {'yearListI'});
    });

    test('every rung passed is kept, highest first', () {
      final list = earned(yearList: inMonth(8, 80));

      expect(list.first.tierLabel, 'III');
      expect(
        keysOf(list),
        containsAll({'yearListI', 'yearListII', 'yearListIII'}),
      );
    });

    test('an empty year has nothing', () {
      expect(earned(), isEmpty);
    });
  });

  group('🗓️ All year round', () {
    test('needs every month of the year', () {
      final elevenMonths = [
        for (var month = 1; month <= 11; month++)
          '2026-${'$month'.padLeft(2, '0')}-15',
      ];

      expect(
        keysOf(earned(activeDays: elevenMonths)),
        isNot(contains('allYearRound')),
      );

      expect(
        keysOf(earned(activeDays: [...elevenMonths, '2026-12-15'])),
        contains('allYearRound'),
      );
    });

    test('is read from days out, not from new species', () {
      // A month in which only species you already had that year were heard is
      // still a month you went outside.
      final everyMonth = [
        for (var month = 1; month <= 12; month++)
          '2026-${'$month'.padLeft(2, '0')}-15',
      ];

      expect(
        keysOf(earned(yearList: const [], activeDays: everyMonth)),
        contains('allYearRound'),
      );
    });

    test('days from another year do not count towards it', () {
      final mixed = [
        for (var month = 1; month <= 11; month++)
          '2026-${'$month'.padLeft(2, '0')}-15',
        '2025-12-15',
      ];

      expect(
        keysOf(earned(activeDays: mixed)),
        isNot(contains('allYearRound')),
      );
    });
  });

  group('🐦 The returners', () {
    test('needs ten species first heard in spring', () {
      expect(
        keysOf(earned(yearList: inMonth(4, 9))),
        isNot(contains('theReturners')),
      );
      expect(
        keysOf(earned(yearList: inMonth(4, 10))),
        contains('theReturners'),
      );
    });

    test('spring is March to May inclusive', () {
      for (final month in [3, 4, 5]) {
        expect(
          keysOf(earned(yearList: inMonth(month, 10))),
          contains('theReturners'),
          reason: 'month $month',
        );
      }
    });

    test('February and June are not spring', () {
      for (final month in [2, 6]) {
        expect(
          keysOf(earned(yearList: inMonth(month, 12))),
          isNot(contains('theReturners')),
          reason: 'month $month',
        );
      }
    });

    test('a mixed year counts only the spring arrivals', () {
      final list = [
        ...inMonth(4, 6, prefix: 'a'),
        ...inMonth(8, 20, prefix: 'b'),
      ];

      expect(keysOf(earned(yearList: list)), isNot(contains('theReturners')));
    });
  });

  group('❄️ Winter visitors', () {
    test('needs five species in December or January', () {
      expect(
        keysOf(earned(yearList: inMonth(1, 4))),
        isNot(contains('winterVisitors')),
      );
      expect(
        keysOf(earned(yearList: inMonth(1, 5))),
        contains('winterVisitors'),
      );
    });

    test('the two months add up together', () {
      // They straddle a year boundary in reality — that is one winter — but a
      // year list can only see its own year, so both halves count within it.
      final list = [
        ...inMonth(1, 3, prefix: 'jan'),
        ...inMonth(12, 2, prefix: 'dec'),
      ];

      expect(keysOf(earned(yearList: list)), contains('winterVisitors'));
    });

    test('November and February are not winter for this badge', () {
      final list = [
        ...inMonth(11, 5, prefix: 'nov'),
        ...inMonth(2, 5, prefix: 'feb'),
      ];

      expect(keysOf(earned(yearList: list)), isNot(contains('winterVisitors')));
    });
  });

  group('they are all independent', () {
    test('a full year earns everything at once', () {
      final list = [
        ...inMonth(1, 5, prefix: 'w'),
        ...inMonth(4, 10, prefix: 'sp'),
        ...inMonth(7, 60, prefix: 'su'),
      ];
      final everyMonth = [
        for (var month = 1; month <= 12; month++)
          '2026-${'$month'.padLeft(2, '0')}-15',
      ];

      expect(
        keysOf(earned(yearList: list, activeDays: everyMonth)),
        containsAll({
          'yearListI',
          'yearListII',
          'yearListIII',
          'allYearRound',
          'theReturners',
          'winterVisitors',
        }),
      );
    });
  });
}
