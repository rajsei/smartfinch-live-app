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
//
// ### The automatic backups sit underneath, and say what they are not
//
// `DAT-09`'s three generations are listed last, each restorable through the
// same confirmation. The section says in its first lines that they stay on
// this phone: a parent who sees "automatic backups" and stops saving files
// would find out on the day the phone is lost, which is the one day it
// matters.
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../../shared/providers/settings_providers.dart';
import '../../../shared/utils/share_sheet.dart';
import '../../collection/collection_providers.dart';
import '../../../shared/utils/share_file_params.dart';
import '../../journal/journal_providers.dart';
import '../../points/points_providers.dart';
import '../../scoring/scoring_providers.dart';
import 'auto_backup_service.dart';
import 'backup_providers.dart';
import 'backup_service.dart';

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

          // The recordings are the child's, on the child's device. Whether
          // they travel with the backup is their call — the app's job is to
          // say what it costs, not to decide for them.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.backupIncludeAudio),
            subtitle: Text(l10n.backupIncludeAudioNote),
            value: ref.watch(includeAudioProvider),
            onChanged:
                _busy
                    ? null
                    : (v) => ref.read(includeAudioProvider.notifier).set(v),
          ),
          const SizedBox(height: 12),

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

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),

          // DAT-09. What they are not comes first, in the explanation, so the
          // list below cannot be read as a reason to stop saving files.
          Text(l10n.autoBackupTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.autoBackupExplanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          _AutoBackupList(onRestore: _busy ? null : _restoreAutomatic),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final origin = shareOriginFrom(context);

    try {
      final bytes = await ref
          .read(backupServiceProvider)
          .export(includeAudio: ref.read(includeAudioProvider));
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

    await _restoreBytes(bytes);
  }

  /// One of the automatic generations (`DAT-09`) — through exactly the same
  /// read-confirm-replace as a file the parent picked.
  Future<void> _restoreAutomatic(AutoBackupEntry entry) async {
    final Uint8List bytes;
    try {
      bytes = await entry.backup.file.readAsBytes();
    } catch (error) {
      debugPrint('[BackupScreen] could not read ${entry.backup.file}: $error');
      if (mounted) _say(AppLocalizations.of(context)!.backupCorrupt);
      return;
    }
    if (!mounted) return;
    await _restoreBytes(bytes);
  }

  Future<void> _restoreBytes(Uint8List bytes) async {
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
      ref.invalidate(autoBackupEntriesProvider);
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

/// The automatic generations, newest first (`DAT-09`).
///
/// No spinner while they are read: three small files, and a list that pops in
/// a moment late is better than a progress indicator for something nobody
/// asked for. A listing that fails shows nothing rather than an error — the
/// backups are a safety net, and a parent cannot do anything about a broken
/// one from here.
class _AutoBackupList extends ConsumerWidget {
  const _AutoBackupList({required this.onRestore});

  /// Null while the screen is busy with another save or restore.
  final void Function(AutoBackupEntry entry)? onRestore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(autoBackupEntriesProvider).value;
    if (entries == null) return const SizedBox.shrink();

    if (entries.isEmpty) {
      return Text(
        l10n.autoBackupNone,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final locale = Localizations.localeOf(context).toString();
    final when = DateFormat.yMMMMd(locale).add_Hm();

    return Column(
      children: [
        for (final entry in entries)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.schedule),
            title: Text(when.format(entry.backup.createdAt)),
            subtitle: Text(l10n.autoBackupSpecies(entry.summary.species)),
            trailing: IconButton(
              icon: const Icon(AppIcons.restartAlt),
              tooltip: l10n.autoBackupRestoreTooltip,
              onPressed: onRestore == null ? null : () => onRestore!(entry),
            ),
          ),
      ],
    );
  }
}
