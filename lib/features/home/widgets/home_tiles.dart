// =============================================================================
// Home tiles — one thing you are meant to do, and five places to go afterwards
// =============================================================================
//
// HOME-04 and HOME-08. The old home screen carried six mode tiles across a
// paged carousel; five of those modes were deleted in 0.3, which left a
// carousel of one card with two page-indicator dots under it.
//
// What replaces it is not a smaller carousel but a different shape:
//
//   **Live is a large primary tile.** There is exactly one thing this app is
//   for, and a child opening it should not have to choose. Everything else is
//   somewhere to go *after* listening.
//   **The rest are equal secondary tiles**, because ranking them would be
//   guessing — a child who wants their collection and a parent who wants
//   settings both arrive on this screen.
//
// The grid is complete as of 2.7: Sammlung, Erkunden, Tagebuch, Punkte,
// Einstellungen. Nothing here is disabled or a placeholder — a tile that opens
// an empty screen is a broken promise, and a greyed-out one is not something
// an eight-year-old reads as "later".
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../collection/collection_screen.dart';
import '../../explore/explore_screen.dart';
import '../../journal/journal_screen.dart';
import '../../live/live_screen.dart';
import '../../points/points_screen.dart';
import '../../settings/settings_screen.dart';
import 'still_possible_card.dart';

/// One secondary destination.
class _HomeTile {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String Function(AppLocalizations l10n) label;
  final Widget Function() builder;
}

/// Everything other than Live, in the order HOME-04 lists them.
const List<_HomeTile> _secondaryTiles = [
  // Collection first: it is the one a child opens in the evening. Explore
  // sits next to it and answers the other question — two destinations, not a
  // toggle (SAM-02).
  _HomeTile(
    icon: AppIcons.gridViewRounded,
    label: _collectionLabel,
    builder: CollectionScreen.new,
  ),
  _HomeTile(
    icon: AppIcons.searchRounded,
    label: _exploreLabel,
    builder: ExploreScreen.new,
  ),
  _HomeTile(
    icon: AppIcons.libraryMusic,
    label: _journalLabel,
    builder: JournalScreen.new,
  ),
  _HomeTile(
    icon: AppIcons.barChart,
    label: _pointsLabel,
    builder: PointsScreen.new,
  ),
  _HomeTile(
    icon: AppIcons.tuneRounded,
    label: _settingsLabel,
    builder: SettingsScreen.new,
  ),
];

String _collectionLabel(AppLocalizations l10n) => l10n.collectionTitle;
String _exploreLabel(AppLocalizations l10n) => l10n.exploreMode;
String _journalLabel(AppLocalizations l10n) => l10n.homeTileJournal;
String _pointsLabel(AppLocalizations l10n) => l10n.pointsTitle;
String _settingsLabel(AppLocalizations l10n) => l10n.settings;

/// The home screen's navigation: one large Live tile plus secondary tiles.
class HomeTiles extends ConsumerWidget {
  const HomeTiles({
    super.key,
    this.isTablet = false,
    this.compact = false,
    this.dense = false,
  });

  final bool isTablet;

  /// Landscape: shorter primary tile, tiles in one row.
  final bool compact;

  /// A screen with no height to spare, which the suggestion above the tiles
  /// answers by making itself shorter rather than by pushing a destination
  /// below the fold (`KID-04`).
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ConstrainedBox(
      // Capped, because a tile stretched across a tablet is a stripe rather
      // than a button — but a wider cap than the phone's, so the extra width
      // goes into the tiles instead of into margin.
      constraints: BoxConstraints(maxWidth: isTablet ? 760 : 480),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // HOME-06 sits here rather than in the header, because the thing
            // it suggests is done by the button directly underneath it. It
            // takes no room on a day with nothing left to suggest — the gap
            // below it belongs to the card, so an absent card leaves none.
            StillPossibleCard(dense: dense),
            _LiveTile(
              isTablet: isTablet,
              compact: compact,
              dense: dense,
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LiveScreen()),
                  ),
            ),
            SizedBox(height: compact ? 8 : (isTablet ? 18 : 14)),
            // Portrait: two, then three. Five across a phone leaves each tile
            // narrower than its own label, and "Einstellungen" wrapping onto
            // three lines is how a grid stops reading as a grid. Landscape
            // keeps the single row, where there is width for it.
            if (compact)
              _TileRow(
                tiles: _secondaryTiles,
                isTablet: isTablet,
                compact: compact,
                dense: dense,
              )
            else ...[
              _TileRow(
                tiles: _secondaryTiles.take(2).toList(),
                isTablet: isTablet,
                compact: compact,
                dense: dense,
              ),
              SizedBox(height: isTablet ? 14 : 10),
              _TileRow(
                tiles: _secondaryTiles.skip(2).toList(),
                isTablet: isTablet,
                compact: compact,
                dense: dense,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One row of equal secondary tiles.
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.tiles,
    required this.isTablet,
    required this.compact,
    required this.dense,
  });

  final List<_HomeTile> tiles;
  final bool isTablet;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Row(
      children: [
        for (final tile in tiles) ...[
          Expanded(
            child: _SecondaryTile(
              icon: tile.icon,
              label: tile.label(l10n),
              isTablet: isTablet,
              dense: dense,
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => tile.builder()),
                  ),
            ),
          ),
          if (tile != tiles.last) SizedBox(width: isTablet ? 14 : 10),
        ],
      ],
    );
  }
}

/// The one thing you are meant to do (HOME-08).
class _LiveTile extends StatelessWidget {
  const _LiveTile({
    required this.onTap,
    required this.isTablet,
    required this.compact,
    required this.dense,
  });

  final VoidCallback onTap;
  final bool isTablet;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Semantics(
      button: true,
      label: l10n.liveMode,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 28 : 22,
              vertical: compact ? 20 : (isTablet ? 46 : (dense ? 26 : 34)),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.micRounded,
                  size: compact ? 34 : (isTablet ? 60 : 46),
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.liveMode,
                        style: (compact
                                ? theme.textTheme.titleLarge
                                : theme.textTheme.headlineSmall)
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onPrimary,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.homeLiveTileSubtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimary.withValues(
                            alpha: 0.9,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Somewhere to go after listening. All secondary tiles look the same, on
/// purpose: ranking them would be guessing.
class _SecondaryTile extends StatelessWidget {
  const _SecondaryTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isTablet,
    required this.dense,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isTablet;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: isTablet ? 30 : (dense ? 18 : 22),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isTablet ? 38 : 30,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                SizedBox(height: isTablet ? 10 : 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (isTablet
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.labelLarge)
                      ?.copyWith(color: theme.colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
