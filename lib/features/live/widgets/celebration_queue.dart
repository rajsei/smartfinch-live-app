// =============================================================================
// CelebrationQueue — at most one card, however many birds (LIVE-07)
// =============================================================================
//
// First finds do not arrive one at a time. A child who walks into a new place
// produces four new species in ninety seconds, and four bottom sheets in a row
// would be a worse experience than none: the fourth is still on screen when
// the bird that earned it is long gone.
//
// So the queue does two things:
//
//   **It collects a burst.** Names that arrive within [burstWindow] of each
//   other become one card — "3 new species!" — rather than three.
//   **It shows one at a time.** Anything arriving while a card is up waits for
//   it, and goes out as the next card.
//
// Pure Dart with an injected clock-free delay, so the burst behaviour can be
// tested with `FakeAsync` instead of by watching a screen for six seconds.
// =============================================================================

import 'dart:async';

import 'first_find_celebration.dart';

/// Collects first finds and hands them out one card at a time.
class CelebrationQueue {
  CelebrationQueue({
    required this.present,
    this.burstWindow = const Duration(milliseconds: 900),
  });

  /// Shows one card and completes when it has gone away.
  ///
  /// The queue waits on this future, which is what keeps the "max 1 visible"
  /// rule true without the queue knowing anything about widgets.
  final Future<void> Function(FirstFindAnnouncement announcement) present;

  /// How long to wait for more finds before showing the card.
  ///
  /// Short enough not to feel like a lag after a single find, long enough to
  /// catch the second and third bird of a burst.
  final Duration burstWindow;

  final List<String> _waiting = [];
  Timer? _burstTimer;
  bool _showing = false;
  bool _disposed = false;

  /// Names currently waiting for a card. Tests and diagnostics.
  List<String> get waiting => List.unmodifiable(_waiting);

  bool get isShowing => _showing;

  /// Queues one or more newly found species.
  ///
  /// Duplicates are ignored: a species can only be found for the first time
  /// once, and a rebuild that re-delivered it must not produce a second card.
  void add(Iterable<String> displayNames) {
    if (_disposed) return;

    for (final name in displayNames) {
      if (!_waiting.contains(name)) _waiting.add(name);
    }
    if (_waiting.isEmpty || _showing) return;

    _burstTimer?.cancel();
    _burstTimer = Timer(burstWindow, _flush);
  }

  Future<void> _flush() async {
    if (_disposed || _showing || _waiting.isEmpty) return;

    final names = List<String>.from(_waiting);
    _waiting.clear();
    _showing = true;

    try {
      await present(
        FirstFindAnnouncement(
          names: names,
          images: {for (final name in names) name: null},
        ),
      );
    } finally {
      _showing = false;
    }

    // Anything that arrived while the card was up goes out as the next one.
    if (!_disposed && _waiting.isNotEmpty) {
      _burstTimer?.cancel();
      _burstTimer = Timer(burstWindow, _flush);
    }
  }

  /// Drops everything pending — a session ended, or the screen is going away.
  void dispose() {
    _disposed = true;
    _burstTimer?.cancel();
    _waiting.clear();
  }
}
