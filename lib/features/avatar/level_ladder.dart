// =============================================================================
// The level ladder, and the bird that grows on it (STAT-07, AVA-01, AVA-02)
// =============================================================================
//
// Fifteen rungs from §3.5, growing by roughly a factor of 1.4 a step — fast at
// first so the first evening produces two levels, slow later so the ladder
// still has somewhere to go after a year.
//
// ### The level *is* the avatar's stage of life
//
// §3.5 renamed levels 8–14 for exactly this reason: they were expertise titles
// (*Kenner*, *Spurenleser*, *Vogelkundler*) sitting on top of a bird's life
// story, and two of them collided with achievement names. **The levels now
// tell one story from egg to legend**, the achievements keep the expertise, and
// `AVA-02` gets a stage to render without a second system to maintain.
//
// Four stages rather than fifteen, because that is what `AVA-02` asks for —
// egg → chick → fledgling → adult. The level number and its title carry the
// finer progression; the picture carries the shape of it.
//
// ### ⚠️ Levels ratchet
//
// A level is a threshold on the star total, and a rebalancing (`AUS-12`,
// `DAT-03`) can lower that total. So the *displayed* level is never derived
// from today's stars alone: `UserProfiles.highestLevelReached` is the floor,
// and it only ever rises. Without it the first rule change would take a level,
// and with it an avatar stage, away from a child who did nothing wrong.
//
// Pure Dart: no Flutter, no database. The thresholds are the kind of thing a
// balancing pass changes, and a table you can test in isolation is the whole
// reason `DAT-04` asks for the rules to live in one place.
// =============================================================================

import 'package:meta/meta.dart';

/// One rung (§3.5).
@immutable
class Level {
  const Level({
    required this.number,
    required this.key,
    required this.fromStars,
  });

  /// 1–15.
  final int number;

  /// Stable identifier; also the l10n key suffix.
  final String key;

  /// Stars at which this level begins.
  final int fromStars;
}

/// The ladder, lowest first (§3.5).
const List<Level> kLevelLadder = [
  Level(number: 1, key: 'egg', fromStars: 0),
  Level(number: 2, key: 'chick', fromStars: 500),
  Level(number: 3, key: 'nestling', fromStars: 1500),
  Level(number: 4, key: 'fledgling', fromStars: 4000),
  Level(number: 5, key: 'youngBird', fromStars: 8000),
  Level(number: 6, key: 'scout', fromStars: 15000),
  Level(number: 7, key: 'listener', fromStars: 25000),
  Level(number: 8, key: 'singer', fromStars: 40000),
  Level(number: 9, key: 'territoryHolder', fromStars: 60000),
  Level(number: 10, key: 'farFlier', fromStars: 90000),
  Level(number: 11, key: 'migrant', fromStars: 130000),
  Level(number: 12, key: 'returner', fromStars: 185000),
  Level(number: 13, key: 'oldBird', fromStars: 260000),
  Level(number: 14, key: 'flockLeader', fromStars: 360000),
  Level(number: 15, key: 'legend', fromStars: 500000),
];

/// What the avatar looks like (`AVA-02`).
///
/// Four, as the requirement words it. Fifteen pictures would be fifteen pieces
/// of artwork nobody has drawn, and the difference between level 11 and 12 is
/// carried by the title anyway — the picture is there to make the *shape* of
/// the progress visible, not to enumerate it.
enum AvatarStage {
  egg,
  chick,
  fledgling,
  adult;

  /// Stand-in artwork.
  ///
  /// Emoji until a bird is drawn. Deliberately not an asset: a placeholder PNG
  /// looks like a decision, and this is explicitly not one. Replacing these
  /// with real illustrations touches this getter and nothing else.
  String get emoji => switch (this) {
    AvatarStage.egg => '🥚',
    AvatarStage.chick => '🐣',
    AvatarStage.fledgling => '🐥',
    AvatarStage.adult => '🐦',
  };
}

/// The stage [level] shows.
AvatarStage stageForLevel(int level) {
  if (level <= 1) return AvatarStage.egg;
  if (level <= 3) return AvatarStage.chick;
  if (level <= 5) return AvatarStage.fledgling;
  return AvatarStage.adult;
}

/// Where a child stands on the ladder (`STAT-07`).
@immutable
class LevelProgress {
  const LevelProgress({required this.level, required this.stars, this.next});

  final Level level;

  /// The star total this was worked out from — after the ratchet, so it can
  /// be lower than [Level.fromStars] and that is not a bug (see [isRatcheted]).
  final int stars;

  /// The rung above, or null at the top of the ladder.
  final Level? next;

  AvatarStage get stage => stageForLevel(level.number);

  /// Stars still needed for [next]. Zero at the top.
  int get starsToNext =>
      next == null ? 0 : (next!.fromStars - stars).clamp(0, next!.fromStars);

  /// How far through the current rung, 0…1.
  ///
  /// One at the top of the ladder: a bar that never fills would say a child
  /// who has finished the ladder is still not there.
  double get fraction {
    final upper = next;
    if (upper == null) return 1;

    final span = upper.fromStars - level.fromStars;
    if (span <= 0) return 1;

    return ((stars - level.fromStars) / span).clamp(0.0, 1.0);
  }

  /// True when the level is held up by the ratchet rather than by the stars.
  ///
  /// Only reachable after a rebalancing lowered a total (`AUS-12`) or an older
  /// backup was restored (`SET-07`). Nothing in the UI says so — the whole
  /// point is that the child never finds out — but the flag exists so a test
  /// can assert the state is reachable and stable.
  bool get isRatcheted => stars < level.fromStars;
}

/// The level [stars] alone would earn.
///
/// ⚠️ Not what to display. Use [progressFor] with the stored floor, or a
/// rebalancing will silently demote someone.
Level levelForStars(int stars) {
  var earned = kLevelLadder.first;
  for (final level in kLevelLadder) {
    if (stars >= level.fromStars) earned = level;
  }
  return earned;
}

/// What to show, given the stars and the highest level ever reached.
///
/// [highestLevelReached] is the ratchet from `UserProfiles`. Passing a lower
/// value than the stars support is harmless — the stars win — which is what
/// makes the floor safe to store lazily.
LevelProgress progressFor({required int stars, int highestLevelReached = 1}) {
  final earned = levelForStars(stars);
  final number =
      earned.number > highestLevelReached ? earned.number : highestLevelReached;
  final level = kLevelLadder[(number - 1).clamp(0, kLevelLadder.length - 1)];

  return LevelProgress(
    level: level,
    stars: stars,
    next:
        level.number < kLevelLadder.length ? kLevelLadder[level.number] : null,
  );
}
