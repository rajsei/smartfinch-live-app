// =============================================================================
// The stickers on the home screen — AVA-07
// =============================================================================
//
// Three claims worth holding.
//
//   **In the background nothing moves.** Panel up, the stickers ignore touch:
//   a child tapping the home screen cannot shift one by accident.
//
//   **Arranging is saved when the finger lifts.** Drag, pinch, turn — the
//   stored board has it without a save button.
//
//   **Nothing is lost.** "Back to the album" takes a sticker off the board;
//   it stays picked and one tap sticks it on again.
// =============================================================================

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/avatar/avatar_state.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/stickers/sticker_board.dart';
import 'package:smartfinch/features/stickers/sticker_catalog.dart';
import 'package:smartfinch/features/stickers/sticker_providers.dart';
import 'package:smartfinch/features/stickers/widgets/sticker_board_layer.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

void main() {
  final catalog = StickerCatalog.parse(
    manifestJson: File('assets/stickers/stickers.json').readAsStringSync(),
    imageAssets: {
      for (final f in Directory('assets/stickers/images').listSync())
        f.path.replaceAll('\\', '/'),
    },
  );

  const kingfisher = 'alcedo_atthis';
  const kiwi = 'apteryx_mantelli';

  late AppDatabase db;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    StickerBoardLayer.resetTray();
  });
  tearDown(() async => db.close());

  Future<StickerBoard> stored() async =>
      StickerBoard.fromJson(await readAvatarField(db, kStickerStateKey));

  /// The kingfisher in the middle of a 400 × 800 board, 120 wide; the kiwi
  /// picked but in the album.
  Future<void> pump(WidgetTester tester, {required bool editable}) async {
    final board = StickerBoard.empty
        .pick(kingfisher, level: 2)
        .pick(kiwi, level: 2)
        .place(kingfisher)
        .move(
          StickerLayout.portrait,
          const StickerPlacement(id: kingfisher, x: 0.5, y: 0.5, scale: 0.3),
        );
    await tester.runAsync(
      () => writeAvatarField(db, kStickerStateKey, board.toJson()),
    );

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          stickerCatalogProvider.overrideWith((ref) async => catalog),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: StickerBoardLayer(
              layout: StickerLayout.portrait,
              editable: editable,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  final sticker = find.byWidgetPredicate(
    (w) => w is Image && w.width == 120 && w.height == 120,
  );

  group('in the background', () {
    testWidgets('the stickers show', (tester) async {
      await pump(tester, editable: false);

      expect(sticker, findsOneWidget);
      expect(tester.getCenter(sticker), const Offset(400 * 0.5, 800 * 0.5));
    });

    testWidgets('and nothing moves them', (tester) async {
      await pump(tester, editable: false);

      expect(sticker.hitTestable(), findsNothing);
      await tester.dragFrom(const Offset(200, 400), const Offset(80, 0));
      await settle(tester);

      final board = (await tester.runAsync(stored))!;
      expect(board.portrait.single.x, 0.5);
    });
  });

  group('arranging', () {
    testWidgets('a drag is saved when the finger lifts', (tester) async {
      await pump(tester, editable: true);

      await tester.drag(sticker, const Offset(80, -40));
      await settle(tester);

      final moved = (await tester.runAsync(stored))!.portrait.single;
      // Less the few pixels a finger travels before a drag counts as one.
      expect(moved.x, closeTo(0.5 + 80 / 400, 0.06));
      expect(moved.x, greaterThan(0.6));
      expect(moved.y, lessThan(0.5));
    });

    testWidgets('two fingers make it bigger', (tester) async {
      await pump(tester, editable: true);

      final a = await tester.startGesture(const Offset(180, 400));
      final b = await tester.startGesture(const Offset(220, 400));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-4, 0));
        await b.moveBy(const Offset(4, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await settle(tester);

      final grown = (await tester.runAsync(stored))!.portrait.single;
      expect(grown.scale, greaterThan(0.3));
    });

    testWidgets(
      'a drag stops at the edge, with the whole sticker on the board',
      (tester) async {
        await pump(tester, editable: true);

        // Far past the top: it would hang over the header above the board.
        await tester.drag(sticker, const Offset(0, -700));
        await settle(tester);

        expect(tester.getRect(sticker).top, moreOrLessEquals(0, epsilon: 0.5));
        final moved = (await tester.runAsync(stored))!.portrait.single;
        expect(moved.y, closeTo(60 / 800, 1e-9));

        // And its top edge still answers a finger.
        await tester.tapAt(
          tester.getRect(sticker).topLeft + const Offset(4, 4),
        );
        await settle(tester);
        expect(find.byTooltip('Back to the album'), findsOneWidget);
      },
    );

    testWidgets('sideways it may hang out by half, and still be taken back', (
      tester,
    ) async {
      await pump(tester, editable: true);

      await tester.drag(sticker, const Offset(700, 0));
      await settle(tester);

      final moved = (await tester.runAsync(stored))!.portrait.single;
      expect(moved.x, 1.0);
      expect(tester.getCenter(sticker).dx, moreOrLessEquals(400, epsilon: 0.5));

      // "Back to the album" is on the half that still shows.
      await tester.tapAt(tester.getRect(sticker).center - const Offset(20, 0));
      await settle(tester);
      final button = find.byTooltip('Back to the album');
      expect(button, findsOneWidget);
      expect(tester.getRect(button).right, lessThanOrEqualTo(400));

      await tester.tap(button);
      await settle(tester);
      expect((await tester.runAsync(stored))!.placedIds, isEmpty);
    });

    testWidgets('growing it against the edge pushes it back onto the board', (
      tester,
    ) async {
      await pump(tester, editable: true);
      await tester.drag(sticker, const Offset(0, -700));
      await settle(tester);

      final top = tester.getRect(sticker).center;
      final a = await tester.startGesture(top + const Offset(-20, 0));
      final b = await tester.startGesture(top + const Offset(20, 0));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await a.moveBy(const Offset(-6, 0));
        await b.moveBy(const Offset(6, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await settle(tester);

      final grown = (await tester.runAsync(stored))!.portrait.single;
      expect(grown.scale, greaterThan(0.3));
      final rect = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is Image && w.width != null && w.width! > 120,
        ),
      );
      expect(rect.top, greaterThanOrEqualTo(-0.5));
    });

    testWidgets('a touch anywhere else lets go of it', (tester) async {
      await pump(tester, editable: true);

      await tester.tap(sticker);
      await settle(tester);
      expect(find.byTooltip('Back to the album'), findsOneWidget);

      await tester.tapAt(const Offset(200, 120));
      await settle(tester);
      expect(find.byTooltip('Back to the album'), findsNothing);

      // Nothing was taken off the board by letting go.
      expect((await tester.runAsync(stored))!.placedIds, {kingfisher});
    });

    testWidgets('a touched sticker can go back to the album', (tester) async {
      await pump(tester, editable: true);

      // The kiwi is picked but not on the board: it waits in the strip.
      expect(
        find.text(
          'Tap a sticker to stick it on. '
          'Drag with one finger, turn and resize with two.',
        ),
        findsOneWidget,
      );

      await tester.tap(sticker);
      await settle(tester);
      await tester.tap(find.byTooltip('Back to the album'));
      await settle(tester);

      final board = (await tester.runAsync(stored))!;
      expect(board.placedIds, isEmpty);
      // Off the board, still picked.
      expect(board.pickedIds, {kingfisher, kiwi});
    });

    testWidgets('a touched sticker can be mirrored', (tester) async {
      await pump(tester, editable: true);

      await tester.tap(sticker);
      await settle(tester);
      await tester.tap(find.byTooltip('Mirror'));
      await settle(tester);

      final board = (await tester.runAsync(stored))!;
      expect(board.portrait.single.flipped, isTrue);
      // Still on the board, still selected: mirroring is not putting away.
      expect(board.placedIds, {kingfisher});
      expect(find.byTooltip('Mirror'), findsOneWidget);
    });

    testWidgets('the strip folds away to the right, and back out', (
      tester,
    ) async {
      await pump(tester, editable: true);
      final strip = find.byWidgetPredicate((w) => w is Image && w.width == 56);
      expect(strip, findsOneWidget);

      await tester.tap(find.byTooltip('Put away'));
      await settle(tester);
      // Folded: the stickers it held are out of the way, and the tab says
      // how many wait in it.
      expect(strip, findsNothing);
      expect(find.text('1'), findsOneWidget);
      expect(find.byTooltip('Show stickers'), findsOneWidget);

      await tester.tap(find.byTooltip('Show stickers'));
      await settle(tester);
      expect(strip, findsOneWidget);
    });

    testWidgets('folded away, it stays folded the next time', (tester) async {
      await pump(tester, editable: true);
      await tester.tap(find.byTooltip('Put away'));
      await settle(tester);

      // The layer is rebuilt every time the panel moves.
      await pump(tester, editable: false);
      await pump(tester, editable: true);

      expect(find.byTooltip('Show stickers'), findsOneWidget);
    });

    testWidgets('and one tap in the strip sticks it on again', (tester) async {
      await pump(tester, editable: true);

      final strip = find.byWidgetPredicate((w) => w is Image && w.width == 56);
      expect(strip, findsOneWidget);

      await tester.tap(strip);
      await settle(tester);

      final board = (await tester.runAsync(stored))!;
      expect(board.placedIds, {kingfisher, kiwi});
      expect(board.portrait.last.id, kiwi);
    });
  });
}

/// Lets the in-memory database answer, then draws what it said.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}
