// =============================================================================
// StorageService — how much room the app takes, and giving the audio back
// =============================================================================
//
// `SET-06`. Two questions a parent asks when the phone says it is full: how
// much of that is this app, and can I get it back without losing anything that
// matters. The answers are "this much, nearly all of it recordings" and "yes —
// the recordings can go, and the collection stays".
//
// ### What is counted where
//
// **Recordings** — everything under `<documents>/recordings`, plus the
// temporary copies made of them for playback, spectrograms and sharing. That
// includes files nothing in the app points at any more: whole-session files
// from the old *Full* recording mode, which the journal cannot play and
// retention (`SET-12`) never sees. They take space all the same, so they are
// counted, and "Delete recordings" removes them.
//
// **Collection** — the database with its side files and the automatic
// backups (`DAT-09`): every species, day, star and badge. Shown so the parent
// sees how small it is next to the audio. Nothing here deletes it; that is
// "Clear all data", in the danger zone.
//
// ### What "Delete recordings" keeps
//
// **The collection, always.** Only audio files go. The detections stay, with
// their stars; the journal stops offering to play them.
//
// **Kept recordings, unless asked.** A child marks a recording to keep
// (`SET-12`), and that promise holds here too: they stay unless the parent
// ticks the box that says, in so many words, that they go as well.
//
// **Nothing while listening.** A live session is writing into the directory
// being emptied. It is refused rather than raced.
//
// ### Order of operations
//
// Files first, then the rows — the same order the retention job uses, for the
// same reason: a row cleared before its file is deleted leaves audio on disk
// that nothing can find. Clearing a path whose file is already gone costs
// nothing, so after the files go every row pointing at a missing file is
// cleared, whatever deleted it.
// =============================================================================

import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/services/app_data_clear_service.dart';

/// `<documents>/recordings`, where `RecordingService` writes a directory per
/// session and the backup restore writes `restored/`.
const String kRecordingsDirectoryName = 'recordings';

/// "120 MB", "2,4 MB", "350 KB" — grouped and punctuated for [locale].
///
/// Powers of 1,000, not 1,024: that is what Android and iOS use in their own
/// storage screens, and a parent comparing the two should see the same number.
String formatStorageSize(int bytes, String locale) {
  const kilo = 1000;
  const mega = kilo * 1000;
  const giga = mega * 1000;

  if (bytes < mega) {
    final kb = (bytes / kilo).ceil();
    return '${NumberFormat.decimalPattern(locale).format(kb)} KB';
  }
  if (bytes < giga) {
    final mb = bytes / mega;
    return '${NumberFormat(mb < 10 ? '0.0' : '0', locale).format(mb)} MB';
  }
  return '${NumberFormat('0.0', locale).format(bytes / giga)} GB';
}

/// What the app occupies on the device (`SET-06`).
@immutable
class StorageUsage {
  const StorageUsage({
    this.recordingBytes = 0,
    this.recordingCount = 0,
    this.keptCount = 0,
    this.collectionBytes = 0,
  });

  /// Every recording and every temporary copy of one.
  final int recordingBytes;

  /// Audio files under the recordings directory.
  final int recordingCount;

  /// Recordings a child marked to keep that are still on disk.
  final int keptCount;

  /// The database, its side files and the automatic backups.
  final int collectionBytes;

  int get totalBytes => recordingBytes + collectionBytes;
}

/// What "Delete recordings" did.
@immutable
class RecordingDeletion {
  const RecordingDeletion({
    this.deleted = 0,
    this.failed = 0,
    this.freedBytes = 0,
  });

  /// Audio files removed from the recordings directory.
  final int deleted;

  /// Files that could not be removed; their rows keep their paths.
  final int failed;

  /// Everything freed, temporary copies included.
  final int freedBytes;
}

/// Thrown when recordings cannot be deleted because a session is writing them.
class StillListeningException implements Exception {
  const StillListeningException();
}

/// Measures the app's storage and deletes recordings (`SET-06`).
class StorageService {
  StorageService({
    required AppDatabase db,
    required bool Function() isListening,
    Future<Directory> Function()? documents,
    Future<Directory> Function()? temporary,
    this.profileId = kDefaultProfileId,
  }) : _db = db,
       _isListening = isListening,
       _documents = documents ?? getApplicationDocumentsDirectory,
       _temporary = temporary ?? getTemporaryDirectory;

  final AppDatabase _db;

  /// True while a live session may be writing audio.
  final bool Function() _isListening;

  /// Injectable so a test can hand it temporary directories.
  final Future<Directory> Function() _documents;
  final Future<Directory> Function() _temporary;
  final String profileId;

  /// What the app occupies right now. The directory walk runs on a
  /// background isolate — a year of clips is thousands of files.
  Future<StorageUsage> measure() async {
    final paths = await _paths();
    final kept = await _keptPaths();
    return _measureOffThread(paths, kept);
  }

  /// Deletes recordings, and with them every temporary copy of one.
  ///
  /// Kept recordings stay unless [includeKept]. Throws
  /// [StillListeningException] while a session is running.
  Future<RecordingDeletion> deleteRecordings({bool includeKept = false}) async {
    if (_isListening()) throw const StillListeningException();

    final paths = await _paths();
    final keep = includeKept ? const <String>[] : await _keptPaths();
    final result = await _deleteOffThread(paths, keep);

    await _clearMissingPaths();
    return result;
  }

  /// Rows pointing at a file that is no longer there get no path, so the
  /// journal stops offering a play button for nothing.
  Future<void> _clearMissingPaths() async {
    final rows =
        await (_db.select(_db.detections)..where(
          (d) => d.profileId.equals(profileId) & d.audioClipPath.isNotNull(),
        )).get();
    final gone = [
      for (final row in rows)
        if (!File(row.audioClipPath!).existsSync()) row.id,
    ];
    if (gone.isEmpty) return;

    final now = DateTime.now();
    await _db.transaction(() async {
      // In slices: SQLite caps the number of variables in one statement.
      for (var start = 0; start < gone.length; start += 500) {
        final slice = gone.sublist(
          start,
          start + 500 > gone.length ? gone.length : start + 500,
        );
        await (_db.update(_db.detections)
          ..where((d) => d.id.isIn(slice))).write(
          DetectionsCompanion(
            audioClipPath: const Value(null),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  /// Recordings the child marked to keep.
  Future<List<String>> _keptPaths() async {
    final rows =
        await (_db.select(_db.detections)..where(
          (d) =>
              d.profileId.equals(profileId) &
              d.clipIsFavourite.equals(true) &
              d.audioClipPath.isNotNull(),
        )).get();
    return [for (final row in rows) row.audioClipPath!];
  }

  Future<_Paths> _paths() async {
    final documents = await _documents();
    final temporary = await _temporary();
    return _Paths(
      recordings: p.join(documents.path, kRecordingsDirectoryName),
      audioCaches: [
        for (final name in AppDataClearService.temporaryAudioDirectories)
          p.join(temporary.path, name),
      ],
      collection: [
        for (final file in appDatabaseFiles(documents)) file.path,
        p.join(documents.path, kAutoBackupDirectoryName),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Off the UI thread
  //
  // ⚠️ Static, and so is everything they call. A closure built inside an
  // instance method carries the instance to the isolate, and this one holds
  // the database, which cannot cross.
  // ---------------------------------------------------------------------------

  static Future<StorageUsage> _measureOffThread(
    _Paths paths,
    List<String> kept,
  ) => Isolate.run(() => _measure(paths, kept));

  static Future<RecordingDeletion> _deleteOffThread(
    _Paths paths,
    List<String> keep,
  ) => Isolate.run(() => _delete(paths, keep));

  static StorageUsage _measure(_Paths paths, List<String> kept) {
    var recordingBytes = 0;
    var recordingCount = 0;
    for (final file in _filesUnder(paths.recordings)) {
      recordingBytes += _sizeOf(file);
      if (_isAudio(file.path)) recordingCount++;
    }
    for (final cache in paths.audioCaches) {
      for (final file in _filesUnder(cache)) {
        recordingBytes += _sizeOf(file);
      }
    }

    var collectionBytes = 0;
    for (final path in paths.collection) {
      if (FileSystemEntity.isDirectorySync(path)) {
        for (final file in _filesUnder(path)) {
          collectionBytes += _sizeOf(file);
        }
      } else {
        collectionBytes += _sizeOf(File(path));
      }
    }

    return StorageUsage(
      recordingBytes: recordingBytes,
      recordingCount: recordingCount,
      keptCount: kept.where((path) => File(path).existsSync()).length,
      collectionBytes: collectionBytes,
    );
  }

  static RecordingDeletion _delete(_Paths paths, List<String> keep) {
    final kept = {for (final path in keep) _canonical(path)};
    var deleted = 0;
    var failed = 0;
    var freed = 0;

    for (final file in _filesUnder(paths.recordings)) {
      if (kept.contains(_canonical(file.path))) continue;
      final size = _sizeOf(file);
      try {
        file.deleteSync();
        freed += size;
        if (_isAudio(file.path)) deleted++;
      } catch (error) {
        debugPrint('[Storage] could not delete ${file.path}: $error');
        failed++;
      }
    }
    _removeEmptyDirectories(paths.recordings);

    // The temporary copies go whole: every one of them can be made again from
    // a recording that still exists, and none of them should outlive one that
    // does not.
    for (final cache in paths.audioCaches) {
      for (final file in _filesUnder(cache)) {
        final size = _sizeOf(file);
        try {
          file.deleteSync();
          freed += size;
        } catch (error) {
          debugPrint('[Storage] could not delete ${file.path}: $error');
        }
      }
    }

    return RecordingDeletion(
      deleted: deleted,
      failed: failed,
      freedBytes: freed,
    );
  }

  static Iterable<File> _filesUnder(String path) sync* {
    final directory = Directory(path);
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) yield entity;
    }
  }

  /// Every directory under [root] left with nothing in it — not [root].
  static void _removeEmptyDirectories(String root) {
    final directory = Directory(root);
    if (!directory.existsSync()) return;
    final directories = [
      for (final entity in directory.listSync(recursive: true))
        if (entity is Directory) entity,
    ]..sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final dir in directories) {
      try {
        if (dir.listSync().isEmpty) dir.deleteSync();
      } catch (_) {
        // Not empty after all, or in use. It costs a few bytes.
      }
    }
  }

  static int _sizeOf(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  static const Set<String> _audioExtensions = {
    '.wav',
    '.flac',
    '.mp3',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
  };

  static bool _isAudio(String path) =>
      _audioExtensions.contains(p.extension(path).toLowerCase());

  static String _canonical(String path) => p.canonicalize(path);
}

/// The places [StorageService] looks, resolved once and sent to the isolate.
@immutable
class _Paths {
  const _Paths({
    required this.recordings,
    required this.audioCaches,
    required this.collection,
  });

  final String recordings;
  final List<String> audioCaches;

  /// Files and directories that make up the collection.
  final List<String> collection;
}
