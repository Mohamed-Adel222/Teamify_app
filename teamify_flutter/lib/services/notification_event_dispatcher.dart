import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../data/models/api_misc.dart';
import '../data/models/notification_preferences_model.dart';
import '../data/demo/demo_notifications_data.dart';

/// Local notification simulator used only in demo mode. In production the
/// backend emits the real notification for each of these events, so this is a
/// no-op to avoid duplicating them client-side.
class NotificationEventDispatcher {
  /// Trigger a notification event and simulate email scheduling according to user preferences.
  static Future<void> triggerEvent({
    required BuildContext context,
    required NotificationType type,
    required String title,
    required String body,
    String entityType = '',
    String entityId = '',
    String recipientEmail = '',
  }) async {
    if (!AppConfig.isDemoMode) return;

    final prefs = await NotificationPreferences.load();

    // Determine if email delivery is enabled for this category
    bool shouldSendEmail = prefs.masterEmailEnabled;
    if (shouldSendEmail) {
      switch (type) {
        case NotificationType.teamInvitation:
          shouldSendEmail = prefs.emailTeamInvitations;
          break;
        case NotificationType.invitationAccepted:
        case NotificationType.invitationRejected:
          shouldSendEmail = prefs.emailInvitationResponses;
          break;
        case NotificationType.taskAssigned:
          shouldSendEmail = prefs.emailTaskAssignments;
          break;
        case NotificationType.taskUpdated:
          shouldSendEmail = prefs.emailTaskUpdates;
          break;
        case NotificationType.deadlineReminder:
          shouldSendEmail = prefs.emailDeadlineReminders;
          break;
        case NotificationType.directMessage:
        case NotificationType.chatMention:
          shouldSendEmail = prefs.emailNewMessages;
          break;
        case NotificationType.roleChanged:
          shouldSendEmail = prefs.emailRoleChanges;
          break;
        case NotificationType.memberRemoved:
          shouldSendEmail = prefs.emailMembershipChanges;
          break;
        case NotificationType.adminAnnouncement:
          shouldSendEmail = prefs.emailAdminAnnouncements;
          break;
        case NotificationType.systemNotification:
          shouldSendEmail = true;
          break;
      }
    }

    final newNotif = NotificationViewModel(
      emailDelivered: shouldSendEmail,
      apiNotification: ApiNotification(
        id: 'notif_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
        isRead: false,
        createdAt: 'Just now',
        type: type.rawValue,
        entityType: entityType,
        entityId: entityId,
      ),
    );

    // Push to global mock dataset for local Demo Mode simulation
    demoNotificationsData.insert(0, newNotif);

    if (shouldSendEmail) {
      debugPrint(
          '[EMAIL SCHEDULER] Scheduled "$title" email to ${recipientEmail.isNotEmpty ? recipientEmail : "user"} (${prefs.deliveryFrequency}).');
    }
  }
}
