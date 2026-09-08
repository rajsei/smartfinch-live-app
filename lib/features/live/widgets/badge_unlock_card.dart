// =============================================================================
// BadgeUnlockCard — the moment a badge is earned (AUS-08)
// =============================================================================
//
// Deliberately the same shape as the first-find card: a bottom sheet, capped
// in time, going through the same queue (`LIVE-07`). A child should not have
// to learn two different ways of being congratulated, and the two must never
// be on screen at once.
//
// It says **what was earned and why**. "🌅 The early bird — heard something
// before 9 in the morning" teaches the rule in the moment it was satisfied,
// which is the one moment a child is guaranteed to be paying attention. A card
// showing only an emoji would be a reward with nothing to learn from.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../points/points_models.dart';
import '../../points/points_screen.dart';

/// "🌅 Badge earned!" — one card, however many badges landed together.
class BadgeUnlockCard extends StatefulWidget {
  const BadgeUnlockCard({super.key, required this.badges});

  final List<BadgeDefinition> badges;

  /// How long the sheet stays up before dismissing itself.
  ///
  /// Shorter than the first-find card's six seconds: there is less to read,
  /// and a child in the middle of a walk should get their screen back.
  static const Duration visibleFor = Duration(seconds: 5);

  /// Shows the sheet and completes when it has gone away.
  static Future<void> show(BuildContext context, List<BadgeDefinition> badges) {
    if (badges.isEmpty) return Future.value();

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => BadgeUnlockCard(badges: badges),
    );
  }

  @override
  State<BadgeUnlockCard> createState() => _BadgeUnlockCardState();
}

class _BadgeUnlockCardState extends State<BadgeUnlockCard> {
  Timer? _dismiss;

  @override
  void initState() {
    super.initState();
    // A cancellable timer rather than a bare `Future.delayed`: the sheet can
    // be swiped away, and a pending callback that outlived it would try to
    // pop a route that is already gone.
    _dismiss = Timer(BadgeUnlockCard.visibleFor, () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.badges.length == 1
                  ? l10n.badgeUnlockedTitle
                  : l10n.badgeUnlockedTitleMany(widget.badges.length),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            for (final badge in widget.badges)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Text(badge.emoji, style: theme.textTheme.displaySmall),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badgeName(l10n, badge.key),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          // The rule, in the one moment a child is certain to
                          // be reading.
                          Text(
                            badgeCondition(l10n, badge.key),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
