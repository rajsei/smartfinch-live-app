// =============================================================================
// GridCell — tests
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/services/grid_cell.dart';

void main() {
  group('rounding', () {
    test('two points a few hundred metres apart share a cell', () {
      // ~300 m apart in Chemnitz. The whole point of coarsening: walking
      // around the block must not change what a bird is worth.
      final a = GridCell.fromCoordinates(50.8322, 12.9252);
      final b = GridCell.fromCoordinates(50.8349, 12.9281);

      expect(a, b);
      expect(a.storageKey, '50.8,12.9');
    });

    test('a cell is about 11 km of latitude across', () {
      // 0.05° either side of the boundary lands in different cells; the
      // boundary itself is what "a different place" means to the app.
      expect(
        GridCell.fromCoordinates(50.84, 12.9),
        isNot(GridCell.fromCoordinates(50.96, 12.9)),
      );
    });

    test('negative coordinates round consistently', () {
      final cell = GridCell.fromCoordinates(-33.87, 151.21);
      expect(cell.storageKey, '-33.9,151.2');
      expect(cell, GridCell.fromCoordinates(-33.885, 151.214));
    });

    test('equality is exact, not floating point', () {
      // Tenths are stored as ints on purpose: 0.1 * 508 is not 50.8 in binary
      // floating point, and a cache key that compares unequal to itself would
      // rebuild the scale on every single lookup.
      final a = GridCell.fromCoordinates(50.8, 12.9);
      final b = GridCell.fromCoordinates(50.8, 12.9);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect({a, b}, hasLength(1));
    });
  });

  group('storage round trip', () {
    test('parses back what it wrote', () {
      final original = GridCell.fromCoordinates(50.8322, 12.9252);
      expect(GridCell.tryParse(original.storageKey), original);
    });

    test('degrades to null rather than throwing', () {
      // A corrupt row must not take down a scoring pass.
      for (final bad in [null, '', 'nonsense', '50.8', '50.8,12.9,7', 'a,b']) {
        expect(GridCell.tryParse(bad), isNull, reason: 'input: $bad');
      }
    });
  });

  test('the representative point is the cell, not the original fix', () {
    // What the geo model is asked about is the cell, so two children in the
    // same cell get identical predictions — and identical star values.
    final a = GridCell.fromCoordinates(50.8322, 12.9252);
    final b = GridCell.fromCoordinates(50.8401, 12.9101);

    expect(a, b);
    expect(a.latitude, b.latitude);
    expect(a.longitude, b.longitude);
  });
}
