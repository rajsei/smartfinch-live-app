import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../core/theme/app_theme.dart';
import '../about/about_screen.dart';
import '../explore/explore_providers.dart';
import '../scoring/scoring_providers.dart';
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
// the status-bar inset plus a fixed content height — and the panel takes the
// rest. Both numbers are exact, and the panel keeps its height while it moves,
// so nothing re-lays-out mid-animation.
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
  static const double headerHeight = 200;

  /// How much of the panel stays on screen when it is down.
  static const double handleHeight = 56;

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

          // Clamped, so a very short screen still leaves the panel room to be
          // a panel rather than a strip with three tiles in it.
          final openTop = (topInset + _PortraitHomeLayout.headerHeight).clamp(
            0.0,
            height * 0.55,
          );
          final closedTop = height - _PortraitHomeLayout.handleHeight;

          return Stack(
            children: [
              Positioned(
                top: topInset,
                left: 0,
                right: 0,
                height: (openTop - topInset).clamp(0.0, height),
                // Scrollable rather than clipped: on a short screen the clamp
                // above can hand the header less than its content wants, and
                // scrolling is the graceful answer to that.
                child: const SingleChildScrollView(child: HomeHeader()),
              ),

              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                top: _down ? closedTop : openTop,
                left: 0,
                right: 0,
                // A fixed height rather than `bottom: 0`: the panel keeps its
                // layout while it slides, so the tiles do not reflow on every
                // frame of the animation.
                height: height - openTop,
                child: _TilePanel(
                  l10n: widget.l10n,
                  theme: theme,
                  isTablet: widget.isTablet,
                  isDown: _down,
                  onToggle: () => setState(() => _down = !_down),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The lower half: a handle, the tiles, the footer.
class _TilePanel extends StatelessWidget {
  const _TilePanel({
    required this.l10n,
    required this.theme,
    required this.isTablet,
    required this.isDown,
    required this.onToggle,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;
  final bool isDown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: Column(
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
              child: SizedBox(
                height: 24,
                child: Center(
                  child: Container(
                    width: 44,
                    height: 5,
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
          // Scrollable, so a small phone scrolls the tiles rather than losing
          // the bottom row off the edge — which is what the first attempt did,
          // and on screen it looked as though the app had stopped drawing.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HomeTiles(isTablet: isTablet),
                  const SizedBox(height: 12),
                  _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
                  const SizedBox(height: 20),
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
// ### Why 2 : 3
//
// The header's width need is close to fixed: a 52-pixel bird, a gap, and a
// six-figure number beside it. The tiles are the half that *uses* extra width —
// Live is a wide primary tile and the rest sit in one row beneath it. So the
// header takes the smaller share and the navigation takes the rest.
//
// ### No handle here
//
// The panel does not slide sideways. In portrait pulling it down frees the
// screen for something — today the header, later the diorama of unlocked birds
// — and there is no such thing to free here: the header is already beside it,
// not behind it. A gesture that only half-matched the other orientation would
// be worse than none.
class _LandscapeHomeLayout extends ConsumerWidget {
  const _LandscapeHomeLayout({
    required this.l10n,
    required this.theme,
    this.isTablet = false,
  });

  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        right: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 2,
              child: Center(
                // Scrollable for the same reason it is in portrait: a short
                // landscape phone can have less height than the header wants,
                // and scrolling is the graceful answer to that.
                child: SingleChildScrollView(
                  child: HomeHeader(compact: !isTablet),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Material(
                color: theme.colorScheme.surface,
                // The rounded edge faces the header, as the top edge does in
                // portrait: one shape, rotated with the layout.
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  left: false,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 14),
                    child: Column(
                      children: [
                        HomeTiles(isTablet: isTablet, compact: true),
                        SizedBox(height: isTablet ? 20 : 14),
                        _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
                      ],
                    ),
                  ),
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
