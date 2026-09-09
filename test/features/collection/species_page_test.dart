// =============================================================================
// The species page — SAM-06, SAM-11
// =============================================================================
//
// Two halves, and each has one thing that would be silently wrong.
//
//   **`SAM-06`, the personal half.** It has to read the *raw* detections as
//   well as the scoring layer: a bird heard all evening with scoring paused
//   was still heard (`LOG-15`), and a page that said "never" would be calling
//   the child a liar about their own afternoon.
//
//   ⚠️ **"Where" is the name the child typed** (`LOG-13`), never a coordinate.
//   The app coarsens location before storing it (`NFA-08`) and the shared day
//   image carries no place at all (`LOG-11`, `KID-07`). A species page that
//   reintroduced a location would undo all three, and nothing on screen would
//   look wrong.
//
//   **`SAM-11`, the register.** A missing rewrite is the ordinary case — only
//   German and English exist, per `SET-10` — so the fallback to the adult
//   description is the behaviour that has to hold, not the exception.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/collection/collection_providers.dart';
import 'package:smartfinch/features/collection/collection_repository.dart';
import 'package:smartfinch/features/explore/widgets/species_info_overlay.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/journal/journal_repository.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/shared/services/child_profile_service.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

void main() {
  const cell = GridCell(508, 129);

  /// Monday 4 May 2026.
  final may4 = DateTime(2026, 5, 4, 14, 30);

  final scale = () {
    final raw = <String, double>{
      for (var rank = 0; rank < 40; rank++)
        'Species sp$rank': 1.0 - rank * 0.02,
    };
    return RarityScale(
      key: const RarityScaleKey(cell, 18),
      scale: ExploreTierScale.fromGeoScores(raw),
      rawScores: raw,
    );
  }();

  group('SAM-06 · your own history with a species', () {
    late AppDatabase db;
    late ScoringRepository scoring;
    late CollectionRepository collection;
    late JournalRepository journal;
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
      journal = JournalRepository(db);
      sessionId = await scoring.startSession(startedAt: may4, cell: cell);
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

    test('a species never heard has nothing personal to say', () async {
      final stats = await collection.personalStatsFor('Species sp0');

      expect(stats.isEmpty, isTrue);
      expect(stats.isCollected, isFalse);
      expect(stats.timesHeard, 0);
    });

    test('how often, and on how many days', () async {
      // Three detections across two days: "3 times on 2 days", not "3 days".
      await hear('Species sp0');
      await hear('Species sp0', at: may4.add(const Duration(hours: 1)));
      await hear('Species sp0', at: may4.add(const Duration(days: 1)));

      final stats = await collection.personalStatsFor('Species sp0');

      expect(stats.timesHeard, 3);
      expect(stats.daysHeard, 2);
    });

    test('first and last are the ends of the history', () async {
      await hear('Species sp0');
      await hear('Species sp0', at: may4.add(const Duration(days: 5)));

      final stats = await collection.personalStatsFor('Species sp0');

      expect(stats.firstHeardAt, isNotNull);
      expect(stats.lastHeardAt, may4.add(const Duration(days: 5)));
      expect(stats.isCollected, isTrue);
    });

    test('the stars it has earned add up across every day', () async {
      await hear('Species sp0');
      await hear('Species sp0', at: may4.add(const Duration(days: 1)));

      final stats = await collection.personalStatsFor('Species sp0');
      final day = await journal.detailFor('2026-05-04');

      expect(stats.stars, greaterThan(0));
      expect(stats.stars, greaterThan(day.scored.single.stars));
    });

    test('⚠️ a bird heard outside scoring was still heard', () async {
      // LOG-15. A page saying "never" about an afternoon the child spent
      // listening would be calling them a liar about their own day.
      await hear('Species sp0', filterEnabled: false);

      final stats = await collection.personalStatsFor('Species sp0');

      expect(stats.timesHeard, 1);
      expect(stats.isEmpty, isFalse);
      // It scored nothing and is not collected, and the page says both.
      expect(stats.isCollected, isFalse);
      expect(stats.stars, 0);
    });

    test('where means the name the child typed', () async {
      await journal.renameSession(sessionId, 'Oma');
      await hear('Species sp0');

      final stats = await collection.personalStatsFor('Species sp0');

      expect(stats.places, ['Oma']);
    });

    test('an unnamed walk contributes no place, not an empty one', () async {
      await hear('Species sp0');

      expect(
        (await collection.personalStatsFor('Species sp0')).places,
        isEmpty,
      );
    });

    test('places come back newest first', () async {
      // "Where did I last hear it" is the question being asked.
      await journal.renameSession(sessionId, 'Schulweg');
      await hear('Species sp0');

      final later = await scoring.startSession(
        startedAt: may4.add(const Duration(days: 1)),
        cell: cell,
      );
      await journal.renameSession(later, 'Oma');
      await hear(
        'Species sp0',
        at: may4.add(const Duration(days: 1)),
        inSession: later,
      );

      final stats = await collection.personalStatsFor('Species sp0');
      expect(stats.places, ['Oma', 'Schulweg']);
    });

    test('another species history does not leak into this one', () async {
      await hear('Species sp0');
      await hear('Species sp1');
      await hear('Species sp1', at: may4.add(const Duration(days: 1)));

      expect((await collection.personalStatsFor('Species sp0')).timesHeard, 1);
      expect((await collection.personalStatsFor('Species sp1')).timesHeard, 2);
    });
  });

  group('SAM-06 · the tile on screen', () {
    Future<void> pump(WidgetTester tester, SpeciesPersonalStats stats) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            speciesPersonalStatsProvider.overrideWith(
              (ref, name) async => stats,
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: SpeciesPersonalTile(scientificName: 'Turdus merula'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says how often, when and where', (tester) async {
      await pump(
        tester,
        SpeciesPersonalStats(
          scientificName: 'Turdus merula',
          firstHeardAt: DateTime(2026, 3, 1),
          lastHeardAt: DateTime(2026, 5, 4),
          timesHeard: 12,
          daysHeard: 5,
          stars: 450,
          places: const ['Oma', 'Schulweg'],
        ),
      );

      expect(find.text('You and this bird'), findsOneWidget);
      expect(find.text('Heard 12 times on 5 days'), findsOneWidget);
      expect(find.text('At: Oma · Schulweg'), findsOneWidget);
      expect(find.text('⭐ 450'), findsOneWidget);
    });

    testWidgets('a bird never heard gets no panel at all', (tester) async {
      // An empty box reading "0 times" would turn the album into a report
      // card about everything the child has not managed.
      await pump(
        tester,
        const SpeciesPersonalStats(scientificName: 'Turdus merula'),
      );

      expect(find.text('You and this bird'), findsNothing);
    });

    testWidgets('an unnamed walk leaves the place line out', (tester) async {
      await pump(
        tester,
        SpeciesPersonalStats(
          scientificName: 'Turdus merula',
          lastHeardAt: DateTime(2026, 5, 4),
          timesHeard: 1,
          daysHeard: 1,
        ),
      );

      expect(find.textContaining('At:'), findsNothing);
      expect(find.text('Heard 1 times on 1 days'), findsOneWidget);
    });

    testWidgets('⚠️ no coordinate ever reaches the page', (tester) async {
      // NFA-07/NFA-08. The only "where" is the child's own word for it, and
      // nothing on screen would look wrong if a cell key leaked in here.
      await pump(
        tester,
        SpeciesPersonalStats(
          scientificName: 'Turdus merula',
          lastHeardAt: DateTime(2026, 5, 4),
          timesHeard: 1,
          daysHeard: 1,
          places: const ['Oma'],
        ),
      );

      // A grid cell is stored as "50.8,12.9" — look for that shape rather
      // than for a bare comma, which every formatted date contains.
      expect(
        find.textContaining(RegExp(r'-?\d+\.\d+,-?\d+\.\d+')),
        findsNothing,
      );
      expect(find.text('At: Oma'), findsOneWidget);
    });
  });

  group('SAM-11 · the child-register profile', () {
    /// A bundle carrying a small stand-in file, so the test does not depend
    /// on the editorial content of the real asset.
    ChildProfileService serviceWith(String json) {
      return ChildProfileService(bundle: _FakeBundle(json));
    }

    test('a rewritten species comes back in the right language', () async {
      final service = serviceWith('''
        {
          "Turdus merula": {
            "de": {"text": "Schwarz mit gelbem Schnabel.", "call": "Flötend."},
            "en": {"text": "Black with a yellow bill.", "call": "Flutey."}
          }
        }
      ''');

      final de = await service.profileFor('Turdus merula', 'de');
      final en = await service.profileFor('Turdus merula', 'en');

      expect(de?.text, 'Schwarz mit gelbem Schnabel.');
      expect(en?.text, 'Black with a yellow bill.');
    });

    test('a region tag still finds its language', () async {
      // `de_DE`, `de-AT` and `de` all want the German text.
      final service = serviceWith('''
        {"Turdus merula": {"de": {"text": "Amsel."}}}
      ''');

      expect(
        (await service.profileFor('Turdus merula', 'de_DE'))?.text,
        'Amsel.',
      );
      expect(
        (await service.profileFor('Turdus merula', 'de-AT'))?.text,
        'Amsel.',
      );
    });

    test('⚠️ a locale with no rewrite gets null, not English', () async {
      // SET-10: a Czech child reading an English paragraph is worse served
      // than one reading the Czech *adult* description. Null is the signal to
      // fall back, and falling back is the ordinary case.
      final service = serviceWith('''
        {"Turdus merula": {"de": {"text": "Amsel."}, "en": {"text": "Blackbird."}}}
      ''');

      expect(await service.profileFor('Turdus merula', 'cs'), isNull);
    });

    test('a species with no rewrite gets null', () async {
      final service = serviceWith('{"Turdus merula": {"de": {"text": "x"}}}');

      expect(await service.profileFor('Parus major', 'de'), isNull);
    });

    test('a species with no honest mnemonic simply has none', () async {
      // Inventing one would teach a child something false about a bird.
      final service = serviceWith('''
        {"Turdus merula": {"de": {"text": "Amsel."}}}
      ''');

      final profile = await service.profileFor('Turdus merula', 'de');
      expect(profile?.hasCall, isFalse);
    });

    test('the editorial note in the file is not a species', () async {
      final service = serviceWith('''
        {
          "_readme": ["notes about the file"],
          "Turdus merula": {"de": {"text": "Amsel."}}
        }
      ''');

      expect(await service.profileCount, 1);
    });

    test('a broken file falls back rather than throwing', () async {
      // Every species then shows the adult description — exactly what happens
      // for the hundred species that have no rewrite yet.
      final service = serviceWith('not json at all');

      expect(await service.profileFor('Turdus merula', 'de'), isNull);
      expect(await service.profileCount, 0);
    });
  });

  group('SAM-11 · the shipped profiles', () {
    late ChildProfileService service;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      service = ChildProfileService();
    });

    test('every profile has both German and English', () async {
      // SET-10 fixed the register at two languages. A species with only one
      // would silently show an adult paragraph in the other.
      final missing = <String>[];
      for (final name in await _shippedNames()) {
        for (final locale in ChildProfileService.availableLocales) {
          if (await service.profileFor(name, locale) == null) {
            missing.add('$name/$locale');
          }
        }
      }

      expect(missing, isEmpty);
    });

    test('every text is more than one sentence and less than a page', () async {
      // "2-3 sentences" is the requirement. A one-liner is a label, and a
      // paragraph is the adult description under a new name.
      for (final name in await _shippedNames()) {
        final profile = (await service.profileFor(name, 'de'))!;
        expect(
          profile.text.length,
          inInclusiveRange(80, 400),
          reason: '$name is the wrong length for a child profile',
        );
      }
    });
  });
}

/// The scientific names in the shipped asset.
Future<List<String>> _shippedNames() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final raw = await rootBundle.loadString(ChildProfileService.assetPath);
  return [
    for (final key
        in (const JsonCodec().decode(raw) as Map).keys.cast<String>())
      if (!key.startsWith('_')) key,
  ];
}

/// Serves one string for any asset path.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.contents);

  final String contents;

  @override
  Future<ByteData> load(String key) async {
    final bytes = const Utf8Codec().encode(contents);
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }
}
