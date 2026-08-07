import 'dart:async';
import 'package:flutter/foundation.dart';

import 'session_controller.dart';

abstract class Disposable {
  void dispose();
}

/// Global registry for automatically disposing listeners, timers,
/// and streams upon user logout or app termination.
class DisposableRegistry {
  final List<dynamic> _disposables = [];

  void register(dynamic item) {
    if (item is StreamSubscription ||
        item is Timer ||
        item is Disposable ||
        item is ChangeNotifier) {
      _disposables.add(item);
    } else {
      debugPrint(
          '[DisposableRegistry] Warning: Tried to register unsupported type: ${item.runtimeType}');
    }
  }

  void disposeAll() {
    for (final item in _disposables) {
      try {
        if (item is StreamSubscription) {
          item.cancel();
        } else if (item is Timer) {
          item.cancel();
        } else if (item is Disposable) {
          item.dispose();
        } else if (item is ChangeNotifier) {
          if (item is SessionController) continue;
          item.dispose();
        }
      } catch (e) {
        debugPrint(
            '[DisposableRegistry] Error disposing ${item.runtimeType}: $e');
      }
    }
    _disposables.clear();
    debugPrint('[DisposableRegistry] All resources disposed.');
  }
}

// Global instance for convenience
final globalDisposableRegistry = DisposableRegistry();
