// =============================================================================
// SeasonHintBanner — the PKT-17 sentence, wherever a species appears
// =============================================================================
//
// One widget for two places, so the app cannot say two different things about
// the same bird on the same day: the live detection card, where it explains a
// number that just moved, and the species detail, where it explains the
// 48-week curve (`SAM-15`) sitting next to it.
//
// It reads as information rather than as a warning. Being early is not a
// problem — it is the most interesting thing that can happen on a walk in
// March.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../explore/explore_providers.dart';
import '../../inference/geo_model.dart';
import '../season_hint.dart';

/// "🌱 Early! The blackcap is normally only here from April." (`PKT-17`)
///
/// Renders nothing when the species is in season, has no curve yet, or is here
/// all year — which is most species most of the time, and is the point: a hint
/// that appears constantly is not a hint.
class SeasonHintBanner extends ConsumerWidget {
  const SeasonHintBanner({
    super.key,
    required this.scientificName,
    required this.commonName,
    this.compact = false,
  });

  final String scientificName;

  /// The name the sentence uses — the child's language, not Latin.
  final String commonName;

  /// Drops the padding and the background, for use inside a detection card.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final species = ref.watch(exploreSpeciesProvider).value;
    if (species == null) return const SizedBox.shrink();

    final match = species.where((s) => s.scientificName == scientificName);
    final scores = match.isEmpty ? null : match.first.weeklyScores;
    if (scores == null) return const SizedBox.shrink();

    final hint = seasonHintFor(
      weeklyScores: scores,
      currentWeek: GeoModel.dateTimeToWeek(DateTime.now()),
    );
    if (hint == null) return const SizedBox.shrink();

    return SeasonHintText(hint: hint, commonName: commonName, compact: compact);
  }
}

/// The rendered sentence, separated from the lookup so it can be tested with a
/// hint rather than with a loaded geo model.
class SeasonHintText extends StatelessWidget {
  const SeasonHintText({
    super.key,
    required this.hint,
    required this.commonName,
    this.compact = false,
  });

  final SeasonHint hint;
  final String commonName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final month = DateFormat.MMMM(
      Localizations.localeOf(context).toString(),
    ).format(DateTime(2026, hint.relevantMonth));

    final (emoji, text) = switch (hint.phase) {
      SeasonPhase.early => ('🌱', l10n.seasonHintEarly(commonName, month)),
      SeasonPhase.late => ('🍂', l10n.seasonHintLate(commonName, month)),
    };

    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: theme.textTheme.bodyMedium),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: (compact
                    ? theme.textTheme.bodySmall
                    : theme.textTheme.bodyMedium)
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );

    if (compact) return line;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Neutral: being early is not a problem, it is the most interesting
        // thing that can happen on a walk in March.
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: line,
    );
  }
}
