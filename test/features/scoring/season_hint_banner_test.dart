// =============================================================================
// The PKT-17 sentence on screen
// =============================================================================
//
// The requirement's example is a whole sentence — "Early! The barn swallow is
// normally only here from May" — so what is tested is the sentence, not the
// widget tree it arrives in. It has to name the species in the child's own
// language and the month in words, or it is a data readout rather than a
// lesson.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/scoring/season_hint.dart';
import 'package:smartfinch/features/scoring/widgets/season_hint_banner.dart';
import 'package:smartfinch/l10n/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    SeasonHint hint, {
    String species = 'Barn swallow',
    bool compact = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SeasonHintText(
            hint: hint,
            commonName: species,
            compact: compact,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('early', () {
    const early = SeasonHint(
      phase: SeasonPhase.early,
      seasonStartMonth: 5,
      seasonEndMonth: 9,
    );

    testWidgets('names the species and the month it normally arrives', (
      tester,
    ) async {
      await pump(tester, early);

      expect(
        find.text('Early! The Barn swallow is normally only here from May.'),
        findsOneWidget,
      );
    });

    testWidgets('the month is a word, not a number', (tester) async {
      // "from 5" is a data readout; "from May" is something a child can act
      // on next spring.
      await pump(tester, early);

      expect(find.textContaining('May'), findsOneWidget);
      expect(find.textContaining('from 5'), findsNothing);
    });

    testWidgets('it is marked with a growing thing, not a warning', (
      tester,
    ) async {
      await pump(tester, early);

      expect(find.text('🌱'), findsOneWidget);
    });
  });

  group('late', () {
    const late = SeasonHint(
      phase: SeasonPhase.late,
      seasonStartMonth: 5,
      seasonEndMonth: 9,
    );

    testWidgets('names when it normally leaves, not when it arrives', (
      tester,
    ) async {
      await pump(tester, late);

      expect(
        find.text(
          'Still here! The Barn swallow is normally gone after September.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('it has its own marker', (tester) async {
      await pump(tester, late);

      expect(find.text('🍂'), findsOneWidget);
      expect(find.text('🌱'), findsNothing);
    });
  });

  group('presentation', () {
    const hint = SeasonHint(
      phase: SeasonPhase.early,
      seasonStartMonth: 4,
      seasonEndMonth: 8,
    );

    testWidgets('the full form is a panel', (tester) async {
      await pump(tester, hint);

      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('the compact form has no panel around it', (tester) async {
      // Inside a detection card the row already sits on a surface; a second
      // one would read as a nested box.
      await pump(tester, hint, compact: true);

      expect(
        find.descendant(
          of: find.byType(SeasonHintText),
          matching: find.byType(Container),
        ),
        findsNothing,
      );
    });

    testWidgets('it is not styled as an error either way', (tester) async {
      // Being early is not a problem — it is the most interesting thing that
      // can happen on a walk in March.
      await pump(tester, hint);

      final context = tester.element(find.byType(SeasonHintText));
      final scheme = Theme.of(context).colorScheme;
      final panel = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(SeasonHintText),
              matching: find.byType(Container),
            )
            .first,
      );

      final decoration = panel.decoration! as BoxDecoration;
      expect(decoration.color, isNot(scheme.error));
      expect(decoration.color, isNot(scheme.errorContainer));
    });
  });
}
