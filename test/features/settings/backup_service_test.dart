// =============================================================================
// BackupService — SET-07, and the promise in LOG-12
// =============================================================================
//
// The thing between a broken phone and a lost collection, so the tests are
// about the ways a restore could quietly return the *wrong* collection rather
// than none at all.
//
//   **Nothing is recomputed.** Every `ScoreEvent` carries its frozen base
//   value, level, geo week, grid cell, threshold and rule version (`PKT-15`),
//   and a restore writes them back unchanged. A restore that re-derived stars
//   from today's rarity scale would look fine and would silently rewrite
//   history — the scale is rebuilt per cell *and* per week.
//
//   ⚠️ **Levels ratchet** (`AUS-12`). Restoring an older backup onto a phone
//   that has since progressed must not take a level, and with it an avatar
//   stage, away from a child.
//
//   **Replace, never merge.** Row ids are UUIDs; nothing can tell a
//   re-imported detection from a new one, so a merge would double every star.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/core/services/grid_cell.dart';
import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/points/points_repository.dart';
import 'package:smartfinch/features/scoring/rarity_scale_provider.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_repository.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/settings/backup/backup_screen.dart';
import 'package:smartfinch/features/settings/backup/backup_service.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  const cell = GridCell(508, 129);

  /// Monday 4 May 2026.
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

  late AppDatabase source;
  late ScoringRepository scoring;
  late BackupService backup;
  late String sessionId;

  ScoringContext contextAt(DateTime when, {bool filterEnabled = true}) =>
      ScoringContext(
        now: when,
        appliedThreshold: 35,
        filterEnabled: filterEnabled,
        scale: scale,
        cell: cell,
      );

  setUp(() async {
    source = AppDatabase.forTesting(NativeDatabase.memory());
    scoring = ScoringRepository(source);
    backup = BackupService(source);
    sessionId = await scoring.startSession(
      startedAt: may4,
      cell: cell,
      placeName: 'Oma',
    );
  });

  tearDown(() async => source.close());

  Future<String> hear(String name, {DateTime? at}) async {
    final recorded = await scoring.recordDetection(
      sessionId: sessionId,
      scientificName: name,
      confidence: 0.9,
      context: contextAt(at ?? may4),
    );
    return recorded.detectionId;
  }

  /// A second, empty database — the new phone.
  Future<AppDatabase> freshPhone() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  group('SET-07 · the round trip', () {
    test('a collection survives a new phone intact', () async {
      await hear('Species sp0');
      await hear('Species sp39');
      await hear('Species sp0', at: may4.add(const Duration(days: 1)));

      final bytes = await backup.export();
      final phone = await freshPhone();
      final summary = await BackupService(phone).restore(bytes);

      expect(summary.species, 2);
      expect(summary.detections, 3);
      expect(summary.stars, greaterThan(0));

      final life = await phone.select(phone.lifeSpecies).get();
      expect(life.map((l) => l.scientificName).toSet(), {
        'Species sp0',
        'Species sp39',
      });
    });

    test('⚠️ every frozen field comes back unchanged', () async {
      // PKT-15 and LOG-12 together. A restore that re-derived any of these
      // from today's scale would look fine and be wrong.
      await hear('Species sp39');

      final before = await source.select(source.scoreEvents).getSingle();
      final bytes = await backup.export();
      final phone = await freshPhone();
      await BackupService(phone).restore(bytes);
      final after = await phone.select(phone.scoreEvents).getSingle();

      expect(after.baseValue, before.baseValue);
      expect(after.levelAtDetection, before.levelAtDetection);
      expect(after.geoWeek, before.geoWeek);
      expect(after.gridCell, before.gridCell);
      expect(after.appliedThreshold, before.appliedThreshold);
      expect(after.ruleVersion, before.ruleVersion);
      expect(after.total, before.total);
      expect(after.awardedAt, before.awardedAt);
    });

    test('the star total is identical afterwards', () async {
      for (var i = 30; i < 36; i++) {
        await hear('Species sp$i');
      }

      final before = await PointsRepository(source).overview(now: may4);
      final bytes = await backup.export();
      final phone = await freshPhone();
      await BackupService(phone).restore(bytes);
      final after = await PointsRepository(phone).overview(now: may4);

      expect(after.figures.totalStars, before.figures.totalStars);
      expect(after.figures.speciesOverall, before.figures.speciesOverall);
      expect(after.figures.activeDays, before.figures.activeDays);
    });

    test('the place the child named comes with it', () async {
      await hear('Species sp0');

      final bytes = await backup.export();
      final phone = await freshPhone();
      await BackupService(phone).restore(bytes);

      final session = await phone.select(phone.sessions).getSingle();
      expect(session.placeName, 'Oma');
    });

    test('an empty collection round-trips too', () async {
      final bytes = await backup.export();
      final phone = await freshPhone();
      final summary = await BackupService(phone).restore(bytes);

      expect(summary.species, 0);
      expect(await phone.select(phone.lifeSpecies).get(), isEmpty);
    });
  });

  group('SET-07 · what the file does not carry', () {
    test('the recordings stay on the old phone', () async {
      // A year of clips is hundreds of megabytes, and a backup too large to
      // send protects nothing (SET-12 deletes them by policy anyway).
      final id = await hear('Species sp0');
      await scoring.setClipPath(detectionId: id, clipPath: '/clips/a.wav');
      await scoring.setClipFavourite(detectionId: id, isFavourite: true);

      final bytes = await backup.export();
      final phone = await freshPhone();
      await BackupService(phone).restore(bytes);

      final detection = await phone.select(phone.detections).getSingle();
      // No path, so the journal never offers a play button for a file that
      // is not there — that would read as a bug rather than as the trade.
      expect(detection.audioClipPath, isNull);
      // But what the child valued is still recorded.
      expect(detection.clipIsFavourite, isTrue);
    });
  });

  group('SET-07 · restore replaces', () {
    test('whatever was there before is gone', () async {
      await hear('Species sp0');
      final bytes = await backup.export();

      final phone = await freshPhone();
      final other = ScoringRepository(phone);
      final otherSession = await other.startSession(startedAt: may4);
      await other.recordDetection(
        sessionId: otherSession,
        scientificName: 'Species sp20',
        confidence: 0.9,
        context: contextAt(may4),
      );

      await BackupService(phone).restore(bytes);

      final life = await phone.select(phone.lifeSpecies).get();
      expect(life.map((l) => l.scientificName), ['Species sp0']);
    });

    test(
      'restoring the same file twice changes nothing the second time',
      () async {
        // Nothing can tell a re-imported row from a new one, so a merge would
        // double every star. Replace is what makes this safe to repeat.
        await hear('Species sp0');
        await hear('Species sp39');
        final bytes = await backup.export();

        final phone = await freshPhone();
        await BackupService(phone).restore(bytes);
        final once = await PointsRepository(phone).overview(now: may4);

        await BackupService(phone).restore(bytes);
        final twice = await PointsRepository(phone).overview(now: may4);

        expect(twice.figures.totalStars, once.figures.totalStars);
        expect(twice.figures.speciesOverall, once.figures.speciesOverall);
      },
    );
  });

  group('⚠️ AUS-12 · levels ratchet through a restore', () {
    Future<void> setLevel(AppDatabase db, int level) async {
      await (db.update(db.userProfiles)
        ..where((p) => p.id.equals(kDefaultProfileId))).write(
        UserProfilesCompanion(
          highestLevelReached: Value(level),
          updatedAt: Value(may4),
        ),
      );
    }

    test('an older backup cannot take a level away', () async {
      // The loss nobody would think to test for: restore a backup from
      // level 3 onto a phone that has since reached level 7, and a child
      // watches their avatar stage disappear. Principle 1 forbids it.
      await setLevel(source, 3);
      final bytes = await backup.export();

      final phone = await freshPhone();
      await setLevel(phone, 7);
      await BackupService(phone).restore(bytes);

      final profile =
          await (phone.select(phone.userProfiles)
            ..where((p) => p.id.equals(kDefaultProfileId))).getSingle();
      expect(profile.highestLevelReached, 7);
    });

    test('a newer backup still raises it', () async {
      await setLevel(source, 9);
      final bytes = await backup.export();

      final phone = await freshPhone();
      await setLevel(phone, 2);
      await BackupService(phone).restore(bytes);

      final profile =
          await (phone.select(phone.userProfiles)
            ..where((p) => p.id.equals(kDefaultProfileId))).getSingle();
      expect(profile.highestLevelReached, 9);
    });
  });

  group('SET-07 · a file that is not a backup', () {
    test('random bytes are refused', () async {
      expect(
        () => backup.restore(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(
          isA<BackupException>().having(
            (e) => e.reason,
            'reason',
            BackupFailure.notABackup,
          ),
        ),
      );
    });

    test('a zip of something else is refused', () async {
      final content = utf8.encode('not a backup');
      final archive =
          Archive()
            ..addFile(ArchiveFile('holiday.json', content.length, content));

      expect(
        () => backup.restore(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsA(isA<BackupException>()),
      );
    });

    test('a backup from a newer app is refused, not half-read', () async {
      // A partial restore of a collection is worse than being told to update
      // the app: nothing would look broken.
      final document = utf8.encode(
        jsonEncode({
          'format': kBackupFormat,
          'version': kBackupFormatVersion + 1,
          'schemaVersion': 99,
          'createdAt': may4.toIso8601String(),
          'tables': <String, dynamic>{},
        }),
      );
      final archive =
          Archive()
            ..addFile(ArchiveFile(kBackupEntryName, document.length, document));

      expect(
        () => backup.restore(Uint8List.fromList(ZipEncoder().encode(archive))),
        throwsA(
          isA<BackupException>().having(
            (e) => e.reason,
            'reason',
            BackupFailure.tooNew,
          ),
        ),
      );
    });

    test('a refused file leaves the collection alone', () async {
      await hear('Species sp0');

      try {
        await backup.restore(Uint8List.fromList([9, 9, 9]));
      } on BackupException {
        // expected
      }

      expect(await source.select(source.lifeSpecies).get(), hasLength(1));
    });
  });

  group('SET-07 · what a parent is shown before confirming', () {
    test('inspect reports the collection without changing anything', () async {
      await hear('Species sp0');
      await hear('Species sp39');

      final bytes = await backup.export();
      final summary = await backup.inspect(bytes);

      // "412 species, 4 May 2026" beats being asked to confirm a filename.
      expect(summary.species, 2);
      expect(summary.stars, greaterThan(0));
      expect(summary.createdAt.year, DateTime.now().year);
      expect(await source.select(source.lifeSpecies).get(), hasLength(2));
    });

    test('it carries the schema it was written from', () async {
      final summary = await backup.inspect(await backup.export());

      expect(summary.schemaVersion, source.schemaVersion);
    });
  });

  // ===========================================================================
  // SET-07 · the screen, worded for a parent
  // ===========================================================================
  //
  // The one screen in the app not written for a child, and the only place
  // where a wrong tap can replace a collection. So: both consequences stated
  // before either button is pressed, and the irreversible half behind a
  // confirmation that names what is in the file.
  // ===========================================================================
  group('SET-07 · the backup screen', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() async => db.close());

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const BackupScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('offers both halves and explains each', (tester) async {
      await pump(tester);

      expect(find.text('Save a backup'), findsOneWidget);
      expect(find.text('Restore from a backup'), findsOneWidget);
    });

    testWidgets('says the recordings are not in the file', (tester) async {
      // The one thing a parent would otherwise discover on the new phone.
      await pump(tester);

      expect(
        find.textContaining('Recordings are not included'),
        findsOneWidget,
      );
    });

    testWidgets('says restoring replaces everything, before it is tapped', (
      tester,
    ) async {
      // A parent should not learn what this button does by being asked to
      // confirm it.
      await pump(tester);

      expect(
        find.text(
          'This replaces everything on this device with what is in the file.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says the app keeps no copy of the file', (tester) async {
      await pump(tester);

      expect(
        find.textContaining('Smartfinch does not keep a copy'),
        findsOneWidget,
      );
    });
  });
}
