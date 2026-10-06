// =============================================================================
// The album on the home screen — AVA-07 against KID-04
// =============================================================================
//
// The album button belongs under the level bar, always visible. On a phone
// too short to carry a button row there, `KID-04` wins — every destination one
// tap away, without scrolling — so the button moves behind the tile panel
// (still under the level bar, shown when the panel is pulled down) and an open
// pick is announced above the Live tile instead.
// =============================================================================

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/avatar/avatar_providers.dart';
import 'package:smartfinch/features/avatar/level_ladder.dart';
import 'package:smartfinch/features/home/home_screen.dart';
import 'package:smartfinch/features/home/widgets/home_header.dart';
import 'package:smartfinch/features/scoring/live_score_board.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/stickers/sticker_catalog.dart';
import 'package:smartfinch/features/stickers/sticker_providers.dart';
import 'package:smartfinch/features/stickers/widgets/sticker_album_button.dart';
import 'package:smartfinch/features/stickers/widgets/sticker_board_layer.dart';
import 'package:smartfinch/features/stickers/widgets/sticker_pick_card.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  final catalog = StickerCatalog.parse(
    manifestJson: File('assets/stickers/stickers.json').readAsStringSync(),
    imageAssets: {
      for (final f in Directory('assets/stickers/images').listSync())
        f.path.replaceAll('\\', '/'),
    },
  );

  Future<void> pumpAt(WidgetTester tester, Size size, {int stars = 0}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          appDatabaseProvider.overrideWithValue(db),
          stickerCatalogProvider.overrideWith((ref) async => catalog),
          starTotalsProvider.overrideWith(
            (ref) async => StarTotals(total: stars),
          ),
          levelProgressProvider.overrideWith(
            (ref) async => progressFor(stars: stars),
          ),
          avatarNameProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    // The board is read from the in-memory database, off the fake clock.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    // Past the home screen's own warm-up (a 2-second taxonomy timeout).
    await tester.pump(const Duration(seconds: 3));
  }

  final inHeader = find.descendant(
    of: find.byType(HomeHeader),
    matching: find.byType(StickerAlbumButton),
  );

  void expectEveryDestinationOnScreen(WidgetTester tester, double height) {
    for (final label in ['Collection', 'Explore', 'Journal', 'Points']) {
      expect(
        tester.getRect(find.text(label)).bottom,
        lessThanOrEqualTo(height),
        reason: '$label is below the fold (KID-04)',
      );
    }
  }

  group('a phone with room', () {
    testWidgets('the button is under the level bar, always visible', (
      tester,
    ) async {
      await pumpAt(tester, const Size(390, 844));

      expect(inHeader, findsOneWidget);
      expect(find.text('Sticker album').hitTestable(), findsOneWidget);
      expectEveryDestinationOnScreen(tester, 844);
    });

    testWidgets('an open pick is on the button, not in the panel', (
      tester,
    ) async {
      await pumpAt(tester, const Size(390, 844), stars: 250);

      expect(find.text('Pick a sticker').hitTestable(), findsOneWidget);
      expect(find.byType(StickerPickCard), findsNothing);
      expectEveryDestinationOnScreen(tester, 844);
    });
  });

  group('the stickers on the board', () {
    bool editable(WidgetTester tester) =>
        tester
            .widget<StickerBoardLayer>(find.byType(StickerBoardLayer))
            .editable;

    testWidgets('are background while the panel is up', (tester) async {
      await pumpAt(tester, const Size(390, 844));

      expect(find.byType(StickerBoardLayer), findsOneWidget);
      expect(editable(tester), isFalse);
    });

    testWidgets('and can be arranged while it is down', (tester) async {
      await pumpAt(tester, const Size(390, 844));

      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();
      expect(editable(tester), isTrue);

      // Pulling it back up is "done".
      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();
      expect(editable(tester), isFalse);
    });

    testWidgets('never reach above the header, in either state', (
      tester,
    ) async {
      await pumpAt(tester, const Size(390, 844));

      final headerBottom = tester.getRect(find.byType(HomeHeader)).bottom;
      expect(
        tester.getRect(find.byType(StickerBoardLayer)).top,
        moreOrLessEquals(headerBottom, epsilon: 1),
      );

      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(StickerBoardLayer)).top,
        moreOrLessEquals(headerBottom, epsilon: 1),
      );
    });
  });

  group('the stickers held sideways', () {
    Future<void> pumpLandscape(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
            stickerCatalogProvider.overrideWith((ref) async => catalog),
            starTotalsProvider.overrideWith((ref) async => const StarTotals()),
            levelProgressProvider.overrideWith(
              (ref) async => progressFor(stars: 0),
            ),
            avatarNameProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(seconds: 3));
    }

    bool editable(WidgetTester tester) =>
        tester
            .widget<StickerBoardLayer>(find.byType(StickerBoardLayer))
            .editable;

    // Flutter's simulated pointer coordinates do not resolve correctly
    // against this suite's landscape (wider-than-tall) test viewport for
    // *any* widget, including tiles that existed long before this change —
    // not something specific to the sticker board. So the handle is
    // exercised by calling its own callback directly, the same way a real
    // drag's `onTap`/`onHorizontalDragEnd` would fire, rather than through
    // `tester.tap`.
    void pressHandle(WidgetTester tester) {
      final handle = tester.widget<GestureDetector>(
        find.byKey(const ValueKey('landscape_panel_handle')),
      );
      handle.onTap!();
    }

    testWidgets('never reach under the header, docked or pushed', (
      tester,
    ) async {
      await pumpLandscape(tester);

      final headerRight = tester.getRect(find.byType(HomeHeader)).right;
      expect(
        tester.getRect(find.byType(StickerBoardLayer)).left,
        moreOrLessEquals(headerRight, epsilon: 1),
      );
      expect(editable(tester), isFalse);

      pressHandle(tester);
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byType(StickerBoardLayer)).left,
        moreOrLessEquals(headerRight, epsilon: 1),
      );
      expect(editable(tester), isTrue);
    });

    testWidgets('pushing the panel right reveals them, and back hides them', (
      tester,
    ) async {
      await pumpLandscape(tester);

      expect(editable(tester), isFalse);

      pressHandle(tester);
      await tester.pumpAndSettle();
      expect(editable(tester), isTrue);

      // Pushing it back left is "done", the same as pulling the portrait
      // panel back up.
      pressHandle(tester);
      await tester.pumpAndSettle();
      expect(editable(tester), isFalse);
    });
  });

  group('⚠️ a short phone (KID-04)', () {
    testWidgets('the button waits behind the panel', (tester) async {
      await pumpAt(tester, const Size(360, 640));

      expect(inHeader, findsNothing);
      expect(find.text('Sticker album').hitTestable(), findsNothing);
      expectEveryDestinationOnScreen(tester, 640);
    });

    testWidgets('and shows, under the level bar, when the panel is down', (
      tester,
    ) async {
      await pumpAt(tester, const Size(360, 640));

      await tester.tap(find.bySemanticsLabel(RegExp('Drag to move')));
      await tester.pumpAndSettle();

      final button = find.text('Sticker album').hitTestable();
      expect(button, findsOneWidget);
      expect(
        tester.getRect(button).top,
        greaterThan(
          tester.getRect(find.byType(LinearProgressIndicator)).bottom,
        ),
      );
    });

    testWidgets('an open pick is announced above the Live tile', (
      tester,
    ) async {
      await pumpAt(tester, const Size(360, 640), stars: 250);

      expect(find.text('Pick a sticker').hitTestable(), findsOneWidget);
      // And the card fits in the room it has: nothing drops below the fold.
      expectEveryDestinationOnScreen(tester, 640);
    });
  });
}
