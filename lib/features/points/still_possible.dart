// =============================================================================
// What is still possible today (HOME-06)
// =============================================================================
//
// The specification calls this "the single best lever for daily return —
// **without a push notification**", and the second half is the constraint. The
// card does not chase a child; it is there when they open the app anyway, and
// it answers the one question a home screen can usefully answer: *is there
// anything left worth going outside for?*
//
// ### Two words in the name do all the work
//
// **Today.** A badge earned this morning is not a suggestion this afternoon,
// so "open" means open *today* — not never-earned. `EarnedBadge.lastEarnedOn`
// carries the day it last happened, and that is the whole test.
//
// **Possible.** Suggesting 🌅 *The early bird* at three in the afternoon is
// worse than suggesting nothing: it is the app asking for something that
// cannot be done any more, which teaches a child that the card is noise. So
// every badge with a clock on it is filtered by the clock.
//
// Nothing here is a to-do list. At most two, and when there is nothing to
// suggest the card does not appear — the same rule the species page follows
// for a bird never heard.
// =============================================================================

import 'points_models.dart';

/// At most this many suggestions. Two is a nudge; five is a chore list.
const int kStillPossibleLimit = 2;

/// Whether [badge] can still be earned at [hour] of the day.
///
/// Only the badges whose condition names a time have an answer here; the rest
/// are possible until midnight. The hours mirror the catalogue in 3.2 exactly
/// — if one moves, it moves in both places or the card starts lying.
bool isStillPossibleAt(BadgeDefinition badge, int hour) => switch (badge.key) {
  // Before 09:00, so at 09:00 it is gone.
  'earlyBird' || 'dawnChorus' => hour < 9,

  // After 22:00 — suggestible right up until it starts, and during it.
  'nightOwl' => hour < 23,

  _ => true,
};

/// The one or two things worth suggesting right now (`HOME-06`).
///
/// [earnedToday] is the day key of a badge's most recent earning; a badge is
/// a candidate when that is not today's.
///
/// Returned in catalogue order, which runs roughly easiest first — a child
/// reading two suggestions should find the nearer one on top.
///
/// Pure and injected rather than reading the database itself, because "what
/// can still be done at this hour" is a rule with edges at 09:00 and 22:00 and
/// a test should be able to stand on either side of them without a clock.
List<BadgeDefinition> stillPossibleToday({
  required String todayKey,
  required String? Function(String badgeKey) lastEarnedOn,
  required int hour,
  int limit = kStillPossibleLimit,
}) {
  final open = <BadgeDefinition>[];

  for (final badge in kDailyBadges) {
    if (lastEarnedOn(badge.key) == todayKey) continue;
    if (!isStillPossibleAt(badge, hour)) continue;

    open.add(badge);
    if (open.length == limit) break;
  }

  return open;
}
