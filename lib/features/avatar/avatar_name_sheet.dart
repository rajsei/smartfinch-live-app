// =============================================================================
// AvatarNameSheet — naming the bird, from a list (AVA-05)
// =============================================================================
//
// `AVA-05` words it precisely: "pick from a preset list, or keep it purely
// local". Both halves matter, and they are two different reasons.
//
// **A list, not a text field.** `KID-07` says no free text that could reach
// another person, and `AVA-05` names the reason — free text is a moderation
// problem the moment anything is ever shared. `LOG-13`'s place names are the
// one exception the specification made deliberately, and it made it because a
// place name is for the child's own memory of a walk. An avatar's name has no
// such argument: it is decoration, and a list gives a child the choice without
// the app acquiring a moderation surface it would then have to defend.
//
// **Purely local.** The name lives in `UserProfiles.avatarState` and travels
// only in a backup (`SET-07`). It is on no screen that leaves the phone — the
// shared day image (`LOG-11`) carries the date, the stars and the species, and
// nothing about the child.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import 'avatar_providers.dart';
import 'level_ladder.dart';
import 'widgets/avatar_card.dart';

/// The names on offer (`AVA-05`).
///
/// Not localised, and that is the decision: a name is a name. Translating
/// "Pieps" into eleven languages would produce eleven different birds for a
/// family that switches the app's language, and a child who named their bird
/// last week would find it renamed. They are short, pronounceable across the
/// supported locales, and none of them is a real person's name.
const List<String> kAvatarNames = [
  'Pieps',
  'Flöckchen',
  'Krümel',
  'Fips',
  'Nimbus',
  'Zilpi',
  'Momo',
  'Tilda',
  'Rufus',
  'Wicki',
  'Pino',
  'Suki',
];

/// Lets the child name their bird, or clear the name again.
Future<void> showAvatarNameSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _AvatarNameSheet(),
  );
}

class _AvatarNameSheet extends ConsumerWidget {
  const _AvatarNameSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    final current = ref.watch(avatarNameProvider).value;
    final stage =
        ref.watch(levelProgressProvider).value?.stage ?? AvatarStage.egg;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarFigure(stage: stage, size: 44),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.avatarNameTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in kAvatarNames)
                  ChoiceChip(
                    label: Text(name),
                    selected: name == current,
                    onSelected: (_) async {
                      await setAvatarName(ref, name);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            if (current != null) ...[
              const SizedBox(height: 12),
              // Undoing a choice is part of making one. A child who tries a
              // name and does not like it should not have to pick a different
              // one to get rid of it.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    await setAvatarName(ref, null);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(AppIcons.close, size: 18),
                  label: Text(l10n.avatarNameClear),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
