import '../../core/network/api_client.dart';
import 'repository_helpers.dart';

class ChatRepository {
  final ApiClient _client;

  ChatRepository(this._client);

  /// GET /api/chat/rooms
  Future<List<Map<String, dynamic>>> listRooms() async {
    final response = await _client.get<dynamic>('/api/chat/rooms');
    return responseList(response.data, ['rooms', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// POST /api/chat/rooms
  /// Payload keys: name, type, project_id, members (list of user IDs)
  Future<Map<String, dynamic>> createRoom(Map<String, dynamic> payload) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms',
      data: payload,
    );
    final data = responseMap(response.data);
    final room = data['room'];
    if (room is Map) {
      return Map<String, dynamic>.from(room);
    }
    return data;
  }

  /// POST /api/chat/rooms/direct — find or create a 1:1 DM room
  Future<Map<String, dynamic>> openDirectRoom(String userId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms/direct',
      data: {'user_id': int.tryParse(userId) ?? userId},
    );
    final data = responseMap(response.data);
    final room = data['room'];
    if (room is Map) {
      return Map<String, dynamic>.from(room);
    }
    return data;
  }

  /// GET /api/chat/rooms/<roomId>
  Future<Map<String, dynamic>> getRoom(String roomId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId',
    );
    return responseMap(response.data);
  }

  /// GET /api/chat/rooms/<roomId>/messages
  Future<List<Map<String, dynamic>>> getMessages(
    String roomId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final response = await _client.get<dynamic>(
      '/api/chat/rooms/$roomId/messages',
      queryParameters: {'page': page, 'per_page': perPage},
    );
    return responseList(response.data, ['messages', 'data'])
        .cast<Map<String, dynamic>>();
  }

  /// POST /api/chat/rooms/<roomId>/messages
  /// Fallback REST endpoint for sending messages when WebSocket is down.
  /// Payload keys: content, idempotency_key
  Future<Map<String, dynamic>> sendMessage(
      String roomId, Map<String, dynamic> payload) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/messages',
      data: payload,
    );
    return responseMap(response.data);
  }

  /// DELETE /api/chat/rooms/<roomId>/messages/<messageId>
  Future<void> deleteMessage(String roomId, String messageId) async {
    await _client.delete<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/messages/$messageId',
    );
  }

  /// POST /api/chat/rooms/<roomId>/meetings/start
  Future<Map<String, dynamic>> startMeetingSession(String roomId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/meetings/start',
    );
    final data = responseMap(response.data);
    final session = data['session'];
    if (session is Map) {
      return Map<String, dynamic>.from(session);
    }
    return data;
  }

  /// POST /api/chat/rooms/<roomId>/meetings/<sessionId>/save — checkpoint (meeting stays live)
  Future<Map<String, dynamic>> saveMeetingCheckpoint(
    String roomId,
    String sessionId, {
    required List<Map<String, dynamic>> transcript,
    required List<String> participantIds,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/meetings/$sessionId/save',
      data: {
        'transcript': transcript,
        'participant_ids': participantIds,
      },
    );
    final data = responseMap(response.data);
    final session = data['session'];
    if (session is Map) {
      return Map<String, dynamic>.from(session);
    }
    return data;
  }

  /// POST /api/chat/rooms/<roomId>/meetings/<sessionId>/stop
  Future<Map<String, dynamic>> stopMeetingSession(
    String roomId,
    String sessionId, {
    required List<Map<String, dynamic>> transcript,
    required List<String> participantIds,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/meetings/$sessionId/stop',
      data: {
        'transcript': transcript,
        'participant_ids': participantIds,
      },
    );
    final data = responseMap(response.data);
    final session = data['session'];
    if (session is Map) {
      return Map<String, dynamic>.from(session);
    }
    return data;
  }

  /// GET /api/chat/rooms/<roomId>/meetings/<sessionId>
  Future<Map<String, dynamic>> getMeetingSession(
      String roomId, String sessionId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/chat/rooms/$roomId/meetings/$sessionId',
    );
    final data = responseMap(response.data);
    final session = data['session'];
    if (session is Map) {
      return Map<String, dynamic>.from(session);
    }
    return data;
  }

  /// GET /api/chat/meetings
  Future<List<Map<String, dynamic>>> listMeetings() async {
    final response = await _client.get<dynamic>('/api/chat/meetings');
    return responseList(response.data, ['meetings', 'data'])
        .cast<Map<String, dynamic>>();
  }
}
