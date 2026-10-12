// =============================================================================
// StorageSettingsSection — Settings → Storage (SET-06, SET-12)
// =============================================================================
//
// Behind Advanced settings: what the recordings take, what the collection
// takes, the clean-up's two thresholds, and "Delete recordings". It started on the
// plain screen, where `SET-01` listed storage, and moved on 2026-10-07 with
// the danger zone — deleting is something a parent goes looking for, not
// something a child should scroll past on the first page.
//
// The collection row is there to be compared, not acted on. Next to a hundred
// megabytes of audio, two megabytes of species and stars is the reassurance a
// parent needs before pressing the button below it — and the button's own
// subtitle says the collection stays.
//
// Measured each time the screen opens, and shown without a spinner: a row with
// no number yet is better than a progress indicator for a figure nobody is
// waiting on.
//
// **The thresholds (`SET-12`) sit between the sizes and the button** — the
// gentle way to make room, next to the blunt one. Loosening one deletes
// nothing. Tightening one can make recordings go at once, so the app counts
// them first, asks with that number, and on a yes runs the clean-up straight
// away: what the question counted is what goes, not something discovered on
// the next start.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/app_haptics.dart';
import '../../../shared/utils/app_icons.dart';
import '../../journal/journal_providers.dart';
import '../../scoring/scoring_providers.dart';
import '../clip_retention.dart';
import '../clip_retention_settings.dart';
import '../storage_providers.dart';
import '../storage_service.dart';

/// The storage section of the advanced settings screen (`SET-06`).
class StorageSettingsSection extends ConsumerStatefulWidget {
  const StorageSettingsSection({
    super.key,
    required this.sectionHeader,
    required this.titleWithHelp,
  });

  /// The settings screen's own section header, so this one looks the same.
  final Widget Function({required String title, required String subtitle})
  sectionHeader;

  /// The settings screen's title with its help button, for the thresholds.
  final Widget Function({required String title, String? helpBody})
  titleWithHelp;

  @override
  ConsumerState<StorageSettingsSection> createState() =>
      _StorageSettingsSectionState();
}

class _StorageSettingsSectionState
    extends ConsumerState<StorageSettingsSection> {
  bool _deleting = false;

  /// A stricter threshold is being counted, confirmed or applied.
  bool _trimming = false;

  bool get _busy => _deleting || _trimming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final usage = ref.watch(storageUsageProvider).value;

    String size(int bytes) => formatStorageSize(bytes, locale);

    final recordingsDetail =
        usage == null
            ? null
            : [
              l10n.storageRecordingsCount(usage.recordingCount),
              if (usage.keptCount > 0)
                l10n.storageRecordingsKept(usage.keptCount),
            ].join(' · ');

    final canDelete = usage != null && usage.recordingBytes > 0 && !_busy;
    final policy = ref.watch(clipRetentionPolicyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.sectionHeader(
          title: l10n.settingsStorage,
          subtitle: l10n.settingsStorageDescription,
        ),
        ListTile(
          leading: const Icon(AppIcons.libraryMusic),
          title: Text(l10n.storageRecordings),
          subtitle: recordingsDetail == null ? null : Text(recordingsDetail),
          trailing: _Amount(usage == null ? null : size(usage.recordingBytes)),
        ),
        ListTile(
          leading: const Icon(AppIcons.gridViewRounded),
          title: Text(l10n.storageCollection),
          subtitle: Text(l10n.storageCollectionDetail),
          trailing: _Amount(usage == null ? null : size(usage.collectionBytes)),
        ),
        // SET-12 · how long every recording stays, however many there are.
        _ThresholdTile(
          title: widget.titleWithHelp(
            title: l10n.storageRetentionAge,
            helpBody: l10n.storageRetentionHelp,
          ),
          subtitle: l10n.storageRetentionAgeSubtitle,
          value: policy.minimumAge.inDays,
          options: ClipRetentionPolicy.dayOptions,
          label: l10n.storageRetentionDays,
          onChanged: _busy ? null : (days) => _changeThreshold(days: days),
        ),
        // SET-12 · how many of one species before the least certain go.
        _ThresholdTile(
          title: widget.titleWithHelp(
            title: l10n.storageRetentionCap,
            helpBody: l10n.storageRetentionHelp,
          ),
          subtitle: l10n.storageRetentionCapSubtitle,
          value: policy.perSpeciesCap,
          options: ClipRetentionPolicy.perSpeciesOptions,
          label: (cap) => '$cap',
          onChanged: _busy ? null : (cap) => _changeThreshold(cap: cap),
        ),
        // The error palette, like the danger zone's actions: this one cannot
        // be undone either.
        ListTile(
          enabled: canDelete,
          leading: Icon(
            AppIcons.deleteOutline,
            color: canDelete ? theme.colorScheme.error : null,
          ),
          title: Text(
            l10n.storageDeleteRecordings,
            style: TextStyle(color: canDelete ? theme.colorScheme.error : null),
          ),
          subtitle: Text(l10n.storageDeleteRecordingsSubtitle),
          trailing:
              _deleting
                  ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : null,
          onTap: canDelete ? () => _delete(usage) : null,
        ),
        const Divider(),
      ],
    );
  }

  Future<void> _delete(StorageUsage usage) async {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final includeKept = await _confirm(usage);
    if (includeKept == null || !mounted) return;

    setState(() => _deleting = true);
    try {
      final result = await ref
          .read(storageServiceProvider)
          .deleteRecordings(includeKept: includeKept);
      if (!mounted) return;
      _refreshAfterDeleting();

      _say(
        result.failed > 0
            ? l10n.storageDeleteFailed
            : l10n.storageDeleteDone(
              result.deleted,
              formatStorageSize(result.freedBytes, locale),
            ),
      );
    } on StillListeningException {
      _say(l10n.storageDeleteWhileListening);
    } catch (error, stack) {
      debugPrint('[Storage] deleting recordings failed: $error\n$stack');
      _say(l10n.storageDeleteFailed);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  /// Saves a threshold, after asking when a stricter one deletes something.
  Future<void> _changeThreshold({int? days, int? cap}) async {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.read(clipRetentionPolicyProvider);
    final next = ClipRetentionPolicy(
      minimumAge: days == null ? current.minimumAge : Duration(days: days),
      perSpeciesCap: cap ?? current.perSpeciesCap,
    );

    setState(() => _trimming = true);
    try {
      // Only a stricter policy can make anything go now, and it says how much
      // before it is saved — a parent who lowers the cap from 100 to 20 should
      // see the number before the recordings are gone, not after.
      var doomed = 0;
      if (next.isStricterThan(current)) {
        doomed = await ref.read(clipRetentionJobProvider).wouldDelete(next);
        if (!mounted) return;
        if (doomed > 0 && !await _confirmThreshold(doomed)) return;
      }

      if (days != null) {
        await ref.read(clipRetentionDaysProvider.notifier).set(days);
      }
      if (cap != null) {
        await ref.read(clipRetentionPerSpeciesProvider.notifier).set(cap);
      }
      if (doomed == 0) return;

      // The job provider has rebuilt with the new thresholds.
      final result = await ref.read(clipRetentionJobProvider).run();
      if (!mounted) return;
      _refreshAfterDeleting();
      _say(
        result.failed > 0
            ? l10n.storageDeleteFailed
            : l10n.storageRetentionDone(result.deleted),
      );
    } catch (error, stack) {
      debugPrint(
        '[Storage] applying a retention threshold failed: $error\n$stack',
      );
      _say(l10n.storageDeleteFailed);
    } finally {
      if (mounted) setState(() => _trimming = false);
    }
  }

  /// Whether the parent agrees to [count] recordings going now.
  Future<bool> _confirmThreshold(int count) async {
    final l10n = AppLocalizations.of(context)!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.storageRetentionConfirmTitle),
          content: Text(l10n.storageRetentionConfirmBody(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            // The error palette, like "Delete recordings": this cannot be
            // undone either.
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              onPressed: () {
                AppHaptics.mediumImpact(dialogContext);
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(l10n.storageDeleteAction),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  /// The journal caches its days; without this a day opened next would still
  /// offer to play recordings that are gone.
  void _refreshAfterDeleting() {
    ref
      ..invalidate(storageUsageProvider)
      ..invalidate(journalDaysProvider)
      ..invalidate(journalBucketsProvider)
      ..invalidate(journalDayProvider);
  }

  /// Null when cancelled; otherwise whether the kept recordings go too.
  ///
  /// The box for the kept ones starts unticked and only appears when there
  /// are any: a child marked them to keep, and that holds unless an adult
  /// says otherwise in so many words.
  Future<bool?> _confirm(StorageUsage usage) {
    final l10n = AppLocalizations.of(context)!;
    var includeKept = false;

    return showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              return AlertDialog(
                title: Text(l10n.storageDeleteConfirmTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.storageDeleteConfirmBody),
                    if (usage.keptCount > 0) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: includeKept,
                        onChanged:
                            (v) => setDialogState(() => includeKept = v!),
                        title: Text(
                          l10n.storageDeleteIncludeKept(usage.keptCount),
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                    onPressed: () {
                      AppHaptics.mediumImpact(dialogContext);
                      Navigator.of(dialogContext).pop(includeKept);
                    },
                    child: Text(l10n.storageDeleteAction),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// One retention threshold: a title, what it does, and a short list to pick
/// from.
class _ThresholdTile extends StatelessWidget {
  const _ThresholdTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.options,
    required this.label,
    required this.onChanged,
  });

  final Widget title;
  final String subtitle;
  final int value;
  final List<int> options;
  final String Function(int value) label;

  /// Null while something is being deleted.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    // A stored value this build does not offer is shown rather than snapped:
    // the dropdown must contain it, and quietly moving it would change what
    // the clean-up deletes.
    final values = {...options, value}.toList()..sort();
    final changed = onChanged;

    return ListTile(
      title: title,
      subtitle: Text(subtitle),
      trailing: DropdownButton<int>(
        value: value,
        underline: const SizedBox.shrink(),
        items: [
          for (final v in values)
            DropdownMenuItem(value: v, child: Text(label(v))),
        ],
        onChanged:
            changed == null
                ? null
                : (v) {
                  if (v != null && v != value) changed(v);
                },
      ),
    );
  }
}

/// A size at the end of a row, or nothing while it is being measured.
class _Amount extends StatelessWidget {
  const _Amount(this.text);

  final String? text;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    return Text(
      text!,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
