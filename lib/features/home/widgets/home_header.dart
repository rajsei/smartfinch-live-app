// =============================================================================
// HomeHeader — the coloured block: bird, stars, level (HOME-01/02/07, STAT-07)
// =============================================================================
//
// The top half of the two-tone home screen, laid out to the agreed sketch:
//
//   • the bird on the left, with its level on a chip
//   • ⭐ the total, large, with its label to the right of it
//   • a rule, then the two smaller figures side by side: 30 days, and today
//   • the level line and its bar across the full width
//
// ### What is not here any more, and why
//
// **The logo and the app title.** They were the first thing on the old home
// screen, and on the two-tone one they cost the header a third of its height
// to tell a child the name of the app they just opened. The header's job is to
// say what *they* have; the app's own name is on the icon they tapped.
//
// ### The paused notice still wins
//
// `LIVE-18`: while scoring is off the numbers are replaced by the same notice
// live mode shows, in the same words. That has to survive any restyling of
// this block — a header that showed stale totals during a paused session would
// be the app quietly lying about a number a child is watching.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../avatar/avatar_name_sheet.dart';
import '../../avatar/level_ladder.dart';
import '../../avatar/widgets/avatar_card.dart';
import '../../avatar/avatar_providers.dart';
import '../../live/widgets/day_summary_bar.dart';
import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_providers.dart';

/// The coloured block at the top of the home screen.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, this.compact = false});

  /// Tightens the bird and the big number for the landscape column, which is
  /// narrower than the full width portrait gives them.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onPrimaryContainer;

    final scoring = ref.watch(liveScoringConditionsProvider).isScoring;
    // A first launch, or a database that has not opened yet, shows zeroes
    // rather than a spinner: a child arriving at an empty home screen should
    // see "0" and understand it, not watch a loading indicator.
    final totals = ref.watch(starTotalsProvider).value ?? const StarTotals();
    final progress = ref.watch(levelProgressProvider).value ?? _startOfLadder;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AvatarBadge(
                progress: progress,
                size: compact ? 52 : 64,
                onTap: () => showAvatarNameSheet(context),
              ),
              SizedBox(width: compact ? 12 : 16),
              Expanded(
                child:
                    scoring
                        ? _Figures(totals: totals, ink: ink, compact: compact)
                        : const ScoringPausedNotice(compact: true),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _LevelLine(progress: progress, ink: ink),
        ],
      ),
    );
  }

  /// What an unopened database means, rather than a spinner.
  static const LevelProgress _startOfLadder = LevelProgress(
    level: Level(number: 1, key: 'egg', fromStars: 0),
    stars: 0,
    next: Level(number: 2, key: 'chick', fromStars: 500),
  );
}

/// The bird in a circle, with its level on a chip (`AVA-01`, `HOME-07`).
class AvatarBadge extends StatelessWidget {
  const AvatarBadge({
    super.key,
    required this.progress,
    this.onTap,
    this.size = 64,
  });

  final LevelProgress progress;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: size,
        height: size,
        // The chip sits on the circle's edge, so it needs room to hang over.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surface,
              ),
              child: Center(
                child: AvatarFigure(stage: progress.stage, size: size * 0.7),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primaryContainer,
                    width: 2,
                  ),
                ),
                child: Text(
                  '${progress.level.number}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Total, last 30 days, today (`HOME-01`, `HOME-02`).
class _Figures extends StatelessWidget {
  const _Figures({
    required this.totals,
    required this.ink,
    this.compact = false,
  });

  final StarTotals totals;
  final Color ink;
  final bool compact;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: _Star(
                  value: totals.total,
                  ink: ink,
                  style: (compact
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.headlineMedium)
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              // The label to the right of the number rather than under it:
              // the number is what a child reads, the word is what tells them
              // which of the three it is.
              Text(
                l10n.homeFigureTotal,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ink.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          Divider(height: 16, color: ink.withValues(alpha: 0.25)),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _SmallFigure(
                    value: totals.last30Days,
                    label: l10n.homeFigureLast30Days,
                    ink: ink,
                  ),
                ),
                VerticalDivider(
                  width: 16,
                  thickness: 1,
                  color: ink.withValues(alpha: 0.25),
                ),
                Expanded(
                  child: _SmallFigure(
                    value: totals.today,
                    label: l10n.homeFigureToday,
                    ink: ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallFigure extends StatelessWidget {
  const _SmallFigure({
    required this.value,
    required this.label,
    required this.ink,
  });

  final int value;
  final String label;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Star(
          value: value,
          ink: ink,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: ink.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }
}

/// "★ 345.657", grouped the way the child's locale groups numbers.
class _Star extends StatelessWidget {
  const _Star({required this.value, required this.ink, this.style});

  final int value;
  final Color ink;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final grouped = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).format(value);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '★',
          style: style?.copyWith(
            color: ink,
            fontSize: 0.62 * (style?.fontSize ?? 20),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            grouped,
            style: style?.copyWith(color: ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// "Level 4" and the bar to the next one (`STAT-07`).
class _LevelLine extends StatelessWidget {
  const _LevelLine({required this.progress, required this.ink});

  final LevelProgress progress;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              l10n.levelShort(progress.level.number),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            const Spacer(),
            const SizedBox(width: 12),
            // Flexible, not a Spacer and a Text: at level 13 this line reads
            // "14,343 to level 14", and on a 360-pixel phone that is wider
            // than what is left. It gives way rather than overflowing.
            Flexible(
              child: Text(
                // At the top of the ladder there is nothing left to reach, and
                // "0 to level 16" would read as a bug rather than as having
                // finished it.
                progress.next == null
                    ? l10n.levelTopOfTheLadder
                    : l10n.levelToNextShort(
                      progress.starsToNext,
                      progress.next!.number,
                    ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ink.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 9,
            backgroundColor: ink.withValues(alpha: 0.22),
            valueColor: AlwaysStoppedAnimation<Color>(
              theme.colorScheme.surface,
            ),
          ),
        ),
      ],
    );
  }
}
