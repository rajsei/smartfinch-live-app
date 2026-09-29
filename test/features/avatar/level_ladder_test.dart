// =============================================================================
// The level ladder and the bird on it — STAT-07, AVA-01, AVA-02, AVA-07, AUS-12
// =============================================================================
//
// The ladder is a formula, which sounds like the kind of thing that cannot be
// got wrong. Four ways it can:
//
//   ⚠️ **The ratchet.** A level is a threshold on the star total, and a
//   rebalancing can lower that total. Deriving the level from today's stars
//   alone would demote a child after a rule change they had nothing to do with
//   — and take a sticker pick and the avatar stage with it. `AUS-12` and
//   principle 1 both forbid it, so the stored floor wins.
//
//   **The boundaries.** Exactly at a threshold is the new level, not the old
//   one — on both sides of the switch from quadratic to linear.
//
//   **The inverse.** `levelForStars` solves the linear part directly; if it
//   disagrees with `starsForLevel` anywhere, a child's level flickers.
//
//   **The titles.** They span several levels now and must keep §3.5's pace.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/avatar/level_ladder.dart';

void main() {
  group('the curve: 250 · n², at most 5,000 a level', () {
    test('the table the decision was made on', () {
      expect(starsForLevel(0), 0);
      expect(starsForLevel(1), 250);
      expect(starsForLevel(2), 1000);
      expect(starsForLevel(3), 2250);
      expect(starsForLevel(5), 6250);
      expect(starsForLevel(10), 25000);
      expect(starsForLevel(15), 50000);
      expect(starsForLevel(20), 75000);
      expect(starsForLevel(30), 125000);
    });

    test('below zero is zero', () {
      expect(starsForLevel(-3), 0);
    });

    test('thresholds rise, and no step is ever more than the cap', () {
      for (var n = 1; n <= 200; n++) {
        final step = starsForLevel(n) - starsForLevel(n - 1);
        expect(step, greaterThan(0), reason: 'level $n');
        expect(step, lessThanOrEqualTo(kLevelStepCap), reason: 'level $n');
      }
    });

    test('from level 10 on every level costs the same', () {
      for (var n = 11; n <= 200; n++) {
        expect(starsForLevel(n) - starsForLevel(n - 1), kLevelStepCap);
      }
    });
  });

  group('levelForStars', () {
    test('an empty account is level 0, the egg', () {
      final level = levelForStars(0);
      expect(level.number, 0);
      expect(level.key, 'egg');
    });

    test('exactly at a threshold is the new level, not the old one', () {
      expect(levelForStars(249).number, 0);
      expect(levelForStars(250).number, 1);
      expect(levelForStars(999).number, 1);
      expect(levelForStars(1000).number, 2);
    });

    test('and across the switch to linear', () {
      expect(levelForStars(24999).number, 9);
      expect(levelForStars(25000).number, 10);
      expect(levelForStars(29999).number, 10);
      expect(levelForStars(30000).number, 11);
    });

    test('is the exact inverse of starsForLevel', () {
      for (var n = 0; n <= 300; n++) {
        final from = starsForLevel(n);
        expect(levelForStars(from).number, n, reason: 'at $from');
        if (from > 0) {
          expect(levelForStars(from - 1).number, n - 1, reason: 'below $from');
        }
      }
    });

    test('the ladder has no top', () {
      expect(levelForStars(10000000).number, greaterThan(1000));
    });
  });

  group('the titles keep the pace of 3.5', () {
    test('egg is level 0 alone', () {
      expect(titleKeyForLevel(0), 'egg');
      for (var n = 1; n <= 200; n++) {
        expect(titleKeyForLevel(n), isNot('egg'), reason: 'level $n');
      }
    });

    test('the bands', () {
      // Each title from the first level whose own threshold has passed the
      // star count §3.5 gave it.
      const bands = {
        1: 'chick',
        2: 'chick',
        3: 'nestling',
        4: 'fledgling',
        6: 'youngBird',
        8: 'scout',
        10: 'listener',
        13: 'singer',
        17: 'territoryHolder',
        23: 'farFlier',
        31: 'migrant',
        42: 'returner',
        57: 'oldBird',
        77: 'flockLeader',
        105: 'legend',
        500: 'legend',
      };
      bands.forEach((level, key) {
        expect(titleKeyForLevel(level), key, reason: 'level $level');
      });
      expect(titleKeyForLevel(104), 'flockLeader');
    });

    test('titles never go backwards along the ladder', () {
      final order = [for (final t in kLevelTitles) t.key];
      var seen = 0;
      for (var n = 0; n <= 200; n++) {
        final index = order.indexOf(titleKeyForLevel(n));
        expect(index, greaterThanOrEqualTo(seen), reason: 'level $n');
        seen = index;
      }
    });

    test('every title is reached', () {
      final reached = {for (var n = 0; n <= 200; n++) titleKeyForLevel(n)};
      expect(reached, {for (final t in kLevelTitles) t.key});
    });
  });

  group('⚠️ the ratchet (AUS-12)', () {
    test('a stored floor above the stars wins', () {
      // After a rebalancing lowered the total, or an older backup was
      // restored (SET-07). The child keeps the level.
      final progress = progressFor(stars: 100, highestLevelReached: 7);

      expect(progress.level.number, 7);
      expect(progress.isRatcheted, isTrue);
    });

    test('and keeps the title that goes with it', () {
      final progress = progressFor(stars: 100, highestLevelReached: 8);
      expect(progress.level.key, 'scout');
    });

    test('and the bar reads empty rather than negative', () {
      // A bar that went backwards would be the app telling a child they had
      // lost ground, which is the whole thing this defends against.
      final progress = progressFor(stars: 100, highestLevelReached: 7);

      expect(progress.fraction, 0);
      expect(progress.fraction, isNot(lessThan(0)));
    });

    test('a floor below the stars is simply ignored', () {
      // Which is what makes the stored value safe to write lazily.
      final progress = progressFor(stars: 60000, highestLevelReached: 2);

      expect(progress.level.number, 17);
      expect(progress.isRatcheted, isFalse);
    });

    test('an honest level is not marked as ratcheted', () {
      expect(progressFor(stars: 4000).isRatcheted, isFalse);
    });
  });

  group('progress to the next rung (STAT-07)', () {
    test('halfway between two rungs is half a bar', () {
      // Level 1 runs 250 → 1,000.
      final progress = progressFor(stars: 625);

      expect(progress.level.number, 1);
      expect(progress.fraction, closeTo(0.5, 1e-9));
      expect(progress.starsToNext, 375);
    });

    test('the moment a level is reached the bar starts again', () {
      expect(progressFor(stars: 250).fraction, 0);
      expect(progressFor(stars: 999).fraction, closeTo(0.998, 0.001));
      expect(progressFor(stars: 1000).fraction, 0);
    });

    test('there is always a next level', () {
      final progress = progressFor(stars: 10000000);

      expect(progress.next.number, progress.level.number + 1);
      expect(progress.starsToNext, greaterThan(0));
    });

    test('the start is level 0 with level 1 ahead', () {
      final start = LevelProgress.start();

      expect(start.level.number, 0);
      expect(start.next.number, 1);
      expect(start.starsToNext, 250);
    });
  });

  group('AVA-02 · the stage follows the title', () {
    test('egg → chick → fledgling → adult, as the requirement words it', () {
      expect(stageForLevel(0), AvatarStage.egg);
      expect(stageForLevel(1), AvatarStage.chick);
      expect(stageForLevel(3), AvatarStage.chick);
      expect(stageForLevel(4), AvatarStage.fledgling);
      expect(stageForLevel(7), AvatarStage.fledgling);
      expect(stageForLevel(8), AvatarStage.adult);
      expect(stageForLevel(200), AvatarStage.adult);
    });

    test('it never goes backwards along the ladder', () {
      var seen = 0;
      for (var n = 0; n <= 200; n++) {
        final index = AvatarStage.values.indexOf(stageForLevel(n));
        expect(index, greaterThanOrEqualTo(seen));
        seen = index;
      }
    });

    test('every stage has a picture', () {
      for (final stage in AvatarStage.values) {
        expect(stage.emoji, isNotEmpty);
      }
    });

    test('the stage a child sees comes through the ratchet too', () {
      // The avatar is the level made visible, so demoting the level would
      // demote the bird — the loss AVA-02 and AUS-12 are paired against.
      expect(
        progressFor(stars: 0, highestLevelReached: 8).stage,
        AvatarStage.adult,
      );
    });
  });
}
