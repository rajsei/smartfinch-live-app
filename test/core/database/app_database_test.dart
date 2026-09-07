// =============================================================================
// AppDatabase — schema tests
// =============================================================================
//
// These cover the things the *database* is supposed to guarantee, not what the
// scoring engine does with it. The distinction matters: a rule enforced by a
// constraint cannot be broken by a future bug, while a rule enforced in Dart
// can. Every constraint below exists because something in the specification
// says "must be impossible" rather than "should not happen".
// =============================================================================

// Drift exports an `isNull` of its own (a SQL expression builder) that collides
// with the matcher package's. The test wants the matcher, and only needs
// `Value` and `InsertMode` from drift itself.
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/database/tables.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Touching the database triggers `onCreate`, which builds the schema and
    // seeds the default profile — so the tests exercise the same startup path
    // a real install takes, rather than a hand-built stand-in.
    await db.customStatement('PRAGMA foreign_keys = ON');
  });

  tearDown(() async => db.close());

  /// Inserts a session and one detection in it, returning the detection id.
  Future<String> insertDetection({
    required String sessionId,
    required String detectionId,
    String species = 'Turdus merula',
    bool scoringPaused = false,
  }) async {
    final now = DateTime.now();
    await db.into(db.sessions).insert(
          SessionsCompanion.insert(
            id: sessionId,
            profileId: kDefaultProfileId,
            updatedAt: now,
            startedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    await db.into(db.detections).insert(
          DetectionsCompanion.insert(
            id: detectionId,
            profileId: kDefaultProfileId,
            updatedAt: now,
            sessionId: sessionId,
            scientificName: species,
            detectedAt: now,
            confidence: 0.8,
            scoringPaused: Value(scoringPaused),
          ),
        );
    return detectionId;
  }

  group('the constraint PKT-03 asks for', () {
    test('a species can only be scored once per day', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');
      await insertDetection(sessionId: 's1', detectionId: 'd2');

      await db.into(db.daySpecies).insert(
            DaySpeciesCompanion.insert(
              id: 'ds1',
              profileId: kDefaultProfileId,
              updatedAt: DateTime.now(),
              dayKey: '2026-05-04',
              scientificName: 'Turdus merula',
              firstDetectionId: 'd1',
              awardedPoints: 50,
            ),
          );

      // The second insert must be refused by the database itself, not by a
      // check somewhere in Dart that a later refactor could drop.
      await expectLater(
        db.into(db.daySpecies).insert(
              DaySpeciesCompanion.insert(
                id: 'ds2',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                dayKey: '2026-05-04',
                scientificName: 'Turdus merula',
                firstDetectionId: 'd2',
                awardedPoints: 50,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('the same species scores again the next day', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');

      for (final day in ['2026-05-04', '2026-05-05']) {
        await db.into(db.daySpecies).insert(
              DaySpeciesCompanion.insert(
                id: 'ds-$day',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                dayKey: day,
                scientificName: 'Turdus merula',
                firstDetectionId: 'd1',
                awardedPoints: 50,
              ),
            );
      }

      expect(await db.select(db.daySpecies).get(), hasLength(2));
    });

    test('two different species share a day without conflict', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');
      await insertDetection(
        sessionId: 's1',
        detectionId: 'd2',
        species: 'Parus major',
      );

      for (final (id, name) in [
        ('ds1', 'Turdus merula'),
        ('ds2', 'Parus major'),
      ]) {
        await db.into(db.daySpecies).insert(
              DaySpeciesCompanion.insert(
                id: id,
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                dayKey: '2026-05-04',
                scientificName: name,
                firstDetectionId: id == 'ds1' ? 'd1' : 'd2',
                awardedPoints: 50,
              ),
            );
      }

      expect(await db.select(db.daySpecies).get(), hasLength(2));
    });
  });

  group('life list — the table that burns PKT-04 if written carelessly', () {
    test('a species can only be a first find once', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');
      await insertDetection(sessionId: 's1', detectionId: 'd2');

      await db.into(db.lifeSpecies).insert(
            LifeSpeciesCompanion.insert(
              id: 'l1',
              profileId: kDefaultProfileId,
              updatedAt: DateTime.now(),
              scientificName: 'Turdus merula',
              firstDetectionId: 'd1',
              firstSeenAt: DateTime.now(),
            ),
          );

      await expectLater(
        db.into(db.lifeSpecies).insert(
              LifeSpeciesCompanion.insert(
                id: 'l2',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                scientificName: 'Turdus merula',
                firstDetectionId: 'd2',
                firstSeenAt: DateTime.now(),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'a paused detection can be stored without any scoring row existing',
      () async {
        // The shape DAT-11 requires: the recording is kept and flagged, and
        // the scoring layer stays untouched. If a future change ever writes a
        // life-list row here, the child's real first find silently loses its
        // ×3 — so the absence is worth asserting.
        await insertDetection(
          sessionId: 's1',
          detectionId: 'd1',
          scoringPaused: true,
        );

        final detection = await db.select(db.detections).getSingle();
        expect(detection.scoringPaused, isTrue);

        expect(await db.select(db.lifeSpecies).get(), isEmpty);
        expect(await db.select(db.daySpecies).get(), isEmpty);
        expect(await db.select(db.yearSpecies).get(), isEmpty);
        expect(await db.select(db.scoreEvents).get(), isEmpty);
      },
    );
  });

  group('year list', () {
    test('resets across calendar years', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');

      for (final year in [2026, 2027]) {
        await db.into(db.yearSpecies).insert(
              YearSpeciesCompanion.insert(
                id: 'y$year',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                year: year,
                scientificName: 'Turdus merula',
                firstDetectionId: 'd1',
                firstSeenAt: DateTime.now(),
              ),
            );
      }

      // Two rows, so the same species is a Jahresneuling again in January —
      // which after D20 is most of what carries the seasonal story.
      expect(await db.select(db.yearSpecies).get(), hasLength(2));
    });

    test('is refused twice in the same year', () async {
      await insertDetection(sessionId: 's1', detectionId: 'd1');

      await db.into(db.yearSpecies).insert(
            YearSpeciesCompanion.insert(
              id: 'y1',
              profileId: kDefaultProfileId,
              updatedAt: DateTime.now(),
              year: 2026,
              scientificName: 'Turdus merula',
              firstDetectionId: 'd1',
              firstSeenAt: DateTime.now(),
            ),
          );

      await expectLater(
        db.into(db.yearSpecies).insert(
              YearSpeciesCompanion.insert(
                id: 'y2',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                year: 2026,
                scientificName: 'Turdus merula',
                firstDetectionId: 'd1',
                firstSeenAt: DateTime.now(),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('ScoreEvent', () {
    test('stores every field PKT-15 requires to be frozen', () async {
      await db.into(db.scoreEvents).insert(
            ScoreEventsCompanion.insert(
              id: 'e1',
              profileId: kDefaultProfileId,
              updatedAt: DateTime.now(),
              dayKey: '2026-05-04',
              awardedAt: DateTime.now(),
              type: ScoreEventType.species,
              baseValue: 200,
              appliedThreshold: 35,
              ruleVersion: 1,
              total: 600,
              scientificName: const Value('Sitta europaea'),
              levelAtDetection: const Value(2),
              geoWeek: const Value(18),
              gridCell: const Value('50.8,12.9'),
              multiplier: const Value(3),
            ),
          );

      final event = await db.select(db.scoreEvents).getSingle();

      // All six frozen fields survive the round trip. Without the threshold in
      // particular, moving the settings slider would silently rewrite what the
      // history meant (D16, NFA-06).
      expect(event.baseValue, 200);
      expect(event.levelAtDetection, 2);
      expect(event.geoWeek, 18);
      expect(event.gridCell, '50.8,12.9');
      expect(event.appliedThreshold, 35);
      expect(event.ruleVersion, 1);
    });

    test('day-level bonuses carry no species', () async {
      await db.into(db.scoreEvents).insert(
            ScoreEventsCompanion.insert(
              id: 'e1',
              profileId: kDefaultProfileId,
              updatedAt: DateTime.now(),
              dayKey: '2026-05-04',
              awardedAt: DateTime.now(),
              type: ScoreEventType.variety,
              baseValue: 0,
              appliedThreshold: 35,
              ruleVersion: 1,
              total: 50,
              bonus: const Value(50),
            ),
          );

      final event = await db.select(db.scoreEvents).getSingle();
      expect(event.scientificName, isNull);
      expect(event.type, ScoreEventType.variety);
    });
  });

  group('referential integrity', () {
    test('a scoring row cannot point at a detection that does not exist',
        () async {
      // Foreign keys are off by default in SQLite; without the PRAGMA this
      // insert would succeed and leave the journal referencing nothing.
      await expectLater(
        db.into(db.daySpecies).insert(
              DaySpeciesCompanion.insert(
                id: 'ds1',
                profileId: kDefaultProfileId,
                updatedAt: DateTime.now(),
                dayKey: '2026-05-04',
                scientificName: 'Turdus merula',
                firstDetectionId: 'does-not-exist',
                awardedPoints: 50,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('UserProfile', () {
    test('levels start at 1 and the ratchet column exists', () async {
      final profile = await db.select(db.userProfiles).getSingle();
      expect(profile.highestLevelReached, 1);
      expect(profile.totalStars, 0);
    });

    test('the ratchet is what a rebalancing must respect', () async {
      // The database stores it; the rule that it never decreases belongs to
      // the scoring engine. This asserts the column is usable for that — the
      // engine's own test will assert the rule.
      await (db.update(db.userProfiles)
            ..where((p) => p.id.equals(kDefaultProfileId)))
          .write(
        const UserProfilesCompanion(
          totalStars: Value(40000),
          highestLevelReached: Value(8),
        ),
      );

      // A recomputation lowers the total — the level must not follow it down.
      await (db.update(db.userProfiles)
            ..where((p) => p.id.equals(kDefaultProfileId)))
          .write(const UserProfilesCompanion(totalStars: Value(35000)));

      final profile = await db.select(db.userProfiles).getSingle();
      expect(profile.totalStars, 35000);
      expect(
        profile.highestLevelReached,
        8,
        reason: 'a lower total must never take a level away (principle 1)',
      );
    });
  });
}
