// =============================================================================
// The live scoring UI — what a child actually reads
// =============================================================================
//
// LIVE-02, LIVE-03, LIVE-04, LIVE-08 and LIVE-18 are all requirements about
// *text on a screen*, so they are tested as text on a screen. The wording is
// asserted rather than the widget type: "already collected today ✓" is the
// requirement, a `_RepeatChip` is an implementation detail.
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/core/services/location_service.dart';
import 'package:smartfinch/features/audio/audio_providers.dart';
import 'package:smartfinch/features/explore/explore_providers.dart';
import 'package:smartfinch/features/live/widgets/day_summary_bar.dart';
import 'package:smartfinch/features/live/widgets/first_find_celebration.dart';
import 'package:smartfinch/features/live/widgets/score_chips.dart';
import 'package:smartfinch/features/scoring/live_score_board.dart';
import 'package:smartfinch/features/scoring/scoring_providers.dart';
import 'package:smartfinch/features/scoring/scoring_engine.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/features/settings/settings_screen.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

/// Somewhere with a position, which is the ordinary case.
const _berlin = AppLocation(latitude: 52.52, longitude: 13.405);

void main() {
  /// Pumps [child] with the scoring providers wired.
  ///
  /// [board] replaces the shared score board; [scoringPaused] turns the species
  /// filter off through the real setting rather than stubbing the provider, so
  /// the test exercises the same path `PKT-20` runs in the app. [prefs] adds
  /// any other stored setting.
  ///
  /// [location] is what the position lookup returns. A real position unless a
  /// test says otherwise: left to itself the lookup asks the platform, finds
  /// no GPS in a test, and every day bar would report "no location".
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    LiveScoreBoard? board,
    bool scoringPaused = false,
    Map<String, Object> prefs = const {},
    Future<AppLocation?> Function()? location,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (scoringPaused) 'species_filter_mode': 'off',
      ...prefs,
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          currentLocationProvider.overrideWith(
            (ref) => (location ?? () async => _berlin)(),
          ),
          // For the tests that open settings: the Audio section's device
          // picker would otherwise build a real capture service.
          inputDevicesProvider.overrideWith((ref) async => const []),
          if (board != null)
            liveScoreBoardProvider.overrideWith((ref) => board),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
  }

  group('LIVE-02 · the stars chip', () {
    testWidgets('shows what was earned, with a plus', (tester) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(stars: 100, multiplier: ScoreMultiplier.none),
        ),
      );

      expect(find.text('⭐ +100'), findsOneWidget);
    });

    testWidgets('shows nothing when there is no score yet', (tester) async {
      // A detection that arrived while scoring was paused, or one still being
      // written. An empty gap beats a zero — a zero looks like a verdict.
      await pump(tester, const DetectionScoreChips(score: null));

      expect(find.textContaining('⭐'), findsNothing);
      expect(find.textContaining('0'), findsNothing);
    });

    testWidgets('a paused detection shows nothing either', (tester) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 0,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.scoringPaused,
          ),
        ),
      );

      expect(find.textContaining('⭐'), findsNothing);
      // The day bar says it once for every card; the card stays quiet.
      expect(find.textContaining('no stars'), findsNothing);
    });
  });

  // A blank card next to a bird the child can hear reads as the app not
  // working. These two reasons used to leave it blank.
  group('why a bird earned nothing', () {
    testWidgets('not expected here this week says so', (tester) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 0,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.notOnLocalList,
          ),
        ),
      );

      expect(
        find.text('no stars — not expected here this week'),
        findsOneWidget,
      );
    });

    testWidgets('no location says so', (tester) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 0,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.noLocation,
          ),
        ),
      );

      expect(find.text('no stars — no location'), findsOneWidget);
    });

    testWidgets('and is read out with its reason', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 0,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.noLocation,
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(
          'No stars, because the app has no location right now',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('a species collected earlier today stays collected', (
      tester,
    ) async {
      // It scored this morning; now the position is gone. It would have been
      // a repeat either way, and "already collected" is the truer line.
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 100,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.noLocation,
          ),
        ),
      );

      expect(find.text('already collected today ✓'), findsOneWidget);
      expect(find.textContaining('no location'), findsNothing);
    });
  });

  group('LIVE-04 · the multiplier chip', () {
    testWidgets('names the reason and the factor, not just the total', (
      tester,
    ) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 300,
            multiplier: ScoreMultiplier.firstFind,
            isFirstFind: true,
          ),
        ),
      );

      // "NEW ×3" beside "⭐ +300" — a child who sees 300 where they saw 100
      // yesterday needs the reason, or the app reads as arbitrary.
      expect(find.text('NEW ×3'), findsOneWidget);
      expect(find.text('⭐ +300'), findsOneWidget);
    });

    testWidgets('each multiplier has its own label', (tester) async {
      for (final entry
          in {
            ScoreMultiplier.firstFind: 'NEW ×3',
            ScoreMultiplier.regular: 'REGULAR ×2',
            ScoreMultiplier.permanentGuest: 'ALWAYS HERE ×3',
            ScoreMultiplier.yearFirst: 'FIRST THIS YEAR ×2',
          }.entries) {
        await pump(
          tester,
          DetectionScoreChips(
            score: LiveSpeciesScore(stars: 100, multiplier: entry.key),
          ),
        );
        expect(find.text(entry.value), findsOneWidget, reason: '${entry.key}');
      }
    });

    testWidgets('an unmultiplied award shows no chip', (tester) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(stars: 50, multiplier: ScoreMultiplier.none),
        ),
      );

      expect(find.textContaining('×'), findsNothing);
    });
  });

  group('LIVE-03 · the repeat line', () {
    testWidgets('says the species is collected, not that nothing happened', (
      tester,
    ) async {
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 50,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.alreadyScoredToday,
          ),
        ),
      );

      expect(find.text('already collected today ✓'), findsOneWidget);
      // The number is replaced, not shown alongside — two answers to one
      // question is exactly the confusion this requirement removes.
      expect(find.textContaining('⭐'), findsNothing);
    });

    testWidgets('a species that never scored today says something else', (
      tester,
    ) async {
      // Heard for the first time while scoring was paused: claiming it was
      // "already collected" would be a lie.
      await pump(
        tester,
        const DetectionScoreChips(
          score: LiveSpeciesScore(
            stars: 0,
            multiplier: ScoreMultiplier.none,
            skipReason: ScoringSkipReason.alreadyScoredToday,
          ),
        ),
      );

      expect(find.text('heard again'), findsOneWidget);
      expect(find.text('already collected today ✓'), findsNothing);
    });
  });

  group('LIVE-08 · the day total', () {
    testWidgets('shows stars and the species count', (tester) async {
      final board = LiveScoreBoard(
        const LiveScoreBoardState(
          summary: DaySummary(
            dayKey: '2026-05-04',
            stars: 850,
            speciesCount: 9,
          ),
        ),
      );

      await pump(tester, const DaySummaryBar(), board: board);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('850'), findsOneWidget);
      expect(find.text('9 species'), findsOneWidget);
    });

    testWidgets('an empty day reads as empty, not as zero species', (
      tester,
    ) async {
      final board = LiveScoreBoard.forDay('2026-05-04');

      await pump(tester, const DaySummaryBar(), board: board);

      expect(find.text('no species yet'), findsOneWidget);
    });
  });

  group('LIVE-18 · the test-mode notice', () {
    testWidgets('replaces the total rather than sitting beside it', (
      tester,
    ) async {
      final board = LiveScoreBoard(
        const LiveScoreBoardState(
          summary: DaySummary(
            dayKey: '2026-05-04',
            stars: 850,
            speciesCount: 9,
          ),
        ),
      );

      await pump(
        tester,
        const DaySummaryBar(),
        board: board,
        scoringPaused: true,
      );

      expect(
        find.text('Test mode — no stars, nothing collected'),
        findsOneWidget,
      );
      // A number next to a notice saying the number does not count is exactly
      // the ambiguity the requirement exists to remove.
      expect(find.text('850'), findsNothing);
    });

    testWidgets('says why, and that recordings are kept', (tester) async {
      await pump(tester, const DaySummaryBar(), scoringPaused: true);

      expect(find.text('The species filter is switched off.'), findsOneWidget);
      expect(find.textContaining('still recorded'), findsOneWidget);
    });

    testWidgets('names every reason that applies', (tester) async {
      // Both switches an adult might have moved, one line each — the fix for
      // one must not look like the fix for both.
      await pump(
        tester,
        const DaySummaryBar(),
        scoringPaused: true,
        prefs: const {'confidence_threshold': 20},
      );

      expect(find.text('The species filter is switched off.'), findsOneWidget);
      expect(
        find.text('The confidence threshold is below 35 %.'),
        findsOneWidget,
      );
    });

    testWidgets('names the effect first, then the cause', (tester) async {
      // "No stars" is something an eight-year-old can act on; "species filter
      // disabled" is not — so the headline must not be phrased that way. The
      // cause follows underneath, for the adult.
      await pump(tester, const DaySummaryBar(), scoringPaused: true);

      final headline = tester.widget<Text>(
        find.text('Test mode — no stars, nothing collected'),
      );
      expect(headline.data, contains('no stars'));
    });

    testWidgets('is not styled as an error', (tester) async {
      // Principle 1: there is never a punishment, and a child who finds this
      // after an adult changed a setting has done nothing wrong.
      await pump(tester, const DaySummaryBar(), scoringPaused: true);

      final context = tester.element(find.byType(ScoringPausedNotice));
      final scheme = Theme.of(context).colorScheme;
      final decoration =
          tester
                  .widget<Container>(
                    find
                        .descendant(
                          of: find.byType(ScoringPausedNotice),
                          matching: find.byType(Container),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;

      expect(decoration.color, isNot(scheme.error));
      expect(decoration.color, isNot(scheme.errorContainer));
    });
  });

  // A session without a position earns nothing, and it used to do so in
  // silence: the bar showed the total, the cards stayed blank, and the
  // journal said "outside scoring" afterwards.
  group('no location is said, not swallowed', () {
    // A fresh one per test: the provider scope disposes the board it was
    // given when the test ends.
    LiveScoreBoard board() => LiveScoreBoard(
      const LiveScoreBoardState(
        summary: DaySummary(dayKey: '2026-05-04', stars: 850, speciesCount: 9),
      ),
    );

    testWidgets('it replaces the total, and is not called test mode', (
      tester,
    ) async {
      await pump(
        tester,
        const DaySummaryBar(),
        board: board(),
        location: () async => null,
      );

      expect(
        find.text('Without a location there are no stars'),
        findsOneWidget,
      );
      expect(find.textContaining('find a location'), findsOneWidget);
      // "Test mode" would send an adult looking for a switch that is not
      // there.
      expect(find.textContaining('Test mode'), findsNothing);
      expect(find.text('850'), findsNothing);
    });

    testWidgets('a fix still on its way is not a warning', (tester) async {
      // Flashing "no location" for the seconds a fix takes would teach a
      // child that the warning is noise.
      final pending = Completer<AppLocation?>();
      await pump(
        tester,
        const DaySummaryBar(),
        board: board(),
        location: () => pending.future,
      );

      expect(find.text('850'), findsOneWidget);
      expect(find.textContaining('location'), findsNothing);

      pending.complete(_berlin);
      await tester.pump();
      expect(find.text('850'), findsOneWidget);
    });
  });

  group('the way to the setting', () {
    testWidgets('a paused setting opens the advanced page, to reveal it', (
      tester,
    ) async {
      await pump(tester, const DaySummaryBar(), scoringPaused: true);

      await tester.tap(find.text('Show in settings'));
      await tester.pumpAndSettle();

      final screen = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
      expect(screen.view, SettingsView.advanced);
      expect(screen.revealBlocker, isTrue);
      // And the page names the same reason the bar did.
      expect(find.text('The species filter is switched off.'), findsWidgets);
    });

    testWidgets('a missing location opens the plain page', (tester) async {
      await pump(tester, const DaySummaryBar(), location: () async => null);

      await tester.tap(find.text('Show in settings'));
      await tester.pumpAndSettle();

      final screen = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
      expect(screen.view, SettingsView.plain);
      expect(screen.revealBlocker, isTrue);
    });

    testWidgets('there is no button when nothing is wrong', (tester) async {
      await pump(tester, const DaySummaryBar());

      expect(find.text('Show in settings'), findsNothing);
    });
  });

  group('LIVE-06 · the first-find card', () {
    testWidgets('names the species and says where it went', (tester) async {
      await pump(
        tester,
        const FirstFindCard(
          announcement: FirstFindAnnouncement(
            names: ['Nuthatch'],
            images: {'Nuthatch': null},
          ),
        ),
      );

      expect(find.text('New species!'), findsOneWidget);
      expect(find.text('Nuthatch'), findsOneWidget);
      expect(find.text('Added to your collection.'), findsOneWidget);
    });

    testWidgets('a burst becomes one card listing all of them', (tester) async {
      await pump(
        tester,
        const FirstFindCard(
          announcement: FirstFindAnnouncement(
            names: ['Nuthatch', 'Robin', 'Blackcap'],
            images: {},
          ),
        ),
      );

      expect(find.text('3 new species!'), findsOneWidget);
      for (final name in ['Nuthatch', 'Robin', 'Blackcap']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('it goes away on its own', (tester) async {
      var dismissed = false;

      await pump(
        tester,
        FirstFindCard(
          announcement: const FirstFindAnnouncement(
            names: ['Nuthatch'],
            images: {},
          ),
          visibleFor: const Duration(seconds: 6),
          onDismissed: () => dismissed = true,
        ),
      );

      expect(dismissed, isFalse);
      await tester.pump(const Duration(seconds: 6));
      expect(dismissed, isTrue);
    });
  });

  group('LIVE-05 · the confetti', () {
    testWidgets('never intercepts a tap', (tester) async {
      // The child must be able to keep using the screen while it plays.
      await pump(tester, const ConfettiBurst());

      expect(
        find.descendant(
          of: find.byType(ConfettiBurst),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('finishes and reports it', (tester) async {
      var finished = false;

      await pump(
        tester,
        ConfettiBurst(
          duration: const Duration(milliseconds: 800),
          onFinished: () => finished = true,
        ),
      );

      await tester.pump(const Duration(milliseconds: 900));
      expect(finished, isTrue);
    });
  });
}
