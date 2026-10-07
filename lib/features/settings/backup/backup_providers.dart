// =============================================================================
// Backup providers — SET-07 and DAT-09
// =============================================================================
//
// Apart from the screen because the automatic backup is started from two
// places that have nothing to do with it — the home screen when the app
// opens, and live mode when a session ends — and neither should have to
// import the backup screen to reach it.
// =============================================================================

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scoring/scoring_providers.dart';
import 'auto_backup_service.dart';
import 'backup_service.dart';

/// Reads and writes the whole collection as one file (`SET-07`).
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});

/// Where the automatic backups live. A provider so tests can point it at a
/// temporary directory instead of a platform channel.
final autoBackupDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultAutoBackupDirectory,
);

/// The rolling local backups (`DAT-09`).
///
/// One instance per database, so app start and the end of a session that ask
/// at the same moment share a single run.
final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  return AutoBackupService(
    ref.watch(appDatabaseProvider),
    ref.watch(backupServiceProvider),
    directory: ref.watch(autoBackupDirectoryProvider),
  );
});

/// The kept generations with what each holds, newest first — for the backup
/// screen. Re-read each time the screen opens.
final autoBackupEntriesProvider =
    FutureProvider.autoDispose<List<AutoBackupEntry>>((ref) {
      return ref.watch(autoBackupServiceProvider).entries();
    });
