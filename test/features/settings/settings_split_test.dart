// =============================================================================
// Settings: plain and Advanced (SET-01), and the warnings that guard scoring
// (SET-13)
// =============================================================================
//
// Two things are worth a test here, and they are not the layout.
//
// **What is on which screen.** SET-01's promise is "reorganised, not cut back":
// nothing is lost for the adult who wants it, nothing is in the way of the
// child who does not. A section that quietly ends up on neither screen breaks
// the first half of that promise silently.
//
// **That the scoring warnings cannot be walked past.** Turning the species
// filter off, or dragging the confidence threshold below the floor, pauses the
// whole scoring layer (PKT-20). The setting is reachable by an adult
// experimenting on a child's device, so the trade has to be shown *before* the
// change lands — and cancelling has to leave the setting alone.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/audio/audio_providers.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/features/settings/settings_screen.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/providers/settings_providers.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsView view = SettingsView.plain,
    Map<String, Object> initialPrefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();

    // A tall surface so the whole list is built at once. Settings is a lazy
    // ListView, and on a phone-sized viewport `find.text` cannot see a section
    // that has not been scrolled into existence — which would make every
    // "is not on this screen" assertion below pass for the wrong reason.
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          // The Audio section's device picker would otherwise construct a real
          // AudioCaptureService, whose disposal schedules a timer that outlives
          // the widget tree and fails the test's own teardown invariant.
          inputDevicesProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(view: view),
        ),
      ),
    );
    await tester.pump();

    container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
  }

  group('SET-01 · what is on which screen', () {
    testWidgets('the plain screen carries the everyday settings', (
      tester,
    ) async {
      await pumpSettings(tester);

      // SET-01's list, as far as it exists today: appearance and language,
      // announcements, location, privacy, storage. (Animation level SET-02 and
      // the rules page SET-11 are phase 2 and not yet built.)
      for (final section in [
        'General',
        'Announcements',
        'Location',
        'Privacy',
        'Danger Zone',
      ]) {
        expect(find.text(section), findsOneWidget, reason: section);
      }

      expect(find.text('Advanced settings'), findsOneWidget);
    });

    testWidgets('the plain screen does not carry the detection controls', (
      tester,
    ) async {
      await pumpSettings(tester);

      // Whatever else changes about these sections, they must not be the first
      // thing a child scrolls past.
      expect(find.text('Confidence threshold'), findsNothing);
      expect(find.text('Species filter'), findsNothing);
      expect(find.text('Spectrogram'), findsNothing);
    });

    testWidgets('the advanced screen carries them, and no door to itself', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      expect(find.text('Confidence threshold'), findsOneWidget);
      expect(find.text('Species filter'), findsWidgets);

      // "Advanced settings" is still on screen — as the app-bar title. What
      // must not be here is the tile that opens it again, identified by the
      // subtitle only the tile carries.
      expect(
        find.text('Audio, detection, spectrogram, recordings and export'),
        findsNothing,
      );
    });

    testWidgets('the advanced tile opens the advanced screen', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Advanced settings'));
      await tester.pumpAndSettle();

      // The title bar of the pushed screen, plus something only it carries.
      expect(find.text('Confidence threshold'), findsOneWidget);
    });

    testWidgets('every section lands on exactly one of the two screens', (
      tester,
    ) async {
      // The old context map could leave a section on no screen at all; this is
      // the property that replaced it.
      for (final view in SettingsView.values) {
        final sections = SettingsScreen.sectionViews.entries
            .where((e) => e.value == view)
            .map((e) => e.key);
        expect(sections, isNotEmpty, reason: '$view has no sections');
      }

      expect(
        SettingsScreen.sectionViews.values.toSet(),
        SettingsView.values.toSet(),
      );
    });
  });

  group('SET-01 · the expert inference controls are gone', () {
    testWidgets('no sensitivity slider and no species ignore list', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      // The one genuine deletion: these change what counts as a detection, and
      // a settings screen that can be used to arrange your own collection has
      // no place in a scoring app.
      expect(find.text('Sensitivity'), findsNothing);
      expect(find.text('Ignore species'), findsNothing);
    });
  });

  group('SET-13 · the species filter warns before it pauses scoring', () {
    testWidgets('choosing "Off" asks first, and cancelling changes nothing', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      final dropdown = find.byType(DropdownButton<String>).last;
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();

      expect(find.text('Then there are no stars'), findsOneWidget);
      // Every part of the promise, in the dialog the adult actually reads.
      expect(find.textContaining('streak'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(speciesFilterModeProvider), isNot('off'));
    });

    testWidgets('confirming switches it off', (tester) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Switch off anyway'));
      await tester.pumpAndSettle();

      expect(container.read(speciesFilterModeProvider), 'off');
    });
  });

  group('SET-13 · the confidence slider', () {
    /// The threshold slider is the first one on the Advanced screen.
    Slider thresholdSlider(WidgetTester tester) {
      final sliders = tester.widgetList<Slider>(find.byType(Slider));
      return sliders.firstWhere((s) => s.max == 100);
    }

    testWidgets('shows the scoring floor before anything is dragged', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      final floor = ScoringRules.current.scoringThresholdFloor;
      expect(floor, 35);

      // Marked on the track, not only in a warning afterwards.
      expect(thresholdSlider(tester).secondaryTrackValue, floor.toDouble());
      expect(
        find.textContaining('Below $floor % there are no stars'),
        findsOneWidget,
      );
    });

    testWidgets('dropping below the floor asks, and cancelling reverts', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);
      final before = container.read(confidenceThresholdProvider);

      // Drag, then release — the confirmation belongs on release, or the dialog
      // would fire on every intermediate value the slider reports.
      thresholdSlider(tester).onChanged!(20);
      await tester.pump();
      thresholdSlider(tester).onChangeEnd!(20);
      await tester.pumpAndSettle();

      expect(find.text('Then there are no stars'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(confidenceThresholdProvider), before);
    });

    testWidgets('raising the threshold never asks', (tester) async {
      // Deliberately asymmetric: a stricter bar produces fewer and safer
      // detections and cannot be abused.
      await pumpSettings(tester, view: SettingsView.advanced);

      thresholdSlider(tester).onChangeEnd!(90);
      await tester.pumpAndSettle();

      expect(find.text('Then there are no stars'), findsNothing);
      expect(container.read(confidenceThresholdProvider), 90);
    });

    testWidgets('confirming lowers it and says scoring is paused', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      thresholdSlider(tester).onChangeEnd!(20);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch off anyway'));
      await tester.pumpAndSettle();

      expect(container.read(confidenceThresholdProvider), 20);
      expect(find.textContaining('No stars at the moment'), findsOneWidget);
    });

    testWidgets('an already-paused threshold does not ask again', (
      tester,
    ) async {
      // Moving from 20 to 25 is still paused; asking a second time would be
      // noise rather than information.
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'confidence_threshold': 20},
      );

      thresholdSlider(tester).onChangeEnd!(25);
      await tester.pumpAndSettle();

      expect(find.text('Then there are no stars'), findsNothing);
      expect(container.read(confidenceThresholdProvider), 25);
    });
  });
}
