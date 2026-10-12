// =============================================================================
// Settings → Storage — the retention thresholds on screen (SET-12)
// =============================================================================
//
// Loosening a threshold deletes nothing and asks nothing. Tightening one can
// delete at once, so the screen counts first and asks with the number — and a
// "no" leaves the setting where it was.
// =============================================================================

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/constants/app_constants.dart';
import 'package:smartfinch/core/database/app_database.dart';
import 'package:smartfinch/features/audio/ring_buffer.dart';
import 'package:smartfinch/features/recording/recording_service.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/storage/clip_retention.dart';
import 'package:smartfinch/features/storage/clip_retention_job.dart';
import 'package:smartfinch/features/storage/clip_retention_settings.dart';
import 'package:smartfinch/features/storage/storage_providers.dart';
import 'package:smartfinch/features/storage/storage_service.dart';
import 'package:smartfinch/features/storage/widgets/storage_settings_section.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

/// A job that counts and deletes on paper.
class _FakeJob extends ClipRetentionJob {
  _FakeJob(AppDatabase db, ClipRetentionPolicy policy, this.log, this.doomed)
    : super(
        db: db,
        recordings: RecordingService(ringBuffer: RingBuffer(capacity: 10)),
        policy: policy,
      );

  final List<String> log;

  /// What a policy with this cap would delete.
  final int Function(ClipRetentionPolicy policy) doomed;

  @override
  Future<int> wouldDelete(ClipRetentionPolicy candidate, {DateTime? now}) {
    log.add('count ${candidate.perSpeciesCap}/${candidate.minimumAge.inDays}');
    return Future.value(doomed(candidate));
  }

  @override
  Future<ClipRetentionResult> run({DateTime? now}) {
    log.add('run ${policy.perSpeciesCap}/${policy.minimumAge.inDays}');
    return Future.value(ClipRetentionResult(deleted: doomed(policy)));
  }
}

void main() {
  late AppDatabase db;
  late List<String> log;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    log = [];
  });
  tearDown(() async => db.close());

  Future<SharedPreferences> pump(
    WidgetTester tester, {
    int Function(ClipRetentionPolicy policy)? doomed,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          storageUsageProvider.overrideWith(
            (ref) async => const StorageUsage(
              recordingBytes: 5000000,
              recordingCount: 300,
            ),
          ),
          clipRetentionJobProvider.overrideWith(
            (ref) => _FakeJob(
              db,
              ref.watch(clipRetentionPolicyProvider),
              log,
              doomed ??
                  (policy) =>
                      policy.perSpeciesCap < 100
                          ? 120 - policy.perSpeciesCap
                          : 0,
            ),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ListView(
              children: [
                StorageSettingsSection(
                  sectionHeader:
                      ({required String title, required String subtitle}) =>
                          Text(title),
                  titleWithHelp:
                      ({required String title, String? helpBody}) =>
                          Text(title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> pick(WidgetTester tester, String current, String choice) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice).last);
    await tester.pumpAndSettle();
  }

  testWidgets('both thresholds show their shipped values', (tester) async {
    await pump(tester);

    expect(find.text('Keep at least'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
    expect(find.text('Recordings per species'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('loosening saves without asking and deletes nothing', (
    tester,
  ) async {
    final prefs = await pump(tester);

    await pick(tester, '100', '500');

    expect(find.byType(AlertDialog), findsNothing);
    expect(prefs.getInt(PrefKeys.clipRetentionPerSpecies), 500);
    expect(log.where((l) => l.startsWith('run')), isEmpty);
  });

  testWidgets('tightening asks with the number first', (tester) async {
    await pump(tester);

    await pick(tester, '100', '20');

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Delete recordings now?'), findsOneWidget);
    expect(find.textContaining('100 recordings are deleted now'), findsOne);
  });

  testWidgets('⚠️ "Cancel" keeps the old value and deletes nothing', (
    tester,
  ) async {
    final prefs = await pump(tester);

    await pick(tester, '100', '20');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(prefs.getInt(PrefKeys.clipRetentionPerSpecies), isNull);
    expect(find.text('100'), findsOneWidget);
    expect(log, ['count 20/30']);
  });

  testWidgets('confirming saves, then runs the stricter clean-up at once', (
    tester,
  ) async {
    final prefs = await pump(tester);

    await pick(tester, '100', '20');
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(prefs.getInt(PrefKeys.clipRetentionPerSpecies), 20);
    // Counted with the new cap, then run with the new cap — not the old one.
    expect(log, ['count 20/30', 'run 20/30']);
    expect(find.text('100 recordings deleted.'), findsOneWidget);
  });

  testWidgets('tightening with nothing to delete does not ask', (tester) async {
    final prefs = await pump(tester, doomed: (_) => 0);

    await pick(tester, '30 days', '7 days');

    expect(find.byType(AlertDialog), findsNothing);
    expect(prefs.getInt(PrefKeys.clipRetentionDays), 7);
    expect(log, ['count 100/7']);
  });
}
