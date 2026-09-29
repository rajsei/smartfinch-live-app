// =============================================================================
// The sticker album and its button — AVA-07
// =============================================================================
//
// Four claims worth holding.
//
//   **A pick is asked for, then revealed.** Tapping a sticker asks; only
//   "Take it" picks; the fact comes after, as the reward.
//
//   **A picked sticker is on the home screen straight away**, and stays
//   picked whatever happens to the board.
//
//   ⚠️ **A sticker is not a find.** Picking a real bird must not touch the
//   life list — the child's own first hearing, weeks later, still earns ×3.
//
//   **The button under the level bar says when a pick is open**, and is there
//   either way.
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/avatar/avatar_providers.dart';
import 'package:smartfinch/features/avatar/avatar_state.dart';
import 'package:smartfinch/features/avatar/level_ladder.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/stickers/sticker_album_screen.dart';
import 'package:smartfinch/features/stickers/sticker_board.dart';
import 'package:smartfinch/features/stickers/sticker_catalog.dart';
import 'package:smartfinch/features/stickers/sticker_providers.dart';
import 'package:smartfinch/features/stickers/widgets/sticker_album_button.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/services/taxonomy_service.dart';

void main() {
  // The shipped catalogue, read from disk: the album is tested against the
  // stickers a child will actually see.
  final catalog = StickerCatalog.parse(
    manifestJson: File('assets/stickers/stickers.json').readAsStringSync(),
    factsJsonByLocale: {
      'en': File('assets/stickers/facts_en.json').readAsStringSync(),
      'de': File('assets/stickers/facts_de.json').readAsStringSync(),
    },
    imageAssets: {
      for (final f in Directory('assets/stickers/images').listSync())
        f.path.replaceAll('\\', '/'),
    },
  );

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  Future<StickerBoard> storedBoard() async =>
      StickerBoard.fromJson(await readAvatarField(db, kStickerStateKey));

  Future<void> pump(WidgetTester tester, Widget home, {int stars = 0}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          stickerCatalogProvider.overrideWith((ref) async => catalog),
          levelProgressProvider.overrideWith(
            (ref) async => progressFor(stars: stars),
          ),
          // Never loads: names fall back to the list's own, then English.
          taxonomyServiceProvider.overrideWith(
            (ref) => Completer<TaxonomyService>().future,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    // runAsync for the in-memory database, whose queries run off the fake
    // clock the widget test otherwise holds still.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  group('the album', () {
    testWidgets('level 3 offers three picks', (tester) async {
      await pump(tester, const StickerAlbumScreen(), stars: 2250);

      expect(
        find.text('You may pick 3 stickers! Tap a bird you like.'),
        findsOneWidget,
      );
      expect(find.text('Pick one'), findsOneWidget);
    });

    testWidgets('a tap asks first; going back picks nothing', (tester) async {
      await pump(tester, const StickerAlbumScreen(), stars: 250);

      await tester.tap(find.text('Shoebill'));
      await tester.pumpAndSettle();
      expect(find.text('Take this sticker?'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect((await tester.runAsync(storedBoard))!.pickedIds, isEmpty);
    });

    testWidgets('taking it picks, places, and reveals the fact', (
      tester,
    ) async {
      await pump(tester, const StickerAlbumScreen(), stars: 250);

      await tester.tap(find.text('Shoebill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take it'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      // The reward: the fact, only now.
      expect(find.text('Did you know?'), findsOneWidget);
      expect(
        find.textContaining('stand completely still for minutes'),
        findsOneWidget,
      );

      final board = (await tester.runAsync(storedBoard))!;
      expect(board.picks, {1: 'balaeniceps_rex'});
      // On the home screen straight away.
      expect(board.placedIds, {'balaeniceps_rex'});

      await tester.tap(find.text('Great!'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.text('Your stickers'), findsOneWidget);
      // The only pick is used: the rest wait for the next level.
      expect(find.text('Still to collect'), findsOneWidget);
      expect(find.text('At level 2 you may pick one.'), findsOneWidget);
    });

    testWidgets('⚠️ picking a bird does not put it on the life list', (
      tester,
    ) async {
      await pump(tester, const StickerAlbumScreen(), stars: 250);

      await tester.tap(find.text('Shoebill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Take it'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      final life = await tester.runAsync(() => db.select(db.lifeSpecies).get());
      expect(life, isEmpty);
    });

    testWidgets('a picked sticker shows its fact again', (tester) async {
      await tester.runAsync(
        () => writeAvatarField(
          db,
          kStickerStateKey,
          StickerBoard.empty.pick('apteryx_mantelli', level: 1).toJson(),
        ),
      );
      await pump(tester, const StickerAlbumScreen(), stars: 250);

      await tester.tap(find.text('Kiwi'));
      await tester.pumpAndSettle();

      expect(find.text('Did you know?'), findsOneWidget);
      expect(find.textContaining('tip of its beak'), findsOneWidget);
    });

    testWidgets('level 0: nothing to pick, and no fact given away', (
      tester,
    ) async {
      await pump(tester, const StickerAlbumScreen());

      expect(find.textContaining('You may pick'), findsNothing);
      expect(find.text('At level 1 you may pick one.'), findsOneWidget);

      await tester.tap(find.text('Shoebill'));
      await tester.pumpAndSettle();

      expect(find.text('Take this sticker?'), findsNothing);
      expect(find.text('Did you know?'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('At level 1 you may pick one.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('every sticker taken says so, and nothing about waiting', (
      tester,
    ) async {
      var board = StickerBoard.empty;
      for (final sticker in catalog.stickers) {
        board = board.pick(sticker.id, level: catalog.stickers.length + 5);
      }
      await tester.runAsync(
        () => writeAvatarField(db, kStickerStateKey, board.toJson()),
      );

      // Five levels open, no stickers left to fill them.
      await pump(
        tester,
        const StickerAlbumScreen(),
        stars: starsForLevel(catalog.stickers.length + 5),
      );

      expect(find.text('You have collected every sticker!'), findsOneWidget);
      expect(find.textContaining('You may pick'), findsNothing);
    });
  });

  group('the button under the level bar', () {
    Widget button() => const Scaffold(
      body: Center(child: StickerAlbumButton(ink: Colors.black)),
    );

    testWidgets('is there at level 0', (tester) async {
      await pump(tester, button());
      expect(find.text('Sticker album'), findsOneWidget);
    });

    testWidgets('says so while a pick is open', (tester) async {
      await pump(tester, button(), stars: 250);
      expect(find.text('Pick a sticker'), findsOneWidget);
    });

    testWidgets('and counts them', (tester) async {
      await pump(tester, button(), stars: 2250);
      expect(find.text('Pick 3 stickers'), findsOneWidget);
    });

    testWidgets('opens the album', (tester) async {
      await pump(tester, button());
      await tester.tap(find.text('Sticker album'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();

      expect(find.byType(StickerAlbumScreen), findsOneWidget);
    });
  });
}
