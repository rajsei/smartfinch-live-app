// =============================================================================
// The rules page — SET-11
// =============================================================================
//
// Principle 6 as a screen, so the tests are about two things:
//
//   **The numbers come from `ScoringRules`.** A page with them typed into its
//   prose would go quietly wrong on the first rebalance — and be wrong in the
//   one place a child goes to check.
//
//   **The section the requirement names is actually there.** "Why do the
//   points change during the year?" is what stops week coupling reading as a
//   bug: same bird, same app, a different number.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/inference/geo_abundance.dart';
import 'package:smartfinch/features/rules/rules_screen.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const RulesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SET-11 · the numbers come from the rules object', () {
    testWidgets('every rarity level shows its real star value', (tester) async {
      await pump(tester);

      const rules = ScoringRules.current;
      for (final tier in ExploreTier.values) {
        expect(
          find.text('${rules.starsFor(tier)} ⭐'),
          findsOneWidget,
          reason: '$tier',
        );
      }
    });

    testWidgets('the multipliers show their real factors', (tester) async {
      await pump(tester);

      // ×3 twice (first find, always here) and ×2 twice (regular, year first).
      expect(find.text('×3'), findsNWidgets(2));
      expect(find.text('×2'), findsNWidgets(2));
    });

    testWidgets('the variety bonus quotes the real first threshold', (
      tester,
    ) async {
      await pump(tester);

      const rules = ScoringRules.current;
      final threshold = rules.varietyBonuses.keys.first;
      final stars = rules.varietyBonuses.values.first.stars;

      expect(
        find.textContaining('At $threshold different ones'),
        findsOneWidget,
      );
      expect(find.textContaining('$stars extra'), findsOneWidget);
    });
  });

  group('SET-11 · the sections a child comes here for', () {
    testWidgets('"why do the points change during the year?" is there', (
      tester,
    ) async {
      // The requirement names this section explicitly. Without it, week
      // coupling looks like a bug.
      await pump(tester);

      expect(
        find.text('Why do the points change during the year?'),
        findsOneWidget,
      );
    });

    testWidgets('and it explains it with a real example', (tester) async {
      await pump(tester);

      expect(find.textContaining('blackcap'), findsOneWidget);
      expect(find.textContaining('January'), findsOneWidget);
    });

    testWidgets('the location half is there too', (tester) async {
      // The value moves with the place as well as with the week (2.1), and a
      // child on holiday needs to have been told that in advance.
      await pump(tester);

      expect(find.text('And why somewhere else is different'), findsOneWidget);
    });

    testWidgets('PKT-07 is one sentence', (tester) async {
      await pump(tester);

      expect(
        find.text("Only the best bonus counts — they don't add up."),
        findsOneWidget,
      );
    });

    testWidgets('PKT-03 is explained as a reason to go somewhere', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('Each animal once a day'), findsOneWidget);
      expect(find.textContaining('beats standing still'), findsOneWidget);
    });
  });
}
