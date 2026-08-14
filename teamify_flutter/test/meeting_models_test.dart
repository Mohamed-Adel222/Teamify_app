import 'package:flutter_test/flutter_test.dart';
import 'package:teamify/core/config/app_config.dart';
import 'package:teamify/core/notifications/notification_actions.dart';
import 'package:teamify/data/models/api_meeting.dart';
import 'package:teamify/data/models/api_misc.dart';

void main() {
  test('ApiMeeting.fromJson maps public id and host', () {
    final meeting = ApiMeeting.fromJson({
      'id': 9,
      'public_id': '11111111-1111-4111-8111-111111111111',
      'title': 'Standup',
      'status': 'live',
      'host_user_id': 3,
      'host_name': 'Host User',
      'project_id': 12,
      'project_name': 'Teamify',
      'chat_room_id': 44,
      'provider': 'livekit',
      'participant_count': 2,
      'participants': [
        {'id': 1, 'user_id': 3, 'display_name': 'Host User', 'role': 'host'},
      ],
    });
    expect(meeting.publicId, '11111111-1111-4111-8111-111111111111');
    expect(meeting.isLive, isTrue);
    expect(meeting.hostName, 'Host User');
    expect(meeting.chatRoomId, '44');
    expect(meeting.participants, hasLength(1));
    expect(meeting.videoAvailable, isTrue);
  });

  test('ApiMeeting.fromJson reads video_available false', () {
    final meeting = ApiMeeting.fromJson({
      'id': 9,
      'public_id': '11111111-1111-4111-8111-111111111111',
      'title': 'Standup',
      'status': 'live',
      'host_user_id': 3,
      'chat_room_id': 44,
      'video_available': false,
    });
    expect(meeting.videoAvailable, isFalse);
  });

  test('MeetingJoinToken.fromJson reads nested data and url', () {
    final token = MeetingJoinToken.fromJson({
      'data': {
        'url': 'https://example.livekit.cloud/',
        'token': 'abc',
        'identity': '3',
        'room': 'teamify_room',
        'configured': true,
      },
    });
    expect(token.token, 'abc');
    expect(token.url, 'https://example.livekit.cloud/');
    expect(token.configured, isTrue);
  });

  test('meeting public id is parsed from notification body', () {
    const n = ApiNotification(
      id: '1',
      title: 'Ahmed invited you to a meeting',
      body: 'Ahmed started "Standup". meeting:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      type: 'meeting_invite',
      entityType: 'Meeting',
      entityId: '9',
    );
    expect(
      meetingPublicIdFromNotification(n),
      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
    );
  });

  test('AppConfig normalizes LiveKit https URLs to wss', () {
    expect(
      AppConfig.normalizeLiveKitUrl('https://example.livekit.cloud/'),
      'wss://example.livekit.cloud',
    );
    expect(
      AppConfig.resolveLiveKitUrl(''),
      AppConfig.normalizeLiveKitUrl(AppConfig.livekitUrl),
    );
  });
}
