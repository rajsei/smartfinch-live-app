// =============================================================================
// BackupScreen — worded for a parent (SET-07)
// =============================================================================
//
// The one screen in Smartfinch not written for a child. A parent arrives here
// for one of two reasons: they are setting up a new phone, or they are about
// to reset the old one. Both are moments of mild panic, so the screen says
// what will happen in plain sentences and puts the irreversible half behind a
// confirmation that names what is being replaced.
//
// ### Saving is a share, restoring is a decision
//
// **Save** hands the file to the system share sheet, so it can go wherever the
// family already keeps things — a cloud drive, an email to themselves. The app
// deliberately does not manage a backup location: it has no account, and a
// file the parent placed somewhere they chose is one they can find again.
//
// **Restore replaces everything.** It is shown as such, with the contents of
// the file read out first — "412 species, saved on 4 May" — because confirming
// a filename is not consent.
// =============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../../shared/utils/share_sheet.dart';
import '../../collection/collection_providers.dart';
import '../../history/services/share_file_params.dart';
import '../../journal/journal_providers.dart';
import '../../points/points_providers.dart';
import '../../scoring/scoring_providers.dart';
import 'backup_service.dart';

/// Reads and writes the whole collection as one file (`SET-07`).
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(appDatabaseProvider));
});

/// Makes every derived screen re-read the database after a restore.
///
/// The **read-side** repositories only. Invalidating `appDatabaseProvider`
/// would cascade further and be tidier, but it also closes the database — and
/// a live session holds a coordinator that would still be writing to it. These
/// four cover every screen that displays history, and each one's dependents
/// follow because they `watch` it.
void refreshAfterRestore(WidgetRef ref) {
  ref
    ..invalidate(journalRepositoryProvider)
    ..invalidate(collectionRepositoryProvider)
    ..invalidate(pointsRepositoryProvider)
    ..invalidate(totalStarsProvider);
}

/// Backup and restore, in Settings (`SET-07`).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            l10n.backupExplanation,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(AppIcons.save),
            label: Text(l10n.backupSaveButton),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.backupSaveNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(AppIcons.restartAlt),
            label: Text(l10n.backupRestoreButton),
          ),
          const SizedBox(height: 6),
          // Said before the button is pressed, not only in the dialog after
          // it: a parent should not discover that this replaces everything by
          // being asked to confirm it.
          Text(
            l10n.backupRestoreNote,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final origin = shareOriginFrom(context);

    try {
      final bytes = await ref.read(backupServiceProvider).export();
      final directory = await getTemporaryDirectory();
      final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final file = File('${directory.path}/smartfinch-$stamp.zip');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await reportShareFailure(
        context,
        SharePlus.instance.share(
          shareParamsForFile(file.path, sharePositionOrigin: origin),
        ),
      );
    } catch (error, stack) {
      debugPrint('[BackupScreen] could not save a backup: $error\n$stack');
      _say(AppLocalizations.of(context)!.backupSaveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(type: FileType.any);
    final file = picked?.files.singleOrNull;
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      // Read first, replace second. What is in the file is what the parent is
      // agreeing to, and they cannot agree to a filename.
      final summary = await ref.read(backupServiceProvider).inspect(bytes);
      if (!mounted) return;

      final confirmed = await _confirm(summary);
      if (confirmed != true || !mounted) return;

      await ref.read(backupServiceProvider).restore(bytes);
      if (!mounted) return;

      refreshAfterRestore(ref);
      _say(AppLocalizations.of(context)!.backupRestoreDone(summary.species));
    } on BackupException catch (error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      _say(switch (error.reason) {
        BackupFailure.tooNew => l10n.backupTooNew,
        BackupFailure.corrupt => l10n.backupCorrupt,
        BackupFailure.notABackup => l10n.backupNotABackup,
      });
    } catch (error, stack) {
      debugPrint('[BackupScreen] could not restore: $error\n$stack');
      if (mounted) _say(AppLocalizations.of(context)!.backupRestoreFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(BackupSummary summary) {
    final l10n = AppLocalizations.of(context)!;
    final saved = DateFormat.yMMMMd(
      Localizations.localeOf(context).toString(),
    ).format(summary.createdAt.toLocal());

    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(l10n.backupRestoreConfirmTitle),
            content: Text(
              l10n.backupRestoreConfirmBody(summary.species, saved),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.backupRestoreConfirmAction),
              ),
            ],
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
