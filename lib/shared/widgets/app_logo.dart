// =============================================================================
// AppLogo — the bird, in the language it is being read in
// =============================================================================
//
// The app has two names. In German it is **Schlaumeise** — a tit, and a pun on
// *Schlaumeier* that only works in German; everywhere else it is
// **Smartfinch**. They are not translations of one another and they are not
// the same bird, so the logo cannot be one file with the wordmark swapped.
//
// Two artworks, then, chosen the way every other string is: by the locale the
// interface is running in. `l10n.appTitle` says the same thing in text, and
// both read from the same switch so the picture and the caption can never
// disagree.
//
// SVG rather than PNG: these are drawn at 40 logical pixels in a settings row
// and at 112 on the onboarding card, and a raster asset would have to ship at
// the larger size to survive the larger use. The launcher icon is a separate
// problem — the platform wants raster there, and that file is still the old
// one.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which artwork a locale gets.
///
/// Only the variants **both** brands have. A style one of them is missing
/// would render for a Czech child and throw for a German one, and the
/// difference would not show up until somebody set the phone to German.
/// (`smartfinch_logo_full.svg` — the bird-plus-wordmark lock-up — is in the
/// tree; its Schlaumeise counterpart is not, so neither is offered.)
enum AppLogoStyle {
  /// The round mark on its own, transparent behind it.
  round,

  /// The round mark on its own solid ground — for placing on a photo, a
  /// coloured block, or anything else it must stay legible against.
  roundOnSolid,
}

/// The app's logo for [style], in the language the interface is running in.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.style = AppLogoStyle.round,
    required this.size,
    this.semanticLabel,
  });

  final AppLogoStyle style;

  /// Width and height; the marks are square.
  final double size;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetFor(Localizations.localeOf(context).languageCode, style),
      width: size,
      height: size,
      semanticsLabel: semanticLabel,
    );
  }

  /// The asset a language code and [style] resolve to.
  ///
  /// Public and pure, so a test can assert the German/rest split without
  /// pumping a widget or loading an SVG.
  static String assetFor(String languageCode, AppLogoStyle style) {
    final brand =
        languageCode.toLowerCase() == 'de' ? 'schlaumeise' : 'smartfinch';
    final variant = switch (style) {
      AppLogoStyle.round => 'round',
      AppLogoStyle.roundOnSolid => 'round_solidbg',
    };
    return 'assets/images/${brand}_logo_$variant.svg';
  }
}
