// =============================================================================
// The avatar on screen, and the level behind it — AVA-01/02/05, HOME-07
// =============================================================================
//
// Three claims worth holding.
//
//   **The floor is written while playing.** `highestLevelReached` is a
//   ratchet, and a ratchet that is only ever *read* is not one. If the scoring
//   repository stops raising it, everything still looks right until the first
//   rebalancing — which is exactly when nobody is looking at this.
//
//   **One widget, two screens** (`AVA-01`). The home screen and the points
//   overview must not be able to show different levels.
//
//   **The name never becomes a text field** (`AVA-05`, `KID-07`). The whole
//   reason for a preset list is that free text is a moderation surface the app
//   has decided not to acquire.
// =============================================================================

import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/avatar/avatar_name_sheet.dart';
import 'package:smartfinch/features/avatar/avatar_providers.dart';
import 'package:smartfinch/features/avatar/level_ladder.dart';
import 'package:smartfinch/features/avatar/widgets/avatar_card.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  const cell = GridCell(508, 129);
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

  group('⚠️ the level floor is written while playing (AUS-12)', () {
    late AppDatabase db;
    late ScoringRepository scoring;
    late String sessionId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      scoring = ScoringRepository(db);
      sessionId = await scoring.startSession(startedAt: may4, cell: cell);
    });

    tearDown(() async => db.close());

    Future<void> hear(String name, {DateTime? at}) => scoring
        .recordDetection(
          sessionId: sessionId,
          scientificName: name,
          confidence: 0.9,
          context: ScoringContext(
            now: at ?? may4,
            appliedThreshold: 35,
            filterEnabled: true,
            scale: scale,
            cell: cell,
          ),
        )
        .then((_) {});

    Future<UserProfile> profile() =>
        (db.select(db.userProfiles)
          ..where((p) => p.id.equals(kDefaultProfileId))).getSingle();

    test('a fresh profile starts on the first rung', () async {
      expect((await profile()).highestLevelReached, 1);
    });

    test('crossing a threshold raises it', () async {
      // The rarest tier is 1,000 base and ×3 on a first find, so a couple of
      // rare birds is enough to pass level 2 (500) and level 3 (1,500).
      await hear('Species sp39');
      await hear('Species sp38');

      final row = await profile();
      expect(row.totalStars, greaterThanOrEqualTo(1500));
      expect(row.highestLevelReached, greaterThanOrEqualTo(3));
    });

    test('and it matches what the ladder says about the total', () async {
      await hear('Species sp39');

      final row = await profile();
      expect(row.highestLevelReached, levelForStars(row.totalStars).number);
    });

    test('a floor already above the total is left alone', () async {
      // The ratchet's whole job. Nothing during play may lower it.
      await (db.update(db.userProfiles)..where(
        (p) => p.id.equals(kDefaultProfileId),
      )).write(const UserProfilesCompanion(highestLevelReached: Value(9)));

      await hear('Species sp0');

      expect((await profile()).highestLevelReached, 9);
    });
  });

  group('AVA-01 · the card on screen', () {
    Future<void> pump(
      WidgetTester tester, {
      int stars = 0,
      int floor = 1,
      String? name,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            levelProgressProvider.overrideWith(
              (ref) async =>
                  progressFor(stars: stars, highestLevelReached: floor),
            ),
            avatarNameProvider.overrideWith((ref) async => name),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AvatarCard()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the level number and its title', (tester) async {
      await pump(tester, stars: 4000);

      expect(find.text('Level 4 · Fledgling'), findsOneWidget);
    });

    testWidgets('and how far to the next one (STAT-07)', (tester) async {
      // Level 4 runs 4,000 → 8,000.
      await pump(tester, stars: 6000);

      expect(find.textContaining('to Young bird'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('the top of the ladder has nothing left to reach', (
      tester,
    ) async {
      await pump(tester, stars: 500000);

      expect(
        find.text('The very top. Nothing above this one.'),
        findsOneWidget,
      );
      expect(find.textContaining('to '), findsNothing);
    });

    // One pump per test: a second pumpWidget reuses the ProviderScope element,
    // and the overrides that come with it do not always take on the rebuild.
    testWidgets('AVA-02 · an empty account is an egg', (tester) async {
      await pump(tester, stars: 0);

      expect(find.text(AvatarStage.egg.emoji), findsOneWidget);
    });

    testWidgets('AVA-02 · and a full one is a grown bird', (tester) async {
      await pump(tester, stars: 60000);

      expect(find.text(AvatarStage.adult.emoji), findsOneWidget);
    });

    testWidgets('AVA-05 · a named bird is called by its name', (tester) async {
      await pump(tester, stars: 4000, name: 'Pieps');

      expect(find.text('Pieps'), findsOneWidget);
      // The level line stays: the name replaces the title, not the level.
      expect(find.text('Level 4 · Fledgling'), findsOneWidget);
    });

    testWidgets('an unnamed bird falls back to its level title', (
      tester,
    ) async {
      await pump(tester, stars: 4000);

      // Never an empty line where a name would be.
      expect(find.text('Fledgling'), findsOneWidget);
    });

    testWidgets('an empty database shows the egg, not a spinner', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            // A future that never completes, rather than a delayed one: a
            // pending timer fails the test at teardown for reasons that have
            // nothing to do with what is being asserted.
            levelProgressProvider.overrideWith(
              (ref) => Completer<LevelProgress>().future,
            ),
            avatarNameProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: AvatarCard()),
          ),
        ),
      );
      await tester.pump();

      // A child arriving at their home screen sees their bird straight away.
      expect(find.text(AvatarStage.egg.emoji), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('⚠️ a ratcheted level still shows, and says nothing about it', (
      tester,
    ) async {
      // The point of AUS-12 is that the child never finds out the level was
      // defended. No warning, no asterisk, no "recalculated".
      await pump(tester, stars: 100, floor: 7);

      expect(find.text('Level 7 · Listener'), findsOneWidget);
      expect(find.textContaining('recalc'), findsNothing);
      expect(find.textContaining('lost'), findsNothing);
    });
  });

  group('AVA-05 · naming the bird', () {
    testWidgets('offers a list, never a text field', (tester) async {
      // KID-07: free text is a moderation surface the app has decided not to
      // acquire, and AVA-05 names that as the reason for a preset list.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 0),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed: () => showAvatarNameSheet(context),
                      child: const Text('open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('What is your bird called?'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(kAvatarNames.length));
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('picking one writes it to the profile', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 0),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder:
                    (context) => TextButton(
                      onPressed: () => showAvatarNameSheet(context),
                      child: const Text('open'),
                    ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kAvatarNames.first));
      await tester.pumpAndSettle();

      final profile =
          await (db.select(db.userProfiles)
            ..where((p) => p.id.equals(kDefaultProfileId))).getSingle();

      // It goes in the profile, so it travels with a backup (SET-07) rather
      // than being the one thing lost on a new phone.
      expect(profile.avatarState, contains(kAvatarNames.first));
    });
  });
}
