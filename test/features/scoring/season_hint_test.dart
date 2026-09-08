// =============================================================================
// SeasonHint — PKT-17
// =============================================================================
//
// The hint's value is entirely in *when it stays quiet*. One that fires for a
// blackbird in February teaches a child something false; one that fires for
// four months of the year is wallpaper. So most of these tests are about the
// cases where nothing should be said.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/scoring/season_hint.dart';

void main() {
  /// A 48-week curve that is high between [fromWeek] and [toWeek] inclusive
  /// and near zero elsewhere.
  ///
  /// Weeks are the geo model's 1–48, four per calendar month.
  List<double> season(int fromWeek, int toWeek) => [
    for (var week = 1; week <= 48; week++)
      (fromWeek <= toWeek
              ? week >= fromWeek && week <= toWeek
              // A season that wraps the new year.
              : week >= fromWeek || week <= toWeek)
          ? 0.8
          : 0.01,
  ];

  /// A bird that is here all year, like a blackbird.
  List<double> resident() => List.filled(48, 0.7);

  group('it stays quiet when there is nothing to say', () {
    test('a resident species never gets a hint', () {
      // Hearing a blackbird in February is not remarkable, and saying it is
      // would teach a child something false.
      for (var week = 1; week <= 48; week++) {
        expect(
          seasonHintFor(weeklyScores: resident(), currentWeek: week),
          isNull,
          reason: 'week $week',
        );
      }
    });

    test('a species in the middle of its season gets none', () {
      // April–August is weeks 13–32; week 22 is the middle of it.
      expect(
        seasonHintFor(weeklyScores: season(13, 32), currentWeek: 22),
        isNull,
      );
    });

    test('nor anywhere inside it', () {
      for (var week = 13; week <= 32; week++) {
        expect(
          seasonHintFor(weeklyScores: season(13, 32), currentWeek: week),
          isNull,
          reason: 'week $week',
        );
      }
    });

    test('a species with no data at all gets none', () {
      expect(
        seasonHintFor(weeklyScores: List.filled(48, 0), currentWeek: 10),
        isNull,
      );
    });

    test('a malformed curve is ignored rather than guessed at', () {
      expect(
        seasonHintFor(weeklyScores: const [0.5, 0.5], currentWeek: 1),
        isNull,
      );
    });
  });

  group('early — the season is still coming', () {
    test('a spring migrant heard in February', () {
      // Season April–August (weeks 13–32); week 6 is mid-February.
      final hint = seasonHintFor(weeklyScores: season(13, 32), currentWeek: 6);

      expect(hint, isNotNull);
      expect(hint!.phase, SeasonPhase.early);
      expect(hint.seasonStartMonth, 4, reason: 'April');
      expect(hint.relevantMonth, 4, reason: 'it names when it starts');
    });

    test('the week before the season starts is still early', () {
      final hint = seasonHintFor(weeklyScores: season(13, 32), currentWeek: 12);

      expect(hint!.phase, SeasonPhase.early);
    });
  });

  group('late — the season has passed', () {
    test('a summer visitor still here in September', () {
      // Season April–August; week 34 is early September.
      final hint = seasonHintFor(weeklyScores: season(13, 32), currentWeek: 34);

      expect(hint!.phase, SeasonPhase.late);
      expect(hint.seasonEndMonth, 8, reason: 'August');
      expect(hint.relevantMonth, 8, reason: 'it names when it ends');
    });

    test('the week after the season ends is late, not early', () {
      // The nearer edge decides, and just past the end the end is nearer.
      final hint = seasonHintFor(weeklyScores: season(13, 32), currentWeek: 33);

      expect(hint!.phase, SeasonPhase.late);
    });
  });

  group('a season that wraps the new year', () {
    // A winter visitor: November to February, weeks 41–48 and 1–8.
    List<double> winterVisitor() => season(41, 8);

    test('is not a hint in January', () {
      expect(
        seasonHintFor(weeklyScores: winterVisitor(), currentWeek: 2),
        isNull,
      );
      expect(
        seasonHintFor(weeklyScores: winterVisitor(), currentWeek: 46),
        isNull,
      );
    });

    test('names November as the start, not January', () {
      // The season has no lowest week that means "start" — the boundary is
      // where the previous week is out of season, which is what makes a
      // wrapping season readable at all.
      final hint = seasonHintFor(
        weeklyScores: winterVisitor(),
        currentWeek: 24,
      );

      expect(hint, isNotNull);
      expect(hint!.seasonStartMonth, 11, reason: 'November');
      expect(hint.seasonEndMonth, 2, reason: 'February');
    });
  });

  group('the season threshold', () {
    test('is half the species\' own peak', () {
      // Compared against itself, not against other species — which is what
      // makes the rule work for a rare bird and a common one alike.
      final curve = List<double>.filled(48, 0.2);
      curve[20] = 1.0; // one strong week
      curve[21] = 0.6; // above half
      curve[22] = 0.4; // below half

      expect(seasonHintFor(weeklyScores: curve, currentWeek: 21), isNull);
      expect(seasonHintFor(weeklyScores: curve, currentWeek: 22), isNull);
      expect(seasonHintFor(weeklyScores: curve, currentWeek: 23), isNotNull);
    });

    test('scaling the whole curve changes nothing', () {
      // Only the shape matters, so a normalised curve and a raw one give the
      // same answer.
      final raw = season(13, 32);
      final scaled = [for (final v in raw) v * 137];

      expect(
        seasonHintFor(weeklyScores: scaled, currentWeek: 6)?.phase,
        seasonHintFor(weeklyScores: raw, currentWeek: 6)?.phase,
      );
    });
  });

  group('monthOfGeoWeek', () {
    test('four weeks to a month, exactly', () {
      expect(monthOfGeoWeek(1), 1);
      expect(monthOfGeoWeek(4), 1);
      expect(monthOfGeoWeek(5), 2);
      expect(monthOfGeoWeek(48), 12);
    });

    test('is clamped rather than wrong at the edges', () {
      expect(monthOfGeoWeek(0), 1);
      expect(monthOfGeoWeek(99), 12);
    });
  });
}
