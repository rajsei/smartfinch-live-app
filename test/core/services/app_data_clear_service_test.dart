// =============================================================================
// App Data Clear Service Tests
// =============================================================================

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/app_data_clear_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDir;
  late Directory temporaryDir;

  setUp(() async {
    documentsDir = await Directory.systemTemp.createTemp('birdnet_docs_');
    temporaryDir = await Directory.systemTemp.createTemp('birdnet_temp_');
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
  });

  tearDown(() async {
    if (await documentsDir.exists()) {
      await documentsDir.delete(recursive: true);
    }
    if (await temporaryDir.exists()) {
      await temporaryDir.delete(recursive: true);
    }
  });

  Future<void> writeFile(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('data');
  }

  test(
    'clears user data stores while preserving unrelated app assets',
    () async {
      // The side files are what an unclean shutdown leaves behind: sqlite3
      // writes through them and folds them back on a clean close, so a kill
      // during a session can leave a `-journal` holding the last rows. Left
      // in place, the next open replays it — a wipe that gave data back.
      await writeFile('${documentsDir.path}/smartfinch.sqlite');
      await writeFile('${documentsDir.path}/smartfinch.sqlite-journal');
      await writeFile('${documentsDir.path}/smartfinch.sqlite-wal');
      await writeFile('${documentsDir.path}/smartfinch.sqlite-shm');
      await writeFile('${documentsDir.path}/sessions/session.json');
      await writeFile('${documentsDir.path}/recordings/session/full.flac');
      await writeFile('${documentsDir.path}/species_lists/watchlist.txt');
      await writeFile('${documentsDir.path}/models/audio.onnx');
      await writeFile('${temporaryDir.path}/birdnet_norm_cache/clip.wav');
      await writeFile('${temporaryDir.path}/birdnet_spec_wav/session.wav');
      await writeFile('${temporaryDir.path}/shared_clips/clip.flac');
      await writeFile('${temporaryDir.path}/other_cache/keep.tmp');

      var mapTileCacheCleared = false;
      final service = AppDataClearService(
        databaseCloser: () async {},
        documentsDirectoryProvider: () async => documentsDir,
        temporaryDirectoryProvider: () async => temporaryDir,
        mapTileCacheClearer: () async => mapTileCacheCleared = true,
      );

      await service.clearAllData();

      expect(
        File('${documentsDir.path}/smartfinch.sqlite').existsSync(),
        isFalse,
      );
      expect(
        File('${documentsDir.path}/smartfinch.sqlite-journal').existsSync(),
        isFalse,
      );
      expect(
        File('${documentsDir.path}/smartfinch.sqlite-wal').existsSync(),
        isFalse,
      );
      expect(
        File('${documentsDir.path}/smartfinch.sqlite-shm').existsSync(),
        isFalse,
      );
      expect(Directory('${documentsDir.path}/sessions').existsSync(), isFalse);
      expect(
        Directory('${documentsDir.path}/recordings').existsSync(),
        isFalse,
      );
      expect(
        Directory('${documentsDir.path}/species_lists').existsSync(),
        isFalse,
      );
      expect(
        File('${documentsDir.path}/models/audio.onnx').existsSync(),
        isTrue,
      );
      expect(
        Directory('${temporaryDir.path}/birdnet_norm_cache').existsSync(),
        isFalse,
      );
      expect(
        Directory('${temporaryDir.path}/birdnet_spec_wav').existsSync(),
        isFalse,
      );
      expect(
        Directory('${temporaryDir.path}/shared_clips').existsSync(),
        isFalse,
      );
      expect(
        File('${temporaryDir.path}/other_cache/keep.tmp').existsSync(),
        isTrue,
      );
      expect(mapTileCacheCleared, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // The database (DAT-01)
  // ─────────────────────────────────────────────────────────────────────────
  //
  // Everything a child earned is in here — the collection, the stars, the
  // badges, the level, the avatar, and the journal's rows — while the
  // recordings those rows point at are files the wipe already removed. A
  // clear that took the files and left the database was the worse of the two
  // possible half-wipes: it emptied the journal's audio and kept the record
  // of every walk, which is the opposite of what `NFA-07` promises.
  test('closes the database, deletes it, and reopens an empty one', () async {
    final databasePath = p.join(documentsDir.path, kAppDatabaseFileName);
    final db = AppDatabase.forTesting(NativeDatabase(File(databasePath)));

    // A collected species, through the same chain the app writes: a session,
    // a detection in it, and the life-list row that makes it "collected".
    final now = DateTime(2026, 5, 4, 7, 30);
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'session-1',
            profileId: kDefaultProfileId,
            updatedAt: now,
            startedAt: now,
          ),
        );
    await db
        .into(db.detections)
        .insert(
          DetectionsCompanion.insert(
            id: 'detection-1',
            profileId: kDefaultProfileId,
            updatedAt: now,
            sessionId: 'session-1',
            scientificName: 'Erithacus rubecula',
            detectedAt: now,
            confidence: 0.91,
          ),
        );
    await db
        .into(db.lifeSpecies)
        .insert(
          LifeSpeciesCompanion.insert(
            id: 'life-1',
            profileId: kDefaultProfileId,
            updatedAt: now,
            scientificName: 'Erithacus rubecula',
            firstDetectionId: 'detection-1',
            firstSeenAt: now,
          ),
        );
    await (db.update(db.userProfiles)
      ..where((profile) => profile.id.equals(kDefaultProfileId))).write(
      const UserProfilesCompanion(
        totalStars: Value(420),
        highestLevelReached: Value(9),
      ),
    );
    expect(File(databasePath).existsSync(), isTrue);

    // Read at close time rather than after the fact, so the assertion below
    // is about the *order* and holds on every platform — not only on Windows,
    // where deleting an open file would have failed the whole wipe anyway.
    var databaseStillThereWhenClosed = false;
    final service = AppDataClearService(
      databaseCloser: () async {
        databaseStillThereWhenClosed = File(databasePath).existsSync();
        await db.close();
      },
      documentsDirectoryProvider: () async => documentsDir,
      temporaryDirectoryProvider: () async => temporaryDir,
      mapTileCacheClearer: () async {},
    );

    await service.clearAllData();

    // Closed first, and awaited: deleting a file the database still holds
    // open fails outright on Windows, and on POSIX unlinks it while the
    // connection keeps writing into a file nothing can reach again.
    expect(databaseStillThereWhenClosed, isTrue);
    expect(File(databasePath).existsSync(), isFalse);

    // And what the next launch opens is a working database, not the wreckage
    // of the old one: drift builds the schema and reseeds the profile.
    final reopened = AppDatabase.forTesting(NativeDatabase(File(databasePath)));
    addTearDown(reopened.close);

    expect(await reopened.select(reopened.lifeSpecies).get(), isEmpty);
    expect(await reopened.select(reopened.detections).get(), isEmpty);
    expect(await reopened.select(reopened.sessions).get(), isEmpty);

    final profile =
        await (reopened.select(reopened.userProfiles)
          ..where((row) => row.id.equals(kDefaultProfileId))).getSingle();
    expect(profile.totalStars, 0);
    expect(profile.highestLevelReached, 1);
  });

  test('attempts remaining stores before reporting clear failures', () async {
    final service = AppDataClearService(
      databaseCloser: () async {},
      documentsDirectoryProvider: () async => documentsDir,
      temporaryDirectoryProvider: () async => temporaryDir,
      mapTileCacheClearer: () async => throw StateError('cache locked'),
    );

    await expectLater(
      service.clearAllData(),
      throwsA(isA<AppDataClearException>()),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
