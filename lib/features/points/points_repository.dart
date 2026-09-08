// =============================================================================
// PointsRepository — deriving the numbers, not storing them
// =============================================================================
//
// Reads only, like the journal and collection layers. Nothing here can award a
// star, and nothing here writes a badge: every badge and achievement is
// recomputed from `DaySpecies`, `ScoreEvents` and `LifeSpecies` on demand.
//
// That is what `AUS-12` asks for — after a rebalance, badges already earned
// must still be derivable from history — and it means a rule change can never
// leave a stale row behind for someone to find months later.
// =============================================================================

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../scoring/scoring_repository.dart';
import 'points_models.dart';

/// Reads the Points area.
class PointsRepository {
  PointsRepository(this._db, {this.profileId = kDefaultProfileId});

  final AppDatabase _db;
  final String profileId;

  /// Ten different species in one day (`AUS-01`, 3.2).
  static const int tenInOneGo = 10;

  /// Everything the Points area shows, in one pass over the tables.
  Future<PointsOverview> overview({
    required DateTime now,
    int chartDays = 30,
  }) async {
    final events =
        await (_db.select(_db.scoreEvents)
          ..where((e) => e.profileId.equals(profileId))).get();
    final daySpecies =
        await (_db.select(_db.daySpecies)
          ..where((d) => d.profileId.equals(profileId))).get();
    final lifeList =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();
    final yearList =
        await (_db.select(_db.yearSpecies)..where(
          (y) => y.profileId.equals(profileId) & y.year.equals(now.year),
        )).get();

    final starsByDay = <String, int>{};
    for (final event in events) {
      starsByDay[event.dayKey] = (starsByDay[event.dayKey] ?? 0) + event.total;
    }

    final speciesByDay = <String, Set<String>>{};
    final daysBySpecies = <String, Set<String>>{};
    for (final row in daySpecies) {
      (speciesByDay[row.dayKey] ??= {}).add(row.scientificName);
      (daysBySpecies[row.scientificName] ??= {}).add(row.dayKey);
    }

    return PointsOverview(
      figures: KeyFigures(
        totalStars: events.fold(0, (sum, event) => sum + event.total),
        speciesOverall: lifeList.length,
        // An active day is one that produced at least one *scoring*
        // detection — which is exactly what a DaySpecies row is (STAT-06).
        activeDays: speciesByDay.length,
        longestStreak: longestStreakIn(speciesByDay.keys),
      ),
      dailyStars: _chart(now: now, days: chartDays, starsByDay: starsByDay),
      badges: _badges(speciesByDay: speciesByDay, daysBySpecies: daysBySpecies),
      achievements: [
        for (final tier in kCollectorTiers.reversed)
          if (lifeList.length >= tier.threshold) tier,
      ],
      yearAchievements: yearAchievementsFor(
        yearList: yearList,
        activeDayKeys: speciesByDay.keys,
        year: now.year,
      ),
    );
  }

  /// The year-list achievements earned in [year] (`AUS-13`, 3.3).
  ///
  /// Derived from `YearSpecies`, which is the table `PKT-12`'s ×2 checks — so
  /// the medal and the multiplier can never disagree about what counted as a
  /// year first.
  ///
  /// Public because the four rules are worth testing on their own; each has a
  /// calendar edge that would be easy to get wrong and invisible when it was.
  static List<YearAchievement> yearAchievementsFor({
    required List<YearSpecy> yearList,
    required Iterable<String> activeDayKeys,
    required int year,
  }) {
    final earned = <YearAchievement>[];

    // 📗📘📙 25 / 50 / 75 species in one calendar year, highest first.
    for (final tier in kYearListTiers.reversed) {
      if (yearList.length >= tier.threshold!) earned.add(tier);
    }

    // 🗓️ Something heard in every month of the year. Read from the *active
    // days* rather than the year list: a month in which only species you
    // already had that year were heard still counts as a month you went out.
    final months = {
      for (final dayKey in activeDayKeys)
        if (dayKey.startsWith('$year-')) dayKey.substring(5, 7),
    };
    if (months.length == 12) earned.add(kAllYearRound);

    // 🐦 Ten species first heard in spring — March to May, the arrival of the
    // migrants. First heard *this year*, which is what makes it a phenology
    // achievement rather than a counting one.
    final springArrivals =
        yearList.where((row) {
          final month = row.firstSeenAt.month;
          return month >= 3 && month <= 5;
        }).length;
    if (springArrivals >= 10) earned.add(kTheReturners);

    // ❄️ Five species in December or January. The two months straddle a year
    // boundary on purpose — that is one winter, whatever the calendar says —
    // but both halves are counted within the year being asked about, since a
    // year list cannot see the previous December.
    final winter =
        yearList.where((row) {
          final month = row.firstSeenAt.month;
          return month == 12 || month == 1;
        }).length;
    if (winter >= 5) earned.add(kWinterVisitors);

    return earned;
  }

  /// The last [days] days, oldest first, **including the empty ones**.
  ///
  /// Days without activity are columns of zero rather than gaps. Omitting them
  /// would let five scattered days across a month draw the same shape as five
  /// days in a row (`STAT-02`).
  List<DayStars> _chart({
    required DateTime now,
    required int days,
    required Map<String, int> starsByDay,
  }) {
    final today = DateTime(now.year, now.month, now.day);

    return [
      for (var back = days - 1; back >= 0; back--)
        () {
          final date = today.subtract(Duration(days: back));
          final dayKey = dayKeyFor(date);
          return DayStars(
            dayKey: dayKey,
            date: date,
            stars: starsByDay[dayKey] ?? 0,
          );
        }(),
    ];
  }

  /// Badges earned so far — the P0 set (`AUS-01`, `AUS-02`).
  List<EarnedBadge> _badges({
    required Map<String, Set<String>> speciesByDay,
    required Map<String, Set<String>> daysBySpecies,
  }) {
    final badges = <EarnedBadge>[];

    // 🔟 Ten in one go — 10 different species in one day.
    final bigDays =
        speciesByDay.entries
            .where((e) => e.value.length >= tenInOneGo)
            .map((e) => e.key)
            .toList()
          ..sort();
    if (bigDays.isNotEmpty) {
      badges.add(
        EarnedBadge(
          definition: kTenInOneGo,
          lastEarnedOn: bigDays.last,
          timesEarned: bigDays.length,
        ),
      );
    }

    // 🤝 Regular / 🏠 Permanent guest — the same species on 3 or 6 days of one
    // ISO week. Derived from the days themselves rather than from the
    // multiplier on the event: the multiplier records what was *paid*, and
    // only the highest one is ever paid (`PKT-07`), so a species that was a
    // first find on the day it also became a Regular would have no ×2 to find.
    for (final entry in daysBySpecies.entries) {
      final perWeek = <String, Set<String>>{};
      for (final dayKey in entry.value) {
        final week = dayKeyFor(startOfIsoWeek(_dateOf(dayKey)));
        (perWeek[week] ??= {}).add(dayKey);
      }

      final best = perWeek.values.fold(
        0,
        (most, days) => days.length > most ? days.length : most,
      );

      if (best >= 6) {
        badges.add(
          EarnedBadge(definition: kPermanentGuest, subject: entry.key),
        );
      } else if (best >= 3) {
        badges.add(EarnedBadge(definition: kRegular, subject: entry.key));
      }
    }

    return badges;
  }

  static DateTime _dateOf(String dayKey) {
    final parts = dayKey.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}

/// Longest run of consecutive days among [activeDayKeys].
///
/// A record, not a status: a broken streak is never commented on anywhere in
/// the app (`AUS-07`, principle 1), so this only ever reports the best one.
///
/// Public because it is the one piece of arithmetic here worth testing on its
/// own — an off-by-one would quietly rewrite a child's personal best.
int longestStreakIn(Iterable<String> activeDayKeys) {
  final days = activeDayKeys.toList()..sort();
  if (days.isEmpty) return 0;

  var longest = 1;
  var current = 1;

  for (var i = 1; i < days.length; i++) {
    final previous = PointsRepository._dateOf(days[i - 1]);
    final today = PointsRepository._dateOf(days[i]);

    // Compared as dates rather than as timestamps, so a daylight-saving
    // change inside a streak does not break it.
    if (today.difference(previous).inDays == 1) {
      current++;
      if (current > longest) longest = current;
    } else {
      current = 1;
    }
  }

  return longest;
}
