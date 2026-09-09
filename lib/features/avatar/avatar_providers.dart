// =============================================================================
// Avatar providers — the level, and the bird's name (STAT-07, AVA-01, AVA-05)
// =============================================================================
//
// Both read the profile row rather than SharedPreferences. The level has to,
// because `highestLevelReached` is the ratchet and lives beside the star total
// it protects; the name goes with it because `UserProfiles.avatarState` was
// put in the schema for exactly this and because a name that did not travel
// with a backup (`SET-07`) would be the one thing a child lost on a new phone.
// =============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../scoring/scoring_providers.dart';
import 'level_ladder.dart';

/// Where the child stands on the ladder (`STAT-07`, `AVA-02`).
///
/// Depends on [totalStarsProvider], which the coordinator already invalidates
/// after every scoring detection — so a level earned mid-session reaches the
/// home screen without anything else having to know about levels.
final levelProgressProvider = FutureProvider<LevelProgress>((ref) async {
  final stars = await ref.watch(totalStarsProvider.future);

  final profile =
      await (ref
          .watch(appDatabaseProvider)
          .select(ref.watch(appDatabaseProvider).userProfiles)
        ..where((p) => p.id.equals(kDefaultProfileId))).getSingleOrNull();

  return progressFor(
    stars: stars,
    highestLevelReached: profile?.highestLevelReached ?? 1,
  );
});

/// The name the child gave their bird, or null (`AVA-05`).
final avatarNameProvider = FutureProvider<String?>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final profile =
      await (db.select(db.userProfiles)
        ..where((p) => p.id.equals(kDefaultProfileId))).getSingleOrNull();

  return _nameIn(profile?.avatarState);
});

/// Writes the avatar's name (`AVA-05`).
///
/// Stored as JSON in one column rather than as a column of its own, because
/// `AVA-03`'s unlockable parts and `AVA-04`'s nest will want to live in the
/// same place and a migration per feature is a poor trade for a field nothing
/// queries. Null clears it.
Future<void> setAvatarName(WidgetRef ref, String? name) async {
  final db = ref.read(appDatabaseProvider);
  final trimmed = name?.trim();

  await (db.update(db.userProfiles)
    ..where((p) => p.id.equals(kDefaultProfileId))).write(
    UserProfilesCompanion(
      avatarState: Value(
        trimmed == null || trimmed.isEmpty
            ? null
            : jsonEncode({'name': trimmed}),
      ),
      updatedAt: Value(DateTime.now()),
    ),
  );

  ref.invalidate(avatarNameProvider);
}

/// Reads the name out of the stored blob, tolerating anything unexpected.
///
/// A profile written by a future version — or by a hand-edited backup — must
/// not stop the home screen from rendering. No name is a state the app already
/// handles, so it is also the safe answer to a blob it cannot read.
String? _nameIn(String? avatarState) {
  if (avatarState == null || avatarState.isEmpty) return null;

  try {
    final decoded = jsonDecode(avatarState);
    if (decoded is! Map) return null;
    final name = decoded['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  } catch (_) {
    return null;
  }
}
