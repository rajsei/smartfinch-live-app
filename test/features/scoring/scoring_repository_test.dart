// =============================================================================
// ScoringRepository — what actually lands on disk
// =============================================================================
//
// The engine tests prove the arithmetic. These prove the writes, and one of
// them matters more than all the others:
//
//   **A paused detection must leave the scoring layer untouched.**
//
// If a test-mode detection reached `LifeSpecies`, the first-find ×3 for that
// species would be burned permanently. The child's real nuthatch, weeks later,
// would score 100 instead of 300 — and nothing in the app could explain why.
// That is precisely the hidden punishment principle 1 forbids, and DAT-11
// exists because of it.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/database/tables.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';

void main() {
  late AppDatabase db;
  late ScoringRepository repo;
  late String sessionId;

  const cell = GridCell(508, 129);

  /// A 40-species scale so all six rank-percentile bands are populated.
  /// (A scale built from a handful of species leaves `rare` empty — see
  /// `scoring_engine_test.dart`.)
  RarityScale scaleFor(int geoWeek, Map<String, int> ranks, {int count = 40}) {
    final byRank = {for (final e in ranks.entries) e.value: e.key};
    final raw = <String, double>{
      for (var rank = 0; rank < count; rank++)
        byRank[rank] ?? 'Fillerus sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: RarityScaleKey(cell, geoWeek),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }

  // Bands at 40 species: 0–3 abundant, 4–7 common, 8–17 frequent,
  // 18–29 uncommon, 30–35 scarce, 36–39 rare.
  final mayScale = scaleFor(18, {
    'Turdus merula': 1, // abundant · 50
    'Erithacus rubecula': 5, // common · 100
    'Sitta europaea': 10, // frequent · 200
    'Upupa epops': 38, // rare · 1000
  });

  ScoringContext contextAt(
    DateTime when, {
    int threshold = 35,
    bool filterEnabled = true,
  }) => ScoringContext(
    now: when,
    appliedThreshold: threshold,
    filterEnabled: filterEnabled,
    scale: mayScale,
    cell: cell,
  );

  /// Monday 4 May 2026, 14:30.
  final may4 = DateTime(2026, 5, 4, 14, 30);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ScoringRepository(db);
    sessionId = await repo.startSession(startedAt: may4);
  });

  tearDown(() async => db.close());

  Future<RecordedDetection> record(
    String name, {
    double confidence = 0.9,
    ScoringContext? context,
  }) => repo.recordDetection(
    sessionId: sessionId,
    scientificName: name,
    confidence: confidence,
    context: context ?? contextAt(may4),
  );

  Future<List<Detection>> allDetections() => db.select(db.detections).get();
  Future<List<ScoreEvent>> allEvents() => db.select(db.scoreEvents).get();
  Future<List<LifeSpecy>> allLifeList() => db.select(db.lifeSpecies).get();
  Future<List<DaySpecy>> allDaySpecies() => db.select(db.daySpecies).get();

  group('a scoring detection writes the whole set', () {
    test('detection, day species, life list, year list and event', () async {
      final result = await record('Erithacus rubecula');

      expect(result.outcome.scored, isTrue);
      expect(result.outcome.stars, 300, reason: '100 × 3 first find');

      expect(await allDetections(), hasLength(1));
      expect(await allDaySpecies(), hasLength(1));
      expect(await allLifeList(), hasLength(1));
      expect(await db.select(db.yearSpecies).get(), hasLength(1));

      final events = await allEvents();
      expect(
        events.where((e) => e.type == ScoreEventType.species),
        hasLength(1),
      );
    });

    test('the event carries the frozen fields (PKT-15)', () async {
      await record('Sitta europaea', context: contextAt(may4, threshold: 42));

      final event = (await allEvents()).firstWhere(
        (e) => e.type == ScoreEventType.species,
      );

      expect(event.baseValue, 200);
      expect(event.levelAtDetection, ExploreTier.frequent.index);
      expect(event.geoWeek, 18);
      expect(event.gridCell, '50.8,12.9');
      expect(event.appliedThreshold, 42);
      expect(event.ruleVersion, ScoringRules.current.version);
      expect(event.total, 600, reason: '200 × 3 first find');
    });

    test('the running total grows by what was awarded', () async {
      expect(await repo.totalStars(), 0);

      final first = await record('Turdus merula');
      expect(await repo.totalStars(), first.starsAwarded);

      final second = await record('Sitta europaea');
      expect(await repo.totalStars(), first.starsAwarded + second.starsAwarded);
      expect(second.totalStars, await repo.totalStars());
    });

    test(
      'the day species row points at the detection that earned it',
      () async {
        final result = await record('Turdus merula');
        final day = (await allDaySpecies()).single;

        expect(day.firstDetectionId, result.detectionId);
        expect(day.awardedPoints, result.outcome.stars);
        expect(day.dayKey, '2026-05-04');
      },
    );
  });

  group('⚠️ DAT-11 · a paused detection touches nothing', () {
    for (final entry
        in {
          'the species filter is off':
              () => contextAt(may4, filterEnabled: false),
          'the threshold is below the floor':
              () => contextAt(may4, threshold: 10),
        }.entries) {
      test('${entry.key}: the detection is kept and flagged', () async {
        final result = await record('Sitta europaea', context: entry.value());

        expect(result.outcome.skipReason, ScoringSkipReason.scoringPaused);

        final detection = (await allDetections()).single;
        expect(detection.scientificName, 'Sitta europaea');
        expect(detection.scoringPaused, isTrue);
      });

      test('${entry.key}: nothing in the scoring layer is written', () async {
        await record('Sitta europaea', context: entry.value());

        expect(await allLifeList(), isEmpty, reason: 'the life list');
        expect(await allDaySpecies(), isEmpty);
        expect(await db.select(db.yearSpecies).get(), isEmpty);
        expect(await allEvents(), isEmpty);
        expect(await repo.totalStars(), 0);
      });
    }

    test('and the real first find later still earns the full ×3', () async {
      // The whole point. A burned life-list row would make this 100.
      await record(
        'Erithacus rubecula',
        context: contextAt(may4, filterEnabled: false),
      );

      final real = await record(
        'Erithacus rubecula',
        context: contextAt(may4.add(const Duration(days: 3))),
      );

      expect(real.outcome.multiplier, ScoreMultiplier.firstFind);
      expect(real.outcome.stars, 300);
    });

    test('an off-list species is skipped but still recorded', () async {
      final result = await record('Struthio camelus');

      expect(result.outcome.skipReason, ScoringSkipReason.notOnLocalList);
      // Not "paused" — the flag means the scoring layer was switched off, not
      // that this particular bird had no tier. recomputeAllScores() may
      // reconsider an off-list species; it must never reconsider a paused one.
      expect((await allDetections()).single.scoringPaused, isFalse);
      expect(await allLifeList(), isEmpty);
    });
  });

  group('PKT-03 · once per species per day', () {
    test('the second detection of the day scores nothing', () async {
      final first = await record('Turdus merula');
      final second = await record('Turdus merula');

      expect(first.outcome.scored, isTrue);
      expect(second.outcome.skipReason, ScoringSkipReason.alreadyScoredToday);
      expect(await repo.totalStars(), first.starsAwarded);
    });

    test('both detections are kept — only the award is once', () async {
      await record('Turdus merula');
      await record('Turdus merula');

      expect(await allDetections(), hasLength(2));
      expect(await allDaySpecies(), hasLength(1));
    });

    test('a repeat can be counted without scoring', () async {
      await record('Turdus merula');
      await record('Turdus merula');
      await repo.countRepeat(
        dayKey: '2026-05-04',
        scientificName: 'Turdus merula',
      );

      expect((await allDaySpecies()).single.detectionCount, 2);
      expect(await repo.totalStars(), 50 * 3);
    });

    test('the database itself refuses a duplicate day row', () async {
      // Not a code check — the UNIQUE constraint means double-awarding is not
      // a bug that can be written.
      // Simulates the race the engine cannot see: two detections of one
      // species scored concurrently, both reading a history that says the
      // species has not scored today yet.
      final first = await record('Turdus merula');

      await expectLater(
        repo.recordDetection(
          sessionId: sessionId,
          scientificName: 'Turdus merula',
          confidence: 0.9,
          context: contextAt(may4),
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
        throwsA(anything),
      );

      // The constraint held: one award, one row, and the total did not move.
      expect(await allDaySpecies(), hasLength(1));
      expect(await repo.totalStars(), first.starsAwarded);
    });

    test('losing the award does not lose the observation', () async {
      // DAT-02: the raw row is the single source of truth and is written
      // whatever happens. Rolling the child's morning back with the stars
      // would be the more damaging half of the trade.
      await record('Turdus merula');

      await expectLater(
        repo.recordDetection(
          sessionId: sessionId,
          scientificName: 'Turdus merula',
          confidence: 0.9,
          context: contextAt(may4),
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
        throwsA(anything),
      );

      expect(await allDetections(), hasLength(2));
    });

    test('and no half-written scoring layer is left behind', () async {
      // A LifeSpecies row without its ScoreEvent would burn the ×3 for a
      // species that was never awarded it, and no recomputation could notice.
      await expectLater(
        repo.recordDetection(
          sessionId: sessionId,
          scientificName: 'Upupa epops',
          confidence: 0.9,
          context: contextAt(may4),
          history: const SpeciesHistory(),
        ),
        completes,
      );

      await expectLater(
        repo.recordDetection(
          sessionId: sessionId,
          scientificName: 'Upupa epops',
          confidence: 0.9,
          context: contextAt(may4),
          history: const SpeciesHistory(),
        ),
        throwsA(anything),
      );

      expect(await allLifeList(), hasLength(1));
      expect(
        (await allEvents()).where((e) => e.type == ScoreEventType.species),
        hasLength(1),
      );
      expect(await repo.totalStars(), 3000);
    });

    test('the same species scores again the next day', () async {
      await record('Turdus merula');
      final tomorrow = await record(
        'Turdus merula',
        context: contextAt(may4.add(const Duration(days: 1))),
      );

      expect(tomorrow.outcome.scored, isTrue);
      expect(await allDaySpecies(), hasLength(2));
    });
  });

  group('history is read from what was written', () {
    test('a species that scored is on the life list ever after', () async {
      await record('Turdus merula');

      final history = await repo.historyFor(
        scientificName: 'Turdus merula',
        now: may4.add(const Duration(days: 400)),
      );

      expect(history.isOnLifeList, isTrue);
      expect(history.isOnYearList, isFalse, reason: 'a different year');
    });

    test('PKT-05 · today counts towards the loyalty multiplier', () async {
      // Monday and Wednesday already scored; today is Friday, so this is the
      // 3rd day of the week and the multiplier is due *now*, not tomorrow.
      await record('Turdus merula', context: contextAt(may4));
      await record(
        'Turdus merula',
        context: contextAt(may4.add(const Duration(days: 2))),
      );

      final friday = may4.add(const Duration(days: 4));
      final history = await repo.historyFor(
        scientificName: 'Turdus merula',
        now: friday,
      );

      expect(history.daysThisIsoWeekWithSpecies, 3);

      final result = await record('Turdus merula', context: contextAt(friday));
      expect(result.outcome.multiplier, ScoreMultiplier.regular);
      expect(result.outcome.stars, 100);
    });

    test('the week window is Monday to Sunday, and it resets', () async {
      // Sunday 10 May is still may4's week; Monday 11 May starts a new one.
      await record('Turdus merula', context: contextAt(may4));

      final sunday = DateTime(2026, 5, 10, 9);
      final monday = DateTime(2026, 5, 11, 9);

      expect(
        (await repo.historyFor(
          scientificName: 'Turdus merula',
          now: sunday,
        )).daysThisIsoWeekWithSpecies,
        2,
      );
      expect(
        (await repo.historyFor(
          scientificName: 'Turdus merula',
          now: monday,
        )).daysThisIsoWeekWithSpecies,
        1,
        reason: 'a new week starts empty',
      );
    });

    test('a paused detection does not count towards the week', () async {
      await record(
        'Turdus merula',
        context: contextAt(may4, filterEnabled: false),
      );

      final history = await repo.historyFor(
        scientificName: 'Turdus merula',
        now: may4.add(const Duration(days: 2)),
      );

      expect(history.daysThisIsoWeekWithSpecies, 1, reason: 'only today');
    });
  });

  group('§2.6 · day bonuses land as their own events', () {
    test('the 5th species of the day earns its bonus once', () async {
      final names = [
        'Fillerus sp2',
        'Fillerus sp3',
        'Fillerus sp4',
        'Fillerus sp6',
        'Fillerus sp7',
      ];

      var bonusesSeen = 0;
      for (final name in names) {
        final result = await record(name);
        bonusesSeen += result.bonuses.length;
      }

      expect(bonusesSeen, 1);

      final variety =
          (await allEvents())
              .where((e) => e.type == ScoreEventType.variety)
              .toList();
      expect(variety, hasLength(1));
      expect(variety.single.total, 50);
      expect(variety.single.scientificName, isNull);
    });

    test('the bonus is added to the running total', () async {
      var expected = 0;
      for (final name in [
        'Fillerus sp2',
        'Fillerus sp3',
        'Fillerus sp4',
        'Fillerus sp6',
        'Fillerus sp7',
      ]) {
        expected += (await record(name)).starsAwarded;
      }

      expect(await repo.totalStars(), expected);
    });

    test('early riser is awarded once per day, not per species', () async {
      final morning = contextAt(DateTime(2026, 5, 4, 7, 30));

      final first = await record('Turdus merula', context: morning);
      final second = await record('Sitta europaea', context: morning);

      expect(first.bonuses.map((b) => b.key), contains('early_riser'));
      expect(second.bonuses.map((b) => b.key), isNot(contains('early_riser')));

      expect(
        (await allEvents()).where((e) => e.type == ScoreEventType.early),
        hasLength(1),
      );
    });

    test('no bonuses at all while scoring is paused', () async {
      for (final name in ['Fillerus sp2', 'Fillerus sp3', 'Fillerus sp4']) {
        await record(name, context: contextAt(may4, filterEnabled: false));
      }
      final fifth = await record(
        'Fillerus sp6',
        context: contextAt(may4, filterEnabled: false),
      );

      expect(fifth.bonuses, isEmpty);
      expect(await allEvents(), isEmpty);
    });
  });

  group('D15 · peak confidence is written back', () {
    test('it is null until the detection closes', () async {
      await record('Turdus merula', confidence: 0.62);
      final detection = (await allDetections()).single;

      expect(detection.confidence, closeTo(0.62, 1e-9));
      expect(detection.peakConfidence, isNull);
    });

    test('closing records the peak without changing the award', () async {
      final result = await record('Turdus merula', confidence: 0.62);
      final awarded = await repo.totalStars();

      await repo.writeBackPeakConfidence(
        detectionId: result.detectionId,
        peakConfidence: 0.91,
      );

      final detection = (await allDetections()).single;
      expect(detection.peakConfidence, closeTo(0.91, 1e-9));
      expect(detection.confidence, closeTo(0.62, 1e-9));
      expect(await repo.totalStars(), awarded);
    });
  });

  group('HOME-01 · the three star totals', () {
    /// Scores one species on [day], using a history that avoids multipliers so
    /// the arithmetic in these tests stays legible.
    Future<void> scoreOn(DateTime day, String name) => repo.recordDetection(
      sessionId: sessionId,
      scientificName: name,
      confidence: 0.9,
      context: contextAt(day),
      history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
    );

    test('total, last 30 days and today are three different numbers', () async {
      await scoreOn(may4.subtract(const Duration(days: 60)), 'Turdus merula');
      await scoreOn(may4.subtract(const Duration(days: 10)), 'Sitta europaea');
      await scoreOn(may4, 'Erithacus rubecula');

      final totals = await repo.starTotals(now: may4);

      expect(totals.total, 50 + 200 + 100);
      expect(totals.last30Days, 200 + 100, reason: 'the 60-day-old one is out');
      expect(totals.today, 100);
      expect(totals.todaySpecies, 1);
    });

    test('the 30-day window includes today and the 30th day back', () async {
      // Off by one here would quietly drop or add a whole day of a child's
      // month, and nothing on screen would look wrong.
      await scoreOn(may4.subtract(const Duration(days: 29)), 'Turdus merula');
      await scoreOn(may4.subtract(const Duration(days: 30)), 'Sitta europaea');

      final totals = await repo.starTotals(now: may4);

      expect(totals.total, 250);
      expect(totals.last30Days, 50, reason: 'day 30 is outside the window');
    });

    test('a paused detection is in none of them', () async {
      await repo.recordDetection(
        sessionId: sessionId,
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4, filterEnabled: false),
      );

      final totals = await repo.starTotals(now: may4);
      expect(totals.total, 0);
      expect(totals.today, 0);
      expect(totals.todaySpecies, 0);
    });

    test('day bonuses count towards all three', () async {
      for (final name in [
        'Fillerus sp2',
        'Fillerus sp3',
        'Fillerus sp4',
        'Fillerus sp6',
        'Fillerus sp7',
      ]) {
        await record(name);
      }

      final totals = await repo.starTotals(now: may4);
      final fromSpecies = await repo.speciesScoredOn('2026-05-04');

      expect(
        totals.today,
        fromSpecies.values.fold(0, (sum, stars) => sum + stars) + 50,
        reason: 'the variety bonus has no species of its own',
      );
    });

    test('an empty database is all zeroes, not an error', () async {
      final totals = await repo.starTotals(now: may4);

      expect(totals.total, 0);
      expect(totals.last30Days, 0);
      expect(totals.today, 0);
    });
  });

  group('the day summary', () {
    test('counts the bonuses the species rows do not carry', () async {
      for (final name in [
        'Fillerus sp2',
        'Fillerus sp3',
        'Fillerus sp4',
        'Fillerus sp6',
        'Fillerus sp7',
      ]) {
        await record(name);
      }

      final summary = await repo.summaryFor('2026-05-04');
      expect(summary.speciesCount, 5);
      expect(await repo.totalStars(), summary.stars);
    });

    test('a day with nothing on it is empty, not missing', () async {
      final summary = await repo.summaryFor('2020-01-01');

      expect(summary.dayKey, '2020-01-01');
      expect(summary.stars, 0);
      expect(summary.speciesCount, 0);
    });
  });

  group('sessions', () {
    test('a session stores its cell but never a precise coordinate', () async {
      final id = await repo.startSession(startedAt: may4, cell: cell);
      final session =
          await (db.select(db.sessions)
            ..where((s) => s.id.equals(id))).getSingle();

      expect(session.gridCell, '50.8,12.9');
    });

    test('a child can name the place afterwards (LOG-13)', () async {
      await repo.nameSession(sessionId, 'Oma');
      final session =
          await (db.select(db.sessions)
            ..where((s) => s.id.equals(sessionId))).getSingle();

      expect(session.placeName, 'Oma');
    });

    test('ending a session records when', () async {
      final ended = may4.add(const Duration(minutes: 45));
      await repo.endSession(sessionId, endedAt: ended);

      final session =
          await (db.select(db.sessions)
            ..where((s) => s.id.equals(sessionId))).getSingle();
      expect(session.endedAt, ended);
    });
  });

  group('the cell is the one at detection time (D23)', () {
    test('a detection stores its own cell, not the session start', () async {
      final walked = ScoringContext(
        now: may4,
        appliedThreshold: 35,
        filterEnabled: true,
        scale: mayScale,
        cell: const GridCell(509, 130),
      );

      await record('Turdus merula', context: walked);

      expect((await allDetections()).single.gridCell, '50.9,13.0');
    });
  });
}
