// =============================================================================
// RarityScaleCache — tests
// =============================================================================
//
// The cache is not an optimisation detail: building a scale costs 48 ONNX
// inferences, and a live session must never wait on that (principle 7). These
// tests count how often the model is actually asked, because "it still returns
// the right answer" would pass just as well with the cache broken.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/inference/geo_model.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';

/// A geo model that answers instantly and counts how often it was asked.
class _CountingGeoModel extends GeoModel {
  int callCount = 0;
  final List<(double, double)> askedFor = [];

  /// Fixed scores, so a tier is predictable: one abundant species, a mid
  /// field, and one below the inclusion threshold.
  static final Map<String, double> _scores = {
    'Turdus merula': 0.95,
    'Parus major': 0.80,
    'Sitta europaea': 0.30,
    'Certhia familiaris': 0.12,
    'Dryocopus martius': 0.06,
    'Upupa epops': 0.001, // below kAbundanceInclusionThreshold — off the list
  };

  @override
  Future<Map<String, List<double>>> predictAllWeeks({
    required double latitude,
    required double longitude,
  }) async {
    callCount++;
    askedFor.add((latitude, longitude));
    return {
      for (final e in _scores.entries) e.key: List<double>.filled(48, e.value),
    };
  }
}

void main() {
  late _CountingGeoModel model;
  late RarityScaleCache cache;

  const cellA = GridCell(508, 129); // 50.8, 12.9
  const cellB = GridCell(521, 134); // 52.1, 13.4 — a different place

  setUp(() {
    model = _CountingGeoModel();
    cache = RarityScaleCache(model);
  });

  group('rebuild policy', () {
    test('the same cell and week is built once', () async {
      const key = RarityScaleKey(cellA, 18);

      await cache.get(key);
      await cache.get(key);
      await cache.get(key);

      expect(
        model.callCount,
        1,
        reason: 'a cached scale must not cost 48 inferences again',
      );
    });

    test('a different cell rebuilds', () async {
      await cache.get(const RarityScaleKey(cellA, 18));
      await cache.get(const RarityScaleKey(cellB, 18));

      expect(model.callCount, 2);
    });

    test('a different week rebuilds', () async {
      await cache.get(const RarityScaleKey(cellA, 18));
      await cache.get(const RarityScaleKey(cellA, 19));

      expect(model.callCount, 2);
    });

    test('the model is asked about the cell, not a precise fix', () async {
      await cache.get(const RarityScaleKey(cellA, 18));

      expect(model.askedFor.single, (50.8, 12.9));
    });

    test('concurrent callers share one inference run', () async {
      const key = RarityScaleKey(cellA, 18);

      // Explore and a detection can ask at the same moment. Without in-flight
      // tracking that is two full runs for one answer.
      final results = await Future.wait([
        cache.get(key),
        cache.get(key),
        cache.get(key),
      ]);

      expect(model.callCount, 1);
      expect(results[0].rawScores, same(results[1].rawScores));
    });
  });

  group('peek — what a detection uses', () {
    test('returns null rather than building', () async {
      expect(cache.peek(const RarityScaleKey(cellA, 18)), isNull);
      expect(
        model.callCount,
        0,
        reason: 'peek must never block the audio pipeline on 48 inferences',
      );
    });

    test('returns a scale once it is built', () async {
      const key = RarityScaleKey(cellA, 18);
      await cache.get(key);

      expect(cache.peek(key), isNotNull);
      expect(model.callCount, 1);
    });
  });

  group('LRU eviction', () {
    test('keeps the most recent scales and drops the oldest', () async {
      cache = RarityScaleCache(model, maxEntries: 2);

      await cache.get(const RarityScaleKey(cellA, 18));
      await cache.get(const RarityScaleKey(cellB, 18));
      await cache.get(const RarityScaleKey(cellA, 19));

      expect(cache.size, 2);
      expect(
        cache.peek(const RarityScaleKey(cellA, 18)),
        isNull,
        reason: 'the oldest entry should have been evicted',
      );
      expect(cache.peek(const RarityScaleKey(cellA, 19)), isNotNull);
    });

    test('a re-used scale survives eviction', () async {
      cache = RarityScaleCache(model, maxEntries: 2);
      const home = RarityScaleKey(cellA, 18);

      await cache.get(home);
      await cache.get(const RarityScaleKey(cellB, 18));
      cache.peek(home); // the child comes home — this is the LRU touch
      await cache.get(const RarityScaleKey(cellA, 19));

      expect(
        cache.peek(home),
        isNotNull,
        reason: 'a route that crosses a boundary must not thrash the cache',
      );
    });
  });

  group('tiers', () {
    test('the top species lands in the abundant tier', () async {
      final scale = await cache.get(const RarityScaleKey(cellA, 18));
      expect(scale.tierFor('Turdus merula'), ExploreTier.abundant);
    });

    test(
      'a species below the inclusion threshold has no tier at all',
      () async {
        final scale = await cache.get(const RarityScaleKey(cellA, 18));

        // Null means "scores nothing" (2.3, D20) — not "top tier". The off-list
        // rule that awarded full points is gone; rule and filter now agree.
        expect(scale.tierFor('Upupa epops'), isNull);
      },
    );

    test('an unknown species has no tier', () async {
      final scale = await cache.get(const RarityScaleKey(cellA, 18));
      expect(scale.tierFor('Struthio camelus'), isNull);
    });

    test('rarer species never rank above commoner ones', () async {
      final scale = await cache.get(const RarityScaleKey(cellA, 18));

      final blackbird = scale.tierFor('Turdus merula')!;
      final nuthatch = scale.tierFor('Sitta europaea')!;
      final woodpecker = scale.tierFor('Dryocopus martius')!;

      // Tier index runs 0 = rare … 5 = abundant, so a commoner bird has the
      // higher index — and therefore the lower star value.
      expect(blackbird.index, greaterThanOrEqualTo(nuthatch.index));
      expect(nuthatch.index, greaterThanOrEqualTo(woodpecker.index));
    });
  });

  test('clear() empties the cache', () async {
    await cache.get(const RarityScaleKey(cellA, 18));
    cache.clear();

    expect(cache.size, 0);
    expect(cache.peek(const RarityScaleKey(cellA, 18)), isNull);
  });

  group('RarityScaleKey', () {
    test('derives the geo week from a date', () {
      // Geo weeks are four per calendar month, not ISO weeks.
      final key = RarityScaleKey.at(cellA, DateTime(2026, 5, 4));
      expect(key.geoWeek, GeoModel.dateTimeToWeek(DateTime(2026, 5, 4)));
    });

    test('is usable as a map key', () {
      // Built rather than written as a literal: the analyzer folds identical
      // const expressions and would flag the set as a duplicate, which hides
      // the thing being tested — that two *separately built* keys collapse.
      final first = RarityScaleKey(GridCell.fromCoordinates(50.83, 12.92), 18);
      final second = RarityScaleKey(GridCell.fromCoordinates(50.84, 12.91), 18);

      expect(first, second);
      expect({first, second}, hasLength(1));
    });
  });
}
