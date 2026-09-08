// =============================================================================
// ClipRetentionJob — reading, asking, deleting (SET-12)
// =============================================================================
//
// The policy decides; this applies. Same split as everywhere else in the
// scoring layer, and for the same reason: the decision is the part worth
// testing, and it should not need a filesystem to ask.
//
// ### Order of operations
//
// The **file goes first**, then the row is cleared. The other way round would
// leave orphaned audio on disk that nothing in the app can find or count —
// invisible to the child and invisible to the next run. Clearing a path whose
// file is already gone costs nothing.
//
// ### When it runs
//
// Once per app start, off the critical path. Not on a timer and not on every
// detection: nothing here is urgent, and a job that competes with inference
// for a disk is a job that drops frames during a live session (`NFA-13`).
// =============================================================================

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../core/database/app_database.dart';
import '../recording/recording_service.dart';
import 'clip_retention.dart';

/// What one run did.
@immutable
class ClipRetentionResult {
  const ClipRetentionResult({this.deleted = 0, this.failed = 0});

  final int deleted;

  /// Files that could not be removed. Their rows keep their path, so the next
  /// run tries again rather than losing track of them.
  final int failed;

  bool get didNothing => deleted == 0 && failed == 0;
}

/// Applies [ClipRetentionPolicy] to what is on disk.
class ClipRetentionJob {
  ClipRetentionJob({
    required AppDatabase db,
    required RecordingService recordings,
    this.policy = const ClipRetentionPolicy(),
    this.profileId = kDefaultProfileId,
  }) : _db = db,
       _recordings = recordings;

  final AppDatabase _db;
  final RecordingService _recordings;
  final ClipRetentionPolicy policy;
  final String profileId;

  /// Every clip currently on record.
  Future<List<ClipCandidate>> candidates() async {
    final rows =
        await (_db.select(_db.detections)..where(
          (d) => d.profileId.equals(profileId) & d.audioClipPath.isNotNull(),
        )).get();

    return [
      for (final row in rows)
        ClipCandidate(
          detectionId: row.id,
          scientificName: row.scientificName,
          recordedAt: row.detectedAt,
          // The peak is what the detection was really worth; the first
          // window's value is only a floor (D15).
          confidence: row.peakConfidence ?? row.confidence,
          path: row.audioClipPath!,
          isFavourite: row.clipIsFavourite,
        ),
    ];
  }

  /// Deletes what the policy selects.
  Future<ClipRetentionResult> run({DateTime? now}) async {
    final clips = await candidates();
    final doomed = policy.selectForDeletion(clips, now: now ?? DateTime.now());
    if (doomed.isEmpty) return const ClipRetentionResult();

    var deleted = 0;
    var failed = 0;

    for (final clip in doomed) {
      try {
        // File first, then the row. The reverse would leave audio on disk that
        // nothing can find or count.
        await _recordings.deleteClip(clip.path);
        await _clearPath(clip.detectionId);
        deleted++;
      } catch (error) {
        // The row keeps its path, so the next run tries again rather than
        // losing track of the file.
        debugPrint('[ClipRetention] could not remove ${clip.path}: $error');
        failed++;
      }
    }

    return ClipRetentionResult(deleted: deleted, failed: failed);
  }

  Future<void> _clearPath(String detectionId) async {
    await (_db.update(_db.detections)
      ..where((d) => d.id.equals(detectionId))).write(
      DetectionsCompanion(
        audioClipPath: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
