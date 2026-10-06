// =============================================================================
// StickerBoardLayer — the child's stickers on the home screen (AVA-07)
// =============================================================================
//
// The whole home screen is the board. Positions are fractions of it and sizes
// fractions of its shorter side (see `sticker_board.dart`), so the same numbers
// work on every phone.
//
// ### Two states, and the panel decides
//
// **Panel up:** the stickers are background — behind the header and the tile
// panel, ignored by touch, invisible to a screen reader. Nothing a child does
// on the home screen can move one by accident.
//
// **Panel down:** the space the panel freed is where stickers are arranged.
// The layer then sits *above* the header so a finger reaches every sticker,
// but only the stickers themselves take touches — a tap on empty space still
// lands on the header underneath.
//
//   • one finger drags, two fingers turn and resize (one gesture, not modes)
//   • the sticker touched comes to the front and shows "back to the album";
//     a touch anywhere else lets go of it again
//   • a sticker stays on the board, however big or turned: one pushed
//     against the top stops there instead of sliding under the header, where
//     it would cover the level bar and could no longer be touched. The sides
//     in portrait are the screen's own edges; there it may hang out by half
//   • a strip above the handle holds the picked stickers not on the board;
//     a tap sticks one on
//
// Pulling the panel back up is "done". There is no save button: every gesture
// is written when the finger lifts — a child who puts the phone down mid-way
// has lost nothing.
//
// ### Nothing is ever lost
//
// "Back to the album" takes a sticker off the board; it stays picked and is
// one tap away in the strip. There is no delete.
// =============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../../shared/utils/app_icons.dart';
import '../sticker_board.dart';
import '../sticker_catalog.dart';
import '../sticker_providers.dart';

/// The stickers of [layout], filling the box it is given.
class StickerBoardLayer extends ConsumerStatefulWidget {
  const StickerBoardLayer({
    super.key,
    required this.layout,
    this.editable = false,
  });

  final StickerLayout layout;

  /// Arranging, rather than showing.
  final bool editable;

  /// Whether the strip is folded out. Static so it outlives the layer, which
  /// is rebuilt every time the panel moves: a child who folded the strip away
  /// should not find it open again the next time, for as long as the app
  /// runs. Not stored — a fresh start shows it, with its hint.
  static bool _trayOpen = true;

  /// Folds the strip out again, as a fresh start would.
  @visibleForTesting
  static void resetTray() => _trayOpen = true;

  @override
  ConsumerState<StickerBoardLayer> createState() => _StickerBoardLayerState();
}

class _StickerBoardLayerState extends ConsumerState<StickerBoardLayer> {
  /// The board as the child is changing it; written on every finger lift.
  StickerBoard? _draft;

  /// The stored board [_draft] was last taken from. A write reloads the
  /// provider; until the new value arrives the draft must not fall back to the
  /// old one, or a sticker would jump back for a frame.
  StickerBoard? _synced;

  /// The sticker last touched, which shows "back to the album".
  String? _selected;

  /// The placement a two-finger gesture started from.
  StickerPlacement? _gestureStart;

  bool get _gesturing => _gestureStart != null;

  /// Fingers currently down on a sticker. A second finger landing beside the
  /// sticker another finger is holding is not "a tap somewhere else".
  int _pointersOnStickers = 0;

  @override
  void didUpdateWidget(StickerBoardLayer old) {
    super.didUpdateWidget(old);
    if (!widget.editable) {
      _selected = null;
      _pointersOnStickers = 0;
    }
  }

  /// A touch anywhere but on a sticker — empty board, the strip, the header,
  /// the handle — lets go of the one that was selected.
  void _deselect() {
    if (_selected == null || _gesturing || _pointersOnStickers > 0) return;
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(stickerCatalogProvider).value;
    final stored = ref.watch(stickerBoardProvider).value;
    if (catalog == null || stored == null) return const SizedBox.shrink();

    // The stored board wins whenever no finger is down: an album pick or a
    // restored backup shows at once, and our own writes come back unchanged.
    if (!_gesturing && !identical(stored, _synced)) {
      _draft = stored;
      _synced = stored;
    }
    final board = _draft ?? stored;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final side = size.shortestSide;

        final stickers = [
          for (final placement in board.placementsFor(widget.layout))
            if (catalog.byId(placement.id) case final sticker?)
              _placed(sticker, placement, size, side),
        ];

        if (!widget.editable) {
          // Background: no touch, no semantics, nothing to trip over.
          return IgnorePointer(
            child: ExcludeSemantics(
              child: ClipRect(child: Stack(children: stickers)),
            ),
          );
        }

        final unplaced = [
          for (final grantedAt in board.picks.keys.toList()..sort())
            if (!board.placedIds.contains(board.picks[grantedAt]))
              if (catalog.byId(board.picks[grantedAt]!) case final sticker?)
                sticker,
        ];

        // Clipped at the board's edge. The bird is kept inside it
        // (`keptOn`), so all this cuts is the image's transparent margin and
        // the selection frame — neither of which may lie over the header.
        return ClipRect(
          child: Stack(
            children: [
              ...stickers,
              // Fastened to the right edge and folding out of it, so it can be
              // put away when it sits over a sticker a child wants to reach.
              if (board.pickedIds.isNotEmpty)
                Positioned(
                  right: 0,
                  bottom: 8,
                  child: _Tray(
                    stickers: unplaced,
                    open: StickerBoardLayer._trayOpen,
                    openWidth: size.width - 12,
                    onToggle:
                        () => setState(
                          () =>
                              StickerBoardLayer._trayOpen =
                                  !StickerBoardLayer._trayOpen,
                        ),
                    onPlace: (sticker) => _commit(board.place(sticker.id)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _placed(
    Sticker sticker,
    StickerPlacement stored,
    Size size,
    double side,
  ) {
    // Kept on the board here as well as while dragging: a placement stored
    // before the board had its current size may still hang over its edge.
    final l10n = AppLocalizations.of(context)!;
    final placement = _keptOn(stored, sticker, size);
    final extent = placement.scale * side;
    // Hanging out on the right, the buttons move to the left corners: the
    // part of the sticker still on screen.
    final hangsOutRight = placement.x * size.width + extent / 2 > size.width;
    // The bird is kept on the board, its transparent margin is not: a sticker
    // pushed to the top or bottom edge can have its box reach past it. The
    // buttons stay on the board, where a finger can reach them.
    final boxTop = placement.y * size.height - extent / 2;
    final buttonsRoom = math.max(0.0, extent - 2 * _StickerActionButton.size);
    final topButtonInset = (-boxTop).clamp(0.0, buttonsRoom);
    final bottomButtonInset = (boxTop + extent - size.height).clamp(
      0.0,
      buttonsRoom,
    );
    final image = Image.asset(
      sticker.imageAsset,
      width: extent,
      height: extent,
      fit: BoxFit.contain,
      // Decoded at the size it is drawn, not at 512 × 512 each.
      cacheWidth: (extent * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(1, 512),
      gaplessPlayback: true,
      errorBuilder: (context, _, _) => SizedBox.square(dimension: extent),
    );

    final selected = widget.editable && _selected == placement.id;
    final rotated = Transform.rotate(
      angle: placement.rotation,
      child: Transform.flip(flipX: placement.flipped, child: image),
    );

    // ⚠️ One shape for every state. Selecting a sticker happens *during* the
    // touch that starts a gesture; if selecting changed the widgets around the
    // GestureDetector, Flutter would throw the detector away mid-gesture and
    // a two-finger pinch would never arrive. So the border is always there
    // (transparent when not selected) and the button is a later child. The
    // TapRegion and Listener are always there too, for the same reason; all
    // stickers share one region, so touching another sticker is not
    // "outside" — it selects that one instead.
    final Widget child =
        !widget.editable
            ? rotated
            : TapRegion(
              groupId: this,
              onTapOutside: (_) => _deselect(),
              child: Listener(
                onPointerDown: (_) => _pointersOnStickers++,
                onPointerUp: (_) => _releasePointer(),
                onPointerCancel: (_) => _releasePointer(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) => _select(placement.id),
                  // A tap only brings it to the front; that order is worth
                  // keeping.
                  onTap: () {
                    final draft = _draft;
                    if (draft != null) _commit(draft);
                  },
                  onScaleStart: (_) {
                    _select(placement.id);
                    setState(
                      () => _gestureStart = _currentPlacement(placement.id),
                    );
                  },
                  onScaleUpdate:
                      (details) => _update(sticker, details, size, side),
                  onScaleEnd: (_) {
                    final draft = _draft;
                    setState(() => _gestureStart = null);
                    if (draft != null) _commit(draft);
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: rotated,
                      ),
                      // Inside the sticker's box, not hanging off its
                      // corner: a touch outside a widget's bounds never
                      // reaches it.
                      if (selected) ...[
                        Positioned(
                          top: topButtonInset,
                          left: hangsOutRight ? 0 : null,
                          right: hangsOutRight ? null : 0,
                          child: _StickerActionButton(
                            icon: AppIcons.photoAlbumRounded,
                            label: l10n.stickerBoardRemove,
                            onPressed: () {
                              final board = _draft;
                              if (board == null) return;
                              setState(() => _selected = null);
                              _commit(board.remove(placement.id));
                            },
                          ),
                        ),
                        // Mirror: the bird looks the other way.
                        Positioned(
                          bottom: bottomButtonInset,
                          left: hangsOutRight ? 0 : null,
                          right: hangsOutRight ? null : 0,
                          child: _StickerActionButton(
                            icon: AppIcons.flipRounded,
                            label: l10n.stickerBoardMirror,
                            onPressed: () {
                              final board = _draft;
                              if (board == null) return;
                              // Mirrored, the bird may sit differently in its
                              // square — kept on the board as it is now.
                              final mirrored = board.mirror(
                                widget.layout,
                                placement.id,
                              );
                              final turned = mirrored
                                  .placementsFor(widget.layout)
                                  .firstWhere((p) => p.id == placement.id);
                              _commit(
                                mirrored.move(
                                  widget.layout,
                                  _keptOn(turned, sticker, size),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );

    return Positioned(
      // Keyed: bringing a sticker to the front reorders the children, and
      // without a key its gesture would carry on in whichever sticker took
      // its old place.
      key: ValueKey(placement.id),
      left: placement.x * size.width - extent / 2,
      top: placement.y * size.height - extent / 2,
      width: extent,
      height: extent,
      child: child,
    );
  }

  StickerPlacement? _currentPlacement(String id) {
    for (final p in _draft?.placementsFor(widget.layout) ?? const []) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _select(String id) {
    final board = _draft;
    if (board == null) return;

    final raised = board.bringToFront(widget.layout, id);
    setState(() {
      _selected = id;
      _draft = raised;
    });
  }

  void _update(
    Sticker sticker,
    ScaleUpdateDetails details,
    Size size,
    double side,
  ) {
    final start = _gestureStart;
    final board = _draft;
    final current = _currentPlacement(sticker.id);
    if (start == null || board == null || current == null) return;

    // Translation accumulates frame by frame; scale and rotation are relative
    // to where the gesture began, which is how the recogniser reports them.
    // Kept on the board every frame, not only when drawn: a finger that
    // pushes past the edge and comes back moves the sticker at once, rather
    // than first working off an overshoot nobody can see.
    final moved = current.copyWith(
      x: current.x + details.focalPointDelta.dx / size.width,
      y: current.y + details.focalPointDelta.dy / size.height,
      scale: details.pointerCount > 1 ? start.scale * details.scale : null,
      rotation:
          details.pointerCount > 1 ? start.rotation + details.rotation : null,
    );

    setState(
      () => _draft = board.move(widget.layout, _keptOn(moved, sticker, size)),
    );
  }

  /// [placement] kept on this board. In portrait the board's sides are the
  /// screen's, so a sticker may hang out there by half; sideways the header
  /// is on the left, and nothing may reach under it.
  StickerPlacement _keptOn(
    StickerPlacement placement,
    Sticker sticker,
    Size size,
  ) => placement.keptOn(
    width: size.width,
    height: size.height,
    openSides: widget.layout == StickerLayout.portrait,
    content: sticker.content,
  );

  void _releasePointer() {
    if (_pointersOnStickers > 0) _pointersOnStickers--;
  }

  Future<void> _commit(StickerBoard board) async {
    setState(() => _draft = board);
    await saveStickerBoard(ref, board);
  }
}

/// A round button on the sticker last touched: "back to the album" in the
/// top corner, "mirror" in the bottom one.
class _StickerActionButton extends StatelessWidget {
  const _StickerActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// Outer size: a 20-dp icon in 8 dp of padding.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: label,
      child: Material(
        color: theme.colorScheme.surface,
        shape: CircleBorder(
          side: BorderSide(color: theme.colorScheme.primary, width: 2),
        ),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
              semanticLabel: label,
            ),
          ),
        ),
      ),
    );
  }
}

/// The how-to line, and the picked stickers that are not on the board.
///
/// Folds out of the right edge. Folded away it is one tab with a count of the
/// stickers waiting in it, so nothing it holds is out of sight for long.
class _Tray extends StatelessWidget {
  const _Tray({
    required this.stickers,
    required this.open,
    required this.openWidth,
    required this.onToggle,
    required this.onPlace,
  });

  final List<Sticker> stickers;
  final bool open;

  /// Width when folded out, tab included.
  final double openWidth;

  final VoidCallback onToggle;
  final ValueChanged<Sticker> onPlace;

  static const double _tabWidth = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final tab = Semantics(
      button: true,
      label: open ? l10n.stickerTrayHide : l10n.stickerTrayShow,
      excludeSemantics: true,
      child: Tooltip(
        message: open ? l10n.stickerTrayHide : l10n.stickerTrayShow,
        child: InkWell(
          onTap: onToggle,
          child: SizedBox(
            width: _tabWidth,
            height: 56,
            child: Center(
              child: Badge(
                isLabelVisible: !open && stickers.isNotEmpty,
                label: Text('${stickers.length}'),
                child: Icon(
                  open ? AppIcons.chevronRight : AppIcons.chevronLeft,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final content = SizedBox(
      width: (openWidth - _tabWidth).clamp(0.0, double.infinity),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              stickers.isEmpty ? l10n.stickerBoardHint : l10n.stickerBoardAdd,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (stickers.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: stickers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final sticker = stickers[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onPlace(sticker),
                      child: Image.asset(
                        sticker.imageAsset,
                        width: 56,
                        height: 56,
                        cacheWidth: 168,
                        errorBuilder:
                            (context, _, _) =>
                                const SizedBox.square(dimension: 56),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.94),
      // Rounded only where it is free; the right side is the screen's edge.
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [tab, if (open) content],
        ),
      ),
    );
  }
}
