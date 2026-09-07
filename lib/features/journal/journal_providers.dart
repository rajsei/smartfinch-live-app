// =============================================================================
// Journal providers
// =============================================================================
//
// All read-only, and all invalidated by hand rather than kept live. A day that
// has been and gone does not change on its own, and the one case that does —
// the child renaming a place — invalidates exactly what it touched.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../scoring/scoring_providers.dart';
import 'journal_models.dart';
import 'journal_repository.dart';

/// Reads the journal. Writes belong to `ScoringRepository`.
final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(ref.watch(appDatabaseProvider));
});

/// Days with something on them, newest first (`LOG-02`).
final journalDaysProvider = FutureProvider<List<JournalDay>>((ref) async {
  return ref.watch(journalRepositoryProvider).days();
});

/// Everything one day contains (`LOG-03`).
final journalDayProvider = FutureProvider.family<JournalDayDetail, String>((
  ref,
  dayKey,
) async {
  return ref.watch(journalRepositoryProvider).detailFor(dayKey);
});

/// The sessions a day is made of — what a place name attaches to (`LOG-13`).
final journalDaySessionsProvider = FutureProvider.family<List<Session>, String>(
  (ref, dayKey) async {
    return ref.watch(journalRepositoryProvider).sessionsOn(dayKey);
  },
);

/// Place names the child has used before, most used first (`LOG-14`).
final journalKnownPlacesProvider = FutureProvider<List<String>>((ref) async {
  return ref.watch(journalRepositoryProvider).knownPlaceNames();
});
