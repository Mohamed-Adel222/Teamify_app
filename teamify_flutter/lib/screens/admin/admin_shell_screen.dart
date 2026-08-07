import 'package:flutter/material.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme.dart';
import 'admin_dashboard_screen.dart';
import 'admin_users_screen.dart';
import 'admin_projects_screen.dart';
import 'admin_tasks_screen.dart';
import 'admin_ai_screen.dart';
import 'admin_disputes_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_files_screen.dart';
import 'admin_logs_screen.dart';
import 'admin_security_screen.dart';
import 'admin_settings_screen.dart';
import 'admin_analytics_screen.dart';
import 'admin_leaderboard_screen.dart';

/// Unified admin navigation shell linking all API-backed admin screens.
class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  late int _index;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.people_outline, label: 'Users'),
    (icon: Icons.folder_outlined, label: 'Projects'),
    (icon: Icons.task_alt_outlined, label: 'Tasks'),
    (icon: Icons.smart_toy_outlined, label: 'AI Monitor'),
    (icon: Icons.gavel_outlined, label: 'Disputes'),
    (icon: Icons.campaign_outlined, label: 'Broadcasts'),
    (icon: Icons.insert_drive_file_outlined, label: 'Files'),
    (icon: Icons.receipt_long_outlined, label: 'Audit Logs'),
    (icon: Icons.analytics_outlined, label: 'Analytics'),
    (icon: Icons.leaderboard_outlined, label: 'Leaderboard'),
    (icon: Icons.security_outlined, label: 'Security'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ];

  late final List<Widget> _screens = const [
    AdminDashboardScreen(),
    AdminUsersScreen(),
    AdminProjectsScreen(),
    AdminTasksScreen(),
    AdminAiScreen(),
    AdminDisputesScreen(),
    AdminNotificationsScreen(),
    AdminFilesScreen(),
    AdminLogsScreen(),
    AdminAnalyticsScreen(),
    AdminLeaderboardScreen(),
    AdminSecurityScreen(),
    AdminSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _screens.length - 1);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out'),
        content:
            const Text('Are you sure you want to sign out of the admin panel?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await SessionController.performAppLogout(context);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_destinations[_index].label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: wide
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
      ),
      drawer: wide ? null : _buildDrawer(),
      body: Row(
        children: [
          if (wide) _buildRail(),
          Expanded(child: _screens[_index]),
        ],
      ),
    );
  }

  Widget _buildRail() {
    return NavigationRail(
      selectedIndex: _index,
      extended: true,
      minExtendedWidth: 180,
      onDestinationSelected: (i) => setState(() => _index = i),
      labelType: NavigationRailLabelType.none,
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(
              icon: const Icon(Icons.logout, color: AppColors.error),
              tooltip: 'Log out',
              onPressed: _logout,
            ),
          ),
        ),
      ),
      destinations: _destinations
          .map((d) => NavigationRailDestination(
                icon: Icon(d.icon),
                label: Text(d.label),
              ))
          .toList(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: AppColors.primaryDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.white, size: 36),
                SizedBox(height: 8),
                Text('Teamify Admin',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18)),
              ],
            ),
          ),
          ...List.generate(_destinations.length, (i) {
            final d = _destinations[i];
            return ListTile(
              leading:
                  Icon(d.icon, color: _index == i ? AppColors.primary : null),
              title: Text(d.label,
                  style: TextStyle(
                      fontWeight:
                          _index == i ? FontWeight.bold : FontWeight.normal)),
              selected: _index == i,
              onTap: () {
                setState(() => _index = i);
                Navigator.pop(context);
              },
            );
          }),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.error),
            title: const Text('Log out',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _logout();
            },
          ),
        ],
      ),
    );
  }
}
