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
class JournalScreen extends ConsumerWidget {
  const JournalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final days = ref.watch(journalDaysProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.journalTitle)),
      body: ContentWidthConstraint(
        child: days.when(
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

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(journalDaysProvider),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: days.length,
                itemBuilder:
                    (context, index) => JournalDayCard(day: days[index]),
              ),
            );
          },
        ),
      ),
    );
  }
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
