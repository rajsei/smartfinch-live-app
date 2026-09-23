// =============================================================================
// Scoring providers — the database, the repository, the coordinator
// =============================================================================
//
// One database and one repository for the process. Both are cheap to hold and
// expensive to build twice: a second `AppDatabase` on the same file would give
// two connections their own transaction view, and the `DaySpecies` UNIQUE
// constraint would start rejecting writes that should have been prevented by
// the engine one layer up.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/database/app_database.dart';
import '../../core/services/grid_cell.dart';
import '../../shared/providers/settings_providers.dart';
import '../explore/explore_providers.dart';
import '../live/live_providers.dart';
import '../storage/clip_retention_job.dart';
import 'live_score_board.dart';
import 'live_scoring_coordinator.dart';
import 'rarity_scale_provider.dart';
import 'scoring_repository.dart';

/// The app's SQLite database (DAT-01).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The only thing that writes the scoring layer.
final scoringRepositoryProvider = Provider<ScoringRepository>((ref) {
  return ScoringRepository(ref.watch(appDatabaseProvider));
});

/// Connects an inference cycle to the repository.
///
/// A `FutureProvider` because it needs the scale cache, which needs the loaded
/// geo model. **Resolve it once when a session starts.** The scales themselves
/// are built per cell and week, in the background; scoring waits for one only
/// in its own queue, never in the inference loop.
///
/// The coordinator reads its conditions and publishes its results through
/// *this* provider's `ref`, which lives as long as the app. That matters: a
/// live session outlives the live screen — leaving the screen keeps recording
/// — so anything wired to the screen's `ref` would start throwing partway
/// through a walk and the child would earn nothing for the rest of it.
final liveScoringCoordinatorProvider = FutureProvider<LiveScoringCoordinator>((
  ref,
) async {
  final scales = await ref.watch(rarityScaleCacheProvider.future);

  final coordinator = LiveScoringCoordinator(
    repository: ref.watch(scoringRepositoryProvider),
    scales: scales,
    conditions: () => ref.read(liveScoringConditionsProvider),
  );

  final board = ref.watch(liveScoreBoardProvider);
  coordinator.onScored = (scored) {
    board.record(scored.record.scientificName, scored.result);
    ref.invalidate(totalStarsProvider);
  };
  return coordinator;
});

/// The `SET-12` clip clean-up.
///
/// Not watched by any screen: it is a job, and it is read once at startup.
final clipRetentionJobProvider = Provider<ClipRetentionJob>((ref) {
  return ClipRetentionJob(
    db: ref.watch(appDatabaseProvider),
    recordings: ref.watch(recordingServiceProvider),
  );
});

/// Today's scoring, as the live screen sees it.
///
/// A `ChangeNotifier` rather than a provider that rebuilds: the detection list
/// redraws on every inference cycle, and a card asking the database what a
/// species earned would be a query per row per second.
final liveScoreBoardProvider = ChangeNotifierProvider<LiveScoreBoard>((ref) {
  return LiveScoreBoard.forDay(dayKeyFor(DateTime.now()));
});

/// The conditions in force right now: threshold, filter, and where we are.
///
/// Read fresh on every cycle rather than captured at session start, because
/// all three can change mid-session — the child walks into a new cell, an
/// adult moves the confidence slider.
final liveScoringConditionsProvider = Provider<LiveScoringConditions>((ref) {
  final location = ref.watch(currentLocationProvider).value;

  return LiveScoringConditions(
    appliedThreshold: ref.watch(confidenceThresholdProvider),
    filterEnabled: ref.watch(speciesFilterModeProvider) != 'off',
    cell:
        location == null
            ? null
            : GridCell.fromCoordinates(location.latitude, location.longitude),
  );
});

/// The profile's running star total.
///
/// Invalidate after a detection scores; the home and live headers watch it.
final totalStarsProvider = FutureProvider<int>((ref) async {
  return ref.watch(scoringRepositoryProvider).totalStars();
});

/// The three numbers in the home screen's star header (HOME-01, HOME-02).
///
/// Invalidated together with [totalStarsProvider] whenever a detection scores,
/// so a child who comes back from a session finds the header already right
/// rather than one frame behind.
final starTotalsProvider = FutureProvider<StarTotals>((ref) async {
  // Depends on the running total so one invalidation refreshes both.
  await ref.watch(totalStarsProvider.future);
  return ref.watch(scoringRepositoryProvider).starTotals(now: DateTime.now());
});
