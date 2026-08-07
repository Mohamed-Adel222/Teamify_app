import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'speech_blob_reader.dart'
    if (dart.library.html) 'speech_blob_reader_web.dart' as blob_reader;
import 'mic_permission_web.dart' if (dart.library.io) 'mic_permission_stub.dart'
    as mic_web;

/// Captures short microphone chunks for Whisper transcription during meetings.
class MeetingSpeechRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _intervalTimer;
  bool _busy = false;
  bool _enabled = false;

  bool get isEnabled => _enabled;

  /// Requests microphone access. On web calls [getUserMedia] directly so the
  /// browser permission prompt is guaranteed to appear (even on mobile Safari /
  /// Chrome for Android where hasPermission() may silently return false).
  Future<bool> ensurePermission() async {
    if (kIsWeb) {
      return mic_web.requestMicPermission();
    }
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Starts periodic capture. [onChunk] receives raw audio bytes and a filename.
  void start({
    Duration interval = const Duration(seconds: 8),
    Duration chunkDuration = const Duration(seconds: 5),
    required Future<void> Function(Uint8List bytes, String filename) onChunk,
    bool Function()? shouldCapture,
  }) {
    stop();
    _enabled = true;
    Future<void> tick() async {
      if (!_enabled) return;
      if (shouldCapture != null && !shouldCapture()) return;
      await _captureOnce(chunkDuration, onChunk);
    }

    // First chunk quickly so the user sees activity without waiting a full interval.
    tick();
    if (kIsWeb) {
      Future.delayed(const Duration(seconds: 3), tick);
    }
    _intervalTimer = Timer.periodic(interval, (_) => tick());
  }

  void stop() {
    _enabled = false;
    _intervalTimer?.cancel();
    _intervalTimer = null;
  }

  /// Captures one last chunk before the meeting stops (native/desktop).
  Future<void> flush(
    Future<void> Function(Uint8List bytes, String filename) onChunk, {
    Duration chunkDuration = const Duration(seconds: 4),
    bool Function()? shouldCapture,
  }) async {
    if (shouldCapture != null && !shouldCapture()) return;
    await _captureOnce(chunkDuration, onChunk);
  }

  Future<void> dispose() async {
    stop();
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _recorder.dispose();
  }

  /// Start a single voice note (chat). Call [stopVoiceNote] to finish.
  Future<bool> startVoiceNote() async {
    if (_busy || await _recorder.isRecording()) return false;

    // On web, permission was already confirmed by ensurePermission(); skip the
    // hasPermission() call (it may return false on iOS Safari even after the
    // user granted access during this session).
    if (!kIsWeb) {
      final hasMic = await _recorder.hasPermission();
      if (!hasMic) return false;
    }

    const config = RecordConfig(
      encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    );

    try {
      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(config, path: path);
      }
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Discard an in-progress voice note without transcribing.
  Future<void> cancelVoiceNote() async {
    if (!await _recorder.isRecording()) {
      _busy = false;
      return;
    }
    try {
      await _recorder.cancel();
    } catch (_) {
      try {
        await _recorder.stop();
      } catch (_) {}
    }
    _busy = false;
  }

  /// Stop voice note and return audio bytes for Whisper transcription.
  Future<({Uint8List bytes, String filename})?> stopVoiceNote() async {
    if (!await _recorder.isRecording()) return null;
    _busy = true;
    try {
      final path = await _recorder.stop();
      if (path == null || path.isEmpty) return null;
      final bytes = await blob_reader.readRecordingBytes(path);
      if (bytes.isEmpty) return null;
      const filename = kIsWeb ? 'voice_note.webm' : 'voice_note.wav';
      return (bytes: bytes, filename: filename);
    } catch (_) {
      return null;
    } finally {
      _busy = false;
    }
  }

  Future<void> _captureOnce(
    Duration chunkDuration,
    Future<void> Function(Uint8List bytes, String filename) onChunk,
  ) async {
    if (_busy || await _recorder.isRecording()) return;
    _busy = true;
    try {
      if (!kIsWeb) {
        final hasMic = await _recorder.hasPermission();
        if (!hasMic) return;
      }

      const config = RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      );

      String? recordPath;
      if (kIsWeb) {
        await _recorder.start(config, path: '');
      } else {
        final dir = await getTemporaryDirectory();
        recordPath =
            '${dir.path}/meeting_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(config, path: recordPath);
      }

      await Future.delayed(chunkDuration);
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? recordPath;
      if (path == null || path.isEmpty) return;

      final bytes = await blob_reader.readRecordingBytes(path);
      if (bytes.isEmpty) return;

      const filename = kIsWeb ? 'meeting_chunk.webm' : 'meeting_chunk.wav';
      await onChunk(bytes, filename);
    } catch (_) {
      // Mic unavailable or browser blocked — caller may show a one-time hint.
    } finally {
      _busy = false;
    }
  }
}
