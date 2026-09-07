// =============================================================================
// AppDatabase — the app's SQLite database (DAT-01)
// =============================================================================
//
// Replaces the JSON-file-per-session store BirdNET Live used. That store had
// no schema, no queries and no constraints, which made three requirements
// unbuildable: `PKT-03`'s "double awarding must be technically impossible"
// (nothing to put a UNIQUE constraint on), `STAT-02`'s 30-day chart (every
// file parsed on every open) and `NFA-11`'s immediate persistence (a session
// was one file, written when it ended).
//
// ### Generated code
//
// `app_database.g.dart` is produced by drift_dev and is **not committed** —
// same reasoning as the l10n output: it would conflict on every upstream
// merge. After changing anything in `tables.dart`:
//
// ```
// dart run build_runner build --delete-conflicting-outputs
// ```
//
// ### Migrations
//
// Every schema change needs a tested upgrade **and** downgrade path (NFA-12).
// A child who has collected 200 species must lose nothing on an update — that
// is the single worst failure this app has, worse than any scoring bug.
// =============================================================================

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// The one profile every row belongs to until family profiles arrive (DAT-07).
///
/// A fixed id rather than a generated one so the first release does not need a
/// migration to introduce profiles later: rows written today already point at
/// a profile that exists.
const String kDefaultProfileId = 'default';

@DriftDatabase(
  tables: [
    Sessions,
    Detections,
    ScoreEvents,
    DaySpecies,
    YearSpecies,
    LifeSpecies,
    Achievements,
    UserProfiles,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For tests: an in-memory database that starts empty and leaves no file.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultProfile();
    },
    onUpgrade: (m, from, to) async {
      // Nothing to migrate yet — schema 1 is the first. When this changes:
      // write the step, write a test for it, and write the downgrade path too
      // (NFA-12). Never edit an existing migration once it has shipped.
    },
    beforeOpen: (details) async {
      // Foreign keys are off by default in SQLite and must be enabled per
      // connection. Without this, `firstDetectionId` could point at a deleted
      // row and the scoring layer would quietly reference nothing.
      await customStatement('PRAGMA foreign_keys = ON');

      // An install that predates the profile row (or a restore that skipped
      // it) still needs one, since every row references it.
      if (details.wasCreated) return;
      await _seedDefaultProfile();
    },
  );

  Future<void> _seedDefaultProfile() async {
    final existing =
        await (select(userProfiles)
          ..where((p) => p.id.equals(kDefaultProfileId))).getSingleOrNull();
    if (existing != null) return;

    await into(userProfiles).insert(
      UserProfilesCompanion.insert(
        id: kDefaultProfileId,
        profileId: kDefaultProfileId,
        updatedAt: DateTime.now(),
      ),
    );
  }
}

/// Opens the database file in the app documents directory.
///
/// Runs on a background isolate (`LazyDatabase` + drift's default executor) so
/// queries never block the frame — the UI has to hold 60 fps during a live
/// session (NFA-13).
QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'smartfinch.sqlite'));

    // Android needs a writable temp directory for sorting and vacuuming; the
    // default is not writable in an app sandbox.
    //
    // The old `applyWorkaroundToOpenSqlite3OnOldAndroidVersions()` call is
    // gone: `sqlite3_flutter_libs` is an empty compatibility stub from version
    // 0.6 onwards, because `package:sqlite3` 3.x bundles the library itself.
    if (Platform.isAndroid) {
      final cache = await getTemporaryDirectory();
      sqlite3.tempDirectory = cache.path;
    }

    return NativeDatabase.createInBackground(file);
  });
}
