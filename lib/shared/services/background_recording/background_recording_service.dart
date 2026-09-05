// =============================================================================
// Background Recording Service — foreground service for screen-off listening
// =============================================================================
//
// Keeps the app alive and recording while the screen is off, via an Android
// foreground service of type `microphone`. This is what makes the walking use
// case work: the phone goes in a pocket and keeps listening.
//
// ### Where this came from
//
// Lifted out of `features/survey/survey_notification.dart` before that module
// was deleted (transition step 0.2). Survey and ARU each carried their own
// near-identical copy — the app's only working foreground-service code — and
// both were entangled with mode-specific stats, routes and localization.
// Survey's was the closer fit to plain recording, so it is the one that was
// generalized. This version is deliberately mode-agnostic:
//
//   * **No l10n dependency.** Every user-visible string is a parameter. A
//     shared service has no business deciding how the app talks to a child,
//     and keeping it out means the strings only have to be written (and
//     translated into 12 locales) when the service is actually wired up.
//   * **No stats, no routes, no GPS.** Start it, update its text, stop it.
//   * **No location service type.** Survey needed `microphone|location` for
//     GPS tracking. Smartfinch only listens, so `microphone` is enough — and
//     `ACCESS_BACKGROUND_LOCATION` can stay out of the manifest, which is one
//     less thing to justify in a children's app (NFA-08).
//
// ### Status: not wired up
//
// Nothing calls this yet. It exists so that `LIVE-10` / `LIVE-11` stay a day's
// work rather than a rewrite once the field test shows the walking case
// matters. It must keep compiling and keep passing its tests.
//
// ### Usage, once wired
//
// ```dart
// await BackgroundRecordingService.init(
//   channelName: l10n.recordingNotificationChannelName,
//   channelDescription: l10n.recordingNotificationChannelDescription,
// );
// final service = BackgroundRecordingService();
// final started = await service.start(
//   title: l10n.recordingNotificationTitle,
//   text: l10n.recordingNotificationText,
//   stopButtonText: l10n.notificationStop,
// );
// await service.update(title: ..., text: ...);   // as stats change
// await service.stop();
// ```
//
// ### Platform behaviour
//
// Android only. On every other platform every method is a no-op that reports
// success, so callers do not need platform checks. iOS background audio is a
// separate mechanism (audio session category) and is not handled here.
// =============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../foreground_service_guard.dart';

// =============================================================================
// Task handler (runs in its own isolate — kept minimal on purpose)
// =============================================================================

/// Top-level callback required by `flutter_foreground_task`.
///
/// Must be a top-level function annotated with `@pragma('vm:entry-point')` so
/// the entry point survives tree shaking in release builds.
@pragma('vm:entry-point')
void backgroundRecordingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(_BackgroundRecordingTaskHandler());
}

/// Minimal task handler.
///
/// All recording logic lives in the main isolate; this handler exists only to
/// satisfy the plugin's API and to forward the notification buttons.
class _BackgroundRecordingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[BackgroundRecording] task started');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // No-op: notification updates are driven from the main isolate so the
    // displayed time matches actual recording time.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[BackgroundRecording] task destroyed (timeout: $isTimeout)');
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == BackgroundRecordingService.stopActionId) {
      FlutterForegroundTask.sendDataToMain({
        'action': BackgroundRecordingService.stopActionId,
      });
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

// =============================================================================
// Service wrapper
// =============================================================================

/// Manages the Android foreground service that keeps recording alive while the
/// screen is off.
///
/// One instance owns at most one running service. Ownership of the shared
/// Android foreground service is arbitrated by [ForegroundServiceGuard].
class BackgroundRecordingService {
  /// Notification button id for "stop". Forwarded to the main isolate as
  /// `{'action': 'stop'}` so the caller can end the session.
  static const String stopActionId = 'stop';

  /// Foreground service id. Distinct from the ids the legacy survey (256) and
  /// ARU (512) services used, so a stale service from either cannot be
  /// mistaken for this one during the transition.
  static const int _serviceId = 128;

  /// Notification channel id. A fresh id rather than a reused one: Android
  /// caches channel importance at creation time and it cannot be raised
  /// programmatically afterwards.
  static const String _channelId = 'smartfinch_recording_fg';

  /// `<meta-data>` name in AndroidManifest.xml pointing at the notification
  /// icon drawable. Changing this requires changing the manifest too.
  static const String _notificationIconMetaData =
      'com.birdnet.live.notification_icon';

  static bool _initialized = false;
  bool _running = false;

  /// Whether the foreground service is currently running.
  bool get isRunning => _running;

  /// Whether [init] has completed at least once in this process.
  @visibleForTesting
  static bool get isInitialized => _initialized;

  /// Resets static state. Tests only.
  @visibleForTesting
  static void resetForTesting() => _initialized = false;

  /// Configures the foreground task. Safe to call more than once.
  ///
  /// [channelName] and [channelDescription] are user-visible in the Android
  /// notification settings, so they must be localized by the caller.
  static Future<void> init({
    required String channelName,
    required String channelDescription,
  }) async {
    if (!Platform.isAndroid) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: channelName,
        channelDescription: channelDescription,
        channelImportance: NotificationChannelImportance.DEFAULT,
        priority: NotificationPriority.DEFAULT,
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _initialized = true;
  }

  /// Requests notification permission (Android 13+).
  ///
  /// Call this well before [start] — during onboarding or when the user first
  /// enables background listening — so the system dialog does not appear in
  /// the middle of starting a session.
  ///
  /// Returns `true` on non-Android platforms, where the permission does not
  /// exist.
  static Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission == NotificationPermission.granted) return true;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  /// Starts the foreground service and shows its persistent notification.
  ///
  /// Returns `true` when the service is running afterwards. Returns `false`
  /// when another owner holds the shared service or the platform refused to
  /// start it — the caller decides whether that is fatal.
  ///
  /// A missing notification permission is **not** treated as fatal: Android
  /// still creates the foreground service, it just may show a default
  /// notification on some OEM builds. Losing the recording would be worse
  /// than losing the notification's appearance.
  ///
  /// On non-Android platforms this is a no-op that returns `true`.
  Future<bool> start({
    required String title,
    required String text,
    required String stopButtonText,
  }) async {
    if (!Platform.isAndroid) return true;
    if (_running) return true;

    // Checked before claiming, so a misordered call cannot leave the guard
    // held by an owner that never started anything.
    if (!_initialized) {
      debugPrint('[BackgroundRecording] start() before init(); not starting');
      return false;
    }

    if (!ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording)) {
      debugPrint(
        '[BackgroundRecording] foreground service already owned by '
        '${ForegroundServiceGuard.owner}; not starting',
      );
      return false;
    }

    await ensureNotificationPermission();

    final result = await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: title,
      notificationText: text,
      notificationIcon: const NotificationIcon(
        metaDataName: _notificationIconMetaData,
      ),
      notificationButtons: [
        NotificationButton(id: stopActionId, text: stopButtonText),
      ],
      callback: backgroundRecordingTaskCallback,
    );

    if (result is ServiceRequestSuccess) {
      _running = true;
      debugPrint('[BackgroundRecording] started');
      return true;
    }

    ForegroundServiceGuard.release(ForegroundServiceOwner.recording);
    debugPrint('[BackgroundRecording] startService failed: $result');
    return false;
  }

  /// Updates the notification text while the service runs.
  ///
  /// Does nothing when the service is not running, so callers can update on a
  /// timer without guarding every call.
  Future<void> update({required String title, required String text}) async {
    if (!_running) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
      notificationIcon: const NotificationIcon(
        metaDataName: _notificationIconMetaData,
      ),
    );
  }

  /// Stops the foreground service and releases the shared-service claim.
  ///
  /// Always releases the claim, even when the service was not running — a
  /// failed [start] must never leave the guard held, or every later attempt
  /// is refused for the rest of the process.
  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (_running) {
      await FlutterForegroundTask.stopService();
      _running = false;
      debugPrint('[BackgroundRecording] stopped');
    }
    ForegroundServiceGuard.release(ForegroundServiceOwner.recording);
  }
}
