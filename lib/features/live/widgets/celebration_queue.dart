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
//
// ### One queue, two kinds of celebration
//
// `AUS-08` asks for an unlock animation when a badge is earned, under "the
// same queuing rule as LIVE-07". Rather than write that rule twice, the queue
// is generic over what it is announcing: first finds carry species names,
// badge unlocks carry badge definitions, and the *behaviour* — burst
// collection, one at a time — is defined in exactly one place. Two copies
// would eventually disagree about what "at most one" means, and the bug would
// be a child watching four popups in a row.
// =============================================================================

import 'dart:async';

/// Collects things worth celebrating and hands them out one card at a time.
class CelebrationQueue<T> {
  CelebrationQueue({
    required this.present,
    this.burstWindow = const Duration(milliseconds: 900),
  });

  /// Shows one card for [items] and completes when it has gone away.
  ///
  /// The queue waits on this future, which is what keeps the "max 1 visible"
  /// rule true without the queue knowing anything about widgets.
  final Future<void> Function(List<T> items) present;

  /// How long to wait for more finds before showing the card.
  ///
  /// Short enough not to feel like a lag after a single find, long enough to
  /// catch the second and third bird of a burst.
  final Duration burstWindow;

  final List<T> _waiting = [];
  Timer? _burstTimer;
  bool _showing = false;
  bool _disposed = false;

  /// Items currently waiting for a card. Tests and diagnostics.
  List<T> get waiting => List.unmodifiable(_waiting);

  bool get isShowing => _showing;

  /// Queues one or more things to celebrate.
  ///
  /// Duplicates are ignored: a species can only be found for the first time
  /// once and a badge unlocked once, and a rebuild that re-delivered either
  /// must not produce a second card.
  void add(Iterable<T> items) {
    if (_disposed) return;

    for (final item in items) {
      if (!_waiting.contains(item)) _waiting.add(item);
    }
    if (_waiting.isEmpty || _showing) return;

    _burstTimer?.cancel();
    _burstTimer = Timer(burstWindow, _flush);
  }

  Future<void> _flush() async {
    if (_disposed || _showing || _waiting.isEmpty) return;

    final items = List<T>.from(_waiting);
    _waiting.clear();
    _showing = true;

    try {
      await present(items);
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
