// =============================================================================
// ScoringEngine — the chapter 2 rule table, as tests (NFA-14)
// =============================================================================
//
// The specification asks for exactly this: "the rules from chapter 2 as a test
// table; every rule change needs a test". All nine worked examples from §2.7 are
// reproduced below, so a rebalance that moves them moves them on purpose.
//
// ### Why the scales are built the way they are
//
// The tier of a species is **rank-relative** (§2.1): the scale cuts the local
// list at fixed shares — 8% abundant, 12% common, 25% frequent, 28% uncommon,
// 17% scarce, 10% rare. A scale built from a handful of species therefore does
// not populate all six bands; the bottom species becomes the scarce edge and
// `rare` stays empty. Tests written against such a scale still pass, but they
// stop testing anything.
//
// So the scales here hold a realistic 40 species, and every worked example
// asserts its **tier** alongside its star count. A row that silently slid into
// the wrong band fails instead of quietly agreeing.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';

void main() {
  const engine = ScoringEngine();
  const cell = GridCell(508, 129);

  /// A species below [kAbundanceInclusionThreshold], so it never reaches the
  /// list at all.
  const offList = {'Struthio camelus': 0.001};

  /// Builds a scale of [count] species in which each entry of [ranks] sits at
  /// the given rank, padded with filler so all six percentile bands are
  /// populated.
  ///
  /// Scores descend by a fixed step, so every padded species clears the
  /// inclusion threshold and only the *rank* decides the tier — which is the
  /// whole point of a rank-relative scale.
  RarityScale scaleFor(
    int geoWeek,
    Map<String, int> ranks, {
    int count = 40,
    Map<String, double> alsoInclude = offList,
  }) {
    final byRank = {for (final e in ranks.entries) e.value: e.key};
    final raw = <String, double>{
      for (var rank = 0; rank < count; rank++)
        byRank[rank] ?? 'Fillerus sp$rank': 1.0 - rank * 0.02,
      ...alsoInclude,
    };

    return RarityScale(
      key: RarityScaleKey(cell, geoWeek),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }

  // With 40 species the bands land on ranks 0–3 abundant, 4–7 common,
  // 8–17 frequent, 18–29 uncommon, 30–35 scarce, 36–39 rare.
  final mayScale = scaleFor(18, {
    'Passer domesticus': 0,
    'Turdus merula': 1, // abundant · 50
    'Parus major': 2, // abundant · 50
    'Erithacus rubecula': 5, // common · 100
    'Sylvia atricapilla': 6, // common · 100
    'Sitta europaea': 10, // frequent · 200
    'Hirundo rustica': 20, // uncommon · 350
    'Dryocopus martius': 32, // scarce · 600
    'Upupa epops': 38, // rare · 1000
  });

  /// The same place in January. Only the blackcap moves — it has no business
  /// being here in winter, and that is the entire point of week coupling.
  final januaryScale = scaleFor(1, {
    'Passer domesticus': 0,
    'Turdus merula': 1,
    'Parus major': 2,
    'Erithacus rubecula': 5,
    'Sitta europaea': 10,
    'Dryocopus martius': 32,
    'Sylvia atricapilla': 33, // scarce · 600
    'Upupa epops': 38,
  });

  ScoringContext contextAt(
    DateTime when, {
    int threshold = 35,
    bool filterEnabled = true,
    RarityScale? scale,
    GridCell? atCell = cell,
  }) => ScoringContext(
    now: when,
    appliedThreshold: threshold,
    filterEnabled: filterEnabled,
    scale: scale ?? mayScale,
    cell: atCell,
  );

  final may4 = DateTime(2026, 5, 4, 14, 30);
  final january12 = DateTime(2026, 1, 12, 14, 30);

  group('the scales populate every band', () {
    // If this fails, every tier-dependent test below is measuring the wrong
    // thing — which is exactly how the first draft of this file passed while
    // asserting almost nothing.
    test('the May scale covers all six tiers', () {
      final tiers = {
        for (final name in mayScale.rawScores.keys) mayScale.tierFor(name),
      }..remove(null);

      expect(tiers, hasLength(ExploreTier.values.length));
    });
  });

  group('§2.4 · once per species per day (PKT-03)', () {
    test('the first detection of the day scores', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.scored, isTrue);
      expect(outcome.stars, greaterThan(0));
    });

    test('every further detection that day scores nothing', () {
      // "Two hours at the same window is worth exactly as much as ten minutes
      // at the same window." This is the single most important balancing rule.
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(
          isOnLifeList: true,
          isOnYearList: true,
          alreadyScoredToday: true,
        ),
      );

      expect(outcome.scored, isFalse);
      expect(outcome.stars, 0);
      expect(outcome.skipReason, ScoringSkipReason.alreadyScoredToday);
    });

    test('a repeat must not re-add the species to the life list', () {
      // The quiet catastrophe this guards against: a second write would be
      // harmless here, but the same mistake on a *paused* detection burns the
      // first-find ×3 permanently (DAT-11).
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(alreadyScoredToday: true),
      );

      expect(outcome.addToLifeList, isFalse);
      expect(outcome.addToYearList, isFalse);
    });
  });

  group('§2.7 · the worked examples', () {
    /// Runs one row of the specification's table.
    ///
    /// [tier] and [stars] are both asserted: the star count alone cannot tell a
    /// correct tier from a wrong tier that happens to multiply to the same
    /// number.
    void expectRow(
      String description, {
      required String species,
      required SpeciesHistory history,
      required ExploreTier tier,
      required int multiplier,
      required int stars,
      RarityScale? scale,
      DateTime? at,
    }) {
      test(description, () {
        final outcome = engine.scoreDetection(
          scientificName: species,
          confidence: 0.9,
          context: contextAt(at ?? may4, scale: scale),
          history: history,
        );

        expect(outcome.tier, tier, reason: 'tier for $species');
        expect(outcome.multiplier.factor, multiplier);
        expect(outcome.stars, stars, reason: outcome.explanation);
      });
    }

    test('blackbird, second time today → 0', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(
          isOnLifeList: true,
          isOnYearList: true,
          alreadyScoredToday: true,
        ),
      );

      expect(outcome.stars, 0);
    });

    expectRow(
      'blackbird in May, first time today → 50 × 1 = 50',
      species: 'Turdus merula',
      history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      tier: ExploreTier.abundant,
      multiplier: 1,
      stars: 50,
    );

    expectRow(
      'robin, first find ever → 100 × 3 = 300',
      species: 'Erithacus rubecula',
      history: const SpeciesHistory(),
      tier: ExploreTier.common,
      multiplier: 3,
      stars: 300,
    );

    expectRow(
      'great tit, 3rd day this week → 50 × 2 = 100',
      species: 'Parus major',
      history: const SpeciesHistory(
        isOnLifeList: true,
        isOnYearList: true,
        daysThisIsoWeekWithSpecies: 3,
      ),
      tier: ExploreTier.abundant,
      multiplier: 2,
      stars: 100,
    );

    expectRow(
      'great tit, 6th day this week → 50 × 3 = 150',
      species: 'Parus major',
      history: const SpeciesHistory(
        isOnLifeList: true,
        isOnYearList: true,
        daysThisIsoWeekWithSpecies: 6,
      ),
      tier: ExploreTier.abundant,
      multiplier: 3,
      stars: 150,
    );

    expectRow(
      'blackcap in May, first this year → 100 × 2 = 200',
      species: 'Sylvia atricapilla',
      history: const SpeciesHistory(isOnLifeList: true),
      tier: ExploreTier.common,
      multiplier: 2,
      stars: 200,
    );

    expectRow(
      'blackcap in January, first this year → 600 × 2 = 1,200',
      species: 'Sylvia atricapilla',
      history: const SpeciesHistory(isOnLifeList: true),
      tier: ExploreTier.scarce,
      multiplier: 2,
      stars: 1200,
      scale: januaryScale,
      at: january12,
    );

    expectRow(
      'barn swallow, first find ever → 350 × 3 = 1,050',
      species: 'Hirundo rustica',
      history: const SpeciesHistory(),
      tier: ExploreTier.uncommon,
      multiplier: 3,
      stars: 1050,
    );

    expectRow(
      'hoopoe, first find, out of season → 1000 × 3 = 3,000',
      species: 'Upupa epops',
      history: const SpeciesHistory(),
      tier: ExploreTier.rare,
      multiplier: 3,
      stars: 3000,
    );
  });

  group('§2.7 · week coupling', () {
    test('the same bird is worth six times as much in January', () {
      // "Same bird, same rule, six times the value — because in January it has
      // no business being here." The clearest statement of what the whole
      // rank-relative scale is for.
      int starsUnder(RarityScale scale, DateTime when) =>
          engine
              .scoreDetection(
                scientificName: 'Sylvia atricapilla',
                confidence: 0.9,
                context: contextAt(when, scale: scale),
                history: const SpeciesHistory(
                  isOnLifeList: true,
                  isOnYearList: true,
                ),
              )
              .stars;

      final may = starsUnder(mayScale, may4);
      final january = starsUnder(januaryScale, january12);

      expect(may, 100);
      expect(january, 600);
      expect(january / may, 6);
    });

    test('the geoWeek frozen into the event follows the scale', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Sylvia atricapilla',
        confidence: 0.9,
        context: contextAt(january12, scale: januaryScale),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.geoWeek, 1);
    });
  });

  group('§2.5 · only the highest multiplier applies (PKT-07)', () {
    test('a first find that is also a year first is ×3, not ×6', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Upupa epops',
        confidence: 0.95,
        context: contextAt(may4),
        history: const SpeciesHistory(daysThisIsoWeekWithSpecies: 3),
      );

      // Stacked this would be 1000 × 3 × 2 × 2 and the curve would come apart.
      expect(outcome.multiplier, ScoreMultiplier.firstFind);
      expect(outcome.stars, 3000);
    });

    test('3,000 is the ceiling for one species on one day', () {
      // The rarest species, every multiplier eligible at once, maximum
      // confidence. Nothing in the rule table may exceed this.
      for (final firstFind in [true, false]) {
        for (final yearFirst in [true, false]) {
          for (var day = 1; day <= 7; day++) {
            final outcome = engine.scoreDetection(
              scientificName: 'Upupa epops',
              confidence: 0.99,
              context: contextAt(may4),
              history: SpeciesHistory(
                isOnLifeList: !firstFind,
                isOnYearList: !yearFirst,
                daysThisIsoWeekWithSpecies: day,
              ),
            );

            expect(outcome.tier, ExploreTier.rare);
            expect(
              outcome.stars,
              lessThanOrEqualTo(3000),
              reason: 'first=$firstFind year=$yearFirst day=$day',
            );
          }
        }
      }
    });
  });

  group('§2.3 · a species with no tier scores nothing (D20)', () {
    test('an off-list species is skipped, not maximised', () {
      // The rule that gave it top tier and full points was removed. Rule and
      // filter now say the same thing.
      final outcome = engine.scoreDetection(
        scientificName: 'Struthio camelus',
        confidence: 0.99,
        context: contextAt(may4),
        history: const SpeciesHistory(),
      );

      expect(outcome.scored, isFalse);
      expect(outcome.stars, 0);
      expect(outcome.skipReason, ScoringSkipReason.notOnLocalList);
    });

    test('a species the scale has never heard of is also skipped', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Nonexistentia ficta',
        confidence: 0.99,
        context: contextAt(may4),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.notOnLocalList);
    });

    test('and neither reaches the life list', () {
      for (final name in ['Struthio camelus', 'Nonexistentia ficta']) {
        final outcome = engine.scoreDetection(
          scientificName: name,
          confidence: 0.99,
          context: contextAt(may4),
          history: const SpeciesHistory(),
        );

        expect(outcome.addToLifeList, isFalse, reason: name);
      }
    });
  });

  group('PKT-20 · scoring pauses', () {
    test('nothing scores while the species filter is off', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.99,
        context: contextAt(may4, filterEnabled: false),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.scoringPaused);
      expect(outcome.stars, 0);
    });

    test('nothing scores below the confidence floor of 35', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.99,
        context: contextAt(may4, threshold: 20),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.scoringPaused);
    });

    test('a stricter threshold still scores — the rule is asymmetric', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.99,
        context: contextAt(may4, threshold: 90),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.scored, isTrue);
    });

    test('a paused detection never reaches the life list', () {
      // The single most damaging thing this engine could get wrong. A row
      // written here means the child's real first find, weeks later, scores
      // 100 instead of 300 — for a reason nothing in the app can explain.
      for (final paused in [
        contextAt(may4, filterEnabled: false),
        contextAt(may4, threshold: 10),
      ]) {
        final outcome = engine.scoreDetection(
          scientificName: 'Sitta europaea',
          confidence: 0.99,
          context: paused,
          history: const SpeciesHistory(),
        );

        expect(outcome.addToLifeList, isFalse);
        expect(outcome.addToYearList, isFalse);
        expect(outcome.scored, isFalse);
      }
    });

    test('no day bonuses while paused', () {
      final bonuses = engine.bonusesFor(
        context: contextAt(may4, filterEnabled: false),
        speciesCountBefore: 4,
        speciesCountAfter: 5,
        earlyRiserAlreadyAwarded: false,
      );

      expect(bonuses, isEmpty);
    });

    test('pausing wins over every other skip reason', () {
      // Whatever else is wrong with a detection, "scoring is off" is the thing
      // the journal should say — it is the one the child can undo.
      final outcome = engine.scoreDetection(
        scientificName: 'Struthio camelus',
        confidence: 0.01,
        context: contextAt(may4, filterEnabled: false, atCell: null),
        history: const SpeciesHistory(alreadyScoredToday: true),
      );

      expect(outcome.skipReason, ScoringSkipReason.scoringPaused);
    });
  });

  group('§2.6 · day bonuses', () {
    test('the 5th species of the day earns +50', () {
      final bonuses = engine.bonusesFor(
        context: contextAt(may4),
        speciesCountBefore: 4,
        speciesCountAfter: 5,
        earlyRiserAlreadyAwarded: false,
      );

      expect(bonuses.single.stars, 50);
      expect(bonuses.single.key, 'variety_5');
    });

    test('a threshold fires once, not on every later species', () {
      final bonuses = engine.bonusesFor(
        context: contextAt(may4),
        speciesCountBefore: 5,
        speciesCountAfter: 6,
        earlyRiserAlreadyAwarded: false,
      );

      expect(bonuses, isEmpty);
    });

    test('crossing two thresholds at once awards both', () {
      // Unlikely from one detection, but a recomputation can jump.
      final bonuses = engine.bonusesFor(
        context: contextAt(may4),
        speciesCountBefore: 4,
        speciesCountAfter: 10,
        earlyRiserAlreadyAwarded: false,
      );

      expect(bonuses.map((b) => b.stars), containsAll([50, 150]));
    });

    test('a day that reaches 15 species has earned 500 in variety bonuses', () {
      // §2.6: "reaching 15 species yields 50 + 150 + 300 = 500". Awarded here
      // as three separate events, which is what makes a day a staircase.
      final total = engine
          .bonusesFor(
            context: contextAt(may4),
            speciesCountBefore: 0,
            speciesCountAfter: 15,
            earlyRiserAlreadyAwarded: true,
          )
          .fold(0, (sum, bonus) => sum + bonus.stars);

      expect(total, 500);
    });

    test('early riser applies before 09:00 and only once', () {
      final morning = contextAt(DateTime(2026, 5, 4, 7, 30));

      final first = engine.bonusesFor(
        context: morning,
        speciesCountBefore: 1,
        speciesCountAfter: 2,
        earlyRiserAlreadyAwarded: false,
      );
      expect(first.single.key, 'early_riser');

      final second = engine.bonusesFor(
        context: morning,
        speciesCountBefore: 2,
        speciesCountAfter: 3,
        earlyRiserAlreadyAwarded: true,
      );
      expect(second, isEmpty);
    });

    test('no early riser after 09:00', () {
      final bonuses = engine.bonusesFor(
        context: contextAt(DateTime(2026, 5, 4, 9, 1)),
        speciesCountBefore: 1,
        speciesCountAfter: 2,
        earlyRiserAlreadyAwarded: false,
      );

      expect(bonuses, isEmpty);
    });
  });

  group('PKT-15 · the frozen fields', () {
    test('a scoring outcome carries everything the event must freeze', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Sitta europaea',
        confidence: 0.9,
        context: contextAt(may4, threshold: 42),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.baseValue, 200);
      expect(outcome.tier, ExploreTier.frequent);
      expect(outcome.geoWeek, 18);
      expect(outcome.gridCell, cell);
      expect(outcome.appliedThreshold, 42);
      expect(outcome.ruleVersion, ScoringRules.current.version);
    });

    test('the applied threshold is the one in force, not the floor', () {
      // Without this the history's meaning would change every time the slider
      // moves (D16).
      for (final threshold in [35, 50, 75]) {
        final outcome = engine.scoreDetection(
          scientificName: 'Sitta europaea',
          confidence: 0.9,
          context: contextAt(may4, threshold: threshold),
          history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
        );

        expect(outcome.appliedThreshold, threshold);
      }
    });
  });

  group('below the applied threshold', () {
    test('a detection under the bar scores nothing', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.4,
        context: contextAt(may4, threshold: 60),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.belowThreshold);
      expect(outcome.addToLifeList, isFalse);
    });

    test('confidence exactly at the threshold scores', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.6,
        context: contextAt(may4, threshold: 60),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.scored, isTrue);
    });
  });

  group('NFA-06 · deterministic', () {
    test('the same inputs always give the same result', () {
      ScoringOutcome run() => engine.scoreDetection(
        scientificName: 'Hirundo rustica',
        confidence: 0.77,
        context: contextAt(may4),
        history: const SpeciesHistory(daysThisIsoWeekWithSpecies: 3),
      );

      final a = run();
      final b = run();

      expect(a.stars, b.stars);
      expect(a.multiplier, b.multiplier);
      expect(a.tier, b.tier);
      expect(a.dayKey, b.dayKey);
    });
  });

  group('DAT-05 · the day key', () {
    test('is the local calendar day', () {
      expect(contextAt(DateTime(2026, 5, 4, 23, 59)).dayKey, '2026-05-04');
    });

    test('rolls over at midnight, not at some other hour', () {
      expect(contextAt(DateTime(2026, 5, 4, 23, 59)).dayKey, '2026-05-04');
      expect(contextAt(DateTime(2026, 5, 5, 0, 1)).dayKey, '2026-05-05');
    });

    test('pads single-digit months and days', () {
      expect(contextAt(DateTime(2026, 1, 7, 12)).dayKey, '2026-01-07');
    });

    test('survives a DST transition without losing or repeating a day', () {
      // Central European clocks jump forward on 29 March 2026 and back on
      // 25 October. A day key built from anything other than the local calendar
      // date would produce a 23- or 25-hour day here.
      for (final day in [
        DateTime(2026, 3, 29, 1, 30),
        DateTime(2026, 3, 29, 4, 30),
        DateTime(2026, 10, 25, 1, 30),
        DateTime(2026, 10, 25, 4, 30),
      ]) {
        final expected =
            '${day.year}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}';
        expect(contextAt(day).dayKey, expected);
      }
    });
  });

  group('no location', () {
    test('scores nothing rather than inventing a value', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4, atCell: null),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.noLocation);
      expect(outcome.addToLifeList, isFalse);
    });

    test('a missing scale is treated the same way', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: ScoringContext(
          now: may4,
          appliedThreshold: 35,
          filterEnabled: true,
          cell: cell,
        ),
        history: const SpeciesHistory(),
      );

      expect(outcome.skipReason, ScoringSkipReason.noLocation);
    });
  });

  group('PKT-16 · every award explains itself', () {
    test('a multiplied award shows the arithmetic', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Erithacus rubecula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(isOnLifeList: true),
      );

      // "100 × 2 = 200" — a child does check the maths, and if the numbers
      // look arbitrary they stop trusting them (principle 6).
      expect(outcome.explanation, '100 × 2 = 200');
    });

    test('an unmultiplied award is just the number', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4),
        history: const SpeciesHistory(isOnLifeList: true, isOnYearList: true),
      );

      expect(outcome.explanation, '50');
    });

    test('a skipped detection explains nothing, and says so', () {
      final outcome = engine.scoreDetection(
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4, filterEnabled: false),
        history: const SpeciesHistory(),
      );

      expect(outcome.explanation, isEmpty);
    });
  });
}
