// =============================================================================
// Points models — the numbers, the badges, the achievements
// =============================================================================
//
// `STAT-05` splits this area into three tabs, and the split is the same one
// that runs through the models: **what happened** (numbers and a chart), **what
// you earned recently** (badges, which reset), and **how far you have come**
// (achievements, which never do).
//
// ### Nothing here is stored
//
// Every badge and achievement is *derived* from `DaySpecies`, `ScoreEvents`
// and `LifeSpecies` rather than written to a table. That is what `AUS-12` asks
// for: after a rebalance, badges already earned must be recomputable from
// history, and a stored row could go stale in a way nothing would notice. The
// `Achievements` table exists for the day an unlock animation needs to know
// whether something is *newly* earned (`AUS-08`, P1); until then, deriving is
// both simpler and more correct.
// =============================================================================

import 'package:meta/meta.dart';

/// One column of the 30-day chart (`STAT-02`).
@immutable
class DayStars {
  const DayStars({required this.dayKey, required this.date, this.stars = 0});

  final String dayKey;
  final DateTime date;

  /// Zero for a day with nothing on it — **and that day is still in the list**.
  ///
  /// Days without activity are shown as an empty column rather than omitted,
  /// or the curve lies: five scattered days across a month would draw the same
  /// shape as five days in a row.
  final int stars;

  bool get isEmpty => stars == 0;
}

/// The key figures row (`STAT-06`).
@immutable
class KeyFigures {
  const KeyFigures({
    this.totalStars = 0,
    this.speciesOverall = 0,
    this.activeDays = 0,
    this.longestStreak = 0,
  });

  final int totalStars;

  /// Distinct species ever collected — the life list.
  final int speciesOverall;

  /// ⚠️ **A day is active when it produced at least one scoring detection.**
  ///
  /// Not "app opened", not "session started". It is the only definition a
  /// child can check against their own journal, and it makes the words mean
  /// what they say. A day spent entirely in test mode is therefore not an
  /// active day (`PKT-20`, `LOG-15`) — which follows from the same rule rather
  /// than being an exception to it.
  final int activeDays;

  /// Longest run of consecutive active days.
  ///
  /// A *broken* streak is never commented on anywhere in the app (`AUS-07`,
  /// principle 1). This figure is a record, not a status.
  final int longestStreak;
}

/// A badge that resets — daily, weekly, or per species (3.2).
enum BadgeKind { daily, weekly, loyalty }

/// One badge in the catalogue.
@immutable
class BadgeDefinition {
  const BadgeDefinition({
    required this.key,
    required this.emoji,
    required this.kind,
  });

  /// Stable identifier; also the l10n key suffix.
  final String key;

  final String emoji;
  final BadgeKind kind;
}

/// A badge the child has earned, and when.
@immutable
class EarnedBadge {
  const EarnedBadge({
    required this.definition,
    this.lastEarnedOn,
    this.timesEarned = 1,
    this.subject,
  });

  final BadgeDefinition definition;

  /// Day key of the most recent time it was earned.
  final String? lastEarnedOn;

  /// How often it has been earned. A badge that resets can be earned again.
  final int timesEarned;

  /// For a loyalty badge, the species it was earned with.
  final String? subject;
}

/// One rung of the Collector ladder (`AUS-03`, 3.3).
@immutable
class AchievementTier {
  const AchievementTier({
    required this.threshold,
    required this.emoji,
    required this.key,
  });

  /// Distinct species needed.
  final int threshold;

  final String emoji;

  /// Stable identifier; also the l10n key suffix.
  final String key;
}

/// The Collector ladder, 3.3.
///
/// Only earned rungs are shown (`AUS-03`), so this is a lookup rather than a
/// display list.
const List<AchievementTier> kCollectorTiers = [
  AchievementTier(threshold: 10, emoji: '🥉', key: 'firstSteps'),
  AchievementTier(threshold: 25, emoji: '🥈', key: 'attentiveListener'),
  AchievementTier(threshold: 50, emoji: '🥇', key: 'halfAHundred'),
  AchievementTier(threshold: 75, emoji: '💎', key: 'connoisseur'),
  AchievementTier(threshold: 100, emoji: '👑', key: 'bigHundred'),
  AchievementTier(threshold: 150, emoji: '⭐', key: 'speciesHunter'),
  AchievementTier(threshold: 200, emoji: '🔥', key: 'earsLikeALynx'),
  AchievementTier(threshold: 250, emoji: '🏆', key: 'ornithologist'),
];

/// The badges this step implements — the P0 set (`AUS-01`, `AUS-02`).
///
/// `AUS-04` and `AUS-05` fill in the rest of the day and week catalogue at P1;
/// each is a row here plus its two strings.
const BadgeDefinition kTenInOneGo = BadgeDefinition(
  key: 'tenInOneGo',
  emoji: '🔟',
  kind: BadgeKind.daily,
);

const BadgeDefinition kRegular = BadgeDefinition(
  key: 'regular',
  emoji: '🤝',
  kind: BadgeKind.loyalty,
);

const BadgeDefinition kPermanentGuest = BadgeDefinition(
  key: 'permanentGuest',
  emoji: '🏠',
  kind: BadgeKind.loyalty,
);

/// Everything the Points area shows.
@immutable
class PointsOverview {
  const PointsOverview({
    required this.figures,
    this.dailyStars = const [],
    this.badges = const [],
    this.achievements = const [],
  });

  final KeyFigures figures;

  /// Oldest first, one entry per day including the empty ones (`STAT-02`).
  final List<DayStars> dailyStars;

  /// Earned badges, most recent first.
  final List<EarnedBadge> badges;

  /// Earned Collector tiers, highest first (`AUS-03`).
  final List<AchievementTier> achievements;

  /// The highest daily total in the chart window, for scaling the bars.
  int get peakDayStars =>
      dailyStars.fold(0, (best, day) => day.stars > best ? day.stars : best);
}
