import 'package:smartfinch/features/announcements/platform/tts_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';

class _FakeFlutterTts extends FlutterTts {
  final List<String> languagesSet = [];
  final List<Map<String, String>> voicesSet = [];
  List<dynamic> voices = [];
  Set<String> availableLanguages = {};
  double? speechRate;
  double? pitch;

  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => 1;

  @override
  Future<dynamic> isLanguageAvailable(String language) async =>
      availableLanguages.contains(language);

  @override
  Future<dynamic> setLanguage(String language) async {
    languagesSet.add(language);
    return 1;
  }

  @override
  Future<dynamic> setSpeechRate(double rate) async {
    speechRate = rate;
    return 1;
  }

  @override
  Future<dynamic> setPitch(double value) async {
    pitch = value;
    return 1;
  }

  @override
  Future<dynamic> setVoice(Map<String, String> voice) async {
    voicesSet.add(voice);
    return 1;
  }

  @override
  Future<dynamic> get getVoices async => voices;

  @override
  Future<dynamic> stop() async => 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('configure resolves language and maps rate and pitch', () async {
    final tts = _FakeFlutterTts()..availableLanguages = {'de'};
    final engine = FlutterTtsEngine(tts: tts);

    await engine.configure(languageTag: 'de-DE', rate: 1.2, pitch: 0.9);

    expect(tts.languagesSet, ['de']);
    expect(tts.speechRate, closeTo(0.6, 0.0001));
    expect(tts.pitch, 0.9);
  });

  test(
    'configure only applies a pinned voice for the resolved language',
    () async {
      final tts =
          _FakeFlutterTts()
            ..availableLanguages = {'de'}
            ..voices = [
              {'name': 'Shared name', 'locale': 'en-US'},
              {'name': 'German voice', 'locale': 'de-DE'},
            ];
      final engine = FlutterTtsEngine(tts: tts);

      await engine.configure(
        languageTag: 'de-DE',
        rate: 1,
        pitch: 1,
        voiceName: 'Shared name',
      );
      expect(tts.voicesSet, isEmpty);
      expect(tts.languagesSet, ['de', 'de']);

      await engine.configure(
        languageTag: 'de-DE',
        rate: 1,
        pitch: 1,
        voiceName: 'German voice',
      );
      expect(tts.voicesSet.single, {'name': 'German voice', 'locale': 'de-DE'});
    },
  );

  test('voicesForLanguage filters and sorts installed voices', () async {
    final tts =
        _FakeFlutterTts()
          ..voices = [
            {'name': 'Zulu', 'locale': 'de-DE'},
            {'name': 'English', 'locale': 'en-US'},
            {'name': 'alpha', 'locale': 'de-AT'},
          ];
    final engine = FlutterTtsEngine(tts: tts);

    final voices = await engine.voicesForLanguage('de');

    expect(voices, const [
      TtsVoice(name: 'alpha', locale: 'de-AT'),
      TtsVoice(name: 'Zulu', locale: 'de-DE'),
    ]);
  });
}
