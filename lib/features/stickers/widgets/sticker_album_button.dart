// =============================================================================
// StickerAlbumButton — the way into the album, under the level bar (AVA-07)
// =============================================================================
//
// Under the level bar on the home header, visible without a gesture on any
// screen tall enough to carry it there. On a short portrait phone it sits
// behind the tile panel — `KID-04` keeps every destination above the fold —
// and `StickerPickCard` announces an open pick in the panel instead. While a pick is open it says so —
// "Pick a sticker" — and stands out in the surface colour against the header;
// otherwise it is a quiet outline. Information, never the error palette.
//
// It never waits: until the catalogue, board and level have loaded it is the
// quiet version, which is also what an empty or broken catalogue looks like.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../../shared/utils/app_icons.dart';
import '../sticker_album_screen.dart';
import '../sticker_providers.dart';

/// Opens the sticker album; says "Pick a sticker" while a pick is open.
class StickerAlbumButton extends ConsumerWidget {
  const StickerAlbumButton({super.key, required this.ink, this.large = false});

  /// The header's foreground colour.
  final Color ink;

  /// Tablet size.
  final bool large;

  /// Height of the button, which the header adds to its own budget.
  static double heightFor({bool large = false}) => large ? 52 : 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final picks = ref.watch(stickerPicksProvider).value;
    final count = picks?.pickableNow ?? 0;

    void open() => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StickerAlbumScreen()));

    final height = heightFor(large: large);
    final textStyle = (large
            ? theme.textTheme.titleMedium
            : theme.textTheme.labelLarge)
        ?.copyWith(fontWeight: FontWeight.w700);

    final button =
        count > 0
            ? FilledButton.icon(
              onPressed: open,
              icon: const Icon(AppIcons.autoAwesomeRounded),
              label: Text(l10n.stickerAlbumPickButton(count)),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.surface,
                foregroundColor: theme.colorScheme.onSurface,
                minimumSize: Size(0, height),
                textStyle: textStyle,
              ),
            )
            : OutlinedButton.icon(
              onPressed: open,
              icon: const Icon(AppIcons.photoAlbumRounded),
              label: Text(l10n.stickerAlbumTitle),
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: BorderSide(color: ink.withValues(alpha: 0.5)),
                minimumSize: Size(0, height),
                textStyle: textStyle,
              ),
            );

    return Center(child: button);
  }
}
