// =============================================================================
// AutoBackupService — three copies of the collection, kept without asking
// =============================================================================
//
// `DAT-09`. The specification calls a lost collection the worst imaginable
// failure, and `SET-07` only defends against it if a parent remembers to save
// a file. This is the half that needs nobody: a copy of the database on the
// device, rolling, three generations.
//
// It survives what happens *on* the phone — a crash that leaves the database
// unreadable, an update whose migration goes wrong (`NFA-12`), a bug that
// writes nonsense. It does not survive losing the phone; that is `SET-07`'s
// job, and the backup screen says so next to both.
//
// ### The same file as SET-07, on purpose
//
// A generation is exactly what "Save a backup" writes, minus the recordings.
// So restoring one is the restore that already exists and is already tested:
// frozen fields written back unchanged (`PKT-15`, `LOG-12`), levels ratcheting
// through it (`AUS-12`), one transaction. A second format would need a second
// restore, and a restore path that runs once in a child's life is not one to
// have two of.
//
// ### One generation per day, three days deep
//
// A copy written after every session would make three generations mean three
// sessions — an afternoon. Damage that goes unnoticed until the next day would
// by then have pushed every good copy out. So a day has one generation, which
// later changes that day *replace*, and the three kept are the last three days
// on which something changed.
//
// ### When it does not write — the rules that keep good copies alive
//
// **Nothing to protect.** An empty database is never written. This is the rule
// that matters most: a migration that wiped the tables, or a corrupt file the
// app recreated empty, would otherwise roll the three good generations out one
// day at a time while nobody looked.
//
// **Nothing new.** If the collection is in a state one of the generations
// already holds, there is nothing to write. "The same state" is a fingerprint
// — row count and newest `updatedAt` per table, which every write in this app
// bumps (`DAT-08`) — so the check is one query rather than a full export.
// It also means restoring a generation does not immediately overwrite today's
// copy with the restored one: that state is already on disk.
//
// **Never replaced by less.** Nothing in this app deletes a detection — only
// a restore does, or damage. So a day's copy is replaced only by a state with
// at least as many detections. A smaller one is written *beside* it: if the
// shrink was a mistaken restore or a bug, the copy from before it is the one
// that undoes it, and it is still there.
//
// **Never half.** The file is written under a temporary name and renamed into
// place; only then is anything older deleted. A crash mid-write leaves a stray
// temporary file, swept on the next run, and every generation intact.
//
// ### It never gets in the way
//
// Runs at app start and when a listening session ends, never during one, and
// the heavy part — JSON and compression — is on a background isolate
// (`BackupService.export`). Every failure is logged and swallowed: a backup
// that could not be written must not become an error a child sees.
// =============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import 'backup_service.dart';

/// How many generations are kept (`DAT-09`).
const int kAutoBackupGenerations = 3;

/// `<documents>/backups`, where the generations live.
Future<Directory> defaultAutoBackupDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory(p.join(documents.path, kAutoBackupDirectoryName));
}

/// One kept copy.
@immutable
class AutoBackup {
  const AutoBackup({
    required this.file,
    required this.createdAt,
    required this.fingerprint,
  });

  final File file;

  /// Local time, as the file name records it.
  final DateTime createdAt;

  /// The state of the database this copy holds. See [AutoBackupService].
  final String fingerprint;
}

/// A generation together with what it holds, for the backup screen.
@immutable
class AutoBackupEntry {
  const AutoBackupEntry(this.backup, this.summary);

  final AutoBackup backup;
  final BackupSummary summary;
}

/// What a run did. Only tests and the log read it.
enum AutoBackupOutcome {
  /// A new generation is on disk.
  written,

  /// The collection is in a state a generation already holds.
  unchanged,

  /// Nothing in the database worth a copy.
  empty,

  /// Something went wrong; logged, and nothing was deleted.
  failed,
}

/// Keeps the rolling local backups (`DAT-09`).
class AutoBackupService {
  AutoBackupService(
    this._db,
    this._backup, {
    Future<Directory> Function()? directory,
    DateTime Function()? clock,
  }) : _directory = directory ?? defaultAutoBackupDirectory,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final BackupService _backup;

  /// Injectable so a test can hand it a temporary directory.
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;

  /// A run already under way. App start and the end of a session can ask at
  /// the same moment; they share one run rather than racing to write.
  Future<AutoBackupOutcome>? _running;

  static final RegExp _namePattern = RegExp(
    r'^auto-(\d{8})-(\d{6})-([0-9a-f]+)\.zip$',
  );

  /// Writes a generation if the collection has changed since the last one.
  ///
  /// Safe to call as often as is convenient: when nothing changed it costs
  /// one query and a directory listing. Never throws.
  Future<AutoBackupOutcome> runIfDue() {
    return _running ??= _run().whenComplete(() => _running = null);
  }

  Future<AutoBackupOutcome> _run() async {
    File? temporary;
    try {
      final state = await currentState();
      if (state == null) return AutoBackupOutcome.empty;
      final fingerprint = state.fingerprint;

      final directory = await _directory();
      await directory.create(recursive: true);
      await _sweepTemporaries(directory);

      final existing = await generations();
      if (existing.any((g) => g.fingerprint == fingerprint)) {
        return AutoBackupOutcome.unchanged;
      }

      final now = _clock();
      final bytes = await _backup.export(now: now);

      final name = _nameFor(now, fingerprint);
      temporary = File(p.join(directory.path, '$name.tmp'));
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(p.join(directory.path, name));
      temporary = null;

      // Only now that the new copy is in place: the day's earlier copy is
      // superseded rather than kept beside it — unless it holds more than the
      // new one — and then the oldest go.
      for (final generation in existing) {
        if (!_sameDay(generation.createdAt, now)) continue;
        if (await _detectionsIn(generation) > state.detections) continue;
        await _delete(generation.file);
      }
      final kept = await generations();
      for (final generation in kept.skip(kAutoBackupGenerations)) {
        await _delete(generation.file);
      }

      return AutoBackupOutcome.written;
    } catch (error, stack) {
      debugPrint('[AutoBackup] no copy written: $error\n$stack');
      if (temporary != null) await _delete(temporary);
      return AutoBackupOutcome.failed;
    }
  }

  /// The kept generations, newest first.
  ///
  /// Anything in the directory that is not a finished generation — a stray
  /// temporary file, something a future version left — is not listed, and
  /// never counts towards the three.
  Future<List<AutoBackup>> generations() async {
    final directory = await _directory();
    if (!await directory.exists()) return const [];

    final found = <AutoBackup>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final match = _namePattern.firstMatch(p.basename(entity.path));
      if (match == null) continue;

      final createdAt = _parseStamp(match.group(1)!, match.group(2)!);
      if (createdAt == null) continue;
      found.add(
        AutoBackup(
          file: entity,
          createdAt: createdAt,
          fingerprint: match.group(3)!,
        ),
      );
    }

    found.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return found;
  }

  /// The generations with what each holds, read on a background isolate.
  ///
  /// A copy that cannot be read is left out rather than offered: restoring it
  /// would fail too, and the list is there to be acted on.
  Future<List<AutoBackupEntry>> entries() async {
    final entries = <AutoBackupEntry>[];
    for (final generation in await generations()) {
      try {
        entries.add(
          AutoBackupEntry(generation, await _summaryOf(generation.file.path)),
        );
      } catch (error) {
        debugPrint('[AutoBackup] unreadable copy ${generation.file}: $error');
      }
    }
    return entries;
  }

  /// Static, so the closure carries nothing but the path to the isolate.
  static Future<BackupSummary> _summaryOf(String path) =>
      Isolate.run(() => BackupService.summaryOf(File(path).readAsBytesSync()));

  /// How many detections [generation] holds; an unreadable copy holds none
  /// worth keeping.
  static Future<int> _detectionsIn(AutoBackup generation) async {
    try {
      return (await _summaryOf(generation.file.path)).detections;
    } catch (_) {
      return 0;
    }
  }

  /// The state of the database, or null when there is nothing to protect.
  ///
  /// The fingerprint is row count and newest `updatedAt` for every table the
  /// backup carries. Every write in this app sets `updatedAt` (`DAT-08`), so
  /// any change moves one of the two; nothing short of a full export would be
  /// stricter, and that is the cost this exists to avoid.
  @visibleForTesting
  Future<({String fingerprint, int detections})?> currentState() async {
    final tables = <TableInfo<Table, dynamic>>[
      _db.sessions,
      _db.detections,
      _db.scoreEvents,
      _db.daySpecies,
      _db.yearSpecies,
      _db.lifeSpecies,
      _db.achievements,
      _db.userProfiles,
    ];
    final columns = [
      for (final (i, table) in tables.indexed) ...[
        '(SELECT COUNT(*) FROM "${table.actualTableName}") AS c$i',
        '(SELECT COALESCE(MAX(updated_at), 0) '
            'FROM "${table.actualTableName}") AS u$i',
      ],
    ];

    final row =
        await _db
            .customSelect(
              'SELECT ${columns.join(', ')}',
              readsFrom: tables.toSet(),
            )
            .getSingle();

    final values = [for (final column in row.data.values) '$column'];

    // Sessions, detections and score events all empty: no listening has ever
    // been recorded. The profile row alone is not a collection.
    final listened = [0, 1, 2].any((i) => row.read<int>('c$i') > 0);
    if (!listened) return null;

    return (
      fingerprint: _fnv1a(values.join('|')),
      detections: row.read<int>('c1'),
    );
  }

  static String _nameFor(DateTime at, String fingerprint) =>
      'auto-${DateFormat('yyyyMMdd-HHmmss').format(at)}-$fingerprint.zip';

  static DateTime? _parseStamp(String date, String time) {
    try {
      return DateTime(
        int.parse(date.substring(0, 4)),
        int.parse(date.substring(4, 6)),
        int.parse(date.substring(6, 8)),
        int.parse(time.substring(0, 2)),
        int.parse(time.substring(2, 4)),
        int.parse(time.substring(4, 6)),
      );
    } on FormatException {
      return null;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// FNV-1a, 32 bits, as eight hex digits — short enough for a file name, and
  /// stable across runs and Dart versions, which `String.hashCode` is not.
  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static Future<void> _sweepTemporaries(Directory directory) async {
    await for (final entity in directory.list()) {
      if (entity is File && entity.path.endsWith('.tmp')) {
        await _delete(entity);
      }
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[AutoBackup] could not delete ${file.path}: $error');
    }
  }
}
