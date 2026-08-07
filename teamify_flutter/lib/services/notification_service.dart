import 'dart:async';

import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/network/websocket_manager.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_mutation.dart';
import '../data/models/models.dart';
import '../data/models/notification_preferences_model.dart';
import '../data/repositories/notification_repository.dart';
import 'home_service.dart';

class NotificationService with ServiceErrorHandler {
  final NotificationRepository _repo;
  final CacheManager _cache;
  final WebSocketManager? _ws;
  final OfflineManager _offline;
  HomeService? _home;

  static const _box = 'notifications';

  NotificationService(
    this._repo,
    this._cache, {
    WebSocketManager? ws,
    required OfflineManager offline,
  })  : _ws = ws,
        _offline = offline {
    _swr = SwrHelper(_cache);
    _subscribeToWebSocket();
  }

  void linkHomeService(HomeService home) => _home = home;

  Future<void> _syncUnreadBadge() async {
    await _cache.invalidateBox(_box);
    await _home?.invalidateAllDashboards();
    final countResult = await getUnreadCount();
    if (countResult.isSuccess && countResult.data != null) {
      _unreadCountController.add(countResult.data!);
    }
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;

  StreamSubscription<SocketPayload>? _wsSub;

  // Exposed so UI can observe unread badge updates pushed via WebSocket.
  final _unreadCountController = StreamController<int>.broadcast();
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  // ---------------------------------------------------------------------------
  // WebSocket listener
  // ---------------------------------------------------------------------------

  void _subscribeToWebSocket() {
    if (_ws == null) return;
    _wsSub = _ws!.stream.listen((payload) {
      if (payload.event == SocketEvent.notification) {
        // Invalidate the list cache so the next listNotifications() returns fresh data
        _cache.invalidateBox(_box);
        // Push the updated unread count to any subscribed badge widgets
        final count = payload.data['unread_count'];
        if (count is int) {
          _unreadCountController.add(count);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Service methods
  // ---------------------------------------------------------------------------

  Future<ApiResult<List<ApiNotification>>> listNotifications({
    bool forceRefresh = false,
    void Function(List<ApiNotification>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'list_notifications',
          () => guard(() async {
                if (forceRefresh) {
                  final list = await _repo.listNotifications();
                  await _cache.putList(
                      _box, 'all', list.map((n) => n.toJson()).toList());
                  return list;
                }

                return _swr
                    .withSwrList<ApiNotification>(
                      boxName: _box,
                      key: 'all',
                      fetcher: () => _repo.listNotifications(),
                      fromJson: ApiNotification.fromJson,
                      toJson: (n) => n.toJson(),
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  Future<ApiResult<int>> getUnreadCount() => _dedup.deduplicate(
      'notif_unread', () => guard(() => _repo.getUnreadCount()));

  Future<ApiResult<void>> markRead(String id) => guardWithOffline(
        () async {
          await _repo.markRead(id);
          await _syncUnreadBadge();
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'PATCH',
          path: '/api/notifications/$id/read',
          data: const {},
          tag: 'markRead',
        ),
        offlineManager: _offline,
      );

  Future<ApiResult<void>> markAllRead() => guardWithOffline(
        () async {
          await _repo.markAllAsRead();
          _unreadCountController.add(0);
          await _syncUnreadBadge();
        },
        mutation: OfflineMutation(
          id: MutationId.generate(),
          method: 'POST',
          path: '/api/notifications/mark-all-read',
          data: const {},
          tag: 'markAllRead',
        ),
        offlineManager: _offline,
      );

  /// Server-side email preferences. Falls back to the Hive cache when the
  /// request fails so the settings screen still works offline.
  Future<ApiResult<NotificationPreferences>> getPreferences() =>
      guard(() async {
        final json = await _repo.getPreferences();
        final prefs = NotificationPreferences.fromJson(json);
        await prefs.save();
        return prefs;
      });

  Future<ApiResult<NotificationPreferences>> savePreferences(
          NotificationPreferences prefs) =>
      guard(() async {
        final json = await _repo.updatePreferences(prefs.toJson());
        final saved = NotificationPreferences.fromJson(json);
        await saved.save();
        return saved;
      });

  void dispose() {
    _wsSub?.cancel();
    _unreadCountController.close();
  }
}
