// =============================================================================
// StickerPickCard — "Pick a sticker" above the Live tile, on short phones
// =============================================================================
//
// On a phone too short for the album button in the header (`KID-04`: every
// destination one tap away, without scrolling), the button lives behind the
// tile panel and appears when the panel is pulled down. An open pick must not
// hide there, so while one is open this card sits directly above the Live
// tile. With no pick open it is absent, and costs no room at all.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../../shared/utils/app_icons.dart';
import '../sticker_album_screen.dart';
import '../sticker_providers.dart';

/// "Pick a sticker" while a pick is open; otherwise nothing.
class StickerPickCard extends ConsumerWidget {
  const StickerPickCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No spinner: until the picks are known, there is nothing to announce.
    final count = ref.watch(stickerPicksProvider).value?.pickableNow ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      // The gap to the Live tile is the card's own, so an absent card
      // leaves none.
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
