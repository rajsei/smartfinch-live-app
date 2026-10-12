// =============================================================================
// The Collection — SAM-02, SAM-03, SAM-05, SAM-16, SAM-17
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
//
// And since 2026-10-12 the album *is* that table: it shows what was found and
// nothing else. The species still to find are Explore's.
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
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/providers/settings_providers.dart';
import 'package:smartfinch/shared/services/taxonomy_service.dart';

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
    CollectionEntry entry({DateTime? thisYear, int? stars}) => CollectionEntry(
      scientificName: 'Turdus merula',
      commonName: 'Blackbird',
      taxonGroup: 'Aves',
      collectedAt: DateTime(2025, 6),
      tier: stars == null ? null : ExploreTier.abundant,
      stars: stars,
      collectedThisYearAt: thisYear,
    );

    test('every entry is in the life list; only this year\'s in the year '
        'list', () {
      // A species found last June and not heard since January is in the
      // album and not in the year list. That difference is the year list.
      final lastYearOnly = entry();
      final heardAgain = entry(thisYear: may4);

      expect(lastYearOnly.isIn(CollectionScope.all), isTrue);
      expect(lastYearOnly.isIn(CollectionScope.thisYear), isFalse);
      expect(heardAgain.isIn(CollectionScope.thisYear), isTrue);
    });

    test('the year view orders by the first find of the year', () {
      final heardAgain = entry(thisYear: may4);

      expect(heardAgain.dateIn(CollectionScope.all), DateTime(2025, 6));
      expect(heardAgain.dateIn(CollectionScope.thisYear), may4);
    });

    test('no level here this week means no value, not zero', () {
      expect(entry().isHereThisWeek, isFalse);
      expect(entry(stars: 50).isHereThisWeek, isTrue);
    });
  });

  group('SAM-05 · progress', () {
    test('is against the local list, not against everything', () {
      // 37 of 128 is a number a child can act on. 37 of 9,789 is not.
      const progress = CollectionProgress(collected: 37, total: 128);

      expect(progress.fraction, closeTo(37 / 128, 1e-9));
    });

    test('the year list counts its own', () {
      const progress = CollectionProgress(
        collected: 37,
        collectedThisYear: 12,
        total: 128,
      );

      expect(progress.collectedIn(CollectionScope.all), 37);
      expect(progress.collectedIn(CollectionScope.thisYear), 12);
      expect(
        progress.fractionIn(CollectionScope.thisYear),
        closeTo(12 / 128, 1e-9),
      );
    });

    test('an empty region does not divide by zero', () {
      const progress = CollectionProgress(collected: 0, total: 0);
      expect(progress.fraction, 0);
    });
  });

  group('the album is the life list', () {
    ExploreSpecies local(String name, String common, ExploreTier tier) =>
        ExploreSpecies(
          scientificName: name,
          commonName: common,
          geoScore: 50,
          rawGeoScore: 0.5,
          tier: tier,
        );

    Future<ProviderContainer> containerWith({
      required Map<String, DateTime> collected,
      Map<String, DateTime> thisYear = const {},
      Map<String, ExploreSpecies> localList = const {},
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          effectiveSpeciesLocaleProvider.overrideWith((ref) => 'en'),
          collectedSpeciesProvider.overrideWith((ref) async => collected),
          collectedThisYearProvider.overrideWith((ref) async => thisYear),
          collectionLocalSpeciesProvider.overrideWith(
            (ref) async => localList,
          ),
          taxonomyServiceProvider.overrideWith(
            (ref) async => TaxonomyService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    final localList = {
      'Turdus merula': local(
        'Turdus merula',
        'Blackbird',
        ExploreTier.abundant,
      ),
      'Upupa epops': local('Upupa epops', 'Hoopoe', ExploreTier.rare),
    };

    test('a species not found yet is not in the album', () async {
      // It is in Explore, which lists everything that occurs here. The album
      // is what the child has.
      final container = await containerWith(
        collected: {'Turdus merula': may4},
        localList: localList,
      );

      final entries = await container.read(collectionEntriesProvider.future);

      expect(entries.map((e) => e.scientificName), ['Turdus merula']);
      expect(entries.single.commonName, 'Blackbird');
      expect(entries.single.stars, 50);
    });

    test('a found species not here this week stays in the album', () async {
      // A swallow collected in June is still collected in December. Building
      // the album from the local list would make it vanish every winter.
      final container = await containerWith(
        collected: {'Turdus merula': may4, 'Hirundo rustica': DateTime(2025, 6)},
        localList: localList,
      );

      final entries = await container.read(collectionEntriesProvider.future);
      final swallow = entries.singleWhere(
        (e) => e.scientificName == 'Hirundo rustica',
      );

      expect(entries, hasLength(2));
      expect(swallow.stars, isNull);
      expect(swallow.isHereThisWeek, isFalse);
    });

    test('newest find first', () async {
      final container = await containerWith(
        collected: {'Hirundo rustica': DateTime(2025, 6), 'Turdus merula': may4},
        localList: localList,
      );

      final entries = await container.read(collectionEntriesProvider.future);

      expect(entries.map((e) => e.scientificName), [
        'Turdus merula',
        'Hirundo rustica',
      ]);
    });

    test('progress counts finds on the local list only', () async {
      final container = await containerWith(
        collected: {'Turdus merula': may4, 'Hirundo rustica': DateTime(2025, 6)},
        thisYear: {'Turdus merula': may4},
        localList: localList,
      );

      final progress = await container.read(collectionProgressProvider.future);

      expect(progress.total, 2);
      expect(progress.collected, 1);
      expect(progress.collectedThisYear, 1);
    });

    test('without a location the album still opens', () async {
      // Only the values and the progress line need the local list. What the
      // child has found does not depend on where they are standing.
      final container = await containerWith(
        collected: {'Turdus merula': may4},
      );

      final entries = await container.read(collectionEntriesProvider.future);
      final progress = await container.read(collectionProgressProvider.future);

      expect(entries, hasLength(1));
      expect(entries.single.stars, isNull);
      expect(progress.total, 0);
    });
  });

  group('the album on screen', () {
    Future<void> pump(
      WidgetTester tester, {
      required List<CollectionEntry> entries,
      CollectionProgress progress = const CollectionProgress(
        collected: 0,
        total: 0,
      ),
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
            collectionProgressProvider.overrideWith((ref) async => progress),
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
      bool thisYear = false,
      int? stars = 50,
      String group = 'Aves',
      DateTime? collectedAt,
    }) => CollectionEntry(
      scientificName: name,
      commonName: name,
      taxonGroup: group,
      collectedAt: collectedAt ?? DateTime(2025, 6),
      tier: stars == null ? null : ExploreTier.abundant,
      stars: stars,
      collectedThisYearAt: thisYear ? may4 : null,
    );

    testWidgets('SAM-03 · every card says what it is worth, and where', (
      tester,
    ) async {
      await pump(tester, entries: [entryFor('Hoopoe', stars: 1000)]);

      // Both halves of the label are load-bearing: the value moves with the
      // season and with the place, and a child told that in advance reads the
      // movement as the game rather than as a bug.
      expect(find.text('Here, this week: 1000 ⭐'), findsOneWidget);
    });

    testWidgets('a species not here this week says so instead of a value', (
      tester,
    ) async {
      await pump(tester, entries: [entryFor('Swallow', stars: null)]);

      expect(find.text('Swallow'), findsOneWidget);
      expect(find.text('Not here this week'), findsOneWidget);
      expect(find.textContaining('⭐'), findsNothing);
    });

    testWidgets('SAM-05 · progress is against the local list', (tester) async {
      await pump(
        tester,
        entries: [entryFor('Blackbird'), entryFor('Robin')],
        progress: const CollectionProgress(collected: 2, total: 3),
      );

      expect(find.text('2 of 3 species in your region'), findsOneWidget);
    });

    testWidgets('no local list, no progress line', (tester) async {
      // "0 of 0" would say nothing true.
      await pump(tester, entries: [entryFor('Blackbird')]);

      expect(find.textContaining('species in your region'), findsNothing);
      expect(find.text('Blackbird'), findsOneWidget);
    });

    testWidgets('there is no "only mine" any more', (tester) async {
      // Everything in the album is the child's. The species still to find
      // are in Explore.
      await pump(tester, entries: [entryFor('Blackbird')]);

      expect(find.text('All'), findsOneWidget);
      expect(find.text('This year'), findsOneWidget);
      expect(find.text('Only mine'), findsNothing);
    });

    testWidgets('SAM-17 · the group filter narrows the album', (tester) async {
      await pump(
        tester,
        entries: [
          entryFor('Blackbird'),
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

    testWidgets('an empty album explains itself and points to Explore', (
      tester,
    ) async {
      await pump(tester, entries: const []);

      expect(find.text('Your collection is still empty'), findsOneWidget);
      expect(find.textContaining('Every bird you hear lands here.'), findsOne);
      expect(find.textContaining('Explore'), findsOneWidget);
    });

    testWidgets('a filter that matches nothing says something different', (
      tester,
    ) async {
      // "You have nothing yet" and "nothing from this group yet" are two
      // different facts, and telling a child the first when the second is
      // true would be discouraging for no reason.
      await pump(tester, entries: [entryFor('Blackbird')]);

      await tester.tap(find.text('Amphibians'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing from this group yet'), findsOneWidget);
      expect(find.text('Your collection is still empty'), findsNothing);
    });
  });

  group('SAM-16 · the year list as a second collection', () {
    CollectionEntry species(
      String name, {
      bool thisYear = false,
      DateTime? collectedAt,
      DateTime? collectedThisYearAt,
    }) => CollectionEntry(
      scientificName: name,
      commonName: name,
      taxonGroup: 'Aves',
      collectedAt: collectedAt ?? DateTime(2025, 6),
      tier: ExploreTier.abundant,
      stars: 50,
      collectedThisYearAt: collectedThisYearAt ?? (thisYear ? may4 : null),
    );

    Future<void> pumpAlbum(
      WidgetTester tester,
      List<CollectionEntry> entries, {
      CollectionProgress progress = const CollectionProgress(
        collected: 0,
        total: 0,
      ),
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
            collectionProgressProvider.overrideWith((ref) async => progress),
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

    testWidgets('the album offers both', (tester) async {
      await pumpAlbum(tester, [species('Blackbird')]);

      expect(find.text('All'), findsOneWidget);
      expect(find.text('This year'), findsOneWidget);
    });

    testWidgets('the year view shows only what was heard this year', (
      tester,
    ) async {
      await pumpAlbum(tester, [
        species('Blackcap'),
        species('Blackbird', thisYear: true),
      ]);

      expect(find.text('Blackcap'), findsOneWidget);

      await tester.tap(find.text('This year'));
      await tester.pumpAndSettle();

      expect(find.text('Blackbird'), findsOneWidget);
      expect(find.text('Blackcap'), findsNothing);
    });

    testWidgets('the year view puts the newest find of the year first', (
      tester,
    ) async {
      // Found first in 2024, heard again in May; found first in 2025, heard
      // again in March. On the life list the second is newer; this year the
      // first is.
      await pumpAlbum(tester, [
        species(
          'Robin',
          collectedAt: DateTime(2025, 6),
          collectedThisYearAt: DateTime(2026, 3, 2),
        ),
        species(
          'Blackbird',
          collectedAt: DateTime(2024, 6),
          collectedThisYearAt: may4,
        ),
      ]);

      await tester.tap(find.text('This year'));
      await tester.pumpAndSettle();

      final blackbird = tester.getTopLeft(find.text('Blackbird'));
      final robin = tester.getTopLeft(find.text('Robin'));
      expect(blackbird.dx < robin.dx || blackbird.dy < robin.dy, isTrue);
    });

    testWidgets('its progress line says "this year", not the life total', (
      tester,
    ) async {
      await pumpAlbum(
        tester,
        [species('Blackcap'), species('Blackbird', thisYear: true)],
        progress: const CollectionProgress(
          collected: 2,
          collectedThisYear: 1,
          total: 2,
        ),
      );

      expect(find.text('2 of 2 species in your region'), findsOneWidget);

      await tester.tap(find.text('This year'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 species this year'), findsOneWidget);
    });

    testWidgets('an empty year does not claim the collection is empty', (
      tester,
    ) async {
      // In January the life list is full and the year list is not. Telling a
      // child their collection is empty would be plainly wrong.
      await pumpAlbum(tester, [species('Blackcap')]);

      await tester.tap(find.text('This year'));
      await tester.pumpAndSettle();

      expect(find.text('Nothing this year yet'), findsOneWidget);
      expect(find.text('Your collection is still empty'), findsNothing);
      // And it says why, so the reset reads as the game rather than as loss.
      expect(find.textContaining('starts again every January'), findsOneWidget);
    });
  });
}
