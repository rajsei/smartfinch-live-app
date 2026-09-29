// =============================================================================
// The sticker board — AVA-07, AUS-12
// =============================================================================
//
// Three claims worth holding.
//
//   ⚠️ **Picks follow the ratcheted level and are never taken back.** One per
//   level from 1 on; a sticker is picked once; a sticker taken off the board
//   stays picked.
//
//   **The stored blob is not trusted.** A hand-edited backup or a newer
//   version must not stop the home screen: bad parts read as empty.
//
//   **Two arrangements, one set of stickers.** Landscape follows portrait
//   until the child moves something there; putting a sticker on or taking it
//   off does it in both.
// =============================================================================

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/stickers/sticker_board.dart';

void main() {
  group('⚠️ picks (AUS-12)', () {
    test('level 0 has no pick, every level from 1 has one', () {
      expect(StickerBoard.empty.openLevels(0), isEmpty);
      expect(StickerBoard.empty.openLevels(1), [1]);
      expect(StickerBoard.empty.openLevels(3), [1, 2, 3]);
    });

    test('a pick uses the lowest open level', () {
      final board = StickerBoard.empty
          .pick('alcedo_atthis', level: 3)
          .pick('balaeniceps_rex', level: 3);

      expect(board.picks, {1: 'alcedo_atthis', 2: 'balaeniceps_rex'});
      expect(board.openLevels(3), [3]);
    });

    test('an existing child catches up on every level reached', () {
      // Updating at level 7 means seven picks, not one.
      expect(StickerBoard.empty.openLevels(7), hasLength(7));
    });

    test('a sticker is picked once', () {
      final board = StickerBoard.empty.pick('alcedo_atthis', level: 2);
      expect(() => board.pick('alcedo_atthis', level: 2), throwsStateError);
    });

    test('no open level, no pick', () {
      final board = StickerBoard.empty.pick('alcedo_atthis', level: 1);
      expect(() => board.pick('balaeniceps_rex', level: 1), throwsStateError);
    });

    test('taking a sticker off the board keeps it picked', () {
      final board = StickerBoard.empty
          .pick('alcedo_atthis', level: 1)
          .place('alcedo_atthis')
          .remove('alcedo_atthis');

      expect(board.placedIds, isEmpty);
      expect(board.pickedIds, {'alcedo_atthis'});
      expect(board.openLevels(1), isEmpty);
    });

    test('picks made at a higher level survive a lower one', () {
      // A ratcheted level cannot fall, but a restored backup could carry
      // picks from a level the stars no longer support. They stay.
      final board = StickerBoard.empty.pick('a', level: 5).pick('b', level: 5);

      expect(board.openLevels(1), isEmpty);
      expect(board.pickedIds, {'a', 'b'});
    });
  });

  group('the board', () {
    final picked = StickerBoard.empty
        .pick('a', level: 3)
        .pick('b', level: 3)
        .pick('c', level: 3);

    test('only picked stickers can go on it, each once', () {
      final board = picked.place('a').place('a').place('unknown');
      expect(board.portrait.map((p) => p.id), ['a']);
    });

    test('a new sticker lands in the middle, on top', () {
      final board = picked.place('a').place('b');
      expect(board.portrait.last.id, 'b');
      expect(board.portrait.last.x, 0.5);
      expect(board.portrait.last.y, 0.5);
      expect(board.portrait.last.scale, kDefaultStickerScale);
    });

    test('the sticker a child touches comes to the front', () {
      final board = picked
          .place('a')
          .place('b')
          .place('c')
          .bringToFront(StickerLayout.portrait, 'a');
      expect(board.portrait.map((p) => p.id), ['b', 'c', 'a']);
    });

    test('moves are kept on the board and at a size that can be grabbed', () {
      final board = picked
          .place('a')
          .move(
            StickerLayout.portrait,
            const StickerPlacement(id: 'a', x: 1.4, y: -0.2, scale: 5),
          );
      final a = board.portrait.single;

      expect(a.x, 1.0);
      expect(a.y, 0.0);
      expect(a.scale, kMaxStickerScale);

      final tiny = board.move(
        StickerLayout.portrait,
        const StickerPlacement(id: 'a', scale: 0.001),
      );
      expect(tiny.portrait.single.scale, kMinStickerScale);
    });

    test('rotation is folded into one turn', () {
      final board = picked
          .place('a')
          .move(
            StickerLayout.portrait,
            const StickerPlacement(id: 'a', rotation: 3 * math.pi),
          );
      expect(board.portrait.single.rotation, closeTo(math.pi, 1e-9));
    });

    test('moving a sticker that is not on the board changes nothing', () {
      final board = picked.move(
        StickerLayout.portrait,
        const StickerPlacement(id: 'a', x: 0.1),
      );
      expect(board.portrait, isEmpty);
    });
  });

  group('two arrangements', () {
    final placed = StickerBoard.empty
        .pick('a', level: 2)
        .pick('b', level: 2)
        .place('a')
        .place('b');

    test('landscape starts as a copy of portrait', () {
      expect(placed.landscape, isNull);
      expect(
        placed.placementsFor(StickerLayout.landscape),
        placed.placementsFor(StickerLayout.portrait),
      );
    });

    test('moving in landscape makes it its own, and leaves portrait alone', () {
      final board = placed.move(
        StickerLayout.landscape,
        const StickerPlacement(id: 'a', x: 0.1, y: 0.9),
      );

      expect(board.landscape, isNotNull);
      expect(board.placementsFor(StickerLayout.landscape).first.x, 0.1);
      expect(board.placementsFor(StickerLayout.portrait).first.x, 0.5);
    });

    test('after that, moving in portrait leaves landscape alone', () {
      final board = placed
          .move(
            StickerLayout.landscape,
            const StickerPlacement(id: 'a', x: 0.1),
          )
          .move(
            StickerLayout.portrait,
            const StickerPlacement(id: 'a', x: 0.8),
          );

      expect(board.placementsFor(StickerLayout.landscape).first.x, 0.1);
      expect(board.placementsFor(StickerLayout.portrait).first.x, 0.8);
    });

    test('putting on and taking off does it in both', () {
      final own = placed
          .pick('c', level: 3)
          .move(StickerLayout.landscape, const StickerPlacement(id: 'a'));

      final added = own.place('c');
      expect(added.placementsFor(StickerLayout.landscape).map((p) => p.id), [
        'a',
        'b',
        'c',
      ]);

      final removed = added.remove('a');
      expect(removed.placementsFor(StickerLayout.portrait).map((p) => p.id), [
        'b',
        'c',
      ]);
      expect(removed.placementsFor(StickerLayout.landscape).map((p) => p.id), [
        'b',
        'c',
      ]);
    });
  });

  group('stored as JSON', () {
    test('survives a round trip', () {
      final board = StickerBoard.empty
          .pick('a', level: 2)
          .pick('b', level: 2)
          .place('a')
          .place('b')
          .move(
            StickerLayout.landscape,
            const StickerPlacement(id: 'a', x: 0.2, y: 0.3, scale: 0.4),
          );

      final restored = StickerBoard.fromJson(
        jsonDecode(jsonEncode(board.toJson())),
      );

      expect(restored.picks, board.picks);
      expect(restored.portrait, board.portrait);
      expect(restored.landscape, board.landscape);
    });

    test('an empty or unreadable blob is an empty board', () {
      for (final raw in [
        null,
        'nonsense',
        42,
        <Object?>[],
        <String, Object?>{},
      ]) {
        final board = StickerBoard.fromJson(raw);
        expect(board.picks, isEmpty, reason: '$raw');
        expect(board.portrait, isEmpty, reason: '$raw');
        expect(board.landscape, isNull, reason: '$raw');
      }
    });

    test('bad parts are dropped, good parts kept', () {
      final board = StickerBoard.fromJson({
        'v': 1,
        'picks': {
          '1': 'a',
          '2': 'b',
          '0': 'level zero has no pick',
          'x': 'not a level',
          '3': 42,
          '4': 'a', // picked twice: the lower level keeps it
        },
        'portrait': [
          {'id': 'a', 'x': 0.2, 'y': 0.3, 's': 0.4, 'r': 0.1},
          {'id': 'a', 'x': 0.9}, // twice
          {'id': 'never_picked'},
          {'x': 0.5}, // no id
          'nonsense',
          {'id': 'b', 'x': 'left', 's': double.nan},
        ],
      });

      expect(board.picks, {1: 'a', 2: 'b'});
      expect(board.portrait.map((p) => p.id), ['a', 'b']);
      expect(board.portrait.first.x, 0.2);
      expect(board.portrait.last.x, 0.5);
      expect(board.portrait.last.scale, kDefaultStickerScale);
      expect(board.openLevels(4), [3, 4]);
    });

    test('a stored landscape is repaired to the stickers on the board', () {
      final board = StickerBoard.fromJson({
        'picks': {'1': 'a', '2': 'b'},
        'portrait': [
          {'id': 'a'},
          {'id': 'b'},
        ],
        'landscape': [
          {'id': 'b', 'x': 0.1},
          {'id': 'gone'},
        ],
      });

      expect(board.landscape!.map((p) => p.id), ['b', 'a']);
      expect(board.landscape!.first.x, 0.1);
    });
  });
}
