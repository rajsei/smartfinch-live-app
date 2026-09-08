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
  bool _onlyCollected = false;

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
                    (!_onlyCollected || entry.isCollected))
                  entry,
            ];

            return Column(
              children: [
                const CollectionProgressBar(),
                _Filters(
                  groups: _groups,
                  onlyCollected: _onlyCollected,
                  onToggleGroup:
                      (group) => setState(() {
                        _groups.contains(group)
                            ? _groups.remove(group)
                            : _groups.add(group);
                      }),
                  onToggleCollected:
                      () => setState(() => _onlyCollected = !_onlyCollected),
                ),
                Expanded(
                  child:
                      visible.isEmpty
                          ? _EmptyCollection(onlyCollected: _onlyCollected)
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

/// "37 of 128 species in your region" (`SAM-05`).
class CollectionProgressBar extends ConsumerWidget {
  const CollectionProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final progress = ref.watch(collectionProgressProvider).value;
    if (progress == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.collectionProgress(progress.collected, progress.total),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.groups,
    required this.onlyCollected,
    required this.onToggleGroup,
    required this.onToggleCollected,
  });

  final Set<CollectionGroup> groups;
  final bool onlyCollected;
  final void Function(CollectionGroup group) onToggleGroup;
  final VoidCallback onToggleCollected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          FilterChip(
            label: Text(l10n.collectionOnlyMine),
            selected: onlyCollected,
            onSelected: (_) => onToggleCollected(),
          ),
          const SizedBox(width: 12),
          for (final group in CollectionGroup.values) ...[
            FilterChip(
              label: Text(group.label(l10n)),
              selected: groups.contains(group),
              onSelected: (_) => onToggleGroup(group),
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
  const CollectionCard({super.key, required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      label:
          entry.isCollected
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
              Expanded(child: _CardImage(entry: entry)),
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
                            entry.isCollected
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
  const _CardImage({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!entry.isCollected) {
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
  const _EmptyCollection({required this.onlyCollected});

  /// Whether the filter is what emptied it — a very different message.
  final bool onlyCollected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

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
              onlyCollected
                  ? l10n.collectionEmptyTitle
                  : l10n.collectionNoMatches,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (onlyCollected) ...[
              const SizedBox(height: 6),
              Text(
                l10n.collectionEmptySubtitle,
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
