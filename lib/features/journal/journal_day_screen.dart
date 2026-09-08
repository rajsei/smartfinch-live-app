// =============================================================================
// JournalDayScreen — one day, species by species
// =============================================================================
//
// `LOG-03` asks for every species of the day **with the points it earned and
// the multiplier that applied**. That second half is the part worth defending:
// a child who sees 300 for a robin and 50 for a blackbird will work out the
// rule from the chips, and a list of bare numbers teaches them nothing except
// that the app decides.
//
// Three further things live here:
//
//   **✨ NEW** (`LOG-09`) marks a species that entered the life list on this
//   day — first time *ever*, not first time today, so reopening the day in a
//   month still marks the right ones.
//
//   **Outside scoring** (`LOG-15`) is a second list, visibly set apart. Not a
//   warning and not an error: those recordings exist, they can be listened to,
//   they simply did not count. The child did nothing wrong.
//
//   **The place name** (`LOG-13`) is editable here, which is the point of it —
//   a walk can be labelled in the evening, when there is time to think of a
//   name for it.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../shared/widgets/content_width_constraint.dart';
import '../../shared/providers/settings_providers.dart';
import '../explore/explore_providers.dart';
import '../explore/widgets/species_info_overlay.dart';
import '../../core/theme/score_colors.dart';
import '../scoring/scoring_rules.dart';
import '../settings/animation_level.dart';
import 'day_share_screen.dart';
import 'journal_models.dart';
import 'journal_providers.dart';
import 'journal_screen.dart';
import 'widgets/journal_clip_sheet.dart';
import 'widgets/place_name_editor.dart';

/// One day of the journal (`LOG-03`, `LOG-09`, `LOG-13`, `LOG-15`).
class JournalDayScreen extends ConsumerWidget {
  const JournalDayScreen({super.key, required this.dayKey});

  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final detail = ref.watch(journalDayProvider(dayKey));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          detail.value == null
              ? l10n.journalTitle
              : formatJournalDate(context, detail.value!.day.date),
        ),
        actions: [
          // The app's only way out (LOG-11), and it opens a preview rather
          // than a share sheet: a child sends the picture after seeing it.
          if (detail.value != null && !detail.value!.day.isEmpty)
            IconButton(
              tooltip: l10n.journalShareDayButton,
              icon: const Icon(AppIcons.share),
              onPressed:
                  () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DayShareScreen(detail: detail.value!),
                    ),
                  ),
            ),
        ],
      ),
      body: ContentWidthConstraint(
        child: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(l10n.journalUnavailable)),
          data: (detail) => _DayBody(detail: detail),
        ),
      ),
    );
  }
}

class _DayBody extends ConsumerWidget {
  const _DayBody({required this.detail});

  final JournalDayDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      children: [
        _DayHeader(day: detail.day),
        const SizedBox(height: 12),

        PlaceNameEditor(dayKey: detail.day.dayKey),

        if (detail.scored.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel(text: l10n.journalCollected),
          for (final species in detail.scored)
            JournalSpeciesTile(species: species, dayKey: detail.day.dayKey),
        ],

        if (detail.bonuses.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionLabel(text: l10n.journalDayBonuses),
          for (final bonus in detail.bonuses)
            ListTile(
              dense: true,
              leading: const Text('⭐', style: TextStyle(fontSize: 18)),
              title: Text(_bonusLabel(l10n, bonus.key)),
              trailing: Text(
                '+${bonus.stars}',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],

        // Set apart, and last: these are real recordings that did not count.
        if (detail.hasOutsideScoring) ...[
          const SizedBox(height: 20),
          _OutsideScoringHeader(count: detail.outsideScoring.length),
          for (final species in detail.outsideScoring)
            JournalSpeciesTile(species: species, dayKey: detail.day.dayKey),
        ],
      ],
    );
  }

  String _bonusLabel(AppLocalizations l10n, String key) => switch (key) {
    'variety' => l10n.bonusVariety,
    'early_riser' => l10n.bonusEarlyRiser,
    'new_place' => l10n.bonusNewPlace,
    _ => l10n.bonusWeekWrapUp,
  };
}

/// Stars and species count for the day.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final JournalDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text('⭐', style: theme.textTheme.headlineSmall),
          const SizedBox(width: 8),
          Text(
            '${day.stars}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const Spacer(),
          Text(
            l10n.journalDaySpecies(day.speciesCount),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// One species row, which opens into the times it was heard (`LOG-03`,
/// `LOG-09`, `LOG-07`).
///
/// Tapping expands rather than opening the bird's page, because the row's own
/// contents are one level in and the page is two. The link to the page is the
/// last thing inside, where a child who wanted it will find it — and where the
/// old session concept lives on, one level deeper than it used to.
class JournalSpeciesTile extends ConsumerStatefulWidget {
  const JournalSpeciesTile({
    super.key,
    required this.species,
    required this.dayKey,
  });

  final JournalSpecies species;

  /// What the clip sheet invalidates after the keep switch (`SET-12`).
  final String dayKey;

  @override
  ConsumerState<JournalSpeciesTile> createState() => _JournalSpeciesTileState();
}

class _JournalSpeciesTileState extends ConsumerState<JournalSpeciesTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final species = widget.species;
    final taxonomy = ref.watch(taxonomyServiceProvider).value;
    final locale = ref.watch(effectiveSpeciesLocaleProvider);
    final displayName =
        taxonomy?.lookup(species.scientificName)?.commonNameForLocale(locale) ??
        species.scientificName;
    final motion = animationLevelFor(context, ref);

    final header = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap:
          species.isExpandable
              ? () => setState(() => _open = !_open)
              : () => _openSpeciesPage(displayName),
      title: Row(
        children: [
          Flexible(
            child: Text(
              displayName,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                // The one visual difference that carries meaning: a species
                // that did not count reads as quieter, not as wrong.
                color:
                    species.scored
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (species.isNew) ...[const SizedBox(width: 6), _NewMarker()],
        ],
      ),
      subtitle: Text(
        _subtitle(context, l10n),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          species.scored
              ? _Award(species: species)
              : Text(
                l10n.journalOutsideScoringShort,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          if (species.isExpandable)
            Icon(
              _open ? AppIcons.expandLess : AppIcons.expandMore,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      ),
    );

    final body =
        _open
            ? _HeardTimes(
              species: species,
              speciesName: displayName,
              dayKey: widget.dayKey,
              onOpenSpeciesPage: () => _openSpeciesPage(displayName),
            )
            : const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        // Off means off: at that level the row simply is or is not open
        // (SET-02), and nothing on this screen slides.
        if (motion == AnimationLevel.off)
          body
        else
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: body,
          ),
      ],
    );
  }

  void _openSpeciesPage(String displayName) => SpeciesInfoOverlay.show(
    context,
    ref,
    scientificName: widget.species.scientificName,
    commonName: displayName,
  );

  String _subtitle(BuildContext context, AppLocalizations l10n) {
    final time = DateFormat.Hm(
      Localizations.localeOf(context).toString(),
    ).format(widget.species.firstHeardAt);

    if (widget.species.detectionCount <= 1) return time;
    return '$time · ${l10n.journalHeardTimes(widget.species.detectionCount)}';
  }
}

/// Every time the species was heard that day (`LOG-07`).
class _HeardTimes extends StatelessWidget {
  const _HeardTimes({
    required this.species,
    required this.speciesName,
    required this.dayKey,
    required this.onOpenSpeciesPage,
  });

  final JournalSpecies species;
  final String speciesName;
  final String dayKey;
  final VoidCallback onOpenSpeciesPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, detection) in species.detections.indexed)
            _HeardRow(
              detection: detection,
              speciesName: speciesName,
              dayKey: dayKey,
              // Only the first hearing of the day scored (PKT-04). Saying so
              // here is the cheapest place in the app to teach that rule.
              scored: species.scored && index == 0,
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onOpenSpeciesPage,
              icon: const Icon(AppIcons.infoOutline, size: 18),
              label: Text(l10n.journalAboutThisBird),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One hearing: when, how sure, and the recording if it was kept.
class _HeardRow extends StatelessWidget {
  const _HeardRow({
    required this.detection,
    required this.speciesName,
    required this.dayKey,
    required this.scored,
  });

  final JournalDetection detection;
  final String speciesName;
  final String dayKey;
  final bool scored;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scoreColors = theme.extension<ScoreColors>();
    final percent = (detection.confidence * 100).round();

    return InkWell(
      onTap:
          detection.hasClip
              ? () => showJournalClipSheet(
                context,
                detection: detection,
                speciesName: speciesName,
                dayKey: dayKey,
              )
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Text(
              DateFormat.Hm(
                Localizations.localeOf(context).toString(),
              ).format(detection.heardAt),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (scored) ...[
              const SizedBox(width: 8),
              Text(
                l10n.journalThisOneScored,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const Spacer(),
            Semantics(
              label: l10n.a11yConfidencePercent(percent),
              excludeSemantics: true,
              child: Text(
                '$percent %',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scoreColors?.forScore(detection.confidence),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (detection.hasClip)
              Icon(
                detection.isFavourite
                    ? AppIcons.bookmarkFilled
                    : AppIcons.graphicEq,
                size: 20,
                color:
                    detection.isFavourite
                        ? theme.colorScheme.tertiary
                        : theme.colorScheme.primary,
              )
            else
              // Retention has been through, or the clip was never kept. Said
              // plainly rather than left as a gap the child has to interpret.
              Tooltip(
                message: l10n.journalNoRecording,
                child: Icon(
                  AppIcons.volumeOffRounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The points and the reason for them (`LOG-03`).
class _Award extends StatelessWidget {
  const _Award({required this.species});

  final JournalSpecies species;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final multiplierLabel = switch (species.multiplier) {
      ScoreMultiplier.firstFind => l10n.multiplierFirstFind,
      ScoreMultiplier.permanentGuest => l10n.multiplierPermanentGuest,
      ScoreMultiplier.regular => l10n.multiplierRegular,
      ScoreMultiplier.yearFirst => l10n.multiplierYearFirst,
      ScoreMultiplier.none => null,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '⭐ ${species.stars}',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        if (multiplierLabel != null)
          Text(
            '$multiplierLabel ×${species.multiplier.factor}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// "✨ NEW" (`LOG-09`).
class _NewMarker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '✨ ${AppLocalizations.of(context)!.multiplierFirstFind}',
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onTertiary,
        ),
      ),
    );
  }
}

/// Introduces the outside-scoring list, in the register `LOG-15` asks for.
class _OutsideScoringHeader extends StatelessWidget {
  const _OutsideScoringHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        // Neutral, not error: a note rather than a warning (principle 1).
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppIcons.infoOutline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.journalOutsideScoringTitle(count),
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.journalOutsideScoringExplainer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
