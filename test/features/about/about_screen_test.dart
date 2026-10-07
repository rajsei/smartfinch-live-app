// =============================================================================
// AboutScreen — the links
// =============================================================================
//
// Where the app and BirdNET can be found is *named*, not linked: a children's
// app sends nobody out of it with a tap. The source address is this app's, not
// the BirdNET Live repository it is forked from; the BirdNET website stays,
// because the model is theirs; and the name is the one the child reads —
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
import 'package:smartfinch/shared/utils/app_icons.dart';

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

  testWidgets('names the source, the website and BirdNET as text', (
    tester,
  ) async {
    await pump(tester);

    final text = find.byType(SelectableText);
    expect(text, findsOneWidget);
    final body = tester.widget<SelectableText>(text).data!;
    expect(body, contains('github.com/rajsei/smartfinch-live-app'));
    expect(body, contains('schlaumeise.org'));
    expect(body, contains('birdnet.cornell.edu'));
    // Addresses to read and copy, not to follow.
    expect(body, isNot(contains('https://')));
  });

  testWidgets('and sends nobody out of the app except to the policies', (
    tester,
  ) async {
    // App stores ask for a parental gate in front of every link out of a
    // children's app. The two policies must stay reachable; nothing else
    // opens a browser.
    await pump(tester);

    final outbound = find.byIcon(AppIcons.openInNew);
    expect(outbound, findsNWidgets(2));
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Donate to BirdNET'), findsNothing);
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

  testWidgets('in German the text carries the German name', (tester) async {
    await pump(tester, locale: 'de');

    final body =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(body, startsWith('Der Quellcode von Schlaumeise'));
  });
}
