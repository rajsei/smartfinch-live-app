// =============================================================================
// AvatarCard — the bird, its level, and how far to the next (AVA-01, STAT-07)
// =============================================================================
//
// One widget for two places (`AVA-01`: the home screen and the points
// overview), so the app cannot show two different levels on two screens.
//
// ### What it says, in order
//
//   **The bird.** `AVA-02`'s stage of life, which is the level made visible.
//   **The name**, when the child has given one (`AVA-05`) — otherwise the
//   level title, so the line is never empty.
//   **Level 4 · Fledgling**, because the number is what a child compares and
//   the title is what they remember.
//   **The bar** (`STAT-07`), with the stars still to go underneath it.
//
// ### The bar never says "you have lost ground"
//
// Levels ratchet (`AUS-12`): after a rebalancing the stored level can sit
// above what today's stars would earn. `LevelProgress.fraction` clamps at
// zero, so the bar reads empty rather than negative, and nothing anywhere
// mentions it. The child keeps the level and never finds out it was defended.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../avatar_providers.dart';
import '../level_ladder.dart';

/// The avatar with its level and progress (`AVA-01`, `AVA-02`, `STAT-07`).
class AvatarCard extends ConsumerWidget {
  const AvatarCard({
    super.key,
    this.compact = false,
    this.onTap,
    this.foreground,
  });

  /// Drops the progress bar, for the tighter landscape header.
  final bool compact;

  /// Opens the naming sheet (`AVA-05`) where the host wires one up.
  final VoidCallback? onTap;

  /// Colour to draw on, when the card sits on a coloured block rather than on
  /// the surface. Defaults to the theme's ordinary on-surface colour.
  final Color? foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final progress = ref.watch(levelProgressProvider).value;
    final name = ref.watch(avatarNameProvider).value;

    // Before the database has opened, the egg — not a spinner. A child
    // arriving at their home screen should see their bird immediately, and
    // level 1 is what an empty database means anyway.
    final shown =
        progress ??
        const LevelProgress(
          level: Level(number: 1, key: 'egg', fromStars: 0),
          stars: 0,
        );
    final ink = foreground ?? theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: compact ? 4 : 8),
        child: Row(
          children: [
            AvatarFigure(stage: shown.stage, size: compact ? 40 : 56),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name ?? levelTitle(l10n, shown.level.key),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    l10n.levelWithTitle(
                      shown.level.number,
                      levelTitle(l10n, shown.level.key),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.withValues(alpha: 0.85),
                    ),
                  ),
                  if (!compact) ...[
                    const SizedBox(height: 6),
                    LevelProgressBar(progress: shown, foreground: ink),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The bird itself.
///
/// Its own widget so the placeholder emoji can become an illustration in one
/// place, and so a test can find the stage without going through the card.
class AvatarFigure extends StatelessWidget {
  const AvatarFigure({super.key, required this.stage, this.size = 56});

  final AvatarStage stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          stage.emoji,
          style: TextStyle(fontSize: size * 0.72),
          semanticsLabel: _label(AppLocalizations.of(context)!),
        ),
      ),
    );
  }

  String _label(AppLocalizations l10n) => switch (stage) {
    AvatarStage.egg => l10n.avatarStageEgg,
    AvatarStage.chick => l10n.avatarStageChick,
    AvatarStage.fledgling => l10n.avatarStageFledgling,
    AvatarStage.adult => l10n.avatarStageAdult,
  };
}

/// How far to the next level (`STAT-07`).
class LevelProgressBar extends StatelessWidget {
  const LevelProgressBar({super.key, required this.progress, this.foreground});

  final LevelProgress progress;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final ink = foreground ?? theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 8,
            backgroundColor: ink.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(ink),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          // At the top of the ladder there is nothing left to go, and saying
          // "0 stars to the next level" would read as a bug rather than as an
          // achievement.
          progress.next == null
              ? l10n.levelTopOfTheLadder
              : l10n.levelStarsToNext(
                progress.starsToNext,
                levelTitle(l10n, progress.next!.key),
              ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: ink.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

/// The level's name in the child's language (§3.5).
String levelTitle(AppLocalizations l10n, String key) => switch (key) {
  'egg' => l10n.levelEgg,
  'chick' => l10n.levelChick,
  'nestling' => l10n.levelNestling,
  'fledgling' => l10n.levelFledgling,
  'youngBird' => l10n.levelYoungBird,
  'scout' => l10n.levelScout,
  'listener' => l10n.levelListener,
  'singer' => l10n.levelSinger,
  'territoryHolder' => l10n.levelTerritoryHolder,
  'farFlier' => l10n.levelFarFlier,
  'migrant' => l10n.levelMigrant,
  'returner' => l10n.levelReturner,
  'oldBird' => l10n.levelOldBird,
  'flockLeader' => l10n.levelFlockLeader,
  _ => l10n.levelLegend,
};
