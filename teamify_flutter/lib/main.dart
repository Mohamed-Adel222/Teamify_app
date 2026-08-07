import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'config/app_config.dart';
import 'core/theme.dart';
import 'core/theme_controller.dart';
import 'core/localization/app_localizations.dart';
import 'core/routes.dart';
import 'core/auth/oauth_redirect_capture.dart';
import 'core/cache/cache_manager.dart';
import 'core/network/websocket_manager.dart';
import 'core/session/session_controller.dart';
import 'core/session/app_lifecycle_manager.dart';
import 'core/session/disposable_registry.dart';
import 'core/offline/offline_manager.dart';
import 'data/repositories/app_repositories.dart';
import 'data/models/api_user.dart';
import 'services/app_services.dart';

import 'screens/auth/auth_screens.dart';
import 'screens/auth/oauth_profile_setup_screen.dart';
import 'screens/home/home_screens.dart';
import 'screens/home/new_user_home_screen.dart';
import 'screens/notifications/notification_details_screen.dart';
import 'screens/features/feature_screens.dart';
import 'screens/project/project_screens.dart';
import 'screens/chat/chat_screens.dart';
import 'screens/ai/ai_screens.dart';
import 'screens/profile/profile_screens.dart';
import 'screens/profile/email_notification_settings_screen.dart';
import 'screens/resume/resume_screens.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/mentor/mentor_screens.dart';
import 'screens/team/team_screens.dart';
import 'screens/meeting/meeting_screens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Infrastructure ──────────────────────────────────────────────────────
  final cache = CacheManager();
  await cache.init();
  await stashOAuthRedirectIfPresent(cache);

  final repositories = AppRepositories();
  final apiClient = repositories.apiClient;

  final session = SessionController(repositories.auth);
  apiClient.onAuthFailure = session.forceUnauthenticated;

  // ── Offline Manager ──────────────────────────────────────────────────
  // Created BEFORE AppServices so every service shares the same queue.
  final offline = OfflineManager(
    cache: cache,
    apiClient: apiClient,
  );
  offline.init();
  globalDisposableRegistry.register(offline);

  // ── WebSocket ─────────────────────────────────────────────────────────
  // Created BEFORE AppServices so NotificationService can subscribe to events.
  final ws = WebSocketManager(repositories.tokenStorage);

  // ── Service layer ──────────────────────────────────────────────────────
  final services = AppServices(
    repos: repositories,
    session: session,
    cache: cache,
    offlineManager: offline,
    ws: ws,
  );

  // Restore session, then connect WebSocket if authenticated (non-demo mode)
  await session.restoreSession();
  if (!AppConfig.isDemoMode && session.isAuthenticated) {
    await ws.connect();
  }

  // Listen for session changes to connect/disconnect WebSocket automatically
  session.addListener(() {
    if (!AppConfig.isDemoMode) {
      if (session.isAuthenticated && !ws.isConnected) {
        ws.connect();
      } else if (!session.isAuthenticated && ws.isConnected) {
        ws.disconnect();
        offline.clearAll();
      }
    }
  });
  globalDisposableRegistry.register(ws);

  // ── Lifecycle Manager ─────────────────────────────────────────────────
  final lifecycle = AppLifecycleManager(wsManager: ws, offlineManager: offline);
  lifecycle.init();
  globalDisposableRegistry.register(lifecycle);

  final themeController = ThemeController();
  await themeController.load();

  runApp(
    MultiProvider(
      providers: [
        Provider<AppRepositories>.value(value: repositories),
        Provider<AppServices>.value(value: services),
        Provider<CacheManager>.value(value: cache),
        Provider<WebSocketManager>.value(value: ws),
        Provider<OfflineManager>.value(value: offline),
        ChangeNotifierProvider<SessionController>.value(value: session),
        ChangeNotifierProvider<ThemeController>.value(value: themeController),
      ],
      child: const TeamifyApp(),
    ),
  );
}

class TeamifyApp extends StatelessWidget {
  const TeamifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeController>().themeMode;
    Widget protected(Widget child) => ProtectedRoute(child: child);
    Widget adminOnly(Widget child) => protected(AdminRoute(child: child));

    return MaterialApp(
      title: 'Teamify',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: const Locale('en'),
      supportedLocales: const [Locale('en')],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: R.splash,
      routes: {
        // ── Auth ──────────────────────────────────────────────────────────────
        R.splash: (_) => const SplashScreen(),
        R.onboarding: (_) => const OnboardingScreen(),
        R.roleSelection: (_) => const RoleSelectionScreen(),
        R.login: (_) => const LoginScreen(),
        R.signupAdmin: (_) => const AdminSignupScreen(),
        R.signupFreelancer: (_) => const FreelancerSignupScreen(),
        R.signupStudent: (_) => const StudentSignupScreen(),
        R.verifyEmail: (_) => const VerifyEmailScreen(),
        R.forgotPassword: (_) => const ForgotPasswordScreen(),
        R.otpVerification: (_) => const OTPVerificationScreen(),
        R.createNewPassword: (_) => const CreateNewPasswordScreen(),
        R.confirmationAdmin: (_) => const ConfirmationAdminScreen(),
        R.confirmationFreelancer: (_) => const ConfirmationFreelancerScreen(),
        R.confirmationStudent: (_) => const ConfirmationStudentScreen(),
        R.oauthProfileSetup: (_) => protected(const OAuthProfileSetupScreen()),

        // ── Home ─────────────────────────────────────────────────────────────
        R.freelancerHome: (_) => protected(const FreelancerHomeScreen()),
        R.studentHome: (_) => protected(const StudentHomeScreen()),
        R.adminHome: (_) => protected(const AdminDashboardScreen()),
        R.newUserHome: (_) => const NewUserHomeScreen(),
        R.search: (_) => protected(const SearchScreen()),
        R.completeProfile: (_) => protected(const CompleteProfileScreen()),
        R.teammateMatching: (_) => protected(const AITeammateMatchingScreen()),
        R.riskPredictor: (_) => protected(const ProjectRiskPredictorScreen()),
        R.chatEmotion: (_) => protected(const ChatEmotionScreen()),
        R.meetingTranscription: (_) =>
            protected(const MeetingTranscriptionScreen()),
        R.fileHistory: (_) => protected(const FileVersionHistoryScreen()),
        R.notifications: (_) => protected(const NotificationsScreen()),
        R.notificationDetails: (_) =>
            protected(const NotificationDetailsScreen()),
        R.settings: (_) => protected(const SettingsScreen()),
        R.privacyPolicy: (_) => protected(const PrivacyPolicyScreen()),
        R.addUser: (_) => adminOnly(const AddUserScreen()),
        R.mentorMain: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final tab = args is Map ? (args['tab'] as int?) ?? 0 : 0;
          return protected(MentorMainScreen(initialTab: tab));
        },
        R.addTask: (_) => protected(const AddTaskScreen()),

        // ── Project ───────────────────────────────────────────────────────────
        R.projectsList: (_) => protected(const ProjectsListScreen()),
        // Web bookmark / legacy hash alias
        '/projects_list': (_) => protected(const ProjectsListScreen()),
        R.projectDetails: (_) => protected(const ProjectDetailsScreen()),
        R.addProject: (_) => protected(const AddProjectScreen()),

        // ── Chat ─────────────────────────────────────────────────────────────
        R.chatList: (_) => protected(const ChatListScreen()),
        R.groupChat: (_) => protected(const GroupChatScreen()),
        R.directChat: (_) => protected(const DirectChatScreen()),
        R.chatSummary: (_) => protected(const ChatSummaryScreen()),
        R.pinnedMessages: (_) => protected(const PinnedMessagesScreen()),
        R.smartQA: (_) => protected(const SmartQAScreen()),
        R.fileSharing: (_) => protected(const FileSharingScreen()),
        R.fileIntegrity: (_) => protected(const FileIntegrityScreen()),
        R.meeting: (_) => protected(const MeetingsListScreen()),

        // ── AI ────────────────────────────────────────────────────────────────
        R.aiHub: (_) => protected(const AIHubScreen()),
        R.smartTodo: (_) => protected(const SmartTodoScreen()),
        R.aiTaskAllocation: (_) => protected(const AITaskAllocationScreen()),
        R.aiSuggestedResult: (_) => protected(const AISuggestedResultScreen()),
        R.aiExplanation: (_) => protected(const AIExplanationScreen()),
        R.aiPriority: (_) => protected(const AIPriorityScreen()),
        R.aiDeadline: (_) => protected(const AIDeadlineScreen()),
        R.pomodoro: (_) => protected(const PomodoroScreen()),
        R.aiInsights: (_) => protected(const AIInsightsScreen()),
        R.aiMentor: (_) => protected(const AIMentorScreen()),
        R.aiMentorChat: (_) => protected(const CareerMentorChatScreen()),
        R.teamRecommendation: (_) =>
            protected(const TeamRecommendationScreen()),
        R.recommendedCourses: (_) =>
            protected(const RecommendedCoursesScreen()),
        R.skills: (_) => protected(const SkillsScreen()),

        // ── Profile ───────────────────────────────────────────────────────────
        R.freelancerProfile: (_) => protected(const FreelancerProfileScreen()),
        R.studentProfile: (_) => protected(const StudentProfileScreen()),
        R.adminProfile: (_) => protected(const AdminProfileScreen()),
        R.editProfile: (_) => protected(const EditProfileScreen()),
        R.completedProjects: (_) => protected(const CompletedProjectsScreen()),
        R.ratings: (_) => protected(const RatingsScreen()),
        R.performance: (_) => protected(const PerformanceScreen()),
        R.emailNotificationSettings: (_) =>
            protected(const EmailNotificationSettingsScreen()),

        // ── Resume ────────────────────────────────────────────────────────────
        R.resumeCVStart: (_) => protected(const ResumeCVStartScreen()),
        R.resumeBuilder: (_) => protected(const ResumeBuilderScreen()),
        R.resumePreview: (_) => protected(const ResumePreviewScreen()),
        R.resumeEditContent: (_) => protected(const ResumeEditContentScreen()),
        R.resumeCustomize: (_) => protected(const ResumeCustomizeScreen()),
        R.resumeExportSuccess: (_) =>
            protected(const ResumeExportSuccessScreen()),

        // ── Admin / Security ──────────────────────────────────────────────────
        R.adminDashboard: (_) => adminOnly(const AdminDashboardScreen()),
        R.adminProjects: (_) => adminOnly(const AdminProjectsScreen()),
        R.adminTasks: (_) => adminOnly(const AdminTasksScreen()),
        R.adminAi: (_) => adminOnly(const AdminAiScreen()),
        R.adminDisputes: (_) => adminOnly(const AdminDisputesScreen()),
        R.adminNotifications: (_) =>
            adminOnly(const AdminNotificationsScreen()),
        R.adminFiles: (_) => adminOnly(const AdminFilesScreen()),
        R.adminLogs: (_) => adminOnly(const AdminLogsScreen()),
        R.adminSecurity: (_) => adminOnly(const AdminSecurityScreen()),
        R.adminSettings: (_) => adminOnly(const AdminSettingsScreen()),
        R.adminLeaderboard: (_) => adminOnly(const AdminLeaderboardScreen()),

        R.adminUsers: (_) => adminOnly(const AdminUsersScreen()),
        R.adminUserDetails: (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          return adminOnly(
            UserDetailsAdminScreen(
              initialUser: args is ApiUser ? args : null,
            ),
          );
        },
        R.adminRoles: (_) => adminOnly(const AdminRolesScreen()),
        R.editRolePermissions: (_) =>
            adminOnly(const EditRolePermissionsScreen()),
        R.securityChecklist: (_) => adminOnly(const SecurityChecklistScreen()),
        R.loginLogs: (_) => adminOnly(const LoginLogsScreen()),
        R.securityAlerts: (_) => adminOnly(const SecurityAlertsScreen()),
        R.alertDetails: (_) => adminOnly(const AlertDetailsScreen()),
        R.securityMonitor: (_) => adminOnly(const AdminSecurityScreen()),
        R.rateLimiting: (_) => adminOnly(const RateLimitingScreen()),
        R.encryptionStatus: (_) => adminOnly(const EncryptionStatusScreen()),

        R.analyst: (_) => adminOnly(const AnalystScreen()),
        R.securityFiles: (_) => adminOnly(const SecurityFilesScreen()),
        R.securityCenter: (_) => adminOnly(const SecurityCenterScreen()),
        R.securityOverview: (_) => adminOnly(const SecurityOverviewScreen()),
        R.forceLogout: (_) => adminOnly(const ForceLogoutScreen()),
        R.logoutAllDevices: (_) => adminOnly(const LogoutAllDevicesScreen()),
        R.reviewActivity: (_) => adminOnly(const ReviewActivityScreen()),
        R.askAI: (_) => adminOnly(const AskAIScreen()),
        R.adminAnnouncements: (_) =>
            adminOnly(const AdminAnnouncementsScreen()),
        R.adminAnnouncementsCreate: (_) =>
            adminOnly(const CreateAnnouncementScreen()),
        R.adminAnnouncementsPreview: (_) =>
            adminOnly(const AnnouncementPreviewScreen()),
        R.teamsList: (_) => protected(const TeamsListScreen()),
        R.membersList: (_) => protected(const MembersListScreen()),
      },
    );
  }
}

class ProtectedRoute extends StatelessWidget {
  final Widget child;

  const ProtectedRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.isDemoMode) {
      return child;
    }
    final session = context.watch<SessionController>();
    if (session.status == SessionStatus.unknown &&
        session.currentUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!session.isAuthenticated) {
      Future.microtask(() {
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
              context, R.roleSelection, (_) => false);
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return child;
  }
}

/// Blocks non-admin users from admin-only security screens.
class AdminRoute extends StatelessWidget {
  final Widget child;

  const AdminRoute({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppConfig.isDemoMode) {
      return child;
    }
    final session = context.watch<SessionController>();
    final user = session.currentUser;
    if (user?.isAdmin != true) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text('Access denied'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 48, color: AppColors.textSecondary),
                const SizedBox(height: 16),
                Text(
                  'Security Center is available for administrators only.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Go back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return child;
  }
}
