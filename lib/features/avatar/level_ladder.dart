// =============================================================================
// The level ladder, and the bird that grows on it (STAT-07, AVA-01, AVA-02)
// =============================================================================
//
// ### A formula, not a table
//
// Every level from 1 on unlocks a sticker (`AVA-07`), and more stickers will
// keep arriving — so the ladder has no top. Level *n* starts at 250 · n² stars,
// but no single level costs more than 5,000:
//
//   level   0    1      2      3      5       10      15      20      30
//   stars   0  250  1,000  2,250  6,250  25,000  50,000  75,000  125,000
//
// Quadratic at first, so the first evening brings two or three levels and a
// sticker each; flat from level 10 on, so every further level costs the same
// ~1.5 weeks of regular play and the ladder never turns into a wall. Adding
// stickers therefore never needs a code change — nor does a child running out
// of them, because an open pick simply waits.
//
// ### The titles keep the old pace
//
// The fifteen titles of §3.5 tell one story from egg to legend, and the level
// *is* the avatar's stage of life. They stay anchored to the star counts §3.5
// gave them: a level carries the highest title whose threshold its own
// starting stars have passed. Levels now come faster; the story does not — a
// regular player is still a migrant after about a year and a legend after
// about three. Egg is level 0 alone: from the first level on, the bird hatched.
//
// ### ⚠️ Levels ratchet
//
// A level is a threshold on the star total, and a rebalancing (`AUS-12`,
// `DAT-03`) can lower that total. So the *displayed* level is never derived
// from today's stars alone: `UserProfiles.highestLevelReached` is the floor,
// and it only ever rises. Without it the first rule change would take a level
// — and with it a sticker pick and an avatar stage — away from a child who did
// nothing wrong.
//
// Pure Dart: no Flutter, no database. The numbers are the kind of thing a
// balancing pass changes, and a formula you can test in isolation is the whole
// reason `DAT-04` asks for the rules to live in one place.
// =============================================================================

import 'package:meta/meta.dart';

/// Stars per level squared while the ladder is still quadratic.
const int kLevelStarsBase = 250;

/// The most a single level ever costs; the ladder is linear from here on.
const int kLevelStepCap = 5000;

/// The last level the quadratic part reaches before the cap takes over.
///
/// Level *n* costs `base · (2n − 1)` over the one below it, which passes the
/// cap after level 10 for the numbers above.
const int _lastQuadraticLevel = (kLevelStepCap ~/ kLevelStarsBase + 1) ~/ 2;

/// Stars at which [level] begins. Level 0 and below begin at zero.
int starsForLevel(int level) {
  if (level <= 0) return 0;
  if (level <= _lastQuadraticLevel) return kLevelStarsBase * level * level;

  final quadraticTop =
      kLevelStarsBase * _lastQuadraticLevel * _lastQuadraticLevel;
  return quadraticTop + kLevelStepCap * (level - _lastQuadraticLevel);
}

/// One title of §3.5 and the star count it was given there.
@immutable
class LevelTitle {
  const LevelTitle(this.key, this.fromStars);

  /// Stable identifier; also the l10n key suffix.
  final String key;

  /// The §3.5 threshold. Decides which levels carry this title.
  final int fromStars;
}

/// The fifteen titles, egg to legend (§3.5).
const List<LevelTitle> kLevelTitles = [
  LevelTitle('egg', 0),
  LevelTitle('chick', 500),
  LevelTitle('nestling', 1500),
  LevelTitle('fledgling', 4000),
  LevelTitle('youngBird', 8000),
  LevelTitle('scout', 15000),
  LevelTitle('listener', 25000),
  LevelTitle('singer', 40000),
  LevelTitle('territoryHolder', 60000),
  LevelTitle('farFlier', 90000),
  LevelTitle('migrant', 130000),
  LevelTitle('returner', 185000),
  LevelTitle('oldBird', 260000),
  LevelTitle('flockLeader', 360000),
  LevelTitle('legend', 500000),
];

/// The title key [level] carries.
///
/// Derived from the level, not from the stars — so a ratcheted level keeps
/// its title along with its number.
String titleKeyForLevel(int level) {
  if (level <= 0) return kLevelTitles.first.key;

  final from = starsForLevel(level);
  // From level 1 on the egg has hatched, even though level 1 begins below
  // the chick's 500.
  var title = kLevelTitles[1];
  for (final candidate in kLevelTitles.skip(2)) {
    if (from >= candidate.fromStars) title = candidate;
  }
  return title.key;
}

/// One rung.
@immutable
class Level {
  const Level({
    required this.number,
    required this.key,
    required this.fromStars,
  });

  /// The rung for [number].
  factory Level.at(int number) {
    final n = number < 0 ? 0 : number;
    return Level(
      number: n,
      key: titleKeyForLevel(n),
      fromStars: starsForLevel(n),
    );
  }

  /// 0 and up; there is no top.
  final int number;

  /// The title key (see [kLevelTitles]); also the l10n key suffix.
  final String key;

  /// Stars at which this level begins.
  final int fromStars;

  @override
  bool operator ==(Object other) =>
      other is Level &&
      other.number == number &&
      other.key == key &&
      other.fromStars == fromStars;

  @override
  int get hashCode => Object.hash(number, key, fromStars);
}

/// What the avatar looks like (`AVA-02`).
///
/// Four, as the requirement words it. The level number and its title carry the
/// finer progression; the picture is there to make the *shape* of the progress
/// visible, not to enumerate it.
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

/// The stage [level] shows — read off its title, so picture and name agree.
AvatarStage stageForLevel(int level) => switch (titleKeyForLevel(level)) {
  'egg' => AvatarStage.egg,
  'chick' || 'nestling' => AvatarStage.chick,
  'fledgling' || 'youngBird' => AvatarStage.fledgling,
  _ => AvatarStage.adult,
};

/// Where a child stands on the ladder (`STAT-07`).
@immutable
class LevelProgress {
  const LevelProgress({
    required this.level,
    required this.stars,
    required this.next,
  });

  /// An empty account: level 0, the egg.
  ///
  /// What an unopened database means, so a screen can show it instead of a
  /// spinner.
  factory LevelProgress.start() => progressFor(stars: 0);

  final Level level;

  /// The star total this was worked out from — after the ratchet, so it can
  /// be lower than [Level.fromStars] and that is not a bug (see [isRatcheted]).
  final int stars;

  /// The rung above. Always there: the ladder has no top.
  final Level next;

  AvatarStage get stage => stageForLevel(level.number);

  /// Stars still needed for [next].
  int get starsToNext => (next.fromStars - stars).clamp(0, next.fromStars);

  /// How far through the current rung, 0…1.
  double get fraction {
    final span = next.fromStars - level.fromStars;
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
  if (stars <= 0) return Level.at(0);

  // Past the quadratic part the ladder is linear and can be solved directly;
  // below it there are only ten rungs to walk.
  final quadraticTop = starsForLevel(_lastQuadraticLevel);
  if (stars >= quadraticTop) {
    return Level.at(
      _lastQuadraticLevel + (stars - quadraticTop) ~/ kLevelStepCap,
    );
  }

  var level = 0;
  while (starsForLevel(level + 1) <= stars) {
    level++;
  }
  return Level.at(level);
}

/// What to show, given the stars and the highest level ever reached.
///
/// [highestLevelReached] is the ratchet from `UserProfiles`. Passing a lower
/// value than the stars support is harmless — the stars win — which is what
/// makes the floor safe to store lazily.
LevelProgress progressFor({required int stars, int highestLevelReached = 0}) {
  final earned = levelForStars(stars).number;
  final number = earned > highestLevelReached ? earned : highestLevelReached;

  return LevelProgress(
    level: Level.at(number),
    stars: stars,
    next: Level.at(number + 1),
  );
}
