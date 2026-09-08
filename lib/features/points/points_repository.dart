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
import '../../core/database/tables.dart';
import '../inference/geo_model.dart';
import '../scoring/scoring_repository.dart';
import '../scoring/season_hint.dart';
import 'points_models.dart';

/// A species' 48-week geo curve, or null when the model has nothing for it.
///
/// The seam that lets 🌱 Herald of spring be decided in the repository beside
/// the other badges while the curve itself comes from the inference layer.
typedef WeeklyScoresLookup = List<double>? Function(String scientificName);

/// Reads the Points area.
class PointsRepository {
  PointsRepository(this._db, {this.profileId = kDefaultProfileId});

  final AppDatabase _db;
  final String profileId;

  /// Ten different species in one day (`AUS-01`, 3.2).
  static const int tenInOneGo = 10;

  /// Different species in the 05:00–09:00 window for 🎵 Dawn chorus.
  static const int dawnChorusSpecies = 5;

  /// Days of one ISO week for 📅 Consistent.
  static const int consistentDays = 4;

  /// Distinct grid cells in one ISO week for 🌍 Well travelled.
  static const int wellTravelledPlaces = 3;

  /// Stars in one ISO week for 🎯 Weekly target.
  static const int weeklyTargetStars = 5000;

  /// The rarest level a detection can carry (`levelAtDetection`, 0 = rare).
  static const int topRarityLevel = 0;

  /// "The upper half of the rarity levels" (3.2, 3.3).
  ///
  /// `levelAtDetection` runs 0 = rare … 5 = abundant, so the *rarer* half is
  /// 0, 1 and 2 — rare, scarce, uncommon. Reading this the other way round
  /// would hand out the rarity medals for blackbirds.
  static const int upperHalfRarityLevel = 2;

  /// Everything the Points area shows, in one pass over the tables.
  ///
  /// [weeklyScores] is the one input that does not come from the database: 🌱
  /// Herald of spring asks whether a bird was early for the season, and the
  /// answer lives in the geo model's 48-week curve. Injected rather than
  /// looked up here, so the badge rule stays beside the others and the
  /// repository stays a thing you can hand a fake to. Omitting it means the
  /// badge simply cannot be earned, which is honest: without a curve there is
  /// no season to be early for.
  Future<PointsOverview> overview({
    required DateTime now,
    int chartDays = 30,
    WeeklyScoresLookup? weeklyScores,
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

    final sessions =
        await (_db.select(_db.sessions)
          ..where((s) => s.profileId.equals(profileId))).get();

    final speciesEvents = [
      for (final event in events)
        if (event.type == ScoreEventType.species) event,
    ];

    final figures = KeyFigures(
      totalStars: events.fold(0, (sum, event) => sum + event.total),
      speciesOverall: lifeList.length,
      // An active day is one that produced at least one *scoring*
      // detection — which is exactly what a DaySpecies row is (STAT-06).
      activeDays: speciesByDay.length,
      longestStreak: longestStreakIn(speciesByDay.keys),
    );

    return PointsOverview(
      figures: figures,
      dailyStars: _chart(now: now, days: chartDays, starsByDay: starsByDay),
      badges: _badges(
        speciesEvents: speciesEvents,
        speciesByDay: speciesByDay,
        daysBySpecies: daysBySpecies,
        starsByDay: starsByDay,
        lifeList: lifeList,
        sessions: sessions,
        weeklyScores: weeklyScores,
      ),
      rarityAchievements: rarityAchievementsFor(speciesEvents),
      persistenceAchievements: persistenceAchievementsFor(figures),
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

  /// Badges earned so far — the full day and week catalogue (`AUS-01`,
  /// `AUS-02`, `AUS-04`, `AUS-05`).
  ///
  /// "Earned" means **ever earned**, not earned today. The catalogue on screen
  /// shows every badge with a tick or greyed out, and a tick that vanished at
  /// midnight would make the tab a to-do list rather than a record.
  ///
  /// Read from `ScoreEvents` rather than from `Detections`, so a badge means
  /// the same thing every star does: listening with scoring paused (`PKT-20`,
  /// `LOG-15`) is kept and is worth nothing, badges included.
  List<EarnedBadge> _badges({
    required List<ScoreEvent> speciesEvents,
    required Map<String, Set<String>> speciesByDay,
    required Map<String, Set<String>> daysBySpecies,
    required Map<String, int> starsByDay,
    required List<LifeSpecy> lifeList,
    required List<Session> sessions,
    WeeklyScoresLookup? weeklyScores,
  }) {
    final badges = <EarnedBadge>[];

    /// Records [definition] against the days it was earned on, or nothing.
    void award(BadgeDefinition definition, Iterable<String> onDays) {
      final days = onDays.toList()..sort();
      if (days.isEmpty) return;
      badges.add(
        EarnedBadge(
          definition: definition,
          lastEarnedOn: days.last,
          timesEarned: days.length,
        ),
      );
    }

    // ---- Daily, from the clock (AUS-04) --------------------------------
    final byHour = <String, List<ScoreEvent>>{};
    for (final event in speciesEvents) {
      (byHour[event.dayKey] ??= []).add(event);
    }

    String? dayIf(String dayKey, bool Function(ScoreEvent e) test) =>
        byHour[dayKey]!.any(test) ? dayKey : null;

    final earlyBird = <String>[];
    final eveningListener = <String>[];
    final nightOwl = <String>[];
    final dawnChorus = <String>[];

    for (final dayKey in byHour.keys) {
      if (dayIf(dayKey, (e) => e.awardedAt.hour < 9) != null) {
        earlyBird.add(dayKey);
      }
      if (dayIf(dayKey, (e) => e.awardedAt.hour >= 18) != null) {
        eveningListener.add(dayKey);
      }
      if (dayIf(dayKey, (e) => e.awardedAt.hour >= 22) != null) {
        nightOwl.add(dayKey);
      }

      // Five *different* species in the dawn window, not five detections.
      final atDawn = {
        for (final event in byHour[dayKey]!)
          if (event.awardedAt.hour >= 5 &&
              event.awardedAt.hour < 9 &&
              event.scientificName != null)
            event.scientificName!,
      };
      if (atDawn.length >= dawnChorusSpecies) dawnChorus.add(dayKey);
    }

    award(kEarlyBird, earlyBird);
    award(kEveningListener, eveningListener);
    award(kDawnChorus, dawnChorus);
    award(kNightOwl, nightOwl);

    // ---- 🔟 Ten different species in one day (AUS-01) --------------------
    award(
      kTenInOneGo,
      speciesByDay.entries
          .where((e) => e.value.length >= tenInOneGo)
          .map((e) => e.key),
    );

    // ---- ✨ A first find on this day (AUS-04) ----------------------------
    // From the life list, so it means the same thing the journal's ✨ NEW
    // does (`LOG-09`): first time ever, not first time today.
    award(kDiscoveryDay, {
      for (final row in lifeList) dayKeyFor(row.firstSeenAt),
    });

    // ---- 🥇 A species from the upper half of the rarity levels ----------
    award(kRareGuest, {
      for (final event in speciesEvents)
        if ((event.levelAtDetection ?? 99) <= upperHalfRarityLevel)
          event.dayKey,
    });

    // ---- 🌱 A bird that is unusually scarce here this week ---------------
    // The judgement `PKT-17` puts on screen as a sentence, awarded as a
    // badge — so the app cannot congratulate a child for an early arrival it
    // simultaneously describes as ordinary.
    if (weeklyScores != null) {
      final herald = <String>{};
      for (final event in speciesEvents) {
        final name = event.scientificName;
        if (name == null || herald.contains(event.dayKey)) continue;
        final scores = weeklyScores(name);
        if (scores == null) continue;
        final hint = seasonHintFor(
          weeklyScores: scores,
          currentWeek: GeoModel.dateTimeToWeek(event.awardedAt),
        );
        if (hint?.phase == SeasonPhase.early) herald.add(event.dayKey);
      }
      award(kHeraldOfSpring, herald);
    }

    // ---- 🗺️ Somewhere never listened in before ---------------------------
    // A place is a 0.1° cell (NFA-08), not a name the child typed: a badge
    // that needed labelled walks would be a badge for bookkeeping.
    final located = [
      for (final session in sessions)
        if (session.gridCell != null) session,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final seenCells = <String>{};
    final newGround = <String>{};
    for (final session in located) {
      if (seenCells.add(session.gridCell!) && seenCells.length > 1) {
        // Not the very first cell: everywhere is new ground the first time
        // the app is opened, and a badge for that teaches nothing.
        newGround.add(dayKeyFor(session.startedAt));
      }
    }
    award(kNewGround, newGround);

    // ---- Weekly (AUS-05) ------------------------------------------------
    final daysPerWeek = <String, Set<String>>{};
    final starsPerWeek = <String, int>{};
    final cellsPerWeek = <String, Set<String>>{};

    for (final dayKey in speciesByDay.keys) {
      (daysPerWeek[_weekKeyOf(dayKey)] ??= {}).add(dayKey);
    }
    for (final entry in starsByDay.entries) {
      final week = _weekKeyOf(entry.key);
      starsPerWeek[week] = (starsPerWeek[week] ?? 0) + entry.value;
    }
    for (final session in located) {
      final week = _weekKeyOf(dayKeyFor(session.startedAt));
      (cellsPerWeek[week] ??= {}).add(session.gridCell!);
    }

    award(
      kConsistent,
      daysPerWeek.entries
          .where((e) => e.value.length >= consistentDays)
          .map((e) => e.key),
    );
    award(
      kWellTravelled,
      cellsPerWeek.entries
          .where((e) => e.value.length >= wellTravelledPlaces)
          .map((e) => e.key),
    );
    award(
      kWeeklyTarget,
      starsPerWeek.entries
          .where((e) => e.value >= weeklyTargetStars)
          .map((e) => e.key),
    );

    // ---- Loyalty, per species (AUS-02) ----------------------------------
    // Derived from the days themselves rather than from the multiplier on the
    // event: the multiplier records what was *paid*, and only the highest one
    // is ever paid (`PKT-07`), so a species that was a first find on the day
    // it also became a Regular would have no ×2 to find.
    for (final entry in daysBySpecies.entries) {
      final perWeek = <String, Set<String>>{};
      for (final dayKey in entry.value) {
        (perWeek[_weekKeyOf(dayKey)] ??= {}).add(dayKey);
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

  /// Rarity achievements (`AUS-06`, 3.3).
  ///
  /// ⚠️ Counted at `levelAtDetection` — the tier **frozen at the moment of
  /// detection** (`PKT-15`). The scale is rebuilt per grid cell and per geo
  /// week, so re-deriving it today would un-earn a redwing that was rare in
  /// November because the same bird is common in January. Achievements that
  /// drifted with the seasons would be worse than no achievements at all.
  ///
  /// Public because the boundary is worth testing on its own: "upper half of
  /// the rarity levels" is levels 0–2 of 0–5, and an off-by-one here silently
  /// hands out a medal for a blackbird.
  static List<PermanentAchievement> rarityAchievementsFor(
    Iterable<ScoreEvent> speciesEvents,
  ) {
    final rare = <String>{};
    var sensational = false;

    for (final event in speciesEvents) {
      final level = event.levelAtDetection;
      final name = event.scientificName;
      if (level == null || name == null) continue;
      if (level <= upperHalfRarityLevel) rare.add(name);
      if (level == topRarityLevel) sensational = true;
    }

    // Sensation! asks a different question from the three counted rungs — one
    // bird at the very top rather than a tally — so it is decided separately
    // rather than squeezed into the same threshold map.
    return [
      for (final achievement in kRarityAchievements)
        if (achievement.key == kSensation.key
            ? sensational
            : rare.length >= kRarityThresholds[achievement.key]!)
          achievement,
    ];
  }

  /// Persistence achievements (`AUS-07`, 3.3).
  ///
  /// ⚠️ Everything here is a **record**, never a status. The streak rungs read
  /// the longest run there has ever been, so nothing on this list can be taken
  /// away on the day a child misses — `AUS-07` and principle 1 both say a
  /// broken streak is not commented on, and the cheapest way to keep that
  /// promise is to have no number that can go down.
  static List<PermanentAchievement> persistenceAchievementsFor(
    KeyFigures figures,
  ) {
    return [
      if (figures.longestStreak >= kWeekKeptUpDays) kWeekKeptUp,
      if (figures.longestStreak >= kMonthOfBirdEarsDays) kMonthOfBirdEars,
      if (figures.activeDays >= kHundredDaysOutdoorsDays) kHundredDaysOutdoors,
      for (final rung in [kStarCollectorI, kStarCollectorII, kStarCollectorIII])
        if (figures.totalStars >= kStarCollectorThresholds[rung.key]!) rung,
    ];
  }

  static String _weekKeyOf(String dayKey) =>
      dayKeyFor(startOfIsoWeek(_dateOf(dayKey)));

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
