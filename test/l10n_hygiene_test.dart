// =============================================================================
// Every string the app ships is a string the app shows
// =============================================================================
//
// The l10n files once carried 648 keys that no line of code read — Survey,
// Point Count, ARU, File Analysis, Session Review, the research export
// formats — in twelve languages each. Nothing broke while they were there,
// which is exactly how they piled up: an orphaned string is invisible until
// someone translates it, and then it is invisible *and* paid for.
//
// So the rule is enforced rather than hoped for. A key in the template has to
// be read somewhere in `lib/`, or be listed below with the reason it is being
// kept. Adding to the list is allowed; it just has to say why.
//
// Two more rules live here because they span all twelve languages: every
// language carries exactly the template's strings, and wherever a string names
// the spectrogram it also says what one is.
// =============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kept on purpose although nothing reads them yet.
const Map<String, String> _reserved = {
  // AUS-11, 🌧️ the bad-weather hero, sits behind the weather consent that
  // already exists. It will need the condition names and the snapshot labels.
  'weatherCodeClear': 'AUS-11',
  'weatherCodePartlyCloudy': 'AUS-11',
  'weatherCodeCloudy': 'AUS-11',
  'weatherCodeFog': 'AUS-11',
  'weatherCodeDrizzle': 'AUS-11',
  'weatherCodeRain': 'AUS-11',
  'weatherCodeSnow': 'AUS-11',
  'weatherCodeThunder': 'AUS-11',
  'weatherCodeUnknown': 'AUS-11',
  'sessionWeatherSection': 'AUS-11',
  'sessionWeatherAttribution': 'AUS-11 — Open-Meteo asks to be credited',
  'sessionWeatherCondition': 'AUS-11',
  'sessionWeatherTemperature': 'AUS-11',
  'sessionWeatherPrecipitation': 'AUS-11',
  'sessionWeatherWind': 'AUS-11',
  'sessionWeatherCloudCover': 'AUS-11',
  'sessionWeatherTapToLoad': 'AUS-11',
  // A denied microphone currently ends in a bare "Error" in live mode. These
  // are the words for doing better: say why, and offer the way to settings.
  'errorPermissionRequired': 'microphone denied — live mode',
  'errorMicrophoneRequired': 'microphone denied — live mode',
  'openSettings': 'microphone denied — live mode',
};

const List<String> _locales = [
  'en', 'de', 'cs', 'es', 'fr', 'it', 'nb', 'nl', 'pl', 'pt', 'ru', 'zh', //
];

/// The word for "spectrogram" in each language, and the explanation that has
/// to travel with it — in every grammatical case the sentences use.
const Map<String, (String, List<String>)> _spectrogramGloss = {
  'en': ('spectrogram', ['picture of sound']),
  'de': ('spektrogramm', ['bild vom klang', 'bildes vom klang']),
  'es': ('espectrograma', ['imagen del sonido']),
  'fr': ('spectrogramme', ['image du son']),
  'it': ('spettrogramma', ['immagine del suono']),
  'pt': ('espectrograma', ['imagem do som']),
  'nl': ('spectrogram', ['beeld van geluid']),
  'nb': ('spektrogram', ['bilde av lyden', 'bildet av lyden']),
  'pl': (
    'spektrogram',
    ['obraz dźwięku', 'obrazem dźwięku', 'obrazu dźwięku', 'obrazie dźwięku'],
  ),
  'cs': (
    'spektrogram',
    ['obraz zvuku', 'obrazem zvuku', 'obrazu zvuku', 'obraze zvuku'],
  ),
  'ru': (
    'спектрограмм',
    [
      'картинка звука',
      'картинку звука',
      'картинки звука',
      'картинкой звука',
      'картинке звука',
    ],
  ),
  'zh': ('声谱图', ['声音的图像']),
};

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

String _appSource() {
  final buffer = StringBuffer();
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    // The generated localizations mention every key; they are not a reader.
    if (path.startsWith('lib/l10n/')) continue;
    buffer.writeln(entity.readAsStringSync());
  }
  return buffer.toString();
}

void main() {
  final template = _arb('en');
  final keys = [
    for (final key in template.keys)
      if (!key.startsWith('@')) key,
  ];
  final source = _appSource();

  bool isRead(String key) =>
      RegExp(r'\.\s*' + RegExp.escape(key) + r'\b').hasMatch(source);

  test('every string in the template is read by the app', () {
    final orphans = [
      for (final key in keys)
        if (!isRead(key) && !_reserved.containsKey(key)) key,
    ];

    expect(
      orphans,
      isEmpty,
      reason:
          'Unused strings get translated into eleven languages for nothing. '
          'Delete them from every app_*.arb, or add them to _reserved with '
          'the reason they are being kept.',
    );
  });

  test('every language carries every string, and nothing else', () {
    // A string missing from one language falls back to English without a
    // word of warning in the app, and `flutter gen-l10n` only mentions it in
    // passing. Extra keys are the orphans of a deletion that forgot a file.
    final expected = keys.toSet();
    for (final locale in _locales) {
      if (locale == 'en') continue;
      final translated = {
        for (final key in _arb(locale).keys)
          if (!key.startsWith('@')) key,
      };
      expect(
        expected.difference(translated),
        isEmpty,
        reason: '$locale is missing strings the template has',
      );
      expect(
        translated.difference(expected),
        isEmpty,
        reason: '$locale has strings the template no longer has',
      );
    }
  });

  test('wherever the spectrogram is named, it is explained', () {
    // The word is worth learning, so it is used — but a child meets it on the
    // live screen, in the tips and in the help, and it never arrives alone.
    // The two tile titles are exempt: the section description under them
    // explains it.
    const exempt = {'settingsSpectrogram', 'settingsSpectrogramQuality'};
    for (final entry in _spectrogramGloss.entries) {
      final (word, glosses) = entry.value;
      final strings = _arb(entry.key);
      for (final key in strings.keys) {
        final value = strings[key];
        if (key.startsWith('@') || value is! String || exempt.contains(key)) {
          continue;
        }
        final text = value.toLowerCase();
        if (!text.contains(word)) continue;
        expect(
          glosses.any(text.contains),
          isTrue,
          reason:
              '${entry.key}: $key names the spectrogram without saying '
              'what it is',
        );
      }
    }
  });

  test('the reserved list does not outlive its reasons', () {
    // Once AUS-11 reads the weather strings, they stop being reservations and
    // the entry should go — otherwise the list becomes a second orphanage.
    final nowRead = [
      for (final key in _reserved.keys)
        if (isRead(key)) key,
    ];
    final gone = [
      for (final key in _reserved.keys)
        if (!template.containsKey(key)) key,
    ];

    expect(nowRead, isEmpty, reason: 'These are used now; unreserve them.');
    expect(gone, isEmpty, reason: 'These no longer exist; unreserve them.');
  });
}
