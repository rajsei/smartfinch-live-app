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
//
// **That whatever stops the stars can be found.** Named at the top of the
// page, marked where it lives, and one tap — or none, from the live screen —
// away.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/services/location_service.dart';
import 'package:smartfinch/features/audio/audio_providers.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/features/settings/settings_screen.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/providers/settings_providers.dart';

/// Somewhere with a position — the ordinary case.
const _berlin = AppLocation(latitude: 52.52, longitude: 13.405);

/// What the position lookup returns, changeable while a test runs.
final _position = StateProvider<AppLocation?>((ref) => _berlin);

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  Future<void> pumpSettings(
    WidgetTester tester, {
    SettingsView view = SettingsView.plain,
    Map<String, Object> initialPrefs = const {},
    AppLocation? location = _berlin,
    Size size = const Size(1200, 6000),
    bool revealBlocker = false,
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    prefs = await SharedPreferences.getInstance();

    // A tall surface, so every tile is on screen. The page is built all at
    // once, but a tap still needs its target where a finger could reach it.
    tester.view.physicalSize = size;
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
          // Left to itself the lookup asks the platform, finds no GPS in a
          // test, and every page would say there is no location.
          _position.overrideWith((ref) => location),
          currentLocationProvider.overrideWith(
            (ref) async => ref.watch(_position),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(view: view, revealBlocker: revealBlocker),
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
      const tileSubtitle =
          'Audio, detection, spectrogram (the picture of sound), recordings '
          'and backup';
      expect(find.text(tileSubtitle), findsNothing);
    });

    testWidgets('that subtitle is the one the plain screen carries', (
      tester,
    ) async {
      // Without this, a reworded subtitle would leave the assertion above
      // checking for text that exists nowhere — passing forever.
      await pumpSettings(tester);

      expect(
        find.text(
          'Audio, detection, spectrogram (the picture of sound), recordings '
          'and backup',
        ),
        findsOneWidget,
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

  group('what stops the stars is named, and marked where it lives', () {
    const label = 'This is why there are no stars right now';
    const bannerTitle = 'Why there are no stars right now';

    /// [text] inside a marked block. Found through the block's own label, so
    /// only a mark that is actually showing counts.
    Finder marked(String text) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (w) => '${w.runtimeType}' == '_BlockerHighlight',
        ),
      ),
      matching: find.text(text),
    );

    /// Whether [finder] is inside an 800-pixel-high screen.
    bool onScreen(WidgetTester tester, Finder finder) {
      final rect = tester.getRect(finder);
      return rect.top >= 0 && rect.bottom <= 800;
    }

    testWidgets('nothing is marked while scoring works', (tester) async {
      for (final view in SettingsView.values) {
        await pumpSettings(tester, view: view);

        expect(find.text(bannerTitle), findsNothing, reason: '$view');
        expect(find.text(label), findsNothing, reason: '$view');
      }
    });

    testWidgets('the species filter: named at the top, marked in place', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'species_filter_mode': 'off'},
      );

      expect(find.text(bannerTitle), findsOneWidget);
      expect(find.text('The species filter is switched off.'), findsOneWidget);
      expect(marked('Species filter'), findsOneWidget);
      expect(marked('Confidence threshold'), findsNothing);
    });

    testWidgets('the threshold: the slider is marked', (tester) async {
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'confidence_threshold': 20},
      );

      expect(
        find.text('The confidence threshold is below 35 %.'),
        findsOneWidget,
      );
      expect(marked('Confidence threshold'), findsOneWidget);
      expect(marked('Species filter'), findsNothing);
    });

    testWidgets('no location: the location block is marked', (tester) async {
      await pumpSettings(tester, location: null);
      await tester.pump();

      expect(find.textContaining('find a location'), findsOneWidget);
      expect(marked('Use GPS'), findsOneWidget);
      expect(marked('Advanced settings'), findsNothing);
    });

    testWidgets('a fix behind Advanced: the plain page marks the way there', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        initialPrefs: const {'species_filter_mode': 'off'},
      );

      expect(find.text('The species filter is switched off.'), findsOneWidget);
      expect(marked('Advanced settings'), findsOneWidget);

      await tester.tap(find.text('Advanced settings'));
      await tester.pumpAndSettle();

      // Opened onto the switch, not at the top of a long page.
      final pushed = tester.widget<SettingsScreen>(
        find.byType(SettingsScreen).last,
      );
      expect(pushed.view, SettingsView.advanced);
      expect(pushed.revealBlocker, isTrue);
    });

    testWidgets('"Show" scrolls to the marked setting', (tester) async {
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'species_filter_mode': 'off'},
        size: const Size(800, 800),
      );

      // Far down the page: the test means nothing if it starts on screen.
      expect(onScreen(tester, find.text(label)), isFalse);

      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();

      expect(onScreen(tester, find.text(label)), isTrue);
      expect(onScreen(tester, marked('Species filter')), isTrue);
    });

    testWidgets('opened to reveal it, the page gets there by itself', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'species_filter_mode': 'off'},
        size: const Size(800, 800),
        revealBlocker: true,
      );
      await tester.pumpAndSettle();

      expect(onScreen(tester, marked('Species filter')), isTrue);
    });

    testWidgets('the mark goes without rebuilding what is inside it', (
      tester,
    ) async {
      // The mark disappears at exactly the moment someone is using what it
      // marks: halfway through typing coordinates, the location resolves.
      // What was typed, and the keyboard, must survive that.
      await pumpSettings(
        tester,
        initialPrefs: const {'use_gps': false},
        location: null,
      );
      await tester.pump();
      expect(marked('Latitude'), findsOneWidget);

      final field = find.widgetWithText(TextField, 'Latitude');
      await tester.enterText(field, '48.1');
      EditableTextState editor() => tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      final before = editor();

      container.read(_position.notifier).state = _berlin;
      await tester.pump();
      await tester.pump();

      expect(find.text(label), findsNothing);
      expect(identical(editor(), before), isTrue);
      expect(editor().widget.focusNode.hasFocus, isTrue);
      expect(find.text('48.1'), findsOneWidget);
    });
  });

  // Two settings that used to mislead: one recorded into a file nothing could
  // play, the other moved the line between "shown" and "worth something"
  // without saying so.
  group('the recording switch', () {
    Finder switchTile() =>
        find.widgetWithText(SwitchListTile, 'Save recordings');

    testWidgets('a clip per detection, and no "full" left to choose', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      expect(tester.widget<SwitchListTile>(switchTile()).value, isTrue);
      expect(
        container.read(recordingModeProvider),
        RecordingModeSettingNotifier.clips,
      );
      // The three-way mode is gone, with the option that caused it.
      expect(find.text('Full'), findsNothing);
      expect(find.text('Detections only'), findsNothing);
      expect(find.text('Mode'), findsNothing);
    });

    testWidgets('switching it off puts the clip settings away with it', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);
      expect(find.text('Clip Context'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);

      await tester.tap(
        find.descendant(of: switchTile(), matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();

      expect(
        container.read(recordingModeProvider),
        RecordingModeSettingNotifier.off,
      );
      // Settings that describe a clip have nothing to describe.
      expect(find.text('Clip Context'), findsNothing);
      expect(find.text('Format'), findsNothing);
    });
  });

  group('the geo-filter slider says where a level begins', () {
    /// The geo-filter slider — the only one that runs to 0.5.
    Slider geoSlider(WidgetTester tester) => tester
        .widgetList<Slider>(find.byType(Slider))
        .firstWhere((s) => s.max == 0.5);

    testWidgets('0.03 is marked on the track, and named under it', (
      tester,
    ) async {
      await pumpSettings(tester, view: SettingsView.advanced);

      // The same limit the rarity scale uses, so filter and stars agree.
      expect(geoSlider(tester).secondaryTrackValue, 0.03);
      expect(find.textContaining('a species has a level here'), findsOneWidget);
    });

    testWidgets('below it, the slider says what comes through', (tester) async {
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'geo_threshold': 0.0},
      );

      expect(find.textContaining('have no level here'), findsOneWidget);
    });

    testWidgets('but it is not a pause — the stars keep coming', (
      tester,
    ) async {
      // Every species that does have a level here still scores, so saying
      // "there are no stars right now" would be false.
      await pumpSettings(
        tester,
        view: SettingsView.advanced,
        initialPrefs: const {'geo_threshold': 0.0},
      );

      expect(find.text('Why there are no stars right now'), findsNothing);
      expect(
        find.text('This is why there are no stars right now'),
        findsNothing,
      );
    });
  });
}
