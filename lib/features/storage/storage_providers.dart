// =============================================================================
// Storage providers — SET-06
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../live/live_providers.dart';
import '../scoring/scoring_providers.dart';
import 'storage_service.dart';

/// Measures the app's storage and deletes recordings (`SET-06`).
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(
    db: ref.watch(appDatabaseProvider),
    // "Is something writing audio right now" — the recorder, not the screen:
    // a session keeps recording with the live screen closed (LIVE-10).
    isListening: () => ref.read(recordingServiceProvider).isRecording,
  );
});

/// What the app occupies, measured each time the settings screen shows it.
final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((ref) {
  return ref.watch(storageServiceProvider).measure();
});
