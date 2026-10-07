// =============================================================================
// HelpScreen — where "How do I earn stars?" lives (SET-11)
// =============================================================================
//
// The rules page moved here from the settings on 2026-10-07: it is something a
// child reads, not something they set. What is worth asserting is that the
// door is there, near the top, and actually opens the page — a help screen that
// only *named* the rules would send a child looking for them all over again.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/home/help_screen.dart';
import 'package:smartfinch/features/rules/rules_screen.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(400, 800),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HelpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('names the question, on screen without scrolling', (
    tester,
  ) async {
    await pump(tester);

    final card = find.text('How do I earn stars?');
    expect(card, findsOneWidget);
    expect(tester.getRect(card).bottom, lessThan(800));
  });

  testWidgets('and opens the rules page', (tester) async {
    await pump(tester);

    await tester.tap(find.text('How do I earn stars?'));
    await tester.pumpAndSettle();

    expect(find.byType(RulesScreen), findsOneWidget);
    // What the page says is rules_screen_test.dart's business; here it is
    // enough that the door leads to it.
  });

  testWidgets('explains the bird, the stickers and the panel gesture', (
    tester,
  ) async {
    // Pulling the panel down is the one gesture on the home screen nothing
    // else explains (AVA-07, KID-04).
    await pump(tester, size: const Size(400, 2000));

    await tester.tap(find.text('Your bird and the stickers'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Pull the panel with the buttons down'),
      findsOne,
    );
  });

  testWidgets('the threshold tip says where the stars stop', (tester) async {
    // "Lower shows more birds" alone would send a child below the floor,
    // where there are no stars (PKT-20). The number comes from the rules.
    await pump(tester, size: const Size(400, 2400));

    final floor = ScoringRules.current.scoringThresholdFloor;
    expect(find.textContaining('Below $floor % there are no stars'), findsOne);
  });
}
