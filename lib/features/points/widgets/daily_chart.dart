// =============================================================================
// DailyStarsChart — thirty days, including the empty ones (STAT-02)
// =============================================================================
//
// The whole requirement is one sentence: *days without activity are shown as
// an empty column, not omitted — otherwise the curve lies.*
//
// It lies in a specific and flattering way. Omit the gaps and five scattered
// days across a month draw the same shape as five days in a row, so the chart
// tells every child they are consistent. Keeping the gaps is what makes a
// streak visible as a streak, and it is why `AUS-07` can then insist that a
// broken one is never commented on: the chart already says it, quietly, and
// once is enough.
//
// Hand-drawn rather than a charting package. Thirty bars is a `Row` of
// `Container`s; a dependency for that would cost more than it saves.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../points_models.dart';

/// Daily stars over the chart window (`STAT-02`).
class DailyStarsChart extends StatelessWidget {
  const DailyStarsChart({
    super.key,
    required this.days,
    required this.peak,
    this.height = 120,
  });

  /// Oldest first, one entry per day — **including the empty ones**.
  final List<DayStars> days;

  /// The highest daily total in the window, for scaling.
  final int peak;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (days.isEmpty) return const SizedBox.shrink();

    return Semantics(
      label: l10n.pointsChartA11y(days.length, peak),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final day in days)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: _Bar(day: day, peak: peak, maxHeight: height),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(context, days.first.date),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                l10n.journalToday,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(BuildContext context, DateTime date) =>
      DateFormat.Md(Localizations.localeOf(context).toString()).format(date);
}

class _Bar extends StatelessWidget {
  const _Bar({required this.day, required this.peak, required this.maxHeight});

  final DayStars day;
  final int peak;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An empty day keeps a visible sliver rather than vanishing to nothing:
    // the column has to be *there* to be read as a gap, and a bar of zero
    // height is indistinguishable from no bar at all.
    final fraction = peak == 0 ? 0.0 : day.stars / peak;
    final barHeight =
        day.isEmpty ? 2.0 : (fraction * maxHeight).clamp(3.0, maxHeight);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color:
              day.isEmpty
                  ? theme.colorScheme.outlineVariant
                  : theme.colorScheme.primary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );
  }
}
