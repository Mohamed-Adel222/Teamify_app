import '../core/network/api_result.dart';
import '../core/network/service_error_handler.dart';
import '../data/models/api_meeting.dart';
import '../data/repositories/meeting_repository.dart';

class MeetingService with ServiceErrorHandler {
  final MeetingRepository _repo;

  MeetingService(this._repo);

  Future<ApiResult<List<ApiMeeting>>> listMeetings() =>
      guard(_repo.listMeetings);

  Future<ApiResult<ApiMeeting>> createMeeting({
    required int chatRoomId,
    int? projectId,
    String? title,
  }) =>
      guard(() => _repo.createMeeting(
            chatRoomId: chatRoomId,
            projectId: projectId,
            title: title,
          ));

  Future<ApiResult<ApiMeeting>> getMeeting(String publicId) =>
      guard(() => _repo.getMeeting(publicId));

  Future<ApiResult<MeetingJoinToken>> issueToken(String publicId) =>
      guard(() => _repo.issueToken(publicId));

  Future<ApiResult<ApiMeeting>> leave(String publicId) =>
      guard(() => _repo.leave(publicId));

  Future<ApiResult<ApiMeeting>> end(String publicId) =>
      guard(() => _repo.end(publicId));
}
