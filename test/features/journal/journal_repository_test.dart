// =============================================================================
// JournalRepository — the day, assembled from two layers
// =============================================================================
//
// The journal reads across the raw layer and the scoring layer at once, and
// three of its rules are easy to get subtly wrong in a way nothing on screen
// would reveal:
//
//   **A day exists if anything was heard on it**, scored or not. Reading only
//   `ScoreEvents` would make an afternoon of test-mode listening vanish, which
//   is exactly what `LOG-15` promises cannot happen.
//
//   **✨ NEW means first time ever**, not first time today. Read from the life
//   list, so reopening a day next month still marks the right species.
//
//   **Outside scoring is counted separately.** Folded into the species count,
//   a day total would quietly include recordings that never counted.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/journal/journal_repository.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';

void main() {
  late AppDatabase db;
  late ScoringRepository scoring;
  late JournalRepository journal;
  late String sessionId;

  const cell = GridCell(508, 129);

  /// Monday 4 May 2026.
  final may4 = DateTime(2026, 5, 4, 14, 30);

  final scale = () {
    const ranks = {
      'Turdus merula': 1, // abundant · 50
      'Erithacus rubecula': 5, // common · 100
      'Sitta europaea': 10, // frequent · 200
      'Upupa epops': 38, // rare · 1000
    };
    final byRank = {for (final e in ranks.entries) e.value: e.key};
    final raw = <String, double>{
      for (var rank = 0; rank < 40; rank++)
        byRank[rank] ?? 'Fillerus sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: const RarityScaleKey(cell, 18),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }();

  ScoringContext contextAt(DateTime when, {bool filterEnabled = true}) =>
      ScoringContext(
        now: when,
        appliedThreshold: 35,
        filterEnabled: filterEnabled,
        scale: scale,
        cell: cell,
      );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scoring = ScoringRepository(db);
    journal = JournalRepository(db);
    sessionId = await scoring.startSession(startedAt: may4);
  });

  tearDown(() async => db.close());

  Future<void> hear(
    String name, {
    DateTime? at,
    bool filterEnabled = true,
    String? inSession,
  }) => scoring
      .recordDetection(
        sessionId: inSession ?? sessionId,
        scientificName: name,
        confidence: 0.9,
        context: contextAt(at ?? may4, filterEnabled: filterEnabled),
      )
      .then((_) {});

  group('LOG-02 · the day list', () {
    test('a day carries its stars, species count and a preview', () async {
      await hear('Turdus merula');
      await hear('Sitta europaea');

      final days = await journal.days();
      expect(days, hasLength(1));

      final day = days.single;
      expect(day.dayKey, '2026-05-04');
      expect(day.speciesCount, 2);
      expect(day.stars, greaterThan(0));
      expect(day.speciesPreview, hasLength(2));
    });

    test('the preview leads with the richest species', () async {
      // The four names on a card should be the four a child wants to see, not
      // the four that happen to sort first.
      await hear('Turdus merula'); // 50 × 3
      await hear('Upupa epops'); // 1000 × 3

      final day = (await journal.days()).single;
      expect(day.speciesPreview.first, 'Upupa epops');
    });

    test('days are newest first', () async {
      await hear('Turdus merula', at: may4.subtract(const Duration(days: 2)));
      await hear('Sitta europaea', at: may4);

      final days = await journal.days();
      expect(days.map((d) => d.dayKey), ['2026-05-04', '2026-05-02']);
    });

    test('a day of nothing but test mode still appears', () async {
      // The promise of LOG-15: nothing is lost, it just does not count.
      await hear('Turdus merula', filterEnabled: false);

      final days = await journal.days();
      expect(days, hasLength(1));
      expect(days.single.speciesCount, 0);
      expect(days.single.unscoredSpeciesCount, 1);
      expect(days.single.stars, 0);
    });

    test('the two counts stay separate', () async {
      await hear('Turdus merula');
      await hear('Sitta europaea', filterEnabled: false);

      final day = (await journal.days()).single;
      expect(day.speciesCount, 1, reason: 'only the scored one');
      expect(day.unscoredSpeciesCount, 1);
    });

    test('a repeat of a scored species is not "outside scoring"', () async {
      // It scored earlier today; hearing it again is not a failure to count.
      await hear('Turdus merula');
      await hear('Turdus merula');

      final day = (await journal.days()).single;
      expect(day.unscoredSpeciesCount, 0);
    });

    test('an empty database has no days', () async {
      expect(await journal.days(), isEmpty);
    });
  });

  group('LOG-03 · the day detail', () {
    test('every species carries its points and its multiplier', () async {
      await hear('Erithacus rubecula');

      final detail = await journal.detailFor('2026-05-04');
      final species = detail.scored.single;

      expect(species.scientificName, 'Erithacus rubecula');
      expect(species.stars, 300);
      expect(species.multiplier, ScoreMultiplier.firstFind);
      expect(species.hasMultiplier, isTrue);
    });

    test('species are listed richest first', () async {
      await hear('Turdus merula');
      await hear('Upupa epops');

      final detail = await journal.detailFor('2026-05-04');
      expect(detail.scored.first.scientificName, 'Upupa epops');
    });

    test('a species heard twice reports both', () async {
      await hear('Turdus merula');
      await hear('Turdus merula', at: may4.add(const Duration(hours: 1)));

      final species = (await journal.detailFor('2026-05-04')).scored.single;
      expect(species.detectionCount, 2);
      expect(species.firstHeardAt, may4, reason: 'the one that scored');
    });

    test('day bonuses are listed apart from the species', () async {
      for (final name in [
        'Fillerus sp2',
        'Fillerus sp3',
        'Fillerus sp4',
        'Fillerus sp6',
        'Fillerus sp7',
      ]) {
        await hear(name);
      }

      final detail = await journal.detailFor('2026-05-04');
      expect(detail.scored, hasLength(5));
      expect(detail.bonuses.map((b) => b.key), contains('variety'));
      // They belong to the day, not to any species, so no card claims them.
      expect(
        detail.scored.fold(0, (sum, s) => sum + s.stars),
        isNot(detail.day.stars),
      );
    });

    test('an untouched day is empty rather than missing', () async {
      final detail = await journal.detailFor('2020-01-01');

      expect(detail.day.dayKey, '2020-01-01');
      expect(detail.scored, isEmpty);
      expect(detail.outsideScoring, isEmpty);
    });
  });

  group('LOG-09 · ✨ NEW means first time ever', () {
    test('a first find is marked on the day it happened', () async {
      await hear('Erithacus rubecula');

      final species = (await journal.detailFor('2026-05-04')).scored.single;
      expect(species.isNew, isTrue);
    });

    test('the same species on a later day is not new', () async {
      await hear('Erithacus rubecula');
      await hear('Erithacus rubecula', at: may4.add(const Duration(days: 1)));

      final later = await journal.detailFor('2026-05-05');
      expect(later.scored.single.isNew, isFalse);
    });

    test('the original day keeps its marker afterwards', () async {
      // Reopening the day a month later must still mark the right species.
      await hear('Erithacus rubecula');
      await hear('Erithacus rubecula', at: may4.add(const Duration(days: 30)));

      final original = await journal.detailFor('2026-05-04');
      expect(original.scored.single.isNew, isTrue);
    });
  });

  group('LOG-15 · outside scoring', () {
    test('paused species land in their own list', () async {
      await hear('Turdus merula');
      await hear('Sitta europaea', filterEnabled: false);

      final detail = await journal.detailFor('2026-05-04');

      expect(detail.scored.map((s) => s.scientificName), ['Turdus merula']);
      expect(detail.outsideScoring.map((s) => s.scientificName), [
        'Sitta europaea',
      ]);
      expect(detail.hasOutsideScoring, isTrue);
    });

    test('they are worth nothing and say so', () async {
      await hear('Upupa epops', filterEnabled: false);

      final species =
          (await journal.detailFor('2026-05-04')).outsideScoring.single;
      expect(species.scored, isFalse);
      expect(species.stars, 0);
      expect(species.hasMultiplier, isFalse);
    });

    test('they never reach the day total', () async {
      await hear('Turdus merula');
      final withScoring = (await journal.detailFor('2026-05-04')).day.stars;

      await hear('Upupa epops', filterEnabled: false);

      final detail = await journal.detailFor('2026-05-04');
      expect(detail.day.stars, withScoring);
      expect(detail.day.speciesCount, 1);
    });

    test('the recording is still there — with its peak confidence', () async {
      await hear('Sitta europaea', filterEnabled: false);

      final species =
          (await journal.detailFor('2026-05-04')).outsideScoring.single;
      expect(species.peakConfidence, closeTo(0.9, 1e-9));
      expect(species.detectionCount, 1);
    });
  });

  group('LOG-13 · the child names the place', () {
    test('a day lists the sessions a name can attach to', () async {
      await hear('Turdus merula');

      final sessions = await journal.sessionsOn('2026-05-04');
      expect(sessions.map((s) => s.id), [sessionId]);
    });

    test('naming one shows up on the day and in the detail', () async {
      await hear('Turdus merula');
      await journal.renameSession(sessionId, 'Oma');

      expect((await journal.days()).single.placeNames, ['Oma']);
      expect((await journal.detailFor('2026-05-04')).day.placeNames, ['Oma']);
    });

    test('it can be changed afterwards, and cleared', () async {
      // Editable afterwards is the point: a walk gets named in the evening.
      await hear('Turdus merula');
      await journal.renameSession(sessionId, 'Oma');
      await journal.renameSession(sessionId, 'Am Teich');

      expect((await journal.days()).single.placeNames, ['Am Teich']);

      await journal.renameSession(sessionId, null);
      expect((await journal.days()).single.placeNames, isEmpty);
    });

    test('a day made of two sessions lists both places', () async {
      // Ten minutes before school and forty in the park is one day.
      final second = await scoring.startSession(
        startedAt: may4.add(const Duration(hours: 3)),
      );
      await hear('Turdus merula');
      await hear(
        'Sitta europaea',
        at: may4.add(const Duration(hours: 3)),
        inSession: second,
      );

      await journal.renameSession(sessionId, 'Schulweg');
      await journal.renameSession(second, 'Park');

      final day = (await journal.days()).single;
      expect(day.placeNames, ['Park', 'Schulweg']);
      expect(day.speciesCount, 2, reason: 'one day, not two sessions');
    });

    test('LOG-14 · names used before come back, most used first', () async {
      final second = await scoring.startSession(startedAt: may4);
      final third = await scoring.startSession(startedAt: may4);

      await journal.renameSession(sessionId, 'Oma');
      await journal.renameSession(second, 'Oma');
      await journal.renameSession(third, 'Park');

      expect(await journal.knownPlaceNames(), ['Oma', 'Park']);
    });

    test('blank names are not remembered as places', () async {
      await journal.renameSession(sessionId, '   ');

      expect(await journal.knownPlaceNames(), isEmpty);
      expect((await journal.days()), isEmpty);
    });
  });
}
