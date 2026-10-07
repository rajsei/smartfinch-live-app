// =============================================================================
// AppHaptics — every vibration the app makes, behind one switch (SET-04)
// =============================================================================
//
// `SET-04` asks for sounds and haptics to be switchable separately. The sound
// half already was: the only sounds Smartfinch plays by itself are the spoken
// announcements and the cue tone before them, and both have their own
// switches. The haptic half was not — four places called `HapticFeedback`
// directly, so there was nothing to switch.
//
// Now they all come through here, and here asks the setting first. A new
// vibration added anywhere else would quietly ignore the switch, which is why
// `test/shared/utils/app_haptics_test.dart` fails if `HapticFeedback` is
// called from anywhere but this file.
//
// What it does not cover: the phone's own touch feedback — Android's click
// sounds and long-press buzz that Flutter's widgets ask the system for. Those
// follow the phone's settings, as every other app's do.
// =============================================================================

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_providers.dart';
import '../providers/settings_providers.dart';

/// Whether the app vibrates on its own buttons and cues (`SET-04`).
///
/// On by default: a short buzz on the listen button is part of how it feels
/// to press, and a child who does not want it can switch it off.
final hapticsEnabledProvider = StateNotifierProvider<BoolSettingNotifier, bool>(
  (ref) {
    return BoolSettingNotifier(
      ref.watch(sharedPreferencesProvider),
      PrefKeys.hapticsEnabled,
      true,
    );
  },
);

/// The app's vibrations, each one checking [hapticsEnabledProvider] first.
abstract final class AppHaptics {
  /// A light tap — the listen button, a wizard step.
  static Future<void> lightImpact(BuildContext context) =>
      enabledFor(context) ? HapticFeedback.lightImpact() : Future.value();

  /// A firmer one — confirming something that cannot be undone.
  static Future<void> mediumImpact(BuildContext context) =>
      enabledFor(context) ? HapticFeedback.mediumImpact() : Future.value();

  /// The smallest — a choice changing.
  static Future<void> selectionClick(BuildContext context) =>
      enabledFor(context) ? HapticFeedback.selectionClick() : Future.value();

  /// [selectionClick], for code with no [BuildContext] that has already read
  /// the setting — the announcement cue, which runs inside the speech engine.
  static Future<void> selectionClickIf(bool enabled) =>
      enabled ? HapticFeedback.selectionClick() : Future.value();

  /// Whether the setting allows a vibration from [context].
  ///
  /// A context with no `ProviderScope` above it — a widget test pumping one
  /// bare widget — behaves like the default, which is on.
  static bool enabledFor(BuildContext context) {
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(hapticsEnabledProvider);
    } on StateError {
      return true;
    }
  }
}
