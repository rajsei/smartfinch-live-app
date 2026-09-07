// =============================================================================
// First-find celebration — confetti and a card, one at a time
// =============================================================================
//
// LIVE-05, LIVE-06, LIVE-07. Three constraints shape all of this:
//
//   **It must not block detection.** The confetti is a `CustomPainter` over the
//   existing tree and the card is a bottom sheet; neither touches the
//   inference loop, and both are capped in time (2 s and 6 s).
//
//   **A walk in the woods must not stack five popups.** First finds arrive in
//   bursts — a new place produces four species in ninety seconds. So they go
//   through a queue: at most one card is visible, and a burst that lands
//   together becomes one combined card rather than four in a row.
//
//   **A find that did not count is not celebrated.** The queue is fed from the
//   score board, which only records a first find when the detection actually
//   scored (PKT-20, LIVE-18). Celebrating a paused first find would be the
//   cruellest possible bug: the child sees confetti for a species that was
//   never added to anything.
//
// ### Reduced motion
//
// `MediaQuery.disableAnimations` skips the confetti and keeps the card. The
// information is the card; the confetti is the feeling. Losing the feeling is
// an accessibility setting, losing the information would be a bug. (SET-02's
// three-way animation level is 2.8 and will sit on top of this.)
// =============================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:smartfinch/l10n/app_localizations.dart';

/// Plays confetti for [duration], then removes itself.
///
/// A painter rather than a package: one screen needs it, it is ninety lines,
/// and a dependency for two seconds of animation is a poor trade.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.duration = const Duration(milliseconds: 1800),
    this.pieces = 40,
    this.onFinished,
  });

  final Duration duration;
  final int pieces;
  final VoidCallback? onFinished;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    // Seeded, so a golden test of this screen is not a lottery.
    final random = math.Random(7);
    _pieces = [for (var i = 0; i < widget.pieces; i++) _Piece.random(random)];
    _controller.forward().whenComplete(() => widget.onFinished?.call());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.secondary,
      Colors.amber,
    ];

    // Never intercepts a tap: the child must be able to keep using the screen
    // while this plays.
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder:
            (context, _) => CustomPaint(
              painter: _ConfettiPainter(
                pieces: _pieces,
                progress: _controller.value,
                palette: palette,
              ),
              size: Size.infinite,
            ),
      ),
    );
  }
}

class _Piece {
  _Piece({
    required this.x,
    required this.drift,
    required this.delay,
    required this.spin,
    required this.size,
    required this.colorIndex,
  });

  factory _Piece.random(math.Random random) => _Piece(
    x: random.nextDouble(),
    drift: random.nextDouble() * 0.3 - 0.15,
    delay: random.nextDouble() * 0.35,
    spin: random.nextDouble() * 6 - 3,
    size: 5 + random.nextDouble() * 5,
    colorIndex: random.nextInt(4),
  );

  /// Horizontal start, 0–1 of the width.
  final double x;

  /// Sideways travel over the fall, as a fraction of the width.
  final double drift;

  /// How long this piece waits before falling, 0–1 of the duration.
  final double delay;

  final double spin;
  final double size;
  final int colorIndex;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({
    required this.pieces,
    required this.progress,
    required this.palette,
  });

  final List<_Piece> pieces;
  final double progress;
  final List<Color> palette;

  @override
  void paint(Canvas canvas, Size size) {
    for (final piece in pieces) {
      final t = ((progress - piece.delay) / (1 - piece.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      // Fades out over the last third rather than vanishing on the last frame.
      final opacity = t > 0.66 ? (1 - (t - 0.66) / 0.34) : 1.0;
      final dx = (piece.x + piece.drift * t) * size.width;
      final dy = t * (size.height + 40) - 20;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(piece.spin * t * math.pi);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: piece.size,
          height: piece.size * 0.6,
        ),
        Paint()..color = palette[piece.colorIndex].withValues(alpha: opacity),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

// =============================================================================
// The card
// =============================================================================

/// One first find, or several that arrived together.
class FirstFindAnnouncement {
  const FirstFindAnnouncement({required this.names, required this.images});

  /// Display names, in the order they were found.
  final List<String> names;

  /// Image path per name, where one exists.
  final Map<String, String?> images;

  bool get isCombined => names.length > 1;
}

/// The non-modal card a first find puts on screen (LIVE-06).
///
/// A bottom sheet, dismissible by swipe, gone on its own after six seconds.
/// Not a dialog: a dialog would stop the session behind it, and the child is
/// still listening.
class FirstFindCard extends StatefulWidget {
  const FirstFindCard({
    super.key,
    required this.announcement,
    this.visibleFor = const Duration(seconds: 6),
    this.onDismissed,
  });

  final FirstFindAnnouncement announcement;
  final Duration visibleFor;
  final VoidCallback? onDismissed;

  /// Shows the card over [context] and completes when it goes away.
  static Future<void> show(
    BuildContext context,
    FirstFindAnnouncement announcement, {
    Duration visibleFor = const Duration(seconds: 6),
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // The two flags that make it non-modal in the way that matters: the
      // screen behind stays visible and the sheet never grabs focus from it.
      barrierColor: Colors.transparent,
      isScrollControlled: false,
      useSafeArea: true,
      builder:
          (sheetContext) => FirstFindCard(
            announcement: announcement,
            visibleFor: visibleFor,
            onDismissed: () {
              if (Navigator.of(sheetContext).canPop()) {
                Navigator.of(sheetContext).pop();
              }
            },
          ),
    );
  }

  @override
  State<FirstFindCard> createState() => _FirstFindCardState();
}

class _FirstFindCardState extends State<FirstFindCard> {
  /// Cancelled on dispose. A card whose screen has gone away must not keep a
  /// six-second timer alive behind it — and a swipe-dismiss disposes the card
  /// long before the timer would have fired.
  Timer? _autoDismiss;

  @override
  void initState() {
    super.initState();
    _autoDismiss = Timer(widget.visibleFor, () {
      if (mounted) widget.onDismissed?.call();
    });
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final announcement = widget.announcement;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              announcement.isCombined
                  ? l10n.liveNewSpeciesCombined(announcement.names.length)
                  : l10n.liveNewSpeciesSingle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final name in announcement.names)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Text('⭐', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              l10n.liveNewSpeciesSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
