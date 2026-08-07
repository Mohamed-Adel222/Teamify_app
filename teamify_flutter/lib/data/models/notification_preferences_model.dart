import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../core/theme.dart';
import 'api_misc.dart';

/// Comprehensive notification event types across Teamify.
enum NotificationType {
  teamInvitation,
  invitationAccepted,
  invitationRejected,
  taskAssigned,
  taskUpdated,
  deadlineReminder,
  directMessage,
  chatMention,
  roleChanged,
  memberRemoved,
  adminAnnouncement,
  systemNotification,
}

extension NotificationTypeX on NotificationType {
  String get rawValue {
    switch (this) {
      case NotificationType.teamInvitation:
        return 'team_invitation';
      case NotificationType.invitationAccepted:
        return 'invitation_accepted';
      case NotificationType.invitationRejected:
        return 'invitation_rejected';
      case NotificationType.taskAssigned:
        return 'task_assigned';
      case NotificationType.taskUpdated:
        return 'task_updated';
      case NotificationType.deadlineReminder:
        return 'deadline_reminder';
      case NotificationType.directMessage:
        return 'direct_message';
      case NotificationType.chatMention:
        return 'chat_mention';
      case NotificationType.roleChanged:
        return 'role_changed';
      case NotificationType.memberRemoved:
        return 'member_removed';
      case NotificationType.adminAnnouncement:
        return 'admin_announcement';
      case NotificationType.systemNotification:
        return 'system_notification';
    }
  }

  static NotificationType fromString(String raw) {
    final clean = raw.toLowerCase().trim();
    if (clean.contains('invite') || clean.contains('invitation')) {
      if (clean.contains('accept')) return NotificationType.invitationAccepted;
      if (clean.contains('reject') || clean.contains('decline')) {
        return NotificationType.invitationRejected;
      }
      return NotificationType.teamInvitation;
    }
    if (clean.contains('task')) {
      if (clean.contains('assign')) return NotificationType.taskAssigned;
      if (clean.contains('due') ||
          clean.contains('deadline') ||
          clean.contains('reminder')) {
        return NotificationType.deadlineReminder;
      }
      return NotificationType.taskUpdated;
    }
    if (clean.contains('chat') ||
        clean.contains('message') ||
        clean.contains('mention')) {
      if (clean.contains('mention')) return NotificationType.chatMention;
      return NotificationType.directMessage;
    }
    if (clean.contains('role') || clean.contains('perm')) {
      return NotificationType.roleChanged;
    }
    if (clean.contains('remove') ||
        clean.contains('kick') ||
        clean.contains('leave')) {
      return NotificationType.memberRemoved;
    }
    if (clean.contains('announc') || clean.contains('admin')) {
      return NotificationType.adminAnnouncement;
    }
    return NotificationType.systemNotification;
  }

  String get label {
    switch (this) {
      case NotificationType.teamInvitation:
        return 'Team Invitation';
      case NotificationType.invitationAccepted:
        return 'Invitation Accepted';
      case NotificationType.invitationRejected:
        return 'Invitation Declined';
      case NotificationType.taskAssigned:
        return 'Task Assigned';
      case NotificationType.taskUpdated:
        return 'Task Updated';
      case NotificationType.deadlineReminder:
        return 'Deadline Reminder';
      case NotificationType.directMessage:
        return 'Direct Message';
      case NotificationType.chatMention:
        return 'Chat Mention';
      case NotificationType.roleChanged:
        return 'Role Changed';
      case NotificationType.memberRemoved:
        return 'Member Removed';
      case NotificationType.adminAnnouncement:
        return 'Admin Announcement';
      case NotificationType.systemNotification:
        return 'System Notification';
    }
  }

  IconData get icon {
    switch (this) {
      case NotificationType.teamInvitation:
        return Icons.group_add_outlined;
      case NotificationType.invitationAccepted:
        return Icons.check_circle_outline;
      case NotificationType.invitationRejected:
        return Icons.cancel_outlined;
      case NotificationType.taskAssigned:
        return Icons.assignment_ind_outlined;
      case NotificationType.taskUpdated:
        return Icons.assignment_outlined;
      case NotificationType.deadlineReminder:
        return Icons.alarm_outlined;
      case NotificationType.directMessage:
        return Icons.chat_bubble_outline;
      case NotificationType.chatMention:
        return Icons.alternate_email_outlined;
      case NotificationType.roleChanged:
        return Icons.admin_panel_settings_outlined;
      case NotificationType.memberRemoved:
        return Icons.person_remove_outlined;
      case NotificationType.adminAnnouncement:
        return Icons.campaign_outlined;
      case NotificationType.systemNotification:
        return Icons.notifications_outlined;
    }
  }

  Color get color {
    switch (this) {
      case NotificationType.teamInvitation:
      case NotificationType.invitationAccepted:
        return AppColors.primary;
      case NotificationType.invitationRejected:
      case NotificationType.memberRemoved:
        return AppColors.error;
      case NotificationType.taskAssigned:
      case NotificationType.taskUpdated:
        return const Color(0xFF0284C7); // Sky Blue
      case NotificationType.deadlineReminder:
        return AppColors.warning;
      case NotificationType.directMessage:
      case NotificationType.chatMention:
        return const Color(0xFF8B5CF6); // Purple
      case NotificationType.roleChanged:
      case NotificationType.adminAnnouncement:
        return const Color(0xFFD97706); // Amber
      case NotificationType.systemNotification:
        return AppColors.textSecondary;
    }
  }
}

/// Email & Notification Preferences model with Hive persistence support.
class NotificationPreferences {
  static const String _boxName = 'settings_box';
  static const String _prefKey = 'email_notification_preferences';

  final bool masterEmailEnabled;
  final bool emailTeamInvitations;
  final bool emailInvitationResponses;
  final bool emailTaskAssignments;
  final bool emailTaskUpdates;
  final bool emailDeadlineReminders;
  final bool emailNewMessages;
  final bool emailRoleChanges;
  final bool emailMembershipChanges;
  final bool emailAdminAnnouncements;
  final String
      taskReminderTiming; // '3_hours', '12_hours', '24_hours', '48_hours'
  final String
      messageEmailBehavior; // 'never', 'offline', '15_min_inactivity', 'every_message'
  final String deliveryFrequency; // 'instant', 'daily_digest', 'weekly_digest'

  const NotificationPreferences({
    this.masterEmailEnabled = true,
    this.emailTeamInvitations = true,
    this.emailInvitationResponses = true,
    this.emailTaskAssignments = true,
    this.emailTaskUpdates = false,
    this.emailDeadlineReminders = true,
    this.emailNewMessages = false,
    this.emailRoleChanges = true,
    this.emailMembershipChanges = true,
    this.emailAdminAnnouncements = true,
    this.taskReminderTiming = '24_hours',
    this.messageEmailBehavior = 'offline',
    this.deliveryFrequency = 'instant',
  });

  NotificationPreferences copyWith({
    bool? masterEmailEnabled,
    bool? emailTeamInvitations,
    bool? emailInvitationResponses,
    bool? emailTaskAssignments,
    bool? emailTaskUpdates,
    bool? emailDeadlineReminders,
    bool? emailNewMessages,
    bool? emailRoleChanges,
    bool? emailMembershipChanges,
    bool? emailAdminAnnouncements,
    String? taskReminderTiming,
    String? messageEmailBehavior,
    String? deliveryFrequency,
  }) {
    return NotificationPreferences(
      masterEmailEnabled: masterEmailEnabled ?? this.masterEmailEnabled,
      emailTeamInvitations: emailTeamInvitations ?? this.emailTeamInvitations,
      emailInvitationResponses:
          emailInvitationResponses ?? this.emailInvitationResponses,
      emailTaskAssignments: emailTaskAssignments ?? this.emailTaskAssignments,
      emailTaskUpdates: emailTaskUpdates ?? this.emailTaskUpdates,
      emailDeadlineReminders:
          emailDeadlineReminders ?? this.emailDeadlineReminders,
      emailNewMessages: emailNewMessages ?? this.emailNewMessages,
      emailRoleChanges: emailRoleChanges ?? this.emailRoleChanges,
      emailMembershipChanges:
          emailMembershipChanges ?? this.emailMembershipChanges,
      emailAdminAnnouncements:
          emailAdminAnnouncements ?? this.emailAdminAnnouncements,
      taskReminderTiming: taskReminderTiming ?? this.taskReminderTiming,
      messageEmailBehavior: messageEmailBehavior ?? this.messageEmailBehavior,
      deliveryFrequency: deliveryFrequency ?? this.deliveryFrequency,
    );
  }

  Map<String, dynamic> toJson() => {
        'masterEmailEnabled': masterEmailEnabled,
        'emailTeamInvitations': emailTeamInvitations,
        'emailInvitationResponses': emailInvitationResponses,
        'emailTaskAssignments': emailTaskAssignments,
        'emailTaskUpdates': emailTaskUpdates,
        'emailDeadlineReminders': emailDeadlineReminders,
        'emailNewMessages': emailNewMessages,
        'emailRoleChanges': emailRoleChanges,
        'emailMembershipChanges': emailMembershipChanges,
        'emailAdminAnnouncements': emailAdminAnnouncements,
        'taskReminderTiming': taskReminderTiming,
        'messageEmailBehavior': messageEmailBehavior,
        'deliveryFrequency': deliveryFrequency,
      };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      masterEmailEnabled: json['masterEmailEnabled'] as bool? ?? true,
      emailTeamInvitations: json['emailTeamInvitations'] as bool? ?? true,
      emailInvitationResponses:
          json['emailInvitationResponses'] as bool? ?? true,
      emailTaskAssignments: json['emailTaskAssignments'] as bool? ?? true,
      emailTaskUpdates: json['emailTaskUpdates'] as bool? ?? false,
      emailDeadlineReminders: json['emailDeadlineReminders'] as bool? ?? true,
      emailNewMessages: json['emailNewMessages'] as bool? ?? false,
      emailRoleChanges: json['emailRoleChanges'] as bool? ?? true,
      emailMembershipChanges: json['emailMembershipChanges'] as bool? ?? true,
      emailAdminAnnouncements: json['emailAdminAnnouncements'] as bool? ?? true,
      taskReminderTiming: json['taskReminderTiming']?.toString() ?? '24_hours',
      messageEmailBehavior:
          json['messageEmailBehavior']?.toString() ?? 'offline',
      deliveryFrequency: json['deliveryFrequency']?.toString() ?? 'instant',
    );
  }

  /// Load preferences from local storage (Hive).
  static Future<NotificationPreferences> load() async {
    try {
      Box box;
      if (Hive.isBoxOpen(_boxName)) {
        box = Hive.box(_boxName);
      } else {
        box = await Hive.openBox(_boxName);
      }
      final raw = box.get(_prefKey);
      if (raw != null && raw is Map) {
        return NotificationPreferences.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return const NotificationPreferences();
  }

  /// Save preferences to local storage (Hive).
  Future<void> save() async {
    try {
      Box box;
      if (Hive.isBoxOpen(_boxName)) {
        box = Hive.box(_boxName);
      } else {
        box = await Hive.openBox(_boxName);
      }
      await box.put(_prefKey, toJson());
    } catch (_) {}
  }
}

/// Lightweight UI View Model extending [ApiNotification] capabilities.
class NotificationViewModel {
  final ApiNotification apiNotification;
  final bool emailDelivered;
  final String? relatedProjectId;
  final String? relatedProjectName;
  final String? relatedTaskId;
  final String? relatedTaskName;
  final String? relatedTeamId;
  final String? relatedTeamName;
  final String? relatedUserName;
  final String? actionRoute;

  const NotificationViewModel({
    required this.apiNotification,
    this.emailDelivered = false,
    this.relatedProjectId,
    this.relatedProjectName,
    this.relatedTaskId,
    this.relatedTaskName,
    this.relatedTeamId,
    this.relatedTeamName,
    this.relatedUserName,
    this.actionRoute,
  });

  String get id => apiNotification.id;
  String get title => apiNotification.title;
  String get body => apiNotification.body;
  bool get isRead => apiNotification.isRead;
  String get createdAt => apiNotification.createdAt;
  String get rawType => apiNotification.type;

  NotificationType get category => NotificationTypeX.fromString(rawType);
  IconData get icon => category.icon;
  Color get color => category.color;

  NotificationViewModel copyWith({
    ApiNotification? apiNotification,
    bool? emailDelivered,
    String? relatedProjectId,
    String? relatedProjectName,
    String? relatedTaskId,
    String? relatedTaskName,
    String? relatedTeamId,
    String? relatedTeamName,
    String? relatedUserName,
    String? actionRoute,
  }) {
    return NotificationViewModel(
      apiNotification: apiNotification ?? this.apiNotification,
      emailDelivered: emailDelivered ?? this.emailDelivered,
      relatedProjectId: relatedProjectId ?? this.relatedProjectId,
      relatedProjectName: relatedProjectName ?? this.relatedProjectName,
      relatedTaskId: relatedTaskId ?? this.relatedTaskId,
      relatedTaskName: relatedTaskName ?? this.relatedTaskName,
      relatedTeamId: relatedTeamId ?? this.relatedTeamId,
      relatedTeamName: relatedTeamName ?? this.relatedTeamName,
      relatedUserName: relatedUserName ?? this.relatedUserName,
      actionRoute: actionRoute ?? this.actionRoute,
    );
  }
}
