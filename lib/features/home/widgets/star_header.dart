// =============================================================================
// StarHeader — three numbers at the top of the home screen
// =============================================================================
//
// HOME-01 and HOME-02. Three numbers rather than one, because each answers a
// different question and a child asks all three:
//
//   **Total** — what I have built. Large, the pride value.
//   **Last 30 days** — whether I am still building it. Small beside it.
//   **Today** — the only one I can still change before bedtime. The number
//   that gets a child outside, so it gets its own line.
//
// While scoring is paused the numbers are replaced by the same notice live
// mode shows (LIVE-18) — same wording, two places, so it cannot be missed and
// the two cannot disagree.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../live/widgets/day_summary_bar.dart';
import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_providers.dart';

/// The star header (HOME-01, HOME-02, LIVE-18).
class StarHeader extends ConsumerWidget {
  const StarHeader({super.key, this.compact = false, this.flat = false});

  /// Tightens the spacing for the landscape layout.
  final bool compact;

  /// Drops the container: on the two-tone home screen these numbers already
  /// sit on a block of `primaryContainer`, and a second one inside it would
  /// be a card on a card in the same colour.
  final bool flat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoring = ref.watch(liveScoringConditionsProvider).isScoring;
    if (!scoring) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: ScoringPausedNotice(compact: true),
      );
    }

    // A first launch, or a database that has not opened yet, shows zeroes
    // rather than a spinner: a child arriving at an empty home screen should
    // see "0" and understand it, not watch a loading indicator.
    final totals = ref.watch(starTotalsProvider).value ?? const StarTotals();
    return _Totals(totals: totals, compact: compact, flat: flat);
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.totals,
    required this.compact,
    this.flat = false,
  });

  final StarTotals totals;
  final bool compact;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      label: l10n.homeStarHeaderA11y(
        totals.total,
        totals.last30Days,
        totals.today,
      ),
      excludeSemantics: true,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: flat ? 0 : 16),
        padding: EdgeInsets.symmetric(
          horizontal: flat ? 4 : 16,
          vertical: compact ? 10 : 14,
        ),
        decoration:
            flat
                ? null
                : BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('⭐', style: theme.textTheme.headlineSmall),
                const SizedBox(width: 8),
                Text(
                  '${totals.total}',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                // Small beside the total: the 30-day figure is context for
                // the big number, not a competitor to it.
                Expanded(
                  child: Text(
                    l10n.homeStarsLast30Days(totals.last30Days),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 2 : 6),
            Text(
              totals.todaySpecies > 0
                  ? l10n.homeStarsTodayWithSpecies(
                    totals.today,
                    totals.todaySpecies,
                  )
                  : l10n.homeStarsToday(totals.today),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
