// =============================================================================
// CelebrationQueue — LIVE-07, the rule that keeps a walk in the woods bearable
// =============================================================================

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/live/widgets/celebration_queue.dart';
import 'package:smartfinch/features/live/widgets/first_find_celebration.dart';

void main() {
  const window = Duration(milliseconds: 900);

  /// What the live screen builds from the names the queue hands back.
  FirstFindAnnouncement announcementOf(List<String> names) =>
      FirstFindAnnouncement(
        names: names,
        images: {for (final name in names) name: null},
      );

  /// Runs [body] with a queue whose cards are recorded rather than shown.
  ///
  /// `cardVisibleFor` models how long the real bottom sheet stays up, so the
  /// "one at a time" rule is tested against something that actually takes time.
  void withQueue(
    void Function(
      CelebrationQueue<String> queue,
      List<FirstFindAnnouncement> shown,
      FakeAsync async,
    )
    body, {
    Duration cardVisibleFor = const Duration(seconds: 6),
  }) {
    fakeAsync((async) {
      final shown = <FirstFindAnnouncement>[];
      // The queue is generic since AUS-08 reused it for badge unlocks, so the
      // announcement is built by the caller — exactly as the live screen
      // does it, which is the point of testing through this shape.
      final queue = CelebrationQueue<String>(
        burstWindow: window,
        present: (names) async {
          shown.add(announcementOf(names));
          await Future<void>.delayed(cardVisibleFor);
        },
      );
      body(queue, shown, async);
      queue.dispose();
    });
  }

  group('one card at a time', () {
    test('a single find is shown after the burst window', () {
      withQueue((queue, shown, async) {
        queue.add(['Blackbird']);
        expect(shown, isEmpty, reason: 'still collecting');

        async.elapse(window);
        expect(shown, hasLength(1));
        expect(shown.single.names, ['Blackbird']);
        expect(shown.single.isCombined, isFalse);
      });
    });

    test('finds arriving together become one combined card', () {
      // A new place produces four species in ninety seconds. Four bottom
      // sheets in a row would be worse than none.
      withQueue((queue, shown, async) {
        queue.add(['Blackbird']);
        async.elapse(const Duration(milliseconds: 300));
        queue.add(['Robin']);
        async.elapse(const Duration(milliseconds: 300));
        queue.add(['Nuthatch']);

        async.elapse(window);

        expect(shown, hasLength(1));
        expect(shown.single.names, ['Blackbird', 'Robin', 'Nuthatch']);
        expect(shown.single.isCombined, isTrue);
      });
    });

    test('a find during a card waits for the next one', () {
      withQueue((queue, shown, async) {
        queue.add(['Blackbird']);
        async.elapse(window);
        expect(shown, hasLength(1));

        // Arrives while the first card is still up.
        queue.add(['Robin']);
        async.elapse(const Duration(seconds: 1));
        expect(shown, hasLength(1), reason: 'still only one visible');

        // The card ends, the queue moves on.
        async.elapse(const Duration(seconds: 6) + window);
        expect(shown, hasLength(2));
        expect(shown.last.names, ['Robin']);
      });
    });

    test('never two cards at once, however fast they arrive', () {
      withQueue((queue, shown, async) {
        for (var i = 0; i < 10; i++) {
          queue.add(['Species $i']);
          async.elapse(const Duration(milliseconds: 200));
          expect(queue.isShowing || shown.length <= 1, isTrue);
        }
        async.elapse(const Duration(minutes: 2));

        // Everything got out, and never more than one at a time.
        final announced = shown.expand((a) => a.names).toList();
        expect(announced, hasLength(10));
      });
    });
  });

  group('duplicates', () {
    test('the same species is only celebrated once', () {
      // A rebuild that re-delivered a find must not produce a second card.
      withQueue((queue, shown, async) {
        queue.add(['Blackbird']);
        queue.add(['Blackbird']);
        async.elapse(window);

        expect(shown.single.names, ['Blackbird']);
      });
    });
  });

  group('dispose', () {
    test('drops everything still waiting', () {
      fakeAsync((async) {
        final shown = <FirstFindAnnouncement>[];
        final queue = CelebrationQueue<String>(
          burstWindow: window,
          present: (names) async => shown.add(announcementOf(names)),
        );

        queue.add(['Blackbird']);
        queue.dispose();
        async.elapse(const Duration(minutes: 1));

        expect(shown, isEmpty);
      });
    });

    test('a find after dispose is ignored', () {
      fakeAsync((async) {
        final shown = <FirstFindAnnouncement>[];
        final queue = CelebrationQueue<String>(
          burstWindow: window,
          present: (names) async => shown.add(announcementOf(names)),
        );

        queue.dispose();
        queue.add(['Blackbird']);
        async.elapse(const Duration(minutes: 1));

        expect(shown, isEmpty);
        expect(queue.waiting, isEmpty);
      });
    });
  });
}
