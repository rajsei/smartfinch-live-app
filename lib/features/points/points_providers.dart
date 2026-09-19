// =============================================================================
// Points providers
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../scoring/scoring_providers.dart';
import '../scoring/scoring_repository.dart';
import 'chart_range.dart';
import 'still_possible.dart';
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
  return ref
      .watch(pointsRepositoryProvider)
      .overview(
        now: DateTime.now(),
        chartDays: ref.watch(chartRangeProvider).days,
      );
});

/// How far the 30-day chart looks back (`STAT-04`).
///
/// Session state rather than a stored setting: which window a child is looking
/// at is a thing they are doing right now, not a preference they hold. It
/// resets to the month, which is the one `STAT-02` was written for.
final chartRangeProvider = StateProvider<ChartRange>((ref) {
  return ChartRange.month;
});

/// The last seven days, for the home screen's sparkline (`HOME-05`).
///
/// Separate from [pointsOverviewProvider] so opening the home screen does not
/// derive every badge and achievement to draw seven bars.
final homeSparklineProvider = FutureProvider<List<DayStars>>((ref) async {
  await ref.watch(totalStarsProvider.future);
  return ref
      .watch(pointsRepositoryProvider)
      .dailyStars(now: DateTime.now(), days: 7);
});

/// The one or two things still worth going outside for (`HOME-06`).
///
/// Derived from the same badge list the Points area shows, so the home screen
/// cannot suggest something the catalogue already ticks off.
final stillPossibleProvider = FutureProvider<List<BadgeDefinition>>((
  ref,
) async {
  final overview = await ref.watch(pointsOverviewProvider.future);
  final now = DateTime.now();

  return stillPossibleToday(
    todayKey: dayKeyFor(now),
    lastEarnedOn: (key) => overview.badgeFor(key)?.lastEarnedOn,
    hour: now.hour,
  );
});
