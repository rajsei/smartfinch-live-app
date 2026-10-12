// =============================================================================
// Clip retention settings — SET-12
// =============================================================================
//
// The two thresholds are settings now, and a setting that deletes is held to
// two promises:
//
//   * **what the app counts before asking is what goes** — the count is a
//     dry run over the same clips the job would delete, and deletes nothing;
//   * **a broken stored value never widens the clean-up** — a cap of 0 would
//     take every recording older than the minimum age with it.
// =============================================================================

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/constants/app_constants.dart';
import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/audio/ring_buffer.dart';
import 'package:smartfinch/features/recording/recording_service.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/storage/clip_retention.dart';
import 'package:smartfinch/features/storage/clip_retention_job.dart';
import 'package:smartfinch/features/storage/clip_retention_settings.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  group('the settings', () {
    Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('nothing stored means the shipped 30 days and 100', () async {
      final container = await containerWith({});
      final policy = container.read(clipRetentionPolicyProvider);

      expect(policy.minimumAge, const Duration(days: 30));
      expect(policy.perSpeciesCap, 100);
    });

    test('a stored choice is the one the job applies', () async {
      final container = await containerWith({
        PrefKeys.clipRetentionDays: 90,
        PrefKeys.clipRetentionPerSpecies: 20,
      });
      final policy = container.read(clipRetentionPolicyProvider);

      expect(policy.minimumAge, const Duration(days: 90));
      expect(policy.perSpeciesCap, 20);
    });

    test('changing a setting changes the policy at once', () async {
      final container = await containerWith({});

      await container.read(clipRetentionPerSpeciesProvider.notifier).set(50);

      expect(container.read(clipRetentionPolicyProvider).perSpeciesCap, 50);
    });

    test('⚠️ a broken stored value falls back rather than widening', () async {
      final container = await containerWith({
        PrefKeys.clipRetentionDays: 0,
        PrefKeys.clipRetentionPerSpecies: -5,
      });
      final policy = container.read(clipRetentionPolicyProvider);

      expect(policy.minimumAge, const Duration(days: 30));
      expect(policy.perSpeciesCap, 100);
    });
  });

  group('counting before asking', () {
    late AppDatabase db;
    late Directory dir;
    late String sessionId;
    late RecordingService recordings;
    final now = DateTime(2026, 5, 4);

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      dir = await Directory.systemTemp.createTemp('retention_settings_test');
      recordings = RecordingService(ringBuffer: RingBuffer(capacity: 10));
      sessionId = await ScoringRepository(db).startSession(startedAt: now);
    });

    tearDown(() async {
      await db.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    /// [count] blackbird clips, sixty days old, each with a file on disk.
    Future<List<File>> blackbirds(int count) async {
      final files = <File>[];
      for (var i = 0; i < count; i++) {
        final file = File('${dir.path}/blackbird_$i.wav');
        await file.writeAsBytes(const [0, 1, 2, 3]);
        files.add(file);
        await db
            .into(db.detections)
            .insert(
              DetectionsCompanion.insert(
                id: 'blackbird-$i',
                profileId: kDefaultProfileId,
                updatedAt: now,
                sessionId: sessionId,
                scientificName: 'Turdus merula',
                detectedAt: now.subtract(const Duration(days: 60)),
                confidence: 0.4 + i * 0.01,
                audioClipPath: Value(file.path),
              ),
            );
      }
      return files;
    }

    ClipRetentionJob job(ClipRetentionPolicy policy) =>
        ClipRetentionJob(db: db, recordings: recordings, policy: policy);

    test('the count deletes nothing', () async {
      final files = await blackbirds(30);

      final count = await job(
        const ClipRetentionPolicy(),
      ).wouldDelete(const ClipRetentionPolicy(perSpeciesCap: 20), now: now);

      expect(count, 10);
      for (final file in files) {
        expect(await file.exists(), isTrue);
      }
      final withPath =
          await (db.select(db.detections)
            ..where((d) => d.audioClipPath.isNotNull())).get();
      expect(withPath, hasLength(30));
    });

    test('what was counted is what the stricter job deletes', () async {
      await blackbirds(30);
      const stricter = ClipRetentionPolicy(perSpeciesCap: 20);

      final counted = await job(
        const ClipRetentionPolicy(),
      ).wouldDelete(stricter, now: now);
      final result = await job(stricter).run(now: now);

      expect(result.deleted, counted);
      expect(result.failed, 0);
    });

    test('a looser setting has nothing to count', () async {
      await blackbirds(30);

      final count = await job(const ClipRetentionPolicy()).wouldDelete(
        const ClipRetentionPolicy(
          minimumAge: Duration(days: 90),
          perSpeciesCap: 500,
        ),
        now: now,
      );

      expect(count, 0);
    });
  });
}
