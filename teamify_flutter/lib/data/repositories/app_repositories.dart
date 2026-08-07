import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import 'admin_repository.dart';
import 'ai_repository.dart';
import 'auth_repository.dart';
import 'chat_repository.dart';
import 'comment_repository.dart';
import 'cv_repository.dart';
import 'dispute_repository.dart';
import 'feedback_repository.dart';
import 'file_repository.dart';
import 'home_repository.dart';
import 'log_repository.dart';
import 'notification_repository.dart';
import 'project_repository.dart';
import 'rating_repository.dart';
import 'reminder_repository.dart';
import 'search_repository.dart';
import 'stats_repository.dart';
import 'task_repository.dart';
import 'university_repository.dart';
import 'user_repository.dart';

class AppRepositories {
  final TokenStorage tokenStorage;
  final ApiClient apiClient;

  late final AuthRepository auth;
  late final UserRepository users;
  late final ProjectRepository projects;
  late final TaskRepository tasks;
  late final NotificationRepository notifications;
  late final SearchRepository search;
  late final AdminRepository admin;
  late final FileRepository files;
  late final CVRepository cv;
  late final AIRepository ai;

  // ── New repositories (Phase 3–5) ─────────────────────────────────────────
  late final HomeRepository home;
  late final RatingRepository ratings;
  late final FeedbackRepository feedback;
  late final DisputeRepository disputes;
  late final ChatRepository chat;
  late final CommentRepository comments;
  late final LogRepository logs;
  late final StatsRepository stats;
  late final ReminderRepository reminders;
  late final UniversityRepository universities;

  AppRepositories._({
    required this.tokenStorage,
    required this.apiClient,
  }) {
    auth = AuthRepository(client: apiClient, tokenStorage: tokenStorage);
    users = UserRepository(apiClient);
    projects = ProjectRepository(apiClient);
    tasks = TaskRepository(apiClient);
    notifications = NotificationRepository(apiClient);
    search = SearchRepository(apiClient);
    admin = AdminRepository(apiClient);
    files = FileRepository(apiClient);
    cv = CVRepository(apiClient);
    ai = AIRepository(apiClient);

    // New
    home = HomeRepository(apiClient);
    ratings = RatingRepository(apiClient);
    feedback = FeedbackRepository(apiClient);
    disputes = DisputeRepository(apiClient);
    chat = ChatRepository(apiClient);
    comments = CommentRepository(apiClient);
    logs = LogRepository(apiClient);
    stats = StatsRepository(apiClient);
    reminders = ReminderRepository(apiClient);
    universities = UniversityRepository(apiClient);
  }

  factory AppRepositories({
    TokenStorage? tokenStorage,
    ApiClient? apiClient,
  }) {
    final storage = tokenStorage ?? TokenStorage();
    return AppRepositories._(
      tokenStorage: storage,
      apiClient: apiClient ?? ApiClient(tokenStorage: storage),
    );
  }
}
