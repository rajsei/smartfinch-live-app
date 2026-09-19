// =============================================================================
// StillPossibleCard — what is left today (HOME-06)
// =============================================================================
//
// The specification calls this the single best lever for daily return *without
// a push notification*, and the second half is the design. Nothing here goes
// looking for a child; the card is what they find when they open the app on
// their own, and it answers one question: is there anything left worth going
// outside for?
//
// The rule it draws is in `still_possible.dart` — today, possible at this
// hour, at most two. What is left here is where it sits and how loud it is.
//
// ### Directly above the Live tile, and quieter than it
//
// It is a suggestion, not the instruction. The Live tile stays the one filled
// primary-coloured thing on the screen; this is a low box above it, so the
// reading order runs *here is something open* → *here is the button that does
// it*. A child who ignores it loses nothing, and a child who reads it already
// has their thumb next to the answer.
//
// ### One line, because it is standing on the tiles' ground
//
// The home screen has no spare height on a small phone: everything this card
// takes comes out of the space the destinations need, and `KID-04` says every
// one of those is one tap away. So the card is a single wrapped line — the
// heading and the badge names, nothing else. What each badge *requires* is in
// the Points area, one tap away in the same panel, and a child who wants a
// name explained has somewhere to go for it.
//
// When there is nothing to suggest — everything earned, or too late in the day
// for what is left — the card is absent rather than empty. An encouraging
// placeholder would make it furniture, and furniture is not read.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../points/points_providers.dart';
import '../../points/points_screen.dart' show badgeName;

/// The one or two badges still open today (`HOME-06`).
class StillPossibleCard extends ConsumerWidget {
  const StillPossibleCard({super.key, this.dense = false});

  /// One suggestion instead of two, for a screen with no height to spare.
  ///
  /// `HOME-06` asks for one *or* two, so the short screen gets the shorter of
  /// the two forms rather than a squeezed version of the longer one.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No spinner and no error state: this is a suggestion. While the database
    // is opening, or if it refuses to, the home screen is one box shorter and
    // nothing else changes.
    final open = ref.watch(stillPossibleProvider).value ?? const [];
    if (open.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final shown = dense ? open.take(1) : open;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      // The gap to the Live tile is the card's own bottom margin, so on a day
      // with nothing to say it costs no space at all.
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            l10n.homeStillPossibleTitle,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          for (final badge in shown)
            Text(
              '${badge.emoji} ${badgeName(l10n, badge.key)}',
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }
}
