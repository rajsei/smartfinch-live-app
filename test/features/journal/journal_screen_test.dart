// =============================================================================
// The Journal on screen — LOG-02, LOG-03, LOG-09, LOG-15
// =============================================================================
//
// These requirements are about *what a child reads*, so they are tested as
// text. The one that most needs a test is `LOG-15`: an outside-scoring species
// has to appear, be legible, and be visibly not counted — three things that a
// restyle could break one at a time without anything looking obviously wrong.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smartfinch/features/journal/journal_day_screen.dart';
import 'package:smartfinch/features/journal/journal_models.dart';
import 'package:smartfinch/features/journal/journal_providers.dart';
import 'package:smartfinch/features/journal/journal_repository.dart';
import 'package:smartfinch/features/journal/journal_screen.dart';
import 'package:smartfinch/features/scoring/scoring_rules.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';
import 'package:smartfinch/shared/providers/app_providers.dart';

void main() {
  final may4 = DateTime(2026, 5, 4);

  JournalDay dayWith({
    int stars = 450,
    int speciesCount = 8,
    int unscored = 0,
    List<String> preview = const ['Turdus merula'],
    List<String> places = const [],
  }) => JournalDay(
    dayKey: '2026-05-04',
    date: may4,
    stars: stars,
    speciesCount: speciesCount,
    unscoredSpeciesCount: unscored,
    speciesPreview: preview,
    placeNames: places,
  );

  JournalBucket weekOf(
    DateTime start, {
    int stars = 900,
    int speciesCount = 12,
    int newSpecies = 0,
    int activeDays = 3,
    JournalPeriod period = JournalPeriod.week,
  }) => JournalBucket(
    period: period,
    start: start,
    end: JournalRepository.endOfPeriod(start, period),
    stars: stars,
    speciesCount: speciesCount,
    newSpeciesCount: newSpecies,
    activeDays: activeDays,
  );

  /// Every scope the screen asked the bucket provider for, in order.
  final askedFor = <JournalScope>[];

  setUp(askedFor.clear);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    List<JournalDay>? days,
    List<JournalBucket>? buckets,
    JournalDayDetail? detail,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (days != null)
            journalDaysProvider.overrideWith((ref, scope) async {
              askedFor.add(scope);
              return days;
            }),
          // Narrowing is the repository's job (and is tested there); the
          // screen only has to ask for the right scope, so the fake answers
          // by level and reports what it was asked for.
          journalBucketsProvider.overrideWith((ref, scope) async {
            askedFor.add(scope);
            return [
              for (final bucket in buckets ?? const <JournalBucket>[])
                if (bucket.period == scope.period) bucket,
            ];
          }),
          if (detail != null)
            journalDayProvider.overrideWith((ref, key) async => detail),
          // The place editor reads its own sessions; nothing to name here.
          journalDaySessionsProvider.overrideWith((ref, key) async => []),
        ],
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

  group('LOG-02 · the day card', () {
    testWidgets('carries the date, the stars and the species count', (
      tester,
    ) async {
      await pump(tester, const JournalScreen(), days: [dayWith()]);

      expect(find.text('⭐ 450'), findsOneWidget);
      expect(find.text('8 species'), findsOneWidget);
    });

    testWidgets('the two nearest days get a word, not a date', (tester) async {
      // "Today" and "Yesterday" are what a child is actually looking for.
      final today = DateTime.now();
      await pump(
        tester,
        const JournalScreen(),
        days: [
          JournalDay(
            dayKey: '2026-05-04',
            date: DateTime(today.year, today.month, today.day),
            speciesCount: 3,
          ),
        ],
      );

      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('shows the place the child named (LOG-13)', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [
          dayWith(places: ['Oma', 'Schulweg']),
        ],
      );

      expect(find.text('Oma · Schulweg'), findsOneWidget);
    });

    testWidgets('an empty journal explains itself', (tester) async {
      await pump(tester, const JournalScreen(), days: []);

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(find.text('Every day you listen shows up here.'), findsOneWidget);
    });
  });

  group('LOG-15 · what did not count, on the card', () {
    testWidgets('is a second line under the day total', (tester) async {
      await pump(tester, const JournalScreen(), days: [dayWith(unscored: 3)]);

      // "8 species · ⭐ 450" with "3 more outside scoring" underneath — the
      // day total stays honest and the recordings are still there.
      expect(find.text('8 species'), findsOneWidget);
      expect(find.text('3 more outside scoring'), findsOneWidget);
    });

    testWidgets('is absent when everything counted', (tester) async {
      await pump(tester, const JournalScreen(), days: [dayWith()]);

      expect(find.textContaining('outside scoring'), findsNothing);
    });
  });

  group('LOG-03 · the day detail', () {
    JournalDayDetail detailWith({
      List<JournalSpecies> scored = const [],
      List<JournalSpecies> outside = const [],
      List<JournalBonus> bonuses = const [],
    }) => JournalDayDetail(
      day: dayWith(speciesCount: scored.length, unscored: outside.length),
      scored: scored,
      outsideScoring: outside,
      bonuses: bonuses,
    );

    testWidgets('a species shows its points and the multiplier', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: detailWith(
          scored: [
            JournalSpecies(
              scientificName: 'Erithacus rubecula',
              firstHeardAt: may4.add(const Duration(hours: 8)),
              stars: 300,
              multiplier: ScoreMultiplier.firstFind,
            ),
          ],
        ),
      );

      // A child who sees 300 here and 50 next to a blackbird works out the
      // rule from the chip. A bare number teaches nothing.
      expect(find.text('⭐ 300'), findsOneWidget);
      expect(find.text('NEW ×3'), findsOneWidget);
    });

    testWidgets('an unmultiplied award shows only the number', (tester) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: detailWith(
          scored: [
            JournalSpecies(
              scientificName: 'Turdus merula',
              firstHeardAt: may4,
              stars: 50,
            ),
          ],
        ),
      );

      expect(find.text('⭐ 50'), findsOneWidget);
      expect(find.textContaining('×'), findsNothing);
    });

    testWidgets('day bonuses are named, not just numbered', (tester) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: detailWith(
          bonuses: const [JournalBonus(key: 'variety', stars: 50)],
        ),
      );

      expect(find.text('Many different species'), findsOneWidget);
      expect(find.text('+50'), findsOneWidget);
    });
  });

  group('LOG-09 · the ✨ NEW marker', () {
    testWidgets('appears on a first find', (tester) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 1),
          scored: [
            JournalSpecies(
              scientificName: 'Upupa epops',
              firstHeardAt: may4,
              stars: 3000,
              multiplier: ScoreMultiplier.firstFind,
              isNew: true,
            ),
          ],
        ),
      );

      expect(find.text('✨ NEW'), findsOneWidget);
    });

    testWidgets('does not appear on a species heard before', (tester) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 1),
          scored: [
            JournalSpecies(
              scientificName: 'Turdus merula',
              firstHeardAt: may4,
              stars: 50,
            ),
          ],
        ),
      );

      expect(find.text('✨ NEW'), findsNothing);
    });
  });

  group('LOG-15 · what did not count, in the detail', () {
    Future<void> pumpWithOutside(WidgetTester tester) => pump(
      tester,
      const JournalDayScreen(dayKey: '2026-05-04'),
      detail: JournalDayDetail(
        day: dayWith(speciesCount: 1, unscored: 2),
        scored: [
          JournalSpecies(
            scientificName: 'Turdus merula',
            firstHeardAt: may4,
            stars: 50,
          ),
        ],
        outsideScoring: [
          JournalSpecies(
            scientificName: 'Sitta europaea',
            firstHeardAt: may4,
            scored: false,
          ),
          JournalSpecies(
            scientificName: 'Upupa epops',
            firstHeardAt: may4,
            scored: false,
          ),
        ],
      ),
    );

    testWidgets('the species are listed, not hidden', (tester) async {
      await pumpWithOutside(tester);

      expect(find.text('Sitta europaea'), findsOneWidget);
      expect(find.text('Upupa epops'), findsOneWidget);
    });

    testWidgets('they are marked and set apart', (tester) async {
      await pumpWithOutside(tester);

      expect(find.text('2 species outside scoring'), findsOneWidget);
      expect(find.text('no stars'), findsNWidgets(2));
    });

    testWidgets('the explanation says the recordings are kept', (tester) async {
      await pumpWithOutside(tester);

      expect(find.textContaining('recordings are kept'), findsOneWidget);
    });

    testWidgets('each species says why it did not count', (tester) async {
      // Not "no stars" three times: the reason is what an adult needs to fix
      // anything, and "scoring was off" for a bird heard without a location
      // sent one looking for a switch that was never off.
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 0, unscored: 3),
          outsideScoring: [
            JournalSpecies(
              scientificName: 'Sitta europaea',
              firstHeardAt: may4,
              scored: false,
              outsideReason: OutsideScoringReason.scoringPaused,
            ),
            JournalSpecies(
              scientificName: 'Upupa epops',
              firstHeardAt: may4,
              scored: false,
              outsideReason: OutsideScoringReason.noLocation,
            ),
            JournalSpecies(
              scientificName: 'Corvus corax',
              firstHeardAt: may4,
              scored: false,
              outsideReason: OutsideScoringReason.notExpectedHere,
            ),
          ],
        ),
      );

      expect(find.text('scoring was off'), findsOneWidget);
      expect(find.text('no location'), findsOneWidget);
      expect(find.text('not expected here'), findsOneWidget);
      expect(find.text('no stars'), findsNothing);
      // The explainer promises exactly that.
      expect(find.textContaining('Each bird shows why'), findsOneWidget);
    });

    testWidgets('it is a note, not a warning', (tester) async {
      // Principle 1: the child did nothing wrong, so nothing here is styled
      // as an error.
      await pumpWithOutside(tester);

      final context = tester.element(find.byType(JournalDayScreen));
      final scheme = Theme.of(context).colorScheme;
      final banner = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('2 species outside scoring'),
              matching: find.byType(Container),
            )
            .last,
      );

      final decoration = banner.decoration! as BoxDecoration;
      expect(decoration.color, isNot(scheme.error));
      expect(decoration.color, isNot(scheme.errorContainer));
    });

    testWidgets('the section is absent when everything counted', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 1),
          scored: [
            JournalSpecies(
              scientificName: 'Turdus merula',
              firstHeardAt: may4,
              stars: 50,
            ),
          ],
        ),
      );

      expect(find.textContaining('outside scoring'), findsNothing);
      expect(find.text('no stars'), findsNothing);
    });
  });

  // ===========================================================================
  // LOG-04 / LOG-05 · zooming out, and knowing where you are
  // ===========================================================================
  //
  // The day list is what a child recognises, so it stays the level the journal
  // opens on. The wider levels exist because a full year of listening is three
  // hundred cards, and the sticky month header is what keeps that scroll from
  // becoming a wall of unlabelled dates.
  // ===========================================================================
  group('LOG-04 · the aggregation levels', () {
    testWidgets('the journal opens on days', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5, 4))],
      );

      // The day is on screen, the week is not.
      expect(find.textContaining('8 species'), findsOneWidget);
      expect(find.textContaining('Week of'), findsNothing);
    });

    testWidgets('all four levels are offered', (tester) async {
      await pump(tester, const JournalScreen(), days: [dayWith()]);

      for (final label in ['Days', 'Weeks', 'Months', 'Years']) {
        expect(
          find.widgetWithText(SegmentedButton<JournalPeriod>, label),
          findsOneWidget,
        );
      }
    });

    testWidgets('picking Weeks swaps the list', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5, 4), stars: 900)],
      );

      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Week of'), findsOneWidget);
      expect(find.text('⭐ 900'), findsOneWidget);
      expect(find.textContaining('3 days outside'), findsOneWidget);
    });

    testWidgets('a week card says how many species, once each', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5, 4), speciesCount: 12)],
      );

      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('12 species'), findsOneWidget);
    });

    testWidgets('first finds are called out — the number a child looks for', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5, 4), newSpecies: 4)],
      );

      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('4 new species'), findsOneWidget);
    });

    testWidgets('a week without a first find says nothing about it', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5, 4))],
      );

      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(find.textContaining('new species'), findsNothing);
    });

    testWidgets('a month is named, a year is a number', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [
          weekOf(DateTime(2026, 5), period: JournalPeriod.month),
          weekOf(DateTime(2026), period: JournalPeriod.year),
        ],
      );

      await tester.tap(find.text('Months'));
      await tester.pumpAndSettle();
      expect(find.text('May 2026'), findsOneWidget);

      await tester.tap(find.text('Years'));
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('an empty level explains itself rather than going blank', (
      tester,
    ) async {
      await pump(tester, const JournalScreen(), days: [dayWith()], buckets: []);

      await tester.tap(find.text('Months'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing here yet'), findsOneWidget);
    });
  });

  group('LOG-05 · the sticky month header', () {
    testWidgets('every month in the list gets one', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [
          dayWith(),
          JournalDay(
            dayKey: '2026-04-28',
            date: DateTime(2026, 4, 28),
            stars: 120,
            speciesCount: 3,
          ),
        ],
      );

      expect(find.text('May 2026'), findsOneWidget);
      expect(find.text('April 2026'), findsOneWidget);
    });

    testWidgets('it is pinned, so it stays put while its days scroll', (
      tester,
    ) async {
      await pump(tester, const JournalScreen(), days: [dayWith()]);

      final header = tester.widget<SliverPersistentHeader>(
        find.byType(SliverPersistentHeader).first,
      );
      expect(header.pinned, isTrue);
    });

    testWidgets('the wider levels carry their own labels instead', (
      tester,
    ) async {
      // A month header above a list of months would say the same thing twice.
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: [weekOf(DateTime(2026, 5), period: JournalPeriod.month)],
      );

      await tester.tap(find.text('Months'));
      await tester.pumpAndSettle();

      expect(find.byType(SliverPersistentHeader), findsNothing);
    });
  });

  // ===========================================================================
  // LOG-04 · drilling in
  // ===========================================================================
  //
  // A tap goes one level in and **narrows** to what was tapped, rather than
  // scrolling a full list to it. Both because that is what the child meant —
  // "show me 2026" — and because scrolling could not work: the lists are
  // capped, so a March week is not in the newest sixty days to scroll to.
  //
  // What the screen is responsible for is asking for the right span. The
  // narrowing itself is the repository's, and is tested there.
  // ===========================================================================
  group('LOG-04 · drilling into a card', () {
    /// Years, months and weeks, so any level has something to show.
    final everyLevel = [
      weekOf(DateTime(2026), period: JournalPeriod.year),
      weekOf(DateTime(2026, 5), period: JournalPeriod.month),
      weekOf(DateTime(2026, 5, 4)),
    ];

    Future<void> openYears(WidgetTester tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: everyLevel,
      );
      await tester.tap(find.text('Years'));
      await tester.pumpAndSettle();
    }

    testWidgets('a year opens its own months, not everyone\u2019s', (
      tester,
    ) async {
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();

      expect(
        askedFor.last,
        JournalScope.within(
          JournalPeriod.month,
          start: DateTime(2026),
          end: DateTime(2027),
        ),
      );
      expect(find.text('May 2026'), findsOneWidget);
    });

    testWidgets('a month opens its own weeks', (tester) async {
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('May 2026'));
      await tester.pumpAndSettle();

      expect(
        askedFor.last,
        JournalScope.within(
          JournalPeriod.week,
          start: DateTime(2026, 5),
          end: DateTime(2026, 6),
        ),
      );
    });

    testWidgets('a week opens its own days', (tester) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: everyLevel,
      );
      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Week of'));
      await tester.pumpAndSettle();

      // Monday to the following Monday — the same seven days PKT-05 counts.
      expect(
        askedFor.last,
        JournalScope.within(
          JournalPeriod.day,
          start: DateTime(2026, 5, 4),
          end: DateTime(2026, 5, 11),
        ),
      );
    });

    testWidgets('the day is the floor — it opens its detail, not a list', (
      tester,
    ) async {
      await pump(tester, const JournalScreen(), days: [dayWith()]);

      await tester.tap(find.text('8 species'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(JournalDayScreen), findsOneWidget);
    });

    testWidgets('the trail names the whole way in', (tester) async {
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('May 2026'));
      await tester.pumpAndSettle();

      expect(find.text('2026 › May 2026'), findsOneWidget);
    });

    testWidgets('tapping the trail climbs back out one step', (tester) async {
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('May 2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('2026 › May 2026'));
      await tester.pumpAndSettle();

      // Back at the months of 2026, not at the top of the journal.
      expect(find.text('May 2026'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('the system back button climbs out before it leaves', (
      tester,
    ) async {
      // A child who has tapped three times in should not land on the home
      // screen on the first press back.
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('May 2026'), findsNothing);
      expect(find.byType(JournalScreen), findsOneWidget);
    });

    testWidgets('the selector is the way out, so it drops the trail', (
      tester,
    ) async {
      await openYears(tester);
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(askedFor.last, const JournalScope(JournalPeriod.week));
      expect(find.textContaining('›'), findsNothing);
    });

    testWidgets('the chevron is the only sign the card goes anywhere', (
      tester,
    ) async {
      await pump(
        tester,
        const JournalScreen(),
        days: [dayWith()],
        buckets: everyLevel,
      );
      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.chevronRight), findsOneWidget);
    });

    testWidgets('a card that leads nowhere shows no chevron', (tester) async {
      // The bare card is what the tests of LOG-04's contents use; a chevron
      // that promised a tap and did nothing would be worse than none.
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: JournalBucketCard(bucket: weekOf(DateTime(2026, 5, 4))),
          ),
        ),
      );

      expect(find.byIcon(AppIcons.chevronRight), findsNothing);
    });
  });

  // ===========================================================================
  // LOG-07 · the row opens into the times it was heard
  // ===========================================================================
  //
  // The one level below a species, and where the old session concept lives on.
  // What has to hold: the row opens, every hearing is listed with its time and
  // how sure the app was, only the first one is marked as having counted, and
  // the bird's own page stays reachable now that a tap no longer opens it.
  // ===========================================================================
  group('LOG-07 · the hearings inside a species', () {
    JournalSpecies merulaHeard({
      List<JournalDetection> detections = const [],
      bool scored = true,
    }) => JournalSpecies(
      scientificName: 'Turdus merula',
      firstHeardAt: may4.add(const Duration(hours: 7)),
      stars: scored ? 50 : 0,
      scored: scored,
      detectionCount: detections.length,
      detections: detections,
    );

    JournalDetection heardAt(
      int hour,
      int minute, {
      double confidence = 0.87,
      String? clip,
      bool kept = false,
    }) => JournalDetection(
      id: 'd$hour$minute',
      heardAt: DateTime(2026, 5, 4, hour, minute),
      confidence: confidence,
      clipPath: clip,
      isFavourite: kept,
    );

    Future<void> openRow(
      WidgetTester tester, {
      required List<JournalDetection> detections,
      bool scored = true,
    }) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: scored ? 1 : 0, unscored: scored ? 0 : 1),
          scored: scored ? [merulaHeard(detections: detections)] : const [],
          outsideScoring:
              scored
                  ? const []
                  : [merulaHeard(detections: detections, scored: false)],
        ),
      );

      await tester.tap(find.text('Turdus merula'));
      await tester.pumpAndSettle();
    }

    testWidgets('a closed row shows nothing but the species', (tester) async {
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 1),
          scored: [
            merulaHeard(detections: [heardAt(7, 12), heardAt(9, 3)]),
          ],
        ),
      );

      expect(find.text('09:03'), findsNothing);
    });

    testWidgets('tapping opens every time it was heard', (tester) async {
      await openRow(
        tester,
        detections: [heardAt(7, 12), heardAt(7, 40), heardAt(9, 3)],
      );

      expect(find.text('07:12'), findsOneWidget);
      expect(find.text('07:40'), findsOneWidget);
      expect(find.text('09:03'), findsOneWidget);
    });

    testWidgets('only the first one is marked as having counted', (
      tester,
    ) async {
      // PKT-04 in one word, in the cheapest place in the app to teach it.
      await openRow(tester, detections: [heardAt(7, 12), heardAt(9, 3)]);

      expect(find.text('counted'), findsOneWidget);
    });

    testWidgets('nothing counted outside scoring, so nothing says it did', (
      tester,
    ) async {
      await openRow(
        tester,
        detections: [heardAt(7, 12), heardAt(9, 3)],
        scored: false,
      );

      expect(find.text('07:12'), findsOneWidget);
      expect(find.text('counted'), findsNothing);
    });

    testWidgets('each hearing says how sure the app was', (tester) async {
      await openRow(tester, detections: [heardAt(7, 12, confidence: 0.87)]);

      expect(find.text('87 %'), findsOneWidget);
    });

    testWidgets('a kept recording is marked as kept', (tester) async {
      await openRow(
        tester,
        detections: [
          heardAt(7, 12, clip: '/clips/a.wav'),
          heardAt(9, 3, clip: '/clips/b.wav', kept: true),
        ],
      );

      expect(find.byIcon(AppIcons.bookmarkFilled), findsOneWidget);
      expect(find.byIcon(AppIcons.graphicEq), findsOneWidget);
    });

    testWidgets('a hearing with no recording says so rather than going blank', (
      tester,
    ) async {
      // Retention has been through. That is ordinary, and the row still has
      // to render a time a child can read.
      await openRow(tester, detections: [heardAt(7, 12)]);

      expect(find.text('07:12'), findsOneWidget);
      expect(find.byIcon(AppIcons.volumeOffRounded), findsOneWidget);
      expect(find.byIcon(AppIcons.graphicEq), findsNothing);
    });

    testWidgets('the bird’s own page is still one tap away', (tester) async {
      // The tap that used to open it now expands, so the link has to be
      // inside — otherwise LOG-07 would have quietly removed SAM-06.
      await openRow(tester, detections: [heardAt(7, 12)]);

      expect(find.text('About this bird'), findsOneWidget);
    });

    testWidgets('tapping again closes it', (tester) async {
      await openRow(tester, detections: [heardAt(7, 12)]);
      expect(find.text('07:12'), findsOneWidget);

      await tester.tap(find.text('Turdus merula'));
      await tester.pumpAndSettle();

      expect(find.text('07:12'), findsNothing);
    });

    testWidgets('a species with no hearings left opens its page instead', (
      tester,
    ) async {
      // Nothing to expand into, so the row keeps its old behaviour rather
      // than becoming a tap that does nothing.
      await pump(
        tester,
        const JournalDayScreen(dayKey: '2026-05-04'),
        detail: JournalDayDetail(
          day: dayWith(speciesCount: 1),
          scored: [merulaHeard()],
        ),
      );

      expect(find.byIcon(AppIcons.expandMore), findsNothing);
    });
  });
}
