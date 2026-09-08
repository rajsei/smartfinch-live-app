// =============================================================================
// PlaceNameEditor — the child's own word for where they were (LOG-13)
// =============================================================================
//
// A recording gets a name the child types: "Oma", "Urlaub", "Schulweg", "Am
// Teich". Better than a geocoded place name for three reasons the requirement
// names, and all three matter here:
//
//   * it works **offline**, which is where most listening happens;
//   * it sends **nothing to anyone** (`NFA-07`, `KID-07`);
//   * it is **their word** for the place, which is what makes a recording
//     recognisable to them weeks later.
//
// **Editable afterwards** is the point, not a convenience. A walk is labelled
// in the evening, when there is time to think of a name for it — during the
// walk the child is looking at birds.
//
// The text never leaves the device: it is not rendered into the shared day
// image (`LOG-11`, `KID-07`).
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../journal_providers.dart';

/// Shows and edits the place names of one day's sessions.
class PlaceNameEditor extends ConsumerWidget {
  const PlaceNameEditor({super.key, required this.dayKey});

  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final sessions = ref.watch(journalDaySessionsProvider(dayKey)).value;

    if (sessions == null || sessions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: OutlinedButton.icon(
              onPressed:
                  () => _edit(
                    context,
                    ref,
                    sessionId: session.id,
                    current: session.placeName,
                  ),
              icon: Icon(
                session.placeName == null
                    ? AppIcons.editNote
                    : AppIcons.locationOn,
                size: 18,
              ),
              label: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  session.placeName ?? l10n.journalNamePlacePrompt,
                  style:
                      session.placeName == null
                          ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                          : theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    required String sessionId,
    required String? current,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    // Names already used, so "Oma" is one tap rather than typed again — and so
    // the same place keeps the same spelling (LOG-14).
    final known = await ref.read(journalKnownPlacesProvider.future);
    if (!context.mounted) return;

    final name = await showDialog<String>(
      context: context,
      builder:
          (context) => _PlaceNameDialog(
            current: current,
            suggestions: known,
            l10n: l10n,
          ),
    );
    if (name == null) return;

    final trimmed = name.trim();
    await ref
        .read(journalRepositoryProvider)
        .renameSession(sessionId, trimmed.isEmpty ? null : trimmed);

    ref
      ..invalidate(journalDaySessionsProvider(dayKey))
      ..invalidate(journalDayProvider(dayKey))
      ..invalidate(journalDaysProvider)
      ..invalidate(journalBucketsProvider)
      ..invalidate(journalKnownPlacesProvider);
  }
}

class _PlaceNameDialog extends StatefulWidget {
  const _PlaceNameDialog({
    required this.current,
    required this.suggestions,
    required this.l10n,
  });

  final String? current;
  final List<String> suggestions;
  final AppLocalizations l10n;

  @override
  State<_PlaceNameDialog> createState() => _PlaceNameDialogState();
}

class _PlaceNameDialogState extends State<_PlaceNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;

    return AlertDialog(
      title: Text(l10n.journalNamePlaceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 40,
            decoration: InputDecoration(
              hintText: l10n.journalNamePlaceHint,
              counterText: '',
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (widget.suggestions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.journalNamePlaceUsedBefore,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final suggestion in widget.suggestions.take(6))
                  ActionChip(
                    label: Text(suggestion),
                    onPressed:
                        () => setState(() {
                          _controller.text = suggestion;
                        }),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.sessionSave),
        ),
      ],
    );
  }
}
