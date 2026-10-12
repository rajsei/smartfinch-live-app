// =============================================================================
// CollectionScreen — the album (SAM-02, SAM-03, SAM-04, SAM-05, SAM-17)
// =============================================================================
//
// A grid of every species the child has found, each with its photo.
//
// **Only what was found** (decided 2026-10-12). The species still to find are
// not in the album at all — no placeholders, no silhouettes (`SAM-04b` is
// struck). They are in Explore, which lists everything that occurs here and
// ticks what is already collected; the progress line above the grid is the
// one place in the album that says how many are still out there.
//
// **Every card answers "what is this worth to me?"** and says *where* and
// *when* it is worth that (`SAM-03`). "Here, this week: 200 ⭐" is the honest
// label — the value moves with the season and with the place, and a child who
// is told that in advance reads the movement as the game rather than as a bug.
// A species found in May that is not here in December stays in the album and
// says so, rather than disappearing from it.
//
// **All animal groups** are collectable and filterable (`SAM-17`). A frog or a
// field cricket in the album is a strong draw for this age group, and the
// non-bird groups call in the summer months when bird activity drops.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../shared/widgets/content_width_constraint.dart';
import '../explore/widgets/species_info_overlay.dart';
import 'collection_providers.dart';

/// Taxon groups the album can be narrowed to (`SAM-17`).
///
/// An empty selection means "all", which is the default: the album shows
/// everything the child has found, and the filter is for a child who wants to
/// look at just the frogs.
enum CollectionGroup {
  aves,
  mammalia,
  amphibia,
  insecta;

  /// Matches the `taxon_group` column in the bundled taxonomy CSV.
  String get csvValue => switch (this) {
    CollectionGroup.aves => 'Aves',
    CollectionGroup.mammalia => 'Mammalia',
    CollectionGroup.amphibia => 'Amphibia',
    CollectionGroup.insecta => 'Insecta',
  };

  String label(AppLocalizations l10n) => switch (this) {
    CollectionGroup.aves => l10n.exploreFilterBirds,
    CollectionGroup.mammalia => l10n.exploreFilterMammals,
    CollectionGroup.amphibia => l10n.exploreFilterAmphibians,
    CollectionGroup.insecta => l10n.exploreFilterInsects,
  };
}

/// What the child has found.
class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  final Set<CollectionGroup> _groups = {};
  CollectionScope _scope = CollectionScope.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(collectionEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.collectionTitle)),
      body: ContentWidthConstraint(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(child: Text(l10n.collectionUnavailable)),
          data: (all) {
            final inScope = [
              for (final entry in all)
                if (entry.isIn(_scope)) entry,
            ]..sort((a, b) => b.dateIn(_scope).compareTo(a.dateIn(_scope)));
            final visible = [
              for (final entry in inScope)
                if (_groups.isEmpty ||
                    _groups.any((g) => g.csvValue == entry.taxonGroup))
                  entry,
            ];

            return Column(
              children: [
                CollectionProgressBar(scope: _scope),
                _ScopeSelector(
                  scope: _scope,
                  onChanged: (scope) => setState(() => _scope = scope),
                ),
                _GroupFilters(
                  groups: _groups,
                  onToggle:
                      (group) => setState(() {
                        _groups.contains(group)
                            ? _groups.remove(group)
                            : _groups.add(group);
                      }),
                ),
                Expanded(
                  child:
                      visible.isEmpty
                          ? _EmptyCollection(
                            scope: _scope,
                            filteredOut: inScope.isNotEmpty,
                          )
                          : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 170,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 0.78,
                                ),
                            itemCount: visible.length,
                            itemBuilder:
                                (context, index) =>
                                    CollectionCard(entry: visible[index]),
                          ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// "37 of 128 species in your region" (`SAM-05`), or the year's count.
///
/// Hidden when there is no local list to count against — without a location
/// "0 of 0" would say nothing true.
class CollectionProgressBar extends ConsumerWidget {
  const CollectionProgressBar({super.key, this.scope = CollectionScope.all});

  final CollectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final progress = ref.watch(collectionProgressProvider).value;
    if (progress == null || progress.total == 0) return const SizedBox.shrink();

    final found = progress.collectedIn(scope);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // A different sentence in the year view, because the number means
            // something different: this year, not ever.
            scope == CollectionScope.thisYear
                ? l10n.collectionProgressThisYear(found, progress.total)
                : l10n.collectionProgress(found, progress.total),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fractionIn(scope),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// All · This year (`SAM-16`, 3.4).
///
/// A segmented control rather than two chips: they are two collections, not
/// two independent filters, and only one can be shown at a time.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({required this.scope, required this.onChanged});

  final CollectionScope scope;
  final void Function(CollectionScope scope) onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<CollectionScope>(
          segments: [
            ButtonSegment(
              value: CollectionScope.all,
              label: Text(l10n.collectionScopeAll),
            ),
            ButtonSegment(
              value: CollectionScope.thisYear,
              label: Text(l10n.collectionScopeThisYear),
            ),
          ],
          selected: {scope},
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

class _GroupFilters extends StatelessWidget {
  const _GroupFilters({required this.groups, required this.onToggle});

  final Set<CollectionGroup> groups;
  final void Function(CollectionGroup group) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final group in CollectionGroup.values) ...[
            FilterChip(
              label: Text(group.label(l10n)),
              selected: groups.contains(group),
              onSelected: (_) => onToggle(group),
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

/// One species the child has found: its photo, its name, its worth here now.
class CollectionCard extends ConsumerWidget {
  const CollectionCard({super.key, required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final stars = entry.stars;

    return Semantics(
      button: true,
      label:
          stars != null
              ? l10n.collectionCardCollectedA11y(entry.commonName, stars)
              : l10n.collectionCardNotHereA11y(entry.commonName),
      excludeSemantics: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap:
              () => SpeciesInfoOverlay.show(
                context,
                ref,
                scientificName: entry.scientificName,
                commonName: entry.commonName,
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CardImage(entry: entry)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.commonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // "Here, this week: 200 ⭐" — both halves of that label are
                    // load-bearing (SAM-03). A species with no level here this
                    // week is worth nothing here now (D20), and says so in the
                    // same place instead of showing a 0.
                    Text(
                      stars != null
                          ? l10n.collectionWorthHereThisWeek(stars)
                          : l10n.collectionNotHereThisWeek,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            stars != null
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = Container(color: theme.colorScheme.surfaceContainerHighest);

    final path = entry.imagePath;
    if (path == null) return empty;

    return Image.asset(
      path,
      fit: BoxFit.cover,
      // A missing bundle must not look like a crash. Without the species
      // bundle built, every card falls back to this quietly.
      errorBuilder: (context, _, _) => empty,
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.scope, required this.filteredOut});

  /// Which collection is empty.
  final CollectionScope scope;

  /// Whether there is something in [scope] that the group filter hides.
  final bool filteredOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // "You have nothing yet", "nothing yet this year" and "nothing from this
    // group yet" are three different facts. Telling a child the first when the
    // third is true is discouraging for no reason — and telling them the first
    // in January, when the life list is full, would be plainly wrong.
    final (title, subtitle) = switch ((scope, filteredOut)) {
      (_, true) => (l10n.collectionNoMatches, null),
      (CollectionScope.all, false) => (
        l10n.collectionEmptyTitle,
        l10n.collectionEmptySubtitle,
      ),
      (CollectionScope.thisYear, false) => (
        l10n.collectionEmptyThisYearTitle,
        l10n.collectionEmptyThisYearSubtitle,
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              AppIcons.searchRounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
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
