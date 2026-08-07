import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centralized localization dictionary for Teamify (English-Only).
class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const Map<String, String> _englishValues = {
    // General
    'language_settings': 'Language Settings',
    'english': 'English',
    'choose_language': 'Choose Language',
    'save_apply': 'Apply Language',
    'saving': 'Saving…',
    'settings': 'Settings',
    'back': 'Back',
    'language_set_to': 'Language set to ',
    'cancel': 'Cancel',
    'ok': 'OK',
    'error': 'Error',
    'success': 'Success',
    'yes': 'Yes',
    'no': 'No',
    'save': 'Save',

    // Auth & Role Selection
    'sign_in': 'Sign In',
    'sign_up': 'Sign Up',
    'login': 'Login',
    'register': 'Register',
    'email': 'Email Address',
    'password': 'Password',
    'confirm_password': 'Confirm Password',
    'forgot_password': 'Forgot Password?',
    'continue': 'Continue',
    'choose_role': 'Choose your account role',
    'dont_have_account': "Don't have an account?",
    'already_have_account': 'Already have an account?',
    'role_student': 'Student',
    'role_freelancer': 'Freelancer',
    'role_admin': 'Admin',
    'role_employee': 'Employee',
    'role_founder': 'Startup Founder',
    'role_recruiter': 'Recruiter / Company',

    // Home & Dashboard
    'home': 'Home',
    'search': 'Search',
    'projects': 'Projects',
    'meetings': 'Meetings',
    'messages': 'Messages',
    'notifications': 'Notifications',
    'profile': 'Profile',
    'quick_actions': 'Quick Actions',
    'new_project': 'New Project',
    'new_task': 'New Task',
    'create_quickly': 'Create quickly',
    'teams': 'Teams',
    'manage_groups': 'Manage groups',
    'members': 'Members',
    'find_experts': 'Find experts',
    'ai_smart_sync': 'AI Smart Sync',
    'recent_activity': 'Recent Activity',
    'welcome_back': 'Welcome Back',
    'overview_sub': "Here's your overview for today",
    'active_projects': 'Active Projects',
    'tasks_done': 'Tasks Done',
    'in_progress': 'In progress',
    'workload_overview': 'Workload overview',
    'resume': 'Resume / CV',
    'view_all': 'View All',

    // Settings & Profile
    'edit_profile': 'Edit Profile',
    'language': 'Language',
    'email_notifications': 'Email Notifications',
    'theme': 'Appearance',
    'dark_mode': 'Dark Mode',
    'security_privacy': 'Security & Privacy',
    'account': 'Account',
    'privacy_policy': 'Privacy Policy',
    'security_center': 'Security Center',
    'logout': 'Logout',

    // Navigation
    'nav_home': 'Home',
    'nav_search': 'Search',
    'nav_projects': 'Projects',
    'nav_chat': 'Chat',
    'nav_profile': 'Profile',

    // Email Notifications & Filters
    'enable_email_notifications': 'Enable Email Notifications',
    'email_notifications_desc':
        'Receive important updates and activity digests in your inbox.',
    'notification_categories': 'Notification Categories',
    'delivery_and_timing': 'Delivery & Timing',
    'team_invitations': 'Team Invitations',
    'invitation_responses': 'Invitation Responses',
    'task_assignments': 'Task Assignments',
    'task_updates': 'Task Updates',
    'deadline_reminders': 'Deadline Reminders',
    'new_direct_messages': 'New Direct Messages',
    'role_permission_changes': 'Role & Permission Changes',
    'membership_changes': 'Team Membership Changes',
    'admin_announcements': 'Admin Announcements',
    'filter_all': 'All',
    'filter_unread': 'Unread',
    'email_sent': 'Email Sent',
    'in_app_only': 'In-App Only',
  };

  /// Translate a key into the English string.
  String translate(String key) {
    return _englishValues[key] ?? key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
