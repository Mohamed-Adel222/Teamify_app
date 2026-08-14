import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../config/app_config.dart';
import '../storage/token_storage.dart';
import '../observability/app_logger.dart';

/// Event types emitted by the WebSocket manager.
enum SocketEvent {
  connected,
  disconnected,
  connectError,
  error,
  chatMessage,
  messageDeleted,
  meetingPresence,
  notification,
  taskUpdate,
  projectUpdate,
  error,
}

/// Payload delivered with every [SocketEvent].
class SocketPayload {
  final SocketEvent event;
  final Map<String, dynamic> data;

  const SocketPayload({required this.event, this.data = const {}});
}

/// Centralized WebSocket manager with auto-reconnect and event streaming.
///
/// Design decisions
/// ----------------
/// * Transport: WebSocket preferred; long-polling fallback when the proxy or
///   worker cannot upgrade (e.g. during a misconfigured gunicorn deploy).
///
/// * No manual ping/pong: Socket.IO's engine.io layer already does heartbeats
///   (ping_interval=25s, ping_timeout=60s on the server).  Sending a custom
///   `ping` event on top of that is redundant and can confuse reconnect timing.
///
/// * Fresh token on reconnect: Rather than mutating socket options (which is
///   unreliable in socket_io_client v3), we dispose the old socket and create
///   a new one with the fresh token.  This guarantees the auth handshake
///   always uses a valid JWT.
///
/// * Reconnect cap + exponential backoff: Caps at [_maxReconnects] attempts
///   with [_baseDelay] × 2^attempt ms delay, preventing infinite loops when
///   the server is genuinely down or the token is permanently invalid.
///
/// Usage:
/// ```dart
/// final ws = WebSocketManager(tokenStorage);
/// ws.stream.listen((payload) { ... });
/// await ws.connect();
/// ws.joinRoom('42');
/// ws.sendMessage('42', 'Hello!');
/// await ws.dispose();
/// ```
class WebSocketManager {
  final TokenStorage _tokenStorage;

  io.Socket? _socket;
  bool _disposed = false;
  bool _isConnecting = false;

  int _reconnectAttempts = 0;
  static const int _maxReconnects = 8;
  static const Duration _baseDelay = Duration(milliseconds: 1000);

  Timer? _reconnectTimer;
  Completer<bool>? _connectCompleter;

  final _controller = StreamController<SocketPayload>.broadcast();

  /// Stream of all incoming events.
  Stream<SocketPayload> get stream => _controller.stream;

  /// Whether the socket is currently connected.
  bool get isConnected => _socket?.connected ?? false;

  WebSocketManager(this._tokenStorage);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Establish a Socket.IO connection authenticated via JWT.
  ///
  /// Safe to call multiple times — returns immediately if already connecting
  /// or connected. Waits up to [timeout] for the handshake to complete.
  Future<bool> connect({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_disposed) return false;
    if (AppConfig.isDemoMode) {
      debugPrint('[WS] Demo mode active — aborting connect');
      return false;
    }
    if (isConnected) return true;
    if (_isConnecting && _connectCompleter != null) {
      try {
        return await _connectCompleter!.future.timeout(timeout);
      } catch (_) {
        return isConnected;
      }
    }

    _isConnecting = true;
    final completer = Completer<bool>();
    _connectCompleter = completer;

    try {
      final token = await _tokenStorage.readAccessToken();
      if (token == null || token.isEmpty) {
        debugPrint('[WS] No access token — aborting connect');
        if (!completer.isCompleted) completer.complete(false);
        return false;
      }

      // Dispose stale socket before creating a new one.
      _destroySocket();

      _socket = io.io(
        AppConfig.socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            // Pass JWT in both the auth dict (preferred by Socket.IO v4)
            // and extra headers (fallback for some proxy configurations).
            .setAuth({'token': token})
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            // Disable socket_io_client's built-in reconnection so WE control
            // the retry loop with fresh tokens each time.
            .disableAutoConnect()
            .disableReconnection()
            .build(),
      );

      _attachHandlers();
      _socket!.connect();

      try {
        return await completer.future.timeout(timeout);
      } on TimeoutException {
        debugPrint('[WS] Connect timed out after ${timeout.inSeconds}s');
        return isConnected;
      }
    } finally {
      _isConnecting = false;
      _connectCompleter = null;
    }
  }

  /// Join a chat room.
  void joinRoom(String roomId) {
    if (!isConnected) return;
    _socket?.emit('join_chat', {'room_id': int.tryParse(roomId) ?? roomId});
  }

  /// Leave a chat room.
  void leaveRoom(String roomId) {
    if (!isConnected) return;
    _socket?.emit('leave_chat', {'room_id': int.tryParse(roomId) ?? roomId});
  }

  /// Join live meeting presence for a chat room.
  void joinMeeting(String roomId) {
    if (!isConnected) return;
    final id = int.tryParse(roomId);
    if (id == null) return;
    _socket?.emit('join_meeting', {'room_id': id});
  }

  /// Leave live meeting presence.
  void leaveMeeting(String roomId) {
    if (!isConnected) return;
    final id = int.tryParse(roomId);
    if (id == null) return;
    _socket?.emit('leave_meeting', {'room_id': id});
  }

  /// Send a chat message to a room (fire-and-forget). Prefer [sendChatPayloadWithAck].
  void sendMessage(String roomId, String content) {
    sendChatPayload(roomId, {'content': content, 'message_type': 'text'});
  }

  /// Text, image, or file message (see backend chat_message_service).
  void sendChatPayload(String roomId, Map<String, dynamic> payload) {
    if (!isConnected) return;
    _socket?.emit('send_message', {
      'room_id': int.tryParse(roomId) ?? roomId,
      ...payload,
    });
  }

  /// Send a chat payload and wait for the server acknowledgement.
  ///
  /// Returns the ack map (`{ok, message}` or `{ok: false, error}`) or `null`
  /// when the socket is down or the ack times out. Socket connectivity alone
  /// is not treated as delivery — callers must inspect the ack or use REST.
  Future<Map<String, dynamic>?> sendChatPayloadWithAck(
    String roomId,
    Map<String, dynamic> payload, {
    Duration timeout = AppConfig.messageAckTimeout,
  }) async {
    final socket = _socket;
    if (socket == null || !socket.connected) return null;
    final completer = Completer<Map<String, dynamic>?>();
    try {
      socket.emitWithAck(
        'send_message',
        {
          'room_id': int.tryParse(roomId) ?? roomId,
          ...payload,
        },
        ack: (dynamic data) {
          if (completer.isCompleted) return;
          completer.complete(_asMap(data));
        },
      );
    } catch (e, st) {
      AppLogger.error('[WS] send_message emit failed', e, st);
      return null;
    }
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      AppLogger.log('[WS] send_message ack timed out for room $roomId');
      return null;
    }
  }

  /// Disconnect cleanly (preserves the ability to reconnect later).
  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _destroySocket();
  }

  /// Permanently dispose — no reconnect possible after this.
  Future<void> dispose() async {
    _disposed = true;
    disconnect();
    await _controller.close();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  void _attachHandlers() {
    final socket = _socket!;

    socket.onConnect((_) {
      _reconnectAttempts = 0;
      debugPrint('[WS] ✓ Connected');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete(true);
      }
      _emit(SocketEvent.connected);
    });

    socket.onDisconnect((reason) {
      debugPrint('[WS] ✗ Disconnected — reason: $reason');
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete(false);
      }
      _emit(SocketEvent.disconnected, {'reason': reason?.toString() ?? ''});

      // Only auto-reconnect for recoverable disconnect reasons.
      // 'io server disconnect' means the server explicitly kicked us
      // (e.g. bad JWT) — do not loop.
      final shouldRetry = reason != 'io server disconnect';
      if (shouldRetry && !_disposed) {
        _scheduleReconnect();
      }
    });

    socket.onConnectError((err) {
      debugPrint('[WS] Connection error: $err');
      AppLogger.error('[WS] connect_error', err);
      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete(false);
      }
      _emit(SocketEvent.connectError, {'message': err?.toString() ?? 'connect_error'});
      if (!_disposed) _scheduleReconnect();
    });

    socket.onError((err) {
      debugPrint('[WS] Socket error: $err');
      AppLogger.error('[WS] error', err);
      _emit(SocketEvent.error, {'message': err?.toString() ?? 'socket error'});
    });

    socket.on('error', (data) {
      final map = _asMap(data);
      final message = map['message']?.toString() ??
          map['error']?.toString() ??
          'Chat error';
      AppLogger.error('[WS] server error: $message');
      _emit(SocketEvent.error, {
        ...map,
        'message': message,
      });
    });

    // ── Chat events ──────────────────────────────────────────────────────
    socket.on('receive_message', (data) {
      _emit(SocketEvent.chatMessage, _asMap(data));
    });

    // Legacy event name support
    socket.on('new_message', (data) {
      _emit(SocketEvent.chatMessage, _asMap(data));
    });

    socket.on('message', (data) {
      _emit(SocketEvent.chatMessage, _asMap(data));
    });

    socket.on('message_deleted', (data) {
      _emit(SocketEvent.messageDeleted, _asMap(data));
    });

    socket.on('error', (data) {
      _emit(SocketEvent.error, _asMap(data));
    });

    socket.on('meeting_presence', (data) {
      _emit(SocketEvent.meetingPresence, _asMap(data));
    });

    // ── Notification events ──────────────────────────────────────────────
    // Backend emits 'new_notification' from create_notification() helper.
    socket.on('new_notification', (data) {
      _emit(SocketEvent.notification, _asMap(data));
    });
    // Legacy alias
    socket.on('notification', (data) {
      _emit(SocketEvent.notification, _asMap(data));
    });

    // ── Task events ──────────────────────────────────────────────────────
    socket.on('task_update', (data) {
      _emit(SocketEvent.taskUpdate, _asMap(data));
    });

    socket.on('task_status_changed', (data) {
      _emit(SocketEvent.taskUpdate, _asMap(data));
    });

    // ── Project events ────────────────────────────────────────────────
    socket.on('project_member_added', (data) {
      _emit(SocketEvent.projectUpdate, _asMap(data));
    });

    socket.on('project_member_removed', (data) {
      _emit(SocketEvent.projectUpdate, _asMap(data));
    });
  }

  void _destroySocket() {
    try {
      // socket_io_client v3: off() requires an event name.
      // Unregister every event we attached in _attachHandlers() so that
      // no listener closure can fire after the socket is gone.
      for (final event in const [
        'connect',
        'disconnect',
        'connect_error',
        'error',
        'receive_message',
        'new_message',
        'message',
        'message_deleted',
        'meeting_presence',
        'new_notification',
        'notification',
        'task_update',
        'task_status_changed',
        'project_member_added',
        'project_member_removed',
      ]) {
        _socket?.off(event);
      }
      _socket?.disconnect();
      _socket?.dispose(); // releases remaining internal references
    } catch (_) {
      // Best-effort cleanup — ignore errors on a dead socket
    }
    _socket = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectAttempts >= _maxReconnects) {
      debugPrint(
          '[WS] Max reconnect attempts ($_maxReconnects) reached — giving up');
      AppLogger.log(
          '[WebSocket] Reconnect loop terminated after $_maxReconnects attempts');
      _emit(SocketEvent.disconnected, {'reason': 'reconnect_exhausted'});
      return;
    }

    // Exponential backoff capped at 30 s
    final delayMs =
        (_baseDelay.inMilliseconds * (1 << _reconnectAttempts)).clamp(
      _baseDelay.inMilliseconds,
      30000,
    );
    _reconnectAttempts++;
    debugPrint('[WS] Reconnect attempt $_reconnectAttempts in ${delayMs}ms');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_disposed) return;
      // Always fetch a fresh token — the old one might have expired while
      // we were offline, causing the server to reject and immediately
      // disconnect us → triggering another reconnect loop.
      await connect();
    });
  }

  void _emit(SocketEvent event, [Map<String, dynamic> data = const {}]) {
    if (!_controller.isClosed) {
      _controller.add(SocketPayload(event: event, data: data));
    }
  }

  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }
}
