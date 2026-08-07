import 'package:flutter/material.dart';
import '../models/api_misc.dart';
import '../models/notification_preferences_model.dart';
import '../../core/routes.dart';

/// Mutable Demo Notifications List used for state management in Demo Mode.
final List<NotificationViewModel> demoNotificationsData = [
  NotificationViewModel(
    emailDelivered: true,
    relatedProjectId: 'proj_101',
    relatedProjectName: 'Mobile Redesign',
    relatedUserName: 'Sara Connor',
    actionRoute: R.projectsList,
    apiNotification: const ApiNotification(
      id: 'demo_notif_1',
      title: 'Project Invitation',
      body: 'Sara Connor invited you to join the "Mobile Redesign" project team.',
      isRead: false,
      createdAt: '10 min ago',
      type: 'team_invitation',
      entityType: 'project',
      entityId: 'proj_101',
    ),
  ),
  NotificationViewModel(
    emailDelivered: true,
    relatedTaskId: 'task_202',
    relatedTaskName: 'Implement Auth Flow & Tokens',
    relatedProjectName: 'Teamify Frontend',
    actionRoute: R.projectsList,
    apiNotification: const ApiNotification(
      id: 'demo_notif_2',
      title: 'New Task Assigned',
      body: 'You have been assigned to "Implement Auth Flow & Tokens" in Teamify Frontend.',
      isRead: false,
      createdAt: '1 hour ago',
      type: 'task_assigned',
      entityType: 'task',
      entityId: 'task_202',
    ),
  ),
  NotificationViewModel(
    emailDelivered: false,
    relatedTaskId: 'task_203',
    relatedTaskName: 'API Client Integration',
    actionRoute: R.projectsList,
    apiNotification: const ApiNotification(
      id: 'demo_notif_3',
      title: 'Task Deadline Approaching',
      body: 'Reminder: "API Client Integration" is due in less than 24 hours.',
      isRead: false,
      createdAt: '3 hours ago',
      type: 'deadline_reminder',
      entityType: 'task',
      entityId: 'task_203',
    ),
  ),
  NotificationViewModel(
    emailDelivered: true,
    relatedProjectId: 'proj_102',
    relatedProjectName: 'Analytics Dashboard',
    relatedUserName: 'Alexander Wright',
    actionRoute: R.projectsList,
    apiNotification: const ApiNotification(
      id: 'demo_notif_4',
      title: 'Invitation Accepted',
      body: 'Alexander Wright accepted your invitation to join "Analytics Dashboard".',
      isRead: true,
      createdAt: '5 hours ago',
      type: 'invitation_accepted',
      entityType: 'project',
      entityId: 'proj_102',
    ),
  ),
  NotificationViewModel(
    emailDelivered: true,
    relatedProjectId: 'proj_103',
    relatedProjectName: 'Teamify Web Core',
    actionRoute: R.projectsList,
    apiNotification: const ApiNotification(
      id: 'demo_notif_5',
      title: 'Role & Permissions Changed',
      body: 'Your role in "Teamify Web Core" was updated from Member to Project Admin.',
      isRead: true,
      createdAt: '1 day ago',
      type: 'role_changed',
      entityType: 'project',
      entityId: 'proj_103',
    ),
  ),
  const NotificationViewModel(
    emailDelivered: false,
    actionRoute: R.adminAnnouncements,
    apiNotification: ApiNotification(
      id: 'demo_notif_6',
      title: 'System Announcement',
      body: 'Scheduled maintenance: Teamify platform will undergo update tonight at 2:00 AM UTC.',
      isRead: true,
      createdAt: '2 days ago',
      type: 'admin_announcement',
    ),
  ),
];

/// Global store for live Demo Notifications state across the app.
class DemoNotificationStore extends ChangeNotifier {
  static final DemoNotificationStore instance = DemoNotificationStore._();
  DemoNotificationStore._();

  List<NotificationViewModel> get items => List.unmodifiable(demoNotificationsData);

  int get unreadCount => demoNotificationsData.where((n) => !n.isRead).length;

  void markAsRead(String id) {
    final idx = demoNotificationsData.indexWhere((n) => n.id == id);
    if (idx != -1 && !demoNotificationsData[idx].isRead) {
      demoNotificationsData[idx] = demoNotificationsData[idx].copyWith(
        apiNotification: demoNotificationsData[idx].apiNotification.copyWith(isRead: true),
      );
      notifyListeners();
    }
  }

  void toggleReadState(String id) {
    final idx = demoNotificationsData.indexWhere((n) => n.id == id);
    if (idx != -1) {
      final currentRead = demoNotificationsData[idx].isRead;
      demoNotificationsData[idx] = demoNotificationsData[idx].copyWith(
        apiNotification: demoNotificationsData[idx].apiNotification.copyWith(isRead: !currentRead),
      );
      notifyListeners();
    }
  }

  void markAllRead() {
    bool changed = false;
    for (int i = 0; i < demoNotificationsData.length; i++) {
      if (!demoNotificationsData[i].isRead) {
        demoNotificationsData[i] = demoNotificationsData[i].copyWith(
          apiNotification: demoNotificationsData[i].apiNotification.copyWith(isRead: true),
        );
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void deleteNotification(String id) {
    demoNotificationsData.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void addNotification(NotificationViewModel item) {
    demoNotificationsData.insert(0, item);
    notifyListeners();
  }
}
