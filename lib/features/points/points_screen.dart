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
import 'package:smartfinch/shared/utils/app_icons.dart';

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
                    _BadgesTab(overview: data),
                    _AchievementsTab(
                      earned: data.achievements,
                      year: data.yearAchievements,
                      rarity: data.rarityAchievements,
                      persistence: data.persistenceAchievements,
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
/// The badge catalogue (`AUS-01`, `AUS-02`, `AUS-04`, `AUS-05`).
///
/// **The day and week catalogues are shown in full, earned or not.** An open
/// daily badge is a suggestion for this afternoon — "Evening listener, not yet
/// today" is an invitation to go outside after dinner, which is exactly the
/// rhythm 3.2 is trying to set.
///
/// **The loyalty badges are not.** `AUS-02` is explicit: they appear only once
/// earned. The difference is that a loyalty badge belongs to a *species*, and
/// a permanently greyed "Regular — blackbird" would be a reproach about a bird
/// rather than an invitation about an evening.
class _BadgesTab extends StatelessWidget {
  const _BadgesTab({required this.overview});

  final PointsOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final loyalty = [
      for (final badge in overview.badges)
        if (badge.definition.kind == BadgeKind.loyalty) badge,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _SectionLabel(text: l10n.pointsSectionToday),
        for (final definition in kDailyBadges)
          BadgeTile(
            definition: definition,
            earned: overview.badgeFor(definition.key),
          ),
        const SizedBox(height: 12),
        _SectionLabel(text: l10n.pointsSectionThisWeek),
        for (final definition in kWeeklyBadges)
          BadgeTile(
            definition: definition,
            earned: overview.badgeFor(definition.key),
          ),
        if (loyalty.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel(text: l10n.pointsSectionLoyalty),
          for (final badge in loyalty)
            BadgeTile(definition: badge.definition, earned: badge),
        ],
      ],
    );
  }
}

/// One badge, earned or still open.
class BadgeTile extends StatelessWidget {
  const BadgeTile({super.key, required this.definition, this.earned});

  final BadgeDefinition definition;

  /// Null while the badge is still open.
  final EarnedBadge? earned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isEarned = earned != null;

    // Open badges are quieter, not crossed out. The distinction the tab has to
    // carry is "done" versus "still to do", never "done" versus "failed".
    final foreground =
        isEarned
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isEarned ? null : theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        leading: Opacity(
          opacity: isEarned ? 1 : 0.4,
          child: Text(definition.emoji, style: theme.textTheme.headlineSmall),
        ),
        title: Text(
          // A loyalty badge belongs to a species, and saying which is most of
          // its meaning: "Regular — Blackbird".
          earned?.subject == null
              ? badgeName(l10n, definition.key)
              : '${badgeName(l10n, definition.key)} · ${earned!.subject}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
        subtitle: Text(
          badgeCondition(l10n, definition.key),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: _BadgeMark(earned: earned),
      ),
    );
  }
}

/// ✓ and, where it has happened more than once, how often.
class _BadgeMark extends StatelessWidget {
  const _BadgeMark({required this.earned});

  final EarnedBadge? earned;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (earned == null) {
      return Icon(
        AppIcons.lockOutline,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        semanticLabel: l10n.pointsBadgeOpen,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (earned!.timesEarned > 1)
          Text(
            '×${earned!.timesEarned}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        const SizedBox(width: 6),
        Icon(
          AppIcons.checkCircle,
          size: 20,
          color: theme.colorScheme.primary,
          semanticLabel: l10n.pointsBadgeEarned,
        ),
      ],
    );
  }
}

/// The badge's name in the child's language.
///
/// A free function rather than a method, so the celebration card (`AUS-08`)
/// and the catalogue cannot end up calling a badge two different things.
String badgeName(AppLocalizations l10n, String key) => switch (key) {
  'earlyBird' => l10n.badgeEarlyBird,
  'eveningListener' => l10n.badgeEveningListener,
  'dawnChorus' => l10n.badgeDawnChorus,
  'tenInOneGo' => l10n.badgeTenInOneGo,
  'discoveryDay' => l10n.badgeDiscoveryDay,
  'rareGuest' => l10n.badgeRareGuest,
  'heraldOfSpring' => l10n.badgeHeraldOfSpring,
  'newGround' => l10n.badgeNewGround,
  'nightOwl' => l10n.badgeNightOwl,
  'consistent' => l10n.badgeConsistent,
  'wellTravelled' => l10n.badgeWellTravelled,
  'weeklyTarget' => l10n.badgeWeeklyTarget,
  'regular' => l10n.badgeRegular,
  _ => l10n.badgePermanentGuest,
};

/// What has to happen to earn it.
String badgeCondition(AppLocalizations l10n, String key) => switch (key) {
  'earlyBird' => l10n.badgeEarlyBirdCondition,
  'eveningListener' => l10n.badgeEveningListenerCondition,
  'dawnChorus' => l10n.badgeDawnChorusCondition,
  'tenInOneGo' => l10n.badgeTenInOneGoCondition,
  'discoveryDay' => l10n.badgeDiscoveryDayCondition,
  'rareGuest' => l10n.badgeRareGuestCondition,
  'heraldOfSpring' => l10n.badgeHeraldOfSpringCondition,
  'newGround' => l10n.badgeNewGroundCondition,
  'nightOwl' => l10n.badgeNightOwlCondition,
  'consistent' => l10n.badgeConsistentCondition,
  'wellTravelled' => l10n.badgeWellTravelledCondition,
  'weeklyTarget' => l10n.badgeWeeklyTargetCondition,
  'regular' => l10n.badgeRegularCondition,
  _ => l10n.badgePermanentGuestCondition,
};

/// A rarity or persistence achievement's name (`AUS-06`, `AUS-07`).
String achievementName(AppLocalizations l10n, String key) => switch (key) {
  'luckyOne' => l10n.achievementLuckyOne,
  'tracker' => l10n.achievementTracker,
  'rarityCollector' => l10n.achievementRarityCollector,
  'sensation' => l10n.achievementSensation,
  'weekKeptUp' => l10n.achievementWeekKeptUp,
  'monthOfBirdEars' => l10n.achievementMonthOfBirdEars,
  'hundredDaysOutdoors' => l10n.achievementHundredDaysOutdoors,
  'starCollectorI' => l10n.achievementStarCollector('I'),
  'starCollectorII' => l10n.achievementStarCollector('II'),
  _ => l10n.achievementStarCollector('III'),
};

String achievementCondition(AppLocalizations l10n, String key) => switch (key) {
  'luckyOne' => l10n.achievementLuckyOneCondition,
  'tracker' => l10n.achievementTrackerCondition,
  'rarityCollector' => l10n.achievementRarityCollectorCondition,
  'sensation' => l10n.achievementSensationCondition,
  'weekKeptUp' => l10n.achievementWeekKeptUpCondition,
  'monthOfBirdEars' => l10n.achievementMonthOfBirdEarsCondition,
  'hundredDaysOutdoors' => l10n.achievementHundredDaysOutdoorsCondition,
  _ => l10n.achievementStarCollectorCondition(
    kStarCollectorThresholds[key] ?? 0,
  ),
};

/// The Collector ladder (`AUS-03`).
class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({
    required this.earned,
    required this.year,
    required this.rarity,
    required this.persistence,
    required this.speciesOverall,
  });

  final List<AchievementTier> earned;

  /// Year-list achievements (`AUS-13`), kept in their own section.
  final List<YearAchievement> year;

  /// Rarity achievements (`AUS-06`).
  final List<PermanentAchievement> rarity;

  /// Persistence achievements (`AUS-07`).
  final List<PermanentAchievement> persistence;

  final int speciesOverall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    if (earned.isEmpty &&
        year.isEmpty &&
        rarity.isEmpty &&
        persistence.isEmpty) {
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
        if (earned.isNotEmpty) ...[
          _SectionLabel(text: l10n.pointsSectionCollector),
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
                subtitle: Text(
                  l10n.achievementSpeciesCollected(tier.threshold),
                ),
              ),
            ),
          if (next.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                l10n.pointsNextTier(next.first.threshold - speciesOverall),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],

        // Rarity and persistence are their own sections rather than more
        // rungs of the Collector ladder: they count different things —
        // luck, and turning up — and a single list would imply an order
        // between them that does not exist (AUS-06, AUS-07).
        if (rarity.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel(text: l10n.pointsSectionRarity),
          for (final achievement in rarity)
            _AchievementCard(achievement: achievement),
        ],

        // ⚠️ Nothing here can be lost. The streak rungs read the *longest*
        // run there has ever been, so there is no number on this screen that
        // goes down on the day a child misses (AUS-07, principle 1).
        if (persistence.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel(text: l10n.pointsSectionPersistence),
          for (final achievement in persistence)
            _AchievementCard(achievement: achievement),
        ],

        // Its own section, because it means something different: the Collector
        // ladder only ever grows, the year list starts again every January.
        // Mixed together they would suggest the second can be lost (3.4).
        if (year.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionLabel(text: l10n.pointsTabYear),
          for (final achievement in year)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(
                  achievement.emoji,
                  style: theme.textTheme.headlineSmall,
                ),
                title: Text(
                  _yearName(l10n, achievement),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(_yearCondition(l10n, achievement)),
              ),
            ),
        ],
      ],
    );
  }

  String _yearName(AppLocalizations l10n, YearAchievement a) => switch (a.key) {
    'yearList' => l10n.achievementYearList(a.tierLabel ?? ''),
    'allYearRound' => l10n.achievementAllYearRound,
    'theReturners' => l10n.achievementTheReturners,
    _ => l10n.achievementWinterVisitors,
  };

  String _yearCondition(AppLocalizations l10n, YearAchievement a) => switch (a
      .key) {
    'yearList' => l10n.achievementYearListCondition(a.threshold ?? 0),
    'allYearRound' => l10n.achievementAllYearRoundCondition,
    'theReturners' => l10n.achievementTheReturnersCondition,
    _ => l10n.achievementWinterVisitorsCondition,
  };

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

/// One earned rarity or persistence achievement (`AUS-06`, `AUS-07`).
///
/// Only earned ones are rendered. Unlike the daily badges these are not
/// invitations for this afternoon — "listen for 100 days" greyed out is a
/// measure of how far you are not, which is the opposite of the point.
class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement});

  final PermanentAchievement achievement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Text(achievement.emoji, style: theme.textTheme.headlineSmall),
        title: Text(
          achievementName(l10n, achievement.key),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(achievementCondition(l10n, achievement.key)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
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
