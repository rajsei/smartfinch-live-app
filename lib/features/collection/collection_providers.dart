// =============================================================================
// The Collection — what the child has, and what is still open
// =============================================================================
//
// `SAM-02` splits this from Explore deliberately: two destinations answering
// two questions. **Explore** is the reference list — everything that occurs
// here, found or not. **The Collection** is the thing a child opens in the
// evening.
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

/// One cell in the album.
@immutable
class CollectionEntry {
  const CollectionEntry({
    required this.scientificName,
    required this.commonName,
    required this.tier,
    required this.stars,
    required this.taxonGroup,
    this.collectedAt,
    this.collectedThisYearAt,
    this.imagePath,
  });

  final String scientificName;
  final String commonName;

  /// Rarity here, this week (2.1). Both halves of that matter and both are in
  /// the label the card shows.
  final ExploreTier tier;

  /// What this species is worth **here, this week** (`SAM-03`).
  ///
  /// Answerable *before* the detection — "what is this bird worth to me?" is
  /// the question the album is opened with.
  final int stars;

  /// `Aves`, `Mammalia`, `Amphibia`, `Insecta` (`SAM-17`).
  final String taxonGroup;

  /// Null while the species is still open.
  final DateTime? collectedAt;

  /// When it was first heard **this calendar year** (`SAM-16`).
  ///
  /// Null for a species on the life list that has not been heard again since
  /// January — which is precisely the state the year list exists to make
  /// visible.
  final DateTime? collectedThisYearAt;

  /// The bundled photo, or null to fall back to the placeholder (`SAM-04`).
  final String? imagePath;

  bool get isCollected => collectedAt != null;

  bool get isCollectedThisYear => collectedThisYearAt != null;

  /// Whether this entry counts as found in [scope].
  bool isFoundIn(CollectionScope scope) => switch (scope) {
    CollectionScope.everything => isCollected,
    CollectionScope.mine => isCollected,
    CollectionScope.thisYear => isCollectedThisYear,
  };
}

/// Which of the three collections the album is showing (`SAM-16`, `SAM-02`).
enum CollectionScope {
  /// Everything that occurs here, found or not — the default, because the
  /// contrast between filled and empty cells is what `SAM-04` rests on.
  everything,

  /// Only what has ever been collected.
  mine,

  /// Only what has been collected **this year**. Empties on 1 January without
  /// the life list losing anything (3.4).
  thisYear,
}

/// The album: every species that occurs here, marked collected or open.
///
/// The grid deliberately contains **both**. `SAM-04` rests the whole Pokédex
/// effect on the contrast — "a grid where some cells carry a bird and others
/// visibly do not is already the thing that makes a child want to fill it" —
/// and a grid of only what you already have has nothing to fill.
final collectionEntriesProvider = FutureProvider<List<CollectionEntry>>((
  ref,
) async {
  final species = await ref.watch(exploreSpeciesProvider.future);
  final collected = await ref.watch(collectedSpeciesProvider.future);
  final thisYear = await ref.watch(collectedThisYearProvider.future);
  final rules = ScoringRules.current;

  final entries = [
    for (final s in species)
      CollectionEntry(
        scientificName: s.scientificName,
        commonName: s.commonName,
        tier: s.tier,
        stars: rules.starsFor(s.tier),
        taxonGroup: s.taxonomy?.taxonGroup ?? '',
        collectedAt: collected[s.scientificName],
        collectedThisYearAt: thisYear[s.scientificName],
        imagePath: s.taxonomy?.assetImagePath,
      ),
  ];

  // Collected first, then the open ones by what they are worth. A child
  // scrolling their album sees what they have, then what is worth going out
  // for — which is the order the screen is opened in.
  entries.sort((a, b) {
    if (a.isCollected != b.isCollected) return a.isCollected ? -1 : 1;
    if (a.isCollected) return b.collectedAt!.compareTo(a.collectedAt!);
    return b.stars.compareTo(a.stars);
  });

  return entries;
});

/// "37 of 128 species in your region" (`SAM-05`).
@immutable
class CollectionProgress {
  const CollectionProgress({required this.collected, required this.total});

  final int collected;
  final int total;

  double get fraction => total == 0 ? 0 : collected / total;
}

/// Progress against the local list, not against everything the model knows.
///
/// 37 of 128 is a number a child can act on. 37 of 9,789 is not.
final collectionProgressProvider = FutureProvider<CollectionProgress>((
  ref,
) async {
  final entries = await ref.watch(collectionEntriesProvider.future);

  return CollectionProgress(
    collected: entries.where((e) => e.isCollected).length,
    total: entries.length,
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
