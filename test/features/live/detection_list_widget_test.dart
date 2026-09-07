// =============================================================================
// Detection List Widget Tests
// =============================================================================

import 'package:smartfinch/features/live/widgets/detection_list_widget.dart';
import 'package:smartfinch/features/live/widgets/live_tips.dart';
import 'package:smartfinch/features/live/live_session.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const countChipText = '\u00d73';
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  DetectionRecord record(String scientificName) {
    return DetectionRecord(
      scientificName: scientificName,
      commonName: scientificName,
      confidence: 0.8,
      timestamp: DateTime(2026, 7, 5, 10),
    );
  }

  Widget buildSubject({
    required bool showTips,
    bool isActive = false,
    List<DetectionRecord> detections = const [],
    Set<DetectionRecord>? activeDetections,
    Map<String, int>? speciesDetectionCounts,
  }) {
    return ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DetectionList(
            detections: detections,
            isActive: isActive,
            showTips: showTips,
            activeDetections: activeDetections,
            speciesDetectionCounts: speciesDetectionCounts,
          ),
        ),
      ),
    );
  }

  testWidgets('shows live tips only when the host opts in', (tester) async {
    await tester.pumpWidget(buildSubject(showTips: true));

    expect(find.byType(LiveTipsCarousel), findsOneWidget);
  });

  testWidgets('hides live tips by default for shared mode screens', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(showTips: false));

    expect(find.byType(LiveTipsCarousel), findsNothing);
  });

  testWidgets('hides live tips while a session is active', (tester) async {
    await tester.pumpWidget(buildSubject(showTips: true, isActive: true));

    expect(find.byType(LiveTipsCarousel), findsNothing);
  });

  testWidgets('shows species detection count chip when provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        showTips: false,
        isActive: true,
        detections: [record('A')],
        speciesDetectionCounts: const {'A': 3},
      ),
    );

    expect(find.text(countChipText), findsOneWidget);
    // Active rows (no activeDetections override) are shown at full opacity.
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity != 1.0),
      findsNothing,
    );
  });

  testWidgets('keeps count chip on inactive retained species rows', (
    tester,
  ) async {
    final detection = record('A');

    await tester.pumpWidget(
      buildSubject(
        showTips: false,
        isActive: true,
        detections: [detection],
        activeDetections: Set<DetectionRecord>.identity(),
        speciesDetectionCounts: const {'A': 3},
      ),
    );

    expect(find.text(countChipText), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // Retained (inactive) rows are dimmed to read as no-longer-live.
    expect(
      find.byWidgetPredicate((w) => w is Opacity && w.opacity == 0.75),
      findsOneWidget,
    );
  });
}
