// =============================================================================
// Two names, one app — the brand split
// =============================================================================
//
// In German the app is **Schlaumeise**; everywhere else it is **Smartfinch**.
// They are not translations of one another — *Schlaumeise* is a tit and a pun
// that only works in German — which is why each has its own artwork rather
// than one file with the wordmark swapped.
//
// The thing that would break silently: the picture and the caption drifting
// apart, so that a German child reads "Schlaumeise" under a finch. Both come
// from the locale, and these tests hold them to it.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/widgets/app_logo.dart';

void main() {
  group('which bird a language gets', () {
    test('German gets the Schlaumeise', () {
      expect(
        AppLogo.assetFor('de', AppLogoStyle.round),
        'assets/images/schlaumeise_logo_round.svg',
      );
    });

    test('everything else gets the Smartfinch', () {
      for (final code in [
        'en',
        'cs',
        'es',
        'fr',
        'it',
        'nb',
        'nl',
        'pl',
        'pt',
        'ru',
        'zh',
      ]) {
        expect(
          AppLogo.assetFor(code, AppLogoStyle.round),
          'assets/images/smartfinch_logo_round.svg',
          reason: '$code should be Smartfinch',
        );
      }
    });

    test('a region or a capital does not change the answer', () {
      // `de_AT`, `de-CH` and `DE` all reach here as a language code, and a
      // Swiss child should not get a finch.
      expect(
        AppLogo.assetFor('DE', AppLogoStyle.round),
        contains('schlaumeise'),
      );
    });

    test('every style resolves to a file that exists', () {
      for (final code in ['de', 'en']) {
        for (final style in AppLogoStyle.values) {
          final asset = AppLogo.assetFor(code, style);
          expect(
            File(asset).existsSync(),
            isTrue,
            reason: '$asset is referenced but not in the repository',
          );
        }
      }
    });
  });

  group('the caption agrees with the picture', () {
    Future<AppLocalizations> localisations(
      WidgetTester tester,
      String code,
    ) async {
      late AppLocalizations l10n;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(code),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      );
      return l10n;
    }

    testWidgets('German reads Schlaumeise', (tester) async {
      final l10n = await localisations(tester, 'de');

      expect(l10n.appTitle, 'Schlaumeise');
      expect(
        AppLogo.assetFor('de', AppLogoStyle.roundOnSolid),
        contains('schlaumeise'),
      );
    });

    testWidgets('and every other locale reads Smartfinch', (tester) async {
      for (final locale in AppLocalizations.supportedLocales) {
        if (locale.languageCode == 'de') continue;

        final l10n = await localisations(tester, locale.languageCode);
        expect(
          l10n.appTitle,
          'Smartfinch',
          reason: '${locale.languageCode} should read Smartfinch',
        );
      }
    });
  });
}
