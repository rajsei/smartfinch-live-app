// =============================================================================
// What is still possible today (HOME-06)
// =============================================================================
//
// The card's whole value is that it does not lie. Two ways it could:
//
//   **By suggesting something already done.** A badge earned this morning is
//   not a suggestion this afternoon.
//   **By suggesting something that cannot be done any more.** 🌅 *The early
//   bird* at three in the afternoon teaches a child that the card is noise.
//
// Both edges are hours — 09:00 and 22:00 — so they are tested on either side
// without a clock.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/features/points/still_possible.dart';

const _today = '2026-05-14';

/// Nothing earned today.
String? _nothingEarned(String key) => null;

List<String> _keysAt(
  int hour, {
  String? Function(String key) earned = _nothingEarned,
  int limit = kStillPossibleLimit,
}) =>
    stillPossibleToday(
      todayKey: _today,
      lastEarnedOn: earned,
      hour: hour,
      limit: limit,
    ).map((badge) => badge.key).toList();

void main() {
  group('stillPossibleToday', () {
    test('suggests at most two, in catalogue order', () {
      final open = _keysAt(10);

      expect(open, hasLength(kStillPossibleLimit));
      expect(open, [kEveningListener.key, kTenInOneGo.key]);
    });

    test('skips what has already been earned today', () {
      final open = _keysAt(
        10,
        earned: (key) => key == kEveningListener.key ? _today : null,
      );

      expect(open, isNot(contains(kEveningListener.key)));
    });

    test('a badge earned yesterday is open again', () {
      final open = _keysAt(10, earned: (key) => '2026-05-13');

      expect(open, isNotEmpty);
    });

    test('is empty when everything is done, rather than repeating itself', () {
      final open = _keysAt(10, earned: (key) => _today);

      expect(open, isEmpty);
    });
  });

  group('isStillPossibleAt', () {
    test('the morning badges close at 09:00', () {
      expect(isStillPossibleAt(kEarlyBird, 8), isTrue);
      expect(isStillPossibleAt(kEarlyBird, 9), isFalse);
      expect(isStillPossibleAt(kDawnChorus, 8), isTrue);
      expect(isStillPossibleAt(kDawnChorus, 9), isFalse);
    });

    test('the night badge is suggestible right up to the last hour', () {
      expect(isStillPossibleAt(kNightOwl, 21), isTrue);
      expect(isStillPossibleAt(kNightOwl, 22), isTrue);
      expect(isStillPossibleAt(kNightOwl, 23), isFalse);
    });

    test('a badge with no clock on it is possible all day', () {
      for (final hour in [0, 9, 15, 23]) {
        expect(isStillPossibleAt(kTenInOneGo, hour), isTrue);
      }
    });

    test('the early risers are gone from the list after nine', () {
      expect(_keysAt(6), contains(kEarlyBird.key));
      expect(_keysAt(9, limit: 99), isNot(contains(kEarlyBird.key)));
      expect(_keysAt(9, limit: 99), isNot(contains(kDawnChorus.key)));
    });
  });
}
