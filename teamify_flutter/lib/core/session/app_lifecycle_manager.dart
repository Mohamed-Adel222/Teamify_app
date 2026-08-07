import 'package:flutter/material.dart';
import '../network/websocket_manager.dart';
import '../offline/offline_manager.dart';
import '../observability/app_logger.dart';

class AppLifecycleManager with WidgetsBindingObserver {
  final WebSocketManager wsManager;
  final OfflineManager offlineManager;

  bool _isBackground = false;

  AppLifecycleManager({
    required this.wsManager,
    required this.offlineManager,
  });

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    AppLogger.log('AppLifecycleState changed to: $state');

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _onBackground();
        break;
      case AppLifecycleState.resumed:
        _onForeground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  void _onBackground() {
    if (_isBackground) return;
    _isBackground = true;
    AppLogger.log('App entering background. Suspending heavy tasks.');

    // Suspend WebSocket but don't clear session
    if (wsManager.isConnected) {
      wsManager.disconnect();
    }

    offlineManager.pauseReplay();
  }

  void _onForeground() {
    if (!_isBackground) return;
    _isBackground = false;
    AppLogger.log('App entering foreground. Resuming tasks.');

    // Resume WebSocket
    wsManager.connect();

    // Resume Offline Manager
    offlineManager.resumeReplay();
  }
}
