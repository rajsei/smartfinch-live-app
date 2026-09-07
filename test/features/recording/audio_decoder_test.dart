// =============================================================================
// Unit tests for DecodedAudio — resampleTo and readFloat32
// =============================================================================

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:smartfinch/features/recording/audio_decoder.dart';
import 'package:smartfinch/features/recording/flac_encoder.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // resampleTo
  // ═══════════════════════════════════════════════════════════════════════

  group('DecodedAudio.resampleTo', () {
    test('returns same instance when rate matches', () {
      final audio = DecodedAudio(
        samples: Int16List.fromList([100, 200, 300]),
        sampleRate: 32000,
      );
      final result = audio.resampleTo(32000);
      expect(identical(result, audio), isTrue);
    });

    test('downsamples 48 kHz → 32 kHz', () {
      // 48000 samples at 48 kHz = 1 second.
      // After resample to 32 kHz → 32000 samples.
      final samples = Int16List(48000);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = (i % 1000).toInt();
      }
      final audio = DecodedAudio(samples: samples, sampleRate: 48000);
      final resampled = audio.resampleTo(32000);

      expect(resampled.sampleRate, 32000);
      expect(resampled.totalSamples, 32000);
      // Duration should be preserved (1 second).
      expect(resampled.duration.inMilliseconds, 1000);
    });

    test('upsamples 16 kHz → 32 kHz', () {
      final samples = Int16List(16000);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = i;
      }
      final audio = DecodedAudio(samples: samples, sampleRate: 16000);
      final resampled = audio.resampleTo(32000);

      expect(resampled.sampleRate, 32000);
      expect(resampled.totalSamples, 32000);
      expect(resampled.duration.inMilliseconds, 1000);
    });

    test('linear interpolation is accurate for simple ramp', () {
      // 6 samples at rate 3 → resample to rate 2 → 4 samples.
      // Source: [0, 10000, 20000, 30000, 20000, 10000]
      // Ratio = 3/2 = 1.5, so:
      //   out[0] = src[0.0] = 0
      //   out[1] = src[1.5] = lerp(10000, 20000, 0.5) = 15000
      //   out[2] = src[3.0] = 30000
      //   out[3] = src[4.5] = lerp(20000, 10000, 0.5) = 15000
      final audio = DecodedAudio(
        samples: Int16List.fromList([0, 10000, 20000, 30000, 20000, 10000]),
        sampleRate: 3,
      );
      final resampled = audio.resampleTo(2);

      expect(resampled.sampleRate, 2);
      expect(resampled.totalSamples, 4);
      expect(resampled.samples[0], 0);
      expect(resampled.samples[1], 15000);
      expect(resampled.samples[2], 30000);
      expect(resampled.samples[3], 15000);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // readFloat32
  // ═══════════════════════════════════════════════════════════════════════

  group('DecodedAudio.readFloat32', () {
    test('normalizes Int16 to [-1.0, 1.0] range', () {
      final audio = DecodedAudio(
        samples: Int16List.fromList([0, 16384, -16384, 32767]),
        sampleRate: 1,
      );
      final floats = audio.readFloat32(0, 4);
      expect(floats[0], closeTo(0.0, 1e-6));
      expect(floats[1], closeTo(0.5, 0.001));
      expect(floats[2], closeTo(-0.5, 0.001));
      expect(floats[3], closeTo(1.0, 0.001));
    });

    test('zero-fills past end of samples', () {
      final audio = DecodedAudio(
        samples: Int16List.fromList([1000, 2000]),
        sampleRate: 1,
      );
      final floats = audio.readFloat32(0, 5);
      expect(floats.length, 5);
      expect(floats[2], 0.0);
      expect(floats[3], 0.0);
      expect(floats[4], 0.0);
    });
  });

  group('AudioDecoder WAV metadata and ranges', () {
    test('inspectFile reads metadata without full decode', () async {
      final dir = await Directory.systemTemp.createTemp('birdnet_audio_test_');
      try {
        final file = File('${dir.path}${Platform.pathSeparator}test.wav');
        await file.writeAsBytes(_buildPcm16Wav([100, 200, 300, 400]));

        final metadata = await AudioDecoder.inspectFile(file.path);

        expect(metadata.format, 'WAV');
        expect(metadata.sampleRate, 32000);
        expect(metadata.totalSamples, 4);
        expect(metadata.decodedPcmBytes, 8);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('decodeRange returns only the requested WAV samples', () async {
      final dir = await Directory.systemTemp.createTemp('birdnet_audio_test_');
      try {
        final file = File('${dir.path}${Platform.pathSeparator}test.wav');
        await file.writeAsBytes(_buildPcm16Wav([100, 200, 300, 400]));

        final decoded = await AudioDecoder.decodeRange(
          file.path,
          startSample: 1,
          count: 2,
        );

        expect(decoded.sampleRate, 32000);
        expect(decoded.samples, [200, 300]);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('AudioDecoder streaming FLAC ranges and windows', () {
    test(
      'match full decode without requiring callers to load FLAC bytes',
      () async {
        final dir = await Directory.systemTemp.createTemp('birdnet_flac_test_');
        try {
          final file = File('${dir.path}${Platform.pathSeparator}test.flac');
          final samples = Float32List(4096 * 4);
          for (var i = 0; i < samples.length; i++) {
            samples[i] = ((i % 257) - 128) / 256.0;
          }
          await FlacEncoder.writeFile(filePath: file.path, samples: samples);

          final full = await AudioDecoder.decodeFile(file.path);
          final ranged = await AudioDecoder.decodeRange(
            file.path,
            startSample: 1234,
            count: 4321,
          );

          expect(ranged.sampleRate, full.sampleRate);
          expect(ranged.samples, full.samples.sublist(1234, 1234 + 4321));

          final starts = <int>[];
          await AudioDecoder.decodeFlacWindows(
            file.path,
            windowSamples: 2048,
            stepSamples: 1024,
            maxWindows: 4,
            onWindow: (windowIndex, startSample, window) async {
              starts.add(startSample);
              expect(windowIndex, starts.length - 1);
              expect(window.sampleRate, full.sampleRate);
              expect(
                window.samples,
                full.samples.sublist(startSample, startSample + 2048),
              );
              return true;
            },
          );

          expect(starts, [0, 1024, 2048, 3072]);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  });
}

Uint8List _buildPcm16Wav(List<int> samples) {
  final dataSize = samples.length * 2;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 32000, Endian.little);
  data.setUint32(28, 32000 * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }

  return bytes;
}
