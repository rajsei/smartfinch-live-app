// =============================================================================
// Foreground Service Guard - mutual exclusion for the shared Android service
// =============================================================================
//
// Every mode that needs background operation is backed by the single
// `ForegroundService` declaration in AndroidManifest.xml. Only one may own that
// service at a time; starting a second while the first is still running would
// contend over the same foreground service.
//
// Each notification controller must [tryClaim] before `startService` and
// [release] after `stopService` (or when a start attempt fails).
//
// **Transition note:** [ForegroundServiceOwner.survey] and
// [ForegroundServiceOwner.aru] disappear with their modes (transition step
// 0.3), leaving [ForegroundServiceOwner.recording] as the only owner. At that
// point this guard can be reduced to a single boolean or deleted outright —
// arbitrating between one participant is not arbitration. It is kept for now
// so the modes still compile until they are removed.

/// The mode currently holding the shared Android foreground service.
enum ForegroundServiceOwner {
  /// Background recording for Live mode
  /// (`shared/services/background_recording/`). The only owner that survives
  /// the transition.
  recording,

  /// Legacy: survey mode. Removed in transition step 0.3.
  survey,

  /// Legacy: ARU mode. Removed in transition step 0.3.
  aru,
}

/// Process-wide tracker that enforces single ownership of the shared Android
/// foreground service across ARU and Survey.
class ForegroundServiceGuard {
  ForegroundServiceGuard._();

  static ForegroundServiceOwner? _owner;

  /// The current owner, or `null` when the foreground service is free.
  static ForegroundServiceOwner? get owner => _owner;

  /// Attempts to claim the foreground service for [owner].
  ///
  /// Returns `true` if [owner] already holds it or the service is free;
  /// returns `false` (without changing ownership) when a different mode owns it.
  static bool tryClaim(ForegroundServiceOwner owner) {
    if (_owner != null && _owner != owner) return false;
    _owner = owner;
    return true;
  }

  /// Releases the claim if [owner] currently holds it.
  static void release(ForegroundServiceOwner owner) {
    if (_owner == owner) _owner = null;
  }
}
