import 'api_helpers.dart';

class ApiMeetingParticipant {
  final String id;
  final String userId;
  final String displayName;
  final String role;
  final String inviteStatus;

  const ApiMeetingParticipant({
    required this.id,
    required this.userId,
    this.displayName = '',
    this.role = 'participant',
    this.inviteStatus = 'invited',
  });

  factory ApiMeetingParticipant.fromJson(Map<String, dynamic> json) {
    return ApiMeetingParticipant(
      id: asString(json['id']),
      userId: asString(json['user_id']),
      displayName: asString(json['display_name']),
      role: asString(json['role'], 'participant'),
      inviteStatus: asString(json['invite_status'], 'invited'),
    );
  }
}

class ApiMeeting {
  final String id;
  final String publicId;
  final String title;
  final String status;
  final String hostUserId;
  final String hostName;
  final String? projectId;
  final String? projectName;
  final String chatRoomId;
  final String provider;
  final String providerRoom;
  final String? startsAt;
  final String? endedAt;
  final String? createdAt;
  final int participantCount;
  final List<ApiMeetingParticipant> participants;
  final Map<String, dynamic>? session;

  const ApiMeeting({
    required this.id,
    required this.publicId,
    required this.title,
    required this.status,
    required this.hostUserId,
    this.hostName = '',
    this.projectId,
    this.projectName,
    required this.chatRoomId,
    this.provider = 'livekit',
    this.providerRoom = '',
    this.startsAt,
    this.endedAt,
    this.createdAt,
    this.participantCount = 0,
    this.participants = const [],
    this.session,
  });

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended' || status == 'cancelled';
  bool get isScheduled => status == 'scheduled';

  factory ApiMeeting.fromJson(Map<String, dynamic> json) {
    final participantsRaw = json['participants'];
    final participants = <ApiMeetingParticipant>[];
    if (participantsRaw is List) {
      for (final row in participantsRaw) {
        if (row is Map) {
          participants.add(
            ApiMeetingParticipant.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    final sessionRaw = json['session'];
    return ApiMeeting(
      id: asString(json['id']),
      publicId: asString(json['public_id'] ?? json['publicId']),
      title: asString(json['title'], 'Team meeting'),
      status: asString(json['status'], 'live'),
      hostUserId: asString(json['host_user_id']),
      hostName: asString(json['host_name']),
      projectId: _optionalId(json['project_id']),
      projectName: _optionalString(json['project_name']),
      chatRoomId: asString(json['chat_room_id']),
      provider: asString(json['provider'], 'livekit'),
      providerRoom: asString(json['provider_room']),
      startsAt: _optionalString(json['starts_at']),
      endedAt: _optionalString(json['ended_at']),
      createdAt: _optionalString(json['created_at']),
      participantCount: asInt(json['participant_count']) > 0
          ? asInt(json['participant_count'])
          : participants.length,
      participants: participants,
      session: sessionRaw is Map
          ? Map<String, dynamic>.from(sessionRaw)
          : null,
    );
  }

  static String? _optionalId(dynamic value) {
    final s = asString(value);
    return s.isEmpty ? null : s;
  }

  static String? _optionalString(dynamic value) {
    final s = asString(value);
    return s.isEmpty ? null : s;
  }
}

class MeetingJoinToken {
  final String url;
  final String token;
  final String identity;
  final String room;
  final int ttlSeconds;
  final ApiMeeting? meeting;

  const MeetingJoinToken({
    required this.url,
    required this.token,
    required this.identity,
    required this.room,
    this.ttlSeconds = 7200,
    this.meeting,
  });

  factory MeetingJoinToken.fromJson(Map<String, dynamic> json) {
    final meetingRaw = json['meeting'];
    return MeetingJoinToken(
      url: asString(json['url']),
      token: asString(json['token']),
      identity: asString(json['identity']),
      room: asString(json['room']),
      ttlSeconds: asInt(json['ttl_seconds'], 7200),
      meeting: meetingRaw is Map
          ? ApiMeeting.fromJson(Map<String, dynamic>.from(meetingRaw))
          : null,
    );
  }
}
