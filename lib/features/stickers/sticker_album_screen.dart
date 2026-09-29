// =============================================================================
// Sticker album — pick a sticker, read its fact again (AVA-07)
// =============================================================================
//
// Reached from the button under the level bar on the home screen. Three parts,
// top to bottom:
//
//   **A banner** while a pick is open: "You may pick a sticker!".
//   **Your stickers**, in the order they were picked. Tapping one shows its
//   fact again.
//   **The rest.** While a pick is open they are in colour and tapping one asks
//   "Take this sticker?"; otherwise they are faded and say at which level the
//   next pick comes.
//
// ### Picking is deliberate, the fact is the reward
//
// A pick is permanent, so a tap only *asks*; the child confirms. The fact is
// held back until after the pick — it is the surprise for having chosen, not
// a sales pitch for choosing. A faded sticker therefore shows its name, never
// its fact.
//
// ### Nothing here says anything is missing
//
// When every sticker is taken but levels are still open, the album says the
// child has collected them all — not that picks are waiting for artwork. The
// open picks wait quietly (principle 1: no commentary on what is not there).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../shared/utils/app_icons.dart';
import '../../shared/widgets/content_width_constraint.dart';
import '../avatar/avatar_providers.dart';
import 'sticker_board.dart';
import 'sticker_catalog.dart';
import 'sticker_providers.dart';

/// The sticker album (`AVA-07`).
class StickerAlbumScreen extends ConsumerWidget {
  const StickerAlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    final catalog = ref.watch(stickerCatalogProvider).value;
    final board = ref.watch(stickerBoardProvider).value;
    final progress = ref.watch(levelProgressProvider).value;
    final picks = ref.watch(stickerPicksProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.stickerAlbumTitle)),
      body: ContentWidthConstraint(
        child:
            catalog == null || board == null || progress == null
                ? const Center(child: CircularProgressIndicator())
                : _AlbumBody(
                  catalog: catalog,
                  board: board,
                  level: progress.level.number,
                  canPick: picks?.canPick ?? false,
                  pickCount: picks?.pickableNow ?? 0,
                ),
      ),
    );
  }
}

class _AlbumBody extends ConsumerWidget {
  const _AlbumBody({
    required this.catalog,
    required this.board,
    required this.level,
    required this.canPick,
    required this.pickCount,
  });

  final StickerCatalog catalog;
  final StickerBoard board;
  final int level;
  final bool canPick;
  final int pickCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // In the order they were picked, so the album reads as a history.
    final mine = [
      for (final grantedAt in board.picks.keys.toList()..sort())
        if (catalog.byId(board.picks[grantedAt]!) case final sticker?) sticker,
    ];
    final picked = board.pickedIds;
    final rest = [
      for (final sticker in catalog.stickers)
        if (!picked.contains(sticker.id)) sticker,
    ];
    final hasOpenLevels = board.openLevels(level).isNotEmpty;

    const grid = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 0.82,
    );

    Widget heading(String text) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      sliver: SliverToBoxAdapter(
        child: Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    Widget note(String text) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      sliver: SliverToBoxAdapter(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    return CustomScrollView(
      slivers: [
        if (canPick)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _PickBanner(text: l10n.stickerAlbumPickBanner(pickCount)),
            ),
          ),
        if (mine.isNotEmpty) ...[
          heading(l10n.stickerAlbumMine),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: grid,
              itemCount: mine.length,
              itemBuilder:
                  (context, i) => _StickerTile(
                    catalog: catalog,
                    sticker: mine[i],
                    state: _TileState.mine,
                  ),
            ),
          ),
        ],
        if (rest.isNotEmpty) ...[
          heading(
            canPick ? l10n.stickerAlbumToPick : l10n.stickerAlbumStillToCollect,
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid.builder(
              gridDelegate: grid,
              itemCount: rest.length,
              itemBuilder:
                  (context, i) => _StickerTile(
                    catalog: catalog,
                    sticker: rest[i],
                    state: canPick ? _TileState.pickable : _TileState.later,
                    nextLevel: level + 1,
                  ),
            ),
          ),
        ],
        if (rest.isEmpty && mine.isNotEmpty)
          note(l10n.stickerAlbumAllCollected)
        else if (!canPick && !hasOpenLevels)
          note(l10n.stickerAlbumNextLevel(level + 1))
        else
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

/// "You may pick a sticker!" — information, in the primary container colour,
/// never the error palette.
class _PickBanner extends StatelessWidget {
  const _PickBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              AppIcons.autoAwesomeRounded,
              size: 32,
              color: theme.colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TileState { mine, pickable, later }

class _StickerTile extends ConsumerWidget {
  const _StickerTile({
    required this.catalog,
    required this.sticker,
    required this.state,
    this.nextLevel = 1,
  });

  final StickerCatalog catalog;
  final Sticker sticker;
  final _TileState state;
  final int nextLevel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final name = stickerName(ref, catalog, sticker);
    final faded = state == _TileState.later;

    return Semantics(
      button: true,
      label: switch (state) {
        _TileState.mine => l10n.stickerPickedA11y(name),
        _TileState.pickable => l10n.stickerPickableA11y(name),
        _TileState.later => l10n.stickerLockedA11y(name),
      },
      excludeSemantics: true,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color:
            state == _TileState.pickable
                ? theme.colorScheme.secondaryContainer
                : theme.colorScheme.surfaceContainerHigh,
        child: InkWell(
          onTap: () => _onTap(context, ref, name),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: StickerImage(sticker: sticker, faded: faded)),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        faded
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref, String name) async {
    final l10n = AppLocalizations.of(context)!;

    switch (state) {
      case _TileState.mine:
        await showStickerFact(
          context,
          catalog: catalog,
          sticker: sticker,
          name: name,
        );
      case _TileState.later:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(l10n.stickerAlbumNextLevel(nextLevel))),
          );
      case _TileState.pickable:
        final take = await _confirmPick(context, name);
        if (take != true || !context.mounted) return;

        final picked = await pickSticker(ref, sticker.id);
        if (!picked || !context.mounted) return;

        await showStickerFact(
          context,
          catalog: catalog,
          sticker: sticker,
          name: name,
          celebrate: true,
        );
    }
  }

  Future<bool?> _confirmPick(BuildContext context, String name) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 180, child: StickerImage(sticker: sticker)),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.stickerPickQuestion,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.stickerPickCancel),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(AppIcons.checkRounded),
                label: Text(l10n.stickerPickConfirm),
              ),
            ],
          ),
    );
  }
}

/// A sticker's picture, never stretched; faded for one not yet collected.
class StickerImage extends StatelessWidget {
  const StickerImage({super.key, required this.sticker, this.faded = false});

  final Sticker sticker;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      sticker.imageAsset,
      fit: BoxFit.contain,
      // A broken file must cost the picture, not the album.
      errorBuilder: (context, _, _) => const SizedBox.shrink(),
    );

    if (!faded) return image;

    return Opacity(
      opacity: 0.45,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 1, 0, //
        ]),
        child: image,
      ),
    );
  }
}

/// The sticker with its fact — "Did you know?".
///
/// [celebrate] is the reveal right after a pick: the sticker grows in. Opened
/// again from the album it simply shows.
Future<void> showStickerFact(
  BuildContext context, {
  required StickerCatalog catalog,
  required Sticker sticker,
  required String name,
  bool celebrate = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final theme = Theme.of(context);
  final fact = catalog.factFor(
    sticker.id,
    Localizations.localeOf(context).toLanguageTag(),
  );

  return showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: celebrate ? 0.4 : 1.0, end: 1.0),
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.elasticOut,
                  builder:
                      (context, scale, child) =>
                          Transform.scale(scale: scale, child: child),
                  child: SizedBox(
                    height: 200,
                    child: StickerImage(sticker: sticker),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (fact != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.stickerFactHeading,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fact,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.stickerFactDone),
            ),
          ],
        ),
  );
}
