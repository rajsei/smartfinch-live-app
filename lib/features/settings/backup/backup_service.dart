// =============================================================================
// BackupService — the thing between a broken phone and a lost collection
// =============================================================================
//
// `SET-07`. The app has no cloud account and stores everything on the device,
// which is the right trade for `NFA-07` and the wrong one the day the phone
// goes in a river. `DAT-09`'s rolling local backups survive a crash; they do
// not survive a lost device. This does.
//
// ### Nothing is recomputed — that is the whole design
//
// `LOG-12` was rewritten around this: a backup carries the `ScoreEvent`
// journal, and every event already holds its **frozen** base value, level,
// `geoWeek`, grid cell, threshold and rule version (`PKT-15`). A restore
// writes them back **unchanged**.
//
// The alternative — re-deriving stars from today's rarity scale — would look
// harmless and would silently rewrite a child's history: the scale is rebuilt
// per grid cell *and* per geo week, so a redwing that was worth 1,000 stars in
// November would come back worth 200 in January. There is no historical lookup
// that can go wrong here, because there is no historical lookup.
//
// ### Restore replaces, it does not merge
//
// Two histories cannot be merged. Row ids are UUIDs, so nothing can tell a
// re-imported detection from a genuinely new one, and a merge would double
// every star it touched. The case this exists for is a *new phone*, where
// there is nothing to merge with — so replace-all, behind a confirmation,
// which is both honest and the only thing that can be reasoned about.
//
// ### What is deliberately not in the file
//
// **The audio.** A year of clips is hundreds of megabytes, and a backup too
// large to write or send protects nothing. The clips are already a
// retention-managed cache that `SET-12` deletes by policy; the *collection* is
// the thing that has to survive. On restore the clip paths are cleared, so the
// journal never offers a play button for a file that is on the old phone.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../../core/database/app_database.dart';

/// The file format, so a future change can be recognised rather than guessed.
const String kBackupFormat = 'smartfinch-backup';

/// Bumped when the *file* shape changes, independently of the DB schema.
const int kBackupFormatVersion = 1;

/// Name of the JSON document inside the archive.
const String kBackupEntryName = 'smartfinch-backup.json';

/// What a restore found in the file.
@immutable
class BackupSummary {
  const BackupSummary({
    required this.createdAt,
    required this.schemaVersion,
    this.species = 0,
    this.detections = 0,
    this.stars = 0,
  });

  final DateTime createdAt;

  /// The database schema the backup was written from.
  final int schemaVersion;

  /// Life-list size — the number a parent recognises as "the collection".
  final int species;

  final int detections;
  final int stars;
}

/// Raised when a file is not a Smartfinch backup, or cannot be used.
class BackupException implements Exception {
  const BackupException(this.reason);

  /// One of a small set of causes, so the UI can say something specific
  /// rather than "something went wrong".
  final BackupFailure reason;

  @override
  String toString() => 'BackupException($reason)';
}

enum BackupFailure {
  /// Not a zip, or no backup document inside it.
  notABackup,

  /// A Smartfinch backup, but from a newer app than this one.
  ///
  /// Refused rather than half-read: a partial restore of a collection is
  /// worse than a clear "update the app first".
  tooNew,

  /// The document is there and unreadable.
  corrupt,
}

/// Writes and reads the whole database as one file (`SET-07`).
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Everything, as the bytes of a zip archive.
  ///
  /// Zipped rather than bare JSON for one practical reason: a year of
  /// detections is a lot of very repetitive text, and this compresses to a
  /// fraction of it. The format also leaves room to add files later — kept
  /// recordings, say — without the reader having to change.
  Future<Uint8List> export({DateTime? now}) async {
    final document = <String, dynamic>{
      'format': kBackupFormat,
      'version': kBackupFormatVersion,
      'schemaVersion': _db.schemaVersion,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'tables': {
        'sessions': await _rows(_db.sessions),
        'detections': await _rows(_db.detections),
        'scoreEvents': await _rows(_db.scoreEvents),
        'daySpecies': await _rows(_db.daySpecies),
        'yearSpecies': await _rows(_db.yearSpecies),
        'lifeSpecies': await _rows(_db.lifeSpecies),
        'achievements': await _rows(_db.achievements),
        'userProfiles': await _rows(_db.userProfiles),
      },
    };

    final json = utf8.encode(jsonEncode(document));
    final archive =
        Archive()..addFile(ArchiveFile(kBackupEntryName, json.length, json));

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  /// What [bytes] contains, without changing anything.
  ///
  /// Read before the confirmation, so a parent is told what they are about to
  /// replace their collection with — "412 species, 4 May 2026" — rather than
  /// being asked to confirm a filename.
  Future<BackupSummary> inspect(Uint8List bytes) async {
    final document = _documentIn(bytes);
    final tables = document['tables'] as Map<String, dynamic>;

    final events = (tables['scoreEvents'] as List?) ?? const [];

    return BackupSummary(
      createdAt:
          DateTime.tryParse(document['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      schemaVersion: document['schemaVersion'] as int? ?? 0,
      species: ((tables['lifeSpecies'] as List?) ?? const []).length,
      detections: ((tables['detections'] as List?) ?? const []).length,
      stars: events.fold<int>(
        0,
        (sum, row) => sum + (((row as Map)['total'] as int?) ?? 0),
      ),
    );
  }

  /// Replaces everything with the contents of [bytes] (`SET-07`, `LOG-12`).
  ///
  /// One transaction: a restore either happened or it did not. A half-restored
  /// collection — detections without the events that scored them — would be
  /// worse than the empty database it replaced, because nothing would look
  /// broken.
  Future<BackupSummary> restore(Uint8List bytes) async {
    final summary = await inspect(bytes);
    final document = _documentIn(bytes);
    final tables = document['tables'] as Map<String, dynamic>;

    // ⚠️ AUS-12: levels ratchet. Read before the wipe, so restoring an older
    // backup onto a phone that has since progressed cannot take a level — and
    // with it an avatar stage — away from a child. Principle 1 forbids it,
    // and it is exactly the sort of loss nobody would think to test for.
    final highestBefore = await _highestLevelReached();

    await _db.transaction(() async {
      // Reverse dependency order: detections reference sessions.
      await _db.delete(_db.achievements).go();
      await _db.delete(_db.lifeSpecies).go();
      await _db.delete(_db.yearSpecies).go();
      await _db.delete(_db.daySpecies).go();
      await _db.delete(_db.scoreEvents).go();
      await _db.delete(_db.detections).go();
      await _db.delete(_db.sessions).go();
      await _db.delete(_db.userProfiles).go();

      await _insert(_db.sessions, tables['sessions'], Session.fromJson);
      await _insert(_db.detections, tables['detections'], _detectionFromJson);
      await _insert(
        _db.scoreEvents,
        tables['scoreEvents'],
        ScoreEvent.fromJson,
      );
      await _insert(_db.daySpecies, tables['daySpecies'], DaySpecy.fromJson);
      await _insert(_db.yearSpecies, tables['yearSpecies'], YearSpecy.fromJson);
      await _insert(_db.lifeSpecies, tables['lifeSpecies'], LifeSpecy.fromJson);
      await _insert(
        _db.achievements,
        tables['achievements'],
        Achievement.fromJson,
      );
      await _insert(
        _db.userProfiles,
        tables['userProfiles'],
        UserProfile.fromJson,
      );
    });

    await _ratchetLevel(highestBefore);
    return summary;
  }

  /// The clip path is dropped on the way in.
  ///
  /// The recordings are not in the file — see the header — so a restored
  /// detection must not claim to have one. The journal would render a play
  /// button for a file that is on the old phone, which reads as a bug rather
  /// than as the deliberate trade it is. `clipIsFavourite` survives: it says
  /// something about what the child valued, and costs nothing.
  static Detection _detectionFromJson(Map<String, dynamic> json) {
    // Drift's serializer keys the JSON by the *Dart* field name, not the
    // column name — 'audioClipPath', not 'audio_clip_path'. Getting that
    // wrong here would leave the path in place and do nothing visible.
    return Detection.fromJson({...json, 'audioClipPath': null});
  }

  Future<int> _highestLevelReached() async {
    final profiles = await _db.select(_db.userProfiles).get();
    return profiles.fold<int>(
      0,
      (best, p) => p.highestLevelReached > best ? p.highestLevelReached : best,
    );
  }

  Future<void> _ratchetLevel(int floor) async {
    if (floor <= 0) return;

    final profiles = await _db.select(_db.userProfiles).get();
    for (final profile in profiles) {
      if (profile.highestLevelReached >= floor) continue;
      await (_db.update(_db.userProfiles)
        ..where((p) => p.id.equals(profile.id))).write(
        UserProfilesCompanion(
          highestLevelReached: Value(floor),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _rows(
    TableInfo<Table, dynamic> table,
  ) async {
    final rows = await _db.select(table).get();
    return [for (final row in rows) (row as DataClass).toJson()];
  }

  Future<void> _insert<T extends Insertable<dynamic>>(
    TableInfo<Table, dynamic> table,
    Object? rows,
    T Function(Map<String, dynamic>) parse,
  ) async {
    if (rows is! List) return;

    for (final row in rows) {
      if (row is! Map) continue;
      await _db
          .into(table)
          .insert(
            parse(Map<String, dynamic>.from(row)),
            mode: InsertMode.insertOrReplace,
          );
    }
  }

  /// Unwraps and validates the archive.
  Map<String, dynamic> _documentIn(Uint8List bytes) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException(BackupFailure.notABackup);
    }

    ArchiveFile? entry;
    for (final file in archive.files) {
      if (file.isFile && file.name.endsWith('.json')) entry = file;
    }
    if (entry == null) throw const BackupException(BackupFailure.notABackup);

    late final Map<String, dynamic> document;
    try {
      document =
          jsonDecode(utf8.decode(entry.content as List<int>))
              as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException(BackupFailure.corrupt);
    }

    if (document['format'] != kBackupFormat) {
      throw const BackupException(BackupFailure.notABackup);
    }
    // Refused rather than half-read: a partial restore of a collection is
    // worse than being told to update the app.
    if ((document['version'] as int? ?? 0) > kBackupFormatVersion) {
      throw const BackupException(BackupFailure.tooNew);
    }
    if (document['tables'] is! Map) {
      throw const BackupException(BackupFailure.corrupt);
    }

    return document;
  }
}
