// =============================================================================
// StorageService — SET-06, space used and deleting the audio
// =============================================================================
//
// "Delete recordings" is a button a parent presses when the phone is full,
// quickly and without reading much. So what it must never do is the point of
// most of these tests:
//
//   **The collection stays.** Detections, stars and the life list are not
//   audio, and nothing here touches them.
//
//   **Kept recordings stay, unless asked.** A child was told those are safe.
//
//   **Nothing while listening.** A session is writing into that directory.
//
// And what it must do: free *all* the audio — including files nothing in the
// app points at any more, which no other code path would ever remove.
// =============================================================================

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/storage/storage_service.dart';

void main() {
  const cell = GridCell(508, 129);
  final may4 = DateTime(2026, 5, 4, 9);

  final scale = () {
    final raw = <String, double>{
      for (var rank = 0; rank < 40; rank++)
        'Species sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: const RarityScaleKey(cell, 18),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }();

  late AppDatabase db;
  late ScoringRepository scoring;
  late Directory documents;
  late Directory temporary;
  late bool listening;
  late StorageService storage;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scoring = ScoringRepository(db);
    documents = Directory.systemTemp.createTempSync('storage_docs');
    temporary = Directory.systemTemp.createTempSync('storage_tmp');
    listening = false;
    storage = StorageService(
      db: db,
      isListening: () => listening,
      documents: () async => documents,
      temporary: () async => temporary,
    );
    sessionId = await scoring.startSession(startedAt: may4, cell: cell);
  });

  tearDown(() async {
    await db.close();
    for (final dir in [documents, temporary]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  File write(String path, int bytes) =>
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.filled(bytes, 1));

  String recordings(String name) =>
      p.join(documents.path, 'recordings', 'session-1', name);

  /// A scored detection of [name] with a clip of [bytes] on disk.
  Future<({String id, File clip})> heardWithClip(
    String name, {
    int bytes = 1000,
    bool kept = false,
  }) async {
    final recorded = await scoring.recordDetection(
      sessionId: sessionId,
      scientificName: name,
      confidence: 0.9,
      context: ScoringContext(
        now: may4,
        appliedThreshold: 35,
        filterEnabled: true,
        scale: scale,
        cell: cell,
      ),
    );
    final clip = write(recordings('clip_$name.wav'), bytes);
    await scoring.setClipPath(
      detectionId: recorded.detectionId,
      clipPath: clip.path,
    );
    if (kept) {
      await scoring.setClipFavourite(
        detectionId: recorded.detectionId,
        isFavourite: true,
      );
    }
    return (id: recorded.detectionId, clip: clip);
  }

  Future<String?> clipPathOf(String id) async {
    final row =
        await (db.select(db.detections)
          ..where((d) => d.id.equals(id))).getSingle();
    return row.audioClipPath;
  }

  group('what it measures', () {
    test('recordings, kept ones, and the collection beside them', () async {
      await heardWithClip('Species sp0', bytes: 3000);
      await heardWithClip('Species sp1', bytes: 2000, kept: true);
      // A whole session from the old Full mode: nothing points at it.
      write(recordings('full.flac'), 5000);
      // A playback copy in the temporary directory.
      write(p.join(temporary.path, 'birdnet_norm_cache', 'x.wav'), 500);
      write(p.join(documents.path, 'smartfinch.sqlite'), 700);
      write(p.join(documents.path, 'backups', 'auto-1.zip'), 300);

      final usage = await storage.measure();

      expect(usage.recordingCount, 3);
      expect(usage.keptCount, 1);
      expect(usage.recordingBytes, 3000 + 2000 + 5000 + 500);
      expect(usage.collectionBytes, 700 + 300);
      expect(usage.totalBytes, 11500);
    });

    test('a device with nothing on it measures nothing', () async {
      final usage = await storage.measure();

      expect(usage.recordingBytes, 0);
      expect(usage.recordingCount, 0);
      expect(usage.collectionBytes, 0);
    });
  });

  group('deleting recordings', () {
    test('frees every recording a child did not keep', () async {
      final plain = await heardWithClip('Species sp0', bytes: 3000);
      final kept = await heardWithClip('Species sp1', bytes: 2000, kept: true);
      final orphan = write(recordings('full.flac'), 5000);
      final cache = write(
        p.join(temporary.path, 'shared_clips', 'clip.wav'),
        400,
      );

      final result = await storage.deleteRecordings();

      expect(plain.clip.existsSync(), isFalse);
      expect(orphan.existsSync(), isFalse);
      expect(cache.existsSync(), isFalse);
      expect(kept.clip.existsSync(), isTrue);
      expect(result.deleted, 2);
      expect(result.freedBytes, 3000 + 5000 + 400);
    });

    test('the journal stops offering what is gone, and only that', () async {
      final plain = await heardWithClip('Species sp0');
      final kept = await heardWithClip('Species sp1', kept: true);

      await storage.deleteRecordings();

      expect(await clipPathOf(plain.id), isNull);
      expect(await clipPathOf(kept.id), kept.clip.path);
    });

    test('kept ones go too only when asked, and stay marked', () async {
      final kept = await heardWithClip('Species sp1', kept: true);

      await storage.deleteRecordings(includeKept: true);

      expect(kept.clip.existsSync(), isFalse);
      expect(await clipPathOf(kept.id), isNull);
      // What the child valued is still on record, as after a restore.
      final row =
          await (db.select(db.detections)
            ..where((d) => d.id.equals(kept.id))).getSingle();
      expect(row.clipIsFavourite, isTrue);
    });

    test('the collection is untouched', () async {
      await heardWithClip('Species sp0');
      await heardWithClip('Species sp5', kept: true);
      Future<List<Object>> collection() async => [
        (await db.select(db.detections).get()).length,
        (await db.select(db.scoreEvents).get()).fold<int>(
          0,
          (sum, e) => sum + e.total,
        ),
        (await db.select(db.lifeSpecies).get()).length,
      ];
      final before = await collection();

      await storage.deleteRecordings(includeKept: true);

      expect(await collection(), before);
    });

    test('nothing is deleted while a session is listening', () async {
      final plain = await heardWithClip('Species sp0');
      listening = true;

      await expectLater(
        storage.deleteRecordings(),
        throwsA(isA<StillListeningException>()),
      );
      expect(plain.clip.existsSync(), isTrue);
      expect(await clipPathOf(plain.id), plain.clip.path);
    });

    test('emptied session folders go, the recordings folder stays', () async {
      await heardWithClip('Species sp0');

      await storage.deleteRecordings();

      final root = Directory(p.join(documents.path, 'recordings'));
      expect(root.existsSync(), isTrue);
      expect(root.listSync(), isEmpty);
    });
  });

  group('sizes, as a parent reads them', () {
    test('powers of a thousand, like the phone itself', () {
      expect(formatStorageSize(0, 'en'), '0 KB');
      expect(formatStorageSize(350000, 'en'), '350 KB');
      expect(formatStorageSize(2400000, 'en'), '2.4 MB');
      expect(formatStorageSize(120000000, 'en'), '120 MB');
      expect(formatStorageSize(1200000000, 'en'), '1.2 GB');
    });

    test('with the decimal comma where the language has one', () {
      expect(formatStorageSize(2400000, 'de'), '2,4 MB');
    });
  });
}
