// =============================================================================
// AutoBackupService — DAT-09, the rolling local backups
// =============================================================================
//
// A backup that exists is not the point; a *good* one that still exists on the
// day it is needed is. So most of these tests are about what must not happen:
//
//   **An emptied database never rolls the good copies out.** A migration that
//   wiped the tables would otherwise replace all three, one day at a time.
//
//   **A day is one generation, three days deep.** Three copies written by
//   three sessions in one afternoon would leave nothing from yesterday.
//
//   **Nothing is replaced by less.** A restore, or damage, makes the
//   collection smaller; the copy from before it is the one that undoes it.
//
//   **A generation restores.** Through SET-07's own restore, so the frozen
//   fields and the level ratchet come with it.
// =============================================================================

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/settings/backup/auto_backup_service.dart';
import 'package:smartfinch/features/settings/backup/backup_service.dart';

void main() {
  const cell = GridCell(508, 129);

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

  late AppDatabase db;
  late ScoringRepository scoring;
  late Directory directory;
  late DateTime now;
  late AutoBackupService auto;
  String? sessionId;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    scoring = ScoringRepository(db);
    directory = Directory.systemTemp.createTempSync('auto_backup');
    now = DateTime(2026, 5, 4, 9);
    sessionId = null;
    auto = AutoBackupService(
      db,
      BackupService(db),
      directory: () async => directory,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  /// One detection of [name], scored, at the current [now].
  Future<void> hear(String name) async {
    sessionId ??= await scoring.startSession(startedAt: now, cell: cell);
    await scoring.recordDetection(
      sessionId: sessionId!,
      scientificName: name,
      confidence: 0.9,
      context: ScoringContext(
        now: now,
        appliedThreshold: 35,
        filterEnabled: true,
        scale: scale,
        cell: cell,
      ),
    );
  }

  /// Moves the clock on; every write after it carries a later `updatedAt`.
  void later(Duration by) => now = now.add(by);

  Future<int> starsIn(AppDatabase database) async {
    final events = await database.select(database.scoreEvents).get();
    return events.fold<int>(0, (sum, e) => sum + e.total);
  }

  group('when it writes nothing', () {
    test('an empty database is not a collection', () async {
      expect(await auto.runIfDue(), AutoBackupOutcome.empty);
      expect(await auto.generations(), isEmpty);
    });

    test('nothing new since the last copy', () async {
      await hear('Species sp0');
      expect(await auto.runIfDue(), AutoBackupOutcome.written);

      later(const Duration(days: 1));
      expect(await auto.runIfDue(), AutoBackupOutcome.unchanged);
      expect(await auto.generations(), hasLength(1));
    });

    test('an emptied database never rolls the good copies out', () async {
      // The failure this exists for: a migration — or a corrupt file the app
      // recreated — leaves empty tables, and nobody notices for a week.
      for (var day = 0; day < 3; day++) {
        await hear('Species sp$day');
        await auto.runIfDue();
        later(const Duration(days: 1));
      }
      final before = await auto.generations();
      expect(before, hasLength(3));

      await db.transaction(() async {
        await db.delete(db.lifeSpecies).go();
        await db.delete(db.yearSpecies).go();
        await db.delete(db.daySpecies).go();
        await db.delete(db.scoreEvents).go();
        await db.delete(db.detections).go();
        await db.delete(db.sessions).go();
      });

      for (var day = 0; day < 5; day++) {
        expect(await auto.runIfDue(), AutoBackupOutcome.empty);
        later(const Duration(days: 1));
      }
      expect(
        [for (final g in await auto.generations()) g.file.path],
        [for (final g in before) g.file.path],
      );
    });
  });

  group('one generation a day, three days deep', () {
    test('a change later the same day replaces that day\'s copy', () async {
      // Three sessions in one afternoon must not become three generations,
      // or the copy from yesterday is gone by the evening.
      await hear('Species sp0');
      await auto.runIfDue();
      final morning = (await auto.generations()).single;

      later(const Duration(hours: 6));
      await hear('Species sp1');
      expect(await auto.runIfDue(), AutoBackupOutcome.written);

      final evening = (await auto.generations()).single;
      expect(evening.fingerprint, isNot(morning.fingerprint));
      expect(morning.file.existsSync(), isFalse);
    });

    test('keeps the last three days and lets the oldest go', () async {
      final written = <String>[];
      for (var day = 0; day < 5; day++) {
        await hear('Species sp$day');
        await auto.runIfDue();
        written.add((await auto.generations()).first.file.path);
        later(const Duration(days: 1));
      }

      final kept = await auto.generations();
      expect(kept, hasLength(kAutoBackupGenerations));
      // Newest first: days 5, 4, 3.
      expect([for (final g in kept) g.file.path], written.reversed.take(3));
    });

    test('a half-written copy is swept, and never counts', () async {
      // What a crash mid-write leaves behind.
      File(
        '${directory.path}/auto-20260504-090000-deadbeef.zip.tmp',
      ).writeAsStringSync('half a zip');

      await hear('Species sp0');
      await auto.runIfDue();

      final names = [
        for (final entity in directory.listSync()) entity.uri.pathSegments.last,
      ];
      expect(names.where((n) => n.endsWith('.tmp')), isEmpty);
      expect(await auto.generations(), hasLength(1));
    });
  });

  group('never replaced by less', () {
    test('a smaller state the same day is kept beside the larger', () async {
      await hear('Species sp0');
      final small = await BackupService(db).export(now: now);
      await hear('Species sp1');
      await auto.runIfDue();
      final larger = (await auto.generations()).single;

      // Rows only ever go away through a restore or through damage. Here a
      // restore of a file saved before the second bird, which no automatic
      // copy holds.
      later(const Duration(hours: 1));
      await BackupService(db).restore(small);
      expect(await auto.runIfDue(), AutoBackupOutcome.written);

      final kept = await auto.generations();
      expect(kept, hasLength(2));
      expect(larger.file.existsSync(), isTrue);
    });
  });

  group('restoring', () {
    test('a generation restores the collection it was taken from', () async {
      await hear('Species sp0');
      await hear('Species sp5');
      await auto.runIfDue();
      final generation = (await auto.generations()).single;

      final phone = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(phone.close);
      await BackupService(phone).restore(generation.file.readAsBytesSync());

      expect(await starsIn(phone), await starsIn(db));
      expect(
        (await phone.select(phone.lifeSpecies).get()).length,
        (await db.select(db.lifeSpecies).get()).length,
      );
    });

    test('restoring an older copy does not cost today\'s', () async {
      await hear('Species sp0');
      await auto.runIfDue();
      final yesterday = (await auto.generations()).single;

      later(const Duration(days: 1));
      await hear('Species sp1');
      await hear('Species sp2');
      await auto.runIfDue();
      final today = (await auto.generations()).first;

      // The parent goes back a day — on purpose or not.
      await BackupService(db).restore(yesterday.file.readAsBytesSync());
      later(const Duration(hours: 1));
      await auto.runIfDue();

      expect(today.file.existsSync(), isTrue);
      expect(yesterday.file.existsSync(), isTrue);
    });

    test('the list says what each copy holds', () async {
      await hear('Species sp0');
      await hear('Species sp1');
      await auto.runIfDue();

      final entries = await auto.entries();
      expect(entries, hasLength(1));
      expect(entries.single.summary.species, 2);
      expect(entries.single.summary.detections, 2);
    });
  });

  test('two callers at once share one run', () async {
    // App start and the end of a session can ask in the same moment.
    await hear('Species sp0');
    final outcomes = await Future.wait([auto.runIfDue(), auto.runIfDue()]);

    expect(outcomes, everyElement(AutoBackupOutcome.written));
    expect(await auto.generations(), hasLength(1));
  });
}
