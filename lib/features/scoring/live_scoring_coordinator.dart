// =============================================================================
// LiveScoringCoordinator — from an inference cycle to stars on disk
// =============================================================================
//
// [DetectionAccumulator] already decides when a detection begins, how its peak
// changes and when it ends. Those are exactly D15's two moments:
//
//   * `DetectionRecordChange.isNew` — the first inference window over the
//     threshold. **This is when the species appears on screen, so this is when
//     it scores**, and the stars land at the same instant the bird does.
//   * `closedRecords` — the detection ended. The peak confidence is written
//     back here and changes nothing about the award (PKT-15).
//
// So this class is thin on purpose: it assembles a [ScoringContext] from what
// the session knows, and hands each new detection to the repository.
//
// ### Why the work is queued
//
// Scoring is asynchronous — reading the life list, the year list and the week
// is four queries — while inference is a tight loop that must not wait
// (NFA-13, principle 7). Detections are therefore appended to a queue and
// drained one at a time.
//
// One at a time is not tidiness. Two concurrent detections of the same species
// would both read a history saying "not scored today", both pass the engine's
// repeat check and both try to insert the same `DaySpecies` row. The database
// would refuse the second — the constraint holds — but the child would see a
// detection that failed for no reason they could understand. Serialising
// removes the race rather than surviving it.
//
// ### What it deliberately does not do
//
// Decide anything. Every rule lives in [ScoringEngine] and every write in
// [ScoringRepository]; this only carries values between them.
// =============================================================================

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/services/grid_cell.dart';
import '../inference/detection_accumulator.dart';
import '../live/live_session.dart';
import 'rarity_scale_provider.dart';
import 'scoring_engine.dart';
import 'scoring_repository.dart';
import 'scoring_rules.dart';

/// Everything about the current session that scoring needs and cannot read
/// from a detection.
@immutable
class LiveScoringConditions {
  const LiveScoringConditions({
    required this.appliedThreshold,
    required this.filterEnabled,
    this.cell,
  });

  final int appliedThreshold;
  final bool filterEnabled;

  /// Coarsened cell at this moment (D23). Null when there is no position —
  /// after D18 put the home region in onboarding this should not happen, but
  /// the engine must not invent a value.
  final GridCell? cell;

  bool get isScoring => ScoringRules.current.isScoring(
    threshold: appliedThreshold,
    filterEnabled: filterEnabled,
  );
}

/// A detection that has been scored, ready for the UI.
@immutable
class ScoredDetection {
  const ScoredDetection({required this.record, required this.result});

  /// The canonical record the live screen is already showing.
  final DetectionRecord record;

  final RecordedDetection result;
}

/// Turns inference cycles into `ScoreEvent` rows.
class LiveScoringCoordinator {
  LiveScoringCoordinator({
    required ScoringRepository repository,
    required RarityScaleCache scales,
    required LiveScoringConditions Function() conditions,
  }) : _repository = repository,
       _scales = scales,
       _conditions = conditions;

  final ScoringRepository _repository;
  final RarityScaleCache _scales;

  /// Reads the conditions in force right now.
  ///
  /// A callback rather than a stored value, because all three can change
  /// mid-session — the child walks into a new cell, an adult moves the
  /// confidence slider. And supplied by the caller rather than read here,
  /// because the live *screen* may be disposed while the session runs on: a
  /// closure that captured the screen's `ref` would start throwing halfway
  /// through a walk, and the child would earn nothing for the rest of it.
  final LiveScoringConditions Function() _conditions;

  /// Database session id, set by [beginSession]. Null when nothing is running.
  String? _sessionId;

  /// Detection-record identity → the `Detection` row it produced, so a close
  /// can find the row its peak belongs to.
  ///
  /// Keyed the way [DetectionAccumulator] keys records — species and start
  /// timestamp, never object identity, because a confidence update replaces
  /// the record object.
  final Map<(String, int), String> _rowIds = {};

  final Queue<_PendingDetection> _pending = Queue();
  Future<void>? _draining;

  /// The last scale that was actually available.
  ///
  /// A rebuild takes 48 inferences and must never interrupt listening
  /// (principle 7), so a detection during one is valued with the previous
  /// cell: off by at most a few minutes, and always explainable.
  RarityScale? _lastScale;

  /// Called after each detection is scored, on the main isolate.
  void Function(ScoredDetection scored)? onScored;

  bool get isRunning => _sessionId != null;

  /// Opens the database session a live session's detections belong to.
  Future<void> beginSession({
    required DateTime startedAt,
    GridCell? cell,
  }) async {
    await endSession(endedAt: startedAt);
    _sessionId = await _repository.startSession(
      startedAt: startedAt,
      cell: cell,
    );
  }

  /// Closes the session once every queued detection has been written.
  Future<void> endSession({required DateTime endedAt}) async {
    final id = _sessionId;
    if (id == null) return;

    await drain();
    _sessionId = null;
    _rowIds.clear();
    await _repository.endSession(id, endedAt: endedAt);
  }

  /// Hands one inference cycle to the scoring layer.
  ///
  /// Returns immediately: the work is queued. Safe to call from the inference
  /// loop.
  void submitCycle(DetectionCycleResult cycle) {
    if (_sessionId == null) return;

    // Read once per cycle, so every detection in it is scored under the same
    // conditions even if the queue drains slowly.
    final conditions = _conditions();

    for (final change in cycle.changes) {
      // Only the first window scores. Later windows of the same detection
      // raise its confidence, which is written back on close and does not
      // change the award (D15).
      if (!change.isNew) continue;
      _pending.add(_PendingDetection.opened(change.record, conditions));
    }

    for (final closed in cycle.closedRecords) {
      _pending.add(_PendingDetection.closed(closed, conditions));
    }

    unawaited(drain());
  }

  /// Waits until everything queued has been written.
  Future<void> drain() {
    return _draining ??= _drainLoop().whenComplete(() => _draining = null);
  }

  Future<void> _drainLoop() async {
    while (_pending.isNotEmpty) {
      final next = _pending.removeFirst();
      try {
        if (next.isClose) {
          await _close(next.record);
        } else {
          await _open(next.record, next.conditions);
        }
      } catch (error, stack) {
        // A failed detection must never stop the session or the queue behind
        // it. The raw row is written first and separately, so the worst case
        // here is stars lost for one bird, not a lost morning.
        debugPrint('[LiveScoringCoordinator] scoring failed: $error\n$stack');
      }
    }
  }

  Future<void> _open(
    DetectionRecord record,
    LiveScoringConditions conditions,
  ) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    final result = await _repository.recordDetection(
      sessionId: sessionId,
      scientificName: record.scientificName,
      confidence: record.confidence,
      context: await _contextFor(record.timestamp, conditions),
    );

    _rowIds[_keyOf(record)] = result.detectionId;

    // A species heard again after it already scored today still belongs in the
    // day's tally, even though it earns nothing (PKT-03).
    if (result.outcome.skipReason == ScoringSkipReason.alreadyScoredToday) {
      await _repository.countRepeat(
        dayKey: result.outcome.dayKey,
        scientificName: record.scientificName,
      );
    }

    onScored?.call(ScoredDetection(record: record, result: result));
  }

  Future<void> _close(DetectionRecord record) async {
    final rowId = _rowIds.remove(_keyOf(record));
    if (rowId == null) return;

    await _repository.writeBackPeakConfidence(
      detectionId: rowId,
      // The accumulator only ever raises a record's confidence, so by the time
      // it closes this *is* the peak.
      peakConfidence: record.confidence,
    );
  }

  /// Builds the context for a detection at [when].
  ///
  /// Uses [RarityScaleCache.peek], which returns immediately or not at all —
  /// blocking the queue on 48 inferences would delay every detection behind
  /// this one. A miss triggers a background build and falls back to the last
  /// scale that was available.
  Future<ScoringContext> _contextFor(
    DateTime when,
    LiveScoringConditions conditions,
  ) async {
    final cell = conditions.cell;
    RarityScale? scale;

    if (cell != null) {
      final key = RarityScaleKey.at(cell, when);
      scale = _scales.peek(key);
      if (scale == null) {
        // Warm it for the detections behind this one, but do not wait.
        unawaited(_warm(key));
        scale = _lastScale;
      } else {
        _lastScale = scale;
      }
    }

    return ScoringContext(
      now: when,
      appliedThreshold: conditions.appliedThreshold,
      filterEnabled: conditions.filterEnabled,
      scale: scale,
      // The cell the *scale* belongs to, not the one the phone is in: a
      // fallback scale from the previous cell must be frozen into the event
      // together with the cell it was actually built for (PKT-15), or the
      // history would claim a value that cell never produced.
      cell: scale?.key.cell,
    );
  }

  /// Builds a scale in the background so the detections behind this one find
  /// it ready. Failure is logged and dropped — the fallback scale still works.
  Future<void> _warm(RarityScaleKey key) async {
    try {
      _lastScale = await _scales.get(key);
    } catch (error) {
      debugPrint('[LiveScoringCoordinator] scale build failed: $error');
    }
  }

  (String, int) _keyOf(DetectionRecord record) => (
    record.scientificName,
    record.timestamp.microsecondsSinceEpoch,
  );
}

/// One queued unit of work.
class _PendingDetection {
  _PendingDetection.opened(this.record, this.conditions) : isClose = false;
  _PendingDetection.closed(this.record, this.conditions) : isClose = true;

  final DetectionRecord record;
  final LiveScoringConditions conditions;
  final bool isClose;
}
