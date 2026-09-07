// =============================================================================
// Rarity scale — one scale, shared by Explore and by scoring (DAT-10)
// =============================================================================
//
// A species' star value comes from its rarity tier, and that tier is not a
// fixed property: `ExploreTierScale` cuts the local species list at rank
// percentiles, recalibrated for every location and every week (2.1). So the
// tier — and the points — depend on *which scale you ask*.
//
// Before this, that scale was built inside `exploreSpeciesProvider`, scoped to
// the Explore screen. Scoring needs the identical one at detection time in Live
// mode. **If the two can disagree about what a bird is worth, principle 6
// breaks loudly and in front of the child**: the Collection says 200 stars, the
// detection card awards 350, and nothing in the app can explain the difference.
//
// ### Rebuild policy
//
// Building a scale costs 48 ONNX inferences, so it is keyed on
// `(GridCell, geoWeek)` and cached:
//
//   * **Rebuilt only when the cell changes** (D23). The position is re-checked
//     every few minutes at coarse accuracy; a child on foot needs over an hour
//     to cross a 0.1° cell, so in practice this runs almost never.
//   * **The current scale stays usable while a rebuild is in flight** — nothing
//     may interrupt listening (principle 7). A detection during the rebuild is
//     valued with the previous cell, which is off by at most a few minutes and
//     always explainable.
//   * **A small LRU cache**, so a route that crosses a boundary does not
//     rebuild back and forth every few minutes.
//
// ### Isolate
//
// [RarityScaleCache.build] does the inference off the main isolate. Explore
// deliberately runs it inline, because there it happens once on a loading
// screen — during a live session the UI has to hold 60 fps (NFA-13).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/grid_cell.dart';
import '../explore/explore_providers.dart';
import '../inference/geo_abundance.dart';
import '../inference/geo_model.dart';

/// Identifies one rarity scale: a place and a time of year.
///
/// `geoWeek` is the geo model's 1–48 (four weeks per calendar month, the fourth
/// running 9–10 days) — **not** the ISO week that drives the loyalty
/// multipliers. Two different calendars; never let one variable mean both.
@immutable
class RarityScaleKey {
  const RarityScaleKey(this.cell, this.geoWeek);

  factory RarityScaleKey.at(GridCell cell, DateTime when) =>
      RarityScaleKey(cell, GeoModel.dateTimeToWeek(when));

  final GridCell cell;
  final int geoWeek;

  @override
  bool operator ==(Object other) =>
      other is RarityScaleKey && other.cell == cell && other.geoWeek == geoWeek;

  @override
  int get hashCode => Object.hash(cell, geoWeek);

  @override
  String toString() => 'RarityScaleKey(${cell.storageKey}, w$geoWeek)';
}

/// A built scale plus the raw scores it was built from.
///
/// The scores are kept because scoring needs both: the scale answers "which
/// tier", and the raw score is what you look the tier up with.
@immutable
class RarityScale {
  const RarityScale({
    required this.key,
    required this.scale,
    required this.rawScores,
  });

  final RarityScaleKey key;
  final ExploreTierScale scale;

  /// Raw current-week geo score per scientific name, before any normalisation.
  final Map<String, double> rawScores;

  /// The tier for [scientificName], or null when the species is not on this
  /// week's local list at all.
  ///
  /// **Null means it scores nothing** (2.3, D20) — not "top tier". The off-list
  /// rule that awarded full points was removed; rule and filter now say the
  /// same thing.
  ExploreTier? tierFor(String scientificName) {
    final raw = rawScores[scientificName];
    if (raw == null || raw < kAbundanceInclusionThreshold) return null;
    return scale.tierFor(raw);
  }
}

/// Builds and caches rarity scales.
///
/// Held as a singleton by [rarityScaleCacheProvider]; the cache lives for the
/// process, not for a screen.
class RarityScaleCache {
  RarityScaleCache(this._geoModel, {this.maxEntries = 6});

  final GeoModel _geoModel;

  /// How many `(cell, week)` scales to keep. Six covers a home cell, a school
  /// route that crosses a boundary, and a weekend trip, without holding a
  /// meaningful amount of memory — each entry is a few hundred doubles.
  final int maxEntries;

  /// Insertion-ordered: Dart's `Map` preserves insertion order, so the first
  /// key is the least recently used once [_touch] re-inserts on every hit.
  final Map<RarityScaleKey, RarityScale> _entries = {};

  /// Rebuilds in flight, so two callers asking for the same scale at once wait
  /// on one inference run rather than starting two.
  final Map<RarityScaleKey, Future<RarityScale>> _inFlight = {};

  /// The scale for [key] if it is already built. Never triggers work.
  ///
  /// This is what a detection should use: it returns immediately, and a caller
  /// that gets null can fall back to the last known scale rather than blocking
  /// the audio pipeline on 48 inferences.
  RarityScale? peek(RarityScaleKey key) {
    final hit = _entries[key];
    if (hit != null) _touch(key, hit);
    return hit;
  }

  /// The scale for [key], building it if necessary.
  Future<RarityScale> get(RarityScaleKey key) {
    final cached = peek(key);
    if (cached != null) return Future.value(cached);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _build(key);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<RarityScale> _build(RarityScaleKey key) async {
    // 48 single-sample inferences. Cheap per call, but not free — this is the
    // work the cache exists to avoid repeating.
    final allWeeks = await _geoModel.predictAllWeeks(
      latitude: key.cell.latitude,
      longitude: key.cell.longitude,
    );

    final rawScores = <String, double>{};
    for (final entry in allWeeks.entries) {
      rawScores[entry.key] = entry.value[key.geoWeek - 1];
    }

    final built = RarityScale(
      key: key,
      scale: ExploreTierScale.fromGeoScores(rawScores),
      rawScores: rawScores,
    );

    _entries[key] = built;
    _evictIfNeeded();
    return built;
  }

  void _touch(RarityScaleKey key, RarityScale value) {
    _entries.remove(key);
    _entries[key] = value;
  }

  void _evictIfNeeded() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Number of cached scales. Tests and diagnostics only.
  @visibleForTesting
  int get size => _entries.length;

  /// Drops everything. Used by "Clear all data" and by tests.
  void clear() {
    _entries.clear();
    _inFlight.clear();
  }
}

/// The process-wide scale cache.
///
/// A `FutureProvider` because it needs the loaded geo model, and pretending
/// otherwise would only move the wait somewhere less obvious. **Resolve it once
/// at session start and hold the instance** — a live session then uses [peek],
/// which is synchronous and never blocks on inference.
final rarityScaleCacheProvider = FutureProvider<RarityScaleCache>((ref) async {
  final geoModel = await ref.watch(geoModelProvider.future);
  final cache = RarityScaleCache(geoModel);
  ref.onDispose(cache.clear);
  return cache;
});

/// The scale for the current location and week.
///
/// Returns null when there is no position at all — which after D18 should not
/// happen, because the home region is chosen during onboarding. Without a cell
/// there is no tier and therefore no stars (gap F).
final currentRarityScaleProvider = FutureProvider<RarityScale?>((ref) async {
  final location = await ref.watch(currentLocationProvider.future);
  if (location == null) return null;

  final cache = await ref.watch(rarityScaleCacheProvider.future);
  final key = RarityScaleKey.at(
    GridCell.fromCoordinates(location.latitude, location.longitude),
    DateTime.now(),
  );
  return cache.get(key);
});
