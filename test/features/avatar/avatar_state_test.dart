// =============================================================================
// avatarState — every writer merges (AVA-05, AVA-07)
// =============================================================================
//
// The claim worth holding: **renaming the bird does not delete the stickers.**
// Name and stickers share one JSON column, and the name used to be written as
// the whole blob.
// =============================================================================

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/avatar/avatar_state.dart';

void main() {
  group('decodeAvatarState', () {
    test('reads nothing as empty', () {
      expect(decodeAvatarState(null), isEmpty);
      expect(decodeAvatarState(''), isEmpty);
    });

    test('reads anything it cannot use as empty', () {
      expect(decodeAvatarState('{not json'), isEmpty);
      expect(decodeAvatarState('[1, 2]'), isEmpty);
      expect(decodeAvatarState('"Pieps"'), isEmpty);
    });

    test('reads an object', () {
      expect(decodeAvatarState('{"name":"Pieps"}'), {'name': 'Pieps'});
    });
  });

  group('mergeAvatarState', () {
    test('keeps every other key', () {
      final raw = jsonEncode({
        'name': 'Pieps',
        'stickers': {'v': 1},
        'fromTheFuture': true,
      });

      final merged = decodeAvatarState(mergeAvatarState(raw, 'name', 'Flocke'));

      expect(merged['name'], 'Flocke');
      expect(merged['stickers'], {'v': 1});
      expect(merged['fromTheFuture'], isTrue);
    });

    test('null removes the key and only that key', () {
      final raw = jsonEncode({
        'name': 'Pieps',
        'stickers': {'v': 1},
      });

      expect(decodeAvatarState(mergeAvatarState(raw, 'name', null)), {
        'stickers': {'v': 1},
      });
    });

    test('nothing left stores nothing', () {
      expect(mergeAvatarState('{"name":"Pieps"}', 'name', null), isNull);
      expect(mergeAvatarState(null, 'name', null), isNull);
    });

    test('an unreadable blob is replaced rather than kept', () {
      expect(decodeAvatarState(mergeAvatarState('{broken', 'name', 'Pieps')), {
        'name': 'Pieps',
      });
    });
  });

  group('⚠️ writeAvatarField against the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('renaming the bird keeps the stickers', () async {
      await writeAvatarField(db, 'stickers', {
        'v': 1,
        'picks': {'1': 'alcedo_atthis'},
      });
      await writeAvatarField(db, 'name', 'Pieps');
      await writeAvatarField(db, 'name', 'Flocke');

      expect(await readAvatarField(db, 'name'), 'Flocke');
      expect(await readAvatarField(db, 'stickers'), {
        'v': 1,
        'picks': {'1': 'alcedo_atthis'},
      });
    });

    test('clearing the name keeps the stickers', () async {
      await writeAvatarField(db, 'name', 'Pieps');
      await writeAvatarField(db, 'stickers', {'v': 1});
      await writeAvatarField(db, 'name', null);

      expect(await readAvatarField(db, 'name'), isNull);
      expect(await readAvatarField(db, 'stickers'), {'v': 1});
    });
  });
}
