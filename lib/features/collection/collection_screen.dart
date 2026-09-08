// =============================================================================
// CollectionScreen — the album (SAM-02, SAM-03, SAM-04, SAM-05, SAM-17)
// =============================================================================
//
// A grid of every species that occurs here, with the ones the child has found
// showing a photo and the rest a placeholder.
//
// **The contrast is the feature.** `SAM-04` is explicit that the Pokédex
// effect rests on it rather than on the artwork: a grid where some cells carry
// a bird and others visibly do not is already the thing that makes a child
// want to fill it. So the default view contains both, and "only mine" is a
// filter rather than the starting state.
//
// **Every cell answers "what is this worth to me?"** before the detection, and
// says *where* and *when* it is worth that (`SAM-03`). "Here, this week: 200 ⭐"
// is the honest label — the value moves with the season and with the place,
// and a child who is told that in advance reads the movement as the game
// rather than as a bug.
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
/// everything the model can hear here, and the filter is for a child who wants
/// to look at just the frogs.
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
  CollectionScope _scope = CollectionScope.everything;

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
            final visible = [
              for (final entry in all)
                if ((_groups.isEmpty ||
                        _groups.any((g) => g.csvValue == entry.taxonGroup)) &&
                    (_scope == CollectionScope.everything ||
                        entry.isFoundIn(_scope)))
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
                          ? _EmptyCollection(scope: _scope)
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
                                (context, index) => CollectionCard(
                                  entry: visible[index],
                                  scope: _scope,
                                ),
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
class CollectionProgressBar extends ConsumerWidget {
  const CollectionProgressBar({
    super.key,
    this.scope = CollectionScope.everything,
  });

  final CollectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(collectionEntriesProvider).value;
    if (entries == null) return const SizedBox.shrink();

    final total = entries.length;
    final found = entries.where((e) => e.isFoundIn(scope)).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // A different sentence in the year view, because the number means
            // something different: this year, not ever.
            scope == CollectionScope.thisYear
                ? l10n.collectionProgressThisYear(found, total)
                : l10n.collectionProgress(found, total),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : found / total,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// All species · My collection · This year (`SAM-16`, 3.4).
///
/// A segmented control rather than three chips: they are three views of the
/// same grid, not three independent filters, and only one can be true at a
/// time.
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
              value: CollectionScope.everything,
              label: Text(l10n.collectionScopeAll),
            ),
            ButtonSegment(
              value: CollectionScope.mine,
              label: Text(l10n.collectionOnlyMine),
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

/// One species: a photo if it has been found, a placeholder if not (`SAM-04`).
class CollectionCard extends ConsumerWidget {
  const CollectionCard({
    super.key,
    required this.entry,
    this.scope = CollectionScope.everything,
  });

  final CollectionEntry entry;

  /// Which collection this card is part of — a species on the life list but
  /// not yet heard this year reads as *open* in the year view (`SAM-16`).
  final CollectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final found = entry.isFoundIn(scope);

    return Semantics(
      button: true,
      label:
          found
              ? l10n.collectionCardCollectedA11y(entry.commonName, entry.stars)
              : l10n.collectionCardOpenA11y(entry.commonName, entry.stars),
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
              Expanded(child: _CardImage(entry: entry, found: found)),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // An open cell keeps its name: the album is a wanted
                      // list, and a row of question marks is not one.
                      entry.commonName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color:
                            found
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // "Here, this week: 200 ⭐" — both halves of that label are
                    // load-bearing (SAM-03).
                    Text(
                      l10n.collectionWorthHereThisWeek(entry.stars),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
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
  const _CardImage({required this.entry, required this.found});

  final CollectionEntry entry;

  /// Whether it counts as found in the current scope.
  final bool found;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!found) {
      // The placeholder the app already ships — no pipeline work, no new
      // assets. SAM-04b replaces it with a per-species silhouette at P1, which
      // is what turns a grid of blanks into a wanted list.
      return Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            AppIcons.helpOutlineRounded,
            size: 32,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final path = entry.imagePath;
    if (path == null) {
      return Container(color: theme.colorScheme.surfaceContainerHighest);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          path,
          fit: BoxFit.cover,
          // A missing bundle must not look like a crash. Without the species
          // bundle built, every cell falls back to this quietly.
          errorBuilder:
              (context, _, _) =>
                  Container(color: theme.colorScheme.surfaceContainerHighest),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              AppIcons.checkCircle,
              size: 14,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyCollection extends StatelessWidget {
  const _EmptyCollection({required this.scope});

  /// Which view is empty — three different facts needing three messages.
  final CollectionScope scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // "You have nothing yet", "nothing yet this year" and "nothing in this
    // group here" are three different facts. Telling a child the first when
    // the third is true is discouraging for no reason — and telling them the
    // first in January, when the life list is full, would be plainly wrong.
    final (title, subtitle) = switch (scope) {
      CollectionScope.mine => (
        l10n.collectionEmptyTitle,
        l10n.collectionEmptySubtitle,
      ),
      CollectionScope.thisYear => (
        l10n.collectionEmptyThisYearTitle,
        l10n.collectionEmptyThisYearSubtitle,
      ),
      CollectionScope.everything => (l10n.collectionNoMatches, null),
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
