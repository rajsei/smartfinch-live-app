// =============================================================================
// Score chips — what a detection card says about points
// =============================================================================
//
// Three small things, and the order of preference between them is the whole
// design (LIVE-02, LIVE-03, LIVE-04):
//
//   `NEW ×3` `⭐ +300`     a first find, with the reason shown before the number
//   `⭐ +50`               an ordinary award
//   `already collected today ✓`  a repeat
//
// **Never just the final number.** A child who sees 300 where they saw 100
// yesterday will decide the app is arbitrary unless the chip says why. That is
// principle 6, and the multiplier chip is the cheapest place to honour it.
//
// **The repeat line is not an error message.** It answers a question a child
// asks out loud — *why didn't I get anything?* — before they ask it, and the ✓
// says the species is safely collected rather than missed.
//
// **Neither is the no-stars line.** The same question has two more answers
// that used to go unsaid: the bird is not expected here this week, so it has
// no rarity level and earns nothing (D20); or the app does not know where it
// is yet. Both left the card blank, and a blank card next to a bird the child
// can hear reads as the app not working. A pause an adult switched on is the
// one case still left blank — the day bar above the list says that once, for
// every card.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../scoring/live_score_board.dart';
import '../../scoring/scoring_engine.dart';
import '../../scoring/scoring_rules.dart';

/// The points half of a detection card.
///
/// Renders nothing at all when the species has no score yet — one still being
/// written — or when scoring is paused for a species not collected today,
/// which the day bar already says. An empty gap is better than a zero: a zero
/// looks like a verdict.
class DetectionScoreChips extends StatelessWidget {
  const DetectionScoreChips({super.key, required this.score});

  final LiveSpeciesScore? score;

  @override
  Widget build(BuildContext context) {
    final value = score;
    if (value == null) return const SizedBox.shrink();

    if (value.isRepeat) return _RepeatChip(hadStars: value.stars > 0);
    if (!value.scored) {
      // Collected earlier today. Whatever stopped this detection, it would
      // have been a repeat anyway, and "already collected ✓" is the truer
      // line — the child does not lose a species they have.
      if (value.stars > 0) return const _RepeatChip(hadStars: true);
      return switch (value.skipReason) {
        ScoringSkipReason.notOnLocalList => const _NoStarsChip(
          reason: ScoringSkipReason.notOnLocalList,
        ),
        ScoringSkipReason.noLocation => const _NoStarsChip(
          reason: ScoringSkipReason.noLocation,
        ),
        _ => const SizedBox.shrink(),
      };
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (value.hasMultiplier) ...[
          _MultiplierChip(multiplier: value.multiplier),
          const SizedBox(width: 4),
        ],
        _StarsChip(stars: value.stars),
      ],
    );
  }
}

/// `⭐ +100` — only ever shown when points were actually awarded (LIVE-02).
class _StarsChip extends StatelessWidget {
  const _StarsChip({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: AppLocalizations.of(context)!.liveStarsEarnedA11y(stars),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '⭐ +$stars',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// `NEW ×3`, `REGULAR ×2` — the reason, not just the result (LIVE-04).
class _MultiplierChip extends StatelessWidget {
  const _MultiplierChip({required this.multiplier});

  final ScoreMultiplier multiplier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final label = switch (multiplier) {
      ScoreMultiplier.firstFind => l10n.multiplierFirstFind,
      ScoreMultiplier.permanentGuest => l10n.multiplierPermanentGuest,
      ScoreMultiplier.regular => l10n.multiplierRegular,
      ScoreMultiplier.yearFirst => l10n.multiplierYearFirst,
      ScoreMultiplier.none => '',
    };
    if (label.isEmpty) return const SizedBox.shrink();

    // A first find is the rarest and the biggest, so it gets the loudest
    // colour; the loyalty multipliers repeat weekly and stay quieter.
    final isFirstFind = multiplier == ScoreMultiplier.firstFind;
    final background =
        isFirstFind
            ? theme.colorScheme.tertiary
            : theme.colorScheme.tertiaryContainer;
    final foreground =
        isFirstFind
            ? theme.colorScheme.onTertiary
            : theme.colorScheme.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label ×${multiplier.factor}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// "already collected today ✓" (LIVE-03).
class _RepeatChip extends StatelessWidget {
  const _RepeatChip({required this.hadStars});

  /// Whether the species actually scored earlier today.
  ///
  /// False when it was heard for the first time while scoring was paused, in
  /// which case saying "already collected" would be a lie.
  final bool hadStars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Text(
      hadStars ? l10n.liveAlreadyCollectedToday : l10n.liveHeardAgain,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Why this bird earned nothing, when the reason is not a pause.
///
/// Quiet on purpose — the neutral surface and the muted text of the repeat
/// chip, not an error colour. Nothing went wrong that the child could have
/// done differently.
class _NoStarsChip extends StatelessWidget {
  const _NoStarsChip({required this.reason});

  final ScoringSkipReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final (label, a11y) = switch (reason) {
      ScoringSkipReason.noLocation => (
        l10n.liveChipNoLocation,
        l10n.liveChipNoLocationA11y,
      ),
      _ => (l10n.liveChipNotExpectedHere, l10n.liveChipNotExpectedHereA11y),
    };

    return Semantics(
      label: a11y,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
