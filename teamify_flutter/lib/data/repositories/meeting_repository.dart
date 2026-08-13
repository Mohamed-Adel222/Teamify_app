import '../../core/network/api_client.dart';
import '../models/api_meeting.dart';
import 'repository_helpers.dart';

class MeetingRepository {
  final ApiClient _client;

  MeetingRepository(this._client);

  /// GET /api/meetings
  Future<List<ApiMeeting>> listMeetings() async {
    final response = await _client.get<dynamic>('/api/meetings');
    final rows = responseList(response.data, ['meetings', 'data']);
    return rows
        .whereType<Map>()
        .map((row) => ApiMeeting.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// POST /api/meetings
  Future<ApiMeeting> createMeeting({
    required int chatRoomId,
    int? projectId,
    String? title,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/meetings',
      data: {
        'chat_room_id': chatRoomId,
        if (projectId != null) 'project_id': projectId,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      },
    );
    return _meetingFrom(response.data);
  }

  /// GET /api/meetings/<publicId>
  Future<ApiMeeting> getMeeting(String publicId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/api/meetings/$publicId',
    );
    return _meetingFrom(response.data);
  }

  /// POST /api/meetings/<publicId>/token
  Future<MeetingJoinToken> issueToken(String publicId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/meetings/$publicId/token',
    );
    final data = responseMap(response.data);
    return MeetingJoinToken.fromJson(data);
  }

  /// POST /api/meetings/<publicId>/leave
  Future<ApiMeeting> leave(String publicId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/meetings/$publicId/leave',
    );
    return _meetingFrom(response.data);
  }

  /// POST /api/meetings/<publicId>/end
  Future<ApiMeeting> end(String publicId) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/api/meetings/$publicId/end',
    );
    return _meetingFrom(response.data);
  }

  ApiMeeting _meetingFrom(Map<String, dynamic>? raw) {
    final data = responseMap(raw);
    final meeting = data['meeting'];
    if (meeting is Map) {
      return ApiMeeting.fromJson(Map<String, dynamic>.from(meeting));
    }
    return ApiMeeting.fromJson(data);
  }
}
