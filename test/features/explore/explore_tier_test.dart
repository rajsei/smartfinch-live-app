// Tests for the distribution-adaptive Explore abundance tiers.

import 'package:smartfinch/features/explore/explore_tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExploreTierScale', () {
    test('thresholds are monotonically non-decreasing rare to abundant', () {
      final scores = List<double>.generate(100, (i) => (i + 1) / 100);
      final scale = ExploreTierScale.fromScores(scores);

      double previous = -1;
      for (final tier in ExploreTier.values) {
        final min = scale.minRawFor(tier);
        expect(min, greaterThanOrEqualTo(previous));
        previous = min;
      }
    });

    test('top species in a confident area is abundant', () {
      // Many high scores clustered near the top (Ithaca-like).
      final scores = [
        for (var i = 0; i < 40; i++) 0.90 + (i % 10) * 0.01,
        for (var i = 0; i < 60; i++) 0.10 + (i % 20) * 0.01,
      ];
      final scale = ExploreTierScale.fromScores(scores);
      expect(scale.tierFor(0.99), ExploreTier.abundant);
    });

    test(
      'a confident area demands a high score for abundant (raises the bar)',
      () {
        final scores = [
          for (var i = 0; i < 50; i++) 0.92 + (i % 8) * 0.01,
          for (var i = 0; i < 50; i++) 0.20,
        ];
        final scale = ExploreTierScale.fromScores(scores);
        // A merely "good" 0.85 should not be abundant when the top cluster is
        // packed at 0.92+.
        expect(scale.tierFor(0.85), isNot(ExploreTier.abundant));
      },
    );

    test('absolute floor prevents a weak area from minting abundant', () {
      // Sparse area: best guess is only 0.15.
      final scores = [
        0.15,
        for (var i = 0; i < 30; i++) 0.03 + (i % 5) * 0.005,
      ];
      final scale = ExploreTierScale.fromScores(scores);
      // Below the 0.20 abundant floor, so even the top species is not abundant.
      expect(scale.tierFor(0.15), isNot(ExploreTier.abundant));
    });

    test('empty list yields a well-defined fallback scale', () {
      final scale = ExploreTierScale.fromScores(const []);
      expect(scale.tierFor(1.0), ExploreTier.abundant);
      expect(scale.tierFor(0.0), ExploreTier.rare);
    });

    test('tierFor spans all tiers across a spread distribution', () {
      final scores = List<double>.generate(200, (i) => i / 199);
      final scale = ExploreTierScale.fromScores(scores);
      final produced = scores.map(scale.tierFor).toSet();
      expect(produced.length, ExploreTier.values.length);
    });
  });

  group('ExploreTier', () {
    test('fill fraction increases with abundance', () {
      expect(ExploreTier.rare.fillFraction, closeTo(1 / 6, 1e-9));
      expect(ExploreTier.abundant.fillFraction, 1.0);
    });

    test('ramp position spans 0..1', () {
      expect(ExploreTier.rare.rampPosition, 0.0);
      expect(ExploreTier.abundant.rampPosition, 1.0);
    });
  });
}
