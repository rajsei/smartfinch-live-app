// =============================================================================
// The shared day image — LOG-11, KID-07, NFA-07
// =============================================================================
//
// This is the only thing that leaves the phone, so most of these tests are
// about **absence**. What is on the card can be checked by looking at it; what
// is missing cannot, and it is the half that matters.
//
// The place name is the sharp case. `LOG-13` lets a child type free text and
// `KID-07` says free text must never reach another person — so "Oma" lives on
// the day card inside the app and must not survive into the picture. The two
// requirements meet in exactly one widget, and nothing on screen would look
// wrong if it were got wrong.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/history/services/share_file_params.dart';
import 'package:smartfinch/features/journal/day_share_screen.dart';
import 'package:smartfinch/features/journal/journal_models.dart';
import 'package:smartfinch/features/journal/journal_providers.dart';
import 'package:smartfinch/features/journal/journal_day_screen.dart';
import 'package:smartfinch/features/journal/widgets/day_image_card.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

void main() {
  final may4 = DateTime(2026, 5, 4);

  JournalDayDetail dayWith({
    int stars = 450,
    List<String> places = const [],
    List<JournalSpecies> scored = const [],
  }) => JournalDayDetail(
    day: JournalDay(
      dayKey: '2026-05-04',
      date: may4,
      stars: stars,
      speciesCount: scored.length,
      placeNames: places,
    ),
    scored: scored,
  );

  JournalSpecies species(String name, {bool isNew = false}) => JournalSpecies(
    scientificName: name,
    firstHeardAt: may4,
    stars: 50,
    isNew: isNew,
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('LOG-11 · what is on the card', () {
    testWidgets('the date, the stars and the species', (tester) async {
      await pump(
        tester,
        DayImageCard(
          detail: dayWith(
            scored: [species('Turdus merula'), species('Sitta europaea')],
          ),
        ),
      );

      expect(find.text('Monday, May 4, 2026'), findsOneWidget);
      expect(find.text('450'), findsOneWidget);
      expect(find.text('2 species'), findsOneWidget);
      expect(find.text('Turdus merula'), findsOneWidget);
    });

    testWidgets('first finds are called out', (tester) async {
      await pump(
        tester,
        DayImageCard(
          detail: dayWith(
            scored: [
              species('Turdus merula', isNew: true),
              species('Sitta europaea'),
            ],
          ),
        ),
      );

      expect(find.textContaining('1 new species'), findsOneWidget);
    });

    testWidgets('a day with no first find says nothing about it', (
      tester,
    ) async {
      await pump(
        tester,
        DayImageCard(detail: dayWith(scored: [species('Turdus merula')])),
      );

      expect(find.textContaining('new species'), findsNothing);
    });

    testWidgets('a long list is trimmed rather than run off the card', (
      tester,
    ) async {
      await pump(
        tester,
        DayImageCard(
          detail: dayWith(
            scored: [
              for (var i = 0; i < DayImageCard.namedSpecies + 4; i++)
                species('Species $i'),
            ],
          ),
        ),
      );

      expect(find.text('+4 more'), findsOneWidget);
      expect(find.text('Species 0'), findsOneWidget);
      expect(find.text('Species ${DayImageCard.namedSpecies}'), findsNothing);
    });
  });

  group('KID-07 · what the card must never carry', () {
    testWidgets('not the place the child named', (tester) async {
      // LOG-13 free text meets KID-07 in this one widget. It is on the day
      // card inside the app and must not survive into the picture.
      await pump(
        tester,
        DayImageCard(
          detail: dayWith(
            places: ['Oma', 'Schulweg'],
            scored: [species('Turdus merula')],
          ),
        ),
      );

      expect(find.text('Oma'), findsNothing);
      expect(find.text('Schulweg'), findsNothing);
      expect(find.textContaining('Oma'), findsNothing);
    });

    testWidgets('the picture is captured from the card on screen', (
      tester,
    ) async {
      // "What you see is what grandma gets" holds by construction only while
      // the boundary that gets rendered to PNG wraps the previewed card. A
      // second, off-screen copy would be free to drift from this one.
      await pump(
        tester,
        DayShareScreen(detail: dayWith(scored: [species('Turdus merula')])),
      );

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(
              of: find.byType(DayImageCard),
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      final image = await boundary.toImage(pixelRatio: 3);
      addTearDown(image.dispose);

      // 360 logical pixels at ratio 3 — the size chat apps want, and proof
      // that the previewed subtree is the one that can be rendered.
      expect(image.width, (DayImageCard.width * 3).round());
      expect(image.height, greaterThan(0));
    });

    testWidgets('the preview says so, so nobody has to squint', (tester) async {
      await pump(
        tester,
        DayShareScreen(detail: dayWith(scored: [species('Turdus merula')])),
      );

      expect(find.textContaining('stay on this phone'), findsOneWidget);
    });
  });

  group('LOG-11 · getting to it', () {
    testWidgets('the day screen offers to share', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            journalDayProvider.overrideWith(
              (ref, key) async => dayWith(scored: [species('Turdus merula')]),
            ),
            journalDaySessionsProvider.overrideWith((ref, key) async => []),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JournalDayScreen(dayKey: '2026-05-04'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(AppIcons.share));
      await tester.pumpAndSettle();

      // The preview, not a share sheet: a child sends the picture after
      // seeing it, which is the whole safeguard.
      expect(find.byType(DayShareScreen), findsOneWidget);
      expect(find.text('Share this day'), findsOneWidget);
    });

    testWidgets('a day with nothing on it has nothing to share', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            journalDayProvider.overrideWith(
              (ref, key) async => dayWith(stars: 0),
            ),
            journalDaySessionsProvider.overrideWith((ref, key) async => []),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const JournalDayScreen(dayKey: '2026-05-04'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.share), findsNothing);
    });
  });

  test('LOG-11 · a PNG is shared as a picture, not as a file', () {
    // Without a real type, chat apps offer the day image as a download
    // instead of showing it — which defeats the whole point of an image.
    expect(
      mimeTypeForSharedPath('/tmp/smartfinch-2026-05-04.png'),
      'image/png',
    );
  });
}
