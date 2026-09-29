// =============================================================================
// StickerPickCard — "Pick a sticker" above the Live tile, on short phones
// =============================================================================
//
// On a phone too short for the album button in the header (`KID-04`: every
// destination one tap away, without scrolling), the button lives behind the
// tile panel and appears when the panel is pulled down. An open pick must not
// hide there, so while one is open this card takes the slot above the Live
// tile — the slot `HOME-06`'s "still possible today" uses.
//
// It *takes* the slot rather than joining it: two boxes above the Live tile
// would push the last row of destinations below the fold, which is the whole
// thing the short-phone layout avoids. With no pick open, [fallback] shows as
// before. A sticker pick is a one-off that waits until chosen; the daily
// suggestion is back the moment it is.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../../shared/utils/app_icons.dart';
import '../sticker_album_screen.dart';
import '../sticker_providers.dart';

/// "Pick a sticker" while a pick is open; otherwise [fallback].
class StickerPickCard extends ConsumerWidget {
  const StickerPickCard({super.key, required this.fallback});

  /// What the slot shows when there is nothing to pick.
  final Widget fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No spinner: until the picks are known, the slot is what it always was.
    final count = ref.watch(stickerPicksProvider).value?.pickableNow ?? 0;
    if (count == 0) return fallback;

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      // The same bottom gap the suggestion card leaves above the Live tile.
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const StickerAlbumScreen(),
                ),
              ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    AppIcons.autoAwesomeRounded,
                    size: 22,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.stickerAlbumPickButton(count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    AppIcons.chevronRight,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
