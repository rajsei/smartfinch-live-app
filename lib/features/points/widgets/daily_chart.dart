// =============================================================================
// DailyStarsChart — the window, including the empty days (STAT-02/03/04)
// =============================================================================
//
// The core requirement is one sentence: *days without activity are shown as an
// empty column, not omitted — otherwise the curve lies.*
//
// It lies in a specific and flattering way. Omit the gaps and five scattered
// days across a month draw the same shape as five days in a row, so the chart
// tells every child they are consistent. Keeping the gaps is what makes a
// streak visible as a streak, and it is why `AUS-07` can then insist that a
// broken one is never commented on: the chart already says it, quietly, and
// once is enough.
//
// ### Two things arrived on top of that
//
// `STAT-04` gives the chart three windows, and `STAT-03` makes a bar a way in:
// tapping one opens that day in the journal. Both are here rather than in the
// screen, because the bar knows which day it is and the screen would have to
// be told twice.
//
// The empty columns are the reason a tap needs a rule of its own. A gap has no
// journal entry behind it, so its column carries no day key and does not
// react — see `ChartColumn.dayKey`. A child aiming at a gap gets nothing,
// which is better than getting a blank screen.
//
// Hand-drawn rather than a charting package. Fifty-two bars is a `Row` of
// `Container`s; a dependency for that would cost more than it saves.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../journal/journal_day_screen.dart';
import '../chart_range.dart';
import '../points_models.dart';

/// Daily stars over the chart window (`STAT-02`, `STAT-03`, `STAT-04`).
class DailyStarsChart extends StatelessWidget {
  const DailyStarsChart({
    super.key,
    required this.days,
    required this.peak,
    this.range = ChartRange.month,
    this.height = 120,
  });

  /// Oldest first, one entry per day — **including the empty ones**.
  final List<DayStars> days;

  /// The highest daily total in the window, for scaling.
  final int peak;

  /// Which window this is, which decides whether a bar is a day or a week.
  final ChartRange range;

  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (days.isEmpty) return const SizedBox.shrink();

    final columns = columnsFor(days, range);
    // Re-derived rather than taken from the overview's per-day peak: a weekly
    // column is the sum of seven days, so scaling a year by the best *day*
    // would send most of its bars off the top of the chart.
    final ceiling = columns.fold<int>(
      0,
      (best, column) => column.stars > best ? column.stars : best,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Labelled but not `excludeSemantics`: each bar is now a button of its
        // own (`STAT-03`), and excluding them would trade a way into the day
        // for a sentence describing it.
        Semantics(
          label: l10n.pointsChartA11y(days.length, peak),
          child: SizedBox(
            height: height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final column in columns)
                  Expanded(
                    child: Padding(
                      // The gap closes as the bars get thinner: across a year
                      // a pixel each side is a third of the bar.
                      padding: EdgeInsets.symmetric(
                        horizontal: columns.length > 40 ? 0.5 : 1,
                      ),
                      child: _Bar(
                        column: column,
                        peak: ceiling,
                        maxHeight: height,
                      ),
                    ),
                  ),
              ],
            ),
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
    );
  }

  String _shortDate(BuildContext context, DateTime date) =>
      DateFormat.Md(Localizations.localeOf(context).toString()).format(date);
}

/// Seven days · thirty · a year (`STAT-04`).
class ChartRangeSelector extends StatelessWidget {
  const ChartRangeSelector({
    super.key,
    required this.range,
    required this.onChanged,
  });

  final ChartRange range;
  final ValueChanged<ChartRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ChartRange>(
        segments: [
          ButtonSegment(
            value: ChartRange.week,
            label: Text(l10n.chartRangeWeek),
          ),
          ButtonSegment(
            value: ChartRange.month,
            label: Text(l10n.chartRangeMonth),
          ),
          ButtonSegment(
            value: ChartRange.year,
            label: Text(l10n.chartRangeYear),
          ),
        ],
        selected: {range},
        onSelectionChanged: (selected) => onChanged(selected.first),
        // No tick in front of the selected label: it costs the width of a word
        // in every language and the filled segment already says which one it
        // is.
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.column,
    required this.peak,
    required this.maxHeight,
  });

  final ChartColumn column;
  final int peak;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // An empty day keeps a visible sliver rather than vanishing to nothing:
    // the column has to be *there* to be read as a gap, and a bar of zero
    // height is indistinguishable from no bar at all.
    final fraction = peak == 0 ? 0.0 : column.stars / peak;
    final barHeight =
        column.isEmpty ? 2.0 : (fraction * maxHeight).clamp(3.0, maxHeight);

    final bar = Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        height: barHeight,
        decoration: BoxDecoration(
          color:
              column.isEmpty
                  ? theme.colorScheme.outlineVariant
                  : theme.colorScheme.primary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      ),
    );

    final dayKey = column.dayKey;
    if (dayKey == null) return bar;

    final date = DateFormat.yMMMd(
      Localizations.localeOf(context).toString(),
    ).format(column.date);

    return Semantics(
      button: true,
      label: l10n.pointsChartBarA11y(date, column.stars),
      excludeSemantics: true,
      child: GestureDetector(
        // Opaque across the whole column rather than the drawn bar: two pixels
        // of sliver is not a tap target, and the empty height above a short
        // bar belongs to the same day as the bar does.
        behavior: HitTestBehavior.opaque,
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JournalDayScreen(dayKey: dayKey),
              ),
            ),
        child: bar,
      ),
    );
  }
}
