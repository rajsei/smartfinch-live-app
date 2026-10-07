// =============================================================================
// AnnouncementsTtsAdapter
// =============================================================================
//
// Thin abstraction over `flutter_tts` for the Announcements feature.
// The interface (`TtsEngine`) is small on purpose — the controller and
// tests should never reach into platform plugin details. Tests can
// inject a `FakeTtsEngine` (or Mocktail mock) without touching
// MethodChannels.
//
// Responsibilities:
//   - Initialize the platform engine for the user's voice locale,
//     rate, pitch, and (optionally) a specific installed voice.
//   - Speak an utterance and return a `Future<void>` that completes
//     when the platform reports speech end — with a hard timeout so a
//     misbehaving OEM engine can never wedge the announcement pipeline.
//   - Enumerate the voices installed for a language so the Settings UI
//     can let the user escape a bad default voice.
//
// Why the robustness work (this was the "flaky TTS" bug):
//   `flutter_tts.speak()` is fire-and-forget *unless* you call
//   `awaitSpeakCompletion(true)`. The previous version relied purely on
//   `setCompletionHandler` firing to resolve an internal completer.
//   Several Android OEM engines (Samsung TTS, some budget skins) fire
//   that callback unreliably or not at all — so the completer never
//   resolved, `speak()` hung forever, and the controller's `_speaking`
//   guard latched, silencing every later announcement for the rest of
//   the session. We now (a) opt into `awaitSpeakCompletion` so `speak()`
//   resolves on the same native completion signal the plugin uses, and
//   (b) wrap it in a duration-scaled timeout so even a totally silent
//   engine unblocks the pipeline.
//
// Language resolution: we no longer hand `setLanguage` a raw tag and
// hope. We probe `isLanguageAvailable` down a fallback chain
// (exact → language-only → en-US → en), producing a predictable fallback
// when the requested language is not installed.
//
// Routing (which output device speech goes to) is the
// `AnnouncementsRoutingService`'s job, not this adapter's — keeping
// concerns separable means we can unit-test rate/pitch/queueing in
// isolation from the Bluetooth-route mess.
//
// See `dev/announcements.md` §4 for engine choice, §7.1–7.2 for the
// missing-engine / missing-voice fallbacks, and §3.4–3.5 for
// throttling context.
// =============================================================================

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../shared/utils/app_haptics.dart';

/// A selectable platform voice. `name` is the engine-specific voice
/// identifier (what `setVoice` expects); `locale` is the BCP-47 tag the
/// voice speaks. Both come straight from `flutter_tts.getVoices`.
class TtsVoice {
  final String name;
  final String locale;
  const TtsVoice({required this.name, required this.locale});

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

/// Pure interface — what the rest of the Announcements code touches.
abstract class TtsEngine {
  /// Configure the platform voice for [languageTag] (BCP-47, e.g.
  /// `en-US`), [rate] (0.5–1.5, where 1.0 is the platform default
  /// "normal" pace), and [pitch] (0.7–1.3).
  ///
  /// [voiceName] optionally pins a specific installed voice (as returned
  /// by [FlutterTtsEngine.voicesForLanguage]); `null`/empty leaves the
  /// platform default voice for the resolved language.
  ///
  /// Safe to call repeatedly when the user changes settings.
  Future<void> configure({
    required String languageTag,
    required double rate,
    required double pitch,
    String? voiceName,
  });

  /// Speak [text] and complete when the platform signals speech end (or
  /// a safety timeout elapses — see the class header).
  ///
  /// If a previous utterance is still playing it is cancelled before
  /// the new one starts (never queued — stale calls have no value).
  Future<void> speak(String text);

  /// Play a short pre-roll cue before an utterance to give the listener
  /// a moment to switch attention. Fire-and-forget on failure — the cue
  /// is decorative and must never block speech.
  ///
  /// [haptic] allows the vibration some platforms add to the tone; false
  /// when the app's vibration switch is off (`SET-04`).
  Future<void> playPrerollCue({bool haptic = true});

  /// Cancel any in-flight utterance immediately.
  Future<void> stop();

  /// Release platform resources. Safe to call multiple times.
  Future<void> dispose();
}

/// Production [TtsEngine] backed by `flutter_tts`.
class FlutterTtsEngine implements TtsEngine {
  FlutterTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  /// Approx characters spoken per second at normal rate, used only to
  /// size the safety timeout on [speak]. Deliberately pessimistic (slow)
  /// so the guard band is generous.
  static const double _charsPerSecond = 11.0;

  bool _initialized = false;
  String? _requestedLanguage; // last tag asked for (before fallback)
  String? _appliedLanguage; // tag actually set on the engine
  double? _rate;
  double? _pitch;
  String? _appliedVoiceName; // null ⇒ platform default voice

  @override
  Future<void> configure({
    required String languageTag,
    required double rate,
    required double pitch,
    String? voiceName,
  }) async {
    await _ensureInitialized();

    if (_requestedLanguage != languageTag) {
      final resolved = await _resolveLanguage(languageTag);
      if (resolved != null && resolved != _appliedLanguage) {
        await _tts.setLanguage(resolved);
        _appliedLanguage = resolved;
        // Changing the language resets the engine to that language's
        // default voice, so any prior explicit pin no longer applies.
        _appliedVoiceName = null;
      }
      _requestedLanguage = languageTag;
    }

    if (_rate != rate) {
      // flutter_tts speech rates: Android 0.0–1.0 (0.5 = normal),
      // iOS 0.0–1.0 (0.5 = normal). Map our 0.5–1.5 range so 1.0 ≈
      // platform default (0.5 of plugin units).
      await _tts.setSpeechRate(rate * 0.5);
      _rate = rate;
    }
    if (_pitch != pitch) {
      await _tts.setPitch(pitch);
      _pitch = pitch;
    }

    await _applyVoice(voiceName);
  }

  @override
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _ensureInitialized();
    // Cancel anything still playing. The controller serialises calls, but
    // a stray in-flight utterance (e.g. a preview) must not overlap.
    try {
      await _tts.stop();
    } catch (_) {}

    // Hard ceiling: even if the engine never reports completion, the
    // pipeline must unblock. Scale by length so long Chatty sentences get
    // room, plus a fixed guard band for engine latency.
    // Account for the selected rate: at 0.5x the same sentence takes about
    // twice as long. Without this, slow voices could be cut off by the guard.
    final rateMultiplier = (_rate ?? 1.0).clamp(0.5, 1.5);
    final estMs =
        (text.length / (_charsPerSecond * rateMultiplier) * 1000).round();
    final guard = Duration(milliseconds: estMs + 6000);
    try {
      // `awaitSpeakCompletion(true)` (set in _ensureInitialized) makes
      // this future resolve when the platform finishes the utterance.
      await _tts.speak(text).timeout(guard);
    } on TimeoutException {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  @override
  Future<void> playPrerollCue({bool haptic = true}) async {
    try {
      // `alert` is a genuine tone on iOS; on much of Android it is a
      // no-op, so we also fire a light haptic as a fallback pre-cue.
      await SystemSound.play(SystemSoundType.alert);
      if (!kIsWeb && Platform.isAndroid) {
        await AppHaptics.selectionClickIf(haptic);
      }
      // Give the OS a brief moment to render the cue before speech starts
      // so it isn't talked over.
      await Future<void>.delayed(const Duration(milliseconds: 160));
    } catch (_) {
      // Cue is decorative — never let a platform hiccup block speech.
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
  }

  /// Voices installed for [languageTag] (matched on language subtag), for
  /// the Settings voice picker. Returns an empty list when the engine
  /// exposes no voices (some minimal Android engines) — the caller then
  /// shows a "manage voices in system settings" hint.
  Future<List<TtsVoice>> voicesForLanguage(String languageTag) async {
    final subtag = _subtag(languageTag);
    final raw = await _rawVoices();
    final seen = <String>{};
    final out = <TtsVoice>[];
    for (final v in raw) {
      final name = v['name'];
      final locale = v['locale'] ?? '';
      if (name == null || name.isEmpty) continue;
      if (subtag.isNotEmpty && _subtag(locale) != subtag) continue;
      if (!seen.add(name)) continue;
      out.add(TtsVoice(name: name, locale: locale));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Whether the platform has a usable TTS engine at all. Android can
  /// ship without one (or the user disabled it); iOS/web always do.
  /// A probe failure returns `true` so we never disable the feature on a
  /// transient plugin error.
  static Future<bool> isEngineAvailable({FlutterTts? tts}) async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final engine = await (tts ?? FlutterTts()).getDefaultEngine;
      return engine != null && engine.toString().isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  // --- internals -----------------------------------------------------------

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      // Make speak() resolve on the platform completion signal rather
      // than returning immediately. This is the crux of the flaky-TTS
      // fix — without it, our completion bookkeeping desyncs.
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    if (!kIsWeb && Platform.isIOS) {
      try {
        // Share the AVAudioSession `audio_session` configured so speech
        // plays through the resolved route without tearing down capture.
        await _tts.setSharedInstance(true);
      } catch (_) {}
    }
    // Keep the plugin's callbacks wired even though we drive completion
    // through the returned future + timeout; some plugin versions only
    // resolve the internal completer when a handler is registered.
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {});
    _initialized = true;
  }

  /// Probe [tag] and its fallbacks and return the first tag the engine
  /// reports as available, or `null` to leave the current language in
  /// place. The explicit English tail gives devices without the requested
  /// language a predictable last resort instead of relying on an OEM's
  /// undocumented fallback.
  Future<String?> _resolveLanguage(String tag) async {
    for (final candidate in _languageCandidates(tag)) {
      try {
        final available = await _tts.isLanguageAvailable(candidate);
        if (available == true) return candidate;
      } catch (_) {
        // isLanguageAvailable can throw on odd engines; keep probing.
      }
    }
    // Nothing probed clean. Still attempt the requested tag so the engine
    // gets a chance rather than being stuck on a stale language.
    final normalized = tag.replaceAll('_', '-').trim();
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _applyVoice(String? voiceName) async {
    final target = (voiceName == null || voiceName.isEmpty) ? null : voiceName;
    if (target == _appliedVoiceName) return;

    if (target == null) {
      // Revert to the platform default voice for the resolved language.
      final lang = _appliedLanguage;
      if (lang != null) {
        try {
          await _tts.setLanguage(lang);
        } catch (_) {}
      }
      _appliedVoiceName = null;
      return;
    }

    try {
      final raw = await _rawVoices();
      Map<String, String>? match;
      final languageSubtag = _subtag(_appliedLanguage ?? '');
      for (final v in raw) {
        final voiceSubtag = _subtag(v['locale'] ?? '');
        if (v['name'] == target &&
            (languageSubtag.isEmpty || voiceSubtag == languageSubtag)) {
          match = v;
          break;
        }
      }
      if (match != null) {
        await _tts.setVoice({
          'name': match['name']!,
          'locale': match['locale'] ?? _appliedLanguage ?? '',
        });
        _appliedVoiceName = target;
      } else {
        // A persisted voice may have been removed, or may belong to the
        // language used before the species-name locale changed. Reapply the
        // resolved language so an old explicit voice cannot remain active.
        final lang = _appliedLanguage;
        if (lang != null) await _tts.setLanguage(lang);
        _appliedVoiceName = null;
      }
    } catch (_) {}
  }

  Future<List<Map<String, String>>> _rawVoices() async {
    try {
      final dynamic list = await _tts.getVoices;
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            {
              for (final entry in e.entries)
                entry.key.toString(): entry.value.toString(),
            },
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Fallback chain for language resolution: exact tag, language-only,
  /// then English. Deduped, order preserved.
  static List<String> _languageCandidates(String tag) {
    final normalized = tag.replaceAll('_', '-').trim();
    final out = <String>[];
    void add(String s) {
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }

    add(normalized);
    final dash = normalized.indexOf('-');
    if (dash > 0) add(normalized.substring(0, dash));
    add('en-US');
    add('en');
    return out;
  }

  static String _subtag(String tag) {
    final normalized = tag.replaceAll('_', '-').trim().toLowerCase();
    if (normalized.isEmpty) return '';
    final dash = normalized.indexOf('-');
    return dash > 0 ? normalized.substring(0, dash) : normalized;
  }
}
