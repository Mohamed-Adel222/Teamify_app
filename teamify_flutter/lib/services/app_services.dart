import '../core/cache/cache_manager.dart';
import '../core/network/websocket_manager.dart';
import '../core/offline/offline_manager.dart';
import '../core/session/session_controller.dart';
import '../data/repositories/app_repositories.dart';
import 'admin_service.dart';
import 'ai_service.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'cv_service.dart';
import 'dispute_service.dart';
import 'feedback_service.dart';
import 'file_service.dart';
import 'home_service.dart';
import 'log_service.dart';
import 'meeting_service.dart';
import 'notification_service.dart';
import 'project_service.dart';
import 'rating_service.dart';
import 'reminder_service.dart';
import 'search_service.dart';
import 'task_service.dart';
import 'university_service.dart';
import 'user_service.dart';

/// Central registry for all service-layer instances.
///
/// Every service receives at minimum:
///  - the relevant [AppRepositories] repository slice
///  - a shared [CacheManager] for SWR caching
///  - a shared [OfflineManager] for mutation queuing (mutating services only)
///
/// Services are accessed anywhere in the widget tree via:
///   `context.read<AppServices>().disputes.fileDispute(...)`
class AppServices {
  // ── Core auth ──────────────────────────────────────────────────────────────
  late final AuthService auth;

  // ── Data domains ───────────────────────────────────────────────────────────
  late final UserService users;
  late final ProjectService projects;
  late final TaskService tasks;
  late final FileService files;
  late final CVService cvs;
  late final AIService ai;
  late final ChatService chat;
  late final MeetingService meetings;
  late final NotificationService notifications;
  late final SearchService search;
  late final HomeService home;
  late final RatingService ratings;
  late final FeedbackService feedback;
  late final UniversityService universities;

  // ── Admin ──────────────────────────────────────────────────────────────────
  late final AdminService admin;

  // ── Previously-orphaned repositories — now fully wired ────────────────────
  late final DisputeService disputes;
  late final LogService logs;
  late final ReminderService reminders;

  /// The shared [OfflineManager] — exposed so the UI can read queue depth,
  /// trigger manual replays, or display permanent-failure banners.
  late final SessionController session;
  late final OfflineManager offline;

  AppServices({
    required AppRepositories repos,
    required this.session,
    required CacheManager cache,
    required OfflineManager offlineManager,
    WebSocketManager? ws,
  }) {
    offline = offlineManager;

    // ── Auth ──────────────────────────────────────────────────────────────
    auth = AuthService(
      repo: repos.auth,
      session: session,
      cache: cache,
    );

    // ── User & Profile ────────────────────────────────────────────────────
    users = UserService(
      repo: repos.users,
      cache: cache,
      offline: offlineManager,
    );

    // ── Projects & Tasks ──────────────────────────────────────────────────
    projects = ProjectService(
      repo: repos.projects,
      stats: repos.stats,
      cache: cache,
      offline: offlineManager,
      ws: ws,
    );

    tasks = TaskService(
      repo: repos.tasks,
      comments: repos.comments,
      cache: cache,
      offline: offlineManager,
      ws: ws,
    );

    // ── Files ─────────────────────────────────────────────────────────────
    files = FileService(repos.files, offlineManager, cache);

    // ── AI & CV ───────────────────────────────────────────────────────────
    cvs = CVService(
      repo: repos.cv,
      cache: cache,
      offlineManager: offlineManager,
    );
    ai = AIService(
      ai: repos.ai,
      cv: repos.cv,
      cache: cache,
    );

    // ── Communication ─────────────────────────────────────────────────────
    chat = ChatService(repos.chat, offlineManager, cache);
    meetings = MeetingService(repos.meetings);
    notifications = NotificationService(repos.notifications, cache,
        ws: ws, offline: offlineManager);

    // ── Search & Home ─────────────────────────────────────────────────────
    search = SearchService(repos.search);
    home = HomeService(repos.home, cache);
    notifications.linkHomeService(home);

    // ── Reference data ────────────────────────────────────────────────────
    universities = UniversityService(repos.universities);

    // ── Admin (full surface) ──────────────────────────────────────────────
    admin = AdminService(repos.admin, cache);

    // ── Ratings & Feedback ────────────────────────────────────────────────
    ratings = RatingService(repos.ratings, cache, offlineManager);
    feedback = FeedbackService(
      repo: repos.feedback,
      cache: cache,
      offline: offlineManager,
    );

    // ── Disputes (SWR + offline mutations) ───────────────────────────────
    disputes = DisputeService(
      repo: repos.disputes,
      cache: cache,
      offline: offlineManager,
    );

    // ── Logs (SWR, read-only) ─────────────────────────────────────────────
    logs = LogService(
      repo: repos.logs,
      cache: cache,
    );

    // ── Reminders (SWR, read-only, 2-min TTL) ────────────────────────────
    reminders = ReminderService(
      repo: repos.reminders,
      cache: cache,
    );
  }
}
