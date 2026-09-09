// =============================================================================
// CollectionRepository — the life list, read
// =============================================================================
//
// Reads only. Every write to `LifeSpecies` goes through `ScoringRepository`
// (`DAT-11`), and keeping that true is worth a file that does nothing but
// `SELECT`: the album must not be able to add to itself.
// =============================================================================

import 'package:drift/drift.dart';

import 'package:meta/meta.dart';

import '../../core/database/app_database.dart';
import '../scoring/scoring_repository.dart';

/// What the child's own history says about one species (`SAM-06`).
///
/// The half of the species page that turns a reference entry into a
/// collection card. The other half — picture, name, taxonomy, the 48-week
/// curve — is the same for every child in the country; this part is theirs.
///
/// ⚠️ **"Where" is the name the child typed** (`LOG-13`), never a coordinate.
/// The app coarsens location to a 0.1° cell before it stores anything
/// (`NFA-08`) and the shared day image carries no place at all (`LOG-11`,
/// `KID-07`). A species page that quietly reintroduced a map would undo all
/// three.
@immutable
class SpeciesPersonalStats {
  const SpeciesPersonalStats({
    required this.scientificName,
    this.firstHeardAt,
    this.lastHeardAt,
    this.timesHeard = 0,
    this.daysHeard = 0,
    this.stars = 0,
    this.places = const [],
  });

  final String scientificName;

  /// The day it entered the life list, if it ever did.
  final DateTime? firstHeardAt;

  final DateTime? lastHeardAt;

  /// Every detection, scored or not — this is "how often you heard it", and
  /// a bird heard while scoring was paused was still heard (`LOG-15`).
  final int timesHeard;

  /// Distinct days it was heard on. The number that says "regular" or "once".
  final int daysHeard;

  /// Stars this species has earned across all time.
  final int stars;

  /// The child's own names for the places they heard it, most recent first.
  final List<String> places;

  bool get isCollected => firstHeardAt != null;

  /// Whether there is anything personal to show at all.
  bool get isEmpty => timesHeard == 0;
}

/// Reads what the child has collected.
class CollectionRepository {
  CollectionRepository(this._db, {this.profileId = kDefaultProfileId});

  final AppDatabase _db;
  final String profileId;

  /// Every species ever collected, and when it was first heard (`PKT-04`).
  Future<Map<String, DateTime>> collected() async {
    final rows =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();

    return {for (final row in rows) row.scientificName: row.firstSeenAt};
  }

  /// Species collected in [year] — the year list (`SAM-16`, `PKT-12`).
  ///
  /// A second collection that empties every January. Not yet a view of its
  /// own; the data is here so that view is a screen rather than a migration.
  Future<Map<String, DateTime>> collectedIn(int year) async {
    final rows =
        await (_db.select(_db.yearSpecies)..where(
          (y) => y.profileId.equals(profileId) & y.year.equals(year),
        )).get();

    return {for (final row in rows) row.scientificName: row.firstSeenAt};
  }

  /// Everything the child's own history says about [scientificName]
  /// (`SAM-06`).
  ///
  /// Reads across both layers on purpose. The **raw** `Detections` answer
  /// "how often, when, where" — including the ones heard while scoring was
  /// paused, because a bird heard in test mode was still heard (`LOG-15`).
  /// The **scoring** layer answers "is it collected" and "what has it been
  /// worth". Reading only the second would tell a child they have never heard
  /// a robin on the evening they spent listening to one.
  Future<SpeciesPersonalStats> personalStatsFor(String scientificName) async {
    final detections =
        await (_db.select(_db.detections)..where(
          (d) =>
              d.profileId.equals(profileId) &
              d.scientificName.equals(scientificName),
        )).get();

    if (detections.isEmpty) {
      return SpeciesPersonalStats(scientificName: scientificName);
    }

    detections.sort((a, b) => a.detectedAt.compareTo(b.detectedAt));

    final life =
        await (_db.select(_db.lifeSpecies)..where(
          (l) =>
              l.profileId.equals(profileId) &
              l.scientificName.equals(scientificName),
        )).getSingleOrNull();

    final awards =
        await (_db.select(_db.daySpecies)..where(
          (d) =>
              d.profileId.equals(profileId) &
              d.scientificName.equals(scientificName),
        )).get();

    // The child's own words for the places, newest first — that is the order
    // "where did I last hear it" is asked in.
    final named = await _placeNamesBySession();
    final places = <String>[];
    for (final detection in detections.reversed) {
      final place = named[detection.sessionId];
      if (place != null && !places.contains(place)) places.add(place);
    }

    return SpeciesPersonalStats(
      scientificName: scientificName,
      firstHeardAt: life?.firstSeenAt,
      lastHeardAt: detections.last.detectedAt,
      timesHeard: detections.length,
      daysHeard: {for (final d in detections) dayKeyFor(d.detectedAt)}.length,
      stars: awards.fold(0, (sum, row) => sum + row.awardedPoints),
      places: places,
    );
  }

  /// Session id → the name the child gave that place, where they gave one.
  Future<Map<String, String>> _placeNamesBySession() async {
    final sessions =
        await (_db.select(_db.sessions)
          ..where((s) => s.profileId.equals(profileId))).get();

    return {
      for (final session in sessions)
        if ((session.placeName ?? '').trim().isNotEmpty)
          session.id: session.placeName!.trim(),
    };
  }

  /// How many species have ever been collected.
  Future<int> count() async {
    final rows =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();
    return rows.length;
  }
}
