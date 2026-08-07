import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/localization/app_localizations.dart';
import '../../data/models/notification_preferences_model.dart';
import '../../services/app_services.dart';
import '../../widgets/widgets.dart';

/// Dedicated UI for managing Email Notification Preferences.
class EmailNotificationSettingsScreen extends StatefulWidget {
  const EmailNotificationSettingsScreen({super.key});

  @override
  State<EmailNotificationSettingsScreen> createState() =>
      _EmailNotificationSettingsScreenState();
}

class _EmailNotificationSettingsScreenState
    extends State<EmailNotificationSettingsScreen> {
  NotificationPreferences _prefs = const NotificationPreferences();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // Show the Hive copy immediately, then reconcile with the server.
    final cached = await NotificationPreferences.load();
    if (mounted) {
      setState(() {
        _prefs = cached;
        _loading = false;
      });
    }

    if (!mounted) return;
    final result = await context.read<AppServices>().notifications.getPreferences();
    if (!mounted || !result.isSuccess) return;
    setState(() => _prefs = result.data ?? cached);
  }

  Future<void> _updatePreferences(NotificationPreferences newPrefs) async {
    final previous = _prefs;
    setState(() => _prefs = newPrefs);

    final result =
        await context.read<AppServices>().notifications.savePreferences(newPrefs);
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    result.when(
      success: (saved) {
        setState(() => _prefs = saved);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification settings updated.'),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.success,
          ),
        );
      },
      failure: (error) {
        setState(() => _prefs = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save settings: $error'),
            backgroundColor: AppColors.error,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          loc?.translate('email_notifications') ?? 'Email Notifications',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Master Switch Card ──────────────────────────────────────
                TCard(
                  child: SwitchListTile(
                    value: _prefs.masterEmailEnabled,
                    activeThumbColor: AppColors.primary,
                    title: Text(
                      loc?.translate('enable_email_notifications') ??
                          'Enable Email Notifications',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    subtitle: Text(
                      loc?.translate('email_notifications_desc') ??
                          'Receive important updates and activity digests in your inbox.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    onChanged: (val) {
                      _updatePreferences(
                          _prefs.copyWith(masterEmailEnabled: val));
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // ── Notification Categories ────────────────────────────────
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _prefs.masterEmailEnabled ? 1.0 : 0.4,
                  child: AbsorbPointer(
                    absorbing: !_prefs.masterEmailEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TSectionHeader(
                            title: loc?.translate('notification_categories') ??
                                'Notification Categories'),
                        const SizedBox(height: 8),
                        TCard(
                          child: Column(
                            children: [
                              _switchTile(
                                icon: Icons.group_add_outlined,
                                title: loc?.translate('team_invitations') ??
                                    'Team Invitations',
                                subtitle: 'Email when invited to a new team or project.',
                                value: _prefs.emailTeamInvitations,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailTeamInvitations: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.check_circle_outline,
                                title: loc?.translate('invitation_responses') ??
                                    'Invitation Responses',
                                subtitle: 'Email when someone accepts or declines your invite.',
                                value: _prefs.emailInvitationResponses,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailInvitationResponses: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.assignment_ind_outlined,
                                title: loc?.translate('task_assignments') ??
                                    'Task Assignments',
                                subtitle: 'Email when a task is assigned to you.',
                                value: _prefs.emailTaskAssignments,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailTaskAssignments: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.assignment_outlined,
                                title: loc?.translate('task_updates') ??
                                    'Task Updates',
                                subtitle: 'Email when status or details change on your tasks.',
                                value: _prefs.emailTaskUpdates,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailTaskUpdates: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.alarm_outlined,
                                title: loc?.translate('deadline_reminders') ??
                                    'Deadline Reminders',
                                subtitle: 'Email reminders for upcoming task deadlines.',
                                value: _prefs.emailDeadlineReminders,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailDeadlineReminders: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.chat_bubble_outline,
                                title: loc?.translate('new_direct_messages') ??
                                    'New Direct Messages',
                                subtitle: 'Email for unread chat messages.',
                                value: _prefs.emailNewMessages,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailNewMessages: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.admin_panel_settings_outlined,
                                title: loc?.translate('role_permission_changes') ??
                                    'Role & Permission Changes',
                                subtitle: 'Email when your project permissions are modified.',
                                value: _prefs.emailRoleChanges,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailRoleChanges: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.person_remove_outlined,
                                title: loc?.translate('membership_changes') ??
                                    'Team Membership Changes',
                                subtitle: 'Email when members are added or removed from your project.',
                                value: _prefs.emailMembershipChanges,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailMembershipChanges: v)),
                              ),
                              _divider(theme),
                              _switchTile(
                                icon: Icons.campaign_outlined,
                                title: loc?.translate('admin_announcements') ??
                                    'Admin Announcements',
                                subtitle: 'Email for system-wide announcements.',
                                value: _prefs.emailAdminAnnouncements,
                                onChanged: (v) => _updatePreferences(
                                    _prefs.copyWith(emailAdminAnnouncements: v)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Advanced Timing & Delivery Behavior ────────────
                        TSectionHeader(
                            title: loc?.translate('delivery_and_timing') ??
                                'Delivery & Timing'),
                        const SizedBox(height: 8),
                        TCard(
                          child: Column(
                            children: [
                              _pickerTile(
                                context: context,
                                icon: Icons.timer_outlined,
                                title: 'Task Deadline Reminder',
                                subtitle: 'When to send task deadline alerts.',
                                currentValue: _taskReminderLabel(_prefs.taskReminderTiming),
                                options: const [
                                  {'key': '3_hours', 'label': '3 hours before'},
                                  {'key': '12_hours', 'label': '12 hours before'},
                                  {'key': '24_hours', 'label': '24 hours before'},
                                  {'key': '48_hours', 'label': '48 hours before'},
                                ],
                                onSelect: (val) => _updatePreferences(
                                    _prefs.copyWith(taskReminderTiming: val)),
                              ),
                              _divider(theme),
                              _pickerTile(
                                context: context,
                                icon: Icons.mark_chat_unread_outlined,
                                title: 'Chat Email Behavior',
                                subtitle: 'When to trigger chat notification emails.',
                                currentValue: _chatBehaviorLabel(_prefs.messageEmailBehavior),
                                options: const [
                                  {'key': 'never', 'label': 'Never'},
                                  {'key': 'offline', 'label': 'When offline'},
                                  {
                                    'key': '15_min_inactivity',
                                    'label': 'After 15 min of inactivity'
                                  },
                                  {'key': 'every_message', 'label': 'Every new message'},
                                ],
                                onSelect: (val) => _updatePreferences(
                                    _prefs.copyWith(messageEmailBehavior: val)),
                              ),
                              _divider(theme),
                              _pickerTile(
                                context: context,
                                icon: Icons.mark_email_read_outlined,
                                title: 'General Delivery Frequency',
                                subtitle: 'How often email digests are dispatched.',
                                currentValue: _frequencyLabel(_prefs.deliveryFrequency),
                                options: const [
                                  {'key': 'instant', 'label': 'Instant Notifications'},
                                  {'key': 'daily_digest', 'label': 'Daily Digest'},
                                  {'key': 'weekly_digest', 'label': 'Weekly Digest'},
                                ],
                                onSelect: (val) => _updatePreferences(
                                    _prefs.copyWith(deliveryFrequency: val)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      ),
      value: value,
      activeThumbColor: AppColors.primary,
      onChanged: onChanged,
    );
  }

  Widget _pickerTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String currentValue,
    required List<Map<String, String>> options,
    required ValueChanged<String> onSelect,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentValue,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textSecondary),
        ],
      ),
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                ...options.map(
                  (opt) => ListTile(
                    title: Text(opt['label']!),
                    trailing: currentValue == opt['label']
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      onSelect(opt['key']!);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _divider(ThemeData theme) =>
      Divider(height: 1, color: theme.dividerColor);

  String _taskReminderLabel(String key) {
    switch (key) {
      case '3_hours':
        return '3 hours before';
      case '12_hours':
        return '12 hours before';
      case '48_hours':
        return '48 hours before';
      default:
        return '24 hours before';
    }
  }

  String _chatBehaviorLabel(String key) {
    switch (key) {
      case 'never':
        return 'Never';
      case '15_min_inactivity':
        return 'After 15 min';
      case 'every_message':
        return 'Every new message';
      default:
        return 'When offline';
    }
  }

  String _frequencyLabel(String key) {
    switch (key) {
      case 'daily_digest':
        return 'Daily Digest';
      case 'weekly_digest':
        return 'Weekly Digest';
      default:
        return 'Instant Notifications';
    }
  }
}
