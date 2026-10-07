import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../core/theme/app_theme.dart';
import '../about/about_screen.dart';
import '../explore/explore_providers.dart';
import '../scoring/scoring_providers.dart';
import '../stickers/sticker_board.dart';
import '../stickers/widgets/sticker_album_button.dart';
import '../stickers/widgets/sticker_board_layer.dart';
import '../live/live_providers.dart';
import '../../shared/providers/settings_providers.dart';
import 'help_screen.dart';
import 'widgets/home_header.dart';
import 'widgets/home_tiles.dart';

// =============================================================================
// Home Screen — Main Menu
// =============================================================================
//
// Top to bottom (HOME-01, HOME-02, HOME-04, HOME-08):
//   • App logo + title
//   • Star header: total, last 30 days, today
//   • One large Live tile, then equal secondary tiles
//   • Help and About in the footer
//
// The 2×2 mode carousel is gone. It made sense when there were six modes; 0.3
// deleted five of them and left a carousel of one card with two page-indicator
// dots underneath. What replaces it says the same thing the app does: there is
// exactly one thing you are meant to do, and it is listen.
// =============================================================================

/// Main menu screen — entry point after onboarding.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_warmUpApp());
    });
  }

  Future<void> _warmUpApp() async {
    // Nothing here is on the critical path for what the user sees, and
    // nothing gates it any more: the logo precache that used to run first went
    // with the logo, which the two-tone header does not carry.
    //
    // Riverpod caches these results, so opening Live Mode (or another feature)
    // reuses work that has already completed instead of redoing it — and
    // nothing here is awaited, so the menu stays interactive throughout.
    //
    // loadModel() decides for itself whether there is anything to do: it joins
    // a load already in flight, no-ops once the model is ready or a session is
    // running, and retries after a failure. The menu does not second-guess it.
    unawaited(ref.read(liveControllerProvider).loadModel());

    _preload(ref.read(taxonomyServiceProvider.future), 'taxonomy');
    _preload(ref.read(audioLabelsSetProvider.future), 'audio labels');
    _preload(ref.read(geoModelProvider.future), 'geo model');
    unawaited(_warmUpLocation());
    unawaited(_runClipRetention());
  }

  /// Trims the audio clips once per app start (`SET-12`).
  ///
  /// Here rather than on a timer or after every detection: nothing about it is
  /// urgent, and a clean-up competing with inference for the disk is one that
  /// drops frames during a live session (`NFA-13`). Failures are logged and
  /// dropped — a clip that could not be removed keeps its row, so the next run
  /// tries again rather than losing track of the file.
  Future<void> _runClipRetention() async {
    try {
      final result = await ref.read(clipRetentionJobProvider).run();
      if (!result.didNothing) {
        debugPrint(
          '[HomeScreen] clip retention: ${result.deleted} removed, '
          '${result.failed} failed',
        );
      }
    } catch (error) {
      debugPrint('[HomeScreen] clip retention failed: $error');
    }
  }

  /// Warm the location up only when doing so is free.
  ///
  /// With GPS off the provider just echoes the manual coordinates.  With GPS
  /// on it calls through to `getCurrentLocation()`, which *requests* the
  /// permission if it has not been granted yet — so without this guard a user
  /// who skipped the location step during onboarding would be met by the OS
  /// location prompt on the main menu, out of any context that explains it.
  /// Leave that first request to the screen that actually needs a fix.
  Future<void> _warmUpLocation() async {
    if (ref.read(useGpsProvider)) {
      final granted = await ref.read(locationServiceProvider).hasPermission();
      if (!granted || !mounted) return;
    }
    _preload(ref.read(currentLocationProvider.future), 'location');
  }

  /// Let a warm-up run to completion in the background, logging rather than
  /// surfacing failures — a warm-up is an optimisation, and the screen that
  /// really needs the value will report the error itself.
  void _preload<T>(Future<T> future, String label) {
    unawaited(() async {
      try {
        await future;
      } catch (error) {
        debugPrint('[HomeScreen] $label warm-up failed: $error');
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;

    // Both layouts take the whole box and do their own scrolling inside it:
    // each is a Stack or a Row of full-height columns, and neither survives
    // being handed the unbounded height a scroll view would give it.
    return Scaffold(
      body:
          isLandscape
              ? _LandscapeHomeLayout(
                l10n: l10n,
                theme: theme,
                isTablet: isTablet,
              )
              : _PortraitHomeLayout(
                l10n: l10n,
                theme: theme,
                isTablet: isTablet,
              ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Portrait Layout — two-tone: a coloured top, a panel of tiles below
// ─────────────────────────────────────────────────────────────────────────────
//
// A block of `primaryContainer` at the top carrying the avatar and the star
// figures (`HOME-07`, `HOME-01`, `HOME-02`), and a `surface`-coloured panel
// below carrying the tile navigation (`HOME-04`, `HOME-08`). Both colours come
// from `ColorScheme`, so the layout follows light/dark/dynamic-colour/
// high-contrast the way the rest of the app does, and nothing here commits to
// a palette that was explicitly not settled.
//
// ### Why this is arithmetic and not a DraggableScrollableSheet
//
// It was one, and it did not work. That widget sizes itself in *fractions of
// its parent*, which is right for a modal over a finished screen and wrong for
// a panel that has to leave a particular header visible: the fraction and the
// header's real height are unrelated numbers, and when they disagree the panel
// covers the header and clips its own contents. On a phone it opened over the
// star figures and cut the tiles off mid-row.
//
// So the split is computed instead. The header gets what its content needs —
// the status-bar inset plus a fixed content height — and the panel takes **as
// much of the rest as its own content needs**, no more.
//
// That last part matters. The panel used to take the whole remainder and push
// its contents to the bottom of it, which meant the surface-coloured block ran
// up behind an empty region that belonged to nothing. Sizing it to its content
// puts that region back on the coloured side, where the sketch wanted it: the
// space above the panel is the diorama's, not dead surface inside the panel.
// The cap is still the old number, so the panel never grows past where it used
// to start, and when the content is taller than that it scrolls.
//
// ### The panel still pulls down, and that is the load-bearing part
//
// The one piece the sketch marked as meant to survive: the lower area drops to
// a handle at the screen's edge and frees the space above it. Today that space
// is the header; later it is where a child arranges the birds their level has
// unlocked, before pulling the panel back up.
//
// Not a hidden gesture: the handle is visible, it is a **tap target as well as
// a drag** — a child who never discovers the drag can still press it — there
// are two positions rather than a free float, and every destination is one tap
// away in the default position (`KID-04`).
class _PortraitHomeLayout extends ConsumerStatefulWidget {
  const _PortraitHomeLayout({
    required this.l10n,
    required this.theme,
    this.isTablet = false,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;

  /// What the header needs below the status bar: the avatar row with the
  /// figures beside it, and the level line with its bar.
  ///
  /// A tablet gets more, and the header's contents grow to use it — otherwise
  /// the extra height on a 1,280-pixel screen turns into a band of empty
  /// colour above a block of empty surface.
  ///
  /// Plus the sticker album button under the level bar (`AVA-07`) when the
  /// screen is tall enough to carry it there — see [albumButtonInHeaderFrom].
  ///
  /// ⚠️ The +23 is not decoration. The header used to sit in a
  /// `SingleChildScrollView`, which absorbed a 23-pixel shortfall between this
  /// budget and what the header's own content actually needs — invisibly,
  /// since nothing here ever suggested it could scroll. The header is fixed
  /// now, on purpose: it is the one block on this screen a child must always
  /// see in full. Recalibrate this number (against `HomeHeader`'s own layout,
  /// not against a guess) if its content ever changes shape again.
  ///
  /// Last measured with the "Today" label under the sparkline (`HOME-05`),
  /// which added 18: a phone header's content is 237, a tablet's 300. The
  /// phone keeps the 4 it had to spare, and needs them — the album button
  /// below is 44 by [StickerAlbumButton.heightFor] but 48 on screen, padded
  /// to Material's tap target.
  static double headerHeight({
    required bool isTablet,
    bool dense = false,
    bool withAlbumButton = true,
  }) =>
      (isTablet ? 323 : (dense ? 184 : 241)) +
      (withAlbumButton
          ? stickerButtonGap(large: isTablet) +
              StickerAlbumButton.heightFor(large: isTablet)
          : 0);

  /// From this height on, the sticker album button sits in the header,
  /// always visible (`AVA-07`).
  ///
  /// Below it, a 48-dp button row would push the last row of destinations
  /// below the fold, and `KID-04` wins: the button moves behind the panel —
  /// under the level bar still, visible when the panel is pulled down — and an
  /// open pick is announced in the panel instead (`StickerPickCard`). Measured
  /// against the tiles as they are: a 360 × 720 phone needs 784 to fit both.
  static const double albumButtonInHeaderFrom = 784;

  /// How much of the panel stays on screen when it is down.
  ///
  /// Comfortably more than the handle's own tap target, so what is left at the
  /// edge reads as the top of a panel rather than as a stray grab bar.
  static const double handleHeight = 64;

  /// Space between the header's last line and the top of the sticker board.
  static const double boardGap = 4;

  /// Below this the screen cannot carry everything at full size.
  ///
  /// The header and the panel are both sized from the same fixed budget, so on
  /// a short phone the sparkline comes straight out of the room the
  /// destinations need. `KID-04` wins that argument: below this height the
  /// sparkline is not drawn and the tiles tighten, rather than a tile being
  /// pushed below the fold.
  static const double denseBelow = 720;

  @override
  ConsumerState<_PortraitHomeLayout> createState() =>
      _PortraitHomeLayoutState();
}

class _PortraitHomeLayoutState extends ConsumerState<_PortraitHomeLayout> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;

          final dense = height < _PortraitHomeLayout.denseBelow;
          final albumInHeader =
              widget.isTablet ||
              height >= _PortraitHomeLayout.albumButtonInHeaderFrom;

          // Where the header stops, and so the highest the panel may reach.
          // Clamped, so a very short screen still leaves the panel room to be
          // a panel rather than a strip with three tiles in it.
          final headerBottom = (topInset +
                  _PortraitHomeLayout.headerHeight(
                    isTablet: widget.isTablet,
                    dense: dense,
                    withAlbumButton: albumInHeader,
                  ))
              .clamp(0.0, height * 0.55);

          // The sticker board (`AVA-07`): from just under the header's last
          // line — its bottom margin is margin, not content — down to the top
          // of the handle the lowered panel leaves on screen. The same box in
          // both states, because positions are fractions of it: a box that
          // changed size with the panel would move every sticker.
          final boardTop =
              headerBottom -
              HomeHeader.bottomPadding(large: widget.isTablet) +
              _PortraitHomeLayout.boardGap;
          Widget board({required bool editable}) => Positioned(
            top: boardTop,
            left: 0,
            right: 0,
            bottom: _PortraitHomeLayout.handleHeight,
            child: StickerBoardLayer(
              layout: StickerLayout.portrait,
              editable: editable,
            ),
          );

          return Stack(
            children: [
              // Never under the header: the star/level/avatar block is a
              // fixed reference a child can always read in full. Behind the
              // panel while it is up; arrangeable while it is down.
              if (!_down) board(editable: false),

              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                height: (headerBottom - topInset).clamp(0.0, height),
                // Fixed, not scrollable: this block is the one thing on the
                // screen a child must always see in full. Clipped rather than
                // left to overflow, for the rare case — a large system text
                // scale — where its content still asks for more than the
                // budget above gives it.
                child: ClipRect(
                  child: HomeHeader(
                    large: widget.isTablet,
                    dense: dense,
                    showAlbumButton: albumInHeader,
                  ),
                ),
              ),

              if (_down) board(editable: true),

              // On a short phone the album button waits behind the panel,
              // still under the level bar, and shows when it is pulled down.
              if (!albumInHeader)
                Positioned(
                  top: headerBottom + stickerButtonGap(),
                  left: 0,
                  right: 0,
                  child: StickerAlbumButton(
                    ink: theme.colorScheme.onPrimaryContainer,
                  ),
                ),

              // Laid out rather than positioned, because the number that
              // decides where the panel starts is its own content height —
              // which only the layout pass knows. The delegate asks for it,
              // then puts the panel at the bottom of the screen; sliding down
              // is the same delegate with the target moved, so the panel keeps
              // its layout while it moves and nothing reflows mid-animation.
              Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: _down ? 1 : 0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, slide, child) {
                    return CustomSingleChildLayout(
                      delegate: _PanelPosition(
                        maxHeight: height - headerBottom,
                        peek: _PortraitHomeLayout.handleHeight,
                        slide: slide,
                      ),
                      child: child,
                    );
                  },
                  child: _TilePanel(
                    l10n: widget.l10n,
                    theme: theme,
                    isTablet: widget.isTablet,
                    dense: dense,
                    stickerCard: !albumInHeader,
                    isDown: _down,
                    onToggle: () => setState(() => _down = !_down),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Sizes the panel to its content and parks it at the bottom edge.
///
/// [slide] runs 0 (open, sitting on the bottom of the screen) to 1 (down, with
/// only [peek] of it left). Both ends are computed from the panel's measured
/// height, which is the whole reason this is a layout delegate and not an
/// `AnimatedPositioned`: a `Positioned` has to be told a height, and the only
/// honest answer here is "whatever the tiles come to".
class _PanelPosition extends SingleChildLayoutDelegate {
  const _PanelPosition({
    required this.maxHeight,
    required this.peek,
    required this.slide,
  });

  /// How far up the panel may grow — the header's bottom edge.
  final double maxHeight;

  /// What stays on screen when it is down.
  final double peek;

  final double slide;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    // Full width, and free to be any height up to the header. Loose rather
    // than tight is the point: a tight height is what made the panel bigger
    // than its contents in the first place.
    return BoxConstraints(
      minWidth: constraints.maxWidth,
      maxWidth: constraints.maxWidth,
      maxHeight: maxHeight,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final open = size.height - childSize.height;
    final down = size.height - peek;
    return Offset(0, lerpDouble(open, down, slide)!);
  }

  @override
  bool shouldRelayout(_PanelPosition old) =>
      old.maxHeight != maxHeight || old.peek != peek || old.slide != slide;
}

/// The lower half: a handle, the tiles, the footer.
class _TilePanel extends StatelessWidget {
  const _TilePanel({
    required this.l10n,
    required this.theme,
    required this.isTablet,
    required this.dense,
    required this.isDown,
    required this.onToggle,
    this.stickerCard = false,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;
  final bool dense;

  /// Announce an open sticker pick above the Live tile, because the album
  /// button is behind the panel on this screen.
  final bool stickerCard;
  final bool isDown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        // The panel is as tall as what is in it; the delegate above puts it at
        // the bottom edge. Nothing here stretches to fill a box any more.
        mainAxisSize: MainAxisSize.min,
        children: [
          // Visible, tappable and draggable. A gesture nobody can see is a
          // gesture a child does not have (KID-04), so the handle answers to a
          // press as well as to a drag.
          Semantics(
            button: true,
            label: l10n.homePanelHandleA11y,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 100 && !isDown) onToggle();
                if (velocity < -100 && isDown) onToggle();
              },
              // A band, not a bar. The grip is drawn small because a big one
              // would be furniture, but a child aiming at five pixels with a
              // thumb misses — so the thing that answers is the full width and
              // comfortably past the 48-pixel target the rest of the app uses.
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: Center(
                  child: Container(
                    width: 52,
                    height: 6,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // `Flexible`, not `Expanded`: the tiles get the height they ask for
          // and the panel ends there. Only when they ask for more than the
          // header leaves — a short phone, or large text — does the cap bite,
          // and then this scrolls rather than pushing a destination off the
          // edge (`KID-04`).
          //
          // There is no alignment to choose any more. Bottom-on-a-phone and
          // centred-on-a-tablet were two ways of spending slack inside a panel
          // that was bigger than its contents; there is no slack to spend now,
          // and the room that used to be it is the coloured block above, which
          // is where the sketch put the diorama of unlocked birds.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HomeTiles(
                    isTablet: isTablet,
                    dense: dense,
                    stickerCard: stickerCard,
                  ),
                  SizedBox(height: isTablet ? 20 : 14),
                  _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
                  SizedBox(height: isTablet ? 28 : 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Landscape Layout — the same two tones, turned ninety degrees
// ─────────────────────────────────────────────────────────────────────────────
//
// Portrait splits the screen top and bottom because that is where the room is.
// Held sideways a phone has the opposite problem — plenty of width, barely any
// height — so the same two blocks stand side by side instead: the coloured one
// on the left with the bird and the figures, the surface one on the right with
// the tiles.
//
// **It is the same `HomeHeader`.** Not a landscape arrangement of the same
// numbers — the identical widget, so the star display with its rules is the
// one a child already knows and the two orientations cannot drift into showing
// different things.
//
// ### Why 2 : 5
//
// The header's width need is close to fixed: a 52-pixel bird, a gap, and a
// six-figure number beside it. The tiles are the half that *uses* extra width —
// Live is a wide primary tile and the rest sit in one row beneath it. So the
// header takes the smaller share and the navigation takes the rest.
//
// ### The panel pushes right — the mirror of pulling down (`AVA-07`)
//
// Portrait frees room for stickers by pulling the panel *down*; sideways the
// room to free is *beside* the panel, not above it, so the panel slides
// *right* instead — the same handle, the same two positions, the same "a tap
// or a drag" rule, turned ninety degrees. Docked (the resting position), it
// covers the whole width the header does not need, exactly as it always did
// before stickers existed. Pushed, only [handleWidth] stays on screen and the
// strip it uncovers — always to the right of the header, never under it —
// is where stickers can be arranged.
class _LandscapeHomeLayout extends ConsumerStatefulWidget {
  const _LandscapeHomeLayout({
    required this.l10n,
    required this.theme,
    this.isTablet = false,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;

  /// What stays on screen when the panel is pushed right — the mirror of
  /// [_PortraitHomeLayout.handleHeight].
  static const double handleWidth = 64;

  @override
  ConsumerState<_LandscapeHomeLayout> createState() =>
      _LandscapeHomeLayoutState();
}

class _LandscapeHomeLayoutState extends ConsumerState<_LandscapeHomeLayout> {
  bool _pushed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;

    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // The header's own share never changes; only the panel moves.
          final headerWidth = width * 2 / 5;
          final panelWidth = width - headerWidth;

          return Stack(
            children: [
              // The child's stickers (`AVA-07`), confined to the strip the
              // panel occupies — never under the header — and hidden behind
              // the panel until it is pushed aside.
              // Up to the handle the pushed panel leaves on screen, in both
              // states — one box, so no sticker moves when the panel does.
              if (!_pushed)
                Positioned(
                  left: headerWidth,
                  right: _LandscapeHomeLayout.handleWidth,
                  top: 0,
                  bottom: 0,
                  child: const StickerBoardLayer(
                    layout: StickerLayout.landscape,
                  ),
                ),

              // ⚠️ Positioned, like every other child here. A Stack sizes
              // itself to its non-positioned children, and a header left
              // unpositioned made the whole Stack 2/5 of the screen wide —
              // which clipped the panel, positioned beyond that edge, clean
              // off the screen and out of reach of every tap.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: headerWidth,
                child: SafeArea(
                  right: false,
                  child: Center(
                    child: ClipRect(
                      child: HomeHeader(compact: !widget.isTablet),
                    ),
                  ),
                ),
              ),

              if (_pushed)
                Positioned(
                  left: headerWidth,
                  right: _LandscapeHomeLayout.handleWidth,
                  top: 0,
                  bottom: 0,
                  child: const StickerBoardLayer(
                    layout: StickerLayout.landscape,
                    editable: true,
                  ),
                ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                left:
                    _pushed
                        ? width - _LandscapeHomeLayout.handleWidth
                        : headerWidth,
                top: 0,
                bottom: 0,
                width: panelWidth,
                child: _TilePanelLandscape(
                  l10n: widget.l10n,
                  theme: theme,
                  isTablet: widget.isTablet,
                  isPushed: _pushed,
                  onToggle: () => setState(() => _pushed = !_pushed),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The right-hand panel: a handle on its leading edge, the tiles, the footer.
///
/// [_TilePanel]'s mirror image. The handle moves from the top edge to the
/// left one, and answers to a horizontal drag instead of a vertical one;
/// everything else — visible and tappable, two positions, every destination
/// reachable at rest (`KID-04`) — is the same rule, turned.
class _TilePanelLandscape extends StatelessWidget {
  const _TilePanelLandscape({
    required this.l10n,
    required this.theme,
    required this.isTablet,
    required this.isPushed,
    required this.onToggle,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;
  final bool isPushed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surface,
      // The rounded edge faces the header, as the top edge does in portrait:
      // one shape, rotated with the layout. Which side it faces does not
      // change with the push — the panel's own leading edge is always here.
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        left: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Visible, tappable and draggable — the same KID-04 reasoning as
            // the horizontal handle in portrait, turned vertical.
            Semantics(
              button: true,
              label: l10n.homePanelHandleLandscapeA11y,
              child: GestureDetector(
                key: const ValueKey('landscape_panel_handle'),
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 100 && !isPushed) onToggle();
                  if (velocity < -100 && isPushed) onToggle();
                },
                child: SizedBox(
                  width: 48,
                  child: Center(
                    child: Container(
                      width: 6,
                      height: 52,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 14),
                child: Column(
                  children: [
                    // Sideways the scarce dimension is height, so the tiles
                    // take their tighter form on a phone and their full one
                    // on a tablet.
                    HomeTiles(
                      isTablet: isTablet,
                      compact: true,
                      dense: !isTablet,
                    ),
                    SizedBox(height: isTablet ? 20 : 14),
                    _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.l10n,
    required this.theme,
    this.isTablet = false,
  });
  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    final highContrast = AppTheme.isHighContrastTheme(theme);
    final color =
        highContrast
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurface.withAlpha(153);
    final fontSize = isTablet ? 16.0 : 14.0;
    // Journal, Explore and Settings moved up into the tile grid (HOME-04).
    // What is left here is what a child never needs and a parent needs once.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: isTablet ? 12 : 6,
      runSpacing: isTablet ? 6 : 4,
      children: [
        _FooterButton(
          icon: AppIcons.helpOutlineRounded,
          label: l10n.helpTitle,
          color: color,
          fontSize: fontSize,
          isTablet: isTablet,
          onPressed:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
              ),
        ),
        _FooterButton(
          icon: AppIcons.infoOutline,
          label: l10n.about,
          color: color,
          fontSize: fontSize,
          isTablet: isTablet,
          onPressed:
              () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
              ),
        ),
      ],
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    required this.fontSize,
    this.isTablet = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;
  final double fontSize;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: isTablet ? 24 : 20, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: fontSize)),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 12 : 8,
          vertical: isTablet ? 10 : 8,
        ),
        minimumSize: Size(isTablet ? 76 : 64, isTablet ? 48 : 44),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
      ),
    );
  }
}
