// =============================================================================
// Clip retention — deciding which recordings go (SET-12)
// =============================================================================
//
// `LIVE-14` keeps a short audio snippet per detection. Left alone that grows
// without limit, which is what `NFA-05` forbids. `SET-12` is the rule that
// makes the two compatible instead of exempting one from the other.
//
// ### The order matters more than the thresholds
//
// **Most-recorded species first, and within a species the lowest confidence
// first.** So the hundredth mediocre blackbird goes before the only nuthatch.
// A plain oldest-first rule would delete exactly backwards: a child's earliest
// recordings are the ones they were most excited about.
//
// ### Two thresholds, both adjustable
//
//   * a clip is only ever a candidate once it is older than **30 days**;
//   * and only above **100 clips of that species**.
//
// Both are generous on purpose. Nobody has yet measured what a child actually
// accumulates in a month, so chapter 9 says to set them high and check against
// the field test rather than guess low and delete something that mattered.
//
// ### Favourites are never deleted
//
// The one promise the whole clean-up rests on. A child who marks a recording
// has been told it stays, and a job that removed it anyway would be the single
// worst thing this feature could do. Favourites are excluded before anything
// is ranked, and they still count towards the cap so the child can see how
// much of it they have used.
//
// ### Pure, then applied
//
// [ClipRetentionPolicy.selectForDeletion] is a pure function over rows. The
// job reads, asks it, deletes files, clears paths. Keeping the decision
// separate from the deletion is what makes "would this remove the only
// nuthatch?" a question a test can ask without a filesystem.
// =============================================================================

import 'package:meta/meta.dart';

/// One clip, as the policy sees it.
@immutable
class ClipCandidate {
  const ClipCandidate({
    required this.detectionId,
    required this.scientificName,
    required this.recordedAt,
    required this.confidence,
    required this.path,
    this.isFavourite = false,
  });

  final String detectionId;
  final String scientificName;
  final DateTime recordedAt;

  /// Peak confidence where one was written back (D15), else the first window's.
  final double confidence;

  final String path;

  /// Never deleted (`SET-12`).
  final bool isFavourite;
}

/// The two thresholds, as data so they can become settings.
@immutable
class ClipRetentionPolicy {
  const ClipRetentionPolicy({
    this.minimumAge = const Duration(days: 30),
    this.perSpeciesCap = 100,
  });

  /// Nothing younger than this is ever a candidate.
  ///
  /// A recording from this morning is the one a child is most likely to want
  /// to play back tonight, whatever the counts say.
  final Duration minimumAge;

  /// Clips of one species above which the oldest weak ones start to go.
  final int perSpeciesCap;

  /// Which clips to delete, worst first.
  ///
  /// Returns nothing when nothing qualifies — the common case, and the one the
  /// job runs into every day for months.
  List<ClipCandidate> selectForDeletion(
    List<ClipCandidate> clips, {
    required DateTime now,
  }) {
    final bySpecies = <String, List<ClipCandidate>>{};
    for (final clip in clips) {
      (bySpecies[clip.scientificName] ??= []).add(clip);
    }

    // Species with the most clips are trimmed first, so a single very common
    // bird cannot crowd out the rest of the collection.
    final species =
        bySpecies.keys.toList()..sort(
          (a, b) => bySpecies[b]!.length.compareTo(bySpecies[a]!.length),
        );

    final doomed = <ClipCandidate>[];

    for (final name in species) {
      final all = bySpecies[name]!;
      if (all.length <= perSpeciesCap) continue;

      // Favourites are removed from consideration but **not** from the count:
      // they occupy the cap, which is what lets the app tell a child how many
      // of their hundred they have used.
      final removable =
          all
              .where(
                (clip) =>
                    !clip.isFavourite &&
                    now.difference(clip.recordedAt) >= minimumAge,
              )
              .toList()
            // Lowest confidence first; oldest breaks a tie. The hundredth
            // mediocre blackbird goes before the only good one.
            ..sort((a, b) {
              final byConfidence = a.confidence.compareTo(b.confidence);
              if (byConfidence != 0) return byConfidence;
              return a.recordedAt.compareTo(b.recordedAt);
            });

      final over = all.length - perSpeciesCap;
      doomed.addAll(removable.take(over));
    }

    return doomed;
  }

  /// How many of the cap [scientificName] has used, favourites included.
  ///
  /// Shown to the child so the number stopping is explainable rather than
  /// mysterious — "12 of your 100".
  int usedOfCap(List<ClipCandidate> clips, String scientificName) {
    return clips.where((c) => c.scientificName == scientificName).length;
  }
}
