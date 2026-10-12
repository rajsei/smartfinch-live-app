// =============================================================================
// Clip retention settings — SET-12
// =============================================================================
//
// The two thresholds of [ClipRetentionPolicy] as settings, in Advanced
// settings → Storage: how long every recording is kept at least, and how many
// recordings of one species there may be before the least certain go.
//
// Their own file rather than `storage_providers.dart`, because the retention
// job's provider reads them and `storage_providers.dart` already reads the
// scoring providers — one import each way would be a cycle.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/settings_providers.dart';
import 'clip_retention.dart';

/// Days every clip is kept before the clean-up may delete it.
final clipRetentionDaysProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return IntSettingNotifier(
        prefs,
        PrefKeys.clipRetentionDays,
        ClipRetentionPolicy.defaultDays,
      );
    });

/// Clips of one species above which the least certain are deleted.
final clipRetentionPerSpeciesProvider =
    StateNotifierProvider<IntSettingNotifier, int>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return IntSettingNotifier(
        prefs,
        PrefKeys.clipRetentionPerSpecies,
        ClipRetentionPolicy.defaultPerSpeciesCap,
      );
    });

/// The policy the retention job applies.
///
/// A stored value that is not positive falls back to the default: the job
/// deletes, and a cap of 0 would take every recording older than the minimum
/// age with it.
final clipRetentionPolicyProvider = Provider<ClipRetentionPolicy>((ref) {
  final days = ref.watch(clipRetentionDaysProvider);
  final cap = ref.watch(clipRetentionPerSpeciesProvider);
  return ClipRetentionPolicy(
    minimumAge: Duration(
      days: days > 0 ? days : ClipRetentionPolicy.defaultDays,
    ),
    perSpeciesCap: cap > 0 ? cap : ClipRetentionPolicy.defaultPerSpeciesCap,
  );
});
