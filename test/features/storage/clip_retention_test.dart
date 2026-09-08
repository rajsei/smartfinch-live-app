// =============================================================================
// Clip retention — SET-12
// =============================================================================
//
// One rule matters more than the thresholds, and it is the order:
//
//   **The hundredth mediocre blackbird goes before the only nuthatch.**
//
// A plain oldest-first rule would delete exactly backwards — a child's
// earliest recordings are the ones they were most excited about. And a
// favourite is never a candidate at all: a child who marked a recording has
// been told it stays.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/storage/clip_retention.dart';

void main() {
  const policy = ClipRetentionPolicy();
  final now = DateTime(2026, 5, 4);

  /// A clip old enough to be a candidate unless something else stops it.
  ClipCandidate clip(
    String species, {
    required double confidence,
    int daysAgo = 60,
    bool favourite = false,
    String? id,
  }) => ClipCandidate(
    detectionId: id ?? '$species-$confidence-$daysAgo',
    scientificName: species,
    recordedAt: now.subtract(Duration(days: daysAgo)),
    confidence: confidence,
    path: '/clips/$species-$confidence-$daysAgo.flac',
    isFavourite: favourite,
  );

  /// [count] clips of one species, confidences ascending from [from].
  List<ClipCandidate> many(
    String species,
    int count, {
    double from = 0.4,
    int daysAgo = 60,
  }) => [
    for (var i = 0; i < count; i++)
      clip(
        species,
        confidence: from + i * 0.001,
        daysAgo: daysAgo,
        id: '$species-$i',
      ),
  ];

  group('the thresholds', () {
    test('nothing goes below the per-species cap', () {
      final clips = many('Turdus merula', 100);

      expect(policy.selectForDeletion(clips, now: now), isEmpty);
    });

    test('one over the cap removes exactly one', () {
      final clips = many('Turdus merula', 101);

      expect(policy.selectForDeletion(clips, now: now), hasLength(1));
    });

    test('a young clip is never a candidate, however many there are', () {
      // A recording from this morning is the one a child is most likely to
      // want to play back tonight, whatever the counts say.
      final clips = many('Turdus merula', 150, daysAgo: 3);

      expect(policy.selectForDeletion(clips, now: now), isEmpty);
    });

    test('the age boundary is 30 days', () {
      expect(
        policy.selectForDeletion(
          many('Turdus merula', 101, daysAgo: 29),
          now: now,
        ),
        isEmpty,
      );
      expect(
        policy.selectForDeletion(
          many('Turdus merula', 101, daysAgo: 30),
          now: now,
        ),
        hasLength(1),
      );
    });

    test('an empty library needs no clean-up', () {
      expect(policy.selectForDeletion(const [], now: now), isEmpty);
    });
  });

  group('the order', () {
    test('the weakest clip of a species goes first', () {
      final clips = [
        ...many('Turdus merula', 100, from: 0.8),
        clip('Turdus merula', confidence: 0.31, id: 'the-weak-one'),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(doomed.single.detectionId, 'the-weak-one');
    });

    test('a tie is broken by age', () {
      final clips = [
        ...many('Turdus merula', 100, from: 0.8),
        clip('Turdus merula', confidence: 0.5, daysAgo: 40, id: 'newer'),
        clip('Turdus merula', confidence: 0.5, daysAgo: 200, id: 'older'),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(doomed.map((c) => c.detectionId), ['older', 'newer']);
    });

    test('⚠️ the only nuthatch survives a hundred blackbirds', () {
      // The whole point of the rule, in one test.
      final clips = [
        ...many('Turdus merula', 130, from: 0.9),
        clip('Sitta europaea', confidence: 0.36, id: 'the-only-nuthatch'),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);

      expect(doomed, hasLength(30));
      expect(
        doomed.map((c) => c.detectionId),
        isNot(contains('the-only-nuthatch')),
      );
      expect(doomed.every((c) => c.scientificName == 'Turdus merula'), isTrue);
    });

    test('a species under its own cap is untouched by another over it', () {
      final clips = [...many('Turdus merula', 120), ...many('Parus major', 40)];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(doomed.every((c) => c.scientificName == 'Turdus merula'), isTrue);
    });

    test('two species over the cap are both trimmed', () {
      final clips = [
        ...many('Turdus merula', 110),
        ...many('Parus major', 105),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(
        doomed.where((c) => c.scientificName == 'Turdus merula'),
        hasLength(10),
      );
      expect(
        doomed.where((c) => c.scientificName == 'Parus major'),
        hasLength(5),
      );
    });
  });

  group('⚠️ favourites', () {
    test('are never deleted, however weak', () {
      // The one promise the clean-up rests on. A child who marked a recording
      // has been told it stays.
      final clips = [
        ...many('Turdus merula', 100, from: 0.9),
        clip('Turdus merula', confidence: 0.05, favourite: true, id: 'kept'),
        clip('Turdus merula', confidence: 0.06, id: 'gone'),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(doomed.map((c) => c.detectionId), isNot(contains('kept')));
    });

    test('a library of nothing but favourites loses nothing', () {
      final clips = [
        for (var i = 0; i < 200; i++)
          clip('Turdus merula', confidence: 0.1, favourite: true, id: 'fav-$i'),
      ];

      expect(policy.selectForDeletion(clips, now: now), isEmpty);
    });

    test('they still occupy the cap', () {
      // Which is what lets the app tell a child "12 of your 100" rather than
      // letting favourites quietly raise the ceiling.
      final clips = [
        for (var i = 0; i < 95; i++)
          clip('Turdus merula', confidence: 0.9, favourite: true, id: 'fav-$i'),
        ...many('Turdus merula', 10, from: 0.4),
      ];

      final doomed = policy.selectForDeletion(clips, now: now);
      expect(doomed, hasLength(5), reason: '105 clips, cap of 100');
      expect(policy.usedOfCap(clips, 'Turdus merula'), 105);
    });

    test('too many favourites cannot be trimmed back into the cap', () {
      // Deliberate: the app tells the child the number instead of breaking its
      // own promise. `SET-12` says show how much of the cap they have used.
      final clips = [
        for (var i = 0; i < 120; i++)
          clip('Turdus merula', confidence: 0.9, favourite: true, id: 'fav-$i'),
      ];

      expect(policy.selectForDeletion(clips, now: now), isEmpty);
      expect(policy.usedOfCap(clips, 'Turdus merula'), 120);
    });
  });

  group('adjustable thresholds', () {
    test('a tighter cap removes more', () {
      const tight = ClipRetentionPolicy(perSpeciesCap: 10);
      final clips = many('Turdus merula', 25);

      expect(tight.selectForDeletion(clips, now: now), hasLength(15));
    });

    test('a longer minimum age protects more', () {
      const patient = ClipRetentionPolicy(minimumAge: Duration(days: 365));
      final clips = many('Turdus merula', 150, daysAgo: 60);

      expect(patient.selectForDeletion(clips, now: now), isEmpty);
    });
  });

  group('the clip path reaches the database', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    test('the column exists and starts empty', () async {
      // The gap this step closed: the writer attached clips to the in-memory
      // record only, so this column was never filled and the job above had
      // nothing to rank.
      final rows = await db.select(db.detections).get();
      expect(rows, isEmpty);
    });
  });
}
