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

/// A year-list achievement (`AUS-13`, 3.3).
///
/// Together with the year-first ×2 (`PKT-12`) these **replace the removed
/// season bonus**. They reset on 1 January without the life list losing
/// anything — which is what keeps every spring interesting once the local
/// region has been largely exhausted (3.4).
@immutable
class YearAchievement {
  const YearAchievement({
    required this.key,
    required this.emoji,
    this.threshold,
    this.tierLabel,
  });

  /// Stable identifier; also the l10n key suffix.
  final String key;

  final String emoji;

  /// Species needed, for the three counted rungs.
  final int? threshold;

  /// `I`, `II`, `III` for the counted rungs; null for the named ones.
  final String? tierLabel;
}

/// The three counted rungs of the year list (`AUS-13`).
const List<YearAchievement> kYearListTiers = [
  YearAchievement(key: 'yearList', emoji: '📗', threshold: 25, tierLabel: 'I'),
  YearAchievement(key: 'yearList', emoji: '📘', threshold: 50, tierLabel: 'II'),
  YearAchievement(
    key: 'yearList',
    emoji: '📙',
    threshold: 75,
    tierLabel: 'III',
  ),
];

/// At least one detection in every month of a year.
const YearAchievement kAllYearRound = YearAchievement(
  key: 'allYearRound',
  emoji: '🗓️',
);

/// Ten species first heard in spring — the arrival of the migrants.
const YearAchievement kTheReturners = YearAchievement(
  key: 'theReturners',
  emoji: '🐦',
);

/// Five species in December or January.
const YearAchievement kWinterVisitors = YearAchievement(
  key: 'winterVisitors',
  emoji: '❄️',
);

/// 🔟 Ten different species in one day (`AUS-01`).
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

/// The full daily catalogue (`AUS-04`, 3.2).
///
/// **All of them are shown, earned or not.** That is the difference between a
/// badge and a loyalty badge: `AUS-02` keeps 🤝 and 🏠 hidden until earned
/// because a permanent reminder of a species you have not been loyal to is
/// meaningless, while an open *daily* badge is a suggestion for this
/// afternoon. "Evening listener, not yet today" is an invitation; "Regular —
/// blackbird, not yet" would be a reproach.
///
/// Ordered as they are in 3.2, which runs roughly from easiest to rarest.
const List<BadgeDefinition> kDailyBadges = [
  kEarlyBird,
  kEveningListener,
  kDawnChorus,
  kTenInOneGo,
  kDiscoveryDay,
  kRareGuest,
  kHeraldOfSpring,
  kNewGround,
  kNightOwl,
];

/// 🌅 At least one detection before 09:00.
///
/// Deliberately easy. It and [kEveningListener] are not feats but **rhythm
/// setters** — once before school, once after — and that rhythm is the whole
/// behaviour the app is trying to encourage (3.2).
const BadgeDefinition kEarlyBird = BadgeDefinition(
  key: 'earlyBird',
  emoji: '🌅',
  kind: BadgeKind.daily,
);

/// 🌆 At least one detection after 18:00.
const BadgeDefinition kEveningListener = BadgeDefinition(
  key: 'eveningListener',
  emoji: '🌆',
  kind: BadgeKind.daily,
);

/// 🎵 Five different species between 05:00 and 09:00.
const BadgeDefinition kDawnChorus = BadgeDefinition(
  key: 'dawnChorus',
  emoji: '🎵',
  kind: BadgeKind.daily,
);

/// ✨ At least one first find on this day.
const BadgeDefinition kDiscoveryDay = BadgeDefinition(
  key: 'discoveryDay',
  emoji: '✨',
  kind: BadgeKind.daily,
);

/// 🥇 A species from the upper half of the rarity levels.
const BadgeDefinition kRareGuest = BadgeDefinition(
  key: 'rareGuest',
  emoji: '🥇',
  kind: BadgeKind.daily,
);

/// 🌱 A species that is unusually scarce here this week.
///
/// The same judgement `PKT-17` puts on screen as a sentence — a bird heard in
/// the early shoulder of its own season. Which makes this the one badge that
/// cannot be derived from the database alone: it needs the species' 48-week
/// curve, so the repository takes the curve as an argument.
const BadgeDefinition kHeraldOfSpring = BadgeDefinition(
  key: 'heraldOfSpring',
  emoji: '🌱',
  kind: BadgeKind.daily,
);

/// 🗺️ A detection in a grid cell never listened in before.
const BadgeDefinition kNewGround = BadgeDefinition(
  key: 'newGround',
  emoji: '🗺️',
  kind: BadgeKind.daily,
);

/// 🌙 At least one detection after 22:00.
///
/// 3.2 moved this from 18:00 to 22:00 on purpose: at 18:00 the name would
/// simply be wrong in June, and at 22:00 it becomes a genuine rarity — owls
/// and nightingales.
const BadgeDefinition kNightOwl = BadgeDefinition(
  key: 'nightOwl',
  emoji: '🌙',
  kind: BadgeKind.daily,
);

/// The full weekly catalogue (`AUS-05`, 3.2). Resets on Monday.
const List<BadgeDefinition> kWeeklyBadges = [
  kConsistent,
  kWellTravelled,
  kWeeklyTarget,
];

/// 📅 Listened on at least 4 days of the week.
const BadgeDefinition kConsistent = BadgeDefinition(
  key: 'consistent',
  emoji: '📅',
  kind: BadgeKind.weekly,
);

/// 🌍 Listened in at least 3 different places.
///
/// A place is a 0.1° grid cell, not a name the child typed: names are optional
/// and a badge nobody can earn without labelling their walks would be a badge
/// for bookkeeping (`NFA-08`, `LOG-13`).
const BadgeDefinition kWellTravelled = BadgeDefinition(
  key: 'wellTravelled',
  emoji: '🌍',
  kind: BadgeKind.weekly,
);

/// 🎯 5,000 stars in one week.
const BadgeDefinition kWeeklyTarget = BadgeDefinition(
  key: 'weeklyTarget',
  emoji: '🎯',
  kind: BadgeKind.weekly,
);

/// A permanent achievement that is not a rung of a ladder (`AUS-06`, `AUS-07`).
///
/// Separate from [AchievementTier] because those count one thing — species —
/// and these count four different things. Sharing a class would have meant a
/// `threshold` that means stars in one row and consecutive days in the next.
@immutable
class PermanentAchievement {
  const PermanentAchievement({required this.key, required this.emoji});

  /// Stable identifier; also the l10n key suffix.
  final String key;

  final String emoji;
}

/// Rarity achievements (`AUS-06`, 3.3).
///
/// ⚠️ Counted at the level **at the moment of detection** (`levelAtDetection`,
/// a `PKT-15` frozen field), never at today's. The rarity scale is rebuilt per
/// grid cell and per geo week, so a redwing that was rare in November is not
/// un-earned by the same bird being common in January. Achievements that
/// drifted with the seasons would be worse than no achievements.
const List<PermanentAchievement> kRarityAchievements = [
  kLuckyOne,
  kTracker,
  kRarityCollector,
  kSensation,
];

const PermanentAchievement kLuckyOne = PermanentAchievement(
  key: 'luckyOne',
  emoji: '🍀',
);
const PermanentAchievement kTracker = PermanentAchievement(
  key: 'tracker',
  emoji: '👣',
);
const PermanentAchievement kRarityCollector = PermanentAchievement(
  key: 'rarityCollector',
  emoji: '💠',
);

/// One species at the very top of the scale.
const PermanentAchievement kSensation = PermanentAchievement(
  key: 'sensation',
  emoji: '🎆',
);

/// How many distinct upper-half species each rarity rung needs.
const Map<String, int> kRarityThresholds = {
  'luckyOne': 1,
  'tracker': 5,
  'rarityCollector': 10,
};

/// Persistence achievements (`AUS-07`, 3.3).
///
/// ⚠️ A broken streak is **not** commented on — not marked, not coloured, not
/// mentioned. These record the best run there has ever been, so there is
/// nothing here that can be lost on the day a child misses (principle 1).
const List<PermanentAchievement> kPersistenceAchievements = [
  kWeekKeptUp,
  kMonthOfBirdEars,
  kHundredDaysOutdoors,
  kStarCollectorI,
  kStarCollectorII,
  kStarCollectorIII,
];

const PermanentAchievement kWeekKeptUp = PermanentAchievement(
  key: 'weekKeptUp',
  emoji: '🔗',
);
const PermanentAchievement kMonthOfBirdEars = PermanentAchievement(
  key: 'monthOfBirdEars',
  emoji: '📆',
);
const PermanentAchievement kHundredDaysOutdoors = PermanentAchievement(
  key: 'hundredDaysOutdoors',
  emoji: '🥾',
);
const PermanentAchievement kStarCollectorI = PermanentAchievement(
  key: 'starCollectorI',
  emoji: '✨',
);
const PermanentAchievement kStarCollectorII = PermanentAchievement(
  key: 'starCollectorII',
  emoji: '🌟',
);
const PermanentAchievement kStarCollectorIII = PermanentAchievement(
  key: 'starCollectorIII',
  emoji: '💫',
);

/// Consecutive days needed for the two streak achievements.
const int kWeekKeptUpDays = 7;
const int kMonthOfBirdEarsDays = 30;

/// Days outdoors in total, consecutive or not.
const int kHundredDaysOutdoorsDays = 100;

/// Stars needed for the three Star collector rungs.
const Map<String, int> kStarCollectorThresholds = {
  'starCollectorI': 10000,
  'starCollectorII': 50000,
  'starCollectorIII': 100000,
};

/// Everything the Points area shows.
@immutable
class PointsOverview {
  const PointsOverview({
    required this.figures,
    this.dailyStars = const [],
    this.badges = const [],
    this.achievements = const [],
    this.yearAchievements = const [],
    this.rarityAchievements = const [],
    this.persistenceAchievements = const [],
  });

  final KeyFigures figures;

  /// Oldest first, one entry per day including the empty ones (`STAT-02`).
  final List<DayStars> dailyStars;

  /// Earned badges, most recent first.
  final List<EarnedBadge> badges;

  /// Earned Collector tiers, highest first (`AUS-03`).
  final List<AchievementTier> achievements;

  /// Earned year-list achievements (`AUS-13`).
  ///
  /// Kept apart from [achievements] because they mean something different:
  /// the Collector ladder only ever grows, the year list starts again every
  /// January. Mixing them would suggest the second can be lost.
  final List<YearAchievement> yearAchievements;

  /// Earned rarity achievements (`AUS-06`).
  final List<PermanentAchievement> rarityAchievements;

  /// Earned persistence achievements (`AUS-07`).
  final List<PermanentAchievement> persistenceAchievements;

  /// The highest daily total in the chart window, for scaling the bars.
  int get peakDayStars =>
      dailyStars.fold(0, (best, day) => day.stars > best ? day.stars : best);

  /// The earned entry for [key], or null when the badge is still open.
  ///
  /// What lets the badges tab render the whole catalogue and mark it, rather
  /// than rendering only what has been earned (`AUS-04`, `AUS-05`).
  EarnedBadge? badgeFor(String key) {
    for (final badge in badges) {
      if (badge.definition.key == key) return badge;
    }
    return null;
  }

  bool hasAchievement(String key) =>
      rarityAchievements.any((a) => a.key == key) ||
      persistenceAchievements.any((a) => a.key == key);
}
