import 'dart:async';

import 'package:flutter/foundation.dart';

import 'meeting_background_transcriber.dart';
import 'meeting_browser_speech.dart';
import 'meeting_mic_keepalive.dart';
import 'meeting_web_chunk_recorder.dart';

/// Layer 1 — live browser captions. Layer 2 — Whisper refine (parallel, non-blocking).
enum MeetingSpeechPipelineMode {
  idle,
  liveBrowser,
  hybridBrowserWhisper,
  liveWhisperFallback,
}

typedef LiveSpeechHandler = void Function(String text, bool isFinal);
typedef WhisperRefineHandler = void Function(String text);
typedef BackgroundJobHandler = void Function(int pendingCount);

/// Orchestrates continuous meeting transcription.
class MeetingSpeechPipeline {
  MeetingSpeechPipeline();

  final MeetingBrowserSpeech _browser = MeetingBrowserSpeech();
  MeetingBackgroundTranscriber _background = MeetingBackgroundTranscriber();
  final MeetingWebChunkRecorder _webChunks = MeetingWebChunkRecorder();
  final MeetingWebChunkRecorder _whisperRefineRecorder =
      MeetingWebChunkRecorder();

  MeetingSpeechPipelineMode _mode = MeetingSpeechPipelineMode.idle;
  LiveSpeechHandler? _onLive;
  WhisperRefineHandler? _onWhisperRefine;
  void Function(String message)? _onError;
  void Function(String status)? _onStatus;
  BackgroundJobHandler? _onBackgroundJobsChanged;
  bool Function()? _shouldRun;

  Future<String?> Function(Uint8List bytes, String filename)? _transcribe;

  MeetingSpeechPipelineMode get mode => _mode;
  bool get isLiveActive =>
      _mode == MeetingSpeechPipelineMode.liveBrowser ||
      _mode == MeetingSpeechPipelineMode.hybridBrowserWhisper ||
      _mode == MeetingSpeechPipelineMode.liveWhisperFallback;

  bool get isBrowserLive =>
      _mode == MeetingSpeechPipelineMode.liveBrowser ||
      _mode == MeetingSpeechPipelineMode.hybridBrowserWhisper;

  int get backgroundJobCount => _background.pendingCount;

  Future<bool> start({
    required LiveSpeechHandler onLiveText,
    required Future<String?> Function(Uint8List bytes, String filename)
        transcribeFallback,
    void Function(String message)? onError,
    void Function(String status)? onStatus,
    BackgroundJobHandler? onBackgroundJobsChanged,
    WhisperRefineHandler? onWhisperRefine,
    bool Function()? shouldRun,
  }) async {
    await shutdown();
    _onLive = onLiveText;
    _onWhisperRefine = onWhisperRefine;
    _onError = onError;
    _onStatus = onStatus;
    _onBackgroundJobsChanged = onBackgroundJobsChanged;
    _shouldRun = shouldRun;
    _transcribe = transcribeFallback;
    _background = MeetingBackgroundTranscriber();

    final browserOk = await _browser.initialize(
      onError: _onError,
      onStatus: (status) {
        _onStatus?.call(status);
        if (status == 'done' || status == 'notListening') {
          _restartBrowserIfNeeded();
        }
      },
    );

    if (browserOk) {
      final listening = await _browser.startListening(_handleBrowserResult);
      if (listening) {
        _mode = MeetingSpeechPipelineMode.liveBrowser;

        // Layer 2 (web): low-rate Whisper slices refine transcript without blocking Layer 1.
        if (kIsWeb && _onWhisperRefine != null) {
          unawaited(_startWhisperRefineParallel());
        }
        return true;
      }
    }

    if (kIsWeb) {
      await MeetingMicKeepAlive.acquire();
      final chunkOk = await _webChunks.start(
        onChunk: (bytes, name) async {
          _enqueueWhisperChunk(bytes, name, refine: false);
        },
        timesliceMs: 12000,
      );
      if (chunkOk) {
        _mode = MeetingSpeechPipelineMode.liveWhisperFallback;
        return true;
      }
      MeetingMicKeepAlive.release();
    }

    _mode = MeetingSpeechPipelineMode.idle;
    return false;
  }

  Future<void> _startWhisperRefineParallel() async {
    // Delay so browser SpeechRecognition claims the mic first.
    await Future.delayed(const Duration(seconds: 2));
    if (!isBrowserLive || _shouldRun?.call() == false) return;

    final ok = await _whisperRefineRecorder.start(
      onChunk: (bytes, name) async {
        _enqueueWhisperChunk(bytes, name, refine: true);
      },
      timesliceMs: 18000,
      useKeepAlive: false,
    );
    if (ok && isBrowserLive) {
      _mode = MeetingSpeechPipelineMode.hybridBrowserWhisper;
    }
  }

  void _handleBrowserResult(String text, bool isFinal) {
    if (_shouldRun != null && !_shouldRun!()) return;
    _onLive?.call(text, isFinal);
  }

  Future<void> _restartBrowserIfNeeded() async {
    if (!isBrowserLive) return;
    if (_shouldRun != null && !_shouldRun!()) return;
    if (_browser.isListening) return;
    _onStatus?.call('restarting');
    await _browser.resumeListening();
  }

  void _enqueueWhisperChunk(
    Uint8List bytes,
    String filename, {
    required bool refine,
  }) {
    if (_shouldRun != null && !_shouldRun!()) return;
    final transcribe = _transcribe;
    if (transcribe == null) return;

    _notifyBackgroundJobs();
    _background.enqueue(
      bytes: bytes,
      filename: filename,
      transcribe: transcribe,
      onText: (text) {
        if (refine) {
          _onStatus?.call('whisper_refining');
          _onWhisperRefine?.call(text);
        } else {
          _onLive?.call(text, true);
        }
        _notifyBackgroundJobs();
      },
      onQueueEmpty: _notifyBackgroundJobs,
    );
  }

  void _notifyBackgroundJobs() {
    _onBackgroundJobsChanged?.call(_background.pendingCount);
  }

  Future<void> commitPartial(LiveSpeechHandler? handler) async {
    final h = handler ?? _onLive;
    if (h == null) return;
    _onStatus?.call('finalizing_phrase');
    if (isBrowserLive) {
      await _browser.commitPartial(h);
    } else if (_mode == MeetingSpeechPipelineMode.liveWhisperFallback) {
      await _webChunks.flushFinal((bytes, name) async {
        _enqueueWhisperChunk(bytes, name, refine: false);
      });
    }
  }

  Future<void> drainBackground() => _background.drain();

  Future<void> shutdown() async {
    if (isBrowserLive) {
      await _browser.stop(null);
    }

    _webChunks.stop();
    _whisperRefineRecorder.stop();
    await _background.drain();
    _background.dispose();

    if (kIsWeb) {
      MeetingMicKeepAlive.release();
    }

    _mode = MeetingSpeechPipelineMode.idle;
    _onLive = null;
    _onWhisperRefine = null;
    _onError = null;
    _onStatus = null;
    _shouldRun = null;
    _transcribe = null;
    _notifyBackgroundJobs();
  }

  void dispose() {
    unawaited(shutdown());
  }
}
