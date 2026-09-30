// =============================================================================
// The sticker board — which stickers a child has, and where they are (AVA-07)
// =============================================================================
//
// Stored as the `stickers` key of `UserProfiles.avatarState`, beside the
// bird's name, and written through `writeAvatarField` so neither can erase the
// other. It travels with a backup (`SET-07`) because the profile row does.
//
// ### Picks follow the ratcheted level
//
// Every level from 1 on is worth one pick. The level is the *displayed* one —
// the stored floor, not today's stars — so a rebalancing that lowers the total
// can never take a pick away (`AUS-12`, principle 1). Picks are keyed by the
// level that granted them, which makes "how many are still open" a question
// with one answer however often it is asked.
//
// ### Nothing is ever lost
//
// A sticker taken off the board goes back to the album; it stays picked. A
// sticker whose catalogue entry disappears keeps its pick and is simply not
// drawn. Each sticker can be picked once.
//
// ### ⚠️ A sticker is not a find
//
// Nothing here reads or writes the life list, the collection or any score.
// Picking a real bird as a sticker must never burn its first-find ×3
// (`PKT-04`) — the child's own first hearing, weeks later, still counts.
//
// ### Two arrangements
//
// Portrait and landscape keep their own positions, because the free space is
// tall and narrow in one and wide and flat in the other. Landscape starts as a
// copy of portrait and becomes its own the first time the child moves
// something there. Which stickers are *on* the board is shared: putting one
// on or taking one off does it in both.
//
// Positions are fractions of the board (0…1, the sticker's centre) and sizes
// are fractions of its shorter side, so a sticker looks the same size when the
// phone turns and the numbers mean the same thing on every screen.
//
// Pure Dart: every operation returns a new board.
// =============================================================================

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// The two arrangements.
enum StickerLayout { portrait, landscape }

/// One sticker on the board.
@immutable
class StickerPlacement {
  const StickerPlacement({
    required this.id,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = kDefaultStickerScale,
    this.rotation = 0,
  });

  /// Reads one placement, or null if it is unusable.
  static StickerPlacement? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;

    double number(Object? value, double fallback) =>
        value is num && value.isFinite ? value.toDouble() : fallback;

    return StickerPlacement(
      id: id,
      x: number(json['x'], 0.5),
      y: number(json['y'], 0.5),
      scale: number(json['s'], kDefaultStickerScale),
      rotation: number(json['r'], 0),
    ).clamped();
  }

  final String id;

  /// Centre, as a fraction of the board's width.
  final double x;

  /// Centre, as a fraction of the board's height.
  final double y;

  /// Size, as a fraction of the board's shorter side.
  final double scale;

  /// Radians, clockwise.
  final double rotation;

  StickerPlacement copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
  }) =>
      StickerPlacement(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
      ).clamped();

  /// Kept on the board, at a size a child can still grab, with the angle
  /// folded into one turn.
  StickerPlacement clamped() => StickerPlacement(
    id: id,
    x: x.clamp(0.0, 1.0),
    y: y.clamp(0.0, 1.0),
    scale: scale.clamp(kMinStickerScale, kMaxStickerScale),
    rotation: _normalizeAngle(rotation),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'x': x,
    'y': y,
    's': scale,
    'r': rotation,
  };

  @override
  bool operator ==(Object other) =>
      other is StickerPlacement &&
      other.id == id &&
      other.x == x &&
      other.y == y &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(id, x, y, scale, rotation);
}

/// A new sticker's size on the board.
const double kDefaultStickerScale = 0.3;

/// Smallest size — below this a sticker is hard to grab again.
const double kMinStickerScale = 0.12;

/// Largest size.
const double kMaxStickerScale = 0.9;

/// Everything a child has done with stickers.
@immutable
class StickerBoard {
  const StickerBoard({
    this.picks = const {},
    this.portrait = const [],
    this.landscape,
  });

  /// Nothing picked yet.
  static const StickerBoard empty = StickerBoard();

  /// Format version written into the stored blob.
  static const int version = 1;

  /// Reads the stored blob, tolerating anything unexpected.
  ///
  /// Unreadable parts read as empty. A placement for a sticker that was never
  /// picked, or a second placement of the same sticker, is dropped; a pick for
  /// a level below 1 is dropped; a sticker picked twice keeps its lowest level.
  factory StickerBoard.fromJson(Object? json) {
    if (json is! Map) return empty;

    final picks = <int, String>{};
    final rawPicks = json['picks'];
    if (rawPicks is Map) {
      final entries = [
        for (final e in rawPicks.entries)
          if (int.tryParse('${e.key}') case final level?
              when level >= 1 && e.value is String)
            (level, e.value as String),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final taken = <String>{};
      for (final (level, id) in entries) {
        if (taken.add(id)) picks[level] = id;
      }
    }
    final picked = picks.values.toSet();

    List<StickerPlacement> placements(Object? raw) {
      if (raw is! List) return const [];
      final seen = <String>{};
      return [
        for (final item in raw)
          if (StickerPlacement.fromJson(item) case final p?
              when picked.contains(p.id) && seen.add(p.id))
            p,
      ];
    }

    final portrait = placements(json['portrait']);
    final landscape =
        json['landscape'] is List ? placements(json['landscape']) : null;

    return StickerBoard(
      picks: Map.unmodifiable(picks),
      portrait: List.unmodifiable(portrait),
      landscape:
          landscape == null
              ? null
              : List.unmodifiable(_sameStickersAs(portrait, landscape)),
    );
  }

  /// Level that granted the pick → sticker id.
  final Map<int, String> picks;

  /// Portrait arrangement, bottom to top.
  final List<StickerPlacement> portrait;

  /// Landscape arrangement, bottom to top; null while it still follows
  /// portrait.
  final List<StickerPlacement>? landscape;

  Map<String, Object?> toJson() => {
    'v': version,
    'picks': {for (final e in picks.entries) '${e.key}': e.value},
    'portrait': [for (final p in portrait) p.toJson()],
    if (landscape != null)
      'landscape': [for (final p in landscape!) p.toJson()],
  };

  /// Every sticker picked so far.
  Set<String> get pickedIds => picks.values.toSet();

  /// Stickers currently on the board.
  Set<String> get placedIds => {for (final p in portrait) p.id};

  /// Levels up to [level] that have not been used for a pick yet, lowest
  /// first.
  List<int> openLevels(int level) => [
    for (var l = 1; l <= level; l++)
      if (!picks.containsKey(l)) l,
  ];

  /// The arrangement to draw for [layout].
  List<StickerPlacement> placementsFor(StickerLayout layout) =>
      switch (layout) {
        StickerLayout.portrait => portrait,
        StickerLayout.landscape => landscape ?? portrait,
      };

  /// Picks [id] with the lowest open level up to [level].
  ///
  /// Throws [StateError] when no level is open or [id] is already picked —
  /// the album only offers a pick when both are fine, so either is a bug.
  StickerBoard pick(String id, {required int level}) {
    final open = openLevels(level);
    if (open.isEmpty) throw StateError('no open pick at level $level');
    if (pickedIds.contains(id)) throw StateError('$id is already picked');

    return _copy(picks: {...picks, open.first: id});
  }

  /// Puts picked sticker [id] on the board, on top, in both arrangements.
  ///
  /// It lands in the upper part of the board, which the tile panel does not
  /// cover — a sticker picked in the album must be *seen* on the home screen —
  /// spread so the first few do not stack on each other.
  ///
  /// Already on the board, or never picked: unchanged.
  StickerBoard place(String id) {
    if (!pickedIds.contains(id) || placedIds.contains(id)) return this;

    final added = _spotFor(id, portrait.length);
    return _copy(
      portrait: [...portrait, added],
      landscape: landscape == null ? null : [...landscape!, added],
    );
  }

  /// Takes [id] off the board in both arrangements. It stays picked.
  StickerBoard remove(String id) => _copy(
    portrait: [
      for (final p in portrait)
        if (p.id != id) p,
    ],
    landscape:
        landscape == null
            ? null
            : [
              for (final p in landscape!)
                if (p.id != id) p,
            ],
  );

  /// Replaces the placement of [placement.id] in [layout].
  ///
  /// The first change in landscape turns it from a copy of portrait into an
  /// arrangement of its own. A sticker not on the board: unchanged.
  StickerBoard move(StickerLayout layout, StickerPlacement placement) {
    if (!placedIds.contains(placement.id)) return this;

    List<StickerPlacement> replaced(List<StickerPlacement> list) => [
      for (final p in list) p.id == placement.id ? placement.clamped() : p,
    ];

    return switch (layout) {
      StickerLayout.portrait => _copy(portrait: replaced(portrait)),
      StickerLayout.landscape => _copy(
        landscape: replaced(landscape ?? portrait),
      ),
    };
  }

  /// Moves [id] to the top of [layout] — the sticker a child touches is the
  /// one that should end up in front.
  StickerBoard bringToFront(StickerLayout layout, String id) {
    List<StickerPlacement> raised(List<StickerPlacement> list) {
      final match = list.where((p) => p.id == id).toList();
      if (match.isEmpty || list.last.id == id) return list;
      return [...list.where((p) => p.id != id), match.first];
    }

    return switch (layout) {
      StickerLayout.portrait => _copy(portrait: raised(portrait)),
      StickerLayout.landscape => _copy(
        landscape: raised(landscape ?? portrait),
      ),
    };
  }

  StickerBoard _copy({
    Map<int, String>? picks,
    List<StickerPlacement>? portrait,
    Object? landscape = _keep,
  }) => StickerBoard(
    picks: Map.unmodifiable(picks ?? this.picks),
    portrait: List.unmodifiable(portrait ?? this.portrait),
    landscape:
        identical(landscape, _keep)
            ? this.landscape
            : landscape == null
            ? null
            : List.unmodifiable(landscape as List<StickerPlacement>),
  );
}

const Object _keep = Object();

/// Where the [n]-th sticker on the board lands.
StickerPlacement _spotFor(String id, int n) {
  const xs = [0.22, 0.5, 0.78];
  return StickerPlacement(
    id: id,
    x: xs[n % xs.length],
    y: 0.14 + 0.1 * ((n ~/ xs.length) % 3),
  );
}

/// [landscape] reduced to, and completed with, the stickers in [portrait].
///
/// Which stickers are on the board is shared between the two arrangements; a
/// stored landscape that disagrees is repaired rather than trusted.
List<StickerPlacement> _sameStickersAs(
  List<StickerPlacement> portrait,
  List<StickerPlacement> landscape,
) {
  final onBoard = {for (final p in portrait) p.id};
  final kept = [
    for (final p in landscape)
      if (onBoard.contains(p.id)) p,
  ];
  final keptIds = {for (final p in kept) p.id};
  return [
    ...kept,
    for (final p in portrait)
      if (!keptIds.contains(p.id)) p,
  ];
}

double _normalizeAngle(double radians) {
  const turn = 2 * math.pi;
  final folded = radians % turn;
  return folded > math.pi ? folded - turn : folded;
}
