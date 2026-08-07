import 'dart:async';

import 'package:flutter/foundation.dart';

/// Layer 2: Whisper/API transcription queue — never blocks the live mic pipeline.
class MeetingBackgroundTranscriber {
  final List<_Job> _queue = [];
  bool _draining = false;
  int _inFlight = 0;

  int get pendingCount => _queue.length + _inFlight;

  void enqueue({
    required Uint8List bytes,
    required String filename,
    required Future<String?> Function(Uint8List bytes, String filename)
        transcribe,
    required void Function(String text) onText,
    VoidCallback? onQueueEmpty,
  }) {
    _queue.add(_Job(bytes, filename, transcribe, onText, onQueueEmpty));
    unawaited(_drain());
  }

  /// Wait until all queued transcription jobs finish (used when ending meeting).
  Future<void> drain() async {
    for (var i = 0; i < 600; i++) {
      await _drain();
      if (_queue.isEmpty && _inFlight == 0) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('MeetingBackgroundTranscriber: drain timed out');
  }

  void dispose() {
    _queue.clear();
    _draining = false;
    _inFlight = 0;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _inFlight++;
      try {
        final text = await job.transcribe(job.bytes, job.filename);
        final trimmed = text?.trim() ?? '';
        if (trimmed.isNotEmpty) {
          job.onText(trimmed);
        }
      } catch (e) {
        debugPrint('MeetingBackgroundTranscriber: $e');
      } finally {
        _inFlight--;
        job.onQueueEmpty?.call();
      }
    }
    _draining = false;
  }
}

class _Job {
  _Job(
    this.bytes,
    this.filename,
    this.transcribe,
    this.onText,
    this.onQueueEmpty,
  );

  final Uint8List bytes;
  final String filename;
  final Future<String?> Function(Uint8List bytes, String filename) transcribe;
  final void Function(String text) onText;
  final VoidCallback? onQueueEmpty;
}
