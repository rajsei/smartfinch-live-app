// =============================================================================
// Sticker providers — catalogue, board, open picks (AVA-07)
// =============================================================================
//
// The board lives in the profile's `avatarState` blob under [kStickerStateKey]
// and is only ever written through `writeAvatarField`, which merges — so
// renaming the bird cannot erase the stickers, nor the stickers the name.
//
// The number of open picks comes from the *displayed* level, which is the
// ratcheted one (`levelProgressProvider`). A pick granted is never taken back.
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

import '../avatar/avatar_providers.dart';
import '../avatar/avatar_state.dart';
import '../explore/explore_providers.dart';
import '../scoring/scoring_providers.dart';
import '../../shared/providers/settings_providers.dart';
import 'sticker_board.dart';
import 'sticker_catalog.dart';

/// The key of the sticker board in `UserProfiles.avatarState`.
const String kStickerStateKey = 'stickers';

/// Every sticker the app ships, with its facts.
final stickerCatalogProvider = FutureProvider<StickerCatalog>(
  (ref) => loadStickerCatalog(rootBundle),
);

/// The child's picks and arrangements.
final stickerBoardProvider = FutureProvider<StickerBoard>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  return StickerBoard.fromJson(await readAvatarField(db, kStickerStateKey));
});

/// How many picks are open, and whether there is anything to pick from.
@immutable
class StickerPicks {
  const StickerPicks({required this.openLevels, required this.available});

  /// Levels reached but not yet used for a pick.
  final int openLevels;

  /// Stickers in the catalogue that have not been picked.
  final int available;

  /// True when the child can pick a sticker right now.
  ///
  /// False when every sticker is taken, even with levels open: the pick then
  /// waits quietly for new stickers, and nothing says anything is missing.
  bool get canPick => openLevels > 0 && available > 0;

  /// How many stickers can be picked right now: the open picks, as far as
  /// there are stickers to fill them.
  int get pickableNow => openLevels < available ? openLevels : available;
}

/// Open picks against the ratcheted level (`AUS-12`).
final stickerPicksProvider = FutureProvider<StickerPicks>((ref) async {
  final progress = await ref.watch(levelProgressProvider.future);
  final board = await ref.watch(stickerBoardProvider.future);
  final catalog = await ref.watch(stickerCatalogProvider.future);

  final picked = board.pickedIds;
  return StickerPicks(
    openLevels: board.openLevels(progress.level.number).length,
    available: catalog.stickers.where((s) => !picked.contains(s.id)).length,
  );
});

/// Writes [board] and refreshes everything that reads it.
Future<void> saveStickerBoard(WidgetRef ref, StickerBoard board) async {
  await writeAvatarField(
    ref.read(appDatabaseProvider),
    kStickerStateKey,
    board.toJson(),
  );
  ref.invalidate(stickerBoardProvider);
}

/// Picks sticker [id] with the lowest open level, and puts it on the board.
///
/// On the board straight away, so the child sees it on the home screen the
/// moment they go back — arranging it is optional, having it is not.
///
/// Returns false, and changes nothing, when no pick is open or [id] is taken
/// — a double tap on "pick" must not throw.
Future<bool> pickSticker(WidgetRef ref, String id) async {
  final progress = await ref.read(levelProgressProvider.future);
  final board = await ref.read(stickerBoardProvider.future);

  if (board.openLevels(progress.level.number).isEmpty) return false;
  if (board.pickedIds.contains(id)) return false;

  await saveStickerBoard(
    ref,
    board.pick(id, level: progress.level.number).place(id),
  );
  return true;
}

/// The name to show for [sticker], in the species-name language.
///
/// The list's own name first, then the taxonomy, then English. Reads the
/// taxonomy only if it has already loaded — a sticker is never worth waiting
/// for, and every sticker the app ships carries a usable fallback.
String stickerName(WidgetRef ref, StickerCatalog catalog, Sticker sticker) {
  final taxonomy = ref.watch(taxonomyServiceProvider).value;
  return catalog.nameFor(
    sticker,
    ref.watch(effectiveSpeciesLocaleProvider),
    taxonomyName:
        (scientificName, locale) =>
            taxonomy?.lookup(scientificName)?.commonNameForLocale(locale),
  );
}
