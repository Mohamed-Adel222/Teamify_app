// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'meeting_web_continuous_speech_stub.dart';

/// Native Web Speech API with continuous=true and interimResults=true.
class MeetingWebContinuousSpeech {
  static bool get isApiAvailable => _speechRecognitionCtor() != null;

  JSObject? _recognition;
  bool _intentionalStop = false;
  bool _restartScheduled = false;
  DateTime? _lastRestartAt;
  WebSpeechResultHandler? _onResult;
  void Function(String message)? _onError;
  void Function(String status)? _onStatus;
  String _localeId = 'en-US';

  JSFunction? _onResultJs;
  JSFunction? _onErrorJs;
  JSFunction? _onEndJs;
  JSFunction? _onStartJs;
  JSFunction? _onSpeechStartJs;

  static const Duration _restartDebounce = Duration(milliseconds: 450);
  static const Duration _minRestartGap = Duration(milliseconds: 800);

  bool get isListening => _recognition != null && !_intentionalStop;

  Future<bool> start({
    required WebSpeechResultHandler onResult,
    void Function(String message)? onError,
    void Function(String status)? onStatus,
    String localeId = 'en-US',
  }) async {
    await stop();
    _onResult = onResult;
    _onError = onError;
    _onStatus = onStatus;
    _localeId = localeId;
    _intentionalStop = false;
    return _startEngine();
  }

  static JSObject get _window => web.window as JSObject;

  static JSObject? _speechRecognitionCtor() {
    final standard = _window.getProperty('SpeechRecognition'.toJS);
    if (standard != null) return standard as JSObject;
    final webkit = _window.getProperty('webkitSpeechRecognition'.toJS);
    return webkit as JSObject?;
  }

  bool _startEngine() {
    final ctor = _speechRecognitionCtor();
    if (ctor == null) return false;

    final created = (ctor as JSFunction).callAsConstructor<JSObject>();
    _recognition = created;
    final rec = created;

    rec.setProperty('continuous'.toJS, true.toJS);
    rec.setProperty('interimResults'.toJS, true.toJS);
    rec.setProperty('maxAlternatives'.toJS, 1.toJS);
    rec.setProperty('lang'.toJS, _localeId.toJS);

    _onResultJs = ((JSObject event) => _handleResult(event)).toJS;
    rec.setProperty('onresult'.toJS, _onResultJs);

    _onErrorJs = ((JSObject event) => _handleError(event)).toJS;
    rec.setProperty('onerror'.toJS, _onErrorJs);

    _onEndJs = ((JSObject _) => _handleEnd()).toJS;
    rec.setProperty('onend'.toJS, _onEndJs);

    _onStartJs = ((JSObject _) => _onStatus?.call('listening')).toJS;
    rec.setProperty('onstart'.toJS, _onStartJs);

    _onSpeechStartJs =
        ((JSObject _) => _onStatus?.call('speech_detected')).toJS;
    rec.setProperty('onspeechstart'.toJS, _onSpeechStartJs);

    try {
      rec.callMethod('start'.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleResult(JSObject event) {
    final handler = _onResult;
    if (handler == null) return;

    final results = event.getProperty('results'.toJS);
    if (results == null) return;
    final resultsObj = results as JSObject;

    final length = _jsInt(resultsObj.getProperty('length'.toJS));
    final resultIndex = _jsInt(event.getProperty('resultIndex'.toJS));

    var lastInterim = '';
    for (var i = resultIndex; i < length; i++) {
      final result = resultsObj.callMethod('item'.toJS, i.toJS) as JSObject?;
      if (result == null) continue;
      final transcript = _transcriptFromResult(result);
      if (transcript.isEmpty) continue;
      if (_isResultFinal(result)) {
        handler(transcript, true);
      } else {
        lastInterim = transcript;
      }
    }

    final interimTrim = lastInterim.trim();
    if (interimTrim.isNotEmpty) {
      handler(interimTrim, false);
      return;
    }

    if (length > 0) {
      final last =
          resultsObj.callMethod('item'.toJS, (length - 1).toJS) as JSObject?;
      if (last != null && !_isResultFinal(last)) {
        final tail = _transcriptFromResult(last);
        if (tail.isNotEmpty) handler(tail, false);
      }
    }
  }

  String _transcriptFromResult(JSObject result) {
    try {
      final alt = result.callMethod('item'.toJS, 0.toJS) as JSObject?;
      if (alt == null) return '';
      return _jsString(alt.getProperty('transcript'.toJS)) ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _isResultFinal(JSObject result) {
    final v = result.getProperty('isFinal'.toJS);
    if (v is JSBoolean) return v.toDart;
    return false;
  }

  void _handleError(JSObject event) {
    final err = _jsString(event.getProperty('error'.toJS));
    _onError?.call(err ?? 'speech_error');
    _onStatus?.call('error');
  }

  void _handleEnd() {
    if (_intentionalStop) return;
    _onStatus?.call('ended');
    _scheduleRestart();
  }

  void _scheduleRestart() {
    if (_intentionalStop || _onResult == null) return;
    if (_restartScheduled) return;

    final now = DateTime.now();
    var delay = _restartDebounce;
    if (_lastRestartAt != null) {
      final since = now.difference(_lastRestartAt!);
      if (since < _minRestartGap) {
        delay = _minRestartGap - since + _restartDebounce;
      }
    }

    _restartScheduled = true;
    _onStatus?.call('restarting');

    Future.delayed(delay, () {
      _restartScheduled = false;
      if (_intentionalStop || _onResult == null) return;
      _lastRestartAt = DateTime.now();
      try {
        final rec = _recognition;
        if (rec != null) {
          rec.callMethod('start'.toJS);
        } else {
          _startEngine();
        }
      } catch (_) {
        _startEngine();
      }
    });
  }

  Future<void> stop() async {
    _intentionalStop = true;
    _restartScheduled = false;
    final rec = _recognition;
    _recognition = null;
    _onResultJs = null;
    _onErrorJs = null;
    _onEndJs = null;
    _onStartJs = null;
    _onSpeechStartJs = null;
    if (rec != null) {
      try {
        rec.callMethod('stop'.toJS);
      } catch (_) {}
    }
    _onResult = null;
  }

  static int _jsInt(JSAny? value) {
    if (value == null) return 0;
    if (value is JSNumber) return value.toDartInt;
    return int.tryParse(value.toString()) ?? 0;
  }

  static String? _jsString(JSAny? value) {
    if (value == null) return null;
    if (value is JSString) return value.toDart;
    return value.toString();
  }
}
