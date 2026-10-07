// =============================================================================
// StorageSettingsSection — Settings → Storage (SET-06)
// =============================================================================
//
// Three rows and one action, on the plain settings screen (`SET-01` lists
// storage there): what the recordings take, what the collection takes, and
// "Delete recordings".
//
// The collection row is there to be compared, not acted on. Next to a hundred
// megabytes of audio, two megabytes of species and stars is the reassurance a
// parent needs before pressing the button below it — and the button's own
// subtitle says the collection stays.
//
// Measured each time the screen opens, and shown without a spinner: a row with
// no number yet is better than a progress indicator for a figure nobody is
// waiting on.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/app_haptics.dart';
import '../../../shared/utils/app_icons.dart';
import '../../journal/journal_providers.dart';
import '../storage_providers.dart';
import '../storage_service.dart';

/// The storage section of the plain settings screen (`SET-06`).
class StorageSettingsSection extends ConsumerStatefulWidget {
  const StorageSettingsSection({super.key, required this.sectionHeader});

  /// The settings screen's own section header, so this one looks the same.
  final Widget Function({required String title, required String subtitle})
  sectionHeader;

  @override
  ConsumerState<StorageSettingsSection> createState() =>
      _StorageSettingsSectionState();
}

class _StorageSettingsSectionState
    extends ConsumerState<StorageSettingsSection> {
  bool _deleting = false;

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

    final canDelete = usage != null && usage.recordingBytes > 0 && !_deleting;

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

      // The journal caches its days; without this a day opened next would
      // still offer to play recordings that are gone.
      ref
        ..invalidate(storageUsageProvider)
        ..invalidate(journalDaysProvider)
        ..invalidate(journalBucketsProvider)
        ..invalidate(journalDayProvider);

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
