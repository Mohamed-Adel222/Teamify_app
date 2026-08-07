import 'package:flutter/material.dart';
import '../../core/theme.dart';

/// Target audience options for platform announcements.
enum AnnouncementAudience {
  allUsers,
  students,
  freelancers,
  teamOwners,
  recruiters,
  specificTeam,
}

extension AnnouncementAudienceX on AnnouncementAudience {
  String get label {
    switch (this) {
      case AnnouncementAudience.allUsers:
        return 'All Users';
      case AnnouncementAudience.students:
        return 'Students';
      case AnnouncementAudience.freelancers:
        return 'Freelancers';
      case AnnouncementAudience.teamOwners:
        return 'Team Owners';
      case AnnouncementAudience.recruiters:
        return 'Recruiters / Companies';
      case AnnouncementAudience.specificTeam:
        return 'Specific Team';
    }
  }

  IconData get icon {
    switch (this) {
      case AnnouncementAudience.allUsers:
        return Icons.groups_outlined;
      case AnnouncementAudience.students:
        return Icons.school_outlined;
      case AnnouncementAudience.freelancers:
        return Icons.work_outline;
      case AnnouncementAudience.teamOwners:
        return Icons.verified_user_outlined;
      case AnnouncementAudience.recruiters:
        return Icons.business_outlined;
      case AnnouncementAudience.specificTeam:
        return Icons.badge_outlined;
    }
  }

  /// Cohort keyword accepted by `POST /admin/notifications`.
  String get apiTarget {
    switch (this) {
      case AnnouncementAudience.students:
        return 'students';
      case AnnouncementAudience.freelancers:
        return 'freelancers';
      case AnnouncementAudience.specificTeam:
        return 'specific';
      case AnnouncementAudience.allUsers:
      case AnnouncementAudience.teamOwners:
      case AnnouncementAudience.recruiters:
        return 'all';
    }
  }

  static AnnouncementAudience fromApiTarget(String? target) {
    switch (target?.toLowerCase()) {
      case 'students':
        return AnnouncementAudience.students;
      case 'freelancers':
        return AnnouncementAudience.freelancers;
      case 'specific':
        return AnnouncementAudience.specificTeam;
      default:
        return AnnouncementAudience.allUsers;
    }
  }

  /// Cohorts the backend can actually resolve into recipients.
  static const List<AnnouncementAudience> broadcastable = [
    AnnouncementAudience.allUsers,
    AnnouncementAudience.students,
    AnnouncementAudience.freelancers,
    AnnouncementAudience.specificTeam,
  ];
}

/// Status lifecycle for admin announcements.
enum AnnouncementStatus {
  draft,
  scheduled,
  sent,
  cancelled,
}

extension AnnouncementStatusX on AnnouncementStatus {
  String get label {
    switch (this) {
      case AnnouncementStatus.draft:
        return 'Draft';
      case AnnouncementStatus.scheduled:
        return 'Scheduled';
      case AnnouncementStatus.sent:
        return 'Sent';
      case AnnouncementStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case AnnouncementStatus.draft:
        return const Color(0xFF64748B); // Slate Gray
      case AnnouncementStatus.scheduled:
        return AppColors.warning; // Amber
      case AnnouncementStatus.sent:
        return AppColors.success; // Green
      case AnnouncementStatus.cancelled:
        return AppColors.error; // Red
    }
  }

  IconData get icon {
    switch (this) {
      case AnnouncementStatus.draft:
        return Icons.edit_note_outlined;
      case AnnouncementStatus.scheduled:
        return Icons.schedule_outlined;
      case AnnouncementStatus.sent:
        return Icons.send_outlined;
      case AnnouncementStatus.cancelled:
        return Icons.block_outlined;
    }
  }
}

/// Delivery channels for platform announcements.
enum AnnouncementDeliveryType {
  inApp,
  email,
  both,
}

extension AnnouncementDeliveryTypeX on AnnouncementDeliveryType {
  String get label {
    switch (this) {
      case AnnouncementDeliveryType.inApp:
        return 'In-App Only';
      case AnnouncementDeliveryType.email:
        return 'Email Only';
      case AnnouncementDeliveryType.both:
        return 'In-App + Email';
    }
  }

  IconData get icon {
    switch (this) {
      case AnnouncementDeliveryType.inApp:
        return Icons.notifications_active_outlined;
      case AnnouncementDeliveryType.email:
        return Icons.mail_outline;
      case AnnouncementDeliveryType.both:
        return Icons.mark_email_unread_outlined;
    }
  }
}

/// Model representing an Admin Announcement.
class AdminAnnouncement {
  final String id;
  final String title;
  final String message;
  final AnnouncementAudience audience;
  final String targetTeamName;
  final bool inAppNotification;
  final bool emailNotification;
  final AnnouncementStatus status;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final int recipientCount;
  final String sentByName;

  const AdminAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    required this.audience,
    this.targetTeamName = '',
    this.inAppNotification = true,
    this.emailNotification = true,
    this.status = AnnouncementStatus.draft,
    required this.createdAt,
    this.scheduledAt,
    this.sentAt,
    this.recipientCount = 0,
    this.sentByName = '',
  });

  /// Builds a model from a `GET /admin/notifications/history` row. Every stored
  /// broadcast has already been delivered, so the status is always `sent`.
  factory AdminAnnouncement.fromBroadcast(Map<String, dynamic> json) {
    final sentAt = DateTime.tryParse('${json['sent_at'] ?? ''}')?.toLocal();
    return AdminAnnouncement(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      message: '${json['body'] ?? ''}',
      audience:
          AnnouncementAudienceX.fromApiTarget('${json['target_audience']}'),
      status: AnnouncementStatus.sent,
      createdAt: sentAt ?? DateTime.now(),
      sentAt: sentAt,
      recipientCount: (json['recipient_count'] as num?)?.toInt() ?? 0,
      sentByName: '${json['admin_name'] ?? ''}',
    );
  }

  AnnouncementDeliveryType get deliveryType {
    if (inAppNotification && emailNotification) {
      return AnnouncementDeliveryType.both;
    } else if (emailNotification) {
      return AnnouncementDeliveryType.email;
    }
    return AnnouncementDeliveryType.inApp;
  }

  AdminAnnouncement copyWith({
    String? id,
    String? title,
    String? message,
    AnnouncementAudience? audience,
    String? targetTeamName,
    bool? inAppNotification,
    bool? emailNotification,
    AnnouncementStatus? status,
    DateTime? createdAt,
    DateTime? scheduledAt,
    DateTime? sentAt,
    int? recipientCount,
    String? sentByName,
  }) {
    return AdminAnnouncement(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      audience: audience ?? this.audience,
      targetTeamName: targetTeamName ?? this.targetTeamName,
      inAppNotification: inAppNotification ?? this.inAppNotification,
      emailNotification: emailNotification ?? this.emailNotification,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      sentAt: sentAt ?? this.sentAt,
      recipientCount: recipientCount ?? this.recipientCount,
      sentByName: sentByName ?? this.sentByName,
    );
  }
}
