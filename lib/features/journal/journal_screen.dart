// =============================================================================
// JournalScreen — the day list (LOG-01, LOG-02)
// =============================================================================
//
// The core rebuild. The app stops being organised by *recording* and starts
// being organised by *day*: a child who listened for ten minutes before school
// and forty in the park has had one day, and the journal should say so.
//
// What a day card carries (`LOG-02`): the date, the day's stars, how many
// species scored, a preview of which ones, and — where the child wrote one —
// the name of the place (`LOG-13`).
//
// And, separately counted, whatever was heard outside scoring (`LOG-15`).
// "8 species · ⭐ 450" with "3 more outside scoring" underneath keeps the day
// total honest without hiding the recordings. That second line is a **note,
// not a warning**: the child did nothing wrong.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../shared/widgets/content_width_constraint.dart';
import '../../shared/providers/settings_providers.dart';
import '../explore/explore_providers.dart';
import 'journal_day_screen.dart';
import 'journal_models.dart';
import 'journal_providers.dart';

/// The child's own record of what they have heard, by day.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  /// Opens on days — the level a child recognises. `LOG-06` will eventually
  /// pick this from how much data there is.
  JournalPeriod _period = JournalPeriod.day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.journalTitle)),
      body: ContentWidthConstraint(
        child: Column(
          children: [
            JournalPeriodSelector(
              period: _period,
              onChanged: (period) => setState(() => _period = period),
            ),
            Expanded(
              child:
                  _period == JournalPeriod.day
                      ? const _DayList()
                      : _BucketList(period: _period),
            ),
          ],
        ),
      ),
    );
  }
}

/// Day · Week · Month · Year (`LOG-04`).
class JournalPeriodSelector extends StatelessWidget {
  const JournalPeriodSelector({
    super.key,
    required this.period,
    required this.onChanged,
  });

  final JournalPeriod period;
  final void Function(JournalPeriod period) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<JournalPeriod>(
          segments: [
            ButtonSegment(
              value: JournalPeriod.day,
              label: Text(l10n.journalPeriodDay),
            ),
            ButtonSegment(
              value: JournalPeriod.week,
              label: Text(l10n.journalPeriodWeek),
            ),
            ButtonSegment(
              value: JournalPeriod.month,
              label: Text(l10n.journalPeriodMonth),
            ),
            ButtonSegment(
              value: JournalPeriod.year,
              label: Text(l10n.journalPeriodYear),
            ),
          ],
          selected: {period},
          onSelectionChanged: (selected) => onChanged(selected.first),
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

/// The day list, grouped under sticky month headers (`LOG-02`, `LOG-05`).
class _DayList extends ConsumerWidget {
  const _DayList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ref
        .watch(journalDaysProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, _) => _JournalMessage(
                icon: AppIcons.errorOutline,
                title: l10n.journalUnavailable,
              ),
          data: (days) {
            if (days.isEmpty) {
              return _JournalMessage(
                icon: AppIcons.libraryMusic,
                title: l10n.journalEmptyTitle,
                subtitle: l10n.journalEmptySubtitle,
              );
            }

            // Grouped by month, in the order the days already come in.
            final months = <String, List<JournalDay>>{};
            for (final day in days) {
              (months[day.dayKey.substring(0, 7)] ??= []).add(day);
            }

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(journalDaysProvider),
              child: CustomScrollView(
                slivers: [
                  for (final entry in months.entries)
                    // `SliverMainAxisGroup` is what makes the header *sticky*
                    // rather than merely pinned: without it every month's
                    // header would stack at the top instead of the next one
                    // pushing the last away (LOG-05).
                    SliverMainAxisGroup(
                      slivers: [
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _MonthHeaderDelegate(
                            label: _monthLabel(context, entry.value.first.date),
                          ),
                        ),
                        SliverList.builder(
                          itemCount: entry.value.length,
                          itemBuilder:
                              (context, index) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: JournalDayCard(day: entry.value[index]),
                              ),
                        ),
                      ],
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            );
          },
        );
  }

  String _monthLabel(BuildContext context, DateTime date) => DateFormat.yMMMM(
    Localizations.localeOf(context).toString(),
  ).format(date);
}

/// The header that stays put while its month scrolls under it (`LOG-05`).
class _MonthHeaderDelegate extends SliverPersistentHeaderDelegate {
  _MonthHeaderDelegate({required this.label});

  final String label;

  static const double _height = 36;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final theme = Theme.of(context);

    return Container(
      height: _height,
      // Opaque: the cards scroll *under* this, and a translucent header would
      // show them through it.
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_MonthHeaderDelegate old) => old.label != label;
}

/// Weeks, months or years (`LOG-04`).
class _BucketList extends ConsumerWidget {
  const _BucketList({required this.period});

  final JournalPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ref
        .watch(journalBucketsProvider(period))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (error, _) => _JournalMessage(
                icon: AppIcons.errorOutline,
                title: l10n.journalUnavailable,
              ),
          data: (buckets) {
            if (buckets.isEmpty) {
              return _JournalMessage(
                icon: AppIcons.libraryMusic,
                title: l10n.journalEmptyTitle,
                subtitle: l10n.journalEmptySubtitle,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              itemCount: buckets.length,
              itemBuilder:
                  (context, index) => JournalBucketCard(bucket: buckets[index]),
            );
          },
        );
  }
}

/// One week, month or year (`LOG-04`).
class JournalBucketCard extends StatelessWidget {
  const JournalBucketCard({super.key, required this.bucket});

  final JournalBucket bucket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatBucketLabel(context, bucket),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (bucket.stars > 0)
                  Text(
                    '⭐ ${bucket.stars}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.journalDaySpecies(bucket.speciesCount),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 2),
            Text(
              l10n.journalBucketDaysOut(bucket.activeDays),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            // The number a child looks for when zoomed out: a month with four
            // first finds was a different month from one with none, however
            // similar the star totals.
            if (bucket.newSpeciesCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                l10n.journalBucketNewSpecies(bucket.newSpeciesCount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Week of 4 May", "May 2026", "2026".
String formatBucketLabel(BuildContext context, JournalBucket bucket) {
  final locale = Localizations.localeOf(context).toString();

  return switch (bucket.period) {
    JournalPeriod.week => AppLocalizations.of(
      context,
    )!.journalWeekOf(DateFormat.MMMMd(locale).format(bucket.start)),
    JournalPeriod.month => DateFormat.yMMMM(locale).format(bucket.start),
    JournalPeriod.year => '${bucket.start.year}',
    JournalPeriod.day => DateFormat.yMMMMd(locale).format(bucket.start),
  };
}

/// One day (`LOG-02`).
class JournalDayCard extends ConsumerWidget {
  const JournalDayCard({super.key, required this.day});

  final JournalDay day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap:
            () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => JournalDayScreen(dayKey: day.dayKey),
              ),
            ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatJournalDate(context, day.date),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (day.stars > 0)
                    Text(
                      '⭐ ${day.stars}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
              // The child's own word for the place, where they wrote one.
              // Their word, offline, and it goes nowhere (LOG-13, KID-07).
              if (day.placeNames.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      AppIcons.locationOn,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        day.placeNames.join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                l10n.journalDaySpecies(day.speciesCount),
                style: theme.textTheme.bodyMedium,
              ),
              if (day.speciesPreview.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _previewNames(ref, day.speciesPreview),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // A note, not a warning: the day total stays honest and the
              // recordings are still there to listen to (LOG-15).
              if (day.unscoredSpeciesCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.journalMoreOutsideScoring(day.unscoredSpeciesCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _previewNames(WidgetRef ref, List<String> scientificNames) {
    final taxonomy = ref.watch(taxonomyServiceProvider).value;
    final locale = ref.watch(effectiveSpeciesLocaleProvider);

    return [
      for (final name in scientificNames)
        taxonomy?.lookup(name)?.commonNameForLocale(locale) ?? name,
    ].join(' · ');
  }
}

/// Empty and error states, which look the same and say different things.
class _JournalMessage extends StatelessWidget {
  const _JournalMessage({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Today", "Yesterday", or a written date.
///
/// The two nearest days get a word rather than a number, because those are the
/// two a child is actually looking for.
String formatJournalDate(BuildContext context, DateTime date) {
  final l10n = AppLocalizations.of(context)!;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final difference = today.difference(
    DateTime(date.year, date.month, date.day),
  );

  if (difference.inDays == 0) return l10n.journalToday;
  if (difference.inDays == 1) return l10n.journalYesterday;

  return DateFormat.yMMMMEEEEd(
    Localizations.localeOf(context).toString(),
  ).format(date);
}
