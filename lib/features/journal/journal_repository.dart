// =============================================================================
// JournalRepository — reading the day, not the recording
// =============================================================================
//
// Separate from [ScoringRepository] on purpose. That one owns the **writes**,
// and its most important property is that every path into `LifeSpecies` runs
// through one method in one file (`DAT-11`). Adding the journal's read queries
// there would bury that guarantee in three hundred lines of `SELECT`.
//
// So: this reads, that writes, and nothing here can award a star.
//
// ### Days come from two places
//
// A day appears in the journal if **anything** was heard on it — scored or
// not. Days with stars come from `ScoreEvents`; days that produced only
// paused detections come from `Detections`, and they matter precisely because
// `LOG-15` promises nothing is lost. Reading only the first source would make
// an afternoon of test-mode listening vanish.
// =============================================================================

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/database/tables.dart';
import '../scoring/scoring_repository.dart';
import '../scoring/scoring_rules.dart';
import 'journal_models.dart';

/// Reads the journal.
class JournalRepository {
  JournalRepository(this._db, {this.profileId = kDefaultProfileId});

  final AppDatabase _db;
  final String profileId;

  /// How many species names a day card previews.
  static const int previewLength = 4;

  /// Days with something on them, newest first (`LOG-02`).
  ///
  /// [from] and [to] narrow the list to one span — the week a child tapped
  /// (`LOG-04`). Without them the newest [limit] days come back, which is why
  /// the drill-down narrows rather than scrolls: an old week is not in the
  /// last sixty days to scroll to.
  Future<List<JournalDay>> days({
    int limit = 60,
    DateTime? from,
    DateTime? to,
  }) async {
    final events =
        await (_db.select(_db.scoreEvents)
          ..where((e) => e.profileId.equals(profileId))).get();
    final daySpecies =
        await (_db.select(_db.daySpecies)
          ..where((d) => d.profileId.equals(profileId))).get();
    final detections =
        await (_db.select(_db.detections)
          ..where((d) => d.profileId.equals(profileId))).get();

    final scoredNames = <String, Set<String>>{};
    for (final row in daySpecies) {
      (scoredNames[row.dayKey] ??= {}).add(row.scientificName);
    }

    // Every day anything was heard, from both sources.
    final dayKeys = <String>{
      ...events.map((e) => e.dayKey),
      ...detections.map((d) => dayKeyFor(d.detectedAt)),
    };

    final starsByDay = <String, int>{};
    for (final event in events) {
      starsByDay[event.dayKey] = (starsByDay[event.dayKey] ?? 0) + event.total;
    }

    // Species heard on a day that never made it into DaySpecies — recorded
    // while scoring was paused, or off the local list (LOG-15).
    final unscoredByDay = <String, Set<String>>{};
    final placesByDay = <String, Set<String>>{};
    final sessionPlaces = await _placeNamesBySession();

    for (final detection in detections) {
      final dayKey = dayKeyFor(detection.detectedAt);
      if (!(scoredNames[dayKey]?.contains(detection.scientificName) ?? false)) {
        (unscoredByDay[dayKey] ??= {}).add(detection.scientificName);
      }
      final place = sessionPlaces[detection.sessionId];
      if (place != null) (placesByDay[dayKey] ??= {}).add(place);
    }

    // Richest species first, so the four names on the card are the four a
    // child would want to see rather than the four that happen to sort first.
    final previewByDay = <String, List<String>>{};
    for (final row in daySpecies) {
      (previewByDay[row.dayKey] ??= []).add(row.scientificName);
    }
    final pointsOf = {
      for (final row in daySpecies)
        '${row.dayKey}|${row.scientificName}': row.awardedPoints,
    };
    for (final entry in previewByDay.entries) {
      entry.value.sort(
        (a, b) => (pointsOf['${entry.key}|$b'] ?? 0).compareTo(
          pointsOf['${entry.key}|$a'] ?? 0,
        ),
      );
    }

    final days = [
      for (final dayKey in dayKeys)
        if (_within(_dateOf(dayKey), from, to))
          JournalDay(
            dayKey: dayKey,
            date: _dateOf(dayKey),
            stars: starsByDay[dayKey] ?? 0,
            speciesCount: scoredNames[dayKey]?.length ?? 0,
            unscoredSpeciesCount: unscoredByDay[dayKey]?.length ?? 0,
            speciesPreview:
                (previewByDay[dayKey] ?? const []).take(previewLength).toList(),
            placeNames: (placesByDay[dayKey] ?? const {}).toList()..sort(),
          ),
    ]..sort((a, b) => b.dayKey.compareTo(a.dayKey));

    return days.take(limit).toList();
  }

  /// Weeks, months or years of the journal, newest first (`LOG-04`).
  ///
  /// Only buckets that contain something are returned. An empty week between
  /// two busy ones is not a fact about the child worth a card — unlike an
  /// empty *day* in the 30-day chart (`STAT-02`), where the gap is the whole
  /// point. A list is read by scrolling; a chart is read by shape.
  ///
  /// [from] and [to] narrow the list to the card the child tapped one level
  /// out (`LOG-04`) — the months of 2026, the weeks of May. A bucket belongs
  /// to the span if it **overlaps** it, so the ISO week that straddles the turn
  /// of the month shows up under both and takes the first days of the new
  /// month with it.
  Future<List<JournalBucket>> buckets(
    JournalPeriod period, {
    int limit = 60,
    DateTime? from,
    DateTime? to,
  }) async {
    if (period == JournalPeriod.day) return const [];

    final events =
        await (_db.select(_db.scoreEvents)
          ..where((e) => e.profileId.equals(profileId))).get();
    final daySpecies =
        await (_db.select(_db.daySpecies)
          ..where((d) => d.profileId.equals(profileId))).get();
    final lifeList =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();

    final stars = <DateTime, int>{};
    final species = <DateTime, Set<String>>{};
    final days = <DateTime, Set<String>>{};
    final newSpecies = <DateTime, int>{};

    for (final event in events) {
      final bucket = startOfPeriod(_dateOf(event.dayKey), period);
      stars[bucket] = (stars[bucket] ?? 0) + event.total;
    }
    for (final row in daySpecies) {
      final bucket = startOfPeriod(_dateOf(row.dayKey), period);
      (species[bucket] ??= {}).add(row.scientificName);
      (days[bucket] ??= {}).add(row.dayKey);
    }
    for (final row in lifeList) {
      final bucket = startOfPeriod(row.firstSeenAt, period);
      newSpecies[bucket] = (newSpecies[bucket] ?? 0) + 1;
    }

    final starts =
        {...stars.keys, ...species.keys}.where((start) {
            return _overlaps(start, endOfPeriod(start, period), from, to);
          }).toList()
          ..sort((a, b) => b.compareTo(a));

    return [
      for (final start in starts.take(limit))
        JournalBucket(
          period: period,
          start: start,
          end: endOfPeriod(start, period),
          stars: stars[start] ?? 0,
          speciesCount: species[start]?.length ?? 0,
          newSpeciesCount: newSpecies[start] ?? 0,
          activeDays: days[start]?.length ?? 0,
        ),
    ];
  }

  /// Everything one day contains (`LOG-03`, `LOG-09`, `LOG-15`).
  Future<JournalDayDetail> detailFor(String dayKey) async {
    final scoredRows =
        await (_db.select(_db.daySpecies)..where(
          (d) => d.profileId.equals(profileId) & d.dayKey.equals(dayKey),
        )).get();

    final events =
        await (_db.select(_db.scoreEvents)..where(
          (e) => e.profileId.equals(profileId) & e.dayKey.equals(dayKey),
        )).get();

    final detections = await _detectionsOn(dayKey);

    // ✨ NEW means first time *ever*, not first time today (LOG-09). Read from
    // the life list rather than from the day, so reopening the day a month
    // later still shows the marker on the right species.
    final lifeList =
        await (_db.select(_db.lifeSpecies)
          ..where((l) => l.profileId.equals(profileId))).get();
    final newOnThisDay = {
      for (final row in lifeList)
        if (dayKeyFor(row.firstSeenAt) == dayKey) row.scientificName,
    };

    final multiplierOf = <String, int>{
      for (final event in events)
        if (event.type == ScoreEventType.species &&
            event.scientificName != null)
          event.scientificName!: event.multiplier,
    };

    // First detection and peak per species, from the raw rows.
    final firstHeard = <String, DateTime>{};
    final peaks = <String, double>{};
    final counts = <String, int>{};
    for (final detection in detections) {
      final name = detection.scientificName;
      counts[name] = (counts[name] ?? 0) + 1;
      final earliest = firstHeard[name];
      if (earliest == null || detection.detectedAt.isBefore(earliest)) {
        firstHeard[name] = detection.detectedAt;
      }
      final peak = detection.peakConfidence ?? detection.confidence;
      if (peak > (peaks[name] ?? 0)) peaks[name] = peak;
    }

    // Every hearing, earliest first — what a species row expands into
    // (`LOG-07`). Built once for the day rather than queried per tap.
    final byName = <String, List<JournalDetection>>{};
    for (final detection in detections) {
      (byName[detection.scientificName] ??= []).add(
        JournalDetection(
          id: detection.id,
          heardAt: detection.detectedAt,
          confidence: detection.peakConfidence ?? detection.confidence,
          clipPath: detection.audioClipPath,
          isFavourite: detection.clipIsFavourite,
        ),
      );
    }
    for (final list in byName.values) {
      list.sort((a, b) => a.heardAt.compareTo(b.heardAt));
    }

    final scoredNames = {for (final row in scoredRows) row.scientificName};

    final scored = [
      for (final row in scoredRows)
        JournalSpecies(
          scientificName: row.scientificName,
          firstHeardAt: firstHeard[row.scientificName] ?? _dateOf(dayKey),
          stars: row.awardedPoints,
          multiplier: _multiplierFrom(multiplierOf[row.scientificName] ?? 1),
          detectionCount: counts[row.scientificName] ?? row.detectionCount,
          isNew: newOnThisDay.contains(row.scientificName),
          peakConfidence: peaks[row.scientificName],
          detections: byName[row.scientificName] ?? const [],
        ),
    ]..sort((a, b) => b.stars.compareTo(a.stars));

    final outsideNames = {for (final d in detections) d.scientificName}
      ..removeAll(scoredNames);

    final outsideScoring = [
      for (final name in outsideNames)
        JournalSpecies(
          scientificName: name,
          firstHeardAt: firstHeard[name] ?? _dateOf(dayKey),
          detectionCount: counts[name] ?? 1,
          scored: false,
          peakConfidence: peaks[name],
          detections: byName[name] ?? const [],
        ),
    ]..sort((a, b) => a.firstHeardAt.compareTo(b.firstHeardAt));

    final sessionPlaces = await _placeNamesBySession();
    final places =
        {
            for (final d in detections)
              if (sessionPlaces[d.sessionId] != null)
                sessionPlaces[d.sessionId]!,
          }.toList()
          ..sort();

    return JournalDayDetail(
      day: JournalDay(
        dayKey: dayKey,
        date: _dateOf(dayKey),
        stars: events.fold(0, (sum, event) => sum + event.total),
        speciesCount: scored.length,
        unscoredSpeciesCount: outsideScoring.length,
        speciesPreview:
            scored.take(previewLength).map((s) => s.scientificName).toList(),
        placeNames: places,
      ),
      scored: scored,
      outsideScoring: outsideScoring,
      bonuses: [
        for (final event in events)
          if (event.type != ScoreEventType.species)
            JournalBonus(key: _bonusKeyOf(event.type), stars: event.total),
      ],
    );
  }

  /// Sessions that touched [dayKey], for naming a place (`LOG-13`).
  Future<List<Session>> sessionsOn(String dayKey) async {
    final detections = await _detectionsOn(dayKey);
    final ids = {for (final d in detections) d.sessionId};
    if (ids.isEmpty) return const [];

    return (_db.select(_db.sessions)
          ..where((s) => s.id.isIn(ids))
          ..orderBy([(s) => OrderingTerm(expression: s.startedAt)]))
        .get();
  }

  /// Gives a session the name the child typed for it (`LOG-13`).
  ///
  /// The one write in this file, and it touches nothing the scoring layer
  /// owns: a place name is a label on a recording, not a score.
  Future<void> renameSession(String sessionId, String? placeName) async {
    await (_db.update(_db.sessions)
      ..where((s) => s.id.equals(sessionId))).write(
      SessionsCompanion(
        placeName: Value(placeName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Place names the child has used before (`LOG-14`).
  ///
  /// Not yet on screen — it is what makes "Oma" one tap rather than typed
  /// again, and what keeps the spelling stable so a per-place view stays
  /// possible later.
  Future<List<String>> knownPlaceNames() async {
    final sessions =
        await (_db.select(_db.sessions)
          ..where((s) => s.profileId.equals(profileId))).get();

    final counts = <String, int>{};
    for (final session in sessions) {
      final name = session.placeName;
      if (name == null || name.trim().isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }

    // Most used first: the place a child listens in every day should be the
    // first one offered.
    return counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  }

  // ── Internals ────────────────────────────────────────────────────────────

  Future<List<Detection>> _detectionsOn(String dayKey) {
    final start = _dateOf(dayKey);
    final end = start.add(const Duration(days: 1));

    // A range on `detectedAt` rather than a stored day key: the raw table has
    // no dayKey column, deliberately — the day is a property of the scoring
    // layer, and the raw row is just a timestamp.
    return (_db.select(_db.detections)
          ..where(
            (d) =>
                d.profileId.equals(profileId) &
                d.detectedAt.isBiggerOrEqualValue(start) &
                d.detectedAt.isSmallerThanValue(end),
          )
          ..orderBy([(d) => OrderingTerm(expression: d.detectedAt)]))
        .get();
  }

  Future<Map<String, String>> _placeNamesBySession() async {
    final sessions =
        await (_db.select(_db.sessions)
          ..where((s) => s.profileId.equals(profileId))).get();

    return {
      for (final session in sessions)
        if (session.placeName != null && session.placeName!.trim().isNotEmpty)
          session.id: session.placeName!.trim(),
    };
  }

  /// The first day of [when]'s bucket at [period].
  ///
  /// Weeks are **ISO** weeks, Monday to Sunday — the same calendar the loyalty
  /// multipliers use (`PKT-05`). Two week definitions in one app would mean a
  /// child's "3rd day this week" and their journal week could disagree about
  /// where a Sunday belongs.
  static DateTime startOfPeriod(DateTime when, JournalPeriod period) =>
      switch (period) {
        JournalPeriod.day => DateTime(when.year, when.month, when.day),
        JournalPeriod.week => startOfIsoWeek(when),
        JournalPeriod.month => DateTime(when.year, when.month),
        JournalPeriod.year => DateTime(when.year),
      };

  /// The first day *after* [start]'s bucket. Exclusive.
  static DateTime endOfPeriod(DateTime start, JournalPeriod period) =>
      switch (period) {
        JournalPeriod.day => start.add(const Duration(days: 1)),
        JournalPeriod.week => start.add(const Duration(days: 7)),
        // Month arithmetic through `DateTime`, not through day counts: months
        // are 28 to 31 days long and February is where a fixed offset breaks.
        JournalPeriod.month => DateTime(start.year, start.month + 1),
        JournalPeriod.year => DateTime(start.year + 1),
      };

  /// Whether a single day falls inside the half-open span `[from, to)`.
  static bool _within(DateTime day, DateTime? from, DateTime? to) =>
      from == null || (!day.isBefore(from) && day.isBefore(to!));

  /// Whether a bucket's own half-open range meets the span at all.
  static bool _overlaps(
    DateTime start,
    DateTime end,
    DateTime? from,
    DateTime? to,
  ) => from == null || (start.isBefore(to!) && end.isAfter(from));

  static DateTime _dateOf(String dayKey) {
    final parts = dayKey.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Recovers the multiplier from the factor stored on the event.
  ///
  /// The factor is what the event freezes, because it is what the arithmetic
  /// used; the name is presentation. Two multipliers share a factor of 3, so
  /// the first-find case wins — it is the one with a marker beside it.
  static ScoreMultiplier _multiplierFrom(int factor) => switch (factor) {
    3 => ScoreMultiplier.firstFind,
    2 => ScoreMultiplier.regular,
    _ => ScoreMultiplier.none,
  };

  static String _bonusKeyOf(ScoreEventType type) => switch (type) {
    ScoreEventType.variety => 'variety',
    ScoreEventType.early => 'early_riser',
    ScoreEventType.place => 'new_place',
    ScoreEventType.week => 'week_wrap_up',
    ScoreEventType.species => 'species',
  };
}
