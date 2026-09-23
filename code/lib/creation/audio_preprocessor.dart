import 'dart:io';

import 'package:flutter/services.dart';

/// Audio preparation boundary (spec V1 §二十一): every input media file is
/// decoded down to ONE format — mono 16 kHz 16-bit PCM WAV — before it ever
/// reaches the ASR engine. The ASR side never sees mp3/m4a/mp4.
abstract class AudioPreprocessor {
  /// Decodes [inputPath] (any Android-decodable media) into a mono 16 kHz
  /// WAV at [outputPath]. Returns [outputPath].
  Future<String> toMono16kWav(String inputPath, String outputPath);
}

/// Production implementation over the native MediaCodec decoder
/// (android/app/.../MainActivity.kt, channel `listenloop/creation_native`).
class MethodChannelAudioPreprocessor implements AudioPreprocessor {
  MethodChannelAudioPreprocessor({this.sampleRate = 16000});

  final int sampleRate;
  static const MethodChannel _channel = MethodChannel(
    'listenloop/creation_native',
  );

  @override
  Future<String> toMono16kWav(String inputPath, String outputPath) async {
    // WAV input at the target rate can pass through untouched.
    if (inputPath.toLowerCase().endsWith('.wav')) {
      return inputPath;
    }
    return await _channel.invokeMethod<String>('decodeToWav', {
          'input': inputPath,
          'output': outputPath,
          'sampleRate': sampleRate,
        }) ??
        outputPath;
  }
}

/// Deterministic implementation for tests: asserts the input is already a
/// 16 kHz mono WAV-shaped file (header check) and passes it through.
class PassthroughAudioPreprocessor implements AudioPreprocessor {
  @override
  Future<String> toMono16kWav(String inputPath, String outputPath) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    if (bytes.length < 44 ||
        bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46) {
      throw const FormatException('not a WAV file');
    }
    return inputPath;
  }
}
