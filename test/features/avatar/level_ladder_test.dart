// =============================================================================
// The level ladder and the bird on it — STAT-07, AVA-01, AVA-02, AUS-12
// =============================================================================
//
// The ladder is a table of thresholds, which sounds like the kind of thing
// that cannot be got wrong. Three ways it can:
//
//   ⚠️ **The ratchet.** A level is a threshold on the star total, and a
//   rebalancing can lower that total. Deriving the level from today's stars
//   alone would demote a child after a rule change they had nothing to do with
//   — and take the avatar stage with it. `AUS-12` and principle 1 both forbid
//   it, so the stored floor wins.
//
//   **The boundaries.** Exactly at a threshold is the new level, not the old
//   one. Off by one and a child watches the bar sit at 100 % for a while.
//
//   **The top.** At level 15 there is nothing above, and "0 stars to the next
//   level" would read as a bug rather than as having finished the ladder.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/avatar/level_ladder.dart';

void main() {
  group('the ladder itself', () {
    test('is the fifteen rungs of 3.5, in order', () {
      expect(kLevelLadder, hasLength(15));
      expect(kLevelLadder.first.number, 1);
      expect(kLevelLadder.last.number, 15);

      for (var i = 1; i < kLevelLadder.length; i++) {
        expect(
          kLevelLadder[i].fromStars,
          greaterThan(kLevelLadder[i - 1].fromStars),
          reason: 'thresholds must rise',
        );
        expect(kLevelLadder[i].number, kLevelLadder[i - 1].number + 1);
      }
    });

    test('every rung has its own name', () {
      final keys = {for (final level in kLevelLadder) level.key};
      expect(keys, hasLength(kLevelLadder.length));
    });
  });

  group('levelForStars', () {
    test('an empty account is the egg', () {
      expect(levelForStars(0).key, 'egg');
    });

    test('exactly at a threshold is the new level, not the old one', () {
      expect(levelForStars(499).number, 1);
      expect(levelForStars(500).number, 2);
      expect(levelForStars(1500).number, 3);
    });

    test('past the top of the ladder stays at the top', () {
      expect(levelForStars(500000).number, 15);
      expect(levelForStars(9999999).number, 15);
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

      expect(progress.level.number, 9);
      expect(progress.isRatcheted, isFalse);
    });

    test('an honest level is not marked as ratcheted', () {
      expect(progressFor(stars: 4000).isRatcheted, isFalse);
    });
  });

  group('progress to the next rung (STAT-07)', () {
    test('halfway between two rungs is half a bar', () {
      // Level 2 runs 500 → 1,500.
      final progress = progressFor(stars: 1000);

      expect(progress.level.number, 2);
      expect(progress.fraction, closeTo(0.5, 1e-9));
      expect(progress.starsToNext, 500);
    });

    test('the moment a level is reached the bar starts again', () {
      expect(progressFor(stars: 500).fraction, 0);
      expect(progressFor(stars: 1499).fraction, closeTo(0.999, 0.001));
      expect(progressFor(stars: 1500).fraction, 0);
    });

    test('the top of the ladder is full, and has nothing above it', () {
      final progress = progressFor(stars: 500000);

      expect(progress.next, isNull);
      expect(progress.fraction, 1);
      // Not "0 stars to the next level" — there is no next level.
      expect(progress.starsToNext, 0);
    });
  });

  group('AVA-02 · the stage follows the level', () {
    test('egg → chick → fledgling → adult, as the requirement words it', () {
      expect(stageForLevel(1), AvatarStage.egg);
      expect(stageForLevel(2), AvatarStage.chick);
      expect(stageForLevel(3), AvatarStage.chick);
      expect(stageForLevel(4), AvatarStage.fledgling);
      expect(stageForLevel(5), AvatarStage.fledgling);
      expect(stageForLevel(6), AvatarStage.adult);
      expect(stageForLevel(15), AvatarStage.adult);
    });

    test('it never goes backwards along the ladder', () {
      var seen = 0;
      for (final level in kLevelLadder) {
        final index = AvatarStage.values.indexOf(stageForLevel(level.number));
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
        progressFor(stars: 0, highestLevelReached: 6).stage,
        AvatarStage.adult,
      );
    });
  });
}
