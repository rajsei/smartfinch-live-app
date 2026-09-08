// =============================================================================
// JournalClipSheet — the child's clip player (LOG-07, SET-12)
// =============================================================================
//
// Two things are worth a test here, and neither is the audio.
//
//   **What the sheet does not have.** It is deliberately not the session
//   review player: no share, no delete, no notes, no voice memos. Sharing
//   audio in particular is something Smartfinch decided against — `LOG-11`
//   makes the rendered day image the only sharing path — and a later "just
//   reuse the other sheet" would put it back without anyone noticing.
//
//   **The keep switch reaches the database.** It is the one control on the
//   sheet that changes anything, and what it changes is whether retention is
//   allowed to delete the recording (`SET-12`). A toggle that only moved the
//   icon would look identical and lose the clip a month later.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/journal/journal_models.dart';
import 'package:smartfinch/features/journal/widgets/journal_clip_sheet.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  /// A detection whose clip file does not exist.
  ///
  /// That is the ordinary case in a test and a real one on a phone: retention
  /// is allowed to have deleted it. The sheet has to draw either way — a
  /// missing picture is not a missing recording.
  JournalDetection detection({bool kept = false}) => JournalDetection(
    id: 'detection-1',
    heardAt: DateTime(2026, 5, 4, 7, 12),
    confidence: 0.87,
    clipPath: '/nowhere/merula.wav',
    isFavourite: kept,
  );

  Future<void> pump(WidgetTester tester, {bool kept = false}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

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
          home: Scaffold(
            body: JournalClipSheet(
              detection: detection(kept: kept),
              speciesName: 'Blackbird',
              dayKey: '2026-05-04',
              clipPath: '/nowhere/merula.wav',
            ),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the decode fails asynchronously and the progress
    // indicator spins until it does.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('names the bird and offers to play it', (tester) async {
    await pump(tester);

    expect(find.text('Blackbird'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
  });

  testWidgets('carries nothing that could send the audio anywhere', (
    tester,
  ) async {
    // KID-07 and LOG-11: the day image is the only thing that leaves the
    // phone, and it has no audio in it.
    await pump(tester);

    expect(find.byIcon(AppIcons.share), findsNothing);
    expect(find.byType(PopupMenuButton<Object?>), findsNothing);
  });

  testWidgets('offers to keep the recording, and says why', (tester) async {
    await pump(tester);

    expect(find.text('Keep'), findsOneWidget);
    expect(find.textContaining('never deleted to make room'), findsOneWidget);
  });

  testWidgets('keeping it reaches the database', (tester) async {
    // The detection references a session, so one has to exist for it.
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'session-1',
            profileId: kDefaultProfileId,
            updatedAt: DateTime(2026, 5, 4),
            startedAt: DateTime(2026, 5, 4, 7),
          ),
        );
    await db
        .into(db.detections)
        .insert(
          DetectionsCompanion.insert(
            id: 'detection-1',
            profileId: kDefaultProfileId,
            updatedAt: DateTime(2026, 5, 4),
            sessionId: 'session-1',
            scientificName: 'Turdus merula',
            detectedAt: DateTime(2026, 5, 4, 7, 12),
            confidence: 0.87,
          ),
        );

    await pump(tester);
    await tester.tap(find.text('Keep'));
    // Bounded pumps rather than pumpAndSettle: the spectrogram spinner never
    // stops in a test, because the decode has no audio plugin to return from.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final row =
        await (db.select(db.detections)
          ..where((d) => d.id.equals('detection-1'))).getSingle();

    expect(row.clipIsFavourite, isTrue);
    expect(find.text('Kept'), findsOneWidget);
  });

  testWidgets('a clip already kept opens saying so', (tester) async {
    await pump(tester, kept: true);

    expect(find.text('Kept'), findsOneWidget);
    expect(find.byIcon(AppIcons.bookmarkFilled), findsOneWidget);
  });
}
