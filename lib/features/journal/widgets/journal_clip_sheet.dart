// =============================================================================
// JournalClipSheet — one kept recording, for a child (LOG-07, SET-12)
// =============================================================================
//
// Deliberately *not* the session-review clip player. That one grew for adults
// doing fieldwork: it shares the audio, exports Raven selection tables, edits
// notes, records voice memos and confirms detections. Every one of those is
// either gone with the research modes or, in the case of sharing audio,
// something Smartfinch decided against — `LOG-11` makes the rendered day image
// the app's only sharing path, and `KID-07` keeps free text off anyone else's
// screen.
//
// So this sheet does three things and stops: it draws the spectrogram, it
// plays the clip, and it lets a child keep the recording (`SET-12`).
//
// ### The keep switch is the one control that changes anything
//
// Retention deletes the oldest clips once a species is over its cap. A kept
// clip is exempt. That is the whole mechanism, and it belongs here rather than
// in a settings list, because the moment a child knows a recording is worth
// keeping is the moment they are listening to it.
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:smartfinch/l10n/app_localizations.dart';
import 'package:smartfinch/shared/utils/app_icons.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/providers/settings_providers.dart';
import '../../history/services/spectrogram_renderer.dart';
import '../../recording/audio_decoder.dart';
import '../../recording/native_audio_decoder.dart';
import '../../scoring/scoring_providers.dart';
import '../journal_models.dart';
import '../journal_providers.dart';

/// Open the player for one kept recording.
///
/// Does nothing when there is no clip, or the file is gone — retention is
/// allowed to have deleted it since the day was last opened.
Future<void> showJournalClipSheet(
  BuildContext context, {
  required JournalDetection detection,
  required String speciesName,
  required String dayKey,
}) async {
  final path = detection.clipPath;
  if (path == null || !File(path).existsSync()) return;
  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (_) => JournalClipSheet(
          detection: detection,
          speciesName: speciesName,
          dayKey: dayKey,
          clipPath: path,
        ),
  );
}

/// The sheet itself. Public so a widget test can pump it directly.
class JournalClipSheet extends ConsumerStatefulWidget {
  const JournalClipSheet({
    super.key,
    required this.detection,
    required this.speciesName,
    required this.dayKey,
    required this.clipPath,
  });

  final JournalDetection detection;
  final String speciesName;

  /// Invalidated after the keep switch, so the day reopens with it set.
  final String dayKey;

  final String clipPath;

  @override
  ConsumerState<JournalClipSheet> createState() => _JournalClipSheetState();
}

class _JournalClipSheetState extends ConsumerState<JournalClipSheet> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;

  ui.Image? _spectrogram;
  bool _drawing = true;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _length = Duration.zero;

  late bool _kept = widget.detection.isFavourite;

  @override
  void initState() {
    super.initState();
    unawaited(_draw());
    unawaited(_load());
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _spectrogram?.dispose();
    super.dispose();
  }

  Future<void> _draw() async {
    final colorMap = ref.read(colorMapProvider);
    try {
      final decoded =
          await AudioDecoder.canDecodeDart(widget.clipPath)
              ? await AudioDecoder.decodeFile(widget.clipPath)
              : await NativeAudioDecoder.decodeFile(widget.clipPath);

      // Off the UI thread: a clip is short, but the FFT is still a few
      // hundred milliseconds on a slow phone and this sheet animates in.
      final rendered = await Isolate.run(
        () => renderSpectrogram(
          decoded,
          targetSampleRate: AppConstants.sampleRate,
          fftSize: 1024,
          hop: 256,
          maxDisplayBins: 256,
          colorMapName: colorMap,
        ),
      );
      if (rendered == null) {
        if (mounted) setState(() => _drawing = false);
        return;
      }

      final image = await _toImage(rendered);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _spectrogram = image;
        _drawing = false;
      });
    } catch (error, stack) {
      debugPrint(
        '[JournalClipSheet] could not draw ${widget.clipPath}: '
        '$error\n$stack',
      );
      // The sheet still plays; a missing picture is not a missing recording.
      if (mounted) setState(() => _drawing = false);
    }
  }

  static Future<ui.Image> _toImage(SpectrogramPixels rendered) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rendered.pixels,
      rendered.width,
      rendered.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  Future<void> _load() async {
    try {
      final length = await _player.setFilePath(widget.clipPath);
      if (!mounted) return;
      setState(() => _length = length ?? Duration.zero);

      _positionSub = _player.positionStream.listen((at) {
        if (mounted) setState(() => _position = at);
      });
      _stateSub = _player.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _playing = state.playing);
        if (state.processingState == ProcessingState.completed) {
          _player
            ..pause()
            ..seek(Duration.zero);
        }
      });
    } catch (_) {
      // Nothing to do: the controls stay, and pressing play will fail
      // silently rather than crash a child's evening.
    }
  }

  Future<void> _toggleKept() async {
    final next = !_kept;
    setState(() => _kept = next);

    await ref
        .read(scoringRepositoryProvider)
        .setClipFavourite(detectionId: widget.detection.id, isFavourite: next);

    if (!mounted) return;
    ref.invalidate(journalDayProvider(widget.dayKey));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.speciesName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            _Spectrogram(
              image: _spectrogram,
              drawing: _drawing,
              progress:
                  _length.inMilliseconds == 0
                      ? 0
                      : _position.inMilliseconds / _length.inMilliseconds,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filled(
                  onPressed: () => _playing ? _player.pause() : _player.play(),
                  icon: Icon(
                    _playing
                        ? AppIcons.pauseRounded
                        : AppIcons.playArrowRounded,
                  ),
                  tooltip:
                      _playing ? l10n.journalClipPause : l10n.journalClipPlay,
                ),
                const SizedBox(width: 12),
                Text(
                  _clock(_position),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [ui.FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                // The one control that changes anything: a kept clip is
                // exempt from retention (SET-12).
                TextButton.icon(
                  onPressed: _toggleKept,
                  icon: Icon(
                    _kept ? AppIcons.bookmarkFilled : AppIcons.bookmark,
                    color: _kept ? theme.colorScheme.tertiary : null,
                  ),
                  label: Text(
                    _kept ? l10n.journalClipKept : l10n.journalClipKeep,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.journalClipKeepExplained,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clock(Duration at) {
    final seconds = at.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${at.inMinutes}:$seconds';
  }
}

/// The picture of the sound, with a line showing where playback has got to.
class _Spectrogram extends StatelessWidget {
  const _Spectrogram({
    required this.image,
    required this.drawing,
    required this.progress,
  });

  final ui.Image? image;
  final bool drawing;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 7,
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                RawImage(image: image, fit: BoxFit.fill)
              else if (drawing)
                const Center(child: CircularProgressIndicator())
              else
                // No picture, but the recording is still there to hear.
                Center(
                  child: Icon(
                    AppIcons.graphicEq,
                    size: 36,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (image != null && progress > 0)
                Align(
                  alignment: Alignment(progress.clamp(0.0, 1.0) * 2 - 1, 0),
                  child: Container(width: 2, color: theme.colorScheme.surface),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
