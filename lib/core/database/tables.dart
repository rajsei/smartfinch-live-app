// =============================================================================
// Database tables — the whole of Smartfinch's persistent state
// =============================================================================
//
// Two layers, and the split is the most important thing in this file:
//
//   **Raw data** — [Sessions], [Detections]. Written on every detection,
//   always, whether it scores or not. `Detection` is the single source of
//   truth; everything below is derived from it (DAT-02).
//
//   **Scoring layer** — [ScoreEvents], [DaySpecies], [YearSpecies],
//   [LifeSpecies], [Achievements], [UserProfiles]. Written *only while scoring
//   is active*. When the detection parameters leave the scoring range
//   (PKT-20), the raw row is still written and flagged; nothing here is
//   touched at all.
//
// ### What is deliberately not here
//
// Species names, images, families and rarity levels. Those come from
// `assets/models/taxonomy.csv` and the geo model, which already ship with the
// app — duplicating them into the database would be work with no gain and a
// second copy to keep in sync. Species are referenced by scientific name,
// which is the join key the rest of the app already uses.
//
// ### Fields that cannot be added later
//
// `profileId` (DAT-07), `updatedAt` + `syncState` (DAT-08), UUID primary keys,
// [Detections.scoringPaused] (DAT-11) and [UserProfiles.highestLevelReached]
// all cost a column now and are a migration over a real child's data later.
// They are in the first schema on purpose, even though nothing reads some of
// them yet.
// =============================================================================

import 'package:drift/drift.dart';

/// Columns every table carries so a future sync (DAT-08) and family profiles
/// (DAT-07) stay possible without a migration.
///
/// `id` is a UUID rather than an auto-increment integer: two devices that
/// later sync must not both mint row 47. Generated in Dart, never by SQLite.
mixin SyncableRow on Table {
  /// UUID v4, generated on insert.
  TextColumn get id => text()();

  /// Which profile this row belongs to (DAT-07). One profile today; the
  /// column exists so a second child on the same device is a feature rather
  /// than a schema change.
  TextColumn get profileId => text()();

  /// Last local modification, for conflict resolution if sync ever arrives.
  DateTimeColumn get updatedAt => dateTime()();

  /// Sync bookkeeping (DAT-08). `0` = local only. Nothing reads it yet.
  IntColumn get syncState => integer().withDefault(const Constant(0))();
}

// =============================================================================
// Raw data — always written
// =============================================================================

/// One recording session: the app was listening from here to there.
///
/// Sessions survive into Smartfinch but disappear from navigation — the
/// Journal is organised by day, not by recording (LOG-01).
class Sessions extends Table with SyncableRow {
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Coarsened 0.1° cell the session started in (NFA-08, D23). Never a precise
  /// coordinate. Stored as `"lat,lon"` of the rounded cell, e.g. `"50.8,12.9"`.
  TextColumn get gridCell => text().nullable()();

  /// The name the child gave this place — "Oma", "Schulweg" (LOG-13).
  ///
  /// Free text, and it stays on the device: it must never be rendered into the
  /// shared day image (KID-07).
  TextColumn get placeName => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One species heard once, at one moment.
///
/// Written immediately rather than when the session ends (NFA-11): a crash
/// mid-session must not lose the morning.
class Detections extends Table with SyncableRow {
  TextColumn get sessionId => text().references(Sessions, #id)();

  /// Join key into the taxonomy and the geo model.
  TextColumn get scientificName => text()();

  DateTimeColumn get detectedAt => dateTime()();

  /// Confidence of the window that first crossed the threshold — the moment
  /// the species appeared on screen and scored (D15).
  RealColumn get confidence => real()();

  /// Highest confidence reached before the detection ended, written back when
  /// the record closes (D15). Null until then.
  ///
  /// This is the value a later audit or the confirmation step (PKT-11) should
  /// look at, not [confidence].
  RealColumn get peakConfidence => real().nullable()();

  /// Cell at the moment of detection, not of the session (D23) — a child walks
  /// to school, and the bird at the end belongs where it was heard.
  TextColumn get gridCell => text().nullable()();

  /// ⚠️ **True when the scoring layer was paused for this detection** (PKT-20).
  ///
  /// Set when the species filter was off or the confidence threshold was below
  /// the scoring floor of 35. Such a detection is kept and shown in the journal
  /// marked "outside scoring" (LOG-15), but **nothing in the scoring layer was
  /// written for it** — no `ScoreEvent`, no `DaySpecies`, no `YearSpecies`, and
  /// above all no `LifeSpecies`.
  ///
  /// `recomputeAllScores()` must honour this flag, or a recomputation would
  /// retroactively award every test recording ever made (DAT-11).
  BoolColumn get scoringPaused => boolean().withDefault(const Constant(false))();

  /// Path to the saved audio clip, if one was written (LIVE-14). Subject to
  /// the retention rules in SET-12.
  TextColumn get audioClipPath => text().nullable()();

  /// Whether the child marked this clip as a favourite. Favourites are never
  /// deleted by the retention job (SET-12).
  BoolColumn get clipIsFavourite =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// =============================================================================
// Scoring layer — written only while scoring is active
// =============================================================================

/// What a `ScoreEvent` was awarded for.
enum ScoreEventType {
  /// Points for a species, the ordinary case.
  species,

  /// Variety bonus at 5 / 10 / 15 / 20 species in a day (B1–B5).
  variety,

  /// Early riser, before 09:00 (B6).
  early,

  /// New place (B7).
  place,

  /// Week wrap-up (B8).
  week,
}

/// An immutable record of stars awarded (DAT-03).
///
/// **Append-only.** Rows are never edited and never deleted. The full score is
/// recomputable from the `Detection` rows at any time — but a recomputation
/// re-derives multipliers and bonuses only, and never touches the frozen
/// fields below.
class ScoreEvents extends Table with SyncableRow {
  /// Local calendar day, `YYYY-MM-DD` (DAT-05). The day the child would call
  /// it, in the device timezone.
  TextColumn get dayKey => text()();

  DateTimeColumn get awardedAt => dateTime()();

  IntColumn get type => intEnum<ScoreEventType>()();

  /// Null for the day-level bonuses (variety, early riser, week).
  TextColumn get scientificName => text().nullable()();

  // ── Frozen at the moment of detection (PKT-15) ───────────────────────────
  //
  // None of these may ever be recalculated. The rarity scale is rebuilt per
  // location *and* per week, so a value re-derived later would not even match
  // for the same child on the same day in a different park.

  /// Rarity tier index at the moment of detection, 0 = rare … 5 = abundant.
  IntColumn get levelAtDetection => integer().nullable()();

  /// Base star value before multipliers (PKT-02).
  IntColumn get baseValue => integer()();

  /// Geo-model week 1–48 (four per calendar month) — **not** the ISO week.
  IntColumn get geoWeek => integer().nullable()();

  /// Coarsened cell the scale was built for.
  TextColumn get gridCell => text().nullable()();

  /// Confidence threshold that applied when this was awarded.
  ///
  /// The slider stays adjustable through the MVP (D16), so without this the
  /// history's meaning would silently change whenever it moves, and NFA-06
  /// would fail.
  IntColumn get appliedThreshold => integer()();

  /// Version of the `ScoringRules` object in force (DAT-04).
  IntColumn get ruleVersion => integer()();

  // ── Re-derivable by recomputeAllScores() ─────────────────────────────────

  /// Highest applicable multiplier. Multipliers never stack (PKT-07).
  IntColumn get multiplier => integer().withDefault(const Constant(1))();

  /// Additive bonus, applied after the multiplier (2.6).
  IntColumn get bonus => integer().withDefault(const Constant(0))();

  /// `baseValue × multiplier + bonus`, stored so the chart does not have to
  /// recompute it per row.
  IntColumn get total => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per species per day — the table that makes double-awarding
/// impossible (PKT-03).
class DaySpecies extends Table with SyncableRow {
  TextColumn get dayKey => text()();
  TextColumn get scientificName => text()();
  TextColumn get firstDetectionId => text().references(Detections, #id)();

  /// How often the species was heard that day. Only the first one scores.
  IntColumn get detectionCount => integer().withDefault(const Constant(1))();

  IntColumn get awardedPoints => integer()();

  /// False while a high-value detection is still awaiting a second sighting
  /// (PKT-11). Points are awarded either way.
  BoolColumn get confirmed => boolean().withDefault(const Constant(true))();

  /// **The constraint PKT-03 asks for.** Not a code check — the database
  /// refuses the second insert, so double-awarding is not a bug that can be
  /// written.
  @override
  List<Set<Column>> get uniqueKeys => [
    {profileId, dayKey, scientificName},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

/// The year list — a second collection that empties every January (3.4).
///
/// Carries more weight than originally planned: with the off-list case removed
/// (D20), this is the main way a child experiences the year changing.
class YearSpecies extends Table with SyncableRow {
  IntColumn get year => integer()();
  TextColumn get scientificName => text()();
  TextColumn get firstDetectionId => text().references(Detections, #id)();
  DateTimeColumn get firstSeenAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {profileId, year, scientificName},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

/// ⚠️ **The life list. Handle with more care than anything else here.**
///
/// A row means "this child has heard this species at least once, ever", and
/// that is what the first-find ×3 multiplier checks (PKT-04).
///
/// **Writing a row too early burns that multiplier permanently.** A test-mode
/// detection, a manually added species (LIVE-16) or an import must never reach
/// this table — otherwise the child's real first find, weeks later, quietly
/// scores 100 instead of 300, for a reason nothing in the app can explain.
/// That is precisely the hidden punishment principle 1 forbids.
///
/// Only a scoring detection writes here (DAT-11).
class LifeSpecies extends Table with SyncableRow {
  TextColumn get scientificName => text()();
  TextColumn get firstDetectionId => text().references(Detections, #id)();
  DateTimeColumn get firstSeenAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {profileId, scientificName},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

/// A badge or achievement the child has earned (AUS-*).
///
/// Only earned rows exist. Progress towards an unearned one is derived from
/// the tables above rather than stored, so a rule change (AUS-12) cannot leave
/// a stale half-finished row behind.
class Achievements extends Table with SyncableRow {
  /// Stable identifier, e.g. `collector_50` or `badge_ten_in_one_go`.
  TextColumn get key => text()();

  /// Tier within a family of achievements, where one exists.
  IntColumn get tier => integer().nullable()();

  DateTimeColumn get unlockedAt => dateTime()();

  /// The day it was earned, for the journal.
  TextColumn get dayKey => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {profileId, key, tier},
  ];

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per child on this device (DAT-07).
class UserProfiles extends Table with SyncableRow {
  /// Shown on the home screen and the points overview.
  TextColumn get displayName => text().nullable()();

  /// Running total. Materialised rather than summed on every read, and
  /// rebuildable from [ScoreEvents] at any time.
  IntColumn get totalStars => integer().withDefault(const Constant(0))();

  /// ⚠️ **Levels ratchet.** The highest level ever reached, never lowered.
  ///
  /// Levels are thresholds on [totalStars], and a rebalancing (AUS-12) can
  /// lower that total. Without this column the child would drop a level and
  /// lose the avatar stage tied to it (AVA-02) — the app taking something away
  /// for something the child did not do, which principle 1 forbids.
  IntColumn get highestLevelReached => integer().withDefault(const Constant(1))();

  /// Home region chosen during onboarding (SET-09, D18). Without a cell there
  /// is no rarity level and therefore no stars, so this is set before the
  /// first detection.
  TextColumn get homeGridCell => text().nullable()();

  /// Serialized avatar state (AVA-*). Null until the avatar exists.
  TextColumn get avatarState => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
