import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../data/models/api_misc.dart';
import '../../data/models/notification_preferences_model.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

/// Screen displaying complete details for a selected notification.
class NotificationDetailsScreen extends StatefulWidget {
  const NotificationDetailsScreen({super.key});

  @override
  State<NotificationDetailsScreen> createState() =>
      _NotificationDetailsScreenState();
}

class _NotificationDetailsScreenState extends State<NotificationDetailsScreen> {
  bool _markedRead = false;

  String _actionButtonLabel(NotificationViewModel notif) {
    switch (notif.category) {
      case NotificationType.teamInvitation:
      case NotificationType.invitationAccepted:
      case NotificationType.invitationRejected:
        return 'View Invitation';
      case NotificationType.taskAssigned:
      case NotificationType.taskUpdated:
      case NotificationType.deadlineReminder:
        return 'View Task';
      case NotificationType.directMessage:
      case NotificationType.chatMention:
        return 'Open Chat';
      case NotificationType.roleChanged:
      case NotificationType.memberRemoved:
        return 'View Team';
      case NotificationType.adminAnnouncement:
        return 'View Announcement';
      default:
        return 'View Details';
    }
  }

  void _handlePrimaryAction(BuildContext context, NotificationViewModel notif) {
    if (notif.actionRoute != null && notif.actionRoute!.isNotEmpty) {
      try {
        Navigator.pushNamed(context, notif.actionRoute!);
        return;
      } catch (_) {}
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This notification has no linked workspace item.'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Marks the notification read server-side the first time it is opened.
  void _markReadOnce(NotificationViewModel notif) {
    if (_markedRead || notif.isRead) return;
    _markedRead = true;
    context.read<AppServices>().notifications.markRead(notif.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final args = ModalRoute.of(context)?.settings.arguments;
    final notif = args is NotificationViewModel
        ? args
        : args is ApiNotification
            ? NotificationViewModel(apiNotification: args)
            : null;

    if (notif == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Details')),
        body: const Center(child: Text('No notification data provided.')),
      );
    }

    _markReadOnce(notif);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Notification Details',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header Banner Card ──────────────────────────────────────────
          TCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: notif.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(notif.icon, size: 24, color: notif.color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notif.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notif.createdAt,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),

                // Full Body Message
                Text(
                  notif.body,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Status & Channel Badges Card ────────────────────────────────
          const TSectionHeader(title: 'Delivery & Read Status'),
          const SizedBox(height: 8),
          TCard(
            child: Column(
              children: [
                _infoRow(
                  icon: notif.isRead
                      ? Icons.mark_email_read_outlined
                      : Icons.mark_email_unread_outlined,
                  label: 'Read Status',
                  value: notif.isRead ? 'Read' : 'Unread',
                  valueColor:
                      notif.isRead ? AppColors.success : AppColors.warning,
                ),
                Divider(height: 1, color: theme.dividerColor),
                _infoRow(
                  icon: notif.emailDelivered
                      ? Icons.mail_outline
                      : Icons.phonelink_ring_outlined,
                  label: 'Email Dispatch',
                  value:
                      notif.emailDelivered ? 'Email Sent' : 'In-App Only',
                  valueColor: notif.emailDelivered
                      ? AppColors.success
                      : AppColors.textSecondary,
                ),
                Divider(height: 1, color: theme.dividerColor),
                _infoRow(
                  icon: Icons.category_outlined,
                  label: 'Category',
                  value: notif.category.label,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Related Entities Card (if present) ─────────────────────────
          if (notif.relatedProjectName != null ||
              notif.relatedTaskName != null ||
              notif.relatedTeamName != null ||
              notif.relatedUserName != null) ...[
            const TSectionHeader(title: 'Related Workspace Context'),
            const SizedBox(height: 8),
            TCard(
              child: Column(
                children: [
                  if (notif.relatedUserName != null) ...[
                    _infoRow(
                      icon: Icons.person_outline,
                      label: 'Related User',
                      value: notif.relatedUserName!,
                    ),
                    Divider(height: 1, color: theme.dividerColor),
                  ],
                  if (notif.relatedProjectName != null) ...[
                    _infoRow(
                      icon: Icons.folder_open_outlined,
                      label: 'Project',
                      value: notif.relatedProjectName!,
                    ),
                    Divider(height: 1, color: theme.dividerColor),
                  ],
                  if (notif.relatedTaskName != null) ...[
                    _infoRow(
                      icon: Icons.assignment_outlined,
                      label: 'Task',
                      value: notif.relatedTaskName!,
                    ),
                    Divider(height: 1, color: theme.dividerColor),
                  ],
                  if (notif.relatedTeamName != null) ...[
                    _infoRow(
                      icon: Icons.groups_outlined,
                      label: 'Team',
                      value: notif.relatedTeamName!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else ...[
            const SizedBox(height: 8),
          ],

          // ── Contextual Primary Action Button ────────────────────────────
          TButton(
            label: _actionButtonLabel(notif),
            onTap: () => _handlePrimaryAction(context, notif),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
