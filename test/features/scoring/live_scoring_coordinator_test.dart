// =============================================================================
// LiveScoringCoordinator — the two moments of D15
// =============================================================================
//
// The engine tests prove the arithmetic and the repository tests prove the
// writes. What is left to prove is *timing*:
//
//   * a detection scores **once**, on the window where it appears — not again
//     on every window that raises its confidence;
//   * the peak confidence is written back when it ends, and changes nothing;
//   * the queue is serial, so two detections of the same species cannot race
//     each other into the same `DaySpecies` row.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart' hide Detection;
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/detection_accumulator.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/inference/geo_model.dart';
import 'package:smartfinch/features/inference/models/detection.dart';
import 'package:smartfinch/features/inference/models/species.dart';
import 'package:smartfinch/features/live/live_session.dart';
import 'package:smartfinch/features/scoring/live_scoring_coordinator.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';

/// A cache pre-loaded with one scale, so no geo model is needed.
///
/// [RarityScaleCache] builds by running 48 ONNX inferences; the coordinator
/// only ever calls `peek`, so a cache that already holds the answer exercises
/// the real path without the model.
class _StubScaleCache implements RarityScaleCache {
  _StubScaleCache(this._scale);

  final RarityScale _scale;

  /// Keys asked for that were not in the cache.
  final List<RarityScaleKey> misses = [];

  @override
  RarityScale? peek(RarityScaleKey key) {
    if (key == _scale.key) return _scale;
    misses.add(key);
    return null;
  }

  @override
  Future<RarityScale> get(RarityScaleKey key) async => _scale;

  @override
  void clear() {}

  @override
  int get size => 1;

  @override
  int get maxEntries => 6;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late ScoringRepository repo;
  late LiveScoringCoordinator coordinator;
  late _StubScaleCache scales;

  const cell = GridCell(508, 129);

  /// Monday 4 May 2026, 14:30 — geo week 18.
  final may4 = DateTime(2026, 5, 4, 14, 30);

  RarityScale buildScale(Map<String, int> ranks, {int count = 40}) {
    final byRank = {for (final e in ranks.entries) e.value: e.key};
    final raw = <String, double>{
      for (var rank = 0; rank < count; rank++)
        byRank[rank] ?? 'Fillerus sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: RarityScaleKey(cell, GeoModel.dateTimeToWeek(may4)),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }

  const scoring = LiveScoringConditions(
    appliedThreshold: 35,
    filterEnabled: true,
    cell: cell,
  );

  const paused = LiveScoringConditions(
    appliedThreshold: 35,
    filterEnabled: false,
    cell: cell,
  );

  /// What the coordinator reads on every cycle.
  ///
  /// Mutable on purpose: the threshold, the filter and the cell can all change
  /// while a session runs, and the coordinator reading them fresh rather than
  /// capturing them at session start is the behaviour under test.
  late LiveScoringConditions conditions;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ScoringRepository(db);
    scales = _StubScaleCache(
      buildScale({
        'Turdus merula': 1, // abundant · 50
        'Erithacus rubecula': 5, // common · 100
      }),
    );
    conditions = scoring;
    coordinator = LiveScoringCoordinator(
      repository: repo,
      scales: scales,
      conditions: () => conditions,
    );
    await coordinator.beginSession(startedAt: may4, cell: cell);
  });

  tearDown(() async => db.close());

  Detection detectionOf(String name, double confidence) => Detection(
    species: Species(
      index: 0,
      id: 0,
      scientificName: name,
      commonName: name,
      className: 'Aves',
      order: 'Passeriformes',
    ),
    confidence: confidence,
    timestamp: may4,
  );

  DetectionRecord recordOf(String name, double confidence, {DateTime? at}) =>
      DetectionRecord(
        scientificName: name,
        commonName: name,
        confidence: confidence,
        timestamp: at ?? may4,
      );

  /// One cycle: [opened] began, [changed] rose in confidence, [closed] ended.
  DetectionCycleResult cycle({
    List<DetectionRecord> opened = const [],
    List<DetectionRecord> changed = const [],
    List<DetectionRecord> closed = const [],
  }) => DetectionCycleResult(
    changes: [
      for (final record in opened)
        DetectionRecordChange(
          detection: detectionOf(record.scientificName, record.confidence),
          record: record,
          previousConfidence: record.confidence,
          isNew: true,
        ),
      for (final record in changed)
        DetectionRecordChange(
          detection: detectionOf(record.scientificName, record.confidence),
          record: record,
          previousConfidence: record.confidence - 0.1,
          isNew: false,
        ),
    ],
    closedRecords: closed,
  );

  group('D15 · a detection scores on the window it appears', () {
    test('a new record earns its stars', () async {
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.6)]));
      await coordinator.drain();

      expect(await repo.totalStars(), 150, reason: '50 × 3 first find');
      expect(await db.select(db.detections).get(), hasLength(1));
    });

    test('a confidence update does not score again', () async {
      final record = recordOf('Turdus merula', 0.6);
      coordinator.submitCycle(cycle(opened: [record]));
      await coordinator.drain();
      final afterFirst = await repo.totalStars();

      // The same detection, three windows later, louder.
      coordinator.submitCycle(
        cycle(changed: [recordOf('Turdus merula', 0.93)]),
      );
      await coordinator.drain();

      expect(await repo.totalStars(), afterFirst);
      expect(await db.select(db.detections).get(), hasLength(1));
    });

    test('closing writes the peak back without changing the award', () async {
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.6)]));
      await coordinator.drain();
      final awarded = await repo.totalStars();

      coordinator.submitCycle(cycle(closed: [recordOf('Turdus merula', 0.93)]));
      await coordinator.drain();

      final detection = (await db.select(db.detections).get()).single;
      expect(detection.confidence, closeTo(0.6, 1e-9));
      expect(detection.peakConfidence, closeTo(0.93, 1e-9));
      expect(await repo.totalStars(), awarded);
    });

    test('a close for an unknown record is ignored, not an error', () async {
      // Can happen after a pause: the accumulator closes a record whose
      // opening cycle belonged to a session that has already ended.
      coordinator.submitCycle(cycle(closed: [recordOf('Turdus merula', 0.9)]));

      await expectLater(coordinator.drain(), completes);
      expect(await db.select(db.detections).get(), isEmpty);
    });
  });

  group('SET-12 · the clip path reaches the database', () {
    test('a clip attached after scoring lands on the row', () async {
      final record = recordOf('Turdus merula', 0.6);
      coordinator.submitCycle(cycle(opened: [record]));
      await coordinator.drain();

      coordinator.submitClip(record, '/clips/blackbird.flac');
      await coordinator.drain();

      final detection = (await db.select(db.detections).get()).single;
      expect(detection.audioClipPath, '/clips/blackbird.flac');
    });

    test(
      '⚠️ a clip that lands after the detection closed still finds it',
      () async {
        // Cutting a clip means waiting for post-roll and then encoding, so it
        // routinely arrives after the detection ended. Removing the row id on
        // close — which is what the first version did — silently dropped every
        // one of them.
        final record = recordOf('Turdus merula', 0.6);
        coordinator.submitCycle(cycle(opened: [record]));
        coordinator.submitCycle(cycle(closed: [record]));
        await coordinator.drain();

        coordinator.submitClip(record, '/clips/late.flac');
        await coordinator.drain();

        final detection = (await db.select(db.detections).get()).single;
        expect(detection.audioClipPath, '/clips/late.flac');
        expect(detection.peakConfidence, isNotNull, reason: 'close still ran');
      },
    );

    test('a clip for an unknown detection is ignored, not an error', () async {
      coordinator.submitClip(recordOf('Turdus merula', 0.6), '/clips/x.flac');

      await expectLater(coordinator.drain(), completes);
      expect(await db.select(db.detections).get(), isEmpty);
    });

    test('a paused detection still gets its clip path', () async {
      // The recordings are kept while scoring is off (LOG-15), so they have to
      // be findable by the retention job like any other.
      conditions = paused;
      final record = recordOf('Turdus merula', 0.6);
      coordinator.submitCycle(cycle(opened: [record]));
      await coordinator.drain();

      coordinator.submitClip(record, '/clips/paused.flac');
      await coordinator.drain();

      final detection = (await db.select(db.detections).get()).single;
      expect(detection.scoringPaused, isTrue);
      expect(detection.audioClipPath, '/clips/paused.flac');
    });

    test('nothing is written once the session has ended', () async {
      final record = recordOf('Turdus merula', 0.6);
      coordinator.submitCycle(cycle(opened: [record]));
      await coordinator.endSession(endedAt: may4);

      coordinator.submitClip(record, '/clips/orphan.flac');
      await coordinator.drain();

      final detection = (await db.select(db.detections).get()).single;
      expect(detection.audioClipPath, isNull);
    });
  });

  group('the queue is serial', () {
    test('two detections of one species in one cycle do not race', () async {
      // Both would read "not scored today" if they ran concurrently, and both
      // would try to insert the same DaySpecies row.
      coordinator.submitCycle(
        cycle(
          opened: [
            recordOf('Turdus merula', 0.6),
            recordOf(
              'Turdus merula',
              0.7,
              at: may4.add(const Duration(microseconds: 1)),
            ),
          ],
        ),
      );
      await coordinator.drain();

      expect(await db.select(db.daySpecies).get(), hasLength(1));
      expect(await db.select(db.detections).get(), hasLength(2));
      expect(await repo.totalStars(), 150);
    });

    test('the repeat is counted on the day row', () async {
      coordinator.submitCycle(
        cycle(
          opened: [
            recordOf('Turdus merula', 0.6),
            recordOf(
              'Turdus merula',
              0.7,
              at: may4.add(const Duration(microseconds: 1)),
            ),
          ],
        ),
      );
      await coordinator.drain();

      expect((await db.select(db.daySpecies).get()).single.detectionCount, 2);
    });

    test('several species in one cycle all score', () async {
      coordinator.submitCycle(
        cycle(
          opened: [
            recordOf('Turdus merula', 0.6),
            recordOf('Erithacus rubecula', 0.8),
          ],
        ),
      );
      await coordinator.drain();

      expect(await repo.totalStars(), 150 + 300);
      expect(await db.select(db.daySpecies).get(), hasLength(2));
    });
  });

  group('PKT-20 · a paused session still records', () {
    test('the detection is written and flagged, and nothing scores', () async {
      conditions = paused;
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();

      expect(
        (await db.select(db.detections).get()).single.scoringPaused,
        isTrue,
      );
      expect(await db.select(db.lifeSpecies).get(), isEmpty);
      expect(await repo.totalStars(), 0);
    });

    test('the peak is still written back — the recording is kept', () async {
      conditions = paused;
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.6)]));
      coordinator.submitCycle(cycle(closed: [recordOf('Turdus merula', 0.88)]));
      await coordinator.drain();

      final detection = (await db.select(db.detections).get()).single;
      expect(detection.peakConfidence, closeTo(0.88, 1e-9));
    });

    test('turning the filter back on resumes scoring immediately', () async {
      // The conditions are read per cycle, not captured at session start, so
      // an adult who switches the filter back on mid-walk does not have to
      // restart the session for the child to start earning again.
      conditions = paused;
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();
      expect(await repo.totalStars(), 0);

      conditions = scoring;
      coordinator.submitCycle(
        cycle(opened: [recordOf('Erithacus rubecula', 0.9)]),
      );
      await coordinator.drain();

      expect(await repo.totalStars(), 300);
    });

    test('a paused first find is not burned — the ×3 survives', () async {
      // The failure this whole layer exists to prevent, end to end.
      conditions = paused;
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();

      conditions = scoring;
      coordinator.submitCycle(
        cycle(
          opened: [
            recordOf(
              'Turdus merula',
              0.9,
              at: may4.add(const Duration(days: 1)),
            ),
          ],
        ),
      );
      await coordinator.drain();

      expect(await repo.totalStars(), 150, reason: '50 × 3, not 50');
    });
  });

  group('sessions', () {
    test('nothing is recorded before a session begins', () async {
      final idle = LiveScoringCoordinator(
        repository: repo,
        scales: scales,
        conditions: () => conditions,
      );

      idle.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await idle.drain();

      expect(await db.select(db.detections).get(), isEmpty);
    });

    test('ending drains the queue before it closes', () async {
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      // Deliberately not drained: endSession has to do it.
      await coordinator.endSession(endedAt: may4);

      expect(await db.select(db.detections).get(), hasLength(1));
      expect(coordinator.isRunning, isFalse);
    });

    test('nothing is recorded after a session ends', () async {
      await coordinator.endSession(endedAt: may4);

      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();

      expect(await db.select(db.detections).get(), isEmpty);
    });

    test('the session records when it ended', () async {
      final ended = may4.add(const Duration(minutes: 40));
      await coordinator.endSession(endedAt: ended);

      expect((await db.select(db.sessions).get()).single.endedAt, ended);
    });
  });

  group('the scale', () {
    test('a detection with no position scores nothing', () async {
      const nowhere = LiveScoringConditions(
        appliedThreshold: 35,
        filterEnabled: true,
      );
      conditions = nowhere;

      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();

      expect(await repo.totalStars(), 0);
      expect(await db.select(db.detections).get(), hasLength(1));
    });

    test('the event freezes the cell the scale was built for', () async {
      // A cache miss falls back to the last scale rather than blocking on 48
      // inferences — and then the *fallback's* cell must be what is frozen,
      // or the history would claim a value that cell never produced.
      coordinator.submitCycle(cycle(opened: [recordOf('Turdus merula', 0.9)]));
      await coordinator.drain();

      const walkedOn = LiveScoringConditions(
        appliedThreshold: 35,
        filterEnabled: true,
        cell: GridCell(600, 200),
      );
      conditions = walkedOn;
      coordinator.submitCycle(
        cycle(opened: [recordOf('Erithacus rubecula', 0.9)]),
      );
      await coordinator.drain();

      expect(scales.misses, isNotEmpty, reason: 'the new cell is not cached');

      final events = await db.select(db.scoreEvents).get();
      for (final event in events) {
        expect(
          event.gridCell,
          '50.8,12.9',
          reason: 'the cell the scale belongs to',
        );
      }
    });
  });
}
