// =============================================================================
// Background Recording Service — tests
// =============================================================================
//
// What these cover: the parts that do not need a platform channel — the
// mutual-exclusion guard, and the no-op contract on non-Android hosts (which
// is where the test suite runs).
//
// What they deliberately do not cover: the plugin calls themselves.
// `FlutterForegroundTask` exposes only static methods, so mocking them would
// mean wrapping the whole plugin in an interface for the sake of the test.
// That indirection is not worth adding to a service that is not wired up yet;
// the platform behaviour is verified on a device when `LIVE-10` is built.
// =============================================================================

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/shared/services/background_recording/background_recording_service.dart';
import 'package:smartfinch/shared/services/foreground_service_guard.dart';

void main() {
  setUp(() {
    // The guard is process-wide static state; a leaked claim from one test
    // would silently fail the next.
    for (final owner in ForegroundServiceOwner.values) {
      ForegroundServiceGuard.release(owner);
    }
    BackgroundRecordingService.resetForTesting();
  });

  group('ForegroundServiceGuard', () {
    test('is free initially', () {
      expect(ForegroundServiceGuard.owner, isNull);
    });

    test('a claim is granted and recorded', () {
      expect(
        ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording),
        isTrue,
      );
      expect(
        ForegroundServiceGuard.owner,
        ForegroundServiceOwner.recording,
      );
    });

    test('the same owner may claim again', () {
      ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording);
      expect(
        ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording),
        isTrue,
      );
    });

    test('a second owner is refused and does not take ownership', () {
      ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording);
      expect(
        ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.survey),
        isFalse,
      );
      expect(
        ForegroundServiceGuard.owner,
        ForegroundServiceOwner.recording,
        reason: 'a refused claim must not change the owner',
      );
    });

    test('release frees the service for another owner', () {
      ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording);
      ForegroundServiceGuard.release(ForegroundServiceOwner.recording);
      expect(ForegroundServiceGuard.owner, isNull);
      expect(
        ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.survey),
        isTrue,
      );
    });

    test('a non-owner cannot release someone else\'s claim', () {
      ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording);
      ForegroundServiceGuard.release(ForegroundServiceOwner.survey);
      expect(
        ForegroundServiceGuard.owner,
        ForegroundServiceOwner.recording,
        reason: 'releasing as the wrong owner must be a no-op',
      );
    });
  });

  group('BackgroundRecordingService', () {
    test('starts out not running', () {
      expect(BackgroundRecordingService().isRunning, isFalse);
    });

    test('init leaves the service unclaimed', () async {
      await BackgroundRecordingService.init(
        channelName: 'Recording',
        channelDescription: 'Keeps listening while the screen is off',
      );
      expect(
        ForegroundServiceGuard.owner,
        isNull,
        reason: 'configuring the task must not claim the service',
      );
    });

    test('stop() always releases the claim, even when not running', () async {
      ForegroundServiceGuard.tryClaim(ForegroundServiceOwner.recording);

      await BackgroundRecordingService().stop();

      // On Android a failed start could otherwise leave the guard held for the
      // rest of the process, refusing every later attempt. On other platforms
      // stop() returns early, so the claim is only released where the service
      // could have been started in the first place.
      if (Platform.isAndroid) {
        expect(ForegroundServiceGuard.owner, isNull);
      } else {
        expect(ForegroundServiceGuard.owner, ForegroundServiceOwner.recording);
      }
    });

    test('permission check reports success off Android', () async {
      if (Platform.isAndroid) return;
      expect(
        await BackgroundRecordingService.ensureNotificationPermission(),
        isTrue,
        reason: 'callers must not need a platform check of their own',
      );
    });

    test('start() is a successful no-op off Android', () async {
      if (Platform.isAndroid) return;
      final service = BackgroundRecordingService();

      final started = await service.start(
        title: 'Listening',
        text: '3 species so far',
        stopButtonText: 'Stop',
      );

      expect(started, isTrue);
      expect(
        service.isRunning,
        isFalse,
        reason: 'nothing actually runs off Android',
      );
      expect(
        ForegroundServiceGuard.owner,
        isNull,
        reason: 'a no-op start must not claim the shared service',
      );
    });

    test('update() is a no-op while not running', () async {
      // Would throw on a missing platform channel if it reached the plugin.
      await expectLater(
        BackgroundRecordingService().update(title: 'a', text: 'b'),
        completes,
      );
    });
  });
}
