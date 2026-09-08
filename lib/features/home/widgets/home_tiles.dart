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
// ### Tiles that are not here yet
//
// Points arrives with step 2.7. It is deliberately **absent rather than
// disabled**: a greyed-out tile is not something an eight-year-old reads as
// "later", and a tile that opens an empty screen is a broken promise. Adding
// it is a single entry in [_secondaryTiles].
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../collection/collection_screen.dart';
import '../../explore/explore_screen.dart';
import '../../journal/journal_screen.dart';
import '../../live/live_screen.dart';
import '../../settings/settings_screen.dart';

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
  // Punkte (Points) belongs here — 2.7.
  _HomeTile(
    icon: AppIcons.tuneRounded,
    label: _settingsLabel,
    builder: SettingsScreen.new,
  ),
];

String _collectionLabel(AppLocalizations l10n) => l10n.collectionTitle;
String _exploreLabel(AppLocalizations l10n) => l10n.exploreMode;
String _journalLabel(AppLocalizations l10n) => l10n.homeTileJournal;
String _settingsLabel(AppLocalizations l10n) => l10n.settings;

/// The home screen's navigation: one large Live tile plus secondary tiles.
class HomeTiles extends ConsumerWidget {
  const HomeTiles({super.key, this.isTablet = false, this.compact = false});

  final bool isTablet;

  /// Landscape: shorter primary tile, tiles in one row.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isTablet ? 620 : 460),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LiveTile(
              isTablet: isTablet,
              compact: compact,
              onTap:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const LiveScreen()),
                  ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Row(
              children: [
                for (final tile in _secondaryTiles) ...[
                  Expanded(
                    child: _SecondaryTile(
                      icon: tile.icon,
                      label: tile.label(l10n),
                      isTablet: isTablet,
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => tile.builder(),
                            ),
                          ),
                    ),
                  ),
                  if (tile != _secondaryTiles.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The one thing you are meant to do (HOME-08).
class _LiveTile extends StatelessWidget {
  const _LiveTile({
    required this.onTap,
    required this.isTablet,
    required this.compact,
  });

  final VoidCallback onTap;
  final bool isTablet;
  final bool compact;

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
              horizontal: 20,
              vertical: compact ? 18 : (isTablet ? 32 : 26),
            ),
            child: Row(
              children: [
                Icon(
                  AppIcons.micRounded,
                  size: compact ? 34 : (isTablet ? 48 : 40),
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isTablet;

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
            padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: isTablet ? 28 : 24,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
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
