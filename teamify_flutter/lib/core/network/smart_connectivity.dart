import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum InternetStatus {
  online,
  offline,
  degraded,
  captivePortal,
}

class SmartConnectivity {
  final Connectivity _connectivity = Connectivity();
  InternetStatus _currentStatus = InternetStatus.offline;
  InternetStatus get status => _currentStatus;

  final _statusController = StreamController<InternetStatus>.broadcast();
  Stream<InternetStatus> get onStatusChanged => _statusController.stream;

  Timer? _pollingTimer;

  void init() {
    _connectivity.onConnectivityChanged.listen(_handleTransportChange);
    _checkInternetReachability();

    // Poll every 30s to detect captive portals or dropped connections on active wifi
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkInternetReachability();
    });
  }

  void dispose() {
    _pollingTimer?.cancel();
    _statusController.close();
  }

  void _handleTransportChange(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      _updateStatus(InternetStatus.offline);
    } else {
      // We have a transport, let's check actual internet reachability
      _checkInternetReachability();
    }
  }

  Future<void> _checkInternetReachability() async {
    try {
      final stopWatch = Stopwatch()..start();

      // Ping a reliable endpoint
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(
          Uri.parse('https://connectivitycheck.gstatic.com/generate_204'));
      final response = await request.close();

      stopWatch.stop();

      if (response.statusCode == 204) {
        if (stopWatch.elapsedMilliseconds > 2000) {
          _updateStatus(InternetStatus.degraded);
        } else {
          _updateStatus(InternetStatus.online);
        }
      } else if (response.statusCode == 200 || response.statusCode == 302) {
        // Many captive portals intercept the 204 and return 200 or redirect
        _updateStatus(InternetStatus.captivePortal);
      } else {
        _updateStatus(InternetStatus.offline);
      }
      client.close();
    } catch (e) {
      _updateStatus(InternetStatus.offline);
    }
  }

  void _updateStatus(InternetStatus newStatus) {
    if (_currentStatus != newStatus) {
      _currentStatus = newStatus;
      debugPrint('[SmartConnectivity] Status changed: $_currentStatus');
      _statusController.add(_currentStatus);
    }
  }
}
