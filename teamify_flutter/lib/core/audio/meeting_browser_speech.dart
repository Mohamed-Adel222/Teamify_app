import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'meeting_web_continuous_speech.dart' show MeetingWebContinuousSpeech;

/// Layer 1 live STT — Web Speech API (continuous) on web; speech_to_text elsewhere.
class MeetingBrowserSpeech {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final MeetingWebContinuousSpeech _webContinuous =
      MeetingWebContinuousSpeech();

  bool _available = false;
  bool _useWebContinuous = false;
  String _lastPartial = '';
  void Function(String text, bool isFinal)? _onResult;
  void Function(String message)? _onError;
  void Function(String status)? _onStatus;
  bool _restartScheduled = false;

  bool get isAvailable => _available;
  bool get isListening =>
      _useWebContinuous ? _webContinuous.isListening : _speech.isListening;

  Future<bool> initialize({
    void Function(String message)? onError,
    void Function(String status)? onStatus,
  }) async {
    _onError = onError;
    _onStatus = onStatus;

    if (kIsWeb) {
      if (MeetingWebContinuousSpeech.isApiAvailable) {
        _available = true;
        _useWebContinuous = true;
        return true;
      }
      // Chrome without native ctor — fall back to speech_to_text plugin on web.
      _useWebContinuous = false;
      _available = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          debugPrint('MeetingBrowserSpeech error: ${error.errorMsg}');
          _onError?.call(error.errorMsg);
        },
        onStatus: (status) {
          debugPrint('MeetingBrowserSpeech status: $status');
          _onStatus?.call(status);
          _maybeScheduleRestart(status);
        },
      );
      return _available;
    }

    _useWebContinuous = false;
    _available = await _speech.initialize(
      onError: (SpeechRecognitionError error) {
        debugPrint('MeetingBrowserSpeech error: ${error.errorMsg}');
        _onError?.call(error.errorMsg);
      },
      onStatus: (status) {
        debugPrint('MeetingBrowserSpeech status: $status');
        _onStatus?.call(status);
        _maybeScheduleRestart(status);
      },
    );
    return _available;
  }

  void _maybeScheduleRestart(String status) {
    if (_useWebContinuous) return;
    if (_onResult == null) return;
    if (status != 'done' && status != 'notListening') return;
    if (_restartScheduled || _speech.isListening == true) return;
    _restartScheduled = true;
    Future.delayed(const Duration(milliseconds: 450), () async {
      _restartScheduled = false;
      if (_onResult == null || _speech.isListening == true) return;
      _onStatus?.call('restarting');
      await resumeListening();
    });
  }

  Future<bool> resumeListening() async {
    final onResult = _onResult;
    if (!_available || onResult == null) return false;

    if (_useWebContinuous) {
      return _webContinuous.start(
        onResult: onResult,
        onError: _onError,
        onStatus: _onStatus,
      );
    }

    if (_speech.isListening == true) return true;
    return _listenInternal(onResult);
  }

  Future<bool> startListening(
    void Function(String text, bool isFinal) onResult, {
    String? localeId,
  }) async {
    if (!_available) return false;
    _onResult = onResult;
    _lastPartial = '';
    final locale = localeId ?? 'en-US';

    if (_useWebContinuous) {
      return _webContinuous.start(
        onResult: (text, isFinal) {
          if (isFinal) {
            _lastPartial = '';
          } else {
            _lastPartial = text;
          }
          onResult(text, isFinal);
        },
        onError: _onError,
        onStatus: _onStatus,
        localeId: locale,
      );
    }

    if (_speech.isListening == true) {
      await _speech.stop();
      await Future.delayed(const Duration(milliseconds: 40));
    }

    return _listenInternal(onResult, localeId: locale);
  }

  Future<bool> _listenInternal(
    void Function(String text, bool isFinal) onResult, {
    String? localeId,
  }) async {
    final started = await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        final words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        if (result.finalResult) {
          onResult(words, true);
          _lastPartial = '';
        } else {
          _lastPartial = words;
          onResult(words, false);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: localeId ?? 'en-US',
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        pauseFor: const Duration(seconds: 60),
        listenFor: const Duration(hours: 2),
      ),
    );

    if (started != true) return false;
    await Future.delayed(const Duration(milliseconds: 300));
    if (_speech.isListening == true) return true;
    await Future.delayed(const Duration(milliseconds: 500));
    return (_speech.isListening == true) || started == true;
  }

  Future<void> commitPartial(
    void Function(String text, bool isFinal) onResult,
  ) async {
    if (_lastPartial.isNotEmpty) {
      onResult(_lastPartial, true);
      _lastPartial = '';
    }
  }

  Future<void> stop(void Function(String text, bool isFinal)? onResult) async {
    if (_lastPartial.isNotEmpty && onResult != null) {
      onResult(_lastPartial, true);
      _lastPartial = '';
    }
    if (_useWebContinuous) {
      await _webContinuous.stop();
    } else if (_speech.isListening == true) {
      await _speech.stop();
    }
    _onResult = null;
  }
}
