// =============================================================================
// App Data Clear Service — Privacy-focused local data wipe
// =============================================================================
//
// Coordinates the destructive "Clear All Data" action from Settings. The app
// stores user data across a few small local stores: the SQLite database,
// recordings, the legacy session JSON, user species lists, temporary
// review/share caches, SharedPreferences, and the dedicated OpenStreetMap tile
// cache. This service keeps that storage knowledge out of UI code and gives
// tests injectable directory/cache providers.
//
// ### The database is the store that has to be closed first
//
// Everything a child earned lives in `smartfinch.sqlite` (DAT-01): the
// collection, the stars, the badges, the level, the avatar and the journal.
// Every other store here is inert — files that can simply be unlinked — but
// the database has a background isolate holding it open, so it is closed, and
// the close awaited, before a single file is removed. Deleting it underneath
// a live connection fails outright on Windows and, on POSIX, leaves that
// isolate writing into an unlinked file while the app opens a second, empty
// one: a wipe that looks complete and is not.
//
// That is why [AppDataClearService] takes a [DatabaseCloser] rather than
// reaching for the database itself. The one instance in the app belongs to
// `appDatabaseProvider`, and the caller that owns that provider is also the
// caller that has to rebuild it afterwards.
// =============================================================================

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/widgets/open_street_map_tile_layer.dart';
import '../database/app_database.dart';

typedef DirectoryProvider = Future<Directory> Function();
typedef SharedPreferencesProvider = Future<SharedPreferences> Function();
typedef CacheClearer = Future<void> Function();

/// Closes the app's open database so its file can be deleted.
typedef DatabaseCloser = Future<void> Function();

/// Clears every store of user-owned data the app keeps on the device.
class AppDataClearService {
  /// Creates a clear service.
  ///
  /// [databaseCloser] has no default on purpose. A default would have to be
  /// "close nothing", and a caller that forgot to pass one would delete an
  /// open database file rather than fail — the exact silent half-wipe this
  /// service exists to prevent. Optional providers are for tests.
  const AppDataClearService({
    required DatabaseCloser databaseCloser,
    DirectoryProvider? documentsDirectoryProvider,
    DirectoryProvider? temporaryDirectoryProvider,
    SharedPreferencesProvider? sharedPreferencesProvider,
    CacheClearer? mapTileCacheClearer,
  }) : _databaseCloser = databaseCloser,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _temporaryDirectoryProvider =
           temporaryDirectoryProvider ?? getTemporaryDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance,
       _mapTileCacheClearer =
           mapTileCacheClearer ?? clearOpenStreetMapTileCache;

  final DatabaseCloser _databaseCloser;
  final DirectoryProvider _documentsDirectoryProvider;
  final DirectoryProvider _temporaryDirectoryProvider;
  final SharedPreferencesProvider _sharedPreferencesProvider;
  final CacheClearer _mapTileCacheClearer;

  /// Deletes local user data and cached third-party service results.
  ///
  /// This is `NFA-07`'s privacy promise — nothing leaves the device, and what
  /// is on it can be erased — made good, so it has to include the database.
  /// The collection, the stars, the badges, the level, the avatar and the
  /// journal all live there, and leaving them while deleting the recordings
  /// they point at is worse than leaving both.
  ///
  /// The wipe is best-effort across stores: every known store is attempted even
  /// if one fails, then [AppDataClearException] is thrown if anything could not
  /// be cleared.
  Future<void> clearAllData() async {
    final failures = <Object>[];

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (error) {
        failures.add(error);
      }
    }

    final documentsDir = await _documentsDirectoryProvider();
    final temporaryDir = await _temporaryDirectoryProvider();

    // The database goes first, and its close is awaited before anything is
    // unlinked. A failed close still falls through to the deletion below —
    // the pattern here is "attempt every store" — but it is then very likely
    // to be reported as a second failure, which is the honest outcome.
    await attempt(_databaseCloser);
    for (final file in appDatabaseFiles(documentsDir)) {
      await attempt(() => _deleteFileIfExists(file));
    }

    for (final name in _documentDataDirectories) {
      await attempt(
        () => _deleteDirectoryIfExists(p.join(documentsDir.path, name)),
      );
    }

    for (final name in _temporaryDataDirectories) {
      await attempt(
        () => _deleteDirectoryIfExists(p.join(temporaryDir.path, name)),
      );
    }

    await attempt(_mapTileCacheClearer);
    await attempt(() async {
      final prefs = await _sharedPreferencesProvider();
      await prefs.clear();
    });

    if (failures.isNotEmpty) {
      throw AppDataClearException(failures.length);
    }
  }

  static const List<String> _documentDataDirectories = [
    'sessions',
    'recordings',
    'species_lists',
  ];

  static const List<String> _temporaryDataDirectories = [
    'birdnet_norm_cache',
    'birdnet_spec_wav',
    'shared_clips',
  ];

  static Future<void> _deleteDirectoryIfExists(String path) async {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  static Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// Thrown when at least one local store could not be cleared.
class AppDataClearException implements Exception {
  /// Creates a failure with the number of stores that could not be cleared.
  const AppDataClearException(this.failureCount);

  /// Number of failed clear operations.
  final int failureCount;

  @override
  String toString() => 'AppDataClearException($failureCount failures)';
}
