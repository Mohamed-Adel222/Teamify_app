import '../core/cache/cache_manager.dart';
import '../core/cache/swr_helper.dart';
import '../core/network/api_result.dart';
import '../core/network/request_deduplicator.dart';
import '../core/network/service_error_handler.dart';
import '../core/offline/offline_manager.dart';
import '../core/offline/mutation_id.dart';
import '../core/offline/offline_mutation.dart';
import '../data/repositories/chat_repository.dart';

/// Cached/deduplicated chat reads. Messages can be sent over WebSocket
/// or via REST POST when offline / WebSocket unavailable.
///
/// SWR cache TTLs:
///   Chat rooms list — 2 minutes
class ChatService with ServiceErrorHandler {
  final ChatRepository _repo;
  final OfflineManager _offlineManager;
  final CacheManager _cache;

  static const _box = 'chat';
  static const _roomsTtl = Duration(minutes: 2);

  ChatService(this._repo, this._offlineManager, this._cache) {
    _swr = SwrHelper(_cache);
  }

  final RequestDeduplicator _dedup = RequestDeduplicator();
  late final SwrHelper _swr;

  Future<ApiResult<List<Map<String, dynamic>>>> listRooms({
    bool forceRefresh = false,
    void Function(List<Map<String, dynamic>>)? onRefreshed,
  }) =>
      _dedup.deduplicate(
          'chat_list_rooms',
          () => guard(() async {
                if (forceRefresh) {
                  final rooms = await _repo.listRooms();
                  await _cache.putList(_box, 'rooms',
                      rooms.map((r) => Map<String, dynamic>.from(r)).toList());
                  return rooms;
                }
                return _swr
                    .withSwrList<Map<String, dynamic>>(
                      boxName: _box,
                      key: 'rooms',
                      fetcher: () => _repo.listRooms(),
                      fromJson: (j) => j,
                      toJson: (r) => r,
                      staleAge: _roomsTtl,
                      onRefreshed: onRefreshed,
                    )
                    .then((res) =>
                        res.isSuccess ? res.data! : throw Exception(res.error));
              }));

  Future<void> invalidateRooms() => _cache.invalidateBox(_box);

  Future<ApiResult<Map<String, dynamic>>> createRoom(
          Map<String, dynamic> payload) =>
      guard(() async {
        final room = await _repo.createRoom(payload);
        await invalidateRooms();
        return room;
      });

  Future<ApiResult<Map<String, dynamic>>> getRoom(String roomId) =>
      _dedup.deduplicate(
        'chat_room_$roomId',
        () => guard(() => _repo.getRoom(roomId)),
      );

  Future<ApiResult<List<Map<String, dynamic>>>> getMessages(
    String roomId, {
    int page = 1,
    int perPage = 50,
  }) =>
      _dedup.deduplicate(
        'chat_msgs_${roomId}_${page}_$perPage',
        () => guard(
            () => _repo.getMessages(roomId, page: page, perPage: perPage)),
      );

  Future<ApiResult<Map<String, dynamic>>> startMeetingSession(String roomId) =>
      guard(() => _repo.startMeetingSession(roomId));

  Future<ApiResult<Map<String, dynamic>>> saveMeetingCheckpoint(
    String roomId,
    String sessionId, {
    required List<Map<String, dynamic>> transcript,
    required List<String> participantIds,
  }) =>
      guard(() => _repo.saveMeetingCheckpoint(
            roomId,
            sessionId,
            transcript: transcript,
            participantIds: participantIds,
          ));

  Future<ApiResult<Map<String, dynamic>>> stopMeetingSession(
    String roomId,
    String sessionId, {
    required List<Map<String, dynamic>> transcript,
    required List<String> participantIds,
  }) =>
      guard(() => _repo.stopMeetingSession(
            roomId,
            sessionId,
            transcript: transcript,
            participantIds: participantIds,
          ));

  Future<ApiResult<Map<String, dynamic>>> getMeetingSession(
          String roomId, String sessionId) =>
      guard(() => _repo.getMeetingSession(roomId, sessionId));

  Future<ApiResult<Map<String, dynamic>>> sendMessage(
      String roomId, Map<String, dynamic> payload) {
    final mutationPayload = Map<String, dynamic>.from(payload);
    if (!mutationPayload.containsKey('idempotency_key')) {
      mutationPayload['idempotency_key'] = MutationId.generate();
    }

    return guardWithOffline(
      () => _repo.sendMessage(roomId, mutationPayload),
      mutation: OfflineMutation(
        id: MutationId.generate(),
        method: 'POST',
        path: '/api/chat/rooms/$roomId/messages',
        data: mutationPayload,
        tag: 'sendMessage',
      ),
      offlineManager: _offlineManager,
    );
  }

  Future<ApiResult<void>> deleteMessage(String roomId, String messageId) =>
      guard(() => _repo.deleteMessage(roomId, messageId));
}
