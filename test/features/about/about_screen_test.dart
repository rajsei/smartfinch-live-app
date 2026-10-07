// =============================================================================
// AboutScreen — the links
// =============================================================================
//
// The source link points at this app, not at the BirdNET Live repository it is
// forked from; the BirdNET website stays, because the model is theirs; and the
// app's own website carries the app's name in the language the child reads —
// Schlaumeise in German, Smartfinch everywhere else.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/constants/app_constants.dart';
import 'package:smartfinch/features/about/about_screen.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  Future<void> pump(WidgetTester tester, {String locale = 'en'}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          packageInfoProvider.overrideWith(
            (ref) async => PackageInfo(
              appName: 'Smartfinch',
              packageName: 'test',
              version: '1.0.0',
              buildNumber: '1',
            ),
          ),
          // The taxonomy credit is not what this test is about, and loading
          // the real one reads a large asset.
          taxonomyServiceProvider.overrideWith(
            (ref) => Future.error(StateError('not in this test')),
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AboutScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  test('the source link is this app, and the website is its own', () {
    expect(
      AppConstants.githubUrl,
      'https://github.com/rajsei/smartfinch-live-app',
    );
    expect(AppConstants.websiteUrl, 'https://schlaumeise.org');
    // Kept: the model, and the science behind every star, are BirdNET's.
    expect(AppConstants.birdnetUrl, 'https://birdnet.cornell.edu');
  });

  testWidgets('lists the app website, the source and BirdNET', (tester) async {
    await pump(tester);

    expect(find.text('Smartfinch website'), findsOneWidget);
    expect(find.text('This app on GitHub'), findsOneWidget);
    expect(find.text('BirdNET Website'), findsOneWidget);
  });

  testWidgets('says whose app this is, and that it builds on BirdNET Live', (
    tester,
  ) async {
    // The rebrand once swapped the name into BirdNET Live's own credits and
    // funding, which made both claim something about this app.
    await pump(tester, locale: 'de');

    expect(
      find.textContaining(
        'Schlaumeise ist ein Promotionsprojekt der Technischen Universität '
        'Chemnitz und baut auf BirdNET Live auf.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Die Entwicklung von BirdNET Live wird'),
      findsOneWidget,
    );
  });

  testWidgets('in German the website carries the German name', (tester) async {
    await pump(tester, locale: 'de');

    expect(find.text('Schlaumeise-Webseite'), findsOneWidget);
    expect(find.text('BirdNET-Webseite'), findsOneWidget);
  });
}
