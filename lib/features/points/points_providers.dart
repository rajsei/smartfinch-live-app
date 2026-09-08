// =============================================================================
// Points providers
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../scoring/scoring_providers.dart';
import 'points_models.dart';
import 'points_repository.dart';

/// Reads the Points area. Nothing here writes.
final pointsRepositoryProvider = Provider<PointsRepository>((ref) {
  return PointsRepository(ref.watch(appDatabaseProvider));
});

/// Everything the Points area shows, in one read.
///
/// Depends on the running total so a session that just ended refreshes the
/// figures, the chart, the badges and the achievements together — they are
/// four views of one set of tables and must never disagree.
final pointsOverviewProvider = FutureProvider<PointsOverview>((ref) async {
  await ref.watch(totalStarsProvider.future);
  return ref.watch(pointsRepositoryProvider).overview(now: DateTime.now());
});
