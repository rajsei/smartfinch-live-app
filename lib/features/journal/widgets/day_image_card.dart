// =============================================================================
// DayImageCard — the one thing that leaves the phone (LOG-11)
// =============================================================================
//
// "Show grandma your bird day." This is the app's **only** sharing path, which
// makes what the card leaves out as much a requirement as what it shows.
//
// ### What is deliberately not on it
//
//   **The place names** (`LOG-13`, `KID-07`). They are free text a child
//   typed, and free text is the one thing that must never reach another
//   person's screen. "Oma" is for the child's own memory of the day.
//
//   **Any location at all** (`NFA-07`, `NFA-08`). Not the grid cell, not a
//   map, not a region name. The app coarsens coordinates to 0.1° before it
//   even stores them, and none of that survives into a picture that gets
//   forwarded through three chat apps.
//
//   **The audio.** `SET-12` keeps recordings on the device. A shared clip is a
//   recording of a real place at a real time, which is exactly the thing this
//   app promised not to hand out.
//
// So: the date, the stars, the species, and how many of them were new. That is
// a bird day, and it is nobody's address.
//
// ### Why it is a widget rather than a canvas
//
// It is rendered to PNG through a `RepaintBoundary`, so the card a child sees
// in the preview *is* the file that gets shared — same widget, same theme, one
// code path. A hand-painted canvas would be a second implementation of the
// same layout, and the two would drift.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../../shared/providers/settings_providers.dart';
import '../../explore/explore_providers.dart';
import '../journal_models.dart';

/// The shareable picture of one day (`LOG-11`).
///
/// Sized in logical pixels rather than to its parent, so the PNG comes out the
/// same on every phone: a card that fitted the screen would be a different
/// picture on a tablet.
class DayImageCard extends ConsumerWidget {
  const DayImageCard({super.key, required this.detail});

  final JournalDayDetail detail;

  /// Logical width of the rendered card. At the capture's pixel ratio of 3
  /// this is a 1080-pixel-wide image, which is what chat apps want.
  static const double width = 360;

  /// How many species are named before the card says "and 4 more".
  static const int namedSpecies = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final taxonomy = ref.watch(taxonomyServiceProvider).value;
    final locale = ref.watch(effectiveSpeciesLocaleProvider);

    final names = [
      for (final species in detail.scored)
        taxonomy?.lookup(species.scientificName)?.commonNameForLocale(locale) ??
            species.scientificName,
    ];
    final newCount = detail.scored.where((s) => s.isNew).length;

    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.yMMMMEEEEd(
                  Localizations.localeOf(context).toString(),
                ).format(detail.day.date),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('⭐', style: theme.textTheme.headlineMedium),
                  const SizedBox(width: 8),
                  Text(
                    '${detail.day.stars}',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.journalDaySpecies(detail.day.speciesCount),
                style: theme.textTheme.titleMedium,
              ),
              if (newCount > 0) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.journalBucketNewSpecies(newCount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (names.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final name in names.take(namedSpecies))
                      _SpeciesChip(name: name),
                    if (names.length > namedSpecies)
                      _SpeciesChip(
                        name: l10n.journalDayImageMore(
                          names.length - namedSpecies,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // The only branding, and the only thing on the card that is not
              // about this particular day.
              Text(
                l10n.appTitle,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeciesChip extends StatelessWidget {
  const _SpeciesChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
