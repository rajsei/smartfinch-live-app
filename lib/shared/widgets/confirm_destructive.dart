// =============================================================================
// confirmDestructive — shared confirmation dialog for destructive actions
// =============================================================================
//
// Use whenever the user is about to do something irreversible: stopping
// a survey, deleting a session, canceling an analysis, clearing data.
//
// Design rationale (see dev/STYLE_GUIDE.md → "Confirmation Dialogs"):
//   • Title is a question ("Stop survey?", "Delete session?").
//   • Body is one or two short sentences explaining what will be lost.
//   • Buttons left → right: Cancel (TextButton), Confirm (FilledButton.tonal
//     colored with `colorScheme.error`).
//   • Fires a medium haptic on confirm before returning — through
//     `AppHaptics`, so the vibration switch (`SET-04`) applies.
//
// Returns `true` when the user confirms, `false` when they cancel or
// dismiss the dialog. Never returns `null` — safe to use in
// `if (await confirmDestructive(...)) { ... }`.
// =============================================================================

import 'package:flutter/material.dart';

import '../utils/app_haptics.dart';

/// Shows a Material 3 confirmation dialog for a destructive action.
///
/// Returns `true` if the user confirmed, `false` otherwise (including
/// dismissal by tap-outside or back gesture).
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.errorContainer,
              foregroundColor: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () {
              AppHaptics.mediumImpact(dialogContext);
              Navigator.of(dialogContext).pop(true);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
