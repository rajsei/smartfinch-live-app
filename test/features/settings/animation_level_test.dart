// =============================================================================
// AnimationLevel — SET-02, SET-03
// =============================================================================
//
// The rule worth protecting is not which level shows what. It is that **no
// level removes the information**: a first find is still a first find at every
// setting, and only the celebration is optional.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/settings/animation_level.dart';

void main() {
  group('SET-02 · the three levels', () {
    test('Full shows confetti and the card', () {
      expect(AnimationLevel.full.allowsConfetti, isTrue);
      expect(AnimationLevel.full.allowsSpeciesCard, isTrue);
    });

    test('Reduced shows the confetti and not the card', () {
      expect(AnimationLevel.reduced.allowsConfetti, isTrue);
      expect(AnimationLevel.reduced.allowsSpeciesCard, isFalse);
    });

    test('Off shows neither', () {
      expect(AnimationLevel.off.allowsConfetti, isFalse);
      expect(AnimationLevel.off.allowsSpeciesCard, isFalse);
    });

    test('the card never appears without the confetti', () {
      // Not a rule anyone wrote down, but a card with no confetti behind it
      // would read as a bug rather than as a reduced setting.
      for (final level in AnimationLevel.values) {
        if (level.allowsSpeciesCard) {
          expect(level.allowsConfetti, isTrue, reason: '$level');
        }
      }
    });
  });

  group('reading the stored value', () {
    test('round-trips every level', () {
      for (final level in AnimationLevel.values) {
        expect(AnimationLevel.fromStorage(level.storageValue), level);
      }
    });

    test('an unknown value means Full, not Off', () {
      // A corrupted preference must not silently switch the celebrations off:
      // a child would have no way to connect the two.
      expect(AnimationLevel.fromStorage(null), AnimationLevel.full);
      expect(AnimationLevel.fromStorage(''), AnimationLevel.full);
      expect(AnimationLevel.fromStorage('nonsense'), AnimationLevel.full);
    });
  });

  group('SET-03 · the system reduce-motion preference', () {
    test('pulls Full down to Reduced', () {
      expect(
        effectiveAnimationLevel(AnimationLevel.full, systemReducesMotion: true),
        AnimationLevel.reduced,
      );
    });

    test('leaves an explicit Off alone', () {
      // Someone who asked for no animation at all gets none — the system
      // preference can only reduce, never restore.
      expect(
        effectiveAnimationLevel(AnimationLevel.off, systemReducesMotion: true),
        AnimationLevel.off,
      );
    });

    test('changes nothing when the system does not ask', () {
      for (final level in AnimationLevel.values) {
        expect(
          effectiveAnimationLevel(level, systemReducesMotion: false),
          level,
        );
      }
    });

    test('it is not written back to the setting', () {
      // Turning the system preference off restores what the child chose,
      // rather than what the phone decided for them — which is only true
      // because the stored value is never overwritten.
      const stored = AnimationLevel.full;

      expect(
        effectiveAnimationLevel(stored, systemReducesMotion: true),
        AnimationLevel.reduced,
      );
      expect(
        effectiveAnimationLevel(stored, systemReducesMotion: false),
        AnimationLevel.full,
      );
    });
  });
}
