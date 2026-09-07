// =============================================================================
// LiveScoreBoard — what the cards are allowed to say
// =============================================================================
//
// The board is the only thing between a scored detection and the text on a
// card, so the rules it has to get right are the ones a child would notice:
// a repeat must not erase the award it is a repeat of, a paused find must not
// look like a collected one, and the day total must not carry over midnight.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/live_score_board.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';

void main() {
  const engine = ScoringEngine();
  const cell = GridCell(508, 129);
  final may4 = DateTime(2026, 5, 4, 14, 30);

  final scale = () {
    const ranks = {
      'Turdus merula': 1, // abundant · 50
      'Erithacus rubecula': 5, // common · 100
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

  /// Runs the engine and wraps the outcome the way the repository would.
  RecordedDetection recorded(
    String name, {
    SpeciesHistory history = const SpeciesHistory(),
    DateTime? at,
    bool filterEnabled = true,
    List<DayBonus> bonuses = const [],
  }) {
    final outcome = engine.scoreDetection(
      scientificName: name,
      confidence: 0.9,
      context: contextAt(at ?? may4, filterEnabled: filterEnabled),
      history: history,
    );
    return RecordedDetection(
      detectionId: 'd-$name',
      outcome: outcome,
      bonuses: bonuses,
    );
  }

  late LiveScoreBoard board;

  setUp(() => board = LiveScoreBoard.forDay('2026-05-04'));

  group('LIVE-02 · an award reaches the card', () {
    test('stars and multiplier are what the engine decided', () {
      board.record('Erithacus rubecula', recorded('Erithacus rubecula'));

      final score = board.state.scoreFor('Erithacus rubecula')!;
      expect(score.stars, 300);
      expect(score.multiplier, ScoreMultiplier.firstFind);
      expect(score.hasMultiplier, isTrue);
      expect(score.isFirstFind, isTrue);
    });

    test('an ordinary award has no multiplier chip', () {
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
      );

      final score = board.state.scoreFor('Turdus merula')!;
      expect(score.stars, 50);
      expect(score.hasMultiplier, isFalse);
    });
  });

  group('LIVE-03 · a repeat says so without erasing the award', () {
    test('the card keeps the stars and gains the ✓', () {
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
      );
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(
            isOnLifeList: true,
            isOnYearList: true,
            alreadyScoredToday: true,
          ),
        ),
      );

      final score = board.state.scoreFor('Turdus merula')!;
      expect(score.isRepeat, isTrue);
      // Still 50: the species did earn them, just not again.
      expect(score.stars, 50);
    });

    test('the day total does not grow on a repeat', () {
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
      );
      final afterFirst = board.state.summary;

      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(
            isOnLifeList: true,
            isOnYearList: true,
            alreadyScoredToday: true,
          ),
        ),
      );

      expect(board.state.summary.stars, afterFirst.stars);
      expect(board.state.summary.speciesCount, 1);
    });
  });

  group('LIVE-08 · the day total', () {
    test('adds up species awards and day bonuses alike', () {
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
          bonuses: const [DayBonus(key: 'variety_5', stars: 50)],
        ),
      );

      expect(board.state.summary.stars, 100, reason: '50 + 50 bonus');
      expect(board.state.summary.speciesCount, 1);
    });

    test('counts distinct species, not detections', () {
      for (final name in ['Turdus merula', 'Erithacus rubecula']) {
        board.record(name, recorded(name));
      }

      expect(board.state.summary.speciesCount, 2);
    });

    test('starts clean when the day rolls over mid-session', () {
      // A child listening at 23:58 should not see tomorrow open with today's
      // total already on it.
      board.record('Turdus merula', recorded('Turdus merula'));
      expect(board.state.summary.stars, 150);

      board.record(
        'Erithacus rubecula',
        recorded('Erithacus rubecula', at: DateTime(2026, 5, 5, 0, 1)),
      );

      expect(board.state.summary.dayKey, '2026-05-05');
      expect(board.state.summary.stars, 300);
      expect(
        board.state.scoreFor('Turdus merula'),
        isNull,
        reason: 'yesterday is not today',
      );
    });
  });

  group('LIVE-18 · a paused find is not a find', () {
    test('nothing is added to the total and no chip is shown', () {
      board.record(
        'Erithacus rubecula',
        recorded('Erithacus rubecula', filterEnabled: false),
      );

      expect(board.state.summary.stars, 0);
      expect(board.state.summary.speciesCount, 0);

      final score = board.state.scoreFor('Erithacus rubecula')!;
      expect(score.scored, isFalse);
      expect(score.stars, 0);
      expect(score.isRepeat, isFalse);
    });

    test('⚠️ it is never queued for celebration', () {
      // Confetti for a species that was added to nothing would be the
      // cruellest possible bug in this screen.
      board.record(
        'Erithacus rubecula',
        recorded('Erithacus rubecula', filterEnabled: false),
      );

      expect(board.takePendingCelebrations(), isEmpty);
    });
  });

  group('LIVE-05 · celebrations are queued once', () {
    test('a first find is queued', () {
      board.record('Erithacus rubecula', recorded('Erithacus rubecula'));

      expect(board.takePendingCelebrations(), ['Erithacus rubecula']);
    });

    test('taking it clears the queue, so it fires once', () {
      board.record('Erithacus rubecula', recorded('Erithacus rubecula'));

      expect(board.takePendingCelebrations(), hasLength(1));
      expect(board.takePendingCelebrations(), isEmpty);
    });

    test('a species already on the life list is not celebrated', () {
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        ),
      );

      expect(board.takePendingCelebrations(), isEmpty);
    });

    test('a burst queues all of them', () {
      board.record('Turdus merula', recorded('Turdus merula'));
      board.record('Erithacus rubecula', recorded('Erithacus rubecula'));

      expect(board.takePendingCelebrations(), hasLength(2));
    });
  });

  group('notifications', () {
    test('every recorded detection notifies exactly once', () {
      var notifications = 0;
      board.addListener(() => notifications++);

      board.record('Turdus merula', recorded('Turdus merula'));
      board.record(
        'Turdus merula',
        recorded(
          'Turdus merula',
          history: const SpeciesHistory(
            isOnLifeList: true,
            alreadyScoredToday: true,
          ),
        ),
      );

      expect(notifications, 2);
    });
  });
}
