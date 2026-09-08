// =============================================================================
// The badge unlock — AUS-08
// =============================================================================
//
// Two things have to hold, and both are about restraint rather than about the
// animation.
//
//   **A session must not open with a shower of cards.** The badge list is
//   derived from all of history (`AUS-12`), so the first look at it returns
//   everything a child has ever earned. Celebrating that would mean opening
//   the app after a month away and watching forty popups.
//
//   **Nothing is celebrated twice.** The same derivation runs again and again
//   during a session, and every run re-reports every badge.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/live/widgets/badge_unlock_card.dart';
import 'package:smartfinch/features/points/badge_watcher.dart';
import 'package:smartfinch/features/points/points_models.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

void main() {
  List<EarnedBadge> earned(List<BadgeDefinition> definitions) => [
    for (final definition in definitions) EarnedBadge(definition: definition),
  ];

  group('BadgeWatcher', () {
    test('⚠️ the first look celebrates nothing', () {
      // It is establishing what the child already had. A month away and forty
      // badges must not become forty cards.
      final watcher = BadgeWatcher();

      expect(watcher.newlyEarned(earned([kEarlyBird, kTenInOneGo])), isEmpty);
      expect(watcher.isPrimed, isTrue);
    });

    test('a badge that appears afterwards is new', () {
      final watcher = BadgeWatcher()..newlyEarned(earned([kEarlyBird]));

      final fresh = watcher.newlyEarned(earned([kEarlyBird, kDawnChorus]));

      expect(fresh.map((b) => b.key), [kDawnChorus.key]);
    });

    test('and is not new the second time it is reported', () {
      // Every derivation re-reports every badge, so this is the ordinary case
      // rather than an edge one.
      final watcher = BadgeWatcher()..newlyEarned(earned([kEarlyBird]));

      watcher.newlyEarned(earned([kEarlyBird, kDawnChorus]));
      final again = watcher.newlyEarned(earned([kEarlyBird, kDawnChorus]));

      expect(again, isEmpty);
    });

    test('several at once come back together, for one card', () {
      final watcher = BadgeWatcher()..newlyEarned(const []);

      final fresh = watcher.newlyEarned(
        earned([kEarlyBird, kDawnChorus, kTenInOneGo]),
      );

      expect(fresh, hasLength(3));
    });

    test('a reset makes the next look an opening one again', () {
      final watcher = BadgeWatcher()..newlyEarned(earned([kEarlyBird]));
      watcher.reset();

      expect(watcher.newlyEarned(earned([kEarlyBird, kDawnChorus])), isEmpty);
    });

    group('throttling', () {
      final at1200 = DateTime(2026, 5, 4, 12);

      test('the first look is always due', () {
        expect(BadgeWatcher().isDue(at1200), isTrue);
      });

      test('a second look straight after is not', () {
        final watcher = BadgeWatcher(
          minimumInterval: const Duration(seconds: 20),
        )..isDue(at1200);

        expect(watcher.isDue(at1200.add(const Duration(seconds: 5))), isFalse);
      });

      test('and is once the interval has passed', () {
        final watcher = BadgeWatcher(
          minimumInterval: const Duration(seconds: 20),
        )..isDue(at1200);

        expect(watcher.isDue(at1200.add(const Duration(seconds: 21))), isTrue);
      });
    });
  });

  group('BadgeUnlockCard', () {
    Future<void> pump(WidgetTester tester, List<BadgeDefinition> badges) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: BadgeUnlockCard(badges: badges)),
        ),
      );
      await tester.pump();
    }

    testWidgets('names the badge and says what earned it', (tester) async {
      await pump(tester, [kEarlyBird]);

      expect(find.text('Badge earned!'), findsOneWidget);
      expect(find.text('The early bird'), findsOneWidget);
      // The rule, in the one moment a child is certain to be reading.
      expect(
        find.text('Heard something before 9 in the morning'),
        findsOneWidget,
      );

      await tester.pump(BadgeUnlockCard.visibleFor);
    });

    testWidgets('a burst is one card, not three', (tester) async {
      await pump(tester, [kEarlyBird, kDawnChorus, kTenInOneGo]);

      expect(find.text('3 badges earned!'), findsOneWidget);
      expect(find.byType(BadgeUnlockCard), findsOneWidget);

      await tester.pump(BadgeUnlockCard.visibleFor);
    });

    testWidgets('its timer does not outlive it', (tester) async {
      // The sheet can be swiped away, and a pending dismissal that survived
      // would try to pop a route that is already gone.
      await pump(tester, [kEarlyBird]);
      await tester.pumpWidget(const SizedBox());

      // No pending-timer failure at the end of the test is the assertion.
      await tester.pump(BadgeUnlockCard.visibleFor);
    });
  });
}
