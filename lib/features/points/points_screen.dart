// =============================================================================
// PointsScreen — Overview · Badges · Achievements (STAT-01, STAT-05)
// =============================================================================
//
// Tabs rather than one long scroll. Stacked vertically this gets very long on
// a phone, and three tabs are easy for an eight-year-old — they are also the
// three questions a child actually arrives with, in order: *how am I doing*,
// *what did I just earn*, *how far have I come*.
//
// ### What is deliberately not celebrated
//
// A broken streak (`AUS-07`, principle 1). The key figures show the **longest**
// streak, not the current one, so the screen has nothing to say on the day a
// child misses. There is never a punishment, and there is never a reminder of
// one either.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

import '../../shared/widgets/content_width_constraint.dart';
import 'points_models.dart';
import 'points_providers.dart';
import 'widgets/daily_chart.dart';

/// The Points area (`STAT-01`).
class PointsScreen extends ConsumerWidget {
  const PointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final overview = ref.watch(pointsOverviewProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.pointsTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.pointsTabOverview),
              Tab(text: l10n.pointsTabBadges),
              Tab(text: l10n.pointsTabAchievements),
            ],
          ),
        ),
        body: ContentWidthConstraint(
          child: overview.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(child: Text(l10n.pointsUnavailable)),
            data:
                (data) => TabBarView(
                  children: [
                    _OverviewTab(overview: data),
                    _BadgesTab(badges: data.badges),
                    _AchievementsTab(
                      earned: data.achievements,
                      speciesOverall: data.figures.speciesOverall,
                    ),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}

/// Key figures and the 30-day chart (`STAT-02`, `STAT-06`).
class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.overview});

  final PointsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final figures = overview.figures;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        KeyFiguresGrid(figures: figures),
        const SizedBox(height: 24),
        Text(
          l10n.pointsLast30Days,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        DailyStarsChart(days: overview.dailyStars, peak: overview.peakDayStars),
      ],
    );
  }
}

/// Total stars, species, active days, longest streak (`STAT-06`).
class KeyFiguresGrid extends StatelessWidget {
  const KeyFiguresGrid({super.key, required this.figures});

  final KeyFigures figures;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.1,
      children: [
        _Figure(
          value: '${figures.totalStars}',
          label: l10n.pointsFigureTotalStars,
          emoji: '⭐',
        ),
        _Figure(
          value: '${figures.speciesOverall}',
          label: l10n.pointsFigureSpecies,
          emoji: '🐦',
        ),
        _Figure(
          value: '${figures.activeDays}',
          label: l10n.pointsFigureActiveDays,
          emoji: '📅',
        ),
        _Figure(
          value: '${figures.longestStreak}',
          // Longest, not current: the screen has nothing to say on the day a
          // child misses (AUS-07).
          label: l10n.pointsFigureLongestStreak,
          emoji: '🔥',
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.emoji,
  });

  final String value;
  final String label;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Text(emoji, style: theme.textTheme.titleLarge),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
    );
  }
}

/// Earned badges (`AUS-01`, `AUS-02`).
///
/// **Only earned ones are shown.** `AUS-02` is explicit that the loyalty
/// badges are not displayed greyed out — a permanent reminder of what you have
/// not managed is the opposite of what this screen is for. `AUS-04`/`AUS-05`
/// bring the full day and week catalogue at P1, where an open badge reads as a
/// goal rather than as a gap.
class _BadgesTab extends StatelessWidget {
  const _BadgesTab({required this.badges});

  final List<EarnedBadge> badges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (badges.isEmpty) {
      return _EmptyTab(
        emoji: '🏅',
        title: l10n.pointsNoBadgesTitle,
        subtitle: l10n.pointsNoBadgesSubtitle,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [for (final badge in badges) BadgeTile(badge: badge)],
    );
  }
}

/// One earned badge.
class BadgeTile extends ConsumerWidget {
  const BadgeTile({super.key, required this.badge});

  final EarnedBadge badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final name = switch (badge.definition.key) {
      'tenInOneGo' => l10n.badgeTenInOneGo,
      'regular' => l10n.badgeRegular,
      _ => l10n.badgePermanentGuest,
    };
    final condition = switch (badge.definition.key) {
      'tenInOneGo' => l10n.badgeTenInOneGoCondition,
      'regular' => l10n.badgeRegularCondition,
      _ => l10n.badgePermanentGuestCondition,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(
          badge.definition.emoji,
          style: theme.textTheme.headlineSmall,
        ),
        title: Text(
          // A loyalty badge belongs to a species, and saying which is most of
          // its meaning: "Regular — Blackbird".
          badge.subject == null ? name : '$name · ${badge.subject}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(condition),
        trailing:
            badge.timesEarned > 1
                ? Text(
                  '×${badge.timesEarned}',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                )
                : null,
      ),
    );
  }
}

/// The Collector ladder (`AUS-03`).
class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({required this.earned, required this.speciesOverall});

  final List<AchievementTier> earned;
  final int speciesOverall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (earned.isEmpty) {
      return _EmptyTab(
        emoji: '🥉',
        title: l10n.pointsNoAchievementsTitle,
        subtitle: l10n.pointsNextTier(
          kCollectorTiers.first.threshold - speciesOverall,
        ),
      );
    }

    // The next rung, as one line rather than as a greyed row. A ladder of
    // eight faded medals is a list of things you have not done; one sentence
    // saying how far the next one is, is a goal.
    final next = kCollectorTiers.where((t) => t.threshold > speciesOverall);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        for (final tier in earned)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Text(tier.emoji, style: theme.textTheme.headlineSmall),
              title: Text(
                _tierName(l10n, tier.key),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(l10n.achievementSpeciesCollected(tier.threshold)),
            ),
          ),
        if (next.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.pointsNextTier(next.first.threshold - speciesOverall),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _tierName(AppLocalizations l10n, String key) => switch (key) {
    'firstSteps' => l10n.achievementFirstSteps,
    'attentiveListener' => l10n.achievementAttentiveListener,
    'halfAHundred' => l10n.achievementHalfAHundred,
    'connoisseur' => l10n.achievementConnoisseur,
    'bigHundred' => l10n.achievementBigHundred,
    'speciesHunter' => l10n.achievementSpeciesHunter,
    'earsLikeALynx' => l10n.achievementEarsLikeALynx,
    _ => l10n.achievementOrnithologist,
  };
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  final String emoji;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
