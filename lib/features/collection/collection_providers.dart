// =============================================================================
// The Collection — what the child has found, and nothing else
// =============================================================================
//
// `SAM-02` splits this from Explore deliberately: two destinations answering
// two questions. **Explore** is the reference list — everything that occurs
// here, found or not. **The Collection** is the thing a child opens in the
// evening, and it shows only what they have found (decided 2026-10-12: the
// open cells went, and the silhouettes meant for them, `SAM-04b`, with them).
//
// ### Where "found" comes from
//
// From `LifeSpecies`, and from nowhere else.
//
// That table is the same one the first-find ×3 checks (`PKT-04`), so the album
// and the scoring engine cannot disagree. If the Collection drew its own
// conclusions — from raw detections, say — a child could see a species in
// their album and then be awarded ×3 for "finding" it a week later, which is
// exactly the kind of contradiction principle 6 forbids.
//
// A species heard while scoring was paused is therefore **not** in the
// Collection. It is in the journal, marked, with its recording (`LOG-15`);
// what it is not is collected.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../../shared/providers/settings_providers.dart';
import '../explore/explore_providers.dart';
import '../inference/geo_abundance.dart';
import '../scoring/scoring_providers.dart';
import '../scoring/scoring_rules.dart';
import 'collection_repository.dart';

/// Reads the life list and the year list.
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  return CollectionRepository(ref.watch(appDatabaseProvider));
});

/// Every species the child has ever collected, with when they first heard it.
///
/// Invalidated with [totalStarsProvider], so a first find during a session
/// reaches the album without the child having to reopen the app.
final collectedSpeciesProvider = FutureProvider<Map<String, DateTime>>((
  ref,
) async {
  await ref.watch(totalStarsProvider.future);
  return ref.watch(collectionRepositoryProvider).collected();
});

/// The collected set, synchronously, for the ticks Explore already draws.
///
/// Empty until the life list has loaded. That is the right failure: an
/// unticked species is a species you can still find, and briefly showing one
/// as open is far better than briefly showing one as collected.
final collectedSpeciesNamesProvider = Provider<Set<String>>((ref) {
  return ref.watch(collectedSpeciesProvider).value?.keys.toSet() ?? const {};
});

/// Species collected this calendar year — the year list (`SAM-16`, `PKT-12`).
///
/// A **second** collection, not a filtered view of the first. It empties on
/// 1 January without the life list losing anything, which is what solves the
/// motivation drop after roughly forty species: the first blackcap of the year
/// is worth something again even though you have had it three times before
/// (3.4).
final collectedThisYearProvider = FutureProvider<Map<String, DateTime>>((
  ref,
) async {
  await ref.watch(totalStarsProvider.future);
  return ref
      .watch(collectionRepositoryProvider)
      .collectedIn(DateTime.now().year);
});

/// One card in the album — always a species the child has found.
@immutable
class CollectionEntry {
  const CollectionEntry({
    required this.scientificName,
    required this.commonName,
    required this.taxonGroup,
    required this.collectedAt,
    this.tier,
    this.stars,
    this.collectedThisYearAt,
    this.imagePath,
  });

  final String scientificName;
  final String commonName;

  /// `Aves`, `Mammalia`, `Amphibia`, `Insecta` (`SAM-17`).
  final String taxonGroup;

  /// When it entered the life list.
  final DateTime collectedAt;

  /// Rarity here, this week (2.1) — or null when the species is not on the
  /// local list this week: a summer visitor in December, a bird found on
  /// holiday.
  final ExploreTier? tier;

  /// What this species is worth **here, this week** (`SAM-03`), or null for
  /// the same reason as [tier]: without a local level it scores nothing (D20).
  final int? stars;

  /// When it was first heard **this calendar year** (`SAM-16`).
  ///
  /// Null for a species on the life list that has not been heard again since
  /// January — which is precisely the state the year list exists to make
  /// visible.
  final DateTime? collectedThisYearAt;

  /// The bundled photo, or null when there is none.
  final String? imagePath;

  bool get isCollectedThisYear => collectedThisYearAt != null;

  /// Whether the species has a level here this week, and so a value.
  bool get isHereThisWeek => stars != null;

  /// Whether this entry belongs in [scope].
  bool isIn(CollectionScope scope) => switch (scope) {
    CollectionScope.all => true,
    CollectionScope.thisYear => isCollectedThisYear,
  };

  /// The find that orders [scope] — the first ever, or the first this year.
  DateTime dateIn(CollectionScope scope) => switch (scope) {
    CollectionScope.all => collectedAt,
    CollectionScope.thisYear => collectedThisYearAt ?? collectedAt,
  };
}

/// Which of the two collections the album is showing (`SAM-16`).
enum CollectionScope {
  /// Everything ever collected — the life list.
  all,

  /// Only what has been collected **this year**. Empties on 1 January without
  /// the life list losing anything (3.4).
  thisYear,
}

/// The local list by scientific name — what occurs here this week, with its
/// level (`DAT-10`).
///
/// Empty when there is no location or the geo model cannot run. The album
/// itself is the life list and does not depend on this; only the "here, this
/// week" values and the progress line do, and both say less rather than fail.
final collectionLocalSpeciesProvider =
    FutureProvider<Map<String, ExploreSpecies>>((ref) async {
      try {
        final species = await ref.watch(exploreSpeciesProvider.future);
        return {for (final s in species) s.scientificName: s};
      } catch (_) {
        return const {};
      }
    });

/// The album: every species the child has found, and nothing else.
///
/// Built from the **life list**, not from the local list. Species not found
/// yet are not shown at all — they are Explore's, which lists everything that
/// occurs here (`SAM-02`). And a found species stays in the album when it is
/// not here this week: a swallow collected in May is still collected in
/// December, it is only worth nothing here right now.
final collectionEntriesProvider = FutureProvider<List<CollectionEntry>>((
  ref,
) async {
  final collected = await ref.watch(collectedSpeciesProvider.future);
  final thisYear = await ref.watch(collectedThisYearProvider.future);
  final local = await ref.watch(collectionLocalSpeciesProvider.future);
  final taxonomy = await ref.watch(taxonomyServiceProvider.future);
  final speciesLocale = ref.watch(effectiveSpeciesLocaleProvider);
  final rules = ScoringRules.current;

  final entries = <CollectionEntry>[];
  for (final MapEntry(key: name, value: collectedAt) in collected.entries) {
    final here = local[name];
    final info = here?.taxonomy ?? taxonomy.lookup(name);
    entries.add(
      CollectionEntry(
        scientificName: name,
        commonName:
            info?.commonNameForLocale(speciesLocale) ?? here?.commonName ?? name,
        taxonGroup: info?.taxonGroup ?? '',
        collectedAt: collectedAt,
        tier: here?.tier,
        stars: here == null ? null : rules.starsFor(here.tier),
        collectedThisYearAt: thisYear[name],
        imagePath: info?.assetImagePath,
      ),
    );
  }

  // Newest find first: the album is opened in the evening, and what was found
  // today is what a child looks for.
  entries.sort((a, b) => b.collectedAt.compareTo(a.collectedAt));

  return entries;
});

/// "37 of 128 species in your region" (`SAM-05`).
@immutable
class CollectionProgress {
  const CollectionProgress({
    required this.collected,
    required this.total,
    this.collectedThisYear = 0,
  });

  /// Species on the local list that are on the life list.
  final int collected;

  /// Species on the local list that are on the year list.
  final int collectedThisYear;

  /// Species on the local list.
  final int total;

  int collectedIn(CollectionScope scope) => switch (scope) {
    CollectionScope.all => collected,
    CollectionScope.thisYear => collectedThisYear,
  };

  double fractionIn(CollectionScope scope) =>
      total == 0 ? 0 : collectedIn(scope) / total;

  double get fraction => fractionIn(CollectionScope.all);
}

/// Progress against the local list, not against everything the model knows.
///
/// 37 of 128 is a number a child can act on. 37 of 9,789 is not. With the
/// open species gone from the album, this line is the one place in it that
/// says how many are still to find — the species themselves are in Explore.
final collectionProgressProvider = FutureProvider<CollectionProgress>((
  ref,
) async {
  final local = await ref.watch(collectionLocalSpeciesProvider.future);
  final collected = await ref.watch(collectedSpeciesProvider.future);
  final thisYear = await ref.watch(collectedThisYearProvider.future);

  return CollectionProgress(
    collected: local.keys.where(collected.containsKey).length,
    collectedThisYear: local.keys.where(thisYear.containsKey).length,
    total: local.length,
  );
});

/// The child's own history with one species (`SAM-06`).
///
/// A family rather than one big map: a species page asks about exactly one
/// bird, and loading everyone's history to answer that would grow with the
/// collection for no reason.
final speciesPersonalStatsProvider =
    FutureProvider.family<SpeciesPersonalStats, String>((
      ref,
      scientificName,
    ) async {
      return ref
          .watch(collectionRepositoryProvider)
          .personalStatsFor(scientificName);
    });
