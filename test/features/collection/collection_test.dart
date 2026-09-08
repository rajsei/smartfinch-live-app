// =============================================================================
// The Collection — SAM-02, SAM-03, SAM-04, SAM-05, SAM-17
// =============================================================================
//
// One rule matters more than the rest, and it is not a layout rule:
//
//   **The album and the scoring engine read the same table.**
//
// "Found" comes from `LifeSpecies`, which is what the first-find ×3 checks
// (`PKT-04`). If the Collection drew its own conclusions — from raw
// detections, say — a child could see a species in their album and then be
// awarded ×3 for "finding" it a week later, with nothing in the app able to
// explain which of the two was lying.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/collection/collection_providers.dart';
import 'package:smartfinch/features/collection/collection_repository.dart';
import 'package:smartfinch/features/collection/collection_screen.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  const cell = GridCell(508, 129);
  final may4 = DateTime(2026, 5, 4, 14, 30);

  final scale = () {
    const ranks = {
      'Turdus merula': 1, // abundant · 50
      'Erithacus rubecula': 5, // common · 100
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

  group('what counts as collected', () {
    late AppDatabase db;
    late ScoringRepository scoring;
    late CollectionRepository collection;
    late String sessionId;

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
      collection = CollectionRepository(db);
      sessionId = await scoring.startSession(startedAt: may4);
    });

    tearDown(() async => db.close());

    Future<void> hear(String name, {bool filterEnabled = true}) => scoring
        .recordDetection(
          sessionId: sessionId,
          scientificName: name,
          confidence: 0.9,
          context: contextAt(may4, filterEnabled: filterEnabled),
        )
        .then((_) {});

    test('a scoring detection lands in the album', () async {
      await hear('Turdus merula');

      final collected = await collection.collected();
      expect(collected.keys, ['Turdus merula']);
      expect(collected['Turdus merula'], may4);
    });

    test('⚠️ a paused detection does not', () async {
      // The rule the whole album rests on. It is in the journal with its
      // recording (LOG-15); what it is not is collected.
      await hear('Turdus merula', filterEnabled: false);

      expect(await collection.collected(), isEmpty);
      expect(await collection.count(), 0);
    });

    test('an off-list species does not either', () async {
      await hear('Struthio camelus');

      expect(await collection.collected(), isEmpty);
    });

    test('hearing it again does not move the date', () async {
      // The album shows when the child *first* heard it, which is the date
      // that means something to them.
      await hear('Turdus merula');
      await scoring.recordDetection(
        sessionId: sessionId,
        scientificName: 'Turdus merula',
        confidence: 0.9,
        context: contextAt(may4.add(const Duration(days: 3))),
      );

      expect((await collection.collected())['Turdus merula'], may4);
    });

    test('the year list is a second collection', () async {
      // SAM-16: it empties every January, so it is kept apart from the life
      // list rather than derived from it.
      await hear('Turdus merula');

      expect(await collection.collectedIn(2026), hasLength(1));
      expect(await collection.collectedIn(2025), isEmpty);
    });

    test('an empty album is empty, not an error', () async {
      expect(await collection.collected(), isEmpty);
      expect(await collection.count(), 0);
    });
  });

  group('CollectionEntry', () {
    const entry = CollectionEntry(
      scientificName: 'Turdus merula',
      commonName: 'Blackbird',
      tier: ExploreTier.abundant,
      stars: 50,
      taxonGroup: 'Aves',
    );

    test('an entry without a date is still open', () {
      expect(entry.isCollected, isFalse);
    });

    test('a date is what makes it collected', () {
      expect(
        CollectionEntry(
          scientificName: entry.scientificName,
          commonName: entry.commonName,
          tier: entry.tier,
          stars: entry.stars,
          taxonGroup: entry.taxonGroup,
          collectedAt: may4,
        ).isCollected,
        isTrue,
      );
    });
  });

  group('SAM-05 · progress', () {
    test('is against the local list, not against everything', () {
      // 37 of 128 is a number a child can act on. 37 of 9,789 is not.
      const progress = CollectionProgress(collected: 37, total: 128);

      expect(progress.fraction, closeTo(37 / 128, 1e-9));
    });

    test('an empty region does not divide by zero', () {
      const progress = CollectionProgress(collected: 0, total: 0);
      expect(progress.fraction, 0);
    });
  });

  group('the album on screen', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<CollectionEntry> entries,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            collectionEntriesProvider.overrideWith((ref) async => entries),
            collectionProgressProvider.overrideWith(
              (ref) async => CollectionProgress(
                collected: entries.where((e) => e.isCollected).length,
                total: entries.length,
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CollectionScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    CollectionEntry entryFor(
      String name, {
      bool collected = false,
      int stars = 50,
      String group = 'Aves',
    }) => CollectionEntry(
      scientificName: name,
      commonName: name,
      tier: ExploreTier.abundant,
      stars: stars,
      taxonGroup: group,
      collectedAt: collected ? may4 : null,
    );

    testWidgets('SAM-04 · open species are shown, not hidden', (tester) async {
      // The Pokédex effect rests on the contrast: a grid where some cells
      // carry a bird and others visibly do not is what makes a child want to
      // fill it. A grid of only what you already have has nothing to fill.
      await pump(
        tester,
        entries: [entryFor('Blackbird', collected: true), entryFor('Hoopoe')],
      );

      expect(find.text('Blackbird'), findsOneWidget);
      expect(find.text('Hoopoe'), findsOneWidget);
    });

    testWidgets('an open species keeps its name', (tester) async {
      // The album is a wanted list, and a row of question marks is not one.
      await pump(tester, entries: [entryFor('Hoopoe', stars: 1000)]);

      expect(find.text('Hoopoe'), findsOneWidget);
    });

    testWidgets('SAM-03 · every card says what it is worth, and where', (
      tester,
    ) async {
      await pump(tester, entries: [entryFor('Hoopoe', stars: 1000)]);

      // Both halves of the label are load-bearing: the value moves with the
      // season and with the place, and a child told that in advance reads the
      // movement as the game rather than as a bug.
      expect(find.text('Here, this week: 1000 ⭐'), findsOneWidget);
    });

    testWidgets('SAM-05 · progress is against the local list', (tester) async {
      await pump(
        tester,
        entries: [
          entryFor('Blackbird', collected: true),
          entryFor('Robin', collected: true),
          entryFor('Hoopoe'),
        ],
      );

      expect(find.text('2 of 3 species in your region'), findsOneWidget);
    });

    testWidgets('SAM-17 · the group filter narrows the album', (tester) async {
      await pump(
        tester,
        entries: [
          entryFor('Blackbird', collected: true),
          entryFor('Common frog', group: 'Amphibia'),
        ],
      );

      expect(find.text('Common frog'), findsOneWidget);

      await tester.tap(find.text('Birds'));
      await tester.pumpAndSettle();

      expect(find.text('Blackbird'), findsOneWidget);
      expect(find.text('Common frog'), findsNothing);
    });

    testWidgets('SAM-17 · all groups are shown by default', (tester) async {
      // A frog or a field cricket in the album is a strong draw for this age
      // group, and the non-bird groups call when bird activity drops.
      await pump(
        tester,
        entries: [
          entryFor('Blackbird'),
          entryFor('Common frog', group: 'Amphibia'),
          entryFor('Red squirrel', group: 'Mammalia'),
          entryFor('Field cricket', group: 'Insecta'),
        ],
      );

      for (final name in [
        'Blackbird',
        'Common frog',
        'Red squirrel',
        'Field cricket',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('"only mine" is a filter, not the starting state', (
      tester,
    ) async {
      await pump(
        tester,
        entries: [entryFor('Blackbird', collected: true), entryFor('Hoopoe')],
      );

      expect(find.text('Hoopoe'), findsOneWidget);

      await tester.tap(find.text('Only mine'));
      await tester.pumpAndSettle();

      expect(find.text('Blackbird'), findsOneWidget);
      expect(find.text('Hoopoe'), findsNothing);
    });

    testWidgets('an empty album explains itself rather than looking broken', (
      tester,
    ) async {
      await pump(tester, entries: [entryFor('Hoopoe')]);

      await tester.tap(find.text('Only mine'));
      await tester.pumpAndSettle();

      expect(find.text('Your collection is still empty'), findsOneWidget);
      expect(find.text('Every bird you hear lands here.'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing says something different', (
      tester,
    ) async {
      // "You have nothing yet" and "nothing here matches this filter" are two
      // different facts, and telling a child the first when the second is true
      // would be discouraging for no reason.
      await pump(tester, entries: [entryFor('Blackbird', collected: true)]);

      await tester.tap(find.text('Amphibians'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing in this group here'), findsOneWidget);
      expect(find.text('Your collection is still empty'), findsNothing);
    });
  });
}
