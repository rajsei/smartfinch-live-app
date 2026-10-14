// =============================================================================
// Live screen — the spectrogram survives a rotation
// =============================================================================
//
// Portrait stacks the spectrogram above the detection list; landscape puts it
// in the left half of a row. That moves it to a different depth of the widget
// tree, and without a key Flutter disposes it and builds an empty one: every
// rotation wiped the audio already on screen while recording carried on. The
// painter's column buffer lives in the widget's state, so the state surviving
// is what keeps the picture.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/services/location_service.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/live/live_screen.dart';
import 'package:smartfinch/features/spectrogram/spectrogram_widget.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

const _portrait = Size(400, 800);
const _landscape = Size(800, 400);

void main() {
  Future<void> pumpLiveScreen(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentLocationProvider.overrideWith(
            (ref) async => const AppLocation(latitude: 52.52, longitude: 13.405),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LiveScreen(),
        ),
      ),
    );
    // The model cannot load under `flutter test` and its spinner never
    // settles. The spectrogram is in the layout from the first frame on,
    // whatever state the load is in, so one frame is enough.
    await tester.pump();
  }

  void setSize(WidgetTester tester, Size size) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
  }

  testWidgets('keeps the spectrogram when turned to landscape and back', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    setSize(tester, _portrait);
    await pumpLiveScreen(tester);

    final before = tester.state(find.byType(SpectrogramWidget));

    setSize(tester, _landscape);
    await tester.pump();
    expect(
      tester.state(find.byType(SpectrogramWidget)),
      same(before),
      reason: 'a new state means an empty spectrogram',
    );

    setSize(tester, _portrait);
    await tester.pump();
    expect(tester.state(find.byType(SpectrogramWidget)), same(before));
  });
}
