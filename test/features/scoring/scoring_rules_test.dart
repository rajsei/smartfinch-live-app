// =============================================================================
// ScoringRules — tests
// =============================================================================
//
// The worked examples from §2.7 of the specification, checked against the
// configuration rather than against the engine. They belong here because they
// are what the *numbers* are supposed to produce — if the engine later gets
// them wrong, these still say what right looks like.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';

void main() {
  const rules = ScoringRules.current;

  group('§2.3 · levels to points', () {
    test('runs 50 to 1000 across the six tiers', () {
      expect(rules.starsFor(ExploreTier.abundant), 50);
      expect(rules.starsFor(ExploreTier.common), 100);
      expect(rules.starsFor(ExploreTier.frequent), 200);
      expect(rules.starsFor(ExploreTier.uncommon), 350);
      expect(rules.starsFor(ExploreTier.scarce), 600);
      expect(rules.starsFor(ExploreTier.rare), 1000);
    });

    test('the commonest tier is the cheapest, not the dearest', () {
      // The direction is the easiest thing in the whole system to get
      // backwards: `ExploreTier` runs rare → abundant, the specification's
      // table runs common → rare. Reversed, every blackbird is a sensation and
      // the mistake looks plausible in a debug print.
      expect(
        rules.starsFor(ExploreTier.abundant),
        lessThan(rules.starsFor(ExploreTier.rare)),
      );
    });

    test('values rise monotonically as species get rarer', () {
      var previous = 0;
      for (final tier in ExploreTier.values.reversed) {
        final stars = rules.starsFor(tier);
        expect(stars, greaterThan(previous), reason: 'at $tier');
        previous = stars;
      }
    });

    test('the spread is 1:20, the deliberate compression', () {
      // A hoopoe really is a thousand times rarer than a blackbird. In the game
      // it may only be worth twenty times as much, or a child with an
      // inner-city courtyard is shut out (principle 3).
      expect(
        rules.starsFor(ExploreTier.rare) / rules.starsFor(ExploreTier.abundant),
        20,
      );
    });

    test('every tier has a value', () {
      for (final tier in ExploreTier.values) {
        expect(() => rules.starsFor(tier), returnsNormally, reason: '$tier');
      }
    });
  });

  group('§2.5 · only the highest multiplier applies (PKT-07)', () {
    test('an ordinary repeat has no multiplier', () {
      expect(
        rules.multiplierFor(
          isFirstFind: false,
          isYearFirst: false,
          daysThisWeekWithSpecies: 2,
        ),
        ScoreMultiplier.none,
      );
    });

    test('a first find beats a year first rather than stacking with it', () {
      // Stacked, this would be 1000 × 3 × 2 = 6,000 and the curve would come
      // apart. The rule caps the maximum per species per day at 3,000.
      final multiplier = rules.multiplierFor(
        isFirstFind: true,
        isYearFirst: true,
        daysThisWeekWithSpecies: 3,
      );

      expect(multiplier, ScoreMultiplier.firstFind);
      expect(multiplier.factor, 3);
    });

    test('the ceiling is ×3 under every combination', () {
      for (final firstFind in [true, false]) {
        for (final yearFirst in [true, false]) {
          for (var day = 1; day <= 7; day++) {
            final multiplier = rules.multiplierFor(
              isFirstFind: firstFind,
              isYearFirst: yearFirst,
              daysThisWeekWithSpecies: day,
            );
            expect(
              multiplier.factor,
              lessThanOrEqualTo(3),
              reason: 'first=$firstFind year=$yearFirst day=$day',
            );
          }
        }
      }
    });

    test('loyalty applies on the 3rd and 6th day, not in between', () {
      ScoreMultiplier onDay(int day) => rules.multiplierFor(
        isFirstFind: false,
        isYearFirst: false,
        daysThisWeekWithSpecies: day,
      );

      // The rising shape 1, 1, ×2, 1, 1, ×3, 1 builds towards the weekend
      // rather than peaking mid-week.
      expect(onDay(1), ScoreMultiplier.none);
      expect(onDay(2), ScoreMultiplier.none);
      expect(onDay(3), ScoreMultiplier.regular);
      expect(onDay(4), ScoreMultiplier.none);
      expect(onDay(5), ScoreMultiplier.none);
      expect(onDay(6), ScoreMultiplier.permanentGuest);
      expect(onDay(7), ScoreMultiplier.none);
    });

    test('permanent guest outranks year first on the 6th day', () {
      expect(
        rules.multiplierFor(
          isFirstFind: false,
          isYearFirst: true,
          daysThisWeekWithSpecies: 6,
        ),
        ScoreMultiplier.permanentGuest,
      );
    });
  });

  group('§2.6 · variety bonuses are cumulative', () {
    test('nothing below the first threshold', () {
      expect(rules.varietyBonusFor(4), 0);
    });

    test('+50 at five species', () {
      expect(rules.varietyBonusFor(5), 50);
    });

    test('+200 at ten — the staircase, not a replacement', () {
      expect(rules.varietyBonusFor(10), 200);
    });

    test('500 at fifteen, exactly as §2.6 states', () {
      // "Reaching 15 species yields 50 + 150 + 300 = 500."
      expect(rules.varietyBonusFor(15), 500);
    });

    test('accumulates to the top threshold and then stops', () {
      expect(rules.varietyBonusFor(25), 50 + 150 + 300 + 500 + 750);
      expect(rules.varietyBonusFor(40), rules.varietyBonusFor(25));
    });

    test('never decreases as species are added', () {
      var previous = 0;
      for (var count = 0; count <= 30; count++) {
        final bonus = rules.varietyBonusFor(count);
        expect(bonus, greaterThanOrEqualTo(previous), reason: 'at $count');
        previous = bonus;
      }
    });
  });

  group('§2.8 · balancing sanity check', () {
    test('a garden day in May comes to 1,500 stars', () {
      // The specification's worked example: 45 minutes, 14 species —
      // 6 × L1, 6 × L2, 2 × L3 in that week.
      final base =
          6 * rules.starsFor(ExploreTier.abundant) +
          6 * rules.starsFor(ExploreTier.common) +
          2 * rules.starsFor(ExploreTier.frequent);
      final variety = rules.varietyBonusFor(14);

      expect(base, 1300);
      expect(variety, 200);
      expect(base + variety, 1500);
    });

    test('the same day as a very first day comes to 4,100', () {
      // Every species ×3, and the variety bonus is not multiplied — that is
      // the inflation guard in 2.6.
      final base =
          6 * rules.starsFor(ExploreTier.abundant) +
          6 * rules.starsFor(ExploreTier.common) +
          2 * rules.starsFor(ExploreTier.frequent);

      expect(base * 3 + rules.varietyBonusFor(14), 4100);
    });
  });

  group('early riser (B6)', () {
    test('applies before 09:00', () {
      expect(rules.qualifiesAsEarlyRiser(DateTime(2026, 5, 4, 8, 59)), isTrue);
    });

    test('does not apply at 09:00 or later', () {
      expect(rules.qualifiesAsEarlyRiser(DateTime(2026, 5, 4, 9)), isFalse);
      expect(rules.qualifiesAsEarlyRiser(DateTime(2026, 5, 4, 17)), isFalse);
    });

    test('the threshold is 09:00, chosen so a school walk qualifies', () {
      // At 07:00 this would be almost unreachable on a school day; the bonus is
      // deliberately a rhythm setter rather than a feat.
      expect(rules.earlyRiserBefore, 9);
      expect(rules.earlyRiserBonus.stars, 50);
    });
  });

  group('scoring floor (PKT-20)', () {
    test('the floor is the shipped default of 35', () {
      expect(rules.scoringThresholdFloor, 35);
    });

    test('scores at and above the floor', () {
      expect(rules.isScoring(threshold: 35, filterEnabled: true), isTrue);
      expect(rules.isScoring(threshold: 80, filterEnabled: true), isTrue);
    });

    test('pauses below the floor', () {
      expect(rules.isScoring(threshold: 34, filterEnabled: true), isFalse);
      expect(rules.isScoring(threshold: 5, filterEnabled: true), isFalse);
    });

    test('pauses when the species filter is off, whatever the threshold', () {
      expect(rules.isScoring(threshold: 90, filterEnabled: false), isFalse);
    });

    test('the rule is asymmetric on purpose', () {
      // Raising the threshold is always allowed: a stricter bar produces fewer
      // and safer detections and cannot be abused. Only lowering pauses.
      // One sentence for the settings screen: "higher is always allowed,
      // lower means no stars".
      expect(rules.isScoring(threshold: 100, filterEnabled: true), isTrue);
      expect(rules.isScoring(threshold: 0, filterEnabled: true), isFalse);
    });
  });

  group('versioning', () {
    test('carries a version for every ScoreEvent to record', () {
      expect(rules.version, greaterThan(0));
    });

    test('bonus keys are unique — they double as badge keys', () {
      final keys = [
        ...rules.varietyBonuses.values.map((b) => b.key),
        rules.earlyRiserBonus.key,
        rules.newPlaceBonus.key,
        rules.weekWrapUpBonus.key,
      ];

      expect(keys.toSet(), hasLength(keys.length));
    });
  });
}
