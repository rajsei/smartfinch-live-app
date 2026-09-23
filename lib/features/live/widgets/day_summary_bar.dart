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
// It names the **effect** first. "No stars" is something an eight-year-old can
// act on; "species filter disabled" is not.
//
// ### ...and then the cause
//
// The first version stopped at the effect, and a field report showed where
// that ends: a session that scored almost nothing, a bar that said nothing,
// and an adult who could not find out why. So under the effect the bar now
// names each reason that applies - in plain words, one line each - and offers
// a way straight to the setting responsible, which the settings screen then
// highlights. The reasons come from `scoringBlockersProvider`, the same list
// the settings screen reads, so the two cannot disagree.
//
// "No location" is one of them. It is not a pause in the engine's sense, but a
// session without a position earns nothing, and it used to do so in silence.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_blockers.dart';
import '../../scoring/scoring_providers.dart';
import '../../settings/settings_screen.dart';

/// Top-of-screen day total for live mode (LIVE-08, LIVE-18).
class DaySummaryBar extends ConsumerWidget {
  const DaySummaryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockers = ref.watch(scoringBlockersProvider);
    final summary = ref.watch(liveScoreBoardProvider).state.summary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child:
          blockers.isEmpty
              ? _Total(summary: summary)
              : ScoringPausedNotice(blockers: blockers),
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
  const ScoringPausedNotice({
    super.key,
    this.compact = false,
    this.blockers = const [],
  });

  /// Drops the explanatory lines, for places with no room for them.
  final bool compact;

  /// Why there are no stars, one line each. Empty means "paused, reason not
  /// given" - the compact form on the home screen.
  final List<ScoringBlocker> blockers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // "Test mode" describes a pause an adult switched on. A missing location
    // is not that, and calling it test mode would send the adult looking for a
    // switch that is not there.
    final onlyLocation =
        blockers.isNotEmpty &&
        blockers.every((b) => b == ScoringBlocker.noLocation);

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
                    onlyLocation
                        ? l10n.liveNoLocationTitle
                        : l10n.liveTestModeTitle,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 2),
                    // Full colour, not the muted grey of the line after
                    // them: these are the part an adult came to read. Not
                    // bold, so the headline above stays the headline.
                    for (final blocker in blockers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          blockerReason(l10n, blocker),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    Text(
                      l10n.liveTestModeRecordingsKept,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (blockers.isNotEmpty)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed:
                              () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  // Straight to the page the fix is on, and
                                  // on it to the switch, highlighted.
                                  builder:
                                      (_) => SettingsScreen(
                                        view:
                                            blockers.any(
                                                  (b) => b.isAdvancedSetting,
                                                )
                                                ? SettingsView.advanced
                                                : SettingsView.plain,
                                        revealBlocker: true,
                                      ),
                                ),
                              ),
                          child: Text(l10n.liveBlockerOpenSettings),
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
