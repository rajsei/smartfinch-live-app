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
  Future<List<JournalDay>> days({int limit = 60}) async {
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
