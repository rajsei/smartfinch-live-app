// =============================================================================
// CollectionRepository — the life list, read
// =============================================================================
//
// Reads only. Every write to `LifeSpecies` goes through `ScoringRepository`
// (`DAT-11`), and keeping that true is worth a file that does nothing but
// `SELECT`: the album must not be able to add to itself.
// =============================================================================

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

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

  /// How many species have ever been collected.
  Future<int> count() async {
    final rows =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();
    return rows.length;
  }
}
