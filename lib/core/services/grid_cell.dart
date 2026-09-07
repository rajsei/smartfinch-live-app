// =============================================================================
// GridCell — the app's one notion of "roughly here"
// =============================================================================
//
// A 0.1° cell: 11.1 km of latitude everywhere, ~7 km of longitude at German
// latitudes. Every part of the app that needs a location uses this and nothing
// finer (D23).
//
// ### Why coarsen at all — three reasons, in order of weight
//
// 1. **Privacy (NFA-08).** Every `ScoreEvent` carries a location. Un-coarsened,
//    a year of them is a movement history of a child.
// 2. **It defines when the rarity scale is recomputed.** Building a scale costs
//    48 ONNX inferences. Without a cell there is no natural answer to "has the
//    child moved enough to matter?" — you would have to invent a distance rule.
//    The cell *is* that rule, and it doubles as the cache key.
// 3. **Stability of the point values.** Weakest of the three and worth stating
//    accurately: the geo model is trained on aggregated eBird checklists and is
//    far coarser than a kilometre, so a few hundred metres barely moves its
//    output. What could still flip is a species sitting exactly on a tier
//    boundary — the tiers are rank percentiles, so a hair's-breadth change in
//    order can move one species one tier. Rare, small, and unexplainable when
//    it happens, which is what principle 6 objects to.
//
// ### Why 0.1° and not something else
//
// It satisfies NFA-08's 5–10 km, and it is what the weather cache already
// rounds to — so the app keeps *one* notion of "roughly here" rather than two.
// Finer would localise a child too precisely and recompute the scale a hundred
// times as often for the same answer; coarser (1° ≈ 111 km) would put a weekend
// trip in the same cell as the garden, and principle 4 — curiosity is rewarded,
// not runtime — only works if going somewhere gives a different species list.
//
// `PKT-13`'s "new place" bonus uses this same grid rather than the separate
// 5 km one the specification originally named: two definitions of "a different
// place" in one app is a bug waiting to happen.
// =============================================================================

import 'package:flutter/foundation.dart';

/// A coarsened location: everything within one 0.1° cell is "the same place".
@immutable
class GridCell {
  const GridCell(this.latTenths, this.lonTenths);

  /// Rounds a coordinate to the cell that contains it.
  ///
  /// Tenths are stored as integers rather than doubles so equality and hashing
  /// are exact — `0.1 * 508` is not `50.8` in binary floating point, and a
  /// cache keyed on a value that compares unequal to itself would rebuild the
  /// scale on every lookup.
  factory GridCell.fromCoordinates(double latitude, double longitude) {
    return GridCell(
      (latitude * 10).round(),
      (longitude * 10).round(),
    );
  }

  /// Parses the `"50.8,12.9"` form stored in the database. Returns null on
  /// anything unparseable, so a corrupt row degrades to "no cell" rather than
  /// throwing during a scoring pass.
  static GridCell? tryParse(String? value) {
    if (value == null) return null;
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return null;
    return GridCell.fromCoordinates(lat, lon);
  }

  /// Latitude of the cell centre, in tenths of a degree.
  final int latTenths;

  /// Longitude of the cell centre, in tenths of a degree.
  final int lonTenths;

  /// Representative latitude for this cell — what the geo model is asked about.
  double get latitude => latTenths / 10;

  /// Representative longitude for this cell.
  double get longitude => lonTenths / 10;

  /// Stable string form for the `gridCell` columns and for cache keys.
  ///
  /// Matches the weather cache's format, so the two are comparable by eye when
  /// debugging.
  String get storageKey => '${latitude.toStringAsFixed(1)},'
      '${longitude.toStringAsFixed(1)}';

  @override
  bool operator ==(Object other) =>
      other is GridCell &&
      other.latTenths == latTenths &&
      other.lonTenths == lonTenths;

  @override
  int get hashCode => Object.hash(latTenths, lonTenths);

  @override
  String toString() => 'GridCell($storageKey)';
}
