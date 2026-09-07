// =============================================================================
// ScoringRepository — the only thing that writes the scoring layer
// =============================================================================
//
// [ScoringEngine] decides; this writes. The split is deliberate and it is a
// safety property rather than architecture for its own sake:
//
//   * the engine is pure and can be tested without a database;
//   * **every write to `LifeSpecies` goes through one method in one file**, so
//     the rule that protects the first-find ×3 has exactly one place it can be
//     broken (DAT-11).
//
// ### The two layers
//
// A `Detection` row is written for **every** detection, scoring or not
// (DAT-02). Only when [ScoringOutcome.scored] does anything else follow. A
// paused detection therefore leaves `ScoreEvents`, `DaySpecies`, `YearSpecies`
// and `LifeSpecies` completely untouched — it is kept, flagged, and shown in
// the journal as outside scoring (LOG-15).
//
// ### Everything in one transaction
//
// A detection produces up to six rows plus a profile update. Half of that set
// is worse than none of it: a `LifeSpecies` row without its `ScoreEvent` burns
// the ×3 for a species that was never awarded it, and no recomputation could
// notice. So one transaction, and the `DaySpecies` UNIQUE constraint aborts it
// if the same species is somehow scored twice on one day (PKT-03).
// =============================================================================

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/app_database.dart';
import '../../core/database/tables.dart';
import '../../core/services/grid_cell.dart';
import 'live_score_board.dart';
import 'scoring_engine.dart';

/// What happened to one detection: the row that was written, and what the
/// engine decided about it.
class RecordedDetection {
  const RecordedDetection({
    required this.detectionId,
    required this.outcome,
    this.bonuses = const [],
    this.totalStars = 0,
  });

  /// Primary key of the `Detection` row, which always exists.
  final String detectionId;

  final ScoringOutcome outcome;

  /// Day-level bonuses this detection triggered (2.6). Empty unless the
  /// detection scored.
  final List<DayBonus> bonuses;

  /// The profile's running total *after* this detection.
  final int totalStars;

  /// Stars from the species award plus any bonuses it triggered — what the
  /// detection card should show as earned.
  int get starsAwarded =>
      outcome.stars + bonuses.fold(0, (sum, bonus) => sum + bonus.stars);
}

/// Reads and writes everything the scoring layer owns.
class ScoringRepository {
  ScoringRepository(
    this._db, {
    this.profileId = kDefaultProfileId,
    ScoringEngine engine = const ScoringEngine(),
    Uuid uuid = const Uuid(),
  }) : _engine = engine,
       _uuid = uuid;

  final AppDatabase _db;
  final ScoringEngine _engine;
  final Uuid _uuid;

  /// Which child's rows these are (DAT-07). One profile today.
  final String profileId;

  String _newId() => _uuid.v4();

  // ── Sessions ─────────────────────────────────────────────────────────────

  /// Opens a session and returns its id.
  Future<String> startSession({
    required DateTime startedAt,
    GridCell? cell,
    String? placeName,
  }) async {
    final id = _newId();
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            profileId: profileId,
            updatedAt: DateTime.now(),
            startedAt: startedAt,
            gridCell: Value(cell?.storageKey),
            placeName: Value(placeName),
          ),
        );
    return id;
  }

  Future<void> endSession(String sessionId, {required DateTime endedAt}) async {
    await (_db.update(_db.sessions)
      ..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        endedAt: Value(endedAt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Names the place a session happened in (LOG-13). Free text that stays on
  /// the device — it must never reach the shared day image (KID-07).
  Future<void> nameSession(String sessionId, String? placeName) async {
    await (_db.update(_db.sessions)
      ..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        placeName: Value(placeName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Reading history ──────────────────────────────────────────────────────

  /// What the engine needs to know about [scientificName] before scoring it.
  ///
  /// The four questions of chapter 2, answered from the database rather than
  /// guessed: has this species ever scored, has it scored this year, on how
  /// many days of this ISO week, and has it already scored today.
  Future<SpeciesHistory> historyFor({
    required String scientificName,
    required DateTime now,
  }) async {
    final today = dayKeyFor(now);

    final onLifeList =
        await (_db.select(_db.lifeSpecies)..where(
          (l) =>
              l.profileId.equals(profileId) &
              l.scientificName.equals(scientificName),
        )).getSingleOrNull();

    final onYearList =
        await (_db.select(_db.yearSpecies)..where(
          (y) =>
              y.profileId.equals(profileId) &
              y.year.equals(now.year) &
              y.scientificName.equals(scientificName),
        )).getSingleOrNull();

    // dayKey is `YYYY-MM-DD`, so lexicographic order is calendar order and a
    // string range is a correct week window.
    final weekStart = dayKeyFor(startOfIsoWeek(now));
    final weekEnd = dayKeyFor(startOfIsoWeek(now).add(const Duration(days: 6)));

    final thisWeek =
        await (_db.select(_db.daySpecies)..where(
          (d) =>
              d.profileId.equals(profileId) &
              d.scientificName.equals(scientificName) &
              d.dayKey.isBiggerOrEqualValue(weekStart) &
              d.dayKey.isSmallerOrEqualValue(weekEnd),
        )).get();

    final daysWithSpecies = {for (final row in thisWeek) row.dayKey};
    final scoredToday = daysWithSpecies.contains(today);

    return SpeciesHistory(
      isOnLifeList: onLifeList != null,
      isOnYearList: onYearList != null,
      // Today counts towards the loyalty multiplier, and at this moment
      // today's row does not exist yet — the detection being scored is what
      // would create it. Without this, the 3rd day of a week would be read as
      // the 2nd and the ×2 would arrive a day late (PKT-05).
      daysThisIsoWeekWithSpecies: {...daysWithSpecies, today}.length,
      alreadyScoredToday: scoredToday,
    );
  }

  /// Distinct species that have scored on [dayKey].
  Future<int> speciesCountOn(String dayKey) async {
    final rows =
        await (_db.select(_db.daySpecies)..where(
          (d) => d.profileId.equals(profileId) & d.dayKey.equals(dayKey),
        )).get();
    return rows.length;
  }

  /// Today's totals for the live and home headers (LIVE-08).
  ///
  /// Stars come from `ScoreEvents` rather than from `DaySpecies.awardedPoints`,
  /// because the day bonuses (2.6) have no species and live only in the event
  /// journal — summing the species rows would quietly under-report a day by
  /// however much variety the child found.
  Future<DaySummary> summaryFor(String dayKey) async {
    final events =
        await (_db.select(_db.scoreEvents)..where(
          (e) => e.profileId.equals(profileId) & e.dayKey.equals(dayKey),
        )).get();

    return DaySummary(
      dayKey: dayKey,
      stars: events.fold(0, (sum, event) => sum + event.total),
      speciesCount: await speciesCountOn(dayKey),
    );
  }

  /// The three numbers the home screen's star header carries (HOME-01/02).
  ///
  /// Read in one pass over the events rather than three queries: the totals
  /// are the first thing the home screen paints, and a child opening the app
  /// should not watch them appear one after another.
  Future<StarTotals> starTotals({required DateTime now}) async {
    final today = dayKeyFor(now);
    // 30 days *including* today, so the window a child sees matches the one
    // the label promises.
    final windowStart = dayKeyFor(
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
    );

    final events =
        await (_db.select(_db.scoreEvents)
          ..where((e) => e.profileId.equals(profileId))).get();

    var total = 0;
    var last30Days = 0;
    var todayStars = 0;

    for (final event in events) {
      total += event.total;
      if (event.dayKey.compareTo(windowStart) >= 0) {
        last30Days += event.total;
      }
      if (event.dayKey == today) todayStars += event.total;
    }

    return StarTotals(
      total: total,
      last30Days: last30Days,
      today: todayStars,
      todaySpecies: await speciesCountOn(today),
    );
  }

  /// Species that scored on [dayKey], and what each earned.
  Future<Map<String, int>> speciesScoredOn(String dayKey) async {
    final rows =
        await (_db.select(_db.daySpecies)..where(
          (d) => d.profileId.equals(profileId) & d.dayKey.equals(dayKey),
        )).get();
    return {for (final row in rows) row.scientificName: row.awardedPoints};
  }

  /// Whether the early-riser bonus has already been awarded on [dayKey].
  Future<bool> hasEarlyRiserBonus(String dayKey) async {
    final row =
        await (_db.select(_db.scoreEvents)..where(
          (e) =>
              e.profileId.equals(profileId) &
              e.dayKey.equals(dayKey) &
              e.type.equalsValue(ScoreEventType.early),
        )).getSingleOrNull();
    return row != null;
  }

  /// The profile's running total.
  Future<int> totalStars() async {
    final profile =
        await (_db.select(_db.userProfiles)
          ..where((p) => p.id.equals(profileId))).getSingleOrNull();
    return profile?.totalStars ?? 0;
  }

  // ── Writing ──────────────────────────────────────────────────────────────

  /// Records one detection and everything that follows from it.
  ///
  /// Called at the moment the species appears on screen — the first inference
  /// window over the threshold (D15). The peak confidence arrives later via
  /// [writeBackPeakConfidence] and does not change the award.
  ///
  /// The `Detection` row is written whatever happens. The scoring layer is
  /// touched only when the engine says the detection scored.
  ///
  /// [history] is normally read from the database; pass it to score against a
  /// known state, which is also how the duplicate-day race is tested.
  Future<RecordedDetection> recordDetection({
    required String sessionId,
    required String scientificName,
    required double confidence,
    required ScoringContext context,
    SpeciesHistory? history,
  }) async {
    final speciesHistory =
        history ??
        await historyFor(scientificName: scientificName, now: context.now);

    final outcome = _engine.scoreDetection(
      scientificName: scientificName,
      confidence: confidence,
      context: context,
      history: speciesHistory,
    );

    final detectionId = _newId();
    final now = DateTime.now();

    // Bonuses need the day's species count *before* this detection, so they
    // are computed outside the transaction and only applied inside it.
    final speciesBefore =
        outcome.scored ? await speciesCountOn(outcome.dayKey) : 0;
    final earlyAwarded =
        outcome.scored ? await hasEarlyRiserBonus(outcome.dayKey) : false;

    final bonuses =
        outcome.scored
            ? _engine.bonusesFor(
              context: context,
              speciesCountBefore: speciesBefore,
              speciesCountAfter: speciesBefore + 1,
              earlyRiserAlreadyAwarded: earlyAwarded,
            )
            : const <DayBonus>[];

    // ── The raw row, on its own ──────────────────────────────────────────
    //
    // Deliberately *outside* the scoring transaction. The `Detection` row is
    // the single source of truth (DAT-02) and is written whatever happens; if
    // the scoring layer below fails, the child loses some stars, not their
    // morning. Rolling the observation back with the award would be the more
    // damaging half of the trade.
    await _db
        .into(_db.detections)
        .insert(
          DetectionsCompanion.insert(
            id: detectionId,
            profileId: profileId,
            updatedAt: now,
            sessionId: sessionId,
            scientificName: scientificName,
            detectedAt: context.now,
            confidence: confidence,
            gridCell: Value(context.cell?.storageKey),
            // ⚠️ The flag `recomputeAllScores()` has to honour, or a later
            // recomputation would retroactively award every test recording
            // ever made (DAT-11).
            scoringPaused: Value(
              outcome.skipReason == ScoringSkipReason.scoringPaused,
            ),
          ),
        );

    if (!outcome.scored) {
      return RecordedDetection(
        detectionId: detectionId,
        outcome: outcome,
        totalStars: await totalStars(),
      );
    }

    // ── The scoring layer, all or nothing ────────────────────────────────
    //
    // Up to five rows plus the profile update, and half of that set is worse
    // than none of it: a `LifeSpecies` row without its `ScoreEvent` burns the
    // ×3 for a species that was never awarded it, and no recomputation could
    // notice.
    var runningTotal = 0;

    await _db.transaction(() async {
      // The database refuses a second row for the same species on the same
      // day, so double-awarding is not a bug that can be written (PKT-03).
      // The engine already skips repeats; this is the backstop for the race
      // where two detections of one species are scored concurrently.
      await _db
          .into(_db.daySpecies)
          .insert(
            DaySpeciesCompanion.insert(
              id: _newId(),
              profileId: profileId,
              updatedAt: now,
              dayKey: outcome.dayKey,
              scientificName: scientificName,
              firstDetectionId: detectionId,
              awardedPoints: outcome.stars,
            ),
          );

      // ⚠️ Only ever here, and only when the engine said so. A row written for
      // a detection that did not score burns this species' first-find ×3
      // permanently, and nothing in the app could later explain to the child
      // why their real first find was worth 100 instead of 300.
      if (outcome.addToLifeList) {
        await _db
            .into(_db.lifeSpecies)
            .insert(
              LifeSpeciesCompanion.insert(
                id: _newId(),
                profileId: profileId,
                updatedAt: now,
                scientificName: scientificName,
                firstDetectionId: detectionId,
                firstSeenAt: context.now,
              ),
            );
      }

      if (outcome.addToYearList) {
        await _db
            .into(_db.yearSpecies)
            .insert(
              YearSpeciesCompanion.insert(
                id: _newId(),
                profileId: profileId,
                updatedAt: now,
                year: context.now.year,
                scientificName: scientificName,
                firstDetectionId: detectionId,
                firstSeenAt: context.now,
              ),
            );
      }

      await _insertScoreEvent(
        type: ScoreEventType.species,
        outcome: outcome,
        scientificName: scientificName,
        total: outcome.stars,
        multiplier: outcome.multiplier.factor,
        now: now,
      );

      for (final bonus in bonuses) {
        await _insertScoreEvent(
          type: _typeOfBonus(bonus.key),
          outcome: outcome,
          scientificName: null,
          total: bonus.stars,
          bonus: bonus.stars,
          now: now,
        );
      }

      runningTotal = await _addStars(
        outcome.stars + bonuses.fold(0, (sum, b) => sum + b.stars),
        now,
      );
    });

    return RecordedDetection(
      detectionId: detectionId,
      outcome: outcome,
      bonuses: bonuses,
      totalStars: runningTotal,
    );
  }

  /// Writes back the highest confidence the detection reached before it ended
  /// (D15).
  ///
  /// Does not change the award: the stars were fixed the moment the species
  /// appeared. This is the value a later audit or the confirmation step
  /// (PKT-11) should look at.
  Future<void> writeBackPeakConfidence({
    required String detectionId,
    required double peakConfidence,
  }) async {
    await (_db.update(_db.detections)
      ..where((d) => d.id.equals(detectionId))).write(
      DetectionsCompanion(
        peakConfidence: Value(peakConfidence),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Counts a repeat detection of a species that already scored today.
  ///
  /// The repeat is still a real observation and still gets its `Detection`
  /// row; this only keeps the day's tally honest. No stars (PKT-03).
  Future<void> countRepeat({
    required String dayKey,
    required String scientificName,
  }) async {
    final row =
        await (_db.select(_db.daySpecies)..where(
          (d) =>
              d.profileId.equals(profileId) &
              d.dayKey.equals(dayKey) &
              d.scientificName.equals(scientificName),
        )).getSingleOrNull();
    if (row == null) return;

    await (_db.update(_db.daySpecies)..where((d) => d.id.equals(row.id))).write(
      DaySpeciesCompanion(
        detectionCount: Value(row.detectionCount + 1),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<void> _insertScoreEvent({
    required ScoreEventType type,
    required ScoringOutcome outcome,
    required String? scientificName,
    required int total,
    required DateTime now,
    int multiplier = 1,
    int bonus = 0,
  }) async {
    await _db
        .into(_db.scoreEvents)
        .insert(
          ScoreEventsCompanion.insert(
            id: _newId(),
            profileId: profileId,
            updatedAt: now,
            dayKey: outcome.dayKey,
            awardedAt: now,
            type: type,
            scientificName: Value(scientificName),
            levelAtDetection: Value(outcome.tier?.index),
            baseValue: type == ScoreEventType.species ? outcome.baseValue : 0,
            geoWeek: Value(outcome.geoWeek),
            gridCell: Value(outcome.gridCell?.storageKey),
            appliedThreshold: outcome.appliedThreshold,
            ruleVersion: outcome.ruleVersion,
            multiplier: Value(multiplier),
            bonus: Value(bonus),
            total: total,
          ),
        );
  }

  /// Adds [stars] to the running total and returns the new value.
  ///
  /// Materialised rather than summed on every read, and rebuildable from
  /// `ScoreEvents` at any time.
  Future<int> _addStars(int stars, DateTime now) async {
    final profile =
        await (_db.select(_db.userProfiles)
          ..where((p) => p.id.equals(profileId))).getSingle();
    final updated = profile.totalStars + stars;

    await (_db.update(_db.userProfiles)
      ..where((p) => p.id.equals(profileId))).write(
      UserProfilesCompanion(totalStars: Value(updated), updatedAt: Value(now)),
    );
    return updated;
  }

  ScoreEventType _typeOfBonus(String key) {
    if (key.startsWith('variety_')) return ScoreEventType.variety;
    if (key == 'early_riser') return ScoreEventType.early;
    if (key == 'new_place') return ScoreEventType.place;
    return ScoreEventType.week;
  }
}

// =============================================================================
// Calendar helpers
// =============================================================================
//
// Two calendars run through this app and they must never be confused: the geo
// model's 1–48 `geoWeek` decides rarity, the ISO week (Monday to Sunday)
// drives the loyalty multipliers. These are the ISO half.

/// Local calendar day as `YYYY-MM-DD` (DAT-05).
String dayKeyFor(DateTime when) =>
    '${when.year.toString().padLeft(4, '0')}-'
    '${when.month.toString().padLeft(2, '0')}-'
    '${when.day.toString().padLeft(2, '0')}';

/// Midnight on the Monday of [when]'s ISO week.
///
/// Built by subtracting days from the date rather than from the timestamp, so
/// a week that contains a daylight-saving change still starts on Monday
/// morning instead of drifting an hour into Sunday.
DateTime startOfIsoWeek(DateTime when) {
  final midnight = DateTime(when.year, when.month, when.day);
  return midnight.subtract(Duration(days: midnight.weekday - 1));
}
