import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../core/theme/app_theme.dart';
import '../about/about_screen.dart';
import '../explore/explore_providers.dart';
import '../live/live_providers.dart';
import '../../shared/providers/settings_providers.dart';
import 'help_screen.dart';
import 'widgets/home_tiles.dart';
import 'widgets/star_header.dart';

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

/// The app logo, decoded to the largest size it is ever drawn at (160 logical
/// px on a tablet, ×3 for common high-density screens) instead of its full
/// 891×891 source, reducing decode work and the image-cache footprint.
///
/// Shared by the header and by the warm-up's precache so both resolve to the
/// same image-cache entry; `ResizeImage` is part of the cache key, so a plain
/// `AssetImage` here would miss.
const ImageProvider _appLogoImage = ResizeImage(
  AssetImage('assets/images/app-icon.png'),
  width: 480,
  height: 480,
);

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
    // Let the logo finish decoding before any of this starts. The first frame
    // paints without it — an asset image is never ready that early — and its
    // decode finishes on a *later* main-isolate turn, so a warm-up that grabs
    // the isolate first leaves the header visibly logo-less for as long as it
    // holds on. Nothing below is on the critical path for what the user sees.
    await _precacheLogo();
    if (!mounted) return;

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
  }

  /// Decode the logo into the image cache, so the header can paint it on the
  /// next frame.
  ///
  /// Bounded, and failures are swallowed: this gates every other warm-up, and
  /// a logo that never resolves must not be able to leave the model unloaded.
  Future<void> _precacheLogo() async {
    try {
      await precacheImage(
        _appLogoImage,
        context,
      ).timeout(const Duration(seconds: 2));
    } catch (error) {
      debugPrint('[HomeScreen] logo precache failed: $error');
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

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal:
                    isLandscape ? (isTablet ? 64 : 48) : (isTablet ? 40 : 24),
                vertical: isLandscape ? 12 : 0,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child:
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
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Portrait Layout — Original vertical arrangement
// ─────────────────────────────────────────────────────────────────────────────

class _PortraitHomeLayout extends ConsumerWidget {
  const _PortraitHomeLayout({
    required this.l10n,
    required this.theme,
    this.isTablet = false,
  });
  final AppLocalizations l10n;
  final ThemeData theme;
  final bool isTablet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(height: 24),
        _LogoHeader(l10n: l10n, theme: theme, isTablet: isTablet),
        const SizedBox(height: 16),
        // Above the tiles: the first thing a child looks at is what they have,
        // and the second is the button that makes it grow (HOME-01, HOME-08).
        const StarHeader(),
        const SizedBox(height: 20),
        HomeTiles(isTablet: isTablet),
        const SizedBox(height: 12),
        _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Landscape Layout — Logo + title left, grid + footer right
// ─────────────────────────────────────────────────────────────────────────────

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
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        SizedBox(height: isTablet ? 14 : 8),
        // ── Compact single-row logo + title header, pinned left ──
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
            child: _LogoHeader(
              l10n: l10n,
              theme: theme,
              compact: true,
              isTablet: isTablet,
            ),
          ),
        ),
        SizedBox(height: isTablet ? 16 : 12),
        const StarHeader(compact: true),
        SizedBox(height: isTablet ? 20 : 14),
        HomeTiles(isTablet: isTablet, compact: true),
        SizedBox(height: isTablet ? 24 : 18),
        SizedBox(
          width: double.infinity,
          child: _Footer(l10n: l10n, theme: theme, isTablet: isTablet),
        ),
        SizedBox(height: isTablet ? 16 : 10),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Header
// ─────────────────────────────────────────────────────────────────────────────

class _LogoHeader extends ConsumerWidget {
  const _LogoHeader({
    required this.l10n,
    required this.theme,
    this.compact = false,
    this.isTablet = false,
  });
  final AppLocalizations l10n;
  final ThemeData theme;
  final bool compact;
  final bool isTablet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final highContrast = AppTheme.isHighContrastTheme(theme);
    final logoSize =
        compact ? (isTablet ? 72.0 : 56.0) : (isTablet ? 160.0 : 120.0);
    final logo = Container(
      width: logoSize,
      height: logoSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (highContrast
                    ? AppTheme.brandPrimaryLight
                    : theme.colorScheme.primary)
                .withAlpha(60),
            blurRadius: compact ? 16 : 32,
            spreadRadius: compact ? 2 : 4,
          ),
        ],
      ),
      child: ClipOval(
        child: Image(
          image: _appLogoImage,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.cover,
        ),
      ),
    );
    final title = Text(
      l10n.appTitle,
      style: (compact
              ? theme.textTheme.headlineSmall
              : theme.textTheme.headlineMedium)
          ?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            fontSize: compact ? (isTablet ? 22 : 20) : (isTablet ? 32 : null),
          ),
      textAlign: compact ? TextAlign.left : TextAlign.center,
    );
    final subtitle = Text(
      l10n.homeSubtitle,
      style: theme.textTheme.bodyMedium?.copyWith(
        color:
            highContrast
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withAlpha(153),
        fontSize: isTablet ? 16 : null,
      ),
      textAlign: compact ? TextAlign.left : TextAlign.center,
    );
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          logo,
          SizedBox(width: isTablet ? 18 : 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 520 : 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 4), subtitle],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        logo,
        SizedBox(height: isTablet ? 28 : 20),
        title,
        const SizedBox(height: 6),
        subtitle,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer — 5 items that wrap naturally
// ─────────────────────────────────────────────────────────────────────────────

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
