// =============================================================================
// RulesScreen — "How do I earn stars?" (SET-11)
// =============================================================================
//
// Principle 6, made into a screen: *every number is explainable*. A child who
// cannot find out why a robin was worth 300 and a blackbird 50 will decide the
// app is arbitrary, and once they have decided that the whole thing is a
// slot machine with birds in it.
//
// Two things make this page work, and both are easy to lose in a redesign:
//
//   **The numbers come from `ScoringRules`, not from the text.** A rebalance
//   changes one file and this page follows. A page with the numbers typed into
//   its prose would go quietly wrong on the first tuning pass — and be wrong
//   in the one place a child goes to check.
//
//   **"Why do the points change during the year?" is its own section**, which
//   `SET-11` asks for by name. Without it week coupling looks like a bug: the
//   same bird, the same app, a different number. With it, it is the game.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../shared/widgets/content_width_constraint.dart';
import '../inference/geo_abundance.dart';
import '../scoring/scoring_rules.dart';

/// The rules, in the child's own language (`SET-11`).
class RulesScreen extends ConsumerWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    const rules = ScoringRules.current;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rulesTitle)),
      body: ContentWidthConstraint(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            _Section(
              emoji: '⭐',
              title: l10n.rulesHowTitle,
              body: l10n.rulesHowBody,
            ),

            // The ladder, drawn from the rules object rather than written out.
            _TierTable(rules: rules),

            _Section(
              emoji: '1️⃣',
              title: l10n.rulesOncePerDayTitle,
              body: l10n.rulesOncePerDayBody,
            ),
            _Section(
              emoji: '✨',
              title: l10n.rulesMultipliersTitle,
              body: l10n.rulesMultipliersBody,
            ),
            _MultiplierList(rules: rules),

            _Section(
              emoji: '🎁',
              title: l10n.rulesBonusesTitle,
              body: l10n.rulesBonusesBody(
                rules.varietyBonuses.keys.first,
                rules.varietyBonuses.values.first.stars,
              ),
            ),

            // The section SET-11 asks for by name. Without it, week coupling
            // reads as a bug rather than as the game.
            const SizedBox(height: 8),
            _Section(
              emoji: '📅',
              title: l10n.rulesWhyChangeTitle,
              body: l10n.rulesWhyChangeBody,
              highlighted: true,
            ),
            _Section(
              emoji: '📍',
              title: l10n.rulesWhereTitle,
              body: l10n.rulesWhereBody,
              highlighted: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// The six rarity levels and what each is worth (2.3).
class _TierTable extends StatelessWidget {
  const _TierTable({required this.rules});

  final ScoringRules rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Commonest first, which is the order a child meets them in.
    const order = [
      ExploreTier.abundant,
      ExploreTier.common,
      ExploreTier.frequent,
      ExploreTier.uncommon,
      ExploreTier.scarce,
      ExploreTier.rare,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final tier in order)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(_tierLabel(l10n, tier))),
                  Text(
                    '${rules.starsFor(tier)} ⭐',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _tierLabel(AppLocalizations l10n, ExploreTier tier) => switch (tier) {
    ExploreTier.abundant => l10n.rulesTierEverywhere,
    ExploreTier.common => l10n.rulesTierCommon,
    ExploreTier.frequent => l10n.rulesTierRegular,
    ExploreTier.uncommon => l10n.rulesTierUncommon,
    ExploreTier.scarce => l10n.rulesTierScarce,
    ExploreTier.rare => l10n.rulesTierRare,
  };
}

/// The four multipliers, and the rule that only one of them counts.
class _MultiplierList extends StatelessWidget {
  const _MultiplierList({required this.rules});

  final ScoringRules rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final rows = <(String, String, int)>[
      ('🆕', l10n.multiplierFirstFind, ScoreMultiplier.firstFind.factor),
      ('🤝', l10n.multiplierRegular, ScoreMultiplier.regular.factor),
      (
        '🏠',
        l10n.multiplierPermanentGuest,
        ScoreMultiplier.permanentGuest.factor,
      ),
      ('📆', l10n.multiplierYearFirst, ScoreMultiplier.yearFirst.factor),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (emoji, label, factor) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(emoji),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label)),
                  Text(
                    '×$factor',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 20),
          // The one sentence a child can hold: the best bonus always wins.
          Text(
            l10n.rulesOnlyBestMultiplier,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.emoji,
    required this.title,
    required this.body,
    this.highlighted = false,
  });

  final String emoji;
  final String title;
  final String body;

  /// The two "why does it change" sections, which are the ones a child comes
  /// here for after seeing a number move.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding:
          highlighted
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
              : EdgeInsets.zero,
      decoration:
          highlighted
              ? BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              )
              : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: theme.textTheme.titleLarge),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color:
                        highlighted
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
              color:
                  highlighted
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
