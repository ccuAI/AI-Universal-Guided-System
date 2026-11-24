import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';

class TaigiTtsService {
  final AudioPlayer _player = AudioPlayer();

  static const String baseUrl =
      'http://127.0.0.1:8000';

  final Map<String, Uint8List> _cache = {};

  int _session = 0;
  Completer<void>? _playbackDone;

  // 依照標點符號切割文章
  List<String> splitText(String text) {
    final sentences = text
        .split(RegExp(r'(?<=[。！？；\n])'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    final parts = <String>[];

    for (final sentence in sentences) {
      final chars = sentence.runes.toList();

      for (int i = 0; i < chars.length; i += 100) {
        final end = i + 100 < chars.length
            ? i + 100
            : chars.length;

        parts.add(
          String.fromCharCodes(chars.sublist(i, end)),
        );
      }
    }

    return parts;
  }

  // 取得語音，優先使用快取
  Future<Uint8List> _fetchAudio(String text) async {
    if (_cache.containsKey(text)) {
      return _cache[text]!;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/tts'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'text': text}),
    ).timeout(const Duration(minutes: 3));

    if (response.statusCode != 200) {
      throw Exception(
        '語音生成失敗：${response.statusCode}',
      );
    }

    // 限制快取數量
    if (_cache.length >= 30) {
      _cache.remove(_cache.keys.first);
    }

    _cache[text] = response.bodyBytes;

    return response.bodyBytes;
  }

  // 播放並等待音訊結束
  Future<void> _playAudio(Uint8List audio) async {
    final done = Completer<void>();
    _playbackDone = done;

    final subscription =
        _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) {
        done.complete();
      }
    });

    try {
      await _player.play(
        BytesSource(audio, mimeType: 'audio/wav'),
      );

      await done.future;
    } finally {
      await subscription.cancel();

      if (identical(_playbackDone, done)) {
        _playbackDone = null;
      }
    }
  }

  // 預載下一段語音
  Future<void> speak(String text) async {
    await stop();

    final session = _session;
    final parts = splitText(text);

    if (parts.isEmpty) return;

    Uint8List currentAudio =
        await _fetchAudio(parts.first);

    for (int i = 0; i < parts.length; i++) {
      if (session != _session) return;

      Uint8List? nextAudio;

      await Future.wait<void>([
        _playAudio(currentAudio),

        if (i + 1 < parts.length)
          _fetchAudio(parts[i + 1]).then((audio) {
            nextAudio = audio;
          }),
      ]);

      if (session != _session) return;

      if (nextAudio != null) {
        currentAudio = nextAudio!;
      }
    }
  }

  Future<void> stop() async {
    _session++;

    final done = _playbackDone;

    if (done != null && !done.isCompleted) {
      done.complete();
    }

    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    _cache.clear();
    await _player.dispose();
  }
}