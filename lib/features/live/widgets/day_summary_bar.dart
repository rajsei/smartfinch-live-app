// =============================================================================
// DaySummaryBar — the running day total, or why there isn't one
// =============================================================================
//
// One bar with two states, because they are the same question answered two
// ways: *what has today been worth?*
//
//   **Scoring** — "Today: ⭐ 850 · 9 species" (LIVE-08).
//   **Paused**  — "Test mode — no stars, nothing collected" (LIVE-18).
//
// The paused state replaces the total rather than sitting beside it. A number
// next to a notice saying the number does not count is exactly the ambiguity
// the requirement exists to remove.
//
// ### Why it does not look like a warning
//
// No red, no exclamation mark, no icon that means *something is wrong* —
// principle 1 says there is never a punishment, and a child who finds this bar
// after an adult changed a setting has done nothing. It reads as information:
// a neutral surface, the same weight as the total it replaces.
//
// It also names the **effect**, not the cause. "No stars" is something an
// eight-year-old can act on; "species filter disabled" is not.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_providers.dart';

/// Top-of-screen day total for live mode (LIVE-08, LIVE-18).
class DaySummaryBar extends ConsumerWidget {
  const DaySummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoring = ref.watch(liveScoringConditionsProvider).isScoring;
    final summary = ref.watch(liveScoreBoardProvider).state.summary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: scoring ? _Total(summary: summary) : const ScoringPausedNotice(),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.summary});

  final DaySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      liveRegion: true,
      label: l10n.liveDayTotalA11y(summary.stars, summary.speciesCount),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(
              l10n.liveDayTotalLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Text('⭐', style: theme.textTheme.titleMedium),
            const SizedBox(width: 4),
            // The number a child watches. Given its own weight, because
            // watching it climb is the point of the whole screen.
            Text(
              '${summary.stars}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const Spacer(),
            Text(
              l10n.liveDaySpeciesCount(summary.speciesCount),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The permanent, unalarming notice that nothing is being collected (LIVE-18).
///
/// Public because the home screen's star header carries the identical notice —
/// two places, one wording, so it cannot be missed and cannot disagree.
class ScoringPausedNotice extends StatelessWidget {
  const ScoringPausedNotice({super.key, this.compact = false});

  /// Drops the two explanatory lines, for places with no room for them.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // Deliberately the neutral container, not errorContainer.
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              AppIcons.infoOutline,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.liveTestModeTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.liveTestModeHowToFix,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      l10n.liveTestModeRecordingsKept,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
