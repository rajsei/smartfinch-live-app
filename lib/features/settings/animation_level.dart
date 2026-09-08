// =============================================================================
// AnimationLevel — Full · Reduced · Off (SET-02, SET-03)
// =============================================================================
//
// Explicitly requested, and it does two jobs at once: accessibility and
// annoyance control. The same setting that lets a child who finds the confetti
// too much turn it down is the one that respects a system-wide reduce-motion
// preference.
//
// The three levels are not a volume knob — each one removes something specific:
//
//   **Full** — confetti and the species card. What the celebration layer in
//   `LIVE-05`/`LIVE-06` was built to do.
//   **Reduced** — confetti on a first find, no card. The moment is still
//   marked; nothing covers part of the screen or has to be waited out.
//   **Off** — numbers only. The stars still land on the cards and in the day
//   total; what goes away is everything that moves.
//
// ### What no level removes
//
// The **information**. A first find is still a first find at every level: the
// life-list row is written, the ×3 is paid, the journal marks it ✨ NEW. Only
// the celebration is a setting; losing the feeling is a preference, losing the
// fact would be a bug.
// =============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/settings_providers.dart';

/// How much the app is allowed to move (`SET-02`).
enum AnimationLevel {
  /// Confetti and the species card.
  full,

  /// Confetti on a first find, no card.
  reduced,

  /// Numbers only.
  off;

  /// Reads the persisted value, tolerating anything unexpected.
  ///
  /// An unrecognised string means the *most* animation rather than the least:
  /// a corrupted preference should not silently switch the game's celebrations
  /// off, because a child would have no way to connect the two.
  static AnimationLevel fromStorage(String? value) => switch (value) {
    'off' => AnimationLevel.off,
    'reduced' => AnimationLevel.reduced,
    _ => AnimationLevel.full,
  };

  String get storageValue => name;

  /// Whether confetti may play (`LIVE-05`).
  bool get allowsConfetti => this != AnimationLevel.off;

  /// Whether the first-find card may appear (`LIVE-06`).
  bool get allowsSpeciesCard => this == AnimationLevel.full;
}

/// The stored animation level, before the system preference is applied.
final animationLevelSettingProvider =
    StateNotifierProvider<StringSettingNotifier, String>((ref) {
      return StringSettingNotifier(
        ref.watch(sharedPreferencesProvider),
        PrefKeys.animationLevel,
        AnimationLevel.full.storageValue,
      );
    });

/// The level actually in force.
///
/// `SET-03`: a system-wide "reduce motion" preference pulls Full down to
/// Reduced automatically. It does **not** override an explicit *Off* — someone
/// who asked for no animation at all gets none — and it is deliberately not
/// written back to the setting, so turning the system preference off restores
/// what the child chose rather than what the phone decided for them.
AnimationLevel effectiveAnimationLevel(
  AnimationLevel stored, {
  required bool systemReducesMotion,
}) {
  if (!systemReducesMotion) return stored;
  return stored == AnimationLevel.full ? AnimationLevel.reduced : stored;
}

/// The level in force for [context], system preference included.
AnimationLevel animationLevelFor(BuildContext context, WidgetRef ref) {
  final stored = AnimationLevel.fromStorage(
    ref.watch(animationLevelSettingProvider),
  );
  return effectiveAnimationLevel(
    stored,
    systemReducesMotion: MediaQuery.of(context).disableAnimations,
  );
}
