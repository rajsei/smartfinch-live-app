// =============================================================================
// HomeHeader — the coloured block: bird, stars, level (HOME-01/02/07, STAT-07)
// =============================================================================
//
// The top half of the two-tone home screen, laid out to the agreed sketch:
//
//   • the bird on the left, with its level on a chip
//   • ⭐ the total, large, with its label to the right of it
//   • a rule, then the two smaller figures side by side: 30 days, and today
//   • seven bars for the seven days behind them (`HOME-05`)
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
import '../../points/points_models.dart';
import '../../points/points_providers.dart';
import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_providers.dart';

/// The coloured block at the top of the home screen.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({
    super.key,
    this.compact = false,
    this.large = false,
    this.dense = false,
  });

  /// Tightens the bird and the big number for the landscape column, which is
  /// narrower than the full width portrait gives them.
  final bool compact;

  /// Opens them up for a tablet, which has height to spare and would
  /// otherwise show a phone-sized header floating in a band of colour.
  final bool large;

  /// A screen too short for everything. The sparkline is what goes: it is the
  /// only thing in this block that repeats a figure already shown beside it,
  /// and losing it costs less than a clipped level bar.
  final bool dense;

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
      padding:
          large
              ? const EdgeInsets.fromLTRB(32, 24, 32, 28)
              : const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AvatarBadge(
                progress: progress,
                size: compact ? 52 : (large ? 96 : 64),
                onTap: () => showAvatarNameSheet(context),
              ),
              SizedBox(width: compact ? 12 : (large ? 24 : 16)),
              Expanded(
                child:
                    scoring
                        ? _Figures(
                          totals: totals,
                          ink: ink,
                          compact: compact,
                          large: large,
                        )
                        : const ScoringPausedNotice(compact: true),
              ),
            ],
          ),
          // Hidden along with the figures while scoring is off (`LIVE-18`):
          // seven bars of stars is a point count like any other, and a header
          // that keeps drawing them under a "paused" notice is the app
          // contradicting itself.
          if (scoring && !dense) ...[
            SizedBox(height: large ? 22 : 14),
            _Sparkline(ink: ink, large: large),
          ],
          SizedBox(height: large ? 28 : 18),
          _LevelLine(progress: progress, ink: ink, large: large),
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
    this.large = false,
  });

  final StarTotals totals;
  final Color ink;
  final bool compact;
  final bool large;

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
                          : (large
                              ? theme.textTheme.displaySmall
                              : theme.textTheme.headlineMedium))
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

/// The last seven days, seven bars wide (`HOME-05`).
///
/// The same rule as the big chart (`STAT-02`): a day with nothing on it is an
/// empty column, never a day that was left out. Seven bars is too few to show
/// a trend and that is the point — it shows *yesterday and the day before*,
/// which is the span a child actually remembers.
///
/// Its own provider rather than the Points overview, so opening the home
/// screen does not derive every badge and achievement to draw seven bars.
class _Sparkline extends ConsumerWidget {
  const _Sparkline({required this.ink, this.large = false});

  final Color ink;
  final bool large;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Absent rather than empty while the database opens: the header would
    // otherwise jump by a bar's height a moment after it is drawn.
    final days = ref.watch(homeSparklineProvider).value ?? const <DayStars>[];
    if (days.isEmpty) return const SizedBox.shrink();

    final peak = days.fold<int>(
      0,
      (best, day) => day.stars > best ? day.stars : best,
    );
    final barHeight = large ? 40.0 : 28.0;

    return Semantics(
      label: l10n.homeSparklineA11y(days.length),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // The chart's own word for this window, not a second one: the home
          // screen and the Points screen should not call seven days two
          // different things.
          Text(
            l10n.chartRangeWeek,
            style: theme.textTheme.bodySmall?.copyWith(
              color: ink.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: barHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _SparkBar(
                          day: day,
                          peak: peak,
                          maxHeight: barHeight,
                          ink: ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkBar extends StatelessWidget {
  const _SparkBar({
    required this.day,
    required this.peak,
    required this.maxHeight,
    required this.ink,
  });

  final DayStars day;
  final int peak;
  final double maxHeight;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fraction = peak == 0 ? 0.0 : day.stars / peak;
    final height =
        day.isEmpty ? 3.0 : (fraction * maxHeight).clamp(4.0, maxHeight);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          // The same pairing as the level bar below it — the header's own
          // surface for what counts, a wash of the ink for what does not —
          // so the two read as one block rather than as two charts.
          color:
              day.isEmpty
                  ? ink.withValues(alpha: 0.22)
                  : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
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
  const _LevelLine({
    required this.progress,
    required this.ink,
    this.large = false,
  });

  final LevelProgress progress;
  final Color ink;
  final bool large;

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
            minHeight: large ? 14 : 9,
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
