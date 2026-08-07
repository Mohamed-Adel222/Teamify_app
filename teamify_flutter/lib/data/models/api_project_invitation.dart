import 'api_helpers.dart';

class ApiProjectInvitation {
  final String id;
  final String projectId;
  final String inviteeId;
  final String inviteeName;
  final String inviteeEmail;
  final String inviteeDisplayName;
  final List<String> inviteeSkills;
  final String inviterId;
  final String inviterName;
  final String status;
  final String createdAt;
  final String respondedAt;

  const ApiProjectInvitation({
    required this.id,
    required this.projectId,
    required this.inviteeId,
    this.inviteeName = '',
    this.inviteeEmail = '',
    this.inviteeDisplayName = '',
    this.inviteeSkills = const [],
    this.inviterId = '',
    this.inviterName = '',
    required this.status,
    this.createdAt = '',
    this.respondedAt = '',
  });

  String get displayName {
    if (inviteeName.isNotEmpty) return inviteeName;
    if (inviteeDisplayName.isNotEmpty) return inviteeDisplayName;
    return inviteeEmail.isNotEmpty ? inviteeEmail : 'User $inviteeId';
  }

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isAccepted => status.toLowerCase() == 'accepted';
  bool get isDeclined => status.toLowerCase() == 'declined';

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'declined':
        return 'Declined';
      default:
        return status.isEmpty ? 'Unknown' : status;
    }
  }

  factory ApiProjectInvitation.fromJson(Map<String, dynamic> json) {
    return ApiProjectInvitation(
      id: asString(json['id']),
      projectId: asString(json['project_id'] ?? json['projectId']),
      inviteeId: asString(json['invitee_id'] ?? json['inviteeId']),
      inviteeName: asString(json['invitee_name'] ?? json['inviteeName']),
      inviteeEmail: asString(json['invitee_email'] ?? json['inviteeEmail']),
      inviteeDisplayName: asString(
        json['invitee_display_name'] ?? json['inviteeDisplayName'],
      ),
      inviteeSkills:
          asStringList(json['invitee_skills'] ?? json['inviteeSkills']),
      inviterId: asString(json['inviter_id'] ?? json['inviterId']),
      inviterName: asString(json['inviter_name'] ?? json['inviterName']),
      status: asString(json['status'], 'pending'),
      createdAt: asString(json['created_at'] ?? json['createdAt']),
      respondedAt: asString(json['responded_at'] ?? json['respondedAt']),
    );
  }
}
