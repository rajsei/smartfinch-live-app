// =============================================================================
// avatarState — one JSON column, several owners (AVA-05, AVA-07)
// =============================================================================
//
// `UserProfiles.avatarState` holds everything about the bird that nothing
// queries: its name today, the stickers a child has picked and placed
// (`AVA-07`), and later the unlockable parts of `AVA-03`. One column rather
// than one per feature, so a new feature is not a migration.
//
// ### ⚠️ Every writer merges
//
// The name used to be written as `{'name': …}` — the whole blob. With a second
// owner in the column that would have deleted every sticker a child had
// placed the moment they renamed their bird. So nobody writes the column
// directly any more: they hand [writeAvatarField] one key, and every other key
// — including ones a newer version of the app put there — survives.
//
// Pure functions first, so the merge can be tested without a database.
// =============================================================================

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';

/// The stored blob as a map, tolerating anything unexpected.
///
/// Null, empty, malformed or not an object all read as empty: a profile
/// written by a future version — or by a hand-edited backup — must not stop
/// the home screen from rendering.
Map<String, Object?> decodeAvatarState(String? raw) {
  if (raw == null || raw.isEmpty) return {};

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};
    return {for (final e in decoded.entries) '${e.key}': e.value};
  } catch (_) {
    return {};
  }
}

/// [raw] with [key] set to [value], every other key untouched.
///
/// A null [value] removes the key. Returns null when nothing is left, so a
/// profile with no name and no stickers stores no blob at all — which is what
/// a fresh profile looks like.
String? mergeAvatarState(String? raw, String key, Object? value) {
  final state = decodeAvatarState(raw);

  if (value == null) {
    state.remove(key);
  } else {
    state[key] = value;
  }

  return state.isEmpty ? null : jsonEncode(state);
}

/// Reads [key] from the default profile's blob.
Future<Object?> readAvatarField(AppDatabase db, String key) async {
  final profile =
      await (db.select(db.userProfiles)
        ..where((p) => p.id.equals(kDefaultProfileId))).getSingleOrNull();

  return decodeAvatarState(profile?.avatarState)[key];
}

/// Sets [key] in the default profile's blob, keeping every other key.
///
/// Read and write in one transaction, so two writers — a rename and a sticker
/// placed a moment later — cannot each read the old blob and have the second
/// write lose the first one's change.
Future<void> writeAvatarField(AppDatabase db, String key, Object? value) {
  return db.transaction(() async {
    final profile =
        await (db.select(db.userProfiles)
          ..where((p) => p.id.equals(kDefaultProfileId))).getSingleOrNull();

    await (db.update(db.userProfiles)
      ..where((p) => p.id.equals(kDefaultProfileId))).write(
      UserProfilesCompanion(
        avatarState: Value(mergeAvatarState(profile?.avatarState, key, value)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  });
}
