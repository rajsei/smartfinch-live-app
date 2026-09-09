// =============================================================================
// DayShareScreen — see it, then send it (LOG-11)
// =============================================================================
//
// The share is a two-step: the child looks at the card, then decides. That is
// not politeness, it is the safeguard. This is the only path out of the app
// (`LOG-11`), and a one-tap share from the day screen would mean a child hands
// a picture to a chat app without ever having seen what is on it.
//
// The preview shows the *same widget* that gets captured, so "what you see is
// what grandma gets" is true by construction rather than by review.
//
// ### The picture is built from the widget, not painted twice
//
// `RepaintBoundary.toImage` renders the subtree that is already on screen. The
// alternative — a `PictureRecorder` and a hand-written layout — would be a
// second implementation of the card that has to be kept in step with the
// first, and the two would drift the first time someone restyled a chip.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../shared/utils/share_sheet.dart';
import '../../shared/utils/share_file_params.dart';
import 'journal_models.dart';
import 'widgets/day_image_card.dart';

/// Preview of the day image, and the button that sends it (`LOG-11`).
class DayShareScreen extends ConsumerStatefulWidget {
  const DayShareScreen({super.key, required this.detail});

  final JournalDayDetail detail;

  @override
  ConsumerState<DayShareScreen> createState() => _DayShareScreenState();
}

class _DayShareScreenState extends ConsumerState<DayShareScreen> {
  final GlobalKey _cardKey = GlobalKey();

  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.journalShareDayTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: RepaintBoundary(
                    key: _cardKey,
                    child: DayImageCard(detail: widget.detail),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Says what is *not* on the card. A child who wonders
                  // whether "Oma" went with it should not have to squint at
                  // the preview to find out (KID-07, LOG-13).
                  Text(
                    l10n.journalShareDayPrivacy,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(AppIcons.share),
                    label: Text(l10n.journalShareDayButton),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    final origin = shareOriginFrom(context);

    try {
      final file = await _capture();
      if (file == null || !mounted) return;

      await reportShareFailure(
        context,
        SharePlus.instance.share(
          shareParamsForFile(file.path, sharePositionOrigin: origin),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// Renders the previewed card to a PNG in the cache directory.
  ///
  /// The cache rather than documents: the file exists to be handed to another
  /// app, and once that app has copied it there is no reason for Smartfinch to
  /// keep a picture of the child's day lying around.
  Future<File?> _capture() async {
    final boundary =
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    try {
      // Three, so the 360-logical-pixel card lands as a 1080-pixel image.
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return null;

      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/smartfinch-${widget.detail.day.dayKey}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      return file;
    } catch (error, stack) {
      debugPrint(
        '[DayShareScreen] could not render the day image: '
        '$error\n$stack',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.shareSheetFailed),
          ),
        );
      }
      return null;
    }
  }
}
